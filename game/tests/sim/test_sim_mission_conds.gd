extends RefCounted
## MIS1: every condition kind of the mission system, evaluated by the real sim on a real generated map. One mission holds one
## trigger per condition (each completes its own objective), so a test reads which conditions are true at a given moment.

const TANK: String = "unit.napc.guardian_tank"
const SQUAD: String = "unit.napc.rifle_squad"
const JAGER: String = "unit.nec.jager_squad"
const GEN: String = "structure.shared.generator"
const WATCH: String = "structure.shared.watchtower"
const HQ: String = "structure.shared.headquarters"

var _cases: Array = []  ## [name, when]


func _add(name: String, when: Dictionary) -> void:
	_cases.append([name, when])


func _build_cases() -> void:
	if not _cases.is_empty():
		return
	_add("time_ge", {"kind": "time", "seconds": 2})
	_add("time_lt", {"kind": "time", "cmp": "<", "ticks": 100000})
	_add("time_never", {"kind": "time", "seconds": 1000})
	_add("count_def", {"kind": "count", "owner": 0, "def": TANK, "value": 3})
	_add("count_def_gt", {"kind": "count", "owner": 0, "def": TANK, "cmp": ">", "value": 3})
	_add("count_tag", {"kind": "count", "owner": 0, "tag": "tank", "value": 3})
	_add("count_tags_all", {"kind": "count", "owner": 0, "tag": ["tank", "ground"], "value": 3})
	_add("count_area", {"kind": "count", "owner": 0, "def": TANK, "area": "a_base", "value": 3})
	_add("count_area_far", {"kind": "count", "owner": 0, "area": "a_far", "cmp": "==", "value": 0})
	_add("count_struct", {"kind": "count", "owner": 0, "of": "structure", "def": HQ, "cmp": "==", "value": 1})
	_add("count_any", {"kind": "count", "owner": 0, "of": "any", "value": 6})
	_add("count_team", {"kind": "count", "owner": "team:2", "def": JAGER, "value": 2})
	_add("count_enemies", {"kind": "count", "owner": "enemies_of:0", "value": 2})
	_add("count_allies_none", {"kind": "count", "owner": "allies_of:0", "cmp": "==", "value": 0})
	_add("count_all", {"kind": "count", "owner": "all", "of": "any", "value": 8})
	_add("count_neutral", {"kind": "count", "owner": "neutral", "of": "structure", "value": 1})
	_add("struct_def_exists", {"kind": "structure", "state": "exists", "owner": 1, "def": GEN})
	_add("struct_def_missing", {"kind": "structure", "state": "exists", "owner": 0, "def": GEN})
	_add("struct_placed_exists", {"kind": "structure", "state": "exists", "placed": "gen1"})
	_add("struct_placed_owner_ok", {"kind": "structure", "state": "exists", "placed": "gen1", "owner": 1})
	_add("struct_placed_owner_wrong", {"kind": "structure", "state": "exists", "placed": "gen1", "owner": 0})
	_add("struct_destroyed", {"kind": "structure", "state": "destroyed", "placed": "gen1"})
	_add("struct_captured", {"kind": "structure", "state": "captured", "placed": "watch1"})
	_add("area_left", {"kind": "area_left", "owner": 1, "area": "a_far"})
	_add("credits_ge", {"kind": "credits", "owner": 0, "value": 5000})
	_add("credits_gt", {"kind": "credits", "owner": 0, "cmp": ">", "value": 5000})
	_add("credits_sum_team", {"kind": "credits", "owner": "all", "value": 10000})
	_add("research_done", {"kind": "research", "owner": 0, "research": "research.napc.adaptive_plating"})
	_add("power_floor", {"kind": "power", "owner": 0, "cmp": ">=", "value": -100000})
	_add("power_pos", {"kind": "power", "owner": 0, "cmp": ">=", "value": 100000})
	_add("sp_ready", {"kind": "support_power", "owner": 0, "slot": 0, "state": "ready"})
	_add("sp_used", {"kind": "support_power", "owner": 0, "slot": 0, "state": "used"})
	_add("sw_fired", {"kind": "superweapon", "owner": 0, "state": "fired"})
	_add("sw_ready", {"kind": "superweapon", "owner": 0, "state": "ready"})
	_add("defeated", {"kind": "defeated", "owner": 1})
	_add("no_assets_p1", {"kind": "no_assets", "owner": 1})
	_add("no_assets_p0", {"kind": "no_assets", "owner": 0})
	_add("wave_spawned", {"kind": "wave", "wave": "w1", "state": "spawned"})
	_add("wave_cleared", {"kind": "wave", "wave": "w1", "state": "cleared"})
	_add("trigger_fired", {"kind": "trigger", "trigger": "t_time_ge"})
	_add("trigger_never", {"kind": "trigger", "trigger": "t_time_never", "cmp": ">=", "value": 1})
	_add("objective_active", {"kind": "objective", "objective": "o_time_ge", "state": "active"})
	_add("objective_completed", {"kind": "objective", "objective": "o_time_ge", "state": "completed"})
	_add("timer_expired", {"kind": "timer", "timer": "tm"})
	_add("all_true", {"all": [{"kind": "time", "seconds": 0}, {"kind": "count", "owner": 0, "def": TANK, "value": 1}]})
	_add("all_false", {"all": [{"kind": "time", "seconds": 0}, {"kind": "time", "seconds": 1000}]})
	_add("any_true", {"any": [{"kind": "time", "seconds": 1000}, {"kind": "time", "seconds": 0}]})
	_add("any_false", {"any": [{"kind": "time", "seconds": 1000}, {"kind": "time", "seconds": 2000}]})
	_add("not_false", {"not": {"kind": "time", "seconds": 1000}})
	_add("not_true", {"not": {"kind": "time", "seconds": 0}})
	_add("nested", {"all": [{"any": [{"kind": "time", "seconds": 1000}, {"not": {"kind": "time", "seconds": 1000}}]}, {"kind": "time", "seconds": 0}]})


