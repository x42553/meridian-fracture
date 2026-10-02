extends RefCounted
## APP-1 match glue over the real `NetSession` (net.md 5.9, ui.md 5.3): the config completion, the LOCAL session through
## `AppMatch.start_local` (parity with the direct sim, pause, surrender, tick limits, takeover), the AI seam over `AiFactory` and the
## end-screen model. Everything runs without a renderer, unpaced, polling the context by hand.

const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla"]
const ROSTERS3: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla"]

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


func _config(seed_value: int = 5, rosters: PackedStringArray = ROSTERS) -> Dictionary:
	return AppMatch.simple_config(rosters, seed_value, 96)


## Starts a headless unpaced LOCAL match and polls until PLAYING.
func _start(cfg: Dictionary, extra: Dictionary = {}) -> AppMatchContext:
	var o: Dictionary = {"with_view": false, "bind": false, "unpaced": true, "discard_events": true}
	o.merge(extra, true)
	var ctx: AppMatchContext = AppMatch.start_local(cfg, o)
	if ctx == null:
		return null
	var guard: int = 0
	while ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		ctx.frame()
		OS.delay_msec(2)
		guard += 1
	return ctx


func _finish(ctx: AppMatchContext) -> void:
	if ctx == null:
		return
	ctx.dispose()
	var app: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("AppState")
	if app != null and app.get("match_ctx") == ctx:
		app.set("match_ctx", null)


## Polls until `cond` or `max_polls`; returns the ticks run.
func _run(ctx: AppMatchContext, cond: Callable, max_polls: int = 600) -> void:
	var g: int = 0
	while not bool(cond.call()) and g < max_polls:
		ctx.frame()
		g += 1


## The world of a UI-shape config built directly (no session, no lockstep).
func _direct_world(cfg: Dictionary) -> SimWorld:
	var job: AppMatchJob = AppMatchJob.new(cfg, false, _gd())
	var guard: int = 0
	while not job.step(4000) and guard < 4000:
		OS.delay_msec(2)
		guard += 1
	return job.take_world()


## An AI factory override whose thinkers never issue a command (parity runs).
func _idle_ai(hook_out: Array) -> Callable:
	return func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
		hook_out.append(pid)
		return func(_w: RefCounted, _out: Array) -> void: pass


# ---------------------------------------------------------------- config completion

func test_completed_config_is_accepted_by_net(t: TestCtx) -> void:
	var d: GameData = _gd()
	var o: NetSessionOptions = AppNetSetup.make_options(d, {})
	var cfg: Dictionary = _config(3, ROSTERS3)
	# lobby-style team ids (5 + slot) and a second human slot
	((cfg["players"] as Array)[1] as Dictionary)["team"] = 6
	((cfg["players"] as Array)[2] as Dictionary)["team"] = 7
	((cfg["players"] as Array)[1] as Dictionary)["kind"] = "human"
	((cfg["players"] as Array)[1] as Dictionary).erase("ai")
	var full: Dictionary = NetMatchConfig.normalize(AppNetSetup.complete_config(cfg, o, 1_790_000_000))
	t.check(not full.is_empty(), "normalize accepts the completed config")
	t.eq(NetMatchConfig.validate(full, o), "", "and it validates")
	var pl: Array = full["players"] as Array
	t.eq(pl.size(), 3)
	t.eq(str((pl[0] as Dictionary)["kind"]), "human")
	t.eq(int((pl[0] as Dictionary)["peer"]), 1, "the first human is the local peer")
	t.eq(str((pl[1] as Dictionary)["kind"]), "ai", "a second human cannot exist in a LOCAL match: an AI plays the slot")
	t.eq(int(((pl[1] as Dictionary)["ai"] as Dictionary)["level"]), AppAiHook.takeover_level)
	t.eq(int((pl[1] as Dictionary)["team"]), 9, "team 6 (lobby 'no team') becomes the private team 8 + pid")
	t.eq(int((pl[2] as Dictionary)["team"]), 10)
	t.eq(int((full["net"] as Dictionary)["speed_pct"]), 100)
	t.check((full["rules"] as Dictionary).has("vision_stride"), "the whole rules schema is present")
	t.check(not (full["rules"] as Dictionary).has("victory"), "keys outside the net schema are dropped")


func test_speed_option_reaches_the_config(t: TestCtx) -> void:
	var ctx: AppMatchContext = _start(_config(), {"speed_pct": 150})
	if not t.not_null(ctx, "session created"):
		return
	t.eq(int((ctx.config["net"] as Dictionary)["speed_pct"]), 150)
	_finish(ctx)


