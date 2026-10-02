class_name UiBuildCard
extends Control
## One cell of the sidebar build grid (ui.md 5.10.4 card anatomy): baked icon or glyph placeholder over the plate
## gradient, tier badge (top right), role glyph (bottom left), hotkey badge, cost line, queue pill, state banners and a
## clock-wipe sweep. Static parts are drawn in `_draw` and only redrawn when the derived state changes or once per
## displayed second; the per-tick progress goes to the `UiCooldownSweep` child, a fill rect and a countdown label so a
## BUILDING card costs no GDScript geometry per frame. Never reads the sim: it draws its `UiBuildItem`.

signal pressed(item: UiBuildItem, shift: bool)
signal right_pressed(item: UiBuildItem)

const CARD_SIZE := Vector2(98.0, 104.0)
const ICON_H: float = 62.0

var item: UiBuildItem = null
var _sweep: UiCooldownSweep = null
var _time: Label = null
var _fill: ColorRect = null
var _hover: bool = false
var _down: bool = false
var _pulse: float = 1.0
var _pulse_accum: float = 0.0
var _sig: int = 0
var _shown_sec: int = -1


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sweep = UiCooldownSweep.new()
	_sweep.position = Vector2(3.0, 3.0)
	_sweep.size = Vector2(CARD_SIZE.x - 6.0, ICON_H)
	_sweep.visible = false
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
	_time.visible = false
	add_child(_time)
	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2(5.0, CARD_SIZE.y - 5.0)
	_fill.size = Vector2(0.0, 2.0)
	_fill.visible = false
	add_child(_fill)


## Binds the card to a view-model and shows it.
func setup(it: UiBuildItem) -> UiBuildCard:
	item = it
	_sig = 0
	_shown_sec = -1
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


func _accent() -> Color:
	return get_theme_color(&"accent", UiTheme.ACCENT_TYPE)


func _accent2() -> Color:
	return get_theme_color(&"accent2", UiTheme.ACCENT_TYPE)


## Call after the view-model changed. Redraws only when something static changed.
func refresh() -> void:
	if item == null:
		return
	var sweeping: bool = item.is_sweeping()
	_sweep.visible = sweeping
	_sweep.shade_color = Color(0.32, 0.20, 0.0, 0.62) if item.state == UiBuildItem.State.ON_HOLD else UiCooldownSweep.SHADE
	_time.visible = item.state == UiBuildItem.State.BUILDING or item.state == UiBuildItem.State.COOLDOWN
	_fill.visible = sweeping
	_fill.color = UiPalette.WARN if item.state == UiBuildItem.State.ON_HOLD else _accent()
	set_progress()
	var sig: int = hash([item.state, item.queued, item.requires_text, item.reason_text, item.queue_state, item.tier, item.icon, item.role_glyph, item.cost, item.slot])
	if sig != _sig:
		_sig = sig
		queue_redraw()
	var pulsing: bool = item.state == UiBuildItem.State.READY or item.state == UiBuildItem.State.PLACING \
		or ((item.kind == UiBuildItem.Kind.POWER or item.kind == UiBuildItem.Kind.SUPERWEAPON) and item.state == UiBuildItem.State.AVAILABLE)
	set_process(pulsing)


## Per-tick path: moves the sweep and the fill, updates the countdown text when the displayed second changes.
func set_progress() -> void:
	if item == null:
		return
	var p: float = item.progress()
	_sweep.progress = p
	_fill.size.x = (size.x - 10.0) * p
	var sec: int = item.remaining_whole_seconds()
	if sec != _shown_sec:
		_shown_sec = sec
		_time.text = UiBuildItem.mmss(sec)
		if item.is_sweeping():
			queue_redraw()


func _process(delta: float) -> void:
	_pulse_accum += delta
	if _pulse_accum >= 1.0 / 15.0:
		_pulse_accum = 0.0
		_pulse = 0.65 + 0.35 * UiMotion.pulse(float(Time.get_ticks_msec()) / 1000.0)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or item == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(mb.position):
				pressed.emit(item, mb.shift_pressed)
		queue_redraw()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		right_pressed.emit(item)
		accept_event()


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_THEME_CHANGED:
			_pill = null
			queue_redraw()
		NOTIFICATION_RESIZED:
			var iw: float = size.x - 6.0
			_sweep.size = Vector2(iw, ICON_H)
			_time.size = Vector2(iw, ICON_H)
			_fill.position = Vector2(5.0, size.y - 5.0)
			set_progress()
			queue_redraw()


