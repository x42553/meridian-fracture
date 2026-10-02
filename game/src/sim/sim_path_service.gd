class_name SimPathService
extends RefCounted
## Path request queue, priorities, cache, group attach and the per-tick work budget (terrain_movement 4.7 / 5.3.5).
## Runs first thing in SimMovementSystem.update. All budgets are counts of work units (DR-11); the request table is
## struct-of-arrays, slots recycled through a LIFO free list; the cache is a Dictionary with int keys that is only
## looked up and evicted through a FIFO ring, never iterated (DR-6).

const PRIO_ORDER: int = 0
const PRIO_ECON: int = 1
const PRIO_REPATH: int = 2
## request flags
const RQ_REPATH: int = 1  ## a failure leaves the unit's current path/state alone
const RQ_ALT: int = 2  ## the goal was replaced by an alternative reachable cell: the result is partial

var map: MapData = null
var search: MapPathSearch = null
var last_units: int = 0  ## units charged by the last process() call (diagnostic, <= its budget)
var last_budget: int = 0
var stat_searches: int = 0  ## diagnostics (not hashed): searches started, cache/attach hits, deliveries, failures
var stat_hits: int = 0
var stat_delivered: int = 0
var stat_failed: int = 0

var r_ent: PackedInt32Array = PackedInt32Array()
var r_np: PackedInt32Array = PackedInt32Array()
var r_size: PackedInt32Array = PackedInt32Array()
var r_start: PackedInt32Array = PackedInt32Array()
var r_goal: PackedInt32Array = PackedInt32Array()
var r_goal_r: PackedInt32Array = PackedInt32Array()
var r_prio: PackedInt32Array = PackedInt32Array()
var r_flags: PackedInt32Array = PackedInt32Array()
var r_seq: PackedInt32Array = PackedInt32Array()
var r_state: PackedInt32Array = PackedInt32Array()  ## 0 free / 1 queued / 2 active
var r_first: PackedInt32Array = PackedInt32Array()  ## tick of the first dirty-graph deferral, -1 none
var r_hold: PackedInt32Array = PackedInt32Array()  ## skipped while tick < r_hold
var r_avoid: Array[PackedInt32Array] = []

var _free: PackedInt32Array = PackedInt32Array()
var _q: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
var _seq: int = 0
var _active: int = -1
var _slot_of: Dictionary = {}  ## entity id -> slot (keyed lookups only)
var _pending: int = 0

var _cache: Dictionary = {}  ## key -> ring index
var c_keys: PackedInt64Array = PackedInt64Array()
var c_paths: Array[PackedInt32Array] = []
var c_ver: PackedInt32Array = PackedInt32Array()
var c_born: PackedInt32Array = PackedInt32Array()
var _c_used: int = 0
var _c_next: int = 0


func _init(p_map: MapData) -> void:
	map = p_map
	search = MapPathSearch.new(p_map.nav)
	c_keys.resize(SimMoveConfig.CACHE_CAP)
	c_ver.resize(SimMoveConfig.CACHE_CAP)
	c_born.resize(SimMoveConfig.CACHE_CAP)
	for _i: int in SimMoveConfig.CACHE_CAP:
		c_paths.append(PackedInt32Array())


# ---- public API ---------------------------------------------------------------------------------------------------

## Queues a path request for `e` (start = its current cell, np / size from e.move); replaces the entity's previous
## request. Returns the request id (> 0), also stored in e.move.req_id.
func request(e: SimEntity, goal_cell: int, goal_r: int, prio: int, flags: int, avoid: PackedInt32Array = PackedInt32Array()) -> int:
	var mv: SimCompMove = e.move
	cancel(e.id)
	var slot: int
	if _free.is_empty():
		slot = r_ent.size()
		for arr: PackedInt32Array in [r_ent, r_np, r_size, r_start, r_goal, r_goal_r, r_prio, r_flags, r_seq, r_state, r_first, r_hold]:
			arr.append(0)
		r_avoid.append(PackedInt32Array())
	else:
		slot = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
	var w: int = map.w
	var cx: int = clampi(e.x >> 10, 0, w - 1)
	var cy: int = clampi(e.y >> 10, 0, map.h - 1)
	_seq += 1
	r_ent[slot] = e.id
	r_np[slot] = mv.np
	r_size[slot] = mv.nav_size
	r_start[slot] = cy * w + cx
	r_goal[slot] = goal_cell
	r_goal_r[slot] = goal_r
	r_prio[slot] = clampi(prio, 0, 2)
	r_flags[slot] = flags
	r_seq[slot] = _seq
	r_state[slot] = 1
	r_first[slot] = -1
	r_hold[slot] = 0
	r_avoid[slot] = avoid
	_q[r_prio[slot]].append(slot)
	_slot_of[e.id] = slot
	_pending += 1
	mv.req_id = _seq
	return _seq


