extends SceneTree
## Engine behaviour measured through AudioEffectCapture / bus meters (Dummy driver mixes in real time, so waits are wall-clock).
## Run: Godot --headless --path prototypes/audio --script res://tests/t_capture.gd -- [only=att,pan,lp,duck,step,seam]

const SR: int = 44100
var cap: AudioEffectCapture
var out: Dictionary = {}
var only: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run()


func _noise(seconds: float, mode: int = 0, seed_v: int = 1) -> AudioStreamWAV:  # 0 mono, 1 stereo, 2 stereo L only, 3 stereo R only
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_v
	var n: int = int(seconds * SR)
	var ch: int = 1 if mode == 0 else 2
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * ch * 2)
	for i in n:
		for c in ch:
			var v: float = rng.randfn(0.0, 0.18)
			if (mode == 2 and c == 1) or (mode == 3 and c == 0):
				v = 0.0
			bytes.encode_s16((i * ch + c) * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = ch == 2
	w.mix_rate = SR
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _sine(freq: float, seconds: float, amp: float = 0.5) -> AudioStreamWAV:
	var n: int = int(seconds * SR)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(sin(TAU * freq * float(i) / SR) * amp * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _grab(seconds: float) -> PackedVector2Array:
	cap.clear_buffer()
	await create_timer(seconds).timeout
	return cap.get_buffer(cap.get_frames_available())


func _db(p: float) -> float:
	return 10.0 * log(maxf(p, 1e-12)) / log(10.0)


func _lr_db(b: PackedVector2Array, from: int) -> Vector2:
	var l: float = 0.0
	var r: float = 0.0
	for i in range(from, b.size()):
		l += b[i].x * b[i].x
		r += b[i].y * b[i].y
	var n: float = float(maxi(b.size() - from, 1))
	return Vector2(_db(l / n), _db(r / n))


func _total_db(b: PackedVector2Array, from: int = 3000) -> float:
	var v: Vector2 = _lr_db(b, from)
	return _db(pow(10.0, v.x / 10.0) + pow(10.0, v.y / 10.0))


func _band_db(b: PackedVector2Array, f0: float, from: int = 3000) -> float:
	var acc: float = 0.0
	for k in range(-4, 5):
		var w: float = TAU * f0 * (1.0 + 0.02 * k) / SR
		var coeff: float = 2.0 * cos(w)
		var s1: float = 0.0
		var s2: float = 0.0
		for i in range(from, b.size()):
			var s0: float = b[i].x + b[i].y + coeff * s1 - s2
			s2 = s1
			s1 = s0
		acc += s1 * s1 + s2 * s2 - coeff * s1 * s2
	return _db(acc / 9.0 / float(b.size() - from) / float(b.size() - from))


func _want(k: String) -> bool:
	return only.is_empty() or only.has(k)


func _run() -> void:
	await process_frame
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	SndBus.setup()
	cap = AudioEffectCapture.new()
	cap.buffer_length = 3.0
	AudioServer.add_bus_effect(0, cap)
	# REQUIRED: a current Camera3D must exist in the viewport, otherwise AudioListener3D alone yields silence (verified in 4.7.2).
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var listener: AudioListener3D = AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	if _want("att"):
		await _exp_attenuation()
	if _want("pan"):
		await _exp_pan()
	if _want("lp"):
		await _exp_lowpass()
	if _want("duck"):
		await _exp_duck()
	if _want("step"):
		await _exp_step()
	if _want("seam"):
		await _exp_seam()
	print("RESULT ", JSON.stringify(out))
	quit()


func _exp_attenuation() -> void:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = _noise(1.0)
	p.unit_size = 10.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.max_distance = 0.0
	root.add_child(p)
	p.play()
	var res: Dictionary = {}
	for m: Array in [[AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "inverse"], [AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE, "inverse_square"], [AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC, "logarithmic"], [AudioStreamPlayer3D.ATTENUATION_DISABLED, "disabled"]]:
		p.attenuation_model = m[0]
		var row: Dictionary = {}
		for d: float in [1.0, 2.5, 5.0, 10.0, 20.0, 40.0, 80.0, 160.0]:
			p.global_position = Vector3(0, 0, -d)
			await create_timer(0.1).timeout
			row[str(d)] = snappedf(_total_db(await _grab(0.35)), 0.1)
		res[m[1]] = row
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_distance = 100.0
	var row2: Dictionary = {}
	for d: float in [50.0, 90.0, 99.0, 101.0, 150.0]:
		p.global_position = Vector3(0, 0, -d)
		await create_timer(0.1).timeout
		row2[str(d)] = snappedf(_total_db(await _grab(0.35)), 0.1)
	res["max_distance_100"] = row2
	out["attenuation_dbfs"] = res
	p.queue_free()
	await process_frame


func _exp_pan() -> void:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.unit_size = 10.0
	p.attenuation_filter_cutoff_hz = 20500.0
	root.add_child(p)
	var res: Dictionary = {}
	for mode: Array in [[0, "mono_src"], [2, "stereo_src_L_only"]]:
		p.stream = _noise(1.0, mode[0])
		p.play()
		for ps: float in [0.0, 0.5, 1.0]:
			p.panning_strength = ps
			var row: Dictionary = {}
			for az: Array in [["left", Vector3(-10, 0, 0)], ["front", Vector3(0, 0, -10)], ["right", Vector3(10, 0, 0)], ["behind", Vector3(0, 0, 10)]]:
				p.global_position = az[1]
				await create_timer(0.1).timeout
				var v: Vector2 = _lr_db(await _grab(0.35), 3000)
				row[az[0]] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]
			res["%s panning_strength=%.1f (L,R dBFS)" % [mode[1], ps]] = row
	out["panning"] = res
	p.queue_free()
	await process_frame


func _exp_lowpass() -> void:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = _noise(1.0)
	p.unit_size = 10.0
	p.max_distance = 0.0
	root.add_child(p)
	p.play()
	var res: Dictionary = {}
	for cutoff: float in [20500.0, 5000.0]:
		p.attenuation_filter_cutoff_hz = cutoff
		for d: float in [5.0, 40.0, 160.0]:
			p.global_position = Vector3(0, 0, -d)
			await create_timer(0.1).timeout
			var b: PackedVector2Array = await _grab(0.4)
			var ref: float = _band_db(b, 1000.0)
			var row: Dictionary = {}
			for f: float in [250.0, 1000.0, 4000.0, 8000.0, 14000.0]:
				row[str(int(f))] = snappedf(_band_db(b, f) - ref, 0.1)
			res["cutoff=%d dist=%d (dB re 1 kHz)" % [int(cutoff), int(d)]] = row
	out["distance_lowpass"] = res
	p.queue_free()
	await process_frame


func _mean_peak(bus: int, frames: int) -> float:
	var acc: float = 0.0
	for i in frames:
		await process_frame
		acc += maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), -80.0)
	return acc / float(frames)


