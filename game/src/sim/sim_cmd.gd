class_name SimCmd
extends RefCounted
## MASTER command catalog (sim_core 3.5 / 6.1): opcode constants, wire layouts, per-op metadata and the static
## int-array builders. The AI, the UI command bus and tests build commands ONLY with these builders (they return
## the `PackedInt32Array` net carries): `[op, fields in layout order..., sorted-unique ids...]`. A domain never
## hand-packs ints. Tables are immutable statics (DR-9).

# ---- opcodes (decimal blocks: 1-39 core / movement / unit orders, 40-47 combat, 99 debug, 100-119 abilities,
# 120-149 economy / production / strategic, 240-255 net / system)
const MOVE: int = 1
const STOP: int = 2
const SCATTER: int = 3
const PATROL: int = 4
const LOAD: int = 5
const GARRISON: int = 6
const CAPTURE: int = 7
const REPAIR: int = 8
const SALVAGE: int = 9
const HARVEST: int = 10
const RETURN_CARGO: int = 11
const FOLLOW: int = 12
const ATTACK: int = 40
const ATTACK_MOVE: int = 41
const GUARD: int = 42
const HOLD: int = 43
const FORCE_FIRE: int = 44
const SET_STANCE: int = 45
const SCUTTLE: int = 46
const RETURN_TO_BASE: int = 47
const DEBUG: int = 99
const DEPLOY: int = 100
const UNDEPLOY: int = 101
const SET_MODE: int = 102
const USE_ABILITY: int = 103
const SET_AUTOCAST: int = 104
const UNLOAD: int = 105
const BUILD_START: int = 120
const BUILD_CANCEL: int = 121
const BUILD_HOLD: int = 122
const BUILD_PLACE: int = 123
const TRAIN: int = 124
const TRAIN_CANCEL: int = 125
const QUEUE_HOLD: int = 126
const SET_RALLY: int = 127
const SET_PRIMARY: int = 128
const RESEARCH: int = 129
const RESEARCH_CANCEL: int = 130
const RESEARCH_HOLD: int = 131
const SELL: int = 132
const SET_STRUCT_REPAIR: int = 133
const UNDEPLOY_HQ: int = 134
const USE_POWER: int = 140
const LAUNCH_SUPERWEAPON: int = 141
const RESIGN: int = 250

# ---- FT_*: the storage slot a wire field decodes into (the 8 field slots of SimCommand)
const FT_TARGET: int = 0
const FT_X: int = 1
const FT_Y: int = 2
const FT_DEF: int = 3
const FT_COUNT: int = 4
const FT_MODE: int = 5
const FT_FLAGS: int = 6
const FT_ANGLE: int = 7

# ---- M_*: per-op metadata bits (checked by the kernel before any executor runs)
const M_IDS: int = 1  ## the wire carries an id list
const M_UNITS: int = 2  ## actors must be UNITs
const M_STRUCTS: int = 4  ## actors must be STRUCTUREs
const M_ANY: int = 8  ## actors may be either
const M_POS: int = 16  ## x,y are sub-cell coordinates inside the map
const M_QUEUE: int = 32  ## mode is a queue mode 0..2
const M_ANGLE: int = 64  ## angle in 0..4095
const M_CELL: int = 128  ## x,y are cell coordinates inside the map

const _U: int = M_IDS | M_UNITS
const _S: int = M_IDS | M_STRUCTS
const _A: int = M_IDS | M_ANY

