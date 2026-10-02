#!/usr/bin/env python3
"""validate_audio.py - stdlib-only validator of game/data/audio/*.json (audio spec 7.9, rules V-AUD-01..28).

    python3 tools/py/audio/validate_audio.py [--strict] [--json OUT] [--quiet]

Checks the six data files against each other, the asset manifest (`game/assets/audio/audio_manifest.json`), the balance
sheets, the bible and `project.godot`. Errors always fail; warnings fail with --strict. Prints coverage counters.
"""
from __future__ import annotations

import argparse
import glob
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA = ROOT / "game" / "data" / "audio"
ASSETS = ROOT / "game" / "assets" / "audio"
BALANCE = ROOT / "game" / "data" / "balance"
BIBLE = ROOT / "game" / "data" / "bible" / "meridian_factions.json"
FACTIONS = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]
SCHEMAS = {"manifest": "meridian.audio.manifest/1", "mix": "meridian.audio.mix/1", "events": "meridian.audio.events/2", "music": "meridian.audio.music/1",
           "announcer": "meridian.audio.announcer/1", "responses": "meridian.audio.responses/1", "factions": "meridian.audio.factions/1"}
TOP = {
    "manifest": {"schema", "format", "files"},
    "mix": {"schema", "engine", "buses", "pool", "camera", "hearing", "loops", "propagation", "size_thresholds_units", "replay", "strategic", "terrain", "ambience"},
    "events": {"schema", "groups", "events", "profiles", "power_cues", "sw_cues", "sim_map"},
    "music": {"schema", "meter", "director", "stem_windows", "transitions", "tracks", "stingers", "sets", "roster_sets", "contexts"},
    "announcer": {"schema", "defaults", "categories", "packs", "lines"},
    "responses": {"schema", "gaps", "default_mode", "voice_mix_pct", "classes", "types", "structure_types", "barks"},
    "factions": {"schema", "factions", "roster_overrides"},
}
EVENT_KEYS = {"category", "bus", "priority", "variants", "flavours", "volume_db", "volume_jitter_db", "pitch", "pitch_jitter_semitones", "spatial", "limit",
              "loop", "fade_in_ms", "fade_out_ms", "cull_below_db", "link", "tags", "notes"}
SPATIAL_KEYS = {"mode", "unit_size_m", "max_distance_m", "attenuation", "lowpass_hz", "panning_strength", "doppler", "propagation", "fog", "fog_gain_db", "fog_lowpass_hz"}
LIMIT_KEYS = {"group", "max_instances", "min_interval_ms", "steal"}
PROFILE_KEYS = {"parent", "voice_class", "weapon_variant", "loops", "die", "spawn", "select_fx", "scalars", "notes"}
SIM_MAP_KEYS = {"weapon_fire", "explosion", "impact_bullet", "collapse", "profile", "weapon_override", "unit_profile", "structure_profile"}
WEAPON_ARCHS = ["small_arms", "machine_gun", "autocannon", "tank_cannon", "siege_gun", "demolition_cannon", "at_missile", "aa_missile", "flak",
                "artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "beam_thermal", "rail_gun", "torpedo", "depth_charge", "bomb",
                "air_missile", "emp_pulse", "canister", "grenade_launcher", "breach_charge", "naval_gun", "naval_bombard", "cruise_missile", "drone_missile"]
POWER_CLASSES = {"recon", "repair", "buff", "shield", "cloak", "smoke", "barrage", "generic"}
SW_NAMES = {"atlas", "aurora", "helios", "perun", "tempest", "dragonfall", "horizon", "trident"}
VOICE_CLASSES = {"infantry", "vehicle", "heavy", "air", "naval", "support", "structure"}
WHEN = {"always", "moving", "airborne", "structure_active", "charging"}
LOOKS_SPECIFIC = re.compile(r"^snd\.profile\.(?!generic\.)")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.counters: dict[str, object] = {}

    def err(self, rule: int, msg: str) -> None:
        self.errors.append(f"V-AUD-{rule:02d}: {msg}")

    def warn(self, rule: int, msg: str) -> None:
        self.warnings.append(f"V-AUD-{rule:02d}: {msg}")


