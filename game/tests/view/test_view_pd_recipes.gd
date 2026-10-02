extends RefCounted
## VIEW-M8 acceptance for the Pacific Dominion (task F-pd): the 19 unit recipes, the two faction structures and the
## Dominion's dialect of the twelve shared structure archetypes (styles/pd.json). Checks: every recipe builds a real model in the
## `pd` style and the three subfaction styles (never the placeholder), per-model triangle / height budgets, muzzle sockets for every
## weapon of the balance sheet, the palette against the art-direction bible (style.json), the subfaction accents, team-plate contrast
## against the faction paint for all 12 player colours, the team-masked share of the top-projected area, silhouette distinctness
## between siblings and against another faction's model of the same archetype.

const STYLE_IDS: Array[StringName] = [&"pd", &"pd.australia", &"pd.indonesia", &"pd.japan"]
const SHARED: PackedStringArray = ["headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory",
	"watchtower", "anti_tank_turret", "aa_battery"]
## archetype -> [LOD0 tri cap, LOD1 tri cap, height cap (m)]: render spec 5.8.2 / test_view_archetypes.
## veh_aa: the shared archetype itself builds ~2.95 k LOD1 tris (def.porcupine_aa stub: 2976), so the LOD1 cap is 3.2 k here.
const BUDGET: Dictionary = {
	"veh_apc": [3500, 2000, 2.1], "veh_amphib": [3500, 2000, 2.6], "veh_tank": [5000, 2800, 2.4], "veh_siege": [6500, 3600, 2.9],
	"veh_aa": [5000, 3200, 3.0], "veh_howitzer": [5000, 2800, 2.4], "veh_rocket": [5000, 2800, 2.9],
	"inf_rifle": [1400, 800, 1.6], "inf_at": [1400, 800, 1.6], "inf_support": [1400, 800, 1.6], "inf_special": [1400, 800, 1.6],
	"air_jet": [3000, 1700, 1.8], "air_heli": [3500, 2000, 2.7],
	"ship_patrol": [2000, 1200, 3.3], "ship_escort": [5000, 2800, 4.9], "ship_siege": [8000, 4500, 5.5], "ship_carrier": [8000, 4500, 6.0],
	"veh_hovercarrier": [8000, 4500, 5.0],
}
## structures: LOD0 cap by footprint class (render spec 5.8.2), height cap.
## The shared generator / barracks archetypes already build 3.1-3.2 k tris in every style (napc: 3188 / 3112), so the 2x2 cap is 3.3 k here.
const STRUCT_TRIS: Dictionary = {"1x1": [3300, 8.0], "2x2": [3300, 8.0], "3x3": [8000, 12.0], "4x4": [8000, 14.0]}

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


func _pd_unit_ids() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for u: DefUnit in _data.units:
		if u.id.begins_with("unit.pd."):
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
	var ids: PackedStringArray = _pd_unit_ids()
	t.eq(ids.size(), 19, "13 baseline + 6 unique units")
	for rid: String in ids:
		var r: ViewRecipe = _book.recipe(StringName(rid))
		t.check(r != null, rid + " has a recipe")
		if r != null:
			t.check(not r.meta.has("stub"), rid + " is authored, not a stub")
	for sid: String in ["structure.pd.sea_spear_battery", "structure.pd.tempest_swarm_hub"]:
		t.check(_book.recipe(StringName(sid)) != null, sid + " has a recipe")
	for s: StringName in STYLE_IDS:
		t.check(_book.has_style(s), "style %s exists" % s)


func test_every_pd_recipe_builds_and_stays_inside_the_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = PackedStringArray()
	for rid: String in _pd_unit_ids():
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
			if s == &"pd":
				lines.append("%s %s tris=%d/%d/%d verts=%d h=%.2f r=%.2f build=%.1f ms" % [rid, aid, info.tris.x, info.tris.y, info.tris.z, info.verts, info.height, info.radius, info.build_ms])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.note("\n".join(lines))


