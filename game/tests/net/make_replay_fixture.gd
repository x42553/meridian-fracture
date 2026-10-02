extends SceneTree
## Regenerates the golden replay fixture (docs/spec/net.md 5.8 "Replay used by tests"):
##   tools/gd run res://tests/net/make_replay_fixture.gd [-- ticks=3600 out=res://tests/fixtures/net/replays/xplat_2p_ai.mfreplay]
## A LOCAL real-sim match (96x96, two scripted test bots, 3 minutes) is recorded through NetSession and written as a .mfreplay.
## The second fixture, app_ai_2p_3min.mfreplay, was recorded by the game itself (real AI, app world builder):
##   tools/gd run res://src/app/boot.tscn -- --autostart=match --players=2 --humans=0 --ticks=3600 --speed=0 --fresh-settings \
##     --no-audio --map-size=96 --map-seed=7 --replay-dir=user://rep1_accept      (then copy autosave_1.mfreplay from that folder)
## Run it only after an intentional sim or data change that makes test_golden_replay_fixture_verifies fail; the file is verified
## on every OS by `python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_net_replay.gd`.

const DEFAULT_OUT: String = "res://tests/fixtures/net/replays/xplat_2p_ai.mfreplay"


func _initialize() -> void:
	var ticks: int = 3600
	var out: String = DEFAULT_OUT
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0] == "ticks":
			ticks = int(kv[1])
		elif kv.size() == 2 and kv[0] == "out":
			out = kv[1]
	var clock: NetClock = NetClock.manual(1_000_000)
	var o: NetSessionOptions = NetSessionOptions.from_game_data(SimMatchKit.data())
	o.clock = clock
	o.replay_dir = ""
	o.speed_pct_override = 0
	o.max_ticks_per_poll = 64
	o.discovery_enabled = false
	o.unix_time_override = 1_790_000_000
	o.match_seed_override = 0x5EED
	o.world_builder = NetSessionKit.real_job
	o.ai_factory = NetSessionKit.bot_factory({"first_attack_tick": 600, "interval": 1, "wave_size": 5})
	o.log_sink = func(_l: int, _t: String) -> void: pass
	var st: NetLobbyState = NetLobbyState.create_skirmish("Me", "roster.napc.vanilla", o)
	st.map_size = 96
	st.layout_players = 2
	st.slots[0].kind = NetProtocol.SlotKind.AI
	st.slots[0].peer_id = 0
	st.slots[0].name = "AI 1"
	st.slots[0].ready = true
	st.slots[0].ai_level = 1
	st.slots[1].roster_id = "roster.nec.vanilla"
	st.rules["fog"] = 1
	var ver: Dictionary = {"game": o.game_version, "proto": NetProtocol.PROTO_VERSION, "sim": o.sim_version, "data_hash": o.data_hash, "data_format": 1,
		"data_ids": int(SimMatchKit.data().table_hashes.get("ids", 0))}
	var cfg: Dictionary = NetMatchConfig.parse(NetMatchConfig.canonical_json(NetMatchConfig.from_lobby(st, 20261001, ver, 1_790_000_000, o.roster_ids)))
	var s: NetSession = NetSession.local_from_config(o, cfg)
	if s == null:
		printerr("FIXTURE FAILED: %s" % NetSession.last_create_error)
		quit(1)
		return
	var guard: int = 0
	while guard < 40000 and s.phase != NetSession.Phase.ENDED and (s.adapter() == null or s.adapter().current_tick() < ticks):
		clock.advance_us(50_000)
		s.poll()
		guard += 1
	s.shutdown()
	var bytes: PackedByteArray = s.replay_bytes()
	var f: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("FIXTURE FAILED: cannot write %s" % out)
		quit(1)
		return
	f.store_buffer(bytes)
	f.close()
	var d: NetReplayData = NetReplayData.from_bytes(bytes)
	print("FIXTURE %s bytes=%d turns=%d checks=%d final_tick=%d final=%08x" % [out, bytes.size(), d.turns.size(), d.check_count(), int(d.end["final_tick"]), int(d.end["final_checksum"])])
	quit(0)
