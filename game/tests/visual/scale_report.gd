extends SceneTree
## VQ2A tool: real model sizes of every shipped unit / structure recipe vs the sim radius / footprint.
## `tools/gd run res://tests/visual/scale_report.gd -- [csv_path]`; prints per-class medians and writes a CSV
## (id, kind, class, r_m, L, W, H, ratio_L_to_2r, fp_w, fp_h, fp_m_w, tris).

func _init() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var data: GameData = GameData.load_default()
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var rows: PackedStringArray = PackedStringArray(["id,kind,class,r_m,L,W,H,L_over_2r,fp_w,fp_h,tris,archetype"])
	var by_class: Dictionary = {}
	for u: DefUnit in data.units:
		var rid: StringName = StringName(u.pres_recipe if u.pres_recipe != "" else u.id)
		var sty: StringName = book.style_for_def(u.id, "")
		var o: Dictionary = ViewModelBuilder.build_data(book, rid, sty, u.pres_scale_bp)
		if o["placeholder"] as bool:
			continue
		var mi: ViewModelInfo = o["info"] as ViewModelInfo
		var bb: AABB = mi.rest_aabb
		var r_m: float = float(u.radius) * ViewConsts.M_PER_UNIT
		var rec: ViewRecipe = book.recipe(rid)
		var arch: String = String(rec.arch.id) if rec != null and rec.arch != null else ""
		var cls: String = String(o["size_class"])
		rows.append("%s,u,%s,%.2f,%.2f,%.2f,%.2f,%.2f,0,0,%d,%s" % [u.id, cls, r_m, bb.size.z, bb.size.x, bb.position.y + bb.size.y, bb.size.z / (2.0 * r_m), mi.tris.x, arch])
		if not by_class.has(cls):
			by_class[cls] = []
		(by_class[cls] as Array).append([bb.size.z, bb.size.x, bb.position.y + bb.size.y, r_m])
	for s: DefStructure in data.structures:
		var rid2: StringName = StringName(s.pres_recipe if s.pres_recipe != "" else s.id)
		var sty2: StringName = book.style_for_def(s.id, "")
		var o2: Dictionary = ViewModelBuilder.build_data(book, rid2, sty2, 10000)
		if o2["placeholder"] as bool:
			continue
		var mi2: ViewModelInfo = o2["info"] as ViewModelInfo
		var bb2: AABB = mi2.rest_aabb
		rows.append("%s,s,%s,%.2f,%.2f,%.2f,%.2f,0,%d,%d,%d," % [s.id, String(o2["size_class"]), float(s.radius) * ViewConsts.M_PER_UNIT, bb2.size.z, bb2.size.x, bb2.position.y + bb2.size.y, s.fp_w, s.fp_h, mi2.tris.x])
	var keys: Array = by_class.keys()
	keys.sort()
	for k: Variant in keys:
		var a: Array = by_class[k] as Array
		var L: float = 0.0
		var W: float = 0.0
		var H: float = 0.0
		var R: float = 0.0
		for e: Variant in a:
			var ea: Array = e as Array
			L += ea[0] as float
			W += ea[1] as float
			H += ea[2] as float
			R += ea[3] as float
		var n: float = float(a.size())
		print("%-12s n=%3d  mean L=%.2f W=%.2f H=%.2f  r=%.2f m" % [k, a.size(), L / n, W / n, H / n, R / n])
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(rows) + "\n")
		f.close()
	quit()
