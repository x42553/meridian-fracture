extends RefCounted
## End-to-end audio: a real match (real data, real map, two armies) through SndManager on the Dummy driver. No script errors,
## sounds start, limits hold, --no-audio paths stay silent (audio spec 10.4).


func test_match_plays_events_without_errors(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Dictionary = await SndMatchDriver.run({"ticks": 500, "seed": 3})
	t.check(bool(r.get("ok", false)), "no engine or Log errors: %s" % str(r.get("error", "")))
	if not bool(r.get("ok", false)) and str(r.get("error", "")) != "":
		return
	t.gt(int(r["starts"]), 20, "voices started during the fight (%d)" % int(r["starts"]))
	t.le(int(r["max_voices_3d"]), 48, "3D pool bound held")
	t.gt(int(r["combat_events"]) + int(r["starts"]), 0, "something happened")
	t.note("voices/s %.1f, starts %d in %.1f s game time, max 3d %d, loops %d, audio %.2f ms avg / %.2f ms max, driver %s, counters %s" % [
		float(r["voices_per_s"]), int(r["starts"]), float(r["game_s"]), int(r["max_voices_3d"]), int(r["max_loops"]),
		float(r["ms_audio_avg"]), float(r["ms_audio_max"]), str(r["driver"]), str(r["counters"])])


func test_music_and_meter_react(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Dictionary = await SndMatchDriver.run({"ticks": 300, "seed": 5})
	t.check(bool(r.get("ok", false)), "run ok: %s" % str(r.get("error", "")))
	t.gt(float(r.get("heat", 0.0)) + float(r.get("starts", 0)), 0.0, "the meter or the pool saw the fight")


func test_no_audio_flag_installs_nothing(t: TestCtx) -> void:
	var args: AppLaunchArgs = AppLaunchArgs.new()
	args.no_audio = true
	var before: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Snd")
	var a: AppAudio = AppAudio.install(null, null, args)
	t.is_null(a, "--no-audio returns null")
	t.is_null(AppAudio.current, "and registers nothing")
	t.eq((Engine.get_main_loop() as SceneTree).root.get_node_or_null("Snd"), before, "no Snd node was added")
