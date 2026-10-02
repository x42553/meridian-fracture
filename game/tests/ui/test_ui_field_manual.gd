extends RefCounted
## Field Manual screen (ui.md 5.17): entry params, category switching, chips opening cards, search, roster picker, compare page,
## tech tree clicks and the skin restore on exit. Rendering checks are structural; the pixels are inspected in shots.

const H := preload("res://tests/ui/ui_harness.gd")

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


func _mount(h: H.Rig, params: Dictionary) -> UiScreenFieldManual:
	var p: Dictionary = params.duplicate()
	p["data"] = _gd()
	var scr: UiScreenFieldManual = UiScreenFieldManual.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter(p)
	return scr


func test_focus_id_opens_the_unit_card(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.napc.canada", "page": &"overview", "focus_id": "unit.napc.rifle_squad"})
	await H.frames(2)
	t.eq(scr.category, &"units", "a focus id switches to its category")
	t.eq(scr.selected_card()["name"], "Rifle Squad")
	t.eq(scr.model.roster_id(), "roster.napc.canada")
	t.check(scr.open_id("structure.shared.generator"), "open_id by structure id")
	t.eq(scr.category, &"structures")
	t.eq(scr.selected_card()["name"], "Generator")
	t.check(not scr.open_id("unit.napc.guardian_tank"), "Guardian Tank is not in the Canada roster")
	scr.exit()
	H.done(h)


func test_chips_open_cards_and_categories_render(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.han.china"})
	await H.frames(1)
	t.eq(scr.category, &"overview")
	for cat: StringName in [&"units", &"structures", &"research", &"powers", &"tree", &"compare", &"overview"]:
		scr.show_category(cat)
		await H.frames(1)
		t.eq(scr.category, cat)
		t.check(scr._detail_box.get_child_count() > 0, "%s renders a detail" % cat)
	scr.show_category(&"units")
	var first: Dictionary = scr.selected_card()
	t.check(not first.is_empty() and scr._rows.size() >= 16, "the unit list has rows: %d" % scr._rows.size())
	# a producer chip navigates to the structure
	var producer: Dictionary = first["producer"]
	scr.open_card(int(producer["kind"]), int(producer["index"]))
	t.eq(scr.category, &"structures")
	t.eq(scr.selected_card()["index"], producer["index"])
	scr.exit()
	H.done(h)


func test_search_groups_results_and_enter_opens_the_first(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.napc.canada"})
	await H.frames(1)
	scr._search.text = "narwhal"
	scr._run_search("narwhal")
	t.check(scr._searching and not scr._search_results.is_empty(), "search results")
	t.eq(scr._search_results[0]["name"], "Narwhal Amphibious Tank")
	t.check(scr._list_panel.visible, "results show in the list")
	scr._search.text_submitted.emit("narwhal")
	t.eq(scr.selected_card()["name"], "Narwhal Amphibious Tank")
	t.check(not scr._searching, "opening a result leaves search mode")
	scr._search.text = "zzzz"
	scr._run_search("zzzz")
	t.eq(scr._rows.size(), 0)
	t.check(scr.on_escape(), "Escape clears the search first")
	t.eq(scr._search.text, "")
	scr.exit()
	H.done(h)


func test_roster_picker_and_compare(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var d: GameData = _gd()
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.napc.vanilla", "page": &"units"})
	await H.frames(1)
	t.eq(scr._faction_pick.item_count, 8, "eight factions")
	t.eq(scr._sub_pick.item_count, 4, "vanilla plus three subfactions")
	scr._sub_pick.item_selected.emit(2)
	t.eq(scr.model.roster.id, d.rosters[int(scr._sub_pick.get_item_metadata(2))].id, "the subfaction picker switches the roster")
	scr._faction_pick.item_selected.emit(d.faction_idx("faction.han"))
	t.eq(scr.model.roster.faction, d.faction_idx("faction.han"), "the faction picker switches to its vanilla roster")
	t.check(scr.model.roster.is_vanilla)
	scr.show_category(&"compare")
	await H.frames(1)
	t.check(scr.compare_roster != null and scr.compare_roster != scr.model.roster, "a default comparison roster")
	var cmp_count: int = scr._detail_box.get_child_count()
	t.gt(cmp_count, 2, "compare page has header, columns and matrix")
	scr.compare_roster = d.rosters[d.roster_idx("roster.han.china")]
	scr._render_detail()
	await H.frames(1)
	scr.exit()
	H.done(h)


func test_tech_tree_click_opens_the_structure(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.napc.usa", "page": &"tree"})
	await H.frames(2)
	t.check(scr._tree_view != null and scr._tree_view.node_count() == scr.model.roster.producible_structures.size() + 1, "one node per structure")
	var gen: int = _gd().structure_idx("structure.shared.generator")
	var r: Rect2 = scr._tree_view.rect_of(DefEnums.Kind.STRUCTURE, gen)
	t.check(r.size != Vector2.ZERO, "generator node laid out")
	var got: Array = []
	scr._tree_view.node_selected.connect(func(k: int, i: int) -> void: got.append([k, i]))
	H.click(h.vp, scr._tree_view.global_position + r.get_center())
	await H.frames(1)
	t.eq(got.size(), 1, "click emits node_selected")
	t.eq(scr.category, &"structures")
	t.eq(scr.selected_index, gen)
	scr.exit()
	H.done(h)


func test_exit_restores_the_previous_skin(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	UiThemeService.rebuild(UiSkinSet.shared().skin_for("nec"))
	var before: Color = UiThemeService.current_skin().accent
	var scr: UiScreenFieldManual = _mount(h, {"roster_id": "roster.napc.vanilla"})
	await H.frames(1)
	t.check(UiThemeService.current_skin().accent != before, "the manual shows the viewed faction's skin")
	scr.exit()
	t.eq(UiThemeService.current_skin().accent, before, "the skin of the screen below comes back")
	H.done(h)


func test_live_view_marks_values_live(t: TestCtx) -> void:
	var d: GameData = _gd()
	var r: DefRoster = d.rosters[d.roster_idx("roster.napc.vanilla")]
	var view: DefPlayerView = DefPlayerView.new(d, r)
	var m: UiFmModel = UiFmModel.new()
	m.build(d, r, view)
	t.check(m.live, "an injected view is live")
	t.check(m.view == view)
	var idle: UiFmModel = UiFmModel.new()
	idle.build(d, r)
	t.check(not idle.live)
