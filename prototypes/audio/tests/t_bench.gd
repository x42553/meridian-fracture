extends SceneTree
## Real-time playback cost. Run via py/bench.py (which measures process CPU time externally).
## args (after --): n=<voices> fmt=ogg_mono|ogg_stereo|pcm_mono|qoa_mono mode=3d|2d filter=1|0 secs=<s> move=1|0

var _a: Dictionary = {}
var _players: Array = []
var _base: PackedVector3Array = PackedVector3Array()
var _t0_us: int = 0
var _frames: int = 0
var _upd_us: int = 0
var _frame_max_us: int = 0
var _last_us: int = 0
var _secs: float = 8.0
var _move: bool = true
var _mode: String = "3d"


func _streams(fmt: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	match fmt:
		"ogg_mono":
			for n in ["engine_tracked_loop", "engine_wheeled_loop", "engine_boat_loop", "footsteps_loop"]:
				var s: AudioStreamOggVorbis = (load("res://assets/audio/vehicles/%s.ogg" % n) as AudioStreamOggVorbis).duplicate()
				s.loop = true
				out.append(s)
		"ogg_stereo":
			for p in ["air/heli_rotor_loop", "energy/beam_hum_loop", "alarms/sw_siren_loop"]:
				var s2: AudioStreamOggVorbis = (load("res://assets/audio/%s.ogg" % p) as AudioStreamOggVorbis).duplicate()
				s2.loop = true
				out.append(s2)
		"pcm_mono", "qoa_mono":
			for n in ["engine_tracked_loop", "engine_wheeled_loop", "engine_boat_loop", "footsteps_loop"]:
				var w: AudioStreamWAV = AudioStreamWAV.load_from_file("res://assets/wav_test/%s.wav" % n) if fmt == "pcm_mono" else (load("res://assets/wav_test/%s.wav" % n) as AudioStreamWAV).duplicate()
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate)
				out.append(w)
	return out


func _initialize() -> void:
	Engine.max_fps = 60


var _built: bool = false


func _build() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=")
		_a[kv[0]] = kv[1]
	var n: int = int(_a.get("n", 64))
	var fmt: String = String(_a.get("fmt", "ogg_mono"))
	_mode = String(_a.get("mode", "3d"))
	_secs = float(_a.get("secs", 8.0))
	_move = int(_a.get("move", 1)) == 1
	SndBus.setup()
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var listener: AudioListener3D = AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	var streams: Array[AudioStream] = _streams(fmt)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var pos: Vector3 = Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
		_base.append(pos)
		var s: AudioStream = streams[i % streams.size()]
		if _mode == "3d":
			var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
			p.stream = s
			p.bus = &"Sfx"
			p.unit_size = 20.0
			p.max_distance = 400.0
			p.attenuation_filter_cutoff_hz = 5000.0 if int(_a.get("filter", 1)) == 1 else 20500.0
			root.add_child(p)
			p.global_position = pos
			p.play(rng.randf() * 2.0)
			_players.append(p)
		else:
			var p2: AudioStreamPlayer = AudioStreamPlayer.new()
			p2.stream = s
			p2.bus = &"Sfx"
			root.add_child(p2)
			p2.play(rng.randf() * 2.0)
			_players.append(p2)
	_t0_us = Time.get_ticks_usec()
	_last_us = _t0_us


func _process(_delta: float) -> bool:
	if not _built:
		_built = true
		_build()
		return false
	var now: int = Time.get_ticks_usec()
	_frames += 1
	if _frames > 1:
		_frame_max_us = maxi(_frame_max_us, now - _last_us)
	_last_us = now
	if _move and _mode == "3d":  # units moving: 60 transform updates per second per voice
		var t: float = float(now - _t0_us) * 1e-6
		for i in _players.size():
			(_players[i] as AudioStreamPlayer3D).global_position = _base[i] + Vector3(sin(t * 0.7 + i) * 6.0, 0.0, cos(t * 0.5 + i) * 6.0)
		_upd_us += Time.get_ticks_usec() - now
	var elapsed: float = float(now - _t0_us) * 1e-6
	if elapsed >= _secs:
		var playing: int = 0
		for p in _players:
			playing += 1 if p.playing else 0
		print("RESULT ", JSON.stringify({"n": _players.size(), "fmt": _a.get("fmt", "ogg_mono"), "mode": _mode, "filter": int(_a.get("filter", 1)),
			"secs": snappedf(elapsed, 0.01), "fps": snappedf(float(_frames) / elapsed, 0.1), "frame_max_ms": snappedf(float(_frame_max_us) / 1000.0, 0.01),
			"pos_update_us_per_frame": snappedf(float(_upd_us) / maxf(_frames, 1), 0.1), "playing": playing, "driver": AudioServer.get_driver_name(),
			"mix_rate": AudioServer.get_mix_rate(), "latency_ms": snappedf(AudioServer.get_output_latency() * 1000.0, 0.1)}))
		return true
	return false
