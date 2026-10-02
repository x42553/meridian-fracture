extends RefCounted
## VIEW-M7 acceptance: the structure / neutral / summon / projectile archetypes (`str_*`, `neu_building`, `sum_*`, `proj_*`, 28 files).
## Footprint discipline (each structure archetype builds at three footprints and never leaves its plinth), height caps, triangle
## budgets, team-colour surface, sockets and animated parts, destroyed-state meta, projectile / summon conventions, and that the
## shipped recipes of the balance data use these archetypes (no `gen_*` stubs left for them).

const Pt := ViewMeshBuilder.Part
const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]

## archetype -> footprints (cells) it must fit: minimum, nominal (the shipped def) and maximum.
const STRUCT_FP: Dictionary = {
	"str_headquarters": [[2, 2], [3, 3], [4, 4]], "str_generator": [[1, 1], [2, 2], [3, 3]], "str_refinery": [[2, 2], [3, 3], [4, 3]],
	"str_barracks": [[2, 2], [3, 2], [3, 3]], "str_factory": [[2, 2], [3, 3], [4, 4]], "str_dock": [[2, 2], [3, 3], [4, 3]],
	"str_radar": [[2, 2], [3, 2], [3, 3]], "str_airfield": [[4, 3], [6, 3], [6, 4]], "str_laboratory": [[2, 2], [3, 3], [4, 4]],
	"str_watchtower": [[1, 1], [2, 2], [3, 3]], "str_at_turret": [[1, 1], [2, 2], [3, 3]], "str_aa_battery": [[1, 1], [2, 2], [3, 3]],
	"str_relay": [[1, 1], [2, 2], [3, 3]], "str_defense_adv": [[2, 2], [3, 3], [4, 4]], "str_superweapon": [[4, 4], [5, 5], [6, 6]],
}
## neutral kit -> footprints
const NEUTRAL_FP: Dictionary = {
	"garrison": [[2, 2], [3, 3], [4, 3]], "substation": [[2, 2], [3, 2], [3, 3]], "outpost": [[1, 1], [2, 2], [3, 3]],
	"depot": [[2, 2], [3, 3], [4, 3]], "hospital": [[2, 2], [2, 3], [3, 3]], "harbor": [[2, 2], [3, 3], [4, 3]],
	"deposit": [[2, 2], [3, 3], [4, 4]],
}
## nominal footprint (the shipped def) per archetype
const NOMINAL: Dictionary = {
	"str_headquarters": [3, 3], "str_generator": [2, 2], "str_refinery": [3, 3], "str_barracks": [2, 2], "str_factory": [3, 3], "str_dock": [3, 3],
	"str_radar": [2, 2], "str_airfield": [6, 3], "str_laboratory": [3, 3], "str_watchtower": [1, 1], "str_at_turret": [1, 1], "str_aa_battery": [2, 2],
	"str_relay": [1, 1], "str_defense_adv": [2, 2], "str_superweapon": [4, 4],
}
const DEFENSE_KITS: PackedStringArray = ["bulwark_cannon", "lance_rail", "sunwall", "citadel_mortar", "sea_spear", "dragon_tooth", "forge_cannon", "bastion_tower"]
const SUPERWEAPON_KITS: PackedStringArray = ["halo_tower", "billboard", "sunflower", "gantry_silo", "hive_tower", "assembly_hall", "long_barrel", "three_masts"]
## archetype -> animated parts it must contain
const PARTS: Dictionary = {
	"str_headquarters": [Pt.RADAR, Pt.BLINK], "str_generator": [Pt.RADAR, Pt.BLINK], "str_refinery": [Pt.SLIDE_Z, Pt.BLINK],
	"str_barracks": [Pt.DOOR, Pt.BLINK], "str_factory": [Pt.DOOR, Pt.RADAR, Pt.BLINK, Pt.SLIDE_Y], "str_dock": [Pt.DOOR, Pt.BLINK, Pt.SLIDE_Y],
	"str_radar": [Pt.RADAR, Pt.BLINK], "str_airfield": [Pt.DOOR, Pt.RADAR, Pt.BLINK], "str_laboratory": [Pt.RADAR, Pt.BLINK],
	"str_watchtower": [Pt.RADAR, Pt.BLINK], "str_at_turret": [Pt.TURRET, Pt.BARREL], "str_aa_battery": [Pt.TURRET, Pt.RADAR],
	"str_relay": [Pt.RADAR, Pt.BLINK], "str_defense_adv": [Pt.TURRET], "str_superweapon": [Pt.BLINK],
}
const SUMMONS: PackedStringArray = ["sum_uav", "sum_balloon", "sum_cargo", "sum_drone_swarm", "sum_capsule", "sum_engine", "sum_station", "sum_cover"]
const PROJECTILES: PackedStringArray = ["proj_missile", "proj_rocket", "proj_bomb", "proj_torpedo"]

