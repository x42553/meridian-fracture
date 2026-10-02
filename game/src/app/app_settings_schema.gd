class_name AppSettingsSchema
extends RefCounted
## The table of every setting (ui.md 4.8.1): drives validation, persistence and the generated options UI.
## Row: `{id, type, default, min, max, step, choices, apply, restart, guard, label_key, preset, max_len}`.
## `preset` rows are the quality keys whose absence means "the preset's value" (their `default` is null, `get_value`
## returns null while unset). `apply` hook in `video audio input ui quality net misc`. Ids are `section/key`.

enum T { BOOL = 0, INT = 1, FLOAT = 2, CHOICE = 3, STRING = 4, KEYS = 5, VECTOR2I = 6, LIST = 7 }

const SECTION_CONTROLS: String = "controls"
const MIN_WINDOW := Vector2i(1024, 576)
const NAME_MAX: int = 24

static var _entries: Array[Dictionary] = []
static var _index: Dictionary = {}


## All rows in schema (= file) order. The array and its rows are shared: do not modify them.
static func entries() -> Array[Dictionary]:
	_ensure()
	return _entries


## The row of `id`, or `{}` for an unknown id.
static func entry(id: StringName) -> Dictionary:
	_ensure()
	return _index.get(String(id), {}) as Dictionary


static func has(id: StringName) -> bool:
	_ensure()
	return _index.has(String(id))


static func section_of(id: String) -> String:
	var i: int = id.find("/")
	return id.substr(0, i) if i >= 0 else ""


static func key_of(id: String) -> String:
	var i: int = id.find("/")
	return id.substr(i + 1) if i >= 0 else id


## Capability guard (5.18.4): whether the running renderer / platform can honour a row.
static func guard_ok(guard: StringName) -> bool:
	match guard:
		&"", &"none":
			return true
		&"forward_plus", &"fsr2":
			return RenderingServer.get_current_rendering_method() == "forward_plus"
		&"not_compat":
			return RenderingServer.get_current_rendering_method() != "gl_compatibility"
		&"metalfx":
			return RenderingServer.get_current_rendering_driver_name() == "metal"
		&"windowed_only":
			return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
		&"renderer_switch":
			return AppRelaunch.supported()
		&"tts":
			return not DisplayServer.tts_get_voices_for_language("en").is_empty()
		&"font_alt":
			return FileAccess.file_exists(UiFonts.PATH_ALT)
	return true


## A default value copy safe to hand out (Arrays / Dictionaries are duplicated).
static func default_of(row: Dictionary) -> Variant:
	var d: Variant = row.get("default")
	if d is Array or d is Dictionary or d is PackedStringArray:
		return d.duplicate()
	return d


static func _ensure() -> void:
	if not _entries.is_empty():
		return
	_build()
	for row: Dictionary in _entries:
		_index[String(row["id"])] = row


static func _row(id: String, type: int, def: Variant, apply: StringName, extra: Dictionary = {}) -> void:
	var r: Dictionary = {
		"id": id, "type": type, "default": def, "min": null, "max": null, "step": 1, "choices": [] as Array[Dictionary],
		"apply": apply, "restart": false, "guard": &"", "label_key": StringName("opt." + id.replace("/", ".")),
		"preset": false, "max_len": 0,
	}
	for k: String in extra:
		r[k] = extra[k]
	_entries.append(r)


