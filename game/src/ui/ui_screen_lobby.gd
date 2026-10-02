class_name UiScreenLobby
extends UiScreen
## Skirmish lobby (ui.md 5.14, role LOCAL): the slot table (8 rows: type, faction, subfaction, team, colour, start position), the
## faction briefing under it, the map panel (family, size, seed, live preview) and the rules panel in the middle column, and the
## bottom bar with Back, the status line, the start error line and START. START validates the setup (`UiLobbyState.validate`, the
## `NetLobby.StartError` codes of 5.14.4: the error shows in red above the button for 6 s and the offending row / panel pulses),
## builds the match config and launches the local session (`AppMatch.start_local`), then shows the loading screen.
## The last edited setup is restored on entry and saved when the screen is left (`user://last_skirmish.json`).
## LAN roles (`params.lan = true`, session from `params.session` or `AppLan.current_session()`): the same widgets edit a mirror of the
## replicated lobby (`UiLobbyLan` / `UiLobbyNet`). The HOST edits every row, the map, the rules and the network options, kicks
## players and starts with a countdown; a CLIENT edits its own row, toggles READY, may take an open slot or become a spectator and sees
## everything else read-only. Chat, the lobby info and the spectator list sit in a right column (wide windows) or a bottom-right
## drawer (`CHAT` button), the ping of every remote player shows in its row and the client's own latency in the title bar.
## Params: `{role: "local", back: StringName, error: String}` or `{lan: true, session: NetSession, error: String, abort_reason: int}`.

const ERROR_SHOW_S: float = 6.0
## Logical window width from which the LAN column sits beside the map and rules; narrower windows get the drawer.
const WIDE_FROM: float = 1880.0

var state: UiLobbyState = null

var _data: GameData = null
var _rows: Array[UiLobbySlotRow] = []
var _briefing: UiLobbyBriefing = null
var _map: UiLobbyMapPanel = null
var _rules: UiLobbyRulesPanel = null
var _focus_slot: int = 0
var _hover_slot: int = -1
var _title_badge: UiFactionBadge = null
var _status: Label = null
var _error: Label = null
var _error_t: float = 0.0
var _start: Button = null
var _presets: OptionButton = null
var _slots_panel: PanelContainer = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _skin_code: String = ""

## LAN roles: `UiLobbyNet.Role` (LOCAL for the skirmish), the controller and the extra widgets.
var role: int = UiLobbyNet.Role.LOCAL
var lan: UiLobbyLan = null
var chat: UiLobbyChat = null
var _lan_col: Control = null
var _drawer: PanelContainer = null
var _drawer_button: Button = null
var _spec_button: Button = null
var _title_main: Label = null
var _title_sub: Label = null
var _ping_chip: Label = null
var _info_labels: Dictionary = {}
## Screenshots only (`--screen=lobby --lan-host --lan-address=192.0.2.10:27615`): shown instead of the real LAN address, so a published
## image never carries the maintainer's private address.
var _address_override: String = ""
var _spec_list: Label = null
var _countdown: Control = null
var _countdown_label: Label = null
var _rows_box: VBoxContainer = null
var _wide: bool = true


func _init() -> void:
	super._init()
	screen_id = &"lobby"