var _book: ViewRecipeBook = null
var _cache: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false
	ViewExpr.quiet = false


static func footprint_entry(arch: String, fw: int, fh: int) -> Dictionary:
	var dz: float = (float(fh) * 0.5 + 0.5) * 3.0
	if arch == "str_refinery":
		dz = (float(fh) * 0.5 - 0.5) * 3.0  # the refinery dock cell is inside the footprint (shipped data)
	var dx: float = (0.5 - float(fw) * 0.5) * 3.0
	return {"fw": fw, "fh": fh, "door_cx": dx, "door_cz": dz, "exit_dir": 1024, "dock_cx": dx, "dock_cz": dz, "dock_dir": 1024,
		"pads_n": 4 if arch == "str_airfield" else 0}


func _rid(arch: String, kit: String, fw: int, fh: int) -> StringName:
	return StringName("rcx.%s.%s.%dx%d" % [arch, kit, fw, fh])


## Book with the shipped data plus synthetic recipes (archetype, kit, footprint) so every footprint can be exercised.
func _ensure() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()
	var fps: Dictionary = {}
	for arch: String in STRUCT_FP:
		var kits: PackedStringArray = [""]
		if arch == "str_defense_adv":
			kits = DEFENSE_KITS
		elif arch == "str_superweapon":
			kits = SUPERWEAPON_KITS
		elif arch == "str_aa_battery":
			kits = ["missile", "flak"]
		for kit: String in kits:
			for f: Variant in STRUCT_FP[arch] as Array:
				var fw: int = (f as Array)[0] as int
				var fh: int = (f as Array)[1] as int
				var rid: StringName = _rid(arch, kit, fw, fh)
				var rec: Dictionary = {"schema": "meridian.recipe/1", "id": String(rid), "archetype": arch, "style": "auto"}
				if kit != "":
					rec["params"] = {"weapon": kit} if arch == "str_aa_battery" else {"kit": kit}
				_book.add_recipe(rec, "test")
				fps[String(rid)] = footprint_entry(arch, fw, fh)
	for kit: String in NEUTRAL_FP:
		for f: Variant in NEUTRAL_FP[kit] as Array:
			var fw2: int = (f as Array)[0] as int
			var fh2: int = (f as Array)[1] as int
			var rid2: StringName = _rid("neu_building", kit, fw2, fh2)
			_book.add_recipe({"schema": "meridian.recipe/1", "id": String(rid2), "archetype": "neu_building", "style": "auto", "params": {"kit": kit, "heaps": 3}}, "test")
			fps[String(rid2)] = footprint_entry("neu_building", fw2, fh2)
	for a: String in SUMMONS + PROJECTILES:
		_book.add_recipe({"schema": "meridian.recipe/1", "id": "rcx." + a, "archetype": a, "style": "auto"}, "test")
	_book.add_footprints({"schema": "meridian.footprints/1", "structures": fps}, "test")
	_book.link()


func _build(rid: StringName, style: StringName = &"napc") -> Dictionary:
	_ensure()
	var key: String = "%s@%s" % [rid, style]
	if not _cache.has(key):
		_cache[key] = ViewModelBuilder.build_data(_book, rid, style, 10000)
	return _cache[key] as Dictionary


