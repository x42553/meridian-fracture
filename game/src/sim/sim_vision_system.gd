class_name SimVisionSystem
extends SimSystem
## Pipeline stage 10 (abilities 3.4 / 5.9): fog, shroud, detection and structure ghosts.
##
## One counted coverage grid per group and kind (`vis` = sight, `det` = detection). A source stamps a disc of its sight
## radius; a mover only touches the cells that enter / leave (SimCoverGrid.move_disc). 0 <-> positive transitions are
## recorded by the grids and turned, once per update, into the fog bytes (0 shroud, 1 fog, 2 visible) and into
## entity visibility masks (`vis.vis_mask`, bit g = group g sees the entity). No height occlusion.
##
## Groups: with shared vision one per team (ascending team id), otherwise one per pid. Every stamp / unstamp happens
## immediately, the derived data (fog, masks, ghosts) is brought up to date by `update` every `vstride`-th tick.
## The view reads `fog_state_bytes` (live array, read-only); `world.fog` is replaced by the SimFogApi below.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const MAX_G: int = 8

## SimFogApi implementation (sim_core 3.3.2): thin adapter over the system, which it references but never owns.
class Fog:
	extends SimFogApi
	var sys: SimVisionSystem = null

	func cell_visible(pid: int, cx: int, cy: int) -> bool:
		return sys.is_cell_visible(sys.group_of(pid), cx, cy) if sys.group_of(pid) >= 0 else true

	func cell_explored(pid: int, cx: int, cy: int) -> bool:
		return sys.is_cell_explored(sys.group_of(pid), cx, cy) if sys.group_of(pid) >= 0 else true

	func entity_visible(pid: int, e: SimEntity) -> bool:
		return sys.entity_visible_to(pid, e)

	func entity_revealed(pid: int, e: SimEntity) -> bool:
		return sys.entity_revealed_to(pid, e)

	func fog_bytes(pid: int) -> PackedByteArray:
		return sys.fog_state_bytes(sys.group_of(pid))

	func fog_version(pid: int) -> int:
		return sys.fog_version(sys.group_of(pid))

	func ghosts(pid: int) -> Array:
		return sys.ghosts_of(sys.group_of(pid))

	func ghost_version(pid: int) -> int:
		var g: int = sys.group_of(pid)
		return sys.ghost_ver[g] if g >= 0 else 0

	func decoy_identified(pid: int, e: SimEntity) -> bool:
		return sys.decoy_identified(e, sys.group_of(pid))

var vstride: int = 2  ## MatchRules.vision_stride: an update every vstride-th tick
var restamp_budget: int = 128  ## MatchRules.vision_budget: sight-disc moves per update
var w: int = 0
var h: int = 0
var fog_on: bool = true
var shared: bool = false
var ngroups: int = 0
var pid_group: PackedInt32Array = PackedInt32Array()  ## slot_of(pid) -> group, -1
var pid_team: PackedInt32Array = PackedInt32Array()  ## slot_of(pid) -> team, -1
var group_team: PackedInt32Array = PackedInt32Array()
var disc: SimDisc = null
var vis: Array[SimCoverGrid] = []
var det: Array[SimCoverGrid] = []
var vis_sink: Array[SimCoverGrid.Sink] = []
var det_sink: Array[SimCoverGrid.Sink] = []
var fog: Array[PackedByteArray] = []
var explored_digest: PackedInt32Array = PackedInt32Array()
var fog_ver: PackedInt32Array = PackedInt32Array()
var ghost_ver: PackedInt32Array = PackedInt32Array()
var ghost_lists: Array = []  ## per group: Array[SimGhost] ascending eid
var temp: PackedInt32Array = PackedInt32Array()  ## MAX_TEMP_SRC x TS ints
var event_mask: int = 0  ## client-local: groups that get EV_VIS_CHANGED (never read by sim logic)
var pending: PackedInt32Array = PackedInt32Array()  ## eids to restamp at the next update
var deferred: PackedInt32Array = PackedInt32Array()  ## eids whose disc move waited for budget (ascending)
var uc_ids: PackedInt32Array = PackedInt32Array()  ## structures stamped with the construction radius
## Counters for the budget tests (never wall time).
var stat_restamps: int = 0
var stat_updates: int = 0
var stat_recomputes: int = 0

const AUDIT_N: int = 32  ## entities audited per update
const TS: int = 11  ## temp source: [gmask, shape, x, y, x2, y2, radius, detect, until, bind_eid, stamped]
const T_GMASK: int = 0
const T_SHAPE: int = 1
const T_X: int = 2
const T_Y: int = 3
const T_X2: int = 4
const T_Y2: int = 5
const T_RADIUS: int = 6
const T_DETECT: int = 7
const T_UNTIL: int = 8
const T_BIND: int = 9
const T_STAMPED: int = 10

var _update_no: int = 0
var _last_ghost_check: int = 0
var _acc: PackedInt32Array = PackedInt32Array()  ## movers of skipped ticks (vstride 3)
var _rc_stamp: PackedInt32Array = PackedInt32Array()
var _pmark: PackedByteArray = PackedByteArray()
var _bk_mark: PackedInt32Array = PackedInt32Array()
var _bk_list: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _busy_id: int = -1
var _audit_pos: int = 0


func _init() -> void:
	stage_no = 10
	stride = 2


