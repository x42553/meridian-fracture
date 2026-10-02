class_name SndBus
extends RefCounted
## Builds and verifies the bus layout of audio spec 4.1 from `mix.json` (idempotent; never removes foreign buses).
## Index order is the reference order: every send goes to a lower index and the two hidden ducking keys sit at the top.

const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const SFX: StringName = &"Sfx"
const AMBIENCE: StringName = &"Ambience"
const UI: StringName = &"Ui"
const VOICE: StringName = &"Voice"
const ANNOUNCER: StringName = &"Announcer"
const SFX_HEAVY: StringName = &"SfxHeavy"

static var _layout: Array = []  ## the bus dictionaries of the last successful setup (for verify)


static func setup(mix: SndMixConfig) -> bool:
	var spec: Array = mix.buses
	if spec.is_empty():
		return false
	_layout = spec
	for i: int in spec.size():
		var b: Dictionary = spec[i]
		var name: StringName = StringName(str(b.get("name", "")))
		if name == &"":
			return false
		var idx: int = AudioServer.get_bus_index(name)
		var created: bool = false
		if idx < 0:
			AudioServer.add_bus(mini(i, AudioServer.bus_count))
			idx = mini(i, AudioServer.bus_count - 1)
			AudioServer.set_bus_name(idx, String(name))
			created = true
		if idx != i and name != MASTER and i < AudioServer.bus_count:
			AudioServer.move_bus(idx, i)
			idx = i
		if name != MASTER:
			AudioServer.set_bus_send(idx, StringName(str(b.get("send", "Master"))))
		if created:
			AudioServer.set_bus_volume_db(idx, float(b.get("volume_db", 0.0)))
		_ensure_effects(idx, b.get("effects", []))
	return true


static func _ensure_effects(idx: int, effects: Array) -> void:
	var ok: bool = AudioServer.get_bus_effect_count(idx) == effects.size()
	if ok:
		for i: int in effects.size():
			if _type_of(AudioServer.get_bus_effect(idx, i)) != str((effects[i] as Dictionary).get("type", "")):
				ok = false
				break
	if not ok:
		while AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.remove_bus_effect(idx, 0)
		for e: Variant in effects:
			AudioServer.add_bus_effect(idx, _make_effect(e as Dictionary))
	for i: int in effects.size():
		var ed: Dictionary = effects[i]
		_configure(AudioServer.get_bus_effect(idx, i), ed)
		AudioServer.set_bus_effect_enabled(idx, i, bool(ed.get("enabled", true)))


static func _type_of(fx: AudioEffect) -> String:
	if fx is AudioEffectCompressor:
		return "compressor"
	if fx is AudioEffectLowPassFilter:
		return "lowpass"
	if fx is AudioEffectHardLimiter:
		return "hard_limiter"
	return "unknown"


static func _make_effect(ed: Dictionary) -> AudioEffect:
	match str(ed.get("type", "")):
		"compressor":
			return AudioEffectCompressor.new()
		"lowpass":
			return AudioEffectLowPassFilter.new()
		_:
			return AudioEffectHardLimiter.new()


static func _configure(fx: AudioEffect, ed: Dictionary) -> void:
	if fx is AudioEffectCompressor:
		var c: AudioEffectCompressor = fx
		c.threshold = float(ed.get("threshold_db", 0.0))
		c.ratio = float(ed.get("ratio", 4.0))
		c.attack_us = float(ed.get("attack_us", 20.0))
		c.release_ms = float(ed.get("release_ms", 250.0))
		c.gain = float(ed.get("gain_db", 0.0))
		c.sidechain = StringName(str(ed.get("sidechain", "")))
	elif fx is AudioEffectLowPassFilter:
		(fx as AudioEffectLowPassFilter).cutoff_hz = float(ed.get("cutoff_hz", 1200.0))
	elif fx is AudioEffectHardLimiter:
		var l: AudioEffectHardLimiter = fx
		l.ceiling_db = float(ed.get("ceiling_db", -1.0))
		l.pre_gain_db = float(ed.get("pre_gain_db", 0.0))
		l.release = float(ed.get("release", 0.1))


static func bus_index(name: StringName) -> int:
	return AudioServer.get_bus_index(name)


## Index of the effect with the mix.json id on a bus (position inside the bus's effect list), -1 when unknown.
static func effect_index(bus: StringName, effect_id: StringName) -> int:
	for b: Variant in _layout:
		if StringName(str((b as Dictionary).get("name", ""))) != bus:
			continue
		var effects: Array = (b as Dictionary).get("effects", [])
		for i: int in effects.size():
			if StringName(str((effects[i] as Dictionary).get("id", ""))) == effect_id:
				return i
	return -1


## Violations of the reference layout (empty = fine): index order, sends, sidechain names, limiter last on Master.
static func verify() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in _layout.size():
		var b: Dictionary = _layout[i]
		var name: StringName = StringName(str(b.get("name", "")))
		var idx: int = AudioServer.get_bus_index(name)
		if idx != i:
			out.append("bus %s at index %d, expected %d" % [str(name), idx, i])
			continue
		if name != MASTER:
			var send: StringName = AudioServer.get_bus_send(idx)
			var want: StringName = StringName(str(b.get("send", "Master")))
			if send != want:
				out.append("bus %s sends to %s, expected %s" % [str(name), str(send), str(want)])
			if AudioServer.get_bus_index(send) >= idx:
				out.append("bus %s sends to a higher index" % str(name))
		var effects: Array = b.get("effects", [])
		if AudioServer.get_bus_effect_count(idx) != effects.size():
			out.append("bus %s has %d effects, expected %d" % [str(name), AudioServer.get_bus_effect_count(idx), effects.size()])
			continue
		for e: int in effects.size():
			var fx: AudioEffect = AudioServer.get_bus_effect(idx, e)
			var ed: Dictionary = effects[e]
			if fx is AudioEffectCompressor:
				var sc: StringName = (fx as AudioEffectCompressor).sidechain
				if sc != StringName(str(ed.get("sidechain", ""))):
					out.append("bus %s effect %d sidechain %s" % [str(name), e, str(sc)])
				if absf((fx as AudioEffectCompressor).threshold - float(ed.get("threshold_db", 0.0))) > 0.01:
					out.append("bus %s effect %d threshold" % [str(name), e])
		if name == MASTER and effects.size() > 0:
			var last: AudioEffect = AudioServer.get_bus_effect(idx, effects.size() - 1)
			if not (last is AudioEffectHardLimiter):
				out.append("Master: limiter is not the last effect")
	return out
