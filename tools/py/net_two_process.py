#!/usr/bin/env python3
"""Two-process LAN test for Meridian's netcode (docs/spec/net.md 5.11 / 10.6, tasks NET-11 and NET-13).

Starts a headless HOST process and one or more headless CLIENT processes (each a `tools/gd run` of
res://tests/net/net_harness.gd, real ENet over UDP on 127.0.0.1), lets them play a lobby -> launch -> N ticks match with
scripted commands and asserts that every process reports the same input chain, final checksum and per-20-tick checksum list,
that no desync was seen and that all exit codes are 0.

    python3 tools/py/net_two_process.py                       P1: host + 1 client, fake sim, 3000 ticks, fixed delay 2
    python3 tools/py/net_two_process.py --clients 2 --fault wifi --ticks 6000 --fixed-delay 3      P2
    python3 tools/py/net_two_process.py --sim real --ai 1 --ticks 3000                              P3: 2 humans + 1 AI, real sim
    python3 tools/py/net_two_process.py --desync-selftest     a forced divergence MUST be detected and produce a desync package
    python3 tools/py/net_two_process.py --suite               the acceptance set: P1, P2, real sim, real sim + fault, desync self-test
    python3 tools/py/net_two_process.py --mode both --linux   one gd invocation (the host spawns its clients) inside the Linux container

Exit code 0 = every check passed. The last line is `NET_TWO_PROCESS RESULT=OK|FAIL ...` (a JSON summary follows with --json).
Lock contention: tools/gd serialises Godot import runs; if a project import lands between the host and the client start the client
can be queued behind it, so a run that fails during SETUP (not a real mismatch) is retried (--retries, default 2).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[2]
GD = ROOT / "tools" / "gd"
HARNESS = "res://tests/net/net_harness.gd"

KV = re.compile(r"(\w+)=(\S+)")


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
    """A `tools/gd` child whose stdout is collected on a thread (so a full pipe can never block it)."""

    def __init__(self, name: str, cmd: List[str]):
        self.name = name
        self.cmd = cmd
        self.lines: List[str] = []
        self.lock = threading.Lock()
        self.t0 = time.time()
        self.p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                                  cwd=str(ROOT), start_new_session=True)
        self.thread = threading.Thread(target=self._pump, daemon=True)
        self.thread.start()

    def _pump(self) -> None:
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


def parse_line(line: str) -> Dict[str, str]:
    """key=value pairs of a NETTEST line; `package_dir=` (a path that may contain spaces) runs to the end of the line."""
    tail = ""
    if " package_dir=" in line:
        line, tail = line.split(" package_dir=", 1)
    kv = dict(KV.findall(line))
    if tail:
        kv["package_dir"] = tail
    return kv


def gd_cmd(linux: bool, arch: str, timeout: int, args: List[str]) -> List[str]:
    cmd = [sys.executable, str(GD)]
    if linux:
        cmd += ["linux", "--arch", arch]
    cmd += ["run", "--timeout", str(timeout), HARNESS, "--"] + args
    return cmd


def common_args(a: argparse.Namespace, ticks: int, fault: str) -> List[str]:
    out = [f"sim={a.sim}", f"ticks={ticks}", f"players={a.clients + 1}", f"ai={a.ai}", f"fixed-delay={a.fixed_delay}",
           f"speed={a.speed}", f"seed={a.seed}", f"timeout={a.timeout}", f"lobby-timeout={a.start_timeout}", f"ai-impl={a.ai_impl}", f"map-size={a.map_size}"]
    if fault and fault != "none":
        out.append(f"fault={fault}")
    if a.script:
        out.append(f"script={a.script}")
    if a.bots is not None:
        out.append(f"bots={a.bots}")
    return out


class Run:
    def __init__(self, label: str):
        self.label = label
        self.ok = False
        self.setup_failure = False
        self.problems: List[str] = []
        self.lines: Dict[str, Dict[str, str]] = {}
        self.wall = 0.0
        self.exit_codes: Dict[str, Optional[int]] = {}
        self.raw: Dict[str, List[str]] = {}


def run_once(a: argparse.Namespace, label: str, ticks: int, fault: str, desync: bool) -> Run:
    r = Run(label)
    t0 = time.time()
    tmp = Path(tempfile.mkdtemp(prefix="net2p_"))
    port = free_udp_port()
    expect = ["expect-desync"] if desync else []
    procs: List[Proc] = []
    try:
        base = common_args(a, ticks, fault) + expect
        outs = {"host": tmp / "host.json"}
        if a.mode == "both":
            host_args = base + ["role=host", f"port={port}", f"out={outs['host']}", f"spawn-clients={a.clients}"]
            if desync:
                host_args.append(f"child-diverge-at={a.diverge_at}")
            procs.append(Proc("host", gd_cmd(a.linux, a.arch, a.timeout + 60, host_args)))
            r.exit_codes["host"] = procs[0].wait(a.timeout + 60)
            if r.exit_codes["host"] is None:
                r.problems.append("host process did not finish in time")
                r.setup_failure = True
        else:
            host_args = base + ["role=host", f"port={port}", f"out={outs['host']}", "name=Host"]
            procs.append(Proc("host", gd_cmd(a.linux, a.arch, a.timeout + 60, host_args)))
            # wait until the host listens (the first gd run may import the project: generous limit)
            deadline = time.time() + a.start_timeout
            listen = None
            while time.time() < deadline and procs[0].alive():
                listen = procs[0].find("NETTEST_LISTEN")
                if listen:
                    break
                time.sleep(0.1)
            if not listen:
                r.problems.append("the host never reported NETTEST_LISTEN (see its output)")
                r.setup_failure = True
            else:
                real_port = int(parse_line(listen).get("port", port))
                for i in range(a.clients):
                    name = f"client{i + 1}"
                    outs[name] = tmp / f"{name}.json"
                    cargs = base + ["role=client", f"connect=127.0.0.1:{real_port}", f"out={outs[name]}", f"name=Client{i + 2}"]
                    if desync and i == a.clients - 1:
                        cargs.append(f"diverge-at={a.diverge_at}")
                    procs.append(Proc(name, gd_cmd(a.linux, a.arch, a.timeout + 60, cargs)))
                for p in procs:
                    remaining = max(5.0, a.timeout + 60 - (time.time() - t0))
                    r.exit_codes[p.name] = p.wait(remaining)
                    if r.exit_codes[p.name] is None:
                        r.problems.append(f"{p.name} did not finish in time")
        r.wall = time.time() - t0
        for p in procs:
            r.raw[p.name] = p.snapshot()
        check_results(a, r, procs, outs, desync)
    finally:
        for p in procs:
            p.kill()
        try:
            for f in tmp.iterdir():
                f.unlink()
            tmp.rmdir()
        except OSError:
            pass
    r.ok = not r.problems
    return r


def check_results(a: argparse.Namespace, r: Run, procs: List[Proc], outs: Dict[str, Path], desync: bool) -> None:
    lines: List[Dict[str, str]] = []
    seen: Dict[str, Dict[str, str]] = {}
    for name, out in r.raw.items():
        for line in out:
            if line.startswith("NETTEST_ERROR"):
                r.problems.append(f"{name}: {line}")
                if " code=4" in line:
                    r.setup_failure = True
            if line.startswith("NETTEST ") and not line.startswith("NETTEST_"):
                kv = parse_line(line)
                kv["_src"] = name
                # --mode both: a child inherits stdout AND the host re-prints its result: keep one line per (role, pid)
                seen[f"{kv.get('role', '?')}:{kv.get('pid', '?')}"] = kv
    lines = list(seen.values())
    r.lines.update(seen)
    expected = a.clients + 1
    if len(lines) != expected:
        r.problems.append(f"expected {expected} NETTEST lines, got {len(lines)}")
        r.setup_failure = r.setup_failure or len(lines) == 0
        # show the tail of the silent process to help
        for name, out in r.raw.items():
            r.problems.append(f"--- {name} tail ---")
            r.problems.extend(out[-6:])
        return
    for name, code in r.exit_codes.items():
        if code not in (0,) and not (a.mode == "both" and name != "host"):
            r.problems.append(f"{name} exit code {code}")
    for k, kv in r.lines.items():
        if kv.get("status") != "ok" and not desync:
            r.problems.append(f"{k}: status={kv.get('status')}")
    if desync:
        for k, kv in r.lines.items():
            if kv.get("desync") != "1":
                r.problems.append(f"{k}: the forced divergence was not detected")
            files = kv.get("package", "").split(",")
            if not all(f in files for f in ("json", "state", "checks")):
                r.problems.append(f"{k}: no desync package (files={files})")
        return
    ref = None
    for kv in lines:
        for key in ("chain", "final", "checks", "digest", "ticks"):
            if ref is not None and kv.get(key) != ref.get(key):
                r.problems.append(f"{kv.get('role')}:{kv.get('pid')} {key}={kv.get(key)} differs from {ref.get('role')}:{ref.get('pid')} {ref.get(key)}")
        if kv.get("desync") != "0":
            r.problems.append(f"{kv.get('role')}:{kv.get('pid')} reported a desync")
        if ref is None:
            ref = kv
    if int(lines[0].get("checks", "0")) < int(lines[0].get("ticks", "0")) // 20:
        r.problems.append("fewer checksum snapshots than ticks/20")
    # per-tick comparison from the JSON files when we have them (host + subprocess mode)
    rows: Dict[str, Dict[int, tuple]] = {}
    for name, path in outs.items():
        if path.exists():
            try:
                d = json.loads(path.read_text())
                rows[name] = {int(t): (int(c), int(h)) for t, c, h in d.get("check_rows", []) if int(t) <= int(d.get("ticks", 0))}
            except (OSError, ValueError):
                r.problems.append(f"unreadable result file for {name}")
    names = list(rows)
    for n in names[1:]:
        common = set(rows[names[0]]) & set(rows[n])
        bad = [t for t in sorted(common) if rows[names[0]][t] != rows[n][t]]
        if bad:
            r.problems.append(f"{n}: checksum/chain differs from {names[0]} at ticks {bad[:5]}")
        if len(common) < int(lines[0].get("ticks", "0")) // 20:
            r.problems.append(f"{n}: only {len(common)} common checksum ticks")


def repeat_check(runs: List[Run]) -> List[str]:
    """--repeat: with a fixed input delay the bundles are byte-identical run to run, so chain/final/digest must repeat exactly."""
    problems: List[str] = []
    keys = ("chain", "final", "digest", "checks")
    first = runs[0].lines.get("host:0")
    for r in runs[1:]:
        cur = r.lines.get("host:0")
        if not first or not cur:
            problems.append("repeat: a run produced no host line")
            continue
        for k in keys:
            if first.get(k) != cur.get(k):
                problems.append(f"repeat: {k} {first.get(k)} != {cur.get(k)} between two identical runs")
    return problems


def summarize(r: Run) -> Dict[str, object]:
    out: Dict[str, object] = {"label": r.label, "ok": r.ok, "wall_s": round(r.wall, 1), "problems": r.problems}
    per = {}
    for k, kv in r.lines.items():
        per[k] = {x: kv.get(x) for x in ("ticks", "chain", "final", "checks", "digest", "desync", "stalls", "stall_ms", "delay", "bytes_out",
                                          "bytes_in", "play_ms", "ms_per_tick", "lat_avg_ms", "lat_p95_ms", "cmds", "world", "status")}
        try:
            secs = max(0.001, float(kv.get("play_ms", "0")) / 1000.0)
            per[k]["out_bytes_per_s"] = round(int(kv.get("bytes_out", "0")) / secs)
            per[k]["in_bytes_per_s"] = round(int(kv.get("bytes_in", "0")) / secs)
        except ValueError:
            pass
    out["processes"] = per
    return out


def run_scenario(a: argparse.Namespace, label: str, ticks: int, fault: str, desync: bool) -> Run:
    attempts = a.retries + 1
    r = Run(label)
    for i in range(attempts):
        r = run_once(a, label, ticks, fault, desync)
        if r.ok or not r.setup_failure or i == attempts - 1:
            break
        print(f"[{label}] setup failure, retrying ({i + 1}/{attempts - 1}): {r.problems[:2]}", flush=True)
    return r


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=["fake", "real"], default="fake")
    ap.add_argument("--clients", type=int, default=1, help="client processes (players = clients + 1 humans)")
    ap.add_argument("--ai", type=int, default=0, help="AI slots (host-side thinkers)")
    ap.add_argument("--ticks", type=int, default=3000)
    ap.add_argument("--fault", default="none", help="fault preset or a name from game/tests/net/profiles.json")
    ap.add_argument("--fixed-delay", type=int, default=2)
    ap.add_argument("--speed", type=int, default=0, help="0 = unpaced (fast), 50..200 = paced")
    ap.add_argument("--seed", type=int, default=20260930)
    ap.add_argument("--map-size", type=int, default=96)
    ap.add_argument("--ai-impl", choices=["ai", "bot", "stub"], default="ai")
    ap.add_argument("--bots", choices=["0", "1"], default=None, help="real sim: SimBot commands for the human players (default on)")
    ap.add_argument("--script", default="", help="fake sim: res:// path of a scripted command file (spec 7.6)")
    ap.add_argument("--timeout", type=int, default=240, help="wall limit of one match in seconds")
    ap.add_argument("--start-timeout", type=int, default=180, help="seconds to wait for the host to listen (import, lock queue)")
    ap.add_argument("--retries", type=int, default=2)
    ap.add_argument("--repeat", type=int, default=1, help="run the scenario N times and require identical chain/final/digest (golden)")
    ap.add_argument("--desync-selftest", action="store_true", help="the last client corrupts its world at --diverge-at; both sides must detect it")
    ap.add_argument("--diverge-at", type=int, default=400)
    ap.add_argument("--mode", choices=["gd", "both"], default="gd", help="gd: host and clients are separate `tools/gd run` processes; both: one invocation, the host spawns the clients")
    ap.add_argument("--linux", action="store_true", help="run inside the Debian container (`tools/gd linux`); implies --mode both")
    ap.add_argument("--arch", choices=["amd64", "arm64"], default="amd64")
    ap.add_argument("--suite", action="store_true", help="P1 + P2 + real-sim P3 + real-sim with faults + the desync self-test")
    ap.add_argument("--json", action="store_true", help="print the JSON summary")
    a = ap.parse_args()
    if a.linux:
        a.mode = "both"
    results: List[Run] = []
    if a.suite:
        plan = [
            ("P1 fake host+1", dict(sim="fake", clients=1, ai=0, ticks=3000, fault="none", fixed_delay=2, repeat=2), False),
            ("P2 fake host+2 wifi", dict(sim="fake", clients=2, ai=0, ticks=6000, fault="wifi", fixed_delay=3), False),
            ("P3 real 2 humans+AI", dict(sim="real", clients=1, ai=1, ticks=3000, fault="none", fixed_delay=2, repeat=2), False),
            ("P3f real 2 humans+AI wifi", dict(sim="real", clients=1, ai=1, ticks=3000, fault="wifi", fixed_delay=3), False),
            ("D desync self-test real", dict(sim="real", clients=1, ai=1, ticks=1200, fault="none", fixed_delay=2), True),
        ]
        base = vars(a).copy()
        for label, over, desync in plan:
            b = argparse.Namespace(**{**base, **over})
            r = run_scenario(b, label, b.ticks, b.fault, desync)
            if r.ok and b.repeat > 1:
                more = [run_scenario(b, label + f" #{i + 2}", b.ticks, b.fault, desync) for i in range(b.repeat - 1)]
                for m in more:
                    r.problems.extend(m.problems)
                r.problems.extend(repeat_check([r] + more))
                r.ok = not r.problems
            results.append(r)
            print(("PASS " if r.ok else "FAIL ") + f"{label} ({r.wall:.1f}s) " + ("" if r.ok else "; ".join(r.problems[:6])), flush=True)
    else:
        label = "desync-selftest" if a.desync_selftest else f"{a.sim} host+{a.clients}"
        r = run_scenario(a, label, a.ticks, a.fault, a.desync_selftest)
        if r.ok and a.repeat > 1:
            more = [run_scenario(a, label + f" #{i + 2}", a.ticks, a.fault, a.desync_selftest) for i in range(a.repeat - 1)]
            for m in more:
                r.problems.extend(m.problems)
            r.problems.extend(repeat_check([r] + more))
            r.ok = not r.problems
        results.append(r)
        print(("PASS " if r.ok else "FAIL ") + f"{label} ({r.wall:.1f}s)" + ("" if r.ok else " " + "; ".join(r.problems[:8])), flush=True)
    summary = [summarize(r) for r in results]
    for s in summary:
        for k, v in (s["processes"] or {}).items():  # type: ignore[union-attr]
            print(f"  {s['label']} {k}: " + " ".join(f"{x}={y}" for x, y in v.items() if y is not None))
    ok = all(r.ok for r in results)
    print(f"NET_TWO_PROCESS RESULT={'OK' if ok else 'FAIL'} runs={len(results)} failed={sum(1 for r in results if not r.ok)}")
    if a.json:
        print(json.dumps(summary, indent=1))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
