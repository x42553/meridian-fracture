extends RefCounted
## VIEW-M8 acceptance for the North American Peace Corps (task F-napc): the 19 unit recipes, the two faction structures and the
## Peace Corps dialect of the twelve shared structure archetypes (styles/napc.json). Checks: every recipe builds a real model in the
## `napc` style and the three subfaction styles (never the placeholder), per-model triangle / height budgets, muzzle sockets for every
## weapon of the balance sheet, the animated parts each archetype must carry, the palette against the art-direction bible (style.json),
## the subfaction accents, team-plate contrast against the faction paint for all 12 player colours, the team-masked share of the
## top-projected area, silhouette distinctness between siblings and against other factions' models of the same archetype.

const STYLE_IDS: Array[StringName] = [&"napc", &"napc.usa", &"napc.canada", &"napc.mexico"]
const SUBS: PackedStringArray = ["usa", "canada", "mexico"]
const SHARED: PackedStringArray = ["headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory",
	"watchtower", "anti_tank_turret", "aa_battery"]
const Pt := ViewMeshBuilder.Part
## archetype -> [LOD0 tri cap, LOD1 tri cap, height cap (m)]: render spec 5.8.2 / test_view_archetypes.
const BUDGET: Dictionary = {
	"veh_apc": [3500, 2000, 2.1], "veh_amphib": [3500, 2000, 2.6], "veh_tank": [5000, 2800, 2.4], "veh_siege": [6500, 3600, 2.9],
	"veh_aa": [5000, 2800, 3.0], "veh_howitzer": [5000, 2800, 2.4],
	"inf_rifle": [1400, 800, 1.7], "inf_at": [1400, 800, 1.6], "inf_support": [1400, 800, 1.6], "inf_special": [1400, 800, 1.6],
	"air_jet": [3000, 1700, 1.8], "air_heli": [3500, 2000, 2.7], "air_bomber": [3000, 1700, 1.6],
	"ship_patrol": [2000, 1200, 3.3], "ship_escort": [5000, 2800, 4.9], "ship_siege": [8000, 4500, 5.5],
}
## archetype -> animated parts that must be present (art_direction 5.5.9 rule 4)
const PARTS: Dictionary = {
	"veh_tank": [Pt.TURRET, Pt.BARREL, Pt.TRACK], "veh_siege": [Pt.TURRET, Pt.BARREL, Pt.TRACK], "veh_howitzer": [Pt.TURRET, Pt.BARREL, Pt.DEPLOY],
	"veh_aa": [Pt.TURRET, Pt.RADAR], "veh_apc": [Pt.WHEEL, Pt.TURRET, Pt.RADAR],
	"inf_rifle": [Pt.LEG_A, Pt.LEG_B, Pt.BODY_BOB], "inf_at": [Pt.LEG_A, Pt.LEG_B, Pt.BODY_BOB], "inf_support": [Pt.LEG_A, Pt.LEG_B, Pt.BODY_BOB],
	"inf_special": [Pt.LEG_A, Pt.LEG_B, Pt.BODY_BOB], "air_heli": [Pt.ROTOR, Pt.TAIL_ROTOR], "air_jet": [Pt.BLINK],
	"ship_patrol": [Pt.RADAR, Pt.TURRET], "ship_escort": [Pt.RADAR, Pt.TURRET], "ship_siege": [Pt.TURRET],
}
## structures: LOD0 cap by footprint class (render spec 5.8.2), height cap.
const STRUCT_TRIS: Dictionary = {"1x1": [3000, 8.0], "2x2": [3000, 8.0], "3x3": [8000, 12.0], "4x4": [10000, 14.0]}

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


