"""Run a Godot process with live output, hard timeout, stall watchdog and error accounting."""
from __future__ import annotations

import os
import queue
import re
import shlex
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
HEADER_RE = re.compile(r"^Godot Engine v\d")
# Engine level error records. WARNING lines are deliberately not counted.
ERROR_RE = re.compile(r"^(SCRIPT ERROR:|ERROR:|USER ERROR:|Parse Error:|CHECKER ABORTED|RUNNER ABORTED)")
PROGRESS_RE = re.compile(r"^\[\s*\d+% \]")

_ACTIVE: List["subprocess.Popen[bytes]"] = []
_HANDLERS_INSTALLED = False


def _kill_group(proc: "subprocess.Popen[bytes]", grace: float = 3.0) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, AttributeError):
        proc.terminate()
    deadline = time.time() + grace
    while proc.poll() is None and time.time() < deadline:
        time.sleep(0.05)
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, AttributeError):
            proc.kill()


def _install_signal_handlers() -> None:
    """Ctrl-C / SIGTERM on gd must not leave Godot children running (they would keep the cache busy)."""
    global _HANDLERS_INSTALLED
    if _HANDLERS_INSTALLED or threading.current_thread() is not threading.main_thread():
        return
    _HANDLERS_INSTALLED = True

    def handler(signum: int, _frame: object) -> None:
        for p in list(_ACTIVE):
            _kill_group(p, grace=1.0)
        raise SystemExit(128 + signum)

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, handler)
        except (ValueError, OSError):
            pass


@dataclass
class RunResult:
    rc: int = 0
    lines: List[str] = field(default_factory=list)
    error_lines: List[str] = field(default_factory=list)
    timed_out: bool = False
    stalled: bool = False
    elapsed: float = 0.0
    cmd: List[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.rc == 0 and not self.timed_out and not self.stalled


def run_process(
    cmd: Sequence[str],
    *,
    timeout: float,
    stall_after_error: Optional[float] = 20.0,
    echo: bool = True,
    verbose: bool = False,
    cwd: Optional[str] = None,
    env: Optional[Dict[str, str]] = None,
    drop_progress: bool = False,
    line_filter: Optional[Callable[[str], bool]] = None,
    line_map: Optional[Callable[[str], str]] = None,
    prefix: str = "",
) -> RunResult:
    """Run `cmd`, merging stderr into stdout.

    echo:        print every kept line immediately (live output).
    timeout:     hard wall-clock limit in seconds; the whole process group is killed.
    stall_after_error: once an engine error line was seen, kill the process when it produces no output
                 for this many seconds. A runtime error inside _initialize()/_ready() aborts that function
                 before quit() and Godot then idles forever; this turns the hang into a prompt failure.
    line_filter: return False to drop a line (it is still not counted as an error).
    """
    _install_signal_handlers()
    if verbose:
        print("gd: exec: " + shlex.join(str(c) for c in cmd), file=sys.stderr, flush=True)
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    start = time.time()
    try:
        proc = subprocess.Popen(
            [str(c) for c in cmd], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            cwd=cwd, env=full_env, start_new_session=True, bufsize=0,
        )
    except OSError as exc:
        return RunResult(rc=127, lines=[f"gd: cannot execute {cmd[0]}: {exc}"], error_lines=[str(exc)], cmd=list(map(str, cmd)))
    _ACTIVE.append(proc)
    q: "queue.Queue[Optional[bytes]]" = queue.Queue()

    def reader() -> None:
        assert proc.stdout is not None
        for raw in iter(proc.stdout.readline, b""):
            q.put(raw)
        q.put(None)

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    res = RunResult(cmd=list(map(str, cmd)))
    last_output = time.time()
    saw_error = False
    skip_blank_after_header = False
    finished_reading = False
    try:
        while not finished_reading:
            now = time.time()
            if now - start > timeout:
                res.timed_out = True
                break
            if saw_error and stall_after_error and now - last_output > stall_after_error:
                res.stalled = True
                break
            try:
                raw = q.get(timeout=0.25)
            except queue.Empty:
                continue
            if raw is None:
                finished_reading = True
                break
            last_output = time.time()
            line = ANSI_RE.sub("", raw.decode("utf-8", errors="replace")).rstrip("\r\n")
            if HEADER_RE.match(line):
                skip_blank_after_header = True
                continue
            if skip_blank_after_header:
                skip_blank_after_header = False
                if not line.strip():
                    continue
            if drop_progress and PROGRESS_RE.match(line):
                continue
            if line_filter is not None and not line_filter(line):
                continue
            if line_map is not None:
                line = line_map(line)
            res.lines.append(line)
            if ERROR_RE.match(line):
                saw_error = True
                res.error_lines.append(line)
            if echo:
                try:
                    print(prefix + line, flush=True)
                except BrokenPipeError:
                    # the consumer (e.g. `| head`) went away: stop Godot and leave quietly
                    _kill_group(proc, grace=1.0)
                    try:
                        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())  # silence the exit-time flush
                    except OSError:
                        pass
                    raise SystemExit(141)
    finally:
        if proc.poll() is None:
            _kill_group(proc)
        try:
            _ACTIVE.remove(proc)
        except ValueError:
            pass
    proc.wait()
    t.join(timeout=2.0)
    res.rc = proc.returncode if not (res.timed_out or res.stalled) else 124
    res.elapsed = time.time() - start
    if res.rc < 0 and not (res.timed_out or res.stalled):
        try:
            name = signal.Signals(-res.rc).name
        except ValueError:
            name = str(-res.rc)
        msg = f"gd: Godot died from signal {name} (crash?); last output above"
        res.lines.append(msg)
        print(msg, file=sys.stderr, flush=True)
    if res.timed_out:
        msg = f"gd: TIMEOUT after {timeout:.0f}s - process killed (raise it with --timeout)"
        res.lines.append(msg)
        print(msg, file=sys.stderr, flush=True)
    elif res.stalled:
        msg = (f"gd: STALLED - an engine error was printed and then no output for {stall_after_error:.0f}s; process killed. "
               "A runtime error inside _initialize()/_ready() aborts the function before quit() is reached, so Godot "
               "idles forever. Fix the error above (or pass --stall 0 to disable this watchdog).")
        res.lines.append(msg)
        print(msg, file=sys.stderr, flush=True)
    return res
