#!/usr/bin/env python3
"""BAL3: list the signed fair-cost deviation (cost / fair cost - 1, negative = cheap = strong) of every combat unit sheet, per faction code.

  python3 tools/py/bal3_dev.py [--balance DIR] [--only nec,pd] [--min-abs 0]

Same formula as validate_balance V-RNG-02 (limit +-8 %). Shows the headroom a number change has before the validator clamps it.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "py"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--balance", default=str(ROOT / "game" / "data" / "balance"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.environ["MERIDIAN_BALANCE_GLOBAL"] = str(Path(a.balance) / "global.json")
    import balance_calc as bc  # noqa: WPS433
    only = {x for x in a.only.split(",") if x}
    for f in sorted(Path(a.balance).glob("units_*.json")):
        code = f.stem[len("units_"):]
        if only and code not in only:
            continue
        d = json.load(open(f))
        ws = {w["id"]: w for w in d.get("weapons", [])}
        for u in d["units"]:
            arch = bc.ARCH.get(u.get("archetype", ""))
            if arch is None or "cost_credits" not in u or "health" not in u:
                continue
            row = {"archetype": u["archetype"], "health": u["health"], "speed_cells_s": u.get("speed_cells_s", arch["speed_cells_s"]),
                   "vision_cells": u.get("vision_cells", arch["vision_cells"]), "cost_credits": u["cost_credits"],
                   "range_cells": u.get("range_cells", 0), "dps_vs_primary": u.get("dps_vs_primary", 0),
                   "sortie_avg_dps_vs_primary": u.get("sortie_avg_dps_vs_primary", u.get("dps_vs_primary", 0)), "abilities": list(u.get("abilities", []))}
            try:
                dev = bc.fair_cost_deviation(row) * 100
            except Exception:  # noqa: BLE001
                continue
            print("%-4s %-40s %-18s cost %5d bt %5.1f hp %5d dps %6.1f rng %4.1f dev %+5.1f%%" % (
                code, u["id"].split(".", 2)[-1], u["archetype"], u["cost_credits"], u.get("build_time_s", 0), u["health"], u.get("dps_vs_primary", 0),
                u.get("range_cells", 0), dev))
    return 0


if __name__ == "__main__":
    sys.exit(main())
