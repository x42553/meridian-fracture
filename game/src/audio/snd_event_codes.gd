class_name SndEventCodes
extends RefCounted
## Mirror of the sim event codes audio consumes (audio spec 6.1). The sim owns the numbers (SimEvent, SimCombatConsts,
## SimEconConst, SimAbilityConsts, SimMoveConfig, SimAirMove, SimZoneConsts); this is the ONE file to fix when a code moves,
## and `test_snd_event_codes` asserts equality by name. `IGNORED` lists known codes audio deliberately does not voice.

const CASH: int = 4
const CMD_REJECTED: int = 5
const ORDER_FAILED: int = 6
const PLAYER_ELIMINATED: int = 7
const MATCH_END: int = 8
const EV_MOVE_FAILED: int = 100
const EV_AIR_TAKEOFF: int = 102
const EV_AIR_LANDED: int = 103
const EV_FIRE: int = 200
const EV_PROJ_SPAWN: int = 201
const EV_PROJ_END: int = 202
const EV_IMPACT: int = 203
const EV_HIT: int = 204
const EV_BEAM_START: int = 205
const EV_BEAM_END: int = 206
const EV_DEATH: int = 208
const EV_INTERCEPT: int = 211
const EV_EMP: int = 213
const EV_ATTACK_ALERT: int = 214
const EV_EJECT: int = 218
const EV_CRASH: int = 219
const EV_WEAPON_LOCK: int = 220
const EV_CLOAK_CHANGED: int = 230
const EV_LOADED: int = 240
const EV_UNLOADED: int = 241
const EV_SCAN_WARNING: int = 250
const EVT_STRUCTURE_READY: int = 302
const EVT_STRUCTURE_PLACED: int = 303
const EVT_UNIT_PRODUCED: int = 305
const EVT_QUEUE_STATE: int = 306
const EVT_RESEARCH_COMPLETE: int = 307
const EVT_CREDITS_GAINED: int = 308
const EVT_INSUFFICIENT_FUNDS: int = 309
const EVT_UNIT_CAP_REACHED: int = 310
const EVT_POWER_SHORTAGE: int = 311
const EVT_POWER_RESTORED: int = 312
const EVT_STRUCTURE_SOLD: int = 314
const EVT_STRUCTURE_SELLING: int = 315
const EVT_REPAIR_STATE: int = 316
const EVT_HQ_DEPLOYED: int = 317
const EVT_ORDER_FAILED: int = 319
const EVT_COLLECTOR_ATTACKED: int = 320
const EVT_STRUCTURE_CAPTURED: int = 326
const EVT_SALVAGE_PAID: int = 328
const EVT_POWER_READY: int = 401
const EVT_POWER_ACTIVATED: int = 402
const EVT_WARNING: int = 404
const EVT_SW_READY: int = 405
const EVT_SW_CANCELLED: int = 406
const EVT_SW_EXEC_START: int = 407
const EVT_SW_IMPACT: int = 408

## Mirrored SimCommand.Err values (checked by the mirror test).
const ERR_NO_CREDITS: int = 11
const ERR_BAD_SITE: int = 13
const ERR_UNIT_CAP: int = 16

