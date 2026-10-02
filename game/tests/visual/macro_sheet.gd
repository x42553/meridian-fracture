extends "res://tests/visual/lineup_models.gd"
## VIEW-M4 contact sheet: every structure / ship / landmark macro rendered through the REAL recipe pipeline (in-memory test
## archetypes -> ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend). One model per macro (or macro variant) on a grid.
## `tools/gd shot res://tests/visual/macro_sheet.tscn out.png --size 1920x1080 -- --sheet=structures|ships|superweapons|defences|parts
## [--style=napc] [--cam=N --yaw=N --pitch=N --tx=N --tz=N] [--only=name] [--pose=action|rest]`

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null
var _sheet: String = "structures"
var _style: StringName = &"napc"
var _only: String = ""
var _items: Array = []


static func sheet_items(sheet: String) -> Array:
	var f: Dictionary = {"call": "foundation", "args": {"fw": 3, "fh": 3}}
	var out: Array = []
	match sheet:
		"parts":
			out = [
				["foundation", 2, 2, [f_with(2, 2)]],
				["wall_block", 2, 2, [f_with(2, 2), {"call": "wall_block", "args": {"center": [0, 1.9, 0], "size": [4.5, 3.4, 4.5]}}]],
				["roller_door", 3, 3, [f_with(3, 3), {"call": "wall_block", "args": {"center": [0, 1.9, -1.95], "size": [7.4, 3.6, 4.9]}},
					{"call": "roller_door", "args": {"center": [0, 0.16, 1.0]}}]],
				["window_strip", 2, 2, [f_with(2, 2), {"call": "wall_block", "args": {"center": [0, 1.9, 0], "size": [4.5, 3.4, 4.5]}},
					{"call": "window_strip", "args": {"center": [0, 2.4, 2.3], "n": 4}}, {"call": "window_strip", "args": {"center": [2.3, 2.4, 0], "n": 3, "dir": 90}}]],
				["stack+silo", 2, 2, [f_with(2, 2), {"call": "stack", "args": {"center": [-1.4, 0.16, 0], "r": 0.4, "h": 4.5}},
					{"call": "silo", "args": {"center": [1.0, 0.16, 0], "r": 0.9, "h": 4.5}}]],
				["silo_cluster", 3, 3, [f_with(3, 3), {"call": "silo_cluster", "args": {"center": [0, 0.16, -0.5], "n": 5, "r": 0.8, "h": 5}}]],
				["crane jib", 3, 3, [f_with(3, 3), {"call": "crane", "args": {"center": [-2.5, 0.16, 0], "reach": 6, "h": 6}}]],
				["crane gantry", 3, 3, [f_with(3, 3), {"call": "crane", "args": {"center": [0, 0.16, -1.0], "reach": 6, "h": 5, "kind": "gantry"}}]],
				["pads", 3, 3, [f_with(3, 3), {"call": "pad", "args": {"center": [-2.6, 0.16, -2.0], "mark": "ring"}},
					{"call": "pad", "args": {"center": [0.2, 0.16, -2.0], "mark": "h"}}, {"call": "pad", "args": {"center": [2.6, 0.16, -2.0], "mark": "x"}},
					{"call": "pad", "args": {"center": [0, 0.16, 2.0], "size": [5.0, 0.04, 3.0], "mark": "runway"}}]],
				["dome_shell", 2, 2, [f_with(2, 2), {"call": "dome_shell", "args": {"center": [0, 0.16, 0], "r": 2.0, "lens": 1}}]],
				["pylon_ring", 3, 3, [f_with(3, 3), {"call": "pylon_ring", "args": {"center": [0, 0.16, 0], "r": 3.2, "n": 6}}]],
				["launch_rail", 3, 3, [f_with(3, 3), {"call": "launch_rail", "args": {"center": [0, 1.0, 2.0], "len": 6, "elev": 25}}]],
				["turret_base", 2, 2, [f_with(2, 2), {"call": "turret_base", "args": {"center": [0, 0.16, 0], "r": 1.6, "h": 1.0}}]],
				["pennant+beacon+plate", 2, 2, [f_with(2, 2), {"call": "wall_block", "args": {"center": [0, 1.4, 0], "size": [4.5, 2.4, 4.5]}},
					{"call": "roof_plate", "args": {"center": [0, 2.78, 0.4], "size": [2.0, 0.03, 1.6]}},
					{"call": "pennant", "args": {"pos": [-1.9, 2.72, -1.9]}}, {"call": "beacon", "args": {"pos": [1.9, 2.72, -1.9]}}]],
				["conveyor+funnel", 3, 3, [f_with(3, 3), {"call": "conveyor", "args": {"from": [-3, 0.2, 1.5], "to": [1, 0.9, 1.5]}},
					{"call": "funnel", "args": {"center": [2.5, 0.16, 1.5]}}]],
				["lattice", 2, 2, [f_with(2, 2), {"call": "lattice", "args": {"center": [0, 0.16, 0], "h": 8}}]],
			]
		"ships":
			out = [
				["hull sharp", 0, 0, [{"call": "hull_ship", "args": {"len": 6, "beam": 2.2, "bow": "sharp"}},
					{"call": "superstructure", "args": {"center": [0, 0.8, 0.6]}}, {"call": "ship_turret", "args": {"pos": [0, 0.8, -1.8]}}]],
				["hull blunt", 0, 0, [{"call": "hull_ship", "args": {"len": 5, "beam": 2.6, "bow": "blunt", "freeboard": 0.6}},
					{"call": "superstructure", "args": {"center": [0, 0.6, 1.4], "tiers": 1}}, {"call": "vls", "args": {"center": [0, 0.62, -0.8], "rows": 4, "cols": 2}}]],
				["hull round", 0, 0, [{"call": "hull_ship", "args": {"len": 7, "beam": 2.6, "bow": "round", "draft": 0.5}},
					{"call": "superstructure", "args": {"center": [0, 0.8, 1.4], "tiers": 3, "len": 2.6}},
					{"call": "ship_turret", "args": {"pos": [0, 0.8, -2.4], "barrels": 2, "mount": 0}}, {"call": "vls", "args": {"center": [0, 0.82, -0.6], "rows": 5, "cols": 3}}]],
				["turrets 1/2/3", 0, 0, [{"call": "hull_ship", "args": {"len": 9, "beam": 3.0, "bow": "sharp", "freeboard": 1.0}},
					{"call": "ship_turret", "args": {"pos": [0, 1.0, -3.2], "barrels": 3, "mount": 0, "r": 0.6, "len": 2.0}},
					{"call": "ship_turret", "args": {"pos": [0, 1.0, -1.4], "barrels": 2, "mount": 1, "r": 0.5}}, {"call": "superstructure", "args": {"center": [0, 1.0, 1.2], "tiers": 3, "len": 3.2}}]],
				["carrier", 0, 0, [{"call": "hull_ship", "args": {"len": 12, "beam": 4.4, "bow": "blunt", "freeboard": 1.6, "draft": 0.8}},
					{"call": "flight_deck", "args": {"center": [-0.3, 1.6, 0.3], "len": 11, "wid": 3.8}},
					{"call": "superstructure", "args": {"center": [1.6, 1.78, 2.0], "len": 2.0, "wid": 1.0, "tiers": 3}},
					{"call": "deck_drones", "args": {"center": [-0.7, 1.78, -2.5], "n": 6}}]],
				["submarine", 0, 0, [{"call": "hull_ship", "args": {"len": 9, "beam": 2.2, "bow": "round", "freeboard": 0.5, "draft": 1.0}},
					{"call": "sail", "args": {"pos": [0, 0.5, -0.5]}}]],
			]
		"superweapons":
			out = []
			for n: String in ["sw_halo_tower", "sw_billboard", "sw_sunflower", "sw_gantry_silo", "sw_hive_tower", "sw_assembly_hall", "sw_long_barrel", "sw_three_masts"]:
				out.append([n, 4, 4, [f_with(4, 4), {"call": n}]])
		"defences":
			out = []
			for n: String in ["adv_bulwark_cannon", "adv_lance_rail", "adv_sunwall", "adv_citadel_mortar", "adv_sea_spear", "adv_dragon_tooth", "adv_forge_cannon", "adv_bastion_tower"]:
				out.append([n, 2, 2, [f_with(2, 2), {"call": n}]])
	if f.is_empty():
		return []
	return out


