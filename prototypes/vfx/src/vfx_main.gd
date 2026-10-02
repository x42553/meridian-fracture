extends Node3D
## Test arena and drivers for the VFX spike. NOT part of the reusable system (that is FxManager/FxRecipes/...).
##
## godot --path prototypes/vfx [--rendering-method mobile|gl_compatibility] [--fixed-fps 60] -- --mode=<m> [opts]
##   --mode=sheet --sheet=N        contact sheet N (6 effects x 3 time offsets) -> out/sheet_N.png
##   --mode=chaos [--secs=20]      200 shots/s + 20 explosions/s stress, prints RESULT| json line
##   --mode=hitch [--prewarm=1]    first-spawn hitch test (worst frame per effect)
##   --mode=bench                  particle strategy comparison (VfxBench)
##   --mode=play                   interactive: 1..9/0 spawn effects at the mouse, mouse wheel = zoom
##   --quality=low|medium|high|ultra   --tag=<text> (suffix for output file names)

const CW: int = 480
const CH: int = 270

var fx: FxManager
var cam: Camera3D
var _args: Dictionary = {}
var _label: Label
var _shake: float = 0.0
var _shake_enabled: bool = true
var _cam_look: Vector3 = Vector3.ZERO
var _cam_dist: float = 60.0
var _props: Array[Node3D] = []
var _mover: Node3D
var _mover_from: Vector3 = Vector3.ZERO
var _mover_to: Vector3 = Vector3.ZERO
var _mover_dur: float = 1.0
var _mover_t0: float = 0.0
var _mover_hide_at_end: bool = false
var _scenery: Array[Node3D] = []

# chaos state
var _chaos_on: bool = false
var _carry: Dictionary = {}
var _dust_units: Array[Node3D] = []
var _dust_dir: Array[Vector3] = []
var _samples: Dictionary = {"dt": [], "gpu": [], "cpu": [], "proc": [], "draws": [], "objs": [], "prims": []}
var _record: bool = false
var _hitch_max: float = 0.0
var _play_index: int = 0


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_arena()
	fx = FxManager.new()
	add_child(fx)
	fx.setup(cam, _quality_from_args())
	fx.camera_shake.connect(_on_camera_shake)
	for hn in String(_args.get("hide", "")).split(","):
		if hn != "":
			fx.hidden_batches[StringName(hn)] = true
	_build_hud()
	var mode: String = _args.get("mode", "play")
	match mode:
		"sheet":
			_run_sheet()
		"chaos":
			_run_chaos()
		"hitch":
			_run_hitch()
		"bench":
			_run_bench()
		_:
			_run_play()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _quality_from_args() -> FxManager.Quality:
	match String(_args.get("quality", "high")):
		"low":
			return FxManager.Quality.LOW
		"medium":
			return FxManager.Quality.MEDIUM
		"ultra":
			return FxManager.Quality.ULTRA
	return FxManager.Quality.HIGH


func _out_path(file: String) -> String:
	var dir: String = ProjectSettings.globalize_path("res://out/")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir + file


func _on_camera_shake(amount: float, _pos: Vector3) -> void:
	_shake = minf(1.0, _shake + amount)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		var k: float = _shake * _shake * 0.9 if _shake_enabled else 0.0
		cam.h_offset = randf_range(-1.0, 1.0) * k
		cam.v_offset = randf_range(-1.0, 1.0) * k
	if _mover != null:
		var t: float = clampf((fx.now() - _mover_t0) / _mover_dur, 0.0, 1.0)
		_mover.global_position = _mover_from.lerp(_mover_to, t)
		if t >= 1.0 and _mover_hide_at_end:
			_mover.visible = false
	if _chaos_on:
		_chaos_step(delta)
	if _record:
		_sample_frame(delta)
	_hitch_max = maxf(_hitch_max, delta)

# ------------------------------------------------------------------ arena

