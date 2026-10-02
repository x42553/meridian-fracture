class_name SndVoicePool
extends Node
## Fixed pool of positional (AudioStreamPlayer3D) and non-positional (AudioStreamPlayer) voices.
## An RTS emits hundreds of sound requests per second; nodes-per-unit does not scale. All requests go through play(),
## which culls by distance / audibility / rate, enforces per-event and per-group limits, and steals the least
## important voice when the pool is full. Presentation-only: uses its own RandomNumberGenerator (never SimRng).

const INVALID: int = -1
## Godot clamps 3D attenuation at AudioStreamPlayer3D.max_db (default +3 dB).
const MAX_GAIN_DB: float = 3.0

class Slot extends RefCounted:
	var p3: AudioStreamPlayer3D = null
	var p2: AudioStreamPlayer = null
	var def: SndEventDef = null
	var handle: int = 0
	var start_ms: int = 0
	var est_db: float = -80.0
	var busy: bool = false

	func playing() -> bool:
		return p3.playing if p3 != null else p2.playing

	func halt() -> void:
		if p3 != null:
			p3.stop()
		else:
			p2.stop()

## The camera controller sets this every frame to the ground point under the screen centre.
var listener_pos: Vector3 = Vector3.ZERO
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var stats: Dictionary = {"played": 0, "cull_distance": 0, "cull_audibility": 0, "cull_interval": 0, "cull_limit": 0, "stolen": 0, "dropped": 0}

var _map: SndEventMap
var _listener: AudioListener3D
var _slots3: Array[Slot] = []
var _slots2: Array[Slot] = []
var _by_handle: Dictionary = {}
var _group_count: Dictionary = {}
var _next_handle: int = 1


## Call once after adding the pool to the tree. The viewport MUST also contain a current Camera3D: verified on 4.7.2 that
## AudioStreamPlayer3D is silent with an AudioListener3D alone; with a camera present the listener overrides the camera transform.
func setup(map: SndEventMap, voices_3d: int = 48, voices_2d: int = 16, seed_value: int = 1) -> void:
	_map = map
	rng.seed = seed_value
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()
	for i in voices_3d:
		var s: Slot = Slot.new()
		s.p3 = AudioStreamPlayer3D.new()
		add_child(s.p3)
		_slots3.append(s)
	for i in voices_2d:
		var s2: Slot = Slot.new()
		s2.p2 = AudioStreamPlayer.new()
		add_child(s2.p2)
		_slots2.append(s2)


## Total level change (dB) at `distance`: model curve (clamped at +3 dB) plus the linear fade-to-silence window that Godot
## applies up to max_distance. Both terms verified against the engine in tests/t_capture.gd (within 0.7 dB).
static func attenuation_db(def: SndEventDef, distance: float) -> float:
	var db: float = model_db(def, distance)
	if def.max_distance > 0.0:
		db += linear_to_db(maxf(1.0 - distance / def.max_distance, 0.0))
	return db


## Pure distance-model term (no max_distance window).
static func model_db(def: SndEventDef, distance: float) -> float:
	var ratio: float = maxf(distance / def.unit_size, 0.0001)
	var att: float = 0.0
	match def.attenuation:
		AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE:
			att = linear_to_db(1.0 / ratio)
		AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE:
			att = linear_to_db(1.0 / (ratio * ratio))
		AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC:
			att = -20.0 * log(ratio)
	return minf(att, MAX_GAIN_DB)


## Requests an event. Returns a handle (>0) or INVALID when culled/dropped. Loops must be stopped with stop().
func play(event_id: StringName, pos: Vector3 = Vector3.ZERO, variant: StringName = &"", gain_db: float = 0.0) -> int:
	var def: SndEventDef = _map.get_def(event_id, variant)
	if def == null:
		return INVALID
	var now: int = Time.get_ticks_msec()
	if def.min_interval_ms > 0 and now - def.last_play_ms < def.min_interval_ms:
		stats["cull_interval"] += 1
		return INVALID
	var is3d: bool = def.spatial == SndEventDef.Spatial.WORLD_3D
	var est: float = def.volume_db + gain_db
	if is3d:
		var dist: float = listener_pos.distance_to(pos)
		if def.max_distance > 0.0 and dist > def.max_distance:
			stats["cull_distance"] += 1
			return INVALID
		est += attenuation_db(def, dist)
		if est < def.cull_below_db:
			stats["cull_audibility"] += 1
			return INVALID
	var slot: Slot = _slot_for(def, is3d, est, now)
	if slot == null:
		return INVALID
	_start(slot, def, pos, gain_db, est, now, is3d)
	return slot.handle


func stop(handle: int) -> void:
	var slot: Slot = _by_handle.get(handle, null)
	if slot != null:
		slot.halt()
		_release(slot)


func set_position(handle: int, pos: Vector3) -> void:
	var slot: Slot = _by_handle.get(handle, null)
	if slot != null and slot.p3 != null:
		slot.p3.global_position = pos


