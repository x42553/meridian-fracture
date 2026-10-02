class_name UiObserverController
extends RefCounted
## Everything the observer HUD does besides drawing (ui.md 5.16.3, task REP2): feeds the `UiObserverBar` / `UiScoreboard` from the
## `UiObserverModel`, owns the perspective (whose vision the world and the minimap show: -1 = all players with the fog off, or one
## pid), the follow camera, and, for replays, the transport (`UiReplayBar` <-> `AppReplaySession`: pause, speed, seek, jump to events).
## Created by `UiScreenGame` in observer mode. It reads the sim through `UiSimPort` and steers presentation only: the stage's vision,
## the camera and the playback engine. It never submits a command.

signal perspective_changed(pid: int)
signal follow_changed(on: bool)

const FOLLOW_EVERY_S: float = 0.6
const JUMP_LEAD_TICKS: int = 60
const ROWS_EVERY_FRAMES: int = 6
const OVERVIEW_ZOOM: float = 0.62

var model: UiObserverModel = UiObserverModel.new()
var perspective: int = -1
var follow: bool = false

var hud: UiHud = null
var sim: UiSimPort = null
var view: UiViewPort = null
var stage: AppViewStage = null
var presenter: UiHudPresenter = null
var selection: UiSelection = null
var replay: AppReplaySession = null

var _last_player: int = 0
var _follow_t: float = 0.0
var _frames: int = 0
var _discovered: Dictionary = {}
var _marks: Array[Dictionary] = []
var _marks_sig: int = -1


## `default_pid`: the first perspective (-1 = all players; a surrendered or defeated player starts on their own view).
func setup(p_hud: UiHud, p_sim: UiSimPort, p_view: UiViewPort, p_stage: AppViewStage, p_presenter: UiHudPresenter, p_selection: UiSelection,
		p_replay: AppReplaySession, default_pid: int) -> void:
	hud = p_hud
	sim = p_sim
	view = p_view
	stage = p_stage
	presenter = p_presenter
	selection = p_selection
	replay = p_replay
	_last_player = maxi(default_pid, 0)
	var bar: UiObserverBar = hud.observer_bar()
	if bar != null:
		bar.perspective_requested.connect(set_perspective)
		bar.follow_toggled.connect(func(on: bool) -> void: set_follow(on, false))
		bar.scoreboard_requested.connect(toggle_scoreboard)
	if replay != null:
		var rb: UiReplayBar = hud.add_replay_bar()
		rb.pause_toggled.connect(replay.toggle_pause)
		rb.speed_chosen.connect(replay.set_speed)
		rb.seek_requested.connect(replay.seek)
		rb.seek_relative.connect(replay.seek_by_seconds)
		rb.event_jump.connect(jump_event)
	model.update(sim, true)
	set_perspective(default_pid, true)
	_push_rows()
	if default_pid < 0 and view != null:
		var cs: Dictionary = view.camera_state()  # watching everyone: start with the wider view of the battlefield
		if not cs.is_empty():
			cs["zoom"] = OVERVIEW_ZOOM
			view.set_camera_state(cs, true)


## Chooses whose vision is shown (-1 = everyone, fog off).
func set_perspective(pid: int, force: bool = false) -> void:
	if pid == perspective and not force:
		return
	perspective = pid
	if pid >= 0:
		_last_player = pid
	sim.set_viewer_pid(pid)
	if stage != null and is_instance_valid(stage):
		stage.set_perspective(pid)
	if selection != null:
		selection.clear()
	if presenter != null:
		presenter.refresh_all()
	var bar: UiObserverBar = hud.observer_bar()
	if bar != null:
		bar.set_perspective(pid)
	hud.sidebar().set_header("REPLAY" if replay != null else "OBSERVER", "ALL PLAYERS" if pid < 0 else sim.name_of(pid).to_upper())
	perspective_changed.emit(pid)


## F: everything visible <-> the last viewed player's vision.
func toggle_fog() -> void:
	set_perspective(_last_player if perspective < 0 else -1)


## 1..8: that player (if there is one); Tab / Shift+Tab: the next / previous one still in the game.
func choose_player(pid: int) -> void:
	for r: Dictionary in model.rows:
		if int(r["pid"]) == pid:
			set_perspective(pid)
			return


func next_player(direction: int = 1) -> void:
	var pid: int = model.next_pid(perspective, direction)
	if pid >= 0:
		set_perspective(pid)


## `announce`: the bar already shows the state (it toggled itself).
func set_follow(on: bool, announce: bool = true) -> void:
	follow = on
	_follow_t = FOLLOW_EVERY_S
	if announce and hud.observer_bar() != null:
		hud.observer_bar().set_follow(on)
	follow_changed.emit(on)


func toggle_scoreboard() -> void:
	var sb: UiScoreboard = hud.scoreboard()
	if sb == null:
		return
	sb.toggle()
	if sb.visible:
		sb.set_rows(model.rows, sim.tick())


