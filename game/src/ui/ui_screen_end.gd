class_name UiScreenEnd
extends UiScreen
## The end screen (ui.md 5.16.4): the result banner (VICTORY / DEFEAT / DRAW / MATCH ENDED), the match line (map, duration, seed) and
## four tabs over the summary model `UiMatchStats.build` made: Summary (per player: colour bar, emblem, name, roster, team, result,
## score, time alive), Military (units and structures built / lost / destroyed, damage), Economy (harvested, spent, peak, research,
## APM) and Graphs (lines per player, switchable metric). Buttons: Play again (back to the skirmish lobby) and Main menu. Params:
## `{summary: Dictionary}` (default: the summary of `AppState.match_ctx`). Replay buttons join when the replay pipeline (NET-8) exists.

const TABS: Array[Dictionary] = [
	{"id": &"summary", "text": "Summary"}, {"id": &"military", "text": "Military"}, {"id": &"economy", "text": "Economy"},
	{"id": &"graphs", "text": "Graphs"},
]
const METRICS: Array[Array] = [["harvested", "Credits harvested"], ["spent", "Credits spent"], ["army", "Army size"], ["kills", "Kills"]]
const ROW_H: float = 54.0
const ROW_PAD: int = 10
const ELIM_TEXT: PackedStringArray = ["Survived", "Defeated", "Surrendered", "Disconnected", "Removed", "Timed out", "Out of sync", "Defeated"]

var summary: Dictionary = {}
var tabs: UiTabBar = null
var _content: PanelContainer = null
var _graph: UiEndGraph = null
var _play_again: Button = null
var _main_menu: Button = null
var _save_replay: Button = null
var _watch_replay: Button = null
## The match context this screen was shown for (disposed when the screen goes; a replay started from here replaces `AppState.match_ctx`).
var _ctx: AppMatchContext = null
## LAN match: the first button is "BACK TO THE LOBBY" (the host sends everybody back; a client waits for the host).
var _lan: bool = false
var _waiting_host: bool = false
var _wait_label: Label = null


func _init() -> void:
	super._init()
	screen_id = &"end"
	handles_escape = false


func enter(params: Dictionary) -> void:
	summary = params.get("summary", {}) as Dictionary
	var state: Node = get_tree().root.get_node_or_null("AppState")
	_ctx = state.get("match_ctx") as AppMatchContext if state != null else null
	if summary.is_empty():
		summary = _ctx.summary() if _ctx != null else {}
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_local_skin()
	_build()
	select_tab(StringName(str(params.get("tab", "summary"))))
	setup_menu_focus()


func exit() -> void:
	# the finished session is not needed any more once the player leaves the results
	var state: Node = get_tree().root.get_node_or_null("AppState") if is_inside_tree() else null
	if _ctx != null:
		_ctx.dispose()
	if state != null and state.get("match_ctx") == _ctx:
		state.set("match_ctx", null)
	_ctx = null


func default_focus() -> Control:
	return _play_again


func on_escape() -> bool:
	return false


func can_leave() -> bool:
	return false


# ---------------------------------------------------------------- model helpers (pure, tested)

## Row text of the "Result" column for one player row of the summary.
static func result_text(row: Dictionary, winner_team: int, outcome_known: bool) -> String:
	if outcome_known and winner_team >= 0 and int(row["team"]) == winner_team:
		return "Winner"
	if bool(row.get("eliminated", false)):
		return ELIM_TEXT[clampi(int(row.get("elim_reason", 1)), 0, ELIM_TEXT.size() - 1)]
	return "Survived"


## "12:34" for a tick count.
static func clock_of(ticks: int) -> String:
	return UiFormatLite.clock(ticks * SimConfig.TICK_MS / 1000)


## The banner word and colour of a summary.
static func banner_of(sum: Dictionary) -> Array:
	return UiScreenGame.end_banner(int(sum.get("outcome", UiMatchStats.OUTCOME_OBSERVED)), int(sum.get("reason", 0)))


