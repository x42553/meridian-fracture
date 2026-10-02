#!/usr/bin/env python3
"""export_proof.py - prove the EXPORTED builds in builds/ load every runtime resource from the .pck.

  python3 tools/py/export_proof.py [--ticks 1200] [--no-linux] [--no-mac]

For each runnable target: `--headless --smoke`, then a headless autostart match
(`--autostart=match --ticks=N --speed=0 --bots --fresh-settings`, audio index + recipes + balance + fonts + shaders load from the pck)
and the final chain/checksum is compared between targets (macOS native vs Linux amd64 in the Debian 12 container).
Static checks for every platform: the pck audit (tests/tools/docs excluded, every project file present) and the three pcks byte-identical.
Windows is NEVER executed here (no Windows host): only exe + pck existence, sizes and pck equality with the Linux pck are checked.
Exit 0 only when everything run passed.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
B = ROOT / "builds"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pck_list  # noqa: E402

MATCH = ["--", "--autostart=match", "--ticks={ticks}", "--speed=0", "--bots", "--fresh-settings", "--no-audio"]


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def pe_info(path: Path) -> str:
    """Static look at a Windows executable (never executed here): PE signature, machine, subsystem, and that Godot's embedded-pck marker is absent
    (the .pck sits next to the exe)."""
    import struct
    with open(path, "rb") as f:
        d = f.read(4096)
    if d[:2] != b"MZ":
        return "NOT A PE FILE"
    off = struct.unpack_from("<I", d, 0x3C)[0]
    if d[off:off + 4] != b"PE\0\0":
        return "BAD PE SIGNATURE"
    machine = struct.unpack_from("<H", d, off + 4)[0]
    opt = off + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    sub = struct.unpack_from("<H", d, opt + 68)[0]
    return "PE%s machine=%s subsystem=%s" % ("32+" if magic == 0x20B else "32", {0x8664: "x86_64", 0xAA64: "arm64", 0x14C: "x86"}.get(machine, hex(machine)),
                                              {2: "GUI", 3: "console"}.get(sub, sub))


def run(cmd, timeout=600):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def check_match(out: str, ticks: int):
    bad = [l for l in out.splitlines() if re.search(r"ERROR|FATAL|SCRIPT ERROR|\[E\]", l)]
    m = re.findall(r"APPTEST tick=%d chain=(\w+) checksum=(\w+)" % ticks, out)
    end = "APPTEST_END reason=ticks" in out
    return (m[-1] if m else None), end, bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ticks", type=int, default=1200)
    ap.add_argument("--no-linux", action="store_true")
    ap.add_argument("--no-mac", action="store_true")
    a = ap.parse_args()
    ok = True
    results = {}

    # static: pcks
    pcks = {"windows": B / "windows/MeridianFracture.pck", "linux": B / "linux/MeridianFracture.pck",
            "macos": B / "macos/MeridianFracture.app/Contents/Resources/Meridian Fracture.pck"}
    for k, p in pcks.items():
        print(f"{k:8} pck {p.stat().st_size/1e6:8.1f} MB  sha256 {sha(p)[:16]}")
    for k in ("windows", "macos"):
        r = subprocess.run([sys.executable, str(ROOT / "tools/py/pck_list.py"), str(pcks[k]), "--compare", str(pcks["linux"])], capture_output=True, text=True)
        print(f"{k} pck vs linux pck: {r.stdout.strip().splitlines()[0]} -> {'OK' if r.returncode == 0 else 'DIFFERENT'}")
        ok &= r.returncode == 0
    r = subprocess.run([sys.executable, str(ROOT / "tools/py/pck_list.py"), str(pcks["linux"]), "--audit", "--project", str(ROOT / "game")], capture_output=True, text=True)
    print(r.stdout.strip().splitlines()[0]); print("\n".join(r.stdout.strip().splitlines()[-3:]))
    ok &= r.returncode == 0
    for f in ("windows/MeridianFracture.exe", "windows/MeridianFracture.console.exe", "linux/MeridianFracture.x86_64"):
        print(f"{f}: {(B / f).stat().st_size/1e6:.1f} MB" + (f"  [{pe_info(B / f)}]" if f.startswith("windows") else ""))
        if f.startswith("windows"):
            ok &= "machine=x86_64" in pe_info(B / f)

    if not a.no_mac and sys.platform == "darwin":
        exe = B / "macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture"
        rc, out = run([str(exe), "--headless", "--smoke"], 120)
        smoke = "MERIDIAN_BOOT" in out and "selftest=ok" in out
        rc2, out2 = run([str(exe), "--headless"] + [x.format(ticks=a.ticks) for x in MATCH], 600)
        res, end, bad = check_match(out2, a.ticks)
        print(f"macos    smoke={'OK' if smoke else 'FAIL'} match chain={res} ended={end} errors={len(bad)} rc={rc2}")
        results["macos"] = res
        ok &= smoke and end and not bad and res is not None
    if not a.no_linux:
        cmd = ("cd /tmp && cp -r /b app && cd app && ./MeridianFracture.x86_64 --headless --smoke 2>&1; echo ==SMOKE-END==; "
               "./MeridianFracture.x86_64 --headless " + " ".join(x.format(ticks=a.ticks) for x in MATCH) + " 2>&1")
        rc, out = run(["docker", "run", "--rm", "--platform", "linux/amd64", "-v", f"{B / 'linux'}:/b:ro", "meridian-linux-runner:amd64", "bash", "-c", cmd], 900)
        smoke_txt, _, match_txt = out.partition("==SMOKE-END==")
        smoke = "MERIDIAN_BOOT" in smoke_txt and "selftest=ok" in smoke_txt
        res, end, bad = check_match(match_txt, a.ticks)
        print(f"linux-amd64 smoke={'OK' if smoke else 'FAIL'} match chain={res} ended={end} errors={len(bad)}")
        results["linux"] = res
        ok &= smoke and end and not bad and res is not None
    if len(set(v for v in results.values() if v)) > 1:
        print("DIVERGENCE between exported targets:", results)
        ok = False
    print("windows: NOT EXECUTED (no Windows host); static pck/exe checks only")
    print("EXPORT PROOF", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
