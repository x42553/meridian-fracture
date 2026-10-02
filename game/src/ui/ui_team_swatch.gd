class_name UiTeamSwatch
extends Control
## Live preview of the eight team colours in both colour sets (ui.md 5.18.1 "Accessibility", first-run dialog): two rows of
## squares, the active set outlined. Each square carries its player number so the swatch is readable without colour.

const SQ: float = 30.0
const GAP: float = 6.0
const LABEL_W: float = 412.0  ## default label column: the options page aligns the squares with its control column

var mode: String = "normal"
var label_w: float = LABEL_W
var _font: Font = null


func _init(label_width: float = LABEL_W) -> void:
	label_w = label_width
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(label_w + 8.0 * (SQ + GAP), SQ * 2.0 + GAP + 4.0)
	_font = UiFonts.get_font(UiFonts.Role.NUM)


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		queue_redraw()


func _draw() -> void:
	var sets: Array = [["Standard", UiPalette.TEAM_DEFAULT, "normal"], ["Colour-safe", UiPalette.TEAM_CVD, "cvd"]]
	for r: int in 2:
		var y: float = float(r) * (SQ + GAP)
		var info: Array = sets[r]
		var active: bool = str(info[2]) == mode
		draw_string(UiFonts.get_font(UiFonts.Role.BODY), Vector2(0.0, y + SQ * 0.68), str(info[0]) + " palette", HORIZONTAL_ALIGNMENT_LEFT, label_w - 6.0, 15,
			UiPalette.TEXT if active else UiPalette.TEXT_MUTE)
		var cols: PackedStringArray = info[1]
		for i: int in 8:
			var rect: Rect2 = Rect2(label_w + float(i) * (SQ + GAP), y, SQ, SQ)
			var col: Color = Color(cols[i])
			draw_rect(rect, col)
			draw_rect(rect, Color(1.0, 1.0, 1.0, 0.9) if active else UiPalette.LINE, false, 2.0 if active else 1.0)
			var lum: float = UiA11y.luminance(col)
			draw_string(_font, rect.position + Vector2(0.0, SQ * 0.68), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, SQ, 15,
				Color.BLACK if lum > 0.35 else Color.WHITE)
