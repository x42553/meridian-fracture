"""gen_event_map.py - compile data/audio_events.json (+ assets/audio/audio_manifest.json) from the built assets.

In the game this file is hand/tool-edited data; this generator is the reference for what a full event table looks like and keeps
the prototype consistent with the asset build (stream paths, loop flags, music metadata).
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets" / "audio"
RES = "res://assets/audio"

GROUPS = {"small_arms": {"max_voices": 10, "steal": "oldest"}, "heavy": {"max_voices": 8}, "explosions": {"max_voices": 6},
          "loops": {"max_voices": 16}, "voice": {"max_voices": 2}}

# id: (files, overrides).  spatial: 3d | global | ui.
def E(files, **kw):
    return (files, kw)

EVENTS: dict[str, tuple] = {
    "weapon.rifle.fire": E(["rifle_shot_1", "rifle_shot_2", "rifle_shot_3"], priority=30, volume_db=-3, volume_jitter_db=1.5, pitch_jitter_semitones=0.8, unit_size=22, max_distance=170, group="small_arms", max_instances=6, min_interval_ms=35, lowpass_hz=9000),
    "weapon.autocannon.fire": E(["autocannon_burst"], priority=40, volume_db=-2, volume_jitter_db=1.0, pitch_jitter_semitones=0.5, unit_size=28, max_distance=200, group="small_arms", max_instances=4, min_interval_ms=150, lowpass_hz=9000),
    "weapon.cannon_heavy.fire": E(["tank_cannon"], priority=60, volume_jitter_db=1.0, pitch_jitter_semitones=0.6, unit_size=45, max_distance=320, group="heavy", max_instances=4, min_interval_ms=90),
    "weapon.artillery.fire": E(["howitzer_thump"], priority=65, unit_size=70, max_distance=450, group="heavy", max_instances=3, min_interval_ms=200),
    "weapon.missile.fire": E(["missile_launch"], priority=55, unit_size=40, max_distance=350, group="heavy", max_instances=4, min_interval_ms=120),
    "weapon.rocket.fire": E(["rocket_whoosh"], priority=45, pitch_jitter_semitones=1.0, unit_size=30, max_distance=220, group="small_arms", max_instances=4, min_interval_ms=80),
    "weapon.beam.fire": E(["beam_discharge"], priority=50, unit_size=40, max_distance=300, group="heavy", max_instances=4, min_interval_ms=150),
    "weapon.beam.loop": E(["beam_hum_loop"], priority=25, loop=True, unit_size=25, max_distance=160, group="loops", max_instances=6),
    "weapon.rail.fire": E(["rail_crack"], priority=58, unit_size=50, max_distance=400, group="heavy", max_instances=3, min_interval_ms=200),
    "weapon.emp.fire": E(["emp_zap"], priority=62, unit_size=45, max_distance=350, group="heavy", max_instances=3, min_interval_ms=250),
    "impact.explosion_small": E(["explosion_small_1", "explosion_small_2"], priority=70, volume_jitter_db=1.0, pitch_jitter_semitones=1.0, unit_size=45, max_distance=380, group="explosions", max_instances=5, min_interval_ms=60),
    "impact.explosion_large": E(["explosion_large"], priority=85, unit_size=90, max_distance=650, group="explosions", max_instances=3, min_interval_ms=200, pitch_jitter_semitones=0.5),
    "structure.collapse": E(["building_collapse"], priority=90, unit_size=100, max_distance=750, group="explosions", max_instances=2, min_interval_ms=300),
    "air.jet.flyby": E(["jet_flyby"], priority=60, unit_size=80, max_distance=520, max_instances=3, min_interval_ms=400),
    "air.heli.rotor": E(["heli_rotor_loop"], priority=30, loop=True, unit_size=45, max_distance=260, group="loops", max_instances=8),
    "unit.engine.tracked": E(["engine_tracked_loop"], priority=15, loop=True, unit_size=18, max_distance=120, group="loops", max_instances=12, lowpass_hz=6000),
    "unit.engine.wheeled": E(["engine_wheeled_loop"], priority=15, loop=True, unit_size=18, max_distance=120, group="loops", max_instances=12, lowpass_hz=6000),
    "unit.engine.boat": E(["engine_boat_loop"], priority=15, loop=True, unit_size=20, max_distance=130, group="loops", max_instances=8, lowpass_hz=6000),
    "unit.foot.step": E(["footsteps_loop"], priority=10, loop=True, unit_size=12, max_distance=70, group="loops", max_instances=10, lowpass_hz=6000),
    "structure.construct.hammer": E(["construction_hammer"], priority=35, unit_size=25, max_distance=150, max_instances=6, min_interval_ms=200),
    "structure.construct.servo": E(["construction_servo"], priority=30, unit_size=25, max_distance=150, max_instances=4, min_interval_ms=300),
    "structure.power.down": E(["power_down"], priority=80, spatial="global", volume_db=-2),
    "structure.power.up": E(["power_up"], priority=80, spatial="global", volume_db=-2),
    "structure.radar.ping": E(["radar_ping"], priority=70, spatial="global", volume_db=-3, max_instances=2),
    "economy.cash_tick": E(["cash_tick"], priority=60, spatial="global", pitch_jitter_semitones=0.4, max_instances=3, min_interval_ms=45),
    "ui.click": E(["ui_click"], priority=95, spatial="ui", bus="Ui", pitch_jitter_semitones=0.2, max_instances=4, min_interval_ms=30),
    "ui.hover": E(["ui_hover"], priority=90, spatial="ui", bus="Ui", max_instances=2, min_interval_ms=60),
    "ui.error": E(["ui_error"], priority=95, spatial="ui", bus="Ui", max_instances=1, min_interval_ms=200),
    "ui.confirm": E(["ui_confirm"], priority=95, spatial="ui", bus="Ui", max_instances=2, min_interval_ms=100),
    "alarm.superweapon.siren": E(["sw_siren_loop"], priority=97, spatial="global", loop=True, max_instances=1, volume_db=-2),
    "alarm.countdown.beep": E(["countdown_beep"], priority=96, spatial="global", max_instances=2),
    "alarm.countdown.final": E(["countdown_final"], priority=97, spatial="global", max_instances=1),
    "ambience.wind": E(["amb_wind_loop"], priority=5, spatial="global", bus="Ambience", loop=True, max_instances=1),
    "ambience.city": E(["amb_city_hum_loop"], priority=5, spatial="global", bus="Ambience", loop=True, max_instances=1),
    "ambience.coast": E(["amb_coast_waves_loop"], priority=5, spatial="global", bus="Ambience", loop=True, max_instances=1),
}


def category_of(name: str, metrics: dict) -> str:
    m = metrics.get(name)
    return m["category"] if m else "?"


def event(eid: str, files: list[str], kw: dict, metrics: dict) -> dict:
    cat = category_of(files[0], metrics)
    sub = {"weapons": "weapons", "explosions": "explosions"}.get(cat, cat)
    spatial = kw.get("spatial", "3d")
    d: dict = {"category": sub, "bus": kw.get("bus", "Sfx"), "priority": kw.get("priority", 50),
               "variants": [{"stream": f"{RES}/{category_of(f, metrics)}/{f}{'.mono' if (spatial == '3d' and metrics[f]['channels'] == 2) else ''}.ogg", "weight": 1.0} for f in files],
               "volume_db": kw.get("volume_db", 0.0), "volume_jitter_db": kw.get("volume_jitter_db", 0.0), "pitch": 1.0,
               "pitch_jitter_semitones": kw.get("pitch_jitter_semitones", 0.0), "loop": kw.get("loop", False),
               "spatial": {"mode": spatial}, "limit": {"max_instances": kw.get("max_instances", 8), "min_interval_ms": kw.get("min_interval_ms", 0), "steal": kw.get("steal", "oldest")},
               "cull_below_db": kw.get("cull_below_db", -48.0)}
    if spatial == "3d":
        d["spatial"].update({"unit_size": kw.get("unit_size", 30), "max_distance": kw.get("max_distance", 250), "attenuation": "inverse",
                             "lowpass_hz": kw.get("lowpass_hz", 12000), "panning_strength": 1.0})
    if kw.get("group"):
        d["limit"]["group"] = kw["group"]
    return d


def main() -> None:
    sfx = json.loads((ROOT / "analysis" / "sfx_metrics_v3.json").read_text())
    music = json.loads((ROOT / "analysis" / "music_metrics_v2.json").read_text())
    voice = json.loads((A / "voice" / "voice_manifest.json").read_text())
    events = {eid: event(eid, files, kw, sfx) for eid, (files, kw) in EVENTS.items()}
    # announcer lines: default pack, radio + faction overrides ("id@variant")
    for key, m in voice.items():
        pack, line = key.split("/")
        eid = f"voice.{line}" if pack == "default" else f"voice.{line}@{pack}"
        events[eid] = {"category": "voice", "bus": "Voice", "priority": 95, "variants": [{"stream": f"{RES}/voice/{pack}/{line}.ogg", "weight": 1.0}],
                       "volume_db": 0.0, "spatial": {"mode": "ui"}, "limit": {"max_instances": 1, "group": "voice", "steal": "none"}}
    tracks = {n: {"folder": f"{RES}/music/{n}", "bpm": t["bpm"], "beat_count": t["beat_count"], "bar_beats": t["bar_beats"], "stems": ["drums", "bass", "pads", "lead"],
                  "length_samples": t["length_samples"], "mode": t["mode"]} for n, t in music.items() if n != "flavour_demo"}
    out = {"version": 1, "groups": GROUPS, "events": events, "music": tracks,
           "sim_map": {"weapon_fire": {"pattern": "weapon.{snd}.fire", "fallback": "weapon.rifle.fire"},
                       "explosion": {"pattern": "impact.explosion_{size}", "fallback": "impact.explosion_small"},
                       "movement_loop": {"pattern": "unit.engine.{movement_class}", "fallback": "unit.engine.wheeled"},
                       "announcement": {"pattern": "voice.{line}"}}}
    (ROOT / "data").mkdir(exist_ok=True)
    (ROOT / "data" / "audio_events.json").write_text(json.dumps(out, indent=1))
    manifest = {}
    for f in sorted(A.rglob("*.ogg")):
        rel = f.relative_to(A).as_posix()
        name = f.stem
        is_mono_variant = name.endswith(".mono")
        name = name[:-5] if is_mono_variant else name
        if is_mono_variant:
            m = sfx[name]
            manifest[rel] = {"duration_s": m["duration_s"], "loop": m["loop"], "channels": 1}
        elif rel.startswith("music/"):
            tr = rel.split("/")[1]
            manifest[rel] = {"duration_s": music[tr]["length_samples"] / 44100.0, "loop": True, "channels": 2}
        elif rel.startswith("voice/"):
            m = voice[f"{rel.split('/')[1]}/{name}"]
            manifest[rel] = {"duration_s": m["duration_s"], "loop": False, "channels": 1}
        else:
            m = sfx[name]
            manifest[rel] = {"duration_s": m["duration_s"], "loop": m["loop"], "channels": m["channels"]}
    (A / "audio_manifest.json").write_text(json.dumps(manifest, indent=1))
    wt = ROOT / "assets" / "wav_test"
    wt.mkdir(parents=True, exist_ok=True)
    for n, cat in (("engine_tracked_loop", "vehicles"), ("engine_wheeled_loop", "vehicles"), ("engine_boat_loop", "vehicles"), ("footsteps_loop", "vehicles"), ("heli_rotor_loop", "air")):
        shutil.copy(ROOT / ".build" / "wav" / cat / f"{n}.wav", wt / f"{n}.wav")
    print(f"events: {len(events)}  music tracks: {len(tracks)}  manifest assets: {len(manifest)}")


if __name__ == "__main__":
    main()
