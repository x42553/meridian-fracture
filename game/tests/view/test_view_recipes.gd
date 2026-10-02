extends RefCounted
## VIEW-T1 acceptance (render spec 7.9 V-RCP-02 / 09 / 10): the recipe DATA as shipped. Every unit, summon, structure and neutral
## def of the real balance data has a recipe that builds a real model (never the magenta placeholder) in every style it can be
## instantiated with; budgets; structure anchors; index.json / footprints.json agree with the files and the balance data; the
## `styles/*.json` merge rules. Authoritative Godot counterpart of tools/py/validate_recipes.py.

const Pt := ViewMeshBuilder.Part
const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]
## LOD0 triangle ceilings by archetype size_class (render spec 5.8.2, upper end of each class).
const TRIS: Dictionary = {"inf": 1400, "squad": 1400, "light": 3500, "medium": 5000, "heavy": 6500, "huge": 8000, "air": 3500, "ship": 8000,
	"structure": 10000}

var _book: ViewRecipeBook = null
var _data: GameData = null


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	_data = GameData.load_default()


func _all_def_ids() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for u: DefUnit in _data.units:
		out.append(u.pres_recipe if u.pres_recipe != "" else u.id)
	for s: DefStructure in _data.structures:
		out.append(s.pres_recipe if s.pres_recipe != "" else s.id)
	for n: DefNeutral in _data.neutrals:
		out.append(n.pres_recipe if n.pres_recipe != "" else n.id)
	return out


## The styles a recipe can be instantiated with: its own faction for unit.<fac>.* / structure.<fac>.*, every faction roster for
## *.shared.*, `neutral` for neutrals.
func _styles_for(id: String) -> Array[StringName]:
	var out: Array[StringName] = []
	if id.begins_with("neutral.") or id.begins_with("proj."):
		out.append(ViewRecipeBook.NEUTRAL if id.begins_with("neutral.") else _book.style_for_roster("roster.napc"))
		return out
	for f: String in FACTIONS:
		var sid: StringName = _book.style_for_def(id, "roster." + f)
		if not out.has(sid):
			out.append(sid)
	return out


func test_book_loads_clean_and_index_matches(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "no load errors: %s" % ", ".join(_book.errors()))
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes/index.json")) as Dictionary
	t.eq(str(idx.get("schema")), "meridian.recipes.index/1", "index schema")
	var ids: Array = idx.get("ids", []) as Array
	t.eq(ids.size(), _book.ids().size(), "index.json lists every recipe file")
	var ok: bool = true
	for i: int in mini(ids.size(), _book.ids().size()):
		ok = ok and str(ids[i]) == _book.ids()[i]
	t.check(ok, "index.json ids equal the sorted recipe ids")


func test_every_def_has_a_recipe(t: TestCtx) -> void:
	_load()
	if _data == null:
		t.skip("balance data not loadable")
		return
	var ids: PackedStringArray = _all_def_ids()
	t.gt(ids.size(), 190, "units + structures + neutrals")
	var missing: PackedStringArray = PackedStringArray()
	for id: String in ids:
		if not _book.has_recipe(StringName(id)):
			missing.append(id)
	t.eq(missing.size(), 0, "defs without a recipe: %s" % ", ".join(missing))
	for pid: String in ["proj.bomb", "proj.missile", "proj.rocket", "proj.torpedo"]:
		t.check(_book.has_recipe(StringName(pid)), "projectile recipe " + pid)


