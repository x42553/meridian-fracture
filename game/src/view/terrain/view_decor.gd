class_name ViewDecor
extends Node3D
## Deterministic decoration scatter rendered with MultiMeshInstance3D groups (render spec 5.5 "Decor"). All placement comes from
## terrain ids, flags and the per-cell `deco` byte, so every client draws the same picture:
##   FOREST cells: 1-4 trees (conifers above 8 m, in the arctic biome or with the conifer kit; palms with the palm kit),
##   ROCK / CLIFF / MOUNTAIN cells: rocks (larger on cliffs, none on ramps), SF_BLOCK cells: one small rock,
##   SHALLOW cells within one cell of land (temperate and tropical biomes): reed tufts,
##   deposit cells: crystal / scrap cluster scaled by the deposit fraction (hidden at 0),
##   URBAN_BLOCK cells: one building per merged rectangle of at most 3 x 3 cells (height 6 + (deco & 7) * 0.7 m).
## Never on open ground, road, pavement, ford, beach or deep cells. Instances are bucketed into groups x groups MultiMeshes
## because a MultiMesh is culled as ONE AABB (4-6 per side = 56-94 MultiMeshes). Presentation only.

enum Kind { BROADLEAF, CONIFER, ROCK, CRYSTAL, SCRAP, PALM, REED, OFFICE, APARTMENT, WAREHOUSE }
const KIND_COUNT: int = 10

## 12 transform + 4 colour (always white) + 4 custom (phase, variation, emissive, unused). Colour AND custom data are both
## enabled on purpose: with custom data only, Compatibility feeds the custom data into COLOR (trunks turn red).
const FLOATS_PER_INSTANCE: int = 20
const SHADER_PATH: String = "res://assets/shaders/decor.gdshader"
const HIDDEN_SCALE: float = 0.0001
const MAX_BLOCK_CELLS: int = 3
const REED_SHORE_MAX: int = 3  ## MapData.shore_dist chamfer units (3 = one cell from land)

var material: ShaderMaterial = null
var groups_per_side: int = 5
var counts: Array[int] = []
var mesh_tris: Array[int] = []
var multimesh_count: int = 0
var build_ms: float = 0.0
var kit: String = "broadleaf"  ## broadleaf | conifer | palm (ViewMoodDef.decor_kit)
var density: float = 1.0

var _terrain: ViewTerrain = null
var _src: ViewTerrainSource = null
var _meshes: Array[ArrayMesh] = []
var _inst: Array[PackedFloat32Array] = []
var _row_src: Array[PackedInt32Array] = []  # source cell (top-left cell of a building) per row
var _row_dep: Array[PackedInt32Array] = []  # deposit cell per row, -1 otherwise
var _row_mul: Array[PackedFloat32Array] = []  # applied scale multiplier per row (deposit clusters)
var _nodes: Array[MultiMeshInstance3D] = []
var _dep_loc: Dictionary = {}  # deposit cell -> Vector3i(node index, instance index, kind)
var _dep_row: Dictionary = {}  # deposit cell -> row in _inst[kind]
var _shadows: bool = true


func build(t: ViewTerrain, src: ViewTerrainSource, q: ViewQuality) -> void:
	ViewGlobals.ensure()
	var t0: int = Time.get_ticks_usec()
	_terrain = t
	_src = src
	var groups: int = 5
	var casts: bool = true
	density = 1.0
	if q != null:
		density = clampf(q.get_float(&"decor_density"), 0.05, 1.0) if q.values.has("decor_density") else 1.0
		groups = clampi(q.get_int(&"decor_groups"), 1, 12) if q.values.has("decor_groups") else 5
		casts = q.get_bool(&"decor_casts_shadow") and q.shadow_cascades() > 0
	_shadows = casts
	kit = kit_for_biome(src.biome)
	if material == null:
		var base: Shader = load(SHADER_PATH) as Shader
		material = ShaderMaterial.new()
		material.shader = base
	_meshes = [
		ViewDecorMeshes.broadleaf(7), ViewDecorMeshes.conifer(9), ViewDecorMeshes.rock(11), ViewDecorMeshes.crystal(13),
		ViewDecorMeshes.scrap(15), ViewDecorMeshes.palm(17), ViewDecorMeshes.reed(19),
		ViewDecorMeshes.building(0, 21), ViewDecorMeshes.building(1, 23), ViewDecorMeshes.building(2, 25),
	]
	mesh_tris.clear()
	for k: int in KIND_COUNT:
		mesh_tris.append(ViewDecorMeshes.triangle_count(_meshes[k]))
	_place()
	regroup(groups)
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


