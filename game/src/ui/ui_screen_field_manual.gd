class_name UiScreenFieldManual
extends UiScreen
## Field Manual (ui.md 5.17, UI-12 lean): the in-game encyclopedia of all 8 factions and 32 rosters. Left navigation (roster
## pickers, Overview / Units / Structures / Research / Powers / Tech tree / Compare, search), a middle list and a detail card whose
## numbers are the RESOLVED stats of the chosen roster with delta markers against the base values (`UiFmModel`). Reached from the
## main menu, the lobby briefing (`focus_id`), the Esc menu and F1 in a match (pushed overlay).
## Params: `{roster_id: String, page: StringName = &"overview", focus_id: String = "", view: DefPlayerView}`; `view` is the live
## player view of a running match (badge LIVE); without it the stats are the menu values (no completed research).

const CATEGORIES: Array[Dictionary] = [
	{"id": &"overview", "title": "Overview", "glyph": 24}, {"id": &"units", "title": "Units", "glyph": 1},
	{"id": &"structures", "title": "Structures", "glyph": 0}, {"id": &"research", "title": "Research", "glyph": 24},
	{"id": &"powers", "title": "Powers", "glyph": 6}, {"id": &"tree", "title": "Tech tree", "glyph": 5},
	{"id": &"compare", "title": "Compare", "glyph": 7},
]
const SEARCH_DEBOUNCE_S: float = 0.15
const KIND_OF: Dictionary = {&"units": DefEnums.Kind.UNIT, &"structures": DefEnums.Kind.STRUCTURE, &"research": DefEnums.Kind.RESEARCH}

var data: GameData = null
var model: UiFmModel = null
var category: StringName = &"overview"
var selected_kind: int = -1
var selected_index: int = -1
## Roster B of the Compare page (null = none chosen yet).
var compare_roster: DefRoster = null

var _view_override: DefPlayerView = null
var _faction_pick: OptionButton = null
var _sub_pick: OptionButton = null
var _search: LineEdit = null
var _search_timer: Timer = null
var _nav_buttons: Dictionary = {}
var _list_panel: Control = null
var _list_box: VBoxContainer = null
var _list_scroll: ScrollContainer = null
var _detail_scroll: ScrollContainer = null
var _detail_box: VBoxContainer = null
var _title_badge: UiFactionBadge = null
var _live_tag: Label = null
var _rows: Array[UiFmRow] = []
var _tree_view: UiFmTechTree = null
var _prev_skin: UiSkin = null
var _searching: bool = false
var _search_results: Array[Dictionary] = []
var _cmp_faction: OptionButton = null
var _cmp_sub: OptionButton = null
var _cmp_unit: int = -1
var _icons: UiViewPortWorld = null


func _init() -> void:
	super._init()
	screen_id = &"field_manual"


## Opens the Field Manual over the current screen. `params` as documented above; false when the app shell is missing.
static func open(params: Dictionary = {}) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState") if tree != null else null
	if state == null:
		return false
	state.call("push_mode", AppFlow.Mode.FIELD_MANUAL, params)
	return true


