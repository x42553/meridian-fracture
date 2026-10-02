extends Node
## Spike driver. Examples (run from the repo root):
##   Godot --path prototypes/models -- --mode=shot --scene=units --out=/abs/dir --name=units_v1.png
##   Godot --path prototypes/models -- --mode=turntable --model=tank
##   Godot --path prototypes/models -- --mode=icons | --mode=stats | --mode=lod
##   Godot --path prototypes/models --disable-vsync -- --mode=bench --path_kind=nodes --shadows=1 --n=400

class Stage extends RefCounted:
	var vp: SubViewport
	var cam: Camera3D
	var root: Node3D
	var sun: DirectionalLight3D
	var env: Environment
	var ground: MeshInstance3D

const TEAMS: Array[Color] = [Color(0.92, 0.14, 0.10), Color(0.14, 0.42, 0.98), Color(0.96, 0.80, 0.10), Color(0.12, 0.76, 0.30),
	Color(0.95, 0.45, 0.05), Color(0.62, 0.20, 0.85), Color(0.10, 0.80, 0.85), Color(0.92, 0.92, 0.92)]

var _args: Dictionary = {}
var _out: String = ""
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial


func _ready() -> void:
	_args = _parse_args()
	_out = String(_args.get("out", ProjectSettings.globalize_path("res://shots")))
	DirAccess.make_dir_recursive_absolute(_out)
	get_viewport().disable_3d = true
	ViewUnitMaterial.register_globals()
	ViewMeshBuilder.lod1_key = _f("lod1", ViewMeshBuilder.lod1_key)
	ViewMeshBuilder.lod2_key = _f("lod2", ViewMeshBuilder.lod2_key)
	var mode: String = String(_args.get("mode", "shot"))
	print("PROTO renderer=", RenderingServer.get_video_adapter_name(), " api=", RenderingServer.get_video_adapter_api_version(), " method=", ProjectSettings.get_setting("rendering/renderer/rendering_method"), " driver=", RenderingServer.get_current_rendering_driver_name())
	match mode:
		"shot": await _mode_shot()
		"turntable": await _mode_turntable()
		"icons": await _mode_icons()
		"stats": await _mode_stats()
		"lod": await _mode_lod()
		"sheet": await _mode_sheet()
		"bench": await _mode_bench()
		_: push_error("unknown mode " + mode)
	get_tree().quit()


func _parse_args() -> Dictionary:
	var d: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _f(key: String, default: float) -> float:
	return float(_args.get(key, default))


# ------------------------------------------------------------------ resources
func _mesh(id: StringName, faction: StringName = &"napc") -> ArrayMesh:
	var key: String = "%s:%s" % [id, faction]
	if not _meshes.has(key):
		var style: Dictionary = ViewSampleModels.tank_style(faction) if id == &"tank" else ViewSampleModels.palette(faction)
		_meshes[key] = ViewSampleModels.build(id, style)
	return _meshes[key]


func _mat(faction: StringName = &"napc") -> ShaderMaterial:
	if not _mats.has(faction):
		var q: float = _f("quality", 1.0)
		_mats[faction] = ViewUnitMaterial.create({"quality": q})
	return _mats[faction]


func _make_env(transparent: bool) -> Environment:
	var e := Environment.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.44, 0.70)
	sm.sky_horizon_color = Color(0.80, 0.82, 0.84)
	sm.ground_horizon_color = Color(0.66, 0.63, 0.58)
	sm.ground_bottom_color = Color(0.30, 0.28, 0.25)
	var sky := Sky.new()
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = _f("ambient", 0.8)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = int(_args.get("tonemap", Environment.TONE_MAPPER_FILMIC))
	e.tonemap_exposure = _f("exposure", 1.0)
	e.tonemap_white = 6.0
	if int(_args.get("post", 1)) == 1:
		e.ssao_enabled = true
		e.ssao_radius = 1.0
		e.ssao_intensity = 2.0
		e.ssao_power = 1.6
		e.ssao_light_affect = 0.25
		e.glow_enabled = true
		e.glow_intensity = 0.7
		e.glow_bloom = 0.04
		e.glow_hdr_threshold = 1.1
		e.adjustment_enabled = true
		e.adjustment_saturation = 1.05
		e.adjustment_contrast = 1.12
	return e


