extends RefCounted
## Keymap (ui.md 10.2 `test_ui_keymap`): conflict-free defaults, packed key format, exact matching, labels, rebinding rules,
## persistence through AppSettingsStore, InputMap installation and the per-OS gesture modifiers. Touches the global
## InputMap, so every test uninstalls its keymap.


func _km(mac: int = 0) -> UiKeymap:
	var k := UiKeymap.new()
	k.load_defaults(mac)
	return k


func _key(code: int, mods: int = 0) -> InputEventKey:
	var e: InputEventKey = UiKeymap.unpack(code | mods)
	e.pressed = true
	return e


## Actions of the installed set an event matches (exact).
func _hits(km: UiKeymap, ev: InputEvent) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: StringName in km.installed_ids():
		if km.matches(ev, id):
			out.append(String(id))
	return out


func test_defaults_are_conflict_free(t: TestCtx) -> void:
	for mac: int in [0, 1]:
		var km: UiKeymap = _km(mac)
		var ids: Array[StringName] = km.action_ids()
		t.ge(ids.size(), 150, "the table has about 150 actions")
		var bad: PackedStringArray = PackedStringArray()
		for a: StringName in ids:
			var d: UiActions.Def = km.def_of(a)
			t.check(d.default.size() >= 1 and d.default.size() <= 2, "%s has 1-2 default bindings" % a)
			for packed: int in d.default:
				var others: PackedStringArray = km.conflicts(packed, d.contexts, a)
				if not others.is_empty():
					bad.append("%s vs %s" % [a, ",".join(others)])
		t.eq(bad, PackedStringArray(), "no shared packed key with an overlapping context (mac=%d)" % mac)


func test_pack_unpack(t: TestCtx) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_1
	e.ctrl_pressed = true
	e.shift_pressed = true
	t.eq(UiKeymap.pack(e), 301989937, "Ctrl+Shift+1")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.alt_pressed = true
	t.eq(UiKeymap.pack(q), 67108945, "Alt+Q")
	for p: int in [301989937, 67108945, KEY_F9, KEY_DELETE | KEY_MASK_CTRL, KEY_A | KEY_MASK_META]:
		t.eq(UiKeymap.pack(UiKeymap.unpack(p)), p, "unpack o pack identity for %d" % p)
	var hand := InputEventKey.new()
	hand.keycode = KEY_S
	t.eq(UiKeymap.pack(hand), KEY_S, "a hand-made event with only `keycode` still packs")
	t.eq(UiActions.parse_chord("Alt+Q"), 67108945)
	t.eq(UiActions.parse_chord("Option+Q"), 67108945)
	t.eq(UiActions.parse_chord("Ctrl+Shift+1"), 301989937)
	t.eq(UiActions.parse_chord("Equal"), KEY_EQUAL)
	t.eq(UiActions.parse_chord("="), KEY_EQUAL)
	t.eq(UiActions.parse_chord("Nonsense+Q"), 0)
	t.eq(UiActions.parse_chord("Ctrl+"), 0)


