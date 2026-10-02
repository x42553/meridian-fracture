extends "res://tests/visual/lineup_models.gd"
## NEC content review sheet (VIEW-M8 / F-nec): the REAL recipes through ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend on a labelled
## grid, with a per-entry style (`id@style`) so a NEC unit can stand beside another faction's unit of the same class.
##   tools/gd shot res://tests/visual/nec_sheet.tscn out.png --size 1920x1080 -- --ids='unit.nec.leopard_tank,unit.napc.guardian_tank@napc'
##     [--pattern='unit.nec.*'] [--style=nec] [--cols=4] [--cell=9] [--cam=N --yaw=N --pitch=N --tx=N --ty=N --tz=N] [--pose=rest|action]
##     [--team=1] [--labels=1] [--air=1 (keep the aircraft altitude; default 0 puts them on the ground for framing)] [--fov=34]

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _ready() -> void:
	var ids_arg: String = ""
	var pattern: String = ""
	var style_arg: String = "nec"
	var cols: int = 4
	var cell: float = 9.0
	var dist: float = 0.0
	var yaw: float = 200.0
	var pitch: float = 35.0
	var tx: float = 0.0
	var ty: float = 1.0
	var tz: float = 0.0
	var fov: float = 34.0
	var labels: bool = true
	var air: bool = false
	var pose_arg: String = "rest"
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		var v: String = kv[1]
		match kv[0]:
			"ids": ids_arg = v
			"pattern": pattern = v
			"style": style_arg = v
			"cols": cols = v.to_int()
			"cell": cell = v.to_float()
			"cam": dist = v.to_float()
			"yaw": yaw = v.to_float()
			"pitch": pitch = v.to_float()
			"tx": tx = v.to_float()
			"ty": ty = v.to_float()
			"tz": tz = v.to_float()
			"fov": fov = v.to_float()
			"pose": pose_arg = v
			"team": team_id = v.to_int()
			"labels": labels = v != "0"
			"air": air = v == "1"
	pose = pose_arg
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_mats.setup(null, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	_book = ViewRecipeBook.new()
	_book.load_all()
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_mats.setup(_book, q)
	var entries: Array[String] = []
	for tok: String in ids_arg.split(",", false):
		entries.append(tok.strip_edges())
	if pattern != "":
		for rid: String in _book.ids():
			for pat: String in pattern.split(",", false):
				if rid.match(pat):
					entries.append(rid)
					break
	var rows: int = ceili(float(entries.size()) / float(cols))
	for i in entries.size():
		var tok: String = entries[i]
		var rid: String = tok.get_slice("@", 0)
		var sid: StringName = StringName(tok.get_slice("@", 1)) if tok.contains("@") else StringName(style_arg)
		var pos: Vector3 = Vector3((float(i % cols) - float(cols - 1) * 0.5) * cell, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * cell)
		var ent: Object = Entity.new()
		ent.style_id = sid
		ent.team_index = team_id
		var m: ViewModel = _builder.get_model(StringName(rid), sid) as ViewModel
		_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
		ent.rig.transform = Transform3D(Basis(Vector3.UP, 0.0), pos + Vector3(0.0, m.info.hover if air else 0.0, 0.0))
		if pose == "action":
			ent.deploy = 1.0
			ent.turret_yaw = deg_to_rad(-25.0)
			ent.recoil = 0.5
			ent.elevation = 0.6
			ent.spin_angle = 1.1
			ent.move01 = 1.0
			ent.roll_m = 0.4
		_push(ent)
		_ents.append(ent)
		if labels:
			var lb: Label3D = Label3D.new()
			lb.text = "%s [%s]" % [rid.get_slice(".", 2) if rid.count(".") >= 2 else rid, sid]
			lb.font_size = 40
			lb.pixel_size = 0.006
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.no_depth_test = true
			lb.modulate = Color(1, 1, 1)
			lb.outline_size = 10
			lb.position = pos + Vector3(0.0, -0.05, cell * 0.42)
			add_child(lb)
		print("  %s@%s tris=%s verts=%d h=%.1f r=%.1f build=%.1fms%s" % [rid, sid, m.info.tris, m.info.verts, m.info.height, m.info.radius,
			m.info.build_ms, " PLACEHOLDER " + m.error if m.placeholder else ""])
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	_aim(Vector3(tx, ty, tz), dist if dist > 0.0 else span * 1.15, pitch, yaw, fov)
