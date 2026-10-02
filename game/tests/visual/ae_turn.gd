extends "res://tests/visual/lineup_models.gd"
## VIEW-M8 (AE) turntable / sheet tool: the REAL recipe files through ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend, every
## matching id drawn once per yaw in a row-major grid (rows = ids, columns = yaws), so a single shot shows a model from several sides.
## `tools/gd shot res://tests/visual/ae_turn.tscn out.png --size 1920x1080 -- --pattern='unit.ae.*' [--style=ae] [--yaws=30,120,210,300]
##  [--cell=6] [--cam=N --pitch=N --yaw=N] [--pose=rest|action] [--team=1] [--damage=0.0] [--aimh=N] [--grid=N]`
## `--items=id@style,id@style` selects ids with their own style (a same id may appear once per style only through separate calls).
## `--teamcycle` gives every placed model its own player colour (index r in grid mode, else the column), 12 colours.
## `--grid=N` lays the matching ids out in a grid of N columns instead (first yaw only).
## The camera looks at the grid centre at height `aimh` (default: half of the highest hover so aircraft stay in frame).

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _mesh(id: StringName, faction: StringName) -> Object:
	if _builder == null:
		_book = ViewRecipeBook.new()
		_book.load_all()
		var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
		_builder = ViewModelBuilder.new()
		_builder.setup(_book, q)
		_mats.setup(_book, q)
	return _builder.get_model(id, faction)


func _style_of(ids: Array[String], id_styles: Array[String], r: int, style_arg: String) -> StringName:
	if r < id_styles.size() and id_styles[r] != "":
		return StringName(id_styles[r])
	if style_arg != "":
		return StringName(style_arg)
	return _book.style_for_def(ids[r], "roster.ae")


func _ready() -> void:
	var pattern: String = "unit.ae.*"
	var style_arg: String = "ae"
	var yaws: PackedFloat32Array = PackedFloat32Array([30.0, 120.0, 210.0, 300.0])
	var cell: float = 6.0
	var dist: float = 0.0
	var pitch: float = 40.0
	var cam_yaw: float = 0.0
	var aimh: float = -1.0
	var pose_arg: String = "rest"
	var damage: float = 0.0
	var grid: int = 0
	var teamcycle: bool = false
	var items: PackedStringArray = PackedStringArray()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pattern="):
			pattern = a.substr(10)
		elif a.begins_with("--style="):
			style_arg = a.substr(8)
		elif a.begins_with("--yaws="):
			yaws = PackedFloat32Array()
			for s: String in a.substr(7).split(",", false):
				yaws.append(s.to_float())
		elif a.begins_with("--cell="):
			cell = a.substr(7).to_float()
		elif a.begins_with("--cam="):
			dist = a.substr(6).to_float()
		elif a.begins_with("--pitch="):
			pitch = a.substr(8).to_float()
		elif a.begins_with("--yaw="):
			cam_yaw = a.substr(6).to_float()
		elif a.begins_with("--aimh="):
			aimh = a.substr(7).to_float()
		elif a.begins_with("--pose="):
			pose_arg = a.substr(7)
		elif a.begins_with("--team="):
			team_id = a.substr(7).to_int()
		elif a.begins_with("--damage="):
			damage = a.substr(9).to_float()
		elif a.begins_with("--items="):
			items = a.substr(8).split(",", false)
		elif a == "--teamcycle":
			teamcycle = true
		elif a.begins_with("--grid="):
			grid = a.substr(7).to_int()
	pose = pose_arg
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_mats.setup(null, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	_mesh(&"x", &"ae")
	var ids: Array[String] = []
	var id_styles: Array[String] = []
	for it: String in items:
		var at: int = it.find("@")
		var iid: String = it if at < 0 else it.substr(0, at)
		ids.append(iid)
		id_styles.append("" if at < 0 else it.substr(at + 1))
	var all_ids: PackedStringArray = _book.ids() if items.is_empty() else PackedStringArray()
	for rid: String in all_ids:
		for pat: String in pattern.split(",", false):
			if rid.match(pat):
				ids.append(rid)
				break
	var cols: int = yaws.size()
	var rows: int = ids.size()
	if grid > 0:
		cols = mini(grid, ids.size())
		rows = ceili(float(ids.size()) / float(cols))
	var max_hover: float = 0.0
	var count: int = ids.size() if grid > 0 else rows
	for r in count:
		var sid: StringName = _style_of(ids, id_styles, r, style_arg)
		var m: ViewModel = _mesh(StringName(ids[r]), sid) as ViewModel
		print("  %s@%s tris=%s verts=%d h=%.1f r=%.1f%s" % [ids[r], sid, m.info.tris, m.info.verts, m.info.height, m.info.radius, " PLACEHOLDER " + m.error if m.placeholder else ""])
		var n_yaw: int = 1 if grid > 0 else cols
		for c in n_yaw:
			var ent: Object = Entity.new()
			ent.style_id = sid
			ent.team_index = (r if grid > 0 else c) % 12 if teamcycle else team_id
			var model: ViewModel = _mesh(StringName(ids[r]), sid) as ViewModel
			_backend.add(ent, model, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
			var gx: int = c
			var gz: int = r
			if grid > 0:
				gx = r % cols
				gz = r / cols
			var pos: Vector3 = Vector3((float(gx) - float(cols - 1) * 0.5) * cell, 0.0, (float(gz) - float(rows - 1) * 0.5) * cell)
			ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaws[c])), pos + Vector3(0.0, model.info.hover, 0.0))
			max_hover = maxf(max_hover, model.info.hover)
			if pose == "action":
				ent.deploy = 1.0
				ent.turret_yaw = deg_to_rad(-25.0)
				ent.recoil = 0.5
				ent.elevation = 0.6
				ent.spin_angle = 1.1
				ent.move01 = 1.0
				ent.roll_m = 0.4
			ent.damage = damage
			_push(ent)
			_ents.append(ent)
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	var target_y: float = aimh if aimh >= 0.0 else 1.0 + max_hover * 0.5
	_aim(Vector3(0.0, target_y, 0.0), dist if dist > 0.0 else span * 1.1, pitch, cam_yaw, 34.0)
