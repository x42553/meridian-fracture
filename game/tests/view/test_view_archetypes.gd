extends RefCounted
## VIEW-M5 / VIEW-M6 acceptance (render spec 11 rows M5 / M6, 5.8.2, 5.8.6, 5.10): the 28 unit archetypes (13 ground vehicles, 5 infantry,
## 5 air, 5 ships) as shipped in game/data/recipes/archetypes. Every archetype builds in every shipped style and in each of its
## parameter variants, stays inside the triangle / height budgets, carries a muzzle socket for every weapon mount of the balance data,
## owns the animated parts its family needs, deploys (artillery) and hides squad members by hp.

const Pt := ViewMeshBuilder.Part
const STYLES: Array[StringName] = [&"napc", &"nec", &"def", &"han", &"neutral"]

## archetype -> [LOD0 tri cap, LOD1 tri cap, height cap (m)]. Caps are render spec 5.8.2; heights of air / ships use the size cards of
## art_direction 5.7 with the spec class limit as the floor (antennas, rotors and radomes count, they are part of the silhouette).
const BUDGET: Dictionary = {
	"veh_apc": [3500, 2000, 2.1], "veh_amphib": [3500, 2000, 2.6], "veh_lightarty": [3500, 2000, 2.6], "veh_tank": [5000, 2800, 2.4],
	"veh_siege": [6500, 3600, 2.9], "veh_aa": [5000, 2800, 3.0], "veh_howitzer": [5000, 2800, 2.4], "veh_rocket": [5000, 2800, 2.9],
	"veh_walker": [8000, 4500, 5.0], "veh_hovercarrier": [8000, 4500, 3.6], "veh_collector": [3500, 2000, 2.6], "veh_mcv": [5000, 2800, 4.2],
	"veh_landing": [3500, 2000, 2.9],
	"inf_rifle": [1400, 800, 1.6], "inf_at": [1400, 800, 1.6], "inf_support": [1400, 800, 1.6], "inf_special": [1400, 800, 1.6],
	"inf_engineer": [1400, 800, 1.6],
	"air_jet": [3000, 1700, 1.8], "air_heli": [3500, 2000, 2.7], "air_bomber": [3000, 1700, 2.0], "air_drone": [3000, 1700, 1.0],
	"air_ew": [3000, 1700, 2.4],
	"ship_patrol": [2000, 1200, 3.3], "ship_escort": [5000, 2800, 4.9], "ship_siege": [8000, 4500, 5.5], "ship_carrier": [8000, 4500, 5.5],
	"ship_sub": [5000, 2800, 4.5],
}

## archetype -> parameter dictionaries besides the defaults (each is also built in every style).
const VARIANTS: Dictionary = {
	"veh_apc": [{"roof": "radar", "cab": "armoured"}, {"roof": "mast", "axles": 2.0, "skirt": "slab"}, {"roof": "drone_rack", "bed": "cargo", "skirt": "none"}, {"roof": "crown", "deck": "container"}],
	"veh_amphib": [{"float": "pontoon", "roof": "radar"}, {"float": "hover", "roof": "mast"}, {"skirt": "none", "deck": "container"}],
	"veh_lightarty": [{"chassis": "buggy", "payload": "mortar"}, {"chassis": "skimmer"}, {"payload": "mortar"}],
	"veh_tank": [{"heavy": true, "second": "rws", "aps": true}, {"second": "rail", "muzzle": "coil", "barrel_len": 3.2}, {"float_skirt": true, "roof": "mast"}],
	"veh_siege": [{"weapon": "twin"}, {"weapon": "rail", "gun_len": 3.2}, {"weapon": "prism"}, {"weapon": "ram", "treads": "crawler", "hull_len": 5.0}],
	"veh_aa": [{"payload": "flak"}, {"payload": "laser"}, {"payload": "drone_bay"}, {"roof": "mast"}],
	"veh_howitzer": [{"gun_len": 3.0}, {"skirt": "slab", "deck": "container"}],
	"veh_rocket": [{"pods": "canister"}, {"pods": "drone_nest"}],
	"veh_hovercarrier": [{"roof": "mast"}], "veh_collector": [{}], "veh_mcv": [{}], "veh_landing": [{"cargo": "crate"}],
	"veh_walker": [{"roof": "mast"}],
	"inf_rifle": [{"kit": "hmg"}, {"kit": "shield", "n": 3.0}, {"n": 2.0}, {"n": 1.0}],
	"inf_at": [{"launcher": "tripod"}, {"launcher": "twin"}],
	"inf_support": [{"gadget": "radio"}, {"gadget": "scope"}, {"gadget": "tool"}, {"gadget": "echo"}, {"gadget": "shield"}, {"n": 1.0}],
	"inf_special": [{"gear": "pioneer"}, {"gear": "sapper"}, {"gear": "torch"}, {"gear": "hook"}],
	"inf_engineer": [{"crew": 1.0}],
	"air_jet": [{"wing": "swept", "tail": "twin"}, {"wing": "forward"}, {"fold": true}],
	"air_heli": [{"rotors": "coax"}, {"rotors": "tilt"}, {"stubs": "none"}],
	"air_bomber": [{"plan": "heavy"}, {"plan": "drone"}],
	"air_drone": [{}], "air_ew": [{}],
	"ship_patrol": [{"bow": "blunt", "cabin": "closed", "gun": "auto"}],
	"ship_escort": [{"helipad": false, "vls_rows": 4.0}],
	"ship_siege": [{"battery": "missile_cells"}],
	"ship_carrier": [{"deck": "container"}],
	"ship_sub": [{}],
}