func enter(params: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var state: Node = get_tree().root.get_node_or_null("AppState") if is_inside_tree() else null
	data = params.get("data") as GameData
	if data == null and state != null:
		data = state.get("data") as GameData
	if data == null:
		data = GameData.load_default()
	_view_override = params.get("view") as DefPlayerView
	_prev_skin = UiThemeService.current_skin()
	var roster: DefRoster = data.rosters[data.roster_idx(str(params.get("roster_id", _default_roster_id())))] if data.roster_idx(str(params.get("roster_id", _default_roster_id()))) >= 0 else data.vanilla_roster_of(0)
	_build()
	_icons = UiViewPortWorld.menu_icons()
	if not _icons.icon_ready.is_connected(_on_icon_ready):
		_icons.icon_ready.connect(_on_icon_ready)
	set_roster(roster)
	var want: StringName = StringName(str(params.get("page", "overview")))
	show_category(want if _is_category(want) else &"overview")
	var focus_id: String = str(params.get("focus_id", ""))
	if not focus_id.is_empty():
		open_id(focus_id)


func exit() -> void:
	if _icons != null and _icons.icon_ready.is_connected(_on_icon_ready):
		_icons.icon_ready.disconnect(_on_icon_ready)
	if _prev_skin != null:
		UiThemeService.rebuild(_prev_skin)


func default_focus() -> Control:
	return _nav_buttons.get(category) as Control


func on_escape() -> bool:
	if _search != null and not _search.text.is_empty():
		_search.text = ""
		_run_search("")
		return true
	return false


func _default_roster_id() -> String:
	var settings: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	if settings != null and settings.get("store") is AppSettingsStore:
		return str((settings.get("store") as AppSettingsStore).get_value(&"game/last_roster"))
	return "roster.napc.vanilla"


static func _is_category(id: StringName) -> bool:
	for c: Dictionary in CATEGORIES:
		if c["id"] == id:
			return true
	return false


# ---------------------------------------------------------------------------------------------------------------- build

func _build() -> void:
	UiScreenKit.backdrop(self, Color(UiPalette.BG_DEEP, 0.97))
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)
	UiLayerRoot.fill(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	margin.add_child(col)
	col.add_child(_build_header())
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", UiMetrics.SP_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	body.add_child(_build_nav())
	body.add_child(_build_list())
	body.add_child(_build_detail())


func _build_header() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_4)
	_title_badge = UiFactionBadge.new("", 54.0)
	_title_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_title_badge)
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override("separation", -4)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(UiScreenKit.wordmark("FIELD MANUAL", 34, 800, 3, UiPalette.TEXT))
	_live_tag = UiScreenKit.label("", &"CaptionLabel")
	words.add_child(_live_tag)
	h.add_child(words)
	h.add_child(UiScreenKit.spacer(24.0))
	_faction_pick = OptionButton.new()
	_faction_pick.custom_minimum_size = Vector2(300.0, 40.0)
	_faction_pick.accessibility_name = "Faction"
	for f: DefFaction in data.factions:
		_faction_pick.add_item(f.ui_name)
	_faction_pick.item_selected.connect(_on_faction_picked)
	h.add_child(_faction_pick)
	_sub_pick = OptionButton.new()
	_sub_pick.custom_minimum_size = Vector2(230.0, 40.0)
	_sub_pick.accessibility_name = "Subfaction"
	_sub_pick.item_selected.connect(_on_sub_picked)
	h.add_child(_sub_pick)
	h.add_child(UiScreenKit.spacer(0.0, true))
	_search = LineEdit.new()
	_search.placeholder_text = "Search units, structures, powers"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(330.0, 40.0)
	_search.accessibility_name = "Search the Field Manual"
	_search.text_changed.connect(_on_search_text)
	_search.text_submitted.connect(func(_t: String) -> void:
		if not _search_results.is_empty():
			var r: Dictionary = _search_results[0]
			open_card(int(r["kind"]), int(r["index"])))
	h.add_child(_search)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE_S
	_search_timer.timeout.connect(func() -> void: _run_search(_search.text))
	add_child(_search_timer)
	var back: Button = UiScreenKit.button("BACK", &"GhostButton", Vector2(130.0, 40.0))
	back.pressed.connect(func() -> void: back_requested.emit())
	h.add_child(back)
	return h


func _build_nav() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.custom_minimum_size = Vector2(210.0, 0.0)
	v.add_theme_constant_override("separation", 6)
	for c: Dictionary in CATEGORIES:
		var b: Button = Button.new()
		b.text = str(c["title"]).to_upper()
		b.toggle_mode = true
		b.theme_type_variation = &"TabButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0.0, 44.0)
		b.focus_mode = Control.FOCUS_ALL
		var id: StringName = c["id"]
		b.pressed.connect(func() -> void: show_category(id))
		v.add_child(b)
		_nav_buttons[id] = b
	return v


func _build_list() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(390.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_panel = panel
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 0)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list_box)
	return panel


