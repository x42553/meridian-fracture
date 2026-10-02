class_name AiResourceSites
extends RefCounted
## Deposit-field sites (ai.md 4.2): position, stock, land / amphibious region, refinery claim, saturation, route length from
## my HQ, threat and a kind (0 main, 1 near expansion, 2 far, 3 enemy side). `refresh_step` is cursor based (one row per
## call) so the knowledge-base slot can spread the work. All positions in sub-cell units.

const K_MAIN: int = 0
const K_NEAR: int = 1
const K_FAR: int = 2
const K_ENEMY: int = 3

var count: int = 0
var id: PackedInt32Array = PackedInt32Array()  ## AiWorldView deposit (field) id
var x: PackedInt32Array = PackedInt32Array()
var y: PackedInt32Array = PackedInt32Array()
var left: PackedInt32Array = PackedInt32Array()
var region_land: PackedInt32Array = PackedInt32Array()
var region_amph: PackedInt32Array = PackedInt32Array()
var claimed_refinery_eid: PackedInt32Array = PackedInt32Array()  ## -1 none
var collectors_assigned: PackedInt32Array = PackedInt32Array()
var path_len_c: PackedInt32Array = PackedInt32Array()  ## cells from my HQ, -1 unreachable
var threat_q8: PackedInt32Array = PackedInt32Array()
var kind: PackedInt32Array = PackedInt32Array()
var cursor: int = 0
var home_x: int = 0
var home_y: int = 0


## Builds the rows from the view's deposit list; home = my start cell.
func setup(view: AiWorldView, enemy_starts: PackedInt32Array) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	count = view.deposit_ids(ids)
	for a: PackedInt32Array in [id, x, y, left, region_land, region_amph, claimed_refinery_eid, collectors_assigned, path_len_c, threat_q8, kind]:
		a.resize(count)
	var hcx: int = view.start_cell_x(view.me())
	var hcy: int = view.start_cell_y(view.me())
	home_x = hcx * Fp.CELL + Fp.CELL / 2
	home_y = hcy * Fp.CELL + Fp.CELL / 2
	for i: int in count:
		id[i] = ids[i]
		x[i] = view.deposit_x(ids[i])
		y[i] = view.deposit_y(ids[i])
		left[i] = view.deposit_left(ids[i])
		var cx: int = x[i] >> Fp.CELL_SHIFT
		var cy: int = y[i] >> Fp.CELL_SHIFT
		region_land[i] = view.region(cx, cy, AiTypes.MoveClass.TRACKED)
		region_amph[i] = view.region(cx, cy, AiTypes.MoveClass.AMPHIBIOUS)
		claimed_refinery_eid[i] = -1
		collectors_assigned[i] = 0
		path_len_c[i] = -1
		threat_q8[i] = 0
		kind[i] = _classify(cx, cy, hcx, hcy, enemy_starts)


func _classify(cx: int, cy: int, hcx: int, hcy: int, enemy_starts: PackedInt32Array) -> int:
	var dme: int = maxi(absi(cx - hcx), absi(cy - hcy))
	var de: int = 1 << 20
	for i: int in enemy_starts.size() / 2:
		de = mini(de, maxi(absi(cx - enemy_starts[2 * i]), absi(cy - enemy_starts[2 * i + 1])))
	if dme <= 14:
		return K_MAIN
	if de < dme:
		return K_ENEMY
	if dme <= 34:
		return K_NEAR
	return K_FAR


## Refreshes one row (stock, saturation, threat, route length) and advances the cursor. Cost ~5 wu.
func refresh_step(view: AiWorldView, kb: AiKnowledge, route: AiRouteGraph) -> void:
	if count == 0:
		return
	var i: int = cursor
	cursor = (cursor + 1) % count
	left[i] = view.deposit_left(id[i])
	collectors_assigned[i] = view.deposit_harvesters(id[i])
	threat_q8[i] = kb.threat_circle(x[i], y[i], 6 * Fp.CELL) * 256 / maxi(1, 1000)
	if path_len_c[i] < 0 and route != null and route.is_bound():
		var pts: PackedInt32Array = PackedInt32Array()
		if route.route(home_x, home_y, x[i], y[i], AiTypes.MoveClass.TRACKED, 0, pts) > 0:
			path_len_c[i] = route.route_cells(pts)


## Row of the nearest unclaimed, non-empty site to (px, py) of kind <= max_kind, -1 if none.
func best_free_site(px: int, py: int, max_kind: int = K_FAR) -> int:
	var best: int = -1
	var best_d: int = 1 << 60
	for i: int in count:
		if kind[i] > max_kind or left[i] <= 0 or claimed_refinery_eid[i] >= 0:
			continue
		var dx: int = x[i] - px
		var dy: int = y[i] - py
		var d: int = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


func row_of_id(deposit_id: int) -> int:
	for i: int in count:
		if id[i] == deposit_id:
			return i
	return -1


func total_left(max_kind: int = K_FAR) -> int:
	var s: int = 0
	for i: int in count:
		if kind[i] <= max_kind:
			s += left[i]
	return s


func state_hash() -> int:
	return AiRng.hash_ints(left, count)
