class_name UiQueueStrip
extends Control
## Production queue of the selected producer: 5 slots, the first with a clock wipe. Click a slot = cancel one,
## right-click = cancel all behind it (C&C convention). Data-only widget: the HUD feeds `slots`.

signal slot_cancelled(index: int)

const SLOT := Vector2(56.0, 44.0)
const GAP := 4.0

var skin: UiSkin
var title: String = ""
## Each slot: {item: UiBuildItem, progress: float} or empty for a free slot.
var slots: Array[Dictionary] = []
var _hover: int = -1

func _init() -> void:
	custom_minimum_size = Vector2(0.0, 66.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		var i: int = _at(mb.position)
		if i >= 0 and i < slots.size() and not slots[i].is_empty():
			slot_cancelled.emit(i)
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()

func _at(p: Vector2) -> int:
	for i in 5:
		if Rect2(float(i) * (SLOT.x + GAP), 18.0, SLOT.x, SLOT.y).has_point(p):
			return i
	return -1

func _draw() -> void:
	draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(0.0, 11.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiPalette.TEXT_DIM)
	draw_string(UiFonts.get_font(UiFonts.Role.NUM), Vector2(0.0, 11.0), "%d / 5" % slots.filter(func(s: Dictionary) -> bool: return not s.is_empty()).size(), HORIZONTAL_ALIGNMENT_RIGHT, size.x, 12, skin.accent)
	for i in 5:
		var r := Rect2(float(i) * (SLOT.x + GAP), 18.0, SLOT.x, SLOT.y)
		var filled: bool = i < slots.size() and not slots[i].is_empty()
		draw_style_box(get_theme_stylebox(&"normal" if filled else &"disabled", &"Button"), r)
		if not filled:
			continue
		var it: UiBuildItem = slots[i]["item"]
		if it.icon != null:
			var ir: Rect2 = r.grow(-2.0)
			var h: float = ir.size.x / (float(it.icon.get_width()) / float(it.icon.get_height()))
			draw_texture_rect(it.icon, Rect2(ir.position.x, ir.position.y + (ir.size.y - h) * 0.5, ir.size.x, h), false, Color.WHITE.lightened(0.1 if i == _hover else 0.0))
		if i == 0:
			var p: float = float(slots[i].get("progress", 0.0))
			var poly: PackedVector2Array = UiDraw.rect_sector(r.grow(-2.0), p, 1.0)
			if poly.size() >= 3:
				draw_colored_polygon(poly, Color(0, 0, 0, 0.62))
			draw_rect(Rect2(r.position.x + 3.0, r.end.y - 5.0, (r.size.x - 6.0) * p, 2.0), skin.accent)
		if i == _hover:
			draw_rect(r, Color(UiPalette.DANGER, 0.25))
			UiGlyphs.draw(self, UiGlyphs.Glyph.CLOSE, Rect2(r.get_center() - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Color.WHITE, 1.6)
