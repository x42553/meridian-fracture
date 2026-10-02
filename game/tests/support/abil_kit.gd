class_name AbilKit
extends RefCounted
## Test helpers of the abilities domain: a private copy of the small test data with abilities and effects attached,
## worlds with the REAL abilities / vision / combat stages (movement off: tests move units with world.set_pos), spawn
## shortcuts, effect builders and event readers.

const CELL: int = 1024
const AK := preload("res://src/sim/abilities/sim_ability_consts.gd")


## Fresh small_data() (private: mutate freely; unarmed unless `armed`). Rifleman = stationary camouflage (delay 120), Collector = moving
## camouflage with reveal_t 120 (Dune Rover), Tank = detector 5 cells, Turret = detector 4 cells (Watchtower),
## Tank2 = submarine (submerge). Sights: rifleman 7 cells, tank 9, turret 8.
static func data(armed: bool = false) -> GameData:
	var d: GameData = DefTestKit.small_data()
	if not armed:  # nobody shoots: tests drive last_fire_tick / last_hit_tick by hand
		var lists: Array = [d.units, d.structures]
		for r: DefRoster in d.rosters:
			lists.append(r.units)
			lists.append(r.structures)
		for l: Variant in lists:
			for x: Variant in l:
				if x != null and x.weapons != null:
					x.weapons.clear()
					if x is DefUnit:
						(x as DefUnit).max_range = 0
	add_ability(d, DefTestKit.U_RIFLEMAN, DefEnums.AbilityKind.CAMOUFLAGE, {
		"delay_t": 120, "needs_stationary": true, "needs_no_attack": true, "moving_ok": false, "reveal_on_fire": true,
		"reveal_on_damage": true, "reveal_t": 0, "keeps_abilities_active": false})
	add_ability(d, DefTestKit.U_COLLECTOR, DefEnums.AbilityKind.CAMOUFLAGE, {
		"delay_t": 120, "needs_stationary": false, "needs_no_attack": true, "moving_ok": true, "reveal_on_fire": true,
		"reveal_on_damage": true, "reveal_t": 120, "keeps_abilities_active": false})
	add_ability(d, DefTestKit.U_TANK, DefEnums.AbilityKind.DETECTOR, {"radius_u": 5120})
	add_ability(d, DefTestKit.U_TANK2, DefEnums.AbilityKind.SUBMERGE, {"surface_t": 160})
	add_ability(d, DefTestKit.S_TURRET, DefEnums.AbilityKind.DETECTOR, {"radius_u": 4096}, true)
	var ti: int = d.structure_idx(DefTestKit.S_TURRET)  # an unpowered Watchtower: no power stage in these worlds
	d.structures[ti].flags &= ~DefEnums.SF_POWERED_DEFENSE
	for r3: DefRoster in d.rosters:
		if r3.has_structure(ti):
			r3.structure(ti).flags &= ~DefEnums.SF_POWERED_DEFENSE
	set_sight(d, DefTestKit.U_RIFLEMAN, 7168)
	set_sight(d, DefTestKit.U_TANK, 9216)
	set_sight(d, DefTestKit.S_TURRET, 8192, true)
	return d


## Adds an ability to the base def and to every roster clone.
static func add_ability(d: GameData, def_id: String, kind: int, params: Dictionary, structure: bool = false) -> void:
	var lists: Array = []
	if structure:
		lists.append(d.structures[d.structure_idx(def_id)])
		for r: DefRoster in d.rosters:
			if r.has_structure(d.structure_idx(def_id)):
				lists.append(r.structure(d.structure_idx(def_id)))
	else:
		lists.append(d.units[d.unit_idx(def_id)])
		for r2: DefRoster in d.rosters:
			if r2.has_unit(d.unit_idx(def_id)):
				lists.append(r2.unit(d.unit_idx(def_id)))
	for u: Variant in lists:
		var a: DefAbility = DefAbility.new()
		a.kind = kind
		a.slot = (u.abilities as Array).size()
		a.params = params.duplicate()
		u.abilities.append(a)
		u.ability_slot_of_kind[kind] = a.slot
		u.ability_mask |= 1 << kind
		if kind == DefEnums.AbilityKind.DETECTOR:
			u.detect_radius = int(params.get("radius_u", 5120))


