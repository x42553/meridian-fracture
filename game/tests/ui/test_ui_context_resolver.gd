extends RefCounted
## The contextual command table of ui.md 5.7 (10.2 `test_ui_context_resolver`): pure rows over synthetic
## capability sets, then make_target over the fixture and the caps of real defs.

const Q: int = UiContextResolver.MOD_QUEUE
const F: int = UiContextResolver.MOD_FORCE

const TANK: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_HIT_WATER | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE
const AA: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_AIR | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE
const RIFLE: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_GARRISON | UiUnitCaps.CAP_PASSENGER
const ENG: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_CAPTURE | UiUnitCaps.CAP_GARRISON | UiUnitCaps.CAP_PASSENGER
const COLL: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE | UiUnitCaps.CAP_COLLECTOR
const MCV: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE | UiUnitCaps.CAP_MCV | UiUnitCaps.CAP_DEPLOY
const APC: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE | UiUnitCaps.CAP_TRANSPORT
const JET: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_HIT_AIR | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_AIR
const REPAIRER: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE | UiUnitCaps.CAP_REPAIR_VEHICLE | UiUnitCaps.CAP_REPAIR_STRUCT
const SALVAGER: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE | UiUnitCaps.CAP_SALVAGE
const SCOUT: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE
const DRONE: int = UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_AIR | UiUnitCaps.CAP_CARRIER_DRONE
const SERVICE: int = UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_SERVICE
const BARRACKS: int = UiUnitCaps.CAP_STRUCTURE | UiUnitCaps.CAP_PRODUCER | UiUnitCaps.CAP_SELLABLE
const TURRET: int = UiUnitCaps.CAP_STRUCTURE | UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_SELLABLE
const FOOT: int = 1 << DefEnums.MoveClass.FOOT
const TRACKED: int = 1 << DefEnums.MoveClass.TRACKED
const NAVAL: int = 1 << DefEnums.MoveClass.NAVAL


## entries = [[id, caps], ...] or [[id, caps, move_class], ...]
func _sel(entries: Array, mode: int = UiSelection.Mode.UNITS) -> UiSelectionInfo:
	var ids := PackedInt32Array()
	var caps := PackedInt32Array()
	var defs := PackedInt32Array()
	var mcs := PackedInt32Array()
	for e: Array in entries:
		ids.append(int(e[0]))
		caps.append(int(e[1]))
		defs.append(100 + int(e[0]))
		mcs.append(int(e[2]) if e.size() > 2 else DefEnums.MoveClass.TRACKED)
	return UiSelectionInfo.from_entries(mode, ids, caps, defs, mcs)


func _enemy(id: int = 900, layer: int = 0, ek: int = UiTarget.EntityKind.UNIT) -> UiTarget:
	return UiTarget.entity(UiTarget.Kind.ENEMY, id, ek, 5000, 6000, layer)


func _own(id: int = 800, ek: int = UiTarget.EntityKind.UNIT) -> UiTarget:
	return UiTarget.entity(UiTarget.Kind.OWN, id, ek, 7000, 8000)


func _r(sel: UiSelectionInfo, tgt: UiTarget, mods: int = 0, armed: int = UiModes.Armed.NONE) -> UiOrderIntent:
	return UiContextResolver.resolve(sel, tgt, mods, armed)


func _is(t: TestCtx, it: UiOrderIntent, kind: int, ids: Array, msg: String) -> void:
	t.eq(it.kind, kind, "%s: kind (%s)" % [msg, it.describe()])
	t.eq(it.ids, PackedInt32Array(ids), "%s: ids" % msg)


func _kinds(it: UiOrderIntent) -> Array[int]:
	var out: Array[int] = []
	for i: UiOrderIntent in it.all_intents():
		out.append(i.kind)
	return out


# ---- guards ----------------------------------------------------------------------------------------------------------
func test_no_or_foreign_selection_gives_none(t: TestCtx) -> void:
	var none: UiSelectionInfo = UiSelectionInfo.new()
	t.eq(_r(none, UiTarget.ground(1, 1)).kind, UiOrderIntent.Kind.NONE, "empty selection")
	t.eq(_r(none, UiTarget.ground(1, 1)).cursor, UiOrderIntent.CUR_DEFAULT)
	t.eq(_r(none, _own()).cursor, UiOrderIntent.CUR_SELECT, "hover an own entity with nothing selected: SELECT")
	t.eq(_r(none, _enemy()).cursor, UiOrderIntent.CUR_INSPECT, "hover an enemy: INSPECT")
	var foreign: UiSelectionInfo = _sel([[1, TANK]], UiSelection.Mode.FOREIGN)
	t.eq(_r(foreign, UiTarget.ground(1, 1)).kind, UiOrderIntent.Kind.NONE, "foreign selection takes no commands")
	t.eq(_r(foreign, _enemy()).cursor, UiOrderIntent.CUR_INSPECT)


func test_off_map_is_denied(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK]]), UiTarget.new())
	t.eq(it.kind, UiOrderIntent.Kind.DENIED)
	t.eq(it.deny_reason, UiContextResolver.DENY_OFF_MAP)
	t.eq(it.cursor, UiOrderIntent.CUR_DENIED)
	t.eq(it.marker, UiOrderIntent.MK_DENIED)


# ---- rule 1 FORCE ----------------------------------------------------------------------------------------------------
func test_rule1_force_fire_on_ground(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, TANK]]), UiTarget.ground(20480, 20480), F)
	_is(t, it, UiOrderIntent.Kind.FORCE_FIRE, [1, 2], "force on ground")
	t.eq(it.x, 20480)
	t.eq(it.cursor, UiOrderIntent.CUR_FORCE_FIRE)


func test_rule1_force_on_own_unit_sets_forced_flag(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[5, TANK], [6, TANK]]), _own(1203), F)
	_is(t, it, UiOrderIntent.Kind.ATTACK, [5, 6], "force on own unit")
	t.eq(it.target_eid, 1203)
	t.check(it.force, "forced flag")


