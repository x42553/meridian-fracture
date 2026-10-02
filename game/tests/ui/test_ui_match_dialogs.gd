extends RefCounted
## APP-1 in-match UI (ui.md 5.16): game menu, pause banner, stall overlay and prompt, desync dialog, net overlay, the overlay
## host wired to a real `NetSession`, and the end screen model / tabs.

const H := preload("res://tests/ui/ui_harness.gd")


func _texts(n: Node, out: PackedStringArray) -> void:
	for c: Node in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
		_texts(c, out)


func _button(n: Node, text: String) -> Button:
	for c: Node in n.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
		var deeper: Button = _button(c, text)
		if deeper != null:
			return deeper
	return null


# ---------------------------------------------------------------- dialogs and overlays

func test_game_menu_confirms_surrender_and_leave(t: TestCtx) -> void:
	var m: UiDlgGameMenu = UiDlgGameMenu.new(true, true)
	var res: Array[int] = []
	m.closed.connect(func(r: int) -> void: res.append(r))
	var txt: PackedStringArray = PackedStringArray()
	_texts(m, txt)
	t.check(txt.has("Resume") and txt.has("Surrender") and txt.has("Leave match"), "the menu items")
	t.check(txt.has("The game is paused while this menu is open."), "LOCAL footer")
	t.check(not m.is_confirming())
	_button(m, "Surrender").pressed.emit()
	t.check(m.is_confirming(), "Surrender asks first")
	t.eq(res.size(), 0)
	_button(m, "Back").pressed.emit()
	t.check(not m.is_confirming(), "Back returns to the items")
	_button(m, "Surrender").pressed.emit()
	for b: Button in m._confirm.find_children("*", "Button", true, false):
		if b.text == "Surrender":
			b.pressed.emit()
	t.eq(res, [UiDlgGameMenu.RESULT_SURRENDER], "the confirmed surrender closes with its code")
	var m2: UiDlgGameMenu = UiDlgGameMenu.new(false, false)
	var txt2: PackedStringArray = PackedStringArray()
	_texts(m2, txt2)
	t.check(txt2.has("The game continues while this menu is open."), "LAN footer")
	t.check(_button(m2, "Surrender").disabled, "an observer cannot surrender")
	_button(m2, "Leave match").pressed.emit()
	var closed2: Array[int] = []
	m2.closed.connect(func(r: int) -> void: closed2.append(r))
	for b2: Button in m2._confirm.find_children("*", "Button", true, false):
		if b2.text == "Leave match":
			b2.pressed.emit()
	t.eq(closed2, [UiDlgGameMenu.RESULT_LEAVE])
	m.free()
	m2.free()


func test_pause_banner_texts(t: TestCtx) -> void:
	var b: UiPauseBanner = UiPauseBanner.new()
	b.show_paused("", -1, "Pause", true, true)
	t.check(b.visible and b.sub_text().contains("Pause"), "LOCAL: press the key to resume")
	b.show_paused("Alex", 2, "Pause", false, false)
	t.eq(b.sub_text(), "Alex paused the game (2 pauses left)")
	b.hide_banner()
	t.check(not b.visible)
	b.free()


func test_stall_overlay_lists_the_waiting_players(t: TestCtx) -> void:
	var o: UiStallOverlay = UiStallOverlay.new()
	t.check(not o.visible)
	o.set_waiting([{"pid": 1, "name": "Bob", "reason": NetProtocol.StallReason.DISCONNECTED, "wait_ms": 2600},
		{"pid": 2, "name": "Cy", "reason": NetProtocol.StallReason.SLOW_CPU, "wait_ms": 900}])
	t.check(o.visible and o.is_waiting())
	t.eq(o.title_text(), "Waiting for Bob, Cy... 2 s")
	var txt: PackedStringArray = PackedStringArray()
	_texts(o, txt)
	t.check(txt.has("Bob: connection lost") and txt.has("Cy's computer is running slowly"), "per-reason sublines")
	o.set_waiting([{"pid": -1, "name": "host", "reason": NetProtocol.StallReason.NETWORK, "wait_ms": 0}])
	t.eq(o.title_text(), "Waiting for the host... 0 s")
	o.set_waiting([])
	t.check(not o.visible, "an empty list resumes")
	o.free()


