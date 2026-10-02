class_name SndMusicDirector
extends Node
## Music state machine (audio spec 5.8): MENU / CALM / COMBAT / STINGER over an AudioStreamInteractive, safe transitions
## (one at a time, minimum interval, no reversal while a switch is pending), stem levels following the intensity windows
## of music.json, stingers and the menu theme. Time comes from the caller (`update(dt, now_ms)`).

signal state_changed(state: int, track_id: StringName)
signal stinger_finished()

enum State { NONE = 0, MENU = 1, CALM = 2, COMBAT = 3, STINGER = 4 }

const CLIP_OF_STATE: Dictionary = {State.CALM: 0, State.COMBAT: 1}
const MIN_DB_DELTA: float = 0.05
const STEM_FLOOR_DB: float = -80.0

## Test seam: an object with `switch_to_clip(int)` and `get_current_clip_index() -> int` replaces the engine playback.
var playback_stub: Object = null
var switch_count: int = 0

var _lib: SndMusicLibrary = null
var _store: SndDataStore = null
var _state: int = State.NONE
var _pending: int = State.NONE
var _pending_since_ms: int = 0
var _pending_hold_ms: int = 0
var _last_switch_ms: int = -100000
var _built: SndMusicLibrary.Built = null
var _player: AudioStreamPlayer = null
var _stinger_player: AudioStreamPlayer = null
var _menu_player: AudioStreamPlayer = null
var _menu_sync: AudioStreamSynchronized = null
var _menu_track: String = ""
var _track_id: StringName = &""
var _faction: StringName = &""
var _intensity_target: float = 0.2
var _stem_cur: PackedFloat32Array = PackedFloat32Array()
var _stem_tgt: PackedFloat32Array = PackedFloat32Array()
var _stem_applied: Dictionary = {}  ## "clip|i" -> last applied dB
var _min_switch_s: float = 8.0
var _smoothing_s: float = 0.8
var _windows: Dictionary = {}
var _volume_db: float = 0.0
var _volume_target: float = 0.0
var _volume_ramp_s: float = 0.0
var _stop_after_fade: bool = false
var _combat_since_ms: int = 0
var _fade_left_s: float = 0.0


func setup(lib: SndMusicLibrary, store: SndDataStore) -> void:
	_lib = lib
	_store = store
	var d: Dictionary = store.music.get("director", {})
	_min_switch_s = float(d.get("min_switch_interval_s", 8.0))
	_smoothing_s = float(d.get("smoothing_s", 0.8))
	_windows = store.music.get("stem_windows", {})
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "MusicPlayer"
		_player.bus = SndBus.MUSIC
		add_child(_player)
		_menu_player = AudioStreamPlayer.new()
		_menu_player.name = "MenuPlayer"
		_menu_player.bus = SndBus.MUSIC
		add_child(_menu_player)
		_stinger_player = AudioStreamPlayer.new()
		_stinger_player.name = "StingerPlayer"
		_stinger_player.bus = SndBus.MUSIC
		add_child(_stinger_player)
		_stinger_player.finished.connect(_on_stinger_finished)


func current_state() -> int:
	return _state


func current_track() -> StringName:
	return _track_id


func is_transition_pending() -> bool:
	return _pending != State.NONE


func pending_state() -> int:
	return _pending


func stem_levels_db() -> PackedFloat32Array:
	return _stem_cur


func set_min_switch_interval(seconds: float) -> void:
	_min_switch_s = seconds


## Menu theme (also the lobby context via `intensity`).
func enter_menu(context: String = "menu") -> void:
	_stop_match_player()
	var tid: String = _lib.menu_track_id(context)
	if tid == "":
		_state = State.MENU
		_track_id = &"menu"
		state_changed.emit(_state, _track_id)
		return
	if _menu_track != tid or _menu_sync == null:
		_menu_sync = _lib.build_sync(tid)
		_menu_track = tid
	if _menu_sync != null:
		_menu_player.stream = _menu_sync
		_menu_player.volume_db = 0.0
		if not _menu_player.playing:
			_menu_player.play()
	_intensity_target = _lib.menu_intensity(context)
	_apply_menu_stems()
	_state = State.MENU
	_track_id = StringName(tid)
	state_changed.emit(_state, _track_id)


