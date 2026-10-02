class_name SndManager
extends Node
## The audio facade (autoload `Snd`, audio spec 3.1): owns every subsystem, loads the data, builds the buses, and turns the
## per-frame feeds of the app (camera pose, the sim event batch) plus direct calls from UI / net into sound. Presentation
## only: it never mutates the simulation and never touches the checksum (DR-12).

signal announcement_started(line_id: StringName, text: String, priority: int)
signal announcement_finished(line_id: StringName)
signal music_state_changed(state: int, track_id: StringName)
signal audio_warning(code: int, message: String)

const MODE_BOOT: int = 0
const MODE_MENU: int = 1
const MODE_LOBBY: int = 2
const MODE_LOADING: int = 3
const MODE_MATCH: int = 4
const MODE_POST_MATCH: int = 5

const SEED_XOR: int = 0x53E1D
const LOW_POWER_POLL_S: float = 1.0
const ATTACH_RETRY_S: float = 1.0

var store: SndDataStore = null
var index: SndAssetIndex = null
var map: SndEventMap = null
var scheduler: SndScheduler = null
var fader: SndBusFader = null
var reader: SndWorldReader = null
var bank: SndSoundBank = null
var bridge: SndSimBridge = null
var loops: SndLoopManager = null
var meter: SndCombatMeter = null
var countdown: SndCountdown = null
var ambience: SndAmbience = null
var listener: SndListener = null
var responses: SndUnitResponse = null
var stats_obj: SndStats = SndStats.new()
var mode: int = MODE_BOOT
var ready_ok: bool = false
var virtual_pool: bool = false  ## bookkeeping-only pool (tools without an audio server)

var _pool: SndVoicePool = null
var _announcer: SndAnnouncer = null
var _music: SndMusicDirector = null
var _library: SndMusicLibrary = null
var _settings: SndSettings = SndSettings.new()
var _cfg: SndMatchConfig = null
var _world_root: Node3D = null
var _attach_left: float = 0.0
var _attached: bool = false
var _dt: float = 0.016
var _match_loading: bool = false
var _match_active: bool = false
var _bound_world: SimWorld = null
var _clock: Callable = Callable()
var _time_ms_override: int = -1
var _low_power_left: float = 0.0
var _combat_since_ms: int = 0
var _deferred: Array[Dictionary] = []
var _monitors: PackedStringArray = PackedStringArray()
var _muted_by_focus: bool = false
var _post_result: int = SndMatchConfig.RESULT_NONE


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "Snd"


# ------------------------------------------------------------------ lifecycle

