class_name UiObjectivesPanel
extends PanelContainer
## The objectives panel of a scripted mission (MIS2): primary objectives, then the optional ones, each with a state mark (open ring,
## green check, red cross). A click on the header (or the `toggle_objectives` hotkey) collapses it to the header line. An objective
## that appears or changes state flashes for `FLASH_S`; while the panel is collapsed such a change shows the list for `PEEK_S` and
## the header blinks, so a new objective is never missed. Data comes from `UiMissionModel`; the panel never reads the sim.

signal collapsed_changed(collapsed: bool)

const WIDTH: float = 344.0
const FLASH_S: float = 4.0
const PEEK_S: float = 7.0
const ROW_GAP: int = 6

var model: UiMissionModel = null
var collapsed: bool = false
## Text of the hotkey chip in the header ("Ctrl+O"); set by the HUD from the keymap.
var hotkey_text: String = "":
	set(v):
		hotkey_text = v
		if _head != null:
			_head.queue_redraw()

var _head: _Head = null
var _body: VBoxContainer = null
var _rows: Array[Dictionary] = []  ## {panel, mark, label, idx, state}
var _signature: String = ""
var _peek_until: int = 0
var _blink_until: int = 0


func _init() -> void:
	theme_type_variation = &"InsetPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0.0)
	set_process(false)
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 8)
	add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	_head = _Head.new()
	_head.panel = self
	v.add_child(_head)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", ROW_GAP)
	v.add_child(_body)


func setup(m: UiMissionModel) -> void:
	model = m
	refresh()


## Rebuilds the rows when the objectives or their states changed (cheap signature check); call after every `model.sync`.
## `changed`: the objective indices that changed in the last sync (they flash).
func refresh(changed: PackedInt32Array = PackedInt32Array()) -> void:
	if model == null or model.def == null:
		return
	var now: int = Time.get_ticks_msec()
	for i: int in changed:
		if model.obj_state[i] != UiMissionModel.S_HIDDEN:
			_blink_until = now + int(FLASH_S * 1000.0)
			if collapsed:
				_peek_until = now + int(PEEK_S * 1000.0)
	var rows: Array[Dictionary] = model.rows()
	var sig: String = ""
	for r: Dictionary in rows:
		sig += "%d:%d," % [int(r["idx"]), int(r["state"])]
	if sig != _signature:
		_signature = sig
		_rebuild(rows)
	_apply_visibility(now)
	_head.queue_redraw()
	set_process(not changed.is_empty() or _flashing(now))


