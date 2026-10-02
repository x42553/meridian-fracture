class_name UiDialogStack
extends Node
## Modal dialog stack (ui.md 3.5): dims the screen, blocks the input controller (`has_modal_over_input()`), traps focus
## inside the visible dialog, handles Escape (first, in `_input`, before any screen), one dialog visible at a time; further
## `push`es queue and show in order. The host is a full-rect `UiLayerRoot` of the OVERLAY layer (`attach`).

signal top_changed(dlg: UiDialog)

var _host: Control = null
var _scrim: ColorRect = null
var _center: CenterContainer = null
var _queue: Array[UiDialog] = []
var _top: UiDialog = null
var _prev_focus: Control = null
var _regrab_queued: bool = false


## Builds the scrim and the centring container inside `host` (a UiLayerRoot); call once, before `push`.
func attach(host: Control) -> void:
	_host = host
	_scrim = ColorRect.new()
	_scrim.color = UiPalette.BLACK_A
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	host.add_child(_scrim)
	UiLayerRoot.fill(_scrim)
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.visible = false
	host.add_child(_center)
	UiLayerRoot.fill(_center)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Shows `dlg` now, or queues it behind the visible one.
func push(dlg: UiDialog) -> void:
	if _host == null:
		Log.error("ui", "UiDialogStack.push before attach()")
		dlg.queue_free()
		return
	if _top == null:
		_show(dlg)
	else:
		_queue.append(dlg)


## Closes the visible dialog with `result` (its `closed` signal fires), then shows the next queued one.
func close_top(result: int = 0) -> void:
	if _top != null:
		_top.close(result)


func is_open() -> bool:
	return _top != null


## True while a dialog is up: `UiInputController.enabled = false`.
func has_modal_over_input() -> bool:
	return _top != null


func top() -> UiDialog:
	return _top


## Visible dialog plus the queued ones.
func count() -> int:
	return (1 if _top != null else 0) + _queue.size()


func _show(dlg: UiDialog) -> void:
	_top = dlg
	if _prev_focus == null:
		_prev_focus = get_viewport().gui_get_focus_owner()
	dlg.closed.connect(_on_closed.bind(dlg), CONNECT_ONE_SHOT)
	_scrim.visible = true
	_center.visible = true
	_host.move_child(_scrim, -1)
	_host.move_child(_center, -1)
	_center.add_child(dlg)
	dlg.modulate.a = 0.0
	UiMotion.fade(self, dlg, 1.0, UiMotion.TOAST_IN_S)
	if UiMotion.reduce_motion:
		dlg.modulate.a = 1.0
	_focus_dialog()
	top_changed.emit(dlg)


func _on_closed(_result: int, dlg: UiDialog) -> void:
	if dlg.get_parent() != null:
		dlg.get_parent().remove_child(dlg)
	dlg.queue_free()
	_top = null
	if not _queue.is_empty():
		_show(_queue.pop_front())
		return
	_scrim.visible = false
	_center.visible = false
	if _prev_focus != null and is_instance_valid(_prev_focus) and _prev_focus.is_visible_in_tree():
		_prev_focus.grab_focus()
	_prev_focus = null
	top_changed.emit(null)


func _focus_dialog() -> void:
	if _top == null:
		return
	# deferred: the dialog has no size until the container laid it out
	_grab.call_deferred()


func _grab() -> void:
	if _top == null or not is_instance_valid(_top):
		return
	var c: Control = _top.default_focus()
	if c != null and c.is_visible_in_tree():
		c.grab_focus()


## Focus trap. The re-grab is DEFERRED (never nested in the `gui_focus_changed` emission): a nested `grab_focus()` made the engine alternate
## between the outside control and the dialog button forever, which overflowed the native stack (SIGSEGV when the first-run LAN firewall
## explainer opened over the LAN browser, whose screen grabs its filter field right after `enter`).
func _on_focus_changed(node: Control) -> void:
	if _top != null and is_instance_valid(_top) and node != null and not _top.is_ancestor_of(node) and node != _top:
		if not _regrab_queued:
			_regrab_queued = true
			_regrab.call_deferred()


func _regrab() -> void:
	_regrab_queued = false
	if _top == null or not is_instance_valid(_top):
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not (_top.is_ancestor_of(focused) or focused == _top):
		_grab()


func _input(event: InputEvent) -> void:
	if _top == null or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _top.dismiss_on_escape:
			close_top(0)
		get_viewport().set_input_as_handled()