func test_stall_prompt_is_non_modal_and_reports_the_choice(t: TestCtx) -> void:
	var p: UiDlgStallPrompt = UiDlgStallPrompt.new()
	t.eq(p.mouse_filter, Control.MOUSE_FILTER_STOP)
	p.set_pids(PackedInt32Array([2]), {2: "Dana"})
	t.check(p.visible and p.pid_count() == 1)
	var got: Array = []
	p.chosen.connect(func(pid: int, action: int) -> void: got.append([pid, action]))
	_button(p, "Replace with AI").pressed.emit()
	_button(p, "Drop (resigns)").pressed.emit()
	_button(p, "Wait").pressed.emit()
	t.eq(got, [[2, NetProtocol.StallAction.STALL_DROP_AI], [2, NetProtocol.StallAction.STALL_DROP_RESIGN], [2, NetProtocol.StallAction.STALL_WAIT]])
	t.check(not p.visible, "Wait dismisses the panel: no forced choice")
	p.free()


func test_desync_dialog_content(t: TestCtx) -> void:
	var d: UiDlgDesync = UiDlgDesync.new({"tick": 3620, "kind": "SIM", "message": "state differs in: units"})
	var txt: PackedStringArray = PackedStringArray()
	_texts(d, txt)
	var joined: String = "\n".join(txt)
	t.check(joined.contains("3:01") and joined.contains("tick 3620"), "the time and tick of the divergence: " + joined)
	t.check(joined.contains("SIM") and joined.contains("units"))
	t.check(_button(d, "Show folder") != null and _button(d, "Copy report") != null and _button(d, "Leave") != null)
	var res: Array[int] = []
	d.closed.connect(func(r: int) -> void: res.append(r))
	_button(d, "Show folder").pressed.emit()
	t.eq(res.size(), 0, "Show folder keeps the dialog open")
	_button(d, "Leave").pressed.emit()
	t.eq(res, [UiDlgDesync.RESULT_LEAVE])
	d.free()


func test_net_overlay_text(t: TestCtx) -> void:
	var txt: String = UiNetOverlay.format({"role": NetSession.Role.HOST, "tick": 1200, "turn": 600, "delay_turns": 2, "speed_pct": 100,
		"rtt_ms": {0: 0, 1: 34}, "jitter_ms": {1: 5}, "kbps_in": 12.5, "kbps_out": 40.0, "load_pct": 8, "stall_count": 1, "stall_ms": 420,
		"last_checksum_tick": 1180}, 60, 0)
	t.check(txt.contains("host  tick 1200  turn 600  D=2  speed 100%"), txt)
	t.check(txt.contains("p0*") and txt.contains("p1  rtt 34 ms  jitter 5 ms"), "per player rtt, the local one starred")
	t.check(txt.contains("stalls 1 (420 ms)") and txt.contains("fps 60"))


