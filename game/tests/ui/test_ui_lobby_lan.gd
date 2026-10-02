extends RefCounted
## APP2: the lobby in the LAN roles against REAL sessions (NetSessionKit: host + clients over the loopback hub on a manual clock):
## `UiLobbyLan` (edit -> lobby -> snapshot -> mirror), the lobby screen in the HOST and CLIENT roles (read-only rules for a client,
## ready toggle, kick, start errors, countdown, chat as plain text) and the LAN browser screen on injected discovery entries.

const H := preload("res://tests/ui/ui_harness.gd")

var _kit: NetSessionKit = null


func _gd() -> GameData:
	var app: Node = H.tree().root.get_node_or_null("AppState")
	var d: GameData = app.get("data") as GameData if app != null else null
	if d == null:
		d = GameData.load_default()
		if app != null:
			app.set("data", d)
	return d


## Host "X42553" + clients "Mara" (and "Jules" when asked) in the lobby. The AI factory is a stub so AI slots can start.
func _rig(clients: int = 1) -> NetSession:
	_kit = NetSessionKit.new()
	_kit.ai_factory = func(_pid: int, _level: int, _style: int, _seed: int) -> Callable: return func(_w: RefCounted, _out: Array) -> void: pass
	var host: NetSession = _kit.host("X42553", {"discovery_enabled": false, "countdown_s": 3})
	for name_text: String in ["Mara", "Jules"].slice(0, clients):
		_kit.join(name_text)
	_kit.all_in(NetSession.Phase.LOBBY, 100)
	_kit.step(8, 60_000)
	return host


func _ui_for(s: NetSession) -> Array:
	var ui: UiLobbyState = UiLobbyState.create(_gd())
	var lan: UiLobbyLan = UiLobbyLan.new()
	lan.setup(s, ui)
	return [lan, ui]


func _done() -> void:
	if _kit != null:
		_kit.shutdown_all()
		_kit = null


func test_host_edits_reach_the_lobby_and_the_client(t: TestCtx) -> void:
	var host: NetSession = _rig()
	var client: NetSession = _kit.sessions[1]
	var pair: Array = _ui_for(host)
	var lan: UiLobbyLan = pair[0] as UiLobbyLan
	var ui: UiLobbyState = pair[1] as UiLobbyState
	t.eq(lan.role, UiLobbyNet.Role.HOST)
	t.eq(ui.slots[0].kind, UiLobbyState.Kind.HUMAN)
	t.eq(ui.slots[1].name, "Mara", "the joined client is seated in slot 1")
	# slot 2 -> Hard AI, team B, through the mirror exactly like the widgets do
	ui.slots[2].kind = UiLobbyState.Kind.AI
	ui.slots[2].ai_level = 2
	var r: Dictionary = lan.push()
	t.eq(int(r["result"]), NetLobby.Result.OK)
	t.eq(host.lobby.state.slots[2].kind, NetProtocol.SlotKind.AI)
	t.eq(host.lobby.state.slots[2].ai_level, 2, "kind and level both applied")
	ui.slots[2].team = 2
	ui.slots[0].team = 1
	lan.push()
	lan.push()
	t.eq(host.lobby.state.slots[2].team, 2)
	t.eq(host.lobby.state.slots[0].team, 1)
	ui.size = 160
	lan.push()
	t.eq(host.lobby.state.map_size, 160, "the map panel edit reaches the lobby")
	ui.speed_pct = 150
	ui.pause_policy = 0
	lan.push()
	t.eq(host.lobby.state.speed_code, 4)
	t.eq(host.lobby.state.pause_policy, 0)
	_kit.step(8, 60_000)
	t.eq(client.lobby.state.slots[2].kind, NetProtocol.SlotKind.AI, "the client sees the host's edit in its snapshot")
	t.eq(client.lobby.state.map_size, 160)
	# a host edit clears the remote ready flags
	t.check(not host.lobby.state.slots[1].ready)
	_done()


