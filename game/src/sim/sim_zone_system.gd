class_name SimZoneSystem
extends SimSystem
## Pipeline stage 9 (abilities 5.11): the zone table, its lifecycle, membership passes, the Trident interception hand-off,
## warning markers, construction blocking, the unit-ability entry (smoke, cover, puck, decoy) and the summon drivers.
## A zone is an ints-only record (SimZone); its behaviour is data (the template's effects[]): SimZoneFx applies them.
##
## Entry points for the power framework (economy, EC3B) - all take positions and durations in sim units and ticks:
##   create_zone(zone_idx, pid, x, y, angle, until_tick, bind_eid, radius, length, width, warmup, power_idx, src_eid, count,
##               scatter_u, aux, shape) -> zone id or -1          the general form
##   spawn_zone(zone_idx, pid, x, y, angle, until_tick, bind_eid) -> zone id or -1     the spec form
##   end_zone(zone_id, reason), spawn_warning(...), intercept_ordinary / intercept_packet (combat), construction_blocked.
## Systems never store the SimWorld (a RefCounted cycle would leak): it is reached through a WeakRef set in init_world.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const PEND_STRIDE: int = 10  ## [due_tick, op, power_idx, pid, x, y, a, b, c, d]

var zones: Array[SimZone] = []  ## ascending id
var next_id: int = 1
var n_intercept: int = 0
var inter_slots: PackedInt32Array = PackedInt32Array()  ## MAX_INTERCEPT zone ids, 0 = free
var sum_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of entities carrying a summon record (derived list)
var pend: PackedInt32Array = PackedInt32Array()  ## deferred power actions (SimPowerFx), PEND_STRIDE ints each, ascending due tick
var attach_q: PackedInt32Array = PackedInt32Array()  ## Lagos-class parents waiting for their repair drone
var stat_passes: int = 0
var stat_members: int = 0

var _wr: WeakRef = null
var wh_cache: Dictionary = {}  ## packet warheads built on first use (derived cache, see SimPowerFx.warhead_for)
var _masks: Dictionary = {}  ## (owner, kind, selector) -> PackedByteArray of matching def indices (derived cache)


func _init() -> void:
	stage_no = 9
	inter_slots.resize(SimZoneConsts.MAX_INTERCEPT)


func init_world(world: SimWorld) -> void:
	_wr = weakref(world)
	for p: SimPlayer in world.players:
		if p.fx == null:
			p.fx = SimPlayerFx.new()


func _w() -> SimWorld:
	return _wr.get_ref() as SimWorld if _wr != null else null


# ---- queries -----------------------------------------------------------------------------------------------------

func get_zone(zone_id: int) -> SimZone:
	var lo: int = 0
	var hi: int = zones.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if zones[mid].id < zone_id:
			lo = mid + 1
		else:
			hi = mid
	if lo < zones.size() and zones[lo].id == zone_id:
		return zones[lo]
	return null


## Live zones sorted by id; read-only for the view.
func active_zones() -> Array[SimZone]:
	return zones


func zone_count() -> int:
	return zones.size()


## Does the zone show for player `viewer_pid` (view / AI)? Warning markers use their computed mask; everything else shows to
## the owner's team and, when the template says so (`visible_to_enemy`, the default), to everybody.
func visible_to(z: SimZone, viewer_pid: int) -> bool:
	var world: SimWorld = _w()
	if world == null or viewer_pid < 0 or viewer_pid >= world.players.size():
		return false
	if z.kind == SimZoneConsts.ZK_WARNING:
		return ((z.warn_vis >> viewer_pid) & 1) != 0
	if world.players[viewer_pid].team == z.team:
		return true
	return z.zone_idx >= 0 and world.data.zones[z.zone_idx].visible_to_enemy


## The zone whose shootable body is entity `eid`, null when it is none.
func zone_of_body(eid: int) -> SimZone:
	for z: SimZone in zones:
		if z.body_eid == eid:
			return z
	return null


## true when a debris zone covers the centre of cell (cx, cy) (Horizon: no new construction).
func construction_blocked(cx: int, cy: int) -> bool:
	var px: int = cx * 1024 + 512
	var py: int = cy * 1024 + 512
	for z: SimZone in zones:
		if z.kind == DefEnums.ZoneKind.DEBRIS and z.state == SimZoneConsts.ZS_ACTIVE and z.contains_point(px, py):
			var w: SimWorld = _w()
			if w == null or bool(w.data.zones[z.zone_idx].params.get("blocks_new_construction", false)):
				return true
	return false