## Drops the entity's request (queued or active); an active search is aborted.
func cancel(entity_id: int) -> void:
	var slot: int = _slot_of.get(entity_id, -1)
	if slot < 0:
		return
	_release(slot)


func pending() -> int:
	return _pending


func invalidate_cache() -> void:
	_cache.clear()
	_c_used = 0
	_c_next = 0


## Stage 6 step (b): drains the queue within the tick's unit budget (5.3.5).
func process(world: SimWorld) -> void:
	var nav: MapNav = map.nav
	var budget: int = SimMoveConfig.PATH_BASE + SimMoveConfig.PATH_PER_PENDING * mini(_pending, SimMoveConfig.PATH_PENDING_CAP)
	last_budget = budget
	var units: int = 0
	var deliveries: int = 0
	while units < budget and deliveries < SimMoveConfig.PATH_MAX_DELIVERIES:
		if _active < 0:
			var slot: int = _pick(world, nav)
			if slot < 0:
				break
			units = mini(units + 1, budget)  # the snap
			if _begin(world, nav, slot):
				deliveries += 1
			if _active < 0:
				continue
		var used: int = search.step(budget - units)
		units += used
		if search.status == MapPathSearch.ST_RUNNING:
			break
		_finish_search(world, nav)
		deliveries += 1
	last_units = mini(units, budget)


## Appends: seq, queue contents, live request slots, the free list, the search state, the cache ring (5.3.5 / 8).
func state_ints(buf: PackedInt32Array) -> void:
	buf.append(_seq)
	buf.append(_active)
	for p: int in 3:
		buf.append(_q[p].size())
		buf.append_array(_q[p])
	for s: int in r_ent.size():
		if r_state[s] == 0:
			continue
		buf.append(s)
		buf.append(r_ent[s])
		buf.append(r_start[s])
		buf.append(r_goal[s])
		buf.append(r_goal_r[s])
		buf.append(r_flags[s])
		buf.append(r_seq[s])
		buf.append(r_state[s])
		buf.append(r_first[s])
		buf.append(r_hold[s])
		buf.append(r_avoid[s].size())
		buf.append_array(r_avoid[s])
	buf.append(_free.size())
	buf.append_array(_free)
	search.state_ints(buf)
	buf.append(_c_used)
	buf.append(_c_next)
	for i: int in _c_used:
		buf.append(c_keys[i] & 0xFFFFFFFF)
		buf.append(c_keys[i] >> 32)
		buf.append(c_ver[i])
		buf.append(c_born[i])
		var p: PackedInt32Array = c_paths[i]
		buf.append(p.size())
		buf.append(Checksum.digest32(p))


# ---- internals ---------------------------------------------------------------------------------------------------

func _release(slot: int) -> void:
	if r_state[slot] == 0:
		return
	if r_state[slot] == 2:
		search.cancel()
		_active = -1
	else:
		var q: PackedInt32Array = _q[r_prio[slot]]
		var i: int = q.find(slot)
		if i >= 0:
			q.remove_at(i)
	_slot_of.erase(r_ent[slot])
	r_state[slot] = 0
	r_avoid[slot] = PackedInt32Array()
	_free.append(slot)
	_pending -= 1


func _octile(a: int, b: int) -> int:
	var w: int = map.w
	var dx: int = absi(a % w - b % w)
	var dy: int = absi(a / w - b / w)
	return 10 * (dx + dy) - 6 * mini(dx, dy)


## First queued request (priority order, FIFO) that is not held back this tick; removed from its queue.
func _pick(world: SimWorld, nav: MapNav) -> int:
	var dirty: bool = nav.pending_dirty() > 0
	for p: int in 3:
		var q: PackedInt32Array = _q[p]
		var i: int = 0
		while i < q.size():
			var slot: int = q[i]
			if r_hold[slot] > world.tick:
				i += 1
				continue
			if dirty and r_flags[slot] & RQ_ALT == 0 and _needs_abstract(nav, slot):
				if r_first[slot] < 0:
					r_first[slot] = world.tick
				if world.tick - r_first[slot] < SimMoveConfig.PATH_DIRTY_WAIT:
					r_hold[slot] = world.tick + 1
					i += 1
					continue
			q.remove_at(i)
			r_state[slot] = 2
			return slot
	return -1


