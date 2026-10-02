extends RefCounted
## CB-02: the damage pipeline (combat 5.6): reference vectors U-PIPE-1..9 plus the bible rules (50 % combined
## resistance cap, type-specific resistances, interception packets, directional armor, faction / research layers).

const ALL: int = SimCombatConsts.FILTER_ALL_WEAPON
const BULLET: int = SimCombatConsts.DT_BULLET
const HE: int = SimCombatConsts.DT_HE
const THERMAL: int = SimCombatConsts.DT_THERMAL
const TANK_ARMOR: int = DefEnums.ArmorClass.MEDIUM_ARMOR


func _tank() -> Array:
	var w: SimWorld = CombatKit.world()
	return [w, CombatKit.tank(w, 1, 30, 30)]


func _lease(w: SimWorld, e: SimEntity, key: int, bp: int, filter: int = ALL) -> void:
	SimCombatMods.apply(w, e, key, SimCombatConsts.STAT_TAKEN, bp, filter, 1000)


func test_u_pipe_1_thermal_tick(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, THERMAL, TANK_ARMOR, 12000)
	_lease(w, v, 1, 1000)  # Thermal Shrouds
	_lease(w, v, 2, 2000)  # Steel Advance
	t.eq(CombatKit.compute(w, v, CombatKit.wh(12, THERMAL), 12, SimCombatConsts.DC_DIRECT, {"static": 11500, "tmp": 2000}), 14, "12 -> 14.4 -> 16.56 -> 19.87 -> 13.9 -> 14")
	t.eq(w.combat.scratch_hitf & SimCombatConsts.HITF_CAP, 0, "cap not reached")


func test_u_pipe_2_trident_packet_and_cap(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, HE, TANK_ARMOR, 10000)
	_lease(w, v, 1, 2500)  # Emergency Fortification
	var perun: SimCombatWarhead = CombatKit.wh(1400, HE)
	t.eq(CombatKit.compute(w, v, perun, 1400, SimCombatConsts.DC_STRATEGIC, {"pkt": 5000}), 700, "packet 5000 + 2500 -> capped to 50 %")
	t.check((w.combat.scratch_hitf & SimCombatConsts.HITF_CAP) != 0, "cap flag")
	t.check((w.combat.scratch_hitf & SimCombatConsts.HITF_PACKET) != 0, "packet flag")
	t.eq(CombatKit.compute(w, v, perun, 1400, SimCombatConsts.DC_STRATEGIC), 1050, "without Trident: taken 7500")
	# the interception rule: the packet reduction never breaks the overall cap
	_lease(w, v, 2, 5000)
	t.eq(CombatKit.compute(w, v, perun, 1400, SimCombatConsts.DC_STRATEGIC, {"pkt": 5000}), 700, "even 12500 of resistance stops at 50 %")


func test_u_pipe_3_layers_multiply(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, BULLET, TANK_ARMOR, 10000)
	CombatKit.cdef(w, v).dir_rows.append_array(PackedInt32Array([SimCombatConsts.make_filter(1 << BULLET, SimCombatConsts.DC_DIRECT,
		SimCombatConsts.DC_SPLASH | SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_STRATEGIC), 0, 683, 2500, 0]))  # Gate Guard shield
	_lease(w, v, 1, 1500)  # Protected Advance
	t.eq(CombatKit.compute(w, v, CombatKit.wh(5, BULLET), 5), 3, "5 * 0.75 * 0.85 = 3.19 -> 3")
	t.check((w.combat.scratch_hitf & SimCombatConsts.HITF_DIRECTIONAL) != 0, "directional armor applied")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100), 64, "100 * 0.75 * 0.85 = 63.75 -> 64")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 2048}), 85, "from behind: no shield, only the lease")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 683}), 64, "edge of the arc still counts")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 684}), 85, "just outside the arc")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_SPLASH), 85, "blasts ignore the frontal shield")
	v.facing = 1024
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 1024}), 64, "the arc follows the victim's facing")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100), 85, "a bearing of 0 is now a flank")


func test_u_pipe_4_different_keys_add(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, HE, TANK_ARMOR, 10000)
	_lease(w, v, 1, 1000)  # Adaptive Plating
	_lease(w, v, 2, 2000)  # Steel Advance
	t.eq(CombatKit.compute(w, v, CombatKit.wh(60, HE), 60, SimCombatConsts.DC_DIRECT, {"tmp": 2000}), 50, "60 * 1.2 * 0.7 = 50.4 -> 50")
	_lease(w, v, 1, 1000)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(60, HE), 60, SimCombatConsts.DC_DIRECT, {"tmp": 2000}), 50, "the same key never stacks")


func test_u_pipe_5_chip_floor_and_immunity(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	var got: PackedInt32Array = PackedInt32Array()
	for m: int in [500, 400, 0]:
		CombatKit.set_matrix(w, BULLET, TANK_ARMOR, m)
		got.append(CombatKit.compute(w, v, CombatKit.wh(5, BULLET), 5))
	t.eq(got, PackedInt32Array([1, 0, 0]), "matrix 5 % chips for 1, 4 % rounds to 0, 0 % is immune")
	var q0: int = w.combat.dmg_queue.size()
	t.eq(CombatKit.hit(w, v, CombatKit.wh(5, BULLET)), 0, "deal on a 0 % matrix")
	t.eq(w.combat.dmg_queue.size(), q0, "queues nothing (immune, no status)")


func test_u_pipe_6_rear_vulnerability(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, BULLET, TANK_ARMOR, 10000)
	CombatKit.cdef(w, v).dir_rows.append_array(PackedInt32Array([ALL, 2048, 1024, -2000, 0]))
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 2048}), 120, "rear -2000 raises taken to 120 % (not capped)")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 0}), 100, "front unaffected")
	_lease(w, v, 1, 3000)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"from": 2048}), 84, "layers 0 and 3 multiply: 1.2 * 0.7")


