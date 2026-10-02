extends RefCounted
## Settings store, schema, crash-safe writer, window clamp and graphics glue (ui.md 10.2 `test_ui_settings`,
## `test_app_settings_atomic_write`, `test_app_window_clamp`).

const U := preload("res://tests/ui/app_test_util.gd")


func _store_with(pairs: Dictionary) -> AppSettingsStore:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	for k: Variant in pairs:
		s.set_value(StringName(k), pairs[k])
	return s


func test_schema_rows_unique_and_typed(t: TestCtx) -> void:
	var seen: Dictionary = {}
	for row: Dictionary in AppSettingsSchema.entries():
		var id: String = String(row["id"])
		t.check(not seen.has(id), "unique id %s" % id)
		seen[id] = true
		t.check(id.contains("/"), "section/key %s" % id)
		t.check(["video", "audio", "input", "ui", "quality", "net", "misc"].has(String(row["apply"])), "apply hook of %s" % id)
		var d: Variant = row["default"]
		if bool(row["preset"]):
			t.is_null(d, "%s preset rows default to null" % id)
			continue
		match int(row["type"]):
			AppSettingsSchema.T.BOOL:
				t.check(d is bool, "%s bool" % id)
			AppSettingsSchema.T.INT:
				t.check(d is int, "%s int" % id)
			AppSettingsSchema.T.FLOAT:
				t.check(d is float, "%s float" % id)
			AppSettingsSchema.T.STRING:
				t.check(d is String, "%s string" % id)
			AppSettingsSchema.T.VECTOR2I:
				t.check(d is Vector2i, "%s vector2i" % id)
			AppSettingsSchema.T.LIST:
				t.check(d is PackedStringArray, "%s list" % id)
			AppSettingsSchema.T.CHOICE:
				var ok: bool = false
				for c: Dictionary in row["choices"]:
					ok = ok or c["value"] == d
				t.check(ok, "%s default is one of its choices" % id)
	for must: String in ["meta/version", "meta/first_run", "video/window_mode", "video/resolution", "video/ui_scale", "video/quality",
			"video/renderer", "audio/master", "audio/ambience", "access/colour_mode", "input/drag_threshold", "ui/sidebar_side",
			"game/last_roster", "net/player_name", "net/port", "net/recent_hosts", "net/auto_drop_ms"]:
		t.check(seen.has(must), "row %s exists" % must)
	t.gt(seen.size(), 85, "the schema lists the whole table of 4.8.1")


func test_defaults_and_clamps(t: TestCtx) -> void:
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.get_value(&"video/ui_scale"), 100)
	t.eq(s.get_value(&"audio/music"), 70)
	t.eq(s.get_value(&"video/resolution"), Vector2i(1600, 900))
	t.eq(s.get_value(&"net/port"), 27615)
	t.check(s.set_value(&"video/ui_scale", 250))
	t.eq(s.get_value(&"video/ui_scale"), 200, "ui_scale 250 -> 200")
	t.check(s.set_value(&"video/ui_scale", 123))
	t.eq(s.get_value(&"video/ui_scale"), 125, "ui_scale snaps to the 5 step")
	s.set_value(&"audio/master", -5)
	t.eq(s.get_value(&"audio/master"), 0, "audio/master -5 -> 0")
	t.check(not s.set_value(&"no/such_id", 1), "unknown id -> false")
	t.check(not s.set_value(&"video/vsync", 9), "value outside the choices -> false")
	t.check(not s.set_value(&"audio/master", "loud"), "unusable value -> false")
	t.eq(s.get_value(&"audio/master"), 0, "a refused value changes nothing")
	s.set_value(&"video/resolution", Vector2i(100, 100))
	t.eq(s.get_value(&"video/resolution"), Vector2i(1024, 576), "resolution has the window minimum")
	s.set_value(&"video/render_scale", 0.84)
	t.near(float(s.get_value(&"video/render_scale")), 0.85, 0.0001, "render_scale snaps to 0.05")
	t.is_null(s.get_value(&"video/msaa"), "an unset preset row reads null")
	s.set_value(&"net/player_name", "  Ann\u0007  Lee ")
	t.eq(s.get_value(&"net/player_name"), "Ann Lee", "name sanitised")
	s.set_value(&"net/recent_hosts", ["a:1", "b:2", "c:3", "d:4", "e:5", "f:6", "g:7", "h:8", "i:9"])
	t.eq((s.get_value(&"net/recent_hosts") as PackedStringArray).size(), 8, "recent hosts capped at 8")
	t.check(s.set_value(&"video/ui_scale", null), "null resets")
	t.check(s.is_default(&"video/ui_scale"))


