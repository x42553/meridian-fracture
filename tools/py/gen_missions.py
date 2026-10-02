#!/usr/bin/env python3
"""MIS3: regenerates the shipped mission files (game/data/missions/*.json, except the hand-written demo_*.json) from the authoring modules in
tools/py/mis3/. Usage: python3 tools/py/gen_missions.py [id ...]   (no argument = all). Then: python3 tools/py/validate_missions.py"""
import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

MODULES = ["tutorial", "op_napc", "op_nec", "op_olm", "op_def", "op_pd", "op_han", "op_ae", "op_sap"]


def main(argv):
    only = set(argv)
    for name in MODULES:
        try:
            mod = importlib.import_module("mis3." + name)
        except ModuleNotFoundError as e:
            if e.name == "mis3." + name:
                continue
            raise
        m = mod.build()
        if only and m.d["id"] not in only:
            continue
        m.write()
        print("wrote", m.d["id"], f"({len(m.d['triggers'])} triggers, {len(m.d['messages'])} messages, {len(m.d['objectives'])} objectives)")


def update_manifest():
    """The manifest lists every file of game/data/missions, sorted (the data hash covers exactly that list)."""
    import json
    import re
    root = Path(__file__).resolve().parents[2]
    man = root / "game" / "data" / "balance" / "manifest.json"
    files = sorted(p.name for p in (root / "game" / "data" / "missions").glob("*.json"))
    text = man.read_text(encoding="utf-8")
    new = re.sub(r'"missions": \[[^\]]*\]', '"missions": ' + json.dumps(files), text)
    if new != text:
        man.write_text(new, encoding="utf-8")
        print("manifest missions:", files)


if __name__ == "__main__":
    main(sys.argv[1:])
    update_manifest()
