class_name FxAssets
extends RefCounted
## Procedural resources for the VFX system: textures, meshes and materials.
## Everything is generated at startup (no imported art). Static caches let several FxManagers share them.

const SHADER_DIR: String = "res://shaders/"
const BIG_AABB: AABB = AABB(Vector3(-600.0, -200.0, -600.0), Vector3(1200.0, 600.0, 1200.0))

static var _noise: ImageTexture
static var _ramp: ImageTexture
static var _palette: ImageTexture
static var _scorch: ImageTexture
static var _scorch_glow: ImageTexture
static var _shaders: Dictionary = {}

# ------------------------------------------------------------------ textures

## 256x256 seamless RGBA noise atlas. R = fbm billows, G = inverted cellular bubbles, B = smooth low
## frequency, A = fine grit. Sampled with mipmaps + repeat by every Fx shader (one fetch = 4 noise layers).
static func noise_atlas() -> ImageTexture:
	if _noise != null:
		return _noise
	const N: int = 256
	var chans: Array[PackedByteArray] = []
	for i in 4:
		var fn := FastNoiseLite.new()
		fn.seed = 1337 + i * 977
		var invert: bool = false
		match i:
			0:
				fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
				fn.fractal_type = FastNoiseLite.FRACTAL_FBM
				fn.fractal_octaves = 5
				fn.frequency = 0.014
			1:
				fn.noise_type = FastNoiseLite.TYPE_CELLULAR
				fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
				fn.frequency = 0.03
				invert = true
			2:
				fn.noise_type = FastNoiseLite.TYPE_PERLIN
				fn.fractal_type = FastNoiseLite.FRACTAL_FBM
				fn.fractal_octaves = 3
				fn.frequency = 0.008
			_:
				fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
				fn.fractal_type = FastNoiseLite.FRACTAL_FBM
				fn.fractal_octaves = 3
				fn.frequency = 0.06
		var img: Image = fn.get_seamless_image(N, N, invert)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var data := PackedByteArray()
	data.resize(N * N * 4)
	var c0: PackedByteArray = chans[0]
	var c1: PackedByteArray = chans[1]
	var c2: PackedByteArray = chans[2]
	var c3: PackedByteArray = chans[3]
	for p in N * N:
		var o: int = p * 4
		data[o] = c0[p]
		data[o + 1] = c1[p]
		data[o + 2] = c2[p]
		data[o + 3] = c3[p]
	var atlas := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, data)
	atlas.generate_mipmaps()
	_noise = ImageTexture.create_from_image(atlas)
	return _noise


## 256x1 half-float HDR ramp indexed by "heat": rgb is PREMULTIPLIED (glow + smoke colour), a is coverage.
## Cold end = sooty smoke, hot end = white-hot core. One premultiplied blend pass renders fire AND smoke.
static func fire_ramp() -> ImageTexture:
	if _ramp != null:
		return _ramp
	var offs: Array[float] = [0.0, 0.06, 0.2, 0.4, 0.6, 0.8, 1.0]
	var cols: Array[Color] = [
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.010, 0.009, 0.008, 0.55),
		Color(0.32, 0.045, 0.01, 0.78),
		Color(1.4, 0.30, 0.04, 0.70),
		Color(3.0, 1.1, 0.18, 0.50),
		Color(5.5, 3.2, 1.0, 0.30),
		Color(9.0, 7.5, 5.0, 0.10),
	]
	var img := Image.create_empty(256, 1, false, Image.FORMAT_RGBAH)
	for x in 256:
		img.set_pixel(x, 0, _sample_stops(offs, cols, float(x) / 255.0))
	_ramp = ImageTexture.create_from_image(img)
	return _ramp


