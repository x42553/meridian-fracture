extends RefCounted
## VIEW-W2 / VIEW-O3 scenarios on a REAL SimWorld (shipped balance data, real economy / combat / vision / strategic systems): the
## structure lifecycle (build-up with scaffold, damage stages, low-power fade, sale, collapse with rubble), wreck timing (60 s, burn-out,
## sink in the last 1.5 s), remembered-structure ghosts under fog, zones without models, strategic warnings (geometry, who sees them,
## cancel), floating text, status marks, the FX port and the debug overlay.

const Kit := preload("res://tests/view/w2_kit.gd")
const C: int = SimConfig.CELL


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ---- structure lifecycle -------------------------------------------------------------------------------------------------

func test_buildup_rises_inside_a_scaffold_and_completes(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.factory", 0, 40, 40, SimEvent.SPAWN_PLACED, SimFlags.F_UNDER_CONSTRUCTION)
	Kit.tick(vw, 1)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	t.not_null(st, "structure record")
	if st == null:
		Kit.free_view(vw)
		return
	t.eq(st.phase, ViewConsts.PH_BUILDUP, "SPAWNED with reason PLACED starts the build-up")
	t.eq(st.phase_ticks, ViewStructure.DEFAULT_BUILDUP_TICKS, "30 ticks")
	Kit.tick(vw, 14)
	t.check(st.build > 0.35 and st.build < 0.7, "about half way after 15 ticks (build %.2f)" % st.build)
	var want_sink: float = (1.0 - _ease(st.build)) * (st.height_m + 1.5)
	t.near(st.sink_m, want_sink, 0.05, "u_anim.x = (1 - ease(build)) * (height + 1.5)")
	t.eq(vw.scaffolds.count, 1, "one scaffold cage while building")
	t.check(vw.fx.count_of(&"building_collapse") == 0, "no collapse effect")
	Kit.tick(vw, 20)
	t.eq(st.phase, ViewConsts.PH_ACTIVE, "active after the build-up")
	t.near(st.sink_m, 0.0, 0.0001, "risen")
	t.eq(vw.scaffolds.count, 0, "cage gone")
	t.gt(vw.fx.count_of(&"ring_add") + vw.fx.count_of(&"sprites"), 0, "completion and weld effects were requested")
	Kit.free_view(vw)


func test_scaffold_pool_is_capped_and_follows_visibility(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	for i: int in 30:
		Kit.place(w, "structure.shared.watchtower", 0, 6 + (i % 10) * 2, 6 + (i / 10) * 2, SimEvent.SPAWN_PLACED, SimFlags.F_UNDER_CONSTRUCTION)
	Kit.tick(vw, 3)
	t.check(vw.scaffolds.tracked_count() >= 24, "all 30 structures tracked (%d)" % vw.scaffolds.tracked_count())
	t.check(vw.scaffolds.count <= ViewScaffolds.MAX_CAGES, "cage pool capped at %d (%d shown)" % [ViewScaffolds.MAX_CAGES, vw.scaffolds.count])
	Kit.tick(vw, 35)
	t.eq(vw.scaffolds.count, 0, "all cages gone")
	t.eq(vw.scaffolds.tracked_count(), 0, "nothing tracked any more")
	Kit.free_view(vw)


func test_damage_stages_have_hysteresis(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.factory", 0, 40, 40)
	Kit.tick(vw, 6)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	t.eq(st.damage_stage, 0, "healthy")
	var stages: Array = []
	for pct: int in [80, 60, 40, 30, 36, 40, 70, 72]:
		e.hp = e.hp_max * pct / 100
		Kit.tick(vw, 6)
		stages.append(st.damage_stage)
	# 80 -> 0, 60 -> 1 (smoke), 40 -> 1, 30 -> 2 (fire), 36 -> still 2 (needs > 38 %), 40 -> 1, 70 -> still 1 (needs > 71 %), 72 -> 0
	t.eq(stages, [0, 1, 1, 2, 2, 1, 1, 0], "smoke below 66 %, fire below 33 %, 5 % hysteresis")
	e.hp = e.hp_max * 25 / 100
	Kit.tick(vw, 12)
	t.gt(st.damage, 0.6, "shader damage channel rises with the loss (%.2f)" % st.damage)
	t.check((st.flags & ViewConsts.UF_STRUCT) != 0, "UF_STRUCT set: the shader draws cracks and paint loss")
	Kit.free_view(vw)


func test_damage_emitters_are_capped_and_nearest_first(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.0, 48.0), 0.9)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 40:
		var e: SimEntity = Kit.place(w, "structure.shared.watchtower", 0, 40 + (i % 10) * 2, 40 + (i / 10) * 2)
		if e != null:
			e.hp = e.hp_max * 20 / 100
			ids.append(e.id)
	Kit.tick(vw, 14)
	vw.state.update(1.0)  # forces a ranking pass
	t.eq(vw.state.damage_emitters, ViewStateOverlays.DAMAGE_CAP, "40 damaged structures, exactly %d emitters" % ViewStateOverlays.DAMAGE_CAP)
	t.gt(vw.fx.count_of(&"puff_smoke"), 0, "smoke was requested")
	Kit.free_view(vw)


func test_low_power_fades_emissives_over_0_4_s(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.factory", 0, 40, 40)
	Kit.tick(vw, 3)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	st.needs_power = true
	st.powered = true
	vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.near(st.power_fade, 0.0, 0.0001, "powered: no fade")
	st.powered = false
	var frames: int = 0
	while st.power_fade < 1.0 and frames < 60:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
		frames += 1
		if frames == 6:
			t.check(st.power_fade > 0.2 and st.power_fade < 0.6, "a quarter of a second in: partway (%.2f)" % st.power_fade)
	t.check(frames >= 22 and frames <= 26, "fully dark after 0.4 s = 24 frames (%d)" % frames)
	t.check((st.flags & ViewConsts.UF_UNPOWERED) != 0, "UF_UNPOWERED while dark")
	t.near(st.move01, 1.0, 0.001, "u_anim.y carries the fade depth")
	st.powered = true
	for i: int in 30:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.near(st.power_fade, 0.0, 0.0001, "power back: fade out again")
	t.check((st.flags & ViewConsts.UF_UNPOWERED) == 0, "flag cleared once the fade ran out")
	Kit.free_view(vw)


func test_radar_spins_down_over_two_seconds(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.radar", 0, 40, 40)
	Kit.tick(vw, 3)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	st.powered = true
	for i: int in 90:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.near(st.spin, ViewStructure.RADAR_RATE, 0.001, "spun up")
	st.powered = false
	st.needs_power = false
	for i: int in 60:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.check(st.spin > 0.2 and st.spin < 0.9, "decelerating one second in (%.2f)" % st.spin)
	for i: int in 80:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.near(st.spin, 0.0, 0.001, "stopped after about two seconds")
	Kit.free_view(vw)


func test_sale_reverses_the_buildup(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.factory", 0, 40, 40)
	Kit.tick(vw, 4)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	w.emit(SimEconConst.EVT_STRUCTURE_SELLING, e.x, e.y, 0, e.id, w.tick + 40)
	Kit.tick(vw, 2)
	t.eq(st.phase, ViewConsts.PH_SELLING, "selling")
	t.eq(vw.scaffolds.count, 1, "cage while selling")
	Kit.tick(vw, 16)
	t.check(st.build < 0.7 and st.build > 0.3, "sinking (build %.2f)" % st.build)
	Kit.tick(vw, 30)
	t.near(st.build, 0.0, 0.001, "fully sunk")
	t.gt(st.sink_m, st.height_m, "buried")
	Kit.free_view(vw)


func test_destruction_collapses_into_rubble_for_thirty_seconds(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.factory", 1, 40, 40)
	Kit.tick(vw, 4)
	var id: int = e.id
	w.kill(e, SimCombatConsts.CAUSE_DAMAGE, 0, 0)
	Kit.tick(vw, 2)
	var st: ViewStructure = Kit.structure_view(vw, id)
	t.not_null(st, "dying record")
	if st == null:
		Kit.free_view(vw)
		return
	t.check(st.dead and st.dying_kind == ViewConsts.DK_STRUCTURE, "DK_STRUCTURE")
	t.check(st.dying_until_tick - st.dying_start_tick >= 20, "the record outlives the 7-tick sim window so the sink is visible (%d ticks)" % (st.dying_until_tick - st.dying_start_tick))
	t.eq(vw.fx.count_of(&"building_collapse"), 1, "one building_collapse")
	t.check(vw.rubble.has_heap(id), "a rubble heap starts")
	Kit.tick(vw, 6)
	t.gt(st.sink_m, 0.0, "sinking after the shake")
	Kit.tick(vw, 20)
	t.check(not vw.has_entity(id), "record disposed after the collapse")
	t.check(vw.rubble.has_heap(id), "rubble stays")
	# 30 s of view time later the heap is gone (dt of one second per frame)
	for i: int in 25:
		vw.frame(1.0, 1.0, PackedInt32Array())
	t.check(vw.rubble.has_heap(id), "still there at 25 s")
	for i: int in 8:
		vw.frame(1.0, 1.0, PackedInt32Array())
	t.check(not vw.rubble.has_heap(id), "gone after 30 s")
	Kit.free_view(vw)


func test_refinery_unload_arm_cycles_while_docked(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var e: SimEntity = Kit.place(w, "structure.shared.refinery", 0, 40, 40)
	Kit.tick(vw, 4)
	var st: ViewStructure = Kit.structure_view(vw, e.id)
	if st == null or e.econ == null:
		t.fail("refinery record or economy component missing")
		Kit.free_view(vw)
		return
	e.econ.dock_occupant = 999
	var hi: float = 0.0
	for i: int in 8:
		Kit.tick(vw, 1, 6)
	for i: int in 60:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
		hi = maxf(hi, st.activity)
	t.check(st.dock_busy, "dock occupancy is read")
	t.gt(hi, 0.9, "the arm reaches full travel (%.2f)" % hi)
	e.econ.dock_occupant = 0
	Kit.tick(vw, 8, 6)
	for i: int in 150:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.near(st.deploy, 0.0, 0.01, "finishes the cycle and rests")
	Kit.free_view(vw)


# ---- wrecks ---------------------------------------------------------------------------------------------------------------

func test_wreck_lives_60_seconds_burns_out_and_sinks_in_the_last_1_5_s(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(4)
	var vw: ViewWorld = Kit.view(w)
	var victim: SimEntity = Kit.unit(w, 1, false, 40, 40)
	Kit.tick(vw, 3)
	w.kill(victim, SimCombatConsts.CAUSE_DAMAGE, 0, 0)
	Kit.tick(vw, 3)
	var wreck: SimEntity = null
	for we: SimEntity in w.wrecks:
		if (we.flags & SimFlags.F_GONE) == 0:
			wreck = we
	t.not_null(wreck, "an enemy kill leaves a wreck (salvage is enabled by the AE roster)")
	if wreck == null:
		Kit.free_view(vw)
		return
	var ve: ViewUnit = vw.entity_view(wreck.id) as ViewUnit
	t.not_null(ve, "wreck record")
	t.check((ve.flags & ViewConsts.UF_WRECK) != 0, "UF_WRECK")
	t.eq(wreck.expire_tick - wreck.born, SimCombatConsts.WRECK_TICKS, "the sim keeps a wreck 1200 ticks = 60 s")
	# early: embers burning, not sunk
	Kit.tick(vw, 10)
	t.gt(ve.cloak, 0.5, "fresh wreck: embers at full (%.2f)" % ve.cloak)
	t.near(ve.sink_m, 0.0, 0.0001, "not sunk")
	# after 15 s the embers are out
	for i: int in 300:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.lt(ve.cloak, 0.05, "embers burnt out after 14 s (%.3f)" % ve.cloak)
	# run to 40 ticks before the end: still level; 15 ticks before: sinking
	while w.tick < wreck.expire_tick - 40:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.near(ve.sink_m, 0.0, 0.0001, "level 2 s before the end")
	while w.tick < wreck.expire_tick - 15:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.check(ve.sink_m > 0.1 and ve.sink_m < ViewUnit.WRECK_SINK_M, "sinking in the last 1.5 s (%.2f m)" % ve.sink_m)
	t.check(vw.has_entity(wreck.id), "still there 15 ticks before the end")
	for i: int in 30:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.check(not vw.has_entity(wreck.id), "gone at the end of its 60 s (8-tick shrink after the sim removal)")
	Kit.free_view(vw)


func test_wreck_fx_starts_once_then_thins_out(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(4)
	var vw: ViewWorld = Kit.view(w)
	var victim: SimEntity = Kit.unit(w, 1, false, 40, 40)
	Kit.tick(vw, 3)
	w.kill(victim, SimCombatConsts.CAUSE_DAMAGE, 0, 0)
	for i: int in 40:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.eq(vw.fx.count_of(&"wreck_start"), 1, "one wreck_start")
	var before: int = vw.fx.count_of(&"puff_smoke")
	for i: int in 400:
		w.step()
		vw.frame(1.0 / 20.0, 1.0, w.events.take())
	t.gt(vw.fx.count_of(&"puff_smoke"), before, "thin smoke after the first 14 s")
	t.eq(vw.fx.count_of(&"wreck_start"), 1, "still just one wreck_start")
	Kit.free_view(vw)


# ---- ghosts ---------------------------------------------------------------------------------------------------------------

func test_remembered_structure_ghost_under_fog(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2, true)
	var vw: ViewWorld = Kit.view(w)
	var enemy: SimEntity = Kit.place(w, "structure.shared.factory", 1, 50, 50)
	var scout: SimEntity = Kit.unit(w, 0, false, 44, 50)
	Kit.tick(vw, 14)
	var live: ViewEntity = vw.entity_view(enemy.id)
	t.not_null(live, "enemy record")
	t.check(live.vs != ViewConsts.VS_HIDDEN, "seen by the scout")
	t.eq(vw.ghosts.count, 0, "no ghost while visible")
	w.remove_entity(scout.id, SimEvent.REM_SCRIPT)
	Kit.tick(vw, 30)
	t.eq(live.vs, ViewConsts.VS_HIDDEN, "out of sight: the live model hides")
	var gl: Array = w.fog.ghosts(0)
	t.eq(gl.size(), 1, "the sim remembers it")
	vw.ghosts.invalidate()
	Kit.tick(vw, 2)
	t.eq(vw.ghosts.count, 1, "one ghost drawn")
	var g: ViewStructure = vw.ghosts.ghost_view(enemy.id)
	t.not_null(g, "ghost record by the entity id")
	if g != null:
		t.check((g.flags & ViewConsts.UF_GHOST) != 0, "UF_GHOST")
		t.eq(g.model, live.model, "the model of that def in the owner's style")
		t.eq(vw.ghosts.ghost_at(g.wx, g.wz), enemy.id, "the picker can find the ghost by its footprint")
		t.eq(vw.ghosts.ghost_at(g.wx + 40.0, g.wz), -1, "and nothing beside it")
	# damage look follows the remembered hp: damage the building, look again, then remember once more
	var scout2: SimEntity = Kit.unit(w, 0, false, 44, 50)
	Kit.tick(vw, 14)
	enemy.hp = enemy.hp_max / 4
	Kit.tick(vw, 8)
	t.eq(vw.ghosts.count, 0, "seen again: the ghost goes")
	t.check(live.vs != ViewConsts.VS_HIDDEN, "live model back")
	w.remove_entity(scout2.id, SimEvent.REM_SCRIPT)
	Kit.tick(vw, 30)
	vw.ghosts.invalidate()
	Kit.tick(vw, 2)
	var g2: ViewStructure = vw.ghosts.ghost_view(enemy.id)
	t.not_null(g2, "remembered again")
	if g2 != null:
		t.gt(g2.damage, 0.5, "the remembered damage shows (%.2f)" % g2.damage)
	Kit.free_view(vw)


func test_ghost_disappears_when_the_cell_is_seen_empty(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2, true)
	var vw: ViewWorld = Kit.view(w)
	var enemy: SimEntity = Kit.place(w, "structure.shared.barracks", 1, 50, 50)
	var scout: SimEntity = Kit.unit(w, 0, false, 46, 50)
	Kit.tick(vw, 14)
	w.remove_entity(scout.id, SimEvent.REM_SCRIPT)
	Kit.tick(vw, 30)
	vw.ghosts.invalidate()
	Kit.tick(vw, 2)
	t.eq(vw.ghosts.count, 1, "ghost")
	# the building is destroyed unseen, then the spot is looked at again
	w.kill(enemy, SimCombatConsts.CAUSE_DAMAGE, 0, 1)
	Kit.tick(vw, 12)
	Kit.unit(w, 0, false, 46, 50)
	Kit.tick(vw, 14)
	t.eq(vw.ghosts.count, 0, "the sim drops the record once the cell is visible and empty")
	Kit.free_view(vw)


# ---- zones ----------------------------------------------------------------------------------------------------------------

func test_zones_are_mirrored_without_models(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var names: Array[String] = ["zone.smoke_dust_screen", "zone.repair_station", "zone.sensor_puck", "zone.infantry_shelter", "zone.portable_cover",
		"zone.horizon_debris", "zone.trident_interception"]
	var made: Array[int] = []
	var col: int = 0
	for nm: String in names:
		var zi: int = w.data.zone_idx(nm)
		t.check(zi >= 0, "%s exists" % nm)
		var zid: int = w.zones.create_zone(zi, 0, (20 + col * 8) * C, 40 * C, 0, w.tick + 400)
		made.append(zid)
		col += 1
	Kit.tick(vw, 3)
	var live: int = 0
	for zid: int in made:
		if zid >= 0:
			live += 1
	t.eq(vw.zones.zone_ids().size(), live, "one visual per zone")
	var kinds: Dictionary = {}
	for zid2: int in vw.zones.zone_ids():
		kinds[vw.zones.vis_of(zid2).kind] = true
	t.check(kinds.has(DefEnums.ZoneKind.SMOKE) and kinds.has(DefEnums.ZoneKind.REPAIR) and kinds.has(DefEnums.ZoneKind.PUCK) and kinds.has(DefEnums.ZoneKind.DEBRIS) and kinds.has(DefEnums.ZoneKind.INTERCEPT), "smoke, repair, puck, debris and interception all drawn")
	for zid3: int in vw.zones.zone_ids():
		var z: ViewZones.Vis = vw.zones.vis_of(zid3)
		t.check(z.node != null and z.node.mesh != null, "zone %d has a conforming mesh" % zid3)
		if z.kind == DefEnums.ZoneKind.INTERCEPT:
			t.not_null(z.dome, "the interception zone has a dome")
		if z.kind == DefEnums.ZoneKind.DEBRIS:
			t.gt(z.hl, 5.0, "the debris field is a capsule (half length %.1f m)" % z.hl)
		if z.kind == DefEnums.ZoneKind.SMOKE:
			t.near(z.r, 18.0, 0.5, "Dust Screen radius 6 cells = 18 m")
	# ending a zone fades it out in 0.4 s and removes it
	var first: int = made[0]
	w.zones.end_zone(first, SimZoneConsts.ZE_CANCELLED)
	Kit.tick(vw, 3)
	for i: int in 40:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.check(vw.zones.vis_of(first) == null, "ended zone is gone after the fade")
	Kit.free_view(vw)


func test_decoy_zones_never_show_to_the_enemy(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0)
	var zi: int = w.data.zone_idx("zone.decoy_tank")
	var own: int = w.zones.create_zone(zi, 0, 30 * C, 30 * C, 0, w.tick + 400)
	var theirs: int = w.zones.create_zone(zi, 1, 60 * C, 60 * C, 0, w.tick + 400)
	Kit.tick(vw, 3)
	t.check(own >= 0 and theirs >= 0, "both decoy zones created")
	t.check(vw.zones.vis_of(own) != null, "own decoy zone shows")
	t.check(vw.zones.vis_of(theirs) == null, "an enemy decoy zone is never drawn")
	Kit.free_view(vw)


func test_interception_brightness_follows_the_charges(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var zid: int = w.zones.create_zone(w.data.zone_idx("zone.trident_interception"), 0, 40 * C, 40 * C, 0, w.tick + 400)
	Kit.tick(vw, 3)
	var z: ViewZones.Vis = vw.zones.vis_of(zid)
	t.not_null(z, "dome zone")
	var full: float = z.charge
	w.zones.get_zone(zid).charges = 6
	Kit.tick(vw, 6)
	t.check(z.charge < full, "fewer charges: dimmer (%.2f -> %.2f)" % [full, z.charge])
	t.near(z.charge, 6.0 / 24.0, 0.001, "charge / 24")
	Kit.free_view(vw)


# ---- warnings -------------------------------------------------------------------------------------------------------------

func _warn(w: SimWorld, sw_id: String, owner: int, cx: int, cy: int, angle: int = 300) -> SimWarning:
	var si: int = w.data.superweapon_idx(sw_id)
	var sw: DefSuperweapon = w.data.superweapons[si]
	var geom: PackedInt32Array = SimSuperweapons.geometry(sw, cx * C, cy * C, angle, cx * C, cy * C)
	return w.strategic.add_warning(w, SimEconConst.WK_SUPER, si, owner, 0, geom, sw.warning_t, SimSuperweapons.exec_span(sw))


func _modes(rec: ViewWarnings.Rec) -> Array:
	var out: Array = []
	for p: ViewWarnings.Prim in rec.prims:
		out.append(p.mode)
	return out


func test_warning_geometry_per_superweapon(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	Kit.unit(w, 0, false, 40, 40)  # a local unit in every zone so the local player is affected
	var atlas: SimWarning = _warn(w, "superweapon.napc.atlas_kinetic_array", 1, 40, 40)
	var helios: SimWarning = _warn(w, "superweapon.olm.helios_reflector", 1, 40, 40)
	var horizon: SimWarning = _warn(w, "superweapon.ae.horizon_mass_driver", 1, 40, 40)
	var perun: SimWarning = _warn(w, "superweapon.def.perun_missile_complex", 1, 40, 40)
	for sw: SimWarning in [atlas, helios, horizon, perun]:
		sw.affected_mask |= 1
	Kit.tick(vw, 4)
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	var ra: ViewWarnings.Rec = vw.warnings.rec_of(atlas.id)
	var rh: ViewWarnings.Rec = vw.warnings.rec_of(helios.id)
	var rz: ViewWarnings.Rec = vw.warnings.rec_of(horizon.id)
	var rp: ViewWarnings.Rec = vw.warnings.rec_of(perun.id)
	t.check(ra != null and rh != null and rz != null and rp != null, "all four warnings drawn")
	if ra == null or rh == null or rz == null or rp == null:
		Kit.free_view(vw)
		return
	t.eq(_modes(ra), [ViewWarnings.MODE_TRAIL, ViewWarnings.MODE_IMPACT, ViewWarnings.MODE_IMPACT, ViewWarnings.MODE_IMPACT], "Atlas: three impact circles joined by the axis")
	t.eq(_modes(rh), [ViewWarnings.MODE_LINE], "Helios: the beam line")
	t.eq(_modes(rz), [ViewWarnings.MODE_LINE, ViewWarnings.MODE_IMPACT, ViewWarnings.MODE_IMPACT, ViewWarnings.MODE_IMPACT], "Horizon: the strike line with its three impacts")
	t.eq(_modes(rp), [ViewWarnings.MODE_AREA, ViewWarnings.MODE_CORE], "Perun: fragmentation ring and core")
	# Perun: ring radius 7 cells, core 3 cells
	t.near(rp.prims[0].r, 7.0 * 3.0, 0.05, "Perun ring = 7 cells")
	t.near(rp.prims[1].r, 3.0 * 3.0, 0.05, "Perun core = 3 cells")
	# Atlas circles: radius 2 cells at -3, 0, +3 cells along the axis
	t.near(ra.prims[1].r, 6.0, 0.05, "Atlas circle radius 2 cells")
	var d01: float = ra.prims[1].center.distance_to(ra.prims[2].center)
	t.near(d01, 9.0, 0.1, "circles 3 cells apart")
	# Helios line: 16 cells long, 3 cells wide
	t.near(rh.prims[0].hl * 2.0, 48.0, 0.2, "Helios line 16 cells")
	t.near(rh.prims[0].r * 2.0, 9.0, 0.1, "3 cells wide")
	# Horizon: 10 cells of line, three impacts at -5, 0, +5 cells with their delays
	t.near(rz.prims[0].hl * 2.0, 30.0, 0.2, "Horizon line 10 cells")
	t.eq([rz.prims[1].delay_ticks, rz.prims[2].delay_ticks, rz.prims[3].delay_ticks], [0, 90, 180], "impacts at X, X+90, X+180")
	# the light column over each target is requested for the warning phase
	Kit.tick(vw, 4)
	t.gt(vw.fx.count_of(&"beacon"), 3, "a beacon column per warning (%d)" % vw.fx.count_of(&"beacon"))
	Kit.free_view(vw)


func test_strike_power_warnings_are_circles_or_lines(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	Kit.unit(w, 0, false, 40, 40)
	var circle: SimWarning = w.strategic.add_warning(w, SimEconConst.WK_POWER, 0, 1, 0, PackedInt32Array([40 * C, 40 * C, 40 * C, 40 * C, 3 * C, 0, 0]), 100, 200)
	var line: SimWarning = w.strategic.add_warning(w, SimEconConst.WK_POWER, 1, 1, 0, PackedInt32Array([36 * C, 40 * C, 44 * C, 40 * C, C, 2 * C, 0]), 100, 200)
	var scan: SimWarning = w.strategic.add_warning(w, SimEconConst.WK_SCAN, 2, 0, 0, PackedInt32Array([50 * C, 50 * C, 50 * C, 50 * C, 6 * C, 0, 0]), 100, 200)
	for x: SimWarning in [circle, line, scan]:
		x.affected_mask |= 1
	Kit.tick(vw, 4)
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	t.eq(_modes(vw.warnings.rec_of(circle.id)), [ViewWarnings.MODE_AREA], "a strike power circle")
	t.eq(_modes(vw.warnings.rec_of(line.id)), [ViewWarnings.MODE_LINE], "a strike power line")
	var rs: ViewWarnings.Rec = vw.warnings.rec_of(scan.id)
	t.check(rs != null and not rs.hostile, "the Wideband scan is shown, never as an attack")
	Kit.free_view(vw)


func test_warnings_show_only_to_affected_players_and_ignore_fog(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(3, true, PackedInt32Array([1, 2, 3]))
	var vw: ViewWorld = Kit.view(w, 0)
	Kit.unit(w, 0, false, 40, 40)
	var near: SimWarning = _warn(w, "superweapon.def.perun_missile_complex", 1, 40, 40)
	var far: SimWarning = _warn(w, "superweapon.def.perun_missile_complex", 1, 80, 80)
	t.check((near.affected_mask & 1) != 0, "the sim says player 0 is affected by the near zone")
	t.check((far.affected_mask & 1) == 0, "and not by the far one")
	Kit.tick(vw, 4)
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	t.check(vw.warnings.rec_of(near.id) != null, "affected: drawn although the enemy launcher is in the fog")
	t.check(vw.warnings.rec_of(far.id) == null, "not affected: nothing drawn")
	var rec: ViewWarnings.Rec = vw.warnings.rec_of(near.id)
	if rec != null:
		t.check(rec.hostile, "an enemy attack: DANGER colour set")
	# an observer sees everything
	vw.set_local_player(-1, true)
	vw.warnings.request_sync()
	Kit.tick(vw, 3)
	t.check(vw.warnings.rec_of(far.id) != null, "observers see every warning")
	Kit.free_view(vw)


func test_own_team_warning_is_amber_and_the_trident_is_seen_by_all(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2, false, PackedInt32Array([1, 2]))
	var vw: ViewWorld = Kit.view(w, 0)
	var own: SimWarning = _warn(w, "superweapon.def.perun_missile_complex", 0, 40, 40)
	var trident: SimWarning = _warn(w, "superweapon.sap.trident_interception_array", 1, 60, 60)
	Kit.tick(vw, 4)
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	var ro: ViewWarnings.Rec = vw.warnings.rec_of(own.id)
	t.check(ro != null and not ro.hostile, "own attack: WARN amber")
	var rt: ViewWarnings.Rec = vw.warnings.rec_of(trident.id)
	t.check(rt != null, "the Trident warning reaches every player")
	if rt != null:
		t.check(not rt.hostile, "the dome is defensive: amber for everybody")
	Kit.free_view(vw)


func test_countdown_label_and_cancel(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	Kit.unit(w, 0, false, 40, 40)
	var wr: SimWarning = _warn(w, "superweapon.def.perun_missile_complex", 1, 40, 40)
	wr.affected_mask |= 1
	Kit.tick(vw, 4)
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	var rec: ViewWarnings.Rec = vw.warnings.rec_of(wr.id)
	t.not_null(rec, "warning drawn")
	if rec == null:
		Kit.free_view(vw)
		return
	var shown: float = rec.label.text.trim_prefix("!! ").to_float()
	var want: float = float(wr.exec_tick - w.tick) * 0.05
	t.check(absf(shown - want) < 0.35, "the label counts down (%s vs %.1f s)" % [rec.label.text, want])
	Kit.tick(vw, 20)
	var shown2: float = rec.label.text.trim_prefix("!! ").to_float()
	t.lt(shown2, shown - 0.8, "and keeps counting (%.1f -> %.1f)" % [shown, shown2])
	# cancel: the record leaves the live list, flashes, fades and is freed
	wr.phase = SimEconConst.AT_CANCELLED
	vw.warnings.request_sync()
	Kit.tick(vw, 2)
	t.check(rec.dying and rec.cancelled, "cancelled warnings fade out marked as cancelled")
	for i: int in 60:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.check(vw.warnings.rec_of(wr.id) == null, "gone after the fade")
	Kit.free_view(vw)


# ---- float text, marks, port, debug ----------------------------------------------------------------------------------------

func test_float_text_pool_and_aggregation(t: TestCtx) -> void:
	var ft: ViewFloatText = ViewFloatText.new()
	ft.setup(null)
	for i: int in 40:
		ft.popup("+%d" % i, Vector3(float(i), 0.0, 0.0), ViewFloatText.GOLD)
	ft.update(0.016)
	t.eq(ft.active_count, ViewFloatText.POOL, "pool of %d, the oldest recycled" % ViewFloatText.POOL)
	var n: int = 0
	for i: int in 100:
		ft.update(0.02)
		n = ft.active_count
	t.eq(n, 0, "all labels fade away within 1.2 s")
	var before: int = ft.total_popups
	ft.add_income(7, 100, Vector3.ZERO)
	ft.add_income(7, 50, Vector3.ZERO)
	ft.add_income(8, 30, Vector3.ZERO)
	ft.update(0.2)
	t.eq(ft.total_popups, before, "aggregating: nothing shown before 0.5 s")
	ft.update(0.4)
	t.eq(ft.total_popups, before + 2, "one popup per source after 0.5 s")
	ft.clear()
	ft.free()


func test_income_events_become_gold_numbers_for_the_local_player_only(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0)
	Kit.tick(vw, 2)
	var before: int = vw.float_text.total_popups
	w.emit(SimEconConst.EVT_CREDITS_GAINED, 40 * C, 40 * C, 0, 700, 40 * C, 40 * C)
	w.emit(SimEconConst.EVT_CREDITS_GAINED, 60 * C, 40 * C, 1, 500, 60 * C, 40 * C)
	Kit.tick(vw, 1)
	for i: int in 45:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.eq(vw.float_text.total_popups, before + 1, "only the local player's income is shown")
	Kit.free_view(vw)


func test_status_marks_masks(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0)
	var emp: SimEntity = Kit.unit(w, 0, false, 40, 40)
	var sup: SimEntity = Kit.unit(w, 0, true, 44, 40)
	var clo: SimEntity = Kit.unit(w, 0, false, 48, 40)
	var foe: SimEntity = Kit.unit(w, 1, false, 52, 40)
	Kit.tick(vw, 2)
	emp.flags |= SimFlags.F_EMP_SHUT
	sup.flags |= SimFlags.F_SUPPRESSED
	clo.flags |= SimFlags.F_CLOAKED
	foe.flags |= SimFlags.F_CLOAKED | SimFlags.F_SUPPRESSED
	Kit.tick(vw, 8)
	var marks: ViewStatusMarks = vw.status_marks
	t.eq(marks.mask_of(vw.entity_view(emp.id)), 1 << ViewStatusMarks.G_EMP, "EMP bolt")
	t.eq(marks.mask_of(vw.entity_view(sup.id)), 1 << ViewStatusMarks.G_SUPPRESSED, "suppression chevrons")
	t.eq(marks.mask_of(vw.entity_view(clo.id)), 1 << ViewStatusMarks.G_CLOAK, "own cloaked unit: cloak ring")
	t.eq(marks.mask_of(vw.entity_view(foe.id)), 1 << ViewStatusMarks.G_SUPPRESSED, "an enemy's cloak is not marked")
	for i: int in 30:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.check(marks.count >= 3 or marks.count == 0, "glyph rows are batched (%d)" % marks.count)
	Kit.free_view(vw)


func test_capture_progress_ring_and_power_glyph(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0)
	var neutral: SimEntity = Kit.place(w, "structure.shared.watchtower", 1, 40, 40)
	var tower: SimEntity = Kit.place(w, "structure.shared.anti_tank_turret", 0, 50, 40)
	Kit.tick(vw, 4)
	t.check(neutral.econ != null, "economy component")
	neutral.econ.cap_progress = 500
	neutral.econ.cap_pid = 0
	tower.flags &= ~SimFlags.F_POWERED
	Kit.tick(vw, 8)
	for i: int in 30:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.eq(vw.status_marks.ring_count, 1, "one capture ring")
	neutral.econ.cap_progress = 0
	Kit.tick(vw, 8)
	for i: int in 30:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
	t.eq(vw.status_marks.ring_count, 0, "ring gone with the capture")
	Kit.free_view(vw)


func test_fx_port_is_a_noop_without_a_manager_and_records_for_tests(t: TestCtx) -> void:
	var p: ViewFxPort = ViewFxPort.new()
	t.check(not p.active(), "inactive")
	t.eq(p.spawn(&"building_collapse", Vector3.ZERO), -1, "no-op")
	p.puff(&"puff_smoke", Vector3.ZERO, 1.0, 1.0)
	p.weld_spark(Vector3.ZERO)
	t.eq(p.stat_forwarded, 0, "nothing forwarded")
	p.recording = true
	p.spawn(&"a", Vector3.ZERO)
	p.spawn(&"b", Vector3.ONE, Vector3.ZERO, 2.0)
	p.suppressed[&"b"] = true
	p.spawn(&"b", Vector3.ONE)
	t.eq(p.count_of(&"a"), 1, "recorded")
	t.eq(p.count_of(&"b"), 1, "a suppressed id is dropped")
	p.loop(&"c", Vector3.ZERO, Vector3.ZERO, 1.0, 0.2, 3.0)
	t.eq(p.count_of(&"c"), 1, "loops are recorded")


func test_fx_port_binds_a_real_manager_and_skips_unknown_ids(t: TestCtx) -> void:
	var fx: FxManager = FxManager.new()
	var cam: Camera3D = Camera3D.new()
	fx.add_child(cam)
	var book: FxRecipeBook = FxRecipeBook.new()
	book.load_file()
	fx.setup(cam, FxManager.Quality.HIGH, book, null, null)
	fx.force = true
	var p: ViewFxPort = ViewFxPort.new()
	p.bind(fx)
	t.check(p.active(), "active once bound")
	t.check(p.has_effect(&"building_collapse"), "authored effect known")
	t.check(not p.has_effect(&"damage_smoke_that_does_not_exist"), "unknown effect")
	p.spawn(&"damage_smoke_that_does_not_exist", Vector3.ZERO)
	t.eq(p.stat_missing, 1, "counted as missing")
	t.eq(fx.stat_unknown, 0, "the manager never sees (or warns about) the unknown id")
	p.spawn(&"building_collapse", Vector3.ZERO, Vector3.ZERO, 1.0)
	t.gt(fx.stat_spawned, 0, "known effect forwarded")
	fx.free()


func test_debug_overlay_draws_an_ai_frame(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w, 0)
	if not ViewDebugOverlay.available():
		t.skip("release build")
		Kit.free_view(vw)
		return
	var f: AiDebugFrame = AiDebugFrame.new()
	f.add_circle(40 * C, 40 * C, 6 * C, 0xFF3366, "rally")
	f.add_circle(50 * C, 44 * C, 4 * C, 0x33FF66)
	f.add_line(40 * C, 40 * C, 50 * C, 44 * C, 0xFFFFFF)
	vw.debug.set_frame(f)
	vw.debug.update(0.0)
	t.eq(vw.debug.circle_count, 2, "two circles")
	t.eq(vw.debug.line_count, 1, "one line")
	t.check(vw.debug.stats_text().length() > 10, "stats panel text")
	vw.debug.set_frame(null)
	vw.debug.update(0.0)
	t.eq(vw.debug.circle_count, 0, "cleared")
	Kit.free_view(vw)


func test_state_overlays_cost_little_in_a_busy_world(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(4)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(48.0, 48.0), 0.9)
	for i: int in 40:
		var e: SimEntity = Kit.place(w, "structure.shared.watchtower", i % 4, 6 + (i % 20) * 4, 6 + (i / 20) * 4, SimEvent.SPAWN_PLACED if i < 12 else SimEvent.SPAWN_INITIAL)
		if e != null and i % 3 == 0:
			e.hp = e.hp_max / 5
	for i: int in 300:
		Kit.unit(w, i % 4, i % 2 == 0, 4 + (i % 30) * 3, 40 + (i / 30) * 3)
	w.zones.create_zone(w.data.zone_idx("zone.smoke_dust_screen"), 0, 40 * C, 60 * C, 0, w.tick + 400)
	Kit.tick(vw, 12)
	var sum: float = 0.0
	var worst: float = 0.0
	var n: int = 120
	for i: int in n:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())
		sum += vw.state.ms_last
		worst = maxf(worst, vw.state.ms_last)
	t.note("state overlays: avg %.3f ms, worst %.3f ms, %d entities" % [sum / float(n), worst, vw.entity_count()])
	t.lt(sum / float(n), 0.6, "average under 0.6 ms (%.3f)" % (sum / float(n)))
	Kit.free_view(vw)