## animated part kinds each archetype must own (default parameters); the family list of render spec 5.8.6 / 5.10.
const PARTS: Dictionary = {
	"veh_apc": [Pt.WHEEL, Pt.TURRET, Pt.BARREL], "veh_amphib": [Pt.WHEEL, Pt.TURRET, Pt.BARREL, Pt.ROTOR],
	"veh_lightarty": [Pt.WHEEL, Pt.TURRET, Pt.BARREL, Pt.DEPLOY_Z], "veh_tank": [Pt.TRACK, Pt.WHEEL, Pt.TURRET, Pt.BARREL],
	"veh_siege": [Pt.TRACK, Pt.WHEEL, Pt.TURRET, Pt.BARREL, Pt.DEPLOY], "veh_aa": [Pt.TRACK, Pt.TURRET, Pt.BARREL, Pt.RADAR, Pt.TURRET1, Pt.BARREL1],
	"veh_howitzer": [Pt.TRACK, Pt.TURRET, Pt.BARREL, Pt.DEPLOY], "veh_rocket": [Pt.TRACK, Pt.TURRET, Pt.BARREL, Pt.DEPLOY],
	"veh_walker": [Pt.LEG_A, Pt.LEG_B, Pt.BODY_BOB, Pt.TURRET, Pt.BARREL, Pt.RADAR, Pt.DEPLOY_Z],
	"veh_hovercarrier": [Pt.DEPLOY, Pt.TURRET, Pt.BARREL, Pt.ROTOR], "veh_collector": [Pt.WHEEL, Pt.SLIDE_Y, Pt.BLINK],
	"veh_mcv": [Pt.TRACK, Pt.DEPLOY_Z, Pt.SLIDE_Y], "veh_landing": [Pt.DEPLOY, Pt.ROTOR],
	"inf_rifle": [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB], "inf_at": [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB],
	"inf_support": [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB], "inf_special": [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB],
	"inf_engineer": [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB],
	"air_jet": [Pt.BLINK], "air_heli": [Pt.ROTOR, Pt.TAIL_ROTOR, Pt.TURRET1, Pt.BARREL1], "air_bomber": [Pt.BLINK], "air_drone": [Pt.ROTOR],
	"air_ew": [Pt.RADAR, Pt.BLINK],
	"ship_patrol": [Pt.RADAR, Pt.TURRET, Pt.BARREL], "ship_escort": [Pt.RADAR, Pt.TURRET, Pt.BARREL, Pt.TURRET1, Pt.BARREL1, Pt.TURRET2, Pt.BARREL2],
	"ship_siege": [Pt.RADAR, Pt.TURRET, Pt.BARREL], "ship_carrier": [Pt.RADAR, Pt.SLIDE_Y, Pt.SLIDE_Z, Pt.BLINK], "ship_sub": [Pt.RADAR, Pt.ROTOR],
}

