class_name UiScreenCampaign
extends UiScreen
## The campaign screen (MIS2): the theatre map with the tutorial "Field Training" and the faction Operations (`UiCampaignMap`), and a
## detail panel for the selected mission: emblem, title, the briefing teaser, objectives count, state, best time and difficulty. A
## double click on a card (or the BRIEFING button) opens the mission briefing; a locked mission explains how to unlock it. Escape
## and BACK return to the main menu. The data comes from `UiCampaignModel` over `AppState.profile.campaign`.
## Params: `{select: mission id}` (preselect, e.g. coming back from the briefing), `{error: String}` (a mission that could not start).

var model: UiCampaignModel = null
var map: UiCampaignMap = null
var selected_id: String = ""

var _data: GameData = null
var _campaign: AppCampaign = null
var _detail: PanelContainer = null
var _d_badge: UiFactionBadge = null
var _d_group: Label = null
var _d_title: Label = null
var _d_faction: Label = null
var _d_teaser: Label = null
var _d_rows: VBoxContainer = null
var _d_obj: VBoxContainer = null
var _d_note: Label = null
var _brief: Button = null
var _back: Button = null
var _progress: Label = null


func _init() -> void:
	super._init()
	screen_id = &"campaign"


func enter(params: Dictionary) -> void:
	var state: Node = get_tree().root.get_node_or_null("AppState")
	_data = state.get("data") as GameData if state != null else null
	if state != null and state.get("match_ctx") is AppMatchContext:
		(state.get("match_ctx") as AppMatchContext).dispose()  # coming back from a mission
		state.set("match_ctx", null)
	_campaign = (state.get("profile") as AppProfile).campaign if state != null and state.get("profile") is AppProfile else AppCampaign.new()
	model = UiCampaignModel.build(_data, _campaign)
	UiThemeService.rebuild(UiSkinSet.shared().neutral_skin())
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	map.setup(model)
	var want: String = str(params.get("select", ""))
	if want == "" or model.entry(want) == null:
		want = model.recommended()
	if want == "" and model.count() > 0:
		want = model.entries[0].id
	if want != "":
		map.select(want)
	_update_detail()
	setup_menu_focus()
	if str(params.get("error", "")) != "":
		UiDlgMessage.open("Mission could not start", str(params["error"]))


func exit() -> void:
	pass


func default_focus() -> Control:
	return map.focus_card() if map != null else null


func on_escape() -> bool:
	return false


# ---------------------------------------------------------------- construction

func _build() -> void:
	var acc: Color = UiScreenKit.accent(self)
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.8, 0.05, 0.0, 0.02, acc))
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	UiLayerRoot.fill(margin)
	margin.add_theme_constant_override("margin_left", int(UiMetrics.SCREEN_MARGIN.x))
	margin.add_theme_constant_override("margin_top", int(UiMetrics.SCREEN_MARGIN.y))
	margin.add_theme_constant_override("margin_right", int(UiMetrics.SCREEN_MARGIN.z))
	margin.add_theme_constant_override("margin_bottom", int(UiMetrics.SCREEN_MARGIN.w))
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", UiMetrics.SP_3)
	margin.add_child(page)
	page.add_child(_header(acc))
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiMetrics.SP_5)
	page.add_child(body)
	map = UiCampaignMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(640.0, 420.0)
	map.mission_selected.connect(_on_selected)
	map.mission_activated.connect(func(id: String) -> void: _open_briefing(id))
	body.add_child(map)
	_build_detail()
	body.add_child(_detail)
	page.add_child(_footer())


func _header(acc: Color) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_6)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(UiScreenKit.wordmark("CAMPAIGN", 72, 850, 10, UiPalette.TEXT))
	var line: Label = UiScreenKit.label("FIELD TRAINING  //  EIGHT OPERATIONS  //  2086", &"HeaderLabel")
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", acc)
	box.add_child(line)
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = &"InsetPanel"
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_progress = UiScreenKit.label("", &"CaptionLabel")
	chip.add_child(_progress)
	row.add_child(chip)
	return row


func _build_detail() -> void:
	var made: Dictionary = UiScreenKit.panel("Mission", "", &"", 14, 10)
	_detail = made["panel"] as PanelContainer
	_detail.custom_minimum_size = Vector2(500.0, 0.0)
	var v: VBoxContainer = made["body"] as VBoxContainer
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	v.add_child(top)
	_d_badge = UiFactionBadge.new("", 88.0)
	_d_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_d_badge)
	var names: VBoxContainer = VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_d_group = UiScreenKit.label("", &"CaptionLabel")
	names.add_child(_d_group)
	_d_title = UiScreenKit.label("", &"HeaderLabel", true)
	_d_title.add_theme_font_size_override("font_size", 26)
	names.add_child(_d_title)
	_d_faction = UiScreenKit.label("", &"SubLabel", true)
	names.add_child(_d_faction)
	v.add_child(UiScreenKit.spacer(2.0))
	_d_teaser = UiScreenKit.label("", &"", true)
	_d_teaser.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_d_teaser.add_theme_font_size_override("font_size", 17)
	v.add_child(_d_teaser)
	v.add_child(UiScreenKit.spacer(4.0))
	v.add_child(UiPanelHeader.new("Objectives", ""))
	_d_obj = VBoxContainer.new()
	_d_obj.add_theme_constant_override("separation", 6)
	v.add_child(_d_obj)
	v.add_child(UiScreenKit.spacer(4.0))
	_d_rows = VBoxContainer.new()
	_d_rows.add_theme_constant_override("separation", 6)
	v.add_child(_d_rows)
	v.add_child(UiScreenKit.spacer(0.0, true))
	_d_note = UiScreenKit.label("", &"CaptionLabel", true)
	v.add_child(_d_note)
	_brief = UiScreenKit.button("BRIEFING", &"PrimaryButton", Vector2(0.0, 52.0))
	_brief.pressed.connect(func() -> void: _open_briefing(selected_id))
	v.add_child(_brief)


