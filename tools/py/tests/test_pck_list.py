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


class TestProjectCoverage(unittest.TestCase):
    """project_files_missing(): which project files the audit expects in the pck."""

    def _tree(self, files: dict) -> str:
        import tempfile
        d = tempfile.mkdtemp(prefix="pck_cov_")
        self.addCleanup(__import__("shutil").rmtree, d, True)
        for rel, data in files.items():
            p = Path(d) / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        return d

    def test_present_files_are_not_missing(self) -> None:
        d = self._tree({"src/a.gd": b"x", "data/x.json": b"{}", "project.godot": b"", "src/a.gd.uid": b"u"})
        self.assertEqual(pck_list.project_files_missing(d, ["src/a.gd.remap", "data/x.json"]), [])

    def test_a_file_that_is_not_packed_is_reported(self) -> None:
        d = self._tree({"src/a.gd": b"x", "data/x.json": b"{}"})
        self.assertEqual(pck_list.project_files_missing(d, ["src/a.gd.remap"]), ["data/x.json"])

    def test_gdignore_folders_are_skipped_with_everything_below(self) -> None:
        """Godot never exports a folder with a .gdignore (the generated icon set lives in one)."""
        d = self._tree({"assets/icons/set/.gdignore": b"", "assets/icons/set/app_icon_16.png": b"p",
                        "assets/icons/set/deep/more.png": b"p", "assets/icons/app_icon.png": b"p"})
        self.assertEqual(pck_list.project_files_missing(d, ["assets/icons/app_icon.png"]), [])
        self.assertEqual(pck_list.project_files_missing(d, []), ["assets/icons/app_icon.png"])


if __name__ == "__main__":
    unittest.main()
