class_name UiMatchChat
extends VBoxContainer
## In-match chat (LAN matches; Enter = everybody, Shift+Enter = team): the last few lines fade out after `life_s` seconds (settings
## `ui/chat_fade_s`, `ui/chat_opacity`) and a one-line input opens on the hotkey. While the input has focus the input controller ignores
## the keymap (`UiInputController.keys_ok`), so typing "s" never issues a stop order. Enter sends, Shift+Enter sends to the team only,
## Escape closes the input. Text is plain (labels never parse markup) and capped at the wire limit; the network sanitises it again.
## `submitted(text, team_only)` is the only output; the screen forwards it to `NetSession.send_chat`. Mouse-transparent except the input.

signal submitted(text: String, team_only: bool)
signal closed()

const MAX_LINES: int = 8
const FADE_S: float = 1.0

var life_s: float = 8.0
var opacity: float = 0.85

var _lines: Array[Dictionary] = []  ## {label: Label, born: int (msec), text: String}
var _input: LineEdit = null
var _team: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(460.0, 0.0)
	_input = LineEdit.new()
	_input.max_length = NetProtocol.CHAT_MAX_BYTES
	_input.custom_minimum_size = Vector2(0.0, 34.0)
	_input.visible = false
	_input.context_menu_enabled = false
	_input.gui_input.connect(_on_input_event)
	_input.text_submitted.connect(func(t: String) -> void: _submit(t, _team))
	add_child(_input)
	set_process(false)


## Reads the fade time and opacity settings (a missing store keeps the defaults).
func apply_settings(fade_s: int, opacity_pct: int) -> void:
	life_s = float(clampi(fade_s, 3, 30))
	opacity = float(clampi(opacity_pct, 20, 100)) / 100.0


func is_open() -> bool:
	return _input.visible


func line_count() -> int:
	return _lines.size()


func line_text(i: int) -> String:
	return String(_lines[i]["text"])


## Opens the input (everybody, or the team only).
func open(team_only: bool) -> void:
	_team = team_only
	_input.placeholder_text = "Message to your team ..." if team_only else "Message to everybody ..."
	_input.visible = true
	_input.clear()
	if _input.is_inside_tree():
		_input.grab_focus()
	set_process(true)


## Closes the input without sending (the focus goes back to the world).
func close() -> void:
	if not _input.visible:
		return
	_input.clear()
	_input.release_focus()
	_input.visible = false
	closed.emit()


## Types into the open input (tests).
func set_input_text(text: String) -> void:
	_input.text = text


func submit_current(team_only: bool) -> void:
	_submit(_input.text, team_only)


## One received line. `channel` 0 = everybody, 1 = team; `from_slot` 255 with no name = a system line.
func add_line(channel: int, from_slot: int, from_name: String, text: String) -> void:
	var shown: String = UiLobbyChat.format_line(channel, from_slot, from_name, text)
	var l: Label = Label.new()
	l.text = shown
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440.0, 0.0)
	var col: Color = UiPalette.TEXT
	if UiLobbyChat.is_system(from_slot, from_name):
		col = UiPalette.semantic(&"warn")
	elif channel == 1:
		col = UiPalette.semantic(&"ok")
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	move_child(l, _input.get_index())
	_lines.append({"label": l, "born": Time.get_ticks_msec(), "text": shown})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		(old["label"] as Label).queue_free()
	set_process(true)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var keep: bool = _input.visible
	for i: int in range(_lines.size() - 1, -1, -1):
		var e: Dictionary = _lines[i]
		var age: float = float(now - int(e["born"])) / 1000.0
		var lab: Label = e["label"] as Label
		if _input.visible:
			lab.modulate.a = opacity  # everything stays readable while typing
			continue
		if age >= life_s:
			lab.queue_free()
			_lines.remove_at(i)
			continue
		lab.modulate.a = opacity * clampf((life_s - age) / FADE_S, 0.0, 1.0)
		keep = true
	if not keep:
		set_process(false)


func _on_input_event(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_ESCAPE:
		close()
		_input.accept_event()
	elif (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and k.shift_pressed:
		_submit(_input.text, true)
		_input.accept_event()


func _submit(text: String, team_only: bool) -> void:
	var t: String = text.strip_edges()
	close()
	if t.is_empty():
		return
	submitted.emit(t, team_only)
