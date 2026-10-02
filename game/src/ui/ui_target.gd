class_name UiTarget
extends RefCounted
## What is under the cursor (ui.md 4.3): the input of `UiContextResolver.resolve`. Built by
## `UiContextResolver.make_target` from a pick + port reads, or by hand in tests via the `ground` / `entity` helpers.

enum Kind { NONE = 0, GROUND = 1, ENEMY = 2, OWN = 3, ALLY = 4, NEUTRAL = 5, WRECK = 6, DEPOSIT = 7 }
enum EntityKind { UNIT = 0, STRUCTURE = 1, WRECK = 2, NEUTRAL_STRUCTURE = 3 }

var kind: int = Kind.NONE
var entity_kind: int = EntityKind.UNIT  ## meaningful when kind >= ENEMY
var eid: int = -1  ## -1 for ground
var def_idx: int = -1  ## -1 for ground
var owner: int = -1
var layer: int = 0  ## 0 ground, 1 air, 2 surface, 3 underwater
var x: int = 0  ## sim units (entity position, or the ground point)
var y: int = 0
var visible: bool = true  ## currently visible to the viewer
var ghost: bool = false  ## remembered structure
var hp_permille: int = 1000
var damaged: bool = false  ## hp < hp_max
var capturable: bool = false  ## neutral tech structure not yet owned by the viewer's team
var garrisonable: bool = false  ## neutral civilian garrison with a free slot
var transport_free: int = 0  ## free squad slots (own / ally transports)
var transport_vehicle_free: int = 0
var is_producer: bool = false
var is_refinery: bool = false
var is_airfield: bool = false
var is_carrier: bool = false
var salvageable: bool = false  ## enemy land-vehicle wreck inside its window
var passable_mask: int = -1  ## move classes that can stand on this ground cell (bit per DefEnums.MoveClass); -1 = unknown (no check)
# extensions used by the armed modes (not in the spec table)
var caps: int = 0  ## UiUnitCaps of the target's def (CAP_SELLABLE for SELL, CAP_VEHICLE for repair)
var repairing: bool = false  ## structure repair toggle is on (F_REPAIRING)
var selling: bool = false  ## structure is being sold


func is_entity() -> bool:
	return kind >= Kind.ENEMY and kind != Kind.DEPOSIT


func is_structure() -> bool:
	return entity_kind == EntityKind.STRUCTURE or entity_kind == EntityKind.NEUTRAL_STRUCTURE


## A ground point target.
static func ground(px: int, py: int, mask: int = -1) -> UiTarget:
	var t := UiTarget.new()
	t.kind = Kind.GROUND
	t.x = px
	t.y = py
	t.passable_mask = mask
	return t


## A deposit cell (eid -1; x, y = the cell centre).
static func deposit(px: int, py: int) -> UiTarget:
	var t := UiTarget.new()
	t.kind = Kind.DEPOSIT
	t.x = px
	t.y = py
	return t


## An entity target of relation `k` (Kind.ENEMY / OWN / ALLY / NEUTRAL / WRECK).
static func entity(k: int, id: int, ek: int, px: int, py: int, layer_v: int = 0) -> UiTarget:
	var t := UiTarget.new()
	t.kind = k
	t.entity_kind = ek
	t.eid = id
	t.x = px
	t.y = py
	t.layer = layer_v
	return t
