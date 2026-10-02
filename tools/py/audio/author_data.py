#!/usr/bin/env python3
"""author_data.py - writes game/data/audio/*.json (AUD-T6): mix, events, music, announcer, responses, factions, manifest.

The audio spec (docs/spec/audio.md 7) defines the schemas; this script is the compact authoring source of the initial
content (priorities, ranges, limits, profiles, cue tables) so the six files stay consistent with each other and with the
asset catalog (`tools/py/audio/catalog`). Stdlib only. Re-run after changing a table:

    python3 tools/py/audio/author_data.py            # writes game/data/audio/*.json
    python3 tools/py/audio/validate_audio.py --strict

Unit / structure profile tables are generated from `game/data/balance/units_*.json` and `structures.json` (the archetype of a
unit is not kept by GameData, so audio keeps its own id -> profile table in `events.json` `sim_map.unit_profile`).
"""
from __future__ import annotations

import glob
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = ROOT / "game" / "data" / "audio"
BALANCE = ROOT / "game" / "data" / "balance"
BIBLE = ROOT / "game" / "data" / "bible" / "meridian_factions.json"
FACTIONS = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]


def write(name: str, obj: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(obj, indent=1, ensure_ascii=False, sort_keys=False) + "\n"
    (OUT / name).write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------------------------------------- mix.json
def mix() -> dict:
    return {
        "schema": "meridian.audio.mix/1",
        "engine": {"mix_rate": 44100, "output_latency_ms": 15},
        "buses": [
            {"name": "Master", "send": "", "volume_db": 0.0, "effects": [
                {"id": "night", "type": "compressor", "enabled": False, "threshold_db": -24.0, "ratio": 3.0, "attack_us": 20000.0, "release_ms": 250.0, "gain_db": 4.0},
                {"id": "muffle", "type": "lowpass", "enabled": False, "cutoff_hz": 1200.0},
                {"id": "limiter", "type": "hard_limiter", "enabled": True, "ceiling_db": -1.0, "pre_gain_db": 0.0, "release": 0.1}]},
            {"name": "Music", "send": "Master", "volume_db": -6.0, "effects": [
                {"id": "duck_ann", "type": "compressor", "enabled": True, "sidechain": "Announcer", "threshold_db": -18.0, "ratio": 3.0, "attack_us": 12000.0, "release_ms": 450.0, "gain_db": 0.0},
                {"id": "duck_heavy", "type": "compressor", "enabled": True, "sidechain": "SfxHeavy", "threshold_db": -12.0, "ratio": 2.0, "attack_us": 8000.0, "release_ms": 350.0, "gain_db": 0.0}]},
            {"name": "Sfx", "send": "Master", "volume_db": -2.0, "effects": []},
            {"name": "Ambience", "send": "Master", "volume_db": -8.0, "effects": [
                {"id": "duck_heavy", "type": "compressor", "enabled": True, "sidechain": "SfxHeavy", "threshold_db": -16.0, "ratio": 2.5, "attack_us": 8000.0, "release_ms": 400.0, "gain_db": 0.0}]},
            {"name": "Ui", "send": "Master", "volume_db": -2.0, "effects": []},
            {"name": "Voice", "send": "Master", "volume_db": 0.0, "effects": []},
            {"name": "Announcer", "send": "Voice", "volume_db": 0.0, "effects": []},
            {"name": "SfxHeavy", "send": "Sfx", "volume_db": 0.0, "effects": []},
        ],
        "pool": {"voices_3d": {"low": 24, "medium": 40, "high": 48}, "voices_2d": 16, "reserve_high_slots": 6, "reserve_high_priority": 70,
                 "max_starts_per_frame": 24, "steal_margin": 1.0, "age_penalty_per_s": 1.0, "cull_below_db": -42.0},
        "camera": {"ref_height_m": 55.0, "zoom_scale_min": 0.6, "zoom_scale_max": 2.0, "listener_height_m": 2.0,
                   "source_height_ground_m": 1.5, "source_height_air_m": 22.0, "focus_smooth_s": 0.08},
        "hearing": {"max_scan_m": 750.0, "loud_fog_radius_m": 300.0, "fog_muffled_gain_db": -9.0, "fog_muffled_lowpass_hz": 1200.0, "offscreen_alert_m": 45.0},
        "loops": {"budget": {"low": 8, "medium": 12, "high": 16}, "scan_period_s": 0.25, "radius_m": 90.0, "hysteresis_db": 3.0,
                  "fade_in_ms": 120, "fade_out_ms": 200, "pitch_speed_lo": 0.85, "pitch_speed_hi": 1.15, "max_candidates": 160},
        "propagation": {"speed_mps": 900.0, "max_delay_ms": 400},
        "size_thresholds_units": {"small": 819, "medium": 1536, "large": 2560},
        "replay": {"gate_priority_above_2x": 80},
        "strategic": {"helios_length_cells": 16.0},
        "terrain": {"material": ["water", "water", "water", "dirt", "dirt", "dirt", "dirt", "concrete", "wood", "concrete", "concrete", "concrete", "concrete", "concrete", "concrete"],
                    "_ids": "MapTerrain 0..14: deep_water shallow ford beach grass dirt sand rock forest road pavement rubble urban_block cliff mountain"},
        "ambience": {"scan_period_s": 0.5, "radius_m": 24.0, "grid_cells": 8, "water_weight": [1.0, 1.0, 0.5], "forest_id": 8,
                     "family_wind_db": [0.0, -9.0, -3.0], "coast_floor_db": -9.0,
                     "full": {"coast": 0.25, "river": 0.15, "forest": 0.33, "far_heat": 40.0},
                     "trim_db": {"river": -3.0, "forest": -3.0, "battle_far": -6.0},
                     "start_db": -40.0, "stop_db": -46.0, "stop_after_s": 3.0, "fade_in_s": 1.5, "fade_out_s": 2.5, "detail_zoom_db_per_unit": -6.0,
                     "biome": [{"name": "temperate", "wind_db": 0.0, "wind_pitch": 1.0, "forest_db": 0.0},
                               {"name": "desert", "wind_db": 2.0, "wind_pitch": 1.06, "forest_db": -8.0},
                               {"name": "arctic", "wind_db": 3.0, "wind_pitch": 0.92, "forest_db": -4.0},
                               {"name": "tropical", "wind_db": -3.0, "wind_pitch": 1.0, "forest_db": 4.0}]},
    }


# -------------------------------------------------------------------------------------------------------- events.json
def asset_of(eid: str) -> str:
    """Event id -> asset group / id (catalog rule, tools/py/audio/catalog/__init__.py)."""
    p = eid.split(".")[1:]
    fam = p[0]
    if eid == "snd.emp.hit":
        return "sfx/impact/emp"
    if fam in ("ui", "alarm", "amb"):
        return f"{fam}/" + "_".join(p[1:])
    return f"sfx/{fam}/" + "_".join(p[1:])


def flavour_families() -> set[str]:
    """Weapon events (asset group names under sfx/weapon) that have a per-faction flavour group in the asset catalog."""
    try:
        sys.path.insert(0, str(ROOT / "tools" / "py" / "audio"))
        from catalog import all_specs  # type: ignore
        fam = {s.id.split("/")[-1] for s in all_specs() if s.id.startswith("sfx/weapon_fx/napc/")}
        if fam:
            return fam
    except Exception:  # noqa: BLE001 - catalog optional; fall back to the spec's ten families
        pass
    return {"small_arms", "machine_gun", "autocannon", "tank_cannon_medium", "tank_cannon_heavy", "siege_gun", "at_missile", "artillery_shell", "beam_thermal", "rail_gun"}


EVENTS: dict[str, dict] = {}


def ev(eid: str, prio: int, *, cat: str, vol: float = 0.0, bus: str = "Sfx", mode: str = "3d", unit: float = 20.0, maxd: float = 0.0,
       atten: str = "inverse", lp: float | None = None, fog: str = "hidden", prop: bool = False, group: str | None = None, inst: int = 8,
       min_ms: int = 0, steal: str = "oldest", loop: bool = False, jit: float = 0.0, pj: float = 0.0, flav: bool = False,
       fade_in: int | None = None, fade_out: int | None = None, link: dict | None = None, cull: float | None = None,
       doppler: bool = False, asset: str | None = None, pan: float | None = None) -> None:
    e: dict = {"category": cat, "bus": bus, "priority": prio, "variants": [{"group": asset or asset_of(eid)}]}
    if flav:
        name = (asset or asset_of(eid)).split("/")[-1]
        e["flavours"] = {f: [{"group": f"sfx/weapon_fx/{f}/{name}"}] for f in FACTIONS}
    e["volume_db"] = vol
    if jit:
        e["volume_jitter_db"] = jit
    if pj:
        e["pitch_jitter_semitones"] = pj
    if cull is not None:
        e["cull_below_db"] = cull
    sp: dict = {"mode": mode}
    if mode == "3d":
        sp.update({"unit_size_m": unit, "max_distance_m": maxd, "attenuation": atten})
        if lp is not None:
            sp["lowpass_hz"] = lp
        if pan is not None:
            sp["panning_strength"] = pan
        if doppler:
            sp["doppler"] = True
        if prop:
            sp["propagation"] = True
        sp["fog"] = fog
    e["spatial"] = sp
    lim: dict = {"max_instances": inst, "steal": steal}
    if group:
        lim["group"] = group
    if min_ms:
        lim["min_interval_ms"] = min_ms
    e["limit"] = lim
    if loop:
        e["loop"] = True
        e["fade_in_ms"] = 120 if fade_in is None else fade_in
        e["fade_out_ms"] = 200 if fade_out is None else fade_out
    if link:
        e["link"] = link
    EVENTS[eid] = e


def build_events() -> None:
    fam = flavour_families()
    # ---- weapon fire: (name, priority, unit, max, group, instances, min_ms, volume, bus, fog, prop, lowpass)
    W = [
        ("small_arms", 28, 22, 170, "small_arms", 6, 35, -3.0, "Sfx", "hidden", False, 9000),
        ("machine_gun", 30, 22, 170, "small_arms", 5, 45, -3.0, "Sfx", "hidden", False, 9000),
        ("autocannon", 38, 28, 200, "small_arms", 4, 60, -2.0, "Sfx", "hidden", False, 9500),
        ("tank_cannon_light", 52, 34, 260, "heavy", 4, 90, -1.0, "Sfx", "hidden", False, 11000),
        ("tank_cannon_medium", 58, 40, 300, "heavy", 4, 90, 0.0, "Sfx", "hidden", False, 12000),
        ("tank_cannon_heavy", 64, 50, 340, "heavy", 3, 120, 0.0, "Sfx", "hidden", False, 12000),
        ("siege_gun", 62, 55, 380, "heavy", 3, 150, 0.0, "Sfx", "hidden", False, 12000),
        ("demolition_cannon", 66, 55, 380, "heavy", 2, 250, 0.0, "Sfx", "hidden", False, 12000),
        ("at_missile", 46, 34, 260, "heavy", 4, 100, -1.0, "Sfx", "hidden", False, 10000),
        ("aa_missile", 46, 34, 260, "heavy", 4, 80, -1.0, "Sfx", "hidden", False, 10000),
        ("flak", 40, 30, 220, "small_arms", 4, 60, -2.0, "Sfx", "hidden", False, 9500),
        ("artillery_shell", 66, 70, 450, "heavy", 3, 200, 0.0, "SfxHeavy", "muffled", True, 12000),
        ("rocket_barrage", 54, 45, 320, "heavy", 4, 60, -1.0, "Sfx", "hidden", False, 10000),
        ("mortar", 50, 34, 260, "heavy", 3, 150, -1.0, "Sfx", "hidden", False, 10000),
        ("missile_artillery", 62, 60, 420, "heavy", 3, 200, 0.0, "Sfx", "hidden", False, 11000),
        ("rail_gun", 62, 60, 420, "heavy", 3, 250, 0.0, "SfxHeavy", "muffled", False, 12000),
        ("torpedo", 48, 34, 260, "heavy", 3, 300, -1.0, "Sfx", "hidden", False, 9000),
        ("depth_charge", 52, 34, 260, "heavy", 3, 300, -1.0, "Sfx", "hidden", False, 9000),
        ("bomb", 50, 34, 260, "heavy", 4, 100, -1.0, "Sfx", "hidden", False, 10000),
        ("air_missile", 46, 34, 260, "heavy", 4, 90, -1.0, "Sfx", "hidden", False, 10000),
        ("emp_pulse", 62, 45, 350, "heavy", 3, 250, 0.0, "Sfx", "hidden", False, 12000),
        ("canister", 46, 30, 220, "heavy", 4, 100, -1.0, "Sfx", "hidden", False, 10000),
        ("grenade_launcher", 40, 24, 180, "small_arms", 4, 100, -2.0, "Sfx", "hidden", False, 9500),
        ("breach_charge", 56, 26, 190, "heavy", 3, 300, 0.0, "Sfx", "hidden", False, 11000),
        ("naval_gun", 58, 55, 380, "heavy", 3, 200, 0.0, "Sfx", "hidden", False, 11000),
        ("naval_bombard", 68, 70, 460, "heavy", 3, 300, 0.0, "SfxHeavy", "muffled", True, 12000),
        ("cruise_missile", 62, 60, 420, "heavy", 3, 300, 0.0, "Sfx", "muffled", False, 11000),
        ("drone_missile", 42, 30, 220, "small_arms", 4, 80, -2.0, "Sfx", "hidden", False, 9500),
    ]
    for name, pr, u, mx, grp, inst, mn, vol, bus, fog, prop, lp in W:
        ev(f"snd.weapon.{name}", pr, cat="weapon", vol=vol, bus=bus, unit=u, maxd=mx, lp=lp, fog=fog, prop=prop, group=grp, inst=inst,
           min_ms=mn, jit=1.0 if pr >= 46 else 1.5, pj=0.6 if pr >= 46 else 0.8, flav=name in fam)
    ev("snd.weapon.beam_thermal", 52, cat="weapon", unit=40, maxd=300, lp=10000, group="loops", inst=6, min_ms=200, link={"loop": "snd.weapon.beam_thermal.loop", "end": "snd.weapon.beam_thermal.end"}, flav="beam_thermal" in fam)
    ev("snd.weapon.beam_thermal.loop", 20, cat="weapon", vol=-2.0, unit=30, maxd=220, lp=8000, group="loops", inst=6, loop=True, fade_in=150, fade_out=200)
    ev("snd.weapon.beam_thermal.end", 40, cat="weapon", unit=30, maxd=220, lp=9000, group="loops", inst=6)
    # ---- projectile flight (missile / torpedo are path-voice loops)
    ev("snd.proj.missile", 20, cat="proj", vol=-4.0, unit=25, maxd=200, lp=8000, group="loops", inst=6, loop=True, fade_in=60, fade_out=60)
    ev("snd.proj.torpedo", 20, cat="proj", vol=-4.0, unit=25, maxd=200, lp=6000, group="loops", inst=4, loop=True, fade_in=60, fade_out=60)
    ev("snd.proj.shell_whistle", 44, cat="proj", vol=-3.0, unit=40, maxd=260, lp=10000, group="impacts", inst=3, min_ms=150, fog="hidden")
    ev("snd.proj.bomb_whistle", 44, cat="proj", vol=-3.0, unit=40, maxd=260, lp=10000, group="impacts", inst=3, min_ms=150)
    # ---- impacts
    for mat, pr in (("dirt", 24), ("concrete", 28), ("metal", 30), ("flesh", 26), ("wood", 26), ("water", 24)):
        ev(f"snd.impact.bullet.{mat}", pr, cat="impact", vol=-6.0, unit=12, maxd=100, lp=9000, group="impacts", inst=4, min_ms=60, jit=1.5, pj=1.0)
    ev("snd.impact.energy.small", 34, cat="impact", vol=-5.0, unit=14, maxd=120, lp=10000, group="impacts", inst=4, min_ms=100, jit=1.0, pj=0.6)
    ev("snd.impact.energy.large", 40, cat="impact", vol=-3.0, unit=25, maxd=200, lp=10000, group="impacts", inst=3, min_ms=120)
    ev("snd.impact.rail", 44, cat="impact", vol=-3.0, unit=30, maxd=240, lp=12000, group="impacts", inst=3, min_ms=150)
    ev("snd.impact.kinetic", 60, cat="impact", vol=-1.0, unit=45, maxd=350, lp=12000, group="impacts", inst=2, min_ms=250, fog="muffled", bus="SfxHeavy")
    ev("snd.impact.emp", 50, cat="impact", vol=-3.0, unit=35, maxd=260, lp=11000, group="impacts", inst=2, min_ms=250)
    # ---- explosions, collapses, deaths
    ev("snd.explosion.small", 50, cat="explosion", vol=-3.0, unit=30, maxd=240, lp=11000, group="explosions", inst=4, min_ms=60, jit=1.0, pj=0.8)
    ev("snd.explosion.medium", 60, cat="explosion", vol=-1.0, unit=42, maxd=320, lp=12000, group="explosions", inst=3, min_ms=80, jit=1.0, pj=0.6)
    ev("snd.explosion.large", 80, cat="explosion", vol=0.0, unit=60, maxd=440, lp=12000, group="explosions", inst=3, min_ms=120, fog="muffled", prop=True, bus="SfxHeavy", cull=-46.0)
    ev("snd.explosion.huge", 85, cat="explosion", vol=0.0, unit=90, maxd=650, lp=12000, group="explosions", inst=2, min_ms=200, fog="muffled", prop=True, bus="SfxHeavy", cull=-50.0)
    ev("snd.explosion.water.small", 46, cat="explosion", vol=-3.0, unit=28, maxd=220, lp=9000, group="explosions", inst=3, min_ms=80)
    ev("snd.explosion.water.medium", 56, cat="explosion", vol=-2.0, unit=40, maxd=300, lp=9000, group="explosions", inst=3, min_ms=100)
    ev("snd.explosion.water.large", 70, cat="explosion", vol=0.0, unit=55, maxd=420, lp=9000, group="explosions", inst=2, min_ms=150, fog="muffled", bus="SfxHeavy")
    for i, (pr, u, mx) in enumerate(((50, 30, 240), (60, 40, 320), (88, 60, 450), (90, 80, 600)), start=1):
        big = i >= 3
        ev(f"snd.collapse.s{i}", pr, cat="collapse", vol=0.0 if big else -2.0, unit=u, maxd=mx, lp=11000, group="explosions", inst=2, min_ms=100,
           fog="muffled" if big else "hidden", prop=big, bus="SfxHeavy" if big else "Sfx")
    ev("snd.death.infantry", 22, cat="death", vol=-5.0, unit=14, maxd=110, lp=9000, group="impacts", inst=4, min_ms=50, jit=1.5, pj=1.0)
    ev("snd.death.decoy", 30, cat="death", vol=-3.0, unit=20, maxd=160, lp=10000, group="impacts", inst=2, min_ms=100)
    ev("snd.death.ship", 64, cat="death", vol=-1.0, unit=50, maxd=380, lp=9000, group="explosions", inst=2, min_ms=200, fog="muffled")
    ev("snd.death.sub", 60, cat="death", vol=-1.0, unit=45, maxd=340, lp=8000, group="explosions", inst=2, min_ms=200)
    ev("snd.death.drone", 30, cat="death", vol=-4.0, unit=18, maxd=140, lp=10000, group="impacts", inst=3, min_ms=80)
    ev("snd.intercept.aps", 55, cat="intercept", vol=-2.0, unit=25, maxd=200, lp=11000, group="impacts", inst=3, min_ms=100)
    ev("snd.intercept.zone", 55, cat="intercept", vol=-2.0, unit=30, maxd=240, lp=11000, group="impacts", inst=3, min_ms=100)
    ev("snd.emp.hit", 50, cat="intercept", vol=-2.0, unit=35, maxd=260, lp=11000, group="impacts", inst=2, min_ms=250)
    # ---- movement loops and air one-shots
    ev("snd.loop.step.foot", 12, cat="loop", vol=-2.0, unit=10, maxd=70, lp=6000, group="loops", inst=10, loop=True)
    for nm, pr, u, mx, vol in (("wheeled", 15, 16, 110, -1.0), ("tracked", 16, 18, 120, -1.0), ("tracked_heavy", 17, 22, 140, 0.0), ("amphibious", 15, 18, 120, -1.0),
                               ("boat_small", 15, 20, 130, -1.0), ("boat_large", 16, 30, 200, 0.0), ("sub", 14, 18, 110, -2.0)):
        ev(f"snd.loop.engine.{nm}", pr, cat="loop", vol=vol, unit=u, maxd=mx, lp=6000, group="loops", inst=12, loop=True)
    ev("snd.loop.air.jet", 18, cat="loop", vol=-1.0, unit=40, maxd=300, lp=8000, group="loops", inst=6, loop=True, doppler=True)
    ev("snd.loop.air.rotor", 18, cat="loop", vol=-1.0, unit=35, maxd=260, lp=8000, group="loops", inst=6, loop=True)
    ev("snd.loop.air.drone", 16, cat="loop", vol=-3.0, unit=18, maxd=110, lp=8000, group="loops", inst=8, loop=True)
    ev("snd.air.takeoff", 45, cat="air", vol=-2.0, unit=40, maxd=300, lp=9000, group="impacts", inst=3, min_ms=400)
    ev("snd.air.landing", 45, cat="air", vol=-2.0, unit=40, maxd=300, lp=9000, group="impacts", inst=3, min_ms=400)
    ev("snd.air.crash_fall", 60, cat="air", vol=-1.0, unit=45, maxd=340, lp=9000, group="explosions", inst=3, min_ms=200, fog="muffled")
    # ---- structures and economy
    for kind in ("hq", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory", "watchtower", "turret",
                 "aa_battery", "relay", "superweapon", "adv_defense"):
        ev(f"snd.struct.online.{kind}", 45, cat="struct", vol=-3.0, unit=30, maxd=220, lp=11000, group="struct", inst=3, min_ms=300)
    ev("snd.struct.sell", 42, cat="struct", vol=-3.0, unit=28, maxd=200, lp=11000, group="struct", inst=3, min_ms=250)
    ev("snd.struct.repair", 14, cat="struct", vol=-4.0, unit=16, maxd=100, lp=8000, group="loops", inst=6, loop=True)
    ev("snd.struct.power_down", 92, cat="struct", vol=-2.0, mode="global", group="struct", inst=1, min_ms=1500)
    ev("snd.struct.power_up", 90, cat="struct", vol=-2.0, mode="global", group="struct", inst=1, min_ms=1500)
    ev("snd.struct.defense_offline", 55, cat="struct", vol=-3.0, unit=30, maxd=220, lp=10000, group="struct", inst=3, min_ms=500)
    for cls in ("infantry", "vehicle", "aircraft", "ship"):
        ev(f"snd.struct.unit_out.{cls}", 40, cat="struct", vol=-4.0, unit=25, maxd=180, lp=10000, group="struct", inst=2, min_ms=250)
    ev("snd.struct.captured", 65, cat="struct", vol=-2.0, unit=35, maxd=260, lp=11000, group="struct", inst=2, min_ms=500, fog="audible")
    ev("snd.struct.salvage", 14, cat="struct", vol=-4.0, unit=20, maxd=130, lp=8000, group="loops", inst=4, loop=True)
    ev("snd.struct.hq_deploy", 60, cat="struct", vol=-2.0, unit=35, maxd=260, lp=11000, group="struct", inst=2, min_ms=500)
    for kind in ("generator", "radar", "lab", "airfield", "refinery"):
        ev(f"snd.struct.hum.{kind}", 11, cat="loop", vol=-4.0, unit=14, maxd=100, lp=6000, group="loops", inst=8, loop=True)
    ev("snd.eco.cash", 35, cat="eco", vol=-4.0, mode="global", group="ui", inst=3, min_ms=120, jit=1.0, pj=0.5)
    ev("snd.eco.cash_big", 90, cat="eco", vol=-3.0, mode="global", group="ui", inst=2, min_ms=300)
    # ---- support powers
    for cls in ("recon", "repair", "buff", "shield", "cloak", "smoke", "barrage", "generic"):
        ev(f"snd.power.{cls}.activate", 62, cat="power", vol=-2.0, unit=60, maxd=400, lp=12000, group="power", inst=3, min_ms=300, fog="hidden")
        ev(f"snd.power.{cls}.loop", 30, cat="power", vol=-6.0, unit=40, maxd=250, lp=9000, group="power", inst=3, loop=True)
        ev(f"snd.power.{cls}.end", 45, cat="power", vol=-3.0, unit=45, maxd=300, lp=11000, group="power", inst=3, min_ms=300)
    ev("snd.power.barrage.warning", 90, cat="power", vol=-2.0, mode="global", group="power", inst=1, min_ms=1000)
    ev("snd.power.barrage.impact", 62, cat="power", vol=0.0, unit=60, maxd=420, lp=12000, group="power", inst=3, min_ms=120, fog="muffled", prop=True)
    # ---- superweapons: (name, {phase: mode}) as generated by the catalog
    SW = {
        "atlas": {"launch": "global", "impact": "3d"},
        "aurora": {"charge": "global", "launch": "global", "loop": "3d", "impact": "global", "end": "global"},
        "helios": {"charge": "global", "launch": "global", "loop": "3d", "end": "global"},
        "perun": {"launch": "3d", "impact": "3d"},
        "tempest": {"launch": "3d", "loop": "3d", "end": "global"},
        "dragonfall": {"launch": "global", "loop": "3d", "impact": "3d", "end": "global"},
        "horizon": {"charge": "global", "launch": "3d", "impact": "3d"},
        "trident": {"launch": "global", "loop": "3d", "end": "global"},
    }
    for name, phases in SW.items():
        for ph, mode in phases.items():
            eid = f"snd.sw.{name}.{ph}"
            if ph == "charge":
                ev(eid, 30, cat="power", vol=-6.0, mode="global", group="strategic", inst=1, loop=True, fade_in=400, fade_out=400)
            elif ph == "loop":
                ev(eid, 45, cat="power", vol=-3.0, unit=80, maxd=800, lp=11000, fog="audible", group="strategic", inst=2, loop=True, fade_in=300, fade_out=500)
            elif ph == "launch":
                if mode == "3d":
                    ev(eid, 92, cat="power", vol=0.0, unit=90, maxd=800, lp=12000, fog="audible", group="strategic", inst=2, bus="SfxHeavy")
                else:
                    ev(eid, 92, cat="power", vol=-1.0, mode="global", group="strategic", inst=2)
            elif ph == "impact":
                if mode == "3d":
                    ev(eid, 90, cat="power", vol=0.0, unit=100, maxd=900, lp=12000, fog="audible", prop=True, group="strategic", inst=4, min_ms=100, bus="SfxHeavy", cull=-50.0)
                else:
                    ev(eid, 90, cat="power", vol=-1.0, mode="global", group="strategic", inst=2, bus="SfxHeavy")
            else:
                ev(eid, 60, cat="power", vol=-2.0, mode="global", group="strategic", inst=2)
    # ---- alarms (Ui bus: never ducked by gameplay sound)
    ev("snd.alarm.sw_siren", 97, cat="alarm", vol=-3.0, bus="Ui", mode="global", group="strategic", inst=2, loop=True, fade_in=300, fade_out=300)
    ev("snd.alarm.countdown_tick", 96, cat="alarm", vol=-3.0, bus="Ui", mode="global", group="ui", inst=2)
    ev("snd.alarm.countdown_final", 97, cat="alarm", vol=-2.0, bus="Ui", mode="global", group="ui", inst=1)
    ev("snd.alarm.base_attack", 95, cat="alarm", vol=-3.0, bus="Ui", mode="global", group="ui", inst=1, min_ms=3000)
    ev("snd.alarm.incoming", 96, cat="alarm", vol=-3.0, bus="Ui", mode="global", group="ui", inst=1, min_ms=3000)
    ev("snd.alarm.low_power", 93, cat="alarm", vol=-3.0, bus="Ui", mode="global", group="ui", inst=1, min_ms=3000)
    # ---- UI
    ui = ["click", "hover", "confirm", "error", "back", "tab", "toggle_on", "toggle_off", "slider_tick", "queue_add", "queue_cancel", "queue_hold",
          "build_ready", "place_ok", "place_fail", "sell_mode", "repair_mode", "group_set", "group_recall", "waypoint", "rally_set", "minimap_ping",
          "minimap_click", "alert", "chat", "lobby_join", "lobby_leave", "lobby_ready", "lobby_countdown_tick", "lobby_start", "menu_transition", "notify"]
    for name in ui:
        ev(f"snd.ui.{name}", 95, cat="ui", vol=0.0, bus="Ui", mode="ui", group="ui", inst=3, min_ms=30, pj=0.2)
    # ---- ambience beds (flat looped stereo on the Ambience bus, played by SndAmbience)
    for bed in ("wind_open", "city_hum", "coast_waves", "river_flow", "forest", "battle_far"):
        ev(f"snd.amb.{bed}", 5, cat="ambience", vol=0.0, bus="Ambience", mode="ui", inst=1, loop=True, fade_in=1500, fade_out=2500)


# ------------------------------------------------------------------------------------------------------------ profiles
def build_profiles() -> tuple[dict, dict, dict]:
    """(profiles, unit_profile table, structure_profile table)."""
    P: dict = {}

    def loops(*rows: tuple) -> list:
        return [{"event": e, "when": w, "gain_db": g, "pitch_speed": ps} for (e, w, g, ps) in rows]

    foot = loops(("snd.loop.step.foot", "moving", 0.0, True))
    whl = loops(("snd.loop.engine.wheeled", "moving", 0.0, True))
    trk = loops(("snd.loop.engine.tracked", "moving", 0.0, True))
    trk_h = loops(("snd.loop.engine.tracked_heavy", "moving", 0.0, True))
    amph = loops(("snd.loop.engine.amphibious", "moving", 0.0, True))
    boat_s = loops(("snd.loop.engine.boat_small", "moving", 0.0, True))
    boat_l = loops(("snd.loop.engine.boat_large", "moving", 0.0, True))
    sub = loops(("snd.loop.engine.sub", "moving", 0.0, True))
    jet = loops(("snd.loop.air.jet", "airborne", 0.0, True))
    rotor = loops(("snd.loop.air.rotor", "airborne", 0.0, True))
    drone = loops(("snd.loop.air.drone", "airborne", 0.0, True))
    role = {  # archetype -> (voice class, loops, weapon_variant)
        "inf_line": ("infantry", foot, None), "inf_at": ("infantry", foot, None), "inf_combat_spec": ("infantry", foot, None),
        "inf_support": ("support", foot, None),
        "veh_scout": ("vehicle", whl, None), "veh_aa": ("vehicle", whl, None), "veh_aa_flak": ("vehicle", whl, None), "veh_aa_beam": ("vehicle", whl, None),
        "veh_command": ("heavy", trk, {"tank_cannon": "medium"}), "veh_assault_carrier": ("heavy", trk_h, None),
        "mbt_t1": ("vehicle", trk, {"tank_cannon": "light"}), "mbt_t2": ("vehicle", trk, {"tank_cannon": "medium"}),
        "mbt_t2_rail": ("vehicle", trk, {"tank_cannon": "medium"}),
        "siege_ap": ("heavy", trk_h, {"tank_cannon": "heavy"}), "siege_he": ("heavy", trk_h, None), "siege_demo": ("heavy", trk_h, None),
        "siege_rail": ("heavy", trk_h, None), "siege_beam": ("heavy", trk_h, None),
        "arty_light": ("vehicle", whl, None), "arty_howitzer": ("vehicle", trk, None), "arty_missile": ("vehicle", whl, None), "arty_rocket": ("vehicle", whl, None),
        "air_fighter": ("air", jet, None), "air_bomber": ("air", jet, None), "air_gunship": ("air", rotor, None), "air_ew": ("air", jet, None),
        "air_drone": ("air", drone, None),
        "ship_escort": ("naval", boat_s, None), "ship_patrol": ("naval", boat_s, None), "ship_siege": ("naval", boat_l, None),
        "ship_carrier": ("naval", boat_l, None), "ship_sub": ("naval", sub, None),
    }
    for name, (vc, lp, wv) in role.items():
        p: dict = {"voice_class": vc, "loops": lp}
        if wv:
            p["weapon_variant"] = wv
        P[f"snd.profile.{name}"] = p
    P["snd.profile.svc_engineer"] = {"voice_class": "support", "loops": foot}
    P["snd.profile.svc_collector"] = {"voice_class": "support", "loops": trk_h}
    P["snd.profile.svc_mcv"] = {"voice_class": "support", "loops": trk_h}
    P["snd.profile.svc_landing_transport"] = {"voice_class": "support", "loops": amph}
    P["snd.profile.summon_drone"] = {"voice_class": "air", "loops": drone}
    P["snd.profile.summon_capsule"] = {"voice_class": "support", "loops": []}
    P["snd.profile.decoy"] = {"voice_class": "vehicle", "loops": whl}
    gen = {"foot": ("infantry", foot), "wheeled": ("vehicle", whl), "tracked": ("vehicle", trk), "amphibious": ("vehicle", amph),
           "naval": ("naval", boat_s), "submerged": ("naval", sub), "air_fixed": ("air", jet), "air_hover": ("air", rotor), "static": ("structure", [])}
    for name, (vc, lp) in gen.items():
        P[f"snd.profile.generic.{name}"] = {"voice_class": vc, "loops": lp}
    hum = {"generator": "generator", "refinery": "refinery", "radar": "radar", "laboratory": "lab", "airfield": "airfield"}
    for kind in ("hq", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory", "watchtower", "turret", "aa_battery", "relay"):
        lp = loops((f"snd.struct.hum.{hum[kind]}", "structure_active", 0.0, False)) if kind in hum else []
        P[f"snd.profile.struct.{kind}"] = {"voice_class": "structure", "loops": lp}
    for f in FACTIONS:
        P[f"snd.profile.struct.sw_{f}"] = {"voice_class": "structure", "loops": []}
        P[f"snd.profile.struct.adv_{f}"] = {"voice_class": "structure", "loops": []}
    # ---- id tables from the balance sheets
    unit_profile: dict = {}
    for path in sorted(glob.glob(str(BALANCE / "units_*.json"))):
        d = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        for u in d.get("units", []):
            a = u.get("archetype", "")
            if a.startswith("service."):
                unit_profile[u["id"]] = "snd.profile.svc_" + {"collector": "collector", "engineer": "engineer", "mcv": "mcv", "landing_transport": "landing_transport"}[a.split(".")[1]]
            else:
                unit_profile[u["id"]] = f"snd.profile.{a}"
        for s in d.get("summons", []):
            mc = s.get("movement_class", "tracked")
            if s.get("class") == "drone":
                unit_profile[s["id"]] = "snd.profile.summon_drone"
            elif "decoy" in s["id"]:
                unit_profile[s["id"]] = "snd.profile.decoy"
            elif mc == "static":
                unit_profile[s["id"]] = "snd.profile.summon_capsule"
            else:
                unit_profile[s["id"]] = f"snd.profile.generic.{mc}"
    struct_profile: dict = {}
    sws = {"atlas_kinetic_array", "aurora_microwave_array", "helios_reflector", "perun_missile_complex", "tempest_swarm_hub", "dragonfall_field_foundry",
           "horizon_mass_driver", "trident_interception_array"}
    st = json.loads((BALANCE / "structures.json").read_text(encoding="utf-8"))["structures"]
    for s in st:
        sid = s["id"]
        parts = sid.split(".")
        if parts[1] == "shared":
            nm = {"anti_tank_turret": "turret", "headquarters": "hq"}.get(parts[2], parts[2])
            struct_profile[sid] = f"snd.profile.struct.{nm}"
        elif parts[2] == "relay":
            struct_profile[sid] = "snd.profile.struct.relay"
        elif parts[2] in sws:
            struct_profile[sid] = f"snd.profile.struct.sw_{parts[1]}"
        else:
            struct_profile[sid] = f"snd.profile.struct.adv_{parts[1]}"
    return P, dict(sorted(unit_profile.items())), dict(sorted(struct_profile.items()))


POWER_CLASS = {
    "recon": ["uav_sweep", "survey_drone", "maritime_patrol", "long_watch", "wideband_scan", "survey_network", "recon_balloon", "counterbattery_solution"],
    "repair": ["field_repair_drop", "floating_workshop", "mobile_workshop", "expeditionary_workshop", "repair_swarm", "field_refurbishment"],
    "shield": ["emergency_earthworks", "redundant_orders", "steel_advance", "joint_landing", "emergency_fortification", "protected_advance"],
    "cloak": ["silent_watch", "false_convoy", "false_front", "feint_landing"],
    "smoke": ["dust_screen", "broken_contact", "concealed_crossing"],
    "barrage": ["counterbattery_mission", "tremor_barrage", "counterlaunch_plot"],
}


def power_cues() -> dict:
    bible = json.loads(BIBLE.read_text(encoding="utf-8"))
    by_name = {n: c for c, names in POWER_CLASS.items() for n in names}
    out = {}
    for pid in bible["support_powers"]:
        out[pid] = by_name.get(pid.split(".")[-1], "buff")
    return out


def sw_cues() -> dict:
    bible = json.loads(BIBLE.read_text(encoding="utf-8"))
    out = {}
    for sid in bible["superweapons"]:
        nm = sid.split(".")[-1]
        out[sid] = {"atlas_kinetic_array": "atlas", "aurora_microwave_array": "aurora", "helios_reflector": "helios", "perun_missile_complex": "perun",
                    "tempest_swarm_hub": "tempest", "dragonfall_field_foundry": "dragonfall", "horizon_mass_driver": "horizon",
                    "trident_interception_array": "trident"}[nm]
    return out


def events_json() -> dict:
    build_events()
    profiles, unit_profile, struct_profile = build_profiles()
    return {
        "schema": "meridian.audio.events/2",
        "groups": {"explosions": {"max_voices": 6}, "heavy": {"max_voices": 8}, "impacts": {"max_voices": 8}, "loops": {"max_voices": 16},
                   "power": {"max_voices": 4}, "small_arms": {"max_voices": 10}, "strategic": {"max_voices": 4}, "struct": {"max_voices": 6},
                   "ui": {"max_voices": 6}},
        "events": dict(sorted(EVENTS.items())),
        "profiles": dict(sorted(profiles.items())),
        "power_cues": power_cues(),
        "sw_cues": sw_cues(),
        "sim_map": {
            "weapon_fire": {"pattern": "snd.weapon.{archetype}", "fallback": "snd.weapon.small_arms"},
            "explosion": {"pattern": "snd.explosion.{size}", "fallback": "snd.explosion.small"},
            "impact_bullet": {"pattern": "snd.impact.bullet.{material}", "fallback": "snd.impact.bullet.dirt"},
            "collapse": {"pattern": "snd.collapse.{area}", "fallback": "snd.collapse.s1"},
            "profile": {"pattern": "snd.profile.{archetype}", "fallback": "snd.profile.generic.tracked"},
            "weapon_override": {},
            "unit_profile": unit_profile,
            "structure_profile": struct_profile,
        },
    }


# ---------------------------------------------------------------------------------------------------------- music.json
# faction -> (combat bpm, root midi, mode)
MUSIC_FLAVOUR = {"napc": (138, 45, "aeolian"), "nec": (128, 38, "dorian"), "olm": (126, 40, "phrygian_dominant"), "def": (132, 36, "harmonic_minor"),
                 "pd": (140, 43, "pentatonic_minor"), "han": (120, 38, "hirajoshi"), "ae": (126, 41, "dorian"), "sap": (132, 42, "phrygian_dominant")}
STEMS = ["drums", "bass", "pads", "lead"]


def track(folder: str, bpm: float, bars: int, root: int, mode: str) -> dict:
    beats = bars * 4
    return {"folder": folder, "bpm": float(bpm), "bars": bars, "bar_beats": 4, "beat_count": beats,
            "length_samples": round(beats * 60.0 / bpm * 44100), "stems": STEMS, "mono_stems": ["bass"], "mode": mode, "root_midi": root}


def _catalog_music() -> dict | None:
    """tracks + stingers as the music generator's catalog defines them (single source of truth) or None when it is not importable."""
    try:
        sys.path.insert(0, str(ROOT / "tools" / "py" / "audio"))
        from catalog import music as cm  # type: ignore
        return cm.music_json()
    except Exception:  # noqa: BLE001 - the catalog needs the music package; fall back to the spec's numbers
        return None


def music_json() -> dict:
    tracks: dict = {}
    stingers: dict = {}
    sets: dict = {}
    for f, (bpm, root, mode) in MUSIC_FLAVOUR.items():
        calm_bpm = round(bpm * 0.6)
        tracks[f"{f}.combat"] = track(f"mus/{f}/combat", bpm, 24, root, mode)
        tracks[f"{f}.calm"] = track(f"mus/{f}/calm", calm_bpm, 12, root, mode)
        stingers[f"stinger.{f}.riser"] = {"stream": f"mus/stinger/{f}_riser", "bpm": float(bpm), "bars": 2}
        stingers[f"stinger.{f}.victory"] = {"stream": f"mus/stinger/{f}_victory"}
        stingers[f"stinger.{f}.defeat"] = {"stream": f"mus/stinger/{f}_defeat"}
        sets[f] = {"calm": f"{f}.calm", "combat": f"{f}.combat", "riser": f"stinger.{f}.riser", "victory": f"stinger.{f}.victory", "defeat": f"stinger.{f}.defeat"}
    tracks["menu.theme"] = track("mus/menu", 100, 24, 40, "aeolian")
    stingers["stinger.match_start"] = {"stream": "mus/stinger/match_start"}
    cat = _catalog_music()
    if cat:
        tracks, stingers = cat["tracks"], cat["stingers"]
    return {
        "schema": "meridian.audio.music/1",
        "meter": {"tau_s": 6.0, "h_ref": 25.0, "attack_s": 0.6, "release_s": 4.0, "radius_m": 80.0, "min_dist_weight": 0.15, "far_weight": 0.25,
                  "combat_on": 0.40, "combat_on_hold_s": 1.0, "combat_off": 0.15, "combat_off_hold_s": 18.0, "min_combat_s": 25.0,
                  "weights": {"fire_small": 0.3, "fire_medium": 0.6, "fire_heavy": 1.0, "fire_artillery": 1.2, "beam_start": 0.5, "impact_base": 0.3,
                              "impact_per_size": 0.25, "death_unit_own": 4.0, "death_unit_enemy": 2.0, "death_structure": 8.0, "strategic": 30.0, "alert_own": 20.0}},
        "director": {"smoothing_s": 0.8, "min_switch_interval_s": 8.0, "calm_base": 0.2, "calm_gain": 1.5, "calm_max": 0.75, "combat_floor": 0.55, "combat_floor_s": 10.0},
        "stem_windows": {
            "calm": {"pads": [0.0, 0.20], "bass": [0.10, 0.35], "drums": [0.30, 0.60], "lead": [0.55, 0.90]},
            "combat": {"pads": [0.0, 0.15], "bass": [0.15, 0.40], "drums": [0.35, 0.65], "lead": [0.65, 0.95]}},
        "transitions": {
            "calm>combat": {"from": "next_bar", "to": "start", "fade": "cross", "fade_beats": 2.0, "filler": "riser"},
            "calm>combat_hot": {"from": "next_beat", "to": "start", "fade": "cross", "fade_beats": 1.0},
            "combat>calm": {"from": "next_bar", "to": "start", "fade": "cross", "fade_beats": 4.0}},
        "tracks": tracks,
        "stingers": stingers,
        "sets": sets,
        "roster_sets": {},
        "contexts": {"menu": {"track": "menu.theme", "intensity": 0.6}, "lobby": {"track": "menu.theme", "intensity": 0.35}},
    }


# ------------------------------------------------------------------------------------------- announcer / responses / factions
LINES = [  # id, text, category, priority, cooldown_ms, variants, expire_ms (None = default)
    ("construction_complete", "Construction complete.", "prod", 60, 3000, 2, None),
    ("unit_ready", "Unit ready.", "prod", 45, 5000, 2, None),
    ("new_construction_options", "New construction options.", "prod", 40, 20000, 1, None),
    ("research_complete", "Research complete.", "prod", 55, 3000, 1, None),
    ("on_hold", "On hold.", "prod", 40, 2000, 1, None),
    ("canceled", "Canceled.", "prod", 40, 2000, 1, None),
    ("cannot_deploy", "Cannot deploy here.", "prod", 60, 3000, 1, None),
    ("unable_to_comply", "Unable to comply.", "prod", 55, 2500, 1, None),
    ("power_ready", "Support power ready.", "prod", 68, 4000, 1, None),
    ("insufficient_funds", "Insufficient funds.", "eco", 70, 8000, 2, None),
    ("unit_cap_reached", "Unit limit reached.", "eco", 60, 15000, 1, None),
    ("low_power", "Low power.", "eco", 75, 45000, 2, None),
    ("power_restored", "Power restored.", "eco", 65, 10000, 1, None),
    ("defenses_offline", "Defenses offline.", "eco", 72, 30000, 1, None),
    ("structure_sold", "Structure sold.", "eco", 30, 1500, 1, None),
    ("base_under_attack", "Base under attack.", "alert", 92, 12000, 2, 4000),
    ("collector_under_attack", "Collector under attack.", "alert", 85, 12000, 1, 4000),
    ("unit_under_attack", "Unit under attack.", "alert", 60, 15000, 1, 4000),
    ("aircraft_under_attack", "Aircraft under attack.", "alert", 60, 15000, 1, 4000),
    ("ally_under_attack", "Ally under attack.", "alert", 70, 15000, 1, 4000),
    ("unit_lost", "Unit lost.", "alert", 50, 8000, 2, 4000),
    ("structure_lost", "Structure lost.", "alert", 80, 5000, 1, 4000),
    ("collector_lost", "Collector lost.", "alert", 82, 10000, 1, 4000),
    ("structure_captured", "Structure captured by the enemy.", "alert", 88, 6000, 1, 4000),
    ("building_captured", "Building captured.", "alert", 60, 4000, 1, None),
    ("systems_disabled", "Systems disabled.", "alert", 75, 15000, 1, 4000),
    ("superweapon_destroyed", "Strategic weapon destroyed.", "alert", 90, 10000, 1, 4000),
    ("sw_charging", "Strategic weapon charging.", "sw", 70, 30000, 1, None),
    ("sw_ready", "Strategic weapon ready.", "sw", 90, 10000, 1, None),
    ("sw_launched", "Strategic weapon launched.", "sw", 80, 10000, 1, None),
    ("sw_cancelled", "Launch aborted.", "sw", 85, 10000, 1, None),
    ("enemy_sw_charging", "Enemy strategic weapon charging.", "sw", 88, 60000, 1, None),
    ("sw_launch_detected", "Strategic launch detected.", "sw", 97, 3000, 1, 4000),
    ("sw_incoming_strike", "Incoming strike.", "sw", 93, 6000, 1, 4000),
    ("scan_detected", "Enemy scan detected.", "sw", 70, 20000, 1, None),
    ("match_start", "Battle control online.", "match", 90, 60000, 1, None),
    ("victory", "Victory.", "match", 100, 10000, 1, None),
    ("defeat", "Defeat.", "match", 100, 10000, 1, None),
    ("ally_defeated", "Ally defeated.", "match", 80, 3000, 1, None),
    ("enemy_defeated", "Enemy defeated.", "match", 80, 3000, 1, None),
    ("player_disconnected", "Player disconnected.", "match", 70, 3000, 1, None),
    ("game_paused", "Game paused.", "match", 50, 1000, 1, None),
    ("game_resumed", "Game resumed.", "match", 50, 1000, 1, None),
]
VOICES = {"napc": "am_michael", "nec": "bf_emma", "olm": "am_fenrir", "def": "bm_george", "pd": "af_bella", "han": "af_nicole", "ae": "am_puck", "sap": "bf_isabella"}
CHAINS = {"napc": "officer", "nec": "officer", "olm": "radio", "def": "radio", "pd": "officer", "han": "radio", "ae": "radio", "sap": "officer"}
LABELS = {"napc": "North American Peace Corps", "nec": "Northern European Concord", "olm": "Oil Lands Monarchies", "def": "Defense Union",
          "pd": "Pacific Dominion", "han": "Han Union", "ae": "African Emergence", "sap": "South American Pact"}


def announcer_json() -> dict:
    bible = json.loads(BIBLE.read_text(encoding="utf-8"))
    packs: dict = {"computer": {"label": "Computer", "engine": "kokoro", "voice": "af_heart", "chain": "computer"}}
    lines: dict = {}
    for lid, text, cat, pr, cd, var, exp in LINES:
        e: dict = {"text": text, "category": cat, "priority": pr, "cooldown_ms": cd, "variants": var}
        if exp is not None:
            e["expire_ms"] = exp
        lines[lid] = e
    for f in FACTIONS:
        motto = bible["factions"][f"faction.{f}"]["motto"]
        packs[f] = {"label": LABELS[f], "engine": "kokoro", "voice": VOICES[f], "chain": CHAINS[f], "motto": motto}
        lines[f"match_start_{f}"] = {"text": motto, "category": "match", "priority": 90, "cooldown_ms": 60000, "variants": 1}
    return {
        "schema": "meridian.audio.announcer/1",
        "defaults": {"cooldown_ms": 6000, "expire_ms": 8000, "priority": 50, "gap_ms": 250, "preempt_margin": 20, "max_queue": 4},
        "categories": {"alert": {"gap_ms": 2500}, "prod": {"gap_ms": 1500}, "eco": {"gap_ms": 2000}, "sw": {"gap_ms": 800}, "match": {"gap_ms": 500}},
        "packs": packs,
        "lines": lines,
    }


def responses_json() -> dict:
    barks = {
        "infantry": {"select": ["Yes, sir.", "Ready.", "Standing by."], "move": ["Moving out.", "On my way.", "Roger."], "attack": ["Engaging.", "Open fire.", "Attacking."],
                     "deny": ["Negative.", "Can't do that."], "special": ["Affirmative.", "On it."]},
        "vehicle": {"select": ["Ready.", "Awaiting orders.", "Standing by."], "move": ["Moving.", "En route.", "Proceeding."], "attack": ["Engaging.", "Firing.", "Target acquired."],
                    "deny": ["Negative.", "Unable."], "special": ["Affirmative.", "Executing."]},
        "heavy": {"select": ["Ready.", "Heavy armor ready.", "Awaiting orders."], "move": ["Rolling.", "Moving out.", "On the move."], "attack": ["Firing.", "Engaging.", "Fire mission."],
                  "deny": ["Negative.", "Unable."], "special": ["Affirmative.", "Executing."]},
        "air": {"select": ["Airborne.", "Ready.", "Standing by."], "move": ["Vectoring.", "On course.", "Moving."], "attack": ["Engaging.", "Attack run.", "Weapons hot."],
                "deny": ["Negative.", "Unable."], "special": ["Affirmative.", "Executing."]},
        "naval": {"select": ["Aye.", "Ready.", "Standing by."], "move": ["Making way.", "Underway.", "Course set."], "attack": ["Firing.", "Engaging.", "Guns ready."],
                  "deny": ["Negative.", "Unable."], "special": ["Affirmative.", "Executing."]},
        "support": {"select": ["Ready.", "At your service.", "Standing by."], "move": ["Moving.", "On my way.", "Roger."], "attack": ["Engaging.", "On it.", "Acknowledged."],
                    "deny": ["Negative.", "Can't do that."], "special": ["Affirmative.", "On it."]},
    }
    return {
        "schema": "meridian.audio.responses/1",
        "gaps": {"global_ms": 250, "same_ms": 700, "fatigue_count": 4, "fatigue_window_s": 3.0},
        "default_mode": "synth", "voice_mix_pct": 60,
        "classes": {"infantry": {"register": "high", "len_ms": [150, 260]}, "vehicle": {"register": "mid", "len_ms": [200, 340]},
                    "heavy": {"register": "low", "len_ms": [280, 450]}, "air": {"register": "trill", "len_ms": [160, 300]},
                    "naval": {"register": "ping", "len_ms": [250, 420]}, "support": {"register": "soft", "len_ms": [180, 320]},
                    "structure": {"register": "click", "len_ms": [80, 160]}},
        "types": {"select": 3, "move": 3, "attack": 3, "deny": 2, "special": 2},
        "structure_types": {"select": 3},
        "barks": barks,
    }


def factions_json() -> dict:
    F = {
        "napc": (0.0, 1.0, 1.0, 1.0, "breech_clack", "clean_digital", 55, 90, -44.0),
        "nec": (1.0, 1.25, 0.6, 0.8, "sensor_tick", "crisp_wide", 45, 70, -46.0),
        "olm": (-0.5, 0.90, 1.5, 0.9, "energy_hum", "warm_analog", 60, 100, -40.0),
        "def": (-2.0, 0.75, 1.3, 1.4, "low_brass_growl", "noisy_clipped", 60, 110, -38.0),
        "pd": (0.5, 1.10, 1.2, 0.8, "water_slap", "smooth_digital", 50, 80, -46.0),
        "han": (2.0, 1.40, 0.7, 1.0, "drone_buzz", "packet_chirp", 40, 60, -50.0),
        "ae": (-0.5, 1.00, 0.9, 1.2, "metal_clank", "crackly_hf", 55, 90, -38.0),
        "sap": (-1.0, 0.95, 1.1, 1.1, "shield_hum", "wobbly", 50, 90, -42.0),
    }
    out: dict = {}
    for f, (pitch, bright, tail, drive, layer, style, so, sc, hiss) in F.items():
        out[f] = {"music_set": f, "announcer_pack": f, "response_pack": f, "weapon_flavour": f,
                  "flavour": {"pitch_st": pitch, "bright": bright, "tail": tail, "drive": drive, "layer": layer},
                  "radio": {"style": style, "squelch_open_ms": so, "squelch_close_ms": sc, "hiss_db": hiss}}
    return {"schema": "meridian.audio.factions/1", "factions": out, "roster_overrides": {}}


def main() -> int:
    write("manifest.json", {"schema": "meridian.audio.manifest/1", "format": 1,
                            "files": ["announcer.json", "events.json", "factions.json", "mix.json", "music.json", "responses.json"]})
    write("mix.json", mix())
    ej = events_json()
    write("events.json", ej)
    write("music.json", music_json())
    write("announcer.json", announcer_json())
    write("responses.json", responses_json())
    write("factions.json", factions_json())
    print(f"wrote {len(ej['events'])} events, {len(ej['profiles'])} profiles, {len(ej['sim_map']['unit_profile'])} unit ids, "
          f"{len(ej['sim_map']['structure_profile'])} structure ids to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