## Name used by SimPlacement.
func blocks_construction(cx: int, cy: int) -> bool:
	return construction_blocked(cx, cy)


## Does a selector (DefSelector index, -1 = anyone) match entity e of the roster of its owner? Cached masks.
func selector_ok(world: SimWorld, e: SimEntity, sel: int) -> bool:
	if sel < 0:
		return true
	if e.owner < 0 or e.owner >= world.players.size():
		return false
	var is_struct: int = 1 if e.kind == SimEntity.Kind.STRUCTURE else 0
	var key: int = ((e.owner * 2 + is_struct) << 20) | sel
	var m: PackedByteArray
	if _masks.has(key):
		m = _masks[key]
	else:
		var r: DefRoster = world.players[e.owner].roster
		m = r.selector_mask_structures(sel) if is_struct == 1 else r.selector_mask_units(sel)
		_masks[key] = m
	return e.def_idx >= 0 and e.def_idx < m.size() and m[e.def_idx] != 0


## true when a zone other than z of the same template currently lists entity id as a member.
func covered_by_other(z: SimZone, id: int) -> bool:
	for o: SimZone in zones:
		if o != z and o.zone_idx == z.zone_idx and o.is_member(id):
			return true
	return false


# ---- creation ----------------------------------------------------------------------------------------------------

## Spec form (abilities 3.5): template zone at (x, y); until_tick 0 = the template duration; -1 when the table is full.
func spawn_zone(zone_idx: int, pid: int, x: int, y: int, angle: int, until_tick: int, bind_eid: int) -> int:
	return create_zone(zone_idx, pid, x, y, angle, until_tick, bind_eid)


## General form. radius / length / width override the template when > 0 (a length > 0 on a disc template makes it a
## capsule: Concealed Crossing); `shape` -1 = the template's, 0 disc, 1 capsule. warmup > 0 starts the zone in WARMUP for
## that many ticks (Wideband Scan: the marker is visible, nothing happens yet; the duration starts after it). count /
## scatter_u / aux drive DECOY zones (count decoys, scattered by hash(aux, k) inside scatter_u). Returns the zone id, or
## -1 (table full, bad template / owner, no room in the interception slots). extra_flags (SimZoneConsts.ZF_*) and
## override_bp (cover / shelter: the builder's own damage reduction instead of the template's) are set before the first
## membership pass.
func create_zone(zone_idx: int, pid: int, x: int, y: int, angle: int = 0, until_tick: int = 0, bind_eid: int = -1, radius: int = 0,
		length: int = 0, width: int = 0, warmup: int = 0, power_idx: int = -1, src_eid: int = -1, count: int = 1,
		scatter_u: int = 0, aux: int = 0, shape: int = -1, extra_flags: int = 0, override_bp: int = 0) -> int:
	var world: SimWorld = _w()
	if world == null or zone_idx < 0 or zone_idx >= world.data.zones.size():
		return -1
	if pid < -1 or pid >= world.players.size():
		return -1
	if zones.size() >= SimZoneConsts.MAX_ZONES:
		return -1
	var d: DefZone = world.data.zones[zone_idx]
	if d.max_per_owner > 0:
		_enforce_max(world, d, pid)
	var z: SimZone = SimZone.new()
	z.zone_idx = zone_idx
	z.kind = d.zone_kind
	z.owner_pid = pid
	z.team = world.team_of(pid)
	z.affects = d.affects
	z.membership = DefEnums.Membership.LATCHED if d.zone_kind == DefEnums.ZoneKind.BUFF else DefEnums.Membership.CONTINUOUS
	z.angle = angle & 4095
	z.x = x
	z.y = y
	z.bind_eid = bind_eid
	z.src_eid = src_eid
	z.power_idx = power_idx
	z.flags = extra_flags
	z.pa = override_bp
	var shp: int = d.shape if shape < 0 else shape
	if shape < 0 and length > 0:
		shp = DefEnums.ZoneShape.LINE
	z.shape = shp
	if shp == DefEnums.ZoneShape.LINE:
		var len_u: int = length if length > 0 else d.length
		var w_u: int = width if width > 0 else d.width
		var hw: int = w_u / 2 if w_u > 0 else (radius if radius > 0 else d.radius)
		if len_u <= 0:
			len_u = 2 * hw
		var hx: int = Fp.mul_q16(len_u / 2, Fp.cos(angle))
		var hy: int = Fp.mul_q16(len_u / 2, Fp.sin(angle))
		z.ax = x - hx
		z.ay = y - hy
		z.bx = x + hx
		z.by = y + hy
		z.radius = maxi(hw, 1)
	else:
		z.radius = radius if radius > 0 else d.radius
		z.ax = x
		z.ay = y
		z.bx = x
		z.by = y
	z.t_start = world.tick
	z.t_warn_end = world.tick + maxi(warmup, 0)
	z.state = SimZoneConsts.ZS_WARMUP if warmup > 0 else SimZoneConsts.ZS_ACTIVE
	z.t_end = until_tick if until_tick > 0 else z.t_warn_end + maxi(d.duration_t, 1)
	if z.t_end <= world.tick:
		return -1
	if d.follow_source and bind_eid > 0:
		z.flags |= SimZoneConsts.ZF_FOLLOW
	for fx: DefEffect in d.effects:
		if bool(fx.params.get("ends_on_move", false)):
			z.flags |= SimZoneConsts.ZF_ENDS_ON_MOVE
	if z.kind == DefEnums.ZoneKind.COVER or z.kind == DefEnums.ZoneKind.SHELTER:
		z.occ_max = int(d.params.get("occupants_max_n", 2))
	if z.kind == DefEnums.ZoneKind.INTERCEPT:
		var slot: int = _free_slot()
		if slot < 0:
			return -1
		z.slot = slot
		z.charges = int(d.params.get("charges_n", 24))
		z.pa = int(d.params.get("charges_per_strategic_packet_n", 8))
		z.pb = int(d.params.get("strategic_reduction_bp", 5000))
	z.id = next_id
	next_id += 1
	zones.append(z)
	if z.slot >= 0:
		inter_slots[z.slot] = z.id
		n_intercept += 1
	world.emit(SimZoneConsts.EV_ZONE_SPAWNED, z.x, z.y, -1, z.id, z.kind, pid)
	if warmup > 0 and z.kind == DefEnums.ZoneKind.REVEAL:
		world.emit(K.EV_SCAN_WARNING, z.x, z.y, -1, power_idx, z.radius / 1024, pid)
	if d.hp > 0 and z.kind != DefEnums.ZoneKind.DECOY:
		_spawn_body(world, z, d)
	if z.kind == DefEnums.ZoneKind.DECOY:
		SimZoneDecoys.spawn(world, z, d, count, scatter_u, aux)
	if z.state == SimZoneConsts.ZS_ACTIVE:
		_activate(world, z, d)
	return z.id