func test_overlay_host_follows_the_session_signals(t: TestCtx) -> void:
	var o: NetSessionOptions = AppNetSetup.make_options(GameData.load_default(), {})
	var cfg: Dictionary = AppMatch.simple_config(PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"]), 5, 96)
	var s: NetSession = NetSession.local_from_config(o, AppNetSetup.complete_config(cfg, o))
	if not t.not_null(s, NetSession.last_create_error):
		return
	var ov: UiMatchOverlays = UiMatchOverlays.new()
	ov.setup(s, {0: "Commander", 1: "Bot 1"}, null)
	s.pause_changed.emit(true, 0)
	t.check(ov.banner.visible, "pause_changed shows the banner")
	s.pause_changed.emit(false, 0)
	t.check(not ov.banner.visible)
	s.stall_changed.emit([{"pid": 1, "name": "Bot 1", "reason": 0, "wait_ms": 500}])
	t.check(ov.stall.visible)
	s.stall_prompt.emit(PackedInt32Array([1]))
	t.check(ov.prompt.visible)
	s.stall_changed.emit([])
	t.check(not ov.stall.visible and not ov.prompt.visible, "resuming clears both")
	s.desync_detected.emit({"tick": 400, "kind": "SIM"})
	t.not_null(ov.desync_dialog, "desync_detected builds the dialog")
	if ov.desync_dialog != null:
		ov.desync_dialog.free()
	ov.toggle_net_overlay()
	t.check(ov.net_overlay.visible)
	var left: Array = []
	ov.leave_requested.connect(func() -> void: left.append(true))
	s.phase_changed.emit(NetSession.Phase.DISCONNECTED, NetSession.Phase.PLAYING)
	t.eq(left.size(), 1, "a lost connection asks to leave (no dialog host in this rig)")
	ov.release()
	t.eq(s.pause_changed.get_connections().size(), 0, "release disconnects the session")
	ov.free()
	s.shutdown()


# ---------------------------------------------------------------- end screen

func _summary() -> Dictionary:
	var rows: Array = []
	for i: int in 3:
		var st: Dictionary = {"units_built": 40 + i, "units_lost": 10 * i, "units_killed": 30 - 10 * i, "structures_built": 12, "structures_lost": i,
			"structures_destroyed": 3 - i, "harvested": 20000 + 5000 * i, "spent": 18000, "damage_dealt": 90000, "damage_taken": 50000,
			"commands": 600, "peak_units": 44, "research_done": 2, "value_destroyed": -1, "value_lost": -1, "powers_used": -1, "sw_launched": -1}
		rows.append({"pid": i, "name": "Player %d" % i, "roster_id": "roster.napc.vanilla", "faction_code": "NAPC", "team": i + 1, "color": i,
			"status": 0, "is_local": i == 0, "is_ai": i > 0, "ai_level": i, "eliminated": i == 2, "elim_reason": 1, "alive_ticks": 9000 - 1000 * i,
			"credits": 1200, "stats": st, "score": 1000 * (3 - i), "apm": 60})
	var series: Dictionary = {}
	for i2: int in 3:
		series[i2] = {"harvested": PackedInt32Array([0, 1000, 3000, 6000, 9000 + i2 * 3000]), "army": PackedInt32Array([0, 4, 9, 14, 20]),
			"kills": PackedInt32Array([0, 0, 2, 5, 9])}
	return {"outcome": UiMatchStats.OUTCOME_VICTORY, "result": "victory", "reason": 0, "winner_team": 1, "duration_ticks": 9000, "players": rows,
		"series": series, "map_name": "Ashen Reach", "map_seed": 0x9F3AC21E, "map_family": 0, "map_size": 96, "final_checksum": 1}


func test_end_screen_tabs_and_navigation(t: TestCtx) -> void:
	var h: H.Rig = await H.make()
	var scr: UiScreenEnd = UiScreenEnd.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"summary": _summary()})
	await H.frames(2)
	var txt: PackedStringArray = PackedStringArray()
	_texts(scr, txt)
	t.check(txt.has("VICTORY"), "banner: " + ",".join(txt))
	t.check(txt.has("Player 0  (you)") and txt.has("Player 1  [Medium AI]"), "names with the local marker and the AI level")
	t.check(txt.has("Winner") and txt.has("Defeated") and txt.has("Survived"), "results: winner, eliminated, alive")
	t.check(txt.has("3,000") and txt.has("2,000"), "scores")
	t.check(txt.has("7:30") and txt.has("5:50"), "time alive: 9000 ticks = 7:30, 7000 ticks = 5:50")
	for tab: StringName in [&"military", &"economy", &"graphs", &"summary"]:
		scr.select_tab(tab)
		await H.frames(1)
		t.eq(scr.current_tab(), tab)
	scr.select_tab(&"economy")
	var eco: PackedStringArray = PackedStringArray()
	_texts(scr, eco)
	t.check(eco.has("HARVESTED") and eco.has("25,000"), "economy table")
	scr.select_tab(&"graphs")
	await H.frames(2)
	t.check(scr._graph != null and scr._graph.max_value() == 15000, "the graph reads the series")
	t.eq(UiEndGraph._nice_max(15000), 20000)
	var nav: Array = []
	scr.navigate.connect(func(target: StringName, p: Dictionary) -> void: nav.append([target, p]))
	_button(scr, "PLAY AGAIN").pressed.emit()
	_button(scr, "MAIN MENU").pressed.emit()
	t.eq(nav[0][0], &"lobby")
	t.eq(nav[1][0], &"main_menu")
	t.check(not scr.on_escape() and not scr.can_leave(), "Escape does not leave the results by accident")
	scr.queue_free()
	H.done(h)


func test_end_banner_words(t: TestCtx) -> void:
	t.eq(UiScreenGame.end_banner(UiMatchStats.OUTCOME_VICTORY, 0)[0], "VICTORY")
	t.eq(UiScreenGame.end_banner(UiMatchStats.OUTCOME_DEFEAT, 0)[0], "DEFEAT")
	t.eq(UiScreenGame.end_banner(UiMatchStats.OUTCOME_DRAW, 0)[0], "DRAW")
	t.eq(UiScreenGame.end_banner(UiMatchStats.OUTCOME_OBSERVED, 0)[0], "MATCH ENDED")
	t.eq(UiScreenGame.end_banner(UiMatchStats.OUTCOME_OBSERVED, NetProtocol.MatchEndReason.DESYNC)[0], "DESYNC")
	t.eq(UiScreenEnd.result_text({"team": 1, "eliminated": false}, 1, true), "Winner")
	t.eq(UiScreenEnd.result_text({"team": 2, "eliminated": true, "elim_reason": SimPlayer.Elim.RESIGN}, 1, true), "Surrendered")
	t.eq(UiScreenEnd.result_text({"team": 2, "eliminated": false}, -1, true), "Survived")
