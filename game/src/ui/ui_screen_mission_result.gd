class_name UiScreenMissionResult
extends UiScreen
## The result screen of a scripted mission (MIS2; the END_SCREEN of a mission): MISSION COMPLETE / MISSION FAILED, the objective list
## with its final states, the time against the best one, the difficulty, the debrief figures of the local player, and the buttons NEXT
## MISSION (after a win, when one is open), RETRY, WATCH REPLAY and CAMPAIGN. Params: `{mission: AppMission.result_model, summary:
## the match summary}`. Leaving the screen disposes the finished match.

var model: Dictionary = {}
var summary: Dictionary = {}

var _ctx: AppMatchContext = null
var _next: Button = null
var _retry: Button = null
var _watch: Button = null
var _campaign_btn: Button = null


func _init() -> void:
	super._init()
	screen_id = &"mission_result"
	handles_escape = false


func enter(params: Dictionary) -> void:
	model = params.get("mission", {}) as Dictionary
	summary = params.get("summary", {}) as Dictionary
	var state: Node = get_tree().root.get_node_or_null("AppState")
	_ctx = state.get("match_ctx") as AppMatchContext if state != null else null
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiThemeService.rebuild(UiSkinSet.shared().skin_for(str(model.get("faction_code", ""))))
	_build()
	setup_menu_focus()


func exit() -> void:
	var state: Node = get_tree().root.get_node_or_null("AppState") if is_inside_tree() else null
	if _ctx != null:
		_ctx.dispose()
	if state != null and state.get("match_ctx") == _ctx:
		state.set("match_ctx", null)
	_ctx = null


## NEXT MISSION after a win (CAMPAIGN when there is none), RETRY after a defeat.
func default_focus() -> Control:
	if _next != null and not _next.disabled:
		return _next
	return _campaign_btn if bool(model.get("won", false)) else _retry


func on_escape() -> bool:
	return false


func can_leave() -> bool:
	return false


# ---------------------------------------------------------------- model helpers (pure, tested)

static func headline(won: bool) -> String:
	return "MISSION COMPLETE" if won else "MISSION FAILED"


## "NEW BEST TIME", "FIRST CLEAR", "NEW HIGHEST DIFFICULTY" chips of the campaign outcome (in this order).
static func badges(outcome: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if bool(outcome.get("won", false)):
		if bool(outcome.get("first_clear", false)):
			out.append("FIRST CLEAR")
		if bool(outcome.get("new_best_time", false)) and not bool(outcome.get("first_clear", false)):
			out.append("NEW BEST TIME")
		if bool(outcome.get("new_best_difficulty", false)) and not bool(outcome.get("first_clear", false)):
			out.append("NEW HIGHEST DIFFICULTY")
	return out


## The debrief rows [label, value] of the local player's stats.
static func debrief_rows(stats: Dictionary) -> Array[Array]:
	var rows: Array[Array] = []
	if stats.is_empty():
		return rows
	rows.append(["ENEMY UNITS DESTROYED", UiFormatLite.credits(int(stats.get("units_killed", 0)))])
	rows.append(["UNITS LOST", UiFormatLite.credits(int(stats.get("units_lost", 0)))])
	rows.append(["ENEMY STRUCTURES DESTROYED", UiFormatLite.credits(int(stats.get("structures_destroyed", 0)))])
	rows.append(["STRUCTURES LOST", UiFormatLite.credits(int(stats.get("structures_lost", 0)))])
	rows.append(["CREDITS HARVESTED", UiFormatLite.credits(int(stats.get("harvested", 0)))])
	rows.append(["CREDITS SPENT", UiFormatLite.credits(int(stats.get("spent", 0)))])
	return rows


# ---------------------------------------------------------------- construction

func _build() -> void:
	var won: bool = bool(model.get("won", false))
	var col: Color = UiPalette.semantic(&"ok") if won else UiPalette.semantic(&"danger")
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.85, 0.06, 0.0, 0.03, col))
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	UiLayerRoot.fill(margin)
	margin.add_theme_constant_override("margin_left", int(UiMetrics.SCREEN_MARGIN.x))
	margin.add_theme_constant_override("margin_top", int(UiMetrics.SCREEN_MARGIN.y))
	margin.add_theme_constant_override("margin_right", int(UiMetrics.SCREEN_MARGIN.z))
	margin.add_theme_constant_override("margin_bottom", int(UiMetrics.SCREEN_MARGIN.w))
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", UiMetrics.SP_4)
	margin.add_child(page)
	page.add_child(_header(won, col))
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", UiMetrics.SP_5)
	page.add_child(body)
	body.add_child(_objectives_panel())
	body.add_child(_debrief_panel(col))
	page.add_child(UiScreenKit.spacer(0.0, true))
	page.add_child(_buttons())


