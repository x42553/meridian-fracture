extends SceneTree
## VQ2A probe: how much of a unit's top view and side view changes between the vanilla style and the roster (subfaction) style.
## `tools/gd run res://tests/visual/subfaction_delta_probe.gd -- [faction]` prints, per replaced / unique unit, the share of the
## silhouette cells (0.08 m) whose colour moved by dE00 >= 8 or that exist in only one of the two renders.

const CELL: float = 0.08

func _init() -> void:
	var only: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bible/meridian_factions.json")) as Dictionary
	var rosters: Dictionary = d["rosters"] as Dictionary
	var low: PackedStringArray = PackedStringArray()
	for rid: String in rosters:
		var r: Dictionary = rosters[rid] as Dictionary
		if str(r.get("kind", "")) == "vanilla":
			continue
		var parts: PackedStringArray = rid.split(".")
		if only != "" and parts[1] != only:
			continue
		var fac: StringName = StringName(parts[1])
		var sty: StringName = StringName(parts[1] + "." + parts[2])
		var ids: Array[String] = []
		for rep: Variant in (r["delta"] as Dictionary)["replacements"] as Array:
			ids.append(str((rep as Dictionary)["replaced_unit_id"]))
			ids.append(str((rep as Dictionary)["replacement_unit_id"]))
		var line: PackedStringArray = PackedStringArray()
		for id: String in ids:
			var a: Dictionary = _grid(book, id, fac)
			var b: Dictionary = _grid(book, id, sty)
			var top: float = _delta(a["top"] as Dictionary, b["top"] as Dictionary)
			var side: float = _delta(a["side"] as Dictionary, b["side"] as Dictionary)
			line.append("%s %.1f/%.1f%%" % [id.get_slice(".", 2).substr(0, 14), top * 100.0, side * 100.0])
			if maxf(top, side) < 0.03:
				low.append("%s %s" % [sty, id])
		print("%-26s %s" % [sty, " | ".join(line)])
	print("LOW (<3%% visible delta): %d" % low.size())
	for l: String in low:
		print("  ", l)
	quit()


func _grid(book: ViewRecipeBook, id: String, sty: StringName) -> Dictionary:
	var o: Dictionary = ViewModelBuilder.build_data(book, StringName(id), sty, 10000)
	var arr: Array = (o["mesh"] as Dictionary)["arrays"] as Array
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
			_fill(top, a.x, a.z, a.y, b.x, b.z, b.y, c.x, c.z, c.y, cc)
		if absf(n.x) / nl > 0.3:
			_fill(side, a.z, a.y, a.x, b.z, b.y, b.x, c.z, c.y, c.x, cc, signf(n.x))
		i += 3
	return {"top": top, "side": side}


func _fill(g: Dictionary, ax: float, ay: float, az: float, bx: float, by: float, bz: float, cx: float, cy: float, cz: float, col: Color, facing: float = 1.0) -> void:
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


func _delta(a: Dictionary, b: Dictionary) -> float:
	var n: int = 0
	var diff: int = 0
	var keys: Dictionary = {}
	for k: Variant in a:
		keys[k] = true
	for k: Variant in b:
		keys[k] = true
	for k: Variant in keys:
		n += 1
		if not a.has(k) or not b.has(k):
			diff += 1
		elif ViewTeamColors.delta_e00((a[k] as Array)[1] as Color, (b[k] as Array)[1] as Color) >= 8.0:
			diff += 1
	return float(diff) / float(maxi(n, 1))
