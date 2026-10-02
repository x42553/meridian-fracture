extends SceneTree
## Replays a .mfreplay headless and reports whether it verifies (docs/spec/net.md 5.8):
##   tools/gd run res://tests/net/replay_verify_main.gd -- path=<file.mfreplay> [builder=app|kit] [seeks=a,b,c] [strict=1] [max=N]
## builder=app (default) builds the world exactly like the game (AppNetSetup.make_options -> AppMatchJob), builder=kit uses the
## test kit (NetSessionKit.real_job). seeks=a,b,c seeks to those ticks first (backward = rebuild), then plays to the end.
## Prints `REPLAYVERIFY ok=<0|1> ticks= compared= final=<hex> chain=<hex> first_mismatch= kind= parts= seeks_ok=` and exits 0 / 1.


func _initialize() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	var path: String = str(args.get("path", ""))
	var d: NetReplayData = NetReplayData.load_file(path)
	if d == null:
		print("REPLAYVERIFY ok=0 error=%s" % NetReplayData.last_error)
		quit(1)
		return
	var builder: Callable = NetSessionKit.real_job
	var local: Dictionary = {}
	if str(args.get("builder", "app")) == "app":
		var o: NetSessionOptions = AppNetSetup.make_options(SimMatchKit.data(), {"with_view": false, "events": false})
		builder = o.world_builder
		local = NetReplay.local_versions(o)
	var p: NetReplayPlayer = NetReplayPlayer.new()
	p.strict = str(args.get("strict", "0")) == "1"
	p.local_versions = local
	p.auto_clear_events = true
	var clock: NetClock = NetClock.manual(0)
	if p.setup(d, builder, clock) != OK:
		print("REPLAYVERIFY ok=0 error=%s" % p.error_text)
		quit(1)
		return
	if p.warning != "":
		print("REPLAYVERIFY warning=%s" % p.warning)
	p.set_speed(NetReplayPlayer.MAX)
	var seeks_ok: bool = true
	var stop: int = int(args.get("max", "0"))
	var seeks: String = str(args.get("seeks", ""))
	if seeks != "":
		for part: String in seeks.split(","):
			var target: int = int(part)
			p.seek_tick(target)
			var g: int = 0
			while p.is_seeking() and g < 10_000_000:
				g += 1
				p.poll(20000)
			if p.current_tick() != mini(target, p.end_tick()):
				seeks_ok = false
			print("REPLAYVERIFY seek target=%d now=%d verified_through=%d diverged=%d" % [target, p.current_tick(), p.verified_through_tick(), p.diverged_tick()])
	var guard: int = 0
	while not p.is_finished() and guard < 10_000_000 and (stop <= 0 or p.current_tick() < stop):
		guard += 1
		p.poll(20000)
	var mm: Dictionary = p.mismatch()
	var ok: bool = p.diverged_tick() < 0 and seeks_ok and (p.is_finished() or stop > 0)
	print("REPLAYVERIFY ok=%d ticks=%d compared=%d final=%08x chain=%08x first_mismatch=%d kind=%s parts=%s seeks_ok=%s recorded_final=%08x recorded_tick=%d" % [
		1 if ok else 0, p.current_tick(), p.compared_count(), p.adapter().checksum_now() & 0xFFFFFFFF, p.input_chain(), p.diverged_tick(),
		str(mm.get("kind", "")), str(mm.get("parts", "")), str(seeks_ok), int(d.end.get("final_checksum", 0)), int(d.end.get("final_tick", 0))])
	quit(0 if ok else 1)
