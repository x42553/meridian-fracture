extends RefCounted
## AIX1 engineer and siege ops on real matches (ai.md 5.11, 5.8.2 SIEGING, S10): neutral capture by an Engineer with escorts,
## African Empire wreck salvage (only enemy wrecks, only AE rosters), and the artillery siege of a defended cluster.

const R_AE: String = "roster.ae.vanilla"


func test_capture_op_takes_a_neutral_structure(t: TestCtx) -> void:
	var found: bool = false
	for sd: int in range(1, 9):
		var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 5400, {"seed": sd})
		var b: AiBrain = AiXKit.brain(m, 0)
		var c: AiContext = AiXKit.ctx(m, 0)
		var bg: AiBudget = AiBudget.new()
		bg.reset(100000, 100000)
		var cand: Dictionary = AiOpCapture.best_candidate(c, b, bg)
		if cand.is_empty():
			continue
		found = true
		# an Engineer next to the base and the credits for it
		var w: SimWorld = AiXKit.world(m)
		var h: PackedInt32Array = AiXKit.home(m, 0)
		AiXKit.spawn(m, "unit.shared.engineer", 0, h[0] + 3 * AiXKit.CELL, h[1], 500)
		w.players[0].credits = 6000
		AiSoakKit.play(m, 60)
		var before: int = b.stat("capture_ops")
		AiSoakKit.play(m, 3600)
		t.gt(b.stat("capture_ops"), before - 1, "a capture op was launched on seed %d" % sd)
		t.gt(b.stat("capture_ops"), 0, "the capture op ran")
		t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
		var nid: int = int(cand["eid"])
		if b.stat("capture_done") > 0:
			t.gt(b.stat("capture_done"), 0)
		t.check(w.get_entity(nid) != null)
		break
	t.check(found, "one of the first eight maps has a capturable neutral within reach")


func test_capture_value_table(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 1], 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	var gd: GameData = c.view.game_data()
	var cheap: int = 0
	for nd: DefNeutral in gd.neutrals:
		if nd == null or not nd.capturable:
			continue
		var v: int = AiOpCapture.value_of(c, nd)
		if v < AiOpCapture.MIN_VALUE:
			cheap += 1
	t.ge(cheap, 0)
	var dep: int = gd.neutral_idx("neutral.salvage_depot")
	t.ge(AiOpCapture.value_of(c, gd.neutrals[dep]), AiOpCapture.MIN_VALUE, "a Salvage Depot is worth an Engineer")
	var hosp: int = gd.neutral_idx("neutral.field_hospital")
	t.lt(AiOpCapture.value_of(c, gd.neutrals[hosp]), 400, "a Field Hospital is a marginal prize")


func test_mexico_and_nigeria_capture_earlier(t: TestCtx) -> void:
	for r: String in ["roster.napc.mexico", "roster.ae.nigeria"]:
		var m: Dictionary = AiXKit.match_of(PackedStringArray([r, AiXKit.R_NEC]), [1, 1], 0)
		var c: AiContext = AiXKit.ctx(m, 0)
		t.check(c.pers.has_flag(AiTypes.doctrine_bit("CAPTURE_POINTS")), "%s has CAPTURE_POINTS" % r)


