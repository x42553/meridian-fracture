class_name UiScreenLanBrowser
extends UiScreen
## LAN browser and joining (ui.md 5.15): the games announced on the network (`NetDiscovery.entries()`: name, host address, map, players,
## build compatibility; incompatible and full games are listed dimmed with the reason), filters and sortable columns, a detail card with
## a compatibility banner, JOIN GAME, direct connect by address with recent hosts, HOST GAME (`UiDlgHostGame`) and the join flow
## (CONNECTING dialog with Cancel, `UiDlgJoinRejected` for a refusal, a password prompt for BAD_PASSWORD, a message for a timeout).
## The firewall / permission explainer (`UiDlgFirewallHelp`) is shown once, BEFORE the first socket opens. The list itself is
## `UiLanModel`; sessions come from `AppLan`. Params: `{message: String}` (why the previous screen was left, e.g. "The host left the game."), `no_help: true` (screenshots and tests: skip the explainer).

const REFRESH_S: float = 0.4

var browser: NetDiscovery = null

var _data: GameData = null
var _list_box: VBoxContainer = null
var _list_scroll: ScrollContainer = null
var _header: UiPanelHeader = null
var _hint: Label = null
var _empty_note: Label = null
var _filter: LineEdit = null
var _hide_full: CheckBox = null
var _hide_bad: CheckBox = null
var _sort_buttons: Array[Button] = []
var _sort_col: int = UiLanModel.Col.GAME
var _sort_desc: bool = false
var _rows: Array[Dictionary] = []
var _row_nodes: Array[LanRow] = []
var _signature: String = ""
var _selected_key: String = ""
var _refresh_t: float = 0.0
var _empty_s: float = 0.0
var _detail: Dictionary = {}
var _join_button: Button = null
var _status: Label = null
var _addr: LineEdit = null
var _port: SpinBox = null
var _recent: OptionButton = null
var _direct_error: Label = null
var _join_ctx: AppMatchContext = null
var _join_target: String = ""
var _join_address: String = ""
var _join_port: int = 0
var _connecting: UiDialog = null
var _handed_over: bool = false
var _local_version: String = ""


func _init() -> void:
	super._init()
	screen_id = &"lan_browser"


func enter(params: Dictionary) -> void:
	var app: Node = get_tree().root.get_node_or_null("AppState")
	_data = app.get("data") as GameData if app != null else null
	if _data == null:
		_data = GameData.load_default()
		if app != null and _data != null:
			app.set("data", _data)
	if _data == null:
		add_child(UiScreenKit.label("The game data could not be loaded.", &"SubLabel"))
		return
	_local_version = str(ProjectSettings.get_setting("application/config/version", ""))
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("clear_backdrop")
	_build()
	_refresh_detail()
	set_process(true)
	if str(params.get("message", "")) != "":
		UiDlgMessage.open("LAN game", str(params["message"]))
	if AppLan.help_shown() or scenes == null or bool(params.get("no_help", false)):
		_begin_browse()
	else:
		var dlg: UiDlgFirewallHelp = UiDlgFirewallHelp.open()
		dlg.closed.connect(func(_r: int) -> void:
			AppLan.mark_help_shown()
			_begin_browse())


func exit() -> void:
	set_process(false)
	if browser != null:
		browser.close()
		browser = null
	_detach_join()
	if _join_ctx != null and not _handed_over:
		AppLan.leave()
	_join_ctx = null
	if _connecting != null and is_instance_valid(_connecting):
		_connecting.close(0)


func default_focus() -> Control:
	return _filter


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
	body.add_child(_games_panel())
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size = Vector2(500.0, 0.0)
	body.add_child(right)
	right.add_child(_detail_panel())
	right.add_child(_direct_panel())
	right.add_child(_help_panel())
	root.add_child(_bottom_bar())