func _build_detail() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(_detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", UiMetrics.SP_3)
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(_detail_box)
	return panel


# ---------------------------------------------------------------------------------------------------------------- roster

## Switches the manual to another roster (rebuilds the model, keeps the category, tries to keep the selection).
func set_roster(r: DefRoster) -> void:
	if r == null:
		return
	model = UiFmModel.new()
	model.build(data, r, _view_override)
	_live_tag.text = "LIVE VALUES" if model.live else "BASE ROSTER VALUES"
	_title_badge.faction_code = data.factions[r.faction].code.to_lower()
	UiThemeService.rebuild(UiSkinSet.shared().skin_for(data.factions[r.faction].code.to_lower()))
	_faction_pick.select(r.faction)
	_fill_subs(_sub_pick, r.faction, r)
	if compare_roster != null and compare_roster == r:
		compare_roster = null
	if selected_kind >= 0 and model.card_for(selected_kind, selected_index).is_empty():
		selected_kind = -1
		selected_index = -1
	refresh()


func _fill_subs(pick: OptionButton, faction: int, current: DefRoster) -> void:
	pick.clear()
	var f: DefFaction = data.factions[faction]
	var ids: Array[int] = [f.vanilla_roster]
	for ri: int in f.sub_rosters:
		ids.append(ri)
	for i: int in ids.size():
		var r: DefRoster = data.rosters[ids[i]]
		pick.add_item("Vanilla" if r.is_vanilla else UiFmModel.roster_sub_name(r.id))
		pick.set_item_metadata(i, ids[i])
		if current != null and r == current:
			pick.select(i)


func _on_faction_picked(i: int) -> void:
	var r: DefRoster = data.vanilla_roster_of(i)
	set_roster(r)


func _on_sub_picked(i: int) -> void:
	set_roster(data.rosters[int(_sub_pick.get_item_metadata(i))])


# ---------------------------------------------------------------------------------------------------------------- navigation

func show_category(id: StringName) -> void:
	category = id
	_searching = false
	for k: StringName in _nav_buttons:
		(_nav_buttons[k] as Button).set_pressed_no_signal(k == id)
	refresh()


## Rebuilds the list and the detail for the current category and selection.
func refresh() -> void:
	if model == null:
		return
	_clear(_list_box)
	_rows.clear()
	_tree_view = null
	var wide: bool = category == &"overview" or category == &"compare" or category == &"tree"
	_list_panel.visible = not wide
	match category:
		&"units":
			_fill_list(model.units())
		&"structures":
			_fill_list(model.structures())
		&"research":
			_fill_list(model.research())
		&"powers":
			_fill_list(model.powers())
	if _searching:
		_list_panel.visible = true
		_fill_search()
	_render_detail()


func _fill_list(cards: Array[Dictionary]) -> void:
	var first: UiFmRow = null
	var current: UiFmRow = null
	var last_group: String = ""
	for c: Dictionary in cards:
		var group: String = _group_of(c)
		if group != last_group and not group.is_empty():
			var hdr: Label = UiScreenKit.label(group.to_upper(), &"CaptionLabel")
			hdr.custom_minimum_size = Vector2(0.0, 30.0)
			hdr.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			var pad: MarginContainer = MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 14)
			pad.add_child(hdr)
			_list_box.add_child(pad)
			last_group = group
		var row: UiFmRow = UiFmRow.new()
		row.set_card(c)
		row.selected.connect(open_card.bind(int(c["kind"]), int(c["index"])))
		_list_box.add_child(row)
		_rows.append(row)
		_row_icon(row)
		if first == null:
			first = row
		if int(c["kind"]) == selected_kind and int(c["index"]) == selected_index:
			current = row
	if current == null and first != null:
		current = first
		selected_kind = first.kind
		selected_index = first.def_index
	if current != null:
		current.is_selected = true


func _group_of(c: Dictionary) -> String:
	if int(c["kind"]) == DefEnums.Kind.UNIT:
		if bool(c.get("summon", false)):
			return "Summoned"
		return "Tier %d" % int(c["tier"]) if int(c["tier"]) > 0 else "Service"
	if int(c["kind"]) == DefEnums.Kind.STRUCTURE:
		return "Headquarters" if bool(c.get("start", false)) else ("Depth %d" % int(c["tier"]))
	if int(c["kind"]) == DefEnums.Kind.SUPERWEAPON:
		return "Superweapon"
	if int(c["kind"]) == DefEnums.Kind.POWER:
		return "Support powers"
	return ""


## Opens the card of (kind, def index): switches the category, selects the row and shows the detail.
func open_card(kind: int, def_index: int) -> void:
	var cat: StringName = _category_of_kind(kind)
	selected_kind = kind
	selected_index = def_index
	_searching = false
	if cat != category or not _rows.any(func(r: UiFmRow) -> bool: return r.kind == kind and r.def_index == def_index):
		category = cat
		for k: StringName in _nav_buttons:
			(_nav_buttons[k] as Button).set_pressed_no_signal(k == cat)
		refresh()
		_scroll_to_selected()
		return
	for r: UiFmRow in _rows:
		r.is_selected = r.kind == kind and r.def_index == def_index
	_render_detail()


