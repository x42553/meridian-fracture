class_name SimAbilityEvents
extends RefCounted
## Command reject reasons of the abilities commands (abilities 5.6.2 / 6.1) and the mapping onto the kernel's
## SimCommand.Err. The kernel emits CMD_REJECTED(pid, op, err, detail, target) itself: an executor returns the Err and
## leaves the abilities reason (RJ_*) in `cmd.detail`. Event codes live in SimAbilityConsts (EV_*); this file re-exports
## the ones used by the runtime so callers can name them from one place.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")

const RJ_OK: int = 0
const RJ_NO_SLOT: int = 1
const RJ_NOT_OWNER: int = 2
const RJ_COOLDOWN: int = 3
const RJ_BAD_STATE: int = 4
const RJ_BAD_TARGET: int = 5
const RJ_NO_ROOM: int = 6
const RJ_DISABLED: int = 7
const RJ_LIMIT: int = 8
const RJ_NOT_STATIONARY: int = 9
const RJ_OUT_OF_RANGE: int = 10

const EV_MODE_STARTED: int = K.EV_MODE_STARTED
const EV_MODE_CHANGED: int = K.EV_MODE_CHANGED
const EV_ABILITY_USED: int = K.EV_ABILITY_USED
const EV_ABILITY_READY: int = K.EV_ABILITY_READY
const EV_LOADED: int = K.EV_LOADED
const EV_UNLOADED: int = K.EV_UNLOADED
const EV_UNLOAD_BLOCKED: int = K.EV_UNLOAD_BLOCKED
const EV_GARRISON_CHANGED: int = K.EV_GARRISON_CHANGED
const EV_EJECTED: int = K.EV_EJECTED
const EV_DROWNED: int = K.EV_DROWNED
const EV_SALVAGE_DONE: int = K.EV_SALVAGE_DONE
const EV_CAPTURE_DONE: int = K.EV_CAPTURE_DONE
const EV_REPAIR_PULSE: int = K.EV_REPAIR_PULSE


## RJ_* -> the kernel's SimCommand.Err (what CMD_REJECTED.err carries).
static func err_of(reason: int) -> int:
	match reason:
		RJ_OK:
			return SimCommand.Err.OK
		RJ_NO_SLOT:
			return SimCommand.Err.WRONG_KIND
		RJ_NOT_OWNER:
			return SimCommand.Err.NO_ACTORS
		RJ_COOLDOWN:
			return SimCommand.Err.NOT_READY
		RJ_BAD_STATE, RJ_LIMIT, RJ_NOT_STATIONARY, RJ_OUT_OF_RANGE:
			return SimCommand.Err.NOT_ALLOWED
		RJ_BAD_TARGET:
			return SimCommand.Err.NO_TARGET
		RJ_NO_ROOM:
			return SimCommand.Err.BLOCKED
		RJ_DISABLED:
			return SimCommand.Err.DISABLED
	return SimCommand.Err.NOT_ALLOWED
