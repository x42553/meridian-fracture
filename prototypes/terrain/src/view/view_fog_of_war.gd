class_name ViewFogOfWar
extends RefCounted
## Per-cell fog-of-war feed (design + demo). Contract with the sim's vision layer:
## a PackedByteArray of width*height bytes, 0 = shroud, 1 = fog (explored), 2 = visible.
## The bytes reach the GPU untouched (R8, sampled with texelFetch); all smoothing is done in shaders.
## Two textures ping-pong so shaders cross-fade the previous and current state (see fog_of_war.gdshaderinc).

const STATE_SHROUD: int = 0
const STATE_FOG: int = 1
const STATE_VISIBLE: int = 2

var cells_w: int = 0
var cells_h: int = 0
var update_interval: float = 0.1
var last_upload_us: int = 0
var uploads: int = 0

static var _registered: bool = false

var _img: Image
var _tex: Array[ImageTexture] = []
var _cur: int = 0
var _blend_t: float = 1.0


## Registers the global shader parameters. Call once at boot, BEFORE any shader that includes
## fog_of_war.gdshaderinc is compiled.
static func register_globals() -> void:
	# Do NOT use RenderingServer.global_shader_parameter_get_list() to test for existence: it is editor-only and errors at runtime.
	if _registered:
		return
	_registered = true
	var blank: ImageTexture = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_R8))
	RenderingServer.global_shader_parameter_add(&"fow_curr", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, blank)
	RenderingServer.global_shader_parameter_add(&"fow_prev", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, blank)
	RenderingServer.global_shader_parameter_add(&"fow_blend", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	RenderingServer.global_shader_parameter_add(&"fow_rect", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 1, 1))
	RenderingServer.global_shader_parameter_add(&"fow_cells", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(1, 1))


func setup(w: int, h: int, origin_m: Vector2, cell_m: float) -> void:
	cells_w = w
	cells_h = h
	var zero: PackedByteArray = PackedByteArray()
	zero.resize(w * h)
	_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, zero)
	_tex = [ImageTexture.create_from_image(_img), ImageTexture.create_from_image(_img)]
	RenderingServer.global_shader_parameter_set(&"fow_rect", Vector4(origin_m.x, origin_m.y, 1.0 / (w * cell_m), 1.0 / (h * cell_m)))
	RenderingServer.global_shader_parameter_set(&"fow_cells", Vector2(w, h))
	_publish()


## Uploads a new state grid (call at 10 Hz). No conversion: the sim's bytes are the texture.
func submit(states: PackedByteArray) -> void:
	var t0: int = Time.get_ticks_usec()
	_cur = 1 - _cur
	_img.set_data(cells_w, cells_h, false, Image.FORMAT_R8, states)
	_tex[_cur].update(_img)
	_blend_t = 0.0
	_publish()
	last_upload_us = Time.get_ticks_usec() - t0
	uploads += 1


## Call every frame: drives the prev->curr cross-fade so 10 Hz data looks continuous.
func advance(delta: float) -> void:
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / update_interval)
		RenderingServer.global_shader_parameter_set(&"fow_blend", _blend_t)


func current_texture() -> ImageTexture:
	return _tex[_cur]


func _publish() -> void:
	RenderingServer.global_shader_parameter_set(&"fow_curr", _tex[_cur])
	RenderingServer.global_shader_parameter_set(&"fow_prev", _tex[1 - _cur])
	RenderingServer.global_shader_parameter_set(&"fow_blend", 0.0)
