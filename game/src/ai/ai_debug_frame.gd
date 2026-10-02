class_name AiDebugFrame
extends RefCounted
## Plain data for overlay rendering (ai.md 4.3): circles, lines, labels, threat heat and a text panel. Produced by the AI,
## rendered by view/ui (never by the AI).

var pid: int = 0
var tick: int = 0
var circles: PackedInt32Array = PackedInt32Array()  ## stride 5: x, y, r, argb, label_idx
var lines: PackedInt32Array = PackedInt32Array()  ## stride 5: x0, y0, x1, y1, argb
var labels: PackedStringArray = PackedStringArray()
var heat_w: int = 0
var heat_h: int = 0
var heat: PackedInt32Array = PackedInt32Array()  ## threat blocks 0..255
var panel: PackedStringArray = PackedStringArray()  ## "key: value" lines


func add_circle(x: int, y: int, r: int, argb: int, label: String = "") -> void:
	var li: int = -1
	if not label.is_empty():
		li = labels.size()
		labels.append(label)
	circles.append_array(PackedInt32Array([x, y, r, argb, li]))


func add_line(x0: int, y0: int, x1: int, y1: int, argb: int) -> void:
	lines.append_array(PackedInt32Array([x0, y0, x1, y1, argb]))
