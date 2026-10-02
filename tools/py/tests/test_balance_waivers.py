"""HARD1: the shipped balance data passes `validate_balance.py --strict` (exit 0) with the documented waivers, waivers are well formed, never
hide an error and cannot go stale.  Run: python3 -m unittest discover -s tools/py/tests -p 'test_balance_waivers.py' -v"""
from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import validate_balance as vb  # noqa: E402

ROOT = HERE.parents[2]


def run_cli(*argv: str) -> tuple[int, str]:
    out = io.StringIO()
    with redirect_stdout(out), redirect_stderr(out):
        rc = vb.main(list(argv))
    return rc, out.getvalue()


class TestWaivers(unittest.TestCase):
    def test_shipped_data_is_strict_clean(self) -> None:
        rc, text = run_cli("--strict")
        self.assertEqual(rc, 0, text[-2000:])
        self.assertIn("0 warning(s)", text)

    def test_without_waivers_the_four_documented_warnings_remain(self) -> None:
        rc, text = run_cli("--strict", "--no-waivers")
        self.assertEqual(rc, 2, text[-1500:])
        self.assertIn("4 warning(s)", text)

    def test_waiver_file_is_documented(self) -> None:
        doc = json.loads(vb.WAIVERS.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(doc["waivers"]), 1)
        seen = set()
        for w in doc["waivers"]:
            self.assertTrue(w["rule"].startswith("V-"))
            self.assertGreater(len(w["reason"]), 30, w["id"])
            self.assertNotIn((w["rule"], w["id"]), seen)
            seen.add((w["rule"], w["id"]))

    def test_stale_waiver_is_reported(self) -> None:
        doc = json.loads(vb.WAIVERS.read_text(encoding="utf-8"))
        doc["waivers"].append({"rule": "V-RNG-02", "id": "units_nec.json:weapon.nec.nothing.damage", "reason": "does not exist, must be flagged as stale"})
        ctx, rep = vb.run(vb.ROOT / "game/data/balance", vb.ROOT / "game/data/bible/meridian_factions.json", True)
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "w.json"
            p.write_text(json.dumps(doc), encoding="utf-8")
            vb.apply_waivers(rep, p, check_stale=True)
        stale = [f for f in rep.findings if f.rule == "V-WAIVER-01"]
        self.assertEqual(len(stale), 1)
        self.assertEqual(rep.exit_code(), 2)

    def test_an_error_cannot_be_waived(self) -> None:
        ctx, rep = vb.run(vb.ROOT / "game/data/balance", vb.ROOT / "game/data/bible/meridian_factions.json", True)
        rep.add("V-SCH-01", "units_nec.json", "synthetic error", entity="x", field="y")
        doc = {"waivers": [{"rule": "V-SCH-01", "id": "units_nec.json:x.y", "reason": "an error must stay an error whatever the waiver says"}]}
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "w.json"
            p.write_text(json.dumps(doc), encoding="utf-8")
            vb.apply_waivers(rep, p, check_stale=False)
        self.assertEqual(rep.exit_code(), 1)


if __name__ == "__main__":
    unittest.main()
