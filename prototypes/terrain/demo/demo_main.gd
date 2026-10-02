extends Node3D
## Terrain / water / atmosphere / fog-of-war / camera / decor / decals / minimap spike: demo + benchmark harness.
## Run:  Godot --path prototypes/terrain [--rendering-method forward_plus|mobile|gl_compatibility] [--disable-vsync]
##       [--resolution 1920x1080] -- mood=temperate|arid  views=lake,mesa  out=/abs/prefix_  fog=0|1  ui=0|1  bench=full|res|lite
## Interactive: WASD/arrows pan, Q/E rotate, wheel zoom, MMB orbit, F1 mood, F2 fog of war, F3 HUD/minimaps,
##              F4 scorch at cursor, F5 tonemapper, F6 SSAO, F7 shadows, F8 water.

const MAP_CELLS: int = 192
const MAP_SEED: int = 1337
const UNIT_POOL: int = 400

## name -> [focus cell, yaw deg, zoom 0..1, pitch bias deg]
const VIEWS: Dictionary = {
	"overview": [Vector2(96, 96), 0.0, 1.0, 0.0],
	"gameplay": [Vector2(92, 104), 15.0, 0.5, 0.0],
	"lake": [Vector2(76, 106), 28.0, 0.40, 0.0],
	"mesa": [Vector2(118, 127), -25.0, 0.42, 0.0],
	"salvage": [Vector2(100, 62), 0.0, 0.34, 0.0],
	"mountain": [Vector2(138, 66), 200.0, 0.5, 0.0],
	"base": [Vector2(48, 50), 10.0, 0.55, 0.0],
	"road": [Vector2(88, 82), 60.0, 0.30, 0.0],
	"coast": [Vector2(98, 172), 340.0, 0.5, 0.0],
	"fow": [Vector2(92, 104), 0.0, 0.85, 0.0],
	"far": [Vector2(96, 100), 15.0, 0.95, 0.0],
}

const DEFAULT_CFG: Dictionary = {
	"ssao": true, "ssao_q": 2, "ssao_half": true, "ssil": false, "glow": true, "fog": true, "vfog": false,
	"shadows": 2, "shadow_size": 4096, "shadow_filter": 4, "terrain_shadow": true, "decor_shadow": true, "unit_shadow": true,
	"msaa": 2, "taa": false, "saa": 0, "scale_mode": 0, "scale": 1.0,
	"decor": true, "water": true, "fow": true, "units": 150, "blob": false, "decals": 0, "terrain_low": false,
	"sky_process": 1, "minimap_sv": 0, "cloud": true, "tonemap": 3,
}

class Scout:
	extends RefCounted
	var center: Vector2
	var orbit: float
	var speed: float
	var phase: float
	var vision: int

var args: Dictionary = {}
var renderer: String = ""
var cfg: Dictionary = {}
var boot: Dictionary = {}

var map: MapTerrainData
var detail: ViewDetailTextures
var terrain: ViewTerrain
var water: ViewWater
var atmos: ViewAtmosphere
var fow: ViewFogOfWar
var cam: ViewRtsCamera
var decor: ViewDecor
var decals: ViewDecals
var scorch: ViewScorchLayer
var blobs: ViewBlobShadows
var minimap: ViewMinimap
var mood: ViewMoodDef
var hud: Label
var ui: CanvasLayer
var mm_cpu: TextureRect
var mm_sv: TextureRect
var units: Array[MeshInstance3D] = []
var unit_home: PackedVector2Array = PackedVector2Array()
var unit_mats: Array[ShaderMaterial] = []
var unit_shadows: bool = true

