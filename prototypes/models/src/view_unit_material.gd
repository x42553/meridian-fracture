class_name ViewUnitMaterial
extends RefCounted
## Factory for the shared unit ShaderMaterial (one per paint style) plus the global fog-of-war hook.
## The unit shader has two compile variants: default (instance uniforms, MeshInstance3D path) and MM
## (INSTANCE_CUSTOM, MultiMesh path). Both are built from the same .gdshader source via a #define prefix.

const SHADER_PATH: String = "res://shaders/unit.gdshader"

static var _shader: Shader
static var _shader_mm: Shader
static var _globals_ready: bool = false


## Registers the global shader parameters the unit shader reads. Call once at boot, BEFORE any material is created.
## fow_tex is a per-player visibility texture (R = 1 visible, 0 hidden); fow_rect = (origin.x, origin.z, 1/size.x, 1/size.z).
static func register_globals() -> void:
	if _globals_ready:
		return
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	RenderingServer.global_shader_parameter_add("fow_tex", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_add("fow_rect", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(-512.0, -512.0, 1.0 / 1024.0, 1.0 / 1024.0))
	_globals_ready = true


static func _get_shader(multimesh: bool) -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	if not multimesh:
		return _shader
	if _shader_mm == null:
		_shader_mm = Shader.new()
		_shader_mm.code = "#define MM 1\n" + _shader.code
	return _shader_mm


## style keys (all optional): wear, dirt, panel (0..1), wear_color, dirt_color (Color), quality (0..1), emissive (float).
static func create(style: Dictionary = {}, multimesh: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _get_shader(multimesh)
	if style.has("wear"):
		m.set_shader_parameter("wear_amount", float(style["wear"]))
	if style.has("dirt"):
		m.set_shader_parameter("dirt_amount", float(style["dirt"]))
	if style.has("panel"):
		m.set_shader_parameter("panel_amount", float(style["panel"]))
	if style.has("wear_color"):
		var wc: Color = style["wear_color"]
		m.set_shader_parameter("wear_color", Vector3(wc.r, wc.g, wc.b))
	if style.has("dirt_color"):
		var dc: Color = style["dirt_color"]
		m.set_shader_parameter("dirt_color", Vector3(dc.r, dc.g, dc.b))
	if style.has("quality"):
		m.set_shader_parameter("quality", float(style["quality"]))
	if style.has("emissive"):
		m.set_shader_parameter("emissive_strength", float(style["emissive"]))
	return m
