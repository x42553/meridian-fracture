class_name SimPlacement
extends RefCounted
## Placement validation and ghost data (economy 3.4 / 5.3): build radius from every own ACTIVE HQ, footprint,
## terrain, structures, deposit fields, debris, units, aprons, dock berth and the strategic limit. Stateless: static
## methods taking the world, no allocation-free promise (AI / command time only, never per tick).
##
## Data used (data module, no competing file): DefStructure.fp_w / fp_h / fp_mask, exit_dx / exit_dy (the exit
## cell of a producer, which doubles as its apron), place_mask (PLACE_SHORELINE for a Dock; rotatable),
## max_per_player, build_radius (> 0 marks an HQ), queue_kind (producers need a free apron). The footprint the map
## occupies is `map.footprint_of(STRUCTURE, s_idx)` when registered, else built from the def.
##
## Dock berth (not a data field): the fw x 2 strip of cells directly beyond the footprint on the exit side.

const DOCK_BERTH_ROWS: int = 2
const MIN_WATER_BODY: int = 30


## Fills `out` (caller-owned, reusable) and returns out.reason (RSN_*, 0 = valid). cx / cy = origin (top-left)
## cell of the rotated footprint. All failing cells are marked in out.cells; the reason is the first failing rule in
## the order of economy 5.3.
static func validate(world: SimWorld, pid: int, s_idx: int, cx: int, cy: int, rot: int, out: SimPlacementResult) -> int:
	return _validate(world, pid, s_idx, cx, cy, rot, out, false, 0)


## HQ site of an MCV: the HQ footprint centred on the MCV's cell, rules 1 and 3-9 (no radius, no strategic limit).
static func validate_hq_site(world: SimWorld, pid: int, mcv: SimEntity, out: SimPlacementResult) -> int:
	var s_idx: int = hq_def_of_mcv(world, mcv.def_idx)
	if s_idx < 0:
		out.reset(0, 0, 0, 0)
		out.reason = SimEconConst.RSN_NOT_AVAILABLE
		return out.reason
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	var sz: int = fp.size_oriented(0)
	var w: int = sz >> 8
	var h: int = sz & 255
	var ccx: int = mcv.x >> SimConfig.CELL_SHIFT
	var ccy: int = mcv.y >> SimConfig.CELL_SHIFT
	return _validate(world, pid, s_idx, ccx - (w - 1) / 2, ccy - (h - 1) / 2, 0, out, true, mcv.id)


## Sub-cell centre x of the structure entity: cx * 1024 + w * 512 (w after rotation). Ints only (DR-1).
static func footprint_center_x(world: SimWorld, s_idx: int, cx: int, rot: int) -> int:
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	var w: int = fp.size_oriented(rot & 3) >> 8
	return cx * SimConfig.CELL + w * (SimConfig.CELL / 2)


static func footprint_center_y(world: SimWorld, s_idx: int, cy: int, rot: int) -> int:
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	var h: int = fp.size_oriented(rot & 3) & 255
	return cy * SimConfig.CELL + h * (SimConfig.CELL / 2)


## Squared distance from a point to the rectangle [rx0, rx1] x [ry0, ry1] (sub-cells, exact ints).
static func dist2_point_to_rect(px: int, py: int, rx0: int, ry0: int, rx1: int, ry1: int) -> int:
	var dx: int = maxi(maxi(rx0 - px, px - rx1), 0)
	var dy: int = maxi(maxi(ry0 - py, py - ry1), 0)
	return dx * dx + dy * dy


## AI helper: first valid origin cell around (near_x, near_y) [cells] in ring order (ring r = Chebyshev distance,
## row-major inside a ring), at most 400 probes. False when none. DEVIATION: `out_cell` is a PackedInt32Array
## ([cx, cy]) because a Vector2i argument cannot be an out parameter in GDScript.
static func find_site(world: SimWorld, pid: int, s_idx: int, near_x: int, near_y: int, max_ring: int, out_cell: PackedInt32Array) -> bool:
	return find_site_rot(world, pid, s_idx, near_x, near_y, max_ring, 0, out_cell)


