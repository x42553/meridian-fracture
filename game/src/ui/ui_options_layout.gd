class_name UiOptionsLayout
extends RefCounted
## Which settings row sits on which options page (ui.md 5.18.1). The rows come from `AppSettingsSchema`; this table only orders
## and groups them, so a row added to the schema that is not listed here (or in `HIDDEN`) fails `test_ui_options_schema`.
## Section rows are schema ids or `@` pseudo rows the page builders render specially (`@adapter`, `@keys`, `@swatch`, ...).

const PAGES: Array[Dictionary] = [
	{"id": &"graphics", "title": "Graphics"},
	{"id": &"audio", "title": "Audio"},
	{"id": &"controls", "title": "Controls"},
	{"id": &"interface", "title": "Interface"},
	{"id": &"network", "title": "Network"},
	{"id": &"storage", "title": "Storage"},
]

## Schema ids that are state, not options: no row on any page.
const HIDDEN: PackedStringArray = [
	"meta/version", "meta/first_run", "video/window_pos", "video/monitor", "game/last_roster", "game/last_skirmish",
	"game/skirmish_preset", "net/last_address", "net/recent_hosts", "net/help_shown",
]

## Ids whose change can lock a player out and therefore opens the 15-second "Keep these settings?" dialog (5.18.3).
const KEEP_IDS: PackedStringArray = ["video/window_mode", "video/resolution", "video/vsync"]

## The advanced quality foldout of the Graphics page.
const ADVANCED: PackedStringArray = [
	"video/render_scale", "video/scaling_mode", "video/msaa", "video/fxaa", "video/shadow_mode", "video/ssao", "video/ssil",
	"video/glow", "video/decor_density", "video/health_bars", "video/unit_outline", "video/unit_backend", "video/night_maps",
	"video/wide_view",
]


## `[{title, rows: PackedStringArray, foldout: bool}]` of a page id.
static func sections(page: StringName) -> Array[Dictionary]:
	match page:
		&"graphics":
			return [
				_sec("Display", ["@adapter", "video/window_mode", "video/resolution", "video/vsync", "video/fps_cap", "video/background_fps"]),
				_sec("Quality", ["video/quality", "video/look"]),
				_sec("Advanced quality", ADVANCED, true),
				_sec("Renderer", ["video/renderer"]),
			]
		&"audio":
			return [
				_sec("Volume", ["audio/master", "audio/music", "audio/sfx", "audio/ambience", "audio/ui", "audio/voice"]),
				_sec("Voices and music", ["audio/announcer", "audio/unit_voices", "audio/music_mode", "audio/captions"]),
				_sec("Output", ["audio/dynamic_range", "audio/quality", "audio/output_device", "audio/mute_unfocused"]),
			]
		&"controls":
			return [
				_sec("Key bindings", ["@keys"]),
				_sec("Pointer", ["input/double_click_ms", "input/drag_threshold", "input/confine_cursor"]),
				_sec("Behaviour", ["input/sticky_modes", "input/group_double_tap_center", "input/esc_clears_selection", "input/pause_on_menu",
					"input/pause_on_focus_loss", "input/sidebar_hover_hotkeys"]),
				_sec("Orders", ["input/move_speed_match", "input/move_reverse"]),
			]
		&"interface":
			return [
				_sec("Interface", ["video/ui_scale", "ui/sidebar_side", "ui/tooltips", "ui/tooltip_delay_ms", "ui/minimap_sweep", "ui/brackets",
					"ui/range_rings", "ui/camera_pad", "ui/strategic_markers", "ui/chat_fade_s", "ui/chat_opacity", "ui/show_fps", "ui/cursor_style", "game/tips"]),
				_sec("Accessibility", ["access/colour_mode", "@swatch", "access/high_contrast_hud", "access/reduce_motion", "access/reduce_flash",
					"access/ui_font", "access/announcer_tts", "access/cursor_scale"]),
				_sec("Camera", ["input/key_scroll_speed", "input/rotate_speed", "input/zoom_speed", "input/invert_zoom", "input/invert_orbit",
					"input/orbit_mode", "access/edge_scroll_enabled", "access/edge_scroll_speed"]),
				_sec("Language", ["game/language"]),
			]
		&"network":
			return [
				_sec("Player", ["net/player_name", "net/port", "net/discovery", "net/allow_public_discovery"]),
				_sec("Match", ["net/min_input_delay", "net/auto_drop_ms", "net/replay_autosave_count", "net/record_chat", "net/show_net_overlay", "@net_help"]),
			]
		&"storage":
			return [_sec("Disk usage", ["@storage"])]
	return []


static func _sec(title: String, rows: Variant, foldout: bool = false) -> Dictionary:
	return {"title": title, "rows": PackedStringArray(rows), "foldout": foldout}


static func page_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for p: Dictionary in PAGES:
		out.append(p["id"])
	return out


static func title_of(page: StringName) -> String:
	for p: Dictionary in PAGES:
		if p["id"] == page:
			return str(p["title"])
	return ""


static func is_page(page: StringName) -> bool:
	return page_ids().has(page)


## Every real schema id listed on any page (the `@` pseudo rows are dropped), in page order.
static func all_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for pg: StringName in page_ids():
		for sec: Dictionary in sections(pg):
			for id: String in sec["rows"] as PackedStringArray:
				if not id.begins_with("@"):
					out.append(id)
	return out


## The page a schema id lives on, `&""` for hidden or unknown ids.
static func page_of(id: String) -> StringName:
	for pg: StringName in page_ids():
		for sec: Dictionary in sections(pg):
			if (sec["rows"] as PackedStringArray).has(id):
				return pg
	return &""
