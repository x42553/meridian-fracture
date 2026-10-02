class_name UiPlacement
extends RefCounted
## Ready-to-place flow (ui.md 5.10.5). The ghost, its per-cell colours and the build-radius ring are drawn by the view;
## this class owns the state: the footprint anchor under the pointer, the validity poll (only when the anchor or the
## orientation changes), rotation of rotatable footprints (only the Dock), the reason text and the commit / cancel.
## The data feed for the ghost is `state` (a `ViewPlacementState` filled from `UiSimPort.placement_result`) and the view
## calls `begin_placement` / `update_placement` / `end_placement` on the injected view object when it has them.
## Anchor = (cx - fp_w / 2, cy - fp_h / 2) with integer division: the footprint's top-left cell.

signal started(def_idx: int)
signal ended(committed: bool, def_idx: int)

const PENDING_MSEC: int = 1000  ## the card shows PLACING for at most this long after a commit
const REASON_TEXT: PackedStringArray = ["", "Outside build radius", "Blocked", "Needs shoreline", "Only one strategic structure allowed", "Unexplored"]

var active: bool = false
var def_idx: int = -1
var orient: int = 0
var anchor: Vector2i = Vector2i(-1, -1)  ## footprint top-left cell
var cell: Vector2i = Vector2i(-1, -1)  ## the cell under the pointer
var valid: bool = false
var reason: int = 0  ## `UiSimPort.place_reason()` of the last failed poll
var state: ViewPlacementState = ViewPlacementState.new()
var polls: int = 0  ## number of validity polls (test hook: proves the poll is skipped while nothing changed)

var _sim: UiSimPort = null
var _view: Object = null
var _bus: UiCommandBus = null
var _audio: UiAudioPort = null
var _roster: DefRoster = null
var _pending_def: int = -1
var _pending_until: int = 0
var _polled_orient: int = -1


func setup(sim: UiSimPort, view: Object, bus: UiCommandBus, audio: UiAudioPort, roster: DefRoster) -> void:
	_sim = sim
	_view = view
	_bus = bus
	_audio = audio
	_roster = roster


## Anchor cell for the pointer cell (cx, cy) and the oriented footprint size.
static func anchor_for(cx: int, cy: int, fp_w: int, fp_h: int) -> Vector2i:
	return Vector2i(cx - fp_w / 2, cy - fp_h / 2)


## Footprint size after `orient` quarter turns.
func footprint_size(struct_def: int, p_orient: int) -> Vector2i:
	var s: DefStructure = _roster.structure(struct_def) if _roster != null else null
	var w: int = s.fp_w if s != null else 1
	var h: int = s.fp_h if s != null else 1
	return Vector2i(h, w) if (p_orient & 1) == 1 else Vector2i(w, h)


## The def whose card shows PLACING: the active placement or a just-committed one (until the sim answers, <= 1 s).
func card_def() -> int:
	if active:
		return def_idx
	if _pending_def >= 0 and Time.get_ticks_msec() < _pending_until:
		return _pending_def
	return -1


## Starts placing `struct_def`. false when the flow cannot start (unknown def).
func begin(struct_def: int) -> bool:
	if _sim == null or struct_def < 0:
		return false
	if active:
		_end(false)
	active = true
	def_idx = struct_def
	orient = 0
	anchor = Vector2i(-1, -1)
	cell = Vector2i(-1, -1)
	valid = false
	reason = 0
	_pending_def = -1
	_call_view(&"begin_placement", [struct_def])
	started.emit(struct_def)
	return true


## Pointer over the world (screen px, <= 30 Hz): `pick_ground` -> cell -> `update_cell`. No-op on a miss.
func update_pointer(screen: Vector2) -> bool:
	if not active or _view == null or not _view.has_method(&"pick_ground") or not _view.has_method(&"world_to_sim"):
		return false
	var g: Vector3 = _view.call(&"pick_ground", screen)
	if not g.is_finite():
		return false
	var s: Vector2i = _view.call(&"world_to_sim", g)
	return update_cell(s.x >> 10, s.y >> 10)


