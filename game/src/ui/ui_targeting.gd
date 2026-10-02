class_name UiTargeting
extends RefCounted
## Support-power and superweapon targeting (ui.md 5.10.6, 5.9): the shape preview (circle of the resolved radius, or a
## length x width corridor for line powers), vision validity from `power_target_ok` / `visibility`, the friendly-fire
## warning and the commit. Point powers commit on click; line powers take an angle: press = start, drag = direction,
## release = commit, with `binary angle = posmod(roundi(atan2(dy, dx) * 4096 / TAU), 4096)` (0 = +x, increasing toward
## +y like SimEntity.facing) as the single float -> int step. Powers naming an own structure / unit (OWN_STRUCTURE)
## commit on the hovered own entity and send its eid. RMB / Esc cancels. Commands go through `UiCommandBus`.

signal started(is_superweapon: bool, power_idx: int)
signal ended(committed: bool)

enum Kind { NONE = 0, POWER = 1, SUPERWEAPON = 2 }

const CELL: int = 1024
const HINT_NEEDS_VISION: String = "Needs vision"
const HINT_UNEXPLORED: String = "Unexplored"
const HINT_OWN_TARGET: String = "Select one of your own structures"
const DRAG_MIN_UNITS: int = 1024  ## a line power keeps the default angle unless the drag is at least one cell long

var active: bool = false
var kind: int = Kind.NONE
var power_idx: int = -1
var shape: int = UiWorldOverlay.SHAPE_CIRCLE
var radius_units: int = 0
var length_units: int = 0
var target_mode: int = DefEnums.TargetMode.POINT
var valid: bool = false
var friendly_fire: bool = false
var hint: String = ""
var angle: int = 0
var hover: Vector2i = Vector2i.ZERO
var hover_eid: int = 0  ## own entity under the pointer (OWN_STRUCTURE powers)

var _sim: UiSimPort = null
var _bus: UiCommandBus = null
var _overlay: UiWorldOverlay = null
var _audio: UiAudioPort = null
var _roster: DefRoster = null
var _data: GameData = null
var _damaging: bool = false
var _vision: int = DefEnums.TargetVision.ANY
var _start: Vector2i = Vector2i.ZERO
var _pressing: bool = false
var _ids: PackedInt32Array = PackedInt32Array()
var _row: UiEntityRow = UiEntityRow.new()


func setup(sim: UiSimPort, bus: UiCommandBus, overlay: UiWorldOverlay, audio: UiAudioPort, roster: DefRoster) -> void:
	_sim = sim
	_bus = bus
	_overlay = overlay
	_audio = audio
	_roster = roster
	_data = sim.data()


## Binary angle of the vector (dx, dy) in sim axes: `posmod(roundi(atan2(dy, dx) * 4096 / TAU), 4096)`.
static func angle_of(dx: int, dy: int) -> int:
	return posmod(roundi(atan2(float(dy), float(dx)) * 4096.0 / TAU), 4096)


## Starts targeting for the roster power `p_idx` (`GameData.powers` index). A power without a target fires at once (returns
## true, `active` stays false). false when the power is unknown or the bus refused the immediate use.
func begin_power(p_idx: int) -> bool:
	if _data == null or p_idx < 0 or p_idx >= _data.powers.size():
		return false
	var p: DefPower = _data.powers[p_idx]
	if p.target_mode == DefEnums.TargetMode.NONE:
		return _bus.use_power(p_idx, 0, 0, 0)
	_reset()
	active = true
	kind = Kind.POWER
	power_idx = p_idx
	target_mode = p.target_mode
	_vision = p.target_vision
	if p.target_mode == DefEnums.TargetMode.LINE:
		shape = UiWorldOverlay.SHAPE_LINE
		radius_units = maxi(p.width / 2, 512)
		length_units = maxi(p.length, CELL)
	else:
		shape = UiWorldOverlay.SHAPE_CIRCLE
		radius_units = maxi(p.radius, 512)
		length_units = 0
	_damaging = false
	for a: DefPowerAction in p.actions:
		if a.op == DefEnums.PowerOp.STRIKE or not a.impacts.is_empty():
			_damaging = true
	started.emit(false, p_idx)
	return true


## Starts targeting for the viewer's superweapon (geometry from the resolved `DefSuperweapon`).
func begin_superweapon() -> bool:
	if _roster == null or _roster.superweapon_def == null:
		return false
	var sw: DefSuperweapon = _roster.superweapon_def
	_reset()
	active = true
	kind = Kind.SUPERWEAPON
	power_idx = _roster.superweapon
	target_mode = DefEnums.TargetMode.POINT
	_vision = sw.target_vision
	var far: int = maxi(sw.radius, 0)
	for pk: DefImpactPacket in sw.packets:
		far = maxi(far, int(Vector2(float(pk.offset_x), float(pk.offset_y)).length()) + pk.radius)
	var linear: bool = sw.action_kind == DefEnums.SwAction.BEAM_SWEEP or sw.action_kind == DefEnums.SwAction.RAIL_STRIKE
	if linear:
		shape = UiWorldOverlay.SHAPE_LINE
		target_mode = DefEnums.TargetMode.LINE
		radius_units = 1024
		length_units = maxi(far * 2, 8 * CELL)
	else:
		shape = UiWorldOverlay.SHAPE_CIRCLE
		radius_units = maxi(far, 1024)
		length_units = 0
	_damaging = not sw.packets.is_empty() or sw.action_kind == DefEnums.SwAction.EMP_BURST
	started.emit(true, power_idx)
	return true


