extends RefCounted
## Headless input scripting on a REAL SimWorld (UI-09a / UI-04b acceptance, ui.md 10.4): synthetic mouse and key events go
## through the GUI pipeline of a SubViewport into the input controller; box-select, right-click move / attack, armed
## attack-move, control-group assign / recall and bookmarks produce the right commands through the command bus, the
## loopback net port and `SimWorld`, which then executes them. The picking data comes from the fixture view adapter over
## `UiSimPortWorld`, so the ray / box picks are the fixture reference implementation of ViewPicker's rules.

const KIT := preload("res://tests/support/sim_econ_kit.gd")
const H := preload("res://tests/ui/ui_harness.gd")
const G := preload("res://tests/ui/ui_input_glue.gd")
const V := preload("res://src/ui/ui_view_port.gd")
const CELL: int = SimConfig.CELL


class Rig extends RefCounted:
	var w: SimWorld
	var port: UiSimPortWorld
	var net: UiNetPortLoopback
	var bus: UiCommandBus = UiCommandBus.new()
	var view: UiViewPortFixture
	var vp: SubViewport
	var km: UiKeymap
	var ctl: UiInputController
	var glue: G
	var issued: Array[PackedInt32Array] = []
	var tanks: Array[SimEntity] = []
	var rifle: SimEntity
	var foe: SimEntity

	func step(n: int = 1) -> void:
		for _i: int in n:
			w.step()
		view.refresh()

	func motion(p: Vector2, mask: int = 0) -> void:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
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
		b.button_mask = ((1 << (index - 1)) if pressed else 0) as MouseButtonMask
		vp.push_input(b)

	func click(p: Vector2, index: int = MOUSE_BUTTON_LEFT, mods: int = 0) -> void:
		ctl.time_override_ms += 1000
		motion(p)
		btn(p, index, true, mods)
		btn(p, index, false, mods)

	func drag(a: Vector2, b: Vector2, mods: int = 0) -> void:
		motion(a)
		btn(a, MOUSE_BUTTON_LEFT, true, mods)
		motion(a.lerp(b, 0.5), MOUSE_BUTTON_MASK_LEFT)
		motion(b, MOUSE_BUTTON_MASK_LEFT)
		btn(b, MOUSE_BUTTON_LEFT, false, mods)

	func key(code: int, mods: int = 0) -> void:
		for pressed: bool in [true, false]:
			var e: InputEventKey = UiKeymap.unpack(code | mods)
			e.keycode = code as Key
			e.pressed = pressed
			vp.push_input(e)

	## Viewport pixel of a sim point on the ground.
	func screen_of(sx: int, sy: int) -> Vector2:
		var out: PackedVector2Array = PackedVector2Array()
		view.project_points(PackedInt32Array([sx, sy]), out)
		return out[0]

	func centre_of(e: SimEntity) -> Vector2:
		return view.entity_screen_rect(e.id).get_center()

	func last() -> String:
		return UiCmdCodec.describe(issued.back()) if not issued.is_empty() else "(none)"


func _rig() -> Rig:
	var r := Rig.new()
	r.w = KIT.make_world({"start_mode": 0, "rules": {"start_credits": 5000}})
	r.port = UiSimPortWorld.new(r.w, 0)
	r.net = UiNetPortLoopback.new(r.w, 0)
	var fb := UiFeedback.new()
	fb.setup(null, null, UiAudioPortRecorder.new(), null)
	r.bus.setup(r.net, r.port, null, UiAudioPortRecorder.new(), fb)
	r.bus.issued.connect(func(_k: int, cmd: PackedInt32Array) -> void: r.issued.append(cmd))
	for i: int in 3:
		r.tanks.append(SimTestKit.spawn_tank(r.w, 0, (30 + 2 * i) * CELL, (30 + (i % 2) * 2) * CELL))
	r.rifle = SimTestKit.spawn_rifle(r.w, 0, 33 * CELL, 31 * CELL)
	r.foe = SimTestKit.spawn_tank(r.w, 1, 38 * CELL, 31 * CELL)
	r.w.step()
	return r