func _header(won: bool, col: Color) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	var badge: UiFactionBadge = UiFactionBadge.new(str(model.get("faction_code", "")), 120.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	box.add_child(UiScreenKit.wordmark(headline(won), 96, 850, 12, col))
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(model.get("title", "")))
	parts.append(str(model.get("difficulty_name", "")))
	parts.append(str(model.get("clock", "0:00")))
	var line: Label = UiScreenKit.label("   /   ".join(parts).to_upper(), &"HeaderLabel")
	line.add_theme_font_size_override("font_size", 18)
	box.add_child(line)
	return row


func _objectives_panel() -> Control:
	var made: Dictionary = UiScreenKit.panel("Objectives", "", &"", 16, 10)
	var panel: PanelContainer = made["panel"] as PanelContainer
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v: VBoxContainer = made["body"] as VBoxContainer
	var rows: Array = model.get("objectives", []) as Array
	for pass_idx: int in 2:
		var first: bool = true
		for rv: Variant in rows:
			var r: Dictionary = rv as Dictionary
			var primary: bool = int(r["kind"]) == UiMissionModel.KIND_PRIMARY
			if primary != (pass_idx == 0):
				continue
			if first:
				first = false
				v.add_child(UiScreenKit.label("PRIMARY" if primary else "OPTIONAL", &"CaptionLabel"))
			v.add_child(_objective_row(r))
	if rows.is_empty():
		v.add_child(UiScreenKit.label("This mission has no listed objectives.", &"DimLabel"))
	return panel


func _objective_row(r: Dictionary) -> Control:
	var st: int = int(r["state"])
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var mark: UiObjectiveMark = UiObjectiveMark.new()
	mark.state = st
	mark.primary = int(r["kind"]) == UiMissionModel.KIND_PRIMARY
	h.add_child(mark)
	var t: Label = UiScreenKit.label(str(r["text"]), &"", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 18)
	h.add_child(t)
	var word: Label = UiScreenKit.label(str(r["word"]), &"CaptionLabel")
	var wc: Color = UiPalette.TEXT_MUTE
	if st == UiMissionModel.S_COMPLETED:
		wc = UiPalette.semantic(&"ok")
	elif st == UiMissionModel.S_FAILED:
		wc = UiPalette.semantic(&"danger")
	word.add_theme_color_override("font_color", wc)
	h.add_child(word)
	return h


func _debrief_panel(col: Color) -> Control:
	var made: Dictionary = UiScreenKit.panel("Debrief", "", &"", 16, 10)
	var panel: PanelContainer = made["panel"] as PanelContainer
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v: VBoxContainer = made["body"] as VBoxContainer
	var outcome: Dictionary = model.get("outcome", {}) as Dictionary
	_row(v, "MISSION TIME", str(model.get("clock", "0:00")), UiPalette.TEXT, true)
	var best: int = int(model.get("best_ticks", 0))
	if best > 0:
		_row(v, "BEST TIME", UiFormatLite.clock(best * SimConfig.TICK_MS / 1000), UiPalette.TEXT_DIM, false)
	_row(v, "DIFFICULTY", str(model.get("difficulty_name", "")), UiPalette.TEXT, false)
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	for b: String in badges(outcome):
		var chip: PanelContainer = PanelContainer.new()
		chip.theme_type_variation = &"InsetPanel"
		var l: Label = UiScreenKit.label(b, &"CaptionLabel")
		l.add_theme_color_override("font_color", col)
		chip.add_child(l)
		chips.add_child(chip)
	if chips.get_child_count() > 0:
		v.add_child(chips)
	v.add_child(UiScreenKit.spacer(8.0))
	for r: Array in debrief_rows(model.get("stats", {}) as Dictionary):
		_row(v, str(r[0]), str(r[1]), UiPalette.TEXT, false)
	return panel