func test_exact_matching(t: TestCtx) -> void:
	var km: UiKeymap = _km()
	km.install(UiKeymap.Context.GAME)
	t.eq(_hits(km, _key(KEY_1, KEY_MASK_CTRL)), PackedStringArray(["group_assign_1"]), "Ctrl+1 matches only group_assign_1")
	t.eq(_hits(km, _key(KEY_1)), PackedStringArray(["group_select_1"]), "1 matches group_select_1 only")
	t.eq(_hits(km, _key(KEY_1, KEY_MASK_SHIFT)), PackedStringArray(["group_append_1"]), "Shift+1 matches group_append_1 only")
	t.eq(_hits(km, _key(KEY_1, KEY_MASK_CTRL | KEY_MASK_SHIFT)), PackedStringArray(["group_add_1"]))
	t.eq(_hits(km, _key(KEY_S, KEY_MASK_SHIFT)), PackedStringArray(), "Shift+S matches no action")
	t.eq(_hits(km, _key(KEY_S)), PackedStringArray(["cmd_stop"]))
	t.eq(_hits(km, _key(KEY_Q, KEY_MASK_ALT)), PackedStringArray(["card_1"]), "Alt+Q is card_1 and not cam_rotate_left")
	t.eq(_hits(km, _key(KEY_Q)), PackedStringArray(["cam_rotate_left"]))
	t.eq(_hits(km, _key(KEY_PAUSE)), PackedStringArray(["pause_game"]))
	t.eq(_hits(km, _key(KEY_P, KEY_MASK_CTRL)), PackedStringArray(["pause_game"]), "Pause and Ctrl+P both pause")
	t.eq(_hits(km, _key(KEY_P)), PackedStringArray(["cmd_patrol"]))
	t.eq(_hits(km, _key(KEY_J)), PackedStringArray(["cmd_ping"]))
	t.eq(_hits(km, _key(KEY_DELETE)), PackedStringArray(["tool_sell"]))
	t.eq(_hits(km, _key(KEY_DELETE, KEY_MASK_CTRL)), PackedStringArray(["cmd_scuttle"]))
	t.eq(_hits(km, _key(KEY_E, KEY_MASK_CTRL)), PackedStringArray(["toggle_edge_scroll"]))
	t.eq(_hits(km, _key(KEY_TAB)), PackedStringArray(["tab_next"]), "Tab is tab_next in GAME")
	# observer context swaps the meaning of Tab / Space / 1
	km.install(UiKeymap.Context.OBSERVER)
	t.eq(_hits(km, _key(KEY_TAB)), PackedStringArray(["obs_next_player"]))
	t.eq(_hits(km, _key(KEY_SPACE)), PackedStringArray(["obs_pause"]))
	t.eq(_hits(km, _key(KEY_1)), PackedStringArray(["obs_player_1"]))
	t.eq(_hits(km, _key(KEY_S)), PackedStringArray(), "game-only actions are not installed for observers")
	# echo repeats never match unless allowed
	km.install(UiKeymap.Context.GAME)
	var echo: InputEventKey = _key(KEY_PAGEUP)
	echo.echo = true
	t.check(not km.matches(echo, &"cam_tilt_up"), "echo ignored by default")
	t.check(km.matches(echo, &"cam_tilt_up", true), "echo matches for repeat actions")
	# a hand-built event without physical_keycode does not match a physical binding
	var hand := InputEventKey.new()
	hand.keycode = KEY_S
	hand.pressed = true
	t.check(not km.matches(hand, &"cmd_stop"), "physical bindings need physical_keycode on the event")
	km.uninstall(0)


func test_labels(t: TestCtx) -> void:
	var km: UiKeymap = _km()
	@warning_ignore("int_as_enum_without_match")
	var alt_q: String = OS.get_keycode_string((KEY_Q | KEY_MASK_ALT) as Key)
	t.eq(km.label(&"card_1"), alt_q, "label of card_1 = the platform's Alt+Q")
	if OS.get_name() != "macOS":
		t.eq(km.label(&"card_1"), "Alt+Q")
	t.eq(km.label(&"cmd_stop"), "S")
	t.eq(km.label(&"power_1"), "F5")
	t.eq(km.label(&"tool_sell"), "Delete")
	t.eq(km.label(&"no_such_action"), "")
	var mac: UiKeymap = _km(1)
	t.eq(mac.bindings(&"group_assign_3").size(), 2, "macOS gets Cmd+n as a second group-assign default")
	t.eq(mac.bindings(&"cmd_follow").size(), 2, "and Cmd+F for follow")
	t.eq(km.bindings(&"group_assign_3").size(), 1)