func _make_stage(size: Vector2i, opts: Dictionary = {}) -> Stage:
	var st := Stage.new()
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = bool(opts.get("transparent", false))
	vp.msaa_3d = Viewport.MSAA_4X if int(_args.get("msaa", 1)) == 1 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(_args.get("fxaa", 0)) == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.mesh_lod_threshold = _f("lodthr", 1.0)
	add_child(vp)
	st.vp = vp
	st.root = Node3D.new()
	vp.add_child(st.root)
	st.env = _make_env(bool(opts.get("transparent", false)))
	var we := WorldEnvironment.new()
	we.environment = st.env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = _f("sun", 1.9)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = int(_args.get("shadows", 1)) == 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(opts.get("shadow_dist", 90.0))
	sun.light_angular_distance = 0.6
	vp.add_child(sun)
	st.sun = sun
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	fill.light_energy = _f("fill", 0.45)
	fill.light_color = Color(0.55, 0.70, 1.0)
	fill.shadow_enabled = false
	vp.add_child(fill)
	if bool(opts.get("ground", true)):
		if _ground_mat == null:
			_ground_mat = ShaderMaterial.new()
			_ground_mat.shader = load("res://shaders/ground.gdshader") as Shader
			_water_mat = ShaderMaterial.new()
			_water_mat.shader = _ground_mat.shader
			_water_mat.set_shader_parameter("water_mix", 1.0)
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(400.0, 400.0)
		g.mesh = pm
		g.material_override = _ground_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		st.root.add_child(g)
		st.ground = g
	var cam := Camera3D.new()
	cam.near = 0.5
	cam.far = 500.0
	vp.add_child(cam)
	cam.current = true
	st.cam = cam
	return st


func _water_patch(st: Stage, center: Vector3, size: Vector2) -> MeshInstance3D:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	w.mesh = pm
	w.material_override = _water_mat
	w.position = center + Vector3(0.0, 0.02, 0.0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	st.root.add_child(w)
	return w


func _frame(st: Stage, mesh: ArrayMesh, hover: float, pitch: float, yaw: float, fov: float, margin: float = 1.12) -> void:
	var bb: AABB = mesh.get_meta("rest_aabb")
	var c: Vector3 = bb.get_center() + Vector3(0.0, hover, 0.0)
	var r: float = bb.size.length() * 0.5 * margin
	_aim(st, c, r / sin(deg_to_rad(fov) * 0.5), pitch, yaw, fov)


func _aim(st: Stage, target: Vector3, dist: float, pitch_deg: float, yaw_deg: float, fov: float) -> void:
	var p: float = deg_to_rad(pitch_deg)
	var y: float = deg_to_rad(yaw_deg)
	var dir := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	st.cam.fov = fov
	st.cam.position = target + dir * dist
	st.cam.look_at(target, Vector3.UP)


func _place(st: Stage, id: StringName, faction: StringName, pos: Vector3, yaw_deg: float, team: int, pose: String = "rest") -> ViewModelRig:
	var r := ViewModelRig.new()
	r.setup(_mesh(id, faction), _mat(faction), TEAMS[team])
	r.position = pos + Vector3(0.0, float(ViewSampleModels.info(id)["hover"]), 0.0)
	r.rotation_degrees.y = yaw_deg
	if pose == "action":
		r.anim_time = 1.7 + pos.x * 0.1
		match id:
			&"tank":
				r.turret_yaw = deg_to_rad(-22.0)
				r.recoil = 0.55
			&"apc":
				r.turret_yaw = deg_to_rad(35.0)
				r.spin = 3.0
			&"howitzer":
				r.deploy = 1.0
				r.turret_yaw = deg_to_rad(18.0)
				r.recoil = 0.3
			&"infantry":
				r.move = 1.0
				r.roll = 0.37 + pos.x * 0.05
			&"gunship":
				r.spin = 34.0
				r.turret_yaw = deg_to_rad(25.0)
			&"boat":
				r.spin = 2.5
				r.turret_yaw = deg_to_rad(-30.0)
			&"factory":
				r.deploy = 1.0
		r.push_anim()
		r.push_aux()
	elif id == &"gunship" or id == &"boat":
		r.spin = 34.0 if id == &"gunship" else 2.5
		r.push_aux()
	st.root.add_child(r)
	return r


# ------------------------------------------------------------------ frames / capture
func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(st: Stage, path: String) -> Image:
	await _settle()
	var img: Image = st.vp.get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())
	return img


