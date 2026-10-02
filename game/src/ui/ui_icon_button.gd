class_name UiIconButton
extends Control
## Glyph / icon button (ui.md 2.3): toggle, badge, hotkey text, caption. One custom-drawn Control (glyph, hotkey and badge
## share one canvas item and one hit area) styled through the shared theme (`CommandButton` recipe: normal / hover /
## pressed / disabled). HUD-safe by default: `focus_mode = NONE`, `MOUSE_FILTER_STOP` over itself only. Menus call
## `set_focusable(true)` (Tab / Enter, styled focus ring). The glyph id is a `UiGlyphs.Glyph` value (drawn through
## `UiDraw.glyph`); `icon` (a Texture2D, e.g. a baked portrait) wins over the glyph. Redraws only on state change.

signal pressed()
signal right_pressed()
## Toggle buttons: emitted with the new state on every click.
signal toggled(on: bool)

@export var glyph: int = UiDraw.G_STOP:
	set(v):
		glyph = v
		queue_redraw()
@export var icon: Texture2D = null:
	set(v):
		icon = v
		queue_redraw()
## Small text at the bottom-right corner (hotkey), NUM 14.
@export var hotkey: String = "":
	set(v):
		hotkey = v
		queue_redraw()
## Top-right notification badge (count of ready items ...).
@export var badge: String = "":
	set(v):
		badge = v
		queue_redraw()
## Text under the glyph (14 px), keeps the glyph in the upper part.
@export var caption: String = "":
	set(v):
		caption = v
		queue_redraw()
@export var toggle_mode: bool = false
## Colour of an active toggle / hover glyph; default = the skin accent.
@export var accent_override: Color = Color(0.0, 0.0, 0.0, 0.0)

var enabled: bool = true
var active: bool = false:
	set(v):
		if v == active:
			return
		active = v
		queue_redraw()
var _hover: bool = false
var _down: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(float(UiMetrics.COMMAND_BTN), float(UiMetrics.COMMAND_BTN))


## Menu use: the button takes keyboard focus (Tab / Enter / Space) and draws the focus ring.
func set_focusable(on: bool) -> void:
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func set_enabled(v: bool) -> void:
	enabled = v
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
	if not v:
		_down = false
	queue_redraw()


## Rich tooltip (`UiTooltipBody` spec: title, tag, text, ...). Also sets the accessibility name to the title.
func set_tip(tip: Dictionary) -> void:
	tooltip_text = UiTooltipBody.encode(tip) if not tip.is_empty() else ""
	if tip.has("title") and accessibility_name == "":
		accessibility_name = String(tip["title"])


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_down = false
			queue_redraw()
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = true
			elif _down:
				_down = false
				if Rect2(Vector2.ZERO, size).has_point(mb.position):
					_activate()
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			right_pressed.emit()
			accept_event()
		return
	if event.is_action_pressed(&"ui_accept") and has_focus():
		_activate()
		accept_event()


func _activate() -> void:
	if toggle_mode:
		active = not active
		toggled.emit(active)
	pressed.emit()


func _accent() -> Color:
	if accent_override.a > 0.0:
		return accent_override
	return get_theme_color(&"accent", UiTheme.ACCENT_TYPE)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var state: StringName = &"normal"
	if not enabled:
		state = &"disabled"
	elif _down or (toggle_mode and active):
		state = &"pressed"
	elif _hover:
		state = &"hover"
	draw_style_box(get_theme_stylebox(state, &"CommandButton"), r)
	var acc: Color = _accent()
	var col: Color = UiPalette.TEXT_DIM
	if not enabled:
		col = UiPalette.TEXT_DISABLED
	elif active:
		col = acc
	elif _hover:
		col = UiPalette.TEXT
	var has_cap: bool = caption != ""
	var gs: float = minf(size.x, size.y) * (0.44 if has_cap else 0.5)
	var gc := Vector2(size.x * 0.5, size.y * (0.38 if has_cap else 0.5))
	var grect := Rect2(gc - Vector2(gs, gs) * 0.5, Vector2(gs, gs))
	if icon != null:
		draw_texture_rect(icon, grect.grow(gs * 0.15), false, Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.45))
	else:
		UiDraw.glyph(self, glyph, grect, col, 1.8)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	if has_cap:
		draw_string(body, Vector2(0.0, size.y - 6.0), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, UiMetrics.FS_SMALL, col)
	if hotkey != "":
		var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
		var hw: float = num.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION).x
		var hp := Vector2(size.x - hw - 4.0, size.y - 4.0) if not has_cap else Vector2(4.0, 15.0)
		draw_string(num, hp, hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION, acc if _hover and enabled else UiPalette.TEXT_DIM)
	if badge != "":
		var bw: float = maxf(18.0, body.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_SMALL).x + 8.0)
		var br := Rect2(size.x - bw + 2.0, -3.0, bw, 18.0)
		draw_rect(br, acc.darkened(0.1))
		draw_string(body, Vector2(br.position.x, br.position.y + 14.0), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, UiMetrics.FS_SMALL, UiPalette.TEXT_ON_ACCENT)
	if has_focus():
		draw_style_box(get_theme_stylebox(&"focus", &"CommandButton"), r)