func _info(d: Dictionary) -> ViewModelInfo:
	return d["info"] as ViewModelInfo


static func height_cap(fw: int, fh: int) -> float:
	var m: int = maxi(fw, fh)
	return 14.0 if m >= 4 else (12.0 if m >= 3 else 8.0)


static func tri_cap(arch: String, fw: int, fh: int) -> int:
	if arch == "str_superweapon":
		return 10000
	var nom: Array = NOMINAL.get(arch, [fw, fh]) as Array
	return 3000 if (nom[0] as int) * (nom[1] as int) <= 4 else 8000


## Area of upward-facing triangles that carry the team mask (vertex alpha > 0.5), LOD0, in m2.
static func team_roof_area(d: Dictionary) -> float:
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var area: float = 0.0
	var i: int = 0
	while i + 2 < idx.size():
		var a: int = idx[i]
		var b: int = idx[i + 1]
		var c: int = idx[i + 2]
		i += 3
		if col[a].a > 0.5 and col[b].a > 0.5 and col[c].a > 0.5 and nrm[a].y > 0.7:
			area += 0.5 * (pos[b] - pos[a]).cross(pos[c] - pos[a]).length()
	return area


## Horizontal extent swept by yawing parts (rotors, radar arrays, turrets, barrels): for every such vertex the circle around the
## part's pivot. Returns Rect2(min xz, size).
static func sweep_rect(d: Dictionary) -> Rect2:
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var c0: Variant = arrays[Mesh.ARRAY_CUSTOM0]
	var c1: Variant = arrays[Mesh.ARRAY_CUSTOM1]
	var lo: Vector2 = Vector2(1.0e9, 1.0e9)
	var hi: Vector2 = Vector2(-1.0e9, -1.0e9)
	var any: bool = false
	for i: int in pos.size():
		var kind: int
		if c0 is PackedByteArray:
			kind = (c0 as PackedByteArray)[i * 4 + 1]
		else:
			kind = roundi((c0 as PackedFloat32Array)[i * 4 + 1] * 255.0)
		if not (kind == 1 or kind == 2 or kind == 5 or kind == 7 or (kind >= 19 and kind <= 24)):
			continue
		var pv: Vector3
		if c1 is PackedByteArray:
			var by: PackedByteArray = c1 as PackedByteArray
			pv = Vector3(by.decode_half(i * 8), by.decode_half(i * 8 + 2), by.decode_half(i * 8 + 4))
		else:
			var fa: PackedFloat32Array = c1 as PackedFloat32Array
			pv = Vector3(fa[i * 4], fa[i * 4 + 1], fa[i * 4 + 2])
		var r: float = Vector2(pos[i].x - pv.x, pos[i].z - pv.z).length()
		lo = lo.min(Vector2(pv.x - r, pv.z - r))
		hi = hi.max(Vector2(pv.x + r, pv.z + r))
		any = true
	return Rect2(lo, hi - lo) if any else Rect2()


## Extra horizontal allowance (m) beyond the plinth for muzzle overhang, per archetype.
static func overhang(arch: String) -> float:
	return 0.45 if arch in ["str_at_turret", "str_aa_battery", "str_defense_adv", "str_watchtower", "str_superweapon"] else 0.12


# ------------------------------------------------------------------------------------------------------------- inventory
func test_the_28_archetype_files_exist_and_load(t: TestCtx) -> void:
	_ensure()
	t.eq(_book.errors().size(), 0, "book loads clean: %s" % ", ".join(_book.errors()))
	var want: PackedStringArray = PackedStringArray()
	for a: String in STRUCT_FP:
		want.append(a)
	want.append("neu_building")
	want.append_array(SUMMONS)
	want.append_array(PROJECTILES)
	t.eq(want.size(), 28, "15 structures + 1 neutral + 8 summons + 4 projectiles")
	for a: String in want:
		t.check(_book.archetype(StringName(a)) != null, "archetype file %s.json loads" % a)


