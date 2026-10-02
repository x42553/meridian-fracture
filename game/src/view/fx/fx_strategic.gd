class_name FxStrategic
extends RefCounted
## Zones, warnings, support powers and the 8 superweapon sequences (render spec 5.9.5-5.9.7). Called by FxEventRouter (which owns the
## gating helpers); geometry the events do not carry comes from the sim's queryable records: SimZone (zone shapes and lifetimes, warning
## markers are zones of kind ZK_WARNING) and SimWarning (exec tick, angle, launcher). Per-superweapon parameters live in
## `fx.json -> mappings.superweapons[<power key>]` (shape, radius, timing, effect ids), zone effect ids in `mappings.zones[<kind>]`.
## Presentation only; strategic events are global (never fog gated), zone effects follow the zone's own visibility rule.

const ZK_WARNING: int = 20
const ZE_CANCELLED: int = 2
const TICK_S: float = 0.05
const M_PER_UNIT: float = 3.0 / 1024.0
const TAU_PER_BAT: float = TAU / 4096.0

var stat_zone_loops: int = 0
var stat_warnings: int = 0

var _zone_loops: Dictionary = {}  # zone id -> Array[int] emitter handles
var _zone_handles: Dictionary = {}  # zone id -> Array[int] super-effect handles (cancel on ZE_CANCELLED)
var _warn_handles: Dictionary = {}  # warning id -> Array[int]
var _last_sw: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])  # x, y, tick, radius of the last drawn strategic impact


func setup(_r: FxEventRouter) -> void:
	pass


func _sw_cfg(r: FxEventRouter, key: StringName) -> Dictionary:
	var m: Variant = r.fx.recipe_book().mappings.get("superweapons", {})
	if m is Dictionary:
		return (m as Dictionary).get(String(key), {}) as Dictionary
	return {}


func _zone_cfg(r: FxEventRouter, kind: int) -> Dictionary:
	var m: Variant = r.fx.recipe_book().mappings.get("zones", {})
	if m is Dictionary:
		return (m as Dictionary).get(str(kind), {}) as Dictionary
	return {}