## op -> [name, wire layout (FT_* in wire order), meta]
const TABLE: Dictionary = {
	1: ["MOVE", [FT_X, FT_Y, FT_MODE, FT_FLAGS], _U | M_POS | M_QUEUE],
	2: ["STOP", [], _U],
	3: ["SCATTER", [], _U],
	4: ["PATROL", [FT_X, FT_Y, FT_MODE, FT_FLAGS], _U | M_POS | M_QUEUE],
	5: ["LOAD", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	6: ["GARRISON", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	7: ["CAPTURE", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	8: ["REPAIR", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	9: ["SALVAGE", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	10: ["HARVEST", [FT_TARGET, FT_X, FT_Y, FT_MODE], _U | M_POS | M_QUEUE],
	11: ["RETURN_CARGO", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	12: ["FOLLOW", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	40: ["ATTACK", [FT_TARGET, FT_MODE, FT_FLAGS], _U | M_QUEUE],
	41: ["ATTACK_MOVE", [FT_X, FT_Y, FT_MODE, FT_FLAGS], _U | M_POS | M_QUEUE],
	42: ["GUARD", [FT_TARGET, FT_X, FT_Y, FT_MODE], _U | M_POS | M_QUEUE],
	43: ["HOLD", [], _U],
	44: ["FORCE_FIRE", [FT_TARGET, FT_X, FT_Y, FT_COUNT], _U | M_POS],
	45: ["SET_STANCE", [FT_MODE], _U],
	46: ["SCUTTLE", [], _U],
	47: ["RETURN_TO_BASE", [FT_TARGET, FT_MODE], _U | M_QUEUE],
	99: ["DEBUG", [FT_MODE, FT_TARGET, FT_DEF, FT_COUNT, FT_X, FT_Y], 0],
	100: ["DEPLOY", [FT_DEF], _A],
	101: ["UNDEPLOY", [FT_DEF], _A],
	102: ["SET_MODE", [FT_DEF, FT_MODE], _A],
	103: ["USE_ABILITY", [FT_DEF, FT_MODE, FT_TARGET, FT_X, FT_Y], _A],
	104: ["SET_AUTOCAST", [FT_DEF, FT_MODE], _A],
	105: ["UNLOAD", [FT_MODE, FT_TARGET, FT_X, FT_Y], _A | M_POS],
	120: ["BUILD_START", [FT_DEF, FT_COUNT], 0],
	121: ["BUILD_CANCEL", [FT_MODE], 0],
	122: ["BUILD_HOLD", [FT_MODE], 0],
	123: ["BUILD_PLACE", [FT_DEF, FT_X, FT_Y, FT_MODE], M_CELL],
	124: ["TRAIN", [FT_TARGET, FT_DEF, FT_COUNT], 0],
	125: ["TRAIN_CANCEL", [FT_TARGET, FT_MODE], 0],
	126: ["QUEUE_HOLD", [FT_MODE], _S],
	127: ["SET_RALLY", [FT_X, FT_Y, FT_TARGET, FT_FLAGS], _S],
	128: ["SET_PRIMARY", [FT_TARGET], 0],
	129: ["RESEARCH", [FT_DEF], 0],
	130: ["RESEARCH_CANCEL", [FT_MODE], 0],
	131: ["RESEARCH_HOLD", [FT_MODE], 0],
	132: ["SELL", [], _S],
	133: ["SET_STRUCT_REPAIR", [FT_MODE], _S],
	134: ["UNDEPLOY_HQ", [], _S],
	140: ["USE_POWER", [FT_DEF, FT_X, FT_Y, FT_ANGLE, FT_TARGET], M_POS | M_ANGLE],
	141: ["LAUNCH_SUPERWEAPON", [FT_X, FT_Y, FT_ANGLE], M_POS | M_ANGLE],
	250: ["RESIGN", [FT_MODE], 0],
}

## Every op of the catalog, ascending.
const _OPS: PackedInt32Array = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 40, 41, 42, 43, 44, 45, 46, 47, 99, 100, 101, 102, 103, 104, 105,
	120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 140, 141, 250,
]

static var _layouts: Array[PackedInt32Array] = []  ## by op (0..255), built once from TABLE


static func is_known(op: int) -> bool:
	return TABLE.has(op)


static func name_of(op: int) -> String:
	if not TABLE.has(op):
		return "OP%d" % op
	var row: Array = TABLE[op]
	return row[0]


## Wire fields of `op` as FT_* codes (empty for unknown ops).
static func layout_of(op: int) -> PackedInt32Array:
	if _layouts.is_empty():
		_build_layouts()
	if op < 0 or op > 255:
		return PackedInt32Array()
	return _layouts[op]


static func meta_of(op: int) -> int:
	if not TABLE.has(op):
		return 0
	var row: Array = TABLE[op]
	return row[2]


## Every op of the catalog, ascending (schema-aware fuzzing, docs).
static func all_ops() -> PackedInt32Array:
	return _OPS.duplicate()


## [op, values..., sorted-unique ids...].
static func build(op: int, values: Array, ids: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.append(op)
	for v: Variant in values:
		out.append(int(v))
	if not ids.is_empty():
		var s: PackedInt32Array = ids.duplicate()
		s.sort()
		var last: int = 0
		var first: bool = true
		for id: int in s:
			if first or id != last:
				out.append(id)
			last = id
			first = false
	return out


static func _build_layouts() -> void:
	_layouts.resize(256)
	for i: int in 256:
		_layouts[i] = PackedInt32Array()
	for op: int in TABLE:
		var row: Array = TABLE[op]
		var lay: Array = row[1]
		var p: PackedInt32Array = PackedInt32Array()
		for ft: int in lay:
			p.append(ft)
		_layouts[op] = p


# ---- builders: one per catalog row, `ids` first (when the op carries them), wire order after ----
static func move(ids: PackedInt32Array, x: int, y: int, mode: int = 0, flags: int = 0) -> PackedInt32Array:
	return build(MOVE, [x, y, mode, flags], ids)


static func stop(ids: PackedInt32Array) -> PackedInt32Array:
	return build(STOP, [], ids)


static func scatter(ids: PackedInt32Array) -> PackedInt32Array:
	return build(SCATTER, [], ids)


static func patrol(ids: PackedInt32Array, x: int, y: int, mode: int = 0, flags: int = 0) -> PackedInt32Array:
	return build(PATROL, [x, y, mode, flags], ids)


static func load(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(LOAD, [target, mode], ids)


static func garrison(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(GARRISON, [target, mode], ids)


static func capture(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(CAPTURE, [target, mode], ids)


static func repair(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(REPAIR, [target, mode], ids)


static func salvage(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(SALVAGE, [target, mode], ids)


static func harvest(ids: PackedInt32Array, target: int, x: int, y: int, mode: int = 0) -> PackedInt32Array:
	return build(HARVEST, [target, x, y, mode], ids)


static func return_cargo(ids: PackedInt32Array, target: int = 0, mode: int = 0) -> PackedInt32Array:
	return build(RETURN_CARGO, [target, mode], ids)


static func follow(ids: PackedInt32Array, target: int, mode: int = 0) -> PackedInt32Array:
	return build(FOLLOW, [target, mode], ids)


static func attack(ids: PackedInt32Array, target: int, mode: int = 0, flags: int = 0) -> PackedInt32Array:
	return build(ATTACK, [target, mode, flags], ids)


static func attack_move(ids: PackedInt32Array, x: int, y: int, mode: int = 0, flags: int = 0) -> PackedInt32Array:
	return build(ATTACK_MOVE, [x, y, mode, flags], ids)


static func guard(ids: PackedInt32Array, target: int, x: int = 0, y: int = 0, mode: int = 0) -> PackedInt32Array:
	return build(GUARD, [target, x, y, mode], ids)


static func hold(ids: PackedInt32Array) -> PackedInt32Array:
	return build(HOLD, [], ids)


static func force_fire(ids: PackedInt32Array, target: int, x: int = 0, y: int = 0, count: int = 0) -> PackedInt32Array:
	return build(FORCE_FIRE, [target, x, y, count], ids)


static func set_stance(ids: PackedInt32Array, mode: int) -> PackedInt32Array:
	return build(SET_STANCE, [mode], ids)


static func scuttle(ids: PackedInt32Array) -> PackedInt32Array:
	return build(SCUTTLE, [], ids)


static func return_to_base(ids: PackedInt32Array, target: int = 0, mode: int = 0) -> PackedInt32Array:
	return build(RETURN_TO_BASE, [target, mode], ids)


static func debug(mode: int, target: int = 0, def: int = 0, count: int = 0, x: int = 0, y: int = 0) -> PackedInt32Array:
	return build(DEBUG, [mode, target, def, count, x, y])


static func deploy(ids: PackedInt32Array, def: int = -1) -> PackedInt32Array:
	return build(DEPLOY, [def], ids)


static func undeploy(ids: PackedInt32Array, def: int = -1) -> PackedInt32Array:
	return build(UNDEPLOY, [def], ids)


static func set_mode(ids: PackedInt32Array, def: int, mode: int) -> PackedInt32Array:
	return build(SET_MODE, [def, mode], ids)


static func use_ability(ids: PackedInt32Array, def: int, mode: int = 0, target: int = 0, x: int = 0, y: int = 0) -> PackedInt32Array:
	return build(USE_ABILITY, [def, mode, target, x, y], ids)


static func set_autocast(ids: PackedInt32Array, def: int, mode: int) -> PackedInt32Array:
	return build(SET_AUTOCAST, [def, mode], ids)


static func unload(ids: PackedInt32Array, mode: int = 0, target: int = 0, x: int = 0, y: int = 0) -> PackedInt32Array:
	return build(UNLOAD, [mode, target, x, y], ids)


static func build_start(def: int, count: int = 1) -> PackedInt32Array:
	return build(BUILD_START, [def, count])


static func build_cancel(mode: int = 0) -> PackedInt32Array:
	return build(BUILD_CANCEL, [mode])


static func build_hold(mode: int = 1) -> PackedInt32Array:
	return build(BUILD_HOLD, [mode])


static func build_place(def: int, cx: int, cy: int, rot: int = 0) -> PackedInt32Array:
	return build(BUILD_PLACE, [def, cx, cy, rot])


static func train(producer: int, def: int, count: int = 1) -> PackedInt32Array:
	return build(TRAIN, [producer, def, count])


static func train_cancel(producer: int, index: int = 0) -> PackedInt32Array:
	return build(TRAIN_CANCEL, [producer, index])


static func queue_hold(ids: PackedInt32Array, mode: int = 1) -> PackedInt32Array:
	return build(QUEUE_HOLD, [mode], ids)


static func set_rally(ids: PackedInt32Array, x: int, y: int, target: int = 0, flags: int = 0) -> PackedInt32Array:
	return build(SET_RALLY, [x, y, target, flags], ids)


static func set_primary(producer: int) -> PackedInt32Array:
	return build(SET_PRIMARY, [producer])


static func research(def: int) -> PackedInt32Array:
	return build(RESEARCH, [def])


static func research_cancel(index: int = 0) -> PackedInt32Array:
	return build(RESEARCH_CANCEL, [index])


static func research_hold(mode: int = 1) -> PackedInt32Array:
	return build(RESEARCH_HOLD, [mode])


static func sell(ids: PackedInt32Array) -> PackedInt32Array:
	return build(SELL, [], ids)


static func set_struct_repair(ids: PackedInt32Array, mode: int = 2) -> PackedInt32Array:
	return build(SET_STRUCT_REPAIR, [mode], ids)


static func undeploy_hq(ids: PackedInt32Array) -> PackedInt32Array:
	return build(UNDEPLOY_HQ, [], ids)


static func use_power(def: int, x: int, y: int, angle: int = 0, target: int = 0) -> PackedInt32Array:
	return build(USE_POWER, [def, x, y, angle, target])


static func launch_superweapon(x: int, y: int, angle: int = 0) -> PackedInt32Array:
	return build(LAUNCH_SUPERWEAPON, [x, y, angle])


static func resign(mode: int = 0) -> PackedInt32Array:
	return build(RESIGN, [mode])
