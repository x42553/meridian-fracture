class_name SimExitMove
extends RefCounted
## Exits, spawn placement and eject (terrain_movement 5.9). The glide itself lives in SimMovement.glide /
## SimMovementSystem (MS_GLIDE); this file holds the cell searches and the MS_EVICT fallback.

const EJECT_RINGS: int = 6
const EVICT_RINGS: int = 12
const EVICT_TICKS: int = 40  ## a boxed-in unit drives out for at most this long
const EVICT_ARRIVE: int = 384  ## units from the exit cell centre
const EVICT_MIN_STEP: int = 64  ## units per tick
const CLEAR_RADIUS: int = 600  ## another same-layer entity centre closer than this to the cell centre blocks it


## Default profile by layer (5.9): GROUND -> wheeled size 2 (conservative for infantry too), SURFACE -> naval size 2,
## UNDERWATER -> sub size 2. Returns the nav profile, -1 for AIR (the cell itself always qualifies).
static func profile_of_layer(layer: int) -> int:
	match layer:
		SimEntity.Layer.SURFACE:
			return MapTerrain.NP_NAVAL
		SimEntity.Layer.UNDERWATER:
			return MapTerrain.NP_SUB
		SimEntity.Layer.AIR:
			return -1
	return MapTerrain.NP_WHEELED


## Cell index `k` (0-based) of ring `r` around (cx, cy) in the domain-wide walk (top row left to right, right column top
## to bottom, bottom row right to left, left column bottom to top); r = 0 is the centre. Returns packed dx | dy << 16
## with a +32768 bias on both, or -1 past the end of the ring.
static func ring_cell(r: int, k: int) -> int:
	if r == 0:
		return (32768 | (32768 << 16)) if k == 0 else -1
	var side: int = 2 * r
	if k < 0 or k >= 4 * side:
		return -1
	var dx: int
	var dy: int
	if k < side:  # top row, left -> right (the last cell belongs to the right column)
		dx = -r + k
		dy = -r
	elif k < 2 * side:  # right column, top -> bottom
		dx = r
		dy = -r + (k - side)
	elif k < 3 * side:  # bottom row, right -> left
		dx = r - (k - 2 * side)
		dy = r
	else:  # left column, bottom -> top
		dx = -r
		dy = r - (k - 3 * side)
	return (dx + 32768) | ((dy + 32768) << 16)


## True when cell (x, y) can take a fresh unit of the layer: passable for the default profile, no structure on it and no
## same-layer non-ghost entity centred within CLEAR_RADIUS. `skip_rect` (x0, y0, x1, y1 inclusive) is excluded.
static func cell_free(world: SimWorld, x: int, y: int, layer: int, buf: PackedInt32Array, skip_rect: PackedInt32Array = PackedInt32Array(), exclude: int = -1) -> bool:
	var map: MapData = world.map
	if x < 0 or y < 0 or x >= map.w or y >= map.h:
		return false
	if not skip_rect.is_empty() and x >= skip_rect[0] and x <= skip_rect[2] and y >= skip_rect[1] and y <= skip_rect[3]:
		return false
	var i: int = y * map.w + x
	var np: int = profile_of_layer(layer)
	if np >= 0:
		if not map.nav.passable(np, 2, i) or map.occupant_at(i) >= 0:
			return false
	buf.resize(0)
	world.query_circle(x * SimConfig.CELL + SimConfig.CELL / 2, y * SimConfig.CELL + SimConfig.CELL / 2, CLEAR_RADIUS, buf, SimTag.ALIVE | SimTag.layer_bit(layer))
	for id: int in buf:
		if id == exclude:
			continue
		var o: SimEntity = world.by_id[id]
		if (o.flags & SimFlags.F_NO_COLLISION) == 0 and (o.kind == SimEntity.Kind.UNIT or o.kind == SimEntity.Kind.STRUCTURE):
			return false
	return true


## First qualifying cell of rings 0..max_radius (ring order of ring_cell) around `cell`; -1 if none.
static func find_free_cell_near(world: SimWorld, cell: int, layer: int, max_radius: int) -> int:
	return _search(world, cell, layer, max_radius, PackedInt32Array(), -1)


