class_name UiScreenReplays
extends UiScreen
## The replay browser (ui.md 5.16.6, task REP2): every `*.mfreplay` of the replay folder as a sortable, filterable list (date, map,
## players with their colours, result, length, build compatibility), a detail pane with the map thumbnail (generated from the recorded
## seed and parameters), the rosters and colours, and the actions WATCH, VERIFY (a time-sliced headless re-simulation), SAVE AS /
## RENAME, DELETE and OPEN FOLDER. The list is `UiReplayModel`; metadata comes from `NetReplay.read_info` and is read progressively
## (the list shows at once, rows fill in as files are read). Params: `{dir: String, message: String, select: String (path)}`.

const READ_BUDGET_US: int = 4000
const THUMB_CACHE: int = 12

var dir: String = ""

var _data: GameData = null
var _local: Dictionary = {}
var _infos: Array[Dictionary] = []
var _pending: PackedStringArray = PackedStringArray()
var _rows: Array[Dictionary] = []
var _row_nodes: Array[UiListRow] = []
var _sort_col: int = UiReplayModel.Col.DATE
var _sort_desc: bool = true
var _sort_buttons: Array[Button] = []
var _widths: PackedFloat32Array = UiReplayModel.COLUMN_WIDTHS
var _scroll: ScrollContainer = null
var _selected_key: String = ""
var _dirty: bool = false
var _since_rebuild: float = 0.0

var _header: UiPanelHeader = null
var _filter: LineEdit = null
var _hide_auto: CheckBox = null
var _hide_bad: CheckBox = null
var _list_box: VBoxContainer = null
var _empty_note: Label = null
var _status: Label = null
var _preview: UiMapPreview = null
var _lines: Dictionary = {}
var _players_box: VBoxContainer = null
var _chips: HFlowContainer = null
var _banner: Label = null
var _watch: Button = null
var _verify: Button = null
var _rename: Button = null
var _delete: Button = null
var _verify_bar: ProgressBar = null
var _verify_label: Label = null

var _thumb_job: MapGenJob = null
var _thumb_key: String = ""
var _thumbs: Dictionary = {}
var _thumb_order: PackedStringArray = PackedStringArray()
var _verifier: NetReplayPlayer = null
var _verify_path: String = ""
var _verify_results: Dictionary = {}


func _init() -> void:
	super._init()
	screen_id = &"replays"


func enter(params: Dictionary) -> void:
	var app: Node = get_tree().root.get_node_or_null("AppState")
	_data = app.get("data") as GameData if app != null else null
	dir = str(params.get("dir", ""))
	if dir == "":
		dir = NetReplay.default_dir()
		if dir == "":
			dir = NetReplay.DEFAULT_DIR
	_local = AppReplay.local_versions()
	if app != null and app.get("match_ctx") is AppMatchContext:
		(app.get("match_ctx") as AppMatchContext).dispose()  # a finished playback is let go when its browser is shown again
		app.set("match_ctx", null)
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("clear_backdrop")
	_selected_key = str(params.get("select", ""))
	_build()
	scan()
	if str(params.get("message", "")) != "":
		_status.text = str(params["message"])
	set_process(true)
	setup_menu_focus()
	if bool(params.get("watch", false)):
		_watch_when_read.call_deferred()  # `--watch` (screenshots, tests): the first replay is opened as soon as the list is read


## Screenshots and tests: reads the folder, selects the newest replay and presses WATCH.
func _watch_when_read() -> void:
	read_all()
	_on_watch()


func exit() -> void:
	set_process(false)
	_cancel_thumb()
	_verifier = null


func default_focus() -> Control:
	return _filter


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_DELETE and is_visible_in_tree() and not selected_info().is_empty() \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		_on_delete()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)


func on_escape() -> bool:
	return false


# ---------------------------------------------------------------- construction