func test_every_archetype_builds_without_error_in_every_style(t: TestCtx) -> void:
	_ensure()
	var bad: PackedStringArray = PackedStringArray()
	var styles: Array[StringName] = [&"napc", &"nec", &"def", &"han", &"neutral"]
	var n: int = 0
	for a: String in STRUCT_FP:
		var f: Array = (STRUCT_FP[a] as Array)[1] as Array
		var kit: String = ""
		if a == "str_defense_adv":
			kit = "bulwark_cannon"
		elif a == "str_superweapon":
			kit = "halo_tower"
		elif a == "str_aa_battery":
			kit = "missile"
		for sid: StringName in styles:
			var d: Dictionary = _build(_rid(a, kit, f[0] as int, f[1] as int), sid)
			n += 1
			if d["placeholder"] as bool:
				bad.append("%s@%s: %s" % [a, sid, d["error"]])
	for a: String in SUMMONS + PROJECTILES:
		for sid: StringName in styles:
			var d2: Dictionary = _build(StringName("rcx." + a), sid)
			n += 1
			if d2["placeholder"] as bool:
				bad.append("%s@%s: %s" % [a, sid, d2["error"]])
	t.gt(n, 90, "builds")
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))


# ------------------------------------------------------------------------------------------------------- footprint discipline
func _check_fit(t: TestCtx, label: String, d: Dictionary, arch: String, fw: int, fh: int) -> void:
	var info: ViewModelInfo = _info(d)
	var hx: float = float(fw) * 1.5 - 0.25
	var hz: float = float(fh) * 1.5 - 0.25
	var bb: AABB = info.rest_aabb
	var m: float = overhang(arch)
	t.check(bb.position.x >= -hx - m and bb.end.x <= hx + m, "%s x %.2f..%.2f inside +-%.2f" % [label, bb.position.x, bb.end.x, hx])
	t.check(bb.position.z >= -hz - m and bb.end.z <= hz + m, "%s z %.2f..%.2f inside +-%.2f" % [label, bb.position.z, bb.end.z, hz])
	# the yawing parts (rotors, arrays, turrets) sweep circles around their pivots: those stay over the plinth too
	if arch != "str_defense_adv" and arch != "str_superweapon":
		var sw: Rect2 = sweep_rect(d)
		if sw.size != Vector2.ZERO:
			t.check(sw.position.x >= -hx - m and sw.end.x <= hx + m and sw.position.y >= -hz - m and sw.end.y <= hz + m,
				"%s rotating parts sweep x %.2f..%.2f z %.2f..%.2f inside the plinth" % [label, sw.position.x, sw.end.x, sw.position.y, sw.end.y])
	t.le(info.height, height_cap(fw, fh) + 0.01, "%s height %.2f <= %.0f" % [label, info.height, height_cap(fw, fh)])
	t.le(info.tris.x, tri_cap(arch, fw, fh), "%s LOD0 tris %d" % [label, info.tris.x])
	t.le(info.tris.y, int(float(tri_cap(arch, fw, fh)) * 0.65), "%s LOD1 tris %d" % [label, info.tris.y])
	t.le(info.verts, 16000, "%s vertices %d (VRAM <= 900 KB)" % [label, info.verts])
	t.check(info.build_ms < 60.0, "%s builds in %.1f ms" % [label, info.build_ms])
	t.check(bb.position.y <= -0.9, "%s has a skirt below the ground for the build-up rise (min y %.2f)" % [label, bb.position.y])
	t.eq(info.footprint, Vector2i(fw, fh), "%s meta footprint" % label)


func test_structures_fit_their_plinth_at_three_footprints(t: TestCtx) -> void:
	_ensure()
	var checked: int = 0
	for a: String in STRUCT_FP:
		var kit: String = ""
		if a == "str_defense_adv":
			kit = "bulwark_cannon"
		elif a == "str_superweapon":
			kit = "halo_tower"
		elif a == "str_aa_battery":
			kit = "missile"
		for f: Variant in STRUCT_FP[a] as Array:
			var fw: int = (f as Array)[0] as int
			var fh: int = (f as Array)[1] as int
			var d: Dictionary = _build(_rid(a, kit, fw, fh))
			_check_fit(t, "%s %dx%d" % [a, fw, fh], d, a, fw, fh)
			checked += 1
	t.eq(checked, 45, "15 archetypes x 3 footprints")


