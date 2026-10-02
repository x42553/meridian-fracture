extends SceneTree
## Import + decode verification. Run: Godot --headless --path prototypes/audio --script res://tests/t_import.gd
## Checks every generated OGG: imports as AudioStreamOggVorbis, sample-exact length, loop/BPM metadata round-trip, offline decode
## throughput (AudioStreamPlayback.mix_audio) for OGG mono/stereo, QOA and PCM, and loop-seam continuity of the music stems.

var fails: int = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL  ", msg)


func _decode_speed(label: String, s: AudioStream, seconds: float) -> Dictionary:
	var pb: AudioStreamPlayback = s.instantiate_playback()
	pb.start(0.0)
	var frames: int = int(seconds * 44100.0)
	var got: int = 0
	var acc: float = 0.0
	var t0: int = Time.get_ticks_usec()
	while got < frames:
		var buf: PackedVector2Array = pb.mix_audio(1.0, 1024)
		if buf.is_empty():
			break
		for i in range(0, buf.size(), 64):
			acc += absf(buf[i].x)
		got += buf.size()
	var dt: float = float(Time.get_ticks_usec() - t0) * 1e-6
	return {"label": label, "audio_s": snappedf(float(got) / 44100.0, 0.01), "decode_ms": snappedf(dt * 1000.0, 0.1),
		"x_realtime": snappedf((float(got) / 44100.0) / maxf(dt, 1e-6), 1.0), "cpu_pct_per_voice": snappedf(100.0 * dt / (float(got) / 44100.0), 0.001), "probe": snappedf(acc, 0.01)}


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/audio_manifest.json"))
	var ok: int = 0
	var worst_ms: float = 0.0
	var worst_name: String = ""
	var t0: int = Time.get_ticks_usec()
	for rel: String in manifest:
		var s: Resource = load("res://assets/audio/" + rel)
		check(s is AudioStreamOggVorbis, "type of %s is %s" % [rel, s])
		if not (s is AudioStreamOggVorbis):
			continue
		var d_ms: float = absf((s as AudioStream).get_length() - float(manifest[rel]["duration_s"])) * 1000.0
		if d_ms > worst_ms:
			worst_ms = d_ms
			worst_name = rel
		check(d_ms < 1.5, "length mismatch %s: %.3f ms" % [rel, d_ms])
		ok += 1
	print("IMPORT   %d/%d OGG assets load as AudioStreamOggVorbis in %.0f ms; worst length error %.4f ms (%s)" % [
		ok, manifest.size(), float(Time.get_ticks_usec() - t0) / 1000.0, worst_ms, worst_name])

	# --- loop flag / tempo metadata round trip on a duplicate (never mutate the cached resource)
	var drums: AudioStreamOggVorbis = (load("res://assets/audio/music/combat_tense/drums.ogg") as AudioStreamOggVorbis).duplicate()
	check(not drums.loop, "imported default loop must be false")
	drums.loop = true
	drums.bpm = 140.0
	drums.beat_count = 128
	drums.bar_beats = 4
	check(drums.has_loop() and is_equal_approx(drums.bpm, 140.0) and drums.beat_count == 128, "loop/bpm round trip")
	print("META     loop=%s bpm=%s beat_count=%d bar_beats=%d length=%.4fs (expected 54.8571)" % [drums.loop, drums.bpm, drums.beat_count, drums.bar_beats, drums.get_length()])

	# --- runtime load path (works from res:// and from PCK)
	var raw: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file("res://assets/audio/ui/ui_click.ogg")
	check(raw != null and absf(raw.get_length() - 0.16) < 0.002, "AudioStreamOggVorbis.load_from_file")

	# --- WAV: imported (default QOA) vs raw PCM
	var qoa: AudioStreamWAV = load("res://assets/wav_test/engine_tracked_loop.wav")
	var pcm: AudioStreamWAV = AudioStreamWAV.load_from_file("res://assets/wav_test/engine_tracked_loop.wav")
	print("WAV      imported: format=%d (0=8bit 1=16bit 2=IMA-ADPCM 3=QOA) bytes=%d stereo=%s | raw load_from_file: format=%d bytes=%d" % [qoa.format, qoa.data.size(), qoa.stereo, pcm.format, pcm.data.size()])
	check(qoa.format == AudioStreamWAV.FORMAT_QOA, "default WAV import should be QOA in 4.7")

	# --- offline decode cost per voice (10 s of audio each)
	var rows: Array[Dictionary] = []
	rows.append(_decode_speed("ogg mono   (engine_tracked)", (load("res://assets/audio/vehicles/engine_tracked_loop.ogg") as AudioStreamOggVorbis).duplicate(), 10.0))
	rows.append(_decode_speed("ogg stereo (heli_rotor)", (load("res://assets/audio/air/heli_rotor_loop.ogg") as AudioStreamOggVorbis).duplicate(), 10.0))
	rows.append(_decode_speed("ogg stereo (music stem)", drums, 10.0))
	rows.append(_decode_speed("qoa mono", qoa, 10.0))
	rows.append(_decode_speed("pcm16 mono", pcm, 10.0))
	for r in rows:
		print("DECODE   ", JSON.stringify(r))

	# --- loop seam continuity inside the engine: decode across the loop point of every music stem
	for tr: String in ["combat_tense", "calm_buildup"]:
		for stem: String in ["drums", "bass", "pads", "lead"]:
			var st: AudioStreamOggVorbis = (load("res://assets/audio/music/%s/%s.ogg" % [tr, stem]) as AudioStreamOggVorbis).duplicate()
			st.loop = true
			var n: int = int(round(st.get_length() * 44100.0))
			var pb: AudioStreamPlayback = st.instantiate_playback()
			pb.start(maxf(0.0, st.get_length() - 0.5))
			var frames: PackedVector2Array = PackedVector2Array()
			while frames.size() < 44100:
				var b: PackedVector2Array = pb.mix_audio(1.0, 1024)
				if b.is_empty():
					break
				frames.append_array(b)
			var seam: int = int(round(0.5 * 44100.0)) if false else n - int(round((st.get_length() - 0.5) * 44100.0))
			var jump: float = (frames[seam] - frames[seam - 1]).length()
			var deltas: PackedFloat32Array = PackedFloat32Array()
			for i in range(1, frames.size()):
				deltas.append((frames[i] - frames[i - 1]).length())
			var sorted: PackedFloat32Array = deltas.duplicate()
			sorted.sort()
			var p99: float = sorted[int(sorted.size() * 0.99)]
			var ratio: float = jump / maxf(p99, 1e-6)
			print("SEAM     %s/%s frames=%d seam@%d jump=%.5f p99_step=%.5f ratio=%.2f" % [tr, stem, n, seam, jump, p99, ratio])
			check(ratio < 2.5, "engine loop seam click %s/%s ratio %.2f" % [tr, stem, ratio])

	# --- AudioStreamInteractive API smoke (bar-synced transitions between whole tracks)
	var inter: AudioStreamInteractive = AudioStreamInteractive.new()
	inter.clip_count = 2
	inter.set_clip_name(0, &"calm")
	inter.set_clip_stream(0, load("res://assets/audio/music/calm_buildup/pads.ogg"))
	inter.set_clip_name(1, &"combat")
	inter.set_clip_stream(1, load("res://assets/audio/music/combat_tense/pads.ogg"))
	inter.add_transition(0, 1, AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR, AudioStreamInteractive.TRANSITION_TO_TIME_START, AudioStreamInteractive.FADE_CROSS, 2.0)
	check(inter.has_transition(0, 1), "AudioStreamInteractive transition")
	print("INTERACT clip_count=%d has_transition(0,1)=%s" % [inter.clip_count, inter.has_transition(0, 1)])

	print("T_IMPORT %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