func test_rule1_force_on_wreck_and_deposit(t: TestCtx) -> void:
	var wreck: UiTarget = UiTarget.entity(UiTarget.Kind.WRECK, 77, UiTarget.EntityKind.WRECK, 100, 200)
	_is(t, _r(_sel([[1, TANK]]), wreck, F), UiOrderIntent.Kind.FORCE_FIRE, [1], "force on a wreck")
	_is(t, _r(_sel([[1, TANK]]), UiTarget.deposit(49664, 17920), F), UiOrderIntent.Kind.FORCE_FIRE, [1], "force on a deposit cell")


func test_rule1_unarmed_units_fall_through_to_move(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, ENG]]), UiTarget.ground(1000, 2000), F)
	t.eq(_kinds(it), [UiOrderIntent.Kind.FORCE_FIRE, UiOrderIntent.Kind.MOVE], "armed fire, unarmed walk")
	t.eq(it.extra[0].ids, PackedInt32Array([2]))


func test_rule1_force_on_enemy_is_a_normal_unforced_attack(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK]]), _enemy(), F)
	_is(t, it, UiOrderIntent.Kind.ATTACK, [1], "force on an enemy")
	t.check(not it.force, "an enemy target needs no forced flag")


func test_rule1_anti_air_cannot_force_ground(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, AA]]), UiTarget.ground(1000, 2000), F)
	t.eq(_kinds(it), [UiOrderIntent.Kind.FORCE_FIRE, UiOrderIntent.Kind.MOVE], "the AA unit cannot hit ground and walks instead")
	var air: UiTarget = UiTarget.entity(UiTarget.Kind.ALLY, 55, UiTarget.EntityKind.UNIT, 10, 20, 1)
	var it2: UiOrderIntent = _r(_sel([[1, TANK], [2, AA]]), air, F)
	_is(t, it2, UiOrderIntent.Kind.ATTACK, [2], "force on an allied aircraft: only AA can hit the air layer")


# ---- rules 2-3 CAPTURE / GARRISON ------------------------------------------------------------------------------------
func _neutral(capturable: bool, garrison: bool = false) -> UiTarget:
	var n: UiTarget = UiTarget.entity(UiTarget.Kind.NEUTRAL, 300, UiTarget.EntityKind.NEUTRAL_STRUCTURE, 3000, 3000)
	n.capturable = capturable
	n.garrisonable = garrison
	return n


func test_rule2_capture(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, ENG]]), _neutral(true))
	_is(t, it, UiOrderIntent.Kind.CAPTURE, [1], "engineer captures")
	t.eq(it.cursor, UiOrderIntent.CUR_INTERACT)
	t.eq(it.marker, UiOrderIntent.MK_CAPTURE)
	_is(t, _r(_sel([[1, RIFLE]]), _neutral(true)), UiOrderIntent.Kind.MOVE, [1], "riflemen cannot capture: they walk")
	_is(t, _r(_sel([[1, ENG]]), _neutral(false)), UiOrderIntent.Kind.MOVE, [1], "not capturable: walk")


func test_rule3_garrison(t: TestCtx) -> void:
	_is(t, _r(_sel([[1, RIFLE]]), _neutral(false, true)), UiOrderIntent.Kind.GARRISON, [1], "infantry garrison a civilian building")
	_is(t, _r(_sel([[1, TANK]]), _neutral(false, true)), UiOrderIntent.Kind.MOVE, [1], "tanks cannot garrison")
	var svc_inf: int = RIFLE | UiUnitCaps.CAP_SERVICE
	var it: UiOrderIntent = _r(_sel([[1, svc_inf], [2, RIFLE]]), _neutral(false, true))
	t.eq(it.kind, UiOrderIntent.Kind.GARRISON)
	t.eq(it.ids, PackedInt32Array([2]), "service units never garrison")


# ---- rule 4 LOAD -----------------------------------------------------------------------------------------------------
func _apc(id: int, free: int, vehicle_free: int = 0) -> UiTarget:
	var a: UiTarget = UiTarget.entity(UiTarget.Kind.OWN, id, UiTarget.EntityKind.UNIT, 4000, 4000)
	a.transport_free = free
	a.transport_vehicle_free = vehicle_free
	return a


func test_rule4_load_squads_and_e7(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, APC], [2, RIFLE]]), _apc(700, 2))
	t.eq(_kinds(it), [UiOrderIntent.Kind.LOAD, UiOrderIntent.Kind.MOVE], "E7: the squad loads, the APC itself walks over")
	t.eq(it.ids, PackedInt32Array([2]))
	t.eq(it.target_eid, 700)
	t.eq(it.extra[0].ids, PackedInt32Array([1]))
	_is(t, _r(_sel([[2, RIFLE]]), _apc(700, 0)), UiOrderIntent.Kind.MOVE, [2], "no free slot: walk")


func test_rule4_vehicles_need_vehicle_slots(t: TestCtx) -> void:
	_is(t, _r(_sel([[1, TANK]]), _apc(700, 2, 0)), UiOrderIntent.Kind.MOVE, [1], "tanks do not fit squad slots")
	var ptank: int = TANK | UiUnitCaps.CAP_PASSENGER
	_is(t, _r(_sel([[1, ptank]]), _apc(700, 0, 1)), UiOrderIntent.Kind.LOAD, [1], "transportable vehicles load into vehicle slots")
	_is(t, _r(_sel([[1, TANK]]), _apc(700, 0, 1)), UiOrderIntent.Kind.MOVE, [1], "a vehicle that is not a passenger walks")
	var it: UiOrderIntent = _r(_sel([[1, ptank], [2, RIFLE]]), _apc(700, 0, 1))
	t.eq(_kinds(it), [UiOrderIntent.Kind.LOAD, UiOrderIntent.Kind.MOVE], "the squad has no slot and walks")