static func f_with(fw: int, fh: int) -> Dictionary:
	return {"call": "foundation", "args": {"fw": fw, "fh": fh}}


func _mesh(id: StringName, faction: StringName) -> Object:
	if _builder == null:
		_book = ViewRecipeBook.new()
		_book.load_all()
		for it: Variant in _items:
			var e: Array = it as Array
			var aid: String = "sheet." + (e[0] as String)
			_book.add_archetype({"schema": "meridian.archetype/1", "id": aid, "size_class": "structure" if (e[1] as int) > 0 else "ship", "ops": e[3]}, "sheet")
			_book.add_recipe({"schema": "meridian.recipe/1", "id": aid, "archetype": aid}, "sheet")
		_book.link()
		var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
		_builder = ViewModelBuilder.new()
		_builder.setup(_book, q)
		_mats.setup(_book, q)
	return _builder.get_model(StringName("sheet." + String(id)), faction)


func _ready() -> void:
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 50.0
	var tx: float = 0.0
	var tz: float = 0.0
	var pose_arg: String = "rest"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--sheet="):
			_sheet = a.substr(8)
		elif a.begins_with("--style="):
			_style = StringName(a.substr(8))
		elif a.begins_with("--only="):
			_only = a.substr(7)
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
	pose = pose_arg
	layout = 0  # unused: this script lays out its own sheet
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	_mats.setup(null, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	_items = sheet_items(_sheet)
	if _only != "":
		var keep: Array = []
		for it: Variant in _items:
			if (_only.split(",") as PackedStringArray).has((it as Array)[0] as String):
				keep.append(it)
		_items = keep
	var cols: int = 2 if _items.size() <= 4 else 4
	var cell: float = 15.0 if _sheet == "superweapons" else (9.0 if _sheet in ["defences", "parts"] else 14.0)
	var rows: int = ceili(float(_items.size()) / float(cols))
	for i in _items.size():
		var e: Array = _items[i] as Array
		var pos: Vector3 = Vector3((float(i % cols) - float(cols - 1) * 0.5) * cell, 0.0, (float(i / cols) - float(rows - 1) * 0.5) * cell)
		_place_sheet(StringName(e[0] as String), pos, e)
	var span: float = maxf(float(cols) * cell, float(rows) * cell)
	_aim(Vector3(tx, 2.0, tz), dist if dist > 0.0 else span * 1.45, pitch, yaw, 34.0)
	print("SHEET %s items=%d" % [_sheet, _items.size()])
	for i in _items.size():
		var m: ViewModel = _mesh(StringName((_items[i] as Array)[0] as String), _style) as ViewModel
		print("  %s tris=%s verts=%d h=%.2f r=%.2f parts=%d err=%s" % [(_items[i] as Array)[0], m.info.tris, m.info.verts, m.info.height, m.info.radius, m.info.parts_mask, m.error])


func _place_sheet(id: StringName, pos: Vector3, _e: Array) -> void:
	var ent: Object = Entity.new()
	ent.style_id = _style
	ent.team_index = team_id
	var model: Object = _mesh(id, _style)
	_backend.add(ent, model, _style, ViewTeamColors.color(ent.team_index), ent.team_index)
	ent.rig.transform = Transform3D(Basis.IDENTITY, pos)
	if pose == "action":
		ent.deploy = 1.0
		ent.turret_yaw = deg_to_rad(-25.0)
		ent.recoil = 0.5
		ent.elevation = 0.6
		ent.spin_angle = 1.1
	_push(ent)
	_ents.append(ent)