static func kit_for_biome(biome: int) -> String:
	if biome == 2:
		return "conifer"
	if biome == 3:
		return "palm"
	return "broadleaf"


func apply_mood(m: ViewMoodDef) -> void:
	if material == null:
		return
	material.set_shader_parameter("foliage_a", m.foliage_a)
	material.set_shader_parameter("foliage_b", m.foliage_b)
	if m.decor_kit != kit and _src != null and (m.decor_kit == "broadleaf" or m.decor_kit == "conifer" or m.decor_kit == "palm"):
		kit = m.decor_kit
		_place()
		regroup(groups_per_side)


func set_shadows(enabled: bool) -> void:
	_shadows = enabled
	for n: MultiMeshInstance3D in _nodes:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_visible_decor(enabled: bool) -> void:
	visible = enabled


func total_instances() -> int:
	var n: int = 0
	for c: int in counts:
		n += c
	return n


## Source cell index of every row of a kind (test hook): the scatter rules are checked against these.
func source_cells(kind: int) -> PackedInt32Array:
	return _row_src[kind]


func row_position(kind: int, row: int) -> Vector3:
	var o: int = row * FLOATS_PER_INSTANCE
	var b: PackedFloat32Array = _inst[kind]
	return Vector3(b[o + 3], b[o + 7], b[o + 11])


func row_scale_multiplier(kind: int, row: int) -> float:
	return _row_mul[kind][row]


## Rebuilds the MultiMeshInstance3D set with the given number of groups per map side.
func regroup(groups: int) -> void:
	groups = maxi(groups, 1)
	groups_per_side = groups
	for n: MultiMeshInstance3D in _nodes:
		n.queue_free()
	_nodes.clear()
	_dep_loc.clear()
	multimesh_count = 0
	var size: Vector2 = _src.size_m()
	var gsz: Vector2 = size / float(groups)
	for kind: int in KIND_COUNT:
		var src_buf: PackedFloat32Array = _inst[kind]
		var count: int = counts[kind]
		if count == 0:
			continue
		var bucket_of: PackedInt32Array = PackedInt32Array()
		bucket_of.resize(count)
		var per_bucket: PackedInt32Array = PackedInt32Array()
		per_bucket.resize(groups * groups)
		for k: int in count:
			var o: int = k * FLOATS_PER_INSTANCE
			var gx: int = clampi(int(src_buf[o + 3] / gsz.x), 0, groups - 1)
			var gz: int = clampi(int(src_buf[o + 11] / gsz.y), 0, groups - 1)
			bucket_of[k] = gz * groups + gx
			per_bucket[gz * groups + gx] += 1
		var starts: PackedInt32Array = PackedInt32Array()
		starts.resize(groups * groups + 1)
		for g: int in groups * groups:
			starts[g + 1] = starts[g] + per_bucket[g]
		var cursor: PackedInt32Array = starts.duplicate()
		var order: PackedInt32Array = PackedInt32Array()
		order.resize(count)
		for k: int in count:
			var b: int = bucket_of[k]
			order[cursor[b]] = k
			cursor[b] += 1
		for g: int in groups * groups:
			var n_in: int = per_bucket[g]
			if n_in == 0:
				continue
			var buf: PackedFloat32Array = PackedFloat32Array()
			for j: int in n_in:
				var row: int = order[starts[g] + j]
				var o2: int = row * FLOATS_PER_INSTANCE
				var mul: float = _row_mul[kind][row]
				var slice: PackedFloat32Array = src_buf.slice(o2, o2 + FLOATS_PER_INSTANCE)
				if mul != 1.0:
					for c: int in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
						slice[c] *= mul
				buf.append_array(slice)
				var dep: int = _row_dep[kind][row]
				if dep >= 0:
					_dep_loc[dep] = Vector3i(_nodes.size(), j, kind)
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _meshes[kind]
			mm.instance_count = n_in
			mm.buffer = buf
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = material
			mmi.extra_cull_margin = 2.0
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.layers = ViewLayers.MASK_WORLD
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_nodes.append(mmi)
			multimesh_count += 1


