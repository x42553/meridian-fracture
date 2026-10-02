extends RefCounted
## VIEW-O2: order / rally lines, range rings, the placement ghost with per-cell colours and the build-radius ring.

const Kit := preload("res://tests/view/vw_kit.gd")
const EK := preload("res://tests/support/sim_econ_kit.gd")
const C: int = SimConfig.CELL


func _order(type: int, cx: int, cy: int, target: int = 0) -> SimOrder:
	var o: SimOrder = SimOrder.new()
	o.type = type
	o.x = cx * C + C / 2
	o.y = cy * C + C / 2
	o.target_id = target
	return o


func _lines_world() -> Array:
	var w: SimWorld = Kit.sim()
	var a: SimEntity = Kit.tank(w, 0, 46, 48)
	var foe: SimEntity = Kit.tank(w, 1, 60, 48)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(50.0, 48.0), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	var ln: ViewLines = ViewLines.new()
	vw.add_child(ln)
	ln.setup(vw)
	return [w, vw, a, foe, ln]


func test_order_path_colours_caps_and_ownership(t: TestCtx) -> void:
	var r: Array = _lines_world()
	var vw: ViewWorld = r[1] as ViewWorld
	var a: SimEntity = r[2] as SimEntity
	var foe: SimEntity = r[3] as SimEntity
	var ln: ViewLines = r[4] as ViewLines
	a.orders.append(_order(SimOrder.T_MOVE, 52, 48))
	a.orders.append(_order(SimOrder.T_ATTACK_MOVE, 52, 54))
	a.orders.append(_order(SimOrder.T_GUARD, 46, 54))
	foe.orders.append(_order(SimOrder.T_MOVE, 70, 48))
	ln.set_order_sources(PackedInt32Array([a.id, foe.id]))
	ln.update(1.0)
	t.eq(ln.count_lines, 3, "three legs for the own unit, none for the enemy (enemy orders are never read)")
	var rib: ViewRibbon = ln.ribbon()
	t.gt(rib.vertex_count, 20, "ribbon has geometry")
	t.gt(rib.triangle_count(), 20, "and triangles")
	var cols: Dictionary = {}
	for c: Color in rib._col:
		cols[c.to_html(false)] = true
	t.check(cols.has(ViewLines.COL_MOVE.to_html(false)), "move is green")
	t.check(cols.has(ViewLines.COL_ATTACK_MOVE.to_html(false)), "attack-move is orange")
	t.check(cols.has(ViewLines.COL_GUARD.to_html(false)), "guard is blue")
	t.check(not cols.has(ViewLines.COL_ATTACK.to_html(false)), "no red without an attack order")
	# throttle: nothing changed, no rebuild
	var n0: int = ln.rebuilds
	ln.update(1.0)
	ln.update(1.0)
	t.eq(ln.rebuilds, n0, "no rebuild while orders and positions are unchanged")
	# more than 8 orders: capped
	for i: int in 12:
		a.orders.append(_order(SimOrder.T_MOVE, 40 + i, 40))
	ln.update(1.0)
	t.eq(ln.count_lines, ViewLines.MAX_WAYPOINTS, "at most 8 waypoints per unit")
	Kit.free_view(vw)


func test_hidden_target_never_leaks_and_attack_is_red(t: TestCtx) -> void:
	var r: Array = _lines_world()
	var vw: ViewWorld = r[1] as ViewWorld
	var a: SimEntity = r[2] as SimEntity
	var foe: SimEntity = r[3] as SimEntity
	var ln: ViewLines = r[4] as ViewLines
	a.orders.append(_order(SimOrder.T_ATTACK, 0, 0, foe.id))
	ln.set_order_sources(PackedInt32Array([a.id]))
	ln.update(1.0)
	t.eq(ln.count_lines, 1, "attack line to a visible enemy")
	var has_red: bool = false
	for c: Color in ln.ribbon()._col:
		has_red = has_red or c.is_equal_approx(ViewLines.COL_ATTACK)
	t.check(has_red, "attack is red")
	var fv: ViewEntity = vw.entity_view(foe.id)
	fv.vs = ViewConsts.VS_HIDDEN
	ln._dirty = true
	ln.update(1.0)
	t.eq(ln.count_lines, 0, "the position of a hidden target is not drawn")
	Kit.free_view(vw)