## A request the abstract phase would serve (long, no direct line) must wait for a dirty graph.
func _needs_abstract(nav: MapNav, slot: int) -> bool:
	if _octile(r_start[slot], r_goal[slot]) < MapPathSearch.HIER_MIN_OCTILE:
		return false
	var lc: int = nav.los_cost(r_np[slot], r_size[slot], r_start[slot], r_goal[slot])
	return lc < 0 or lc > _octile(r_start[slot], r_goal[slot]) * 5 / 4


## Snap / trivial / cache / reachability, then starts the search. Returns true when the request finished here.
func _begin(world: SimWorld, nav: MapNav, slot: int) -> bool:
	var np: int = r_np[slot]
	var size: int = r_size[slot]
	var s: int = r_start[slot]
	var g: int = r_goal[slot]
	if nav.clear_at(np, s) < size:
		s = nav.nearest_passable(np, size, s, 3)
	if s >= 0 and nav.clear_at(np, g) < size:
		g = nav.nearest_passable(np, size, g, 6)
	if s < 0 or g < 0:
		_fail(world, slot, SimMoveConfig.RS_NO_PATH)
		return true
	r_start[slot] = s
	r_goal[slot] = g
	var goal_r: int = r_goal_r[slot]
	var w: int = map.w
	if s == g or (goal_r > 0 and maxi(absi(s % w - g % w), absi(s / w - g / w)) <= goal_r):
		_deliver(world, slot, PackedInt32Array(), 0, false)
		return true
	var use_cache: bool = r_avoid[slot].is_empty() and (r_flags[slot] & RQ_ALT) == 0
	var key: int = 0
	if use_cache:
		key = _cache_key(nav, np, size, s, g, goal_r)
		var hit: int = _cache_lookup(world, nav, key, s, np, size)
		if hit >= 0:
			stat_hits += 1
			var k: int = hit & 0xFFFF
			_deliver(world, slot, c_paths[hit >> 16], k, false)
			return true
	# reachability (5.3.5 step 4)
	if nav.has_graph(np, size):
		var rs: int = nav.region_id(np, size, s)
		var rg: int = nav.region_id(np, size, g)
		if rs < 0 or rg < 0 or rs != rg:
			if nav.pending_dirty() > 0:
				if r_first[slot] < 0:
					r_first[slot] = world.tick
				if world.tick - r_first[slot] < SimMoveConfig.PATH_DIRTY_WAIT:
					r_hold[slot] = world.tick + 1
					r_state[slot] = 1
					_q[r_prio[slot]].insert(0, slot)
					return false
			var alt: int = _alt_goal(nav, np, size, g, rs)
			if alt < 0:
				_fail(world, slot, SimMoveConfig.RS_NO_PATH)
				return true
			r_goal[slot] = alt
			r_goal_r[slot] = 0
			r_flags[slot] |= RQ_ALT
			g = alt
			goal_r = 0
			use_cache = false
	stat_searches += 1
	search.begin(np, size, s, g, goal_r, r_avoid[slot])
	_active = slot
	if search.status != MapPathSearch.ST_RUNNING:
		_finish_search(world, nav)
		return true
	return false


func _cache_key(nav: MapNav, np: int, size: int, s: int, g: int, goal_r: int) -> int:
	var node: int = nav.node_of(np, size, s) + 1
	return g | (np << 20) | (size << 23) | (goal_r << 25) | (node << 30)


## Returns (ring index << 16) | k for a valid entry the follower can attach to, else -1.
func _cache_lookup(world: SimWorld, nav: MapNav, key: int, s: int, np: int, size: int) -> int:
	var ci: int = _cache.get(key, -1)
	if ci < 0:
		return -1
	if c_ver[ci] != map.nav_version or world.tick - c_born[ci] > SimMoveConfig.CACHE_TTL:
		return -1
	var p: PackedInt32Array = c_paths[ci]
	var lim: int = mini(5, p.size() - 1)
	for k: int in range(0, lim + 1):
		if nav.los(np, size, s, p[k]):
			return (ci << 16) | k
	return -1


func _cache_store(world: SimWorld, key: int, path: PackedInt32Array) -> void:
	var ci: int = _cache.get(key, -1)
	if ci < 0:
		ci = _c_next
		if _c_used == SimMoveConfig.CACHE_CAP:
			_cache.erase(c_keys[ci])
		else:
			_c_used += 1
		_c_next = (_c_next + 1) % SimMoveConfig.CACHE_CAP
		c_keys[ci] = key
		_cache[key] = ci
	c_paths[ci] = path
	c_ver[ci] = map.nav_version
	c_born[ci] = world.tick