func _enforce_max(world: SimWorld, d: DefZone, pid: int) -> void:
	var mine: Array[SimZone] = []
	for z: SimZone in zones:
		if z.zone_idx == d.index and z.owner_pid == pid:
			mine.append(z)
	while mine.size() >= d.max_per_owner:
		end_zone(mine[0].id, SimZoneConsts.ZE_CANCELLED)
		mine.remove_at(0)
	if world == null:
		return


func _free_slot() -> int:
	for i: int in SimZoneConsts.MAX_INTERCEPT:
		if inter_slots[i] == 0:
			return i
	return -1


## The zone became ACTIVE: latch a buff snapshot, open a reveal source.
func _activate(world: SimWorld, z: SimZone, d: DefZone) -> void:
	z.state = SimZoneConsts.ZS_ACTIVE
	if z.membership == DefEnums.Membership.LATCHED and not d.effects.is_empty():
		var n: int = SimZoneFx.latch(world, self, z)
		if z.power_idx >= 0:
			world.emit(K.EV_BUFF_APPLIED, z.x, z.y, -1, z.power_idx, n, z.owner_pid)
	elif z.kind == DefEnums.ZoneKind.REVEAL or z.kind == DefEnums.ZoneKind.PUCK:
		var detect: bool = false
		for fx: DefEffect in d.effects:
			if fx.op == DefEnums.EffectOp.REVEAL and bool(fx.params.get("detect", false)):
				detect = true
		var bind: int = z.body_eid if z.body_eid > 0 else -1
		z.vis_handle = SimVision.add_reveal(world, 1 << (z.team & 15), z.shape, z.ax, z.ay, z.bx, z.by, z.radius, z.t_end, detect, bind)
	elif z.kind != DefEnums.ZoneKind.INTERCEPT and z.kind != DefEnums.ZoneKind.DECOY and not d.effects.is_empty():
		SimZoneFx.run_pass(world, self, z)


