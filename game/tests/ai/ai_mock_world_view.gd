class_name AiMockWorldView
extends AiWorldView
## Scriptable AiWorldView for unit tests (ai.md 2.6): no SimWorld at all. Entities, players, deposits, map passability and
## the power / research / construction polls are plain data set by the test. The GameData is the real one (shared cache) so
## profiles, roles and roster tables are the real ones.
##   var v := AiMockWorldView.new(0)
##   v.add_player(0, "roster.napc.vanilla", Vector2i(20, 20)); v.add_player(1, "roster.nec.vanilla", Vector2i(80, 80))
##   v.add_entity(10, 0, AiTypes.KIND_UNIT, def_idx, x, y)

var mock_tick: int = 0
var mock_data: GameData = null
var mock_credits: int = 5000
var mock_income_total: int = 0
var mock_supply: int = 200
var mock_demand: int = 100
var mock_research_active: int = -1
var mock_research_done: Dictionary = {}
var mock_cstate: PackedInt32Array = PackedInt32Array([0, 0, 0, -1])
var mock_warnings: PackedInt32Array = PackedInt32Array()
var mock_w: int = 96
var mock_h: int = 96
var mock_family: int = 0
var players: Array[Dictionary] = []  ## pid -> {alive, roster_idx, team, start (Vector2i)}
var ents: Dictionary = {}  ## eid -> PackedInt32Array (AiTypes.ROW_* layout)
var hidden: Dictionary = {}  ## eid -> true : not visible to me
var last_fire: Dictionary = {}  ## eid -> tick
var visible_fn: Callable = Callable()  ## (cx, cy) -> bool, empty = everything visible
var passable_fn: Callable = Callable()  ## (cx, cy, mc) -> bool, empty = everything passable
var deposits: Array[Dictionary] = []  ## {x, y, left, klass}
var collectors: PackedInt32Array = PackedInt32Array()
var structs_owned: PackedInt32Array = PackedInt32Array()


func _init(p_me: int = 0, p_omniscient: bool = false) -> void:
	super(p_me, p_omniscient)
	mock_data = GameData.load_default()


func add_player(pid: int, roster_id: String, start: Vector2i, team: int = -1) -> void:
	while players.size() <= pid:
		players.append({"alive": false, "roster_idx": -1, "team": -1, "start": Vector2i(-1, -1)})
	players[pid] = {"alive": true, "roster_idx": mock_data.roster_idx(roster_id), "team": team if team >= 0 else pid + 1, "start": start}


func add_entity(id: int, owner: int, kind: int, def: int, x: int, y: int, hp: int = 100, hp_max: int = 100, flags: int = 0, order: int = 0, paid: int = 0) -> void:
	var r: PackedInt32Array = PackedInt32Array()
	r.resize(AiTypes.ROW_SIZE)
	r[AiTypes.ROW_DEF] = def
	r[AiTypes.ROW_OWNER] = owner
	r[AiTypes.ROW_KIND] = kind
	r[AiTypes.ROW_X] = x
	r[AiTypes.ROW_Y] = y
	r[AiTypes.ROW_HP] = hp
	r[AiTypes.ROW_HP_MAX] = hp_max
	r[AiTypes.ROW_FLAGS] = flags
	r[AiTypes.ROW_ORDER] = order
	r[AiTypes.ROW_SINCE_COMBAT] = 9999
	r[AiTypes.ROW_PAID] = paid
	r[AiTypes.ROW_CONTAINER] = -1
	ents[id] = r


func remove_entity(id: int) -> void:
	ents.erase(id)
	hidden.erase(id)


func set_hp(id: int, hp: int) -> void:
	var r: PackedInt32Array = ents[id]
	r[AiTypes.ROW_HP] = hp
	ents[id] = r


func move_entity(id: int, x: int, y: int) -> void:
	var r: PackedInt32Array = ents[id]
	r[AiTypes.ROW_X] = x
	r[AiTypes.ROW_Y] = y
	ents[id] = r


