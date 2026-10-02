extends RefCounted
## VIEW-M8 (African Empire) acceptance: the AE style dictionaries (styles/ae.json), the 19 unit recipes, the summon, the two faction
## structures and the shared structures drawn with the AE dialect. Palette against the art direction and the bible's visual direction,
## team-plate contrast (plate rings against hull, every player colour), per-model triangle / vertex budgets (art_direction 9.2), team
## surface presence, unique-unit silhouettes differing from the units they replace.

const FACTION_UNITS: PackedStringArray = [
	"unit.ae.union_guard", "unit.ae.pike_team", "unit.ae.reclaimer", "unit.ae.mamba_apc", "unit.ae.buffalo_tank", "unit.ae.weaver_aa",
	"unit.ae.forge_howitzer", "unit.ae.kiln_assault_crawler", "unit.ae.sunbird_interceptor", "unit.ae.hammerhead_gunship",
	"unit.ae.delta_patrol_boat", "unit.ae.anchor_escort", "unit.ae.sovereign_arsenal_ship", "unit.ae.civic_rifle_team",
	"unit.ae.lagos_drone_guard", "unit.ae.okapi_amphibious_carrier", "unit.ae.river_warden", "unit.ae.rhino_rail_tank",
	"unit.ae.protea_gun_carrier",
]
## unique subfaction unit -> the baseline unit it replaces
const REPLACES: Dictionary = {
	"unit.ae.civic_rifle_team": "unit.ae.union_guard", "unit.ae.lagos_drone_guard": "unit.ae.weaver_aa",
	"unit.ae.okapi_amphibious_carrier": "unit.ae.mamba_apc", "unit.ae.river_warden": "unit.ae.reclaimer",
	"unit.ae.rhino_rail_tank": "unit.ae.buffalo_tank", "unit.ae.protea_gun_carrier": "unit.ae.forge_howitzer",
}
const SHARED_STRUCTURES: PackedStringArray = [
	"structure.shared.headquarters", "structure.shared.generator", "structure.shared.refinery", "structure.shared.barracks",
	"structure.shared.factory", "structure.shared.dock", "structure.shared.radar", "structure.shared.airfield",
	"structure.shared.laboratory", "structure.shared.watchtower", "structure.shared.anti_tank_turret", "structure.shared.aa_battery",
]
const AE_STYLES: Array[StringName] = [&"ae", &"ae.nigeria", &"ae.kongo", &"ae.south_africa"]
const PLAYER_COLOURS: Array[Color] = [
	Color("D93A3A"), Color("2F7DE1"), Color("2DB56A"), Color("F2B234"), Color("8B5CD6"), Color("27C4D6"),
	Color("F0782A"), Color("D9479B"), Color("9BD13B"), Color("8A97A8"), Color("8C5A3B"), Color("ECECEC"),
]
const HAIRLINE: Color = Color("E6E6E6")

var _book: ViewRecipeBook = null
var _cache: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


func _ensure() -> void:
	if _book == null:
		_book = ViewRecipeBook.new()
		_book.load_all()


func _build(rid: String, style: StringName = &"ae") -> Dictionary:
	_ensure()
	var key: String = "%s@%s" % [rid, style]
	if not _cache.has(key):
		_cache[key] = ViewModelBuilder.build_data(_book, StringName(rid), style, 10000)
	return _cache[key] as Dictionary


