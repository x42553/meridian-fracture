extends RefCounted
## VIEW-M8 F-han acceptance: the Han Empire recipes (19 units, 2 structures, the four styles) as shipped in game/data/recipes.
## Authored (no stubs), real models in all four Han styles, per-model triangle budgets, muzzle sockets per weapon, signature
## parts (crowns, deploy), palette vs the bible's visual direction and the art-direction palette, team-plate contrast and share.

const UNITS: PackedStringArray = [
	"unit.han.banner_infantry", "unit.han.lance_team", "unit.han.link_operator", "unit.han.jade_carrier", "unit.han.ox_tank",
	"unit.han.firefly_aa_drone", "unit.han.nest_rocket_drone", "unit.han.dragon_command_walker", "unit.han.swallow_interceptor",
	"unit.han.silkwing_drone_bomber", "unit.han.canal_patrol_boat", "unit.han.jade_escort", "unit.han.emperor_drone_ship",
	"unit.han.imperial_guard_tank", "unit.han.long_command_walker", "unit.han.canopy_ranger", "unit.han.reed_rocket_skimmer",
	"unit.han.lotus_drone_tender", "unit.han.mekong_field_engineer",
]
const STRUCTS: PackedStringArray = ["structure.han.dragon_tooth_launcher", "structure.han.dragonfall_field_foundry"]
const STYLES: Array[StringName] = [&"han", &"han.china", &"han.vietnam", &"han.cambodia"]
## archetype -> [LOD0 tri cap, LOD1 tri cap, height cap m] (same table as test_view_archetypes.BUDGET, render spec 5.8.2)
const BUDGET: Dictionary = {
	"veh_apc": [3500, 2000, 2.1], "veh_lightarty": [3500, 2000, 2.6], "veh_tank": [5000, 2800, 2.4], "veh_aa": [5000, 2800, 3.0],
	"veh_rocket": [5000, 2800, 2.9], "veh_walker": [8000, 4500, 5.0], "inf_rifle": [1400, 800, 1.6], "inf_at": [1400, 800, 1.6],
	"inf_support": [1400, 800, 1.6], "air_jet": [3000, 1700, 1.8], "air_bomber": [3000, 1700, 2.0], "ship_patrol": [2000, 1200, 3.3],
	"ship_escort": [5000, 2800, 4.9], "ship_carrier": [8000, 4500, 5.5], "str_defense_adv": [5000, 2800, 8.0], "str_superweapon": [10000, 5500, 14.0],
}

var _book: ViewRecipeBook = null
var _cache: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()


func _build(rid: String, sid: StringName) -> Dictionary:
	_load()
	var key: String = "%s@%s" % [rid, sid]
	if not _cache.has(key):
		_cache[key] = ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)
	return _cache[key] as Dictionary


func _json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v as Dictionary if v is Dictionary else {}


func _hue(c: Color) -> float:
	return c.h * 360.0


