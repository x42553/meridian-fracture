class_name UiTheme
extends RefCounted
## Builds THE game theme from a `UiSkin` (ui.md 5.19.1, 4.6.3): labels, panels, buttons, inputs, bars, scrollbars,
## sliders, popups and tooltips, plus the type variations of 4.6.3. One `Theme`, assigned to every `UiLayerRoot`
## (Window.theme is not inherited below a CanvasLayer, P1). Style boxes are `UiStyleBox` instances shared through
## `UiStyleBox.cached` (one per recipe, state, skin and accessibility options).
## `a11y` options: `{high_contrast: bool, cvd: bool}` (panels alpha 1, no glow, borders LINE_BRIGHT 2 px, TEXT_MUTE
## promoted to TEXT_DIM; semantic colours of the colour-vision-safe set).
## Widgets read skin colours from the theme type `ACCENT_TYPE` (`accent`, `accent2`, `tint`, `ok`, `warn`, `danger`, `power`).

const ACCENT_TYPE: StringName = &"Ui"
const BUTTON_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled"]


# --- effective recipes ---

## The effective chrome recipe table of a skin (`style.ui.chrome` over the built-in defaults); test U-1 compares it to the JSON.
static func chrome(skin: UiSkin) -> Dictionary:
	return skin.chrome if not skin.chrome.is_empty() else UiSkin.DEFAULT_CHROME


static func _a11y_key(a11y: Dictionary) -> String:
	return "%d%d" % [1 if a11y.get("high_contrast", false) else 0, 1 if a11y.get("cvd", false) else 0]


static func _hc(a11y: Dictionary) -> bool:
	return bool(a11y.get("high_contrast", false))


## Shared style box for (recipe, state, skin, a11y). Recipes: panel sidebar ribbon inset tooltip popup popup_hover
## button primary hero danger tab ghost command focus focus_input input bar_bg bar_fill scroll_track grabber
## slider_track slider_fill.
static func box(skin: UiSkin, recipe: StringName, state: StringName = &"normal", a11y: Dictionary = {}) -> UiStyleBox:
	var key: String = "%s|%s|%s|%s" % [skin.cache_key(), recipe, state, _a11y_key(a11y)]
	return UiStyleBox.cached(key, func() -> UiStyleBox: return _build_box(skin, recipe, state, a11y))


static func _border_of(skin: UiSkin, name_or_token: String) -> Color:
	if name_or_token == "accent":
		return skin.accent
	return UiPalette.token(StringName(name_or_token))


