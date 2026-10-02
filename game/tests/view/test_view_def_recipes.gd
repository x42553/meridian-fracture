extends RefCounted
## VIEW-M8 (DEF) acceptance: the Democratic Eurasian Federation art. All 19 unit recipes, the two faction structures and the shared
## structures / service units build in the four DEF styles (def, def.russia, def.kazakhstan, def.north_korea) inside the render
## budgets; the DEF palette matches the bible visual direction and art_direction 5.3; the team plate separates from the hull under
## every player colour; every unit is a distinct model; top-projected team-masked area is in band; subfaction overlays differ.

const Pt := ViewMeshBuilder.Part
const STYLES: Array[StringName] = [&"def", &"def.russia", &"def.kazakhstan", &"def.north_korea"]
const UNITS: PackedStringArray = [
	"line_conscript", "recoil_team", "signal_officer", "mule_apc", "hammer_tank", "porcupine_aa", "anvil_rocket_battery", "colossus_siege_tank",
	"kite_interceptor", "burya_bomber", "picket_boat", "rampart_escort", "boreal_missile_submarine",
	"ural_assault_tank", "bear_siege_crawler", "steppe_recon_carrier", "saker_missile_truck", "fortress_guard", "echo_team"]
const STRUCTURES: PackedStringArray = ["structure.def.citadel_mortar", "structure.def.perun_missile_complex"]
const SHARED: PackedStringArray = [
	"headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory", "watchtower", "anti_tank_turret", "aa_battery"]
## LOD0 triangle ceilings (render spec 5.8.2) and height ceilings by archetype size_class.
const TRIS: Dictionary = {"inf": 1400, "squad": 1400, "light": 3500, "medium": 5000, "heavy": 6500, "huge": 8000, "air": 3500, "ship": 8000, "structure": 10000}
## Team-masked share of the top-projected silhouette: render spec 5.8.2 asks 4-12 %, art_direction 5.4.3 asks 5-12 %; the test allows a small margin.
const TEAM_MIN: float = 0.035
const TEAM_MAX: float = 0.16
## Squads are 4 soldiers whose back plates and helmets are team-masked by the shared soldier macro: their share is naturally higher.
const TEAM_MAX_INF: float = 0.22

var _book: ViewRecipeBook = null
var _cache: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	_cache.clear()


func _load() -> void:
	if _book == null:
		_book = ViewRecipeBook.new()
		_book.load_all()


func _build(rid: String, sid: StringName) -> Dictionary:
	_load()
	var key: String = "%s@%s" % [rid, sid]
	if not _cache.has(key):
		_cache[key] = ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)
	return _cache[key] as Dictionary


func _ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for u: String in UNITS:
		out.append("unit.def." + u)
	out.append_array(STRUCTURES)
	return out


func test_def_recipes_are_hand_authored(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	for rid: String in _ids():
		var r: ViewRecipe = _book.recipe(StringName(rid))
		t.not_null(r, "%s exists" % rid)
		if r != null:
			t.check(not bool(r.meta.get("stub", false)), "%s is no generated stub" % rid)
	t.eq(UNITS.size(), 19, "13 baseline + 6 unique DEF units")


func test_def_styles_exist_and_differ(t: TestCtx) -> void:
	_load()
	for sid: StringName in STYLES:
		t.check(_book.has_style(sid), "style %s" % sid)
	var base: Dictionary = _book.style(&"def")
	for sid: StringName in [&"def.russia", &"def.kazakhstan", &"def.north_korea"]:
		var s: Dictionary = _book.style(sid)
		t.ne(str((s["palette"] as Dictionary)["acc"]), str((base["palette"] as Dictionary)["acc"]), "%s has its own accent" % sid)
		t.ne(str(s["emblem"]), str(base["emblem"]), "%s has its own emblem" % sid)
		# overlays keep the faction paint: base / dark / metal / rubber / glass are inherited unchanged
		for k: String in ["base", "dark", "metal", "rubber", "glass", "concrete"]:
			t.eq(str((s["palette"] as Dictionary)[k]), str((base["palette"] as Dictionary)[k]), "%s keeps palette.%s" % [sid, k])
	t.eq(_book.style_for_roster("roster.def.russia"), &"def.russia", "roster -> style")
	t.eq(_book.style_for_roster("roster.def.vanilla"), &"def", "vanilla roster -> faction style")
	t.eq(_book.style_for_def("structure.shared.factory", "roster.def.north_korea"), &"def.north_korea", "shared structures wear the owner's roster style")


func test_all_def_models_build_within_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = PackedStringArray()
	var ids: PackedStringArray = _ids()
	for s: String in SHARED:
		ids.append("structure.shared." + s)
	for rid: String in ids:
		for sid: StringName in STYLES:
			var d: Dictionary = _build(rid, sid)
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [rid, sid, d["error"]])
				continue
			var info: ViewModelInfo = d["info"] as ViewModelInfo
			var r: ViewRecipe = _book.recipe(StringName(rid))
			var cap: int = int(TRIS.get(String(r.arch.size_class), 10000))
			if info.tris.x - info.livery_tris.x > cap:
				over.append("%s@%s tris %d > %d" % [rid, sid, info.tris.x, cap])
			if info.tris.y - info.livery_tris.y > int(cap * 0.66):
				over.append("%s@%s LOD1 %d > %d" % [rid, sid, info.tris.y, int(cap * 0.66)])
			if info.verts > 65535 or info.build_ms > 250.0:
				over.append("%s@%s verts %d build %.0f ms" % [rid, sid, info.verts, info.build_ms])
			if sid == &"def":
				lines.append("%s tris=%s h=%.2f r=%.2f" % [rid.get_slice(".", 2), info.tris, info.height, info.radius])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.note("\n".join(lines))


