class_name SndMusicLibrary
extends RefCounted
## Builds the per-faction AudioStreamInteractive of the dynamic music (audio spec 5.8): clips are AudioStreamSynchronized
## stem stacks whose children are duplicated, looping OGG streams carrying the track's bpm / bar metadata.

class Built:
	extends RefCounted
	var stream: AudioStreamInteractive = null
	var sync: Dictionary = {}  ## clip name -> AudioStreamSynchronized
	var clip_index: Dictionary = {}  ## clip name -> int
	var bpm: Dictionary = {}  ## clip name -> float
	var stems: PackedStringArray = PackedStringArray()

const CLIP_CALM: StringName = &"calm"
const CLIP_COMBAT: StringName = &"combat"
const CLIP_RISER: StringName = &"riser"
const CLIP_HOT: StringName = &"combat_hot"
const FROM_NAMES: Dictionary = {"immediate": 0, "next_beat": 1, "next_bar": 2, "end": 3}
const TO_NAMES: Dictionary = {"same_position": 0, "start": 1, "previous_position": 2}
const FADE_NAMES: Dictionary = {"disabled": 0, "in": 1, "out": 2, "cross": 3, "automatic": 4}

var _store: SndDataStore = null
var _index: SndAssetIndex = null


func setup(store: SndDataStore, index: SndAssetIndex) -> void:
	_store = store
	_index = index


func tracks() -> Dictionary:
	return _store.music.get("tracks", {})


func set_of(faction: StringName) -> Dictionary:
	return (_store.music.get("sets", {}) as Dictionary).get(String(faction), {})


func banks_of(faction: StringName) -> PackedStringArray:
	return PackedStringArray(["mus_%s" % String(faction), "mus_common"])


func request_set(faction: StringName) -> void:
	_index.request_banks(banks_of(faction))


func has_set(faction: StringName) -> bool:
	return not set_of(faction).is_empty()


## One track as a stem stack (AudioStreamSynchronized) with looping, bpm-tagged children; null when the track is unknown.
func build_sync(track_id: String) -> AudioStreamSynchronized:
	var t: Variant = tracks().get(track_id)
	if not (t is Dictionary):
		return null
	var td: Dictionary = t
	var stems: Array = td.get("stems", [])
	var sync: AudioStreamSynchronized = AudioStreamSynchronized.new()
	sync.stream_count = stems.size()
	var loaded: int = 0
	for i: int in stems.size():
		var sid: String = "%s/%s" % [str(td.get("folder", "")), str(stems[i])]
		if not _index.has_asset(sid):
			continue
		var s: AudioStream = _index.get_stream(sid, false)
		if s == null:
			continue
		loaded += 1
		s = SndAssetIndex.apply_loop(s, true)
		if s is AudioStreamOggVorbis:
			var o: AudioStreamOggVorbis = s
			o.bpm = float(td.get("bpm", 120.0))
			o.beat_count = int(td.get("beat_count", 0))
			o.bar_beats = int(td.get("bar_beats", 4))
		sync.set_sync_stream(i, s)
	return sync if loaded > 0 else null


