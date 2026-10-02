class_name UiSkin
extends RefCounted
## Faction skin: the only faction-dependent inputs of the theme (`style.ui.skins`, ui.md 5.19.2): `accent`
## (borders on hover, tab underline, progress fills, headings, focus rings), `accent2` (badges, small ticks),
## `tint` (dark colour mixed into the panel gradients). Also carries the `chrome` recipe dictionary
## (`ViewStyle.chrome()`, ui.md 5.19.1). With `ui_palette.gd` the only UI file allowed to hold colour literals.

var code: String = "neutral"
var accent: Color = Color("#7fb0e6")
var accent2: Color = Color("#ffd35c")
var tint: Color = Color("#141c26")
## Style recipes (5.19.1); missing keys fall back to `DEFAULT_CHROME`.
var chrome: Dictionary = {}

## The shipped recipes; test U-1 asserts they equal `style.ui.chrome` (a key the JSON lacks falls back to this).
const DEFAULT_CHROME: Dictionary = {
	"grid_px": 4, "panel_cut_px": 10, "button_cut_px": 6, "inset_cut_px": 4, "border_px": 1,
	"bracket_len_px": 12, "bracket_w_px": 2, "glow_alpha": 0.22, "hover_ms": 90, "press_ms": 60,
	"panel_slide_ms": 180, "ease": "cubic_out", "stroke_px": 1.8, "glyph_grid": 24, "min_glyph_px": 16,
	"min_stroke_px": 1.5,
	"panel": {"top_tint_mix": 0.55, "bottom_tint_mix": 0.25, "top_from": "BG_RAISED", "bottom_from": "BG_PANEL",
		"alpha": [0.94, 0.97], "border": "LINE", "cut_px": 10, "sidebar_cut_px": 18, "ribbon_cut_px": 12, "padding_px": [12, 10]},
	"button": {"cut_px": 6, "normal": ["#1F2C3C", "#141E2B"], "hover": ["#2A3F57", "#1A2A3C"],
		"pressed": ["#0D141C", "#182638"], "disabled": ["#0F151C", "#0C1218"],
		"border": {"normal": "LINE", "hover": "accent", "pressed": "accent", "disabled": "LINE_DIM"},
		"label_on_accent": "#10161D", "accent_fill": {"from_lighten": 0.12, "to_darken": 0.42},
		"accent_border_lighten": 0.35, "hero": {"cut_px": 12, "font": "HEAD", "size_px": 20, "alpha": 0.78}},
	"bar": {"inset_cut_px": 3, "fill": {"from_lighten": 0.25, "to_darken": 0.35}, "scroll_padding_px": 3,
		"track_alpha": 0.35, "grabber_darken": 0.35},
	"tooltip": {"alpha": 0.98, "cut_px": 8, "bracket": "top_left"},
	"timing": {"credit_ticker_ms": 300, "alert_pulse_hz": 1.0, "max_animation_hz": 2.0},
}

## Faction codes in `style.faction_order`.
const CODES: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]

## Built-in skins (values of `style.ui.skins`), used when no `ViewStyle` is available.
const _BUILTIN: Dictionary = {
	"napc": ["#F07F2C", "#C9D27A", "#2A2F16"], "nec": ["#5B93E0", "#FFB733", "#14243D"],
	"olm": ["#2FC9BB", "#D9803F", "#0F2B2C"], "def": ["#E0503A", "#F0DC8C", "#341612"],
	"pd": ["#33A0EC", "#FF7F5C", "#0F2740"], "han": ["#33C98A", "#E0424F", "#0F2F22"],
	"ae": ["#26D6E8", "#E0AA3C", "#11292D"], "sap": ["#F3A622", "#7A72E6", "#2C2412"],
}


## Neutral skin (splash, fatal, observers, replays): `#7fb0e6` / `#ffd35c` / `#141c26`.
static func neutral() -> UiSkin:
	var s := UiSkin.new()
	s.chrome = DEFAULT_CHROME.duplicate(true)
	return s


## Built-in skin of a faction code (the values of `style.ui.skins`); unknown code -> `neutral()`.
static func builtin(faction_code: String) -> UiSkin:
	if not _BUILTIN.has(faction_code):
		return neutral()
	var d: Array = _BUILTIN[faction_code]
	var s := UiSkin.new()
	s.code = faction_code
	s.accent = Color(String(d[0]))
	s.accent2 = Color(String(d[1]))
	s.tint = Color(String(d[2]))
	s.chrome = DEFAULT_CHROME.duplicate(true)
	return s


## Skin from a style source (a `ViewStyle`: duck-typed `skin(code)` and `chrome()`), art R-17. `style == null` or
## an unknown code -> `builtin(code)` / `neutral()`. `skin(code)` may return a Dictionary of hex strings / Colors.
static func from_style(style: Object, faction_code: String) -> UiSkin:
	var s: UiSkin = builtin(faction_code)
	if style == null:
		return s
	if style.has_method(&"skin"):
		var entry: Variant = style.call(&"skin", faction_code)
		if entry is Dictionary:
			var d: Dictionary = entry
			if d.has("accent") and d.has("accent2") and d.has("tint"):
				s.code = faction_code
				s.accent = _color_of(d["accent"], s.accent)
				s.accent2 = _color_of(d["accent2"], s.accent2)
				s.tint = _color_of(d["tint"], s.tint)
	if style.has_method(&"chrome"):
		var ch: Variant = style.call(&"chrome")
		if ch is Dictionary and not (ch as Dictionary).is_empty():
			s.chrome = merge_chrome(ch as Dictionary)
	return s


## `DEFAULT_CHROME` with `over` laid on top (recursive), so that a JSON lacking a key still yields a full table.
static func merge_chrome(over: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULT_CHROME.duplicate(true)
	_merge_into(out, over)
	return out


static func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k: Variant in src:
		if dst.get(k) is Dictionary and src[k] is Dictionary:
			_merge_into(dst[k] as Dictionary, src[k] as Dictionary)
		else:
			dst[k] = src[k]


static func _color_of(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v as Color
	if v is String or v is StringName:
		return Color(String(v))
	return fallback


## Stable identity of the look this skin produces (style-box cache key).
func cache_key() -> String:
	return "%s|%s|%s|%s" % [code, accent.to_html(), accent2.to_html(), tint.to_html()]


## Recipe sub-dictionary (`chrome[name]`), never null.
func recipe(section: String) -> Dictionary:
	var v: Variant = chrome.get(section, DEFAULT_CHROME.get(section, {}))
	return v as Dictionary if v is Dictionary else {}


## Panel gradient top stop (`BG_RAISED.lerp(tint, 0.55)`, alpha default 0.94).
func panel_top(alpha: float = -1.0) -> Color:
	var p: Dictionary = recipe("panel")
	var c: Color = UiPalette.token(StringName(String(p.get("top_from", "BG_RAISED")))).lerp(tint, float(p.get("top_tint_mix", 0.55)))
	c.a = alpha if alpha >= 0.0 else float((p.get("alpha", [0.94, 0.97]) as Array)[0])
	return c


## Panel gradient bottom stop (`BG_PANEL.lerp(tint, 0.25)`, alpha default 0.97).
func panel_bottom(alpha: float = -1.0) -> Color:
	var p: Dictionary = recipe("panel")
	var c: Color = UiPalette.token(StringName(String(p.get("bottom_from", "BG_PANEL")))).lerp(tint, float(p.get("bottom_tint_mix", 0.25)))
	c.a = alpha if alpha >= 0.0 else float((p.get("alpha", [0.94, 0.97]) as Array)[1])
	return c
