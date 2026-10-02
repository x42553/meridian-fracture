class_name AppTestBoot
extends RefCounted
## Headless / test boot (ui.md 5.2.3): `--autostart=match` builds a LOCAL session from `--config=<json>` (or from the flags
## below), runs it to the end or to `--ticks=N`, prints greppable lines and exits.
##
##   tools/gd run res://src/app/boot.tscn -- --autostart=match --ticks=600 --speed=0 --bots [--players=2 --humans=1]
##
## Flags (besides the AppLaunchArgs ones): `--ticks=N` (0 = until the match ends), `--speed=<pct>` (0 = unpaced), `--with-ui` (go
## through the real LOADING -> IN_MATCH screens, so the HUD, presenter and input controller run against the real ports),
## `--bots` (AI slots are played by the scripted test bot; `--bots=all` also the human slots; `--bots=human` only the human slot, the AI
## slots use the real AI), `--ai-levels=1,2` (levels of the AI slots in order; `--ai-level=L` sets all), `--players=N` (2..8),
## `--humans=H` (leading human slots, default 1), `--rosters=a,b,...` (roster ids), `--map-seed=S`, `--map-size=N`,
## `--family=0|1|2`, `--ai-level=L`, `--fog=0|1`, `--quit-on-end`, `--timeout-s=S`, `--pause-at=N` (GUI shots: pause the sim at tick N),
## `--with-view` (headless proof runs: build the real view and FX stage on the dummy renderer and feed it), `--pause-when=build|wreck|fight [--pause-after=10]` (pause N ticks after the first construction / wreck / fight of the match), `--focus=fight|build|wreck [--focus-zoom=0.25]` (GUI: the camera follows the hottest fight / the first structure being built / the newest wreck), `--surrender-at=N` (the local player surrenders at tick N: exercises the end banner), `--preview=<tags>` (game screen: `select`, `units`, `place`), `--drive` (GUI: at tick `--drive-tick`, default 2400, a scripted human
## drags a selection box over its units and right-clicks the ground through real input events; prints `APPTEST_DRIVE`).
## VQ2B showcase captures: `--scenario=showcase` (AppScenario: rich credits, instant tech base, charged + launched superweapon, staged `--battle=ground|air|naval`
## fights, `--army=N`), `--cap=T1,T2,.. --cap-out=<prefix>` (window PNGs `<prefix>_<tick>.png` at those sim ticks, then the run ends), `--focus=sw|crowd|fight|wreck|..`
## (camera follows the superweapon target / the busiest crowd / ...), `--cap-keep` (do not end after the last capture); `APPTEST_SHAKE` reports the camera trauma.
## HOT1: `--keys="F5@80;movehq:4,0@85;clickhq:4,0@100"` pushes real key / mouse events at those sim ticks (see `AppTestKeys`), `--cap=` captures the result.
## MIS2 missions: `--autostart=mission=<id> [--difficulty=0..3 (default 1) --ticks=N --speed=0 --bots=human --with-ui ...]` starts that scripted mission
## (game/data/missions) through `AppMission.start` (LOCAL session, the AI levels shifted by the difficulty); `--bots=human` lets the scripted bot play
## the human slot. Extra lines: `APPTEST_MISSION tick= result= objectives=<id:state,...> timers=<id:state:left,...>` with every report and
## `APPTEST_MISSION_END id= difficulty= result=win|lose|none tick= objectives=... campaign=...` at the end (`--mission=<id>` is the older spelling).
## LAN: `--autostart=lan-host` and `--autostart=lan-join=<address>` dispatch to `AppLanTestBoot` (two headless processes play a whole LAN game
## through the real lobby / launch / match path; driver `tools/py/app_two_process.py`, flags documented there).
## Output: `APP_READY mode=match data_hash=<%08X>`, every 200 ticks `APPTEST tick=<n> chain=<%08X> checksum=<%08X> cmds=<n>
## ui_cmds=<n> refused=<n>`, and `APPTEST_END reason=<victory|defeat|ticks|timeout> tick=<n>`. Exit codes: 0 ok, 2 data load
## failed, 3 world build failed, 5 timeout.

