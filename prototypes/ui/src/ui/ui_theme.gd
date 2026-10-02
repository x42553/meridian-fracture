class_name UiTheme
extends RefCounted
## Builds THE game theme from a UiSkin. One `Theme` resource, assigned to the root Window, styles every
## Control (including popups and tooltips). Re-tinting for another faction = build() again + swap (~1 ms).
## Type variations (Control.theme_type_variation): HeaderLabel DimLabel NumLabel TitleLabel CreditsLabel
## InsetPanel SidebarPanel RibbonPanel  PrimaryButton HeroButton CommandButton TabButton GhostButton.

const FS_BODY := 15
const FS_SMALL := 13
const FS_HEAD := 13
const FS_TITLE := 40

static func build(skin: UiSkin) -> Theme:
	var t := Theme.new()
	t.default_font = UiFonts.get_font(UiFonts.Role.BODY)
	t.default_font_size = FS_BODY
	_labels(t, skin)
	_panels(t, skin)
	_buttons(t, skin)
	_inputs(t, skin)
	_bars_and_scroll(t, skin)
	_popups(t, skin)
	return t

# --- style recipes (public: widgets that draw their own frames reuse them) -------------------------

static func panel_box(skin: UiSkin, alpha: float = 0.94, cut: float = 10.0) -> UiStyleBox:
	var s := UiStyleBox.new()
	s.fill_top = skin.panel_top(alpha)
	s.fill_bottom = skin.panel_bottom(alpha)
	s.border_color = UiPalette.LINE
	s.cuts = Vector4(cut, 0.0, cut, 0.0)
	s.bracket_color = skin.accent
	s.bracket_mask = 5
	return s.set_padding(12.0, 10.0, 12.0, 10.0)

static func inset_box(skin: UiSkin) -> UiStyleBox:
	var s := UiStyleBox.new()
	s.fill_top = UiPalette.BG_DEEP.lerp(skin.tint, 0.2)
	s.fill_bottom = UiPalette.BG_PANEL.lerp(skin.tint, 0.1)
	s.border_color = UiPalette.LINE_DIM
	s.cuts = Vector4(4.0, 0.0, 4.0, 0.0)
	s.highlight = 0.0
	return s.set_padding(8.0, 6.0, 8.0, 6.0)

static func button_box(skin: UiSkin, state: StringName, cut: float = 6.0) -> UiStyleBox:
	var s := UiStyleBox.new()
	s.cuts = Vector4(cut, 0.0, cut, 0.0)
	match state:
		&"hover":
			s.fill_top = Color("#2a3f57")
			s.fill_bottom = Color("#1a2a3c")
			s.border_color = skin.accent
			s.glow = Color(skin.accent, 0.22)
		&"pressed":
			s.fill_top = Color("#0d141c")
			s.fill_bottom = Color("#182638")
			s.border_color = skin.accent
			s.highlight = 0.0
		&"disabled":
			s.fill_top = Color("#0f151c")
			s.fill_bottom = Color("#0c1218")
			s.border_color = UiPalette.LINE_DIM
			s.highlight = 0.0
		_:
			s.fill_top = Color("#1f2c3c")
			s.fill_bottom = Color("#141e2b")
			s.border_color = UiPalette.LINE
	return s.set_padding(14.0, 6.0, 14.0, 6.0)

static func accent_button_box(skin: UiSkin, state: StringName) -> UiStyleBox:
	var s := button_box(skin, state, 8.0)
	var top: Color = skin.accent.lightened(0.12)
	var bot: Color = skin.accent.darkened(0.42)
	match state:
		&"hover":
			top = top.lightened(0.15)
			bot = bot.lightened(0.15)
			s.glow = Color(skin.accent, 0.35)
		&"pressed":
			top = bot
			bot = skin.accent.darkened(0.6)
		&"disabled":
			top = UiPalette.BG_CONTROL
			bot = UiPalette.BG_PANEL
	s.fill_top = top
	s.fill_bottom = bot
	if state != &"disabled":
		s.border_color = skin.accent.lightened(0.35)
	return s