func test_every_defence_and_superweapon_kit_fits_and_is_armed(t: TestCtx) -> void:
	_ensure()
	for kit: String in DEFENSE_KITS:
		var d: Dictionary = _build(_rid("str_defense_adv", kit, 2, 2))
		_check_fit(t, "defence %s" % kit, d, "str_defense_adv", 2, 2)
		t.check(_info(d).has_socket(&"muzzle0_0"), "defence %s has muzzle0_0" % kit)
	for kit: String in SUPERWEAPON_KITS:
		var d2: Dictionary = _build(_rid("str_superweapon", kit, 4, 4))
		_check_fit(t, "superweapon %s" % kit, d2, "str_superweapon", 4, 4)
		if kit not in ["sunflower", "long_barrel"]:
			t.check(_info(d2).has_part(Pt.BLINK), "superweapon %s has its charge display (BLINK)" % kit)
	t.check(_info(_build(_rid("str_superweapon", "long_barrel", 4, 4))).has_socket(&"muzzle0_0"), "long_barrel has a muzzle socket")


func test_neutral_kits_fit_and_carry_the_pennant_or_none(t: TestCtx) -> void:
	_ensure()
	for kit: String in NEUTRAL_FP:
		for f: Variant in NEUTRAL_FP[kit] as Array:
			var fw: int = (f as Array)[0] as int
			var fh: int = (f as Array)[1] as int
			var d: Dictionary = _build(_rid("neu_building", kit, fw, fh), &"neutral")
			var info: ViewModelInfo = _info(d)
			var label: String = "neutral %s %dx%d" % [kit, fw, fh]
			var hx: float = float(fw) * 1.5 - 0.25
			var hz: float = float(fh) * 1.5 - 0.25
			var bb: AABB = info.rest_aabb
			t.check(bb.position.x >= -hx - 0.3 and bb.end.x <= hx + 0.3 and bb.position.z >= -hz - 0.3 and bb.end.z <= hz + 0.3, "%s inside the plinth %s" % [label, bb])
			t.le(info.height, height_cap(fw, fh) + 0.01, "%s height %.2f" % [label, info.height])
			t.le(info.tris.x, 8000, "%s tris %d" % [label, info.tris.x])
			t.check(info.build_ms < 60.0, "%s build %.1f ms" % [label, info.build_ms])
			if kit != "deposit":
				t.gt(_team_area_any(d), 20.0, "%s has a team-masked pennant so a captured building shows its owner" % label)


# ---------------------------------------------------------------------------------------------------------- team colour
func test_team_plate_area_on_the_roof(t: TestCtx) -> void:
	_ensure()
	for a: String in STRUCT_FP:
		var kit: String = ""
		if a == "str_defense_adv":
			kit = "bulwark_cannon"
		elif a == "str_superweapon":
			kit = "halo_tower"
		elif a == "str_aa_battery":
			kit = "missile"
		var f: Array = NOMINAL[a] as Array
		var fw: int = f[0] as int
		var fh: int = f[1] as int
		var area: float = team_roof_area(_build(_rid(a, kit, fw, fh)))
		var plinth: float = (float(fw) * 3.0 - 0.5) * (float(fh) * 3.0 - 0.5)
		t.ge(area, 0.9 if plinth >= 20.0 else 0.15, "%s team roof surface %.2f m2 (>= ~1 m2, small structures >= 0.15)" % [a, area])
		t.le(area / plinth, 0.14, "%s team area %.1f %% of the plinth (<= 12-14 %%)" % [a, area / plinth * 100.0])
		if a not in ["str_watchtower", "str_relay", "str_at_turret", "str_aa_battery", "str_defense_adv", "str_superweapon"]:
			t.ge(area / plinth, 0.025, "%s team plate %.1f %% of the footprint (>= 2.5 %%)" % [a, area / plinth * 100.0])


