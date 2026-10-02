class_name UiUnitTooltip
extends VBoxContainer
## Rich tooltip body for build cards. Returned from Control._make_custom_tooltip(); Godot wraps it in the
## themed TooltipPanel, so this control must NOT draw its own frame (it would be doubled).

static func create(item: UiBuildItem, skin: UiSkin) -> UiUnitTooltip:
	var t := UiUnitTooltip.new()
	t.add_theme_constant_override("separation", 4)
	t.custom_minimum_size = Vector2(290.0, 0.0)
	var title := Label.new()
	title.text = item.display_name.to_upper()
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", skin.accent)
	t.add_child(title)
	var meta := Label.new()
	meta.theme_type_variation = &"DimLabel"
	meta.text = "TIER %d  //  %s" % [item.tier, item.model_kind.replace("_", " ").to_upper()]
	t.add_child(meta)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	stats.add_child(_stat("COST", "$%s" % _group(item.cost), UiPalette.CREDITS))
	stats.add_child(_stat("TIME", _mmss(item.build_seconds), UiPalette.TEXT))
	if item.power_delta != 0:
		stats.add_child(_stat("POWER", "%+d" % item.power_delta, UiPalette.POWER if item.power_delta > 0 else UiPalette.WARN))
	stats.add_child(_stat("HOTKEY", item.hotkey if item.hotkey != "" else "-", UiPalette.TEXT))
	t.add_child(stats)
	if item.description != "":
		var d := Label.new()
		d.text = item.description
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(290.0, 0.0)
		d.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		t.add_child(d)
	if item.requires != "":
		var r := Label.new()
		r.text = "Requires: %s" % item.requires.replace("Requires ", "")
		r.add_theme_color_override("font_color", UiPalette.WARN)
		t.add_child(r)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "LMB build   RMB hold / cancel   SHIFT x5"
	t.add_child(hint)
	return t

static func _stat(label: String, value: String, col: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"DimLabel"
	l.add_theme_font_size_override("font_size", 11)
	v.add_child(l)
	var n := Label.new()
	n.text = value
	n.theme_type_variation = &"NumLabel"
	n.add_theme_color_override("font_color", col)
	v.add_child(n)
	return v

static func _group(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func _mmss(sec: float) -> String:
	var s: int = int(ceilf(sec))
	return "%d:%02d" % [s / 60, s % 60]
