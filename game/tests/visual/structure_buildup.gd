extends "res://tests/visual/structure_sheet.gd"
## VIEW-M7 build-up sequence (render spec 5.2 BUILDUP, art_direction 5.9.6): the same structure at build 0 .. 1 side by side. The
## model rises from below the ground (`u_anim.x = (1 - ease(build)) * (height + 1.5)` m, the ground plane hides the buried part) while a
## translucent scaffold cage (test stand-in for the VIEW-W2 mesh, `ViewMaterials.scaffold_material()`) grows to `height * ease(build)`.
##   tools/gd shot res://tests/visual/structure_buildup.tscn out.png --size 1920x1080 -- --arch=str_factory --fp=3x3 [--steps=6] [--kits=..]
##     [--reverse] (selling) [--cam=N --yaw=N --pitch=N --tx=N --tz=N]

func _ready() -> void:
	var arch: String = "str_factory"
	var fp: Array = [3, 3]
	var steps: int = 6
	var kit: String = ""
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 38.0
	var reverse: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--arch="):
			arch = a.substr(7)
		elif a.begins_with("--fp="):
			var wh: PackedStringArray = a.substr(5).split("x")
			fp = [wh[0].to_int(), wh[1].to_int()]
		elif a.begins_with("--steps="):
			steps = a.substr(8).to_int()
		elif a.begins_with("--kits="):
			kit = a.substr(7)
		elif a.begins_with("--cam="):
			dist = a.substr(6).to_float()
		elif a.begins_with("--yaw="):
			yaw = a.substr(6).to_float()
		elif a.begins_with("--pitch="):
			pitch = a.substr(8).to_float()
		elif a == "--reverse":
			reverse = true
	layout = 0
	pose = "rest"
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	var rid: String = rid_of(arch, fp[0] as int, fp[1] as int, kit)
	var rows: Array = [[arch, fp[0], fp[1], rid, kit]]
	_book = make_book(rows, {})
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_mats.setup(_book, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	var m: ViewModel = _builder.get_model(StringName(rid), &"napc")
	var span: float = float(maxi(fp[0] as int, fp[1] as int)) * 3.0 + 2.5
	var scaffold_mat: ShaderMaterial = _mats.scaffold_material()
	for i in steps:
		var build: float = float(i) / float(steps - 1)
		if reverse:
			build = 1.0 - build
		var e: float = build * build * (3.0 - 2.0 * build)
		var pos: Vector3 = Vector3((float(i) - float(steps - 1) * 0.5) * span, 0.0, 0.0)
		var ent: Object = Entity.new()
		ent.style_id = &"napc"
		ent.team_index = team_id
		_backend.add(ent, m, &"napc", ViewTeamColors.color(ent.team_index), ent.team_index)
		ent.rig.transform = Transform3D(Basis.IDENTITY, pos)
		ent.sink_m = (1.0 - e) * (m.info.height + 1.5)
		if build >= 1.0:
			ent.sink_m = 0.0
		_push(ent)
		_ents.append(ent)
		if build < 0.999:
			var cage: MeshInstance3D = MeshInstance3D.new()
			var bm: BoxMesh = BoxMesh.new()
			var ch: float = maxf(m.info.height * e, 0.05)
			bm.size = Vector3(float(fp[0] as int) * 3.0 - 0.3, ch, float(fp[1] as int) * 3.0 - 0.3)
			cage.mesh = bm
			cage.material_override = scaffold_mat
			cage.position = pos + Vector3(0.0, ch * 0.5, 0.0)
			cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(cage)
	_aim(Vector3(0.0, m.info.height * 0.3, 0.0), dist if dist > 0.0 else span * float(steps) * 1.0 + m.info.height, pitch, yaw, 34.0)
