class_name AppReplayBoot
extends RefCounted
## `--autostart=replay=<file.mfreplay>` (task REP2): plays a recorded match back through the real app path (`AppReplay.start` ->
## `AppMatchContext` -> `AppReplaySession` -> `NetReplayPlayer`), headless or in a window, and prints greppable lines like the live
## `--autostart=match` run does, so a recording and its playback can be compared line by line:
##
##   tools/gd run res://src/app/boot.tscn -- --autostart=match --ticks=3000 --speed=0 --ck-lines --record-replays --replay-dir=<dir> ...
##   tools/gd run res://src/app/boot.tscn -- --autostart=replay=<dir>/autosave_1.mfreplay --ck-lines
##
## Output: `APP_READY mode=replay data_hash=<%08X>`, with `--ck-lines` an `APPTEST_CK tick=<n> chain=<%08X> checksum=<%08X>` line at every
## 200th tick (the same lines the match run prints under `--ck-lines`), then `APPTEST_SUMMARY` / `APPTEST_PLAYER` (as the match run),
## `APPTEST_REPLAY ok=<0|1> ticks= compared= verified_through= diverged= chain= checksum= recorded_checksum=` and
## `APPTEST_END reason=replay tick=<n>`. Flags: `--with-ui` (real LOADING -> REPLAY_PLAYBACK screens in a window), `--speed=<pct>`
## (0 = as fast as possible, the headless default), `--seek-demo` (seeks forward, backward and to the end first), `--timeout-s=S`,
## `--allow-mismatch`. Exit codes: 0 ok (no divergence), 2 data failed, 3 replay could not be started, 4 diverged, 5 timeout.

const CK_EVERY: int = 200


static func run(host: Node, args: AppLaunchArgs) -> void:
	var tree: SceneTree = host.get_tree()
	var state: Node = tree.root.get_node_or_null("AppState")
	var data: GameData = state.get("data") as GameData if state != null else null
	if data == null:
		_out("APPTEST_END reason=data tick=0")
		tree.quit(2)
		return
	_out("APP_READY mode=replay data_hash=%08X" % data.data_hash())
	var path: String = String(args.autostart).substr(String(args.autostart).find("=") + 1)
	var headless: bool = DisplayServer.get_name() == "headless"
	var gui: bool = args.with_ui and not headless
	var ck: bool = args.extras.has("ck-lines")
	var opts: Dictionary = {"with_view": gui or (headless and args.extras.has("with-view")), "bind": gui, "title": "Replay",
		"allow_mismatch": args.extras.has("allow-mismatch"), "events": gui}
	if gui:
		state.call("go", AppFlow.Mode.LOADING, {"kind": "replay", "title": "Replay"})
	var ctx: AppMatchContext = AppReplay.start(path, opts)
	if ctx == null:
		_out("APPTEST_END reason=replay_failed tick=0 detail=%s" % AppReplay.last_error)
		tree.quit(3)
		return
	var rs: AppReplaySession = ctx.replay
	var t0: int = Time.get_ticks_msec()
	while not rs.is_ready and not rs.is_failed:
		await tree.process_frame
		if AppShutdown.quitting:
			return
		if (Time.get_ticks_msec() - t0) / 1000 > args.timeout_s:
			_out("APPTEST_END reason=timeout tick=0")
			tree.quit(5)
			return
	if rs.is_failed:
		_out("APPTEST_END reason=replay_failed tick=0 detail=%s" % rs.error_text)
		tree.quit(3)
		return
	var end_tick: int = rs.end_tick()
	_out("APPTEST_REPLAY_INFO players=%d end_tick=%d finalized=%s" % [(rs.data.config.get("players", []) as Array).size(), end_tick, str(rs.data.finalized)])
	if args.extras.has("seek-demo"):
		await _seek_demo(tree, rs)
	var seek_to: int = int(args.extras.get("seek-to", 0))
	if seek_to > 0:
		rs.set_speed(NetReplayPlayer.MAX)
		rs.seek(seek_to)
		rs.set_paused(true)  # `--seek-to=N`: land on tick N and hold (screenshots)
	var paced: bool = gui and args.speed_pct > 0
	if args.speed_pct > 0 and NetProtocol.SPEED_PCT.has(args.speed_pct):
		rs.set_speed(float(args.speed_pct) / 100.0)
	elif not paced:
		rs.set_speed(NetReplayPlayer.MAX)
	var next_ck: int = ((rs.tick() / CK_EVERY) + 1) * CK_EVERY
	while not rs.is_finished():
		if (Time.get_ticks_msec() - t0) / 1000 > args.timeout_s:
			_out("APPTEST_END reason=timeout tick=%d" % rs.tick())
			tree.quit(5)
			return
		if not gui:
			# headless: step to exactly every 200th tick so the lines line up with the recording's
			var target: int = mini(next_ck, end_tick)
			rs.seek(target)
			while rs.is_seeking() and not rs.is_finished():
				await tree.process_frame
				if AppShutdown.quitting:
					return
			if ck and rs.tick() == next_ck:
				_ck_line(rs)
			next_ck += CK_EVERY
			if rs.tick() >= end_tick:
				break
		else:
			await tree.process_frame
			if AppShutdown.quitting:
				return
			_gui_flags(tree, args, rs)
			if ck and rs.tick() >= next_ck:
				_ck_line(rs)
				next_ck = ((rs.tick() / CK_EVERY) + 1) * CK_EVERY
	var w: SimWorld = rs.world()
	var p: NetReplayPlayer = rs.player
	var diverged: int = p.diverged_tick()
	_out("APPTEST_SUMMARY result=replay winner_team=%d duration_ticks=%d players=%d samples=0" % [int(ctx.last_end.get("winner_team", -1)), rs.tick(), w.players.size()])
	_players(ctx)
	_out("APPTEST_REPLAY ok=%d ticks=%d compared=%d verified_through=%d diverged=%d chain=%08X checksum=%08X recorded_checksum=%08X" % [
		1 if diverged < 0 else 0, rs.tick(), p.compared_count(), p.verified_through_tick(), diverged, p.input_chain() & 0xFFFFFFFF,
		w.checksum() & 0xFFFFFFFF, int(rs.data.end.get("final_checksum", 0)) & 0xFFFFFFFF])
	if w.mission != null:  # a recorded mission: its objectives and result as the replay left them (same line the live mission run prints)
		_out("APPTEST_MISSION_END id=%s difficulty=-1 result=%s tick=%d objectives=%s" % [w.mission.def.id, AppTestBoot.result_word(w.mission.result), w.tick,
			AppTestBoot.objectives_text(w)])
	_out("APPTEST_END reason=replay tick=%d" % rs.tick())
	if args.quit_on_end or headless or not gui:
		AppShutdown.begin_quit(tree)
		await AppAudio.release_for_quit(tree)
		AppShutdown.prepare_quit(tree)
		ctx.dispose()
		AppShutdown.release_statics()
		tree.quit(0 if diverged < 0 else 4)


