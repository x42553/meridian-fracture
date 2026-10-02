extends RefCounted
## Keyboard navigation of the widget core (ui.md 10.3 `lab_menu_nav`, widget part; QA A-04): Tab / Shift+Tab / arrows /
## Enter / Esc through a menu column and through dialogs, the styled focus ring, HUD widgets that never take focus.

const H := preload("res://tests/ui/ui_harness.gd")


func test_focus_ring_styles(t: TestCtx) -> void:
	var th: Theme = UiTheme.build(UiSkin.builtin("han"))
	for tname: String in ["Button", "PrimaryButton", "HeroButton", "LineEdit", "TextEdit", "CheckBox"]:
		var sb: StyleBox = th.get_stylebox("focus", tname)
		t.check(sb is UiStyleBox, "%s has a styled focus ring" % tname)
		if sb is UiStyleBox:
			var ub: UiStyleBox = sb as UiStyleBox
			var accent: Color = UiSkin.builtin("han").accent
			if tname == "LineEdit" or tname == "TextEdit":
				t.check(ub.border_color.is_equal_approx(accent), "%s ring is the accent" % tname)
			else:
				t.check(ub.border_color.is_equal_approx(accent) and ub.border_width == 2.0, "%s ring: 2 px accent" % tname)
				t.eq(ub.fill_top.a, 0.0, "%s ring has no fill (drawn over the control)" % tname)


func test_menu_column_traversal(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var col := VBoxContainer.new()
	rig.root.add_child(col)
	var names: Array[String] = ["Skirmish", "LAN", "Options", "Quit"]
	var btns: Array[Button] = []
	var pressed: Array[String] = []
	for n in names:
		var b := Button.new()
		b.text = n
		b.pressed.connect(func() -> void: pressed.append(n))
		col.add_child(b)
		btns.append(b)
	UiFocusPolicy.apply_menu(col)
	await H.frames(2)
	t.eq(btns[0].focus_mode, Control.FOCUS_ALL)
	btns[0].grab_focus()
	await H.frames(1)
	t.check(rig.vp.gui_get_focus_owner() == btns[0])
	H.key(rig.vp, KEY_TAB)
	t.check(rig.vp.gui_get_focus_owner() == btns[1], "Tab moves to the next control")
	H.key(rig.vp, KEY_DOWN)
	t.check(rig.vp.gui_get_focus_owner() == btns[2], "Down arrow moves to the neighbour below")
	H.key(rig.vp, KEY_TAB, true)
	t.check(rig.vp.gui_get_focus_owner() == btns[1], "Shift+Tab moves back")
	H.key(rig.vp, KEY_UP)
	t.check(rig.vp.gui_get_focus_owner() == btns[0], "Up arrow")
	btns[3].grab_focus()
	H.key(rig.vp, KEY_ENTER)
	await H.frames(1)
	t.eq(pressed, ["Quit"] as Array[String], "Enter presses the focused button")
	H.done(rig)


func test_hud_widgets_do_not_take_focus_or_keys(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var hud := Control.new()
	rig.root.add_child(hud)
	var ib := UiIconButton.new()
	var tb := UiTabBar.new()
	tb.set_tabs([{"id": &"a", "text": "A"}, {"id": &"b", "text": "B"}] as Array[Dictionary])
	hud.add_child(ib)
	hud.add_child(tb)
	UiFocusPolicy.apply_hud(hud)
	await H.frames(1)
	t.eq(ib.focus_mode, Control.FOCUS_NONE, "HUD widgets refuse focus (arrow keys / Space reach the game)")
	t.eq(tb.focus_mode, Control.FOCUS_NONE)
	t.is_null(rig.vp.gui_get_focus_owner())
	H.key(rig.vp, KEY_RIGHT)
	t.eq(tb.selected, 0, "an unfocused tab bar ignores arrows")
	H.done(rig)


func test_dialog_keyboard_flow(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	var d := UiDialog.new("Delete replay?")
	d.add_text("This cannot be undone.")
	d.add_button("Cancel", 0)
	d.add_button("Rename", 2)
	d.add_button("Delete", 1, &"danger")
	var res: Array[int] = [-1]
	d.closed.connect(func(r: int) -> void: res[0] = r)
	stack.push(d)
	await H.frames(3)
	var focus: Control = rig.vp.gui_get_focus_owner()
	t.check(focus != null and d.is_ancestor_of(focus), "a dialog button owns focus on open")
	t.check(focus == d.get_button(0), "no primary button: the first button is the default")
	# a full Tab cycle stays inside the dialog (focus trap, no keyboard trap: Esc still leaves)
	for i in 5:
		H.key(rig.vp, KEY_TAB)
		await H.frames(1)
		var f: Control = rig.vp.gui_get_focus_owner()
		t.check(f != null and d.is_ancestor_of(f), "Tab %d stays in the dialog" % i)
	H.key(rig.vp, KEY_TAB, true)
	await H.frames(1)
	t.check(d.is_ancestor_of(rig.vp.gui_get_focus_owner()), "Shift+Tab stays in the dialog")
	d.get_button(1).grab_focus()
	H.key(rig.vp, KEY_ENTER)
	await H.frames(2)
	t.eq(res[0], 2, "Enter presses the focused button (Rename = 2)")
	# Esc always leaves
	var d2 := UiDialog.new("Escape test")
	d2.add_button("OK", 1, &"primary")
	var r2: Array[int] = [-1]
	d2.closed.connect(func(r: int) -> void: r2[0] = r)
	stack.push(d2)
	await H.frames(3)
	H.key(rig.vp, KEY_ESCAPE)
	await H.frames(2)
	t.eq(r2[0], 0, "Esc closes with 0")
	# a dialog that must be answered ignores Esc (but still swallows it)
	var d3 := UiDialog.new("Must answer")
	d3.dismiss_on_escape = false
	d3.add_button("OK", 1, &"primary")
	var r3: Array[int] = [-1]
	d3.closed.connect(func(r: int) -> void: r3[0] = r)
	stack.push(d3)
	await H.frames(3)
	H.key(rig.vp, KEY_ESCAPE)
	await H.frames(2)
	t.eq(r3[0], -1, "dismiss_on_escape = false keeps the dialog")
	stack.close_top(1)
	await H.frames(2)
	t.eq(r3[0], 1)
	H.done(rig)


func test_screen_esc_reaches_screen_only_without_dialog(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var s := UiScreen.new()
	rig.root.add_child(s)
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	var backs: Array[int] = [0]
	s.back_requested.connect(func() -> void: backs[0] += 1)
	await H.frames(2)
	H.key(rig.vp, KEY_ESCAPE)
	await H.frames(1)
	t.eq(backs[0], 1, "Esc on a screen without dialogs goes back")
	stack.push(UiDialog.message(&"ui.ok", "modal"))
	await H.frames(3)
	H.key(rig.vp, KEY_ESCAPE)
	await H.frames(2)
	t.eq(backs[0], 1, "an open dialog consumes Esc before the screen")
	H.done(rig)
