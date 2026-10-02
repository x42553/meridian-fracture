class_name UiOptRow
extends HBoxContainer
## One row of an options page, generated from an `AppSettingsSchema` row (ui.md 5.18): label, the control that fits the row type
## (check box, slider with a value label, drop-down, line edit, spin box, number pair), a reset arrow that shows only while the
## value differs from the default, and a disabled state with a reason tooltip for rows a capability guard rejects.
## The row never writes settings itself: it emits `changed(id, value)` and the page applies it.

signal changed(id: String, value: Variant)
signal reset_requested(id: String)

const LABEL_W: float = 400.0
const CONTROL_W: float = 440.0

var id: String = ""
var row: Dictionary = {}

var _label: Label = null
var _ctl: Control = null
var _value_label: Label = null
var _reset: Button = null
var _muted: bool = false
var _busy: bool = false  ## true while `show_value` sets the control (no `changed`)


## Builds the row for a schema `row` showing `value` (null = the preset's own value for preset rows).
static func make(schema_row: Dictionary, value: Variant, is_default: bool) -> UiOptRow:
	var r: UiOptRow = UiOptRow.new()
	r._build(schema_row)
	r.show_value(value, is_default)
	return r


func _build(schema_row: Dictionary) -> void:
	row = schema_row
	id = str(row["id"])
	add_theme_constant_override("separation", UiMetrics.SP_3)
	custom_minimum_size = Vector2(0.0, 40.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_label = UiScreenKit.label(UiOptionsText.label(id), &"", false, HORIZONTAL_ALIGNMENT_LEFT, true)
	_label.custom_minimum_size = Vector2(LABEL_W, 0.0)
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_label)
	_ctl = _make_control()
	add_child(_ctl)
	_reset = Button.new()
	_reset.text = "↺"
	_reset.flat = true
	_reset.focus_mode = Control.FOCUS_ALL
	_reset.custom_minimum_size = Vector2(34.0, 34.0)
	_reset.tooltip_text = "Reset to default"
	_reset.accessibility_name = "Reset %s to default" % _label.text
	_reset.pressed.connect(func() -> void: reset_requested.emit(id))
	add_child(_reset)
	var tip: String = UiOptionsText.tip(id)
	_label.tooltip_text = tip
	if _ctl.tooltip_text.is_empty():
		_ctl.tooltip_text = tip
	UiA11y.name_text(_ctl, _label.text)


func label_text() -> String:
	return _label.text


func control() -> Control:
	return _ctl


func reset_button() -> Button:
	return _reset


func _make_control() -> Control:
	var type: int = int(row["type"])
	match type:
		AppSettingsSchema.T.BOOL:
			var cb: CheckButton = CheckButton.new()
			cb.focus_mode = Control.FOCUS_ALL
			cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cb.custom_minimum_size = Vector2(64.0, 0.0)
			cb.toggled.connect(func(on: bool) -> void:
				if not _busy:
					changed.emit(id, on))
			return cb
		AppSettingsSchema.T.INT, AppSettingsSchema.T.FLOAT:
			return _make_number(type == AppSettingsSchema.T.FLOAT)
		AppSettingsSchema.T.CHOICE:
			return _make_choice()
		AppSettingsSchema.T.STRING:
			var le: LineEdit = LineEdit.new()
			le.custom_minimum_size = Vector2(CONTROL_W, 34.0)
			le.max_length = int(row.get("max_len", 0))
			le.focus_mode = Control.FOCUS_ALL
			le.text_submitted.connect(func(t: String) -> void:
				if not _busy:
					changed.emit(id, t))
			le.focus_exited.connect(func() -> void:
				if not _busy:
					changed.emit(id, le.text))
			return le
		AppSettingsSchema.T.VECTOR2I:
			return _make_size()
	var l: Label = UiScreenKit.label("(unsupported)", &"DimLabel")
	return l


func _make_number(is_float: bool) -> Control:
	var lo: float = float(row["min"])
	var hi: float = float(row["max"])
	var step: float = float(row["step"])
	if hi - lo > 2000.0 and not is_float:
		var sp: SpinBox = SpinBox.new()
		sp.min_value = lo
		sp.max_value = hi
		sp.step = step
		sp.custom_minimum_size = Vector2(CONTROL_W * 0.5, 34.0)
		sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sp.value_changed.connect(func(v: float) -> void:
			if not _busy:
				changed.emit(id, int(v)))
		return sp
	var box: HBoxContainer = HBoxContainer.new()
	box.custom_minimum_size = Vector2(CONTROL_W, 0.0)
	box.add_theme_constant_override("separation", UiMetrics.SP_3)
	var sl: HSlider = HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(150.0, 28.0)
	sl.focus_mode = Control.FOCUS_ALL
	sl.value_changed.connect(func(v: float) -> void:
		_value_label.text = UiOptionsText.value_text(id, _num(v, is_float))
		if not _busy:
			changed.emit(id, _num(v, is_float)))
	box.add_child(sl)
	_value_label = UiScreenKit.label("")
	_value_label.custom_minimum_size = Vector2(78.0, 0.0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_value_label)
	return box


