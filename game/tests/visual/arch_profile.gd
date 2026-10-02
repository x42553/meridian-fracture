extends SceneTree
## VIEW-M5 / M6 tool: LOD0 triangle cost per top-level op of an archetype (prefix builds).
## `tools/gd run res://tests/visual/arch_profile.gd -- veh_apc [napc] [min_delta=40] [fw fh]` (structures: footprint in cells, default 3x3)

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "veh_tank"
	var style: String = args[1] if args.size() > 1 else "napc"
	var min_delta: int = args[2].to_int() if args.size() > 2 else 40
	var fw: int = args[3].to_int() if args.size() > 3 else 3
	var fh: int = args[4].to_int() if args.size() > 4 else fw
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes/archetypes/%s.json" % id)) as Dictionary
	var ops: Array = src["ops"] as Array
	var prev: int = 0
	var last_hash: int = 0
	for k in ops.size():
		var d: Dictionary = src.duplicate(true)
		d["id"] = "prof_arch"
		d["ops"] = ops.slice(0, k + 1)
		var bk: ViewRecipeBook = ViewRecipeBook.new()
		bk.load_all()
		bk.add_archetype(d, "prof")
		bk.add_recipe({"schema": "meridian.recipe/1", "id": "prof.r", "archetype": "prof_arch"}, "prof")
		if id.begins_with("str_"):
			var dz: float = (float(fh) * 0.5 + 0.5) * 3.0
			var dx: float = (0.5 - float(fw) * 0.5) * 3.0
			bk.add_footprints({"schema": "meridian.footprints/1", "structures": {"prof.r": {"fw": fw, "fh": fh, "door_cx": dx, "door_cz": dz,
				"exit_dir": 1024, "dock_cx": dx, "dock_cz": dz, "dock_dir": 1024, "pads_n": 0}}}, "prof")
		bk.link()
		var out: Dictionary = ViewModelBuilder.build_data(bk, &"prof.r", StringName(style), 10000)
		if out["placeholder"] as bool:
			print("op %d: ERROR %s" % [k, out["error"]])
			continue
		var info: ViewModelInfo = out["info"] as ViewModelInfo
		var t: int = info.tris.x
		if t - prev >= min_delta:
			print("op %2d %5d  %s" % [k, t - prev, JSON.stringify(ops[k]).substr(0, 110)])
		prev = t
		last_hash = info.verts
	print("TOTAL tris=%d verts=%d" % [prev, last_hash])
	quit()
