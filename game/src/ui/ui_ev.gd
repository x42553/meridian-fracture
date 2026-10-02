class_name UiEv
extends RefCounted
## The ONLY file that names event codes and field offsets the UI consumes (ui.md 6.2.1). A record is
## [type, tick, x, y, a, b, c, d, e, f] (stride 10); x, y in sub-cell units or (0, 0). The trigger names of
## notices.json are the lower-case names below (`by_name(&"attack_alert") == 214`).

const STRIDE: int = 10
const I_TYPE: int = 0
const I_TICK: int = 1
const I_X: int = 2
const I_Y: int = 3
const I_A: int = 4
const I_B: int = 5
const I_C: int = 6
const I_D: int = 7
const I_E: int = 8
const I_F: int = 9

# core registry
const SPAWNED: int = 1
const REMOVED: int = 2
const OWNER_CHANGED: int = 3
const CASH: int = 4
const CMD_REJECTED: int = 5
const ORDER_FAILED: int = 6
const PLAYER_ELIMINATED: int = 7
const MATCH_END: int = 8
# mission block (MIS2): SimEvent.MISSION_*, fields documented there
const MISSION_OBJECTIVE: int = 130  ## a = objective idx, b = new state, c = kind, d = previous state
const MISSION_MESSAGE: int = 131  ## a = message idx, b = announcer idx into DefMission.announcers (-1 none)
const MISSION_TIMER: int = 132  ## a = timer idx, b = 0 started / 1 stopped / 2 expired, c = duration ticks
const MISSION_RESULT: int = 133  ## a = pid, b = 1 win / 2 lose, c = team
const MISSION_CAMERA: int = 134  ## x, y = target (sub-cell units), a = area idx (-1), b = display ticks
const MISSION_MUSIC: int = 135  ## a = DefMissionAction.MUSIC_NAMES index
# combat block
const DEATH: int = 208
const EMP: int = 213
const ATTACK_ALERT: int = 214
# abilities block
const MODE_CHANGED: int = 235
const ABILITY_USED: int = 236
const ABILITY_READY: int = 237
const LOADED: int = 240
const UNLOADED: int = 241
const UNLOAD_BLOCKED: int = 242
const GARRISON_CHANGED: int = 243
const SCAN_WARNING: int = 250
const BUFF_APPLIED: int = 259
# economy block
const PLACE_REJECTED: int = 301
const STRUCTURE_READY: int = 302
const UNIT_PRODUCED: int = 305
const QUEUE_STATE: int = 306
const RESEARCH_COMPLETE: int = 307
const INSUFFICIENT_FUNDS: int = 309
const UNIT_CAP_REACHED: int = 310
const POWER_SHORTAGE: int = 311
const POWER_RESTORED: int = 312
const STRUCTURE_SOLD: int = 314
const HQ_DEPLOYED: int = 317
const HQ_UNDEPLOYED: int = 318
const POWER_UNLOCKED: int = 400
const POWER_READY: int = 401
const POWER_ACTIVATED: int = 402
const WARNING: int = 404
const SW_READY: int = 405
const SW_CANCELLED: int = 406
const SW_EXEC_START: int = 407
const SW_IMPACT: int = 408
const SW_DONE: int = 409

## Reasons carried by SPAWNED.f / REMOVED.e (= SimEvent.SPAWN_* / REM_*).
const SPAWN_DEPLOYED: int = 3
const REM_KILLED: int = 0
const REM_SOLD: int = 1
const REM_DEPLOYED: int = 3
const REM_CONSUMED: int = 4

## Name (lower case, notices.json trigger) -> code, in table order.
const NAMES: Dictionary = {
	&"spawned": 1, &"removed": 2, &"owner_changed": 3, &"cash": 4, &"cmd_rejected": 5, &"order_failed": 6,
	&"player_eliminated": 7, &"match_end": 8, &"mission_objective": 130, &"mission_message": 131, &"mission_timer": 132,
	&"mission_result": 133, &"mission_camera": 134, &"mission_music": 135, &"death": 208, &"emp": 213, &"attack_alert": 214,
	&"mode_changed": 235, &"ability_used": 236, &"ability_ready": 237, &"loaded": 240, &"unloaded": 241,
	&"unload_blocked": 242, &"garrison_changed": 243, &"scan_warning": 250, &"buff_applied": 259,
	&"place_rejected": 301, &"structure_ready": 302, &"unit_produced": 305, &"queue_state": 306,
	&"research_complete": 307, &"insufficient_funds": 309, &"unit_cap_reached": 310, &"power_shortage": 311,
	&"power_restored": 312, &"structure_sold": 314, &"hq_deployed": 317, &"hq_undeployed": 318,
	&"power_unlocked": 400, &"power_ready": 401, &"power_activated": 402, &"warning": 404, &"sw_ready": 405,
	&"sw_cancelled": 406, &"sw_exec_start": 407, &"sw_impact": 408, &"sw_done": 409,
}