func enter(params: Dictionary) -> void:
	var app: Node = get_tree().root.get_node_or_null("AppState")
	_data = app.get("data") as GameData if app != null else null
	if _data == null:
		_data = GameData.load_default()  # opened without the boot's data (tools, tests)
		if app != null and _data != null:
			app.set("data", _data)
	if _data == null:
		Log.warn("ui", "lobby: no game data")
		add_child(UiScreenKit.label("The game data could not be loaded.", &"SubLabel"))
		return
	_rng.randomize()
	_address_override = str(params.get("address_override", ""))
	state = UiLobbyState.create(_data)
	var session: NetSession = null
	if bool(params.get("lan", false)) or str(params.get("role", "")) == "host" or str(params.get("role", "")) == "client":
		session = params.get("session", null) as NetSession
		if session == null:
			session = AppLan.current_session()
		if session == null or session.role == NetSession.Role.LOCAL or session.lobby == null:
			Log.warn("ui", "lobby: the LAN lobby was opened without a LAN session")
			add_child(UiScreenKit.label("There is no LAN game to show.", &"SubLabel"))
			back_requested.emit.call_deferred()
			return
	if session != null:
		lan = UiLobbyLan.new()
		lan.setup(session, state)
		role = lan.role
	else:
		var st: Node = get_tree().root.get_node_or_null("AppSettings")
		if st != null and st.get("store") is AppSettingsStore:
			var nm: Variant = (st.get("store") as AppSettingsStore).get_value(&"net/player_name")
			if nm != null and str(nm) != "":
				state.player_name = str(nm)
		state.load_saved()
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("clear_backdrop")
	_wide = _viewport_width() >= WIDE_FROM
	_apply_skin()
	_build()
	if lan != null:
		_lan_wire(session)
	_refresh_all()
	if str(params.get("error", "")) != "":
		if lan != null and params.has("abort_reason"):
			_modal(UiDlgJoinRejected.for_abort(int(params["abort_reason"]), str(params["error"])))
		else:
			UiDlgMessage.open("Could not start the match", str(params["error"]))
	if params.has("preview"):
		_debug_preview(str(params["preview"]))
	set_process(true)


func exit() -> void:
	set_process(false)
	if state != null and lan == null:
		state.save()
	if _map != null:
		_map.cancel()
	if lan != null:
		_lan_unwire()


func default_focus() -> Control:
	return _start


func on_escape() -> bool:
	if lan != null and _drawer != null and _drawer.visible:
		_toggle_drawer()
		return true
	return false


## The LAN lobby asks before it closes or leaves the game (the skirmish just goes back).
func can_leave() -> bool:
	if lan == null:
		return true
	_confirm_leave()
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
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(_slots_table())
	_briefing = UiLobbyBriefing.new()
	_briefing.setup(_data)
	left.add_child(_briefing)
	var mid: VBoxContainer = VBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	mid.custom_minimum_size = Vector2(560.0 if lan == null else 500.0, 0.0)
	mid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(mid)
	_map = UiLobbyMapPanel.new()
	_map.setup(state, lan != null)
	_map.changed.connect(_on_state_changed)
	mid.add_child(_map)
	_rules = UiLobbyRulesPanel.new()
	_rules.setup(state, lan != null)
	_rules.changed.connect(_on_state_changed)
	_rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_rules)
	if lan != null:
		_lan_col = _lan_column()
		if _wide:
			_lan_col.custom_minimum_size = Vector2(300.0, 0.0)
			_lan_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			body.add_child(_lan_col)
		else:
			_make_drawer()
		_countdown = _countdown_overlay()
		add_child(_countdown)
		_apply_read_only()
	root.add_child(_bottom_bar())


func _title_bar() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	_title_badge = UiFactionBadge.new("", 52.0)
	h.add_child(_title_badge)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	_title_main = UiScreenKit.wordmark("SKIRMISH" if lan == null else "LAN LOBBY", 38, 800, 4, UiPalette.TEXT)
	v.add_child(_title_main)
	_title_sub = UiScreenKit.label("NEW MATCH  //  UP TO 8 COMMANDERS  //  SINGLE PLAYER" if lan == null else _lan_subtitle(), &"DimLabel")
	v.add_child(_title_sub)
	var sp: Control = UiScreenKit.spacer(0.0, true)
	sp.size_flags_vertical = Control.SIZE_FILL
	h.add_child(sp)
	if lan != null:
		h.add_child(_lan_chips())
		return h
	var pl: Label = UiScreenKit.label("PRESET", &"CaptionLabel")
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pl)
	_presets = OptionButton.new()
	_presets.fit_to_longest_item = false
	_presets.custom_minimum_size = Vector2(260.0, 38.0)
	_presets.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_presets.add_item("Custom", 0)
	var list: Array = UiLobbyState.presets()
	for i: int in list.size():
		_presets.add_item(str((list[i] as Dictionary).get("name", "Preset")), i + 1)
	_presets.item_selected.connect(func(i: int) -> void:
		if i > 0:
			state.apply_preset(list[i - 1] as Dictionary)
			_refresh_all()
			_presets.select(0))
	h.add_child(_presets)
	return h


