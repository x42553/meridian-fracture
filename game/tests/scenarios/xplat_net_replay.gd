extends SceneTree
## Cross-platform replay determinism (NET-8): plays the golden replays recorded on macOS
## (res://tests/fixtures/net/replays/*.mfreplay, regenerate with tests/net/make_replay_fixture.gd) through
## NetReplayPlayer and prints the checksum of the replayed world at every CHECK tick:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_net_replay.gd
## `HASH tick=<n> <hex>`: the player's checksum at every 20th tick, the final checksum, the input chain and the number of
## recorded CHECKs the player matched. The scenario exits 1 when the replay does not verify against the file's own records, so a
## replay recorded on one OS must replay identically on every other.

const FIXTURES: PackedStringArray = [
	"res://tests/fixtures/net/replays/app_ai_2p_3min.mfreplay",  # recorded by the game (real AI), world built like the game does
	"res://tests/fixtures/net/replays/xplat_2p_ai.mfreplay",  # recorded by make_replay_fixture.gd (scripted test bots)
]


func _initialize() -> void:
	var all_ok: bool = true
	for fi: int in FIXTURES.size():
		var builder: Callable = NetSessionKit.real_job
		if fi == 0:
			builder = AppNetSetup.make_options(SimMatchKit.data(), {"with_view": false, "events": false}).world_builder
		if not _play(FIXTURES[fi], builder, fi * 100000):
			all_ok = false
	print("SCENARIO_DONE")
	quit(0 if all_ok else 1)


func _play(path: String, builder: Callable, base: int) -> bool:
	var d: NetReplayData = NetReplayData.load_file(path)
	if d == null:
		printerr("SCENARIO FAILED: %s: %s" % [path, NetReplayData.last_error])
		return false
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.auto_clear_events = true
	var clock: NetClock = NetClock.manual(0)
	if p.setup(d, builder, clock) != OK:
		printerr("SCENARIO FAILED: %s: %s" % [path, p.error_text])
		return false
	p.set_speed(NetReplayPlayer.MAX)
	var seen: int = -1
	var guard: int = 0
	while not p.is_finished() and guard < 10_000_000:
		guard += 1
		p.poll(1)
		var t: int = p.current_tick()
		if t % 20 == 0 and t != seen and t > 0:
			seen = t
			print("HASH tick=%d %08x" % [base + t, p.adapter().checksum_at(t) & 0xFFFFFFFF])
	var ok: bool = p.diverged_tick() < 0 and p.is_finished()
	print("HASH tick=%d %08x" % [base + 9001, p.input_chain() & 0xFFFFFFFF])
	print("HASH tick=%d %08x" % [base + 9002, p.adapter().checksum_now() & 0xFFFFFFFF])
	print("HASH tick=%d %08x" % [base + 9003, p.compared_count()])
	print("REPLAY file=%s ok=%s ticks=%d compared=%d diverged=%d warning=%s" % [path.get_file(), str(ok), p.current_tick(), p.compared_count(), p.diverged_tick(), p.warning])
	return ok
