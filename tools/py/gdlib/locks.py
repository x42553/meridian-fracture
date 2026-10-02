"""Fair reader/writer lock built from two flock(2) files.

Why: many agents run Godot on the same game/ project. `godot --import` rewrites game/.godot/
(including global_script_class_cache.cfg, needed to resolve class_name globals) and must never overlap
with any other Godot process that reads it. So:

  * every normal command holds the lock SHARED for its whole run (any number in parallel),
  * an import holds it EXCLUSIVE (waits for the readers to drain, blocks new ones).

Plain flock has no writer priority, so a steady stream of readers could starve an importer forever.
A second "gate" file fixes that (classic turnstile): everybody takes the gate first, then the main lock,
then releases the gate. An importer that is waiting for readers to drain holds the gate, so no new reader
can slip in. Lock order is always gate -> main and no holder ever waits for the gate while holding main,
therefore no deadlock. A process must never try to upgrade shared -> exclusive: it releases and
re-acquires (see commands.ready_shared), because two upgraders would deadlock each other.

flock locks die with the process, so a killed gd can never leave a stale lock behind.
On platforms without fcntl (Windows CI) the lock degrades to a no-op: CI runs one gd at a time.
"""
from __future__ import annotations

import contextlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, Iterator, List, Optional

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows
    fcntl = None  # type: ignore[assignment]

WAIT_NOTICE_AFTER_S = 1.0


def _trace(event: str, kind: str, name: str) -> None:
    path = os.environ.get("GD_TRACE_FILE")
    if not path:
        return
    line = f"{time.monotonic_ns()} {os.getpid()} {name} {kind} {event}\n".encode()
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, line)
    finally:
        os.close(fd)


def _alive(pid: int) -> bool:
    if sys.platform == "win32":
        # os.kill(pid, 0) would TERMINATE the process on Windows; ask the kernel instead.
        try:
            import ctypes
            handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
            if not handle:
                return False
            code = ctypes.c_ulong()
            ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
            ctypes.windll.kernel32.CloseHandle(handle)
            return bool(ok) and code.value == 259  # STILL_ACTIVE
        except Exception:  # noqa: BLE001 - liveness is best effort
            return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def list_holders(directory: Path) -> List[Dict[str, object]]:
    """Live gd processes holding (or about to hold) any project lock, oldest first. Stale records are pruned."""
    out: List[Dict[str, object]] = []
    for d in sorted(directory.glob("*.holders")):
        for f in d.glob("*.json"):
            try:
                rec = json.loads(f.read_text())
                if _alive(int(rec["pid"])):
                    rec["lock"] = d.name[: -len(".holders")]
                    out.append(rec)
                else:
                    f.unlink()
            except (OSError, ValueError, KeyError):
                continue
    return sorted(out, key=lambda r: float(r.get("since", 0)))


class RWLock:
    def __init__(self, directory: Path, name: str = "gd") -> None:
        self.name = name
        self.dir = directory
        self.main_path = directory / f"{name}.lock"
        self.gate_path = directory / f"{name}.gate"
        self.holders_dir = directory / f"{name}.holders"

    # -- low level ---------------------------------------------------------------------------
    def _open(self, path: Path) -> int:
        self.dir.mkdir(parents=True, exist_ok=True)
        return os.open(str(path), os.O_RDWR | os.O_CREAT, 0o644)

    def _flock(self, fd: int, mode: int, what: str) -> None:
        if fcntl is None:
            return
        try:
            fcntl.flock(fd, mode | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            pass
        holder = self._holder_text()
        print(f"gd: waiting for the project lock ({what}){holder} ...", file=sys.stderr, flush=True)
        fcntl.flock(fd, mode)  # blocks; SIGINT/SIGTERM still interrupt it

    def _holder_text(self) -> str:
        recs = [r for r in list_holders(self.dir) if r["lock"] == self.name and r["pid"] != os.getpid()]
        if not recs:
            return ""
        now = time.time()
        shown = ", ".join(f"pid {r['pid']} `gd {r.get('cmd', '?')}` ({r['kind']}, {now - float(r.get('since', now)):.0f}s)" for r in recs[:4])
        return f"; running: {shown}" + (f" (+{len(recs) - 4} more)" if len(recs) > 4 else "") + " - `tools/gd ps` lists them"

    def _register(self, kind: str) -> Optional[Path]:
        try:
            self.holders_dir.mkdir(parents=True, exist_ok=True)
            path = self.holders_dir / f"{os.getpid()}-{kind}-{time.monotonic_ns()}.json"
            path.write_text(json.dumps({"pid": os.getpid(), "kind": kind, "cmd": " ".join(sys.argv[1:6]), "since": time.time()}))
            return path
        except OSError:
            return None

    @staticmethod
    def _unregister(path: Optional[Path]) -> None:
        if path is not None:
            try:
                path.unlink()
            except OSError:
                pass

    @staticmethod
    def _unlock(fd: int) -> None:
        if fcntl is not None:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass

    # -- public ------------------------------------------------------------------------------
    @contextlib.contextmanager
    def shared(self) -> Iterator[None]:
        gate = self._open(self.gate_path)
        main = self._open(self.main_path)
        try:
            if fcntl is not None:
                self._flock(gate, fcntl.LOCK_EX, "shared, queued behind an import")
                try:
                    self._flock(main, fcntl.LOCK_SH, "shared")
                finally:
                    self._unlock(gate)
            record = self._register("shared")
            _trace("acquire", "shared", self.name)
            try:
                yield
            finally:
                _trace("release", "shared", self.name)
                self._unregister(record)
        finally:
            self._unlock(main)
            os.close(main)
            os.close(gate)

    @contextlib.contextmanager
    def exclusive(self, label: str = "") -> Iterator[None]:
        gate = self._open(self.gate_path)
        main = self._open(self.main_path)
        try:
            if fcntl is not None:
                self._flock(gate, fcntl.LOCK_EX, "exclusive")
                try:
                    self._flock(main, fcntl.LOCK_EX, "exclusive, waiting for running commands")
                finally:
                    self._unlock(gate)
            record = self._register("exclusive")
            _trace("acquire", "exclusive", self.name)
            try:
                yield
            finally:
                _trace("release", "exclusive", self.name)
                self._unregister(record)
        finally:
            self._unlock(main)
            os.close(main)
            os.close(gate)
