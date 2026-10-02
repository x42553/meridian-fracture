#!/usr/bin/env python3
"""VQ2A: contact sheets of every subfaction's unique units next to the unit they replace.

For each of the 24 subfactions one PNG (docs/shots/vq2/sub_<faction>_<sub>.png): one row per unique unit with three cells,
(1) the replaced vanilla unit in the vanilla style, (2) the same unit in the subfaction style, (3) the unique unit in the subfaction
style. Then one vanilla unit set per faction (docs/shots/vq2/van_<faction>.png). Needs a project root with tools/gd.
  python3 tools/py/vq2_subfaction_sheets.py [--only napc] [--out docs/shots/vq2]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FACTIONS = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]


def _layout(items, cols):
    """Cell size (m) and camera distance from the largest archetype among the items: ships need much more room than tanks."""
    big = 0
    for it in items:
        rid = it.split("@")[0]
        try:
            arch = json.loads((ROOT / "game/data/recipes" / f"{rid}.json").read_text()).get("archetype", "")
        except OSError:
            arch = ""
        big = max(big, 3 if arch.startswith("ship_") else 2 if arch.startswith(("air_", "veh_walker", "veh_hovercarrier")) else 1)
    cell = {1: 7.5, 2: 10.0, 3: 18.0}[big]
    if cols == 5:
        cell *= 0.9
    rows = (len(items) + cols - 1) // cols
    cam = max(cols * cell * 0.95, rows * cell * 1.7, 24.0)
    return cell, int(cam)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default="docs/shots/vq2")
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--list", action="store_true", help="print the plan (rows) and exit")
    a = ap.parse_args()
    data = json.loads((ROOT / "game/data/bible/meridian_factions.json").read_text())
    units = data["units"]
    rosters = data["rosters"]
    recipes = {p.stem for p in (ROOT / "game/data/recipes").glob("unit.*.json")}
    out = ROOT / a.out
    out.mkdir(parents=True, exist_ok=True)
    jobs = []
    for fac in FACTIONS:
        if a.only and a.only != fac:
            continue
        vanilla = sorted(u for u in units if u.startswith(f"unit.{fac}.") and units[u].get("roster_class") != "unique_subfaction" and u in recipes)
        jobs.append((f"van_{fac}", [f"{u}@{fac}" for u in vanilla], 5, f"vanilla {fac}: {len(vanilla)} units"))
        for rid, r in rosters.items():
            if not rid.startswith(f"roster.{fac}.") or r.get("kind") == "vanilla":
                continue
            sub = rid.split(".")[2]
            items = []
            for rep in r.get("delta", {}).get("replacements", []):
                old = rep.get("replaced_unit_id")
                new = rep.get("replacement_unit_id") or rep.get("unique_unit_id")
                if not old or not new:
                    continue
                items += [f"{old}@{fac}", f"{old}@{fac}.{sub}", f"{new}@{fac}.{sub}"]
            jobs.append((f"sub_{fac}_{sub}", items, 3, f"{fac}.{sub}: {len(items) // 3} unique units"))
    for name, items, cols, desc in jobs:
        print(name, desc)
        if a.list or not items:
            continue
        cell, cam = _layout(items, cols)
        cmd = [str(ROOT / "tools/gd"), "shot", "res://tests/visual/def_sheet.tscn", str(out / f"{name}.png"), "--size", a.size, "--frames", "30",
               "--allow-errors", "--", "--items=" + ",".join(items), f"--cols={cols}", f"--cell={cell}", "--pitch=52", "--cam=%d" % cam,
               "--labels=0", "--face=140", "--pose=rest"]
        rc = subprocess.run(cmd, capture_output=True, text=True).returncode
        if rc not in (0, 3):
            print("  FAILED rc", rc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
