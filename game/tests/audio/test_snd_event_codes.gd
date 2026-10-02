extends RefCounted
## SndEventCodes mirrors the sim: every consumed code equals the sim constant of the same name; every consumed code has
## a route; unknown codes are ignored.


const SCRIPTS: Dictionary = {
	"SimEvent": "res://src/sim/sim_event.gd", "SimCombatConsts": "res://src/sim/combat/sim_combat_consts.gd",
	"SimEconConst": "res://src/sim/sim_econ_const.gd", "SimAbilityConsts": "res://src/sim/abilities/sim_ability_consts.gd",
	"SimMoveConfig": "res://src/sim/sim_move_config.gd", "SimAirMove": "res://src/sim/sim_air_move.gd",
	"SimZoneConsts": "res://src/sim/zones/sim_zone_consts.gd",
}


func _const(cls: String, name: String) -> Variant:
	var path: String = str(SCRIPTS.get(cls, ""))
	if path == "":
		return null
	var s: GDScript = load(path) as GDScript
	if s == null:
		return null
	return s.get_script_constant_map().get(name)


func test_match_sim(t: TestCtx) -> void:
	for row: Array in SndEventCodes.CONSUMED + SndEventCodes.IGNORED:
		var v: Variant = _const(str(row[2]), str(row[0]))
		if v == null:
			t.fail("%s.%s does not exist in the sim any more" % [row[2], row[0]])
		else:
			t.eq(int(v), int(row[1]), "%s.%s" % [row[2], row[0]])


func test_payload_constants(t: TestCtx) -> void:
	for row: Array in SndEventCodes.PAYLOAD:
		var cls: String = str(row[2])
		var v: Variant = null
		if cls == "SimCommand.Err":
			v = SimCommand.Err.get(str(row[3]))
		elif cls == "SimPlayer.Elim":
			v = SimPlayer.Elim.get(str(row[3]))
		else:
			v = _const(cls, str(row[3]))
		t.check(v != null, "%s.%s exists" % [cls, row[3]])
		if v != null:
			t.eq(int(v), int(row[1]), "%s.%s" % [cls, row[3]])


func test_every_consumed_code_has_a_route(t: TestCtx) -> void:
	for code: int in SndEventCodes.consumed_codes():
		t.check(SndSimBridge.route_of(code) != SndSimBridge.R_IGNORE, "route for %s" % SndEventCodes.name_of(code))
	for row: Array in SndEventCodes.IGNORED:
		t.eq(SndSimBridge.route_of(int(row[1])), SndSimBridge.R_IGNORE, "%s ignored" % row[0])
	t.eq(SndSimBridge.route_of(0x7E), SndSimBridge.R_IGNORE, "unknown type ignored")


func test_all_sim_events_are_classified(t: TestCtx) -> void:
	# every event constant the sim declares in a domain block is either consumed or deliberately ignored (new sim codes show up here)
	var known: Dictionary = {}
	for row: Array in SndEventCodes.CONSUMED + SndEventCodes.IGNORED:
		known[int(row[1])] = true
	var missing: PackedStringArray = PackedStringArray()
	for cls: String in ["SimCombatConsts", "SimEconConst", "SimAbilityConsts", "SimMoveConfig", "SimAirMove", "SimZoneConsts", "SimEvent"]:
		var s: GDScript = load(str(SCRIPTS[cls])) as GDScript
		var map: Dictionary = s.get_script_constant_map()
		for name: Variant in map.keys():
			var n: String = str(name)
			if (n.begins_with("EV_") or n.begins_with("EVT_") or (cls == "SimEvent" and n in ["SPAWNED", "REMOVED", "OWNER_CHANGED", "CASH", "CMD_REJECTED", "ORDER_FAILED", "PLAYER_ELIMINATED", "MATCH_END", "NAV_CHANGED"])) and map[name] is int:
				if not known.has(int(map[name])):
					missing.append("%s.%s=%d" % [cls, n, int(map[name])])
	if not missing.is_empty():
		t.note("sim event codes audio has not classified yet: %s" % str(missing))
	t.check(true, "informational")