func init_world(world: SimWorld) -> void:
	var r: SimMatchRules = world.rules
	setup(world, r.shared_vision != 0, r.fog != 0, r.vision_stride, r.vision_budget)


## Builds groups and grids and installs the fog adapter into world.fog.
func setup(world: SimWorld, shared_vision: bool, fog_enabled: bool, stride_ticks: int, budget: int) -> void:
	w = world.map.w
	h = world.map.h
	shared = shared_vision
	fog_on = fog_enabled
	vstride = clampi(stride_ticks, 1, 4)
	stride = 1  # the stage runs every tick: the skipped ticks only collect the movers (see update)
	restamp_budget = maxi(budget, 1)
	disc = SimDisc.new()
	pid_group.resize(SimConfig.MAX_PLAYERS + 1)
	pid_group.fill(-1)
	pid_team.resize(SimConfig.MAX_PLAYERS + 1)
	pid_team.fill(-1)
	group_team.resize(MAX_G)
	group_team.fill(-1)
	var teams: PackedInt32Array = PackedInt32Array()
	for p: SimPlayer in world.players:
		if p.controller == SimPlayer.Controller.NONE or p.pid >= SimConfig.MAX_PLAYERS:
			continue
		pid_team[p.pid] = p.team
		if not teams.has(p.team):
			teams.append(p.team)
	teams.sort()
	ngroups = 0
	for p2: SimPlayer in world.players:
		if p2.controller == SimPlayer.Controller.NONE or p2.pid >= SimConfig.MAX_PLAYERS:
			continue
		var g: int = teams.find(p2.team) if shared else p2.pid
		pid_group[p2.pid] = g
		group_team[g] = p2.team
		ngroups = maxi(ngroups, g + 1)
	vis.clear()
	det.clear()
	vis_sink.clear()
	det_sink.clear()
	fog.clear()
	ghost_lists.clear()
	explored_digest.resize(MAX_G)
	explored_digest.fill(0)
	fog_ver.resize(MAX_G)
	fog_ver.fill(0)
	ghost_ver.resize(MAX_G)
	ghost_ver.fill(0)
	var all_seen: PackedByteArray = PackedByteArray()
	if not fog_on:
		all_seen.resize(w * h)
		all_seen.fill(2)
	for gi: int in ngroups:
		ghost_lists.append([])
		if fog_on:
			vis.append(SimCoverGrid.new(w, h, disc))
			det.append(SimCoverGrid.new(w, h, disc))
			vis_sink.append(SimCoverGrid.Sink.new())
			det_sink.append(SimCoverGrid.Sink.new())
			var fb: PackedByteArray = PackedByteArray()
			fb.resize(w * h)
			fog.append(fb)
		else:
			fog.append(all_seen)
	temp.resize(K.MAX_TEMP_SRC * TS)
	temp.fill(0)
	var fa: Fog = Fog.new()
	fa.sys = self
	world.fog = fa
	_bk_mark.resize(world.spatial.bw * world.spatial.bh)


# ---- group / query API -------------------------------------------------------------------------------------------

func group_of(pid: int) -> int:
	return pid_group[SimConfig.slot_of(pid)] if pid >= 0 and pid < SimConfig.MAX_PLAYERS else -1


func n_groups() -> int:
	return ngroups


func is_cell_visible(group: int, cx: int, cy: int) -> bool:
	if not fog_on:
		return true
	if group < 0 or cx < 0 or cy < 0 or cx >= w or cy >= h:
		return false
	return fog[group][cy * w + cx] == 2


func is_cell_explored(group: int, cx: int, cy: int) -> bool:
	if not fog_on:
		return true
	if group < 0 or cx < 0 or cy < 0 or cx >= w or cy >= h:
		return false
	return fog[group][cy * w + cx] >= 1


func is_point_visible(group: int, x: int, y: int) -> bool:
	return is_cell_visible(group, x >> 10, y >> 10)


func is_cell_detected(group: int, cx: int, cy: int) -> bool:
	if not fog_on or group < 0 or cx < 0 or cy < 0 or cx >= w or cy >= h:
		return false
	return det[group].counts[cy * w + cx] > 0


## Fog and camouflage / detection (mask bit); the owner group always sees its own.
func entity_visible(e: SimEntity, group: int) -> bool:
	if not fog_on or group < 0:
		return true
	if e.vis == null:
		return is_cell_visible(group, e.x >> 10, e.y >> 10)
	return ((e.vis.vis_mask >> group) & 1) != 0


## Viewer pid: own and allied entities are always visible, others by mask.
func entity_visible_to(pid: int, e: SimEntity) -> bool:
	if not fog_on:
		return true
	var g: int = group_of(pid)
	if g < 0 or e.owner == pid:
		return true
	if e.owner >= 0 and e.team == pid_team[SimConfig.slot_of(pid)]:
		return true
	return entity_visible(e, g)


## Camouflage / detection only (fog ignored): an omniscient viewer still needs a detector for concealed enemies.
func entity_revealed_to(pid: int, e: SimEntity) -> bool:
	var g: int = group_of(pid)
	if g < 0 or e.vis == null or e.vis.concealed == 0 or e.owner == pid or not fog_on:
		return true
	if e.owner >= 0 and e.team == pid_team[SimConfig.slot_of(pid)]:
		return true
	return det[g].count_xy(e.x >> 10, e.y >> 10) > 0


