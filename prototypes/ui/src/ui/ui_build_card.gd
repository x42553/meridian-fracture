class_name UiBuildCard
extends Control
## One cell of the sidebar build grid: portrait, name, cost, build time, hotkey, queue count, clock-wipe
## progress and state overlays (READY / ON HOLD / LOCKED / cost too high / cooldown).
## Static parts are drawn in _draw() and only redrawn on state change or once per displayed second; the
## per-frame progress goes to the UiCooldownSweep child so a building card costs ~no GDScript per frame.

signal pressed(item: UiBuildItem)
signal right_pressed(item: UiBuildItem)

const CARD_SIZE := Vector2(98.0, 104.0)
const ICON_H := 62.0

var item: UiBuildItem
var skin: UiSkin
var _sweep: UiCooldownSweep
var _time: Label
var _hover: bool = false
var _down: bool = false
var _pulse: float = 1.0
var _shown_sec: int = -1

func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(it: UiBuildItem, s: UiSkin, backend: UiCooldownSweep.Backend = UiCooldownSweep.Backend.SHADER) -> UiBuildCard:
	item = it
	skin = s
	_sweep = UiCooldownSweep.new(backend)
	_sweep.position = Vector2(3.0, 3.0)
	_sweep.size = Vector2(CARD_SIZE.x - 6.0, ICON_H)
	add_child(_sweep)
	_time = Label.new()
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time.position = Vector2(3.0, 3.0)
	_time.size = Vector2(CARD_SIZE.x - 6.0, ICON_H)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	_time.add_theme_font_size_override("font_size", 19)
	_time.add_theme_constant_override("outline_size", 6)
	_time.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	add_child(_time)
	tooltip_text = it.display_name
	refresh()
	return self

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		_down = false
		queue_redraw())

## Call after the view-model changed (state, queue, icon).
func refresh() -> void:
	var sweeping: bool = item.state in [UiBuildItem.State.BUILDING, UiBuildItem.State.ON_HOLD, UiBuildItem.State.COOLDOWN]
	_sweep.visible = sweeping
	_sweep.progress = item.progress
	_time.visible = item.state in [UiBuildItem.State.BUILDING, UiBuildItem.State.COOLDOWN]
	_time.text = _mmss(item.build_seconds * (1.0 - item.progress))
	set_process(item.state == UiBuildItem.State.READY)
	queue_redraw()

## Per-frame progress update path (production tick): moves the sweep, redraws text only when the second changes.
func set_progress(p: float) -> void:
	item.progress = p
	_sweep.progress = p
	var sec: int = int(ceilf(item.build_seconds * (1.0 - p)))
	if sec != _shown_sec:
		_shown_sec = sec
		_time.text = _mmss(item.build_seconds * (1.0 - p))
		queue_redraw()

func _process(_delta: float) -> void:
	_pulse = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = true
		elif _down:
			_down = false
			pressed.emit(item)
		queue_redraw()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		right_pressed.emit(item)
		accept_event()

func _make_custom_tooltip(_for_text: String) -> Object:
	return UiUnitTooltip.create(item, skin)

func _draw() -> void:
	if item == null:
		return
	var locked: bool = item.state == UiBuildItem.State.LOCKED
	var r := Rect2(Vector2.ZERO, size)
	var key: StringName = &"normal"
	if _down:
		key = &"pressed"
	elif _hover and not locked:
		key = &"hover"
	elif locked:
		key = &"disabled"
	draw_style_box(get_theme_stylebox(key, &"Button"), r)
	var ir := Rect2(3.0, 3.0, size.x - 6.0, ICON_H)
	_backdrop(ir)
	var tint := Color.WHITE
	match item.state:
		UiBuildItem.State.LOCKED:
			tint = Color(0.33, 0.36, 0.40)
		UiBuildItem.State.UNAFFORDABLE:
			tint = Color(0.64, 0.62, 0.64)
		UiBuildItem.State.COOLDOWN:
			tint = Color(0.75, 0.8, 0.85)
	if _hover and not locked:
		tint = tint.lightened(0.12)
	if item.icon != null:
		draw_texture_rect(item.icon, ir, false, tint)
	else:
		UiGlyphs.draw(self, item.glyph, Rect2(ir.get_center() - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), skin.accent.darkened(0.15) if not locked else UiPalette.TEXT_MUTE, 2.0)
	_overlays(ir)
	_footer(r)

