extends RefCounted
## SimWorld construction, stepping, checkpoints, dumps and opts (sim_core 3.4.1 / 3.4.2 / 3.4.8, 10.1 test_sim_world).

const K := preload("res://tests/support/sim_test_kit.gd")


func test_construction(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	t.not_null(w, "world builds")
	t.eq(w.entities.size(), 2, "two HQs")
	var hq: int = w.data.structure_idx(DefTestKit.S_HQ)
	t.eq([w.get_entity(1).kind, w.get_entity(1).def_idx, w.get_entity(1).owner], [SimEntity.Kind.STRUCTURE, hq, 0], "HQ 1 belongs to pid 0")
	t.eq(w.get_entity(2).owner, 1, "HQ 2 belongs to pid 1")
	t.eq(w.get_entity(1).x, 20 * 1024 + 512, "HQ centred on the spawn cell (20, 20)")
	t.eq(w.get_entity(2).y, 70 * 1024 + 512, "second spawn (70, 70)")
	t.check((w.get_entity(1).flags & SimFlags.F_INITIAL) != 0, "F_INITIAL")
	t.eq(w.get_entity(1).hp, w.get_entity(1).hp_max, "full hp")
	t.eq(w.players[0].credits, 7500, "start credits")
	t.eq(w.players[0].struct_count, 1, "HQ counted")
	t.eq(w.players[0].st_structs_built, 0, "SPAWN_INITIAL is not 'built'")
	t.eq(w.checksum_log.size(), 2, "tick-0 checkpoint")
	t.eq(w.checksum_log[0], 0, "checkpoint at tick 0")
	t.eq(w.checksum_log[1], w.checksum(), "checkpoint == checksum()")
	t.eq(w.tick, 0, "tick 0")
	t.eq(w.next_id, 3, "ids 1 and 2 used")
	t.eq(w.humans_total, 1, "one human")
	t.eq(w.struct_at(20, 20), 1, "HQ occupies its centre cell")
	t.eq(w.struct_at(19, 21), 1, "3x3: cell 19..21")
	t.eq(w.struct_at(22, 20), 0, "outside the footprint")
	var w2: SimWorld = K.make_world()
	t.eq(w.checksum(), w2.checksum(), "two builds agree")
	t.ne(K.make_world({"seed": 999}).checksum(), w.checksum(), "another seed differs")


func test_start_modes_and_neutrals(t: TestCtx) -> void:
	var mcv: SimWorld = K.make_world({"rules": {"start_mode": SimMatchRules.START_MCV}})
	t.eq(mcv.units.size(), 2, "START_MCV spawns MCV units")
	t.eq(mcv.units[0].def_idx, mcv.data.unit_idx(DefTestKit.U_MCV), "the roster's MCV")
	t.eq(mcv.players[0].rebuilders, 1, "the MCV keeps its owner alive")
	t.eq(mcv.players[0].unit_count, 0, "pop 0")
	var none: SimWorld = K.make_world({"rules": {"start_mode": SimMatchRules.START_NONE, "victory": 0}})
	t.eq(none.entities.size(), 0, "START_NONE spawns nothing")
	# neutral records: [kind, cell, w, h, variant, flags, orbit, reserved]; kind 0 -> barracks def, kind 3 unmapped
	var recs: PackedInt32Array = PackedInt32Array([0, 50 * 96 + 40, 2, 2, 0, 0, 0, 0, 3, 60 * 96 + 60, 2, 2, 0, 0, 0, 0])
	var w: SimWorld = K.make_world({"neutrals": recs})
	t.eq(w.entities.size(), 3, "one mapped neutral structure spawned, the unmapped kind spawns nothing")
	var n: SimEntity = w.get_entity(1)
	t.eq([n.owner, n.kind, n.x, n.y], [-1, SimEntity.Kind.STRUCTURE, 40 * 1024 + 1024, 50 * 1024 + 1024], "neutrals come first, centre = top-left + size / 2")
	t.check((n.flags & SimFlags.F_INITIAL) != 0, "F_INITIAL")
	t.eq(w.struct_at(40, 50), 1, "2x2 occupied")
	t.eq(w.struct_at(41, 51), 1, "2x2 occupied (far corner)")
	t.eq(w.struct_at(42, 50), 0, "outside")
	t.eq(w.structures_of(-1).size(), 1, "neutral list")
	t.eq(w.players[0].struct_count, 1, "neutrals count for nobody")
	var off: SimWorld = K.make_world({"neutrals": recs, "rules": {"neutral_structures": 0}})
	t.eq(off.entities.size(), 2, "neutral_structures = 0 spawns none")


func test_create_validation(t: TestCtx) -> void:
	var cfg: SimMatchConfig = K.make_config(2)
	cfg.players[1].start = 20
	Log.quiet = true
	t.is_null(SimWorld.create(K.data(), cfg, K.make_map(), {}), "a start slot beyond the map's spawns is refused")
	Log.quiet = false
	t.check("start" in Log.ring[Log.ring.size() - 1], "the problem is logged")
	var bad: MapData = K.make_map()
	bad = bad.clone_fresh()
	bad.neutrals = PackedInt32Array([1, 2, 3])
	Log.quiet = true
	t.is_null(SimWorld.create(K.data(), K.make_config(2), bad, {}), "neutral records that are not whole records are refused")
	Log.quiet = false
	t.not_null(SimWorld.create(K.data(), K.make_config(2), K.make_map(), {}), "a valid config builds")


func test_vacant_players(t: TestCtx) -> void:
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 5, "map": {}, "players": [
		{"pid": 0, "kind": "human", "roster": DefTestKit.R_ALPHA, "team": 1, "color": 0, "start": 0},
		{"pid": 3, "kind": "ai", "roster": DefTestKit.R_VANILLA, "team": 2, "color": 1, "start": 1},
	]})
	var w: SimWorld = SimWorld.create(K.data(), cfg, K.make_map(), {})
	t.eq(w.players.size(), 4, "array sized max pid + 1")
	t.eq(w.players[1].controller, SimPlayer.Controller.NONE, "pid 1 vacant")
	t.eq(w.players[1].eliminated, 1, "vacant = pre-eliminated")
	t.eq(w.entities.size(), 2, "only active players get a start entity")
	t.eq(w.get_entity(2).owner, 3, "pid 3 keeps its pid")
	t.eq(w.rel(1, 0), SimWorld.Rel.NEUTRAL, "vacant pids are neutral to everyone")
	t.eq(w.rel(0, 3), SimWorld.Rel.ENEMY, "different teams")
	t.check_false(w.is_player_active(1), "vacant is inactive")
	t.check(w.is_player_active(3), "active")
	t.is_null(w.spawn_unit(K.unit_def(DefTestKit.U_RIFLEMAN), 1, 0, 0), "no spawns for a vacant owner")