# ------------------------------------------------------------------------------------------------------------ animation
func test_activity_parts_per_structure(t: TestCtx) -> void:
	_ensure()
	for a: String in PARTS:
		var kit: String = ""
		if a == "str_defense_adv":
			kit = "bulwark_cannon"
		elif a == "str_superweapon":
			kit = "halo_tower"
		elif a == "str_aa_battery":
			kit = "missile"
		var f: Array = (STRUCT_FP[a] as Array)[1] as Array
		var info: ViewModelInfo = _info(_build(_rid(a, kit, f[0] as int, f[1] as int)))
		for p: int in PARTS[a] as Array:
			t.check(info.has_part(p), "%s has part kind %d" % [a, p])


func test_sockets_of_structures(t: TestCtx) -> void:
	_ensure()
	for a: String in STRUCT_FP:
		var kit: String = ""
		if a == "str_defense_adv":
			kit = "bulwark_cannon"
		elif a == "str_superweapon":
			kit = "halo_tower"
		elif a == "str_aa_battery":
			kit = "missile"
		for f: Variant in STRUCT_FP[a] as Array:
			var fw: int = (f as Array)[0] as int
			var fh: int = (f as Array)[1] as int
			var rid: StringName = _rid(a, kit, fw, fh)
			var info: ViewModelInfo = _info(_build(rid))
			var label: String = "%s %dx%d" % [a, fw, fh]
			t.check(info.has_socket(&"door_exit"), "%s has door_exit" % label)
			if info.has_socket(&"door_exit"):
				var sk: ViewModelInfo.ViewSocket = info.sockets[&"door_exit"] as ViewModelInfo.ViewSocket
				var fp: Dictionary = _book.footprint_vars(rid)
				t.check(Vector2(sk.pos.x - float(fp["door_cx"]), sk.pos.z - float(fp["door_cz"])).length() <= 0.75, "%s door_exit sits on the data anchor" % label)
			for w: String in ["weld0", "weld1", "weld2", "top"]:
				t.check(info.has_socket(StringName(w)), "%s has socket %s" % [label, w])
			if a == "str_refinery":
				t.check(info.has_socket(&"dock"), "%s has the dock socket" % label)
	for a2: String in ["str_watchtower", "str_at_turret", "str_aa_battery"]:
		var kit2: String = "missile" if a2 == "str_aa_battery" else ""
		t.check(_info(_build(_rid(a2, kit2, 2, 2))).has_socket(&"muzzle0_0"), "%s has muzzle0_0" % a2)
	t.check(_info(_build(_rid("str_aa_battery", "flak", 2, 2))).has_socket(&"muzzle0_0"), "flak battery has muzzle0_0")
	# generator and factory expose steam sockets for the smoke puffs
	t.check(_info(_build(_rid("str_generator", "", 2, 2))).has_socket(&"steam0"), "generator steam0")


func test_destroyed_state_meta_and_skirt(t: TestCtx) -> void:
	_ensure()
	for a: String in STRUCT_FP:
		var kit: String = "bulwark_cannon" if a == "str_defense_adv" else ("halo_tower" if a == "str_superweapon" else ("missile" if a == "str_aa_battery" else ""))
		var f: Array = (STRUCT_FP[a] as Array)[1] as Array
		var info: ViewModelInfo = _info(_build(_rid(a, kit, f[0] as int, f[1] as int)))
		t.eq(info.death_kind, &"structure", "%s dies as a structure (collapse FX + 7-tick shake)" % a)
		t.eq(info.death_ticks, 7, "%s dying window is 7 ticks" % a)
		t.eq(info.buildup_ticks, 30, "%s build-up is the default 30 ticks" % a)


