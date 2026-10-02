class_name ViewTestEvents
extends RefCounted
## Builders for synthetic event batches (render spec 6.2.2 / 10.1), written against the REAL kernel layout of
## sim_core 4.9 / 6.2: a record is 10 ints `[type, tick, x, y, a, b, c, d, e, f]` (NOT the render spec's a..h
## draft, sim_core.md wins) and the codes are the domain blocks of the master registry (core 1-9, movement 100-129,
## combat 200-229, abilities 230-259, economy 300-499). The names of the render reaction table (SPAWNED, DIED,
## DAMAGE, ...) are mapped to those real codes in `REACTIONS`; a render event that has no kernel equivalent has an
## empty code list.

const STRIDE: int = 10  # == SimEvent.STRIDE
const NAMES: Dictionary = {
	1: "SPAWNED", 2: "REMOVED", 3: "OWNER_CHANGED", 8: "MATCH_END", 9: "NAV_CHANGED",
	200: "EV_FIRE", 201: "EV_PROJ_SPAWN", 202: "EV_PROJ_END", 203: "EV_IMPACT", 204: "EV_HIT", 205: "EV_BEAM_START",
	206: "EV_BEAM_END", 207: "EV_SWEEP", 208: "EV_DEATH", 209: "EV_WRECK_ADD", 210: "EV_WRECK_REMOVE",
	211: "EV_INTERCEPT", 212: "EV_SUPPRESS", 213: "EV_EMP", 215: "EV_AIR_STATE", 216: "EV_REARM", 217: "EV_DRONE",
	218: "EV_EJECT", 219: "EV_CRASH", 220: "EV_WEAPON_LOCK",
	230: "EV_CLOAK_CHANGED", 232: "EV_GHOST_ADDED", 233: "EV_GHOST_REMOVED", 234: "EV_MODE_STARTED", 235: "EV_MODE_CHANGED",
	236: "EV_ABILITY_USED", 240: "EV_LOADED", 241: "EV_UNLOADED", 246: "EV_ZONE_SPAWNED", 247: "EV_ZONE_ENDED",
	248: "EV_SUMMONED", 250: "EV_SCAN_WARNING", 251: "EV_SALVAGE_DONE", 254: "EV_REPAIR_PULSE",
	303: "EVT_STRUCTURE_PLACED", 304: "EVT_STRUCTURE_ACTIVE", 305: "EVT_UNIT_PRODUCED", 311: "EVT_POWER_SHORTAGE",
	312: "EVT_POWER_RESTORED", 315: "EVT_STRUCTURE_SELLING", 316: "EVT_REPAIR_STATE", 328: "EVT_SALVAGE_PAID",
	308: "EVT_CREDITS_GAINED", 402: "EVT_POWER_ACTIVATED", 404: "EVT_WARNING", 405: "EVT_SW_READY",
	406: "EVT_SW_CANCELLED", 407: "EVT_SW_EXEC_START", 408: "EVT_SW_IMPACT", 410: "EVT_SUMMON_EXPIRED",
}
## Render reaction table (6.2.2) -> real kernel codes. The order is the table order.
const REACTIONS: Dictionary = {
	"SPAWNED": [1], "REMOVED": [2], "DIED": [208], "OWNER_CHANGED": [3],
	"STATE": [234, 235, 230, 213, 212, 215, 315, 316, 220], "LOADED": [240], "UNLOADED": [241],
	"DAMAGE": [204], "WEAPON_FIRED": [200], "PROJECTILE_LAUNCHED": [201], "PROJECTILE_IMPACT": [202, 203],
	"EXPLOSION": [203], "BEAM": [205, 206], "INTERCEPT": [211], "HEAL": [254], "SALVAGE": [251, 328],
	"HARVEST_DELIVERED": [308], "POWER_LOW": [311], "POWER_RESTORED": [312], "PRODUCTION_COMPLETE": [305],
	"POWER_USED": [402], "SW_READY": [405], "SW_WARNING": [404], "SW_LAUNCHED": [407], "SW_CANCELLED": [406],
	"SW_IMPACT": [408], "ABILITY": [236], "REVEAL_AREA": [], "MATCH_END": [8], "PAUSED": [], "UNPAUSED": [],
}
## Sample payloads (x, y, a..f) per code, plausible values of the kernel / domain specs.
const SAMPLES: Dictionary = {
	1: [51200, 30720, 7, 0, 3, 0, 1024, 1],  # id, kind, def, owner, facing, reason PRODUCED
	2: [51200, 30720, 7, 0, 3, 0, 0, 0],  # id, kind, def, owner, reason KILLED
	3: [51200, 30720, 7, 0, 1, 2, 0, 0],
	8: [0, 0, 0, 1, 12345, 0, 0, 0],
	9: [0, 0, 0x0A0A0C0C, 1, 9, 1, 0, 0],
	200: [51200, 30720, 7, 3, 0x0010, 9, 52224, 31744],  # shooter, weapon, mount|barrel<<4|result<<12, target, aim
	201: [51200, 30720, 40, 9, 0, 0x0000_0201, 9, 52224],
	202: [52000, 31000, 40, 0, -1, 0, 0, 0],
	203: [52224, 31744, 4, 40, 1, 1500, 900, 0],
	204: [52224, 31744, 9, 120, 7, 2, 60, 200],  # victim, damage, attacker, dtype|flags, hp after, hp max
	205: [51200, 30720, 7, 13, 0, 9, 40, 0],
	206: [51200, 30720, 7, 3, 0, 0, 0, 0],
	208: [52224, 31744, 9, 3, 0x001, 7, 0x0101, 4096],  # id, def, death_kind|cause|flags, killer, pids, facing|layer|visual_ticks
	211: [52224, 31744, 40, 11, 0, 3, 0, 1],
	212: [52224, 31744, 9, 1, 0, 0, 0, 0],
	213: [52224, 31744, 9, 100, 1, 0, 0, 0],
	215: [0, 0, 12, 2, 0, 5, 0, 0],
	219: [52224, 31744, 12, 0, 30, 0, 0, 0],
	220: [0, 0, 9, 1, 0, 0, 0, 0],
	230: [51200, 30720, 9, 1, 1, 0, 0, 0],
	234: [51200, 30720, 9, 0, 1, 0, 0, 0],
	235: [51200, 30720, 9, 0, 1, 0, 0, 0],
	236: [51200, 30720, 9, 4, 0, 0, 0, 0],
	240: [0, 0, 5, 6, 0, 0, 0, 0],
	241: [51200, 30720, 5, 6, 0, 0, 0, 0],
	246: [51200, 30720, 0, 3, 2, 0, 0, 0],
	248: [51200, 30720, 30, 7, 1, 0, 0, 0],
	251: [51200, 30720, 8, 15, 300, 0, 0, 0],
	254: [51200, 30720, 9, 4, 25, 0, 0, 0],
	305: [0, 0, 0, 12, 4, 6, 0, 0],
	308: [51200, 30720, 0, 300, 51200, 30720, 0, 0],
	311: [0, 0, 0, 40, 100, 0, 0, 0],
	312: [0, 0, 0, 0, 0, 0, 0, 0],
	315: [51200, 30720, 0, 12, 2000, 0, 0, 0],
	316: [51200, 30720, 0, 12, 1, 0, 0, 0],
	328: [51200, 30720, 0, 150, 51200, 30720, 0, 0],
	402: [0, 0, 0, 2, 3, 51200, 30720, 0],
	404: [51200, 30720, 1, 0, 0, 4, 51200, 30720],
	405: [0, 0, 0, 0, 0, 0, 0, 0],
	406: [0, 0, 0, 0, 1, 0, 1, 0],
	407: [0, 0, 0, 0, 1, 0, 0, 0],
	408: [51200, 30720, 0, 51200, 30720, 6144, 3, 0],
	410: [51200, 30720, 30, 51200, 30720, 0, 0, 0],
}


