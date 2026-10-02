#!/usr/bin/env python3
"""Generate a stub recipe for every def the view has to draw (VIEW-T1; render spec 5.8.7 / 7.4 / 7.9 V-RCP-02).

  python3 tools/py/gen_recipe_stubs.py              # write / refresh stubs, then refresh index.json + footprints.json
  python3 tools/py/gen_recipe_stubs.py --check      # write nothing; exit 1 when a stub is missing or out of date
  python3 tools/py/gen_recipe_stubs.py --prune      # also delete stubs of ids that no longer exist in the balance data
  python3 tools/py/gen_recipe_stubs.py --only 'unit.napc.*'   # restrict to ids matching an fnmatch pattern

Covers every unit (156), summon (13), structure (29) and neutral (8) def of game/data/balance plus the projectile ids
(recipe_lib.PROJECTILE_IDS). Each id is resolved through game/data/recipes/assignments.json to a view archetype
(recipe_lib.resolve); while that archetype file does not exist the generic fallback of `assignments.json -> fallbacks` is used, so
every stub builds a valid model and NOTHING falls back to the magenta placeholder box.

A stub is a recipe file with `meta.stub = true`. It is (re)written whenever the rules or the archetype files change; a recipe
WITHOUT that flag is hand-authored (VIEW-M8) and is never touched. Delete the `stub` key when you take over a file.
Exit codes: 0 ok, 1 --check found drift, 2 usage / data error. Warnings (ids without a rule) go to stderr.
"""
from __future__ import annotations

import argparse
import fnmatch
import sys
from pathlib import Path
from typing import Dict, List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import recipe_lib as rl  # noqa: E402


def plan(recipes: Path = rl.RECIPES, balance: Path = rl.BALANCE, only: Optional[str] = None) -> Dict[str, dict]:
    """id -> {"path", "text", "status" (new|changed|same|kept), "warnings": [...]} for every def id."""
    defs = rl.collect_defs(balance)
    assign = rl.load_json(recipes / "assignments.json")
    out: Dict[str, dict] = {}
    for def_id in defs.all_ids():
        if only and not fnmatch.fnmatchcase(def_id, only):
            continue
        path = recipes / (def_id + ".json")
        res = rl.resolve(def_id, defs, assign)
        arch, params, notes = rl.choose_archetype(res, assign, recipes)
        warns: List[str] = list(notes)
        if not res.matched:
            warns.append("V-RCP-02: no assignments rule matches '%s' (stub uses '%s')" % (def_id, arch))
        if path.exists() and not rl.is_stub(path):
            out[def_id] = {"path": path, "text": None, "status": "kept", "warnings": warns}
            continue
        text = rl.dumps(rl.stub_recipe(res, arch, params))
        if not path.exists():
            status = "new"
        else:
            status = "same" if path.read_text(encoding="utf-8") == text else "changed"
        out[def_id] = {"path": path, "text": text, "status": status, "warnings": warns}
    return out


def stale_stubs(defs_ids: List[str], recipes: Path = rl.RECIPES) -> List[Path]:
    known = set(defs_ids)
    return [p for p in rl.recipe_files(recipes) if p.stem not in known and rl.is_stub(p)]


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 on drift")
    ap.add_argument("--prune", action="store_true", help="delete stubs of ids that are no longer defined")
    ap.add_argument("--only", metavar="PATTERN", help="fnmatch pattern on the def id")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    try:
        p = plan(only=args.only)
        defs = rl.collect_defs()
    except (OSError, ValueError, KeyError) as e:
        print("gen_recipe_stubs: %s" % e, file=sys.stderr)
        return 2
    counts = {"new": 0, "changed": 0, "same": 0, "kept": 0}
    for def_id, e in p.items():
        counts[e["status"]] += 1
        for w in e["warnings"]:
            print("warning: %s: %s" % (def_id, w), file=sys.stderr)
        if not args.check and e["status"] in ("new", "changed"):
            rl.write_if_changed(e["path"], e["text"])
    stale = stale_stubs(defs.all_ids())
    if args.prune and not args.check:
        for path in stale:
            path.unlink()
    drift = counts["new"] + counts["changed"] + (len(stale) if args.prune else 0)
    if not args.quiet:
        print("stubs: %d ids, %d new, %d changed, %d unchanged, %d hand-authored kept, %d stale%s" % (
            len(p), counts["new"], counts["changed"], counts["same"], counts["kept"], len(stale), " (pruned)" if args.prune and not args.check else ""))
    if args.check:
        return 1 if drift else 0
    if not args.only:
        import gen_recipe_index
        gen_recipe_index.main(["--quiet"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
