#!/usr/bin/env python3
"""App-level two-process LAN proof (task APP2, docs/spec/ui.md 5.15, net.md 5.11).

Starts two headless APP processes (`tools/gd run res://src/app/boot.tscn`) that go through the real lobby / launch / match path on
127.0.0.1 over ENet: the host (`--autostart=lan-host`) opens a game through `AppLan.host_lan`, the client
(`--autostart=lan-join=127.0.0.1`) joins through `AppLan.join_lan`; the host fills the lobby through `UiLobbyNet` (two humans and one
AI slot), the client picks its faction and readies up, the host starts (countdown, config, loading, LOAD_DONE compare, START), and both
play N ticks with a scripted test bot per human while the AI slot runs on the host. Every process prints `APPTEST role= tick= chain=
checksum=` every 200 ticks; the lines of the two roles must be identical.

    python3 tools/py/app_two_process.py                     macOS / host OS: two gd processes, 3000 ticks
    python3 tools/py/app_two_process.py --linux             the same inside the Debian container (host spawns the client itself)
    python3 tools/py/app_two_process.py --repeat 2          the same seed twice: the checksum lines must repeat exactly
    python3 tools/py/app_two_process.py --ticks 1000 --net-speed 200

Exit code 0 = every check passed; the last line is `APP_TWO_PROCESS RESULT=OK|FAIL ...`.
"""
from __future__ import annotations

import argparse
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
GD = ROOT / "tools" / "gd"
SCENE = "res://src/app/boot.tscn"
KV = re.compile(r"(\w+)=(\S+)")
# Godot prints these when the process exits with live resources; every boot of the app does (not a failure of the proof)
EXIT_NOISE = re.compile(r"still in use at exit|leaked at exit|RID allocations")


def free_udp_port() -> int:
    for _ in range(50):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind(("0.0.0.0", 0))
            port = s.getsockname()[1]
        finally:
            s.close()
        if 20000 <= port <= 60000:
            return port
    return 27615