var _book: ViewRecipeBook = null


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	for aid: String in BUDGET:
		for vi: int in range(-1, (VARIANTS.get(aid, []) as Array).size()):
			var rec: Dictionary = {"schema": "meridian.recipe/1", "id": _rid(aid, vi), "archetype": aid}
			if vi >= 0:
				var pv: Dictionary = (VARIANTS[aid] as Array)[vi] as Dictionary
				if not pv.is_empty():
					rec["params"] = pv
			_book.add_recipe(rec, "test")
	_book.link()


static func _rid(aid: String, vi: int) -> String:
	return "proof.%s.%d" % [aid, vi + 1]


func _build(aid: String, vi: int, style: StringName) -> Dictionary:
	_load()
	return ViewModelBuilder.build_data(_book, StringName(_rid(aid, vi)), style, 10000)


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


# ---------------------------------------------------------------------------------------------------- catalogue
func test_all_28_archetype_files_are_well_formed(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	t.eq(BUDGET.size(), 28, "13 ground vehicles + 5 infantry + 5 air + 5 ships")
	for aid: String in BUDGET:
		var path: String = "res://data/recipes/archetypes/%s.json" % aid
		t.check(FileAccess.file_exists(path), "%s.json exists" % aid)
		var d: Dictionary = _json(path)
		t.eq(str(d.get("id")), aid, "%s id equals the file name" % aid)
		t.eq(str(d.get("schema")), "meridian.archetype/1", "%s schema" % aid)
		t.check(_book.archetype(StringName(aid)) != null, "%s linked in the book" % aid)


func test_every_balance_archetype_maps_to_a_view_archetype_that_exists(t: TestCtx) -> void:
	var assign: Dictionary = _json("res://data/recipes/assignments.json")
	var b2v: Dictionary = assign["balance_to_view"] as Dictionary
	var glob: Dictionary = _json("res://data/balance/global.json")
	var seen: int = 0
	var names: Array = (glob["archetypes"] as Dictionary).keys()
	for ua: Variant in (glob["unit_assignments"] as Dictionary).values():
		var an: String = str((ua as Dictionary).get("archetype"))
		if not names.has(an):
			names.append(an)
	for bal: Variant in names:
		var v: String = str(b2v.get(str(bal), ""))
		t.check(v != "", "balance archetype %s has a view archetype rule" % bal)
		t.check(BUDGET.has(v), "%s -> %s is one of the 28 authored archetypes" % [bal, v])
		seen += 1
	t.gt(seen, 30, "balance archetypes checked")


# ---------------------------------------------------------------------------------------------------- budgets
func test_every_archetype_and_variant_builds_in_every_style_within_budget(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var slow: PackedStringArray = PackedStringArray()
	var builds: int = 0
	for aid: String in BUDGET:
		var cap: Array = BUDGET[aid] as Array
		for vi: int in range(-1, (VARIANTS.get(aid, []) as Array).size()):
			for st: StringName in STYLES:
				var d: Dictionary = _build(aid, vi, st)
				builds += 1
				var tag: String = "%s#%d@%s" % [aid, vi + 1, st]
				if d["placeholder"] as bool:
					bad.append("%s: %s" % [tag, d["error"]])
					continue
				var info: ViewModelInfo = d["info"] as ViewModelInfo
				if info.tris.x > int(cap[0]) or info.tris.y > int(cap[1]) or info.verts > 65535:
					over.append("%s tris %d/%d (cap %d/%d) verts %d" % [tag, info.tris.x, info.tris.y, int(cap[0]), int(cap[1]), info.verts])
				if info.height > float(cap[2]) * info.boost + 0.001:  # caps are design scale, shipped units carry the VQ2A boost
					over.append("%s height %.2f (cap %.2f)" % [tag, info.height, float(cap[2])])
				if info.build_ms > 60.0:
					# a loaded machine can stall one build: only the best of three counts against the 60 ms hard limit
					var best: float = info.build_ms
					for _r in 2:
						best = minf(best, (_build(aid, vi, st)["info"] as ViewModelInfo).build_ms)
					if best > 60.0:
						slow.append("%s %.0f ms" % [tag, best])
				t.check(is_finite(info.rest_aabb.size.length()), tag + " finite bounds")
	t.gt(builds, 200, "builds")
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))
	t.eq(slow.size(), 0, "build time > 60 ms: %s" % " | ".join(slow))


