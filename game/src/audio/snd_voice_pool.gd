class_name SndVoicePool
extends Node
## The only owner of the `AudioStreamPlayer*` nodes used for one-shot and looped SFX (audio spec 3.4 / 5.2): fixed pools,
## priority stealing with a reserve for important sounds, per-event and per-group limits, ramped volumes, handles with a
## generation. `virtual_mode` keeps the bookkeeping without creating players (fuzz tests, headless tools).

const INVALID: int = 0
const REGION_3D_END: int = SndConfig.POOL_3D_MAX  ## slots 0..87 are positional, 88..127 flat

class Slot:
	extends RefCounted
	var idx: int = 0
	var p3: AudioStreamPlayer3D = null
	var p2: AudioStreamPlayer = null
	var def: SndEventDef = null
	var handle: int = 0
	var gen: int = 0
	var busy: bool = false
	var fading: bool = false
	var counted: bool = false
	var start_ms: int = 0
	var end_ms: int = -1  ## virtual mode: when a one-shot ends (-1 = loops)
	var est_db: float = 0.0
	var gain_db: float = 0.0
	var vol_db: float = 0.0
	var ramp_from_db: float = 0.0
	var ramp_to_db: float = 0.0
	var ramp_t_ms: float = 0.0
	var ramp_dur_ms: float = 0.0
	var ramp_stop_at_end: bool = false
	var owner_tag: int = 0
	var world_pos: Vector3 = Vector3.ZERO
	var priority: int = 0

var stats: SndStats = SndStats.new()
var virtual_mode: bool = false

var _map: SndEventMap = null
var _cfg: SndMixConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: Callable = Callable()
var _slots: Array[Slot] = []
var _n3d: int = 0
var _n2d: int = 0
var _group_count: Dictionary = {}
var _focus: Vector3 = Vector3.ZERO
var _inv_scale: float = 1.0
var _gate_priority: int = 0
var _paused: bool = false
var _container: Node3D = null
var _active_3d: int = 0
var _active_2d: int = 0


func setup(map: SndEventMap, cfg: SndMixConfig, seed_value: int, clock: Callable) -> void:
	_map = map
	_cfg = cfg
	_rng.seed = seed_value
	_clock = clock
	for old: Slot in _slots:
		if old != null and old.p2 != null and is_instance_valid(old.p2):
			old.p2.queue_free()
	_slots.clear()
	_slots.resize(SndConfig.MAX_SLOTS)
	_group_count.clear()
	_active_2d = 0
	_active_3d = 0
	_n2d = mini(cfg.voices_2d, SndConfig.POOL_2D_MAX)
	for i: int in _n2d:
		var s: Slot = Slot.new()
		s.idx = REGION_3D_END + i
		if not virtual_mode:
			s.p2 = AudioStreamPlayer.new()
			s.p2.name = "v2d_%d" % i
			add_child(s.p2)
		_slots[s.idx] = s


## New match: stops every voice, clears counters and reseeds; the players stay.
func reset(seed_value: int) -> void:
	stop_all(0)
	stats.reset()
	_rng.seed = seed_value
	_group_count.clear()
	_gate_priority = 0
	_paused = false
	if _map != null:
		_map.reset_bookkeeping()


func attach_3d(container: Node3D, voices_3d: int) -> void:
	detach_3d()
	_container = container
	_n3d = clampi(voices_3d, 0, SndConfig.POOL_3D_MAX)
	for i: int in _n3d:
		var s: Slot = Slot.new()
		s.idx = i
		if not virtual_mode:
			s.p3 = AudioStreamPlayer3D.new()
			s.p3.name = "v3d_%d" % i
			s.p3.max_db = SndConfig.MAX_GAIN_DB
			container.add_child(s.p3)
		_slots[i] = s


func detach_3d() -> void:
	for i: int in REGION_3D_END:
		var s: Slot = _slots[i] if i < _slots.size() else null
		if s == null:
			continue
		if s.busy:
			_release(s)
		if s.p3 != null and is_instance_valid(s.p3):
			s.p3.queue_free()
		_slots[i] = null
	_n3d = 0
	_container = null