# --- theme sections ----------------------------------------------------------------------------------

static func _labels(t: Theme, skin: UiSkin) -> void:
	t.set_color("font_color", "Label", UiPalette.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "Label", UiFonts.get_font(UiFonts.Role.BODY))
	t.set_font_size("font_size", "Label", FS_BODY)
	_label_variation(t, "HeaderLabel", UiFonts.Role.HEAD, FS_HEAD, skin.accent)
	_label_variation(t, "DimLabel", UiFonts.Role.BODY, FS_SMALL, UiPalette.TEXT_DIM)
	_label_variation(t, "NumLabel", UiFonts.Role.NUM, FS_BODY, UiPalette.TEXT)
	_label_variation(t, "TitleLabel", UiFonts.Role.HEAD, FS_TITLE, UiPalette.TEXT)
	_label_variation(t, "CreditsLabel", UiFonts.Role.NUM, 15, UiPalette.CREDITS)

static func _label_variation(t: Theme, vname: StringName, role: UiFonts.Role, size: int, col: Color) -> void:
	t.set_type_variation(vname, "Label")
	t.set_font("font", vname, UiFonts.get_font(role))
	t.set_font_size("font_size", vname, size)
	t.set_color("font_color", vname, col)

static func _panels(t: Theme, skin: UiSkin) -> void:
	t.set_stylebox("panel", "PanelContainer", panel_box(skin))
	t.set_stylebox("panel", "Panel", panel_box(skin))
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", inset_box(skin))
	t.set_type_variation("SidebarPanel", "PanelContainer")
	var sb: UiStyleBox = panel_box(skin, 0.97, 0.0)
	sb.cuts = Vector4(0.0, 0.0, 0.0, 18.0)
	sb.bracket_mask = 8
	t.set_stylebox("panel", "SidebarPanel", sb.set_padding(14.0, 12.0, 14.0, 12.0))
	t.set_type_variation("RibbonPanel", "PanelContainer")
	var rb: UiStyleBox = panel_box(skin, 0.92, 12.0)
	rb.cuts = Vector4(12.0, 12.0, 12.0, 12.0)
	rb.bracket_mask = 0
	t.set_stylebox("panel", "RibbonPanel", rb.set_padding(20.0, 6.0, 20.0, 6.0))

static func _buttons(t: Theme, skin: UiSkin) -> void:
	_button_type(t, "Button", skin, false, 6.0)
	_button_type(t, "PrimaryButton", skin, true, 8.0)
	t.set_type_variation("PrimaryButton", "Button")
	_button_type(t, "HeroButton", skin, false, 10.0)
	t.set_type_variation("HeroButton", "Button")
	t.set_font("font", "HeroButton", UiFonts.get_font(UiFonts.Role.HEAD))
	t.set_font_size("font_size", "HeroButton", 20)
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		var hb: UiStyleBox = button_box(skin, state, 12.0)
		hb.set_padding(28.0, 12.0, 28.0, 12.0)
		hb.fill_top.a = 0.78
		hb.fill_bottom.a = 0.78
		t.set_stylebox(state, "HeroButton", hb)
	t.set_stylebox("hover_pressed", "HeroButton", t.get_stylebox("pressed", "HeroButton"))
	t.set_type_variation("CommandButton", "Button")
	t.set_type_variation("TabButton", "Button")
	t.set_type_variation("GhostButton", "Button")
	var ghost: UiStyleBox = button_box(skin, &"normal", 4.0)
	ghost.fill_top = Color(0.0, 0.0, 0.0, 0.0)
	ghost.fill_bottom = Color(0.0, 0.0, 0.0, 0.0)
	ghost.border_color = Color(0.0, 0.0, 0.0, 0.0)
	ghost.highlight = 0.0
	t.set_stylebox("normal", "GhostButton", ghost)