func test_client_edits_its_row_and_reverts_the_rest(t: TestCtx) -> void:
	var host: NetSession = _rig()
	var client: NetSession = _kit.sessions[1]
	var pair: Array = _ui_for(client)
	var lan: UiLobbyLan = pair[0] as UiLobbyLan
	var ui: UiLobbyState = pair[1] as UiLobbyState
	t.eq(lan.role, UiLobbyNet.Role.CLIENT)
	t.eq(lan.local_slot(), 1)
	ui.slots[1].team = 3
	ui.slots[1].color = 7
	ui.slots[1].faction = UiLobbyNet.roster_pick(_gd(), "roster.olm.vanilla").x
	ui.slots[1].sub = 0
	ui.slots[0].team = 4         # the host's row: never sent
	ui.start_credits = 1000      # host-only: never sent
	var r: Dictionary = lan.push()
	t.eq(int(r["ops"]), 3, "roster, team and colour")
	_kit.step(8, 60_000)
	var mara: NetPlayerSlot = host.lobby.state.slots[1]
	t.eq(mara.team, 3)
	t.eq(mara.color, 7)
	t.check(mara.roster_id.begins_with("roster.olm."), "the roster arrived")
	t.eq(host.lobby.state.slots[0].team, 0, "the host's row was not touched")
	lan.tick(1.0)   # no snapshot pending any more: the mirror shows the authoritative state again
	lan.pull()
	t.eq(ui.slots[0].team, 0, "an edit the host would not accept snaps back")
	t.eq(ui.start_credits, host.lobby.state.rules["start_credits"])
	# ready toggle
	t.check(not lan.is_ready())
	lan.toggle_ready()
	_kit.step(8, 60_000)
	t.check(host.lobby.state.slots[1].ready, "READY reaches the host")
	t.check(lan.is_ready(), "and comes back in the snapshot")
	# take an open slot, then spectate and play again
	t.eq(lan.take(3), NetLobby.Result.OK)
	_kit.step(8, 60_000)
	t.eq(host.lobby.state.slots[3].peer_id, client.local_peer_id, "the client moved to slot 3")
	t.eq(lan.spectate(), NetLobby.Result.OK)
	_kit.step(8, 60_000)
	t.check(lan.is_spectator(), "spectators stay in the lobby")
	t.eq(host.lobby.state.spectators.size(), 1)
	lan.play()
	_kit.step(8, 60_000)
	t.check(not lan.is_spectator())
	_done()


func test_start_conditions_kick_and_countdown(t: TestCtx) -> void:
	var host: NetSession = _rig()
	var client: NetSession = _kit.sessions[1]
	var pair: Array = _ui_for(host)
	var lan: UiLobbyLan = pair[0] as UiLobbyLan
	var ui: UiLobbyState = pair[1] as UiLobbyState
	ui.slots[0].team = 1
	ui.slots[1].team = 2
	lan.push()
	lan.push()
	_kit.step(6, 60_000)
	t.eq(lan.start(), NetLobby.StartError.HUMAN_NOT_READY, "a human that is not ready blocks the start")
	t.eq(UiLobbyNet.error_rows(NetLobby.StartError.HUMAN_NOT_READY, ui), PackedInt32Array([1]), "and the row is named")
	client.lobby.set_ready(true)
	_kit.step(8, 60_000)
	t.eq(lan.start_error(), NetLobby.StartError.OK)
	t.eq(lan.start(), NetLobby.StartError.OK, "everything ready: the countdown begins")
	t.check(lan.counting_down(), "the lobby is locked during the countdown")
	var seen: Array = []
	host.countdown_changed.connect(func(n: int) -> void: seen.append(n))
	lan.cancel_start()
	_kit.step(4, 60_000)
	t.check(not lan.counting_down(), "the host cancels")
	# kick with the ban flag
	t.eq(lan.kick(1, true), NetLobby.Result.OK)
	_kit.step(10, 60_000)
	t.eq(host.lobby.state.slots[1].kind, NetProtocol.SlotKind.OPEN, "the kicked player's slot opens")
	t.eq(lan.kick(0, false), NetLobby.Result.INVALID, "the host cannot kick itself")
	_done()


func test_removal_is_reported_before_it_is_sent(t: TestCtx) -> void:
	var host: NetSession = _rig()
	var pair: Array = _ui_for(host)
	var lan: UiLobbyLan = pair[0] as UiLobbyLan
	var ui: UiLobbyState = pair[1] as UiLobbyState
	t.eq(lan.removals(), PackedInt32Array(), "no pending change")
	ui.slots[1].kind = UiLobbyState.Kind.CLOSED
	t.eq(lan.removals(), PackedInt32Array([1]), "closing a seated human would remove it: the screen asks first")
	lan.pull()
	t.eq(ui.slots[1].kind, UiLobbyState.Kind.HUMAN, "declining restores the row")
	_done()