func test_bind_conflicts_and_refusals(t: TestCtx) -> void:
	var km: UiKeymap = _km()
	var seen: Array[int] = [0]
	km.bindings_changed.connect(func() -> void: seen[0] += 1)
	var q: int = KEY_Q
	t.eq(km.conflicts(q, UiKeymap.Context.GAME, &"cmd_stop"), PackedStringArray(["cam_rotate_left"]), "Q is rotate-left")
	t.check(not km.bind(&"cmd_stop", 0, q, UiKeymap.Conflict.REFUSE), "refuse leaves everything")
	t.eq(km.bindings(&"cmd_stop"), PackedInt32Array([KEY_S]))
	t.eq(km.bindings(&"cam_rotate_left"), PackedInt32Array([KEY_Q]))
	t.eq(seen[0], 0, "no change signal on refusal")
	t.check(km.bind(&"cmd_stop", 0, q, UiKeymap.Conflict.SWAP), "swap")
	t.eq(km.bindings(&"cmd_stop"), PackedInt32Array([KEY_Q]))
	t.eq(km.bindings(&"cam_rotate_left"), PackedInt32Array([KEY_S]), "the other action received the previous key")
	t.eq(seen[0], 1)
	km.reset_all()
	t.check(km.bind(&"cmd_stop", 0, q, UiKeymap.Conflict.REPLACE), "replace")
	t.eq(km.bindings(&"cam_rotate_left"), PackedInt32Array(), "the other action is unbound")
	km.reset(&"cmd_stop")
	t.eq(km.bindings(&"cmd_stop"), PackedInt32Array([KEY_S]))
	# second slot
	km.reset_all()
	t.check(km.bind(&"cmd_stop", 1, KEY_F10 | KEY_MASK_SHIFT, UiKeymap.Conflict.REFUSE))
	t.eq(km.bindings(&"cmd_stop").size(), 2)
	km.unbind(&"cmd_stop", 0)
	t.eq(km.bindings(&"cmd_stop"), PackedInt32Array([KEY_F10 | KEY_MASK_SHIFT]))
	# forbidden combos
	km.reset_all()
	t.check(not km.bind(&"cmd_stop", 0, KEY_ESCAPE, UiKeymap.Conflict.REPLACE), "Esc only for toggle_menu")
	t.check(km.last_error.contains("Esc"))
	t.check(km.bind(&"toggle_menu", 0, KEY_ESCAPE, UiKeymap.Conflict.REFUSE), "toggle_menu keeps Esc")
	t.check(not km.bind(&"cmd_stop", 0, KEY_F4 | KEY_MASK_ALT, UiKeymap.Conflict.REPLACE), "Alt+F4 is the OS's")
	t.check(not km.bind(&"cmd_stop", 0, KEY_Q | KEY_MASK_META, UiKeymap.Conflict.REPLACE), "Cmd+Q is the OS's")
	t.check(not km.bind(&"cmd_stop", 0, KEY_SHIFT, UiKeymap.Conflict.REPLACE), "a modifier alone")
	t.check(not km.bind(&"cmd_stop", 0, -3, UiKeymap.Conflict.REPLACE), "mouse buttons only for allow_mouse actions")
	t.check(km.bind(&"cam_orbit", 0, -2, UiKeymap.Conflict.REFUSE), "cam_orbit accepts a mouse button")
	t.eq(km.bindings(&"cam_orbit"), PackedInt32Array([-2]))
	t.check(not km.bind(&"nope", 0, KEY_Q, UiKeymap.Conflict.REFUSE))


func test_persistence_round_trip(t: TestCtx) -> void:
	var km: UiKeymap = _km()
	var store: AppSettingsStore = AppSettingsStore.with_defaults()
	km.save_to(store)
	t.eq(store.keys_section().size(), 0, "defaults store nothing")
	t.check(km.bind(&"cmd_scatter", 0, KEY_X | KEY_MASK_SHIFT, UiKeymap.Conflict.REFUSE))
	km.unbind(&"cmd_hold", 0)
	t.check(km.bind(&"card_1", 0, KEY_Q | KEY_MASK_ALT | KEY_MASK_SHIFT, UiKeymap.Conflict.REPLACE))
	km.bind(&"cam_orbit", 0, -2, UiKeymap.Conflict.REFUSE)
	km.save_to(store)
	var sec: Dictionary = store.keys_section()
	t.eq(sec["cmd_scatter"], PackedStringArray(["k:%d" % (KEY_X | KEY_MASK_SHIFT)]))
	t.eq(sec["cmd_hold"], PackedStringArray(), "an empty array means explicitly unbound")
	t.eq(sec["cam_orbit"], PackedStringArray(["m:2"]))
	t.check(not sec.has("cmd_stop"), "unmodified actions are omitted")
	# through the file text
	var text: String = store.to_text()
	var again: AppSettingsStore = AppSettingsStore.with_defaults()
	t.check(again.from_text(text), "the settings text parses")
	var km2: UiKeymap = _km()
	km2.load_from(again)
	for a: StringName in km.action_ids():
		t.eq(km2.bindings(a), km.bindings(a), "round trip of %s" % a)
	# unknown tokens dropped; a row with only garbage keeps the default; unknown actions survive a save
	var junk: Dictionary = {"cmd_stop": PackedStringArray(["x:5", "k:abc"]), "cmd_move": PackedStringArray(["k:%d" % KEY_F11, "zzz"]),
		"future_action": PackedStringArray(["k:65"])}
	var s3: AppSettingsStore = AppSettingsStore.with_defaults()
	s3.set_keys_section(junk)
	var km3: UiKeymap = _km()
	km3.load_from(s3)
	t.eq(km3.bindings(&"cmd_stop"), PackedInt32Array([KEY_S]), "all-garbage row keeps the default")
	t.eq(km3.bindings(&"cmd_move"), PackedInt32Array([KEY_F11]), "unknown tokens dropped")
	km3.save_to(s3)
	t.check(s3.keys_section().has("future_action"), "unknown actions are preserved")


