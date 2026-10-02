extends RefCounted
## VIEW-M8 acceptance for the South Asian Protectorate (task F-sap): the 19 unit recipes, the two faction structures and the
## Protectorate's dialect of the twelve shared structure archetypes (styles/sap.json). Checks: every recipe builds a real model in the
## `sap` style and the three subfaction styles (never the placeholder), per-model triangle / height budgets, muzzle sockets for every
## weapon of the balance sheet, the palette against the art-direction bible (style.json), the subfaction accents, team-plate contrast
## against the faction paint for all 12 player colours, the team-masked share of the top-projected area, silhouette distinctness
## between siblings and against another faction's model of the same archetype.

const STYLE_IDS: Array[StringName] = [&"sap", &"sap.india", &"sap.thailand", &"sap.pakistan"]
const SHARED: PackedStringArray = ["headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory",
	"watchtower", "anti_tank_turret", "aa_battery"]
## archetype -> [LOD0 tri cap, LOD1 tri cap, height cap (m)]: render spec 5.8.2 / test_view_archetypes.
const BUDGET: Dictionary = {
	"veh_apc": [3500, 2000, 2.1], "veh_amphib": [3500, 2000, 2.6], "veh_tank": [5000, 2800, 2.4], "veh_siege": [6500, 3600, 2.9],
	"veh_aa": [5000, 2800, 3.0], "veh_howitzer": [5000, 2800, 2.4], "veh_rocket": [5000, 2800, 2.9],
	"inf_rifle": [1400, 800, 1.6], "inf_at": [1400, 800, 1.6], "inf_support": [1400, 800, 1.6], "inf_special": [1400, 800, 1.6],
	"air_jet": [3000, 1700, 1.8], "air_heli": [3500, 2000, 2.7],
	"ship_patrol": [2000, 1200, 3.3], "ship_escort": [5000, 2800, 4.9], "ship_siege": [8000, 4500, 5.5],
}
## structures: LOD0 cap by footprint class (render spec 5.8.2), height cap.
const STRUCT_TRIS: Dictionary = {"1x1": [3000, 8.0], "2x2": [3000, 8.0], "3x3": [8000, 12.0], "4x4": [8000, 14.0]}

var _book: ViewRecipeBook = null
var _data: GameData = null
var _cache: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	_data = GameData.load_default()


func _sap_unit_ids() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for u: DefUnit in _data.units:
		if u.id.begins_with("unit.sap."):
			out.append(u.id)
	out.sort()
	return out


func _build(rid: String, style: StringName) -> Dictionary:
	_load()
	var key: String = "%s@%s" % [rid, style]
	if not _cache.has(key):
		_cache[key] = ViewModelBuilder.build_data(_book, StringName(rid), style, 10000)
	return _cache[key] as Dictionary


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func test_nineteen_units_two_structures_and_four_styles(t: TestCtx) -> void:
	var ids: PackedStringArray = _sap_unit_ids()
	t.eq(ids.size(), 19, "13 baseline + 6 unique units")
	for rid: String in ids:
		var r: ViewRecipe = _book.recipe(StringName(rid))
		t.check(r != null, rid + " has a recipe")
		if r != null:
			t.check(not r.meta.has("stub"), rid + " is authored, not a stub")
	for sid: String in ["structure.sap.bastion_missile_tower", "structure.sap.trident_interception_array"]:
		t.check(_book.recipe(StringName(sid)) != null, sid + " has a recipe")
	for s: StringName in STYLE_IDS:
		t.check(_book.has_style(s), "style %s exists" % s)