## Forward, backward and end-of-file seeks with a sanity check that the world lands on the requested ticks.
static func _seek_demo(tree: SceneTree, rs: AppReplaySession) -> void:
	var end_tick: int = rs.end_tick()
	var targets: Array[int] = [end_tick / 2, end_tick / 4, (end_tick * 3) / 4, 0, end_tick]
	for t: int in targets:
		rs.set_speed(NetReplayPlayer.MAX)
		rs.seek(t)
		var guard: int = 0
		while rs.is_seeking() and guard < 1_000_000:
			guard += 1
			await tree.process_frame
		_out("APPTEST_SEEK target=%d now=%d verified_through=%d diverged=%d entities=%d" % [t, rs.tick(), rs.verified_through(), rs.diverged_tick(),
			rs.world().by_id.size() if rs.world() != null else -1])
	rs.seek(0)
	while rs.is_seeking():
		await tree.process_frame


## Screenshot flags once the game screen exists: `--perspective=N` (-1 = all), `--scoreboard`, `--follow`, `--menu`, `--select=<pid>`, `--cam-zoom=Z`.
static func _gui_flags(tree: SceneTree, args: AppLaunchArgs, rs: AppReplaySession) -> void:
	if _flags_done or not rs.is_ready:
		return
	var scn: Node = tree.root.get_node_or_null("AppScenes")
	var gs: UiScreenGame = scn.get("screen") as UiScreenGame if scn != null else null
	if gs == null or gs.observer_ctl == null or rs.tick() < int(args.extras.get("seek-to", 0)):
		return
	_flags_done = true
	var oc: UiObserverController = gs.observer_ctl
	if args.extras.has("perspective"):
		oc.set_perspective(int(args.extras["perspective"]))
	if args.extras.has("scoreboard"):
		oc.toggle_scoreboard()
	if args.extras.has("follow"):
		oc.set_follow(true)
	if args.extras.has("cam-zoom") and gs._view != null:
		var cs: Dictionary = gs._view.camera_state()
		cs["zoom"] = float(str(args.extras["cam-zoom"]))
		gs._view.set_camera_state(cs, true)
	if args.extras.has("menu"):
		gs.open_menu()
	if args.extras.has("select"):
		var ids: PackedInt32Array = PackedInt32Array()
		var w: SimWorld = rs.world()
		for e: SimEntity in w.entities:
			if e.kind == SimEntity.Kind.UNIT and e.owner == int(args.extras["select"]) and ids.size() < 6:
				ids.append(e.id)
		gs.selection.replace(ids, gs._sim)


static var _flags_done: bool = false


static func _ck_line(rs: AppReplaySession) -> void:
	var w: SimWorld = rs.world()
	_out("APPTEST_CK tick=%d chain=%08X checksum=%08X" % [rs.tick(), rs.player.input_chain() & 0xFFFFFFFF, w.checksum() & 0xFFFFFFFF])


## The `APPTEST_PLAYER` lines of the match run for the world as it stands.
static func _players(ctx: AppMatchContext) -> void:
	var sum: Dictionary = ctx.summary(ctx.last_end)
	for r: Variant in sum["players"] as Array:
		var pr: Dictionary = r as Dictionary
		var st: Dictionary = pr["stats"] as Dictionary
		_out("APPTEST_PLAYER pid=%d name=%s ai=%s level=%d team=%d built=%d lost=%d killed=%d structs=%d/%d earned=%d spent=%d score=%d apm=%d elim=%s" % [
			int(pr["pid"]), str(pr["name"]).replace(" ", "_"), str(pr["is_ai"]), int(pr["ai_level"]), int(pr["team"]),
			int(st["units_built"]), int(st["units_lost"]), int(st["units_killed"]), int(st["structures_built"]), int(st["structures_lost"]),
			int(st["harvested"]), int(st["spent"]), int(pr["score"]), int(pr["apm"]), str(pr["eliminated"])])


static func _out(line: String) -> void:
	# lint-allow: L006 greppable test-boot protocol lines (ui.md 5.2.3), parsed by tools and CI
	print(line)
