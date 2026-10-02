class_name UiLobbySlotRow
extends PanelContainer
## One player slot of the lobby table (ui.md 5.14.2, LOCAL role): colour swatch (click = next colour, conflicts swap), slot
## number, faction emblem, type (AI level / open / closed), faction and subfaction pickers, team, start position and a status
## word. Edits go to the `UiLobbyState` and are announced with `changed(index)`; `hovered(index)` drives the briefing. Pickers are
## real `OptionButton`s with `fit_to_longest_item = false` and clipped text.
## LAN roles (`configure_net`): the same row with a handicap chip, the ready / ping status, a kick button (host, remote humans) and a
## take-slot button (client, open rows). The host edits every seated row, a client only its own (`UiLobbyNet.can_edit_row`); the type
## picker of a seated human shows its name and only the host can turn it into Open / Closed / AI (which removes the player).

signal changed(index: int)
signal hovered(index: int)
## LAN roles: the host's kick button of a remote human, and the "take this slot" button a client sees on an open row.
signal kick_requested(index: int)
signal take_requested(index: int)

## The lobby table is packed a little tighter than `UiMetrics.LOBBY_ROW_H` so eight rows and the briefing fit 1080 px.
const ROW_H: float = 44.0
## Picker columns: minimum width and stretch ratio (the row shrinks to fit 1280 x 720 windows and grows on wide ones).
const COL_TYPE: float = 126.0
const COL_FACTION: float = 176.0
const COL_SUB: float = 136.0
const COL_TEAM: float = 100.0
const COL_START: float = 92.0
const RATIO: Array[float] = [1.0, 1.9, 1.3, 1.0, 0.8]
## LAN rows carry a handicap chip, a status block and a kick button, so the picker columns are narrower (type keeps its width: it shows the
## player's name).
const LAN_SCALE: Array[float] = [1.0, 0.8, 0.8, 0.95, 0.95]
## Width of the swatch + emblem block in front of the pickers.
const LEAD_W: float = 88.0

var index: int = 0
## `UiLobbyNet.Role` (LOCAL = the skirmish rows) and the slot of this peer (-1 = spectator / none).
var role: int = 0
var local_slot: int = -1
var focused: bool = false:
	set(v):
		focused = v
		queue_redraw()

var _state: UiLobbyState = null
var _swatch: Button = null
var _badge: UiFactionBadge = null
var _type: OptionButton = null
var _faction: OptionButton = null
var _sub: OptionButton = null
var _team: OptionButton = null
var _start: OptionButton = null
var _status: Label = null
var _ping: Label = null
var _hcp: OptionButton = null
var _kick: Button = null
var _take: Button = null
var _cols: Array[OptionButton] = []
var _building: bool = false
var _flash: float = 0.0
var _sig: String = ""


