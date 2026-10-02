class_name SimSuperweapons
extends RefCounted
## Superweapons (economy 5.19 / 5.21; task EC3B, E8): the per-player charge machine of slot 3, launch validation and
## activation, the warning record and its cancellation rules, the execution hand-off to SimPowerFx.apply_superweapon
## (the compiled timelines of global.json live in DefSuperweapon; AB3 turns them into strikes, sweeps, zones and summons),
## the EVT_SW_IMPACT schedule and `danger_fraction_bp` (AI dodge helper). Stateless; state lives in SimPlayerEcon.slots,
## SimStrategicSystem.warnings / sched.
##
## Charge machine: NONE -> (launcher ACTIVE) CHARGING charge 0 ("starts empty") -> READY after `recharge_t` powered ticks.
## `charge_ok` = powered(pid) and every prerequisite structure present (Radar, Laboratory: "intact", not "online") and the
## launcher ACTIVE and not EMP-shut-down. Activation restarts the full recharge at once and creates a WARNING record; the
## attack executes when the warning ends. A launcher destroyed, sold or EMP-shut-down during the WARNING phase cancels the
## attack without refund; after that nothing cancels it.

const CAUSE_DESTROYED: int = 1
const CAUSE_SHUTDOWN: int = 2
const CAUSE_SOLD: int = 3


# ---- geometry of the compiled superweapons -----------------------------------------------------------------------------

## Line targets (Atlas, Helios, Horizon) take an angle; the others are areas.
static func is_line(sw: DefSuperweapon) -> bool:
	return sw.action_kind == DefEnums.SwAction.KINETIC_VOLLEY or sw.action_kind == DefEnums.SwAction.BEAM_SWEEP \
			or sw.action_kind == DefEnums.SwAction.RAIL_STRIKE


## Half the length of the line (units): the packet offsets of Atlas / Horizon, half the beam line of Helios.
static func half_len(sw: DefSuperweapon) -> int:
	if sw.action_kind == DefEnums.SwAction.BEAM_SWEEP:
		return int(sw.params.get("line_len_u", 0)) / 2
	var m: int = 0
	for pk: DefImpactPacket in sw.packets:
		m = maxi(m, absi(pk.offset_x))
	return m


## Radius of the warning zone (units): the impact circle, the beam half-width, or the area radius (Perun: the ring's).
static func zone_radius(sw: DefSuperweapon) -> int:
	match sw.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.RAIL_STRIKE:
			return sw.packets[0].radius if not sw.packets.is_empty() else 0
		DefEnums.SwAction.BEAM_SWEEP:
			return int(sw.params.get("width_u", 3072)) / 2
		DefEnums.SwAction.BUNKER_BUSTER:
			var m: int = 0
			for pk: DefImpactPacket in sw.packets:
				m = maxi(m, pk.radius)
			return m
	return sw.radius


## Ticks between the start of the execution and its last effect (upper bound for the swarm).
static func exec_span(sw: DefSuperweapon) -> int:
	match sw.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.RAIL_STRIKE, DefEnums.SwAction.BUNKER_BUSTER:
			var m: int = 0
			for pk: DefImpactPacket in sw.packets:
				m = maxi(m, pk.delay_t)
			return m
		DefEnums.SwAction.BEAM_SWEEP:
			return int(sw.params.get("traverse_t", 240))
		DefEnums.SwAction.DRONE_SWARM:
			return SimZoneConsts.SWARM_HARD_CAP_TICKS
		DefEnums.SwAction.ENGINE_DROP:
			return int(sw.params.get("unfold_t", 100)) + SimZoneConsts.ENGINE_LIFE_TICKS
		DefEnums.SwAction.INTERCEPT_ZONE:
			return sw.duration_t
	return 0


## Warning geometry [x, y, x2, y2, radius, width, angle]: a capsule (start, end, radius = half width, width > 0) for lines,
## a circle (centre; x2, y2 = launcher for the swarm approach line, else the centre; width 0) for areas.
static func geometry(sw: DefSuperweapon, tx: int, ty: int, angle: int, hub_x: int, hub_y: int) -> PackedInt32Array:
	var r: int = zone_radius(sw)
	if is_line(sw):
		var h: int = half_len(sw)
		var dx: int = Fp.mul_q16(h, Fp.cos(angle))
		var dy: int = Fp.mul_q16(h, Fp.sin(angle))
		return PackedInt32Array([tx - dx, ty - dy, tx + dx, ty + dy, r, 2 * r, angle])
	if sw.action_kind == DefEnums.SwAction.DRONE_SWARM:
		return PackedInt32Array([tx, ty, hub_x, hub_y, r, 0, angle])
	return PackedInt32Array([tx, ty, tx, ty, r, 0, angle])


