"""pck_list.py against the exported pck (skipped when no export exists): parses, nothing forbidden ships, (the full --project coverage check runs in export_proof.py, where the export is fresh)."""
from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PCK = ROOT / "builds" / "linux" / "MeridianFracture.pck"
sys.path.insert(0, str(ROOT / "tools" / "py"))

import pck_list  # noqa: E402


@unittest.skipUnless(PCK.exists(), "no exported build (python3 tools/py/export.py export linux)")
class TestPck(unittest.TestCase):
    def test_parse_and_audit(self) -> None:
        pk = pck_list.read_pck(str(PCK))
        self.assertGreater(len(pk["entries"]), 1000)
        r = subprocess.run([sys.executable, str(ROOT / "tools/py/pck_list.py"), str(PCK), "--audit"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("forbidden entries (tests/tools/prototypes/docs/Input/*.md): 0", r.stdout)

    def test_compare_with_itself(self) -> None:
        r = subprocess.run([sys.executable, str(ROOT / "tools/py/pck_list.py"), str(PCK), "--compare", str(PCK)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
