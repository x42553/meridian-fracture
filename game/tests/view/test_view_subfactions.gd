extends RefCounted
## VQ2A: subfaction review. For all 24 subfactions (8 factions x 3) and both of their unique units (data: roster.delta.replacements):
## the unique unit is NOT a copy of the unit it replaces (top and side silhouette IoU), the roster style adds visible insignia /
## kit-bash geometry (more triangles or a changed accent) to the replaced unit and to the unique unit, and an owner's own-faction
## defs resolve to the roster style (ViewRecipeBook.style_for_def).

const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]
const MAX_IOU: float = 0.93  ## silhouette overlap above which a unique unit counts as a re-skin of the unit it replaces
const CELL: float = 0.08
const MIN_VISIBLE: float = 0.03  ## share of the silhouette cells (top or side view) that must differ between the vanilla and the roster style

var _book: ViewRecipeBook = null
var _rosters: Dictionary = {}


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	var f: FileAccess = FileAccess.open("res://data/bible/meridian_factions.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	_rosters = d["rosters"] as Dictionary


func _subs() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for rid: String in _rosters:
		var r: Dictionary = _rosters[rid] as Dictionary
		if str(r.get("kind", "")) == "vanilla":
			continue
		var parts: PackedStringArray = rid.split(".")
		var reps: Array = (r.get("delta", {}) as Dictionary).get("replacements", []) as Array
		out.append({"roster": rid, "faction": parts[1], "style": StringName(parts[1] + "." + parts[2]), "reps": reps})
	return out


func _model(rid: String, sid: StringName) -> Dictionary:
	return ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)


## Silhouette grids {Vector2i: true} of one model seen from above (xz) and from the side (zy).
func _views(d: Dictionary) -> Array[Dictionary]:
	var arr: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] as PackedInt32Array
	var top: Dictionary = {}
	var side: Dictionary = {}
	var i: int = 0
	while i + 2 < idx.size():
		_fill(top, pos[idx[i]].x, pos[idx[i]].z, pos[idx[i + 1]].x, pos[idx[i + 1]].z, pos[idx[i + 2]].x, pos[idx[i + 2]].z)
		_fill(side, pos[idx[i]].z, pos[idx[i]].y, pos[idx[i + 1]].z, pos[idx[i + 1]].y, pos[idx[i + 2]].z, pos[idx[i + 2]].y)
		i += 3
	return [top, side]