func test_rule4_target_inside_selection_is_skipped(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[700, APC], [2, RIFLE]]), _apc(700, 2))
	t.eq(it.kind, UiOrderIntent.Kind.DENIED, "clicking a selected transport orders nothing")
	t.eq(it.deny_reason, UiContextResolver.DENY_NO_VALID)


# ---- rules 5-7 REPAIR / SALVAGE --------------------------------------------------------------------------------------
func test_rule5_repair_vehicle(t: TestCtx) -> void:
	var tank: UiTarget = _own(801)
	tank.damaged = true
	tank.caps = TANK
	var it: UiOrderIntent = _r(_sel([[1, REPAIRER]]), tank)
	_is(t, it, UiOrderIntent.Kind.REPAIR, [1], "repair a damaged own vehicle")
	t.eq(it.cursor, UiOrderIntent.CUR_REPAIR)
	tank.damaged = false
	_is(t, _r(_sel([[1, REPAIRER]]), tank), UiOrderIntent.Kind.MOVE, [1], "undamaged: walk")
	var inf: UiTarget = _own(802)
	inf.damaged = true
	inf.caps = RIFLE
	_is(t, _r(_sel([[1, REPAIRER]]), inf), UiOrderIntent.Kind.MOVE, [1], "infantry are not vehicles")
	tank.damaged = true
	t.eq(_r(_sel([[801, REPAIRER]]), tank).kind, UiOrderIntent.Kind.DENIED, "a repairer never repairs itself")


func test_rule6_repair_structure(t: TestCtx) -> void:
	var b: UiTarget = UiTarget.entity(UiTarget.Kind.ALLY, 810, UiTarget.EntityKind.STRUCTURE, 1, 1)
	b.damaged = true
	_is(t, _r(_sel([[1, REPAIRER]]), b), UiOrderIntent.Kind.REPAIR, [1], "repair a damaged allied structure")
	_is(t, _r(_sel([[1, TANK]]), b), UiOrderIntent.Kind.MOVE, [1], "tanks cannot repair")
	b.damaged = false
	_is(t, _r(_sel([[1, REPAIRER]]), b), UiOrderIntent.Kind.MOVE, [1], "undamaged structure: walk")


func test_rule7_salvage(t: TestCtx) -> void:
	var w: UiTarget = UiTarget.entity(UiTarget.Kind.WRECK, 77, UiTarget.EntityKind.WRECK, 100, 200)
	w.salvageable = true
	_is(t, _r(_sel([[1, SALVAGER]]), w), UiOrderIntent.Kind.SALVAGE, [1], "salvage a wreck")
	_is(t, _r(_sel([[1, TANK]]), w), UiOrderIntent.Kind.MOVE, [1], "tanks walk to the wreck")
	w.salvageable = false
	_is(t, _r(_sel([[1, SALVAGER]]), w), UiOrderIntent.Kind.MOVE, [1], "not salvageable: walk")


# ---- rules 8-10 HARVEST / RETURN -------------------------------------------------------------------------------------
func test_rule8_harvest_deposit_e4(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[9, COLL]]), UiTarget.deposit(49664, 17920))
	_is(t, it, UiOrderIntent.Kind.HARVEST, [9], "E4")
	t.eq(it.x, 49664)
	t.eq(it.y, 17920)
	t.eq(it.cursor, UiOrderIntent.CUR_INTERACT)
	_is(t, _r(_sel([[9, TANK]]), UiTarget.deposit(49664, 17920)), UiOrderIntent.Kind.MOVE, [9], "only collectors harvest")
	_is(t, _r(_sel([[9, COLL]]), UiTarget.ground(49664, 17920)), UiOrderIntent.Kind.MOVE, [9], "an unexplored / depleted cell is plain ground")


func test_rule9_return_cash(t: TestCtx) -> void:
	var ref: UiTarget = _own(640, UiTarget.EntityKind.STRUCTURE)
	ref.is_refinery = true
	_is(t, _r(_sel([[9, COLL]]), ref), UiOrderIntent.Kind.RETURN_CASH, [9], "deliver the load")
	_is(t, _r(_sel([[9, TANK]]), ref), UiOrderIntent.Kind.MOVE, [9], "tanks walk to the refinery")


func test_rule10_return_base_e9(t: TestCtx) -> void:
	var af: UiTarget = _own(640, UiTarget.EntityKind.STRUCTURE)
	af.is_airfield = true
	var it: UiOrderIntent = _r(_sel([[21, JET], [22, JET], [23, JET]]), af)
	_is(t, it, UiOrderIntent.Kind.RETURN_BASE, [21, 22, 23], "E9")
	t.eq(it.target_eid, 640)
	_is(t, _r(_sel([[21, TANK]]), af), UiOrderIntent.Kind.MOVE, [21], "ground units walk")
	var carrier: UiTarget = _own(641)
	carrier.is_carrier = true
	_is(t, _r(_sel([[30, DRONE]]), carrier), UiOrderIntent.Kind.RETURN_BASE, [30], "drones return to their carrier")


# ---- rules 11-12 ATTACK / CANNOT_HIT ---------------------------------------------------------------------------------
func test_rule11_attack_e1(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, TANK], [3, TANK], [4, COLL]]), _enemy())
	_is(t, it, UiOrderIntent.Kind.ATTACK, [1, 2, 3], "E1")
	t.eq(it.extra.size(), 0, "the collector is excluded, not moved")
	t.eq(it.cursor, UiOrderIntent.CUR_ATTACK)
	t.eq(it.marker, UiOrderIntent.MK_ATTACK)
	t.check(not it.force)


func test_rule11_queue_modifier_e6(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, TANK]]), _enemy(900, 0, UiTarget.EntityKind.STRUCTURE), Q)
	_is(t, it, UiOrderIntent.Kind.ATTACK, [1, 2], "E6")
	t.check(it.queued, "Shift / latch queue the attack")


