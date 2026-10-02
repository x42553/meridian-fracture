"""Tests for the recipe tooling (VIEW-T1): recipe_lib, gen_recipe_stubs, gen_recipe_index, validate_recipes.
Run:  python3 -m unittest discover -s tools/py/tests -p 'test_recipe_tools.py' -v

Mutation style like test_validate_balance.py: every case copies game/data/recipes to a temp dir, applies ONE change and asserts the
expected rule id fires (or that the shipped data is clean).
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import gen_recipe_index as gi  # noqa: E402
import gen_recipe_stubs as gs  # noqa: E402
import recipe_lib as rl  # noqa: E402
import validate_recipes as vr  # noqa: E402

ROOT = rl.ROOT
SPEC = ROOT / "docs/spec/render.md"


def rules_of(rep: vr.Report, sev: str = "error") -> set:
    return {i.rule for i in rep.issues if i.sev == sev}


class Sandbox(unittest.TestCase):
    """A writable copy of game/data/recipes."""

    facts = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.facts = vr.Facts()

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="recipes_"))
        self.dir = self.tmp / "recipes"
        shutil.copytree(rl.RECIPES, self.dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def validate(self) -> vr.Report:
        return vr.Validator(self.dir, rl.BALANCE, self.facts).run()

    def wjson(self, rel: str, obj) -> None:
        p = self.dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")

    def rjson(self, rel: str):
        return json.loads((self.dir / rel).read_text(encoding="utf-8"))

    def add_arch(self, aid: str, ops, defaults=None, size_class="medium", **extra) -> None:
        d = {"schema": rl.ARCH_SCHEMA, "id": aid, "size_class": size_class, "defaults": defaults or {}, "ops": ops}
        d.update(extra)
        self.wjson("archetypes/%s.json" % aid, d)

    def add_recipe(self, rid: str, aid: str, **kw) -> None:
        d = {"schema": rl.RECIPE_SCHEMA, "id": rid, "archetype": aid, "style": "auto"}
        d.update(kw)
        self.wjson("%s.json" % rid, d)

    def with_recipe(self, ops, defaults=None, rid="t.r", **kw) -> vr.Report:
        self.add_arch("t_a", ops, defaults, **kw.pop("arch", {}))
        self.add_recipe(rid, "t_a", **kw)
        return self.validate()


class ShippedData(Sandbox):
    def test_shipped_recipes_validate_clean_and_strict(self):
        rep = self.validate()
        self.assertEqual([(i.rule, i.where, i.msg) for i in rep.issues], [])

    def test_every_def_has_a_recipe_and_the_index_is_sorted(self):
        defs = rl.collect_defs()
        self.assertEqual(len(defs.units), 156)
        self.assertEqual(len(defs.structures), 29)
        self.assertEqual(len(defs.summons), 15)  # + summon.nec.survey_drone, summon.sap.recon_balloon (added by the orchestrator after wave 5)
        self.assertEqual(len(defs.neutrals), 8)
        ids = self.rjson("index.json")["ids"]
        self.assertEqual(ids, sorted(ids))
        for d in defs.all_ids():
            self.assertIn(d, ids, d)
        self.assertEqual(len(ids), len(rl.recipe_files(self.dir)))

    def test_stub_generation_is_idempotent_and_current(self):
        self.assertEqual(gs.main(["--check", "--quiet"]), 0)
        self.assertEqual(gi.main(["--check", "--quiet"]), 0)

    def test_assignments_reproduce_the_spec_lists(self):
        """render.md 5.8.7 lists the units of every view archetype (sum = 156)."""
        text = SPEC.read_text(encoding="utf-8")
        para = text[text.index("`inf_rifle`: ae.civic_rifle_team"):]
        para = para[:para.index("(Sum = 156")]
        defs = rl.collect_defs()
        assign = rl.load_json(rl.RECIPES / "assignments.json")
        want = {}
        for chunk in para.split("·"):
            m = re.match(r"\s*((?:`\w+`(?:/)?)+): (.*)", chunk.strip(), re.S)
            self.assertIsNotNone(m, chunk[:60])
            archs = re.findall(r"`(\w+)`", m.group(1))
            ids = [x.strip().rstrip(".") for x in re.split(r"[,/]", m.group(2)) if x.strip()]
            for a, uid in zip(archs, ids) if len(archs) > 1 else [(archs[0], u) for u in ids]:
                want["unit." + uid] = a
        self.assertEqual(len(want), 156)
        for uid in defs.units:
            got = rl.resolve(uid, defs, assign).archetype
            self.assertEqual(got, want[uid], uid)

    def test_footprints_json_records(self):
        fp = self.rjson("footprints.json")["structures"]
        self.assertEqual(len(fp), 29 + 8)
        f = fp["structure.shared.factory"]
        self.assertEqual((f["fw"], f["fh"], f["door_cx"], f["door_cz"], f["exit_dir"]), (3, 3, -3.0, 6.0, 1024))
        r = fp["structure.shared.refinery"]
        self.assertEqual((r["door_cx"], r["door_cz"]), (-3.0, 3.0))
        self.assertEqual(fp["structure.shared.airfield"]["pads_n"], 4)
        self.assertEqual((fp["structure.shared.airfield"]["fw"], fp["structure.shared.airfield"]["fh"]), (6, 3))
        self.assertEqual(fp["neutral.observation_tower"]["door_cz"], 3.0)


class Expressions(unittest.TestCase):
    F = vr.Facts().funcs

    def ok(self, s):
        return vr.parse_expr(s, self.F)

    def bad(self, s, frag):
        with self.assertRaises(vr.ExprError) as cm:
            vr.parse_expr(s, self.F)
        self.assertIn(frag, str(cm.exception))

    def test_grammar(self):
        self.assertEqual(self.ok("a*2 + max(b, 0.5) - -c"), {"a", "b", "c"})
        self.assertEqual(self.ok("i % 2 == 0 ? 'base' : 'sec'"), {"i"})
        self.assertEqual(self.ok("not x and (y or z) ? 1 : 0"), {"x", "y", "z"})
        self.assertEqual(self.ok("clamp(door_cx, -(bw*0.5-door_w*0.5-0.3), bw*0.5)"), {"door_cx", "bw", "door_w"})
        self.assertEqual(self.ok("rnd(i+9)*TAU"), {"i", "TAU"})
        self.assertEqual(self.ok("fw*fh>1 ? 1.0 : 0.3"), {"fw", "fh"})

    def test_errors(self):
        self.bad("1 +", "end of expression")
        self.bad("foo(1)", "unknown function")
        self.bad("min(1)", "takes 2")
        self.bad("a / 0", "division by the literal 0")
        self.bad("a % 0.0", "division by the literal 0")
        self.bad("(1 + 2", "missing ')'")
        self.bad("a ? b", "':'")
        self.bad("a // 2", "unexpected")
        self.bad("a $ b", "unexpected '$'")


class Mutations(Sandbox):
    def test_unknown_names(self):
        self.assertIn("V-RCP-03", rules_of(self._bad_arch()))
        rep = self.with_recipe([["nosuchop", 1]])
        self.assertIn("V-RCP-03", rules_of(rep))
        rep = self.with_recipe([{"call": "nosuchmacro"}])
        self.assertIn("V-RCP-03", rules_of(rep))
        rep = self.with_recipe([{"call": "hatch", "args": {"bogus": 1}}])
        self.assertIn("V-RCP-03", rules_of(rep))
        rep = self.with_recipe([{"part": {"kind": "wingding"}, "do": []}])
        self.assertIn("V-RCP-03", rules_of(rep))
        rep = self.with_recipe([["brush", "base", "plastic"]])
        self.assertIn("V-RCP-03", rules_of(rep))
        rep = self.with_recipe([{"for": "i", "n": 2, "do": [], "bogus": 1}])
        self.assertIn("V-RCP-03", rules_of(rep))

    def _bad_arch(self):
        self.add_recipe("t.q", "no_such_arch")
        return self.validate()

    def test_recipe_params(self):
        rep = self.with_recipe([], {"n": 3, "kind": "a", "flag": True}, params={"zzz": 1})
        self.assertIn("V-RCP-04", rules_of(rep))
        rep = self.with_recipe([], {"n": 3}, params={"n": True})
        self.assertIn("V-RCP-04", rules_of(rep))
        rep = self.with_recipe([], {"kind": "a"}, params={"kind": 5})
        self.assertIn("V-RCP-04", rules_of(rep))
        rep = self.with_recipe([], {"n": 3}, params={"n": "n*2"})
        self.assertNotIn("V-RCP-04", rules_of(rep))
        rep = self.with_recipe([], {"n": 3}, params={"n": "nope*2"})
        self.assertIn("V-RCP-05", rules_of(rep))

    def test_expressions_in_ops(self):
        rep = self.with_recipe([["box", [0, "q", 0], [1, 1, 1]]])
        self.assertIn("V-RCP-05", rules_of(rep))
        rep = self.with_recipe([["box", [0, "w*2", 0], [1, 1, 1]]], {"w": 1.0})
        self.assertNotIn("V-RCP-05", rules_of(rep))
        rep = self.with_recipe([["box", [0, "1/0", 0], [1, 1, 1]]])
        self.assertIn("V-RCP-05", rules_of(rep))
        # a `let` is visible to later ops only (compile order), a loop variable inside its body only in order
        rep = self.with_recipe([["box", [0, "later", 0], [1, 1, 1]], {"let": {"later": 1}}])
        self.assertIn("V-RCP-05", rules_of(rep))
        rep = self.with_recipe([{"let": {"a": 1}}, {"for": "i", "n": 3, "do": [["box", ["i*a", 0, 0], [1, 1, 1]]]}])
        self.assertNotIn("V-RCP-05", rules_of(rep))
        rep = self.with_recipe([{"if": "unknown_flag", "then": []}])
        self.assertIn("V-RCP-05", rules_of(rep))

    def test_colours(self):
        rep = self.with_recipe([["brush", "chartreuse"]])
        self.assertIn("V-RCP-06", rules_of(rep))
        rep = self.with_recipe([["brush", "#12345"]])
        self.assertIn("V-RCP-06", rules_of(rep))
        rep = self.with_recipe([["brush", "mix(base,acc,0.3)"], ["brush", "dark*1.2"], ["brush", "#a1b2c3"]])
        self.assertNotIn("V-RCP-06", rules_of(rep))

    def test_team_surface_warning(self):
        rep = self.with_recipe([["box", [0, 0, 0], [1, 1, 1]]], rid="unit.napc.t")
        self.assertIn("V-RCP-06", rules_of(rep, "warning"))
        rep = self.with_recipe([["brush", "base", "paint", 1], ["box", [0, 0, 0], [1, 1, 1]]], rid="unit.napc.t")
        self.assertNotIn("V-RCP-06", rules_of(rep, "warning"))
        rep = self.with_recipe([{"call": "team_panel", "args": {"center": [0, 1, 0], "size": [1, 0.03, 1]}}], rid="unit.napc.t")
        self.assertNotIn("V-RCP-06", rules_of(rep, "warning"))

    def test_loop_and_depth_limits(self):
        rep = self.with_recipe([{"for": "i", "n": 65, "do": []}])
        self.assertIn("V-RCP-07", rules_of(rep))
        deep = [{"for": "a", "n": 2, "do": [{"for": "b", "n": 2, "do": [{"for": "c", "n": 2, "do": [{"for": "d", "n": 2, "do": []}]}]}]}]
        self.assertIn("V-RCP-07", rules_of(self.with_recipe(deep)))
        ops = [["box", [0, 0, 0], [1, 1, 1]]]
        for _ in range(10):
            ops = [{"if": "true", "then": ops}]
        self.assertIn("V-RCP-07", rules_of(self.with_recipe(ops)))

    def test_file_level(self):
        self.add_recipe("t.r", "veh_tank")
        p = self.dir / "t.r.json"
        d = json.loads(p.read_text())
        d["id"] = "other"
        p.write_text(json.dumps(d))
        self.assertIn("V-RCP-01", rules_of(self.validate()))
        p.write_text("{ not json")
        self.assertIn("V-RCP-01", rules_of(self.validate()))
        p.write_text(json.dumps({"schema": "x", "id": "t.r", "archetype": "veh_tank"}))
        self.assertIn("V-RCP-01", rules_of(self.validate()))

    def test_index_footprints_and_missing_recipes(self):
        idx = self.rjson("index.json")
        idx["ids"].remove("unit.napc.guardian_tank")
        self.wjson("index.json", idx)
        self.assertIn("V-RCP-02", rules_of(self.validate()))
        shutil.copy(rl.RECIPES / "index.json", self.dir / "index.json")
        (self.dir / "unit.napc.guardian_tank.json").unlink()
        rep = self.validate()
        self.assertIn("V-RCP-02", rules_of(rep))
        shutil.copy(rl.RECIPES / "unit.napc.guardian_tank.json", self.dir / "unit.napc.guardian_tank.json")
        fp = self.rjson("footprints.json")
        fp["structures"]["structure.shared.factory"]["door_cx"] = 99
        self.wjson("footprints.json", fp)
        self.assertIn("V-RCP-02", rules_of(self.validate()))

    def test_def_without_rule_warns(self):
        a = self.rjson("assignments.json")
        del a["balance_to_view"]["inf_at"]
        self.wjson("assignments.json", a)
        rep = self.validate()
        self.assertIn("V-RCP-02", rules_of(rep, "warning"))

    def test_rule_names_an_archetype_that_does_not_exist(self):
        a = self.rjson("assignments.json")
        a["balance_to_view"]["inf_at"] = "inf_nonexistent"
        self.wjson("assignments.json", a)
        self.assertIn("V-RCP-03", rules_of(self.validate()))

    def test_styles(self):
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"nec": {"emblem": "none"}}})
        self.assertIn("V-RCP-12", rules_of(self.validate()))
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc": {"emblem": "swastika"}}})
        self.assertIn("V-RCP-11", rules_of(self.validate()))
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc.usa": {"extends": "napc.nowhere"}}})
        self.assertIn("V-RCP-03", rules_of(self.validate()))
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc.a": {"extends": "napc.b"}, "napc.b": {"extends": "napc.a"}}})
        self.assertIn("V-RCP-12", rules_of(self.validate()))
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc": {"palette": {"base": "olive"}}}})
        self.assertIn("V-RCP-06", rules_of(self.validate()))
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc": {"team_plate": "fancy"}}})
        self.assertIn("V-RCP-12", rules_of(self.validate()))
        # a legal partial override merges over styles.json, is recorded as a warning and is not an error
        self.wjson("styles/napc.json", {"schema": rl.STYLES_SCHEMA, "styles": {"napc": {"palette": {"base": "#4d592e"}}, "napc.usa": {"extends": "napc", "palette": {"acc": "#ed5e0f"}}}})
        rep = self.validate()
        self.assertEqual(rules_of(rep), set())
        self.assertIn("V-RCP-12", rules_of(rep, "warning"))
        # unsorted keys
        self.wjson("styles/nec.json", {"schema": rl.STYLES_SCHEMA, "styles": {"nec.b": {}, "nec.a": {}}})
        self.assertIn("V-RCP-01", rules_of(self.validate()))

    def test_structure_anchors(self):
        r = self.rjson("structure.shared.factory.json")
        r["archetype"] = "t_s"
        self.wjson("structure.shared.factory.json", r)
        self.add_arch("t_s", [["socket", "door_exit", [0, 0, 0], [0, 0, 1]], ["meta", "footprint", ["fw", "fh"]]], size_class="structure")
        self.assertIn("V-RCP-10", rules_of(self.validate()))
        self.add_arch("t_s", [["meta", "footprint", ["fw", "fh"]]], size_class="structure")
        self.assertIn("V-RCP-10", rules_of(self.validate()))
        self.add_arch("t_s", [["socket", "door_exit", ["door_cx", 0, "door_cz"], [0, 0, 1]], ["meta", "footprint", ["fw", "fh"]]], size_class="structure")
        self.assertNotIn("V-RCP-10", rules_of(self.validate()))

    def test_armed_units_need_muzzle_sockets(self):
        r = self.rjson("unit.napc.guardian_tank.json")
        r["archetype"] = "t_u"
        self.wjson("unit.napc.guardian_tank.json", r)
        self.add_arch("t_u", [["brush", "base", "paint", 1], ["box", [0, 0, 0], [1, 1, 1]]])
        self.assertIn("V-RCP-08", rules_of(self.validate()))
        self.add_arch("t_u", [["brush", "base", "paint", 1], ["box", [0, 0, 0], [1, 1, 1]], ["socket", "muzzle0_0", [0, 1, 0], [0, 0, -1]]])
        self.assertNotIn("V-RCP-08", rules_of(self.validate()))


class SpecExamples(Sandbox):
    """The example recipes of render spec 7.3 pass the validators (against an archetype that declares their parameters)."""

    GUARDIAN = {
        "schema": "meridian.recipe/1", "id": "unit.napc.guardian_tank", "archetype": "veh_tank", "style": "auto", "scale": 1.0,
        "params": {"len": 3.5, "wheel_n": 5, "barrel_len": 2.0, "skirt": "modules", "roof": "cupola"},
        "slots": {"roof": [
            {"call": "hatch", "args": {"c": ["turret_hw*0.36", "top_y", "turret_z+turret_hl*0.30"], "r": 0.15, "body": "sec", "ring": "acc"}},
            {"call": "whip", "args": {"base": ["-turret_hw*0.6", "top_y", "turret_z+turret_hl*0.85"], "tip": ["-turret_hw*0.62", "top_y+1.15", "turret_z+turret_hl*0.9"], "r": 0.011, "col": "metal"}}]},
        "ops_after": [], "meta": {"role": "tank", "icon": {"yaw": 150, "pitch": 24, "margin": 0.78}},
    }
    FACTORY = {
        "schema": "meridian.recipe/1", "id": "structure.shared.factory", "archetype": "str_factory", "style": "auto",
        "params": {"height": 6.5, "hall_h": 3.6, "door_w": "min(3.76, fw*3-1.6)", "roof": "skylights", "stacks": 2},
        "ops_after": [
            {"for": "i", "n": 10, "do": [
                {"part": {"kind": "door", "extra": "2.88-0.25*i"}, "do": [
                    ["brush", "i % 3 == 0 ? 'sec*0.85' : 'sec'"],
                    ["box", ["door_cx", "0.29+0.30*i", "fh*1.5-0.03"], ["door_w", 0.28, 0.07], 0.01]]}]},
            ["socket", "door_exit", ["door_cx", 0, "door_cz"], [0, 0, 1]],
            ["socket", "weld0", [1.2, "height", 0.8], [0, 1, 0]],
            ["meta", "footprint", ["fw", "fh"]]],
    }

    def test_guardian_tank_example(self):
        r = json.loads(json.dumps(self.GUARDIAN))
        r["id"] = "unit.napc.guardian_tank"
        self.wjson("unit.napc.guardian_tank.json", r)
        rep = self.validate()
        self.assertEqual([i for i in rep.issues if i.where.startswith("unit.napc.guardian_tank")], [])

    def test_factory_example(self):
        self.add_arch("str_factory", [["brush", "base", "paint", 1], ["box", [0, 1, 0], [1, 1, 1]]],
                      {"height": 5.0, "hall_h": 3.0, "door_w": 3.0, "roof": "flat", "stacks": 1}, size_class="structure")
        self.wjson("structure.shared.factory.json", self.FACTORY)
        rep = self.validate()
        self.assertEqual([i for i in rep.issues if i.where.startswith("structure.shared.factory")], [])


class Stubs(Sandbox):
    def plan(self, **kw):
        return gs.plan(self.dir, rl.BALANCE, **kw)

    def test_hand_authored_recipes_are_never_touched(self):
        p = self.dir / "unit.napc.guardian_tank.json"
        d = json.loads(p.read_text())
        d["meta"] = {"role": "tank"}  # no stub flag: hand-authored
        d["params"] = {"len": 3.7}
        p.write_text(json.dumps(d))
        e = self.plan()["unit.napc.guardian_tank"]
        self.assertEqual(e["status"], "kept")

    def test_stub_is_repointed_when_the_real_archetype_appears(self):
        # the shipped data has the real str_factory by now: rebuild the stub state this test is about
        (self.dir / "archetypes" / "str_factory.json").unlink(missing_ok=True)
        stub = {"schema": rl.RECIPE_SCHEMA, "id": "structure.shared.factory", "archetype": "gen_structure", "params": {"role": "factory"},
                "meta": {"stub": True}, "style": "auto"}
        (self.dir / "structure.shared.factory.json").write_text(json.dumps(stub))
        before = json.loads((self.dir / "structure.shared.factory.json").read_text())
        self.assertEqual(before["archetype"], "gen_structure")
        self.assertEqual(before["params"], {"role": "factory"})
        self.add_arch("str_factory", [["box", [0, 0, 0], [1, 1, 1]]], {"hall_h": 3.0})
        e = self.plan()["structure.shared.factory"]
        self.assertEqual(e["status"], "changed")
        after = json.loads(e["text"])
        self.assertEqual(after["archetype"], "str_factory")
        self.assertNotIn("params", after)  # the rule carries no params for str_factory

    def test_rule_params_are_kept_only_where_the_archetype_declares_them(self):
        self.add_arch("neu_building", [["box", [0, 0, 0], [1, 1, 1]]], {"kit": "garrison"})
        e = self.plan()["neutral.salvage_field_rich"]
        after = json.loads(e["text"])
        self.assertEqual(after["archetype"], "neu_building")
        self.assertEqual(after["params"], {"kit": "deposit"})
        self.assertTrue(any("heaps" in w for w in e["warnings"]))
        # the fallback (gen_neutral) declares heaps
        e2 = gs.plan(self.dir, rl.BALANCE)
        self.assertIn("neutral.salvage_field", e2)

    def test_missing_stub_is_written_and_prune_removes_stale(self):
        (self.dir / "summon.napc.uav.json").unlink()
        self.assertEqual(self.plan()["summon.napc.uav"]["status"], "new")
        stale = self.dir / "unit.zzz.ghost.json"
        stale.write_text(json.dumps({"schema": rl.RECIPE_SCHEMA, "id": "unit.zzz.ghost", "archetype": "veh_tank", "meta": {"stub": True}}))
        defs = rl.collect_defs()
        self.assertEqual([p.name for p in gs.stale_stubs(defs.all_ids(), self.dir)], ["unit.zzz.ghost.json"])

    def test_only_filter(self):
        p = self.plan(only="structure.shared.*")
        self.assertEqual(len(p), 12)

    def test_fallbacks_cover_every_view_archetype(self):
        a = rl.load_json(rl.RECIPES / "assignments.json")
        names = set(a["balance_to_view"].values()) | {"veh_amphib"}
        names |= {o["archetype"] for o in a["overrides"].values()} | {p["archetype"] for p in a["patterns"]}
        have = set(rl.archetype_files(rl.RECIPES))
        for n in names:
            self.assertTrue(n in have or n in a["fallbacks"], n)
        # a stub never names an archetype without a file
        for rid in json.loads((rl.RECIPES / "index.json").read_text())["ids"]:
            r = json.loads((rl.RECIPES / (rid + ".json")).read_text())
            if r.get("meta", {}).get("stub"):
                self.assertIn(r["archetype"], have, rid)


if __name__ == "__main__":
    unittest.main()