func test_invalid_config_fails_to_create_a_session(t: TestCtx) -> void:
	t.expect_errors(1)
	var bad: Dictionary = _config()
	(bad["map"] as Dictionary)["size"] = 100  # not a multiple of 8
	var ctx: AppMatchContext = AppMatch.start_local(bad, {"with_view": false, "bind": false})
	t.is_null(ctx, "no context for a config net rejects")
	t.check(NetSession.last_create_error != "", "and the reason is kept")


# ---------------------------------------------------------------- session over net

func test_local_session_matches_the_direct_sim(t: TestCtx) -> void:
	var cfg: Dictionary = _config(7)
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(cfg, {"ticks": 600})
	AppAiHook.factory = Callable()
	if not t.not_null(ctx, "session"):
		return
	var checks: Dictionary = {}
	ctx.session.checksum_observer = func(tick: int, cs: int, _chain: int) -> void: checks[tick] = cs
	_run(ctx, func() -> bool: return ctx.limit_reached)
	t.eq(ctx.tick(), 600, "the tick limit stops the polling exactly")
	t.eq(made, [1], "net asked the hook for the AI slot only")
	# the same UI-shape config through the direct sim, no commands at all
	var direct: SimWorld = _direct_world(cfg)
	for _i: int in 600:
		direct.step()
	t.eq(direct.checksum(), ctx.world().checksum(), "final checksum equals the direct sim")
	for tk: int in [200, 400, 600]:
		t.eq(direct.checksum_at(tk), int(checks.get(tk, -2)), "checksum at tick %d equals the direct sim" % tk)
	t.eq(ctx.session.command_log().cmds.size(), 0, "no command entered the lockstep")
	_finish(ctx)


## net S12 / D2: an all-AI LOCAL session (no local player, idle thinkers) against `SimMatchKit`'s direct run of the same match.
func test_all_ai_local_session_matches_simmatchkit(t: TestCtx) -> void:
	var cfg: Dictionary = AppMatch.simple_config(ROSTERS, 13, 96, 0, 0)
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(cfg, {"ticks": 400})
	AppAiHook.factory = Callable()
	if not t.not_null(ctx):
		return
	t.eq(ctx.session.local_pid, -1, "no human slot: an observer session")
	t.check(ctx.net.is_observer() and not ctx.net.can_submit(), "the net port refuses commands")
	_run(ctx, func() -> bool: return ctx.limit_reached)
	t.eq(made, [0, 1], "both slots were made by the hook")
	var kit: Dictionary = SimMatchKit.make_match({"rosters": ROSTERS, "seed": 13, "size": 96, "sim_seed": int(cfg["seed"]), "bots": false,
		"rules": {"fog": true, "victory": 1, "start_credits": 7500, "unit_cap": 150, "superweapons": true, "shared_vision": false, "veterancy": false}})
	var w: SimWorld = kit["world"] as SimWorld
	for _i: int in 400:
		w.step()
	t.eq(ctx.world().checksum(), w.checksum(), "LOCAL session == SimMatchKit after 400 ticks")
	t.eq(ctx.world().checksum_at(400), w.checksum_at(400))
	_finish(ctx)


func test_recorded_commands_replay_on_a_fresh_world(t: TestCtx) -> void:
	var cfg: Dictionary = _config(9)
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(cfg, {"ticks": 400})
	AppAiHook.factory = Callable()
	var w: SimWorld = ctx.world()
	var ids: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in w.entities:
		if e != null and e.owner == 0:
			ids.append(e.id)
	t.check(not ids.is_empty(), "the human owns entities")
	var chains: Array[int] = []
	ctx.session.checksum_observer = func(_tick: int, _cs: int, chain: int) -> void: chains.append(chain)
	t.check(ctx.net.submit(SimCmd.stop(ids)), "the port accepts a command")
	t.eq(ctx.commands_sent, 1)
	t.check(not ctx.net.submit(PackedInt32Array()), "an empty command is refused")
	_run(ctx, func() -> bool: return ctx.limit_reached)
	var ticks: int = ctx.tick()
	t.eq(ctx.session.command_log().cmds.size(), 1, "the command went through the lockstep and the log")
	var res: Dictionary = ctx.session.command_log().play(_direct_world(cfg), ticks)
	t.check(bool(res["ok"]), "the command log replays to the same checkpoints: %s" % str(res))
	t.eq(int(res["final"]), ctx.world().checksum())
	_finish(ctx)