func _build_arena() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.44, 0.74)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.84)
	sky_mat.ground_horizon_color = Color(0.66, 0.70, 0.72)
	sky_mat.ground_bottom_color = Color(0.30, 0.30, 0.30)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = _args.get("noglow", "0") != "1"
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 3.0
	env.glow_hdr_scale = 1.4
	var levels: Array[float] = [0.6, 1.0, 1.0, 0.8, 0.5, 0.25, 0.0]
	for i in 7:
		env.set_glow_level(i, levels[i])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700.0, 700.0)
	ground.mesh = plane
	var gmat := ShaderMaterial.new()
	gmat.shader = FxAssets.shader_from("arena_ground")
	gmat.set_shader_parameter(&"noise_tex", FxAssets.noise_atlas())
	ground.material_override = gmat
	add_child(ground)

	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(46.0, 30.0)
	water.mesh = wp
	water.position = Vector3(30.0, 0.05, 0.0)
	var wmat := ShaderMaterial.new()
	wmat.shader = FxAssets.shader_from("arena_water")
	wmat.set_shader_parameter(&"noise_tex", FxAssets.noise_atlas())
	water.material_override = wmat
	add_child(water)

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.5
	cam.far = 1500.0
	add_child(cam)
	_place_camera(Vector3.ZERO, 60.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 46:
		var ang: float = rng.randf() * TAU
		var rad: float = rng.randf_range(52.0, 150.0)
		var t := _make_tree(rng.randf_range(0.8, 1.6))
		t.position = Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		add_child(t)
		_scenery.append(t)
	for i in 6:
		var b := _make_building()
		var ang: float = float(i) / 6.0 * TAU + 0.4
		b.position = Vector3(cos(ang) * 68.0, 0.0, sin(ang) * 64.0)
		b.rotation.y = rng.randf() * TAU
		add_child(b)
		_scenery.append(b)
	for i in 10:
		var tk := _make_tank(Color(0.28, 0.33, 0.2) if i % 2 == 0 else Color(0.3, 0.3, 0.34))
		var ang: float = float(i) / 10.0 * TAU + 0.2
		tk.position = Vector3(cos(ang) * 58.0, 0.0, sin(ang) * 58.0)
		tk.rotation.y = rng.randf() * TAU
		add_child(tk)
		_scenery.append(tk)


func _place_camera(look: Vector3, dist: float, pitch_deg: float = 52.0, yaw_deg: float = 20.0) -> void:
	_cam_look = look
	_cam_dist = dist
	var pitch: float = deg_to_rad(pitch_deg)
	var yaw: float = deg_to_rad(yaw_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.global_position = look + dir * dist
	cam.look_at(look, Vector3.UP)
	cam.h_offset = 0.0
	cam.v_offset = 0.0


func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _make_tank(color: Color) -> Node3D:
	var n := Node3D.new()
	_box(Vector3(3.2, 1.0, 5.4), Vector3(0.0, 0.75, 0.0), color, n)
	_box(Vector3(2.2, 0.75, 2.6), Vector3(0.0, 1.6, 0.3), color.lightened(0.08), n)
	var barrel := _box(Vector3(0.28, 0.28, 3.6), Vector3(0.0, 1.65, -2.0), color.darkened(0.25), n)
	barrel.name = "Barrel"
	for x in [-1.75, 1.75]:
		_box(Vector3(0.6, 0.7, 5.6), Vector3(x, 0.4, 0.0), Color(0.09, 0.09, 0.1), n)
	return n


func _make_building() -> Node3D:
	var n := Node3D.new()
	_box(Vector3(10.0, 7.0, 10.0), Vector3(0.0, 3.5, 0.0), Color(0.55, 0.57, 0.6), n)
	_box(Vector3(10.4, 0.5, 10.4), Vector3(0.0, 7.2, 0.0), Color(0.3, 0.3, 0.33), n)
	_box(Vector3(9.0, 0.6, 0.15), Vector3(0.0, 4.5, 5.05), Color(0.9, 0.75, 0.4), n, true)
	_box(Vector3(9.0, 0.6, 0.15), Vector3(0.0, 2.2, 5.05), Color(0.9, 0.75, 0.4), n, true)
	return n


func _make_tree(scale_f: float) -> Node3D:
	var n := Node3D.new()
	_box(Vector3(0.5, 2.4, 0.5), Vector3(0.0, 1.2, 0.0), Color(0.25, 0.17, 0.1), n)
	var crown := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 2.0
	cm.height = 5.5
	crown.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.26, 0.1)
	mat.roughness = 1.0
	crown.material_override = mat
	crown.position = Vector3(0.0, 4.6, 0.0)
	n.add_child(crown)
	n.scale = Vector3.ONE * scale_f
	return n


func _make_plane() -> Node3D:
	var n := Node3D.new()
	_box(Vector3(1.2, 1.0, 9.0), Vector3.ZERO, Color(0.55, 0.58, 0.62), n)
	_box(Vector3(9.0, 0.18, 2.4), Vector3(0.0, 0.0, 0.5), Color(0.5, 0.53, 0.58), n)
	_box(Vector3(3.0, 0.18, 1.4), Vector3(0.0, 0.2, 3.8), Color(0.5, 0.53, 0.58), n)
	return n


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _clear_props() -> void:
	for p in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	_mover = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# ------------------------------------------------------------------ contact sheets

func _sheet_table() -> Array[Dictionary]:
	var t: Array[Dictionary] = []
	t.append({"id": &"rifle_shot", "a": Vector3(-10, 1.3, 0), "b": Vector3(10, 1.0, -2), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 24.0, "times": [0.04, 0.09, 0.2]})
	t.append({"id": &"mg_burst", "a": Vector3(-10, 1.3, 2), "b": Vector3(10, 0.8, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 24.0, "times": [0.12, 0.25, 0.5]})
	t.append({"id": &"cannon_shot", "a": Vector3(-14, 1.6, 0), "b": Vector3(14, 0, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 34.0, "times": [0.06, 0.24, 0.6]})
	t.append({"id": &"cannon_impact", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1, 0), "dist": 20.0, "times": [0.1, 0.4, 1.3]})
	t.append({"id": &"missile_launch", "a": Vector3(-18, 1.5, 0), "b": Vector3(18, 0.5, -4), "s": 1.0, "look": Vector3(0, 2, -2), "dist": 46.0, "times": [0.3, 0.72, 1.6]})
	t.append({"id": &"artillery_shell", "a": Vector3(-32, 1.5, 4), "b": Vector3(28, 0, -6), "s": 1.0, "look": Vector3(-2, 6, -1), "dist": 84.0, "times": [0.12, 1.2, 2.3]})
	t.append({"id": &"explosion_large", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 3, 0), "dist": 52.0, "times": [0.12, 0.5, 1.7]})
	t.append({"id": &"beam_thermal", "a": Vector3(-16, 2.5, 0), "b": Vector3(16, 0, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 40.0, "times": [0.3, 0.9, 1.7]})
	t.append({"id": &"beam_rail", "a": Vector3(-16, 2.5, 0), "b": Vector3(16, 0.5, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 40.0, "times": [0.04, 0.14, 0.4]})
	t.append({"id": &"emp_pulse", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 10.0, "look": Vector3(0, 0.5, 0), "dist": 38.0, "times": [0.12, 0.45, 0.95], "prop": "tanks"})
	t.append({"id": &"vehicle_destroy", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1, 0), "dist": 28.0, "times": [0.12, 0.7, 3.0], "prop": "tank_destroy"})
	t.append({"id": &"building_collapse", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 3, 0), "dist": 58.0, "times": [0.35, 1.1, 3.2], "prop": "building_collapse"})
	t.append({"id": &"infantry_hit", "a": Vector3(0, 1.0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.8, 0), "dist": 10.0, "times": [0.05, 0.15, 0.4]})
	t.append({"id": &"aircraft_contrail", "a": Vector3(0, 22, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 12, 0), "dist": 105.0, "times": [0.7, 1.4, 2.4], "prop": "plane_line"})
	t.append({"id": &"aircraft_crash", "a": Vector3(-30, 40, 0), "b": Vector3(15, 0, -5), "s": 1.0, "look": Vector3(-6, 12, -2), "dist": 88.0, "times": [0.5, 1.3, 2.4], "prop": "plane_crash"})
	t.append({"id": &"impact_ground", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.4, 0), "dist": 8.0, "times": [0.04, 0.15, 0.4]})
	t.append({"id": &"impact_water", "a": Vector3(30, 0.05, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(30, 0.6, 0), "dist": 12.0, "times": [0.12, 0.4, 1.0]})
	t.append({"id": &"vehicle_dust", "a": Vector3.ZERO, "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.5, 0), "dist": 42.0, "times": [0.9, 1.8, 3.0], "prop": "tank_move"})
	t.append({"id": &"construction_sparks", "a": Vector3(0, 1.2, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1.0, 0), "dist": 9.0, "times": [0.3, 0.9, 1.8], "prop": "welder"})
	t.append({"id": &"sw_warning_marker", "a": Vector3(0, 0, 0), "b": Vector3(10, 0, 0), "s": 12.0, "look": Vector3(0, 6, 0), "dist": 58.0, "times": [0.5, 5.0, 9.5], "prop": "tanks"})
	t.append({"id": &"sw_orbital_strike", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 8, 0), "dist": 82.0, "times": [0.17, 0.5, 1.3]})
	t.append({"id": &"sw_shockwave", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 2, 0), "dist": 112.0, "times": [0.15, 0.6, 1.7]})
	t.append({"id": &"sw_microwave_dome", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 6, 0), "dist": 112.0, "times": [0.4, 1.5, 3.2], "prop": "tanks"})
	return t