## Opens a def by its id ("unit.napc.rifle_squad"); false when the id is unknown or not in the roster.
func open_id(def_id: String) -> bool:
	for kind: int in UiFmModel.SUMMARY_KINDS:
		var idx: int = data.idx(kind, def_id)
		if idx >= 0 and not model.card_for(kind, idx).is_empty():
			open_card(kind, idx)
			return true
	return false


func _category_of_kind(kind: int) -> StringName:
	match kind:
		DefEnums.Kind.UNIT:
			return &"units"
		DefEnums.Kind.STRUCTURE:
			return &"structures"
		DefEnums.Kind.RESEARCH:
			return &"research"
	return &"powers"


func _scroll_to_selected() -> void:
	get_tree().process_frame.connect(_do_scroll, CONNECT_ONE_SHOT)


func _do_scroll() -> void:
	for r: UiFmRow in _rows:
		if r.is_selected and is_instance_valid(_list_scroll):
			_list_scroll.ensure_control_visible(r)


func selected_card() -> Dictionary:
	if model == null or selected_kind < 0:
		return {}
	return model.card_for(selected_kind, selected_index)


# ---------------------------------------------------------------------------------------------------------------- search

func _on_search_text(_t: String) -> void:
	_search_timer.start()


func _run_search(text: String) -> void:
	if text.strip_edges().is_empty():
		_searching = false
		_search_results = []
		refresh()
		return
	_search_results = model.search(text, 20)
	_searching = true
	refresh()


func _fill_search() -> void:
	_clear(_list_box)
	_rows.clear()
	if _search_results.is_empty():
		var l: Label = UiScreenKit.label("Nothing matches \"%s\"." % _search.text, &"DimLabel", true)
		l.custom_minimum_size = Vector2(300.0, 60.0)
		_list_box.add_child(l)
		return
	var last: String = ""
	for r: Dictionary in _search_results:
		if str(r["what"]) != last:
			last = str(r["what"])
			var hdr: Label = UiScreenKit.label(last.to_upper(), &"CaptionLabel")
			var pad: MarginContainer = MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 14)
			pad.add_child(hdr)
			_list_box.add_child(pad)
		var row: UiFmRow = UiFmRow.new()
		row.set_card(model.card_for(int(r["kind"]), int(r["index"])))
		row.selected.connect(open_card.bind(int(r["kind"]), int(r["index"])))
		_list_box.add_child(row)
		_rows.append(row)


# ---------------------------------------------------------------------------------------------------------------- detail

func _clear(box: Control) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _render_detail() -> void:
	_clear(_detail_box)
	_detail_scroll.scroll_vertical = 0
	match category:
		&"overview":
			_render_overview()
		&"tree":
			_render_tree()
		&"compare":
			_render_compare()
		_:
			_detail_box.add_child(UiFmCardView.build(_card_with_icon(), open_card))


## The selected card plus its baked portrait (`icon`, null until ready) for units and structures; the head tile keeps its glyph
## while the icon is being baked.
func _card_with_icon() -> Dictionary:
	var card: Dictionary = selected_card()
	if card.is_empty() or _icons == null or model == null:
		return card
	var kind: int = int(card.get("kind", -1))
	if kind == DefEnums.Kind.UNIT or kind == DefEnums.Kind.STRUCTURE:
		card["icon"] = _icons.request_icon(str(card.get("id", "")), model.roster_id(), UiViewPort.ICON_SIZE_PORTRAIT)
		card["roster_id"] = model.roster_id()  # the head tile becomes the 3D turntable (UiModelViewer)
	return card


## Units and structures show their baked model (128 x 96) in the list; the class glyph stays until it is ready.
func _row_icon(row: UiFmRow) -> void:
	if _icons == null or model == null or row.def_id.is_empty():
		return
	if row.kind == DefEnums.Kind.UNIT or row.kind == DefEnums.Kind.STRUCTURE:
		row.icon = _icons.request_icon(row.def_id, model.roster_id(), UiViewPort.ICON_SIZE_ICON)


