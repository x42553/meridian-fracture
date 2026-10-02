class_name SimWorld
extends RefCounted
## The deterministic world (sim_core 3.4 / 5.3 / 5.4): construction from data + config + map, `step()`, spawn /
## kill / removal / ownership, the entity lists, spatial queries, the credits ledger, checkpoints and dumps.
## Everything is integer math and ordered iteration (DR-1..15). The world owns every SimEntity; systems mutate
## entities only through the documented world API and their own components.

enum EndReason { ELIMINATION = 0, NO_HUMANS = 1, DRAW = 2, MISSION_WIN = 3, MISSION_LOSE = 4 }
enum Rel { SELF = 0, ALLY = 1, ENEMY = 2, NEUTRAL = 3 }
## Why an entity died (numbering = combat's CAUSE_*; RESIGN = its owner was eliminated).
enum Cause { DAMAGE = 0, SCUTTLE = 1, EXPIRE = 2, ORPHAN = 3, CARGO = 4, RESIGN = 5, SCRIPT = 6 }

const MATCH_RUNNING: int = 0
const MATCH_ENDED: int = 1

## Names of the 16 checksum parts, in order (sim_core 8.2).
const CHECKSUM_PART_NAMES: PackedStringArray = [
	"world", "rng", "players", "entities", "map",
	"sys.commands", "sys.production", "sys.economy", "sys.power", "sys.orders", "sys.movement",
	"sys.abilities", "sys.combat", "sys.zones", "sys.vision", "sys.cleanup",
]

# ---- state (read-only for everyone except the owning domain), sim_core 3.4.3 ----
var config: SimMatchConfig
var rules: SimMatchRules
var data: GameData
var defs: SimDefs
var map: MapData  ## private clone of the map
var tick: int = 0  ## completed ticks
var rng: SimRng
var players: Array[SimPlayer] = []  ## index = pid (vacant pids included)
var humans_total: int = 0
var by_id: Array[SimEntity] = []  ## sparse, index = entity id; null = free / removed
var entities: Array[SimEntity] = []  ## ALL live entities ascending id (includes F_DEAD until removal)
var units: Array[SimEntity] = []
var structures: Array[SimEntity] = []
var wrecks: Array[SimEntity] = []
var zone_ents: Array[SimEntity] = []
var neutrals: Array[SimEntity] = []
var next_id: int = 1
var next_proj_id: int = 1
var spatial: SpatialHash
var stages: Array[SimSystem] = []
var commands: SimCommandSystem
var orders: SimOrderSystem
var cleanup: SimCleanupSystem
var production: SimProductionSystem
var economy: SimEconomySystem
var power: SimPowerSystem
var movement: SimMovementSystem
var abilities: SimAbilitySystem
var combat: SimCombatSystem
var zones: SimZoneSystem
var vision: SimVisionSystem
var strategic: SimStrategicSystem  ## assigned by economy in init_world
var mission: SimMissionSystem = null  ## scripted mission (config.mission_id != ""), driven by the cleanup stage; null in skirmishes
var fog: SimFogApi
var events: SimEventBuffer
var match_state: int = MATCH_RUNNING
var winner_team: int = -1
var end_reason: int = 0
var end_tick: int = 0
var checksum_log: PackedInt64Array = PackedInt64Array()  ## pairs [tick, checksum] every 20 ticks incl. tick 0
var report_ring: Array[Dictionary] = []
var last_report: Dictionary = {}
var snapshot_ring: Array[String] = []

# ---- kernel-private (cleanup and the state hash read some of these; nobody else) ----
var _live_count: int = 0
var _config_hash: int = 0
var _participants: int = 0  ## non-vacant players at construction (a match needs >= 2 to end)
var _ckpt_interval: int = SimConfig.CHECKSUM_PERIOD
var _inv_every: int = 0
var _snapshot_keep: int = 0
var _max_x: int = 0
var _max_y: int = 0
var _pending: Array[SimCommand] = []
var _ord_counter: int = 0
var _spawn_queue: Array[SimEntity] = []
var _dead: Array[SimEntity] = []
var _dead_cause: PackedInt32Array = PackedInt32Array()
var _dead_killer: PackedInt32Array = PackedInt32Array()
var _dead_killer_pid: PackedInt32Array = PackedInt32Array()
@warning_ignore("unused_private_class_variable")  # read and written by SimCleanupSystem
var _dead_done: int = 0
var _remove_q: Array[SimEntity] = []
var _remove_reason: PackedInt32Array = PackedInt32Array()
@warning_ignore("unused_private_class_variable")  # read and written by SimCleanupSystem
var _remove_done: int = 0
var _removed_since_compact: int = 0
var _moved: PackedInt32Array = PackedInt32Array()
var _moved_prev: PackedInt32Array = PackedInt32Array()
var _moved_ver: int = 0
var _moved2: PackedInt32Array = PackedInt32Array()
var _moved2_ver: int = -1
var _units_by: Array = []  ## slot (0..8) -> Array[SimEntity]
var _structs_by: Array = []
var _lists_ver: int = 0
var _own_cache: Array[PackedInt32Array] = []
var _own_ver: PackedInt32Array = PackedInt32Array()
var _rel_tab: PackedByteArray = PackedByteArray()
var _non_enemy: PackedInt32Array = PackedInt32Array()
var _qbuf: PackedInt32Array = PackedInt32Array()