func _crop_save(img: Image, rect: Rect2i, scale: int, path: String) -> void:
	var r: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var c: Image = img.get_region(r)
	c.resize(r.size.x * scale, r.size.y * scale, Image.INTERPOLATE_NEAREST)
	c.save_png(path)
	print("CROP ", path, " ", c.get_size())


# ------------------------------------------------------------------ scenes
func _scene_units(st: Stage, pose: String) -> void:
	var yaw: float = 158.0
	_place(st, &"tank", &"napc", Vector3(-9.0, 0.0, 3.0), yaw, 1, pose)
	var t2: ViewModelRig = _place(st, &"tank", &"napc", Vector3(-2.5, 0.0, 3.0), yaw + 12.0, 1, pose)
	t2.damage = 0.75
	t2.push_state()
	var a: ViewModelRig = _place(st, &"apc", &"napc", Vector3(4.0, 0.0, 3.0), yaw, 1, pose)
	a.selected = 1.0
	a.push_state()
	_place(st, &"howitzer", &"napc", Vector3(11.5, 0.0, 3.0), yaw - 10.0, 1, pose)
	_place(st, &"infantry", &"napc", Vector3(-6.0, 0.0, -5.5), yaw, 1, pose)
	_place(st, &"gunship", &"napc", Vector3(2.0, 0.0, -6.0), yaw - 25.0, 1, pose)
	_place(st, &"infantry", &"napc", Vector3(9.0, 0.0, -5.0), yaw + 20.0, 1, "rest")


func _scene_big(st: Stage, pose: String) -> void:
	_place(st, &"factory", &"napc", Vector3(0.0, 0.0, -4.0), 180.0, 1, pose)
	_place(st, &"tank", &"napc", Vector3(-9.0, 0.0, 6.0), -30.0, 1, pose)
	_place(st, &"infantry", &"napc", Vector3(-4.0, 0.0, 6.5), -30.0, 1, pose)
	_water_patch(st, Vector3(15.0, 0.0, 2.0), Vector2(16.0, 14.0))
	_place(st, &"boat", &"napc", Vector3(14.0, 0.0, 3.0), -50.0, 1, pose)


func _scene_factions(st: Stage, pose: String) -> void:
	var f: Array[StringName] = [&"napc", &"nec", &"def", &"han"]
	for i in 4:
		_place(st, &"tank", f[i], Vector3(-7.5 + 5.0 * float(i), 0.0, 0.0), 156.0, 1, pose)


