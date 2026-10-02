class_name UiTabBar
extends Control
## Segmented tab strip, glyph or text tabs with badges (ui.md 2.3). One custom-drawn Control; tabs use the `TabButton`
## recipe of the theme and a 3-px accent underline marks the selected one. Tabs: `[{id: StringName, text: String,
## glyph: int, badge: String, tip: String, enabled: bool}]`; glyph tabs are TAB_SIZE (38) squares with 2 px gaps, text tabs
## size to their label. `stretch` spreads the tabs over the full width instead. HUD default: no focus; menus call
## `set_focusable(true)` and use Left / Right / Home / End.

signal tab_selected(index: int, id: StringName)

const UNDERLINE: float = 3.0

var stretch: bool = false
var selected: int = 0

var _tabs: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _hover: int = -1
var _down: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, float(UiMetrics.TAB_SIZE))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_focusable(on: bool) -> void:
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


## Replaces the tabs (keeps the selection index when still valid).
func set_tabs(tabs: Array[Dictionary]) -> void:
	_tabs = tabs
	selected = clampi(selected, 0, maxi(tabs.size() - 1, 0))
	_relayout()
	update_minimum_size()
	queue_redraw()


func tab_count() -> int:
	return _tabs.size()


func selected_id() -> StringName:
	if selected < 0 or selected >= _tabs.size():
		return &""
	return StringName(_tabs[selected].get("id", &""))


## Selects a tab by index; `emit` fires `tab_selected` (user clicks always do).
func select(index: int, emit: bool = false) -> void:
	if index < 0 or index >= _tabs.size() or not _enabled(index):
		return
	var changed: bool = index != selected
	selected = index
	queue_redraw()
	if emit or changed:
		if emit:
			tab_selected.emit(index, selected_id())


## Selects the next (direction > 0) or previous enabled tab, wrapping around (the Tab / Shift+Tab hotkeys); true when the
## selection changed. `emit` fires `tab_selected` like a click.
func step(direction: int, emit: bool = true) -> bool:
	var n: int = _tabs.size()
	if n == 0:
		return false
	var dir: int = 1 if direction >= 0 else -1
	for k: int in range(1, n):
		var j: int = posmod(selected + dir * k, n)
		if _enabled(j):
			select(j, emit)
			return true
	return false


func select_id(id: StringName, emit: bool = false) -> void:
	for i in _tabs.size():
		if StringName(_tabs[i].get("id", &"")) == id:
			select(i, emit)
			return


## Sets or clears (empty string) the badge of a tab.
func set_badge(id: StringName, badge: String) -> void:
	for t in _tabs:
		if StringName(t.get("id", &"")) == id:
			t["badge"] = badge
	queue_redraw()


func tab_rect(index: int) -> Rect2:
	return _rects[index] if index >= 0 and index < _rects.size() else Rect2()


func _enabled(i: int) -> bool:
	return bool(_tabs[i].get("enabled", true))


func _tab_width(i: int) -> float:
	var t: Dictionary = _tabs[i]
	var txt: String = String(t.get("text", ""))
	if txt == "":
		return float(UiMetrics.TAB_SIZE)
	var f: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	return maxf(float(UiMetrics.TAB_SIZE), f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_LIST).x + 28.0)


func _relayout() -> void:
	_rects.clear()
	var n: int = _tabs.size()
	if n == 0:
		return
	var gap: float = float(UiMetrics.TAB_GAP)
	var h: float = maxf(size.y, float(UiMetrics.TAB_SIZE))
	if stretch and size.x > 0.0:
		var w: float = (size.x - gap * float(n - 1)) / float(n)
		for i in n:
			_rects.append(Rect2(float(i) * (w + gap), 0.0, w, h))
		return
	var x: float = 0.0
	for i in n:
		var w2: float = _tab_width(i)
		_rects.append(Rect2(x, 0.0, w2, h))
		x += w2 + gap


func _get_minimum_size() -> Vector2:
	if stretch or _tabs.is_empty():
		return Vector2(0.0, float(UiMetrics.TAB_SIZE))
	var w: float = 0.0
	for i in _tabs.size():
		w += _tab_width(i) + float(UiMetrics.TAB_GAP)
	return Vector2(w - float(UiMetrics.TAB_GAP), float(UiMetrics.TAB_SIZE))


