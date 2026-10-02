"""Release engineering: version stamping (tools/py/version.py) and the app icon outputs (tools/py/gen_app_icon.py)."""
from __future__ import annotations

import re
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "py"))
import version  # noqa: E402

ICONS = ROOT / "game" / "assets" / "icons"


def png_size(p: Path) -> tuple:
    d = p.read_bytes()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", p
    return struct.unpack(">II", d[16:24])


class TestVersion(unittest.TestCase):
    def test_repo_is_consistent(self) -> None:
        self.assertEqual(version.check(), [])

    def test_semver_and_windows_version(self) -> None:
        self.assertTrue(version.SEMVER.match("0.1.0"))
        self.assertTrue(version.SEMVER.match("1.2.3-rc.1"))
        self.assertFalse(version.SEMVER.match("1.2"))
        self.assertFalse(version.SEMVER.match("01.2.3"))
        self.assertEqual(version.win_version("0.1.0"), "0.1.0.0")
        self.assertEqual(version.win_version("2.10.3-rc.1"), "2.10.3.0")

    def test_runtime_reads_project_setting(self) -> None:
        # src/app/app_info.gd reads application/config/version: the same key version.py stamps
        self.assertIn("ProjectSettings.get_setting(\"application/config/version\"", (ROOT / "game/src/app/app_info.gd").read_text())

    def test_bump_and_drift_in_a_copy(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for rel in ("VERSION", "game/project.godot", "game/export_presets.cfg", "README.md", "CHANGELOG.md"):
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / rel, root / rel)
            saved = (version.ROOT, version.PROJECT, version.PRESETS, version.README, version.CHANGELOG)
            try:
                version.ROOT = root
                version.PROJECT, version.PRESETS = root / "game/project.godot", root / "game/export_presets.cfg"
                version.README, version.CHANGELOG = root / "README.md", root / "CHANGELOG.md"
                self.assertEqual(version.check(), [])
                self.assertEqual(version.bump("minor"), "0.2.0")
                drift = version.check()
                self.assertEqual(len(drift), 1, drift)  # only the CHANGELOG section is missing
                self.assertIn("CHANGELOG", drift[0])
                self.assertIn('config/version="0.2.0"', version.PROJECT.read_text())
                self.assertIn('application/file_version="0.2.0.0"', version.PRESETS.read_text())
                self.assertIn("version-0.2.0-blue", version.README.read_text())
                self.assertIn("meridian-fracture_0.2.0_amd64.deb", version.README.read_text())
                (root / "game/project.godot").write_text(version.PROJECT.read_text().replace('config/version="0.2.0"', 'config/version="0.1.9"'))
                self.assertTrue(any("project.godot" in m for m in version.check()))
                self.assertEqual(version.bump("1.0.0-rc.1"), "1.0.0-rc.1")
                self.assertIn("version-1.0.0--rc.1-blue", version.README.read_text())
            finally:
                version.ROOT, version.PROJECT, version.PRESETS, version.README, version.CHANGELOG = saved

    def test_deb_version_reader(self) -> None:
        import package_linux
        with tempfile.TemporaryDirectory() as td:
            deb = Path(td) / "x.deb"
            package_linux.build_deb(deb, "9.8.7", {"opt/meridian-fracture/a": (b"x", 0o644)})
            self.assertEqual(version.deb_version(deb), "9.8.7")

    def test_package_scripts_default_to_version_file(self) -> None:
        for name in ("package_linux.py", "package_windows.py", "package_macos.py"):
            self.assertIn("version.read_version()", (ROOT / "tools/py" / name).read_text(), name)