## One record `[type, tick, x, y, a, b, c, d, e, f]`.
static func make(type: int, tick: int, x: int = 0, y: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> PackedInt32Array:
	return PackedInt32Array([type, tick, x, y, a, b, c, d, e, f])


## The sample record of a real event code at `tick` (payload from SAMPLES; zeros for codes without a sample).
static func sample(code: int, tick: int) -> PackedInt32Array:
	var s: Array = SAMPLES.get(code, [0, 0, 0, 0, 0, 0, 0, 0])
	return make(code, tick, s[0] as int, s[1] as int, s[2] as int, s[3] as int, s[4] as int, s[5] as int, s[6] as int, s[7] as int)


## Sample records for every real code behind a render reaction name ([] for names without kernel equivalent).
static func for_reaction(reaction: String, tick: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for code: int in codes_of(reaction):
		out.append_array(sample(code, tick))
	return out


static func codes_of(reaction: String) -> Array:
	return REACTIONS.get(reaction, []) as Array


## Concatenates records into one batch.
static func batch(records: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: Variant in records:
		out.append_array(r as PackedInt32Array)
	return out


## Number of records in a batch.
static func count(b: PackedInt32Array) -> int:
	return b.size() / STRIDE


## Appends a record into a real SimEventBuffer (so router tests can also drive `world.events.take()`).
static func emit_into(buf: SimEventBuffer, rec: PackedInt32Array) -> void:
	var t: int = buf.tick
	buf.tick = rec[1]
	buf.emit(rec[0], rec[2], rec[3], rec[4], rec[5], rec[6], rec[7], rec[8], rec[9])
	buf.tick = t


## The kernel's own event constants that exist in code, by name (used to verify the tables above against the sim).
static func real_constant_codes() -> Dictionary:
	return {
		"SPAWNED": SimEvent.SPAWNED, "REMOVED": SimEvent.REMOVED, "OWNER_CHANGED": SimEvent.OWNER_CHANGED,
		"MATCH_END": SimEvent.MATCH_END, "NAV_CHANGED": SimEvent.NAV_CHANGED,
		"EV_FIRE": SimCombatConsts.EV_FIRE, "EV_PROJ_SPAWN": SimCombatConsts.EV_PROJ_SPAWN,
		"EV_PROJ_END": SimCombatConsts.EV_PROJ_END, "EV_IMPACT": SimCombatConsts.EV_IMPACT, "EV_HIT": SimCombatConsts.EV_HIT,
		"EV_BEAM_START": SimCombatConsts.EV_BEAM_START, "EV_BEAM_END": SimCombatConsts.EV_BEAM_END,
		"EV_DEATH": SimCombatConsts.EV_DEATH, "EV_INTERCEPT": SimCombatConsts.EV_INTERCEPT,
		"EV_SUPPRESS": SimCombatConsts.EV_SUPPRESS, "EV_EMP": SimCombatConsts.EV_EMP,
		"EV_AIR_STATE": SimCombatConsts.EV_AIR_STATE, "EV_CRASH": SimCombatConsts.EV_CRASH,
		"EV_WEAPON_LOCK": SimCombatConsts.EV_WEAPON_LOCK,
		"EVT_STRUCTURE_PLACED": SimEconConst.EVT_STRUCTURE_PLACED, "EVT_UNIT_PRODUCED": SimEconConst.EVT_UNIT_PRODUCED,
		"EVT_POWER_SHORTAGE": SimEconConst.EVT_POWER_SHORTAGE, "EVT_POWER_RESTORED": SimEconConst.EVT_POWER_RESTORED,
		"EVT_STRUCTURE_SELLING": SimEconConst.EVT_STRUCTURE_SELLING, "EVT_REPAIR_STATE": SimEconConst.EVT_REPAIR_STATE,
		"EVT_CREDITS_GAINED": SimEconConst.EVT_CREDITS_GAINED, "EVT_SALVAGE_PAID": SimEconConst.EVT_SALVAGE_PAID,
		"EVT_POWER_ACTIVATED": SimEconConst.EVT_POWER_ACTIVATED, "EVT_WARNING": SimEconConst.EVT_WARNING,
		"EVT_SW_READY": SimEconConst.EVT_SW_READY, "EVT_SW_CANCELLED": SimEconConst.EVT_SW_CANCELLED,
		"EVT_SW_EXEC_START": SimEconConst.EVT_SW_EXEC_START, "EVT_SW_IMPACT": SimEconConst.EVT_SW_IMPACT,
		"EVT_SUMMON_EXPIRED": SimEconConst.EVT_SUMMON_EXPIRED,
	}
