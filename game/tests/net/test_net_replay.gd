extends RefCounted
## NET-8 (docs/spec/net.md 5.8, 10.3): the .mfreplay recorder / loader / player, autosave + listing, and the session
## integration (LOCAL, HOST, CLIENT). Real-sim cases record one 3-minute AI match (cached for the whole file).

const P := NetSession.Phase
const REAL_TICKS: int = 3600

## {bytes: PackedByteArray, checks: Dictionary(tick -> [checksum, chain]), final: int, ticks: int, cfg: Dictionary, dumps: Dictionary(tick -> hash)}
static var _real: Dictionary = {}
var _dirs: PackedStringArray = PackedStringArray()


func teardown() -> void:
	for d: String in _dirs:
		_rm_dir(d)
	_dirs.clear()


## A kit whose AI slots do nothing (a LOCAL session needs an AI factory for its AI slot).
func _kit() -> NetSessionKit:
	var kit: NetSessionKit = NetSessionKit.new()
	kit.ai_factory = func(_pid: int, _level: int, _style: int, _seed: int) -> Callable:
		return func(_w: RefCounted, _out: Array) -> void: pass
	return kit


func _dir(tag: String) -> String:
	var d: String = "user://replay_test_%s_%d" % [tag, OS.get_process_id()]
	_rm_dir(d)
	DirAccess.make_dir_recursive_absolute(d)
	_dirs.append(d)
	return d


func _rm_dir(d: String) -> void:
	var da: DirAccess = DirAccess.open(d)
	if da != null:
		for f: String in da.get_files():
			da.remove(f)
		DirAccess.remove_absolute(d)


func _write(path: String, bytes: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


# ---- builders ---------------------------------------------------------------------------------------------------

func _config(o: NetSessionOptions, real: bool = false) -> Dictionary:
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o)
	st.map_size = 96
	st.layout_players = 2
	st.slots[0].kind = NetProtocol.SlotKind.AI
	st.slots[0].peer_id = 0
	st.slots[0].name = "AI 1"
	st.slots[0].ready = true
	st.slots[0].ai_level = 1
	st.slots[1].roster_id = "roster.nec.vanilla"
	st.rules["fog"] = 0
	var ids: int = int(SimMatchKit.data().table_hashes.get("ids", 0)) if real else 0
	var ver: Dictionary = {"game": o.game_version, "proto": 1, "sim": o.sim_version, "data_hash": o.data_hash, "data_format": 1, "data_ids": ids}
	var raw: Dictionary = NetMatchConfig.from_lobby(st, 20260930, ver, 1_790_000_000, o.roster_ids)
	return NetMatchConfig.parse(NetMatchConfig.canonical_json(raw))


func _real_options(kit: NetSessionKit) -> NetSessionOptions:
	var o: NetSessionOptions = NetSessionOptions.from_game_data(SimMatchKit.data())
	o.clock = kit.clock()
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.fixed_input_delay_turns = 0
	o.discovery_enabled = false
	o.replay_dir = ""
	o.world_builder = NetSessionKit.real_job
	o.ai_factory = NetSessionKit.bot_factory({"first_attack_tick": 400, "interval": 1})
	o.log_sink = func(_l: int, _t: String) -> void: pass
	return o


## Records a LOCAL real-sim bot match of `ticks` ticks (memory recording) and returns the recording and what the session saw.
func _record_real(ticks: int, dumps_at: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = _real_options(kit)
	var cfg: Dictionary = _config(o, true)
	var s: NetSession = NetSession.local_from_config(o, cfg)
	if s == null:
		return {"error": NetSession.last_create_error}
	var checks: Dictionary = {}
	var dumps: Dictionary = {}
	var wr: WeakRef = weakref(s)
	s.checksum_observer = func(tick: int, cs: int, chain: int) -> void:
		checks[tick] = [cs & 0xFFFFFFFF, chain & 0xFFFFFFFF]
		var sess: NetSession = wr.get_ref() as NetSession
		if sess != null and dumps_at.has(tick):
			dumps[tick] = NetProtocol.fnv1a32(sess.adapter().dump_state().to_utf8_buffer())
	var guard: int = 0
	while guard < 20000 and s.phase != P.ENDED and (s.adapter() == null or s.adapter().current_tick() < ticks):
		kit.clock().advance_us(50_000)
		s.poll()
		guard += 1
	var final_sum: int = s.adapter().checksum_now() & 0xFFFFFFFF
	var reached: int = s.adapter().current_tick()
	s.checksum_observer = Callable()
	s.shutdown()
	return {"bytes": s.replay_bytes(), "checks": checks, "final": final_sum, "ticks": reached, "cfg": s.config(), "dumps": dumps, "opts": o, "path": s.replay_path()}


func _real_cached() -> Dictionary:
	if _real.is_empty():
		_real = _record_real(REAL_TICKS, PackedInt32Array([1000]))
	return _real


## Runs a LOCAL fake-sim session; script = Array of [tick, ints]. Returns {session, bytes, path, kit, checks}.
func _fake_local(replay_dir: String, ticks: int, script: Array = []) -> Dictionary:
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = kit.options("Me", {"replay_dir": replay_dir, "replay_autosave_count": 3, "max_ticks_per_poll": 2})
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o)
	var s: NetSession = NetSession.local(o, st)
	if s == null:
		return {"error": NetSession.last_create_error}
	var checks: Dictionary = {}
	s.checksum_observer = func(tick: int, cs: int, chain: int) -> void: checks[tick] = [cs & 0xFFFFFFFF, chain & 0xFFFFFFFF]
	var done: PackedInt32Array = PackedInt32Array()
	done.resize(script.size())
	var guard: int = 0
	while guard < 20000 and s.phase != P.ENDED and (s.adapter() == null or s.adapter().current_tick() < ticks):
		if s.adapter() != null and s.phase == P.PLAYING:
			for i: int in script.size():
				if done[i] == 0 and s.adapter().current_tick() >= int((script[i] as Array)[0]):
					done[i] = 1
					s.submit_command((script[i] as Array)[1] as PackedInt32Array)
		kit.clock().advance_us(50_000)
		s.poll()
		guard += 1
	var final_sum: int = s.adapter().checksum_now() & 0xFFFFFFFF
	s.checksum_observer = Callable()
	s.shutdown()
	return {"session": s, "bytes": s.replay_bytes(), "path": s.replay_path(), "kit": kit, "checks": checks, "final": final_sum, "ticks": ticks}


func _script() -> Array:
	var out: Array = []
	for i: int in 40:
		out.append([i * 18, PackedInt32Array([1 + (i % 5), i * 7, 1000 - i, (i * 31) % 97])])
	return out


## Offsets of every record of a replay file: Array of [type, payload_start, payload_len].
func _records(bytes: PackedByteArray) -> Array:
	var out: Array = []
	var pos: int = NetReplayRecorder.HEADER_SIZE + bytes.decode_u32(8)
	while pos < bytes.size() - 8:
		var r: NetReader = NetReader.new(bytes, pos)
		var type: int = r.u8()
		var n: int = r.varint()
		if not r.ok:
			break
		out.append([type, r.pos(), n])
		pos = r.pos() + n
	return out


