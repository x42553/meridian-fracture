extends "res://tests/visual/lineup_models.gd"
## VIEW-M8 (OLM) contact sheets: the REAL recipe files of any pattern through ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend,
## rest pose by default, aircraft optionally dropped to the ground (`--ground=1`) so they fit a ground-level camera.
## `tools/gd shot res://tests/visual/olm_sheet.tscn out.png --size 1920x1080 -- --pattern='unit.olm.*' [--style=olm.algeria]
##   [--roster=roster.olm] [--cols=4] [--cell=8] [--cam=N --yaw=N --pitch=N --tx=N --ty=N --tz=N --fov=N] [--ground=1]
##   [--face=deg] [--pose=rest|action] [--team=N] [--labels=1]`

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _ready() -> void:
	var pattern: String = "unit.olm.*"
	var style_arg: String = ""
	var roster: String = "roster.olm"
	var cols: int = 4
	var cell: float = 8.0
	var dist: float = 0.0
	var yaw: float = 155.0
	var pitch: float = 38.0
	var tx: float = 0.0
	var ty: float = 1.2
	var tz: float = 0.0
	var fov: float = 34.0
	var ground: bool = false
	var face: float = 0.0
	var labels: bool = false
	var pose_arg: String = "rest"
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"pattern": pattern = kv[1]
			"style": style_arg = kv[1]
			"roster": roster = kv[1]
			"cols": cols = kv[1].to_int()
			"cell": cell = kv[1].to_float()
			"cam": dist = kv[1].to_float()
			"yaw": yaw = kv[1].to_float()
			"pitch": pitch = kv[1].to_float()
			"tx": tx = kv[1].to_float()
			"ty": ty = kv[1].to_float()
			"tz": tz = kv[1].to_float()
			"fov": fov = kv[1].to_float()
			"ground": ground = kv[1] == "1"
			"face": face = kv[1].to_float()
			"labels": labels = kv[1] == "1"
			"pose": pose_arg = kv[1]
			"team": team_id = kv[1].to_int()
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
	var ids: Array[String] = []
	for pat: String in pattern.split(",", false):
		for rid: String in _book.ids():
			if rid.match(pat) and not ids.has(rid):
				ids.append(rid)
	var rows: int = ceili(float(ids.size()) / float(cols))
	for i in ids.size():
		var rid: String = ids[i]
		var sid: StringName = StringName(style_arg) if style_arg != "" else _book.style_for_def(rid, roster)
		var pos: Vector3 = Vector3((float(i % cols) - float(cols - 1) * 0.5) * cell, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * cell)
		var ent: Object = Entity.new()
		ent.style_id = sid
		ent.team_index = team_id
		var m: ViewModel = _builder.get_model(StringName(rid), sid)
		_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
		ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(face)), pos + Vector3(0.0, 0.0 if ground else m.info.hover, 0.0))
		if pose == "action":
			ent.deploy = 1.0
			ent.turret_yaw = deg_to_rad(-25.0)
			ent.recoil = 0.5
			ent.elevation = 0.6
			ent.spin_angle = 1.1
			ent.move01 = 1.0
			ent.roll_m = 0.4
		elif pose == "deploy":
			ent.deploy = 1.0
			ent.elevation = 0.8
		_push(ent)
		_ents.append(ent)
		if labels:
			var lb: Label3D = Label3D.new()
			lb.text = rid.get_slice(".", 2)
			lb.pixel_size = 0.012
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.no_depth_test = true
			lb.position = pos + Vector3(0.0, 0.05, cell * 0.36)
			add_child(lb)
		print("  %s@%s tris=%s h=%.1f r=%.1f%s" % [rid, sid, m.info.tris, m.info.height, m.info.radius, " PLACEHOLDER " + m.error if m.placeholder else ""])
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	_aim(Vector3(tx, ty, tz), dist if dist > 0.0 else span * 1.15, pitch, yaw, fov)
