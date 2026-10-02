class_name UiScoreboard
extends PanelContainer
## The F2 scoreboard of the observer HUD (ui.md 5.16.3): player (colour bar, emblem, name), team, credits, income per minute, units,
## structures, kills, losses, score and APM, best score first. Fed with `UiObserverModel.rows`; it only draws them. Mouse
## transparent, so the world below stays usable while it is open.

const COLS: Array[Dictionary] = [
	{"id": "name", "title": "PLAYER", "w": 232.0, "align": 0}, {"id": "team", "title": "TEAM", "w": 54.0, "align": 1},
	{"id": "credits", "title": "CREDITS", "w": 92.0, "align": 2}, {"id": "income", "title": "INCOME/MIN", "w": 100.0, "align": 2},
	{"id": "units", "title": "UNITS", "w": 62.0, "align": 2}, {"id": "structs", "title": "BLDG", "w": 60.0, "align": 2},
	{"id": "kills", "title": "KILLS", "w": 62.0, "align": 2}, {"id": "losses", "title": "LOST", "w": 62.0, "align": 2},
	{"id": "score", "title": "SCORE", "w": 78.0, "align": 2}, {"id": "apm", "title": "APM", "w": 52.0, "align": 2},
]

var _box: VBoxContainer = null
var _rows_box: VBoxContainer = null
var _title: Label = null
var _cells: Dictionary = {}
var _order: Array[int] = []


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var m: MarginContainer = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 4)
	m.add_child(_box)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.text = "SCOREBOARD"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_title)
	_box.add_child(_head_row())
	_rows_box = VBoxContainer.new()
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override("separation", 3)
	_box.add_child(_rows_box)


func _head_row() -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 0)
	for c: Dictionary in COLS:
		var l: Label = Label.new()
		l.text = str(c["title"])
		l.theme_type_variation = &"CaptionLabel"
		l.custom_minimum_size = Vector2(float(c["w"]), 0.0)
		l.horizontal_alignment = _align(int(c["align"]))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
	return h


static func _align(a: int) -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_LEFT if a == 0 else (HORIZONTAL_ALIGNMENT_CENTER if a == 1 else HORIZONTAL_ALIGNMENT_RIGHT)


func toggle() -> void:
	visible = not visible


## `rows`: `UiObserverModel.rows`; `tick`: the sim tick for the title.
func set_rows(rows: Array[Dictionary], tick: int) -> void:
	_title.text = "SCOREBOARD   %s" % UiFormatLite.clock(tick * SimConfig.TICK_MS / 1000)
	var sorted: Array[Dictionary] = rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["active"]) != bool(b["active"]):
			return bool(a["active"])
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["pid"]) < int(b["pid"]))
	var order: Array[int] = []
	for r: Dictionary in sorted:
		order.append(int(r["pid"]))
	if order != _order:
		_rebuild(sorted)
		_order = order
	for r2: Dictionary in sorted:
		_fill(int(r2["pid"]), r2)


func row_count() -> int:
	return _order.size()


## The text of one cell (tests).
func cell_text(pid: int, id: String) -> String:
	var l: Label = (_cells.get(pid, {}) as Dictionary).get(id) as Label
	return l.text if l != null else ""


func _rebuild(sorted: Array[Dictionary]) -> void:
	for c: Node in _rows_box.get_children():
		c.queue_free()
	_cells.clear()
	for r: Dictionary in sorted:
		var pid: int = int(r["pid"])
		var row: PanelContainer = PanelContainer.new()
		row.theme_type_variation = &"InsetPanel"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h: HBoxContainer = HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 0)
		row.add_child(h)
		var cells: Dictionary = {}
		for c: Dictionary in COLS:
			if str(c["id"]) == "name":
				h.add_child(_name_cell(r, cells, float(c["w"])))
				continue
			var l: Label = Label.new()
			l.custom_minimum_size = Vector2(float(c["w"]), 0.0)
			l.horizontal_alignment = _align(int(c["align"]))
			l.theme_type_variation = &"NumLabel"
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(l)
			cells[str(c["id"])] = l
		_cells[pid] = cells
		_rows_box.add_child(row)


func _name_cell(r: Dictionary, cells: Dictionary, w: float) -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.custom_minimum_size = Vector2(w, 34.0)
	h.add_theme_constant_override("separation", 8)
	var bar: ColorRect = ColorRect.new()
	bar.color = UiPalette.team(int(r["color"]))
	bar.custom_minimum_size = Vector2(5.0, 30.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var badge: UiFactionBadge = UiFactionBadge.new(str(r["faction"]), 28.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var l: Label = Label.new()
	l.theme_type_variation = &"NameLabel"
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	cells["name"] = l
	cells["bar"] = bar
	cells["badge"] = badge
	return h


func _fill(pid: int, r: Dictionary) -> void:
	var cells: Dictionary = _cells.get(pid, {}) as Dictionary
	if cells.is_empty():
		return
	var active: bool = bool(r["active"])
	(cells["name"] as Label).text = str(r["name"]) + ("" if active else "  (out)")
	(cells["name"] as Label).modulate = Color.WHITE if active else Color(1.0, 1.0, 1.0, 0.5)
	(cells["badge"] as UiFactionBadge).muted = not active
	var team: int = int(r["team"])
	var vals: Dictionary = {"team": "T%d" % team if team >= 1 and team <= 4 else "-", "credits": UiFormatLite.credits(int(r["credits"])),
		"income": "+" + UiFormatLite.credits(int(r["income"])), "units": str(int(r["units"])), "structs": str(int(r["structs"])),
		"kills": str(int(r["kills"])), "losses": str(int(r["losses"])), "score": UiFormatLite.credits(int(r["score"])), "apm": str(int(r["apm"]))}
	for k: String in vals:
		var l: Label = cells.get(k) as Label
		if l != null:
			l.text = str(vals[k])
			l.modulate = Color.WHITE if active else Color(1.0, 1.0, 1.0, 0.5)
