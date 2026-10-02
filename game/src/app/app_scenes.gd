extends Node
## Autoload `AppScenes` (no class_name, ui.md 2.1 / 3.1): the layer stack (backdrop / screen / overlay / fade / debug), screen
## instantiate-enter-exit with fade transitions, overlay screens (`push` / `pop`), the modal dialog stack, the toast host and
## the theme distribution to every `UiLayerRoot` (pitfall P1: the theme is assigned on the first Control under each
## CanvasLayer, which `UiLayerRoot` does through `UiThemeService`). The layers are built lazily so the node also works
## where `_ready` has not run.

signal screen_changed(id: StringName)
## A screen asked to open another one (`UiScreen.navigate`); `AppState` maps it to a flow mode.
signal navigate_requested(target: StringName, params: Dictionary)
## The current top screen asked to go back (Esc on a menu root, its Back button).
signal back_requested()
## Emitted when the last queued transition finished.
signal transition_finished()

enum Layer { BACKDROP = 0, SCREEN = 1, OVERLAY = 2, FADE = 3, DEBUG = 4 }

## CanvasLayer index of every `Layer`.
const LAYER_INDEX: Array[int] = [0, 10, 40, 90, 100]
const TOAST_MAX: int = 5

var screen: UiScreen = null
var dialogs: UiDialogStack = null

var _built: bool = false
var _layers: Array[CanvasLayer] = []
var _roots: Array[UiLayerRoot] = []
var _backdrop3d: Node3D = null
var _fade: ColorRect = null
var _toasts: VBoxContainer = null
var _busy: bool = false
var _pending: Dictionary = {}
var _pushed: Array[Dictionary] = []
var _fps_label: Label = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	ensure_built()


## Builds the layers once (idempotent).
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_backdrop3d = Node3D.new()
	_backdrop3d.name = "BackdropHost"
	add_child(_backdrop3d)
	for i: int in LAYER_INDEX.size():
		var cl: CanvasLayer = CanvasLayer.new()
		cl.layer = LAYER_INDEX[i]
		cl.name = String(Layer.keys()[i]).capitalize().replace(" ", "")
		add_child(cl)
		var root: UiLayerRoot = UiLayerRoot.new()
		root.name = "Root"
		cl.add_child(root)
		_layers.append(cl)
		_roots.append(root)
	_fade = ColorRect.new()
	_fade.color = UiPalette.BG_DEEP
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_roots[Layer.FADE].add_child(_fade)
	UiLayerRoot.fill(_fade)
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.custom_minimum_size = Vector2(420.0, 0.0)
	_roots[Layer.OVERLAY].add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_left = -440.0
	_toasts.offset_right = -20.0
	_toasts.offset_top = 20.0
	dialogs = UiDialogStack.new()
	add_child(dialogs)
	dialogs.attach(_roots[Layer.OVERLAY])


# ---------------------------------------------------------------- layers

## The `UiLayerRoot` of a layer (BACKDROP: the 2D backdrop root; the 3D host is `backdrop_host()`).
func layer_root(layer: int) -> Control:
	ensure_built()
	return _roots[clampi(layer, 0, _roots.size() - 1)]


func backdrop_host() -> Node3D:
	ensure_built()
	return _backdrop3d


## Replaces the 3D backdrop (main menu showcase); the previous one is freed.
func set_backdrop(n: Node3D) -> void:
	clear_backdrop()
	if n != null:
		_backdrop3d.add_child(n)


func clear_backdrop() -> void:
	ensure_built()
	for c: Node in _backdrop3d.get_children():
		_backdrop3d.remove_child(c)
		c.queue_free()


## Assigns `t` to every layer root (the theme service does this on rebuild; this is for a custom theme).
func set_theme(t: Theme) -> void:
	ensure_built()
	for r: UiLayerRoot in _roots:
		r.theme = t


## The fade curtain alpha (tests).
func fade_alpha() -> float:
	ensure_built()
	return _fade.modulate.a


func is_busy() -> bool:
	return _busy


# ---------------------------------------------------------------- screens

## Replaces the screen: fade out 0.18 s -> exit -> free -> enter -> fade in 0.22 s. Requests made during a transition are
## coalesced (the last one wins). `AppScenes.transition_finished` fires when the queue is empty.
func goto(id: StringName, params: Dictionary = {}, fade: bool = true) -> void:
	ensure_built()
	_pending = {"id": id, "params": params, "fade": fade}
	if _busy:
		return
	_busy = true
	@warning_ignore("missing_await")
	_drain()


func _drain() -> void:
	while not _pending.is_empty():
		var req: Dictionary = _pending
		_pending = {}
		await _transition(StringName(req["id"]), req["params"] as Dictionary, bool(req["fade"]))
	_busy = false
	transition_finished.emit()


func _transition(id: StringName, params: Dictionary, fade: bool) -> void:
	if not AppScreens.is_valid_id(id):
		Log.error("app", "goto: unknown screen '%s'" % id)
		return
	if fade and screen != null:
		await _fade_to(1.0, UiMotion.SCREEN_OUT_S)
	_release_pushed()
	_release_screen()
	var s: UiScreen = AppScreens.make(id)
	if s == null:
		await _fade_to(0.0, UiMotion.SCREEN_IN_S)
		return
	screen = s
	_roots[Layer.SCREEN].add_child(s)
	_wire(s)
	s.enter(params)
	if id != &"game" and id != &"splash":
		s.setup_menu_focus()
	screen_changed.emit(id)
	if fade or _fade.modulate.a > 0.0:
		await _fade_to(0.0, UiMotion.SCREEN_IN_S)


