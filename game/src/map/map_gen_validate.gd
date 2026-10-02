class_name MapGenValidate
extends RefCounted
## Map validation V1..V12 (terrain_movement 5.12.6) on a FINALIZED map. Connectivity is evaluated on the land-only
## guarantee set (land + fords; deep and ordinary shallow water impassable) with 3x3 clearance (the vehicle size-2
## rule: every 8-neighbour also in the set), so water is never required. `validate` returns "V<n> name" entries,
## [] = valid; `metrics` the numbers behind them. Integer only, no static state.
##
## DEVIATIONS from the spec text: V1 checks only the vehicle-c2 component (the foot set contains it, so foot
## connectivity follows); V10 attributes a contested field to every start within 125 % of its nearest start distance
## (the map records no pair); V7 uses NP_WHEELED / SZ_2 fine A* (force_mode = 1).

const DOCK_MAX_EDGE: int = 8  ## a Dock site's nearest cell is at most this far (Chebyshev) from the HQ centre
const SPREAD_MAX: int = 150  ## V7: (max - min) * 1000 / min of the detour ratios per field kind (permille)
const BLOCK_MASK: int = MapData.SF_BLOCK


static func validate(map: MapData, p_tables: MapGenTables = null) -> PackedStringArray:
	return (analyze(map, false, p_tables)["fails"] as PackedStringArray)


static func metrics(map: MapData, p_tables: MapGenTables = null) -> Dictionary:
	return analyze(map, true, p_tables)["metrics"] as Dictionary