static func line_len(w: SimWarning) -> int:
	return Fp.dist(w.x2 - w.x, w.y2 - w.y)


## true when (x, y) is inside the warning zone grown by `margin` units.
static func in_zone(w: SimWarning, x: int, y: int, margin: int) -> bool:
	if w.width > 0:
		return SimShape.capsule_contains(w.x, w.y, w.x2, w.y2, w.radius + margin, x, y)
	return SimShape.circle_contains(w.x, w.y, w.radius + margin, x, y)


## Bit p = player p sees the zone (economy 5.16): the owner and its team, every player owning a non-decoy entity inside the
## zone grown by 3 cells; the Trident dome is visible to everybody. Fog and decoys never change it.
static func affected_mask(world: SimWorld, w: SimWarning) -> int:
	var m: int = 0
	var trident: bool = false
	if w.kind == SimEconConst.WK_SUPER and w.src_idx >= 0 and w.src_idx < world.data.superweapons.size():
		trident = world.data.superweapons[w.src_idx].action_kind == DefEnums.SwAction.INTERCEPT_ZONE
	var team: int = world.team_of(w.owner)
	for p: SimPlayer in world.players:
		if p.controller == SimPlayer.Controller.NONE:
			continue
		if trident or p.team == team:
			m |= 1 << p.pid
	if trident:
		return m
	var cands: PackedInt32Array = PackedInt32Array()
	var margin: int = SimStrategicSystem.MARGIN_U
	if w.width > 0:
		SimShape.query_shape(world, SimShape.SHAPE_CAPSULE, w.x, w.y, w.x2, w.y2, w.radius + margin, cands)
	else:
		SimShape.query_shape(world, SimShape.SHAPE_DISC, w.x, w.y, w.x, w.y, w.radius + margin, cands)
	for id: int in cands:
		var e: SimEntity = world.by_id[id]
		if e != null and e.owner >= 0 and (e.flags & SimFlags.F_DECOY) == 0 and (e.kind == SimEntity.Kind.UNIT or e.kind == SimEntity.Kind.STRUCTURE):
			m |= 1 << e.owner
	return m


# ---- launchers and the charge machine --------------------------------------------------------------------------------

## The ACTIVE launcher of superweapon `w_idx` owned by pid (lowest entity id), null when there is none.
static func launcher_of(world: SimWorld, pid: int, w_idx: int) -> SimEntity:
	for e: SimEntity in world.structures_of(pid):
		if (e.flags & SimFlags.F_GONE) != 0 or e.econ == null or e.econ.st != SimEconConst.ST_ACTIVE:
			continue
		if world.data.structures[e.def_idx].superweapon == w_idx:
			return e
	return null


## Prerequisites of the superweapon other than the launcher itself (Radar, Laboratory): present and ACTIVE.
static func prereqs_ok(pe: SimPlayerEcon, w: DefSuperweapon) -> bool:
	var mask: int = w.requires_mask
	if w.launcher >= 0:
		mask &= ~(1 << w.launcher)
	return SimStrategicSystem.prereqs_present(pe, mask)


static func charge_ok(world: SimWorld, pid: int, pe: SimPlayerEcon, w: DefSuperweapon, launcher: SimEntity) -> bool:
	return world.power.powered(pid) and prereqs_ok(pe, w) and launcher.econ.shutdown_until <= world.tick


