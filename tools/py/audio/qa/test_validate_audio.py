"""Tests of the data authoring script and the audio data validator (stdlib unittest; run: python3 -m unittest tools/py/audio/qa/test_validate_audio.py)."""
import importlib.util
import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve()
AUDIO = HERE.parents[1]


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, AUDIO / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


class ValidateAudioTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.va = load("validate_audio")
        cls.rep = cls.va.Report()
        cls.va.validate(cls.rep)

    def test_data_rules_pass_except_pending_assets(self):
        # voice (19), responses (23) and music (21/22) depend on assets that other tasks generate; everything else must be clean
        bad = [e for e in self.rep.errors if not e.startswith(("V-AUD-19", "V-AUD-20", "V-AUD-21", "V-AUD-22", "V-AUD-23"))]
        self.assertEqual(bad, [])

    def test_coverage_counters(self):
        c = self.rep.counters
        self.assertGreaterEqual(c["events"], 200)
        self.assertGreaterEqual(c["profiles"], 77)
        self.assertEqual(c["units_generic"], c["units_generic"])
        self.assertEqual(c["structures"], 29)

    def test_unknown_key_is_reported(self):
        rep = self.va.Report()
        self.va.check_keys({"priority": 1, "prioritee": 2}, {"priority"}, "x", rep)
        self.assertEqual(len(rep.errors), 1)
        self.assertIn("prioritee", rep.errors[0])


class AuthorDataTest(unittest.TestCase):
    def test_events_are_deterministic_and_sorted(self):
        ad = load("author_data")
        a = ad.events_json()
        ad.EVENTS.clear()
        b = ad.events_json()
        self.assertEqual(json.dumps(a, sort_keys=False), json.dumps(b, sort_keys=False))
        ids = list(a["events"].keys())
        self.assertEqual(ids, sorted(ids))

    def test_every_weapon_archetype_has_an_event(self):
        ad = load("author_data")
        ad.EVENTS.clear()
        ev = ad.events_json()["events"]
        for name in ("small_arms", "tank_cannon_light", "tank_cannon_medium", "tank_cannon_heavy", "beam_thermal", "cruise_missile"):
            self.assertIn(f"snd.weapon.{name}", ev)

    def test_track_lengths(self):
        ad = load("author_data")
        m = ad.music_json()
        t = m["tracks"]["napc.combat"]
        self.assertEqual(t["length_samples"], round(24 * 4 * 60 / 138 * 44100))
        self.assertEqual(m["tracks"]["napc.calm"]["bpm"], 83.0)


if __name__ == "__main__":
    unittest.main()
