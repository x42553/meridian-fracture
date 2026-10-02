class_name SndDataStore
extends RefCounted
## Loads and validates every `game/data/audio/*.json` (audio spec 3.3 / 7). Unknown keys and wrong schema ids are errors
## ("file: path: message"). Keys starting with `_` are documentation and ignored. The parsed dictionaries stay here; typed
## defs are built from them by SndEventMap, SndMusicLibrary, SndAnnouncer and SndUnitResponse.

const FILES: PackedStringArray = ["mix", "events", "music", "announcer", "responses", "factions"]
const SCHEMAS: Dictionary = {
	"manifest": "meridian.audio.manifest/1", "mix": "meridian.audio.mix/1", "events": "meridian.audio.events/2",
	"music": "meridian.audio.music/1", "announcer": "meridian.audio.announcer/1", "responses": "meridian.audio.responses/1",
	"factions": "meridian.audio.factions/1",
}
const KEYS_TOP: Dictionary = {
	"manifest": ["schema", "format", "files"],
	"mix": ["schema", "engine", "buses", "pool", "camera", "hearing", "loops", "propagation", "size_thresholds_units", "replay", "strategic", "terrain", "ambience"],
	"events": ["schema", "groups", "events", "profiles", "power_cues", "sw_cues", "sim_map"],
	"music": ["schema", "meter", "director", "stem_windows", "transitions", "tracks", "stingers", "sets", "roster_sets", "contexts"],
	"announcer": ["schema", "defaults", "categories", "packs", "lines"],
	"responses": ["schema", "gaps", "default_mode", "voice_mix_pct", "classes", "types", "structure_types", "barks"],
	"factions": ["schema", "factions", "roster_overrides"],
}
const KEYS_MIX: Dictionary = {
	"engine": ["mix_rate", "output_latency_ms"],
	"pool": ["voices_3d", "voices_2d", "reserve_high_slots", "reserve_high_priority", "max_starts_per_frame", "steal_margin", "age_penalty_per_s", "cull_below_db"],
	"camera": ["ref_height_m", "zoom_scale_min", "zoom_scale_max", "listener_height_m", "source_height_ground_m", "source_height_air_m", "focus_smooth_s"],
	"hearing": ["max_scan_m", "loud_fog_radius_m", "fog_muffled_gain_db", "fog_muffled_lowpass_hz", "offscreen_alert_m", "contact_ping"],
	"loops": ["budget", "scan_period_s", "radius_m", "hysteresis_db", "fade_in_ms", "fade_out_ms", "pitch_speed_lo", "pitch_speed_hi", "max_candidates"],
	"propagation": ["speed_mps", "max_delay_ms"],
	"size_thresholds_units": ["small", "medium", "large"],
	"replay": ["gate_priority_above_2x"],
	"strategic": ["helios_length_cells"],
	"terrain": ["material"],
}
const KEYS_EVENT: PackedStringArray = [
	"category", "bus", "priority", "variants", "flavours", "volume_db", "volume_jitter_db", "pitch", "pitch_jitter_semitones",
	"spatial", "limit", "loop", "fade_in_ms", "fade_out_ms", "cull_below_db", "link", "tags", "notes",
]
const KEYS_SPATIAL: PackedStringArray = [
	"mode", "unit_size_m", "max_distance_m", "attenuation", "lowpass_hz", "panning_strength", "doppler", "propagation", "fog",
	"fog_gain_db", "fog_lowpass_hz",
]
const KEYS_LIMIT: PackedStringArray = ["group", "max_instances", "min_interval_ms", "steal"]
const KEYS_PROFILE: PackedStringArray = ["parent", "voice_class", "weapon_variant", "loops", "die", "spawn", "select_fx", "scalars", "notes"]
const KEYS_SIM_MAP: PackedStringArray = [
	"weapon_fire", "explosion", "impact_bullet", "collapse", "profile", "weapon_override", "unit_profile", "structure_profile",
]