func _build() -> void:
	var acc: Color = UiScreenKit.accent(self)
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.8, 0.0, 0.0, 0.03, acc))
	var m: MarginContainer = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(UiMetrics.SCREEN_MARGIN.x))
	m.add_theme_constant_override("margin_top", int(UiMetrics.SCREEN_MARGIN.y))
	m.add_theme_constant_override("margin_right", int(UiMetrics.SCREEN_MARGIN.z))
	m.add_theme_constant_override("margin_bottom", int(UiMetrics.SCREEN_MARGIN.w))
	add_child(m)
	UiLayerRoot.fill(m)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)
	root.add_child(_title_bar())
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_list_panel())
	body.add_child(_detail_panel())
	root.add_child(_bottom_bar())


func _title_bar() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.add_child(UiScreenKit.wordmark("REPLAYS", 38, 800, 4, UiPalette.TEXT))
	v.add_child(UiScreenKit.label("EVERY MATCH IS RECORDED AUTOMATICALLY  //  WATCH IT AGAIN FROM ANY ANGLE", &"DimLabel"))
	return v


func _list_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Recorded matches", "", &"", 12, 8)
	var panel: PanelContainer = d["panel"] as PanelContainer
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_header = d["header"] as UiPanelHeader
	var box: VBoxContainer = d["body"] as VBoxContainer
	var f: HBoxContainer = HBoxContainer.new()
	f.add_theme_constant_override("separation", 14)
	box.add_child(f)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter by map, player or name"
	_filter.clear_button_enabled = true
	_filter.custom_minimum_size = Vector2(220.0, 36.0)
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	f.add_child(_filter)
	_hide_auto = CheckBox.new()
	_hide_auto.text = "Hide automatic"
	_hide_auto.toggled.connect(func(_on: bool) -> void: _rebuild())
	f.add_child(_hide_auto)
	_hide_bad = CheckBox.new()
	_hide_bad.text = "Hide old builds"
	_hide_bad.toggled.connect(func(_on: bool) -> void: _rebuild())
	f.add_child(_hide_bad)
	var heads: HBoxContainer = HBoxContainer.new()
	heads.add_theme_constant_override("separation", 0)
	heads.custom_minimum_size = Vector2(0.0, 34.0)
	box.add_child(heads)
	for i: int in UiReplayModel.COLUMN_NAMES.size():
		var b: Button = UiScreenKit.button(UiReplayModel.COLUMN_NAMES[i], &"GhostButton", Vector2(UiReplayModel.COLUMN_WIDTHS[i], 34.0))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_sort.bind(i))
		heads.add_child(b)
		_sort_buttons.append(b)
	_update_sort_marks()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.resized.connect(func() -> void: _dirty = true)
	_scroll = scroll
	box.add_child(scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_list_box)
	_empty_note = UiScreenKit.label("No replays yet. Every match you play is recorded automatically; the last few appear here.", &"SubLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	_empty_note.custom_minimum_size = Vector2(0.0, 110.0)
	_empty_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(_empty_note)
	return panel


func _detail_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Selected replay", "", &"", 12, 8)
	var panel: PanelContainer = d["panel"] as PanelContainer
	panel.custom_minimum_size = Vector2(470.0, 0.0)
	var box: VBoxContainer = d["body"] as VBoxContainer
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	box.add_child(top)
	_preview = UiMapPreview.new()
	_preview.custom_minimum_size = Vector2(196.0, 196.0)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_preview)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.add_theme_constant_override("separation", 3)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lines)
	for key: String in ["REPLAY", "MAP", "FAMILY", "SEED", "LENGTH", "RESULT", "DATE", "BUILD", "SIZE", "RECORDING"]:
		var line: HBoxContainer = HBoxContainer.new()
		var cap: Label = UiScreenKit.label(key, &"CaptionLabel")
		cap.custom_minimum_size = Vector2(78.0, 0.0)
		line.add_child(cap)
		var val: Label = UiScreenKit.label("-", &"SubLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(val)
		lines.add_child(line)
		_lines[key] = val
	box.add_child(UiScreenKit.label("RULES", &"CaptionLabel"))
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	box.add_child(_chips)
	box.add_child(UiScreenKit.label("COMMANDERS", &"CaptionLabel"))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 96.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players_box)
	var banner_panel: PanelContainer = PanelContainer.new()
	banner_panel.theme_type_variation = &"InsetPanel"
	_banner = UiScreenKit.label("Select a replay in the list to see its details.", &"DimLabel", true)
	_banner.custom_minimum_size = Vector2(0.0, 40.0)
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_panel.add_child(_banner)
	box.add_child(banner_panel)
	var vrow: HBoxContainer = HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 10)
	box.add_child(vrow)
	_verify_bar = ProgressBar.new()
	_verify_bar.show_percentage = false
	_verify_bar.max_value = 100.0
	_verify_bar.custom_minimum_size = Vector2(150.0, 12.0)
	_verify_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_verify_bar.visible = false
	vrow.add_child(_verify_bar)
	_verify_label = UiScreenKit.label("", &"DimLabel")
	_verify_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(_verify_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_verify = UiScreenKit.button("VERIFY", &"", Vector2(0.0, 38.0))
	_verify.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_verify.pressed.connect(_on_verify)
	actions.add_child(_verify)
	_rename = UiScreenKit.button("SAVE AS", &"", Vector2(0.0, 38.0))
	_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename.pressed.connect(_on_rename)
	actions.add_child(_rename)
	_delete = UiScreenKit.button("DELETE", &"DangerButton", Vector2(0.0, 38.0))
	_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete.pressed.connect(_on_delete)
	actions.add_child(_delete)
	_watch = UiScreenKit.button("WATCH REPLAY", &"PrimaryButton", Vector2(0.0, 52.0))
	_watch.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	_watch.add_theme_font_size_override("font_size", 20)
	_watch.pressed.connect(_on_watch)
	box.add_child(_watch)
	return panel


func _bottom_bar() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var back: Button = UiScreenKit.button("BACK", &"", Vector2(150.0, 46.0))
	back.pressed.connect(func() -> void: back_requested.emit())
	h.add_child(back)
	_status = UiScreenKit.label("", &"DimLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_status)
	var open: Button = UiScreenKit.button("OPEN FOLDER", &"", Vector2(200.0, 46.0))
	open.pressed.connect(_on_open_folder)
	h.add_child(open)
	return h


# ---------------------------------------------------------------- scanning

## (Re)reads the folder: the file list now, the metadata progressively from `_process`.
func scan() -> void:
	_infos.clear()
	_pending = PackedStringArray()
	var d: DirAccess = DirAccess.open(dir) if DirAccess.dir_exists_absolute(dir) else null
	if d != null:
		var files: Array[Array] = []
		for f: String in d.get_files():
			if f.get_extension() == NetReplay.EXT:
				var p: String = dir.path_join(f)
				files.append([FileAccess.get_modified_time(p), p])
		files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1])))
		for e: Array in files:
			_pending.append(str(e[1]))
	_dirty = true
	_rebuild()


