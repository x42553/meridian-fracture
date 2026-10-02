#!/usr/bin/env python3
"""release_manifest.py - writes builds/RELEASE_MANIFEST.json: every release artifact with size + sha256 (task QA2).

  python3 tools/py/release_manifest.py [--qa builds/qa] [--check]

Lists builds/packages/*, the exported binaries and the pck of each platform (the .app executable and its pck inside the bundle), the version,
the engine, and merges the QA result files under builds/qa/*.json (export_qa.py runs, perf / startup measurements) when present.
`--check` re-hashes everything and fails when a file differs from the manifest (a package was rebuilt after the QA pass).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
B = ROOT / "builds"
MANIFEST = B / "RELEASE_MANIFEST.json"


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def artifacts() -> list[Path]:
    out = sorted((B / "packages").glob("*"))
    out += [B / "windows/MeridianFracture.exe", B / "windows/MeridianFracture.console.exe", B / "windows/MeridianFracture.pck",
            B / "linux/MeridianFracture.x86_64", B / "linux/MeridianFracture.pck",
            B / "macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture", B / "macos/MeridianFracture.app/Contents/Resources/Meridian Fracture.pck"]
    return [p for p in out if p.is_file()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--qa", default=str(B / "qa"))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        old = json.loads(MANIFEST.read_text())
        bad = 0
        for e in old["artifacts"]:
            p = ROOT / e["path"]
            ok = p.is_file() and p.stat().st_size == e["bytes"] and sha(p) == e["sha256"]
            bad += not ok
            print(f"[{'ok' if ok else 'CHANGED'}] {e['path']}")
        print("RELEASE_MANIFEST", "matches" if not bad else f"{bad} artifact(s) differ")
        return 1 if bad else 0
    ver = (ROOT / "VERSION").read_text().strip()
    arts = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": sha(p)} for p in artifacts()]
    qa: dict = {}
    for f in sorted(Path(a.qa).glob("*.json")):
        try:
            qa[f.stem] = json.loads(f.read_text())
        except ValueError:
            pass
    MANIFEST.write_text(json.dumps({"game": "Meridian Fracture", "version": ver, "engine": "Godot 4.7.2-stable", "windows_executed": False,
                                    "artifacts": arts, "qa": qa}, indent=1) + "\n")
    for e in arts:
        print(f"{e['bytes']:>12,}  {e['sha256']}  {e['path']}")
    print(f"wrote {MANIFEST.relative_to(ROOT)} ({len(arts)} artifacts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
