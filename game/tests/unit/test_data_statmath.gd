extends RefCounted
## data_balance 10.1 "stat math" + "move table" effective_speed vectors.

const S := DefEnums.Stat


func _eco() -> DefEconomy:
	return DefEconomy.new()


func test_fold2(t: TestCtx) -> void:
	t.eq(DefStatMath.fold2(800, 1000, 0), 880, "800 +10%")
	t.eq(DefStatMath.fold2(420, 1000, 0), 462, "420 +10%")
	t.eq(DefStatMath.fold2(400, 1000, 1000), 484, "400 +10% +10%")
	t.eq(DefStatMath.fold2(500, -1000, 1500), 518, "500 -10% +15%")
	t.eq(DefStatMath.fold2(1100, -1000, 1000), 1089, "1100 -10% +10%")
	t.eq(DefStatMath.fold2(1400, 500, 1000), 1617, "1400")
	t.eq(DefStatMath.fold2(150, 2500, 0), 188, "150 +25%")
	t.eq(DefStatMath.fold2(150, 2500, 2000), 225, "150 +25% +20%")
	t.eq(DefStatMath.fold2(133, -1000, -1000), 108, "133 -10% -10%")
	t.eq(DefStatMath.fold2(100, -20000, 0), 0, "factor clamped at 0")


func test_resolve_and_effective(t: TestCtx) -> void:
	var e: DefEconomy = _eco()
	t.eq(DefStatMath.resolve_static(S.COST, 200, -1500, 0, e), 170, "cost -15%")
	t.eq(DefStatMath.effective(S.COST, 200, 170, -3000, e), 120, "cost floor 60%")
	t.eq(DefStatMath.effective(S.RELOAD, 40000, 44000, -1500, e), 37400, "reload -15%")
	t.eq(DefStatMath.effective(S.RELOAD, 40000, 20000, -5000, e), 20000, "reload floor 50%")
	t.eq(DefStatMath.apply_bp(55, 2000), 66, "apply_bp")
	t.eq(DefStatMath.resist_total_bp(6500, e), 5000, "resist cap")
	t.eq(DefStatMath.resist_total_bp(-100, e), 0, "resist floor")
	t.eq(DefStatMath.clamp_stat(S.HEALTH, 100, 0, e), 1, "health >= 1")
	t.eq(DefStatMath.clamp_stat(S.SPEED, 0, 0, e), 0, "speed base 0 stays 0")
	t.eq(DefStatMath.clamp_stat(S.DAMAGE, 0, 0, e), 0, "damage base 0 stays 0")
	t.eq(DefStatMath.clamp_stat(S.COST, 0, 0, e), 0, "cost base 0 skipped")
	t.eq(DefStatMath.clamp_stat(S.REARM, 160, 10, e), 80, "rearm floor")


func test_final_damage(t: TestCtx) -> void:
	var e: DefEconomy = _eco()
	t.eq(DefStatMath.final_damage(141, 10000, 100, 1000, 100, e), 127, "141 vs 10% resist")
	t.eq(DefStatMath.final_damage(140, 10000, 100, 0, 100, e), 140, "plain")
	t.eq(DefStatMath.final_damage(100, 10000, 100, 6500, 100, e), 50, "cap clamped inside")
	t.eq(DefStatMath.final_damage(140, 10000, 0, 0, 100, e), 0, "rail vs aircraft")
	t.eq(DefStatMath.final_damage(1, 10000, 6, 5000, 100, e), 1, "min 1")
	t.eq(DefStatMath.final_damage(140, 11000, 100, 0, 100, e), 154, "+10% bonus")
	t.eq(DefStatMath.final_damage(2400, 10000, 130, 0, 50, e), 1560, "kinetic vs building, splash edge")
	t.eq(DefStatMath.final_damage(5200, 10000, 70, 0, 100, e), 3640, "Perun core vs fortress")
	t.eq(DefStatMath.final_damage(0, 10000, 100, 0, 100, e), 0, "raw 0")


func test_hp_and_stack(t: TestCtx) -> void:
	t.eq(DefStatMath.rescale_hp(300, 400, 440), 330, "rescale up")
	t.eq(DefStatMath.rescale_hp(1, 1000, 1), 1, "rescale keeps >= 1")
	t.eq(DefStatMath.stack_pick(1000, 1500), 1500, "larger wins")
	t.eq(DefStatMath.stack_pick(1000, -1500), -1500, "larger |delta| wins")
	t.eq(DefStatMath.stack_pick(1000, -1000), 1000, "tie keeps existing")


func test_move_table_effective_speed(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	var g: Dictionary = DefTestKit.read_json("res://data/balance/global.json")
	var m: DefMoveTable = DefMoveTable.from_global(g, rep)
	t.check(rep.is_ok(), rep.text())
	var MC := DefEnums.MoveClass
	var TK := DefEnums.TerrainKind
	t.eq(m.speed_bp_at(MC.FOOT, TK.DEEP), 0, "foot deep")
	t.eq(m.speed_bp_at(MC.FOOT, TK.ROAD), 11000, "foot road")
	t.eq(m.speed_bp_at(MC.WHEELED, TK.ROAD), 13000, "wheeled road")
	t.eq(m.speed_bp_at(MC.WHEELED, TK.FOREST), 0, "wheeled forest")
	t.eq(m.speed_bp_at(MC.TRACKED, TK.FOREST), 5500, "tracked forest")
	t.eq(m.speed_bp_at(MC.AMPHIBIOUS, TK.SHALLOW), 9000, "amphibious shallow")
	t.eq(m.speed_bp_at(MC.AMPHIBIOUS, TK.DEEP), 7000, "amphibious deep")
	t.eq(m.speed_bp_at(MC.NAVAL, TK.OPEN), 0, "naval open")
	t.eq(m.speed_bp_at(MC.NAVAL, TK.DEEP), 10000, "naval deep")
	t.eq(m.speed_bp_at(MC.AIR_FIXED, TK.CLIFF), 10000, "air over cliff")
	for k: int in DefMoveTable.TERRAIN_COUNT:
		t.eq(m.speed_bp_at(MC.STATIC, k), 0, "static terrain %d" % k)
	t.check(m.passable(MC.FOOT, TK.SHALLOW), "foot passes shallow")
	t.check(not m.passable(MC.FOOT, TK.DEEP), "foot blocked by deep")
	t.eq(m.layer_mask[MC.AMPHIBIOUS], DefEnums.L_GROUND | DefEnums.L_WATER, "amphibious mask")
	t.eq(m.layer_mask[MC.SUBMERGED], DefEnums.L_UNDER | DefEnums.L_WATER, "submerged mask")
	t.eq(DefMoveTable.effective_speed(m, 164, MC.AMPHIBIOUS, TK.DEEP, 0, 12000), 138, "Canada Beaver on deep")
	t.eq(DefMoveTable.effective_speed(m, 102, MC.AMPHIBIOUS, TK.DEEP, 6000, 10000), 61, "Tide Tank on deep")
	t.eq(DefMoveTable.effective_speed(m, 102, MC.TRACKED, TK.FOREST, 0, 10000), 56, "tracked tank in forest")
	t.eq(DefMoveTable.effective_speed(m, 164, MC.WHEELED, TK.ROAD, 0, 10000), 213, "wheeled on road")
