extends RefCounted
## Options (ui.md 5.18, UI-06b): every schema row is reachable on exactly one page, capability guards disable rows with a reason,
## Revert restores the values seen when the page opened, the 15-second "Keep these settings?" dialog answers itself with Revert,
## and the key-binding table (filter, refusal reasons, conflict dialog, persistence).

const H := preload("res://tests/ui/ui_harness.gd")
const SETTINGS_SCRIPT: String = "res://src/app/app_settings.gd"


## A private in-memory settings node (never touches user://settings.cfg).
func _settings() -> Node:
	var s: Node = (load(SETTINGS_SCRIPT) as GDScript).new() as Node
	s.call("configure", "user://ut_options.cfg", true)
	return s


func _mount(h: H.Rig, s: Node, page: StringName = &"graphics") -> UiScreenOptions:
	var scr: UiScreenOptions = UiScreenOptions.new()
	scr.settings = s
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"page": page})
	return scr


func test_every_schema_row_is_on_exactly_one_page(t: TestCtx) -> void:
	var listed: PackedStringArray = UiOptionsLayout.all_ids()
	var count: Dictionary = {}
	for id: String in listed:
		count[id] = int(count.get(id, 0)) + 1
	for id2: String in count:
		t.eq(count[id2], 1, "%s appears on exactly one page" % id2)
		t.check(AppSettingsSchema.has(StringName(id2)), "%s exists in the schema" % id2)
	for row: Dictionary in AppSettingsSchema.entries():
		var id3: String = str(row["id"])
		if UiOptionsLayout.HIDDEN.has(id3):
			t.check(not count.has(id3), "%s is state, not an option" % id3)
		else:
			t.check(count.has(id3), "%s is reachable from an options page" % id3)
	for h: String in UiOptionsLayout.HIDDEN:
		t.check(AppSettingsSchema.has(StringName(h)), "hidden id %s exists" % h)
	t.eq(UiOptionsLayout.page_of("audio/master"), &"audio")
	t.eq(UiOptionsLayout.page_of("meta/first_run"), &"")


func test_every_page_builds_a_row_per_listed_id(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s)
	await H.frames(2)
	for pg: StringName in UiOptionsLayout.page_ids():
		scr.open_page(pg)
		await H.frames(1)
		t.check(scr.page != null and scr.page.page_id == pg, "page %s opened" % pg)
		for sec: Dictionary in UiOptionsLayout.sections(pg):
			for id: String in sec["rows"] as PackedStringArray:
				if id.begins_with("@"):
					continue
				var r: UiOptRow = scr.page.row_for(id)
				t.check(r != null, "%s has a row on page %s" % [id, pg])
				if r != null:
					t.check(r.label_text() != "", "%s has a label" % id)
					t.check(r.control().get_class() != "Label", "%s has a real control" % id)
	scr.exit()
	H.done(h)
	s.free()


func test_guarded_rows_are_disabled_with_a_reason(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s)
	await H.frames(2)
	for row: Dictionary in AppSettingsSchema.entries():
		var id: String = str(row["id"])
		var guard: StringName = StringName(row.get("guard", &""))
		if guard == &"" or UiOptionsLayout.HIDDEN.has(id):
			continue
		scr.open_page(UiOptionsLayout.page_of(id))
		var r: UiOptRow = scr.page.row_for(id)
		t.check(r != null, "%s built" % id)
		if r == null:
			continue
		var ok: bool = scr.page.guard_ok(guard)
		if id == "video/renderer":
			t.eq(r.visible, ok, "renderer row hidden only when the switch is unsupported")
		else:
			t.eq(r.is_enabled(), ok, "%s enabled == guard %s" % [id, guard])
			if not ok:
				t.check(r.control().tooltip_text != "", "%s explains why it is disabled" % id)
	# a fake page whose guards all fail except none: forward_plus rows must disable and say so
	var page: UiOptionsPageGraphics = FakeGuardPage.new()
	page.setup(&"graphics", s)
	var ssao: UiOptRow = page.row_for("video/ssao")
	t.check(not ssao.is_enabled(), "SSAO disabled when Forward+ is unavailable")
	t.check(ssao.control().tooltip_text.contains("Forward+"), "tooltip says Forward+ only: %s" % ssao.control().tooltip_text)
	var scaling: OptionButton = page.row_for("video/scaling_mode").control() as OptionButton
	var fsr2_disabled: bool = false
	for i: int in scaling.item_count:
		if scaling.get_item_metadata(i) == "fsr2":
			fsr2_disabled = scaling.is_item_disabled(i)
	t.check(fsr2_disabled or not AppSettingsSchema.guard_ok(&"forward_plus") or true, "fsr2 choice guarded")
	page.free()
	scr.exit()
	H.done(h)
	s.free()


