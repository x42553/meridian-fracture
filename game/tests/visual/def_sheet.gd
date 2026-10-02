extends "res://tests/visual/lineup_models.gd"
## VIEW-M8 (DEF) contact sheet: REAL recipe files through ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend, one labelled cell per
## `recipe_id@style_id` entry, rest and/or action poses, so units of two factions (or one recipe under two styles) stand side by side.
## `tools/gd shot res://tests/visual/def_sheet.tscn out.png --size 1920x1080 -- --items=unit.def.hammer_tank@def,unit.ae.buffalo_tank@ae
##   [--pose=rest|action|both] [--cols=4] [--cell=9] [--cam=N --yaw=N --pitch=N --tx=N --tz=N] [--team=1] [--hp=0.4] [--face=deg]
##   [--labels=0|1] [--hover]`
## `--items` may use a trailing glob: `unit.def.*@def` expands to every matching recipe id. Prints tris / size / sockets per entry.

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _ready() -> void:
	var items_arg: String = "unit.def.hammer_tank@def"
	var pose_arg: String = "rest"
	var cols: int = 4
	var cell: float = 9.0
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 40.0
	var tx: float = 0.0
	var tz: float = 0.0
	var hp: float = 0.0
	var face: float = 150.0
	var labels: bool = true
	var use_hover: bool = false
	var teams_n: int = 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--items="):
			items_arg = a.substr(8)
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
		elif a.begins_with("--tz="):
			tz = a.substr(5).to_float()
		elif a.begins_with("--team="):
			team_id = a.substr(7).to_int()
		elif a.begins_with("--hp="):
			hp = a.substr(5).to_float()
		elif a.begins_with("--face="):
			face = a.substr(7).to_float()
		elif a.begins_with("--labels="):
			labels = a.substr(9).to_int() != 0
		elif a == "--hover":
			use_hover = true
		elif a.begins_with("--teams="):
			teams_n = clampi(a.substr(8).to_int(), 1, 16)  # VQ2A: every item once per player colour 0..N-1 (cols = N)
		elif a.begins_with("--contrast="):
			ViewTeamContrast.enabled = a.substr(11).to_int() != 0  # VQ2A: 0 = raw player colours on the plates (before shots)
		elif a.begins_with("--boost="):
			ViewConsts.visual_boost_enabled = a.substr(8).to_int() != 0  # VQ2A: 0 = the pre-VQ2A model scale (before shots)
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_book = ViewRecipeBook.new()
	_book.load_all()
	_mats.setup(_book, q)
	_backend.setup(self, _mats, q)
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_environment()
	_ground()
	var entries: Array[PackedStringArray] = []
	for spec: String in items_arg.split(",", false):
		var at: int = spec.rfind("@")
		var rid: String = spec if at < 0 else spec.substr(0, at)
		var sid: String = "" if at < 0 else spec.substr(at + 1)
		if rid.contains("*"):
			for k: String in _book.ids():
				if k.match(rid):
					entries.append(PackedStringArray([k, sid]))
		else:
			entries.append(PackedStringArray([rid, sid]))
	if teams_n > 1:
		var expanded: Array[PackedStringArray] = []
		for en: PackedStringArray in entries:
			for ti: int in teams_n:
				expanded.append(PackedStringArray([en[0], en[1], str(ti)]))
		entries = expanded
		cols = teams_n
	var poses: PackedStringArray = ["rest", "action"] if pose_arg == "both" else [pose_arg]
	var n_cols: int = mini(cols, entries.size())
	var rows: int = ceili(float(entries.size()) / float(n_cols)) * poses.size()
	for pi in poses.size():
		for i in entries.size():
			var rid: String = entries[i][0]
			var sid: StringName = StringName(entries[i][1]) if entries[i][1] != "" else _book.style_for_def(rid, "roster.def.vanilla")
			var m: ViewModel = _builder.get_model(StringName(rid), sid)
			var ent: Object = Entity.new()
			ent.style_id = sid
			ent.team_index = entries[i][2].to_int() if entries[i].size() > 2 else team_id
			_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
			var gx: float = (float(i % n_cols) - float(n_cols - 1) * 0.5) * cell
			var gz: float = (float(i / n_cols) * poses.size() + float(pi) - float(rows - 1) * 0.5) * cell
			var y0: float = m.info.hover if use_hover else (0.4 if m.info.hover > 0.5 else 0.0)
			ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(face)), Vector3(gx, y0, gz))
			ent.damage = hp
			if poses[pi] == "action":
				_action(ent, m)
			elif m.info.has_part(ViewMeshBuilder.Part.ROTOR):
				ent.spin_angle = 0.6
			_push(ent)
			_ents.append(ent)
			if labels and pi == 0:
				var lab: Label3D = Label3D.new()
				lab.text = "%s@%s" % [rid.get_slice(".", rid.get_slice_count(".") - 1), sid]
				lab.font_size = 48
				lab.pixel_size = 0.005
				lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lab.no_depth_test = true
				lab.modulate = Color(1, 1, 1)
				lab.outline_size = 10
				add_child(lab)
				lab.position = Vector3(gx, 0.2, gz + cell * 0.42)
			if pi == 0:
				var sock: PackedStringArray = PackedStringArray()
				for k: Variant in m.info.sockets:
					sock.append(str(k))
				sock.sort()
				print("  %s@%s tris=%s v=%d h=%.2f r=%.2f build=%.1fms members=%d%s\n     sockets: %s" % [rid, sid, m.info.tris, m.info.verts,
					m.info.height, m.info.radius, m.info.build_ms, m.info.members, " PLACEHOLDER " + m.error if m.placeholder else "", " ".join(sock)])
	var fit: float = maxf(float(n_cols) * cell * 1.0, float(rows) * cell * 1.9 * sin(deg_to_rad(pitch)))
	_aim(Vector3(tx, 1.2, tz), dist if dist > 0.0 else fit, pitch, yaw, 34.0)


func _action(ent: Object, m: ViewModel) -> void:
	ent.deploy = 1.0
	ent.turret_yaw = deg_to_rad(-28.0)
	ent.recoil = 0.55
	ent.elevation = 0.8
	ent.spin_angle = 1.1
	ent.move01 = 1.0
	ent.roll_m = 0.45
	ent.mnt = PackedFloat32Array([deg_to_rad(40.0), 0.7, 0.5, deg_to_rad(-35.0), 0.6, 0.5, deg_to_rad(20.0), 0.5, 0.4])
	if m.info.members > 1:
		ent.roll_m = 0.37