def load(name: str, rep: Report) -> dict:
    p = DATA / f"{name}.json"
    if not p.exists():
        rep.err(1, f"{p.name} missing")
        return {}
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        rep.err(1, f"{p.name}: {e}")
        return {}
    if d.get("schema") != SCHEMAS[name]:
        rep.err(1, f"{p.name}: schema '{d.get('schema')}' != '{SCHEMAS[name]}'")
    for k in d:
        if k not in TOP[name] and not k.startswith("_"):
            rep.err(1, f"{p.name}: unknown top-level key '{k}'")
    return d


def check_keys(d: dict, allowed: set, where: str, rep: Report) -> None:
    for k in d:
        if k not in allowed and not k.startswith("_"):
            rep.err(1, f"{where}: unknown key '{k}'")


class Assets:
    """Asset manifest view: ids, groups, files."""

    def __init__(self) -> None:
        self.assets: dict[str, dict] = {}
        self.groups: dict[str, int] = {}
        self.present = False
        mp = ASSETS / "audio_manifest.json"
        if mp.exists():
            self.present = True
            self.assets = json.loads(mp.read_text(encoding="utf-8")).get("assets", {})
        for aid in self.assets:
            m = re.match(r"^(.*)_(\d+)$", aid)
            if m:
                self.groups[m.group(1)] = max(self.groups.get(m.group(1), 0), int(m.group(2)))

    def members(self, group: str) -> list[str]:
        n = self.groups.get(group, 0)
        if n:
            return [f"{group}_{i}" for i in range(1, n + 1)]
        return [group] if group in self.assets else []

    def has_mono(self, aid: str) -> bool:
        a = self.assets.get(aid)
        return bool(a) and (a.get("channels") == 1 or "mono_file" in a)

    def file_ok(self, aid: str) -> bool:
        a = self.assets.get(aid)
        return bool(a) and (ASSETS / a["file"]).exists()


def project_audio() -> dict:
    out = {"mix_rate": 44100, "output_latency": 15}
    p = ROOT / "game" / "project.godot"
    if p.exists():
        text = p.read_text(encoding="utf-8")
        for key, name in (("audio/driver/mix_rate", "mix_rate"), ("audio/driver/output_latency", "output_latency")):
            m = re.search(rf"^{re.escape(key)}\s*=\s*(\d+)", text, re.M)
            if m:
                out[name] = int(m.group(1))
    return out


