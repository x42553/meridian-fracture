#!/usr/bin/env python3
"""Mirror the read-only design bible into the Godot project: Input/meridian_agent_reference -> game/data/bible.

    tools/py/sync_bible.py            copy (verbatim) + write manifest.json + README.md; refuses to clobber hand edits
    tools/py/sync_bible.py --check    verify game/data/bible against manifest.json AND the Input/ sources (exit 1 on drift)
    tools/py/sync_bible.py --force    overwrite even when the mirrored files were edited by hand

What is copied: meridian_factions.json (canonical data) and meridian_factions.schema.json, byte for byte.
manifest.json records sha256 + size of the source and of the copy. A destination file whose hash differs from the
manifest is a hand edit: the script stops instead of destroying it (exit 1). Never edit game/data/bible/ by hand;
change the bible in Input/ (the user's source of truth) and re-run this script.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gdlib import env  # noqa: E402

SRC_DIR = env.ROOT / "Input" / "meridian_agent_reference"
DST_DIR = env.GAME / "data" / "bible"
FILES = ["meridian_factions.json", "meridian_factions.schema.json"]
MANIFEST = "manifest.json"
README = "README.md"

README_TEXT = """# game/data/bible - GENERATED, DO NOT EDIT

This folder is a verbatim mirror of `Input/meridian_agent_reference/` (the read-only design bible), produced by
`tools/py/sync_bible.py`. `manifest.json` lists the sha256 of every file; `tools/py/sync_bible.py --check` fails
when a file here was edited or when `Input/` changed and this mirror was not refreshed.

* Canonical data: `meridian_factions.json` (schema: `meridian_factions.schema.json`).
* Balance numbers the bible leaves `null` live in `game/data/balance/`, never here.
* To change the bible: edit `Input/` (only the user does that), then run `python3 tools/py/sync_bible.py`.
"""


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest() -> dict:
    try:
        return json.loads((DST_DIR / MANIFEST).read_text())
    except (OSError, ValueError):
        return {}


def check() -> int:
    manifest = load_manifest()
    files = manifest.get("files", {})
    bad = 0
    for name in FILES:
        src, dst = SRC_DIR / name, DST_DIR / name
        rec = files.get(name)
        if not dst.exists():
            print(f"MISSING  {env.rel_to_root(dst)}")
            bad += 1
            continue
        if rec is None:
            print(f"UNTRACKED {name}: not listed in {MANIFEST}")
            bad += 1
            continue
        if sha256(dst) != rec["sha256"]:
            print(f"EDITED   {name}: differs from manifest (hand edit or corruption)")
            bad += 1
        if src.exists() and sha256(src) != rec["source_sha256"]:
            print(f"STALE    {name}: Input/ changed since the last sync; run tools/py/sync_bible.py")
            bad += 1
    if not bad:
        print(f"bible mirror OK ({len(FILES)} files match manifest and Input/)")
    return 1 if bad else 0


def sync(force: bool) -> int:
    for name in FILES:
        if not (SRC_DIR / name).exists():
            env.die(f"source missing: {SRC_DIR / name}", 2)
    DST_DIR.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    files = manifest.get("files", {})
    refused = []
    for name in FILES:
        src, dst = SRC_DIR / name, DST_DIR / name
        if not dst.exists():
            continue
        current = sha256(dst)
        recorded = files.get(name, {}).get("sha256")
        if current == sha256(src) or current == recorded:
            continue  # identical to the source, or untouched since the last sync
        refused.append(name)
    if refused and not force:
        print("REFUSING to overwrite hand-edited files (their hash matches neither the manifest nor the source):", file=sys.stderr)
        for name in refused:
            print(f"  {env.rel_to_root(DST_DIR / name)}", file=sys.stderr)
        print("Revert them (this folder is generated) or pass --force to discard the edits.", file=sys.stderr)
        return 1
    out = {"generated_by": "tools/py/sync_bible.py", "source": "Input/meridian_agent_reference", "files": {}}
    changed = 0
    for name in FILES:
        src, dst = SRC_DIR / name, DST_DIR / name
        before = sha256(dst) if dst.exists() else None
        shutil.copyfile(src, dst)
        digest = sha256(dst)
        if digest != sha256(src):
            env.die(f"copy of {name} is not identical to the source", 1)
        changed += before != digest
        out["files"][name] = {"sha256": digest, "source_sha256": sha256(src), "bytes": dst.stat().st_size}
    (DST_DIR / MANIFEST).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
    if not (DST_DIR / README).exists():
        (DST_DIR / README).write_text(README_TEXT)
    for name in FILES:
        rec = out["files"][name]
        print(f"{name}  {rec['bytes']} bytes  sha256 {rec['sha256']}")
    print(f"bible synced to {env.rel_to_root(DST_DIR)} ({changed} file(s) changed)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    return check() if args.check else sync(args.force)


if __name__ == "__main__":
    sys.exit(main())