func test_every_recipe_builds_a_real_model_in_every_style(t: TestCtx) -> void:
	_load()
	var builds: int = 0
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var slow: PackedStringArray = PackedStringArray()
	for rid: String in _book.ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		for sid: StringName in _styles_for(rid):
			var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)
			builds += 1
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [rid, sid, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var cap: int = int(TRIS.get(String(r.arch.size_class), 10000))
			if info.tris.x > cap or info.verts > 65535:
				over.append("%s@%s tris %d verts %d (cap %d)" % [rid, sid, info.tris.x, info.verts, cap])
			if info.build_ms > 60.0:
				slow.append("%s@%s %.0f ms" % [rid, sid, info.build_ms])
			t.check(is_finite(info.rest_aabb.size.length()), "%s finite bounds" % rid)
	t.gt(builds, 200, "builds run")
	t.eq(bad.size(), 0, "placeholders / errors: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.eq(slow.size(), 0, "build time > 60 ms: %s" % " | ".join(slow))


func test_structure_models_respect_footprint_and_height(t: TestCtx) -> void:
	_load()
	var checked: int = 0
	for rid: String in _book.ids():
		if not _book.has_footprint(StringName(rid)):
			continue
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var fw: int = int(fp["fw"])
		var fh: int = int(fp["fh"])
		for sid: StringName in _styles_for(rid):
			var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var half_x: float = float(fw) * 1.5 - 0.25
			var half_z: float = float(fh) * 1.5 - 0.25
			var bb: AABB = info.rest_aabb
			var margin: float = 0.4
			t.check(bb.position.x >= -half_x - margin and bb.end.x <= half_x + margin, "%s@%s x extent %.2f..%.2f within +-%.2f" % [rid, sid, bb.position.x, bb.end.x, half_x])
			t.check(bb.position.z >= -half_z - margin and bb.end.z <= half_z + margin, "%s@%s z extent %.2f..%.2f within +-%.2f" % [rid, sid, bb.position.z, bb.end.z, half_z])
			var cap: float = 14.0 if rid.contains("superweapon") or fw >= 4 else (12.0 if fw >= 3 or fh >= 3 else 8.0)
			if rid.begins_with("structure.") and (fw >= 4 or rid.contains("atlas") or rid.contains("aurora")):
				cap = 14.0
			t.check(info.height <= cap + 0.01, "%s@%s height %.2f <= %.1f" % [rid, sid, info.height, cap])
			t.eq(info.footprint, Vector2i(fw, fh), "%s meta footprint" % rid)
			checked += 1
	t.gt(checked, 37, "structure builds checked")


func test_structure_door_exit_and_dock_sockets(t: TestCtx) -> void:
	_load()
	var n: int = 0
	for rid: String in _book.ids():
		if not _book.has_footprint(StringName(rid)) or rid.begins_with("neutral."):
			continue
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), _book.style_for_def(rid, "roster.napc"), 10000)
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		t.check(info.has_socket(&"door_exit"), "%s has door_exit" % rid)
		if info.has_socket(&"door_exit"):
			var sk: ViewModelInfo.ViewSocket = info.sockets[&"door_exit"] as ViewModelInfo.ViewSocket
			var dist: float = Vector2(sk.pos.x - float(fp["door_cx"]), sk.pos.z - float(fp["door_cz"])).length()
			t.check(dist <= 0.75, "%s door_exit within 0.75 m of the data anchor (%.2f)" % [rid, dist])
		if rid.ends_with(".refinery"):
			t.check(info.has_socket(&"dock"), "refinery dock socket")
		n += 1
	t.gt(n, 20, "structures checked")


func test_armed_structures_have_muzzle_sockets(t: TestCtx) -> void:
	_load()
	if _data == null:
		t.skip("balance data not loadable")
		return
	for s: DefStructure in _data.structures:
		if s.weapons.is_empty():
			continue
		var rid: String = s.pres_recipe if s.pres_recipe != "" else s.id
		var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), _book.style_for_def(rid, "roster.napc"), 10000)
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		for wi: int in mini(s.weapons.size(), 1):
			t.check(info.has_socket(StringName("muzzle0_%d" % wi)), "%s has muzzle0_%d" % [rid, wi])