## Column specs `[title, width, align, key]` of a tab; `key` is read from the row's stats (or the row itself).
static func columns(tab: StringName) -> Array[Array]:
	match tab:
		&"military":
			return [["Units built", 110.0, 2, "units_built"], ["Units lost", 110.0, 2, "units_lost"], ["Units killed", 120.0, 2, "units_killed"],
				["Structures built", 140.0, 2, "structures_built"], ["Structures lost", 140.0, 2, "structures_lost"],
				["Structures destroyed", 170.0, 2, "structures_destroyed"], ["Damage dealt", 130.0, 2, "damage_dealt"], ["Damage taken", 130.0, 2, "damage_taken"]]
		&"economy":
			return [["Harvested", 130.0, 2, "harvested"], ["Spent", 130.0, 2, "spent"], ["Credits left", 130.0, 2, "credits"],
				["Peak units", 110.0, 2, "peak_units"], ["Research", 100.0, 2, "research_done"], ["Commands", 110.0, 2, "commands"], ["APM", 80.0, 2, "apm"]]
	return []


# ---------------------------------------------------------------- construction

func _apply_local_skin() -> void:
	for r: Variant in summary.get("players", []) as Array:
		var row: Dictionary = r as Dictionary
		if bool(row.get("is_local", false)):
			UiThemeService.rebuild(UiSkinSet.shared().skin_for(str(row.get("faction_code", "")).to_lower()))
			return


func _build() -> void:
	var look: Array = banner_of(summary)
	var col: Color = look[1] as Color
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
	page.add_theme_constant_override("separation", UiMetrics.SP_3)
	margin.add_child(page)
	page.add_child(_header(str(look[0]), col))
	tabs = UiTabBar.new()
	tabs.set_focusable(true)
	tabs.set_tabs(TABS.duplicate())
	tabs.tab_selected.connect(func(_i: int, id: StringName) -> void: select_tab(id))
	page.add_child(tabs)
	_content = PanelContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	page.add_child(_content)
	page.add_child(_buttons())


func _header(word: String, col: Color) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var big: Label = UiScreenKit.wordmark(word, 96, 850, 12, col)
	box.add_child(big)
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(summary.get("map_name", "")))
	parts.append(clock_of(int(summary.get("duration_ticks", 0))))
	parts.append("%d players" % (summary.get("players", []) as Array).size())
	if int(summary.get("map_seed", 0)) != 0:
		parts.append("seed %s" % UiFormatLite.hash8(int(summary.get("map_seed", 0))))
	var line: Label = UiScreenKit.label("   /   ".join(parts).to_upper(), &"HeaderLabel")
	line.add_theme_font_size_override("font_size", 18)
	box.add_child(line)
	return box


func _buttons() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	row.add_child(UiScreenKit.spacer(0.0, true))
	_lan = AppLan.is_lan_match()
	_wait_label = UiScreenKit.label("Waiting for the host to return to the lobby...", &"DimLabel")
	_wait_label.visible = false
	row.add_child(_wait_label)
	_save_replay = UiScreenKit.button("SAVE REPLAY", &"", Vector2(220.0, 52.0))
	_save_replay.pressed.connect(_on_save_replay)
	_save_replay.disabled = not bool(summary.get("can_save_replay", false))
	_save_replay.tooltip_text = "Keep this match under a name of your own." if not _save_replay.disabled else "This match was not recorded."
	row.add_child(_save_replay)
	_watch_replay = UiScreenKit.button("WATCH REPLAY", &"", Vector2(220.0, 52.0))
	_watch_replay.pressed.connect(_on_watch_replay)
	var rp: String = str(summary.get("replay_path", ""))
	_watch_replay.disabled = rp == "" or not FileAccess.file_exists(rp) or _lan
	_watch_replay.tooltip_text = "Watch the match again from any angle." if not _watch_replay.disabled else \
		("Leave the LAN lobby first, then watch it under Replays." if _lan else "This match was not recorded.")
	row.add_child(_watch_replay)
	_play_again = UiScreenKit.button("BACK TO THE LOBBY" if _lan else "PLAY AGAIN", &"PrimaryButton", Vector2(220.0, 52.0))
	_play_again.pressed.connect(_on_play_again)
	row.add_child(_play_again)
	_main_menu = UiScreenKit.button("MAIN MENU", &"", Vector2(220.0, 52.0))
	_main_menu.pressed.connect(_on_main_menu)
	row.add_child(_main_menu)
	return row