def validate(rep: Report) -> None:
    mix = load("mix", rep)
    ev = load("events", rep)
    music = load("music", rep)
    ann = load("announcer", rep)
    resp = load("responses", rep)
    fac = load("factions", rep)
    man = load("manifest", rep)
    A = Assets()
    if not A.present:
        rep.err(2, "game/assets/audio/audio_manifest.json missing: assets not generated yet")
    if man:
        for f in man.get("files", []):
            if not (DATA / f).exists():
                rep.err(1, f"manifest.json lists missing file {f}")
    # ---- mix
    for sec, keys in {"engine": {"mix_rate", "output_latency_ms"}, "pool": {"voices_3d", "voices_2d", "reserve_high_slots", "reserve_high_priority", "max_starts_per_frame", "steal_margin", "age_penalty_per_s", "cull_below_db"},
                      "camera": {"ref_height_m", "zoom_scale_min", "zoom_scale_max", "listener_height_m", "source_height_ground_m", "source_height_air_m", "focus_smooth_s"},
                      "hearing": {"max_scan_m", "loud_fog_radius_m", "fog_muffled_gain_db", "fog_muffled_lowpass_hz", "offscreen_alert_m", "contact_ping"},
                      "loops": {"budget", "scan_period_s", "radius_m", "hysteresis_db", "fade_in_ms", "fade_out_ms", "pitch_speed_lo", "pitch_speed_hi", "max_candidates"},
                      "propagation": {"speed_mps", "max_delay_ms"}, "size_thresholds_units": {"small", "medium", "large"}, "replay": {"gate_priority_above_2x"},
                      "strategic": {"helios_length_cells"}, "terrain": {"material"}}.items():
        if isinstance(mix.get(sec), dict):
            check_keys(mix[sec], keys, f"mix.{sec}", rep)
    buses = {b["name"]: b for b in mix.get("buses", [])}
    pa = project_audio()
    eng = mix.get("engine", {})
    if eng.get("mix_rate") != pa["mix_rate"] or eng.get("output_latency_ms") != pa["output_latency"]:
        rep.err(25, f"mix.engine {eng} differs from project.godot audio/driver ({pa})")
    if len(mix.get("terrain", {}).get("material", [])) != 15:
        rep.err(1, "mix.terrain.material must have 15 entries")
    order = [b["name"] for b in mix.get("buses", [])]
    for i, b in enumerate(mix.get("buses", [])):
        if b.get("send") and b["send"] in order and order.index(b["send"]) >= i:
            rep.err(11, f"bus {b['name']} sends to a higher index bus {b['send']}")
        for fx in b.get("effects", []):
            sc = fx.get("sidechain")
            if sc and sc not in buses:
                rep.err(11, f"bus {b['name']} effect {fx.get('id')}: sidechain bus '{sc}' missing")
    # ---- events
    events = ev.get("events", {})
    profiles = ev.get("profiles", {})
    groups = ev.get("groups", {})
    seen: dict[str, str] = {}
    n_variants = 0
    for eid, e in events.items():
        w = f"events.{eid}"
        low = eid.lower()
        if low in seen:
            rep.err(9, f"duplicate id (case-insensitive): {eid} / {seen[low]}")
        seen[low] = eid
        check_keys(e, EVENT_KEYS, w, rep)
        sp = e.get("spatial", {})
        check_keys(sp, SPATIAL_KEYS, w + ".spatial", rep)
        check_keys(e.get("limit", {}), LIMIT_KEYS, w + ".limit", rep)
        pr = e.get("priority", 50)
        if not (0 <= pr <= 100):
            rep.err(5, f"{w}: priority {pr} outside 0..100")
        bus = e.get("bus", "Sfx")
        if bus not in buses:
            rep.err(11, f"{w}: unknown bus '{bus}'")
        g = e.get("limit", {}).get("group")
        if g and g not in groups:
            rep.err(6, f"{w}: limit.group '{g}' not declared in groups")
        v = e.get("volume_db", 0.0)
        if not (-24.0 <= v <= 3.0):
            rep.err(17, f"{w}: volume_db {v} outside [-24, 3]")
        c = e.get("cull_below_db", -42.0)
        if not (-80.0 <= c <= -10.0):
            rep.err(17, f"{w}: cull_below_db {c} outside [-80, -10]")
        mode = sp.get("mode", "ui")
        if mode == "3d":
            u = sp.get("unit_size_m", 0)
            if u <= 0:
                rep.err(16, f"{w}: unit_size_m must be > 0")
            elif 0 < sp.get("max_distance_m", 0) < 3 * u:
                rep.warn(16, f"{w}: max_distance_m {sp.get('max_distance_m')} < 3 * unit_size_m")
        for fl in e.get("flavours", {}):
            if fl not in FACTIONS:
                rep.err(10, f"{w}: flavour '{fl}' is not a faction code")
        lists = [("variants", e.get("variants", []))] + [(f"flavours.{k}", v) for k, v in e.get("flavours", {}).items()]
        for label, vs in lists:
            if not vs:
                rep.err(1, f"{w}.{label}: no variants")
            for var in vs:
                ids: list[str] = []
                if "stream" in var:
                    ids = [var["stream"]] if var["stream"] in A.assets else []
                elif "group" in var:
                    ids = A.members(var["group"])
                else:
                    rep.err(1, f"{w}.{label}: variant needs 'stream' or 'group'")
                    continue
                if var.get("weight", 1.0) <= 0:
                    rep.err(1, f"{w}.{label}: weight must be > 0")
                if not ids and A.present:
                    rep.err(2, f"{w}.{label}: asset '{var.get('stream') or var.get('group')}' not in the asset manifest")
                for aid in ids:
                    n_variants += 1
                    if not A.file_ok(aid):
                        rep.err(2, f"{w}: asset file missing for {aid}")
                        continue
                    if mode == "3d" and not A.has_mono(aid):
                        rep.err(3, f"{w}: 3d event uses non-mono asset {aid}")
                    if bool(e.get("loop", False)) != bool(A.assets[aid].get("loop", False)):
                        rep.err(4, f"{w}: loop={e.get('loop', False)} but asset {aid} loop={A.assets[aid].get('loop', False)}")
        for k in ("loop", "end"):
            t = e.get("link", {}).get(k)
            if t and t not in events:
                rep.err(7, f"{w}: link.{k} '{t}' is not an event")
    # ---- profiles
    for pid, p in profiles.items():
        w = f"profiles.{pid}"
        check_keys(p, PROFILE_KEYS, w, rep)
        if "voice_class" in p and p["voice_class"] not in VOICE_CLASSES:
            rep.err(7, f"{w}: voice_class '{p['voice_class']}'")
        chain = 0
        cur = p
        seen_p = {pid}
        while cur.get("parent"):
            par = cur["parent"]
            if par not in profiles or par in seen_p:
                rep.err(7, f"{w}: parent '{par}' missing or cyclic")
                break
            seen_p.add(par)
            cur = profiles[par]
            chain += 1
            if chain > 4:
                rep.err(7, f"{w}: parent chain deeper than 4")
                break
        for lp in p.get("loops", []):
            if lp.get("event") not in events:
                rep.err(7, f"{w}: loop event '{lp.get('event')}' is not an event")
            if lp.get("when") not in WHEN:
                rep.err(7, f"{w}: loops.when '{lp.get('when')}'")
        for k in ("die", "spawn", "select_fx"):
            if p.get(k) and p[k] not in events:
                rep.err(7, f"{w}: {k} '{p[k]}' is not an event")
    # ---- sim_map
    sm = ev.get("sim_map", {})
    check_keys(sm, SIM_MAP_KEYS, "sim_map", rep)
    for k in ("weapon_fire", "explosion", "impact_bullet", "collapse", "profile"):
        r = sm.get(k)
        if not r or "pattern" not in r:
            rep.err(8, f"sim_map.{k} missing")
            continue
        fb = r.get("fallback")
        if fb not in events and fb not in profiles:
            rep.err(8, f"sim_map.{k}: fallback '{fb}' does not exist")
    for wid, target in sm.get("weapon_override", {}).items():
        if target not in events:
            rep.err(13, f"sim_map.weapon_override.{wid} -> '{target}' is not an event")
    # ---- balance sheets: profile tables, pres_snd_profile, archetype coverage
    explicit = derived = generic = 0
    unit_ids: dict[str, str] = {}
    for path in sorted(glob.glob(str(BALANCE / "units_*.json"))):
        d = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        for u in d.get("units", []):
            unit_ids[u["id"]] = u.get("archetype", "")
            sn = u.get("pres", {}).get("snd_profile")
            if sn and sn not in events and sn not in profiles:
                rep.err(13, f"{u['id']}: pres.snd_profile '{sn}' unknown")
        for s in d.get("summons", []):
            unit_ids[s["id"]] = ""
    for uid, arch in unit_ids.items():
        pid = sm.get("unit_profile", {}).get(uid)
        if pid is None:
            rep.err(14, f"unit {uid} has no entry in sim_map.unit_profile")
            continue
        if pid not in profiles:
            rep.err(13, f"unit {uid}: profile '{pid}' is not a profile")
            continue
        if not arch or arch.startswith("service."):
            derived += 1
        elif pid == f"snd.profile.{arch}":
            explicit += 1
        else:
            derived += 1
        if pid.startswith("snd.profile.generic.") and arch and not arch.startswith("service."):
            rep.err(14, f"unit {uid}: generic profile {pid} although archetype '{arch}' has a specific profile")
        if arch and not arch.startswith("service.") and f"snd.profile.{arch}" not in profiles:
            rep.err(14, f"archetype '{arch}' of {uid} has no profile")
        if pid.startswith("snd.profile.generic."):
            generic += 1
    st = json.loads((BALANCE / "structures.json").read_text(encoding="utf-8"))["structures"]
    for s in st:
        pid = sm.get("structure_profile", {}).get(s["id"])
        if pid is None or pid not in profiles:
            rep.err(14, f"structure {s['id']}: profile '{pid}' missing")
    rep.counters.update({"units_with_archetype_profile": explicit, "units_derived": derived, "units_generic": generic, "structures": len(st)})
    # ---- weapon archetypes
    for a in WEAPON_ARCHS:
        names = ["tank_cannon_light", "tank_cannon_medium", "tank_cannon_heavy"] if a == "tank_cannon" else [a]
        for nm in names:
            if f"snd.weapon.{nm}" not in events:
                rep.err(15, f"weapon archetype '{a}' has no event snd.weapon.{nm}")
    # ---- bible: power and superweapon cues
    bible = json.loads(BIBLE.read_text(encoding="utf-8"))
    pc = ev.get("power_cues", {})
    sc = ev.get("sw_cues", {})
    for pid in bible.get("support_powers", {}):
        if pid not in pc:
            rep.err(12, f"bible power {pid} absent from power_cues")
    for sid in bible.get("superweapons", {}):
        if sid not in sc:
            rep.err(12, f"bible superweapon {sid} absent from sw_cues")
    for pid, cls in pc.items():
        if cls not in POWER_CLASSES:
            rep.err(12, f"power_cues.{pid}: class '{cls}'")
        elif f"snd.power.{cls}.activate" not in events:
            rep.err(12, f"power class {cls} has no activate event")
    for sid, nm in sc.items():
        if nm not in SW_NAMES:
            rep.err(12, f"sw_cues.{sid}: name '{nm}'")
        elif not any(k.startswith(f"snd.sw.{nm}.") for k in events):
            rep.err(12, f"superweapon {nm} has no events")
    # ---- announcer
    lines = ann.get("lines", {})
    packs = ann.get("packs", {})
    n_ann = 0
    for lid, ln in lines.items():
        if not str(ln.get("text", "")).strip():
            rep.err(28, f"announcer line {lid}: empty caption text")
        var = int(ln.get("variants", 1))
        if A.present:
            for pk in ["computer"] + [p for p in packs if p != "computer"]:
                files = [x for x in (f"vox/{pk}/{lid}", f"vox/{pk}/{lid}_1", f"vox/{pk}/{lid}_2", f"vox/{pk}/{lid}_3") if x in A.assets]
                if not files:
                    rep.err(19, f"announcer line {lid}: no file for pack {pk}")
                elif var > len(files):
                    rep.err(20, f"announcer line {lid}: variants {var} > files present ({len(files)}) in pack {pk}")
                n_ann += len(files)
    for f in FACTIONS:
        if f"match_start_{f}" not in lines:
            rep.err(19, f"announcer: match_start_{f} line missing")
    # ---- music
    tracks = music.get("tracks", {})
    stingers = music.get("stingers", {})
    for tid, t in tracks.items():
        if t["beat_count"] != t["bars"] * t["bar_beats"]:
            rep.err(21, f"track {tid}: beat_count != bars * bar_beats")
        exp = round(t["bars"] * t["bar_beats"] * 60.0 / t["bpm"] * 44100)
        if t["length_samples"] != exp:
            rep.err(21, f"track {tid}: length_samples {t['length_samples']} != {exp}")
        if A.present:
            for stem in t["stems"]:
                aid = f"{t['folder']}/{stem}"
                a = A.assets.get(aid)
                if a is None:
                    rep.err(21, f"track {tid}: stem {aid} missing")
                    continue
                if a.get("duration_samples") != t["length_samples"]:
                    rep.err(21, f"track {tid}: stem {aid} has {a.get('duration_samples')} samples, expected {t['length_samples']}")
                if stem in t.get("mono_stems", []) and not A.has_mono(aid):
                    rep.err(21, f"track {tid}: stem {aid} must be mono")
    for sid, s in stingers.items():
        if A.present and s["stream"] not in A.assets:
            rep.err(22, f"stinger {sid}: stream {s['stream']} missing")
    for fset, s in music.get("sets", {}).items():
        for key, ref in s.items():
            if key in ("calm", "combat") and ref not in tracks:
                rep.err(22, f"sets.{fset}.{key}: track {ref} missing")
            if key in ("riser", "victory", "defeat") and ref not in stingers:
                rep.err(22, f"sets.{fset}.{key}: stinger {ref} missing")
    for name, tr in music.get("transitions", {}).items():
        f = tr.get("filler")
        if f and f not in ("riser",):
            rep.err(22, f"transitions.{name}: filler '{f}' unknown")
    for ctx, c in music.get("contexts", {}).items():
        if c["track"] not in tracks:
            rep.err(22, f"contexts.{ctx}: track {c['track']} missing")
    # ---- responses
    rc = resp.get("classes", {})
    types = resp.get("types", {})
    n_resp = 0
    if A.present:
        for f in FACTIONS:
            for cls in rc:
                for t, n in (types.items() if cls != "structure" else resp.get("structure_types", {}).items()):
                    for i in range(1, n + 1):
                        aid = f"resp/{f}/{cls}_{t}_{i}"
                        if aid not in A.assets:
                            rep.err(23, f"response clip {aid} missing")
                        else:
                            n_resp += 1
    # ---- factions
    for f in FACTIONS:
        if f not in fac.get("factions", {}):
            rep.err(1, f"factions.json: faction '{f}' missing")
    # ---- budget, orphans, provenance
    if A.present:
        files = sum(1 for a in A.assets.values()) + sum(1 for a in A.assets.values() if "mono_file" in a)
        total = sum(a.get("bytes", 0) + a.get("mono_bytes", 0) for a in A.assets.values())
        banks: dict[str, int] = {}
        for a in A.assets.values():
            banks[a["bank"]] = banks.get(a["bank"], 0) + a.get("bytes", 0) + a.get("mono_bytes", 0)
        if files > 2500 or total > 110_000_000 or any(v > 45_000_000 for v in banks.values()):
            rep.err(24, f"asset budget exceeded: {files} files, {total / 1e6:.1f} MB, largest bank {max(banks.values()) / 1e6:.1f} MB")
        referenced: set[str] = set()

        def add(var_list: list) -> None:
            for var in var_list:
                if "stream" in var:
                    referenced.add(var["stream"])
                elif "group" in var:
                    referenced.update(A.members(var["group"]))

        for e in events.values():
            add(e.get("variants", []))
            for v in e.get("flavours", {}).values():
                add(v)
        for t in tracks.values():
            referenced.update(f"{t['folder']}/{s}" for s in t["stems"])
        referenced.update(s["stream"] for s in stingers.values())
        for lid, ln in lines.items():
            for pk in packs:
                for x in (f"vox/{pk}/{lid}", f"vox/{pk}/{lid}_1", f"vox/{pk}/{lid}_2", f"vox/{pk}/{lid}_3"):
                    referenced.add(x)
        orphans = [a for a in A.assets if a not in referenced and not a.startswith("resp/")]
        if orphans:
            rep.warn(24, f"{len(orphans)} orphan assets not referenced by any data, e.g. {sorted(orphans)[:3]}")
        prov_path = ASSETS / "provenance.json"
        if prov_path.exists():
            prov = {p["file"]: p for p in json.loads(prov_path.read_text(encoding="utf-8")).get("files", [])}
            for aid, a in A.assets.items():
                for fk in ("file", "mono_file"):
                    if fk in a:
                        key = "game/assets/audio/" + a[fk]
                        if key not in prov:
                            rep.err(26, f"provenance.json lacks an entry for {key}")
                        elif prov[key].get("licence_model") not in ("Apache-2.0", "MIT", "CC0-1.0", "CC-BY-4.0", "procedural"):
                            rep.err(26, f"provenance.json: {key} licence_model {prov[key].get('licence_model')}")
        else:
            rep.err(26, "provenance.json missing")
    # ---- economy buildup
    econ = ROOT / "game" / "src" / "sim" / "sim_econ_const.gd"
    if econ.exists():
        m = re.search(r"const BUILDUP_TICKS: int = (\d+)", econ.read_text(encoding="utf-8"))
        if m and int(m.group(1)) != round(1.5 * 20):
            rep.warn(27, f"BUILDUP_TICKS {m.group(1)} differs from SndConfig.BUILDUP_SECONDS * 20")
    rep.counters.update({"events": len(events), "profiles": len(profiles), "event_variants_resolved": n_variants, "announcer_files": n_ann,
                         "response_clips": n_resp, "assets": len(A.assets), "announcer_lines": len(lines), "tracks": len(tracks), "stingers": len(stingers)})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--strict", action="store_true", help="warnings fail too")
    ap.add_argument("--json", help="write the report to this file")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    rep = Report()
    validate(rep)
    if not args.quiet:
        for m in rep.errors[:80]:
            print("ERROR", m)
        if len(rep.errors) > 80:
            print(f"... {len(rep.errors) - 80} more errors")
        for m in rep.warnings[:40]:
            print("WARN ", m)
    print("coverage:", json.dumps(rep.counters, sort_keys=True))
    failed = bool(rep.errors) or (args.strict and bool(rep.warnings))
    print(f"validate_audio: {len(rep.errors)} error(s), {len(rep.warnings)} warning(s) -> {'FAIL' if failed else 'OK'}")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps({"errors": rep.errors, "warnings": rep.warnings, "counters": rep.counters}, indent=1), encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