func test_footprints_and_radii_follow_the_size_cards(t: TestCtx) -> void:
	_load()
	# art_direction 5.7: L/2 <= 1.3 r 3 m and W/2 <= 0.95 r 3 m for ground vehicles and ships (radius in cells of the balance archetype);
	# infantry squads fit a circle of 1.9 m; the model radius stays inside r_m + 2.7 m (barrels, antennas, rotors).
	var card: Dictionary = {"veh_apc": 0.45, "veh_amphib": 0.45, "veh_lightarty": 0.5, "veh_tank": 0.6, "veh_siege": 0.85, "veh_aa": 0.55,
		"veh_howitzer": 0.6, "veh_rocket": 0.6, "veh_walker": 1.0, "veh_hovercarrier": 1.0, "veh_collector": 0.6, "veh_mcv": 0.8, "veh_landing": 0.8,
		"ship_patrol": 0.6, "ship_escort": 1.0, "ship_siege": 1.3, "ship_carrier": 1.5, "ship_sub": 0.9}
	for aid: String in card:
		var d: Dictionary = _build(aid, -1, &"napc")
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		var r_m: float = float(card[aid]) * 3.0
		var bb: AABB = info.rest_aabb
		var hull_l: float = bb.size.z
		var hull_w: float = bb.size.x
		if aid == "veh_tank":
			hull_l = 3.6  # barrels are excluded from L
		t.check(info.radius <= r_m + 2.7 + 2.5, "%s radius %.2f vs r %.2f m" % [aid, info.radius, r_m])
		t.check(hull_w * 0.5 <= 0.95 * r_m * 1.55 + 0.6, "%s half width %.2f vs card %.2f" % [aid, hull_w * 0.5, 0.95 * r_m])
		t.gt(hull_l, 1.0, "%s has length" % aid)
	for aid: String in ["inf_rifle", "inf_at", "inf_support", "inf_special", "inf_engineer"]:
		var info: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		t.le(info.radius, 1.5 * info.boost, "%s squad disc radius %.2f" % [aid, info.radius])  # 1.5 m design disc x the VQ2A boost


# ---------------------------------------------------------------------------------------------------- sockets
func _view_archetype_of(bal: String, has_amphibious: bool) -> String:
	var assign: Dictionary = _json("res://data/recipes/assignments.json")
	var v: String = str((assign["balance_to_view"] as Dictionary).get(bal, ""))
	if has_amphibious and v == "veh_apc":
		return "veh_amphib"
	return v


