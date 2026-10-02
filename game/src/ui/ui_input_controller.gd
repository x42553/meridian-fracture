class_name UiInputController
extends Node
## World input state machine (ui.md 3.3, 5.5). The proven pattern of the spike's input lab (cases A-S):
##  * gestures START in `_unhandled_input`, so a click on any STOP Control (sidebar, button) can never start a drag;
##  * once one is active `_input` (which runs before the GUI) sees every event and consumes it, so the rectangle keeps
##    following the pointer over the sidebar and the HUD never sees the release;
##  * `tick()` (called by the screen every frame) polls `Input` for a lost release, camera keys and the edge scroll band;
##  * focus loss, modal open, resize and Esc cancel the gesture and emit nothing.
## Outputs are signals only; the screen turns them into selection changes and `UiCommandBus` intents. Keys are matched
## through `UiKeymap` (exact match) against the actions installed in the InputMap.

signal select_box(rect: Rect2, mode: int)  ## mode: 0 replace, 1 add
signal select_click(pos: Vector2, mode: int, double: bool)  ## mode: 0 replace, 1 toggle
signal context_click(pos: Vector2, mods: int)  ## RMB press in the world; mods = UiKeymap.MOD_* bits
signal armed_click(pos: Vector2, mods: int)  ## LMB while a command mode is armed
signal cancel_armed()  ## RMB while a command mode is armed: the screen disarms (no order)
signal camera_pan(dir: Vector2, delta: float)
signal camera_rotate(dir: float, delta: float)  ## keyboard Q/E: dir = +-1, the rig applies rotate_speed x delta
signal camera_tilt(deg: float)  ## PageUp / PageDown: +-1 degree per repeat
signal camera_orbit(yaw_deg: float, tilt_deg: float)  ## MMB drag, already in degrees
signal camera_zoom(steps: float, cursor: Vector2)
signal action(id: StringName)  ## a keymap action fired (exact match); polled camera actions are not emitted
signal hover_changed(pos: Vector2, over_ui: bool)  ## <= 30 Hz while the pointer moves

enum State { IDLE = 0, PRESS = 1, BOX = 2, ORBIT = 3 }

const FOCUS_SWALLOW_MS: int = 150  ## an LMB press this soon after FOCUS_IN starts no gesture
const EDGE_GRACE_MS: int = 500  ## no edge scroll this soon after the window regained focus
const HOVER_INTERVAL_MS: int = 33
const ORBIT_DEG_PER_PX: float = 0.22
const POLLED_ACTIONS: PackedStringArray = [
	"cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down", "cam_rotate_left", "cam_rotate_right",
]

var enabled: bool = true:  ## false while a modal is open (mouse + keys)
	set(v):
		if not v:
			cancel_gesture()
		enabled = v
var enabled_keys: bool = true  ## false while a LineEdit has focus (5.5.8); also derived from the focus owner
var edge_scroll: bool = true
var select_rect: UiSelectRect = null
var armed: int = UiModes.Armed.NONE  ## UiModes.Armed, kept in sync by the screen
var state: int = State.IDLE
var keymap: UiKeymap = null  ## default: the shared instance
## func(pos: Vector2) -> int: the OWN unit under `pos` (-1 = none); the double-click detector requires both presses on the
## same one. Not set = position and time alone decide.
var hit_probe: Callable = Callable()
var synthetic: bool = false  ## tests: pushed events do not update Input, so skip the lost-release poll
var assume_focused: bool = false  ## skip `Window.has_focus()` (the headless root window never has it)
var drag_threshold: float = 6.0
var double_click_ms: int = 350
var double_click_px: float = 8.0
var key_scroll_speed: float = 1.0  ## input/key_scroll_speed / 100
var edge_scroll_speed: float = 1.0  ## access/edge_scroll_speed / 100
var zoom_speed: float = 1.0
var orbit_speed: float = 1.0
var invert_zoom: bool = false
var invert_orbit: bool = false
var orbit_toggle: bool = false  ## input/orbit_mode 1: click once to start, again to stop
var edge_dir: Vector2 = Vector2.ZERO  ## the scroll band the pointer is in (the cursor shows the matching arrow)
var time_override_ms: int = -1  ## tests: replaces `Time.get_ticks_msec()`

