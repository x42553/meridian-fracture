class_name SndEventMap
extends RefCounted
## Data-driven audio event map: event id -> SndEventDef (variants, randomisation, 3D attenuation, limits, priority).
## Loads and validates data/audio_events.json (schema documented in REPORT.md). Unknown keys are reported, so typos in
## hand-edited data surface at load time instead of as silent missing sounds.

const SCHEMA_VERSION: int = 1
const _EVENT_KEYS: PackedStringArray = ["category", "bus", "priority", "variants", "volume_db", "volume_jitter_db", "pitch",
	"pitch_jitter_semitones", "spatial", "limit", "loop", "cull_below_db", "notes"]
const _SPATIAL_KEYS: PackedStringArray = ["mode", "unit_size", "max_distance", "attenuation", "lowpass_hz", "panning_strength"]
const _LIMIT_KEYS: PackedStringArray = ["group", "max_instances", "min_interval_ms", "steal"]

var errors: PackedStringArray = PackedStringArray()
## Music section of the JSON: track id -> {folder, bpm, beat_count, bar_beats, stems[]}.
var music: Dictionary = {}
var _defs: Dictionary = {}
var _groups: Dictionary = {}
var _sim_map: Dictionary = {}


func load_file(path: String) -> bool:
	errors.clear()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	var json: JSON = JSON.new()
	if json.parse(f.get_as_text()) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return false
	var root: Dictionary = json.data
	if int(root.get("version", 0)) != SCHEMA_VERSION:
		errors.append("unsupported schema version %s (expected %d)" % [str(root.get("version")), SCHEMA_VERSION])
		return false
	_groups = root.get("groups", {})
	_sim_map = root.get("sim_map", {})
	music = root.get("music", {})
	var events: Dictionary = root.get("events", {})
	for id: String in events:
		var def: SndEventDef = _parse_event(StringName(id), events[id])
		if def != null:
			_defs[StringName(id)] = def
	return errors.is_empty()


func has_event(id: StringName) -> bool:
	return _defs.has(id)


func event_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _defs:
		out.append(k)
	return out


## Looks up "<id>@<variant>" first (per-faction / per-announcer override), then "<id>".
func get_def(id: StringName, variant: StringName = &"") -> SndEventDef:
	if variant != &"":
		var specific: StringName = StringName("%s@%s" % [id, variant])
		if _defs.has(specific):
			return _defs[specific]
	return _defs.get(id, null)


func group_limit(group: StringName) -> int:
	return int((_groups.get(String(group), {}) as Dictionary).get("max_voices", 1 << 20))


## Maps gameplay tags to an event id through the "sim_map" patterns, e.g. resolve(&"weapon_fire", {"snd": "rifle"}) -> weapon.rifle.fire.
func resolve(kind: StringName, tags: Dictionary) -> StringName:
	var rule: Dictionary = _sim_map.get(String(kind), {})
	if rule.is_empty():
		return &""
	var id: StringName = StringName(String(rule.get("pattern", "")).format(tags))
	if _defs.has(id):
		return id
	return StringName(String(rule.get("fallback", "")))


func _parse_event(id: StringName, d: Dictionary) -> SndEventDef:
	for k: String in d:
		if not _EVENT_KEYS.has(k):
			errors.append("%s: unknown key '%s'" % [id, k])
	var def: SndEventDef = SndEventDef.new()
	def.id = id
	def.category = StringName(d.get("category", ""))
	def.bus = StringName(d.get("bus", "Sfx"))
	def.priority = clampi(int(d.get("priority", 50)), 0, 100)
	def.volume_db = float(d.get("volume_db", 0.0))
	def.volume_jitter_db = float(d.get("volume_jitter_db", 0.0))
	def.pitch = float(d.get("pitch", 1.0))
	def.pitch_jitter_semitones = float(d.get("pitch_jitter_semitones", 0.0))
	def.loop = bool(d.get("loop", false))
	def.cull_below_db = float(d.get("cull_below_db", -50.0))
	var sp: Dictionary = d.get("spatial", {})
	for k: String in sp:
		if not _SPATIAL_KEYS.has(k):
			errors.append("%s.spatial: unknown key '%s'" % [id, k])
	match String(sp.get("mode", "3d")):
		"ui":
			def.spatial = SndEventDef.Spatial.UI
		"global":
			def.spatial = SndEventDef.Spatial.GLOBAL
		"3d":
			def.spatial = SndEventDef.Spatial.WORLD_3D
		var other:
			errors.append("%s.spatial.mode: '%s' (ui|global|3d)" % [id, other])
	def.unit_size = float(sp.get("unit_size", 30.0))
	def.max_distance = float(sp.get("max_distance", 250.0))
	def.lowpass_hz = float(sp.get("lowpass_hz", 20500.0))
	def.panning_strength = float(sp.get("panning_strength", 1.0))
	match String(sp.get("attenuation", "inverse")):
		"inverse":
			def.attenuation = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		"inverse_square":
			def.attenuation = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		"logarithmic":
			def.attenuation = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		"none":
			def.attenuation = AudioStreamPlayer3D.ATTENUATION_DISABLED
		var other:
			errors.append("%s.spatial.attenuation: '%s'" % [id, other])
	var lim: Dictionary = d.get("limit", {})
	for k: String in lim:
		if not _LIMIT_KEYS.has(k):
			errors.append("%s.limit: unknown key '%s'" % [id, k])
	def.group = StringName(lim.get("group", ""))
	def.max_instances = maxi(1, int(lim.get("max_instances", 8)))
	def.min_interval_ms = maxi(0, int(lim.get("min_interval_ms", 0)))
	match String(lim.get("steal", "oldest")):
		"none":
			def.steal = SndEventDef.Steal.NONE
		"oldest":
			def.steal = SndEventDef.Steal.OLDEST
		"quietest":
			def.steal = SndEventDef.Steal.QUIETEST
		var other:
			errors.append("%s.limit.steal: '%s'" % [id, other])
	var variants: Array = d.get("variants", [])
	if variants.is_empty():
		errors.append("%s: no variants" % id)
		return null
	for v: Dictionary in variants:
		var path: String = String(v.get("stream", ""))
		if not ResourceLoader.exists(path):
			errors.append("%s: missing stream %s" % [id, path])
			continue
		var s: AudioStream = load(path)
		def.streams.append(_prepare(s, def.loop))
		def.weights.append(float(v.get("weight", 1.0)))
	return def if not def.streams.is_empty() else null


## Loop flag lives on the (cached, shared) stream resource, so loops get a private duplicate.
func _prepare(s: AudioStream, loop: bool) -> AudioStream:
	if not loop:
		return s
	if s is AudioStreamOggVorbis:
		var o: AudioStreamOggVorbis = (s as AudioStreamOggVorbis).duplicate()
		o.loop = true
		return o
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	return s
