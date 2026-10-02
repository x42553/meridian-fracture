class_name UiLobbyChat
extends PanelContainer
## The lobby chat (ui.md 5.14.9): a scrolling history and a one-line input. Text is plain: `RichTextLabel.add_text` never parses
## BBCode, so "[b]hi[/b]" shows literally. The sender's name is drawn in the colour of its slot, system lines (`from_slot` 255) in
## the warning colour, team-only lines are tagged "(team)". Enter sends, Shift+Enter sends to the team only. The input is limited to
## the wire limit (`NetProtocol.CHAT_MAX_BYTES`); the network sanitises the text again. `submitted(text, team_only)` is the only output,
## the screen forwards it to `NetSession.send_chat`. Lines are kept at most `MAX_LINES`.

signal submitted(text: String, team_only: bool)

const MAX_LINES: int = 200

var unread: int = 0
var line_count: int = 0

var _history: RichTextLabel = null
var _input: LineEdit = null
var _send: Button = null
var _lines: Array[Dictionary] = []


func _init() -> void:
	theme_type_variation = &"InsetPanel"
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	v.add_child(UiPanelHeader.new("Chat", "ENTER  //  SHIFT+ENTER TEAM"))
	_history = RichTextLabel.new()
	_history.bbcode_enabled = false
	_history.scroll_following = true
	_history.selection_enabled = true
	_history.fit_content = false
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.custom_minimum_size = Vector2(0.0, 120.0)
	_history.focus_mode = Control.FOCUS_NONE
	v.add_child(_history)
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something ..."
	_input.max_length = NetProtocol.CHAT_MAX_BYTES
	_input.custom_minimum_size = Vector2(0.0, 36.0)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.gui_input.connect(_on_input_event)
	_input.text_submitted.connect(func(t: String) -> void: _submit(t, false))
	h.add_child(_input)
	_send = UiScreenKit.button("SEND", &"", Vector2(84.0, 36.0))
	_send.pressed.connect(func() -> void: _submit(_input.text, false))
	h.add_child(_send)


## Adds one received line. `channel` 0 = everybody, 1 = team; `from_slot` 255 = system; `color` = the sender's slot colour.
func add_line(channel: int, from_slot: int, from_name: String, text: String, color: Color = Color.WHITE) -> void:
	_lines.append({"channel": channel, "from_slot": from_slot, "name": from_name, "text": text})
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
		_rebuild()
	else:
		_append(_lines[_lines.size() - 1], color)
	line_count = _lines.size()
	if not is_visible_in_tree():
		unread += 1


## The plain text of a line as shown ("[SYSTEM] ...", "Name (team): ...", "Name: ...").
static func format_line(channel: int, from_slot: int, from_name: String, text: String) -> String:
	if is_system(from_slot, from_name):
		return "[SYSTEM] " + text
	if from_slot == 255:
		return "%s (spectator): %s" % [from_name, text]  # a spectator has no slot (255) but a name
	return "%s%s: %s" % [from_name, " (team)" if channel == 1 else "", text]


## A system line has no slot (255) and no name; a spectator's line has slot 255 and a name.
static func is_system(from_slot: int, from_name: String) -> bool:
	return from_slot == 255 and from_name.is_empty()


## The current history as plain text (tests).
func history_text() -> String:
	return _history.get_parsed_text() if _history != null else ""


func focus_input() -> void:
	unread = 0
	_input.grab_focus()


func _append(line: Dictionary, color: Color) -> void:
	var from_slot: int = int(line["from_slot"])
	if is_system(from_slot, str(line["name"])):
		_history.push_color(UiPalette.semantic(&"warn"))
		_history.add_text(format_line(0, 255, "", str(line["text"])))
		_history.pop()
	else:
		_history.push_color(color if from_slot != 255 else UiPalette.TEXT_DIM)
		_history.add_text("%s%s" % [str(line["name"]), " (team)" if int(line["channel"]) == 1 else (" (spectator)" if from_slot == 255 else "")])
		_history.pop()
		_history.add_text(": " + str(line["text"]))
	_history.newline()


func _rebuild() -> void:
	_history.clear()
	for l: Dictionary in _lines:
		_append(l, Color.WHITE)


func _on_input_event(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and k.shift_pressed:
		_submit(_input.text, true)
		_input.accept_event()


func _submit(text: String, team_only: bool) -> void:
	var t: String = text.strip_edges()
	_input.clear()
	if t.is_empty():
		return
	submitted.emit(t, team_only)
