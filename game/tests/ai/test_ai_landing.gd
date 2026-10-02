extends RefCounted
## AIX1 amphibious assault (ai.md 5.10.1 / 5.10.2, S9): the decision (`consider`: land maps never land; a missing land route asks for
## docks and Landing Transports; a route that is at least 25 % shorter over water launches a TRANSPORT_ASSAULT roster) and the
## op's state machine on a coast map with real transports: assemble, load, cross, unload, hand the landed force to an attack op.

const COAST: int = 2


## A route graph that reports "no land route" for every land class (the generator never produces a split map).
class NoLandRoute extends AiRouteGraph:
	func connected(fx: int, fy: int, tx: int, ty: int, mc: int) -> bool:
		if mc == AiTypes.MoveClass.TRACKED or mc == AiTypes.MoveClass.WHEELED or mc == AiTypes.MoveClass.FOOT:
			return false
		return super.connected(fx, fy, tx, ty, mc)


func _coast(rosters: PackedStringArray, levels: Array, ticks: int, seed_v: int = 2) -> Dictionary:
	return AiXKit.match_of(rosters, levels, ticks, {"seed": seed_v, "family": COAST})


func _budget() -> AiBudget:
	var bg: AiBudget = AiBudget.new()
	bg.reset(1000000, 1000000)
	return bg


func _target(m: Dictionary) -> Dictionary:
	var eh: PackedInt32Array = AiXKit.home(m, 1)
	return {"x": eh[0], "y": eh[1], "eid": -1, "value": 2000, "ratio": 400}


func test_land_maps_never_use_the_landing_op(t: TestCtx) -> void:
	# an open map: a connected land route and no TRANSPORT_ASSAULT doctrine => not applicable
	var m: Dictionary = AiXKit.match_of(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 1], 300)
	var force: PackedInt32Array = AiXKit.brain(m, 0).squads().reserve.units.duplicate()
	var r: int = AiOpLanding.consider(AiXKit.ctx(m, 0), AiXKit.brain(m, 0), _budget(), force, _target(m), 400)
	t.eq(r, 0, "a land-connected target never needs a landing")
	# even a TRANSPORT_ASSAULT roster needs a water route that is 25 % shorter
	var m2: Dictionary = AiXKit.match_of(PackedStringArray(["roster.napc.canada", AiXKit.R_NEC]), [1, 1], 300, {"family": 0})
	var c2: AiContext = AiXKit.ctx(m2, 0)
	t.check(c2.pers.has_flag(AiTypes.doctrine_bit("TRANSPORT_ASSAULT")))
	var r2: int = AiOpLanding.consider(c2, AiXKit.brain(m2, 0), _budget(), AiXKit.brain(m2, 0).squads().reserve.units.duplicate(), _target(m2), 400)
	t.eq(r2, 0, "no water on an open map: no landing")


func test_missing_land_route_asks_for_a_dock_and_transports(t: TestCtx) -> void:
	# S9: needs_water(primary), an NAPC roster without amphibious combat units => wants for a Dock and Landing Transports, wave held
	var m: Dictionary = _coast(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 3000)
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	c.kb.route = _no_land(c)
	var r: int = AiOpLanding.consider(c, b, _budget(), b.squads().reserve.units.duplicate(), _target(m), 400)
	t.eq(r, 2, "a landing is needed and cannot be prepared yet")
	var eco: AiEconomy = b.eco()
	var dock_want: bool = false
	var lt_want: bool = false
	for w: AiWant in eco.wants:
		if w.kind == AiTypes.WantKind.UNIT_ROLE and w.role == AiTypes.R_LANDING_TRANSPORT:
			lt_want = true
		if w.kind == AiTypes.WantKind.STRUCT and c.res.kind_of_structure(w.def) == AiTypes.StructKind.DOCK:
			dock_want = true
	t.check(lt_want, "Landing Transports are wanted")
	t.check(dock_want or eco.struct_own[c.res.structure_of_kind(AiTypes.StructKind.DOCK)] > 0, "a Dock is wanted (or stands)")
	t.gt(b.stat("landing_requests"), 0)


func _no_land(c: AiContext) -> AiRouteGraph:
	var g: NoLandRoute = NoLandRoute.new()
	var base: AiRouteGraph = c.kb.route
	g.block_cells = base.block_cells
	g.min_open_pct = base.min_open_pct
	g.threat_weight_q8 = base.threat_weight_q8
	g.choke_open_max = base.choke_open_max
	g.bw = base.bw
	g.bh = base.bh
	g.map_w = base.map_w
	g.map_h = base.map_h
	g._passable_fn = base._passable_fn
	g.threat = base.threat
	g.tick_hint = base.tick_hint
	return g