## A baked icon finished: redraw the open card when it is the one that was waiting.
func _on_icon_ready(key: StringName) -> void:
	for r: UiFmRow in _rows:
		if r.icon == null and not r.def_id.is_empty() and String(key).begins_with(r.def_id + "|"):
			_row_icon(r)
	var card: Dictionary = selected_card()
	if _detail_box == null or card.is_empty() or not String(key).begins_with(str(card.get("id", "")) + "|"):
		return
	if category != &"overview" and category != &"tree" and category != &"compare":
		_render_detail()


func _para(text: String, variation: StringName = &"") -> void:
	if not text.strip_edges().is_empty():
		_detail_box.add_child(UiScreenKit.label(text, variation, true))


func _render_overview() -> void:
	var ov: Dictionary = model.overview()
	var f: Dictionary = ov["faction"]
	var r: Dictionary = ov["roster"]
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiMetrics.SP_5)
	var badge: UiFactionBadge = UiFactionBadge.new(str(f["code"]).to_lower(), 110.0)
	badge.sub_key = "" if bool(r["vanilla"]) else "%s.%s" % [str(f["code"]).to_lower(), str(r["id"]).get_slice(".", 2)]
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(badge)
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm: Label = UiScreenKit.label(str(f["name"]).to_upper(), &"HeaderLabel")
	nm.add_theme_font_size_override("font_size", 30)
	v.add_child(nm)
	var motto: Label = UiScreenKit.label("\"%s\"" % f["motto"], &"SubLabel", true)
	motto.add_theme_color_override("font_color", UiScreenKit.accent(self))
	v.add_child(motto)
	if not bool(r["vanilla"]):
		v.add_child(UiScreenKit.label("%s  •  %s" % [r["sub"], r["title"]], &"NameLabel"))
	v.add_child(UiScreenKit.label(str(f["identity"]), &"DimLabel", true))
	head.add_child(v)
	_detail_box.add_child(head)
	var counts: Dictionary = ov["counts"]
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", UiMetrics.SP_5)
	for pair: Array in [["Units", counts["units"]], ["Structures", counts["structures"]], ["Research", counts["research"]], ["Powers", int(counts["powers"]) + 1]]:
		chips.add_child(UiScreenKit.label("%s  %s" % [str(pair[0]).to_upper(), pair[1]], &"CaptionLabel"))
	_detail_box.add_child(chips)
	if not bool(r["vanilla"]):
		var b1: VBoxContainer = UiFmCardView.section(_detail_box, "%s: %s" % [r["sub"], r["title"]])
		b1.add_child(UiScreenKit.label(str(r["identity"]), &"NameLabel", true))
		b1.add_child(UiScreenKit.label(str(r["lore"]), &"", true))
	var b2: VBoxContainer = UiFmCardView.section(_detail_box, "Background")
	b2.add_child(UiScreenKit.label(str(f["lore"]), &"", true))
	var traits: PackedStringArray = f["traits"] as PackedStringArray
	if not traits.is_empty():
		var b3: VBoxContainer = UiFmCardView.section(_detail_box, "Faction traits")
		UiFmCardView.bullets(b3, Array(traits))
	var mods: Array = ov["modifiers"] as Array
	if not mods.is_empty():
		var b4: VBoxContainer = UiFmCardView.section(_detail_box, "Subfaction modifiers")
		for m: Dictionary in mods:
			var h: HBoxContainer = HBoxContainer.new()
			h.add_theme_constant_override("separation", UiMetrics.SP_2)
			var arrow: Label = UiScreenKit.label("▲" if int(m["delta_bp"]) > 0 else "▼")
			arrow.add_theme_color_override("font_color", UiPalette.semantic(&"ok") if str(m["tone"]) == "good" else UiPalette.semantic(&"danger"))
			arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			h.add_child(arrow)
			var t: Label = UiScreenKit.label(str(m["text"]), &"", true)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(t)
			b4.add_child(h)
	var repl: Array = ov["replacements"] as Array
	var removed: Array = ov["removed"] as Array
	if not repl.is_empty() or not removed.is_empty():
		var b5: VBoxContainer = UiFmCardView.section(_detail_box, "Roster changes")
		for rp: Dictionary in repl:
			var hr: HBoxContainer = HBoxContainer.new()
			hr.add_theme_constant_override("separation", UiMetrics.SP_3)
			hr.add_child(UiFmCardView.chip(rp["baseline"] as Dictionary, func(_k: int, _i: int) -> void: pass))
			hr.add_child(UiScreenKit.label("is replaced by", &"DimLabel"))
			hr.add_child(UiFmCardView.chip(rp["replacement"] as Dictionary, open_card))
			b5.add_child(hr)
		if not removed.is_empty():
			var names: PackedStringArray = PackedStringArray()
			for rm: Dictionary in removed:
				names.append(str(rm["name"]))
			b5.add_child(UiScreenKit.label("Not available: " + ", ".join(names), &"DimLabel", true))
	var b6: VBoxContainer = UiFmCardView.section(_detail_box, "Opening")
	b6.add_child(UiScreenKit.label(str(r["opening"]) if not str(r["opening"]).is_empty() else str(f["opening"]), &"", true))
	var counter: String = str(r["counterplay"]) if not str(r["counterplay"]).is_empty() else str(f["counterplay"])
	if not counter.is_empty():
		var b7: VBoxContainer = UiFmCardView.section(_detail_box, "Counterplay")
		b7.add_child(UiScreenKit.label(counter, &"", true))


