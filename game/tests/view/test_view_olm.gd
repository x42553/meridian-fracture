extends RefCounted
## VIEW-M8 (OLM) acceptance: the 19 unit recipes, the 2 faction structures and the OLM style overlays (`styles/olm.json`).
## Hand-authored (no stub flag), builds in the faction style and the three subfaction styles, per-model triangle budgets (render 5.8.2),
## a muzzle socket for every weapon mount, team surface bounded and separated from the ivory / teal / copper paint, palette against the
## bible's visual direction, shared structures wearing the OLM dialect inside their footprint.

const STYLES: Array[StringName] = [&"olm", &"olm.saudi_arabia", &"olm.algeria", &"olm.el_andalus"]
## view archetype -> [LOD0 cap, LOD1 cap] (render.md 5.8.2)
const CAPS: Dictionary = {
	"inf_rifle": [1400, 800], "inf_at": [1400, 800], "inf_support": [1400, 800], "veh_apc": [3500, 2000], "veh_tank": [5000, 2800],
	"veh_aa": [5000, 2800], "veh_lightarty": [3500, 2000], "veh_siege": [6500, 3600], "air_jet": [3000, 1700], "air_bomber": [3000, 1700],
	"ship_patrol": [2000, 1200], "ship_escort": [5000, 2800], "ship_siege": [8000, 4500],
	"str_superweapon": [10000, 5500], "str_defense_adv": [3400, 1800],  # the sunwall macro landmark itself is 3308 / 1730
}
const BIBLE: Dictionary = {"base": "#d9caa6", "acc": "#b3663a", "dark": "#0f4d54"}  ## render.md 5.8.4: ivory, copper, deep teal
var _book: ViewRecipeBook = null
var _data: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false
	ViewExpr.quiet = false


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance/units_olm.json"))
	_data = d as Dictionary


func _ids() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for id: String in _book.ids():
		if id.begins_with("unit.olm.") or id.begins_with("structure.olm."):
			out.append(id)
	return out


func _build(id: String, style: StringName) -> Dictionary:
	return ViewModelBuilder.build_data(_book, StringName(id), style, 10000)


func test_all_nineteen_units_and_two_structures_are_hand_authored(t: TestCtx) -> void:
	_load()
	var ids: PackedStringArray = _ids()
	var units: int = 0
	for id: String in ids:
		if id.begins_with("unit."):
			units += 1
		var txt: String = FileAccess.get_file_as_string("res://data/recipes/%s.json" % id)
		t.check(not txt.contains("\"stub\""), "%s is hand-authored (no stub flag)" % id)
	t.eq(units, 19, "13 baseline + 6 unique subfaction units")
	t.eq(ids.size(), 21, "19 units and the two faction structures")
	for u: Variant in _data.get("units", []) as Array:
		t.check(_book.has_recipe(StringName(str((u as Dictionary).get("id")))), "%s has a recipe" % (u as Dictionary).get("id"))


