class_name UiListRow
extends Control
## One row of a data list (LAN game browser, replays): fixed column widths, per-cell colour, hover / selected
## states from the Button theme styles. Custom-drawn = one canvas item per row instead of one node per cell,
## which keeps a 200-row server list cheap. `activated` fires on double click.

signal selected
signal activated

var skin: UiSkin
## Each cell: {text: String, color: Color (optional), align: int (optional HorizontalAlignment)}.
var cells: Array[Dictionary] = []
var widths: PackedFloat32Array = PackedFloat32Array()
var is_header: bool = false
var is_selected: bool = false:
	set(v):
		is_selected = v
		queue_redraw()
var dimmed: bool = false
var _hover: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(0.0, 38.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not is_header:
		if mb.double_click:
			activated.emit()
		else:
			selected.emit()
		accept_event()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if is_header:
		draw_rect(r, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), skin.accent)
	elif is_selected:
		draw_style_box(get_theme_stylebox(&"pressed", &"Button"), r)
	elif _hover:
		draw_style_box(get_theme_stylebox(&"hover", &"Button"), r)
	else:
		draw_rect(r, Color(1, 1, 1, 0.025))
		draw_rect(Rect2(0.0, size.y - 1.0, size.x, 1.0), Color(1, 1, 1, 0.04))
	var f: Font = UiFonts.get_font(UiFonts.Role.HEAD if is_header else UiFonts.Role.BODY_BOLD)
	var x: float = 14.0
	for i in cells.size():
		var w: float = widths[i]
		var c: Dictionary = cells[i]
		var col: Color = c.get("color", UiPalette.TEXT_DIM if is_header else UiPalette.TEXT)
		if dimmed and not is_header:
			col = col.darkened(0.4)
		draw_string(f, Vector2(x, size.y * 0.5 + (4.0 if is_header else 5.5)), String(c["text"]), c.get("align", HORIZONTAL_ALIGNMENT_LEFT), w - 10.0, 12 if is_header else 16, col)
		x += w