static func _num(v: float, is_float: bool) -> Variant:
	if is_float:
		return v
	return int(v)


func _make_choice() -> Control:
	var ob: OptionButton = OptionButton.new()
	ob.custom_minimum_size = Vector2(CONTROL_W, 34.0)
	ob.focus_mode = Control.FOCUS_ALL
	ob.fit_to_longest_item = false
	var choices: Array = row["choices"] as Array
	for i: int in choices.size():
		var c: Dictionary = choices[i]
		ob.add_item(UiOptionsText.choice(id, c["value"]), i)
		ob.set_item_metadata(i, c["value"])
		var g: StringName = StringName(c.get("guard", &""))
		if g != &"" and not AppSettingsSchema.guard_ok(g):
			ob.set_item_disabled(i, true)
			ob.set_item_tooltip(i, UiOptionsText.guard_reason(g))
	ob.item_selected.connect(func(i: int) -> void:
		if not _busy:
			changed.emit(id, ob.get_item_metadata(i)))
	return ob


func _make_size() -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.custom_minimum_size = Vector2(CONTROL_W, 0.0)
	box.add_theme_constant_override("separation", UiMetrics.SP_2)
	for axis: int in 2:
		var sp: SpinBox = SpinBox.new()
		sp.min_value = float((row["min"] as Vector2i)[axis]) if row["min"] != null else 320.0
		sp.max_value = 8192.0
		sp.step = 2.0
		sp.custom_minimum_size = Vector2(120.0, 34.0)
		sp.value_changed.connect(func(_v: float) -> void:
			if not _busy:
				changed.emit(id, Vector2i(int((box.get_child(0) as SpinBox).value), int((box.get_child(2) as SpinBox).value))))
		box.add_child(sp)
		if axis == 0:
			box.add_child(UiScreenKit.label("x", &"DimLabel"))
	return box


## Shows `value` without emitting `changed`.
func show_value(value: Variant, is_default: bool) -> void:
	_busy = true
	var type: int = int(row["type"])
	match type:
		AppSettingsSchema.T.BOOL:
			(_ctl as CheckButton).button_pressed = bool(value)
		AppSettingsSchema.T.INT, AppSettingsSchema.T.FLOAT:
			var v: float = float(value) if value != null else float(row["min"])
			if _ctl is SpinBox:
				(_ctl as SpinBox).value = v
			else:
				var sl: HSlider = _ctl.get_child(0) as HSlider
				sl.value = v
				_value_label.text = UiOptionsText.value_text(id, _num(v, type == AppSettingsSchema.T.FLOAT))
		AppSettingsSchema.T.CHOICE:
			var ob: OptionButton = _ctl as OptionButton
			ob.select(-1)
			for i: int in ob.item_count:
				if ob.get_item_metadata(i) == value:
					ob.select(i)
					break
		AppSettingsSchema.T.STRING:
			var le: LineEdit = _ctl as LineEdit
			if le.text != str(value):
				le.text = str(value)
		AppSettingsSchema.T.VECTOR2I:
			var sz: Vector2i = value as Vector2i if value is Vector2i else Vector2i(1600, 900)
			(_ctl.get_child(0) as SpinBox).value = sz.x
			(_ctl.get_child(2) as SpinBox).value = sz.y
	_reset.modulate.a = 0.0 if is_default else 1.0
	_reset.disabled = is_default
	_reset.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_default else Control.MOUSE_FILTER_STOP
	_busy = false


## Enables or disables the whole row; a disabled row explains itself in its tooltip.
func set_enabled(on: bool, reason: String = "") -> void:
	_muted = not on
	_set_disabled(_ctl, not on)
	_label.modulate = Color(1, 1, 1, 1.0 if on else 0.55)
	if not on:
		_label.tooltip_text = reason
		_ctl.tooltip_text = reason
		_reset.disabled = true
	else:
		_label.tooltip_text = UiOptionsText.tip(id)
		_ctl.tooltip_text = UiOptionsText.tip(id)


func is_enabled() -> bool:
	return not _muted


static func _set_disabled(c: Control, off: bool) -> void:
	if c is BaseButton:
		(c as BaseButton).disabled = off
	elif c is Range:
		if c is Slider:
			(c as Slider).editable = not off
		elif c is SpinBox:
			(c as SpinBox).editable = not off
	elif c is LineEdit:
		(c as LineEdit).editable = not off
	for ch: Node in c.get_children():
		if ch is Control:
			_set_disabled(ch as Control, off)


## Puts the keyboard focus on the main control.
func focus_control() -> void:
	var f: Control = _ctl
	if f is HBoxContainer:
		f = f.get_child(0) as Control
	if f != null and f.focus_mode != Control.FOCUS_NONE:
		f.grab_focus()