func stems_of(track_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var t: Variant = tracks().get(track_id)
	if t is Dictionary:
		for s: Variant in (t as Dictionary).get("stems", []):
			out.append(str(s))
	return out


func bpm_of(track_id: String) -> float:
	var t: Variant = tracks().get(track_id)
	return float((t as Dictionary).get("bpm", 120.0)) if t is Dictionary else 120.0


## Faction stream: clip 0 calm, 1 combat, 2 riser (filler), 3 combat_hot (alias of combat's stem stack).
func build_interactive(faction: StringName) -> Built:
	var tset: Dictionary = set_of(faction)
	if tset.is_empty():
		return null
	var b: Built = Built.new()
	var calm: AudioStreamSynchronized = build_sync(str(tset.get("calm", "")))
	var combat: AudioStreamSynchronized = build_sync(str(tset.get("combat", "")))
	if calm == null or combat == null:
		return null
	b.stems = stems_of(str(tset.get("combat", "")))
	var inter: AudioStreamInteractive = AudioStreamInteractive.new()
	inter.clip_count = 4
	inter.set_clip_name(0, CLIP_CALM)
	inter.set_clip_stream(0, calm)
	inter.set_clip_name(1, CLIP_COMBAT)
	inter.set_clip_stream(1, combat)
	inter.set_clip_name(2, CLIP_RISER)
	var riser: AudioStream = _stinger_stream(str(tset.get("riser", "")))
	if riser != null:
		inter.set_clip_stream(2, riser)
	inter.set_clip_name(3, CLIP_HOT)
	inter.set_clip_stream(3, combat)
	inter.initial_clip = 0
	b.clip_index = {CLIP_CALM: 0, CLIP_COMBAT: 1, CLIP_RISER: 2, CLIP_HOT: 3}
	b.sync = {CLIP_CALM: calm, CLIP_COMBAT: combat, CLIP_HOT: combat}
	b.bpm = {CLIP_CALM: bpm_of(str(tset.get("calm", ""))), CLIP_COMBAT: bpm_of(str(tset.get("combat", ""))), CLIP_HOT: bpm_of(str(tset.get("combat", "")))}
	_add_transitions(inter, b, riser != null)
	b.stream = inter
	return b


func _add_transitions(inter: AudioStreamInteractive, b: Built, has_riser: bool) -> void:
	var trs: Dictionary = _store.music.get("transitions", {})
	for key: Variant in trs.keys():
		var parts: PackedStringArray = str(key).split(">")
		if parts.size() != 2 or not b.clip_index.has(StringName(parts[0])) or not b.clip_index.has(StringName(parts[1])):
			continue
		var t: Dictionary = trs[key]
		var from_i: int = b.clip_index[StringName(parts[0])]
		var to_i: int = b.clip_index[StringName(parts[1])]
		var filler: String = str(t.get("filler", ""))
		var use_filler: bool = filler != "" and has_riser and b.clip_index.has(StringName(filler))
		var fb: float = float(t.get("fade_beats", 1.0))
		_add_one(inter, from_i, to_i, t, use_filler, b.clip_index.get(StringName(filler), -1), fb)
		if parts[0] == "combat" and parts[1] == "calm":
			_add_one(inter, 3, to_i, t, false, -1, fb)  # combat_hot leaves the same way


func _add_one(inter: AudioStreamInteractive, from_i: int, to_i: int, t: Dictionary, use_filler: bool, filler_i: int, fade_beats: float) -> void:
	inter.add_transition(from_i, to_i, int(FROM_NAMES.get(str(t.get("from", "next_bar")), 2)) as AudioStreamInteractive.TransitionFromTime,
		int(TO_NAMES.get(str(t.get("to", "start")), 1)) as AudioStreamInteractive.TransitionToTime,
		int(FADE_NAMES.get(str(t.get("fade", "cross")), 3)) as AudioStreamInteractive.FadeMode, fade_beats, use_filler, filler_i)


func _stinger_stream(stinger_id: String) -> AudioStream:
	var st: Variant = (_store.music.get("stingers", {}) as Dictionary).get(stinger_id)
	if not (st is Dictionary):
		return null
	return _index.get_stream(str((st as Dictionary).get("stream", "")), false)


func stinger(stinger_id: String) -> AudioStream:
	return _stinger_stream(stinger_id)


func menu_track_id(context: String = "menu") -> String:
	var c: Variant = (_store.music.get("contexts", {}) as Dictionary).get(context)
	return str((c as Dictionary).get("track", "")) if c is Dictionary else ""


func menu_intensity(context: String = "menu") -> float:
	var c: Variant = (_store.music.get("contexts", {}) as Dictionary).get(context)
	return float((c as Dictionary).get("intensity", 0.5)) if c is Dictionary else 0.5