static func _button_type(t: Theme, tname: StringName, skin: UiSkin, accent: bool, cut: float) -> void:
	for state in [&"normal", &"hover", &"pressed", &"disabled"]:
		var sb: UiStyleBox = accent_button_box(skin, state) if accent else button_box(skin, state, cut)
		t.set_stylebox(state, tname, sb)
	t.set_stylebox("hover_pressed", tname, t.get_stylebox("pressed", tname))
	t.set_stylebox("focus", tname, StyleBoxEmpty.new())
	var txt: Color = Color("#10161d") if accent else UiPalette.TEXT
	t.set_color("font_color", tname, txt)
	t.set_color("font_hover_color", tname, txt if accent else Color.WHITE)
	t.set_color("font_pressed_color", tname, txt if accent else skin.accent.lightened(0.3))
	t.set_color("font_hover_pressed_color", tname, txt if accent else skin.accent.lightened(0.3))
	t.set_color("font_focus_color", tname, txt)
	t.set_color("font_disabled_color", tname, UiPalette.TEXT_MUTE)
	t.set_font("font", tname, UiFonts.get_font(UiFonts.Role.BODY_BOLD))
	t.set_font_size("font_size", tname, 15)

static func _inputs(t: Theme, skin: UiSkin) -> void:
	var normal: UiStyleBox = inset_box(skin)
	var focus: UiStyleBox = inset_box(skin)
	focus.border_color = skin.accent
	focus.glow = Color(skin.accent, 0.2)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", normal)
	t.set_color("font_color", "LineEdit", UiPalette.TEXT)
	t.set_color("caret_color", "LineEdit", skin.accent)
	t.set_color("selection_color", "LineEdit", Color(skin.accent, 0.35))
	t.set_color("font_placeholder_color", "LineEdit", UiPalette.TEXT_MUTE)
	# OptionButton reuses Button styles; only the arrow is extra.
	t.set_icon("arrow", "OptionButton", _icon_arrow(UiPalette.TEXT_DIM))
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_constant("h_separation", "OptionButton", 8)
	for k in ["CheckBox", "CheckButton"]:
		t.set_icon("unchecked", k, _icon_box(UiPalette.LINE_BRIGHT, Color(0.0, 0.0, 0.0, 0.0)))
		t.set_icon("checked", k, _icon_box(skin.accent, skin.accent))
		t.set_icon("unchecked_disabled", k, _icon_box(UiPalette.LINE_DIM, Color(0.0, 0.0, 0.0, 0.0)))
		t.set_icon("checked_disabled", k, _icon_box(UiPalette.LINE_DIM, UiPalette.LINE))
		t.set_color("font_color", k, UiPalette.TEXT)
		t.set_color("font_hover_color", k, Color.WHITE)
		t.set_color("font_pressed_color", k, UiPalette.TEXT)
		t.set_stylebox("normal", k, StyleBoxEmpty.new())
		t.set_stylebox("hover", k, StyleBoxEmpty.new())
		t.set_stylebox("pressed", k, StyleBoxEmpty.new())
		t.set_stylebox("focus", k, StyleBoxEmpty.new())
		t.set_constant("h_separation", k, 10)

