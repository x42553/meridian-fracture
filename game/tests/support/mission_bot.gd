class_name MissionBot
extends SimBot
## MIS3: the scripted macro bot (SimBot: build ladder, production, rally) steered by mission GOALS. SimBot knows nothing about scripted objectives,
## so a goal list says what a competent human would do while an objective is in a state: attack an area, hold a rally point there, or walk
## some unit types to an area. Goals only choose WHERE; economy, production and every fight are SimBot's. Without an active goal the army
## stays at the base (generic skirmish attacks happen only with opts.generic_attack).
##
## goal: {obj: objective id ("" = always), state: "active" (default) | "completed" | "failed" | "hidden", from_s, to_s (seconds, optional window),
##        mode: "attack" | "rally" | "move_def" | "launch" (superweapon, or support power with `power`: id, at the area centre), area: area id, min_army: int (attack: units needed before the push, default 6),
##        defs: [unit ids] (move_def), tags: [] unused}
## The first goal (in list order) whose condition holds is the active one.

const OBJ_STATE_NAMES: PackedStringArray = ["hidden", "active", "completed", "failed"]

var goals: Array = []
var _mw: SimWorld = null
var _goal_attacking: Dictionary = {}  ## goal index -> true once the push started
var _last_rally_goal: int = -2
var _last_move: Dictionary = {}  ## goal index -> tick of the last move_def order
var active_goal: int = -1