static func _search(world: SimWorld, cell: int, layer: int, max_radius: int, skip_rect: PackedInt32Array, exclude: int) -> int:
	var map: MapData = world.map
	var cx: int = cell % map.w
	var cy: int = cell / map.w
	var buf: PackedInt32Array = PackedInt32Array()
	if layer == SimEntity.Layer.AIR:
		return cell
	for r: int in range(0, max_radius + 1):
		var k: int = 0
		while true:
			var p: int = ring_cell(r, k)
			if p < 0:
				break
			var x: int = cx + (p & 0xFFFF) - 32768
			var y: int = cy + (p >> 16) - 32768
			if cell_free(world, x, y, layer, buf, skip_rect, exclude):
				return y * map.w + x
			k += 1
	return -1


## Units of `team` (world.team_of(owner)) with a ground / surface layer centred in the inclusive cell rect move out in
## ascending id to the nearest qualifying cell outside it (EJECT_RINGS rings); a unit with none starts MS_EVICT toward
## the nearest structure-free cell outside the rectangle (EVICT_RINGS rings), or stays if there is not even that.
static func eject_units_from_rect(world: SimWorld, x0: int, y0: int, x1: int, y1: int, team: int) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	world.query_rect(x0 * SimConfig.CELL, y0 * SimConfig.CELL, (x1 + 1) * SimConfig.CELL - 1, (y1 + 1) * SimConfig.CELL - 1, ids, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
	var map: MapData = world.map
	var rect: PackedInt32Array = PackedInt32Array([x0, y0, x1, y1])
	for id: int in ids:
		var e: SimEntity = world.by_id[id]
		if e.move == null or e.team != team or e.layer == SimEntity.Layer.AIR or (e.flags & (SimFlags.F_INSIDE | SimFlags.F_GONE)) != 0:
			continue
		var cell: int = clampi(e.y >> 10, 0, map.h - 1) * map.w + clampi(e.x >> 10, 0, map.w - 1)
		var found: int = _search(world, cell, e.layer, EJECT_RINGS, rect, e.id)
		if found >= 0:
			SimMovement.stop(world, e, true)
			world.set_pos(e, (found % map.w) * SimConfig.CELL + SimConfig.CELL / 2, (found / map.w) * SimConfig.CELL + SimConfig.CELL / 2)
			continue
		var exit_cell: int = _evict_target(world, e, cell, rect)
		if exit_cell >= 0:
			start_evict(world, e, exit_cell)


## Nearest cell outside `rect` with no structure that the unit's own profile accepts (units ignored), -1 if none.
static func _evict_target(world: SimWorld, e: SimEntity, cell: int, rect: PackedInt32Array) -> int:
	var map: MapData = world.map
	var cx: int = cell % map.w
	var cy: int = cell / map.w
	var mv: SimCompMove = e.move
	for r: int in range(1, EVICT_RINGS + 1):
		var k: int = 0
		while true:
			var p: int = ring_cell(r, k)
			if p < 0:
				break
			var x: int = cx + (p & 0xFFFF) - 32768
			var y: int = cy + (p >> 16) - 32768
			k += 1
			if x < 0 or y < 0 or x >= map.w or y >= map.h:
				continue
			if x >= rect[0] and x <= rect[2] and y >= rect[1] and y <= rect[3]:
				continue
			var i: int = y * map.w + x
			if map.nav.passable(mv.np, mv.nav_size, i) and map.occupant_at(i) < 0:
				return i
	return -1


## Starts the drive-out of a boxed-in unit toward `exit_cell` (centre), ignoring cell weights for EVICT_TICKS ticks.
static func start_evict(world: SimWorld, e: SimEntity, exit_cell: int) -> void:
	var mv: SimCompMove = e.move
	var map: MapData = world.map
	SimMovement.stop(world, e, true)
	mv.goal_kind = SimMoveConfig.GK_EVICT
	mv.goal_x = (exit_cell % map.w) * SimConfig.CELL + SimConfig.CELL / 2
	mv.goal_y = (exit_cell / map.w) * SimConfig.CELL + SimConfig.CELL / 2
	mv.goal_tick = world.tick
	mv.goal_target = -1
	mv.result = SimMoveConfig.RS_NONE
	mv.state = SimMoveConfig.MS_EVICT
