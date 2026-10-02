extends "res://tests/visual/lineup_models.gd"
## VIEW-T1 gallery: the REAL recipe files (stubs and hand-authored) through ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend.
## `tools/gd shot res://tests/visual/recipe_gallery.tscn out.png --size 1920x1080 -- --pattern='structure.shared.*' [--style=napc]
##  [--cols=4] [--cell=14] [--cam=N --yaw=N --pitch=N --tx=N --tz=N] [--pose=rest|action] [--team=1]`
## The style is `--style` when given, else ViewRecipeBook.style_for_def(id, roster of --roster, default napc).

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null
var _ids: Array[String] = []
var _style_arg: String = ""
var _roster: String = "roster.napc"


func _ensure_book() -> void:
	if _builder == null:
		_book = ViewRecipeBook.new()
		_book.load_all()
		var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
		_builder = ViewModelBuilder.new()
		_builder.setup(_book, q)
		_mats.setup(_book, q)


func _mesh(id: StringName, faction: StringName) -> Object:
	_ensure_book()
	return _builder.get_model(id, faction)


func _ready() -> void:
	var pattern: String = "structure.shared.*"
	var cols: int = 4
	var cell: float = 14.0
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 45.0
	var tx: float = 0.0
	var tz: float = 0.0
	var pose_arg: String = "rest"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pattern="):
			pattern = a.substr(10)
		elif a.begins_with("--style="):
			_style_arg = a.substr(8)
		elif a.begins_with("--roster="):
			_roster = a.substr(9)
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
		elif a.begins_with("--pose="):
			pose_arg = a.substr(7)
		elif a.begins_with("--team="):
			team_id = a.substr(7).to_int()
	pose = pose_arg
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_mats.setup(null, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	_ensure_book()
	for rid: String in _book.ids():
		for pat: String in pattern.split(",", false):
			if rid.match(pat):
				_ids.append(rid)
				break
	var rows: int = ceili(float(_ids.size()) / float(cols))
	for i in _ids.size():
		var rid: String = _ids[i]
		var sid: StringName = StringName(_style_arg) if _style_arg != "" else _book.style_for_def(rid, _roster)
		var pos: Vector3 = Vector3((float(i % cols) - float(cols - 1) * 0.5) * cell, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * cell)
		var ent: Object = Entity.new()
		ent.style_id = sid
		ent.team_index = team_id
		var m: ViewModel = _mesh(StringName(rid), sid) as ViewModel
		_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
		ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(0.0)), pos + Vector3(0.0, m.info.hover, 0.0))
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
		print("  %s@%s tris=%s h=%.1f r=%.1f%s" % [rid, sid, m.info.tris, m.info.height, m.info.radius, " PLACEHOLDER " + m.error if m.placeholder else ""])
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	_aim(Vector3(tx, 1.5, tz), dist if dist > 0.0 else span * 1.15, pitch, yaw, 34.0)