func _backdrop(ir: Rect2) -> void:
	var top: Color = Color("#141e2a").lerp(skin.tint, 0.4)
	var bot: Color = Color("#070b10").lerp(skin.tint, 0.2)
	draw_polygon(PackedVector2Array([ir.position, Vector2(ir.end.x, ir.position.y), ir.end, Vector2(ir.position.x, ir.end.y)]), PackedColorArray([top, top, bot, bot]))
	draw_set_transform(Vector2(ir.get_center().x, ir.end.y - 11.0), 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, ir.size.x * 0.46, Color(skin.accent, 0.13))
	draw_circle(Vector2.ZERO, ir.size.x * 0.30, Color(skin.accent, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _overlays(ir: Rect2) -> void:
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	# cost strip
	var strip := Rect2(ir.position.x, ir.end.y - 17.0, ir.size.x, 17.0)
	draw_polygon(PackedVector2Array([strip.position, Vector2(strip.end.x, strip.position.y), strip.end, Vector2(strip.position.x, strip.end.y)]), PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.78)]))
	if item.cost > 0:
		var cc: Color = UiPalette.DANGER if item.state == UiBuildItem.State.UNAFFORDABLE else UiPalette.CREDITS
		draw_string(num, Vector2(ir.position.x + 5.0, ir.end.y - 4.0), "$" + _group(item.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	var t_txt: String = _mmss(item.build_seconds * (1.0 - item.progress) if item.state in [UiBuildItem.State.BUILDING, UiBuildItem.State.COOLDOWN, UiBuildItem.State.ON_HOLD] else item.build_seconds)
	draw_string(num, Vector2(ir.end.x - 4.0 - 40.0, ir.end.y - 4.0), t_txt, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 12, UiPalette.TEXT_DIM)
	# hotkey badge
	if item.hotkey != "":
		draw_rect(Rect2(ir.position.x + 3.0, ir.position.y + 3.0, 15.0, 15.0), Color(0, 0, 0, 0.6))
		draw_string(num, Vector2(ir.position.x + 3.0, ir.position.y + 14.5), item.hotkey, HORIZONTAL_ALIGNMENT_CENTER, 15.0, 12, UiPalette.TEXT_DIM)
	# queue count pill
	if item.queued > 0 and item.state != UiBuildItem.State.AVAILABLE:
		var label: String = "x%d" % item.queued
		var w: float = bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
		var pill := Rect2(ir.end.x - w - 3.0, ir.position.y + 3.0, w, 16.0)
		draw_style_box(_pill_box(), pill)
		draw_string(bold, Vector2(pill.position.x, pill.position.y + 13.0), label, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color("#0b1016"))
	# centre overlays by state
	var c: Vector2 = ir.get_center() - Vector2(0.0, 6.0)
	match item.state:
		UiBuildItem.State.READY:
			_banner(ir, "READY", UiPalette.OK, _pulse)
		UiBuildItem.State.ON_HOLD:
			_banner(ir, "ON HOLD", UiPalette.WARN, 1.0)
		UiBuildItem.State.LOCKED:
			draw_rect(ir, Color(0, 0, 0, 0.35))
			UiGlyphs.draw(self, UiGlyphs.Glyph.LOCK, Rect2(c - Vector2(10.0, 12.0), Vector2(20.0, 20.0)), UiPalette.TEXT_DIM, 1.6)

func _banner(ir: Rect2, text: String, col: Color, alpha: float) -> void:
	var b := Rect2(ir.position.x, ir.get_center().y - 10.0, ir.size.x, 20.0)
	draw_rect(b, Color(col.darkened(0.55), 0.82))
	draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 1.0), Color(col, alpha))
	draw_rect(Rect2(b.position.x, b.end.y - 1.0, b.size.x, 1.0), Color(col, alpha))
	draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(b.position.x, b.position.y + 14.5), text, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 12, Color(col.lightened(0.35), alpha))

func _footer(r: Rect2) -> void:
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var name_col: Color = UiPalette.TEXT if item.state != UiBuildItem.State.LOCKED else UiPalette.TEXT_MUTE
	if item.state == UiBuildItem.State.BUILDING:
		name_col = skin.accent.lightened(0.25)
	var nm: String = _fit(bold, item.display_name, 14, r.size.x - 8.0)
	draw_string(bold, Vector2(4.0, ICON_H + 19.0), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, 14, name_col)
	var status: String = ""
	var sc: Color = UiPalette.TEXT_MUTE
	match item.state:
		UiBuildItem.State.BUILDING:
			status = "BUILDING %d%%" % int(item.progress * 100.0)
			sc = skin.accent
		UiBuildItem.State.QUEUED:
			status = "QUEUED"
		UiBuildItem.State.READY:
			status = "PLACE STRUCTURE" if item.tier == 0 else "READY"
			sc = UiPalette.OK
		UiBuildItem.State.ON_HOLD:
			status = "ON HOLD"
			sc = UiPalette.WARN
		UiBuildItem.State.LOCKED:
			status = _fit(body, item.requires.replace("Requires ", "Needs "), 12, r.size.x - 8.0) if item.requires != "" else "LOCKED"
			sc = UiPalette.WARN.darkened(0.2)
		UiBuildItem.State.UNAFFORDABLE:
			status = "NEED CREDITS"
			sc = UiPalette.DANGER
		UiBuildItem.State.COOLDOWN:
			status = "CHARGING %d%%" % int(item.progress * 100.0)
			sc = skin.accent2
		_:
			status = "T%d" % item.tier if item.tier > 1 else ""
	if status != "":
		draw_string(body, Vector2(4.0, ICON_H + 33.0), status, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, 12, sc)
	if item.state in [UiBuildItem.State.BUILDING, UiBuildItem.State.COOLDOWN, UiBuildItem.State.ON_HOLD]:
		var track := Rect2(5.0, r.size.y - 5.0, r.size.x - 10.0, 2.0)
		draw_rect(track, Color(0, 0, 0, 0.6))
		var fc: Color = skin.accent if item.state != UiBuildItem.State.ON_HOLD else UiPalette.WARN
		draw_rect(Rect2(track.position, Vector2(track.size.x * item.progress, track.size.y)), fc)

var _pill: UiStyleBox

func _pill_box() -> UiStyleBox:
	if _pill == null:
		_pill = UiStyleBox.new()
		_pill.fill_top = skin.accent2.lightened(0.1)
		_pill.fill_bottom = skin.accent2.darkened(0.15)
		_pill.border_color = skin.accent2.lightened(0.4)
		_pill.cuts = Vector4(4.0, 0.0, 4.0, 0.0)
		_pill.highlight = 0.0
	return _pill

static func _fit(font: Font, text: String, fsize: int, max_w: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
		return text
	var s: String = text
	while s.length() > 1 and font.get_string_size(s + "..", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + ".."

static func _group(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

static func _mmss(sec: float) -> String:
	var s: int = int(ceilf(sec))
	return "%d:%02d" % [s / 60, s % 60]
