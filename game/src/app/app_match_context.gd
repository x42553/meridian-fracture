class_name AppMatchContext
extends RefCounted
## Everything a match screen needs (ui.md 3.1): the session, the four ports and the local roster / skin. Created when the
## session starts LOADING (ports null), completed by `build_ports()` once the world (and stage) exist, disposed on leaving the
## match.

var session: NetSession = null
## Replay playback (task REP2): set instead of `session` when this context plays a recording. The world, the frame drive and the
## tick interpolation then come from the replay engine; the ports are the observer ports.
var replay: AppReplaySession = null
## The AI seam (owns the `AiFactory`; a Callable would not keep it alive).
var ai: AppAiHook = null
## The latest world job of the session (`AppMatchJob`: progress and phase name for the loading screen, the view stage).
var job: AppMatchJob = null
## Time series and result summary for the end screen.
var stats: UiMatchStats = UiMatchStats.new()
## Debug: a bot playing the LOCAL human slot (`--bots=human|all`).
var human_bot: AppHumanBot = null
## `--ticks=N` (0 = until the match ends): polling stops when the world reaches this tick.
var tick_limit: int = 0
## `--pause-at=N`: request a pause once this tick is reached (screenshots hold a state still).
var pause_at_tick: int = 0
## The tick limit was reached (the session itself is still PLAYING).
var limit_reached: bool = false
## Commands the UI / bot submitted through `AppNetPortSession`.
var commands_sent: int = 0
var _port_seen: int = 0
var _replay_gen: int = 0
var config: Dictionary = {}
var local_pid: int = -1
var is_observer: bool = false
var is_replay: bool = false
var data: GameData = null
var roster: DefRoster = null
var skin: UiSkin = null
var sim: UiSimPort = null
var view: UiViewPort = null
var net: UiNetPort = null
var audio: UiAudioPort = null
var stage: AppViewStage = null
## Frame driver node when the `AppNet` autoload is absent (unit tests); null when `AppNet` polls this context.
var driver: AppSessionDriver = null
## Title of the loading screen / end screen ("Skirmish").
var title: String = "Skirmish"
var disposed: bool = false
## Scripted mission (MIS2): the difficulty (AI level shift, `AppMission`) the match was started with, and the campaign outcome
## `AppMission.finish` stored when it ended ({won, ticks, first_clear, new_best_time, ...}; empty while running).
var mission_difficulty: int = 1
var mission_outcome: Dictionary = {}
## Debug: `--preview=<a,b>` tags for the game screen (`select`, `place`, `units`, `power`), empty in normal play.
var preview: String = ""


## Builds the ports over the finished world. `stage` may be null (headless: no view; the view port is then a menu fixture).
func build_ports(p_stage: AppViewStage) -> void:
	var sw: SimWorld = world()
	if sw == null:
		return
	stage = p_stage
	is_observer = local_pid < 0
	var viewer: int = maxi(local_pid, 0)
	var sp: UiSimPortWorld = UiSimPortWorld.new(sw, local_pid if is_observer else viewer)  # an observer views everything (fog off)
	sp.bind_alpha(replay.tick_alpha if replay != null else session.tick_alpha)
	_wire_bot()
	sim = sp
	if is_observer or session == null:
		net = UiNetPortNull.new()
	else:
		net = AppNetPortSession.new(session, self)
	audio = UiAudioPortSnd.new() if AppAudio.current != null else UiAudioPortNull.new()
	if stage != null:
		view = AppViewPort.new(stage)
	else:
		view = UiViewPortFixture.new(sim, 0.0, false)
	data = sw.data
	if replay != null:
		_replay_gen = replay.player.generation()
	roster = sim.roster_of(viewer)
	var code: String = ""
	if roster != null and roster.faction >= 0 and roster.faction < data.factions.size():
		code = data.factions[roster.faction].code.to_lower()
	skin = UiSkinSet.shared().skin_for("" if is_observer else code)  # observers and replays wear the neutral skin


## Id of the scripted mission of this match / replay ("" = skirmish).
func mission_id() -> String:
	return str(config.get("mission", ""))


func world() -> SimWorld:
	if replay != null:
		return replay.world()
	return session.world() as SimWorld if session != null else null


## The current sim tick (0 before the world exists).
func tick() -> int:
	var w: SimWorld = world()
	return w.tick if w != null else 0


