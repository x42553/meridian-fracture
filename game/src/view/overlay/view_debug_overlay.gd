class_name ViewDebugOverlay
extends Node3D
## Minimal debug overlays (render spec 5.10 AI/debug): the AiDebugFrame of a thinker (circles as ground rings with Label3D captions,
## line segments, a threat heat texture on the ground) and the view stats panel (F3, ViewWorld.stats()). Exists only in debug builds
## (`OS.is_debug_build()`): in a release export every call is a no-op and nothing is created, so no data ids can leak (QA V-ID1).

const MAX_CIRCLES: int = 48
const MAX_LINES: int = 96
const SHADER_PATH: String = "res://assets/shaders/zone.gdshader"

var enabled: bool = false
var stats_visible: bool = false
var circle_count: int = 0
var line_count: int = 0

var _v: ViewWorld = null
var _circles: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _lines: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null
var _heat: MeshInstance3D = null
var _heat_tex: ImageTexture = null
var _panel: Label = null
var _canvas: CanvasLayer = null
var _frame: AiDebugFrame = null
var _mesh_dirty: bool = false
var _shader: Shader = null
var _stats_t: float = 0.0


static func available() -> bool:
	return OS.is_debug_build()


func setup(v: ViewWorld) -> void:
	_v = v
	if not available():
		return
	_shader = load(SHADER_PATH) as Shader
	_line_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _line_mesh
	var lm: StandardMaterial3D = StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.no_depth_test = true
	lm.render_priority = 8
	_lines.material_override = lm
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.layers = ViewLayers.MASK_OVERLAYS
	add_child(_lines)


## The AI's debug frame (null clears every overlay). The caller passes the frame of `ai.debug_frame(pid)` at its own cadence.
func set_frame(f: AiDebugFrame) -> void:
	if not available() or _v == null:
		return
	_frame = f
	enabled = f != null
	_mesh_dirty = true


func set_stats_visible(on: bool) -> void:
	if not available():
		return
	stats_visible = on
	if on and _panel == null:
		_canvas = CanvasLayer.new()
		_canvas.layer = 90
		_panel = Label.new()
		_panel.position = Vector2(8.0, 96.0)
		_panel.add_theme_font_size_override(&"font_size", 13)
		_panel.add_theme_color_override(&"font_color", Color(0.85, 1.0, 0.85))
		_panel.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
		_panel.add_theme_constant_override(&"outline_size", 4)
		_canvas.add_child(_panel)
		add_child(_canvas)
	if _canvas != null:
		_canvas.visible = on


func toggle_stats() -> void:
	set_stats_visible(not stats_visible)


func update(dt: float) -> void:
	if not available() or _v == null:
		return
	if stats_visible and _panel != null:
		_stats_t += dt
		if _stats_t >= 0.25:
			_stats_t = 0.0
			_panel.text = stats_text()
	if _mesh_dirty:
		_mesh_dirty = false
		_rebuild()


func stats_text() -> String:
	var s: Dictionary = _v.stats()
	var ms: Dictionary = s.get("ms", {}) as Dictionary
	return "view: %d entities (%d visible)  script %.2f ms\nrouter %.2f  sample %.2f  entities %.2f  overlays %.2f\ndraws %s  zones %d  warnings %d  ghosts %d" % [
		s.get("entities", 0), s.get("visible", 0), ms.get("total", 0.0), ms.get("router", 0.0), ms.get("sample", 0.0),
		ms.get("entities", 0.0), ms.get("overlays", 0.0), str(s.get("draws", 0)),
		_v.zones.count if _v.zones != null else 0, _v.warnings.count if _v.warnings != null else 0, _v.ghosts.count if _v.ghosts != null else 0]


