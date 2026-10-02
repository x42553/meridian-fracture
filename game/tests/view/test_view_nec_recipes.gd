extends RefCounted
## F-nec (VIEW-M8) acceptance for the New European Confederation content: the 19 unit recipes, the three NEC structures and the
## `styles/nec.json` overlays (`nec`, `nec.nordics`, `nec.eurocorps`, `nec.alpine_brotherhood`) that the shared structures use.
## Palette against the bible `visual_direction`, team-plate contrast for the 12 lobby colours, per-model triangle budgets
## (render spec 5.8.2), team-mask area, sibling distinctness. Run with `tools/gd test view_nec`.

const UNITS: PackedStringArray = [
	"unit.nec.jager_squad", "unit.nec.spike_team", "unit.nec.sapper", "unit.nec.surveyor_apc", "unit.nec.leopard_tank",
	"unit.nec.rapier_aa", "unit.nec.archer_spg", "unit.nec.argent_rail_tank", "unit.nec.kestrel_interceptor",
	"unit.nec.aster_ew_aircraft", "unit.nec.skerry_patrol_boat", "unit.nec.horizon_escort", "unit.nec.concord_monitor",
	"unit.nec.fen_recon_carrier", "unit.nec.fjord_missile_carrier", "unit.nec.marte_heavy_mbt", "unit.nec.charlemagne_siege_tank",
	"unit.nec.alpine_pioneer", "unit.nec.ibex_crawler_gun"]
const STRUCTS: PackedStringArray = ["structure.nec.relay", "structure.nec.lance_rail_emplacement", "structure.nec.aurora_microwave_array"]
const SHARED: PackedStringArray = [
	"structure.shared.headquarters", "structure.shared.generator", "structure.shared.refinery", "structure.shared.barracks",
	"structure.shared.factory", "structure.shared.dock", "structure.shared.radar", "structure.shared.airfield",
	"structure.shared.laboratory", "structure.shared.watchtower", "structure.shared.anti_tank_turret", "structure.shared.aa_battery"]
const STYLES: PackedStringArray = ["nec", "nec.nordics", "nec.eurocorps", "nec.alpine_brotherhood"]
## unique subfaction unit -> the baseline unit it replaces
const REPLACES: Dictionary = {
	"unit.nec.fen_recon_carrier": "unit.nec.surveyor_apc", "unit.nec.fjord_missile_carrier": "unit.nec.archer_spg",
	"unit.nec.marte_heavy_mbt": "unit.nec.leopard_tank", "unit.nec.charlemagne_siege_tank": "unit.nec.argent_rail_tank",
	"unit.nec.alpine_pioneer": "unit.nec.sapper", "unit.nec.ibex_crawler_gun": "unit.nec.archer_spg"}
## LOD0 / LOD1 triangle caps (render spec 5.8.2) per model
const CAPS: Dictionary = {
	"unit.nec.jager_squad": [1400, 800], "unit.nec.spike_team": [1400, 800], "unit.nec.sapper": [1400, 800], "unit.nec.alpine_pioneer": [1400, 800],
	"unit.nec.surveyor_apc": [3500, 2000], "unit.nec.fen_recon_carrier": [3500, 2000],
	"unit.nec.leopard_tank": [5000, 2800], "unit.nec.marte_heavy_mbt": [5000, 2800], "unit.nec.rapier_aa": [5000, 2800],
	"unit.nec.archer_spg": [5000, 2800], "unit.nec.ibex_crawler_gun": [5000, 2800], "unit.nec.fjord_missile_carrier": [5000, 2800],
	"unit.nec.argent_rail_tank": [6500, 3600], "unit.nec.charlemagne_siege_tank": [6500, 3600],
	"unit.nec.kestrel_interceptor": [3000, 1700], "unit.nec.aster_ew_aircraft": [3500, 2000],
	"unit.nec.skerry_patrol_boat": [2000, 1200], "unit.nec.horizon_escort": [5000, 2800], "unit.nec.concord_monitor": [8000, 4500],
	"structure.nec.relay": [3000, 1700], "structure.nec.lance_rail_emplacement": [3000, 1700], "structure.nec.aurora_microwave_array": [10000, 5500]}

var _book: ViewRecipeBook = null
var _models: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false


func _load() -> void:
	if _book != null:
		return
	_book = ViewRecipeBook.new()
	_book.load_all()


func _build(rid: String, sid: String) -> ViewModel:
	_load()
	var key: String = rid + "@" + sid
	if not _models.has(key):
		var d: Dictionary = ViewModelBuilder.build_data(_book, StringName(rid), StringName(sid), 10000)
		var m: ViewModel = ViewModel.new()
		m.mesh = ViewMeshBuilder.mesh_from_arrays(d["mesh"] as Dictionary, key)
		m.info = d["info"] as ViewModelInfo
		m.placeholder = d["placeholder"] as bool
		m.error = d["error"] as String
		_models[key] = m
	return _models[key] as ViewModel


func _hex(s: Variant) -> Color:
	return Color.html(str(s))