func _fill(g: Dictionary, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> void:
	var x0: int = floori(minf(ax, minf(bx, cx)) / CELL)
	var x1: int = floori(maxf(ax, maxf(bx, cx)) / CELL)
	var y0: int = floori(minf(ay, minf(by, cy)) / CELL)
	var y1: int = floori(maxf(ay, maxf(by, cy)) / CELL)
	var den: float = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
	if absf(den) < 1e-9:
		return
	for gx: int in range(x0, x1 + 1):
		for gy: int in range(y0, y1 + 1):
			var px: float = (float(gx) + 0.5) * CELL
			var py: float = (float(gy) + 0.5) * CELL
			var w0: float = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
			var w1: float = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
			if w0 >= 0.0 and w1 >= 0.0 and 1.0 - w0 - w1 >= 0.0:
				g[Vector2i(gx, gy)] = true


func _iou(a: Dictionary, b: Dictionary) -> float:
	var ca: Vector2 = _centroid(a)
	var cb: Vector2 = _centroid(b)
	var sh: Vector2i = Vector2i(roundi(ca.x - cb.x), roundi(ca.y - cb.y))
	var inter: int = 0
	for k: Variant in b:
		if a.has((k as Vector2i) + sh):
			inter += 1
	return float(inter) / float(maxi(a.size() + b.size() - inter, 1))


func _centroid(g: Dictionary) -> Vector2:
	var s: Vector2 = Vector2.ZERO
	for k: Variant in g:
		s += Vector2(k as Vector2i)
	return s / float(maxi(g.size(), 1))


func test_every_subfaction_has_two_unique_units_with_recipes(t: TestCtx) -> void:
	var subs: Array[Dictionary] = _subs()
	t.eq(subs.size(), 24, "24 subfactions")
	for s: Dictionary in subs:
		t.eq((s["reps"] as Array).size(), 2, "%s replaces two units" % s["roster"])
		for rep: Variant in s["reps"] as Array:
			var r: Dictionary = rep as Dictionary
			t.check(_book.has_recipe(StringName(str(r["replacement_unit_id"]))), "%s has a recipe" % r["replacement_unit_id"])
			t.check(_book.has_recipe(StringName(str(r["replaced_unit_id"]))), "%s has a recipe" % r["replaced_unit_id"])


func test_unique_units_are_not_copies_of_the_units_they_replace(t: TestCtx) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for s: Dictionary in _subs():
		for rep: Variant in s["reps"] as Array:
			var r: Dictionary = rep as Dictionary
			var old_id: String = str(r["replaced_unit_id"])
			var new_id: String = str(r["replacement_unit_id"])
			var va: Array[Dictionary] = _views(_model(old_id, s["style"] as StringName))
			var vb: Array[Dictionary] = _views(_model(new_id, s["style"] as StringName))
			var top: float = _iou(va[0], vb[0])
			var side: float = _iou(va[1], vb[1])
			lines.append("%s %s -> %s top %.2f side %.2f" % [s["roster"], old_id.get_slice(".", 2), new_id.get_slice(".", 2), top, side])
			t.lt(minf(top, side), MAX_IOU, "%s: %s reads as a different unit than %s (IoU top %.2f side %.2f)" % [s["roster"], new_id, old_id, top, side])
	t.note("\n".join(lines))


func test_roster_style_adds_visible_insignia_to_replaced_and_unique_units(t: TestCtx) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for s: Dictionary in _subs():
		var base: StringName = StringName(str(s["faction"]))
		for rep: Variant in s["reps"] as Array:
			var r: Dictionary = rep as Dictionary
			for id: String in [str(r["replaced_unit_id"]), str(r["replacement_unit_id"])]:
				var a: Dictionary = _model(id, base)
				var b: Dictionary = _model(id, s["style"] as StringName)
				t.ne((a["info"] as ViewModelInfo).content_hash, (b["info"] as ViewModelInfo).content_hash, "%s differs in %s" % [id, s["style"]])
				var ga: Array[Dictionary] = _colour_views(a)
				var gb: Array[Dictionary] = _colour_views(b)
				var top: float = _view_delta(ga[0], gb[0])
				var side: float = _view_delta(ga[1], gb[1])
				lines.append("%s %s top %.1f%% side %.1f%%" % [s["roster"], id.get_slice(".", 2), top * 100.0, side * 100.0])
				t.ge(maxf(top, side), MIN_VISIBLE, "%s wears a visible %s livery: %.1f%% of its top / side silhouette changed" % [id, s["style"], maxf(top, side) * 100.0])
	t.note("\n".join(lines))


## Subfaction styles never touch the vanilla faction models: the livery only applies to ids with a dot.
func test_vanilla_styles_get_no_livery(t: TestCtx) -> void:
	_load()
	for fac: String in FACTIONS:
		var sid: StringName = StringName(fac)
		t.check(not ViewLivery.is_subfaction(fac, _book.style(sid)), "%s is not a subfaction style" % fac)
	t.check(ViewLivery.is_subfaction("napc.usa", _book.style(&"napc.usa")), "napc.usa is a subfaction style")
	var tri_a: int = (_model("unit.napc.guardian_tank", &"napc")["info"] as ViewModelInfo).tris.x
	var tri_b: int = (_model("unit.napc.guardian_tank", &"napc.usa")["info"] as ViewModelInfo).tris.x
	t.gt(tri_b, tri_a, "the subfaction build carries the livery geometry (%d vs %d tris)" % [tri_b, tri_a])
	t.lt(tri_b - tri_a, 600, "the livery stays small (%d extra tris)" % (tri_b - tri_a))


## Top / side raster of {Vector2i: [height, Color]} (highest surface wins) of one built model.
func _colour_views(d: Dictionary) -> Array[Dictionary]:
	var arr: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] as PackedInt32Array
	var top: Dictionary = {}
	var side: Dictionary = {}
	var i: int = 0
	while i + 2 < idx.size():
		var a: Vector3 = pos[idx[i]]
		var b: Vector3 = pos[idx[i + 1]]
		var c: Vector3 = pos[idx[i + 2]]
		var n: Vector3 = (b - a).cross(c - a)
		var cc: Color = col[idx[i]]
		cc.a = 1.0
		var nl: float = maxf(n.length(), 1e-9)
		if n.y / nl < -0.3:
			_fill_c(top, a.x, a.z, a.y, b.x, b.z, b.y, c.x, c.z, c.y, cc, 1.0)
		if absf(n.x) / nl > 0.3:
			_fill_c(side, a.z, a.y, a.x, b.z, b.y, b.x, c.z, c.y, c.x, cc, signf(n.x))
		i += 3
	return [top, side]


