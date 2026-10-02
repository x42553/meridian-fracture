class_name UiModes
extends RefCounted
## Armed command modes (ui.md 3.3, 5.7.2): which click mode is active, the WAYPOINT latch and the sticky setting.
## The screen wires `changed` to the cursor (UiCursors.set_state) and the tool-row highlight.

enum Armed {
	NONE = 0, ATTACK_MOVE = 1, GUARD = 2, SELL = 3, REPAIR = 4, RALLY = 5, WAYPOINT = 6, FORCE_FIRE = 7, POWER = 8,
	SUPERWEAPON = 9, PLACE = 10, ABILITY = 11, PING = 12, MOVE = 13, PATROL = 14, FOLLOW = 15,
}

signal changed(armed: int, previous: int)

var armed: int = Armed.NONE
var waypoint_latch: bool = false  ## W: every resolved intent is queued
var sticky: bool = false  ## input/sticky_modes
var arg: int = -1  ## ability slot / power index for ABILITY / POWER
var audio: UiAudioPort = null  ## optional cue sink (arm plays a cue)


## Arms a mode (WAYPOINT toggles the latch instead of a click mode). Plays the mode's cue.
func arm(mode: int, p_arg: int = -1) -> void:
	if mode == Armed.WAYPOINT:
		toggle_waypoint()
		return
	var prev: int = armed
	armed = mode
	arg = p_arg
	if mode != Armed.NONE:
		_cue(mode)
	if prev != mode:
		changed.emit(armed, prev)


func disarm() -> void:
	if armed == Armed.NONE:
		return
	var prev: int = armed
	armed = Armed.NONE
	arg = -1
	changed.emit(armed, prev)


## W: toggles the queue latch (Esc clears it through `clear_latch`).
func toggle_waypoint() -> void:
	waypoint_latch = not waypoint_latch
	if audio != null:
		audio.ui(UiAudioPort.WAYPOINT)
	changed.emit(armed, armed)


func clear_latch() -> void:
	if waypoint_latch:
		waypoint_latch = false
		changed.emit(armed, armed)


## After one issued order: disarm unless sticky or Shift is held.
func consume(shift_held: bool) -> void:
	if sticky or shift_held:
		return
	disarm()


## LMB issues (or commits) instead of selecting.
func is_click_mode() -> bool:
	return armed != Armed.NONE and armed != Armed.WAYPOINT


## `mods` with the queue bit added while the WAYPOINT latch is on.
func effective_mods(mods: int) -> int:
	return mods | UiContextResolver.MOD_QUEUE if waypoint_latch else mods


func _cue(mode: int) -> void:
	if audio == null:
		return
	match mode:
		Armed.SELL:
			audio.ui(UiAudioPort.SELL_MODE)
		Armed.REPAIR:
			audio.ui(UiAudioPort.REPAIR_MODE)
		_:
			audio.ui(UiAudioPort.CONFIRM)