func decoy_identified(e: SimEntity, group: int) -> bool:
	if group < 0 or not fog_on or (e.flags & SimFlags.F_DECOY) == 0:
		return false
	return det[group].count_xy(e.x >> 10, e.y >> 10) > 0


## 0 shroud, 1 fog, 2 visible; size w * h; the live array (never write).
func fog_state_bytes(group: int) -> PackedByteArray:
	return fog[group] if group >= 0 and group < fog.size() else PackedByteArray()


func fog_version(group: int) -> int:
	return fog_ver[group] if group >= 0 and group < MAX_G else 0


func ghosts_of(group: int) -> Array:
	return ghost_lists[group] if group >= 0 and group < ghost_lists.size() else []


## Group g remembers a ghost of structure eid.
func has_ghost(group: int, eid: int) -> bool:
	return _ghost_find(group, eid) >= 0


func set_event_groups(mask: int) -> void:
	event_mask = mask


## Reveals the terrain of a group for good (fog state 1 everywhere it was shroud).
func explore_all(group: int) -> void:
	if not fog_on or group < 0 or group >= ngroups:
		return
	var fb: PackedByteArray = fog[group]
	var changed: bool = false
	for cell: int in w * h:
		if fb[cell] == 0:
			fb[cell] = 1
			explored_digest[group] ^= SimCoverGrid.mix32(cell ^ 0x85EBCA6B)
			changed = true
	if changed:
		fog_ver[group] += 1


func restamp_pending() -> int:
	return pending.size()


# ---- temporary sources (64) ------------------------------------------------------------------------------------

## Adds a source for one group and returns its handle (0..63), -1 when the table is full or fog is off. SHAPE_DISC:
## disc of `radius` units around (x, y); SHAPE_CAPSULE: segment (x, y)-(x2, y2) with half-width `radius`. `detect`
## also stamps the detection grid. `until_tick` is absolute; `bind_eid` > 0 ends the source when that entity is gone
## (a disc follows it).
func add_temp_source(group: int, shape: int, x: int, y: int, x2: int, y2: int, radius: int, detect: bool, until_tick: int, bind_eid: int) -> int:
	if group < 0 or group >= ngroups:
		return -1
	return add_temp_mask(1 << group, shape, x, y, x2, y2, radius, detect, until_tick, bind_eid)


## Same for a mask of groups.
func add_temp_mask(gmask: int, shape: int, x: int, y: int, x2: int, y2: int, radius: int, detect: bool, until_tick: int, bind_eid: int) -> int:
	if not fog_on or gmask == 0:
		return -1
	for i: int in K.MAX_TEMP_SRC:
		var t: int = i * TS
		if temp[t + T_GMASK] != 0:
			continue
		temp[t + T_GMASK] = gmask
		temp[t + T_SHAPE] = shape
		temp[t + T_X] = x
		temp[t + T_Y] = y
		temp[t + T_X2] = x2
		temp[t + T_Y2] = y2
		temp[t + T_RADIUS] = radius
		temp[t + T_DETECT] = 1 if detect else 0
		temp[t + T_UNTIL] = until_tick
		temp[t + T_BIND] = bind_eid
		temp[t + T_STAMPED] = 0
		_temp_stamp(i, 1)
		return i
	return -1


func move_temp_source(handle: int, x: int, y: int) -> void:
	if handle < 0 or handle >= K.MAX_TEMP_SRC:
		return
	var t: int = handle * TS
	if temp[t + T_GMASK] == 0:
		return
	if temp[t + T_SHAPE] == K.SHAPE_DISC:
		_temp_move(handle, x, y)
		return
	var dx: int = x - temp[t + T_X]
	var dy: int = y - temp[t + T_Y]
	_temp_stamp(handle, -1)
	temp[t + T_X] = x
	temp[t + T_Y] = y
	temp[t + T_X2] += dx
	temp[t + T_Y2] += dy
	_temp_stamp(handle, 1)


func remove_temp_source(handle: int) -> void:
	if handle < 0 or handle >= K.MAX_TEMP_SRC:
		return
	var t: int = handle * TS
	if temp[t + T_GMASK] == 0:
		return
	if temp[t + T_STAMPED] != 0:
		_temp_stamp(handle, -1)
	for j: int in TS:
		temp[t + j] = 0


func temp_source_count() -> int:
	var n: int = 0
	for i: int in K.MAX_TEMP_SRC:
		if temp[i * TS + T_GMASK] != 0:
			n += 1
	return n


func _temp_stamp(i: int, sgn: int) -> void:
	var t: int = i * TS
	var gmask: int = temp[t + T_GMASK]
	var shape: int = temp[t + T_SHAPE]
	var cx: int = clampi(temp[t + T_X] >> 10, 0, w - 1)
	var cy: int = clampi(temp[t + T_Y] >> 10, 0, h - 1)
	var rc: int = SimDisc.radius_cells(temp[t + T_RADIUS])
	var detect: bool = temp[t + T_DETECT] != 0
	for g: int in ngroups:
		if ((gmask >> g) & 1) == 0:
			continue
		if shape == K.SHAPE_DISC:
			vis[g].stamp_disc(cx, cy, rc, sgn, vis_sink[g])
			if detect:
				det[g].stamp_disc(cx, cy, rc, sgn, det_sink[g])
		else:
			vis[g].stamp_capsule(temp[t + T_X], temp[t + T_Y], temp[t + T_X2], temp[t + T_Y2], temp[t + T_RADIUS], sgn, vis_sink[g])
			if detect:
				det[g].stamp_capsule(temp[t + T_X], temp[t + T_Y], temp[t + T_X2], temp[t + T_Y2], temp[t + T_RADIUS], sgn, det_sink[g])
	temp[t + T_STAMPED] = 1 if sgn > 0 else 0