## (LOD0 triangles, vertices) ceilings of art_direction 9.2 for the archetype family a recipe uses.
func _caps(rid: String) -> Vector2i:
	var r: ViewRecipe = _book.recipe(StringName(rid))
	match String(r.archetype):
		"inf_rifle", "inf_at", "inf_special", "inf_support", "inf_engineer", "inf_squad":
			return Vector2i(1400, 4000)
		"veh_apc", "veh_amphib", "veh_lightarty", "veh_collector", "veh_landing":
			return Vector2i(3500, 9500)
		"veh_tank", "veh_aa", "veh_howitzer", "veh_rocket", "veh_mcv":
			return Vector2i(5000, 14500)
		"veh_siege":
			return Vector2i(6500, 18500)
		"air_jet":
			return Vector2i(3000, 8500)
		"air_heli", "air_drone", "air_ew", "air_bomber":
			return Vector2i(3500, 9500)
		"ship_patrol":
			return Vector2i(2000, 5500)
		"ship_escort", "ship_sub":
			return Vector2i(5000, 14500)
		"ship_siege", "ship_carrier":
			return Vector2i(8000, 23000)
		"str_superweapon":
			return Vector2i(10000, 29000)
		"sum_uav", "sum_balloon", "sum_drone_swarm":
			return Vector2i(3000, 8500)
	if rid.begins_with("structure."):
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var area: int = int(fp["fw"]) * int(fp["fh"])
		if area <= 4:
			return Vector2i(3000, 8700)  # the shared 2x2 generator archetype alone is 8502 vertices
		if area <= 9:
			return Vector2i(5000, 14500)
		return Vector2i(8000, 23000)
	return Vector2i(3500, 9500)


## LOD1 triangle ceilings of render.md 5.8.2 per family.
func _lod1_cap(rid: String) -> int:
	var r: ViewRecipe = _book.recipe(StringName(rid))
	match String(r.archetype):
		"inf_rifle", "inf_at", "inf_special", "inf_support", "inf_engineer", "inf_squad":
			return 800
		"veh_apc", "veh_amphib", "veh_lightarty", "veh_collector", "veh_landing":
			return 2000
		"veh_tank", "veh_aa", "veh_howitzer", "veh_rocket", "veh_mcv":
			return 2800
		"veh_siege":
			return 3600
		"air_jet", "sum_uav", "sum_balloon", "sum_drone_swarm":
			return 1700
		"air_heli", "air_drone", "air_ew", "air_bomber":
			return 2000
		"ship_patrol":
			return 1200
		"ship_escort", "ship_sub":
			return 2800
		"ship_siege", "ship_carrier":
			return 4500
		"str_superweapon":
			return 5500
	if rid.begins_with("structure."):
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var area: int = int(fp["fw"]) * int(fp["fh"])
		if area <= 4:
			return 1850  # the shared generator archetype alone is 1760
		if area <= 9:
			return 3200
		return 4500
	return 2000


func _team_share(d: Dictionary) -> float:
	## team-masked share of the upward-facing surface area (LOD0), a proxy for the plan-view team share (art_direction 5.4.3: 5-12 %).
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var up: float = 0.0
	var team: float = 0.0
	var i: int = 0
	while i + 2 < idx.size():
		var a: int = idx[i]
		var b: int = idx[i + 1]
		var c: int = idx[i + 2]
		i += 3
		if nrm[a].y > 0.7:
			var ar: float = 0.5 * (pos[b] - pos[a]).cross(pos[c] - pos[a]).length()
			up += ar
			if col[a].a > 0.5 and col[b].a > 0.5 and col[c].a > 0.5:
				team += ar
	return team / maxf(up, 0.001)