func _spawn_body(world: SimWorld, z: SimZone, d: DefZone) -> void:
	var def_idx: int = SimSummons.body_def(world.data, d)
	if def_idx < 0:
		return
	var flags: int = SimZoneConsts.SM_DEFAULT_POWER | SimZoneConsts.SM_SHOOTABLE | SimZoneConsts.SM_BODY | SimZoneConsts.SM_UNCONTROLLABLE \
		| SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_NO_VISION_GRANT
	var id: int = SimSummons.spawn(world, def_idx, z.owner_pid, z.x, z.y, z.src_eid, flags, z.t_end - world.tick, SimZoneConsts.SD_STATIC, 0, 0, 0)
	if id <= 0:
		return
	var e: SimEntity = world.by_id[id]
	world.set_hp_max(e, d.hp)
	e.hp = d.hp
	e.summon.zone_id = z.id
	e.summon.src_kind = 3
	e.summon.src_idx = z.zone_idx
	z.body_eid = id


## Mirror of an economy attack record as a marker (abilities 5.11.5). kind 0 circle (a = radius units) or 1 line
## (a = length, b = width); the marker lives `ticks` ticks and is visible to the owner team and to every player owning an
## entity inside the shape expanded by 3 cells, whatever the fog says. Returns the zone id or -1.
func spawn_warning(kind: int, pid: int, x: int, y: int, angle: int, a: int, b: int, ticks: int) -> int:
	var world: SimWorld = _w()
	if world == null or zones.size() >= SimZoneConsts.MAX_ZONES or ticks <= 0:
		return -1
	var z: SimZone = SimZone.new()
	z.zone_idx = -1
	z.kind = SimZoneConsts.ZK_WARNING
	z.owner_pid = pid
	z.team = world.team_of(pid)
	z.x = x
	z.y = y
	z.angle = angle & 4095
	z.pa = kind
	z.pb = b
	if kind == SimZoneConsts.WK_LINE:
		z.shape = DefEnums.ZoneShape.LINE
		var hx: int = Fp.mul_q16(a / 2, Fp.cos(angle))
		var hy: int = Fp.mul_q16(a / 2, Fp.sin(angle))
		z.ax = x - hx
		z.ay = y - hy
		z.bx = x + hx
		z.by = y + hy
		z.radius = maxi(b / 2, 1)
	else:
		z.shape = DefEnums.ZoneShape.CIRCLE
		z.ax = x
		z.ay = y
		z.bx = x
		z.by = y
		z.radius = a
	z.t_start = world.tick
	z.t_warn_end = world.tick + ticks
	z.t_end = world.tick + ticks
	z.affects = DefEnums.AFFECTS_ALL
	z.id = next_id
	next_id += 1
	zones.append(z)
	_warn_vis(world, z)
	world.emit(SimZoneConsts.EV_ZONE_SPAWNED, x, y, -1, z.id, z.kind, pid)
	return z.id


func _warn_vis(world: SimWorld, z: SimZone) -> void:
	var m: int = 0
	for p: SimPlayer in world.players:
		if p.team == z.team:
			m |= 1 << p.pid
	var cands: PackedInt32Array = PackedInt32Array()
	SimShape.query_shape(world, z.shape, z.ax, z.ay, z.bx, z.by, z.radius + SimZoneConsts.WARN_MARGIN_U, cands)
	for id: int in cands:
		var e: SimEntity = world.by_id[id]
		if e != null and e.owner >= 0 and (e.kind == SimEntity.Kind.UNIT or e.kind == SimEntity.Kind.STRUCTURE):
			m |= 1 << e.owner
	z.warn_vis = m


# ---- ending ------------------------------------------------------------------------------------------------------

## Ends a zone: releases what it holds, closes its vision source, removes its body and decoys, emits EV_ZONE_ENDED.
func end_zone(zone_id: int, reason: int) -> void:
	var world: SimWorld = _w()
	var z: SimZone = get_zone(zone_id)
	if world == null or z == null:
		return
	z.flags |= SimZoneConsts.ZF_CANCELLED
	if z.zone_idx >= 0:
		SimZoneFx.release_all(world, self, z)
	if z.vis_handle >= 0:
		SimVision.remove_reveal(world, z.vis_handle)
		z.vis_handle = -1
	if z.slot >= 0:
		inter_slots[z.slot] = 0
		n_intercept -= 1
		z.slot = -1
	for i: int in zones.size():
		if zones[i] == z:
			zones.remove_at(i)
			break
	if z.body_eid > 0:
		var b: SimEntity = world.get_entity(z.body_eid)
		if b != null and (b.flags & SimFlags.F_GONE) == 0:
			world.remove_entity(b.id, SimEvent.REM_EXPIRED)
	if z.kind == DefEnums.ZoneKind.DECOY:
		for id: int in z.members:
			var dec: SimEntity = world.get_entity(id)
			if dec != null and (dec.flags & SimFlags.F_GONE) == 0:
				world.remove_entity(id, SimEvent.REM_EXPIRED)
	world.emit(SimZoneConsts.EV_ZONE_ENDED, z.x, z.y, -1, z.id, reason)
	SimZoneAbilities.on_zone_ended(world, self, z)


