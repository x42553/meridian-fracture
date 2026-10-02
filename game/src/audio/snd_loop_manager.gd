class_name SndLoopManager
extends RefCounted
## Entity-bound and effect loops (audio spec 5.6 / 3.7): engines, rotors, structure hums chosen by audibility and a
## budget, beam loops, projectile path voices, repair / salvage loops bound to an entity, timed superweapon loops.
## Positions chase the latest sim position with a 60 ms time constant (no previous position exists in the sim).

const TAU_POS_S: float = 0.06
const TAU_PITCH_S: float = 0.3

class Rec:
	extends RefCounted
	var key: int = 0
	var entity_id: int = 0
	var def: SndEventDef = null
	var handle: int = 0
	var cur: Vector3 = Vector3.ZERO
	var speed: float = 0.0
	var pitch: float = 1.0
	var base_pitch: float = 1.0
	var pitch_speed: bool = false
	var vmax: float = 1.0
	var gain_db: float = 0.0
	var flavour: StringName = &""

var reader: SndWorldReader = null
var bank: SndSoundBank = null
var pool: SndVoicePool = null
var mix: SndMixConfig = null
var map: SndEventMap = null
var stats: SndStats = SndStats.new()

var _ent: Dictionary = {}  ## key (entity id * 8 + loop index) -> Rec
var _beam: Dictionary = {}  ## shooter * 32 + arch -> Rec
var _path: Dictionary = {}  ## projectile serial -> {handle, from, to, start_ms, dur_ms}
var _bound: Dictionary = {}  ## key -> Rec
var _timed: Array[Dictionary] = []
var _focus: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _scan_left: float = 0.0
var _ids: PackedInt32Array = PackedInt32Array()


func setup(p_reader: SndWorldReader, p_bank: SndSoundBank, p_pool: SndVoicePool, p_mix: SndMixConfig, p_map: SndEventMap) -> void:
	reader = p_reader
	bank = p_bank
	pool = p_pool
	mix = p_mix
	map = p_map


func set_view(focus: Vector3, zoom_scale: float) -> void:
	_focus = focus
	_zoom = zoom_scale


func active_loops() -> int:
	return _ent.size()


func beam_count() -> int:
	return _beam.size()


func path_count() -> int:
	return _path.size()


func clear() -> void:
	for k: Variant in _ent.keys():
		pool.stop((_ent[k] as Rec).handle, 0)
	for k2: Variant in _beam.keys():
		pool.stop((_beam[k2] as Rec).handle, 0)
	for k3: Variant in _path.keys():
		pool.stop(int((_path[k3] as Dictionary)["handle"]), 0)
	for k4: Variant in _bound.keys():
		pool.stop((_bound[k4] as Rec).handle, 0)
	for t: Dictionary in _timed:
		pool.stop(int(t["handle"]), 0)
	_ent.clear()
	_beam.clear()
	_path.clear()
	_bound.clear()
	_timed.clear()


# ------------------------------------------------------------------ per-frame

func update(dt: float, now_ms: int) -> void:
	if reader == null or not reader.is_bound():
		return
	_scan_left -= dt
	if _scan_left <= 0.0:
		_scan_left = mix.loops_scan_period_s
		_scan()
	_follow(_ent, dt)
	_follow(_bound, dt)
	_follow_beams(dt)
	_update_paths(now_ms)
	_update_timed(now_ms)


func _follow(dict: Dictionary, dt: float) -> void:
	var dead: Array = []
	var a: float = 1.0 - exp(-dt / TAU_POS_S)
	var ap: float = 1.0 - exp(-dt / TAU_PITCH_S)
	for k: Variant in dict.keys():
		var r: Rec = dict[k]
		var e: SimEntity = reader.entity(r.entity_id)
		if e == null or (e.flags & SimFlags.F_GONE) != 0 or not pool.is_active(r.handle):
			dead.append(k)
			continue
		var h: float = mix.source_height_air_m if e.layer == SimEntity.Layer.AIR else mix.source_height_ground_m
		var tgt: Vector3 = SndUnits.to_world(e.x, e.y, h)
		var prev: Vector3 = r.cur
		r.cur = r.cur + (tgt - r.cur) * a
		pool.set_position(r.handle, r.cur)
		if r.pitch_speed and dt > 0.0:
			var sp: float = Vector2(r.cur.x - prev.x, r.cur.z - prev.z).length() / dt
			r.speed += (sp - r.speed) * ap
			var target_pitch: float = r.base_pitch * lerpf(mix.loops_pitch_lo, mix.loops_pitch_hi, clampf(r.speed / maxf(r.vmax, 0.1), 0.0, 1.0))
			r.pitch += (target_pitch - r.pitch) * ap
			pool.set_pitch(r.handle, r.pitch)
	for k2: Variant in dead:
		var rr: Rec = dict[k2]
		pool.stop(rr.handle)
		dict.erase(k2)