class TestIconOutputs(unittest.TestCase):
    def test_master_and_set(self) -> None:
        self.assertEqual(png_size(ICONS / "app_icon.png"), (1024, 1024))
        for n in (16, 32, 48, 64, 128, 256, 512):
            self.assertEqual(png_size(ICONS / "set" / f"app_icon_{n}.png"), (n, n))
        self.assertTrue((ICONS / "set" / ".gdignore").exists(), "the PNG set must not be imported into the game")

    def test_ico(self) -> None:
        d = (ICONS / "app_icon.ico").read_bytes()
        reserved, typ, count = struct.unpack("<HHH", d[:6])
        self.assertEqual((reserved, typ), (0, 1))
        sizes = set()
        for i in range(count):
            w, h = d[6 + 16 * i], d[7 + 16 * i]
            sizes.add(w or 256)
        self.assertEqual(sizes, {16, 24, 32, 48, 64, 128, 256})

    def test_icns(self) -> None:
        d = (ICONS / "app_icon.icns").read_bytes()
        self.assertEqual(d[:4], b"icns")
        self.assertEqual(struct.unpack(">I", d[4:8])[0], len(d))
        if sys.platform == "darwin" and shutil.which("iconutil"):
            import subprocess
            with tempfile.TemporaryDirectory() as td:
                r = subprocess.run(["iconutil", "-c", "iconset", str(ICONS / "app_icon.icns"), "-o", str(Path(td) / "i.iconset")], capture_output=True)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertGreaterEqual(len(list((Path(td) / "i.iconset").glob("*.png"))), 6)

    def test_wired_into_project_and_presets(self) -> None:
        proj = (ROOT / "game/project.godot").read_text()
        self.assertIn('config/icon="res://assets/icons/app_icon.png"', proj)
        pre = (ROOT / "game/export_presets.cfg").read_text()
        self.assertIn('application/icon="res://assets/icons/app_icon.icns"', pre)
        self.assertIn('application/icon="res://assets/icons/app_icon.ico"', pre)
        self.assertRegex(pre, r"application/modify_resources=false")  # no rcedit/wine on the build host: the .ico ships beside the exe
        for res in re.findall(r'"res://(assets/icons/[^"]+)"', proj + pre):
            self.assertTrue((ROOT / "game" / res).exists(), res)

    def test_generator_matches_committed_master_when_pillow_is_present(self) -> None:
        try:
            import PIL  # noqa: F401
        except ImportError:
            self.skipTest("Pillow not installed")
        import gen_app_icon
        self.assertEqual(gen_app_icon.main.__module__, "gen_app_icon")
        a = gen_app_icon.render_master(256)
        from PIL import Image
        b = Image.open(ICONS / "set" / "app_icon_256.png").convert("RGB")
        diff = sum(abs(x - y) for p, q in zip(a.getdata(), b.getdata()) for x, y in zip(p, q)) / (256 * 256 * 3)
        self.assertLess(diff, 2.0)  # same emblem (resampling differs slightly: 1024 -> 256 vs direct 256)

    def test_linux_package_icon_is_the_emblem(self) -> None:
        import package_linux
        self.assertEqual((package_linux.make_icon(256)), (ICONS / "set" / "app_icon_256.png").read_bytes())


class TestDebInstallTest(unittest.TestCase):
    def test_package_folder_is_mounted_by_absolute_path(self) -> None:
        """CI called test_deb with builds/packages/x.deb relative to the repo root; docker took the relative -v source for a volume name and failed."""
        import contextlib
        import io
        import os
        import subprocess
        from unittest import mock

        import package_linux
        seen: list = []

        def fake_run(cmd, **kw):
            seen.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        cwd = os.getcwd()
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "builds" / "packages").mkdir(parents=True)
            (Path(d) / "builds" / "packages" / "x.deb").write_bytes(b"")
            os.chdir(d)
            try:
                with mock.patch.object(package_linux.subprocess, "run", fake_run), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(package_linux.test_deb(Path("builds/packages/x.deb"), images=("debian:12-slim",)), 0)
            finally:
                os.chdir(cwd)
        self.assertEqual(len(seen), 1)
        host = seen[0][seen[0].index("-v") + 1].rsplit(":/pkg", 1)[0]
        self.assertTrue(os.path.isabs(host), host)


@unittest.skipUnless(sys.platform == "darwin" and (ROOT / "builds/macos/MeridianFracture.app").is_dir(), "needs an exported macOS app on a macOS host")
class TestMacosApp(unittest.TestCase):
    def test_exported_app_has_icon_version_and_signature(self) -> None:
        import package_macos
        self.assertEqual(package_macos.verify_app(package_macos.APP, version.read_version()), [])
        res = package_macos.APP / "Contents" / "Resources"
        self.assertEqual((res / "icon.icns").read_bytes(), (ICONS / "app_icon.icns").read_bytes())


if __name__ == "__main__":
    unittest.main()
