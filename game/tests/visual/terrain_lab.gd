extends Node3D
## VIEW-02 / VIEW-05 visual acceptance: generates a REAL map with MapGenerator (open land 192x192, fixed seed), builds the
## terrain stack (ViewTerrainSource -> ViewTerrain) and looks at it through ViewCamera at the RTS camera range.
## The sun / sky / grade below is a stand-in for VIEW-03's ViewAtmosphere (values of the terrain spike's two moods).
##   tools/gd shot res://tests/visual/terrain_lab.tscn out.png --size 1920x1080 -- --biome=0 --view=gameplay
## Args: --biome=0|1|2|3 --seed=N --family=0|1|2 --size=N --view=<name> --focus=cx,cy --yaw=deg --zoom=0..1 --bias=deg
##       --low (TERRAIN_LOW variant) --nofow

const VIEWS: Dictionary = {
	"overview": [Vector2(96, 96), 0.0, 1.0, 0.0],
	"gameplay": [Vector2(92, 104), 15.0, 0.5, 0.0],
	"close": [Vector2(70, 80), 20.0, 0.0, 0.0],
	"far": [Vector2(96, 100), 15.0, 0.95, 0.0],
	"road": [Vector2(88, 82), 60.0, 0.30, 0.0],
	"mid": [Vector2(60, 120), -20.0, 0.35, 0.0],
}

const MOODS: Dictionary = {
	0: {"elev": 40.0, "az": 222.0, "sun": Color(1.0, 0.94, 0.82), "energy": 1.55, "top": Color(0.17, 0.38, 0.78), "horizon": Color(0.66, 0.78, 0.92),
		"gh": Color(0.58, 0.64, 0.64), "gb": Color(0.24, 0.27, 0.26), "amb": 0.78, "fog": Color(0.64, 0.76, 0.90), "fog_d": 0.0011,
		"exposure": 1.18, "white": 5.0, "sat": 1.12, "contrast": 1.06, "dryness": 0.0,
		"palette": {
			"grass_a": Color(0.24, 0.42, 0.12), "grass_b": Color(0.42, 0.60, 0.20), "dry_a": Color(0.48, 0.42, 0.22), "dry_b": Color(0.62, 0.55, 0.30),
			"dirt_a": Color(0.29, 0.22, 0.15), "dirt_b": Color(0.45, 0.35, 0.25), "rock_a": Color(0.27, 0.26, 0.25), "rock_b": Color(0.46, 0.43, 0.40),
			"sand_a": Color(0.72, 0.65, 0.46), "sand_b": Color(0.86, 0.79, 0.59), "snow_c": Color(0.93, 0.96, 1.0)}},
	1: {"elev": 17.0, "az": 250.0, "sun": Color(1.0, 0.72, 0.46), "energy": 2.1, "top": Color(0.20, 0.27, 0.55), "horizon": Color(0.96, 0.62, 0.40),
		"gh": Color(0.60, 0.42, 0.34), "gb": Color(0.18, 0.13, 0.12), "amb": 1.0, "fog": Color(0.80, 0.58, 0.48), "fog_d": 0.0011,
		"exposure": 1.25, "white": 4.5, "sat": 1.0, "contrast": 1.08, "dryness": 1.0,
		"palette": {
			"grass_a": Color(0.24, 0.40, 0.12), "grass_b": Color(0.40, 0.56, 0.19), "dry_a": Color(0.56, 0.46, 0.28), "dry_b": Color(0.72, 0.60, 0.38),
			"dirt_a": Color(0.36, 0.26, 0.19), "dirt_b": Color(0.52, 0.40, 0.29), "rock_a": Color(0.36, 0.31, 0.29), "rock_b": Color(0.60, 0.52, 0.45),
			"sand_a": Color(0.74, 0.62, 0.44), "sand_b": Color(0.90, 0.78, 0.58), "snow_c": Color(0.90, 0.88, 0.92)}},
}

var terrain: ViewTerrain = null
var cam: ViewCamera = null
var map: MapData = null
var boot: Dictionary = {}
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var biome: int = int(_args.get("biome", "0"))
	var t0: int = Time.get_ticks_usec()
	map = MapGenerator.generate({
		"family": int(_args.get("family", "0")), "size": int(_args.get("size", "192")), "seed": int(_args.get("seed", "1337")),
		"layout_players": int(_args.get("players", "2")), "params": {"biome": biome},
	})
	var t1: int = Time.get_ticks_usec()
	if map == null:
		push_error("terrain_lab: map generation failed")
		return
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var detail: ViewDetailTextures = ViewDetailTextures.build(256)
	var t2: int = Time.get_ticks_usec()
	terrain = ViewTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(src, 2, detail, _args.has("low"))
	var t3: int = Time.get_ticks_usec()
	boot = {"gen_ms": (t1 - t0) / 1000.0, "source_detail_ms": (t2 - t1) / 1000.0, "terrain_ms": (t3 - t2) / 1000.0, "stats": terrain.stats}
	var mood: Dictionary = MOODS[1 if biome == 1 else 0]
	_atmosphere(mood)
	terrain.apply_palette(mood["palette"] as Dictionary, mood["dryness"] as float)
	if _args.has("nofow"):
		terrain.material.set_shader_parameter("fow_enabled", 0.0)
	cam = ViewCamera.new()
	cam.name = "Camera"
	cam.auto_input = false
	cam.edge_scroll_enabled = false
	add_child(cam)
	cam.configure(Rect2(Vector2.ZERO, terrain.world_size()), terrain)
	var v: Array = VIEWS.get(str(_args.get("view", "gameplay")), VIEWS["gameplay"])
	var focus: Vector2 = v[0] as Vector2
	if _args.has("focus"):
		var p: PackedStringArray = str(_args["focus"]).split(",")
		focus = Vector2(float(p[0]), float(p[1]))
	if _args.has("find"):
		focus = _find_focus(str(_args["find"]), focus)
	# start cell of the first player: a gameplay-relevant default when no view / focus was chosen
	if not _args.has("focus") and not _args.has("view") and not _args.has("find") and map.start_cells.size() >= 2:
		focus = Vector2(float(map.start_cells[0]), float(map.start_cells[1]) + 6.0)
	if terrain.src.has_water():
		_water_stand_in(terrain.src.sea_level_m)
	cam.snap_to(focus * ViewConsts.CELL_M, float(_args.get("yaw", str(v[1]))), float(_args.get("zoom", str(v[2]))), float(_args.get("bias", str(v[3]))))
	cam.advance(0.0)
	_fit_shadows()
	print("TERRAIN_LAB ", boot, " sea=", terrain.src.sea_level_m, " focus=", focus, " ground=", terrain.height_at(focus.x * 3.0, focus.y * 3.0))


