extends RefCounted
## Entity loops (engines, hums, beams, path voices) and the ambience bed targets of audio spec 5.6 / 5.11.


func _rig() -> Array:
	var rig: SndTestKit.Rig = SndTestKit.Rig.new()
	rig.reader.rel = {0: SndWorldReader.REL_SELF, 1: SndWorldReader.REL_ENEMY}
	var lm: SndLoopManager = SndLoopManager.new()
	lm.setup(rig.reader, rig.bank, rig.pool, rig.mix, rig.map)
	lm.set_view(Vector3.ZERO, 1.0)
	return [rig, lm]


func _tank_def() -> int:
	return SndTestKit.game_data().unit_idx("unit.napc.bastion_heavy_tank")


func test_moving_unit_gets_an_engine_loop(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	var e: SimEntity = rig.reader.add_entity(5, SimEntity.Kind.UNIT, _tank_def(), 0, 20 * 1024, 0, 0, SimFlags.F_MOVING)
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 1, "one engine loop")
	t.eq(rig.pool.active_3d(), 1, "one positional voice")
	e.flags = 0
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 0, "stopped when the unit stops")
	# fade-out completes
	for i: int in 30:
		rig.pool.update(1.0 / 60.0)
	t.eq(rig.pool.active_3d(), 0, "voice retired after the fade")


func test_position_chases_the_sim_position(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	var e: SimEntity = rig.reader.add_entity(5, SimEntity.Kind.UNIT, _tank_def(), 0, 20 * 1024, 0, 0, SimFlags.F_MOVING)
	lm.update(0.3, rig.clock.ms)
	e.x = 30 * 1024
	for i: int in 60:
		lm.update(1.0 / 60.0, rig.clock.ms)
	var rec: SndLoopManager.Rec = lm._ent.values()[0]
	t.near(rec.cur.x, 30.0 * 3.0, 0.5, "smoothed position reached the new sim position (%.2f)" % rec.cur.x)
	t.gt(rec.speed, 0.0, "speed is tracked for the pitch")


func test_budget_keeps_the_loudest(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	for i: int in 30:
		rig.reader.add_entity(100 + i, SimEntity.Kind.UNIT, _tank_def(), 0, (5 + i) * 1024, 0, 0, SimFlags.F_MOVING)
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), rig.mix.loops_budget, "budget %d" % rig.mix.loops_budget)
	var ids: Array = []
	for r: Variant in lm._ent.values():
		ids.append((r as SndLoopManager.Rec).entity_id)
	ids.sort()
	t.eq(ids[0], 100, "the nearest is in")
	t.check(not ids.has(129), "the farthest is out")


func test_fog_hides_enemy_loops(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	rig.reader.add_entity(9, SimEntity.Kind.UNIT, _tank_def(), 1, 20 * 1024, 0, 0, SimFlags.F_MOVING)
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 0, "an enemy in the fog makes no engine noise")
	rig.reader.show_cell(20, 0)
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 1, "visible: it does")


func test_structure_hum_needs_power(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	var gen: int = SndTestKit.game_data().structure_idx("structure.shared.generator")
	var e: SimEntity = rig.reader.add_entity(40, SimEntity.Kind.STRUCTURE, gen, 0, 10 * 1024, 0, 0, 0)
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 0, "unpowered: silent")
	e.flags = SimFlags.F_POWERED
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 1, "powered: hums")
	e.flags = SimFlags.F_POWERED | SimFlags.F_SELLING
	lm.update(0.3, rig.clock.ms)
	t.eq(lm.active_loops(), 0, "selling: silent")


