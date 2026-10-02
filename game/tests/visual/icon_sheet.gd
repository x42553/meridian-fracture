extends Control
## VIEW-M9 contact sheet: bakes the icons of a whole roster through ViewIconBake and lays them out on a dark backdrop, then
## prints the timings (cold bake, prewarm total, cache-hit path). Not a test: run it with
##   tools/gd shot res://tests/visual/icon_sheet.tscn out.png --size 1920x1080 --frames 400 -- --roster=roster.napc.canada [--size=card|icon|portrait|banner]
##   [--cols=10] [--cold] [--items=unit.napc.guardian,structure.napc.hq] [--report]
## `--cold` clears the disk cache first (measures real bakes); without it a second run measures the cache-hit path.

var _size: int = ViewIconBake.S_CARD
var _cols: int = 10
var _cold: bool = false
var _roster_id: String = "roster.napc.canada"
var _items: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--roster="):
			_roster_id = a.substr(9)
		elif a.begins_with("--size="):
			_size = ["icon", "portrait", "card", "banner"].find(a.substr(7))
		elif a.begins_with("--cols="):
			_cols = a.substr(7).to_int()
		elif a.begins_with("--items="):
			_items = a.substr(8).split(",", false)
		elif a == "--cold":
			_cold = true
	_size = maxi(_size, 0)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_run.call_deferred()


func _run() -> void:
	var data: GameData = GameData.load_default()
	var ri: int = data.roster_idx(_roster_id)
	var roster: DefRoster = data.rosters[ri] if ri >= 0 else data.vanilla_roster_of(0)
	var defs: ViewDefAdapter = ViewDefAdapter.new()
	defs.setup(data)
	var bake: ViewIconBake = ViewIconBake.new()
	bake.setup_standalone()
	add_child(bake)
	bake.render_enabled = true
	if _cold:
		print("SHEET cleared %d cached files" % bake.clear_disk_cache())
	var entries: Array[Dictionary] = []
	if _items.is_empty():
		for si: int in roster.producible_structures:
			entries.append({"kind": SimEntity.Kind.STRUCTURE, "idx": si})
		for ui: int in roster.producible_units:
			entries.append({"kind": SimEntity.Kind.UNIT, "idx": ui})
		if roster.hq_idx >= 0:
			entries.append({"kind": SimEntity.Kind.STRUCTURE, "idx": roster.hq_idx})
		if roster.mcv_idx >= 0:
			entries.append({"kind": SimEntity.Kind.UNIT, "idx": roster.mcv_idx})
	else:
		for id: String in _items:
			var si2: int = data.structure_idx(id)
			if si2 >= 0:
				entries.append({"kind": SimEntity.Kind.STRUCTURE, "idx": si2})
			else:
				entries.append({"kind": SimEntity.Kind.UNIT, "idx": data.unit_idx(id)})
	var reqs: Array = []
	for e: Dictionary in entries:
		var vd: ViewDef = defs.def_for(e["kind"] as int, e["idx"] as int)
		e["vd"] = vd
		reqs.append({"tag": StringName(vd.id), "recipe": vd.recipe_id, "style": bake.recipe_book().style_for_def(vd.id, _roster_id), "scale_bp": vd.scale_bp, "size": _size})
	var t0: int = Time.get_ticks_usec()
	bake.prewarm(reqs)
	await bake.wait_idle()
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("SHEET %d icons size=%d in %.0f ms; bakes=%d hits=%d hit_us_max=%d" % [entries.size(), _size, ms, bake.stats["bakes"], bake.stats["hits"], bake.stats["hit_us_max"]])
	# lay out
	var px: Vector2i = ViewIconBake.SIZES[_size]
	var scale_k: float = minf(1.0, (1860.0 / float(_cols) - 4.0) / float(px.x))
	var cell: Vector2 = Vector2(float(px.x) * scale_k, float(px.y) * scale_k)
	var grid: GridContainer = GridContainer.new()
	grid.columns = _cols
	grid.position = Vector2(20.0, 16.0)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 14)
	add_child(grid)
	for e2: Dictionary in entries:
		var vd2: ViewDef = e2["vd"] as ViewDef
		var box: VBoxContainer = VBoxContainer.new()
		var trect: TextureRect = TextureRect.new()
		trect.texture = bake.peek(vd2.recipe_id, bake.recipe_book().style_for_def(vd2.id, _roster_id), vd2.scale_bp, _size)
		trect.custom_minimum_size = cell
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_SCALE
		var back: ColorRect = ColorRect.new()
		back.color = Color(0.13, 0.15, 0.18)
		back.custom_minimum_size = cell
		var holder: Control = Control.new()
		holder.custom_minimum_size = cell
		holder.add_child(back)
		holder.add_child(trect)
		box.add_child(holder)
		var lb: Label = Label.new()
		lb.text = vd2.id.get_slice(".", 2)
		lb.add_theme_font_size_override("font_size", 11)
		box.add_child(lb)
		grid.add_child(box)
	# cache-hit path: forget the memory copies and ask again
	bake.flush()
	bake.clear_memory()
	var t1: int = Time.get_ticks_usec()
	bake.prewarm(reqs)
	await bake.wait_idle()
	var ms2: float = float(Time.get_ticks_usec() - t1) / 1000.0
	print("SHEET cache-hit pass: %d icons in %.1f ms (%.2f ms each); hit_us_max=%d" % [entries.size(), ms2, ms2 / maxf(float(entries.size()), 1.0), bake.stats["hit_us_max"]])
