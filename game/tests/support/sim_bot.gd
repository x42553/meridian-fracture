class_name SimBot
extends RefCounted
## A scripted, roster-agnostic skirmish BOT: the seed of the future AI module (src/ai). It plays one pid using ONLY
## public commands (SimCmd builders submitted with SimWorld.submit_raw) and read queries (world.players[..].econ,
## world.production.q_*, world.economy.q_*, world.power, world.units_of / structures_of, SimPlacement.find_site,
## world.visible_enemy_ids). It never writes world state, never draws random numbers and never reads floats, so a
## match with bots is as deterministic as the sim itself: same world + same bots => identical checksum chain.
##
## Usage:  var bot := SimBot.new(pid, {"enemy_starts": [Vector2i cells...]})
##         each tick, before world.step():  bot.think(world)
## think() acts every THINK_INTERVAL ticks (staggered per pid), so 8 bots cost little.
##
## Strategy (all decisions come from DefPlayerView / DefRoster data, never from unit or structure ids):
##  * BUILD LADDER: an ordered list of structure ROLES (power, refinery, barracks, factory, tech, ...) resolved against the
##    roster (cheapest producible def of the role). The first unsatisfied entry whose prerequisites exist is queued when
##    the construction queue is idle; a ready item is placed with SimPlacement.find_site near the HQ (refineries lean
##    toward the nearest deposit field, defences toward the enemy). A generator is inserted whenever the next consumer
##    would overdraw the grid. Because entries are COUNT based the ladder also rebuilds destroyed structures.
##  * PRODUCTION: every ACTIVE barracks / factory keeps up to 2 units queued. The unit is chosen by ROLE (tank, infantry,
##    artillery, light vehicle, anti-air) from tags, filling the role that is furthest below its target share, then the
##    highest tier / cost the roster offers. Refineries queue Collectors up to 2 per refinery.
##  * ARMY: producers rally at a point on the way to the enemy. Once the idle army reaches the wave size the bot
##    attack-moves everybody at the nearest KNOWN enemy structure (seen through world.visible_enemy_ids and remembered;
##    the enemy start cells of the match config are the fallback); reinforcements follow while the attack is on.
##
## Options (opts): variety (bool: rotate through every affordable unit def of a role, the soak uses it), research (bool: queue the cheapest available research), air / naval (bool: also build Airfields / Docks from the ladder entries "airfield" / "dock" and fly / sail
## what they produce), ladder (PackedStringArray of role names), interval, first_attack_tick, wave_size,
## wave_growth_ticks, retreat_below, rally_dist, enemy_starts.
## Not covered yet (future AI work): research, powers / superweapons, expansion, scouting, defending, repair / sell,
## engineers, transports, real air / naval tactics (aircraft and ships only receive attack-move orders).

const THINK_INTERVAL: int = 10
const QUEUE_DEPTH: int = 2  ## units kept queued per producer
const ROLE_NONE: int = -1
# structure roles
const R_HQ: int = 0
const R_POWER: int = 1
const R_REFINERY: int = 2
const R_BARRACKS: int = 3
const R_FACTORY: int = 4
const R_TECH: int = 5
const R_DEFENSE: int = 6
const R_AIRFIELD: int = 7
const R_DOCK: int = 8
const R_OTHER: int = 9
const R_COUNT: int = 10
# unit roles
const U_TANK: int = 0
const U_INFANTRY: int = 1
const U_ARTILLERY: int = 2
const U_LIGHT: int = 3
const U_ANTI_AIR: int = 4
const U_AIR: int = 5  ## aircraft (only with opts.air)
const U_SHIP: int = 6  ## ships (only with opts.naval)
const U_COLLECTOR: int = 7
const U_SKIP: int = 8
const U_COUNT: int = 9
## Target army share per combat role (parts of 100); a producer only offers the roles it can build.
const SHARE: PackedInt32Array = [40, 30, 10, 10, 10, 30, 30]
## Default ladder: role names in build order. Repeated names mean "one more".
const DEFAULT_LADDER: PackedStringArray = [
	"power", "refinery", "barracks", "factory", "tech", "power", "refinery", "barracks", "factory", "power",
	"tech", "defense", "defense", "power", "factory", "defense", "defense", "power",
]

