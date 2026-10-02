class_name MapFootprint
extends RefCounted
## Structure footprints (terrain_movement 3.6). A footprint is an authored w x h shape (optional row-major solid
## mask) that can be rotated by `orient` (0..3 = 0/90/180/270 degrees clockwise, x east, y south). The numbers
## (fp_w, fp_h, fp_mask) belong to DefStructure / DefNeutral; MapData keeps the def -> MapFootprint table
## (`footprint_of`). The static helpers work on raw numbers; the instance form is what the kernel reads
## (`rotatable`, `size_oriented`).

var w: int = 1
var h: int = 1
## Row-major w*h, non-zero = solid; empty = the full rectangle.
var mask: PackedByteArray = PackedByteArray()
var rotatable: bool = false


func _init(fp_w: int = 1, fp_h: int = 1, fp_mask: PackedByteArray = PackedByteArray(), can_rotate: bool = false) -> void:
	w = fp_w
	h = fp_h
	mask = fp_mask.duplicate()
	rotatable = can_rotate


## Packed `(w << 8) | h` of the footprint after rotation by `orient` (orient is ignored when not rotatable).
func size_oriented(orient: int) -> int:
	return oriented_size(w, h, orient if rotatable else 0)


## Solid cell indices at top-left (cx, cy) of the oriented bounding box; -1 when any cell is outside the map.
func cells_at(orient: int, cx: int, cy: int, out: PackedInt32Array, map_w: int, map_h: int) -> int:
	return cells(w, h, mask, orient if rotatable else 0, cx, cy, out, map_w, map_h)


## Cell indices of the SOLID cells (fp_mask empty = full rectangle, else row-major fp_w*fp_h, non-zero = blocked)
## when the authored shape is rotated by `orient` and its top-left cell (of the ORIENTED bounding box) is
## (cx, cy). `out` is cleared and filled in ascending index order. Returns the count, or -1 (out cleared) if any
## cell lies outside the map_w x map_h map.
## DEVIATION: the spec signature has no map size; `map_w` / `map_h` are appended.
static func cells(fp_w: int, fp_h: int, fp_mask: PackedByteArray, orient: int, cx: int, cy: int,
		out: PackedInt32Array, map_w: int, map_h: int) -> int:
	out.clear()
	var o: int = orient & 3
	var ow: int = fp_h if (o & 1) == 1 else fp_w
	var oh: int = fp_w if (o & 1) == 1 else fp_h
	if cx < 0 or cy < 0 or cx + ow > map_w or cy + oh > map_h:
		return -1
	var has_mask: bool = not fp_mask.is_empty()
	for oy: int in oh:
		for ox: int in ow:
			var ax: int = ox
			var ay: int = oy
			match o:
				1:
					ax = oy
					ay = fp_h - 1 - ox
				2:
					ax = fp_w - 1 - ox
					ay = fp_h - 1 - oy
				3:
					ax = fp_w - 1 - oy
					ay = ox
			if has_mask and fp_mask[ay * fp_w + ax] == 0:
				continue
			out.append((cy + oy) * map_w + cx + ox)
	return out.size()


## Packed `(w << 8) | h` after rotation (swapped for odd orient).
static func oriented_size(fp_w: int, fp_h: int, orient: int) -> int:
	if (orient & 1) == 1:
		return (fp_h << 8) | fp_w
	return (fp_w << 8) | fp_h


## An authored offset (dx, dy) in a w x h footprint maps to  0: (dx, dy)   1: (h-1-dy, dx)   2: (w-1-dx, h-1-dy)
## 3: (dy, w-1-dx); out[0] = dx', out[1] = dy'. Angles (exit direction, dock facing) add orient * 1024.
static func rotate_offset(fp_w: int, fp_h: int, orient: int, dx: int, dy: int, out: PackedInt32Array) -> void:
	match orient & 3:
		0:
			out[0] = dx
			out[1] = dy
		1:
			out[0] = fp_h - 1 - dy
			out[1] = dx
		2:
			out[0] = fp_w - 1 - dx
			out[1] = fp_h - 1 - dy
		_:
			out[0] = dy
			out[1] = fp_w - 1 - dx