## Deposit clusters shrink with the deposit fraction (scale 0.35 + 0.65 * fraction) and hide at 0. `cells` come from
## ViewTerrainSource.drain_deposit_changes; the cost is O(changed).
func apply_deposit_changes(src: ViewTerrainSource, cells: PackedInt32Array, n: int) -> void:
	for k: int in mini(n, cells.size()):
		var cell: int = cells[k]
		if not _dep_loc.has(cell):
			continue
		var loc: Vector3i = _dep_loc[cell] as Vector3i
		var kind: int = loc.z
		var row: int = _dep_row[cell] as int
		var f: float = src.deposit_fraction(cell)
		var mul: float = 0.35 + 0.65 * f if f > 0.0 else HIDDEN_SCALE
		_row_mul[kind][row] = mul
		var o: int = row * FLOATS_PER_INSTANCE
		var b: PackedFloat32Array = _inst[kind]
		var bas: Basis = Basis(Vector3(b[o], b[o + 4], b[o + 8]) * mul, Vector3(b[o + 1], b[o + 5], b[o + 9]) * mul, Vector3(b[o + 2], b[o + 6], b[o + 10]) * mul)
		var mm: MultiMesh = _nodes[loc.x].multimesh
		mm.set_instance_transform(loc.y, Transform3D(bas, Vector3(b[o + 3], b[o + 7], b[o + 11])))


# ---- placement ---------------------------------------------------------------------------------------------------------

func _reset_rows() -> void:
	_dep_row.clear()
	_inst.clear()
	_row_src.clear()
	_row_dep.clear()
	_row_mul.clear()
	counts.clear()
	for k: int in KIND_COUNT:
		_inst.append(PackedFloat32Array())
		_row_src.append(PackedInt32Array())
		_row_dep.append(PackedInt32Array())
		_row_mul.append(PackedFloat32Array())
		counts.append(0)


func _push(kind: int, x: float, z: float, yaw: float, sx: float, sy: float, sz: float, phase: float, variation: float, emissive: float, src_cell: int, dep_cell: int = -1, y_override: float = -1000.0, mul: float = 1.0) -> void:
	var y: float = _terrain.height_at(x, z) - 0.06 if y_override < -999.0 else y_override
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	_inst[kind].append_array(PackedFloat32Array([
		c * sx, 0.0, s * sz, x, 0.0, sy, 0.0, y, -s * sx, 0.0, c * sz, z,
		1.0, 1.0, 1.0, 1.0, phase, variation, emissive, 0.0]))
	_row_src[kind].append(src_cell)
	_row_dep[kind].append(dep_cell)
	_row_mul[kind].append(mul)
	counts[kind] += 1


