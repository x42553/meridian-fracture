extends UiLayerRoot
## LAN screens sheet (task APP2). tools/gd shot res://tests/visual/app2_lan.tscn out.png --size 1920x1080 -- --view=<v>
##   --view=browser | browser-empty | lobby-host | lobby-client | lobby-countdown | rejected-data | rejected-proto | rejected-pw | abort-map |
##          firewall-mac | firewall-win | firewall-linux | host-dialog | connecting
##   --drawer=1 opens the chat drawer (windows narrower than 1880 logical px use it instead of the right column)
## The lobby views run real `NetSession`s (host + clients over the loopback hub of NetSessionKit on a manual clock) behind the real
## `UiScreenLobby`. No class_name on purpose (labs never take real class names).

var _kit: NetSessionKit = null
var _screen: UiScreen = null
var _stack: UiDialogStack = null


func _ready() -> void:
	var view: String = "browser"
	var drawer: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.substr(7)
		elif arg == "--drawer=1":
			drawer = true
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiLayout.apply(win, 1.0)
	UiSkinSet.shared().setup_from_json()
	UiThemeService.rebuild(UiSkinSet.shared().skin_for("napc"))
	var back: ColorRect = ColorRect.new()
	back.color = Color("#0b1016")
	add_child(back)
	UiLayerRoot.fill(back)
	_stack = UiDialogStack.new()
	add_child(_stack)
	_stack.attach(self)
	if view.begins_with("lobby"):
		await _lobby(view, drawer)
	elif view.begins_with("browser"):
		await _browser(view == "browser-empty")
	else:
		_dialog(view)
	set_process(true)


func _process(_delta: float) -> void:
	if _kit != null:
		_kit.step(1, 5_000)


# ---------------------------------------------------------------- dialogs

func _dialog(view: String) -> void:
	var dlg: UiDialog = null
	match view:
		"rejected-data":
			dlg = UiDlgJoinRejected.new(NetProtocol.RejectReason.DATA_MISMATCH, {"host_game_version": "0.1.0", "local_game_version": "0.1.0",
				"host_data_hash": 0x9FF1B389, "local_data_hash": 0x41D8D123, "diff_lines": PackedStringArray(["units_nec.json: 14 values differ", "global.json: weapon archetype 'arc' differs"])},
				"192.168.1.20:27615")
		"rejected-proto":
			dlg = UiDlgJoinRejected.new(NetProtocol.RejectReason.PROTO_MISMATCH, {"host_game_version": "0.2.0", "local_game_version": "0.1.0",
				"host_proto_version": 3, "local_proto_version": 2}, "192.168.1.20:27615")
		"rejected-pw":
			dlg = UiDlgJoinRejected.new(NetProtocol.RejectReason.BAD_PASSWORD, {}, "Mara's game")
		"abort-map":
			dlg = UiDlgJoinRejected.for_abort(NetProtocol.AbortReason.MAP_MISMATCH, "Mara generated a different map (host 3F9A21C4, Mara 11B0E7D2).")
		"firewall-mac":
			dlg = UiDlgFirewallHelp.new("macos")
		"firewall-win":
			dlg = UiDlgFirewallHelp.new("windows")
		"firewall-linux":
			dlg = UiDlgFirewallHelp.new("linux")
		"host-dialog":
			dlg = UiDlgHostGame.new({"lobby_name": "Simon's game", "port": 27615, "advertise": true, "spectators": true})
		"connecting":
			dlg = UiDialog.new("Connecting", 460)
			dlg.add_text("Connecting to 192.168.1.20:27615 ...\nThe attempt gives up after 6 seconds.")
			dlg.add_button("Cancel", 0)
	if dlg != null:
		_stack.push(dlg)


# ---------------------------------------------------------------- browser