## Reads every pending file now (tests, screenshots).
func read_all() -> void:
	while not _pending.is_empty():
		_read_one()
	_rebuild()


func _read_one() -> void:
	var p: String = _pending[0]
	_pending.remove_at(0)
	_infos.append(NetReplay.read_info(p, _local))
	_dirty = true


func _process(delta: float) -> void:
	if _scroll != null and absf(_scroll.size.x - 8.0 - _widths_total()) > 30.0 and _scroll.size.x > 100.0:
		_dirty = true
	if not _pending.is_empty():
		var t0: int = Time.get_ticks_usec()
		while not _pending.is_empty() and Time.get_ticks_usec() - t0 < READ_BUDGET_US:
			_read_one()
	_since_rebuild += delta
	if _dirty and (_pending.is_empty() or _since_rebuild > 0.15):
		_rebuild()
	_poll_thumb()
	_poll_verify()


# ---------------------------------------------------------------- list

func _widths_total() -> float:
	var t: float = 0.0
	for w: float in _widths:
		t += w
	return t


func _filters() -> Dictionary:
	return {"text": _filter.text if _filter != null else "", "hide_autosaves": _hide_auto.button_pressed if _hide_auto != null else false,
		"hide_incompatible": _hide_bad.button_pressed if _hide_bad != null else false}