## Constructs the world (sim_core 3.4.1). Prefer SimWorld.create() for real matches.
func _init(game_data: GameData, cfg: SimMatchConfig, map_data: MapData, opts: Dictionary = {}) -> void:
	data = game_data
	config = cfg
	rules = cfg.rules
	if cfg.mission_id != "":
		mission = SimMissionSystem.create(game_data, cfg.mission_id)
		if mission != null:
			rules = mission.apply_rules(cfg.rules)  # a private copy: the config stays as given
	_config_hash = cfg.config_hash()
	defs = SimDefs.new(data)
	map = map_data.clone_fresh()
	rng = SimRng.new(cfg.seed_value)
	spatial = SpatialHash.new(map.w, map.h)
	_max_x = map.w * SimConfig.CELL - 1
	_max_y = map.h * SimConfig.CELL - 1
	_ckpt_interval = maxi(int(opts.get("checkpoint_interval", SimConfig.CHECKSUM_PERIOD)), 1)
	_inv_every = int(opts.get("invariants_every", 0))
	_snapshot_keep = int(opts.get("snapshot_keep", 0))
	events = SimEventBuffer.new()
	events.enabled = bool(opts.get("events", true))
	fog = SimFogApi.new()
	for _i: int in SimConfig.MAX_PLAYERS + 1:
		var ul: Array[SimEntity] = []
		var sl: Array[SimEntity] = []
		_units_by.append(ul)
		_structs_by.append(sl)
		_own_cache.append(PackedInt32Array())
	_own_ver.resize(SimConfig.MAX_PLAYERS + 1)
	_own_ver.fill(-1)
	_build_players()
	_build_relations()
	stages = SimPipeline.create(opts.get("disable"), opts.get("systems"))
	_assign_members()
	for s: SimSystem in stages:
		s.init_world(self)
	_spawn_initial()
	_flush_spawns()
	if mission != null:
		mission.begin(self)
		_flush_spawns()
	_record_checkpoint()


## The validating factory for real matches: null + Log.error for every problem.
static func create(game_data: GameData, cfg: SimMatchConfig, map_data: MapData, opts: Dictionary = {}) -> SimWorld:
	var problems: PackedStringArray = PackedStringArray()
	if game_data == null:
		problems.append("no game data")
	if cfg == null:
		problems.append("no match config")
	if map_data == null or not map_data.is_finalized():
		problems.append("map missing or not finalized")
	elif cfg != null:
		if map_data.spawns.size() % MapData.SPAWN_STRIDE != 0:
			problems.append("map.spawns is not a whole number of %d-int records" % MapData.SPAWN_STRIDE)
		if map_data.neutrals.size() % MapData.NEUTRAL_STRIDE != 0:
			problems.append("map.neutrals is not a whole number of %d-int records" % MapData.NEUTRAL_STRIDE)
		problems.append_array(cfg.validate(game_data, map_data.spawns.size() / MapData.SPAWN_STRIDE))
	if not problems.is_empty():
		for msg: String in problems:
			Log.error("world", msg)
		return null
	return SimWorld.new(game_data, cfg, map_data, opts)


func _build_players() -> void:
	var n: int = config.max_pid() + 1
	for pid: int in n:
		var p: SimPlayer = SimPlayer.new()
		p.pid = pid
		p.team = 0
		p.controller = SimPlayer.Controller.NONE
		p.eliminated = 1
		players.append(p)
	for s: SimPlayerSlot in config.players:
		if s.pid < 0 or s.pid >= n:
			continue
		var p: SimPlayer = players[s.pid]
		p.controller = SimPlayer.Controller.AI if s.kind == SimPlayerSlot.AI else SimPlayer.Controller.HUMAN
		if p.controller == SimPlayer.Controller.HUMAN:
			humans_total += 1
		p.eliminated = 0
		p.team = s.team
		p.color = s.color
		p.name = s.name
		p.handicap = s.handicap
		p.ai_level = s.ai_level
		p.ai_style = s.ai_style
		p.ai_flags = s.ai_flags
		var ri: int = data.roster_idx(s.roster)
		if ri < 0:
			Log.error("world", "pid %d: unknown roster '%s', using the base roster" % [s.pid, s.roster])
			p.roster = data.base_roster
		else:
			p.roster = data.rosters[ri]
		p.roster_idx = ri
		p.faction_idx = p.roster.faction
		p.view = DefPlayerView.new(data, p.roster)
		p.credits = rules.start_credits * s.handicap / 100
		_participants += 1


func _build_relations() -> void:
	var m: int = SimConfig.MAX_PLAYERS + 1
	_rel_tab.resize(m * m)
	_non_enemy.resize(m)
	for a: int in m:
		var mask: int = 0
		for b: int in m:
			var r: int = Rel.NEUTRAL
			if _is_player(a) and _is_player(b):
				if a == b:
					r = Rel.SELF
				elif players[a].team == players[b].team:
					r = Rel.ALLY
				else:
					r = Rel.ENEMY
			_rel_tab[a * m + b] = r
			if r != Rel.ENEMY:
				mask |= 1 << (10 + b)
		_non_enemy[a] = mask


func _is_player(slot: int) -> bool:
	return slot < players.size() and slot < SimConfig.MAX_PLAYERS and players[slot].controller != SimPlayer.Controller.NONE


func _assign_members() -> void:
	commands = stages[0] as SimCommandSystem
	production = stages[1] as SimProductionSystem
	economy = stages[2] as SimEconomySystem
	power = stages[3] as SimPowerSystem
	orders = stages[4] as SimOrderSystem
	movement = stages[5] as SimMovementSystem
	abilities = stages[6] as SimAbilitySystem
	combat = stages[7] as SimCombatSystem
	zones = stages[8] as SimZoneSystem
	vision = stages[9] as SimVisionSystem
	cleanup = stages[10] as SimCleanupSystem
	if commands == null or orders == null or cleanup == null:
		Log.error("world", "stage 1 / 5 / 11 must be SimCommandSystem / SimOrderSystem / SimCleanupSystem (or subclasses)")


