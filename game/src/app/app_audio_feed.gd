class_name AppAudioFeed
extends Node
## Per-frame glue between the running match and the `Snd` facade (audio spec 3.2). It runs at process priority -50: after the
## session was polled (AppNet, -100) and before the game screen takes the frame's event batch, so it PEEKS the world's event
## buffer (never `take()`s it) and hands the records added since its last look to `Snd.on_events`. It also
##  - starts / ends the audio side of a match when `AppState.match_ctx` gets a world / goes away,
##  - swaps the context's `UiAudioPortNull` for a `UiAudioPortSnd` so HUD cues and unit responses are heard,
##  - pushes the view camera pose (or a stand-in camera on a headless run) and the pause state,
##  - switches the music between menu / lobby / match with the app flow mode.

var _app: AppAudio = null
var _snd: SndManager = null
var _ctx: AppMatchContext = null
var _seen: int = 0
var _begun: bool = false
var _ended: bool = false
var _standin: Node3D = null
var _standin_cam: Camera3D = null
var _standin_focus: Vector3 = Vector3.ZERO
var _centroid_left: float = 0.0
var _flow_mode: int = -1
var _paused: bool = false
var _port: UiAudioPortSnd = null
var _last_result: int = SndMatchConfig.RESULT_NONE
## Event records handed to the facade since the feed exists (diagnostics: `AppAudio.report`).
var events_fed: int = 0


func setup(app: AppAudio, snd: SndManager) -> void:
	_app = app
	_snd = snd
	process_priority = -50
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _snd == null or not _snd.is_ready():
		return
	var state: Node = get_node_or_null("/root/AppState")
	if state == null:
		return
	_follow_flow(state)
	var ctx: AppMatchContext = state.get("match_ctx") as AppMatchContext
	if ctx != _ctx:
		_leave_match()
		_ctx = ctx
		_seen = 0
		_begun = false
		_ended = false
	if _ctx == null or _ctx.disposed:
		return
	var w: SimWorld = _ctx.world()
	if w == null:
		return
	if not _begun:
		_begin(w)
		if not _begun:
			return
	_feed_camera(w, delta)
	_feed_events(w)
	var alpha: float = 1.0
	if _ctx.session != null and _ctx.session.has_method("tick_alpha"):
		alpha = float(_ctx.session.call("tick_alpha"))
	_snd.on_frame(w, alpha, delta)
	_follow_pause()
	if not _ended and w.match_state == SimWorld.MATCH_ENDED:
		_ended = true


func _follow_flow(state: Node) -> void:
	var flow: Variant = state.get("flow")
	if not (flow is AppFlow):
		return
	var mode: int = (flow as AppFlow).mode
	if mode == _flow_mode:
		return
	_flow_mode = mode
	match mode:
		AppFlow.Mode.MAIN_MENU, AppFlow.Mode.LAN_BROWSER, AppFlow.Mode.REPLAYS, AppFlow.Mode.CREDITS, AppFlow.Mode.FIELD_MANUAL, AppFlow.Mode.OPTIONS, \
				AppFlow.Mode.CAMPAIGN, AppFlow.Mode.MISSION_BRIEFING:
			if _ctx == null or mode == AppFlow.Mode.MAIN_MENU or mode == AppFlow.Mode.CAMPAIGN:
				_snd.set_mode(SndManager.MODE_MENU)
		AppFlow.Mode.SKIRMISH_LOBBY, AppFlow.Mode.LAN_LOBBY:
			_snd.set_mode(SndManager.MODE_LOBBY)
		AppFlow.Mode.LOADING:
			_snd.set_mode(SndManager.MODE_LOADING)


func _begin(w: SimWorld) -> void:
	if _ctx.sim == null:
		return  # ports (and the view stage) are built by the session at match start
	var cfg: SndMatchConfig = SndMatchConfig.from_world(w, _ctx.local_pid)
	cfg.replay = _ctx.is_replay
	if _ctx.roster != null:
		cfg.local_roster_id = _ctx.roster.id
	_snd.begin_match(cfg)
	_begun = true
	_seen = w.events.data.size()
	_swap_port()
	if _ctx.stage != null and is_instance_valid(_ctx.stage):
		_snd.attach_world(_ctx.stage)
	else:
		_attach_standin()


func _swap_port() -> void:
	if _ctx.audio == null or _ctx.audio is UiAudioPortNull:
		_port = UiAudioPortSnd.new(_snd)
		_snd.announcement_started.connect(_port.caption.emit)
		_ctx.audio = _port


## A headless run has no view: audio gets its own root with a current camera so positional sound works.
func _attach_standin() -> void:
	if _standin == null:
		_standin = Node3D.new()
		_standin.name = "AudioStandIn"
		_standin_cam = Camera3D.new()
		_standin.add_child(_standin_cam)
		get_tree().root.add_child(_standin)
	_standin_cam.current = true
	_snd.attach_world(_standin)


func _feed_camera(w: SimWorld, dt: float) -> void:
	var stage: AppViewStage = _ctx.stage
	if stage != null and is_instance_valid(stage) and stage.view != null and stage.view.camera != null and stage.view.camera.camera != null:
		var cam: ViewCamera = stage.view.camera
		_snd.set_camera(cam.current_focus(), cam.camera.global_basis, cam.current_height())
		return
	_centroid_left -= dt
	if _centroid_left <= 0.0:
		_centroid_left = 1.0
		_standin_focus = _own_centroid(w)
	_snd.set_camera(_standin_focus, Basis.IDENTITY, 55.0)


func _own_centroid(w: SimWorld) -> Vector3:
	var pid: int = _ctx.local_pid if _ctx.local_pid >= 0 else 0
	var n: int = 0
	var sx: int = 0
	var sy: int = 0
	for e: SimEntity in w.units_of(pid):
		sx += e.x
		sy += e.y
		n += 1
		if n >= 64:
			break
	if n == 0:
		for s: SimEntity in w.structures_of(pid):
			sx += s.x
			sy += s.y
			n += 1
	if n == 0:
		return _standin_focus
	return SndUnits.to_world(sx / n, sy / n, 0.0)


## The records the buffer gained since the last look (the game screen empties the buffer after us, every frame).
func _feed_events(w: SimWorld) -> void:
	var data: PackedInt32Array = w.events.data
	if data.size() < _seen:
		_seen = 0
	if data.size() > _seen:
		_snd.on_events(w, data.slice(_seen), 1.0)
		events_fed += data.size() - _seen
	_seen = data.size()
	if _ctx.stage == null:
		# nobody else consumes the buffer without a view (headless run): empty it here, like the session's auto clear does
		w.clear_events()
		_seen = 0


func _follow_pause() -> void:
	var s: Object = _ctx.session
	if s == null or not s.has_method("is_paused"):
		return
	var p: bool = bool(s.call("is_paused"))
	if p != _paused:
		_paused = p
		_snd.set_world_paused(p)


func _leave_match() -> void:
	if _ctx != null and _begun:
		_snd.end_match(SndMatchConfig.RESULT_ABORT if not _ended else _last_result)
		_snd.detach_world()
	if _ctx != null and _port != null:
		if _snd.announcement_started.is_connected(_port.caption.emit):
			_snd.announcement_started.disconnect(_port.caption.emit)
	_port = null
	_begun = false
	if _standin != null:
		_standin.queue_free()
		_standin = null
		_standin_cam = null