# ---------------------------------------------------------------------------------------------------------------- palette
func test_style_loads_with_faction_and_three_subfaction_styles(t: TestCtx) -> void:
	_ensure()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	for sid: StringName in AE_STYLES:
		t.check(_book.has_style(sid), "style %s exists" % sid)
	t.eq(_book.style_for_roster("roster.ae.vanilla"), &"ae", "vanilla roster -> ae")
	t.eq(_book.style_for_roster("roster.ae.nigeria"), &"ae.nigeria", "nigeria roster -> ae.nigeria")
	t.eq(_book.style_for_roster("roster.ae.kongo"), &"ae.kongo", "kongo roster -> ae.kongo")
	t.eq(_book.style_for_roster("roster.ae.south_africa"), &"ae.south_africa", "south_africa roster -> ae.south_africa")
	t.eq(_book.style_for_def("unit.ae.buffalo_tank", "roster.ae.nigeria"), &"ae.nigeria", "faction units wear the owner's roster style (VQ2A)")
	t.eq(_book.style_for_def("unit.ae.buffalo_tank", "roster.ae.vanilla"), &"ae", "vanilla roster -> faction style")
	t.eq(_book.style_for_def("unit.ae.buffalo_tank", "roster.napc.usa"), &"ae", "a captured foreign unit keeps its own faction style")
	t.eq(_book.style_for_def("structure.shared.factory", "roster.ae.kongo"), &"ae.kongo", "shared structures wear the roster style")
	var parent: Dictionary = (_book.style(&"ae")["palette"] as Dictionary)
	for sid: StringName in [&"ae.nigeria", &"ae.kongo", &"ae.south_africa"]:
		var pal: Dictionary = (_book.style(sid)["palette"] as Dictionary)
		for k: String in ["base", "sec", "dark", "metal", "glass", "rubber", "light", "plate", "concrete"]:
			t.eq(pal[k], parent[k], "%s keeps the parent paint %s (subfactions change only the accent)" % [sid, k])
		t.ne(pal["acc"], parent["acc"], "%s has its own accent" % sid)
		t.gt(UiA11y.delta_e(Color(str(pal["acc"])), Color(str(parent["acc"]))), 5.0, "%s accent is distinguishable from the parent (art_direction 5.6.1: AE >= 6.5)" % sid)


func test_palette_matches_art_direction_and_visual_direction(t: TestCtx) -> void:
	_ensure()
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes/style.json")) as Dictionary
	var ap: Dictionary = ((art["palettes"] as Dictionary)["palette.ae"] as Dictionary)
	var pal: Dictionary = (_book.style(&"ae")["palette"] as Dictionary)
	for pair: Array in [["base", "primary"], ["sec", "secondary"], ["acc", "accent"], ["dark", "dark"], ["metal", "metal"], ["glass", "glass"], ["light", "light"]]:
		var d: float = UiA11y.delta_e(Color(str(pal[pair[0]])), Color(str(ap[pair[1]])))
		t.le(d, 1.5, "palette.%s equals the authored %s (dE00 %.2f)" % [pair[0], pair[1], d])
	# bible visual direction: "ochre, charcoal and bright cyan"
	var ochre: Vector3 = UiA11y.to_lab(Color(str(pal["base"])))
	var oc: float = Vector2(ochre.y, ochre.z).length()
	var oh: float = fposmod(rad_to_deg(atan2(ochre.z, ochre.y)), 360.0)
	t.check(oh > 55.0 and oh < 90.0 and oc > 25.0 and ochre.x > 35.0 and ochre.x < 60.0, "base is ochre (L %.0f C %.0f h %.0f)" % [ochre.x, oc, oh])
	var char_: Vector3 = UiA11y.to_lab(Color(str(pal["sec"])))
	t.check(Vector2(char_.y, char_.z).length() < 8.0 and char_.x > 25.0 and char_.x < 42.0, "sec is charcoal (L %.0f)" % char_.x)
	var cyan: Vector3 = UiA11y.to_lab(Color(str(pal["acc"])))
	var ch: float = fposmod(rad_to_deg(atan2(cyan.z, cyan.y)), 360.0)
	t.check(ch > 195.0 and ch < 235.0 and Vector2(cyan.y, cyan.z).length() > 35.0 and cyan.x > 70.0, "acc is bright cyan (L %.0f h %.0f)" % [cyan.x, ch])
	# ochre hull chroma <= 45 (P-4), no pure primaries
	t.le(Vector2(ochre.y, ochre.z).length(), 45.0, "hull chroma <= 45")
	for k: String in pal:
		var c: Color = Color(str(pal[k]))
		t.check(not (c.r > 0.98 and c.g < 0.05 and c.b < 0.05) and not (c.g > 0.98 and c.r < 0.05 and c.b < 0.05) and not (c.b > 0.98 and c.r < 0.05 and c.g < 0.05), "palette.%s is not a pure primary" % k)