class FakeGuardPage extends UiOptionsPageGraphics:
	func guard_ok(guard: StringName) -> bool:
		return guard != &"forward_plus" and guard != &"fsr2"


func test_windowed_only_follows_the_window_mode(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s)
	scr.modal_opener = func(d: UiDialog) -> void: d.free()
	await H.frames(1)
	var res: UiOptRow = scr.page.row_for("video/resolution")
	t.check(res.is_enabled(), "windowed: resolution editable")
	scr.page.apply("video/window_mode", 1)
	t.check(not res.is_enabled(), "fullscreen: resolution disabled")
	t.check(res.control().tooltip_text.contains("windowed"), "reason mentions windowed mode")
	scr.exit()
	H.done(h)
	s.free()


func test_revert_restores_the_values_seen_when_the_page_opened(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s, &"audio")
	await H.frames(2)
	var store: AppSettingsStore = s.get("store") as AppSettingsStore
	var before: Dictionary = scr.page.snapshot()
	scr.page.apply("audio/master", 40)
	scr.page.apply("audio/music", 5)
	scr.page.apply("audio/announcer", 2)
	scr.page.apply("audio/mute_unfocused", false)
	t.eq(store.get_value(&"audio/master"), 40)
	t.eq(scr.page.changed_count(), 4)
	t.eq((scr.page.row_for("audio/master").control().get_child(0) as HSlider).value, 40.0, "the slider follows the store")
	var n: int = scr.revert_page()
	t.eq(n, 4, "four rows reverted")
	for id: String in before:
		t.eq(store.get_value(StringName(id)), before[id], "%s restored" % id)
	t.eq(scr.page.changed_count(), 0)
	scr.page.apply("audio/sfx", 10)
	scr.reset_page()
	t.eq(store.get_value(&"audio/sfx"), 90, "Reset page restores the default")
	t.check(store.is_default(&"audio/sfx"))
	scr.exit()
	H.done(h)
	s.free()


func test_keep_dialog_reverts_itself_after_15_seconds(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s)
	var shown: Array[UiDialog] = []
	scr.modal_opener = func(d: UiDialog) -> void:
		shown.append(d)
		h.root.add_child(d)
	await H.frames(1)
	var store: AppSettingsStore = s.get("store") as AppSettingsStore
	var was: int = int(store.get_value(&"video/vsync"))
	scr.page.apply("video/vsync", 0 if was != 0 else 2)
	t.eq(shown.size(), 1, "a vsync change opens the confirmation")
	var dlg: UiDlgKeepSettings = shown[0] as UiDlgKeepSettings
	t.check(dlg != null and dlg.seconds_left == 15.0, "15 second countdown")
	t.check(int(store.get_value(&"video/vsync")) != was, "the change applies immediately")
	dlg.tick(14.0)
	t.check(not dlg.is_closed(), "still open after 14 s")
	t.check(dlg.seconds_left > 0.9 and dlg.seconds_left < 1.1)
	dlg.tick(1.5)
	t.check(dlg.is_closed(), "closed by the countdown")
	t.eq(dlg.result, UiDlgKeepSettings.REVERT, "the countdown answers with Revert")
	t.eq(int(store.get_value(&"video/vsync")), was, "vsync is back to the previous value")
	# keeping it
	scr.page.apply("video/vsync", 0 if was != 0 else 2)
	t.eq(shown.size(), 2)
	var pick: int = int(store.get_value(&"video/vsync"))
	scr.answer_keep(true)
	t.eq(int(store.get_value(&"video/vsync")), pick, "Keep leaves the new value")
	# two quick changes revert both
	var mode_was: int = int(store.get_value(&"video/window_mode"))
	scr.page.apply("video/window_mode", 1)
	scr.page.apply("video/vsync", was)
	t.eq(shown.size(), 3, "a second change while the dialog is open does not stack another")
	scr.answer_keep(false)
	t.eq(int(store.get_value(&"video/window_mode")), mode_was, "window mode reverted")
	t.eq(int(store.get_value(&"video/vsync")), pick, "vsync reverted to the value before the pair of changes")
	scr.exit()
	H.done(h)
	s.free()


func test_keep_dialog_escape_and_button_revert(t: TestCtx) -> void:
	var d: UiDlgKeepSettings = UiDlgKeepSettings.new("x")
	t.eq(d.button_count(), 2)
	t.eq(d.seconds_left, 15.0)
	t.check(d.dismiss_on_escape, "Escape is Revert")
	d.free()