func test_rule11_ghost_becomes_attack_move_e8(t: TestCtx) -> void:
	var ghost: UiTarget = _enemy(901, 0, UiTarget.EntityKind.STRUCTURE)
	ghost.ghost = true
	ghost.visible = false
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, TANK], [3, TANK], [4, TANK], [5, TANK], [6, AA]]), ghost)
	_is(t, it, UiOrderIntent.Kind.ATTACK_MOVE, [1, 2, 3, 4, 5], "E8")
	t.eq(it.cursor, UiOrderIntent.CUR_ATTACK, "cursor stays ATTACK")
	t.eq(it.extra.size(), 0, "the AA unit is consumed by rule 12")
	t.eq(it.x, 5000)


func test_rule12_cannot_hit_e3(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, AA]]), _enemy())
	t.eq(it.kind, UiOrderIntent.Kind.DENIED, "E3")
	t.eq(it.deny_reason, UiContextResolver.DENY_CANNOT_HIT)
	t.eq(it.cursor, UiOrderIntent.CUR_DENIED)
	_is(t, _r(_sel([[1, AA]]), _enemy(902, 1)), UiOrderIntent.Kind.ATTACK, [1], "the same AA unit attacks an aircraft")
	var mix: UiOrderIntent = _r(_sel([[1, AA], [2, RIFLE]]), _enemy())
	_is(t, mix, UiOrderIntent.Kind.ATTACK, [2], "AA is silently excluded from a mixed ground attack")
	t.eq(mix.extra.size(), 0)


func test_deny_no_weapon_and_not_visible(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, COLL], [2, MCV]]), _enemy())
	t.eq(it.kind, UiOrderIntent.Kind.DENIED)
	t.eq(it.deny_reason, UiContextResolver.DENY_NO_WEAPON, "collectors and MCVs never march into a fight")
	var hidden: UiTarget = _enemy()
	hidden.visible = false
	var it2: UiOrderIntent = _r(_sel([[1, TANK]]), hidden)
	t.eq(it2.deny_reason, UiContextResolver.DENY_NOT_VISIBLE)


func test_service_units_are_excluded_from_attacks(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, SERVICE]]), _enemy())
	_is(t, it, UiOrderIntent.Kind.ATTACK, [1], "service units stay out of attack orders")


# ---- rule 13 RALLY ---------------------------------------------------------------------------------------------------
func test_rule13_rally_e5(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[31, BARRACKS], [32, BARRACKS]], UiSelection.Mode.STRUCTURES), UiTarget.ground(10240, 12288))
	_is(t, it, UiOrderIntent.Kind.SET_RALLY, [31, 32], "E5")
	t.eq(it.x, 10240)
	t.eq(it.target_eid, -1)
	t.eq(it.cursor, UiOrderIntent.CUR_RALLY)
	var own_it: UiOrderIntent = _r(_sel([[31, BARRACKS]], UiSelection.Mode.STRUCTURES), _own(640, UiTarget.EntityKind.STRUCTURE))
	t.eq(own_it.target_eid, 640, "rally onto an own entity carries its id")
	var no_prod: UiOrderIntent = _r(_sel([[33, TURRET]], UiSelection.Mode.STRUCTURES), UiTarget.ground(1, 1))
	t.eq(no_prod.kind, UiOrderIntent.Kind.DENIED, "a turret has no rally point")


# ---- rules 14-16 MOVE ------------------------------------------------------------------------------------------------
func test_rule14_move_ground(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[7, TANK], [3, RIFLE], [12, COLL]]), UiTarget.ground(15360, 30720))
	_is(t, it, UiOrderIntent.Kind.MOVE, [3, 7, 12], "move: ids ascending")
	t.eq(it.cursor, UiOrderIntent.CUR_MOVE)
	t.eq(it.marker, UiOrderIntent.MK_MOVE)
	t.eq(it.x, 15360)
	var structs: UiOrderIntent = _r(_sel([[31, BARRACKS]], UiSelection.Mode.STRUCTURES), UiTarget.ground(1, 1))
	t.eq(structs.kind, UiOrderIntent.Kind.SET_RALLY, "structures are not mobile: the ground click is a rally")


func test_rule14_blocked_ground(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[1, TANK, DefEnums.MoveClass.TRACKED]])
	var water: UiTarget = UiTarget.ground(1, 1, NAVAL)
	var it: UiOrderIntent = _r(sel, water)
	t.eq(it.kind, UiOrderIntent.Kind.DENIED)
	t.eq(it.deny_reason, UiContextResolver.DENY_BLOCKED, "no selected class can stand there")
	var mixed: UiSelectionInfo = _sel([[1, TANK, DefEnums.MoveClass.TRACKED], [2, RIFLE, DefEnums.MoveClass.FOOT]])
	_is(t, _r(mixed, UiTarget.ground(1, 1, FOOT)), UiOrderIntent.Kind.MOVE, [1, 2], "one class can stand there: the sim paths the others")
	_is(t, _r(sel, UiTarget.ground(1, 1, TRACKED)), UiOrderIntent.Kind.MOVE, [1], "standable")
	_is(t, _r(sel, UiTarget.ground(1, 1, -1)), UiOrderIntent.Kind.MOVE, [1], "unknown mask: no check")


func test_rule15_move_to_entity(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[1, TANK], [2, TANK]])
	_is(t, _r(sel, _own(800)), UiOrderIntent.Kind.MOVE, [1, 2], "own unit")
	_is(t, _r(sel, UiTarget.entity(UiTarget.Kind.ALLY, 801, UiTarget.EntityKind.STRUCTURE, 1, 2)), UiOrderIntent.Kind.MOVE, [1, 2], "allied structure")
	_is(t, _r(sel, _neutral(false)), UiOrderIntent.Kind.MOVE, [1, 2], "neutral building")
	_is(t, _r(sel, UiTarget.entity(UiTarget.Kind.WRECK, 802, UiTarget.EntityKind.WRECK, 1, 2)), UiOrderIntent.Kind.MOVE, [1, 2], "wreck")
	t.eq(_r(sel, _own(1)).kind, UiOrderIntent.Kind.DENIED, "clicking a selected unit does nothing")