## Shutdown: stops everything and lets go of every stream.
func release_streams() -> void:
	stop_all(0)
	for s: Slot in _slots:
		if s == null:
			continue
		if s.p3 != null and is_instance_valid(s.p3):
			s.p3.stream = null
		if s.p2 != null and is_instance_valid(s.p2):
			s.p2.stream = null


func has_3d() -> bool:
	return _n3d > 0


func now_ms() -> int:
	return int(_clock.call()) if _clock.is_valid() else SndConfig.now_ms()


## Audio space: p' = focus + (p - focus) * inv_scale on x/z, height preserved (audio spec 5.3).
func set_listener(focus: Vector3, inv_scale: float) -> void:
	_focus = focus
	_inv_scale = inv_scale


func listener_focus() -> Vector3:
	return _focus


func to_audio_space(p: Vector3) -> Vector3:
	return Vector3(_focus.x + (p.x - _focus.x) * _inv_scale, p.y, _focus.z + (p.z - _focus.z) * _inv_scale)


func _listener_pos() -> Vector3:
	return Vector3(_focus.x, _cfg.listener_height_m if _cfg != null else 2.0, _focus.z)


static func model_db(def: SndEventDef, distance_m: float) -> float:
	var u: float = maxf(def.unit_size_m, 0.001)
	var d: float = maxf(distance_m, 1e-4 * u)
	var db: float = 0.0
	match def.attenuation:
		SndEventDef.Atten.INVERSE:
			db = -20.0 * log(d / u) / log(10.0)
		SndEventDef.Atten.INVERSE_SQUARE:
			db = -40.0 * log(d / u) / log(10.0)
		SndEventDef.Atten.LOGARITHMIC:
			db = -20.0 * log(d / u)
		_:
			db = 0.0
	return minf(db, SndConfig.MAX_GAIN_DB)


static func attenuation_db(def: SndEventDef, distance_m: float) -> float:
	var db: float = model_db(def, distance_m)
	if def.max_distance_m > 0.0:
		var w: float = maxf(1.0 - distance_m / def.max_distance_m, 0.0)
		db += 20.0 * log(maxf(w, 1e-6)) / log(10.0)
	return db


func estimate_db(def: SndEventDef, world_pos: Vector3, gain_db: float) -> float:
	var est: float = def.volume_db + gain_db
	if def.spatial == SndEventDef.Spatial.WORLD_3D:
		est += attenuation_db(def, to_audio_space(world_pos).distance_to(_listener_pos()))
	return est


func set_gate_priority(min_priority: int) -> void:
	_gate_priority = min_priority


func play(event_id: StringName, world_pos: Vector3 = Vector3.ZERO, flavour: StringName = &"", gain_db: float = 0.0) -> int:
	if _map == null:
		return INVALID
	var def: SndEventDef = _map.get_def(event_id)
	if def == null:
		stats.add(&"cull_unknown")
		return INVALID
	return play_def(def, world_pos, flavour, gain_db)


## Pipeline of audio spec 5.2. Any failure returns INVALID and increments one counter.
func play_def(def: SndEventDef, world_pos: Vector3, flavour: StringName, gain_db: float, pitch_mul: float = 1.0, owner_tag: int = 0, lowpass_hz: float = 0.0) -> int:
	if def == null:
		return INVALID
	var now: int = now_ms()
	if _gate_priority > 0 and def.priority < _gate_priority:
		stats.add(&"cull_gate")
		return INVALID
	if def.min_interval_ms > 0 and now - def.last_play_ms < def.min_interval_ms:
		stats.add(&"cull_interval")
		return INVALID
	var is3d: bool = def.spatial == SndEventDef.Spatial.WORLD_3D
	if is3d and _n3d == 0:
		stats.add(&"cull_no3d")
		return INVALID
	var est: float = def.volume_db + gain_db
	var apos: Vector3 = world_pos
	if is3d:
		apos = to_audio_space(world_pos)
		var d_eff: float = apos.distance_to(_listener_pos())
		if def.max_distance_m > 0.0 and d_eff > def.max_distance_m:
			stats.add(&"cull_distance")
			return INVALID
		est += attenuation_db(def, d_eff)
	if est < def.cull_below_db:
		stats.add(&"cull_level")
		return INVALID
	var score: float = float(def.priority) + 0.5 * est
	var slot: Slot = null
	if def.active_count >= def.max_instances:
		slot = _victim_in(def, is3d, false, now)
		if slot == null:
			stats.add(&"cull_limit")
			return INVALID
		stats.add(&"stolen")
	if slot == null and def.group != &"":
		if int(_group_count.get(def.group, 0)) >= _map.group_limit(def.group):
			slot = _victim_in(def, is3d, true, now)
			if slot == null:
				stats.add(&"cull_limit")
				return INVALID
			stats.add(&"stolen")
	if slot != null:
		_release(slot)
	else:
		slot = _find_slot(def, is3d, score, now)
		if slot == null:
			return INVALID
	return _begin(slot, def, world_pos, apos, flavour, gain_db, pitch_mul, owner_tag, est, lowpass_hz, now)