func _rebuild() -> void:
	if _list_box == null:
		return
	_dirty = false
	_since_rebuild = 0.0
	_rows = UiReplayModel.build_rows(_infos, _filters(), _sort_col, _sort_desc)
	_widths = UiReplayModel.scaled_widths(_scroll.size.x - 8.0 if _scroll != null else 0.0)
	for i0: int in _sort_buttons.size():
		_sort_buttons[i0].custom_minimum_size.x = _widths[i0]
	for n: UiListRow in _row_nodes:
		n.queue_free()
	_row_nodes.clear()
	var keep: bool = false
	for i: int in _rows.size():
		var r: Dictionary = _rows[i]
		var node: UiListRow = UiListRow.new()
		node.odd = i % 2 == 1
		node.dimmed = bool(r["dimmed"])
		node.tooltip_text = str(r["tooltip"])
		node.set_cells(r["cells"] as Array[Dictionary], _widths)
		var key: String = str(r["key"])
		node.is_selected = key == _selected_key
		keep = keep or node.is_selected
		node.selected.connect(_select.bind(key))
		node.activated.connect(func() -> void:
			_select(key)
			_on_watch())
		node.set_focusable(true)
		node.focus_entered.connect(func() -> void:
			if _selected_key != key:
				_select(key))  # arrow keys move the focus, and the selection follows it
		_list_box.add_child(node)
		_row_nodes.append(node)
	if not keep and not (_pending.size() > 0 and not _selected_key.is_empty() and not _has_row(_selected_key)):
		# (a wanted selection whose file has not been read yet is kept until the list is complete)
		_selected_key = str(_rows[0]["key"]) if not _rows.is_empty() else ""
		for i2: int in _row_nodes.size():
			_row_nodes[i2].is_selected = str(_rows[i2]["key"]) == _selected_key
	_empty_note.visible = _rows.is_empty()
	if _rows.is_empty():
		_empty_note.text = "No replays yet. Every match you play is recorded automatically; the last few appear here." if _infos.is_empty() and _pending.is_empty() \
			else ("Reading the replay folder ..." if not _pending.is_empty() else "No replay matches the filters.")
	var total: int = _infos.size()
	_header.right_text = "%d REPLAY%s" % [total, "" if total == 1 else "S"] if _pending.is_empty() else "READING %d" % _pending.size()
	_refresh_detail()


func _has_row(key: String) -> bool:
	for r: Dictionary in _rows:
		if str(r["key"]) == key:
			return true
	return false


func _select(key: String) -> void:
	_selected_key = key
	for i: int in _row_nodes.size():
		_row_nodes[i].is_selected = str(_rows[i]["key"]) == key
	_refresh_detail()


func _selected_row() -> Dictionary:
	for r: Dictionary in _rows:
		if str(r["key"]) == _selected_key:
			return r
	return {}


## The info of the selected replay ({} = none).
func selected_info() -> Dictionary:
	var r: Dictionary = _selected_row()
	return r["info"] as Dictionary if not r.is_empty() else {}


func row_count() -> int:
	return _rows.size()


func _on_sort(col: int) -> void:
	if _sort_col == col:
		_sort_desc = not _sort_desc
	else:
		_sort_col = col
		_sort_desc = col == UiReplayModel.Col.DATE or col == UiReplayModel.Col.LENGTH
	_update_sort_marks()
	_rebuild()


func _update_sort_marks() -> void:
	for i: int in _sort_buttons.size():
		var mark: String = ""
		if i == _sort_col:
			mark = "  v" if _sort_desc else "  ^"
		_sort_buttons[i].text = UiReplayModel.COLUMN_NAMES[i] + mark


# ---------------------------------------------------------------- detail