func test_install_uninstall_and_tab(t: TestCtx) -> void:
	var before: int = InputMap.action_get_events(&"ui_focus_next").size()
	t.gt(before, 0, "the engine binds Tab to ui_focus_next")
	var km: UiKeymap = _km()
	km.install(UiKeymap.Context.GAME)
	t.check(InputMap.has_action(&"cmd_stop") and InputMap.has_action(&"toggle_menu"), "GAME + GLOBAL actions installed")
	t.check(not InputMap.has_action(&"obs_pause"), "observer actions are not")
	t.eq(InputMap.action_get_events(&"ui_focus_next").size(), 0, "Tab freed in GAME (spike case R)")
	t.eq(InputMap.action_get_events(&"ui_focus_prev").size(), 0)
	t.gt(InputMap.action_get_events(&"ui_accept").size(), 0, "ui_accept is never touched")
	t.check(km.bind(&"cmd_stop", 0, KEY_F11 | KEY_MASK_SHIFT, UiKeymap.Conflict.REFUSE), "rebinding while installed reinstalls")
	t.eq(InputMap.action_get_events(&"cmd_stop").size(), 1)
	var e: InputEvent = InputMap.action_get_events(&"cmd_stop")[0]
	t.check(e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F11, "events use physical_keycode")
	km.install(UiKeymap.Context.MENU)
	t.check(not InputMap.has_action(&"cmd_stop"), "stale actions erased when the context changes")
	t.eq(InputMap.action_get_events(&"ui_focus_next").size(), before, "Tab restored outside GAME / OBSERVER")
	km.install(UiKeymap.Context.OBSERVER)
	t.eq(InputMap.action_get_events(&"ui_focus_next").size(), 0)
	km.uninstall(UiKeymap.Context.OBSERVER)
	t.eq(InputMap.action_get_events(&"ui_focus_next").size(), before, "uninstall restores ui_focus_next")
	t.check(not InputMap.has_action(&"obs_pause"))


func test_mods_of_per_os(t: TestCtx) -> void:
	var km: UiKeymap = _km()
	var ev := InputEventMouseButton.new()
	km.os_name = "Windows"
	ev.ctrl_pressed = true
	t.eq(km.mods_of(ev), UiKeymap.MOD_CTRL, "Ctrl is the force-fire role on Windows / Linux")
	ev.shift_pressed = true
	t.eq(km.mods_of(ev), UiKeymap.MOD_CTRL | UiKeymap.MOD_SHIFT)
	km.os_name = "macOS"
	t.eq(km.mods_of(ev), UiKeymap.MOD_SHIFT, "Ctrl+click is a right click on macOS: no role")
	ev.ctrl_pressed = false
	ev.alt_pressed = true
	t.eq(km.mods_of(ev), UiKeymap.MOD_CTRL | UiKeymap.MOD_SHIFT, "Option is the force-fire role on macOS")
	km.os_name = "Linux"
	t.eq(km.mods_of(ev), UiKeymap.MOD_ALT | UiKeymap.MOD_SHIFT, "raw Alt elsewhere")
	t.eq(UiActions.indexed(&"group_select_7", "group_select_"), 7)
	t.eq(UiActions.indexed(&"cmd_stop", "group_select_"), -1)