## --find=water|cliff|ramp|mountain|forest|urban|road|rock: focus on the first such cell (scan from the map centre outwards).
func _find_focus(what: String, dflt: Vector2) -> Vector2:
	var ids: Dictionary = {"water": [1, 2], "deep": [0], "marsh": [15], "cliff": [13], "mountain": [14], "forest": [8], "urban": [12], "road": [9], "rock": [7], "sand": [6], "beach": [3]}
	var best: Vector2 = dflt
	var best_d: float = 1.0e9
	for i: int in map.n:
		var hit: bool = (what == "ramp" and (map.flags[i] & MapData.SF_RAMP) != 0) or (ids.has(what) and (ids[what] as Array).has(int(map.terrain[i])))
		if what == "mountain" and hit and (i % map.w < 8 or i / map.w < 8 or i % map.w > map.w - 9 or i / map.w > map.h - 9):
			hit = false
		if hit:
			var p: Vector2 = Vector2(float(i % map.w), float(i / map.w))
			var d: float = p.distance_to(Vector2(float(map.w) * 0.5, float(map.h) * 0.5))
			if d < best_d:
				best_d = d
				best = p
	return best


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


var _sun: DirectionalLight3D = null


## Stand-in for VIEW-03's ViewWater: one translucent plane at the sea level.
func _water_stand_in(level: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = terrain.world_size() * 3.0
	mi.mesh = pm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.32, 0.45, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic_specular = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(terrain.world_size().x * 0.5, level, terrain.world_size().y * 0.5)
	add_child(mi)


func _atmosphere(m: Dictionary) -> void:
	var el: float = deg_to_rad(m["elev"] as float)
	var az: float = deg_to_rad(m["az"] as float)
	var to_sun: Vector3 = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.4
	_sun.light_color = m["sun"] as Color
	_sun.light_energy = m["energy"] as float
	add_child(_sun)
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	var sm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sm.sky_top_color = m["top"] as Color
	sm.sky_horizon_color = m["horizon"] as Color
	sm.ground_horizon_color = m["gh"] as Color
	sm.ground_bottom_color = m["gb"] as Color
	sm.sky_curve = 0.18
	var sky: Sky = Sky.new()
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = m["amb"] as float
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = m["exposure"] as float
	env.tonemap_white = m["white"] as float
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = m["fog"] as Color
	env.fog_density = m["fog_d"] as float
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = m["sat"] as float
	env.adjustment_contrast = m["contrast"] as float
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	ViewGlobals.set_value(ViewGlobals.G_ATM_SUN_DIR, to_sun)
	var sc: Color = (m["sun"] as Color).srgb_to_linear()
	ViewGlobals.set_value(ViewGlobals.G_ATM_SUN_COLOR, Vector3(sc.r, sc.g, sc.b) * (m["energy"] as float))
	var hc: Color = (m["horizon"] as Color).srgb_to_linear()
	var zc: Color = (m["top"] as Color).srgb_to_linear()
	ViewGlobals.set_value(ViewGlobals.G_ATM_SKY_HORIZON, Vector3(hc.r, hc.g, hc.b))
	ViewGlobals.set_value(ViewGlobals.G_ATM_SKY_ZENITH, Vector3(zc.r, zc.g, zc.b))
	ViewGlobals.set_value(ViewGlobals.G_ATM_CLOUD, Vector4(0.12, 1.0 / 240.0, 3.0, 1.2))


## Same numbers as the spike's fit_shadows: cascades start where the ground begins.
func _fit_shadows() -> void:
	var h: float = cam.current_height()
	var pitch: float = cam.current_pitch_deg()
	var a_top: float = deg_to_rad(clampf(pitch - cam.fov_deg * 0.5, 8.0, 89.0))
	var far_depth: float = h / sin(a_top) * cos(a_top - deg_to_rad(pitch))
	_sun.directional_shadow_max_distance = far_depth * 1.09 + 12.0
	_sun.directional_shadow_split_1 = 0.16
	_sun.directional_shadow_split_2 = 0.38
	_sun.directional_shadow_split_3 = 0.68