var _scouts: Array[Scout] = []
var _fog_states: PackedByteArray = PackedByteArray()
var _vis_list: PackedInt32Array = PackedInt32Array()
var _fog_t: float = 0.0
var _fog_timer: float = 0.0
var _fog_mark_us: int = 0
var _hud_timer: float = 0.0
var _anim_t: float = 0.0
var _mood_index: int = 0
var _tonemap_cycle: Array[int] = [Environment.TONE_MAPPER_ACES, Environment.TONE_MAPPER_FILMIC, Environment.TONE_MAPPER_AGX, Environment.TONE_MAPPER_REINHARDT]
var _bench_rows: PackedStringArray = PackedStringArray()
var _script_us: int = 0
var _script_frames: int = 0
var target_res: Vector2i = Vector2i.ZERO   ## logical benchmark resolution (3D render target), 0 = native window size


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	renderer = RenderingServer.get_current_rendering_method()
	cfg = DEFAULT_CFG.duplicate()
	_setup_resolution()
	ViewFogOfWar.register_globals()
	ViewAtmosphere.register_globals()
	_build_world()
	_apply_cfg(cfg)
	var automated: bool = args.has("views") or args.has("bench")
	cam.edge_scroll_enabled = not automated
	print("READY|renderer=%s|adapter=%s|window=%s|scale3d=%.3f|render3d=%s" % [renderer, RenderingServer.get_video_adapter_name(), get_window().size, get_viewport().scaling_3d_scale, Vector2(get_viewport().get_visible_rect().size) * get_viewport().scaling_3d_scale])
	for k in boot:
		print("BOOT|%s|%.1f ms" % [k, boot[k]])
	if args.has("views"):
		await _run_views(String(args["views"]).split(","), String(args.get("out", "/tmp/terrain_")))
	elif args.has("bench"):
		await _run_bench(String(args["bench"]))


## macOS clamps windows to the usable screen area, so an exact 1920x1080 / 2560x1440 window is impossible on a laptop
## panel. We keep a 16:9 window and render the 3D scene at `res` through Viewport.scaling_3d_scale (>1 = supersampled),
## so the 3D pass cost matches the requested resolution; the final blit to the window is a cheap bilinear resample.
func _setup_resolution() -> void:
	if not args.has("res"):
		return
	var r: PackedStringArray = String(args["res"]).split("x")
	target_res = Vector2i(int(r[0]), int(r[1]))
	var screen: Vector2i = DisplayServer.screen_get_usable_rect().size
	var w: int = mini(target_res.x, screen.x - 60)
	var h: int = w * target_res.y / target_res.x
	if h > screen.y - 90:
		h = screen.y - 90
		w = h * target_res.x / target_res.y
	get_window().size = Vector2i(w, h)


func _base_scale() -> float:
	if target_res == Vector2i.ZERO:
		return 1.0
	return float(target_res.x) / float(get_viewport().get_visible_rect().size.x)


func _stage(label: String, fn: Callable) -> void:
	var t0: int = Time.get_ticks_usec()
	fn.call()
	boot[label] = float(Time.get_ticks_usec() - t0) / 1000.0


func _build_world() -> void:
	_stage("map_gen (int noise)", func() -> void: map = MapTerrainGen.generate(MAP_SEED, MAP_CELLS, MAP_CELLS))
	_stage("detail_textures", func() -> void: detail = ViewDetailTextures.build(256))
	terrain = ViewTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var subdiv: int = int(args.get("subdiv", 2))
	_stage("terrain_build (threaded)", func() -> void: terrain.build(map, subdiv, not args.has("nothread")))
	for k in terrain.stats:
		boot["  terrain." + k] = float(terrain.stats[k])
	_stage("terrain_material", func() -> void: terrain.create_material(detail, false))
	water = ViewWater.new()
	water.name = "Water"
	add_child(water)
	_stage("water", func() -> void: water.build(terrain, detail))
	fow = ViewFogOfWar.new()
	fow.setup(MAP_CELLS, MAP_CELLS, Vector2.ZERO, MapTerrainData.CELL_M)
	_init_fog_sim()
	atmos = ViewAtmosphere.new()
	atmos.name = "Atmosphere"
	add_child(atmos)
	atmos.setup()
	decor = ViewDecor.new()
	decor.name = "Decor"
	add_child(decor)
	_stage("decor (place+multimesh)", func() -> void: decor.build(terrain, int(args.get("groups", 4))))
	scorch = ViewScorchLayer.new()
	scorch.setup(map.size_m(), 1024)
	terrain.set_scorch_texture(scorch.texture)
	decals = ViewDecals.new()
	decals.name = "Decals"
	add_child(decals)
	decals.setup(1100)
	blobs = ViewBlobShadows.new()
	blobs.name = "BlobShadows"
	add_child(blobs)
	blobs.setup(UNIT_POOL)
	_build_units()
	_scatter_marks()
	cam = ViewRtsCamera.new()
	cam.name = "RtsCamera"
	cam.map_rect = Rect2(Vector2.ZERO, map.size_m())
	cam.height_func = terrain.height_at
	cam.ground_pick_func = terrain.raycast
	cam.view_changed.connect(_on_view_changed)
	add_child(cam)
	minimap = ViewMinimap.new()
	mood = ViewMoodDef.arid_dusk() if String(args.get("mood", "temperate")) == "arid" else ViewMoodDef.temperate_day()
	_mood_index = 1 if mood.mood_name == "arid_dusk" else 0
	_apply_mood(mood)
	_stage("minimap_cpu_bake", func() -> void: minimap.bake_cpu(terrain, mood))
	_build_ui()
	_goto_view(String(args.get("view", "gameplay")))