func _ids_of(owner_is_me: bool) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var keys: Array = ents.keys()
	keys.sort()
	for id: int in keys:
		var o: int = (ents[id] as PackedInt32Array)[AiTypes.ROW_OWNER]
		var k: int = (ents[id] as PackedInt32Array)[AiTypes.ROW_KIND]
		if k != AiTypes.KIND_UNIT and k != AiTypes.KIND_STRUCTURE:
			continue
		if owner_is_me and o == _me:
			out.append(id)
		elif not owner_is_me and o != _me and is_enemy(o) and (omniscient or not hidden.has(id)):
			out.append(id)
	return out


# ------------------------------------------------------------------------------------------------- overrides
func begin_think(_world: RefCounted, dt: int) -> void:
	_dt = dt


func bound() -> bool:
	return true


func tick() -> int:
	return mock_tick


func match_running() -> bool:
	return true


func game_data() -> GameData:
	return mock_data


func player_slots() -> int:
	return players.size()


func player_count() -> int:
	return players.size()


func player_alive(p: int) -> bool:
	return p >= 0 and p < players.size() and bool(players[p]["alive"])


func team_of(p: int) -> int:
	return int(players[p]["team"])


func is_enemy(p: int) -> bool:
	return p != _me and player_alive(p) and team_of(p) != team_of(_me)


func is_ally(p: int) -> bool:
	return p != _me and player_alive(p) and team_of(p) == team_of(_me)


func roster_of(p: int) -> int:
	return int(players[p]["roster_idx"])


func roster_id_of(p: int) -> String:
	return mock_data.rosters[roster_of(p)].id


func roster(of_player: int = -1) -> DefRoster:
	return mock_data.rosters[roster_of(_me if of_player < 0 else of_player)]


func unit_def(def_idx: int, of_player: int = -1) -> DefUnit:
	return roster(of_player).unit(def_idx)


func structure_def(def_idx: int, of_player: int = -1) -> DefStructure:
	return roster(of_player).structure(def_idx)


func credits() -> int:
	return mock_credits


func income_total() -> int:
	return mock_income_total


func income_per_minute() -> int:
	return 0


func power_supply() -> int:
	return mock_supply


func power_demand() -> int:
	return mock_demand


func power_shortage() -> bool:
	return mock_demand > mock_supply


func unit_cap() -> int:
	return 150


func unit_count() -> int:
	return _ids_of(true).size()


func unit_cap_room() -> int:
	return 150 - unit_count()


func own_ids() -> PackedInt32Array:
	return _ids_of(true)


func alive(eid: int) -> bool:
	return ents.has(eid)


func read_row(eid: int, out: PackedInt32Array) -> bool:
	if not ents.has(eid):
		return false
	var r: PackedInt32Array = ents[eid]
	out.resize(AiTypes.ROW_SIZE)
	for i: int in AiTypes.ROW_SIZE:
		out[i] = r[i]
	return true


func e_def(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_DEF] if ents.has(eid) else -1


func e_owner(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_OWNER] if ents.has(eid) else -1


func e_kind(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_KIND] if ents.has(eid) else -1


func e_x(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_X] if ents.has(eid) else 0


func e_y(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_Y] if ents.has(eid) else 0


func e_hp(eid: int) -> int:
	return (ents[eid] as PackedInt32Array)[AiTypes.ROW_HP] if ents.has(eid) else 0


func e_last_fire(eid: int) -> int:
	return int(last_fire.get(eid, -1))


func visible_enemy_ids(out: PackedInt32Array) -> int:
	var ids: PackedInt32Array = _ids_of(false)
	out.resize(ids.size())
	for i: int in ids.size():
		out[i] = ids[i]
	return ids.size()


func enemies_in_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for id: int in _ids_of(false):
		var dx: int = e_x(id) - x
		var dy: int = e_y(id) - y
		if dx * dx + dy * dy <= r * r:
			out.append(id)
	return out.size()


func targetable_now(eid: int) -> bool:
	return ents.has(eid) and not hidden.has(eid)


func cell_visible(cx: int, cy: int) -> bool:
	return visible_fn.call(cx, cy) if visible_fn.is_valid() else true


func cell_explored(_cx: int, _cy: int) -> bool:
	return true


func construction_state(out: PackedInt32Array) -> void:
	out.resize(4)
	for i: int in 4:
		out[i] = mock_cstate[i]