func _wire(r: Rig) -> void:
	r.vp = SubViewport.new()
	r.vp.size = Vector2i(1920, 1080)
	r.vp.disable_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(r.vp)
	await (Engine.get_main_loop() as SceneTree).process_frame
	r.view = UiViewPortFixture.new(r.port, 0.0, false)
	r.view.attach(r.vp)
	r.view.distance = 80.0
	r.view.focus_on_sim(34 * CELL, 31 * CELL, true)
	r.view.refresh()
	r.km = UiKeymap.new()
	r.km.load_defaults(0)
	r.km.install(UiKeymap.Context.GAME)
	r.ctl = UiInputController.new()
	r.ctl.keymap = r.km
	r.ctl.edge_scroll = false
	r.ctl.synthetic = true
	r.ctl.assume_focused = true
	r.ctl.time_override_ms = 500000
	r.vp.add_child(r.ctl)
	r.glue = G.new()
	r.glue.setup(r.port, r.view, r.bus, r.ctl)
	await (Engine.get_main_loop() as SceneTree).process_frame


func _done(r: Rig) -> void:
	r.km.uninstall(0)
	r.view.dispose()
	r.vp.queue_free()


func _ids(list: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for e: Variant in list:
		out.append((e as SimEntity).id)
	out.sort()
	return out


func test_box_select_then_right_click_move(t: TestCtx) -> void:
	var r: Rig = _rig()
	await _wire(r)
	var own: Array = r.tanks + [r.rifle]
	# drag a rectangle around the four own units (the enemy tank is 4 cells further right)
	var box: Rect2 = r.view.entity_screen_rect(r.tanks[0].id)
	for e: Variant in own:
		box = box.merge(r.view.entity_screen_rect((e as SimEntity).id))
	box = box.grow(12.0)
	r.drag(box.position, box.end)
	t.eq(r.glue.sel.sorted_ids(), _ids(own), "box-select picked the four own units and not the enemy")
	t.eq(r.glue.sel.mode, UiSelection.Mode.UNITS)
	t.eq(r.view.selection_ids.size(), 4, "the view was told the selection")
	# right-click on the ground -> one MOVE for the whole selection
	var goal: Vector2 = r.screen_of(46 * CELL + 512, 34 * CELL + 512)
	r.click(goal, MOUSE_BUTTON_RIGHT)
	t.eq(r.issued.size(), 1, "one command for the whole selection")
	var g: Vector3 = r.view.pick_ground(goal)
	var sx: Vector2i = r.view.world_to_sim(g)
	var expect: String = UiCmdCodec.describe(UiCmdCodec.move(_ids(own), sx.x, sx.y, false))
	t.eq(r.last(), expect, "MOVE ids sorted, target = the ground point under the cursor")
	t.eq(r.net.pending_count(), 1, "the loopback queued it for the sim")
	r.step(2)
	for e: Variant in own:
		var se: SimEntity = e
		t.check(not se.orders.is_empty() and se.orders[0].type == SimOrder.T_MOVE, "entity %d executes a MOVE" % se.id)
		t.eq(Vector2i(se.orders[0].x, se.orders[0].y), sx, "toward the clicked ground point")
	# Shift + right-click queues a second leg
	var goal2: Vector2 = r.screen_of(46 * CELL + 512, 28 * CELL + 512)
	r.click(goal2, MOUSE_BUTTON_RIGHT, KEY_MASK_SHIFT)
	r.step(2)
	t.eq(r.issued.size(), 2)
	t.check(r.last().contains("mode=1"), "Shift queued (append) - %s" % r.last())
	t.check(r.tanks[0].orders.size() >= 2, "the second leg is queued in the sim")
	_done(r)


func test_right_click_enemy_attacks_and_shift_click_toggles(t: TestCtx) -> void:
	var r: Rig = _rig()
	await _wire(r)
	# click a tank to select it, shift-click the rifle to add it... (toggle), then RMB the enemy
	r.click(r.centre_of(r.tanks[0]))
	t.eq(r.glue.sel.ids, PackedInt32Array([r.tanks[0].id]), "click selects one own unit")
	r.click(r.centre_of(r.rifle), MOUSE_BUTTON_LEFT, KEY_MASK_SHIFT)
	t.eq(r.glue.sel.sorted_ids(), _ids([r.tanks[0], r.rifle]), "Shift + click adds")
	r.click(r.centre_of(r.rifle), MOUSE_BUTTON_LEFT, KEY_MASK_SHIFT)
	t.eq(r.glue.sel.ids, PackedInt32Array([r.tanks[0].id]), "and toggles it off again")
	r.click(r.centre_of(r.foe), MOUSE_BUTTON_RIGHT)
	t.eq(r.issued.size(), 1)
	t.eq(r.last(), UiCmdCodec.describe(UiCmdCodec.attack(PackedInt32Array([r.tanks[0].id]), r.foe.id, false, false)), "RMB on the enemy = ATTACK")
	r.step(2)
	var a: SimEntity = r.tanks[0]
	t.check(not a.orders.is_empty() and a.orders[0].type == SimOrder.T_ATTACK and a.orders[0].target_id == r.foe.id, "the sim executes the attack")
	# clicking the enemy selects it as a FOREIGN inspect selection, and a right click then issues nothing
	r.click(r.centre_of(r.foe))
	t.eq(r.glue.sel.mode, UiSelection.Mode.FOREIGN, "an enemy click is an inspect selection")
	var n: int = r.issued.size()
	r.click(r.screen_of(40 * CELL, 33 * CELL), MOUSE_BUTTON_RIGHT)
	t.eq(r.issued.size(), n, "no order from a foreign selection")
	# clicking empty ground clears
	r.click(r.screen_of(24 * CELL, 26 * CELL))
	t.check(r.glue.sel.is_empty(), "click on empty ground clears the selection")
	# a fogged enemy cannot be clicked: hide it and click where it stands
	var spot: Vector2 = r.centre_of(r.foe)
	r.click(r.centre_of(r.tanks[1]))
	r.click(spot)
	t.eq(r.glue.sel.mode, UiSelection.Mode.FOREIGN, "visible: inspectable")
	_done(r)


func test_control_group_recall(t: TestCtx) -> void:
	var r: Rig = _rig()
	await _wire(r)
	var trio: Array = r.tanks + [r.rifle]  # the rectangle around the tanks also covers the rifle between them
	var box: Rect2 = r.view.entity_screen_rect(r.tanks[0].id)
	for e: Variant in trio:
		box = box.merge(r.view.entity_screen_rect((e as SimEntity).id))
	r.drag(box.grow(6.0).position, box.grow(6.0).end)
	t.eq(r.glue.sel.sorted_ids(), _ids(trio), "the tanks and the rifle are selected")
	r.key(KEY_1, KEY_MASK_CTRL)
	t.eq(r.glue.groups.members(1), _ids(trio), "Ctrl+1 assigned group 1")
	# deselect, then recall with 1
	r.click(r.screen_of(24 * CELL, 26 * CELL))
	t.check(r.glue.sel.is_empty())
	r.ctl.time_override_ms += 5000
	r.key(KEY_1)
	t.eq(r.glue.sel.sorted_ids(), _ids(trio), "1 recalls the group")
	# a move order from the recalled selection
	r.click(r.screen_of(44 * CELL, 33 * CELL), MOUSE_BUTTON_RIGHT)
	t.eq(r.issued.size(), 1)
	t.check(r.last().begins_with("MOVE ids=[%d,%d,%d,%d]" % [trio[0].id, trio[1].id, trio[2].id, trio[3].id]), "MOVE for the recalled group: %s" % r.last())
	# double tap centres the camera on the centroid
	r.view.focus_on_sim(10 * CELL, 10 * CELL, true)
	r.ctl.time_override_ms += 5000
	r.key(KEY_1)
	r.ctl.time_override_ms += 200
	r.key(KEY_1)
	var c: Vector2i = r.glue.groups.centroid_sim(1, r.port)
	var want: Vector3 = r.view.sim_to_world(c.x, c.y)
	t.check(Vector2(r.view.focus.x, r.view.focus.z).distance_to(Vector2(want.x, want.z)) < 0.01, "the double tap focused the camera on the centroid")
	# Ctrl+Shift+2 adds the current selection; Shift+2 appends the group to another selection
	r.click(r.centre_of(r.rifle))
	r.key(KEY_2, KEY_MASK_CTRL | KEY_MASK_SHIFT)
	t.eq(r.glue.groups.members(2), PackedInt32Array([r.rifle.id]), "Ctrl+Shift+2 added the rifle to group 2")
	r.click(r.centre_of(r.tanks[0]))
	r.key(KEY_2, KEY_MASK_SHIFT)
	t.eq(r.glue.sel.sorted_ids(), _ids([r.tanks[0], r.rifle]), "Shift+2 appended group 2 to the selection")
	# a dead member disappears from the group on recall
	r.w.kill(r.tanks[1], SimWorld.Cause.DAMAGE, 0, 1)
	r.step(1)
	r.click(r.screen_of(24 * CELL, 26 * CELL))
	r.ctl.time_override_ms += 5000
	r.key(KEY_1)
	t.eq(r.glue.sel.sorted_ids(), _ids([r.tanks[0], r.tanks[2], r.rifle]), "the dead tank is not recalled")
	t.eq(r.glue.groups.members(1), _ids([r.tanks[0], r.tanks[2], r.rifle]), "and is dropped from the group for good")
	# an empty group plays the soft tick and selects nothing
	r.click(r.screen_of(24 * CELL, 26 * CELL))
	r.ctl.time_override_ms += 5000
	r.key(KEY_9)
	t.eq(r.glue.empty_ticks, 1)
	t.check(r.glue.sel.is_empty())
	_done(r)


func test_armed_attack_move_stop_and_double_click(t: TestCtx) -> void:
	var r: Rig = _rig()
	await _wire(r)
	r.glue.sel.replace(PackedInt32Array([r.tanks[0].id, r.tanks[1].id]), r.port)
	r.key(KEY_A)
	t.eq(r.glue.modes.armed, UiModes.Armed.ATTACK_MOVE, "A arms attack-move")
	t.eq(r.ctl.armed, UiModes.Armed.ATTACK_MOVE, "the controller follows the mode")
	# LMB on the ground while armed = ATTACK_MOVE (no selection change)
	var goal: Vector2 = r.screen_of(44 * CELL, 33 * CELL)
	r.click(goal)
	t.eq(r.issued.size(), 1)
	t.check(r.last().begins_with("ATTACK_MOVE"), "armed LMB issues attack-move: %s" % r.last())
	t.eq(r.glue.modes.armed, UiModes.Armed.NONE, "the mode is consumed after one order")
	t.eq(r.glue.sel.size(), 2, "the selection did not change")
	r.step(2)
	t.eq(r.tanks[0].orders[0].type, SimOrder.T_ATTACK_MOVE, "the sim executes ATTACK_MOVE")
	# armed, then RMB cancels the mode without an order
	r.key(KEY_A)
	r.click(goal, MOUSE_BUTTON_RIGHT)
	t.eq(r.glue.modes.armed, UiModes.Armed.NONE)
	t.eq(r.issued.size(), 1, "RMB while armed only cancels")
	# S stops
	r.key(KEY_S)
	t.eq(r.issued.size(), 2)
	t.check(r.last().begins_with("STOP ids=[%d,%d]" % [r.tanks[0].id, r.tanks[1].id]), r.last())
	# double click on a tank selects all tanks on screen (the rifle is a different type)
	r.glue.ctl.hit_probe = func(p: Vector2) -> int: return r.view.pick(p, V.PICK_UNITS | V.PICK_OWN)
	r.glue.sel.clear()
	var at: Vector2 = r.centre_of(r.tanks[2])
	r.ctl.time_override_ms += 5000
	for dt: int in [0, 150]:
		r.ctl.time_override_ms += dt
		r.motion(at)
		r.btn(at, MOUSE_BUTTON_LEFT, true)
		r.btn(at, MOUSE_BUTTON_LEFT, false)
	t.eq(r.glue.sel.sorted_ids(), _ids(r.tanks), "double click = every own tank on screen")
	# Ctrl+A: all military
	r.glue.sel.clear()
	r.key(KEY_A, KEY_MASK_CTRL)
	t.eq(r.glue.sel.sorted_ids(), _ids(r.tanks + [r.rifle]), "Ctrl+A selects every combat unit")
	# bookmarks: Ctrl+F9 stores, F9 restores
	r.key(KEY_F9, KEY_MASK_CTRL)
	var stored: Vector3 = r.view.focus
	r.view.pan_screen(Vector2(1.0, 0.0), 1.0)
	t.check(r.view.focus.distance_to(stored) > 1.0, "the camera moved")
	r.key(KEY_F9)
	t.check(r.view.focus.distance_to(stored) < 0.01, "F9 restored the bookmark")
	_done(r)