func _temp_move(i: int, x: int, y: int) -> void:
	var t: int = i * TS
	var gmask: int = temp[t + T_GMASK]
	var ocx: int = clampi(temp[t + T_X] >> 10, 0, w - 1)
	var ocy: int = clampi(temp[t + T_Y] >> 10, 0, h - 1)
	var ncx: int = clampi(x >> 10, 0, w - 1)
	var ncy: int = clampi(y >> 10, 0, h - 1)
	var rc: int = SimDisc.radius_cells(temp[t + T_RADIUS])
	for g: int in ngroups:
		if ((gmask >> g) & 1) == 0:
			continue
		vis[g].move_disc(ocx, ocy, ncx, ncy, rc, vis_sink[g])
		if temp[t + T_DETECT] != 0:
			det[g].move_disc(ocx, ocy, ncx, ncy, rc, det_sink[g])
	temp[t + T_X] = x
	temp[t + T_Y] = y
	temp[t + T_X2] = x
	temp[t + T_Y2] = y


# ---- entity hooks ------------------------------------------------------------------------------------------------

func on_spawn(world: SimWorld, e: SimEntity) -> void:
	if disc == null or (e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE and e.kind != SimEntity.Kind.NEUTRAL):
		return
	var v: SimCompVision = SimCompVision.new()
	v.group = group_of(e.owner)
	if e.kind == SimEntity.Kind.STRUCTURE:
		v.vflags |= K.VF_STATIC
	if (e.flags & SimFlags.F_DECOY) != 0:
		v.stealth_kind |= K.SK_DECOY
	if e.abil != null:
		if e.abil.slot_of_kind(K.AK_CAMOUFLAGE) >= 0:
			v.stealth_kind |= K.SK_CAMOUFLAGE
		if e.abil.slot_of_kind(K.AK_SUBMERGE) >= 0:
			v.stealth_kind |= K.SK_SUBMARINE
	e.vis = v
	if world.abilities != null:
		world.abilities.finish_spawn(world, e)
	SimStealth.recompute(world, e, K.CR_GRANT)
	_restamp(world, e)
	_recompute(world, e)


func on_dying(world: SimWorld, e: SimEntity, _cause: int, _killer_id: int, _killer_pid: int) -> void:
	if e.vis != null:
		_restamp(world, e)


func on_remove(_world: SimWorld, e: SimEntity, _reason: int) -> void:
	if e.vis != null and fog_on:
		_unstamp_all(e.vis)
		e.vis.vis_mask = 0


func on_owner_changed(world: SimWorld, e: SimEntity, _old_owner: int) -> void:
	if e.vis == null:
		return
	_restamp(world, e)
	_recompute(world, e)


## Marks e for a restamp (sight radius / owner / activity / detector state changed); processed by the next update.
func request_restamp(eid: int) -> void:
	if eid >= _pmark.size():
		_pmark.resize(maxi(eid + 1, _pmark.size() * 2))
	if _pmark[eid] == 0:
		_pmark[eid] = 1
		pending.append(eid)


## Concealment of e flipped (SimStealth): recompute its mask for every group at once.
func on_conceal_changed(world: SimWorld, e: SimEntity) -> void:
	if e.vis != null and _busy_id != e.id:
		_recompute(world, e)


func force_reveal(world: SimWorld, e: SimEntity, until_tick: int) -> void:
	if e.vis == null:
		return
	e.vis.revealed_until = maxi(e.vis.revealed_until, until_tick)
	SimStealth.recompute(world, e, K.CR_DETECT)


# ---- sources ---------------------------------------------------------------------------------------------------

## FIX (abilities AB2): a squad inside a civilian garrison keeps looking out (sight of the claiming group); every other
## passenger is off the map.
static func _on_map(e: SimEntity) -> bool:
	if (e.flags & SimFlags.F_GONE) != 0:
		return false
	return (e.flags & SimFlags.F_INSIDE) == 0 or (e.flags & SimFlags.F_GARRISONED) != 0