## SAVE REPLAY: asks for a name and keeps a copy of the recording next to the automatic ones.
func _on_save_replay() -> void:
	var session: NetSession = _ctx.session if _ctx != null else null
	var cfg: Dictionary = _ctx.config if _ctx != null else {}
	UiDlgReplayName.ask("Save replay", AppReplay.default_name(cfg), "Save", func(chosen: String) -> void:
		var path: String = AppReplay.save_session(session, chosen)
		var scenes: Node = get_tree().root.get_node_or_null("AppScenes") if is_inside_tree() else null
		if scenes != null:
			scenes.call("toast", ("Replay saved as %s." % path.get_file()) if path != "" else "The replay could not be saved: %s" % AppReplay.last_error, 0 if path != "" else 2)
		if path != "":
			_save_replay.disabled = true
			_save_replay.text = "REPLAY SAVED")


## WATCH REPLAY: plays the recording of this match back in the observer HUD (loading screen, then the replay screen).
func _on_watch_replay() -> void:
	var rp: String = str(summary.get("replay_path", ""))
	if rp == "":
		return
	var rctx: AppMatchContext = AppReplay.start(rp, {"title": "Replay"})
	if rctx == null:
		UiDlgMessage.open("Replay", "The replay cannot be played: %s" % AppReplay.last_error)
		return
	navigate.emit(&"loading", {"kind": "replay", "title": "Replay"})


func _on_play_again() -> void:
	if not _lan:
		navigate.emit(&"lobby", {"role": "local"})
		return
	if AppLan.return_to_lobby():
		navigate.emit(&"lobby", {"lan": true})
		return
	# a client: the host has not sent the lobby yet; the screen keeps polling
	_waiting_host = true
	_wait_label.visible = true
	_play_again.disabled = true
	set_process(true)


func _on_main_menu() -> void:
	if _lan:
		AppLan.leave()  # a client sends LEAVE, the host closes the game for everybody
	navigate.emit(&"main_menu", {})


func _process(_delta: float) -> void:
	if not _waiting_host:
		set_process(false)
		return
	if AppLan.return_to_lobby():
		_waiting_host = false
		navigate.emit(&"lobby", {"lan": true})
	elif AppLan.current_session() == null or AppLan.current_session().phase == NetSession.Phase.DISCONNECTED or AppLan.current_session().phase == NetSession.Phase.IDLE:
		# the host left or the connection dropped while waiting
		_waiting_host = false
		_wait_label.text = "The host closed the game."
		_play_again.disabled = true
		set_process(false)


# ---------------------------------------------------------------- tabs

func select_tab(id: StringName) -> void:
	if _content == null:
		return
	tabs.select_id(id)
	for c: Node in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_graph = null
	var body: Control
	match id:
		&"military", &"economy":
			body = _table(id)
		&"graphs":
			body = _graphs()
		_:
			body = _summary_table()
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	pad.add_child(body)
	_content.add_child(pad)


func current_tab() -> StringName:
	return tabs.selected_id() if tabs != null else &""


## The per-player rows, the local player first? No: the config order (pid), which is the lobby order.
func _rows() -> Array:
	return summary.get("players", []) as Array


## A column: `min` width, `ratio` > 0 makes it stretch, `align` 0 left / 1 centre / 2 right.
static func _col(min_w: float, ratio: float = 0.0, align: int = 0) -> Dictionary:
	return {"min": min_w, "ratio": ratio, "align": align}


