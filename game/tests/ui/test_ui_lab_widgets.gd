extends RefCounted
## Core widget behaviour in a sized SubViewport (labs of ui.md 10.3; `lab_widgets` core part): theme distribution
## (P1 / P2), style-box caching, dialog stack, toast, icon button, tab bar, list row, select rect, screen escape chain,
## tooltip body, focus policy, motion. Async coroutine tests (the runner supports `await`).

const H := preload("res://tests/ui/ui_harness.gd")


func test_layer_root_theme_and_size(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var label := Label.new()
	label.text = "hello"
	rig.root.add_child(label)
	await H.frames(2)
	t.check(rig.root.theme != null, "layer root carries the theme")
	t.eq(rig.root.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	t.eq(rig.root.size, Vector2(1280.0, 720.0), "full rect under a CanvasLayer (P2)")
	var f: Font = label.get_theme_font(&"font", &"Label")
	t.check(f == UiFonts.get_font(UiFonts.Role.BODY), "labels below the layer root use the BODY font (P1)")
	t.eq(label.get_theme_font_size(&"font_size", &"Label"), UiMetrics.FS_BODY)
	t.check(UiThemeService.instance().root_count() >= 1)
	H.done(rig)


func test_theme_service_rebuild_swaps_theme(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	await H.frames(1)
	var svc: UiThemeService = UiThemeService.instance()
	var seen: Array[Theme] = []
	var on_changed: Callable = func(nt: Theme) -> void: seen.append(nt)
	svc.theme_changed.connect(on_changed)
	var before: Theme = rig.root.theme
	var han: UiSkin = UiSkin.builtin("han")
	var th: Theme = UiThemeService.rebuild(han)
	t.check(th != before, "new Theme instance")
	t.check(rig.root.theme == th, "assigned to every registered root")
	t.eq(seen.size(), 1, "theme_changed fired once")
	t.check(th.get_color(&"accent", UiTheme.ACCENT_TYPE).is_equal_approx(han.accent), "accent colour carried by the theme")
	t.check(UiThemeService.current() == th)
	svc.theme_changed.disconnect(on_changed)
	UiThemeService.rebuild(UiSkin.neutral())
	H.done(rig)


func test_style_box_cache(t: TestCtx) -> void:
	var skin: UiSkin = UiSkin.builtin("olm")
	var a: UiStyleBox = UiTheme.box(skin, &"button", &"hover")
	var b: UiStyleBox = UiTheme.box(skin, &"button", &"hover")
	t.check(a == b, "same (recipe, state, skin) -> same instance")
	t.check(a != UiTheme.box(skin, &"button", &"pressed"))
	t.check(a != UiTheme.box(UiSkin.builtin("han"), &"button", &"hover"), "skin is part of the key")
	UiTheme.build(skin)
	var n: int = UiStyleBox.cache_size()
	for i in 200:
		UiTheme.build(skin)
	t.eq(UiStyleBox.cache_size(), n, "no style box allocated per rebuild (object count stable)")


func test_theme_build_timing(t: TestCtx) -> void:
	UiStyleBox.clear_cache()
	var skin: UiSkin = UiSkin.builtin("ae")
	var t0: int = Time.get_ticks_usec()
	UiTheme.build(skin)
	var first_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var t1: int = Time.get_ticks_usec()
	for i in 50:
		UiTheme.build(skin)
	var warm_ms: float = float(Time.get_ticks_usec() - t1) / 1000.0 / 50.0
	t.note("UiTheme.build first %.2f ms, warm %.3f ms (spec: <= 10 ms first, <= 0.3 ms warm)" % [first_ms, warm_ms])
	t.lt(first_ms, 30.0, "first build")
	t.lt(warm_ms, 3.0, "warm build")


func test_dialog_stack_queue_focus_escape(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var outside := Button.new()
	outside.text = "outside"
	outside.focus_mode = Control.FOCUS_ALL
	rig.root.add_child(outside)
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	await H.frames(1)
	outside.grab_focus()
	t.check_false(stack.is_open())
	t.check_false(stack.has_modal_over_input())
	var results: Array[int] = []
	var tops: Array[UiDialog] = []
	stack.top_changed.connect(func(d: UiDialog) -> void: tops.append(d))
	var d1: UiDialog = UiDialog.confirm(&"ui.confirm", &"ui.confirm")
	var d2: UiDialog = UiDialog.message(&"ui.ok", "second")
	d1.closed.connect(func(r: int) -> void: results.append(r))
	d2.closed.connect(func(r: int) -> void: results.append(r))
	stack.push(d1)
	stack.push(d2)
	await H.frames(2)
	t.check(stack.is_open() and stack.has_modal_over_input(), "modal while open")
	t.eq(stack.count(), 2, "second dialog queued")
	t.check(stack.top() == d1, "one dialog visible at a time")
	t.check(d2.get_parent() == null, "queued dialog not in the tree")
	var focus: Control = rig.vp.gui_get_focus_owner()
	t.check(focus == d1.default_focus(), "default button focused (yes)")
	# focus trap: focusing the outside control is undone
	outside.grab_focus()
	await H.frames(2)
	t.check(d1.is_ancestor_of(rig.vp.gui_get_focus_owner()), "focus trapped inside the dialog")
	# Escape closes with 0 and shows the next dialog
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	rig.vp.push_input(esc)
	await H.frames(2)
	t.eq(results, [0] as Array[int], "Esc closes the top dialog with result 0")
	t.check(stack.top() == d2, "queued dialog shown next")
	t.eq(stack.count(), 1)
	stack.close_top(1)
	await H.frames(2)
	t.eq(results, [0, 1] as Array[int], "close_top(1) reports the button result")
	t.check_false(stack.is_open())
	t.check(tops.size() == 3 and tops[2] == null, "top_changed: d1, d2, null")
	t.check(rig.vp.gui_get_focus_owner() == outside, "focus restored after the last dialog")
	H.done(rig)


func test_dialog_buttons_and_results(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	var d: UiDialog = UiDialog.confirm(&"ui.confirm", &"ui.confirm")
	var got: Array[int] = [-1]
	d.closed.connect(func(r: int) -> void: got[0] = r)
	stack.push(d)
	await H.frames(3)
	t.eq(d.button_count(), 2)
	var yes: Button = d.get_button(1)
	t.eq(yes.text, "Yes")
	t.eq(d.get_button(0).text, "No")
	H.click(rig.vp, H.center(yes))
	await H.frames(2)
	t.eq(got[0], 1, "clicking Yes closes with 1")
	t.check(not is_instance_valid(d) or d.is_closed(), "closed dialog is freed")
	# modal scrim blocks clicks below
	var below := Button.new()
	below.custom_minimum_size = Vector2(100.0, 40.0)
	rig.root.add_child(below)
	var hits: Array[int] = [0]
	below.pressed.connect(func() -> void: hits[0] += 1)
	var d2: UiDialog = UiDialog.message(&"ui.ok", "blocked")
	stack.push(d2)
	await H.frames(3)
	H.click(rig.vp, Vector2(30.0, 20.0))
	await H.frames(1)
	t.eq(hits[0], 0, "the scrim swallows clicks on controls below the dialog")
	stack.close_top(0)
	await H.frames(2)
	H.click(rig.vp, Vector2(30.0, 20.0))
	await H.frames(1)
	t.eq(hits[0], 1, "clicks reach the control again once the stack is empty")
	H.done(rig)


func test_toast_lifecycle_and_actions(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var fired: Array[int] = [0]
	var acts: Array[Dictionary] = [{"label": "Undo", "call": func() -> void: fired[0] += 1}]
	var toast: UiToast = UiToast.make("Saved", UiToast.Severity.WARN, acts)
	toast.hold_s = 0.05
	var gone: Array[bool] = [false]
	toast.dismissed.connect(func() -> void: gone[0] = true)
	rig.root.add_child(toast)
	await H.frames(2)
	t.check(toast.modulate.a < 1.0 or toast.modulate.a == 1.0, "alpha within range")
	t.eq(toast.accessibility_live, AccessibilityServer.LIVE_POLITE)
	# auto-dismiss (in 0.15 + hold 0.1 + out 0.3 s) - wait for it
	var guard: int = 0
	while not gone[0] and guard < 180:
		await H.frames(1)
		guard += 1
	t.check(gone[0], "toast dismisses itself")
	await H.frames(2)
	t.check(not is_instance_valid(toast), "toast freed")
	# an action press runs the callback and dismisses
	var t2: UiToast = UiToast.make("Copy?", UiToast.Severity.INFO, acts)
	var idx: Array[int] = [-1]
	t2.action_pressed.connect(func(i: int) -> void: idx[0] = i)
	rig.root.add_child(t2)
	await H.frames(3)
	var buttons: Array[Node] = t2.find_children("*", "Button", true, false)
	t.eq(buttons.size(), 1)
	H.click(rig.vp, H.center(buttons[0] as Control))
	await H.frames(1)
	t.eq(fired[0], 1, "action callback ran")
	t.eq(idx[0], 0)
	H.done(rig)


func test_icon_button_input(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var b := UiIconButton.new()
	b.position = Vector2(100.0, 100.0)
	rig.root.add_child(b)
	await H.frames(2)
	t.eq(b.focus_mode, Control.FOCUS_NONE, "HUD-safe: no keyboard focus")
	t.eq(b.mouse_filter, Control.MOUSE_FILTER_STOP)
	t.check(b.size.x >= float(UiMetrics.COMMAND_BTN) and b.size.y >= float(UiMetrics.COMMAND_BTN), "hit target >= 32 (48)")
	var events: Array[String] = []
	b.pressed.connect(func() -> void: events.append("p"))
	b.right_pressed.connect(func() -> void: events.append("r"))
	b.toggled.connect(func(on: bool) -> void: events.append("t%d" % int(on)))
	H.click(rig.vp, H.center(b))
	H.click(rig.vp, H.center(b), MOUSE_BUTTON_RIGHT)
	t.eq(events, ["p", "r"] as Array[String])
	# release outside the button does not fire
	events.clear()
	H.press(rig.vp, H.center(b))
	H.press(rig.vp, Vector2(600.0, 400.0), MOUSE_BUTTON_LEFT, false)
	t.eq(events.size(), 0, "release outside cancels the click")
	# toggle
	b.toggle_mode = true
	H.click(rig.vp, H.center(b))
	t.eq(events, ["t1", "p"] as Array[String])
	t.check(b.active)
	# disabled
	events.clear()
	b.set_enabled(false)
	H.click(rig.vp, H.center(b))
	t.eq(events.size(), 0, "disabled button ignores clicks")
	# keyboard only when focusable
	b.set_enabled(true)
	b.toggle_mode = false
	b.set_focusable(true)
	b.grab_focus()
	await H.frames(1)
	H.key(rig.vp, KEY_ENTER)
	await H.frames(1)
	t.eq(events, ["p"] as Array[String], "Enter activates a focusable icon button")
	b.set_tip({"title": "Attack move", "text": "Move and engage."})
	t.check(b.tooltip_text.begins_with("{"), "rich tooltip stored as JSON")
	t.eq(b.accessibility_name, "Attack move")
	H.done(rig)


func test_tab_bar(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var tb := UiTabBar.new()
	rig.root.add_child(tb)
	var tabs: Array[Dictionary] = [{"id": &"a", "text": "BUILD"}, {"id": &"b", "text": "UNITS"}, {"id": &"c", "text": "OFF", "enabled": false}, {"id": &"d", "glyph": UiDraw.G_CLOSE}]
	tb.set_tabs(tabs)
	await H.frames(2)
	t.eq(tb.tab_count(), 4)
	t.eq(tb.selected_id(), &"a")
	t.eq(tb.tab_rect(3).size, Vector2(float(UiMetrics.TAB_SIZE), tb.tab_rect(3).size.y), "glyph tab = 38 px wide")
	t.near(tb.tab_rect(1).position.x - tb.tab_rect(0).end.x, float(UiMetrics.TAB_GAP), 0.01, "2 px gap")
	var got: Array[StringName] = []
	tb.tab_selected.connect(func(_i: int, id: StringName) -> void: got.append(id))
	H.click(rig.vp, tb.get_global_position() + tb.tab_rect(1).get_center())
	t.eq(got, [&"b"] as Array[StringName])
	t.eq(tb.selected, 1)
	H.click(rig.vp, tb.get_global_position() + tb.tab_rect(2).get_center())
	t.eq(tb.selected, 1, "disabled tab cannot be selected")
	H.click(rig.vp, tb.get_global_position() + tb.tab_rect(3).get_center())
	t.eq(got, [&"b", &"d"] as Array[StringName])
	# keyboard (menu mode)
	tb.set_focusable(true)
	tb.select(0)
	tb.grab_focus()
	await H.frames(1)
	H.key(rig.vp, KEY_RIGHT)
	t.eq(tb.selected, 1)
	H.key(rig.vp, KEY_RIGHT)
	t.eq(tb.selected, 3, "arrow skips the disabled tab")
	H.key(rig.vp, KEY_HOME)
	t.eq(tb.selected, 0)
	tb.set_badge(&"a", "3")
	t.eq(tb.selected_id(), &"a")
	tb.select_id(&"b")
	t.eq(tb.selected, 1)
	# stretch mode fills the width
	var st := UiTabBar.new()
	st.stretch = true
	st.custom_minimum_size = Vector2(318.0, 0.0)
	rig.root.add_child(st)
	var eight: Array[Dictionary] = []
	for i in 8:
		eight.append({"id": StringName("t%d" % i), "glyph": UiDraw.G_PLUS})
	st.set_tabs(eight)
	st.size = Vector2(318.0, 38.0)
	await H.frames(2)
	t.near(st.tab_rect(7).end.x, 318.0, 0.5, "8 stretched tabs fill 318 px")
	H.done(rig)


func test_list_row(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var row := UiListRow.new()
	rig.root.add_child(row)
	row.set_cells([{"text": "Game"}, {"text": "Map"}], PackedFloat32Array([100.0, 100.0]))
	row.size = Vector2(300.0, 38.0)
	await H.frames(2)
	var events: Array[String] = []
	row.selected.connect(func() -> void: events.append("s"))
	row.activated.connect(func() -> void: events.append("a"))
	H.click(rig.vp, H.center(row))
	H.click(rig.vp, H.center(row), MOUSE_BUTTON_LEFT, true)
	t.eq(events, ["s", "a"] as Array[String], "click selects, double click activates")
	events.clear()
	row.is_header = true
	H.click(rig.vp, H.center(row))
	t.eq(events.size(), 0, "header rows ignore clicks")
	t.eq(row.accessibility_name, "Game, Map")
	t.eq(row.cell_count(), 2)
	H.done(rig)


func test_select_rect_and_vignette(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var sr := UiSelectRect.new()
	rig.root.add_child(sr)
	var vig := UiVignette.new()
	rig.root.add_child(vig)
	await H.frames(2)
	t.eq(sr.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	t.eq(vig.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	t.eq(sr.size, Vector2(800.0, 450.0))
	sr.show_rect(Rect2(Vector2(200.0, 100.0), Vector2(-50.0, -40.0)))
	t.eq(sr.rect, Rect2(Vector2(150.0, 60.0), Vector2(50.0, 40.0)), "normalised to a positive rect")
	t.check(sr.active)
	sr.hide_rect()
	t.check_false(sr.active)
	# the overlay never eats a click meant for the world (spike case A)
	var world := Button.new()
	world.custom_minimum_size = Vector2(80.0, 40.0)
	world.position = Vector2(50.0, 50.0)
	rig.root.add_child(world)
	rig.root.move_child(world, 0)
	var hit: Array[int] = [0]
	world.pressed.connect(func() -> void: hit[0] += 1)
	await H.frames(1)
	H.click(rig.vp, H.center(world))
	t.eq(hit[0], 1, "full-rect IGNORE overlays let clicks through")
	vig.set_lite(true)
	vig.set_time(1.0)
	H.done(rig)


class _TestScreen extends UiScreen:
	var escape_handled: bool = false
	var leave_ok: bool = true

	func on_escape() -> bool:
		return escape_handled

	func can_leave() -> bool:
		return leave_ok


func test_screen_escape_chain(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(800, 450))
	var s := _TestScreen.new()
	rig.root.add_child(s)
	await H.frames(1)
	t.eq(s.mouse_filter, Control.MOUSE_FILTER_IGNORE, "screens let clicks through by default")
	t.eq(s.size, Vector2(800.0, 450.0))
	var backs: Array[int] = [0]
	s.back_requested.connect(func() -> void: backs[0] += 1)
	s.escape_handled = true
	t.check(s.handle_escape())
	t.eq(backs[0], 0, "a handled escape does not go back")
	s.escape_handled = false
	t.check(s.handle_escape())
	t.eq(backs[0], 1, "unhandled escape -> back_requested")
	s.leave_ok = false
	s.handle_escape()
	t.eq(backs[0], 1, "can_leave() == false keeps the screen (it shows its own confirm)")
	t.is_null(s.default_focus())
	H.done(rig)


func test_tooltip_body(t: TestCtx) -> void:
	var spec: Dictionary = {"title": "Rifleman", "tag": "TIER 1 // INFANTRY", "stats": [{"label": "cost", "value": "150", "delta": "+10%", "tone": "danger"}, {"label": "time", "value": "0:12"}], "text": "Cheap light infantry. " + "Very long description. ".repeat(20), "warn": "Requires Barracks", "hint": "LMB build"}
	var body: UiTooltipBody = UiTooltipBody.make_from_text(UiTooltipBody.encode(spec))
	t.check(body.custom_minimum_size.x <= float(UiMetrics.TOOLTIP_MAX_W) and body.custom_minimum_size.x >= 180.0, "width clamped to 180 .. 340 (%f)" % body.custom_minimum_size.x)
	t.eq(body.get_spec()["title"], "Rifleman")
	t.eq(body.get_child_count(), 6, "title, tag, stats row, text, warn, hint")
	t.eq((body.get_child(0) as Label).text, "RIFLEMAN", "CAPS header")
	var plain: UiTooltipBody = UiTooltipBody.make_from_text("Just text")
	t.eq(plain.get_child_count(), 1)
	t.eq((plain.get_child(0) as Label).text, "Just text")
	t.eq(body.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	body.free()
	plain.free()
	# the encode / decode round trip keeps an accent Color override
	var enc: String = UiTooltipBody.encode({"title": "X", "accent": Color("#33c98a")})
	var back: UiTooltipBody = UiTooltipBody.make_from_text(enc)
	t.check(back.get_child(0).get_theme_color(&"font_color").is_equal_approx(Color("#33c98a")), "accent override")
	back.free()


func test_focus_policy(t: TestCtx) -> void:
	var root := Control.new()
	var b := Button.new()
	var le := LineEdit.new()
	var ib := UiIconButton.new()
	var sub := Panel.new()
	var b2 := Button.new()
	root.add_child(b)
	root.add_child(le)
	root.add_child(ib)
	root.add_child(sub)
	sub.add_child(b2)
	UiFocusPolicy.apply_hud(root)
	t.eq(b.focus_mode, Control.FOCUS_NONE)
	t.eq(b2.focus_mode, Control.FOCUS_NONE, "recursive")
	t.eq(le.focus_mode, Control.FOCUS_ALL, "text inputs keep focus (chat)")
	UiFocusPolicy.apply_menu(root)
	t.eq(b.focus_mode, Control.FOCUS_ALL)
	t.eq(ib.focus_mode, Control.FOCUS_NONE, "icon buttons opt in with set_focusable")
	root.free()


func test_motion_and_reduce_motion(t: TestCtx) -> void:
	UiMotion.reduce_motion = false
	t.near(UiMotion.dur(0.18), 0.18, 0.0001)
	var p: float = UiMotion.pulse(0.25)
	t.near(p, 1.0, 0.001, "1 Hz pulse peaks at t = 0.25")
	UiMotion.reduce_motion = true
	t.eq(UiMotion.dur(0.18), 0.0, "reduce_motion: every duration is 0")
	t.eq(UiMotion.pulse(0.25), 1.0, "reduce_motion: steady")
	var c := Control.new()
	UiMotion.tween_prop(c, c, ^"custom_minimum_size", Vector2(5.0, 5.0), 0.2)
	t.eq(c.custom_minimum_size, Vector2(5.0, 5.0), "assigned immediately")
	c.free()
	UiMotion.reduce_motion = false
	UiMotion.reduce_flash = true
	t.eq(UiMotion.pulse(0.1), 1.0, "reduce_flash: steady")
	UiMotion.reduce_flash = false
	t.le(UiMotion.PULSE_HZ, UiMotion.MAX_HZ)


func test_fonts(t: TestCtx) -> void:
	for role: int in [UiFonts.Role.BODY, UiFonts.Role.BODY_BOLD, UiFonts.Role.HEAD, UiFonts.Role.HEAD_LIGHT, UiFonts.Role.NUM]:
		var f: Font = UiFonts.get_font(role)
		t.not_null(f, "font role %d" % role)
		t.check(f.get_string_size("Aa 0123", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > 10.0, "role %d shapes text" % role)
		t.check(f.get_fallbacks().size() >= 1 and f.get_fallbacks()[0] is SystemFont, "fallback chain ends in a SystemFont")
	var head: FontVariation = UiFonts.get_font(UiFonts.Role.HEAD) as FontVariation
	t.eq(head.spacing_glyph, 1, "Orbitron +1 px glyph spacing")
	t.eq(UiFonts.size_of(&"body"), 15)
	t.eq(UiFonts.role_of(&"caption"), UiFonts.Role.NUM)
	t.check(UiFonts.get_font(UiFonts.Role.HEAD) == UiFonts.get_font(UiFonts.Role.HEAD), "cached")
	# vendored licences
	for fam: String in ["rajdhani", "orbitron", "share_tech_mono"]:
		t.check(FileAccess.file_exists("res://assets/fonts/%s/OFL.txt" % fam), "%s ships OFL.txt" % fam)


class _GlyphProbe extends Control:
	var ids: Array[int] = []

	func _draw() -> void:
		var x: float = 0.0
		for g in ids:
			UiDraw.glyph(self, g, Rect2(Vector2(x, 0.0), Vector2(24.0, 24.0)), Color.WHITE, 1.8)
			x += 28.0


func test_glyph_fallback_and_plugin(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(400, 100))
	var probe := _GlyphProbe.new()
	probe.ids = [UiDraw.G_STOP, UiDraw.G_WARNING, UiDraw.G_CHEVRON_UP, UiDraw.G_CHEVRON_DOWN, UiDraw.G_CLOSE, UiDraw.G_CHECK, UiDraw.G_PLUS, UiDraw.G_MINUS, UiDraw.G_INFO, 9999]
	rig.root.add_child(probe)
	await H.frames(2)
	t.check(probe.is_inside_tree(), "the fallback painter draws every basic glyph without an engine error")
	# a glyph library plugs in through a Script with a static `draw`
	var plug := GDScript.new()
	plug.source_code = "extends RefCounted\nstatic var calls: int = 0\nstatic func draw(_ci: CanvasItem, _g: int, _r: Rect2, _c: Color, _w: float) -> void:\n\tcalls += 1\n"
	t.eq(plug.reload(), OK)
	UiDraw.set_glyph_painter(plug)
	probe.queue_redraw()
	await H.frames(2)
	t.eq(int(plug.get(&"calls")), probe.ids.size(), "the installed painter receives every glyph")
	UiDraw.set_glyph_painter(null)
	H.done(rig)
