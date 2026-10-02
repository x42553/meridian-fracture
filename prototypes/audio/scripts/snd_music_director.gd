class_name SndMusicDirector
extends Node
## Layered-stem music. One AudioStreamSynchronized per track (all stems start and loop in lock-step inside ONE player);
## a single scalar `intensity` (0..1, fed by the game: 0 idle/build-up ... 1 full combat) fades the stems in and out.

const STEMS: Array[StringName] = [&"drums", &"bass", &"pads", &"lead"]

## Intensity window per stem: x = where the stem starts to fade in, y = where it reaches full level.
var layer_windows: Dictionary = {
	&"pads": Vector2(0.0, 0.15), &"bass": Vector2(0.15, 0.40), &"drums": Vector2(0.35, 0.65), &"lead": Vector2(0.65, 0.95)}
var smoothing_s: float = 0.8
var intensity: float = 0.0:
	set = set_intensity
var track: StringName = &""
var bpm: float = 0.0
var bar_beats: int = 4
## Current stem levels in dB (for debug overlays and tests).
var layer_db: PackedFloat32Array = PackedFloat32Array([-80.0, -80.0, -80.0, -80.0])

var _player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _target: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _current: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)


## `entry` = one item of the "music" section of audio_events.json.
func load_track(track_id: StringName, entry: Dictionary) -> bool:
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = STEMS.size()
	for i in STEMS.size():
		var path: String = "%s/%s.ogg" % [entry["folder"], STEMS[i]]
		if not ResourceLoader.exists(path):
			push_error("SndMusicDirector: missing stem %s" % path)
			return false
		var s: AudioStreamOggVorbis = (load(path) as AudioStreamOggVorbis).duplicate()
		s.loop = true
		s.bpm = float(entry["bpm"])
		s.beat_count = int(entry["beat_count"])
		s.bar_beats = int(entry["bar_beats"])
		_sync.set_sync_stream(i, s)
		_sync.set_sync_stream_volume(i, -80.0)
	track = track_id
	bpm = float(entry["bpm"])
	bar_beats = int(entry["bar_beats"])
	_player.stream = _sync
	_apply_intensity()
	for i in STEMS.size():
		_current[i] = _target[i]
	_push_volumes(true)
	return true


func play(from_position: float = 0.0) -> void:
	_player.play(from_position)


func stop() -> void:
	_player.stop()


func player() -> AudioStreamPlayer:
	return _player


func length() -> float:
	return _sync.get_length() if _sync != null else 0.0


## Bars elapsed since the loop start (fractional) - lets the game align stingers / transitions to bar lines.
func bar_position() -> float:
	if bpm <= 0.0:
		return 0.0
	return _player.get_playback_position() * bpm / 60.0 / float(bar_beats)


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	_apply_intensity()


func _apply_intensity() -> void:
	for i in STEMS.size():
		var w: Vector2 = layer_windows.get(STEMS[i], Vector2(0.0, 1.0))
		var t: float = clampf(inverse_lerp(w.x, w.y, intensity), 0.0, 1.0)
		_target[i] = sin(t * PI * 0.5)  # equal-power fade-in


func _process(delta: float) -> void:
	if _sync == null:
		return
	var a: float = 1.0 - exp(-delta / maxf(smoothing_s, 0.001))
	for i in STEMS.size():
		_current[i] += (_target[i] - _current[i]) * a
	_push_volumes(false)


func _push_volumes(force: bool) -> void:
	for i in STEMS.size():
		var db: float = linear_to_db(maxf(_current[i], 0.0001))
		if force or absf(db - layer_db[i]) > 0.05:
			layer_db[i] = db
			_sync.set_sync_stream_volume(i, db)