func _slots_table() -> Control:
	var d: Dictionary = UiScreenKit.panel("Players", "8 SLOTS  //  TEAM GAMES SUPPORTED" if lan == null else "8 SLOTS  //  HOST CONTROLS THE MAP AND THE OPEN SLOTS", &"", 12, 6)
	_slots_panel = d["panel"] as PanelContainer
	var body: VBoxContainer = d["body"] as VBoxContainer
	var caps: HBoxContainer = HBoxContainer.new()
	caps.add_theme_constant_override("separation", 10)
	caps.add_child(UiScreenKit.spacer(0.0))
	caps.get_child(0).custom_minimum_size = Vector2(UiLobbySlotRow.LEAD_W - 10.0, 0.0)
	var names: PackedStringArray = ["PLAYER", "FACTION", "SUBFACTION", "TEAM", "START"]
	var mins: Array[float] = [UiLobbySlotRow.COL_TYPE, UiLobbySlotRow.COL_FACTION, UiLobbySlotRow.COL_SUB, UiLobbySlotRow.COL_TEAM, UiLobbySlotRow.COL_START]
	for i: int in names.size():
		var l: Label = UiScreenKit.label(names[i], &"CaptionLabel")
		l.custom_minimum_size = Vector2(mins[i] * (UiLobbySlotRow.LAN_SCALE[i] if lan != null else 1.0), 0.0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = UiLobbySlotRow.RATIO[i]
		caps.add_child(l)
	if lan != null:
		var hc: Label = UiScreenKit.label("HCP", &"CaptionLabel")
		hc.custom_minimum_size = Vector2(66.0, 0.0)
		caps.add_child(hc)
	var tail: Control = UiScreenKit.spacer(0.0)
	tail.custom_minimum_size = Vector2(64.0 if lan == null else 100.0 if role == UiLobbyNet.Role.HOST else 60.0, 0.0)
	caps.add_child(tail)
	body.add_child(caps)
	_rows_box = body
	for i: int in UiLobbyState.MAX_SLOTS:
		var row: UiLobbySlotRow = UiLobbySlotRow.new(i, state)
		row.changed.connect(_on_row_changed)
		row.hovered.connect(_on_row_hovered)
		if lan != null:
			row.kick_requested.connect(_on_kick)
			row.take_requested.connect(func(slot: int) -> void: lan.take(slot))
			row.configure_net(role, lan.local_slot())
		body.add_child(row)
		_rows.append(row)
	_slots_panel.mouse_exited.connect(func() -> void:
		_hover_slot = -1
		_show_briefing())
	return _slots_panel


func _bottom_bar() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var back: Button = UiScreenKit.button("BACK", &"", Vector2(150.0, 46.0))
	back.pressed.connect(func() -> void:
		if lan != null:
			_confirm_leave()
		else:
			back_requested.emit())
	h.add_child(back)
	_status = UiScreenKit.label("", &"DimLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_status)
	_error = UiScreenKit.label("", &"DangerLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error.add_theme_font_size_override("font_size", 16)
	h.add_child(_error)
	if lan != null:
		if not _wide:
			_drawer_button = UiScreenKit.button("CHAT", &"", Vector2(150.0, 46.0))
			_drawer_button.pressed.connect(_toggle_drawer)
			h.add_child(_drawer_button)
		if role == UiLobbyNet.Role.CLIENT:
			_spec_button = UiScreenKit.button("SPECTATE", &"", Vector2(170.0, 46.0))
			_spec_button.pressed.connect(_on_spectate)
			h.add_child(_spec_button)
	_start = UiScreenKit.button("START" if role != UiLobbyNet.Role.CLIENT else "READY", &"PrimaryButton", Vector2(260.0, 52.0))
	_start.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	_start.add_theme_font_size_override("font_size", 20)
	_start.pressed.connect(_on_start)
	h.add_child(_start)
	return h


# ---------------------------------------------------------------- state -> widgets

func _refresh_all() -> void:
	_apply_skin()
	for r: UiLobbySlotRow in _rows:
		r.refresh()
	_map.refresh()
	_rules.refresh()
	_show_briefing()
	_update_status()
	if lan != null:
		_update_lan_widgets()


func _on_state_changed() -> void:
	if lan != null:
		_lan_edit()
		return
	for r: UiLobbySlotRow in _rows:
		r.refresh()
	_update_status()


func _on_row_changed(index: int) -> void:
	if lan != null:
		_focus_slot = index
		_lan_edit()
		return
	_focus_slot = index
	_apply_skin()
	for r: UiLobbySlotRow in _rows:
		r.refresh()
	_map.refresh()
	_show_briefing()
	_update_status()


func _on_row_hovered(index: int) -> void:
	_hover_slot = index
	_show_briefing()


## The lobby wears the skin of the human player's faction (slot 1); Random gives the neutral skin.
func _apply_skin() -> void:
	var f: int = state.slots[_skin_slot()].faction
	var code: String = _data.factions[f].code.to_lower() if f >= 0 and f < _data.factions.size() else ""
	if code == _skin_code:
		return
	_skin_code = code
	UiThemeService.rebuild(UiSkinSet.shared().skin_for(code))


## The slot whose faction dresses the screen: this peer's seat in the LAN roles, else the first slot.
func _skin_slot() -> int:
	if lan != null and lan.local_slot() >= 0:
		return lan.local_slot()
	return 0


func _show_briefing() -> void:
	var slot: int = _hover_slot if _hover_slot >= 0 and state.slots[_hover_slot].active() else _focus_slot
	if not state.slots[slot].active():
		slot = 0
	for i: int in _rows.size():
		_rows[i].focused = i == slot
	var roster: DefRoster = state.preview_roster(slot)
	var note: String = ""
	if roster == null:
		note = "The host draws %s when the match starts." % ["a vanilla roster of a random faction", "a subfaction of a random faction",
			"any of the 32 rosters"][clampi(state.slots[slot].sub, 0, 2)]
	_briefing.show_roster(roster, note)
	_title_badge.faction_code = roster.id.get_slice(".", 1) if roster != null else ""
	_title_badge.muted = roster == null
	_map.set_highlight(slot)


func _update_status() -> void:
	var active: int = state.active_count()
	var open: int = 0
	for s: UiLobbyState.Slot in state.slots:
		if s.kind == UiLobbyState.Kind.OPEN:
			open += 1
	if lan != null:
		var humans: int = 0
		for sl: UiLobbyState.Slot in state.slots:
			if sl.kind == UiLobbyState.Kind.HUMAN:
				humans += 1
		_status.text = "%d players (%d human)  //  %d open  //  data hash %s%s" % [active, humans, open, UiFormatLite.hash8(_data.data_hash()),
			"  //  %d spectator%s" % [state.spectators.size(), "" if state.spectators.size() == 1 else "s"] if state.allow_spectators else ""]
		return
	_status.text = "%d players  //  %d open  //  data hash %s" % [active, open, UiFormatLite.hash8(_data.data_hash())]


# ---------------------------------------------------------------- start

## `--preview=<a,b>` (screenshots): `full` (a 6-player setup), `units` / `powers` (briefing tab), `error` (press START on a
## single-team setup), `popup` (opens the first faction dropdown), `sub` (focus a subfaction slot).
func _debug_preview(spec: String) -> void:
	for tag: String in spec.split(",", false):
		match tag:
			"full":
				state.apply_preset(UiLobbyState.presets()[1] as Dictionary)
				state.set_layout_players(6)
				state.slots[4].kind = UiLobbyState.Kind.AI
				state.slots[5].kind = UiLobbyState.Kind.AI
				for i: int in 6:
					state.slots[i].faction = (i + 3) % _data.factions.size()
					state.slots[i].sub = i % 4
					state.slots[i].team = 1 if i < 3 else 2
				_refresh_all()
			"sub":
				state.slots[0].faction = _faction_by_code("NAPC")
				state.slots[0].sub = 2
				_refresh_all()
			"units":
				_briefing.select_tab(&"units")
			"powers":
				_briefing.select_tab(&"powers")
			"error":
				for i: int in 4:
					state.slots[i].kind = UiLobbyState.Kind.HUMAN if i == 0 else UiLobbyState.Kind.AI
					state.slots[i].team = 1
				_refresh_all()
				_on_start()
			"popup":
				(_rows[1].get_child(0).get_child(3) as OptionButton).show_popup()


func _faction_by_code(code: String) -> int:
	for i: int in _data.factions.size():
		if _data.factions[i].code == code:
			return i
	return 0


func _on_start() -> void:
	if lan != null:
		_lan_start()
		return
	var v: Dictionary = state.validate()
	var err: int = int(v["err"])
	if err != UiLobbyState.Err.OK:
		_show_error(err, int(v.get("slot", -1)), str(v.get("detail", "")))
		return
	state.save()
	var cfg: Dictionary = state.to_config(_rng)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, {"title": "Skirmish"})
	if ctx == null:
		UiDlgMessage.open("Could not start the match", "The session could not be created. See the log for details.")
		return
	navigate.emit(&"loading", {"kind": "match", "title": "Skirmish"})


func _show_error(err: int, slot: int, detail: String) -> void:
	_error.text = UiLobbyState.error_text(err) + ("  " + detail if detail != "" else "")
	_error_t = ERROR_SHOW_S
	match err:
		UiLobbyState.Err.MAP_INVALID, UiLobbyState.Err.TOO_MANY_PLAYERS:
			_map.highlight_error()
		_:
			if slot >= 0 and slot < _rows.size():
				_rows[slot].flash_error()
			else:
				for r: UiLobbySlotRow in _rows:
					if r.index < state.active_count() + 1:
						r.flash_error()


func _process(delta: float) -> void:
	if lan != null:
		lan.tick(delta)
	if _error_t > 0.0:
		_error_t -= delta
		if _error_t <= 0.0:
			_error.text = ""


# ---------------------------------------------------------------- LAN roles

func _viewport_width() -> float:
	if size.x > 100.0:
		return size.x
	var vp: Viewport = get_viewport()
	return vp.get_visible_rect().size.x if vp != null else 1920.0


func _modal(dlg: UiDialog) -> void:
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes") if is_inside_tree() else null
	if scenes != null:
		scenes.call("modal", dlg)


func _lan_subtitle() -> String:
	var who: String = "YOU ARE THE HOST" if role == UiLobbyNet.Role.HOST else "CONNECTED TO THE HOST"
	return "%s  //  %s  //  UP TO 8 COMMANDERS" % [state.lobby_name.to_upper() if state.lobby_name != "" else "LAN GAME", who]


func _lan_chips() -> Control:
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = &"InsetPanel"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c: HBoxContainer = HBoxContainer.new()
	c.add_theme_constant_override("separation", 22)
	chip.add_child(c)
	c.add_child(UiScreenKit.label("DATA HASH  " + UiFormatLite.hash8(_data.data_hash()), &"CaptionLabel"))
	_ping_chip = UiScreenKit.label("HOST" if role == UiLobbyNet.Role.HOST else "PING  --", &"CaptionLabel")
	c.add_child(_ping_chip)
	return chip


## The right column: lobby info, the spectators and the chat.
func _lan_column() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info: Dictionary = UiScreenKit.panel("Lobby", "LAN", &"", 12, 4)
	var box: VBoxContainer = info["body"] as VBoxContainer
	for key: String in ["name", "address", "access", "spectators"]:
		var line: HBoxContainer = HBoxContainer.new()
		var cap: Label = UiScreenKit.label(key.to_upper(), &"CaptionLabel")
		cap.custom_minimum_size = Vector2(92.0, 0.0)
		line.add_child(cap)
		var val: Label = UiScreenKit.label("-", &"SubLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(val)
		box.add_child(line)
		_info_labels[key] = val
	_spec_list = UiScreenKit.label("", &"DimLabel", true)
	box.add_child(_spec_list)
	col.add_child(info["panel"] as Control)
	chat = UiLobbyChat.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.submitted.connect(func(text: String, team_only: bool) -> void: lan.send_chat(text, team_only))
	col.add_child(chat)
	return col


func _make_drawer() -> void:
	_drawer = PanelContainer.new()
	_drawer.theme_type_variation = &"PopupPanel"
	_drawer.visible = false
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_drawer)
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_drawer.offset_left = -500.0
	_drawer.offset_top = -690.0
	_drawer.offset_right = -56.0
	_drawer.offset_bottom = -96.0
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	_drawer.add_child(m)
	m.add_child(_lan_col)


func _toggle_drawer() -> void:
	if _drawer == null:
		return
	_drawer.visible = not _drawer.visible
	if _drawer.visible and chat != null:
		chat.focus_input()
	_update_drawer_button()


func _update_drawer_button() -> void:
	if _drawer_button == null or chat == null:
		return
	_drawer_button.text = "CHAT" if chat.unread == 0 or _drawer.visible else "CHAT (%d)" % chat.unread


func _countdown_overlay() -> Control:
	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()  # opaque: the locked lobby behind it must not show through the digits
	sb.bg_color = UiPalette.BG_RAISED
	sb.border_color = UiScreenKit.accent(self)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(p)
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	p.add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	v.add_child(UiScreenKit.label("MATCH STARTS IN", &"CaptionLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	_countdown_label = UiScreenKit.wordmark("3", 96, 800, 4, UiPalette.TEXT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_countdown_label)
	v.add_child(UiScreenKit.label("The settings are locked. Un-ready or cancel to stop.", &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	return center


func _lan_wire(session: NetSession) -> void:
	lan.refreshed.connect(_on_lan_refreshed)
	lan.notice.connect(_flash_notice)
	session.countdown_changed.connect(_on_countdown)
	session.chat_received.connect(_on_chat)
	session.launch_aborted.connect(_on_launch_aborted)
	chat.add_line(0, 255, "", "Welcome to %s. Press Enter to chat; Shift+Enter talks to your team only." % (state.lobby_name if state.lobby_name != "" else "the lobby"))
	if lan.counting_down():
		_on_countdown(NetProtocol.COUNTDOWN_S)


func _lan_unwire() -> void:
	var s: NetSession = lan.session
	if s != null:
		if s.countdown_changed.is_connected(_on_countdown):
			s.countdown_changed.disconnect(_on_countdown)
		if s.chat_received.is_connected(_on_chat):
			s.chat_received.disconnect(_on_chat)
		if s.launch_aborted.is_connected(_on_launch_aborted):
			s.launch_aborted.disconnect(_on_launch_aborted)
	if lan.refreshed.is_connected(_on_lan_refreshed):
		lan.refreshed.disconnect(_on_lan_refreshed)
	lan.release()


## The authoritative lobby changed: rows, map, rules, briefing and the LAN widgets follow.
func _on_lan_refreshed() -> void:
	if _rows.is_empty():
		return
	var seat: int = lan.local_slot()
	for r: UiLobbySlotRow in _rows:
		r.local_slot = seat
		r.refresh()
	_apply_skin()
	_map.refresh()
	_rules.refresh()
	_show_briefing()
	_update_status()
	_update_lan_widgets()


## Settings are editable for the host while the lobby is open; everything else is read-only.
func _apply_read_only() -> void:
	var edit: bool = role == UiLobbyNet.Role.HOST and lan.open_for_edits()
	_map.set_editable(edit)
	_rules.set_editable(edit)


func _update_lan_widgets() -> void:
	_apply_read_only()
	_title_sub.text = _lan_subtitle()
	if role == UiLobbyNet.Role.CLIENT:
		var ping: int = lan.my_ping_ms()
		_ping_chip.text = "PING  %d ms" % ping if ping > 0 else "PING  --"
	var counting: bool = lan.counting_down()
	if role == UiLobbyNet.Role.HOST:
		_start.text = "CANCEL START" if counting else "START"
		_start.theme_type_variation = &"" if counting else &"PrimaryButton"
	else:
		if lan.is_spectator():
			_start.text = "TAKE A SLOT"
			_start.disabled = state.layout_players() <= 0 or lan.state().first_open_slot() < 0
		else:
			_start.text = "CANCEL READY" if lan.is_ready() else "READY UP"
			_start.disabled = lan.local_slot() < 0
		_spec_button.visible = state.allow_spectators and not lan.is_spectator()
		_spec_button.disabled = counting
	# lobby info
	(_info_labels["name"] as Label).text = state.lobby_name if state.lobby_name != "" else "-"
	var addr: String = "-"
	if role == UiLobbyNet.Role.HOST:
		var list: PackedStringArray = lan.session.advertised_addresses()
		addr = list[0] if not list.is_empty() else "127.0.0.1:%d" % lan.session.transport.local_port() if lan.session.transport != null else "-"
	else:
		addr = "connected"
	(_info_labels["address"] as Label).text = _address_override if _address_override != "" and role == UiLobbyNet.Role.HOST else addr
	(_info_labels["access"] as Label).text = "Password" if state.password_set else "Open to the network"
	(_info_labels["spectators"] as Label).text = "Allowed" if state.allow_spectators else "Closed"
	if state.spectators.is_empty():
		_spec_list.text = "No spectators." if state.allow_spectators else ""
	else:
		var names: PackedStringArray = PackedStringArray()
		for sp: Variant in state.spectators:
			names.append(str((sp as Dictionary).get("name", "?")))
		_spec_list.text = "Spectating: " + ", ".join(names)
	_update_drawer_button()
	if not counting and _countdown != null:
		_countdown.visible = false


## A widget edit happened (a row picker, the map, a rule): send it to the lobby.
func _lan_edit() -> void:
	if not lan.open_for_edits():
		lan.pull()
		return
	var gone: PackedInt32Array = lan.removals()
	if not gone.is_empty():
		_confirm_removal(gone[0])
		return
	_apply_skin()
	_show_briefing()
	lan.push()
	if role == UiLobbyNet.Role.CLIENT:
		_update_status()


func _confirm_removal(slot: int) -> void:
	var who: String = lan.state().slots[slot].name
	var d: UiDlgConfirm = UiDlgConfirm.new("Remove player", "Remove %s from the game to make this change?" % who, "Remove", "Keep", true)
	d.closed.connect(func(result_code: int) -> void:
		if result_code == 1:
			lan.push()
		else:
			lan.pull())
	_modal(d)


func _on_kick(index: int) -> void:
	var who: String = lan.state().slots[index].name
	var d: UiDialog = UiDialog.new("Remove player", 460)
	d.add_text("Remove %s from the game? They can join again unless you ban them for this session." % who)
	var ban: CheckBox = CheckBox.new()
	ban.text = "Ban for this session"
	d.set_content(ban)
	d.add_button("Keep", 0)
	d.add_button("Remove", 1, &"danger")
	d.closed.connect(func(result_code: int) -> void:
		if result_code == 1:
			lan.kick(index, ban.button_pressed))
	_modal(d)


func _on_spectate() -> void:
	lan.spectate()


func _lan_start() -> void:
	if role == UiLobbyNet.Role.HOST:
		if lan.counting_down():
			lan.cancel_start()
			return
		var err: int = lan.start()
		if err != NetLobby.StartError.OK:
			_show_lan_error(err)
		return
	if lan.is_spectator():
		lan.play()
		return
	lan.toggle_ready()


func _show_lan_error(err: int) -> void:
	if err == NetLobby.StartError.ALREADY_LAUNCHING:
		return
	var text: String = _lan_error_text(err)
	_error.text = text
	_error_t = ERROR_SHOW_S
	match err:
		UiLobbyState.Err.MAP_INVALID, UiLobbyState.Err.TOO_MANY_PLAYERS:
			_map.highlight_error()
		_:
			for i: int in UiLobbyNet.error_rows(err, state):
				_rows[i].flash_error()


func _lan_error_text(err: int) -> String:
	var rows: PackedInt32Array = UiLobbyNet.error_rows(err, state)
	var names: PackedStringArray = PackedStringArray()
	for i: int in rows:
		names.append(state.slots[i].name)
	match err:
		UiLobbyState.Err.HUMAN_NOT_READY:
			return "Waiting for %s to be ready." % ", ".join(names) if not names.is_empty() else "A player is not ready."
		UiLobbyState.Err.HUMAN_DISCONNECTED:
			return "%s disconnected." % ", ".join(names) if not names.is_empty() else "A player has disconnected."
		UiLobbyState.Err.MAP_INVALID:
			return UiLobbyState.error_text(err) + "  " + MapGenerator.validate_params(state.family, state.size, state.layout_players())
	var t: String = UiLobbyState.error_text(err)
	return t if t != "Cannot start." else NetLobby.start_error_text(err)


func _flash_notice(text: String) -> void:
	_error.text = text
	_error_t = ERROR_SHOW_S


func _on_countdown(seconds_left: int) -> void:
	if _countdown == null:
		return
	_countdown.visible = seconds_left > 0
	if seconds_left > 0:
		_countdown_label.text = str(seconds_left)
	_update_lan_widgets()


func _on_chat(channel: int, from_slot: int, from_name: String, text: String) -> void:
	if chat == null:
		return
	var col: Color = Color.WHITE
	if from_slot >= 0 and from_slot < UiLobbyState.MAX_SLOTS:
		col = UiPalette.team(state.slots[from_slot].color)
	chat.add_line(channel, from_slot, from_name, text, col)
	_update_drawer_button()


func _on_launch_aborted(reason: int, detail: String) -> void:
	_modal(UiDlgJoinRejected.for_abort(reason, detail))
	_on_countdown(0)


## BACK in the LAN roles: the host closes the game for everybody, a client just leaves.
func _confirm_leave() -> void:
	var host: bool = role == UiLobbyNet.Role.HOST
	var d: UiDlgConfirm = UiDlgConfirm.new("Close the game" if host else "Leave the game",
		"You are the host. Leaving closes the game for everybody." if host else "Leave this lobby and go back to the game list?",
		"Close game" if host else "Leave", "Stay", true)
	d.closed.connect(func(result_code: int) -> void:
		if result_code == 1:
			leave_now())
	_modal(d)


## Leaves the LAN session and returns to the browser (no question asked).
func leave_now() -> void:
	AppLan.leave()
	back_requested.emit()
