extends RefCounted
## Kernel model types (SC-04): flags, tags, orders, hash coverage (DR-13), component / system stubs, SimDefs
## against the data domain's DefTestKit.small_data(), and the SimWorld enums.


## Reflection guard of DR-13 (the real one lives in SimTestKit, SC-12): perturb every int / String script variable
## and require the digest of hash_into to change exactly for the non-exempt ones. Returns the problems.
func _coverage(cls: GDScript, exempt: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var o: Object = cls.new()
	var buf: PackedInt32Array = PackedInt32Array()
	o.call("hash_into", buf)
	var base: int = Checksum.digest32(buf)
	for p: Dictionary in o.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		var v: Variant = o.get(n)
		if typeof(v) == TYPE_INT:
			o.set(n, (v as int) + 1)
		elif typeof(v) == TYPE_STRING:
			o.set(n, (v as String) + "x")
		else:
			continue
		buf = PackedInt32Array()
		o.call("hash_into", buf)
		var changed: bool = Checksum.digest32(buf) != base
		o.set(n, v)
		if changed and exempt.has(n):
			problems.append("%s is exempt but hashed" % n)
		elif not changed and not exempt.has(n):
			problems.append("%s is not hashed" % n)
	return problems


func test_flags(t: TestCtx) -> void:
	t.eq(SimFlags.F_GONE, 3, "F_GONE = F_DEAD | F_REMOVING")
	t.eq(SimFlags.F_DEAD, 1, "F_DEAD")
	t.eq(SimFlags.F_EXPIRE_KILLS, 1 << 15, "bit 15")
	t.eq(SimFlags.F_SELLING, 1 << 30, "bit 30")
	t.eq(SimFlags.F_NO_CAPTURE, 1 << 32, "bit 32")
	t.eq(SimFlags.F_NO_FOOTPRINT, 1 << 35, "bit 35")
	t.eq(SimFlags.F_UNDER_CONSTRUCTION, 1 << 40, "bit 40")
	var all: PackedInt64Array = [
		SimFlags.F_DEAD, SimFlags.F_REMOVING, SimFlags.F_INSIDE, SimFlags.F_TEMPORARY, SimFlags.F_SUMMONED, SimFlags.F_NO_UNIT_CAP,
		SimFlags.F_DECOY, SimFlags.F_NO_COLLISION, SimFlags.F_INVULNERABLE, SimFlags.F_UNTARGETABLE, SimFlags.F_NO_SELECT,
		SimFlags.F_TETHERED, SimFlags.F_HAS_CHILDREN, SimFlags.F_NO_SALVAGE, SimFlags.F_INITIAL, SimFlags.F_EXPIRE_KILLS,
		SimFlags.F_MOVING, SimFlags.F_AIRBORNE, SimFlags.F_BLOCKED, SimFlags.F_ON_WATER, SimFlags.F_FIRING, SimFlags.F_ENGAGED,
		SimFlags.F_WEAPONS_OFF, SimFlags.F_DEPLOYED, SimFlags.F_DEPLOYING, SimFlags.F_CLOAKED, SimFlags.F_ABILITY_ACTIVE,
		SimFlags.F_POWERED, SimFlags.F_REPAIR_ON, SimFlags.F_SELLING, SimFlags.F_NO_CAPTURE, SimFlags.F_NO_REPAIR,
		SimFlags.F_NO_VISION_GRANT, SimFlags.F_NO_FOOTPRINT, SimFlags.F_SCRIPTED_MOVE, SimFlags.F_EMP_SHUT, SimFlags.F_SUPPRESSED,
		SimFlags.F_GARRISONED, SimFlags.F_UNDER_CONSTRUCTION,
	]
	var seen: int = 0
	var clash: bool = false
	for f: int in all:
		if (seen & f) != 0 or f == 0:
			clash = true
		seen |= f
	t.check_false(clash, "39 distinct single bits")
	t.eq(all.size(), 39, "39 flags")


func test_tag(t: TestCtx) -> void:
	var e: SimEntity = SimEntity.new()
	e.kind = SimEntity.Kind.STRUCTURE
	e.layer = SimEntity.Layer.AIR
	e.owner = 2
	var tag: int = SimTag.of(e)
	t.eq(tag, (1 << 1) | SimTag.ALIVE | (1 << 7) | (1 << 12), "kind | alive | layer | owner")
	e.flags = SimFlags.F_DEAD
	t.eq(SimTag.of(e) & SimTag.ALIVE, 0, "ALIVE cleared by F_DEAD")
	e.flags = SimFlags.F_REMOVING
	t.eq(SimTag.of(e) & SimTag.ALIVE, 0, "ALIVE cleared by F_REMOVING")
	e.owner = -1
	t.eq(SimTag.of(e) & SimTag.ALL_OWNERS, SimTag.NEUTRAL_OWNER, "neutral owner is bit 18")
	t.eq(SimTag.NEUTRAL_OWNER, 1 << 18, "NEUTRAL_OWNER")
	t.eq(SimTag.owner_bit(-1), SimTag.NEUTRAL_OWNER, "owner_bit(-1)")
	t.eq(SimTag.owner_bit(0), 1 << 10, "owner_bit(0)")
	t.eq(SimTag.kind_bit(SimEntity.Kind.NEUTRAL), 1 << 4, "kind_bit")
	t.eq(SimTag.layer_bit(SimEntity.Layer.UNDERWATER), 1 << 9, "layer_bit")
	t.eq(SimTag.ALL_KINDS, 31, "ALL_KINDS")
	t.eq(SimTag.ALL_LAYERS, 0x3C0, "ALL_LAYERS")
	t.check(SimTag.NEUTRAL_OWNER < (1 << 31), "fits the spatial hash's int32 tag")


func test_entity_hash_coverage(t: TestCtx) -> void:
	t.eq(_coverage(SimEntity, SimEntity.HASH_EXEMPT), PackedStringArray(), "SimEntity: only the documented exempt fields are unhashed")


func test_player_hash_coverage(t: TestCtx) -> void:
	t.eq(_coverage(SimPlayer, SimPlayer.HASH_EXEMPT), PackedStringArray(), "SimPlayer: only the documented exempt fields are unhashed")


func test_order_hash_coverage(t: TestCtx) -> void:
	t.eq(_coverage(SimOrder, SimOrder.HASH_EXEMPT), PackedStringArray(), "SimOrder: only `fail` is unhashed")


func test_entity_hash_details(t: TestCtx) -> void:
	var e: SimEntity = SimEntity.new()
	var b0: PackedInt32Array = PackedInt32Array()
	e.hash_into(b0)
	t.eq(b0.size(), 21 + 1 + 1, "21 scalar words + order count + component mask")
	e.flags = 1 << 34
	var b1: PackedInt32Array = PackedInt32Array()
	e.hash_into(b1)
	t.ne(Checksum.digest32(b1), Checksum.digest32(b0), "flag bit 34 (high word) is hashed")
	e.flags = 0
	e.orders.append(SimOrder.new(SimOrder.T_MOVE, 0, 5, 6))
	var b2: PackedInt32Array = PackedInt32Array()
	e.hash_into(b2)
	t.eq(b2.size(), b0.size() + 11, "an order adds its 11 words")
	e.orders.clear()
	e.move = SimCompMove.new()
	var b3: PackedInt32Array = PackedInt32Array()
	e.hash_into(b3)
	t.eq(b3[b0.size() - 1], 1, "mask bit 0 = move (the mask precedes the components)")
	e.summon = SimCompSummon.new()
	var b4: PackedInt32Array = PackedInt32Array()
	e.hash_into(b4)
	t.eq(b4[b0.size() - 1], 1 | 1024, "mask bit 10 = summon")


func test_player_hash_details(t: TestCtx) -> void:
	var p: SimPlayer = SimPlayer.new()
	var b0: PackedInt32Array = PackedInt32Array()
	p.hash_into(b0)
	t.eq(b0.size(), 33 + 1 + 1, "33 words + view checksum + component mask")
	p.econ = SimPlayerEcon.new()
	p.vis = SimPlayerVision.new()
	var b1: PackedInt32Array = PackedInt32Array()
	p.hash_into(b1)
	t.eq(b1[34], 5, "comp_mask econ=1, vis=4 (right after the view checksum; the components follow)")
	p.name = "renamed"
	var b2: PackedInt32Array = PackedInt32Array()
	p.hash_into(b2)
	t.eq(b2, b1, "the name is never hashed")


## Components a domain has filled (economy, movement, abilities / vision, combat): they hash real state, so the
## empty-stub assertions below do not apply. Add a class here when its domain fills it.
static func _filled_components() -> Array:
	return [
		SimCompMove, SimCompCombat, SimCompAir, SimCompCarrier, SimCompEcon, SimCompProd, SimCompAbility, SimCompStats,
		SimCompVision, SimCompCargo, SimCompSummon, SimPlayerFx, SimPlayerEcon,
	]


func test_components_instantiate(t: TestCtx) -> void:
	var comps: Array = [SimCompMove, SimCompCombat, SimCompAir, SimCompCarrier, SimCompEcon, SimCompProd, SimCompAbility,
		SimCompStats, SimCompVision, SimCompCargo, SimCompSummon, SimPlayerEcon, SimPlayerFx, SimPlayerVision]
	t.eq(comps.size(), 14, "14 component stubs")
	for cls: GDScript in comps:
		var c: SimComponent = cls.new() as SimComponent
		t.not_null(c, "instantiates")
		var buf: PackedInt32Array = PackedInt32Array()
		c.hash_into(buf)
		if _filled_components().has(cls):  # filled by a domain: it must declare its HASH_EXEMPT list (tests/<domain> cover it)
			t.check(cls.get("HASH_EXEMPT") is PackedStringArray, "%s declares HASH_EXEMPT" % cls.get_global_name())
			continue
		t.eq(buf.size(), 0, "an empty stub hashes nothing")
		t.eq(c.dump(), {} as Dictionary, "and dumps nothing")
		t.eq(cls.get("HASH_EXEMPT"), PackedStringArray(), "declares HASH_EXEMPT")


func test_component_dump_is_reflective(t: TestCtx) -> void:
	# a throw-away subclass proves the base dump() and the coverage helper against a real component shape
	var src: GDScript = GDScript.new()
	src.source_code = "extends SimComponent\nconst HASH_EXEMPT: PackedStringArray = [\"cache\"]\nvar a: int = 3\nvar cache: int = 9\nvar arr: PackedInt32Array = [1, 2]\nfunc hash_into(buf: PackedInt32Array) -> void:\n\tbuf.append(a)\n\tbuf.append_array(arr)\n"
	t.eq(src.reload(), OK, "test component compiles")
	var c: SimComponent = src.new() as SimComponent
	var d: Dictionary = c.dump()
	t.eq(d["a"], 3, "dump has scalars")
	t.eq(d["arr"], PackedInt32Array([1, 2]), "and packed arrays")
	var copy: PackedInt32Array = d["arr"]
	copy.append(3)
	t.eq((c.get("arr") as PackedInt32Array).size(), 2, "packed arrays in the dump are copies")
	t.eq(_coverage(src, PackedStringArray(["cache"])), PackedStringArray(), "coverage helper accepts a correct component")
	t.eq(_coverage(src, PackedStringArray()).size(), 1, "and flags an undeclared derived field")


func test_system_stubs(t: TestCtx) -> void:
	var stubs: Array = [SimProductionSystem, SimEconomySystem, SimPowerSystem, SimMovementSystem, SimAbilitySystem, SimCombatSystem, SimZoneSystem, SimVisionSystem]
	var stages: PackedInt32Array = [2, 3, 4, 6, 7, 8, 9, 10]
	for i: int in stubs.size():
		var cls: GDScript = stubs[i]
		var s: SimSystem = cls.new() as SimSystem
		t.eq(s.stage_no, stages[i], "stage_no of stub %d" % i)
		t.eq(s.stride, 2 if stages[i] == 10 else 1, "stride")
		t.eq(s.system_name(), SimSystem.STAGE_NAMES[stages[i] - 1], "name")
	var base: SimSystem = SimSystem.new()
	t.eq(base.order_gate(null, null, null), 0, "default order_gate is OK")
	t.eq(base.on_debug(null, 0, 4, 0, 0, 0, 0, 0), -1, "default on_debug = not my mode")
	base.update(null)  # no-ops must not raise engine errors (the runner fails the test otherwise)
	base.hash_state(null, PackedInt32Array())
	t.eq(SimSystem.STAGE_NAMES.size(), 11, "11 stage names")
	t.eq(SimSystem.new().system_name(), "stage0", "unassigned stage")
	t.not_null(SimStrategicSystem.new(), "strategic stub")


func test_fog_defaults(t: TestCtx) -> void:
	var f: SimFogApi = SimFogApi.new()
	var e: SimEntity = SimEntity.new()
	t.check(f.cell_visible(0, 1, 1) and f.cell_explored(0, 1, 1), "everything visible")
	t.check(f.entity_visible(0, e) and f.entity_revealed(0, e), "entities visible")
	t.eq(f.fog_bytes(0).size(), 0, "no bytes")
	t.eq(f.ghosts(0).size(), 0, "no ghosts")
	t.eq(f.ghost_version(0) + f.fog_version(0), 0, "versions 0")
	t.check_false(f.decoy_identified(0, e), "no decoys identified")


func test_order_constants(t: TestCtx) -> void:
	t.eq([SimOrder.T_WAIT, SimOrder.T_MOVE, SimOrder.T_PATROL, SimOrder.T_FOLLOW, SimOrder.T_FACE, SimOrder.T_LAND], [1, 16, 17, 18, 19, 20] as Array, "movement types")
	t.eq([SimOrder.T_HARVEST, SimOrder.T_RETURN_CARGO, SimOrder.T_CAPTURE, SimOrder.T_REPAIR, SimOrder.T_SALVAGE, SimOrder.T_DEPLOY_MCV], [30, 31, 32, 33, 34, 35] as Array, "economy types")
	t.eq([SimOrder.T_ATTACK, SimOrder.T_ATTACK_MOVE, SimOrder.T_GUARD, SimOrder.T_HOLD, SimOrder.T_FORCE_FIRE, SimOrder.T_RETURN_BASE], [40, 41, 42, 43, 44, 45] as Array, "combat types")
	t.eq([SimOrder.T_LOAD, SimOrder.T_UNLOAD, SimOrder.T_GARRISON, SimOrder.T_DEPLOY, SimOrder.T_UNDEPLOY, SimOrder.T_USE_ABILITY, SimOrder.T_SET_MODE], [50, 51, 52, 53, 54, 55, 56] as Array, "ability types")
	t.eq([SimOrder.OF_FORCED, SimOrder.OF_CYCLIC, SimOrder.OF_AUTO, SimOrder.OF_NO_FORMATION, SimOrder.OF_SPEED_MATCH, SimOrder.OF_REVERSE_OK], [1, 2, 4, 8, 16, 32] as Array, "flags")
	t.eq([SimOrder.RUNNING, SimOrder.DONE, SimOrder.FAILED, SimOrder.QM_REPLACE, SimOrder.QM_APPEND, SimOrder.QM_FRONT], [0, 1, 2, 0, 1, 2] as Array, "status / queue modes")
	t.eq([SimOrder.END_DONE, SimOrder.END_FAILED, SimOrder.END_CANCELLED, SimOrder.END_REPLACED, SimOrder.END_DIED], [0, 1, 2, 3, 4] as Array, "end reasons")
	t.eq(SimOrder.TYPE_COUNT, 64, "TYPE_COUNT")
	t.eq(SimOrder.new().phase, SimOrder.PH_NEW, "new orders have not begun")
	var o: SimOrder = SimOrder.new(SimOrder.T_ATTACK, 7, 1, 2, 3, 4, SimOrder.OF_FORCED)
	t.eq([o.type, o.target_id, o.x, o.y, o.arg, o.arg2, o.flags], [40, 7, 1, 2, 3, 4, 1] as Array, "constructor arguments")
	var buf: PackedInt32Array = PackedInt32Array()
	o.hash_into(buf)
	t.eq(buf, PackedInt32Array([40, 7, 1, 2, 3, 4, 1, 0, 0, 0, 0]), "order words in spec order")


func test_enum_values(t: TestCtx) -> void:
	t.eq([SimEntity.Kind.UNIT, SimEntity.Kind.STRUCTURE, SimEntity.Kind.WRECK, SimEntity.Kind.ZONE, SimEntity.Kind.NEUTRAL], [0, 1, 2, 3, 4] as Array, "Kind")
	t.eq([SimEntity.Layer.GROUND, SimEntity.Layer.AIR, SimEntity.Layer.SURFACE, SimEntity.Layer.UNDERWATER], [0, 1, 2, 3] as Array, "Layer")
	t.eq([SimPlayer.Controller.HUMAN, SimPlayer.Controller.AI, SimPlayer.Controller.NONE], [0, 1, 2] as Array, "Controller")
	t.eq(SimPlayer.Elim.SCRIPT, 7, "Elim.SCRIPT")
	t.eq(SimPlayer.Elim.KICKED, 4, "Elim.KICKED")
	t.eq(SimWorld.Cause.RESIGN, 5, "Cause.RESIGN")
	t.eq(SimWorld.Cause.SCRIPT, 6, "Cause.SCRIPT")
	t.eq(SimWorld.Rel.NEUTRAL, 3, "Rel.NEUTRAL")
	t.eq(SimWorld.EndReason.DRAW, 2, "EndReason.DRAW")
	t.eq(SimWorld.CHECKSUM_PART_NAMES.size(), 16, "16 checksum parts")
	t.eq(SimWorld.CHECKSUM_PART_NAMES[5], "sys.commands", "part 5")
	t.eq(SimWorld.CHECKSUM_PART_NAMES[15], "sys.cleanup", "part 15")


func test_sim_defs(t: TestCtx) -> void:
	var d: GameData = DefTestKit.small_data()
	var U: int = SimEntity.Kind.UNIT
	var mcv: int = d.unit_idx(DefTestKit.U_MCV)
	var rifle: int = d.unit_idx(DefTestKit.U_RIFLEMAN)
	var tank: int = d.unit_idx(DefTestKit.U_TANK)
	var hq: int = d.structure_idx(DefTestKit.S_HQ)
	d.units[tank].home_layer = SimEntity.Layer.AIR
	d.units[tank].flags |= SimDefs.UF_NON_BLOCKING | SimDefs.UF_NO_REPAIR | SimDefs.UF_NO_CAPTURE | SimDefs.UF_NO_SALVAGE
	var defs: SimDefs = SimDefs.new(d)
	t.check(defs.has_def(U, 5) and not defs.has_def(U, 6) and not defs.has_def(U, -1), "has_def bounds")
	t.check(defs.has_def(SimEntity.Kind.WRECK, rifle), "a wreck names a unit def")
	t.check(defs.has_def(SimEntity.Kind.STRUCTURE, 5) and not defs.has_def(SimEntity.Kind.STRUCTURE, 6), "structures")
	t.check(defs.has_def(SimEntity.Kind.ZONE, 0) and defs.has_def(SimEntity.Kind.NEUTRAL, 0), "zones / neutrals")
	t.check_false(defs.has_def(5, 0), "kind 5 is reserved")
	t.eq(defs.hp_max(null, U, rifle), d.units[rifle].health, "neutral owner: base unit health")
	t.eq(defs.hp_max(null, SimEntity.Kind.STRUCTURE, hq), d.structures[hq].health, "base structure health")
	t.eq(defs.hp_max(null, SimEntity.Kind.ZONE, 0), 0, "zone hp 0 = indestructible")
	t.eq(defs.hp_max(null, SimEntity.Kind.NEUTRAL, 0), d.neutrals[0].health, "neutral health")
	var view: DefPlayerView = DefTestKit.player_view(d, DefTestKit.R_VANILLA)
	t.eq(defs.hp_max(view, U, rifle), view.resolved_stats(DefEnums.Kind.UNIT, rifle)[SimDefs.STAT_HEALTH], "player view: resolved_stats(UNIT, i)[HEALTH]")
	t.eq(defs.hp_max(view, SimEntity.Kind.WRECK, rifle), defs.hp_max(view, U, rifle), "a wreck resolves through the UNIT table")
	t.eq(defs.hp_max(view, SimEntity.Kind.STRUCTURE, hq), view.resolved_stats(DefEnums.Kind.STRUCTURE, hq)[SimDefs.STAT_HEALTH], "structure through kind 1")
	t.eq(defs.radius(U, rifle), d.units[rifle].radius, "radius")
	t.eq(defs.radius(SimEntity.Kind.ZONE, 0), d.zones[0].radius, "zone radius")
	t.eq(defs.home_layer(U, tank), SimEntity.Layer.AIR, "unit home layer")
	t.eq(defs.home_layer(SimEntity.Kind.STRUCTURE, hq), SimEntity.Layer.GROUND, "non-units are GROUND")
	t.eq(defs.cap_weight(U, rifle), 1, "pop 1")
	t.eq(defs.cap_weight(U, mcv), 0, "pop 0 is exempt")
	t.eq(defs.cap_weight(SimEntity.Kind.STRUCTURE, hq), 0, "structures are not capped")
	t.eq(defs.flags_init(U, rifle), 0, "plain unit")
	t.eq(defs.flags_init(U, tank), SimFlags.F_NO_COLLISION | SimFlags.F_NO_REPAIR | SimFlags.F_NO_CAPTURE | SimFlags.F_NO_SALVAGE, "UF_* mapped to F_*")
	t.eq(defs.flags_init(SimEntity.Kind.ZONE, 0), SimFlags.F_UNTARGETABLE | SimFlags.F_NO_SELECT, "zones")
	t.eq(defs.flags_init(SimEntity.Kind.STRUCTURE, hq), 0, "structures")
	t.check(defs.is_rebuilder(U, mcv), "MCV carries DEPLOY_STRUCTURE")
	t.check_false(defs.is_rebuilder(U, rifle), "rifle does not")
	t.check_false(defs.is_rebuilder(SimEntity.Kind.STRUCTURE, hq), "only units")
	t.check_false(defs.is_rebuilder(U, 99), "out of range is false")
	t.eq(SimDefs.DEF_KIND, PackedInt32Array([0, 1, 0, 7, 8]), "DEF_KIND")
	t.eq(SimDefs.DEF_KIND[SimEntity.Kind.ZONE], DefEnums.Kind.ZONE, "DEF_KIND zone == DefEnums.Kind.ZONE")
	t.eq(SimDefs.STAT_HEALTH, DefEnums.Stat.HEALTH, "STAT_HEALTH == DefEnums.Stat.HEALTH")