## Pointer over the world at sim position (x, y); `own_eid` = an own entity under it (or 0). Updates validity and preview.
func update(x: int, y: int, own_eid: int = 0) -> void:
	if not active:
		return
	hover = Vector2i(x, y)
	hover_eid = own_eid
	var px: int = _start.x if _pressing else x
	var py: int = _start.y if _pressing else y
	if _pressing and shape == UiWorldOverlay.SHAPE_LINE:
		var dx: int = x - _start.x
		var dy: int = y - _start.y
		if absi(dx) + absi(dy) >= DRAG_MIN_UNITS:
			angle = angle_of(dx, dy)
	_evaluate(px, py)
	if _overlay != null:
		_overlay.set_targeting_preview(shape, px, py, radius_units, angle, length_units, valid, friendly_fire and valid)


## LMB press. Point / own-target powers commit here; line powers start the angle drag.
func press(x: int, y: int, own_eid: int = 0) -> bool:
	if not active:
		return false
	update(x, y, own_eid)
	if shape == UiWorldOverlay.SHAPE_LINE:
		if not valid:
			return _deny()
		_pressing = true
		_start = Vector2i(x, y)
		return true
	return _commit(x, y, own_eid)


## LMB release: commits a line power at the press point with the dragged angle.
func release(x: int, y: int) -> bool:
	if not active or not _pressing:
		return false
	update(x, y, hover_eid)
	_pressing = false
	return _commit(_start.x, _start.y, 0)


## RMB / Esc.
func cancel() -> void:
	if active:
		_finish(false)


func is_line() -> bool:
	return shape == UiWorldOverlay.SHAPE_LINE


## A line power whose start point is set (the angle is being chosen; the next click commits).
func is_pressing() -> bool:
	return active and _pressing


func _evaluate(x: int, y: int) -> void:
	hint = ""
	valid = true
	if target_mode == DefEnums.TargetMode.OWN_STRUCTURE:
		valid = hover_eid > 0
		if not valid:
			hint = HINT_OWN_TARGET
		friendly_fire = false
		return
	var cx: int = x / CELL
	var cy: int = y / CELL
	if kind == Kind.POWER:
		valid = _sim.power_target_ok(power_idx, x, y)
		if not valid:
			hint = HINT_NEEDS_VISION
	else:
		var vis: int = _sim.visibility(cx, cy)
		match _vision:
			DefEnums.TargetVision.EXPLORED:
				valid = vis >= UiSimPort.Vis.FOG
				hint = "" if valid else HINT_UNEXPLORED
			DefEnums.TargetVision.CURRENT:
				valid = vis == UiSimPort.Vis.VISIBLE
				hint = "" if valid else HINT_NEEDS_VISION
	friendly_fire = _damaging and _own_inside(x, y)


## True when one of the viewer's entities lies inside the preview (a friendly-fire warning ring / hatch).
func _own_inside(x: int, y: int) -> bool:
	var pts: PackedVector2Array = UiWorldOverlay.preview_ground_points(shape, x, y, radius_units, angle, length_units)
	if pts.size() < 3:
		return false
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		bounds = bounds.expand(p)
	_sim.own_ids(UiSimPort.KM_UNIT | UiSimPort.KM_STRUCTURE, _ids)
	for id: int in _ids:
		if not _sim.read(id, _row):
			continue
		var q := Vector2(float(_row.x), float(_row.y))
		if bounds.has_point(q) and Geometry2D.is_point_in_polygon(q, pts):
			return true
	return false


func _commit(x: int, y: int, own_eid: int) -> bool:
	if not valid:
		return _deny()
	var ok: bool = false
	if kind == Kind.SUPERWEAPON:
		ok = _bus.launch_superweapon(x, y, angle)
	elif target_mode == DefEnums.TargetMode.OWN_STRUCTURE:
		var eid: int = own_eid if own_eid > 0 else hover_eid
		var ex: int = x
		var ey: int = y
		if _sim.read(eid, _row):
			ex = _row.x
			ey = _row.y
		ok = _bus.use_power(power_idx, ex, ey, 0, eid)
	else:
		ok = _bus.use_power(power_idx, x, y, angle)
	if ok:
		_finish(true)
	else:
		_deny()
	return ok


func _deny() -> bool:
	if _audio != null:
		_audio.ui(UiAudioPort.ERROR)
	return false


func _finish(committed: bool) -> void:
	active = false
	_pressing = false
	if _overlay != null:
		_overlay.clear_targeting_preview()
	ended.emit(committed)


func _reset() -> void:
	if active and _overlay != null:
		_overlay.clear_targeting_preview()
	active = false
	valid = false
	friendly_fire = false
	hint = ""
	angle = 0
	hover_eid = 0
	_pressing = false