func test_text_round_trip_writes_only_non_defaults(t: TestCtx) -> void:
	var s: AppSettingsStore = _store_with({"video/ui_scale": 110, "video/quality": 3 if AppGraphics.recommend() != 3 else 1,
		"video/render_scale": 0.85, "access/colour_mode": "cvd", "meta/first_run": false, "net/recent_hosts": ["192.168.1.20:27615"]})
	s.set_value(&"video/vsync", 1)
	s.set_keys_section({"cmd_attack_move": PackedStringArray(["k:65"])})
	var text: String = s.to_text()
	t.check(text.contains("[meta]") and text.contains("version=1"), "meta version written")
	t.check(text.contains("ui_scale=110") and text.contains("render_scale=0.85"), "changed values written")
	t.check(text.contains("colour_mode=\"cvd\""), "string value")
	t.check(text.contains("first_run=false"))
	t.check(not text.contains("vsync"), "a default is not written")
	t.check(not text.contains("[audio]"), "an all-default section is absent")
	t.check(text.contains("[controls]") and text.contains("PackedStringArray(\"k:65\")"), "key bindings")
	var back: AppSettingsStore = AppSettingsStore.with_defaults()
	t.check(back.from_text(text), "text parses")
	t.eq(back.get_value(&"video/ui_scale"), 110)
	t.eq(back.get_value(&"access/colour_mode"), "cvd")
	t.eq(back.get_value(&"net/recent_hosts"), PackedStringArray(["192.168.1.20:27615"]))
	t.eq(back.keys_section()["cmd_attack_move"], PackedStringArray(["k:65"]))
	t.check(not back.dirty(), "a freshly loaded store is clean")


func test_unknown_keys_and_newer_version_are_preserved(t: TestCtx) -> void:
	var dir: String = U.sandbox("unk")
	var path: String = dir.path_join("settings.cfg")
	U.write(path, "[meta]\nversion=7\n[video]\nui_scale=120\nfuture_key=\"kept\"\n[experimental]\nflag=true\n")
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.load_from(path), OK, "a newer file version still loads")
	t.eq(s.get_value(&"video/ui_scale"), 120)
	t.check(s.save_to(path) == OK)
	var text: String = U.read(path)
	t.check(text.contains("future_key=\"kept\""), "unknown key kept")
	t.check(text.contains("[experimental]") and text.contains("flag=true"), "unknown section kept verbatim")
	t.check(text.contains("version=7"), "newer version not downgraded")
	U.cleanup(dir)


func test_invalid_values_fall_back_with_a_note(t: TestCtx) -> void:
	var dir: String = U.sandbox("inv")
	var path: String = dir.path_join("settings.cfg")
	U.write(path, "[video]\nvsync=9\nui_scale=\"wide\"\n[audio]\nmaster=55\n")
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.load_from(path), OK)
	t.eq(s.get_value(&"video/vsync"), 1, "invalid choice -> default")
	t.eq(s.get_value(&"audio/master"), 55)
	t.eq(s.load_notes.size(), 2, "one note per invalid value")
	U.cleanup(dir)


func test_corrupt_file_is_renamed_and_defaults_load(t: TestCtx) -> void:
	t.expect_errors(1)  # ConfigFile.parse reports the broken tag itself
	var dir: String = U.sandbox("bad")
	var path: String = dir.path_join("settings.cfg")
	U.write(path, "[video\nui_scale=")
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.load_from(path), ERR_PARSE_ERROR, "corrupt and no backup")
	t.eq(s.get_value(&"video/ui_scale"), 100, "defaults")
	t.gt(s.load_notes.size(), 0, "load_notes explain")
	var bad: int = 0
	for f: String in DirAccess.get_files_at(dir):
		bad += 1 if f.begins_with("settings.cfg.bad-") else 0
	t.eq(bad, 1, "the corrupt file was kept as settings.cfg.bad-<utc>")
	t.check(not FileAccess.file_exists(path), "and moved away")
	U.cleanup(dir)


func test_corrupt_file_with_valid_backup_restores_it(t: TestCtx) -> void:
	t.expect_errors(1)
	var dir: String = U.sandbox("bak")
	var path: String = dir.path_join("settings.cfg")
	var good: AppSettingsStore = _store_with({"video/ui_scale": 140})
	U.write(path + ".bak", good.to_text())
	U.write(path, "this is not a config file\nvideo ui_scale = wide")
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.load_from(path), OK, "the backup was used")
	t.eq(s.get_value(&"video/ui_scale"), 140)
	t.check(FileAccess.file_exists(path), "settings.cfg restored from the backup")
	U.cleanup(dir)


