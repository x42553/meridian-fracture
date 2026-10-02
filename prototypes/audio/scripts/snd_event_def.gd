class_name SndEventDef
extends RefCounted
## One resolved audio event, parsed from data/audio_events.json by SndEventMap.
## Immutable after load except for the bookkeeping fields at the bottom, which SndVoicePool owns.

enum Spatial { UI, GLOBAL, WORLD_3D }
enum Steal { NONE, OLDEST, QUIETEST }

var id: StringName = &""
var category: StringName = &""
var bus: StringName = &"Sfx"
## 0..100. Higher priority survives voice stealing; UI/announcer sit at 90+, ambience at ~10.
var priority: int = 50
var streams: Array[AudioStream] = []
var weights: PackedFloat32Array = PackedFloat32Array()
var volume_db: float = 0.0
var volume_jitter_db: float = 0.0
var pitch: float = 1.0
var pitch_jitter_semitones: float = 0.0
var spatial: Spatial = Spatial.WORLD_3D
## Distance (m) at which attenuation is 0 dB (Godot: gain = unit_size / distance for INVERSE_DISTANCE).
var unit_size: float = 30.0
## Hard cull distance (m); 0 = unlimited. Beyond it the pool does not even start the voice.
var max_distance: float = 250.0
var attenuation: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
var lowpass_hz: float = 20500.0
var panning_strength: float = 1.0
## Optional shared limit bucket (see "groups" in the JSON).
var group: StringName = &""
var max_instances: int = 8
var min_interval_ms: int = 0
var steal: Steal = Steal.OLDEST
var loop: bool = false
## Voices whose estimated level (volume + distance attenuation) is below this are never started.
var cull_below_db: float = -50.0

# --- runtime bookkeeping, owned by SndVoicePool ---
var active_count: int = 0
var last_play_ms: int = -1000000
var _last_variant: int = -1


## Weighted random variant that never repeats the previous pick (when more than one exists).
func pick_variant(rng: RandomNumberGenerator) -> int:
	var n: int = streams.size()
	if n <= 1:
		return 0
	var total: float = 0.0
	for i in n:
		if i != _last_variant:
			total += weights[i]
	var r: float = rng.randf() * total
	for i in n:
		if i == _last_variant:
			continue
		r -= weights[i]
		if r <= 0.0:
			_last_variant = i
			return i
	_last_variant = 0 if _last_variant != 0 else n - 1
	return _last_variant