func _scene_rts(st: Stage, pose: String) -> void:
	var yaw: float = -30.0
	for r in 2:
		for c in 3:
			_place(st, &"tank", &"napc", Vector3(-14.0 + 3.7 * float(c), 0.0, -2.0 + 3.6 * float(r)), yaw + float(c) * 4.0, 1, pose)
	for c in 3:
		_place(st, &"apc", &"napc", Vector3(-14.0 + 3.7 * float(c), 0.0, 6.6), yaw, 1, pose)
	_place(st, &"howitzer", &"napc", Vector3(-20.5, 0.0, -1.0), yaw, 1, pose)
	var hw: ViewModelRig = _place(st, &"howitzer", &"napc", Vector3(-20.5, 0.0, 6.0), yaw, 1, "action")
	hw.turret_yaw = deg_to_rad(40.0)
	hw.push_anim()
	for i in 5:
		_place(st, &"infantry", &"napc", Vector3(-2.5 + 1.6 * float(i % 3), 0.0, -3.0 + 3.0 * float(i / 3)), yaw + 15.0 * float(i), 1, pose)
	_place(st, &"gunship", &"napc", Vector3(-12.0, 0.0, -9.0), yaw, 1, pose)
	_place(st, &"gunship", &"napc", Vector3(-5.0, 0.0, -10.0), yaw + 30.0, 1, pose)
	_place(st, &"factory", &"napc", Vector3(-26.0, 0.0, -14.0), 180.0, 1, pose)
	var enemy: Array[StringName] = [&"def", &"nec", &"han"]
	for r in 3:
		for c in 3:
			_place(st, &"tank", enemy[r], Vector3(9.0 + 3.7 * float(c), 0.0, -5.0 + 4.0 * float(r)), 150.0 + float(c) * 5.0, 0, pose)
	_water_patch(st, Vector3(20.0, 0.0, 14.0), Vector2(22.0, 12.0))
	_place(st, &"boat", &"napc", Vector3(16.0, 0.0, 14.0), -60.0, 1, pose)
	_place(st, &"boat", &"napc", Vector3(23.0, 0.0, 13.0), -90.0, 1, pose)