func _title_bar() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	v.add_child(UiScreenKit.wordmark("LAN MULTIPLAYER", 38, 800, 4, UiPalette.TEXT))
	v.add_child(UiScreenKit.label("FIND A GAME ON YOUR NETWORK  //  UDP %d-%d" % [NetProtocol.DISCOVERY_PORT, NetProtocol.DEFAULT_PORT + NetProtocol.PORT_SCAN_COUNT - 1], &"DimLabel"))
	h.add_child(UiScreenKit.spacer(0.0, true))
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = &"InsetPanel"
	var c: HBoxContainer = HBoxContainer.new()
	c.add_theme_constant_override("separation", 22)
	chip.add_child(c)
	c.add_child(UiScreenKit.label("PLAYER  " + _player_name().to_upper(), &"CaptionLabel"))
	c.add_child(UiScreenKit.label("BUILD  v%s" % _local_version if _local_version != "" else "BUILD  dev", &"CaptionLabel"))
	c.add_child(UiScreenKit.label("DATA HASH  " + UiFormatLite.hash8(_data.data_hash()), &"CaptionLabel"))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	return h


func _games_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Games on the network", "SEARCHING", &"", 12, 8)
	var panel: PanelContainer = d["panel"] as PanelContainer
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_header = d["header"] as UiPanelHeader
	var box: VBoxContainer = d["body"] as VBoxContainer
	# filters
	var f: HBoxContainer = HBoxContainer.new()
	f.add_theme_constant_override("separation", 14)
	box.add_child(f)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter by name, address or map"
	_filter.clear_button_enabled = true
	_filter.custom_minimum_size = Vector2(300.0, 36.0)
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild(true))
	f.add_child(_filter)
	_hide_full = CheckBox.new()
	_hide_full.text = "Hide full"
	_hide_full.toggled.connect(func(_on: bool) -> void: _rebuild(true))
	f.add_child(_hide_full)
	_hide_bad = CheckBox.new()
	_hide_bad.text = "Hide incompatible"
	_hide_bad.toggled.connect(func(_on: bool) -> void: _rebuild(true))
	f.add_child(_hide_bad)
	var refresh: Button = UiScreenKit.button("REFRESH", &"", Vector2(120.0, 36.0))
	refresh.pressed.connect(_on_refresh)
	f.add_child(refresh)
	# sortable column heads
	var heads: HBoxContainer = HBoxContainer.new()
	heads.add_theme_constant_override("separation", 0)
	heads.custom_minimum_size = Vector2(0.0, 34.0)
	box.add_child(heads)
	for i: int in UiLanModel.COLUMN_NAMES.size():
		var b: Button = UiScreenKit.button(UiLanModel.COLUMN_NAMES[i], &"GhostButton", Vector2(UiLanModel.COLUMN_WIDTHS[i], 34.0))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_sort.bind(i))
		heads.add_child(b)
		_sort_buttons.append(b)
	_update_sort_marks()
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_list_scroll)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(stack)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_list_box)
	_empty_note = UiScreenKit.label("Searching for games on your network ...", &"SubLabel", true, HORIZONTAL_ALIGNMENT_CENTER)
	_empty_note.custom_minimum_size = Vector2(0.0, 90.0)
	_empty_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(_empty_note)
	_hint = UiScreenKit.label("", &"WarnLabel", true)
	box.add_child(_hint)
	return panel


