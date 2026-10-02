class_name UiIconButton
extends Control
## Square glyph button used by the command bar, the build tab strip and the sell/repair toggles.
## Custom-drawn Control (not a Button subclass) so glyph, hotkey and badge share one canvas item and one hit area,
## but styled through the shared Theme: normal/hover/pressed/disabled come from the "Button" theme type.
## HUD pattern: focus_mode NONE (never steals keyboard focus), mouse_filter STOP (eats clicks over itself only).

signal pressed
signal right_pressed

@export var glyph: UiGlyphs.Glyph = UiGlyphs.Glyph.STOP
## Small text at the bottom-right corner (hotkey).
@export var hotkey: String = ""
## Top-right notification badge (count of ready items, etc).
@export var badge: String = ""
@export var toggle_mode: bool = false
@export var enabled: bool = true
@export var accent: Color = Color.WHITE
@export var caption: String = ""

var active: bool = false:
	set(v):
		active = v
		queue_redraw()
var _hover: bool = false
var _down: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(46.0, 46.0)

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		_down = false
		queue_redraw())

func set_enabled(v: bool) -> void:
	enabled = v
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not enabled:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = true
		elif _down:
			_down = false
			if toggle_mode:
				active = not active
			pressed.emit()
		queue_redraw()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		right_pressed.emit()
		accept_event()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var state: StringName = &"normal"
	if not enabled:
		state = &"disabled"
	elif _down or (toggle_mode and active):
		state = &"pressed"
	elif _hover:
		state = &"hover"
	draw_style_box(get_theme_stylebox(state, &"Button"), r)
	var col: Color = UiPalette.TEXT_DIM
	if not enabled:
		col = UiPalette.TEXT_MUTE
	elif active:
		col = accent
	elif _hover:
		col = UiPalette.TEXT
	var gs: float = minf(size.x, size.y) * (0.5 if caption == "" else 0.42)
	var gc := Vector2(size.x * 0.5, size.y * (0.5 if caption == "" else 0.40))
	UiGlyphs.draw(self, glyph, Rect2(gc - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), col, 1.8)
	var f: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	if caption != "":
		draw_string(f, Vector2(0.0, size.y - 6.0), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, col)
	if hotkey != "":
		draw_string(UiFonts.get_font(UiFonts.Role.NUM), Vector2(size.x - 14.0, size.y - 5.0), hotkey, HORIZONTAL_ALIGNMENT_CENTER, 12.0, 11, UiPalette.TEXT_MUTE if not _hover else accent)
	if badge != "":
		var bw: float = maxf(14.0, f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0)
		var br := Rect2(size.x - bw - 2.0, 2.0, bw, 14.0)
		draw_rect(br, accent.darkened(0.15))
		draw_string(f, Vector2(br.position.x, br.position.y + 11.0), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color("#0b1016"))
