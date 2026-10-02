class_name UiWorldOverlay
extends Control
## 2D layer drawn over the 3D view: selection brackets, health bars, rally lines. Reads entity snapshots
## (pos, radius, hp, selected, team) and the camera; never touches the sim. mouse_filter IGNORE so clicks
## fall through to the input controller. One draw_multiline_colors for all brackets keeps the command count low.

var camera: Camera3D
var entities: Array[Dictionary] = []
var skin: UiSkin
## Last draw cost in microseconds (perf counter shown by the benchmark).
var last_draw_us: int = 0
var last_visible: int = 0
var show_all_bars: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _team_color(team: int) -> Color:
	match team:
		0:
			return UiPalette.OK
		1:
			return UiPalette.DANGER
	return UiPalette.POWER

func _draw() -> void:
	if camera == null:
		return
	var t0: int = Time.get_ticks_usec()
	var view: Rect2 = Rect2(Vector2(-40.0, -40.0), size + Vector2(80.0, 80.0))
	var right: Vector3 = camera.global_transform.basis.x
	var seg := PackedVector2Array()
	var seg_col := PackedColorArray()
	var visible: int = 0
	for e in entities:
		var hp: float = float(e["hp"])
		var selected: bool = e["selected"]
		if not selected and hp >= 0.99 and not show_all_bars:
			continue
		var pos: Vector3 = e["pos"]
		if camera.is_position_behind(pos):
			continue
		var sp: Vector2 = camera.unproject_position(pos + Vector3(0.0, 0.8 if not e["struct"] else 2.0, 0.0))
		if not view.has_point(sp):
			continue
		visible += 1
		var radius: float = float(e["radius"])
		var rp: float = absf(camera.unproject_position(pos + right * radius).x - camera.unproject_position(pos).x)
		var col: Color = _team_color(int(e["team"]))
		var half: float = maxf(rp * 1.1, 10.0)
		if selected:
			var l: float = maxf(half * 0.42, 5.0)
			var o: Vector2 = sp + Vector2(0.0, half * 0.15)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := Vector2(o.x + sx * half, o.y + sy * half * 0.78)
					seg.append(corner)
					seg.append(corner - Vector2(sx * l, 0.0))
					seg.append(corner)
					seg.append(corner - Vector2(0.0, sy * l * 0.8))
					seg_col.append(col)
					seg_col.append(col)
		var bw: float = clampf(half * 1.7, 24.0, 90.0)
		var by: float = sp.y - half * 0.78 - 9.0
		var bar := Rect2(sp.x - bw * 0.5, by, bw, 4.0)
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), UiSelectionView._hp_color(hp) if int(e["team"]) == 0 else col.lerp(Color.WHITE, 0.15))
	if not seg.is_empty():
		draw_multiline_colors(seg, seg_col, 1.6)
	last_visible = visible
	last_draw_us = Time.get_ticks_usec() - t0