## Initial entities (sim_core 3.4.1): neutral structures of the map, then each active player's start entity.
func _spawn_initial() -> void:
	if rules.neutral_structures != 0:
		var nrec: int = map.neutrals.size() / MapData.NEUTRAL_STRIDE
		for r: int in nrec:
			var o: int = r * MapData.NEUTRAL_STRIDE
			var def_idx: int = map.neutral_def_for_kind(map.neutrals[o])
			if def_idx < 0:
				continue
			var cell: int = map.neutrals[o + 1]
			var x: int = (cell % map.w) * SimConfig.CELL + map.neutrals[o + 2] * (SimConfig.CELL / 2)
			var y: int = (cell / map.w) * SimConfig.CELL + map.neutrals[o + 3] * (SimConfig.CELL / 2)
			spawn_entity(map.neutral_ent_kind(map.neutrals[o]), def_idx, -1, x, y, 0, SimFlags.F_INITIAL, 0, 0, SimEvent.SPAWN_INITIAL)
	if rules.start_mode == SimMatchRules.START_NONE:
		return
	for s: SimPlayerSlot in config.players:
		var rec: int = s.start * MapData.SPAWN_STRIDE
		if s.pid < 0 or s.pid >= players.size() or rec < 0 or rec + 2 >= map.spawns.size():
			continue
		var p: SimPlayer = players[s.pid]
		var cell: int = map.spawns[rec + 1]
		var x: int = (cell % map.w) * SimConfig.CELL + SimConfig.CELL / 2
		var y: int = (cell / map.w) * SimConfig.CELL + SimConfig.CELL / 2
		if rules.start_mode == SimMatchRules.START_HQ:
			if p.roster.hq_idx < 0:
				Log.error("world", "pid %d: roster has no HQ" % s.pid)
				continue
			spawn_entity(SimEntity.Kind.STRUCTURE, p.roster.hq_idx, s.pid, x, y, 0, SimFlags.F_INITIAL, 0, 0, SimEvent.SPAWN_INITIAL)
		else:
			if p.roster.mcv_idx < 0:
				Log.error("world", "pid %d: roster has no MCV" % s.pid)
				continue
			spawn_entity(SimEntity.Kind.UNIT, p.roster.mcv_idx, s.pid, x, y, map.spawns[rec + 2], SimFlags.F_INITIAL, 0, 0, SimEvent.SPAWN_INITIAL)


# ---- stepping and command intake (3.4.2) ----
## Queues [op, fields..., ids...] for the NEXT step(); pid is stamped by the caller. Never fails.
func submit_raw(pid: int, ints: PackedInt32Array) -> void:
	var c: SimCommand = SimCommand.new()
	c.pid = pid
	c.raw = ints
	c._ord = _ord_counter
	_ord_counter += 1
	_pending.append(c)


## = submit_raw(cmd.pid, cmd.to_ints()).
func submit(cmd: SimCommand) -> void:
	submit_raw(cmd.pid, cmd.to_ints())


## THE only way time advances: one 50 ms tick (sim_core 5.3).
func step() -> void:
	if match_state != MATCH_RUNNING:
		_pending.clear()
		_ord_counter = 0
		return
	events.tick = tick
	_begin_tick_moves()
	commands.update(self)
	_flush_spawns()
	for i: int in range(1, stages.size()):
		var s: SimSystem = stages[i]
		if s.stride > 1 and (tick + s.stride_offset) % s.stride != 0:
			continue
		s.update(self)
		_flush_spawns()
	tick += 1
	events.tick = tick
	if _inv_every > 0 and tick % _inv_every == 0:
		for msg: String in SimInvariants.check(self):
			Log.error("invariant", "tick %d: %s" % [tick, msg])
	if tick % _ckpt_interval == 0:
		_record_checkpoint()


## n x step().
func run(n: int) -> void:
	for _i: int in n:
		step()


## Internal (SimCommandSystem): hands over the pending commands and restarts the submission counter.
func take_pending() -> Array[SimCommand]:
	var out: Array[SimCommand] = _pending
	_pending = []
	_ord_counter = 0
	return out


# ---- queries (3.4.4) ----
## Null if never allocated / already removed (dead-but-not-removed entities ARE returned).
func get_entity(id: int) -> SimEntity:
	if id <= 0 or id >= by_id.size():
		return null
	return by_id[id]


## Exists and not F_DEAD | F_REMOVING.
func is_alive(id: int) -> bool:
	if id <= 0 or id >= by_id.size():
		return false
	var e: SimEntity = by_id[id]
	return e != null and (e.flags & SimFlags.F_GONE) == 0


static func _slot(owner: int) -> int:
	return SimConfig.NEUTRAL_SLOT if owner < 0 or owner >= SimConfig.MAX_PLAYERS else owner


## Live internal list of the owner's units (-1 = neutral), ascending id; read-only, stage-stable.
func units_of(owner: int) -> Array[SimEntity]:
	return _units_by[_slot(owner)]


## Live internal list of the owner's structures.
func structures_of(owner: int) -> Array[SimEntity]:
	return _structs_by[_slot(owner)]


## Ascending ids of the live units + structures of pid (borrowed; rebuilt when a list changed).
func own_ids(pid: int) -> PackedInt32Array:
	var s: int = _slot(pid)
	if _own_ver[s] != _lists_ver:
		var out: PackedInt32Array = PackedInt32Array()
		var ul: Array[SimEntity] = _units_by[s]
		var sl: Array[SimEntity] = _structs_by[s]
		var i: int = 0
		var j: int = 0
		while i < ul.size() or j < sl.size():
			var e: SimEntity
			if j >= sl.size() or (i < ul.size() and ul[i].id < sl[j].id):
				e = ul[i]
				i += 1
			else:
				e = sl[j]
				j += 1
			if (e.flags & SimFlags.F_GONE) == 0:
				out.append(e.id)
		_own_cache[s] = out
		_own_ver[s] = _lists_ver
	return _own_cache[s]


## -1 for neutral / invalid / vacant.
func team_of(owner: int) -> int:
	if owner < 0 or not _is_player(owner):
		return -1
	return players[owner].team


## Rel.* between two OWNERS (pids or -1); vacant pids are NEUTRAL to everyone.
func rel(a: int, b: int) -> int:
	return _rel_tab[_slot(a) * (SimConfig.MAX_PLAYERS + 1) + _slot(b)]