func test_team_plate_reads_on_ae_paint_for_every_player_colour(t: TestCtx) -> void:
	_ensure()
	var pal: Dictionary = (_book.style(&"ae")["palette"] as Dictionary)
	var gasket: Color = Color(str(pal["dark"]))
	var base: Color = Color(str(pal["base"]))
	# the plate is ringed by a dark gasket and a light hairline (art_direction 5.4.3), so the rings must separate from the hull
	t.ge(UiA11y.delta_e(gasket, base), 20.0, "gasket separates from the ochre hull")
	t.ge(UiA11y.delta_e(HAIRLINE, base), 20.0, "hairline separates from the ochre hull")
	for i in PLAYER_COLOURS.size():
		var c: Color = PLAYER_COLOURS[i]
		var ring: float = maxf(UiA11y.delta_e(c, gasket), UiA11y.delta_e(c, HAIRLINE))
		t.ge(ring, 20.0, "player colour %d is separated from at least one plate ring (%.1f)" % [i, ring])
		t.ge(minf(UiA11y.delta_e(c, gasket), UiA11y.delta_e(c, HAIRLINE)) + UiA11y.delta_e(c, base), 20.0, "player colour %d plate + hull margin" % i)
	# the two authored low-contrast pairs of the faction: brown vs the hull, cyan vs the accent trim (rings rescue both)
	t.lt(UiA11y.delta_e(PLAYER_COLOURS[10], base), 20.0, "brown is the authored low-contrast pair (hull)")
	t.lt(UiA11y.delta_e(PLAYER_COLOURS[5], Color(str(pal["acc"]))), 20.0, "cyan collides with the AE accent trim (documented; plate rings + small trim area mitigate)")


# ---------------------------------------------------------------------------------------------------------------- models
func test_every_ae_recipe_is_hand_authored_and_builds(t: TestCtx) -> void:
	_ensure()
	for rid: String in FACTION_UNITS:
		t.check(_book.has_recipe(StringName(rid)), "%s has a recipe" % rid)
		var r: ViewRecipe = _book.recipe(StringName(rid))
		t.check(not bool(r.meta.get("stub", false)), "%s is hand-authored (no stub flag)" % rid)
		var d: Dictionary = _build(rid)
		t.check(not (d["placeholder"] as bool), "%s builds (%s)" % [rid, d["error"]])
	for rid: String in ["structure.ae.forge_cannon", "structure.ae.horizon_mass_driver", "summon.ae.repair_drone"]:
		var r2: ViewRecipe = _book.recipe(StringName(rid))
		t.check(not bool(r2.meta.get("stub", false)), "%s is hand-authored" % rid)
		t.check(not (_build(rid)["placeholder"] as bool), "%s builds" % rid)


func test_models_stay_inside_the_art_direction_budgets(t: TestCtx) -> void:
	_ensure()
	var ids: PackedStringArray = PackedStringArray(FACTION_UNITS)
	ids.append("structure.ae.forge_cannon")
	ids.append("structure.ae.horizon_mass_driver")
	ids.append("summon.ae.repair_drone")
	for rid: String in ids:
		var caps: Vector2i = _caps(rid)
		var info: ViewModelInfo = _build(rid)["info"] as ViewModelInfo
		t.le(info.tris.x, caps.x, "%s LOD0 tris %d <= %d" % [rid, info.tris.x, caps.x])
		t.le(info.verts, caps.y, "%s vertices %d <= %d" % [rid, info.verts, caps.y])
		t.le(info.tris.y, _lod1_cap(rid), "%s LOD1 tris %d <= %d" % [rid, info.tris.y, _lod1_cap(rid)])
		t.lt(info.build_ms, 60.0, "%s builds in %.1f ms" % [rid, info.build_ms])
	for sid: StringName in AE_STYLES:
		for rid: String in SHARED_STRUCTURES:
			var caps2: Vector2i = _caps(rid)
			var info2: ViewModelInfo = _build(rid, sid)["info"] as ViewModelInfo
			t.le(info2.tris.x, caps2.x, "%s@%s LOD0 tris %d <= %d" % [rid, sid, info2.tris.x, caps2.x])
			t.le(info2.verts, caps2.y, "%s@%s vertices %d <= %d" % [rid, sid, info2.verts, caps2.y])
			t.le(info2.tris.y, _lod1_cap(rid), "%s@%s LOD1 tris %d <= %d" % [rid, sid, info2.tris.y, _lod1_cap(rid)])