func _region_bounds(is3d: bool) -> Vector2i:
	return Vector2i(0, REGION_3D_END) if is3d else Vector2i(REGION_3D_END, REGION_3D_END + _n2d)


func _score_of(s: Slot, now: int) -> float:
	var age: float = float(now - s.start_ms) / 1000.0
	return float(s.def.priority) + 0.5 * s.est_db - age * _cfg.age_penalty_per_s


func _victim_in(def: SndEventDef, is3d: bool, by_group: bool, now: int) -> Slot:
	if def.steal == SndEventDef.Steal.NONE:
		return null
	var b: Vector2i = _region_bounds(is3d)
	var best: Slot = null
	var best_v: float = INF
	for i: int in range(b.x, b.y):
		var s: Slot = _slots[i]
		if s == null or not s.busy or s.fading:
			continue
		if by_group:
			if s.def.group != def.group:
				continue
		elif s.def != def:
			continue
		var v: float = float(s.start_ms) if def.steal == SndEventDef.Steal.OLDEST else _score_of(s, now)
		if v < best_v:
			best_v = v
			best = s
	return best


func _find_slot(def: SndEventDef, is3d: bool, score: float, now: int) -> Slot:
	var b: Vector2i = _region_bounds(is3d)
	var free_slot: Slot = null
	var fading_slot: Slot = null
	var free_count: int = 0
	var victim: Slot = null
	var victim_score: float = INF
	for i: int in range(b.x, b.y):
		var s: Slot = _slots[i]
		if s == null:
			continue
		if not s.busy:
			free_count += 1
			if free_slot == null:
				free_slot = s
		elif s.fading:
			free_count += 1
			if fading_slot == null:
				fading_slot = s
		else:
			var sc: float = _score_of(s, now)
			if sc < victim_score:
				victim_score = sc
				victim = s
	if free_count > 0 and (free_count > _cfg.reserve_high_slots or def.priority >= _cfg.reserve_high_priority):
		if free_slot != null:
			return free_slot
		if fading_slot != null:
			_release(fading_slot)
			return fading_slot
	if fading_slot != null and def.priority >= _cfg.reserve_high_priority:
		_release(fading_slot)
		return fading_slot
	if victim != null and score > victim_score + _cfg.steal_margin:
		stats.add(&"stolen")
		_release(victim)
		return victim
	stats.add(&"dropped")
	return null