var pid: int = 0
var opts: Dictionary = {}
## Optional recorder: when set, every command is submitted through it (SimCommandLog.submit) so a match can be replayed.
var cmd_log: SimCommandLog = null
## Counters for tests and reports.
var stats: Dictionary = {"structures_started": 0, "structures_placed": 0, "place_failed": 0, "units_queued": 0, "waves": 0, "attack_orders": 0, "thinks": 0}

var _ready: bool = false
var _ladder: Array[Vector2i] = []  ## (structure def index, needed count)
var _gen_def: int = -1
var _s_role: PackedInt32Array = PackedInt32Array()  ## per structure def
var _u_role: PackedInt32Array = PackedInt32Array()  ## per unit def
var _hq_cx: int = 0
var _hq_cy: int = 0
var _enemy_cells: Array[Vector2i] = []  ## start cells of the enemy players
var _enemy_pids: PackedInt32Array = PackedInt32Array()  ## their pids (-1 = from opts, always valid)
var _rally_x: int = 0
var _rally_y: int = 0
var _rally_set: Dictionary = {}  ## producer id -> true
var _attacking: bool = false
var _target_id: int = 0
var _target_x: int = 0
var _target_y: int = 0
var _last_go: Dictionary = {}  ## unit id -> tick of its last attack order
var _known: Dictionary = {}  ## enemy structure id -> Vector3i(x, y, def)
var _site: PackedInt32Array = PackedInt32Array([0, 0])
var _tmp: PackedInt32Array = PackedInt32Array()
var _place_wait: int = 0  ## tick before which a READY item is not re-placed (rejected placements)
var _place_fail: int = 0


func _init(p_pid: int, p_opts: Dictionary = {}) -> void:
	pid = p_pid
	opts = p_opts.duplicate()
	for c: Variant in opts.get("enemy_starts", []):
		_enemy_cells.append(c as Vector2i)
		_enemy_pids.append(-1)


## Call once per tick before world.step().
func think(world: SimWorld) -> void:
	if world.match_state != SimWorld.MATCH_RUNNING or pid >= world.players.size() or world.players[pid].eliminated != 0:
		return
	if (world.tick + pid * 3) % int(opts.get("interval", THINK_INTERVAL)) != 0:
		return
	if not _ready and not _setup(world):
		_deploy_mcv(world)  # START_MCV matches: the first job is unfolding the MCV
		return
	stats["thinks"] = int(stats["thinks"]) + 1
	_scan_enemies(world)
	_manage_construction(world)
	_manage_production(world)
	_manage_research(world)
	_manage_army(world)


## THE only way the bot acts: one command, as the int array a network peer would send.
func _send(world: SimWorld, ints: PackedInt32Array) -> void:
	if cmd_log != null:
		cmd_log.submit(world, pid, ints)
	else:
		world.submit_raw(pid, ints)


## Rally point in sub-cell units (valid after the first think).
func rally_point() -> Vector2i:
	return Vector2i(_rally_x, _rally_y)


## Enemy structures currently remembered.
func known_structures() -> int:
	return _known.size()