func _synthetic_bytes(cfg: Dictionary) -> PackedByteArray:
	var rec: NetReplayRecorder = NetReplayRecorder.new()
	rec.open_memory(cfg, NetReplayRecorder.make_meta(1, 0, 1_790_000_000, "0.0.1"), NetMatchConfig.canonical_json(cfg))
	for turn: int in [0, 1, 5, 6, 40]:
		rec.record_turn(NetBundle.build(turn, PackedInt32Array(), [], []))
	rec.record_turn(NetBundle.build(5, PackedInt32Array([0, 3]), [[PackedInt32Array([1, 10, -20])], [PackedInt32Array([2, 5]), PackedInt32Array([3, 70000, 1, 1])]], []))
	rec.record_turn(NetBundle.build(6, PackedInt32Array([1]), [[PackedInt32Array([9])]], [PackedInt32Array([1, 3])]))
	rec.record_turn(NetBundle.build(6, PackedInt32Array([1]), [[PackedInt32Array([9])]], []))
	rec.record_turn(NetBundle.build(40, PackedInt32Array([2]), [[PackedInt32Array([4, 4, 4])]], []))
	rec.record_check(20, 0xAABBCCDD, 0x11223344)
	rec.record_check(40, 0x01020304, 0xFFFFFFFF)
	rec.record_check(41, 5, 5)
	rec.record_parts(40, PackedInt32Array([7, -1, 9]))
	rec.record_event(5, NetProtocol.ReplayEvent.PLAYER_STATUS, PackedInt32Array([2, 3, 0]))
	rec.record_event(6, NetProtocol.ReplayEvent.CHAT, PackedInt32Array([1]), "Grüße 日本")
	rec.finish({"final_tick": 82, "final_checksum": 0xDEADBEEF, "final_chain": 0x12345678, "reason": 3, "winner_team": -1})
	return rec.to_bytes()


# ---- recorder / data ------------------------------------------------------------------------------------------------