func _napc_unit_ids() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for u: DefUnit in _data.units:
		if u.id.begins_with("unit.napc."):
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
	var ids: PackedStringArray = _napc_unit_ids()
	t.eq(ids.size(), 19, "13 baseline + 6 unique units")
	for rid: String in ids:
		var r: ViewRecipe = _book.recipe(StringName(rid))
		t.check(r != null, rid + " has a recipe")
		if r != null:
			t.check(not r.meta.has("stub"), rid + " is authored, not a stub")
	for sid: String in ["structure.napc.bulwark_cannon", "structure.napc.atlas_kinetic_array"]:
		var rs: ViewRecipe = _book.recipe(StringName(sid))
		t.check(rs != null and not rs.meta.has("stub"), sid + " is authored")
	for s: StringName in STYLE_IDS:
		t.check(_book.has_style(s), "style %s exists" % s)
	t.eq(String(_book.style(&"napc.usa").get("emblem", "")), "chevron", "usa emblem")
	t.check(_book.errors().is_empty(), "recipe book loads clean: %s" % " | ".join(_book.errors()))


func test_every_napc_recipe_builds_and_stays_inside_the_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = PackedStringArray()
	for rid: String in _napc_unit_ids():
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
			if info.build_ms > 60.0:
				over.append("%s@%s build %.0f ms" % [rid, s, info.build_ms])
			if s == &"napc":
				lines.append("%s %s tris=%d/%d/%d verts=%d h=%.2f r=%.2f build=%.1f ms" % [rid, aid, info.tris.x, info.tris.y, info.tris.z, info.verts, info.height, info.radius, info.build_ms])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.note("\n".join(lines))


func test_every_archetype_carries_its_animated_parts(t: TestCtx) -> void:
	_load()
	for rid: String in _napc_unit_ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		var aid: String = String(r.arch.id)
		var info: ViewModelInfo = _build(rid, &"napc")["info"] as ViewModelInfo
		for p: int in (PARTS.get(aid, []) as Array):
			t.check((info.parts_mask & (1 << p)) != 0, "%s (%s) has animated part %d" % [rid, aid, p])
	# deployables: the howitzer spades, the Vanguard cover panel, the Narwhal wave-breaker
	for rid: String in ["unit.napc.paladin_howitzer", "unit.napc.vanguard_rifle_squad", "unit.napc.narwhal_amphibious_tank"]:
		var info2: ViewModelInfo = _build(rid, &"napc")["info"] as ViewModelInfo
		t.check((info2.parts_mask & ((1 << Pt.DEPLOY) | (1 << Pt.DEPLOY_Z))) != 0, rid + " has a DEPLOY part")
	# squads keep every soldier inside a gait part tagged with its member index (hide-by-hp)
	for rid: String in ["unit.napc.rifle_squad", "unit.napc.javelin_team", "unit.napc.combat_medic", "unit.napc.vanguard_rifle_squad", "unit.napc.aguila_breach_team"]:
		var info3: ViewModelInfo = _build(rid, &"napc")["info"] as ViewModelInfo
		t.gt(info3.members, 1, rid + " tags its members")


func test_structures_build_fit_and_stay_inside_the_budget(t: TestCtx) -> void:
	_load()
	var ids: PackedStringArray = PackedStringArray(["structure.napc.bulwark_cannon", "structure.napc.atlas_kinetic_array"])
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
			t.check(info.tris.x <= int(cap[0]), "%s@%s tris %d (%s cap %d)" % [rid, s, info.tris.x, key, int(cap[0])])
			t.check(info.height <= float(cap[1]) + 0.01, "%s@%s height %.1f m (cap %.0f)" % [rid, s, info.height, float(cap[1])])
			t.check(info.verts <= 65535, "%s@%s verts" % [rid, s])
			if s == &"napc":
				lines.append("%s %s tris=%d/%d/%d h=%.1f r=%.1f" % [rid, key, info.tris.x, info.tris.y, info.tris.z, info.height, info.radius])
	t.note("\n".join(lines))


func _footprint(rid: String) -> Dictionary:
	var fps: Dictionary = (_json("res://data/recipes/footprints.json")["structures"] as Dictionary)
	return fps.get(rid, {}) as Dictionary