func _row(v: VBoxContainer, key: String, value: String, vcol: Color, big: bool) -> void:
	var h: HBoxContainer = HBoxContainer.new()
	var k: Label = UiScreenKit.label(key, &"CaptionLabel")
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var l: Label = UiScreenKit.label(value, &"NameLabel")
	l.add_theme_color_override("font_color", vcol)
	if big:
		l.add_theme_font_size_override("font_size", 30)
	h.add_child(l)
	v.add_child(h)


func _buttons() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	row.add_child(UiScreenKit.spacer(0.0, true))
	_watch = UiScreenKit.button("WATCH REPLAY", &"", Vector2(220.0, 52.0))
	_watch.pressed.connect(_on_watch_replay)
	var rp: String = str(summary.get("replay_path", ""))
	_watch.disabled = rp == "" or not FileAccess.file_exists(rp)
	_watch.tooltip_text = "Watch the mission again from any angle." if not _watch.disabled else "This mission was not recorded."
	row.add_child(_watch)
	_retry = UiScreenKit.button("RETRY", &"" if bool(model.get("won", false)) else &"PrimaryButton", Vector2(220.0, 52.0))
	_retry.pressed.connect(retry)
	row.add_child(_retry)
	var next_id: String = str(model.get("next_id", ""))
	_next = UiScreenKit.button("NEXT MISSION", &"PrimaryButton", Vector2(240.0, 52.0))
	_next.disabled = next_id == ""
	_next.pressed.connect(next_mission)
	if next_id != "":
		_next.tooltip_text = next_title(next_id)
		row.add_child(_next)
	else:
		_next.queue_free()
		_next = null
	_campaign_btn = UiScreenKit.button("CAMPAIGN", &"", Vector2(220.0, 52.0))
	_campaign_btn.pressed.connect(back_to_campaign)
	row.add_child(_campaign_btn)
	return row


func next_title(next_id: String) -> String:
	var state: Node = get_tree().root.get_node_or_null("AppState") if is_inside_tree() else null
	var d: GameData = state.get("data") as GameData if state != null else null
	var def: DefMission = AppMission.def_of(d, next_id)
	return "Next: %s" % def.ui_title if def != null else ""


# ---------------------------------------------------------------- actions

func retry() -> void:
	var id: String = str(model.get("id", ""))
	var ctx: AppMatchContext = AppMission.start(id, int(model.get("difficulty", -1)), {})
	if ctx == null:
		UiDlgMessage.open("Mission could not start", NetSession.last_create_error if NetSession.last_create_error != "" else "The match could not be created.")
		return
	navigate.emit(&"loading", {"kind": "match", "title": str(model.get("title", "")), "mission": id})


func next_mission() -> void:
	var next_id: String = str(model.get("next_id", ""))
	if next_id != "":
		navigate.emit(&"mission_briefing", {"mission": next_id})


func back_to_campaign() -> void:
	navigate.emit(&"campaign", {"select": str(model.get("next_id", "")) if bool(model.get("won", false)) and str(model.get("next_id", "")) != "" else str(model.get("id", ""))})


func _on_watch_replay() -> void:
	var rp: String = str(summary.get("replay_path", ""))
	if rp == "":
		return
	var rctx: AppMatchContext = AppReplay.start(rp, {"title": "Replay"})
	if rctx == null:
		UiDlgMessage.open("Replay", "The replay cannot be played: %s" % AppReplay.last_error)
		return
	navigate.emit(&"loading", {"kind": "replay", "title": "Replay"})