func _rebuild() -> void:
	for n: MeshInstance3D in _circles:
		n.visible = false
	for l: Label3D in _labels:
		l.visible = false
	_line_mesh.clear_surfaces()
	circle_count = 0
	line_count = 0
	if _heat != null:
		_heat.visible = false
	if _frame == null:
		return
	var m: float = ViewConsts.M_PER_UNIT
	var nc: int = mini(_frame.circles.size() / 5, MAX_CIRCLES)
	for i: int in nc:
		var o: int = i * 5
		var c: Vector2 = Vector2(float(_frame.circles[o]), float(_frame.circles[o + 1])) * m
		var r: float = maxf(float(_frame.circles[o + 2]) * m, 0.6)
		var argb: int = _frame.circles[o + 3]
		var col: Color = Color(float((argb >> 16) & 255) / 255.0, float((argb >> 8) & 255) / 255.0, float(argb & 255) / 255.0, 1.0)
		var node: MeshInstance3D = _circle_node(i)
		var half: Vector2 = Vector2(r + 1.0, r + 1.0)
		node.mesh = ViewGroundMesh.build_flat(_v, c, 0.0, half, clampf(r / 8.0, 0.5, 2.0), 0.2)
		var mat: ShaderMaterial = node.material_override as ShaderMaterial
		mat.set_shader_parameter(&"tint", col)
		mat.set_shader_parameter(&"geom", Vector4(0.0, r, 1.0, 1.0))
		mat.set_shader_parameter(&"tm", Vector4(0.0, 0.0, 1.0, 0.0))
		node.visible = true
		var li: int = _frame.circles[o + 4]
		if li >= 0 and li < _frame.labels.size():
			var lab: Label3D = _label_node(i)
			lab.text = _frame.labels[li]
			lab.modulate = col
			lab.position = Vector3(c.x, _v.ground_at(c.x, c.y) + 1.5, c.y)
			lab.visible = true
	circle_count = nc
	var nl: int = mini(_frame.lines.size() / 5, MAX_LINES)
	if nl > 0:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for j: int in nl:
			var o2: int = j * 5
			var argb2: int = _frame.lines[o2 + 4]
			var col2: Color = Color(float((argb2 >> 16) & 255) / 255.0, float((argb2 >> 8) & 255) / 255.0, float(argb2 & 255) / 255.0, 1.0)
			var a: Vector2 = Vector2(float(_frame.lines[o2]), float(_frame.lines[o2 + 1])) * m
			var b: Vector2 = Vector2(float(_frame.lines[o2 + 2]), float(_frame.lines[o2 + 3])) * m
			_line_mesh.surface_set_color(col2)
			_line_mesh.surface_add_vertex(Vector3(a.x, _v.ground_at(a.x, a.y) + 0.5, a.y))
			_line_mesh.surface_set_color(col2)
			_line_mesh.surface_add_vertex(Vector3(b.x, _v.ground_at(b.x, b.y) + 0.5, b.y))
		_line_mesh.surface_end()
	line_count = nl
	_heat_quad()


func _circle_node(i: int) -> MeshInstance3D:
	while _circles.size() <= i:
		var n: MeshInstance3D = MeshInstance3D.new()
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _shader
		mat.render_priority = 4
		mat.set_shader_parameter(&"kind", 0)
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.layers = ViewLayers.MASK_OVERLAYS
		add_child(n)
		_circles.append(n)
	return _circles[i]


func _label_node(i: int) -> Label3D:
	while _labels.size() <= i:
		var l: Label3D = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.no_depth_test = true
		l.pixel_size = 0.0008
		l.font_size = 28
		l.outline_size = 8
		l.layers = ViewLayers.MASK_OVERLAYS
		add_child(l)
		_labels.append(l)
	return _labels[i]


## Threat heat: a heat_w x heat_h grid of blocks (0..255) over the whole map as one translucent ground quad.
func _heat_quad() -> void:
	if _frame.heat_w <= 0 or _frame.heat_h <= 0 or _frame.heat.size() < _frame.heat_w * _frame.heat_h or _v.terrain == null:
		return
	var img: Image = Image.create_empty(_frame.heat_w, _frame.heat_h, false, Image.FORMAT_RGBA8)
	for y: int in _frame.heat_h:
		for x: int in _frame.heat_w:
			var h: float = clampf(float(_frame.heat[y * _frame.heat_w + x]) / 255.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.25 + 0.5 * (1.0 - h), 0.1, h * 0.55))
	_heat_tex = ImageTexture.create_from_image(img)
	if _heat == null:
		_heat = MeshInstance3D.new()
		var pm: PlaneMesh = PlaneMesh.new()
		pm.size = Vector2.ONE
		_heat.mesh = pm
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.no_depth_test = false
		_heat.material_override = mat
		_heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_heat.layers = ViewLayers.MASK_OVERLAYS
		add_child(_heat)
	var ws: Vector2 = _v.terrain.world_size()
	(_heat.material_override as StandardMaterial3D).albedo_texture = _heat_tex
	_heat.transform = Transform3D(Basis.from_scale(Vector3(ws.x, 1.0, ws.y)), Vector3(ws.x * 0.5, 2.0, ws.y * 0.5))
	_heat.visible = true