func _mission() -> Dictionary:
	_build_cases()
	var objectives: Array = []
	var triggers: Array = []
	for c: Variant in _cases:
		var name: String = (c as Array)[0]
		objectives.append({"id": "o_" + name, "kind": "secondary", "text": name})
		triggers.append({"id": "t_" + name, "when": (c as Array)[1], "then": [{"do": "set_objective", "objective": "o_" + name, "state": "completed"}]})
	# setup trigger (id sorts first): placed structures and a wave for the others to look at
	triggers.append({"id": "a_setup", "when": {"kind": "time", "ticks": 0}, "then": [
		{"do": "spawn_structure", "owner": 1, "def": GEN, "area": "a_far", "id": "gen1"},
		{"do": "spawn_structure", "owner": "neutral", "def": WATCH, "area": "a_mid", "id": "watch1"},
		{"do": "spawn_units", "owner": 1, "def": JAGER, "count": 2, "area": "a_far", "wave": "w1"},
		{"do": "timer_start", "timer": "tm"}]})
	var start: Dictionary = {"mode": "hq", "units": [{"def": TANK, "count": 3, "dx": 4, "dy": 3}, {"def": SQUAD, "count": 2, "dx": 3, "dy": 6}]}
	var players: Array = [
		{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": start},
		{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
	]
	return MissionKit.base("c_all", {"objectives": objectives, "triggers": triggers, "players": players,
		"timers": [{"id": "tm", "seconds": 3}]})


func _world() -> SimWorld:
	var d: GameData = MissionKit.data({"c_all": _mission()})
	return MissionKit.world(d, "c_all", {"events": false})


func _done(w: SimWorld, name: String) -> bool:
	return w.mission.obj_state[w.mission.def.objective_idx("o_" + name)] == SimMissionConst.OBJ_COMPLETED


func _true_set(w: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_build_cases()
	for c: Variant in _cases:
		if _done(w, (c as Array)[0]):
			out.append((c as Array)[0])
	return out


func test_conditions_at_start(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if not t.not_null(w, "world"):
		return
	t.eq(w.units_of(0).size(), 5, "5 start units")
	MissionKit.run(w, 70)
	var got: PackedStringArray = _true_set(w)
	var expect_true: PackedStringArray = ["time_ge", "time_lt", "count_def", "count_tag", "count_tags_all", "count_area", "count_area_far", "count_struct", "count_any",
		"count_team", "count_enemies", "count_allies_none", "count_all", "count_neutral", "struct_def_exists", "struct_placed_exists", "struct_placed_owner_ok",
		"credits_ge", "credits_sum_team", "power_floor", "wave_spawned", "trigger_fired", "objective_active", "objective_completed", "timer_expired",
		"all_true", "any_true", "not_false", "nested"]
	for n: String in expect_true:
		t.check(got.has(n), "true: " + n)
	var expect_false: PackedStringArray = ["time_never", "count_def_gt", "struct_def_missing", "struct_placed_owner_wrong", "struct_destroyed", "struct_captured", "area_left",
		"credits_gt", "research_done", "power_pos", "sp_used", "sw_fired", "defeated", "no_assets_p1", "no_assets_p0", "wave_cleared", "trigger_never", "all_false",
		"any_false", "not_true", "sp_ready", "sw_ready"]
	for n: String in expect_false:
		t.check(not got.has(n), "false: " + n)


func test_objective_state_is_checked_the_pass_after_the_change(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	# t_objective_active and t_objective_completed are independent triggers evaluated in id order; "active" fires at the first pass
	# (o_time_ge is still active there because t_time_ge sorts after t_objective_*), "completed" the pass after
	MissionKit.run(w, 6)
	t.check(_done(w, "objective_active"), "active seen on the first pass")
	t.check(not _done(w, "objective_completed"), "completed not yet on the first pass")
	MissionKit.run(w, 50)
	t.check(_done(w, "objective_completed"))


func test_destroyed_captured_area_left_wave_cleared(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.run(w, 10)
	var gen_id: int = w.mission.placed_id[w.mission.def.placed.find("gen1")]
	var watch_id: int = w.mission.placed_id[w.mission.def.placed.find("watch1")]
	t.gt(gen_id, 0, "gen1 spawned")
	t.gt(watch_id, 0, "watch1 spawned")
	t.eq(w.get_entity(watch_id).owner, -1, "neutral structure")
	# kill the wave and the generator, capture the watchtower
	for e: SimEntity in w.units_of(1).duplicate():
		w.kill(e, SimWorld.Cause.SCRIPT)
	w.kill(w.get_entity(gen_id), SimWorld.Cause.SCRIPT)
	t.check(w.change_owner(watch_id, 0, SimEvent.OWNER_CAPTURE), "capture")
	MissionKit.run(w, 15)
	var got: PackedStringArray = _true_set(w)
	for n: String in ["wave_cleared", "struct_destroyed", "struct_captured", "area_left", "no_assets_p1"]:
		t.check(got.has(n), "true after the changes: " + n)


func test_values_set_directly_reach_the_conditions(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	var p0: SimPlayer = w.players[0]
	var ri: int = w.data.research_idx("research.napc.adaptive_plating")
	t.gt(ri, -1, "research exists")
	p0.econ.researched[ri] = 1
	p0.econ.slots[0].uses = 1
	p0.econ.slots[0].announced = true
	p0.econ.slots[0].ready_tick = 0
	var sw: SimPowerSlot = p0.econ.slots[SimEconConst.SLOT_SW]
	t.gt(sw.def_idx, -1, "the roster has a superweapon")
	sw.last_activation_tick = 5
	sw.sw_state = SimEconConst.SW_READY
	w.add_credits(0, 100, SimEvent.CASH_SCRIPT)
	p0.power_supply = 500
	p0.power_demand = 100
	MissionKit.run(w, 10)
	var got: PackedStringArray = _true_set(w)
	for n: String in ["research_done", "sp_used", "sp_ready", "sw_fired", "credits_gt", "power_floor"]:
		t.check(got.has(n), "true: " + n)
	# the superweapon stage recomputes sw_state every tick, so READY is evaluated directly (no step in between)
	sw.sw_state = SimEconConst.SW_READY
	var c: DefMissionCond = DefMissionCond.new()
	c.op = DefMissionCond.Op.SUPERWEAPON
	c.owner_mode = DefMissionCond.OWN_PID
	c.owner_val = 0
	c.state = 1
	t.check(SimMissionConds.eval(w.mission, w, c), "superweapon ready")
	sw.sw_state = SimEconConst.SW_CHARGING
	t.check(not SimMissionConds.eval(w.mission, w, c), "superweapon charging is not ready")
	# the economy recomputes the balance itself; the cond reads SimPlayer.power_supply / demand (checked next pass)
	w.eliminate(1, SimPlayer.Elim.SCRIPT)
	MissionKit.run(w, 10)
	t.check(_done(w, "defeated"), "defeated after eliminate")


func test_power_condition_reads_the_player_balance(t: TestCtx) -> void:
	var w: SimWorld = _world()
	if w == null:
		return
	MissionKit.run(w, 5)
	var p0: SimPlayer = w.players[0]
	var bal: int = p0.power_supply - p0.power_demand
	var want_pos: bool = bal >= 100000
	t.eq(_done(w, "power_pos"), want_pos, "power_pos agrees with the balance %d" % bal)
