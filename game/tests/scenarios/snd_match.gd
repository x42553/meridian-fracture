extends SceneTree
## `tools/gd run res://tests/scenarios/snd_match.gd -- --ticks=1200 --seed=3 [--bots] [--no-fight] [--no-music] [--quality=2]`
## A real match (SimMatchKit, two armies that fight) played through the real audio stack on the Dummy audio driver. Prints
## `SND_MATCH ...` with voices per second of game time, pool peaks, loop counts and the audio cost per frame. Exit 0 when no
## error was logged and sounds were started.


func _initialize() -> void:
	var o: Dictionary = {"ticks": 1200, "seed": 3, "bots": false, "fight": true, "music": true, "quality": 1}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):
			o["ticks"] = int(a.substr(8))
		elif a.begins_with("--seed="):
			o["seed"] = int(a.substr(7))
		elif a.begins_with("--quality="):
			o["quality"] = int(a.substr(10))
		elif a == "--bots":
			o["bots"] = true
		elif a == "--no-fight":
			o["fight"] = false
		elif a == "--realtime":
			o["realtime"] = true
		elif a == "--heat":
			o["heat"] = true
		elif a == "--no-music":
			o["music"] = false
	var r: Dictionary = await SndMatchDriver.run(o)
	print("SND_MATCH ok=%s driver=%s ticks=%d game_s=%.1f starts=%d voices_per_s=%.1f culls=%d max_3d=%d max_2d=%d max_loops=%d audio_ms_avg=%.3f audio_ms_max=%.3f worst_frame=%d music_states=%s" % [
		str(r.get("ok")), str(r.get("driver", "?")), int(r.get("ticks", 0)), float(r.get("game_s", 0.0)), int(r.get("starts", 0)),
		float(r.get("voices_per_s", 0.0)), int(r.get("culls", 0)), int(r.get("max_voices_3d", 0)), int(r.get("max_voices_2d", 0)),
		int(r.get("max_loops", 0)), float(r.get("ms_audio_avg", 0.0)), float(r.get("ms_audio_max", 0.0)), int(r.get("worst_frame", 0)), str(r.get("music_states", []))])
	print("SND_COUNTERS pool=%s bridge=%s" % [str(r.get("counters", {})), str(r.get("bridge", {}))])
	if str(r.get("error", "")) != "":
		printerr("SND_MATCH error: %s" % str(r["error"]))
	quit(0 if bool(r.get("ok", false)) and int(r.get("starts", 0)) > 0 else 1)
