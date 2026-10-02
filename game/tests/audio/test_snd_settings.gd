extends RefCounted
## Settings: slider curve, ConfigFile round trip with the qa.md key names, flat-dictionary import, unknown keys.


func test_slider_curve(t: TestCtx) -> void:
	t.near(SndSettings.slider_to_linear(100), 1.0, 0.0001, "100 -> 1.0")
	t.near(linear_to_db(SndSettings.slider_to_linear(50)), -12.04, 0.05, "50 -> -12.04 dB")
	t.eq(SndSettings.slider_to_linear(0), 0.0, "0 -> exactly 0 (mute)")
	t.near(SndSettings.slider_to_db(70, -6.0), -12.2, 0.1, "music 70 on a -6 dB bus -> -12.2 dB")
	t.eq(SndSettings.slider_to_db(0, -6.0), SndConfig.SILENT_DB, "muted slider is -80")


func test_config_round_trip(t: TestCtx) -> void:
	var s: SndSettings = SndSettings.new()
	s.master = 40
	s.music = 55
	s.announcer_mode = SndSettings.ANN_COMPUTER
	s.unit_voice_mode = SndSettings.UV_MIXED
	s.music_mode = SndSettings.MUSIC_CALM_ONLY
	s.dynamic_range = SndSettings.DR_NIGHT
	s.quality = SndSettings.Q_HIGH
	s.mute_unfocused = false
	s.captions = false
	s.output_device = "Speakers"
	s.announcer_tts = true
	var cfg: ConfigFile = ConfigFile.new()
	s.save_to(cfg)
	t.eq(int(cfg.get_value("audio", "master")), 40, "audio/master key")
	t.eq(bool(cfg.get_value("audio", "mute_unfocused")), false, "audio/mute_unfocused key")
	t.eq(bool(cfg.get_value("audio", "captions")), false, "audio/captions key")
	t.eq(bool(cfg.get_value("access", "announcer_tts")), true, "access/announcer_tts key")
	var s2: SndSettings = SndSettings.new()
	s2.load_from(cfg)
	t.eq(s2.master, 40, "master")
	t.eq(s2.music, 55, "music")
	t.eq(s2.announcer_mode, SndSettings.ANN_COMPUTER, "announcer")
	t.eq(s2.unit_voice_mode, SndSettings.UV_MIXED, "unit voices")
	t.eq(s2.music_mode, SndSettings.MUSIC_CALM_ONLY, "music mode")
	t.eq(s2.dynamic_range, SndSettings.DR_NIGHT, "dynamic range")
	t.eq(s2.quality, SndSettings.Q_HIGH, "quality")
	t.eq(s2.output_device, "Speakers", "device")
	t.check(s2.announcer_tts, "tts")
	t.check(not s2.captions and not s2.mute_unfocused, "bools")


func test_unknown_and_missing_keys(t: TestCtx) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "master", 20)
	cfg.set_value("audio", "no_such_key", 5)
	cfg.set_value("weird", "x", 1)
	var s: SndSettings = SndSettings.new()
	s.load_from(cfg)
	t.eq(s.master, 20, "known key read")
	t.eq(s.music, 70, "missing key keeps its default")
	cfg.set_value("audio", "master", 500)
	s.load_from(cfg)
	t.eq(s.master, 100, "out-of-range clamps")


func test_values_from_the_settings_layer(t: TestCtx) -> void:
	var s: SndSettings = SndSettings.new()
	s.load_values({"audio/master": 33, "audio/announcer": 2, "access/announcer_tts": true, "audio/nonsense": 9, "video/fullscreen": true})
	t.eq(s.master, 33, "master from flat dict")
	t.eq(s.announcer_mode, SndSettings.ANN_OFF, "announcer")
	t.check(s.announcer_tts, "tts")
	t.eq(s.music, 70, "untouched keys keep values")