func test_deterministic_builds(t: TestCtx) -> void:
	_ensure()
	for a: String in ["str_factory", "str_refinery", "neu_building"]:
		var rid: StringName = _rid(a, "garrison" if a == "neu_building" else "", 3, 3)
		var d1: Dictionary = ViewModelBuilder.build_data(_book, rid, &"napc", 10000)
		var d2: Dictionary = ViewModelBuilder.build_data(_book, rid, &"napc", 10000)
		t.eq(_info(d1).content_hash, _info(d2).content_hash, "%s content hash is stable" % a)
	var h1: int = _info(_build(_rid("str_factory", "", 3, 3), &"napc")).content_hash
	var h2: int = _info(_build(_rid("str_factory", "", 3, 3), &"han")).content_hash
	t.ne(h1, h2, "styles change the model (palette / seed)")


# ----------------------------------------------------------------------------------------------- shipped recipes / re-pointing
func test_shipped_recipes_use_the_new_archetypes(t: TestCtx) -> void:
	_ensure()
	var stale: PackedStringArray = PackedStringArray()
	var n: int = 0
	for rid: String in _book.ids():
		if rid.begins_with("rcx."):
			continue
		if rid.begins_with("structure.") or rid.begins_with("neutral.") or rid.begins_with("proj.") or (rid.begins_with("summon.") and not rid.contains("decoy")):
			var r: ViewRecipe = _book.recipe(StringName(rid))
			if r.arch != null and String(r.arch.id).begins_with("gen_") and not String(r.arch.id) == "gen_air":
				stale.append("%s -> %s" % [rid, r.arch.id])
			n += 1
	t.gt(n, 40, "recipes checked")
	t.eq(stale.size(), 0, "recipes still on a gen_* stub archetype: %s" % ", ".join(stale))


func test_shipped_structure_recipes_build_and_fit(t: TestCtx) -> void:
	_ensure()
	var n: int = 0
	for rid: String in _book.ids():
		if rid.begins_with("rcx.") or not _book.has_footprint(StringName(rid)):
			continue
		var fp: Dictionary = _book.footprint_vars(StringName(rid))
		var fw: int = int(fp["fw"])
		var fh: int = int(fp["fh"])
		for f: String in FACTIONS:
			var sid: StringName = _book.style_for_def(rid, "roster." + f)
			if rid.begins_with("neutral.") and f != "napc":
				continue
			var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), sid, 10000)
			t.check(not (d["placeholder"] as bool), "%s@%s builds: %s" % [rid, sid, d["error"]])
			if d["placeholder"] as bool:
				continue
			var info: ViewModelInfo = _info(d)
			var hx: float = float(fw) * 1.5 - 0.25
			var hz: float = float(fh) * 1.5 - 0.25
			var tol: float = 0.3 if rid.begins_with("neutral.") else overhang(String(_book.recipe(StringName(rid)).arch.id))
			t.check(info.rest_aabb.position.x >= -hx - tol and info.rest_aabb.end.x <= hx + tol and info.rest_aabb.position.z >= -hz - tol
				and info.rest_aabb.end.z <= hz + tol, "%s@%s inside its %dx%d plinth" % [rid, sid, fw, fh])
			t.le(info.height, height_cap(fw, fh) + 0.01, "%s@%s height %.2f" % [rid, sid, info.height])
			n += 1
	t.gt(n, 37, "shipped structure builds")


# ---------------------------------------------------------------------------------------------------- summons / projectiles
func test_projectiles_point_down_minus_z_and_are_small(t: TestCtx) -> void:
	_ensure()
	var lengths: Dictionary = {"proj_missile": 1.9, "proj_rocket": 1.2, "proj_bomb": 1.5, "proj_torpedo": 2.6}
	for a: String in PROJECTILES:
		var d: Dictionary = _build(StringName("rcx." + a))
		var info: ViewModelInfo = _info(d)
		var bb: AABB = info.rest_aabb
		t.near(bb.size.z, lengths[a] as float, 0.35, "%s length %.2f m" % [a, bb.size.z])
		t.lt(maxf(bb.size.x, bb.size.y), bb.size.z, "%s is longer than wide" % a)
		t.lt(bb.size.x, 1.0, "%s stays small" % a)
		t.le(info.tris.x, 900, "%s tris %d" % [a, info.tris.x])
		t.check(info.has_socket(&"tail"), "%s has the trail anchor" % a)
		# nose = -Z: the socket `tail` lies behind the centre, the widest section sits in the rear half
		t.gt((info.sockets[&"tail"] as ViewModelInfo.ViewSocket).pos.z, 0.3, "%s tail socket at +Z" % a)
		t.gt(team_roof_area(d) + _team_area_any(d), 0.0, "%s carries a team-masked band" % a)


