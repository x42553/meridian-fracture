class_name UiScreenCredits
extends UiScreen
## Credits (ui.md 5.16.7): the wordmark, then the sections of `data/text/credits.json` scrolling slowly upward over a dark
## vignette. The scroll pauses while the pointer hovers it or a key scrolls it; Escape, Back or a click leaves (pushed overlay).

const CREDITS_PATH: String = "res://data/text/credits.json"
const SPEED_PX_S: float = 46.0

var _scroll: ScrollContainer = null
var _offset: float = 0.0
var _paused: bool = false
var _back: Button = null


func _init() -> void:
	super._init()
	screen_id = &"credits"


func enter(_params: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var acc: Color = UiScreenKit.accent(self)
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.9, 0.07, 0.0, 0.03, acc))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(col)
	col.add_child(UiScreenKit.spacer(float(DisplayServer.window_get_size().y) * 0.4 if DisplayServer.get_name() != "headless" else 400.0))
	var title: Label = UiScreenKit.wordmark("MERIDIAN", 84, 900, 6, UiPalette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub: Label = UiScreenKit.wordmark("FRACTURE", 36, 500, 30, acc)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UiScreenKit.spacer(90.0))
	for sec: Variant in _load_sections():
		var d: Dictionary = sec as Dictionary
		var head: Label = UiScreenKit.label(str(d.get("heading", "")).to_upper(), &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
		head.add_theme_font_size_override("font_size", 20)
		col.add_child(head)
		for line: Variant in d.get("lines", []) as Array:
			var l: Label = UiScreenKit.label(str(line), &"SubLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
			l.add_theme_font_size_override("font_size", 20)
			col.add_child(l)
		col.add_child(UiScreenKit.spacer(64.0))
	col.add_child(UiScreenKit.spacer(float(DisplayServer.window_get_size().y) * 0.5 if DisplayServer.get_name() != "headless" else 500.0))
	_back = UiScreenKit.button("BACK", &"GhostButton", Vector2(150.0, 44.0))
	_back.pressed.connect(func() -> void: back_requested.emit())
	add_child(_back)
	_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_back.offset_left = 56.0
	_back.offset_top = -80.0
	_back.offset_right = 206.0
	_back.offset_bottom = -36.0
	mouse_entered.connect(func() -> void: _paused = true)
	mouse_exited.connect(func() -> void: _paused = false)
	set_process(true)


func exit() -> void:
	set_process(false)


func default_focus() -> Control:
	return _back


func _load_sections() -> Array:
	var f: FileAccess = FileAccess.open(CREDITS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).get("sections") is Array:
			return (parsed as Dictionary)["sections"] as Array
	return [{"heading": "Meridian Fracture", "lines": []}]


func _process(delta: float) -> void:
	if _paused or _scroll == null:
		return
	_offset += SPEED_PX_S * delta
	_scroll.scroll_vertical = int(_offset)
	var limit: float = _scroll.get_v_scroll_bar().max_value - _scroll.size.y
	if _offset > limit + 40.0:
		_offset = 0.0