func test_armed_units_carry_a_muzzle_socket_per_weapon(t: TestCtx) -> void:
	_load()
	var sheet: Dictionary = _json("res://data/balance/units_napc.json")
	var checked: int = 0
	for u: Variant in sheet["units"] as Array:
		var ud: Dictionary = u as Dictionary
		var rid: String = str(ud["id"])
		var info: ViewModelInfo = _build(rid, &"napc")["info"] as ViewModelInfo
		var n: int = (ud.get("weapons", []) as Array).size()
		for m: int in n:
			t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s has muzzle%d_0" % [rid, m])
			checked += 1
		t.check(info.has_socket(&"top"), rid + " has a top socket")
	t.gt(checked, 15, "weapons checked")
	var bw: ViewModelInfo = _build("structure.napc.bulwark_cannon", &"napc")["info"] as ViewModelInfo
	t.check(bw.has_socket(&"muzzle0_0"), "bulwark cannon muzzle0_0")


func test_palette_matches_the_art_direction_bible(t: TestCtx) -> void:
	_load()
	var bible: Dictionary = _json("res://data/recipes/style.json")
	var pal: Dictionary = (bible["palettes"] as Dictionary)["palette.napc"] as Dictionary
	var st: Dictionary = _book.style(&"napc")
	var sp: Dictionary = st["palette"] as Dictionary
	var map: Dictionary = {"base": "primary", "sec": "secondary", "acc": "accent", "dark": "dark", "metal": "metal", "glass": "glass",
		"rubber": "rubber", "light": "light"}
	for k: Variant in map:
		var want: Color = Color.html(str(pal[str(map[k])]))
		var got: Color = Color.html(str(sp[str(k)]))
		t.check(ViewTeamColors.delta_e(want, got) < 1.0, "palette %s matches the bible (%s)" % [k, pal[str(map[k])]])
	# visual_direction: "Olive, cream and rescue orange": hue bands of the three role colours
	var base: Color = Color.html(str(sp["base"]))
	var sec: Color = Color.html(str(sp["sec"]))
	var acc: Color = Color.html(str(sp["acc"]))
	t.check(base.h * 360.0 > 60.0 and base.h * 360.0 < 100.0 and base.s > 0.3, "primary is olive (h %.0f s %.2f)" % [base.h * 360.0, base.s])
	t.check(sec.h * 360.0 > 35.0 and sec.h * 360.0 < 65.0 and sec.s < 0.35 and _lstar(sec) > 75.0, "secondary is cream (h %.0f s %.2f)" % [sec.h * 360.0, sec.s])
	t.check(acc.h * 360.0 > 12.0 and acc.h * 360.0 < 30.0 and acc.s > 0.8, "accent is rescue orange (h %.0f s %.2f)" % [acc.h * 360.0, acc.s])
	# subfactions: only the accent moves and it equals the bible's derived sub accent; sibling accents differ by dE >= 8
	var accents: Array[Color] = []
	for sub: String in SUBS:
		var bs: Dictionary = (bible["palettes"] as Dictionary)["palette.napc." + sub] as Dictionary
		var ms: Dictionary = (_book.style(StringName("napc." + sub))["palette"]) as Dictionary
		t.check(ViewTeamColors.delta_e(Color.html(str(bs["accent"])), Color.html(str(ms["acc"]))) < 1.0, "%s accent matches the bible" % sub)
		accents.append(Color.html(str(ms["acc"])))
		for k: String in ["base", "sec", "dark", "metal", "glass"]:
			t.eq(str(ms[k]), str(sp[k]), "%s keeps the faction %s" % [sub, k])
	for i: int in accents.size():
		for j: int in range(i + 1, accents.size()):
			t.check(ViewTeamColors.delta_e(accents[i], accents[j]) >= 8.0, "sibling sub accents %d/%d differ (dE %.1f)" % [i, j, ViewTeamColors.delta_e(accents[i], accents[j])])
	# value rules: cream is the lightest mass, olive is mid, the dark role is a dark mass
	t.check(_luma(sp["sec"]) > _luma(sp["base"]) + 0.3, "cream secondary is lighter than the olive primary")
	t.check(_lstar(base) > 25.0 and _lstar(base) < 45.0, "primary L* in the mid-dark band (%.1f)" % _lstar(base))
	t.check(_luma(sp["dark"]) < 0.05, "dark role is a dark mass (luma %.3f)" % _luma(sp["dark"]))
	t.check(ViewTeamColors.delta_e(base, sec) > 25.0, "primary vs secondary dE >= 25")


