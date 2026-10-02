class_name UiNetOverlay
extends PanelContainer
## The F3 network overlay (ui.md 5.16.2): role, tick, turn, input delay D, speed, per-player RTT and jitter, traffic, load and stalls
## from `NetSession.stats()`, plus the frame rate. Refreshed at 4 Hz while visible; hidden by default (`net/show_net_overlay`).

const REFRESH_S: float = 0.25

var session: NetSession = null
var _label: Label = null
var _acc: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label = UiScreenKit.label("", &"DimLabel")
	_label.add_theme_font_size_override("font_size", 13)
	add_child(_label)


func toggle() -> void:
	set_shown(not visible)


func set_shown(on: bool) -> void:
	visible = on
	set_process(on)
	if on:
		refresh()


func text() -> String:
	return _label.text


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= REFRESH_S:
		_acc = 0.0
		refresh()


func refresh() -> void:
	if session == null:
		return
	_label.text = format(session.stats(), int(Engine.get_frames_per_second()), session.local_pid)
	reset_size()


## The overlay text of a `NetSession.stats()` dictionary.
static func format(st: Dictionary, fps: int, local_pid: int) -> String:
	var roles: PackedStringArray = ["none", "host", "client", "local"]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s  tick %d  turn %d  D=%d  speed %d%%" % [roles[clampi(int(st.get("role", 0)), 0, 3)], int(st.get("tick", 0)),
		int(st.get("turn", 0)), int(st.get("delay_turns", 0)), int(st.get("speed_pct", 0))])
	var rtt: Dictionary = st.get("rtt_ms", {}) as Dictionary
	var jit: Dictionary = st.get("jitter_ms", {}) as Dictionary
	var pids: Array = rtt.keys()
	pids.sort()
	for pid: Variant in pids:
		lines.append("  p%d%s  rtt %d ms  jitter %d ms" % [int(pid), "*" if int(pid) == local_pid else "", int(rtt[pid]), int(jit.get(pid, 0))])
	lines.append("in %.1f kbps  out %.1f kbps  load %d%%  stalls %d (%d ms)" % [float(st.get("kbps_in", 0.0)), float(st.get("kbps_out", 0.0)),
		int(st.get("load_pct", 0)), int(st.get("stall_count", 0)), int(st.get("stall_ms", 0))])
	lines.append("checksum tick %d  fps %d" % [int(st.get("last_checksum_tick", 0)), fps])
	return "\n".join(lines)