func test_rally_line_from_structure(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var fac: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_FACTORY), 0, 40 * C + C, 44 * C + C / 2, 0, 0, 0, 0, SimEvent.SPAWN_INITIAL)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(44.0, 46.0), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	var ln: ViewLines = ViewLines.new()
	vw.add_child(ln)
	ln.setup(vw)
	ln.set_rally_sources(PackedInt32Array([fac.id]))
	ln.update(1.0)
	t.eq(ln.count_lines, 0, "no rally point set: nothing drawn")
	if fac.prod == null:
		t.skip("factory has no production component in this fixture")
	else:
		fac.prod.rally_on = true
		fac.prod.rally_x = 50 * C
		fac.prod.rally_y = 50 * C
		ln.update(1.0)
		t.eq(ln.count_lines, 1, "rally line drawn")
		var green: bool = false
		for c: Color in ln.ribbon()._col:
			green = green or c.is_equal_approx(ViewLines.COL_RALLY)
		t.check(green, "rally is green")
	Kit.free_view(vw)


func test_range_rings(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var a: SimEntity = Kit.tank(w, 0, 46, 48)
	var b: SimEntity = Kit.rifle(w, 0, 50, 48)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.0, 48.0), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	var rr: ViewRangeRings = ViewRangeRings.new()
	vw.add_child(rr)
	rr.setup(vw)
	rr.show_for(PackedInt32Array([a.id, b.id]))
	rr.update(1.0)
	t.gt(rr.rings().size(), 0, "armed entities get a ring")
	var expect_m: float = float(w.combat.range_max_eff(w, a, -1)) * 3.0 / 1024.0
	var got: Dictionary = {}
	for rec: Dictionary in rr.rings():
		if rec["id"] == a.id:
			got = rec
	t.near(got["r"] as float, expect_m, 0.001, "radius = range_max_eff * 3 / 1024 metres")
	t.gt(rr.ribbon().vertex_count, 100, "ring geometry")
	# points lie on the circle
	var ok: bool = true
	var av: ViewEntity = vw.entity_view(a.id)
	for i: int in mini(rr.ribbon()._pos.size(), 40):
		var p: Vector3 = rr.ribbon()._pos[i]
		if absf(Vector2(p.x - av.wx, p.z - av.wz).length() - expect_m) > 0.05:
			ok = false
	t.check(ok, "ribbon vertices sit on the range circle")
	# cap
	var ids: PackedInt32Array = PackedInt32Array()
	for i2: int in 20:
		ids.append(Kit.tank(w, 0, 20 + i2, 30).id)
	Kit.frame(vw)
	rr.show_for(ids)
	t.eq(rr.rings().size(), 1, "twenty identical tanks show one ring (one per distinct range class)")
	# preview and hide
	rr.show_preview(Vector3(100.0, 0.0, 100.0), 18.0, 6.0)
	rr.update(1.0)
	t.eq(rr.count, 3, "the tank ring plus the preview's max and min ring")
	rr.hide_all()
	rr.update(1.0)
	t.check(not rr.has_rings(), "hide_all clears")
	t.eq(rr.ribbon().vertex_count, 0, "and empties the mesh")
	Kit.free_view(vw)


func test_range_ring_colours_by_weapon_class(t: TestCtx) -> void:
	var rr: ViewRangeRings = ViewRangeRings.new()
	var vd: ViewDef = ViewDef.new()
	var aa: int = DefEnums.WEAPON_ARCH_NAMES.find("aa_missile")
	var art: int = DefEnums.WEAPON_ARCH_NAMES.find("artillery_shell")
	var gun: int = DefEnums.WEAPON_ARCH_NAMES.find("tank_cannon")
	rr._arch_air = ViewRangeRings._arch_indices(["aa_missile", "flak"])
	rr._arch_arty = ViewRangeRings._arch_indices(["artillery_shell", "mortar"])
	vd.warch = PackedInt32Array([aa, -1, -1, -1])
	t.eq(rr._color_of(vd), ViewRangeRings.COL_AIR, "anti-air is cyan")
	vd.warch = PackedInt32Array([art, -1, -1, -1])
	t.eq(rr._color_of(vd), ViewRangeRings.COL_ARTY, "artillery is orange")
	vd.warch = PackedInt32Array([gun, aa, -1, -1])
	t.eq(rr._color_of(vd), ViewRangeRings.COL_GROUND, "a mixed loadout reads as ground")
	rr.free()


