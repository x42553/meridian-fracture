#!/usr/bin/env python3
"""Writes game/tests/golden/convert_vectors.json: parity vectors for DefNumParse / DefConvert (spec data_balance 5.2.3, 10.1).

GDScript (tests/unit/test_data_convert.gd) asserts DefConvert == these vectors; the Python side computes them with
balance_lib/convert.py (the same formulas), so a mismatch on either side shows up as a test failure.
Usage: python3 tools/py/gen_convert_vectors.py [--check]   (--check exits 1 when the file on disk differs)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "py"))
from balance_lib import convert as C  # noqa: E402

OUT = ROOT / "game" / "tests" / "golden" / "convert_vectors.json"
TPS = C.TPS


class Reject(Exception):
    def __init__(self, rule: str) -> None:
        super().__init__(rule)
        self.rule = rule


def milli(v: float | int) -> int:
    """DefNumParse.milli: exact thousandths, or V-SCH-04."""
    if isinstance(v, float) and (v != v or abs(v) == float("inf")):
        raise Reject("V-SCH-04")
    m = v * 1000.0
    if abs(m) >= 1.0e13:
        raise Reject("V-SCH-04")
    r = int(abs(m) + 0.5)
    r = -r if m < 0 else r
    if abs(m - r) > 0.001 or abs(r) >= 1 << 40:
        raise Reject("V-SCH-04")
    return r


def milli_pct(v: float | int) -> int:
    r = milli(v)
    if r % 10 != 0:
        raise Reject("V-SCH-06")
    return r


FUNCS = {
    "milli": lambda x: milli(x),
    "cells_to_units": lambda x: C.rdiv(milli(x) * C.CELL, 1000),
    "cells_s_to_upt": lambda x: C.rdiv(milli(x) * C.CELL, 1000 * TPS),
    "s_to_ticks": lambda x: C.ceil_div(milli(x) * TPS, 1000),
    "s_to_mt": lambda x: milli(x) * TPS,
    "pct_to_bp": lambda x: C.rdiv(milli_pct(x) * 100, 1000),
    "deg_to_a": lambda x: C.rdiv(milli(x) * C.TURN, 360000),
    "deg_s_to_apt": lambda x: (max(1, C.rdiv(milli(x) * C.TURN, 360000 * TPS)) if x > 0 else 0),
    "crps_to_mcpt": lambda x: C.rdiv(milli(x), TPS),
    "pcts_to_bps": lambda x: C.rdiv(milli_pct(x) * 100, 1000),
}

INPUTS = {
    "milli": [0, 1, 1.5, 0.001, 27.5, 1.05, 1.051, -2.25, 0.0005, 1.0005, 1e12, 1099511627.775],
    "cells_to_units": [0, 7.0, 7.5, 0.45, 0.55, 1.0, 0.001, 0.0005, 1.5, 0.5, 6.25],
    "cells_s_to_upt": [0, 1.0, 2.0, 3.0, 3.2, 2.6, 8.0, 16.0, 0.001, 1.5, 7.0],
    "s_to_ticks": [0, 1.05, 1.051, 0.05, 0.06, 8, 15.5, 27.5, 45, 75, 1.2, 0.001, 30.5, 105.5, 0.0005],
    "s_to_mt": [0, 1.2, 0.25, 1.6, 1.0, 0.05, 0.001],
    "pct_to_bp": [0, 10, 12.5, 0.5, -15, 0.01, 0.005, 33.33, 100, 25],
    "deg_to_a": [0, 90, 360, 45, 22.5, 180, 0.001],
    "deg_s_to_apt": [0, 90, 120, 150, 180, 720, 0.001, 60, 45],
    "crps_to_mcpt": [0, 100, 20, 1, 3, 46],
    "pcts_to_bps": [0, 1, 2.5, 0.01, 0.005, 12.5],
}


def build() -> dict:
    vecs = []
    for fn, xs in INPUTS.items():
        for x in xs:
            v = {"fn": fn, "in": x}
            try:
                v["out"] = FUNCS[fn](x)
            except Reject as e:
                v["err"] = e.rule
            vecs.append(v)
    return {"schema": "meridian.test.convert_vectors/1", "generator": "tools/py/gen_convert_vectors.py", "vectors": vecs}


def main() -> int:
    text = json.dumps(build(), indent=1) + "\n"
    if "--check" in sys.argv:
        return 0 if OUT.exists() and OUT.read_text() == text else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(build()['vectors'])} vectors")
    return 0


if __name__ == "__main__":
    sys.exit(main())