func research_active() -> int:
	return mock_research_active


func research_done(res_def: int) -> bool:
	return mock_research_done.has(res_def)


func strategic_warnings(out: PackedInt32Array) -> int:
	out.resize(mock_warnings.size())
	for i: int in mock_warnings.size():
		out[i] = mock_warnings[i]
	return mock_warnings.size()


func collector_ids(out: PackedInt32Array) -> void:
	out.resize(collectors.size())
	for i: int in collectors.size():
		out[i] = collectors[i]


func struct_counts() -> PackedInt32Array:
	return structs_owned


func struct_count(struct_def: int) -> int:
	return structs_owned[struct_def] if struct_def >= 0 and struct_def < structs_owned.size() else 0


func map_w() -> int:
	return mock_w


func map_h() -> int:
	return mock_h


func passable(cx: int, cy: int, move_class: int) -> bool:
	if cx < 0 or cy < 0 or cx >= mock_w or cy >= mock_h:
		return false
	return passable_fn.call(cx, cy, move_class) if passable_fn.is_valid() else true


func region(cx: int, cy: int, move_class: int) -> int:
	return 1 if passable(cx, cy, move_class) else -1


func is_water(_cx: int, _cy: int) -> bool:
	return false


func map_family() -> int:
	return mock_family


func start_positions() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for p: Dictionary in players:
		out.append((p["start"] as Vector2i).x)
		out.append((p["start"] as Vector2i).y)
	return out


func start_cell_x(p: int) -> int:
	return (players[p]["start"] as Vector2i).x if p >= 0 and p < players.size() else -1


func start_cell_y(p: int) -> int:
	return (players[p]["start"] as Vector2i).y if p >= 0 and p < players.size() else -1


func deposit_ids(out: PackedInt32Array) -> int:
	out.resize(deposits.size())
	for i: int in deposits.size():
		out[i] = i
	return deposits.size()


func deposit_x(id: int) -> int:
	return int(deposits[id]["x"])


func deposit_y(id: int) -> int:
	return int(deposits[id]["y"])


func deposit_left(id: int) -> int:
	return int(deposits[id]["left"])


func deposit_klass(id: int) -> int:
	return int(deposits[id].get("klass", 0))


func deposit_radius(_id: int) -> int:
	return 3 * Fp.CELL


func deposit_cap(id: int) -> int:
	return int(deposits[id]["left"])


func deposit_harvesters(_id: int) -> int:
	return 0


func neutral_ids(out: PackedInt32Array) -> int:
	out.resize(0)
	return 0


func wrecks_in_circle(_x: int, _y: int, _r: int, out: PackedInt32Array) -> int:
	out.resize(0)
	return 0


# ------------------------------------------------------------------------------------------- test helpers
## A ready AiContext around `view` (no controller): profiles, roles, tech graph and the knowledge base are set up like
## AiController.bootstrap_from_world does. Set players / entities BEFORE calling.
static func make_ctx(view: AiMockWorldView, level: int = AiTypes.Difficulty.HARD, p_seed: int = 12345) -> AiContext:
	var ctx: AiContext = AiContext.new()
	var store: AiDataStore = AiDataStore.load_default()
	ctx.store = store
	ctx.cfg = AiConfig.make(view.me(), level, 0, p_seed)
	ctx.pid = view.me()
	ctx.diff = store.difficulty(level)
	ctx.view = view
	ctx.telemetry = AiTelemetry.new(view.me())
	ctx.cmd = AiCommandBuilder.new(view.me(), ctx.diff)
	ctx.rng = AiRng.new()
	ctx.rng.seed_from(p_seed)
	ctx.shared = AiSharedData.new(store)
	ctx.shared.bind(view)
	ctx.roster_idx = view.roster_of(view.me())
	ctx.res = ctx.shared.resolver(ctx.roster_idx)
	ctx.tech = ctx.shared.tech_graph(ctx.roster_idx)
	ctx.tick = view.tick()
	ctx.pers = AiPersonality.build(store, view.roster_id_of(view.me()), 0, ctx.diff, ctx.rng)
	ctx.kb = AiKnowledge.new()
	ctx.kb.setup(ctx)
	return ctx