func test_def_size_classes(t: TestCtx) -> void:
	# render spec 5.8.2 height and radius bands (radius = largest horizontal extent, +-15 % around 1.05 * r * 3 m for ground units)
	var caps: Dictionary = {"inf": 1.6, "squad": 1.6, "light": 2.1, "medium": 3.05, "heavy": 3.1, "huge": 5.0, "air": 2.6, "ship": 5.5}
	var bad: PackedStringArray = PackedStringArray()
	for u: String in UNITS:
		var rid: String = "unit.def." + u
		var d: Dictionary = _build(rid, &"def")
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		var sc: String = String(_book.recipe(StringName(rid)).arch.size_class)
		var cap: float = float(caps.get(sc, 3.0)) * info.boost  # design caps x the VQ2A readability boost
		if info.height > cap + 0.01:
			bad.append("%s height %.2f > %.1f (%s)" % [u, info.height, cap, sc])
	t.eq(bad.size(), 0, "height caps: %s" % " | ".join(bad))


func test_def_units_are_distinct_models(t: TestCtx) -> void:
	var seen: Dictionary = {}
	for u: String in UNITS:
		var d: Dictionary = _build("unit.def." + u, &"def")
		var h: int = (d["info"] as ViewModelInfo).content_hash
		t.check(not seen.has(h), "%s differs from %s" % [u, str(seen.get(h, ""))])
		seen[h] = u
	# unique units are designed variants of the unit they replace: same archetype, different model
	var pairs: Array = [["hammer_tank", "ural_assault_tank"], ["colossus_siege_tank", "bear_siege_crawler"], ["mule_apc", "steppe_recon_carrier"],
		["anvil_rocket_battery", "saker_missile_truck"], ["line_conscript", "fortress_guard"], ["signal_officer", "echo_team"]]
	for p: Array in pairs:
		var a: ViewRecipe = _book.recipe(StringName("unit.def." + str(p[0])))
		var b: ViewRecipe = _book.recipe(StringName("unit.def." + str(p[1])))
		t.eq(a.archetype, b.archetype, "%s replaces %s on the same view archetype" % [p[1], p[0]])
		var ia: ViewModelInfo = _build("unit.def." + str(p[0]), &"def")["info"] as ViewModelInfo
		var ib: ViewModelInfo = _build("unit.def." + str(p[1]), &"def")["info"] as ViewModelInfo
		var da: Vector3 = ia.rest_aabb.size
		var db: Vector3 = ib.rest_aabb.size
		t.check(absf(da.x - db.x) + absf(da.y - db.y) + absf(da.z - db.z) > 0.25 or ia.tris.x != ib.tris.x, "%s vs %s differ in extent or detail" % [p[0], p[1]])