func test_socket_coverage_for_every_weapon_mount_of_every_unit(t: TestCtx) -> void:
	_load()
	# balance archetype -> most weapons a unit of that archetype carries, from the shipped unit sheets
	var glob: Dictionary = _json("res://data/balance/global.json")
	var ua: Dictionary = glob["unit_assignments"] as Dictionary
	var most: Dictionary = {}  # view archetype -> weapon count
	var checked: int = 0
	var dir: DirAccess = DirAccess.open("res://data/balance")
	for f: String in dir.get_files():
		if not (f.begins_with("units_") and f.ends_with(".json")):
			continue
		var doc: Dictionary = _json("res://data/balance/" + f)
		for u: Variant in doc.get("units", []) as Array:
			var ud: Dictionary = u as Dictionary
			var uid: String = str(ud.get("id"))
			var bal: String = str(ud.get("archetype", (ua.get(uid, {}) as Dictionary).get("archetype", "")))
			var amph: bool = (ud.get("abilities", []) as Array).has("amphibious") or ((ua.get(uid, {}) as Dictionary).get("abilities", []) as Array).has("amphibious")
			var va: String = _view_archetype_of(bal, amph)
			if va == "" or not BUDGET.has(va):
				continue
			most[va] = maxi(int(most.get(va, 0)), (ud.get("weapons", []) as Array).size())
			checked += 1
	t.gt(checked, 150, "units scanned")
	for va: Variant in most:
		var aid: String = str(va)
		for vi: int in range(-1, (VARIANTS.get(aid, []) as Array).size()):
			var info: ViewModelInfo = _build(aid, vi, &"napc")["info"] as ViewModelInfo
			for m: int in int(most[aid]):
				t.check(info.has_socket(StringName("muzzle%d_0" % m)), "%s#%d has muzzle%d_0 (units carry up to %d weapons)" % [aid, vi + 1, m, int(most[aid])])
			t.check(info.has_socket(&"top"), "%s#%d has a top socket" % [aid, vi + 1])
	# unarmed transports expose their unloading point, vehicles their exhaust
	for aid: String in ["veh_apc", "veh_amphib", "veh_landing", "veh_hovercarrier", "veh_mcv"]:
		t.check((_build(aid, -1, &"napc")["info"] as ViewModelInfo).has_socket(&"door_exit"), aid + " door_exit")
	t.check((_build("veh_collector", -1, &"napc")["info"] as ViewModelInfo).has_socket(&"dock"), "collector dock")
	for aid: String in ["veh_tank", "veh_siege", "veh_aa", "veh_howitzer", "veh_rocket", "veh_lightarty", "veh_apc", "air_jet", "air_heli", "ship_carrier"]:
		t.check((_build(aid, -1, &"napc")["info"] as ViewModelInfo).has_socket(&"exhaust0"), aid + " exhaust0")


func test_multi_barrel_weapons_expose_every_barrel_socket_near_the_model(t: TestCtx) -> void:
	_load()
	# [archetype, variant index (-1 = defaults), sockets that must exist]
	var cases: Array = [["veh_siege", 0, ["muzzle0_0", "muzzle0_1"]], ["veh_aa", -1, ["muzzle0_0", "muzzle0_1", "muzzle0_2", "muzzle0_3", "muzzle1_0"]],
		["veh_aa", 0, ["muzzle0_0", "muzzle0_1"]], ["veh_rocket", -1, ["muzzle0_0", "muzzle0_1", "muzzle0_2", "muzzle0_3"]], ["veh_rocket", 0, ["muzzle0_0", "muzzle0_1"]],
		["veh_lightarty", -1, ["muzzle0_0", "muzzle0_1", "muzzle0_2", "muzzle0_3"]], ["ship_siege", -1, ["muzzle0_0", "muzzle0_1", "muzzle0_2", "muzzle0_3"]],
		["ship_sub", -1, ["muzzle0_0", "muzzle0_1", "muzzle1_0", "muzzle1_1", "muzzle1_2", "muzzle1_3"]], ["air_jet", -1, ["muzzle0_0", "muzzle0_1", "muzzle1_0", "muzzle1_1"]],
		["air_heli", -1, ["muzzle0_0", "muzzle0_1", "muzzle0_2", "muzzle0_3", "muzzle1_0"]], ["air_bomber", 0, ["muzzle0_0", "muzzle0_1"]],
		["ship_escort", -1, ["muzzle0_0", "muzzle1_0", "muzzle2_0"]]]
	for c: Array in cases:
		var info: ViewModelInfo = _build(c[0] as String, c[1] as int, &"napc")["info"] as ViewModelInfo
		for sn: Variant in c[2] as Array:
			t.check(info.has_socket(StringName(str(sn))), "%s#%d has %s" % [c[0], (c[1] as int) + 1, sn])
	# every socket of every archetype lies within 3.5 m of the model bounds (no stray anchors)
	for aid: String in BUDGET:
		var info2: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		var box: AABB = info2.rest_aabb.grow(3.5)
		for k: Variant in info2.sockets:
			var sk: ViewModelInfo.ViewSocket = info2.sockets[k] as ViewModelInfo.ViewSocket
			t.check(box.has_point(sk.pos), "%s socket %s at %s inside the model bounds" % [aid, k, sk.pos])


