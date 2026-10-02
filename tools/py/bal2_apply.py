#!/usr/bin/env python3
"""BAL2: apply numeric edits to the balance unit / weapon sheets (stdlib only). Used for experiment variants (copy of the balance
directory) and to apply the final numbers to game/data/balance.

  python3 tools/py/bal2_apply.py --src game/data/balance --dst OUTDIR  'unit.napc.*:health*=1.10'  'weapon.napc.*:damage*=1.10' ...
  python3 tools/py/bal2_apply.py --inplace  'unit.han.ox_tank:health=900'

Edit syntax: `<id glob>:<field><op><value>` with op one of `*=` (multiply), `+=`, `=`. Ids starting with `unit.` edit units, `weapon.` weapons
(fnmatch globs; `unit.napc.*` also matches unique units of the faction's sub-rosters). Fields: units cost_credits build_time_s health
speed_cells_s vision_cells radius_cells; weapons damage reload_s range_cells hits_per_volley. Integer fields are rounded to int, others
to 2 decimals; cost is rounded to 5 credits (below 1000) or 25. When a weapon's damage / reload changes, `dps_vs_primary` of the
units that carry it as first weapon follows proportionally. `--dst` is created as a full copy of `--src` first. Prints every change.
"""
from __future__ import annotations

import argparse
import fnmatch
import glob
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INT_FIELDS = {"cost_credits", "health", "damage", "hits_per_volley"}
EDIT_RE = re.compile(r"^(?P<glob>[^:]+):(?P<field>[a-z_]+)(?P<op>\*=|\+=|=)(?P<val>-?[0-9.]+)$")


def apply(v, op, x):
    if op == "*=":
        return v * x
    if op == "+=":
        return v + x
    return x


def fix(field, v):
    if field == "cost_credits":
        return int(round(v / (5 if v < 1000 else 25)) * (5 if v < 1000 else 25))
    if field in INT_FIELDS:
        return int(round(v))
    return round(v, 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(ROOT / "game" / "data" / "balance"))
    ap.add_argument("--dst")
    ap.add_argument("--inplace", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("edits", nargs="+")
    a = ap.parse_args()
    if not a.inplace and not a.dst:
        ap.error("--dst or --inplace")
    src = Path(a.src)
    dst = src
    if not a.inplace:
        dst = Path(a.dst)
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    edits = []
    for e in a.edits:
        m = EDIT_RE.match(e)
        if not m:
            ap.error("bad edit: " + e)
        edits.append((m["glob"], m["field"], m["op"], float(m["val"])))
    changed = 0
    for f in sorted(glob.glob(str(dst / "units_*.json"))):
        d = json.load(open(f))
        dirty = False
        wmap = {w["id"]: w for w in d.get("weapons", [])}
        for pat, field, op, val in edits:
            if pat.startswith("weapon."):
                for w in d.get("weapons", []):
                    if fnmatch.fnmatch(w["id"], pat) and field in w:
                        old = w[field]
                        w[field] = fix(field, apply(old, op, val))
                        if w[field] != old:
                            changed += 1
                            dirty = True
                            if not a.quiet:
                                print("%-44s %-16s %s -> %s" % (w["id"], field, old, w[field]))
                            if field in ("damage", "reload_s"):
                                ratio = (w[field] / old) if field == "damage" else (old / w[field])
                                for u in d["units"]:
                                    if u.get("weapons") and u["weapons"][0] == w["id"] and "dps_vs_primary" in u:
                                        u["dps_vs_primary"] = round(u["dps_vs_primary"] * ratio, 1)
                            if field == "range_cells":
                                for u in d["units"]:
                                    if u.get("weapons") and u["weapons"][0] == w["id"] and "range_cells" in u:
                                        u["range_cells"] = w[field]
            else:
                for u in d["units"]:
                    if fnmatch.fnmatch(u["id"], pat) and field in u:
                        old = u[field]
                        u[field] = fix(field, apply(old, op, val))
                        if u[field] != old:
                            changed += 1
                            dirty = True
                            if not a.quiet:
                                print("%-44s %-16s %s -> %s" % (u["id"], field, old, u[field]))
        if dirty:
            with open(f, "w") as fh:
                json.dump(d, fh, indent=2, ensure_ascii=False)
                fh.write("\n")
    print("%d values changed in %s" % (changed, dst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