## 8x1 colour palette selected by the integer part of INSTANCE_CUSTOM.z.
## 0 warm flash, 1 white-hot, 2 red, 3 green, 4 blue-white, 5 neutral shell, 6 fire orange, 7 EMP violet.
static func palette() -> ImageTexture:
	if _palette != null:
		return _palette
	var cols: Array[Color] = [
		Color(1.0, 0.68, 0.26), Color(1.0, 0.92, 0.75), Color(1.0, 0.16, 0.10), Color(0.25, 1.0, 0.35),
		Color(0.55, 0.78, 1.0), Color(0.95, 0.9, 0.8), Color(1.0, 0.42, 0.10), Color(0.42, 0.5, 1.0),
	]
	var img := Image.create_empty(8, 1, false, Image.FORMAT_RGBAH)
	for i in 8:
		img.set_pixel(i, 0, cols[i])
	_palette = ImageTexture.create_from_image(img)
	return _palette


## 128x128 scorch mark: noise-eroded dark blot with a lighter halo (Decal albedo).
static func scorch_texture() -> ImageTexture:
	if _scorch == null:
		_build_scorch()
	return _scorch


## Matching orange emission mask for the first seconds of a scorch (hot ground).
static func scorch_glow_texture() -> ImageTexture:
	if _scorch_glow == null:
		_build_scorch()
	return _scorch_glow


static func _build_scorch() -> void:
	const N: int = 128
	var fn := FastNoiseLite.new()
	fn.seed = 4242
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	fn.frequency = 0.05
	var albedo := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	var glow := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var u: float = (float(x) + 0.5) / float(N) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(N) * 2.0 - 1.0
			var r: float = sqrt(u * u + v * v)
			var n: float = fn.get_noise_2d(float(x), float(y))
			var shape: float = 1.0 - r + n * 0.45
			var alpha: float = smoothstep(0.0, 0.5, shape)
			var core: float = smoothstep(0.3, 0.85, shape)
			var k: float = 1.0 - core
			albedo.set_pixel(x, y, Color(0.018 + 0.07 * k, 0.015 + 0.05 * k, 0.012 + 0.03 * k, alpha * 0.93))
			var g: float = smoothstep(0.35, 0.95, shape)
			glow.set_pixel(x, y, Color(g, g * 0.32, g * 0.05, 1.0))
	_scorch = ImageTexture.create_from_image(albedo)
	_scorch_glow = ImageTexture.create_from_image(glow)


static func _sample_stops(offs: Array[float], cols: Array[Color], t: float) -> Color:
	for i in offs.size() - 1:
		if t <= offs[i + 1]:
			return cols[i].lerp(cols[i + 1], inverse_lerp(offs[i], offs[i + 1], t))
	return cols[cols.size() - 1]

# ------------------------------------------------------------------ meshes

