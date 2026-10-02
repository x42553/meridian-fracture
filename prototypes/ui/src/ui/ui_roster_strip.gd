class_name UiRosterStrip
extends Control
## Wrapped grid of unit portraits with name, tier pips and UNIQUE badge (subfaction replacements).
## Portraits are baked 3D renders (UiIconBaker), so the same pipeline serves HUD cards and menus.

var skin: UiSkin
## Entry: {name: String, icon: Texture2D, tier: int, unique: bool}
var entries: Array[Dictionary] = []
const TILE := Vector2(88.0, 82.0)
const GAP := 6.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, TILE.y * 2.0 + GAP)

func set_entries(list: Array[Dictionary]) -> void:
	entries = list
	queue_redraw()

func _draw() -> void:
	var cols: int = maxi(int((size.x + GAP) / (TILE.x + GAP)), 1)
	var bold: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var r := Rect2(float(i % cols) * (TILE.x + GAP), float(i / cols) * (TILE.y + GAP), TILE.x, TILE.y)
		var unique: bool = e.get("unique", false)
		var top: Color = Color("#141e2a").lerp(skin.tint, 0.4)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, Color("#070b10"), Color("#070b10")]))
		draw_rect(r, skin.accent2 if unique else UiPalette.LINE_DIM, false, 1.0)
		var tex: Texture2D = e.get("icon")
		if tex != null:
			draw_texture_rect(tex, UiSelectionView._fit(tex, Rect2(r.position + Vector2(2.0, 2.0), Vector2(r.size.x - 4.0, 54.0))), false)
		draw_string(bold, r.position + Vector2(3.0, 70.0), UiBuildCard._fit(bold, String(e["name"]), 12, r.size.x - 6.0), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 6.0, 12, UiPalette.TEXT)
		for t in int(e.get("tier", 1)):
			draw_rect(Rect2(r.position.x + 4.0 + float(t) * 6.0, r.position.y + 4.0, 4.0, 4.0), skin.accent)
		if unique:
			draw_rect(Rect2(r.end.x - 55.0, r.position.y + 3.0, 52.0, 13.0), skin.accent2)
			draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(r.end.x - 55.0, r.position.y + 13.0), "UNIQUE", HORIZONTAL_ALIGNMENT_CENTER, 52.0, 9, Color("#0b1016"))