func test_rule16_unarmed_units_walk_to_enemies(t: TestCtx) -> void:
	_is(t, _r(_sel([[1, SCOUT]]), _enemy()), UiOrderIntent.Kind.MOVE, [1], "an unarmed scout walks to the enemy position")
	var it: UiOrderIntent = _r(_sel([[1, TANK], [2, SCOUT], [3, ENG], [4, APC], [5, COLL]]), _enemy())
	t.eq(_kinds(it), [UiOrderIntent.Kind.ATTACK, UiOrderIntent.Kind.MOVE], "tanks and armed APC attack, the scout walks; engineer, collector excluded")
	t.eq(it.ids, PackedInt32Array([1, 4]))
	t.eq(it.extra[0].ids, PackedInt32Array([2]))


# ---- armed modes -----------------------------------------------------------------------------------------------------
func test_armed_attack_move(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[1, TANK], [2, SCOUT], [3, BARRACKS]])
	var on_ground: UiOrderIntent = _r(sel, UiTarget.ground(20480, 10240), 0, UiModes.Armed.ATTACK_MOVE)
	t.eq(_kinds(on_ground), [UiOrderIntent.Kind.ATTACK_MOVE, UiOrderIntent.Kind.MOVE], "armed units attack-move, unarmed mobile units move")
	t.eq(on_ground.ids, PackedInt32Array([1]))
	t.eq(on_ground.extra[0].ids, PackedInt32Array([2]))
	t.eq(on_ground.cursor, UiOrderIntent.CUR_ATTACK_MOVE)
	var on_enemy: UiOrderIntent = _r(sel, _enemy(), 0, UiModes.Armed.ATTACK_MOVE)
	t.eq(_kinds(on_enemy), [UiOrderIntent.Kind.ATTACK, UiOrderIntent.Kind.MOVE], "onto an enemy: rule 11 for armed units, MOVE for the rest")
	var ghost: UiTarget = _enemy(901, 0, UiTarget.EntityKind.STRUCTURE)
	ghost.ghost = true
	ghost.visible = false
	_is(t, _r(_sel([[1, TANK]]), ghost, 0, UiModes.Armed.ATTACK_MOVE), UiOrderIntent.Kind.ATTACK_MOVE, [1], "ghost target")
	var shift: UiOrderIntent = _r(sel, UiTarget.ground(1, 1), Q, UiModes.Armed.ATTACK_MOVE)
	t.check(shift.queued and shift.extra[0].queued, "every intent of the click shares the queue flag")


func test_armed_move_goes_past_enemies(t: TestCtx) -> void:
	_is(t, _r(_sel([[1, TANK], [2, COLL]]), _enemy(), 0, UiModes.Armed.MOVE), UiOrderIntent.Kind.MOVE, [1, 2], "walk into the enemy")
	_is(t, _r(_sel([[1, TANK]]), UiTarget.ground(9, 9), 0, UiModes.Armed.MOVE), UiOrderIntent.Kind.MOVE, [1], "ground")


func test_armed_patrol(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[4, TANK], [8, TANK], [9, BARRACKS]]), UiTarget.ground(30720, 40960), Q, UiModes.Armed.PATROL)
	_is(t, it, UiOrderIntent.Kind.PATROL, [4, 8], "patrol legs")
	t.check(it.queued, "Shift appends a further leg")
	_is(t, _r(_sel([[4, TANK]]), _own(800), 0, UiModes.Armed.PATROL), UiOrderIntent.Kind.PATROL, [4], "patrol onto an entity uses its position")


func test_armed_follow_e10(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[5, RIFLE], [6, RIFLE]])
	var it: UiOrderIntent = _r(sel, _own(1203), 0, UiModes.Armed.FOLLOW)
	_is(t, it, UiOrderIntent.Kind.FOLLOW, [5, 6], "E10")
	t.eq(it.target_eid, 1203)
	_is(t, _r(sel, UiTarget.entity(UiTarget.Kind.ALLY, 1204, UiTarget.EntityKind.UNIT, 1, 1), 0, UiModes.Armed.FOLLOW), UiOrderIntent.Kind.FOLLOW, [5, 6], "allied unit")
	for bad: UiTarget in [_enemy(), _own(1205, UiTarget.EntityKind.STRUCTURE), UiTarget.ground(1, 1), _own(5)]:
		var d: UiOrderIntent = _r(sel, bad, 0, UiModes.Armed.FOLLOW)
		t.eq(d.kind, UiOrderIntent.Kind.DENIED)
		t.eq(d.deny_reason, UiContextResolver.DENY_FOLLOW_TARGET)
	t.eq(_r(sel, _own(1203), Q, UiModes.Armed.FOLLOW).queued, true, "Shift appends")


func test_armed_guard(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[4, TANK], [5, COLL]])
	var unit: UiOrderIntent = _r(sel, _own(800), 0, UiModes.Armed.GUARD)
	_is(t, unit, UiOrderIntent.Kind.GUARD, [4], "guard an own unit (armed mobile units only)")
	t.eq(unit.target_eid, 800)
	var pt: UiOrderIntent = _r(sel, UiTarget.ground(20480, 10240), 0, UiModes.Armed.GUARD)
	_is(t, pt, UiOrderIntent.Kind.GUARD, [4], "guard a point")
	t.eq(pt.target_eid, -1)
	t.eq(pt.x, 20480)
	t.eq(_r(sel, _enemy(), 0, UiModes.Armed.GUARD).deny_reason, UiContextResolver.DENY_GUARD_ENEMY)
	t.eq(_r(sel, _neutral(false), 0, UiModes.Armed.GUARD).kind, UiOrderIntent.Kind.DENIED)
	t.eq(_r(_sel([[800, TANK]]), _own(800), 0, UiModes.Armed.GUARD).kind, UiOrderIntent.Kind.DENIED, "a unit cannot guard itself")


