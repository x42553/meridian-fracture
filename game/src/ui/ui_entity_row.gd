class_name UiEntityRow
extends RefCounted
## One entity read through a `UiSimPort` (ui.md 4.4.1). A reusable buffer: a port fills the caller's row and never
## keeps it; callers copy what they need before the next read.

const F_STRUCT: int = 1
const F_GHOST: int = 2  ## remembered structure, not currently seen
const F_CAMO: int = 4
const F_DEPLOYED: int = 8
const F_EMP: int = 16
const F_UNPOWERED: int = 32
const F_CONSTRUCTING: int = 64
const F_GARRISONED: int = 128  ## occupants inside (neutral garrison or own transport)
const F_LOADED: int = 256  ## this entity is inside a container (not selectable)
const F_DECOY: int = 512  ## decoy identified by the viewer
const F_SUPPRESSED: int = 1024
const F_REPAIRING: int = 2048  ## structure repair toggle on
const F_SELLING: int = 4096  ## being sold (sell button disabled, "Selling..." chip)

## `kind` values: UI classification of `SimEntity.kind` and owner (ui.md 3.2.4).
const K_UNIT: int = 0
const K_STRUCTURE: int = 1
const K_WRECK: int = 2
const K_NEUTRAL_STRUCTURE: int = 3

## `order_kind` values.
const O_IDLE: int = 0
const O_MOVING: int = 1
const O_ATTACKING: int = 2
const O_ATTACK_MOVING: int = 3
const O_GUARDING: int = 4
const O_HOLDING: int = 5
const O_HARVESTING: int = 6
const O_REPAIRING: int = 7
const O_PRODUCING: int = 8
const O_OTHER: int = 15

var id: int = 0
var def_idx: int = -1
var kind: int = 0  ## K_*
var owner: int = -1  ## -1 neutral
var x: int = 0  ## sim units, end of last tick
var y: int = 0
var prev_x: int = 0
var prev_y: int = 0
var facing: int = 0  ## binary angle 0..4095
var layer: int = 0
var hp: int = 0
var hp_max: int = 0
var flags: int = 0
var order_kind: int = 0
var stance: int = -1  ## 0 aggressive, 1 defensive, 2 hold fire, 3 guard (-1 = no combat component)
var mode: int = 0  ## deploy / mode-switch / loadout index
var cargo: int = 0  ## loaded squads
var cargo_cap: int = 0
var ammo: int = -1  ## -1 infinite
var vet: int = 0  ## 0..3
var squad: int = 1  ## live squad members for infantry
var squad_max: int = 1
var container: int = -1  ## -1 none
var paid_cost: int = 0
var rally_x: int = -1  ## producers; -1 unset
var rally_y: int = -1
var rally_target: int = 0
var queue_len: int = 0  ## producers
var is_primary: bool = false  ## producers: the sim's primary building of its kind
# extensions (not in the spec table): neutral structures
var capturable: bool = false  ## neutral tech structure an engineer can capture
var garrison_free: int = 0  ## free garrison squad slots of a neutral civilian building


## Resets every field to its default (a port calls this before filling).
func clear() -> void:
	id = 0
	def_idx = -1
	kind = K_UNIT
	owner = -1
	x = 0
	y = 0
	prev_x = 0
	prev_y = 0
	facing = 0
	layer = 0
	hp = 0
	hp_max = 0
	flags = 0
	order_kind = O_IDLE
	stance = -1
	mode = 0
	cargo = 0
	cargo_cap = 0
	ammo = -1
	vet = 0
	squad = 1
	squad_max = 1
	container = -1
	paid_cost = 0
	rally_x = -1
	rally_y = -1
	rally_target = 0
	queue_len = 0
	is_primary = false
	capturable = false
	garrison_free = 0


## Copies every field of `o` into this row.
func copy_from(o: UiEntityRow) -> void:
	id = o.id
	def_idx = o.def_idx
	kind = o.kind
	owner = o.owner
	x = o.x
	y = o.y
	prev_x = o.prev_x
	prev_y = o.prev_y
	facing = o.facing
	layer = o.layer
	hp = o.hp
	hp_max = o.hp_max
	flags = o.flags
	order_kind = o.order_kind
	stance = o.stance
	mode = o.mode
	cargo = o.cargo
	cargo_cap = o.cargo_cap
	ammo = o.ammo
	vet = o.vet
	squad = o.squad
	squad_max = o.squad_max
	container = o.container
	paid_cost = o.paid_cost
	rally_x = o.rally_x
	rally_y = o.rally_y
	rally_target = o.rally_target
	queue_len = o.queue_len
	is_primary = o.is_primary
	capturable = o.capturable
	garrison_free = o.garrison_free


func is_structure() -> bool:
	return kind == K_STRUCTURE or kind == K_NEUTRAL_STRUCTURE


func has_flag(f: int) -> bool:
	return (flags & f) != 0


## hp as permille of hp_max (1000 when hp_max is 0).
func hp_permille() -> int:
	return 1000 if hp_max <= 0 else hp * 1000 / hp_max
