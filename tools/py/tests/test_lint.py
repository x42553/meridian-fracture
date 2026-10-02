"""Unit tests for tools/py/lint.py. Run: python3 -m unittest discover -s tools/py/tests -v"""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import lint  # noqa: E402


class LintCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.game = self.root / "game"
        (self.game).mkdir()
        (self.game / "project.godot").write_text("config_version=5\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, rel: str, text: str = "") -> Path:
        p = self.game / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def run_lint(self, rules=None) -> lint.Report:
        return lint.run(self.root, self.game, rules=set(rules) if rules else None)

    def found(self, rule=None):
        return [(v.path, v.line, v.rule) for v in self.run_lint([rule] if rule else None).violations]

    def rules_in(self, rel: str, rule: str):
        return [v for v in self.run_lint([rule]).violations if v.path == f"game/{rel}"]


class TestL001Paths(LintCase):
    def test_existing_and_missing_paths(self) -> None:
        self.write("src/core/a.gd", 'extends RefCounted\nconst A := preload("res://src/core/b.gd")\nconst M := preload("res://src/core/missing.gd")\n')
        self.write("src/core/b.gd", "extends RefCounted\n")
        v = self.rules_in("src/core/a.gd", "L001")
        self.assertEqual([x.line for x in v], [3])
        self.assertIn("missing.gd", v[0].message)

    def test_case_mismatch_is_reported(self) -> None:
        self.write("src/sim/sim_world.gd", "extends RefCounted\n")
        self.write("src/core/a.gd", 'var p = "res://src/Sim/sim_world.gd"\nvar q = "res://src/sim/Sim_World.gd"\n')
        v = self.rules_in("src/core/a.gd", "L001")
        self.assertEqual(len(v), 2)
        self.assertTrue(all("case" in x.message for x in v), [x.message for x in v])

    def test_placeholders_directories_and_special_prefixes(self) -> None:
        self.write("data/balance/x.json", "{}")
        self.write("src/core/a.gd", 'a = "res://data/balance/%s.json"\nb = "res://data/balance/"\nc = "res://nodir/%s.json"\n'
                   'd = "uid://abc"\ne = "res://.godot/imported/x.ctex"\nf = "res://"\n')
        v = self.rules_in("src/core/a.gd", "L001")
        self.assertEqual([x.line for x in v], [3], [x.message for x in v])

    def test_comments_are_ignored_but_scenes_and_project_are_checked(self) -> None:
        self.write("src/core/a.gd", '# see res://docs/nothing.md\nvar x := 1 # res://also/nothing\n')
        self.write("scenes/a.tscn", '[ext_resource type="Script" path="res://src/core/gone.gd" id="1"]\n')
        self.write("project.godot", 'config_version=5\n[autoload]\nDevShot="*res://src/app/none.gd"\n')
        self.assertEqual(self.rules_in("src/core/a.gd", "L001"), [])
        self.assertEqual(len(self.rules_in("scenes/a.tscn", "L001")), 1)
        self.assertEqual(len(self.rules_in("project.godot", "L001")), 1)


class TestL002Names(LintCase):
    def test_bad_names(self) -> None:
        for rel in ("src/core/BadName.gd", "src/core/has space.gd", "src/core/con.gd", "assets/AUX.txt", "src/BadDir/ok.gd",
                    "src/core/hy-phen.gd", "src/core/ünï.gd", "src/core/lpt3.tres"):
            self.write(rel, "x")
        got = {v.path for v in self.run_lint(["L002"]).violations}
        for rel in ("src/core/BadName.gd", "src/core/has space.gd", "src/core/con.gd", "assets/AUX.txt", "src/BadDir", "src/core/hy-phen.gd",
                    "src/core/ünï.gd", "src/core/lpt3.tres"):
            self.assertIn(f"game/{rel}", got, rel)

    def test_good_names_and_allowed_uppercase(self) -> None:
        for rel in ("src/core/fp.gd", "src/core/fp.gd.uid", "data/bible/README.md", "assets/fonts/OFL.txt", "assets/x/.gdignore",
                    "src/core/console.gd", "src/core/com10.gd", "src/core/a_b_2.tscn"):
            self.write(rel, "x")
        self.assertEqual(self.run_lint(["L002"]).violations, [])

    def test_path_length(self) -> None:
        deep = "/".join(["d" * 20] * 7) + "/file.gd"
        self.write(deep, "x")
        self.assertTrue(any("chars long" in v.message for v in self.run_lint(["L002"]).violations))


class TestL003Determinism(LintCase):
    def flagged_lines(self, rel: str, src: str):
        self.write(rel, src)
        return sorted({v.line for v in self.rules_in(rel, "L003")})

    def test_bans_in_sim(self) -> None:
        src = ("extends RefCounted\n"                       # 1
               "var a: int = randi()\n"                      # 2 rng
               "var b: int = 1\n"                            # 3 ok
               "var c: int = 5 * 0.5\n"                      # 4 float literal
               "var d: float = 1\n"                          # 5 float type
               "var e := Vector2(1, 2)\n"                    # 6 Vector2
               "func f(delta: int) -> int:\n"                # 7 delta
               "\treturn sin(1)\n"                           # 8 float builtin
               "func g() -> int:\n"                          # 9
               "\treturn Time.get_ticks_msec()\n"            # 10 clock
               "var h := Vector2i(1, 2)\n"                   # 11 ok (int vector)
               "var i: int = Fp.sin(3)\n"                    # 12 ok (table lookup)
               "var j: int = 0xFF\n"                         # 13 ok hex
               "var k: int = 1_000\n"                        # 14 ok
               "var l: int = 1e3\n"                          # 15 exponent literal is a float
               "var m := RandomNumberGenerator.new()\n"      # 16
               "var n: Array = [1]\nfunc o():\n\tn.shuffle()\n")  # 17-19 shuffle
        self.assertEqual(self.flagged_lines("src/sim/sim_x.gd", src), [2, 4, 5, 6, 7, 8, 10, 15, 16, 19])

    def test_float_constants(self) -> None:
        self.assertEqual(self.flagged_lines("src/sim/sim_pi.gd", "var a: int = 3\nvar b: int = PI\nvar c: int = Fp.PI_Q16\nvar d: int = TAU\n"), [2, 4])

    def test_comments_and_strings_are_ignored(self) -> None:
        src = 'extends RefCounted\n# uses randi() and 0.5 and delta\nvar s: String = "float 0.5 randi() Time.now"\nvar t: int = 1 # sqrt(2)\n'
        self.assertEqual(self.flagged_lines("src/core/x.gd", src), [])

    def test_only_deterministic_modules(self) -> None:
        for mod in ("view", "ui", "audio", "app", "net", "ai"):
            self.assertEqual(self.flagged_lines(f"src/{mod}/x_{mod}.gd", "var a: float = randf() * 0.5\n"), [], mod)
        for mod in ("core", "sim", "map", "data"):
            self.assertTrue(self.flagged_lines(f"src/{mod}/x_{mod}.gd", "var a: float = randf() * 0.5\n"), mod)

    def test_data_loaders_may_use_floats_but_not_rng(self) -> None:
        src = "var a: float = 0.5\nvar b: int = roundi(a * 1024.0)\nvar c: int = randi()\n"
        self.assertEqual(self.flagged_lines("src/data/def_loader.gd", src), [3])
        self.assertEqual(self.flagged_lines("src/data/unit_parse.gd", src), [3])
        self.assertEqual(self.flagged_lines("src/data/def_unit.gd", src), [1, 2, 3])

    def test_vector_methods_and_func_definitions(self) -> None:
        src = "func randi_range(a: int) -> int:\n\treturn a\nvar n := Vector2i(1, 2).normalized()\nvar l := Vector2i(3, 4).length_squared()\n"
        self.assertEqual(self.flagged_lines("src/core/rng_like.gd", src), [3, 4])


class TestEscapeHatch(LintCase):
    def test_same_line_previous_line_and_file(self) -> None:
        src = ("extends RefCounted\n"
               "var a: float = 1.0 # lint-allow: L003 view-only conversion at load\n"    # 2 same line
               "# lint-allow: L003 next line is fine because reasons\n"
               "var b: float = 2.0\n"                                                  # 4 previous-line comment
               "var c: float = 3.0\n")                                                 # 5 still flagged
        self.write("src/sim/sim_a.gd", src)
        rep = self.run_lint(["L003"])
        lines = sorted({v.line for v in rep.violations if v.path.endswith("sim_a.gd")})
        self.assertEqual(lines, [5])
        self.assertGreaterEqual(rep.suppressed, 4)

    def test_file_level_allow(self) -> None:
        self.write("src/sim/sim_b.gd", "# lint-allow-file: L003 generated table\nvar a: float = 1.0\nvar b: float = 2.0\n")
        self.assertEqual(self.run_lint(["L003"]).violations, [])

    def test_missing_reason_and_unknown_rule_are_l000(self) -> None:
        self.write("src/sim/sim_c.gd", "var a: float = 1.0 # lint-allow: L003\nvar b := 1 # lint-allow: L777 because\nvar c := 2 # lint-allow: nonsense\n")
        rules = [(v.line, v.rule) for v in self.run_lint().violations if v.path.endswith("sim_c.gd")]
        self.assertIn((1, "L000"), rules)
        self.assertIn((1, "L003"), rules)     # an invalid allow suppresses nothing
        self.assertIn((2, "L000"), rules)
        self.assertIn((3, "L000"), rules)

    def test_allow_for_other_rule_does_not_suppress(self) -> None:
        self.write("src/sim/sim_d.gd", "var a: float = 1.0 # lint-allow: L008 wrong rule\n")
        self.assertTrue(self.rules_in("src/sim/sim_d.gd", "L003"))


class TestL004Classes(LintCase):
    def test_prefix_per_module(self) -> None:
        cases = {"src/sim/sim_ok.gd": "SimOk", "src/sim/bad_thing.gd": "BadThing", "src/data/def_unit.gd": "DefUnit",
                 "src/data/game_data.gd": "GameData", "src/data/weird.gd": "Weird", "src/map/map_data.gd": "MapData",
                 "src/net/net_session.gd": "NetSession", "src/ai/ai_brain.gd": "AiBrain", "src/view/view_world.gd": "ViewWorld",
                 "src/view/fx_spark.gd": "FxSpark", "src/ui/ui_theme.gd": "UiTheme", "src/audio/snd_engine.gd": "SndEngine",
                 "src/app/app_boot.gd": "AppBoot", "src/core/anything.gd": "Anything", "src/ui/nope.gd": "Nope"}
        for rel, cls in cases.items():
            self.write(rel, f"class_name {cls}\nextends RefCounted\n")
        bad = {v.path for v in self.run_lint(["L004"]).violations}
        self.assertEqual(bad, {"game/src/sim/bad_thing.gd", "game/src/data/weird.gd", "game/src/ui/nope.gd"})

    def test_global_uniqueness(self) -> None:
        self.write("src/core/a.gd", "class_name Dup\nextends RefCounted\n")
        self.write("src/core/b.gd", "class_name Dup\nextends RefCounted\n")
        v = self.run_lint(["L004"]).violations
        self.assertEqual(len(v), 1)
        self.assertIn("already declared", v[0].message)

    def test_file_name_matches_class_name_l009(self) -> None:
        self.write("src/sim/sim_world.gd", "class_name SimWorld\n")
        self.write("src/sim/sim_wrong.gd", "class_name SimOther\n")
        got = [v.path for v in self.run_lint(["L009"]).violations]
        self.assertEqual(got, ["game/src/sim/sim_wrong.gd"])


class TestL005Dependencies(LintCase):
    def test_upward_mentions(self) -> None:
        self.write("src/core/log.gd", "class_name Log\nextends RefCounted\nvar w: SimWorld\n")
        self.write("src/core/sim_rng.gd", "class_name SimRng\nextends RefCounted\nvar c: SimConfig\n")
        self.write("src/core/sim_config.gd", "class_name SimConfig\nextends RefCounted\n")
        self.write("src/data/game_data.gd", "class_name GameData\nextends RefCounted\nvar m: MapData\nvar d: DefUnit\nvar s: SimRng\n")
        self.write("src/sim/sim_world.gd", "class_name SimWorld\nextends RefCounted\nvar v: ViewWorld\nvar u: DefUnit\nvar m: MapData\nvar g: GameData\n")
        self.write("src/net/net_session.gd", "class_name NetSession\nextends RefCounted\nvar v: UiHud\nvar a: AiBrain\nvar s: SimWorld\n")
        self.write("src/view/view_world.gd", "class_name ViewWorld\nextends RefCounted\nvar s: SimWorld\nvar n: NetSession\n")
        got = sorted((v.path.split("/")[-1], v.line) for v in self.run_lint(["L005"]).violations)
        self.assertEqual(got, [("game_data.gd", 3), ("log.gd", 3), ("net_session.gd", 3), ("sim_world.gd", 3)])

    def test_comments_strings_and_paths(self) -> None:
        self.write("src/core/x.gd", '# SimWorld is mentioned in a comment\nvar s := "ViewWorld"\nconst P := preload("res://src/sim/sim_world.gd")\n')
        self.write("src/sim/sim_world.gd", "class_name SimWorld\n")
        v = self.run_lint(["L005"]).violations
        self.assertEqual([(x.path.split("/")[-1], x.line) for x in v], [("x.gd", 3)])


class TestL005Tests(LintCase):
    def test_shipped_code_must_not_reference_tests(self) -> None:
        self.write("tests/helper.gd", "extends RefCounted\n")
        self.write("src/app/app_x.gd", 'class_name AppX\nextends RefCounted\nconst H := preload("res://tests/helper.gd")\n')
        self.write("tests/unit/test_y.gd", 'extends RefCounted\nconst H := preload("res://tests/helper.gd")\n')
        got = [(v.path.split("/")[-1], v.line) for v in self.run_lint(["L005"]).violations]
        self.assertEqual(got, [("app_x.gd", 3)])


class TestL006L007L008(LintCase):
    def test_print_and_todo(self) -> None:
        self.write("src/sim/sim_p.gd", "func f() -> void:\n\tprint(1)\n\tprinterr(2)\n\tpush_warning(3)\n\tpush_error(4)\n\tLog.print(5)\n\tprint_stack()\n")
        self.write("src/core/log.gd", "class_name Log\nfunc f() -> void:\n\tprint(1)\n")
        self.write("tests/unit/test_x.gd", "func f() -> void:\n\tprint(1)\n")
        got = [(v.path.split("/")[-1], v.line) for v in self.run_lint(["L006"]).violations]
        self.assertEqual(got, [("sim_p.gd", 2), ("sim_p.gd", 3), ("sim_p.gd", 4)])

    def test_todo_tags(self) -> None:
        self.write("src/sim/sim_t.gd", "# TODO fix me\n# TODO(sim): ok\n# TODO: bare\nvar s := 'TODO in a string is data'\n# TODOS are not todos\n")
        self.assertEqual([v.line for v in self.run_lint(["L006"]).violations], [1, 3])

    def test_file_length(self) -> None:
        self.write("src/core/long.gd", "extends RefCounted\n" + "\n" * 1499)      # 1500 lines exactly
        self.write("src/core/too_long.gd", "extends RefCounted\n" + "\n" * 1500)   # 1501 lines
        self.assertEqual([v.path for v in self.run_lint(["L007"]).violations], ["game/src/core/too_long.gd"])

    def test_untyped_var(self) -> None:
        src = ("var a = 1\nvar b: int = 2\nvar c := 3\n@onready var d = $X\nvar e\nstatic var f = 5\n"
               "func g() -> void:\n\tvar h = 1\n\tvar i: int = 2\n\tvar j := 3\n\tvar k\n")
        self.write("src/sim/sim_v.gd", src)
        self.write("src/view/view_v.gd", "var a = 1\n")
        got = [v.line for v in self.run_lint(["L008"]).violations if v.path.endswith("sim_v.gd")]
        self.assertEqual(got, [1, 4, 5, 6, 8, 11])
        self.assertFalse([v for v in self.run_lint(["L008"]).violations if v.path.endswith("view_v.gd")])


class TestL010LineEndings(LintCase):
    def test_crlf_is_flagged_on_first_offending_line(self) -> None:
        p = self.game / "src" / "core"
        p.mkdir(parents=True)
        (p / "crlf.gd").write_bytes(b"extends RefCounted\nvar a: int = 1\r\nvar b: int = 2\r\n")
        (p / "lf.gd").write_bytes(b"extends RefCounted\nvar a: int = 1\n")
        got = [(v.path, v.line) for v in self.run_lint(["L010"]).violations]
        self.assertEqual(got, [("game/src/core/crlf.gd", 2)])

    def test_other_rules_still_see_clean_lines_in_crlf_files(self) -> None:
        p = self.game / "src" / "sim"
        p.mkdir(parents=True)
        (p / "sim_crlf.gd").write_bytes(b"extends RefCounted\r\nvar a: float = 1.0\r\n")
        self.assertEqual([v.line for v in self.run_lint(["L003"]).violations], [2, 2])


class TestCli(LintCase):
    def test_summary_and_exit_code(self) -> None:
        self.write("src/sim/sim_a.gd", "var a: float = 1.0\n")
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()):
            rc = lint.main(["--root", str(self.root), "--game", str(self.game), "--summary"])
            self.assertEqual(rc, 1)
            self.assertIn("L003", out.getvalue())
            rc = lint.main(["--root", str(self.root), "--game", str(self.game), "--rules", "L001"])
            self.assertEqual(rc, 0)

    def test_targets_filter(self) -> None:
        self.write("src/sim/sim_a.gd", "var a: float = 1.0\n")
        self.write("src/sim/sim_b.gd", "var b: float = 1.0\n")
        rep = lint.run(self.root, self.game, targets=[self.game / "src/sim/sim_a.gd"])
        self.assertEqual({v.path for v in rep.violations}, {"game/src/sim/sim_a.gd"})

    def test_clean_tree_is_clean(self) -> None:
        self.write("src/core/fp.gd", "class_name Fp\nextends RefCounted\n\nconst CELL: int = 1024\n\n\nstatic func cell_of(v: int) -> int:\n\treturn v >> 10\n")
        self.assertEqual(self.run_lint().violations, [])

    def test_real_repo_has_no_lint_noise_from_tools(self) -> None:
        # the linter must at least be able to lint the real project without crashing
        real_root = HERE.parents[2]
        rep = lint.run(real_root, real_root / "game")
        self.assertGreater(rep.files, 5)


if __name__ == "__main__":
    unittest.main()


class TestL011InvisibleChars(LintCase):
    def test_bom_literal_is_flagged(self) -> None:
        p = self.game / "src" / "core"
        p.mkdir(parents=True)
        (p / "bom.gd").write_text('extends RefCounted\nvar a: bool = "x".begins_with("\ufeff")\n', encoding="utf-8")
        (p / "ok.gd").write_text('extends RefCounted\nvar a: bool = "x".unicode_at(0) == 0xFEFF\n', encoding="utf-8")
        got = [(v.path, v.line) for v in self.run_lint(["L011"]).violations]
        self.assertEqual(got, [("game/src/core/bom.gd", 2)])