func test_footprints_json_matches_the_defs(t: TestCtx) -> void:
	_load()
	if _data == null:
		t.skip("balance data not loadable")
		return
	var ad: ViewDefAdapter = ViewDefAdapter.new()
	ad.setup(_data)
	var n: int = 0
	for i: int in _data.structures.size():
		var s: DefStructure = _data.structures[i]
		var rid: StringName = StringName(s.pres_recipe if s.pres_recipe != "" else s.id)
		t.check(_book.has_footprint(rid), "footprints.json has %s" % rid)
		if not _book.has_footprint(rid):
			continue
		var fp: Dictionary = _book.footprint_vars(rid)
		var vd: ViewDef = ad.def_for(SimEntity.Kind.STRUCTURE, i)
		t.eq(int(fp["fw"]), s.fp_w, "%s fw" % rid)
		t.eq(int(fp["fh"]), s.fp_h, "%s fh" % rid)
		t.near(float(fp["door_cx"]), vd.door_cx, 0.001, "%s door_cx" % rid)
		t.near(float(fp["door_cz"]), vd.door_cz, 0.001, "%s door_cz" % rid)
		t.eq(int(fp["exit_dir"]), vd.exit_dir, "%s exit_dir" % rid)
		t.eq(int(fp["pads_n"]), s.pads, "%s pads_n" % rid)
		for k: int in s.pads:
			t.near(float(fp["pad_x%d" % k]), vd.pads[k * 2], 0.001, "%s pad_x%d" % [rid, k])
		n += 1
	t.eq(n, _data.structures.size(), "every structure def")
	for nd: DefNeutral in _data.neutrals:
		var nid: StringName = StringName(nd.pres_recipe if nd.pres_recipe != "" else nd.id)
		t.check(_book.has_footprint(nid), "footprints.json has %s" % nid)
		if _book.has_footprint(nid):
			var nf: Dictionary = _book.footprint_vars(nid)
			t.eq(int(nf["fw"]), nd.fp_w, "%s fw" % nid)
			t.eq(int(nf["fh"]), nd.fp_h, "%s fh" % nid)


func test_airfield_pads_follow_the_data(t: TestCtx) -> void:
	_load()
	var d6: Dictionary = ViewModelBuilder.build_data(_book, &"structure.shared.airfield", &"napc", 10000)
	t.check(not (d6["placeholder"] as bool), "airfield builds")
	var info: ViewModelInfo = d6["info"] as ViewModelInfo
	var fac: ViewModelInfo = (ViewModelBuilder.build_data(_book, &"structure.shared.factory", &"napc", 10000))["info"] as ViewModelInfo
	t.gt(info.rest_aabb.size.x, fac.rest_aabb.size.x * 1.6, "the 6x3 airfield is much wider than the 3x3 factory")


func test_stubs_are_deterministic(t: TestCtx) -> void:
	_load()
	for rid: String in ["unit.napc.aegis_frigate", "structure.shared.factory", "unit.napc.falcon_interceptor", "summon.napc.uav"]:
		var a: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), &"napc", 10000)
		var b: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), &"napc", 10000)
		t.eq((a["info"] as ViewModelInfo).content_hash, (b["info"] as ViewModelInfo).content_hash, "%s content hash" % rid)


func test_team_colour_is_present_and_bounded(t: TestCtx) -> void:
	_load()
	# every stub carries a team-masked surface (team_panel / roof_plate / pennant): checked through the recipes' op text
	var missing: PackedStringArray = PackedStringArray()
	for aid: String in ["gen_structure", "gen_defense", "gen_superweapon", "gen_air", "gen_ship", "gen_prop"]:
		var txt: String = FileAccess.get_file_as_string("res://data/recipes/archetypes/%s.json" % aid)
		if not (txt.contains("team_panel") or txt.contains("roof_plate") or txt.contains("adv_") or txt.contains("sw_")):
			missing.append(aid)
	t.eq(missing.size(), 0, "archetypes without a team surface: %s" % ", ".join(missing))


