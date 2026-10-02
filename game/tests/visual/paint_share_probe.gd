extends SceneTree
## VQ2A probe: top-projected paint shares of the unit / structure models of every roster style (which palette role dominates the plan
## view). `tools/gd run res://tests/visual/paint_share_probe.gd -- [styles_csv]` prints, per style, the top paints with share and the
## nearest palette role. Used to calibrate ViewTeamContrast.PAINT_ROLES.

func _init() -> void:
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var want: PackedStringArray = (OS.get_cmdline_user_args()[0].split(",") if OS.get_cmdline_user_args().size() > 0 else PackedStringArray(["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]))
	for sid: String in want:
		var fac: String = sid.get_slice(".", 0)
		var shares: Dictionary = {}
		var total: float = 0.0
		var pal: Dictionary = book.style(StringName(sid)).get("palette", {}) as Dictionary
		for rid: String in book.ids():
			if not (rid.begins_with("unit.%s." % fac) or rid.begins_with("structure.%s." % fac)):
				continue
			var o: Dictionary = ViewModelBuilder.build_data(book, StringName(rid), StringName(sid), 10000)
			if o["placeholder"] as bool:
				continue
			var arr: Array = (o["mesh"] as Dictionary)["arrays"] as Array
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR] as PackedColorArray
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			var i: int = 0
			while i + 2 < idx.size():
				var a: Vector3 = pos[idx[i]]
				var b: Vector3 = pos[idx[i + 1]]
				var c: Vector3 = pos[idx[i + 2]]
				var n: Vector3 = (b - a).cross(c - a)
				var nl: float = n.length()
				if nl > 1e-9 and n.y / nl < -0.3 and col[idx[i]].a < 0.5:
					var area: float = -n.y * 0.5
					var cc: Color = col[idx[i]]
					var key: String = Color(roundf(cc.r * 15.0) / 15.0, roundf(cc.g * 15.0) / 15.0, roundf(cc.b * 15.0) / 15.0).to_html(false)
					shares[key] = float(shares.get(key, 0.0)) + area
					total += area
				i += 3
		var keys: Array = shares.keys()
		keys.sort_custom(func(x: Variant, y: Variant) -> bool: return (shares[x] as float) > (shares[y] as float))
		var line: PackedStringArray = PackedStringArray()
		for k: Variant in keys.slice(0, 5):
			var near: String = ""
			var bd: float = INF
			for role: String in pal:
				var d: float = ViewTeamColors.delta_e00(Color(str(k)), Color(str(pal[role])))
				if d < bd:
					bd = d
					near = role
			line.append("%s %.0f%% (%s %.0f)" % [k, 100.0 * (shares[k] as float) / maxf(total, 0.001), near, bd])
		print("%-5s base=%s sec=%s | %s" % [sid, str(pal.get("base", "")), str(pal.get("sec", "")), " | ".join(line)])
	quit()
