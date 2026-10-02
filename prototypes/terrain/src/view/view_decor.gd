class_name ViewDecor
extends Node3D
## Deterministic decoration scatter (trees, rocks, crystals, scrap) rendered with MultiMeshInstance3D.
## Instances are bucketed into square groups so the engine can frustum-cull whole groups (a MultiMesh is culled
## as one AABB): groups_per_side = 1 is a single global MultiMesh per kind; 4-6 is the sweet spot for an RTS view.

enum Kind { BROADLEAF, CONIFER, ROCK, CRYSTAL, SCRAP }
## 12 transform + 4 colour (always white) + 4 custom (phase, variation, emissive, unused).
## Colour AND custom data are both enabled on purpose: with custom data only, the Compatibility renderer feeds the custom
## data into COLOR (trunks turn red, crowns glow). Forward+/Mobile are fine either way.
const FLOATS_PER_INSTANCE: int = 20

var material: ShaderMaterial
var groups_per_side: int = 4
var counts: Array[int] = [0, 0, 0, 0, 0]
var mesh_tris: Array[int] = [0, 0, 0, 0, 0]
var multimesh_count: int = 0
var build_ms: float = 0.0

var _terrain: ViewTerrain
var _meshes: Array[ArrayMesh] = []
var _inst: Array[PackedFloat32Array] = []
var _nodes: Array[MultiMeshInstance3D] = []
var _shadows: bool = true


func build(terrain: ViewTerrain, groups: int = 4) -> void:
	var t0: int = Time.get_ticks_usec()
	_terrain = terrain
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/decor.gdshader")
	_meshes = [ViewDecorMeshes.broadleaf(7), ViewDecorMeshes.conifer(9), ViewDecorMeshes.rock(11), ViewDecorMeshes.crystal(13), ViewDecorMeshes.scrap(15)]
	for k in 5:
		mesh_tris[k] = ViewDecorMeshes.triangle_count(_meshes[k])
	_place()
	regroup(groups)
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func apply_mood(mood: ViewMoodDef) -> void:
	material.set_shader_parameter("foliage_a", mood.foliage_a)
	material.set_shader_parameter("foliage_b", mood.foliage_b)


func set_shadows(enabled: bool) -> void:
	_shadows = enabled
	for n in _nodes:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_visible_decor(enabled: bool) -> void:
	visible = enabled


func _push(kind: int, x: float, z: float, yaw: float, sx: float, sy: float, sz: float, phase: float, variation: float, emissive: float) -> void:
	var y: float = _terrain.height_at(x, z) - 0.06
	var c: float = cos(yaw)
	var s: float = sin(yaw)
	var buf: PackedFloat32Array = _inst[kind]
	buf.append_array(PackedFloat32Array([c * sx, 0.0, s * sz, x, 0.0, sy, 0.0, y, -s * sx, 0.0, c * sz, z, 1.0, 1.0, 1.0, 1.0, phase, variation, emissive, 0.0]))
	_inst[kind] = buf
	counts[kind] += 1


