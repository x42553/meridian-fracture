class_name UiFmCardView
extends RefCounted
## Builds the detail card of the Field Manual (ui.md 5.17) from a `UiFmModel` card dictionary: header with glyph, tier pips and
## badges, stat tiles with delta markers (green / red by `tone`, "(floor)" and "*" markers, tooltip with the base value and the
## modifier that caused the change), fact rows, reference chips that open other cards, the weapons table, abilities, modifiers
## and matchup lines. Pure construction (no state): `nav` is `func(kind: int, def_index: int)`.


static func build(card: Dictionary, nav: Callable) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if card.is_empty():
		col.add_child(UiScreenKit.label("This is not part of the selected roster.", &"DimLabel"))
		return col
	col.add_child(_head(card))
	var stats: Array = card.get("stats", []) as Array
	if not stats.is_empty():
		col.add_child(_stat_grid(stats))
	match int(card["kind"]):
		DefEnums.Kind.UNIT:
			_unit_body(col, card, nav)
		DefEnums.Kind.STRUCTURE:
			_structure_body(col, card, nav)
		DefEnums.Kind.RESEARCH:
			_research_body(col, card, nav)
		DefEnums.Kind.POWER:
			_power_body(col, card, nav)
		DefEnums.Kind.SUPERWEAPON:
			_superweapon_body(col, card, nav)
	return col


# ---------------------------------------------------------------------------------------------------------------- head

static func _head(card: Dictionary) -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_4)
	var tile: PanelContainer = PanelContainer.new()
	tile.theme_type_variation = &"InsetPanel"
	var icon: Texture2D = card.get("icon") as Texture2D
	var kind_id: int = int(card.get("kind", -1))
	var viewed: bool = false
	if card.has("roster_id") and (kind_id == DefEnums.Kind.UNIT or kind_id == DefEnums.Kind.STRUCTURE):
		# the 3D turntable (UiModelViewer); the baked portrait / glyph below stay the fallback of a renderer-less run
		var viewer: UiModelViewer = UiModelViewer.new(Vector2(340.0, 255.0))
		if viewer.show_def(str(card.get("id", "")), str(card["roster_id"]), Color(0.0, 0.0, 0.0, 0.0), icon):
			viewer.name = "ModelViewer"
			viewer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			tile.free()
			tile = viewer
			viewed = true
		else:
			viewer.free()
	if viewed:
		pass
	elif icon != null:
		# baked portrait (384 x 288): the faction-styled model instead of the class glyph
		tile.custom_minimum_size = Vector2(228.0, 171.0)
		var pic: TextureRect = TextureRect.new()
		pic.texture = icon
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(pic)
	else:
		tile.custom_minimum_size = Vector2(84.0, 84.0)
		var gl: GlyphTile = GlyphTile.new(int(card.get("glyph", 0)))
		tile.add_child(gl)
	h.add_child(tile)
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	var name_l: Label = UiScreenKit.label(str(card["name"]), &"HeaderLabel")
	name_l.add_theme_font_size_override("font_size", 28)
	v.add_child(name_l)
	var meta: HBoxContainer = HBoxContainer.new()
	meta.add_theme_constant_override("separation", UiMetrics.SP_3)
	meta.add_child(_tag(str(UiFmText.KIND_TITLES.get(int(card["kind"]), "")).to_upper(), false))
	if int(card.get("tier", 0)) > 0 and int(card["kind"]) != DefEnums.Kind.SUPERWEAPON:
		meta.add_child(_tag("TIER %d" % int(card["tier"]), false))
	if card.has("class") and int(card["kind"]) == DefEnums.Kind.UNIT:
		meta.add_child(_tag(str(card["class"]).to_upper(), bool(card.get("unique", false))))
	if card.has("scope") and bool(card.get("exclusive", false)):
		meta.add_child(_tag("SUBFACTION", true))
	v.add_child(meta)
	var text: String = str(card.get("text", ""))
	if not text.is_empty():
		v.add_child(UiScreenKit.label(text, &"SubLabel", true))
	h.add_child(v)
	return h


static func _tag(text: String, accent: bool) -> Control:
	var l: Label = UiScreenKit.label(text, &"CaptionLabel")
	if accent:
		l.add_theme_color_override("font_color", accent_color())
	return l


static func accent_color() -> Color:
	return UiThemeService.current_skin().accent