func test_step_and_checkpoints(t: TestCtx) -> void:
	var w: SimWorld = K.make_world()
	w.run(45)
	t.eq(w.tick, 45, "45 ticks")
	t.eq(w.checksum_log.size(), 6, "checkpoints at 0, 20, 40")
	t.eq(w.checksum_at(0), w.checksum_log[1], "checksum_at(0)")
	t.eq(w.checksum_at(40), w.checksum_log[5], "checksum_at(40)")
	t.eq(w.checksum_at(41), -1, "no checkpoint at 41")
	t.eq(w.checksum_at(60), -1, "not reached")
	t.eq(w.checksum_parts_at(40).size(), 16, "16 parts")
	t.eq(w.checksum_part_names().size(), 16, "16 names")
	var rep: Dictionary = w.report_at(20)
	t.eq(rep["tick"], 20, "report tick")
	t.eq((rep["entity_digests"] as PackedInt32Array).size(), 4, "2 entities x [id, digest]")
	t.eq(rep["final"], w.checksum_at(20), "report final == log")
	t.eq(w.report_at(21), {}, "no report")
	w.run(15)
	t.eq(w.checksum(), w.checksum_at(60), "checksum() at a checkpoint tick equals the log")
	t.eq(w.events.tick, 60, "events carry the current tick")
	var parts: PackedInt32Array = w.checksum_parts_at(60)
	t.eq(parts[SimWorld.CHECKSUM_PART_NAMES.find("sys.combat")], Checksum.EMPTY_DIGEST - 4294967296 if Checksum.EMPTY_DIGEST > 2147483647 else Checksum.EMPTY_DIGEST, "stub stages digest as EMPTY_DIGEST (int32-wrapped)")