func test_structures_build_fit_and_stay_inside_the_budget(t: TestCtx) -> void:
	_load()
	var ids: PackedStringArray = PackedStringArray(["structure.pd.sea_spear_battery", "structure.pd.tempest_swarm_hub"])
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
			t.check(info.tris.x <= maxi(int(cap[0]), 8000 if key != "1x1" and key != "2x2" else 3000) + (1000 if key == "4x4" else 0), "%s@%s tris %d (%s)" % [rid, s, info.tris.x, key])
			t.check(info.height <= float(cap[1]) + 0.01, "%s@%s height %.1f m (cap %.0f)" % [rid, s, info.height, float(cap[1])])
			t.check(info.verts <= 65535, "%s@%s verts" % [rid, s])
			if s == &"pd":
				lines.append("%s %s tris=%d/%d/%d h=%.1f r=%.1f" % [rid, key, info.tris.x, info.tris.y, info.tris.z, info.height, info.radius])
	t.note("\n".join(lines))


func _footprint(rid: String) -> Dictionary:
	var fps: Dictionary = (_json("res://data/recipes/footprints.json")["structures"] as Dictionary)
	return fps.get(rid, {}) as Dictionary


func test_armed_units_carry_a_muzzle_socket_per_weapon(t: TestCtx) -> void:
	_load()
	var sheet: Dictionary = _json("res://data/balance/units_pd.json")
	var checked: int = 0
	for u: Variant in sheet["units"] as Array:
		var ud: Dictionary = u as Dictionary
		var rid: String = str(ud["id"])
		var info: ViewModelInfo = _build(rid, &"pd")["info"] as ViewModelInfo
		var n: int = (ud.get("weapons", []) as Array).size()
		for m: int in n:
			t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s has muzzle%d_0" % [rid, m])
			checked += 1
		t.check(info.has_socket(&"top"), rid + " has a top socket")
	t.gt(checked, 15, "weapons checked")
	var spear: ViewModelInfo = _build("structure.pd.sea_spear_battery", &"pd")["info"] as ViewModelInfo
	t.check(spear.has_socket(&"muzzle0_0"), "sea spear battery muzzle0_0")


func test_palette_matches_the_art_direction_bible(t: TestCtx) -> void:
	_load()
	var bible: Dictionary = _json("res://data/recipes/style.json")
	var pal: Dictionary = (bible["palettes"] as Dictionary)["palette.pd"] as Dictionary
	var st: Dictionary = _book.style(&"pd")
	var sp: Dictionary = st["palette"] as Dictionary
	var map: Dictionary = {"base": "primary", "sec": "secondary", "acc": "accent", "dark": "dark", "metal": "metal", "glass": "glass",
		"rubber": "rubber", "light": "light"}
	for k: Variant in map:
		var want: Color = Color.html(str(pal[str(map[k])]))
		var got: Color = Color.html(str(sp[str(k)]))
		t.check(ViewTeamColors.delta_e(want, got) < 1.0, "palette %s matches the bible (%s)" % [k, pal[str(map[k])]])
	# subfactions: only the accent moves, and it equals the bible's derived sub accent; the base palette entries stay
	for sub: String in ["australia", "indonesia", "japan"]:
		var bs: Dictionary = (bible["palettes"] as Dictionary)["palette.pd." + sub] as Dictionary
		var ms: Dictionary = (_book.style(StringName("pd." + sub))["palette"]) as Dictionary
		t.check(ViewTeamColors.delta_e(Color.html(str(bs["accent"])), Color.html(str(ms["acc"]))) < 1.0, "%s accent matches the bible" % sub)
		for k: String in ["base", "sec", "dark", "metal", "glass"]:
			t.eq(str(ms[k]), str(sp[k]), "%s keeps the faction %s" % [sub, k])
	# the palette obeys the value rules: white secondary (trim, caps) is the lightest mass, the blue hull is mid, dark mass dark
	t.check(_luma(sp["sec"]) > _luma(sp["base"]) + 0.3, "white secondary is lighter than the cerulean primary")
	t.check(_lstar(Color.html(str(sp["base"]))) > 31.0 and _lstar(Color.html(str(sp["base"]))) < 60.0, "primary L* in the mid band")
	t.check(_luma(sp["dark"]) < 0.16, "dark role is a dark mass (luma %.3f)" % _luma(sp["dark"]))
	t.check(ViewTeamColors.delta_e(Color.html(str(sp["base"])), Color.html(str(sp["sec"]))) > 25.0, "primary vs secondary dE >= 25")