func _summary_table() -> Control:
	var winner: int = int(summary.get("winner_team", -1))
	var known: bool = int(summary.get("outcome", 3)) != UiMatchStats.OUTCOME_OBSERVED or winner >= 0
	var cols: Array[Dictionary] = [_col(10.0), _col(44.0), _col(240.0, 3.0), _col(220.0, 3.0), _col(60.0, 0.0, 1), _col(150.0, 1.5),
		_col(360.0, 4.0, 2), _col(110.0, 0.0, 2)]
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.add_child(_head_row(cols, ["", "", "Player", "Roster", "Team", "Result", "Score", "Time alive"]))
	var top: int = 1
	for r0: Variant in _rows():
		top = maxi(top, int((r0 as Dictionary)["score"]))
	for r: Variant in _rows():
		var row: Dictionary = r as Dictionary
		var res: String = result_text(row, winner, known)
		var cells: Array = [_swatch(int(row["color"])), _emblem(row), _name_cell(row), _txt(_roster_name(row), &"DimLabel"),
			_txt(_team_text(row), &"", 1), _txt(res, &"OkLabel" if res == "Winner" else &""),
			_score_cell(int(row["score"]), top, int(row["color"])), _txt(clock_of(int(row["alive_ticks"])), &"", 2)]
		list.add_child(_data_row(cols, cells, bool(row.get("is_local", false))))
	list.add_child(UiScreenKit.spacer(10.0))
	list.add_child(UiPanelHeader.new("Credits harvested over time"))
	var graph: UiEndGraph = _new_graph("harvested")
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(graph)
	list.add_child(_legend())
	return list


func _new_graph(metric: String) -> UiEndGraph:
	var g: UiEndGraph = UiEndGraph.new()
	var colors: Dictionary = {}
	for r: Variant in _rows():
		colors[int((r as Dictionary)["pid"])] = UiPalette.team(int((r as Dictionary)["color"]))
	g.metric = metric
	g.set_data(summary.get("series", {}) as Dictionary, colors)
	return g


func _table(tab: StringName) -> Control:
	var spec: Array[Array] = columns(tab)
	var cols: Array[Dictionary] = [_col(10.0), _col(44.0), _col(260.0, 3.0)]
	var titles: Array = ["", "", "Player"]
	for c: Array in spec:
		cols.append(_col(float(c[1]), 1.0, 2))
		titles.append(str(c[0]))
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.add_child(_head_row(cols, titles))
	for r: Variant in _rows():
		var row: Dictionary = r as Dictionary
		var st: Dictionary = row["stats"] as Dictionary
		var cells: Array = [_swatch(int(row["color"])), _emblem(row), _name_cell(row)]
		for c2: Array in spec:
			var key: String = str(c2[3])
			var v: int = int(st[key]) if st.has(key) else int(row.get(key, 0))
			cells.append(_txt(UiFormatLite.credits(v) if v >= 0 else "-", &"", 2))
		list.add_child(_data_row(cols, cells, bool(row.get("is_local", false))))
	list.add_child(UiScreenKit.spacer(10.0))
	var military: bool = tab == &"military"
	list.add_child(UiPanelHeader.new("Army size over time" if military else "Credits spent over time"))
	var graph: UiEndGraph = _new_graph("army" if military else "spent")
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(graph)
	list.add_child(_legend())
	if not military:
		list.add_child(UiScreenKit.label("Harvested includes salvage. Commands are the accepted orders; APM = commands per minute of match time.", &"DimLabel", true))
	return list


func _graphs() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", UiMetrics.SP_2)
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", UiMetrics.SP_2)
	box.add_child(chips)
	_graph = _new_graph("harvested")
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var group: ButtonGroup = ButtonGroup.new()
	for m: Array in METRICS:
		var b: Button = UiScreenKit.button(str(m[1]), &"TabButton", Vector2(0.0, 34.0))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(m[0]) == _graph.metric
		b.pressed.connect(func() -> void: _graph.metric = str(m[0]))
		chips.add_child(b)
	box.add_child(_graph)
	box.add_child(_legend())
	return box


func _legend() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	for r: Variant in _rows():
		var d: Dictionary = r as Dictionary
		var sw: ColorRect = ColorRect.new()
		sw.color = UiPalette.team(int(d["color"]))
		sw.custom_minimum_size = Vector2(14.0, 14.0)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		row.add_child(UiScreenKit.label("%s  %s" % [_pip_name(int(d["pid"])), str(d["name"])], &"DimLabel"))
	return row


static func _pip_name(pid: int) -> String:
	return ["o", "[]", "^", "<>"][pid % 4]


# ---------------------------------------------------------------- row builders

