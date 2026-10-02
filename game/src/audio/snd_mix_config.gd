class_name SndMixConfig
extends RefCounted
## Typed view of `mix.json` (audio spec 7.2). Quality-dependent sizes are picked by `apply_quality`.

const Q_LOW: int = 0
const Q_MEDIUM: int = 1
const Q_HIGH: int = 2

var raw: Dictionary = {}
var buses: Array = []
# pool
var voices_3d: int = 40
var voices_3d_by_quality: PackedInt32Array = [24, 40, 48]
var voices_2d: int = 16
var reserve_high_slots: int = 6
var reserve_high_priority: int = 70
var max_starts_per_frame: int = 24
var steal_margin: float = 1.0
var age_penalty_per_s: float = 1.0
var cull_below_db: float = -42.0
# camera
var ref_height_m: float = 55.0
var zoom_scale_min: float = 0.6
var zoom_scale_max: float = 2.0
var listener_height_m: float = 2.0
var source_height_ground_m: float = 1.5
var source_height_air_m: float = 22.0
var focus_smooth_s: float = 0.08
# hearing
var max_scan_m: float = 750.0
var loud_fog_radius_m: float = 300.0
var fog_muffled_gain_db: float = -9.0
var fog_muffled_lowpass_hz: float = 1200.0
var offscreen_alert_m: float = 45.0
var contact_ping: bool = false
# loops
var loops_budget: int = 12
var loops_budget_by_quality: PackedInt32Array = [8, 12, 16]
var loops_scan_period_s: float = 0.25
var loops_radius_m: float = 90.0
var loops_hysteresis_db: float = 3.0
var loops_fade_in_ms: int = 120
var loops_fade_out_ms: int = 200
var loops_pitch_lo: float = 0.85
var loops_pitch_hi: float = 1.15
var loops_max_candidates: int = 160
# propagation, sizes, replay, strategic
var speed_of_sound_mps: float = 900.0
var max_delay_ms: int = 400
var size_small: int = 819
var size_medium: int = 1536
var size_large: int = 2560
var replay_gate_priority: int = 80
var helios_length_cells: float = 16.0
var terrain_material: PackedInt32Array = PackedInt32Array()
var ambience: Dictionary = {}
var mix_rate: int = 44100
var output_latency_ms: int = 15


static func _num(d: Dictionary, k: String, dflt: float) -> float:
	var v: Variant = d.get(k, dflt)
	return float(v) if v is float or v is int else dflt


static func _int(d: Dictionary, k: String, dflt: int) -> int:
	var v: Variant = d.get(k, dflt)
	return int(v) if v is float or v is int else dflt


static func _quality_triple(d: Variant, dflt: PackedInt32Array) -> PackedInt32Array:
	if d is Dictionary:
		var dd: Dictionary = d
		return PackedInt32Array([int(dd.get("low", dflt[0])), int(dd.get("medium", dflt[1])), int(dd.get("high", dflt[2]))])
	return dflt


func load_dict(d: Dictionary) -> void:
	raw = d
	buses = d.get("buses", [])
	var eng: Dictionary = d.get("engine", {})
	mix_rate = _int(eng, "mix_rate", mix_rate)
	output_latency_ms = _int(eng, "output_latency_ms", output_latency_ms)
	var p: Dictionary = d.get("pool", {})
	voices_3d_by_quality = _quality_triple(p.get("voices_3d"), voices_3d_by_quality)
	voices_2d = _int(p, "voices_2d", voices_2d)
	reserve_high_slots = _int(p, "reserve_high_slots", reserve_high_slots)
	reserve_high_priority = _int(p, "reserve_high_priority", reserve_high_priority)
	max_starts_per_frame = _int(p, "max_starts_per_frame", max_starts_per_frame)
	steal_margin = _num(p, "steal_margin", steal_margin)
	age_penalty_per_s = _num(p, "age_penalty_per_s", age_penalty_per_s)
	cull_below_db = _num(p, "cull_below_db", cull_below_db)
	var c: Dictionary = d.get("camera", {})
	ref_height_m = _num(c, "ref_height_m", ref_height_m)
	zoom_scale_min = _num(c, "zoom_scale_min", zoom_scale_min)
	zoom_scale_max = _num(c, "zoom_scale_max", zoom_scale_max)
	listener_height_m = _num(c, "listener_height_m", listener_height_m)
	source_height_ground_m = _num(c, "source_height_ground_m", source_height_ground_m)
	source_height_air_m = _num(c, "source_height_air_m", source_height_air_m)
	focus_smooth_s = _num(c, "focus_smooth_s", focus_smooth_s)
	var h: Dictionary = d.get("hearing", {})
	max_scan_m = _num(h, "max_scan_m", max_scan_m)
	loud_fog_radius_m = _num(h, "loud_fog_radius_m", loud_fog_radius_m)
	fog_muffled_gain_db = _num(h, "fog_muffled_gain_db", fog_muffled_gain_db)
	fog_muffled_lowpass_hz = _num(h, "fog_muffled_lowpass_hz", fog_muffled_lowpass_hz)
	offscreen_alert_m = _num(h, "offscreen_alert_m", offscreen_alert_m)
	contact_ping = bool(h.get("contact_ping", false))
	var l: Dictionary = d.get("loops", {})
	loops_budget_by_quality = _quality_triple(l.get("budget"), loops_budget_by_quality)
	loops_scan_period_s = _num(l, "scan_period_s", loops_scan_period_s)
	loops_radius_m = _num(l, "radius_m", loops_radius_m)
	loops_hysteresis_db = _num(l, "hysteresis_db", loops_hysteresis_db)
	loops_fade_in_ms = _int(l, "fade_in_ms", loops_fade_in_ms)
	loops_fade_out_ms = _int(l, "fade_out_ms", loops_fade_out_ms)
	loops_pitch_lo = _num(l, "pitch_speed_lo", loops_pitch_lo)
	loops_pitch_hi = _num(l, "pitch_speed_hi", loops_pitch_hi)
	loops_max_candidates = _int(l, "max_candidates", loops_max_candidates)
	var pr: Dictionary = d.get("propagation", {})
	speed_of_sound_mps = _num(pr, "speed_mps", speed_of_sound_mps)
	max_delay_ms = _int(pr, "max_delay_ms", max_delay_ms)
	var st: Dictionary = d.get("size_thresholds_units", {})
	size_small = _int(st, "small", size_small)
	size_medium = _int(st, "medium", size_medium)
	size_large = _int(st, "large", size_large)
	replay_gate_priority = _int(d.get("replay", {}), "gate_priority_above_2x", replay_gate_priority)
	helios_length_cells = _num(d.get("strategic", {}), "helios_length_cells", helios_length_cells)
	var tm: Array = (d.get("terrain", {}) as Dictionary).get("material", [])
	terrain_material = PackedInt32Array()
	for m: Variant in tm:
		terrain_material.append(maxi(SndUnits.MAT_NAMES.find(str(m)), 0))
	ambience = d.get("ambience", {})
	apply_quality(Q_MEDIUM)


func apply_quality(q: int) -> void:
	q = clampi(q, 0, 2)
	voices_3d = voices_3d_by_quality[q]
	loops_budget = loops_budget_by_quality[q]


func material_of_terrain(terrain_id: int) -> int:
	if terrain_id >= 0 and terrain_id < terrain_material.size():
		return terrain_material[terrain_id]
	return SndUnits.material_of_terrain(terrain_id)