func are_enemies(a: int, b: int) -> bool:
	return rel(a, b) == Rel.ENEMY


## SELF or ALLY (false for neutral and vacant pids).
func are_allied(a: int, b: int) -> bool:
	var r: int = rel(a, b)
	return r == Rel.SELF or r == Rel.ALLY


## Id of the STRUCTURE / NEUTRAL entity occupying the cell, 0 = free or outside the map.
func struct_at(cx: int, cy: int) -> int:
	if not map.in_bounds(cx, cy):
		return 0
	return maxi(map.occupant_at(map.idx(cx, cy)), 0)


func cell_visible(pid: int, cx: int, cy: int) -> bool:
	return fog.cell_visible(pid, cx, cy)


func cell_explored(pid: int, cx: int, cy: int) -> bool:
	return fog.cell_explored(pid, cx, cy)


func entity_visible(pid: int, e: SimEntity) -> bool:
	return fog.entity_visible(pid, e)


## `avoid` mask leaving only enemies of pid: own + allied + neutral owner bits.
func non_enemy_mask(pid: int) -> int:
	return _non_enemy[_slot(pid)]


## Fills out (ascending ids) with entities whose centre is within r; returns the count.
func query_circle(x: int, y: int, r: int, out: PackedInt32Array, need: int = SimTag.ALIVE, avoid: int = 0) -> int:
	return spatial.query_circle(x, y, r, out, need, avoid)


## Rect query, inclusive; see query_circle.
func query_rect(x0: int, y0: int, x1: int, y1: int, out: PackedInt32Array, need: int = SimTag.ALIVE, avoid: int = 0) -> int:
	return spatial.query_rect(x0, y0, x1, y1, out, need, avoid)


## Nearest matching entity id or 0; ties -> lowest id.
func nearest(x: int, y: int, r: int, need: int = SimTag.ALIVE, avoid: int = 0, exclude_id: int = 0) -> int:
	var n: int = spatial.query_circle(x, y, r, _qbuf, need, avoid)
	var best: int = 0
	var best_d: int = 0
	for i: int in n:
		var id: int = _qbuf[i]
		if id == exclude_id:
			continue
		var dx: int = spatial.x_of(id) - x
		var dy: int = spatial.y_of(id) - y
		var d: int = dx * dx + dy * dy
		if best == 0 or d < best_d:
			best = id
			best_d = d
	return best


## Alive enemy UNITs + STRUCTUREs, fog via fog.entity_visible (ignore_fog: only camouflage via entity_revealed).
func enemies_in_circle(viewer: int, x: int, y: int, r: int, out: PackedInt32Array, ignore_fog: bool = false) -> int:
	var avoid: int = _non_enemy[_slot(viewer)] | SimTag.kind_bit(SimEntity.Kind.WRECK) | SimTag.kind_bit(SimEntity.Kind.ZONE) | SimTag.kind_bit(SimEntity.Kind.NEUTRAL)
	var n: int = spatial.query_circle(x, y, r, out, SimTag.ALIVE, avoid)
	var w: int = 0
	for i: int in n:
		var e: SimEntity = by_id[out[i]]
		var ok: bool = fog.entity_revealed(viewer, e) if ignore_fog else fog.entity_visible(viewer, e)
		if ok:
			out[w] = out[i]
			w += 1
	out.resize(w)
	return w


## All alive enemy units + structures of viewer passing fog.entity_visible.
func visible_enemy_ids(viewer: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for e: SimEntity in entities:
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
			continue
		if rel(viewer, e.owner) == Rel.ENEMY and fog.entity_visible(viewer, e):
			out.append(e.id)
	return out.size()


## Alive, on map, selectable units of pid with an empty order queue.
func find_idle_units(pid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for e: SimEntity in units_of(pid):
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE | SimFlags.F_NO_SELECT)) == 0 and e.orders.is_empty():
			out.append(e.id)
	return out.size()