func _fill_c(g: Dictionary, ax: float, ay: float, az: float, bx: float, by: float, bz: float, cx: float, cy: float, cz: float, col: Color, facing: float) -> void:
	var x0: int = floori(minf(ax, minf(bx, cx)) / CELL)
	var x1: int = floori(maxf(ax, maxf(bx, cx)) / CELL)
	var y0: int = floori(minf(ay, minf(by, cy)) / CELL)
	var y1: int = floori(maxf(ay, maxf(by, cy)) / CELL)
	var den: float = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
	if absf(den) < 1e-9:
		return
	for gx: int in range(x0, x1 + 1):
		for gy: int in range(y0, y1 + 1):
			var px: float = (float(gx) + 0.5) * CELL
			var py: float = (float(gy) + 0.5) * CELL
			var w0: float = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
			var w1: float = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
			var w2: float = 1.0 - w0 - w1
			if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
				var h: float = (w0 * az + w1 * bz + w2 * cz) * facing
				var k: Vector2i = Vector2i(gx, gy)
				var cur: Variant = g.get(k)
				if cur == null or h > (cur as Array)[0]:
					g[k] = [h, col]


## Share of the covered cells that exist in only one render or whose colour moved by dE00 >= 8.
func _view_delta(a: Dictionary, b: Dictionary) -> float:
	var keys: Dictionary = {}
	for k: Variant in a:
		keys[k] = true
	for k: Variant in b:
		keys[k] = true
	var diff: int = 0
	for k: Variant in keys:
		if not a.has(k) or not b.has(k):
			diff += 1
		elif ViewTeamColors.delta_e00((a[k] as Array)[1] as Color, (b[k] as Array)[1] as Color) >= 8.0:
			diff += 1
	return float(diff) / float(maxi(keys.size(), 1))


func test_own_faction_defs_wear_the_roster_style(t: TestCtx) -> void:
	_load()
	t.eq(_book.style_for_def("unit.napc.guardian_tank", "roster.napc.usa"), &"napc.usa", "own faction unit -> roster style")
	t.eq(_book.style_for_def("structure.napc.bulwark_cannon", "roster.napc.canada"), &"napc.canada", "own faction structure -> roster style")
	t.eq(_book.style_for_def("unit.napc.guardian_tank", "roster.napc.vanilla"), &"napc", "vanilla roster -> faction style")
	t.eq(_book.style_for_def("unit.napc.guardian_tank", "roster.nec.eurocorps"), &"napc", "foreign owner (captured) -> the unit's faction style")
	t.eq(_book.style_for_def("unit.shared.collector", "roster.han.china"), &"han.china", "shared defs wear the owner's style")