# ---- Trident (abilities 5.11.4) ----------------------------------------------------------------------------------

## Combat asks once per interceptable projectile per tick. Returns the zone id that consumed one charge, or -1.
func intercept_ordinary(_world: SimWorld, owner_team: int, x0: int, y0: int, x1: int, y1: int, sx: int, sy: int, _proj_flags: int) -> int:
	if n_intercept <= 0:
		return -1
	for slot: int in SimZoneConsts.MAX_INTERCEPT:
		var zid: int = inter_slots[slot]
		if zid == 0:
			continue
		var z: SimZone = get_zone(zid)
		if z == null or z.team == owner_team or z.charges <= 0 or z.state != SimZoneConsts.ZS_ACTIVE:
			continue
		if SimShape.circle_contains(z.x, z.y, z.radius, sx, sy):
			continue  # fired from inside: bypasses
		if SimShape.segment_enters_circle(z.x, z.y, z.radius, x0, y0, x1, y1):
			z.charges -= 1
			return z.id
	return -1


## Combat asks once per strategic packet at detonation. Returns the extra resistance in bp (5000) after consuming the
## packet cost from an armed hostile zone covering the point, else 0.
func intercept_packet(_world: SimWorld, owner_team: int, x: int, y: int) -> int:
	if n_intercept <= 0:
		return 0
	for slot: int in SimZoneConsts.MAX_INTERCEPT:
		var zid: int = inter_slots[slot]
		if zid == 0:
			continue
		var z: SimZone = get_zone(zid)
		if z == null or z.team == owner_team or z.state != SimZoneConsts.ZS_ACTIVE or z.charges < z.pa or z.pa <= 0:
			continue
		if SimShape.circle_contains(z.x, z.y, z.radius, x, y):
			z.charges -= z.pa
			return z.pb
	return 0


# ---- unit abilities ----------------------------------------------------------------------------------------------

## CMD_USE_ABILITY of smoke_launcher / portable_cover / sensor_puck / decoy_spawn (called by SimAbilityCmds). Returns
## 0 or an RJ_* reason.
func use_ability(world: SimWorld, e: SimEntity, slot: int, mode: int, target: int, x: int, y: int) -> int:
	return SimZoneAbilities.use(world, self, e, slot, mode, target, x, y)


# ---- lifecycle hooks ---------------------------------------------------------------------------------------------

func on_spawn(world: SimWorld, e: SimEntity) -> void:
	if e.kind != SimEntity.Kind.UNIT:
		return
	if world.data.units[e.def_idx].params.has("summon_attached_idx") and e.summon == null:
		attach_q.append(e.id)
	SimPowerFx.on_unit_spawn(world, e)  # units created inside a global-effect window receive it


func on_dying(world: SimWorld, e: SimEntity, cause: int, _killer_id: int, _killer_pid: int) -> void:
	if e.summon != null:
		SimSummons.on_dying(world, self, e, cause)


func on_remove(world: SimWorld, e: SimEntity, reason: int) -> void:
	if e.summon != null:
		SimSummons.on_remove(world, self, e, reason)
	SimAbilitySystem._erase(sum_ids, e.id)
	var qi: int = attach_q.find(e.id)
	if qi >= 0:
		attach_q.remove_at(qi)


func on_player_eliminated(_world: SimWorld, pid: int) -> void:
	for z: SimZone in zones.duplicate():
		if z.owner_pid == pid:
			end_zone(z.id, SimZoneConsts.ZE_CANCELLED)


# ---- the stage ---------------------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	var tick: int = world.tick
	for p: SimPlayer in world.players:
		if p.fx != null and p.fx.n_active > 0:
			p.fx.prune(tick)
	if not attach_q.is_empty():
		SimSummons.process_attach(world, self)
	if not pend.is_empty():
		SimPowerFx.process_pending(world, self)
	for z: SimZone in zones.duplicate():
		_update_zone(world, z, tick)
	for id: int in sum_ids.duplicate():
		var e: SimEntity = world.by_id[id] if id < world.by_id.size() else null
		if e != null and e.summon != null and (e.flags & SimFlags.F_GONE) == 0:
			SimSummons.step(world, self, e)