## Faction music starting CALM; fades the menu player out.
func enter_match(faction: StringName) -> void:
	_faction = faction
	if _menu_player != null and _menu_player.playing:
		_menu_player.stop()
	_built = _lib.build_interactive(faction)
	_state = State.CALM
	_pending = State.NONE
	_last_switch_ms = -100000
	_intensity_target = 0.2
	_stem_applied.clear()
	if _built == null:
		_track_id = &""
		state_changed.emit(_state, _track_id)
		return
	_player.stream = _built.stream
	_volume_db = SndConfig.SILENT_DB
	_player.volume_db = _volume_db
	_player.play()
	_fade_to(0.0, 1.5)
	_track_id = StringName(str(_lib.set_of(faction).get("calm", "")))
	_stem_cur = PackedFloat32Array()
	_stem_cur.resize(_built.stems.size())
	_stem_cur.fill(STEM_FLOOR_DB)
	_stem_tgt = _stem_cur.duplicate()
	state_changed.emit(_state, _track_id)


## Drops every stream reference (shutdown): nothing may keep a decoded bank alive.
func release() -> void:
	for p: AudioStreamPlayer in [_player, _menu_player, _stinger_player]:
		if p != null:
			p.stop()
			p.stream = null
	_built = null
	_menu_sync = null
	_state = State.NONE
	_pending = State.NONE


func _stop_match_player() -> void:
	if _player != null and _player.playing:
		_player.stop()
	_built = null
	_pending = State.NONE


func _playback() -> Object:
	if playback_stub != null:
		return playback_stub
	if _player == null or not _player.playing:
		return null
	return _player.get_stream_playback()


func _clip_state(idx: int) -> int:
	return State.CALM if idx == 0 else (State.COMBAT if idx == 1 or idx == 3 else State.NONE)


## CALM / COMBAT only. Ignored while a transition is pending (a reversal would drop out, probe P3), within the minimum
## switch interval, or when the state is already current. `urgent` enters COMBAT via the riser-less hot clip.
func request_state(state: int, urgent: bool = false, now_ms: int = -1) -> bool:
	if state != State.CALM and state != State.COMBAT:
		return false
	var now: int = now_ms if now_ms >= 0 else SndConfig.now_ms()
	if _pending != State.NONE or state == _state:
		return false
	if _state != State.CALM and _state != State.COMBAT:
		return false
	if not urgent and now - _last_switch_ms < int(_min_switch_s * 1000.0):
		return false
	var pb: Object = _playback()
	if pb == null:
		return false
	var clip: int = 0
	if state == State.COMBAT:
		clip = 3 if (urgent and _state == State.CALM) else 1
	pb.call("switch_to_clip", clip)
	switch_count += 1
	_pending = state
	_pending_since_ms = now
	var bpm: float = 120.0
	if _built != null:
		bpm = float(_built.bpm.get(&"combat" if state == State.COMBAT else &"calm", 120.0))
	_pending_hold_ms = int((1.0 + (4.0 * 60.0 / maxf(bpm, 30.0))) * 1000.0)
	return true


func set_intensity(v: float) -> void:
	_intensity_target = clampf(v, 0.0, 1.0)


func intensity() -> float:
	return _intensity_target


func play_stinger(stinger_id: StringName, fade_music_ms: int = 1200) -> void:
	var s: AudioStream = _lib.stinger(String(stinger_id)) if _lib != null else null
	_fade_to(SndConfig.SILENT_DB, float(fade_music_ms) / 1000.0)
	_state = State.STINGER
	_pending = State.NONE
	if s == null:
		state_changed.emit(_state, stinger_id)
		_on_stinger_finished()
		return
	_stinger_player.stream = s
	_stinger_player.volume_db = 0.0
	_stinger_player.play()
	state_changed.emit(_state, stinger_id)


func _on_stinger_finished() -> void:
	if _state == State.STINGER:
		_state = State.NONE
	stinger_finished.emit()


func stop(fade_ms: int = 1500) -> void:
	_pending = State.NONE
	_state = State.NONE
	_fade_to(SndConfig.SILENT_DB, float(fade_ms) / 1000.0)
	_stop_after_fade = true
	if _menu_player != null and _menu_player.playing:
		_menu_player.stop()