static func _luma(hex: Variant) -> float:
	var c: Color = Color.html(str(hex))
	return 0.2126 * c.srgb_to_linear().r + 0.7152 * c.srgb_to_linear().g + 0.0722 * c.srgb_to_linear().b


func test_team_plate_contrast_against_the_faction_paint(t: TestCtx) -> void:
	_load()
	var sp: Dictionary = _book.style(&"napc")["palette"] as Dictionary
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
	# orange (id 6) sits near the rescue-orange accent by design; the three-layer plate (dark gasket) is what guarantees the read there
	t.gt(worst, 4.0, "closest player colour to the faction paint (%s) dE %.1f" % [worst_name, worst])
	t.check(_luma(sp["plate"]) < 0.02, "plate gasket colour is near black")
	# against the two large paint fields (olive hull, cream trim) the default eight colours must be separable
	var weak: int = 0
	for cid: int in 8:
		var team2: Color = ViewTeamColors.color(cid)
		var f2: Color = Color(team2.r * 0.909, team2.g * 0.909, team2.b * 0.909)
		if ViewTeamColors.delta_e(f2, faction["base"] as Color) < 20.0 or ViewTeamColors.delta_e(f2, faction["sec"] as Color) < 20.0:
			weak += 1
	t.note("player colours (of the first 8) within dE 20 of olive or cream: %d" % weak)
	t.check(weak <= 3, "at most three of the eight default colours need the plate border to separate from the paint (%d)" % weak)
	# every subfaction accent stays distinct from the plate gasket and the olive hull
	for sub: String in SUBS:
		var acc: Color = Color.html(str((_book.style(StringName("napc." + sub))["palette"] as Dictionary)["acc"]))
		t.gt(ViewTeamColors.delta_e(acc, faction["base"] as Color), 30.0, sub + " accent vs olive")


