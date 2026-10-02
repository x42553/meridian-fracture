extends Control
## Live audio monitor + scripted demo. Exercises the whole stack (bus layout, event map, voice pool, stem music, announcer)
## and draws the engine's own analysis: master spectrum, bus peaks, stem levels, voice-slot occupancy.
## CLI (after "--"):  shot=<png>  frames=<n>   (screenshot after n frames, then quit)

const BG: Color = Color("0d0f14")
const PANEL: Color = Color("161a22")
const EDGE: Color = Color("2a3140")
const TXT: Color = Color("d7dde8")
const DIM: Color = Color("7d889c")
const ACCENT: Color = Color("38d0c0")
const STEM_COLORS: Array[Color] = [Color("ff8a3d"), Color("b06cff"), Color("3d9bff"), Color("ffd23d")]
const BUS_NAMES: Array[StringName] = [&"Master", &"Music", &"Sfx", &"Ambience", &"Ui", &"Voice"]
const BANDS: int = 42
const F_LO: float = 50.0
const F_HI: float = 16000.0

var _map: SndEventMap
var _pool: SndVoicePool
var _music: SndMusicDirector
var _ann: SndAnnouncer
var _spec: AudioEffectSpectrumAnalyzerInstance
var _bands: PackedFloat32Array = PackedFloat32Array()
var _hist: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t: float = 0.0
var _frame: int = 0
var _next_fire: float = 0.0
var _shot: String = ""
var _shot_frame: int = 300
var _said: Dictionary = {}
var _last_ev: String = ""
var _log: PackedStringArray = PackedStringArray()

const FIRE_TABLE: Array = [
	[&"weapon.rifle.fire", 9.0], [&"weapon.autocannon.fire", 3.0], [&"weapon.cannon_heavy.fire", 3.0], [&"impact.explosion_small", 3.0],
	[&"weapon.missile.fire", 1.5], [&"impact.explosion_large", 0.8], [&"weapon.rail.fire", 1.0], [&"structure.collapse", 0.25], [&"air.jet.flyby", 0.3]]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			_shot = a.substr(5)
		elif a.begins_with("frames="):
			_shot_frame = int(a.substr(7))
	_rng.seed = 7
	var cam: Camera3D = Camera3D.new()  # required by AudioStreamPlayer3D (AudioListener3D alone is silent)
	add_child(cam)
	cam.make_current()
	SndBus.setup()
	var sa: AudioEffectSpectrumAnalyzer = AudioEffectSpectrumAnalyzer.new()
	sa.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_4096  # 10.8 Hz bins: 2048 cannot resolve the lowest log bands
	sa.buffer_length = 0.5
	AudioServer.add_bus_effect(0, sa)
	_spec = AudioServer.get_bus_effect_instance(0, AudioServer.get_bus_effect_count(0) - 1) as AudioEffectSpectrumAnalyzerInstance
	_map = SndEventMap.new()
	if not _map.load_file("res://data/audio_events.json"):
		push_error("event map errors: %s" % ", ".join(_map.errors))
	_pool = SndVoicePool.new()
	add_child(_pool)
	_pool.setup(_map, 48, 16, 3)
	_music = SndMusicDirector.new()
	add_child(_music)
	_music.load_track(&"combat_tense", _map.music["combat_tense"])
	_music.play()
	_ann = SndAnnouncer.new()
	add_child(_ann)
	_ann.setup(_map)
	_bands.resize(BANDS)
	_hist.resize(220)
	_hist.fill(-80.0)
	_pool.play(&"ambience.wind")
	_pool.play(&"ambience.city")


