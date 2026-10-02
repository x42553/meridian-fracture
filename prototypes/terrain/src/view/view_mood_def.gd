class_name ViewMoodDef
extends RefCounted
## Data-driven look for a map (sun, sky, fog, grading, terrain/water palette). Two presets are provided.

var mood_name: String = ""
var sun_elevation_deg: float = 50.0
var sun_azimuth_deg: float = 215.0
var sun_color: Color = Color.WHITE
var sun_energy: float = 1.3
var sky_top: Color = Color.WHITE
var sky_horizon: Color = Color.WHITE
var ground_horizon: Color = Color.WHITE
var ground_bottom: Color = Color.WHITE
var ambient_energy: float = 1.0
var fog_color: Color = Color.WHITE
var fog_density: float = 0.001
var fog_sun_scatter: float = 0.2
var fog_aerial: float = 0.3
var exposure: float = 1.0
var white_point: float = 6.0
var saturation: float = 1.05
var contrast: float = 1.05
var brightness: float = 1.0
var lift: Color = Color(0, 0, 0)
var gamma: Color = Color(1, 1, 1)
var gain: Color = Color(1, 1, 1)
var glow_intensity: float = 0.5
var glow_threshold: float = 1.1
var ssao_intensity: float = 2.2
var dryness: float = 0.0
var cloud_strength: float = 0.22
var water_shallow: Color = Color.WHITE
var water_deep: Color = Color.WHITE
var water_absorb: float = 0.45
var foliage_a: Color = Color.WHITE
var foliage_b: Color = Color.WHITE
var palette: Dictionary = {}


static func temperate_day() -> ViewMoodDef:
	var m: ViewMoodDef = ViewMoodDef.new()
	m.mood_name = "temperate_day"
	m.sun_elevation_deg = 40.0
	m.sun_azimuth_deg = 222.0
	m.sun_color = Color(1.0, 0.94, 0.82)
	m.sun_energy = 1.55
	m.sky_top = Color(0.17, 0.38, 0.78)
	m.sky_horizon = Color(0.66, 0.78, 0.92)
	m.ground_horizon = Color(0.58, 0.64, 0.64)
	m.ground_bottom = Color(0.24, 0.27, 0.26)
	m.ambient_energy = 0.78
	m.fog_color = Color(0.64, 0.76, 0.90)
	m.fog_density = 0.0011
	m.fog_sun_scatter = 0.25
	m.fog_aerial = 0.35
	m.exposure = 1.18
	m.white_point = 5.0
	m.saturation = 1.12
	m.contrast = 1.06
	m.lift = Color(0.012, 0.018, 0.03)
	m.gamma = Color(1.0, 1.0, 1.02)
	m.gain = Color(1.03, 1.0, 0.95)
	m.glow_intensity = 0.45
	m.glow_threshold = 1.15
	m.ssao_intensity = 1.5
	m.dryness = 0.0
	m.cloud_strength = 0.12
	m.water_shallow = Color(0.16, 0.58, 0.62)
	m.water_deep = Color(0.03, 0.18, 0.34)
	m.water_absorb = 0.42
	m.foliage_a = Color(0.16, 0.34, 0.10)
	m.foliage_b = Color(0.34, 0.50, 0.14)
	m.palette = {
		"grass_a": Color(0.24, 0.42, 0.12), "grass_b": Color(0.42, 0.60, 0.20),
		"dry_a": Color(0.48, 0.42, 0.22), "dry_b": Color(0.62, 0.55, 0.30),
		"dirt_a": Color(0.29, 0.22, 0.15), "dirt_b": Color(0.45, 0.35, 0.25),
		"rock_a": Color(0.27, 0.26, 0.25), "rock_b": Color(0.46, 0.43, 0.40),
		"sand_a": Color(0.72, 0.65, 0.46), "sand_b": Color(0.86, 0.79, 0.59),
		"snow_c": Color(0.93, 0.96, 1.0),
	}
	return m


static func arid_dusk() -> ViewMoodDef:
	var m: ViewMoodDef = ViewMoodDef.new()
	m.mood_name = "arid_dusk"
	m.sun_elevation_deg = 17.0
	m.sun_azimuth_deg = 250.0
	m.sun_color = Color(1.0, 0.72, 0.46)
	m.sun_energy = 2.1
	m.sky_top = Color(0.20, 0.27, 0.55)
	m.sky_horizon = Color(0.96, 0.62, 0.40)
	m.ground_horizon = Color(0.60, 0.42, 0.34)
	m.ground_bottom = Color(0.18, 0.13, 0.12)
	m.ambient_energy = 1.0
	m.fog_color = Color(0.80, 0.58, 0.48)
	m.fog_density = 0.0011
	m.fog_sun_scatter = 0.5
	m.fog_aerial = 0.4
	m.exposure = 1.25
	m.white_point = 4.5
	m.saturation = 1.0
	m.contrast = 1.08
	m.lift = Color(0.035, 0.03, 0.06)
	m.gamma = Color(1.0, 1.0, 1.02)
	m.gain = Color(1.03, 0.98, 0.92)
	m.glow_intensity = 0.6
	m.glow_threshold = 1.0
	m.ssao_intensity = 1.8
	m.dryness = 1.0
	m.cloud_strength = 0.18
	m.water_shallow = Color(0.28, 0.55, 0.55)
	m.water_deep = Color(0.05, 0.13, 0.26)
	m.water_absorb = 0.5
	m.foliage_a = Color(0.40, 0.40, 0.15)
	m.foliage_b = Color(0.62, 0.52, 0.20)
	m.palette = {
		"grass_a": Color(0.24, 0.40, 0.12), "grass_b": Color(0.40, 0.56, 0.19),
		"dry_a": Color(0.56, 0.46, 0.28), "dry_b": Color(0.72, 0.60, 0.38),
		"dirt_a": Color(0.36, 0.26, 0.19), "dirt_b": Color(0.52, 0.40, 0.29),
		"rock_a": Color(0.36, 0.31, 0.29), "rock_b": Color(0.60, 0.52, 0.45),
		"sand_a": Color(0.74, 0.62, 0.44), "sand_b": Color(0.90, 0.78, 0.58),
		"snow_c": Color(0.90, 0.88, 0.92),
	}
	return m
