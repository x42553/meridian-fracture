class_name UiQueueStrip
extends Control
## Production queue of the chosen producer (ui.md 5.10.8): header `FACTORY 2 // QUEUE`, `3 / 5`, hold toggle, primary
## star and producer-cycling chevrons; five slots, slot 0 with the clock wipe. Data-only: `set_data` is fed by the
## presenter. LMB on a slot -> `slot_pressed(index)` (cancel that index), RMB -> `slot_right_pressed(index)` (cancel
## every queued instance of that def).

signal slot_pressed(index: int)
signal slot_right_pressed(index: int)
signal hold_toggled()
signal primary_pressed()
signal cycled(direction: int)

const SLOT := Vector2(56.0, 44.0)
const GAP: float = 4.0
const HEAD_H: float = 18.0
const MAX_SLOTS: int = 5

var title: String = ""
var count: int = 0
var held: bool = false
var primary: bool = false
var can_cycle: bool = false
## Per slot: {item: UiBuildItem, progress: float 0..1} or {} for a free slot.
var slots: Array[Dictionary] = []
var _hover: int = -1
var _hover_btn: int = -1


func _init() -> void:
	custom_minimum_size = Vector2(0.0, float(UiMetrics.QUEUE_H))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Replaces the shown state.
func set_data(p_title: String, p_slots: Array[Dictionary], p_held: bool, p_primary: bool, p_can_cycle: bool) -> void:
	title = p_title
	slots = p_slots
	held = p_held
	primary = p_primary
	can_cycle = p_can_cycle
	count = 0
	for s: Dictionary in slots:
		if not s.is_empty():
			count += 1
	queue_redraw()


func slot_rect(i: int) -> Rect2:
	return Rect2(float(i) * (SLOT.x + GAP), HEAD_H + 2.0, SLOT.x, SLOT.y)


## Header buttons right to left: hold, star, next, previous. Rects in local px.
func button_rect(idx: int) -> Rect2:
	var bx: float = size.x - 54.0 - float(idx + 1) * 20.0
	return Rect2(bx, 0.0, 18.0, 16.0)


func _slot_at(p: Vector2) -> int:
	for i: int in MAX_SLOTS:
		if slot_rect(i).has_point(p):
			return i
	return -1


func _button_at(p: Vector2) -> int:
	for i: int in 4:
		if button_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _slot_at(mm.position)
		var b: int = _button_at(mm.position)
		if h != _hover or b != _hover_btn:
			_hover = h
			_hover_btn = b
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var i: int = _slot_at(mb.position)
	if i >= 0 and i < slots.size() and not slots[i].is_empty():
		if mb.button_index == MOUSE_BUTTON_LEFT:
			slot_pressed.emit(i)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_pressed.emit(i)
		accept_event()
		return
	var b2: int = _button_at(mb.position)
	if b2 >= 0 and mb.button_index == MOUSE_BUTTON_LEFT:
		match b2:
			0:
				hold_toggled.emit()
			1:
				primary_pressed.emit()
			2:
				if can_cycle:
					cycled.emit(1)
			3:
				if can_cycle:
					cycled.emit(-1)
	accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			_hover_btn = -1
			queue_redraw()
		NOTIFICATION_THEME_CHANGED:
			queue_redraw()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	draw_string(head, Vector2(0.0, 12.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 130.0, 12, UiPalette.TEXT_DIM)
	draw_string(num, Vector2(0.0, 13.0), "%d / %d" % [count, MAX_SLOTS], HORIZONTAL_ALIGNMENT_RIGHT, size.x, 13, acc)
	# header buttons: hold, primary star, next / previous producer
	var glyphs: Array[int] = [UiGlyphs.Glyph.HOLD, UiGlyphs.Glyph.COMMAND, UiGlyphs.Glyph.CHEVRON_DOWN, UiGlyphs.Glyph.CHEVRON_UP]
	for i: int in 4:
		var br: Rect2 = button_rect(i)
		var on: bool = (i == 0 and held) or (i == 1 and primary)
		var enabled: bool = i < 2 or can_cycle
		if not enabled:
			continue
		var col: Color = UiPalette.WARN if (i == 0 and held) else (UiPalette.CREDITS if (i == 1 and primary) else (UiPalette.TEXT if i == _hover_btn else UiPalette.TEXT_DIM))
		if on or i == _hover_btn:
			draw_rect(br, Color(col, 0.16))
		UiGlyphs.draw(self, glyphs[i], br.grow(-2.0), col, 1.4)
	for i2: int in MAX_SLOTS:
		var r: Rect2 = slot_rect(i2)
		var filled: bool = i2 < slots.size() and not slots[i2].is_empty()
		draw_style_box(get_theme_stylebox(&"normal" if filled else &"disabled", &"Button"), r)
		if not filled:
			continue
		var it: UiBuildItem = slots[i2]["item"]
		var ir: Rect2 = r.grow(-2.0)
		if it.icon != null:
			var hh: float = ir.size.x / (float(it.icon.get_width()) / float(it.icon.get_height()))
			draw_texture_rect(it.icon, Rect2(ir.position.x, ir.position.y + (ir.size.y - hh) * 0.5, ir.size.x, hh), false, Color.WHITE.lightened(0.1 if i2 == _hover else 0.0))
		else:
			UiGlyphs.draw(self, it.role_glyph, Rect2(ir.get_center() - Vector2(11.0, 13.0), Vector2(22.0, 22.0)), acc.darkened(0.1), 1.6)
		if i2 == 0:
			var p: float = float(slots[i2].get("progress", 0.0))
			var poly: PackedVector2Array = UiDraw.rect_sector(ir, p, 1.0)
			if poly.size() >= 3:
				draw_colored_polygon(poly, Color(0.32, 0.20, 0.0, 0.62) if held else Color(0, 0, 0, 0.62))
			draw_rect(Rect2(r.position.x + 3.0, r.end.y - 5.0, (r.size.x - 6.0) * p, 2.0), UiPalette.WARN if held else acc)
		if i2 == _hover:
			draw_rect(r, Color(UiPalette.DANGER, 0.25))
			UiGlyphs.draw(self, UiGlyphs.Glyph.CLOSE, Rect2(r.get_center() - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Color.WHITE, 1.6)