# ---- drawing ----------------------------------------------------------------------------------------------------------
func _draw() -> void:
	if item == null:
		return
	var locked: bool = item.is_locked_out()
	var r := Rect2(Vector2.ZERO, size)
	var key: StringName = &"normal"
	if _down:
		key = &"pressed"
	elif locked and item.state == UiBuildItem.State.LOCKED:
		key = &"disabled"
	elif _hover:
		key = &"hover"
	draw_style_box(get_theme_stylebox(key, &"Button"), r)
	var ir := Rect2(3.0, 3.0, size.x - 6.0, ICON_H)
	_backdrop(ir)
	var tint := Color.WHITE
	match item.state:
		UiBuildItem.State.LOCKED:
			tint = Color(0.52, 0.55, 0.60)  # a baked icon must stay recognisable behind the lock
		UiBuildItem.State.BLOCKED:
			tint = Color(0.62, 0.52, 0.50)
		UiBuildItem.State.UNAFFORDABLE:
			tint = Color(0.72, 0.68, 0.68)
		UiBuildItem.State.COOLDOWN, UiBuildItem.State.DONE:
			tint = Color(0.75, 0.8, 0.85)
	if _hover and not locked:
		tint = tint.lightened(0.12)
	var has_icon: bool = item.icon != null
	if has_icon:
		draw_texture_rect(item.icon, ir, false, tint)
	else:
		_placeholder(ir, locked)
	_overlays(ir, has_icon)
	_footer(r)
	if item.replaced_by_roster:
		var bw: float = 4.0
		draw_rect(Rect2(r.end.x - bw - 1.0, r.position.y + 1.0, bw, 10.0), _accent2())