func _render_tree() -> void:
	var b: VBoxContainer = UiFmCardView.section(_detail_box, "Structures by prerequisite depth")
	b.add_child(UiScreenKit.label("Click a structure to open its card.", &"DimLabel"))
	var tree: Dictionary = model.tech_tree()
	_tree_view = UiFmTechTree.new()
	_tree_view.fit_width = true
	_tree_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_view.set_tree(tree)
	_tree_view.node_selected.connect(open_card)
	b.add_child(_tree_view)
	# the lower half: what every structure builds and unlocks, as clickable chips (the graph itself only shows the prerequisites)
	var pb: VBoxContainer = UiFmCardView.section(_detail_box, "What each structure builds and unlocks")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiMetrics.SP_3)
	grid.add_theme_constant_override("v_separation", UiMetrics.SP_3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.add_child(grid)
	var nodes: Array = (tree.get("nodes", []) as Array).duplicate()
	nodes.sort_custom(func(x: Variant, y: Variant) -> bool:
		var a: Dictionary = x as Dictionary
		var c: Dictionary = y as Dictionary
		return int(a["column"]) < int(c["column"]) or (int(a["column"]) == int(c["column"]) and int(a["row"]) < int(c["row"])))
	for nv: Variant in nodes:
		var n: Dictionary = nv as Dictionary
		var card: Dictionary = model.card_for(int(n["kind"]), int(n["index"]))
		var produces: Array = card.get("produces", []) as Array
		var unlocks: Array = card.get("unlocks", []) as Array
		if produces.is_empty() and unlocks.is_empty():
			continue
		var cell: PanelContainer = PanelContainer.new()
		cell.theme_type_variation = &"InsetPanel"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pad: MarginContainer = MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 10)
		cell.add_child(pad)
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		pad.add_child(col)
		var title: Label = UiScreenKit.label(str(n["name"]).to_upper(), &"NameLabel")
		title.add_theme_color_override("font_color", UiScreenKit.accent(self))
		col.add_child(title)
		if not produces.is_empty():
			UiFmCardView.chips(col, "Builds", produces, open_card)
		if not unlocks.is_empty():
			UiFmCardView.chips(col, "Unlocks", unlocks, open_card)
		grid.add_child(cell)


# ---------------------------------------------------------------------------------------------------------------- compare

