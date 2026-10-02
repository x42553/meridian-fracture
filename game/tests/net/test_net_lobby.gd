extends RefCounted
## NET-6: lobby protocol (join accept / reject matrix, permissions, swaps, normalisation, countdown, kick / ban,
## StartError coverage, chat limits, snapshot ordering, password proof) over NetSession + the loopback hub.

const P := NetSession.Phase
const R := NetLobby.Result


func _kit() -> NetSessionKit:
	return NetSessionKit.new()


func _rejects(client: NetSession) -> Array:
	var got: Array = []
	client.join_rejected.connect(func(reason: int, info: Dictionary) -> void: got.append([reason, info]))
	return got


func test_join_accept_and_snapshot(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	t.eq(h.phase, P.LOBBY)
	var c: NetSession = kit.join("Bob")
	t.eq(c.phase, P.CONNECTING)
	t.check(kit.all_in(P.LOBBY, 50))
	t.eq(c.lobby.state.slots[1].name, "Bob")
	t.eq(c.lobby.state.slots[1].kind, NetProtocol.SlotKind.HUMAN)
	t.eq(c.lobby.state.slots[1].peer_id, 2)
	t.eq(c.lobby.state.host_name, "Host's game")
	t.eq(c.lobby.state.session_id, h.lobby.state.session_id)
	t.check(not c.lobby.state.slots[1].ready)
	t.check(h.lobby.state.slots[0].ready, "the host counts as ready")
	t.eq(c.lobby.local_slot(), 1)
	kit.shutdown_all()


func _raw_reject(kit: NetSessionKit, fields: Dictionary) -> Dictionary:
	var ep: NetTransportLoopback = kit.raw_peer()
	kit.step(2)
	var f: Dictionary = {"proto_version": 1, "sim_version": 1, "data_hash": NetSessionKit.DATA_HASH, "client_nonce": 77, "game_version": "0.0.1", "name": "Raw"}
	f.merge(fields, true)
	ep.send(1, 0, NetCodec.encode_join_request(f))
	kit.step(2)
	var out: Dictionary = {"reject": {}, "disconnect_code": -1}
	for e: NetTransportEvent in kit.raw_take(ep):
		if e.kind == NetTransportEvent.Kind.PACKET and e.data[0] == NetProtocol.Msg.JOIN_REJECT:
			out["reject"] = NetCodec.decode_join_reject(e.data)
		elif e.kind == NetTransportEvent.Kind.DISCONNECTED:
			out["disconnect_code"] = e.code
	return out


func test_join_reject_protocol_and_simulation(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	kit.host("Host")
	var r: Dictionary = _raw_reject(kit, {"proto_version": 2})
	t.eq(int((r["reject"] as Dictionary).get("reason", -1)), NetProtocol.RejectReason.PROTO_MISMATCH)
	t.eq(int(r["disconnect_code"]), NetProtocol.RejectReason.PROTO_MISMATCH, "graceful disconnect carries the reason")
	# a garbage body after a foreign proto version is never parsed
	var ep: NetTransportLoopback = kit.raw_peer()
	kit.step(2)
	ep.send(1, 0, PackedByteArray([1, 9, 0, 0xFF, 0xFF]))
	kit.step(2)
	var got_reject: bool = false
	for e: NetTransportEvent in kit.raw_take(ep):
		if e.kind == NetTransportEvent.Kind.PACKET and e.data[0] == NetProtocol.Msg.JOIN_REJECT:
			got_reject = int(NetCodec.decode_join_reject(e.data)["reason"]) == NetProtocol.RejectReason.PROTO_MISMATCH
	t.check(got_reject, "frozen prefix: PROTO_MISMATCH without parsing further")
	# simulation version
	var c: NetSession = kit.join("Sim", {"sim_version": 2})
	var got: Array = _rejects(c)
	kit.step(10)
	t.eq(got.size(), 1)
	t.eq(int((got[0] as Array)[0]), NetProtocol.RejectReason.SIM_MISMATCH)
	t.check(str(((got[0] as Array)[1] as Dictionary)["text"]).contains("simulation"))
	t.eq(c.phase, P.IDLE)
	kit.shutdown_all()


func test_join_reject_data_mismatch_with_diff_and_file_retry(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var host_hs: Callable = func(with_files: bool) -> Dictionary:
		var d: Dictionary = {"format": 1, "hash": NetSessionKit.DATA_HASH, "tables": {"units": 2, "ids": 5, "weapons": 9}}
		if with_files:
			d["files"] = {"balance/units_napc.json": 10, "balance/global.json": 3}
		return d
	var client_hs: Callable = func(with_files: bool) -> Dictionary:
		var d: Dictionary = {"format": 1, "hash": 0x99999999, "tables": {"units": 1, "ids": 5, "weapons": 9}}
		if with_files:
			d["files"] = {"balance/units_napc.json": 11, "balance/global.json": 3}
		return d
	kit.host("Host", {"data_handshake": host_hs, "data_diff": GameData.diff_handshake})
	var c: NetSession = kit.join("Bob", {"data_handshake": client_hs, "data_diff": GameData.diff_handshake, "data_hash": 0x99999999})
	var got: Array = _rejects(c)
	kit.step(30)
	t.eq(got.size(), 1, "exactly one join_rejected after the retry")
	var info: Dictionary = (got[0] as Array)[1] as Dictionary
	t.eq(int((got[0] as Array)[0]), NetProtocol.RejectReason.DATA_MISMATCH)
	var lines: PackedStringArray = info["diff_lines"] as PackedStringArray
	t.check(lines.has("table units differs"), "table line: %s" % str(lines))
	t.check(lines.has("file balance/units_napc.json differs"), "file line after the retry: %s" % str(lines))
	t.check(not lines.has("file balance/global.json differs"))
	var text: String = str(info["text"])
	t.check(text.contains("1234ABCD".to_upper()) and text.contains("99999999"), "text names both hashes: " + text)
	t.eq(c.phase, P.IDLE)
	# a client WITHOUT data_handshake only gets the hash numbers
	var c2: NetSession = kit.join("Bob2", {"data_hash": 0x5})
	var got2: Array = _rejects(c2)
	kit.step(10)
	t.eq(got2.size(), 1)
	t.eq((((got2[0] as Array)[1] as Dictionary)["diff_lines"] as PackedStringArray).size(), 0)
	kit.shutdown_all()


func test_join_reject_full_password_spectators_busy(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host", {"password": "sesame", "allow_spectators": false})
	t.check(h.lobby.state.password_set)
	# no password: BAD_PASSWORD carries the session id
	var c1: NetSession = kit.join("NoPw")
	var g1: Array = _rejects(c1)
	kit.step(10)
	t.eq(int((g1[0] as Array)[0]), NetProtocol.RejectReason.BAD_PASSWORD)
	t.eq(int(((g1[0] as Array)[1] as Dictionary)["session_id"]), h.lobby.state.session_id)
	# wrong password: retried once with the proof, then rejected once
	var c2: NetSession = kit.join("Wrong", {"password": "nope"})
	var g2: Array = _rejects(c2)
	kit.step(20)
	t.eq(g2.size(), 1)
	t.eq(int((g2[0] as Array)[0]), NetProtocol.RejectReason.BAD_PASSWORD)
	# correct password
	var c3: NetSession = kit.join("Right", {"password": "sesame"})
	kit.step(20)
	t.eq(c3.phase, P.LOBBY)
	t.eq(h.lobby.state.human_count(), 2)
	# spectators closed
	var c4: NetSession = kit.join("Spec", {"password": "sesame", "join_as_spectator": true, "join_session_id": h.lobby.state.session_id})
	var g4: Array = _rejects(c4)
	kit.step(20)
	t.eq(int((g4[0] as Array)[0]), NetProtocol.RejectReason.SPECTATORS_CLOSED)
	# full: 2 slots
	t.eq(h.lobby.host_set_map(0, 96, 5, 2), R.OK)
	var c5: NetSession = kit.join("Third", {"password": "sesame", "join_session_id": h.lobby.state.session_id})
	var g5: Array = _rejects(c5)
	kit.step(20)
	t.eq(int((g5[0] as Array)[0]), NetProtocol.RejectReason.LOBBY_FULL)
	t.eq(str(((g5[0] as Array)[1] as Dictionary)["text"]), "The game is full.")
	kit.shutdown_all()


func test_join_reject_busy_and_in_progress(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host", {"countdown_s": 3})
	var c: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	c.lobby.set_team(2)
	kit.step(2)
	c.lobby.set_ready(true)
	kit.step(2)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	kit.step(2)
	t.eq(h.phase, P.COUNTDOWN)
	var late: NetSession = kit.join("Late")
	var g: Array = _rejects(late)
	kit.step(10)
	t.eq(int((g[0] as Array)[0]), NetProtocol.RejectReason.HOST_BUSY)
	kit.step(120)
	t.check(kit.run_until(func() -> bool: return h.phase == P.PLAYING and c.phase == P.PLAYING, 200))
	var late2: NetSession = kit.join("Late2")
	var g2: Array = _rejects(late2)
	kit.step(10)
	t.eq(int((g2[0] as Array)[0]), NetProtocol.RejectReason.IN_PROGRESS)
	kit.shutdown_all()


func test_permissions_swaps_and_normalisation(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(2, {"ai_default_handicap": func(level: int) -> int: return 120 if level == 3 else 100})
	var b: NetSession = kit.sessions[1]
	var c: NetSession = kit.sessions[2]
	# own slot edits
	t.eq(b.lobby.set_roster("roster.nec.a"), R.OK)
	t.eq(b.lobby.set_roster("roster.bogus"), R.INVALID, "unknown roster is refused locally")
	t.eq(b.lobby.set_roster("random.nec"), R.OK, "random tokens are fine")
	t.eq(b.lobby.set_team(9), R.INVALID)
	kit.step(3)
	t.eq(h.lobby.state.slots[1].roster_id, "random.nec")
	# host-only calls from a client are denied
	t.eq(b.lobby.host_set_slot_kind(3, NetProtocol.SlotKind.AI), R.DENIED)
	t.eq(b.lobby.host_kick(3, false), R.DENIED)
	t.eq(b.lobby.host_start(), NetLobby.StartError.ALREADY_LAUNCHING)
	# colour swap: b takes the host's colour
	var host_color: int = h.lobby.state.slots[0].color
	var b_color: int = h.lobby.state.slots[1].color
	t.eq(b.lobby.set_color(host_color), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.slots[1].color, host_color)
	t.eq(h.lobby.state.slots[0].color, b_color, "the two slots swapped colours")
	# start swap
	t.eq(c.lobby.set_start(2), R.OK)
	kit.step(3)
	t.eq(b.lobby.set_start(2), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.slots[1].start, 2)
	t.eq(h.lobby.state.slots[2].start, -1, "swap gave the old start (-1 = random) to the other slot")
	# unique names
	var d: NetSession = kit.join("P2")
	kit.step(10)
	t.eq(d.lobby.state.slots[3].name, "P2 (2)")
	t.eq(d.lobby.set_name("Host"), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.slots[3].name, "Host (2)")
	# sanitised names
	t.eq(d.lobby.set_name("[b]Evil[/b]\u0001"), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.slots[3].name, "bEvil/b")
	# spectator cannot edit: hostile LOBBY_ACTION is ignored and scored
	t.eq(d.lobby.become_spectator(), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.spectators.size(), 1)
	var before: int = h.violation_total()
	d.lobby.set_roster("roster.han.a")
	kit.step(3)
	t.eq(h.violation_total(), before + 1)
	t.eq(d.lobby.become_player(), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.spectators.size(), 0)
	t.eq(h.lobby.state.human_count(), 4)
	# move into an occupied slot is a conflict (scored), into an open one works
	before = h.violation_total()
	b.lobby.move_to_slot(0)
	kit.step(3)
	t.eq(h.violation_total(), before + 1)
	t.eq(b.lobby.move_to_slot(9), R.INVALID)
	t.eq(h.lobby.host_set_map(0, 128, 1, 6), R.OK)
	kit.step(3)
	t.eq(b.lobby.move_to_slot(5), R.OK)
	kit.step(3)
	t.eq(h.lobby.state.slots[5].peer_id, 2, "moved into an open slot")
	t.eq(h.lobby.state.slots[1].kind, NetProtocol.SlotKind.OPEN, "the old slot opens")
	kit.shutdown_all()


func test_ai_defaults_layout_shrink_and_ready_clearing(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(2, {"ai_default_handicap": func(level: int) -> int: return 120 if level == 3 else 100})
	var b: NetSession = kit.sessions[1]
	var c: NetSession = kit.sessions[2]
	t.eq(h.lobby.host_set_slot_kind(3, NetProtocol.SlotKind.AI), R.OK)
	t.eq(h.lobby.state.slots[3].handicap_pct, 100)
	t.eq(h.lobby.host_set_ai(3, 3, 2), R.OK)
	t.eq(h.lobby.state.slots[3].handicap_pct, 120, "Brutal defaults to a 120 handicap")
	t.eq(h.lobby.state.slots[3].ai_style, 2)
	t.eq(h.lobby.host_set_ai(3, 9, 0), R.INVALID)
	t.eq(h.lobby.host_set_slot_handicap(3, 133), R.INVALID)
	t.eq(h.lobby.host_set_slot_handicap(3, 135), R.OK)
	t.eq(h.lobby.state.slots[3].handicap_pct, 135)
	# ready flags are cleared by host edits of settings and of human slots (host excluded)
	b.lobby.set_ready(true)
	c.lobby.set_ready(true)
	kit.step(3)
	t.check(h.lobby.state.slots[1].ready and h.lobby.state.slots[2].ready)
	t.eq(h.lobby.host_set_rules({"start_credits": 15000}), R.OK)
	t.check(not h.lobby.state.slots[1].ready and not h.lobby.state.slots[2].ready, "rules change clears ready")
	t.eq(h.lobby.host_set_rules({"nonsense": 1}), R.INVALID)
	t.eq(h.lobby.host_set_rules({"unit_cap": 5}), R.INVALID)
	t.eq(h.lobby.host_set_net_options({"speed_pct": 150, "pause_policy": 0}), R.OK)
	t.eq(h.lobby.state.speed_code, 4)
	t.eq(h.lobby.host_set_net_options({"speed_pct": 111}), R.INVALID)
	b.lobby.set_ready(true)
	kit.step(3)
	t.eq(h.lobby.host_set_slot_team(1, 3), R.OK)
	t.check(not h.lobby.state.slots[1].ready, "editing a human slot clears ready")
	# layout shrink: slots >= 2 close, the human of slot 2 loses its seat (no free slot) and becomes a spectator
	t.eq(h.lobby.host_set_map(1, 96, 42, 2), R.OK)
	kit.step(5)
	t.eq(h.lobby.state.layout_players, 2)
	t.eq(h.lobby.state.slots[2].kind, NetProtocol.SlotKind.CLOSED)
	t.eq(h.lobby.state.slots[3].kind, NetProtocol.SlotKind.CLOSED)
	t.eq(h.lobby.state.spectators.size(), 1)
	t.eq(c.lobby.state.map_size, 96, "clients see the new map")
	t.eq(h.lobby.host_set_map(0, 100, 1, 4), R.INVALID)
	t.eq(h.lobby.host_set_map(0, 128, 1, 3), R.INVALID)
	t.eq(h.lobby.host_set_slot_kind(0, NetProtocol.SlotKind.CLOSED), R.DENIED, "the host's own slot cannot be closed")
	# closing a human slot kicks its peer
	var kicked: Array = []
	b.kicked.connect(func(reason: int, _d: String) -> void: kicked.append(reason))
	t.eq(h.lobby.host_set_slot_kind(1, NetProtocol.SlotKind.CLOSED), R.OK)
	kit.step(5)
	t.eq(kicked, [NetProtocol.KickReason.KICKED_BY_HOST])
	t.eq(b.phase, P.DISCONNECTED)
	kit.shutdown_all()


func test_countdown_lock_and_abort(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(1, {"countdown_s": 3})
	var b: NetSession = kit.sessions[1]
	b.lobby.set_team(2)
	b.lobby.set_ready(true)
	kit.step(3)
	var hs: Array = []
	var bs: Array = []
	h.countdown_changed.connect(func(n: int) -> void: hs.append(n))
	b.countdown_changed.connect(func(n: int) -> void: bs.append(n))
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	kit.step(2)
	t.eq(h.phase, P.COUNTDOWN)
	t.eq(b.phase, P.COUNTDOWN)
	t.eq(h.lobby.host_start(), NetLobby.StartError.ALREADY_LAUNCHING)
	t.eq(b.lobby.set_team(1), R.LOCKED, "the lobby is locked while counting down")
	t.eq(h.lobby.host_set_map(0, 128, 3, 4), R.LOCKED)
	kit.step(25)
	t.eq(hs.slice(0, 2), [3, 2], "countdown ticks at 1 Hz")
	# an unready click aborts
	b.lobby.set_ready(false)
	kit.step(3)
	t.eq(h.phase, P.LOBBY)
	t.eq(b.phase, P.LOBBY)
	t.eq(hs.back(), 0)
	t.eq(bs.back(), 0)
	t.check(not h.lobby.state.slots[1].ready)
	t.eq(h.lobby.state.phase, NetProtocol.LobbyPhase.OPEN)
	# host cancel
	b.lobby.set_ready(true)
	kit.step(3)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	kit.step(2)
	h.lobby.host_cancel_start()
	kit.step(3)
	t.eq(h.phase, P.LOBBY)
	t.eq(b.phase, P.LOBBY)
	# a client leaving during the countdown aborts it too
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	kit.step(2)
	b.leave()
	kit.step(3)
	t.eq(h.phase, P.LOBBY)
	t.eq(h.lobby.state.human_count(), 1)
	kit.shutdown_all()


func test_kick_and_ban(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(2)
	var b: NetSession = kit.sessions[1]
	var got: Array = []
	b.kicked.connect(func(reason: int, detail: String) -> void: got.append([reason, detail]))
	t.eq(h.lobby.host_kick(2, false), R.OK)
	kit.step(5)
	t.eq(int((got[0] as Array)[0]), NetProtocol.KickReason.KICKED_BY_HOST)
	t.eq(h.lobby.state.slots[1].kind, NetProtocol.SlotKind.OPEN, "the slot opens again")
	t.eq(h.lobby.state.human_count(), 2)
	t.eq(h.lobby.host_kick(1, false), R.INVALID, "cannot kick the host")
	t.eq(h.lobby.host_kick(77, false), R.INVALID)
	# rejoin after a plain kick works
	var b2: NetSession = kit.join("Bob")
	kit.step(10)
	t.eq(b2.phase, P.LOBBY)
	# ban: the same nonce is refused even from another address
	var pid_of_b2: int = b2.local_peer_id
	t.eq(h.lobby.host_kick(pid_of_b2, true), R.OK)
	kit.step(5)
	var b3: NetSession = kit.join("Bob")
	var g3: Array = _rejects(b3)
	kit.step(10)
	t.eq(int((g3[0] as Array)[0]), NetProtocol.RejectReason.BANNED, "banned by nonce")
	# ... and the same address with a fresh nonce
	# first find the banned address: b2 was created with the kit's numbering (10.0.0.<key>)
	var banned_ip: String = ""
	for bn: Variant in h.lobby.bans:
		banned_ip = str((bn as Dictionary)["ip"])
	var fixed: Callable = func() -> NetTransport:
		var ep2: NetTransportLoopback = kit.hub.endpoint(950 + kit.sessions.size())
		ep2.address = banned_ip
		return ep2
	var b4: NetSession = kit.join("Alice", {"client_nonce": 424242, "transport_factory": fixed})
	var g4: Array = _rejects(b4)
	kit.step(10)
	t.eq(int((g4[0] as Array)[0]), NetProtocol.RejectReason.BANNED, "banned by address")
	kit.shutdown_all()


func test_start_error_coverage(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	# dedicated host without players
	var d: NetSession = kit.host("Ded", {"dedicated": true})
	t.eq(d.lobby.host_start(), NetLobby.StartError.NO_PLAYERS)
	d.shutdown()
	kit.sessions.clear()
	var kit2: NetSessionKit = _kit()
	var h: NetSession = kit2.host("Host")
	t.eq(h.lobby.host_start(), NetLobby.StartError.NOT_ENOUGH_PLAYERS)
	var b: NetSession = kit2.join("Bob")
	kit2.all_in(P.LOBBY, 50)
	t.eq(h.lobby.host_start(), NetLobby.StartError.HUMAN_NOT_READY)
	b.lobby.set_ready(true)
	kit2.step(3)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK, "no team = every player is alone in its team")
	kit2.shutdown_all()


func test_start_error_matrix(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host")
	var b: NetSession = kit.join("Bob")
	kit.all_in(P.LOBBY, 50)
	b.lobby.set_ready(true)
	b.lobby.set_team(2)
	h.lobby.set_team(1)
	kit.step(3)
	var st: NetLobbyState = h.lobby.state
	t.eq(h.lobby.start_error(), NetLobby.StartError.OK)
	var E := NetLobby.StartError
	# HUMAN_DISCONNECTED
	st.slots[1].connected = false
	t.eq(h.lobby.start_error(), E.HUMAN_DISCONNECTED)
	st.slots[1].connected = true
	# BAD_ROSTER
	st.slots[0].roster_id = "roster.nope.x"
	t.eq(h.lobby.start_error(), E.BAD_ROSTER)
	st.slots[0].roster_id = "random"
	# COLOR_CONFLICT
	var c1: int = st.slots[1].color
	st.slots[1].color = st.slots[0].color
	t.eq(h.lobby.start_error(), E.COLOR_CONFLICT)
	st.slots[1].color = c1
	# START_CONFLICT
	st.slots[0].start = 1
	st.slots[1].start = 1
	t.eq(h.lobby.start_error(), E.START_CONFLICT)
	st.slots[1].start = 9
	t.eq(h.lobby.start_error(), E.START_CONFLICT, "start beyond the layout")
	st.slots[0].start = -1
	st.slots[1].start = -1
	# TOO_MANY_PLAYERS (state forced: layout 2 with 3 actives)
	h.lobby.host_set_slot_kind(2, NetProtocol.SlotKind.AI)
	st.slots[1].ready = true
	st.layout_players = 2
	t.eq(h.lobby.start_error(), E.TOO_MANY_PLAYERS)
	st.layout_players = 4
	# AI_UNAVAILABLE (no ai_factory)
	t.eq(h.lobby.start_error(), E.AI_UNAVAILABLE)
	h.lobby.host_set_slot_kind(2, NetProtocol.SlotKind.OPEN)
	st.slots[1].ready = true
	# SINGLE_TEAM
	st.slots[0].team = 2
	t.eq(h.lobby.start_error(), E.SINGLE_TEAM)
	st.slots[0].team = 1
	# ALREADY_LAUNCHING
	st.phase = NetProtocol.LobbyPhase.COUNTDOWN
	t.eq(h.lobby.start_error(), E.ALREADY_LAUNCHING)
	st.phase = NetProtocol.LobbyPhase.OPEN
	t.eq(h.lobby.start_error(), E.OK)
	# MAP_INVALID
	h.lobby.opts.map_validator = func(_f: int, _s: int, _l: int) -> String: return "no such map"
	t.eq(h.lobby.start_error(), E.MAP_INVALID)
	h.lobby.opts.map_validator = Callable()
	# allow_solo lets a single player start; single team allowed too
	h.lobby.opts.allow_solo = true
	st.slots[0].team = 1
	st.slots[1].team = 1
	t.eq(h.lobby.start_error(), E.OK)
	h.lobby.opts.allow_solo = false
	for code: int in E.values():
		t.check(code == 0 or NetLobby.start_error_text(code) != "", "text for %d" % code)
	kit.shutdown_all()


func test_chat_sanitising_limits_and_team_channel(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(2)
	var b: NetSession = kit.sessions[1]
	var c: NetSession = kit.sessions[2]
	b.lobby.set_team(2)
	c.lobby.set_team(2)
	h.lobby.set_team(1)
	kit.step(3)
	var hl: Array = []
	var cl: Array = []
	var bl: Array = []
	h.chat_received.connect(func(ch: int, slot: int, nm: String, text: String) -> void: hl.append([ch, slot, nm, text]))
	c.chat_received.connect(func(ch: int, slot: int, nm: String, text: String) -> void: cl.append([ch, slot, nm, text]))
	b.chat_received.connect(func(ch: int, slot: int, nm: String, text: String) -> void: bl.append([ch, slot, nm, text]))
	b.send_chat("  hello\u0001   world\t ")
	kit.step(3)
	t.eq(hl.size(), 1)
	t.eq((hl[0] as Array)[3], "hello world", "control characters removed, whitespace collapsed")
	t.eq((hl[0] as Array)[1], 1)
	t.eq((hl[0] as Array)[2], "P2")
	t.eq(cl.size(), 1, "relayed to the other client")
	t.eq(bl.size(), 1, "the sender sees its own line")
	# 200-byte cut on a UTF-8 boundary
	var long: String = ""
	for _i: int in 150:
		long += "é"
	b.send_chat(long)
	kit.step(3)
	var got: String = (hl[1] as Array)[3]
	t.le(got.to_utf8_buffer().size(), 200)
	t.check(NetProtocol.is_valid_utf8(got.to_utf8_buffer(), 0, got.to_utf8_buffer().size()))
	t.eq(got.to_utf8_buffer().size(), 200)
	# team channel: only teammates (b, c team 2) see it, not the host (team 1)
	hl.clear()
	cl.clear()
	b.send_chat("psst", true)
	kit.step(3)
	t.eq(hl.size(), 0, "team chat is not relayed to the other team")
	t.eq(cl.size(), 1)
	# rate limit: 5 messages per 5 s, the 6th in that window is dropped and scored
	hl.clear()
	kit.step(120)  # let the bucket refill
	var before: int = h.violation_total()
	for i: int in 6:
		b.send_chat("msg %d" % i)
	kit.step(3)
	t.eq(hl.size(), 5, "6th message dropped")
	t.eq(h.violation_total(), before + 1)
	# system lines use slot 255
	h.lobby.system_chat("hello all")
	kit.step(3)
	t.eq((bl.back() as Array)[1], 255)
	kit.shutdown_all()


func test_snapshot_revision_ordering(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(1)
	var b: NetSession = kit.sessions[1]
	var old: PackedByteArray = NetLobbyCodec.encode_snapshot(h.lobby.state)
	var rev: int = b.lobby.state.revision
	h.lobby.host_set_rules({"start_credits": 20000})
	kit.step(5)
	t.gt(b.lobby.state.revision, rev)
	t.eq(int(b.lobby.state.rules["start_credits"]), 20000)
	t.check(not b.lobby.handle_snapshot(old), "an older snapshot is ignored")
	t.eq(int(b.lobby.state.rules["start_credits"]), 20000)
	t.check(not b.lobby.handle_snapshot(NetLobbyCodec.encode_snapshot(b.lobby.state)), "an equal revision is ignored")
	kit.shutdown_all()


func test_snapshot_coalescing(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.lobby_of(1)
	var b: NetSession = kit.sessions[1]
	var applied: PackedInt32Array = PackedInt32Array([0])
	b.lobby_changed.connect(func() -> void: applied[0] += 1)
	# ten quick edits inside 100 ms produce far fewer snapshots than edits
	h.lobby.host_set_slot_kind(2, NetProtocol.SlotKind.AI)
	kit.step(4)
	applied[0] = 0
	for i: int in 10:
		h.lobby.host_set_slot_team(2, i % 5)
		h.poll()
	kit.step(4)
	t.check(applied[0] >= 1 and applied[0] <= 3, "coalesced: %d snapshots for 10 edits" % applied[0])
	t.eq(b.lobby.state.slots[2].team, 4, "the last write wins")
	kit.shutdown_all()
