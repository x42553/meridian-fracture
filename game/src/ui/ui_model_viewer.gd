class_name UiModelViewer
extends PanelContainer
## The 3D model viewer of the Field Manual cards and the lobby briefing (ui.md 11 UI-12): a turntable of the selected unit / structure in
## the faction style of a roster, with the team colour and an idle animation. Drag rotates, the wheel zooms, a double click resets, PAUSE
## freezes the spin. The drawing is `ViewTurntable` (created through the `UiViewPortWorld` adapter, the only UI class that talks to the view);
## without a renderer (headless) or a model the viewer shows the baked `placeholder` icon, or the class glyph, instead.

signal paused_changed(paused: bool)

var def_id: String = ""
var roster_id: String = ""
var turntable: Control = null  ## ViewTurntable, null while the fallback shows

var _stack: Control = null
var _fallback: TextureRect = null
var _hint: Label = null
var _pause: Button = null
var _strip: HBoxContainer = null
var _caption: Label = null
var _prev: Button = null
var _next: Button = null
var _list_ids: PackedStringArray = PackedStringArray()
var _list_names: PackedStringArray = PackedStringArray()
var _list_i: int = 0
var _team: Color = Color(0.0, 0.0, 0.0, 0.0)


func _init(min_size: Vector2 = Vector2(320.0, 230.0)) -> void:
	theme_type_variation = &"InsetPanel"
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	_stack = Control.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_stack.clip_contents = true
	add_child(_stack)
	_fallback = TextureRect.new()
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(_fallback)
	UiLayerRoot.fill(_fallback)
	_strip = HBoxContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_constant_override("separation", 6)
	_stack.add_child(_strip)
	_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_top = -30.0
	_strip.offset_left = 8.0
	_strip.offset_right = -8.0
	_strip.offset_bottom = -6.0
	tooltip_text = "Drag to rotate, mouse wheel to zoom, double click to reset"
	_prev = _small_button("<")
	_prev.visible = false
	_prev.pressed.connect(func() -> void: step_list(-1))
	_strip.add_child(_prev)
	_next = _small_button(">")
	_next.visible = false
	_next.pressed.connect(func() -> void: step_list(1))
	_strip.add_child(_next)
	_hint = UiScreenKit.label("DRAG / WHEEL", &"CaptionLabel")
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.clip_text = true
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_strip.add_child(_hint)
	_caption = UiScreenKit.label("", &"NameLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_stack.add_child(_caption)
	_caption.position = Vector2(10.0, 6.0)
	_caption.size = Vector2(min_size.x - 20.0, 22.0)
	_pause = UiScreenKit.button("PAUSE", &"GhostButton", Vector2(76.0, 26.0))
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.add_theme_font_size_override("font_size", 12)
	_pause.pressed.connect(func() -> void: set_paused(not is_paused()))
	_strip.add_child(_pause)
	_strip.visible = false


static func _small_button(text: String) -> Button:
	var b: Button = UiScreenKit.button(text, &"GhostButton", Vector2(30.0, 26.0))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	return b


## A cycling viewer: the defs `ids` (display `names` as the caption), previous / next buttons in the strip. Shows the first one.
func set_list(ids: PackedStringArray, names: PackedStringArray, p_roster_id: String, team: Color = Color(0.0, 0.0, 0.0, 0.0)) -> bool:
	_list_ids = ids
	_list_names = names
	_list_i = 0
	_team = team
	roster_id = p_roster_id
	_prev.visible = ids.size() > 1
	_next.visible = ids.size() > 1
	_caption.visible = ids.size() > 0
	return _show_listed()


func step_list(dir: int) -> void:
	if _list_ids.is_empty():
		return
	_list_i = posmod(_list_i + dir, _list_ids.size())
	_show_listed()


func list_index() -> int:
	return _list_i


func _show_listed() -> bool:
	if _list_ids.is_empty():
		return false
	_caption.text = _list_names[_list_i].to_upper() if _list_i < _list_names.size() else _list_ids[_list_i]
	return show_def(_list_ids[_list_i], roster_id, _team, _fallback.texture)


## Points the viewer at a def. `placeholder` (a baked icon) is what shows when no model can be drawn. Returns whether the 3D model is shown.
func show_def(p_def_id: String, p_roster_id: String, team: Color = Color(0.0, 0.0, 0.0, 0.0), placeholder: Texture2D = null) -> bool:
	def_id = p_def_id
	roster_id = p_roster_id
	_fallback.texture = placeholder
	var adapter: UiViewPortWorld = UiViewPortWorld.menu_icons()
	var ok: bool = false
	if turntable == null:
		var t: Control = adapter.create_turntable(p_def_id, p_roster_id, team)
		if t != null:
			turntable = t
			_stack.add_child(turntable)
			UiLayerRoot.fill(turntable)
			_stack.move_child(turntable, 1)  # above the fallback, below the control strip
			turntable.call("set_paused", false)
			turntable.connect("paused_changed", _on_paused_changed)
			ok = true
	else:
		ok = adapter.show_in_turntable(turntable, p_def_id, p_roster_id, team)
	_fallback.visible = not ok
	if turntable != null:
		turntable.visible = ok
	_strip.visible = ok
	_hint.visible = _list_ids.is_empty()
	return ok


func has_model() -> bool:
	return turntable != null and turntable.visible and bool(turntable.call("has_model"))


func is_paused() -> bool:
	return turntable != null and bool(turntable.get("paused"))


func set_paused(v: bool) -> void:
	if turntable != null:
		turntable.set("paused", v)


func set_team_color(c: Color) -> void:
	if turntable != null:
		turntable.call("set_team_color", c)


func reset_view() -> void:
	if turntable != null:
		turntable.call("reset_view")


func _on_paused_changed(v: bool) -> void:
	_pause.text = "PLAY" if v else "PAUSE"
	paused_changed.emit(v)
