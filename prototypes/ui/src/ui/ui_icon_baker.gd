class_name UiIconBaker
extends Node
## Renders 3D models into transparent ImageTextures with off-screen SubViewports and caches them.
## Pattern: N SubViewports (UPDATE_ONCE, own_world_3d, transparent_bg) are created in ONE frame, one
## `frame_post_draw` later every one has rendered, all images are read back and the viewports freed.
## Result: any number of build-card portraits in ~2 frames, zero GPU memory kept beyond the ImageTextures.

const YAW_DEG := -36.0
const PITCH_DEG := -28.0

## Callable(kind: String, team: Color) -> Node3D. The game injects ViewModelBuilder here.
var model_builder: Callable = Callable(DemoModels, "build")
var _cache: Dictionary = {}
## Timing of the most recent batch (ms): scene build, wait for GPU, readback + texture upload.
var last_build_ms: float = 0.0
var last_wait_ms: float = 0.0
var last_readback_ms: float = 0.0
var last_count: int = 0

func key_for(kind: String, size: Vector2i, team: Color) -> String:
	return "%s|%dx%d|%s" % [kind, size.x, size.y, team.to_html(false)]

func get_icon(kind: String, size: Vector2i, team: Color) -> ImageTexture:
	return _cache.get(key_for(kind, size, team))

func cached_count() -> int:
	return _cache.size()

func clear() -> void:
	_cache.clear()

## Coroutine: bakes every missing (kind, size, team) icon in one batch. `await` it.
func bake(kinds: PackedStringArray, size: Vector2i, team: Color, rim: Color) -> void:
	var t0: int = Time.get_ticks_usec()
	var views: Array[SubViewport] = []
	var keys: PackedStringArray = PackedStringArray()
	for k in kinds:
		var key: String = key_for(k, size, team)
		if _cache.has(key) or keys.has(key):
			continue
		views.append(_make_view(k, size, team, rim))
		keys.append(key)
	last_count = views.size()
	if views.is_empty():
		return
	var t1: int = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var t2: int = Time.get_ticks_usec()
	for i in views.size():
		var img: Image = views[i].get_texture().get_image()
		img.fix_alpha_edges()
		_cache[keys[i]] = ImageTexture.create_from_image(img)
		views[i].queue_free()
	var t3: int = Time.get_ticks_usec()
	last_build_ms = (t1 - t0) / 1000.0
	last_wait_ms = (t2 - t1) / 1000.0
	last_readback_ms = (t3 - t2) / 1000.0

func _make_view(kind: String, size: Vector2i, team: Color, rim: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.positional_shadow_atlas_size = 0
	var model: Node3D = model_builder.call(kind, team)
	vp.add_child(model)
	var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0))
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var min_r: float = INF
	var max_r: float = -INF
	var min_u: float = INF
	var max_u: float = -INF
	for i in 8:
		var c: Vector3 = bounds.get_endpoint(i)
		min_r = minf(min_r, c.dot(right))
		max_r = maxf(max_r, c.dot(right))
		min_u = minf(min_u, c.dot(up))
		max_u = maxf(max_u, c.dot(up))
	var aspect: float = float(size.x) / float(size.y)
	var ext: float = maxf(max_u - min_u, (max_r - min_r) / aspect) * 1.10
	cam.size = ext
	var center: Vector3 = right * ((min_r + max_r) * 0.5) + up * ((min_u + max_u) * 0.5)
	cam.transform = Transform3D(basis, center + basis.z * 60.0)
	cam.near = 0.1
	cam.far = 200.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.52, 0.62)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	vp.add_child(cam)
	vp.add_child(_light(Vector3(-46.0, -32.0, 0.0), Color(1.0, 0.96, 0.88), 1.7))
	vp.add_child(_light(Vector3(-20.0, 140.0, 0.0), Color(0.55, 0.7, 1.0), 0.55))
	vp.add_child(_light(Vector3(-8.0, 200.0, 0.0), rim, 1.1))
	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var r: float = maxf(bounds.size.x, bounds.size.z) * 0.62
	quad.size = Vector2(r * 2.2, r * 1.5)
	shadow.mesh = quad
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.position = Vector3(bounds.get_center().x, 0.02, bounds.get_center().z)
	shadow.material_override = _shadow_material()
	vp.add_child(shadow)
	add_child(vp)
	return vp

func _light(rot: Vector3, col: Color, energy: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_color = col
	l.light_energy = energy
	return l

static var _shadow_mat: StandardMaterial3D

static func _shadow_material() -> StandardMaterial3D:
	if _shadow_mat == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.0, 0.0, 0.0, 0.62), Color(0.0, 0.0, 0.0, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_texture = gt
	return _shadow_mat

func _bounds(n: Node3D, xf: Transform3D) -> AABB:
	var out := AABB()
	var have: bool = false
	for c in n.get_children():
		var cn := c as Node3D
		if cn == null:
			continue
		var t: Transform3D = xf * cn.transform
		var b := AABB()
		if cn is MeshInstance3D:
			b = t * (cn as MeshInstance3D).get_aabb()
		else:
			b = _bounds(cn, t)
		if b.size == Vector3.ZERO:
			continue
		out = b if not have else out.merge(b)
		have = true
	return out
