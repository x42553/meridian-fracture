"""weapons.py - weapon fire catalog: the 27 archetypes of TAXONOMY section 10 (tank_cannon split into
light/medium/heavy, beam_thermal into start/loop/end) plus the faction flavours of 10 families x 8 factions x 2.

Event `snd.weapon.<archetype>` -> group `sfx/weapon/<archetype>`; flavours `sfx/weapon_fx/<faction>/<archetype>`.
All weapon sounds are positional, hence mono files."""
from __future__ import annotations

from catalog import FACTIONS, AssetSpec, add

# (asset name, recipe, variants, recipe params, exciter, extra spec fields)
BASE: list[tuple] = [
    ("small_arms", "rifle_shot", 3, {}, 0.0, {"params": {"seed_name": "rifle_shot_{v}"}}),
    ("machine_gun", "mg_round", 3, {}, 0.2, {}),
    ("autocannon", "autocannon_round", 3, {}, 0.35, {}),
    ("tank_cannon_light", "tank_cannon", 2, {"k": 1.15, "length": 2.3}, 0.7, {}),
    ("tank_cannon_medium", "tank_cannon", 2, {"k": 1.0, "length": 3.0}, 0.75, {}),
    ("tank_cannon_heavy", "tank_cannon", 2, {"k": 0.8, "length": 3.6}, 0.8, {}),
    ("siege_gun", "siege_gun", 2, {}, 0.85, {}),
    ("demolition_cannon", "demolition_boom", 2, {}, 1.0, {}),
    ("at_missile", "missile_launch", 2, {"size": "mid"}, 0.3, {"lufs": -17.0}),
    ("aa_missile", "missile_launch", 2, {"size": "light", "pitch_st": 1.5}, 0.2, {"lufs": -17.0}),
    ("flak", "flak_pop", 3, {}, 0.3, {}),
    ("artillery_shell", "howitzer_thump", 2, {}, 0.9, {}),
    ("rocket_barrage", "rocket_volley", 2, {}, 0.3, {"lufs": -17.0}),
    ("mortar", "mortar_thunk", 2, {}, 0.5, {}),
    ("missile_artillery", "missile_launch", 2, {"size": "heavy"}, 0.4, {"lufs": -17.0}),
    ("beam_thermal", "beam_discharge", 1, {}, 0.3, {}),
    ("rail_gun", "rail_crack", 2, {}, 0.3, {}),
    ("torpedo", "torpedo_launch", 2, {}, 0.5, {"lufs": -17.0}),
    ("depth_charge", "depth_charge_drop", 2, {}, 0.5, {"lufs": -17.0}),
    ("bomb", "bomb_release", 2, {}, 0.4, {"lufs": -17.0}),
    ("air_missile", "missile_launch", 2, {"size": "light", "pitch_st": -1.0}, 0.2, {"lufs": -17.0}),
    ("emp_pulse", "emp_zap", 1, {}, 0.6, {}),
    ("canister", "canister_blast", 2, {}, 0.4, {}),
    ("grenade_launcher", "grenade_thump", 2, {}, 0.5, {}),
    ("breach_charge", "breach_bang", 1, {}, 0.9, {}),
    ("naval_gun", "naval_gun", 2, {}, 0.95, {}),
    ("naval_bombard", "naval_bombard", 2, {}, 0.85, {}),
    ("cruise_missile", "missile_launch", 2, {"size": "heavy", "pitch_st": 1.0}, 0.4, {"lufs": -17.0}),
    ("drone_missile", "missile_launch", 2, {"size": "light", "pitch_st": 3.5}, 0.2, {"lufs": -17.0}),
]

for name, recipe, variants, params, exc, extra in BASE:
    p = dict(params)
    p.update(extra.get("params", {}))
    add(AssetSpec(f"sfx/weapon/{name}", recipe, variants=variants, channels="mono", exciter=exc, params=p,
                  lufs=extra.get("lufs"), tags=("weapon",)))

add(AssetSpec("sfx/weapon/beam_thermal_loop", "beam_hum_loop", channels="mono", loop=True, peak_db=-6.0, lufs=-20.0,
              exciter=0.25, tags=("weapon", "beam", "loop")))
add(AssetSpec("sfx/weapon/beam_thermal_end", "beam_end", channels="mono", exciter=0.3, tags=("weapon", "beam")))

# faction weapon flavours (audio spec 5.15): pitch (semitones), brightness x, tail x, drive x, signature layer
FX: dict[str, dict] = {
    "napc": {"pitch_st": 0.0, "bright": 1.00, "tail": 1.0, "drive": 1.0, "layer": "boom_clack"},
    "nec": {"pitch_st": 1.0, "bright": 1.25, "tail": 0.6, "drive": 0.8, "layer": "sensor_tick"},
    "olm": {"pitch_st": -0.5, "bright": 0.90, "tail": 1.5, "drive": 0.9, "layer": "energy_hum"},
    "def": {"pitch_st": -2.0, "bright": 0.75, "tail": 1.3, "drive": 1.4, "layer": "brass_growl"},
    "pd": {"pitch_st": 0.5, "bright": 1.10, "tail": 1.2, "drive": 0.8, "layer": "water_slap"},
    "han": {"pitch_st": 2.0, "bright": 1.40, "tail": 0.7, "drive": 1.0, "layer": "drone_buzz"},
    "ae": {"pitch_st": -0.5, "bright": 1.00, "tail": 0.9, "drive": 1.2, "layer": "metal_clank"},
    "sap": {"pitch_st": -1.0, "bright": 0.95, "tail": 1.1, "drive": 1.1, "layer": "shield_hum"},
}
FLAVOUR_FAMILIES = ["small_arms", "machine_gun", "autocannon", "tank_cannon_medium", "tank_cannon_heavy", "siege_gun",
                    "at_missile", "artillery_shell", "beam_thermal", "rail_gun"]
_BASE_BY_NAME = {b[0]: b for b in BASE}
for fam in FLAVOUR_FAMILIES:
    _, recipe, _, params, exc, extra = _BASE_BY_NAME[fam]
    bp = dict(params)          # the flavour wraps the base recipe with the base's own parameters (not its spike seed)
    for f in FACTIONS:
        add(AssetSpec(f"sfx/weapon_fx/{f}/{fam}", "weapon_flavour", variants=2, channels="mono", exciter=exc, lufs=extra.get("lufs"),
                      params={"base": recipe, "base_params": bp, "fx": FX[f]}, tags=("weapon", "flavour"), flavour=f))