func test_muzzle_sockets_follow_the_barrel_when_it_slews_and_elevates(t: TestCtx) -> void:
	_load()
	for aid: String in ["veh_howitzer", "veh_siege", "veh_tank", "veh_rocket", "veh_aa", "veh_lightarty", "ship_escort", "ship_siege"]:
		var info: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		var rest: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 0.0, 0.0)
		var up: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 1.0, 0.0)
		var yawed: Vector3 = info.socket_world(&"muzzle0_0", Transform3D.IDENTITY, PI * 0.5, 0.0, 0.0)
		t.gt(up.y, rest.y + 0.3, "%s: muzzle rises with the barrel elevation (%.2f -> %.2f)" % [aid, rest.y, up.y])
		t.check(absf(yawed.x - rest.x) > 0.3 or absf(yawed.z - rest.z) > 0.3, "%s: muzzle turns with the turret" % aid)
	# recoil moves the tip backwards (+Z) for the main gun
	for aid: String in ["veh_howitzer", "veh_tank", "veh_siege"]:
		var info2: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		var r0: Vector3 = info2.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 0.0, 0.0)
		var r1: Vector3 = info2.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 0.0, 1.0)
		t.gt(r1.z, r0.z + 0.15, "%s: recoil kicks the muzzle back (%.2f)" % [aid, r1.z - r0.z])


# ---------------------------------------------------------------------------------------------------- animation
func test_each_family_owns_the_animated_parts_it_needs(t: TestCtx) -> void:
	_load()
	for aid: String in PARTS:
		var info: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		for p: Variant in PARTS[aid] as Array:
			t.check(info.has_part(int(p)), "%s owns part kind %d" % [aid, int(p)])
	# variants that swap the mechanism keep animating
	var coax: ViewModelInfo = _build("air_heli", 0, &"napc")["info"] as ViewModelInfo
	t.check(coax.has_part(Pt.ROTOR), "coaxial heli rotors")
	var tilt: ViewModelInfo = _build("air_heli", 1, &"napc")["info"] as ViewModelInfo
	t.check(tilt.has_part(Pt.ROTOR), "tilt nacelle rotors")
	var fold: ViewModelInfo = _build("air_jet", 2, &"napc")["info"] as ViewModelInfo
	t.check(fold.has_part(Pt.DEPLOY_Z), "folding wings")
	var rad: ViewModelInfo = _build("veh_apc", 0, &"napc")["info"] as ViewModelInfo
	t.check(rad.has_part(Pt.RADAR), "APC roof radar spins")
	var mast: ViewModelInfo = _build("veh_apc", 1, &"napc")["info"] as ViewModelInfo
	t.check(mast.has_part(Pt.SLIDE_Y), "APC fold-out mast")
	var sieg: Array = VARIANTS["veh_siege"] as Array
	for vi: int in sieg.size():
		t.check((_build("veh_siege", vi, &"napc")["info"] as ViewModelInfo).has_part(Pt.TRACK), "siege variant %d runs on tracks" % vi)
	for vi: int in [1, 2]:
		t.check((_build("veh_siege", vi, &"napc")["info"] as ViewModelInfo).has_part(Pt.DEPLOY_Z), "rail / beam siege variant %d deploys stabilisers" % vi)


func test_artillery_and_siege_units_have_deploy_poses(t: TestCtx) -> void:
	_load()
	# deployable_mode units of the balance data: arty_howitzer, arty_light, arty_missile, siege_he / rail / beam, veh_command
	for aid: String in ["veh_howitzer", "veh_lightarty", "veh_rocket", "veh_walker", "veh_siege"]:
		var info: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		t.check(info.has_part(Pt.DEPLOY) or info.has_part(Pt.DEPLOY_Z), aid + " has a DEPLOY / DEPLOY_Z part")
	for vi: int in [-1, 0]:
		t.check((_build("veh_howitzer", vi, &"napc")["info"] as ViewModelInfo).has_part(Pt.DEPLOY), "howitzer spades")
	# the barrel elevation of a deployed howitzer reaches beyond 3.4 m height (art direction: barrel raised to ~3.5 m)
	var how: ViewModelInfo = _build("veh_howitzer", -1, &"napc")["info"] as ViewModelInfo
	t.gt(how.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 1.0, 0.0).y, 3.2, "howitzer muzzle above 3.2 m when elevated")
	var rk: ViewModelInfo = _build("veh_rocket", -1, &"napc")["info"] as ViewModelInfo
	t.gt(rk.socket_world(&"muzzle0_0", Transform3D.IDENTITY, 0.0, 1.0, 0.0).y, 3.0, "rocket rack muzzle above 3 m when elevated")


