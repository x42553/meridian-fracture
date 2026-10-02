extends RefCounted
## VIEW-O1: selection rings / brackets and health bars (modes, visibility rules, widths, colours, pips, caps).

const Kit := preload("res://tests/view/vw_kit.gd")
const C: int = SimConfig.CELL


func _world() -> Array:
	var w: SimWorld = Kit.sim()
	var a: SimEntity = Kit.tank(w, 0, 46, 48)
	var b: SimEntity = Kit.rifle(w, 0, 50, 48)
	var foe: SimEntity = Kit.tank(w, 1, 54, 48)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(50.0, 48.0), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	return [w, vw, a, b, foe]


func _bar_floats(vw: ViewWorld, i: int) -> PackedFloat32Array:
	return vw.health_bars._buf._buf.slice(i * 20, i * 20 + 20)


func test_selection_rings_and_rim(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var a: SimEntity = r[2] as SimEntity
	var b: SimEntity = r[3] as SimEntity
	vw.selection.set_selection(PackedInt32Array([a.id, b.id]))
	Kit.frame(vw)
	t.eq(vw.selection.count, 2, "one ring per selected unit")
	t.near(vw.entity_view(a.id).selected_target, 1.0, 1e-6, "the model rim is driven (selected target)")
	vw.selection.set_selection(PackedInt32Array([b.id]))
	Kit.frame(vw)
	t.near(vw.entity_view(a.id).selected_target, 0.0, 1e-6, "deselected model loses the rim")
	# the rim eases in over 0.12 s (8 per second)
	for i: int in 10:
		Kit.frame(vw)
	t.near(vw.entity_view(b.id).selected, 1.0, 1e-3, "rim fully on after 0.16 s")
	vw.selection.set_hover((r[4] as SimEntity).id)
	Kit.frame(vw)
	t.eq(vw.selection.count, 2, "hover adds a thin ring")
	Kit.free_view(vw)


func test_ring_geometry_on_a_slope_and_structure_brackets(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var tank: SimEntity = Kit.tank(w, 0, 48, 48)
	var fac: SimEntity = w.spawn_structure(w.data.structure_idx(DefTestKit.S_FACTORY), 0, 40 * C + C, 44 * C + C / 2, 0, 0, 0, 0, SimEvent.SPAWN_INITIAL)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(44.0, 46.0), 0.2)
	Kit.step_frame(vw, 1, 1.0)
	vw.selection.set_selection(PackedInt32Array([tank.id, fac.id]))
	Kit.frame(vw)
	t.eq(vw.selection.count, 2, "a ring and a bracket set")
	var tv: ViewEntity = vw.entity_view(tank.id)
	var ring: PackedFloat32Array = vw.selection._ring._buf.slice(0, 20)
	t.near(ring[7], vw.ground_at(tv.wx, tv.wz) + ViewLayers.RING_LIFT_M, 0.02, "ring lifted 8 cm above the ground (flat terrain)")
	var expect_r: float = maxf(tv.radius_m * 1.25, 0.9) / 0.9
	t.near(ring[0], expect_r, 0.01, "quad scale = R / 0.9 (stroke at 90 % of the quad)")
	var rect: PackedFloat32Array = vw.selection._rect._buf.slice(0, 20)
	var st: ViewStructure = vw.entity_view(fac.id) as ViewStructure
	t.near(rect[16], float(st.footprint.x) * 1.5 + 0.3, 0.01, "bracket half extent = footprint + 0.3 m margin")
	Kit.free_view(vw)


func test_ring_cap_512(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 560:
		ids.append(Kit.rifle(w, 0, 10 + (i % 60), 10 + (i / 60) * 2).id)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(40.0, 20.0), 0.9)
	Kit.step_frame(vw, 1, 1.0)
	vw.selection.set_selection(ids)
	Kit.frame(vw)
	t.eq(vw.selection.count, 512, "rings are capped at 512")
	t.eq(vw.selection._ring.overflow, 48, "the overflow is counted, not drawn")
	Kit.free_view(vw)


func test_health_bar_modes_and_rules(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var w: SimWorld = r[0] as SimWorld
	var a: SimEntity = r[2] as SimEntity
	var foe: SimEntity = r[4] as SimEntity
	var hb: ViewHealthBars = vw.health_bars
	Kit.frame(vw)
	t.eq(hb.count, 0, "DAMAGED mode: nothing shown while nobody is hurt or selected")
	# a hit: the victim's bar shows for 8 s, then fades over 0.5 s
	hb.mark_damaged(a.id, w.tick)
	a.hp = a.hp_max * 6 / 10
	Kit.frame(vw)
	t.eq(hb.count, 1, "hurt own unit shows its bar")
	# enemies are shown only when selected / hovered
	hb.mark_damaged(foe.id, w.tick)
	Kit.frame(vw)
	t.eq(hb.count, 1, "a hurt enemy does not")
	hb.set_hover(foe.id)
	Kit.frame(vw)
	t.eq(hb.count, 2, "hovering the enemy shows it")
	hb.set_hover(-1)
	w.tick += 161
	Kit.frame(vw)
	t.eq(hb.count, 0, "bars vanish 8 s after the last hit")
	# selected units always show
	vw.selection.set_selection(PackedInt32Array([a.id]))
	Kit.frame(vw)
	t.eq(hb.count, 1, "a selected unit shows its bar")
	hb.set_mode(ViewHealthBars.Mode.NEVER)
	Kit.frame(vw)
	t.eq(hb.count, 0, "NEVER")
	hb.set_mode(ViewHealthBars.Mode.ALWAYS)
	Kit.frame(vw)
	t.eq(hb.count, vw.entity_count() - _non_bar_entities(vw), "ALWAYS shows every mirrored entity that has hit points")
	Kit.free_view(vw)


func _non_bar_entities(vw: ViewWorld) -> int:
	var n: int = 0
	for ve: ViewEntity in vw.entities():
		if ve.max_hp <= 0 or ve.kind == SimEntity.Kind.WRECK or ve.vs != ViewConsts.VS_VISIBLE:
			n += 1
	return n


func test_health_bar_data_widths_colours_and_pips(t: TestCtx) -> void:
	var r: Array = _world()
	var vw: ViewWorld = r[1] as ViewWorld
	var a: SimEntity = r[2] as SimEntity
	var b: SimEntity = r[3] as SimEntity
	var hb: ViewHealthBars = vw.health_bars
	hb.set_mode(ViewHealthBars.Mode.SELECTED)
	vw.selection.set_selection(PackedInt32Array([a.id, b.id]))
	a.hp = a.hp_max * 25 / 100
	b.hp = b.hp_max * 50 / 100
	Kit.step_frame(vw, 1, 1.0)
	Kit.frame(vw)
	t.eq(hb.count, 2, "two selected bars")
	var va: ViewEntity = vw.entity_view(a.id)
	var vb: ViewEntity = vw.entity_view(b.id)
	var found: Dictionary = {}
	for i: int in 2:
		var f: PackedFloat32Array = _bar_floats(vw, i)
		found[int(round(f[16] * 1000.0))] = f
	var fa: PackedFloat32Array = found.values()[0] as PackedFloat32Array
	# identify by width (tank 44 / 56 px by size class, squad 28)
	var by_w: Dictionary = {}
	for k: Variant in found:
		by_w[int((found[k] as PackedFloat32Array)[17])] = found[k]
	t.check(by_w.has(int(ViewHealthBars.width_px(va))) and by_w.has(int(ViewHealthBars.width_px(vb))), "bar widths follow the size class")
	t.eq(ViewHealthBars.colour_id(0.75, false), ViewHealthBars.COL_GREEN, "> 60 % green")
	t.eq(ViewHealthBars.colour_id(0.45, false), ViewHealthBars.COL_YELLOW, "30-60 % yellow")
	t.eq(ViewHealthBars.colour_id(0.20, false), ViewHealthBars.COL_RED, "< 30 % red")
	t.eq(ViewHealthBars.colour_id(0.90, true), ViewHealthBars.COL_BUILD, "construction bars are cyan-white")
	t.near((by_w[int(ViewHealthBars.width_px(vb))] as PackedFloat32Array)[16], 0.5, 0.02, "hp fraction in custom.x")
	t.eq(int((by_w[int(ViewHealthBars.width_px(vb))] as PackedFloat32Array)[19]), vb.members - 1, "squad member count rides in the pips mask")
	if fa.size() == 0:
		return
	# pip shapes: distinct per player index 0..7, ids 8..15 repeat with the outline flag
	var shapes: Dictionary = {}
	for pid_idx: int in 8:
		va.team_index = pid_idx
		va.team_color = ViewTeamColors.color(pid_idx)
		Kit.frame(vw)
		var packed: int = int(round(_bar_floats(vw, 0)[15] * 16.0))
		if _bar_floats(vw, 0)[17] != ViewHealthBars.width_px(va):
			packed = int(round(_bar_floats(vw, 1)[15] * 16.0))
		shapes[packed & 7] = true
		t.eq(packed >> 3, 0, "id %d: no outline" % pid_idx)
	t.eq(shapes.size(), 8, "eight distinct pip shapes for player indices 0-7")
	va.team_index = 9
	Kit.frame(vw)
	var f9: PackedFloat32Array = _bar_floats(vw, 0)
	var p9: int = int(round((f9[15] if f9[17] == ViewHealthBars.width_px(va) else _bar_floats(vw, 1)[15]) * 16.0))
	t.eq(p9 >> 3, 1, "id 9 repeats a shape with the outline flag")
	Kit.free_view(vw)


func test_structure_under_construction_shows_a_cyan_bar(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w, 0, Vector2(44.0, 46.0), 0.2)
	var fac: int = w.data.structure_idx(DefTestKit.S_FACTORY)
	var s: SimEntity = w.spawn_structure(fac, 0, 44 * C + C, 44 * C + C / 2, 0, 0, 0, 0, SimEvent.SPAWN_PLACED)
	Kit.step_frame(vw, 5, 0.0)
	var st: ViewStructure = vw.entity_view(s.id) as ViewStructure
	t.eq(st.phase, ViewConsts.PH_BUILDUP, "buildup")
	t.eq(vw.health_bars.count, 1, "all structures under construction get a bar")
	var f: PackedFloat32Array = _bar_floats(vw, 0)
	t.eq(int(f[18]), ViewHealthBars.COL_BUILD, "cyan-white")
	t.near(f[16], st.build, 0.001, "the bar shows the build progress")
	Kit.step_frame(vw, 40, 0.0)
	t.eq(vw.health_bars.count, 0, "the bar disappears when the structure is complete (DAMAGED mode)")
	Kit.free_view(vw)