func _browser(empty: bool) -> void:
	var screen: UiScreenLanBrowser = UiScreenLanBrowser.new()
	_screen = screen
	add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter({"no_help": true})
	if screen.browser != null:
		screen.browser.close()
	var data: GameData = GameData.load_default()
	var clock: NetClock = NetClock.manual(10_000_000)
	var d: NetDiscovery = NetDiscovery.new()
	d.setup(clock, "0.1.0", NetProtocol.PROTO_VERSION, SimConfig.SIM_VERSION, data.data_hash())
	screen.browser = d
	if not empty:
		var rows: Array = [
			["Simon's game", "192.168.1.20", 27615, 0x1001, 0, 1, 3, 2, 128, 1, 0, data.data_hash(), SimConfig.SIM_VERSION, NetProtocol.PROTO_VERSION],
			["Friday night", "192.168.1.34", 27615, 0x1002, NetDiscoveryEntry.F_PASSWORD | NetDiscoveryEntry.F_SPECTATORS, 2, 4, 1, 160, 0, 1, data.data_hash(), SimConfig.SIM_VERSION, NetProtocol.PROTO_VERSION],
			["Big map FFA", "192.168.1.51", 27616, 0x1003, NetDiscoveryEntry.F_FULL, 4, 6, 0, 224, 2, 2, data.data_hash(), SimConfig.SIM_VERSION, NetProtocol.PROTO_VERSION],
			["Old build", "192.168.1.77", 27615, 0x1004, 0, 1, 2, 1, 96, 0, 0, 0x0BADF00D, SimConfig.SIM_VERSION, NetProtocol.PROTO_VERSION],
			["Mara", "192.168.1.90", 27615, 0x1005, NetDiscoveryEntry.F_SPECTATORS, 1, 2, 1, 96, 2, 0, data.data_hash(), SimConfig.SIM_VERSION, NetProtocol.PROTO_VERSION],
		]
		for r: Array in rows:
			var dg: PackedByteArray = NetDiscovery.encode_datagram({"host_name": r[0], "game_port": r[2], "session_id": r[3], "flags": r[4], "humans": r[5],
				"slots_total": r[6], "slots_free": r[7], "map_size": r[8], "map_family": r[9], "ai_count": r[10], "data_hash": r[11], "sim_version": r[12],
				"proto_version": r[13], "game_version": "0.1.0"})
			d.handle_datagram(str(r[1]), dg)
	await get_tree().process_frame
	screen._rebuild(true)
	if not empty and screen._rows.size() > 1:
		screen._select(str(screen._rows[4]["key"]))
	if empty:
		screen._empty_s = 9.0


# ---------------------------------------------------------------- lobby

func _lobby(view: String, drawer: bool) -> void:
	_kit = NetSessionKit.new()
	_kit.ai_factory = func(_pid: int, _level: int, _style: int, _seed: int) -> Callable: return func(_w: RefCounted, _out: Array) -> void: pass
	var host: NetSession = _kit.host("Simon", {"discovery_enabled": false, "countdown_s": 3})
	host.lobby.state.host_name = "Friday night"
	var mara: NetSession = _kit.join("Mara")
	var jules: NetSession = _kit.join("Jules")
	_kit.all_in(NetSession.Phase.LOBBY, 100)
	host.lobby.host_set_map(0, 128, 0xA31F09C2, 4)
	host.lobby.host_set_slot_roster(0, "roster.napc.vanilla")
	host.lobby.host_set_slot_team(0, 1)
	host.lobby.host_set_slot_kind(3, NetProtocol.SlotKind.AI)
	host.lobby.host_set_ai(3, 2, 0)
	host.lobby.host_set_slot_roster(3, "roster.han.vanilla")
	host.lobby.host_set_slot_team(3, 2)
	host.lobby.host_set_slot_handicap(3, 110)
	host.lobby.host_set_net_options({"speed_pct": 125})
	_kit.step(12, 60_000)
	var mara_slot: int = mara.lobby.local_slot()
	mara.lobby.set_roster("roster.nec.vanilla")
	mara.lobby.set_team(1)
	mara.lobby.set_ready(true)
	if view == "lobby-host" or view == "lobby-countdown":
		jules.lobby.set_roster("roster.def.vanilla")
		jules.lobby.set_team(2)
		# Jules watches
		jules.lobby.become_spectator()
	_kit.step(12, 60_000)
	host.peer_info(mara.local_peer_id).rtt_ms = 23
	_kit.step(30, 60_000)
	host.lobby.update_pings({mara.local_peer_id: 23})
	var params: Dictionary = {"lan": true, "session": host if view != "lobby-client" else mara}
	var screen: UiScreenLobby = UiScreenLobby.new()
	_screen = screen
	add_child(screen)
	UiLayerRoot.fill(screen)
	screen.enter(params)
	await get_tree().process_frame
	host.send_chat("Welcome, commanders. Map is Open land, 128 cells.", false)
	_kit.step(6, 60_000)
	mara.send_chat("Ready when you are", false)
	jules.send_chat("watching from the couch", false)
	_kit.step(12, 60_000)
	host.lobby.update_pings({mara.local_peer_id: 23})
	if view == "lobby-countdown":
		host.lobby.host_start()
		_kit.step(4, 60_000)
	if drawer:
		screen._toggle_drawer()
	if mara_slot < 0:
		Log.warn("app2", "lab: mara has no slot")
