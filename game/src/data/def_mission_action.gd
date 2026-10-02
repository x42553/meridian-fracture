class_name DefMissionAction
extends RefCounted
## One action of a mission trigger's `then` list (schema key `do`). Ints only; references are resolved indices (-1 = none).
## Executed by SimMissionActions.

enum Op {
	SET_OBJECTIVE = 0, SHOW_MESSAGE = 1, TIMER_START = 2, TIMER_STOP = 3, SPAWN_UNITS = 4, SPAWN_STRUCTURE = 5,
	GIVE_CREDITS = 6, GRANT_POWER = 7, LOCK_POWER = 8, REVEAL_AREA = 9, CHANGE_AI = 10, TRANSFER = 11, DESTROY = 12,
	ORDER_UNITS = 13, ELIMINATE = 14, TRIGGER_ENABLE = 15, TRIGGER_DISABLE = 16, WIN = 17, LOSE = 18, CAMERA_HINT = 19,
	MUSIC_STATE = 20,
}
const OP_NAMES: PackedStringArray = ["set_objective", "show_message", "timer_start", "timer_stop", "spawn_units", "spawn_structure",
	"give_credits", "grant_power", "lock_power", "reveal_area", "change_ai", "transfer", "destroy", "order_units", "eliminate",
	"trigger_enable", "trigger_disable", "win", "lose", "camera_hint", "music_state"]
## Scripted order kinds (DefMissionAction.order).
const ORD_NONE: int = 0
const ORD_MOVE: int = 1
const ORD_ATTACK_MOVE: int = 2
const ORD_HOLD: int = 3
const ORD_GUARD: int = 4
const ORDER_NAMES: PackedStringArray = ["", "move", "attack_move", "hold", "guard"]
## music_state values (value).
const MUSIC_NAMES: PackedStringArray = ["auto", "calm", "combat", "tense", "victory", "defeat"]

var op: int = 0
var owner_mode: int = 0  ## selector of the acting / affected player(s) (DefMissionCond.OWN_*)
var owner_val: int = 0
var to_pid: int = -1  ## transfer target owner (-1 = neutral)
var of_kind: int = 0  ## DefMissionCond.OF_*
var def_idx: int = -1
var tag_mask: int = 0
var count: int = 1
var area: int = -1  ## area index: spawn / source / reveal / camera area
var order: int = 0  ## ORD_*
var order_area: int = -1  ## area index the order points at (move / attack_move / guard)
var cell_x: int = -1  ## absolute cell (spawn_structure / camera_hint without an area), -1 = none
var cell_y: int = -1
var ref: int = -1  ## objective / timer / message / trigger index
var placed: int = -1  ## placed-structure id index (spawn_structure registers it; transfer / destroy name it)
var wave: int = -1  ## wave index (spawn_units registers it)
var value: int = 0  ## objective state / seconds / credits / music state / power slot
var ai_active: int = -1  ## change_ai: -1 keep, 0 off, 1 on
var ai_level: int = -1
var ai_style: int = -1
var ai_aggr: int = -1  ## 0..100
var announcer: String = ""  ## show_message: optional announcer line id overriding the message's own