func test_host_screen_rows_buttons_and_read_only_flags(t: TestCtx) -> void:
	var host: NetSession = _rig()
	host.lobby.host_set_slot_kind(2, NetProtocol.SlotKind.AI)
	_kit.step(4, 60_000)
	var h: H.Rig = await H.make()
	var screen: UiScreenLobby = UiScreenLobby.new()
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter({"lan": true, "session": host})
	await H.frames(3)
	t.eq(screen.role, UiLobbyNet.Role.HOST)
	t.eq(screen._rows.size(), 8)
	var mara_row: UiLobbySlotRow = screen._rows[1]
	t.check(mara_row.editable(), "the host edits a remote human's row")
	t.check(not mara_row._type.disabled, "and may remove it with the type picker")
	t.check(mara_row._kick.visible, "a kick button on a remote human")
	t.check(not screen._rows[0]._type.disabled == false or screen._rows[0]._type.disabled, "the host's own type picker is fixed")
	t.check(screen._rows[0]._type.disabled)
	t.check(not screen._rows[0]._kick.visible, "no kick button on the host")
	t.eq(mara_row._status.text, "NOT READY")
	t.eq(screen._start.text, "START")
	t.check(screen._rows[2]._hcp.visible and not screen._rows[2]._hcp.disabled, "handicap chip on the AI row")
	# the START button reports the first failing condition
	screen._on_start()
	t.eq(screen._error.text, "Waiting for Mara to be ready.")
	# a widget edit: the AI row's type picker -> Hard
	var type: OptionButton = screen._rows[2]._type
	type.select(2)
	type.item_selected.emit(2)
	t.eq(host.lobby.state.slots[2].ai_level, 2, "the picker edit went through NetLobby")
	# the drawer / column: chat is plain text
	t.not_null(screen.chat)
	screen.chat.add_line(0, 1, "Mara", "[b]hello[/b] [color=red]x[/color]", Color.WHITE)
	t.check(screen.chat.history_text().contains("[b]hello[/b]"), "BBCode in chat is shown literally")
	t.eq(UiLobbyChat.format_line(0, 255, "", "x"), "[SYSTEM] x")
	t.eq(UiLobbyChat.format_line(1, 3, "Mara", "hi"), "Mara (team): hi")
	screen.exit()
	screen.queue_free()
	H.done(h)
	_done()


func test_client_screen_is_read_only_except_its_row(t: TestCtx) -> void:
	var host: NetSession = _rig()
	var client: NetSession = _kit.sessions[1]
	host.lobby.host_set_slot_kind(2, NetProtocol.SlotKind.AI)
	_kit.step(8, 60_000)
	var h: H.Rig = await H.make()
	var screen: UiScreenLobby = UiScreenLobby.new()
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter({"lan": true, "session": client})
	await H.frames(3)
	t.eq(screen.role, UiLobbyNet.Role.CLIENT)
	t.check(screen._rows[1].editable(), "own row")
	t.check(not screen._rows[0].editable(), "not the host's row")
	t.check(not screen._rows[2].editable(), "not the AI's row")
	t.check(screen._rows[0]._faction.disabled and screen._rows[2]._team.disabled)
	t.check(not screen._rows[1]._faction.disabled and not screen._rows[1]._team.disabled)
	t.check(screen._rows[1]._type.disabled, "a client never changes slot types")
	t.check(not screen._rows[1]._kick.visible and not screen._rows[0]._kick.visible, "no kick buttons for a client")
	t.check(screen._rows[3]._take.visible, "a client can take an open slot")
	t.check(screen._rows[2]._hcp.disabled, "the handicap is read-only")
	t.check(screen._rules._credits.disabled and screen._rules._pause.disabled, "the rules are read-only")
	t.check(screen._map._family.disabled and screen._map._reroll.disabled, "the map is read-only")
	t.eq(screen._start.text, "READY UP")
	t.check(screen._spec_button != null and screen._spec_button.visible, "spectate offered")
	screen._on_start()
	_kit.step(8, 60_000)
	t.check(host.lobby.state.slots[1].ready, "the READY button readies the seat")
	t.eq(screen._start.text, "CANCEL READY")
	screen._rows[3]._take.pressed.emit()
	_kit.step(8, 60_000)
	t.eq(host.lobby.state.slots[3].peer_id, client.local_peer_id, "TAKE moved the client")
	screen.exit()
	screen.queue_free()
	H.done(h)
	_done()


