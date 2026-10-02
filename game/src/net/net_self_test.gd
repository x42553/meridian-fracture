class_name NetSelfTest
extends RefCounted
## Determinism self-test (docs/spec/net.md 3.7, 5.7 "NetSelfTest.run_double"). Only the double run is provided.
##
## (A) runs `ticks` of the match through the LOCAL net pipeline (NetSession.local_from_config: config -> world job ->
## turn host -> lockstep, scripted commands plus the AI when a factory is given) and records every checksum snapshot.
## (B) builds a second world with the same builder and drives it ONLY with the command log A executed, rebuilding the
## bundle stream (so the input chain is re-derived too). Every 20-tick (checksum, chain) pair, the final checksum and the
## hash of dump_state() are compared. A's recording (NetReplayRecorder, the same bytes a .mfreplay file holds) is also played
## through NetReplayPlayer in strict mode: every CHECK, the input chain and the final state must verify, else the run fails with
## `replay_error`. `mode` is "commandlog+replay".

## Result keys: ok, ticks, compared, first_mismatch_tick (-1), chain_a, chain_b, final_a, final_b, state_hash_a,
## state_hash_b, mode, error ("" when the run itself worked), parts (sub-checksum names that differ at the first mismatch),
## replay_ok / replay_compared / replay_error (the NetReplayPlayer verification of A's recording).
##
## script: Array of {tick: int, ints: PackedInt32Array}; the command is submitted by the local player once the world
## reached `tick` (entries for a config without a local human are ignored).
static func run_double(config: Dictionary, world_builder: Callable, script: Array, ticks: int, ai_factory: Callable = Callable()) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "ticks": 0, "compared": 0, "first_mismatch_tick": -1, "chain_a": 0, "chain_b": 0, "final_a": 0, "final_b": 0,
		"state_hash_a": 0, "state_hash_b": 0, "mode": "commandlog+replay", "error": "", "parts": PackedStringArray(),
		"replay_ok": false, "replay_compared": 0, "replay_error": "",
	}
	var clock: NetClock = NetClock.manual(1_000_000)
	var o: NetSessionOptions = NetSessionOptions.new()
	o.world_builder = world_builder
	o.ai_factory = ai_factory
	o.clock = clock
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 2
	o.discovery_enabled = false
	o.record_command_log = true
	var ver: Variant = config.get("versions", null)
	if ver is Dictionary:
		# the double run only compares this build with itself: adopt the versions the config was made with
		o.sim_version = int((ver as Dictionary).get("sim", 0))
		o.data_hash = int((ver as Dictionary).get("data_hash", 0))
	o.log_sink = func(_level: int, _text: String) -> void: pass
	var session: NetSession = NetSession.local_from_config(o, config)
	if session == null:
		out["error"] = NetSession.last_create_error
		return out
	var checks: Array = []
	var wr: WeakRef = weakref(session)
	session.checksum_observer = func(tick: int, cs: int, ch: int) -> void:
		var sess: NetSession = wr.get_ref() as NetSession
		var ad: NetSimAdapter = sess.adapter() if sess != null else null
		checks.append([tick, cs, ch, ad.checksum_parts_at(tick) if ad != null else PackedInt32Array()])
	var done: PackedInt32Array = PackedInt32Array()
	done.resize(script.size())
	var guard: int = 0
	while guard < ticks * 4 + 4000 and session.phase != NetSession.Phase.ENDED:
		guard += 1
		if session.phase == NetSession.Phase.IDLE:
			out["error"] = "the session ended early"
			return out
		var adapter_a: NetSimAdapter = session.adapter()
		if adapter_a != null and adapter_a.current_tick() >= ticks:
			break
		if session.phase == NetSession.Phase.PLAYING and adapter_a != null:
			for i: int in script.size():
				var e: Dictionary = script[i] as Dictionary
				if done[i] == 0 and adapter_a.current_tick() >= int(e.get("tick", 0)):
					done[i] = 1
					session.submit_command(e.get("ints", PackedInt32Array()) as PackedInt32Array)
		clock.advance_us(NetProtocol.TICK_US)
		session.poll()
	var a: NetSimAdapter = session.adapter()
	if a == null:
		out["error"] = "no world was built"
		return out
	var total: int = a.current_tick()
	out["ticks"] = total
	out["final_a"] = a.checksum_now()
	out["state_hash_a"] = NetProtocol.fnv1a32(a.dump_state().to_utf8_buffer())
	out["chain_a"] = session.lockstep.input_chain() if session.lockstep != null else 0
	var cmd_log: SimCommandLog = session.command_log()
	var cfg: Dictionary = session.config()
	session.shutdown()
	var rbytes: PackedByteArray = session.replay_bytes()
	# ---- B: a fresh world driven by the recorded commands
	var job: Variant = world_builder.call(cfg)
	if not (job is NetWorldJob):
		out["error"] = "the world builder returned no job"
		return out
	var guard_b: int = 0
	while not (job as NetWorldJob).step(1_000_000) and guard_b < 100000:
		guard_b += 1
	var b: NetSimAdapter = (job as NetWorldJob).take_adapter()
	if b == null:
		out["error"] = "the second world could not be built"
		return out
	var by_tick: Dictionary = {}
	for i: int in cmd_log.cmds.size():
		var t: int = cmd_log.ticks[i]
		if not by_tick.has(t):
			by_tick[t] = {}
		var per: Dictionary = by_tick[t] as Dictionary
		var pid: int = cmd_log.pids[i]
		if not per.has(pid):
			per[pid] = []
		(per[pid] as Array).append(cmd_log.cmds[i])
	var chain: int = 0x811C9DC5
	var expected: Dictionary = {}
	for c: Variant in checks:
		expected[int((c as Array)[0])] = c
	var compared: int = 0
	var first: int = -1
	var names: PackedStringArray = b.checksum_part_names()
	for t: int in total:
		if t % NetProtocol.TURN_TICKS == 0:
			var pids: PackedInt32Array = PackedInt32Array()
			var groups: Array = []
			var per_pid: Dictionary = by_tick.get(t, {}) as Dictionary
			var keys: Array = per_pid.keys()
			keys.sort()
			for k: Variant in keys:
				pids.append(int(k))
				groups.append(per_pid[k])
				for cmd: Variant in per_pid[k] as Array:
					b.submit_command(int(k), cmd as PackedInt32Array)
			chain = NetProtocol.fnv1a32(NetBundle.build(t / NetProtocol.TURN_TICKS, pids, groups, []).core_bytes(), chain)
		b.step()
		var now_tick: int = t + 1
		if expected.has(now_tick) and now_tick % NetProtocol.CHECKSUM_PERIOD_TICKS == 0:
			compared += 1
			var e2: Array = expected[now_tick] as Array
			if first < 0 and (b.checksum_at(now_tick) != (int(e2[1]) & 0xFFFFFFFF) or chain != (int(e2[2]) & 0xFFFFFFFF)):
				first = now_tick
				var pb: PackedInt32Array = b.checksum_parts_at(now_tick)
				var pa: PackedInt32Array = e2[3] as PackedInt32Array
				var diff: PackedStringArray = PackedStringArray()
				for pi: int in mini(pa.size(), pb.size()):
					if pa[pi] != pb[pi]:
						diff.append(names[pi] if pi < names.size() else "part%d" % pi)
				out["parts"] = diff
	out["compared"] = compared
	out["chain_b"] = chain
	out["final_b"] = b.checksum_now()
	out["state_hash_b"] = NetProtocol.fnv1a32(b.dump_state().to_utf8_buffer())
	out["first_mismatch_tick"] = first
	var final_ok: bool = (int(out["final_a"]) & 0xFFFFFFFF) == (int(out["final_b"]) & 0xFFFFFFFF) and int(out["state_hash_a"]) == int(out["state_hash_b"])
	if first < 0 and not final_ok:
		out["first_mismatch_tick"] = total
	# ---- the same recording through NetReplayPlayer (strict, unpaced)
	var rdata: NetReplayData = NetReplayData.from_bytes(rbytes)
	if rdata == null:
		out["replay_error"] = "the session recorded no replay"
	else:
		var rv: Dictionary = NetReplayPlayer.verify_data(rdata, world_builder)
		out["replay_ok"] = bool(rv["ok"]) and int(rv["final_checksum"]) == (int(out["final_a"]) & 0xFFFFFFFF)
		out["replay_compared"] = int(rv["compared"])
		if not bool(out["replay_ok"]):
			out["replay_error"] = "replay verification failed at tick %d (%s)" % [int(rv["first_mismatch_tick"]), str(rv["error"])]
	out["ok"] = first < 0 and final_ok and bool(out["replay_ok"])
	return out
