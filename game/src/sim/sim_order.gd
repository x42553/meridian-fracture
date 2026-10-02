class_name SimOrder
extends RefCounted
## One entry of a unit's order queue plus the order-type / status / queue-mode / flag / end-reason constants
## (sim_core 4.7). Handlers are stateless: all per-order state lives here (`phase, t0, p0, p1`) or in components,
## and all of it is hashed. `fail` is the only unhashed field (the order is dropped at once).

# ---- order types (ranges: 0-15 core, 16-29 movement, 30-39 economy, 40-49 combat, 50-63 transport / abilities)
const T_NONE: int = 0  ## invalid
const T_WAIT: int = 1  ## arg = ticks. Handler: core
const T_MOVE: int = 16  ## x,y; OF_NO_FORMATION, OF_SPEED_MATCH, OF_REVERSE_OK. Handler: movement
const T_PATROL: int = 17  ## x,y; always OF_CYCLIC
const T_FOLLOW: int = 18  ## target (issued by command 12)
const T_FACE: int = 19  ## arg = angle
const T_LAND: int = 20  ## x,y or pad
const T_HARVEST: int = 30  ## target 0 + x,y = a deposit cell. Handler: economy
const T_RETURN_CARGO: int = 31  ## target refinery (0 = nearest)
const T_CAPTURE: int = 32  ## target
const T_REPAIR: int = 33  ## target
const T_SALVAGE: int = 34  ## target
const T_DEPLOY_MCV: int = 35  ## optional cell (x,y)
const T_ATTACK: int = 40  ## target; OF_FORCED = attack own / allied / neutral. Handler: combat
const T_ATTACK_MOVE: int = 41  ## x,y
const T_GUARD: int = 42  ## target (guard that unit) or x,y (guard that spot)
const T_HOLD: int = 43  ## hold position
const T_FORCE_FIRE: int = 44  ## target or x,y (ground); arg = count
const T_RETURN_BASE: int = 45  ## aircraft: land at a pad / rearm
const T_LOAD: int = 50  ## target transport. Handler: abilities (transports)
const T_UNLOAD: int = 51  ## x,y + arg flags
const T_GARRISON: int = 52  ## target building
const T_DEPLOY: int = 53  ## arg = ability slot
const T_UNDEPLOY: int = 54  ## arg = ability slot
const T_USE_ABILITY: int = 55  ## arg slot, arg2 op or mode, target, x,y
const T_SET_MODE: int = 56
const TYPE_COUNT: int = 64  ## size of the handler table; extending needs an amendment

# ---- handler status
const RUNNING: int = 0
const DONE: int = 1
const FAILED: int = 2

# ---- queue modes
const QM_REPLACE: int = 0
const QM_APPEND: int = 1
const QM_FRONT: int = 2

# ---- flags
const OF_FORCED: int = 1
const OF_CYCLIC: int = 2
const OF_AUTO: int = 4
const OF_NO_FORMATION: int = 8
const OF_SPEED_MATCH: int = 16
const OF_REVERSE_OK: int = 32

# ---- on_end reasons
const END_DONE: int = 0
const END_FAILED: int = 1
const END_CANCELLED: int = 2
const END_REPLACED: int = 3
const END_DIED: int = 4

## phase 0: not begun. The dispatcher sets 1 before on_begin(); values >= 1 are handler-defined.
const PH_NEW: int = 0

## Derived / diagnostic fields that are deliberately not hashed.
const HASH_EXEMPT: PackedStringArray = ["fail"]

var type: int = T_NONE
var target_id: int = 0  ## entity id, 0 = none
var x: int = 0  ## destination / target point (sub-cell units)
var y: int = 0
var arg: int = 0  ## type-specific (combat's count = arg)
var arg2: int = 0
var flags: int = 0  ## OF_*
var phase: int = PH_NEW
var t0: int = 0  ## handler scratch: tick started, path cursor, retry counter ... (all hashed)
var p0: int = 0
var p1: int = 0
## A SimCommand.Err the handler sets before returning FAILED; copied into ORDER_FAILED.c. Not hashed.
var fail: int = 0


func _init(p_type: int = T_NONE, p_target_id: int = 0, p_x: int = 0, p_y: int = 0, p_arg: int = 0, p_arg2: int = 0, p_flags: int = 0) -> void:
	type = p_type
	target_id = p_target_id
	x = p_x
	y = p_y
	arg = p_arg
	arg2 = p_arg2
	flags = p_flags


## Builder of sim_core 3.6 (= SimOrder.new).
static func make(t: int, target: int = 0, px: int = 0, py: int = 0, a: int = 0, a2: int = 0, f: int = 0) -> SimOrder:
	return SimOrder.new(t, target, px, py, a, a2, f)


## Appends type, target_id, x, y, arg, arg2, flags, phase, t0, p0, p1 (sim_core 8.2 entity stream).
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(type)
	buf.append(target_id)
	buf.append(x)
	buf.append(y)
	buf.append(arg)
	buf.append(arg2)
	buf.append(flags)
	buf.append(phase)
	buf.append(t0)
	buf.append(p0)
	buf.append(p1)