func _exp_duck() -> void:
	var mi: int = AudioServer.get_bus_index(SndBus.MUSIC)
	AudioServer.set_bus_volume_db(mi, 0.0)
	var music: AudioStreamPlayer = AudioStreamPlayer.new()
	music.stream = _noise(1.0, 0, 3)
	music.bus = SndBus.MUSIC
	root.add_child(music)
	music.play()
	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.stream = _noise(1.0, 0, 4)
	voice.bus = SndBus.VOICE
	voice.volume_db = -8.0
	root.add_child(voice)
	var comp: AudioEffectCompressor = AudioServer.get_bus_effect(mi, 0)
	var res: Dictionary = {}
	for cfg: Array in [[-30.0, 3.0], [-24.0, 4.0], [-36.0, 2.0], [-30.0, 1.0]]:
		comp.threshold = cfg[0]
		comp.ratio = cfg[1]
		await create_timer(0.8).timeout
		var alone: float = await _mean_peak(mi, 30)
		voice.play()
		await create_timer(0.6).timeout
		var during: float = await _mean_peak(mi, 30)
		voice.stop()
		await create_timer(1.5).timeout
		var after: float = await _mean_peak(mi, 30)
		res["threshold=%d ratio=%.0f" % [int(cfg[0]), cfg[1]]] = {"music_peak_alone_db": snappedf(alone, 0.1), "during_voice_db": snappedf(during, 0.1), "duck_db": snappedf(during - alone, 0.1), "after_1.5s_db": snappedf(after, 0.1)}
	# same measurement with a REAL announcer line (looped) instead of noise: what the player will actually hear
	var real: AudioStreamOggVorbis = (load("res://assets/audio/voice/default/base_under_attack.ogg") as AudioStreamOggVorbis).duplicate()
	real.loop = true
	voice.stream = real
	voice.volume_db = 0.0
	for cfg: Array in [[-18.0, 3.0], [-24.0, 4.0], [-14.0, 2.5]]:
		comp.threshold = cfg[0]
		comp.ratio = cfg[1]
		voice.stop()
		await create_timer(1.0).timeout
		var alone2: float = await _mean_peak(mi, 40)
		voice.play()
		await create_timer(0.4).timeout
		var during2: float = await _mean_peak(mi, 40)
		res["REAL SPEECH threshold=%d ratio=%.1f" % [int(cfg[0]), cfg[1]]] = {"music_alone_db": snappedf(alone2, 0.1), "during_speech_db": snappedf(during2, 0.1), "duck_db": snappedf(during2 - alone2, 0.1)}
	out["sidechain_duck"] = res
	music.queue_free()
	voice.queue_free()
	await process_frame