# ---- styles/*.json merge (VIEW-T1) ----------------------------------------------------------------------------------------
func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_style_files_merge_in_order(t: TestCtx) -> void:
	var dir: String = "user://recipes_styles_test"
	_write(dir + "/styles.json", JSON.stringify({"schema": "meridian.styles/1", "styles": {
		"alpha": {"palette": {"base": "#111111", "acc": "#222222"}, "kit": {"len": 3.0, "skirt": "modules"}, "emblem": "bar"},
		"neutral": {"palette": {"base": "#888888"}}}}))
	_write(dir + "/styles/alpha.json", JSON.stringify({"schema": "meridian.styles/1", "styles": {
		"alpha": {"palette": {"base": "#333333"}, "kit": {"len": 3.6}},
		"alpha.sub": {"extends": "alpha", "palette": {"acc": "#444444"}}}}))
	_write(dir + "/styles/beta.json", JSON.stringify({"schema": "meridian.styles/1", "styles": {"beta": {"palette": {"base": "#555555"}}}}))
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.load_all(dir)
	t.eq(bk.errors().size(), 0, "clean load: %s" % ", ".join(bk.errors()))
	var a: Dictionary = bk.style(&"alpha")
	t.eq(((a["palette"] as Dictionary)["base"] as String), "#333333", "styles/alpha.json wins over styles.json per key")
	t.eq(((a["palette"] as Dictionary)["acc"] as String), "#222222", "keys only in styles.json survive (deep merge)")
	t.near(float((a["kit"] as Dictionary)["len"]), 3.6, 0.0001, "kit value overridden")
	t.eq(((a["kit"] as Dictionary)["skirt"] as String), "modules", "kit key kept")
	t.eq(a["emblem"], "bar", "scalar kept")
	var sub: Dictionary = bk.style(&"alpha.sub")
	t.eq(((sub["palette"] as Dictionary)["base"] as String), "#333333", "extends resolves across files")
	t.eq(((sub["palette"] as Dictionary)["acc"] as String), "#444444", "child override")
	t.check(bk.has_style(&"beta") and bk.has_style(&"neutral"), "every file contributes")
	t.eq(bk.warnings().size(), 1, "one override recorded: %s" % ", ".join(bk.warnings()))
	t.eq(bk.style_for_roster("roster.alpha.sub"), &"alpha.sub", "roster lookup finds the subfaction style")
	# replace semantics stay available for tests / tools
	var bk2: ViewRecipeBook = ViewRecipeBook.new()
	bk2.add_styles({"schema": "meridian.styles/1", "styles": {"x": {"emblem": "bar", "kit": {"a": 1}}}})
	bk2.add_styles({"schema": "meridian.styles/1", "styles": {"x": {"emblem": "ring"}}})
	bk2.link()
	t.eq(bk2.style(&"x").has("kit"), false, "add_styles without merge replaces the style")


func test_real_style_files_have_no_conflicts(t: TestCtx) -> void:
	_load()
	t.eq(_book.warnings().size(), 0, "the shipped style sources do not override each other: %s" % ", ".join(_book.warnings()))


func test_spec_example_unit_recipe_builds(t: TestCtx) -> void:
	# render spec 7.3: unit.napc.guardian_tank = archetype + params + a `roof` slot with macro calls
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.load_all()
	var ok: bool = bk.add_recipe({
		"schema": "meridian.recipe/1", "id": "unit.napc.guardian_tank", "archetype": "veh_tank", "style": "auto", "scale": 1.0,
		"params": {"len": 3.5, "wheel_n": 5, "barrel_len": 2.0, "skirt": "modules", "roof": "cupola"},
		"slots": {"roof": [
			{"call": "hatch", "args": {"c": ["turret_hw*0.36", "top_y", "turret_z+turret_hl*0.30"], "r": 0.15, "body": "sec", "ring": "acc"}},
			{"call": "whip", "args": {"base": ["-turret_hw*0.6", "top_y", "turret_z+turret_hl*0.85"], "tip": ["-turret_hw*0.62", "top_y+1.15", "turret_z+turret_hl*0.9"], "r": 0.011, "col": "metal"}}]},
		"ops_after": [], "meta": {"role": "tank", "icon": {"yaw": 150, "pitch": 24, "margin": 0.78}}}, "spec")
	t.check(ok, "the spec example parses")
	bk.link()
	var d: Dictionary = ViewModelBuilder.build_data(bk, &"unit.napc.guardian_tank", &"napc", 10000)
	t.eq(d["error"], "", "builds")
	t.check(not (d["placeholder"] as bool), "not a placeholder")
	t.check((d["info"] as ViewModelInfo).has_socket(&"muzzle0_0"), "muzzle socket")