func _update_zone(world: SimWorld, z: SimZone, tick: int) -> void:
	if get_zone(z.id) != z:
		return
	if tick >= z.t_end:
		end_zone(z.id, SimZoneConsts.ZE_EXPIRED)
		return
	if z.kind == SimZoneConsts.ZK_WARNING:
		if (tick - z.t_start) % SimZoneConsts.WARN_PERIOD == 0:
			_warn_vis(world, z)
		return
	if z.body_eid > 0:
		var b: SimEntity = world.get_entity(z.body_eid)
		if b == null or (b.flags & SimFlags.F_GONE) != 0:
			end_zone(z.id, SimZoneConsts.ZE_BODY)
			return
	if z.bind_eid > 0:
		var be: SimEntity = world.get_entity(z.bind_eid)
		if be == null or (be.flags & SimFlags.F_GONE) != 0:
			end_zone(z.id, SimZoneConsts.ZE_BOUND)
			return
		if z.has_flag(SimZoneConsts.ZF_FOLLOW) and (be.x != z.x or be.y != z.y):
			_move_zone(z, be.x, be.y)
	var d: DefZone = world.data.zones[z.zone_idx]
	if z.state == SimZoneConsts.ZS_WARMUP:
		if tick >= z.t_warn_end:
			_activate(world, z, d)
		return
	if z.membership != DefEnums.Membership.CONTINUOUS or d.effects.is_empty():
		return
	if z.kind == DefEnums.ZoneKind.REVEAL or z.kind == DefEnums.ZoneKind.PUCK or z.kind == DefEnums.ZoneKind.INTERCEPT or z.kind == DefEnums.ZoneKind.DECOY:
		return
	var period: int = SimZoneConsts.PERIOD_SLOW if z.kind == DefEnums.ZoneKind.REPAIR else SimZoneConsts.PERIOD_FAST
	if (tick - z.t_start) % period == 0:
		stat_passes += 1
		SimZoneFx.run_pass(world, self, z)


static func _move_zone(z: SimZone, nx: int, ny: int) -> void:
	var dx: int = nx - z.x
	var dy: int = ny - z.y
	z.x = nx
	z.y = ny
	z.ax += dx
	z.ay += dy
	z.bx += dx
	z.by += dy


# ---- hash / validation -------------------------------------------------------------------------------------------

func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	buf.append(next_id)
	buf.append(n_intercept)
	buf.append(zones.size())
	for z: SimZone in zones:
		z.hash_into(buf)
	buf.append_array(inter_slots)
	buf.append(pend.size())
	buf.append_array(pend)
	buf.append(attach_q.size())
	buf.append_array(attach_q)


func debug_validate(world: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var last: int = 0
	var n_inter: int = 0
	for z: SimZone in zones:
		if z.id <= last:
			out.append("zone %d: ids not ascending" % z.id)
		last = z.id
		if z.n_members != z.members.size():
			out.append("zone %d: n_members %d vs %d" % [z.id, z.n_members, z.members.size()])
		if z.members.size() > SimZoneConsts.MAX_MEMBERS:
			out.append("zone %d: too many members" % z.id)
		for i: int in range(1, z.members.size()):
			if z.members[i - 1] >= z.members[i] and z.kind != DefEnums.ZoneKind.DECOY:
				out.append("zone %d: members not ascending" % z.id)
				break
		if z.t_end < world.tick and z.kind != SimZoneConsts.ZK_WARNING:
			out.append("zone %d: expired but present" % z.id)
		if z.slot >= 0:
			n_inter += 1
			if inter_slots[z.slot] != z.id:
				out.append("zone %d: interception slot %d holds %d" % [z.id, z.slot, inter_slots[z.slot]])
		if z.body_eid > 0:
			var b: SimEntity = world.get_entity(z.body_eid)
			if b == null or b.summon == null or b.summon.zone_id != z.id:
				out.append("zone %d: body %d missing or unlinked" % [z.id, z.body_eid])
	if n_inter != n_intercept:
		out.append("n_intercept %d vs %d slots" % [n_intercept, n_inter])
	for id: int in sum_ids:
		var e: SimEntity = world.by_id[id] if id < world.by_id.size() else null
		if e == null or e.summon == null:
			out.append("sum_ids: %d has no summon record" % id)
	return out
