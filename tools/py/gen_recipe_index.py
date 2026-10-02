#!/usr/bin/env python3
"""Write game/data/recipes/index.json (sorted id list of every recipe file) and footprints.json (structure footprint anchors).

  python3 tools/py/gen_recipe_index.py            # write both files
  python3 tools/py/gen_recipe_index.py --check    # write nothing; exit 1 when a file is out of date

index.json = {"schema": "meridian.recipes.index/1", "ids": [sorted recipe ids]} is exactly the sorted list of `<recipe id>.json`
files (V-RCP-02). footprints.json (`meridian.footprints/1`) is GENERATED from game/data/balance with the same formulas as
ViewDefAdapter (door anchor from the exit cell, pads spread along the footprint width); ViewRecipeBook loads it and the builder
injects each structure's record as expression variables (render spec 5.8.1). A Godot test cross-checks it against DefStructure.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import recipe_lib as rl  # noqa: E402


def index_text(recipes: Path = rl.RECIPES) -> str:
    ids = sorted(p.stem for p in rl.recipe_files(recipes))
    return rl.dumps({"schema": rl.INDEX_SCHEMA, "ids": ids})


def footprints_text(balance: Path = rl.BALANCE) -> str:
    return rl.dumps(rl.build_footprints(rl.collect_defs(balance)), sort_keys=True)


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    files = {rl.RECIPES / "index.json": index_text(), rl.RECIPES / "footprints.json": footprints_text()}
    stale = [p for p, t in files.items() if not p.exists() or p.read_text(encoding="utf-8") != t]
    if args.check:
        for p in stale:
            print("out of date: %s" % p.name, file=sys.stderr)
        return 1 if stale else 0
    for p, t in files.items():
        rl.write_if_changed(p, t)
    if not args.quiet:
        print("index.json: %d ids; footprints.json: %d structures" % (len(rl.load_json(rl.RECIPES / "index.json")["ids"]),
                                                                     len(rl.load_json(rl.RECIPES / "footprints.json")["structures"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
