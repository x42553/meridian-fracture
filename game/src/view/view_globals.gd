class_name ViewGlobals
extends RefCounted
## Registers and updates every global shader parameter of the view (render spec 4.6). The names are the cross-shader
## contract: view_common / fog_of_war / atmosphere .gdshaderinc declare them, this class creates them.
##
## ensure() MUST run before any material that reads a global compiles. It is idempotent (static guard) and never calls
## RenderingServer.global_shader_parameter_get_list() (editor-only). Names already declared in project.godot
## [shader_globals] are respected and not added a second time.

const G_FX_TIME: StringName = &"fx_time"
const G_FX_LOD: StringName = &"fx_lod"
const G_VIEW_TIME: StringName = &"view_time"
const G_ATM_SUN_DIR: StringName = &"atm_sun_dir"
const G_ATM_SUN_COLOR: StringName = &"atm_sun_color"
const G_ATM_SKY_HORIZON: StringName = &"atm_sky_horizon"
const G_ATM_SKY_ZENITH: StringName = &"atm_sky_zenith"
const G_ATM_CLOUD: StringName = &"atm_cloud"
const G_ATM_NIGHT: StringName = &"atm_night"
const G_FOW_CURR: StringName = &"fow_curr"
const G_FOW_PREV: StringName = &"fow_prev"
const G_FOW_BLEND: StringName = &"fow_blend"
const G_FOW_RECT: StringName = &"fow_rect"
const G_FOW_CELLS: StringName = &"fow_cells"
const G_FOW_FOG_DIM: StringName = &"fow_fog_dim"

const ALL_NAMES: Array[StringName] = [
	G_FX_TIME, G_FX_LOD, G_VIEW_TIME, G_ATM_SUN_DIR, G_ATM_SUN_COLOR, G_ATM_SKY_HORIZON, G_ATM_SKY_ZENITH, G_ATM_CLOUD,
	G_ATM_NIGHT, G_FOW_CURR, G_FOW_PREV, G_FOW_BLEND, G_FOW_RECT, G_FOW_CELLS, G_FOW_FOG_DIM,
]

static var _ready: bool = false
static var _known: Dictionary = {}  # StringName -> true for every global this class registered or found declared
static var _view_time: float = 0.0
static var screenshot_mode: bool = false  ## view_time frozen at 0 when true (deterministic screenshots)


## Returns every global with its RenderingServer type and default value: [name, type, default].
static func definitions() -> Array:
	var visible_tex: ImageTexture = _blank_fog_texture()
	return [
		[G_FX_TIME, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[G_FX_LOD, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		[G_VIEW_TIME, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[G_ATM_SUN_DIR, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.4, 0.8, 0.4).normalized()],
		[G_ATM_SUN_COLOR, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1.0, 0.95, 0.85)],
		[G_ATM_SKY_HORIZON, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.6, 0.7, 0.8)],
		[G_ATM_SKY_ZENITH, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.2, 0.4, 0.8)],
		[G_ATM_CLOUD, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.2, 1.0 / 240.0, 3.0, 1.2)],
		[G_ATM_NIGHT, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[G_FOW_CURR, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, visible_tex],
		[G_FOW_PREV, RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, visible_tex],
		[G_FOW_BLEND, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		[G_FOW_RECT, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.0, 0.0, 1.0 / 1024.0, 1.0 / 1024.0)],
		[G_FOW_CELLS, RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(1.0, 1.0)],
		[G_FOW_FOG_DIM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
	]


## A 2x2 R8 texture whose every cell says "visible" (byte 2): the neutral fog state until ViewFogOfWar takes over.
static func _blank_fog_texture() -> ImageTexture:
	var img: Image = Image.create_empty(2, 2, false, Image.FORMAT_R8)
	img.fill(Color(2.0 / 255.0, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


## Registers every global that is not declared yet. Safe to call any number of times.
static func ensure() -> void:
	if _ready:
		return
	for d: Array in definitions():
		var gname: StringName = d[0] as StringName
		if _known.has(gname):
			continue
		if ProjectSettings.has_setting("shader_globals/" + String(gname)):
			_known[gname] = true
			continue
		RenderingServer.global_shader_parameter_add(gname, d[1] as int, d[2])
		_known[gname] = true
	_ready = true


static func is_ready() -> bool:
	return _ready


## Names this class manages (test helper).
static func names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: StringName in ALL_NAMES:
		out.append(String(n))
	return out


static func set_value(gname: StringName, value: Variant) -> void:
	ensure()
	RenderingServer.global_shader_parameter_set(gname, value)


## Per-frame: advances `view_time` (frozen at 0 in screenshot mode). fx_time belongs to FxManager.advance.
static func tick(dt: float) -> void:
	ensure()
	if screenshot_mode:
		_view_time = 0.0
	else:
		_view_time = fposmod(_view_time + dt, 3600.0)
	RenderingServer.global_shader_parameter_set(G_VIEW_TIME, _view_time)


static func view_time() -> float:
	return _view_time
