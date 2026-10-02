class_name SimEntity
extends RefCounted
## The entity record (sim_core 4.2): UNIT / STRUCTURE / WRECK / ZONE / NEUTRAL share one table; projectiles are
## not entities. The world owns every instance and is the only writer of the kernel fields; domains write only
## the fields their column says (see the spec) and their own component slot. All values are ints (DR-1).

enum Kind { UNIT = 0, STRUCTURE = 1, WRECK = 2, ZONE = 3, NEUTRAL = 4 }  ## 5 is reserved, never used
## Same numbering as data's Layer and combat's LAYER_*.
enum Layer { GROUND = 0, AIR = 1, SURFACE = 2, UNDERWATER = 3 }

## Derived / private fields that are deliberately NOT hashed (DR-13 coverage test: exactly these are exempt).
const HASH_EXEMPT: PackedStringArray = ["team", "radius", "_cap", "_asset", "_counted", "_pos_tick", "_listed", "_gone", "_occ"]

var id: int = 0  ## unique, >= 1, monotonic, never reused
var kind: int = 0  ## Kind
var def_idx: int = -1  ## index into the def table selected by kind
var owner: int = -1  ## pid 0..7 or -1 neutral
var parent: int = 0  ## creator id (summoner, carrier of a drone ...), 0 none; not set on wrecks
var container_id: int = -1  ## container id while F_INSIDE, else -1
var x: int = 0  ## sub-cell units (1024 = 1 cell), entity centre; structures: footprint centre
var y: int = 0
var prev_x: int = 0  ## position at the start of the current (or last moved) tick
var prev_y: int = 0
var vx: int = 0  ## displacement during the current (or last completed moved) tick
var vy: int = 0
var facing: int = 0  ## 0..4095 (0 = +x, increasing toward +y)
var layer: int = 0  ## Layer
var hp: int = 0  ## F_DEAD implies 0, otherwise 1..hp_max when hp_max > 0 (hp_max == 0: indestructible)
var hp_max: int = 0
var paid_cost: int = 0  ## credits actually paid (post-modifier); wreck: the dead unit's value
var flags: int = 0  ## 64-bit set, see SimFlags; hashed as two words
var born: int = 0  ## world.tick at spawn
var expire_tick: int = 0  ## absolute tick at which cleanup removes it; 0 = never
var orders: Array[SimOrder] = []  ## queue, head = current. Units only

# ---- component slots (sim_core 4.5): created by the owning domain's on_spawn, never swapped
var move: SimCompMove = null
var combat: SimCompCombat = null
var air: SimCompAir = null
var carrier: SimCompCarrier = null
var econ: SimCompEcon = null
var prod: SimCompProd = null
var abil: SimCompAbility = null
var stats: SimCompStats = null
var vis: SimCompVision = null
var cargo: SimCompCargo = null
var summon: SimCompSummon = null

# ---- derived (not hashed)
var team: int = -1  ## cache of world.team_of(owner)
var radius: int = 0  ## collision / selection radius in units; wreck: the dead unit's
@warning_ignore("unused_private_class_variable")
var _cap: int = 0  ## cap weight counted for the owner
@warning_ignore("unused_private_class_variable")
var _asset: bool = false  ## counts toward struct / rebuilder counters
@warning_ignore("unused_private_class_variable")
var _counted: bool = false  ## currently counted for its owner
@warning_ignore("unused_private_class_variable")
var _pos_tick: int = -1  ## tick stamp of the first set_pos (mover bookkeeping)
@warning_ignore("unused_private_class_variable")
var _listed: bool = false  ## member of the world's lists
@warning_ignore("unused_private_class_variable")
var _gone: bool = false  ## finalised (removed)
@warning_ignore("unused_private_class_variable")
var _occ: bool = false  ## occupies a map footprint


## Appends the entity stream of sim_core 8.2: id ... expire_tick, orders, component mask, components in slot order.
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(id)
	buf.append(kind)
	buf.append(def_idx)
	buf.append(owner)
	buf.append(parent)
	buf.append(container_id)
	buf.append(x)
	buf.append(y)
	buf.append(prev_x)
	buf.append(prev_y)
	buf.append(vx)
	buf.append(vy)
	buf.append(facing)
	buf.append(layer)
	buf.append(hp)
	buf.append(hp_max)
	buf.append(paid_cost)
	buf.append(flags & 0xFFFFFFFF)
	buf.append((flags >> 32) & 0xFFFFFFFF)
	buf.append(born)
	buf.append(expire_tick)
	buf.append(orders.size())
	for o: SimOrder in orders:
		o.hash_into(buf)
	var mask: int = 0
	if move != null:
		mask |= 1
	if combat != null:
		mask |= 2
	if air != null:
		mask |= 4
	if carrier != null:
		mask |= 8
	if econ != null:
		mask |= 16
	if prod != null:
		mask |= 32
	if abil != null:
		mask |= 64
	if stats != null:
		mask |= 128
	if vis != null:
		mask |= 256
	if cargo != null:
		mask |= 512
	if summon != null:
		mask |= 1024
	buf.append(mask)
	if mask == 0:
		return
	if move != null:
		move.hash_into(buf)
	if combat != null:
		combat.hash_into(buf)
	if air != null:
		air.hash_into(buf)
	if carrier != null:
		carrier.hash_into(buf)
	if econ != null:
		econ.hash_into(buf)
	if prod != null:
		prod.hash_into(buf)
	if abil != null:
		abil.hash_into(buf)
	if stats != null:
		stats.hash_into(buf)
	if vis != null:
		vis.hash_into(buf)
	if cargo != null:
		cargo.hash_into(buf)
	if summon != null:
		summon.hash_into(buf)