func _begin(s: Slot, def: SndEventDef, world_pos: Vector3, apos: Vector3, flavour: StringName, gain_db: float, pitch_mul: float, owner_tag: int, est: float, lowpass_hz: float, now: int) -> int:
	var stream: AudioStream = def.pick_stream(_rng, flavour)
	if stream == null:
		stats.add(&"cull_nostream")
		return INVALID
	var jit: float = _rng.randf_range(-def.volume_jitter_db, def.volume_jitter_db) if def.volume_jitter_db > 0.0 else 0.0
	var pj: float = _rng.randf_range(-def.pitch_jitter_semitones, def.pitch_jitter_semitones) if def.pitch_jitter_semitones > 0.0 else 0.0
	var pitch: float = def.pitch * pitch_mul * pow(2.0, pj / 12.0)
	var target_db: float = def.volume_db + gain_db + jit
	s.def = def
	s.busy = true
	s.fading = false
	s.counted = true
	s.start_ms = now
	s.est_db = est
	s.gain_db = gain_db
	s.owner_tag = owner_tag
	s.world_pos = world_pos
	s.priority = def.priority
	s.gen = (s.gen % 0xFFFFFF) + 1
	s.handle = (s.gen << SndConfig.SLOT_BITS) | s.idx
	def.active_count += 1
	def.last_play_ms = now
	_group_count[def.group] = int(_group_count.get(def.group, 0)) + 1
	if s.idx < REGION_3D_END:
		_active_3d += 1
	else:
		_active_2d += 1
	if def.loop:
		s.vol_db = SndConfig.LOOP_START_DB
		_set_ramp(s, SndConfig.LOOP_START_DB, target_db, float(maxi(def.fade_in_ms, 1)), false)
		s.end_ms = -1
	else:
		s.vol_db = target_db
		s.ramp_dur_ms = 0.0
		s.end_ms = now + int(stream.get_length() * 1000.0 / maxf(pitch, 0.1)) + 20
	s.gain_db = gain_db
	if not virtual_mode:
		_configure_player(s, def, stream, apos, pitch, lowpass_hz)
	stats.started()
	return s.handle


func _configure_player(s: Slot, def: SndEventDef, stream: AudioStream, apos: Vector3, pitch: float, lowpass_hz: float) -> void:
	if s.idx < REGION_3D_END:
		var p: AudioStreamPlayer3D = s.p3
		p.stop()
		p.stream = stream
		p.bus = def.bus
		p.volume_db = s.vol_db
		p.pitch_scale = pitch
		p.unit_size = def.unit_size_m
		p.max_distance = def.max_distance_m
		p.attenuation_model = def.attenuation as AudioStreamPlayer3D.AttenuationModel
		p.attenuation_filter_cutoff_hz = lowpass_hz if lowpass_hz > 0.0 else def.lowpass_hz
		p.panning_strength = def.panning_strength
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP if def.doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.stream_paused = _paused
		if p.is_inside_tree():
			p.global_position = apos
		p.play()
	else:
		var q: AudioStreamPlayer = s.p2
		q.stop()
		q.stream = stream
		q.bus = def.bus
		q.volume_db = s.vol_db
		q.pitch_scale = pitch
		q.stream_paused = _paused
		q.play()


func _set_ramp(s: Slot, from_db: float, to_db: float, dur_ms: float, stop_at_end: bool) -> void:
	s.ramp_from_db = from_db
	s.ramp_to_db = to_db
	s.ramp_t_ms = 0.0
	s.ramp_dur_ms = dur_ms
	s.ramp_stop_at_end = stop_at_end


func _release(s: Slot) -> void:
	if not s.busy:
		return
	if s.counted and s.def != null:
		s.def.active_count = maxi(s.def.active_count - 1, 0)
		_group_count[s.def.group] = maxi(int(_group_count.get(s.def.group, 0)) - 1, 0)
	s.counted = false
	if s.idx < REGION_3D_END:
		_active_3d = maxi(_active_3d - 1, 0)
		if s.p3 != null:
			s.p3.stop()
	else:
		_active_2d = maxi(_active_2d - 1, 0)
		if s.p2 != null:
			s.p2.stop()
	s.busy = false
	s.fading = false
	s.handle = 0
	s.def = null
	s.owner_tag = 0
	s.ramp_dur_ms = 0.0


func _slot_of(handle: int) -> Slot:
	if handle <= 0:
		return null
	var i: int = handle & (SndConfig.MAX_SLOTS - 1)
	var s: Slot = _slots[i]
	return s if s != null and s.busy and s.handle == handle else null


func is_active(handle: int) -> bool:
	return _slot_of(handle) != null


func def_of(handle: int) -> SndEventDef:
	var s: Slot = _slot_of(handle)
	return s.def if s != null else null


func stop(handle: int, fade_ms: int = -1) -> void:
	var s: Slot = _slot_of(handle)
	if s == null:
		return
	var f: int = s.def.fade_out_ms if fade_ms < 0 else fade_ms
	if f <= 0:
		_release(s)
		return
	_start_fade(s, f)