func _index_at(p: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].has_point(p):
			return i
	return -1


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = _index_at(at_position)
	return String(_tabs[i].get("tip", "")) if i >= 0 else ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_relayout()
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			_down = -1
			queue_redraw()
		NOTIFICATION_THEME_CHANGED, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _index_at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var i: int = _index_at(mb.position)
		if mb.pressed:
			_down = i
		else:
			if i >= 0 and i == _down and _enabled(i):
				selected = i
				tab_selected.emit(i, selected_id())
			_down = -1
		queue_redraw()
		accept_event()
		return
	if not has_focus() or not event.is_pressed():
		return
	var step: int = 0
	if event.is_action_pressed(&"ui_left"):
		step = -1
	elif event.is_action_pressed(&"ui_right"):
		step = 1
	elif event.is_action_pressed(&"ui_home"):
		step = -_tabs.size()
	elif event.is_action_pressed(&"ui_end"):
		step = _tabs.size()
	if step != 0 and not _tabs.is_empty():
		var j: int = clampi(selected + step, 0, _tabs.size() - 1)
		while j != selected and not _enabled(j):
			j += 1 if step > 0 else -1
			if j < 0 or j >= _tabs.size():
				j = selected
		if j != selected:
			selected = j
			tab_selected.emit(j, selected_id())
			queue_redraw()
		accept_event()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var body: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
	for i in _tabs.size():
		var t: Dictionary = _tabs[i]
		var r: Rect2 = _rects[i]
		var on: bool = i == selected
		var en: bool = _enabled(i)
		var state: StringName = &"normal"
		if not en:
			state = &"disabled"
		elif on or i == _down:
			state = &"pressed"
		elif i == _hover:
			state = &"hover"
		draw_style_box(get_theme_stylebox(state, &"TabButton"), r)
		var col: Color = UiPalette.TEXT_DIM
		if not en:
			col = UiPalette.TEXT_DISABLED
		elif on:
			col = acc
		elif i == _hover:
			col = UiPalette.TEXT
		var txt: String = String(t.get("text", ""))
		var glyph: int = int(t.get("glyph", -1))
		var cy: float = r.position.y + (r.size.y - UNDERLINE) * 0.5
		if glyph >= 0 and txt == "":
			var gs: float = minf(r.size.x, r.size.y) * 0.52
			UiDraw.glyph(self, glyph, Rect2(Vector2(r.get_center().x - gs * 0.5, cy - gs * 0.5), Vector2(gs, gs)), col, 1.8)
		elif txt != "":
			var tw: float = body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_LIST).x
			var x: float = r.get_center().x - tw * 0.5
			if glyph >= 0:
				var gs2: float = 18.0
				x += gs2 * 0.5 + 3.0
				UiDraw.glyph(self, glyph, Rect2(Vector2(x - tw * 0.0 - gs2 - 6.0, cy - gs2 * 0.5), Vector2(gs2, gs2)), col, 1.6)
			UiDraw.shadow_string(self, body, Vector2(x, cy + 5.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_LIST, col)
		if on and en:
			draw_rect(Rect2(r.position.x + 2.0, r.end.y - UNDERLINE, r.size.x - 4.0, UNDERLINE), acc)
		var badge: String = String(t.get("badge", ""))
		if badge != "":
			var bw: float = maxf(18.0, body.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_SMALL).x + 8.0)
			var br := Rect2(r.end.x - bw + 3.0, r.position.y - 5.0, bw, 18.0)
			draw_rect(br, get_theme_color(&"accent2", UiTheme.ACCENT_TYPE))
			draw_string(body, Vector2(br.position.x, br.position.y + 14.0), badge, HORIZONTAL_ALIGNMENT_CENTER, bw, UiMetrics.FS_SMALL, UiPalette.TEXT_ON_ACCENT)
	if has_focus() and selected >= 0 and selected < _rects.size():
		draw_style_box(get_theme_stylebox(&"focus", &"TabButton"), _rects[selected])
