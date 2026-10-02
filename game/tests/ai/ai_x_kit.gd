class_name AiXKit
extends RefCounted
## Shared helpers of the AIX1 tests (micro, repair, handlers, ops): real matches through AiSoakKit with fog off, unit spawning
## next to a player's home, and small readers. Only public APIs.

const R_NAPC: String = "roster.napc.vanilla"
const R_NEC: String = "roster.nec.vanilla"
const CELL: int = 1024


static func match_of(rosters: PackedStringArray, levels: Array, ticks: int = 0, o: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = {"seed": 3, "rosters": rosters, "levels": levels, "family": 0, "fog": false, "credits": 7500}
	opts.merge(o, true)
	var m: Dictionary = AiSoakKit.make(opts)
	AiSoakKit.play(m, maxi(ticks, 8))  # at least one think: the controllers boot on their first think
	return m


static func brain(m: Dictionary, pid: int) -> AiBrain:
	return (m["brains"] as Dictionary)[pid]


static func ctx(m: Dictionary, pid: int) -> AiContext:
	return (m["factory"] as AiFactory).thinker(pid).controller.ctx


static func world(m: Dictionary) -> SimWorld:
	return m["world"]


## Spawns unit `id` for `pid` at (x, y) in sub-cells with its paid cost; returns the entity id.
static func spawn(m: Dictionary, id: String, pid: int, x: int, y: int, paid: int = 0) -> int:
	var w: SimWorld = world(m)
	var d: int = w.data.unit_idx(id)
	var e: SimEntity = w.spawn_unit(d, pid, x, y, 0, 0, paid if paid > 0 else maxi(w.data.units[d].cost, 1))
	return e.id


## Lets the AIs think a few times so that freshly spawned units are in their tables.
static func settle(m: Dictionary, ticks: int = 14) -> void:
	AiSoakKit.play(m, ticks)


## Sets the hp of an entity to pct percent of its maximum.
static func set_hp_pct(m: Dictionary, eid: int, pct: int) -> void:
	var e: SimEntity = world(m).get_entity(eid)
	e.hp = e.hp_max * pct / 100


## Home position (sub-cells) of a player: its start cell.
static func home(m: Dictionary, pid: int) -> PackedInt32Array:
	var c: AiContext = ctx(m, pid)
	return PackedInt32Array([c.kb.sites.home_x, c.kb.sites.home_y])


## A point `cells` cells from `from` towards `to` (sub-cells).
static func toward(from: PackedInt32Array, to: PackedInt32Array, cells: int) -> PackedInt32Array:
	var dx: int = to[0] - from[0]
	var dy: int = to[1] - from[1]
	var d: int = maxi(Fp.dist(dx, dy), 1)
	return PackedInt32Array([from[0] + dx * cells * CELL / d, from[1] + dy * cells * CELL / d])


## A defend op over `ids` of player `pid` (they join a DEFENSE squad and fight what comes).
static func defend_op(m: Dictionary, pid: int, ids: PackedInt32Array, x: int, y: int) -> AiOpDefend:
	settle(m)  # the freshly spawned units enter the AI's tables at its next think
	var op: AiOpDefend = AiOpDefend.new()
	op.setup_defense(x, y, true, ids)
	var b: AiBrain = brain(m, pid)
	b.add_op(ctx(m, pid), op)
	return op


## Entity table row helper: the order kind of a unit as the AI last read it.
static func order_of(m: Dictionary, pid: int, eid: int) -> int:
	var c: AiContext = ctx(m, pid)
	var r: int = c.kb.own.row(eid)
	return c.kb.own.order[r] if r >= 0 else -1


static func alive(m: Dictionary, eid: int) -> bool:
	var e: SimEntity = world(m).get_entity(eid)
	return e != null and (e.flags & SimFlags.F_GONE) == 0