func _process(delta: float) -> void:
	_t += delta
	_frame += 1
	_music.intensity = clampf(_t / 5.0, 0.0, 1.0)
	if _t >= _next_fire:
		_next_fire = _t + 0.05 + 0.06 * _rng.randf()
		var total: float = 0.0
		for row: Array in FIRE_TABLE:
			total += float(row[1])
		var r: float = _rng.randf() * total
		for row: Array in FIRE_TABLE:
			r -= float(row[1])
			if r <= 0.0:
				var ang: float = _rng.randf() * TAU
				var dist: float = 8.0 + 260.0 * pow(_rng.randf(), 1.6)
				var h: int = _pool.play(row[0], Vector3(cos(ang) * dist, 0.0, sin(ang) * dist))
				_last_ev = String(row[0])
				_log.append("%-26s %4.0f m   %s" % [row[0], dist, "play" if h > 0 else "cull"])
				if _log.size() > 5:
					_log.remove_at(0)
				break
	if not _said.has(1) and _t > 1.0:
		_said[1] = true
		_ann.say(&"construction_complete", 50)
	if not _said.has(2) and _t > 3.8:
		_said[2] = true
		_ann.say(&"base_under_attack", 92)
	var floor_db: float = -70.0
	for i in BANDS:
		var lo: float = F_LO * pow(F_HI / F_LO, float(i) / BANDS)
		var hi: float = F_LO * pow(F_HI / F_LO, float(i + 1) / BANDS)
		var m: float = _spec.get_magnitude_for_frequency_range(lo, hi, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var db: float = maxf(linear_to_db(m), floor_db)
		_bands[i] = maxf(db, _bands[i] - 60.0 * delta)
	_hist.remove_at(0)
	_hist.append(AudioServer.get_bus_peak_volume_left_db(0, 0))
	queue_redraw()
	if _shot != "" and _frame == _shot_frame:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


func _text(p: Vector2, s: String, size: int = 14, col: Color = TXT) -> void:
	draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2, title: String) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 1.0)
	_text(r.position + Vector2(12, 20), title, 13, DIM)