func test_opts(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"opts": {"checkpoint_interval": 1}})
	w.run(5)
	t.eq(w.checksum_log.size(), 12, "checkpoint_interval 1: 6 checkpoints in 5 steps")
	var s: SimWorld = K.make_world({"opts": {"snapshot_keep": 2, "checkpoint_interval": 1}})
	s.run(4)
	t.eq(s.snapshot_ring.size(), 2, "snapshot_keep 2 keeps two dumps")
	t.check(s.snapshot_ring[1].begins_with("MFSIM"), "dump header")
	var dump: String = s.dump_state()
	var e_lines: int = 0
	for line: String in dump.split("\n"):
		if line.begins_with("E"):
			e_lines += 1
	t.eq(e_lines, s.entities.size(), "one E line per entity")
	# events: on/off never changes the chain
	var on: SimWorld = K.s_core_1_world()
	var off: SimWorld = K.s_core_1_world({"opts": {"events": false}})
	K.run_script(on, 45, Callable(K, "s_core_1_script"))
	K.run_script(off, 45, Callable(K, "s_core_1_script"))
	t.eq(on.checksum_log, off.checksum_log, "events on / off give the same chain")
	t.check(on.events.count() > 0 and off.events.count() == 0, "events:false leaves the buffer empty")
	t.eq(on.events.take().size() > 0, true, "take() hands over")
	t.eq(on.events.count(), 0, "and empties")
	# disable / systems
	var d: SimWorld = K.make_world({"combat_stub": false, "opts": {"disable": ["SimCombatSystem", "SimVisionSystem"]}})
	t.is_null(d.combat, "disabled stage: typed member is null")
	t.is_null(d.vision, "vision disabled too")
	t.eq(d.stages[7].stage_no, 8, "a plain stub keeps the stage number")
	d.run(3)
	t.eq(d.tick, 3, "the world runs without it")
	var dbl: K.CombatStub = K.CombatStub.new()
	var r: SimWorld = K.make_world({"combat_stub": false, "opts": {"systems": [dbl]}})
	t.check(r.combat == dbl, "systems replaces the stage")


func test_invariants_option(t: TestCtx) -> void:
	var w: SimWorld = K.make_world({"opts": {"invariants_every": 1}})
	var seen: PackedStringArray = PackedStringArray()
	Log.sink = func(_lv: int, _tag: String, msg: String) -> void: seen.append(msg)
	w.run(3)
	t.eq(seen.size(), 0, "a healthy world logs no violation")
	w.get_entity(1).hp = 99999  # above hp_max
	w.step()
	Log.sink = Callable()
	t.check(seen.size() >= 1 and "INV-7" in seen[0], "a corrupted hp is reported as INV-7")


func test_invariants_direct(t: TestCtx) -> void:
	var w: SimWorld = K.s_core_1_world()
	K.run_script(w, 110, Callable(K, "s_core_1_script"))
	t.eq(SimInvariants.check(w), PackedStringArray(), "S-CORE-1 leaves no violation")


func test_world_is_freed(t: TestCtx) -> void:
	var w: SimWorld = K.s_core_1_world()
	K.run_script(w, 110, Callable(K, "s_core_1_script"))
	var ref: WeakRef = weakref(w)
	t.check(ref.get_ref() != null, "alive while referenced")
	w = null
	t.check(ref.get_ref() == null, "a world (stages, orders, cleanup, wreck, events) is freed when its last reference drops: no RefCounted cycle")