const DEFAULT_ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.def.vanilla",
	"roster.olm.vanilla", "roster.pd.vanilla", "roster.ae.vanilla", "roster.sap.vanilla"]
const REPORT_EVERY: int = 200


## Coroutine (AppBoot awaits it). Never returns normally: it quits the tree with the exit code.
static func run(host: Node, args: AppLaunchArgs) -> void:
	var tree: SceneTree = host.get_tree()
	if String(args.autostart).begins_with("lan-"):
		await AppLanTestBoot.run(host, args)  # `--autostart=lan-host` / `lan-join=<address>` (task APP2, tools/py/app_two_process.py)
		return
	if String(args.autostart).begins_with("replay"):
		await AppReplayBoot.run(host, args)  # `--autostart=replay=<file.mfreplay>` (task REP2)
		return
	var state: Node = tree.root.get_node_or_null("AppState")
	var data: GameData = state.get("data") as GameData if state != null else null
	if data == null:
		_out("APPTEST_END reason=data tick=0")
		tree.quit(2)
		return
	_out("APP_READY mode=match data_hash=%08X" % data.data_hash())
	AppAiHook.set_bot_mode(AppBootHook.bot_mode(args))
	var mission_id: String = AppMission.id_of_autostart(String(args.autostart))
	if mission_id == "" and args.extras.has("mission"):
		mission_id = str(args.extras["mission"])
	var config: Dictionary = _config(args) if mission_id == "" else {}
	var headless: bool = DisplayServer.get_name() == "headless"
	var unpaced: bool = args.speed_pct == 0
	var force_view: bool = headless and args.extras.has("with-view")  # proof runs: the real view + FX stage on the dummy renderer
	var opts: Dictionary = {"with_view": not headless or force_view, "unpaced": unpaced, "ticks": args.ticks, "title": "Skirmish",
		"discard_events": (headless or not args.with_ui) and not force_view, "pause_at": int(args.extras.get("pause-at", 0)),
		"speed_pct": args.speed_pct if NetProtocol.SPEED_PCT.has(args.speed_pct) else 0}
	opts["bind"] = args.with_ui
	if args.with_ui:
		var loading_def: DefMission = AppMission.def_of(data, mission_id) if mission_id != "" else null
		state.call("go", AppFlow.Mode.LOADING, {"kind": "match", "title": loading_def.ui_title if loading_def != null else "Skirmish"})
	var ctx: AppMatchContext = null
	if mission_id != "":
		opts.erase("title")
		ctx = AppMission.start(mission_id, int(args.extras.get("difficulty", AppMission.DEFAULT_DIFFICULTY)), opts)
	else:
		ctx = AppMatch.start_local(config, opts)
	if ctx == null:
		_out("APPTEST_END reason=world tick=0 detail=%s" % NetSession.last_create_error)
		tree.quit(3)
		return
	ctx.preview = str(args.extras.get("preview", ""))
	var session: NetSession = ctx.session
	var t0: int = Time.get_ticks_msec()
	var failed: PackedStringArray = PackedStringArray()
	session.launch_aborted.connect(func(_r: int, detail: String) -> void: failed.append(detail))
	if args.extras.has("ck-lines"):
		# `--ck-lines`: the checksum and input chain at every 200th tick, exactly the lines `--autostart=replay` prints (task REP2)
		session.checksum_observer = func(tick: int, cs: int, chain: int) -> void:
			if tick > 0 and tick % AppReplayBoot.CK_EVERY == 0:
				_out("APPTEST_CK tick=%d chain=%08X checksum=%08X" % [tick, chain & 0xFFFFFFFF, cs & 0xFFFFFFFF])
	var next_report: int = REPORT_EVERY
	var driven: bool = false
	var surrender_at: int = int(args.extras.get("surrender-at", 0))
	var drive_tick: int = int(args.extras.get("drive-tick", 2400))
	var focus_what: String = str(args.extras.get("focus", ""))
	var focus_zoom: float = float(str(args.extras.get("focus-zoom", "0.25"))) if focus_what in ["fight", "build", "wreck", "dock", "air", "naval", "crowd", "sw"] else -1.0
	var scen: AppScenario = AppScenario.from_args(args)  # `--scenario=showcase` (late-game debug scenario, LOCAL runs only)
	var caps: PackedInt32Array = PackedInt32Array()  # `--cap=T1,T2 --cap-out=<prefix>`: PNGs of the window at those ticks, then quit
	for c: String in str(args.extras.get("cap", "")).split(",", false):
		caps.append(c.to_int())
	var cap_i: int = 0
	var shake_sum: float = 0.0
	var shake_max: float = 0.0
	var shake_hi: int = 0
	var shake_n: int = 0
	var last_focus: int = -1
	var perf: AppPerfProbe = AppPerfProbe.create(str(args.extras["perf-log"]), str(args.extras.get("perf-label", ""))) if args.extras.has("perf-log") else null
	if perf != null:
		perf.warmup_ticks = int(args.extras.get("perf-warmup", 100))
		perf.sample_ticks = int(args.extras.get("perf-every-ticks", 0))
	var cam_zoom: float = float(str(args.extras.get("cam-zoom", "-1")))  # screenshots: park the camera at this zoom (0 near .. 1 far) once the match runs
	var cam_pitch: float = float(str(args.extras.get("cam-pitch", "0")))  # tilt bias in degrees
	var cam_yaw: float = float(str(args.extras.get("cam-yaw", "0")))
	var cam_done: bool = false
	var mm_click: PackedStringArray = str(args.extras.get("minimap-click", "")).split(",", false)  # screenshots: left-click the minimap at normalised x,y
	var ui_tab: int = int(str(args.extras.get("ui-tab", "-1")))  # screenshots: open this sidebar tab (0 structures .. 7 powers)
	var keys: AppTestKeys = AppTestKeys.parse(str(args.extras.get("keys", "")))
	var stress_n: int = int(args.extras.get("stress-units", 0))
	var stress_at: int = int(args.extras.get("stress-at", 300))
	var pause_when: String = str(args.extras.get("pause-when", ""))
	if pause_when != "" and ctx.session != null and ctx.session.opts != null:
		ctx.session.opts.max_ticks_per_poll = 1  # one tick per frame: the moment is caught exactly
	while session.phase != NetSession.Phase.ENDED and not ctx.limit_reached:
		await tree.process_frame
		if AppShutdown.quitting:
			return  # an orderly quit started (window close, AppQuitHook, Quit): let this coroutine end instead of leaking it at exit
		if not failed.is_empty():
			_out("APPTEST_END reason=world tick=0 detail=%s" % failed[0])
			tree.quit(3)
			return
		if (Time.get_ticks_msec() - t0) / 1000 > args.timeout_s:
			_out("APPTEST_END reason=timeout tick=%d" % ctx.tick())
			tree.quit(5)
			return
		if session.phase == NetSession.Phase.IDLE and ctx.world() == null:
			continue
		var playing: bool = session.phase == NetSession.Phase.PLAYING
		if args.extras.has("drive") and not driven and playing and ctx.tick() >= drive_tick and not headless:
			driven = true
			await _drive(tree, ctx)
		if keys != null and playing and not headless:
			keys.step(tree, ctx)  # `--keys=` (task HOT1): scripted real key / mouse events
		if scen != null and playing:
			scen.step(ctx.world())
			if ctx.stage != null and ctx.stage.view != null and ctx.stage.view.camera != null:
				var trauma: float = ctx.stage.view.camera.trauma()  # shake telemetry of the showcase runs (APPTEST_SHAKE)
				shake_sum += trauma
				shake_max = maxf(shake_max, trauma)
				shake_hi += 1 if trauma > 0.5 else 0
				shake_n += 1
		if cap_i < caps.size() and playing and ctx.tick() >= caps[cap_i] and not headless:
			await RenderingServer.frame_post_draw
			var cap_path: String = "%s_%d.png" % [str(args.extras.get("cap-out", "user://cap")), caps[cap_i]]
			var cap_img: Image = tree.root.get_texture().get_image()
			_out("APPTEST_CAP %s tick=%d err=%d" % [cap_path, ctx.tick(), cap_img.save_png(cap_path)])
			cap_i += 1
			if cap_i >= caps.size() and not args.extras.has("cap-keep"):
				ctx.limit_reached = true
		if surrender_at > 0 and playing and ctx.tick() >= surrender_at:
			surrender_at = 0
			session.surrender()
		if force_view and ctx.stage != null and is_instance_valid(ctx.stage) and ctx.stage.built and ctx.world() != null:
			if ctx.stage.fx_stage != null and not ctx.stage.fx_stage.router.record:
				ctx.stage.fx_stage.router.record = true  # the proof run reports which effects were spawned
			# no game screen in this run: feed the view stage (mirror + FX router) the frame's events, as UiScreenGame does
			ctx.stage.frame(host.get_process_delta_time(), session.tick_alpha(), ctx.world().events.take())
		if pause_when != "" and playing and ctx.pause_at_tick == 0 and ctx.world() != null and AppDevCamera.event_seen(ctx.world(), pause_when):
			ctx.pause_at_tick = ctx.tick() + int(args.extras.get("pause-after", 10))  # a screenshot of the moment, not of a tick number
			_out("APPTEST_PAUSE_WHEN %s seen_at=%d pause_at=%d %s" % [pause_when, ctx.tick(), ctx.pause_at_tick, AppDevCamera.describe(ctx.world(), pause_when)])
		if mm_click.size() == 2 and playing and ctx.tick() >= 60 and not headless:
			var scn2: Node = tree.root.get_node_or_null("AppScenes")
			var gs2: UiScreenGame = scn2.get("screen") as UiScreenGame if scn2 != null else null
			if gs2 != null and gs2.hud != null:
				var mm: UiMinimap = gs2.hud.minimap()
				var mr: Rect2 = mm.map_rect()
				var at: Vector2 = mm.get_global_rect().position + mr.position + Vector2(mr.size.x * mm_click[0].to_float(), mr.size.y * mm_click[1].to_float())
				_motion(at, 0)
				await tree.process_frame
				_mouse(at, MOUSE_BUTTON_LEFT, true)
				await tree.process_frame
				_mouse(at, MOUSE_BUTTON_LEFT, false)
				mm_click = PackedStringArray()
		if ui_tab >= 0 and playing and ctx.tick() >= 40 and not headless:
			var scn: Node = tree.root.get_node_or_null("AppScenes")
			var gs: UiScreenGame = scn.get("screen") as UiScreenGame if scn != null else null
			if gs != null and gs.hud != null:
				gs.hud.sidebar().select_tab(ui_tab, true)
				ui_tab = -1
		if cam_zoom >= 0.0 and not cam_done and playing and ctx.tick() >= 20 and not headless and ctx.view != null:
			var cs: Dictionary = ctx.view.camera_state()
			if not cs.is_empty():
				cam_done = true
				cs["zoom"] = cam_zoom
				cs["pitch_bias"] = cam_pitch
				cs["yaw"] = cam_yaw
				ctx.view.set_camera_state(cs, true)
		if focus_zoom >= 0.0 and playing and ctx.tick() % (48 if focus_what == "crowd" else 12) == 0 and not headless and ctx.tick() != last_focus:
			last_focus = ctx.tick()
			AppDevCamera.follow_fight(ctx.view, ctx.world(), focus_zoom, focus_what)
		if stress_n > 0 and playing and ctx.tick() >= stress_at and ctx.world() != null:
			_out("APPTEST_STRESS spawned=%d at_tick=%d" % [AppStress.spawn(ctx.world(), stress_n), ctx.tick()])
			stress_n = 0
		if perf != null and playing:
			perf.frame(ctx)
		if playing and ctx.tick() >= next_report and perf == null:  # the report recomputes the full state checksum (~10 ms at 500 entities): not while measuring frames
			_report(ctx)
			next_report = ctx.tick() - ctx.tick() % REPORT_EVERY + REPORT_EVERY
	_report(ctx)
	if perf != null:
		_out("APPPERF " + JSON.stringify(perf.finish(ctx)))
	var reason: String = "ticks"
	var end: Dictionary = ctx.last_end
	if session.phase == NetSession.Phase.ENDED and int(end.get("reason", 0)) == NetProtocol.MatchEndReason.SIM_DECIDED:
		reason = str(ctx.summary().get("result", "ended"))
	elif end.is_empty():
		var w: SimWorld = ctx.world()
		end = {"reason": NetProtocol.MatchEndReason.SIM_DECIDED, "winner_team": -1, "final_tick": ctx.tick(),
			"final_checksum": w.checksum() if w != null else 0}
	_summary(ctx, end)
	if mission_id != "":
		_mission_end(ctx, mission_id)
	if AppAudio.current != null:
		_out("APPTEST_AUDIO " + AppAudio.current.report(float(ctx.tick()) * float(SimConfig.TICK_MS) / 1000.0))
	if ctx.stage != null and ctx.stage.fx_stage != null:
		_out("APPTEST_FX " + JSON.stringify(ctx.stage.fx_stage.stats().get("router", {})))
		var hist: Dictionary = {}
		for rec: Variant in ctx.stage.fx_stage.router.spawn_log:
			var fid: String = String((rec as Array)[0])
			hist[fid] = int(hist.get(fid, 0)) + 1
		_out("APPTEST_FX_IDS n=%d %s" % [hist.size(), JSON.stringify(hist)])
	if shake_n > 0:
		_out("APPTEST_SHAKE frames=%d avg=%.3f max=%.3f frac_over_half=%.3f" % [shake_n, shake_sum / float(shake_n), shake_max, float(shake_hi) / float(shake_n)])
	_out("APPTEST_END reason=%s tick=%d" % [reason, ctx.tick()])
	if args.quit_on_end or headless or (args.ticks > 0 and not args.with_ui):
		AppShutdown.begin_quit(tree)
		await AppAudio.release_for_quit(tree)
		AppShutdown.prepare_quit(tree)  # screens exit, then the context is disposed (a screen still holding it would keep the whole world in a reference cycle)
		ctx.dispose()
		AppShutdown.release_statics()
		tree.quit(0)