## {"fails": PackedStringArray, "metrics": Dictionary}. `full` counts every Dock site (else the search stops at one).
## `p_tables` (default MapGenTables.load_default()) supplies the thresholds.
static func analyze(map: MapData, full: bool, p_tables: MapGenTables = null) -> Dictionary:
	var fails: PackedStringArray = PackedStringArray()
	var w: int = map.w
	var h: int = map.h
	var n: int = map.n
	var tt: MapTerrain = map.tt
	var tables: MapGenTables = p_tables if p_tables != null else MapGenTables.load_default()
	var ns: int = map.spawns.size() / MapData.SPAWN_STRIDE
	var nf: int = map.fields.size() / MapData.FIELD_STRIDE
	var nnr: int = map.neutrals.size() / MapData.NEUTRAL_STRIDE
	var gp: PackedInt32Array = map.gen_params
	var resources: int = gp[7] if gp.size() > 10 else 50
	var near_water: bool = gp.size() > 10 and gp[10] != 0
	var lay_exit_r: int = tables.lay("exit_ring_r")

	# ---- guarantee mask, 3x3 clearance, flood fill from start 0 ----
	var gt: PackedByteArray = PackedByteArray()
	gt.resize(MapTerrain.COUNT)
	for t: int in MapTerrain.COUNT:
		gt[t] = 1 if tt.guarantee(t) else 0
	var gm: PackedByteArray = PackedByteArray()
	gm.resize(n)
	var nb: int = MapData.NAV_BORDER
	for y: int in range(nb, h - nb):
		for i: int in range(y * w + nb, y * w + w - nb):
			if gt[map.terrain[i]] != 0 and (map.flags[i] & BLOCK_MASK) == 0:
				gm[i] = 1
	var h3: PackedByteArray = PackedByteArray()
	h3.resize(n)
	for y: int in h:
		for i: int in range(y * w + 1, y * w + w - 1):
			h3[i] = gm[i - 1] & gm[i] & gm[i + 1]
	var c2: PackedByteArray = PackedByteArray()
	c2.resize(n)
	for y: int in range(1, h - 1):
		for i: int in range(y * w + 1, y * w + w - 1):
			c2[i] = h3[i - w] & h3[i] & h3[i + w]
	var reach: PackedByteArray = PackedByteArray()
	reach.resize(n)
	var scell: PackedInt32Array = PackedInt32Array()
	for k: int in ns:
		scell.append(map.spawns[k * MapData.SPAWN_STRIDE + 1])
	var reach_n: int = 0
	if ns > 0 and c2[scell[0]] != 0:
		var stack: PackedInt32Array = PackedInt32Array()
		stack.resize(n)
		var sp: int = 1
		stack[0] = scell[0]
		reach[scell[0]] = 1
		reach_n = 1
		while sp > 0:
			sp -= 1
			var c: int = stack[sp]
			var d: int = c + 1
			if c2[d] != 0 and reach[d] == 0:
				reach[d] = 1
				stack[sp] = d
				sp += 1
			d = c - 1
			if c2[d] != 0 and reach[d] == 0:
				reach[d] = 1
				stack[sp] = d
				sp += 1
			d = c + w
			if c2[d] != 0 and reach[d] == 0:
				reach[d] = 1
				stack[sp] = d
				sp += 1
			d = c - w
			if c2[d] != 0 and reach[d] == 0:
				reach[d] = 1
				stack[sp] = d
				sp += 1
		reach_n = 0
		for i: int in n:
			reach_n += reach[i]

	# V1
	var v1: bool = ns > 0
	for k: int in ns:
		if reach[scell[k]] == 0:
			v1 = false
	if not v1:
		fails.append("V1 starts_disconnected")

	# V2 exits: arcs >= 2, or >= 50 % of the ring cells inside the playable interior covered
	var exits: PackedInt32Array = PackedInt32Array()
	var covered_ring: PackedInt32Array = PackedInt32Array()
	var v2: bool = true
	for k: int in ns:
		var ea: PackedInt32Array = _exit_arcs(reach, map.terrain, w, h, scell[k] % w, scell[k] / w, lay_exit_r)
		exits.append(ea[0])
		covered_ring.append(ea[1])
		if ea[0] < 2 and ea[1] * 2 < ea[2]:
			v2 = false
	if not v2:
		fails.append("V2 few_exits")

	# V3 fields reachable (every deposit cell and the centre)
	var field_ok: PackedByteArray = PackedByteArray()
	field_ok.resize(nf + 65)
	field_ok.fill(1)
	var v3: bool = true
	for i: int in n:
		var f: int = map.field_of[i]
		if f > 0 and reach[i] == 0:
			field_ok[f] = 0
			v3 = false
	for r: int in nf:
		var fc: int = map.fields[r * MapData.FIELD_STRIDE + 1]
		if reach[fc] == 0:
			field_ok[map.fields[r * MapData.FIELD_STRIDE]] = 0
			v3 = false
	if not v3:
		fails.append("V3 field_unreachable")

	# V4 buildable start area: cells of TF_BUILD terrain (deposit rings excluded from the rule, as in the spec text)
	var v4: bool = true
	var min_build: int = tables.lay("min_buildable_start")
	var br: int = tables.lay("start_buildable_r")
	for k: int in ns:
		var cx: int = scell[k] % w
		var cy: int = scell[k] / w
		var cnt: int = 0
		for y: int in range(maxi(0, cy - br), mini(h, cy + br + 1)):
			for x: int in range(maxi(0, cx - br), mini(w, cx + br + 1)):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= br * br and (tt.flags(map.terrain[y * w + x]) & MapTerrain.TF_BUILD) != 0 \
						and (map.flags[y * w + x] & BLOCK_MASK) == 0:
					cnt += 1
		if cnt < min_build:
			v4 = false
	if not v4:
		fails.append("V4 start_area_small")

	# V5 neutrals reachable
	var v5: bool = true
	for r: int in nnr:
		var b: int = r * MapData.NEUTRAL_STRIDE
		var cell: int = map.neutrals[b + 1]
		var x0: int = cell % w
		var y0: int = cell / w
		var touch: bool = false
		for y: int in range(y0 - 1, y0 + map.neutrals[b + 3] + 1):
			for x: int in range(x0 - 1, x0 + map.neutrals[b + 2] + 1):
				if reach[y * w + x] != 0:
					touch = true
		if not touch:
			v5 = false
	if not v5:
		fails.append("V5 neutral_unreachable")

	# V6 route fraction
	var interior: int = (w - 2 * MapData.RIM_W) * (h - 2 * MapData.RIM_W)
	var route_pct: int = reach_n * 100 / maxi(1, interior)
	if route_pct < tables.fam_min_route_pct(map.family):
		fails.append("V6 route_fraction")

	# V8 water never required: no start / field / neutral footprint cell on water (fords count as water here)
	var v8: bool = true
	for k: int in ns:
		if _wet(map.kind[scell[k]]):
			v8 = false
	for i: int in n:
		if map.field_of[i] != 0 and _wet(map.kind[i]):
			v8 = false
	for r: int in nnr:
		var b: int = r * MapData.NEUTRAL_STRIDE
		var cell: int = map.neutrals[b + 1]
		for y: int in range(cell / w, cell / w + map.neutrals[b + 3]):
			for x: int in range(cell % w, cell % w + map.neutrals[b + 2]):
				if _wet(map.kind[y * w + x]):
					v8 = false
	if not v8:
		fails.append("V8 water_required")

	# V9 structural
	var v9: bool = true
	var rim: int = MapData.RIM_W
	for y: int in h:
		for x: int in w:
			if mini(mini(x, y), mini(w - 1 - x, h - 1 - y)) < rim and gt[map.terrain[y * w + x]] != 0:
				v9 = false
	var fsum: int = 0
	for r: int in nf:
		fsum += map.fields[r * MapData.FIELD_STRIDE + 4]
		if map.fields[r * MapData.FIELD_STRIDE] > 64:
			v9 = false
	var dsum: int = 0
	for i: int in n:
		dsum += map.deposit_max[i]
	if nf > 64 or fsum != dsum or ns != map.slots:
		v9 = false
	var hq: PackedInt32Array = PackedInt32Array()
	for k: int in ns:
		hq.clear()
		var cx: int = scell[k] % w
		var cy: int = scell[k] / w
		for y: int in range(cy - 1, cy + 2):
			for x: int in range(cx - 1, cx + 2):
				hq.append(y * w + x)
		if MapBuildRules.check_land(map, hq) != MapBuildRules.PR_OK:
			v9 = false
	if not v9:
		fails.append("V9 structural")

	# V10 economy budget
	var credits: PackedInt32Array = PackedInt32Array()
	credits.resize(ns)
	var budget: int = (tables.deposit["budget_min"] as int) * (50 + resources) / 100
	for r: int in nf:
		var b: int = r * MapData.FIELD_STRIDE
		if field_ok[map.fields[b]] == 0:
			continue
		var owner: int = map.fields[b + 9]
		if owner >= 0 and owner < ns:
			credits[owner] += map.fields[b + 4]
		else:
			var fc: int = map.fields[b + 1]
			var dmin: int = 1 << 40
			for k: int in ns:
				dmin = mini(dmin, _d2(scell[k], fc, w))
			for k: int in ns:
				if _d2(scell[k], fc, w) * 16 <= dmin * 25:
					credits[k] += map.fields[b + 4]
	var v10: bool = ns > 0
	for k: int in ns:
		if credits[k] < budget:
			v10 = false
	if not v10:
		fails.append("V10 economy_budget")

	# V11 dock sites (coast + start_near_water)
	var docks: PackedInt32Array = PackedInt32Array()
	if near_water and map.family == MapGenParams.FAM_COAST:
		var v11: bool = true
		for k: int in ns:
			var cnt: int = dock_sites(map, scell[k] % w, scell[k] / w, not full)
			docks.append(cnt)
			if cnt == 0:
				v11 = false
		if not v11:
			fails.append("V11 no_dock")

	# V12 neutral separation
	var v12: bool = true
	var sd: int = tables.lay("neutral_start_dist")
	var fd: int = tables.lay("neutral_field_dist")
	for r: int in nnr:
		var b: int = r * MapData.NEUTRAL_STRIDE
		var cell: int = map.neutrals[b + 1]
		var lx: int = cell % w + (map.neutrals[b + 2] - 1) / 2
		var ly: int = cell / w + (map.neutrals[b + 3] - 1) / 2
		for k: int in ns:
			if maxi(absi(scell[k] % w - lx), absi(scell[k] / w - ly)) < sd:
				v12 = false
		for q: int in nf:
			var fc: int = map.fields[q * MapData.FIELD_STRIDE + 1]
			if maxi(absi(fc % w - lx), absi(fc / w - ly)) < fd:
				v12 = false
	if not v12:
		fails.append("V12 neutral_separation")

	# V7 fairness (needs a connected, reachable map)
	var spread: int = 0
	if v1 and v3 and map.nav != null:
		spread = _fairness(map, scell)
		if spread < 0:
			fails.append("V7 no_path")
			spread = 0
		elif spread > SPREAD_MAX:
			fails.append("V7 unfair_access")

	var m: Dictionary = {"exits_per_start": exits, "exit_ring_covered": covered_ring, "credits_reachable_per_start": credits, "water_required": false,
		"route_pct": route_pct, "fairness_spread_permille": spread, "dock_sites": docks, "neutrals": nnr}
	return {"fails": fails, "metrics": m}