## [UiEv name, owner class, constant name in that class] for verify_against_sim.
const _SIM_MAP: Array = [
	[&"spawned", "SimEvent", "SPAWNED"], [&"removed", "SimEvent", "REMOVED"], [&"owner_changed", "SimEvent", "OWNER_CHANGED"],
	[&"cash", "SimEvent", "CASH"], [&"cmd_rejected", "SimEvent", "CMD_REJECTED"], [&"order_failed", "SimEvent", "ORDER_FAILED"],
	[&"player_eliminated", "SimEvent", "PLAYER_ELIMINATED"], [&"match_end", "SimEvent", "MATCH_END"],
	[&"mission_objective", "SimEvent", "MISSION_OBJECTIVE"], [&"mission_message", "SimEvent", "MISSION_MESSAGE"],
	[&"mission_timer", "SimEvent", "MISSION_TIMER"], [&"mission_result", "SimEvent", "MISSION_RESULT"],
	[&"mission_camera", "SimEvent", "MISSION_CAMERA"], [&"mission_music", "SimEvent", "MISSION_MUSIC"],
	[&"death", "SimCombatConsts", "EV_DEATH"], [&"emp", "SimCombatConsts", "EV_EMP"], [&"attack_alert", "SimCombatConsts", "EV_ATTACK_ALERT"],
	[&"mode_changed", "SimAbilityConsts", "EV_MODE_CHANGED"], [&"ability_used", "SimAbilityConsts", "EV_ABILITY_USED"],
	[&"ability_ready", "SimAbilityConsts", "EV_ABILITY_READY"], [&"loaded", "SimAbilityConsts", "EV_LOADED"],
	[&"unloaded", "SimAbilityConsts", "EV_UNLOADED"], [&"unload_blocked", "SimAbilityConsts", "EV_UNLOAD_BLOCKED"],
	[&"garrison_changed", "SimAbilityConsts", "EV_GARRISON_CHANGED"], [&"scan_warning", "SimAbilityConsts", "EV_SCAN_WARNING"],
	[&"buff_applied", "SimAbilityConsts", "EV_BUFF_APPLIED"],
	[&"place_rejected", "SimEconConst", "EVT_PLACE_REJECTED"], [&"structure_ready", "SimEconConst", "EVT_STRUCTURE_READY"],
	[&"unit_produced", "SimEconConst", "EVT_UNIT_PRODUCED"], [&"queue_state", "SimEconConst", "EVT_QUEUE_STATE"],
	[&"research_complete", "SimEconConst", "EVT_RESEARCH_COMPLETE"], [&"insufficient_funds", "SimEconConst", "EVT_INSUFFICIENT_FUNDS"],
	[&"unit_cap_reached", "SimEconConst", "EVT_UNIT_CAP_REACHED"], [&"power_shortage", "SimEconConst", "EVT_POWER_SHORTAGE"],
	[&"power_restored", "SimEconConst", "EVT_POWER_RESTORED"], [&"structure_sold", "SimEconConst", "EVT_STRUCTURE_SOLD"],
	[&"hq_deployed", "SimEconConst", "EVT_HQ_DEPLOYED"], [&"hq_undeployed", "SimEconConst", "EVT_HQ_UNDEPLOYED"],
	[&"power_unlocked", "SimEconConst", "EVT_POWER_UNLOCKED"], [&"power_ready", "SimEconConst", "EVT_POWER_READY"],
	[&"power_activated", "SimEconConst", "EVT_POWER_ACTIVATED"], [&"warning", "SimEconConst", "EVT_WARNING"],
	[&"sw_ready", "SimEconConst", "EVT_SW_READY"], [&"sw_cancelled", "SimEconConst", "EVT_SW_CANCELLED"],
	[&"sw_exec_start", "SimEconConst", "EVT_SW_EXEC_START"], [&"sw_impact", "SimEconConst", "EVT_SW_IMPACT"],
	[&"sw_done", "SimEconConst", "EVT_SW_DONE"],
]


## Trigger name of notices.json -> code, -1 unknown.
static func by_name(name: StringName) -> int:
	return int(NAMES.get(name, -1))


## Code -> trigger name (&"" for a code the UI does not consume).
static func name_of(code: int) -> StringName:
	for k: Variant in NAMES:
		if int(NAMES[k]) == code:
			return k as StringName
	return &""


## True when the UI consumes this code (unknown types are skipped without an error).
static func known(code: int) -> bool:
	return NAMES.values().has(code)


## Number of whole records.
static func count(records: PackedInt32Array) -> int:
	return records.size() / STRIDE


## Field `slot` (I_*) of record i; no allocation.
static func field(records: PackedInt32Array, i: int, slot: int) -> int:
	return records[i * STRIDE + slot]


## EV_DEATH field e: ((e >> 8) & 0xFF) - 1 = the dead entity's owner pid.
static func death_owner(e: int) -> int:
	return ((e >> 8) & 0xFF) - 1


## EV_DEATH field e: (e & 0xFF) - 1 = the killer's pid.
static func death_killer_pid(e: int) -> int:
	return (e & 0xFF) - 1


## EV_DEATH field c: (c >> 8) & 0xFF (1 wreck, 2 crash, 4 decoy, 8 summoned, 16 structure, 32 occupants, 64 unit, 128 aircraft).
static func death_flags(c: int) -> int:
	return (c >> 8) & 0xFF


## Compares every code with the sim constants; empty = OK. Abilities-block constants that the sim does not declare
## yet are skipped (the block is still being built).
static func verify_against_sim() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if SimEvent.STRIDE != STRIDE:
		problems.append("stride %d != %d" % [SimEvent.STRIDE, STRIDE])
	for row: Array in _SIM_MAP:
		var name: StringName = row[0]
		var cls: String = row[1]
		var cname: String = row[2]
		var map: Dictionary = _constants_of(cls)
		if not map.has(cname):
			if cls != "SimAbilityConsts":
				problems.append("%s.%s missing" % [cls, cname])
			continue
		if int(map[cname]) != by_name(name):
			problems.append("%s: ui %d != %s.%s %d" % [name, by_name(name), cls, cname, int(map[cname])])
	return problems


static func _constants_of(cls: String) -> Dictionary:
	match cls:
		"SimEvent":
			return (SimEvent as GDScript).get_script_constant_map()
		"SimCombatConsts":
			return (SimCombatConsts as GDScript).get_script_constant_map()
		"SimAbilityConsts":
			return (SimAbilityConsts as GDScript).get_script_constant_map()
		"SimEconConst":
			return (SimEconConst as GDScript).get_script_constant_map()
	return {}