func _place() -> void:
	var data: MapTerrainData = _terrain.data
	var w: int = data.width
	var h: int = data.height
	_inst.clear()
	for k in 5:
		_inst.append(PackedFloat32Array())
		counts[k] = 0
	var f_forest: MapFbm = MapFbm.new().setup(data.seed_value + 91, w, h, 26, 3)
	var cell_m: float = MapTerrainData.CELL_M
	for cy in h:
		for cx in w:
			var c: int = cy * w + cx
			var fl: int = data.flags[c]
			if (fl & (MapTerrainData.F_WATER | MapTerrainData.F_ROAD)) != 0:
				continue
			var t: int = data.types[c]
			var hs: int = MapNoise.hash2(cx, cy, data.seed_value + 5)
			var jx: float = (float(hs & 0xFF) / 255.0) * cell_m
			var jz: float = (float((hs >> 8) & 0xFF) / 255.0) * cell_m
			var x: float = float(cx) * cell_m + jx
			var z: float = float(cy) * cell_m + jz
			var yaw: float = float((hs >> 16) & 0xFFF) / 4095.0 * TAU
			var phase: float = float((hs >> 4) & 0xFF) / 255.0 * TAU
			var var01: float = float((hs >> 12) & 0xFF) / 255.0
			var near_start: bool = false
			for sc in data.start_cells:
				if absi(sc.x - cx) < 13 and absi(sc.y - cy) < 13:
					near_start = true
			var hgt: float = _terrain.height_at(x, z)
			var flat_ok: bool = _terrain.normal_at(x, z).y > 0.88
			if (t == MapTerrainData.T_GRASS or t == MapTerrainData.T_DIRT) and flat_ok and not near_start:
				var dens: int = f_forest.sample_q8(cx * 256 + 128, cy * 256 + 128)
				var n_trees: int = 0
				if dens > 43000:
					n_trees = 1 + (1 if dens > 50000 else 0) + (1 if dens > 57000 else 0)
				for k in n_trees:
					var hk: int = MapNoise.hash2(cx * 3 + k, cy * 5 + k * 7, data.seed_value + 17)
					if (hk % 100) < 14:
						continue
					var tx: float = float(cx) * cell_m + float(hk & 0xFF) / 255.0 * cell_m
					var tz: float = float(cy) * cell_m + float((hk >> 8) & 0xFF) / 255.0 * cell_m
					var ty: float = float((hk >> 16) & 0xFF) / 255.0
					var sc: float = 0.8 + ty * 0.7
					var conifer: bool = hgt > 8.0 or (data.moisture[c] > 150 and (hk & 3) == 0)
					_push(Kind.CONIFER if conifer else Kind.BROADLEAF, tx, tz, float((hk >> 4) & 0xFFF) / 4095.0 * TAU, sc, sc * (0.9 + 0.3 * var01), sc, phase + float(k), var01, 0.0)
			if t == MapTerrainData.T_ROCK or t == MapTerrainData.T_SNOW:
				if (hs % 100) < (5 if t == MapTerrainData.T_SNOW else 11):
					var s1: float = 0.6 + float((hs >> 20) & 0xFF) / 255.0 * 1.5
					_push(Kind.ROCK, x, z, yaw, s1, s1 * 0.9, s1 * (0.8 + var01 * 0.5), 0.0, var01, 0.0)
			elif (t == MapTerrainData.T_SAND or t == MapTerrainData.T_DIRT) and (hs % 100) < 4:
				var s2: float = 0.5 + var01 * 0.9
				_push(Kind.ROCK, x, z, yaw, s2, s2, s2, 0.0, var01, 0.0)
			elif t == MapTerrainData.T_SALVAGE:
				var r100: int = hs % 100
				if r100 < 15:
					var s3: float = 0.8 + var01 * 0.7
					_push(Kind.CRYSTAL, x, z, yaw, s3, s3 * 1.1, s3, phase, var01, 1.3)
				elif r100 < 38:
					var s4: float = 0.85 + var01 * 0.6
					_push(Kind.SCRAP, x, z, yaw, s4, s4, s4, 0.0, var01, 0.0)
			if t == MapTerrainData.T_ROCK and hgt > 6.0 and (hs % 1000) < 12:
				_push(Kind.CRYSTAL, x, z, yaw, 1.2, 1.3, 1.2, phase, var01, 1.1)


## Rebuilds the MultiMeshInstance3D set with the given number of groups per map side.
func regroup(groups: int) -> void:
	groups_per_side = groups
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	multimesh_count = 0
	var size: Vector2 = _terrain.data.size_m()
	var gsz: Vector2 = size / float(groups)
	for kind in 5:
		var src: PackedFloat32Array = _inst[kind]
		var count: int = src.size() / FLOATS_PER_INSTANCE
		var buckets: Array[PackedFloat32Array] = []
		buckets.resize(groups * groups)
		for k in count:
			var o: int = k * FLOATS_PER_INSTANCE
			var gx: int = clampi(int(src[o + 3] / gsz.x), 0, groups - 1)
			var gz: int = clampi(int(src[o + 11] / gsz.y), 0, groups - 1)
			var b: PackedFloat32Array = buckets[gz * groups + gx]
			b.append_array(src.slice(o, o + FLOATS_PER_INSTANCE))
			buckets[gz * groups + gx] = b
		for gi in buckets.size():
			var buf: PackedFloat32Array = buckets[gi]
			if buf.is_empty():
				continue
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _meshes[kind]
			mm.instance_count = buf.size() / FLOATS_PER_INSTANCE
			mm.buffer = buf
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = material
			mmi.extra_cull_margin = 2.0
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_nodes.append(mmi)
			multimesh_count += 1


func total_instances() -> int:
	var n: int = 0
	for c in counts:
		n += c
	return n