## A scripted human through real input events (pushed into the root viewport, so they take the GUI path): box-select the own units on screen, then a right click
## on the ground. Everything after the events is the normal UI path (controller -> selection -> resolver -> command bus).
static func _drive(tree: SceneTree, ctx: AppMatchContext) -> void:
	var scenes: Node = tree.root.get_node_or_null("AppScenes")
	var game: UiScreenGame = scenes.get("screen") as UiScreenGame if scenes != null else null
	if game == null or ctx.sim == null:
		_out("APPTEST_DRIVE skipped=no_game_screen")
		return
	var ids: PackedInt32Array = PackedInt32Array()
	ctx.sim.own_ids(UiSimPort.KM_UNIT, ids)
	var box: Rect2 = Rect2()
	var have: bool = false
	for id: int in ids:
		var r: Rect2 = ctx.view.entity_screen_rect(id)
		if r.size == Vector2.ZERO or r.position.x > 1500.0:
			continue
		box = r if not have else box.merge(r)
		have = true
	if not have:
		_out("APPTEST_DRIVE skipped=no_units_on_screen units=%d" % ids.size())
		return
	box = box.grow(30.0).intersection(Rect2(24.0, 24.0, 1500.0, 780.0))
	var before: int = ctx.commands_sent
	game.controller.synthetic = true  # pushed events do not update Input: skip the lost-release poll
	_motion(box.position, 0)
	await tree.process_frame
	_mouse(box.position, MOUSE_BUTTON_LEFT, true)
	await tree.process_frame
	_motion(box.get_center(), MOUSE_BUTTON_MASK_LEFT)
	await tree.process_frame
	_motion(box.end, MOUSE_BUTTON_MASK_LEFT)
	await tree.process_frame
	_mouse(box.end, MOUSE_BUTTON_LEFT, false)
	await tree.process_frame
	await tree.process_frame
	var selected: int = game.selection.size()
	var target: Vector2 = Vector2(clampf(box.get_center().x + 260.0, 100.0, 1400.0), clampf(box.get_center().y - 140.0, 120.0, 800.0))
	_motion(target, 0)
	await tree.process_frame
	_mouse(target, MOUSE_BUTTON_RIGHT, true)
	await tree.process_frame
	_mouse(target, MOUSE_BUTTON_RIGHT, false)
	for _i: int in 6:
		await tree.process_frame
	_out("APPTEST_DRIVE box=%s selected=%d of %d cmds=%d" % [box, selected, ids.size(), ctx.commands_sent - before])


