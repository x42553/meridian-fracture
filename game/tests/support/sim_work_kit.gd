class_name SimWorkKit
extends RefCounted
## Test kit of the engineer / neutral slice (EC3A): REAL match worlds (SimMatchKit: real GameData, generated map, every real
## system) without bots, plus helpers to place units next to a neutral structure, damage things and step. Never lives under src/.

const CELL: int = SimConfig.CELL
const NAPC: String = "roster.napc.vanilla"
const NEC: String = "roster.nec.vanilla"
const AE: String = "roster.ae.vanilla"


static func data() -> GameData:
	return SimMatchKit.data()


## Two- (or more-) player real match without bots. o: rosters, family, seed, credits, rules, size.
static func world(o: Dictionary = {}) -> SimWorld:
	var oo: Dictionary = {"bots": false, "size": 96, "seed": 1}
	oo.merge(o, true)
	if not oo.has("rosters"):
		oo["rosters"] = PackedStringArray([NAPC, NEC])
	return SimMatchKit.make_match(oo)["world"]


static func uidx(id: String) -> int:
	return data().unit_idx(id)


static func nidx(id: String) -> int:
	return data().neutral_idx(id)


## First neutral entity of a def id, null if the map has none.
static func neutral(w: SimWorld, id: String) -> SimEntity:
	var ni: int = nidx(id)
	for e: SimEntity in w.neutrals:
		if e.def_idx == ni:
			return e
	return null


## Spawns a unit on the nearest free ground cell around (x, y) sub-cell units.
static func unit_near(w: SimWorld, id: String, pid: int, x: int, y: int, paid: int = 0) -> SimEntity:
	var cell: int = SimMovement.find_free_cell_near(w, w.map.idx(x >> SimConfig.CELL_SHIFT, y >> SimConfig.CELL_SHIFT), SimEntity.Layer.GROUND, 6)
	return w.spawn_unit(uidx(id), pid, w.map.center_x(cell), w.map.center_y(cell), 0, 0, paid)


## An engineer standing right next to the footprint edge of `t` (already inside the channel reach).
static func engineer_at(w: SimWorld, pid: int, t: SimEntity, slot: int = 0) -> SimEntity:
	var half: PackedInt32Array = PackedInt32Array([0, 0])
	SimEconomyWork.half_extent(w, t, half)
	var x: int = t.x - half[0] - CELL / 2 - (slot / 3) * CELL
	var y: int = t.y - half[1] + CELL / 2 + (slot % 3) * CELL
	return unit_near(w, "unit.shared.engineer", pid, x, y, 500)


static func cmd(w: SimWorld, pid: int, ints: PackedInt32Array) -> void:
	w.submit_raw(pid, ints)


static func run(w: SimWorld, n: int) -> void:
	for _i: int in n:
		w.step()


## Steps until `pred` (Callable(world) -> bool) is true or `max_ticks` passed; returns the ticks stepped, -1 on timeout.
static func run_until(w: SimWorld, pred: Callable, max_ticks: int) -> int:
	for i: int in max_ticks:
		if pred.call(w):
			return i
		w.step()
	return -1


static func events(w: SimWorld, type: int) -> Array[PackedInt32Array]:
	return SimEconKit.events_of(w, type)


## Sets the hit points (test setup; the sim's own writers are heal / damage).
static func set_hp(e: SimEntity, hp: int) -> void:
	e.hp = clampi(hp, 1, e.hp_max)


static func errors_during(w: SimWorld, ticks: int) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	var old: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errs.append("%s: %s" % [tag, msg])
	run(w, ticks)
	Log.sink = old
	return errs