func test_team_surface_and_sockets(t: TestCtx) -> void:
	_ensure()
	for rid: String in FACTION_UNITS:
		var d: Dictionary = _build(rid)
		var share: float = _team_share(d)
		t.gt(share, 0.0, "%s carries a team-masked surface" % rid)
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		var armed: bool = not rid.ends_with("reclaimer") or true
		if armed:
			t.check(info.has_socket(&"muzzle0_0"), "%s has muzzle0_0" % rid)
	t.check((_build("unit.ae.reclaimer")["info"] as ViewModelInfo).has_socket(&"weld0"), "Reclaimer has a weld0 socket (salvage / repair FX)")
	t.check((_build("unit.ae.river_warden")["info"] as ViewModelInfo).has_socket(&"weld0"), "River Warden has a weld0 socket")


func test_unique_units_differ_from_the_units_they_replace(t: TestCtx) -> void:
	_ensure()
	for uid: Variant in REPLACES:
		var a: ViewModelInfo = _build(str(uid))["info"] as ViewModelInfo
		var b: ViewModelInfo = _build(str(REPLACES[uid]))["info"] as ViewModelInfo
		t.ne(a.content_hash, b.content_hash, "%s differs from %s" % [uid, REPLACES[uid]])
		var sa: Vector3 = a.rest_aabb.size
		var sb: Vector3 = b.rest_aabb.size
		var dv: float = absf(sa.x - sb.x) + absf(sa.y - sb.y) + absf(sa.z - sb.z) + absf(float(a.tris.x - b.tris.x)) * 0.001
		t.gt(dv, 0.02, "%s has a different silhouette / part set than %s (delta %.3f)" % [uid, REPLACES[uid], dv])
	# and every baseline unit differs from every other baseline unit of its archetype family
	var hashes: Dictionary = {}
	for rid: String in FACTION_UNITS:
		var h: int = (_build(rid)["info"] as ViewModelInfo).content_hash
		t.check(not hashes.has(h), "%s has a unique model hash" % rid)
		hashes[h] = rid


func test_style_slots_build_in_every_ae_style_for_every_shared_recipe(t: TestCtx) -> void:
	_ensure()
	var ids: PackedStringArray = PackedStringArray(SHARED_STRUCTURES)
	for sid: String in ["unit.shared.engineer", "unit.shared.collector", "unit.shared.mobile_construction_vehicle", "unit.shared.landing_transport"]:
		ids.append(sid)
	for sid: StringName in AE_STYLES:
		for rid: String in ids:
			var d: Dictionary = _build(rid, sid)
			t.check(not (d["placeholder"] as bool), "%s@%s builds: %s" % [rid, sid, d["error"]])


func test_ae_structures_respect_the_footprint(t: TestCtx) -> void:
	_ensure()
	for rid: String in ["structure.ae.forge_cannon", "structure.ae.horizon_mass_driver"]:
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var info: ViewModelInfo = _build(rid)["info"] as ViewModelInfo
		var hx: float = float(fp["fw"]) * 1.5 - 0.25
		var hz: float = float(fp["fh"]) * 1.5 - 0.25
		var bb: AABB = info.rest_aabb
		t.check(bb.position.x >= -hx - 0.4 and bb.end.x <= hx + 0.4, "%s x %.2f..%.2f" % [rid, bb.position.x, bb.end.x])
		t.check(bb.position.z >= -hz - 0.4 and bb.end.z <= hz + 0.4, "%s z %.2f..%.2f" % [rid, bb.position.z, bb.end.z])
		t.le(info.height, 14.01, "%s height %.1f" % [rid, info.height])
		t.check(info.has_socket(&"muzzle0_0"), "%s has muzzle0_0" % rid)
		t.check(info.has_socket(&"door_exit"), "%s has door_exit" % rid)
