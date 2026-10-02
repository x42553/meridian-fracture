class_name SimPlacementResult
extends RefCounted
## Caller-owned, reusable placement / ghost validation result (economy 4.6). `cells` holds one CF_* code per
## solid cell of the rotated bounding box (w * h entries, row-major from the origin cell).

var reason: int = 0  ## RSN_*
var ox: int = 0  ## origin (top-left) cell of the rotated footprint
var oy: int = 0
var w: int = 0  ## rotated footprint size in cells
var h: int = 0
var in_radius: bool = false
var apron_ok: bool = false
var berth_ok: bool = false
var cells: PackedByteArray = PackedByteArray()


func reset(p_ox: int, p_oy: int, p_w: int, p_h: int) -> void:
	reason = 0
	ox = p_ox
	oy = p_oy
	w = p_w
	h = p_h
	in_radius = false
	apron_ok = true
	berth_ok = true
	cells.resize(maxi(p_w * p_h, 0))
	cells.fill(0)