func _follow_beams(dt: float) -> void:
	var a: float = 1.0 - exp(-dt / TAU_POS_S)
	var dead: Array = []
	for k: Variant in _beam.keys():
		var r: Rec = _beam[k]
		var e: SimEntity = reader.entity(r.entity_id)
		if e == null or (e.flags & SimFlags.F_GONE) != 0 or not pool.is_active(r.handle):
			dead.append(k)
			continue
		var tgt: Vector3 = SndUnits.to_world(e.x, e.y, mix.source_height_ground_m)
		r.cur = r.cur + (tgt - r.cur) * a
		pool.set_position(r.handle, r.cur)
	for k2: Variant in dead:
		pool.stop((_beam[k2] as Rec).handle)
		_beam.erase(k2)


func _update_paths(now_ms: int) -> void:
	var done: Array = []
	for k: Variant in _path.keys():
		var p: Dictionary = _path[k]
		var h: int = int(p["handle"])
		if not pool.is_active(h):
			done.append(k)
			continue
		var f: float = clampf(float(now_ms - int(p["start_ms"])) / maxf(float(p["dur_ms"]), 1.0), 0.0, 1.0)
		pool.set_position(h, (p["from"] as Vector3).lerp(p["to"], f))
		if f >= 1.0:
			pool.stop(h, 60)
			done.append(k)
	for k2: Variant in done:
		_path.erase(k2)


func _update_timed(now_ms: int) -> void:
	var i: int = _timed.size() - 1
	while i >= 0:
		var t: Dictionary = _timed[i]
		if now_ms >= int(t["end_ms"]) or not pool.is_active(int(t["handle"])):
			pool.stop(int(t["handle"]))
			_timed.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ entity loops

func _when_ok(when: int, e: SimEntity) -> bool:
	match when:
		SndProfileDef.When.ALWAYS:
			return true
		SndProfileDef.When.MOVING:
			return (e.flags & SimFlags.F_MOVING) != 0
		SndProfileDef.When.AIRBORNE:
			return (e.flags & SimFlags.F_AIRBORNE) != 0
		SndProfileDef.When.STRUCTURE_ACTIVE:
			return (e.flags & SimFlags.F_POWERED) != 0 and (e.flags & (SimFlags.F_SELLING | SimFlags.F_UNDER_CONSTRUCTION)) == 0
	return false


func _scan() -> void:
	var fx: int = int(_focus.x / SndConfig.M_PER_UNIT)
	var fy: int = int(_focus.z / SndConfig.M_PER_UNIT)
	var radius: int = int(mix.loops_radius_m * _zoom / SndConfig.M_PER_UNIT)
	var n: int = reader.query_radius(fx, fy, radius, _ids)
	var keys: Array = []
	var scores: Dictionary = {}
	var recs: Dictionary = {}
	var limit: int = mini(n, mix.loops_max_candidates)
	for i: int in limit:
		var e: SimEntity = reader.entity(_ids[i])
		if e == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
			continue
		var prof: SndProfileDef = bank.profile_of(e.kind, e.def_idx)
		if prof == null or prof.loops.is_empty():
			continue
		var visible_checked: bool = false
		var visible: bool = true
		for li: int in prof.loops.size():
			var ld: Dictionary = prof.loops[li]
			if not _when_ok(int(ld["when"]), e):
				continue
			if not visible_checked:
				visible = reader.entity_visible(e)
				visible_checked = true
			if not visible:
				break
			var def: SndEventDef = map.get_def(ld["event"])
			if def == null:
				continue
			var key: int = e.id * 8 + li
			var h: float = mix.source_height_air_m if e.layer == SimEntity.Layer.AIR else mix.source_height_ground_m
			var pos: Vector3 = SndUnits.to_world(e.x, e.y, h)
			var est: float = pool.estimate_db(def, pos, float(ld["gain_db"]))
			if est < def.cull_below_db:
				continue
			var score: float = float(def.priority) + 0.5 * est
			if _ent.has(key):
				score += mix.loops_hysteresis_db * 0.5
			keys.append(key)
			scores[key] = score
			recs[key] = [e, ld, def, pos]
	keys.sort_custom(func(a: int, b: int) -> bool:
		var sa: float = scores[a]
		var sb: float = scores[b]
		if sa != sb:
			return sa > sb
		return a < b)
	var keep: Dictionary = {}
	for k: int in keys:
		if keep.size() >= mix.loops_budget:
			break
		keep[k] = true
	for k2: Variant in _ent.keys():
		if not keep.has(k2):
			pool.stop((_ent[k2] as Rec).handle)
			_ent.erase(k2)
	for k3: Variant in keep.keys():
		if _ent.has(k3):
			continue
		var d: Array = recs[k3]
		_start_entity_loop(int(k3), d[0], d[1], d[2], d[3])


