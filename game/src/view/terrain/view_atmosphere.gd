class_name ViewAtmosphere
extends Node3D
## Sky, sun (cascaded shadows fitted to the 34-84 m RTS camera), ambient, SSAO / SSIL / glow, tonemap, exponential fog and
## a per-channel colour-grade LUT, all driven by a ViewMoodDef (render spec 3.4 / 5.6). No baked GI, no probes: the `atm_*`
## globals fake sky reflections and cloud shadows so every material agrees with the environment.
## Presentation only. ViewGlobals.ensure() registers the atm_* globals; this class only writes them.

const SPLIT_1: float = 0.16
const SPLIT_2: float = 0.38
const SPLIT_3: float = 0.68
const MAX_SHADOW_M: float = 320.0  ## VQ2A: upper bound of directional_shadow_max_distance (a far camera with a low pitch bias would ask for 650 m: four cascades over that range at 1080p)
const MIN_SHADOW_M: float = 30.0
const CLOUD_SCALE: float = 1.0 / 240.0
const CLOUD_DRIFT: Vector2 = Vector2(3.0, 1.2)

var sun: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var env: Environment = null
var sky: Sky = null
var sky_material: ProceduralSkyMaterial = null
var mood: ViewMoodDef = null
var tonemapper: int = Environment.TONE_MAPPER_ACES
var compat: bool = false  ## Compatibility renderer: the mood's `compat_grade` replaces lift / gamma / gain
var cloud_shadows: bool = true

var globals: Dictionary = {}  ## last value written to each atm_* global (StringName -> Variant); the headless renderer keeps none

var _sun_dir: Vector3 = Vector3.UP


func setup() -> void:
	ViewGlobals.ensure()
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_fade_start = 0.9
	sun.light_angular_distance = 0.0
	sun.directional_shadow_split_1 = SPLIT_1
	sun.directional_shadow_split_2 = SPLIT_2
	sun.directional_shadow_split_3 = SPLIT_3
	add_child(sun)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 25.0
	sky_material.sun_curve = 0.12
	sky_material.sky_curve = 0.18
	sky = Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_QUALITY  # AUTOMATIC selects INCREMENTAL for this material (per-frame radiance work)
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


## Applies a mood: sun, sky, ambient, tonemap, glow, SSAO strength, fog, grade LUT and every atm_* global.
func apply_mood(m: ViewMoodDef) -> void:
	mood = m
	var el: float = deg_to_rad(m.sun_elevation_deg)
	var az: float = deg_to_rad(m.sun_azimuth_deg)
	_sun_dir = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	sun.basis = Basis.looking_at(-_sun_dir, Vector3.UP)
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
	env.adjustment_color_correction = make_lut(m.grade(compat))

	var sc: Vector3 = _lin(m.sun_color) * m.sun_energy
	_set_global(ViewGlobals.G_ATM_SUN_DIR, _sun_dir)
	_set_global(ViewGlobals.G_ATM_SUN_COLOR, sc)
	_set_global(ViewGlobals.G_ATM_SKY_HORIZON, _lin(m.sky_horizon))
	_set_global(ViewGlobals.G_ATM_SKY_ZENITH, _lin(m.sky_top))
	_write_cloud()
	set_night(m.night)


func sun_dir() -> Vector3:
	return _sun_dir


## 0 day .. 1 night: the `atm_night` global (unit / decor emissive multiplier 1 + 1.2 * k, lit windows).
func set_night(k: float) -> void:
	_set_global(ViewGlobals.G_ATM_NIGHT, clampf(k, 0.0, 1.0))


static func _lin(c: Color) -> Vector3:
	var l: Color = c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


func _write_cloud() -> void:
	var strength: float = mood.cloud_strength if (mood != null and cloud_shadows) else 0.0
	_set_global(ViewGlobals.G_ATM_CLOUD, Vector4(strength, CLOUD_SCALE, CLOUD_DRIFT.x, CLOUD_DRIFT.y))


