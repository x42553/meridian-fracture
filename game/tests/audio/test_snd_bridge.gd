extends RefCounted
## Sim bridge over hand-built event batches (the REAL kernel layout and codes) with a stub world reader.

const C = preload("res://src/audio/snd_event_codes.gd")


func _unit_def(id: String) -> int:
	return SndTestKit.game_data().unit_idx(id)


func _fire(shooter: int, arch: int, x: int, y: int, tick: int = 100) -> PackedInt32Array:
	return SndTestKit.rec(C.EV_FIRE, tick, x, y, shooter, arch, 0, -1, x, y)


func _rig_with_shooter(owner: int, x: int, y: int) -> SndTestKit.Rig:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 1: SndWorldReader.REL_ENEMY, 2: SndWorldReader.REL_ALLY}
	rig.reader.add_entity(7, SimEntity.Kind.UNIT, _unit_def("unit.napc.rifle_squad"), owner, x, y)
	rig.reader.add_entity(8, SimEntity.Kind.UNIT, _unit_def("unit.napc.rifle_squad"), owner, x, y)
	return rig


func test_units(t: TestCtx) -> void:
	var v: Vector3 = SndUnits.to_world(1024, 2048, 1.5)
	t.near(v.x, 3.0, 0.0001, "x metres")
	t.near(v.y, 1.5, 0.0001, "height")
	t.near(v.z, 6.0, 0.0001, "z metres")
	t.eq(SndUnits.cell_of(1024), 1, "cell x")
	t.eq(SndUnits.cell_of(2048), 2, "cell y")


func test_fog(t: TestCtx) -> void:
	var x: int = 20 * 1024
	var y: int = 20 * 1024
	# enemy fire in an invisible cell: culled
	var rig: SndTestKit.Rig = _rig_with_shooter(1, x, y)
	rig.run([_fire(7, 0, x, y)])
	t.eq(rig.pool.stats.starts, 0, "enemy shot in the fog does not start")
	t.eq(rig.bridge.stats.get_count(&"cull_fog"), 1, "cull_fog counted")
	# visible cell: plays
	rig = _rig_with_shooter(1, x, y)
	rig.reader.show_cell(20, 20)
	rig.run([_fire(7, 0, x, y)])
	t.eq(rig.pool.stats.starts, 1, "visible cell starts")
	# own and allied fire in an invisible cell: plays
	rig = _rig_with_shooter(0, x, y)
	rig.run([_fire(7, 0, x, y)])
	t.eq(rig.pool.stats.starts, 1, "own shot in the fog plays")
	rig = _rig_with_shooter(2, x, y)
	rig.run([_fire(7, 0, x, y)])
	t.eq(rig.pool.stats.starts, 1, "allied shot in the fog plays")
	# omniscient
	rig = _rig_with_shooter(1, x, y)
	rig.reader.omniscient = true
	rig.run([_fire(7, 0, x, y)])
	t.eq(rig.pool.stats.starts, 1, "omniscient hears everything")


func test_muffled_fog_rule(t: TestCtx) -> void:
	# artillery is MUFFLED: audible only within 300 m of the focus, with -9 dB
	var arch: int = 9  # artillery_shell
	var near_x: int = int(100.0 / SndConfig.M_PER_UNIT)
	var rig: SndTestKit.Rig = _rig_with_shooter(1, near_x, 0)
	rig.run([_fire(7, arch, near_x, 0)])
	t.eq(rig.pool.stats.starts, 1, "muffled event within 300 m starts")
	t.check(rig.bridge.decision_log[0].contains(" -9.0 "), "with -9 dB: %s" % rig.bridge.decision_log[0])
	var far_x: int = int(400.0 / SndConfig.M_PER_UNIT)
	rig = _rig_with_shooter(1, far_x, 0)
	rig.run([_fire(7, arch, far_x, 0)])
	t.eq(rig.pool.stats.starts, 0, "beyond 300 m it is dropped")