## Loads and validates `game/data/audio`, builds the buses and every subsystem. Returns false only when the data is unusable;
## audio then stays silent and the game goes on.
func setup(data_dir: String = SndConfig.DATA_DIR) -> bool:
	_clock = Callable(self, "now_ms")
	store = SndDataStore.new()
	if not store.load_all(data_dir):
		for e: String in store.errors:
			Log.error("snd", e)
		audio_warning.emit(SndConfig.W_DATA, "audio data failed to load: %s" % (store.errors[0] if not store.errors.is_empty() else "?"))
		return false
	index = SndAssetIndex.new()
	var index_path: String = data_dir.get_base_dir().get_base_dir().path_join("assets/audio/asset_index.json") if data_dir != SndConfig.DATA_DIR else SndConfig.INDEX_PATH
	if not index.setup(index_path):
		Log.warn("snd", "no audio asset index (%s): sounds will be silent placeholders" % index_path)
	map = SndEventMap.new()
	if not map.build(store, index):
		for e2: String in map.errors:
			Log.error("snd", e2)
		audio_warning.emit(SndConfig.W_DATA, "audio events failed to build: %s" % (map.errors[0] if not map.errors.is_empty() else "?"))
		return false
	SndBus.setup(store.mix)
	map.assign_bus_indices()
	fader = SndBusFader.new()
	scheduler = SndScheduler.new()
	reader = SndWorldReader.new()
	meter = SndCombatMeter.new()
	meter.configure(store.music.get("meter", {}))
	_pool = SndVoicePool.new()
	_pool.name = "Pool"
	_pool.virtual_mode = virtual_pool
	add_child(_pool)
	_pool.setup(map, store.mix, 1, _clock)
	_library = SndMusicLibrary.new()
	_library.setup(store, index)
	_music = SndMusicDirector.new()
	_music.name = "Music"
	add_child(_music)
	_music.setup(_library, store)
	_music.state_changed.connect(func(s: int, t: StringName) -> void: music_state_changed.emit(s, t))
	_music.stinger_finished.connect(func() -> void:
		if mode == MODE_POST_MATCH and ready_ok:
			_music.enter_menu("menu"))
	_announcer = SndAnnouncer.new()
	_announcer.name = "Announcer"
	add_child(_announcer)
	_announcer.setup(store, index, _clock, 2)
	_announcer.started.connect(func(l: StringName, t: String, p: int) -> void: announcement_started.emit(l, t, p))
	_announcer.finished.connect(func(l: StringName) -> void: announcement_finished.emit(l))
	_announcer.set_duck_callback(_duck_for_tts)
	responses = SndUnitResponse.new()
	responses.setup(store, index, self, _clock, 3)
	ambience = SndAmbience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(store, map, reader)
	countdown = SndCountdown.new()
	countdown.setup(reader, _pool, map)
	loops = SndLoopManager.new()
	listener = SndListener.new()
	listener.name = "Listener"
	_register_monitors()
	apply_settings(_settings)
	if AudioServer.get_driver_name() == "Dummy":
		audio_warning.emit(SndConfig.W_DUMMY_DRIVER, "audio runs on the Dummy driver (no output device)")
	ready_ok = true
	return true


func shutdown() -> void:
	if not ready_ok and _pool == null:
		return
	end_match(SndMatchConfig.RESULT_ABORT)
	detach_world()
	for id: String in _monitors:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
	_monitors = PackedStringArray()
	if _music != null:
		_music.stop(0)
		_music.release()
	if _pool != null:
		_pool.release_streams()
	if _announcer != null:
		_announcer.release()
	if ambience != null:
		ambience.stop(0)
	if index != null:
		index.release_banks(PackedStringArray())
	ready_ok = false
	if listener != null and is_instance_valid(listener) and listener.get_parent() == null:
		listener.free()
	listener = null


func _register_monitors() -> void:
	var defs: Array = [["snd/voices_3d", Callable(self, "_mon_v3")], ["snd/voices_2d", Callable(self, "_mon_v2")], ["snd/starts", Callable(self, "_mon_starts")],
		["snd/culls", Callable(self, "_mon_culls")], ["snd/heat", Callable(self, "_mon_heat")], ["snd/queue", Callable(self, "_mon_queue")]]
	for d: Array in defs:
		if not Performance.has_custom_monitor(d[0]):
			Performance.add_custom_monitor(d[0], d[1])
			_monitors.append(d[0])


func _mon_v3() -> int:
	return _pool.active_3d() if _pool != null else 0


func _mon_v2() -> int:
	return _pool.active_2d() if _pool != null else 0


func _mon_starts() -> int:
	return _pool.stats.starts if _pool != null else 0


func _mon_culls() -> int:
	return _pool.stats.culls if _pool != null else 0


func _mon_heat() -> float:
	return meter.heat if meter != null else 0.0


func _mon_queue() -> int:
	return _announcer.queue_size() if _announcer != null else 0


## Wall clock in ms; tests can pin it.
func now_ms() -> int:
	return _time_ms_override if _time_ms_override >= 0 else Time.get_ticks_msec()


func set_time_override(ms: int) -> void:
	_time_ms_override = ms


# ------------------------------------------------------------------ accessors

func music() -> SndMusicDirector:
	return _music


func pool() -> SndVoicePool:
	return _pool


func announcer() -> SndAnnouncer:
	return _announcer


func stats() -> SndStats:
	return _pool.stats if _pool != null else stats_obj


func settings() -> SndSettings:
	return _settings


func captions_enabled() -> bool:
	return _settings.captions


func is_ready() -> bool:
	return ready_ok


# ------------------------------------------------------------------ world and match

