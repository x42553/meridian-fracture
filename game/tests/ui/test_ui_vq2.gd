extends RefCounted
## VQ2B UI polish: the model viewer degrades without a renderer, the Field Manual tech tree fits its page (no horizontal scrollbar, a lower
## half with builds / unlocks chips), the feed lines carry a backing plate, the lobby briefing offers the roster showcase.

const H := preload("res://tests/ui/ui_harness.gd")

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


func test_model_viewer_falls_back_without_a_renderer(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(800, 600))
	var v: UiModelViewer = UiModelViewer.new(Vector2(320.0, 230.0))
	h.root.add_child(v)
	var shown: bool = v.show_def("unit.napc.guardian_tank", "roster.napc.vanilla")
	if DisplayServer.get_name() == "headless":
		t.check(not shown, "no renderer: the glyph / baked icon fallback stays")
		t.check(not v.has_model(), "no model")
	t.check(not v.is_paused(), "not paused by default")
	v.set_paused(true)  # must not crash without a turntable
	v.reset_view()
	t.eq(v.def_id, "unit.napc.guardian_tank")
	H.done(h)


func test_tech_tree_fits_the_page_width(t: TestCtx) -> void:
	var d: GameData = _gd()
	var model: UiFmModel = UiFmModel.new()
	model.build(d, d.rosters[d.roster_idx("roster.napc.vanilla")])
	for width: int in [1000, 1540]:
		var h: H.Rig = await H.make(Vector2i(width + 80, 700))
		var tree: UiFmTechTree = UiFmTechTree.new()
		tree.fit_width = true
		tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box: VBoxContainer = VBoxContainer.new()
		box.custom_minimum_size = Vector2(width, 0.0)
		h.root.add_child(box)
		box.add_child(tree)
		tree.set_tree(model.tech_tree())
		await H.frames(2)
		var max_x: float = 0.0
		for n: Variant in model.tech_tree()["nodes"] as Array:
			var r: Rect2 = tree.rect_of(int((n as Dictionary)["kind"]), int((n as Dictionary)["index"]))
			max_x = maxf(max_x, r.end.x)
		t.check(max_x <= float(width) + 0.5, "width %d: the rightmost node ends at %.0f" % [width, max_x])
		t.eq(tree.custom_minimum_size.x, 0.0, "no minimum width forces a horizontal scrollbar")
		H.done(h)


func test_field_manual_tree_page_has_a_lower_half(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var scr: UiScreenFieldManual = UiScreenFieldManual.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"data": _gd(), "roster_id": "roster.napc.vanilla", "page": &"tree"})
	await H.frames(2)
	var buttons: int = 0
	var stack: Array[Node] = [scr._detail_box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			buttons += 1
		stack.append_array(n.get_children())
	t.gt(buttons, 10, "builds / unlocks chips under the graph")
	scr.exit()
	H.done(h)


func test_log_feed_keeps_lines_and_draws(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(800, 300))
	var f: UiLogFeed = UiLogFeed.new()
	f.size = Vector2(420.0, 100.0)
	h.root.add_child(f)
	f.add("Construction complete: Generator.", UiPalette.semantic(&"ok"))
	f.add("Unit under attack at 05")
	await H.frames(2)
	t.eq(f.line_count(), 2)
	H.done(h)