func _refresh_detail() -> void:
	var info: Dictionary = selected_info()
	for c: Node in _players_box.get_children():
		c.queue_free()
	if info.is_empty():
		for chip: Node in _chips.get_children():
			chip.queue_free()
		for k: String in _lines:
			(_lines[k] as Label).text = "-"
		_banner.text = "Select a replay in the list to see its details." if not _rows.is_empty() else "Nothing to show yet."
		_banner.theme_type_variation = &"DimLabel"
		_watch.disabled = true
		_verify.disabled = true
		_rename.disabled = true
		_delete.disabled = true
		_preview.texture = null
		_preview.set_markers(PackedVector2Array(), PackedColorArray(), PackedStringArray())
		_cancel_thumb()
		_thumb_key = ""
		_verify_label.text = ""
		_verify_bar.visible = false
		return
	var detail: Array[Array] = UiReplayModel.detail_lines(info)
	for l: Array in detail:
		if _lines.has(str(l[0])):
			(_lines[str(l[0])] as Label).text = str(l[1])
	var ok: bool = UiReplayModel.playable(info)
	_watch.disabled = not ok
	_verify.disabled = not ok or _verifier != null
	_delete.disabled = false
	_rename.disabled = not bool(info.get("valid", false))
	_rename.text = "RENAME" if str(info.get("kind", "manual")) == "manual" else "SAVE AS"
	var why: String = UiReplayModel.refusal(info)
	if why != "":
		_banner.text = why
		_banner.theme_type_variation = &"DangerLabel"
	elif str(info.get("warning", "")) != "":
		_banner.text = str(info["warning"])
		_banner.theme_type_variation = &"WarnLabel"
	else:
		_banner.text = "Ready to watch. Recorded with this build."
		_banner.theme_type_variation = &"OkLabel"
	_watch.tooltip_text = why
	for c: Node in _chips.get_children():
		c.queue_free()
	for chip: String in UiReplayModel.rule_chips(info):
		var pc: PanelContainer = PanelContainer.new()
		pc.theme_type_variation = &"InsetPanel"
		pc.add_child(UiScreenKit.label(chip, &"DimLabel"))
		_chips.add_child(pc)
	for pv: Variant in info.get("players", []) as Array:
		_players_box.add_child(_player_row(pv as Dictionary, info))
	_show_verify_state(str(info.get("path", "")))
	_request_thumb(info)


