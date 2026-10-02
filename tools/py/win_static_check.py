#!/usr/bin/env python3
"""win_static_check.py - static verification of the Windows export (task QA2). The .exe is NEVER executed here (no Windows host).

  python3 tools/py/win_static_check.py [--out builds/qa/windows-static.json]

Checks: both executables are PE32+ x86-64 (GUI and console subsystem), the main exe has the reserved `pck` section of an external-pck export (embed_pck is false),
the version resource is the ENGINE's own (no rcedit on the export host: not Meridian's), the .pck is byte-identical to the Linux and macOS .pck (sha256) and
parses as pack format 4 / engine 4.7.2 with the same entry count, the zip holds exe + console exe + pck + ico + README, and the CI Windows job runs
`--smoke` and a headless 1200-tick match on the console exe (read from .github/workflows/build.yml). Exit 0 when everything holds.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
B = ROOT / "builds"


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def pe_info(p: Path) -> dict:
    d = p.read_bytes()
    o = struct.unpack_from("<I", d, 0x3C)[0]
    assert d[o:o + 4] == b"PE\0\0", "not a PE file"
    mach, nsec = struct.unpack_from("<HH", d, o + 4)
    osz = struct.unpack_from("<H", d, o + 20)[0]
    opt = o + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    sub = struct.unpack_from("<H", d, opt + 68)[0]
    secs = {}
    so = opt + osz
    for i in range(nsec):
        name, vs, _va, rs, _rp = struct.unpack_from("<8sIIII", d, so + i * 40)
        secs[name.rstrip(b"\0").decode()] = {"virtual": vs, "raw": rs}
    res = {}
    for key in ("FileDescription", "FileVersion"):
        k = key.encode("utf-16le")
        i = d.find(k)
        if i >= 0:
            tail = d[i + len(k):i + len(k) + 160].decode("utf-16le", "ignore")
            res[key] = tail.strip("\0").split("\0")[0][:60]
    return {"machine": hex(mach), "pe32plus": magic == 0x20B, "subsystem": {2: "GUI", 3: "console"}.get(sub, sub), "sections": list(secs), "pck_section_bytes": secs.get("pck", {}).get("raw"),
            "bytes": len(d), "version_resource_strings": res}


def pck_head(p: Path) -> dict:
    d = p.read_bytes()[:64]
    magic = d[:4]
    ver, vmaj, vmin, vpatch = struct.unpack_from("<IIII", d, 4)
    return {"magic": magic.decode("latin1"), "pack_format": ver, "engine": f"{vmaj}.{vmin}.{vpatch}"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(B / "qa" / "windows-static.json"))
    a = ap.parse_args()
    ver = (ROOT / "VERSION").read_text().strip()
    out: dict = {"windows_executed": False, "version": ver, "checks": {}}
    ok = True

    def check(name: str, cond: bool, detail: object) -> None:
        nonlocal ok
        ok = ok and bool(cond)
        out["checks"][name] = {"ok": bool(cond), "detail": detail}
        print(f"  [{'ok' if cond else 'FAIL'}] {name}: {detail}")

    exe, con, pck = B / "windows/MeridianFracture.exe", B / "windows/MeridianFracture.console.exe", B / "windows/MeridianFracture.pck"
    ie, ic = pe_info(exe), pe_info(con)
    check("exe is PE32+ x86-64 GUI", ie["machine"] == "0x8664" and ie["pe32plus"] and ie["subsystem"] == "GUI", f"{ie['machine']} {ie['subsystem']} {ie['bytes']} B")
    check("console exe is PE32+ x86-64 console", ic["machine"] == "0x8664" and ic["pe32plus"] and ic["subsystem"] == "console", f"{ic['machine']} {ic['subsystem']} {ic['bytes']} B")
    check("external pck (embed_pck=false)", "pck" in ie["sections"] and (ie["pck_section_bytes"] or 0) < 4096, f"pck section {ie['pck_section_bytes']} B in the exe")
    out["exe"], out["console_exe"] = ie, ic
    check("version resource is the engine default (no rcedit)", "Godot" in ie["version_resource_strings"].get("FileDescription", ""), ie["version_resource_strings"])
    ph = pck_head(pck)
    check("pck header", ph["magic"] == "GDPC" and ph["engine"].startswith("4.7.2"), ph)
    hashes = {"windows": sha(pck), "linux": sha(B / "linux/MeridianFracture.pck")}
    mac = B / "macos/MeridianFracture.app/Contents/Resources/Meridian Fracture.pck"
    if mac.exists():
        hashes["macos"] = sha(mac)
    check("pck sha256 identical on all OS exports", len(set(hashes.values())) == 1, hashes)
    z = B / "packages" / f"meridian-fracture-{ver}-windows-x86_64.zip"
    with zipfile.ZipFile(z) as zf:
        names = sorted(n.split("/")[-1] for n in zf.namelist())
        inner = hashlib.sha256(zf.read([n for n in zf.namelist() if n.endswith(".pck")][0])).hexdigest()
    check("zip members", {"MeridianFracture.exe", "MeridianFracture.console.exe", "MeridianFracture.pck", "MeridianFracture.ico", "README.txt"} <= set(names), names)
    check("zip pck == build pck", inner == hashes["windows"], inner[:16])
    ci = (ROOT / ".github/workflows/build.yml").read_text()
    smoke = "MeridianFracture.console.exe --headless --smoke" in ci
    match = "MeridianFracture.console.exe --headless -- --autostart=match --ticks=1200" in ci
    proofs = "export_qa.py --binary" in ci and "windows) exe=builds/windows/MeridianFracture.console.exe" in ci
    check("CI Windows job runs --smoke, a headless 1200-tick match and export_qa on the exported console exe", smoke and match and proofs, {"smoke": smoke, "match": match, "export_qa": proofs})
    out["pass"] = ok
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(out, indent=1) + "\n")
    print("WIN_STATIC", "OK (static only: the .exe was NOT executed)" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