static func _mouse(pos: Vector2, button: int, pressed: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button as MouseButton
	e.pressed = pressed
	e.button_mask = ((1 << (button - 1)) if pressed else 0) as MouseButtonMask
	(Engine.get_main_loop() as SceneTree).root.push_input(e)


static func _motion(pos: Vector2, mask: int) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = mask as MouseButtonMask
	(Engine.get_main_loop() as SceneTree).root.push_input(e)


static func _report(ctx: AppMatchContext) -> void:
	var w: SimWorld = ctx.world()
	if w == null:
		return
	if w.mission != null:
		_out("APPTEST_MISSION tick=%d result=%s objectives=%s timers=%s" % [w.tick, result_word(w.mission.result), objectives_text(w), timers_text(w)])
	var chain: int = int(ctx.session.stats().get("chain", 0))
	var cmds: int = ctx.session.command_log().cmds.size() if ctx.session.command_log() != null else 0
	_out("APPTEST tick=%d chain=%08X checksum=%08X cmds=%d ui_cmds=%d refused=%d" % [w.tick, chain & 0xFFFFFFFF, w.checksum() & 0xFFFFFFFF,
		cmds, ctx.commands_sent, 0])


static func result_word(r: int) -> String:
	return "win" if r == SimMissionConst.RES_WIN else ("lose" if r == SimMissionConst.RES_LOSE else "none")


## "id:state,id:state" of the mission's objectives (states: hidden, active, completed, failed).
static func objectives_text(w: SimWorld) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in w.mission.def.objectives.size():
		parts.append("%s:%s" % [w.mission.def.objectives[i].id, DefMissionObjective.STATE_NAMES[w.mission.obj_state[i]]])
	return ",".join(parts)


## "id:state:left_ticks" of the mission's timers (stopped, running, expired).
static func timers_text(w: SimWorld) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = ["stopped", "running", "expired"]
	for i: int in w.mission.def.timers.size():
		var left: int = maxi(w.mission.timer_end[i] - w.tick, 0) if w.mission.timer_state[i] == SimMissionConst.TM_RUNNING else 0
		parts.append("%s:%s:%d" % [w.mission.def.timers[i].id, names[w.mission.timer_state[i]], left])
	return ",".join(parts)


static func _mission_end(ctx: AppMatchContext, mission_id: String) -> void:
	var w: SimWorld = ctx.world()
	if w == null or w.mission == null:
		return
	var out: Dictionary = ctx.mission_outcome
	_out("APPTEST_MISSION_END id=%s difficulty=%d result=%s tick=%d objectives=%s won=%s first_clear=%s new_best=%s" % [mission_id, ctx.mission_difficulty,
		result_word(w.mission.result), w.tick, objectives_text(w), str(out.get("won", false)), str(out.get("first_clear", false)),
		str(out.get("new_best_time", false))])


## The end-screen model on stdout: `APPTEST_SUMMARY outcome= duration_s= players=N samples=N` and one `APPTEST_PLAYER` line per player.
static func _summary(ctx: AppMatchContext, end: Dictionary) -> void:
	var sum: Dictionary = ctx.summary(end)
	var rows: Array = sum["players"] as Array
	_out("APPTEST_SUMMARY result=%s winner_team=%d duration_ticks=%d players=%d samples=%d" % [sum["result"], int(sum["winner_team"]),
		int(sum["duration_ticks"]), rows.size(), ctx.stats.sample_count()])
	for r: Variant in rows:
		var pr: Dictionary = r as Dictionary
		var st: Dictionary = pr["stats"] as Dictionary
		_out("APPTEST_PLAYER pid=%d name=%s ai=%s level=%d team=%d built=%d lost=%d killed=%d structs=%d/%d earned=%d spent=%d score=%d apm=%d elim=%s" % [
			int(pr["pid"]), str(pr["name"]).replace(" ", "_"), str(pr["is_ai"]), int(pr["ai_level"]), int(pr["team"]),
			int(st["units_built"]), int(st["units_lost"]), int(st["units_killed"]), int(st["structures_built"]), int(st["structures_lost"]),
			int(st["harvested"]), int(st["spent"]), int(pr["score"]), int(pr["apm"]), str(pr["eliminated"])])


## The match config: `--config=<json file>` or built from the flags.
static func _config(args: AppLaunchArgs) -> Dictionary:
	if not args.config_path.is_empty():
		var txt: String = FileAccess.get_file_as_string(args.config_path)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			return parsed as Dictionary
		Log.error("app", "--config=%s is not a JSON object; using the default match" % args.config_path)
	if args.extras.has("mission"):  # MIS1: `--mission=<id>` starts that scripted mission (game/data/missions) as a LOCAL match
		var mcfg: Dictionary = SimMissionSetup.build_config(GameData.load_default(), str(args.extras["mission"]))
		if not mcfg.is_empty():
			return mcfg
		Log.error("app", "--mission=%s: unknown mission; using the default match" % str(args.extras["mission"]))
	var n: int = clampi(int(args.extras.get("players", 2)), 2, 8)
	var humans: int = clampi(int(args.extras.get("humans", 1)), 0, n)
	var rosters: PackedStringArray = PackedStringArray()
	if args.extras.has("rosters"):
		rosters = str(args.extras["rosters"]).split(",", false)
	for i: int in range(rosters.size(), n):
		rosters.append(DEFAULT_ROSTERS[i % DEFAULT_ROSTERS.size()])
	rosters.resize(n)
	var cfg: Dictionary = AppMatch.simple_config(rosters, int(args.extras.get("map-seed", 1)), int(args.extras.get("map-size", 96)),
		int(args.extras.get("family", 0)), humans)
	var mparams: Dictionary = ((cfg["map"] as Dictionary)["params"] as Dictionary)
	for k: String in ["biome", "water_pct", "density", "resources", "neutrals"]:
		if args.extras.has(k):
			mparams[k] = int(args.extras[k])
	var levels: PackedStringArray = str(args.extras.get("ai-levels", "")).split(",", false)
	var ai_i: int = 0
	for p: Variant in cfg["players"] as Array:
		var pd: Dictionary = p as Dictionary
		if not pd.has("ai"):
			continue
		if args.extras.has("ai-level"):
			(pd["ai"] as Dictionary)["level"] = int(args.extras["ai-level"])
		if ai_i < levels.size():
			(pd["ai"] as Dictionary)["level"] = clampi(levels[ai_i].to_int(), 0, AiFactory.level_count() - 1)
		ai_i += 1
	if args.extras.has("credits"):
		(cfg["rules"] as Dictionary)["start_credits"] = int(args.extras["credits"])  # perf probes: rich AIs reach 400+ entities within minutes
	if args.extras.has("unit-cap"):
		(cfg["rules"] as Dictionary)["unit_cap"] = int(args.extras["unit-cap"])
	if args.extras.has("fog"):
		(cfg["rules"] as Dictionary)["fog"] = int(args.extras["fog"]) != 0
	else:
		(cfg["rules"] as Dictionary)["fog"] = false
	return cfg


static func _out(line: String) -> void:
	# lint-allow: L006 greppable test-boot protocol lines (ui.md 5.2.3), parsed by tools and CI
	print(line)

