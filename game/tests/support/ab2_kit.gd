class_name Ab2Kit
extends RefCounted
## Test helpers of the AB2 slice (ability core, auras, containers): worlds on the REAL balance data (GameData.load_default)
## with real rosters, an ASCII terrain map (movement kit legend), spawn by def id, event readers and a stepper.
## Movement is ON by default (real orders and cargo walks) and can be disabled; fog is off unless asked for.

const CELL: int = 1024
const MV := preload("res://tests/support/move_test_kit.gd")
const K := preload("res://src/sim/abilities/sim_ability_consts.gd")

static var _data: GameData = null


static func data() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


## Open size x size map (2-cell cliff border), or the given ASCII rows; every structure and neutral footprint registered.
static func map(rows: PackedStringArray = PackedStringArray(), dd: GameData = null) -> MapData:
	var d: GameData = dd if dd != null else data()
	var r: PackedStringArray = rows if not rows.is_empty() else MV.grid(64)
	var m: MapData = MV.map_from(r)
	for s: DefStructure in d.structures:
		m.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	for n: DefNeutral in d.neutrals:
		m.set_footprint(SimEntity.Kind.NEUTRAL, n.index, MapFootprint.new(n.fp_w, n.fp_h, PackedByteArray(), false))
	return m


## o: rosters (Array of ids, default napc.usa / nec.vanilla), rows (ASCII map), movement (bool, default true),
## fog (bool), players (int, default from rosters), rules (Dictionary), teams (Array of team ids per pid), seed.
static func world(o: Dictionary = {}) -> SimWorld:
	var rosters: Array = o.get("rosters", ["roster.napc.usa", "roster.nec.vanilla"])
	var teams: Array = o.get("teams", [])
	var pl: Array = []
	for i: int in rosters.size():
		var team: int = int(teams[i]) if i < teams.size() else i + 1
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": rosters[i], "team": team, "color": i, "start": i, "handicap": 100})
	var rules: Dictionary = {"victory": 0, "fog": bool(o.get("fog", false)), "start_mode": SimMatchRules.START_NONE, "neutral_structures": 0}
	for k: Variant in (o.get("rules", {}) as Dictionary).keys():
		rules[k] = o["rules"][k]
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": int(o.get("seed", 11)), "map": {"id": "ab2"}, "rules": rules, "players": pl})
	var opts: Dictionary = {}
	var dis: Array = []
	if not bool(o.get("movement", true)):
		dis.append("SimMovementSystem")
	for x: Variant in o.get("disable", []):
		dis.append(x)
	opts["disable"] = dis
	opts["invariants_every"] = int(o.get("invariants_every", 25))  # SimInvariants (incl. containers / aura registries) run often
	var rows: PackedStringArray = o.get("rows", PackedStringArray())
	var d: GameData = o.get("data", null) as GameData
	return SimWorld.create(d if d != null else data(), cfg, map(rows, d), opts)


static func uid(id: String) -> int:
	return data().unit_idx(id)


static func spawn(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	var idx: int = data().unit_idx(id)
	if idx < 0:
		push_error("Ab2Kit: unknown unit " + id)
		return null
	var e: SimEntity = w.spawn_unit(idx, owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2, 0, 0, data().units[idx].cost, 0, SimEvent.SPAWN_PRODUCED)
	w.call("_flush_spawns")  # list membership at once (own_ids, research hooks) - the world flushes after every stage
	return e


## Structure spawned ACTIVE-looking: (cx, cy) = the footprint centre cell.
static func structure(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	var idx: int = data().structure_idx(id)
	if idx < 0:
		push_error("Ab2Kit: unknown structure " + id)
		return null
	var e: SimEntity = w.spawn_structure(idx, owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2, 0, 0, data().structures[idx].cost)
	w.call("_flush_spawns")
	return e


static func neutral(w: SimWorld, id: String, cx: int, cy: int) -> SimEntity:
	var idx: int = data().neutral_idx(id) if data().has_method("neutral_idx") else -1
	if idx < 0:
		for n: DefNeutral in data().neutrals:
			if n.id == id:
				idx = n.index
	var e: SimEntity = w.spawn_entity(SimEntity.Kind.NEUTRAL, idx, -1, cx * CELL + CELL / 2, cy * CELL + CELL / 2, 0, SimFlags.F_INITIAL)
	w.call("_flush_spawns")
	return e


## Every unit stops shooting (SimCombatConsts.ST_HOLD_FIRE) - for tests that watch healing and bonuses undisturbed.
static func hold_fire(w: SimWorld) -> void:
	for e: SimEntity in w.units:
		if e.combat != null:
			e.combat.stance = SimCombatConsts.ST_HOLD_FIRE


static func place(w: SimWorld, e: SimEntity, cx: int, cy: int) -> void:
	w.set_pos(e, cx * CELL + CELL / 2, cy * CELL + CELL / 2, true)


static func run(w: SimWorld, ticks: int) -> void:
	for _i: int in ticks:
		w.step()


static func run_to(w: SimWorld, tick: int) -> void:
	while w.tick < tick:
		w.step()


## Steps until pred() holds (checked before each step); returns the tick it held at, -1 on timeout.
static func run_until(w: SimWorld, pred: Callable, max_ticks: int) -> int:
	for _i: int in max_ticks:
		if pred.call():
			return w.tick
		w.step()
	return w.tick if pred.call() else -1


## Number of events of `type` in the world's buffer (optionally with payload a == value); the buffer accumulates until
## w.clear_events().
static func count_events(w: SimWorld, type: int, a: int = -1) -> int:
	var n: int = 0
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		if d[i * SimEvent.STRIDE + SimEvent.I_TYPE] == type and (a < 0 or d[i * SimEvent.STRIDE + SimEvent.I_A] == a):
			n += 1
	return n


## Payload field (SimEvent.I_*) of the n-th event of `type` (0-based), or -1.
static func event_field(w: SimWorld, type: int, nth: int, field: int) -> int:
	var d: PackedInt32Array = w.events.data
	var k: int = 0
	for i: int in d.size() / SimEvent.STRIDE:
		if d[i * SimEvent.STRIDE + SimEvent.I_TYPE] == type:
			if k == nth:
				return d[i * SimEvent.STRIDE + field]
			k += 1
	return -1


## Sum of a lease stat on e right now.
static func lease_bp(w: SimWorld, e: SimEntity, stat: int) -> int:
	return SimCombatMods.sum_bp(e.combat, stat, w.tick) if e.combat != null else 0


static func cmd(w: SimWorld, pid: int, ints: PackedInt32Array) -> void:
	w.submit_raw(pid, ints)


## Wall-clock free "mode of a slot" reader.
static func slot_state(e: SimEntity, kind: int) -> int:
	var s: int = e.abil.slot_of_kind(kind) if e.abil != null else -1
	return e.abil.slots[s * K.SLOT_STRIDE + K.SL_STATE] if s >= 0 else -1
