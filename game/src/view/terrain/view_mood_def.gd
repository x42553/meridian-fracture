class_name ViewMoodDef
extends RefCounted
## Data-driven look of a map (render spec 4.10 / 5.6 / 7.6): sun, sky, fog, grading, water and terrain palette. The five moods
## live in data/recipes/moods.json; `load_all` reads them, `for_map` picks the mood of a map (biome / family).
## Presentation only. Colours are sRGB authored (Color), converted to linear where a shader global needs it.

const JSON_PATH: String = "res://data/recipes/moods.json"
const FALLBACK_MOOD: String = "temperate_day"

static var _tables: Dictionary = {}  ## biome_to_mood / family_override of the last load_all

var mood_name: String = ""
var sun_elevation_deg: float = 40.0
var sun_azimuth_deg: float = 222.0
var sun_color: Color = Color.WHITE
var sun_energy: float = 1.5
var sky_top: Color = Color(0.17, 0.38, 0.78)
var sky_horizon: Color = Color(0.66, 0.78, 0.92)
var ground_horizon: Color = Color(0.58, 0.64, 0.64)
var ground_bottom: Color = Color(0.24, 0.27, 0.26)
var ambient_energy: float = 1.0
var fog_color: Color = Color(0.64, 0.76, 0.90)
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
var ssao_intensity: float = 2.0
var dryness: float = 0.0
var cloud_strength: float = 0.2
var water_shallow: Color = Color(0.16, 0.58, 0.62)
var water_deep: Color = Color(0.03, 0.18, 0.34)
var water_absorb: float = 0.45
var foliage_a: Color = Color(0.16, 0.34, 0.10)
var foliage_b: Color = Color(0.34, 0.50, 0.14)
var night: float = 0.0  ## 0 day .. 1 night: `atm_night` (emissive multiplier 1 + 1.2 * night, lit windows)
var wet: float = 0.0  ## roads / sand roughness reduction
var decor_kit: String = "broadleaf"  ## broadleaf | conifer | palm
var compat_grade: Dictionary = {}  ## {lift, gamma, gain} as Color values; used instead of lift/gamma/gain on Compatibility
var palette: Dictionary = {}  ## terrain uniform name -> Color (grass_a .. snow_c)