func test_per_source_throttle(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = _rig_with_shooter(0, 10 * 1024, 0)
	rig.run([_fire(7, 0, 10 * 1024, 0), _fire(7, 0, 10 * 1024, 0)])
	t.eq(rig.pool.stats.starts, 1, "two shots from one entity in one instant: one voice")
	rig = _rig_with_shooter(0, 10 * 1024, 0)
	rig.run([_fire(7, 0, 10 * 1024, 0), _fire(8, 0, 10 * 1024, 0)])
	# the event-level 35 ms interval also applies to small_arms; use a different archetype pair to isolate the source rule
	t.ge(rig.pool.stats.starts, 1, "two sources")
	rig = _rig_with_shooter(0, 10 * 1024, 0)
	rig.run([_fire(7, 3, 10 * 1024, 0)])
	rig.clock.advance(20)
	rig.run([_fire(7, 3, 10 * 1024, 0)])
	t.eq(rig.pool.stats.starts, 1, "20 ms later from the same entity is throttled")


func test_rank_cap(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	rig.reader.everything_visible = true
	# 100 explosions at distinct places so nothing dedupes: exactly max_starts_per_frame start
	var recs: Array = []
	for i: int in 100:
		recs.append(SndTestKit.rec(C.EV_IMPACT, 100, (i % 10) * 4096 + 512, (i / 10) * 4096 + 512, 0, -1, 0, 700 + i * 20, 0, 0))
	rig.reader.dtypes = {0: 2}
	rig.run(recs)
	t.eq(rig.bridge.decision_log.size(), 24, "exactly 24 sounds are submitted to the pool")
	t.eq(rig.bridge.stats.get_count(&"cull_frame"), 76, "the other 76 are dropped for the frame")
	# the submitted ones are the 24 with the highest priority + 0.5 * est_db: the biggest explosions
	var sizes: PackedStringArray = PackedStringArray()
	for line: String in rig.bridge.decision_log:
		sizes.append(line.get_slice("@", 0))
	t.check(not sizes.has("snd.explosion.small"), "small explosions lose against larger ones: %s" % str(sizes.slice(0, 3)))


func test_dedupe(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.dtypes = {5: 2}
	var x: int = 30 * 1024
	# EV_IMPACT (explosive warhead) and EV_DEATH (vehicle) at the same spot and tick: one boom
	var tank: int = _unit_def("unit.napc.bastion_heavy_tank")
	var death: PackedInt32Array = SndTestKit.rec(C.EV_DEATH, 100, x, x, 9, tank, C.DK_VEHICLE | (0 << 4) | (65 << 8), 0, (1 + 1) << 8, 0)
	var impact: PackedInt32Array = SndTestKit.rec(C.EV_IMPACT, 100, x + 100, x + 100, 5, -1, 0, 1200, 300, 1)
	rig.run([impact, death])
	var booms: int = 0
	for e: String in rig.events_played():
		if e.begins_with("snd.explosion"):
			booms += 1
	t.eq(booms, 1, "one explosion voice (either order)")
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.dtypes = {5: 2}
	rig.run([death, impact])
	booms = 0
	for e2: String in rig.events_played():
		if e2.begins_with("snd.explosion"):
			booms += 1
	t.eq(booms, 1, "other order too")
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.dtypes = {5: 2}
	var far_impact: PackedInt32Array = SndTestKit.rec(C.EV_IMPACT, 100, x + 4096, x + 4096, 5, -1, 0, 1200, 300, 1)
	rig.run([far_impact, death])
	booms = 0
	for e3: String in rig.events_played():
		if e3.begins_with("snd.explosion"):
			booms += 1
	t.eq(booms, 2, "different cells: two voices")


func test_owner_fallback(t: TestCtx) -> void:
	# the shooter no longer resolves: treated as ENEMY (fog decides); flavoured from the shooter's owner is unknown -> default
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.run([_fire(99, 0, 10 * 1024, 0)])
	t.eq(rig.pool.stats.starts, 0, "unknown shooter in the fog is dropped")
	rig.reader.show_cell(10, 0)
	rig.run([_fire(99, 0, 10 * 1024, 0)])
	t.eq(rig.pool.stats.starts, 1, "visible: plays with the default variants")


func test_flavour_from_the_shooters_faction(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = _rig_with_shooter(0, 10 * 1024, 0)
	rig.run([_fire(7, 0, 10 * 1024, 0)])
	t.check(rig.bridge.decision_log[0].contains(" napc "), "napc shooter -> napc flavour: %s" % rig.bridge.decision_log[0])


func test_tank_cannon_variant_from_the_profile(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	rig.reader.add_entity(5, SimEntity.Kind.UNIT, _unit_def("unit.napc.bastion_heavy_tank"), 0, 10 * 1024, 0)
	rig.run([_fire(5, 3, 10 * 1024, 0)])
	t.check(rig.events_played()[0] == "snd.weapon.tank_cannon_heavy", "siege_ap profile -> heavy cannon: %s" % str(rig.events_played()))


func test_damage_filter(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	var inf: int = _unit_def("unit.napc.rifle_squad")
	rig.reader.add_entity(10, SimEntity.Kind.UNIT, inf, 1, 10 * 1024, 0)
	# splash flag: silent
	rig.run([SndTestKit.rec(C.EV_HIT, 100, 10 * 1024, 0, 10, 20, 3, 0 | (SndEventCodes.DC_SPLASH << 8), 100, 200)])
	t.eq(rig.pool.stats.starts, 0, "splash damage is covered by the explosion")
	# bullet vs infantry -> flesh
	rig.run([SndTestKit.rec(C.EV_HIT, 100, 10 * 1024, 0, 10, 20, 3, 0, 100, 200)])
	t.eq(rig.events_played(), PackedStringArray(["snd.impact.bullet.flesh"]), "bullet vs infantry is flesh")
	# a second hit on the same target within 60 ms: throttled
	rig.clock.advance(30)
	rig.run([SndTestKit.rec(C.EV_HIT, 100, 10 * 1024, 0, 10, 20, 3, 0, 100, 200)])
	t.eq(rig.pool.stats.starts, 1, "second hit within 60 ms is throttled")
	# removed target -> metal
	var rig2: SndTestKit.Rig = SndTestKit.Rig.new()
	rig2.reader.everything_visible = true
	rig2.run([SndTestKit.rec(C.EV_HIT, 100, 10 * 1024, 0, 55, 20, 3, 0, 100, 200)])
	t.eq(rig2.events_played(), PackedStringArray(["snd.impact.bullet.metal"]), "removed target falls back to metal")
	# he damage is not voiced
	var rig3: SndTestKit.Rig = SndTestKit.Rig.new()
	rig3.reader.everything_visible = true
	rig3.run([SndTestKit.rec(C.EV_HIT, 100, 10 * 1024, 0, 55, 20, 3, 2, 100, 200)])
	t.eq(rig3.pool.stats.starts, 0, "he damage is voiced by the explosion")


func test_impact_tables(t: TestCtx) -> void:
	t.eq(SndUnits.size_of_radius(0), SndUnits.Size.TINY, "0 -> tiny")
	t.eq(SndUnits.size_of_radius(819), SndUnits.Size.SMALL, "819 -> small")
	t.eq(SndUnits.size_of_radius(820), SndUnits.Size.MEDIUM, "820 -> medium")
	t.eq(SndUnits.size_of_radius(1536), SndUnits.Size.MEDIUM, "1536 -> medium")
	t.eq(SndUnits.size_of_radius(2560), SndUnits.Size.LARGE, "2560 -> large")
	t.eq(SndUnits.size_of_radius(3000), SndUnits.Size.HUGE, "3000 -> huge")
	t.eq(SndUnits.material_of_armor(DefEnums.ArmorClass.INFANTRY), SndUnits.Mat.FLESH, "infantry")
	t.eq(SndUnits.material_of_armor(DefEnums.ArmorClass.MEDIUM_ARMOR), SndUnits.Mat.METAL, "medium armor")
	t.eq(SndUnits.material_of_armor(DefEnums.ArmorClass.BUILDING_HEAVY), SndUnits.Mat.CONCRETE, "heavy building")
	t.eq(SndUnits.material_of_armor(DefEnums.ArmorClass.FORTRESS), SndUnits.Mat.CONCRETE, "fortress")
	for a: int in DefEnums.ArmorClass.COUNT:
		t.check(SndUnits.material_of_armor(a) >= 0, "armor %d has a material" % a)
	var mix: SndMixConfig = (SndTestKit.real()["store"] as SndDataStore).mix
	t.eq(mix.terrain_material.size(), 15, "15 terrain materials")


func test_state_table(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	var turret_def: int = -1
	var data: GameData = SndTestKit.game_data()
	for i: int in data.structures.size():
		if not data.structures[i].weapons.is_empty() and rig.bank.struct_tags[i] & SndSoundBank.TAG_DEFENSE:
			turret_def = i
			break
	t.ge(turret_def, 0, "a defence structure exists")
	rig.reader.add_entity(30, SimEntity.Kind.STRUCTURE, turret_def, 0, 12 * 1024, 12 * 1024)
	# WEAPON_LOCK offline by EMP -> defense_offline + systems_disabled
	rig.run([SndTestKit.rec(C.EV_WEAPON_LOCK, 100, 12 * 1024, 12 * 1024, 30, 1, 0)])
	t.eq(rig.events_played(), PackedStringArray(["snd.struct.defense_offline"]), "defense offline sound")
	t.check(rig.bridge.lines_said.has("systems_disabled"), "line systems_disabled")
	# power loss: line once per 30 s
	rig.clock.advance(3000)
	rig.bridge.lines_said = PackedStringArray()
	rig.run([SndTestKit.rec(C.EV_WEAPON_LOCK, 100, 12 * 1024, 12 * 1024, 30, 1, 2)])
	t.check(rig.bridge.lines_said.has("defenses_offline"), "line defenses_offline")
	# selling
	rig.reader.rel[0] = SndWorldReader.REL_SELF
	var rig2: SndTestKit.Rig = SndTestKit.Rig.new()
	rig2.reader.everything_visible = true
	rig2.run([SndTestKit.rec(C.EVT_STRUCTURE_SELLING, 100, 5 * 1024, 5 * 1024, 0, 30, 400)])
	t.eq(rig2.events_played(), PackedStringArray(["snd.struct.sell"]), "selling")
	# EMP hit
	var rig3: SndTestKit.Rig = SndTestKit.Rig.new()
	rig3.reader.everything_visible = true
	rig3.run([SndTestKit.rec(C.EV_EMP, 100, 5 * 1024, 5 * 1024, 30, 100, 0, 1, 0)])
	t.eq(rig3.events_played(), PackedStringArray(["snd.emp.hit"]), "emp hit")


func test_announcer_lines_and_economy(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	rig.run([
		SndTestKit.rec(C.EVT_POWER_SHORTAGE, 100, 0, 0, 0, 50, 90),
		SndTestKit.rec(C.EVT_STRUCTURE_READY, 100, 0, 0, 0, 3),
		SndTestKit.rec(C.EVT_INSUFFICIENT_FUNDS, 100, 0, 0, 0, 12, 0),
		SndTestKit.rec(C.EVT_POWER_SHORTAGE, 100, 0, 0, 1, 50, 90),  # not the viewer
	])
	t.check(rig.bridge.lines_said.has("low_power"), "own power shortage -> low_power")
	t.check(rig.bridge.lines_said.has("construction_complete"), "structure ready")
	t.check(rig.bridge.lines_said.has("insufficient_funds"), "funds")
	t.eq(rig.bridge.lines_said.count("low_power"), 1, "other player's shortage is silent")
	var ev: PackedStringArray = rig.events_played()
	t.check(ev.has("snd.struct.power_down"), "power_down sound: %s" % str(ev))
	t.check(ev.has("snd.ui.build_ready"), "build_ready sound")
	t.check(ev.has("snd.ui.error"), "error sound")


func test_deaths_and_losses(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 1: SndWorldReader.REL_ENEMY}
	var inf: int = _unit_def("unit.napc.rifle_squad")
	var own_death: PackedInt32Array = SndTestKit.rec(C.EV_DEATH, 100, 9 * 1024, 9 * 1024, 40, inf, C.DK_INFANTRY | (64 << 8), 0, ((0 + 1) << 8), 0)
	var enemy_death: PackedInt32Array = SndTestKit.rec(C.EV_DEATH, 100, 9 * 1024, 9 * 1024, 41, inf, C.DK_INFANTRY | (64 << 8), 0, ((1 + 1) << 8), 0)
	rig.run([own_death, enemy_death])
	t.check(rig.bridge.lines_said.has("unit_lost"), "own unit lost line")
	t.eq(rig.bridge.lines_said.count("unit_lost"), 1, "only for own")
	t.check(rig.events_played().has("snd.death.infantry"), "infantry death sound")
	t.gt(rig.meter.heat, 0.0, "deaths feed the combat meter")


func test_warning(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 1: SndWorldReader.REL_ENEMY}
	rig.reader.team_cells = [Vector3i(50 * 1024, 50 * 1024, 0)]
	rig.reader.stub_tick = 100
	var data: GameData = SndTestKit.game_data()
	var sw: int = 0
	var wt: int = rig.bank.sw_warning_ticks[sw]
	# hostile warning with an own unit inside extent + 3 cells
	var warn: PackedInt32Array = SndTestKit.rec(C.EVT_WARNING, 100, 50 * 1024, 50 * 1024, 1, 1, C.WK_SUPER, sw, 50 * 1024, 50 * 1024)
	rig.run([warn])
	t.check(rig.bridge.lines_said.has("sw_launch_detected"), "line sw_launch_detected")
	t.eq(rig.countdown.active_count(), 1, "countdown registered")
	t.check(rig.countdown.siren_playing(), "siren plays for the affected viewer")
	# the unit leaves: the siren goes within one refresh
	rig.reader.team_cells = []
	rig.countdown.update(101.0, 0.6)
	t.check(not rig.pool.is_active(int((rig.countdown._w[1 * 64 + sw] as Dictionary)["siren"])), "siren stops when nobody is affected")
	# cancel
	rig.run([SndTestKit.rec(C.EVT_SW_CANCELLED, 105, 50 * 1024, 50 * 1024, 1, sw, 1, 3)])
	t.eq(rig.countdown.active_count(), 0, "cancel ends the warning")
	# own launch: line only, no siren
	var rig2: SndTestKit.Rig = SndTestKit.Rig.new()
	rig2.reader.rel = {0: SndWorldReader.REL_SELF}
	rig2.reader.team_cells = [Vector3i(50 * 1024, 50 * 1024, 0)]
	rig2.run([SndTestKit.rec(C.EVT_POWER_ACTIVATED, 100, 50 * 1024, 50 * 1024, 0, C.SLOT_SW, sw, 50 * 1024, 50 * 1024, 0)])
	t.check(rig2.bridge.lines_said.has("sw_launched"), "own launch -> sw_launched")
	t.eq(rig2.countdown.active_count(), 0, "no siren for a friendly launch")
	t.gt(wt, 0, "superweapon warning ticks known (%d)" % wt)
	t.note("data has %d superweapons" % data.superweapons.size())


func test_countdown_ticks(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.team_cells = [Vector3i(0, 0, 0)]
	rig.countdown.on_warning(1, 0, 0, 0, 300, 8192, 0, true)
	var before: int = rig.pool.stats.starts
	var beeps: int = 0
	var last: int = before
	var tick: float = 200.0
	while tick < 305.0:
		rig.clock.advance(50)
		rig.countdown.update(tick, 0.05)
		if rig.pool.stats.starts > last:
			beeps += rig.pool.stats.starts - last
			last = rig.pool.stats.starts
		tick += 1.0
	# siren (already counted before), beeps at T-5..T-1 and the final tone: 6 starts after the siren
	t.eq(beeps, 6, "five countdown beeps and the final tone")
	t.eq(rig.countdown.active_count(), 0, "warning retired at exec_tick")


func test_catch_up_batches(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	var recs: Array = []
	# 2000 records: cosmetic explosions from the whole batch plus an announcer-class record at the very front
	recs.append(SndTestKit.rec(C.EVT_POWER_SHORTAGE, 60, 0, 0, 0, 10, 20))
	for i: int in 1999:
		recs.append(SndTestKit.rec(C.EV_IMPACT, 60 + i / 50, (i % 50) * 3000, (i / 50) * 3000, 0, -1, 0, 900, 0, 0))
	rig.reader.dtypes = {0: 2}
	var t0: int = Time.get_ticks_usec()
	rig.run(recs)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	t.check(rig.bridge.lines_said.has("low_power"), "the announcer-class record at the front of a huge batch is still processed")
	t.ge(rig.bridge.stats.get_count(&"cull_scan"), 2000 - 512 - 1, "older cosmetic records were skipped")
	t.lt(ms, 60.0, "process() of a 2000-record batch: %.1f ms" % ms)


func test_unknown_records_are_ignored(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.run([SndTestKit.rec(0x7E, 1, 0, 0), SndTestKit.rec(9, 1, 0, 0), SndTestKit.rec(2, 1, 0, 0, 5, 0, 0, 0)])
	t.eq(rig.pool.stats.starts, 0, "nothing started")
	t.eq(rig.pool.stats.culls, 0, "no counters either")


func test_match_end_callback(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	var got: Array[int] = []
	rig.bridge.on_match_end = func(r: int) -> void: got.append(r)
	rig.run([SndTestKit.rec(C.MATCH_END, 200, 0, 0, 1, 0, 200)])  # winner team 1 == viewer team 1 (stub)
	rig.run([SndTestKit.rec(C.MATCH_END, 200, 0, 0, 2, 0, 200)])
	rig.run([SndTestKit.rec(C.MATCH_END, 200, 0, 0, -1, 2, 200)])
	t.eq(got, [SndMatchConfig.RESULT_VICTORY, SndMatchConfig.RESULT_DEFEAT, SndMatchConfig.RESULT_DRAW], "victory / defeat / draw")


func test_economy_cash_and_production(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	var tank: int = _unit_def("unit.napc.bastion_heavy_tank")
	rig.reader.add_entity(60, SimEntity.Kind.STRUCTURE, 0, 0, 5 * 1024, 5 * 1024)
	rig.run([
		SndTestKit.rec(C.EVT_CREDITS_GAINED, 100, 5 * 1024, 5 * 1024, 0, 700, 5 * 1024, 5 * 1024),
		SndTestKit.rec(C.EVT_UNIT_PRODUCED, 100, 5 * 1024, 5 * 1024, 0, 77, tank, 60),
	])
	var ev: PackedStringArray = rig.events_played()
	t.check(ev.has("snd.eco.cash_big"), "big payout: %s" % str(ev))
	t.check(ev.has("snd.struct.unit_out.vehicle"), "unit out class: %s" % str(ev))
	t.check(rig.bridge.lines_said.has("unit_ready"), "unit_ready line")


func test_structure_lifecycle_sounds(t: TestCtx) -> void:
	var data: GameData = SndTestKit.game_data()
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	rig.reader.add_entity(70, SimEntity.Kind.STRUCTURE, data.structure_idx("structure.shared.generator"), 0, 10 * 1024, 10 * 1024)
	rig.run([
		SndTestKit.rec(C.EVT_STRUCTURE_PLACED, 100, 10 * 1024, 10 * 1024, 0, 70, data.structure_idx("structure.shared.generator")),
		SndTestKit.rec(C.EVT_STRUCTURE_PLACED, 100, 20 * 1024, 20 * 1024, 0, 71, data.structure_idx("structure.napc.atlas_kinetic_array")),
		SndTestKit.rec(C.EVT_STRUCTURE_PLACED, 100, 30 * 1024, 30 * 1024, 0, 72, data.structure_idx("structure.napc.bulwark_cannon")),
		SndTestKit.rec(C.EVT_STRUCTURE_PLACED, 100, 40 * 1024, 40 * 1024, 0, 73, data.structure_idx("structure.shared.headquarters")),
		SndTestKit.rec(C.EVT_HQ_DEPLOYED, 100, 40 * 1024, 40 * 1024, 0, 73),
		SndTestKit.rec(C.EVT_STRUCTURE_CAPTURED, 100, 50 * 1024, 50 * 1024, 0, 74, 1),
		SndTestKit.rec(C.EVT_STRUCTURE_CAPTURED, 100, 50 * 1024, 50 * 1024, 1, 75, 0),
	])
	var ev: PackedStringArray = rig.events_played()
	t.check(ev.has("snd.struct.online.generator"), "generator online: %s" % str(ev))
	t.check(ev.has("snd.struct.online.superweapon"), "launcher online")
	t.check(ev.has("snd.struct.online.adv_defense"), "advanced defence online")
	t.check(not ev.has("snd.struct.online.hq"), "HQ placement is voiced by the deploy event")
	t.check(ev.has("snd.struct.hq_deploy"), "hq deploy")
	t.check(ev.has("snd.struct.captured"), "captured by us")
	t.check(ev.has("snd.alarm.base_attack"), "captured from us raises the alarm")
	t.check(rig.bridge.lines_said.has("building_captured") and rig.bridge.lines_said.has("structure_captured"), "capture lines")


func test_projectile_flight_sounds(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	var lm: SndLoopManager = rig.enable_loops()
	# missile (arch 6 = at_missile): path voice from launch to end, stopped by the impact with the same serial
	rig.run([SndTestKit.rec(C.EV_PROJ_SPAWN, 100, 10 * 1024, 0, 900, 6, 0 | (4 << 4) | (40 << 16), -1, 30 * 1024, 0)])
	t.eq(lm.path_count(), 1, "missile path voice")
	rig.run([SndTestKit.rec(C.EV_IMPACT, 140, 30 * 1024, 0, 0, 900, 1, 300, 100, 0)])
	t.eq(lm.path_count(), 0, "impact with the serial ends it")
	# artillery arc (arch 9) with a long flight: a shell whistle is scheduled
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.run([SndTestKit.rec(C.EV_PROJ_SPAWN, 100, 10 * 1024, 0, 901, 9, 0 | (3 << 4) | (60 << 16), -1, 40 * 1024, 0)])
	t.check(rig.bridge.decision_log.size() >= 1 and rig.bridge.decision_log[0].begins_with("snd.proj.shell_whistle"), "shell whistle scheduled: %s" % str(rig.bridge.decision_log))
	# short arc flights get none
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.run([SndTestKit.rec(C.EV_PROJ_SPAWN, 100, 10 * 1024, 0, 902, 9, 0 | (3 << 4) | (10 << 16), -1, 12 * 1024, 0)])
	t.eq(rig.bridge.decision_log.size(), 0, "no whistle for a short flight")
	# bomb whistle
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.run([SndTestKit.rec(C.EV_PROJ_SPAWN, 100, 10 * 1024, 0, 903, 17, 0 | (3 << 4) | (30 << 16), -1, 11 * 1024, 0)])
	t.check(rig.bridge.decision_log.size() == 1 and rig.bridge.decision_log[0].begins_with("snd.proj.bomb_whistle"), "bomb whistle")


func test_beam_events_bind_a_loop(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF}
	var lm: SndLoopManager = rig.enable_loops()
	rig.reader.add_entity(21, SimEntity.Kind.UNIT, _unit_def("unit.napc.bastion_heavy_tank"), 0, 15 * 1024, 0)
	rig.run([SndTestKit.rec(C.EV_BEAM_START, 100, 15 * 1024, 0, 21, 13, 0, 5, 60)])
	t.eq(lm.beam_count(), 1, "beam loop while the beam burns")
	rig.run([SndTestKit.rec(C.EV_BEAM_END, 140, 15 * 1024, 0, 21, 3, 0)])
	t.eq(lm.beam_count(), 0, "beam end stops it")
	t.gt(rig.meter.heat, 0.0, "beam start feeds the meter")


func test_alerts_and_offscreen_rule(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 2: SndWorldReader.REL_ALLY}
	# structure under attack: the alert line + alarm + urgent
	rig.run([SndTestKit.rec(C.EV_ATTACK_ALERT, 100, 5 * 1024, 5 * 1024, 0, 60, 1, 1)])
	t.check(rig.bridge.lines_said.has("base_under_attack"), "base_under_attack")
	t.check(rig.events_played().has("snd.alarm.base_attack"), "alarm cue")
	t.check(rig.meter.urgent or rig.meter.heat > 0.0, "music is pushed")
	# a unit under attack ON screen (near the focus) is silent; off screen speaks
	rig = SndTestKit.Rig.new()
	rig.reader.everything_visible = true
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 2: SndWorldReader.REL_ALLY}
	rig.run([SndTestKit.rec(C.EV_ATTACK_ALERT, 100, 5 * 1024, 5 * 1024, 0, 60, 1, 0)])
	t.check(not rig.bridge.lines_said.has("unit_under_attack"), "on-screen unit attack is silent")
	var far: int = int(200.0 / SndConfig.M_PER_UNIT)
	rig.run([SndTestKit.rec(C.EV_ATTACK_ALERT, 100, far, far, 0, 60, 1, 0)])
	t.check(rig.bridge.lines_said.has("unit_under_attack"), "off-screen unit attack speaks")
	# an ally attacked off screen
	rig.run([SndTestKit.rec(C.EV_ATTACK_ALERT, 100, far, far, 2, 61, 1, 0)])
	t.check(rig.bridge.lines_said.has("ally_under_attack"), "ally under attack")


func test_charge_hum(t: TestCtx) -> void:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.countdown.set_charge(0.5, false, "aurora")
	t.eq(rig.pool.active_2d(), 1, "the own charge hum plays (flat)")
	var h: int = rig.countdown._charge_handle
	t.check(rig.pool.is_active(h), "handle active")
	rig.countdown.set_charge(0.9, true, "aurora")
	t.eq(rig.countdown._charge_handle, h, "the same voice keeps playing under a power shortage")
	rig.countdown.stop_charge()
	for i: int in 40:
		rig.pool.update(1.0 / 60.0)
	t.check(not rig.pool.is_active(h), "stopped when ready (after the fade)")
	rig.countdown.set_charge(0.5, false, "atlas")
	t.eq(rig.pool.active_2d(), 0, "a superweapon without a charge sound stays silent")