static func _build_box(skin: UiSkin, recipe: StringName, state: StringName, a11y: Dictionary) -> UiStyleBox:
	var ch: Dictionary = chrome(skin)
	var hc: bool = _hc(a11y)
	var s := UiStyleBox.new()
	var bw: float = 2.0 if hc else float(ch.get("border_px", 1))
	var pn: Dictionary = skin.recipe("panel")
	var pad: Array = pn.get("padding_px", [12, 10])
	var bt: Dictionary = skin.recipe("button")
	var bracket_len: float = float(ch.get("bracket_len_px", 12))
	var bracket_w: float = float(ch.get("bracket_w_px", 2))
	s.bracket_len = bracket_len
	s.bracket_width = bracket_w
	match recipe:
		&"panel", &"sidebar", &"ribbon", &"tooltip", &"popup":
			var alpha_a: float = float((pn.get("alpha", [0.94, 0.97]) as Array)[0])
			var alpha_b: float = float((pn.get("alpha", [0.94, 0.97]) as Array)[1])
			var cut: float = float(pn.get("cut_px", 10))
			s.cuts = Vector4(cut, 0.0, cut, 0.0)
			s.border_color = UiPalette.LINE_BRIGHT if hc else _border_of(skin, String(pn.get("border", "LINE")))
			s.border_width = bw
			s.bracket_color = skin.accent
			s.bracket_mask = 5
			s.set_padding(float(pad[0]), float(pad[1]), float(pad[0]), float(pad[1]))
			var top: Color = skin.panel_top(1.0 if hc else alpha_a)
			var bot: Color = skin.panel_bottom(1.0 if hc else alpha_b)
			match recipe:
				&"sidebar":
					top = skin.panel_top(1.0 if hc else 0.97)
					bot = skin.panel_bottom(1.0 if hc else 0.97)
					s.cuts = Vector4(0.0, 0.0, 0.0, float(pn.get("sidebar_cut_px", 18)))
					s.bracket_mask = 8
					s.set_padding(14.0, 12.0, 14.0, 12.0)
				&"ribbon":
					top = skin.panel_top(1.0 if hc else 0.92)
					bot = skin.panel_bottom(1.0 if hc else 0.92)
					var rc: float = float(pn.get("ribbon_cut_px", 12))
					s.cuts = Vector4(rc, rc, rc, rc)
					s.bracket_mask = 0
					s.set_padding(20.0, 6.0, 20.0, 6.0)
				&"tooltip":
					var tp: Dictionary = skin.recipe("tooltip")
					var a: float = float(tp.get("alpha", 0.98))
					top = skin.panel_top(a)
					bot = skin.panel_bottom(a)
					var tc: float = float(tp.get("cut_px", 8))
					s.cuts = Vector4(tc, 0.0, tc, 0.0)
					s.bracket_mask = 1
					s.glow = Color(0.0, 0.0, 0.0, 0.5)
					s.set_padding(12.0, 8.0, 12.0, 8.0)
				&"popup":
					top = skin.panel_top(0.98)
					bot = skin.panel_bottom(0.98)
					s.cuts = Vector4(6.0, 0.0, 6.0, 0.0)
					s.bracket_mask = 0
					s.set_padding(6.0, 6.0, 6.0, 6.0)
			s.fill_top = top
			s.fill_bottom = bot
		&"inset", &"input", &"bar_bg":
			var ic: float = float(ch.get("inset_cut_px", 4))
			s.cuts = Vector4(ic, 0.0, ic, 0.0)
			s.fill_top = UiPalette.BG_DEEP.lerp(skin.tint, 0.2)
			s.fill_bottom = UiPalette.BG_PANEL.lerp(skin.tint, 0.1)
			s.border_color = UiPalette.LINE_BRIGHT if hc else UiPalette.LINE_DIM
			s.border_width = bw
			s.highlight = 0.0
			s.set_padding(8.0, 6.0, 8.0, 6.0)
			if recipe == &"input":
				s.set_padding(10.0, 6.0, 10.0, 6.0)
				if state == &"focus":
					s.border_color = skin.accent
					s.glow = Color(skin.accent, 0.2)
			elif recipe == &"bar_bg":
				var bc: float = float((skin.recipe("bar")).get("inset_cut_px", 3))
				s.cuts = Vector4(bc, 0.0, bc, 0.0)
				s.set_padding(0.0, 0.0, 0.0, 0.0)
		&"button", &"command", &"hero", &"tab", &"ghost", &"primary", &"danger":
			_button_box(s, skin, recipe, state, a11y, bt)
		&"focus":
			s.fill_top = Color(0.0, 0.0, 0.0, 0.0)
			s.fill_bottom = Color(0.0, 0.0, 0.0, 0.0)
			s.border_color = skin.accent
			s.border_width = 2.0
			s.highlight = 0.0
			s.glow = Color(skin.accent, 0.2)
			var fc: float = float(state == &"hero") * 12.0 + float(state != &"hero") * float(bt.get("cut_px", 6))
			s.cuts = Vector4(fc, 0.0, fc, 0.0)
		&"popup_hover":
			s.fill_top = Color(skin.accent, 0.28)
			s.fill_bottom = Color(skin.accent, 0.14)
			s.border_color = Color(skin.accent, 0.7)
			s.highlight = 0.0
			s.set_padding(8.0, 4.0, 8.0, 4.0)
		&"bar_fill":
			var bf: Dictionary = skin.recipe("bar").get("fill", {})
			s.fill_top = skin.accent.lightened(float(bf.get("from_lighten", 0.25)))
			s.fill_bottom = skin.accent.darkened(float(bf.get("to_darken", 0.35)))
			s.border_width = 0.0
			s.highlight = 0.0
			var fcut: float = float((skin.recipe("bar")).get("inset_cut_px", 3))
			s.cuts = Vector4(fcut, 0.0, fcut, 0.0)
		&"scroll_track":
			var ta: float = float(skin.recipe("bar").get("track_alpha", 0.35))
			s.fill_top = Color(0.0, 0.0, 0.0, ta)
			s.fill_bottom = Color(0.0, 0.0, 0.0, ta)
			s.border_width = 0.0
			s.highlight = 0.0
			var sp: float = float(skin.recipe("bar").get("scroll_padding_px", 3))
			s.set_padding(sp, sp, sp, sp)
		&"grabber":
			var gd: float = float(skin.recipe("bar").get("grabber_darken", 0.35))
			var a2: Color = skin.accent
			if state == &"normal":
				a2 = skin.accent.darkened(gd)
			s.fill_top = a2
			s.fill_bottom = a2.darkened(0.25)
			s.border_width = 0.0
			s.highlight = 0.0
			var gp: float = float(skin.recipe("bar").get("scroll_padding_px", 3))
			s.set_padding(gp, gp, gp, gp)
		&"slider_track":
			s.fill_top = UiPalette.BG_DEEP
			s.fill_bottom = UiPalette.BG_DEEP
			s.border_color = UiPalette.LINE_BRIGHT if hc else UiPalette.LINE_DIM
			s.border_width = bw
			s.highlight = 0.0
			s.set_padding(0.0, 3.0, 0.0, 3.0)
		&"slider_fill":
			s.fill_top = skin.accent.darkened(0.2)
			s.fill_bottom = skin.accent.darkened(0.5)
			s.border_width = 0.0
			s.highlight = 0.0
			s.set_padding(0.0, 3.0, 0.0, 3.0)
		_:
			Log.error("ui", "UiTheme.box: unknown recipe '%s'" % recipe)
	return s