func _econ_view() -> Array:
	var w: SimWorld = EK.make_world()
	var hq: SimEntity = EK.spawn_struct(w, DefTestKit.S_HQ, 0, 40, 40)
	w.step()
	var vw: ViewWorld = Kit.view(w, 0, Vector2(44.0, 44.0), 0.25)
	Kit.step_frame(vw, 1, 1.0)
	return [w, vw, hq]


func test_ghost_cells_from_the_economy_validator(t: TestCtx) -> void:
	var r: Array = _econ_view()
	var w: SimWorld = r[0] as SimWorld
	var vw: ViewWorld = r[1] as ViewWorld
	EK.spawn_struct(w, DefTestKit.S_GENERATOR, 0, 46, 40, 600)
	w.step()
	Kit.frame(vw)
	var gh: ViewPlacementGhost = ViewPlacementGhost.new()
	vw.add_child(gh)
	gh.setup(vw)
	var si: int = EK.sidx(DefTestKit.S_BARRACKS)
	var vd: ViewDef = vw.defs.def_for(SimEntity.Kind.STRUCTURE, si)
	gh.show_structure(si, vd.recipe_id, StringName("neutral"), 0)
	# valid site
	var res: SimPlacementResult = SimPlacementResult.new()
	SimPlacement.validate(w, 0, si, 44, 44, 0, res)
	var st: ViewPlacementState = ViewPlacementState.new()
	st.fill_from_placement(res, si, 0)
	gh.update_cursor(Vector3.ZERO, st, "")
	t.eq(gh.footprint_size, Vector2i(res.w, res.h), "footprint size from the validator")
	t.eq(gh.grid_mesh().surface_get_array_len(0), (res.w + 3) * (res.h + 3), "grid covers the footprint plus a one-cell halo")
	t.eq(gh.last_codes.size(), res.w * res.h, "one code per footprint cell")
	t.eq(gh.last_codes, res.cells, "codes = the validator's cells")
	t.check(gh.rig().visible, "ghost model shown")
	t.eq(gh.grid_material().get_shader_parameter(&"verdict"), 0.0, "valid verdict")
	var cx: float = (float(res.ox) + float(res.w) * 0.5) * 3.0
	t.near(gh.rig().position.x, cx, 0.01, "model snapped to the footprint centre (x)")
	# overlapping the generator: red cells
	SimPlacement.validate(w, 0, si, 45, 40, 0, res)
	st.fill_from_placement(res, si, 0)
	t.check(res.reason != 0, "the site is refused")
	gh.update_cursor(Vector3.ZERO, st, "Blocked")
	t.eq(gh.grid_material().get_shader_parameter(&"verdict"), 1.0, "invalid verdict")
	var bad: int = 0
	for b: int in gh.last_codes:
		if b == ViewPlacementState.CF_STRUCTURE or b == ViewPlacementState.CF_TERRAIN:
			bad += 1
	t.gt(bad, 0, "the overlapping cells carry a blocked code")
	t.eq(gh.label().text, "Blocked", "reason text")
	t.check(gh.label().visible, "reason label shown")
	# outside the build radius: every cell reads red and the tint follows
	SimPlacement.validate(w, 0, si, 70, 70, 0, res)
	st.fill_from_placement(res, si, 0)
	t.check(not st.in_radius, "out of radius")
	gh.update_cursor(Vector3.ZERO, st, "Outside build radius")
	for b2: int in gh.last_codes:
		t.eq(b2, ViewPlacementState.CF_TERRAIN, "all cells red outside the radius")
	gh.hide_ghost()
	t.check(not gh.rig().visible and not gh.label().visible, "hidden")
	Kit.free_view(vw)


