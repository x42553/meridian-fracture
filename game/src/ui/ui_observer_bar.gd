class_name UiObserverBar
extends VBoxContainer
## The observer panel (ui.md 5.16.3, task REP2): it takes the place of the build area of the sidebar when the HUD is in observer mode
## (replays, all-AI sessions, defeated or surrendered players). The first row is "ALL PLAYERS (fog off)", then one row per player with
## colour, emblem, name, team and the live numbers (credits, income per minute, army value and size, structures); a click or the keys
## 1..8 / 0 / Tab choose the perspective (whose vision the world and the minimap show); FOLLOW lets the camera trail that player's
## army; SCOREBOARD opens the F2 table. Pure presentation: rows come from `UiObserverModel`, choices go out through the signals.

signal perspective_requested(pid: int)
signal follow_toggled(on: bool)
signal scoreboard_requested()

const ROW_H: float = 52.0

var perspective: int = -1
var follow: bool = false

var _rows_box: VBoxContainer = null
var _all: PlayerRow = null
var _player_rows: Dictionary = {}
var _follow_btn: Button = null
var _score_btn: Button = null
var _hint: Label = null


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "OBSERVER"
	head.add_child(title)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	_hint = Label.new()
	_hint.theme_type_variation = &"DimLabel"
	head.add_child(_hint)
	add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)
	_all = PlayerRow.new()
	_all.is_all = true
	_all.pressed.connect(func() -> void: perspective_requested.emit(-1))
	_rows_box.add_child(_all)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	add_child(foot)
	_follow_btn = UiScreenKit.button("FOLLOW  C", &"", Vector2(0.0, 34.0))
	_follow_btn.toggle_mode = true
	_follow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_follow_btn.tooltip_text = "The camera trails the army of the viewed player."
	_follow_btn.toggled.connect(func(on: bool) -> void:
		follow = on
		_follow_btn.text = "FOLLOW  C  ON" if on else "FOLLOW  C"
		follow_toggled.emit(on))
	foot.add_child(_follow_btn)
	_score_btn = UiScreenKit.button("SCOREBOARD  F2", &"", Vector2(0.0, 34.0))
	_score_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_btn.pressed.connect(func() -> void: scoreboard_requested.emit())
	foot.add_child(_score_btn)
	_refresh_state()


