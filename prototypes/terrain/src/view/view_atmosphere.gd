class_name ViewAtmosphere
extends Node3D
## Sky, sun (cascaded shadows tuned for a 40-80 m RTS camera), ambient, SSAO/SSIL/glow, tonemap, fog and a
## per-channel colour-grade LUT, all driven by a ViewMoodDef. No baked GI: sky ambient + SSAO + cavity terms.

const G_SUN_DIR: StringName = &"atm_sun_dir"
const G_SUN_COLOR: StringName = &"atm_sun_color"
const G_SKY_HORIZON: StringName = &"atm_sky_horizon"
const G_SKY_ZENITH: StringName = &"atm_sky_zenith"
const G_CLOUD: StringName = &"atm_cloud"

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky: Sky
var sky_material: ProceduralSkyMaterial
var mood: ViewMoodDef
var tonemapper: int = Environment.TONE_MAPPER_ACES

static var _registered: bool = false


## Registers the atmosphere globals. Call once at boot before compiling materials that include atmosphere.gdshaderinc.
static func register_globals() -> void:
	if _registered:
		return
	_registered = true
	RenderingServer.global_shader_parameter_add(G_SUN_DIR, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.4, 0.8, 0.4))
	RenderingServer.global_shader_parameter_add(G_SUN_COLOR, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(1, 1, 1))
	RenderingServer.global_shader_parameter_add(G_SKY_HORIZON, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.6, 0.7, 0.8))
	RenderingServer.global_shader_parameter_add(G_SKY_ZENITH, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.2, 0.4, 0.8))
	RenderingServer.global_shader_parameter_add(G_CLOUD, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0.2, 1.0 / 240.0, 3.0, 1.2))


func setup() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_fade_start = 0.9
	sun.light_angular_distance = 0.0
	add_child(sun)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 25.0
	sky_material.sun_curve = 0.12
	sky_material.sky_curve = 0.18
	sky = Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_QUALITY   # PROCESS_MODE_AUTOMATIC picks INCREMENTAL for this material (per-frame cost)
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = tonemapper as Environment.ToneMapper
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.25
	env.ssao_ao_channel_affect = 0.4
	env.ssil_enabled = false
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_scale = 2.0
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.4)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 0.6)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 60.0, 400.0)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)


func apply_mood(m: ViewMoodDef) -> void:
	mood = m
	var el: float = deg_to_rad(m.sun_elevation_deg)
	var az: float = deg_to_rad(m.sun_azimuth_deg)
	var to_sun: Vector3 = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_color = m.sun_color
	sun.light_energy = m.sun_energy

	sky_material.sky_top_color = m.sky_top
	sky_material.sky_horizon_color = m.sky_horizon
	sky_material.ground_horizon_color = m.ground_horizon
	sky_material.ground_bottom_color = m.ground_bottom
	sky_material.sun_curve = 0.06 if m.sun_elevation_deg < 25.0 else 0.12

	env.ambient_light_energy = m.ambient_energy
	env.tonemap_exposure = m.exposure
	env.tonemap_white = m.white_point
	env.ssao_intensity = m.ssao_intensity
	env.glow_intensity = m.glow_intensity
	env.glow_hdr_threshold = m.glow_threshold
	env.fog_light_color = m.fog_color
	env.fog_density = m.fog_density
	env.fog_sun_scatter = m.fog_sun_scatter
	env.fog_aerial_perspective = m.fog_aerial
	env.adjustment_saturation = m.saturation
	env.adjustment_contrast = m.contrast
	env.adjustment_brightness = m.brightness
	env.adjustment_color_correction = _make_lut(m)

	RenderingServer.global_shader_parameter_set(G_SUN_DIR, to_sun)
	RenderingServer.global_shader_parameter_set(G_SUN_COLOR, _lin(m.sun_color) * m.sun_energy)
	RenderingServer.global_shader_parameter_set(G_SKY_HORIZON, _lin(m.sky_horizon))
	RenderingServer.global_shader_parameter_set(G_SKY_ZENITH, _lin(m.sky_top))
	RenderingServer.global_shader_parameter_set(G_CLOUD, Vector4(m.cloud_strength, 1.0 / 240.0, 3.0, 1.2))


static func _lin(c: Color) -> Vector3:
	var l: Color = c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


## Per-channel 1D grading curve: out = lift*(1-x) + gain * x^(1/gamma)  (split toning: cool shadows, warm highlights).
static func _make_lut(m: ViewMoodDef) -> GradientTexture1D:
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	for i in 9:
		var x: float = float(i) / 8.0
		offsets.append(x)
		colors.append(Color(
			clampf(m.lift.r * (1.0 - x) + m.gain.r * pow(x, 1.0 / m.gamma.r), 0.0, 1.0),
			clampf(m.lift.g * (1.0 - x) + m.gain.g * pow(x, 1.0 / m.gamma.g), 0.0, 1.0),
			clampf(m.lift.b * (1.0 - x) + m.gain.b * pow(x, 1.0 / m.gamma.b), 0.0, 1.0), 1.0))
	var g: Gradient = Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


## Fits the shadow cascades to the visible ground for a camera at `height` m above the focus, pitch below the
## horizon, vertical fov. Ground depth along the view axis spans ~[height/sin(a_bottom)*cos(dp), height/sin(a_top)*cos(dp)].
## Returns the recommended camera near plane (start cascades where ground begins so no shadow texels are wasted).
func fit_shadows(height: float, pitch_deg: float, fov_deg: float, aspect: float = 1.78) -> float:
	var a_bot: float = deg_to_rad(pitch_deg + fov_deg * 0.5)
	var a_top: float = deg_to_rad(clampf(pitch_deg - fov_deg * 0.5, 8.0, 89.0))
	var pitch: float = deg_to_rad(pitch_deg)
	var near_depth: float = height / sin(minf(a_bot, 1.5)) * cos(a_bot - pitch)
	var far_depth: float = height / sin(a_top) * cos(a_top - pitch)
	var margin: float = 1.0 + 0.10 * aspect * 0.5
	var near_plane: float = maxf(2.0, near_depth * 0.82)
	sun.directional_shadow_max_distance = far_depth * margin + 12.0
	sun.directional_shadow_split_1 = 0.16
	sun.directional_shadow_split_2 = 0.38
	sun.directional_shadow_split_3 = 0.68
	return near_plane


func set_ssao(enabled: bool) -> void:
	env.ssao_enabled = enabled


func set_ssil(enabled: bool) -> void:
	env.ssil_enabled = enabled


func set_glow(enabled: bool) -> void:
	env.glow_enabled = enabled


func set_fog(enabled: bool) -> void:
	env.fog_enabled = enabled


func set_volumetric_fog(enabled: bool) -> void:
	env.volumetric_fog_enabled = enabled
	if enabled:
		env.volumetric_fog_density = 0.008
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_albedo = mood.fog_color


func set_tonemapper(mode: int) -> void:
	tonemapper = mode
	env.tonemap_mode = mode as Environment.ToneMapper


## 0 = no sun shadows, 1 = 2 cascades, 2 = 4 cascades.
func set_shadow_cascades(level: int) -> void:
	sun.shadow_enabled = level > 0
	if level == 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	elif level == 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