func _fade_to(db: float, seconds: float) -> void:
	_volume_target = db
	_volume_ramp_s = maxf(seconds, 0.001)
	_fade_left_s = _volume_ramp_s
	_stop_after_fade = false


## Target dB of one stem at `intensity` in the window set of `kind` ("calm" / "combat"): equal-power curve.
func stem_target_db(kind: String, stem: String, intensity_v: float) -> float:
	var w: Variant = (_windows.get(kind, {}) as Dictionary).get(stem)
	if not (w is Array) or (w as Array).size() < 2:
		return 0.0
	var lo: float = float((w as Array)[0])
	var hi: float = float((w as Array)[1])
	var t: float = clampf(inverse_lerp(lo, hi, intensity_v), 0.0, 1.0)
	var g: float = sin(t * PI * 0.5)
	return maxf(linear_to_db(maxf(g, 1e-4)), STEM_FLOOR_DB)


func _apply_menu_stems() -> void:
	if _menu_sync == null:
		return
	var stems: PackedStringArray = _lib.stems_of(_menu_track)
	for i: int in stems.size():
		_menu_sync.set_sync_stream_volume(i, stem_target_db("combat", stems[i], _intensity_target))


func update(dt: float, now_ms: int) -> void:
	# master fade of the match player
	if _volume_ramp_s > 0.0 and not is_equal_approx(_volume_db, _volume_target):
		var step: float = (_volume_target - _volume_db) * (1.0 - exp(-dt / maxf(_fade_left_s * 0.35, 0.02)))
		_volume_db += clampf(step, -SndConfig.RAMP_MAX_STEP_DB_PER_FRAME, SndConfig.RAMP_MAX_STEP_DB_PER_FRAME)
		if absf(_volume_db - _volume_target) < 0.05:
			_volume_db = _volume_target
		_player.volume_db = _volume_db
		_fade_left_s = maxf(_fade_left_s - dt, 0.05)
	elif _stop_after_fade and _player != null:
		_player.stop()
		_stop_after_fade = false
	# pending transition completion
	if _pending != State.NONE:
		var pb: Object = _playback()
		var idx: int = int(pb.call("get_current_clip_index")) if pb != null else -1
		if _clip_state(idx) == _pending and now_ms - _pending_since_ms >= _pending_hold_ms:
			_state = _pending
			_pending = State.NONE
			_last_switch_ms = now_ms
			if _state == State.COMBAT:
				_combat_since_ms = now_ms
			var tset: Dictionary = _lib.set_of(_faction)
			_track_id = StringName(str(tset.get("combat" if _state == State.COMBAT else "calm", "")))
			state_changed.emit(_state, _track_id)
		elif pb == null and playback_stub == null:
			_pending = State.NONE
	# stems
	if _built != null and _state != State.NONE:
		_update_stems(dt)
	elif _state == State.MENU:
		_apply_menu_stems()


func _update_stems(dt: float) -> void:
	var k: float = 1.0 - exp(-dt / maxf(_smoothing_s, 0.05))
	var stems: PackedStringArray = _built.stems
	if _stem_cur.size() != stems.size():
		_stem_cur.resize(stems.size())
		_stem_tgt.resize(stems.size())
	for i: int in stems.size():
		# the active clip's window follows the state; the other one follows its own kind so a fade-in already sounds right
		var kind: String = "combat" if _state == State.COMBAT or _pending == State.COMBAT else "calm"
		_stem_tgt[i] = stem_target_db(kind, stems[i], _intensity_target)
		_stem_cur[i] += (_stem_tgt[i] - _stem_cur[i]) * k
		for clip: StringName in [&"calm", &"combat"]:
			var key: String = "%s|%d" % [clip, i]
			var last: float = float(_stem_applied.get(key, 999.0))
			if absf(_stem_cur[i] - last) >= MIN_DB_DELTA:
				var sync: AudioStreamSynchronized = _built.sync.get(clip)
				if sync != null and i < sync.stream_count:
					sync.set_sync_stream_volume(i, _stem_cur[i])
				_stem_applied[key] = _stem_cur[i]
