class_name UiDlgStallPrompt
extends PanelContainer
## The host's stall prompt (ui.md 5.16.2): a NON-modal panel docked under the top strip that never dims or blocks the game view or the
## input controller. `stall_prompt(pids)` fills it; one row per stalled player offers Wait, Drop (the player resigns) and Replace with
## AI. There is no forced choice and no countdown: unanswered, the game keeps waiting. `chosen(pid, action)` carries a
## `NetProtocol.StallAction` to `NetSession.host_resolve_stall`.

signal chosen(pid: int, action: int)

var _rows: VBoxContainer = null
var _names: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_2)
	add_child(col)
	col.add_child(UiScreenKit.label("PLAYER NOT RESPONDING", &"HeaderLabel"))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UiMetrics.SP_2)
	col.add_child(_rows)


## `names`: pid -> display name (falls back to "Player N"). An empty `pids` hides the prompt.
func set_pids(pids: PackedInt32Array, names: Dictionary = {}) -> void:
	_names = names
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for pid: int in pids:
		_rows.add_child(_row(pid))
	visible = not pids.is_empty()
	reset_size()


func pid_count() -> int:
	return _rows.get_child_count()


func _row(pid: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_2)
	var who: Label = UiScreenKit.label(str(_names.get(pid, "Player %d" % (pid + 1))), &"", false, HORIZONTAL_ALIGNMENT_LEFT)
	who.custom_minimum_size = Vector2(120.0, 0.0)
	row.add_child(who)
	for spec: Array in [["Wait", NetProtocol.StallAction.STALL_WAIT, &""], ["Drop (resigns)", NetProtocol.StallAction.STALL_DROP_RESIGN, &"DangerButton"],
			["Replace with AI", NetProtocol.StallAction.STALL_DROP_AI, &"PrimaryButton"]]:
		var b: Button = UiScreenKit.button(str(spec[0]), spec[2] as StringName, Vector2(0.0, 34.0))
		b.pressed.connect(func() -> void:
			chosen.emit(pid, int(spec[1]))
			if int(spec[1]) == NetProtocol.StallAction.STALL_WAIT:
				visible = false)
		row.add_child(b)
	return row