## Once per rendered frame BEFORE the view and the UI (ui.md 3.0; `AppNet._process`): polls the session, feeds the debug bot, samples
## the statistics and applies the `--ticks` / `--pause-at` test limits. Returns the sim ticks executed.
func frame() -> int:
	if disposed:
		return 0
	if replay != null:
		return _frame_replay()
	if session == null:
		return 0
	var w: SimWorld = world()
	if tick_limit > 0 and w != null and w.tick >= tick_limit:
		limit_reached = true
		return 0
	var base: int = session.opts.max_ticks_per_poll
	if w != null and (tick_limit > 0 or pause_at_tick > 0):
		# never step past the limit or the pause tick: the poll may run at most the ticks left
		var room: int = 1 << 30
		if tick_limit > 0:
			room = tick_limit - w.tick
		if pause_at_tick > 0:
			room = mini(room, maxi(pause_at_tick - w.tick, 1))
		session.opts.max_ticks_per_poll = clampi(room, 1, maxi(base, 1))
	var ran: int = session.poll()
	if session != null and session.opts != null:
		session.opts.max_ticks_per_poll = base
	w = world()
	if w == null:
		return ran
	if session.phase == NetSession.Phase.PLAYING or session.phase == NetSession.Phase.PAUSED:
		if human_bot != null and session.phase == NetSession.Phase.PLAYING:
			human_bot.update(w)
		stats.sample(w)
		if pause_at_tick > 0 and w.tick >= pause_at_tick and session.phase == NetSession.Phase.PLAYING:
			pause_at_tick = 0
			session.request_pause(true)
	return ran


## Replay playback: the engine advances the build / the recording; a rebuilt world (backward seek) is re-bound to the ports.
func _frame_replay() -> int:
	var ran: int = replay.frame()
	if sim is UiSimPortWorld and replay.player.generation() != _replay_gen:
		_replay_gen = replay.player.generation()
		var w: SimWorld = world()
		(sim as UiSimPortWorld).set_world(w)
		if stage != null and is_instance_valid(stage):
			stage.rebind_world(w)
	return ran


## A debug bot plays the LOCAL human slot under `--bots=human|all`.
func _wire_bot() -> void:
	if human_bot != null or ai == null or local_pid < 0 or not AppAiHook.human_is_bot():
		return
	var s: NetSession = session
	human_bot = ai.make_human_bot(local_pid, func(ints: PackedInt32Array) -> bool: return s.submit_command(ints))


## The end-screen model (ui.md 4.9.2) from the current world, the last `match_ended` result and the sampled series.
func summary(end: Dictionary = {}) -> Dictionary:
	var res: Dictionary = end if not end.is_empty() else last_end
	return stats.build(world(), config, res, local_pid, session)


## The last `match_ended` payload (set by `AppMatch` when the session ends); empty while the match runs.
var last_end: Dictionary = {}


## Crash-report info (`AppCrashReporter.info_provider`, whitelisted keys): who plays what on which seed and tick, and the net role.
func crash_info() -> Dictionary:
	var w: SimWorld = world()
	var rosters: Array = []
	for pv: Variant in config.get("players", []) as Array:
		rosters.append(str((pv as Dictionary).get("roster", "")))
	var m: Dictionary = config.get("map", {}) as Dictionary
	var roles: PackedStringArray = ["none", "host", "client", "local"]
	return {"rosters": rosters, "map_family": int(m.get("family", 0)), "map_size": int(m.get("size", 0)), "map_seed": int(m.get("seed", 0)),
		"tick": w.tick if w != null else 0, "checksum": "%08X" % (w.checksum() & 0xFFFFFFFF) if w != null else "n/a",
		"net_role": roles[clampi(session.role, 0, 3)] if session != null else ("replay" if replay != null else "none")}


func dispose() -> void:
	if disposed:
		return
	disposed = true
	human_bot = null
	if job != null and job.phase < AppMatchJob.Phase.DONE:
		job.cancel()  # a loading build: stops the map worker and hides the half-built view stage
	if session != null:
		session.shutdown()
	if replay != null:
		replay.dispose()
	if ai != null:
		ai.shutdown()
	if driver != null and is_instance_valid(driver):
		driver.queue_free()
	driver = null
	if view is UiViewPortWorld:
		var ic: ViewIconBake = (view as UiViewPortWorld).icons
		if ic != null and is_instance_valid(ic):
			ic.flush()
			ic.clear_memory()  # the baked build-card / portrait textures: not left to the engine's exit-time cleanup
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	if view is UiViewPortFixture:
		(view as UiViewPortFixture).dispose()
	sim = null
	view = null
	net = null