func test_lan_lobby_without_a_session_goes_back(t: TestCtx) -> void:
	var h: H.Rig = await H.make()
	var screen: UiScreenLobby = UiScreenLobby.new()
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	var backs: Array = []
	screen.back_requested.connect(func() -> void: backs.append(1))
	screen.enter({"lan": true})
	await H.frames(2)
	t.eq(backs.size(), 1, "a LAN lobby without a session asks to go back instead of crashing")
	screen.queue_free()
	H.done(h)


func test_lan_browser_screen_lists_and_gates_join(t: TestCtx) -> void:
	var data: GameData = _gd()
	var h: H.Rig = await H.make()
	var screen: UiScreenLanBrowser = UiScreenLanBrowser.new()
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter({"no_help": true})  # the explainer would open a modal dialog on the shared AppScenes and swallow later tests' Escape
	await H.frames(2)
	if screen.browser != null:
		screen.browser.close()
	var d: NetDiscovery = NetDiscovery.new()
	d.setup(NetClock.manual(10_000_000), "0.1.0", NetProtocol.PROTO_VERSION, SimConfig.SIM_VERSION, data.data_hash())
	screen.browser = d
	var rows: Array = [["Alpha", "192.168.1.5", 0x11, 0, data.data_hash()], ["Bravo", "192.168.1.6", 0x12, NetDiscoveryEntry.F_FULL, data.data_hash()],
		["Charlie", "192.168.1.7", 0x13, 0, 0xDEADBEEF]]
	for r: Array in rows:
		d.handle_datagram(str(r[1]), NetDiscovery.encode_datagram({"host_name": r[0], "game_port": 27615, "session_id": r[2], "flags": r[3], "humans": 1,
			"slots_total": 4, "slots_free": 3, "map_size": 128, "map_family": 0, "ai_count": 0, "data_hash": r[4], "sim_version": SimConfig.SIM_VERSION,
			"proto_version": NetProtocol.PROTO_VERSION, "game_version": "0.1.0"}))
	screen._rebuild(true)
	t.eq(screen._row_nodes.size(), 3, "three games listed")
	t.check(screen._join_button.disabled, "nothing selected: JOIN is disabled")
	screen._select(str(screen._rows[0]["key"]))
	t.check(not screen._join_button.disabled, "a compatible game can be joined")
	t.check(screen._detail["banner"].text.contains("Same build"), "the compatibility banner")
	screen._select(str(screen._rows[1]["key"]))
	t.check(screen._join_button.disabled and screen._join_button.tooltip_text == "The game is full.", "a full game: disabled with the reason")
	screen._select(str(screen._rows[2]["key"]))
	t.check(screen._join_button.disabled, "an incompatible game: disabled")
	t.check(screen._status.text.contains("game data"), "with the failing layer named")
	screen._hide_bad.button_pressed = true
	screen._rebuild(true)
	t.eq(screen._row_nodes.size(), 2, "hide incompatible")
	screen._on_sort(UiLanModel.Col.GAME)
	t.eq(str(((screen._rows[0]["cells"] as Array[Dictionary])[0] as Dictionary)["text"]), "Bravo", "clicking the sorted column head reverses the order")
	# direct connect validation shows the reason
	screen._addr.text = "not a host!"
	screen._on_connect()
	t.check(screen._direct_error.text != "", "an invalid address is explained")
	screen.exit()
	screen.queue_free()
	H.done(h)


func test_firewall_explainer_comes_before_the_first_socket(t: TestCtx) -> void:
	_gd()
	var st: Node = H.tree().root.get_node_or_null("AppSettings")
	var scenes: Node = H.tree().root.get_node_or_null("AppScenes")
	if st == null or scenes == null:
		t.skip("needs the AppSettings and AppScenes autoloads")
		return
	var before: bool = bool(st.call("get_bool", &"net/help_shown"))
	st.call("set_value", &"net/help_shown", false)
	var h: H.Rig = await H.make()
	var screen: UiScreenLanBrowser = UiScreenLanBrowser.new()
	h.root.add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter({})
	await H.frames(2)
	t.is_null(screen.browser, "no socket is opened before the explainer is answered")
	var dlg: UiDialog = (scenes.get("dialogs") as UiDialogStack).top()
	if t.check(dlg is UiDlgFirewallHelp, "the explainer is on display"):
		dlg.close(UiDlgFirewallHelp.RESULT_OK)
		await H.frames(2)
		t.not_null(screen.browser, "answering it starts the browse")
		t.check(bool(st.call("get_bool", &"net/help_shown")), "and it is remembered (net/help_shown)")
	screen.exit()
	screen.queue_free()
	H.done(h)
	st.call("set_value", &"net/help_shown", before)
