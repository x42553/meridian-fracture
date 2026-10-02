extends RefCounted
## Procedural cursors (ui.md 5.7.3, 7.7): 17 base states on 17 distinct slots, images at three sizes, hotspot scaling, the scroll
## arrows swapping onto the ARROW slot only on a direction change, and the first-run dialog / credits data.

func _on() -> void:
	UiCursors.reset()
	UiCursors.enabled_override = true
	UiCursors.register_all(100, 0)


func _off() -> void:
	UiCursors.reset()
	UiCursors.enabled_override = false
	UiCursors.register_all(100, 1)


func test_seventeen_states_map_to_seventeen_slots(t: TestCtx) -> void:
	var slots: Dictionary = {}
	for st: int in 17:
		slots[UiCursors.slot_of(st)] = true
	t.eq(slots.size(), 17, "17 base states, 17 distinct Input.CursorShape slots")
	t.eq(UiCursors.slot_of(UiCursors.State.POWER), Input.CURSOR_CROSS, "power reticle uses the CROSS slot")
	t.eq(UiCursors.slot_of(UiCursors.State.SUPERWEAPON), Input.CURSOR_CROSS)
	t.eq(UiCursors.slot_of(UiCursors.State.PLACE_OK), Input.CURSOR_ARROW)
	t.eq(UiCursors.slot_of(UiCursors.State.PLACE_BAD), Input.CURSOR_FORBIDDEN)
	t.eq(UiCursors.slot_of(UiCursors.State.SCROLL_NE), Input.CURSOR_ARROW, "scroll arrows live on the ARROW slot")


func test_every_state_rasterises_at_three_sizes(t: TestCtx) -> void:
	for st: int in 29:
		for px: int in UiCursors.sizes():
			var img: Image = UiCursors.image_for(st, px)
			t.check(img != null and img.get_width() == px and img.get_height() == px, "%s at %d px" % [UiCursors.state_name(st), px])
			if img != null:
				var opaque: int = 0
				for y: int in range(0, px, 2):
					for x: int in range(0, px, 2):
						if img.get_pixel(x, y).a > 0.5:
							opaque += 1
				t.check(opaque > px / 4, "%s has visible pixels" % UiCursors.state_name(st))
	var hc: Image = UiCursors.image_for(UiCursors.State.ATTACK, 32, true)
	var normal: Image = UiCursors.image_for(UiCursors.State.ATTACK, 32, false)
	t.check(hc.get_data() != normal.get_data(), "high contrast adds a white outer ring")


func test_hotspots_scale_with_the_size(t: TestCtx) -> void:
	var h32: Vector2 = UiCursors.hotspot_of(UiCursors.State.RALLY, 32)
	var h64: Vector2 = UiCursors.hotspot_of(UiCursors.State.RALLY, 64)
	t.eq(h64, h32 * 2.0, "hotspots are fractions of the image")
	t.eq(UiCursors.hotspot_of(UiCursors.State.ATTACK, 48), Vector2(24, 24))
	var ne: Vector2 = UiCursors.hotspot_of(UiCursors.State.SCROLL_NE, 32)
	t.check(ne.x > 20.0 and ne.y < 12.0, "rotated scroll hotspot sits at the arrow tip: %s" % ne)
	t.eq(UiCursors.size_for_scale(150), 48)
	t.eq(UiCursors.size_for_scale(200), 64)


func test_set_state_is_a_noop_when_unchanged(t: TestCtx) -> void:
	_on()
	var n0: int = UiCursors.apply_calls
	t.check(UiCursors.is_active())
	UiCursors.set_state(UiCursors.State.ATTACK)
	var n1: int = UiCursors.apply_calls
	t.gt(n1, n0)
	UiCursors.set_state(UiCursors.State.ATTACK)
	t.eq(UiCursors.apply_calls, n1, "same state: no engine call")
	UiCursors.set_state(UiCursors.State.MOVE)
	t.eq(Input.get_current_cursor_shape(), Input.CURSOR_MOVE if DisplayServer.get_name() != "headless" else Input.get_current_cursor_shape())
	t.gt(UiCursors.apply_calls, n1)
	# the power reticle swaps into CROSS once and back once
	UiCursors.set_state(UiCursors.State.POWER)
	var n2: int = UiCursors.apply_calls
	UiCursors.set_state(UiCursors.State.ATTACK)
	t.gt(UiCursors.apply_calls, n2, "restoring the crosshair swaps the image back")
	_off()


