extends SceneTree
## Cross-platform determinism scenario for the LOCAL net pipeline (NET-10): two scripted bots play a real 96x96 match
## through NetSession.local_from_config (config -> world job -> turn host -> bundles -> lockstep, AI commands travelling
## in the bundles), 2400 ticks unpaced:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_net_local.gd
## `HASH tick=<n> <hex>`: every 20-tick checksum, the input chain, the final checksum and the command-log digest.

const TICKS: int = 2400


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var clock: NetClock = NetClock.manual(1_000_000)
	var o: NetSessionOptions = NetSessionOptions.from_game_data(SimMatchKit.data())
	o.clock = clock
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.discovery_enabled = false
	o.world_builder = NetSessionKit.real_job
	o.ai_factory = NetSessionKit.bot_factory({"first_attack_tick": 1200, "interval": 1, "wave_size": 6})
	o.log_sink = func(_l: int, _t: String) -> void: pass
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o)
	st.map_size = 96
	st.layout_players = 2
	st.slots[0].kind = NetProtocol.SlotKind.AI
	st.slots[0].peer_id = 0
	st.slots[0].name = "AI 1"
	st.slots[1].roster_id = "roster.nec.vanilla"
	st.rules["fog"] = 1
	st.rules["start_credits"] = 25000
	var ver: Dictionary = {"game": "x", "proto": 1, "sim": o.sim_version, "data_hash": o.data_hash, "data_format": 1,
		"data_ids": int(SimMatchKit.data().table_hashes.get("ids", 0))}
	var cfg: Dictionary = NetMatchConfig.parse(NetMatchConfig.canonical_json(NetMatchConfig.from_lobby(st, 20260930, ver, 1_790_000_000, o.roster_ids)))
	var s: NetSession = NetSession.local_from_config(o, cfg)
	var out: PackedStringArray = PackedStringArray()
	if s == null:
		out.append("ERROR " + NetSession.last_create_error)
		return out
	var lines: PackedStringArray = PackedStringArray()
	s.checksum_observer = func(tick: int, cs: int, _chain: int) -> void: lines.append("HASH tick=%d %08x" % [tick, cs & 0xFFFFFFFF])
	var guard: int = 0
	while guard < 20000 and s.phase != NetSession.Phase.ENDED and (s.adapter() == null or s.adapter().current_tick() < TICKS):
		clock.advance_us(50_000)
		s.poll()
		guard += 1
	out.append_array(lines)
	out.append("HASH tick=9001 %08x" % (s.lockstep.input_chain() & 0xFFFFFFFF))
	out.append("HASH tick=9002 %08x" % (s.adapter().checksum_now() & 0xFFFFFFFF))
	out.append("HASH tick=9003 %08x" % NetProtocol.fnv1a32(PackedByteArray(Array(s.command_log().to_ints()).map(func(v: int) -> int: return v & 0xFF))))
	out.append("HASH tick=9004 %08x" % NetProtocol.fnv1a32(NetMatchConfig.canonical_json(s.config()).to_utf8_buffer()))
	s.checksum_observer = Callable()
	s.shutdown()
	return out