## Large glyph on the head tile.
class GlyphTile extends Control:
	var glyph_id: int = 0

	func _init(g: int) -> void:
		glyph_id = g
		custom_minimum_size = Vector2(84.0, 84.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		UiDraw.glyph(self, glyph_id, Rect2(14.0, 14.0, size.x - 28.0, size.y - 28.0), acc, 2.4)


# ---------------------------------------------------------------------------------------------------------------- stats

static func _tone_color(tone: String) -> Color:
	match tone:
		"good":
			return UiPalette.semantic(&"ok")
		"bad":
			return UiPalette.semantic(&"danger")
	return UiPalette.TEXT_MUTE


static func _stat_grid(stats: Array) -> Control:
	var g: GridContainer = GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", UiMetrics.SP_2)
	g.add_theme_constant_override("v_separation", UiMetrics.SP_2)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s: Dictionary in stats:
		g.add_child(stat_tile(s))
	return g


## One stat tile: caption, value, delta marker.
static func stat_tile(s: Dictionary) -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	p.add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	m.add_child(v)
	v.add_child(UiScreenKit.label(str(s["label"]).to_upper(), &"CaptionLabel"))
	var value: Label = UiScreenKit.label(str(s["text"]) + ("*" if bool(s.get("conditional", false)) else ""), &"")
	value.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	value.add_theme_font_size_override("font_size", 22)
	v.add_child(value)
	var delta: String = ""
	var d_bp: int = int(s.get("delta_bp", 0))
	if d_bp != 0:
		delta = ("▲ " if d_bp > 0 else "▼ ") + str(s["delta_text"])
	if bool(s.get("floor", false)):
		delta += "  (at floor)"
	var dl: Label = UiScreenKit.label(delta if not delta.is_empty() else " ", &"CaptionLabel")
	dl.add_theme_color_override("font_color", _tone_color(str(s.get("tone", ""))))
	v.add_child(dl)
	var tip: String = str(s.get("tip", ""))
	if not tip.is_empty():
		p.tooltip_text = tip
		for c: Node in [v, value, dl, m]:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	p.accessibility_name = "%s %s %s" % [s["label"], s["text"], delta]
	return p


# ---------------------------------------------------------------------------------------------------------------- pieces

static func section(col: VBoxContainer, title: String) -> VBoxContainer:
	var hdr: Label = UiScreenKit.label(title.to_upper(), &"CaptionLabel")
	hdr.add_theme_color_override("font_color", accent_color())
	col.add_child(UiScreenKit.spacer(4.0))
	col.add_child(hdr)
	var rule: ColorRect = ColorRect.new()
	rule.color = UiPalette.LINE_DIM
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	col.add_child(body)
	return body


static func fact(body: VBoxContainer, key: String, value: String) -> void:
	if value.is_empty():
		return
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_3)
	var k: Label = UiScreenKit.label(key, &"DimLabel")
	k.custom_minimum_size = Vector2(150.0, 0.0)
	h.add_child(k)
	var v: Label = UiScreenKit.label(value, &"", true)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	body.add_child(h)


## A row of reference chips (`refs` from the model); a chip opens that card. Shows "None" when empty.
static func chips(body: VBoxContainer, key: String, refs: Array, nav: Callable) -> void:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_3)
	var k: Label = UiScreenKit.label(key, &"DimLabel")
	k.custom_minimum_size = Vector2(150.0, 32.0)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(k)
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if refs.is_empty():
		flow.add_child(UiScreenKit.label("None", &"DimLabel"))
	for r: Variant in refs:
		var d: Dictionary = r as Dictionary
		flow.add_child(chip(d, nav))
	h.add_child(flow)
	body.add_child(h)


static func chip(ref: Dictionary, nav: Callable) -> Button:
	var b: Button = Button.new()
	b.text = str(ref["name"])
	b.custom_minimum_size = Vector2(0.0, 32.0)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not bool(ref.get("in_roster", true))
	if b.disabled:
		b.tooltip_text = "Not part of this roster."
	b.pressed.connect(func() -> void: nav.call(int(ref["kind"]), int(ref["index"])))
	return b


static func bullets(body: VBoxContainer, lines: Array, prefix: String = "•  ") -> void:
	for l: Variant in lines:
		body.add_child(UiScreenKit.label(prefix + str(l), &"", true))


