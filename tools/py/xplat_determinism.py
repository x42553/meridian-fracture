#!/usr/bin/env python3
"""Cross-platform determinism check: run one headless scenario on several platforms and diff the hash chains.

    tools/py/xplat_determinism.py res://tests/scenarios/xplat_int_math.gd [-- scenario args]
    tools/py/xplat_determinism.py <scenario> --targets native,amd64,arm64   (default: all three)
    tools/py/xplat_determinism.py <scenario> --only-local --out FILE        (CI: write this OS's chain)
    tools/py/xplat_determinism.py --compare a.hashes b.hashes [c.hashes]    (CI: diff chains from several OSes)

Targets
    native  the host OS (macOS arm64 here)               tools/gd run <scenario>
    amd64   Debian 12 container, linux/amd64 (emulated on Apple silicon)   tools/gd linux --arch amd64 run <scenario>
    arm64   Debian 12 container, linux/arm64 (native on Apple silicon)     tools/gd linux --arch arm64 run <scenario>

The scenario must print lines `HASH tick=<n> <hex>`; `SCENARIO_DONE` is optional. Exit status: 0 all chains
identical; 1 divergence (the first diverging tick and every target's value are printed) or a target failed;
2 usage. The container path pays a one-off image build + cold Godot import (see docs/spec/qa_tooling.md).
"""
from __future__ import annotations

import argparse
import platform
import re
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

HERE = Path(__file__).resolve().parent
GD = HERE.parent / "gd"
HASH_RE = re.compile(r"^HASH tick=(\d+) ([0-9a-fA-F]+)\s*$")

Chain = List[Tuple[int, str]]


def host_label() -> str:
    os_name = {"darwin": "macos", "linux": "linux", "win32": "windows"}.get(sys.platform, sys.platform)
    m = platform.machine().lower()
    return f"{os_name}-{'arm64' if m in ('arm64', 'aarch64') else 'x86_64'}"


def parse_chain(text: str) -> Chain:
    out: Chain = []
    for line in text.splitlines():
        m = HASH_RE.match(line.strip())
        if m:
            out.append((int(m.group(1)), m.group(2).lower()))
    return out


def run_target(label: str, cmd: Sequence[str], timeout: float, results: Dict[str, dict]) -> None:
    t0 = time.time()
    try:
        p = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
        rc, out = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired as exc:
        rc, out = 124, f"TIMEOUT after {timeout:.0f}s\n{exc.stdout or ''}"
    results[label] = {"rc": rc, "out": out, "chain": parse_chain(out), "seconds": time.time() - t0, "cmd": list(cmd)}


def compare(chains: Dict[str, Chain]) -> Optional[str]:
    """None when all chains are identical, else a human readable description of the first divergence."""
    labels = list(chains)
    ref = labels[0]
    ticks = sorted({t for c in chains.values() for t, _h in c})
    lookup = {lab: dict(c) for lab, c in chains.items()}
    prev_ok: Optional[int] = None
    for t in ticks:
        vals = {lab: lookup[lab].get(t) for lab in labels}
        if len({v for v in vals.values()}) > 1:
            lines = [f"DIVERGENCE at tick {t} (last tick where all targets agreed: {prev_ok if prev_ok is not None else 'none'})"]
            for lab in labels:
                lines.append(f"    {lab:14s} {vals[lab] if vals[lab] is not None else '<no value: chain ended earlier>'}")
            differing = [lab for lab in labels if vals[lab] != vals[ref]]
            lines.append(f"    reference {ref}; differing: {', '.join(differing)}")
            return "\n".join(lines)
        prev_ok = t
    return None


def write_chain(path: Path, chain: Chain) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"HASH tick={t} {h}\n" for t, h in chain))


def cmd_compare(files: Sequence[str]) -> int:
    chains = {Path(f).stem: parse_chain(Path(f).read_text()) for f in files}
    empty = [k for k, v in chains.items() if not v]
    if empty:
        print(f"xplat: no HASH lines in {', '.join(empty)}", file=sys.stderr)
        return 1
    diff = compare(chains)
    print(f"xplat: compared {', '.join(f'{k} ({len(v)} hashes)' for k, v in chains.items())}")
    if diff:
        print(diff)
        return 1
    print("xplat: IDENTICAL hash chains on all platforms")
    return 0


def main() -> int:
    argv = sys.argv[1:]
    user_args: List[str] = []
    if "--" in argv:
        i = argv.index("--")
        argv, user_args = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scenario", nargs="?", help="res://path/to/scenario.gd (extends SceneTree)")
    ap.add_argument("--targets", default="native,amd64,arm64")
    ap.add_argument("--only-local", action="store_true", help="run only the host and write the chain to --out")
    ap.add_argument("--out", help="with --only-local: file to write; otherwise a directory for <target>.hashes")
    ap.add_argument("--compare", nargs="+", metavar="FILE", help="diff chains already produced elsewhere")
    ap.add_argument("--timeout", type=float, default=1800)
    args = ap.parse_args(argv)
    if args.compare:
        return cmd_compare(args.compare)
    if not args.scenario:
        ap.error("scenario required")
    targets = ["native"] if args.only_local else [t.strip() for t in args.targets.split(",") if t.strip()]
    bad = [t for t in targets if t not in ("native", "amd64", "arm64")]
    if bad:
        ap.error(f"unknown target(s): {bad}")
    tail = ["run", args.scenario, *(["--", *user_args] if user_args else [])]
    commands: Dict[str, List[str]] = {}
    for t in targets:
        if t == "native":
            commands[host_label()] = [sys.executable, str(GD), *tail]
        else:
            commands[f"linux-{'x86_64' if t == 'amd64' else 'arm64'}-container"] = [sys.executable, str(GD), "linux", "--arch", t, *tail]
    results: Dict[str, dict] = {}
    t0 = time.time()
    # native first (fast, and it triggers any needed import), containers in parallel afterwards
    labels = list(commands)
    first = labels[0] if targets[0] == "native" else None
    if first:
        run_target(first, commands[first], args.timeout, results)
    threads = [threading.Thread(target=run_target, args=(lab, commands[lab], args.timeout, results)) for lab in labels if lab != first]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    ok = True
    for lab in labels:
        r = results[lab]
        status = "ok" if r["rc"] == 0 and r["chain"] else "FAILED"
        print(f"xplat: {lab:28s} {status:6s} {len(r['chain']):3d} hashes  {r['seconds']:6.1f}s")
        if status == "FAILED":
            ok = False
            print(f"       exit {r['rc']}; last output:\n" + "\n".join("         " + l for l in r["out"].splitlines()[-12:]))
    if args.only_local and args.out:
        write_chain(Path(args.out), results[labels[0]]["chain"])
        print(f"xplat: wrote {args.out}")
    elif args.out:
        for lab in labels:
            write_chain(Path(args.out) / f"{lab}.hashes", results[lab]["chain"])
    if not ok:
        return 1
    if len(labels) > 1:
        diff = compare({lab: results[lab]["chain"] for lab in labels})
        if diff:
            print(diff)
            return 1
        print(f"xplat: IDENTICAL hash chains on {len(labels)} platforms ({len(results[labels[0]]['chain'])} hashes) in {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
