extends RefCounted
## APP2: the lobby-role logic on fixtures (no sockets): roster picks <-> tokens, `UiLobbyNet.pull` / `diff` / permissions, the
## row status texts, `UiLanModel` (rows, filters, sorting, join rules, direct connect, hints), the join-rejected / abort / firewall /
## host-game dialog texts and `AppLan` helpers.

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


## Host "Simon" (slot 0, napc), client "Mara" (slot 1, nec, ready), AI hard (slot 2, han, team 2), slot 3 open, layout 4.
func _fixture() -> NetLobbyState:
	var st: NetLobbyState = NetLobbyState.create_default("Simon", 7, 0xA31F09C2)
	st.map_family = 2
	st.map_size = 160
	st.layout_players = 4
	st.slots[0].roster_id = "roster.napc.vanilla"
	st.slots[0].team = 1
	var m: NetPlayerSlot = st.slots[1]
	m.kind = NetProtocol.SlotKind.HUMAN
	m.peer_id = 2
	m.name = "Mara"
	m.roster_id = "roster.nec.vanilla"
	m.team = 1
	m.color = 1
	m.ready = true
	m.connected = true
	m.ping_ms = 23
	var ai: NetPlayerSlot = st.slots[2]
	ai.kind = NetProtocol.SlotKind.AI
	ai.name = "AI 3"
	ai.roster_id = "roster.han.vanilla"
	ai.team = 2
	ai.color = 2
	ai.ai_level = 2
	ai.handicap_pct = 110
	ai.ready = true
	ai.connected = true
	st.slots[3].kind = NetProtocol.SlotKind.OPEN
	st.rules["start_credits"] = 10000
	st.speed_code = 3
	st.pause_policy = 2
	st.auto_drop_ms = 30000
	st.password_set = true
	st.spectators = [{"peer_id": 5, "name": "Jules"}]
	return st


func _ui(net: NetLobbyState) -> UiLobbyState:
	var ui: UiLobbyState = UiLobbyState.create(_gd())
	UiLobbyNet.pull(net, ui)
	return ui


func _calls(ops: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for op: Dictionary in ops:
		var parts: PackedStringArray = PackedStringArray()
		for a: Variant in op["args"] as Array:
			parts.append(str(a))
		out.append("%s[%s]" % [op["call"], ", ".join(parts)])
	return out


func test_roster_picks_round_trip(t: TestCtx) -> void:
	var data: GameData = _gd()
	for r: DefRoster in data.rosters:
		var pick: Vector2i = UiLobbyNet.roster_pick(data, r.id)
		t.check(pick.x >= 0, "%s maps to a faction" % r.id)
		t.eq(UiLobbyNet.roster_token(data, pick.x, pick.y), r.id, "%s round-trips" % r.id)
	t.eq(UiLobbyNet.roster_pick(data, "random"), Vector2i(-1, 2))
	t.eq(UiLobbyNet.roster_pick(data, "random.vanilla"), Vector2i(-1, 0))
	t.eq(UiLobbyNet.roster_pick(data, "random.subfaction"), Vector2i(-1, 1))
	var nec: int = UiLobbyNet.roster_pick(data, "roster.nec.vanilla").x
	t.eq(UiLobbyNet.roster_pick(data, "random.nec"), Vector2i(nec, 4), "random.<faction> = any of its four")
	t.eq(UiLobbyNet.roster_token(data, nec, 4), "random.nec")
	t.eq(UiLobbyNet.roster_token(data, -1, 0), "random.vanilla")
	t.eq(UiLobbyNet.roster_token(data, -1, 1), "random.subfaction")
	t.eq(UiLobbyNet.roster_token(data, -1, 2), "random")
	t.eq(UiLobbyNet.roster_pick(data, "junk"), Vector2i(-1, 2), "an unknown id becomes Random")


func test_pull_mirrors_the_replicated_state(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	var ui: UiLobbyState = _ui(net)
	t.eq(ui.net_layout, 4)
	t.eq(ui.family, 2)
	t.eq(ui.size, 160)
	t.eq(ui.seed_value, 0xA31F09C2)
	t.eq(ui.start_credits, 10000)
	t.eq(ui.speed_pct, 125, "speed code 3 = 125 %")
	t.eq(ui.pause_policy, 2)
	t.eq(ui.auto_drop_ms, 30000)
	t.check(ui.password_set)
	t.eq(ui.spectators.size(), 1)
	t.eq(ui.slots[0].kind, UiLobbyState.Kind.HUMAN)
	t.eq(ui.slots[1].name, "Mara")
	t.eq(ui.slots[1].peer_id, 2)
	t.check(ui.slots[1].ready)
	t.eq(ui.slots[2].kind, UiLobbyState.Kind.AI)
	t.eq(ui.slots[2].ai_level, 2)
	t.eq(ui.slots[2].handicap, 110)
	t.eq(ui.slots[3].kind, UiLobbyState.Kind.OPEN)
	t.eq(ui.slots[4].kind, UiLobbyState.Kind.CLOSED, "slots beyond the layout are closed")
	var nec: int = UiLobbyNet.roster_pick(_gd(), "roster.nec.vanilla").x
	t.eq(ui.slots[1].faction, nec)
	t.eq(ui.layout_players(), 4, "the layout comes from the lobby, not from the slot count")
	t.check(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0).is_empty(), "a fresh pull has no difference to send")
	t.check(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.CLIENT, 1).is_empty())