var errors: PackedStringArray = PackedStringArray()
var mix: SndMixConfig = SndMixConfig.new()
var events: Dictionary = {}
var music: Dictionary = {}
var announcer: Dictionary = {}
var responses: Dictionary = {}
var factions: Dictionary = {}
var manifest: Dictionary = {}
var data_version: int = 0
var loaded: bool = false


func load_all(dir: String = SndConfig.DATA_DIR) -> bool:
	errors = PackedStringArray()
	loaded = false
	manifest = _read(dir, "manifest")
	var listed: Array = manifest.get("files", [])
	var ver: int = 17
	for name: String in FILES:
		if not listed.has(name + ".json"):
			_err("manifest.json", "files", "does not list %s.json" % name)
		var d: Dictionary = _read(dir, name)
		ver = ver * 31 + int(d.get("__hash", 0))
		d.erase("__hash")
		match name:
			"mix":
				mix = SndMixConfig.new()
				mix.load_dict(d)
			"events":
				events = d
			"music":
				music = d
			"announcer":
				announcer = d
			"responses":
				responses = d
			"factions":
				factions = d
	data_version = ver & 0x7FFFFFFF
	_validate_shapes()
	loaded = errors.is_empty()
	return loaded


func _err(file: String, path: String, msg: String) -> void:
	errors.append("%s: %s: %s" % [file, path, msg])


func _read(dir: String, name: String) -> Dictionary:
	var file: String = name + ".json"
	var path: String = dir.path_join(file)
	if not FileAccess.file_exists(path):
		_err(file, "", "file not found (%s)" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		_err(file, "line %d" % json.get_error_line(), json.get_error_message())
		return {}
	if not (json.data is Dictionary):
		_err(file, "", "top level must be an object")
		return {}
	var d: Dictionary = json.data
	if str(d.get("schema", "")) != str(SCHEMAS.get(name, "")):
		_err(file, "schema", "expected '%s', found '%s'" % [SCHEMAS.get(name, ""), str(d.get("schema", ""))])
	d["__hash"] = text.hash() & 0x7FFFFFFF
	_check_keys(d, KEYS_TOP.get(name, []), file, "")
	return d


## Reports every key of `d` that is not in `allowed` (keys starting with `_` are comments).
func _check_keys(d: Dictionary, allowed: Variant, file: String, path: String) -> void:
	for k: Variant in d.keys():
		var ks: String = str(k)
		if ks.begins_with("_") or ks == "__hash":
			continue
		if not (allowed as Array).has(ks) and not (allowed is PackedStringArray and (allowed as PackedStringArray).has(ks)):
			_err(file, (path + "." + ks) if path != "" else ks, "unknown key")


func _validate_shapes() -> void:
	var mixd: Dictionary = mix.raw
	for sec: String in KEYS_MIX:
		var v: Variant = mixd.get(sec)
		if v is Dictionary:
			_check_keys(v, KEYS_MIX[sec], "mix.json", sec)
	var ev: Dictionary = events.get("events", {})
	for id: Variant in ev.keys():
		var e: Variant = ev[id]
		var ctx: String = "events." + str(id)
		if not (e is Dictionary):
			_err("events.json", ctx, "must be an object")
			continue
		_check_keys(e, KEYS_EVENT, "events.json", ctx)
		if (e as Dictionary).get("spatial") is Dictionary:
			_check_keys(e["spatial"], KEYS_SPATIAL, "events.json", ctx + ".spatial")
		if (e as Dictionary).get("limit") is Dictionary:
			_check_keys(e["limit"], KEYS_LIMIT, "events.json", ctx + ".limit")
		var vars: Variant = (e as Dictionary).get("variants")
		if not (vars is Array) or (vars as Array).is_empty():
			_err("events.json", ctx + ".variants", "must be a non-empty array")
	var pr: Dictionary = events.get("profiles", {})
	for id: Variant in pr.keys():
		if pr[id] is Dictionary:
			_check_keys(pr[id], KEYS_PROFILE, "events.json", "profiles." + str(id))
		else:
			_err("events.json", "profiles." + str(id), "must be an object")
	var sm: Variant = events.get("sim_map")
	if sm is Dictionary:
		_check_keys(sm, KEYS_SIM_MAP, "events.json", "sim_map")