var _press_pos: Vector2 = Vector2.ZERO
var _press_mods: int = 0
var _press_time: int = 0
var _press_hit: int = -1
var _press_double: bool = false
var _last_click_ms: int = -1000000
var _last_click_pos: Vector2 = Vector2.ZERO
var _last_click_hit: int = -1
var _pointer: Vector2 = Vector2(-1.0, -1.0)
var _pointer_seen: bool = false
var _pointer_inside: bool = true
var _hover_dirty: bool = false
var _hover_ms: int = -1000
var _focused: bool = true
var _focus_in_ms: int = -1000000


func _ready() -> void:
	var vp: Viewport = get_viewport()
	if vp != null and not vp.size_changed.is_connected(cancel_gesture):
		vp.size_changed.connect(cancel_gesture)


## Reads the input settings (ids of ui.md 4.8): drag threshold, double click, speeds, inversion, orbit mode, edge scroll.
func configure(store: AppSettingsStore) -> void:
	drag_threshold = float(store.get_value(&"input/drag_threshold"))
	double_click_ms = int(store.get_value(&"input/double_click_ms"))
	key_scroll_speed = float(store.get_value(&"input/key_scroll_speed")) / 100.0
	edge_scroll_speed = float(store.get_value(&"access/edge_scroll_speed")) / 100.0
	zoom_speed = float(store.get_value(&"input/zoom_speed")) / 100.0
	orbit_speed = float(store.get_value(&"input/rotate_speed")) / 100.0
	invert_zoom = bool(store.get_value(&"input/invert_zoom"))
	invert_orbit = bool(store.get_value(&"input/invert_orbit"))
	orbit_toggle = int(store.get_value(&"input/orbit_mode")) == 1
	edge_scroll = bool(store.get_value(&"access/edge_scroll_enabled"))


# ---- pure helpers ---------------------------------------------------------------------------------------------------
## Screen-edge scroll vector for a pointer position; zero outside the window rectangle (a pointer that left the window
## keeps its last position). 1920x1080, margin 6: (2, 300) -> (-1, 0); (1919, 1079) -> (1, 1); (-40, 300) -> (0, 0).
static func edge_direction(p: Vector2, view: Rect2, margin: float = 6.0) -> Vector2:
	if not view.has_point(p):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if p.x <= view.position.x + margin:
		d.x = -1.0
	elif p.x >= view.end.x - margin:
		d.x = 1.0
	if p.y <= view.position.y + margin:
		d.y = -1.0
	elif p.y >= view.end.y - margin:
		d.y = 1.0
	return d


## Euclidean distance press -> cur >= threshold (logical px).
static func drag_exceeded(press: Vector2, cur: Vector2, threshold: float = 6.0) -> bool:
	return press.distance_to(cur) >= threshold


func gesture_active() -> bool:
	return state != State.IDLE


func _now() -> int:
	return time_override_ms if time_override_ms >= 0 else Time.get_ticks_msec()


func _km() -> UiKeymap:
	if keymap == null:
		keymap = UiKeymap.instance()
	return keymap


## False while a modal is open, keys are disabled or a text field owns the focus.
func keys_ok() -> bool:
	if not enabled or not enabled_keys:
		return false
	var vp: Viewport = get_viewport()
	if vp != null:
		var f: Control = vp.gui_get_focus_owner()
		if f is LineEdit or f is TextEdit:
			return false
	return true


# ---- input ------------------------------------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		_on_key(event as InputEventKey)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		camera_zoom.emit((mg.factor - 1.0) * 8.0 * zoom_speed * (-1.0 if invert_zoom else 1.0), mg.position)
		_handled()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if pg.delta.y != 0.0:
			camera_zoom.emit(-pg.delta.y * 0.5 * zoom_speed * (-1.0 if invert_zoom else 1.0), pg.position)
			_handled()


