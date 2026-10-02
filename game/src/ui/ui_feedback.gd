class_name UiFeedback
extends RefCounted
## Immediate acknowledgement of a click (ui.md 5.8.7): the sim executes a command one or two turns later, so
## every click reacts at once: order marker, minimap ping, unit response, bracket flash; refusals shake the cursor
## and play the error cue. The widgets it drives (UiOrderMarkers, UiMinimap, UiNotifier) belong to UI-10 / UI-11 and
## are duck-typed Objects here (`add_marker(kind, x, y, target)`, `add_ping(kind, x, y)`, `notice(key)`); every
## effect is also a signal so a screen can wire it without those classes.

signal marker_requested(marker_kind: int, sim_x: int, sim_y: int, target_eid: int)
signal ping_requested(sim_x: int, sim_y: int)  ## ORDER ping (the point is off-screen)
signal flash_requested(ids: PackedInt32Array)  ## selected units flash their brackets for 0.15 s
signal denied_shown(reason: int, text_key: StringName)

var _overlay: Object = null
var _minimap: Object = null
var _audio: UiAudioPort = null
var _notifier: Object = null
## func(sim_x: int, sim_y: int) -> bool: true when the point is inside the playfield (no minimap ping then).
var on_screen: Callable = Callable()
var last_marker: int = UiOrderIntent.MK_NONE  ## test hook: the last marker requested


func setup(overlay: Object, minimap: Object, audio: UiAudioPort, notifier: Object) -> void:
	_overlay = overlay
	_minimap = minimap
	_audio = audio
	_notifier = notifier


## Marker + minimap ping (off-screen only) + unit response (`audio.unit_ordered`) + bracket flash for one intent kind
## (UiOrderIntent.Kind). `def_idx` is the primary unit's per-kind def.
func order_issued(kind: int, sim_x: int, sim_y: int, ids: PackedInt32Array, def_idx: int, target_eid: int = -1) -> void:
	var marker: int = UiOrderIntent.marker_of(kind)
	if marker != UiOrderIntent.MK_NONE:
		last_marker = marker
		marker_requested.emit(marker, sim_x, sim_y, target_eid)
		if _overlay != null and is_instance_valid(_overlay) and _overlay.has_method("add_marker"):
			_overlay.call("add_marker", marker, sim_x, sim_y, target_eid)
	if _wants_ping(kind) and on_screen.is_valid() and not bool(on_screen.call(sim_x, sim_y)):
		ping_requested.emit(sim_x, sim_y)
		if _minimap != null and is_instance_valid(_minimap) and _minimap.has_method("add_ping"):
			_minimap.call("add_ping", 0, sim_x, sim_y)
	if not ids.is_empty():
		flash_requested.emit(ids)
	if _audio == null:
		return
	if kind == UiOrderIntent.Kind.SET_RALLY:
		_audio.ui(UiAudioPort.RALLY_SET)
		return
	var order: int = unit_order_for(kind)
	if order >= 0:
		_audio.unit_ordered(order, def_idx)


## Refusal of a UI pre-check: cursor shake / ⊘ marker, `snd.ui.error`, the primary unit's deny response, a toast line.
func denied(reason: int, text_key: StringName, def_idx: int = -1, is_structure: bool = false) -> void:
	denied_shown.emit(reason, text_key)
	last_marker = UiOrderIntent.MK_DENIED
	if _audio != null:
		_audio.ui(UiAudioPort.ERROR)
		if def_idx >= 0:
			_audio.order_denied(def_idx, is_structure)
	if _notifier != null and is_instance_valid(_notifier) and _notifier.has_method("notice"):
		_notifier.call("notice", text_key)


## UiAudioPort.Order for an intent kind (ui.md 5.8.7 last column), -1 when the kind has no unit response.
static func unit_order_for(kind: int) -> int:
	match kind:
		UiOrderIntent.Kind.MOVE, UiOrderIntent.Kind.PATROL, UiOrderIntent.Kind.RETURN_BASE, UiOrderIntent.Kind.FOLLOW:
			return UiAudioPort.Order.MOVE
		UiOrderIntent.Kind.ATTACK, UiOrderIntent.Kind.FORCE_FIRE, UiOrderIntent.Kind.ATTACK_MOVE:
			return UiAudioPort.Order.ATTACK
		UiOrderIntent.Kind.GUARD:
			return UiAudioPort.Order.GUARD
		UiOrderIntent.Kind.CAPTURE, UiOrderIntent.Kind.SALVAGE:
			return UiAudioPort.Order.CAPTURE
		UiOrderIntent.Kind.LOAD, UiOrderIntent.Kind.GARRISON:
			return UiAudioPort.Order.LOAD
		UiOrderIntent.Kind.UNLOAD:
			return UiAudioPort.Order.UNLOAD
		UiOrderIntent.Kind.HARVEST, UiOrderIntent.Kind.RETURN_CASH:
			return UiAudioPort.Order.HARVEST
		UiOrderIntent.Kind.REPAIR, UiOrderIntent.Kind.STRUCT_REPAIR:
			return UiAudioPort.Order.REPAIR
		UiOrderIntent.Kind.DEPLOY, UiOrderIntent.Kind.UNDEPLOY:
			return UiAudioPort.Order.DEPLOY
		UiOrderIntent.Kind.STOP, UiOrderIntent.Kind.HOLD:
			return UiAudioPort.Order.STOP
		UiOrderIntent.Kind.SCATTER:
			return UiAudioPort.Order.SCATTER
		UiOrderIntent.Kind.SELL:
			return UiAudioPort.Order.SELL
	return -1


static func _wants_ping(kind: int) -> bool:
	return kind == UiOrderIntent.Kind.MOVE or kind == UiOrderIntent.Kind.ATTACK_MOVE or kind == UiOrderIntent.Kind.PATROL