func test_beam_and_path_voices(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	rig.reader.add_entity(21, SimEntity.Kind.UNIT, _tank_def(), 0, 15 * 1024, 0)
	var beam: SndEventDef = rig.bank.fire_def(13, "")
	t.not_null(beam, "beam event")
	lm.start_beam(21, 13, beam, &"napc")
	t.eq(lm.beam_count(), 1, "beam loop bound")
	lm.stop_beams_of(21)
	t.eq(lm.beam_count(), 0, "beam loop stopped")
	var missile: SndEventDef = rig.map.get_def(&"snd.proj.missile")
	lm.add_path_voice(77, missile, Vector3(0, 1.5, 0), Vector3(100, 1.5, 0), rig.clock.ms, 2000, &"", 0.0)
	t.eq(lm.path_count(), 1, "path voice")
	rig.clock.advance(1000)
	lm.update(0.016, rig.clock.ms)
	var h: int = int((lm._path[77] as Dictionary)["handle"])
	var slot: SndVoicePool.Slot = rig.pool._slots[h & 127]
	t.near(slot.world_pos.x, 50.0, 1.0, "halfway along the path after half the time (%.1f)" % slot.world_pos.x)
	lm.remove_path_voice(77, 0)
	t.eq(lm.path_count(), 0, "removed")


func test_pitch_follows_speed(t: TestCtx) -> void:
	var pair: Array = _rig()
	var rig: SndTestKit.Rig = pair[0]
	var lm: SndLoopManager = pair[1]
	var e: SimEntity = rig.reader.add_entity(5, SimEntity.Kind.UNIT, _tank_def(), 0, 20 * 1024, 0, 0, SimFlags.F_MOVING)
	lm.update(0.3, rig.clock.ms)
	var rec: SndLoopManager.Rec = lm._ent.values()[0]
	var idle_pitch: float = rec.pitch
	for i: int in 240:
		e.x += 60
		lm.update(1.0 / 60.0, rig.clock.ms)
	t.gt(rec.pitch, idle_pitch, "moving fast raises the engine pitch (%.3f -> %.3f)" % [idle_pitch, rec.pitch])
	t.le(rec.pitch, rig.mix.loops_pitch_hi * rec.base_pitch + 0.001, "bounded by the pitch range")


# ------------------------------------------------------------------ ambience

func _amb(family: int, biome: int) -> SndAmbience:
	var r: Dictionary = SndTestKit.real()
	var a: SndAmbience = SndAmbience.new()
	a.setup(r["store"], r["map"], SndWorldReader.new())
	a._family = family
	a._biome = biome
	return a


func test_ambience_targets(t: TestCtx) -> void:
	var a: SndAmbience = _amb(0, 0)
	var tg: Dictionary = a.compute_targets(0.0, 1.0)
	t.near(tg["wind_open"], 0.0, 0.01, "open temperate: only wind_open at 0 dB")
	t.eq(tg["city_hum"], SndConfig.SILENT_DB, "no city hum")
	t.eq(tg["coast_waves"], SndConfig.SILENT_DB, "no waves without water")
	t.eq(tg["forest"], SndConfig.SILENT_DB, "no forest")
	a.set_fractions(0.0, 0.10)
	t.near(a.compute_targets(0.0, 1.0)["forest"], -13.4, 0.1, "10 % forest -> -13.4 dB")
	a.set_fractions(0.05, 0.0)
	tg = a.compute_targets(0.0, 1.0)
	t.near(tg["coast_waves"], -14.0, 0.1, "5 % water -> waves -14.0")
	t.near(tg["river_flow"], -12.5, 0.1, "5 % water -> river -12.5")
	a.set_fractions(0.25, 0.0)
	t.near(a.compute_targets(0.0, 1.0)["coast_waves"], 0.0, 0.01, "25 % water -> waves 0 dB")
	tg = a.compute_targets(4.0, 1.0)
	t.near(tg["battle_far"], -26.0, 0.1, "far_heat 4 -> battle_far -26 dB")


func test_ambience_family_and_biome(t: TestCtx) -> void:
	var coast: SndAmbience = _amb(2, 0)
	var tg: Dictionary = coast.compute_targets(0.0, 1.0)
	t.near(tg["coast_waves"], -9.0, 0.01, "coast family with no water: waves at the floor")
	t.eq(tg["river_flow"], SndConfig.SILENT_DB, "coast family has no river bed")
	var urban: SndAmbience = _amb(1, 0)
	tg = urban.compute_targets(0.0, 1.0)
	t.near(tg["city_hum"], 0.0, 0.01, "urban: city hum")
	t.near(tg["wind_open"], -9.0, 0.01, "urban: wind -9 dB")
	var desert: SndAmbience = _amb(0, 1)
	tg = desert.compute_targets(0.0, 1.0)
	t.near(tg["wind_open"], 2.0, 0.01, "desert wind +2 dB")
	t.near(desert.wind_pitch(), 1.06, 0.001, "desert pitch 1.06")
	desert.set_fractions(0.0, 0.33)
	t.near(desert.compute_targets(0.0, 1.0)["forest"], -3.0 - 8.0, 0.1, "desert forest -8 dB extra")
	var wide: SndAmbience = _amb(0, 0)
	wide.set_fractions(0.0, 0.33)
	t.near(wide.compute_targets(0.0, 1.5)["forest"], -3.0 - 3.0, 0.1, "detail beds lose 6 dB per zoom unit above 1")


func test_ambience_grid_histogram(t: TestCtx) -> void:
	# an 16x16 map, left half water: the fractions near the water edge follow the summary grid
	var r: Dictionary = SndTestKit.real()
	var reader: SndTestKit.StubReader = SndTestKit.StubReader.new()
	var a: SndAmbience = SndAmbience.new()
	a.setup(r["store"], r["map"], reader)
	a._grid_w = 2
	a._grid_h = 2
	a._water_grid = PackedByteArray([255, 0, 255, 0])
	a._forest_grid = PackedByteArray([0, 0, 0, 255])
	a.histogram(Vector3(12.0, 0.0, 12.0), 1.0)
	t.gt(a.f_water, 0.2, "water on the left is seen (%.2f)" % a.f_water)
	a.histogram(Vector3(36.0, 0.0, 36.0), 1.0)
	t.gt(a.f_forest, 0.2, "forest bottom-right (%.2f)" % a.f_forest)