static func _weapons(col: VBoxContainer, weapons: Array) -> void:
	if weapons.is_empty():
		return
	var body: VBoxContainer = section(col, "Weapons")
	var g: GridContainer = GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for head: String in ["WEAPON", "DAMAGE", "DPS", "RANGE", "RELOAD", "TYPE"]:
		var hl: Label = UiScreenKit.label(head, &"CaptionLabel")
		if head != "WEAPON":
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(hl)
	for w: Dictionary in weapons:
		var name_l: Label = UiScreenKit.label(str(w["name"]), &"", false, HORIZONTAL_ALIGNMENT_LEFT, true)
		name_l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.BODY_BOLD))
		name_l.add_theme_font_size_override("font_size", 17)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.custom_minimum_size = Vector2(130.0, 0.0)
		var tags: PackedStringArray = w["tags"] as PackedStringArray
		var tip: String = "Hits: %s. Targets: %s." % [", ".join([str(w["hits"]) + (" per volley" if int(w["hits"]) != 1 else "")]), w["targets"]]
		if not tags.is_empty():
			tip += " " + ", ".join(tags) + "."
		if str(w["splash_text"]) != "":
			tip += " Splash radius %s cells." % w["splash_text"]
		if str(w["min_range_text"]) != "":
			tip += " Minimum range %s cells." % w["min_range_text"]
		name_l.tooltip_text = tip
		name_l.mouse_filter = Control.MOUSE_FILTER_STOP
		g.add_child(name_l)
		var dmg: String = str(w["damage"]) + ("x%d" % int(w["hits"]) if int(w["hits"]) > 1 else "")
		g.add_child(_cell(dmg, HORIZONTAL_ALIGNMENT_RIGHT, true, Color.WHITE))
		var dps_col: Color = _tone_color(str(w.get("dps_tone", "")))
		g.add_child(_cell(str(w["dps_text"]), HORIZONTAL_ALIGNMENT_RIGHT, true, dps_col if str(w.get("dps_tone", "")) != "" else UiPalette.TEXT))
		g.add_child(_cell(str(w["range_text"]), HORIZONTAL_ALIGNMENT_RIGHT, true, Color.WHITE))
		g.add_child(_cell(str(w["reload_text"]), HORIZONTAL_ALIGNMENT_RIGHT, true, Color.WHITE))
		g.add_child(_cell(str(w["dtype_text"]), HORIZONTAL_ALIGNMENT_RIGHT, false, UiPalette.TEXT_DIM))
	body.add_child(g)
	for w2: Dictionary in weapons:
		var extra: PackedStringArray = PackedStringArray(w2["tags"] as PackedStringArray)
		extra.append("Hits: " + str(w2["targets"]))
		if str(w2["splash_text"]) != "":
			extra.append("Splash %s cells" % w2["splash_text"])
		if str(w2["min_range_text"]) != "":
			extra.append("Min range %s cells" % w2["min_range_text"])
		if int(w2.get("ammo", 0)) > 0:
			extra.append("%d volleys per sortie" % int(w2["ammo"]))
		body.add_child(UiScreenKit.label("%s: %s" % [w2["name"], " · ".join(extra)], &"DimLabel", true))


static func _cell(text: String, align: int, mono: bool, col: Color) -> Label:
	var l: Label = UiScreenKit.label(text, &"", false, align)
	if mono:
		l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	if col != Color.WHITE:
		l.add_theme_color_override("font_color", col)
	return l


static func _abilities(col: VBoxContainer, abilities: Array) -> void:
	if abilities.is_empty():
		return
	var body: VBoxContainer = section(col, "Abilities")
	for a: Dictionary in abilities:
		var row: VBoxContainer = VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var nm: Label = UiScreenKit.label(str(a["name"]), &"NameLabel")
		nm.add_theme_color_override("font_color", accent_color())
		row.add_child(nm)
		row.add_child(UiScreenKit.label(str(a["text"]), &"", true))
		body.add_child(row)


static func _modifiers(col: VBoxContainer, mods: Array) -> void:
	if mods.is_empty():
		return
	var body: VBoxContainer = section(col, "Roster modifiers")
	for m: Dictionary in mods:
		var h: HBoxContainer = HBoxContainer.new()
		h.add_theme_constant_override("separation", UiMetrics.SP_2)
		var d: Label = UiScreenKit.label(("▲" if int(m["delta_bp"]) > 0 else "▼"), &"")
		d.add_theme_color_override("font_color", _tone_color(str(m["tone"])))
		d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(d)
		var t: VBoxContainer = VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_child(UiScreenKit.label(str(m["text"]), &"", true))
		var src: String = str(m["source"]).capitalize()
		if bool(m["conditional"]) and str(m["condition"]) != "":
			src += ", applies " + str(m["condition"])
		t.add_child(UiScreenKit.label(src, &"CaptionLabel"))
		h.add_child(t)
		body.add_child(h)