func _render_compare() -> void:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiMetrics.SP_3)
	head.add_child(UiScreenKit.label("COMPARE", &"CaptionLabel"))
	var a_label: Label = UiScreenKit.label(_roster_title(model.roster), &"NameLabel")
	a_label.add_theme_color_override("font_color", UiScreenKit.accent(self))
	head.add_child(a_label)
	head.add_child(UiScreenKit.label("against", &"DimLabel"))
	_cmp_faction = OptionButton.new()
	_cmp_faction.custom_minimum_size = Vector2(250.0, 38.0)
	for f: DefFaction in data.factions:
		_cmp_faction.add_item(f.ui_name)
	_cmp_sub = OptionButton.new()
	_cmp_sub.custom_minimum_size = Vector2(200.0, 38.0)
	var start: DefRoster = compare_roster if compare_roster != null else _default_compare()
	compare_roster = start
	_cmp_faction.select(start.faction)
	_fill_subs(_cmp_sub, start.faction, start)
	_cmp_faction.item_selected.connect(func(i: int) -> void:
		compare_roster = data.vanilla_roster_of(i)
		_render_detail())
	_cmp_sub.item_selected.connect(func(i: int) -> void:
		compare_roster = data.rosters[int(_cmp_sub.get_item_metadata(i))]
		_render_detail())
	head.add_child(_cmp_faction)
	head.add_child(_cmp_sub)
	_detail_box.add_child(head)
	if compare_roster == model.roster:
		_detail_box.add_child(UiScreenKit.label("Pick another roster to compare with.", &"DimLabel"))
		return
	var cmp: Dictionary = model.compare(compare_roster)
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", UiMetrics.SP_4)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(cols)
	_compare_column(cols, "Only in %s" % _short(model.roster), cmp["only_a"] as Array, model.roster)
	_compare_column(cols, "Only in %s" % _short(compare_roster), cmp["only_b"] as Array, compare_roster)
	_replaced_column(cols, cmp["replaced"] as Array)
	_modifier_column(cols, cmp["modifier_diffs"] as Array)
	_compare_matrix(cmp["units"] as Array)


func _default_compare() -> DefRoster:
	var f: DefFaction = data.factions[model.roster.faction]
	for ri: int in f.sub_rosters:
		if data.rosters[ri] != model.roster:
			return data.rosters[ri]
	return data.rosters[f.vanilla_roster] if data.rosters[f.vanilla_roster] != model.roster else data.rosters[f.sub_rosters[0]]


func _short(r: DefRoster) -> String:
	return "Vanilla" if r.is_vanilla else UiFmModel.roster_sub_name(r.id)


func _roster_title(r: DefRoster) -> String:
	return "%s %s" % [data.factions[r.faction].code, _short(r)]


func _column(title: String) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(150.0, 0.0)
	v.add_theme_constant_override("separation", 4)
	var hdr: Label = UiScreenKit.label(title.to_upper(), &"CaptionLabel")
	hdr.add_theme_color_override("font_color", UiScreenKit.accent(self))
	v.add_child(hdr)
	var rule: ColorRect = ColorRect.new()
	rule.color = UiPalette.LINE_DIM
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	v.add_child(rule)
	return v


func _compare_column(parent: Control, title: String, refs: Array, owner_roster: DefRoster) -> void:
	var v: VBoxContainer = _column(title)
	if refs.is_empty():
		v.add_child(UiScreenKit.label("Nothing", &"DimLabel"))
	var nav: Callable = func(kind: int, idx: int) -> void:
		if owner_roster != model.roster:
			set_roster(owner_roster)
		open_card(kind, idx)
	for r: Variant in refs:
		var d: Dictionary = (r as Dictionary).duplicate()
		d["in_roster"] = true
		var b: Button = UiFmCardView.chip(d, nav)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	parent.add_child(v)


func _replaced_column(parent: Control, rows: Array) -> void:
	var v: VBoxContainer = _column("Replaced")
	if rows.is_empty():
		v.add_child(UiScreenKit.label("Nothing", &"DimLabel"))
	for r: Variant in rows:
		var d: Dictionary = r as Dictionary
		var t: Label = UiScreenKit.label("%s  →  %s" % [(d["a"] as Dictionary)["name"], (d["b"] as Dictionary)["name"]], &"", true)
		t.tooltip_text = "Baseline: %s" % (d["baseline"] as Dictionary)["name"]
		t.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(t)
	parent.add_child(v)


func _modifier_column(parent: Control, rows: Array) -> void:
	var v: VBoxContainer = _column("Modifier differences")
	if rows.is_empty():
		v.add_child(UiScreenKit.label("None", &"DimLabel"))
	for r: Variant in rows:
		var d: Dictionary = r as Dictionary
		var side: String = _short(model.roster) if str(d["side"]) == "a" else _short(compare_roster)
		var l: Label = UiScreenKit.label("%s: %s" % [side, d["text"]], &"", true)
		l.add_theme_font_size_override("font_size", 14)
		v.add_child(l)
	parent.add_child(v)