## Runs before the GUI: tracks the pointer and drives an active world gesture (consuming its events).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pointer = mm.position
		_pointer_seen = true
		_pointer_inside = true
		_hover_dirty = true
		if state == State.IDLE:
			return
		_on_motion(mm)
		_handled()
		return
	if state == State.IDLE:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE):
			cancel_gesture()
			_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if not mb.pressed and (state == State.PRESS or state == State.BOX):
					_finish(mb)
					_handled()
			MOUSE_BUTTON_MIDDLE:
				if state == State.ORBIT and ((mb.pressed and orbit_toggle) or (not mb.pressed and not orbit_toggle)):
					state = State.IDLE
					_handled()


func _on_motion(mm: InputEventMouseMotion) -> void:
	match state:
		State.PRESS:
			if armed == UiModes.Armed.NONE and drag_exceeded(_press_pos, mm.position, drag_threshold):
				state = State.BOX
				_show_rect(mm.position)
		State.BOX:
			_show_rect(mm.position)
		State.ORBIT:
			var inv: float = -1.0 if invert_orbit else 1.0
			camera_orbit.emit(-mm.relative.x * ORBIT_DEG_PER_PX * orbit_speed * inv, mm.relative.y * ORBIT_DEG_PER_PX * orbit_speed * inv)


func _show_rect(cur: Vector2) -> void:
	if select_rect != null:
		select_rect.show_rect(Rect2(_press_pos, cur - _press_pos).abs())


func _on_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed and state == State.IDLE:
				if _now() - _focus_in_ms <= FOCUS_SWALLOW_MS:
					_handled()  # the click that regained focus starts nothing
					return
				_press(mb)
				_handled()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed and state == State.IDLE:
				if armed == UiModes.Armed.NONE:
					context_click.emit(mb.position, _km().mods_of(mb))
				else:
					cancel_armed.emit()
				_handled()
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed and state == State.IDLE:
				state = State.ORBIT
				_handled()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			if mb.shift_pressed and armed == UiModes.Armed.PLACE:
				action.emit(&"place_rotate")
			else:
				var dir: float = 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				camera_zoom.emit(dir * maxf(mb.factor, 0.01) * zoom_speed * (-1.0 if invert_zoom else 1.0), mb.position)
			_handled()


func _press(mb: InputEventMouseButton) -> void:
	state = State.PRESS
	_press_pos = mb.position
	_press_mods = _km().mods_of(mb)
	_press_time = _now()
	_press_hit = int(hit_probe.call(mb.position)) if hit_probe.is_valid() else -1
	var same: bool = true
	if hit_probe.is_valid():
		same = _press_hit >= 0 and _press_hit == _last_click_hit
	_press_double = armed == UiModes.Armed.NONE and _press_time - _last_click_ms <= double_click_ms \
			and _press_pos.distance_to(_last_click_pos) <= double_click_px and same


func _finish(mb: InputEventMouseButton) -> void:
	var was_box: bool = state == State.BOX
	var mods: int = _press_mods | _km().mods_of(mb)
	var pos: Vector2 = _press_pos
	state = State.IDLE
	if select_rect != null:
		select_rect.hide_rect()
	if was_box:
		select_box.emit(Rect2(_press_pos, mb.position - _press_pos).abs(), 1 if (mods & UiKeymap.MOD_SHIFT) != 0 else 0)
		return
	if armed != UiModes.Armed.NONE:
		armed_click.emit(pos, mods)
		return
	if _press_double:
		_last_click_ms = -1000000  # a third click is a fresh single click
	else:
		_last_click_ms = _press_time
		_last_click_pos = pos
		_last_click_hit = _press_hit
	select_click.emit(pos, 1 if (mods & UiKeymap.MOD_SHIFT) != 0 else 0, _press_double)


