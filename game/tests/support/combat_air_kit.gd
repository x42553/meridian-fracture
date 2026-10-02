class_name CombatAirKit
extends RefCounted
## Test helpers of the aircraft tests (CB-08): a world where U_TANK is a fixed-wing bomber (or a rotor gunship) and
## S_BARRACKS is an airfield with N pads, on the real movement / orders / combat systems and a flat 96x96 map.

const C: int = SimConfig.CELL


## Base def + every roster clone of a unit.
static func unit_defs(d: GameData, id: String) -> Array[DefUnit]:
	var idx: int = d.unit_idx(id)
	var out: Array[DefUnit] = [d.units[idx]]
	for r: DefRoster in d.rosters:
		if idx < r.units.size() and r.units[idx] != null:
			out.append(r.units[idx])
	return out


static func structure_defs(d: GameData, id: String) -> Array[DefStructure]:
	var idx: int = d.structure_idx(id)
	var out: Array[DefStructure] = [d.structures[idx]]
	for r: DefRoster in d.rosters:
		if idx < r.structures.size() and r.structures[idx] != null:
			out.append(r.structures[idx])
	return out


## kind "bomber" (fixed wing, bombs: `ammo` salvos of a 6-bomb stick), "gunship" (rotor, hitscan guns, range 5 cells).
static func world(kind: String = "bomber", pads: int = 2, speed: int = 460, ammo: int = 1, players: int = 2) -> SimWorld:
	var d: GameData = DefTestKit.small_data()
	d._data_hash = SimTestKit.DATA_HASH
	for u: DefUnit in unit_defs(d, DefTestKit.U_TANK):
		u.tags = (u.tags & ~(DefEnums.UT_LAND_VEHICLE | DefEnums.UT_TANK)) | DefEnums.UT_AIRCRAFT
		u.move_class = MapTerrain.MC_AIR_HOVER if kind == "gunship" else MapTerrain.MC_AIR_FIXED
		u.size_class = DefEnums.SizeClass.AIR_MEDIUM
		u.home_layer = DefEnums.Layer.AIR
		u.layer_mask = DefEnums.L_AIR
		u.radius = 500
		u.speed = speed
		u.turn_rate = 102
		u.accel_t = 12
		u.health = 500
		u.rearm_t = 240
		u.weapons.clear()
		if kind == "gunship":
			var g: DefWeaponSlot = DefTestKit._slot(d, DefEnums.WeaponArch.SMALL_ARMS, 40, 10000, 5 * C, 0)
			u.weapons.append(g)
		else:
			var b: DefWeaponSlot = DefTestKit._slot(d, DefEnums.WeaponArch.BOMB, 200, 20000, 1536, 0)
			b.proj_kind = DefEnums.ProjKind.BOMB
			b.proj_speed = 512
			b.fire_mode = DefEnums.FireMode.INDIRECT
			b.splash_radius = 1536
			b.splash_edge_bp = 3000
			b.hits_per_volley = 6
			b.ammo_volleys = ammo
			b.target_mask = DefEnums.L_GROUND | DefEnums.L_WATER
			u.weapons.append(b)
	for s: DefStructure in structure_defs(d, DefTestKit.S_BARRACKS):
		s.pads = pads
	var pl: Array = []
	for i: int in players:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": DefTestKit.R_VANILLA,
			"team": i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 4242, "map": {"id": "sim_test_kit"}, "rules": {}, "players": pl})
	var w: SimWorld = SimWorld.create(d, cfg, SimTestKit.make_map(), CombatWK.ISOLATE)
	CombatWK.set_matrix_all(w, 10000)
	return w


static func airfield(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_structure(w.data.structure_idx(DefTestKit.S_BARRACKS), owner, cx * C + C, cy * C + C)


## An aircraft parked on a pad of `af`.
static func parked(w: SimWorld, af: SimEntity) -> SimEntity:
	var e: SimEntity = w.spawn_unit(w.data.unit_idx(DefTestKit.U_TANK), af.owner, af.x, af.y)
	SimAirSortie.on_aircraft_spawned(w, e, af.id)
	return e


## An aircraft already in the air at cell (cx, cy), facing east.
static func flying(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_unit(w.data.unit_idx(DefTestKit.U_TANK), owner, cx * C + C / 2, cy * C + C / 2)


## AIR_* states entered by `e` so far, in order (from the EV_AIR_STATE events).
static func states(w: SimWorld, e: SimEntity) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: PackedInt32Array in CombatKit.events(w, SimCombatConsts.EV_AIR_STATE):
		if r[SimEvent.I_A] == e.id:
			out.append(r[SimEvent.I_B])
	return out


## Tick of the first EV_AIR_STATE of `e` entering `state` at or after `from`, -1 if none.
static func tick_of(w: SimWorld, e: SimEntity, state: int, from: int = 0) -> int:
	for r: PackedInt32Array in CombatKit.events(w, SimCombatConsts.EV_AIR_STATE):
		if r[SimEvent.I_A] == e.id and r[SimEvent.I_B] == state and r[SimEvent.I_TICK] >= from:
			return r[SimEvent.I_TICK]
	return -1
