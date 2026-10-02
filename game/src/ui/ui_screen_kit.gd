class_name UiScreenKit
extends RefCounted
## Small builders shared by the menu screens (main menu, lobby, loading, credits): panels with the accent header, labels with
## theme variations, full-rect helpers. Pure construction helpers, no state.


## A `PanelContainer` with a `UiPanelHeader` and a body `VBoxContainer`; returns {panel, body}.
static func panel(title: String, right: String = "", variation: StringName = &"", pad: int = 12, gap: int = 8) -> Dictionary:
	var p: PanelContainer = PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	p.add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	m.add_child(v)
	if title != "":
		v.add_child(UiPanelHeader.new(title, right))
	return {"panel": p, "body": v, "header": v.get_child(0) if title != "" else null}


## `trim`: ellipsis instead of growing (also drops the label's minimum width, so use it only in containers with a real width).
static func label(text: String, variation: StringName = &"", wrapped: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT, trim: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	if variation != &"":
		l.theme_type_variation = variation
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif trim:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func spacer(h: float = 0.0, expand: bool = false) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func button(text: String, kind: StringName = &"", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b: Button = Button.new()
	b.text = text
	if kind != &"":
		b.theme_type_variation = kind
	b.custom_minimum_size = min_size
	return b


## Solid background rectangle filling `host`.
static func backdrop(host: Control, col: Color) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(r)
	UiLayerRoot.fill(r)
	return r


## "9F3AC21E" (8 hex digits) of a u32.
static func hex8(v: int) -> String:
	return "%08X" % (v & 0xFFFFFFFF)


static func accent(c: Control) -> Color:
	return c.get_theme_color(&"accent", UiTheme.ACCENT_TYPE)


## Wordmark label in Orbitron at a variable weight with letter spacing (menu / splash titles).
static func wordmark(text: String, font_px: int, weight: int, spacing: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	var fv: FontVariation = FontVariation.new()
	fv.base_font = load(UiFonts.PATH_HEAD) as Font
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	fv.fallbacks = [UiFonts.get_font(UiFonts.Role.HEAD)]
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(col, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