## Creates the 3D pool and the listener under `world_root`. Needs a current Camera3D in the same viewport.
func attach_world(world_root: Node3D) -> bool:
	if not ready_ok or world_root == null:
		return false
	_world_root = world_root
	if _attached:
		detach_world()
	var ok: bool = listener.setup(world_root, _pool, store.mix)
	if not ok:
		audio_warning.emit(SndConfig.W_NO_CAMERA, "no current Camera3D in the audio viewport; positional audio retries every second")
		Log.warn("snd", "attach_world: no current Camera3D yet")
		_attach_left = ATTACH_RETRY_S
		if listener.get_parent() != null:
			listener.get_parent().remove_child(listener)
		return false
	_pool.attach_3d(world_root, store.mix.voices_3d)
	_attached = true
	_attach_left = 0.0
	return true


func detach_world() -> void:
	_world_root = null
	if _pool != null:
		_pool.detach_3d()
	if listener != null:
		listener.release()
		if listener.get_parent() != null:
			listener.get_parent().remove_child(listener)
	_attached = false


func is_world_attached() -> bool:
	return _attached


func set_mode(new_mode: int) -> void:
	if not ready_ok:
		mode = new_mode
		return
	if new_mode == mode:
		return
	mode = new_mode
	match new_mode:
		MODE_MENU, MODE_POST_MATCH:
			ambience.set_enabled(false)
			_music.enter_menu("menu")
		MODE_LOBBY:
			ambience.set_enabled(false)
			_music.enter_menu("lobby")


func begin_match(cfg: SndMatchConfig) -> void:
	if not ready_ok:
		return
	end_match(SndMatchConfig.RESULT_ABORT)
	_cfg = cfg
	mode = MODE_LOADING
	_match_loading = true
	_match_active = false
	_bound_world = null
	_pool.reset(cfg.match_seed ^ SEED_XOR)
	meter.reset()
	loops = SndLoopManager.new()
	countdown.clear()
	if cfg.data != null:
		bank = SndSoundBank.new()
		bank.bake(cfg.data, map, store.mix)
	var banks: PackedStringArray = PackedStringArray(["core", "amb", "vox_computer", "mus_common"])
	for f: String in cfg.factions_in_match():
		banks.append("fx_" + f)
	var lf: String = cfg.local_faction()
	var packs: Dictionary = _packs_of(lf, cfg.local_roster_id)
	if lf != "":
		banks.append_array(PackedStringArray(["vox_" + str(packs["announcer"]), "resp_" + str(packs["response"]), "mus_" + str(packs["music"])]))
	index.request_banks(banks)
	_announcer.set_pack(StringName(str(packs["announcer"])) if lf != "" else &"computer")
	responses.set_faction(str(packs["response"]))
	if cfg.observer or cfg.replay:
		_announcer.set_mode(SndSettings.ANN_OFF)
		responses.set_mode(SndSettings.UV_OFF)
	else:
		_announcer.set_mode(_settings.announcer_mode)
		responses.set_mode(_settings.unit_voice_mode)
	_pool.set_gate_priority(0)
	if index.banks_ready():
		_finish_match_start()


## Music set / announcer pack / response pack of a faction: factions.json, with the optional per-roster override.
func _packs_of(faction: String, roster_id: String) -> Dictionary:
	var out: Dictionary = {"music": faction, "announcer": faction, "response": faction, "flavour": faction}
	var f: Dictionary = (store.factions.get("factions", {}) as Dictionary).get(faction, {})
	var ov: Dictionary = (store.factions.get("roster_overrides", {}) as Dictionary).get(roster_id, {})
	for k: String in ["music", "announcer", "response"]:
		var key: String = "%s_set" % k if k == "music" else "%s_pack" % k
		out[k] = str(ov.get(key, f.get(key, faction)))
	out["flavour"] = str(ov.get("weapon_flavour", f.get("weapon_flavour", faction)))
	return out


func load_progress() -> float:
	return index.load_progress() if index != null else 1.0


func is_match_ready() -> bool:
	return _match_active and not _match_loading