func test_armed_sell(t: TestCtx) -> void:
	var b: UiTarget = _own(31, UiTarget.EntityKind.STRUCTURE)
	b.caps = BARRACKS
	var it: UiOrderIntent = _r(UiSelectionInfo.new(), b, 0, UiModes.Armed.SELL)
	_is(t, it, UiOrderIntent.Kind.SELL, [31], "sell needs no selection")
	t.eq(it.cursor, UiOrderIntent.CUR_SELL)
	var no: UiTarget = _own(32, UiTarget.EntityKind.STRUCTURE)
	no.caps = UiUnitCaps.CAP_STRUCTURE
	t.eq(_r(UiSelectionInfo.new(), no, 0, UiModes.Armed.SELL).deny_reason, UiContextResolver.DENY_NOT_SELLABLE, "not sellable")
	t.eq(_r(UiSelectionInfo.new(), _own(33), 0, UiModes.Armed.SELL).kind, UiOrderIntent.Kind.DENIED, "a unit cannot be sold")
	var foe: UiTarget = _enemy(34, 0, UiTarget.EntityKind.STRUCTURE)
	foe.caps = BARRACKS
	t.eq(_r(UiSelectionInfo.new(), foe, 0, UiModes.Armed.SELL).kind, UiOrderIntent.Kind.DENIED, "not an enemy building")
	b.selling = true
	t.eq(_r(UiSelectionInfo.new(), b, 0, UiModes.Armed.SELL).kind, UiOrderIntent.Kind.DENIED, "already being sold")


func test_armed_repair_sends_explicit_mode(t: TestCtx) -> void:
	var b: UiTarget = _own(31, UiTarget.EntityKind.STRUCTURE)
	var on: UiOrderIntent = _r(UiSelectionInfo.new(), b, 0, UiModes.Armed.REPAIR)
	_is(t, on, UiOrderIntent.Kind.STRUCT_REPAIR, [31], "repair toggle")
	t.eq(on.arg, 1, "not repairing yet: explicit mode 1")
	b.repairing = true
	t.eq(_r(UiSelectionInfo.new(), b, 0, UiModes.Armed.REPAIR).arg, 0, "already repairing: explicit mode 0")
	t.eq(_r(UiSelectionInfo.new(), _own(5), 0, UiModes.Armed.REPAIR).kind, UiOrderIntent.Kind.DENIED, "units are not repairable this way")
	t.eq(_r(UiSelectionInfo.new(), UiTarget.ground(1, 1), 0, UiModes.Armed.REPAIR).deny_reason, UiContextResolver.DENY_NOT_REPAIRABLE)


func test_armed_force_fire(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[1, TANK]])
	_is(t, _r(sel, UiTarget.ground(5, 5), 0, UiModes.Armed.FORCE_FIRE), UiOrderIntent.Kind.FORCE_FIRE, [1], "ground")
	var enemy: UiOrderIntent = _r(sel, _enemy(), 0, UiModes.Armed.FORCE_FIRE)
	_is(t, enemy, UiOrderIntent.Kind.ATTACK, [1], "enemy")
	t.check(not enemy.force)
	var own: UiOrderIntent = _r(sel, _own(800), 0, UiModes.Armed.FORCE_FIRE)
	_is(t, own, UiOrderIntent.Kind.ATTACK, [1], "own unit")
	t.check(own.force, "forced flag")


func test_armed_rally(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[31, BARRACKS]], UiSelection.Mode.STRUCTURES)
	_is(t, _r(sel, UiTarget.ground(10240, 12288), 0, UiModes.Armed.RALLY), UiOrderIntent.Kind.SET_RALLY, [31], "selected producers")
	var empty: UiOrderIntent = _r(UiSelectionInfo.new(), UiTarget.ground(1, 2), 0, UiModes.Armed.RALLY)
	t.eq(empty.kind, UiOrderIntent.Kind.NONE, "no selection at all: nothing to do")
	var units_only: UiOrderIntent = _r(_sel([[1, TANK]]), UiTarget.ground(1, 2), 0, UiModes.Armed.RALLY)
	t.eq(units_only.kind, UiOrderIntent.Kind.SET_RALLY)
	t.check(units_only.ids.is_empty(), "no producer selected: empty ids, the bus asks its tab fallback")
	t.eq(_r(sel, _enemy(), 0, UiModes.Armed.RALLY).kind, UiOrderIntent.Kind.DENIED)


func test_waypoint_latch_and_passive_modes(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, TANK]]), UiTarget.ground(1, 1), 0, UiModes.Armed.WAYPOINT)
	_is(t, it, UiOrderIntent.Kind.MOVE, [1], "the latch is not a click mode")
	t.check(it.queued, "but everything it resolves is queued")
	for m: int in [UiModes.Armed.PING, UiModes.Armed.POWER, UiModes.Armed.SUPERWEAPON, UiModes.Armed.PLACE, UiModes.Armed.ABILITY]:
		t.eq(_r(_sel([[1, TANK]]), UiTarget.ground(1, 1), 0, m).kind, UiOrderIntent.Kind.NONE, "mode %d is handled elsewhere" % m)


# ---- mixed selections, determinism ---------------------------------------------------------------------------------
func test_e2_engineer_and_squads(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, ENG], [2, RIFLE], [3, RIFLE]]), _neutral(true))
	t.eq(_kinds(it), [UiOrderIntent.Kind.CAPTURE, UiOrderIntent.Kind.MOVE], "E2: two commands")
	t.eq(it.ids, PackedInt32Array([1]))
	t.eq(it.extra[0].ids, PackedInt32Array([2, 3]))
	t.eq(it.cursor, UiOrderIntent.CUR_INTERACT)