func _start_entity_loop(key: int, e: SimEntity, ld: Dictionary, def: SndEventDef, pos: Vector3) -> void:
	var rec: Rec = Rec.new()
	rec.key = key
	rec.entity_id = e.id
	rec.def = def
	rec.cur = pos
	rec.pitch_speed = bool(ld["pitch_speed"])
	rec.gain_db = float(ld["gain_db"])
	rec.base_pitch = 1.0 + float((e.id * 37) % 21 - 10) * 0.004
	rec.pitch = rec.base_pitch
	rec.flavour = &""
	var sp: int = bank.unit_speed[e.def_idx] if e.kind == SimEntity.Kind.UNIT and e.def_idx < bank.unit_speed.size() else 0
	rec.vmax = maxf(float(sp) * 20.0 * SndConfig.M_PER_UNIT, 0.5)
	rec.handle = pool.play_def(def, pos, rec.flavour, rec.gain_db, rec.base_pitch, key)
	if rec.handle != 0:
		_ent[key] = rec
		stats.started()
	else:
		stats.add(&"cull_loop")


# ------------------------------------------------------------------ bound loops (repair, salvage)

func bind_loop(key: int, entity_id: int, def: SndEventDef, flavour: StringName) -> void:
	if def == null or _bound.has(key):
		return
	var e: SimEntity = reader.entity(entity_id)
	if e == null:
		return
	var rec: Rec = Rec.new()
	rec.key = key
	rec.entity_id = entity_id
	rec.def = def
	rec.cur = SndUnits.to_world(e.x, e.y, mix.source_height_ground_m)
	rec.flavour = flavour
	rec.handle = pool.play_def(def, rec.cur, flavour, 0.0, 1.0, key)
	if rec.handle != 0:
		_bound[key] = rec


func unbind_loop(key: int) -> void:
	if _bound.has(key):
		pool.stop((_bound[key] as Rec).handle)
		_bound.erase(key)


# ------------------------------------------------------------------ beams

func start_beam(shooter_id: int, weapon_idx: int, start_def: SndEventDef, flavour: StringName) -> void:
	var key: int = shooter_id * 32 + weapon_idx
	if _beam.has(key):
		return
	var e: SimEntity = reader.entity(shooter_id)
	if e == null:
		return
	var pos: Vector3 = SndUnits.to_world(e.x, e.y, mix.source_height_ground_m)
	pool.play_def(start_def, pos, flavour, 0.0)
	var loop_def: SndEventDef = map.get_def(start_def.link_loop) if start_def.link_loop != &"" else null
	if loop_def == null:
		return
	var rec: Rec = Rec.new()
	rec.key = key
	rec.entity_id = shooter_id
	rec.def = loop_def
	rec.cur = pos
	rec.flavour = flavour
	rec.handle = pool.play_def(loop_def, pos, flavour, 0.0, 1.0, key)
	if rec.handle != 0:
		rec.gain_db = 0.0
		_beam[key] = rec
		rec.pitch = float(weapon_idx)  # remembers the weapon for the end tail
		rec.base_pitch = 1.0


func stop_beam(shooter_id: int, weapon_idx: int) -> void:
	var key: int = shooter_id * 32 + weapon_idx
	if not _beam.has(key):
		return
	var rec: Rec = _beam[key]
	_beam.erase(key)
	pool.stop(rec.handle, 200)
	var start_def: SndEventDef = bank.fire_def(weapon_idx, "")
	if start_def != null and start_def.link_end != &"":
		var end_def: SndEventDef = map.get_def(start_def.link_end)
		if end_def != null:
			pool.play_def(end_def, rec.cur, rec.flavour, 0.0)


func stop_beams_of(shooter_id: int) -> void:
	var keys: Array = []
	for k: Variant in _beam.keys():
		if int(k) / 32 == shooter_id:
			keys.append(k)
	for k2: Variant in keys:
		stop_beam(shooter_id, int(k2) % 32)


# ------------------------------------------------------------------ path voices, timed loops

func add_path_voice(key: int, def: SndEventDef, from: Vector3, to: Vector3, start_ms: int, duration_ms: int, flavour: StringName, gain_db: float) -> void:
	if def == null or _path.size() >= 24:
		return
	var h: int = pool.play_def(def, from, flavour, gain_db)
	if h != 0:
		_path[key] = {"handle": h, "from": from, "to": to, "start_ms": start_ms, "dur_ms": maxi(duration_ms, 50)}


func remove_path_voice(key: int, fade_ms: int) -> void:
	if not _path.has(key):
		return
	pool.stop(int((_path[key] as Dictionary)["handle"]), fade_ms)
	_path.erase(key)


## A loop that stops by itself after `duration_ms` (superweapon effect loops).
func play_timed_loop(def: SndEventDef, pos: Vector3, duration_ms: int, tag: int) -> void:
	if def == null:
		return
	var h: int = pool.play_def(def, pos, &"", 0.0, 1.0, tag)
	if h != 0:
		_timed.append({"handle": h, "end_ms": pool.now_ms() + duration_ms})