static func _bars_and_scroll(t: Theme, skin: UiSkin) -> void:
	var bg: UiStyleBox = inset_box(skin)
	bg.cuts = Vector4(3.0, 0.0, 3.0, 0.0)
	t.set_stylebox("background", "ProgressBar", bg.set_padding(0.0, 0.0, 0.0, 0.0))
	var fill := UiStyleBox.new()
	fill.fill_top = skin.accent.lightened(0.25)
	fill.fill_bottom = skin.accent.darkened(0.35)
	fill.border_color = Color(0.0, 0.0, 0.0, 0.0)
	fill.border_width = 0.0
	fill.cuts = Vector4(3.0, 0.0, 3.0, 0.0)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", UiPalette.TEXT)
	t.set_font("font", "ProgressBar", UiFonts.get_font(UiFonts.Role.NUM))
	t.set_font_size("font_size", "ProgressBar", 12)
	# scrollbars: thin, no arrows
	var track := UiStyleBox.new()
	track.fill_top = Color(0.0, 0.0, 0.0, 0.35)
	track.fill_bottom = Color(0.0, 0.0, 0.0, 0.35)
	track.border_width = 0.0
	track.highlight = 0.0
	track.border_color = Color(0.0, 0.0, 0.0, 0.0)
	track.set_padding(3.0, 3.0, 3.0, 3.0)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		for gname in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var g := UiStyleBox.new()
			var a: Color = skin.accent
			if gname == "grabber":
				a = skin.accent.darkened(0.35)
			g.fill_top = a
			g.fill_bottom = a.darkened(0.25)
			g.border_width = 0.0
			g.highlight = 0.0
			g.border_color = Color(0.0, 0.0, 0.0, 0.0)
			g.set_padding(3.0, 3.0, 3.0, 3.0)
			t.set_stylebox(gname, bar, g)
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 4)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# sliders
	var st := UiStyleBox.new()
	st.fill_top = UiPalette.BG_DEEP
	st.fill_bottom = UiPalette.BG_DEEP
	st.border_color = UiPalette.LINE_DIM
	st.highlight = 0.0
	st.set_padding(0.0, 3.0, 0.0, 3.0)
	var area: UiStyleBox = st.duplicate() as UiStyleBox
	area.fill_top = skin.accent.darkened(0.2)
	area.fill_bottom = skin.accent.darkened(0.5)
	area.border_color = Color(0.0, 0.0, 0.0, 0.0)
	t.set_stylebox("slider", "HSlider", st)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	t.set_icon("grabber", "HSlider", _icon_grabber(UiPalette.TEXT))
	t.set_icon("grabber_highlight", "HSlider", _icon_grabber(skin.accent))
	t.set_constant("center_grabber", "HSlider", 1)

static func _popups(t: Theme, skin: UiSkin) -> void:
	var pop: UiStyleBox = panel_box(skin, 0.98, 6.0)
	pop.bracket_color = Color(0.0, 0.0, 0.0, 0.0)
	pop.set_padding(6.0, 6.0, 6.0, 6.0)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	var hv := UiStyleBox.new()
	hv.fill_top = Color(skin.accent, 0.28)
	hv.fill_bottom = Color(skin.accent, 0.14)
	hv.border_color = Color(skin.accent, 0.7)
	hv.highlight = 0.0
	hv.set_padding(8.0, 4.0, 8.0, 4.0)
	t.set_stylebox("hover", "PopupMenu", hv)
	t.set_color("font_color", "PopupMenu", UiPalette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", UiFonts.get_font(UiFonts.Role.BODY_BOLD))
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "PopupMenu", 6)
	# tooltips (Godot looks up TooltipPanel + TooltipLabel through the owner's theme)
	var tip: UiStyleBox = panel_box(skin, 0.98, 8.0)
	tip.bracket_mask = 1
	tip.glow = Color(0.0, 0.0, 0.0, 0.5)
	t.set_stylebox("panel", "TooltipPanel", tip.set_padding(12.0, 8.0, 12.0, 8.0))
	t.set_color("font_color", "TooltipLabel", UiPalette.TEXT)
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL + 1)

# --- tiny procedural bitmap icons (theme icons must be Textures; they do NOT scale crisply, so keep them 2x) ---

static func _icon_box(border: Color, mark: Color) -> ImageTexture:
	var n: int = 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	img.fill_rect(Rect2i(2, 2, n - 4, n - 4), border)
	img.fill_rect(Rect2i(4, 4, n - 8, n - 8), UiPalette.BG_DEEP)
	if mark.a > 0.0:
		img.fill_rect(Rect2i(8, 8, n - 16, n - 16), mark)
	return ImageTexture.create_from_image(img)

static func _icon_arrow(col: Color) -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in 8:
		img.fill_rect(Rect2i(6 + y, 8 + y, 12 - 2 * y, 1), col)
	return ImageTexture.create_from_image(img)

static func _icon_grabber(col: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in 10:
		img.fill_rect(Rect2i(10 - y - 1, y + 1, 2 * y + 2, 1), col)
		img.fill_rect(Rect2i(10 - y - 1, 19 - y, 2 * y + 2, 1), col)
	return ImageTexture.create_from_image(img)