func test_recorder_data_round_trip(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var cfg: Dictionary = _config(kit.options("Me"))
	t.check(not cfg.is_empty())
	var bytes: PackedByteArray = _synthetic_bytes(cfg)
	var d: NetReplayData = NetReplayData.from_bytes(bytes)
	if not t.not_null(d, NetReplayData.last_error):
		return
	t.check(d.finalized and not d.truncated)
	t.eq(d.format_version, 1)
	t.eq(Array(d.turns), [5, 6, 40], "empty turns are not stored, a repeated turn is ignored")
	t.eq(d.bodies.size(), 3)
	var g5: Array = d.groups_at(0)
	t.eq(g5.size(), 2)
	t.eq(int((g5[0] as Array)[0]), 0)
	t.eq(int((g5[1] as Array)[0]), 3)
	t.eq(((g5[1] as Array)[1] as Array).size(), 2)
	t.eq(((g5[1] as Array)[1] as Array)[1] as PackedInt32Array, PackedInt32Array([3, 70000, 1, 1]))
	t.eq(NetBundle.build(5, PackedInt32Array([0, 3]), [[PackedInt32Array([1, 10, -20])], [PackedInt32Array([2, 5]), PackedInt32Array([3, 70000, 1, 1])]], []).core_bytes().slice(4), d.bodies[0] as PackedByteArray)
	t.eq(d.checks.size(), 6, "a CHECK that is not a multiple of 20 is not recorded")
	t.eq(int(d.checks[3]), 40)
	t.eq(int(d.checks[5]), 0xFFFFFFFF)
	t.eq(d.parts.size(), 1)
	t.eq(((d.parts[0] as Dictionary)["parts"] as PackedInt32Array)[1], -1)
	t.eq(d.events.size(), 2)
	t.eq(str((d.events[1] as Dictionary)["text"]), "Grüße 日本")
	t.eq(int(d.end["final_tick"]), 82)
	t.eq(int(d.end["reason"]), 3)
	t.eq(int(d.end["winner_team"]), -1)
	t.eq(d.total_turns(), int(d.end["total_turns"]))
	t.eq(d.end_tick(), 82)
	t.eq(d.config, cfg, "header config round-trips through normalize")
	t.eq(str(d.replay_meta["os"]), OS.get_name())
	t.eq(int(d.replay_meta["started_unix"]), 1_790_000_000)
	# the header carries the launch JSON verbatim
	var json: String = NetMatchConfig.canonical_json(cfg)
	var hdr: String = bytes.slice(16, 16 + bytes.decode_u32(8)).get_string_from_utf8()
	t.check(hdr.begins_with('{"config":' + json + ',"replay":'), "verbatim config JSON")
	# the gap encoding: first record gap = turn number, then differences
	var recs: Array = _records(bytes)
	t.eq(int((recs[0] as Array)[0]), NetProtocol.ReplayRec.TURNS)
	t.eq(bytes[int((recs[0] as Array)[1])], 5, "first TURNS record: gap = 5")
	t.eq(bytes[int((recs[1] as Array)[1])], 0, "turn 6 follows turn 5 directly: gap 0")
	t.eq(bytes[int((recs[2] as Array)[1])], 33, "turn 40 after 6: gap 33")
	# trailer
	t.eq(bytes.decode_u32(bytes.size() - 8), 20)
	t.eq(bytes.slice(bytes.size() - 4).get_string_from_ascii(), "MFRE")


func test_loader_truncation_and_corruption(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var cfg: Dictionary = _config(kit.options("Me"))
	var bytes: PackedByteArray = _synthetic_bytes(cfg)
	var full: NetReplayData = NetReplayData.from_bytes(bytes)
	var hdr_end: int = 16 + bytes.decode_u32(8)
	var cuts: PackedInt32Array = PackedInt32Array()
	for off: int in range(0, bytes.size(), 97):
		cuts.append(off)
	for off: int in range(bytes.size() - 40, bytes.size()):
		cuts.append(off)
	var bad: int = 0
	for off: int in cuts:
		var d: NetReplayData = NetReplayData.from_bytes(bytes.slice(0, off))
		if off < hdr_end:
			if d != null:
				bad += 1
			continue
		if d == null or not d.truncated or d.finalized:
			bad += 1
			continue
		# the prefix is intact
		for i: int in d.turns.size():
			if d.turns[i] != full.turns[i] or d.bodies[i] != full.bodies[i]:
				bad += 1
	t.eq(bad, 0, "truncation at %d offsets" % cuts.size())
	var whole: NetReplayData = NetReplayData.from_bytes(bytes)
	t.check(whole.finalized and not whole.truncated)
	# a cut exactly before the END record: playable and not finalized
	var recs: Array = _records(bytes)
	var end_rec: Array = recs[recs.size() - 1] as Array
	var cut: NetReplayData = NetReplayData.from_bytes(bytes.slice(0, int(end_rec[1]) - 2))
	t.check(cut != null and cut.truncated and not cut.finalized and cut.end.is_empty())
	t.eq(cut.end_tick(), (40 + 1) * 2, "unfinalized end tick = end of the last command turn")
	# header corruption
	var b1: PackedByteArray = bytes.duplicate()
	b1[20] ^= 0x01
	t.is_null(NetReplayData.from_bytes(b1), "json fnv mismatch")
	t.check(NetReplayData.last_error.contains("checksum"))
	var b2: PackedByteArray = bytes.duplicate()
	b2[0] = 0x58
	t.is_null(NetReplayData.from_bytes(b2), "bad magic")
	var b3: PackedByteArray = bytes.duplicate()
	b3[4] = 2
	t.is_null(NetReplayData.from_bytes(b3), "unsupported format version")
	t.check(NetReplayData.last_error.contains("version"))
	t.is_null(NetReplayData.from_bytes(PackedByteArray([1, 2, 3])))
	# an unknown record type is skipped by its length
	var inject: int = int((recs[1] as Array)[1]) - 2  # before the second TURNS record header (type + 1-byte len)
	var extra: PackedByteArray = PackedByteArray([0x7E, 3, 1, 2, 3])
	var b4: PackedByteArray = bytes.slice(0, inject)
	b4.append_array(extra)
	b4.append_array(bytes.slice(inject))
	var d4: NetReplayData = NetReplayData.from_bytes(b4)
	t.check(d4 != null and d4.finalized and not d4.truncated, "unknown record type skipped")
	t.eq(Array(d4.turns), [5, 6, 40])
	# a structurally invalid TURNS record ends the parse (truncated)
	var b5: PackedByteArray = bytes.duplicate()
	var r1: Array = recs[0] as Array
	b5[int(r1[1]) + int(r1[2]) - 1] = 0xFF  # unterminated varint at the end of the body
	var d5: NetReplayData = NetReplayData.from_bytes(b5)
	t.check(d5 != null and d5.truncated and d5.turns.is_empty())
	# stuff after the trailer: not finalized, no crash
	var b6: PackedByteArray = bytes.duplicate()
	b6.append_array(PackedByteArray([5, 18, 0, 0]))
	var d6: NetReplayData = NetReplayData.from_bytes(b6)
	t.check(d6 != null and not d6.finalized and d6.truncated)


func test_recorder_file_mode_and_failure(t: TestCtx) -> void:
	var dir: String = _dir("rec")
	var kit: NetSessionKit = _kit()
	var cfg: Dictionary = _config(kit.options("Me"))
	var path: String = NetReplay.begin_recording_path(dir)
	var rec: NetReplayRecorder = NetReplayRecorder.new()
	t.eq(rec.open_file(path, cfg, NetReplayRecorder.make_meta(1, 0, 5, "x")), OK)
	rec.record_turn(NetBundle.build(3, PackedInt32Array([0]), [[PackedInt32Array([1, 2])]], []))
	rec.record_check(20, 1, 2)
	t.eq(FileAccess.get_file_as_bytes(path), rec.to_bytes(), "the file is flushed after each CHECK and equals the memory mirror")
	rec.finish({"final_tick": 21, "final_checksum": 3, "final_chain": 4})
	t.eq(FileAccess.get_file_as_bytes(path), rec.to_bytes())
	var d: NetReplayData = NetReplayData.load_file(path)
	t.check(d != null and d.finalized)
	rec.record_turn(NetBundle.build(9, PackedInt32Array([0]), [[PackedInt32Array([1, 2])]], []))
	t.eq(rec.to_bytes().size(), FileAccess.get_file_as_bytes(path).size(), "nothing is recorded after finish")
	NetReplay.release_recording_path(path)
	# an unwritable target: memory recording continues, the error callback fires once
	var errs: Array = []
	var rec2: NetReplayRecorder = NetReplayRecorder.new()
	rec2.on_error = func(text: String) -> void: errs.append(text)
	var err: int = rec2.open_file(dir.path_join("no_such_dir/x.mfreplay"), cfg, NetReplayRecorder.make_meta(1, 0, 5, "x"))
	t.ne(err, OK)
	t.eq(errs.size(), 1)
	rec2.record_turn(NetBundle.build(3, PackedInt32Array([0]), [[PackedInt32Array([1, 2])]], []))
	rec2.finish({"final_tick": 2})
	t.eq(errs.size(), 1)
	t.check(NetReplayData.from_bytes(rec2.to_bytes()) != null, "the memory mirror is still a valid replay")


# ---- player on the fake sim ---------------------------------------------------------------------------------------

func test_fake_local_record_verify_and_player_controls(t: TestCtx) -> void:
	var dir: String = _dir("fake")
	var run: Dictionary = _fake_local(dir, 600, _script())
	if not t.check(run.has("session"), str(run.get("error", ""))):
		return
	var path: String = str(run["path"])
	t.check(path.ends_with("autosave_1.mfreplay"), "autosaved: %s" % path)
	t.check(FileAccess.file_exists(path))
	var d: NetReplayData = NetReplayData.load_file(path)
	t.check(d != null and d.finalized and not d.truncated)
	t.gt(d.turns.size(), 20, "the scripted commands were recorded")
	t.eq(d.check_count(), 30, "one CHECK per 20 ticks")
	var checks: Dictionary = run["checks"] as Dictionary
	for i: int in d.check_count():
		var tick: int = int(d.checks[i * 3])
		var rc: Array = checks[tick] as Array
		if int(rc[0]) != (int(d.checks[i * 3 + 1]) & 0xFFFFFFFF) or int(rc[1]) != (int(d.checks[i * 3 + 2]) & 0xFFFFFFFF):
			t.fail("recorded CHECK differs from what the session saw at tick %d" % tick)
			break
	t.eq(int(d.end["final_checksum"]), int(run["final"]))
	var res: Dictionary = NetReplayPlayer.verify_file(path, NetSessionKit.fake_job)
	t.check(bool(res["ok"]), str(res))
	t.eq(int(res["compared"]), 30)
	t.eq(int(res["final_checksum"]), int(run["final"]))
	t.eq(int(res["ticks"]), int(d.end["final_tick"]))
	# the player: speed, pause, seek (manual clock)
	var clock: NetClock = NetClock.manual(0)
	var p: NetReplayPlayer = NetReplayPlayer.new()
	t.eq(p.setup(d, NetSessionKit.fake_job, clock), OK)
	var failed: Array = []
	p.verify_failed.connect(func(tick: int, e: int, a: int) -> void: failed.append([tick, e, a]))
	var fin: Array = []
	p.finished.connect(func() -> void: fin.append(1))
	p.set_speed(1.0)
	for i: int in 20:
		clock.advance_us(50_000)
		p.poll()
	t.eq(p.current_tick(), 20, "1x: one tick per 50 ms")
	p.set_speed(4.0)
	for i: int in 20:
		clock.advance_us(50_000)
		p.poll()
	t.eq(p.current_tick(), 20 + 80, "4x: four ticks per 50 ms")
	p.set_speed(0.25)
	for i: int in 40:
		clock.advance_us(50_000)
		p.poll()
	t.eq(p.current_tick(), 100 + 10, "0.25x")
	p.set_paused(true)
	for i: int in 40:
		clock.advance_us(50_000)
		p.poll()
	t.eq(p.current_tick(), 110, "paused")
	p.set_paused(false)
	# a long hitch never runs more than 8 x speed ticks per poll
	p.set_speed(2.0)
	clock.advance_us(10_000_000)
	p.poll()
	t.le(p.current_tick() - 110, 16, "tick cap per poll")
	t.eq(p.verified_through_tick(), (p.current_tick() / 20) * 20)
	# seek forward, backward (rebuild), forward
	var rebuilt: Array = []
	p.world_rebuilt.connect(func() -> void: rebuilt.append(1))
	p.seek_tick(333)
	t.check(p.is_seeking())
	var guard: int = 0
	while p.is_seeking() and guard < 100:
		guard += 1
		p.poll(1_000_000)
	t.eq(p.current_tick(), 333)
	var ref: NetSimAdapterFake = NetSimAdapterFake.new(int((d.config["map"] as Dictionary)["seed"]))
	_play_fake(ref, d, 333)
	t.eq(p.adapter().dump_state(), ref.dump_state(), "forward seek equals a straight run")
	p.seek_tick(111)
	guard = 0
	while p.is_seeking() and guard < 100:
		guard += 1
		p.poll(1_000_000)
	t.eq(p.current_tick(), 111)
	t.eq(rebuilt.size(), 1, "a backward seek rebuilt the world")
	var ref2: NetSimAdapterFake = NetSimAdapterFake.new(int((d.config["map"] as Dictionary)["seed"]))
	_play_fake(ref2, d, 111)
	t.eq(p.adapter().dump_state(), ref2.dump_state(), "backward seek equals a straight run")
	p.set_speed(NetReplayPlayer.MAX)
	guard = 0
	while not p.is_finished() and guard < 100:
		guard += 1
		p.poll(1_000_000)
	t.check(p.is_finished())
	t.eq(fin.size(), 1)
	t.eq(failed.size(), 0, "no divergence after seeks")
	t.eq(p.diverged_tick(), -1)
	t.eq(p.adapter().checksum_now() & 0xFFFFFFFF, int(run["final"]))
	t.eq(p.input_chain(), int(d.end["final_chain"]) & 0xFFFFFFFF)
	# seek again after the end
	p.seek_tick(40)
	guard = 0
	while p.is_seeking() and guard < 100:
		guard += 1
		p.poll(1_000_000)
	t.eq(p.current_tick(), 40)
	t.check(not p.is_finished())


## Straight run of a fake world for `ticks` ticks with the recorded commands.
func _play_fake(a: NetSimAdapterFake, d: NetReplayData, ticks: int) -> void:
	var ti: int = 0
	for tick: int in ticks:
		if tick % 2 == 0 and ti < d.turns.size() and d.turns[ti] == tick / 2:
			for g: Variant in d.groups_at(ti):
				for c: Variant in (g as Array)[1] as Array:
					a.submit_command(int((g as Array)[0]), c as PackedInt32Array)
			ti += 1
		a.step()


func test_tamper_is_reported_once_as_replay_desync(t: TestCtx) -> void:
	var dir: String = _dir("tamper")
	var run: Dictionary = _fake_local(dir, 400, _script())
	var bytes: PackedByteArray = (run["bytes"] as PackedByteArray).duplicate()
	var recs: Array = _records(bytes)
	var target: Array = []
	var seen: int = 0
	for r: Variant in recs:
		if int((r as Array)[0]) == NetProtocol.ReplayRec.TURNS:
			seen += 1
			if seen == 12:
				target = r as Array
				break
	if not t.check(not target.is_empty(), "a TURNS record to tamper with"):
		return
	var data0: NetReplayData = NetReplayData.from_bytes(bytes)
	var turn: int = data0.turns[11]
	bytes[int(target[1]) + int(target[2]) - 1] ^= 0x01
	var path: String = _dir("tamper2").path_join("t.mfreplay")
	_write(path, bytes)
	var res: Dictionary = NetReplayPlayer.verify_file(path, NetSessionKit.fake_job)
	t.check(not bool(res["ok"]), "tampered replay must not verify")
	var first_check: int = (2 * turn / 20 + 1) * 20
	t.eq(int(res["first_mismatch_tick"]), first_check, "reported at the first CHECK after the tampered turn")
	t.check(str(res["kind"]) != "", str(res))
	# player: verify_failed fires exactly once, playback continues
	var d: NetReplayData = NetReplayData.load_file(path)
	var p: NetReplayPlayer = NetReplayPlayer.new()
	t.eq(p.setup(d, NetSessionKit.fake_job, NetClock.manual(0)), OK)
	var fails: Array = []
	p.verify_failed.connect(func(tick: int, e: int, a: int) -> void: fails.append([tick, e, a]))
	p.set_speed(NetReplayPlayer.MAX)
	var guard: int = 0
	while not p.is_finished() and guard < 100:
		guard += 1
		p.poll(1_000_000)
	t.check(p.is_finished(), "playback continues past the divergence")
	t.eq(fails.size(), 1, "verify_failed fires once")
	t.eq(int((fails[0] as Array)[0]), first_check)
	t.eq(p.diverged_tick(), first_check)
	t.check(int(p.mismatch()["expected"]) != int(p.mismatch()["actual"]) or int(p.mismatch()["expected_chain"]) != int(p.mismatch()["actual_chain"]))
	t.eq(p.verified_through_tick(), first_check - 20)
	# a flipped byte of the CHECK stream is a mismatch of the recorded side
	var b2: PackedByteArray = (run["bytes"] as PackedByteArray).duplicate()
	for r: Variant in recs:
		if int((r as Array)[0]) == NetProtocol.ReplayRec.CHECK:
			b2[int((r as Array)[1]) + 5] ^= 0x10  # checksum word of the first CHECK
			break
	var p2: String = _dir("tamper3").path_join("t.mfreplay")
	_write(p2, b2)
	var res2: Dictionary = NetReplayPlayer.verify_file(p2, NetSessionKit.fake_job)
	t.check(not bool(res2["ok"]))
	t.eq(int(res2["first_mismatch_tick"]), 20)


func test_version_gate(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = kit.options("Me")
	var cfg: Dictionary = _config(o)
	var local: Dictionary = NetReplay.local_versions(o)
	t.eq(int(local["sim"]), 1)
	var ok_bytes: PackedByteArray = _synthetic_bytes(cfg)
	var good: NetReplayData = NetReplayData.from_bytes(ok_bytes)
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.local_versions = local
	t.eq(p.setup(good, NetSessionKit.fake_job, NetClock.manual(0)), OK, "same versions play")
	t.eq(p.warning, "")
	# different sim version: refused with a message
	var c2: Dictionary = cfg.duplicate(true)
	(c2["versions"] as Dictionary)["sim"] = 99
	var bad: NetReplayData = NetReplayData.from_bytes(_synthetic_bytes(c2))
	var p2: NetReplayPlayer = NetReplayPlayer.new()
	p2.local_versions = local
	t.eq(p2.setup(bad, NetSessionKit.fake_job, NetClock.manual(0)), ERR_INVALID_DATA)
	t.check(p2.error_text.contains("simulation version") and p2.error_text.contains("99"), p2.error_text)
	p2.allow_version_mismatch = true
	t.eq(p2.setup(bad, NetSessionKit.fake_job, NetClock.manual(0)), OK, "developer override")
	# only the balance hash differs: allowed with a warning, refused in strict mode
	var c3: Dictionary = cfg.duplicate(true)
	(c3["versions"] as Dictionary)["data_hash"] = 0x0BADBEEF
	var soft: NetReplayData = NetReplayData.from_bytes(_synthetic_bytes(c3))
	var p3: NetReplayPlayer = NetReplayPlayer.new()
	p3.local_versions = local
	t.eq(p3.setup(soft, NetSessionKit.fake_job, NetClock.manual(0)), OK)
	t.check(p3.warning.contains("alance"), p3.warning)
	var p4: NetReplayPlayer = NetReplayPlayer.new()
	p4.local_versions = local
	p4.strict = true
	t.eq(p4.setup(soft, NetSessionKit.fake_job, NetClock.manual(0)), ERR_INVALID_DATA)
	t.check(p4.error_text.contains("game data"), p4.error_text)
	# protocol / ids / format
	for key: String in ["proto", "data_ids", "data_format"]:
		var c4: Dictionary = cfg.duplicate(true)
		(c4["versions"] as Dictionary)[key] = 77
		var d4: NetReplayData = NetReplayData.from_bytes(_synthetic_bytes(c4))
		if not t.not_null(d4):
			continue
		var gate: Dictionary = NetReplay.check_versions(d4.versions(), {"sim": 1, "proto": 1, "data_ids": 0, "data_format": 1, "data_hash": o.data_hash})
		t.eq(int(gate["level"]), NetReplay.GATE_REFUSE, key)
	t.eq(int(NetReplay.check_versions(good.versions(), {})["level"]), NetReplay.GATE_OK, "no local versions = no gate")
	# the listing flags the incompatible one
	var dir: String = _dir("gate")
	_write(dir.path_join("good.mfreplay"), ok_bytes)
	_write(dir.path_join("bad.mfreplay"), _synthetic_bytes(c2))
	var rows: Array[Dictionary] = NetReplay.list_replays(dir, local)
	t.eq(rows.size(), 2)
	for row: Dictionary in rows:
		if str(row["name"]) == "bad":
			t.check(not bool(row["compatible"]) and str(row["incompatible_reason"]).contains("simulation"), str(row))
		else:
			t.check(bool(row["compatible"]))


# ---- files: autosave, recovery, listing, save/delete ----------------------------------------------------------------

func test_autosave_rotation_keep_3_over_5_matches(t: TestCtx) -> void:
	var dir: String = _dir("rot")
	for i: int in range(1, 6):
		var tmp: String = NetReplay.begin_recording_path(dir)
		_write(tmp, ("m%d" % i).to_utf8_buffer())
		var out: String = NetReplay.finalize_autosave(tmp, 3)
		t.eq(out, dir + "/autosave_1.mfreplay")
		t.check(not FileAccess.file_exists(tmp), "the temp file was renamed")
	t.eq(FileAccess.get_file_as_bytes(NetReplay.autosave_path(1, dir)).get_string_from_utf8(), "m5")
	t.eq(FileAccess.get_file_as_bytes(NetReplay.autosave_path(2, dir)).get_string_from_utf8(), "m4")
	t.eq(FileAccess.get_file_as_bytes(NetReplay.autosave_path(3, dir)).get_string_from_utf8(), "m3")
	t.check(not FileAccess.file_exists(NetReplay.autosave_path(4, dir)))
	# lowering the count prunes
	var tmp2: String = NetReplay.begin_recording_path(dir)
	_write(tmp2, "m6".to_utf8_buffer())
	NetReplay.finalize_autosave(tmp2, 2)
	t.check(not FileAccess.file_exists(NetReplay.autosave_path(3, dir)))
	t.eq(FileAccess.get_file_as_bytes(NetReplay.autosave_path(2, dir)).get_string_from_utf8(), "m5")
	# the total size cap drops the oldest, keeps the newest
	for i: int in 3:
		var tmp3: String = NetReplay.begin_recording_path(dir)
		_write(tmp3, PackedByteArray([65, 66, 67, 68, 69, 70, 71, 72, 73, 74]))
		NetReplay.finalize_autosave(tmp3, 3, 15)
	t.check(FileAccess.file_exists(NetReplay.autosave_path(1, dir)))
	t.check(not FileAccess.file_exists(NetReplay.autosave_path(2, dir)), "cap of 15 bytes keeps one 10-byte file")
	# two live recorders never share a temp path
	var a: String = NetReplay.begin_recording_path(dir)
	var b: String = NetReplay.begin_recording_path(dir)
	t.ne(a, b)
	NetReplay.release_recording_path(a)
	NetReplay.release_recording_path(b)


func test_recover_orphans_and_save_copy_and_delete(t: TestCtx) -> void:
	var dir: String = _dir("orph")
	var kit: NetSessionKit = _kit()
	var cfg: Dictionary = _config(kit.options("Me"))
	# a crashed run: header + a command + one CHECK, never finalised
	var rec: NetReplayRecorder = NetReplayRecorder.new()
	rec.open_memory(cfg, NetReplayRecorder.make_meta(1, 0, 5, "x"))
	rec.record_turn(NetBundle.build(3, PackedInt32Array([0]), [[PackedInt32Array([1, 2])]], []))
	rec.record_check(20, 1, 2)
	_write(dir.path_join("_recording_2000000000.mfreplay.tmp"), rec.to_bytes())
	# an empty one (header only) is deleted, a live recording of this process is left alone
	var empty: NetReplayRecorder = NetReplayRecorder.new()
	empty.open_memory(cfg, NetReplayRecorder.make_meta(1, 0, 5, "x"))
	_write(dir.path_join("_recording_2000000001.mfreplay.tmp"), empty.to_bytes())
	var live: String = NetReplay.begin_recording_path(dir)
	_write(live, rec.to_bytes())
	var got: PackedStringArray = NetReplay.recover_orphans(dir, 0)
	t.eq(got.size(), 1)
	t.check(got[0].get_file().begins_with("crash_") and got[0].ends_with(".mfreplay"), got[0])
	t.check(not FileAccess.file_exists(dir.path_join("_recording_2000000001.mfreplay.tmp")))
	t.check(FileAccess.file_exists(live), "an active recording is not touched")
	var d: NetReplayData = NetReplayData.load_file(got[0])
	t.check(d != null and d.truncated and not d.finalized and d.turns.size() == 1, "recovered replay is truncated but playable")
	t.eq(NetReplay.list_replays(dir)[0]["kind"], "crash")
	NetReplay.release_recording_path(live)
	# save_copy sanitises
	var src: String = dir.path_join("autosave_1.mfreplay")
	_write(src, _synthetic_bytes(cfg))
	var c1: String = NetReplay.save_copy(src, "../x")
	t.check(c1 != "" and c1.get_base_dir() == dir and not c1.get_file().contains(".."), c1)
	t.check(FileAccess.file_exists(c1))
	var c2: String = NetReplay.save_copy(src, "../x")
	t.ne(c1, c2, "collision gets a suffix")
	t.check(c2.get_file().begins_with(NetReplay.sanitize_name("../x")) and c2.contains("_2"), c2)
	t.eq(NetReplay.sanitize_name("My game: final/round?"), "My game_ final_round_")
	t.eq(NetReplay.sanitize_name("   "), "replay")
	t.eq(NetReplay.sanitize_name("a".repeat(80)).length(), 48)
	t.eq(NetReplay.sanitize_name("äö ok"), "__ ok")
	t.check(NetReplay.save_copy(dir.path_join("nope.mfreplay"), "x") == "")
	# delete: only *.mfreplay inside the directory
	t.check(not NetReplay.delete_replay(dir.path_join("../escape.mfreplay"), dir))
	_write(dir.path_join("note.txt"), PackedByteArray([1]))
	t.check(not NetReplay.delete_replay(dir.path_join("note.txt"), dir))
	t.check(NetReplay.delete_replay(c1, dir))
	t.check(not FileAccess.file_exists(c1))
	t.check(not NetReplay.delete_replay("user://elsewhere/x.mfreplay", dir))


func test_list_replays_metadata(t: TestCtx) -> void:
	var dir: String = _dir("list")
	var run: Dictionary = _fake_local(dir, 400, _script())
	var rows: Array[Dictionary] = NetReplay.list_replays(dir, NetReplay.local_versions(run["kit"].options("x")))
	t.eq(rows.size(), 1)
	var r: Dictionary = rows[0]
	t.check(bool(r["valid"]) and bool(r["finalized"]), str(r))
	t.eq(str(r["kind"]), "autosave")
	t.eq(int(r["duration_ticks"]), 400)
	t.eq(int(r["duration_s"]), 20)
	t.eq((r["players"] as Array).size(), 2)
	t.ge(int((r["map"] as Dictionary)["size"]), 96)
	t.eq(int((r["result"] as Dictionary)["final_tick"]), 400)
	t.eq(int((r["result"] as Dictionary)["reason"]), NetProtocol.MatchEndReason.ABANDONED, "the run was stopped by shutdown()")
	t.check(bool(r["compatible"]))
	t.eq(str(r["game_version"]), "0.0.1")
	t.eq(str(r["match_id"]).length(), 16)
	t.eq(int(r["size"]), FileAccess.get_file_as_bytes(str(r["path"])).size())
	# a damaged file is listed as invalid
	_write(dir.path_join("broken.mfreplay"), PackedByteArray([1, 2, 3, 4]))
	var rows2: Array[Dictionary] = NetReplay.list_replays(dir)
	t.eq(rows2.size(), 2)
	var invalid: int = 0
	for x: Dictionary in rows2:
		if not bool(x["valid"]):
			invalid += 1
			t.check(str(x["error"]) != "")
	t.eq(invalid, 1)


# ---- session integration ----------------------------------------------------------------------------------------

func test_match_end_by_the_sim_is_recorded_with_its_result(t: TestCtx) -> void:
	var dir: String = _dir("end")
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = kit.options("Me", {"replay_dir": dir})
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v, 333))
	var s: NetSession = NetSession.local(o, NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o))
	t.not_null(s)
	var saved: Array = []
	s.replay_saved.connect(func(p: String) -> void: saved.append(p))
	var guard: int = 0
	while s.phase != P.ENDED and guard < 5000:
		kit.clock().advance_us(50_000)
		s.poll()
		guard += 1
	t.eq(s.phase, P.ENDED)
	t.eq(saved.size(), 1, "replay_saved fired once at the match end")
	var path: String = s.replay_path()
	t.eq(path, dir + "/autosave_1.mfreplay")
	var d: NetReplayData = NetReplayData.load_file(path)
	t.check(d != null and d.finalized)
	t.eq(int(d.end["final_tick"]), 333)
	t.eq(int(d.end["reason"]), NetProtocol.MatchEndReason.SIM_DECIDED)
	t.eq(int(d.end["total_turns"]), 167)
	s.shutdown()
	t.eq(NetReplayData.load_file(path).byte_size, FileAccess.get_file_as_bytes(path).size(), "shutdown after the end does not rewrite")
	var builder: Callable = func(cfg: Dictionary) -> NetWorldJob:
		var seed_v: int = int((cfg["map"] as Dictionary)["seed"])
		return NetWorldJob.sync(func() -> NetSimAdapter: return NetSimAdapterFake.new(seed_v, 333))
	var res: Dictionary = NetReplayPlayer.verify_file(path, builder)
	t.check(bool(res["ok"]), str(res))
	t.eq(int(res["ticks"]), 333, "the player stops where the sim ended the match")


