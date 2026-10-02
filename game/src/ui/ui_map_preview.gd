class_name UiMapPreview
extends Control
## Square map preview (ui.md 5.14.5): the baked terrain texture with numbered, team-coloured start markers, a spinner while the
## generator runs and an empty-frame state. Purely presentational; the lobby feeds it the texture and the marker list.

var texture: Texture2D = null:
	set(v):
		texture = v
		queue_redraw()
var busy: bool = false:
	set(v):
		busy = v
		set_process(v)
		queue_redraw()
var progress: float = 0.0
## A short message drawn over the frame ("Size too small for 6 players").
var note: String = "":
	set(v):
		note = v
		queue_redraw()
## Marker positions in 0..1 map space, colours, and the labels (slot numbers).
var marker_pos: PackedVector2Array = PackedVector2Array()
var marker_col: PackedColorArray = PackedColorArray()
var marker_txt: PackedStringArray = PackedStringArray()
var highlight: int = -1:
	set(v):
		highlight = v
		queue_redraw()

var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(280.0, 280.0)
	set_process(false)


func set_markers(pos: PackedVector2Array, cols: PackedColorArray, txt: PackedStringArray) -> void:
	marker_pos = pos
	marker_col = cols
	marker_txt = txt
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var r: Rect2 = Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	draw_rect(r, UiPalette.BG_DEEP)
	if texture != null:
		draw_texture_rect(texture, r, false)
	elif not busy:
		draw_rect(r.grow(-1.0), UiPalette.LINE_DIM, false, 1.0)
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	if busy:
		var c: Vector2 = r.get_center()
		draw_rect(r, Color(UiPalette.BG_DEEP, 0.55 if texture != null else 0.0))
		draw_arc(c, 22.0, _t * 4.0, _t * 4.0 + 4.2, 24, acc, 3.0, true)
		draw_arc(c, 22.0, 0.0, TAU, 24, Color(acc, 0.15), 2.0, true)
	var font: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	if note != "":
		var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
		var w0: float = body.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(body, r.get_center() + Vector2(-w0 * 0.5, 5.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiPalette.semantic(&"warn"))
	for i: int in marker_pos.size():
		var p: Vector2 = r.position + marker_pos[i] * s
		var col: Color = marker_col[i]
		var rad: float = 12.0 if i != highlight else 15.0
		draw_circle(p, rad + 2.0, Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(p, rad, col)
		draw_arc(p, rad, 0.0, TAU, 20, UiPalette.TEXT if i == highlight else Color(1.0, 1.0, 1.0, 0.55), 1.5, true)
		var txt: String = marker_txt[i]
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, p + Vector2(-w * 0.5, 4.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.04, 0.05, 0.07))
	draw_rect(r, Color(acc, 0.35), false, 1.0)