## Feeds the rows (`UiObserverModel.rows`): rows are created for new pids, existing ones are updated in place.
func set_rows(rows: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	for r: Dictionary in rows:
		var pid: int = int(r["pid"])
		seen[pid] = true
		var node: PlayerRow = _player_rows.get(pid) as PlayerRow
		if node == null:
			node = PlayerRow.new()
			node.pid = pid
			node.pressed.connect(func() -> void: perspective_requested.emit(pid))
			_player_rows[pid] = node
			_rows_box.add_child(node)
		node.set_data(r)
	for k: Variant in _player_rows.keys():
		if not seen.has(k):
			(_player_rows[k] as PlayerRow).queue_free()
			_player_rows.erase(k)
	var ids: Array = _player_rows.keys()
	ids.sort()
	for i: int in ids.size():
		_rows_box.move_child(_player_rows[ids[i]] as Node, i + 1)
	_all.set_summary(rows.size())
	_refresh_state()


func set_perspective(pid: int) -> void:
	perspective = pid
	_refresh_state()


func set_follow(on: bool) -> void:
	follow = on
	if _follow_btn != null:
		_follow_btn.set_pressed_no_signal(on)
		_follow_btn.text = "FOLLOW  C  ON" if on else "FOLLOW  C"


func row_count() -> int:
	return _player_rows.size()


func row_node(pid: int) -> Control:
	return _player_rows.get(pid) as Control


func all_row() -> Control:
	return _all


func _refresh_state() -> void:
	if _all == null:
		return
	_all.selected = perspective < 0
	for k: Variant in _player_rows:
		(_player_rows[k] as PlayerRow).selected = int(k) == perspective
	var who: PlayerRow = _player_rows.get(perspective) as PlayerRow
	_hint.text = "ALL  //  FOG OFF" if perspective < 0 else ("VIEW  " + (who.player_name.to_upper() if who != null else str(perspective + 1)))


## One row: "ALL PLAYERS" (`is_all`) or a player.
class PlayerRow extends Control:
	signal pressed()

	var pid: int = -1
	var is_all: bool = false
	var player_name: String = ""
	var selected: bool = false:
		set(v):
			if v != selected:
				selected = v
				queue_redraw()
	var data: Dictionary = {}
	var _hover: bool = false
	var _badge: UiFactionBadge = null
	var _count: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, ROW_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_summary(players: int) -> void:
		_count = players
		queue_redraw()

	func set_data(d: Dictionary) -> void:
		data = d
		player_name = str(d.get("name", ""))
		accessibility_name = player_name
		if _badge == null:
			_badge = UiFactionBadge.new(str(d.get("faction", "")), 30.0)
			_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_badge.position = Vector2(14.0, (ROW_H - 30.0) * 0.5 - 2.0)
			add_child(_badge)
		_badge.faction_code = str(d.get("faction", ""))
		_badge.muted = not bool(d.get("active", true))
		queue_redraw()

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER:
				_hover = true
				queue_redraw()
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				queue_redraw()
			NOTIFICATION_THEME_CHANGED, NOTIFICATION_RESIZED:
				queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var bg: Color = Color(1.0, 1.0, 1.0, 0.035)
		if selected:
			bg = Color(acc, 0.20)
		elif _hover:
			bg = Color(acc, 0.10)
		draw_rect(r, bg)
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.05))
		var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
		var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
		var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
		var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
		if is_all:
			draw_rect(Rect2(0.0, 0.0, 5.0, size.y), acc if selected else UiPalette.LINE_DIM)
			draw_string(head, Vector2(16.0, 24.0), "ALL PLAYERS", HORIZONTAL_ALIGNMENT_LEFT, size.x - 60.0, 15, UiPalette.TEXT if selected else UiPalette.TEXT_DIM)
			draw_string(body, Vector2(16.0, 43.0), "Fog off: the whole map, %d commanders" % _count, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60.0, 14, UiPalette.TEXT_MUTE)
			draw_string(num, Vector2(size.x - 34.0, 24.0), "[0]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
			if selected:
				draw_rect(Rect2(0.0, 0.0, size.x, size.y), Color(acc, 0.5), false, 1.0)
			return
		var active: bool = bool(data.get("active", true))
		var col: Color = UiPalette.team(int(data.get("color", 0)))
		var tint: float = 1.0 if active else 0.45
		draw_rect(Rect2(0.0, 0.0, 5.0, size.y), Color(col, tint))
		var x0: float = 54.0
		var name_col: Color = UiPalette.TEXT if active else UiPalette.TEXT_DISABLED
		draw_string(bold, Vector2(x0, 21.0), player_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - x0 - 78.0, 16, name_col)
		var team: int = int(data.get("team", 0))
		var tail: String = "T%d" % team if team >= 1 and team <= 4 else ""
		if not active:
			draw_string(head, Vector2(size.x - 102.0, 21.0), "OUT", HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 13, UiPalette.semantic(&"danger"))
		elif tail != "":
			draw_string(head, Vector2(size.x - 102.0, 21.0), tail, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 13, UiPalette.TEXT_DIM)
		if pid >= 0 and pid < 8:
			draw_string(num, Vector2(size.x - 30.0, 21.0), "[%d]" % (pid + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
		var y2: float = 40.0
		var cw: float = (size.x - x0 - 10.0) / 4.0
		var vals: Array[String] = ["$%s" % _short(int(data.get("credits", 0))), "+%s/m" % _short(int(data.get("income", 0))),
			"A %s" % _short(int(data.get("army_value", 0))), "S %d" % int(data.get("structs", 0))]
		var cols: Array[Color] = [UiPalette.semantic(&"warn"), UiPalette.semantic(&"ok"), UiPalette.TEXT, UiPalette.TEXT_DIM]
		for i: int in 4:
			draw_string(num, Vector2(x0 + cw * float(i), y2), vals[i], HORIZONTAL_ALIGNMENT_LEFT, cw - 4.0, 13, cols[i] if active else UiPalette.TEXT_DISABLED)
		var share: float = float(int(data.get("share", 0))) / 1000.0
		draw_rect(Rect2(x0, size.y - 5.0, size.x - x0 - 10.0, 2.0), Color(1.0, 1.0, 1.0, 0.06))
		draw_rect(Rect2(x0, size.y - 5.0, (size.x - x0 - 10.0) * share, 2.0), Color(col, tint))
		if selected:
			draw_rect(r, Color(acc, 0.5), false, 1.0)

	## 4250 -> "4.2k", 820 -> "820", 1200000 -> "1.2M".
	static func _short(n: int) -> String:
		if n >= 1000000:
			return "%.1fM" % (float(n) / 1000000.0)
		if n >= 10000:
			return "%dk" % (n / 1000)
		if n >= 1000:
			return "%.1fk" % (float(n) / 1000.0)
		return str(n)