## N quads in one mesh. COLOR = 4 per-particle randoms, UV = quad uv, UV2.x = index/N (fx_lod thinning).
static func cluster_mesh(count: int, rng_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var cuv: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for i in count:
		var col := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		var u2 := Vector2(float(i) / float(count), 0.0)
		for k in 4:
			verts.append(Vector3(corners[k].x, corners[k].y, 0.0))
			uvs.append(cuv[k])
			uv2s.append(u2)
			cols.append(col)
		var b: int = i * 4
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	return _finish(verts, uvs, uv2s, cols, idx, PackedVector3Array())


## Ribbon of `segments` quads along +Y (s = 0..1), x in [-0.5, 0.5]. UV = (x + 0.5, s).
static func ribbon_mesh(segments: int = 24) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segments + 1:
		var s: float = float(i) / float(segments)
		verts.append(Vector3(-0.5, s, 0.0))
		verts.append(Vector3(0.5, s, 0.0))
		uvs.append(Vector2(0.0, s))
		uvs.append(Vector2(1.0, s))
	for i in segments:
		var a: int = i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	return _finish(verts, uvs, PackedVector2Array(), PackedColorArray(), idx, PackedVector3Array())


## Horizontal quad spanning [-1,1] in XZ (rings, haze discs).
static func flat_quad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	return _finish(verts, uvs, PackedVector2Array(), PackedColorArray(), idx, PackedVector3Array())


## Unit hemisphere (y >= 0) with normals; UV.x wraps around, UV.y = latitude 0 (top) .. 1 (equator).
static func dome_mesh(rings: int = 24, segs: int = 64) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var th: float = float(i) / float(rings) * PI * 0.5
		for j in segs + 1:
			var ph: float = float(j) / float(segs) * TAU
			var p := Vector3(cos(ph) * sin(th), cos(th), sin(ph) * sin(th))
			verts.append(p)
			norms.append(p)
			uvs.append(Vector2(float(j) / float(segs), float(i) / float(rings)))
	for i in rings:
		for j in segs:
			var a: int = i * (segs + 1) + j
			var b: int = a + segs + 1
			idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	return _finish(verts, uvs, PackedVector2Array(), PackedColorArray(), idx, norms)


static func column_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 20
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	return m


static func _finish(verts: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array, norms: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	if not norms.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = BIG_AABB
	return mesh

# ------------------------------------------------------------------ materials

## Loads a shader once; `define` (e.g. "#define DISTORT") is injected after the shader_type line to build
## compile-time variants from a single source file.
static func shader_from(file: String, define: String = "") -> Shader:
	var key: String = file + "|" + define
	if _shaders.has(key):
		return _shaders[key]
	var base: Shader = load(SHADER_DIR + file + ".gdshader")
	var out: Shader = base
	if not define.is_empty():
		out = Shader.new()
		out.code = base.code.replace("shader_type spatial;", "shader_type spatial;\n" + define)
	_shaders[key] = out
	return out


static func sprite_material(mode: int, tint: Color = Color.WHITE, priority: int = 0, soft_depth: float = 0.8,
		intensity: float = 1.0, node_mode: bool = false, land_seconds: float = 0.0, fade_from: float = 0.85, rise: float = 0.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_sprites", "#define NODE_MODE" if node_mode else "")
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.set_shader_parameter(&"ramp_tex", fire_ramp())
	m.set_shader_parameter(&"palette_tex", palette())
	m.set_shader_parameter(&"tint", tint)
	# Compatibility downgrade: hint_depth_texture soft fade over-attenuates there, so it is switched off.
	m.set_shader_parameter(&"soft_depth", 0.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else soft_depth)
	m.set_shader_parameter(&"intensity", intensity)
	m.set_shader_parameter(&"land_seconds", land_seconds)
	m.set_shader_parameter(&"fade_from", fade_from)
	m.set_shader_parameter(&"rise", rise)
	m.set_shader_parameter(&"depth_ndc", depth_ndc())
	m.render_priority = priority
	return m


## Depth-texture decode constants: capability check on the active renderer, never on the OS name.
static func depth_ndc() -> Vector2:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return Vector2(2.0, -1.0)
	return Vector2(1.0, 0.0)


static func ribbon_material(mode: int, priority: int = 0, tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_ribbon")
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.set_shader_parameter(&"palette_tex", palette())
	m.set_shader_parameter(&"tint", tint)
	m.render_priority = priority
	return m


static func ring_material(mode: int, distort: bool, priority: int = 0, strength: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_ring", "#define DISTORT" if distort else "")
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.set_shader_parameter(&"palette_tex", palette())
	m.set_shader_parameter(&"strength", strength)
	m.render_priority = priority
	return m


static func dome_material(mode: int, priority: int = 2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_dome")
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.render_priority = priority
	return m


static func column_material(mode: int, priority: int = 3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_column")
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.render_priority = priority
	return m


static func shimmer_material(priority: int = -10, strength: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader_from("fx_shimmer")
	m.set_shader_parameter(&"noise_tex", noise_atlas())
	m.set_shader_parameter(&"strength", strength)
	m.render_priority = priority
	return m