func _backdrop(ir: Rect2) -> void:
	var skin_tint: Color = get_theme_color(&"tint", UiTheme.ACCENT_TYPE)
	var acc: Color = _accent()
	var top: Color = UiPalette.BG_RAISED.lerp(skin_tint, 0.4)
	var bot: Color = UiPalette.BG_DEEP.lerp(skin_tint, 0.2)
	draw_polygon(PackedVector2Array([ir.position, Vector2(ir.end.x, ir.position.y), ir.end, Vector2(ir.position.x, ir.end.y)]), PackedColorArray([top, top, bot, bot]))
	draw_set_transform(Vector2(ir.get_center().x, ir.end.y - 11.0), 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, ir.size.x * 0.46, Color(acc, 0.13))
	draw_circle(Vector2.ZERO, ir.size.x * 0.30, Color(acc, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Glyph placeholder while the baked portrait does not exist yet: the role glyph large, in the skin accent.
func _placeholder(ir: Rect2, locked: bool) -> void:
	var col: Color = UiPalette.TEXT_MUTE if locked else _accent().darkened(0.1)
	var gs: float = 38.0
	UiGlyphs.draw(self, item.role_glyph, Rect2(ir.get_center() - Vector2(gs, gs) * 0.5 + Vector2(0.0, -4.0), Vector2(gs, gs)), col, 2.0)


func _overlays(ir: Rect2, has_icon: bool) -> void:
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var strip := Rect2(ir.position.x, ir.end.y - 18.0, ir.size.x, 18.0)
	draw_polygon(PackedVector2Array([strip.position, Vector2(strip.end.x, strip.position.y), strip.end, Vector2(strip.position.x, strip.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.78)]))
	if item.cost > 0:
		var cc: Color = UiPalette.DANGER if item.state == UiBuildItem.State.UNAFFORDABLE else UiPalette.CREDITS
		draw_string(num, Vector2(ir.position.x + 5.0, ir.end.y - 4.0), "$" + UiBuildItem.group_digits(item.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cc)
	if item.total_seconds > 0.0:
		draw_string(num, Vector2(ir.end.x - 44.0, ir.end.y - 4.0), UiBuildItem.mmss(int(ceilf(item.total_seconds))), HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 13, UiPalette.TEXT_DIM)
	# hotkey badge
	var hk: String = UiBuildModel.CARD_KEYS[item.slot] if item.slot >= 0 and item.slot < UiBuildModel.CARD_KEYS.size() and item.kind != UiBuildItem.Kind.POWER and item.kind != UiBuildItem.Kind.SUPERWEAPON else ""
	if item.kind == UiBuildItem.Kind.POWER or item.kind == UiBuildItem.Kind.SUPERWEAPON:
		hk = item.hotkey_label
	if hk != "":
		var hw: float = maxf(15.0, num.get_string_size(hk, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 5.0)
		draw_rect(Rect2(ir.position.x + 3.0, ir.position.y + 3.0, hw, 15.0), Color(0, 0, 0, 0.6))
		draw_string(num, Vector2(ir.position.x + 3.0, ir.position.y + 14.5), hk, HORIZONTAL_ALIGNMENT_CENTER, hw, 13, UiPalette.TEXT_DIM)
	# queue count pill (top right) and the tier chevrons beneath / beside it
	var right_x: float = ir.end.x - 3.0
	if item.queued > 1 or (item.queued > 0 and item.state != UiBuildItem.State.AVAILABLE and item.state != UiBuildItem.State.UNAFFORDABLE and item.kind == UiBuildItem.Kind.UNIT):
		var label: String = "x%d" % item.queued
		var w: float = bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
		var pill := Rect2(ir.end.x - w - 3.0, ir.position.y + 3.0, w, 16.0)
		draw_style_box(_pill_box(), pill)
		draw_string(bold, Vector2(pill.position.x, pill.position.y + 13.0), label, HORIZONTAL_ALIGNMENT_CENTER, w, 13, UiPalette.BG_PANEL)
		right_x = pill.position.x - 4.0
	if item.tier >= 2:
		var acc2: Color = _accent2()
		for i: int in item.tier - 1:
			var cy: float = ir.position.y + 10.0 + float(i) * 4.0
			var cx: float = right_x - 8.0 if right_x < ir.end.x - 4.0 else right_x - 8.0
			draw_polyline(PackedVector2Array([Vector2(cx - 4.0, cy + 2.0), Vector2(cx, cy - 1.0), Vector2(cx + 4.0, cy + 2.0)]), acc2, 1.6, true)
	# role glyph bottom-left above the cost line (only over a baked icon; the placeholder is the glyph)
	if has_icon:
		UiGlyphs.draw(self, item.role_glyph, Rect2(ir.position.x + 4.0, ir.end.y - 34.0, 14.0, 14.0), Color(UiPalette.TEXT, 0.8), 1.4)
	# chips of the head of a queue: waiting for credits / low power
	if item.state == UiBuildItem.State.BUILDING:
		if item.queue_state == UiSimPort.QueueState.WAIT_FUNDS:
			_chip(Vector2(ir.position.x + 4.0, ir.position.y + 22.0), "$", UiPalette.CREDITS)
		elif item.queue_state == UiSimPort.QueueState.LOW_POWER:
			_chip(Vector2(ir.position.x + 4.0, ir.position.y + 22.0), "", UiPalette.WARN)
	var c: Vector2 = ir.get_center() - Vector2(0.0, 6.0)
	match item.state:
		UiBuildItem.State.READY:
			_banner(ir, "READY", UiPalette.OK, _pulse)
		UiBuildItem.State.PLACING:
			_banner(ir, "PLACING", UiPalette.POWER, 1.0)
		UiBuildItem.State.ON_HOLD:
			_banner(ir, "LAUNCHING" if item.kind == UiBuildItem.Kind.SUPERWEAPON else "ON HOLD", UiPalette.WARN, 1.0)
		UiBuildItem.State.LOCKED:
			draw_rect(ir, Color(0, 0, 0, 0.35))
			UiGlyphs.draw(self, UiGlyphs.Glyph.LOCK, Rect2(c - Vector2(10.0, 12.0), Vector2(20.0, 20.0)), UiPalette.TEXT_DIM, 1.6)
		UiBuildItem.State.BLOCKED:
			draw_rect(ir, Color(0.2, 0.0, 0.0, 0.3))
			UiGlyphs.draw(self, UiGlyphs.Glyph.WARNING, Rect2(c - Vector2(10.0, 12.0), Vector2(20.0, 20.0)), UiPalette.WARN, 1.6)
		UiBuildItem.State.DONE:
			draw_rect(ir, Color(0, 0, 0, 0.32))
			UiGlyphs.draw(self, UiGlyphs.Glyph.CHECK, Rect2(c - Vector2(11.0, 12.0), Vector2(22.0, 22.0)), UiPalette.OK, 2.0)
		UiBuildItem.State.AVAILABLE:
			if item.kind == UiBuildItem.Kind.POWER or item.kind == UiBuildItem.Kind.SUPERWEAPON:
				draw_rect(ir, Color(UiPalette.OK, 0.10 * _pulse))
				_banner(ir, "READY", UiPalette.OK, _pulse)


func _chip(p: Vector2, text: String, col: Color) -> void:
	draw_circle(p + Vector2(7.0, 7.0), 8.0, Color(0, 0, 0, 0.72))
	draw_arc(p + Vector2(7.0, 7.0), 8.0, 0.0, TAU, 16, Color(col, 0.9), 1.2, true)
	if text != "":
		draw_string(UiFonts.get_font(UiFonts.Role.NUM), p + Vector2(0.0, 11.5), text, HORIZONTAL_ALIGNMENT_CENTER, 14.0, 13, col)
	else:
		UiGlyphs.draw(self, UiGlyphs.Glyph.BOLT, Rect2(p + Vector2(2.0, 2.0), Vector2(10.0, 10.0)), col, 1.4)


func _banner(ir: Rect2, text: String, col: Color, alpha: float) -> void:
	var b := Rect2(ir.position.x, ir.get_center().y - 10.0, ir.size.x, 20.0)
	draw_rect(b, Color(col.darkened(0.55), 0.82))
	draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 1.0), Color(col, alpha))
	draw_rect(Rect2(b.position.x, b.end.y - 1.0, b.size.x, 1.0), Color(col, alpha))
	draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(b.position.x, b.position.y + 14.5), text, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 12, Color(col.lightened(0.35), alpha))


func _footer(r: Rect2) -> void:
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var acc: Color = _accent()
	var name_col: Color = UiPalette.TEXT
	if item.state == UiBuildItem.State.LOCKED:
		name_col = UiPalette.TEXT_MUTE
	elif item.state == UiBuildItem.State.BUILDING:
		name_col = acc.lightened(0.25)
	var nm: String = UiDraw.ellipsize(bold, item.display_name, 14, r.size.x - 8.0)
	draw_string(bold, Vector2(4.0, ICON_H + 19.0), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, 14, name_col)
	var status: String = ""
	var sc: Color = UiPalette.TEXT_MUTE
	match item.state:
		UiBuildItem.State.BUILDING:
			status = "BUILDING"
			sc = acc
		UiBuildItem.State.QUEUED:
			status = "QUEUED"
		UiBuildItem.State.READY:
			status = "PLACE STRUCTURE" if item.kind == UiBuildItem.Kind.STRUCTURE else "READY"
			sc = UiPalette.OK
		UiBuildItem.State.PLACING:
			status = "PLACING..."
			sc = UiPalette.POWER
		UiBuildItem.State.ON_HOLD:
			status = "ON HOLD"
			sc = UiPalette.WARN
		UiBuildItem.State.LOCKED:
			status = UiDraw.ellipsize(body, ("Needs " + item.requires_text) if item.requires_text != "" else "LOCKED", 12, r.size.x - 8.0)
			sc = UiPalette.WARN.darkened(0.2)
		UiBuildItem.State.BLOCKED:
			status = UiDraw.ellipsize(body, item.reason_text if item.reason_text != "" else "BLOCKED", 12, r.size.x - 8.0)
			sc = UiPalette.WARN
		UiBuildItem.State.UNAFFORDABLE:
			status = "NEED CREDITS"
			sc = UiPalette.DANGER
		UiBuildItem.State.COOLDOWN:
			status = "CHARGING"
			sc = _accent2()
		UiBuildItem.State.DONE:
			status = "RESEARCHED"
			sc = UiPalette.OK
		_:
			status = "T%d" % item.tier if item.tier > 1 else ""
	if status != "":
		draw_string(body, Vector2(4.0, ICON_H + 33.0), status, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8.0, 12, sc)
	if item.is_sweeping():
		var track := Rect2(5.0, r.size.y - 5.0, r.size.x - 10.0, 2.0)
		draw_rect(track, Color(0, 0, 0, 0.6))


var _pill: UiStyleBox = null


func _pill_box() -> UiStyleBox:
	if _pill == null:
		var a2: Color = _accent2()
		_pill = UiStyleBox.new()
		_pill.fill_top = a2.lightened(0.1)
		_pill.fill_bottom = a2.darkened(0.15)
		_pill.border_color = a2.lightened(0.4)
		_pill.cuts = Vector4(4.0, 0.0, 4.0, 0.0)
		_pill.highlight = 0.0
	return _pill
