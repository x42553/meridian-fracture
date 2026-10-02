"""Mutation tests for tools/py/validate_balance.py.  Run: python3 -m unittest discover -s tools/py/tests -p 'test_validate_balance.py' -v

Every case takes the known-good example sheet (balance_lib/EXAMPLE_units_sheet.json installed as units_napc.json next to the shipped shared files),
applies ONE mutation and asserts that the validator reports the expected rule id (and, for the good sheet, nothing else than V-CMP-01 "bible unit
missing", because the example only carries 2 of NAPC's 19 units).
"""
from __future__ import annotations

import copy
import io
import json
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import validate_balance as vb  # noqa: E402
from balance_lib import convert  # noqa: E402
from balance_lib.report import RULES  # noqa: E402

ROOT = HERE.parents[2]
BALANCE = ROOT / "game/data/balance"
BIBLE = ROOT / "game/data/bible/meridian_factions.json"
EXAMPLE = ROOT / "tools/py/balance_lib/EXAMPLE_units_sheet.json"
SHEET = "units_napc.json"
GUARD = 0   # index of unit.napc.guardian_tank in the example
PAL = 1     # index of unit.napc.paladin_howitzer


def load(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))


class Kit:
    """A scratch copy of the balance dir; edits are made on parsed JSON and written back before a run."""

    def __init__(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "balance"
        shutil.copytree(BALANCE, self.dir)
        shutil.copy(EXAMPLE, self.dir / SHEET)
        self.docs: dict[str, dict] = {}
        self.bible_path = Path(self.tmp.name) / "bible.json"
        self.bible_doc: dict | None = None
        self.raw: dict[str, str] = {}

    def doc(self, name: str) -> dict:
        if name not in self.docs:
            self.docs[name] = load(self.dir / name)
        return self.docs[name]

    def bible(self) -> dict:
        if self.bible_doc is None:
            self.bible_doc = load(BIBLE)
        return self.bible_doc

    def run(self, strict: bool = True) -> list:
        for n, d in self.docs.items():
            (self.dir / n).write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
        for n, t in self.raw.items():
            (self.dir / n).write_text(t, encoding="utf-8")
        if self.bible_doc is not None:
            self.bible_path.write_text(json.dumps(self.bible_doc), encoding="utf-8")
            bp = self.bible_path
        else:
            bp = BIBLE
        _, rep = vb.run(self.dir, bp, strict=strict)
        return [f for f in rep.findings if not (f.rule == "V-CMP-01" and "has no entry" in f.message) and "does not exist" not in f.message]

    def close(self) -> None:
        self.tmp.cleanup()


def rules_of(findings: list) -> set[str]:
    return {f.rule for f in findings}


# ---------------------------------------------------------------------------------------------------------------------------------------------------
# mutations: (rule expected, description, function(kit))
# ---------------------------------------------------------------------------------------------------------------------------------------------------
def sheet(k: Kit) -> dict:
    return k.doc(SHEET)


def unit(k: Kit, i: int = GUARD) -> dict:
    return sheet(k)["units"][i]


def weapon(k: Kit, i: int = 0) -> dict:
    return sheet(k)["weapons"][i]


def _dup_key(k: Kit) -> None:
    t = (BALANCE.parent.parent.parent / "tools/py/balance_lib/EXAMPLE_units_sheet.json").read_text()
    k.raw[SHEET] = t.replace('"health": 907,', '"health": 907, "health": 908,')


def _dup_weapon(k: Kit) -> None:
    sheet(k)["weapons"].append(copy.deepcopy(weapon(k)))


def _dup_unit(k: Kit) -> None:
    sheet(k)["units"].append(copy.deepcopy(unit(k)))


def _bible_anti_air(k: Kit) -> None:
    k.bible()["units"]["unit.napc.guardian_tank"]["tags"].append("anti_air")


def _unsorted(k: Kit) -> None:
    sheet(k)["units"].reverse()


def _ability_kind_twice(k: Kit) -> None:
    unit(k, PAL)["abilities"] = ["deployable_mode", "ability.deploy.suppressive"]


def _cross_id(k: Kit) -> None:
    u = copy.deepcopy(unit(k))
    u["id"] = "unit.han.guardian_tank"
    sheet(k)["units"].append(u)


def _struct_drop(k: Kit) -> None:
    k.doc("structures.json")["structures"].pop(0)


def _struct_health(k: Kit) -> None:
    for e in k.doc("structures.json")["structures"]:
        if e["id"] == "structure.shared.barracks":
            e["cost_credits"] = 1


def _matrix_hole(k: Kit) -> None:
    dm = k.doc("global.json")["damage_matrix"]
    first = next(iter(dm))
    if isinstance(dm[first], dict):
        dm[first].pop(next(iter(dm[first])))
    else:
        dm.pop(first)


def _matrix_hi(k: Kit) -> None:
    dm = k.doc("global.json")["damage_matrix"]
    first = next(iter(dm))
    if isinstance(dm[first], dict):
        dm[first][next(iter(dm[first]))] = 999
    else:
        dm[first][0] = 999


def _move_static(k: Kit) -> None:
    k.doc("global.json")["movement_classes"]["static"]["terrain_speed_pct"]["open"] = 100


def _move_hole(k: Kit) -> None:
    k.doc("global.json")["movement_classes"]["foot"]["terrain_speed_pct"].pop("marsh")


def _foot_on_deep(k: Kit) -> None:
    k.doc("global.json")["movement_classes"]["foot"]["terrain_speed_pct"]["deep"] = 50


def _hq_prereq(k: Kit) -> None:
    k.bible()["structures"]["structure.shared.headquarters"]["requires_all_structure_ids"] = ["structure.shared.barracks"]


def _dock_prereq(k: Kit) -> None:
    k.bible()["units"]["unit.napc.guardian_tank"]["requires_all_structure_ids"].append("structure.shared.dock")


def _summon(k: Kit, **kw: object) -> dict:
    d = {"id": "summon.napc.uav", "class": "summon", "unit_tags": ["aircraft", "summoned"], "size_class": "air_medium", "armor_class": "air_light",
         "movement_class": "air_hover", "layer": "air", "health": 60, "speed_cells_s": 6.0, "vision_cells": 7.0, "radius_cells": 0.5, "lifetime_s": 12,
         "pop_n": 0, "flags": ["no_combat_mods", "harmless"]}
    d.update(kw)
    sheet(k)["summons"] = [d]
    return d


def _summon_ok(k: Kit) -> None:
    _summon(k)


def _summon_combat(k: Kit) -> None:
    _summon(k, unit_tags=["aircraft", "summoned", "combat"])


def _summon_missing_ref(k: Kit) -> None:
    _summon(k, weapons=["weapon.napc.nope"])


def _no_health(k: Kit) -> None:
    del unit(k)["health"]
    unit(k)["archetype"] = "mbt_t1"
    k.doc("global.json")["archetypes"]["mbt_t1"].pop("health")


def _mode_no_ability(k: Kit) -> None:
    weapon(k, 1)["modes"] = [0]


def _detector_missing(k: Kit) -> None:
    k.bible()["units"]["unit.napc.guardian_tank"]["tags"].append("transport")


def _cnf09(k: Kit) -> None:
    for e in k.doc("structures.json")["structures"]:
        if e["id"] == "structure.shared.barracks":
            e["health"] = 1


def _vocab_drift(k: Kit) -> None:
    k.doc("global.json")["layers"] = k.doc("global.json")["layers"][:-1]


def _global_struct_cost(k: Kit) -> None:
    k.doc("global.json")["service_units"]["mcv"]["cost_credits"] = 1234


def _bible_tier(k: Kit) -> None:
    b = k.bible()
    u = b["units"]["unit.napc.guardian_tank"]
    for key in ("requires_all_structure_ids", "prerequisites", "requires"):
        if key in u:
            u[key] = list(u[key]) + ["structure.shared.laboratory"]
            return
    raise AssertionError("bible unit has no prerequisite key: " + ",".join(u))


MUTATIONS: list[tuple[str, str, object]] = [
    ("V-SCH-01", "wrong schema key", lambda k: sheet(k).__setitem__("schema", "meridian.balance.units/2")),
    ("V-SCH-01", "manifest lists an unknown file", lambda k: k.doc("manifest.json")["files"].append("zzz.json")),
    ("V-SCH-02", "typo key on a unit", lambda k: unit(k).__setitem__("helth", 5)),
    ("V-SCH-02", "typo key on a weapon", lambda k: weapon(k).__setitem__("dmg", 5)),
    ("V-SCH-02", "duplicate JSON key", _dup_key),
    ("V-SCH-03", "bad id shape", lambda k: unit(k).__setitem__("id", "unit.napc.Guardian Tank")),
    ("V-SCH-03", "duplicate weapon id", _dup_weapon),
    ("V-SCH-04", "4 decimals", lambda k: unit(k).__setitem__("build_time_s", 27.5001)),
    ("V-SCH-05", "non-integral health", lambda k: unit(k).__setitem__("health", 907.5)),
    ("V-SCH-06", "_pct with 3 decimals", lambda k: unit(k).__setitem__("deep_speed_pct", 60.123)),
    ("V-SCH-07", "params key without a unit suffix", lambda k: unit(k).__setitem__("params", {"foo": 3})),
    ("V-SCH-08", "bad tag name", lambda k: unit(k).__setitem__("tags_add", ["Bad Tag"])),
    ("V-SCH-09", "unsorted entries", _unsorted),
    ("V-SCH-10", "string where an integer belongs", lambda k: unit(k).__setitem__("health", "907")),
    ("V-CMP-01", "unit of another faction in the sheet", _cross_id),
    ("V-CMP-01", "duplicate unit entry", _dup_unit),
    ("V-CMP-01", "unknown unit id", lambda k: unit(k).__setitem__("id", "unit.napc.nonexistent_tank")),
    ("V-CMP-02", "structure missing from structures.json", _struct_drop),
    ("V-CMP-05", "armed unit without weapons", lambda k: unit(k).__setitem__("weapons", [])),
    ("V-CNF-01", "tier differs from the bible", lambda k: unit(k).__setitem__("tier", 3)),
    ("V-CNF-03", "locked tag in tags_add", lambda k: unit(k).__setitem__("tags_add", ["infantry"])),
    ("V-CNF-04", "bible-only field on a unit", lambda k: unit(k).__setitem__("producer", "structure.shared.factory")),
    ("V-CNF-05", "global.json vocabulary drift", _vocab_drift),
    ("V-CNF-05", "bible-fixed service unit cost differs", _global_struct_cost),
    ("V-CNF-08", "archetype-locked weapon field", lambda k: weapon(k).__setitem__("damage_type", "kinetic")),
    ("V-REF-01", "weapon id does not exist", lambda k: unit(k).__setitem__("weapons", ["weapon.napc.nope"])),
    ("V-REF-03", "orphan weapon instance", lambda k: sheet(k)["weapons"].append({"id": "weapon.napc.zz_orphan", "archetype": "tank_cannon", "damage": 100, "reload_s": 1.5, "range_cells": 7.0})),
    ("V-REF-04", "unknown archetype", lambda k: unit(k).__setitem__("archetype", "mbt_t9")),
    ("V-REF-04", "unknown movement class", lambda k: unit(k).__setitem__("movement_class", "hovercraft")),
    ("V-RNG-01", "value outside the shared RANGES", lambda k: unit(k).__setitem__("radius_cells", 40.0)),
    ("V-RNG-02", "fair-cost outlier", lambda k: unit(k).__setitem__("cost_credits", 4000)),
    ("V-RNG-03", "speed below 1 upt", lambda k: unit(k).__setitem__("speed_cells_s", 0.005)),
    ("V-RNG-04", "damage matrix hole", _matrix_hole),
    ("V-RNG-04", "damage matrix cell above 300", _matrix_hi),
    ("V-ABL-01", "unknown ability", lambda k: unit(k, PAL).__setitem__("abilities", ["ability.nope.default"])),
    ("V-ABL-01", "unknown ability param", lambda k: unit(k, PAL).__setitem__("ability_params", {"deployable_mode": {"warp_factor_n": 9}})),
    ("V-ABL-02", "two abilities of one kind", _ability_kind_twice),
    ("V-ABL-05", "archetype differs from unit_assignments", lambda k: unit(k).__setitem__("archetype", "mbt_t2")),
    ("V-ROLE-01", "anti_air tag without an air weapon", _bible_anti_air),
    ("V-ROLE-03", "infantry tag on a tracked tank", lambda k: unit(k).__setitem__("movement_class", "foot")),
    ("V-RNG-05", "static class moves", _move_static),
    ("V-RNG-05", "movement table hole", _move_hole),
    ("V-RNG-05", "foot on deep water", _foot_on_deep),
    ("V-CMP-04", "required field missing after defaults", _no_health),
    ("V-ABL-03", "weapon.modes without mode_switch", _mode_no_ability),
    ("V-ROLE-02", "transport tag without a transport ability", _detector_missing),
    ("V-ROLE-05", "summon carrying the combat tag", _summon_combat),
    ("V-REF-01", "summon references a missing weapon", _summon_missing_ref),
    ("V-CNF-09", "structure overlay repeats a global.json number differently", _cnf09),
    ("V-TIER-02", "headquarters with a prerequisite", _hq_prereq),
    ("V-TIER-03", "land unit needing the dock", _dock_prereq),
    ("V-TIER-01", "prerequisite list differs from producer + tier requirements", _bible_tier),
]


class Good(unittest.TestCase):
    def test_valid_summon_is_clean(self) -> None:
        k = Kit()
        try:
            _summon_ok(k)
            self.assertEqual([], [f.text() for f in k.run() if f.file == SHEET])
        finally:
            k.close()

    def test_example_only_lacks_the_other_bible_units(self) -> None:
        k = Kit()
        try:
            fs = k.run()
            mine = [f for f in fs if f.file in (SHEET, "structures.json", "units_shared.json", "ability_kinds.json", "manifest.json", "global.json")]
            self.assertEqual([], [f.text() for f in mine if f.rule != "V-SCH-01" or f.file != "manifest.json"], "the good example must be clean")
        finally:
            k.close()

    def test_shipped_shared_files_are_strict_clean(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = vb.main(["--strict", "--only", "manifest.json,ability_kinds.json,structures.json,units_shared.json,global.json,bible"])
        self.assertEqual(0, rc, buf.getvalue())

    def test_converter_self_test(self) -> None:
        self.assertEqual([], convert.self_test())


class Mutations(unittest.TestCase):
    pass


def _make(rule: str, fn):  # type: ignore[no-untyped-def]
    def t(self: unittest.TestCase) -> None:
        k = Kit()
        try:
            fn(k)
            got = k.run()
            self.assertIn(rule, rules_of(got), f"expected {rule}; got {sorted(rules_of(got))}")
            hit = [f for f in got if f.rule == rule][0]
            self.assertTrue(hit.file, "finding carries a file")
            self.assertTrue(hit.text().startswith(("ERROR", "WARN", "INFO")), hit.text())
        finally:
            k.close()
    return t


for _i, (_r, _d, _f) in enumerate(MUTATIONS):
    setattr(Mutations, "test_%02d_%s_%s" % (_i, _r.replace("-", "_").lower(), "".join(c if c.isalnum() else "_" for c in _d)[:40]), _make(_r, _f))


class Cli(unittest.TestCase):
    def cli(self, *args: str) -> tuple[int, str]:
        buf = io.StringIO()
        with redirect_stdout(buf), redirect_stderr(io.StringIO()):
            rc = vb.main(list(args))
        return rc, buf.getvalue()

    def test_list_rules_covers_every_rule(self) -> None:
        rc, out = self.cli("--list-rules")
        self.assertEqual(0, rc)
        for rid in RULES:
            self.assertIn(rid, out)

    def test_json_output_shape(self) -> None:
        rc, out = self.cli("--json", "--only", "units_shared.json")
        d = json.loads(out)
        self.assertEqual(0, rc)
        self.assertEqual(0, d["summary"]["errors"])

    def test_bad_only_is_usage_error(self) -> None:
        rc, _ = self.cli("--only", "units_zzz.json")
        self.assertEqual(3, rc)

    def test_every_mutated_rule_is_registered(self) -> None:
        for r, _, _ in MUTATIONS:
            self.assertIn(r, RULES)


if __name__ == "__main__":
    unittest.main()
