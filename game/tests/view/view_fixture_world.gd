class_name ViewFixtureWorld
extends RefCounted
## VIEW-S1 fixture world. The real kernel is usable now, so this is a thin layer over SimTestKit: a real SimWorld with
## helpers to spawn entities and to hand-build component states for the seam tests. `bare_entity()` is the only
## stand-in: a SimEntity without components (what the readers must survive).

const UNIT_TANK: String = "unit.tst.tank"
const UNIT_RIFLE: String = "unit.tst.rifleman"
const STRUCT_FACTORY: String = "structure.tst.factory"
const STRUCT_HQ: String = "structure.tst.hq"


## A real SimWorld (SimTestKit cast: 2 players, flat 96x96 map, systems installed).
static func make_world(players: int = 2) -> SimWorld:
	return SimTestKit.make_world({"players": players})


## Spawns a unit of the kit's data by id at cell (cx, cy).
static func spawn_unit(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	return SimTestKit.spawn_unit_id(w, id, owner, cx * SimConfig.CELL + SimConfig.CELL / 2, cy * SimConfig.CELL + SimConfig.CELL / 2)


## Spawns a structure by id with its footprint centre at (x, y) sim units.
static func spawn_structure(w: SimWorld, id: String, owner: int, x: int, y: int) -> SimEntity:
	var d: int = SimTestKit.structure_def(id)
	return w.spawn_entity(SimEntity.Kind.STRUCTURE, d, owner, x, y, 0, 0, 0, 0, SimEvent.SPAWN_INITIAL)


## An entity record with no component at all.
static func bare_entity(kind: int = SimEntity.Kind.UNIT) -> SimEntity:
	var e: SimEntity = SimEntity.new()
	e.id = 1
	e.kind = kind
	return e


## Gives `e` a combat component with `n` mounts and the given per-mount relative turret bats.
static func with_combat(e: SimEntity, bats: PackedInt32Array) -> SimEntity:
	var c: SimCompCombat = SimCompCombat.new()
	c.n_mounts = bats.size()
	c.mnt.resize(bats.size() * SimCombatConsts.MS)
	for m: int in bats.size():
		c.mnt[m * SimCombatConsts.MS + SimCombatConsts.M_ANGLE] = bats[m]
	e.combat = c
	return e


## Gives `e` an economy component carrying `cargo` credits and a capture progress in bp.
static func with_econ(e: SimEntity, cargo: int, cap_progress_bp: int = 0) -> SimEntity:
	var c: SimCompEcon = SimCompEcon.new()
	c.cargo = cargo
	c.cap_progress = cap_progress_bp
	e.econ = c
	return e


## Gives `e` a production component with a rally point.
static func with_rally(e: SimEntity, x: int, y: int, target: int) -> SimEntity:
	var c: SimCompProd = SimCompProd.new()
	c.rally_on = true
	c.rally_x = x
	c.rally_y = y
	c.rally_target = target
	e.prod = c
	return e
