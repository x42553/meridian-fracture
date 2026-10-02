class_name SndEventDef
extends RefCounted
## One resolved event of `events.json` (audio spec 4.3). Variants are kept as asset ids and resolved to streams lazily
## through the SndAssetIndex cache, so a definition costs no decoding until it is first heard.

enum Spatial { UI = 0, GLOBAL = 1, WORLD_3D = 2 }
enum Steal { NONE = 0, OLDEST = 1, QUIETEST = 2 }
enum Fog { HIDDEN = 0, MUFFLED = 1, AUDIBLE = 2 }
enum Atten { INVERSE = 0, INVERSE_SQUARE = 1, LOGARITHMIC = 2, NONE = 3 }

const SPATIAL_NAMES: PackedStringArray = ["ui", "global", "3d"]
const STEAL_NAMES: PackedStringArray = ["none", "oldest", "quietest"]
const FOG_NAMES: PackedStringArray = ["hidden", "muffled", "audible"]
const ATTEN_NAMES: PackedStringArray = ["inverse", "inverse_square", "logarithmic", "none"]

var id: StringName = &""
var index: int = 0
var category: StringName = &""
var bus: StringName = &"Sfx"
var bus_index: int = -1
var priority: int = 50
var var_ids: PackedStringArray = PackedStringArray()
var var_weights: PackedFloat32Array = PackedFloat32Array()
var flavour_ids: Dictionary = {}  ## StringName flavour -> PackedStringArray
var flavour_weights: Dictionary = {}  ## StringName flavour -> PackedFloat32Array
var volume_db: float = 0.0
var volume_jitter_db: float = 0.0
var pitch: float = 1.0
var pitch_jitter_semitones: float = 0.0
var spatial: int = Spatial.UI
var unit_size_m: float = 20.0
var max_distance_m: float = 0.0
var attenuation: int = Atten.INVERSE
var lowpass_hz: float = 20500.0
var panning_strength: float = 1.0
var doppler: bool = false
var propagation: bool = false
var fog: int = Fog.HIDDEN
var fog_gain_db: float = -9.0
var fog_lowpass_hz: float = 1200.0
var group: StringName = &""
var max_instances: int = 8
var min_interval_ms: int = 0
var steal: int = Steal.OLDEST
var loop: bool = false
var fade_in_ms: int = 0
var fade_out_ms: int = 0
var cull_below_db: float = -42.0
var link_loop: StringName = &""
var link_end: StringName = &""
var tags: PackedStringArray = PackedStringArray()
# bookkeeping owned by SndVoicePool
var active_count: int = 0
var last_play_ms: int = -1000000
var _last_variant: Dictionary = {}  ## flavour -> last picked index
var _index: SndAssetIndex = null


func attach_index(idx: SndAssetIndex) -> void:
	_index = idx


func is_3d() -> bool:
	return spatial == Spatial.WORLD_3D


## Picks a variant id: weighted, flavour list first, never the previous pick of the same flavour when more than one exists.
func pick_id(rng: RandomNumberGenerator, flavour: StringName = &"") -> String:
	var ids: PackedStringArray = var_ids
	var w: PackedFloat32Array = var_weights
	var key: StringName = &""
	if flavour != &"" and flavour_ids.has(flavour):
		ids = flavour_ids[flavour]
		w = flavour_weights[flavour]
		key = flavour
	var n: int = ids.size()
	if n == 0:
		return ""
	if n == 1:
		_last_variant[key] = 0
		return ids[0]
	var last: int = int(_last_variant.get(key, -1))
	var total: float = 0.0
	for i: int in n:
		if i != last:
			total += w[i]
	var r: float = rng.randf() * total
	var pick: int = -1
	for i: int in n:
		if i == last:
			continue
		pick = i
		r -= w[i]
		if r < 0.0:
			break
	_last_variant[key] = pick
	return ids[pick]


func pick_stream(rng: RandomNumberGenerator, flavour: StringName = &"") -> AudioStream:
	var vid: String = pick_id(rng, flavour)
	if vid == "" or _index == null:
		return null
	return _index.get_stream(vid, is_3d())