## All moods of the JSON file keyed by id. Returns {} after Log.error when the file is missing or malformed.
static func load_all(path: String = JSON_PATH) -> Dictionary:
	var txt: String = FileAccess.get_file_as_string(path)
	if txt.is_empty():
		Log.error("view", "ViewMoodDef: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("moods"):
		Log.error("view", "ViewMoodDef: %s is not a mood table" % path)
		return {}
	var doc: Dictionary = parsed as Dictionary
	var out: Dictionary = {}
	var moods: Dictionary = doc["moods"] as Dictionary
	for key: Variant in moods.keys():
		out[String(key)] = from_dict(String(key), moods[key] as Dictionary)
	# the biome / family tables travel with the moods so for_map has no second file
	_tables = {"biome_to_mood": doc.get("biome_to_mood", {}), "family_override": doc.get("family_override", {})}
	return out



## Mood for a map: biome 0..3 -> temperate_day / arid_dusk / arctic_day / tropical_day; the urban family (family 1) picks
## urban_night when `night_allowed`, else the `else` mood (temperate_day). DEVIATION from spec 5.6: the map generator forces
## MapData.biome = 3 for urban maps (3 is NOT tropical there), so the urban override matches biome 0 or 3 (`when_biome`
## list) instead of biome 0 only. Falls back to temperate_day, then to any mood, then to a default record.
## Looks the "auto" setting spreads over temperate (biome 0) non-city maps by map seed (grass-friendly looks only): a presentation-only variety, the same on every client.
const AUTO_LOOKS: PackedStringArray = ["temperate_day", "temperate_golden", "temperate_day", "temperate_overcast", "tropical_day", "temperate_day", "temperate_golden", "temperate_day"]


## `look`: the player's "Environment look" setting ("auto" or a mood id); `seed_value` >= 0 lets "auto" vary temperate maps by seed.
static func for_map(biome: int, family: int, moods: Dictionary, night_allowed: bool = true, seed_value: int = -1, look: String = "auto") -> ViewMoodDef:
	if look != "auto" and look != "" and moods.has(look):
		return moods[look] as ViewMoodDef
	var b2m: Dictionary = _tables.get("biome_to_mood", {"0": "temperate_day", "1": "arid_dusk", "2": "arctic_day", "3": "tropical_day"}) as Dictionary
	var fo: Dictionary = _tables.get("family_override", {"1": {"when_biome": [0, 3], "mood": "urban_night", "needs": "night_allowed", "else": "temperate_day"}}) as Dictionary
	var id: String = String(b2m.get(str(biome), FALLBACK_MOOD))
	var ov: Variant = fo.get(str(family))
	if ov is Dictionary:
		var od: Dictionary = ov as Dictionary
		var wb: Variant = od.get("when_biome", [])
		var biomes: Array = wb as Array if wb is Array else [int(wb)]
		var hit: bool = false
		for b: Variant in biomes:
			hit = hit or int(b) == biome
		if hit:
			var needs_ok: bool = String(od.get("needs", "")) != "night_allowed" or night_allowed
			id = String(od.get("mood", id)) if needs_ok else String(od.get("else", FALLBACK_MOOD))
	if id == FALLBACK_MOOD and biome == 0 and family != 1 and seed_value >= 0:
		var pick: String = AUTO_LOOKS[(seed_value * 2654435761 >> 7) & 7]
		if moods.has(pick):
			return moods[pick] as ViewMoodDef
	if moods.has(id):
		return moods[id] as ViewMoodDef
	if moods.has(FALLBACK_MOOD):
		return moods[FALLBACK_MOOD] as ViewMoodDef
	for k: Variant in moods.keys():
		return moods[k] as ViewMoodDef
	return ViewMoodDef.new()


static func from_dict(id: String, d: Dictionary) -> ViewMoodDef:
	var m: ViewMoodDef = ViewMoodDef.new()
	m.mood_name = id
	m.sun_elevation_deg = float(d.get("sun_elevation_deg", m.sun_elevation_deg))
	m.sun_azimuth_deg = float(d.get("sun_azimuth_deg", m.sun_azimuth_deg))
	m.sun_color = _col(d.get("sun_color"), m.sun_color)
	m.sun_energy = float(d.get("sun_energy", m.sun_energy))
	m.sky_top = _col(d.get("sky_top"), m.sky_top)
	m.sky_horizon = _col(d.get("sky_horizon"), m.sky_horizon)
	m.ground_horizon = _col(d.get("ground_horizon"), m.ground_horizon)
	m.ground_bottom = _col(d.get("ground_bottom"), m.ground_bottom)
	m.ambient_energy = float(d.get("ambient_energy", m.ambient_energy))
	m.fog_color = _col(d.get("fog_color"), m.fog_color)
	m.fog_density = float(d.get("fog_density", m.fog_density))
	m.fog_sun_scatter = float(d.get("fog_sun_scatter", m.fog_sun_scatter))
	m.fog_aerial = float(d.get("fog_aerial", m.fog_aerial))
	m.exposure = float(d.get("exposure", m.exposure))
	m.white_point = float(d.get("white_point", m.white_point))
	m.saturation = float(d.get("saturation", m.saturation))
	m.contrast = float(d.get("contrast", m.contrast))
	m.brightness = float(d.get("brightness", m.brightness))
	m.lift = _rgb(d.get("lift"), m.lift)
	m.gamma = _rgb(d.get("gamma"), m.gamma)
	m.gain = _rgb(d.get("gain"), m.gain)
	m.glow_intensity = float(d.get("glow_intensity", m.glow_intensity))
	m.glow_threshold = float(d.get("glow_threshold", m.glow_threshold))
	m.ssao_intensity = float(d.get("ssao_intensity", m.ssao_intensity))
	m.dryness = float(d.get("dryness", m.dryness))
	m.cloud_strength = float(d.get("cloud_strength", m.cloud_strength))
	m.water_shallow = _col(d.get("water_shallow"), m.water_shallow)
	m.water_deep = _col(d.get("water_deep"), m.water_deep)
	m.water_absorb = float(d.get("water_absorb", m.water_absorb))
	m.foliage_a = _col(d.get("foliage_a"), m.foliage_a)
	m.foliage_b = _col(d.get("foliage_b"), m.foliage_b)
	m.night = float(d.get("night", m.night))
	m.wet = float(d.get("wet", m.wet))
	m.decor_kit = String(d.get("decor_kit", m.decor_kit))
	var cg: Variant = d.get("compat_grade")
	if cg is Dictionary:
		var cgd: Dictionary = cg as Dictionary
		m.compat_grade = {
			"lift": _rgb(cgd.get("lift"), Color(0, 0, 0)),
			"gamma": _rgb(cgd.get("gamma"), Color(1, 1, 1)),
			"gain": _rgb(cgd.get("gain"), Color(1, 1, 1)),
		}
	var pal: Variant = d.get("palette")
	if pal is Dictionary:
		for k: Variant in (pal as Dictionary).keys():
			m.palette[String(k)] = _col((pal as Dictionary)[k], Color.MAGENTA)
	return m


## Lift / gamma / gain to use on the running renderer: the mood's own values, or `compat_grade` on Compatibility.
func grade(compat: bool) -> Dictionary:
	if compat and not compat_grade.is_empty():
		return compat_grade
	return {"lift": lift, "gamma": gamma, "gain": gain}


static func _col(v: Variant, dflt: Color) -> Color:
	if v is String:
		return Color.html(v as String)
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v as Array
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return dflt


static func _rgb(v: Variant, dflt: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v as Array
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return dflt
