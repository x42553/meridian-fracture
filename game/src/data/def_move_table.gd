class_name DefMoveTable
extends RefCounted
## Movement classes: default layers and terrain speed multipliers (bp) per class x terrain kind (data_balance 4.2).

const TERRAIN_COUNT: int = 8

var speed_bp: PackedInt32Array = PackedInt32Array()  ## [move_class * 8 + terrain_kind]; 0 = impassable, 10000 = nominal
var layer: PackedInt32Array = PackedInt32Array()  ## per MoveClass: the Layer the class lives in
var layer_mask: PackedInt32Array = PackedInt32Array()  ## per MoveClass: default LayerMask


func speed_bp_at(move_class: int, terrain_kind: int) -> int:
	return speed_bp[move_class * TERRAIN_COUNT + terrain_kind]


func passable(move_class: int, terrain_kind: int) -> bool:
	return speed_bp_at(move_class, terrain_kind) > 0


## Effective speed on one cell with ONE rounding: table value, per-unit DEEP override (Tide Tank) and the water
## multiplier (Canada) combined: half_up(nominal_upt * bp * wm / 10^8).
static func effective_speed(table: DefMoveTable, nominal_upt: int, move_class: int, terrain_kind: int, deep_speed_bp: int, water_mult_bp: int) -> int:
	var bp: int = table.speed_bp_at(move_class, terrain_kind)
	if terrain_kind == DefEnums.TerrainKind.DEEP and deep_speed_bp > 0:
		bp = deep_speed_bp
	var wm: int = 10000
	if terrain_kind == DefEnums.TerrainKind.SHALLOW or terrain_kind == DefEnums.TerrainKind.DEEP:
		wm = water_mult_bp
	return (2 * nominal_upt * bp * wm + 100000000) / 200000000


static func from_global(g: Dictionary, rep: DefLoadReport) -> DefMoveTable:
	var t: DefMoveTable = DefMoveTable.new()
	var nm: int = DefEnums.MoveClass.COUNT
	t.speed_bp.resize(nm * TERRAIN_COUNT)
	t.layer.resize(nm)
	t.layer_mask.resize(nm)
	var terr: Array = g.get("terrain_kinds", [])
	for i: int in TERRAIN_COUNT:
		if i >= terr.size() or str(terr[i]) != DefEnums.TERRAIN_NAMES[i]:
			rep.error("V-CNF-05", "global.json terrain_kinds", "terrain kind %d differs from the frozen TerrainKind" % i)
	var mcs: Dictionary = g.get("movement_classes", {})
	for c: int in nm:
		var name: String = DefEnums.MOVE_NAMES[c]
		var ctx: String = "global.json movement_classes.%s" % name
		if not mcs.has(name):
			rep.error("V-CNF-05", ctx, "missing movement class")
			continue
		var d: Dictionary = mcs[name]
		if int(d.get("index", -1)) != c:
			rep.error("V-CNF-05", ctx, "index %s != frozen %d" % [str(d.get("index")), c])
		var li: int = DefEnums.LAYER_NAMES.find(str(d.get("layer", "")))
		if li < 0:
			rep.error("V-CNF-05", ctx, "unknown layer '%s'" % str(d.get("layer", "")))
			li = 0
		t.layer[c] = li
		var lm: int = 1 << li
		if c == DefEnums.MoveClass.AMPHIBIOUS:
			lm = DefEnums.L_GROUND | DefEnums.L_WATER
		elif c == DefEnums.MoveClass.SUBMERGED:
			lm = DefEnums.L_UNDER | DefEnums.L_WATER
		t.layer_mask[c] = lm
		var sp: Dictionary = d.get("terrain_speed_pct", {})
		for k: int in TERRAIN_COUNT:
			var pm: int = DefNumParse.milli_pct(sp.get(DefEnums.TERRAIN_NAMES[k], 0), ctx, rep)
			t.speed_bp[c * TERRAIN_COUNT + k] = DefConvert.pct_to_bp(pm)
	return t
