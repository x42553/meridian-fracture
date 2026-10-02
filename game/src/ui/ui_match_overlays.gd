class_name UiMatchOverlays
extends Control
## The in-match network overlays and dialogs of one game screen (ui.md 5.16.2): pause banner, stall overlay, the host's stall
## prompt, the desync dialog, the connection-lost message and the F3 network overlay. It listens to the `NetSession` signals, holds no
## game state and never touches the sim: the only outputs are `NetSession.request_pause` and `host_resolve_stall`. Built by
## `UiScreenGame`; a full-rect, mouse-transparent container so world clicks pass through the empty parts.

## Emitted after the desync dialog or a connection-lost message asked to leave the match.
signal leave_requested()

var session: NetSession = null
var banner: UiPauseBanner = null
var stall: UiStallOverlay = null
var prompt: UiDlgStallPrompt = null
var net_overlay: UiNetOverlay = null
var desync_dialog: UiDlgDesync = null
## The game menu holds the pause of a LOCAL match: its own footer says so, the banner would only repeat it.
var banner_suppressed: bool = false:
	set(v):
		banner_suppressed = v
		if v and banner != null:
			banner.hide_banner()
var _names: Dictionary = {}
var _scenes: Node = null
var _bound: Array[Array] = []


func _init() -> void:
	name = "MatchOverlays"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Builds the widgets and connects the session. `names`: pid -> display name. `scenes`: the `AppScenes` node (modal dialogs, toasts).
func setup(p_session: NetSession, names: Dictionary, scenes: Node = null) -> void:
	session = p_session
	_names = names
	_scenes = scenes
	banner = UiPauseBanner.new()
	add_child(banner)
	banner.resume_requested.connect(func() -> void: session.request_pause(false))
	stall = UiStallOverlay.new()
	add_child(stall)
	prompt = UiDlgStallPrompt.new()
	add_child(prompt)
	prompt.chosen.connect(func(pid: int, action: int) -> void: session.host_resolve_stall(pid, action))
	net_overlay = UiNetOverlay.new()
	net_overlay.session = session
	add_child(net_overlay)
	_bind(&"pause_changed", _on_pause)
	_bind(&"stall_changed", _on_stall)
	_bind(&"stall_prompt", _on_prompt)
	_bind(&"desync_detected", _on_desync)
	_bind(&"net_error", _on_net_error)
	_bind(&"kicked", _on_kicked)
	_bind(&"phase_changed", _on_phase)
	_layout()


func _bind(sig: StringName, fn: Callable) -> void:
	session.connect(sig, fn)
	_bound.append([sig, fn])


## Disconnects everything from the session (the screen calls this on exit).
func release() -> void:
	if session != null:
		for b: Array in _bound:
			if session.is_connected(b[0] as StringName, b[1] as Callable):
				session.disconnect(b[0] as StringName, b[1] as Callable)
	_bound.clear()
	if net_overlay != null:
		net_overlay.session = null
	session = null


func toggle_net_overlay() -> void:
	net_overlay.toggle()


func _layout() -> void:
	var field_w: float = maxf(size.x - float(UiMetrics.SIDEBAR_W), 320.0)
	banner.position = Vector2((field_w - banner.size.x) * 0.5, size.y * 0.16)
	stall.position = Vector2((field_w - stall.size.x) * 0.5, size.y * 0.30)
	prompt.position = Vector2(UiMetrics.TOP_STRIP_POS.x, 120.0)
	net_overlay.position = Vector2(field_w - net_overlay.size.x - 12.0, 12.0)


func _process(_delta: float) -> void:
	# the widgets resize when their text changes: keep them centred
	_layout()


# ---------------------------------------------------------------- session signals

func _on_pause(paused: bool, by_pid: int) -> void:
	if not paused:
		banner.hide_banner()
		return
	var key: String = "Pause"
	var km: UiKeymap = UiKeymap.instance()
	if not km.action_ids().is_empty():
		key = km.label(&"pause_game")
	if banner_suppressed:
		return
	banner.show_paused(str(_names.get(by_pid, "")), -1, key, by_pid == session.local_pid or session.role != NetSession.Role.CLIENT,
		session.role == NetSession.Role.LOCAL)
	_layout()


func _on_stall(waiting: Array) -> void:
	stall.set_waiting(waiting)
	if waiting.is_empty():
		prompt.set_pids(PackedInt32Array(), _names)


func _on_prompt(pids: PackedInt32Array) -> void:
	prompt.set_pids(pids, _names)


func _on_desync(report: Dictionary) -> void:
	if desync_dialog != null:
		return
	desync_dialog = UiDlgDesync.new(report)
	desync_dialog.session = session
	desync_dialog.closed.connect(func(result: int) -> void:
		desync_dialog = null
		if result == UiDlgDesync.RESULT_LEAVE:
			leave_requested.emit())
	if _scenes != null:
		_scenes.call("modal", desync_dialog)


func _on_net_error(code: int, text: String) -> void:
	Log.warn("net", "net_error %d: %s" % [code, text])
	if _scenes != null and code != NetProtocol.NetErrorCode.NO_CHECKSUM:
		_scenes.call("toast", text, 1)


func _on_kicked(_reason: int, detail: String) -> void:
	_lost("You were removed from the match." if detail == "" else detail)


func _on_phase(phase: int, _previous: int) -> void:
	if phase == NetSession.Phase.DISCONNECTED:
		_lost("The connection to the host was lost.")


func _lost(text: String) -> void:
	if _scenes == null:
		leave_requested.emit()
		return
	var d: UiDlgMessage = UiDlgMessage.new("Connection lost", text)
	d.closed.connect(func(_r: int) -> void: leave_requested.emit())
	_scenes.call("modal", d)
