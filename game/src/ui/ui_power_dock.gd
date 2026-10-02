class_name UiPowerDock
extends Control
## Support-power dock (ui.md 5.10.6, top left under the strip): the three powers (F5-F7) and the superweapon (F8) as
## 56-px buttons with clock sweeps, remaining seconds and hotkey badges. It mirrors the POWERS tab: `set_items` takes
## the `UiBuildItem`s in dock order (powers by slot, then the superweapon). LMB emits `power_pressed(power_idx)`, the
## superweapon emits `SUPERWEAPON`. Redraws only when a value changes (once per displayed second while cooling down).

signal power_pressed(power_idx: int)

const SUPERWEAPON: int = -2  ## `power_pressed` argument of the superweapon button
const KEYS: PackedStringArray = ["F5", "F6", "F7", "F8"]

var _items: Array[UiBuildItem] = []
var _hover: int = -1
var _down: int = -1
var _pulse: float = 1.0
var _pulse_acc: float = 0.0
var _sig: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # `_has_point` limits it to the buttons
	focus_mode = Control.FOCUS_NONE
	mouse_force_pass_scroll_events = false
	custom_minimum_size = Vector2(float(UiMetrics.DOCK_BTN) * 4.0 + float(UiMetrics.DOCK_GAP) * 3.0, float(UiMetrics.DOCK_BTN))
	set_process(false)


## Dock order items (<= 4). Redraws only when a displayed value changed.
func set_items(list: Array[UiBuildItem]) -> void:
	_items = list
	var parts: Array = []
	for it: UiBuildItem in list:
		parts.append([it.state, it.remaining_whole_seconds(), it.progress_permille / 10, it.hotkey_label])
	var sig: int = hash(parts)
	if sig != _sig:
		_sig = sig
		queue_redraw()
	var pulsing: bool = false
	for it2: UiBuildItem in list:
		if it2.state == UiBuildItem.State.AVAILABLE:
			pulsing = true
	set_process(pulsing)


## Number of buttons shown (powers by slot, then the superweapon).
func item_count() -> int:
	return _items.size()


## The item behind button `i` (null when out of range): the F5..F8 hotkeys read it.
func item_at(i: int) -> UiBuildItem:
	return _items[i] if i >= 0 and i < _items.size() else null


## The key shown on button `i`: the item's label, which is the keymap's current binding ("" = unbound).
func key_of(i: int) -> String:
	return _items[i].hotkey_label if i >= 0 and i < _items.size() else ""


func button_rect(i: int) -> Rect2:
	var s: float = float(UiMetrics.DOCK_BTN)
	return Rect2(float(i) * (s + float(UiMetrics.DOCK_GAP)), 0.0, s, s)


func _at(p: Vector2) -> int:
	for i: int in _items.size():
		if button_rect(i).has_point(p):
			return i
	return -1