# ---------------------------------------------------------------------------------------------- zones
## EV_ZONE_SPAWNED: x, y . b zone id . c zone kind . d owner pid
func on_zone_spawned(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	if r.sim.zones == null:
		return
	var zid: int = ev[o + 5]
	var kind: int = ev[o + 6]
	var z: SimZone = r.sim.zones.get_zone(zid)
	if z == null:
		return
	if not r.v.observer and r.v.local_pid >= 0 and not r.sim.zones.visible_to(z, r.v.local_pid):
		return
	if kind == ZK_WARNING:
		_warning_marker(r, z)
		return
	if not r.v.observer and z.team != r.sim.team_of(r.v.local_pid) and not r.allowed(z.x, z.y):
		return
	var cfg: Dictionary = _zone_cfg(r, kind)
	if cfg.is_empty():
		return
	var dur: float = clampf(float(z.t_end - r.sim.tick) * TICK_S, 0.5, 120.0)
	var handles: Array = []
	var centres: Array[Vector3] = _zone_centres(r, z)
	var rad: float = _zone_radius_m(z, centres.size())
	var burst: StringName = StringName(str(cfg.get("burst", "")))
	var tick_id: StringName = StringName(str(cfg.get("tick", "")))
	var interval: float = float(cfg.get("interval", 0.5))
	for c: Vector3 in centres:
		r.spawn(burst, c, Vector3.ZERO, rad)
		if tick_id != &"":
			handles.append(r.fx.start_loop(tick_id, c, Vector3.ZERO, rad, interval, dur, 0.15))
			stat_zone_loops += 1
	if kind == DefEnums.ZoneKind.INTERCEPT:
		var cfg2: Dictionary = _sw_cfg(r, &"trident_interception_array")
		var c0: Vector3 = centres[0]
		r.spawn(StringName(str(cfg2.get("dome", "sw_intercept_dome"))), c0, Vector3.ZERO, rad)
		handles.append(r.fx.start_loop(&"sw_intercept_pulse", c0, Vector3.ZERO, rad, 3.0, dur, 0.0))
	if not handles.is_empty():
		_zone_loops[zid] = handles


func _zone_centres(r: FxEventRouter, z: SimZone) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if z.shape == DefEnums.ZoneShape.LINE:
		var a: Vector3 = r.gpos(z.ax, z.ay)
		var b: Vector3 = r.gpos(z.bx, z.by)
		var len_m: float = a.distance_to(b)
		var half_w: float = float(z.radius) * M_PER_UNIT
		var n: int = clampi(int(ceil(len_m / maxf(half_w * 1.8, 1.0))), 1, 6)
		for i: int in n:
			var t: float = (float(i) + 0.5) / float(n)
			var p: Vector3 = a.lerp(b, t)
			p.y = r.v.ground_at(p.x, p.z)
			out.append(p)
	else:
		out.append(r.gpos(z.x, z.y))
	return out


func _zone_radius_m(z: SimZone, n_centres: int) -> float:
	var rad: float = float(z.radius) * M_PER_UNIT
	if z.shape == DefEnums.ZoneShape.LINE and n_centres > 1:
		rad *= 1.15
	return maxf(rad, 1.0)


## EV_ZONE_ENDED: b zone id . c reason
func on_zone_ended(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var zid: int = ev[o + 5]
	for h: Variant in _zone_loops.get(zid, []) as Array:
		r.fx.stop_emitter(h as int)
	_zone_loops.erase(zid)
	if ev[o + 6] == ZE_CANCELLED:
		for h2: Variant in _zone_handles.get(zid, []) as Array:
			r.fx.cancel(h2 as int)
	_zone_handles.erase(zid)


## A warning marker (superweapon or warned power): ring + beacon per disc; capsules get a disc chain. Cancelled with the zone.
func _warning_marker(r: FxEventRouter, z: SimZone) -> void:
	if not r.warnings_enabled:
		return
	var dur: float = maxf(float(z.t_warn_end - r.sim.tick) * TICK_S, 1.0)
	var handles: Array = []
	var rad: float = maxf(float(z.radius) * M_PER_UNIT, 1.5)
	var centres: Array[Vector3] = []
	if z.shape == DefEnums.ZoneShape.LINE:
		var a: Vector3 = r.gpos(z.ax, z.ay)
		var b: Vector3 = r.gpos(z.bx, z.by)
		var n: int = clampi(int(ceil(a.distance_to(b) / (rad * 1.9))) + 1, 2, 6)
		for i: int in n:
			var p: Vector3 = a.lerp(b, float(i) / float(n - 1))
			p.y = r.v.ground_at(p.x, p.z)
			centres.append(p)
	else:
		centres.append(r.gpos(z.x, z.y))
	for c: Vector3 in centres:
		var h: int = r.spawn(&"sw_warning_marker", c, Vector3(dur, 0.0, 0.0), rad)
		if h > 0:
			handles.append(h)
	stat_warnings += 1
	if not handles.is_empty():
		_zone_handles[z.id] = handles


# ---------------------------------------------------------------------------------------------- warnings and superweapons
## EVT_WARNING: x, y . a warning id . b owner . c WK_* . d source idx (superweapon idx for WK_SUPER)
func on_warning(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	if ev[o + 6] != SimEconConst.WK_SUPER or r.sim.strategic == null:
		return
	var wid: int = ev[o + 4]
	var wr: SimWarning = r.sim.strategic.get_warning(wid)
	if wr == null:
		return
	var key: StringName = r.v.defs.superweapon_key(ev[o + 7])
	var cfg: Dictionary = _sw_cfg(r, key)
	if cfg.is_empty():
		return
	var dur: float = maxf(float(wr.exec_tick - r.sim.tick) * TICK_S, 0.1)
	var ang: float = float(wr.angle) * TAU_PER_BAT
	var centre: Vector3 = r.gpos((wr.x + wr.x2) / 2 if wr.width > 0 else wr.x, (wr.y + wr.y2) / 2 if wr.width > 0 else wr.y)
	var pre: StringName = StringName(str(cfg.get("pre", "")))
	var handles: Array = []
	match String(key):
		"atlas_kinetic_array", "horizon_mass_driver":
			handles.append(r.spawn(pre, centre, Vector3(dur, 0.0, ang), 1.0))
		"aurora_microwave_array":
			var lp: Vector3 = _launcher_pos(r, wr, centre)
			var charge: float = float(cfg.get("charge_s", 1.0))
			r.spawn_later(maxf(dur - charge, 0.0), pre, lp, Vector3(charge, 0.0, 0.0), 5.0)
		"helios_reflector":
			var start: Vector3 = r.gpos(wr.x, wr.y)
			var aim: float = float(cfg.get("aim_s", 1.0))
			r.spawn_later(maxf(dur - aim, 0.0), pre, start, Vector3(aim, 0.0, 0.0), 1.0)
		"perun_missile_complex":
			var map_c: Vector3 = Vector3(float(r.sim.map.w) * 1.5, 0.0, float(r.sim.map.h) * 1.5)
			var dir: Vector3 = (centre - map_c)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 1.0 else Vector3.LEFT
			var streak: float = float(cfg.get("streak_s", 1.2))
			var from: Vector3 = centre + dir * float(cfg.get("edge_m", 140.0)) + Vector3(0.0, float(cfg.get("sky_m", 90.0)), 0.0)
			r.spawn_later(maxf(dur - streak, 0.0), pre, from, centre, streak)
	var live: Array = []
	for h: Variant in handles:
		if (h as int) > 0:
			live.append(h)
	if not live.is_empty():
		_warn_handles[wid] = live


func _launcher_pos(r: FxEventRouter, wr: SimWarning, fallback: Vector3) -> Vector3:
	var ve: ViewEntity = r.v.entity_view(wr.launcher_id)
	if ve != null:
		return Vector3(ve.wx, ve.wy, ve.wz)
	return fallback


## EVT_SW_CANCELLED: a pid . b sw idx . c cause . d warning id
func on_sw_cancelled(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var wid: int = ev[o + 7]
	for h: Variant in _warn_handles.get(wid, []) as Array:
		r.fx.cancel(h as int)
	_warn_handles.erase(wid)


func on_sw_exec(_r: FxEventRouter, _ev: PackedInt32Array, _o: int) -> void:
	pass  # the sequences run on their own timelines (warning composites, EVT_SW_IMPACT, EV_SWEEP)


func on_sw_done(_r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	_warn_handles.erase(ev[o + 4])


## EVT_SW_IMPACT: x, y . a source idx . b, c position . d radius units . e damage type
func on_sw_impact(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var tick: int = ev[o + 1]
	if _last_sw[0] == x and _last_sw[1] == y and absi(_last_sw[2] - tick) <= 1 and _last_sw[3] == ev[o + 7]:
		return  # emit_packet + the scheduler can both announce one packet
	_last_sw[0] = x
	_last_sw[1] = y
	_last_sw[2] = tick
	_last_sw[3] = ev[o + 7]
	var key: StringName = r.v.defs.superweapon_key(ev[o + 4])
	var cfg: Dictionary = _sw_cfg(r, key)
	var rad_m: float = float(ev[o + 7]) * M_PER_UNIT
	var p: Vector3 = r.gpos(x, y)
	match String(key):
		"atlas_kinetic_array":
			r.spawn(StringName(str(cfg.get("impact", "sw_atlas_impact"))), p, Vector3.ZERO, maxf(rad_m / 6.0, 0.5))
		"aurora_microwave_array":
			r.spawn(StringName(str(cfg.get("impact", "sw_microwave_dome"))), p, Vector3(4.5, 0.0, 0.0), maxf(rad_m / 24.0, 0.3))
		"perun_missile_complex":
			var core_max: float = float(cfg.get("core_max_m", 12.0))
			if rad_m <= core_max:
				r.spawn(StringName(str(cfg.get("core", "sw_perun_core"))), p, Vector3.ZERO, maxf(rad_m / 9.0, 0.4))
			else:
				r.spawn(StringName(str(cfg.get("wave", "sw_perun_wave"))), p, Vector3.ZERO, maxf(rad_m / 21.0, 0.4))
		"horizon_mass_driver":
			r.spawn(StringName(str(cfg.get("impact", "sw_horizon_impact"))), p, Vector3.ZERO, maxf(rad_m / 9.0, 0.4))
		"helios_reflector", "tempest_swarm_hub", "dragonfall_field_foundry", "trident_interception_array":
			pass  # sweeps, swarms, engines and the dome have their own events
		_:
			r.spawn(&"expl_strategic_large", p, Vector3.ZERO, maxf(rad_m, 3.0))


## EV_SWEEP (Helios): x, y = A . a serial . b warhead . c duration | delay << 16 . d width . e, f = B. The hot spot travels A -> B.
func on_sweep(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var c: int = ev[o + 6]
	var dur_s: float = float(c & 0xFFFF) * TICK_S
	var delay_s: float = float((c >> 16) & 0xFFFF) * TICK_S
	var cfg: Dictionary = _sw_cfg(r, &"helios_reflector")
	var a: Vector3 = r.gpos(ev[o + 2], ev[o + 3])
	var b: Vector3 = r.gpos(ev[o + 8], ev[o + 9])
	var sky: float = float(cfg.get("sky_m", 80.0))
	var tick_id: StringName = StringName(str(cfg.get("tick", "beam_helios_tick")))
	var fxm: FxManager = r.fx
	var vw: ViewWorld = r.v
	var t_start: float = fxm.now() + delay_s
	var spot_cb: Callable = func() -> Vector3:
		var u: float = clampf((fxm.now() - t_start) / maxf(dur_s, 0.1), 0.0, 1.0)
		var p: Vector3 = a.lerp(b, u)
		p.y = vw.ground_at(p.x, p.z)
		return p
	var sky_cb: Callable = func() -> Vector3:
		return (spot_cb.call() as Vector3) + Vector3(0.0, sky, 0.0)
	var start_it: Callable = func() -> void:
		fxm.start_tracker(tick_id, sky_cb, spot_cb, 0.07, dur_s, 1.0)
	if delay_s > 0.02:
		fxm.schedule_call(delay_s, start_it)
	else:
		start_it.call()


## EV_SWARM_LAUNCHED (Tempest): x, y = hub . b, c = target
func on_swarm(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var cfg: Dictionary = _sw_cfg(r, &"tempest_swarm_hub")
	r.spawn(StringName(str(cfg.get("launch", "sw_tempest_launch"))), r.gpos(ev[o + 2], ev[o + 3]), Vector3.ZERO, 1.0)


## EV_ENGINE_ASSEMBLED (Dragonfall): x, y . a engine . b capsule
func on_engine(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var cfg: Dictionary = _sw_cfg(r, &"dragonfall_field_foundry")
	r.spawn(StringName(str(cfg.get("assemble", "sw_assemble_burst"))), r.gpos(ev[o + 2], ev[o + 3]), Vector3.ZERO, 1.0)


## EV_SUMMONED: x, y . a entity . b parent . c SM_* flags
func on_summoned(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var id: int = ev[o + 4]
	if not r.allowed(x, y, id):
		return
	var ve: ViewEntity = r.v.entity_view(id)
	var flags: int = ev[o + 6]
	var p: Vector3 = Vector3(ve.wx, ve.wy, ve.wz) if ve != null else r.gpos(x, y)
	if (flags & SimZoneConsts.SM_DECOY) != 0:
		r.spawn(&"decoy_spawn", p + Vector3(0.0, 0.6, 0.0), Vector3.ZERO, 1.0)
		return
	if ve != null and String(ve.recipe_id).contains("dragonfall_capsule"):
		var cfg: Dictionary = _sw_cfg(r, &"dragonfall_field_foundry")
		r.spawn(StringName(str(cfg.get("capsule", "sw_dragonfall_capsule"))), r.gpos(x, y), Vector3.ZERO, 1.0)
		return
	var s: float = clampf((ve.radius_m if ve != null else 1.5) * 1.3, 1.5, 6.0)
	r.spawn(&"summon_arrive", p, Vector3.ZERO, s / 3.0)


## EV_MARKED: a entity . b 1 marked / 0 cleared (Counterbattery mark)
func on_marked(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	if ev[o + 5] != 1:
		return
	var ve: ViewEntity = r.v.entity_view(ev[o + 4])
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE:
		return
	r.spawn(&"power_mark_ring", Vector3(ve.wx, ve.wy, ve.wz), Vector3.ZERO, clampf(ve.radius_m * 1.3 / 1.6, 0.8, 3.0))


## EV_BUFF_APPLIED: x, y . b power idx . c entity count . d pid (area buff cast feedback)
func on_buff(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if x == 0 and y == 0 or not r.allowed(x, y):
		return
	r.spawn(&"power_cast_ring", r.gpos(x, y), Vector3.ZERO, 6.0)


## EVT_POWER_ACTIVATED: a pid . b slot . c def idx . d, e position . f angle. Slot 3 is the superweapon (the warning already ran).
func on_power_used(r: FxEventRouter, ev: PackedInt32Array, o: int) -> void:
	if ev[o + 5] >= SimEconConst.SLOT_SW:
		return
	var x: int = ev[o + 5 + 2]
	var y: int = ev[o + 5 + 3]
	if x <= 0 and y <= 0:
		return
	r.spawn(&"power_cast_ring", r.gpos(x, y), Vector3.ZERO, 5.0)
