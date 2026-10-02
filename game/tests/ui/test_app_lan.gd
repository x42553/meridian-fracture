extends RefCounted
## APP2: `AppLan` over REAL ENet on 127.0.0.1 in one process. The context the class creates is polled by the `AppNet` autoload (as
## in the game); the other side is a raw `NetSession` polled by the test. Covers hosting, a client joining the lobby, the join
## refusals the LAN browser reports (wrong password, different simulation version) and leaving.

const H := preload("res://tests/ui/ui_harness.gd")


func _data() -> GameData:
	var app: Node = H.tree().root.get_node_or_null("AppState")
	var d: GameData = app.get("data") as GameData if app != null else null
	if d == null:
		d = GameData.load_default()
		if app != null:
			app.set("data", d)
	return d


func _raw_options(name_text: String, port: int = 0) -> NetSessionOptions:
	var o: NetSessionOptions = AppNetSetup.make_options(_data(), {"player_name": name_text})
	o.discovery_enabled = false
	if port > 0:
		o.port = port
	return o


func _port() -> int:
	return 28100 + int(Time.get_ticks_usec() % 700) * 2


func _wait(pred: Callable, frames: int, poll: Callable = Callable()) -> bool:
	for _i: int in frames:
		if pred.call():
			return true
		if poll.is_valid():
			poll.call()
		await H.frames(1)
	return pred.call()


func test_host_lan_opens_a_lobby_a_client_can_join(t: TestCtx) -> void:
	_data()
	var port: int = _port()
	var ctx: AppMatchContext = AppLan.host_lan({"port": port, "advertise": false, "with_view": false, "lobby_name": "Test game", "bind": false,
		"player_name": "Hosty", "spectators": true})
	if not t.not_null(ctx, "the host context (%s)" % NetSession.last_create_error):
		return
	t.eq(ctx.session.role, NetSession.Role.HOST)
	t.eq(ctx.session.phase, NetSession.Phase.LOBBY)
	t.eq(AppLan.current_session(), ctx.session, "the context is registered as AppState.match_ctx")
	t.eq(ctx.session.lobby.state.host_name, "Test game")
	t.eq(ctx.session.lobby.state.slots[0].name, "Hosty")
	var net_node: Node = H.tree().root.get_node_or_null("AppNet")
	t.eq(net_node.get("ctx"), ctx, "AppNet polls the context")
	var guest: NetSession = NetSession.join(_raw_options("Guest"), "127.0.0.1", ctx.session.transport.local_port())
	if t.not_null(guest, "the client session (%s)" % NetSession.last_create_error):
		var ok: bool = await _wait(func() -> bool: return guest.phase == NetSession.Phase.LOBBY, 240, func() -> void: guest.poll())
		t.check(ok, "the client reached the lobby (phase %d)" % guest.phase)
		if ok:
			await _wait(func() -> bool: return ctx.session.lobby.state.human_count() == 2, 60, func() -> void: guest.poll())
			t.eq(ctx.session.lobby.state.human_count(), 2, "the host's lobby seats the guest")
			t.eq(ctx.session.lobby.state.slots[1].name, "Guest")
			guest.lobby.set_roster("roster.nec.vanilla")
			await _wait(func() -> bool: return ctx.session.lobby.state.slots[1].roster_id == "roster.nec.vanilla", 60, func() -> void: guest.poll())
			t.eq(ctx.session.lobby.state.slots[1].roster_id, "roster.nec.vanilla", "a client edit arrives at the host")
			# the mirror the lobby screen would show
			var ui: UiLobbyState = UiLobbyState.create(_data())
			UiLobbyNet.pull(ctx.session.lobby.state, ui)
			t.eq(ui.slots[1].name, "Guest")
			t.eq(ui.slots[1].faction, UiLobbyNet.roster_pick(_data(), "roster.nec.vanilla").x)
		guest.shutdown()
	t.check(AppLan.is_lan_match(), "a LAN context is running")
	t.check(AppLan.return_to_lobby(), "a session that is in the lobby phase can 'return' to it (after a match the host sends everybody back first)")
	t.is_null(H.tree().root.get_node("AppState").get("match_ctx"), "the context is detached from AppState so leaving the end screen does not dispose it")
	t.eq(AppLan.current_session(), ctx.session, "but AppNet still polls it and the lobby screen finds it")
	AppLan.leave()
	t.is_null(AppLan.current_session(), "leave clears the context")
	t.check(ctx.disposed)
	t.check(not AppLan.is_lan_match())


func test_join_lan_reports_a_wrong_password(t: TestCtx) -> void:
	_data()
	var port: int = _port()
	var ho: NetSessionOptions = _raw_options("Hosty", port)
	ho.password = "sesame"
	var raw: NetSession = NetSession.host(ho, "Secret")
	if not t.not_null(raw, "raw host"):
		return
	var real_port: int = raw.transport.local_port()
	var ctx: AppMatchContext = AppLan.join_lan("127.0.0.1", real_port, "wrong", {"with_view": false, "bind": false, "player_name": "Guest"})
	if t.not_null(ctx, "the join context"):
		var got: Array = []
		ctx.session.join_rejected.connect(func(reason: int, info: Dictionary) -> void: got.append([reason, info]))
		await _wait(func() -> bool: return not got.is_empty(), 300, func() -> void: raw.poll())
		if t.eq(got.size(), 1, "join_rejected fired"):
			t.eq(got[0][0], NetProtocol.RejectReason.BAD_PASSWORD)
			t.eq((got[0][1] as Dictionary)["text"], "Wrong password.")
			var d: Dictionary = UiDlgJoinRejected.describe(int(got[0][0]), got[0][1] as Dictionary, "127.0.0.1")
			t.eq(d["title"], "Password required", "the browser re-opens a password prompt")
		AppLan.leave()
	raw.shutdown()


func test_join_lan_reports_a_version_mismatch(t: TestCtx) -> void:
	_data()
	var port: int = _port()
	var ho: NetSessionOptions = _raw_options("Hosty", port)
	ho.sim_version += 1000
	var raw: NetSession = NetSession.host(ho, "Other build")
	if not t.not_null(raw, "raw host"):
		return
	var ctx: AppMatchContext = AppLan.join_lan("127.0.0.1", raw.transport.local_port(), "", {"with_view": false, "bind": false, "player_name": "Guest"})
	if t.not_null(ctx, "the join context"):
		var got: Array = []
		ctx.session.join_rejected.connect(func(reason: int, info: Dictionary) -> void: got.append([reason, info]))
		await _wait(func() -> bool: return not got.is_empty(), 300, func() -> void: raw.poll())
		if t.eq(got.size(), 1, "join_rejected fired"):
			t.eq(got[0][0], NetProtocol.RejectReason.SIM_MISMATCH)
			var d: Dictionary = UiDlgJoinRejected.describe(int(got[0][0]), got[0][1] as Dictionary)
			t.eq(d["title"], "Different game version")
			t.check(str(d["body"]).contains("simulation"), "names the failing layer: " + str(d["body"]))
			t.eq((d["rows"] as Array).size(), 2, "with a host / you table")
		AppLan.leave()
	raw.shutdown()


func test_join_lan_refuses_an_unusable_address(t: TestCtx) -> void:
	_data()
	var ctx: AppMatchContext = AppLan.join_lan("not a host!", 27615, "", {"with_view": false, "bind": false})
	t.is_null(ctx, "a bad address creates no session")
	t.check(NetSession.last_create_error.begins_with("bad address"), NetSession.last_create_error)
	t.is_null(AppLan.current_session())