func active_voices() -> int:
	var n: int = 0
	for s: Slot in _slots3:
		n += 1 if s.busy else 0
	for s: Slot in _slots2:
		n += 1 if s.busy else 0
	return n


## Compact state for debug overlays: [{busy, priority, est_db}] for the 3D slots.
func snapshot_3d() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Slot in _slots3:
		out.append({"busy": s.busy, "priority": s.def.priority if s.busy else 0, "est_db": s.est_db})
	return out


func _process(_delta: float) -> void:
	for s: Slot in _slots3:
		if s.busy and not s.playing():
			_release(s)
	for s: Slot in _slots2:
		if s.busy and not s.playing():
			_release(s)


func _slot_for(def: SndEventDef, is3d: bool, est: float, now: int) -> Slot:
	var pool: Array[Slot] = _slots3 if is3d else _slots2
	# 1. per-event and per-group instance limits (may steal from the same bucket only)
	if def.active_count >= def.max_instances:
		var v: Slot = _victim(pool, def, def.id, &"", est)
		if v == null:
			stats["cull_limit"] += 1
			return null
		_release(v, true)
	if def.group != &"" and int(_group_count.get(def.group, 0)) >= _map.group_limit(def.group):
		var vg: Slot = _victim(pool, def, &"", def.group, est)
		if vg == null:
			stats["cull_limit"] += 1
			return null
		_release(vg, true)
	# 2. a free slot
	for s: Slot in pool:
		if not s.busy:
			return s
	# 3. pool exhausted: steal the globally least important voice if we outrank it
	var victim: Slot = _victim(pool, def, &"", &"", est)
	if victim == null:
		stats["dropped"] += 1
		return null
	_release(victim, true)
	return victim


## Least-important busy slot (optionally restricted to an event id / group) that the newcomer may steal from.
func _victim(pool: Array[Slot], newcomer: SndEventDef, only_event: StringName, only_group: StringName, est: float) -> Slot:
	if newcomer.steal == SndEventDef.Steal.NONE:
		return null
	var now: int = Time.get_ticks_msec()
	var new_score: float = float(newcomer.priority) + est * 0.5
	var best: Slot = null
	var best_score: float = INF
	for s: Slot in pool:
		if not s.busy:
			continue
		if only_event != &"" and s.def.id != only_event:
			continue
		if only_group != &"" and s.def.group != only_group:
			continue
		var sc: float
		if newcomer.steal == SndEventDef.Steal.OLDEST:
			sc = float(s.start_ms)
		else:
			sc = float(s.def.priority) + s.est_db * 0.5 - float(now - s.start_ms) * 0.001
		if sc < best_score:
			best_score = sc
			best = s
	if best == null:
		return null
	if only_event == &"" and only_group == &"":
		var victim_score: float = float(best.def.priority) + best.est_db * 0.5 - float(now - best.start_ms) * 0.001
		if new_score <= victim_score + 1.0:
			return null
	return best


func _start(slot: Slot, def: SndEventDef, pos: Vector3, gain_db: float, est: float, now: int, is3d: bool) -> void:
	var v: int = def.pick_variant(rng)
	var vol: float = def.volume_db + gain_db + rng.randf_range(-def.volume_jitter_db, def.volume_jitter_db)
	var pitch_scale: float = def.pitch * pow(2.0, rng.randf_range(-def.pitch_jitter_semitones, def.pitch_jitter_semitones) / 12.0)
	slot.def = def
	slot.handle = _next_handle
	_next_handle += 1
	slot.start_ms = now
	slot.est_db = est
	slot.busy = true
	_by_handle[slot.handle] = slot
	def.active_count += 1
	def.last_play_ms = now
	if def.group != &"":
		_group_count[def.group] = int(_group_count.get(def.group, 0)) + 1
	if is3d:
		var p: AudioStreamPlayer3D = slot.p3
		p.stop()
		p.stream = def.streams[v]
		p.bus = def.bus
		p.volume_db = vol
		p.pitch_scale = pitch_scale
		p.unit_size = def.unit_size
		p.max_distance = def.max_distance
		p.attenuation_model = def.attenuation
		p.attenuation_filter_cutoff_hz = def.lowpass_hz
		p.panning_strength = def.panning_strength
		p.global_position = pos
		p.play()
	else:
		var p2: AudioStreamPlayer = slot.p2
		p2.stop()
		p2.stream = def.streams[v]
		p2.bus = def.bus
		p2.volume_db = vol
		p2.pitch_scale = pitch_scale
		p2.play()
	stats["played"] += 1


func _release(slot: Slot, stolen: bool = false) -> void:
	if not slot.busy:
		return
	slot.busy = false
	_by_handle.erase(slot.handle)
	slot.def.active_count = maxi(0, slot.def.active_count - 1)
	if slot.def.group != &"":
		_group_count[slot.def.group] = maxi(0, int(_group_count.get(slot.def.group, 0)) - 1)
	if stolen:
		stats["stolen"] += 1
		slot.halt()
