class_name UiOptionsText
extends RefCounted
## English strings of the options pages (ui.md 5.18; `UiText` does not exist yet, so the table lives here and is the one place a
## translation would replace). `label(id)`, `tip(id)`, `choice(id, value)`, `unit(id)` and `value_text(row, value)` are pure.

## `id -> [label, tooltip]`.
const ROWS: Dictionary = {
	"video/window_mode": ["Window mode", "Windowed, borderless fullscreen or exclusive fullscreen."],
	"video/resolution": ["Resolution", "Window size in pixels. Only used in windowed mode."],
	"video/vsync": ["Vertical sync", "Waits for the display refresh. Adaptive tears instead of stuttering when the frame rate drops."],
	"video/fps_cap": ["Frame rate cap", "Upper limit of the frame rate. Off lets the GPU run as fast as it can."],
	"video/background_fps": ["Background frame rate", "Frame rate while the window is not focused. 0 keeps the normal cap."],
	"video/quality": ["Graphics preset", "Low, Medium, High and Ultra set every quality key at once. Auto adapts to your frame rate."],
	"video/render_scale": ["Render scale", "Renders the 3D world at a fraction of the window size and scales it up."],
	"video/scaling_mode": ["Upscaling", "How the reduced render scale is scaled up. FSR 2 needs Forward+, MetalFX needs the Metal driver."],
	"video/msaa": ["Anti-aliasing (MSAA)", "Smooths polygon edges. Costs GPU time."],
	"video/fxaa": ["Anti-aliasing (FXAA)", "Cheap post-process edge smoothing."],
	"video/shadow_mode": ["Shadows", "Blob shadows are cheapest, cascades draw real shadows of every unit."],
	"video/ssao": ["Ambient occlusion", "Darkens creases and contact points. Forward+ only."],
	"video/ssil": ["Indirect lighting", "Screen-space bounce light. Forward+ only."],
	"video/glow": ["Bloom", "Soft glow around bright lights and effects."],
	"video/decor_density": ["Decoration density", "How many rocks, trees and props the terrain scatters."],
	"video/health_bars": ["Health bars", "When health bars are drawn over units and structures."],
	"video/unit_outline": ["Unit outline", "Draws a dark or bold outline around units to separate them from the ground."],
	"video/unit_backend": ["Unit rendering", "Auto picks the fastest unit renderer for your GPU."],
	"video/night_maps": ["Night maps", "Allows maps with a night lighting mood."],
	"video/look": ["Environment look", "Lighting and colour grading of the battlefield. Automatic picks a look from the map seed (city maps are night maps)."],
	"video/wide_view": ["Wide camera view", "Lets the camera zoom out further."],
	"video/renderer": ["Renderer", "Changing the renderer restarts the game."],
	"audio/master": ["Master volume", ""],
	"audio/music": ["Music", ""],
	"audio/sfx": ["Effects", "Weapons, explosions and machinery."],
	"audio/ambience": ["Ambience", "Wind, water and environment sounds."],
	"audio/ui": ["Interface", "Button and notification sounds."],
	"audio/voice": ["Voice", "Announcer and unit acknowledgements."],
	"audio/announcer": ["Announcer", "Who reads out alerts such as \"Base under attack\"."],
	"audio/unit_voices": ["Unit responses", "What units say when selected and ordered."],
	"audio/music_mode": ["Music mode", "Dynamic follows the battle, calm plays quiet tracks only."],
	"audio/dynamic_range": ["Dynamic range", "Night mode compresses loud explosions for late sessions."],
	"audio/quality": ["Audio quality", "Higher quality uses more CPU for mixing."],
	"audio/mute_unfocused": ["Mute when unfocused", "Silences the game while another window has the focus."],
	"audio/output_device": ["Output device", "The device sound is played on."],
	"audio/captions": ["Captions", "Shows spoken alerts as text in the message feed."],
	"video/ui_scale": ["Interface scale", "Scales text and controls from 75 to 200 percent."],
	"ui/sidebar_side": ["Sidebar side", "Which edge of the screen the build sidebar sits on."],
	"ui/tooltips": ["Tooltips", "Shows a help text when you rest the pointer on a control."],
	"ui/tooltip_delay_ms": ["Tooltip delay", "How long the pointer rests before a tooltip appears."],
	"ui/minimap_sweep": ["Minimap sweep", "Animated radar sweep on the minimap."],
	"ui/brackets": ["Selection brackets", "Corner brackets around selected units."],
	"ui/range_rings": ["Range rings", "Weapon range circles: never, for the selection, or always on hover."],
	"ui/camera_pad": ["On-screen camera pad", "Buttons for moving and rotating the camera with the mouse alone."],
	"ui/strategic_markers": ["Zoomed-out markers", "Icons that replace units when the camera is far away."],
	"ui/chat_fade_s": ["Chat fade time", "Seconds until a chat line disappears from the screen."],
	"ui/chat_opacity": ["Chat opacity", ""],
	"ui/show_fps": ["Show frame rate", "Displays a small frame counter in the corner."],
	"ui/cursor_style": ["Cursor style", "Game cursors are drawn by the game, system cursors come from your operating system."],
	"game/tips": ["Loading tips", "Shows a gameplay hint on the loading screen."],
	"game/language": ["Language", "More languages are planned."],
	"access/colour_mode": ["Colour palette", "The colour-vision safe palette separates the eight team colours for red-green and blue-yellow colour blindness."],
	"access/high_contrast_hud": ["High-contrast interface", "Solid panels, bright borders and heavier world outlines."],
	"access/reduce_motion": ["Reduce motion", "Removes sweeps, slides and camera smoothing, and softens shakes."],
	"access/reduce_flash": ["Reduce flashes", "Replaces pulses and flash overlays with steady colours."],
	"access/ui_font": ["Interface font", "The dyslexia-friendly font replaces the body text font."],
	"access/announcer_tts": ["Speak alerts with the system voice", "Uses your operating system's text-to-speech voice for announcer captions."],
	"access/cursor_scale": ["Cursor size", "Size of the game cursors."],
	"input/key_scroll_speed": ["Keyboard scroll speed", "Camera speed when panning with the keyboard."],
	"input/rotate_speed": ["Rotation speed", "Camera rotation speed."],
	"input/zoom_speed": ["Zoom speed", "Camera zoom speed."],
	"input/invert_zoom": ["Invert zoom", "Scroll up to zoom out."],
	"input/invert_orbit": ["Invert orbit", "Reverses the direction of mouse orbiting."],
	"input/orbit_mode": ["Orbit control", "Hold the orbit button, or press it once to toggle orbiting."],
	"access/edge_scroll_enabled": ["Edge scrolling", "Moves the camera when the pointer touches the window edge."],
	"access/edge_scroll_speed": ["Edge scroll speed", ""],
	"input/double_click_ms": ["Double-click time", "Maximum time between two clicks that count as a double click."],
	"input/drag_threshold": ["Drag threshold", "Pixels the pointer must move before a click becomes a drag."],
	"input/confine_cursor": ["Cursor confinement", "Keeps the pointer inside the window: always, only in a match, or never."],
	"input/sticky_modes": ["Sticky order modes", "Attack-move, guard and similar modes stay armed after an order."],
	"input/group_double_tap_center": ["Double-tap group centres camera", "Pressing a group number twice moves the camera to the group."],
	"input/esc_clears_selection": ["Escape clears the selection", ""],
	"input/pause_on_menu": ["Pause when the menu is open", "Single-player matches pause while the game menu is open."],
	"input/pause_on_focus_loss": ["Pause when the window loses focus", "Single-player matches pause in the background."],
	"input/sidebar_hover_hotkeys": ["Sidebar hover hotkeys", "Build card hotkeys act on the card under the pointer."],
	"input/move_speed_match": ["Match speed of grouped units", "A selection moving together travels at the speed of its slowest unit."],
	"input/move_reverse": ["Reverse on short moves", "Vehicles back up instead of turning around for short orders."],
	"net/player_name": ["Commander name", "Shown to other players in the lobby and in the match."],
	"net/port": ["Network port", "UDP and TCP port used for hosting a LAN game."],
	"net/discovery": ["Announce and find LAN games", "Lets computers on the same network see your hosted game."],
	"net/allow_public_discovery": ["Allow public networks", "Also announces on networks Windows marks as public."],
	"net/min_input_delay": ["Minimum input delay", "Turns of delay added to every command. Higher is smoother on slow networks."],
	"net/auto_drop_ms": ["Drop silent players after", "A player who stops responding is removed after this time."],
	"net/replay_autosave_count": ["Replays kept", "How many automatic replays are stored."],
	"net/record_chat": ["Record chat in replays", ""],
	"net/show_net_overlay": ["Network overlay", "Shows latency and turn information in a match."],
}