## Stage-4 step of slot 3 for one player. Called before the scheduler runs, so a launcher lost this tick cancels its warning.
static func step(world: SimWorld, sys: SimStrategicSystem, p: SimPlayer, pe: SimPlayerEcon) -> void:
	var s: SimPowerSlot = pe.slots[SimEconConst.SLOT_SW]
	if s.def_idx < 0 or (pe.flags & SimEconConst.PF_SUPERWEAPONS_OFF) != 0 or p.eliminated != 0:
		return
	var w: DefSuperweapon = world.data.superweapons[s.def_idx]
	var tick: int = world.tick
	if s.sw_state == SimEconConst.SW_NONE:
		var found: SimEntity = launcher_of(world, p.pid, s.def_idx)
		if found != null:
			s.sw_state = SimEconConst.SW_CHARGING
			s.launcher_id = found.id
			s.recharge_ticks = w.recharge_t
			s.charge = 0
			if w.starts_charged:
				s.charge = w.recharge_t
				s.sw_state = SimEconConst.SW_READY
				world.emit(SimEconConst.EVT_SW_READY, found.x, found.y, p.pid)
		return
	var le: SimEntity = world.get_entity(s.launcher_id)
	if le == null or (le.flags & SimFlags.F_GONE) != 0 or le.owner != p.pid or le.econ == null or le.econ.st != SimEconConst.ST_ACTIVE:
		var cause: int = CAUSE_SOLD if (le != null and le.econ != null and (le.econ.st == SimEconConst.ST_SELLING or (le.flags & SimFlags.F_SELLING) != 0)) else CAUSE_DESTROYED
		launcher_lost(world, sys, p.pid, s, cause)
		return
	if le.econ.shutdown_until > tick:
		cancel_for_launcher(world, sys, p.pid, le.id, CAUSE_SHUTDOWN)
	if s.sw_state == SimEconConst.SW_CHARGING and s.last_activation_tick != tick:
		if charge_ok(world, p.pid, pe, w, le):
			s.charge += 1
			if s.charge >= s.recharge_ticks:
				s.charge = s.recharge_ticks
				s.sw_state = SimEconConst.SW_READY
				world.emit(SimEconConst.EVT_SW_READY, le.x, le.y, p.pid)


## The launcher is gone: its WARNING attacks are cancelled (no refund) and the slot falls back to NONE (charge lost).
static func launcher_lost(world: SimWorld, sys: SimStrategicSystem, pid: int, s: SimPowerSlot, cause: int) -> void:
	cancel_for_launcher(world, sys, pid, s.launcher_id, cause)
	s.sw_state = SimEconConst.SW_NONE
	s.launcher_id = 0
	s.charge = 0


static func cancel_for_launcher(world: SimWorld, sys: SimStrategicSystem, pid: int, lid: int, cause: int) -> void:
	for w: SimWarning in sys.warnings:
		if w.owner == pid and w.launcher_id == lid and w.kind == SimEconConst.WK_SUPER and w.phase == SimEconConst.AT_WARNING:
			sys.cancel_warning(world, w, cause)


# ---- launch --------------------------------------------------------------------------------------------------------