static func _button_box(s: UiStyleBox, skin: UiSkin, recipe: StringName, state: StringName, a11y: Dictionary, bt: Dictionary) -> void:
	var hc: bool = _hc(a11y)
	var cut: float = float(bt.get("cut_px", 6))
	var glow_a: float = 0.0 if hc else float(skin.chrome.get("glow_alpha", 0.22))
	var st: String = String(state)
	var pair: Array = bt.get(st, bt.get("normal", ["#1F2C3C", "#141E2B"])) as Array
	s.fill_top = Color(String(pair[0]))
	s.fill_bottom = Color(String(pair[1]))
	var border_map: Dictionary = bt.get("border", {})
	s.border_color = _border_of(skin, String(border_map.get(st, "LINE")))
	s.border_width = 2.0 if hc else float(skin.chrome.get("border_px", 1))
	if hc and state == &"normal":
		s.border_color = UiPalette.LINE_BRIGHT
	s.cuts = Vector4(cut, 0.0, cut, 0.0)
	s.set_padding(14.0, 6.0, 14.0, 6.0)
	if state == &"hover":
		s.glow = Color(skin.accent, glow_a)
	elif state == &"pressed" or state == &"disabled":
		s.highlight = 0.0
	match recipe:
		&"primary", &"danger":
			var base: Color = skin.accent if recipe == &"primary" else UiPalette.semantic_for(&"danger", bool(a11y.get("cvd", false)))
			var af: Dictionary = bt.get("accent_fill", {})
			var top: Color = base.lightened(float(af.get("from_lighten", 0.12)))
			var bot: Color = base.darkened(float(af.get("to_darken", 0.42)))
			s.cuts = Vector4(8.0, 0.0, 8.0, 0.0)
			match state:
				&"hover":
					top = top.lightened(0.15)
					bot = bot.lightened(0.15)
					s.glow = Color(base, 0.0 if hc else 0.35)
				&"pressed":
					top = bot
					bot = base.darkened(0.6)
				&"disabled":
					top = UiPalette.BG_CONTROL
					bot = UiPalette.BG_PANEL
			s.fill_top = top
			s.fill_bottom = bot
			if state != &"disabled":
				s.border_color = base.lightened(float(bt.get("accent_border_lighten", 0.35)))
		&"hero":
			var hero: Dictionary = bt.get("hero", {})
			var a: float = float(hero.get("alpha", 0.78))
			s.fill_top.a = a
			s.fill_bottom.a = a
			var hcut: float = float(hero.get("cut_px", 12))
			s.cuts = Vector4(hcut, 0.0, hcut, 0.0)
			s.set_padding(28.0, 12.0, 28.0, 12.0)
		&"command":
			s.set_padding(4.0, 4.0, 4.0, 4.0)
		&"tab":
			s.cuts = Vector4.ZERO
			s.set_padding(10.0, 4.0, 10.0, 4.0)
			if state == &"normal":
				s.fill_top = Color(UiPalette.BG_PANEL, 0.6)
				s.fill_bottom = Color(UiPalette.BG_PANEL, 0.6)
				s.border_color = UiPalette.LINE_DIM if not hc else UiPalette.LINE_BRIGHT
				s.highlight = 0.0
		&"ghost":
			s.cuts = Vector4(4.0, 0.0, 4.0, 0.0)
			s.highlight = 0.0
			if state == &"normal":
				s.fill_top = Color(0.0, 0.0, 0.0, 0.0)
				s.fill_bottom = Color(0.0, 0.0, 0.0, 0.0)
				s.border_color = Color(0.0, 0.0, 0.0, 0.0)