func _on_key(ev: InputEventKey) -> void:
	if not ev.pressed or not keys_ok():
		return
	var km: UiKeymap = _km()
	for id: StringName in km.installed_ids():
		var d: UiActions.Def = km.def_of(id)
		if not km.matches(ev, id, d.repeat):
			continue
		_handled()
		_dispatch_action(id)
		return


func _dispatch_action(id: StringName) -> void:
	if POLLED_ACTIONS.has(String(id)):
		return
	var cursor: Vector2 = _pointer if _pointer_seen else Vector2.ZERO
	var inv: float = -1.0 if invert_zoom else 1.0
	match id:
		&"cam_tilt_up":
			camera_tilt.emit(1.0)
		&"cam_tilt_down":
			camera_tilt.emit(-1.0)
		&"cam_zoom_in":
			camera_zoom.emit(zoom_speed * inv, cursor)
		&"cam_zoom_out":
			camera_zoom.emit(-zoom_speed * inv, cursor)
		&"toggle_edge_scroll":
			edge_scroll = not edge_scroll
			if not edge_scroll:
				edge_dir = Vector2.ZERO
			action.emit(id)
		_:
			action.emit(id)


func _handled() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## Cancels a PRESS / BOX / ORBIT gesture: the rectangle hides and nothing is emitted.
func cancel_gesture() -> void:
	state = State.IDLE
	if select_rect != null:
		select_rect.hide_rect()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			edge_dir = Vector2.ZERO
			cancel_gesture()
		NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_focus_in_ms = _now()
		NOTIFICATION_WM_MOUSE_EXIT:
			_pointer_inside = false
			edge_dir = Vector2.ZERO
		NOTIFICATION_WM_MOUSE_ENTER:
			_pointer_inside = true


func _window_focused() -> bool:
	if not _focused:
		return false
	if assume_focused or DisplayServer.get_name() == "headless":
		return true
	var w: Window = get_window()
	return w == null or w.has_focus()


# ---- per frame --------------------------------------------------------------------------------------------------------
## Called by the screen once per rendered frame (P3a): lost-release poll, polled camera keys, edge scroll, hover probe.
func tick(delta: float) -> void:
	if not enabled:
		edge_dir = Vector2.ZERO
		return
	if (state == State.PRESS or state == State.BOX) and not synthetic and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cancel_gesture()
	var dir: Vector2 = Vector2.ZERO
	if keys_ok():
		dir = Vector2(_axis(&"cam_pan_right", &"cam_pan_left"), _axis(&"cam_pan_down", &"cam_pan_up")).limit_length(1.0) * key_scroll_speed
		var rot: float = _axis(&"cam_rotate_right", &"cam_rotate_left")
		if rot != 0.0:
			camera_rotate.emit(rot, delta)
	edge_dir = Vector2.ZERO
	if edge_scroll and state == State.IDLE and _pointer_inside and _window_focused() and _now() - _focus_in_ms >= EDGE_GRACE_MS:
		var vp: Viewport = get_viewport()
		if vp != null:
			var p: Vector2 = _pointer if _pointer_seen else vp.get_mouse_position()
			edge_dir = edge_direction(p, vp.get_visible_rect())
	dir += edge_dir * edge_scroll_speed
	UiCursors.set_scroll(Vector2i(int(signf(edge_dir.x)), int(signf(edge_dir.y))))  # the edge-scroll arrow while the pointer is in the band
	if dir != Vector2.ZERO:
		camera_pan.emit(dir, delta)
	if _hover_dirty and _now() - _hover_ms >= HOVER_INTERVAL_MS:
		_hover_dirty = false
		_hover_ms = _now()
		var vp2: Viewport = get_viewport()
		hover_changed.emit(_pointer, vp2 != null and vp2.gui_get_hovered_control() != null)


func _axis(pos: StringName, neg: StringName) -> float:
	var v: float = 0.0
	if InputMap.has_action(pos) and Input.is_action_pressed(pos, true):
		v += 1.0
	if InputMap.has_action(neg) and Input.is_action_pressed(neg, true):
		v -= 1.0
	return v
