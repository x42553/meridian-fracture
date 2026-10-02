"""Sanity checks for .github/workflows/build.yml that need no network: every script / scenario it calls exists, and the test shards
(case-insensitive substrings of '<dir>/<file>.gd::<method>') cover every test file exactly the way `gd test <filters>` selects them."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
YML = ROOT / ".github" / "workflows" / "build.yml"


class TestWorkflow(unittest.TestCase):
    def setUp(self) -> None:
        self.text = YML.read_text(encoding="utf-8")

    def test_yaml_parses_when_pyyaml_is_available(self) -> None:
        try:
            import yaml  # type: ignore
        except ImportError:
            self.skipTest("PyYAML not installed")
        doc = yaml.safe_load(self.text)
        self.assertIn("jobs", doc)
        for job in ("tools", "test", "proofs", "determinism", "export", "debian", "deb", "soak"):
            self.assertIn(job, doc["jobs"])

    def test_no_tabs_and_lf_only(self) -> None:
        self.assertNotIn("\t", self.text)
        self.assertNotIn("\r", self.text)

    def test_called_python_tools_exist(self) -> None:
        for name in set(re.findall(r"tools/py/([A-Za-z0-9_]+\.py)", self.text)):
            self.assertTrue((ROOT / "tools" / "py" / name).exists(), name)

    def test_scenarios_exist(self) -> None:
        loops = re.findall(r"for s in ([a-z0-9_ ]+); do", self.text)
        self.assertTrue(loops)
        for loop in loops:
            for s in loop.split():
                self.assertTrue((ROOT / "game" / "tests" / "scenarios" / f"{s}.gd").exists(), s)

    def test_shards_cover_every_test_file_once(self) -> None:
        filters = re.findall(r'filters: "([^"]+)"', self.text)
        self.assertGreaterEqual(len(filters), 3)
        tests = ROOT / "game" / "tests"
        files = sorted(p.relative_to(tests).as_posix() for p in tests.rglob("test_*.gd") if p.parent != tests)  # tests/test_ctx.gd is the context class, not a suite
        self.assertGreater(len(files), 200)
        for rel in files:
            hits = [i for i, f in enumerate(filters) if any(tok.lower() in (rel + "::x").lower() for tok in f.split())]
            self.assertEqual(len(hits), 1, f"{rel} is matched by shards {hits}: every test file must be in exactly one shard")


if __name__ == "__main__":
    unittest.main()