func test_landing_op_carries_infantry_across_the_water(t: TestCtx) -> void:
	var m: Dictionary = _coast(PackedStringArray([AiXKit.R_NAPC, AiXKit.R_NEC]), [1, 0], 600)
	var w: SimWorld = AiXKit.world(m)
	var c: AiContext = AiXKit.ctx(m, 0)
	var b: AiBrain = AiXKit.brain(m, 0)
	var tgt: Dictionary = _target(m)
	var lz: PackedInt32Array = AiOpLanding.find_lz(c, int(tgt["x"]), int(tgt["y"]), _budget())
	t.check(not lz.is_empty(), "a landing zone within 20 cells of the target exists")
	if lz.is_empty():
		return
	var d_lz: int = AiForce.cells(lz[0], lz[1], int(tgt["x"]), int(tgt["y"]))
	t.le(d_lz, 30, "the LZ is close to the target (%d cells)" % d_lz)
	t.check(w.map.is_water(lz[0] / 1024 + 2, lz[1] / 1024) or w.map.is_water(lz[0] / 1024 - 2, lz[1] / 1024) \
		or w.map.is_water(lz[0] / 1024, lz[1] / 1024 + 2) or w.map.is_water(lz[0] / 1024, lz[1] / 1024 - 2), "the LZ is a shore cell")
	# a force at the shore next to the base: 6 riflemen and 2 Landing Transports
	var h: PackedInt32Array = AiXKit.home(m, 0)
	var cargo: PackedInt32Array = PackedInt32Array()
	for i: int in 6:
		cargo.append(AiXKit.spawn(m, "unit.napc.rifle_squad", 0, h[0] + (4 + i) * 900, h[1] + 4 * 1024, 200))
	var trans: PackedInt32Array = PackedInt32Array()
	for k: int in 2:
		trans.append(AiXKit.spawn(m, "unit.shared.landing_transport", 0, h[0] + 8 * 1024 + k * 1500, h[1] + 5 * 1024, 900))
	AiXKit.settle(m)
	var op: AiOpLanding = AiOpLanding.new()
	op.wave_tgt = tgt
	op.wave_ratio = 400
	op.tx = int(tgt["x"])
	op.ty = int(tgt["y"])
	op.lz_x = lz[0]
	op.lz_y = lz[1]
	op.transports = trans
	op.cargo = cargo
	t.check(b.add_op(c, op), "the landing op starts")
	AiSoakKit.play(m, 4200)
	t.check((op.seen_mask & (1 << AiTypes.OpState.STAGING)) != 0, "the cargo was loaded (LOAD state reached)")
	t.check((op.seen_mask & (1 << AiTypes.OpState.ADVANCING)) != 0, "the fleet crossed (CROSS state reached)")
	t.check((op.seen_mask & (1 << AiTypes.OpState.ENGAGING)) != 0, "the transports unloaded (UNLOAD state reached)")
	t.gt(op.landed_n, 0, "cargo left the transports at the landing zone")
	t.gt(b.stat("landing_landed"), 0, "the landed force was handed to an attack op")
	t.eq(op.state, AiTypes.OpState.DONE, "the landing op is done")
	t.eq((m["errors"] as PackedStringArray).size(), 0, "no engine errors")


func test_docks_only_for_naval_doctrine_or_water_routes(t: TestCtx) -> void:
	# PD (naval 45, TRANSPORT_ASSAULT) on a coast map with shore starts wants a Dock; on an open map nobody does
	var coast: Dictionary = AiXKit.match_of(PackedStringArray(["roster.pd.vanilla", AiXKit.R_NEC]), [1, 0], 9000,
		{"seed": 100, "family": COAST, "map_params": {"start_near_water": true}})
	var b: AiBrain = AiXKit.brain(coast, 0)
	var wanted: int = b.stat("dock_wanted_1") + b.stat("dock_wanted_3")
	var dock_def: int = AiXKit.ctx(coast, 0).res.structure_of_kind(AiTypes.StructKind.DOCK)
	t.check(wanted > 0 or b.eco().struct_own[dock_def] > 0, "the naval roster on a shore map builds a Dock")
	var open: Dictionary = AiXKit.match_of(PackedStringArray(["roster.pd.vanilla", AiXKit.R_NEC]), [1, 0], 9000, {"seed": 100, "family": 0})
	var b2: AiBrain = AiXKit.brain(open, 0)
	var d2: int = AiXKit.ctx(open, 0).res.structure_of_kind(AiTypes.StructKind.DOCK)
	t.eq(b2.stat("dock_wanted_1") + b2.stat("dock_wanted_2") + b2.stat("dock_wanted_3"), 0, "no Dock wanted on a land map")
	t.eq(b2.eco().struct_own[d2], 0, "and none built")
	t.eq((coast["errors"] as PackedStringArray).size() + (open["errors"] as PackedStringArray).size(), 0)
