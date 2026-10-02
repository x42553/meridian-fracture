class_name SndWorldReader
extends RefCounted
## The ONLY audio file that touches SimWorld (audio spec 3.6): thin read-only wrappers, so a sim signature change is fixed
## in one place. Everything returns plain ints / bools; nothing here mutates the world.

const REL_SELF: int = 0
const REL_ALLY: int = 1
const REL_ENEMY: int = 2
const REL_NEUTRAL: int = 3

var world: SimWorld = null
var omniscient: bool = false
var _viewer: int = 0
var _team: int = -1


func bind(p_world: SimWorld, p_viewer: int, p_omniscient: bool) -> void:
	world = p_world
	_viewer = p_viewer
	omniscient = p_omniscient or p_viewer < 0
	_team = world.team_of(p_viewer) if world != null else -1


func is_bound() -> bool:
	return world != null


func tick() -> int:
	return world.tick if world != null else 0


func viewer_pid() -> int:
	return _viewer


func viewer_team() -> int:
	return _team


func cell_visible(cx: int, cy: int) -> bool:
	if omniscient or world == null:
		return true
	return world.cell_visible(_viewer, cx, cy)


func relation_of(owner: int) -> int:
	if world == null or owner < 0:
		return REL_NEUTRAL
	if omniscient:
		return REL_ALLY if world.team_of(owner) == _team and _team >= 0 else REL_ENEMY
	return world.rel(_viewer, owner)


func entity(id: int) -> SimEntity:
	return world.get_entity(id) if world != null else null


func entity_visible(e: SimEntity) -> bool:
	if omniscient or world == null:
		return true
	if e.owner == _viewer or relation_of(e.owner) == REL_ALLY:
		return true
	return world.entity_visible(_viewer, e)


func query_radius(x: int, y: int, r: int, out: PackedInt32Array) -> int:
	if world == null:
		return 0
	return world.query_circle(x, y, r, out, SimTag.ALIVE)


## True when an alive entity of the viewer's team lies within r sub-cells (superweapon warning "affected" test).
func team_within(x: int, y: int, r: int) -> bool:
	if world == null:
		return false
	if omniscient:
		return true
	var buf: PackedInt32Array = PackedInt32Array()
	var n: int = world.query_circle(x, y, r, buf, SimTag.ALIVE)
	for i: int in n:
		var e: SimEntity = world.get_entity(buf[i])
		if e != null and world.team_of(e.owner) == _team and e.kind != SimEntity.Kind.ZONE:
			return true
	return false


## First structure of `owner` with the given def index (the superweapon launcher), null when none.
func find_structure(owner: int, def_idx: int) -> SimEntity:
	if world == null:
		return null
	for e: SimEntity in world.structures_of(owner):
		if e.def_idx == def_idx and (e.flags & SimFlags.F_GONE) == 0:
			return e
	return null


func map_size() -> Vector2i:
	if world == null or world.map == null:
		return Vector2i.ZERO
	return Vector2i(world.map.w, world.map.h)


func map_family() -> int:
	return world.map.family if world != null and world.map != null else 0


func map_biome() -> int:
	return world.map.biome if world != null and world.map != null else 0


func terrain_id(cx: int, cy: int) -> int:
	if world == null or world.map == null or cx < 0 or cy < 0 or cx >= world.map.w or cy >= world.map.h:
		return 4
	return world.map.terrain[cy * world.map.w + cx]


func terrain_bytes() -> PackedByteArray:
	return world.map.terrain if world != null and world.map != null else PackedByteArray()


## Owner's player record (power supply / demand ...), null for -1 or unknown pids.
func player(pid: int) -> SimPlayer:
	if world == null or pid < 0 or pid >= world.players.size():
		return null
	return world.players[pid]


func power_low(pid: int) -> bool:
	var p: SimPlayer = player(pid)
	return p != null and p.power_demand > p.power_supply and p.power_demand > 0


## DT_* damage type of a warhead registered by `owner_pid` (-1 when unknown).
func warhead_dtype(owner_pid: int, warhead_idx: int) -> int:
	if world == null or world.combat == null:
		return -1
	var t: SimCombatTables = world.combat.tables_of(owner_pid)
	if t == null or warhead_idx < 0 or warhead_idx >= t.warheads.size():
		return -1
	var w: SimCombatWarhead = t.warheads[warhead_idx]
	return w.dtype if w != null else -1


## ArmorClass of a structure def (9 = heavy building when unknown).
func structure_armor(def_idx: int) -> int:
	if world == null or def_idx < 0 or def_idx >= world.data.structures.size():
		return 9
	return world.data.structures[def_idx].armor_class


## The player's superweapon slot: {state: 0 none / 1 charging / 2 ready, fraction: 0..1, def_idx}.
func superweapon_charge(pid: int) -> Dictionary:
	var p: SimPlayer = player(pid)
	if p == null or p.econ == null:
		return {"state": 0, "fraction": 0.0, "def_idx": -1}
	var slot: SimPowerSlot = p.econ.slots[SimEconConst.SLOT_SW]
	var frac: float = 0.0
	if slot.recharge_ticks > 0:
		frac = clampf(float(slot.charge) / float(slot.recharge_ticks), 0.0, 1.0)
	return {"state": slot.sw_state, "fraction": frac, "def_idx": slot.def_idx}


func faction_code_of_owner(pid: int) -> String:
	var p: SimPlayer = player(pid)
	if p == null or world == null or p.faction_idx < 0 or p.faction_idx >= world.data.factions.size():
		return ""
	return world.data.factions[p.faction_idx].code.to_lower()