## find_site for a rotatable footprint (Dock): the same ring search at orientation `rot` (0..3).
static func find_site_rot(world: SimWorld, pid: int, s_idx: int, near_x: int, near_y: int, max_ring: int, rot: int, out_cell: PackedInt32Array) -> bool:
	var res: SimPlacementResult = SimPlacementResult.new()
	var probes: int = 0
	for r: int in range(0, max_ring + 1):
		for y: int in range(near_y - r, near_y + r + 1):
			var step: int = 1 if (y == near_y - r or y == near_y + r) else maxi(2 * r, 1)
			var x: int = near_x - r
			while x <= near_x + r:
				if probes >= SimEconConst.SITE_MAX_PROBES:
					return false
				probes += 1
				if validate(world, pid, s_idx, x, y, rot, res) == SimEconConst.RSN_OK:
					out_cell.resize(2)
					out_cell[0] = x
					out_cell[1] = y
					return true
				x += step
	return false


## True when the movement domain offers eject_units_from_rect (the static SimMovement facade or a method of the
## stage-6 system); otherwise every ground unit in a footprint blocks placement.
static func can_eject_units(world: SimWorld) -> bool:
	var facade: GDScript = SimMovement
	if facade.has_method("eject_units_from_rect"):
		return true
	return world.movement != null and world.movement.has_method("eject_units_from_rect")


## Pushes the placer team's ground units out of a validated footprint (call after `validate` succeeded and before
## spawning the structure). No-op without an eject service.
static func eject_units(world: SimWorld, pid: int, res: SimPlacementResult) -> void:
	var x0: int = res.ox
	var y0: int = res.oy
	var x1: int = res.ox + res.w - 1
	var y1: int = res.oy + res.h - 1
	var team: int = world.team_of(pid)
	var facade: GDScript = SimMovement
	if facade.has_method("eject_units_from_rect"):
		facade.call("eject_units_from_rect", world, x0, y0, x1, y1, team)
	elif world.movement != null and world.movement.has_method("eject_units_from_rect"):
		world.movement.call("eject_units_from_rect", world, x0, y0, x1, y1, team)


## The footprint the map uses for a structure def (registered) or one built from the def (Dock rotates).
static func footprint_of_def(world: SimWorld, s_idx: int) -> MapFootprint:
	var fp: MapFootprint = world.map.footprint_of(SimEntity.Kind.STRUCTURE, s_idx)
	if fp != null:
		return fp
	var d: DefStructure = world.data.structures[s_idx]
	return MapFootprint.new(d.fp_w, d.fp_h, d.fp_mask, (d.place_mask & DefEnums.PLACE_SHORELINE) != 0)


## Structure def index of the HQ an MCV unit def deploys into (DefStructure.deploy_unit), -1 if none.
static func hq_def_of_mcv(world: SimWorld, unit_idx: int) -> int:
	for s: DefStructure in world.data.structures:
		if s.deploy_unit == unit_idx and unit_idx >= 0:
			return s.index
	return -1