func test_u_pipe_7_cap(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, BULLET, TANK_ARMOR, 10000)
	_lease(w, v, 1, 5000)
	_lease(w, v, 2, 3000)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100), 50, "layer sum 8000 -> taken 5000 (cap): damage halves")
	t.check((w.combat.scratch_hitf & SimCombatConsts.HITF_CAP) != 0, "cap flag")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT, {"tmp": 5000}), 75, "the cap does not limit attacker bonuses: 150 * 0.5")


func test_u_pipe_8_falloff(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, HE, TANK_ARMOR, 10000)
	var wh: SimCombatWarhead = CombatKit.wh(110, HE)
	wh.splash_r = 2048
	wh.splash_inner = 512
	wh.splash_edge_bp = 2500
	var d: int = 1280
	var f: int = 10000 - (10000 - wh.splash_edge_bp) * (d - wh.splash_inner) / (wh.splash_r - wh.splash_inner)
	t.eq(f, 6250, "falloff at d_eff 1280")
	t.eq(CombatKit.compute(w, v, wh, 110, SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_SPLASH, {"falloff": f}), 69, "110 at 62.5 % -> 69")


func test_u_pipe_9_marks(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, HE, TANK_ARMOR, 10000)
	SimCombatMods.apply(w, v, 3, SimCombatConsts.STAT_MARK, 1500, SimCombatMods.mark_filter(1, true), 240)  # Counterbattery mark
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT, {"tmp": 1000, "team": 1}), 125, "Relay +1000 and the mark +1500 add in one layer")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT, {"tmp": 1000, "team": 1, "ground": false}), 110, "a non-ground shooter gets no mark")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT, {"tmp": 1000, "team": 2}), 110, "another team gets no mark")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT, {"tmp": -20000}), 0, "the attacker layer never goes below 0")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT, {"tmp": 90000}), 400, "and is capped at +300 %")


func test_type_specific_resistances(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	for dt: int in [BULLET, HE, SimCombatConsts.DT_RAIL]:
		CombatKit.set_matrix(w, dt, TANK_ARMOR, 10000)
	_lease(w, v, 1, 2000, SimCombatConsts.make_filter(1 << BULLET))  # portable cover: bullets only
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100), 80, "bullet resistance applies to bullets")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100), 100, "and not to explosives")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, SimCombatConsts.DT_RAIL), 100), 100, "nor to rail")
	# a Dust-Screen-like lease only covers direct hits
	_lease(w, v, 2, 3000, SimCombatConsts.FILTER_DIRECT_ONLY)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_DIRECT), 70, "direct explosive hit: smoke applies")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100, SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_SPLASH), 100, "splash: smoke does not apply")
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, BULLET), 100, SimCombatConsts.DC_DIRECT), 50, "bullet direct: cover 2000 + smoke 3000 add inside layer 3 -> 0.5")


func test_research_and_faction_layers(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, HE, TANK_ARMOR, 10000)
	var l3: DefLayer3 = w.players[1].view.layer3
	l3._unit_res[v.def_idx * DefEnums.DamageType.COUNT + HE] = 1000  # permanent research row (Adaptive Plating)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100), 90, "research resistance is layer 3")
	_lease(w, v, 1, 2000)
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100), 70, "and adds to the temporary leases (1000 + 2000 = 3000)")
	CombatKit.cdef(w, v).static_resist = PackedInt32Array([1500, 0])  # a parent-faction layer-1 sum
	t.eq(CombatKit.compute(w, v, CombatKit.wh(100, HE), 100), 60, "faction layers multiply with layer 3: 0.85 * 0.7 = 0.595")
	var emp: SimCombatWarhead = CombatKit.wh(100, SimCombatConsts.DT_EMP)
	CombatKit.set_matrix(w, SimCombatConsts.DT_EMP, TANK_ARMOR, 10000)
	t.eq(CombatKit.compute(w, v, emp, 100), 100, "EMP ignores weapon resistances and faction sums")


func test_deal_encodes_flags_and_effects(t: TestCtx) -> void:
	var s: Array = _tank()
	var w: SimWorld = s[0]
	var v: SimEntity = s[1]
	CombatKit.set_matrix(w, BULLET, TANK_ARMOR, 10000)
	var sup: SimCombatWarhead = CombatKit.wh(10, BULLET)
	sup.suppressive = 1
	sup.packet = 1
	sup.nonlethal = 1
	t.eq(CombatKit.hit(w, v, sup, {"pkt": 5000}), 5, "packet halves it")
	var q: PackedInt32Array = w.combat.dmg_queue
	t.eq(q.size(), SimDamage.STRIDE, "one instance queued")
	t.eq([q[SimDamage.Q_VICTIM], q[SimDamage.Q_DMG], q[SimDamage.Q_DTYPE], q[SimDamage.Q_DC]], [v.id, 5, BULLET, SimCombatConsts.DC_DIRECT], "victim / dmg / type / class")
	var f: int = q[SimDamage.Q_FLAGS]
	t.check((f & SimCombatConsts.DF_NONLETHAL) != 0 and (f & SimCombatConsts.DF_SUPPRESSIVE) != 0 and (f & SimCombatConsts.DF_PACKET) != 0, "warhead flags ride on the instance")
	t.check(((f >> 8) & SimCombatConsts.HITF_PACKET) != 0, "packet reduction recorded for the hit event")
	t.eq([q[SimDamage.Q_IX], q[SimDamage.Q_IY], q[SimDamage.Q_AUX]], [v.x, v.y, 0], "impact point, no EMP")