static func _choices(values: Array, id: String, guards: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Variant in values:
		var label: String = String(v) if v is String else str(v)
		out.append({"value": v, "label_key": StringName("opt.%s.%s" % [id.replace("/", "."), label if not label.is_empty() else "default"]),
			"guard": guards.get(v, &"")})
	return out


static func _bool(id: String, def: bool, apply: StringName) -> void:
	_row(id, T.BOOL, def, apply)


static func _int(id: String, def: int, lo: int, hi: int, apply: StringName, step: int = 1) -> void:
	_row(id, T.INT, def, apply, {"min": lo, "max": hi, "step": step})


static func _choice(id: String, def: Variant, values: Array, apply: StringName, extra: Dictionary = {}) -> void:
	var e: Dictionary = {"choices": _choices(values, id, extra.get("choice_guards", {}) as Dictionary)}
	for k: String in extra:
		if k != "choice_guards":
			e[k] = extra[k]
	_row(id, T.CHOICE, def, apply, e)


static func _str(id: String, def: String, apply: StringName, max_len: int = 0) -> void:
	_row(id, T.STRING, def, apply, {"max_len": max_len})


static func _build() -> void:
	_row("meta/version", T.INT, 1, &"misc")
	_bool("meta/first_run", true, &"misc")
	# ---- video
	_choice("video/window_mode", 0, [0, 1, 2], &"video")
	_row("video/resolution", T.VECTOR2I, Vector2i(1600, 900), &"video", {"min": MIN_WINDOW})
	_row("video/window_pos", T.VECTOR2I, Vector2i(-1, -1), &"video")
	_int("video/monitor", -1, -1, 16, &"video")
	_int("video/ui_scale", 100, 75, 200, &"ui", 5)
	_choice("video/vsync", 1, [0, 1, 2, 3], &"video")
	_choice("video/fps_cap", 0, [0, 30, 60, 90, 120, 144, 165, 240], &"video")
	_int("video/background_fps", 30, 0, 240, &"video")
	# quality keys (ViewQuality reads these exact names); `preset` rows are absent = the preset's value
	# default = the view's own first-run recommendation, so "absent" means the same for the store and for ViewQuality
	_choice("video/quality", AppGraphics.recommend(), [0, 1, 2, 3, 4], &"quality")
	_row("video/render_scale", T.FLOAT, null, &"quality", {"min": 0.5, "max": 1.0, "step": 0.05, "preset": true})
	_choice("video/scaling_mode", null, ["bilinear", "fsr1", "fsr2", "metalfx_spatial", "metalfx_temporal"], &"quality",
		{"preset": true, "choice_guards": {"fsr2": &"forward_plus", "metalfx_spatial": &"metalfx", "metalfx_temporal": &"metalfx"}})
	_choice("video/msaa", null, [0, 1, 2, 3], &"quality", {"preset": true})
	_row("video/fxaa", T.BOOL, null, &"quality", {"preset": true, "guard": &"not_compat"})
	_choice("video/shadow_mode", null, ["blob", "cascades2", "cascades4"], &"quality", {"preset": true})
	_choice("video/ssao", null, ["off", "low_half", "medium_half", "high_full"], &"quality", {"preset": true, "guard": &"forward_plus"})
	_row("video/ssil", T.BOOL, null, &"quality", {"preset": true, "guard": &"forward_plus"})
	_row("video/glow", T.BOOL, null, &"quality", {"preset": true})
	_row("video/decor_density", T.FLOAT, null, &"quality", {"min": 0.0, "max": 1.0, "step": 0.05, "preset": true})
	_choice("video/health_bars", 2, [0, 1, 2, 3], &"quality")
	_choice("video/unit_outline", 1, [0, 1, 2], &"quality")
	_choice("video/unit_backend", -1, [-1, 0, 1], &"quality")
	_bool("video/night_maps", true, &"quality")
	_choice("video/look", "auto", ["auto", "temperate_day", "arid_dusk", "arctic_day", "tropical_day", "urban_night"], &"quality")
	_bool("video/wide_view", false, &"quality")
	_choice("video/renderer", "", ["", "forward_plus", "mobile", "gl_compatibility"], &"video", {"restart": true, "guard": &"renderer_switch"})
	# ---- audio
	_int("audio/master", 100, 0, 100, &"audio")
	_int("audio/music", 70, 0, 100, &"audio")
	_int("audio/sfx", 90, 0, 100, &"audio")
	_int("audio/voice", 100, 0, 100, &"audio")
	_int("audio/ui", 80, 0, 100, &"audio")
	_int("audio/ambience", 70, 0, 100, &"audio")
	_choice("audio/announcer", 0, [0, 1, 2], &"audio")
	_choice("audio/unit_voices", 0, [0, 1, 2, 3], &"audio")
	_choice("audio/music_mode", 0, [0, 1, 2], &"audio")
	_choice("audio/dynamic_range", 0, [0, 1], &"audio")
	_choice("audio/quality", 1, [0, 1, 2], &"audio")
	_bool("audio/mute_unfocused", true, &"audio")
	_str("audio/output_device", "Default", &"audio")
	_bool("audio/captions", true, &"ui")
	# ---- access
	_choice("access/colour_mode", "normal", ["normal", "cvd"], &"ui")
	_bool("access/reduce_motion", false, &"ui")
	_bool("access/reduce_flash", false, &"ui")
	_bool("access/high_contrast_hud", false, &"ui")
	_choice("access/ui_font", 0, [0, 1], &"ui", {"guard": &"font_alt"})
	_row("access/announcer_tts", T.BOOL, false, &"audio", {"guard": &"tts"})
	_choice("access/cursor_scale", 100, [100, 150, 200], &"ui")
	_bool("access/edge_scroll_enabled", true, &"input")
	_int("access/edge_scroll_speed", 100, 25, 200, &"input")
	# ---- input
	_choice("input/confine_cursor", 1, [0, 1, 2], &"input")
	_int("input/key_scroll_speed", 100, 25, 200, &"input")
	_int("input/rotate_speed", 100, 25, 200, &"input")
	_int("input/zoom_speed", 100, 25, 200, &"input")
	_bool("input/invert_zoom", false, &"input")
	_bool("input/invert_orbit", false, &"input")
	_choice("input/orbit_mode", 0, [0, 1], &"input")
	_int("input/double_click_ms", 350, 200, 600, &"input")
	_int("input/drag_threshold", 6, 3, 16, &"input")
	_bool("input/sidebar_hover_hotkeys", false, &"input")
	_bool("input/group_double_tap_center", true, &"input")
	_bool("input/sticky_modes", false, &"input")
	_bool("input/move_speed_match", false, &"input")
	_bool("input/move_reverse", false, &"input")
	_bool("input/esc_clears_selection", false, &"input")
	_bool("input/pause_on_menu", true, &"input")
	_bool("input/pause_on_focus_loss", true, &"input")
	# ---- ui
	_choice("ui/sidebar_side", 0, [0, 1], &"ui")
	_bool("ui/minimap_sweep", true, &"ui")
	_bool("ui/tooltips", true, &"ui")
	_int("ui/tooltip_delay_ms", 500, 0, 1500, &"ui")
	_int("ui/chat_fade_s", 8, 3, 30, &"ui")
	_int("ui/chat_opacity", 85, 20, 100, &"ui")
	_bool("ui/show_fps", false, &"ui")
	_choice("ui/cursor_style", 0, [0, 1], &"ui")
	_bool("ui/brackets", true, &"ui")
	_choice("ui/range_rings", 0, [0, 1, 2], &"ui")
	_bool("ui/camera_pad", true, &"ui")
	_bool("ui/strategic_markers", true, &"ui")
	# ---- game
	_str("game/language", "en", &"misc")
	_str("game/last_roster", "roster.napc.vanilla", &"misc")
	_str("game/last_skirmish", "", &"misc")
	_str("game/skirmish_preset", "", &"misc")
	_bool("game/tips", true, &"misc")
	# ---- net
	_row("net/player_name", T.STRING, AppProfile.default_name(), &"net", {"max_len": NAME_MAX})
	_int("net/port", 27615, 1024, 65535, &"net")
	_str("net/last_address", "", &"net")
	_row("net/recent_hosts", T.LIST, PackedStringArray(), &"net", {"max": 8})
	_bool("net/discovery", true, &"net")
	_bool("net/allow_public_discovery", false, &"net")
	_int("net/min_input_delay", 2, 1, 4, &"net")
	_choice("net/auto_drop_ms", 60000, [0, 30000, 60000, 120000], &"net")
	_int("net/replay_autosave_count", 3, 1, 10, &"net")
	_bool("net/record_chat", true, &"net")
	_bool("net/show_net_overlay", false, &"net")
	_bool("net/help_shown", false, &"net")
