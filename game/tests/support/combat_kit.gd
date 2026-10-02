class_name CombatKit
extends RefCounted
## Test helpers of the combat domain: a world with the REAL SimCombatSystem (SimTestKit stubs it by default),
## spawn shortcuts, hand-made warheads, matrix control and event readers.

const CELL: int = SimConfig.CELL


## 2-player world (pid 0 alpha, pid 1 vanilla; enemies) with the real combat system.
static func world(o: Dictionary = {}) -> SimWorld:
	var opts: Dictionary = o.duplicate()
	opts["combat_stub"] = false
	var sw: Dictionary = (opts.get("opts", {}) as Dictionary).duplicate()
	if not sw.has("disable"):
		sw["disable"] = CombatWK.ISOLATE["disable"]  # combat tests stay independent of the abilities / vision stages
	opts["opts"] = sw
	return SimTestKit.make_world(opts)


static func tank(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return SimTestKit.spawn_tank(w, owner, cx * CELL, cy * CELL)


static func rifle(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return SimTestKit.spawn_rifle(w, owner, cx * CELL, cy * CELL)


static func turret(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_structure(SimTestKit.structure_def(DefTestKit.S_TURRET), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2)


## Hand-made warhead: single victim, ground layers, no splash.
static func wh(damage: int, dtype: int = SimCombatConsts.DT_BULLET) -> SimCombatWarhead:
	var w: SimCombatWarhead = SimCombatWarhead.new()
	w.damage = damage
	w.dtype = dtype
	w.layer_mask = 15
	w.splash_edge_bp = 10000
	return w


static func set_matrix(w: SimWorld, dtype: int, armor: int, bp: int) -> void:
	w.combat.matrix_bp[dtype * w.combat.n_armor + armor] = bp


## Compiled def of an entity (shared by every entity of that def and owner: mutate only in throw-away worlds).
static func cdef(w: SimWorld, e: SimEntity) -> SimCombatDef:
	return w.combat.def_for(w, e)


## compute() with attacker-side defaults (static 10000, tmp 0, no falloff, no packet, frontal).
static func compute(w: SimWorld, v: SimEntity, wh_: SimCombatWarhead, base: int, dc: int = SimCombatConsts.DC_DIRECT, o: Dictionary = {}) -> int:
	return SimDamage.compute(w, v, wh_, base, dc, int(o.get("static", 10000)), int(o.get("tmp", 0)), int(o.get("team", 1)),
		bool(o.get("ground", true)), int(o.get("falloff", 10000)), int(o.get("from", 0)), int(o.get("pkt", 0)))


## Events of `type` as 10-int records [type, tick, x, y, a..f].
static func events(w: SimWorld, type: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for i: int in w.events.count():
		var r: PackedInt32Array = w.events.data.slice(i * SimEvent.STRIDE, (i + 1) * SimEvent.STRIDE)
		if r[SimEvent.I_TYPE] == type:
			out.append(r)
	return out


## deal() with defaults: attacker player 0 (no shooter entity), direct hit, no modifiers, frontal, impact at the victim.
static func hit(w: SimWorld, v: SimEntity, wh_: SimCombatWarhead, o: Dictionary = {}) -> int:
	return SimDamage.deal(w, v, wh_, int(o.get("base", wh_.damage)), int(o.get("dc", SimCombatConsts.DC_DIRECT)), int(o.get("df", 0)),
		int(o.get("atk", -1)), int(o.get("pid", 0)), bool(o.get("ground", true)), int(o.get("static", 10000)), int(o.get("tmp", 0)),
		int(o.get("falloff", 10000)), int(o.get("from", 0)), int(o.get("pkt", 0)), v.x, v.y)


## Steps the world until world.tick == t.
static func run_to(w: SimWorld, t: int) -> void:
	while w.tick < t:
		w.step()
