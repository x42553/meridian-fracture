extends RefCounted
## NET-11: virtual-time scenario suite (docs/spec/net.md 10.4). Host + 3 clients as real NetSessions over the loopback hub,
## every endpoint behind a NetTransportFault, NetSimAdapterFake worlds and seeded random command scripts. S13-S19 live in
## test_net_desync / test_net_security / test_net_lobby / test_net_session (same behaviours, unit-level).

const P := NetSession.Phase


func _rig(preset: String, extra: Dictionary = {}) -> NetScenarioRig:
	var r: NetScenarioRig = NetScenarioRig.new(NetFaultProfile.preset(preset))
	for k: Variant in extra:
		r.set(str(k), extra[k])
	return r


func _stat(r: NetScenarioRig, idx: int) -> Dictionary:
	return r.sess(idx).stats()


func _tick_span(r: NetScenarioRig) -> Array:
	var tk: PackedInt32Array = r.ticks()
	var lo: int = tk[0]
	var hi: int = tk[0]
	for v: int in tk:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	return [lo, hi]


func test_s1_lan_120s(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("lan")
	t.check(r.launch(3), "launched")
	r.run_seconds(120.0)
	var span: Array = _tick_span(r)
	t.note("S1 ticks %s lat %s wire %s" % [str(span), str(r.latency_ms()), str(r.wire_bytes_per_s(120.0))])
	t.ge(int(span[0]), 2385)
	t.le(int(span[1]), 2400)
	t.eq(r.mismatches(), 0)
	t.gt(r.checks_compared(), 100)
	for nd: NetScenarioRig.RigPeer in r.nodes:
		t.eq(nd.delay_changes.size(), 0, "%s: input delay never changed" % nd.name)
		t.eq(int(nd.session.stats()["delay_turns"]), 2)
	var lat: Dictionary = r.latency_ms()
	t.check(absf(float(lat["avg"]) - 240.0) <= 25.0, "avg command latency %s" % str(lat))
	t.le(float(lat["p95"]), 320.0)
	t.eq(int(r.client_stalls()["count"]), 0, "no stalls")
	t.le(float(r.wire_bytes_per_s(120.0)["total"]), 6144.0, "total wire <= 6 KB/s")
	r.shutdown()


func _summary(r: NetScenarioRig, secs: float) -> String:
	var st: Dictionary = r.client_stalls()
	return "ticks %s D %d lat %s stalls %s wire %s mism %d" % [str(r.ticks()), int(_stat(r, 0)["delay_turns"]),
		str(r.latency_ms()), str(st), str(r.wire_bytes_per_s(secs)), r.mismatches()]


func test_s2_wifi_120s(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("wifi")
	t.check(r.launch(3), "launched")
	r.run_seconds(120.0)
	t.note("S2 " + _summary(r, 120.0))
	t.eq(int(_stat(r, 0)["delay_turns"]), 2)
	t.eq(r.mismatches(), 0)
	t.le(int(r.client_stalls()["ms"]), 100, "total stall <= 100 ms")
	r.shutdown()


func test_s3_bad_wifi_120s(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("bad_wifi")
	t.check(r.launch(3), "launched")
	r.run_seconds(120.0)
	t.note("S3 " + _summary(r, 120.0))
	var d: int = int(_stat(r, 0)["delay_turns"])
	t.check(d >= 3 and d <= 5, "final D %d in [3,5]" % d)
	t.eq(r.mismatches(), 0)
	t.le(int(r.client_stalls()["ms"]), 5000, "total client stall <= 5 s")
	t.le(float(r.latency_ms()["avg"]), 520.0)
	r.shutdown()


func test_s4_internet_120s(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("internet")
	t.check(r.launch(3), "launched")
	r.run_seconds(120.0)
	t.note("S4 " + _summary(r, 120.0))
	var d: int = int(_stat(r, 0)["delay_turns"])
	t.check(d >= 4 and d <= 6, "final D %d in [4,6]" % d)
	t.eq(r.mismatches(), 0)
	t.le(float(r.latency_ms()["avg"]), 650.0)
	r.shutdown()


func test_s5_awful_120s(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("awful")
	t.check(r.launch(3), "launched")
	r.run_seconds(120.0)
	t.note("S5 " + _summary(r, 120.0))
	t.eq(int(_stat(r, 0)["delay_turns"]), 8)
	t.ge(r.ticks()[0], 1920, ">= 80 % of 2400 ticks")
	t.eq(r.mismatches(), 0)
	r.shutdown()


func test_s6_wifi_clock_drift_300s(t: TestCtx) -> void:
	t.set_timeout(200.0)
	var r: NetScenarioRig = _rig("wifi")
	t.check(r.launch(3, [0, 150, -150, 150]), "launched")
	r.run_seconds(300.0)
	t.note("S6 " + _summary(r, 300.0))
	t.eq(int(_stat(r, 0)["delay_turns"]), 2)
	t.le(int(r.client_stalls()["count"]), 30, "few stalls (3 clients)")
	t.le(int(r.client_stalls()["ms"]), 1000, "stalls stay short")
	t.eq(r.mismatches(), 0)
	r.shutdown()


func _stall_ms(r: NetScenarioRig, idx: int) -> int:
	return int(_stat(r, idx)["stall_ms"])


func test_s7_lan_client_frozen_3s(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("lan")
	t.check(r.launch(3), "launched")
	r.run_seconds(20.0)
	var before: Array = [_stall_ms(r, 0), _stall_ms(r, 1), _stall_ms(r, 3)]
	r.freeze(2, 3000)
	r.run_seconds(3.5)
	var stalls: Array = [_stall_ms(r, 0) - int(before[0]), _stall_ms(r, 1) - int(before[1]), _stall_ms(r, 3) - int(before[2])]
	r.run_seconds(6.0)
	t.note("S7 stalls during freeze %s ticks %s D %d" % [str(stalls), str(r.ticks()), int(_stat(r, 0)["delay_turns"])])
	for v: Variant in stalls:
		t.check(int(v) >= 2500 and int(v) <= 3300, "the others stall about 3 s (got %d ms)" % int(v))
	for i: int in 4:
		t.eq(int(_stat(r, i)["delay_turns"]), 2, "D unchanged (quarantine) on peer %d" % i)
	var span: Array = _tick_span(r)
	t.le(int(span[1]) - int(span[0]), 3, "tick spread after the resume")
	t.eq(r.mismatches(), 0)
	r.shutdown()


func test_s8_lan_pause_3s(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("lan")
	t.check(r.launch(3), "launched")
	r.run_seconds(10.0)
	t.eq(r.sess(2).request_pause(true), 0)
	r.run_seconds(0.5)
	var frozen_at: PackedInt32Array = r.ticks()
	r.run_seconds(2.5)
	t.eq(r.ticks(), frozen_at, "no ticks on any peer during the pause")
	t.eq(frozen_at[0], frozen_at[1], "same tick on all peers")
	t.eq(frozen_at[2], frozen_at[3])
	t.eq(r.host().request_pause(false), 0, "the host resumes")
	r.run_seconds(17.0)
	var span: Array = _tick_span(r)
	t.note("S8 ticks %s" % str(r.ticks()))
	t.check(absi(int(span[0]) - (600 - 60)) <= 8 and absi(int(span[1]) - (600 - 60)) <= 8, "ticks %s ~ expected 540" % str(span))
	for nd: NetScenarioRig.RigPeer in r.nodes:
		t.check(nd.pauses.has([true, 2]) and nd.pauses.has([false, 0]), "%s saw pause_changed both ways: %s" % [nd.name, str(nd.pauses)])
	t.eq(r.host().turn_host.pauses_used(2), 1, "requester used one pause")
	t.eq(r.mismatches(), 0)
	r.shutdown()


func _ai_stub() -> Callable:
	return func(pid: int, _level: int, _style: int, _seed: int) -> Callable:
		return func(_world: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid]))


func _first_resign_index(s: NetSession, pid: int) -> Array:
	var log_: SimCommandLog = s.command_log()
	var first_tick: int = -1
	var idx_in_group: int = 0
	for i: int in log_.cmds.size():
		if log_.pids[i] != pid:
			continue
		if first_tick >= 0 and log_.ticks[i] != first_tick:
			break
		if first_tick < 0 and log_.cmds[i][0] == NetProtocol.T_RESIGN:
			first_tick = log_.ticks[i]
			return [first_tick, idx_in_group]
		if log_.cmds[i][0] != NetProtocol.T_RESIGN:
			if first_tick < 0 and i + 1 < log_.cmds.size():
				pass
	return [-1, -1]


func _drop_scenario(t: TestCtx, mode: int) -> NetScenarioRig:
	var r: NetScenarioRig = _rig("lan", {"ai_factory": _ai_stub()})
	t.check(r.launch(3), "launched")
	r.run_seconds(30.0)
	r.freeze(1, 10_000)
	r.run_seconds(10.0)
	t.check(r.host().waiting_list().size() >= 1, "host is waiting for the frozen player")
	r.tick_at_drop = r.ticks()[0]
	r.host().host_resolve_stall(1, mode)
	r.run_seconds(10.0)
	return r


func test_s9_drop_to_ai(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _drop_scenario(t, NetProtocol.StallAction.STALL_DROP_AI)
	for i: int in [0, 2, 3]:
		var s: NetSession = r.sess(i)
		t.eq(s.player_status(1), NetProtocol.PlayerNetStatus.AI_TAKEOVER, "peer %d agrees pid 1 is AI" % i)
		t.check(s.command_log().cmds.any(func(c: PackedInt32Array) -> bool: return c.size() == 2 and c[0] == 9 and c[1] == 1), "AI commands for pid 1 on peer %d" % i)
		t.eq(s.phase, P.PLAYING)
	t.eq(r.mismatches(), 0)
	t.gt(r.ticks()[0], r.tick_at_drop + 150, "the game went on after the drop")
	r.shutdown()


func test_s10_drop_resign(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _drop_scenario(t, NetProtocol.StallAction.STALL_DROP_RESIGN)
	var ticks: Array = []
	for i: int in [0, 2, 3]:
		var s: NetSession = r.sess(i)
		t.eq(s.player_status(1), NetProtocol.PlayerNetStatus.DROPPED)
		t.check(not s.adapter().is_player_active(1), "pid 1 is inactive on peer %d" % i)
		var lg: SimCommandLog = s.command_log()
		var at: int = -1
		for k: int in lg.cmds.size():
			if lg.pids[k] == 1 and lg.cmds[k][0] == NetProtocol.T_RESIGN:
				at = k
				break
		t.ge(at, 0, "T_RESIGN recorded on peer %d" % i)
		if at >= 0:
			var first_of_group: bool = at == 0 or lg.pids[at - 1] != 1 or lg.ticks[at - 1] != lg.ticks[at]
			t.check(first_of_group, "T_RESIGN is first in pid 1's group")
			ticks.append(lg.ticks[at])
	t.eq(ticks.size(), 3)
	t.check(ticks[0] == ticks[1] and ticks[1] == ticks[2], "the same turn on every peer: %s" % str(ticks))
	t.eq(r.mismatches(), 0)
	r.shutdown()


func test_s11_raw_chaos_dup_and_reorder(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("raw_chaos")
	t.check(r.launch(3), "launched")
	r.run_seconds(60.0)
	var dup: int = 0
	var ooo: int = 0
	for i: int in 4:
		dup += int(_stat(r, i)["dup_in"])
		ooo += int(_stat(r, i)["ooo_in"])
	t.note("S11 ticks %s dup_in %d ooo_in %d" % [str(r.ticks()), dup, ooo])
	t.gt(dup, 0, "duplicates were seen and dropped")
	t.gt(ooo, 0, "out-of-order bundles were buffered")
	t.eq(r.mismatches(), 0)
	t.gt(r.checks_compared(), 40)
	r.shutdown()


# ---- S13 / S14 at 4-peer scale ------------------------------------------------------------------------------------------

func test_s13_injected_divergence_is_detected_everywhere(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("lan")
	r.builders["P3"] = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter:
			var f: NetSimAdapterFake = NetSimAdapterFake.new(seed_v)
			f.inject_divergence(400, 1)
			return f)
	t.check(r.launch(3), "launched")
	t.check(r.run_until(func() -> bool: return r.nodes.all(func(n: NetScenarioRig.RigPeer) -> bool: return n.session.phase == P.DESYNCED), 3000), "all four peers are DESYNCED")
	r.frames(300)
	for nd: NetScenarioRig.RigPeer in r.nodes:
		t.eq(nd.desyncs.size(), 1, "%s raised desync_detected once" % nd.name)
		if nd.desyncs.size() == 1:
			var rep: Dictionary = nd.desyncs[0] as Dictionary
			t.eq(int(rep["tick"]), 400)
			var files: Dictionary = rep["files"] as Dictionary
			for key: String in ["json", "state", "checks"]:
				t.check(files.has(key) and FileAccess.file_exists(r.desync_dir.path_join(str(files[key]))), "%s: %s file exists" % [nd.name, key])
	r.shutdown()


func test_s14_corrupted_bundle_is_a_protocol_error_not_a_desync(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("lan")
	t.check(r.launch(3), "launched")
	r.run_seconds(5.0)
	# the host's transport flips one byte of the next TURN_BUNDLE it sends to client 2 (peer id 3)
	r.nodes[0].fault.corrupt_next(3, NetProtocol.CH_TURN)
	r.run_seconds(3.0)
	var victim: NetScenarioRig.RigPeer = r.nodes[2]
	t.check(victim.errors.size() >= 1, "the client reported a protocol error: %s" % str(victim.errors))
	if victim.errors.size() >= 1:
		t.eq(int((victim.errors[0] as Array)[0]), NetProtocol.NetErrorCode.HOST_PROTOCOL)
	for nd: NetScenarioRig.RigPeer in r.nodes:
		t.eq(nd.desyncs.size(), 0, "%s: no desync report" % nd.name)
		t.check(nd.session.phase != P.DESYNCED)
	r.shutdown()


# ---- S19: 5 humans + 3 AI --------------------------------------------------------------------------------------------------

func test_s19_eight_players_five_humans_three_ai(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: NetScenarioRig = _rig("wifi", {"ai_factory": _ai_stub()})
	t.check(r.launch(4, [], 3, 8), "8-player lobby launched")
	r.run_seconds(60.0)
	t.note("S19 ticks %s mism %d checks %d" % [str(r.ticks()), r.mismatches(), r.checks_compared()])
	t.eq(r.mismatches(), 0)
	t.ge(_tick_span(r)[0], 1150, "60 s of play")
	var found: bool = false
	for i: int in r.host().command_log().cmds.size():
		var c: PackedInt32Array = r.host().command_log().cmds[i]
		if c.size() == 2 and c[0] == 9 and r.host().command_log().pids[i] >= 5:
			found = true
	t.check(found, "AI commands of slots 5..7 were executed")
	r.shutdown()


# ---- 8-player virtual-time load (timings, turn latency, bandwidth per client) ---------------------------------------

func _load_run(t: TestCtx, preset: String, cmd_ms: int, label: String) -> Dictionary:
	var r: NetScenarioRig = _rig(preset)
	t.check(r.launch(7, [], 0, 8), "8 humans launched")
	for nd: NetScenarioRig.RigPeer in r.nodes:
		nd.cmd_rate_ms = cmd_ms
	r.run_seconds(60.0)
	var w: Dictionary = r.wire_bytes_per_s(60.0)
	var lat: Dictionary = r.latency_ms()
	var st: Dictionary = r.client_stalls()
	t.note("LOAD8 %s cmd/%d ms: D %d ticks %s lat avg %.0f p95 %.0f max %.0f ms, client out %.0f B/s, host out %.0f B/s, stalls %s, mism %d" % [
		label, cmd_ms, int(_stat(r, 0)["delay_turns"]), str(_tick_span(r)), float(lat["avg"]), float(lat["p95"]), float(lat["max"]),
		float(w["client_out"]), float(w["host_out"]), str(st), r.mismatches()])
	t.eq(r.mismatches(), 0)
	t.ge(_tick_span(r)[0], 1100)
	var out: Dictionary = {"wire": w, "lat": lat, "stalls": st}
	r.shutdown()
	return out


func test_load_eight_players_lan_and_wifi(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var lan: Dictionary = _load_run(t, "lan", 250, "lan")
	t.le(float((lan["wire"] as Dictionary)["client_out"]), 2000.0, "a client sends < 2 KB/s at 4 cmd/s")
	t.le(float((lan["wire"] as Dictionary)["host_out"]), 12000.0, "the host relays 8 players in < 12 KB/s")
	var heavy: Dictionary = _load_run(t, "wifi", 60, "wifi heavy")
	t.le(float((heavy["wire"] as Dictionary)["client_out"]), 4000.0)


# ---- S12 / D1 / D2 ---------------------------------------------------------------------------------------------------------

func _fake_cfg_ai(ai_count: int) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.ae.a")
	st.map_size = 96
	st.layout_players = 4
	for i: int in ai_count:
		var sl: NetPlayerSlot = st.slots[1 + i]
		sl.kind = NetProtocol.SlotKind.AI
		sl.name = "AI %d" % (2 + i)
		sl.roster_id = "roster.nec.a"
		sl.ready = true
		sl.connected = true
		sl.ai_level = 1
		sl.team = 2
	var ids: PackedStringArray = NetSessionKit.roster_ids()
	var raw: Dictionary = NetMatchConfig.from_lobby(st, 4242, {"game": "0", "proto": 1, "sim": 1, "data_hash": 0, "data_format": 0, "data_ids": 0}, 1_790_000_000, ids)
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))


func test_s12_d1_local_three_ais_6000_ticks_run_double(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var cfg: Dictionary = _fake_cfg_ai(3)
	var ai: Callable = func(pid: int, _l: int, _s: int, rng_seed: int) -> Callable:
		return func(_w: RefCounted, out: Array) -> void: out.append(PackedInt32Array([9, pid, rng_seed & 0xFF]))
	var script: Array = [{"tick": 5, "ints": PackedInt32Array([1, 2, 3])}, {"tick": 700, "ints": PackedInt32Array([4, -5, 262144])},
		{"tick": 3001, "ints": PackedInt32Array([7, 7])}]
	var builder: Callable = func(c: Dictionary) -> NetWorldJob: return NetSessionKit.fake_job(c)
	var a: Dictionary = NetSelfTest.run_double(cfg, builder, script, 6000, ai)
	t.eq(str(a["error"]), "")
	t.check(bool(a["ok"]), str(a))
	t.eq(int(a["compared"]), 300, "compared == 300")
	var b: Dictionary = NetSelfTest.run_double(cfg, builder, script, 6000, ai)
	t.eq(int(b["final_a"]), int(a["final_a"]), "a second identical run gives the same final checksum")
	t.eq(int(b["chain_a"]), int(a["chain_a"]))


## Re-plays a recorded command log (tick = 2 * turn) on a fresh fake world; returns tick -> [checksum, chain].
func _replay_fake(seed_v: int, lg: SimCommandLog, ticks: int) -> Dictionary:
	var w: NetSimAdapterFake = NetSimAdapterFake.new(seed_v)
	var by_tick: Dictionary = {}
	for i: int in lg.cmds.size():
		var tk: int = lg.ticks[i]
		if not by_tick.has(tk):
			by_tick[tk] = {}
		var per: Dictionary = by_tick[tk] as Dictionary
		if not per.has(lg.pids[i]):
			per[lg.pids[i]] = []
		(per[lg.pids[i]] as Array).append(lg.cmds[i])
	var chain: int = 0x811C9DC5
	var out: Dictionary = {}
	for tk: int in ticks:
		if tk % NetProtocol.TURN_TICKS == 0:
			var pids: PackedInt32Array = PackedInt32Array()
			var groups: Array = []
			var per_pid: Dictionary = by_tick.get(tk, {}) as Dictionary
			var keys: Array = per_pid.keys()
			keys.sort()
			for k: Variant in keys:
				pids.append(int(k))
				groups.append(per_pid[k])
				for c: Variant in per_pid[k] as Array:
					w.submit_command(int(k), c as PackedInt32Array)
			chain = NetProtocol.fnv1a32(NetBundle.build(tk / NetProtocol.TURN_TICKS, pids, groups, []).core_bytes(), chain)
		w.step()
		if (tk + 1) % NetProtocol.CHECKSUM_PERIOD_TICKS == 0:
			out[tk + 1] = [w.checksum_at(tk + 1) & 0xFFFFFFFF, chain]
	return out


func test_d2_loopback_peers_equal_the_command_log_replay(t: TestCtx) -> void:
	t.set_timeout(60.0)
	var r: NetScenarioRig = _rig("wifi", {"fixed_delay": 2})
	t.check(r.launch(1), "launched")
	r.run_seconds(40.0)
	var seed_v: int = int((r.host().config()["map"] as Dictionary)["seed"])
	var top: int = mini(_tick_span(r)[0], 780) / 20 * 20
	var replay: Dictionary = _replay_fake(seed_v, r.host().command_log(), top)
	t.ge(replay.size(), 30)
	var bad: int = 0
	for k: Variant in replay:
		for nd: NetScenarioRig.RigPeer in r.nodes:
			var got: Array = nd.checks.get(k, []) as Array
			if got.size() != 2 or int(got[0]) != int((replay[k] as Array)[0]) or int(got[1]) != int((replay[k] as Array)[1]):
				bad += 1
	t.eq(bad, 0, "both live peers equal the replay of the command log at every checksum tick (%d ticks)" % replay.size())
	r.shutdown()