## Alive entities of that (kind, def) owned by pid, ascending id.
func find_by_def(kind: int, def_idx: int, pid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var list: Array[SimEntity]
	if kind == SimEntity.Kind.UNIT:
		list = units_of(pid)
	elif kind == SimEntity.Kind.STRUCTURE:
		list = structures_of(pid)
	else:
		list = entities
	for e: SimEntity in list:
		if e.kind == kind and e.def_idx == def_idx and e.owner == pid and (e.flags & SimFlags.F_GONE) == 0:
			out.append(e.id)
	return out.size()


## Own + allied entities, plus enemy / neutral entities passing fog.entity_visible (ascending id).
func entities_visible_to(pid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for e: SimEntity in entities:
		if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
			continue
		var r: int = rel(pid, e.owner)
		if r == Rel.SELF or r == Rel.ALLY or fog.entity_visible(pid, e):
			out.append(e.id)
	return out.size()


## Ids whose position changed during this tick so far or the previous one (ascending, unique, borrowed).
func moved_prev2() -> PackedInt32Array:
	if _moved2_ver != _moved_ver:
		var m: PackedInt32Array = _moved_prev.duplicate()
		m.append_array(_moved)
		m.sort()
		var w: int = 0
		for i: int in m.size():
			if w == 0 or m[i] != m[w - 1]:
				m[w] = m[i]
				w += 1
		m.resize(w)
		_moved2 = m
		_moved2_ver = _moved_ver
	return _moved2


## Separate id space for combat's pooled projectiles.
func alloc_proj_id() -> int:
	var id: int = next_proj_id
	next_proj_id += 1
	return id


# ---- spawn, kill, removal, ownership (3.4.5) ----
## THE spawn path; null on failure (entity cap, bad def, bad / eliminated owner, match ended).
func spawn_entity(kind: int, def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, parent: int = 0, paid_cost: int = 0, reason: int = SimEvent.SPAWN_SCRIPT) -> SimEntity:
	if match_state != MATCH_RUNNING or _live_count >= SimConfig.MAX_ENTITIES:
		return null
	if not defs.has_def(kind, def_idx):
		return null
	if owner != -1 and (owner < 0 or owner >= players.size() or players[owner].controller == SimPlayer.Controller.NONE):
		return null
	if owner >= 0 and players[owner].eliminated != 0 and kind != SimEntity.Kind.WRECK:
		return null
	var e: SimEntity = SimEntity.new()
	e.id = next_id
	next_id += 1
	e.kind = kind
	e.def_idx = def_idx
	e.owner = owner
	e.parent = parent
	e.team = team_of(owner)
	e.radius = defs.radius(kind, def_idx)
	e.layer = defs.home_layer(kind, def_idx)
	var cap: int = defs.cap_weight(kind, def_idx)
	var f: int = defs.flags_init(kind, def_idx) | flags
	if kind != SimEntity.Kind.UNIT or cap == 0:
		f |= SimFlags.F_NO_UNIT_CAP
	e.flags = f
	e._cap = 0 if (f & SimFlags.F_NO_UNIT_CAP) != 0 else cap
	e.x = clampi(x, 0, _max_x)
	e.y = clampi(y, 0, _max_y)
	e.prev_x = e.x
	e.prev_y = e.y
	e.facing = facing & (Fp.TURN - 1)
	e.hp_max = defs.hp_max(players[owner].view if owner >= 0 else null, kind, def_idx)
	e.hp = e.hp_max
	e.paid_cost = paid_cost
	e.container_id = -1
	e.born = tick
	if e.id >= by_id.size():
		by_id.resize(maxi(e.id + 1, by_id.size() * 2))
	by_id[e.id] = e
	spatial.insert(e.id, e.x, e.y, SimTag.of(e))
	_count_in(e, reason != SimEvent.SPAWN_INITIAL and reason != SimEvent.SPAWN_WRECK)
	if parent > 0:
		var pe: SimEntity = get_entity(parent)
		if pe != null:
			pe.flags |= SimFlags.F_HAS_CHILDREN
	_live_count += 1
	_spawn_queue.append(e)
	events.emit(SimEvent.SPAWNED, e.x, e.y, e.id, kind, def_idx, owner, e.facing, reason)
	if (kind == SimEntity.Kind.STRUCTURE or kind == SimEntity.Kind.NEUTRAL) and (f & SimFlags.F_NO_FOOTPRINT) == 0:
		_occupy(e)
	for s: SimSystem in stages:
		s.on_spawn(self, e)
	return e


func spawn_unit(def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, paid_cost: int = 0, parent: int = 0, reason: int = SimEvent.SPAWN_SCRIPT) -> SimEntity:
	return spawn_entity(SimEntity.Kind.UNIT, def_idx, owner, x, y, facing, flags, parent, paid_cost, reason)


## x, y = footprint CENTRE (sub-cell units); facing = 1024 x orientation for rotatable footprints.
func spawn_structure(def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, paid_cost: int = 0, parent: int = 0, reason: int = SimEvent.SPAWN_PLACED) -> SimEntity:
	return spawn_entity(SimEntity.Kind.STRUCTURE, def_idx, owner, x, y, facing, flags, parent, paid_cost, reason)


## life_ticks > 0 sets expire_tick = tick + life_ticks.
func spawn_zone(def_idx: int, owner: int, x: int, y: int, life_ticks: int, parent: int = 0, flags: int = 0) -> SimEntity:
	var e: SimEntity = spawn_entity(SimEntity.Kind.ZONE, def_idx, owner, x, y, 0, flags, parent, 0, SimEvent.SPAWN_SUMMONED)
	if e != null and life_ticks > 0:
		e.expire_tick = tick + life_ticks
	return e


## Kind WRECK with the dead unit's def / original owner / paid_cost; called from a combat on_dying hook.
func spawn_wreck(from: SimEntity, salvageable: bool, hp: int = 1, life_ticks: int = 0) -> SimEntity:
	var f: int = SimFlags.F_TEMPORARY | SimFlags.F_UNTARGETABLE | SimFlags.F_NO_SELECT | SimFlags.F_NO_UNIT_CAP
	if not salvageable:
		f |= SimFlags.F_NO_SALVAGE
	var e: SimEntity = spawn_entity(SimEntity.Kind.WRECK, from.def_idx, from.owner, from.x, from.y, from.facing, f, 0, from.paid_cost, SimEvent.SPAWN_WRECK)
	if e == null:
		return null
	e.radius = from.radius
	e.hp = hp
	e.hp_max = hp
	if life_ticks > 0:
		e.expire_tick = tick + life_ticks
	return e


## F_DEAD, hp = 0, off the spatial queries; hooks + removal happen in stage 11 of THIS tick (sim_core 5.4).
func kill(e: SimEntity, cause: int, killer_id: int = 0, killer_pid: int = -1) -> void:
	if e == null or (e.flags & SimFlags.F_GONE) != 0 or match_state != MATCH_RUNNING:
		return
	e.flags |= SimFlags.F_DEAD
	e.hp = 0
	e.expire_tick = 0
	spatial.set_tag(e.id, SimTag.of(e))
	_count_out(e)
	if killer_pid < 0 and killer_id > 0:
		var k: SimEntity = get_entity(killer_id)
		if k != null:
			killer_pid = k.owner
	_dead.append(e)
	_dead_cause.append(cause)
	_dead_killer.append(killer_id)
	_dead_killer_pid.append(killer_pid)
	_lists_ver += 1


## Silent removal (REM_*); no on_dying, no wreck; false if unknown / already leaving.
func remove_entity(id: int, reason: int) -> bool:
	var e: SimEntity = get_entity(id)
	if e == null or (e.flags & SimFlags.F_GONE) != 0 or match_state != MATCH_RUNNING:
		return false
	_count_out(e)
	_queue_removal(e, reason)
	return true


## Removal at stage 11 of the first tick >= at_tick; on a DEAD entity it keeps the corpse until then.
func remove_deferred(id: int, at_tick: int) -> void:
	var e: SimEntity = get_entity(id)
	if e == null or e._gone or (e.flags & SimFlags.F_REMOVING) != 0 or match_state != MATCH_RUNNING:
		return
	e.expire_tick = maxi(at_tick, 1)


## Capture: re-lists, re-counts, hp_max from the new owner's view; false for an invalid / eliminated owner or same owner.
func change_owner(id: int, new_owner: int, reason: int = 0) -> bool:
	var e: SimEntity = get_entity(id)
	if e == null or (e.flags & SimFlags.F_GONE) != 0 or match_state != MATCH_RUNNING:
		return false
	if new_owner == e.owner:
		return false
	if new_owner != -1 and (new_owner < 0 or new_owner >= players.size() or players[new_owner].controller == SimPlayer.Controller.NONE or players[new_owner].eliminated != 0):
		return false
	var old: int = e.owner
	_count_out(e)
	if e._listed:
		_list_remove(e, old)
	e.owner = new_owner
	e.team = team_of(new_owner)
	set_hp_max(e, defs.hp_max(players[new_owner].view if new_owner >= 0 else null, e.kind, e.def_idx))
	_count_in(e, false)
	if e._listed:
		_list_insert(e, new_owner)
	spatial.set_tag(e.id, SimTag.of(e))
	if e.kind == SimEntity.Kind.UNIT and orders != null:
		orders.clear(self, e, SimOrder.END_CANCELLED)
	_lists_ver += 1
	for s: SimSystem in stages:
		s.on_owner_changed(self, e, old)
	events.emit(SimEvent.OWNER_CHANGED, e.x, e.y, e.id, old, new_owner, reason)
	return true


## SimPlayer.Elim.*; the defeat cascade is executed by cleanup. Idempotent.
func eliminate(pid: int, reason: int) -> void:
	if match_state != MATCH_RUNNING or pid < 0 or pid >= players.size():
		return
	var p: SimPlayer = players[pid]
	if p.controller == SimPlayer.Controller.NONE or p.eliminated != 0:
		return
	p.eliminated = 1
	p.elim_tick = tick
	p.elim_reason = reason
	events.emit(SimEvent.PLAYER_ELIMINATED, 0, 0, pid, reason, p.team)
	for s: SimSystem in stages:
		s.on_player_eliminated(self, pid)


## Freezes the world (sim_core 5.9).
func end_match(winner: int, reason: int) -> void:
	if match_state != MATCH_RUNNING:
		return
	match_state = MATCH_ENDED
	winner_team = winner
	end_reason = reason
	end_tick = tick
	events.emit(SimEvent.MATCH_END, 0, 0, winner, reason, tick)


# ---- motion, containers, hit points (3.4.6) ----
## Clamps into the map, updates the spatial hash unless F_INSIDE, maintains prev_x / prev_y / vx / vy.
func set_pos(e: SimEntity, x: int, y: int, teleport: bool = false) -> void:
	x = clampi(x, 0, _max_x)
	y = clampi(y, 0, _max_y)
	if teleport:
		e.prev_x = x
		e.prev_y = y
		e.vx = 0
		e.vy = 0
	else:
		if e._pos_tick != tick:  # first move of this tick: remember where the tick started
			e._pos_tick = tick
			_moved.append(e.id)
			_moved_ver += 1
			e.prev_x = e.x
			e.prev_y = e.y
		e.vx = x - e.prev_x
		e.vy = y - e.prev_y
	e.x = x
	e.y = y
	if (e.flags & SimFlags.F_INSIDE) == 0:
		spatial.move(e.id, x, y)


## Keeps the hash tag in sync.
func set_layer(e: SimEntity, layer: int) -> void:
	e.layer = layer
	spatial.set_tag(e.id, SimTag.of(e))


## Loaded / garrisoned: F_INSIDE + container_id (>= 0), out of / back into the spatial hash.
func set_inside(e: SimEntity, container_id: int, inside: bool) -> void:
	if inside:
		if container_id < 0:
			return
		e.flags |= SimFlags.F_INSIDE
		e.container_id = container_id
		spatial.remove(e.id)
	else:
		e.flags &= ~SimFlags.F_INSIDE
		e.container_id = -1
		if not e._gone:
			spatial.insert(e.id, e.x, e.y, SimTag.of(e))


## New hp_max; hp keeps its fraction (half-up, never below 1 while alive).
func set_hp_max(e: SimEntity, new_max: int) -> void:
	var old: int = e.hp_max
	e.hp_max = new_max
	if (e.flags & SimFlags.F_DEAD) != 0 or new_max <= 0:
		return
	if old <= 0:
		e.hp = new_max
		return
	e.hp = maxi((e.hp * new_max * 2 + old) / (old * 2), 1)


# ---- credits ledger (3.4.7) ----
## Returns the credits actually added (handicap-scaled for HARVEST / SALVAGE).
func add_credits(pid: int, amount: int, reason: int, x: int = 0, y: int = 0, source_id: int = 0, silent: bool = false) -> int:
	if pid < 0 or pid >= players.size():
		return 0
	var p: SimPlayer = players[pid]
	var credited: int = amount
	var income: bool = reason == SimEvent.CASH_HARVEST or reason == SimEvent.CASH_SALVAGE
	if income and p.handicap != 100 and amount > 0:
		var t: int = amount * p.handicap + p.income_frac
		credited = t / 100
		p.income_frac = t % 100
	p.credits += credited
	if income and credited > 0:
		p.st_credits_earned += credited
	if credited < 0:
		p.st_credits_spent -= credited
	elif reason == SimEvent.CASH_REFUND:
		p.st_credits_spent -= credited
	if not silent:
		events.emit(SimEvent.CASH, x, y, pid, credited, p.credits, reason, source_id)
	return credited


## false (no change) if credits < amount.
func try_spend(pid: int, amount: int, reason: int = SimEvent.CASH_SPEND, source_id: int = 0, silent: bool = false) -> bool:
	if pid < 0 or pid >= players.size() or amount < 0:
		return false
	var p: SimPlayer = players[pid]
	if p.credits < amount:
		return false
	p.credits -= amount
	p.st_credits_spent += amount
	if not silent:
		events.emit(SimEvent.CASH, 0, 0, pid, -amount, p.credits, reason, source_id)
	return true


## rules.unit_cap - unit_count, >= 0.
func unit_cap_room(pid: int) -> int:
	if pid < 0 or pid >= players.size():
		return 0
	return maxi(rules.unit_cap - players[pid].unit_count, 0)


# ---- events shortcut (3.7) ----
func emit(type: int, x: int = 0, y: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> void:
	events.emit(type, x, y, a, b, c, d, e, f)


# ---- checksum, net adapter surface and diagnostics (3.4.8) ----
## Computes the checksum NOW; the periodic values are in checksum_log.
func checksum() -> int:
	return SimStateHash.compute(self)["final"]


## u32 recorded at the end of tick t (t % period == 0), -1 if that tick never happened.
func checksum_at(t: int) -> int:
	var i: int = 0
	while i + 1 < checksum_log.size():
		if checksum_log[i] == t:
			return checksum_log[i + 1]
		i += 2
	return -1


## {} or {tick, final, parts, entity_digests} for a retained checkpoint.
func report_at(t: int) -> Dictionary:
	for r: Dictionary in report_ring:
		if r["tick"] == t:
			return r
	return {}


## The 16 part digests of that snapshot; empty if older than SNAPSHOT_KEEP.
func checksum_parts_at(t: int) -> PackedInt32Array:
	var r: Dictionary = report_at(t)
	if r.is_empty():
		return PackedInt32Array()
	return r["parts"]


func checksum_part_names() -> PackedStringArray:
	return CHECKSUM_PART_NAMES


## map.map_hash().
func map_hash() -> int:
	return map.map_hash()


func is_match_over() -> bool:
	return match_state != MATCH_RUNNING


## {winner_team: int (-1 none), reason: int (EndReason)}.
func match_result() -> Dictionary:
	return {"winner_team": winner_team, "reason": end_reason}


## false when eliminated / vacant.
func is_player_active(pid: int) -> bool:
	return pid >= 0 and pid < players.size() and players[pid].controller != SimPlayer.Controller.NONE and players[pid].eliminated == 0


func clear_events() -> void:
	events.clear()


## Deterministic text: header, RNG, one line per player / entity / system with EVERY checksummed int.
func dump_state() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("MFSIM v%d tick=%d next_id=%d proj=%d state=%d winner=%d reason=%d end=%d live=%d cfg=%d data=%d map=%d" % [
		SimConfig.SIM_VERSION, tick, next_id, next_proj_id, match_state, winner_team, end_reason, end_tick, _live_count,
		_config_hash, data.data_hash(), map.map_hash()])
	var buf: PackedInt32Array = PackedInt32Array()
	rules.hash_into(buf)
	lines.append("RULES " + _ints_text(buf))
	buf.resize(0)
	rng.hash_into(buf)
	lines.append("RNG " + _ints_text(buf))
	for p: SimPlayer in players:
		buf.resize(0)
		p.hash_into(buf)
		lines.append("P%d %s" % [p.pid, _ints_text(buf)])
	for e: SimEntity in entities:
		buf.resize(0)
		e.hash_into(buf)
		lines.append("E%d %s" % [e.id, _ints_text(buf)])
	lines.append("MAP %d" % map.checksum_dynamic())
	for s: SimSystem in stages:
		buf.resize(0)
		s.hash_state(self, buf)
		lines.append("S%d %s %s" % [s.stage_no, s.system_name(), _ints_text(buf)])
	return "\n".join(lines) + "\n"


## Reflective field name -> value dictionary (debug UI, tests).
func dump_entity(e: SimEntity) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in e.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		var v: Variant = e.get(n)
		if v is SimComponent:
			out[n] = (v as SimComponent).dump()
		elif n == "orders":
			var arr: Array = []
			for o: SimOrder in e.orders:
				var od: Dictionary = {}
				for op: Dictionary in o.get_property_list():
					if (int(op["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
						od[op["name"]] = o.get(op["name"])
				arr.append(od)
			out[n] = arr
		elif v is PackedInt32Array:
			out[n] = (v as PackedInt32Array).duplicate()
		else:
			out[n] = v
	return out


static func _ints_text(a: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for v: int in a:
		parts.append(str(v))
	return " ".join(parts)


func _record_checkpoint() -> void:
	var r: Dictionary = SimStateHash.compute(self)
	var fin: int = r["final"]
	checksum_log.append(tick)
	checksum_log.append(fin)
	var rep: Dictionary = {"tick": tick, "final": fin, "parts": r["parts"], "entity_digests": r["entity_digests"]}
	report_ring.append(rep)
	if report_ring.size() > SimConfig.SNAPSHOT_KEEP:
		report_ring.pop_front()
	last_report = rep
	if _snapshot_keep > 0:
		snapshot_ring.append(dump_state())
		while snapshot_ring.size() > _snapshot_keep:
			snapshot_ring.pop_front()


# ---- lifecycle internals (also used by SimCleanupSystem, sim_core 5.4) ----
func _begin_tick_moves() -> void:
	_moved_ver += 1
	var t: PackedInt32Array = _moved_prev
	_moved_prev = _moved
	_moved = t
	_moved.resize(0)
	for id: int in _moved_prev:  # last tick's movers: forget the motion
		var e: SimEntity = by_id[id] if id < by_id.size() else null
		if e != null:
			e.prev_x = e.x
			e.prev_y = e.y
			e.vx = 0
			e.vy = 0
			e._pos_tick = -1


func _count_in(e: SimEntity, built: bool) -> void:
	if e._counted or e.owner < 0 or e.owner >= players.size():
		return
	if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
		return
	var p: SimPlayer = players[e.owner]
	e._counted = true
	e._asset = (e.flags & (SimFlags.F_TEMPORARY | SimFlags.F_DECOY | SimFlags.F_SUMMONED)) == 0
	if e.kind == SimEntity.Kind.UNIT:
		p.unit_count += e._cap
		if p.unit_count > p.st_peak_units:
			p.st_peak_units = p.unit_count
		if e._asset and defs.is_rebuilder(e.kind, e.def_idx):
			p.rebuilders += 1
		if built:
			p.st_units_built += 1
	else:
		if e._asset:
			p.struct_count += 1
		if built:
			p.st_structs_built += 1


func _count_out(e: SimEntity) -> void:
	if not e._counted:
		return
	e._counted = false
	var p: SimPlayer = players[e.owner]
	if e.kind == SimEntity.Kind.UNIT:
		p.unit_count -= e._cap
		if e._asset and defs.is_rebuilder(e.kind, e.def_idx):
			p.rebuilders -= 1
	elif e._asset:
		p.struct_count -= 1


func _occupy(e: SimEntity) -> void:
	var fp: MapFootprint = map.footprint_of(e.kind, e.def_idx)
	if fp == null:
		return
	var orient: int = (e.facing >> 10) & 3 if fp.rotatable else 0
	var sz: int = fp.size_oriented(orient)
	var w: int = sz >> 8
	var h: int = sz & 255
	var cx: int = (e.x - w * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var cy: int = (e.y - h * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var bbox: int = map.occupy(e.id, fp, cx, cy, orient)
	if bbox < 0:
		return
	e._occ = true
	events.emit(SimEvent.NAV_CHANGED, e.x, e.y, bbox, map.nav_version, e.id, 1)


## Marks the entity as leaving and queues its removal (stage 11 processes the queue).
func _queue_removal(e: SimEntity, reason: int) -> void:
	e.flags |= SimFlags.F_REMOVING
	spatial.set_tag(e.id, SimTag.of(e))
	_remove_q.append(e)
	_remove_reason.append(reason)
	_lists_ver += 1


## The end of an entity's life (sim_core 5.4 "Removals batch").
func _finalize_removal(e: SimEntity, reason: int) -> void:
	for s: SimSystem in stages:
		s.on_remove(self, e, reason)
	spatial.remove(e.id)
	if e._occ:
		var bbox: int = map.vacate(e.id)
		e._occ = false
		events.emit(SimEvent.NAV_CHANGED, e.x, e.y, maxi(bbox, 0), map.nav_version, e.id, 0)
	if e.kind == SimEntity.Kind.UNIT and not e.orders.is_empty():
		orders.clear(self, e, SimOrder.END_DIED)
	events.emit(SimEvent.REMOVED, e.x, e.y, e.id, e.kind, e.def_idx, e.owner, reason)
	by_id[e.id] = null
	e._gone = true
	_live_count -= 1
	_removed_since_compact += 1
	if (e.flags & SimFlags.F_HAS_CHILDREN) != 0:
		for c: SimEntity in entities:
			if c.parent == e.id and (c.flags & SimFlags.F_TETHERED) != 0 and (c.flags & SimFlags.F_GONE) == 0:
				kill(c, Cause.ORPHAN, 0, -1)
		for c: SimEntity in _spawn_queue:
			if c.parent == e.id and (c.flags & SimFlags.F_TETHERED) != 0 and (c.flags & SimFlags.F_GONE) == 0:
				kill(c, Cause.ORPHAN, 0, -1)


## Appends the parked spawns to the lists (ids ascending, all greater than the listed ones).
func _flush_spawns() -> void:
	if _spawn_queue.is_empty():
		return
	for e: SimEntity in _spawn_queue:
		if e._gone:
			continue
		e._listed = true
		entities.append(e)
		match e.kind:
			SimEntity.Kind.UNIT:
				units.append(e)
				(_units_by[_slot(e.owner)] as Array[SimEntity]).append(e)
			SimEntity.Kind.STRUCTURE:
				structures.append(e)
				(_structs_by[_slot(e.owner)] as Array[SimEntity]).append(e)
			SimEntity.Kind.WRECK:
				wrecks.append(e)
			SimEntity.Kind.ZONE:
				zone_ents.append(e)
			_:
				neutrals.append(e)
	_spawn_queue.clear()
	_lists_ver += 1


## Drops removed entities from every list (one O(n) pass per list, order preserved).
func _compact_lists() -> void:
	if _removed_since_compact == 0:
		return
	_removed_since_compact = 0
	_compact(entities)
	_compact(units)
	_compact(structures)
	_compact(wrecks)
	_compact(zone_ents)
	_compact(neutrals)
	for i: int in _units_by.size():
		_compact(_units_by[i] as Array[SimEntity])
		_compact(_structs_by[i] as Array[SimEntity])
	_lists_ver += 1


static func _compact(list: Array[SimEntity]) -> void:
	var w: int = 0
	for i: int in list.size():
		var e: SimEntity = list[i]
		if not e._gone:
			list[w] = e
			w += 1
	if w != list.size():
		list.resize(w)


func _list_remove(e: SimEntity, owner: int) -> void:
	if e.kind == SimEntity.Kind.UNIT:
		var ul: Array[SimEntity] = _units_by[_slot(owner)]
		ul.remove_at(ul.find(e))
	elif e.kind == SimEntity.Kind.STRUCTURE:
		var sl: Array[SimEntity] = _structs_by[_slot(owner)]
		sl.remove_at(sl.find(e))


func _list_insert(e: SimEntity, owner: int) -> void:
	var list: Array[SimEntity]
	if e.kind == SimEntity.Kind.UNIT:
		list = _units_by[_slot(owner)]
	elif e.kind == SimEntity.Kind.STRUCTURE:
		list = _structs_by[_slot(owner)]
	else:
		return
	var lo: int = 0
	var hi: int = list.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if list[mid].id < e.id:
			lo = mid + 1
		else:
			hi = mid
	list.insert(lo, e)
