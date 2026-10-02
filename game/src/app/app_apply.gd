class_name AppApply
extends RefCounted
## Applies settings to the engine (ui.md 3.1): window / vsync / fps, UI scale, accessibility, tooltip delay, and the hand-offs
## to the other modules through injectable sinks (the audio, view and input modules are wired later; until then the sinks
## stay empty and nothing happens). Pure static; every function takes the store (and optional CLI overrides
## `{id: value}` that are never persisted).

## `func(values: Dictionary)`: `[audio]` + `[access]` values for `Snd.apply_settings` (set by `AppAudio`).
static var audio_sink: Callable = Callable()
## `func(cfg: ConfigFile)`: the `[video]` + `[access]` config for `ViewQuality.from_settings` (`UiViewPort.apply_quality`).
static var quality_sink: Callable = Callable()
## `func(id: StringName, store: AppSettingsStore)`: input settings changed (keymap, camera speeds, cursor confinement).
static var input_sink: Callable = Callable()


## Value with CLI overrides on top.
static func value(store: AppSettingsStore, id: StringName, overrides: Dictionary = {}) -> Variant:
	if overrides.has(String(id)):
		var row: Dictionary = AppSettingsSchema.entry(id)
		if not row.is_empty():
			var v: Variant = AppSettingsStore.coerce(row, overrides[String(id)])
			if v != null:
				return v
	return store.get_value(id)


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Routes one changed id by its schema `apply` hook.
static func on_changed(id: StringName, store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	if id == &"controls/*":
		if input_sink.is_valid():
			input_sink.call(id, store)
		return
	var row: Dictionary = AppSettingsSchema.entry(id)
	if row.is_empty():
		return
	match StringName(row["apply"]):
		&"video":
			apply_video(store, overrides)
		&"ui":
			if id == &"video/ui_scale":
				apply_ui_scale(_root_window(), store, overrides)
			apply_ui(store, overrides)
		&"audio":
			apply_audio(store, overrides)
		&"input":
			if input_sink.is_valid():
				input_sink.call(id, store)
		&"quality":
			apply_quality(store, overrides)
		&"net":
			pass
		_:
			pass


## Boot: everything once.
static func apply_all(store: AppSettingsStore, overrides: Dictionary = {}, manage_window: bool = true) -> void:
	if manage_window:
		apply_video(store, overrides)
	else:
		apply_frame_limits(store, overrides)
	apply_ui_scale(_root_window(), store, overrides)
	apply_ui(store, overrides)
	apply_audio(store, overrides)
	if input_sink.is_valid():
		input_sink.call(&"controls/*", store)
	apply_quality(store, overrides)


static func _root_window() -> Window:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


# ---------------------------------------------------------------- video

## vsync mode and the frame cap (safe in every display server).
static func apply_frame_limits(store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	Engine.max_fps = int(value(store, &"video/fps_cap", overrides))
	if not _headless():
		var modes: Array[int] = [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE,
			DisplayServer.VSYNC_MAILBOX]
		DisplayServer.window_set_vsync_mode(modes[clampi(int(value(store, &"video/vsync", overrides)), 0, 3)] as DisplayServer.VSyncMode)


## Window mode, size and position (the saved rectangle is clamped to the screens that exist, QA X-13), vsync and the fps cap.
static func apply_video(store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	apply_frame_limits(store, overrides)
	if _headless():
		return
	var plan: Dictionary = window_plan(store, screen_rects(), DisplayServer.get_primary_screen(), overrides)
	var monitor: int = int(plan["monitor"])
	match int(plan["mode"]):
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var rect: Rect2i = plan["rect"] as Rect2i
			DisplayServer.window_set_size(rect.size)
			if bool(plan["pos_valid"]):
				DisplayServer.window_set_position(rect.position)
		1:
			if monitor >= 0:
				DisplayServer.window_set_current_screen(monitor)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if monitor >= 0:
				DisplayServer.window_set_current_screen(monitor)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


## Usable rectangles of the connected screens.
static func screen_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i: int in DisplayServer.get_screen_count():
		out.append(DisplayServer.screen_get_usable_rect(i))
	return out


## Pure plan: `{mode, rect: Rect2i, pos_valid: bool, monitor: int}`. `monitor` is -1 when the saved index no longer exists.
static func window_plan(store: AppSettingsStore, screens: Array[Rect2i], primary: int, overrides: Dictionary = {}) -> Dictionary:
	var size: Vector2i = value(store, &"video/resolution", overrides) as Vector2i
	var pos: Vector2i = value(store, &"video/window_pos", overrides) as Vector2i
	var monitor: int = int(value(store, &"video/monitor", overrides))
	if monitor >= screens.size():
		monitor = -1
	var pos_valid: bool = pos != Vector2i(-1, -1)
	var rect: Rect2i = clamp_window_rect(Rect2i(pos if pos_valid else Vector2i.ZERO, size), screens, primary, pos_valid, monitor)
	return {"mode": int(value(store, &"video/window_mode", overrides)), "rect": rect, "pos_valid": pos_valid, "monitor": monitor}


## Clamps a window rectangle to the screens that exist: the size is at least the minimum window and at most the target
## screen, the target screen is the one with the largest overlap (else `preferred` monitor, else the primary), and the
## rectangle is moved fully inside it. A rectangle that overlaps no screen (an unplugged monitor) is centred on the
## target. `place = false` only clamps the size and leaves the position alone (the OS places the window).
static func clamp_window_rect(rect: Rect2i, screens: Array[Rect2i], primary: int = 0, place: bool = true, preferred: int = -1) -> Rect2i:
	var out: Rect2i = Rect2i(rect.position, Vector2i(maxi(rect.size.x, AppSettingsSchema.MIN_WINDOW.x),
		maxi(rect.size.y, AppSettingsSchema.MIN_WINDOW.y)))
	if screens.is_empty():
		return out
	var target: int = -1
	var best: int = 0
	if place:
		for i: int in screens.size():
			var area: Rect2i = screens[i].intersection(out)
			var a: int = area.size.x * area.size.y
			if a > best:
				best = a
				target = i
	var overlapped: bool = target >= 0
	if target < 0:
		target = preferred if preferred >= 0 and preferred < screens.size() else clampi(primary, 0, screens.size() - 1)
	var s: Rect2i = screens[target]
	out.size = Vector2i(mini(out.size.x, maxi(s.size.x, AppSettingsSchema.MIN_WINDOW.x)),
		mini(out.size.y, maxi(s.size.y, AppSettingsSchema.MIN_WINDOW.y)))
	if not place:
		return out
	if not overlapped:
		out.position = s.position + (s.size - out.size) / 2
	else:
		out.position = Vector2i(clampi(out.position.x, s.position.x, maxi(s.position.x, s.end.x - out.size.x)),
			clampi(out.position.y, s.position.y, maxi(s.position.y, s.end.y - out.size.y)))
	return out


## Writes the current windowed rectangle back into the store (call before saving / on quit).
static func capture_window(store: AppSettingsStore) -> void:
	if _headless() or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	store.set_value(&"video/resolution", DisplayServer.window_get_size())
	store.set_value(&"video/window_pos", DisplayServer.window_get_position())
	store.set_value(&"video/monitor", DisplayServer.window_get_current_screen())


# ---------------------------------------------------------------- ui

## Requested factor for a window (5.4.1).
static func ui_factor(window_px: Vector2i, ui_scale_pct: int) -> float:
	return UiLayout.factor(window_px, float(ui_scale_pct) / 100.0)


## The scale the player effectively gets at this window size, in percent ("200 % requested, 178 % effective").
static func effective_pct(window_px: Vector2i, ui_scale_pct: int) -> int:
	var base: float = clampf(float(window_px.y) / float(UiMetrics.DESIGN_H), 0.75, 2.0)
	return roundi(ui_factor(window_px, ui_scale_pct) / base * 100.0)


## `Window.content_scale_factor` from `video/ui_scale`; returns the factor (1.0 without a window).
static func apply_ui_scale(window: Window, store: AppSettingsStore, overrides: Dictionary = {}) -> float:
	if window == null:
		return 1.0
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	return UiLayout.apply(window, float(int(value(store, &"video/ui_scale", overrides))) / 100.0)


## Accessibility switches, fonts, colour mode, tooltip delay.
static func apply_ui(store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	UiMotion.reduce_motion = bool(value(store, &"access/reduce_motion", overrides))
	UiMotion.reduce_flash = bool(value(store, &"access/reduce_flash", overrides))
	var cvd: bool = str(value(store, &"access/colour_mode", overrides)) == "cvd"
	UiSkinSet.shared().set_colour_mode(UiSkinSet.ColourMode.CVD if cvd else UiSkinSet.ColourMode.NORMAL)
	UiFonts.set_alt_body(int(value(store, &"access/ui_font", overrides)) == 1)
	UiThemeService.set_a11y({"high_contrast": bool(value(store, &"access/high_contrast_hud", overrides)), "cvd": cvd})
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", float(int(value(store, &"ui/tooltip_delay_ms", overrides))) / 1000.0)


# ---------------------------------------------------------------- audio and quality hand-offs

## Every `[audio]` + audio-related `[access]` value (what `SndSettings.load_from` reads).
static func audio_values(store: AppSettingsStore, overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in AppSettingsSchema.entries():
		var id: String = String(row["id"])
		if id.begins_with("audio/") or id == "access/announcer_tts":
			out[id] = value(store, StringName(id), overrides)
	return out


static func apply_audio(store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	if audio_sink.is_valid():
		audio_sink.call(audio_values(store, overrides))


## The `[video]` + `[access]` sections for `ViewQuality.from_settings` (4.7.3): exactly the `[video]` keys present in the
## store (absent = the preset's value), `[access] colour_mode` under the view's names (`cvd` -> `deutan` plus
## `cvd_palette`), `high_contrast_hud`, `reduce_motion`, `reduce_flash`. A scaling mode the renderer cannot honour falls
## back to `bilinear`.
static func quality_config(store: AppSettingsStore, overrides: Dictionary = {}) -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	for row: Dictionary in AppSettingsSchema.entries():
		var id: String = String(row["id"])
		if not id.begins_with("video/"):
			continue
		var explicit: bool = store.is_explicit(StringName(id)) or overrides.has(id)
		if not explicit:
			continue
		var v: Variant = value(store, StringName(id), overrides)
		if id == "video/scaling_mode":
			v = _supported_scaling(str(v))
		if v != null and _quality_key(id):
			cfg.set_value("video", AppSettingsSchema.key_of(id), v)
	var cvd: bool = str(value(store, &"access/colour_mode", overrides)) == "cvd"
	cfg.set_value("access", "colour_mode", "deutan" if cvd else "normal")
	cfg.set_value("access", "cvd_palette", cvd)
	cfg.set_value("access", "high_contrast_hud", bool(value(store, &"access/high_contrast_hud", overrides)))
	cfg.set_value("access", "reduce_motion", bool(value(store, &"access/reduce_motion", overrides)))
	cfg.set_value("access", "reduce_flash", bool(value(store, &"access/reduce_flash", overrides)))
	return cfg


## The view reads no window keys from `[video]`.
static func _quality_key(id: String) -> bool:
	return not (id in ["video/window_mode", "video/resolution", "video/window_pos", "video/monitor", "video/ui_scale",
		"video/vsync", "video/background_fps"])


static func _supported_scaling(mode: String) -> String:
	if mode.begins_with("metalfx") and not AppSettingsSchema.guard_ok(&"metalfx"):
		return "bilinear"
	if mode == "fsr2" and not AppSettingsSchema.guard_ok(&"forward_plus"):
		return "bilinear"
	return mode


static func apply_quality(store: AppSettingsStore, overrides: Dictionary = {}) -> void:
	if quality_sink.is_valid():
		quality_sink.call(quality_config(store, overrides))
