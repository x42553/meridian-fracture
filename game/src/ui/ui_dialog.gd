class_name UiDialog
extends PanelContainer
## Dialog base (ui.md 3.5): title, body, button row, `closed(result)` (0 = cancel / Esc / close, 1+ = the result code of
## the pressed button). Shown through `UiDialogStack` (dim, focus trap, Esc). Built from code; subclasses add
## `set_content(control)` for richer bodies (text input, key conflict, host game ...).

signal closed(result: int)

## Escape closes with result 0 (a dialog that must be answered sets this false).
var dismiss_on_escape: bool = true
var result: int = 0

var _title: Label
var _body: VBoxContainer
var _buttons: HBoxContainer
var _default_button: Button = null
var _done: bool = false


func _init(title_text: String = "", width: int = UiMetrics.DIALOG_W_MIN) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(float(clampi(width, UiMetrics.DIALOG_W_MIN, UiMetrics.DIALOG_W_MAX)), 0.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = &"DialogTitle"
	_title.text = title_text.to_upper()
	col.add_child(_title)
	var sep := HSeparator.new()
	col.add_child(sep)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UiMetrics.SP_2)
	col.add_child(_body)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", UiMetrics.SP_2)
	col.add_child(_buttons)
	accessibility_name = title_text


func set_title(text: String) -> void:
	_title.text = text.to_upper()
	accessibility_name = text


func get_title() -> String:
	return _title.text


## Adds a wrapped paragraph to the body; returns the Label.
func add_text(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(custom_minimum_size.x - 24.0, 0.0)
	if variation != &"":
		l.theme_type_variation = variation
	_body.add_child(l)
	return l


## Adds an arbitrary control to the body.
func set_content(c: Control) -> void:
	_body.add_child(c)


## Adds a button (`kind`: &"normal", &"primary", &"danger"). `result_code` >= 1 is what `closed` reports.
## The first primary button (or the first button) is the default focus.
func add_button(text: String, result_code: int, kind: StringName = &"normal") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(110.0, 38.0)
	b.accessibility_name = text
	match kind:
		&"primary": b.theme_type_variation = &"PrimaryButton"
		&"danger": b.theme_type_variation = &"DangerButton"
	b.pressed.connect(close.bind(result_code))
	_buttons.add_child(b)
	if _default_button == null or kind == &"primary":
		_default_button = b
	return b


func button_count() -> int:
	return _buttons.get_child_count()


func get_button(i: int) -> Button:
	return _buttons.get_child(i) as Button


## The control that takes focus when the dialog opens.
func default_focus() -> Control:
	return _default_button


## Closes with `result_code` (idempotent); the stack removes and frees the dialog.
func close(result_code: int = 0) -> void:
	if _done:
		return
	_done = true
	result = result_code
	closed.emit(result_code)


func is_closed() -> bool:
	return _done


## Yes / No confirmation: `closed(1)` on yes, `closed(0)` on no / Esc.
static func confirm(title_key: StringName, body_key: StringName, args: Dictionary = {}, yes_key: StringName = &"ui.yes", no_key: StringName = &"ui.no") -> UiDialog:
	var d := UiDialog.new(UiA11y.resolve_text(title_key, args))
	d.add_text(UiA11y.resolve_text(body_key, args))
	d.add_button(UiA11y.resolve_text(no_key), 0)
	d.add_button(UiA11y.resolve_text(yes_key), 1, &"primary")
	return d


## One-button message: `closed(1)` on OK / Esc gives 0.
static func message(title_key: StringName, body: String, ok_key: StringName = &"ui.ok") -> UiDialog:
	var d := UiDialog.new(UiA11y.resolve_text(title_key))
	d.add_text(body)
	d.add_button(UiA11y.resolve_text(ok_key), 1, &"primary")
	return d