# ------------------------------------------------------------------------------------------------------ setup
func _setup(world: SimWorld) -> bool:
	var hq: SimEntity = null
	for s: SimEntity in world.structures_of(pid):
		if (s.flags & SimFlags.F_GONE) == 0 and world.data.structures[s.def_idx].build_radius > 0:
			hq = s
			break
	if hq == null:
		return false  # no HQ (yet): nothing to anchor on
	_hq_cx = hq.x >> SimConfig.CELL_SHIFT
	_hq_cy = hq.y >> SimConfig.CELL_SHIFT
	var d: GameData = world.data
	var roster: DefRoster = world.players[pid].roster
	_s_role.resize(d.structures.size())
	_s_role.fill(ROLE_NONE)
	for s_idx: int in d.structures.size():
		_s_role[s_idx] = _structure_role(world, s_idx)
	_u_role.resize(d.units.size())
	_u_role.fill(U_SKIP)
	for u_idx: int in d.units.size():
		_u_role[u_idx] = _unit_role(d.units[u_idx])
	# enemy start cells: from the option, else every other player's spawn record
	if _enemy_cells.is_empty():
		for s: SimPlayerSlot in world.config.players:
			if s.pid != pid and not world.are_allied(pid, s.pid):
				var rec: int = s.start * MapData.SPAWN_STRIDE
				if rec + 1 < world.map.spawns.size():
					var cell: int = world.map.spawns[rec + 1]
					_enemy_cells.append(Vector2i(cell % world.map.w, cell / world.map.w))
					_enemy_pids.append(s.pid)
	_rally_from_hq(world)
	_resolve_ladder(world, roster)
	_ready = true
	return true


## Unfolds an MCV (a unit whose ability list deploys a structure) when the player has no HQ, once per 100 ticks.
func _deploy_mcv(world: SimWorld) -> void:
	if world.tick - int(stats.get("deploy_tick", -1000)) < 100:
		return
	for u: SimEntity in world.units_of(pid):
		if (u.flags & SimFlags.F_GONE) == 0 and world.defs.is_rebuilder(u.kind, u.def_idx):
			stats["deploy_tick"] = world.tick
			_send(world, SimCmd.deploy(PackedInt32Array([u.id])))
			return


func _structure_role(world: SimWorld, s_idx: int) -> int:
	var sd: DefStructure = world.data.structures[s_idx]
	if sd.build_radius > 0:
		return R_HQ
	if sd.power > 0:
		return R_POWER
	match sd.queue_kind:
		DefEnums.QueueKind.COLLECTOR:
			return R_REFINERY
		DefEnums.QueueKind.INFANTRY:
			return R_BARRACKS
		DefEnums.QueueKind.VEHICLE:
			return R_FACTORY
		DefEnums.QueueKind.AIRCRAFT:
			return R_AIRFIELD
		DefEnums.QueueKind.NAVAL:
			return R_DOCK
	if (sd.flags & (DefEnums.SF_STRATEGIC | DefEnums.SF_NO_BUILD)) != 0 or sd.superweapon >= 0:
		return R_OTHER
	if (sd.flags & DefEnums.SF_POWERED_DEFENSE) != 0 and sd.weapons.size() > 0:
		return R_DEFENSE
	if world.economy.life.power_class_of(s_idx) == SimEconConst.PC_SENSOR:
		return R_TECH
	return R_OTHER