## Occlusion-aware top view (0.05 m grid, highest surface wins): returns {team, dark, light, cells, mask} shares of the covered cells.
func _top_view(arrays: Array) -> Dictionary:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var cell: float = 0.05
	var top: Dictionary = {}  # Vector2i -> Vector3(y, team, lstar)
	var i: int = 0
	while i + 2 < idx.size():
		var a: Vector3 = pos[idx[i]]
		var b: Vector3 = pos[idx[i + 1]]
		var c: Vector3 = pos[idx[i + 2]]
		var n: Vector3 = (b - a).cross(c - a)
		var nl: float = n.length()
		if nl > 1e-9 and n.y / nl < -0.3:
			var team: float = 1.0 if (col[idx[i]].a > 0.5 and col[idx[i + 1]].a > 0.5 and col[idx[i + 2]].a > 0.5) else 0.0
			var lum: float = _lstar(col[idx[i]])
			var x0: int = floori(minf(a.x, minf(b.x, c.x)) / cell)
			var x1: int = floori(maxf(a.x, maxf(b.x, c.x)) / cell)
			var z0: int = floori(minf(a.z, minf(b.z, c.z)) / cell)
			var z1: int = floori(maxf(a.z, maxf(b.z, c.z)) / cell)
			var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(den) > 1e-9:
				for gx: int in range(x0, x1 + 1):
					for gz: int in range(z0, z1 + 1):
						var px: float = (float(gx) + 0.5) * cell
						var pz: float = (float(gz) + 0.5) * cell
						var w0: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
						var w1: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
						var w2: float = 1.0 - w0 - w1
						if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
							var y: float = w0 * a.y + w1 * b.y + w2 * c.y
							var key: Vector2i = Vector2i(gx, gz)
							var cur: Variant = top.get(key)
							if cur == null or y > (cur as Vector3).x:
								top[key] = Vector3(y, team, lum)
		i += 3
	var n_all: float = maxf(float(top.size()), 1.0)
	var team_n: float = 0.0
	var dark_n: float = 0.0
	var light_n: float = 0.0
	for k: Variant in top:
		var v: Vector3 = top[k] as Vector3
		if v.y > 0.5:
			team_n += 1.0
		elif v.z <= 30.0:
			dark_n += 1.0
		elif v.z >= 75.0:
			light_n += 1.0
	return {"team": team_n / n_all, "dark": dark_n / n_all, "light": light_n / n_all, "cells": top.size(), "grid": top}


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
	var ids: PackedStringArray = _napc_unit_ids()
	ids.append("structure.napc.bulwark_cannon")
	for rid: String in ids:
		var d: Dictionary = _build(rid, &"napc")
		var tv: Dictionary = _top_view((d["mesh"] as Dictionary)["arrays"] as Array)
		var frac: float = float(tv["team"])
		lines.append("%s team %.1f%% dark %.1f%% light %.1f%% (%d cells)" % [rid, frac * 100.0, float(tv["dark"]) * 100.0, float(tv["light"]) * 100.0, int(tv["cells"])])
		t.check(frac > 0.0, rid + " carries a team-colour surface")
		var hi: float = 0.20 if rid.contains("squad") or rid.contains("team") or rid.contains("medic") else 0.14  # squads: small top view, tall backpacks
		t.check(frac >= 0.035 and frac <= hi, "%s team-masked share %.1f%% of the visible top area (bible 5-12 percent, tolerance)" % [rid, frac * 100.0])
		t.check(float(tv["dark"]) >= 0.08, "%s dark mass %.1f%% (three-value rule)" % [rid, float(tv["dark"]) * 100.0])
	t.note("\n".join(lines))


## Filled top-view mask IoU with the centroids aligned (the copy-paste guard of art_direction 5.5.0).
func _iou(a: Dictionary, b: Dictionary) -> float:
	var ga: Dictionary = a["grid"] as Dictionary
	var gb: Dictionary = b["grid"] as Dictionary
	var ca: Vector2 = _centroid(ga)
	var cb: Vector2 = _centroid(gb)
	var shift: Vector2i = Vector2i(roundi(ca.x - cb.x), roundi(ca.y - cb.y))
	var inter: int = 0
	for k: Variant in gb:
		if ga.has((k as Vector2i) + shift):
			inter += 1
	var uni: int = ga.size() + gb.size() - inter
	return float(inter) / float(maxi(uni, 1))


static func _centroid(g: Dictionary) -> Vector2:
	var s: Vector2 = Vector2.ZERO
	for k: Variant in g:
		s += Vector2(k as Vector2i)
	return s / float(maxi(g.size(), 1))


## VQ2A: shape / share / silhouette checks run on the DESIGN-scale geometry (the readability boost is a uniform scale that only
## moves the fixed raster grid of these probes); sizes of the shipped models are covered by test_view_visual_scale.
func test_siblings_and_other_factions_differ(t: TestCtx) -> void:
	ViewConsts.visual_boost_enabled = false
	_test_siblings_and_other_factions_differ_design(t)
	ViewConsts.visual_boost_enabled = true


