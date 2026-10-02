class_name DefBodyTable
extends RefCounted
## Size classes: radius, turn rate, mass, structure footprints (data_balance 4.2), from `global.json -> size_classes`.

var radius_u: PackedInt32Array = PackedInt32Array()  ## per SizeClass
var turn_apt: PackedInt32Array = PackedInt32Array()
var mass: PackedInt32Array = PackedInt32Array()
var is_structure: PackedByteArray = PackedByteArray()
var fp_w: PackedInt32Array = PackedInt32Array()  ## structures s1..s4 (0 for unit classes)
var fp_h: PackedInt32Array = PackedInt32Array()


static func from_global(g: Dictionary, rep: DefLoadReport) -> DefBodyTable:
	var t: DefBodyTable = DefBodyTable.new()
	var n: int = DefEnums.SizeClass.COUNT
	t.radius_u.resize(n)
	t.turn_apt.resize(n)
	t.mass.resize(n)
	t.is_structure.resize(n)
	t.fp_w.resize(n)
	t.fp_h.resize(n)
	var sc: Dictionary = g.get("size_classes", {})
	if sc.size() != n:
		rep.error("V-CNF-05", "global.json size_classes", "expected the %d frozen size classes, found %d" % [n, sc.size()])
	for i: int in n:
		var name: String = DefEnums.SIZE_NAMES[i]
		if not sc.has(name):
			rep.error("V-CNF-05", "global.json size_classes", "missing size class '%s'" % name)
			continue
		var d: Dictionary = sc[name]
		var ctx: String = "global.json size_classes.%s" % name
		t.radius_u[i] = DefConvert.cells_to_units(DefNumParse.milli(d.get("radius_cells", 0), ctx, rep))
		t.turn_apt[i] = DefConvert.deg_s_to_apt(DefNumParse.milli(d.get("turn_deg_s", 0), ctx, rep))
		t.mass[i] = DefNumParse.whole(d.get("mass", 0), ctx, rep)
		t.is_structure[i] = 1 if bool(d.get("structure", false)) else 0
		var fp: Array = d.get("footprint", [0, 0])
		t.fp_w[i] = DefNumParse.whole(fp[0], ctx, rep)
		t.fp_h[i] = DefNumParse.whole(fp[1], ctx, rep)
	return t