func _apply_prop(kind: String, e: Dictionary) -> void:
	match kind:
		"tanks":
			for p in [Vector3(-5, 0, 3), Vector3(4, 0, -2), Vector3(1, 0, 6)]:
				var tk := _make_tank(Color(0.3, 0.34, 0.22))
				tk.position = p
				tk.rotation.y = randf() * TAU
				add_child(tk)
				_props.append(tk)
		"tank_destroy":
			var tk := _make_tank(Color(0.3, 0.34, 0.22))
			add_child(tk)
			_props.append(tk)
			var wreck := _make_tank(Color(0.06, 0.055, 0.05))
			wreck.visible = false
			wreck.rotation.y = 0.35
			add_child(wreck)
			_props.append(wreck)
			get_tree().create_timer(0.1).timeout.connect(func() -> void:
				tk.visible = false
				wreck.visible = true)
		"building_collapse":
			var b := _make_building()
			add_child(b)
			_props.append(b)
			var tw := create_tween()
			tw.tween_interval(0.15)
			tw.tween_property(b, "scale:y", 0.12, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"plane_line":
			_start_mover(_make_plane(), Vector3(-60, 22, 0), Vector3(60, 22, 0), 2.0, false)
			fx.start_stamper(&"contrail_puff", _mover, 2.8, 4.0, 1.0)
		"plane_crash":
			var a: Vector3 = e.a
			var b: Vector3 = e.b
			var flight: float = clampf(a.distance_to(b) / 40.0, 1.0, 2.5)
			_start_mover(_make_plane(), a, b, flight, true)
			_mover.look_at_from_position(a, b, Vector3.UP)
		"tank_move":
			_start_mover(_make_tank(Color(0.3, 0.34, 0.22)), Vector3(-26, 0, 0), Vector3(26, 0, 0), 3.4, false)
			_mover.rotation.y = -PI * 0.5
			fx.start_stamper(&"vehicle_dust", _mover, 1.1, 4.0, 1.0)
		"welder":
			_box(Vector3(3.0, 1.0, 3.0), Vector3(0, 0.5, 0), Color(0.5, 0.5, 0.52), self)
			_props.append(get_child(get_child_count() - 1) as Node3D)


func _start_mover(n: Node3D, from: Vector3, to: Vector3, dur: float, hide_end: bool) -> void:
	add_child(n)
	_props.append(n)
	_mover = n
	_mover_from = from
	_mover_to = to
	_mover_dur = dur
	_mover_t0 = fx.now()
	_mover_hide_at_end = hide_end
	n.global_position = from


func _capture_entry(e: Dictionary) -> Array[Image]:
	fx.clear_all()
	_clear_props()
	_shake = 0.0
	_place_camera(e.look, e.dist)
	_label.text = String(e.id)
	await _frames(4)
	var t0: float = fx.now()
	_mover_t0 = t0
	_apply_prop(String(e.get("prop", "")), e)
	_mover_t0 = t0
	fx.spawn(e.id, e.a, e.b, e.s)
	var out: Array[Image] = []
	for t in e.times:
		while fx.now() - t0 < float(t) - 0.0005:
			await get_tree().process_frame
		_label.text = "%s   t=%.2fs" % [String(e.id), float(t)]
		await RenderingServer.frame_post_draw
		out.append(get_viewport().get_texture().get_image())
	return out


func _run_sheet() -> void:
	_shake_enabled = false
	var table: Array[Dictionary] = _sheet_table()
	var idx: int = int(_args.get("sheet", "0"))
	var per: int = int(_args.get("per", "6"))
	var lo: int = idx * per
	var hi: int = mini(lo + per, table.size())
	if lo >= table.size():
		print("sheet index out of range (%d effects)" % table.size())
		get_tree().quit(1)
		return
	fx.prewarm()
	await _frames(8)
	fx.clear_all()
	await _frames(4)
	var sheet := Image.create_empty(3 * CW, (hi - lo) * CH, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.02, 1.0))
	for row in range(lo, hi):
		var imgs: Array[Image] = await _capture_entry(table[row])
		for c in imgs.size():
			var im: Image = imgs[c]
			im.convert(Image.FORMAT_RGBA8)
			if _args.has("full"):
				im.save_png(_out_path("full_%s_%d%s.png" % [String(table[row].id), c, String(_args.get("tag", ""))]))
			im.resize(CW, CH, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, CW, CH), Vector2i(c * CW, (row - lo) * CH))
	var file: String = "sheet_%d%s.png" % [idx, String(_args.get("tag", ""))]
	sheet.save_png(_out_path(file))
	print("SHEET|saved|", file, "|effects=", hi - lo)
	get_tree().quit(0)