func _finish_match_start() -> void:
	_match_loading = false
	_match_active = true
	mode = MODE_MATCH
	ambience.set_environment(_cfg.family, _cfg.biome)
	ambience.set_enabled(true)
	var music_set: StringName = StringName(str(_packs_of(_cfg.local_faction(), _cfg.local_roster_id)["music"]))
	if _settings.music_mode != SndSettings.MUSIC_OFF and _library.has_set(music_set):
		_music.enter_match(music_set)
	elif _settings.music_mode != SndSettings.MUSIC_OFF:
		_music.stop(300)
	if not _cfg.observer and not _cfg.replay:
		var lf: String = _cfg.local_faction()
		if lf != "":
			_announcer.say(StringName("match_start_" + lf), 90)
		_announcer.say(&"match_start", 90)


## Result -> stinger + announcer line; fades music, ambience and loops. Idempotent.
func end_match(result: int) -> void:
	if not ready_ok:
		return
	var was_active: bool = _match_active or _match_loading
	_match_loading = false
	_match_active = false
	if loops != null:
		loops.clear()
	if countdown != null:
		countdown.clear()
	if scheduler != null:
		scheduler.clear()
	ambience.stop(1500)
	ambience.set_enabled(false)
	if not was_active:
		return
	_post_result = result
	mode = MODE_POST_MATCH
	var f: String = _cfg.local_faction() if _cfg != null else ""
	if result == SndMatchConfig.RESULT_VICTORY or result == SndMatchConfig.RESULT_DEFEAT:
		var which: String = "victory" if result == SndMatchConfig.RESULT_VICTORY else "defeat"
		if f != "" and _settings.music_mode != SndSettings.MUSIC_OFF:
			_music.play_stinger(StringName("stinger.%s.%s" % [f, which]), 1200)
		_deferred.append({"at": now_ms() + 1500, "line": which})
	else:
		_music.stop(1000)
	_bound_world = null
	if reader != null:
		reader.world = null


func set_time_scale(scale: float) -> void:
	if _pool != null:
		_pool.set_gate_priority(store.mix.replay_gate_priority if scale > 2.0 else 0)


func set_world_paused(paused: bool) -> void:
	if _pool == null:
		return
	_pool.set_paused(paused)
	fader.set_effect_enabled(SndBus.MASTER, &"muffle", paused, 150)


# ------------------------------------------------------------------ per-frame feeds

func set_camera(focus: Vector3, basis: Basis, height: float) -> void:
	if not ready_ok:
		return
	if _attached and (listener == null or not is_instance_valid(listener)):
		_attached = false  # the view stage (and the listener parented under its camera) was freed at the end of the match: stand-in pose from here
	if _attached:
		listener.set_camera(focus, basis, height, _dt)
		loops.set_view(listener.focus, listener.zoom_scale)
	else:
		_pool.set_listener(focus, 1.0 / clampf(height / maxf(store.mix.ref_height_m, 1.0), store.mix.zoom_scale_min, store.mix.zoom_scale_max))
		loops.set_view(focus, 1.0)


func _ensure_bound(world: SimWorld) -> void:
	if world == _bound_world or _cfg == null:
		return
	_bound_world = world
	reader.bind(world, _cfg.local_pid, _cfg.observer or _cfg.replay)
	if bank == null:
		bank = SndSoundBank.new()
		bank.bake(world.data, map, store.mix)
	loops.setup(reader, bank, _pool, store.mix, map)
	bridge = SndSimBridge.new()
	bridge.setup(reader, bank, _pool, loops, meter, _announcer, countdown, scheduler, store.mix, map)
	bridge.responses = responses
	bridge.observer = _cfg.observer or _cfg.replay
	bridge.on_match_end = _on_bridge_match_end
	bridge.on_urgent = _on_bridge_urgent
	ambience.set_environment(_cfg.family, _cfg.biome)


func _on_bridge_match_end(result: int) -> void:
	if _match_active:
		end_match(result)


func _on_bridge_urgent() -> void:
	pass  # the meter's urgent flag carries it to the music in on_frame