static func _team_area_any(d: Dictionary) -> float:
	var arrays: Array = (d["mesh"] as Dictionary)["arrays"] as Array
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var n: int = 0
	for c: Color in col:
		if c.a > 0.5:
			n += 1
	return float(n)


func test_summons_budgets_hover_and_animation(t: TestCtx) -> void:
	_ensure()
	var hover: Dictionary = {"sum_uav": 14.0, "sum_balloon": 12.0, "sum_cargo": 15.0, "sum_drone_swarm": 9.0}
	var caps: Dictionary = {"sum_uav": 3500, "sum_balloon": 3500, "sum_cargo": 3500, "sum_drone_swarm": 3500, "sum_capsule": 6500, "sum_engine": 8000, "sum_station": 3500, "sum_cover": 5000}
	for a: String in SUMMONS:
		var info: ViewModelInfo = _info(_build(StringName("rcx." + a)))
		t.le(info.tris.x, caps[a] as int, "%s tris %d" % [a, info.tris.x])
		t.check(info.build_ms < 60.0, "%s builds in %.1f ms" % [a, info.build_ms])
		t.check(info.has_socket(&"top") or info.has_socket(&"muzzle0_0"), "%s has an anchor socket" % a)
		if hover.has(a):
			t.near(info.hover, hover[a] as float, 0.01, "%s cruise altitude" % a)
		t.gt(team_roof_area(_build(StringName("rcx." + a))) + _team_area_any(_build(StringName("rcx." + a))), 0.0, "%s has a team surface" % a)
	t.check(_info(_build(&"rcx.sum_uav")).has_part(Pt.ROTOR), "UAV lift fans spin")
	t.check(_info(_build(&"rcx.sum_cargo")).has_part(Pt.ROTOR), "cargo aircraft lift fans spin")
	t.check(_info(_build(&"rcx.sum_drone_swarm")).has_part(Pt.ROTOR), "drone rotors spin")
	t.check(_info(_build(&"rcx.sum_capsule")).has_part(Pt.DEPLOY) and _info(_build(&"rcx.sum_capsule")).has_part(Pt.DEPLOY_Z), "capsule petals unfold on both axes")
	t.check(_info(_build(&"rcx.sum_engine")).has_socket(&"muzzle0_0"), "siege engine gun socket")
	t.check(_info(_build(&"rcx.sum_engine")).has_part(Pt.TRACK), "siege engine tracks")
	t.check(_info(_build(&"rcx.sum_station")).has_part(Pt.DEPLOY_Z), "repair station arms")
	t.check(_info(_build(&"rcx.sum_cover")).has_part(Pt.DEPLOY), "pontoon repair arm")


func test_ground_summons_stay_inside_their_unit_size_class(t: TestCtx) -> void:
	_ensure()
	# medium ground (pontoon) 3.6 x 2, heavy (capsule), huge (engine) 7.0 x 4.6, light (station) 3.4 x 1.9 upper bounds of render 5.8.2
	var lim: Dictionary = {"sum_cover": Vector2(4.6, 4.6), "sum_capsule": Vector2(3.2, 3.2), "sum_engine": Vector2(4.8, 7.4), "sum_station": Vector2(4.0, 4.0)}
	for a: String in lim:
		var bb: AABB = _info(_build(StringName("rcx." + a))).rest_aabb
		var l: Vector2 = lim[a] as Vector2
		t.le(bb.size.x, l.x, "%s width %.2f" % [a, bb.size.x])
		t.le(bb.size.z, l.y, "%s length %.2f" % [a, bb.size.z])
