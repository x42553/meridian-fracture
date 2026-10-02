extends "res://tests/visual/lineup_models.gd"
## VIEW-M5 / M6 contact sheet: view ARCHETYPES (game/data/recipes/archetypes/*.json) built through the real pipeline
## (ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend) as in-memory proof recipes, one style, rest and/or action poses.
## `tools/gd shot res://tests/visual/archetype_sheet.tscn out.png --size 1920x1080 -- --ids=veh_tank,veh_apc [--style=napc]
##   [--pose=rest|action|both] [--cols=4] [--cell=9] [--cam=N --yaw=N --pitch=N --tx=N --tz=N] [--team=1] [--hp=0.4]
##   [--params=key=val,key=val] [--face=yaw_deg]`
## The action pose exercises every animated channel: deploy, barrel elevation, turret yaw (+ secondary mounts), recoil, spin, gait.

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _ready() -> void:
	var ids_arg: String = "veh_tank"
	var style: String = "napc"
	var pose_arg: String = "both"
	var cols: int = 4
	var cell: float = 9.0
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 40.0
	var tx: float = 0.0
	var tz: float = 0.0
	var hp: float = 0.0
	var face: float = 150.0
	var use_hover: bool = false
	var params: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids_arg = a.substr(6)
		elif a.begins_with("--style="):
			style = a.substr(8)
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
		elif a == "--hover":
			use_hover = true
		elif a.begins_with("--face="):
			face = a.substr(7).to_float()
		elif a.begins_with("--params="):
			for kv: String in a.substr(9).split(",", false):
				var eq: int = kv.find("=")
				var v: String = kv.substr(eq + 1)
				params[kv.substr(0, eq)] = _val(v)
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
	var ids: PackedStringArray = ids_arg.split(",", false)
	var arch_ids: PackedStringArray = PackedStringArray()
	var hps: PackedFloat32Array = PackedFloat32Array()
	var styles: PackedStringArray = PackedStringArray()
	for i in ids.size():
		var spec: String = ids[i]
		var at: int = spec.find("@")
		var local: Dictionary = params.duplicate()
		var aid: String = spec if at < 0 else spec.substr(0, at)
		if at >= 0:
			for kv: String in spec.substr(at + 1).split(";", false):
				var eq: int = kv.find("=")
				var v: String = kv.substr(eq + 1)
				local[kv.substr(0, eq)] = _val(v)
		arch_ids.append(aid)
		hps.append(float(local.get("_hp", hp)))
		local.erase("_hp")
		styles.append(str(local.get("_style", style)))
		local.erase("_style")
		var rec: Dictionary = {"schema": "meridian.recipe/1", "id": "proof.%d.%s" % [i, aid], "archetype": aid}
		if not local.is_empty():
			rec["params"] = local
		_book.add_recipe(rec, "shot")
	_book.link()
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_mats.setup(_book, q)
	var poses: PackedStringArray = ["rest", "action"] if pose_arg == "both" else [pose_arg]
	var n_cols: int = mini(cols, ids.size())
	var rows: int = ceili(float(ids.size()) / float(n_cols)) * poses.size()
	for pi in poses.size():
		for i in ids.size():
			var id: String = ids[i]
			var m: ViewModel = _builder.get_model(StringName("proof.%d.%s" % [i, arch_ids[i]]), StringName(styles[i]))
			var ent: Object = Entity.new()
			ent.style_id = StringName(styles[i])
			ent.team_index = team_id
			_backend.add(ent, m, StringName(styles[i]), ViewTeamColors.color(ent.team_index), ent.team_index)
			var gx: float = (float(i % n_cols) - float(n_cols - 1) * 0.5) * cell
			var gz: float = (float(i / n_cols) * poses.size() + float(pi) - float(rows - 1) * 0.5) * cell
			ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(face)), Vector3(gx, m.info.hover if use_hover else 0.4, gz))
			ent.damage = hps[i]
			if poses[pi] == "action":
				_action(ent, m)
			elif m.info.has_part(ViewMeshBuilder.Part.ROTOR):
				ent.spin_angle = 0.6
			_push(ent)
			_ents.append(ent)
			var sock: PackedStringArray = PackedStringArray()
			for k: Variant in m.info.sockets:
				sock.append(str(k))
			sock.sort()
			if pi == 0:
				print("  %s@%s tris=%s v=%d h=%.2f r=%.2f build=%.1fms members=%d%s\n     sockets: %s" % [id, style, m.info.tris, m.info.verts,
					m.info.height, m.info.radius, m.info.build_ms, m.info.members, " PLACEHOLDER " + m.error if m.placeholder else "", " ".join(sock)])
	var fit: float = maxf(float(n_cols) * cell * 1.0, float(rows) * cell * 1.9 * sin(deg_to_rad(pitch)))
	_aim(Vector3(tx, 1.2, tz), dist if dist > 0.0 else fit, pitch, yaw, 34.0)


func _val(v: String) -> Variant:
	if v.is_valid_float():
		return v.to_float()
	if v == "true" or v == "false":
		return v == "true"
	return v


func _action(ent: Object, m: ViewModel) -> void:
	ent.deploy = 1.0
	ent.turret_yaw = deg_to_rad(-28.0)
	ent.recoil = 0.55
	ent.elevation = 0.8
	ent.spin_angle = 1.1
	ent.move01 = 1.0
	ent.roll_m = 0.45
	ent.mnt = PackedFloat32Array([deg_to_rad(40.0), 0.7, 0.5, deg_to_rad(-35.0), 0.6, 0.5, deg_to_rad(20.0), 0.5, 0.4])
	if m.info.members > 1 and m.info.members > 0:
		ent.roll_m = 0.37