# --- public build ---

## Builds the theme of a skin. `a11y`: `{high_contrast: bool, cvd: bool}`.
static func build(skin: UiSkin, a11y: Dictionary = {}) -> Theme:
	var t := Theme.new()
	t.default_font = UiFonts.get_font(UiFonts.Role.BODY)
	t.default_font_size = UiMetrics.FS_BODY
	_accent_colors(t, skin, a11y)
	_labels(t, skin, a11y)
	_panels(t, skin, a11y)
	_buttons(t, skin, a11y)
	_inputs(t, skin, a11y)
	_bars_and_scroll(t, skin, a11y)
	_popups(t, skin, a11y)
	return t


static func _mute(a11y: Dictionary) -> Color:
	return UiPalette.TEXT_DIM if _hc(a11y) else UiPalette.TEXT_MUTE


static func _accent_colors(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	var cvd: bool = bool(a11y.get("cvd", false))
	t.set_color("accent", ACCENT_TYPE, skin.accent)
	t.set_color("accent2", ACCENT_TYPE, skin.accent2)
	t.set_color("tint", ACCENT_TYPE, skin.tint)
	for kind: StringName in [&"ok", &"warn", &"danger", &"power"]:
		t.set_color(kind, ACCENT_TYPE, UiPalette.semantic_for(kind, cvd))
	t.set_color("text_mute", ACCENT_TYPE, _mute(a11y))


static func _labels(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	var cvd: bool = bool(a11y.get("cvd", false))
	t.set_color("font_color", "Label", UiPalette.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "Label", UiFonts.get_font(UiFonts.Role.BODY))
	t.set_font_size("font_size", "Label", UiMetrics.FS_BODY)
	_label_variation(t, "HeaderLabel", UiFonts.Role.HEAD, UiMetrics.FS_HEAD, skin.accent)
	_label_variation(t, "DimLabel", UiFonts.Role.BODY, UiMetrics.FS_SMALL, UiPalette.TEXT_DIM)
	_label_variation(t, "MuteLabel", UiFonts.Role.BODY, UiMetrics.FS_SMALL, _mute(a11y))
	_label_variation(t, "NumLabel", UiFonts.Role.NUM, UiMetrics.FS_NUM, UiPalette.TEXT)
	_label_variation(t, "CaptionLabel", UiFonts.Role.NUM, UiMetrics.FS_CAPTION, UiPalette.TEXT_DIM)
	_label_variation(t, "TitleLabel", UiFonts.Role.HEAD, UiMetrics.FS_TITLE, UiPalette.TEXT)
	_label_variation(t, "SubLabel", UiFonts.Role.BODY, UiMetrics.FS_SUB, UiPalette.TEXT)
	_label_variation(t, "NameLabel", UiFonts.Role.HEAD, UiMetrics.FS_NAME, UiPalette.TEXT)
	_label_variation(t, "DialogTitle", UiFonts.Role.HEAD, UiMetrics.FS_NAME, skin.accent)
	_label_variation(t, "CreditsLabel", UiFonts.Role.NUM, UiMetrics.FS_NUM, UiPalette.CREDITS)
	_label_variation(t, "OkLabel", UiFonts.Role.BODY_BOLD, UiMetrics.FS_LIST, UiPalette.semantic_for(&"ok", cvd))
	_label_variation(t, "WarnLabel", UiFonts.Role.BODY_BOLD, UiMetrics.FS_LIST, UiPalette.semantic_for(&"warn", cvd))
	_label_variation(t, "DangerLabel", UiFonts.Role.BODY_BOLD, UiMetrics.FS_LIST, UiPalette.semantic_for(&"danger", cvd))
	t.set_color("default_color", "RichTextLabel", UiPalette.TEXT)
	t.set_font("normal_font", "RichTextLabel", UiFonts.get_font(UiFonts.Role.BODY))
	t.set_font("bold_font", "RichTextLabel", UiFonts.get_font(UiFonts.Role.BODY_BOLD))
	t.set_font("mono_font", "RichTextLabel", UiFonts.get_font(UiFonts.Role.NUM))
	t.set_font_size("normal_font_size", "RichTextLabel", UiMetrics.FS_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", UiMetrics.FS_BODY)
	t.set_font_size("mono_font_size", "RichTextLabel", UiMetrics.FS_NUM)
	var sep := StyleBoxLine.new()
	sep.color = UiPalette.LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)


static func _label_variation(t: Theme, vname: StringName, role: int, size: int, col: Color) -> void:
	t.set_type_variation(vname, "Label")
	t.set_font("font", vname, UiFonts.get_font(role))
	t.set_font_size("font_size", vname, size)
	t.set_color("font_color", vname, col)


static func _panels(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	var p: UiStyleBox = box(skin, &"panel", &"normal", a11y)
	t.set_stylebox("panel", "PanelContainer", p)
	t.set_stylebox("panel", "Panel", p)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", box(skin, &"inset", &"normal", a11y))
	t.set_type_variation("SidebarPanel", "PanelContainer")
	t.set_stylebox("panel", "SidebarPanel", box(skin, &"sidebar", &"normal", a11y))
	t.set_type_variation("RibbonPanel", "PanelContainer")
	t.set_stylebox("panel", "RibbonPanel", box(skin, &"ribbon", &"normal", a11y))


static func _buttons(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	_button_type(t, "Button", &"button", skin, a11y, false)
	for pair: Array in [["PrimaryButton", &"primary"], ["HeroButton", &"hero"], ["DangerButton", &"danger"], ["CommandButton", &"command"], ["TabButton", &"tab"], ["GhostButton", &"ghost"]]:
		var vname: StringName = pair[0]
		t.set_type_variation(vname, "Button")
		_button_type(t, vname, pair[1], skin, a11y, pair[1] == &"primary" or pair[1] == &"danger")
	var hero: Dictionary = skin.recipe("button").get("hero", {})
	t.set_font("font", "HeroButton", UiFonts.get_font(UiFonts.Role.HEAD))
	t.set_font_size("font_size", "HeroButton", int(hero.get("size_px", UiMetrics.FS_HERO)))
	t.set_font_size("font_size", "CommandButton", UiMetrics.FS_SMALL)


static func _button_type(t: Theme, tname: StringName, recipe: StringName, skin: UiSkin, a11y: Dictionary, on_accent: bool) -> void:
	for state in BUTTON_STATES:
		t.set_stylebox(state, tname, box(skin, recipe, state, a11y))
	t.set_stylebox("hover_pressed", tname, box(skin, recipe, &"pressed", a11y))
	var focus_state: StringName = &"hero" if recipe == &"hero" else &"normal"
	t.set_stylebox("focus", tname, box(skin, &"focus", focus_state, a11y))
	var txt: Color = UiPalette.TEXT_ON_ACCENT if on_accent else UiPalette.TEXT
	# primary pressed = the dark half of the gradient: light text there (dark text would be < 3:1, deviation from 5.19.1)
	var pressed_txt: Color = UiPalette.TEXT if on_accent else skin.accent.lightened(0.3)
	t.set_color("font_color", tname, txt)
	t.set_color("font_hover_color", tname, txt if on_accent else Color.WHITE)
	t.set_color("font_pressed_color", tname, pressed_txt)
	t.set_color("font_hover_pressed_color", tname, pressed_txt)
	t.set_color("font_focus_color", tname, txt)
	t.set_color("font_disabled_color", tname, UiPalette.TEXT_DISABLED)
	t.set_color("font_outline_color", tname, Color(0.0, 0.0, 0.0, 0.0))
	t.set_font("font", tname, UiFonts.get_font(UiFonts.Role.BODY_BOLD))
	t.set_font_size("font_size", tname, UiMetrics.FS_LIST)


static func _inputs(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	for tn: String in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", tn, box(skin, &"input", &"normal", a11y))
		t.set_stylebox("focus", tn, box(skin, &"input", &"focus", a11y))
		t.set_color("font_color", tn, UiPalette.TEXT)
		t.set_color("caret_color", tn, skin.accent)
		t.set_color("selection_color", tn, Color(skin.accent, 0.35))
		t.set_color("font_placeholder_color", tn, _mute(a11y))
		t.set_font("font", tn, UiFonts.get_font(UiFonts.Role.BODY))
		t.set_font_size("font_size", tn, UiMetrics.FS_BODY)
	t.set_stylebox("read_only", "LineEdit", box(skin, &"input", &"normal", a11y))
	t.set_color("font_uneditable_color", "LineEdit", UiPalette.TEXT_DIM)
	t.set_icon("arrow", "OptionButton", _svg_icon(_svg_chevron(UiPalette.TEXT_DIM), 1.0))
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_constant("h_separation", "OptionButton", 8)
	t.set_constant("modulate_arrow", "OptionButton", 0)
	for k: String in ["CheckBox", "CheckButton"]:
		var boxed: bool = k == "CheckBox"
		t.set_icon("unchecked", k, _svg_icon(_svg_check(UiPalette.LINE_BRIGHT, Color(0, 0, 0, 0), false, boxed), 1.0))
		t.set_icon("checked", k, _svg_icon(_svg_check(skin.accent, skin.accent, true, boxed), 1.0))
		t.set_icon("unchecked_disabled", k, _svg_icon(_svg_check(UiPalette.LINE_DIM, Color(0, 0, 0, 0), false, boxed), 1.0))
		t.set_icon("checked_disabled", k, _svg_icon(_svg_check(UiPalette.LINE, UiPalette.LINE, true, boxed), 1.0))
		t.set_color("font_color", k, UiPalette.TEXT)
		t.set_color("font_hover_color", k, Color.WHITE)
		t.set_color("font_pressed_color", k, UiPalette.TEXT)
		t.set_color("font_hover_pressed_color", k, Color.WHITE)
		t.set_color("font_disabled_color", k, UiPalette.TEXT_DISABLED)
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, k, StyleBoxEmpty.new())
		t.set_stylebox("focus", k, box(skin, &"focus", &"normal", a11y))
		t.set_constant("h_separation", k, 10)
		t.set_font("font", k, UiFonts.get_font(UiFonts.Role.BODY_BOLD))
		t.set_font_size("font_size", k, UiMetrics.FS_LIST)


static func _bars_and_scroll(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	t.set_stylebox("background", "ProgressBar", box(skin, &"bar_bg", &"normal", a11y))
	t.set_stylebox("fill", "ProgressBar", box(skin, &"bar_fill", &"normal", a11y))
	t.set_color("font_color", "ProgressBar", UiPalette.TEXT)
	t.set_font("font", "ProgressBar", UiFonts.get_font(UiFonts.Role.NUM))
	t.set_font_size("font_size", "ProgressBar", UiMetrics.FS_CAPTION)
	for bar: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(skin, &"scroll_track", &"normal", a11y))
		t.set_stylebox("scroll_focus", bar, box(skin, &"scroll_track", &"normal", a11y))
		t.set_stylebox("grabber", bar, box(skin, &"grabber", &"normal", a11y))
		t.set_stylebox("grabber_highlight", bar, box(skin, &"grabber", &"highlight", a11y))
		t.set_stylebox("grabber_pressed", bar, box(skin, &"grabber", &"pressed", a11y))
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 4)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("slider", "HSlider", box(skin, &"slider_track", &"normal", a11y))
	t.set_stylebox("grabber_area", "HSlider", box(skin, &"slider_fill", &"normal", a11y))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(skin, &"slider_fill", &"normal", a11y))
	t.set_icon("grabber", "HSlider", _svg_icon(_svg_grabber(UiPalette.TEXT), 1.0))
	t.set_icon("grabber_highlight", "HSlider", _svg_icon(_svg_grabber(skin.accent), 1.0))
	t.set_icon("grabber_disabled", "HSlider", _svg_icon(_svg_grabber(UiPalette.TEXT_DISABLED), 1.0))
	t.set_constant("center_grabber", "HSlider", 1)


static func _popups(t: Theme, skin: UiSkin, a11y: Dictionary) -> void:
	var pop: UiStyleBox = box(skin, &"popup", &"normal", a11y)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	t.set_stylebox("hover", "PopupMenu", box(skin, &"popup_hover", &"normal", a11y))
	t.set_color("font_color", "PopupMenu", UiPalette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", UiPalette.TEXT_DISABLED)
	t.set_font("font", "PopupMenu", UiFonts.get_font(UiFonts.Role.BODY_BOLD))
	t.set_font_size("font_size", "PopupMenu", UiMetrics.FS_LIST)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_stylebox("panel", "TooltipPanel", box(skin, &"tooltip", &"normal", a11y))
	t.set_color("font_color", "TooltipLabel", UiPalette.TEXT)
	t.set_font("font", "TooltipLabel", UiFonts.get_font(UiFonts.Role.BODY))
	t.set_font_size("font_size", "TooltipLabel", UiMetrics.FS_SMALL)


# --- QA audit surface ---

## Token -> colour per widget state, for the contrast audits (`test_ui_tokens`, `[QA-XR-28]`):
## `{tokens: {NAME: Color}, states: {button|primary: {normal|hover|pressed|disabled|focus: {text, fill_top, fill_bottom, border}}},
##   accents: {code: Color}}`. `focus` = the normal state with the focus ring border.
static func colors(skin: UiSkin = null, a11y: Dictionary = {}) -> Dictionary:
	var sk: UiSkin = skin if skin != null else UiSkinSet.shared().neutral_skin()
	var tokens: Dictionary = {}
	for n in UiPalette.TOKEN_NAMES:
		tokens[n] = UiPalette.token(StringName(n))
	var states: Dictionary = {}
	for recipe: StringName in [&"button", &"primary"]:
		var per: Dictionary = {}
		for state in BUTTON_STATES:
			var b: UiStyleBox = box(sk, recipe, state, a11y)
			var txt: Color = UiPalette.TEXT_ON_ACCENT if recipe == &"primary" else UiPalette.TEXT
			if state == &"disabled":
				txt = UiPalette.TEXT_DISABLED
			elif state == &"pressed" and recipe == &"primary":
				txt = UiPalette.TEXT
			per[String(state)] = {"text": txt, "fill_top": b.fill_top, "fill_bottom": b.fill_bottom, "border": b.border_color}
		var nb: UiStyleBox = box(sk, recipe, &"normal", a11y)
		var fb: UiStyleBox = box(sk, &"focus", &"normal", a11y)
		per["focus"] = {"text": (per["normal"] as Dictionary)["text"], "fill_top": nb.fill_top, "fill_bottom": nb.fill_bottom, "border": fb.border_color}
		states[String(recipe)] = per
	var accents: Dictionary = {}
	for code in UiSkin.CODES:
		accents[code] = UiSkinSet.shared().skin_for(code).accent
	return {"tokens": tokens, "states": states, "accents": accents}


## Colours of the active mode's team set (`[QA-XR-28]`).
static func team_colors() -> PackedColorArray:
	var out := PackedColorArray()
	var skins: UiSkinSet = UiSkinSet.shared()
	for i in skins.team_color_count():
		out.append(skins.team_color(i))
	return out


# --- vector theme icons (DPITexture: re-rasterised at the UI scale, so crisp at any content scale factor) ---

static func _svg_icon(svg: String, scale: float) -> Texture2D:
	return DPITexture.create_from_string(svg, scale)


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _svg_chevron(col: Color) -> String:
	return "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'><path d='M5 8 L10 13 L15 8' fill='none' stroke='%s' stroke-width='2' stroke-linecap='square'/></svg>" % _hex(col)


static func _svg_check(border: Color, mark: Color, checked: bool, boxed: bool) -> String:
	var fill: String = "none" if not checked or mark.a <= 0.0 else _hex(mark)
	var inner: String = ""
	if boxed:
		inner = "<path d='M6 2 L16 2 L16 6 L16 16 L12 16 L2 16 L2 12 L2 2 Z' fill='none' stroke='%s' stroke-width='2'/>" % _hex(border)
		if checked:
			inner = "<path d='M6 2 L18 2 L18 14 L14 18 L2 18 L2 6 Z' fill='%s' stroke='%s' stroke-width='1.5'/><path d='M6 10.5 L9 13.5 L14.5 6.5' fill='none' stroke='%s' stroke-width='2.4' stroke-linecap='square'/>" % [fill, _hex(border), _hex(UiPalette.TEXT_ON_ACCENT)]
		else:
			inner = "<path d='M6 2 L18 2 L18 14 L14 18 L2 18 L2 6 Z' fill='%s' stroke='%s' stroke-width='1.5'/>" % [_hex(UiPalette.BG_DEEP), _hex(border)]
		return "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20' viewBox='0 0 20 20'>%s</svg>" % inner
	# switch (CheckButton): 36 x 20 pill with a knob
	var knob_x: int = 26 if checked else 10
	var track: String = _hex(mark) if checked and mark.a > 0.0 else _hex(UiPalette.BG_DEEP)
	var knob: String = _hex(UiPalette.TEXT_ON_ACCENT) if checked else _hex(border)
	return "<svg xmlns='http://www.w3.org/2000/svg' width='36' height='20' viewBox='0 0 36 20'><rect x='1' y='2' width='34' height='16' rx='2' fill='%s' stroke='%s' stroke-width='1.5'/><rect x='%d' y='5' width='10' height='10' fill='%s'/></svg>" % [track, _hex(border), knob_x - 5, knob]


static func _svg_grabber(col: Color) -> String:
	return "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='22' viewBox='0 0 16 22'><path d='M3 1 L13 1 L15 3 L15 19 L13 21 L3 21 L1 19 L1 3 Z' fill='%s'/><path d='M8 5 L8 17' stroke='%s' stroke-width='1.5'/></svg>" % [_hex(col), _hex(UiPalette.BG_DEEP)]