func _max_step(b: PackedVector2Array, from: int = 2000) -> float:
	var m: float = 0.0
	for i in range(from + 1, b.size()):
		m = maxf(m, absf(b[i].x - b[i - 1].x))
	return m


func _exp_step() -> void:
	var res: Dictionary = {}
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = _sine(220.0, 1.0)
	root.add_child(p)
	p.play()
	await create_timer(0.3).timeout
	var base: float = _max_step(await _grab(0.4))
	res["baseline_max_step (sine 220 Hz, A=0.5)"] = snappedf(base, 0.0001)
	# 1) AudioStreamPlayer.volume_db hard step 0 -> -12 dB
	cap.clear_buffer()
	await create_timer(0.15).timeout
	p.volume_db = -12.0
	await create_timer(0.2).timeout
	res["AudioStreamPlayer.volume_db step -12dB: max_step / baseline"] = snappedf(_max_step(cap.get_buffer(cap.get_frames_available())) / base, 0.01)
	p.volume_db = 0.0
	await create_timer(0.3).timeout
	# 2) same as 60 fps ramp over 0.25 s
	cap.clear_buffer()
	for i in 15:
		p.volume_db = -12.0 * float(i + 1) / 15.0
		await process_frame
		await create_timer(0.016).timeout
	await create_timer(0.1).timeout
	res["AudioStreamPlayer.volume_db 15-step ramp: max_step / baseline"] = snappedf(_max_step(cap.get_buffer(cap.get_frames_available())) / base, 0.01)
	p.stop()
	# 3) AudioStreamSynchronized.set_sync_stream_volume hard step
	var sync: AudioStreamSynchronized = AudioStreamSynchronized.new()
	sync.stream_count = 1
	sync.set_sync_stream(0, _sine(220.0, 1.0))
	p.stream = sync
	p.volume_db = 0.0
	p.play()
	await create_timer(0.3).timeout
	cap.clear_buffer()
	await create_timer(0.15).timeout
	sync.set_sync_stream_volume(0, -12.0)
	await create_timer(0.2).timeout
	res["AudioStreamSynchronized.set_sync_stream_volume step -12dB: max_step / baseline"] = snappedf(_max_step(cap.get_buffer(cap.get_frames_available())) / base, 0.01)
	# 4) bus volume hard step
	p.stop()
	p.stream = _sine(220.0, 1.0)
	p.bus = SndBus.SFX
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SndBus.SFX), 0.0)
	p.play()
	await create_timer(0.3).timeout
	cap.clear_buffer()
	await create_timer(0.15).timeout
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SndBus.SFX), -12.0)
	await create_timer(0.2).timeout
	res["AudioServer.set_bus_volume_db step -12dB: max_step / baseline"] = snappedf(_max_step(cap.get_buffer(cap.get_frames_available())) / base, 0.01)
	out["volume_change_clicks"] = res
	p.queue_free()
	await process_frame


func _save(b: PackedVector2Array, path: String) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(b.size() * 4)
	for i in b.size():
		bytes.encode_s16(i * 4, int(clampf(b[i].x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(b[i].y, -1.0, 1.0) * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = SR
	w.data = bytes
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	out["saved_" + path.get_file()] = w.save_to_wav(path)


func _exp_seam() -> void:
	var entry: Dictionary = {}
	var map: SndEventMap = SndEventMap.new()
	map.load_file("res://data/audio_events.json")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SndBus.MUSIC), 0.0)
	var d: SndMusicDirector = SndMusicDirector.new()
	root.add_child(d)
	await process_frame
	d.load_track(&"combat_tense", map.music["combat_tense"])
	d.intensity = 1.0
	d.load_track(&"combat_tense", map.music["combat_tense"])  # re-load so smoothing state starts at the target
	var start: float = d.length() - 1.0
	cap.clear_buffer()
	d.play(start)
	await create_timer(2.6).timeout
	var b: PackedVector2Array = cap.get_buffer(cap.get_frames_available())
	out["seam_capture_frames"] = b.size()
	out["seam_play_from_s"] = snappedf(start, 0.0001)
	_save(b, "res://analysis/capture/seam_combat.wav")
	d.stop()
