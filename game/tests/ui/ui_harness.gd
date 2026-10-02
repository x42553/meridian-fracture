extends RefCounted
## SubViewport-based input / layout harness for UI tests and labs (ui.md 10.1, spike pitfall P6: the headless root Window
## is 64 x 64, so layout and input run inside a SubViewport of the wanted size). Not a test file (no `test_*` functions).
## Usage: `var h := H.make(t)`; add controls to `h.root` (a `UiLayerRoot`, themed); `await H.frames(2)`; push events with
## `click` / `key`; free with `h.vp.queue_free()` (or `H.done(h)`).

const _Self := preload("res://tests/ui/ui_harness.gd")


## Handle returned by `make`.
class Rig extends RefCounted:
	var vp: SubViewport
	var layer: CanvasLayer
	var root: UiLayerRoot


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## A SubViewport of `size` in the scene tree with a CanvasLayer > UiLayerRoot (the production nesting, P1 / P2).
## Coroutine: `var rig: H.Rig = await H.make(size)`.
static func make(size: Vector2i = Vector2i(1920, 1080)) -> Rig:
	var r := Rig.new()
	r.vp = SubViewport.new()
	r.vp.size = size
	r.vp.disable_3d = true
	r.vp.gui_embed_subwindows = true
	r.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree().root.add_child(r.vp)
	r.layer = CanvasLayer.new()
	r.vp.add_child(r.layer)
	r.root = UiLayerRoot.new()
	r.layer.add_child(r.root)
	# nodes added to the root while the runner is still inside `_initialize` enter the tree on the first frame
	if not r.vp.is_inside_tree():
		await tree().process_frame
	return r


static func done(r: Rig) -> void:
	r.vp.queue_free()


static func frames(n: int = 1) -> void:
	for i in n:
		await tree().process_frame


static func move(vp: Viewport, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	vp.push_input(e)


## Press + release of a mouse button at `pos` (`double` marks both events as a double click).
static func click(vp: Viewport, pos: Vector2, button: int = MOUSE_BUTTON_LEFT, double: bool = false) -> void:
	move(vp, pos)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = pos
		e.global_position = pos
		e.button_index = button as MouseButton
		e.pressed = pressed
		e.double_click = double and pressed
		e.button_mask = (0 if not pressed else (1 << (button - 1))) as MouseButtonMask
		vp.push_input(e)


## Press only (for drag / release-outside cases).
static func press(vp: Viewport, pos: Vector2, button: int = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button as MouseButton
	e.pressed = pressed
	e.button_mask = ((1 << (button - 1)) if pressed else 0) as MouseButtonMask
	vp.push_input(e)


## Key press + release (physical and logical code, so InputMap actions bound to either match).
static func key(vp: Viewport, keycode: int, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode as Key
		e.physical_keycode = keycode as Key
		e.pressed = pressed
		e.shift_pressed = shift
		vp.push_input(e)


## Centre of a control in the harness viewport's coordinates.
static func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()
