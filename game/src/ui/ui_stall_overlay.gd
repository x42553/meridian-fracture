class_name UiStallOverlay
extends PanelContainer
## The lockstep stall overlay (ui.md 5.16.2): "Waiting for {names}... {seconds} s" with one subline per reason, shown while the
## barrier waits for a player (`stall_changed(waiting)`, raised by net after 400 ms). `waiting` entries are
## `{pid, name, reason (NetProtocol.StallReason), wait_ms}`; pid -1 is the host itself being silent (a client's view). The sim
## view freezes on its own; the UI stays live. The seconds count up locally between net updates.

var _title: Label = null
var _lines: VBoxContainer = null
var _waiting: Array = []
var _age_s: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_1)
	add_child(col)
	_title = UiScreenKit.label("", &"HeaderLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_size_override("font_size", 22)
	col.add_child(_title)
	_lines = VBoxContainer.new()
	col.add_child(_lines)
	set_process(false)


## Empty = resumed (hides the overlay).
func set_waiting(waiting: Array) -> void:
	_waiting = waiting.duplicate(true)
	_age_s = 0.0
	visible = not _waiting.is_empty()
	set_process(visible)
	_refresh()


func is_waiting() -> bool:
	return visible


func title_text() -> String:
	return _title.text


func _process(delta: float) -> void:
	_age_s += delta
	_refresh()


func _refresh() -> void:
	if _waiting.is_empty():
		return
	var names: PackedStringArray = PackedStringArray()
	var longest_ms: int = 0
	for w: Variant in _waiting:
		var d: Dictionary = w as Dictionary
		names.append("the host" if int(d.get("pid", 0)) < 0 else str(d.get("name", "player")))
		longest_ms = maxi(longest_ms, int(d.get("wait_ms", 0)))
	var secs: int = longest_ms / 1000 + int(_age_s)
	_title.text = "Waiting for %s... %d s" % [", ".join(names), secs]
	for c: Node in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for w2: Variant in _waiting:
		var d2: Dictionary = w2 as Dictionary
		var sub: String = _reason_text(int(d2.get("reason", 0)), str(d2.get("name", "player")))
		if sub != "":
			_lines.add_child(UiScreenKit.label(sub, &"DimLabel", false, HORIZONTAL_ALIGNMENT_CENTER))
	reset_size()


static func _reason_text(reason: int, player_name: String) -> String:
	match reason:
		NetProtocol.StallReason.DISCONNECTED:
			return "%s: connection lost" % player_name
		NetProtocol.StallReason.LOADING:
			return "%s is still loading" % player_name
		NetProtocol.StallReason.SLOW_CPU:
			return "%s's computer is running slowly" % player_name
	return ""