func _footer() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	_back = UiScreenKit.button("MAIN MENU", &"", Vector2(220.0, 52.0))
	_back.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(_back)
	row.add_child(UiScreenKit.spacer(0.0, true))
	var hint: Label = UiScreenKit.label("Double click a mission or press Enter for its briefing.", &"DimLabel")
	row.add_child(hint)
	return row


# ---------------------------------------------------------------- selection

func _on_selected(id: String) -> void:
	selected_id = id
	_update_detail()


func _update_detail() -> void:
	_progress.text = "%d / %d MISSIONS COMPLETE" % [model.completed_count(), model.count()]
	var e: UiCampaignModel.Entry = model.entry(selected_id)
	if e == null:
		return
	var acc: Color = UiSkinSet.shared().skin_for(e.faction_code).accent
	_d_badge.faction_code = e.faction_code
	_d_badge.muted = e.state == UiCampaignModel.State.LOCKED
	_d_group.text = UiCampaignModel.group_label(e.group, e.order)
	_d_group.add_theme_color_override("font_color", acc)
	_d_title.text = e.title
	_d_faction.text = e.faction_name.to_upper() if e.faction_name != "" else "ALL FACTIONS"
	_d_teaser.text = e.teaser
	for c: Node in _d_rows.get_children():
		_d_rows.remove_child(c)
		c.queue_free()
	for c2: Node in _d_obj.get_children():
		_d_obj.remove_child(c2)
		c2.queue_free()
	_fill_objectives(e, acc)
	match e.state:
		UiCampaignModel.State.LOCKED:
			_add_row("STATUS", "Locked", UiPalette.TEXT_DISABLED)
		UiCampaignModel.State.COMPLETED:
			_add_row("STATUS", "Completed", UiPalette.semantic(&"ok"))
			_add_row("BEST TIME", UiFormatLite.clock(e.best_ticks * SimConfig.TICK_MS / 1000) if e.best_ticks > 0 else "-", UiPalette.TEXT)
			_add_row("HIGHEST DIFFICULTY", AppMission.difficulty_name(e.best_difficulty), UiPalette.TEXT)
		_:
			_add_row("STATUS", "Ready", acc)
			var plays: int = _campaign.plays(e.id)
			if plays > 0:
				_add_row("ATTEMPTS", str(plays), UiPalette.TEXT)
	_d_note.text = model.lock_reason(e.id)
	_d_note.visible = _d_note.text != ""
	_brief.disabled = e.state == UiCampaignModel.State.LOCKED
	_brief.text = "BRIEFING" if e.state != UiCampaignModel.State.COMPLETED else "BRIEFING  //  REPLAY MISSION"


func _fill_objectives(e: UiCampaignModel.Entry, acc: Color) -> void:
	var def: DefMission = AppMission.def_of(_data, e.id)
	if def == null:
		return
	for pass_idx: int in 2:
		for o: DefMissionObjective in def.objectives:
			var primary: bool = o.kind == DefMissionObjective.Kind.PRIMARY
			if o.kind == DefMissionObjective.Kind.HIDDEN or o.initial == 0 or primary != (pass_idx == 0):
				continue
			var h: HBoxContainer = HBoxContainer.new()
			h.add_theme_constant_override("separation", 10)
			var tag: Label = UiScreenKit.label("PRIMARY" if primary else "OPTIONAL", &"CaptionLabel")
			tag.custom_minimum_size = Vector2(78.0, 0.0)
			tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			tag.add_theme_color_override("font_color", acc if primary else UiPalette.TEXT_MUTE)
			h.add_child(tag)
			var t: Label = UiScreenKit.label(o.ui_text, &"", true)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(t)
			_d_obj.add_child(h)
	if _d_obj.get_child_count() == 0:
		_d_obj.add_child(UiScreenKit.label("Revealed during the mission.", &"DimLabel"))


func _add_row(key: String, value: String, col: Color) -> void:
	var h: HBoxContainer = HBoxContainer.new()
	var k: Label = UiScreenKit.label(key, &"CaptionLabel")
	k.custom_minimum_size = Vector2(190.0, 0.0)
	h.add_child(k)
	var v: Label = UiScreenKit.label(value, &"NameLabel")
	v.add_theme_color_override("font_color", col)
	h.add_child(v)
	_d_rows.add_child(h)


func _open_briefing(id: String) -> void:
	var e: UiCampaignModel.Entry = model.entry(id)
	if e == null or e.state == UiCampaignModel.State.LOCKED:
		return
	navigate.emit(&"mission_briefing", {"mission": id})