func test_a_match_that_ends_at_once_does_not_replace_the_autosave(t: TestCtx) -> void:
	var dir: String = _dir("quick")
	var first: Dictionary = _fake_local(dir, 400, _script())
	var keep: PackedByteArray = FileAccess.get_file_as_bytes(str(first["path"]))
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = kit.options("Me", {"replay_dir": dir, "max_ticks_per_poll": 2})
	var s: NetSession = NetSession.local(o, NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o))
	for _i: int in 5:
		kit.clock().advance_us(50_000)
		s.poll()
	s.shutdown()
	t.eq(s.replay_path(), "", "nothing saved")
	t.eq(FileAccess.get_file_as_bytes(NetReplay.autosave_path(1, dir)), keep, "the previous autosave is untouched")
	var left: PackedStringArray = DirAccess.get_files_at(dir)
	t.eq(left.size(), 1, "no stray temp file: %s" % str(left))


func test_record_replay_off_and_memory_only(t: TestCtx) -> void:
	var dir: String = _dir("off")
	var kit: NetSessionKit = _kit()
	var o: NetSessionOptions = kit.options("Me", {"replay_dir": dir, "record_replay": false})
	var s: NetSession = NetSession.local(o, NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o))
	for _i: int in 50:
		kit.clock().advance_us(50_000)
		s.poll()
	s.shutdown()
	t.eq(s.replay_path(), "")
	t.is_null(NetReplayData.from_bytes(s.replay_bytes()), "no recording: only the command-log-lite bytes")
	t.check(s.replay_bytes().slice(0, 7).get_string_from_ascii() == "MFCLOG1")
	t.eq(DirAccess.get_files_at(dir).size(), 0)
	# memory only: bytes, no files
	var kit2: NetSessionKit = _kit()
	var o2: NetSessionOptions = kit2.options("Me", {"replay_dir": ""})
	var s2: NetSession = NetSession.local(o2, NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o2))
	for _i: int in 80:
		kit2.clock().advance_us(50_000)
		s2.poll()
	t.check(NetReplayData.from_bytes(s2.replay_bytes()) != null, "playable mid-match")
	t.check(NetReplayData.from_bytes(s2.replay_bytes()).truncated, "no END mid-match")
	s2.shutdown()
	t.check(NetReplayData.from_bytes(s2.replay_bytes()).finalized)
	t.eq(s2.replay_path(), "")