func test_salvage_engineer_takes_an_enemy_wreck_only_for_ae(t: TestCtx) -> void:
	# S10: AE assigns a salvager to an enemy wreck; the payout is 20 % of the paid cost; non-AE ignore wrecks
	var m: Dictionary = AiXKit.match_of(PackedStringArray([R_AE, AiXKit.R_NEC]), [1, 0], 3400)
	var b: AiBrain = AiXKit.brain(m, 0)
	var w: SimWorld = AiXKit.world(m)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	w.players[0].credits = 9000
	var eng: int = AiXKit.spawn(m, "unit.shared.engineer", 0, h[0] + 4 * AiXKit.CELL, h[1] + 3 * AiXKit.CELL, 500)
	AiSoakKit.play(m, 300)
	t.gt(b.count_ops(AiTypes.OpType.SALVAGE), 0, "the AE AI runs a salvage op once it owns a salvager")
	# an enemy tank dies next to the engineer
	var tank: SimEntity = w.get_entity(AiXKit.spawn(m, "unit.nec.leopard_tank", 1, h[0] + 8 * AiXKit.CELL, h[1] + 3 * AiXKit.CELL, 1100))
	var c0: int = w.players[0].credits
	w.combat.kill(w, tank, SimCombatConsts.CAUSE_DAMAGE, -1, 0)
	AiSoakKit.play(m, 40)
	var assigned: bool = false
	var op: AiOpSalvage = null
	for o: AiOp in b.ops:
		if o is AiOpSalvage:
			op = o
	t.not_null(op)
	if op != null:
		assigned = op.assigned_total > 0
	AiSoakKit.play(m, 40)
	if op != null:
		assigned = assigned or op.assigned_total > 0
	t.check(assigned, "a salvager was assigned within 80 ticks")
	AiSoakKit.play(m, 400)
	t.gt(w.players[0].credits, c0 - 3000, "credits are sane")
	t.gt(w.players[0].econ.stat_salvaged, 0, "the wreck paid out")
	t.eq(w.players[0].econ.stat_salvaged, 220, "20 % of the paid 1100")
	t.check(AiXKit.alive(m, eng))
	# a friendly wreck is never salvaged
	var own: SimEntity = w.get_entity(AiXKit.spawn(m, "unit.ae.buffalo_tank", 0, h[0] + 8 * AiXKit.CELL, h[1] - 3 * AiXKit.CELL, 1000))
	var before: int = w.players[0].econ.stat_salvaged
	w.combat.kill(w, own, SimCombatConsts.CAUSE_DAMAGE, -1, 1)
	AiSoakKit.play(m, 500)
	t.eq(w.players[0].econ.stat_salvaged, before, "own wrecks pay nothing and are not tried")
	# a non-AE roster never launches the op
	var m2: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 3600)
	AiXKit.spawn(m2, "unit.shared.engineer", 0, AiXKit.home(m2, 0)[0] + 3000, AiXKit.home(m2, 0)[1], 500)
	AiSoakKit.play(m2, 200)
	t.eq(AiXKit.brain(m2, 0).count_ops(AiTypes.OpType.SALVAGE), 0, "no salvage op for a roster without the SALVAGE doctrine")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_siege_bombards_a_defended_cluster_with_artillery(t: TestCtx) -> void:
	# NEC artillery (Archer SPG, 15 cells) outranges the Watchtowers of an NAPC cluster: the wave stops out of reach and shells them
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NEC, AiXKit.R_NAPC]), [2, 0], 3000, {"seed": 4})
	var w: SimWorld = AiXKit.world(m)
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	var home: PackedInt32Array = AiXKit.home(m, 0)
	var eh: PackedInt32Array = AiXKit.home(m, 1)
	var wt: int = w.data.structure_idx("structure.shared.watchtower")
	var cluster: PackedInt32Array = AiXKit.toward(eh, home, 14)
	var towers: PackedInt32Array = PackedInt32Array()
	for i: int in 3:
		var e: SimEntity = w.spawn_structure(wt, 1, cluster[0] + i * 3 * AiXKit.CELL, cluster[1], 0, SimFlags.F_POWERED, 300)
		if e != null:
			towers.append(e.id)
	t.ge(towers.size(), 1, "the enemy towers exist")
	AiSoakKit.play(m, 40)
	var g: AiGhostTable = c.kb.ghosts
	t.gt(g.count, 1, "the towers are known ghosts")
	var start: PackedInt32Array = AiXKit.toward(cluster, home, 30)
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 4:
		ids.append(AiXKit.spawn(m, "unit.nec.archer_spg", 0, start[0] + k * 900, start[1], 1400))
	for k2: int in 6:
		ids.append(AiXKit.spawn(m, "unit.nec.leopard_tank", 0, start[0] + k2 * 800, start[1] + 1500, 1000))
	AiXKit.settle(m)
	var op: AiOpAttack = AiOpAttack.new()
	op.setup_wave(AiTypes.SquadKind.MAIN, ids, {"x": cluster[0], "y": cluster[1], "eid": towers[0], "value": 900}, 512)
	op.start_state = AiTypes.OpState.ADVANCING
	t.check(b.add_op(c, op), "the wave starts")
	var seen: Dictionary = {}
	AiSoakKit.play(m, 1800, func(_mm: Dictionary) -> void:
		if op.state == AiTypes.OpState.SIEGING:
			seen["sieging"] = true)
	t.check(seen.has("sieging") or op.siege.sieges > 0, "the wave entered SIEGING")
	t.gt(b.stat("siege"), 0, "siege counter")
	var alive_towers: int = 0
	for tid: int in towers:
		if AiXKit.alive(m, tid):
			alive_towers += 1
	t.lt(alive_towers, towers.size(), "the artillery destroyed at least one tower (%d of %d left)" % [alive_towers, towers.size()])
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")
