class_name ViewPlacementState
extends RefCounted
## Validator-neutral placement record (render spec 3.7). The UI fills it from SimPlacement.validate (economy,
## `SimPlacementResult.cells`, codes 0-7) or from MapBuildRules.check (map, PR_* results) and reuses one instance;
## ViewPlacementGhost reads it. It owns no logic beyond the two fill adapters.

const CF_OK: int = 0
const CF_TERRAIN: int = 1
const CF_STRUCTURE: int = 2
const CF_UNIT: int = 3
const CF_DEPOSIT: int = 4
const CF_DEBRIS: int = 5
const CF_APRON: int = 6
const CF_SHORE: int = 7
const CF_KEEPOUT: int = 8  ## map PR_KEEPOUT / PR_HALO / PR_NOBUILD

var def_idx: int = -1
var origin_cx: int = 0
var origin_cy: int = 0
var rot: int = 0  ## 0..3 clockwise quarter turns seen from above
var w: int = 0  ## footprint size AFTER rotation
var h: int = 0
var cells: PackedByteArray = PackedByteArray()  ## w * h CF_* codes, row-major; empty = colour all cells by `valid`
var valid: bool = false
var in_radius: bool = false


## Copies an economy validation result (numbering CF_OK .. CF_SHORE is shared).
func fill_from_placement(r: SimPlacementResult, p_def_idx: int, p_rot: int) -> void:
	def_idx = p_def_idx
	rot = p_rot
	origin_cx = r.ox
	origin_cy = r.oy
	w = r.w
	h = r.h
	cells = r.cells.duplicate()
	valid = r.reason == 0
	in_radius = r.in_radius


## Fills from a MapBuildRules.check result code (PR_OK = 0): the whole footprint is one colour.
func fill_from_map_check(pr: int, p_def_idx: int, cx: int, cy: int, p_w: int, p_h: int, p_rot: int) -> void:
	def_idx = p_def_idx
	rot = p_rot
	origin_cx = cx
	origin_cy = cy
	w = p_w
	h = p_h
	valid = pr == 0
	in_radius = true
	cells = PackedByteArray()
	if pr != 0:
		cells.resize(maxi(w * h, 0))
		cells.fill(code_of_map_result(pr))


## Map PR_* -> CF_* (PR_NOBUILD is the keep-out colour, water problems read as terrain).
static func code_of_map_result(pr: int) -> int:
	match pr:
		0:
			return CF_OK
		3:
			return CF_STRUCTURE  # PR_OCCUPIED
		4:
			return CF_KEEPOUT  # PR_NOBUILD
		_:
			return CF_TERRAIN  # out of bounds, terrain, needs water, water exit


## CF code of cell (ix, iy) inside the footprint; CF_OK / CF_TERRAIN by `valid` when `cells` is empty.
func cell_code(ix: int, iy: int) -> int:
	if cells.is_empty():
		return CF_OK if valid else CF_TERRAIN
	if ix < 0 or iy < 0 or ix >= w or iy >= h:
		return CF_TERRAIN
	return cells[iy * w + ix]