## Rings 1..ALT_GOAL_RINGS around `goal`: the cell of the start's region with the least octile distance to the goal
## (ties: lowest index) within the first ring holding a candidate plus the next ring. -1 if none.
func _alt_goal(nav: MapNav, np: int, size: int, goal: int, rs: int) -> int:
	if rs < 0:
		return -1
	var w: int = map.w
	var h: int = map.h
	var cl: PackedByteArray = nav.clr_array(np)
	var gx: int = goal % w
	var gy: int = goal / w
	var best: int = -1
	var best_d: int = 0
	var found_ring: int = -1
	for r: int in range(1, SimMoveConfig.ALT_GOAL_RINGS + 1):
		if found_ring >= 0 and r > found_ring + 1:
			break
		var x0: int = gx - r
		var x1: int = gx + r
		var y0: int = gy - r
		var y1: int = gy + r
		for y: int in range(maxi(y0, 0), mini(y1, h - 1) + 1):
			var edge_row: bool = y == y0 or y == y1
			var step: int = 1 if edge_row else 2 * r
			var x: int = x0
			while x <= x1:
				if x >= 0 and x < w:
					var c: int = y * w + x
					if cl[c] >= size and nav.region_id(np, size, c) == rs:
						var d: int = _octile(c, goal)
						if best < 0 or d < best_d or (d == best_d and c < best):
							best = c
							best_d = d
							if found_ring < 0:
								found_ring = r
				x += step
	return best


func _finish_search(world: SimWorld, nav: MapNav) -> void:
	var slot: int = _active
	_active = -1
	var st: int = search.status
	var path: PackedInt32Array = search.path
	if st == MapPathSearch.ST_DONE:
		var np: int = r_np[slot]
		if r_avoid[slot].is_empty() and (r_flags[slot] & RQ_ALT) == 0 and not path.is_empty():
			_cache_store(world, _cache_key(nav, np, r_size[slot], r_start[slot], r_goal[slot], r_goal_r[slot]), path)
		_deliver(world, slot, path, 0, (r_flags[slot] & RQ_ALT) != 0)
	elif st == MapPathSearch.ST_PARTIAL:
		_deliver(world, slot, path, 0, true)
	else:
		_fail(world, slot, SimMoveConfig.RS_NO_PATH)


func _deliver(world: SimWorld, slot: int, path: PackedInt32Array, wp0: int, partial: bool) -> void:
	var e: SimEntity = world.get_entity(r_ent[slot])
	var id: int = r_seq[slot]
	var goal: int = r_goal[slot]
	var alt: bool = (r_flags[slot] & RQ_ALT) != 0
	_release(slot)
	stat_delivered += 1
	if e == null or e.move == null or e.move.req_id != id:
		return
	var m: SimCompMove = e.move
	m.path = path
	m.wp = wp0
	m.path_ver = map.nav_version
	m.req_id = 0
	m.wait = 0
	m.goal_cell = goal
	if not alt and m.goal_kind == SimMoveConfig.GK_POINT and m.route_x < 0:  # (a formation slot keeps its own goal)
		var w: int = map.w
		if (m.goal_y >> 10) * w + (m.goal_x >> 10) != goal:  # the goal cell was snapped to a passable one
			m.goal_x = (goal % w) * 1024 + 512
			m.goal_y = (goal / w) * 1024 + 512
	if partial or alt:
		m.flags |= SimMoveConfig.MF_PATH_PARTIAL
	else:
		m.flags &= ~SimMoveConfig.MF_PATH_PARTIAL
	if m.state == SimMoveConfig.MS_WAIT_PATH:
		m.state = SimMoveConfig.MS_MOVING


func _fail(world: SimWorld, slot: int, code: int) -> void:
	var e: SimEntity = world.get_entity(r_ent[slot])
	var id: int = r_seq[slot]
	var quiet: bool = (r_flags[slot] & RQ_REPATH) != 0
	_release(slot)
	stat_failed += 1
	if e == null or e.move == null or e.move.req_id != id:
		return
	var m: SimCompMove = e.move
	m.req_id = 0
	if quiet:
		return
	m.state = SimMoveConfig.MS_NO_PATH
	m.result = code
	m.goal_kind = SimMoveConfig.GK_NONE