static func can_launch(world: SimWorld, pid: int, tx: int, ty: int, angle: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	var s: SimPowerSlot = pe.slots[SimEconConst.SLOT_SW]
	if (pe.flags & SimEconConst.PF_SUPERWEAPONS_OFF) != 0 or s.def_idx < 0:
		return SimEconConst.RSN_FEATURE_OFF
	if s.sw_state == SimEconConst.SW_NONE:
		return SimEconConst.RSN_NO_LAUNCHER
	if s.sw_state != SimEconConst.SW_READY:
		return SimEconConst.RSN_NOT_CHARGED
	var le: SimEntity = world.get_entity(s.launcher_id)
	if le == null or (le.flags & SimFlags.F_GONE) != 0 or le.econ == null or le.econ.st != SimEconConst.ST_ACTIVE:
		return SimEconConst.RSN_NO_LAUNCHER
	if le.econ.shutdown_until > world.tick:
		return SimEconConst.RSN_NO_POWER
	var w: DefSuperweapon = world.data.superweapons[s.def_idx]
	if not prereqs_ok(pe, w):
		return SimEconConst.RSN_PREREQ
	var cx: int = tx >> 10
	var cy: int = ty >> 10
	if tx < 0 or ty < 0 or not world.map.in_bounds(cx, cy):
		return SimEconConst.RSN_TERRAIN
	if w.target_vision == DefEnums.TargetVision.EXPLORED and not world.cell_explored(pid, cx, cy):
		return SimEconConst.RSN_NOT_EXPLORED
	if w.target_vision == DefEnums.TargetVision.CURRENT and not world.cell_visible(pid, cx, cy):
		return SimEconConst.RSN_NO_VISION
	if angle < 0 or angle > Fp.ANGLE_MASK:
		return SimEconConst.RSN_BAD_TARGET
	return SimEconConst.RSN_OK


## CMD_LAUNCH_SUPERWEAPON: validates, restarts the full recharge, opens the warning. RSN_*.
static func launch(world: SimWorld, sys: SimStrategicSystem, pid: int, x: int, y: int, angle: int) -> int:
	var r: int = can_launch(world, pid, x, y, angle)
	if r != SimEconConst.RSN_OK:
		return r
	var pe: SimPlayerEcon = world.players[pid].econ
	var s: SimPowerSlot = pe.slots[SimEconConst.SLOT_SW]
	var w: DefSuperweapon = world.data.superweapons[s.def_idx]
	var le: SimEntity = world.get_entity(s.launcher_id)
	var a: int = angle if is_line(w) else 0
	s.sw_state = SimEconConst.SW_CHARGING
	s.charge = 0
	s.recharge_ticks = w.recharge_t
	s.last_activation_tick = world.tick
	sys.stat_launches += 1
	world.emit(SimEconConst.EVT_POWER_ACTIVATED, x, y, pid, SimEconConst.SLOT_SW, s.def_idx, x, y, angle)
	var aux: int = world.rng.next_u32() & 0x7FFFFFFF  # the ONE draw of this launch (Dragonfall capsule angles)
	var geom: PackedInt32Array = geometry(w, x, y, a, le.x, le.y)
	var wr: SimWarning = sys.add_warning(world, SimEconConst.WK_SUPER, s.def_idx, pid, le.id, geom, w.warning_t, exec_span(w))
	s.pending_attack = wr.id
	sys.schedule(wr.exec_tick, SimEconConst.SK_WARNING_END, pid, s.def_idx, wr.id, x, y, 0, aux, a)
	return SimEconConst.RSN_OK


## SK_WARNING_END: the warning ended. A launcher that is no longer functional cancels (defensive; step() catches it first);
## otherwise the attack executes. Support-power warnings (Counterbattery, Tremor, Counterlaunch, Wideband Scan) only change
## phase: their shells / scan were already scheduled in the primitives at activation.
static func warning_end(world: SimWorld, sys: SimStrategicSystem, rec: SimScheduled) -> void:
	var wr: SimWarning = sys.get_warning(rec.attack_id)
	if wr == null or wr.phase != SimEconConst.AT_WARNING:
		return
	var kind_id: int = wr.src_idx if wr.kind == SimEconConst.WK_SUPER else 100 + wr.src_idx
	if wr.kind == SimEconConst.WK_SUPER:
		var le: SimEntity = world.get_entity(wr.launcher_id)
		if le == null or (le.flags & SimFlags.F_GONE) != 0 or le.econ == null or le.econ.st != SimEconConst.ST_ACTIVE:
			sys.cancel_warning(world, wr, CAUSE_DESTROYED)
			return
		if le.econ.shutdown_until > world.tick:
			sys.cancel_warning(world, wr, CAUSE_SHUTDOWN)
			return
	wr.phase = SimEconConst.AT_EXEC
	world.emit(SimEconConst.EVT_SW_EXEC_START, wr.x, wr.y, wr.owner, kind_id, wr.id)
	if wr.kind == SimEconConst.WK_SUPER:
		execute(world, sys, wr, rec)
	sys.schedule(maxi(wr.end_tick, world.tick + 1), SimStrategicSystem.SK_DONE, wr.owner, wr.src_idx, wr.id)


## Hands the compiled timeline to SimPowerFx.apply_superweapon and books the EVT_SW_IMPACT records.
static func execute(world: SimWorld, sys: SimStrategicSystem, wr: SimWarning, rec: SimScheduled) -> void:
	var sw: DefSuperweapon = world.data.superweapons[wr.src_idx]
	var le: SimEntity = world.get_entity(wr.launcher_id)
	var hub_x: int = le.x if le != null else wr.x2
	var hub_y: int = le.y if le != null else wr.y2
	var owner_eid: int = wr.launcher_id if le != null else 0
	var res: int = SimPowerFx.apply_superweapon(world, wr.src_idx, wr.owner, rec.x, rec.y, rec.b, hub_x, hub_y, rec.a, owner_eid)
	if res != SimZoneConsts.PW_OK:
		Log.error("strategic", "superweapon %s: apply_superweapon returned %d" % [sw.id, res])
	var now: int = world.tick
	match sw.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.BUNKER_BUSTER, DefEnums.SwAction.EMP_BURST, DefEnums.SwAction.RAIL_STRIKE:
			for pk: DefImpactPacket in sw.packets:
				var px: int = rec.x + Fp.rot_x(pk.offset_x, 0, rec.b)
				var py: int = rec.y + Fp.rot_y(pk.offset_x, 0, rec.b)
				sys.schedule(now + pk.delay_t, SimEconConst.SK_PACKET, wr.owner, wr.src_idx, wr.id, px, py, pk.radius, pk.dtype)
		DefEnums.SwAction.BEAM_SWEEP:
			sys.schedule(now, SimEconConst.SK_PACKET, wr.owner, wr.src_idx, wr.id, rec.x, rec.y, zone_radius(sw), sw.packets[0].dtype)
		DefEnums.SwAction.INTERCEPT_ZONE:
			sys.schedule(now, SimEconConst.SK_PACKET, wr.owner, wr.src_idx, wr.id, rec.x, rec.y, sw.radius, 0)


# ---- danger (AI dodge helper) ----------------------------------------------------------------------------------------

static func _falloff_bp(d: int, r: int, edge_bp: int) -> int:
	if r <= 0 or d > r:
		return 0
	return 10000 - (10000 - edge_bp) * d / r


## 0..10000 estimate of the fraction of one full hit that a unit standing at (x, y) would take if it stayed until tick `t`.
## Uses the compiled geometry and timings only (no RNG). Packets count once their impact tick is <= t; a full hit is the
## strongest packet at its centre; the Helios sweep counts the pulses that cross the point against the ~9 a centreline
## point receives; swarm / engines return a flat estimate inside their area once they have arrived.
static func danger_fraction_bp(world: SimWorld, wr: SimWarning, x: int, y: int, t: int) -> int:
	if wr.kind != SimEconConst.WK_SUPER or wr.phase == SimEconConst.AT_CANCELLED or wr.src_idx < 0 or wr.src_idx >= world.data.superweapons.size():
		return 0
	var sw: DefSuperweapon = world.data.superweapons[wr.src_idx]
	var ex: int = wr.exec_tick
	var cx: int = wr.x
	var cy: int = wr.y
	if wr.width > 0:
		cx = (wr.x + wr.x2) / 2
		cy = (wr.y + wr.y2) / 2
	match sw.action_kind:
		DefEnums.SwAction.KINETIC_VOLLEY, DefEnums.SwAction.BUNKER_BUSTER, DefEnums.SwAction.RAIL_STRIKE:
			var best: int = 1
			for pk: DefImpactPacket in sw.packets:
				best = maxi(best, pk.damage)
			var sum: int = 0
			for pk2: DefImpactPacket in sw.packets:
				if ex + pk2.delay_t > t:
					continue
				var px: int = cx + Fp.rot_x(pk2.offset_x, 0, wr.angle)
				var py: int = cy + Fp.rot_y(pk2.offset_x, 0, wr.angle)
				sum += pk2.damage * _falloff_bp(Fp.dist(x - px, y - py), pk2.radius, pk2.edge_bp) / best
			return mini(sum, 10000)
		DefEnums.SwAction.EMP_BURST:
			return 10000 if (t >= ex and SimShape.circle_contains(cx, cy, sw.radius, x, y)) else 0
		DefEnums.SwAction.BEAM_SWEEP:
			return _beam_danger(sw, wr, x, y, t)
		DefEnums.SwAction.DRONE_SWARM:
			return 6000 if (t >= ex and SimShape.circle_contains(cx, cy, sw.radius + SimZoneConsts.SWARM_MARGIN_U, x, y)) else 0
		DefEnums.SwAction.ENGINE_DROP:
			var unfold: int = int(sw.params.get("unfold_t", 100))
			return 4000 if (t >= ex + unfold and SimShape.circle_contains(cx, cy, sw.radius + SimZoneConsts.ENGINE_NEAR_STRUCT_U, x, y)) else 0
	return 0


static func _beam_danger(sw: DefSuperweapon, wr: SimWarning, x: int, y: int, t: int) -> int:
	var traverse: int = maxi(int(sw.params.get("traverse_t", 240)), 1)
	var every: int = maxi(int(sw.params.get("hit_every_t", 5)), 1)
	var len_u: int = maxi(int(sw.params.get("line_len_u", 1)), 1)
	var half_w: int = int(sw.params.get("width_u", 3072)) / 2
	var spot: int = 3072  # SimProjectiles.spawn_sweep spot length (AB3 passes 3072)
	var c: int = Fp.cos(wr.angle)
	var s: int = Fp.sin(wr.angle)
	var dx: int = x - wr.x
	var dy: int = y - wr.y
	var along: int = Fp.mul_q16(dx, c) + Fp.mul_q16(dy, s)
	var across: int = absi(Fp.mul_q16(dy, c) - Fp.mul_q16(dx, s))
	if across > half_w:
		return 0
	var n: int = 0
	var k: int = 0
	while k * every < traverse:
		if wr.exec_tick + k * every <= t:
			var sk: int = len_u * (k * every) / traverse
			if absi(along - sk) <= spot / 2:
				n += 1
		k += 1
	var full: int = maxi(spot * traverse / (len_u * every), 1)
	return mini(n * 10000 / full, 10000)