func _start_fade(s: Slot, fade_ms: int) -> void:
	if s.fading:
		return
	s.fading = true
	if s.counted and s.def != null:
		s.def.active_count = maxi(s.def.active_count - 1, 0)
		_group_count[s.def.group] = maxi(int(_group_count.get(s.def.group, 0)) - 1, 0)
		s.counted = false
	_set_ramp(s, s.vol_db, SndConfig.SILENT_DB, float(maxi(fade_ms, 1)), true)


func stop_all(fade_ms: int = 100) -> void:
	for s: Slot in _slots:
		if s != null and s.busy:
			if fade_ms <= 0:
				_release(s)
			else:
				_start_fade(s, fade_ms)


func stop_by_tag(tag: int, fade_ms: int = -1) -> void:
	if tag == 0:
		return
	for s: Slot in _slots:
		if s != null and s.busy and s.owner_tag == tag:
			stop(s.handle, fade_ms)


func set_position(handle: int, world_pos: Vector3) -> void:
	var s: Slot = _slot_of(handle)
	if s == null:
		return
	s.world_pos = world_pos
	if s.p3 != null and s.p3.is_inside_tree():
		s.p3.global_position = to_audio_space(world_pos)


func set_gain_db(handle: int, gain_db: float) -> void:
	var s: Slot = _slot_of(handle)
	if s == null or s.fading:
		return
	var target: float = s.def.volume_db + gain_db
	_set_ramp(s, s.vol_db, target, 60.0, false)
	s.gain_db = gain_db


func set_pitch(handle: int, pitch_scale: float) -> void:
	var s: Slot = _slot_of(handle)
	if s == null:
		return
	var p: float = maxf(pitch_scale, 0.05)
	if s.p3 != null:
		s.p3.pitch_scale = p
	elif s.p2 != null:
		s.p2.pitch_scale = p


func set_paused(paused: bool) -> void:
	_paused = paused
	for s: Slot in _slots:
		if s != null and s.busy:
			if s.p3 != null:
				s.p3.stream_paused = paused
			if s.p2 != null:
				s.p2.stream_paused = paused


func active_count() -> int:
	return _active_3d + _active_2d


func active_3d() -> int:
	return _active_3d


func active_2d() -> int:
	return _active_2d


func busy_count() -> int:
	var n: int = 0
	for s: Slot in _slots:
		if s != null and s.busy:
			n += 1
	return n


func group_count(group: StringName) -> int:
	return int(_group_count.get(group, 0))


func snapshot_3d() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in mini(_n3d, _slots.size()):
		var s: Slot = _slots[i]
		if s != null and s.busy:
			out.append({"busy": true, "priority": s.priority, "est_db": s.est_db, "event": s.def.id if s.def != null else &""})
	return out


## Advances ramps, retires finished voices. Call once per rendered frame.
func update(dt: float) -> void:
	var now: int = now_ms()
	var step_ms: float = dt * 1000.0
	for s: Slot in _slots:
		if s == null or not s.busy:
			continue
		if s.ramp_dur_ms > 0.0:
			s.ramp_t_ms += step_ms
			var f: float = clampf(s.ramp_t_ms / s.ramp_dur_ms, 0.0, 1.0)
			var v: float = lerpf(s.ramp_from_db, s.ramp_to_db, f)
			v = clampf(v, s.vol_db - SndConfig.RAMP_MAX_STEP_DB_PER_FRAME, s.vol_db + SndConfig.RAMP_MAX_STEP_DB_PER_FRAME)
			s.vol_db = v
			if s.p3 != null:
				s.p3.volume_db = v
			elif s.p2 != null:
				s.p2.volume_db = v
			if f >= 1.0 and is_equal_approx(v, s.ramp_to_db):
				s.ramp_dur_ms = 0.0
				if s.ramp_stop_at_end:
					_release(s)
					continue
		if _paused:
			continue
		if virtual_mode:
			if s.end_ms >= 0 and now >= s.end_ms:
				_release(s)
		else:
			var playing: bool = s.p3.playing if s.p3 != null else (s.p2.playing if s.p2 != null else false)
			if not playing and now - s.start_ms > 30:
				_release(s)