func _rebuild(rows: Array[Dictionary]) -> void:
	for c: Node in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_rows.clear()
	var last_kind: int = -1
	for r: Dictionary in rows:
		var primary: bool = int(r["kind"]) == UiMissionModel.KIND_PRIMARY
		var group: int = 0 if primary else 1
		if group != last_kind:
			last_kind = group
			var cap: Label = UiScreenKit.label("PRIMARY" if primary else "OPTIONAL", &"CaptionLabel")
			_body.add_child(cap)
		var panel: PanelContainer = PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		sb.content_margin_left = 2.0
		sb.content_margin_right = 2.0
		sb.content_margin_top = 2.0
		sb.content_margin_bottom = 2.0
		panel.add_theme_stylebox_override("panel", sb)
		var h: HBoxContainer = HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		panel.add_child(h)
		var mark: UiObjectiveMark = UiObjectiveMark.new()
		mark.state = int(r["state"])
		mark.primary = primary
		h.add_child(mark)
		var label: Label = UiScreenKit.label(str(r["text"]), &"", true)
		label.custom_minimum_size = Vector2(WIDTH - 62.0, 0.0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st: int = int(r["state"])
		if st == UiMissionModel.S_COMPLETED:
			label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		elif st == UiMissionModel.S_FAILED:
			label.add_theme_color_override("font_color", UiPalette.semantic(&"danger"))
		h.add_child(label)
		_body.add_child(panel)
		_rows.append({"panel": panel, "mark": mark, "label": label, "idx": int(r["idx"]), "state": st, "sb": sb})


func _apply_visibility(now: int) -> void:
	_body.visible = (not collapsed) or now < _peek_until


# ---------------------------------------------------------------- state

func set_collapsed(on: bool) -> void:
	if collapsed == on:
		return
	collapsed = on
	_peek_until = 0
	_apply_visibility(Time.get_ticks_msec())
	_head.queue_redraw()
	collapsed_changed.emit(collapsed)


func toggle() -> void:
	set_collapsed(not collapsed)


func row_count() -> int:
	return _rows.size()


func row_text(i: int) -> String:
	return (_rows[i]["label"] as Label).text


func row_state(i: int) -> int:
	return int(_rows[i]["state"])


func row_index(i: int) -> int:
	return int(_rows[i]["idx"])


## Is row `i` still flashing (its objective changed less than `FLASH_S` ago)?
func is_flashing(i: int) -> bool:
	return _flash_left(int(_rows[i]["idx"]), Time.get_ticks_msec()) > 0.0


## Is the (collapsed) list peeking open because of a new objective?
func peeking() -> bool:
	return collapsed and _body.visible


func header_text() -> String:
	return _head.title_text()


func _flash_left(obj_idx: int, now: int) -> float:
	if model == null or obj_idx >= model.changed_msec.size() or model.changed_msec[obj_idx] == 0:
		return 0.0
	return maxf(FLASH_S - float(now - model.changed_msec[obj_idx]) / 1000.0, 0.0)


func _flashing(now: int) -> bool:
	if now < _blink_until or now < _peek_until:
		return true
	for r: Dictionary in _rows:
		if _flash_left(int(r["idx"]), now) > 0.0:
			return true
	return false


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	for r: Dictionary in _rows:
		var left: float = _flash_left(int(r["idx"]), now)
		var sb: StyleBoxFlat = r["sb"] as StyleBoxFlat
		if left <= 0.0:
			sb.bg_color = Color(acc, 0.0)
			continue
		var pulse: float = 0.5 + 0.5 * sin(float(now) / 1000.0 * 9.0)
		if UiMotion.reduce_flash:
			pulse = 1.0
		var st: int = int(r["state"])
		var base: Color = acc
		if st == UiMissionModel.S_COMPLETED:
			base = UiPalette.semantic(&"ok")
		elif st == UiMissionModel.S_FAILED:
			base = UiPalette.semantic(&"danger")
		sb.bg_color = Color(base, (0.10 + 0.22 * pulse) * minf(left, 1.0))
	if _body.visible != ((not collapsed) or now < _peek_until):
		_apply_visibility(now)
	_head.queue_redraw()
	if not _flashing(now):
		set_process(false)


# ---------------------------------------------------------------- header

class _Head extends Control:
	var panel: UiObjectivesPanel = null

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 28.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func title_text() -> String:
		if panel == null or panel.model == null:
			return "OBJECTIVES"
		var p: Vector2i = panel.model.progress(true)
		return "OBJECTIVES  %d / %d" % [p.x, p.y]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			panel.toggle()
			accept_event()

	func _draw() -> void:
		if panel == null:
			return
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
		var body: Font = UiFonts.get_font(UiFonts.Role.BODY)
		var base: float = size.y - 8.0
		var now: int = Time.get_ticks_msec()
		var blink: bool = now < panel._blink_until and int(float(now) / 280.0) % 2 == 0 and not UiMotion.reduce_flash
		var col: Color = UiPalette.TEXT if blink else acc
		draw_rect(Rect2(0.0, base - 13.0, 4.0, 15.0), col)
		draw_string(head, Vector2(12.0, base), title_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_HEAD, col)
		var x: float = size.x
		var glyph: int = UiGlyphs.Glyph.CHEVRON_DOWN if panel.collapsed else UiGlyphs.Glyph.CHEVRON_UP
		UiDraw.glyph(self, glyph, Rect2(Vector2(x - 20.0, base - 14.0), Vector2(16.0, 16.0)), UiPalette.TEXT_DIM, 1.6)
		x -= 28.0
		if panel.hotkey_text != "":
			var w: float = body.get_string_size(panel.hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(body, Vector2(x - w, base), panel.hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT_MUTE)