## Origin (top-left) cell of a placed structure entity into out[0], out[1].
static func entity_origin(world: SimWorld, e: SimEntity, out: PackedInt32Array) -> void:
	var fp: MapFootprint = footprint_of_def(world, e.def_idx)
	var orient: int = ((e.facing >> 10) & 3) if fp.rotatable else 0
	var sz: int = fp.size_oriented(orient)
	out[0] = (e.x - (sz >> 8) * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	out[1] = (e.y - (sz & 255) * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT


## Exit cell (index into the map) of a structure with origin (ox, oy) and orientation `orient`, -1 outside the map.
static func exit_cell(world: SimWorld, s_idx: int, ox: int, oy: int, orient: int) -> int:
	var d: DefStructure = world.data.structures[s_idx]
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	var o: PackedInt32Array = PackedInt32Array([0, 0])
	MapFootprint.rotate_offset(fp.w, fp.h, orient if fp.rotatable else 0, d.exit_dx, d.exit_dy, o)
	var x: int = ox + o[0]
	var y: int = oy + o[1]
	if not world.map.in_bounds(x, y):
		return -1
	return world.map.idx(x, y)


static func _validate(world: SimWorld, pid: int, s_idx: int, cx: int, cy: int, rot: int, out: SimPlacementResult, hq_site: bool, ignore_id: int) -> int:
	var map: MapData = world.map
	var d: DefStructure = world.data.structures[s_idx] if s_idx >= 0 and s_idx < world.data.structures.size() else null
	if d == null:
		out.reset(cx, cy, 0, 0)
		out.reason = SimEconConst.RSN_INVALID_INDEX
		return out.reason
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	var orient: int = (rot & 3) if fp.rotatable else 0
	var sz: int = fp.size_oriented(orient)
	var w: int = sz >> 8
	var h: int = sz & 255
	out.reset(cx, cy, w, h)
	var reason: int = SimEconConst.RSN_OK
	var solid: PackedInt32Array = PackedInt32Array()
	# 1. footprint inside the map with a 1-cell margin
	if fp.cells_at(orient, cx, cy, solid, map.w, map.h) < 0:
		out.cells.fill(SimEconConst.CF_TERRAIN)
		out.reason = SimEconConst.RSN_TERRAIN
		out.in_radius = false
		return out.reason
	for c: int in solid:
		var mx: int = c % map.w
		var my: int = c / map.w
		if mx < 1 or my < 1 or mx >= map.w - 1 or my >= map.h - 1:
			_mark(out, mx, my, SimEconConst.CF_TERRAIN)
			reason = _first(reason, SimEconConst.RSN_TERRAIN)
	# 2. build radius
	var x0: int = cx * SimConfig.CELL
	var y0: int = cy * SimConfig.CELL
	var x1: int = (cx + w) * SimConfig.CELL
	var y1: int = (cy + h) * SimConfig.CELL
	if hq_site:
		out.in_radius = true
	else:
		out.in_radius = _in_build_radius(world, pid, x0, y0, x1, y1)
		if not out.in_radius:
			reason = _first(reason, SimEconConst.RSN_OUT_OF_RADIUS)
	# 3-6. terrain, structures, deposit fields, debris (per cell; every failing cell is marked)
	var shore: bool = (d.place_mask & DefEnums.PLACE_SHORELINE) != 0
	var zones_block: bool = world.zones != null and world.zones.has_method("blocks_construction")
	for c: int in solid:
		var mx: int = c % map.w
		var my: int = c / map.w
		var ok_t: bool = map.is_shore_buildable(mx, my) if shore else map.is_buildable(mx, my)
		if not ok_t:
			_mark(out, mx, my, SimEconConst.CF_TERRAIN)
			reason = _first(reason, SimEconConst.RSN_TERRAIN)
	for c: int in solid:
		var mx2: int = c % map.w
		var my2: int = c / map.w
		if map.occupant_at(c) >= 0:
			_mark(out, mx2, my2, SimEconConst.CF_STRUCTURE)
			reason = _first(reason, SimEconConst.RSN_STRUCTURE_BLOCK)
	for c: int in solid:
		if map.field_of[c] != 0:
			_mark(out, c % map.w, c / map.w, SimEconConst.CF_DEPOSIT)
			reason = _first(reason, SimEconConst.RSN_DEPOSIT)
	if zones_block:
		for c: int in solid:
			if world.zones.call("blocks_construction", c % map.w, c / map.w):
				_mark(out, c % map.w, c / map.w, SimEconConst.CF_DEBRIS)
				reason = _first(reason, SimEconConst.RSN_DEBRIS)
	# 7. units
	if _units_block(world, pid, x0, y0, x1, y1, solid, out, ignore_id):
		reason = _first(reason, SimEconConst.RSN_UNIT_BLOCK)
	# 8. apron of a producer, and other producers' aprons
	if not _apron_ok(world, s_idx, cx, cy, orient, solid, out):
		out.apron_ok = false
		reason = _first(reason, SimEconConst.RSN_APRON)
	# 9. dock berth
	if shore:
		out.berth_ok = _berth_ok(world, d, cx, cy, orient, fp)
		if not out.berth_ok:
			reason = _first(reason, SimEconConst.RSN_NEEDS_SHORE)
	# 10. strategic limit
	if not hq_site and d.max_per_player > 0 and _owned_of_limit(world, pid) >= d.max_per_player:
		reason = _first(reason, SimEconConst.RSN_STRATEGIC_LIMIT)
	out.reason = reason
	return reason


static func _first(current: int, candidate: int) -> int:
	return candidate if current == SimEconConst.RSN_OK else current


static func _mark(out: SimPlacementResult, mx: int, my: int, flag: int) -> void:
	var i: int = (my - out.oy) * out.w + (mx - out.ox)
	if i >= 0 and i < out.cells.size() and out.cells[i] == SimEconConst.CF_OK:
		out.cells[i] = flag


## valid iff the nearest point of the footprint rect is within the build radius of some own ACTIVE HQ.
static func _in_build_radius(world: SimWorld, pid: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	if pid < 0 or pid >= world.players.size():
		return false
	for e: SimEntity in world.structures_of(pid):
		if (e.flags & SimFlags.F_GONE) != 0 or e.econ == null or e.econ.st != SimEconConst.ST_ACTIVE:
			continue
		var d: DefStructure = world.data.structures[e.def_idx]
		if d.build_radius <= 0:
			continue
		if dist2_point_to_rect(e.x, e.y, x0, y0, x1, y1) <= d.build_radius * d.build_radius:
			return true
	return false


## Ground entities whose centre lies in a solid footprint cell. Friendly mobile units are ejected at placement
## when the movement system offers eject_units_from_rect and do not block; every other ground unit blocks.
static func _units_block(world: SimWorld, pid: int, x0: int, y0: int, x1: int, y1: int, solid: PackedInt32Array, out: SimPlacementResult, ignore_id: int) -> bool:
	var ids: PackedInt32Array = PackedInt32Array()
	var need: int = SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT) | SimTag.layer_bit(SimEntity.Layer.GROUND)
	if world.query_rect(x0, y0, x1 - 1, y1 - 1, ids, need) == 0:
		return false
	var can_eject: bool = can_eject_units(world)
	var blocked: bool = false
	for id: int in ids:
		if id == ignore_id:
			continue
		var u: SimEntity = world.get_entity(id)
		if u == null or (u.flags & (SimFlags.F_INSIDE | SimFlags.F_GONE | SimFlags.F_AIRBORNE)) != 0:
			continue
		var ucx: int = u.x >> SimConfig.CELL_SHIFT
		var ucy: int = u.y >> SimConfig.CELL_SHIFT
		if not solid.has(ucy * world.map.w + ucx):
			continue
		var friendly: bool = u.owner >= 0 and world.team_of(u.owner) == world.team_of(pid)
		var mobile: bool = world.data.units[u.def_idx].speed > 0
		if friendly and mobile and can_eject:
			continue
		_mark(out, ucx, ucy, SimEconConst.CF_UNIT)
		blocked = true
	return blocked


static func _apron_ok(world: SimWorld, s_idx: int, cx: int, cy: int, orient: int, solid: PackedInt32Array, out: SimPlacementResult) -> bool:
	var map: MapData = world.map
	var ok: bool = true
	if _has_apron(world, s_idx):
		# (a) the own exit cell must be passable ground, free of structures and outside the footprint
		var ec: int = exit_cell(world, s_idx, cx, cy, orient)
		if ec < 0 or not map.is_passable_ground(ec % map.w, ec / map.w) or map.occupant_at(ec) >= 0 or solid.has(ec):
			ok = false
	# (b) the new footprint must not cover the exit cell of a nearby producer
	var margin: int = SimEconConst.APRON_SCAN_CELLS * SimConfig.CELL
	var near: PackedInt32Array = PackedInt32Array()
	var need: int = SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.STRUCTURE)
	var rx0: int = out.ox * SimConfig.CELL - margin
	var ry0: int = out.oy * SimConfig.CELL - margin
	var rx1: int = (out.ox + out.w) * SimConfig.CELL + margin
	var ry1: int = (out.oy + out.h) * SimConfig.CELL + margin
	world.query_rect(rx0, ry0, rx1, ry1, near, need)
	var org: PackedInt32Array = PackedInt32Array([0, 0])
	for id: int in near:
		var e: SimEntity = world.get_entity(id)
		if e == null or (e.flags & SimFlags.F_GONE) != 0 or e.kind != SimEntity.Kind.STRUCTURE:
			continue
		if not _has_apron(world, e.def_idx):
			continue
		var fp: MapFootprint = footprint_of_def(world, e.def_idx)
		var eo: int = ((e.facing >> 10) & 3) if fp.rotatable else 0
		entity_origin(world, e, org)
		var xc: int = exit_cell(world, e.def_idx, org[0], org[1], eo)
		if xc >= 0 and solid.has(xc):
			_mark(out, xc % map.w, xc / map.w, SimEconConst.CF_APRON)
			ok = false
	return ok


## Producers with an exit cell outside their footprint (a def whose exit lies inside it carries no apron data).
static func _has_apron(world: SimWorld, s_idx: int) -> bool:
	var d: DefStructure = world.data.structures[s_idx]
	if d.queue_kind != DefEnums.QueueKind.INFANTRY and d.queue_kind != DefEnums.QueueKind.VEHICLE \
			and d.queue_kind != DefEnums.QueueKind.AIRCRAFT and d.queue_kind != DefEnums.QueueKind.COLLECTOR:
		return false
	var fp: MapFootprint = footprint_of_def(world, s_idx)
	return d.exit_dx < 0 or d.exit_dx >= fp.w or d.exit_dy < 0 or d.exit_dy >= fp.h


static func _berth_ok(world: SimWorld, d: DefStructure, cx: int, cy: int, orient: int, fp: MapFootprint) -> bool:
	var map: MapData = world.map
	var berth: PackedInt32Array = PackedInt32Array()
	var o: PackedInt32Array = PackedInt32Array([0, 0])
	for dy: int in range(d.fp_h, d.fp_h + DOCK_BERTH_ROWS):
		for dx: int in d.fp_w:
			MapFootprint.rotate_offset(fp.w, fp.h, orient, dx, dy, o)
			var x: int = cx + o[0]
			var y: int = cy + o[1]
			if not map.in_bounds(x, y):
				return false
			berth.append(map.idx(x, y))
	# every berth cell is DEEP water of one water body of >= MIN_WATER_BODY cells (no puddle docks). Not
	# MapBuildRules.check_berth: its naval-component test reads the SZ_2 clearance graph, and a berth cell next to
	# the shore has clearance 1, so it would refuse every real dock (see the cross-module request).
	return MapBuildRules.berth_in_deep_body(map, berth, MIN_WATER_BODY)


## Strategic structures the player owns (BUILDUP + ACTIVE launchers) for the max-one rule.
static func _owned_of_limit(world: SimWorld, pid: int) -> int:
	var n: int = 0
	for e: SimEntity in world.structures_of(pid):
		if (e.flags & SimFlags.F_GONE) != 0 or e.econ == null:
			continue
		if e.econ.st != SimEconConst.ST_BUILDUP and e.econ.st != SimEconConst.ST_ACTIVE:
			continue
		if (world.data.structures[e.def_idx].flags & DefEnums.SF_STRATEGIC) != 0:
			n += 1
	return n