func _scene_fog(st: Stage) -> void:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v: float = clampf(1.0 - (float(x) - 20.0) / 24.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	RenderingServer.global_shader_parameter_set("fow_tex", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set("fow_rect", Vector4(-16.0, -16.0, 1.0 / 32.0, 1.0 / 32.0))
	for i in 6:
		var r: ViewModelRig = _place(st, &"tank", &"def" if i >= 3 else &"napc", Vector3(-12.5 + 5.0 * float(i), 0.0, 0.0), 156.0, 1, "rest")
		r.fog_mode = 1.0
		r.push_state()
	_place(st, &"tank", &"napc", Vector3(0.0, 0.0, 6.5), 156.0, 1, "rest")


func _mode_shot() -> void:
	var scene: String = String(_args.get("scene", "units"))
	var pose: String = String(_args.get("pose", "action"))
	var st: Stage = _make_stage(Vector2i(int(_f("w", 1920)), int(_f("h", 1080))), {"shadow_dist": _f("sd", 90.0)})
	var tgt := Vector3(_f("tx", 0.0), _f("ty", 0.9), _f("tz", 0.0))
	var d: float = 0.0
	match scene:
		"units":
			_scene_units(st, pose)
			tgt = Vector3(1.0, 1.2, -1.0)
			_aim(st, tgt, _f("dist", 30.0), _f("pitch", 26.0), _f("yaw", 0.0), _f("fov", 32.0))
		"big":
			_scene_big(st, pose)
			tgt = Vector3(2.0, 2.0, 0.0)
			_aim(st, tgt, _f("dist", 34.0), _f("pitch", 26.0), _f("yaw", -18.0), _f("fov", 36.0))
		"factions":
			_scene_factions(st, pose)
			tgt = Vector3(0.0, 0.9, 0.0)
			_aim(st, tgt, _f("dist", 19.0), _f("pitch", 24.0), _f("yaw", 0.0), _f("fov", 34.0))
		"side":
			_place(st, &"tank", &"napc", Vector3(-4.2, 0.0, 0.0), 90.0, 1, "rest")
			_place(st, &"tank", &"napc", Vector3(4.2, 0.0, 0.0), -90.0, 1, "rest")
			tgt = Vector3(0.0, 0.7, 0.0)
			_aim(st, tgt, _f("dist", 11.0), _f("pitch", 10.0), 0.0, 32.0)
		"fog":
			_scene_fog(st)
			tgt = Vector3(0.0, 0.9, 2.0)
			_aim(st, tgt, 26.0, 40.0, 0.0, 34.0)
		"rts":
			_scene_rts(st, pose)
			var cam_h: float = _f("cam_h", 45.0)
			d = cam_h / sin(deg_to_rad(55.0))
			tgt = Vector3(_f("tx", -4.0), 0.0, _f("tz", 2.0))
			_aim(st, tgt, d, 55.0, 0.0, _f("fov", 40.0))
	var name: String = String(_args.get("name", "%s.png" % scene))
	var img: Image = await _capture(st, _out.path_join(name))
	if scene == "rts":
		var p1: Vector2 = st.cam.unproject_position(Vector3(-10.0, 0.6, 2.0))
		_crop_save(img, Rect2i(int(p1.x) - 240, int(p1.y) - 135, 480, 270), 3, _out.path_join(name.get_basename() + "_cropA.png"))
		var p2: Vector2 = st.cam.unproject_position(Vector3(13.0, 0.6, 0.0))
		_crop_save(img, Rect2i(int(p2.x) - 240, int(p2.y) - 135, 480, 270), 3, _out.path_join(name.get_basename() + "_cropB.png"))
		var p3: Vector2 = st.cam.unproject_position(Vector3(-2.0, 0.6, 1.0))
		_crop_save(img, Rect2i(int(p3.x) - 120, int(p3.y) - 68, 240, 136), 6, _out.path_join(name.get_basename() + "_cropC.png"))
		print("PPM px per metre at target: ", (st.cam.unproject_position(tgt + Vector3(3.0, 0.0, 0.0)) - st.cam.unproject_position(tgt)).x / 3.0)


func _mode_turntable() -> void:
	var id: StringName = StringName(String(_args.get("model", "tank")))
	var faction: StringName = StringName(String(_args.get("faction", "napc")))
	var st: Stage = _make_stage(Vector2i(960, 540), {"shadow_dist": 30.0})
	var inf: Dictionary = ViewSampleModels.info(id)
	var rig: ViewModelRig = _place(st, id, faction, Vector3.ZERO, 0.0, 1, String(_args.get("pose", "action")))
	_frame(st, _mesh(id, faction), float(inf["hover"]), _f("pitch", 20.0), 0.0, 30.0, _f("margin", 1.1))
	var sheet := Image.create_empty(1920, 1080, false, Image.FORMAT_RGB8)
	var angles: Array[float] = [-30.0, 60.0, 150.0, 240.0]
	for i in 4:
		rig.rotation_degrees.y = angles[i]
		await _settle(3)
		var img: Image = st.vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(960, 540)), Vector2i((i % 2) * 960, (i / 2) * 540))
	var path: String = _out.path_join(String(_args.get("name", "turn_%s_%s.png" % [id, faction])))
	sheet.save_png(path)
	print("SHOT ", path)