func _place() -> void:
	_reset_rows()
	var s: ViewTerrainSource = _src
	var w: int = s.width
	var h: int = s.height
	var cell_m: float = ViewConsts.CELL_M
	var seed_v: int = s.deco_seed
	var dens_pct: int = int(density * 100.0)
	var arctic: bool = s.biome == 2
	var reeds_ok: bool = s.biome == 0 or s.biome == 3
	var built: PackedByteArray = PackedByteArray()  # urban cells already covered by a building
	built.resize(w * h)
	for cy: int in h:
		for cx: int in w:
			var c: int = cy * w + cx
			var t: int = s.terrain[c]
			var fl: int = s.flags[c]
			var deco: int = s.deco[c]
			var hs: int = ViewDecorMeshes.hash3(cx, cy, seed_v + 5)
			var x0: float = float(cx) * cell_m
			var z0: float = float(cy) * cell_m
			var jx: float = x0 + 0.15 + float(hs & 0xFF) / 255.0 * (cell_m - 0.3)
			var jz: float = z0 + 0.15 + float((hs >> 8) & 0xFF) / 255.0 * (cell_m - 0.3)
			var yaw: float = float((hs >> 16) & 0xFFF) / 4095.0 * TAU
			var phase: float = float((hs >> 4) & 0xFF) / 255.0 * TAU
			var var01: float = float((hs >> 12) & 0xFF) / 255.0
			match t:
				MapTerrain.T_FOREST:
					_place_trees(cx, cy, c, deco, dens_pct, arctic, x0, z0, phase, var01)
				MapTerrain.T_ROCK:
					if (fl & MapData.SF_RAMP) == 0 and (hs % 100) < 22:
						var r1: float = 0.7 + float((hs >> 20) & 0xFF) / 255.0 * 0.9
						_push(Kind.ROCK, jx, jz, yaw, r1, r1 * 0.9, r1 * (0.8 + var01 * 0.5), 0.0, var01, 0.0, c)
				MapTerrain.T_CLIFF:
					if (fl & MapData.SF_RAMP) == 0 and (hs % 100) < 35:
						var r2: float = 1.2 + float((hs >> 20) & 0xFF) / 255.0 * 1.4
						_push(Kind.ROCK, jx, jz, yaw, r2, r2 * 0.95, r2 * (0.8 + var01 * 0.5), 0.0, var01, 0.0, c)
				MapTerrain.T_MOUNTAIN:
					if (hs % 100) < 18:
						var r3: float = 1.0 + float((hs >> 20) & 0xFF) / 255.0 * 1.2
						_push(Kind.ROCK, jx, jz, yaw, r3, r3 * 0.9, r3 * (0.8 + var01 * 0.5), 0.0, var01, 0.0, c)
				MapTerrain.T_SHALLOW:
					if reeds_ok and s.shore_dist[c] <= REED_SHORE_MAX and (hs % 100) < 65:
						_place_reeds(c, jx, jz, yaw, phase, var01)
				MapTerrain.T_URBAN:
					if built[c] == 0:
						_place_building(cx, cy, c, built)
			if (fl & MapData.SF_BLOCK) != 0 and t != MapTerrain.T_FOREST and t != MapTerrain.T_ROCK and t != MapTerrain.T_CLIFF:
				var r4: float = 0.5 + var01 * 0.45
				_push(Kind.ROCK, jx, jz, yaw, r4, r4, r4, 0.0, var01, 0.0, c)
	# deposit clusters (crystal or scrap per cell), scale from the deposit fraction
	var deps: PackedInt32Array = PackedInt32Array()
	s.deposit_cells(deps)
	for c2: int in deps:
		var cx2: int = c2 % w
		var cy2: int = c2 / w
		var hd: int = ViewDecorMeshes.hash3(cx2, cy2, seed_v + 71)
		var px: float = (float(cx2) + 0.5) * cell_m + (float(hd & 0xFF) / 255.0 - 0.5) * 1.4
		var pz: float = (float(cy2) + 0.5) * cell_m + (float((hd >> 8) & 0xFF) / 255.0 - 0.5) * 1.4
		var yw: float = float((hd >> 16) & 0xFFF) / 4095.0 * TAU
		var v01: float = float((hd >> 4) & 0xFF) / 255.0
		var f: float = s.deposit_fraction(c2)
		var mul: float = 0.35 + 0.65 * f if f > 0.0 else HIDDEN_SCALE
		_dep_row[c2] = counts[Kind.CRYSTAL] if ((hd >> 12) & 7) < 4 else counts[Kind.SCRAP]
		if ((hd >> 12) & 7) < 4:
			var sc: float = 0.6 + v01 * 0.4
			_push(Kind.CRYSTAL, px, pz, yw, sc, sc * 1.15, sc, float(hd & 0xFF) / 255.0 * TAU, v01, 0.5, c2, c2, -1000.0, mul)
		else:
			var sc2: float = 0.65 + v01 * 0.45
			_push(Kind.SCRAP, px, pz, yw, sc2, sc2, sc2, 0.0, v01, 0.0, c2, c2, -1000.0, mul)