func _init(p_index: int = 0, state: UiLobbyState = null) -> void:
	index = p_index
	_state = state
	theme_type_variation = &"InsetPanel"
	custom_minimum_size = Vector2(0.0, ROW_H)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	_swatch = Button.new()
	_swatch.custom_minimum_size = Vector2(32.0, 32.0)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.tooltip_text = "Click to change the colour"
	_swatch.pressed.connect(_on_swatch)
	h.add_child(_swatch)
	_badge = UiFactionBadge.new("", 36.0)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_badge)
	_type = _picker(COL_TYPE, RATIO[0])
	h.add_child(_type)
	_faction = _picker(COL_FACTION, RATIO[1])
	h.add_child(_faction)
	_sub = _picker(COL_SUB, RATIO[2])
	h.add_child(_sub)
	_team = _picker(COL_TEAM, RATIO[3])
	h.add_child(_team)
	_start = _picker(COL_START, RATIO[4])
	h.add_child(_start)
	_hcp = OptionButton.new()
	_hcp.fit_to_longest_item = false
	_hcp.custom_minimum_size = Vector2(66.0, 34.0)
	_hcp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hcp.tooltip_text = "Handicap: scales the player's income and build speed"
	_hcp.visible = false
	h.add_child(_hcp)
	var status_box: VBoxContainer = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", -3)
	status_box.custom_minimum_size = Vector2(60.0, 0.0)
	status_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(status_box)
	_status = UiScreenKit.label("", &"OkLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_box.add_child(_status)
	_ping = UiScreenKit.label("", &"CaptionLabel")
	_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping.visible = false
	status_box.add_child(_ping)
	_take = UiScreenKit.button("TAKE", &"", Vector2(64.0, 30.0))
	_take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_take.tooltip_text = "Move to this slot"
	_take.visible = false
	_take.pressed.connect(func() -> void: take_requested.emit(index))
	h.add_child(_take)
	_kick = UiScreenKit.button("X", &"DangerButton", Vector2(34.0, 30.0))
	_kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kick.tooltip_text = "Remove this player"
	_kick.visible = false
	_kick.pressed.connect(func() -> void: kick_requested.emit(index))
	h.add_child(_kick)
	_cols = [_type, _faction, _sub, _team, _start]
	for hc: int in [50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 175, 200]:
		_hcp.add_item("%d%%" % hc, hc)
	_hcp.item_selected.connect(_on_handicap)
	_type.item_selected.connect(_on_type)
	_faction.item_selected.connect(_on_faction)
	_sub.item_selected.connect(_on_sub)
	_team.item_selected.connect(_on_team)
	_start.item_selected.connect(_on_start)
	mouse_entered.connect(func() -> void: hovered.emit(index))
	for c: OptionButton in [_type, _faction, _sub, _team, _start]:
		c.mouse_entered.connect(func() -> void: hovered.emit(index))
	_fill_static()
	refresh()


func _picker(width: float, ratio: float) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	o.fit_to_longest_item = false
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # long faction names end in an ellipsis, not mid-word
	o.custom_minimum_size = Vector2(width, 34.0)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.size_flags_stretch_ratio = ratio
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return o


func _fill_static() -> void:
	_building = true
	_type.clear()
	if index == 0:
		_type.add_item("Human", 0)
	else:
		for lv: int in UiLobbyState.AI_LEVELS.size():
			_type.add_item("AI - " + UiLobbyState.AI_LEVELS[lv], lv)
		_type.add_item("Open", 4)
		_type.add_item("Closed", 5)
	_faction.clear()
	var data: GameData = _state.data()
	for i: int in _state.faction_count():
		_faction.add_item("%s   %s" % [data.factions[i].code, data.factions[i].ui_name], i)
	_faction.add_item("Random", 99)
	_team.clear()
	for i: int in UiLobbyState.TEAMS.size():
		_team.add_item(UiLobbyState.TEAMS[i], i)
	_building = false


## LAN roles: sets the role and the seat of this peer, shows the LAN-only controls and narrows the pickers so a row with the extra
## columns still fits the left column (`UiLobbyNet.Role`; call again when the seat changes).
func configure_net(p_role: int, p_local_slot: int) -> void:
	role = p_role
	local_slot = p_local_slot
	var lan: bool = role != UiLobbyNet.Role.LOCAL
	var bases: Array[float] = [COL_TYPE, COL_FACTION, COL_SUB, COL_TEAM, COL_START]
	for i: int in _cols.size():
		_cols[i].custom_minimum_size.x = bases[i] * (LAN_SCALE[i] if lan else 1.0)
	_hcp.visible = lan
	_ping.visible = lan
	_sig = ""
	refresh()


## LAN: whether this row's pickers accept edits from this peer.
func editable() -> bool:
	if role == UiLobbyNet.Role.LOCAL:
		return _state.slots[index].active()
	return UiLobbyNet.can_edit_row(role, index, local_slot, _state)


## Widgets <- state (no `changed` emission). In the LAN roles the pickers are only rebuilt when the slot really changed (a ping
## update must not close a dropdown the user is looking at); the status and ping labels always update.
func refresh() -> void:
	var lan: bool = role != UiLobbyNet.Role.LOCAL
	var st: UiLobbyState.Slot = _state.slots[index]
	if lan:
		var sig: String = "%d|%d|%d|%d|%d|%d|%d|%d|%s|%d|%d|%d|%d|%d|%d" % [st.kind, st.ai_level, st.faction, st.sub, st.team, st.color, st.start,
			st.handicap, st.name, st.peer_id, int(st.connected), role, local_slot, _state.layout_players(), _state.faction_count()]
		if sig == _sig:
			_refresh_status(st)
			return
		_sig = sig
	_building = true
	var s: UiLobbyState.Slot = st
	var active: bool = s.active()
	_swatch.visible = active
	_swatch.text = str(index + 1)
	if active:
		var col: Color = UiPalette.team(s.color)
		_swatch_style(col)
	_badge.muted = not active
	var f: int = s.faction
	_badge.faction_code = _state.data().factions[f].code if active and f >= 0 and f < _state.faction_count() else ""
	var pr: DefRoster = _state.preview_roster(index)
	_badge.sub_key = ""
	if active and pr != null and not pr.is_vanilla:
		var ps: PackedStringArray = pr.id.split(".")
		_badge.sub_key = "%s.%s" % [ps[1], ps[2]]
	# type
	if lan:
		_refresh_type_net(s)
	elif index == 0:
		_type.select(0)
		_type.disabled = true
	else:
		match s.kind:
			UiLobbyState.Kind.AI:
				_type.select(s.ai_level)
			UiLobbyState.Kind.OPEN:
				_type.select(_type.get_item_index(4))
			_:
				_type.select(_type.get_item_index(5))
	# faction / sub
	var can: bool = active if not lan else UiLobbyNet.can_edit_row(role, index, local_slot, _state)
	_faction.disabled = not can
	_sub.disabled = not can
	_team.disabled = not can
	_start.disabled = not can
	_swatch.disabled = lan and not can
	_faction.select(_faction.get_item_index(99) if f < 0 else _faction.get_item_index(f))
	_sub.clear()
	var subs: PackedStringArray = _state.sub_options(f)
	for i: int in subs.size():
		_sub.add_item(subs[i], i)
	_sub.select(clampi(s.sub, 0, subs.size() - 1))
	_team.select(s.team)
	_start.clear()
	_start.add_item("Auto", 0)
	for i: int in _state.layout_players():
		_start.add_item("Start %d" % (i + 1), i + 1)
	_start.select(clampi(s.start + 1, 0, _start.item_count - 1))
	# status
	_refresh_status(s)
	if lan:
		_hcp.visible = active
		_hcp.disabled = role != UiLobbyNet.Role.HOST
		_hcp.select(_hcp.get_item_index(s.handicap) if _hcp.get_item_index(s.handicap) >= 0 else _hcp.get_item_index(100))
		_kick.visible = role == UiLobbyNet.Role.HOST and s.kind == UiLobbyState.Kind.HUMAN and s.peer_id != 1
		_take.visible = role == UiLobbyNet.Role.CLIENT and s.kind == UiLobbyState.Kind.OPEN
	modulate = Color(1, 1, 1, 1) if active or s.kind == UiLobbyState.Kind.OPEN else Color(1, 1, 1, 0.7)
	_building = false


## The type picker of a LAN row: AI levels, Open, Closed, plus the seated player's name as the selected item.
func _refresh_type_net(s: UiLobbyState.Slot) -> void:
	_type.clear()
	for lv: int in UiLobbyState.AI_LEVELS.size():
		_type.add_item("AI - " + UiLobbyState.AI_LEVELS[lv], lv)
	_type.add_item("Open", 4)
	_type.add_item("Closed", 5)
	if s.kind == UiLobbyState.Kind.HUMAN:
		_type.add_item(s.name, 6)
		_type.select(_type.get_item_index(6))
		_type.tooltip_text = "You" if index == local_slot else ("The host" if s.peer_id == 1 else "A player on another computer")
	else:
		match s.kind:
			UiLobbyState.Kind.AI:
				_type.select(s.ai_level)
			UiLobbyState.Kind.OPEN:
				_type.select(_type.get_item_index(4))
			_:
				_type.select(_type.get_item_index(5))
	if s.kind != UiLobbyState.Kind.HUMAN:
		_type.tooltip_text = ""
	_type.disabled = not UiLobbyNet.can_edit_kind(role, index, local_slot)


## READY / NOT READY / DISCONNECTED / OPEN ... and the ping under it.
func _refresh_status(s: UiLobbyState.Slot) -> void:
	if role != UiLobbyNet.Role.LOCAL:
		var d: Dictionary = UiLobbyNet.status_of(s)
		_status.text = str(d["text"])
		_status.theme_type_variation = d["variation"] as StringName
		_ping.text = UiLobbyNet.ping_text(s)
		return
	match s.kind:
		UiLobbyState.Kind.HUMAN:
			_status.text = "YOU"
			_status.theme_type_variation = &"OkLabel"
		UiLobbyState.Kind.AI:
			_status.text = "READY"
			_status.theme_type_variation = &"OkLabel"
		UiLobbyState.Kind.OPEN:
			_status.text = "OPEN"
			_status.theme_type_variation = &"MuteLabel"
		_:
			_status.text = "CLOSED"
			_status.theme_type_variation = &"MuteLabel"


func _swatch_style(col: Color) -> void:
	for state_name: String in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = col if state_name != "hover" else col.lightened(0.15)
		sb.border_color = Color(1, 1, 1, 0.85) if state_name == "focus" else Color(0, 0, 0, 0.55)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(3)
		_swatch.add_theme_stylebox_override(state_name, sb)
	_swatch.add_theme_color_override("font_color", Color(0.05, 0.06, 0.08))
	_swatch.add_theme_color_override("font_hover_color", Color(0.05, 0.06, 0.08))
	_swatch.add_theme_color_override("font_pressed_color", Color(0.05, 0.06, 0.08))
	_swatch.add_theme_color_override("font_focus_color", Color(0.05, 0.06, 0.08))


func _on_swatch() -> void:
	if _building:
		return
	_state.set_color(index, _state.slots[index].color + 1)
	changed.emit(index)


func _on_type(i: int) -> void:
	if _building:
		return
	var id: int = _type.get_item_id(i)
	if id == 6:
		return  # the seated player's own entry
	if id <= 3:
		_state.slots[index].kind = UiLobbyState.Kind.AI
		_state.slots[index].ai_level = id
	elif id == 4:
		_state.slots[index].kind = UiLobbyState.Kind.OPEN
	else:
		_state.slots[index].kind = UiLobbyState.Kind.CLOSED
	_state.fix_size()
	changed.emit(index)


func _on_handicap(i: int) -> void:
	if _building:
		return
	_state.slots[index].handicap = _hcp.get_item_id(i)
	changed.emit(index)


func _on_faction(i: int) -> void:
	if _building:
		return
	var id: int = _faction.get_item_id(i)
	_state.slots[index].faction = -1 if id == 99 else id
	_state.slots[index].sub = 0
	changed.emit(index)


func _on_sub(i: int) -> void:
	if _building:
		return
	_state.slots[index].sub = i
	changed.emit(index)


func _on_team(i: int) -> void:
	if _building:
		return
	_state.slots[index].team = i
	changed.emit(index)


func _on_start(i: int) -> void:
	if _building:
		return
	_state.slots[index].start = _start.get_item_id(i) - 1
	changed.emit(index)


## Start error highlight: the row pulses red twice (5.14.4).
func flash_error() -> void:
	_flash = 1.0
	var tw: Tween = create_tween()
	for _i: int in 2:
		tw.tween_property(self, "_flash", 1.0, 0.0)
		tw.tween_property(self, "_flash", 0.0, 0.5)
	tw.tween_callback(queue_redraw)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)


func _draw() -> void:
	if focused:
		draw_rect(Rect2(Vector2.ZERO, size), UiScreenKit.accent(self), false, 1.5)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiPalette.semantic(&"danger"), 0.28 * _flash))
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiPalette.semantic(&"danger"), _flash), false, 2.0)