func _test_siblings_and_other_factions_differ_design(t: TestCtx) -> void:
	_load()
	# siblings built on the same archetype must have different geometry (content hash)
	var groups: Dictionary = {}
	for rid: String in _napc_unit_ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		var aid: String = String(r.arch.id)
		if not groups.has(aid):
			groups[aid] = []
		(groups[aid] as Array).append(rid)
	for aid: Variant in groups:
		var g: Array = groups[aid] as Array
		for i: int in g.size():
			for j: int in range(i + 1, g.size()):
				var a: ViewModelInfo = _build(str(g[i]), &"napc")["info"] as ViewModelInfo
				var b: ViewModelInfo = _build(str(g[j]), &"napc")["info"] as ViewModelInfo
				t.ne(a.content_hash, b.content_hash, "%s vs %s differ" % [g[i], g[j]])
	# unique units are designed variants of the unit they replace: same class, clearly different silhouette
	for pair: Array in [["unit.napc.raptor_multirole_fighter", "unit.napc.falcon_interceptor"], ["unit.napc.beaver_amphibious_apc", "unit.napc.pathfinder_apc"],
			["unit.napc.narwhal_amphibious_tank", "unit.napc.guardian_tank"], ["unit.napc.vanguard_rifle_squad", "unit.napc.rifle_squad"]]:
		var v1: Dictionary = _top_view((_build(str(pair[0]), &"napc")["mesh"] as Dictionary)["arrays"] as Array)
		var v2: Dictionary = _top_view((_build(str(pair[1]), &"napc")["mesh"] as Dictionary)["arrays"] as Array)
		var iou: float = _iou(v1, v2)
		t.note("%s vs %s IoU %.2f" % [pair[0], pair[1], iou])
		t.check(iou < 0.985, "%s is not a copy of %s (IoU %.3f)" % [pair[0], pair[1], iou])
	# against other factions: same archetype, different silhouette (copy-paste guard, IoU <= 0.95)
	var lines: PackedStringArray = PackedStringArray()
	for trip: Array in [["unit.napc.guardian_tank", "unit.def.hammer_tank", &"def"], ["unit.napc.guardian_tank", "unit.nec.leopard_tank", &"nec"],
			["unit.napc.pathfinder_apc", "unit.nec.surveyor_apc", &"nec"], ["unit.napc.paladin_howitzer", "unit.pd.breaker_howitzer", &"pd"],
			["unit.napc.rifle_squad", "unit.nec.jager_squad", &"nec"]]:
		if _book.recipe(StringName(str(trip[1]))) == null:
			continue
		var m1: Dictionary = _top_view((_build(str(trip[0]), &"napc")["mesh"] as Dictionary)["arrays"] as Array)
		var m2: Dictionary = _top_view((_build(str(trip[1]), trip[2] as StringName)["mesh"] as Dictionary)["arrays"] as Array)
		var iou2: float = _iou(m1, m2)
		lines.append("%s vs %s IoU %.2f" % [trip[0], trip[1], iou2])
		t.check(iou2 <= 0.95, "%s vs %s silhouette IoU %.2f <= 0.95" % [trip[0], trip[1], iou2])
	t.note("\n".join(lines))


func test_builds_are_deterministic_and_subfaction_styles_only_add_insignia(t: TestCtx) -> void:
	_load()
	for rid: String in ["unit.napc.guardian_tank", "unit.napc.sentinel_aa", "structure.napc.atlas_kinetic_array"]:
		var h1: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"napc", 10000)["info"] as ViewModelInfo).content_hash
		var h2: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"napc", 10000)["info"] as ViewModelInfo).content_hash
		t.eq(h1, h2, rid + " content hash is stable")
	# subfaction styles keep the faction massing (radius within 10 %) and differ from the vanilla look (accent + kit parts)
	var ids: PackedStringArray = PackedStringArray()
	for n: String in SHARED:
		ids.append("structure.shared." + n)
	for rid: String in ["unit.napc.sentinel_aa", "unit.napc.paladin_howitzer", "unit.napc.guardian_tank"]:
		ids.append(rid)
	for rid2: String in ids:
		var base: ViewModelInfo = _build(rid2, &"napc")["info"] as ViewModelInfo
		for sub: StringName in [&"napc.usa", &"napc.canada", &"napc.mexico"]:
			var si: ViewModelInfo = _build(rid2, sub)["info"] as ViewModelInfo
			t.check(absf(si.radius - base.radius) <= base.radius * 0.12 + 0.05, "%s@%s keeps the faction massing" % [rid2, sub])
			t.ne(si.content_hash, base.content_hash, "%s@%s differs from the vanilla Peace Corps look" % [rid2, sub])
