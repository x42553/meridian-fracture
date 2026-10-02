extends RefCounted
## HARD1: opening the first-run LAN firewall explainer over the LAN browser crashed the whole process (SIGSEGV, native stack overflow): the screen grabs
## its filter LineEdit right after the dialog was pushed, the dialog stack's focus trap answered with a NESTED grab_focus() inside the
## `gui_focus_changed` emission, and the engine alternated between the two controls forever. The trap now re-grabs deferred (never nested).

const H := preload("res://tests/ui/ui_harness.gd")


func test_a_screen_grabbing_focus_over_an_open_dialog_does_not_ping_pong(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var filter := LineEdit.new()
	filter.clear_button_enabled = true
	rig.root.add_child(filter)
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	await H.frames(1)
	var changes: Array[int] = [0]
	rig.vp.gui_focus_changed.connect(func(_c: Control) -> void: changes[0] += 1)
	var dlg: UiDlgFirewallHelp = UiDlgFirewallHelp.new("macos")
	stack.push(dlg)
	filter.grab_focus()  # what UiScreen.setup_menu_focus() does right after `enter` pushed the dialog
	t.lt(changes[0], 6, "the grab did not start an endless focus fight (changes so far)")
	await H.frames(3)
	t.lt(changes[0], 12, "and the trap settled")
	var owner: Control = rig.vp.gui_get_focus_owner()
	t.check(owner != null and dlg.is_ancestor_of(owner), "focus ends inside the dialog")
	stack.close_top(0)
	await H.frames(2)
	H.done(rig)


func test_focus_inside_the_dialog_is_left_alone(t: TestCtx) -> void:
	var rig: H.Rig = await H.make(Vector2i(1280, 720))
	var stack := UiDialogStack.new()
	rig.vp.add_child(stack)
	stack.attach(rig.root)
	await H.frames(1)
	var dlg: UiDialog = UiDialog.message(&"ui.ok", "hello")
	stack.push(dlg)
	await H.frames(2)
	var before: Control = rig.vp.gui_get_focus_owner()
	t.not_null(before)
	await H.frames(3)
	t.check(rig.vp.gui_get_focus_owner() == before, "no re-grab churn while the focus is already in the dialog")
	stack.close_top(0)
	await H.frames(2)
	H.done(rig)