## SimBot never builds amphibious units (U_SKIP) although the Pacific Dominion's main tank is one. opts.amphibious = true lets the bot field them by their other tags.
func _unit_role(u: DefUnit) -> int:
	if bool(opts.get("amphibious", false)) and (u.tags & DefEnums.UT_AMPHIBIOUS) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and (u.flags & DefEnums.UF_UNARMED) == 0 \
			and (u.tags & (DefEnums.UT_AIRCRAFT | DefEnums.UT_SHIP | DefEnums.UT_SUBMARINE)) == 0:
		if (u.tags & DefEnums.UT_ANTI_AIR) != 0 and (u.tags & DefEnums.UT_TANK) == 0:
			return U_ANTI_AIR
		if (u.tags & DefEnums.UT_TANK) != 0:
			return U_TANK
		if (u.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0:
			return U_ARTILLERY
		if (u.tags & DefEnums.UT_INFANTRY) != 0:
			return U_INFANTRY
		return U_LIGHT
	return super._unit_role(u)


## opts.include_defs: unit ids that travel with the army although SimBot would skip them (unarmed escorts such as the Han Link Operator).
func _army(world: SimWorld, out: PackedInt32Array) -> void:
	super._army(world, out)
	var inc: Array = opts.get("include_defs", [])
	if inc.is_empty():
		return
	var idxs: PackedInt32Array = PackedInt32Array()
	for did: Variant in inc:
		idxs.append(world.data.unit_idx(str(did)))
	for u: SimEntity in world.units_of(pid):
		if (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == 0 and idxs.has(u.def_idx):
			out.append(u.id)


func _manage_army(world: SimWorld) -> void:
	_mw = world
	# power goals: launch the superweapon / use a support power at the centre of an area while the condition holds
	for i: int in goals.size():
		var pg: Dictionary = goals[i]
		if str(pg.get("mode", "")) == "launch" and _goal_holds(world, pg) and world.tick - int(_last_move.get(i, -1000)) >= 100:
			_last_move[i] = world.tick
			var pxy: Vector2i = _area_xy(world, str(pg["area"]))
			if str(pg.get("power", "")) != "":
				_send(world, SimCmd.use_power(world.data.power_idx(str(pg["power"])), pxy.x, pxy.y))
			elif SimSuperweapons.can_launch(world, pid, pxy.x, pxy.y, 0) == SimEconConst.RSN_OK:
				_send(world, SimCmd.launch_superweapon(pxy.x, pxy.y, 0))
	# walking goals are independent of the army goal: every one whose condition holds runs
	for i: int in goals.size():
		if str((goals[i] as Dictionary).get("mode", "")) == "move_def" and _goal_holds(world, goals[i]):
			_goal_move_def(world, i, goals[i], _area_xy(world, str((goals[i] as Dictionary)["area"])))
	var gi: int = _find_goal(world)
	active_goal = gi
	if gi < 0:
		if bool(opts.get("generic_attack", false)):
			super._manage_army(world)
		else:
			_restore_rally(world)
		return
	var g: Dictionary = goals[gi]
	var xy: Vector2i = _area_xy(world, str(g["area"]))
	match str(g.get("mode", "attack")):
		"attack":
			_goal_attack(world, gi, xy, int(g.get("min_army", 6)))
		"rally":
			_goal_rally(world, gi, xy)


func _find_goal(world: SimWorld) -> int:
	for i: int in goals.size():
		var gm: String = str((goals[i] as Dictionary).get("mode", "attack"))
		if gm != "move_def" and gm != "launch" and _goal_holds(world, goals[i]):
			return i
	return -1


func _goal_holds(world: SimWorld, g: Dictionary) -> bool:
	var m: SimMissionSystem = world.mission
	var oid: String = str(g.get("obj", ""))
	if oid != "":
		var oi: int = m.def.objective_idx(oid)
		if oi < 0 or OBJ_STATE_NAMES[m.obj_state[oi]] != str(g.get("state", "active")):
			return false
	var s: int = world.tick / 20
	if g.has("from_s") and s < int(g["from_s"]):
		return false
	if g.has("to_s") and s >= int(g["to_s"]):
		return false
	return true


func _area_xy(world: SimWorld, area_id: String) -> Vector2i:
	var c: int = world.mission.area_center_cell(world, world.mission.def.area_idx(area_id))
	return Vector2i((c % world.map.w) * SimConfig.CELL + SimConfig.CELL / 2, (c / world.map.w) * SimConfig.CELL + SimConfig.CELL / 2)


func _goal_attack(world: SimWorld, gi: int, xy: Vector2i, min_army: int) -> void:
	var army: PackedInt32Array = PackedInt32Array()
	_army(world, army)
	if not _goal_attacking.has(gi):
		if army.size() < min_army:
			_goal_rally_default(world)
			return
		_goal_attacking[gi] = true
	var go: PackedInt32Array = PackedInt32Array()
	for id: int in army:
		var u: SimEntity = world.get_entity(id)
		if u.orders.is_empty() or (u.orders[0].type != SimOrder.T_ATTACK_MOVE and u.orders[0].type != SimOrder.T_ATTACK):
			if world.tick - int(_last_go.get(id, -1000)) >= 100:
				_last_go[id] = world.tick
				go.append(id)
	if not go.is_empty():
		_send(world, SimCmd.attack_move(go, xy.x, xy.y))


func _goal_rally(world: SimWorld, gi: int, xy: Vector2i) -> void:
	if _last_rally_goal != gi:
		_last_rally_goal = gi
		_rally_x = xy.x
		_rally_y = xy.y
		_rally_set.clear()
	var army: PackedInt32Array = PackedInt32Array()
	_army(world, army)
	var go: PackedInt32Array = PackedInt32Array()
	for id: int in army:
		var u: SimEntity = world.get_entity(id)
		var dx: int = u.x - xy.x
		var dy: int = u.y - xy.y
		if u.orders.is_empty() and dx * dx + dy * dy > 10 * SimConfig.CELL * 10 * SimConfig.CELL:
			go.append(id)
	if not go.is_empty():
		_send(world, SimCmd.attack_move(go, xy.x, xy.y))


func _goal_rally_default(world: SimWorld) -> void:
	_restore_rally(world)


func _restore_rally(world: SimWorld) -> void:
	if _last_rally_goal != -2 and _last_rally_goal != -1:
		_last_rally_goal = -1
		_rally_from_hq(world)
		_rally_set.clear()


func _goal_move_def(world: SimWorld, gi: int, g: Dictionary, xy: Vector2i) -> void:
	if world.tick - int(_last_move.get(gi, -1000)) < 200:
		return
	_last_move[gi] = world.tick
	var ids: PackedInt32Array = PackedInt32Array()
	for did: Variant in g.get("defs", []):
		var idx: int = world.data.unit_idx(str(did))
		for u: SimEntity in world.units_of(pid):
			if (u.flags & SimFlags.F_GONE) == 0 and u.def_idx == idx:
				var dx: int = u.x - xy.x
				var dy: int = u.y - xy.y
				if dx * dx + dy * dy > 6 * SimConfig.CELL * 6 * SimConfig.CELL:
					ids.append(u.id)
	if not ids.is_empty():
		_send(world, SimCmd.move(ids, xy.x, xy.y))