func test_host_diff_expresses_one_widget_edit(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	var ui: UiLobbyState = _ui(net)
	# open slot 3 becomes a Brutal AI: kind, then the level
	ui.slots[3].kind = UiLobbyState.Kind.AI
	ui.slots[3].ai_level = 3
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_slot_kind[3, 3]", "host_set_ai[3, 3, 0]"]))
	ui = _ui(net)
	ui.slots[2].team = 3
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_slot_team[2, 3]"]))
	ui = _ui(net)
	ui.slots[2].handicap = 150
	ui.slots[0].start = 2
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_slot_start[0, 2]", "host_set_slot_handicap[2, 150]"]))
	ui = _ui(net)
	ui.slots[2].ai_level = 0
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_ai[2, 0, 0]"]))
	ui = _ui(net)
	var fac: int = UiLobbyNet.roster_pick(_gd(), "roster.olm.vanilla").x
	ui.slots[2].faction = fac
	ui.slots[2].sub = 4
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_slot_roster[2, random.olm]"]))
	ui = _ui(net)
	ui.slots[2].kind = UiLobbyState.Kind.CLOSED
	t.eq(_calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)), PackedStringArray(["host_set_slot_kind[2, 0]"]))
	ui = _ui(net)
	ui.slots[0].kind = UiLobbyState.Kind.OPEN
	t.check(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0).is_empty(), "the host's own row never changes kind")


func test_host_diff_map_rules_and_net_options(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	var ui: UiLobbyState = _ui(net)
	ui.size = 192
	ui.slots[2].team = 3
	var ops: Array[Dictionary] = UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)
	t.eq(_calls(ops), PackedStringArray(["host_set_map[2, 192, %d, 4]" % 0xA31F09C2]), "a map change is sent alone (the lobby then reshapes the slots)")
	ui = _ui(net)
	ui.set_layout_players(8)
	ops = UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)
	t.eq(int((ops[0]["args"] as Array)[3]), 8, "the layout dropdown is the lobby's layout")
	ui = _ui(net)
	ui.start_credits = 20000
	ui.fog = false
	ui.veterancy = true
	ops = UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)
	t.eq(ops.size(), 1)
	t.eq(ops[0]["call"], "host_set_rules")
	var r: Dictionary = (ops[0]["args"] as Array)[0] as Dictionary
	t.eq(r.size(), 3, "only the changed rules")
	t.eq(r["start_credits"], 20000)
	t.eq(r["fog"], false)
	ui = _ui(net)
	ui.speed_pct = 200
	ui.pause_policy = 0
	ui.on_disconnect = 1
	ui.allow_spectators = false
	ops = UiLobbyNet.diff(net, ui, UiLobbyNet.Role.HOST, 0)
	t.eq(ops[0]["call"], "host_set_net_options")
	var o: Dictionary = (ops[0]["args"] as Array)[0] as Dictionary
	t.eq(o["speed_pct"], 200)
	t.eq(o["pause_policy"], 0)
	t.eq(o["on_disconnect"], 1)
	t.eq(o["allow_spectators"], false)
	t.check(not o.has("auto_drop_ms"), "unchanged options are not resent")