func _mode_icons() -> void:
	var size := Vector2i(int(_f("iw", 256)), int(_f("ih", 192)))
	var st: Stage = _make_stage(size, {"transparent": true, "ground": false, "shadow_dist": 20.0})
	st.sun.shadow_enabled = false
	st.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var jobs: Array = []
	for id in ViewSampleModels.IDS:
		jobs.append([id, &"napc"])
	for f in [&"nec", &"def", &"han"]:
		jobs.append([&"tank", f])
	var sheet := Image.create_empty(size.x * 5, size.y * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.11, 0.14, 1.0))
	var times: Array[float] = []
	var readback_us: Array[float] = []
	var t_first_us: int = 0
	var corner_alpha: float = -1.0
	var k: int = 0
	for job in jobs:
		var id: StringName = job[0]
		var faction: StringName = job[1]
		var t0: int = Time.get_ticks_usec()
		var rig: ViewModelRig = _place(st, id, faction, Vector3.ZERO, 0.0, 1, "rest")
		var inf: Dictionary = ViewSampleModels.info(id)
		_frame(st, _mesh(id, faction), float(inf["hover"]), 24.0, 0.0, 30.0, 0.78)
		rig.rotation_degrees.y = 150.0
		st.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var t_rb: int = Time.get_ticks_usec()
		var img: Image = st.vp.get_texture().get_image()
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		readback_us.append(float(Time.get_ticks_usec() - t_rb))
		var dt: int = Time.get_ticks_usec() - t0
		if k == 0:
			t_first_us = dt
			corner_alpha = img.get_pixel(2, 2).a
		else:
			times.append(float(dt) / 1000.0)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i((k % 5) * size.x, (k / 5) * size.y))
		rig.queue_free()
		k += 1
		if tex == null:
			push_error("icon texture failed")
	var avg: float = 0.0
	for t in times:
		avg += t
	avg /= maxf(float(times.size()), 1.0)
	print("ICONS count=", k, " first_ms=", float(t_first_us) / 1000.0, " avg_next_ms(2 frame waits incl.)=", avg, " readback+ImageTexture_ms_avg=", _avg(readback_us) / 1000.0, " corner_alpha=", corner_alpha, " size=", size)
	sheet.save_png(_out.path_join(String(_args.get("name", "icons.png"))))


func _mode_stats() -> void:
	var jobs: Array = []
	for id in ViewSampleModels.IDS:
		jobs.append([id, &"napc"])
	for f in [&"nec", &"def", &"han"]:
		jobs.append([&"tank", f])
	var keep: Array = []
	var tot_v: int = 0
	var tot_half: int = 0
	var tot_float: int = 0
	var tot_recipe: float = 0.0
	for job in jobs:
		var id: StringName = job[0]
		var faction: StringName = job[1]
		var style: Dictionary = ViewSampleModels.tank_style(faction) if id == &"tank" else ViewSampleModels.palette(faction)
		ViewSampleModels.make_builder(id, style)
		var n: int = 12
		var t0: int = Time.get_ticks_usec()
		var b: ViewMeshBuilder = null
		for i in n:
			b = ViewSampleModels.make_builder(id, style)
		var t_recipe: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
		var m0: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
		b.pack_half = true
		var t1: int = Time.get_ticks_usec()
		var mh: ArrayMesh = b.build(String(id))
		var t_half: float = float(Time.get_ticks_usec() - t1) / 1000.0
		var m1: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
		b.pack_half = false
		var t2: int = Time.get_ticks_usec()
		var mf: ArrayMesh = b.build(String(id))
		var t_float: float = float(Time.get_ticks_usec() - t2) / 1000.0
		var m2: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
		var strides: Array[int] = []
		for m in [mh, mf]:
			var fmt: int = (m as ArrayMesh).surface_get_format(0)
			var vc: int = b.vertex_count()
			var per_v: int = RenderingServer.mesh_surface_get_format_vertex_stride(fmt, vc) + RenderingServer.mesh_surface_get_format_normal_tangent_stride(fmt, vc) + RenderingServer.mesh_surface_get_format_attribute_stride(fmt, vc)
			strides.append(per_v)
		var idx_stride: int = RenderingServer.mesh_surface_get_format_index_stride(mh.surface_get_format(0), b.vertex_count())
		var tc: Vector3i = b.tier_triangle_counts()
		keep.append(mh)
		keep.append(mf)
		tot_v += b.vertex_count()
		tot_half += m1 - m0
		tot_float += m2 - m1
		tot_recipe += t_recipe
		print("STATS %-9s %-5s verts=%6d tris=%6d recipe=%6.2f ms  build(half)=%5.2f ms  build(float)=%5.2f ms  B/vertex half=%d float=%d idx_stride=%d  vbuf_KB(half)=%.0f  tris full/l1/l2=%s  rest_aabb=%s" % [id, faction, b.vertex_count(), b.triangle_count(), t_recipe, t_half, t_float, strides[0], strides[1], idx_stride, float(strides[0] * b.vertex_count() + idx_stride * b.triangle_count() * 3) / 1024.0, tc, (mh.get_meta("rest_aabb") as AABB).size])
	print("STATS total verts=", tot_v, " recipe_ms_total=", snappedf(tot_recipe, 0.1))