func _player_row(p: Dictionary, info: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.theme_type_variation = &"InsetPanel"
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var bar: ColorRect = ColorRect.new()
	bar.color = UiPalette.team(int(p.get("color", 0)))
	bar.custom_minimum_size = Vector2(5.0, 34.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var roster: String = str(p.get("roster", ""))
	var badge: UiFactionBadge = UiFactionBadge.new(UiReplayModel.faction_code(roster), 32.0)
	badge.sub_key = UiReplayModel.sub_key(roster)
	h.add_child(badge)
	var names: VBoxContainer = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	h.add_child(names)
	var winner: bool = false
	for w: Dictionary in UiReplayModel.winners_of(info):
		winner = winner or int(w["pid"]) == int(p["pid"])
	names.add_child(UiScreenKit.label(("* " if winner else "") + str(p.get("name", "")), &"NameLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true))
	names.add_child(UiScreenKit.label(UiReplayModel.roster_line(_data, roster), &"DimLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true))
	var team: String = "TEAM %d" % int(p.get("team", 0)) if int(p.get("team", 0)) <= 4 else ("AI" if str(p.get("kind", "")) == "ai" else "SOLO")
	var t: Label = UiScreenKit.label(team, &"CaptionLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	t.custom_minimum_size = Vector2(60.0, 0.0)
	h.add_child(t)
	return row


# ---------------------------------------------------------------- thumbnail

func _request_thumb(info: Dictionary) -> void:
	var map: Dictionary = info.get("map", {}) as Dictionary
	if map.is_empty():
		return
	var key: String = "%d:%d:%d:%d" % [int(map.get("family", 0)), int(map.get("size", 0)), int(map.get("seed", 0)), int(map.get("layout_players", 2))]
	_set_markers(info, map)
	if key == _thumb_key:
		return
	_cancel_thumb()
	_thumb_key = key
	if _thumbs.has(key):
		_preview.texture = _thumbs[key] as Texture2D
		_preview.busy = false
		return
	_preview.texture = null
	_preview.busy = true
	var cfg: Dictionary = {"family": int(map.get("family", 0)), "size": int(map.get("size", 96)), "seed": int(map.get("seed", 0)),
		"layout_players": int(map.get("layout_players", 2)), "params": (map.get("params", {}) as Dictionary).duplicate()}
	if MapGenerator.validate_params(int(cfg["family"]), int(cfg["size"]), int(cfg["layout_players"])) != "":
		_preview.busy = false
		_preview.note = "No preview"
		return
	_preview.note = ""
	_thumb_job = MapGenJob.begin(cfg, null, true)


func _cancel_thumb() -> void:
	if _thumb_job != null:
		_thumb_job.cancel()
		_thumb_job = null


func _poll_thumb() -> void:
	if _thumb_job == null or not _thumb_job.step(2000):
		return
	var m: MapData = _thumb_job.result()
	_thumb_job = null
	_preview.busy = false
	if m == null:
		return
	var tex: Texture2D = AppViewStage.bake_preview(m)
	_preview.texture = tex
	if tex != null:
		_thumbs[_thumb_key] = tex
		_thumb_order.append(_thumb_key)
		while _thumb_order.size() > THUMB_CACHE:
			_thumbs.erase(_thumb_order[0])
			_thumb_order.remove_at(0)
	var info: Dictionary = selected_info()
	_set_markers(info, info.get("map", {}) as Dictionary, m)


## Numbered, team-coloured start markers once the generated map knows its start cells (before that none).
func _set_markers(info: Dictionary, _map: Dictionary, m: MapData = null) -> void:
	var pos: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var txt: PackedStringArray = PackedStringArray()
	if m != null:
		for pv: Variant in info.get("players", []) as Array:
			var p: Dictionary = pv as Dictionary
			var slot: int = _start_of(info, int(p["pid"]))
			var rec: int = slot * MapData.SPAWN_STRIDE
			if rec + 1 < m.spawns.size():
				var cell: int = m.spawns[rec + 1]
				pos.append(Vector2((float(cell % m.w) + 0.5) / float(m.w), (float(cell / m.w) + 0.5) / float(m.h)))
				cols.append(UiPalette.team(int(p.get("color", 0))))
				txt.append(str(int(p["pid"]) + 1))
	_preview.set_markers(pos, cols, txt)


## The start slot of a player: the header does not repeat it in `players`, so slot = pid unless the info says otherwise.
func _start_of(info: Dictionary, pid: int) -> int:
	for pv: Variant in info.get("players", []) as Array:
		var p: Dictionary = pv as Dictionary
		if int(p["pid"]) == pid:
			return int(p.get("start", pid))
	return pid


# ---------------------------------------------------------------- actions

func _on_watch() -> void:
	var info: Dictionary = selected_info()
	if info.is_empty():
		return
	var why: String = UiReplayModel.refusal(info)
	if why != "":
		UiDlgMessage.open("Replay", why)
		return
	var ctx: AppMatchContext = AppReplay.start(str(info["path"]), {"title": "Replay"})
	if ctx == null:
		UiDlgMessage.open("Replay", "This replay cannot be played: %s" % AppReplay.last_error)
		return
	navigate.emit(&"loading", {"kind": "replay", "title": "Replay"})


func _on_rename() -> void:
	var info: Dictionary = selected_info()
	if info.is_empty():
		return
	var manual: bool = str(info.get("kind", "manual")) == "manual"
	var initial: String = str(info["name"]) if manual else AppReplay.default_name({"map": info.get("map", {})}, UiReplayModel.when_of(info))
	var path: String = str(info["path"])
	UiDlgReplayName.ask("Rename replay" if manual else "Keep replay", initial, "Rename" if manual else "Save", func(chosen: String) -> void:
		var res: String = rename_or_copy(path, chosen, manual)
		_status.text = ("Saved as %s." % res.get_file()) if res != "" else "The replay could not be saved."
		_selected_key = res if res != "" else _selected_key
		scan())


## Manual files are renamed in place, automatic ones (autosave_N, crash_*) are copied under the new name (the rotation keeps its own).
## Returns the new path or "".
func rename_or_copy(path: String, display_name: String, rename: bool) -> String:
	if not rename:
		return NetReplay.save_copy(path, display_name)
	var base: String = NetReplay.sanitize_name(display_name)
	var dst: String = "%s/%s.%s" % [path.get_base_dir(), base, NetReplay.EXT]
	if dst == path:
		return path
	var n: int = 1
	while FileAccess.file_exists(dst):
		n += 1
		dst = "%s/%s_%d.%s" % [path.get_base_dir(), base, n, NetReplay.EXT]
	return dst if DirAccess.rename_absolute(path, dst) == OK else ""


func _on_delete() -> void:
	var info: Dictionary = selected_info()
	if info.is_empty():
		return
	var path: String = str(info["path"])
	UiDlgConfirm.ask("Delete replay", "Delete \"%s\" for good? The file is removed from the replay folder." % UiReplayModel.title_of(info), func(yes: bool) -> void:
		if yes:
			delete_file(path), "Delete", "Keep", true)


## Deletes a replay file of the folder and refreshes the list.
func delete_file(path: String) -> bool:
	var ok: bool = NetReplay.delete_replay(path, dir)
	_status.text = "Replay deleted." if ok else "The replay could not be deleted."
	_selected_key = ""
	scan()
	return ok


func _on_open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(dir) if dir.begins_with("user://") or dir.begins_with("res://") else dir)


# ---------------------------------------------------------------- verify

func _on_verify() -> void:
	var info: Dictionary = selected_info()
	if info.is_empty() or _verifier != null or not UiReplayModel.playable(info):
		return
	var data: NetReplayData = NetReplayData.load_file(str(info["path"]))
	if data == null:
		_verify_label.text = "DIVERGED  file unreadable"
		return
	var o: NetSessionOptions = AppNetSetup.make_options(_data if _data != null else GameData.load_default(), {"with_view": false, "events": false})
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.strict = false
	p.local_versions = _local
	p.auto_clear_events = true
	if p.setup(data, o.world_builder, NetClock.real(), false) != OK:
		_verify_label.text = "DIVERGED  " + p.error_text
		return
	p.set_speed(NetReplayPlayer.MAX)
	_verifier = p
	_verify_path = str(info["path"])
	_verify_bar.visible = true
	_verify_bar.value = 0.0
	_verify_label.text = "Verifying ..."
	_verify.disabled = true


func _poll_verify() -> void:
	if _verifier == null:
		return
	_verifier.poll(6000)
	var build_failed: bool = not _verifier.is_loading() and _verifier.adapter() == null
	var done: bool = _verifier.is_finished() or _verifier.diverged_tick() >= 0 or build_failed
	if not done:
		_verify_bar.value = 0.1 * float(_verifier.load_progress_pct()) if _verifier.is_loading() else 10.0 + 90.0 * _verifier.progress()
		return
	var res: String
	if _verifier.diverged_tick() >= 0:
		res = "DIVERGED at %s" % UiFormatLite.clock(_verifier.diverged_tick() * SimConfig.TICK_MS / 1000)
	elif _verifier.is_finished():
		res = "OK  %d checks" % _verifier.compared_count()
	else:
		res = "FAILED  " + _verifier.error_text
	_verify_results[_verify_path] = res
	_verifier = null
	_verify_bar.visible = false
	_show_verify_state(_selected_key)


func _show_verify_state(path: String) -> void:
	if _verifier != null and _verify_path == path:
		return
	_verify_bar.visible = _verifier != null
	_verify_label.text = str(_verify_results.get(path, ""))
	var bad: bool = _verify_label.text.begins_with("DIVERGED") or _verify_label.text.begins_with("FAILED")
	_verify_label.theme_type_variation = &"DangerLabel" if bad else (&"OkLabel" if _verify_label.text != "" else &"DimLabel")
	_verify.disabled = _verifier != null or not UiReplayModel.playable(selected_info())