func _fade_to(alpha: float, seconds: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	var tw: Tween = UiMotion.fade(self, _fade, alpha, seconds)
	if tw != null:
		await tw.finished
	if alpha <= 0.0:
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _wire(s: UiScreen) -> void:
	s.back_requested.connect(func() -> void: back_requested.emit())
	s.navigate.connect(func(target: StringName, p: Dictionary) -> void: navigate_requested.emit(target, p))


## Quit: runs `exit()` of every overlay and of the base screen (each releases its ports, sessions, textures, signal lambdas) so nothing of the UI
## graph is left in a reference cycle when the engine tears the tree down. The scene tree itself is not touched beyond that.
func release_for_quit() -> void:
	_pending = {}
	if (screen != null and not screen.is_inside_tree()) or (not _pushed.is_empty() and not is_inside_tree()):
		return  # the tree is already coming down: a screen cannot run exit() (no SceneTree any more), the engine frees it
	_release_pushed()
	_release_screen()


func _release_screen() -> void:
	if screen == null:
		return
	var old: UiScreen = screen
	screen = null
	old.exit()
	if old.get_parent() != null:
		old.get_parent().remove_child(old)
	old.queue_free()


## Overlay screen above the live one; the lower screen stops reacting to Escape and clicks are blocked by a shield.
func push(id: StringName, params: Dictionary = {}) -> void:
	ensure_built()
	if not AppScreens.is_valid_id(id):
		Log.error("app", "push: unknown screen '%s'" % id)
		return
	var s: UiScreen = AppScreens.make(id)
	if s == null:
		return
	var lower: UiScreen = top_screen()
	var shield: Control = Control.new()
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.focus_mode = Control.FOCUS_NONE
	_roots[Layer.SCREEN].add_child(shield)
	UiLayerRoot.fill(shield)
	var prev_focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if lower != null:
		lower.handles_escape = false
		if prev_focus != null and lower.is_ancestor_of(prev_focus):
			prev_focus.release_focus()
	_roots[Layer.SCREEN].add_child(s)
	_wire(s)
	_pushed.append({"screen": s, "shield": shield, "focus": prev_focus, "lower": lower})
	s.enter(params)
	s.setup_menu_focus()
	screen_changed.emit(id)


## Removes the top overlay screen and re-enables the one below.
func pop() -> void:
	if _pushed.is_empty():
		return
	var e: Dictionary = _pushed.pop_back()
	var s: UiScreen = e["screen"] as UiScreen
	if is_instance_valid(s):
		s.exit()
		if s.get_parent() != null:
			s.get_parent().remove_child(s)
		s.queue_free()
	var shield: Control = e["shield"] as Control
	if is_instance_valid(shield):
		shield.get_parent().remove_child(shield)
		shield.queue_free()
	var lower: UiScreen = e["lower"] as UiScreen
	if lower != null and is_instance_valid(lower):
		lower.handles_escape = not (lower is AppSplash)
	var f: Control = e["focus"] as Control
	if f != null and is_instance_valid(f) and f.is_visible_in_tree():
		f.grab_focus()
	var top: UiScreen = top_screen()
	if top != null:
		screen_changed.emit(top.screen_id)


func pushed_count() -> int:
	return _pushed.size()


## The screen that currently receives input: the top overlay, else the base screen.
func top_screen() -> UiScreen:
	if not _pushed.is_empty():
		return (_pushed[_pushed.size() - 1] as Dictionary)["screen"] as UiScreen
	return screen


func _release_pushed() -> void:
	while not _pushed.is_empty():
		pop()


# ---------------------------------------------------------------- modal and toast

func modal(dlg: UiDialog) -> void:
	ensure_built()
	dialogs.push(dlg)


## Non-blocking toast in the top-right stack. `actions`: `[{label_key: StringName, label?: String, call: Callable}]`; a toast
## with actions stays 10 s. Severity: `UiToast.Severity` (0 info, 1 warn, 2 error).
func toast(text: String, severity: int = 0, actions: Array[Dictionary] = []) -> UiToast:
	ensure_built()
	var acts: Array[Dictionary] = []
	for a: Dictionary in actions:
		var label: String = str(a.get("label", ""))
		if label.is_empty() and a.has("label_key"):
			label = UiA11y.resolve_text(StringName(a["label_key"]))
		acts.append({"label": label, "call": a.get("call", Callable())})
	var t: UiToast = UiToast.make(text, severity, acts)
	if not acts.is_empty():
		t.hold_s = 10.0
	while _toasts.get_child_count() >= TOAST_MAX:
		var oldest: Node = _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	_toasts.add_child(t)
	return t


func toast_count() -> int:
	ensure_built()
	return _toasts.get_child_count()


# ---------------------------------------------------------------- debug overlay

## `ui/show_fps`: a small frame counter in the DEBUG layer.
func set_fps_visible(on: bool) -> void:
	ensure_built()
	if on and _fps_label == null:
		_fps_label = Label.new()
		_fps_label.theme_type_variation = &"CaptionLabel"
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_roots[Layer.DEBUG].add_child(_fps_label)
		_fps_label.position = Vector2(12.0, 8.0)
	if _fps_label != null:
		_fps_label.visible = on
	set_process(on)


func _process(_delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