func test_pause_resume_and_surrender(t: TestCtx) -> void:
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(_config(4))
	AppAiHook.factory = Callable()
	var s: NetSession = ctx.session
	t.eq(s.phase, NetSession.Phase.PLAYING)
	_run(ctx, func() -> bool: return ctx.tick() >= 40)
	t.eq(ctx.net.request_pause(true), 0, "a LOCAL player may pause")
	_run(ctx, func() -> bool: return s.is_paused())
	t.eq(s.phase, NetSession.Phase.PAUSED)
	var frozen: int = ctx.tick()
	for _i: int in 5:
		ctx.frame()
	t.eq(ctx.tick(), frozen, "no ticks while paused")
	t.eq(ctx.net.request_pause(false), 0)
	_run(ctx, func() -> bool: return not s.is_paused())
	t.eq(s.phase, NetSession.Phase.PLAYING)
	var status: Array[int] = []
	s.player_status_changed.connect(func(pid: int, st: int) -> void:
		if pid == 0:
			status.append(st))
	t.check(ctx.net.surrender(), "surrender is a command")
	_run(ctx, func() -> bool: return s.phase == NetSession.Phase.ENDED)
	t.eq(s.phase, NetSession.Phase.ENDED, "the sim ends the match when the last team wins")
	t.eq(status, [NetProtocol.PlayerNetStatus.RESIGNED], "the resignation is announced to the UI")
	var sum: Dictionary = AppMatch.result_summary(ctx)
	t.eq(sum["outcome"], UiMatchStats.OUTCOME_DEFEAT)
	t.eq(sum["result"], "defeat")
	var rows: Array = sum["players"] as Array
	t.check(bool((rows[0] as Dictionary)["eliminated"]), "the surrendering player is eliminated")
	t.eq(int((rows[0] as Dictionary)["status"]), NetProtocol.PlayerNetStatus.RESIGNED)
	_finish(ctx)


func test_takeover_hands_a_slot_to_the_ai(t: TestCtx) -> void:
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(_config(4))
	_run(ctx, func() -> bool: return ctx.tick() >= 20)
	var s: NetSession = ctx.session
	t.check(s.ai_runner != null and not s.ai_runner.has_ai(0), "the human slot has no thinker")
	s.turn_host.drop_player(0, NetProtocol.StallAction.STALL_DROP_AI, NetProtocol.ResignReason.DISCONNECT)
	_run(ctx, func() -> bool: return s.ai_runner.has_ai(0), 200)
	AppAiHook.factory = Callable()
	t.check(s.ai_runner.has_ai(0), "AI takeover asks the factory for a thinker")
	t.check(made.has(0), "through the app's AI hook")
	_finish(ctx)


# ---------------------------------------------------------------- AI

func test_ai_factory_installs_the_brain(t: TestCtx) -> void:
	var f: AiFactory = AiFactory.new()
	f.make(1, 2, 0, 5)
	t.check(f.thinker(1).controller.ctx.brain is AiBrain, "AiFactory.make installs the AiBrain module set")
	t.check(AiBrain.install(f.thinker(1).controller) == f.thinker(1).controller.ctx.brain, "install is idempotent")
	var bare: AiFactory = AiFactory.new()
	bare.install_brain = false
	bare.make(0, 1, 0, 5)
	t.is_null(bare.thinker(0).controller.ctx.brain, "install_brain = false leaves a bare thinker")