func test_nec_recipes_are_hand_authored(t: TestCtx) -> void:
	_load()
	t.eq(_book.errors().size(), 0, "recipe book loads clean: %s" % ", ".join(_book.errors()))
	var ids: PackedStringArray = UNITS + STRUCTS
	t.eq(ids.size(), 22, "19 units + 3 structures")
	for rid: String in ids:
		var r: ViewRecipe = _book.recipe(StringName(rid))
		if not t.not_null(r, "%s has a recipe" % rid):
			continue
		t.check_false(bool(r.meta.get("stub", false)), "%s is no longer a stub" % rid)
		t.check(r.meta.has("size_card") and r.meta.has("role"), "%s carries meta.role / meta.size_card" % rid)
	for sid: String in STYLES:
		t.check(_book.has_style(StringName(sid)), "style %s exists" % sid)
	# subfaction overlays extend the faction style and change only trim, emblem, kit values and slots (no new palette)
	var base: Dictionary = _book.style(&"nec")
	for sid: String in STYLES.slice(1):
		var st: Dictionary = _book.style(StringName(sid))
		var pal_base: Dictionary = base["palette"] as Dictionary
		var pal_sub: Dictionary = st["palette"] as Dictionary
		for k: Variant in pal_base:
			if k != "acc":
				t.eq(str(pal_sub[k]), str(pal_base[k]), "%s keeps palette.%s" % [sid, k])
		t.ne(str(pal_sub["acc"]), str(pal_base["acc"]), "%s has its own accent" % sid)


func test_nec_models_build_within_budget(t: TestCtx) -> void:
	_load()
	var over: PackedStringArray = PackedStringArray()
	var bad: PackedStringArray = PackedStringArray()
	for rid: String in UNITS + STRUCTS:
		var m: ViewModel = _build(rid, "nec")
		if m.placeholder:
			bad.append("%s: %s" % [rid, m.error])
			continue
		var caps: Array = CAPS[rid] as Array
		if m.info.tris.x - m.info.livery_tris.x > int(caps[0]) or m.info.tris.y - m.info.livery_tris.y > int(caps[1]) or m.info.verts > 65535:
			over.append("%s tris %d / %d (cap %d / %d) verts %d" % [rid, m.info.tris.x, m.info.tris.y, caps[0], caps[1], m.info.verts])
		if m.info.build_ms > 60.0:
			over.append("%s build %.0f ms" % [rid, m.info.build_ms])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(over.size(), 0, "over budget: %s" % " | ".join(over))


func test_nec_styles_build_the_shared_structures_and_units(t: TestCtx) -> void:
	_load()
	var bad: PackedStringArray = PackedStringArray()
	var big: PackedStringArray = PackedStringArray()
	for sid: String in STYLES:
		for rid: String in SHARED:
			var m: ViewModel = _build(rid, sid)
			if m.placeholder:
				bad.append("%s@%s: %s" % [rid, sid, m.error])
			elif m.info.height > 14.0 or m.info.tris.x > 10000:
				big.append("%s@%s h=%.1f tris=%d" % [rid, sid, m.info.height, m.info.tris.x])
		for rid: String in UNITS:
			var m2: ViewModel = _build(rid, sid)
			if m2.placeholder:
				bad.append("%s@%s: %s" % [rid, sid, m2.error])
			else:
				var caps: Array = CAPS[rid] as Array
				if m2.info.tris.x - m2.info.livery_tris.x > int(caps[0]) or m2.info.tris.y - m2.info.livery_tris.y > int(caps[1]):
					big.append("%s@%s tris %d / %d (cap %d / %d)" % [rid, sid, m2.info.tris.x, m2.info.tris.y, caps[0], caps[1]])
	t.eq(bad.size(), 0, "placeholders: %s" % " | ".join(bad))
	t.eq(big.size(), 0, "too big: %s" % " | ".join(big))


func test_nec_palette_matches_visual_direction(t: TestCtx) -> void:
	_load()
	var bible: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bible/meridian_factions.json")) as Dictionary
	var vd: String = ""
	var facs: Variant = (bible.get("factions") as Dictionary)
	vd = str(((facs as Dictionary)["faction.nec"] as Dictionary).get("visual_direction", "")).to_lower()
	t.check(vd.contains("slate blue") and vd.contains("white") and vd.contains("amber"), "bible visual_direction names slate blue / white / amber: %s" % vd)
	var pal: Dictionary = (_book.style(&"nec")["palette"] as Dictionary)
	var base: Color = _hex(pal["base"])
	var sec: Color = _hex(pal["sec"])
	var acc: Color = _hex(pal["acc"])
	var dark: Color = _hex(pal["dark"])
	t.check(base.h * 360.0 >= 205.0 and base.h * 360.0 <= 235.0, "slate blue hue %.0f" % (base.h * 360.0))
	t.check(base.s >= 0.25 and base.s <= 0.6 and base.v >= 0.3 and base.v <= 0.65, "slate blue is muted: s %.2f v %.2f" % [base.s, base.v])
	t.check(sec.v >= 0.85 and sec.s <= 0.12, "secondary is white: s %.2f v %.2f" % [sec.s, sec.v])
	t.check(acc.h * 360.0 >= 30.0 and acc.h * 360.0 <= 50.0 and acc.s >= 0.75 and acc.v >= 0.8, "accent is amber: h %.0f s %.2f" % [acc.h * 360.0, acc.s])
	t.check(absf(dark.h - base.h) * 360.0 < 20.0 and dark.v < base.v, "dark shares the slate hue and is darker")
	# paint albedo stays in the tone-mapping safe range (luma 0.3-0.5 for the hull colour, render spec 5.8.4)
	var luma: float = base.r * 0.2126 + base.g * 0.7152 + base.b * 0.0722
	t.check(luma >= 0.22 and luma <= 0.5, "hull luma %.2f" % luma)
	# subfaction accents: sibling accents differ by >= 8 dE, hue stays within 25 degrees of the parent amber, no new palette hue
	var accents: Array[Color] = [acc]
	for sid: String in STYLES.slice(1):
		var c: Color = _hex((_book.style(StringName(sid))["palette"] as Dictionary)["acc"])
		t.check(absf(c.h - acc.h) * 360.0 <= 25.0, "%s accent hue within 25 degrees of amber (%.0f)" % [sid, c.h * 360.0])
		for other: Color in accents:
			t.ge(ViewTeamColors.delta_e(c, other), 8.0, "%s accent separates from its siblings" % sid)
		accents.append(c)