## `id -> {value: label}` for choices whose value does not read well as text.
const CHOICES: Dictionary = {
	"video/window_mode": {0: "Windowed", 1: "Borderless fullscreen", 2: "Exclusive fullscreen"},
	"video/vsync": {0: "Off", 1: "On", 2: "Adaptive", 3: "Mailbox"},
	"video/fps_cap": {0: "Off", 30: "30", 60: "60", 90: "90", 120: "120", 144: "144", 165: "165", 240: "240"},
	"video/quality": {0: "Low", 1: "Medium", 2: "High", 3: "Ultra", 4: "Auto"},
	"video/scaling_mode": {"bilinear": "Bilinear", "fsr1": "FSR 1", "fsr2": "FSR 2", "metalfx_spatial": "MetalFX spatial", "metalfx_temporal": "MetalFX temporal"},
	"video/msaa": {0: "Off", 1: "2x", 2: "4x", 3: "8x"},
	"video/shadow_mode": {"blob": "Blob shadows", "cascades2": "2 cascades", "cascades4": "4 cascades"},
	"video/ssao": {"off": "Off", "low_half": "Low", "medium_half": "Medium", "high_full": "High"},
	"video/health_bars": {0: "Never", 1: "Selected", 2: "Damaged", 3: "Always"},
	"video/unit_outline": {0: "Off", 1: "Normal", 2: "Bold"},
	"video/look": {"auto": "Automatic", "temperate_day": "Temperate day", "arid_dusk": "Arid dusk", "arctic_day": "Arctic day", "tropical_day": "Tropical day", "urban_night": "City night"},
	"video/unit_backend": {-1: "Automatic", 0: "Instanced", 1: "Individual"},
	"video/renderer": {"": "Current", "forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility"},
	"audio/announcer": {0: "Faction voice", 1: "Computer", 2: "Off"},
	"audio/unit_voices": {0: "Voices", 1: "Bleeps", 2: "Mixed", 3: "Off"},
	"audio/music_mode": {0: "Dynamic", 1: "Calm only", 2: "Off"},
	"audio/dynamic_range": {0: "Full", 1: "Night"},
	"audio/quality": {0: "Low", 1: "Normal", 2: "High"},
	"access/colour_mode": {"normal": "Standard", "cvd": "Colour-vision safe"},
	"access/ui_font": {0: "Default", 1: "Dyslexia-friendly"},
	"access/cursor_scale": {100: "Normal", 150: "Large", 200: "Extra large"},
	"ui/sidebar_side": {0: "Right", 1: "Left"},
	"ui/cursor_style": {0: "Game cursors", 1: "System cursors"},
	"ui/range_rings": {0: "Selection", 1: "Never", 2: "Always"},
	"input/confine_cursor": {0: "Never", 1: "In a match", 2: "Always"},
	"input/orbit_mode": {0: "Hold", 1: "Toggle"},
	"net/auto_drop_ms": {0: "Never", 30000: "30 seconds", 60000: "1 minute", 120000: "2 minutes"},
	"game/language": {"en": "English"},
}