func test_every_recipe_builds_in_the_faction_and_subfaction_styles_within_budget(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var n: int = 0
	for id: String in _ids():
		var r: ViewRecipe = _book.recipe(StringName(id))
		var cap: Array = CAPS.get(String(r.archetype), [10000, 5500]) as Array
		for st: StringName in STYLES:
			var d: Dictionary = _build(id, st)
			n += 1
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [id, st, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			if info.tris.x - info.livery_tris.x > int(cap[0]) or info.tris.y - info.livery_tris.y > int(cap[1]) or info.verts > 65535:
				over.append("%s@%s tris %d/%d (cap %d/%d)" % [id, st, info.tris.x, info.tris.y, int(cap[0]), int(cap[1])])
	t.gt(n, 80, "builds")
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over the per-model triangle budget: %s" % " | ".join(over))


func test_every_weapon_mount_has_a_muzzle_socket_and_units_have_a_top_socket(t: TestCtx) -> void:
	_load()
	for u: Variant in _data.get("units", []) as Array:
		var ud: Dictionary = u as Dictionary
		var id: String = str(ud.get("id"))
		var info: ViewModelInfo = _build(id, &"olm")["info"] as ViewModelInfo
		var mounts: int = (ud.get("weapons", []) as Array).size()
		for m: int in mounts:
			t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s has muzzle%d_0" % [id, m])
		t.check(info.has_socket(&"top"), "%s has a top socket" % id)


func _team_share(d: Dictionary) -> Vector2:
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var up_team: float = 0.0
	var up_all: float = 0.0
	var i: int = 0
	while i + 2 < idx.size():
		var a: Vector3 = pos[idx[i]]
		var n: Vector3 = (pos[idx[i + 1]] - a).cross(pos[idx[i + 2]] - a)
		if n.length() > 1e-9 and n.y / n.length() < -0.3:
			up_all += absf(n.y) * 0.5
			if col[idx[i]].a > 0.5 and col[idx[i + 1]].a > 0.5 and col[idx[i + 2]].a > 0.5:
				up_team += absf(n.y) * 0.5
		i += 3
	return Vector2(up_team, up_all)


func test_team_surface_is_present_bounded_and_separated_from_the_faction_paint(t: TestCtx) -> void:
	_load()
	var pal: Dictionary = (_book.style(&"olm")["palette"] as Dictionary)
	var plate: Color = Color(str(pal["plate"]))
	# 1. every one of the 12 default player colours stands clear of the dark plate border the team_panel macro emits
	for c: int in 12:
		var tc: Color = ViewTeamColors.color(c)
		t.gt(ViewTeamColors.delta_e(tc, plate), 35.0, "player colour %d against the OLM plate border" % c)
	# 2. against the ivory hull the authored separation is reported (white is the known weak pair: art_direction 5.4.4) ...
	var worst: float = INF
	for c: int in 12:
		worst = minf(worst, ViewTeamColors.delta_e(ViewTeamColors.color(c), Color(str(pal["base"]))))
	t.note("OLM ivory vs the 12 player colours: worst dE76 %.1f (white 11 is carried by the plate border)" % worst)
	# 3. every recipe carries a team surface of a sane size
	for id: String in _ids():
		var sh: Vector2 = _team_share(_build(id, &"olm"))
		t.gt(sh.x, 0.0, "%s carries a team-coloured surface" % id)
		var frac: float = sh.x / maxf(sh.y, 0.0001)
		t.check(frac > 0.008 and frac < 0.30, "%s team-masked share of the top-projected area %.1f percent" % [id, frac * 100.0])


func test_palette_matches_the_bible_visual_direction(t: TestCtx) -> void:
	_load()
	var pal: Dictionary = (_book.style(&"olm")["palette"] as Dictionary)
	for k: Variant in BIBLE:
		var de: float = ViewTeamColors.delta_e(Color(str(pal[k])), Color(str(BIBLE[k])))
		t.lt(de, 12.0, "palette %s %s is within dE76 12 of the bible colour %s (got %.1f)" % [k, pal[k], BIBLE[k], de])
	# ivory hull, copper trim, teal cloth: hue families (degrees) of the three brand colours
	var base: Color = Color(str(pal["base"]))
	var acc: Color = Color(str(pal["acc"]))
	var sec: Color = Color(str(pal["sec"]))
	t.check(base.h > 0.08 and base.h < 0.17 and base.s < 0.3, "ivory: warm, low chroma")
	t.check(acc.h > 0.03 and acc.h < 0.09 and acc.s > 0.4, "copper: orange-brown, chromatic")
	t.check(sec.h > 0.45 and sec.h < 0.55, "teal cloth: cyan-green hue")
	# a light-hull faction must carry dark mass: the three subfaction accents differ from each other and from the parent
	var seen: Array[String] = []
	for st: StringName in STYLES:
		var a: String = str((_book.style(st)["palette"] as Dictionary)["acc"])
		t.check(not seen.has(a), "%s has its own accent trim %s" % [st, a])
		seen.append(a)
	for st: StringName in STYLES:
		t.eq(str((_book.style(st)["palette"] as Dictionary)["base"]), str(pal["base"]), "%s keeps the parent hull paint (no new palette)" % st)


func test_shared_structures_wear_the_olm_dialect_inside_their_footprint(t: TestCtx) -> void:
	_load()
	var wearing: int = 0
	for id: String in _book.ids():
		if not id.begins_with("structure.shared."):
			continue
		var plain: Dictionary = _build(id, &"neutral")
		var olm: Dictionary = _build(id, &"olm")
		t.check(not (olm["placeholder"] as bool), "%s builds in the OLM style: %s" % [id, olm["error"]])
		if olm["placeholder"] as bool:
			continue
		var fp: Vector2i = (olm["info"] as ViewModelInfo).footprint
		var bb: AABB = (olm["info"] as ViewModelInfo).rest_aabb
		var half: Vector2 = Vector2(float(fp.x) * 1.5 + 0.05, float(fp.y) * 1.5 + 0.05)
		if fp.x > 0:
			t.check(bb.position.x >= -half.x - 0.3 and bb.end.x <= half.x + 0.3 and bb.position.z >= -half.y - 0.3 and bb.end.z <= half.y + 0.3 \
				or id.ends_with("airfield") or id.ends_with("refinery"), "%s stays inside its footprint (%s)" % [id, bb])
		if (olm["info"] as ViewModelInfo).verts > (plain["info"] as ViewModelInfo).verts:
			wearing += 1
	t.ge(wearing, 8, "at least eight shared structures carry extra OLM geometry (gate, wall, tank, parasol)")


func test_builds_are_deterministic(t: TestCtx) -> void:
	_load()
	for id: String in ["unit.olm.sirocco_tank", "unit.olm.dune_rover", "unit.olm.gate_guard", "structure.olm.helios_reflector"]:
		var a: ViewModelInfo = _build(id, &"olm.algeria")["info"] as ViewModelInfo
		var b: ViewModelInfo = _build(id, &"olm.algeria")["info"] as ViewModelInfo
		t.eq(a.content_hash, b.content_hash, "%s builds identically twice" % id)