func test_scroll_arrows_swap_only_on_direction_change(t: TestCtx) -> void:
	_on()
	UiCursors.set_scroll(Vector2i(0, -1))
	var n: int = UiCursors.apply_calls
	t.eq(UiCursors.current_state(), UiCursors.State.SCROLL_N)
	UiCursors.set_scroll(Vector2i(0, -1))
	t.eq(UiCursors.apply_calls, n, "same direction: no call")
	UiCursors.set_scroll(Vector2i(1, -1))
	t.gt(UiCursors.apply_calls, n)
	t.eq(UiCursors.current_state(), UiCursors.State.SCROLL_NE)
	var n2: int = UiCursors.apply_calls
	UiCursors.set_scroll(Vector2i.ZERO)
	t.gt(UiCursors.apply_calls, n2, "leaving the band restores the arrow")
	t.eq(UiCursors.current_state(), UiCursors.State.DEFAULT)
	var n3: int = UiCursors.apply_calls
	UiCursors.set_scroll(Vector2i.ZERO)
	t.eq(UiCursors.apply_calls, n3, "still zero: nothing to do")
	t.eq(UiCursors.scroll_state(Vector2i(-1, 1)), UiCursors.State.SCROLL_SW)
	_off()


func test_system_cursor_style_registers_nothing(t: TestCtx) -> void:
	_off()
	t.check(not UiCursors.is_active())
	UiCursors.set_state(UiCursors.State.ATTACK)
	t.eq(UiCursors.current_state(), UiCursors.State.ATTACK, "state is tracked")


func test_first_run_dialog_writes_settings_and_clears_the_flag(t: TestCtx) -> void:
	var s: Node = (load("res://src/app/app_settings.gd") as GDScript).new() as Node
	s.call("configure", "user://ut_first.cfg", true)
	var d: UiDlgFirstRun = UiDlgFirstRun.new(s)
	t.check(not d.dismiss_on_escape, "Escape does not skip the first-run dialog")
	t.eq(d.quality_pick.get_selected_id(), AppGraphics.recommend(), "graphics pre-set to the recommendation")
	d.name_edit.text = "  Ada\u0007 Lovelace "
	d.scale_pick.select(2)
	d.cvd_check.button_pressed = true
	d.close(UiDlgFirstRun.CONFIRM)
	var store: AppSettingsStore = s.get("store") as AppSettingsStore
	t.eq(store.get_value(&"net/player_name"), "Ada Lovelace")
	t.eq(store.get_value(&"video/ui_scale"), 150)
	t.eq(store.get_value(&"access/colour_mode"), "cvd")
	t.eq(store.get_value(&"meta/first_run"), false)
	d.free()
	var s2: Node = (load("res://src/app/app_settings.gd") as GDScript).new() as Node
	s2.call("configure", "user://ut_first2.cfg", true)
	var d2: UiDlgFirstRun = UiDlgFirstRun.new(s2)
	d2.name_edit.text = "Ignored"
	d2.close(UiDlgFirstRun.DEFAULTS)
	var st2: AppSettingsStore = s2.get("store") as AppSettingsStore
	t.eq(st2.get_value(&"meta/first_run"), false)
	t.check(st2.get_value(&"net/player_name") != "Ignored", "Use defaults keeps the defaults")
	d2.free()
	s.free()
	s2.free()


func test_credits_name_the_engine_licence_and_the_fonts(t: TestCtx) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/text/credits.json"))
	t.check(parsed is Dictionary)
	var text: String = JSON.stringify(parsed)
	t.check(text.contains("MIT License"), "engine MIT notice")
	for f: String in ["Rajdhani", "Orbitron", "Share Tech Mono"]:
		t.check(text.contains(f), "font %s credited" % f)
	t.check(text.contains("SIL Open Font License"), "OFL named")
	for dir: String in ["orbitron", "rajdhani", "share_tech_mono"]:
		t.check(FileAccess.file_exists("res://assets/fonts/%s/OFL.txt" % dir), "%s licence text ships with the font" % dir)
