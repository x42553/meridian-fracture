extends RefCounted
## VQ2A acceptance: the readability boost (ViewConsts.VISUAL_BOOST), unit vs structure ratios on the REAL shipped balance data and the
## default start framing. The boost is a purely visual uniform scale of the unit archetypes: sim radii and footprints are untouched, so
## the justified bands are (a) the art direction 5.7 footprint rule relaxed to what neighbours can still stand beside (ground hull half
## width <= 1.3 r at the very worst, inf squad half extent <= 1.5 r) and (b) legibility minima at the default zoom.

var _data: GameData = null
var _book: ViewRecipeBook = null


func _load() -> void:
	if _data == null:
		_data = GameData.load_default()
		_book = ViewRecipeBook.new()
		_book.load_all()


func _info(rid: StringName, sid: StringName, scale_bp: int = 10000) -> ViewModelInfo:
	var o: Dictionary = ViewModelBuilder.build_data(_book, rid, sid, scale_bp)
	return o["info"] as ViewModelInfo


func test_boost_table_is_sane_and_only_touches_unit_archetypes(t: TestCtx) -> void:
	for k: String in ViewConsts.VISUAL_BOOST:
		var f: float = float(ViewConsts.VISUAL_BOOST[k])
		t.check(f >= 1.0 and f <= 1.4, "boost %s = %.2f within 1.0 .. 1.4" % [k, f])
	t.near(ViewConsts.visual_boost(&"veh_tank", &"medium"), 1.2, 0.0001, "tank boost")
	t.gt(ViewConsts.visual_boost(&"inf_rifle", &"inf"), ViewConsts.visual_boost(&"veh_tank", &"medium"), "infantry gets the largest boost")
	for a: StringName in [&"str_factory", &"sum_cover", &"proj_missile", &"neu_building", &"gen_prop"]:
		t.near(ViewConsts.visual_boost(a, &"medium"), 1.0, 0.0001, "%s is never boosted" % a)
	ViewConsts.visual_boost_enabled = false
	t.near(ViewConsts.visual_boost(&"veh_tank", &"medium"), 1.0, 0.0001, "QA switch off = design scale")
	ViewConsts.visual_boost_enabled = true


func test_boost_is_a_uniform_scale_of_the_design_model(t: TestCtx) -> void:
	_load()
	var rid: StringName = &"unit.napc.guardian_tank"
	var boosted: ViewModelInfo = _info(rid, &"napc")
	ViewConsts.visual_boost_enabled = false
	var base: ViewModelInfo = _info(rid, &"napc")
	ViewConsts.visual_boost_enabled = true
	t.near(boosted.boost, 1.2, 0.0001, "info.boost")
	t.near(base.boost, 1.0, 0.0001, "design info.boost")
	t.near(boosted.rest_aabb.size.x / base.rest_aabb.size.x, 1.2, 0.02, "width ratio")
	t.near(boosted.rest_aabb.size.z / base.rest_aabb.size.z, 1.2, 0.02, "length ratio")
	t.near(boosted.height / base.height, 1.2, 0.02, "height ratio")
	t.eq(boosted.tris, base.tris, "same triangle counts (no geometry change)")


func test_shipped_units_keep_clear_of_their_neighbours(t: TestCtx) -> void:
	_load()
	var worst_v: float = 0.0
	var worst_i: float = 0.0
	var worst_vid: String = ""
	var checked: int = 0
	for u: DefUnit in _data.units:
		var rid: StringName = StringName(u.pres_recipe if u.pres_recipe != "" else u.id)
		var r: ViewRecipe = _book.recipe(rid)
		if r == null or r.arch == null:
			continue
		var aid: String = String(r.arch.id)
		var is_squad: bool = aid.begins_with("inf_")
		if not (is_squad or aid.begins_with("veh_")):
			continue
		var info: ViewModelInfo = _info(rid, _book.style_for_def(u.id, ""), u.pres_scale_bp)
		var r_m: float = float(u.radius) * ViewConsts.M_PER_UNIT
		var bb: AABB = info.rest_aabb
		checked += 1
		if is_squad:
			var e: float = maxf(bb.size.x, bb.size.z) * 0.5 / r_m
			if e > worst_i:
				worst_i = e
		else:
			var w: float = bb.size.x * 0.5 / r_m  # hull half width over the collision radius (barrels live on the long axis)
			if w > worst_v:
				worst_v = w
				worst_vid = u.id
	t.gt(checked, 60, "units checked")
	t.le(worst_v, 1.3, "widest ground hull half width / r = %.2f (%s)" % [worst_v, worst_vid])
	t.le(worst_i, 1.5, "widest squad half extent / r = %.2f" % worst_i)


func test_units_are_legible_against_structures_at_the_default_framing(t: TestCtx) -> void:
	_load()
	var cam: ViewCamera = ViewCamera.new()
	var ppm: float = cam.px_per_m(ViewCamera.START_ZOOM, 1080.0)
	cam.free()
	t.ge(ppm, 24.0, "default framing %.1f px per metre at 1080p (spike: 27 px/m at 45 m)" % ppm)
	var tank: ViewModelInfo = _info(&"unit.napc.guardian_tank", &"napc")
	var squad: ViewModelInfo = _info(&"unit.napc.rifle_squad", &"napc")
	var heli: ViewModelInfo = _info(&"unit.napc.titan_gunship", &"napc")
	var hull_px: float = tank.rest_aabb.size.x * ppm
	var squad_px: float = squad.rest_aabb.size.x * ppm
	t.ge(hull_px, 62.0, "tank hull width %.0f px" % hull_px)
	t.ge(squad_px, 55.0, "squad width %.0f px at the default zoom" % squad_px)
	t.ge(heli.rest_aabb.size.z * ppm, 130.0, "gunship length %.0f px" % (heli.rest_aabb.size.z * ppm))
	# ratio to the 2x2 barracks plinth (5.5 m): a squad is at least 40 % of its width, a tank hull at least 50 %
	var barracks: ViewModelInfo = _info(&"structure.shared.barracks", &"napc")
	t.ge(squad.rest_aabb.size.x / barracks.rest_aabb.size.x, 0.4, "squad / barracks width %.2f" % (squad.rest_aabb.size.x / barracks.rest_aabb.size.x))
	t.ge(tank.rest_aabb.size.x / barracks.rest_aabb.size.x, 0.5, "tank / barracks width %.2f" % (tank.rest_aabb.size.x / barracks.rest_aabb.size.x))
	# the hull is still smaller than the smallest production structure: units never out-scale buildings
	t.lt(tank.rest_aabb.size.z, barracks.rest_aabb.size.z + 1.5, "tank length vs barracks")