## The whole control is mouse-transparent except over the buttons (the world stays clickable between them).
func _has_point(point: Vector2) -> bool:
	return _at(point) >= 0


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var h: int = _at(mm.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = _at(mb.position)
		else:
			var i: int = _at(mb.position)
			if i >= 0 and i == _down:
				_activate(i)
			_down = -1
		queue_redraw()
		accept_event()


func _activate(i: int) -> void:
	var it: UiBuildItem = _items[i]
	power_pressed.emit(SUPERWEAPON if it.kind == UiBuildItem.Kind.SUPERWEAPON else it.def_idx)


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = _at(at_position)
	if i < 0:
		return ""
	var it: UiBuildItem = _items[i]
	var spec: Dictionary = {"title": it.display_name, "tag": "SUPERWEAPON" if it.kind == UiBuildItem.Kind.SUPERWEAPON else "SUPPORT POWER"}
	var stats: Array[Dictionary] = []
	if it.cost > 0:
		stats.append({"label": "COST", "value": "$" + UiBuildItem.group_digits(it.cost)})
	if it.total_seconds > 0.0:
		stats.append({"label": "COOLDOWN", "value": UiBuildItem.mmss(int(ceilf(it.total_seconds)))})
	stats.append({"label": "HOTKEY", "value": _items[i].hotkey_label if i < _items.size() else ""})
	spec["stats"] = stats
	if it.description != "":
		spec["text"] = it.description
	if it.requires_text != "":
		spec["warn"] = "Requires " + it.requires_text
	elif it.reason_text != "":
		spec["warn"] = it.reason_text
	return UiTooltipBody.encode(spec)


func _make_custom_tooltip(for_text: String) -> Object:
	return UiTooltipBody.make_from_text(for_text)


func _process(delta: float) -> void:
	_pulse_acc += delta
	if _pulse_acc >= 1.0 / 15.0:
		_pulse_acc = 0.0
		_pulse = UiMotion.pulse(float(Time.get_ticks_msec()) / 1000.0)
		queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			_down = -1
			queue_redraw()
		NOTIFICATION_THEME_CHANGED:
			queue_redraw()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
	var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	for i: int in _items.size():
		var it: UiBuildItem = _items[i]
		var r: Rect2 = button_rect(i)
		var st: StringName = &"normal"
		if i == _down:
			st = &"pressed"
		elif it.state == UiBuildItem.State.LOCKED:
			st = &"disabled"
		elif i == _hover:
			st = &"hover"
		draw_style_box(get_theme_stylebox(st, &"CommandButton"), r)
		var locked: bool = it.state == UiBuildItem.State.LOCKED or it.state == UiBuildItem.State.BLOCKED
		var gcol: Color = UiPalette.TEXT_MUTE if locked else (acc.lightened(0.2) if it.state == UiBuildItem.State.AVAILABLE else UiPalette.TEXT_DIM)
		UiGlyphs.draw(self, it.role_glyph, Rect2(r.position + Vector2(14.0, 8.0), Vector2(28.0, 28.0)), gcol, 1.8)
		var inner: Rect2 = r.grow(-2.0)
		match it.state:
			UiBuildItem.State.COOLDOWN, UiBuildItem.State.BLOCKED, UiBuildItem.State.ON_HOLD:
				if it.progress_permille < 1000:
					var poly: PackedVector2Array = UiDraw.rect_sector(inner, it.progress(), 1.0)
					if poly.size() >= 3:
						draw_colored_polygon(poly, Color(0, 0, 0, 0.62) if it.state == UiBuildItem.State.COOLDOWN else Color(0.32, 0.2, 0.0, 0.62))
				if it.state == UiBuildItem.State.COOLDOWN:
					draw_string(head, Vector2(r.position.x, r.position.y + 32.0), UiBuildItem.mmss(it.remaining_whole_seconds()), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color.WHITE)
				elif it.state == UiBuildItem.State.BLOCKED:
					UiGlyphs.draw(self, UiGlyphs.Glyph.NO_POWER, Rect2(r.position + Vector2(18.0, 12.0), Vector2(20.0, 20.0)), UiPalette.WARN, 1.6)
				else:
					draw_string(head, Vector2(r.position.x, r.position.y + 30.0), "LAUNCH", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, UiPalette.WARN)
			UiBuildItem.State.AVAILABLE:
				draw_rect(inner, Color(UiPalette.OK, 0.10 + 0.14 * _pulse))
				draw_rect(inner, Color(UiPalette.OK, 0.5 + 0.4 * _pulse), false, 1.5)
			UiBuildItem.State.LOCKED:
				UiGlyphs.draw(self, UiGlyphs.Glyph.LOCK, Rect2(r.position + Vector2(18.0, 12.0), Vector2(20.0, 20.0)), UiPalette.TEXT_DIM, 1.6)
		draw_string(num, Vector2(r.position.x + 4.0, r.position.y + 13.0), key_of(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_DIM)
		if it.cost > 0 and it.state != UiBuildItem.State.COOLDOWN:
			var cc: Color = UiPalette.DANGER if it.state == UiBuildItem.State.UNAFFORDABLE else UiPalette.CREDITS
			draw_string(num, Vector2(r.position.x, r.end.y - 5.0), "$" + str(it.cost), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, cc)