## Cell under the pointer. Polls the sim only when the anchor cell or the orientation changed; returns true when it did.
func update_cell(cx: int, cy: int) -> bool:
	if not active:
		return false
	cell = Vector2i(cx, cy)
	var fp: Vector2i = footprint_size(def_idx, orient)
	var a: Vector2i = anchor_for(cx, cy, fp.x, fp.y)
	if a == anchor and _polled_orient == orient:
		return false
	anchor = a
	_poll()
	return true



func _poll() -> void:
	polls += 1
	_polled_orient = orient
	var r: int = _sim.check_place(def_idx, anchor.x, anchor.y, orient)
	valid = r == UiSimPort.Rule.OK
	reason = 0 if valid else _sim.place_reason()
	var res: RefCounted = _sim.placement_result(def_idx, anchor.x, anchor.y, orient)
	if res is SimPlacementResult:
		state.fill_from_placement(res as SimPlacementResult, def_idx, orient)
	else:
		state.def_idx = def_idx
		state.origin_cx = anchor.x
		state.origin_cy = anchor.y
		state.rot = orient
		var fp: Vector2i = footprint_size(def_idx, orient)
		state.w = fp.x
		state.h = fp.y
		state.valid = valid
		state.in_radius = reason != 1
		state.cells = PackedByteArray()
	_call_view(&"update_placement", [anchor.x, anchor.y, res, orient])


## Ctrl+R / Shift+wheel: quarter turn clockwise, only for rotatable footprints. Returns true when it turned.
func rotate(steps: int = 1) -> bool:
	if not active or not _sim.footprint_rotatable(def_idx):
		return false
	orient = posmod(orient + steps, 4)
	if cell.x >= 0:
		var fp: Vector2i = footprint_size(def_idx, orient)
		anchor = anchor_for(cell.x, cell.y, fp.x, fp.y)
		_poll()
	return true


## "Outside build radius" / "Blocked" / ... for the failed poll; "" while valid.
func reason_text() -> String:
	if valid or reason <= 0 or reason >= REASON_TEXT.size():
		return ""
	return REASON_TEXT[reason]


## Cursor state: DEFAULT while valid, DENIED otherwise (`UiOrderIntent.CUR_*`).
func cursor_state() -> int:
	return UiOrderIntent.CUR_DEFAULT if valid or cell.x < 0 else UiOrderIntent.CUR_DENIED


## LMB: commits when valid (`BUILD_PLACE` through the bus); an invalid click plays the failure cue and keeps the mode.
func commit() -> bool:
	if not active or _bus == null:
		return false
	if not valid:
		if _audio != null:
			_audio.ui(UiAudioPort.PLACE_FAIL)
		return false
	var ok: bool = _bus.build_place(def_idx, anchor.x, anchor.y, orient)
	if ok:
		_pending_def = def_idx
		_pending_until = Time.get_ticks_msec() + PENDING_MSEC
		_end(true)
	return ok


## RMB / Esc / another card: the item stays READY.
func cancel() -> void:
	if active:
		_end(false)


## Presenter poll: if the READY structure this flow places vanished (cancelled or destroyed), the mode ends.
## Returns true when it ended the flow.
func check_ready(ready_def: int) -> bool:
	if active and ready_def != def_idx:
		_end(false)
		return true
	return false


func _end(committed: bool) -> void:
	var d: int = def_idx
	active = false
	valid = false
	anchor = Vector2i(-1, -1)
	cell = Vector2i(-1, -1)
	_polled_orient = -1
	_call_view(&"end_placement", [])
	ended.emit(committed, d)


func _call_view(method: StringName, args: Array) -> void:
	if _view != null and _view.has_method(method):
		_view.callv(method, args)