func test_client_may_only_edit_its_own_row(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	var ui: UiLobbyState = _ui(net)
	ui.slots[1].team = 4
	ui.slots[1].color = 6
	ui.slots[1].start = 1
	ui.slots[1].faction = UiLobbyNet.roster_pick(_gd(), "roster.pd.vanilla").x
	ui.slots[1].sub = 0
	ui.slots[2].team = 4       # not the client's row: dropped
	ui.slots[0].color = 9
	ui.start_credits = 500     # host-only: dropped
	ui.family = 1
	var calls: PackedStringArray = _calls(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.CLIENT, 1))
	t.eq(calls, PackedStringArray(["set_roster[roster.pd.vanilla]", "set_team[4]", "set_color[6]", "set_start[1]"]))
	t.check(UiLobbyNet.diff(net, ui, UiLobbyNet.Role.CLIENT, -1).is_empty(), "a spectator edits nothing")


func test_row_permissions(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	var ui: UiLobbyState = _ui(net)
	t.check(UiLobbyNet.can_edit_row(UiLobbyNet.Role.HOST, 2, 0, ui), "the host edits an AI row")
	t.check(UiLobbyNet.can_edit_row(UiLobbyNet.Role.HOST, 1, 0, ui), "and a remote human's row")
	t.check(not UiLobbyNet.can_edit_row(UiLobbyNet.Role.HOST, 3, 0, ui), "an open row has no pickers")
	t.check(UiLobbyNet.can_edit_row(UiLobbyNet.Role.CLIENT, 1, 1, ui), "a client edits its own row")
	t.check(not UiLobbyNet.can_edit_row(UiLobbyNet.Role.CLIENT, 0, 1, ui), "not the host's")
	t.check(not UiLobbyNet.can_edit_row(UiLobbyNet.Role.CLIENT, 2, 1, ui), "not an AI's")
	t.check(UiLobbyNet.can_edit_kind(UiLobbyNet.Role.HOST, 1, 0), "the host can remove a player with the type picker")
	t.check(not UiLobbyNet.can_edit_kind(UiLobbyNet.Role.HOST, 0, 0), "but not itself")
	t.check(not UiLobbyNet.can_edit_kind(UiLobbyNet.Role.CLIENT, 2, 1), "a client never changes a slot type")
	t.check(UiLobbyNet.can_edit_kind(UiLobbyNet.Role.LOCAL, 2, 0) and not UiLobbyNet.can_edit_kind(UiLobbyNet.Role.LOCAL, 0, 0), "the skirmish keeps slot 0 human")


func test_status_and_start_error_rows(t: TestCtx) -> void:
	var net: NetLobbyState = _fixture()
	net.slots[1].ready = false
	var ui: UiLobbyState = _ui(net)
	t.eq(UiLobbyNet.status_of(ui.slots[0])["text"], "HOST")
	t.eq(UiLobbyNet.status_of(ui.slots[1])["text"], "NOT READY")
	t.eq(UiLobbyNet.status_of(ui.slots[1])["variation"], &"WarnLabel")
	t.eq(UiLobbyNet.status_of(ui.slots[2])["text"], "READY")
	t.eq(UiLobbyNet.status_of(ui.slots[3])["text"], "OPEN")
	t.eq(UiLobbyNet.status_of(ui.slots[5])["text"], "CLOSED")
	net.slots[1].connected = false
	ui = _ui(net)
	t.eq(UiLobbyNet.status_of(ui.slots[1])["text"], "DISCONNECTED")
	t.eq(UiLobbyNet.status_of(ui.slots[1])["variation"], &"DangerLabel")
	t.eq(UiLobbyNet.ping_text(ui.slots[1]), "", "a disconnected player shows no ping")
	net.slots[1].connected = true
	ui = _ui(net)
	t.eq(UiLobbyNet.ping_text(ui.slots[1]), "23 ms")
	t.eq(UiLobbyNet.ping_text(ui.slots[0]), "", "the host has no ping")
	t.eq(UiLobbyNet.error_rows(UiLobbyState.Err.HUMAN_NOT_READY, ui), PackedInt32Array([1]))
	t.eq(UiLobbyNet.error_rows(UiLobbyState.Err.NOT_ENOUGH_PLAYERS, ui), PackedInt32Array([3]), "the first open slot")
	t.eq(UiLobbyNet.error_rows(UiLobbyState.Err.MAP_INVALID, ui), PackedInt32Array(), "map errors highlight the panel, not rows")
	t.eq(UiLobbyNet.result_text(NetLobby.Result.CONFLICT), "That slot is not free.")
	t.eq(UiLobbyNet.result_text(NetLobby.Result.OK), "")


# ---------------------------------------------------------------- LAN browser model

func _entry(name_text: String, addr: String, humans: int, total: int, flags: int = 0, compatible: bool = true, mismatch: String = "") -> NetDiscoveryEntry:
	var e: NetDiscoveryEntry = NetDiscoveryEntry.new()
	e.host_name = name_text
	e.address = addr
	e.port = 27615
	e.session_id = name_text.hash() & 0xFFFF
	e.humans = humans
	e.slots_total = total
	e.slots_free = total - humans
	e.flags = flags
	e.map_family = 1
	e.map_size = 128
	e.game_version = "0.1.0"
	e.compatible = compatible
	e.mismatch = mismatch
	return e


func test_lan_rows_filters_and_sorting(t: TestCtx) -> void:
	var list: Array[NetDiscoveryEntry] = [
		_entry("Zed", "192.168.1.9", 1, 4),
		_entry("Alpha", "192.168.1.5", 2, 4, NetDiscoveryEntry.F_PASSWORD),
		_entry("Full one", "192.168.1.7", 4, 4, NetDiscoveryEntry.F_FULL),
		_entry("Old", "192.168.1.8", 1, 2, 0, false, "game data"),
	]
	var rows: Array[Dictionary] = UiLanModel.build_rows(list)
	t.eq(rows.size(), 4)
	t.eq(((rows[0]["cells"] as Array[Dictionary])[0] as Dictionary)["text"], "Alpha", "default order: by name")
	t.check(bool(rows[0]["locked"]), "a password game shows the padlock")
	var by_key: Dictionary = {}
	for r: Dictionary in rows:
		by_key[(r["entry"] as NetDiscoveryEntry).host_name] = r
	t.check(bool((by_key["Zed"] as Dictionary)["joinable"]))
	t.check(not bool((by_key["Full one"] as Dictionary)["joinable"]), "a full game is dimmed and not joinable")
	t.eq((by_key["Full one"] as Dictionary)["reason"], "The game is full.")
	t.check(bool((by_key["Old"] as Dictionary)["dimmed"]), "an incompatible game is dimmed")
	t.eq(((by_key["Old"] as Dictionary)["cells"] as Array[Dictionary])[UiLanModel.Col.BUILD]["text"], "v0.1.0  DATA", "and names the failing layer")
	t.eq(((by_key["Zed"] as Dictionary)["cells"] as Array[Dictionary])[UiLanModel.Col.BUILD]["text"], "v0.1.0  OK")
	t.eq(((by_key["Zed"] as Dictionary)["cells"] as Array[Dictionary])[UiLanModel.Col.PLAYERS]["text"], "1 / 4")
	t.eq(((by_key["Full one"] as Dictionary)["cells"] as Array[Dictionary])[UiLanModel.Col.PLAYERS]["text"], "4 / 4  FULL")
	rows = UiLanModel.build_rows(list, {"hide_full": true, "hide_incompatible": true})
	t.eq(rows.size(), 2, "the filters hide full and incompatible games")
	rows = UiLanModel.build_rows(list, {"text": "1.9"})
	t.eq(rows.size(), 1, "the text filter matches the address")
	rows = UiLanModel.build_rows(list, {"text": "urban"})
	t.eq(rows.size(), 4, "and the map family")
	rows = UiLanModel.build_rows(list, {}, UiLanModel.Col.GAME, true)
	t.eq(((rows[0]["cells"] as Array[Dictionary])[0] as Dictionary)["text"], "Zed", "descending sort")
	rows = UiLanModel.build_rows(list, {}, UiLanModel.Col.PLAYERS, true)
	t.eq(((rows[0]["cells"] as Array[Dictionary])[0] as Dictionary)["text"], "Full one", "sort by players")
	var busy: NetDiscoveryEntry = _entry("Busy", "192.168.1.11", 2, 4, NetDiscoveryEntry.F_IN_PROGRESS)
	t.check(not bool(UiLanModel.join_state(busy)["can_join"]))
	t.eq(UiLanModel.join_state(busy)["reason"], "The match has already started.")
	var spec: NetDiscoveryEntry = _entry("Spect", "192.168.1.12", 4, 4, NetDiscoveryEntry.F_FULL | NetDiscoveryEntry.F_SPECTATORS)
	t.check(bool(UiLanModel.join_state(spec)["can_join"]), "a full game that allows spectators can still be joined (as a spectator)")
	t.eq(UiLanModel.banner(list[3])["ok"], false)
	t.check(str(UiLanModel.banner(list[3])["text"]).contains("game data"))


func test_direct_connect_validation(t: TestCtx) -> void:
	var v: Dictionary = UiLanModel.validate_direct("192.168.1.20")
	t.check(bool(v["ok"]))
	t.eq(v["port"], 27615, "default port")
	t.eq(v["target"], "192.168.1.20:27615")
	v = UiLanModel.validate_direct("192.168.1.20:27700")
	t.eq(v["port"], 27700, "the address carries its port")
	v = UiLanModel.validate_direct("host.local", "27616")
	t.eq(v["port"], 27616, "the port field applies to a bare address")
	t.eq(v["host"], "host.local")
	t.check(not bool(UiLanModel.validate_direct("")["ok"]), "empty")
	t.check(not bool(UiLanModel.validate_direct("bad host!")["ok"]), "illegal characters")
	t.check(not bool(UiLanModel.validate_direct("10.0.0.1", "80")["ok"]), "port below 1024")
	t.check(not bool(UiLanModel.validate_direct("10.0.0.1", "70000")["ok"]), "port above 65535")
	t.check(not bool(UiLanModel.validate_direct("10.0.0.1", "abc")["ok"]), "port not a number")
	t.check(not bool(UiLanModel.validate_direct("a".repeat(254) + ".com")["ok"]), "host names up to 253 characters")
	v = UiLanModel.validate_direct("[fe80::1]:27615")
	t.check(bool(v["ok"]), "IPv6 literal with a port")
	t.eq(v["target"], "[fe80::1]:27615")
	t.eq(AppLan.merge_recent(PackedStringArray(["b:1", "a:2"]), "a:2"), PackedStringArray(["a:2", "b:1"]), "recent hosts: newest first, no duplicates")
	var many: PackedStringArray = PackedStringArray()
	for i: int in 8:
		many.append("h%d:1024" % i)
	t.eq(AppLan.merge_recent(many, "new:1024").size(), 8, "at most 8")


func test_silence_hints(t: TestCtx) -> void:
	t.eq(UiLanModel.hint("", 3.0), "", "no false alarm in the first seconds")
	t.eq(UiLanModel.hint("", 9.0), UiLanModel.HINT_NO_GAMES, "after 8 s of an empty list")
	t.eq(UiLanModel.hint("port_in_use", 0.0), UiLanModel.HINT_PORT_IN_USE)
	t.eq(UiLanModel.hint("", 0.0, true, false, 12.0), UiLanModel.HINT_ANNOUNCE_BLOCKED, "announce blocked for 10 s in the host lobby")
	t.eq(UiLanModel.hint("", 0.0, true, false, 4.0), "", "not yet")
	t.eq(UiLanModel.hint("", 0.0, true, true, 30.0), "", "announcing fine")


# ---------------------------------------------------------------- dialogs and helpers

func test_join_rejected_texts(t: TestCtx) -> void:
	var d: Dictionary = UiDlgJoinRejected.describe(NetProtocol.RejectReason.DATA_MISMATCH, {"host_game_version": "0.1.0", "local_game_version": "0.1.0",
		"host_data_hash": 0x9FF1B389, "local_data_hash": 0x41D8D123, "diff_lines": PackedStringArray(["a", "b"])})
	t.eq(d["title"], "Different game data")
	t.check(str(d["body"]).contains("game data"), "the text names the failing layer")
	t.check(str(d["body"]).contains("9FF1B389") and str(d["body"]).contains("41D8D123"), "and both hashes")
	t.eq((d["rows"] as Array).size(), 2)
	t.eq((d["extra"] as PackedStringArray).size(), 2, "the per-file differences")
	d = UiDlgJoinRejected.describe(NetProtocol.RejectReason.PROTO_MISMATCH, {"host_game_version": "0.2.0", "local_game_version": "0.1.0", "host_proto_version": 3, "local_proto_version": 2})
	t.eq(d["title"], "Different game version")
	t.check(str(d["body"]).contains("protocol"))
	d = UiDlgJoinRejected.describe(NetProtocol.RejectReason.SIM_MISMATCH, {"host_sim_version": 5, "local_sim_version": 4})
	t.check(str(d["body"]).contains("simulation"))
	t.eq(UiDlgJoinRejected.describe(NetProtocol.RejectReason.LOBBY_FULL, {})["body"], "The game is full.")
	t.eq(UiDlgJoinRejected.describe(NetProtocol.RejectReason.IN_PROGRESS, {})["body"], "The match has already started.")
	t.eq(UiDlgJoinRejected.describe(NetProtocol.RejectReason.BANNED, {})["body"], "The host removed you from this game.")
	t.eq(UiDlgJoinRejected.describe(NetProtocol.RejectReason.HOST_BUSY, {})["body"], "The host is starting the game. Try again in a moment.")
	var pw: Dictionary = UiDlgJoinRejected.describe(NetProtocol.RejectReason.BAD_PASSWORD, {}, "Simon's game")
	t.eq(pw["title"], "Password required")
	var a: Dictionary = UiDlgJoinRejected.abort_text(NetProtocol.AbortReason.MAP_MISMATCH, "Mara generated a different map (host 3F9A21C4, Mara 11B0E7D2).")
	t.eq(a["title"], "Different map generated")
	t.check(str(a["body"]).contains("3F9A21C4") and str(a["body"]).contains("same version"))
	t.eq(UiDlgJoinRejected.abort_text(NetProtocol.AbortReason.HUMAN_LEFT, "Mara left during loading")["title"], "A player left")
	t.eq(UiDlgJoinRejected.abort_text(NetProtocol.AbortReason.INIT_MISMATCH, "")["title"], "Different starting state")


func test_join_rejected_and_host_dialogs_build(t: TestCtx) -> void:
	var dlg: UiDlgJoinRejected = UiDlgJoinRejected.new(NetProtocol.RejectReason.BAD_PASSWORD, {}, "x")
	t.eq(dlg.button_count(), 2, "cancel + try again")
	t.eq(dlg.password(), "")
	var closed: Array = []
	dlg.closed.connect(func(r: int) -> void: closed.append(r))
	dlg.get_button(1).pressed.emit()
	t.eq(closed, [UiDlgJoinRejected.RESULT_RETRY])
	dlg.free()
	var plain: UiDlgJoinRejected = UiDlgJoinRejected.new(NetProtocol.RejectReason.LOBBY_FULL, {})
	t.eq(plain.button_count(), 1)
	plain.free()
	t.eq(UiDlgHostGame.validate({"lobby_name": "Simon's game", "port": 27615}), "")
	t.check(UiDlgHostGame.validate({"lobby_name": "  ", "port": 27615}) != "", "a name is required")
	t.check(UiDlgHostGame.validate({"lobby_name": "x", "port": 80}) != "", "port range")
	t.check(UiDlgHostGame.validate({"lobby_name": "x", "port": 27615, "password": "p".repeat(40)}) != "", "password length")
	var host: UiDlgHostGame = UiDlgHostGame.new({"lobby_name": "Friday", "port": 27700, "advertise": false, "spectators": false})
	var v: Dictionary = host.values()
	t.eq(v["lobby_name"], "Friday")
	t.eq(v["port"], 27700)
	t.eq(v["advertise"], false)
	t.eq(v["spectators"], false)
	t.check(not host.get_button(1).disabled, "HOST is enabled for valid settings")
	host.free()


func test_firewall_texts_per_platform(t: TestCtx) -> void:
	t.eq(AppLan.platform_key("Windows"), "windows")
	t.eq(AppLan.platform_key("macOS"), "macos")
	t.eq(AppLan.platform_key("Linux"), "linux")
	t.eq(AppLan.platform_key("FreeBSD"), "linux")
	var win: Dictionary = AppLan.firewall_text("windows")
	t.check(str(win["body"]).contains("Private networks") and str(win["body"]).contains("Windows Security"))
	var mac: Dictionary = AppLan.firewall_text("macos")
	t.check(str(mac["body"]).contains("Local Network") and str(mac["body"]).contains("Privacy & Security"))
	var lin: Dictionary = AppLan.firewall_text("linux")
	t.check(str(lin["body"]).contains("ufw allow 27614:27624/udp"), "the Debian ufw command")
	for k: Dictionary in [win, mac, lin]:
		t.check(str(k["ports"]).contains("27615") and str(k["ports"]).contains("27614"), "every platform lists the ports")
	var dlg: UiDlgFirewallHelp = UiDlgFirewallHelp.new("macos")
	t.eq(dlg.button_count(), 1)
	dlg.free()