## `batch` = the frame's `world.events.take()`; read-only, never retained.
func on_events(world: SimWorld, batch: PackedInt32Array, alpha: float) -> void:
	if not ready_ok or not _match_active or world == null:
		return
	_ensure_bound(world)
	bridge.zoom_scale = listener.zoom_scale if _attached else 1.0
	bridge.process(batch, alpha, now_ms())


func on_frame(world: SimWorld, alpha: float, dt: float) -> void:
	if not ready_ok or not _match_active or world == null:
		return
	_ensure_bound(world)
	var now: int = now_ms()
	bridge.run_scheduler(now)
	loops.update(dt, now)
	countdown.update(float(world.tick) + alpha, dt)
	meter.update(dt)
	var focus: Vector3 = listener.focus if _attached else _pool.listener_focus()
	var zoom: float = listener.zoom_scale if _attached else 1.0
	ambience.update(dt, focus, zoom, meter.far_heat)
	_drive_music(now)
	_low_power_left -= dt
	if _low_power_left <= 0.0:
		_low_power_left = LOW_POWER_POLL_S
		if not _cfg.observer and reader.power_low(_cfg.local_pid):
			_announcer.say(&"low_power")
		if not _cfg.observer:
			_poll_charge()


## Own superweapon charge hum (audio spec 5.12): pitch 0.8 + 0.4 * fraction, frozen and quieter during a power shortage.
func _poll_charge() -> void:
	var info: Dictionary = reader.superweapon_charge(_cfg.local_pid)
	var idx: int = int(info["def_idx"])
	if int(info["state"]) == 1 and idx >= 0 and bank != null and idx < bank.sw_name.size():
		countdown.set_charge(float(info["fraction"]), reader.power_low(_cfg.local_pid), bank.sw_name[idx])
	else:
		countdown.stop_charge()


func _drive_music(now: int) -> void:
	if _settings.music_mode == SndSettings.MUSIC_OFF:
		return
	var urgent: bool = meter.urgent
	var want: bool = meter.wants_combat(now)
	var st: int = _music.current_state()
	if _settings.music_mode == SndSettings.MUSIC_DYNAMIC:
		if want and st == SndMusicDirector.State.CALM:
			if _music.request_state(SndMusicDirector.State.COMBAT, urgent, now):
				_combat_since_ms = now
		elif not want and st == SndMusicDirector.State.COMBAT:
			_music.request_state(SndMusicDirector.State.CALM, false, now)
	var inten: float = clampf(0.2 + 1.5 * meter.intensity, 0.0, 0.75)
	if st == SndMusicDirector.State.COMBAT:
		inten = meter.intensity
		if now - _combat_since_ms < 10000:
			inten = maxf(inten, 0.55)
	_music.set_intensity(inten)


# ------------------------------------------------------------------ calls from UI / net / view

func ui(event_id: StringName, gain_db: float = 0.0) -> int:
	if not ready_ok:
		return 0
	return _pool.play(event_id, Vector3.ZERO, &"", gain_db)


func announce(line: StringName, priority: int = -1) -> bool:
	return ready_ok and _announcer.say(line, priority)


func _voice_class(def_idx: int, is_structure: bool) -> int:
	if bank == null:
		return SndUnits.VoiceClass.STRUCTURE if is_structure else SndUnits.VoiceClass.VEHICLE
	var p: SndProfileDef = bank.profile_of(SimEntity.Kind.STRUCTURE if is_structure else SimEntity.Kind.UNIT, def_idx)
	return p.voice_class if p != null else SndUnits.VoiceClass.VEHICLE


func unit_selected(def_idx: int, is_structure: bool, selection_count: int) -> void:
	if ready_ok and _match_active:
		responses.on_selected(_voice_class(def_idx, is_structure), is_structure, selection_count, now_ms())


func unit_ordered(order: int, def_idx: int) -> void:
	if ready_ok and _match_active:
		responses.on_order(order, _voice_class(def_idx, false), now_ms())


func order_denied(def_idx: int, is_structure: bool = false) -> void:
	if ready_ok and _match_active:
		responses.on_denied(_voice_class(def_idx, is_structure), now_ms())