func _detail_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Selected game", "", &"", 12, 6)
	var panel: PanelContainer = d["panel"] as PanelContainer
	var box: VBoxContainer = d["body"] as VBoxContainer
	for key: String in ["name", "host", "map", "players", "options"]:
		var line: HBoxContainer = HBoxContainer.new()
		var cap: Label = UiScreenKit.label(key.to_upper(), &"CaptionLabel")
		cap.custom_minimum_size = Vector2(110.0, 0.0)
		line.add_child(cap)
		var val: Label = UiScreenKit.label("-", &"SubLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(val)
		box.add_child(line)
		_detail[key] = val
	var pips: SlotPips = SlotPips.new()
	box.add_child(pips)
	_detail["pips"] = pips
	var banner_panel: PanelContainer = PanelContainer.new()
	banner_panel.theme_type_variation = &"InsetPanel"
	var banner: Label = UiScreenKit.label("Select a game in the list to see its details.", &"DimLabel", true)
	banner.custom_minimum_size = Vector2(0.0, 52.0)
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_panel.add_child(banner)
	box.add_child(banner_panel)
	_detail["banner"] = banner
	return panel


func _direct_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Join by address", "DIRECT", &"", 12, 8)
	var panel: PanelContainer = d["panel"] as PanelContainer
	var box: VBoxContainer = d["body"] as VBoxContainer
	box.add_child(UiScreenKit.label("HOST ADDRESS", &"CaptionLabel"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_addr = LineEdit.new()
	_addr.placeholder_text = "192.168.1.20 or hostname"
	_addr.max_length = 255
	_addr.custom_minimum_size = Vector2(0.0, 36.0)
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr.text_submitted.connect(func(_t: String) -> void: _on_connect())
	row.add_child(_addr)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.step = 1
	_port.value = NetProtocol.DEFAULT_PORT
	_port.custom_minimum_size = Vector2(120.0, 36.0)
	row.add_child(_port)
	var recent_row: HBoxContainer = HBoxContainer.new()
	recent_row.add_theme_constant_override("separation", 8)
	box.add_child(recent_row)
	_recent = OptionButton.new()
	_recent.fit_to_longest_item = false
	_recent.clip_text = true
	_recent.custom_minimum_size = Vector2(0.0, 36.0)
	_recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_recent()
	var st: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	if st != null:
		var last: Dictionary = UiLanModel.validate_direct(str(st.call("get_str", AppLan.LAST_ADDRESS_KEY)))
		if bool(last["ok"]):
			_addr.text = str(last["host"])
			_port.value = int(last["port"])
	_recent.item_selected.connect(_on_recent)
	recent_row.add_child(_recent)
	var connect_button: Button = UiScreenKit.button("CONNECT", &"PrimaryButton", Vector2(140.0, 38.0))
	connect_button.pressed.connect(_on_connect)
	recent_row.add_child(connect_button)
	_direct_error = UiScreenKit.label("", &"DangerLabel", true)
	box.add_child(_direct_error)
	return panel


func _help_panel() -> Control:
	var d: Dictionary = UiScreenKit.panel("Network help", AppLan.platform_key().to_upper(), &"", 12, 8)
	var panel: PanelContainer = d["panel"] as PanelContainer
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = d["body"] as VBoxContainer
	box.add_child(UiScreenKit.label("Everyone must be on the same network and run the same build (see BUILD). A game shows up within a few seconds; if the list stays empty, ask the host for the address and use Join by address.", &"DimLabel", true))
	box.add_child(UiScreenKit.label(str(AppLan.firewall_text(AppLan.platform_key())["ports"]), &"CaptionLabel", true))
	var b: Button = UiScreenKit.button("SHOW FIREWALL HELP", &"", Vector2(0.0, 38.0))
	b.pressed.connect(func() -> void: UiDlgFirewallHelp.open())
	box.add_child(b)
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
	var host_button: Button = UiScreenKit.button("HOST GAME", &"", Vector2(220.0, 52.0))
	host_button.pressed.connect(_on_host)
	h.add_child(host_button)
	_join_button = UiScreenKit.button("JOIN GAME", &"PrimaryButton", Vector2(260.0, 52.0))
	_join_button.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	_join_button.add_theme_font_size_override("font_size", 20)
	_join_button.pressed.connect(_join_selected)
	h.add_child(_join_button)
	return h


# ---------------------------------------------------------------- browsing

func _begin_browse() -> void:
	if browser != null or not is_inside_tree():
		return
	browser = AppLan.make_browser({})
	if browser == null:
		return
	var err: int = browser.start_browse()
	if err != OK:
		Log.warn("ui", "lan browser: start_browse failed (%d, %s)" % [err, browser.browse_error])
	_refresh_t = 0.0


func _on_refresh() -> void:
	if browser != null:
		browser.stop_browse()
		browser.start_browse()
	_empty_s = 0.0
	_signature = ""
	_rebuild(true)


func _process(delta: float) -> void:
	if browser != null:
		browser.poll()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_S
		_rebuild(false)
	var listed: int = browser.entries().size() if browser != null else 0
	if listed == 0:
		_empty_s += delta
	else:
		_empty_s = 0.0
	if _hint != null:
		var be: String = browser.browse_error if browser != null else ""
		_hint.text = UiLanModel.hint(be, _empty_s)
		_hint.visible = _hint.text != ""
		_empty_note.visible = _row_nodes.is_empty()
		if _row_nodes.is_empty() and listed > 0:
			_empty_note.text = "No game matches the filters."
		elif _row_nodes.is_empty():
			_empty_note.text = "Searching for games on your network ..." if be == "" else "The browser could not listen for announcements."


func _filters() -> Dictionary:
	return {"text": _filter.text, "hide_full": _hide_full.button_pressed, "hide_incompatible": _hide_bad.button_pressed}


## Rebuilds the list rows when the entries, the filters or the sort changed (`force` = a filter or sort was touched).
func _rebuild(force: bool) -> void:
	if _list_box == null:
		return
	var entries: Array[NetDiscoveryEntry] = browser.entries() if browser != null else ([] as Array[NetDiscoveryEntry])
	var rows: Array[Dictionary] = UiLanModel.build_rows(entries, _filters(), _sort_col, _sort_desc, _local_version)
	var sig: String = ""
	for r: Dictionary in rows:
		var cells: Array[Dictionary] = r["cells"] as Array[Dictionary]
		sig += "%s|%s|%s|%s;" % [r["key"], str(cells[UiLanModel.Col.PLAYERS]["text"]), str(cells[UiLanModel.Col.BUILD]["text"]), r["joinable"]]
	if not force and sig == _signature:
		return
	_signature = sig
	_rows = rows
	for n: LanRow in _row_nodes:
		n.queue_free()
	_row_nodes.clear()
	var keep_selected: bool = false
	for i: int in rows.size():
		var r2: Dictionary = rows[i]
		var node: LanRow = LanRow.new()
		node.odd = i % 2 == 1
		node.dimmed = bool(r2["dimmed"])
		node.locked = bool(r2["locked"])
		node.tooltip_text = str(r2["tooltip"])
		node.set_cells(r2["cells"] as Array[Dictionary], UiLanModel.COLUMN_WIDTHS)
		var key: String = str(r2["key"])
		node.is_selected = key == _selected_key
		keep_selected = keep_selected or node.is_selected
		node.selected.connect(_select.bind(key))
		node.activated.connect(func() -> void:
			_select(key)
			_join_selected())
		_list_box.add_child(node)
		_row_nodes.append(node)
	if not keep_selected and _selected_key != "":
		_selected_key = ""
	_header.right_text = "%d GAME%s" % [rows.size(), "" if rows.size() == 1 else "S"] if browser != null else "OFFLINE"
	_refresh_detail()


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


func _refresh_detail() -> void:
	var r: Dictionary = _selected_row()
	if _join_button == null:
		return
	if r.is_empty():
		for key: String in ["name", "host", "map", "players", "options"]:
			(_detail[key] as Label).text = "-"
		(_detail["pips"] as SlotPips).set_counts(0, 0, 0)
		var b0: Label = _detail["banner"] as Label
		b0.text = "Select a game in the list to see its details."
		b0.theme_type_variation = &"DimLabel"
		_join_button.disabled = true
		_status.text = "Select a game, or join by address."
		return
	var e: NetDiscoveryEntry = r["entry"] as NetDiscoveryEntry
	(_detail["name"] as Label).text = e.host_name + ("   [password]" if e.has_password() else "")
	(_detail["host"] as Label).text = e.address + ":" + str(e.port)
	(_detail["map"] as Label).text = "%s  //  %d x %d cells" % [UiMapNames.family_name(e.map_family), e.map_size, e.map_size]
	(_detail["players"] as Label).text = "%d human%s + %d AI  //  %d of %d slots free" % [e.humans, "" if e.humans == 1 else "s", e.ai_count, e.slots_free, e.slots_total]
	(_detail["options"] as Label).text = "Spectators %s  //  build v%s" % ["allowed" if e.spectators_allowed() else "closed", e.game_version]
	(_detail["pips"] as SlotPips).set_counts(e.humans, e.ai_count, e.slots_total)
	var banner: Dictionary = UiLanModel.banner(e)
	var bl: Label = _detail["banner"] as Label
	bl.text = str(banner["text"]) if bool(r["joinable"]) or not bool(banner["ok"]) else str(r["reason"])
	bl.theme_type_variation = &"OkLabel" if bool(banner["ok"]) and bool(r["joinable"]) else &"DangerLabel"
	_join_button.disabled = not bool(r["joinable"])
	_join_button.tooltip_text = str(r["reason"])
	_status.text = str(r["reason"]) if not bool(r["joinable"]) else "Ready to join %s." % e.host_name


func _on_sort(col: int) -> void:
	if _sort_col == col:
		_sort_desc = not _sort_desc
	else:
		_sort_col = col
		_sort_desc = false
	_update_sort_marks()
	_rebuild(true)


func _update_sort_marks() -> void:
	for i: int in _sort_buttons.size():
		var mark: String = ""
		if i == _sort_col:
			mark = "  v" if _sort_desc else "  ^"
		_sort_buttons[i].text = UiLanModel.COLUMN_NAMES[i] + mark


# ---------------------------------------------------------------- direct connect

func _fill_recent() -> void:
	_recent.clear()
	_recent.add_item("Recent hosts", 0)
	var list: PackedStringArray = AppLan.recent_hosts()
	for i: int in list.size():
		_recent.add_item(list[i], i + 1)
	_recent.select(0)
	_recent.disabled = list.is_empty()


func _on_recent(i: int) -> void:
	if i <= 0:
		return
	var t: String = _recent.get_item_text(i)
	var v: Dictionary = UiLanModel.validate_direct(t)
	if bool(v["ok"]):
		_addr.text = str(v["host"])
		_port.value = int(v["port"])
	_recent.select(0)


func _on_connect() -> void:
	var v: Dictionary = UiLanModel.validate_direct(_addr.text, str(int(_port.value)))
	_direct_error.text = str(v["error"])
	if not bool(v["ok"]):
		return
	_start_join(str(v["host"]), int(v["port"]), "")


# ---------------------------------------------------------------- join flow

func _join_selected() -> void:
	var r: Dictionary = _selected_row()
	if r.is_empty() or not bool(r["joinable"]):
		return
	var e: NetDiscoveryEntry = r["entry"] as NetDiscoveryEntry
	_start_join(e.address, e.port, "")


func _start_join(address: String, port: int, password: String) -> void:
	if _join_ctx != null:
		_detach_join()
		AppLan.leave()
		_join_ctx = null
	_join_address = address
	_join_port = port
	_join_target = "%s:%d" % [address, port]
	var ctx: AppMatchContext = AppLan.join_lan(address, port, password, {})
	if ctx == null:
		UiDlgMessage.open("Could not connect", "Could not start connecting to %s: %s" % [_join_target, NetSession.last_create_error])
		return
	_join_ctx = ctx
	ctx.session.phase_changed.connect(_on_join_phase)
	ctx.session.join_rejected.connect(_on_join_rejected)
	ctx.session.net_error.connect(_on_join_error)
	_show_connecting()


func _detach_join() -> void:
	if _join_ctx == null or _join_ctx.session == null:
		return
	var s: NetSession = _join_ctx.session
	if s.phase_changed.is_connected(_on_join_phase):
		s.phase_changed.disconnect(_on_join_phase)
	if s.join_rejected.is_connected(_on_join_rejected):
		s.join_rejected.disconnect(_on_join_rejected)
	if s.net_error.is_connected(_on_join_error):
		s.net_error.disconnect(_on_join_error)


func _show_connecting() -> void:
	_close_connecting()
	_connecting = UiDialog.new("Connecting", 460)
	_connecting.add_text("Connecting to %s ...\nThe attempt gives up after 6 seconds." % _join_target)
	_connecting.add_button("Cancel", 0)
	_connecting.closed.connect(func(result_code: int) -> void:
		if result_code == 0 and _join_ctx != null and not _handed_over:
			_cancel_join())
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("modal", _connecting)
	_status.text = "Connecting to %s ..." % _join_target


func _close_connecting() -> void:
	if _connecting != null and is_instance_valid(_connecting) and not _connecting.is_closed():
		var d: UiDialog = _connecting
		_connecting = null
		d.close(1)
	_connecting = null


func _cancel_join() -> void:
	_detach_join()
	_join_ctx = null
	AppLan.leave()
	_status.text = "Connection cancelled."


func _on_join_phase(phase: int, _previous: int) -> void:
	if phase != NetSession.Phase.LOBBY or _join_ctx == null:
		return
	_close_connecting()
	_detach_join()
	_handed_over = true
	AppLan.remember_host(_join_target)
	navigate.emit(&"lobby", {"lan": true})


func _on_join_rejected(reason: int, info: Dictionary) -> void:
	_close_connecting()
	_detach_join()
	_join_ctx = null
	AppLan.leave()
	var dlg: UiDlgJoinRejected = UiDlgJoinRejected.new(reason, info, _join_target)
	if reason == NetProtocol.RejectReason.BAD_PASSWORD:
		dlg.closed.connect(func(result_code: int) -> void:
			if result_code == UiDlgJoinRejected.RESULT_RETRY:
				_start_join(_join_address, _join_port, dlg.password()))
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("modal", dlg)
	_status.text = "Could not join %s." % _join_target


func _on_join_error(_code: int, text: String) -> void:
	if _join_ctx == null or _join_ctx.session.phase > NetSession.Phase.CONNECTING:
		return
	_close_connecting()
	_detach_join()
	_join_ctx = null
	AppLan.leave()
	UiDlgMessage.open("Could not connect", text)
	_status.text = "Could not connect to %s." % _join_target


# ---------------------------------------------------------------- host flow

func _on_host() -> void:
	var defaults: Dictionary = {"lobby_name": "%s's game" % _player_name(), "port": _setting_int(&"net/port", NetProtocol.DEFAULT_PORT),
		"advertise": _setting_bool(&"net/discovery", true), "spectators": true}
	var dlg: UiDlgHostGame = UiDlgHostGame.new(defaults)
	dlg.closed.connect(func(result_code: int) -> void:
		if result_code == UiDlgHostGame.RESULT_HOST:
			_start_host(dlg.values()))
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("modal", dlg)


func _start_host(values: Dictionary) -> void:
	var ctx: AppMatchContext = AppLan.host_lan(values)
	if ctx == null:
		UiDlgMessage.open("Could not host", "No free network port (%d-%d). Close other instances of the game." % [
			int(values.get("port", NetProtocol.DEFAULT_PORT)), int(values.get("port", NetProtocol.DEFAULT_PORT)) + NetProtocol.PORT_SCAN_COUNT - 1])
		return
	_handed_over = true
	navigate.emit(&"lobby", {"lan": true})


# ---------------------------------------------------------------- helpers

func _player_name() -> String:
	var st: Node = get_tree().root.get_node_or_null("AppSettings") if is_inside_tree() else null
	return str(st.call("get_str", &"net/player_name")) if st != null else "Commander"


func _setting_int(id: StringName, fallback: int) -> int:
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	return int(st.call("get_int", id)) if st != null else fallback


func _setting_bool(id: StringName, fallback: bool) -> bool:
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	return bool(st.call("get_bool", id)) if st != null else fallback


## A list row with the padlock of a password-protected game.
class LanRow extends UiListRow:
	var locked: bool = false

	func _draw() -> void:
		super._draw()
		if locked and not is_header:
			var col: Color = UiPalette.semantic(&"warn")
			if dimmed:
				col = col.darkened(0.4)
			UiGlyphs.draw(self, UiGlyphs.Glyph.LOCK, Rect2(UiLanModel.COLUMN_WIDTHS[0] - 22.0, size.y * 0.5 - 8.0, 16.0, 16.0), col)


## One dot per slot of the selected game: filled in the accent for a human, muted for an AI, an outline for a free slot.
class SlotPips extends Control:
	var humans: int = 0
	var ai: int = 0
	var total: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 30.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_counts(p_humans: int, p_ai: int, p_total: int) -> void:
		humans = p_humans
		ai = p_ai
		total = p_total
		queue_redraw()

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var cap: Font = UiFonts.get_font(UiFonts.Role.BODY)
		draw_string(cap, Vector2(0.0, 20.0), "SLOTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_DIM)
		for i: int in total:
			var c: Vector2 = Vector2(122.0 + float(i) * 26.0, 14.0)
			if i < humans:
				draw_circle(c, 9.0, acc)
			elif i < humans + ai:
				draw_circle(c, 9.0, UiPalette.TEXT_MUTE)
			else:
				draw_arc(c, 8.5, 0.0, TAU, 24, UiPalette.TEXT_DIM, 1.6, true)