static func _wet(k: int) -> bool:
	return k == MapTerrain.TK_SHALLOW or k == MapTerrain.TK_DEEP


static func _d2(a: int, b: int, w: int) -> int:
	var dx: int = a % w - b % w
	var dy: int = a / w - b / w
	return dx * dx + dy * dy


## [arcs, covered, valid] of the Chebyshev ring of radius r around (cx, cy): an arc is a run of >= 3 contiguous ring cells
## inside the main component, `valid` counts the dry ring cells inside the playable interior (the rim and open sea
## are neither exits nor obstacles).
static func _exit_arcs(reach: PackedByteArray, terr: PackedByteArray, w: int, h: int, cx: int, cy: int, r: int) -> PackedInt32Array:
	var ring: PackedByteArray = PackedByteArray()
	for x: int in range(cx - r, cx + r + 1):
		ring.append(_at(reach, terr, w, h, x, cy - r))
	for y: int in range(cy - r + 1, cy + r + 1):
		ring.append(_at(reach, terr, w, h, cx + r, y))
	for x: int in range(cx + r - 1, cx - r - 1, -1):
		ring.append(_at(reach, terr, w, h, x, cy + r))
	for y: int in range(cy + r - 1, cy - r, -1):
		ring.append(_at(reach, terr, w, h, cx - r, y))
	var len_r: int = ring.size()
	var covered: int = 0
	var valid: int = 0
	var start: int = -1
	for j: int in len_r:
		covered += ring[j] & 1
		valid += (ring[j] >> 1) & 1
		if (ring[j] & 1) == 0 and start < 0:
			start = j
	if start < 0:
		return PackedInt32Array([1, covered, valid])
	var arcs: int = 0
	var run: int = 0
	for j: int in len_r:
		if (ring[(start + j) % len_r] & 1) != 0:
			run += 1
		else:
			if run >= 3:
				arcs += 1
			run = 0
	if run >= 3:
		arcs += 1
	return PackedInt32Array([arcs, covered, valid])