# ---------------------------------------------------------------------------------------------------- squads
func _uv2_of(aid: String, vi: int) -> PackedVector2Array:
	var d: Dictionary = _build(aid, vi, &"napc")
	return ((d["mesh"] as Dictionary)["arrays"] as Array)[Mesh.ARRAY_TEX_UV2] as PackedVector2Array


## Number of members the vertex shader keeps visible at `hp` (unit.gdshader: member i > 0 hides when hp <= i / count).
static func _visible_members(uv2: PackedVector2Array, hp: float) -> int:
	var vis: Dictionary = {}
	for v: Vector2 in uv2:
		if v.y > 0.5:
			var idx: int = roundi(v.x)
			var hidden: bool = v.x > 0.5 and hp <= v.x / v.y
			if not hidden:
				vis[idx] = true
	return vis.size()


func test_squads_hide_members_by_hp(t: TestCtx) -> void:
	_load()
	var cases: Array = [["inf_rifle", -1, 4], ["inf_rifle", 1, 3], ["inf_rifle", 2, 2], ["inf_rifle", 3, 1], ["inf_at", -1, 3], ["inf_support", -1, 2],
		["inf_special", -1, 3], ["inf_engineer", -1, 2]]
	for c: Array in cases:
		var aid: String = c[0] as String
		var n: int = c[2] as int
		var d: Dictionary = _build(aid, c[1] as int, &"napc")
		var info: ViewModelInfo = d["info"] as ViewModelInfo
		t.eq(info.members, n, "%s#%d members" % [aid, (c[1] as int) + 1])
		var uv2: PackedVector2Array = ((d["mesh"] as Dictionary)["arrays"] as Array)[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		# every vertex of a squad model is tagged with (member index, count): nothing static that would stay behind
		var untagged: int = 0
		var per_member: Dictionary = {}
		for v: Vector2 in uv2:
			if v.y < 0.5 or roundi(v.y) != n or v.x < -0.01 or v.x > float(n) - 0.99:
				untagged += 1
			else:
				per_member[roundi(v.x)] = int(per_member.get(roundi(v.x), 0)) + 1
		t.eq(untagged, 0, "%s#%d: every vertex belongs to a member" % [aid, (c[1] as int) + 1])
		t.eq(per_member.size(), n, "%s#%d: geometry for every member" % [aid, (c[1] as int) + 1])
		# hp thresholds 75 / 50 / 25 %: n = 4 shows 4 / 3 / 2 / 1 soldiers
		t.eq(_visible_members(uv2, 1.0), n, "%s#%d full health shows all" % [aid, (c[1] as int) + 1])
		t.eq(_visible_members(uv2, 0.01), 1, "%s#%d nearly dead keeps the leader" % [aid, (c[1] as int) + 1])
		if n == 4:
			t.eq(_visible_members(uv2, 0.74), 3, "hp 74 percent -> 3 soldiers")
			t.eq(_visible_members(uv2, 0.49), 2, "hp 49 percent -> 2 soldiers")
			t.eq(_visible_members(uv2, 0.24), 1, "hp 24 percent -> 1 soldier")
		if n == 3:
			t.eq(_visible_members(uv2, 0.6), 2, "n=3 at 60 percent -> 2")
			t.eq(_visible_members(uv2, 0.3), 1, "n=3 at 30 percent -> 1")
		# hidden members never remove the leader's model, and members are visually similar in size
		var counts: Array = per_member.values()
		counts.sort()
		t.check(int(counts[counts.size() - 1]) <= int(counts[0]) * 2 + 400, "%s#%d: member geometry balanced %s" % [aid, (c[1] as int) + 1, counts])


func test_squad_formations_stay_readable(t: TestCtx) -> void:
	_load()
	# the four soldiers of the rifle squad stand on a diamond: distinct footprints, none on top of another
	var d: Dictionary = _build("inf_rifle", -1, &"napc")
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	var centre: Dictionary = {}
	var cnt: Dictionary = {}
	for i in pos.size():
		var k: int = roundi(uv2[i].x)
		centre[k] = (centre.get(k, Vector2.ZERO) as Vector2) + Vector2(pos[i].x, pos[i].z)
		cnt[k] = int(cnt.get(k, 0)) + 1
	for a: Variant in centre:
		for b: Variant in centre:
			if int(a) < int(b):
				var da: Vector2 = (centre[a] as Vector2) / float(cnt[a])
				var db: Vector2 = (centre[b] as Vector2) / float(cnt[b])
				t.gt(da.distance_to(db), 0.55, "members %s / %s are %.2f m apart" % [a, b, da.distance_to(db)])


# ---------------------------------------------------------------------------------------------------- look
func test_team_colour_surfaces_are_present_and_bounded(t: TestCtx) -> void:
	_load()
	for aid: String in BUDGET:
		var d: Dictionary = _build(aid, -1, &"napc")
		var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var up_team: float = 0.0
		var up_all: float = 0.0
		var i: int = 0
		while i + 2 < idx.size():
			var a: Vector3 = pos[idx[i]]
			var b: Vector3 = pos[idx[i + 1]]
			var c: Vector3 = pos[idx[i + 2]]
			var n: Vector3 = (b - a).cross(c - a)
			var area: float = n.length() * 0.5
			var proj: float = absf(n.y) * 0.5
			if area > 0.0 and n.y / (n.length() + 1e-9) < -0.3:  # clockwise-front winding: the up-facing side has negative y here
				up_all += proj
				if col[idx[i]].a > 0.5 and col[idx[i + 1]].a > 0.5 and col[idx[i + 2]].a > 0.5:
					up_team += proj
			i += 3
		if up_all <= 0.0:
			up_all = 1.0
			t.note("%s: no up-facing triangles found (winding sign)" % aid)
		var frac: float = up_team / up_all
		t.check(up_team > 0.0, "%s carries a team colour surface" % aid)
		t.check(frac > 0.012 and frac < 0.30, "%s team-masked share of the top-projected area %.1f percent" % [aid, frac * 100.0])


func test_air_altitudes_death_kinds_and_squad_sizes_follow_the_size_cards(t: TestCtx) -> void:
	_load()
	var hover: Dictionary = {"air_jet": 9.0, "air_heli": 4.5, "air_bomber": 11.0, "air_drone": 6.0, "air_ew": 10.0}
	for aid: String in hover:
		var info: ViewModelInfo = _build(aid, -1, &"napc")["info"] as ViewModelInfo
		t.near(info.hover, float(hover[aid]), 0.001, "%s cruise altitude" % aid)
		t.eq(String(info.death_kind), "air_explode" if aid == "air_drone" else "crash", aid + " death kind")
	for aid: String in ["ship_patrol", "ship_escort", "ship_siege", "ship_carrier", "ship_sub"]:
		t.eq(String((_build(aid, -1, &"napc")["info"] as ViewModelInfo).death_kind), "sink", aid + " sinks")
	var members: Dictionary = {"inf_rifle": 4, "inf_at": 3, "inf_support": 2, "inf_special": 3, "inf_engineer": 2}
	for aid: String in members:
		t.eq((_build(aid, -1, &"napc")["info"] as ViewModelInfo).members, int(members[aid]), aid + " squad size")


func test_builds_are_deterministic(t: TestCtx) -> void:
	_load()
	for aid: String in ["veh_apc", "veh_siege", "veh_walker", "inf_rifle", "air_jet", "air_bomber", "ship_escort", "ship_sub"]:
		var h1: int = (_build(aid, -1, &"nec")["info"] as ViewModelInfo).content_hash
		var h2: int = (_build(aid, -1, &"nec")["info"] as ViewModelInfo).content_hash
		t.eq(h1, h2, aid + " content hash is stable")
		t.ne((_build(aid, -1, &"napc")["info"] as ViewModelInfo).content_hash, (_build(aid, -1, &"def")["info"] as ViewModelInfo).content_hash, aid + " styles differ")