## [name, value, sim class] of every consumed code.
const CONSUMED: Array = [
	["CASH", 4, "SimEvent"],
	["CMD_REJECTED", 5, "SimEvent"],
	["ORDER_FAILED", 6, "SimEvent"],
	["PLAYER_ELIMINATED", 7, "SimEvent"],
	["MATCH_END", 8, "SimEvent"],
	["EV_MOVE_FAILED", 100, "SimMoveConfig"],
	["EV_AIR_TAKEOFF", 102, "SimAirMove"],
	["EV_AIR_LANDED", 103, "SimAirMove"],
	["EV_FIRE", 200, "SimCombatConsts"],
	["EV_PROJ_SPAWN", 201, "SimCombatConsts"],
	["EV_PROJ_END", 202, "SimCombatConsts"],
	["EV_IMPACT", 203, "SimCombatConsts"],
	["EV_HIT", 204, "SimCombatConsts"],
	["EV_BEAM_START", 205, "SimCombatConsts"],
	["EV_BEAM_END", 206, "SimCombatConsts"],
	["EV_DEATH", 208, "SimCombatConsts"],
	["EV_INTERCEPT", 211, "SimCombatConsts"],
	["EV_EMP", 213, "SimCombatConsts"],
	["EV_ATTACK_ALERT", 214, "SimCombatConsts"],
	["EV_EJECT", 218, "SimCombatConsts"],
	["EV_CRASH", 219, "SimCombatConsts"],
	["EV_WEAPON_LOCK", 220, "SimCombatConsts"],
	["EV_CLOAK_CHANGED", 230, "SimAbilityConsts"],
	["EV_LOADED", 240, "SimAbilityConsts"],
	["EV_UNLOADED", 241, "SimAbilityConsts"],
	["EV_SCAN_WARNING", 250, "SimAbilityConsts"],
	["EVT_STRUCTURE_READY", 302, "SimEconConst"],
	["EVT_STRUCTURE_PLACED", 303, "SimEconConst"],
	["EVT_UNIT_PRODUCED", 305, "SimEconConst"],
	["EVT_QUEUE_STATE", 306, "SimEconConst"],
	["EVT_RESEARCH_COMPLETE", 307, "SimEconConst"],
	["EVT_CREDITS_GAINED", 308, "SimEconConst"],
	["EVT_INSUFFICIENT_FUNDS", 309, "SimEconConst"],
	["EVT_UNIT_CAP_REACHED", 310, "SimEconConst"],
	["EVT_POWER_SHORTAGE", 311, "SimEconConst"],
	["EVT_POWER_RESTORED", 312, "SimEconConst"],
	["EVT_STRUCTURE_SOLD", 314, "SimEconConst"],
	["EVT_STRUCTURE_SELLING", 315, "SimEconConst"],
	["EVT_REPAIR_STATE", 316, "SimEconConst"],
	["EVT_HQ_DEPLOYED", 317, "SimEconConst"],
	["EVT_ORDER_FAILED", 319, "SimEconConst"],
	["EVT_COLLECTOR_ATTACKED", 320, "SimEconConst"],
	["EVT_STRUCTURE_CAPTURED", 326, "SimEconConst"],
	["EVT_SALVAGE_PAID", 328, "SimEconConst"],
	["EVT_POWER_READY", 401, "SimEconConst"],
	["EVT_POWER_ACTIVATED", 402, "SimEconConst"],
	["EVT_WARNING", 404, "SimEconConst"],
	["EVT_SW_READY", 405, "SimEconConst"],
	["EVT_SW_CANCELLED", 406, "SimEconConst"],
	["EVT_SW_EXEC_START", 407, "SimEconConst"],
	["EVT_SW_IMPACT", 408, "SimEconConst"],
]
## Known sim events audio ignores on purpose (view / UI / AI concerns, or no sound in v1).
const IGNORED: Array = [
	["EV_SUMMONED", 248, "SimZoneConsts"],
	["EV_SUMMON_EXPIRED", 249, "SimZoneConsts"],
	["EV_SWARM_LAUNCHED", 256, "SimZoneConsts"],
	["EV_ENGINE_ASSEMBLED", 257, "SimZoneConsts"],
	["REMOVED", 2, "SimEvent"],
	["OWNER_CHANGED", 3, "SimEvent"],
	["SPAWNED", 1, "SimEvent"],
	["EV_SALVAGE_DONE", 251, "SimAbilityConsts"],
	["NAV_CHANGED", 9, "SimEvent"],
	["EV_MEDIUM_CHANGED", 101, "SimMoveConfig"],
	["EV_STUCK", 108, "SimMoveConfig"],
	["EV_LAYER_CHANGED", 109, "SimMoveConfig"],
	["EV_SWEEP", 207, "SimCombatConsts"],
	["EV_WRECK_ADD", 209, "SimCombatConsts"],
	["EV_WRECK_REMOVE", 210, "SimCombatConsts"],
	["EV_SUPPRESS", 212, "SimCombatConsts"],
	["EV_AIR_STATE", 215, "SimCombatConsts"],
	["EV_REARM", 216, "SimCombatConsts"],
	["EV_DRONE", 217, "SimCombatConsts"],
	["EV_VIS_CHANGED", 231, "SimAbilityConsts"],
	["EV_GHOST_ADDED", 232, "SimAbilityConsts"],
	["EV_GHOST_REMOVED", 233, "SimAbilityConsts"],
	["EV_MODE_STARTED", 234, "SimAbilityConsts"],
	["EV_MODE_CHANGED", 235, "SimAbilityConsts"],
	["EV_ABILITY_USED", 236, "SimAbilityConsts"],
	["EV_ABILITY_READY", 237, "SimAbilityConsts"],
	["EV_FX_APPLIED", 238, "SimAbilityConsts"],
	["EV_FX_REMOVED", 239, "SimAbilityConsts"],
	["EV_UNLOAD_BLOCKED", 242, "SimAbilityConsts"],
	["EV_GARRISON_CHANGED", 243, "SimAbilityConsts"],
	["EV_EJECTED", 244, "SimAbilityConsts"],
	["EV_DROWNED", 245, "SimAbilityConsts"],
	["EV_ZONE_SPAWNED", 246, "SimZoneConsts"],
	["EV_ZONE_ENDED", 247, "SimZoneConsts"],
	["EV_CAPTURE_DONE", 252, "SimAbilityConsts"],
	["EV_REPAIR_PULSE", 254, "SimAbilityConsts"],
	["EV_DECOY_IDENTIFIED", 255, "SimAbilityConsts"],
	["EV_MARKED", 258, "SimAbilityConsts"],
	["EV_BUFF_APPLIED", 259, "SimAbilityConsts"],
	["EVT_CMD_REJECTED", 300, "SimEconConst"],
	["EVT_PLACE_REJECTED", 301, "SimEconConst"],
	["EVT_STRUCTURE_ACTIVE", 304, "SimEconConst"],
	["EVT_SAP_RESERVE_EMPTY", 313, "SimEconConst"],
	["EVT_HQ_UNDEPLOYED", 318, "SimEconConst"],
	["EVT_NO_REFINERY", 321, "SimEconConst"],
	["EVT_DEPOSIT_DEPLETED", 322, "SimEconConst"],
	["EVT_DEPOSIT_REGROWN", 323, "SimEconConst"],
	["EVT_CAPTURE_PROGRESS", 324, "SimEconConst"],
	["EVT_CAPTURE_CONTESTED", 325, "SimEconConst"],
	["EVT_SALVAGE_STARTED", 327, "SimEconConst"],
	["EVT_WRECKS_HIGHLIGHTED", 329, "SimEconConst"],
	["EVT_POWER_UNLOCKED", 400, "SimEconConst"],
	["EVT_POWER_EFFECT_END", 403, "SimEconConst"],
	["EVT_SW_DONE", 409, "SimEconConst"],
	["EVT_SUMMON_EXPIRED", 410, "SimEconConst"],
]

