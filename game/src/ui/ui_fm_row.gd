class_name UiFmRow
extends Control
## One entry of the Field Manual list (ui.md 5.17): glyph, name, tier pips, credits cost and a second line with the class /
## role. Custom drawn (one canvas item per row). `selected` fires on click, Enter or Space.

signal selected()

const H: float = 54.0

var kind: int = 0
var def_index: int = -1
var is_selected: bool = false:
	set(v):
		if v != is_selected:
			is_selected = v
			queue_redraw()
var title: String = ""
var subtitle: String = ""
var cost_text: String = ""
var glyph: int = 0
## Baked model icon (units and structures; null until the bake finishes, then the class glyph keeps the slot).
var icon: Texture2D = null:
	set(v):
		icon = v
		queue_redraw()
var def_id: String = ""
var tier: int = 0
var badge: String = ""
var dimmed: bool = false

var _hover: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(0.0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## Fills the row from a model card.
func set_card(card: Dictionary) -> void:
	kind = int(card["kind"])
	def_index = int(card["index"])
	def_id = str(card.get("id", ""))
	title = str(card["name"])
	glyph = int(card.get("glyph", 0))
	tier = int(card.get("tier", 0))
	var cost: int = int(card.get("cost", 0))
	cost_text = DefFormat.credits_text(cost) if cost > 0 else ""
	badge = "UNIQUE" if bool(card.get("unique", false)) else ("SUMMON" if bool(card.get("summon", false)) else "")
	match kind:
		DefEnums.Kind.UNIT:
			subtitle = str(card.get("text", ""))
		DefEnums.Kind.STRUCTURE:
			subtitle = str(card.get("text", ""))
		_:
			subtitle = str(card.get("text", ""))
	accessibility_name = "%s, %s" % [title, cost_text] if not cost_text.is_empty() else title
	tooltip_text = str(card.get("text", ""))
	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT, NOTIFICATION_RESIZED:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		selected.emit()
		accept_event()
	elif event.is_action_pressed(&"ui_accept") and has_focus():
		selected.emit()
		accept_event()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	if is_selected:
		draw_style_box(get_theme_stylebox(&"hover", &"PopupMenu"), r)
		draw_rect(Rect2(0.0, 0.0, 3.0, size.y), acc)
	elif _hover:
		draw_rect(r, Color(acc, 0.10))
	else:
		draw_rect(r, Color(1.0, 1.0, 1.0, 0.03))
	draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), Color(1.0, 1.0, 1.0, 0.05))
	var gcol: Color = acc if is_selected else UiPalette.TEXT_DIM
	var x: float = 54.0
	if icon != null:
		var ir: Rect2 = Rect2(6.0, 4.0, 68.0, size.y - 8.0)  # 3:2 model icon, fitted
		var iw: float = minf(ir.size.x, ir.size.y * 1.5)
		draw_texture_rect(icon, Rect2(ir.position + Vector2((ir.size.x - iw) * 0.5, 0.0), Vector2(iw, iw / 1.5)), false)
		x = 84.0
	else:
		UiDraw.glyph(self, glyph, Rect2(12.0, (size.y - 28.0) * 0.5, 28.0, 28.0), gcol, 1.8)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var right: float = size.x - 14.0
	if not cost_text.is_empty():
		var cw: float = num.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
		draw_string(num, Vector2(right - cw, 23.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, UiPalette.CREDITS)
		right -= cw + 14.0
	var name_w: float = maxf(20.0, right - x - (44.0 if tier > 0 else 0.0))
	var nm: String = UiDraw.ellipsize(bold, title, 17, name_w)
	draw_string(bold, Vector2(x, 23.0), nm, HORIZONTAL_ALIGNMENT_LEFT, name_w, 17, UiPalette.TEXT if not dimmed else UiPalette.TEXT_MUTE)
	var nw: float = bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
	var px: float = x + nw + 10.0
	for i: int in tier:
		draw_rect(Rect2(px + float(i) * 9.0, 12.0, 6.0, 6.0), acc)
	if tier > 0:
		px += float(tier) * 9.0 + 6.0
	var sub_w: float = size.x - x - 14.0
	if not badge.is_empty():
		var bw: float = 62.0
		var br: Rect2 = Rect2(size.x - 14.0 - bw, 30.0, bw, 18.0)
		draw_rect(br, Color(acc, 0.22))
		draw_rect(br, acc, false, 1.0)
		draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(br.position.x, 43.5), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, acc)
		sub_w -= bw + 8.0
	var sub: String = UiDraw.ellipsize(body, subtitle, 14, sub_w)
	draw_string(body, Vector2(x, 43.0), sub, HORIZONTAL_ALIGNMENT_LEFT, sub_w, 14, UiPalette.TEXT_MUTE)
	if has_focus():
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), r)