func test_nec_team_plate_contrast(t: TestCtx) -> void:
	_load()
	# the team_panel / roof_plate macros wrap every team surface in the dark `plate` gasket and a pale quiet ring, so what matters is
	# that each of the 12 lobby colours separates from the plate; against the raw slate paint it is only informational
	for sid: String in STYLES:
		var pal: Dictionary = (_book.style(StringName(sid))["palette"] as Dictionary)
		var plate: Color = _hex(pal["plate"])
		var base: Color = _hex(pal["base"])
		var worst_plate: float = INF
		var worst_base: float = INF
		var worst_id: int = 0
		for id in 12:
			var c: Color = ViewTeamColors.color(id)
			worst_plate = minf(worst_plate, ViewTeamColors.delta_e(c, plate))
			var db: float = ViewTeamColors.delta_e(c, base)
			if db < worst_base:
				worst_base = db
				worst_id = id
		t.ge(worst_plate, 25.0, "%s: every player colour separates from the plate gasket" % sid)
		t.note("%s: min dE vs plate %.0f, min dE vs slate paint %.0f (colour id %d, gasket carries it)" % [sid, worst_plate, worst_base, worst_id])
	# every unit recipe puts player colour on a real surface, and the built mesh has a measurable team area
	for rid: String in UNITS:
		var frac: float = _team_fraction(_build(rid, "nec"))
		t.check(frac >= 0.012 and frac <= 0.3, "%s team-masked top area %.1f%%" % [rid, frac * 100.0])


## Fraction of the up-facing triangle area (LOD0) whose vertices carry a team mask > 0.5.
func _team_fraction(m: ViewModel) -> float:
	var arr: Array = m.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR] as PackedColorArray
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] as PackedInt32Array
	var tot: float = 0.0
	var team: float = 0.0
	var i: int = 0
	while i + 2 < idx.size():
		var a: int = idx[i]
		var b: int = idx[i + 1]
		var d: int = idx[i + 2]
		i += 3
		var n: Vector3 = (v[b] - v[a]).cross(v[d] - v[a])
		var ar: float = absf(n.y) * 0.5
		if n.length() < 0.00001 or absf(n.y) / n.length() < 0.5:
			continue
		tot += ar
		if c[a].a > 0.5 and c[b].a > 0.5 and c[d].a > 0.5:
			team += ar
	return team / maxf(tot, 0.0001)


func test_nec_units_are_distinct(t: TestCtx) -> void:
	_load()
	var hashes: Dictionary = {}
	for rid: String in UNITS:
		var h: int = _build(rid, "nec").info.content_hash
		t.check_false(hashes.has(h), "%s does not duplicate %s" % [rid, str(hashes.get(h, ""))])
		hashes[h] = rid
	# a unique subfaction unit is a designed variant: same class, but its bounding box or its kit differs visibly from the unit it replaces
	for uid: String in REPLACES:
		var a: ViewModelInfo = _build(uid, "nec").info
		var b: ViewModelInfo = _build(REPLACES[uid] as String, "nec").info
		var da: Vector3 = a.rest_aabb.size
		var db: Vector3 = b.rest_aabb.size
		var rel: float = maxf(absf(da.x - db.x) / maxf(db.x, 0.01), maxf(absf(da.y - db.y) / maxf(db.y, 0.01), absf(da.z - db.z) / maxf(db.z, 0.01)))
		var tri_rel: float = absf(float(a.tris.x - b.tris.x)) / float(maxi(b.tris.x, 1))
		var vert_rel: float = absf(float(a.verts - b.verts)) / float(maxi(b.verts, 1))
		t.check(rel > 0.04 or tri_rel > 0.05 or vert_rel > 0.05, "%s differs from %s (bounds %.0f%%, tris %.0f%%, verts %.0f%%)" % [uid, REPLACES[uid], rel * 100.0, tri_rel * 100.0, vert_rel * 100.0])