func test_released_ai_is_freed(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"rosters": ROSTERS, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	var hook: AppAiHook = AppAiHook.new()
	var th: Callable = hook.make(1, 2, 0, 5)
	var out: Array = []
	for _i: int in 40:
		out.clear()
		th.call(w, out)
		w.step()
	var ctx_ref: WeakRef = weakref(hook.ai.thinker(1).controller.ctx)
	th = Callable()
	hook.shutdown()
	t.is_null(hook.ai.thinker(1), "shutdown drops the thinkers")
	t.is_null(ctx_ref.get_ref(), "and the brain <-> context cycle no longer keeps the AI (and its world view) alive")


func test_ai_think_period_follows_the_difficulty(t: TestCtx) -> void:
	t.eq(AppAiHook.think_period_turns(0), 15, "Easy thinks every 30 ticks")
	t.eq(AppAiHook.think_period_turns(1), 10)
	t.eq(AppAiHook.think_period_turns(2), 5)
	t.eq(AppAiHook.think_period_turns(3), 3, "Brutal every 6 ticks")


func test_real_ai_plays_through_the_session(t: TestCtx) -> void:
	var cfg: Dictionary = _config(11)
	((cfg["players"] as Array)[1] as Dictionary)["ai"] = {"level": 2, "style": 0, "flags": 0}
	var ctx: AppMatchContext = _start(cfg, {"ticks": 1400})
	if not t.not_null(ctx):
		return
	_run(ctx, func() -> bool: return ctx.limit_reached, 900)
	var rep: Dictionary = SimMatchKit.report(ctx.world(), 1)
	t.gt(int(rep["spent_construction"]) + int(rep["spent_units"]), 0, "the Hard AI in slot 1 built and trained through the bundles")
	t.check(ctx.ai.ai.thinker(1) != null and ctx.ai.ai.thinker(1).controller.ctx.brain is AiBrain, "with the brain installed")
	t.gt(ctx.session.command_log().cmds.size(), 1, "its commands are in the lockstep log")
	# the same match again: the whole thing is deterministic
	var again: AppMatchContext = _start(cfg, {"ticks": 1400})
	_run(again, func() -> bool: return again.limit_reached, 900)
	t.eq(again.world().checksum(), ctx.world().checksum(), "the same config gives the same state (AI included)")
	_finish(ctx)
	_finish(again)


func test_bot_modes(t: TestCtx) -> void:
	var args: AppLaunchArgs = AppLaunchArgs.parse(PackedStringArray(["--bots"]))
	t.eq(AppBootHook.bot_mode(args), "ai")
	t.eq(AppBootHook.bot_mode(AppLaunchArgs.parse(PackedStringArray(["--bots=all"]))), "all")
	t.eq(AppBootHook.bot_mode(AppLaunchArgs.parse(PackedStringArray(["--bots=human"]))), "human")
	t.eq(AppBootHook.bot_mode(AppLaunchArgs.parse(PackedStringArray(["--ticks=5"]))), "")
	AppAiHook.set_bot_mode("human")
	t.check(AppAiHook.human_is_bot() and not AppAiHook.bots_enabled, "human mode: real AI opponents, a bot human")
	AppAiHook.set_bot_mode("all")
	t.check(AppAiHook.human_is_bot() and AppAiHook.bots_enabled)
	AppAiHook.set_bot_mode("")
	t.check(not AppAiHook.human_is_bot() and not AppAiHook.bots_enabled)
	# --bots: the scripted bot replaces the AI slot and acts through the bundles
	AppAiHook.set_bot_mode("ai")
	var ctx: AppMatchContext = _start(_config(3), {"ticks": 500})
	AppAiHook.set_bot_mode("")
	_run(ctx, func() -> bool: return ctx.limit_reached, 600)
	t.gt(ctx.session.command_log().cmds.size(), 0, "the SimBot in slot 1 issued commands")
	_finish(ctx)
	# --bots=human: the bot plays the local slot through submit_command
	AppAiHook.set_bot_mode("human")
	var h: AppMatchContext = _start(_config(3), {"ticks": 500})
	AppAiHook.set_bot_mode("")
	_run(h, func() -> bool: return h.limit_reached, 600)
	t.not_null(h.human_bot, "the context runs a human bot")
	t.gt(h.human_bot.commands(), 0, "and it issued commands")
	_finish(h)


# ---------------------------------------------------------------- limits and the end model

func test_tick_limit_and_pause_at(t: TestCtx) -> void:
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(_config(2), {"ticks": 200, "pause_at": 100})
	AppAiHook.factory = Callable()
	_run(ctx, func() -> bool: return ctx.session.is_paused(), 200)
	t.check(ctx.session.is_paused(), "pause-at holds the sim")
	t.check(ctx.tick() >= 100 and ctx.tick() <= 108, "near the requested tick (%d)" % ctx.tick())
	_finish(ctx)


func test_end_model_from_a_three_player_match(t: TestCtx) -> void:
	var cfg: Dictionary = _config(21, ROSTERS3)
	var pl: Array = cfg["players"] as Array
	(pl[1] as Dictionary)["ai"] = {"level": 1, "style": 0, "flags": 0}
	(pl[2] as Dictionary)["ai"] = {"level": 2, "style": 0, "flags": 0}
	var ctx: AppMatchContext = _start(cfg, {"ticks": 1500})
	_run(ctx, func() -> bool: return ctx.limit_reached, 1200)
	var end: Dictionary = {"reason": NetProtocol.MatchEndReason.SIM_DECIDED, "winner_team": -1, "final_tick": ctx.tick(), "final_checksum": ctx.world().checksum()}
	var sum: Dictionary = ctx.summary(end)
	t.eq((sum["players"] as Array).size(), 3)
	t.eq(sum["outcome"], UiMatchStats.OUTCOME_DRAW)
	t.eq(int(sum["duration_ticks"]), 1500)
	t.gt(ctx.stats.sample_count(), 6, "the time series has a sample per 200 ticks")
	var row1: Dictionary = (sum["players"] as Array)[1] as Dictionary
	t.check(bool(row1["is_ai"]) and int(row1["ai_level"]) == 1)
	t.gt(int((row1["stats"] as Dictionary)["units_built"]) + int((row1["stats"] as Dictionary)["structures_built"]), 0, "the AI built things")
	t.eq(int((row1["stats"] as Dictionary)["value_destroyed"]), -1, "counters the sim does not keep yet are -1")
	t.check(sum["series"].has(2), "series exist for every player")
	t.check(int(row1["score"]) >= 0 and int(row1["apm"]) >= 0)
	_finish(ctx)


func test_score_formula(t: TestCtx) -> void:
	var st: Dictionary = {"value_destroyed": 42000, "harvested": 60000, "research_done": 3, "powers_used": 4, "sw_launched": 1, "commands": 1800}
	var sc: Dictionary = UiScore.compute(st)
	t.eq(int(sc["military"]), 4200)
	t.eq(int(sc["economy"]), 3000)
	t.eq(int(sc["technology"]), 750)
	t.eq(int(sc["total"]), 7950, "the worked example of ui.md 5.16.5")
	t.check(not bool(sc["estimated"]))
	t.eq(UiScore.apm(1800, 1500 * 20), 72, "1800 commands in a 1500 s match")
	var est: Dictionary = UiScore.compute({"value_destroyed": -1, "units_killed": 10, "structures_destroyed": 2, "harvested": 0})
	t.check(bool(est["estimated"]), "without the value counter the military term is estimated from kills")
	t.eq(int(est["military"]), (10 * UiScore.KILL_UNIT_VALUE + 2 * UiScore.KILL_STRUCT_VALUE) / UiScore.MILITARY_DIV)


func test_app_net_autoload_drives_and_ends_the_session(t: TestCtx) -> void:
	var net: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("AppNet")
	if not t.not_null(net, "the AppNet autoload is registered"):
		return
	var made: Array = []
	AppAiHook.factory = _idle_ai(made)
	var ctx: AppMatchContext = _start(_config(8))
	AppAiHook.factory = Callable()
	t.check(net.get("ctx") == ctx, "start_local hands the context to AppNet")
	t.check(net.call("session") == ctx.session)
	t.is_null(ctx.driver, "and no fallback driver node exists")
	var app: Node = (Engine.get_main_loop() as SceneTree).root.get_node("AppState")
	t.check(app.get("match_ctx") == ctx, "AppState holds the context")
	var opts: NetSessionOptions = net.call("make_options", {"with_view": false}) as NetSessionOptions
	t.eq(opts.player_name, NetProtocol.sanitize_name(str((Engine.get_main_loop() as SceneTree).root.get_node("AppSettings").call("get_str", &"net/player_name"))))
	net.call("end_session")
	t.is_null(net.get("ctx"), "end_session lets go")
	t.check(ctx.disposed and ctx.session.phase == NetSession.Phase.IDLE, "and shuts the session down")
	t.is_null(app.get("match_ctx"), "and clears AppState.match_ctx")


func test_state_binding_of_the_flow(t: TestCtx) -> void:
	var st: Node = load("res://src/app/app_state.gd").new() as Node
	var fake: Object = FakeSession.new()
	st.call("bind_session", fake, true)
	t.eq(fake.get_signal_connection_list("match_ended").size(), 0, "end_via_screen leaves match_ended to the game screen")
	t.eq(fake.get_signal_connection_list("match_started").size(), 1)
	st.call("unbind_session")
	t.eq(fake.get_signal_connection_list("match_started").size(), 0, "unbind releases the connections")
	st.free()


class FakeSession extends RefCounted:
	signal match_started()
	signal launch_aborted(reason: int, detail: String)
	signal match_ended(result: Dictionary)
	signal kicked(reason: int, detail: String)