func _draw() -> void:
	var W: float = size.x
	var H: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_text(Vector2(24, 34), "MERIDIAN FRACTURE  -  AUDIO MONITOR", 20, TXT)
	_text(Vector2(24, 54), "renderer: %s   driver: %s   mix: %d Hz   latency: %.1f ms" % [
		RenderingServer.get_current_rendering_method(), AudioServer.get_driver_name(), int(AudioServer.get_mix_rate()), AudioServer.get_output_latency() * 1000.0], 12, DIM)
	# --- spectrum
	var sp: Rect2 = Rect2(24, 74, W * 0.62 - 36, 250)
	_panel(sp, "MASTER SPECTRUM (engine AudioEffectSpectrumAnalyzer, 50 Hz - 16 kHz, log)")
	var bw: float = (sp.size.x - 24.0) / BANDS
	for i in BANDS:
		var h: float = clampf((_bands[i] + 70.0) / 70.0, 0.0, 1.0) * (sp.size.y - 64.0)
		var c: Color = ACCENT.lerp(Color("ff5d73"), clampf((_bands[i] + 30.0) / 30.0, 0.0, 1.0))
		draw_rect(Rect2(sp.position.x + 12 + i * bw + 1, sp.end.y - 24 - h, bw - 2, h), c)
	for fl: Array in [[100.0, "100"], [1000.0, "1k"], [10000.0, "10k"]]:
		var fx: float = sp.position.x + 12 + log(float(fl[0]) / F_LO) / log(F_HI / F_LO) * (sp.size.x - 24.0)
		draw_line(Vector2(fx, sp.end.y - 23), Vector2(fx, sp.end.y - 19), DIM)
		_text(Vector2(fx - 8, sp.end.y - 7), String(fl[1]), 10, DIM)
	# --- master peak history
	var hp: Rect2 = Rect2(24, 336, W * 0.62 - 36, 96)
	_panel(hp, "MASTER PEAK HISTORY (dBFS, after HardLimiter -1 dB)")
	var hw: float = (hp.size.x - 24.0) / _hist.size()
	for i in _hist.size():
		var v: float = clampf((_hist[i] + 60.0) / 60.0, 0.0, 1.0)
		draw_rect(Rect2(hp.position.x + 12 + i * hw, hp.end.y - 10 - v * (hp.size.y - 36), maxf(hw, 1.0), v * (hp.size.y - 36)), Color("3d9bff"))
	# --- voice slots
	var vp: Rect2 = Rect2(24, 448, W * 0.62 - 36, 128)
	_panel(vp, "VOICE POOL  %d / 64 active   played %d  stolen %d  cull(dist %d, level %d, rate %d, limit %d)" % [
		_pool.active_voices(), _pool.stats["played"], _pool.stats["stolen"], _pool.stats["cull_distance"], _pool.stats["cull_audibility"], _pool.stats["cull_interval"], _pool.stats["cull_limit"]])
	var snap: Array[Dictionary] = _pool.snapshot_3d()
	var cols: int = 24
	var cw: float = (vp.size.x - 24.0) / cols
	for i in snap.size():
		var cell: Rect2 = Rect2(vp.position.x + 12 + (i % cols) * cw + 1, vp.position.y + 34 + (i / cols) * (cw + 2), cw - 3, cw - 3)
		if snap[i]["busy"]:
			var pr: float = float(snap[i]["priority"]) / 100.0
			draw_rect(cell, Color.from_hsv(0.08 + 0.55 * pr, 0.75, 0.55 + 0.45 * clampf((float(snap[i]["est_db"]) + 40.0) / 40.0, 0.0, 1.0)))
		else:
			draw_rect(cell, Color("1f2430"))
	_text(vp.position + Vector2(12, vp.size.y - 10), "cell hue = priority (orange low .. green .. blue high), brightness = level after distance attenuation", 11, DIM)
	var lp: Rect2 = Rect2(24, 588, W * 0.62 - 36, H - 588 - 24)
	_panel(lp, "EVENT LOG (newest last)  - requests routed through SndVoicePool.play()")
	for i in _log.size():
		_text(lp.position + Vector2(12, 40 + i * 14), _log[i], 12, ACCENT if _log[i].ends_with("play") else Color("ff8a8a"))
	# --- stems
	var mp: Rect2 = Rect2(W * 0.62 + 4, 74, W * 0.38 - 28, 250)
	_panel(mp, "STEM LAYERS  intensity %.2f  bar %.1f  %.0f bpm" % [_music.intensity, _music.bar_position(), _music.bpm])
	for i in SndMusicDirector.STEMS.size():
		var x: float = mp.position.x + 24 + i * (mp.size.x - 40) / 4.0
		var bwid: float = (mp.size.x - 40) / 4.0 - 16
		var lvl: float = clampf((_music.layer_db[i] + 60.0) / 60.0, 0.0, 1.0)
		draw_rect(Rect2(x, mp.position.y + 40, bwid, mp.size.y - 84), Color("1f2430"))
		draw_rect(Rect2(x, mp.end.y - 44 - lvl * (mp.size.y - 84), bwid, lvl * (mp.size.y - 84)), STEM_COLORS[i])
		_text(Vector2(x, mp.end.y - 26), String(SndMusicDirector.STEMS[i]), 13, TXT)
		_text(Vector2(x, mp.end.y - 10), "%.0f dB" % _music.layer_db[i], 11, DIM)
	# --- buses
	var bp: Rect2 = Rect2(W * 0.62 + 4, 336, W * 0.38 - 28, H - 336 - 24)
	_panel(bp, "BUS PEAKS (dBFS)   announcer: %s" % ("speaking" if _ann.is_speaking() else "idle"))
	for i in BUS_NAMES.size():
		var bi: int = AudioServer.get_bus_index(BUS_NAMES[i])
		var pk: float = AudioServer.get_bus_peak_volume_left_db(bi, 0)
		var y: float = bp.position.y + 44 + i * 34
		_text(Vector2(bp.position.x + 12, y + 12), String(BUS_NAMES[i]), 13, TXT)
		draw_rect(Rect2(bp.position.x + 110, y, bp.size.x - 190, 16), Color("1f2430"))
		draw_rect(Rect2(bp.position.x + 110, y, (bp.size.x - 190) * clampf((pk + 60.0) / 60.0, 0.0, 1.0), 16), ACCENT if i else Color("ff5d73"))
		_text(Vector2(bp.end.x - 70, y + 12), "%5.1f" % maxf(pk, -99.9), 12, DIM)