func play_at(event_id: StringName, world_pos: Vector3, flavour: StringName = &"", gain_db: float = 0.0) -> int:
	return _pool.play(event_id, world_pos, flavour, gain_db) if ready_ok else 0


func stop_handle(handle: int, fade_ms: int = -1) -> void:
	if ready_ok:
		_pool.stop(handle, fade_ms)


# ------------------------------------------------------------------ settings

func apply_settings(s: SndSettings) -> void:
	_settings = s
	if not ready_ok and store == null:
		return
	var buses: Dictionary = {}
	for b: Variant in store.mix.buses:
		buses[str((b as Dictionary).get("name", ""))] = float((b as Dictionary).get("volume_db", 0.0))
	for slider: String in SndSettings.SLIDER_BUS:
		var bus: String = SndSettings.SLIDER_BUS[slider]
		var db: float = SndSettings.slider_to_db(s.slider_of(slider), float(buses.get(bus, 0.0)))
		if slider == "music" and s.music_mode == SndSettings.MUSIC_OFF:
			db = SndConfig.SILENT_DB
		fader.set_target_db(StringName(bus), db, 100)
	fader.set_effect_enabled(SndBus.MASTER, &"night", s.dynamic_range == SndSettings.DR_NIGHT, 100)
	store.mix.apply_quality(s.quality)
	if _announcer != null:
		_announcer.set_mode(s.announcer_mode)
		if s.announcer_tts and not _announcer.set_tts(true):
			audio_warning.emit(SndConfig.W_TTS, "no English text-to-speech voice available")
			s.announcer_tts = false
		elif not s.announcer_tts:
			_announcer.set_tts(false)
	if responses != null:
		responses.set_mode(s.unit_voice_mode)
	if _music != null and s.music_mode == SndSettings.MUSIC_OFF and _music.current_state() != SndMusicDirector.State.NONE:
		_music.stop(600)


func apply_values(values: Dictionary) -> void:
	var s: SndSettings = _settings.duplicate_settings()
	s.load_values(values)
	apply_settings(s)


func _duck_for_tts(on: bool) -> void:
	if fader != null:
		var buses: float = -6.0 if on else 0.0
		fader.set_target_db(SndBus.MUSIC, SndSettings.slider_to_db(_settings.music, -6.0) + buses, 150)


# ------------------------------------------------------------------ frame tick, focus

func _process(delta: float) -> void:
	if not ready_ok:
		return
	_dt = delta
	var now: int = now_ms()
	fader.update(delta)
	_pool.update(delta)
	_announcer.update(delta, now)
	_music.update(delta, now)
	if _match_loading and index.banks_ready():
		_finish_match_start()
	if not _attached and _world_root != null:
		_attach_left -= delta
		if _attach_left <= 0.0:
			attach_world(_world_root)
	var i: int = _deferred.size() - 1
	while i >= 0:
		if now >= int(_deferred[i]["at"]):
			_announcer.say(StringName(str(_deferred[i]["line"])), 100)
			_deferred.remove_at(i)
		i -= 1


func _notification(what: int) -> void:
	if not ready_ok or not _settings.mute_unfocused:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_muted_by_focus = true
		fader.set_target_db(SndBus.MASTER, SndConfig.SILENT_DB, 200)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _muted_by_focus:
		_muted_by_focus = false
		fader.set_target_db(SndBus.MASTER, SndSettings.slider_to_db(_settings.master, 0.0), 200)


func debug_snapshot() -> Dictionary:
	return {
		"voices_3d": _pool.active_3d() if _pool != null else 0,
		"voices_2d": _pool.active_2d() if _pool != null else 0,
		"music_state": _music.current_state() if _music != null else 0,
		"intensity": meter.intensity if meter != null else 0.0,
		"heat": meter.heat if meter != null else 0.0,
		"stems_db": _music.stem_levels_db() if _music != null else PackedFloat32Array(),
		"queue": _announcer.queue_size() if _announcer != null else 0,
		"counters": _pool.stats.counters if _pool != null else {},
		"loops": loops.active_loops() if loops != null else 0,
		"mode": mode,
	}