## Payload constants of the consumed events: [name, value, sim class, sim constant].
const PAYLOAD: Array = [
	["SLOT_SW", 3, "SimEconConst", "SLOT_SW"], ["WK_SUPER", 0, "SimEconConst", "WK_SUPER"], ["WK_POWER", 1, "SimEconConst", "WK_POWER"],
	["WK_SCAN", 2, "SimEconConst", "WK_SCAN"], ["QS_HOLD", 2, "SimEconConst", "QS_HOLD"],
	["DK_NONE", 0, "SimCombatConsts", "DK_NONE"], ["DK_VEHICLE", 1, "SimCombatConsts", "DK_VEHICLE"],
	["DK_INFANTRY", 2, "SimCombatConsts", "DK_INFANTRY"], ["DK_CRASH", 3, "SimCombatConsts", "DK_CRASH"],
	["DK_AIR_EXPLODE", 4, "SimCombatConsts", "DK_AIR_EXPLODE"], ["DK_SINK", 5, "SimCombatConsts", "DK_SINK"],
	["DK_STRUCTURE", 6, "SimCombatConsts", "DK_STRUCTURE"], ["DK_DRONE", 7, "SimCombatConsts", "DK_DRONE"],
	["DK_SILENT", 8, "SimCombatConsts", "DK_SILENT"], ["DC_SPLASH", 4, "SimCombatConsts", "DC_SPLASH"],
	["ERR_NO_CREDITS", 11, "SimCommand.Err", "NO_CREDITS"], ["ERR_BAD_SITE", 13, "SimCommand.Err", "BAD_SITE"],
	["ERR_UNIT_CAP", 16, "SimCommand.Err", "UNIT_CAP"], ["ELIM_DISCONNECT", 3, "SimPlayer.Elim", "DISCONNECT"],
]
const SLOT_SW: int = 3
const WK_SUPER: int = 0
const WK_POWER: int = 1
const WK_SCAN: int = 2
const QS_HOLD: int = 2
const DK_NONE: int = 0
const DK_VEHICLE: int = 1
const DK_INFANTRY: int = 2
const DK_CRASH: int = 3
const DK_AIR_EXPLODE: int = 4
const DK_SINK: int = 5
const DK_STRUCTURE: int = 6
const DK_DRONE: int = 7
const DK_SILENT: int = 8
const DC_SPLASH: int = 4
const ELIM_DISCONNECT: int = 3

static var _consumed: PackedInt32Array = PackedInt32Array()
static var _ignored: Dictionary = {}


static func consumed_codes() -> PackedInt32Array:
	if _consumed.is_empty():
		for row: Array in CONSUMED:
			_consumed.append(int(row[1]))
	return _consumed


static func is_ignored(code: int) -> bool:
	if _ignored.is_empty():
		for row: Array in IGNORED:
			_ignored[int(row[1])] = true
	return _ignored.has(code)


static func name_of(code: int) -> String:
	for row: Array in CONSUMED:
		if int(row[1]) == code:
			return str(row[0])
	for row: Array in IGNORED:
		if int(row[1]) == code:
			return str(row[0])
	return ""