func _apply_mood(m: ViewMoodDef) -> void:
	mood = m
	atmos.apply_mood(m)
	terrain.apply_mood(m)
	water.apply_mood(m)
	decor.apply_mood(m)
	if minimap.cpu_texture != null:
		minimap.bake_cpu(terrain, m)
		if mm_cpu != null:
			mm_cpu.texture = minimap.cpu_texture


func _on_view_changed(height: float, pitch_deg: float) -> void:
	atmos.fit_shadows(height, pitch_deg, cam.fov_deg, get_viewport().get_visible_rect().size.aspect())


func _goto_view(name: String) -> void:
	var v: Array = VIEWS.get(name, VIEWS["gameplay"])
	var focus_cells: Vector2 = v[0]
	if name == "overview":
		cam.height_max = 640.0
		cam.pitch_far_deg = 72.0
	else:
		cam.height_max = 84.0
		cam.pitch_far_deg = 61.0
	cam.snap_to(focus_cells * MapTerrainData.CELL_M, float(v[1]), float(v[2]), float(v[3]))


# ---------------------------------------------------------------- units, marks, fog sim

func _build_units() -> void:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	var body: BoxMesh = BoxMesh.new()
	body.size = Vector3(2.0, 0.8, 3.6)
	b.add(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), Color(0.19, 0.21, 0.16), 0.0, 0.0, 2.0, 0.0, 0.0, 1, 0.7)
	for sx in [-1.25, 1.25]:
		var track: BoxMesh = BoxMesh.new()
		track.size = Vector3(0.6, 0.8, 3.9)
		b.add(track, Transform3D(Basis.IDENTITY, Vector3(sx, 0.5, 0)), Color(0.14, 0.14, 0.15), 0.0, 0.0, 2.0, 0.0, 0.0, 2, 0.7)
	var turret: BoxMesh = BoxMesh.new()
	turret.size = Vector3(1.5, 0.6, 1.7)
	b.add(turret, Transform3D(Basis.IDENTITY, Vector3(0, 1.4, -0.2)), Color(1, 1, 1), 3.0, 0.0, 2.0, 0.0, 0.0, 3, 0.8)
	var barrel: CylinderMesh = CylinderMesh.new()
	barrel.top_radius = 0.11
	barrel.bottom_radius = 0.13
	barrel.height = 2.3
	barrel.radial_segments = 6
	b.add(barrel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.45, -1.6)), Color(0.2, 0.2, 0.21), 0.0, 0.0, 2.0, 0.0, 0.0, 4, 0.8)
	var mesh: ArrayMesh = b.build(true)
	var unit_shader: Shader = load("res://shaders/unit_demo.gdshader")
	var team_mats: Array[ShaderMaterial] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var teams: Array[Color] = [Color(0.9, 0.15, 0.1), Color(0.15, 0.4, 0.95), Color(0.95, 0.75, 0.1)]
	for k in 6:
		var um: ShaderMaterial = ShaderMaterial.new()
		um.shader = unit_shader
		um.set_shader_parameter("team_color", teams[k % 3])
		um.set_shader_parameter("hide_in_fog", 1.0 if k >= 3 else 0.0)
		team_mats.append(um)
		unit_mats.append(um)
	var made: int = 0
	var guard: int = 0
	while made < UNIT_POOL and guard < 20000:
		guard += 1
		var cx: float = rng.randf_range(84.0, 106.0) if made < 300 else rng.randf_range(20.0, 170.0)
		var cz: float = rng.randf_range(94.0, 118.0) if made < 300 else rng.randf_range(20.0, 170.0)
		var x: float = cx * MapTerrainData.CELL_M
		var z: float = cz * MapTerrainData.CELL_M
		if terrain.height_at(x, z) < 0.6 or terrain.normal_at(x, z).y < 0.9:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		var enemy: bool = made >= 300 and made % 2 == 0
		mi.material_override = team_mats[(made % 3) + (3 if enemy else 0)]
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		units.append(mi)
		unit_home.append(Vector2(x, z))
		made += 1