func _mode_sheet() -> void:
	var tile := Vector2i(640, 420)
	var ids: Array[StringName] = [&"apc", &"howitzer", &"gunship", &"boat", &"factory", &"infantry"]
	var st: Stage = _make_stage(tile, {"shadow_dist": 60.0})
	var sheet := Image.create_empty(tile.x * 3, tile.y * 2, false, Image.FORMAT_RGB8)
	var k: int = 0
	for id in ids:
		var rig: ViewModelRig = _place(st, id, &"napc", Vector3.ZERO, 150.0 if id != &"factory" else 140.0, 1, String(_args.get("pose", "action")))
		var water: MeshInstance3D = null
		if id == &"boat":
			water = _water_patch(st, Vector3.ZERO, Vector2(24.0, 24.0))
		_frame(st, _mesh(id), float(ViewSampleModels.info(id)["hover"]), 26.0, 0.0, 30.0, 1.05)
		await _settle(3)
		var img: Image = st.vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), Vector2i((k % 3) * tile.x, (k / 3) * tile.y))
		rig.queue_free()
		if water != null:
			water.queue_free()
		k += 1
	var path: String = _out.path_join(String(_args.get("name", "sheet.png")))
	sheet.save_png(path)
	print("SHOT ", path)


func _mode_lod() -> void:
	var st: Stage = _make_stage(Vector2i(1920, 1080), {"shadow_dist": 60.0})
	st.sun.shadow_enabled = false
	for key in [0.01, 0.02, 0.04]:
		ViewMeshBuilder.lod1_key = key
		ViewMeshBuilder.lod2_key = key * 3.0
		_meshes.clear()
		var rig: ViewModelRig = _place(st, &"tank", &"napc", Vector3.ZERO, 0.0, 1, "rest")
		var row: String = ""
		for dist in [6.0, 12.0, 25.0, 50.0, 100.0, 200.0]:
			_aim(st, Vector3(0.0, 1.0, 0.0), dist, 30.0, 0.0, 40.0)
			await _settle(3)
			row += " d=%d:%d" % [int(dist), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
		print("LOD key=", key, " (main pass only, tris)", row)
		rig.queue_free()
		await get_tree().process_frame


# ------------------------------------------------------------------ benchmark
func _mode_bench() -> void:
	var n: int = int(_f("n", 400))
	var kind: String = String(_args.get("path_kind", "nodes"))
	var res := Vector2i(int(_f("w", 1920)), int(_f("h", 1080)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var st: Stage = _make_stage(res, {"shadow_dist": 110.0})
	var mix: Array = [[&"tank", 130], [&"apc", 60], [&"howitzer", 50], [&"infantry", 100], [&"gunship", 30], [&"boat", 20], [&"factory", 10]]
	var list: Array[StringName] = []
	for m in mix:
		for i in int(round(float(m[1]) * float(n) / 400.0)):
			list.append(m[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in range(list.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: StringName = list[i]
		list[i] = list[j]
		list[j] = tmp
	var cols: int = 25
	var rigs: Array[ViewModelRig] = []
	var mms: Array = []
	if kind == "nodes":
		for i in list.size():
			var pos := Vector3((float(i % cols) - float(cols) * 0.5) * 2.7, 0.0, (float(i / cols) - 8.0) * 2.6)
			var r: ViewModelRig = _place(st, list[i], &"napc", pos, rng.randf_range(0.0, 360.0), i % 8, "rest")
			r.move = 1.0
			rigs.append(r)
	else:
		var mm_mat: ShaderMaterial = ViewUnitMaterial.create({"quality": _f("quality", 1.0)}, true)
		var groups: Dictionary = {}
		for i in list.size():
			if not groups.has(list[i]):
				groups[list[i]] = []
			groups[list[i]].append(i)
		for id in groups.keys():
			var idxs: Array = groups[id]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _mesh(id)
			mm.instance_count = idxs.size()
			mm.custom_aabb = AABB(Vector3(-100.0, -5.0, -100.0), Vector3(200.0, 60.0, 200.0))
			for k in idxs.size():
				var i: int = idxs[k]
				var pos := Vector3((float(i % cols) - float(cols) * 0.5) * 2.7, float(ViewSampleModels.info(id)["hover"]), (float(i / cols) - 8.0) * 2.6)
				mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), pos))
				mm.set_instance_custom_data(k, Color(0.0, 0.0, 0.0, 0.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mm_mat
			st.root.add_child(mmi)
			mms.append([mm, idxs.size()])
	_aim(st, Vector3(0.0, 0.0, 0.0), _f("dist", 78.0), 55.0, 0.0, 40.0)
	if int(_args.get("shadows", 1)) == 0:
		for r in rigs:
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rid: RID = st.vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var warm: int = 60
	var frames: int = int(_f("frames", 240))
	var dts: Array[float] = []
	var upd: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var draws: int = 0
	var prims: int = 0
	var objs: int = 0
	var t_prev: int = Time.get_ticks_usec()
	for f in warm + frames:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var dt: float = float(now - t_prev) / 1000.0
		t_prev = now
		var t: float = float(f) / 60.0
		var u0: int = Time.get_ticks_usec()
		if kind == "nodes":
			for i in rigs.size():
				var r: ViewModelRig = rigs[i]
				r.anim_time = t
				r.roll = t * 3.0
				r.turret_yaw = sin(t + float(i)) * 0.6
				r.push_anim()
				r.recoil = maxf(0.0, sin(t * 2.0 + float(i)))
				r.push_aux()
		else:
			for g in mms:
				var mm: MultiMesh = g[0]
				for k in int(g[1]):
					mm.set_instance_custom_data(k, Color(t * 3.0, sin(t + float(k)) * 0.6, 0.0, 0.0))
		var ut: float = float(Time.get_ticks_usec() - u0) / 1000.0
		if f >= warm:
			dts.append(dt)
			upd.append(ut)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			objs = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var res_d: Dictionary = {
		"kind": kind, "n": list.size(), "shadows": int(_args.get("shadows", 1)), "post": int(_args.get("post", 1)), "msaa": int(_args.get("msaa", 1)), "res": "%dx%d" % [res.x, res.y],
		"quality": _f("quality", 1.0), "frame_ms_avg": snappedf(_avg(dts), 0.01), "frame_ms_p95": snappedf(_pct(dts, 0.95), 0.01), "script_update_ms": snappedf(_avg(upd), 0.01),
		"render_cpu_ms": snappedf(_avg(cpu), 0.01), "render_gpu_ms": snappedf(_avg(gpu), 0.01), "draw_calls": draws, "primitives": prims, "objects": objs,
	}
	print("BENCH ", JSON.stringify(res_d))
	if int(_args.get("snap", 0)) == 1:
		await _capture(st, _out.path_join(String(_args.get("name", "bench_%s.png" % kind))))


static func _avg(a: Array[float]) -> float:
	var s: float = 0.0
	for x in a:
		s += x
	return s / maxf(float(a.size()), 1.0)


static func _pct(a: Array[float], p: float) -> float:
	var b: Array[float] = a.duplicate()
	b.sort()
	return b[clampi(int(float(b.size()) * p), 0, b.size() - 1)] if b.size() > 0 else 0.0
