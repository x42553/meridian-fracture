class_name UiTooltipBody
extends VBoxContainer
## Frameless rich tooltip body (ui.md 5.10.9). Godot wraps the body returned by `Control._make_custom_tooltip` in the
## themed `TooltipPanel`, so this Control draws no frame. Max width 340 px. Any Control can use it:
## ```
## tooltip_text = UiTooltipBody.encode({title = "Rifleman", tag = "TIER 1 // INFANTRY", stats = [...], text = "..."})
## func _make_custom_tooltip(for_text: String) -> Object: return UiTooltipBody.make_from_text(for_text)
## ```
## Spec keys (all optional): `title` (accent, Orbitron 15), `tag` (dim caption), `stats` (`[{label, value, delta, tone}]`,
## `tone` = &"ok" / &"warn" / &"danger" colours the delta chip), `text` (wrapped), `warn` (requirement line in the warning
## colour), `hint` (dim, last line), `accent` (Color override). The tooltip delay (500 ms) is the project's
## `gui/timers/tooltip_delay_sec`.

const MAX_W: float = float(UiMetrics.TOOLTIP_MAX_W)
const MIN_W: float = 180.0

var _spec: Dictionary = {}


## Body Control for a spec Dictionary.
static func make(spec: Dictionary) -> UiTooltipBody:
	var b := UiTooltipBody.new()
	b.build(spec)
	return b


## JSON form of a spec, to be stored in `tooltip_text`.
static func encode(spec: Dictionary) -> String:
	var d: Dictionary = spec.duplicate()
	if d.has("accent") and d["accent"] is Color:
		d["accent"] = (d["accent"] as Color).to_html(true)
	return JSON.stringify(d)


## Body for a `tooltip_text` (an `encode` string, or plain text -> a single wrapped paragraph).
static func make_from_text(for_text: String) -> UiTooltipBody:
	if for_text.begins_with("{"):
		var parsed: Variant = JSON.parse_string(for_text)
		if parsed is Dictionary:
			return make(parsed as Dictionary)
	return make({"text": for_text})


func _init() -> void:
	add_theme_constant_override("separation", UiMetrics.SP_2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## (Re)builds the labels from a spec.
func build(spec: Dictionary) -> void:
	_spec = spec
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var accent: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE) if is_inside_tree() else UiThemeService.current().get_color(&"accent", UiTheme.ACCENT_TYPE)
	if spec.has("accent"):
		accent = Color(String(spec["accent"]))
	var width: float = _wanted_width(spec)
	custom_minimum_size = Vector2(width, 0.0)
	var title: String = String(spec.get("title", ""))
	if title != "":
		var l := Label.new()
		l.theme_type_variation = &"HeaderLabel"
		l.text = title.to_upper()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", accent)
		add_child(l)
	var tag: String = String(spec.get("tag", ""))
	if tag != "":
		var l := Label.new()
		l.theme_type_variation = &"CaptionLabel"
		l.text = tag
		add_child(l)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiMetrics.SP_4)
		for s: Variant in stats:
			row.add_child(_stat_cell(s as Dictionary))
		add_child(row)
	var text: String = String(spec.get("text", ""))
	if text != "":
		add_child(_paragraph(text, &"", width))
	var warn: String = String(spec.get("warn", ""))
	if warn != "":
		add_child(_paragraph(warn, &"WarnLabel", width))
	var hint: String = String(spec.get("hint", ""))
	if hint != "":
		add_child(_paragraph(hint, &"MuteLabel", width))


func get_spec() -> Dictionary:
	return _spec


func _paragraph(text: String, variation: StringName, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0.0)
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _stat_cell(s: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.theme_type_variation = &"CaptionLabel"
	cap.text = String(s.get("label", "")).to_upper()
	v.add_child(cap)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var val := Label.new()
	val.theme_type_variation = &"NumLabel"
	val.text = String(s.get("value", ""))
	line.add_child(val)
	var delta: String = String(s.get("delta", ""))
	if delta != "":
		var d := Label.new()
		d.theme_type_variation = &"CaptionLabel"
		d.text = delta
		var tone: String = String(s.get("tone", "ok"))
		var col: Color = UiPalette.semantic(StringName(tone))
		d.add_theme_color_override("font_color", col)
		line.add_child(d)
	v.add_child(line)
	return v


## Width that fits the longest single-line piece, clamped to 180 .. 340 px.
func _wanted_width(spec: Dictionary) -> float:
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var w: float = MIN_W
	w = maxf(w, head.get_string_size(String(spec.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	w = maxf(w, num.get_string_size(String(spec.get("tag", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION).x)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		var sw: float = 0.0
		for s: Variant in stats:
			var d: Dictionary = s as Dictionary
			var cell: float = maxf(num.get_string_size(String(d.get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_CAPTION).x, num.get_string_size(String(d.get("value", "")) + String(d.get("delta", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_NUM).x + 8.0)
			sw += cell + float(UiMetrics.SP_4)
		w = maxf(w, sw)
	for key: String in ["text", "warn", "hint"]:
		var t: String = String(spec.get(key, ""))
		if t != "":
			w = maxf(w, minf(body.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_SMALL).x, MAX_W))
	return clampf(ceilf(w), MIN_W, MAX_W)
