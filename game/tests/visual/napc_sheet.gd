extends "res://tests/visual/lineup_models.gd"
## VIEW-M8 (NAPC) contact sheet: recipe ids (`id` or `id@style`) built from the REAL recipe files through ViewRecipeBook ->
## ViewModelBuilder -> ViewNodeBackend, laid out on a labelled grid; several poses and camera options.
## `tools/gd shot res://tests/visual/napc_sheet.tscn out.png --size 1920x1080 -- --ids=unit.napc.guardian_tank,unit.def.hammer_tank@def
##  [--style=napc] [--cols=4] [--cell=9] [--cam=N --yaw=N --pitch=N --ty=1.5 --tx=0 --tz=0 --fov=34] [--pose=rest|action]
##  [--team=1] [--hover=0|1] [--face=0] [--hp=0.0] [--labels=1] [--gray=0]`
## --hover=0 puts aircraft on the ground plane (default 1 = at their `meta.hover` altitude). --face is the yaw of every model.

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _ready() -> void:
	var ids_arg: String = "unit.napc.guardian_tank"
	var style_arg: String = ""
	var pose_arg: String = "rest"
	var cols: int = 4
	var cell: float = 9.0
	var dist: float = 0.0
	var yaw: float = 150.0
	var pitch: float = 30.0
	var tx: float = 0.0
	var ty: float = 1.0
	var tz: float = 0.0
	var fov: float = 34.0
	var hover_on: bool = true
	var face: float = 0.0
	var hp: float = 0.0
	var labels: bool = true
	var roster: String = "roster.napc"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids_arg = a.substr(6)
		elif a.begins_with("--style="):
			style_arg = a.substr(8)
		elif a.begins_with("--roster="):
			roster = a.substr(9)
		elif a.begins_with("--pose="):
			pose_arg = a.substr(7)
		elif a.begins_with("--cols="):
			cols = a.substr(7).to_int()
		elif a.begins_with("--cell="):
			cell = a.substr(7).to_float()
		elif a.begins_with("--cam="):
			dist = a.substr(6).to_float()
		elif a.begins_with("--yaw="):
			yaw = a.substr(6).to_float()
		elif a.begins_with("--pitch="):
			pitch = a.substr(8).to_float()
		elif a.begins_with("--tx="):
			tx = a.substr(5).to_float()
		elif a.begins_with("--ty="):
			ty = a.substr(5).to_float()
		elif a.begins_with("--tz="):
			tz = a.substr(5).to_float()
		elif a.begins_with("--fov="):
			fov = a.substr(6).to_float()
		elif a.begins_with("--team="):
			team_id = a.substr(7).to_int()
		elif a.begins_with("--hover="):
			hover_on = a.substr(8).to_int() != 0
		elif a.begins_with("--face="):
			face = a.substr(7).to_float()
		elif a.begins_with("--hp="):
			hp = a.substr(5).to_float()
		elif a.begins_with("--labels="):
			labels = a.substr(9).to_int() != 0
	pose = pose_arg
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_book = ViewRecipeBook.new()
	_book.load_all()
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_mats.setup(_book, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	var ids: PackedStringArray = ids_arg.split(",", false)
	var rows: int = ceili(float(ids.size()) / float(cols))
	for i in ids.size():
		var tok: String = ids[i]
		var rid: String = tok
		var sid: StringName = &""
		if tok.contains("@"):
			rid = tok.get_slice("@", 0)
			sid = StringName(tok.get_slice("@", 1))
		elif style_arg != "":
			sid = StringName(style_arg)
		else:
			sid = _book.style_for_def(rid, roster)
		var pos: Vector3 = Vector3((float(i % cols) - float(cols - 1) * 0.5) * cell, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * cell)
		var ent: Object = Entity.new()
		ent.style_id = sid
		ent.team_index = team_id
		var m: ViewModel = _builder.get_model(StringName(rid), sid) as ViewModel
		_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
		var hv: float = m.info.hover if hover_on else 0.0
		ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(face)), pos + Vector3(0.0, hv, 0.0))
		if pose == "action":
			ent.deploy = 1.0
			ent.turret_yaw = deg_to_rad(-25.0)
			ent.recoil = 0.5
			ent.elevation = 0.6
			ent.spin_angle = 1.1
			ent.move01 = 1.0
			ent.roll_m = 0.4
		ent.damage = hp
		_push(ent)
		_ents.append(ent)
		if labels:
			var lb: Label3D = Label3D.new()
			lb.text = rid.get_slice(".", rid.get_slice_count(".") - 1)
			lb.pixel_size = 0.014 * maxf(cell / 9.0, 0.5)
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.no_depth_test = true
			lb.modulate = Color(1, 1, 1)
			lb.outline_modulate = Color(0, 0, 0)
			lb.position = pos + Vector3(0.0, 0.05, cell * 0.42)
			add_child(lb)
		print("  %s@%s tris=%s h=%.1f r=%.1f%s" % [rid, sid, m.info.tris, m.info.height, m.info.radius, " PLACEHOLDER " + m.error if m.placeholder else ""])
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	_aim(Vector3(tx, ty, tz), dist if dist > 0.0 else span * 1.15, pitch, yaw, fov)