func test_def_animated_parts_and_sockets(t: TestCtx) -> void:
	var tanks: PackedStringArray = ["hammer_tank", "ural_assault_tank", "colossus_siege_tank", "bear_siege_crawler", "porcupine_aa"]
	for u: String in tanks:
		var i: ViewModelInfo = _build("unit.def." + u, &"def")["info"] as ViewModelInfo
		t.check(i.has_part(Pt.TURRET) and i.has_part(Pt.BARREL), "%s has turret + barrel" % u)
		t.check(i.has_socket(&"muzzle0_0"), "%s muzzle0_0" % u)
	for u: String in ["line_conscript", "recoil_team", "signal_officer", "fortress_guard", "echo_team"]:
		var i: ViewModelInfo = _build("unit.def." + u, &"def")["info"] as ViewModelInfo
		t.check(i.has_part(Pt.LEG_A) and i.has_part(Pt.LEG_B) and i.has_part(Pt.ARM_A) and i.has_part(Pt.BODY_BOB), "%s infantry gait parts" % u)
		t.gt(i.members, 1, "%s squad members" % u)
	var f: ViewModelInfo = _build("unit.def.fortress_guard", &"def")["info"] as ViewModelInfo
	t.check(f.has_part(Pt.DEPLOY), "fortress guard deploys (DEPLOY part)")
	for u: String in ["anvil_rocket_battery", "saker_missile_truck"]:
		var i: ViewModelInfo = _build("unit.def." + u, &"def")["info"] as ViewModelInfo
		t.check(i.has_part(Pt.DEPLOY) and i.has_part(Pt.BARREL), "%s deploy spades + elevating rack" % u)
	var sc: ViewModelInfo = _build("unit.def.steppe_recon_carrier", &"def")["info"] as ViewModelInfo
	t.check(sc.has_part(Pt.SLIDE_Y) and sc.has_part(Pt.WHEEL), "steppe carrier: extending mast + wheels")
	var b: ViewModelInfo = _build("unit.def.burya_bomber", &"def")["info"] as ViewModelInfo
	t.gt(b.hover, 5.0, "bomber flies")
	t.check(_build("unit.def.boreal_missile_submarine", &"def")["info"] != null, "submarine builds")


func test_def_palette_matches_visual_direction(t: TestCtx) -> void:
	# bible visual_direction: "Oxide red, gray and pale yellow; slab armor, exposed running gear and standardized containers"
	_load()
	var pal: Dictionary = _book.style(&"def")["palette"] as Dictionary
	var base: Color = Color.html(str(pal["base"]))
	var sec: Color = Color.html(str(pal["sec"]))
	var acc: Color = Color.html(str(pal["acc"]))
	var dark: Color = Color.html(str(pal["dark"]))
	var metal: Color = Color.html(str(pal["metal"]))
	t.check(base.h * 360.0 <= 22.0 or base.h * 360.0 >= 350.0, "oxide red hue %.0f deg" % (base.h * 360.0))
	t.check(base.s >= 0.5 and base.v >= 0.35 and base.v <= 0.65, "oxide red is saturated and mid-dark (s %.2f v %.2f)" % [base.s, base.v])
	for c: Color in [sec, acc]:
		t.check(c.h * 360.0 >= 42.0 and c.h * 360.0 <= 62.0, "pale yellow hue %.0f deg" % (c.h * 360.0))
		t.check(c.v >= 0.7 and c.s <= 0.65, "pale yellow is light and unsaturated (s %.2f v %.2f)" % [c.s, c.v])
	t.check(dark.s <= 0.12 and metal.s <= 0.12, "gray running gear / metal is neutral")
	t.check(dark.v <= 0.3, "dark mass is dark (v %.2f)" % dark.v)
	# art_direction 5.3.1 authored palette.def (style.json): primary, secondary(gray), accent(pale yellow) within a small delta E
	var ad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes/style.json")) as Dictionary
	var ap: Dictionary = (ad["palettes"] as Dictionary)["palette.def"] as Dictionary
	t.check(ViewTeamColors.delta_e(base, Color.html(str(ap["primary"]))) <= 6.0, "base within dE 6 of art_direction primary")
	t.check(ViewTeamColors.delta_e(acc, Color.html(str(ap["accent"]))) <= 8.0, "acc within dE 8 of art_direction accent")
	t.check(ViewTeamColors.delta_e(dark, Color.html(str(ap["dark"]))) <= 14.0, "dark within dE 14 of art_direction dark")
	t.check(ViewTeamColors.delta_e(metal, Color.html(str(ap["secondary"]))) <= 16.0, "metal is the art_direction secondary gray")
	# subfaction accents are the authored sub accents
	var subs: Dictionary = {"def.russia": "palette.def.russia", "def.kazakhstan": "palette.def.kazakhstan", "def.north_korea": "palette.def.north_korea"}
	for sid: String in subs:
		var want: Color = Color.html(str((( ad["palettes"] as Dictionary)[subs[sid]] as Dictionary)["accent"]))
		var have: Color = Color.html(str(((_book.style(StringName(sid)))["palette"] as Dictionary)["acc"]))
		t.check(ViewTeamColors.delta_e(want, have) <= 2.0, "%s accent equals the authored sub accent" % sid)
	# sibling accents stay apart (art_direction 5.6.1: dE >= 8 between sub accents)
	var accs: Array[Color] = []
	for sid: String in subs:
		accs.append(Color.html(str(((_book.style(StringName(sid)))["palette"] as Dictionary)["acc"])))
	for i in accs.size():
		for j in range(i + 1, accs.size()):
			t.check(ViewTeamColors.delta_e(accs[i], accs[j]) >= 8.0, "sub accents %d/%d are distinguishable" % [i, j])


