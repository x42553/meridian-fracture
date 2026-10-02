class_name UiMissionTimers
extends VBoxContainer
## The running, labelled timers of a scripted mission (MIS2) as chips at the top right of the playfield: label and "m:ss". A chip turns
## warn under 30 s and danger under 10 s. Data from `UiMissionModel.visible_timers`; the chips are rebuilt only when the set of timers
## changes, the time text is updated in place.

const WARN_TICKS: int = 30 * 20
const DANGER_TICKS: int = 10 * 20

var _chips: Dictionary = {}  ## timer idx -> {panel, name, time}
var _order: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_BEGIN


## `list` = `UiMissionModel.visible_timers()`.
func update(list: Array[Dictionary]) -> void:
	var order: PackedInt32Array = PackedInt32Array()
	for t: Dictionary in list:
		order.append(int(t["idx"]))
	if order != _order:
		_order = order
		for c: Node in get_children():
			remove_child(c)
			c.queue_free()
		_chips.clear()
		for t: Dictionary in list:
			_chips[int(t["idx"])] = _make_chip(str(t["label"]))
	for t: Dictionary in list:
		var chip: Dictionary = _chips[int(t["idx"])] as Dictionary
		var left: int = int(t["left_ticks"])
		var tl: Label = chip["time"] as Label
		tl.text = UiMissionModel.clock_of(left)
		var col: Color = UiPalette.TEXT
		if left <= DANGER_TICKS:
			col = UiPalette.semantic(&"danger")
		elif left <= WARN_TICKS:
			col = UiPalette.semantic(&"warn")
		tl.add_theme_color_override("font_color", col)


func chip_count() -> int:
	return _chips.size()


func chip_text(timer_idx: int) -> String:
	var chip: Variant = _chips.get(timer_idx)
	return (chip["time"] as Label).text if chip != null else ""


func chip_label(timer_idx: int) -> String:
	var chip: Variant = _chips.get(timer_idx)
	return (chip["name"] as Label).text if chip != null else ""


func _make_chip(label_text: String) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(m)
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	m.add_child(h)
	var name_l: Label = UiScreenKit.label(label_text.to_upper(), &"CaptionLabel")
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_l)
	var time_l: Label = UiScreenKit.label("0:00", &"NameLabel")
	time_l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	time_l.add_theme_font_size_override("font_size", UiMetrics.FS_NUM_COUNTDOWN)
	h.add_child(time_l)
	add_child(panel)
	return {"panel": panel, "name": name_l, "time": time_l}