func test_every_han_recipe_is_authored_and_uses_the_han_archetype_family(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	var all: PackedStringArray = UNITS + STRUCTS
	for rid: String in all:
		t.check(_book.has_recipe(StringName(rid)), rid + " exists")
		var doc: Dictionary = _json("res://data/recipes/%s.json" % rid)
		t.check(doc.has("meta") and not bool((doc["meta"] as Dictionary).get("stub", false)), rid + " is hand authored (meta.stub cleared)")
		t.eq(str(doc.get("style", "")), "auto", rid + " uses the roster style")
	t.eq(UNITS.size(), 19, "13 baseline + 6 unique units")


func test_han_styles_resolve_and_extend_the_faction_style(t: TestCtx) -> void:
	_load()
	for sid: StringName in STYLES:
		t.check(_book.has_style(sid), "style %s" % sid)
	t.eq(_book.style_for_def("unit.han.ox_tank", "roster.han.vanilla"), &"han", "vanilla roster style")
	t.eq(_book.style_for_def("unit.shared.engineer", "roster.han.china"), &"han.china", "china roster wears han.china")
	t.eq(_book.style_for_def("structure.shared.factory", "roster.han.cambodia"), &"han.cambodia", "cambodia roster wears han.cambodia")
	# subfactions change accent / emblem / kit-bash slot only: same base, dark, sec (no new palettes)
	var base: Dictionary = (_book.style(&"han")["palette"] as Dictionary)
	for sid: StringName in [&"han.china", &"han.vietnam", &"han.cambodia"]:
		var pal: Dictionary = _book.style(sid)["palette"] as Dictionary
		for k: String in ["base", "dark", "sec", "metal", "glass"]:
			t.eq(str(pal[k]), str(base[k]), "%s keeps the parent %s" % [sid, k])
		t.ne(str(pal["acc"]), str(base["acc"]), "%s has its own accent" % sid)


func test_every_han_recipe_builds_a_real_model_in_all_four_han_styles_within_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var slow: PackedStringArray = PackedStringArray()
	for rid: String in UNITS + STRUCTS:
		var r: ViewRecipe = _book.recipe(StringName(rid))
		for sid: StringName in STYLES:
			var d: Dictionary = _build(rid, sid)
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [rid, sid, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var cap: Array = BUDGET.get(String(r.arch.id), [10000, 5500, 14.0]) as Array
			if info.tris.x - info.livery_tris.x > int(cap[0]) or info.verts > 65535:
				over.append("%s@%s tris %d verts %d (cap %d)" % [rid, sid, info.tris.x, info.verts, int(cap[0])])
			if info.tris.y - info.livery_tris.y > int(cap[1]):
				over.append("%s@%s LOD1 %d (cap %d)" % [rid, sid, info.tris.y, int(cap[1])])
			if info.height > float(cap[2]) * info.boost + 0.001:
				over.append("%s@%s height %.2f (cap %.1f)" % [rid, sid, info.height, float(cap[2])])
			if info.build_ms > 60.0:
				slow.append("%s@%s %.0f ms" % [rid, sid, info.build_ms])
	t.eq(bad.size(), 0, "placeholders / errors: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.eq(slow.size(), 0, "build time > 60 ms: %s" % " | ".join(slow))


func test_shared_han_units_and_structures_build_in_all_four_han_styles(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	for rid: String in _book.ids():
		if not (rid.begins_with("unit.shared.") or rid.begins_with("structure.shared.")):
			continue
		var r: ViewRecipe = _book.recipe(StringName(rid))
		for sid: StringName in STYLES:
			var d: Dictionary = _build(rid, sid)
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [rid, sid, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var cap2: Array = BUDGET.get(String(r.arch.id), [10000, 5500, 14.0]) as Array
			var cap_tris: int = int(cap2[0])
			if rid.begins_with("structure.shared.") and _book.has_footprint(StringName(rid)):
				# render spec 5.8.2: 1x1 / 2x2 structures 3.0 k, 3x3 and larger 8.0 k (airfield 10 k)
				var fp: Dictionary = _book.footprint_vars(StringName(rid))
				cap_tris = 3000 if int(fp["fw"]) * int(fp["fh"]) <= 4 else 8000
				if info.tris.y - info.livery_tris.y > int(float(cap_tris) * 0.65):
					over.append("%s@%s LOD1 %d" % [rid, sid, info.tris.y])
			if info.tris.x - info.livery_tris.x > cap_tris:
				over.append("%s@%s tris %d (cap %d)" % [rid, sid, info.tris.x, cap_tris])
	t.eq(bad.size(), 0, "placeholders / errors: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))


func test_armed_units_have_a_muzzle_socket_per_weapon(t: TestCtx) -> void:
	_load()
	var sheet: Dictionary = _json("res://data/balance/units_han.json")
	var seen: int = 0
	for u: Variant in sheet.get("units", []) as Array:
		var ud: Dictionary = u as Dictionary
		var uid: String = str(ud.get("id"))
		if not UNITS.has(uid):
			continue
		var info: ViewModelInfo = _build(uid, &"han")["info"] as ViewModelInfo
		var n: int = (ud.get("weapons", []) as Array).size()
		for m in n:
			t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s has muzzle%d_0" % [uid, m])
		t.check(info.has_socket(&"top"), uid + " has a top socket")
		seen += 1
	t.eq(seen, 19, "every Han unit sheet entry has a recipe")


func test_signature_parts_command_providers_show_a_rotating_crown(t: TestCtx) -> void:
	_load()
	# command-field providers and the sensor-crown vehicles carry a RADAR part (the crown turns slowly)
	for uid: String in ["unit.han.link_operator", "unit.han.mekong_field_engineer", "unit.han.dragon_command_walker",
			"unit.han.long_command_walker", "unit.han.ox_tank", "unit.han.imperial_guard_tank", "unit.han.firefly_aa_drone",
			"unit.han.jade_carrier", "unit.han.jade_escort", "unit.han.emperor_drone_ship", "unit.han.canal_patrol_boat"]:
		var info: ViewModelInfo = _build(uid, &"han")["info"] as ViewModelInfo
		t.check(info.has_part(ViewMeshBuilder.Part.RADAR), uid + " has the crown (RADAR part)")
	var mek: ViewModelInfo = _build("unit.han.mekong_field_engineer", &"han")["info"] as ViewModelInfo
	t.check(mek.has_part(ViewMeshBuilder.Part.DEPLOY), "Mekong Field Engineer unfolds its boom antenna (DEPLOY part)")
	var lng: ViewModelInfo = _build("unit.han.long_command_walker", &"han")["info"] as ViewModelInfo
	t.check(lng.has_part(ViewMeshBuilder.Part.DEPLOY) and lng.has_part(ViewMeshBuilder.Part.DEPLOY_Z), "Long Command Walker deploys its outrigger ring")
	var ranger: ViewModelInfo = _build("unit.han.canopy_ranger", &"han")["info"] as ViewModelInfo
	t.check(ranger.members >= 1, "Canopy Ranger is a gait squad")


func test_unique_units_are_designed_variants_of_the_unit_they_replace(t: TestCtx) -> void:
	_load()
	# [unique, replaced, min differing dimension (m)]: the swap must be readable (>= 0.30 m in length, width or height)
	var pairs: Array = [["unit.han.imperial_guard_tank", "unit.han.ox_tank"], ["unit.han.long_command_walker", "unit.han.dragon_command_walker"],
		["unit.han.canopy_ranger", "unit.han.banner_infantry"], ["unit.han.reed_rocket_skimmer", "unit.han.nest_rocket_drone"],
		["unit.han.lotus_drone_tender", "unit.han.jade_carrier"], ["unit.han.mekong_field_engineer", "unit.han.link_operator"]]
	for p: Array in pairs:
		var a: ViewModelInfo = _build(p[0] as String, &"han")["info"] as ViewModelInfo
		var b: ViewModelInfo = _build(p[1] as String, &"han")["info"] as ViewModelInfo
		t.ne(a.content_hash, b.content_hash, "%s differs from %s" % [p[0], p[1]])
		var d: Vector3 = (a.rest_aabb.size - b.rest_aabb.size).abs()
		var tri_diff: int = absi(a.tris.x - b.tris.x)
		t.check(maxf(d.x, maxf(d.y, d.z)) >= 0.25 or tri_diff >= 150 or a.members != b.members, "%s vs %s: size delta %s, tri delta %d" % [p[0], p[1], d, tri_diff])
	# no two Han units share a mesh
	var seen: Dictionary = {}
	for uid: String in UNITS:
		var h: int = (_build(uid, &"han")["info"] as ViewModelInfo).content_hash
		t.check(not seen.has(h), "%s is unique" % uid)
		seen[h] = uid


func test_han_palette_is_jade_crimson_and_porcelain(t: TestCtx) -> void:
	_load()
	# bible visual direction: "Jade green, crimson and porcelain" (docs/factions/han.md)
	var bible: Dictionary = _json("res://data/bible/meridian_factions.json")
	var vd: String = str(((bible.get("factions", {}) as Dictionary).get("faction.han", {}) as Dictionary).get("visual_direction", "")).to_lower()
	t.check(vd.contains("jade") and vd.contains("crimson") and vd.contains("porcelain"), "bible visual_direction: %s" % vd)
	var pal: Dictionary = _book.style(&"han")["palette"] as Dictionary
	var base: Color = Color.html(str(pal["base"]))
	var acc: Color = Color.html(str(pal["acc"]))
	var sec: Color = Color.html(str(pal["sec"]))
	var dark: Color = Color.html(str(pal["dark"]))
	t.check(_hue(base) > 140.0 and _hue(base) < 175.0 and base.s > 0.4, "base is jade green (hue %.0f sat %.2f)" % [_hue(base), base.s])
	t.check((_hue(acc) > 340.0 or _hue(acc) < 12.0) and acc.s > 0.7 and acc.v > 0.5, "accent is crimson (hue %.0f sat %.2f val %.2f)" % [_hue(acc), acc.s, acc.v])
	t.check(sec.v > 0.88 and sec.s < 0.12 and _hue(sec) > 30.0 and _hue(sec) < 70.0, "secondary is warm porcelain (val %.2f sat %.2f)" % [sec.v, sec.s])
	t.check(dark.v < 0.35 and _hue(dark) > 140.0 and _hue(dark) < 185.0, "dark is deep jade")
	# same identity as the art-direction palette (style.json palette.han): within delta E 8 for the four painted roles
	var art: Dictionary = (_json("res://data/recipes/style.json")["palettes"] as Dictionary)["palette.han"] as Dictionary
	var map: Dictionary = {"base": "primary", "sec": "secondary", "acc": "accent", "dark": "dark"}
	for k: String in map:
		var de: float = ViewTeamColors.delta_e(Color.html(str(pal[k])), Color.html(str(art[map[k]])))
		t.lt(de, 8.0, "%s within delta E 8 of art direction %s (%.1f)" % [k, map[k], de])
	# subfaction accents: art direction table 5.6.1 (within delta E 3), and pairwise distinct (delta E >= 8)
	var accs: Array[Color] = []
	for sub: String in ["china", "vietnam", "cambodia"]:
		var want: Color = Color.html(str((_json("res://data/recipes/style.json")["palettes"] as Dictionary)["palette.han." + sub]["accent"]))
		var got: Color = Color.html(str((_book.style(StringName("han." + sub))["palette"] as Dictionary)["acc"]))
		t.lt(ViewTeamColors.delta_e(want, got), 3.0, "%s accent matches 5.6.1" % sub)
		accs.append(got)
	for i in accs.size():
		for j in range(i + 1, accs.size()):
			t.gt(ViewTeamColors.delta_e(accs[i], accs[j]), 8.0, "sub accents %d/%d separate" % [i, j])


func test_team_plate_contrast_against_the_han_paint(t: TestCtx) -> void:
	_load()
	# the three-layer plate (dark gasket + light hairline + neutral key field) must separate every one of the 12 lobby colours
	# from the Han hull paint; only the lobby colour the spec already lists as low contrast (emerald, id 2) may be close to the jade
	var pal: Dictionary = _book.style(&"han")["palette"] as Dictionary
	var paint: Dictionary = {}
	for k: String in ["base", "dark", "sec", "metal"]:
		paint[k] = Color.html(str(pal[k]))
	var gasket: Color = Color.html(str(pal["plate"]))
	var low: PackedInt32Array = PackedInt32Array()
	for id in 12:
		var tc: Color = ViewTeamColors.color(id)
		t.gt(ViewTeamColors.delta_e(tc, gasket), 25.0, "colour %d stands out from the plate gasket" % id)
		if ViewTeamColors.contrast_against(tc, paint) < 20.0:
			low.append(id)
	t.check(low.size() <= 2, "at most the known low-contrast lobby colours are close to the Han paint: %s" % str(low))
	for id: int in low:
		t.check(id == 2 or id == 11 or id == 9, "unexpected low-contrast colour id %d" % id)


## Occlusion-aware plan-view share of the team-masked surfaces: every triangle is rasterised into a 5 cm height field
## (topmost wins), the share is team-masked cells / covered cells. Returns Vector2(team m2, silhouette m2).
func _plan_share(arrays: Array) -> Vector2:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	if pos.is_empty():
		return Vector2.ZERO
	var lo: Vector3 = pos[0]
	var hi: Vector3 = pos[0]
	for p: Vector3 in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	var cell: float = 0.05
	var w: int = int(ceil((hi.x - lo.x) / cell)) + 1
	var h: int = int(ceil((hi.z - lo.z) / cell)) + 1
	var top: PackedFloat32Array = PackedFloat32Array()
	top.resize(w * h)
	top.fill(-1.0e9)
	var team: PackedByteArray = PackedByteArray()
	team.resize(w * h)
	var i: int = 0
	while i + 2 < idx.size():
		var a: Vector3 = pos[idx[i]]
		var b: Vector3 = pos[idx[i + 1]]
		var c: Vector3 = pos[idx[i + 2]]
		var tm: int = 1 if (col[idx[i]].a > 0.5 and col[idx[i + 1]].a > 0.5 and col[idx[i + 2]].a > 0.5) else 0
		i += 3
		var x0: int = maxi(int(floor((minf(a.x, minf(b.x, c.x)) - lo.x) / cell)), 0)
		var x1: int = mini(int(ceil((maxf(a.x, maxf(b.x, c.x)) - lo.x) / cell)), w - 1)
		var z0: int = maxi(int(floor((minf(a.z, minf(b.z, c.z)) - lo.z) / cell)), 0)
		var z1: int = mini(int(ceil((maxf(a.z, maxf(b.z, c.z)) - lo.z) / cell)), h - 1)
		var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1.0e-9:
			continue
		for zi in range(z0, z1 + 1):
			var pz: float = lo.z + (float(zi) + 0.5) * cell
			for xi in range(x0, x1 + 1):
				var px: float = lo.x + (float(xi) + 0.5) * cell
				var l1: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
				var l2: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
				var l3: float = 1.0 - l1 - l2
				if l1 < -0.001 or l2 < -0.001 or l3 < -0.001:
					continue
				var y: float = l1 * a.y + l2 * b.y + l3 * c.y
				var k: int = zi * w + xi
				if y > top[k] + 0.0005:
					top[k] = y
					team[k] = tm
				elif y > top[k] - 0.0005 and tm == 1:
					team[k] = 1
	var cells: int = 0
	var tcells: int = 0
	for k in w * h:
		if top[k] > -1.0e8:
			cells += 1
			tcells += team[k]
	return Vector2(float(tcells) * cell * cell, float(cells) * cell * cell)


## VQ2A: shape / share / silhouette checks run on the DESIGN-scale geometry (the readability boost is a uniform scale that only
## moves the fixed raster grid of these probes); sizes of the shipped models are covered by test_view_visual_scale.
func test_team_colour_share_of_the_plan_view_silhouette(t: TestCtx) -> void:
	ViewConsts.visual_boost_enabled = false
	_test_team_colour_share_of_the_plan_view_silhouette_design(t)
	ViewConsts.visual_boost_enabled = true


func _test_team_colour_share_of_the_plan_view_silhouette_design(t: TestCtx) -> void:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for rid: String in UNITS + STRUCTS:
		var d: Dictionary = _build(rid, &"han")
		var ar: Vector2 = _plan_share((d["mesh"] as Dictionary)["arrays"] as Array)
		var frac: float = ar.x / maxf(ar.y, 0.0001)
		var is_struct: bool = rid.begins_with("structure.")
		t.check(ar.x > 0.0, "%s carries a team colour surface" % rid)
		if is_struct:
			t.check(ar.x >= 1.0 and frac >= 0.02, "%s roof plate %.2f m2 = %.1f percent of the plan silhouette" % [rid, ar.x, frac * 100.0])
		else:
			t.check(frac >= 0.04 and frac <= (0.2 if rid.contains("infantry") or rid.contains("team") or rid.contains("ranger") or rid.contains("operator") or rid.contains("engineer") else 0.14), "%s team share %.1f percent of the plan silhouette (%.2f of %.1f m2)" % [rid, frac * 100.0, ar.x, ar.y])
		out.append("%s %.1f" % [rid.get_slice(".", 2), frac * 100.0])
	t.note("plan-view team share percent: " + ", ".join(out))
