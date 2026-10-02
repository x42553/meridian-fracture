class_name SndBus
extends RefCounted
## Bus layout: Master(HardLimiter) <- Music(sidechain-ducked by Voice) / Sfx / Ambience / Ui / Voice.
## Built in code (idempotent) so the layout is data-reviewable and identical on every platform.

const MUSIC: StringName = &"Music"
const SFX: StringName = &"Sfx"
const AMBIENCE: StringName = &"Ambience"
const UI: StringName = &"Ui"
const VOICE: StringName = &"Voice"

## name -> default volume (dB). Music sits under SFX; the announcer is the loudest element.
const LAYOUT: Dictionary = {&"Music": -6.0, &"Sfx": -2.0, &"Ambience": -8.0, &"Ui": -2.0, &"Voice": 0.0}


## Ducking defaults: measured -8.5 dB with (-24 dB, 4:1) on -8 dB noise, but about -15 dB with real announcer lines (-18 LUFS speech),
## so the default is gentler: (-18 dB, 3:1).
static func setup(duck_music_threshold_db: float = -18.0, duck_ratio: float = 3.0) -> void:
	for name: StringName in LAYOUT:
		var idx: int = AudioServer.get_bus_index(name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, float(LAYOUT[name]))
	var master: int = 0
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.pre_gain_db = 0.0
		lim.release = 0.1
		AudioServer.add_bus_effect(master, lim)
	var mi: int = AudioServer.get_bus_index(MUSIC)
	if AudioServer.get_bus_effect_count(mi) == 0:
		AudioServer.add_bus_effect(mi, make_duck(VOICE, duck_music_threshold_db, duck_ratio))


## Compressor keyed by another bus: the classic "music ducks under the announcer" without any per-frame code.
static func make_duck(key_bus: StringName, threshold_db: float, ratio: float) -> AudioEffectCompressor:
	var c: AudioEffectCompressor = AudioEffectCompressor.new()
	c.sidechain = key_bus
	c.threshold = threshold_db
	c.ratio = ratio
	c.attack_us = 12000.0
	c.release_ms = 450.0
	c.gain = 0.0
	c.mix = 1.0
	return c