## Keymap actions of the observer context. True when handled.
func handle_action(id: StringName) -> bool:
	var n: int = UiActions.indexed(id, "obs_player_")
	if n >= 1:
		choose_player(n - 1)
		return true
	match id:
		&"obs_all":
			set_perspective(-1)
		&"obs_next_player":
			next_player(1)
		&"obs_toggle_fog":
			toggle_fog()
		&"obs_follow":
			set_follow(not follow)
		&"toggle_scoreboard":
			toggle_scoreboard()
		&"obs_pause":
			if replay != null:
				replay.toggle_pause()
			else:
				return false
		&"obs_speed_up":
			if replay != null:
				replay.set_speed(UiReplayBar.step_speed(replay.speed(), 1))
			else:
				return false
		&"obs_speed_down":
			if replay != null:
				replay.set_speed(UiReplayBar.step_speed(replay.speed(), -1))
			else:
				return false
		&"obs_event_next":
			jump_event(1)
		&"obs_event_prev":
			jump_event(-1)
		&"obs_seek_fwd":
			if replay != null:
				replay.seek_by_seconds(UiReplayBar.SKIP_SECONDS)
		&"obs_seek_back":
			if replay != null:
				replay.seek_by_seconds(-UiReplayBar.SKIP_SECONDS)
		_:
			return false
	return true


## Recorded events plus the eliminations discovered while watching (first seen tick), ascending.
func marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var known: Dictionary = {}
	if replay != null:
		for m: Dictionary in replay.event_marks():
			out.append(m)
			if str(m["kind"]) != "chat":
				known[int(m["pid"])] = true
	for pid: Variant in _discovered:
		if not known.has(pid):
			out.append({"tick": int(_discovered[pid]), "kind": "defeated", "pid": int(pid), "text": "%s eliminated" % sim.name_of(int(pid))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) < int(b["tick"]))
	return out


## Jumps to the next / previous event: a few seconds before it (exactly on it when that would not move forward).
func jump_event(direction: int) -> void:
	if replay == null:
		return
	var t: int = UiReplayBar.event_after(marks(), replay.tick(), direction)
	if t < 0:
		return
	var lead: int = t - JUMP_LEAD_TICKS
	replay.seek(lead if (lead > replay.tick() + 20 or direction < 0) else t)


## Once per rendered frame after the sim advanced.
func update(delta: float) -> void:
	_frames += 1
	var rebuilt: bool = false
	if _frames % ROWS_EVERY_FRAMES == 0 and model.update(sim):
		rebuilt = true
		_note_eliminations()
		_push_rows()
	if replay != null:
		_push_replay_state()
		var ts: UiTopStrip = hud.top_strip()
		ts.set_paused(replay.is_paused())
		var sp: float = replay.speed()
		ts.set_speed_label("" if sp == 1.0 else ("MAX" if sp <= 0.0 else "%sx" % String.num(sp, 2).rstrip("0").rstrip(".")))
		if rebuilt:
			var m: Array[Dictionary] = marks()
			var sig: int = m.size() * 1000003 + (int(m[m.size() - 1]["tick"]) if not m.is_empty() else 0)
			if sig != _marks_sig:
				_marks_sig = sig
				_marks = m
				hud.replay_bar().set_marks(m)
	if follow:
		_follow_t += delta
		if _follow_t >= FOLLOW_EVERY_S:
			_follow_t = 0.0
			_follow_camera()


func _push_rows() -> void:
	var total: int = 0
	for r: Dictionary in model.rows:
		total += int(r["units"]) + int(r["structs"])
	hud.top_strip().set_entities(total)
	var bar: UiObserverBar = hud.observer_bar()
	if bar != null:
		bar.set_rows(model.rows)
	if perspective >= 0:
		hud.sidebar().credits().income_per_min = int(model.row_of(perspective).get("income", 0))  # the model's rolling minute, kept across switches
	var sb: UiScoreboard = hud.scoreboard()
	if sb != null and sb.visible:
		sb.set_rows(model.rows, sim.tick())


func _push_replay_state() -> void:
	var rb: UiReplayBar = hud.replay_bar()
	if rb == null:
		return
	var p: NetReplayPlayer = replay.player
	rb.set_state(p.current_tick(), p.end_tick(), p.speed(), p.is_paused(), p.verified_through_tick(), p.diverged_tick(), p.is_seeking(),
		int(p.seek_progress() * 100.0), p.is_finished())


## Remembers the tick at which a player was first seen out of the game (the jump list of a replay without recorded status events).
func _note_eliminations() -> void:
	for r: Dictionary in model.rows:
		var pid: int = int(r["pid"])
		if not bool(r["active"]) and not _discovered.has(pid):
			_discovered[pid] = sim.tick()


func _follow_camera() -> void:
	var pid: int = perspective
	if pid < 0:
		var best: int = -1
		var top: int = -1
		for r: Dictionary in model.rows:
			if bool(r["active"]) and int(r["army_value"]) > top:
				top = int(r["army_value"])
				best = int(r["pid"])
		pid = best
	if pid < 0:
		return
	var t: Vector2i = model.follow_target(pid)
	if t.x >= 0:
		view.focus_on_sim(t.x, t.y, false)