func _place_trees(cx: int, cy: int, c: int, deco: int, dens_pct: int, arctic: bool, x0: float, z0: float, phase: float, var01: float) -> void:
	var n_trees: int = 1 + (deco & 3)
	for k: int in n_trees:
		var hk: int = ViewDecorMeshes.hash3(cx * 3 + k, cy * 5 + k * 7, _src.deco_seed + 17)
		if (hk % 100) >= dens_pct:
			continue
		var tx: float = x0 + 0.3 + float(hk & 0xFF) / 255.0 * 2.4
		var tz: float = z0 + 0.3 + float((hk >> 8) & 0xFF) / 255.0 * 2.4
		var sc: float = 0.8 + float((hk >> 16) & 0xFF) / 255.0 * 0.7
		var hgt: float = _terrain.height_at(tx, tz)
		var kind: int = Kind.BROADLEAF
		if arctic or kit == "conifer" or hgt > 8.0:
			kind = Kind.CONIFER
		elif kit == "palm" and ((hk >> 24) & 0xFF) < 140:
			kind = Kind.PALM
		_push(kind, tx, tz, float((hk >> 4) & 0xFFF) / 4095.0 * TAU, sc, sc * (0.9 + 0.3 * var01), sc, phase + float(k), var01, 0.0, c)


func _place_reeds(c: int, jx: float, jz: float, yaw: float, phase: float, var01: float) -> void:
	var sea: float = _src.sea_level_m
	var bed: float = _terrain.height_at(jx, jz)
	var y: float = maxf(bed, sea - 0.6)
	var sc: float = 0.8 + var01 * 0.6
	_push(Kind.REED, jx, jz, yaw, sc, sc, sc, phase, var01, 0.0, c, -1, y)


## Greedy merge: the largest rectangle of at most 3 x 3 URBAN cells starting at (cx, cy), not covered yet.
func _place_building(cx: int, cy: int, c: int, built: PackedByteArray) -> void:
	var s: ViewTerrainSource = _src
	var bw: int = 1
	while bw < MAX_BLOCK_CELLS and cx + bw < s.width and s.terrain[cy * s.width + cx + bw] == MapTerrain.T_URBAN and built[cy * s.width + cx + bw] == 0:
		bw += 1
	var bh: int = 1
	var can_grow: bool = true
	while bh < MAX_BLOCK_CELLS and cy + bh < s.height and can_grow:
		for i: int in bw:
			var ci: int = (cy + bh) * s.width + cx + i
			if s.terrain[ci] != MapTerrain.T_URBAN or built[ci] != 0:
				can_grow = false
				break
		if can_grow:
			bh += 1
	for j: int in bh:
		for i: int in bw:
			built[(cy + j) * s.width + cx + i] = 1
	var cell_m: float = ViewConsts.CELL_M
	var x0: float = float(cx) * cell_m
	var z0: float = float(cy) * cell_m
	var fw: float = float(bw) * cell_m
	var fh: float = float(bh) * cell_m
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for pz: float in [0.0, 0.5, 1.0]:
		for px: float in [0.0, 0.5, 1.0]:
			var hy: float = _terrain.height_at(x0 + fw * px, z0 + fh * pz)
			lo = minf(lo, hy)
			hi = maxf(hi, hy)
	var hs: int = ViewDecorMeshes.hash3(cx, cy, _src.deco_seed + 91)
	var height_m: float = 6.0 + float(s.deco[c] & 7) * 0.7
	var variant: int = (hs >> 4) % 3
	var kind: int = Kind.OFFICE + variant
	var var01: float = float((hs >> 12) & 0xFF) / 255.0
	# unit-box meshes: scale x / z = footprint minus a 0.5 m inset, y = building height plus the slope span and a 0.35 m foundation
	_push(kind, x0 + fw * 0.5, z0 + fh * 0.5, 0.0, fw - 0.5, height_m + (hi - lo) + 0.35, fh - 0.5, 0.0, var01, 0.0, c, -1, lo - 0.35)