func test_missing_file_uses_backup_then_defaults(t: TestCtx) -> void:
	var dir: String = U.sandbox("miss")
	var path: String = dir.path_join("settings.cfg")
	var s: AppSettingsStore = AppSettingsStore.with_defaults()
	t.eq(s.load_from(path), ERR_FILE_NOT_FOUND, "nothing at all = first run, defaults")
	t.eq(s.load_notes.size(), 0, "a first run is not an error")
	U.write(path + ".bak", _store_with({"audio/music": 12}).to_text())
	t.eq(s.load_from(path), OK)
	t.eq(s.get_value(&"audio/music"), 12)
	U.cleanup(dir)


## The write sequence is interrupted after every mutating step; a valid file is always recoverable.
func test_app_settings_atomic_write(t: TestCtx) -> void:
	for partial: bool in [false, true]:
		for cut: int in range(0, 5):
			var dir: String = U.sandbox("atomic")
			var path: String = dir.path_join("settings.cfg")
			var a: AppSettingsStore = _store_with({"video/ui_scale": 110})
			t.eq(a.save_to(path), OK, "first save")
			t.eq(a.save_to(path), OK, "second save creates the .bak")
			var b: AppSettingsStore = _store_with({"video/ui_scale": 120})
			var crashy: Object = U.Crashy.new(cut, partial)
			var err: int = b.save_to(path, crashy)
			t.eq(err == OK, cut >= 4, "cut %d completes only when the whole sequence ran" % cut)
			var loaded: AppSettingsStore = AppSettingsStore.with_defaults()
			var lerr: int = loaded.load_from(path)
			t.eq(lerr, OK, "cut %d (partial %s): a valid file is loadable" % [cut, partial])
			var ui: int = int(loaded.get_value(&"video/ui_scale"))
			t.check(ui == 110 or ui == 120, "cut %d: old or new value, never garbage (%d)" % [cut, ui])
			t.eq(ui, 120 if cut >= 4 else 110, "cut %d keeps the previous state until the last rename" % cut)
			t.check(FileAccess.file_exists(path), "cut %d: settings.cfg exists again after load" % cut)
			var again: AppSettingsStore = AppSettingsStore.with_defaults()
			t.eq(again.load_from(path), OK, "and stays loadable")
			U.cleanup(dir)


func test_save_failure_is_reported_not_thrown(t: TestCtx) -> void:
	var s: AppSettingsStore = _store_with({"video/ui_scale": 110})
	var err: int = s.save_to("user://no_such_folder_ut/deeper/settings.cfg")
	t.check(err != OK, "unwritable location fails")
	t.eq(s.last_error, err)
	t.check(s.dirty(), "the store stays dirty (memory only)")
	t.eq(s.get_value(&"video/ui_scale"), 110, "and keeps working")


func test_app_window_clamp(t: TestCtx) -> void:
	var one: Array[Rect2i] = [Rect2i(0, 0, 1920, 1080)]
	var two: Array[Rect2i] = [Rect2i(0, 0, 1920, 1080), Rect2i(1920, 0, 2560, 1440)]
	# fits: unchanged
	t.eq(AppApply.clamp_window_rect(Rect2i(100, 80, 1600, 900), one), Rect2i(100, 80, 1600, 900))
	# hanging off the right edge: pulled back inside
	t.eq(AppApply.clamp_window_rect(Rect2i(1000, 500, 1600, 900), one), Rect2i(320, 180, 1600, 900))
	# unplugged monitor: saved on screen 2, only screen 1 exists -> centred on the primary
	t.eq(AppApply.clamp_window_rect(Rect2i(2500, 100, 1600, 900), one), Rect2i(160, 90, 1600, 900))
	# the same rectangle with two screens stays where it was
	t.eq(AppApply.clamp_window_rect(Rect2i(2500, 100, 1600, 900), two), Rect2i(2500, 100, 1600, 900))
	# larger than the screen: shrunk to it
	t.eq(AppApply.clamp_window_rect(Rect2i(0, 0, 3000, 2000), one), Rect2i(0, 0, 1920, 1080))
	# below the minimum: raised
	t.eq(AppApply.clamp_window_rect(Rect2i(10, 10, 300, 200), one).size, Vector2i(1024, 576))
	# straddling two screens: assigned to the one with the larger overlap and moved inside it
	var straddle: Rect2i = AppApply.clamp_window_rect(Rect2i(1500, 100, 1600, 900), two)
	t.check(two[1].encloses(straddle) or one[0].encloses(straddle), "inside exactly one screen")
	t.eq(straddle.position, Vector2i(1920, 100), "second screen has the larger overlap")
	# no screens known: only the size rule
	t.eq(AppApply.clamp_window_rect(Rect2i(5, 5, 800, 500), [] as Array[Rect2i]).size, Vector2i(1024, 576))
	# via the store: window_pos (-1, -1) means "let the OS place"
	var s: AppSettingsStore = _store_with({"video/resolution": Vector2i(1280, 720)})
	var plan: Dictionary = AppApply.window_plan(s, one, 0)
	t.check(not bool(plan["pos_valid"]), "no saved position")
	t.eq((plan["rect"] as Rect2i).size, Vector2i(1280, 720))
	s.set_value(&"video/window_pos", Vector2i(4000, 4000))
	s.set_value(&"video/monitor", 1)
	plan = AppApply.window_plan(s, one, 0)
	t.check(bool(plan["pos_valid"]))
	t.eq(int(plan["monitor"]), -1, "a monitor that is gone is forgotten")
	t.eq((plan["rect"] as Rect2i).position, Vector2i(320, 180), "centred on the primary screen")