func _scatter_marks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		var p: Vector2 = Vector2(rng.randf_range(76.0, 112.0), rng.randf_range(90.0, 120.0)) * MapTerrainData.CELL_M
		scorch.paint(p, rng.randf_range(1.2, 3.8))
	scorch.flush()


func _init_fog_sim() -> void:
	_fog_states.resize(MAP_CELLS * MAP_CELLS)
	_fog_states.fill(0)
	for cy in MAP_CELLS:
		for cx in MAP_CELLS:
			if Vector2(cx, cy).distance_to(Vector2(96.0, 96.0)) < 92.0:
				_fog_states[cy * MAP_CELLS + cx] = 1
	var defs: Array[Array] = [[Vector2(46, 46), 0.0, 0.0, 0.0, 17], [Vector2(92, 104), 12.0, 0.22, 0.0, 12], [Vector2(130, 118), 9.0, -0.27, 2.0, 13], [Vector2(100, 64), 11.0, 0.3, 4.0, 11], [Vector2(70, 130), 8.0, -0.2, 1.0, 10]]
	for d in defs:
		var s: Scout = Scout.new()
		s.center = d[0]
		s.orbit = d[1]
		s.speed = d[2]
		s.phase = d[3]
		s.vision = d[4]
		_scouts.append(s)
	_update_fog()


func _update_fog() -> void:
	var t0: int = Time.get_ticks_usec()
	for idx in _vis_list:
		_fog_states[idx] = 1
	_vis_list.clear()
	for s in _scouts:
		var p: Vector2 = s.center + Vector2(cos(_fog_t * s.speed + s.phase), sin(_fog_t * s.speed + s.phase)) * s.orbit
		var r: int = s.vision
		for y in range(maxi(0, int(p.y) - r), mini(MAP_CELLS, int(p.y) + r + 1)):
			var dy: float = float(y) + 0.5 - p.y
			var half: int = int(sqrt(maxf(0.0, float(r * r) - dy * dy)))
			for x in range(maxi(0, int(p.x) - half), mini(MAP_CELLS, int(p.x) + half + 1)):
				var idx: int = y * MAP_CELLS + x
				_fog_states[idx] = 2
				_vis_list.append(idx)
	_fog_mark_us = Time.get_ticks_usec() - t0
	fow.submit(_fog_states)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hud.add_theme_constant_override("outline_size", 5)
	ui.add_child(hud)
	mm_cpu = ViewMinimap.make_rect(minimap.cpu_texture, Vector2(240, 240), map.size_m())
	ui.add_child(mm_cpu)
	var sv: SubViewport = minimap.make_viewport(self, map.size_m(), 512)
	mm_sv = ViewMinimap.make_rect(sv.get_texture(), Vector2(240, 240), map.size_m())
	ui.add_child(mm_sv)
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)
	var show_ui: bool = String(args.get("ui", "0")) == "1" or not (args.has("views") or args.has("bench"))
	ui.visible = show_ui