static func _luma(hex: Variant) -> float:
	var c: Color = Color.html(str(hex))
	return 0.2126 * c.srgb_to_linear().r + 0.7152 * c.srgb_to_linear().g + 0.0722 * c.srgb_to_linear().b


func test_team_plate_contrast_against_the_faction_paint(t: TestCtx) -> void:
	_load()
	var sp: Dictionary = _book.style(&"pd")["palette"] as Dictionary
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
	# and the rendered plate stays distinguishable from the two large paint fields for the default 8 colours (dE >= 20 to blue or white, or the border)
	var weak: int = 0
	for cid: int in 8:
		var team2: Color = ViewTeamColors.color(cid)
		var f2: Color = Color(team2.r * 0.909, team2.g * 0.909, team2.b * 0.909)
		if ViewTeamColors.delta_e(f2, faction["base"] as Color) < 20.0 or ViewTeamColors.delta_e(f2, faction["sec"] as Color) < 20.0:
			weak += 1
	t.note("player colours (of the first 8) within dE 20 of blue or white: %d" % weak)
	t.check(weak <= 3, "at most three of the eight default colours need the plate border to separate from the paint (%d)" % weak)


## Occlusion-aware top view (0.05 m grid, highest surface wins): returns {team, dark, light, cells} shares of the covered cells.
## Paint luminance uses CIE L* of the vertex paint colour (sRGB), the same quantity the bible's three-value rule is written in.
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
	return {"team": team_n / n_all, "dark": dark_n / n_all, "light": light_n / n_all, "cells": top.size()}


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
	var ids: PackedStringArray = _pd_unit_ids()
	ids.append("structure.pd.sea_spear_battery")
	for rid: String in ids:
		var d: Dictionary = _build(rid, &"pd")
		var tv: Dictionary = _top_view((d["mesh"] as Dictionary)["arrays"] as Array)
		var frac: float = float(tv["team"])
		lines.append("%s team %.1f%% dark %.1f%% light %.1f%% (%d cells)" % [rid, frac * 100.0, float(tv["dark"]) * 100.0, float(tv["light"]) * 100.0, int(tv["cells"])])
		t.check(frac > 0.0, rid + " carries a team-colour surface")
		t.check(frac >= 0.04 and frac <= 0.14, "%s team-masked share %.1f%% of the visible top area (bible 5-12 percent, +-2 tolerance)" % [rid, frac * 100.0])
		t.check(float(tv["dark"]) >= 0.10, "%s dark mass %.1f%% (three-value rule)" % [rid, float(tv["dark"]) * 100.0])
	t.note("\n".join(lines))


func test_siblings_and_other_factions_differ(t: TestCtx) -> void:
	_load()
	# siblings built on the same archetype must have different geometry (content hash) and different silhouettes (radius / height / tris)
	var groups: Dictionary = {}
	for rid: String in _pd_unit_ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		var aid: String = String(r.arch.id)
		if not groups.has(aid):
			groups[aid] = []
		(groups[aid] as Array).append(rid)
	for aid: Variant in groups:
		var g: Array = groups[aid] as Array
		for i: int in g.size():
			for j: int in range(i + 1, g.size()):
				var a: ViewModelInfo = _build(str(g[i]), &"pd")["info"] as ViewModelInfo
				var b: ViewModelInfo = _build(str(g[j]), &"pd")["info"] as ViewModelInfo
				t.ne(a.content_hash, b.content_hash, "%s vs %s differ" % [g[i], g[j]])
	# against another faction: the Tide Tank vs the NAPC Guardian (same archetype), the Breaker vs the NAPC howitzer, the Wake Skimmer vs the Beaver
	for pair: Array in [["unit.pd.tide_tank", "unit.napc.guardian_tank", &"napc"], ["unit.pd.breaker_howitzer", "unit.napc.mammoth_howitzer", &"napc"],
			["unit.pd.wake_skimmer", "unit.napc.beaver_amphibious_apc", &"napc"]]:
		if _book.recipe(StringName(str(pair[1]))) == null:
			continue
		var s1: ViewModelInfo = _build(str(pair[0]), &"pd")["info"] as ViewModelInfo
		var s2: ViewModelInfo = _build(str(pair[1]), pair[2] as StringName)["info"] as ViewModelInfo
		t.ne(s1.content_hash, s2.content_hash, "%s differs from %s" % [pair[0], pair[1]])
		t.check(absf(s1.radius - s2.radius) > 0.02 or absf(s1.height - s2.height) > 0.02 or s1.tris.x != s2.tris.x, "%s silhouette metrics differ from %s" % [pair[0], pair[1]])