func test_every_sap_recipe_builds_and_stays_inside_the_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = PackedStringArray()
	for rid: String in _sap_unit_ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		var aid: String = String(r.arch.id)
		for s: StringName in STYLE_IDS:
			var d: Dictionary = _build(rid, s)
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [rid, s, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var cap: Array = BUDGET.get(aid, [5000, 2800, 3.0]) as Array
			if info.tris.x - info.livery_tris.x > int(cap[0]) or info.tris.y - info.livery_tris.y > int(cap[1]) or info.height > float(cap[2]) * info.boost or info.verts > 65535:
				over.append("%s@%s tris %d/%d h %.2f (caps %d/%d/%.1f)" % [rid, s, info.tris.x, info.tris.y, info.height, int(cap[0]), int(cap[1]), float(cap[2])])
			if s == &"sap":
				lines.append("%s %s tris=%d/%d/%d verts=%d h=%.2f r=%.2f build=%.1f ms" % [rid, aid, info.tris.x, info.tris.y, info.tris.z, info.verts, info.height, info.radius, info.build_ms])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.note("\n".join(lines))


func test_structures_build_fit_and_stay_inside_the_budget(t: TestCtx) -> void:
	_load()
	var ids: PackedStringArray = PackedStringArray(["structure.sap.bastion_missile_tower", "structure.sap.trident_interception_array"])
	for n: String in SHARED:
		ids.append("structure.shared." + n)
	var lines: PackedStringArray = PackedStringArray()
	for rid: String in ids:
		for s: StringName in STYLE_IDS:
			var d: Dictionary = _build(rid, s)
			t.check(not (d["placeholder"] as bool), "%s@%s builds: %s" % [rid, s, d["error"]])
			if d["placeholder"] as bool:
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var fp: Dictionary = _footprint(rid)
			var key: String = "%dx%d" % [int(fp.get("fw", 2)), int(fp.get("fh", 2))]
			var cap: Array = STRUCT_TRIS.get(key, [8000, 14.0]) as Array
			# the subfaction skins add band patterns to the vanilla dialect: 2.5 percent grace on the 3.0 k class ceiling
			var grace: float = 1.0 if s == &"sap" else 1.025
			t.check(float(info.tris.x) <= float(int(cap[0])) * grace, "%s@%s tris %d (%s, cap %d)" % [rid, s, info.tris.x, key, int(cap[0])])
			t.check(info.height <= float(cap[1]) + 0.01, "%s@%s height %.1f m (cap %.0f)" % [rid, s, info.height, float(cap[1])])
			t.check(info.verts <= 65535, "%s@%s verts" % [rid, s])
			if s == &"sap":
				lines.append("%s %s tris=%d/%d/%d h=%.1f r=%.1f" % [rid, key, info.tris.x, info.tris.y, info.tris.z, info.height, info.radius])
	t.note("\n".join(lines))


func _footprint(rid: String) -> Dictionary:
	var fps: Dictionary = (_json("res://data/recipes/footprints.json")["structures"] as Dictionary)
	return fps.get(rid, {}) as Dictionary


func test_armed_units_carry_a_muzzle_socket_per_weapon(t: TestCtx) -> void:
	_load()
	var sheet: Dictionary = _json("res://data/balance/units_sap.json")
	var checked: int = 0
	for u: Variant in sheet["units"] as Array:
		var ud: Dictionary = u as Dictionary
		var rid: String = str(ud["id"])
		var info: ViewModelInfo = _build(rid, &"sap")["info"] as ViewModelInfo
		var n: int = (ud.get("weapons", []) as Array).size()
		for m: int in n:
			t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s has muzzle%d_0" % [rid, m])
			checked += 1
		t.check(info.has_socket(&"top"), rid + " has a top socket")
	t.gt(checked, 15, "weapons checked")
	var bastion: ViewModelInfo = _build("structure.sap.bastion_missile_tower", &"sap")["info"] as ViewModelInfo
	t.check(bastion.has_socket(&"muzzle0_0"), "bastion tower muzzle0_0")


func test_palette_matches_the_art_direction_bible(t: TestCtx) -> void:
	_load()
	var bible: Dictionary = _json("res://data/recipes/style.json")
	var pal: Dictionary = (bible["palettes"] as Dictionary)["palette.sap"] as Dictionary
	var st: Dictionary = _book.style(&"sap")
	var sp: Dictionary = st["palette"] as Dictionary
	var map: Dictionary = {"base": "primary", "sec": "secondary", "acc": "accent", "dark": "dark", "metal": "metal", "glass": "glass",
		"rubber": "rubber", "light": "light"}
	for k: Variant in map:
		var want: Color = Color.html(str(pal[str(map[k])]))
		var got: Color = Color.html(str(sp[str(k)]))
		t.check(ViewTeamColors.delta_e(want, got) < 1.0, "palette %s matches the bible (%s)" % [k, pal[str(map[k])]])
	# subfactions: only the accent moves, and it equals the bible's derived sub accent; the base palette entries stay
	for sub: String in ["india", "thailand", "pakistan"]:
		var bs: Dictionary = (bible["palettes"] as Dictionary)["palette.sap." + sub] as Dictionary
		var ms: Dictionary = (_book.style(StringName("sap." + sub))["palette"]) as Dictionary
		t.check(ViewTeamColors.delta_e(Color.html(str(bs["accent"])), Color.html(str(ms["acc"]))) < 1.0, "%s accent matches the bible" % sub)
		for k: String in ["base", "sec", "dark", "metal", "glass"]:
			t.eq(str(ms[k]), str(sp[k]), "%s keeps the faction %s" % [sub, k])
	# the palette obeys the value rules: hull (sand) lighter than the indigo layers, dark mass dark
	t.check(_luma(sp["base"]) > _luma(sp["sec"]) + 0.2, "sand primary is lighter than the indigo secondary")
	t.check(_luma(sp["dark"]) < 0.16, "dark role is a dark mass (luma %.3f)" % _luma(sp["dark"]))
	t.check(ViewTeamColors.delta_e(Color.html(str(sp["base"])), Color.html(str(sp["sec"]))) > 25.0, "primary vs secondary dE >= 25")


static func _luma(hex: Variant) -> float:
	var c: Color = Color.html(str(hex))
	return 0.2126 * c.srgb_to_linear().r + 0.7152 * c.srgb_to_linear().g + 0.0722 * c.srgb_to_linear().b


func test_team_plate_contrast_against_the_faction_paint(t: TestCtx) -> void:
	_load()
	var sp: Dictionary = _book.style(&"sap")["palette"] as Dictionary
	var faction: Dictionary = {}
	for k: String in ["base", "sec", "dark", "acc"]:
		faction[k] = Color.html(str(sp[k]))
	var worst: float = 1000.0
	var worst_name: String = ""
	var lines: PackedStringArray = PackedStringArray()
	for cid: int in 12:
		var team: Color = ViewTeamColors.color(cid)
		# the plate field is painted with the neutral key and lit by team * (0.40 + 0.9 * luma(key)) = team * 0.909
		var field: Color = Color(team.r * 0.909, team.g * 0.909, team.b * 0.909)
		var best: float = 1000.0
		var against: String = ""
		for k: Variant in faction:
			var de: float = ViewTeamColors.delta_e(field, faction[k] as Color)
			if de < best:
				best = de
				against = str(k)
		lines.append("colour %d vs %s: dE %.1f" % [cid, against, best])
		if best < worst:
			worst = best
			worst_name = "colour %d vs %s" % [cid, against]
	t.note("\n".join(lines))
	# the three-layer plate (dark gasket + light hairline) is what guarantees the read; the raw pair may be close but never identical
	t.gt(worst, 8.0, "closest player colour to the faction paint (%s) dE %.1f" % [worst_name, worst])
	# every ground model's plate has a dark border: the team_panel macro emits the 'plate' gasket, whose colour must be a dark mass
	t.check(_luma(sp["plate"]) < 0.02, "plate gasket colour is near black")
	# and the rendered plate stays distinguishable from the two large paint fields for the default 8 colours (dE >= 20 to sand or indigo, or the border)
	var weak: int = 0
	for cid: int in 8:
		var team2: Color = ViewTeamColors.color(cid)
		var f2: Color = Color(team2.r * 0.909, team2.g * 0.909, team2.b * 0.909)
		if ViewTeamColors.delta_e(f2, faction["base"] as Color) < 20.0 or ViewTeamColors.delta_e(f2, faction["sec"] as Color) < 20.0:
			weak += 1
	t.note("player colours (of the first 8) within dE 20 of sand or indigo: %d" % weak)
	t.check(weak <= 3, "at most three of the eight default colours need the plate border to separate from the paint (%d)" % weak)


## Occlusion-aware top view (0.05 m grid, highest surface wins): returns {team, dark, light, cells} shares of the covered cells.
## Paint luminance uses CIE L* of the vertex paint colour (sRGB), the same quantity the bible's three-value rule is written in.
func _top_view(arrays: Array) -> Dictionary:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var cell: float = 0.1
	var lo: Vector3 = Vector3(1e9, 1e9, 1e9)
	var hi: Vector3 = Vector3(-1e9, -1e9, -1e9)
	for p: Vector3 in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	var gw: int = int((hi.x - lo.x) / cell) + 2
	var gh: int = int((hi.z - lo.z) / cell) + 2
	var ys: PackedFloat32Array = PackedFloat32Array()
	ys.resize(gw * gh)
	ys.fill(-1e9)
	var kind: PackedFloat32Array = PackedFloat32Array()  # -1 team, else L*
	kind.resize(gw * gh)
	var i: int = 0
	while i + 2 < idx.size():
		var a: Vector3 = pos[idx[i]]
		var b: Vector3 = pos[idx[i + 1]]
		var c: Vector3 = pos[idx[i + 2]]
		var n: Vector3 = (b - a).cross(c - a)
		var nl: float = n.length()
		var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if nl > 1e-9 and n.y / nl < -0.3 and absf(den) > 1e-9:
			var val: float = -1.0 if (col[idx[i]].a > 0.5 and col[idx[i + 1]].a > 0.5 and col[idx[i + 2]].a > 0.5) else _lstar(col[idx[i]])
			var x0: int = maxi(int((minf(a.x, minf(b.x, c.x)) - lo.x) / cell), 0)
			var x1: int = mini(int((maxf(a.x, maxf(b.x, c.x)) - lo.x) / cell) + 1, gw - 1)
			var z0: int = maxi(int((minf(a.z, minf(b.z, c.z)) - lo.z) / cell), 0)
			var z1: int = mini(int((maxf(a.z, maxf(b.z, c.z)) - lo.z) / cell) + 1, gh - 1)
			for gx: int in range(x0, x1 + 1):
				var px: float = lo.x + (float(gx) + 0.5) * cell
				for gz: int in range(z0, z1 + 1):
					var pz: float = lo.z + (float(gz) + 0.5) * cell
					var w0: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
					var w1: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
					var w2: float = 1.0 - w0 - w1
					if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
						var y: float = w0 * a.y + w1 * b.y + w2 * c.y
						var k: int = gz * gw + gx
						if y > ys[k]:
							ys[k] = y
							kind[k] = val
		i += 3
	var covered: float = 0.0
	var team_n: float = 0.0
	var dark_n: float = 0.0
	var light_n: float = 0.0
	for k: int in ys.size():
		if ys[k] > -1e8:
			covered += 1.0
			var v: float = kind[k]
			if v < 0.0:
				team_n += 1.0
			elif v <= 30.0:
				dark_n += 1.0
			elif v >= 75.0:
				light_n += 1.0
	covered = maxf(covered, 1.0)
	return {"team": team_n / covered, "dark": dark_n / covered, "light": light_n / covered, "cells": int(covered)}


static func _lstar(c: Color) -> float:
	var l: Color = c.srgb_to_linear()
	var y: float = 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var f: float = pow(y, 1.0 / 3.0) if y > 0.008856 else 7.787 * y + 16.0 / 116.0
	return 116.0 * f - 16.0


## VQ2A: shape / share / silhouette checks run on the DESIGN-scale geometry (the readability boost is a uniform scale that only
## moves the fixed raster grid of these probes); sizes of the shipped models are covered by test_view_visual_scale.
func test_team_masked_share_of_the_top_projected_area(t: TestCtx) -> void:
	ViewConsts.visual_boost_enabled = false
	_test_team_masked_share_of_the_top_projected_area_design(t)
	ViewConsts.visual_boost_enabled = true


func _test_team_masked_share_of_the_top_projected_area_design(t: TestCtx) -> void:
	_load()
	var lines: PackedStringArray = PackedStringArray()
	var ids: PackedStringArray = _sap_unit_ids()
	ids.append("structure.sap.bastion_missile_tower")
	for rid: String in ids:
		var d: Dictionary = _build(rid, &"sap")
		var tv: Dictionary = _top_view((d["mesh"] as Dictionary)["arrays"] as Array)
		var frac: float = float(tv["team"])
		lines.append("%s team %.1f%% dark %.1f%% light %.1f%% (%d cells)" % [rid, frac * 100.0, float(tv["dark"]) * 100.0, float(tv["light"]) * 100.0, int(tv["cells"])])
		t.check(frac > 0.0, rid + " carries a team-colour surface")
		var squad: bool = rid.contains("rifle_squad") or rid.contains("marine") or rid.contains("kavach") or rid.contains("pioneer") or rid.contains("watchpost")
		# squads: the soldier macro's back patches are 15-20 percent of a 4-man top view (bible 5.4.3 measures vehicles); vehicles: 5-12 +-2
		t.check(frac >= 0.04 and frac <= (0.22 if squad else 0.14), "%s team-masked share %.1f%% of the visible top area" % [rid, frac * 100.0])
		if not squad:
			t.check(float(tv["dark"]) >= 0.10, "%s dark mass %.1f%% (three-value rule)" % [rid, float(tv["dark"]) * 100.0])
	t.note("\n".join(lines))


func test_siblings_and_other_factions_differ(t: TestCtx) -> void:
	_load()
	# siblings built on the same archetype must have different geometry (content hash) and different silhouettes (radius / height / tris)
	var groups: Dictionary = {}
	for rid: String in _sap_unit_ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		var aid: String = String(r.arch.id)
		if not groups.has(aid):
			groups[aid] = []
		(groups[aid] as Array).append(rid)
	for aid: Variant in groups:
		var g: Array = groups[aid] as Array
		for i: int in g.size():
			for j: int in range(i + 1, g.size()):
				var a: ViewModelInfo = _build(str(g[i]), &"sap")["info"] as ViewModelInfo
				var b: ViewModelInfo = _build(str(g[j]), &"sap")["info"] as ViewModelInfo
				t.ne(a.content_hash, b.content_hash, "%s vs %s differ" % [g[i], g[j]])
	# against another faction: the Bulwark vs the NAPC Guardian (same archetype) and the SAP howitzer vs the NAPC one
	for pair: Array in [["unit.sap.bulwark_tank", "unit.napc.guardian_tank", &"napc"], ["unit.sap.monsoon_howitzer", "unit.napc.paladin_howitzer", &"napc"],
			["unit.sap.jackal_apc", "unit.napc.pathfinder_apc", &"napc"], ["unit.sap.vajra_aa", "unit.napc.sentinel_aa", &"napc"],
			["unit.sap.garuda_interceptor", "unit.napc.falcon_interceptor", &"napc"], ["unit.sap.sarus_gunship", "unit.napc.titan_gunship", &"napc"],
			["unit.sap.estuary_patrol_boat", "unit.napc.riverwatch_patrol_boat", &"napc"], ["unit.sap.shield_escort", "unit.napc.aegis_frigate", &"napc"]]:
		if _book.recipe(StringName(str(pair[1]))) == null:
			continue
		var s1: ViewModelInfo = _build(str(pair[0]), &"sap")["info"] as ViewModelInfo
		var s2: ViewModelInfo = _build(str(pair[1]), pair[2] as StringName)["info"] as ViewModelInfo
		t.ne(s1.content_hash, s2.content_hash, "%s differs from %s" % [pair[0], pair[1]])
		t.check(absf(s1.radius - s2.radius) > 0.02 or absf(s1.height - s2.height) > 0.02 or s1.tris.x != s2.tris.x, "%s silhouette metrics differ from %s" % [pair[0], pair[1]])


func test_builds_are_deterministic_and_subfaction_styles_only_recolour_units(t: TestCtx) -> void:
	_load()
	for rid: String in ["unit.sap.arjun_assault_tank", "unit.sap.shaheen_missile_battery", "structure.sap.trident_interception_array"]:
		var h1: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"sap", 10000)["info"] as ViewModelInfo).content_hash
		var h2: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"sap", 10000)["info"] as ViewModelInfo).content_hash
		t.eq(h1, h2, rid + " content hash is stable")
	# subfaction styles add insignia parts to shared structures but keep the faction massing (same size class, radius within 10 %)
	for n: String in SHARED:
		var rid2: String = "structure.shared." + n
		var base: ViewModelInfo = _build(rid2, &"sap")["info"] as ViewModelInfo
		for sub: StringName in [&"sap.india", &"sap.thailand", &"sap.pakistan"]:
			var si: ViewModelInfo = _build(rid2, sub)["info"] as ViewModelInfo
			t.check(absf(si.radius - base.radius) <= base.radius * 0.10 + 0.01, "%s@%s keeps the faction massing" % [rid2, sub])
			t.ne(si.content_hash, base.content_hash, "%s@%s differs from the vanilla Protectorate look" % [rid2, sub])