func _compare_matrix(rows: Array) -> void:
	var body: VBoxContainer = UiFmCardView.section(_detail_box, "Unit comparison")
	var keys: Array[String] = ["Cost", "Build time", "Health", "Speed", "DPS", "Range"]
	var g: GridContainer = GridContainer.new()
	g.columns = keys.size() + 1
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(UiScreenKit.label("UNIT", &"CaptionLabel"))
	for k: String in keys:
		var hl: Label = UiScreenKit.label(k.to_upper(), &"CaptionLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the stat columns share the page width instead of hugging the unit names
		g.add_child(hl)
	for row: Variant in rows:
		var d: Dictionary = row as Dictionary
		var a: Dictionary = d["a"] as Dictionary
		var b: Dictionary = d["b"] as Dictionary
		var name_text: String = str(a["name"]) if not a.is_empty() else "-"
		if not b.is_empty() and (a.is_empty() or a["index"] != b["index"]):
			name_text += "  →  " + str(b["name"])
		var nb: Button = Button.new()
		nb.text = name_text
		nb.flat = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.clip_text = true
		nb.custom_minimum_size = Vector2(330.0, 30.0)
		var base_idx: int = int((d["baseline"] as Dictionary)["index"])
		nb.pressed.connect(func() -> void:
			_cmp_unit = base_idx
			_render_detail())
		g.add_child(nb)
		var stat_rows: Array = d["rows"] as Array
		for k2: String in keys:
			var found: Dictionary = {}
			for sr: Variant in stat_rows:
				if str((sr as Dictionary)["label"]) == k2:
					found = sr as Dictionary
			var cell: Control = _matrix_cell(found)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(cell)
	body.add_child(g)
	if _cmp_unit >= 0:
		_compare_detail()


func _compare_detail() -> void:
	var stat_rows: Array[Dictionary] = model.compare_unit(_cmp_unit, compare_roster)
	if stat_rows.is_empty():
		return
	var title: String = data.units[_cmp_unit].ui_name
	var body: VBoxContainer = UiFmCardView.section(_detail_box, "%s: %s vs %s" % [title, _short(model.roster), _short(compare_roster)])
	var g: GridContainer = GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 4)
	for h: String in ["STAT", _short(model.roster).to_upper(), _short(compare_roster).to_upper(), "CHANGE"]:
		g.add_child(UiScreenKit.label(h, &"CaptionLabel"))
	for s: Dictionary in stat_rows:
		g.add_child(UiScreenKit.label(str(s["label"]), &"DimLabel"))
		g.add_child(_num_label(str(s["a_text"]), UiPalette.TEXT))
		g.add_child(_num_label(str(s["b_text"]), UiPalette.TEXT))
		var d_bp: int = int(s["delta_bp"])
		var tone: String = str(s["tone"])
		g.add_child(_num_label(UiFmText.delta_text(d_bp) if d_bp != 0 else "same", UiPalette.semantic(&"ok") if tone == "good" else (UiPalette.semantic(&"danger") if tone == "bad" else UiPalette.TEXT_MUTE)))
	body.add_child(g)


func _num_label(text: String, col: Color) -> Label:
	var l: Label = UiScreenKit.label(text)
	l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	l.add_theme_color_override("font_color", col)
	return l


func _matrix_cell(s: Dictionary) -> Control:
	if s.is_empty():
		return UiScreenKit.label("-", &"DimLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	var same: bool = str(s["a_text"]) == str(s["b_text"])
	var text: String = str(s["a_text"]) if same else "%s → %s" % [s["a_text"], s["b_text"]]
	var l: Label = UiScreenKit.label(text, &"", false, HORIZONTAL_ALIGNMENT_RIGHT)
	l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	l.add_theme_font_size_override("font_size", 14)
	if same:
		l.add_theme_color_override("font_color", UiPalette.TEXT_MUTE)
	else:
		l.add_theme_color_override("font_color", UiPalette.semantic(&"ok") if str(s["tone"]) == "good" else (UiPalette.semantic(&"danger") if str(s["tone"]) == "bad" else UiPalette.TEXT))
		l.tooltip_text = "%s: %s → %s (%s)" % [s["label"], s["a_text"], s["b_text"], UiFmText.delta_text(int(s["delta_bp"])) if int(s["delta_bp"]) != 0 else "different"]
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l
