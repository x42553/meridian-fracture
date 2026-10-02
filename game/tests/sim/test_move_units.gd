extends RefCounted
## terrain_movement unit tests of TM-10 / TM-11: U16 profiles, U19 hash coverage, U8 speed law, steering helpers.

const K := preload("res://tests/support/sim_test_kit.gd")
const M := preload("res://tests/support/move_test_kit.gd")


func test_u16_profiles(t: TestCtx) -> void:
	var d: GameData = M.data()
	var p: SimMoveProfiles = SimMoveProfiles.build(d, MapTerrain.load_default())
	var tank: int = d.unit_idx(DefTestKit.U_TANK)
	t.eq(p.np[tank], MapTerrain.NP_TRACKED, "tank np")
	t.eq(p.nav_size[tank], 2, "tank nav_size")
	t.eq(p.mass[tank], d.bodies.mass[d.units[tank].size_class], "mass from the body table")
	t.eq(p.accel_q4[tank], 272, "Guardian accel_q4")
	t.eq(p.decel_q4[tank], 408, "Guardian decel_q4")
	t.eq(p.turn_mode[tank], SimMoveConfig.TM_PIVOT, "tracked pivots")
	t.eq(p.reverse_pct[tank], 50, "reverse 50")
	t.eq(p.hl_default[tank], SimMoveConfig.HL_GROUND, "ground layer")
	var rifle: int = d.unit_idx(DefTestKit.U_RIFLEMAN)
	t.eq(p.nav_size[rifle], 1, "infantry nav_size 1")
	t.eq(p.turn_mode[rifle], SimMoveConfig.TM_INSTANT, "infantry instant")
	t.eq(p.reverse_pct[rifle], 0, "infantry no reverse")
	t.eq(p.accel_q4[rifle], 696, "infantry accel_q4 = 8 * speed")
	t.eq(p.decel_q4[rifle], 1392, "infantry decel_q4 (decel_t 1)")
	var col: int = d.unit_idx(DefTestKit.U_COLLECTOR)
	t.eq(p.turn_mode[col], SimMoveConfig.TM_ARC, "wheeled arcs")
	t.eq(p.np[col], MapTerrain.NP_WHEELED, "wheeled np")
	# reclassify a copy: fighter, gunship, large ship, amphibious light / medium
	var u: DefUnit = d.units[d.unit_idx(DefTestKit.U_TANK2)]
	u.move_class = DefEnums.MoveClass.AIR_FIXED
	var p2: SimMoveProfiles = SimMoveProfiles.build(d, null)
	var i2: int = d.unit_idx(DefTestKit.U_TANK2)
	t.eq(p2.turn_mode[i2], SimMoveConfig.TM_BANK, "fixed wing banks")
	t.eq(p2.hl_default[i2], SimMoveConfig.HL_AIR_HIGH, "fixed wing high")
	t.eq(p2.np[i2], MapTerrain.NP_NONE, "air has no nav profile")
	u.move_class = DefEnums.MoveClass.AIR_HOVER
	t.eq(SimMoveProfiles.build(d, null).turn_mode[i2], SimMoveConfig.TM_INSTANT, "gunship instant")
	u.move_class = DefEnums.MoveClass.NAVAL
	u.radius = 1434
	var p3: SimMoveProfiles = SimMoveProfiles.build(d, null)
	t.eq(p3.np[i2], MapTerrain.NP_NAVAL_DEEP, "large ship deep only")
	t.eq(p3.nav_size[i2], 3, "large ship size 3")
	t.eq(p3.hl_default[i2], SimMoveConfig.HL_WATER, "naval water layer")
	u.move_class = DefEnums.MoveClass.AMPHIBIOUS
	u.size_class = DefEnums.SizeClass.LIGHT
	t.eq(SimMoveProfiles.build(d, null).turn_mode[i2], SimMoveConfig.TM_ARC, "light amphibious arcs")
	u.size_class = DefEnums.SizeClass.MEDIUM
	t.eq(SimMoveProfiles.build(d, null).turn_mode[i2], SimMoveConfig.TM_PIVOT, "medium amphibious pivots")


func test_u19_hash_coverage(t: TestCtx) -> void:
	t.eq(K.check_hash_coverage(SimCompMove, SimCompMove.HASH_EXEMPT), PackedStringArray(), "every non-exempt field is hashed")


func test_u8_speed_law(t: TestCtx) -> void:
	var spd: int = 0
	var seq: PackedInt32Array = PackedInt32Array()
	for i: int in 7:
		spd = SimSteering.speed_law(spd, 1632, 272, 408)
		seq.append(spd)
	t.eq(seq, PackedInt32Array([272, 544, 816, 1088, 1360, 1632, 1632]), "acceleration sequence")
	var braked: PackedInt32Array = PackedInt32Array()
	spd = 1632
	var dist: int = 0
	for i: int in 4:
		spd = SimSteering.speed_law(spd, 0, 272, 408)
		braked.append(spd)
		dist += SimSteering.vel_x(spd, 0)
	t.eq(braked, PackedInt32Array([1224, 816, 408, 0]), "braking sequence")
	t.check(absi(dist - 154) <= 20, "braking distance %d" % dist)
	# vcur_q4 examples of 5.1
	t.eq(SimSteering.top_speed_q4(128, 10500, false, 10000, 10000, 0), 2150, "Open Corridor on a road")
	t.eq(SimSteering.top_speed_q4(128, 8000, false, 10000, 10000, 0), 1638, "rough")
	t.eq(SimSteering.top_speed_q4(164, 7000, true, 12000, 10000, 0), 2204, "Beaver on deep water")
	t.eq(SimSteering.top_speed_q4(87, 7000, false, 10000, 7500, 0), 731, "suppressed infantry in forest")
	t.eq(SimSteering.top_speed_q4(102, 10000, false, 10000, 10000, 1000), 1000, "formation cap")
	# infantry: full speed in 2 ticks, stops in one
	var inf: int = SimSteering.speed_law(0, 1392, 696, 1392)
	t.eq(inf, 696, "infantry tick 1")
	t.eq(SimSteering.speed_law(SimSteering.speed_law(inf, 1392, 696, 1392), 0, 696, 1392), 0, "stops within one tick")


func test_steering_helpers(t: TestCtx) -> void:
	t.eq(SimSteering.angle_err(10, 4090), 16, "wraps positive")
	t.eq(SimSteering.angle_err(4090, 10), -16, "wraps negative")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_PIVOT, 100), 256, "pivot small error")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_PIVOT, 512), 128, "pivot half")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_PIVOT, 900), 0, "pivot stops for big turns")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_INSTANT, 900), 0, "instant follows the pivot curve")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_BANK, 2000), 256, "bank is never limited")
	t.eq(SimSteering.heading_factor(SimMoveConfig.TM_ARC, 2000), 64, "arc creeps at 25 %")
	t.eq(SimSteering.turn_step_rate(SimMoveConfig.TM_ARC, 100, 0, 1000), 25, "arc at rest = 25 % of the rate")
	t.eq(SimSteering.turn_step_rate(SimMoveConfig.TM_ARC, 100, 1000, 1000), 100, "arc at full speed")
	# worked braking example: Guardian at rd' = 300, full speed
	t.eq(SimSteering.arrival_speed(408, 1632, 300, 0), Fp.isqrt(32 * 408 * (300 - 102)), "arrival speed with the lead term")