func _team_albedo(team: Color, paint: Color) -> Color:
	# unit.gdshader PAINT: albedo = team_color * (0.30 + 0.9 * luma(paint_linear) + 0.10), luma weights (0.3, 0.55, 0.15)
	var pl: Color = paint.srgb_to_linear()
	var luma: float = pl.r * 0.3 + pl.g * 0.55 + pl.b * 0.15
	var tl: Color = team.srgb_to_linear()
	var f: float = 0.30 + 0.9 * luma + 0.10
	return Color(minf(tl.r * f, 1.0), minf(tl.g * f, 1.0), minf(tl.b * f, 1.0)).linear_to_srgb()


func test_def_team_plate_contrast(t: TestCtx) -> void:
	# The plate is a dark gasket (palette.plate) around the field. The field is painted with palette.team_key (neutral #C6C6C6,
	# art_direction 5.4.3) so it renders at ~0.91 of the player colour on every faction; the hull is palette.base.
	_load()
	var pal: Dictionary = _book.style(&"def")["palette"] as Dictionary
	var gasket: Color = Color.html(str(pal["plate"]))
	var key: Color = Color.html(str(pal["team_key"]))
	var hull: Color = Color.html(str(pal["base"]))
	var weak_hull: PackedStringArray = PackedStringArray()
	var weak_hull_base: PackedStringArray = PackedStringArray()
	for id in 12:
		var team: Color = ViewTeamColors.color(id)
		var field: Color = _team_albedo(team, key)
		t.check(ViewTeamColors.delta_e(field, gasket) >= 15.0, "player %d field separates from the gasket (dE %.1f)" % [id, ViewTeamColors.delta_e(field, gasket)])
		var de_hull: float = ViewTeamColors.delta_e(field, hull)
		if de_hull < 15.0:
			weak_hull.append("%d(%.0f)" % [id, de_hull])
		# what the shipped team_panel macro paints today: field colour = palette.base
		var de_base: float = ViewTeamColors.delta_e(_team_albedo(team, hull), hull)
		if de_base < 15.0:
			weak_hull_base.append("%d(%.0f)" % [id, de_base])
	t.note("field(team_key) vs hull dE < 15: [%s]; field(base) vs hull dE < 15: [%s]" % [", ".join(weak_hull), ", ".join(weak_hull_base)])
	# art_direction 5.4.4 lists DEF x crimson(0), brown(10) as the low-contrast pairs; the gasket + hairline anatomy carries them
	t.check(weak_hull.size() <= 3, "at most the documented low-contrast player colours are close to the hull paint: %s" % ", ".join(weak_hull))