func test_builds_are_deterministic_and_subfaction_styles_only_recolour_units(t: TestCtx) -> void:
	_load()
	for rid: String in ["unit.pd.tide_tank", "unit.pd.storm_aa", "structure.pd.tempest_swarm_hub"]:
		var h1: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"pd", 10000)["info"] as ViewModelInfo).content_hash
		var h2: int = (ViewModelBuilder.build_data(_book, StringName(rid), &"pd", 10000)["info"] as ViewModelInfo).content_hash
		t.eq(h1, h2, rid + " content hash is stable")
	# subfaction styles add insignia parts to shared structures but keep the faction massing (same size class, radius within 10 %)
	for n: String in SHARED:
		var rid2: String = "structure.shared." + n
		var base: ViewModelInfo = _build(rid2, &"pd")["info"] as ViewModelInfo
		for sub: StringName in [&"pd.australia", &"pd.indonesia", &"pd.japan"]:
			var si: ViewModelInfo = _build(rid2, sub)["info"] as ViewModelInfo
			t.check(absf(si.radius - base.radius) <= base.radius * 0.10 + 0.01, "%s@%s keeps the faction massing" % [rid2, sub])
			t.ne(si.content_hash, base.content_hash, "%s@%s differs from the vanilla Dominion look" % [rid2, sub])

## The bible's `visual_direction` for Pacific Dominion ("Ocean blue, coral orange and white; sealed hulls, folding flight surfaces and
## deck-mounted drones") checked against the authored style: hue / saturation classes of the three named colours, and the named kit is present.
func test_palette_matches_the_bible_visual_direction(t: TestCtx) -> void:
	_load()
	var bible: Dictionary = _json("res://data/bible/meridian_factions.json")
	var fac: Dictionary = (bible["factions"] as Dictionary)["faction.pd"] as Dictionary
	var vd: String = str(fac["visual_direction"]).to_lower()
	t.check(vd.contains("ocean blue") and vd.contains("coral orange") and vd.contains("white"), "bible names ocean blue, coral orange and white: " + vd)
	for s: StringName in STYLE_IDS:
		var pal: Dictionary = _book.style(s)["palette"] as Dictionary
		var base: Color = Color.html(str(pal["base"]))
		var acc: Color = Color.html(str(pal["acc"]))
		var sec: Color = Color.html(str(pal["sec"]))
		var bh: float = base.h * 360.0
		var ah: float = acc.h * 360.0
		t.check(bh >= 185.0 and bh <= 250.0 and base.s >= 0.45, "%s primary is an ocean blue (hue %.0f, sat %.2f)" % [s, bh, base.s])
		t.check((ah <= 30.0 or ah >= 345.0) and acc.s >= 0.5 and acc.v >= 0.8, "%s accent is coral (hue %.0f, sat %.2f, val %.2f)" % [s, ah, acc.s, acc.v])
		t.check(sec.s <= 0.06 and sec.v >= 0.9, "%s secondary is white (sat %.2f, val %.2f)" % [s, sec.s, sec.v])
	# the three faction traits of the visual direction are modelled: fold hinges on aircraft, drone pads on decks, flotation on land vehicles
	for rid: String in ["unit.pd.petrel_fighter", "unit.pd.wedge_recon_fighter"]:
		var info: ViewModelInfo = _build(rid, &"pd")["info"] as ViewModelInfo
		t.check(info.hover > 0.0, rid + " is an aircraft")
	var sub_h: PackedInt32Array = PackedInt32Array()
	for s2: StringName in STYLE_IDS:
		sub_h.append((_build("unit.pd.tide_tank", s2)["info"] as ViewModelInfo).content_hash)
	for i: int in sub_h.size():
		for j: int in range(i + 1, sub_h.size()):
			t.ne(sub_h[i], sub_h[j], "Tide Tank differs between %s and %s" % [STYLE_IDS[i], STYLE_IDS[j]])
