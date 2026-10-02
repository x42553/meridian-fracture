class_name UiToast
extends PanelContainer
## Non-modal notice (ui.md 2.3): info / warn / error with optional action buttons (Open logs folder, Copy report,
## Watch recovered replay, Undo) and auto-dismiss (in 0.15 s, hold 4 s, out 0.3 s; the timer pauses while hovered and an
## action toast holds twice as long). The host (`AppScenes.toast`) stacks toasts; this is one toast.
## Actions: `[{label: String, call: Callable}]` (the label may come from `UiA11y.resolve_text`).

enum Severity { INFO = 0, WARN = 1, ERROR = 2 }

## Emitted with the action index when an action button was pressed (the action's `call` runs first).
signal action_pressed(index: int)
## Emitted once, right before the toast frees itself.
signal dismissed()

var severity: int = Severity.INFO
var hold_s: float = UiMotion.TOAST_HOLD_S

var _age: float = 0.0
var _hover: bool = false
var _leaving: bool = false
var _label: Label
var _mark: Mark
var _row: HBoxContainer
var _actions: HBoxContainer = null
var _col: VBoxContainer


## Creates a toast. `actions` entries: `{label: String, call: Callable}`.
static func make(text: String, sev: int = Severity.INFO, actions: Array[Dictionary] = []) -> UiToast:
	var t := UiToast.new()
	t.setup(text, sev, actions)
	return t


func _init() -> void:
	theme_type_variation = &"RibbonPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(240.0, 44.0)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", UiMetrics.SP_2)
	add_child(_col)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", UiMetrics.SP_3)
	_col.add_child(_row)
	_mark = Mark.new()
	_row.add_child(_mark)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.custom_minimum_size = Vector2(150.0, 0.0)
	_row.add_child(_label)


func setup(text: String, sev: int, actions: Array[Dictionary]) -> void:
	severity = sev
	_label.text = text
	accessibility_name = text
	accessibility_live = AccessibilityServer.LIVE_POLITE
	_mark.severity = sev
	if not actions.is_empty():
		_actions = HBoxContainer.new()
		_actions.alignment = BoxContainer.ALIGNMENT_END
		_actions.add_theme_constant_override("separation", UiMetrics.SP_2)
		_col.add_child(_actions)
	for i in actions.size():
		var b := Button.new()
		b.text = String(actions[i].get("label", ""))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0.0, 32.0)
		b.accessibility_name = b.text
		b.pressed.connect(_on_action.bind(i, actions[i].get("call", Callable()) as Callable))
		_actions.add_child(b)
	if not actions.is_empty():
		hold_s *= 2.0
	var close := UiIconButton.new()
	close.glyph = UiDraw.G_CLOSE
	close.custom_minimum_size = Vector2(32.0, 32.0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.accessibility_name = UiA11y.resolve_text(&"ui.close")
	close.pressed.connect(dismiss)
	_row.add_child(close)


func _ready() -> void:
	modulate.a = 0.0 if not UiMotion.reduce_motion else 1.0


func _on_action(index: int, cb: Callable) -> void:
	if cb.is_valid():
		cb.call()
	action_pressed.emit(index)
	dismiss()


## Starts the fade-out now (idempotent).
func dismiss() -> void:
	if _leaving:
		return
	_leaving = true
	_age = UiMotion.dur(UiMotion.TOAST_IN_S) + hold_s
	if UiMotion.reduce_motion:
		_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false


func _process(delta: float) -> void:
	if _hover and not _leaving:
		return
	_age += delta
	var t_in: float = UiMotion.dur(UiMotion.TOAST_IN_S)
	var t_out: float = UiMotion.dur(UiMotion.TOAST_OUT_S)
	if _age < t_in:
		modulate.a = _age / t_in
	elif _age < t_in + hold_s:
		modulate.a = 1.0
	else:
		if not _leaving:
			_leaving = true
		var k: float = (_age - t_in - hold_s) / maxf(t_out, 0.0001)
		modulate.a = clampf(1.0 - k, 0.0, 1.0)
		if k >= 1.0:
			_finish()


func _finish() -> void:
	set_process(false)
	dismissed.emit()
	queue_free()


## Severity mark: a coloured stripe with the glyph, drawn by one small Control.
class Mark extends Control:
	var severity: int = UiToast.Severity.INFO

	func _init() -> void:
		custom_minimum_size = Vector2(28.0, 28.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var col: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var g: int = UiDraw.G_INFO
		if severity == UiToast.Severity.WARN:
			col = get_theme_color(&"warn", UiTheme.ACCENT_TYPE)
			g = UiDraw.G_WARNING
		elif severity == UiToast.Severity.ERROR:
			col = get_theme_color(&"danger", UiTheme.ACCENT_TYPE)
			g = UiDraw.G_WARNING
		draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.16))
		draw_rect(Rect2(0.0, 0.0, 3.0, size.y), col)
		UiDraw.glyph(self, g, Rect2(Vector2(7.0, 5.0), Vector2(18.0, 18.0)), col, 1.8)
