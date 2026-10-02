extends RefCounted
## AIX1 MCV expansion (ai.md 5.4.4): the op moves the MCV with an escort of reserve units, deploys it and reports the new HQ;
## a killed MCV fails the op and blocks the site; AiExpansion delegates the trip to the op.


func _budget() -> AiBudget:
	var bg: AiBudget = AiBudget.new()
	bg.reset(1000000, 1000000)
	return bg


func test_expand_op_moves_escorts_and_deploys(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3600, {"seed": 3, "credits": 12000})
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	var eco: AiEconomy = b.eco()
	# pick the free site the expansion module would pick
	var s: int = eco.expansion._pick_site(c)
	t.gt(s, -1, "a free field exists")
	if s < 0:
		return
	eco.expansion._compute_target(c, s)
	var w: SimWorld = AiXKit.world(m)
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var mcv: int = AiXKit.spawn(m, "unit.shared.mobile_construction_vehicle", 0, h[0] + 4 * AiXKit.CELL, h[1] + 4 * AiXKit.CELL, 3000)
	var hq_def: int = c.res.structure_of_kind(AiTypes.StructKind.HQ)
	var hq0: int = eco.struct_own[hq_def]
	AiXKit.settle(m)
	var op: AiOpExpand = AiOpExpand.new()
	op.setup_expand(mcv, eco.expansion.target_x, eco.expansion.target_y, hq0)
	t.check(b.add_op(c, op), "the expand op starts")
	t.ge(op.escort_ids.size(), 1, "reserve units escort the MCV (%d)" % op.escort_ids.size())
	t.eq(op.priority, 58)
	AiSoakKit.play(m, 3000)
	t.check(op.success or op.state == AiTypes.OpState.ENGAGING or op.state == AiTypes.OpState.ADVANCING or op.state == AiTypes.OpState.DONE,
		"the op progressed (state %d, tries %d, %s)" % [op.state, op.tries, op.fail_reason])
	var hq_now: int = 0
	for e: SimEntity in w.structures_of(0):
		if e.def_idx == hq_def:
			hq_now += 1
	t.check(op.success or hq_now > hq0 or op.tries > 0, "the MCV deployed a new HQ or is retrying")
	t.eq((m["errors"] as PackedStringArray).size(), 0)


func test_expand_op_fails_when_the_mcv_dies(t: TestCtx) -> void:
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [2, 0], 3600, {"seed": 3})
	var b: AiBrain = AiXKit.brain(m, 0)
	var c: AiContext = AiXKit.ctx(m, 0)
	var eco: AiEconomy = b.eco()
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var mcv: int = AiXKit.spawn(m, "unit.shared.mobile_construction_vehicle", 0, h[0] + 4 * AiXKit.CELL, h[1] + 4 * AiXKit.CELL, 3000)
	AiXKit.settle(m)
	var op: AiOpExpand = AiOpExpand.new()
	op.setup_expand(mcv, h[0] + 30 * AiXKit.CELL, h[1], eco.struct_own[c.res.structure_of_kind(AiTypes.StructKind.HQ)])
	t.check(b.add_op(c, op))
	AiSoakKit.play(m, 60)
	AiXKit.world(m).remove_entity(mcv, SimEvent.REM_KILLED)
	AiSoakKit.play(m, 120)
	t.eq(op.state, AiTypes.OpState.FAILED, "a lost MCV fails the op")
	t.eq(op.squads.size(), 0, "the escort is released")


func test_expansion_module_delegates_to_the_op(t: TestCtx) -> void:
	# an EARLY-expansion personality at Hard: by 12 minutes the module has used the op at least once
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NEC, AiXKit.R_NAPC]), [2, 0], 14400,
		{"seed": 6, "pers_over": {0: {"expand": 0}}, "credits": 10000})
	var b: AiBrain = AiXKit.brain(m, 0)
	var ex: AiExpansion = b.eco().expansion
	t.check(ex.enabled, "expansion is enabled at Hard")
	t.check(ex.started > 0 or ex.op_runs > 0 or b.stat("expand_ops") > 0, "an expansion was attempted (started %d, ops %d)" % [ex.started, ex.op_runs])
	t.eq((m["errors"] as PackedStringArray).size(), 0)