func _layout_ui() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	mm_cpu.size = Vector2(240, 240)
	mm_sv.size = Vector2(240, 240)
	mm_cpu.position = Vector2(vs.x - 252.0, 12.0)
	mm_sv.position = Vector2(vs.x - 252.0, 264.0)


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F1:
			_mood_index = 1 - _mood_index
			_apply_mood(ViewMoodDef.arid_dusk() if _mood_index == 1 else ViewMoodDef.temperate_day())
		KEY_F2:
			cfg["fow"] = not cfg["fow"]
			_apply_cfg(cfg)
		KEY_F3:
			ui.visible = not ui.visible
		KEY_F4:
			var hit: Vector3 = cam.screen_to_ground(get_viewport().get_mouse_position())
			if hit != Vector3.INF:
				scorch.paint(Vector2(hit.x, hit.z), 4.0)
				scorch.flush()
		KEY_F5:
			var i: int = (_tonemap_cycle.find(atmos.tonemapper) + 1) % _tonemap_cycle.size()
			atmos.set_tonemapper(_tonemap_cycle[i])
		KEY_F6:
			cfg["ssao"] = not cfg["ssao"]
			_apply_cfg(cfg)
		KEY_F7:
			cfg["shadows"] = 0 if int(cfg["shadows"]) > 0 else 2
			_apply_cfg(cfg)
		KEY_F8:
			cfg["water"] = not cfg["water"]
			_apply_cfg(cfg)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var t_script: int = Time.get_ticks_usec()
	_fog_t += delta
	_anim_t += delta
	fow.advance(delta)
	_fog_timer += delta
	if _fog_timer >= fow.update_interval:
		_fog_timer -= fow.update_interval
		_update_fog()
	var n_units: int = int(cfg["units"])
	var pos: PackedVector3Array = PackedVector3Array()
	for i in n_units:
		var home: Vector2 = unit_home[i]
		var a: float = _anim_t * 0.35 + float(i)
		var x: float = home.x + cos(a) * 3.0
		var z: float = home.y + sin(a) * 3.0
		var g: Vector3 = Vector3(x, terrain.height_at(x, z), z)
		units[i].position = g
		units[i].rotation.y = -a - PI * 0.5
		pos.append(g)
	if cfg["blob"]:
		var radii: PackedFloat32Array = PackedFloat32Array()
		radii.resize(n_units)
		radii.fill(2.4)
		blobs.update(terrain, pos, radii)
	_script_us += Time.get_ticks_usec() - t_script
	_script_frames += 1
	_hud_timer += delta
	if _hud_timer > 0.25 and hud != null and ui.visible:
		_hud_timer = 0.0
		var rid: RID = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		hud.text = "%s | %.0f fps %.2f ms | gpu %.2f cpu %.2f | draws %d objs %d tris %.2fM vram %.0f MB | fog upload %d us, mark %d us | %s" % [
			renderer, Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			RenderingServer.viewport_get_measured_render_time_gpu(rid), RenderingServer.viewport_get_measured_render_time_cpu(rid),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			fow.last_upload_us, _fog_mark_us, mood.mood_name]


# ---------------------------------------------------------------- config