## bit 0 = in the main component, bit 1 = inside the playable interior.
static func _at(reach: PackedByteArray, terr: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	if x < MapData.RIM_W or y < MapData.RIM_W or x >= w - MapData.RIM_W or y >= h - MapData.RIM_W:
		return 0
	var t: int = terr[y * w + x]
	if t == MapTerrain.T_DEEP or t == MapTerrain.T_SHALLOW:
		return 0  # open sea is not an obstacle to count against
	return reach[y * w + x] | 2


## Max over field kinds / ranks of the spread (permille) of detour ratios across slots; -1 when a path is missing.
static func _fairness(map: MapData, scell: PackedInt32Array) -> int:
	var ns: int = scell.size()
	var nf: int = map.fields.size() / MapData.FIELD_STRIDE
	var ps: MapPathSearch = MapPathSearch.new(map.nav)
	ps.force_mode = 1
	var worst: int = 0
	for kind: int in 4:
		var per_slot: Array[PackedInt32Array] = []
		var ranks: int = 0
		for k: int in ns:
			per_slot.append(PackedInt32Array())
		for r: int in nf:
			var b: int = r * MapData.FIELD_STRIDE
			var owner: int = map.fields[b + 9]
			if map.fields[b + 5] == kind and owner >= 0 and owner < ns:
				per_slot[owner].append(map.fields[b + 1])
				ranks = maxi(ranks, per_slot[owner].size())
		for rank: int in ranks:
			var lo: int = 1 << 40
			var hi: int = 0
			var cnt: int = 0
			for k: int in ns:
				if rank >= per_slot[k].size():
					continue
				var ratio: int = _detour(ps, map.w, scell[k], per_slot[k][rank])
				if ratio < 0:
					return -1
				lo = mini(lo, ratio)
				hi = maxi(hi, ratio)
				cnt += 1
			if cnt >= 2:
				worst = maxi(worst, (hi - lo) * 1000 / lo)
	return worst


static func _detour(ps: MapPathSearch, w: int, a: int, b: int) -> int:
	ps.begin(MapTerrain.NP_WHEELED, MapTerrain.SZ_2, a, b, 0, PackedInt32Array())
	while ps.status == MapPathSearch.ST_RUNNING:
		ps.step(1000000)
	if ps.status != MapPathSearch.ST_DONE or ps.path_cost <= 0:
		return -1
	var dx: int = absi(a % w - b % w)
	var dy: int = absi(a / w - b / w)
	return ps.path_cost * 1000 / (10 * maxi(dx, dy) + 4 * mini(dx, dy))


## Number of Dock sites (footprint position x orientation) around the HQ centre (cx, cy): a 3x3 (harbor footprint)
## buildable footprint (shore allowed) whose nearest cell is <= 8 cells away, not overlapping the HQ, with the authored
## berth (rotated) passing MapBuildRules.check_berth. `first_only` stops at the first site.
static func dock_sites(map: MapData, cx: int, cy: int, first_only: bool) -> int:
	var dims: int = MapGenLayout.neutral_dims()["neutral.harbor_terminal"] as int
	var fw: int = dims >> 8
	var fh: int = dims & 255
	var berth: PackedInt32Array = MapGenLayout.harbor_berth()
	var w: int = map.w
	var count: int = 0
	var cells: PackedInt32Array = PackedInt32Array()
	var bc: PackedInt32Array = PackedInt32Array()
	var off: PackedInt32Array = PackedInt32Array([0, 0])
	for ty: int in range(cy - DOCK_MAX_EDGE - fh + 1, cy + DOCK_MAX_EDGE + 1):
		for tx: int in range(cx - DOCK_MAX_EDGE - fw + 1, cx + DOCK_MAX_EDGE + 1):
			if tx < 0 or ty < 0 or tx + fw > w or ty + fh > map.h:
				continue
			if tx <= cx + 1 and tx + fw - 1 >= cx - 1 and ty <= cy + 1 and ty + fh - 1 >= cy - 1:
				continue  # overlaps the HQ
			if MapBuildRules.check_land(map, _rect_cells(tx, ty, fw, fh, w, cells), true) != MapBuildRules.PR_OK:
				continue
			for orient: int in 4:
				bc.clear()
				for by: int in berth[3]:
					for bx: int in berth[2]:
						MapFootprint.rotate_offset(fw, fh, orient, berth[0] + bx, berth[1] + by, off)
						var x: int = tx + off[0]
						var y: int = ty + off[1]
						if x >= 0 and y >= 0 and x < w and y < map.h:
							bc.append(y * w + x)
				if bc.size() == berth[2] * berth[3] and _berth_ok(map, bc):
					count += 1
					if first_only:
						return count
	return count


## MapBuildRules.check_berth with the naval-component test done on the water body (>= NAVAL_COMPONENT_MIN cells): the
## graph test of check_berth looks at the FIRST berth cell, which always touches the dock and so never has the 3x3
## water clearance of a size-2 naval node (see CROSS_MODULE_REQUESTS).
static func _berth_ok(map: MapData, cells: PackedInt32Array) -> bool:
	return MapBuildRules.berth_in_deep_body(map, cells, MapBuildRules.NAVAL_COMPONENT_MIN)


static func _rect_cells(x0: int, y0: int, rw: int, rh: int, w: int, out: PackedInt32Array) -> PackedInt32Array:
	out.clear()
	for y: int in range(y0, y0 + rh):
		for x: int in range(x0, x0 + rw):
			out.append(y * w + x)
	return out