# ------------------------------------------------------------------ chaos battle

func _rand_ground(margin: float = 0.08) -> Vector3:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var p := Vector2(randf_range(margin, 1.0 - margin) * vp.x, randf_range(0.22, 1.0 - margin) * vp.y)
	var o: Vector3 = cam.project_ray_origin(p)
	var n: Vector3 = cam.project_ray_normal(p)
	if absf(n.y) < 0.01:
		return Vector3.ZERO
	return o + n * (-o.y / n.y)


func _sample_frame(delta: float) -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	_samples.dt.append(delta * 1000.0)
	_samples.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_samples.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	_samples.proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_samples.draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_samples.objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	_samples.prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))


static func summarize(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {}
	var s: Array = arr.duplicate()
	s.sort()
	var sum: float = 0.0
	for v in s:
		sum += float(v)
	var n: int = s.size()
	return {
		"mean": snappedf(sum / float(n), 0.001), "p50": snappedf(float(s[n / 2]), 0.001),
		"p95": snappedf(float(s[int(float(n) * 0.95)]), 0.001), "p99": snappedf(float(s[mini(int(float(n) * 0.99), n - 1)]), 0.001),
		"max": snappedf(float(s[n - 1]), 0.001),
	}


func _reset_samples() -> void:
	for k in _samples:
		_samples[k].clear()


func _chaos_rates() -> Array:
	return [
		[&"rifle", 150.0], [&"cannon", 20.0], [&"missile", 6.0], [&"rail", 8.0], [&"artillery", 2.0],
		[&"thermal", 1.0], [&"hit", 60.0], [&"exp_small", 10.0], [&"exp_medium", 6.0], [&"exp_large", 3.0],
		[&"vehicle", 0.9], [&"building", 0.25], [&"emp", 0.3],
	]


func _chaos_step(delta: float) -> void:
	var rate_mul: float = float(_args.get("rate", "1"))
	for r in _chaos_rates():
		var key: StringName = r[0]
		var c: float = float(_carry.get(key, 0.0)) + float(r[1]) * delta * rate_mul
		while c >= 1.0:
			c -= 1.0
			_chaos_spawn(key)
		_carry[key] = c
	for i in _dust_units.size():
		var u: Node3D = _dust_units[i]
		u.global_position += _dust_dir[i] * 6.0 * delta
		var p: Vector3 = u.global_position
		if absf(p.x) > 45.0 or p.z > 32.0 or p.z < -30.0:
			_dust_dir[i] = (Vector3.ZERO - p).normalized()


func _chaos_spawn(key: StringName) -> void:
	var p: Vector3 = _rand_ground()
	var ang: float = randf() * TAU
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	match key:
		&"rifle":
			fx.spawn(&"rifle_shot", p + Vector3(0, 1.3, 0), p + dir * randf_range(10.0, 25.0) + Vector3(0, 0.5, 0), 1.0)
		&"cannon":
			fx.spawn(&"cannon_shot", p + Vector3(0, 1.6, 0), p + dir * randf_range(14.0, 30.0), 1.0)
		&"missile":
			fx.spawn(&"missile_launch", p + Vector3(0, 1.5, 0), p + dir * randf_range(25.0, 45.0), 1.0)
		&"rail":
			fx.spawn(&"beam_rail", p + Vector3(0, 2.5, 0), p + dir * randf_range(20.0, 40.0), 1.0)
		&"artillery":
			fx.spawn(&"artillery_shell", p + Vector3(0, 1.5, 0), _rand_ground(), 1.0)
		&"thermal":
			fx.spawn(&"beam_thermal", p + Vector3(0, 2.5, 0), p + dir * randf_range(18.0, 30.0), 1.0)
		&"hit":
			fx.spawn(&"infantry_hit", p + Vector3(0, 1.0, 0), Vector3.ZERO, 1.0)
		&"exp_small":
			fx.spawn(&"explosion_small", p, Vector3.ZERO, 1.0)
		&"exp_medium":
			fx.spawn(&"explosion_medium", p, Vector3.ZERO, 1.0)
		&"exp_large":
			fx.spawn(&"explosion_large", p, Vector3.ZERO, 1.0)
		&"vehicle":
			fx.spawn(&"vehicle_destroy", p, Vector3.ZERO, 1.0)
		&"building":
			fx.spawn(&"building_collapse", p, Vector3.ZERO, 1.0)
		&"emp":
			fx.spawn(&"emp_pulse", p, Vector3.ZERO, 10.0)


func _run_chaos() -> void:
	_shake_enabled = false
	_place_camera(Vector3.ZERO, 70.0, 55.0, 10.0)
	if _args.get("prewarm", "1") == "1":
		fx.prewarm()
		await _frames(8)
		fx.clear_all()
	for i in 20:
		var u := _make_tank(Color(0.3, 0.34, 0.22))
		u.position = _rand_ground(0.2)
		add_child(u)
		_dust_units.append(u)
		_dust_dir.append(Vector3(cos(i * 1.7), 0.0, sin(i * 1.7)))
		fx.start_stamper(&"vehicle_dust", u, 1.6, 1000.0, 1.0)
	await _frames(30)
	var secs: float = float(_args.get("secs", "20"))
	# baseline: scenery + dust units only (dust stampers run; chaos spawns off)
	_reset_samples()
	fx.reset_stats()
	_record = true
	await get_tree().create_timer(3.0).timeout
	_record = false
	var base: Dictionary = _pack_samples()
	_chaos_on = true
	_reset_samples()
	fx.reset_stats()
	_record = true
	await get_tree().create_timer(secs).timeout
	_record = false
	_chaos_on = false
	var chaos: Dictionary = _pack_samples()
	var stats: Dictionary = fx.get_stats()
	var res: Dictionary = {
		"renderer": String(RenderingServer.get_current_rendering_method()), "driver": String(RenderingServer.get_current_rendering_driver_name()),
		"viewport": get_viewport().get_visible_rect().size, "quality": int(fx.quality), "secs": secs, "rate_mul": float(_args.get("rate", "1")),
		"baseline": base, "chaos": chaos, "fx_stats": stats,
		"texture_mem_mb": snappedf(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0, 0.1),
	}
	var js: String = JSON.stringify(res)
	print("RESULT|chaos|", js)
	var f := FileAccess.open(_out_path("chaos_%s%s.json" % [RenderingServer.get_current_rendering_method(), String(_args.get("tag", ""))]), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_out_path("chaos_last_%s%s.png" % [RenderingServer.get_current_rendering_method(), String(_args.get("tag", ""))]))
	get_tree().quit(0)


func _pack_samples() -> Dictionary:
	return {
		"frames": _samples.dt.size(), "frame_ms": summarize(_samples.dt), "gpu_ms": summarize(_samples.gpu),
		"render_cpu_ms": summarize(_samples.cpu), "script_ms": summarize(_samples.proc),
		"draw_calls": summarize(_samples.draws), "objects": summarize(_samples.objs), "primitives": summarize(_samples.prims),
	}

# ------------------------------------------------------------------ first-spawn hitch test

func _run_hitch() -> void:
	_shake_enabled = false
	_place_camera(Vector3.ZERO, 60.0, 55.0, 10.0)
	fx.force = true
	if _args.get("prewarm", "0") == "1":
		fx.prewarm()
		await _frames(6)
		fx.clear_all()
	await get_tree().create_timer(1.0).timeout
	var table: Array[Dictionary] = _sheet_table()
	var rows: Array = []
	var worst_all: float = 0.0
	for pass_i in 2:
		for e in table:
			fx.clear_all()
			_hitch_max = 0.0
			await get_tree().create_timer(0.25).timeout
			_hitch_max = 0.0
			fx.spawn(e.id, e.a * 0.4, e.b * 0.4, e.s)
			await get_tree().create_timer(0.35).timeout
			rows.append([pass_i, String(e.id), snappedf(_hitch_max * 1000.0, 0.1)])
			if pass_i == 0:
				worst_all = maxf(worst_all, _hitch_max * 1000.0)
	var cold: Array = []
	var warm: Array = []
	for r in rows:
		(cold if int(r[0]) == 0 else warm).append(float(r[2]))
	var res: Dictionary = {
		"renderer": String(RenderingServer.get_current_rendering_method()), "prewarm": _args.get("prewarm", "0"),
		"first_pass_ms": summarize(cold), "second_pass_ms": summarize(warm), "rows": rows,
	}
	print("RESULT|hitch|", JSON.stringify(res))
	var f := FileAccess.open(_out_path("hitch_%s_prewarm%s.json" % [RenderingServer.get_current_rendering_method(), String(_args.get("prewarm", "0"))]), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	get_tree().quit(0)

# ------------------------------------------------------------------ bench + play

func _run_bench() -> void:
	var b := VfxBench.new()
	add_child(b)
	await b.run(self, _args)
	get_tree().quit(0)


func _run_play() -> void:
	fx.prewarm()
	await _frames(6)
	fx.clear_all()
	_label.text = "1-9,0 spawn | click ground | wheel zoom | Q quality"


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_place_camera(_cam_look, maxf(8.0, _cam_dist * 0.9))
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_place_camera(_cam_look, minf(200.0, _cam_dist * 1.1))
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_play_spawn(_ground_under_mouse())
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
			_play_index = ev.keycode - KEY_1
		elif ev.keycode == KEY_0:
			_play_index = 9
		_label.text = "effect #%d: %s" % [_play_index, String(_sheet_table()[_play_index % _sheet_table().size()].id)]


func _ground_under_mouse() -> Vector3:
	var p: Vector2 = get_viewport().get_mouse_position()
	var o: Vector3 = cam.project_ray_origin(p)
	var n: Vector3 = cam.project_ray_normal(p)
	return o + n * (-o.y / n.y) if absf(n.y) > 0.01 else Vector3.ZERO


func _play_spawn(p: Vector3) -> void:
	var table: Array[Dictionary] = _sheet_table()
	var e: Dictionary = table[_play_index % table.size()]
	var off: Vector3 = p - Vector3(e.look.x, 0.0, e.look.z)
	fx.spawn(e.id, e.a + off, e.b + off, e.s)
