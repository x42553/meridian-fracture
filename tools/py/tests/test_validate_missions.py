"""Tests for tools/py/validate_missions.py.  Run: python3 -m unittest discover -s tools/py/tests -p 'test_validate_missions.py' -v

Every case mutates ONE field of a known-good mission (in memory) and asserts the expected V-MIS rule id."""
from __future__ import annotations

import copy
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import validate_missions as vm  # noqa: E402

VOCAB = vm.Vocab()


def good() -> dict:
    return {
        "schema": "meridian.mission/1", "id": "t_good", "title": "Good", "map": {"family": "open", "size": 96, "seed": 3},
        "rules": {"fog": False},
        "players": [
            {"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": {"mode": "hq", "units": [{"def": "unit.napc.guardian_tank", "count": 2}]}},
            {"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": False}, "start": {"mode": "none"}},
        ],
        "areas": [{"id": "a", "shape": "circle", "anchor": "start:0", "x": 0, "y": 0, "r": 5}, {"id": "b", "shape": "rect", "anchor": "map", "x": 500, "y": 500, "w": 4, "h": 4}],
        "messages": [{"id": "m1", "text": "Hello", "announcer": "base_under_attack"}],
        "objectives": [{"id": "o1", "kind": "primary", "text": "Do"}, {"id": "o2", "kind": "hidden", "text": "Secret"}],
        "timers": [{"id": "tm", "seconds": 5}],
        "triggers": [{"id": "t1", "when": {"kind": "time", "seconds": 1}, "then": [{"do": "show_message", "message": "m1"}]}],
    }


def check(m: dict, name: str = "t_good.json") -> vm.Problems:
    out = vm.Problems()
    vm.check_mission(m, name, VOCAB, out)
    return out


def rules_of(p: vm.Problems) -> set[str]:
    return {line.split(": ", 2)[2].split(" ", 1)[0] for line in p.errors}