func _apply_cfg(c: Dictionary) -> void:
	var vp: Viewport = get_viewport()
	atmos.set_ssao(c["ssao"])
	RenderingServer.environment_set_ssao_quality(int(c["ssao_q"]) as RenderingServer.EnvironmentSSAOQuality, c["ssao_half"], 0.5, 2, 60.0, 400.0)
	atmos.set_ssil(c["ssil"])
	atmos.set_glow(c["glow"])
	atmos.set_fog(c["fog"])
	atmos.set_volumetric_fog(c["vfog"])
	atmos.set_shadow_cascades(int(c["shadows"]))
	RenderingServer.directional_shadow_atlas_set_size(int(c["shadow_size"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(c["shadow_filter"]) as RenderingServer.ShadowQuality)
	terrain.set_shadow_casting(c["terrain_shadow"] and int(c["shadows"]) > 0)
	decor.set_shadows(c["decor_shadow"] and int(c["shadows"]) > 0)
	unit_shadows = c["unit_shadow"] and int(c["shadows"]) > 0
	vp.msaa_3d = int(c["msaa"]) as Viewport.MSAA
	vp.use_taa = c["taa"]
	vp.screen_space_aa = int(c["saa"]) as Viewport.ScreenSpaceAA
	vp.scaling_3d_mode = int(c["scale_mode"]) as Viewport.Scaling3DMode
	vp.scaling_3d_scale = float(c["scale"]) * _base_scale()
	decor.set_visible_decor(c["decor"])
	water.visible = c["water"]
	var fow_on: float = 1.0 if c["fow"] else 0.0
	terrain.material.set_shader_parameter("fow_enabled", fow_on)
	terrain.material.set_shader_parameter("cloud_enabled", 1.0 if c["cloud"] else 0.0)
	water.material.set_shader_parameter("fow_enabled", fow_on)
	decor.material.set_shader_parameter("fow_enabled", fow_on)
	for um in unit_mats:
		um.set_shader_parameter("fow_enabled", fow_on)
	var n_units: int = int(c["units"])
	for i in units.size():
		units[i].visible = i < n_units
		units[i].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if unit_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blobs.visible = c["blob"]
	_set_decal_count(int(c["decals"]))
	atmos.sky.process_mode = int(c["sky_process"]) as Sky.ProcessMode
	atmos.set_tonemapper(int(c["tonemap"]))
	if minimap.viewport != null:
		var mode: int = int(c["minimap_sv"])
		minimap.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if mode == 2 else (SubViewport.UPDATE_ONCE if mode == 1 else SubViewport.UPDATE_DISABLED)
	if bool(c["terrain_low"]) != (terrain.material.shader.code.find("TERRAIN_LOW") >= 0):
		var m: ShaderMaterial = terrain.create_material(detail, bool(c["terrain_low"]))
		terrain.apply_mood(mood)
		terrain.set_scorch_texture(scorch.texture)
		m.set_shader_parameter("fow_enabled", fow_on)


func _set_decal_count(n: int) -> void:
	if decals.pool.size() < n:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 5
		while decals.pool.size() < n:
			var p: Vector2 = Vector2(rng.randf_range(78.0, 108.0), rng.randf_range(90.0, 120.0)) * MapTerrainData.CELL_M
			decals.add(Vector3(p.x, terrain.height_at(p.x, p.y), p.y), rng.randf_range(1.6, 4.5), rng.randf() * TAU)
	for i in decals.pool.size():
		decals.pool[i].visible = i < n


# ---------------------------------------------------------------- automation

func _run_views(names: PackedStringArray, prefix: String) -> void:
	if args.has("apply"):
		for kv in String(args["apply"]).split(","):
			var p: PackedStringArray = kv.split(":")
			var cur: Variant = cfg[p[0]]
			cfg[p[0]] = (p[1] == "1" or p[1] == "true") if cur is bool else (float(p[1]) if cur is float else int(p[1]))
	if args.has("fog"):
		cfg["fow"] = String(args["fog"]) == "1"
	else:
		cfg["fow"] = false
	_apply_cfg(cfg)
	if args.has("scorch"):
		terrain.set_scorch_texture(scorch.texture)
	minimap.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for n in names:
		_goto_view(n)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(prefix + n + ".png")
		print("SHOT|%s|%dx%d" % [prefix + n + ".png", img.get_width(), img.get_height()])
	get_tree().quit()


## Frame pacing is locked to the display (120 Hz ProMotion: every config reads 8.33 ms, --disable-vsync is ignored by the
## Metal layer) and viewport GPU timestamps read 0 on Metal, so we measure render THROUGHPUT: RenderingServer.force_draw()
## renders all viewports without presenting, back to back. Script cost of the demo's own per-frame logic is timed separately.
func _measure(label: String, frames: int, warm: int) -> Dictionary:
	for i in warm:
		await get_tree().process_frame
	_script_us = 0
	_script_frames = 0
	for i in 12:
		await get_tree().process_frame
	var script_ms: float = float(_script_us) / float(maxi(1, _script_frames)) / 1000.0
	var t_warm: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_warm < 600:
		RenderingServer.force_draw(false, 0.0)
	var samples: PackedFloat32Array = PackedFloat32Array()
	var t_all: int = Time.get_ticks_usec()
	for i in frames:
		var t0: int = Time.get_ticks_usec()
		RenderingServer.force_draw(false, 0.0)
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var avg: float = float(Time.get_ticks_usec() - t_all) / 1000.0 / float(frames)
	samples.sort()
	return {"name": label, "res": str(Vector2i(Vector2(get_viewport().get_visible_rect().size) * get_viewport().scaling_3d_scale)),
		"avg": avg, "p50": samples[frames / 2], "p95": samples[int(frames * 0.95)], "script": script_ms,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), "objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), "vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}


func _row(r: Dictionary) -> String:
	return "BENCH|%s|%s|%s|p50=%.2f|avg=%.2f|p95=%.2f|script=%.2f|draws=%d|objs=%d|Mprims=%.2f|vram=%.0f" % [
		renderer, r["res"], r["name"], r["p50"], r["avg"], r["p95"], r["script"], r["draws"], r["objs"], float(r["prims"]) / 1.0e6, r["vram"]]


func _bench_matrix(kind: String) -> Array[Array]:
	var m: Array[Array] = []
	m.append(["full", {}])
	if kind == "one":
		return m
	if kind == "lite":
		m.append(["low_preset", {"shadows": 0, "ssao": false, "glow": false, "msaa": 0, "terrain_low": true, "blob": true, "fog": true}])
		m.append(["med_preset", {"shadows": 1, "shadow_size": 2048, "ssao": true, "ssao_q": 1, "msaa": 0, "saa": 1, "terrain_shadow": false}])
		m.append(["shadows_off", {"shadows": 0}])
		m.append(["water_off", {"water": false}])
		m.append(["decor_off", {"decor": false}])
		m.append(["fow_off", {"fow": false}])
		m.append(["terrain_low", {"terrain_low": true}])
		m.append(["no_glow", {"glow": false}])
		m.append(["msaa_off", {"msaa": 0}])
		m.append(["msaa_8x", {"msaa": 3}])
		m.append(["blob_instead_of_shadows", {"shadows": 0, "blob": true}])
		m.append(["decals_256", {"decals": 256}])
		m.append(["units_400", {"units": 400}])
		return m
	m.append(["no_ssao", {"ssao": false}])
	m.append(["ssao_high_full", {"ssao_q": 3, "ssao_half": false}])
	m.append(["ssao_verylow", {"ssao_q": 0}])
	m.append(["ssil", {"ssil": true}])
	m.append(["no_glow", {"glow": false}])
	m.append(["no_env_fog", {"fog": false}])
	m.append(["volumetric_fog", {"vfog": true}])
	m.append(["shadows_off", {"shadows": 0}])
	m.append(["shadows_2casc", {"shadows": 1}])
	m.append(["shadow_2048", {"shadow_size": 2048}])
	m.append(["shadow_8192", {"shadow_size": 8192}])
	m.append(["shadow_filter_hard", {"shadow_filter": 0}])
	m.append(["shadow_filter_ultra", {"shadow_filter": 5}])
	m.append(["terrain_no_shadow", {"terrain_shadow": false}])
	m.append(["decor_no_shadow", {"decor_shadow": false}])
	m.append(["unit_no_shadow", {"unit_shadow": false}])
	m.append(["decor_off", {"decor": false}])
	m.append(["water_off", {"water": false}])
	m.append(["fow_off", {"fow": false}])
	m.append(["cloud_off", {"cloud": false}])
	m.append(["terrain_low", {"terrain_low": true}])
	m.append(["msaa_off", {"msaa": 0}])
	m.append(["msaa_2x", {"msaa": 1}])
	m.append(["msaa_8x", {"msaa": 3}])
	m.append(["taa", {"msaa": 0, "taa": true}])
	m.append(["fxaa", {"msaa": 0, "saa": 1}])
	m.append(["smaa", {"msaa": 0, "saa": 2}])
	for sm in [[0, "bilinear"], [1, "fsr1"], [2, "fsr2"], [3, "metalfx_spatial"], [4, "metalfx_temporal"]]:
		m.append(["scale067_" + String(sm[1]), {"scale_mode": sm[0], "scale": 0.67}])
	m.append(["units_0", {"units": 0}])
	m.append(["units_400", {"units": 400}])
	m.append(["blob_instead_of_shadows", {"shadows": 0, "blob": true}])
	m.append(["decals_64", {"decals": 64}])
	m.append(["decals_256", {"decals": 256}])
	m.append(["decals_512", {"decals": 512}])
	m.append(["decals_1024", {"decals": 1024}])
	m.append(["minimap_sv_always", {"minimap_sv": 2}])
	m.append(["sky_automatic", {"sky_process": 0}])
	m.append(["tonemap_agx", {"tonemap": Environment.TONE_MAPPER_AGX}])
	m.append(["low_preset", {"shadows": 0, "ssao": false, "glow": false, "msaa": 0, "terrain_low": true, "blob": true}])
	m.append(["med_preset", {"shadows": 1, "shadow_size": 2048, "ssao": true, "ssao_q": 1, "msaa": 0, "saa": 1, "terrain_shadow": false}])
	m.append(["ultra_preset", {"ssil": true, "ssao_q": 3, "ssao_half": false, "shadow_size": 8192, "shadow_filter": 5, "msaa": 3, "units": 400}])
	if kind == "res":
		var keep: PackedStringArray = ["full", "low_preset", "med_preset", "ultra_preset", "shadows_off", "no_ssao", "msaa_off", "taa", "fxaa", "smaa", "water_off", "decor_off"]
		var out: Array[Array] = []
		for e in m:
			if keep.has(String(e[0])):
				out.append(e)
		return out
	return m


func _run_bench(kind: String) -> void:
	_goto_view("gameplay")
	minimap.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var frames: int = int(args.get("frames", 150))
	if kind == "micro":
		await _run_micro()
		get_tree().quit()
		return
	if kind == "groups":
		for g in [1, 2, 4, 6, 8, 12]:
			decor.regroup(g)
			_apply_cfg(cfg)
			var r: Dictionary = await _measure("decor_groups_%d(multimeshes=%d)" % [g, decor.multimesh_count], frames, 20)
			print(_row(r))
		get_tree().quit()
		return
	var matrix: Array[Array] = _bench_matrix(kind)
	cfg = DEFAULT_CFG.duplicate()
	_apply_cfg(cfg)
	for i in 20:
		await get_tree().process_frame
	var t_warm: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_warm < 3500:
		RenderingServer.force_draw(false, 0.0)
	var best: Dictionary = {}
	var passes: int = int(args.get("passes", 2))
	for pass_i in passes:
		for entry in matrix:
			var c: Dictionary = DEFAULT_CFG.duplicate()
			var over: Dictionary = entry[1]
			for k in over:
				c[k] = over[k]
			cfg = c
			_apply_cfg(cfg)
			var r: Dictionary = await _measure(String(entry[0]), frames, 16)
			if not best.has(r["name"]) or float(r["p50"]) < float(best[r["name"]]["p50"]):
				best[r["name"]] = r
	for entry in matrix:
		print(_row(best[String(entry[0])]))
	print("BENCH_DONE|%d rows x %d passes (min of p50 per config)" % [matrix.size(), passes])
	get_tree().quit()


func _run_micro() -> void:
	var t0: int = Time.get_ticks_usec()
	for i in 2000:
		terrain.raycast(Vector3(288.0 + float(i) * 0.05, 60.0, 400.0), Vector3(0.3, -0.8, -0.5).normalized())
	print("MICRO|terrain.raycast (camera ray vs heightfield)|%.1f us/call" % (float(Time.get_ticks_usec() - t0) / 2000.0))
	t0 = Time.get_ticks_usec()
	var acc: float = 0.0
	for i in 100000:
		acc += terrain.height_at(float(i % 570), float((i * 7) % 570))
	print("MICRO|terrain.height_at (bilinear)|%.2f us/call" % (float(Time.get_ticks_usec() - t0) / 100000.0))
	t0 = Time.get_ticks_usec()
	for i in 200:
		fow.submit(_fog_states)
	print("MICRO|fog submit 192x192 R8 (set_data+ImageTexture.update)|%.1f us/upload (last %d us)" % [float(Time.get_ticks_usec() - t0) / 200.0, fow.last_upload_us])
	await get_tree().process_frame
	t0 = Time.get_ticks_usec()
	for i in 500:
		scorch.paint(Vector2(300.0 + float(i % 40) * 3.0, 300.0 + float(i / 40) * 3.0), 1.5 + float(i % 4))
	print("MICRO|scorch.paint (blend_rect stamp)|%.1f us/mark" % (float(Time.get_ticks_usec() - t0) / 500.0))
	scorch.paint(Vector2(100, 100), 3.0)
	scorch.flush()
	print("MICRO|scorch layer upload 1024x1024 RGBA8 (4 MB)|%d us" % scorch.last_flush_us)
	var pos: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i in UNIT_POOL:
		pos.append(Vector3(units[i].position.x, 0.0, units[i].position.z))
		radii.append(2.4)
	blobs.update(terrain, pos, radii)
	blobs.update(terrain, pos, radii)
	print("MICRO|blob shadows update, %d units|%d us" % [UNIT_POOL, blobs.last_update_us])
	_update_fog()
	print("MICRO|fog mark (5 scouts, ~1.4k cells) GDScript|%d us" % _fog_mark_us)
	var t1: int = Time.get_ticks_usec()
	minimap.bake_cpu(terrain, mood)
	print("MICRO|minimap CPU bake 192x192 GDScript|%.1f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	for g in [1, 4, 8]:
		var t2: int = Time.get_ticks_usec()
		decor.regroup(g)
		print("MICRO|decor regroup g=%d (%d multimeshes, %d instances)|%.1f ms" % [g, decor.multimesh_count, decor.total_instances(), float(Time.get_ticks_usec() - t2) / 1000.0])
	print("MICRO|decor triangles per model broadleaf/conifer/rock/crystal/scrap|%s" % str(decor.mesh_tris))
	for combo in [[2, true], [2, false], [1, true], [3, true], [4, true]]:
		terrain.build(map, combo[0], combo[1])
		print("MICRO|terrain.build subdiv=%d threaded=%s|heights %.0f ms, chunks %.0f ms, meshes %.0f ms, textures %.0f ms, %d verts, %d tris" % [
			combo[0], str(combo[1]), terrain.stats["height_ms"], terrain.stats["chunk_ms"], terrain.stats["mesh_ms"], terrain.stats["tex_ms"], terrain.stats["vertices"], terrain.stats["triangles"]])
	print("MICRO_DONE")