## 256-px 1D grading curve per channel: out = lift * (1 - x) + gain * x^(1 / gamma) (split toning: cool shadows, warm lights).
## `grade` = {lift, gamma, gain} as Colors (ViewMoodDef.grade).
static func make_lut(grade: Dictionary) -> GradientTexture1D:
	var lift: Color = grade["lift"] as Color
	var gamma: Color = grade["gamma"] as Color
	var gain: Color = grade["gain"] as Color
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	for i: int in 9:
		var x: float = float(i) / 8.0
		offsets.append(x)
		colors.append(Color(
			clampf(lift.r * (1.0 - x) + gain.r * pow(x, 1.0 / gamma.r), 0.0, 1.0),
			clampf(lift.g * (1.0 - x) + gain.g * pow(x, 1.0 / gamma.g), 0.0, 1.0),
			clampf(lift.b * (1.0 - x) + gain.b * pow(x, 1.0 / gamma.b), 0.0, 1.0), 1.0))
	var g: Gradient = Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


## Fits the sun cascades to the ground a camera `height` m above the focus sees (pitch below the horizon, vertical fov):
## a_bot / a_top are the view-ray angles of the bottom / top screen edge, far_depth the ground distance of the top edge along
## the view axis. Sets `directional_shadow_max_distance = far_depth * (1 + 0.05 * aspect) + 12` (89 / 114 / 141 m at
## H = 34 / 54 / 84 with the camera's 46 -> 61 deg pitch and 38 deg fov) and the 0.16 / 0.38 / 0.68 splits.
## Returns the camera near plane to use: 0.6 * height, at least 2 m (the ground begins about 1.0 * height away).
func fit_shadows(height: float, pitch_deg: float, fov_deg: float, aspect: float = 1.78) -> float:
	var a_top: float = deg_to_rad(clampf(pitch_deg - fov_deg * 0.5, 8.0, 89.0))
	var pitch: float = deg_to_rad(pitch_deg)
	var far_depth: float = height / sin(a_top) * cos(a_top - pitch)
	sun.directional_shadow_max_distance = clampf(far_depth * (1.0 + 0.05 * aspect) + 12.0, MIN_SHADOW_M, MAX_SHADOW_M)
	sun.directional_shadow_split_1 = SPLIT_1
	sun.directional_shadow_split_2 = SPLIT_2
	sun.directional_shadow_split_3 = SPLIT_3
	return maxf(2.0, height * 0.6)


## Applies the quality table: cascades (0 = no shadow maps, blob shadows instead), glow, SSAO / SSIL, cloud shadows, and
## the renderer's colour grade (Compatibility uses the mood's compat_grade).
func apply_quality(q: ViewQuality) -> void:
	set_shadow_cascades(q.shadow_cascades())
	env.glow_enabled = q.get_bool(&"glow")
	var ao: Dictionary = q.ssao_settings()
	env.ssao_enabled = ao["enabled"] as bool
	env.ssil_enabled = q.get_bool(&"ssil")
	cloud_shadows = q.get_bool(&"cloud_shadows")
	var was_compat: bool = compat
	compat = q.renderer == ViewQuality.Renderer.COMPATIBILITY
	q.apply_to_rendering_server()
	if mood != null:
		if was_compat != compat:
			env.adjustment_color_correction = make_lut(mood.grade(compat))
		_write_cloud()


func set_ssao(enabled: bool) -> void:
	env.ssao_enabled = enabled


func set_ssil(enabled: bool) -> void:
	env.ssil_enabled = enabled


func set_glow(enabled: bool) -> void:
	env.glow_enabled = enabled


func set_fog(enabled: bool) -> void:
	env.fog_enabled = enabled


func set_tonemapper(mode: int) -> void:
	tonemapper = mode
	env.tonemap_mode = mode as Environment.ToneMapper


## 0 = no sun shadows, 2 = 2 cascades, 4 = 4 cascades (ViewQuality.shadow_cascades()).
func set_shadow_cascades(count: int) -> void:
	sun.shadow_enabled = count > 0
	if count == 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	elif count >= 4:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func _set_global(gname: StringName, value: Variant) -> void:
	globals[gname] = value
	ViewGlobals.set_value(gname, value)