func test_graphics_overrides(t: TestCtx) -> void:
	var s: AppSettingsStore = _store_with({"video/quality": 1})
	t.eq(AppGraphics.overrides(s).size(), 0, "a preset-only file has no overrides")
	t.eq(AppGraphics.preset_label(s), "Medium")
	s.set_value(&"video/msaa", 2)
	s.set_value(&"video/shadow_mode", "cascades2")
	s.set_value(&"video/health_bars", 3)
	var o: PackedStringArray = AppGraphics.overrides(s)
	t.eq(o, PackedStringArray(["msaa", "shadow_mode"]), "only preset-table keys count (health_bars is not one)")
	t.eq(AppGraphics.preset_label(s), "Custom (based on Medium)")
	AppGraphics.clear_overrides(s)
	t.eq(AppGraphics.overrides(s).size(), 0)
	t.is_null(s.get_value(&"video/msaa"))
	t.eq(AppGraphics.recommend(), ViewQuality.recommend(), "recommend forwards the view")


func test_profile_name_sanitising(t: TestCtx) -> void:
	t.eq(AppProfile.sanitize_name(""), "Commander")
	t.eq(AppProfile.sanitize_name("\u0001\u0002"), "Commander")
	t.eq(AppProfile.sanitize_name("  a   b  "), "a b")
	t.eq(AppProfile.sanitize_name("x".repeat(40)).length(), 24)
	var p: AppProfile = AppProfile.new()
	p.player_name = "山田 Ann"
	t.eq(p.ascii_name(), "__ Ann".replace(" ", "_"), "non-ASCII characters become underscores")


## The autoload node: debounced save (0.5 s) into a sandbox, in-memory mode never writes, overrides are not persisted.
func test_app_settings_node_debounce_and_overrides(t: TestCtx) -> void:
	t.set_timeout(10.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var node: Node = (load("res://src/app/app_settings.gd") as GDScript).new() as Node
	tree.root.add_child(node)
	await tree.process_frame
	var dir: String = U.sandbox("node")
	var path: String = dir.path_join("settings.cfg")
	node.call("configure", path, false)
	node.call("set_overrides", {"video/ui_scale": 150})
	t.eq(int(node.call("get_int", &"video/ui_scale")), 150, "override wins")
	node.call("set_value", &"audio/master", 42)
	t.check(not FileAccess.file_exists(path), "not written immediately (debounce)")
	await tree.create_timer(0.8).timeout
	t.check(FileAccess.file_exists(path), "written after the debounce")
	var text: String = U.read(path)
	t.check(text.contains("master=42"))
	t.check(not text.contains("ui_scale"), "the override is never persisted")
	node.call("set_value", &"audio/music", 5)
	node.call("flush")
	t.check(U.read(path).contains("music=5"), "flush saves at once")
	var mem_dir: String = U.sandbox("mem")
	node.call("configure", mem_dir.path_join("settings.cfg"), true)
	node.call("set_value", &"audio/master", 11)
	node.call("flush")
	t.check(not FileAccess.file_exists(mem_dir.path_join("settings.cfg")), "in-memory mode never writes")
	tree.root.remove_child(node)
	node.free()
	U.cleanup(dir)
	U.cleanup(mem_dir)