func test_extras_follow_rule_order(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[1, ENG], [2, RIFLE], [3, SCOUT], [4, COLL]]), _neutral(true, true))
	t.eq(_kinds(it), [UiOrderIntent.Kind.CAPTURE, UiOrderIntent.Kind.GARRISON, UiOrderIntent.Kind.MOVE], "capture (2), garrison (3), then move (15)")
	t.eq(it.ids, PackedInt32Array([1]))
	t.eq(it.extra[0].ids, PackedInt32Array([2]))
	t.eq(it.extra[1].ids, PackedInt32Array([3, 4]))


func test_every_unit_ends_in_at_most_one_intent(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[1, TANK], [2, ENG], [3, RIFLE], [4, COLL], [5, SCOUT], [6, JET], [7, APC], [8, AA]])
	for tgt: UiTarget in [_enemy(), UiTarget.ground(1, 1), _own(800), _neutral(true), UiTarget.deposit(1024, 1024)]:
		var seen: Dictionary = {}
		for i: UiOrderIntent in _r(sel, tgt).all_intents():
			for id: int in i.ids:
				t.check(not seen.has(id), "unit %d in one intent only" % id)
				seen[id] = true


func test_determinism(t: TestCtx) -> void:
	var sel: UiSelectionInfo = _sel([[9, RIFLE], [3, TANK], [7, ENG], [1, COLL]])
	var a: UiOrderIntent = _r(sel, _neutral(true, true), Q)
	var b: UiOrderIntent = _r(sel, _neutral(true, true), Q)
	var pa: PackedStringArray = PackedStringArray()
	var pb: PackedStringArray = PackedStringArray()
	for i: UiOrderIntent in a.all_intents():
		pa.append(i.describe())
	for i: UiOrderIntent in b.all_intents():
		pb.append(i.describe())
	t.eq(pa, pb, "identical inputs give identical intents")
	for i: UiOrderIntent in a.all_intents():
		for k: int in range(1, i.ids.size()):
			t.lt(i.ids[k - 1], i.ids[k], "ids ascending")


func test_intent_metadata(t: TestCtx) -> void:
	var it: UiOrderIntent = _r(_sel([[7, TANK], [3, RIFLE]]), UiTarget.ground(1, 1))
	t.eq(it.def_idx, 103, "the primary def of the intent's first unit")
	t.eq(UiContextResolver.cursor_for(it), UiOrderIntent.CUR_MOVE)
	t.eq(UiOrderIntent.cursor_of(UiOrderIntent.Kind.ATTACK_MOVE), UiOrderIntent.CUR_ATTACK_MOVE)
	t.eq(UiOrderIntent.cursor_of(UiOrderIntent.Kind.GUARD), UiOrderIntent.CUR_GUARD)
	t.eq(UiOrderIntent.cursor_of(UiOrderIntent.Kind.SELL), UiOrderIntent.CUR_SELL)
	t.eq(UiOrderIntent.marker_of(UiOrderIntent.Kind.PATROL), UiOrderIntent.MK_MOVE)
	t.eq(UiOrderIntent.marker_of(UiOrderIntent.Kind.SET_RALLY), UiOrderIntent.MK_RALLY)
	t.eq(UiOrderIntent.marker_of(UiOrderIntent.Kind.STOP), UiOrderIntent.MK_NONE)


# ---- caps of real defs and make_target over the fixture --------------------------------------------------------------
func test_caps_of_real_defs(t: TestCtx) -> void:
	var d: GameData = UiSimPortFixture.shared_data()
	var caps := UiUnitCaps.new()
	caps.setup(d, null)
	var tank: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.napc.guardian_tank"))
	t.check((tank & (UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE)) == (UiUnitCaps.CAP_ARMED | UiUnitCaps.CAP_HIT_GROUND | UiUnitCaps.CAP_MOBILE | UiUnitCaps.CAP_VEHICLE), "guardian tank: %s" % UiUnitCaps.describe(tank))
	t.check((tank & UiUnitCaps.CAP_HIT_AIR) == 0, "a tank cannot hit air")
	var aa: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.napc.sentinel_aa"))
	t.check((aa & UiUnitCaps.CAP_HIT_AIR) != 0, "sentinel AA hits air: %s" % UiUnitCaps.describe(aa))
	var eng: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.shared.engineer"))
	t.check((eng & UiUnitCaps.CAP_CAPTURE) != 0 and (eng & UiUnitCaps.CAP_ARMED) == 0, "engineer: %s" % UiUnitCaps.describe(eng))
	var coll: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.shared.collector"))
	t.check((coll & UiUnitCaps.CAP_COLLECTOR) != 0, "collector: %s" % UiUnitCaps.describe(coll))
	var mcv: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.shared.mobile_construction_vehicle"))
	t.check((mcv & UiUnitCaps.CAP_MCV) != 0 and (mcv & UiUnitCaps.CAP_DEPLOY) != 0 and (mcv & UiUnitCaps.CAP_MOBILE) != 0, "MCV: %s" % UiUnitCaps.describe(mcv))
	var apc: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.napc.beaver_amphibious_apc"))
	t.check((apc & UiUnitCaps.CAP_TRANSPORT) != 0 and (apc & UiUnitCaps.CAP_PASSENGER) == 0, "APC: %s" % UiUnitCaps.describe(apc))
	var rifle: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.napc.rifle_squad"))
	t.check((rifle & (UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_GARRISON | UiUnitCaps.CAP_PASSENGER)) == (UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_GARRISON | UiUnitCaps.CAP_PASSENGER), "rifle squad: %s" % UiUnitCaps.describe(rifle))
	var jet: int = caps.caps_of(UiSimPort.KIND_UNIT, d.unit_idx("unit.napc.falcon_interceptor"))
	t.check((jet & UiUnitCaps.CAP_AIR) != 0, "interceptor is air: %s" % UiUnitCaps.describe(jet))
	var bar: int = caps.caps_of(UiSimPort.KIND_STRUCTURE, d.structure_idx("structure.shared.barracks"))
	t.check((bar & (UiUnitCaps.CAP_STRUCTURE | UiUnitCaps.CAP_PRODUCER | UiUnitCaps.CAP_SELLABLE)) == (UiUnitCaps.CAP_STRUCTURE | UiUnitCaps.CAP_PRODUCER | UiUnitCaps.CAP_SELLABLE), "barracks: %s" % UiUnitCaps.describe(bar))
	t.check((bar & UiUnitCaps.CAP_MOBILE) == 0)
	t.eq(caps.caps_of(UiSimPort.KIND_UNIT, -1), 0)
	t.check(UiUnitCaps.hits(tank, 0) and not UiUnitCaps.hits(tank, 1) and UiUnitCaps.hits(aa, 1))