func _unit_role(u: DefUnit) -> int:
	if (u.tags & DefEnums.UT_COLLECTOR) != 0:
		return U_COLLECTOR
	if (u.tags & DefEnums.UT_COMBAT) == 0 or (u.flags & DefEnums.UF_UNARMED) != 0:
		return U_SKIP
	if (u.tags & DefEnums.UT_AIRCRAFT) != 0:
		return U_AIR if bool(opts.get("air", false)) else U_SKIP
	if (u.tags & (DefEnums.UT_SHIP | DefEnums.UT_SUBMARINE)) != 0:
		return U_SHIP if bool(opts.get("naval", false)) else U_SKIP
	if (u.tags & DefEnums.UT_AMPHIBIOUS) != 0:
		return U_SKIP
	if (u.tags & DefEnums.UT_ANTI_AIR) != 0 and (u.tags & DefEnums.UT_TANK) == 0:
		return U_ANTI_AIR
	if (u.tags & DefEnums.UT_TANK) != 0:
		return U_TANK
	if (u.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0:
		return U_ARTILLERY
	if (u.tags & DefEnums.UT_INFANTRY) != 0:
		return U_INFANTRY
	return U_LIGHT


## Cheapest producible def of a role (ties: lowest index); TECH offers several (cheapest first).
func _defs_of_role(world: SimWorld, roster: DefRoster, role: int) -> Array[int]:
	var out: Array[int] = []
	for s_idx: int in roster.producible_structures:
		if _s_role[s_idx] == role:
			out.append(s_idx)
	var view: DefPlayerView = world.players[pid].view
	# insertion sort by (cost, index)
	for i: int in range(1, out.size()):
		var v: int = out[i]
		var j: int = i - 1
		while j >= 0 and (view.struct_cost[out[j]] > view.struct_cost[v] or (view.struct_cost[out[j]] == view.struct_cost[v] and out[j] > v)):
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = v
	return out


func _resolve_ladder(world: SimWorld, roster: DefRoster) -> void:
	var names: PackedStringArray = opts.get("ladder", DEFAULT_LADDER)
	var by_name: Dictionary = {"power": R_POWER, "refinery": R_REFINERY, "barracks": R_BARRACKS, "factory": R_FACTORY, "tech": R_TECH, "defense": R_DEFENSE, "airfield": R_AIRFIELD, "dock": R_DOCK}
	var occurrence: Dictionary = {}
	var need: Dictionary = {}
	var view: DefPlayerView = world.players[pid].view
	# the best generator: most power per credit
	_gen_def = -1
	var best: int = -1
	for s_idx: int in roster.producible_structures:
		if _s_role[s_idx] == R_POWER:
			var score: int = view.struct_power[s_idx] * 1000 / maxi(view.struct_cost[s_idx], 1)
			if score > best:
				best = score
				_gen_def = s_idx
	for n: String in names:
		var role: int = by_name.get(n, ROLE_NONE)
		if role == ROLE_NONE:
			continue
		var k: int = int(occurrence.get(role, 0))
		occurrence[role] = k + 1
		var defs: Array[int] = _defs_of_role(world, roster, role)
		if defs.is_empty():
			continue
		var s_idx: int
		if role == R_TECH:
			if k >= defs.size():
				continue
			s_idx = defs[k]
		elif role == R_POWER:
			s_idx = _gen_def
		elif role == R_DEFENSE:
			s_idx = defs[k % defs.size()]
		else:
			s_idx = defs[0]
		var c: int = int(need.get(s_idx, 0)) + 1
		need[s_idx] = c
		_ladder.append(Vector2i(s_idx, c))


func _rally_from_hq(world: SimWorld) -> void:
	var tx: int = world.map.w / 2
	var ty: int = world.map.h / 2
	if not _enemy_cells.is_empty():
		tx = _enemy_cells[0].x
		ty = _enemy_cells[0].y
	var dx: int = tx - _hq_cx
	var dy: int = ty - _hq_cy
	var m: int = maxi(maxi(absi(dx), absi(dy)), 1)
	var dist: int = int(opts.get("rally_dist", 11))
	var cx: int = clampi(_hq_cx + dx * dist / m, 4, world.map.w - 5)
	var cy: int = clampi(_hq_cy + dy * dist / m, 4, world.map.h - 5)
	_rally_x = cx * SimConfig.CELL + SimConfig.CELL / 2
	_rally_y = cy * SimConfig.CELL + SimConfig.CELL / 2


# ------------------------------------------------------------------------------------------------ intelligence
func _scan_enemies(world: SimWorld) -> void:
	world.visible_enemy_ids(pid, _tmp)
	for id: int in _tmp:
		var e: SimEntity = world.get_entity(id)
		if e != null and e.kind == SimEntity.Kind.STRUCTURE:
			_known[id] = Vector3i(e.x, e.y, e.def_idx)
	# forget structures whose cell we can see and that are gone
	var gone: Array[int] = []
	for id: int in _known:
		var v: Vector3i = _known[id]
		if not world.is_alive(id) and world.cell_visible(pid, v.x >> SimConfig.CELL_SHIFT, v.y >> SimConfig.CELL_SHIFT):
			gone.append(id)
	for id: int in gone:
		_known.erase(id)


# ---------------------------------------------------------------------------------------------- construction
func _own_count(world: SimWorld, s_idx: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ
	var n: int = pe.struct_count[s_idx]  # ACTIVE
	for q: int in pe.cq_def:
		if q == s_idx:
			n += 1
	# structures under construction (placed, BUILDUP)
	for s: SimEntity in world.structures_of(pid):
		if s.def_idx == s_idx and (s.flags & (SimFlags.F_GONE | SimFlags.F_UNDER_CONSTRUCTION)) == SimFlags.F_UNDER_CONSTRUCTION:
			n += 1
	return n


func _manage_construction(world: SimWorld) -> void:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null or pe.active_hq_count == 0:
		return
	var st: PackedInt32Array = PackedInt32Array()
	world.production.construction_state(pid, st)
	if st[0] == 2:  # READY: place it
		_place_ready(world, st[3])
		return
	if not pe.cq_def.is_empty():
		return  # busy (building / paused): one item at a time
	var next: int = _next_structure(world, pe)
	if next < 0:
		return
	_send(world, SimCmd.build_start(next, 1))
	stats["structures_started"] = int(stats["structures_started"]) + 1


func _next_structure(world: SimWorld, pe: SimPlayerEcon) -> int:
	var prod: SimProductionSystem = world.production
	# emergency power: the grid is (about to be) overdrawn and no generator is coming
	if _gen_def >= 0 and world.power.demand(pid) > world.power.supply(pid) and _own_pending(world, pe, _gen_def) == 0:
		if prod.can_queue_structure(world, pid, _gen_def) == SimEconConst.RSN_OK:
			return _gen_def
	for entry: Vector2i in _ladder:
		if _own_count(world, entry.x) >= entry.y:
			continue
		var want: int = _with_prereqs(world, pe, entry.x, 0)
		if want < 0:
			return -1  # a prerequisite is under construction: wait for it
		var rsn: int = prod.can_queue_structure(world, pid, want)
		if rsn == SimEconConst.RSN_OK:
			# a consumer that would overdraw the grid waits behind a generator
			var draw: int = -world.players[pid].view.struct_power[want]
			if draw > 0 and _gen_def >= 0 and world.power.demand(pid) + draw > world.power.supply(pid) and _own_pending(world, pe, _gen_def) == 0 and want != _gen_def:
				return _gen_def
			return want
		if rsn == SimEconConst.RSN_QUEUE_FULL:
			return -1
		# feature off / strategic limit / not in the roster: try the next ladder entry
	return -1


## The structure to queue for wanting `s_idx`: itself when its prerequisites exist, else the first missing prerequisite
## (recursively); -1 when a missing prerequisite is already being built.
func _with_prereqs(world: SimWorld, pe: SimPlayerEcon, s_idx: int, depth: int) -> int:
	if depth > 4:
		return s_idx
	for r: int in world.data.structures[s_idx].requires:
		if pe.struct_count[r] > 0:
			continue
		if _own_count(world, r) > 0:
			return -1
		return _with_prereqs(world, pe, r, depth + 1)
	return s_idx


func _own_pending(world: SimWorld, pe: SimPlayerEcon, s_idx: int) -> int:
	var n: int = 0
	for q: int in pe.cq_def:
		if q == s_idx:
			n += 1
	for s: SimEntity in world.structures_of(pid):
		if s.def_idx == s_idx and (s.flags & (SimFlags.F_GONE | SimFlags.F_UNDER_CONSTRUCTION)) == SimFlags.F_UNDER_CONSTRUCTION:
			n += 1
	return n


func _anchor_for(world: SimWorld, s_idx: int) -> Vector2i:
	var role: int = _s_role[s_idx]
	var toward: Vector2i = Vector2i(_rally_x >> SimConfig.CELL_SHIFT, _rally_y >> SimConfig.CELL_SHIFT)
	if role == R_REFINERY:
		var dep: int = world.economy.q_deposit_nearest(world, pid, _hq_cx * SimConfig.CELL, _hq_cy * SimConfig.CELL, 300)
		if dep >= 0:
			toward = Vector2i(world.economy.deposits.x[dep] >> SimConfig.CELL_SHIFT, world.economy.deposits.y[dep] >> SimConfig.CELL_SHIFT)
			return _lean(toward, 5)
	if role == R_DOCK:
		var wc: int = _nearest_water_cell(world)
		if wc >= 0:
			return Vector2i(wc % world.map.w, wc / world.map.w)
	if role == R_DEFENSE:
		return _lean(toward, 6)
	if role == R_POWER or role == R_TECH:
		return _lean(toward, -4)  # behind the HQ
	return _lean(toward, 3)


## Nearest DEEP water cell within 12 cells of the HQ (ring order), -1 when none.
func _nearest_water_cell(world: SimWorld) -> int:
	var m: MapData = world.map
	for r: int in range(1, 13):
		for y: int in range(_hq_cy - r, _hq_cy + r + 1):
			for x: int in range(_hq_cx - r, _hq_cx + r + 1):
				if maxi(absi(x - _hq_cx), absi(y - _hq_cy)) != r or not m.in_bounds(x, y):
					continue
				if m.kind[y * m.w + x] == MapTerrain.TK_DEEP:
					return y * m.w + x
	return -1


## The cell `dist` steps from the HQ toward `toward` (negative dist = away), Chebyshev-normalised.
func _lean(toward: Vector2i, dist: int) -> Vector2i:
	var dx: int = toward.x - _hq_cx
	var dy: int = toward.y - _hq_cy
	var m: int = maxi(maxi(absi(dx), absi(dy)), 1)
	return Vector2i(_hq_cx + dx * dist / m, _hq_cy + dy * dist / m)


func _place_ready(world: SimWorld, s_idx: int) -> void:
	if s_idx < 0 or world.tick < _place_wait:
		return
	var a: Vector2i = _anchor_for(world, s_idx)
	var rot: int = 0
	var found: bool = false
	if _s_role[s_idx] == R_DOCK:
		# a Dock rotates: try the four orientations against the nearest water
		for r: int in 4:
			if SimPlacement.find_site_rot(world, pid, s_idx, a.x, a.y, 9, r, _site):
				rot = r
				found = true
				break
	else:
		found = SimPlacement.find_site(world, pid, s_idx, a.x, a.y, 9, _site)
	if found:
		_send(world, SimCmd.build_place(s_idx, _site[0], _site[1], rot))
		stats["structures_placed"] = int(stats["structures_placed"]) + 1
		_place_fail = 0
		_place_wait = world.tick + 20  # the command lands next tick; the queue leaves READY a tick later
	else:
		stats["place_failed"] = int(stats["place_failed"]) + 1
		_place_fail += 1
		_place_wait = world.tick + 100
		if _place_fail >= 3:  # nowhere to put it: drop the item so the queue does not stall for ever
			_send(world, SimCmd.build_cancel(0))
			_place_fail = 0


# ------------------------------------------------------------------------------------------------ production
func _manage_production(world: SimWorld) -> void:
	var pe: SimPlayerEcon = world.players[pid].econ
	if pe == null:
		return
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(U_COUNT)
	var queued: PackedInt32Array = PackedInt32Array()
	queued.resize(U_COUNT)
	for u: SimEntity in world.units_of(pid):
		if (u.flags & SimFlags.F_GONE) == 0:
			counts[_u_role[u.def_idx]] += 1
	var producers: PackedInt32Array = pe.producer_flat
	for id: int in producers:
		var e: SimEntity = world.get_entity(id)
		if e != null and e.prod != null:
			for q: int in e.prod.q_def:
				queued[_u_role[q]] += 1
	var reserve: int = _construction_reserve(world, pe)
	for id: int in producers:
		var e: SimEntity = world.get_entity(id)
		if e == null or e.prod == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var kind: int = e.prod.kind
		if kind == SimEconConst.PROD_DOCK or kind == SimEconConst.PROD_AIRFIELD:
			if not bool(opts.get("air" if kind == SimEconConst.PROD_AIRFIELD else "naval", false)):
				continue
		elif kind != SimEconConst.PROD_BARRACKS and kind != SimEconConst.PROD_FACTORY and kind != SimEconConst.PROD_REFINERY:
			continue
		if not _rally_set.has(id) and kind != SimEconConst.PROD_REFINERY and kind != SimEconConst.PROD_AIRFIELD:
			_rally_set[id] = true
			_send(world, SimCmd.set_rally(PackedInt32Array([id]), _rally_x, _rally_y))
		if e.prod.q_def.size() >= QUEUE_DEPTH:
			continue
		if world.economy.unit_cap_room(pid) <= 0 and kind != SimEconConst.PROD_REFINERY:
			continue
		var pick: int = _pick_unit(world, pe, id, kind, counts, queued, reserve)
		if pick >= 0:
			_send(world, SimCmd.train(id, pick, 1))
			queued[_u_role[pick]] += 1
			stats["units_queued"] = int(stats["units_queued"]) + 1


## Credits kept back for the construction queue while the build ladder is still growing.
func _construction_reserve(world: SimWorld, pe: SimPlayerEcon) -> int:
	if pe.cq_def.is_empty():
		return 0
	return world.players[pid].view.struct_cost[pe.cq_def[0]] / 2


func _pick_unit(world: SimWorld, pe: SimPlayerEcon, producer: int, kind: int, counts: PackedInt32Array, queued: PackedInt32Array, reserve: int) -> int:
	var view: DefPlayerView = world.players[pid].view
	world.production.q_buildable_units(world, pid, producer, _tmp, false)
	if kind == SimEconConst.PROD_REFINERY:
		var want: int = mini(pe.refinery_ids.size() * 2, 4)
		if counts[U_COLLECTOR] + queued[U_COLLECTOR] >= want:
			return -1
		for u: int in _tmp:
			if _u_role[u] == U_COLLECTOR and world.production.can_queue_unit(world, pid, producer, u) == SimEconConst.RSN_OK:
				return u
		return -1
	var credits: int = world.economy.credits(pid) - reserve
	# role furthest below its target share (counts include what is queued)
	var best_role: int = -1
	var best_num: int = 0
	for role: int in SHARE.size():
		if not _role_available(role):
			continue
		var have: int = counts[role] + queued[role]
		# minimise have / share  <=>  compare have * share_b < have_b * share_a
		if best_role < 0 or have * SHARE[best_role] < best_num * SHARE[role]:
			best_role = role
			best_num = have
	if best_role < 0:
		return -1
	var pick: int = -1
	var cands: PackedInt32Array = PackedInt32Array()
	for u: int in _tmp:
		if _u_role[u] != best_role or world.production.can_queue_unit(world, pid, producer, u) != SimEconConst.RSN_OK:
			continue
		if view.unit_cost[u] > credits + 400:
			continue
		cands.append(u)
		if pick < 0 or _better_unit(world.data.units[u], view.unit_cost[u], world.data.units[pick], view.unit_cost[pick]):
			pick = u
	if bool(opts.get("variety", false)) and cands.size() > 1:
		# soak mode: rotate through every affordable def of the role instead of always the best one, so a match exercises
		# the whole roster (deterministic: the counter is part of the bot, the candidates come in def-index order)
		pick = cands[(int(stats["units_queued"]) + pid) % cands.size()]
	return pick


func _role_available(role: int) -> bool:
	for u: int in _tmp:
		if _u_role[u] == role:
			return true
	return false


func _better_unit(a: DefUnit, cost_a: int, b: DefUnit, cost_b: int) -> bool:
	if a.tier != b.tier:
		return a.tier > b.tier
	if cost_a != cost_b:
		return cost_a > cost_b
	return a.index < b.index


# -------------------------------------------------------------------------------------------------- research
## With opts.research: keeps the research queue busy with the cheapest available research (a Laboratory unlocks them).
func _manage_research(world: SimWorld) -> void:
	var pe: SimPlayerEcon = world.players[pid].econ
	if not bool(opts.get("research", false)) or pe == null or not pe.rq_def.is_empty():
		return
	world.production.q_researchable(world, pid, _tmp, false)
	var pick: int = -1
	for r: int in _tmp:
		if world.production.can_queue_research(world, pid, r) != SimEconConst.RSN_OK:
			continue
		if pick < 0 or world.data.research[r].cost < world.data.research[pick].cost:
			pick = r
	if pick >= 0 and world.data.research[pick].cost <= world.economy.credits(pid):
		_send(world, SimCmd.research(pick))
		stats["research_started"] = int(stats.get("research_started", 0)) + 1


# ---------------------------------------------------------------------------------------------------- army
func _army(world: SimWorld, out: PackedInt32Array) -> void:
	out.resize(0)
	for u: SimEntity in world.units_of(pid):
		if (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		var r: int = _u_role[u.def_idx]
		if r >= 0 and r < U_COLLECTOR:
			out.append(u.id)


func _manage_army(world: SimWorld) -> void:
	var army: PackedInt32Array = PackedInt32Array()
	_army(world, army)
	var wave: int = int(opts.get("wave_size", 8)) + world.tick / int(opts.get("wave_growth_ticks", 3000))
	if not _attacking:
		if army.size() < wave or world.tick < int(opts.get("first_attack_tick", 3600)):
			return
		_attacking = true
		stats["waves"] = int(stats["waves"]) + 1
	elif army.size() < int(opts.get("retreat_below", 3)):
		_attacking = false  # the wave is spent: regroup at the rally point
		var back: PackedInt32Array = army.duplicate()
		if not back.is_empty():
			_send(world, SimCmd.move(back, _rally_x, _rally_y))
		return
	if not _pick_target(world, army):
		return
	# everybody idle joins (reinforcements included); units already fighting keep their orders
	var go: PackedInt32Array = PackedInt32Array()
	for id: int in army:
		var u: SimEntity = world.get_entity(id)
		if u.orders.is_empty() or (u.orders[0].type != SimOrder.T_ATTACK_MOVE and u.orders[0].type != SimOrder.T_ATTACK):
			if world.tick - int(_last_go.get(id, -1000)) >= 100:  # an order that fails at once is not re-sent every think
				_last_go[id] = world.tick
				go.append(id)
	if go.is_empty():
		return
	_send(world, SimCmd.attack_move(go, _target_x, _target_y))
	stats["attack_orders"] = int(stats["attack_orders"]) + 1


## Chooses the attack point: the known enemy structure nearest to the rally point, else an enemy start cell.
func _pick_target(world: SimWorld, army: PackedInt32Array) -> bool:
	var best: int = 0
	var best_d: int = 0
	for id: int in _known:
		var v: Vector3i = _known[id]
		var dx: int = v.x - _rally_x
		var dy: int = v.y - _rally_y
		var d: int = dx * dx + dy * dy
		if best == 0 or d < best_d or (d == best_d and id < best):
			best = id
			best_d = d
	if best != 0:
		var kv: Vector3i = _known[best]
		_target_id = best
		_target_x = kv.x
		_target_y = kv.y
		return true
	# nothing known: sweep the start cells of the enemies still in the game (the lobby tells every player where the others start)
	var idx: int = -1
	if not army.is_empty():
		var u: SimEntity = world.get_entity(army[0])
		var bd: int = -1
		for i: int in _enemy_cells.size():
			if _enemy_pids[i] >= 0 and world.players[_enemy_pids[i]].eliminated != 0:
				continue
			var dx2: int = _enemy_cells[i].x * SimConfig.CELL - u.x
			var dy2: int = _enemy_cells[i].y * SimConfig.CELL - u.y
			var d2: int = dx2 * dx2 + dy2 * dy2
			if bd < 0 or d2 < bd:
				bd = d2
				idx = i
	if idx < 0:
		return false
	_target_id = 0
	_target_x = _enemy_cells[idx].x * SimConfig.CELL + SimConfig.CELL / 2
	_target_y = _enemy_cells[idx].y * SimConfig.CELL + SimConfig.CELL / 2
	return true