class Shipped(unittest.TestCase):
    def test_shipped_missions_are_clean(self) -> None:
        p = vm.check_all()
        self.assertEqual(p.errors, [])
        self.assertEqual(p.warnings, [])

    def test_good_fixture_is_clean(self) -> None:
        p = check(good())
        self.assertEqual(p.errors, [])
        self.assertEqual(p.warnings, [])

    def test_schema_text_matches_the_gdscript_compiler_header(self) -> None:
        gd = vm.gd_schema_block()
        self.assertTrue(gd, "the schema block of def_mission_parser.gd was not found")
        self.assertEqual(gd.strip(), vm.schema_text().strip(), "def_mission_parser.gd header and validate_missions.py --schema differ")

    def test_schema_flag_prints_the_schema(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = vm.main(["--schema"])
        self.assertEqual(rc, 0)
        self.assertIn("meridian.mission/1", buf.getvalue())
        self.assertIn("ACTION  {do: <name>, ...}", buf.getvalue())


class Mutations(unittest.TestCase):
    def expect(self, rule: str, mutate, label: str = "") -> None:  # type: ignore[no-untyped-def]
        m = good()
        mutate(m)
        self.assertIn(rule, rules_of(check(m)), label or rule)

    def test_identity(self) -> None:
        self.expect("V-MIS-01", lambda m: m.update(schema="meridian.mission/2"))
        self.expect("V-MIS-01", lambda m: m.update(id="other"), "id vs file name")
        self.expect("V-MIS-01", lambda m: m.update(id="T-Good"))
        self.expect("V-MIS-02", lambda m: m.update(typo=1))
        self.expect("V-MIS-02", lambda m: m.pop("title"))
        self.expect("V-MIS-02", lambda m: m.update(order=1.5))
        self.expect("V-MIS-02", lambda m: m.update(order=10000))

    def test_map_players_rules(self) -> None:
        self.expect("V-MIS-02", lambda m: m["map"].update(family="moon"))
        self.expect("V-MIS-06", lambda m: m["map"].update(size=100))
        self.expect("V-MIS-02", lambda m: m["map"].update(size=64))
        self.expect("V-MIS-02", lambda m: m["map"].update(params={"water_pct": 90}))
        self.expect("V-MIS-02", lambda m: m["map"].update(params={"lava": 1}))
        self.expect("V-MIS-06", lambda m: m["players"][0].update(kind="ai"))
        self.expect("V-MIS-06", lambda m: m["players"][1].update(kind="human"))
        self.expect("V-MIS-04", lambda m: m["players"][1].update(slot=0))
        self.expect("V-MIS-04", lambda m: m["players"][0].update(color=1))
        self.expect("V-MIS-04", lambda m: m["players"][1].update(start_slot=0))
        self.expect("V-MIS-03", lambda m: m["players"][1].update(roster="roster.nope.vanilla"))
        self.expect("V-MIS-02", lambda m: m["players"][1].update(team=5))
        self.expect("V-MIS-02", lambda m: m["players"][1].update(handicap=101))
        self.expect("V-MIS-02", lambda m: m["players"][1].update(name="Bad[Name]"))
        self.expect("V-MIS-05", lambda m: m["players"][0].update(ai={"level": 1}))
        self.expect("V-MIS-03", lambda m: m["players"][0]["start"].update(units=[{"def": "unit.nope"}]))
        self.expect("V-MIS-02", lambda m: m["rules"].update(start_mode=1), "start_mode cannot be set")
        self.expect("V-MIS-02", lambda m: m["rules"].update(unit_cap=5))
        self.expect("V-MIS-06", lambda m: m.update(players=[]))

    def test_lists(self) -> None:
        self.expect("V-MIS-04", lambda m: m["areas"][1].update(id="a"))
        self.expect("V-MIS-02", lambda m: m["areas"][0].update(shape="star"))
        self.expect("V-MIS-03", lambda m: m["areas"][0].update(anchor="start:5"))
        self.expect("V-MIS-02", lambda m: m["areas"][0].pop("r"))
        self.expect("V-MIS-02", lambda m: m["areas"][1].update(x=1001))
        self.expect("V-MIS-04", lambda m: m["messages"].append({"id": "m1", "text": "x"}))
        self.expect("V-MIS-04", lambda m: m["objectives"].append({"id": "o1", "kind": "primary", "text": "x"}))
        self.expect("V-MIS-05", lambda m: m["objectives"][1].update(initial="active"))
        self.expect("V-MIS-02", lambda m: m["objectives"][0].update(kind="tertiary"))
        self.expect("V-MIS-02", lambda m: m["timers"][0].update(seconds=0))
        self.expect("V-MIS-03", lambda m: m.update(briefing=[{"text": "x", "lore": "bogus.thing"}]))
        self.expect("V-MIS-04", lambda m: m["triggers"].append(copy.deepcopy(m["triggers"][0])))

    def trig(self, when=None, then=None):  # type: ignore[no-untyped-def]
        def mutate(m: dict) -> None:
            if when is not None:
                m["triggers"][0]["when"] = when
            if then is not None:
                m["triggers"][0]["then"] = then
        return mutate

    def test_conditions(self) -> None:
        self.expect("V-MIS-05", self.trig(when={"kind": "weather"}))
        self.expect("V-MIS-02", self.trig(when={"kind": "time", "seconds": 1, "bogus": 1}))
        self.expect("V-MIS-05", self.trig(when={"kind": "time"}))
        self.expect("V-MIS-05", self.trig(when={"kind": "time", "seconds": 1, "ticks": 20}))
        self.expect("V-MIS-03", self.trig(when={"kind": "timer", "timer": "nope"}))
        self.expect("V-MIS-03", self.trig(when={"kind": "objective", "objective": "nope", "state": "active"}))
        self.expect("V-MIS-02", self.trig(when={"kind": "credits", "owner": 0, "cmp": "=>", "value": 1}))
        self.expect("V-MIS-03", self.trig(when={"kind": "credits", "owner": 5, "value": 1}))
        self.expect("V-MIS-02", self.trig(when={"kind": "credits", "owner": "everyone", "value": 1}))
        self.expect("V-MIS-03", self.trig(when={"kind": "count", "owner": 0, "def": "unit.nope", "value": 1}))
        self.expect("V-MIS-03", self.trig(when={"kind": "count", "owner": 0, "tag": "wizard", "value": 1}))
        self.expect("V-MIS-03", self.trig(when={"kind": "count", "owner": 0, "area": "nope", "value": 1}))
        self.expect("V-MIS-05", self.trig(when={"kind": "count", "owner": 0, "of": "structure", "def": "unit.napc.guardian_tank", "value": 1}))
        self.expect("V-MIS-05", self.trig(when={"kind": "structure", "state": "destroyed", "owner": 0, "def": "structure.shared.generator"}))
        self.expect("V-MIS-03", self.trig(when={"kind": "wave", "wave": "nope", "state": "cleared"}))
        self.expect("V-MIS-05", self.trig(when={"all": []}))
        self.expect("V-MIS-05", self.trig(when={"all": [{"kind": "time", "seconds": 1}], "kind": "time"}))
        deep: dict = {"kind": "time", "seconds": 1}
        for _ in range(9):
            deep = {"not": deep}
        self.expect("V-MIS-05", self.trig(when=deep), "depth limit")

    def test_actions(self) -> None:
        a = lambda d: self.trig(then=[d])  # noqa: E731
        self.expect("V-MIS-05", a({"do": "explode"}))
        self.expect("V-MIS-03", a({"do": "show_message", "message": "nope"}))
        self.expect("V-MIS-02", a({"do": "timer_stop", "timer": "tm", "x": 1}))
        self.expect("V-MIS-02", a({"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad"}))
        self.expect("V-MIS-02", a({"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad", "area": "a", "order": {"kind": "attack_move"}}))
        self.expect("V-MIS-05", a({"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator"}))
        self.expect("V-MIS-05", a({"do": "win", "owner": "neutral"}))
        self.expect("V-MIS-05", a({"do": "change_ai", "owner": 0, "active": True}))
        self.expect("V-MIS-05", a({"do": "change_ai", "owner": 1}))
        self.expect("V-MIS-05", a({"do": "transfer", "to": 0}), "transfer needs a target")
        self.expect("V-MIS-05", a({"do": "destroy"}), "destroy needs a target")
        self.expect("V-MIS-02", a({"do": "music_state", "state": "polka"}))
        self.expect("V-MIS-02", self.trig(then=[]))

    def test_good_actions_pass(self) -> None:
        m = good()
        m["triggers"][0]["then"] = [
            {"do": "spawn_units", "owner": 1, "def": "unit.nec.jager_squad", "count": 3, "area": "a", "wave": "w1", "order": {"kind": "attack_move", "area": "b"}},
            {"do": "spawn_structure", "owner": "neutral", "def": "structure.shared.generator", "cell": [10, 10], "id": "gen"},
            {"do": "transfer", "to": 0, "placed": "gen"}, {"do": "destroy", "owner": 1, "of": "unit", "area": "a"},
            {"do": "order_units", "owner": 0, "tag": "tank", "area": "a", "order": {"kind": "hold"}},
            {"do": "reveal_area", "owner": "team:1", "area": "a"}, {"do": "camera_hint", "cell": [1, 2]},
            {"do": "change_ai", "owner": 1, "level": 3}, {"do": "give_credits", "owner": 0, "amount": -50},
            {"do": "grant_power", "owner": 0, "slot": 2}, {"do": "trigger_enable", "trigger": "t1"},
        ]
        m["triggers"].append({"id": "t2", "when": {"all": [{"kind": "wave", "wave": "w1", "state": "cleared"},
                                                            {"kind": "structure", "state": "captured", "placed": "gen"},
                                                            {"kind": "area_left", "owner": 1, "area": "a"},
                                                            {"not": {"kind": "no_assets", "owner": "enemies_of:0"}}]},
                              "then": [{"do": "win", "owner": 0}]})
        self.assertEqual(check(m).errors, [])

    def test_duplicate_placed_id(self) -> None:
        m = good()
        spawn = {"do": "spawn_structure", "owner": 1, "def": "structure.shared.generator", "area": "a", "id": "dup"}
        m["triggers"][0]["then"] = [spawn, dict(spawn)]
        self.assertIn("V-MIS-04", rules_of(check(m)))

    def test_unknown_announcer_is_a_warning(self) -> None:
        m = good()
        m["messages"][0]["announcer"] = "no_such_line"
        p = check(m)
        self.assertEqual(p.errors, [])
        self.assertTrue(any("V-MIS-07" in w for w in p.warnings))


class Manifest(unittest.TestCase):
    def run_dir(self, listed: list[str], files: dict[str, dict]) -> vm.Problems:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "missions").mkdir()
            (root / "balance").mkdir()
            (root / "balance" / "manifest.json").write_text(json.dumps({"schema": "meridian.balance.manifest/1", "format": 1, "files": [], "missions": listed}))
            for name, doc in files.items():
                (root / "missions" / name).write_text(json.dumps(doc))
            return vm.check_all(root / "missions", root / "balance", VOCAB)

    def test_clean_listing(self) -> None:
        p = self.run_dir(["t_good.json"], {"t_good.json": good()})
        self.assertEqual((p.errors, p.warnings), ([], []))

    def test_unsorted_and_missing_and_unlisted(self) -> None:
        a = good()
        b = good()
        b["id"] = "t_a"
        p = self.run_dir(["t_good.json", "t_a.json"], {"t_good.json": a, "t_a.json": b})
        self.assertTrue(any("sorted" in e for e in p.errors))
        p = self.run_dir(["gone.json"], {})
        self.assertTrue(any("does not exist" in e for e in p.errors))
        p = self.run_dir([], {"t_good.json": a})
        self.assertTrue(any("not listed" in w for w in p.warnings))


if __name__ == "__main__":
    unittest.main()