static func set_sight(d: GameData, def_id: String, sight_u: int, structure: bool = false) -> void:
	if structure:
		var si: int = d.structure_idx(def_id)
		d.structures[si].sight = sight_u
		for r: DefRoster in d.rosters:
			if r.has_structure(si):
				r.structure(si).sight = sight_u
		return
	var ui: int = d.unit_idx(def_id)
	d.units[ui].sight = sight_u
	for r2: DefRoster in d.rosters:
		if r2.has_unit(ui):
			r2.unit(ui).sight = sight_u


## World on `d` (default data()): rules fog on, no start entities, movement off. o: players (2), teams, rules (merged),
## opts, seed.
static func world(o: Dictionary = {}, d: GameData = null) -> SimWorld:
	var data_: GameData = d if d != null else data()
	var rules: Dictionary = {"start_mode": SimMatchRules.START_NONE, "victory": 0, "neutral_structures": 0, "fog": true}
	for k: Variant in (o.get("rules", {}) as Dictionary).keys():
		rules[k] = o["rules"][k]
	var cfg: SimMatchConfig = SimTestKit.make_config(int(o.get("players", 2)), int(o.get("seed", 7)), rules, o.get("teams", PackedInt32Array()))
	var opts: Dictionary = (o.get("opts", {}) as Dictionary).duplicate()
	var dis: Array = (opts.get("disable", []) as Array).duplicate()
	if not dis.has("SimMovementSystem"):
		dis.append("SimMovementSystem")
	opts["disable"] = dis
	return SimWorld.create(data_, cfg, SimTestKit.make_map(), opts)


static func spawn(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_unit(w.data.unit_idx(id), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2, 0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)


static func spawn_struct(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_structure(w.data.structure_idx(id), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2)


static func rifle(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return spawn(w, DefTestKit.U_RIFLEMAN, owner, cx, cy)


static func tank(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return spawn(w, DefTestKit.U_TANK, owner, cx, cy)


## Moves an entity by whole cells at once (movement is off).
static func teleport_cell(w: SimWorld, e: SimEntity, cx: int, cy: int) -> void:
	w.set_pos(e, cx * CELL + CELL / 2, cy * CELL + CELL / 2)


static func run_to(w: SimWorld, t: int) -> void:
	while w.tick < t:
		w.step()


# ---- effects ----
## Registers a DefEffect on zone 0 of the world's data BEFORE world creation (data must be the private copy).
static func fx_stat(stat: int, delta_bp: int, group: int = -1, dur_t: int = 0) -> DefEffect:
	var e: DefEffect = DefEffect.new()
	e.op = DefEnums.EffectOp.STAT_MOD
	e.stat = stat
	e.delta_bp = delta_bp
	e.stack_group = group
	e.duration_t = dur_t
	return e


static func fx_op(op: int, delta_bp: int = 0, params: Dictionary = {}, dur_t: int = 0) -> DefEffect:
	var e: DefEffect = DefEffect.new()
	e.op = op
	e.delta_bp = delta_bp
	e.params = params
	e.duration_t = dur_t
	return e


## Appends effects to zone 0 (timed-effect table) of `d`; returns them for index lookup after the world exists.
static func add_zone_effects(d: GameData, list: Array[DefEffect]) -> void:
	for f: DefEffect in list:
		d.zones[0].effects.append(f)


## Appends effects to research 0 (conditional effects are bound through DefLayer3 by bind_cond()).
static func add_research_effects(d: GameData, list: Array[DefEffect]) -> void:
	for f: DefEffect in list:
		d.research[0].effects.append(f)


## Makes `fx` a conditional research effect of the player's unit def (what DefLayer3 does for a completed research).
static func bind_cond(w: SimWorld, pid: int, def_id: String, fx: DefEffect) -> void:
	var l3: DefLayer3 = w.players[pid].view.layer3
	var ui: int = w.data.unit_idx(def_id)
	if not l3._cond_units.has(ui):
		l3._cond_units[ui] = []
	(l3._cond_units[ui] as Array).append(fx)
	l3.version += 1


static func fx_index(w: SimWorld, fx: DefEffect) -> int:
	return w.abilities.fx_table.index_of(fx)


static func events(w: SimWorld, type: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for i: int in w.events.count():
		var r: PackedInt32Array = w.events.data.slice(i * SimEvent.STRIDE, (i + 1) * SimEvent.STRIDE)
		if r[SimEvent.I_TYPE] == type:
			out.append(r)
	return out
