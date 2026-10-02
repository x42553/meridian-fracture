"""End-to-end tests of tools/gd against the real Godot binary, in an isolated throw-away project (GD_ROOT).
Set GD_SKIP_GUI=1 to skip the screenshot test on machines without a display.
Run: python3 -m unittest discover -s tools/py/tests -v"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = HERE.parent
REPO = PY.parents[1]
GD = REPO / "tools" / "gd"
sys.path.insert(0, str(PY))

from gdlib import env  # noqa: E402

# A throw-away mini project: the real project.godot minus every autoload except DevShot (the others pull in most of src/), the standalone
# toolsmith files and the sample tests. Other modules' work in progress can never break these tests.
COPY = ["src/app/dev_shot.gd", "tests/runner.gd", "tests/test_ctx.gd", "tests/harness",
        "tests/fixtures/fixture_failing.gd", "tests/fixtures/fixture_async.gd", "tests/fixtures/fixture_engine_error.gd",
        "tests/fixtures/fixture_legacy_run.gd", "tests/fixtures/fixture_needs_args.gd", "tests/fixtures/run_args_demo.gd",
        "tests/unit/test_sample_basic.gd", "tests/unit/test_sample_ctx.gd", "tests/unit/test_runner_detects_failure.gd",
        "tests/scenarios/xplat_int_math.gd", "tests/scenarios/shot_demo.gd", "tests/scenarios/shot_demo.tscn"]


def mini_project_godot() -> str:
    out, section = [], ""
    for line in (REPO / "game" / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            section = line
        if section == "[autoload]" and "=" in line and not line.startswith("DevShot="):
            continue
        if line.startswith(("run/main_scene=", "config/icon=")):  # the mini project has neither the scene nor the icon file
            continue
        out.append(line)
    return "\n".join(out) + "\n"


@unittest.skipUnless(env.godot_bin().exists(), "Godot binary not available")
class TestGdCli(unittest.TestCase):
    tmp: Path
    root: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="gd-cli-"))
        cls.root = cls.tmp
        game = cls.root / "game"
        game.mkdir(parents=True)
        (game / "project.godot").write_text(mini_project_godot(), encoding="utf-8")
        for rel in COPY:
            src = REPO / "game" / rel
            dst = game / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir():
                shutil.copytree(src, dst, ignore=shutil.ignore_patterns(".godot"))
            else:
                shutil.copy2(src, dst)
        r = cls.gd("import")
        assert r.returncode == 0, r.stdout + r.stderr

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def gd(cls, *args: str, timeout: float = 180) -> subprocess.CompletedProcess:
        e = dict(os.environ, GD_ROOT=str(cls.root))
        return subprocess.run([sys.executable, str(GD), *args], capture_output=True, text=True, env=e, timeout=timeout)

    def write(self, rel: str, text: str) -> Path:
        p = self.root / "game" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    # -- test runner ---------------------------------------------------------------------------------
    def test_green_suite_passes_and_prints_summary(self) -> None:
        r = self.gd("test")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS  unit/test_sample_basic.gd::test_integer_math_is_exact", r.stdout)
        self.assertRegex(r.stdout, r"== \d+ files, \d+ tests in [\d.]+ s: \d+ passed, 0 failed, 0 errors")

    def test_failing_test_makes_gd_test_exit_1(self) -> None:
        r = self.gd("test", "--file", "tests/fixtures/fixture_failing.gd")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL  fixtures/fixture_failing.gd::test_fails_check", r.stdout)
        self.assertIn("fixture_failing.gd:12: check failed: deliberate failure", r.stdout)
        self.assertIn("2 failed, 1 errors, 1 skipped", r.stdout)

    def test_engine_errors_inside_tests_are_attributed(self) -> None:
        r = self.gd("test", "--file", "tests/fixtures/fixture_engine_error.gd")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("ERROR fixtures/fixture_engine_error.gd::test_runtime_error_is_reported", r.stdout)
        self.assertIn("Nonexistent function 'no_such_method' in base 'Nil'", r.stdout)
        self.assertIn("ERROR fixtures/fixture_engine_error.gd::test_push_error_is_reported", r.stdout)
        self.assertIn("PASS  fixtures/fixture_engine_error.gd::test_declared_errors_are_accepted", r.stdout)

    def test_empty_selection_is_a_failure_unless_allowed(self) -> None:
        self.assertEqual(self.gd("test", "zzz_matches_nothing").returncode, 2)
        self.assertEqual(self.gd("test", "zzz_matches_nothing", "--allow-empty").returncode, 0)

    def test_filter_list_and_json_report(self) -> None:
        listing = self.gd("test", "sample_ctx", "--list")
        self.assertEqual(listing.returncode, 0)
        self.assertEqual(len([l for l in listing.stdout.splitlines() if "::" in l]), 4)
        out = self.tmp / "report.json"
        r = self.gd("test", "sample_basic", "--json", str(out))
        self.assertEqual(r.returncode, 0)
        import json
        data = json.loads(out.read_text())
        self.assertEqual(data["counts"]["failed"], 0)
        self.assertEqual(data["counts"]["tests"], 4)

    def test_new_class_name_needs_no_manual_import(self) -> None:
        self.write("src/core/brand_new_thing.gd", "class_name BrandNewThing\nextends RefCounted\n\nfunc answer() -> int:\n\treturn 42\n")
        self.write("tests/unit/test_brand_new.gd", "extends RefCounted\n\nfunc test_uses_new_global(t: TestCtx) -> void:\n\tt.eq(BrandNewThing.new().answer(), 42)\n")
        r = self.gd("test", "brand_new")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS  unit/test_brand_new.gd::test_uses_new_global", r.stdout)

    # -- check ---------------------------------------------------------------------------------------
    def test_check_detects_syntax_type_and_lint_errors_then_recovers(self) -> None:
        broken = self.write("src/app/tmp_broken.gd", "extends RefCounted\n\nfunc f() -> int:\n\tvar x: int = \"abc\"\n\treturn undefined_symbol + x\n\nfunc g(\n")
        r = self.gd("check", "--fast")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("game/src/app/tmp_broken.gd:7: error: Parse Error: Expected closing", r.stdout)
        broken.write_text("extends RefCounted\n\nfunc f() -> int:\n\tvar x: int = \"abc\"\n\treturn undefined_symbol + x\n")
        r = self.gd("check", "--fast")
        self.assertEqual(r.returncode, 1)
        self.assertIn("tmp_broken.gd:4: error: Parse Error: Cannot assign a value of type", r.stdout)
        self.assertIn("tmp_broken.gd:5: error: Parse Error: Identifier \"undefined_symbol\" not declared", r.stdout)
        broken.unlink()
        lint_bad = self.write("src/sim/sim_lint_bad.gd", "class_name SimLintBad\nextends RefCounted\n\nvar a: float = randf()\n")
        r = self.gd("check", "--fast")
        self.assertEqual(r.returncode, 1)
        self.assertIn("game/src/sim/sim_lint_bad.gd:4: L003", r.stdout)
        lint_bad.unlink()
        r = self.gd("check", "--fast")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("RESULT: OK", r.stdout)

    def test_check_warnings_are_reported_and_strict_fails(self) -> None:
        w = self.write("src/app/tmp_warn.gd", "extends RefCounted\n\nfunc f(unused_param: int) -> void:\n\tvar unused_local: int = 1\n")
        try:
            r = self.gd("check", "--warnings")
            self.assertEqual(r.returncode, 0, r.stdout)
            self.assertIn("tmp_warn.gd:3: warning[unused_parameter]", r.stdout)
            self.assertIn("tmp_warn.gd:4: warning[unused_variable]", r.stdout)
            self.assertEqual(self.gd("check", "--strict").returncode, 1)
            self.assertEqual(self.gd("check", "--fast").returncode, 0)
        finally:
            w.unlink()

    def test_check_scoped_to_a_path(self) -> None:
        bad = self.write("src/app/tmp_scoped_bad.gd", "extends RefCounted\nfunc g(\n")
        try:
            self.assertEqual(self.gd("check", "--fast", "src/app").returncode, 1)
            self.assertEqual(self.gd("check", "--fast", "tests/harness", "--no-lint").returncode, 0)
        finally:
            bad.unlink()

    def test_lint_only_needs_no_godot(self) -> None:
        r = self.gd("check", "--lint-only")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    # -- run -----------------------------------------------------------------------------------------
    def test_run_passes_user_args_and_exit_code(self) -> None:
        r = self.gd("run", "tests/fixtures/run_args_demo.gd", "--", "--foo=1", "bar", "--exit=7")
        self.assertEqual(r.returncode, 7, r.stdout + r.stderr)
        self.assertIn("ARGS=--foo=1,bar,--exit=7", r.stdout)

    def test_run_turns_engine_errors_into_failure(self) -> None:
        self.write("tests/fixtures/tmp_pusherr.gd", "extends SceneTree\nfunc _initialize() -> void:\n\tpush_error(\"boom\")\n\tquit(0)\n")
        r = self.gd("run", "tests/fixtures/tmp_pusherr.gd")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertEqual(self.gd("run", "tests/fixtures/tmp_pusherr.gd", "--allow-errors").returncode, 0)

    def test_run_kills_a_script_that_hangs_after_a_runtime_error(self) -> None:
        self.write("tests/fixtures/tmp_hang.gd", "extends SceneTree\nfunc _initialize() -> void:\n\tvar n: Variant = null\n\tn.explode()\n\tquit(0)\n")
        r = self.gd("run", "tests/fixtures/tmp_hang.gd", "--stall", "3", timeout=60)
        self.assertEqual(r.returncode, 124, r.stdout + r.stderr)
        self.assertIn("STALLED", r.stderr)

    def test_hard_timeout(self) -> None:
        self.write("tests/fixtures/tmp_forever.gd", "extends SceneTree\nfunc _initialize() -> void:\n\tpass\n")
        r = self.gd("run", "tests/fixtures/tmp_forever.gd", "--timeout", "3", timeout=60)
        self.assertEqual(r.returncode, 124)
        self.assertIn("TIMEOUT", r.stderr)

    # -- shot / docs ---------------------------------------------------------------------------------
    @unittest.skipIf(os.environ.get("GD_SKIP_GUI") or (sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and not shutil.which("xvfb-run")),
                     "needs a display")
    def test_shot_writes_a_png_of_the_requested_size(self) -> None:
        out = self.tmp / "boot.png"
        r = self.gd("shot", "res://tests/scenarios/shot_demo.tscn", str(out), "--frames", "3", "--size", "320x180")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        data = out.read_bytes()
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        import struct
        self.assertEqual(struct.unpack(">II", data[16:24]), (320, 180))
        self.assertEqual(r.stdout.strip().splitlines()[-1], str(out.resolve()))

    @unittest.skipIf(os.environ.get("GD_SKIP_GUI") or (sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and not shutil.which("xvfb-run")),
                     "needs a display")
    def test_shot_of_a_3d_scene_with_user_args(self) -> None:
        plain, labelled = self.tmp / "demo_a.png", self.tmp / "demo_b.png"
        for out, label in ((plain, "aaa"), (labelled, "a much longer label text")):
            r = self.gd("shot", "res://tests/scenarios/shot_demo.tscn", str(out), "--frames", "4", "--size", "320x180", "--quiet", "--", f"--label={label}")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertGreater(plain.stat().st_size, 3000, "a lit 3D scene is not a blank frame")
        self.assertNotEqual(plain.read_bytes(), labelled.read_bytes(), "the --label user arg reached the scene")

    def test_shot_of_a_missing_scene_fails(self) -> None:
        out = self.tmp / "nothing.png"
        r = self.gd("shot", "res://src/app/does_not_exist.tscn", str(out), "--frames", "1")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(out.exists())

    def test_docs(self) -> None:
        r = self.gd("docs", "Node2D", "position")
        self.assertEqual(r.returncode, 0)
        self.assertIn("position: Vector2", r.stdout)
        self.assertEqual(self.gd("docs", "Nod").returncode, 1)

    def test_determinism_scenario_is_stable(self) -> None:
        a = self.gd("run", "tests/scenarios/xplat_int_math.gd")
        b = self.gd("run", "tests/scenarios/xplat_int_math.gd")
        self.assertEqual(a.returncode, 0, a.stdout + a.stderr)
        self.assertEqual(a.stdout, b.stdout)
        self.assertIn("HASH tick=200 ", a.stdout)


if __name__ == "__main__":
    unittest.main()