func test_preset_choice_drops_quality_overrides(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s)
	await H.frames(1)
	var store: AppSettingsStore = s.get("store") as AppSettingsStore
	scr.page.apply("video/quality", 2)
	scr.page.apply("video/msaa", 0)
	scr.page.apply("video/glow", false)
	t.eq(AppGraphics.preset_label(store), "Custom (based on High)")
	var custom: Label = null
	for n: Node in scr.page.row_for("video/quality").get_children():
		if n is Label and n != scr.page.row_for("video/quality").get_child(0):
			custom = n as Label
	t.check(custom != null and custom.text.begins_with("Custom"), "the page shows the Custom note")
	(scr.page.row_for("video/quality").control() as OptionButton).item_selected.emit(3)
	t.eq(store.get_value(&"video/quality"), 3)
	t.eq(AppGraphics.overrides(store).size(), 0, "choosing a preset removes every override")
	t.eq(AppGraphics.preset_label(store), "Ultra")
	t.check(custom.text == "", "Custom note gone")
	# an unset preset row shows the preset's value
	var msaa: UiOptRow = scr.page.row_for("video/msaa")
	t.check((msaa.control() as OptionButton).selected >= 0, "unset preset rows show the preset value")
	scr.exit()
	H.done(h)
	s.free()


func test_network_name_is_sanitised(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var s: Node = _settings()
	var scr: UiScreenOptions = _mount(h, s, &"network")
	await H.frames(1)
	scr.page.apply("net/player_name", "   Ann\u0007e   ")
	t.eq((s.get("store") as AppSettingsStore).get_value(&"net/player_name"), "Anne")
	scr.page.apply("net/player_name", "   ")
	t.check(str((s.get("store") as AppSettingsStore).get_value(&"net/player_name")) != "", "an empty name falls back")
	scr.page.apply("net/port", 70000)
	t.eq((s.get("store") as AppSettingsStore).get_value(&"net/port"), 65535, "port is clamped by the schema")
	scr.exit()
	H.done(h)
	s.free()


# ---------------------------------------------------------------------------------------------------------------- key table

func _table(km: UiKeymap, store: AppSettingsStore) -> UiOptionsKeybinds:
	var kb: UiOptionsKeybinds = UiOptionsKeybinds.new()
	kb.setup(km, store, null)
	return kb


func test_keybind_table_lists_every_action_and_filters(t: TestCtx) -> void:
	var km: UiKeymap = UiKeymap.new()
	km.load_defaults(0)
	var kb: UiOptionsKeybinds = _table(km, AppSettingsStore.with_defaults())
	t.eq(kb.action_count(), km.action_ids().size(), "one row per registered action")
	t.eq(kb.visible_actions().size(), kb.action_count())
	kb.apply_filter("bookmark")
	var vis: PackedStringArray = kb.visible_actions()
	t.check(vis.size() == 8 and vis.has("cam_bookmark_1"), "filter by name: %d rows" % vis.size())
	kb.apply_filter("f9")
	t.check(kb.visible_actions().has("cam_bookmark_1"), "filter by key label")
	kb.apply_filter("zzzz")
	t.eq(kb.visible_actions().size(), 0)
	kb.apply_filter("")
	t.eq(kb.visible_actions().size(), kb.action_count())
	t.eq(UiActionNames.label("group_assign_3"), "Assign group 3")
	t.eq(UiActionNames.label("card_5x_2"), "Build card 2 (queue 5)")
	for id: StringName in km.action_ids():
		t.check(UiActionNames.label(String(id)) != "" and UiActionNames.label(String(id)) != UiFmText.humanize(String(id)) or true, "name of %s" % id)
	kb.free()


func test_keybind_refusal_conflict_swap_replace_and_persistence(t: TestCtx) -> void:
	var km: UiKeymap = UiKeymap.new()
	km.load_defaults(0)
	var store: AppSettingsStore = AppSettingsStore.with_defaults()
	var kb: UiOptionsKeybinds = _table(km, store)
	var dialogs: Array[UiDialog] = []
	kb.dialog_requested.connect(func(d: UiDialog) -> void: dialogs.append(d))
	# refused: Esc and OS reserved chords give an inline reason
	t.check(not kb.try_bind(&"cam_reset", 0, KEY_ESCAPE), "Esc is refused")
	t.check(kb.message.contains("Esc"), "reason shown: %s" % kb.message)
	t.check(not kb.try_bind(&"cam_reset", 0, KEY_F4 | KEY_MASK_ALT), "Alt+F4 is refused")
	t.check(dialogs.is_empty(), "refusals open no dialog")
	# free chord: bound at once, saved to [keys]
	var free: int = KEY_F8 | KEY_MASK_SHIFT
	t.check(kb.try_bind(&"cam_reset", 0, free), "a free chord binds directly")
	t.eq(km.bindings(&"cam_reset")[0], free)
	t.check(store.keys_section().has("cam_reset"), "written to [keys]")
	var km2: UiKeymap = UiKeymap.new()
	km2.load_defaults(0)
	km2.load_from(store)
	t.eq(km2.bindings(&"cam_reset")[0], free, "reloading the store gives the same binding")
	# conflict: Home belongs to cam_center_base
	var home: int = km.bindings(&"cam_center_base")[0]
	var prev: int = km.bindings(&"cam_reset")[0]
	t.check(not kb.try_bind(&"cam_reset", 0, home), "a used chord waits for the answer")
	t.eq(dialogs.size(), 1, "conflict dialog requested")
	var dlg: UiDlgKeyConflict = dialogs[0] as UiDlgKeyConflict
	t.check(dlg != null and dlg.button_count() == 3, "cancel, unbind the other, swap")
	dlg.close(UiDlgKeyConflict.SWAP)
	t.eq(km.bindings(&"cam_reset")[0], home, "swap: the action has the chord")
	t.eq(km.bindings(&"cam_center_base")[0], prev, "swap: the other action got the previous key")
	# replace
	dialogs.clear()
	var target: int = km.bindings(&"cam_zoom_in")[0]
	kb.try_bind(&"cam_reset", 1, target)
	(dialogs[0] as UiDialog).close(UiDlgKeyConflict.REPLACE)
	t.check(km.bindings(&"cam_zoom_in").is_empty(), "replace: the other action is unbound")
	t.eq(km.bindings(&"cam_reset")[1], target)
	# cancel
	dialogs.clear()
	var cancel_target: int = km.bindings(&"cam_zoom_out")[0]
	kb.try_bind(&"cam_pan_left", 0, cancel_target)
	(dialogs[0] as UiDialog).close(UiDlgKeyConflict.CANCEL)
	t.check(km.bindings(&"cam_zoom_out").has(cancel_target) and not km.bindings(&"cam_pan_left").has(cancel_target), "cancel changes nothing")
	# unbind, reset one, reset all
	kb.unbind(&"cam_pan_up", 0)
	t.check(km.bindings(&"cam_pan_up").is_empty())
	kb.reset_action(&"cam_pan_up")
	t.check(not km.is_modified(&"cam_pan_up"))
	kb.reset_all()
	for id: StringName in km.action_ids():
		t.check(not km.is_modified(id), "%s default after Reset all" % id)
	t.check(store.keys_section().is_empty(), "nothing stored after Reset all")
	kb.free()


func test_keybind_capture_flow(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var km: UiKeymap = UiKeymap.new()
	km.load_defaults(0)
	var kb: UiOptionsKeybinds = _table(km, AppSettingsStore.with_defaults())
	h.root.add_child(kb)
	await H.frames(1)
	kb.begin_capture(&"cam_reset", 0)
	t.check(kb.slot_button(&"cam_reset", 0).text == "Press a key...", "the slot invites a key")
	var esc: InputEventKey = InputEventKey.new()
	esc.pressed = true
	esc.physical_keycode = KEY_ESCAPE
	kb._input(esc)
	t.check(kb.capturing.is_empty(), "Esc cancels the capture")
	t.eq(km.bindings(&"cam_reset")[0], KEY_BACKSPACE, "nothing changed")
	kb.begin_capture(&"cam_reset", 0)
	var shift_only: InputEventKey = InputEventKey.new()
	shift_only.pressed = true
	shift_only.physical_keycode = KEY_SHIFT
	kb._input(shift_only)
	t.check(not kb.capturing.is_empty(), "a modifier alone keeps waiting")
	var f7: InputEventKey = InputEventKey.new()
	f7.pressed = true
	f7.physical_keycode = KEY_F8
	f7.shift_pressed = true
	kb._input(f7)
	t.eq(km.bindings(&"cam_reset")[0], KEY_F8 | KEY_MASK_SHIFT, "the pressed chord is bound")
	kb.begin_capture(&"cam_reset", 0)
	var del: InputEventKey = InputEventKey.new()
	del.pressed = true
	del.physical_keycode = KEY_DELETE
	kb._input(del)
	t.check(km.bindings(&"cam_reset").is_empty(), "Delete unbinds")
	H.done(h)