class Proc:
    """A `tools/gd` child whose stdout is collected on a thread (a full pipe can never block it)."""

    def __init__(self, name: str, cmd: List[str]):
        self.name = name
        self.lines: List[str] = []
        self.lock = threading.Lock()
        # An EXPORTED (release) engine does not flush stdout per line when it is a pipe, so the host's APPLAN_LISTEN would only show at exit: give it a
        # pseudo terminal (line buffered) instead (QA2).
        self.pty_master = -1
        if cmd[0] != sys.executable and sys.platform != "win32":  # not the tools/gd wrapper: an exported binary
            import pty
            self.pty_master, slave = pty.openpty()
            self.p = subprocess.Popen(cmd, stdout=slave, stderr=slave, stdin=subprocess.DEVNULL, cwd=str(ROOT), start_new_session=True)
            os.close(slave)
        else:
            self.p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, cwd=str(ROOT), start_new_session=True)
        self.thread = threading.Thread(target=self._pump, daemon=True)
        self.thread.start()

    def _pump(self) -> None:
        if self.pty_master >= 0:
            buf = b""
            while True:
                try:
                    chunk = os.read(self.pty_master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
                *done, buf = buf.split(b"\n")
                with self.lock:
                    self.lines.extend(x.decode("utf-8", "replace").rstrip("\r") for x in done)
            os.close(self.pty_master)
            return
        assert self.p.stdout is not None
        for line in self.p.stdout:
            with self.lock:
                self.lines.append(line.rstrip("\n"))

    def snapshot(self) -> List[str]:
        with self.lock:
            return list(self.lines)

    def find(self, prefix: str) -> Optional[str]:
        for line in self.snapshot():
            if line.startswith(prefix):
                return line
        return None

    def alive(self) -> bool:
        return self.p.poll() is None

    def wait(self, timeout: float) -> Optional[int]:
        try:
            rc = self.p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None
        self.thread.join(timeout=5)
        return rc

    def kill(self) -> None:
        if self.alive():
            try:
                os.killpg(os.getpgid(self.p.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                self.p.wait(timeout=8)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(self.p.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
        self.thread.join(timeout=3)


def gd_cmd(a: argparse.Namespace, timeout: int, user_args: List[str]) -> List[str]:
    if a.binary:  # task QA2: the EXPORTED app (headless) on both sides; the checksum chain of host and client must still be identical
        return [a.binary, "--headless", "--"] + user_args
    cmd = [sys.executable, str(GD)]
    if a.linux:
        cmd += ["linux", "--arch", a.arch]
    cmd += ["run", "--timeout", str(timeout)]
    if not a.strict_errors:
        cmd.append("--allow-errors")
    cmd += [SCENE, "--"] + user_args
    return cmd


def parse(line: str) -> Dict[str, str]:
    return dict(KV.findall(line))


class Result:
    def __init__(self) -> None:
        self.problems: List[str] = []
        self.rows: Dict[str, Dict[int, Tuple[str, str]]] = {"host": {}, "client": {}}
        self.summary: Dict[str, Dict[str, str]] = {}
        self.ends: Dict[str, Dict[str, str]] = {}
        self.back_in_lobby: Dict[str, Dict[str, str]] = {}
        self.wall = 0.0


def collect(lines_by_proc: Dict[str, List[str]], res: Result) -> None:
    for name, lines in lines_by_proc.items():
        for raw in lines:
            line = raw[len("CLIENT| "):] if raw.startswith("CLIENT| ") else raw
            if line.startswith("APPTEST "):
                kv = parse(line)
                role = kv.get("role", name)
                if "tick" in kv and "chain" in kv and role in res.rows:
                    res.rows[role][int(kv["tick"])] = (kv["chain"], kv["checksum"])
            elif line.startswith("APPTEST_END"):
                kv = parse(line)
                res.ends[kv.get("role", name)] = kv
            elif line.startswith("APPLAN_BACK_IN_LOBBY"):
                res.back_in_lobby[parse(line).get("role", name)] = parse(line)
            elif line.startswith("APPLAN_SUMMARY"):
                kv = parse(line)
                res.summary[kv.get("role", name)] = kv
            elif ("SCRIPT ERROR" in line or line.startswith("ERROR:") or "Parse Error" in line) and not EXIT_NOISE.search(line):
                res.problems.append(f"{name}: engine message: {line[:200]}")


def check(a: argparse.Namespace, res: Result, codes: Dict[str, Optional[int]]) -> None:
    want = list(range(200, a.ticks + 1, 200))
    for role in ("host", "client"):
        got = sorted(res.rows[role])
        if got != want:
            res.problems.append(f"{role}: expected checksum lines at ticks {want[0]}..{want[-1]} step 200, got {got[:3]}...{got[-3:]} ({len(got)} lines)")
        end = res.ends.get(role)
        if end is None or end.get("reason") != "ticks":
            res.problems.append(f"{role}: APPTEST_END reason={end.get('reason') if end else 'missing'} {end.get('detail', '') if end else ''}")
        s = res.summary.get(role)
        if s is None:
            res.problems.append(f"{role}: no APPLAN_SUMMARY line")
        else:
            if s.get("desyncs") != "0":
                res.problems.append(f"{role}: desyncs={s.get('desyncs')}")
            if int(s.get("players", "0")) != 3:
                res.problems.append(f"{role}: expected 3 players (2 humans + 1 AI), config has {s.get('players')}")
            by_pid = dict(x.split(":") for x in s.get("cmds_by_pid", "").split(",") if ":" in x)
            silent = [pid for pid in ("0", "1", "2") if int(by_pid.get(pid, "0")) == 0]
            if silent and not a.binary:  # (an exported build has no SimBot: the two human slots stay idle, only the host's AI plays)
                res.problems.append(f"{role}: players {silent} never issued a command (cmds_by_pid={s.get('cmds_by_pid')})")
            if int(s.get("cmds", "0")) < (1 if a.binary else 20):
                res.problems.append(f"{role}: only {s.get('cmds')} commands executed (the bots / the AI did not play)")
    if a.lobby_again:
        for role in ("host", "client"):
            b = res.back_in_lobby.get(role)
            if b is None:
                res.problems.append(f"{role}: never came back to the lobby (no APPLAN_BACK_IN_LOBBY)")
            elif b.get("humans") != "2":
                res.problems.append(f"{role}: back in the lobby with {b.get('humans')} humans, expected 2")
    for tick in want:
        h, c = res.rows["host"].get(tick), res.rows["client"].get(tick)
        if h is not None and c is not None and h != c:
            res.problems.append(f"tick {tick}: host chain/checksum {h} != client {c}")
    for name, code in codes.items():
        if code != 0:
            res.problems.append(f"{name} exit code {code}")


def run_once(a: argparse.Namespace, label: str) -> Result:
    res = Result()
    t0 = time.time()
    port = free_udp_port()
    tmp = Path(os.environ.get("TMPDIR", "/tmp")) / f"app2p_{os.getpid()}_{label}"
    tmp.mkdir(parents=True, exist_ok=True)
    common = [f"--port={port}", f"--ticks={a.ticks}", f"--net-speed={a.net_speed}", f"--ai={a.ai}", f"--ai-level={a.ai_level}",
              f"--map-seed={a.seed}", f"--match-seed={a.seed * 7919 + 13}", f"--map-size={a.map_size}", "--fresh-settings", "--no-audio", f"--timeout-s={a.timeout}",
              f"--lobby-timeout-s={a.start_timeout}"]
    if a.with_ui:
        common.append("--with-ui")
    if a.lobby_again:
        common.append("--lobby-again")
    procs: List[Proc] = []
    codes: Dict[str, Optional[int]] = {}
    try:
        if a.mode == "both":
            host_args = ["--autostart=lan-host", "--spawn-client"] + common
            p = Proc("host", gd_cmd(a, a.timeout + 120, host_args))
            procs.append(p)
            codes["host"] = p.wait(a.timeout + 120)
            if codes["host"] is None:
                res.problems.append("host process did not finish in time")
        else:
            host_args = ["--autostart=lan-host"] + common
            hp = Proc("host", gd_cmd(a, a.timeout + 120, host_args))
            procs.append(hp)
            deadline = time.time() + a.start_timeout
            listen = None
            while time.time() < deadline and hp.alive():
                listen = hp.find("APPLAN_LISTEN")
                if listen:
                    break
                time.sleep(0.1)
            if not listen:
                res.problems.append("the host never reported APPLAN_LISTEN")
                res.problems.extend(hp.snapshot()[-8:])
            else:
                real_port = int(parse(listen).get("port", port))
                cargs = ["--autostart=lan-join=127.0.0.1"] + [x if not x.startswith("--port=") else f"--port={real_port}" for x in common]
                cp = Proc("client", gd_cmd(a, a.timeout + 120, cargs))
                procs.append(cp)
                for p in procs:
                    remaining = max(5.0, a.timeout + 120 - (time.time() - t0))
                    codes[p.name] = p.wait(remaining)
                    if codes[p.name] is None:
                        res.problems.append(f"{p.name} did not finish in time")
        collect({p.name: p.snapshot() for p in procs}, res)
        if not res.problems or a.always_check:
            check(a, res, codes)
        else:
            for p in procs:
                res.problems.append(f"--- {p.name} tail ---")
                res.problems.extend(p.snapshot()[-6:])
    finally:
        for p in procs:
            p.kill()
        try:
            for f in tmp.iterdir():
                f.unlink()
            tmp.rmdir()
        except OSError:
            pass
    res.wall = time.time() - t0
    if a.verbose:
        for p in procs:
            print(f"--- {p.name} output ---")
            for line in p.snapshot():
                print(line)
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ticks", type=int, default=3000)
    ap.add_argument("--net-speed", type=int, default=200, help="game speed in percent (an unpaced LAN run exceeds the per-peer input rate limit)")
    ap.add_argument("--ai", type=int, default=1)
    ap.add_argument("--ai-level", type=int, default=0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--map-size", type=int, default=128)
    ap.add_argument("--timeout", type=int, default=420, help="seconds for the whole match")
    ap.add_argument("--start-timeout", type=int, default=180, help="seconds until the host listens / the lobby fills (first run imports)")
    ap.add_argument("--repeat", type=int, default=1, help="run N times; the checksum lines must be identical run to run")
    ap.add_argument("--linux", action="store_true", help="run inside the Debian container (implies --mode both)")
    ap.add_argument("--arch", default="amd64")
    ap.add_argument("--binary", default="", help="run the EXPORTED app instead of tools/gd run (host and client are two processes of it; mode gd)")
    ap.add_argument("--mode", choices=["gd", "both"], default=None, help="gd: two tools/gd processes; both: the host spawns the client")
    ap.add_argument("--lobby-again", action="store_true", help="after the target tick both humans surrender, the match ends and both return to the lobby (AppLan.return_to_lobby)")
    ap.add_argument("--with-ui", action="store_true", help="both processes show the real screens (lobby, loading, in-match) on the dummy renderer")
    ap.add_argument("--strict-errors", action="store_true", help="fail on any engine error line (the exit-time leak report of the app boot is one)")
    ap.add_argument("--always-check", action="store_true")
    ap.add_argument("--retries", type=int, default=1, help="retry a run that failed during SETUP (lock contention)")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    if a.mode is None:
        a.mode = "both" if a.linux else "gd"
    runs: List[Result] = []
    ok = True
    for i in range(a.repeat):
        res = Result()
        for attempt in range(a.retries + 1):
            res = run_once(a, f"r{i}")
            setup_fail = any("never reported APPLAN_LISTEN" in p for p in res.problems)
            if not res.problems or not setup_fail:
                break
            print(f"[run {i}] setup failure, retrying: {res.problems[:2]}", flush=True)
        runs.append(res)
        status = "OK" if not res.problems else "FAIL"
        rows = res.rows["host"]
        last = rows.get(max(rows)) if rows else None
        print(f"[run {i}] {status} wall={res.wall:.0f}s lines host={len(res.rows['host'])} client={len(res.rows['client'])} last={last}", flush=True)
        for t in sorted(res.rows["host"]):
            h = res.rows["host"][t]
            c = res.rows["client"].get(t)
            print(f"  tick={t} host chain={h[0]} checksum={h[1]} client {'IDENTICAL' if c == h else c}")
        for prob in res.problems:
            print(f"  PROBLEM {prob}")
        ok = ok and not res.problems
    if ok and len(runs) > 1:
        first = runs[0].rows["host"]
        for i, r in enumerate(runs[1:], 1):
            if r.rows["host"] != first:
                ok = False
                print(f"  PROBLEM run {i}: checksum lines differ from run 0 (same seed, same bots): not deterministic")
    print(f"APP_TWO_PROCESS RESULT={'OK' if ok else 'FAIL'} runs={len(runs)} ticks={a.ticks} mode={a.mode}{' linux' if a.linux else ''}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
