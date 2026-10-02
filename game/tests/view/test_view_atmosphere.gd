extends RefCounted
## VIEW-03: moods.json (five moods incl. night), mood selection, ViewAtmosphere (fit_shadows numbers, globals, LUT, quality),
## ViewWater and ViewMinimapSource.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")
const MOOD_IDS: Array[String] = ["temperate_day", "arid_dusk", "arctic_day", "tropical_day", "urban_night"]


func _atmo() -> ViewAtmosphere:
	var a: ViewAtmosphere = ViewAtmosphere.new()
	a.setup()
	return a


func test_five_moods_load_with_all_fields(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	t.eq(moods.size(), 7, "five biome / night moods plus the temperate golden-hour and overcast variants")
	for id: String in MOOD_IDS:
		t.check(moods.has(id), "mood %s present" % id)
		var m: ViewMoodDef = moods[id] as ViewMoodDef
		t.eq(m.mood_name, id, "%s name" % id)
		for key: String in ["grass_a", "grass_b", "dry_a", "dry_b", "dirt_a", "dirt_b", "rock_a", "rock_b", "sand_a", "sand_b", "snow_c"]:
			t.check(m.palette.has(key), "%s palette %s" % [id, key])
		t.check(m.compat_grade.has("gamma"), "%s has a compat grade" % id)
		t.gt(m.sun_energy, 0.0, "%s sun energy" % id)
	var temperate: ViewMoodDef = moods["temperate_day"] as ViewMoodDef
	t.near(temperate.sun_elevation_deg, 40.0, 1e-4, "temperate sun elevation (spike numbers)")
	t.near(temperate.sun_azimuth_deg, 222.0, 1e-4, "temperate sun azimuth")
	t.near(temperate.sun_energy, 1.55, 1e-4, "temperate sun energy")
	t.near((moods["arid_dusk"] as ViewMoodDef).sun_elevation_deg, 17.0, 1e-4, "arid dusk elevation")
	t.near((moods["urban_night"] as ViewMoodDef).night, 1.0, 1e-4, "urban_night is the night mood")
	t.near((moods["temperate_day"] as ViewMoodDef).night, 0.0, 1e-4, "day moods are not night")
	t.eq((moods["tropical_day"] as ViewMoodDef).decor_kit, "palm", "tropical kit")
	t.eq((moods["arctic_day"] as ViewMoodDef).decor_kit, "conifer", "arctic kit")


func test_for_map_selection(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	t.eq(ViewMoodDef.for_map(0, 0, moods).mood_name, "temperate_day", "biome 0")
	t.eq(ViewMoodDef.for_map(1, 0, moods).mood_name, "arid_dusk", "biome 1")
	t.eq(ViewMoodDef.for_map(2, 0, moods).mood_name, "arctic_day", "biome 2")
	t.eq(ViewMoodDef.for_map(3, 0, moods).mood_name, "tropical_day", "biome 3 on an open map")
	t.eq(ViewMoodDef.for_map(0, 1, moods, true).mood_name, "urban_night", "urban + night allowed (biome 0)")
	t.eq(ViewMoodDef.for_map(3, 1, moods, true).mood_name, "urban_night", "urban maps carry MapData.biome 3")
	t.eq(ViewMoodDef.for_map(3, 1, moods, false).mood_name, "temperate_day", "urban without night: day")
	t.eq(ViewMoodDef.for_map(1, 2, moods).mood_name, "arid_dusk", "coast keeps the biome mood")
	t.eq(ViewMoodDef.for_map(0, 0, {}).mood_name, "", "empty table: default record")


func test_look_setting_and_auto_variety(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	t.eq(ViewMoodDef.for_map(0, 0, moods, true, 5, "arid_dusk").mood_name, "arid_dusk", "an explicit look wins")
	t.eq(ViewMoodDef.for_map(0, 1, moods, true, 5, "tropical_day").mood_name, "tropical_day", "an explicit look wins on a city map too")
	t.eq(ViewMoodDef.for_map(0, 0, moods, true, -1, "auto").mood_name, "temperate_day", "auto without a seed stays temperate")
	t.eq(ViewMoodDef.for_map(0, 0, moods, true, 5, "nonsense").mood_name == "", false, "an unknown look falls back to a real mood")
	var seen: Dictionary = {}
	for sd: int in 64:
		var id: String = ViewMoodDef.for_map(0, 0, moods, true, sd, "auto").mood_name
		seen[id] = true
		t.eq(id, ViewMoodDef.for_map(0, 0, moods, true, sd, "auto").mood_name, "auto is a pure function of the seed")
	t.check(seen.size() >= 3, "auto spreads temperate maps over several looks (got %d)" % seen.size())
	t.eq(ViewMoodDef.for_map(3, 1, moods, true, 9, "auto").mood_name, "urban_night", "city maps stay night maps under auto")
	t.eq(ViewMoodDef.for_map(1, 0, moods, true, 9, "auto").mood_name, "arid_dusk", "a non-temperate biome is never re-rolled")
	for sd2: int in 64:
		t.check(ViewMoodDef.AUTO_LOOKS.has(ViewMoodDef.for_map(0, 0, moods, true, sd2, "auto").mood_name), "auto only picks grass-friendly looks")


func test_fit_shadows_numbers(t: TestCtx) -> void:
	var a: ViewAtmosphere = _atmo()
	var cam: ViewCamera = ViewCamera.new()
	var expect: Dictionary = {34.0: 89.0, 54.0: 114.0, 84.0: 141.0}
	for h: float in expect.keys():
		var z: float = 0.0
		# invert the camera's height curve: zoom01 whose height is h
		for step: int in 1001:
			var zz: float = float(step) / 1000.0
			if absf(cam._height_of(zz) - h) < absf(cam._height_of(z) - h):
				z = zz
		var pitch: float = cam._base_pitch_deg(z)
		var near: float = a.fit_shadows(h, pitch, cam.fov_deg)
		t.near(a.sun.directional_shadow_max_distance, expect[h] as float, 1.0, "fit_shadows at H %d" % int(h))
		t.near(near, maxf(2.0, 0.6 * h), 1e-4, "near plane 0.6 * H at %d" % int(h))
	t.near(a.sun.directional_shadow_split_1, 0.16, 1e-6, "split 1")
	t.near(a.sun.directional_shadow_split_2, 0.38, 1e-6, "split 2")
	t.near(a.sun.directional_shadow_split_3, 0.68, 1e-6, "split 3")
	cam.free()
	a.free()


func test_apply_mood_writes_globals(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	var a: ViewAtmosphere = _atmo()
	a.apply_mood(moods["temperate_day"] as ViewMoodDef)
	var dir: Vector3 = a.globals[&"atm_sun_dir"] as Vector3
	t.near(dir.length(), 1.0, 1e-4, "sun dir is a unit vector")
	t.near(asin(dir.y), deg_to_rad(40.0), 1e-3, "sun elevation 40 deg")
	t.near(a.sun.light_energy, 1.55, 1e-4, "sun energy")
	t.check((-a.sun.basis.z).dot(dir) < -0.999, "sun light points away from the sun direction")
	var sc: Vector3 = a.globals[&"atm_sun_color"] as Vector3
	t.gt(sc.x, sc.z, "warm temperate sun: red > blue")
	t.eq(a.globals[&"atm_night"], 0.0, "day: atm_night 0")
	var cloud: Vector4 = a.globals[&"atm_cloud"] as Vector4
	t.near(cloud.x, 0.12, 1e-4, "cloud strength from the mood")
	a.apply_mood(moods["urban_night"] as ViewMoodDef)
	t.eq(a.globals[&"atm_night"], 1.0, "night mood: atm_night 1")
	t.near(a.env.tonemap_exposure, (moods["urban_night"] as ViewMoodDef).exposure, 1e-4, "night exposure")
	t.check(a.env.adjustment_color_correction is GradientTexture1D, "grade LUT installed")
	a.set_night(0.4)
	t.near(a.globals[&"atm_night"] as float, 0.4, 1e-5, "set_night")
	a.free()


func test_moods_are_distinct(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	var seen: Dictionary = {}
	for id: String in MOOD_IDS:
		var m: ViewMoodDef = moods[id] as ViewMoodDef
		var key: String = "%s|%s|%.2f" % [m.sun_color.to_html(), m.sky_top.to_html(), m.sun_energy]
		t.check(not seen.has(key), "%s differs from the other moods" % id)
		seen[key] = true
	t.lt((moods["urban_night"] as ViewMoodDef).sky_top.get_luminance(), 0.1, "night sky is dark")
	t.gt((moods["temperate_day"] as ViewMoodDef).sky_top.get_luminance(), 0.2, "day sky is bright")


func test_lut_matches_formula(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	var m: ViewMoodDef = moods["temperate_day"] as ViewMoodDef
	var lut: GradientTexture1D = ViewAtmosphere.make_lut(m.grade(false))
	t.eq(lut.width, 256, "256 px LUT")
	var c0: Color = lut.gradient.get_color(0)
	var c1: Color = lut.gradient.get_color(lut.gradient.get_point_count() - 1)
	t.near(c0.r, m.lift.r, 1e-5, "x = 0 -> lift")
	t.near(c1.b, minf(m.gain.b, 1.0), 1e-5, "x = 1 -> gain")
	t.check(m.grade(true) != m.grade(false), "compat grade differs from the normal grade")


func test_apply_quality_low_has_no_shadow_maps(t: TestCtx) -> void:
	var a: ViewAtmosphere = _atmo()
	var qs: Dictionary = ViewQuality.load_presets()
	a.apply_quality(ViewQuality.create(qs, ViewQuality.Preset.LOW, ViewQuality.Renderer.FORWARD_PLUS))
	t.check(not a.sun.shadow_enabled, "LOW: blob shadows instead of shadow maps")
	t.check(not a.env.glow_enabled, "LOW: no glow")
	a.apply_quality(ViewQuality.create(qs, ViewQuality.Preset.MEDIUM, ViewQuality.Renderer.FORWARD_PLUS))
	t.check(a.sun.shadow_enabled, "MEDIUM: shadows on")
	t.eq(a.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "MEDIUM: 2 cascades")
	a.apply_quality(ViewQuality.create(qs, ViewQuality.Preset.HIGH, ViewQuality.Renderer.FORWARD_PLUS))
	t.eq(a.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "HIGH: 4 cascades")
	t.check(a.env.glow_enabled and a.env.ssao_enabled, "HIGH: glow and SSAO")
	a.free()


func _water_ter() -> ViewTerrain:
	var patch: Callable = func(md: MapData) -> void:
		Fx.paint(md, 20, 20, 40, 40, MapTerrain.T_DEEP)
		Fx.paint(md, 18, 20, 19, 40, MapTerrain.T_SHALLOW)
		md.water_level_u = 100
	var high: Callable = func(_cx: int, _cy: int) -> int: return 300
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(Fx.source(64, high, 0, 0, patch), 2, ViewDetailTextures.build(64), false, false)
	return ter


func test_water_plane_and_variants(t: TestCtx) -> void:
	var ter: ViewTerrain = _water_ter()
	var tex: ViewDetailTextures = ViewDetailTextures.build(64)
	var w: ViewWater = ViewWater.new()
	w.build(ter, tex, false)
	t.check(w.visible, "map with water: plane visible")
	t.near(w.plane.position.y, ter.src.sea_level_m, 1e-4, "plane at the sea level")
	t.near(w.plane.position.x, 96.0, 1e-3, "plane centred on the map")
	t.eq(w.material.render_priority, ViewLayers.PRIO_WATER, "render priority")
	t.eq(w.material.shader.code.find("\n#define WATER_LOW"), -1, "full variant has no define")
	w.apply_mood(ViewMoodDef.load_all()["arid_dusk"] as ViewMoodDef)
	t.eq(w.material.get_shader_parameter("absorb"), 0.5, "mood absorb applied")
	var low: ViewWater = ViewWater.new()
	low.build(ter, tex, true)
	t.check(low.material.shader.code.find("\n#define WATER_LOW") >= 0, "low variant defines WATER_LOW")
	var dry: ViewTerrain = ViewTerrain.new()
	dry.build(Fx.source(64), 2, tex, false, false)
	var w2: ViewWater = ViewWater.new()
	w2.build(dry, tex, false)
	t.check(not w2.visible, "map without water: no plane")
	for n: Node in [w, low, w2, ter, dry]:
		n.free()


func test_minimap_bake_and_mapping(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	var patch: Callable = func(md: MapData) -> void:
		Fx.paint(md, 10, 10, 20, 20, MapTerrain.T_ROCK)
		md.deposit_max[30 * 64 + 30] = 1000
		md.deposit_max[30 * 64 + 31] = 1000
	var src: ViewTerrainSource = Fx.source(64, Callable(), 0, 0, patch)
	var mm: ViewMinimapSource = ViewMinimapSource.new()
	var tex: ImageTexture = mm.bake(src, moods["temperate_day"] as ViewMoodDef)
	t.eq(tex.get_width(), 64, "one texel per cell (w)")
	t.eq(tex.get_height(), 64, "one texel per cell (h)")
	t.gt(mm.bake_ms, 0.0, "bake timed")
	t.note("64^2 minimap bake %.1f ms" % mm.bake_ms)
	var rock: Color = mm.texel(15, 15)
	var grass: Color = mm.texel(40, 15)
	t.check(rock.r > 0.0 and rock != grass, "rock and grass texels differ")
	t.gt(grass.g, grass.r, "grass texel is green")
	var gold: Color = mm.texel(30, 30)
	t.gt(gold.r, grass.r, "deposit texel is golden")
	t.eq(mm.world_to_uv(Vector3(96.0, 5.0, 48.0)), Vector2(0.5, 0.25), "world_to_uv")
	t.eq(mm.uv_to_world(Vector2(0.5, 0.25)), Vector3(96.0, 0.0, 48.0), "uv_to_world")
	t.eq(mm.make_material(true).get_shader_parameter("fow_enabled"), 1.0, "fog material")
	t.eq(mm.make_material(false).get_shader_parameter("fow_enabled"), 0.0, "no-fog material")


func test_minimap_deposit_depletion(t: TestCtx) -> void:
	var moods: Dictionary = ViewMoodDef.load_all()
	var patch: Callable = func(md: MapData) -> void: md.deposit_max[30 * 64 + 30] = 1000
	var map: MapData = Fx.map(64, Callable(), 0, 0, patch)
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var mm: ViewMinimapSource = ViewMinimapSource.new()
	mm.bake(src, moods["temperate_day"] as ViewMoodDef)
	var full: Color = mm.texel(30, 30)
	map.harvest_cell(30 * 64 + 30, 600)
	var cells: PackedInt32Array = PackedInt32Array()
	var n: int = src.drain_deposit_changes(cells)
	t.eq(n, 1, "one changed cell")
	mm.update_deposits(src, cells, n)
	var half: Color = mm.texel(30, 30)
	t.check(half != full, "half-depleted deposit is re-tinted")
	map.harvest_cell(30 * 64 + 30, 1000)
	n = src.drain_deposit_changes(cells)
	mm.update_deposits(src, cells, n)
	var empty: Color = mm.texel(30, 30)
	t.lt(empty.r, half.r, "empty deposit loses the gold")
	t.check(not mm.flush(0.1), "upload waits for the 2 Hz gate")
	t.check(mm.flush(0.5), "upload after 0.5 s")
	t.check(not mm.flush(1.0), "nothing pending")