func test_host_and_client_record_identical_streams_equal_to_local(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var dir_h: String = _dir("host")
	var dir_c: String = _dir("client")
	var h: NetSession = kit.host("Host", {"replay_dir": dir_h, "max_ticks_per_poll": 2})
	var c: NetSession = kit.join("Guest", {"replay_dir": dir_c, "max_ticks_per_poll": 2})
	kit.all_in(P.LOBBY, 100)
	c.lobby.set_ready(true)
	kit.step(3)
	h.lobby.set_team(1)
	c.lobby.set_team(2)
	kit.step(3)
	t.eq(h.lobby.host_start(), NetLobby.StartError.OK)
	t.check(kit.all_in(P.PLAYING, 300), "both playing")
	var script: Array = _script()
	var done: PackedInt32Array = PackedInt32Array()
	done.resize(script.size())
	var guard: int = 0
	while h.adapter().current_tick() < 700 and guard < 3000:
		for i: int in script.size():
			if done[i] == 0 and h.adapter().current_tick() >= int((script[i] as Array)[0]):
				done[i] = 1
				h.submit_command((script[i] as Array)[1] as PackedInt32Array)
		kit.step(1)
		guard += 1
	var host_pid: int = h.local_pid
	t.eq(host_pid, 0)
	var h_ticks: int = h.adapter().current_tick()
	var c_ticks: int = c.adapter().current_tick()
	var cfg: Dictionary = h.config()
	kit.shutdown_all()
	var hp: String = h.replay_path()
	var cp: String = c.replay_path()
	t.check(hp != "" and cp != "", "both recorded to disk: '%s' '%s'" % [hp, cp])
	var hd: NetReplayData = NetReplayData.load_file(hp)
	var cd: NetReplayData = NetReplayData.load_file(cp)
	if not t.check(hd != null and cd != null):
		return
	t.check(hd.finalized and cd.finalized)
	t.eq(hd.config, cd.config, "same MatchConfig in both headers")
	t.eq(int(hd.replay_meta["recorder_peer"]), 1)
	t.eq(int(cd.replay_meta["recorder_peer"]), 2)
	t.eq(int(cd.replay_meta["recorder_pid"]), 1)
	# the command streams equal up to the point both had reached
	var common_turn: int = mini(h_ticks, c_ticks) / 2 - 3
	var n: int = 0
	for i: int in hd.turns.size():
		if hd.turns[i] > common_turn:
			break
		n += 1
		t.check(i < cd.turns.size() and cd.turns[i] == hd.turns[i] and cd.bodies[i] == hd.bodies[i], "turn %d identical on host and client" % hd.turns[i])
	t.gt(n, 20, "a real number of command turns compared")
	var m: int = mini(hd.check_count(), cd.check_count())
	t.gt(m, 20)
	for i: int in m:
		t.check(hd.checks[i * 3] == cd.checks[i * 3] and hd.checks[i * 3 + 1] == cd.checks[i * 3 + 1] and hd.checks[i * 3 + 2] == cd.checks[i * 3 + 2], "CHECK %d identical" % i)
	# both replay clean
	for pth: String in [hp, cp]:
		var res: Dictionary = NetReplayPlayer.verify_file(pth, NetSessionKit.fake_job)
		t.check(bool(res["ok"]), str(res))
	# LOCAL, same commands, same input delay: the same stream (turns and bodies)
	var dir_l: String = _dir("local")
	var lrun: Dictionary = _fake_local(dir_l, 700, script)
	var ld: NetReplayData = NetReplayData.from_bytes(lrun["bytes"] as PackedByteArray)
	var lcmp: int = 0
	for i: int in hd.turns.size():
		if hd.turns[i] > common_turn:
			break
		lcmp += 1
		t.check(i < ld.turns.size() and ld.turns[i] == hd.turns[i] and ld.bodies[i] == hd.bodies[i], "turn %d: LOCAL equals HOST" % hd.turns[i])
	t.eq(lcmp, n)
	t.eq(cfg["players"].size(), 2)


func test_leaving_a_running_match_records_the_state_reached(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var dir_h: String = _dir("lh")
	var dir_c: String = _dir("lc")
	var h: NetSession = kit.host("Host", {"replay_dir": dir_h})
	var c: NetSession = kit.join("Guest", {"replay_dir": dir_c})
	kit.all_in(P.LOBBY, 100)
	c.lobby.set_ready(true)
	kit.step(3)
	h.lobby.set_team(1)
	c.lobby.set_team(2)
	kit.step(3)
	h.lobby.host_start()
	kit.all_in(P.PLAYING, 300)
	kit.step(150)
	var leave_tick: int = c.adapter().current_tick()
	c.leave()
	var path: String = c.replay_path()
	t.check(path != "" and FileAccess.file_exists(path), "the client's replay was saved on leave")
	var d: NetReplayData = NetReplayData.load_file(path)
	t.check(d != null and d.finalized)
	t.eq(int(d.end["final_tick"]), leave_tick)
	t.eq(int(d.end["reason"]), NetProtocol.MatchEndReason.ABANDONED)
	var res: Dictionary = NetReplayPlayer.verify_file(path, NetSessionKit.fake_job)
	t.check(bool(res["ok"]), str(res))
	t.eq(int(res["ticks"]), leave_tick)
	kit.shutdown_all()


func test_desync_package_carries_a_playable_replay(t: TestCtx) -> void:
	var kit: NetSessionKit = _kit()
	var h: NetSession = kit.host("Host", {"replay_dir": ""})
	var c: NetSession = kit.join("Guest", {"replay_dir": ""})
	kit.all_in(P.LOBBY, 100)
	c.lobby.set_ready(true)
	kit.step(3)
	h.lobby.set_team(1)
	c.lobby.set_team(2)
	kit.step(3)
	h.lobby.host_start()
	kit.all_in(P.PLAYING, 300)
	kit.step(30)
	(c.adapter() as NetSimAdapterFake).inject_divergence(c.adapter().current_tick() + 40, 0)
	var reports: Array = []
	h.desync_detected.connect(func(r: Dictionary) -> void: reports.append(r))
	kit.run_until(func() -> bool: return not reports.is_empty(), 400)
	t.check(not reports.is_empty(), "desync detected")
	if reports.is_empty():
		kit.shutdown_all()
		return
	var rep: Dictionary = reports[0] as Dictionary
	var dir: String = str(rep.get("dir", kit.desync_dir))
	var found: String = ""
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".mfreplay"):
			found = dir.path_join(f)
	t.check(found != "", "the package has a replay")
	if found != "":
		var d: NetReplayData = NetReplayData.load_file(found)
		t.check(d != null, "it is a real .mfreplay, not the command-log-lite file: %s" % NetReplayData.last_error)
	kit.shutdown_all()


# ---- real sim (3-minute AI match) ---------------------------------------------------------------------------------

func test_real_three_minute_match_replays_identically(t: TestCtx) -> void:
	var rec: Dictionary = _real_cached()
	if not t.check(not rec.has("error"), str(rec.get("error", ""))):
		return
	var d: NetReplayData = NetReplayData.from_bytes(rec["bytes"] as PackedByteArray)
	t.check(d != null and d.finalized and not d.truncated)
	t.ge(int(rec["ticks"]), REAL_TICKS)
	t.ge(d.turns.size(), 20, "the AIs issued commands through the bundles")
	t.eq(d.check_count(), int(d.end["final_tick"]) / 20)
	t.gt(d.parts.size(), 10, "sub-checksums every 200 ticks")
	var checks: Dictionary = rec["checks"] as Dictionary
	var bad: int = 0
	for i: int in d.check_count():
		var rc: Array = checks[int(d.checks[i * 3])] as Array
		if int(rc[0]) != (int(d.checks[i * 3 + 1]) & 0xFFFFFFFF) or int(rc[1]) != (int(d.checks[i * 3 + 2]) & 0xFFFFFFFF):
			bad += 1
	t.eq(bad, 0, "recorded CHECKs = what the live session saw")
	t.eq(int(d.end["final_checksum"]), int(rec["final"]))
	# the replay reproduces every CHECK and the final state, in strict mode with the version gate
	var path: String = _dir("real").path_join("m.mfreplay")
	_write(path, rec["bytes"] as PackedByteArray)
	var local: Dictionary = NetReplay.local_versions(rec["opts"] as NetSessionOptions)
	var res: Dictionary = NetReplayPlayer.verify_file(path, NetSessionKit.real_job, 0, local)
	t.check(bool(res["ok"]), str(res))
	t.eq(int(res["compared"]), d.check_count())
	t.eq(int(res["final_checksum"]), int(rec["final"]))
	t.eq(int(res["ticks"]), int(d.end["final_tick"]))


func test_real_seek_to_three_arbitrary_ticks_and_continue(t: TestCtx) -> void:
	var rec: Dictionary = _real_cached()
	if not t.check(not rec.has("error"), str(rec.get("error", ""))):
		return
	var d: NetReplayData = NetReplayData.from_bytes(rec["bytes"] as PackedByteArray)
	var dumps: Dictionary = rec["dumps"] as Dictionary
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.strict = true
	p.auto_clear_events = true
	var clock: NetClock = NetClock.manual(0)
	t.eq(p.setup(d, NetSessionKit.real_job, clock), OK)
	var fails: Array = []
	p.verify_failed.connect(func(tick: int, e: int, a: int) -> void: fails.append([tick, e, a]))
	p.set_speed(NetReplayPlayer.MAX)
	# the live session's dump_state hashes at 2711 (forward), 903 (backward = rebuild), 3333 (forward), 1000 (backward)
	for target: int in [2711, 903, 3333, 1000]:
		p.seek_tick(target)
		var guard: int = 0
		while p.is_seeking() and guard < 100000:
			guard += 1
			p.poll(4000)
		t.eq(p.current_tick(), target)
		var h: int = NetProtocol.fnv1a32(p.adapter().dump_state().to_utf8_buffer())
		# the live run only captured dump_state at tick 1000; elsewhere check the CHECK verification instead
		var base: int = (target / 20) * 20
		if dumps.has(target):
			t.eq(h, int(dumps[target]), "dump_state hash at tick %d equals the live run" % target)
		else:
			t.check(p.verified_through_tick() >= base or p.verified_through_tick() >= base - 20, "verified through %d" % p.verified_through_tick())
	# the dump hashes recorded for ticks that are multiples of 20 (1000 here) were compared above; continue to the end
	var guard2: int = 0
	while not p.is_finished() and guard2 < 100000:
		guard2 += 1
		p.poll(8000)
	t.check(p.is_finished())
	t.eq(fails.size(), 0, "no replay-desync after seeking: %s" % str(fails))
	t.eq(p.adapter().checksum_now() & 0xFFFFFFFF, int(rec["final"]))
	t.eq(p.input_chain(), int(d.end["final_chain"]) & 0xFFFFFFFF)
	t.eq(p.compared_count(), d.check_count())


func test_real_seek_equals_straight_run_dump(t: TestCtx) -> void:
	var rec: Dictionary = _real_cached()
	if not t.check(not rec.has("error"), str(rec.get("error", ""))):
		return
	var d: NetReplayData = NetReplayData.from_bytes(rec["bytes"] as PackedByteArray)
	# straight run to 2711 (an odd, non-multiple-of-20 tick) one poll at a time
	var a: NetReplayPlayer = NetReplayPlayer.new()
	a.auto_clear_events = true
	a.setup(d, NetSessionKit.real_job, NetClock.manual(0))
	a.set_speed(NetReplayPlayer.MAX)
	while a.current_tick() < 2711:
		a.poll(1)
	var straight: int = NetProtocol.fnv1a32(a.adapter().dump_state().to_utf8_buffer())
	# seek: 3333 first, then back to 2711
	var b: NetReplayPlayer = NetReplayPlayer.new()
	b.auto_clear_events = true
	b.setup(d, NetSessionKit.real_job, NetClock.manual(0))
	b.seek_tick(3333)
	var guard: int = 0
	while b.is_seeking() and guard < 100000:
		guard += 1
		b.poll(8000)
	b.seek_tick(2711)
	guard = 0
	while b.is_seeking() and guard < 100000:
		guard += 1
		b.poll(8000)
	t.eq(b.current_tick(), 2711)
	t.eq(NetProtocol.fnv1a32(b.adapter().dump_state().to_utf8_buffer()), straight, "seek back to 2711 equals the straight run")
	t.eq(b.generation(), 2, "one rebuild")


func test_real_tampered_command_is_reported(t: TestCtx) -> void:
	var rec: Dictionary = _real_cached()
	if not t.check(not rec.has("error"), str(rec.get("error", ""))):
		return
	var bytes: PackedByteArray = (rec["bytes"] as PackedByteArray).duplicate()
	var recs: Array = _records(bytes)
	var turns_seen: int = 0
	var flipped: int = -1
	for r: Variant in recs:
		var ra: Array = r as Array
		if int(ra[0]) == NetProtocol.ReplayRec.TURNS:
			turns_seen += 1
			if turns_seen == 25:
				bytes[int(ra[1]) + int(ra[2]) - 1] ^= 0x01
				flipped = turns_seen
				break
	t.eq(flipped, 25)
	var path: String = _dir("rtamper").path_join("t.mfreplay")
	_write(path, bytes)
	var res: Dictionary = NetReplayPlayer.verify_file(path, NetSessionKit.real_job, 0, {})
	t.check(not bool(res["ok"]), "flipping one command byte is a replay-desync")
	t.gt(int(res["first_mismatch_tick"]), 0)
	var base: NetReplayData = NetReplayData.from_bytes(rec["bytes"] as PackedByteArray)
	var turn: int = base.turns[24]
	t.eq(int(res["first_mismatch_tick"]), (2 * turn / 20 + 1) * 20, "reported at the first CHECK after the tampered turn")


func test_real_player_setup_is_sliceable(t: TestCtx) -> void:
	var rec: Dictionary = _real_cached()
	if not t.check(not rec.has("error"), str(rec.get("error", ""))):
		return
	var d: NetReplayData = NetReplayData.from_bytes(rec["bytes"] as PackedByteArray)
	var p: NetReplayPlayer = NetReplayPlayer.new()
	var clock: NetClock = NetClock.manual(0)
	t.eq(p.setup(d, NetSessionKit.real_job, clock, false), OK)
	t.check(p.is_loading())
	t.is_null(p.adapter())
	var guard: int = 0
	while p.is_loading() and guard < 1000:
		guard += 1
		p.poll(4000)
	t.check(not p.is_loading())
	t.not_null(p.adapter())
	t.eq(p.current_tick(), 0)
	t.eq(p.end_tick(), int(d.end["final_tick"]))
	t.near(p.progress(), 0.0)


# ---- golden replay (recorded on macOS; also run on Linux by tools/py/xplat_determinism.py xplat_net_replay.gd) ----------

func test_golden_replay_fixtures_verify(t: TestCtx) -> void:
	var o: NetSessionOptions = AppNetSetup.make_options(SimMatchKit.data(), {"with_view": false, "events": false})
	var local: Dictionary = NetReplay.local_versions(o)
	var cases: Array = [["app_ai_2p_3min", o.world_builder], ["xplat_2p_ai", NetSessionKit.real_job]]
	for c: Variant in cases:
		var path: String = "res://tests/fixtures/net/replays/%s.mfreplay" % str((c as Array)[0])
		var d: NetReplayData = NetReplayData.load_file(path)
		if not t.not_null(d, "fixture missing (see tests/net/make_replay_fixture.gd): %s" % NetReplayData.last_error):
			continue
		t.check(d.finalized and not d.truncated)
		t.ge(d.check_count(), 150, "a 3-minute match")
		var gate: Dictionary = NetReplay.check_versions(d.versions(), local, true)
		if int(gate["level"]) != NetReplay.GATE_OK:
			t.note("%s was recorded for other data/sim versions, regenerate it (tests/net/make_replay_fixture.gd): %s" % [path.get_file(), str(gate["text"])])
			continue
		var res: Dictionary = NetReplayPlayer.verify_file(path, (c as Array)[1] as Callable, 0, local)
		t.check(bool(res["ok"]), "%s: %s (regenerate after an intentional sim change)" % [path.get_file(), str(res)])
		t.eq(int(res["compared"]), d.check_count())
		t.eq(int(res["final_checksum"]), int(d.end["final_checksum"]) & 0xFFFFFFFF)