## Suffix of a numeric value in the slider's value label.
const UNITS: Dictionary = {
	"video/ui_scale": "%", "audio/master": "%", "audio/music": "%", "audio/sfx": "%", "audio/ambience": "%", "audio/ui": "%",
	"audio/voice": "%", "video/render_scale": "%", "video/decor_density": "%", "ui/tooltip_delay_ms": " ms", "ui/chat_fade_s": " s",
	"ui/chat_opacity": "%", "input/key_scroll_speed": "%", "input/rotate_speed": "%", "input/zoom_speed": "%",
	"access/edge_scroll_speed": "%", "input/double_click_ms": " ms", "input/drag_threshold": " px", "video/background_fps": " fps",
}
## Float rows shown as percent (0.5 -> 50 %).
const FRACTIONS: PackedStringArray = ["video/render_scale", "video/decor_density"]


static func label(id: String) -> String:
	var r: Variant = ROWS.get(id)
	return str((r as Array)[0]) if r != null else UiFmText.humanize(id.get_slice("/", 1))


static func tip(id: String) -> String:
	var r: Variant = ROWS.get(id)
	return str((r as Array)[1]) if r != null else ""


## Text of one choice value.
static func choice(id: String, value: Variant) -> String:
	var table: Variant = CHOICES.get(id)
	if table != null and (table as Dictionary).has(value):
		return str((table as Dictionary)[value])
	return UiFmText.humanize(str(value)) if str(value) != "" else "Default"


static func unit(id: String) -> String:
	return str(UNITS.get(id, ""))


## Display text of a numeric value ("70 %", "500 ms", "85 %" for a 0.85 fraction).
static func value_text(id: String, value: Variant) -> String:
	if FRACTIONS.has(id):
		return "%d%%" % roundi(float(value) * 100.0)
	if value is float:
		return "%s%s" % [String.num(float(value), 2), unit(id)]
	return "%s%s" % [str(value), unit(id)]


## Why a choice / row is disabled (tooltip), by capability guard (5.18.4).
static func guard_reason(guard: StringName) -> String:
	match guard:
		&"forward_plus", &"fsr2":
			return "Forward+ renderer only."
		&"not_compat":
			return "Not available on the Compatibility renderer."
		&"metalfx":
			return "Metal driver only."
		&"windowed_only":
			return "Only in windowed mode."
		&"renderer_switch":
			return "Switching the renderer is not supported here."
		&"tts":
			return "No text-to-speech voice for English is installed."
		&"font_alt":
			return "The dyslexia-friendly font is not installed."
	return "Not available on this system."