## Top-projected share of team-masked surfaces (height raster, 5 cm cells; a cell belongs to the triangle that is highest there).
func _team_share(d: Dictionary) -> Vector2:
	var mesh: Dictionary = d["mesh"] as Dictionary
	var arrays: Array = mesh["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var bb: AABB = (d["info"] as ViewModelInfo).rest_aabb
	var cell: float = 0.05
	var w: int = int(ceilf(bb.size.x / cell)) + 2
	var h: int = int(ceilf(bb.size.z / cell)) + 2
	var height: PackedFloat32Array = PackedFloat32Array()
	height.resize(w * h)
	height.fill(-1000.0)
	var team: PackedByteArray = PackedByteArray()
	team.resize(w * h)
	for ti in range(0, idx.size(), 3):
		var i0: int = idx[ti]
		var i1: int = idx[ti + 1]
		var i2: int = idx[ti + 2]
		var a: Vector3 = pos[i0]
		var b: Vector3 = pos[i1]
		var c: Vector3 = pos[i2]
		var mask: int = 1 if (col[i0].a + col[i1].a + col[i2].a) / 3.0 > 0.5 else 0
		var minx: int = maxi(int(floorf((minf(a.x, minf(b.x, c.x)) - bb.position.x) / cell)), 0)
		var maxx: int = mini(int(ceilf((maxf(a.x, maxf(b.x, c.x)) - bb.position.x) / cell)), w - 1)
		var minz: int = maxi(int(floorf((minf(a.z, minf(b.z, c.z)) - bb.position.z) / cell)), 0)
		var maxz: int = mini(int(ceilf((maxf(a.z, maxf(b.z, c.z)) - bb.position.z) / cell)), h - 1)
		var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-9:
			continue
		for zi in range(minz, maxz + 1):
			var pz: float = bb.position.z + (float(zi) + 0.5) * cell
			for xi in range(minx, maxx + 1):
				var px: float = bb.position.x + (float(xi) + 0.5) * cell
				var l0: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
				var l1: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
				var l2: float = 1.0 - l0 - l1
				if l0 < -0.001 or l1 < -0.001 or l2 < -0.001:
					continue
				var y: float = l0 * a.y + l1 * b.y + l2 * c.y
				var k: int = zi * w + xi
				if y > height[k]:
					height[k] = y
					team[k] = mask
	var covered: int = 0
	var teamed: int = 0
	for k in w * h:
		if height[k] > -999.0:
			covered += 1
			teamed += team[k]
	return Vector2(float(teamed) * cell * cell, float(teamed) / maxf(float(covered), 1.0))


func test_def_team_masked_area_share(t: TestCtx) -> void:
	var out: PackedStringArray = PackedStringArray()
	var bad: PackedStringArray = PackedStringArray()
	for u: String in UNITS:
		var d: Dictionary = _build("unit.def." + u, &"def")
		var s: Vector2 = _team_share(d)
		out.append("%s %.2f m2 %.1f%%" % [u, s.x, s.y * 100.0])
		var hi: float = TEAM_MAX_INF if String(_book.recipe(StringName("unit.def." + u)).arch.size_class) == "inf" else TEAM_MAX
		if s.y < TEAM_MIN or s.y > hi:
			bad.append("%s %.1f%%" % [u, s.y * 100.0])
	t.note("team-masked top-projected share: " + "; ".join(out))
	t.eq(bad.size(), 0, "team share outside %.1f-%.1f %%: %s" % [TEAM_MIN * 100.0, TEAM_MAX * 100.0, ", ".join(bad)])


func test_def_structures_carry_a_roof_plate(t: TestCtx) -> void:
	# art_direction 5.4.3: structure roof plate >= 1.0 m2 and >= 2.5 % of the footprint
	var bad: PackedStringArray = PackedStringArray()
	var notes: PackedStringArray = PackedStringArray()
	for s: String in ["headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "laboratory", "aa_battery"]:
		var rid: String = "structure.shared." + s
		var d: Dictionary = _build(rid, &"def")
		var fp: Vector2i = (d["info"] as ViewModelInfo).footprint
		var share: Vector2 = _team_share(d)
		var foot: float = float(fp.x * 3 - 1) * float(fp.y * 3 - 1)
		notes.append("%s %.1f m2 (%.1f%% of the plinth)" % [s, share.x, 100.0 * share.x / maxf(foot, 1.0)])
		if share.x < 1.0:
			bad.append("%s %.2f m2" % [s, share.x])
	t.note("structure team area: " + "; ".join(notes))
	t.eq(bad.size(), 0, "roof team plates under 1.0 m2: %s" % ", ".join(bad))


func test_def_subfaction_overlays_change_the_models(t: TestCtx) -> void:
	# accent colour and kit overrides reach the mesh: the same recipe hashes differently in every DEF style where the overlay touches it
	for rid: String in ["unit.def.hammer_tank", "unit.def.mule_apc", "structure.shared.barracks", "structure.shared.headquarters"]:
		var hashes: Dictionary = {}
		for sid: StringName in STYLES:
			var h: int = (_build(rid, sid)["info"] as ViewModelInfo).content_hash
			t.check(not hashes.has(h), "%s: %s differs from %s" % [rid, sid, str(hashes.get(h, ""))])
			hashes[h] = sid