func test_ghost_from_the_map_validator_and_rotation(t: TestCtx) -> void:
	var r: Array = _econ_view()
	var vw: ViewWorld = r[1] as ViewWorld
	var gh: ViewPlacementGhost = ViewPlacementGhost.new()
	vw.add_child(gh)
	gh.setup(vw)
	var si: int = EK.sidx(DefTestKit.S_BARRACKS)
	var vd: ViewDef = vw.defs.def_for(SimEntity.Kind.STRUCTURE, si)
	gh.show_structure(si, vd.recipe_id, StringName("neutral"), 0)
	var st: ViewPlacementState = ViewPlacementState.new()
	st.fill_from_map_check(4, si, 44, 44, vd.fp_w, vd.fp_h, 0)  # PR_NOBUILD
	gh.update_cursor(Vector3.ZERO, st, "")
	var all_keepout: bool = true
	for b: int in gh.last_codes:
		all_keepout = all_keepout and b == ViewPlacementState.CF_KEEPOUT
	t.check(all_keepout, "a map PR_NOBUILD colours the footprint keep-out")
	# a non-rotatable footprint ignores rot
	st.fill_from_map_check(0, si, 44, 44, vd.fp_w, vd.fp_h, 1)
	gh.update_cursor(Vector3.ZERO, st, "")
	t.near(gh.rig().rotation.y, 0.0, 1e-6, "only rotatable footprints (the Dock) rotate")
	gh._rotatable = true
	gh._sig = 0
	st.rot = 1
	gh.update_cursor(Vector3.ZERO, st, "")
	t.near(gh.rig().rotation.y, -PI * 0.5, 1e-4, "a quarter turn clockwise seen from above")
	Kit.free_view(vw)


func test_build_radius_ring_is_24_m_around_completed_hqs(t: TestCtx) -> void:
	var r: Array = _econ_view()
	var w: SimWorld = r[0] as SimWorld
	var vw: ViewWorld = r[1] as ViewWorld
	var hq: SimEntity = r[2] as SimEntity
	var gh: ViewPlacementGhost = ViewPlacementGhost.new()
	vw.add_child(gh)
	gh.setup(vw)
	t.eq(gh.hq_centres().size(), 1, "one completed friendly HQ")
	gh.show_build_radius(true)
	gh.update(1.0)
	t.gt(gh.ring_vertex_count(), 100, "ring drawn")
	var hv: ViewEntity = vw.entity_view(hq.id)
	var rib: ViewRibbon = gh._ring
	var worst: float = 0.0
	for p: Vector3 in rib._pos:
		worst = maxf(worst, absf(Vector2(p.x - hv.wx, p.z - hv.wz).length() - 24.0))
	t.lt(worst, 0.01, "every ring vertex is 24 m (8 cells) from the HQ centre")
	# an enemy or allied HQ does not extend it; an HQ under construction does not either
	EK.spawn_struct(w, DefTestKit.S_HQ, 1, 10, 10)
	EK.spawn_struct(w, DefTestKit.S_HQ, 0, 60, 60, 0, false)
	w.step()
	Kit.frame(vw)
	Kit.frame(vw)
	t.eq(gh.hq_centres().size(), 1, "enemy and unfinished HQs are ignored")
	gh.show_build_radius(false)
	t.eq(gh.ring_vertex_count(), 0, "off clears the ring")
	Kit.free_view(vw)


func test_ribbon_strips_split_at_corners(t: TestCtx) -> void:
	var rib: ViewRibbon = ViewRibbon.new()
	rib.begin()
	var straight: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(6, 0, 0)])
	rib.add_polyline(straight, Color.WHITE, ViewRibbon.STYLE_SOLID)
	t.eq(rib.vertex_count, 6, "3 points = 6 ribbon vertices")
	var bent: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 3)])
	rib.add_polyline(bent, Color.WHITE, ViewRibbon.STYLE_SOLID)
	t.eq(rib.vertex_count, 6 + 8, "a right angle splits the strip (2 x 2 points)")
	t.near(rib._uv[6].x, -1.0, 1e-6, "side coordinate")
	t.near(rib._uv[rib._uv.size() - 1].y, 6.0, 1e-4, "distance stays continuous along the path across the split")
	rib.begin()
	t.eq(rib.vertex_count, 0, "begin clears")
