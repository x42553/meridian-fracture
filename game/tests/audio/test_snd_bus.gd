extends RefCounted
## Bus layout: idempotent setup, verify(), ducking sidechains, limiter last on Master, fader ramps.


func _mix() -> SndMixConfig:
	return (SndTestKit.real()["store"] as SndDataStore).mix


func test_setup_is_idempotent_and_verifies(t: TestCtx) -> void:
	var mix: SndMixConfig = _mix()
	t.check(SndBus.setup(mix), "first setup")
	var count: int = AudioServer.bus_count
	var names: PackedStringArray = PackedStringArray()
	for i: int in count:
		names.append(AudioServer.get_bus_name(i))
	t.check(SndBus.setup(mix), "second setup")
	t.eq(AudioServer.bus_count, count, "no duplicate buses")
	for i: int in count:
		t.eq(AudioServer.get_bus_name(i), names[i], "same order %d" % i)
	t.eq(SndBus.verify().size(), 0, "verify(): %s" % str(SndBus.verify()))


func test_index_order_and_sends(t: TestCtx) -> void:
	SndBus.setup(_mix())
	t.gt(SndBus.bus_index(SndBus.ANNOUNCER), SndBus.bus_index(SndBus.MUSIC), "Announcer above Music")
	t.gt(SndBus.bus_index(SndBus.SFX_HEAVY), SndBus.bus_index(SndBus.MUSIC), "SfxHeavy above Music")
	t.eq(AudioServer.get_bus_send(SndBus.bus_index(SndBus.ANNOUNCER)), SndBus.VOICE, "Announcer sends to Voice")
	t.eq(AudioServer.get_bus_send(SndBus.bus_index(SndBus.SFX_HEAVY)), SndBus.SFX, "SfxHeavy sends to Sfx")
	t.eq(AudioServer.get_bus_send(SndBus.bus_index(SndBus.MUSIC)), SndBus.MASTER, "Music sends to Master")


func test_sidechains_and_limiter(t: TestCtx) -> void:
	SndBus.setup(_mix())
	var music: int = SndBus.bus_index(SndBus.MUSIC)
	var duck_ann: AudioEffectCompressor = AudioServer.get_bus_effect(music, SndBus.effect_index(SndBus.MUSIC, &"duck_ann")) as AudioEffectCompressor
	t.not_null(duck_ann, "duck_ann compressor")
	t.eq(duck_ann.sidechain, SndBus.ANNOUNCER, "sidechain name")
	t.near(duck_ann.threshold, -18.0, 0.01, "threshold")
	t.near(duck_ann.ratio, 3.0, 0.01, "ratio")
	var duck_heavy: AudioEffectCompressor = AudioServer.get_bus_effect(music, SndBus.effect_index(SndBus.MUSIC, &"duck_heavy")) as AudioEffectCompressor
	t.eq(duck_heavy.sidechain, SndBus.SFX_HEAVY, "heavy sidechain")
	var master: int = 0
	var last: AudioEffect = AudioServer.get_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	t.check(last is AudioEffectHardLimiter, "limiter is last on Master")
	t.near((last as AudioEffectHardLimiter).ceiling_db, -1.0, 0.01, "ceiling -1 dB")


func test_fader_ramps(t: TestCtx) -> void:
	SndBus.setup(_mix())
	var f: SndBusFader = SndBusFader.new()
	var idx: int = SndBus.bus_index(SndBus.SFX)
	AudioServer.set_bus_volume_db(idx, 0.0)
	f.set_target_db(SndBus.SFX, -30.0, 200)
	var prev: float = 0.0
	var max_step: float = 0.0
	for i: int in 30:
		f.update(1.0 / 60.0)
		var v: float = AudioServer.get_bus_volume_db(idx)
		max_step = maxf(max_step, absf(v - prev))
		prev = v
	t.near(prev, -30.0, 0.01, "reaches the target")
	t.le(max_step, 6.0, "never a single step larger than 6 dB (max %.2f)" % max_step)
	t.gt(max_step, 0.0, "it moved")
	AudioServer.set_bus_volume_db(idx, -2.0)
	# effect toggle: disabling waits for the ramp, enabling is immediate
	var mi: int = 0
	var mu: int = SndBus.effect_index(SndBus.MASTER, &"muffle")
	f.set_effect_enabled(SndBus.MASTER, &"muffle", true, 100)
	t.check(AudioServer.is_bus_effect_enabled(mi, mu), "enabled at once")
	f.set_effect_enabled(SndBus.MASTER, &"muffle", false, 100)
	t.check(AudioServer.is_bus_effect_enabled(mi, mu), "still on during the ramp")
	f.update(0.2)
	t.check(not AudioServer.is_bus_effect_enabled(mi, mu), "off after the ramp")