# ---------------------------------------------------------------------------------------------------------------- bodies

static func _unit_body(col: VBoxContainer, c: Dictionary, nav: Callable) -> void:
	var facts: VBoxContainer = section(col, "Details")
	fact(facts, "Armor", str(c["armor"]))
	fact(facts, "Movement", str(c["move"]))
	fact(facts, "Layers", str(c["layers"]))
	fact(facts, "Population", str(c["pop"]) if int(c["pop"]) != 1 else "1")
	fact(facts, "Detection radius", str(c["detect_text"]) + " cells" if str(c["detect_text"]) != "" else "")
	if not (c["producer"] as Dictionary).is_empty():
		chips(facts, "Built at", [c["producer"]], nav)
	if not (c["requires"] as Array).is_empty():
		chips(facts, "Requires", c["requires"] as Array, nav)
	if not (c["replaces"] as Dictionary).is_empty():
		chips(facts, "Replaces", [c["replaces"]], nav)
	if not (c["replaced_by"] as Array).is_empty():
		chips(facts, "Replaced by", c["replaced_by"] as Array, nav)
	var flags: PackedStringArray = c["flags"] as PackedStringArray
	if not flags.is_empty():
		fact(facts, "Notes", ". ".join(flags) + ".")
	_weapons(col, c["weapons"] as Array)
	_abilities(col, c["abilities"] as Array)
	var match_body: VBoxContainer = section(col, "Matchups")
	if not (c["effective_vs"] as PackedStringArray).is_empty():
		fact(match_body, "Strong against", ", ".join(c["effective_vs"] as PackedStringArray))
	if not (c["poor_vs"] as PackedStringArray).is_empty():
		fact(match_body, "Weak against", ", ".join(c["poor_vs"] as PackedStringArray))
	fact(match_body, "Takes full damage", ", ".join(c["takes_full"] as PackedStringArray))
	fact(match_body, "Resists", ", ".join(c["resists"] as PackedStringArray))
	_modifiers(col, c["modifiers"] as Array)


static func _structure_body(col: VBoxContainer, c: Dictionary, nav: Callable) -> void:
	var facts: VBoxContainer = section(col, "Details")
	fact(facts, "Armor", str(c["armor"]))
	fact(facts, "Footprint", str(c["footprint"]))
	if int(c["queues"]) > 1:
		fact(facts, "Production queues", str(c["queues"]))
	if not (c["requires"] as Array).is_empty():
		chips(facts, "Requires", c["requires"] as Array, nav)
	if not (c["produces"] as Array).is_empty():
		chips(facts, "Produces", c["produces"] as Array, nav)
	if not (c["unlocks"] as Array).is_empty():
		chips(facts, "Unlocks", c["unlocks"] as Array, nav)
	for pf: String in c["placement"] as PackedStringArray:
		fact(facts, "Placement", pf + ".")
	for fl: String in c["flags"] as PackedStringArray:
		fact(facts, "Note", fl + ".")
	_weapons(col, c["weapons"] as Array)
	_abilities(col, c["abilities"] as Array)
	_modifiers(col, c["modifiers"] as Array)


static func _research_body(col: VBoxContainer, c: Dictionary, nav: Callable) -> void:
	var facts: VBoxContainer = section(col, "Details")
	fact(facts, "Available to", str(c["scope"]))
	if not (c["requires"] as Array).is_empty():
		chips(facts, "Requires", c["requires"] as Array, nav)
	fact(facts, "Effect", str(c["text"]))


static func _power_body(col: VBoxContainer, c: Dictionary, nav: Callable) -> void:
	var facts: VBoxContainer = section(col, "Details")
	fact(facts, "Available to", str(c["scope"]))
	fact(facts, "Targeting", "%s. %s." % [c["targeting"], c["vision"]])
	if bool(c["needs_power"]):
		fact(facts, "Needs", "Powered structures.")
	if not (c["requires"] as Array).is_empty():
		chips(facts, "Requires", c["requires"] as Array, nav)


static func _superweapon_body(col: VBoxContainer, c: Dictionary, nav: Callable) -> void:
	var facts: VBoxContainer = section(col, "Details")
	fact(facts, "Targeting", str(c["targeting"]))
	fact(facts, "Charges", str(c["charges"]) + (", starts charged" if bool(c["starts_charged"]) else ""))
	if not (c["launcher"] as Dictionary).is_empty():
		chips(facts, "Launched by", [c["launcher"]], nav)
	if not (c["requires"] as Array).is_empty():
		chips(facts, "Requires", c["requires"] as Array, nav)
