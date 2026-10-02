class_name UiOrderIntent
extends RefCounted
## What a click would do (ui.md 4.3): the output of `UiContextResolver.resolve`, the input of `UiCommandBus.dispatch`.
## `extra` holds the further intents produced by the SAME click for the other units of a mixed selection.

enum Kind {
	NONE = 0, MOVE = 1, ATTACK = 2, ATTACK_MOVE = 3, GUARD = 4, FORCE_FIRE = 5, CAPTURE = 6, REPAIR = 7, LOAD = 8,
	GARRISON = 9, SALVAGE = 10, HARVEST = 11, RETURN_BASE = 12, SET_RALLY = 13, SELL = 14, STRUCT_REPAIR = 15,
	USE_POWER = 16, LAUNCH_SUPERWEAPON = 17, UNLOAD = 18, DEPLOY = 19, HOLD = 20, STOP = 21, SCATTER = 22, PATROL = 23,
	STANCE = 24, RETURN_CASH = 25, ABILITY = 26, SCUTTLE = 27, UNDEPLOY = 28, FOLLOW = 29, DENIED = 99,
}

## Order-marker kinds (UiOrderMarkers, ui.md 4.1).
const MK_NONE: int = -1
const MK_MOVE: int = 0
const MK_ATTACK: int = 1
const MK_ATTACK_MOVE: int = 2
const MK_GUARD: int = 3
const MK_RALLY: int = 4
const MK_REPAIR: int = 5
const MK_CAPTURE: int = 6
const MK_DENIED: int = 7

## Cursor states (= UiCursors.State integers, ui.md 3.5); UiCursors itself lives in UI-01b.
const CUR_DEFAULT: int = 0
const CUR_ATTACK: int = 3
const CUR_MOVE: int = 4
const CUR_SELECT: int = 5
const CUR_DENIED: int = 6
const CUR_ATTACK_MOVE: int = 7
const CUR_FORCE_FIRE: int = 8
const CUR_GUARD: int = 9
const CUR_SELL: int = 11
const CUR_REPAIR: int = 12
const CUR_RALLY: int = 13
const CUR_INSPECT: int = 14
const CUR_INTERACT: int = 16

var kind: int = Kind.NONE
var ids: PackedInt32Array = PackedInt32Array()  ## eligible units (ascending)
var target_eid: int = -1  ## -1 = point (sent as target 0)
var x: int = 0  ## sim units
var y: int = 0
var queued: bool = false  ## Shift or the WAYPOINT latch -> QM_APPEND on every op that has a queue mode
var force: bool = false  ## ATTACK on a non-enemy: sets FLAGS bit0 "forced"
var move_flags: int = 0  ## MOVE / ATTACK_MOVE / PATROL flag bits: b1 speed-match, b2 reverse-ok (filled by the bus from settings)
var arg: int = 0  ## stance / ability slot / power index / structure-repair mode
var arg2: int = 0  ## spare (UNLOAD: 0 all cargo / 1 one passenger; USE_POWER: angle)
var extra: Array[UiOrderIntent] = []
var cursor: int = CUR_DEFAULT
var deny_reason: StringName = &""  ## UiText key when kind == DENIED ("order.deny.no_weapon" ...)
var marker: int = MK_NONE
var def_idx: int = -1  ## primary def of `ids` (unit responses)


static func make(k: int, p_ids: PackedInt32Array, tx: int, ty: int, target: int = -1) -> UiOrderIntent:
	var it := UiOrderIntent.new()
	it.kind = k
	it.ids = p_ids
	it.x = tx
	it.y = ty
	it.target_eid = target
	it.cursor = cursor_of(k)
	it.marker = marker_of(k)
	return it


static func denied(reason: StringName) -> UiOrderIntent:
	var it := UiOrderIntent.new()
	it.kind = Kind.DENIED
	it.deny_reason = reason
	it.cursor = CUR_DENIED
	it.marker = MK_DENIED
	return it


## Cursor state shown for an intent kind.
static func cursor_of(k: int) -> int:
	match k:
		Kind.MOVE, Kind.PATROL, Kind.FOLLOW:
			return CUR_MOVE
		Kind.ATTACK:
			return CUR_ATTACK
		Kind.ATTACK_MOVE:
			return CUR_ATTACK_MOVE
		Kind.GUARD:
			return CUR_GUARD
		Kind.FORCE_FIRE:
			return CUR_FORCE_FIRE
		Kind.CAPTURE, Kind.LOAD, Kind.GARRISON, Kind.SALVAGE, Kind.HARVEST, Kind.RETURN_BASE, Kind.RETURN_CASH, Kind.UNLOAD:
			return CUR_INTERACT
		Kind.REPAIR, Kind.STRUCT_REPAIR:
			return CUR_REPAIR
		Kind.SET_RALLY:
			return CUR_RALLY
		Kind.SELL:
			return CUR_SELL
		Kind.DENIED:
			return CUR_DENIED
	return CUR_DEFAULT


## Order-marker kind for an intent kind (ui.md 5.8.7).
static func marker_of(k: int) -> int:
	match k:
		Kind.MOVE, Kind.PATROL:
			return MK_MOVE
		Kind.ATTACK, Kind.FORCE_FIRE:
			return MK_ATTACK
		Kind.ATTACK_MOVE:
			return MK_ATTACK_MOVE
		Kind.GUARD:
			return MK_GUARD
		Kind.SET_RALLY:
			return MK_RALLY
		Kind.REPAIR, Kind.STRUCT_REPAIR:
			return MK_REPAIR
		Kind.CAPTURE, Kind.LOAD, Kind.GARRISON, Kind.SALVAGE, Kind.HARVEST, Kind.RETURN_BASE, Kind.RETURN_CASH, Kind.FOLLOW:
			return MK_CAPTURE
		Kind.DENIED:
			return MK_DENIED
	return MK_NONE


## This intent followed by its extras, in submission order.
func all_intents() -> Array[UiOrderIntent]:
	var out: Array[UiOrderIntent] = [self]
	out.append_array(extra)
	return out


## Compact text for test failure messages.
func describe() -> String:
	var kn: String = Kind.find_key(kind) if Kind.find_key(kind) != null else str(kind)
	return "%s ids=%s target=%d (%d,%d)%s%s" % [kn, ids, target_eid, x, y, " Q" if queued else "", " F" if force else ""]