class FakeView extends RefCounted:
	var pick_id: int = -1
	var ground: Vector3 = Vector3(45.0, 0.0, 90.0)
	var picks: Array[Vector2] = []

	func pick(screen: Vector2, _filter: int = 0xFF) -> int:
		picks.append(screen)
		return pick_id

	func pick_ground(_screen: Vector2) -> Vector3:
		return ground

	func world_to_sim(p: Vector3) -> Vector2i:
		return UiCmdCodec.world_to_sim(p.x, p.z, 128, 128)


func test_make_target_over_fixture(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file("hud_mid_match")
	var v := FakeView.new()
	v.pick_id = 2001
	var enemy: UiTarget = UiContextResolver.make_target(f, v, Vector2(10, 10), 0)
	t.eq(enemy.kind, UiTarget.Kind.ENEMY)
	t.eq(enemy.eid, 2001)
	t.check(enemy.visible and not enemy.ghost)
	t.check(enemy.damaged, "500 / 700 hp")
	t.eq(enemy.hp_permille, 714)
	v.pick_id = 2003
	var ghost: UiTarget = UiContextResolver.make_target(f, v, Vector2(10, 10), 0)
	t.check(ghost.ghost and not ghost.visible, "a remembered structure is a ghost")
	t.eq(ghost.entity_kind, UiTarget.EntityKind.STRUCTURE)
	v.pick_id = 3001
	t.eq(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).kind, UiTarget.Kind.ALLY)
	v.pick_id = 1001
	t.eq(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).kind, UiTarget.Kind.OWN)
	v.pick_id = 88
	var fac: UiTarget = UiContextResolver.make_target(f, v, Vector2.ZERO, 0)
	t.check(fac.is_producer, "factory is a producer")
	v.pick_id = 90
	t.check(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).is_refinery, "refinery")


func test_make_target_ground_and_deposit(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.load_file("hud_mid_match")
	var v := FakeView.new()
	v.ground = Vector3(45.0, 0.0, 90.0)
	var g: UiTarget = UiContextResolver.make_target(f, v, Vector2.ZERO, 0)
	t.eq(g.kind, UiTarget.Kind.GROUND)
	t.eq(Vector2i(g.x, g.y), Vector2i(15360, 30720))
	t.gt(g.passable_mask, 0, "every move class can stand on open ground")
	f.set_blocked(15, 30)
	t.eq(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).passable_mask, 0, "a blocked cell allows no class")
	v.ground = Vector3(48.5 * 3.0, 0.0, 17.5 * 3.0)
	var dep: UiTarget = UiContextResolver.make_target(f, v, Vector2.ZERO, 0)
	t.eq(dep.kind, UiTarget.Kind.DEPOSIT, "explored deposit cell")
	t.eq(Vector2i(dep.x, dep.y), Vector2i(49664, 17920), "E4: the cell centre")
	f.set_visibility(48, 17, UiSimPort.Vis.SHROUD)
	t.eq(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).kind, UiTarget.Kind.GROUND, "an unexplored deposit cell is plain ground")
	v.ground = Vector3(INF, INF, INF)
	t.eq(UiContextResolver.make_target(f, v, Vector2.ZERO, 0).kind, UiTarget.Kind.NONE, "a miss is off-map")


func test_make_target_neutrals(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada")
	f.set_viewer(0)
	var sub: UiEntityRow = f.spawn("neutral.substation", -1, 1000, 1000, 61)
	t.check(sub.capturable, "the substation is capturable")
	var civ: UiEntityRow = f.spawn("neutral.civilian_garrison", -1, 2000, 1000, 62)
	t.gt(civ.garrison_free, 0, "the civilian building has garrison slots")
	var v := FakeView.new()
	v.pick_id = 61
	var ts: UiTarget = UiContextResolver.make_target(f, v, Vector2.ZERO, 0)
	t.eq(ts.kind, UiTarget.Kind.NEUTRAL)
	t.check(ts.capturable and not ts.garrisonable)
	v.pick_id = 62
	var tc: UiTarget = UiContextResolver.make_target(f, v, Vector2.ZERO, 0)
	t.check(tc.garrisonable, "garrison slot free")
	# full pipeline: an engineer captures the substation
	var eng: UiEntityRow = f.spawn("unit.shared.engineer", 0, 3000, 3000, 63)
	var sel := UiSelection.new()
	sel.replace(PackedInt32Array([eng.id]), f)
	v.pick_id = 61
	var it: UiOrderIntent = UiContextResolver.resolve(UiSelectionInfo.build(sel, f), UiContextResolver.make_target(f, v, Vector2.ZERO, 0), 0, UiModes.Armed.NONE)
	_is(t, it, UiOrderIntent.Kind.CAPTURE, [63], "pick -> target -> selection info -> resolver")
