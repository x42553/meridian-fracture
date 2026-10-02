extends RefCounted
## Input lab rig (ui.md 10.3, spike input lab): a 1280 x 720 SubViewport with the production nesting (CanvasLayer >
## UiLayerRoot HUD root, IGNORE) holding a STOP sidebar (buttons, label, scroll), a UiSelectRect, a `UiInputController`
## with a signal recorder, and event helpers that go through the real GUI pipeline (`Viewport.push_input`).
## Not a test file (no `test_*` functions). `var r: Rig = await Rig.make()`, ... `Rig.done(r)`.

const H := preload("res://tests/ui/ui_harness.gd")
const SIDEBAR_W: float = 300.0


## Records what reaches `_input` (before the GUI) and `_unhandled_input` (after it), motion included on request.
class Probe extends Node:
	var seen_input: PackedStringArray = PackedStringArray()
	var seen_unhandled: PackedStringArray = PackedStringArray()
	var motion_unhandled: int = 0

	func _input(e: InputEvent) -> void:
		if not (e is InputEventMouseMotion):
			seen_input.append(Rig.describe(e))

	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			motion_unhandled += 1
		else:
			seen_unhandled.append(Rig.describe(e))


class Rig extends RefCounted:
	var h: H.Rig
	var vp: SubViewport
	var hud: UiLayerRoot
	var sidebar: PanelContainer
	var button: Button
	var button2: Button
	var label: Label
	var scroll: ScrollContainer
	var rect: UiSelectRect
	var ctl: UiInputController
	var probe: Probe
	var km: UiKeymap
	var evlog: PackedStringArray = PackedStringArray()
	var pressed_count: int = 0
	var gui_log: PackedStringArray = PackedStringArray()
	var world: Vector2 = Vector2(300.0, 300.0)
	var on_sidebar: Vector2
	var on_button: Vector2
	var on_label: Vector2

	static func describe(e: InputEvent) -> String:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			return "%s %s" % [["?", "LMB", "RMB", "MMB", "wheelUp", "wheelDown"][clampi(mb.button_index, 0, 5)], "down" if mb.pressed else "up"]
		if e is InputEventKey:
			var k := e as InputEventKey
			return "key %s %s" % [OS.get_keycode_string(k.physical_keycode), "down" if k.pressed else "up"]
		return e.get_class()

	static func make(size: Vector2i = Vector2i(1280, 720)) -> Rig:
		var r := Rig.new()
		r.h = await H.make(size)
		r.vp = r.h.vp
		r.hud = r.h.root
		r.km = UiKeymap.new()
		r.km.load_defaults(0)
		r.km.install(UiKeymap.Context.GAME)
		r.sidebar = PanelContainer.new()
		r.sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		r.sidebar.offset_left = -SIDEBAR_W
		r.sidebar.gui_input.connect(func(e: InputEvent) -> void: r._gui("sidebar", e))
		r.hud.add_child(r.sidebar)
		var v := VBoxContainer.new()
		r.sidebar.add_child(v)
		r.button = Button.new()
		r.button.text = "Build"
		r.button.focus_mode = Control.FOCUS_NONE
		r.button.pressed.connect(func() -> void: r.pressed_count += 1)
		r.button.gui_input.connect(func(e: InputEvent) -> void: r._gui("button", e))
		v.add_child(r.button)
		r.button2 = Button.new()
		r.button2.text = "Sell"
		r.button2.focus_mode = Control.FOCUS_NONE
		v.add_child(r.button2)
		r.label = Label.new()
		r.label.text = "Credits 5000"
		v.add_child(r.label)
		r.scroll = ScrollContainer.new()
		r.scroll.custom_minimum_size = Vector2(0.0, 200.0)
		var tall := Control.new()
		tall.custom_minimum_size = Vector2(100.0, 900.0)
		r.scroll.add_child(tall)
		v.add_child(r.scroll)
		r.rect = UiSelectRect.new()
		r.hud.add_child(r.rect)
		r.ctl = UiInputController.new()
		r.ctl.keymap = r.km
		r.ctl.select_rect = r.rect
		r.ctl.edge_scroll = false
		r.ctl.synthetic = true
		r.ctl.assume_focused = true
		r.ctl.select_box.connect(func(rc: Rect2, m: int) -> void: r.evlog.append("box(%d,%d,%d,%d,m%d)" % [rc.position.x, rc.position.y, rc.size.x, rc.size.y, m]))
		r.ctl.select_click.connect(func(p: Vector2, m: int, d: bool) -> void: r.evlog.append("click(%d,%d,m%d%s)" % [p.x, p.y, m, ",dbl" if d else ""]))
		r.ctl.context_click.connect(func(p: Vector2, m: int) -> void: r.evlog.append("ctx(%d,%d,m%d)" % [p.x, p.y, m]))
		r.ctl.armed_click.connect(func(p: Vector2, m: int) -> void: r.evlog.append("armed(%d,%d,m%d)" % [p.x, p.y, m]))
		r.ctl.cancel_armed.connect(func() -> void: r.evlog.append("cancel_armed"))
		r.ctl.camera_zoom.connect(func(s: float, c: Vector2) -> void: r.evlog.append("zoom(%.2f@%d,%d)" % [s, c.x, c.y]))
		r.ctl.camera_pan.connect(func(d: Vector2, _dt: float) -> void: r.evlog.append("pan(%.2f,%.2f)" % [d.x, d.y]))
		r.ctl.camera_rotate.connect(func(d: float, _dt: float) -> void: r.evlog.append("rotate(%d)" % d))
		r.ctl.camera_tilt.connect(func(d: float) -> void: r.evlog.append("tilt(%d)" % d))
		r.ctl.camera_orbit.connect(func(y: float, p: float) -> void: r.evlog.append("orbit(%.2f,%.2f)" % [y, p]))
		r.ctl.action.connect(func(id: StringName) -> void: r.evlog.append("action(%s)" % id))
		r.ctl.time_override_ms = 1000000
		r.vp.add_child(r.ctl)
		r.probe = Probe.new()  # after the controller: unhandled input runs in reverse tree order, so the probe sees events first
		r.vp.add_child(r.probe)
		await H.frames(2)
		r.on_sidebar = Vector2(float(size.x) - 150.0, 400.0)
		r.on_button = r.button.global_position + Vector2(20.0, 10.0)
		r.on_label = r.label.global_position + Vector2(10.0, 5.0)
		return r

	static func done(r: Rig) -> void:
		r.km.uninstall(0)
		H.done(r.h)

	func _gui(who: String, e: InputEvent) -> void:
		if not (e is InputEventMouseMotion):
			gui_log.append("%s.%s" % [who, describe(e)])

	## Starts a fresh observation window.
	func reset() -> void:
		evlog.clear()
		gui_log.clear()
		pressed_count = 0
		probe.seen_input.clear()
		probe.seen_unhandled.clear()
		probe.motion_unhandled = 0

	func motion(p: Vector2, mask: int = 0, rel: Vector2 = Vector2.ZERO) -> void:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		m.relative = rel
		m.button_mask = mask as MouseButtonMask
		vp.push_input(m)

	func btn(p: Vector2, index: int, pressed: bool, mods: int = 0) -> void:
		var b := InputEventMouseButton.new()
		b.button_index = index as MouseButton
		b.pressed = pressed
		b.position = p
		b.global_position = p
		b.shift_pressed = (mods & KEY_MASK_SHIFT) != 0
		b.ctrl_pressed = (mods & KEY_MASK_CTRL) != 0
		b.alt_pressed = (mods & KEY_MASK_ALT) != 0
		b.button_mask = ((1 << (index - 1)) if pressed and index <= 3 else 0) as MouseButtonMask
		vp.push_input(b)

	func click(p: Vector2, index: int = MOUSE_BUTTON_LEFT, mods: int = 0) -> void:
		ctl.time_override_ms += 1000  # separate clicks never form a double click by accident
		motion(p)
		btn(p, index, true, mods)
		btn(p, index, false, mods)

	## Key press (+ release when `release`): physical keycode plus modifier mask bits (KEY_MASK_*).
	func key(code: int, mods: int = 0, release: bool = true) -> void:
		for pressed: bool in [true, false]:
			if not pressed and not release:
				return
			var e: InputEventKey = UiKeymap.unpack(code | mods)
			e.keycode = code as Key
			e.pressed = pressed
			vp.push_input(e)

	func hovered() -> Control:
		return vp.gui_get_hovered_control()