func _head_row(cols: Array[Dictionary], titles: Array) -> Control:
	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override("margin_left", ROW_PAD)
	pad.add_theme_constant_override("margin_right", ROW_PAD)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	pad.add_child(row)
	for i: int in cols.size():
		var l: Label = UiScreenKit.label(str(titles[i]).to_upper(), &"DimLabel", false, _align(int(cols[i]["align"])), true)
		_size_cell(l, cols[i])
		l.add_theme_font_size_override("font_size", 13)
		row.add_child(l)
	return pad


func _data_row(cols: Array[Dictionary], cells: Array, local: bool) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, ROW_H)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(UiScreenKit.accent(self), 0.16) if local else UiPalette.BG_RAISED
	sb.border_color = UiScreenKit.accent(self) if local else UiPalette.LINE_DIM
	sb.border_width_left = 3 if local else 1
	sb.border_width_bottom = 1
	sb.content_margin_left = ROW_PAD
	sb.content_margin_right = ROW_PAD
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_3)
	panel.add_child(row)
	for i: int in cells.size():
		var c: Control = cells[i] as Control
		_size_cell(c, cols[i])
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	return panel


static func _size_cell(c: Control, col: Dictionary) -> void:
	c.custom_minimum_size = Vector2(float(col["min"]), c.custom_minimum_size.y)
	if float(col["ratio"]) > 0.0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = float(col["ratio"])


## Score number with a bar in the team colour, scaled to the best score.
func _score_cell(score: int, top: int, color_id: int) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", UiMetrics.SP_3)
	var track: Control = Control.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.custom_minimum_size = Vector2(80.0, 12.0)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frac: float = clampf(float(maxi(score, 0)) / float(maxi(top, 1)), 0.0, 1.0)
	track.draw.connect(func() -> void:
		track.draw_rect(Rect2(Vector2.ZERO, track.size), UiPalette.BG_DEEP)
		track.draw_rect(Rect2(Vector2.ZERO, Vector2(track.size.x * frac, track.size.y)), UiPalette.team(color_id)))
	box.add_child(track)
	var num: Label = UiScreenKit.label(UiFormatLite.credits(score), &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	num.custom_minimum_size = Vector2(86.0, 0.0)
	num.add_theme_font_size_override("font_size", 20)
	box.add_child(num)
	return box


func _swatch(color_id: int) -> Control:
	var r: ColorRect = ColorRect.new()
	r.color = UiPalette.team(color_id)
	r.custom_minimum_size = Vector2(10.0, 28.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _emblem(row: Dictionary) -> Control:
	return UiFactionBadge.new(str(row.get("faction_code", "")), 38.0)


func _name_cell(row: Dictionary) -> Control:
	var suffix: String = ""
	if bool(row.get("is_ai", false)):
		suffix = "  [%s AI]" % AppMatch.AI_LEVEL_NAMES[clampi(int(row.get("ai_level", 1)), 0, AppMatch.AI_LEVEL_NAMES.size() - 1)]
	elif bool(row.get("is_local", false)):
		suffix = "  (you)"
	var l: Label = UiScreenKit.label(str(row["name"]) + suffix, &"", false, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_theme_font_size_override("font_size", 20)
	return l


func _txt(text: String, variation: StringName = &"", align: int = 0) -> Label:
	var l: Label = UiScreenKit.label(text, variation, false, _align(align), true)
	if variation == &"":
		l.add_theme_font_size_override("font_size", 18)
	return l


static func _align(a: int) -> HorizontalAlignment:
	return [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][clampi(a, 0, 2)] as HorizontalAlignment


func _team_text(row: Dictionary) -> String:
	var t: int = int(row["team"])
	return "-" if t > 4 else char(64 + t)


func _roster_name(row: Dictionary) -> String:
	var state: Node = get_tree().root.get_node_or_null("AppState") if is_inside_tree() else null
	var data: GameData = state.get("data") as GameData if state != null else null
	if data != null:
		var idx: int = data.roster_idx(str(row.get("roster_id", "")))
		if idx >= 0:
			var title: String = data.rosters[idx].ui_title
			var fac: int = data.rosters[idx].faction
			var code: String = data.factions[fac].code if fac >= 0 and fac < data.factions.size() else ""
			return "%s  %s" % [code, title] if title != "" else str(row["roster_id"])
	return str(row.get("roster_id", ""))
