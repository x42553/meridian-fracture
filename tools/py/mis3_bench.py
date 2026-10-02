#!/usr/bin/env python3
"""MIS3 acceptance driver: plays shipped missions with the harness (game/tests/scenarios/mis3_run.gd) for several seeds and prints a table.
  python3 tools/py/mis3_bench.py op_napc [op_nec ...] [--driver bot|ai|idle] [--seeds 777,1234] [--minutes 25] [--json out.json]
Each run = one headless Godot process per (mission, seed): MIS3_RESULT lines are parsed."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(mission, driver, seed, minutes, extra):
    cmd = [str(ROOT / "tools" / "gd"), "run", "res://tests/scenarios/mis3_run.gd", "--", f"mission={mission}", f"driver={driver}",
           f"ai_seed={seed}", f"sim_seed={extra.get('sim_seed', -1)}", f"minutes={minutes}", "full=1"]
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=3000)
    out = None
    for line in (p.stdout + p.stderr).splitlines():
        if line.startswith("MIS3_RESULT"):
            out = json.loads(line[len("MIS3_RESULT "):])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("missions", nargs="+")
    ap.add_argument("--driver", default="bot")
    ap.add_argument("--seeds", default="777,1234")
    ap.add_argument("--minutes", type=int, default=25)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    rows = []
    for m in a.missions:
        for si, s in enumerate(a.seeds.split(",")):
            r = run(m, a.driver, int(s), a.minutes, {"sim_seed": 1000 + si * 77 if si else -1})
            if r is None:
                print(f"{m:14s} {a.driver:5s} seed={s:6s} NO RESULT")
                continue
            rows.append({"mission": m, "driver": a.driver, "seed": int(s), "outcome": r["outcome"], "seconds": r["seconds"], "wall_ms": r.get("wall_ms"),
                         "errors": r["errors"], "objectives": r["objectives"]})
            prim = {k: v for k, v in r["objectives"].items() if not k.startswith(("live_", "done_"))}
            print(f"{m:14s} {a.driver:5s} seed={s:6s} {r['outcome']:8s} {r['seconds']:5d}s wall={r.get('wall_ms')}ms {prim} {r['errors'] or ''}")
    if a.json:
        Path(a.json).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