func _sight_cells(world: SimWorld, e: SimEntity) -> int:
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_NO_VISION_GRANT)) != 0 or not _on_map(e) or e.owner < 0:
		return 0
	var sight: int = SimStats.get_val(world, e, DefEnums.Stat.SIGHT)
	if sight <= 0:
		return 0
	var r: int = SimDisc.radius_cells(sight)
	if (e.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
		r = mini(r, K.CONSTRUCTION_SIGHT_CELLS)
	return r


func _detect_cells(world: SimWorld, e: SimEntity) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or e.owner < 0:
		return 0
	var s: int = ab.slot_of_kind(K.AK_DETECTOR)
	if s < 0 or ab.slots[s * K.SLOT_STRIDE + K.SL_STATE] != K.DET_ON:
		return 0
	if e.kind == SimEntity.Kind.STRUCTURE:
		var sd: DefStructure = world.data.structures[e.def_idx]
		if (sd.flags & DefEnums.SF_POWERED_DEFENSE) != 0 and (e.flags & SimFlags.F_POWERED) == 0:
			return 0
	if world.combat != null and not world.combat.is_functional(world, e):
		return 0
	var base: int = K.DEFAULT_DETECT_U
	var list: Array[DefAbility] = world.abilities.abilities_of(world, e)
	var idx: int = ab.slots[s * K.SLOT_STRIDE + K.SL_AB_IDX]
	if idx >= 0 and idx < list.size():
		base = int(list[idx].params.get("radius_u", base))
	var radius_u: int = world.abilities.ability_param(world, e, K.AK_DETECTOR, "radius_u", base)
	var m: int = ab.slot_of_kind(K.AK_SENSOR_MAST)
	if m >= 0 and ab.slots[m * K.SLOT_STRIDE + K.SL_STATE] == 1 and ab.slots[m * K.SLOT_STRIDE + K.SL_T_END] == 0:
		var midx: int = ab.slots[m * K.SLOT_STRIDE + K.SL_AB_IDX]
		if midx >= 0 and midx < list.size():
			radius_u = maxi(radius_u, int(list[midx].params.get("reveal_radius_u", 0)))
	return SimDisc.radius_cells(radius_u)


## Brings the stamped sight / detection discs of e in line with its current state.
func _restamp(world: SimWorld, e: SimEntity) -> void:
	var v: SimCompVision = e.vis
	if v == null:
		return
	var active: bool = _on_map(e)
	if active:
		v.vflags &= ~K.VF_INACTIVE
	else:
		v.vflags |= K.VF_INACTIVE
	var group: int = group_of(e.owner)
	if not fog_on:
		v.group = group
		return
	var cx: int = clampi(e.x >> 10, 0, w - 1)
	var cy: int = clampi(e.y >> 10, 0, h - 1)
	var r: int = _sight_cells(world, e) if group >= 0 else 0
	if v.cx >= 0:
		if v.group == group and r == v.r_cells and r > 0:
			if v.cx != cx or v.cy != cy:
				vis[group].move_disc(v.cx, v.cy, cx, cy, r, vis_sink[group])
				v.cx = cx
				v.cy = cy
		else:
			vis[v.group].stamp_disc(v.cx, v.cy, v.r_cells, -1, vis_sink[v.group])
			v.cx = -1
	if v.cx < 0 and r > 0:
		vis[group].stamp_disc(cx, cy, r, 1, vis_sink[group])
		v.cx = cx
		v.cy = cy
		v.r_cells = r
		if (e.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
			v.vflags |= K.VF_UNDER_CONSTRUCTION
			if not uc_ids.has(e.id):
				uc_ids.append(e.id)
		else:
			v.vflags &= ~K.VF_UNDER_CONSTRUCTION
	var dr: int = _detect_cells(world, e) if group >= 0 else 0
	if v.det_cx >= 0:
		if v.group == group and dr == v.det_r and dr > 0:
			if v.det_cx != cx or v.det_cy != cy:
				det[group].move_disc(v.det_cx, v.det_cy, cx, cy, dr, det_sink[group])
				v.det_cx = cx
				v.det_cy = cy
		else:
			det[v.group].stamp_disc(v.det_cx, v.det_cy, v.det_r, -1, det_sink[v.group])
			v.det_cx = -1
	if v.det_cx < 0 and dr > 0:
		det[group].stamp_disc(cx, cy, dr, 1, det_sink[group])
		v.det_cx = cx
		v.det_cy = cy
		v.det_r = dr
	v.group = group


func _unstamp_all(v: SimCompVision) -> void:
	if v.cx >= 0 and v.group >= 0:
		vis[v.group].stamp_disc(v.cx, v.cy, v.r_cells, -1, vis_sink[v.group])
	if v.det_cx >= 0 and v.group >= 0:
		det[v.group].stamp_disc(v.det_cx, v.det_cy, v.det_r, -1, det_sink[v.group])
	v.cx = -1
	v.det_cx = -1


# ---- the stage ---------------------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	if not fog_on or disc == null:
		return
	var tick: int = world.tick
	# Movers are collected on EVERY tick (the world keeps the ids of the current and the previous tick only), so a
	# move made in stage 11 of an update tick, or in a tick the stride skips, is still seen by the next update.
	_acc.append_array(world.moved_prev2())
	if tick % vstride != 0:
		return
	_update_no += 1
	stat_updates += 1
	if _rc_stamp.size() < world.next_id:
		_rc_stamp.resize(maxi(world.next_id, _rc_stamp.size() * 2))
	# 0. structures that finished construction
	if not uc_ids.is_empty():
		var keep: PackedInt32Array = PackedInt32Array()
		for id: int in uc_ids:
			var ue: SimEntity = world.by_id[id]
			if ue == null or (ue.flags & SimFlags.F_GONE) != 0:
				continue
			if (ue.flags & SimFlags.F_UNDER_CONSTRUCTION) == 0:
				request_restamp(id)
			else:
				keep.append(id)
		uc_ids = keep
	var recl: PackedInt32Array = PackedInt32Array()
	# 1. pending restamps: spawn-time changes, sight stat changes, detector state
	if not pending.is_empty():
		pending.sort()
		var todo: PackedInt32Array = pending
		pending = PackedInt32Array()
		for id2: int in todo:
			_pmark[id2] = 0
			var pe: SimEntity = world.by_id[id2] if id2 < world.by_id.size() else null
			if pe != null and pe.vis != null:
				_restamp(world, pe)
				recl.append(id2)
	# 2/3. movers: sight and detection discs step by step, throttled by the restamp budget
	_acc.sort()
	var movers: PackedInt32Array = _dedupe(_acc)
	_acc = PackedInt32Array()
	var cand: PackedInt32Array = _merge(deferred, movers)
	var next_def: PackedInt32Array = PackedInt32Array()
	var crossings: int = 0
	for id3: int in cand:
		var e: SimEntity = world.by_id[id3] if id3 < world.by_id.size() else null
		if e == null or e.vis == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		var v: SimCompVision = e.vis
		var cx: int = e.x >> 10
		var cy: int = e.y >> 10
		var need_src: bool = v.cx >= 0 and (v.cx != cx or v.cy != cy)
		var need_det: bool = v.det_cx >= 0 and (v.det_cx != cx or v.det_cy != cy)
		if need_src or need_det:
			if crossings >= restamp_budget:
				next_def.append(id3)
			else:
				crossings += 1
				stat_restamps += 1
				if need_src:
					vis[v.group].move_disc(v.cx, v.cy, cx, cy, v.r_cells, vis_sink[v.group])
					v.cx = cx
					v.cy = cy
				if need_det:
					det[v.group].move_disc(v.det_cx, v.det_cy, cx, cy, v.det_r, det_sink[v.group])
					v.det_cx = cx
					v.det_cy = cy
		if cy * w + cx != v.mcell:
			recl.append(id3)
	deferred = next_def
	# 4. temporary sources
	_update_temp(world)
	# 5/9. fog bytes and the buckets whose entities must be re-evaluated
	_bk_list.resize(0)
	for g: int in ngroups:
		var s: PackedInt32Array = vis_sink[g].cells
		var ds: PackedInt32Array = det_sink[g].cells
		if s.is_empty() and ds.is_empty():
			continue
		var fb: PackedByteArray = fog[g]
		var vc: PackedInt32Array = vis[g].counts
		var changed: bool = false
		for c2: int in s:
			var cell: int = c2 >> 1
			var old: int = fb[cell]
			if vc[cell] > 0:
				if old != 2:
					fb[cell] = 2
					if old == 0:
						explored_digest[g] ^= SimCoverGrid.mix32(cell ^ 0x85EBCA6B)
					changed = true
			elif old == 2:
				fb[cell] = 1
				changed = true
			_mark_bucket(world, cell)
		for c3: int in ds:
			_mark_bucket(world, c3 >> 1)
		if changed:
			fog_ver[g] += 1
		vis_sink[g].clear()
		det_sink[g].clear()
	# 6. entity masks: movers that changed cell first, then every entity of a touched bucket
	for id4: int in recl:
		var me: SimEntity = world.by_id[id4]
		_recompute(world, me)
		_rc_stamp[id4] = _update_no
	if not _bk_list.is_empty():
		_bk_list.sort()
		var sp: SpatialHash = world.spatial
		for b: int in _bk_list:
			sp.cell_bucket((b % sp.bw) << 2, (b / sp.bw) << 2, _ids)
			for id5: int in _ids:
				var be: SimEntity = world.by_id[id5]
				if be == null or be.vis == null or _rc_stamp[id5] == _update_no:
					continue
				_recompute(world, be)
				_rc_stamp[id5] = _update_no
	# 8. ghosts whose cell became visible
	if tick - _last_ghost_check >= 10:
		_last_ghost_check = tick
		_prune_ghosts(world)
	_audit(world)


## Safety net for changes nobody announces (teleports, loading into a container, unloading): AUDIT_N entities per
## update, round robin over the entity list, are compared with their stamped state; a mismatch queues a restamp.
func _audit(world: SimWorld) -> void:
	var ents: Array[SimEntity] = world.entities
	var n: int = ents.size()
	if n == 0:
		return
	for k: int in mini(AUDIT_N, n):
		_audit_pos = (_audit_pos + 1) % n
		var e: SimEntity = ents[_audit_pos]
		var v: SimCompVision = e.vis
		if v == null:
			continue
		var active: bool = _on_map(e)
		if active != ((v.vflags & K.VF_INACTIVE) == 0):
			request_restamp(e.id)
		elif active and (e.flags & SimFlags.F_MOVING) == 0 and ((v.cx >= 0 and (v.cx != e.x >> 10 or v.cy != e.y >> 10)) \
				or (v.mcell >= 0 and v.mcell != (e.y >> 10) * w + (e.x >> 10))) and not deferred.has(e.id):
			request_restamp(e.id)


func _mark_bucket(world: SimWorld, cell: int) -> void:
	var sp: SpatialHash = world.spatial
	var b: int = ((cell / w) >> 2) * sp.bw + ((cell % w) >> 2)
	if _bk_mark[b] != _update_no:
		_bk_mark[b] = _update_no
		_bk_list.append(b)


func _update_temp(world: SimWorld) -> void:
	for i: int in K.MAX_TEMP_SRC:
		var t: int = i * TS
		if temp[t + T_GMASK] == 0:
			continue
		var bind: int = temp[t + T_BIND]
		var alive: bool = true
		var be: SimEntity = null
		if bind > 0:
			be = world.by_id[bind] if bind < world.by_id.size() else null
			alive = be != null and (be.flags & SimFlags.F_GONE) == 0
		if temp[t + T_UNTIL] <= world.tick or not alive:
			remove_temp_source(i)
		elif be != null and temp[t + T_SHAPE] == K.SHAPE_DISC and ((be.x >> 10) != (temp[t + T_X] >> 10) or (be.y >> 10) != (temp[t + T_Y] >> 10)):
			move_temp_source(i, be.x, be.y)


## Recomputes the visibility mask of e for every group (idempotent); fires ghosts, decoy identification and the
## detection side effects (Silent Watch end_on DETECTED, reveal_t linger).
func _recompute(world: SimWorld, e: SimEntity) -> void:
	var v: SimCompVision = e.vis
	if v == null:
		return
	stat_recomputes += 1
	var old: int = v.vis_mask
	var m: int = 0
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == 0:
		if not fog_on:
			m = (1 << ngroups) - 1
			v.mcell = (e.y >> 10) * w + (e.x >> 10)
		else:
			var cell: int = clampi(e.y >> 10, 0, h - 1) * w + clampi(e.x >> 10, 0, w - 1)
			v.mcell = cell
			var prev_busy: int = _busy_id
			_busy_id = e.id
			if (v.stealth_kind & (K.SK_CAMOUFLAGE | K.SK_SUBMARINE)) != 0 or v.concealed != 0:
				_detect_side_effects(world, e, v, cell)
			if (e.flags & SimFlags.F_DECOY) != 0:
				_decoy_check(world, e, v, cell)
			_busy_id = prev_busy
			for g: int in ngroups:
				if g == v.group:
					m |= 1 << g
				elif vis[g].counts[cell] > 0 and (v.concealed == 0 or det[g].counts[cell] > 0):
					m |= 1 << g
	else:
		v.mcell = -1
	if m != old:
		v.vis_mask = m
		_mask_changed(world, e, v, old, m)


func _detect_side_effects(world: SimWorld, e: SimEntity, v: SimCompVision, cell: int) -> void:
	var detected: bool = false
	for g: int in ngroups:
		if g != v.group and group_team[g] != e.team and vis[g].counts[cell] > 0 and det[g].counts[cell] > 0:
			detected = true
			break
	if not detected:
		return
	SimStatus.remove_on_event(world, e, K.RE_DETECT)
	var ab: SimCompAbility = e.abil
	if ab != null:
		var s: int = ab.slot_of_kind(K.AK_CAMOUFLAGE)
		if s >= 0:
			var reveal: int = SimStealth.slot_reveal(ab.slots[s * K.SLOT_STRIDE + K.SL_N])
			if reveal > 0:
				v.revealed_until = maxi(v.revealed_until, world.tick + reveal)
	SimStealth.recompute(world, e, K.CR_DETECT)


func _decoy_check(world: SimWorld, e: SimEntity, v: SimCompVision, cell: int) -> void:
	for g: int in ngroups:
		if g == v.group or group_team[g] == e.team or ((v.decoy_mask >> g) & 1) != 0:
			continue
		if det[g].counts[cell] > 0:
			v.decoy_mask |= 1 << g
			world.emit(K.EV_DECOY_IDENTIFIED, e.x, e.y, e.id, g)


func _mask_changed(world: SimWorld, e: SimEntity, v: SimCompVision, old: int, now: int) -> void:
	var diff: int = old ^ now
	for g: int in ngroups:
		if ((diff >> g) & 1) == 0:
			continue
		var seen: bool = ((now >> g) & 1) != 0
		if seen:
			v.ever_mask |= 1 << g
			if e.kind == SimEntity.Kind.STRUCTURE and _ghost_find(g, e.id) >= 0:
				_ghost_remove(world, g, e.id)
		elif e.kind == SimEntity.Kind.STRUCTURE and e.owner >= 0 and group_team[g] != e.team \
				and ((v.ever_mask >> g) & 1) != 0 and (e.flags & SimFlags.F_GONE) == 0:
			_ghost_add(world, g, e)
		if ((event_mask >> g) & 1) != 0:
			world.emit(K.EV_VIS_CHANGED, e.x, e.y, e.id, g, 1 if seen else 0)


# ---- ghosts -----------------------------------------------------------------------------------------------------

func _ghost_find(group: int, eid: int) -> int:
	if group < 0 or group >= ghost_lists.size():
		return -1
	var list: Array = ghost_lists[group]
	var lo: int = 0
	var hi: int = list.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if (list[mid] as SimGhost).eid < eid:
			lo = mid + 1
		else:
			hi = mid
	if lo < list.size() and (list[lo] as SimGhost).eid == eid:
		return lo
	return -1 - lo


func _ghost_add(world: SimWorld, group: int, e: SimEntity) -> void:
	var gh: SimGhost = SimGhost.new()
	gh.eid = e.id
	gh.def_idx = e.def_idx
	gh.owner = e.owner
	gh.x = e.x
	gh.y = e.y
	gh.facing = e.facing
	gh.hp_pct = (e.hp * 100 / e.hp_max) if e.hp_max > 0 else 100
	gh.seen_tick = world.tick
	gh.cell = (e.y >> 10) * w + (e.x >> 10)
	var list: Array = ghost_lists[group]
	var pos: int = _ghost_find(group, e.id)
	if pos >= 0:
		list[pos] = gh
	else:
		list.insert(-1 - pos, gh)
	ghost_ver[group] += 1
	world.emit(K.EV_GHOST_ADDED, e.x, e.y, e.id, group, e.def_idx)


func _ghost_remove(world: SimWorld, group: int, eid: int) -> void:
	var pos: int = _ghost_find(group, eid)
	if pos < 0:
		return
	(ghost_lists[group] as Array).remove_at(pos)
	ghost_ver[group] += 1
	world.emit(K.EV_GHOST_REMOVED, 0, 0, eid, group)


func _prune_ghosts(world: SimWorld) -> void:
	for g: int in ngroups:
		var list: Array = ghost_lists[g]
		var i: int = list.size() - 1
		while i >= 0:
			var gh: SimGhost = list[i]
			if fog[g][gh.cell] == 2:
				list.remove_at(i)
				ghost_ver[g] += 1
				world.emit(K.EV_GHOST_REMOVED, gh.x, gh.y, gh.eid, g)
			i -= 1


# ---- helpers ----------------------------------------------------------------------------------------------------

static func _dedupe(sorted: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var last: int = -1
	for v: int in sorted:
		if v != last:
			out.append(v)
			last = v
	return out


## Union of two ascending unique id lists.
static func _merge(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	if a.is_empty():
		return b
	var out: PackedInt32Array = PackedInt32Array()
	var i: int = 0
	var j: int = 0
	while i < a.size() and j < b.size():
		if a[i] < b[j]:
			out.append(a[i])
			i += 1
		elif a[i] > b[j]:
			out.append(b[j])
			j += 1
		else:
			out.append(a[i])
			i += 1
			j += 1
	while i < a.size():
		out.append(a[i])
		i += 1
	while j < b.size():
		out.append(b[j])
		j += 1
	return out


# ---- checksum and debug ----------------------------------------------------------------------------------------

func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	buf.append(ngroups)
	for g: int in ngroups:
		buf.append(vis[g].digest if fog_on else 0)
		buf.append(det[g].digest if fog_on else 0)
		buf.append(explored_digest[g])
		var list: Array = ghost_lists[g]
		buf.append(list.size())
		for gh: SimGhost in list:
			gh.hash_into(buf)
	buf.append_array(temp)
	buf.append(pending.size())
	buf.append_array(pending)
	buf.append(deferred.size())
	buf.append_array(deferred)
	buf.append(uc_ids.size())
	buf.append_array(uc_ids)
	buf.append(_acc.size())
	buf.append_array(_acc)
	buf.append(_audit_pos)


## Rebuilds every grid from the stamped state of the entities and temp sources and returns the number of cells
## (over all grids) whose count differs from the incremental result; 0 = OK.
func debug_rebuild_compare(world: SimWorld) -> int:
	if not fog_on:
		return 0
	var bad: int = 0
	var rv: Array[SimCoverGrid] = []
	var rd: Array[SimCoverGrid] = []
	for g: int in ngroups:
		rv.append(SimCoverGrid.new(w, h, disc))
		rd.append(SimCoverGrid.new(w, h, disc))
	for e: SimEntity in world.entities:
		var v: SimCompVision = e.vis
		if v == null or v.group < 0:
			continue
		if v.cx >= 0:
			rv[v.group].stamp_disc(v.cx, v.cy, v.r_cells, 1)
		if v.det_cx >= 0:
			rd[v.group].stamp_disc(v.det_cx, v.det_cy, v.det_r, 1)
	for i: int in K.MAX_TEMP_SRC:
		var t: int = i * TS
		if temp[t + T_GMASK] == 0 or temp[t + T_STAMPED] == 0:
			continue
		var rc: int = SimDisc.radius_cells(temp[t + T_RADIUS])
		for g2: int in ngroups:
			if ((temp[t + T_GMASK] >> g2) & 1) == 0:
				continue
			if temp[t + T_SHAPE] == K.SHAPE_DISC:
				var cx: int = clampi(temp[t + T_X] >> 10, 0, w - 1)
				var cy: int = clampi(temp[t + T_Y] >> 10, 0, h - 1)
				rv[g2].stamp_disc(cx, cy, rc, 1)
				if temp[t + T_DETECT] != 0:
					rd[g2].stamp_disc(cx, cy, rc, 1)
			else:
				rv[g2].stamp_capsule(temp[t + T_X], temp[t + T_Y], temp[t + T_X2], temp[t + T_Y2], temp[t + T_RADIUS], 1)
				if temp[t + T_DETECT] != 0:
					rd[g2].stamp_capsule(temp[t + T_X], temp[t + T_Y], temp[t + T_X2], temp[t + T_Y2], temp[t + T_RADIUS], 1)
	for g3: int in ngroups:
		for cell: int in w * h:
			if rv[g3].counts[cell] != vis[g3].counts[cell]:
				bad += 1
			if rd[g3].counts[cell] != det[g3].counts[cell]:
				bad += 1
		if rv[g3].digest != vis[g3].digest or rd[g3].digest != det[g3].digest:
			bad += 1
	return bad


## Total array writes of all grids (budget tests compare counters, never wall time).
func cells_written() -> int:
	var n: int = 0
	for g: int in vis.size():
		n += vis[g].stat_cells_written + det[g].stat_cells_written
	return n
