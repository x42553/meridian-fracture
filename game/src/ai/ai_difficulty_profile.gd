class_name AiDifficultyProfile
extends RefCounted
## One difficulty row (ai.md 4.3 / 5.14.1), loaded from ai_difficulty.json by AiDataStore. ONLY Brutal cheats: fog-piercing
## reads (`info_omniscient`, camouflage is still honoured) and the labelled +20 % economy bonus (`handicap_pct` 120, applied
## by the sim through the slot handicap - the AI itself applies nothing). `label_cheats` is the text key shown next to the
## level name; `cheats_text` is its English default.

const INT_FIELDS: PackedStringArray = [
	"id", "think_period_ticks", "micro_period_ticks", "apm_cap", "cmd_burst", "reaction_delay_ticks", "idle_tolerance_ticks",
	"queue_depth", "place_latency_ticks", "opt_step_keep_pct", "scout_level", "expansions_max", "collector_k_x10",
	"tech_delay_x100", "first_attack_min_s", "wave_interval_s", "launch_ratio_x100", "est_noise_pct", "dodge_pct",
	"powers_level", "eager_pct", "sw_min_time_s", "unit_cap_pct", "wu_per_tick", "call_cap_wu", "jitter_pct", "handicap_pct",
	"prongs_max", "harass_ops_max", "enemy_prior",
]
const BOOL_FIELDS: PackedStringArray = ["info_omniscient", "micro_retreat", "micro_focus", "micro_kite"]

var id: int = 0
var label: String = ""
var label_cheats: String = ""
var cheats_text: String = ""
var think_period_ticks: int = 20
var micro_period_ticks: int = 0
var apm_cap: int = 90
var cmd_burst: int = 8
var reaction_delay_ticks: int = 30
var idle_tolerance_ticks: int = 80
var queue_depth: int = 2
var place_latency_ticks: int = 40
var opt_step_keep_pct: int = 80
var info_omniscient: bool = false
var scout_level: int = 1
var expansions_max: int = 1
var collector_k_x10: int = 15
var tech_delay_x100: int = 125
var first_attack_min_s: int = 600
var wave_interval_s: int = 180
var launch_ratio_x100: int = 130
var est_noise_pct: int = 25
var micro_retreat: bool = true
var micro_focus: bool = true
var micro_kite: bool = false
var dodge_pct: int = 50
var powers_level: int = 2
var eager_pct: int = 125
var sw_min_time_s: int = 960
var unit_cap_pct: int = 85
var wu_per_tick: int = 350
var call_cap_wu: int = 2400
var jitter_pct: int = 25
var handicap_pct: int = 100
var prongs_max: int = 2
var harass_ops_max: int = 1
var enemy_prior: int = 1  ## 0 off, 1 air only, 2 full


static func from_dict(d: Dictionary) -> AiDifficultyProfile:
	var p: AiDifficultyProfile = AiDifficultyProfile.new()
	for k: String in INT_FIELDS:
		if d.has(k):
			p.set(k, int(d[k]))
	for k: String in BOOL_FIELDS:
		if d.has(k):
			p.set(k, bool(d[k]))
	p.label = str(d.get("label", ""))
	p.label_cheats = str(d.get("label_cheats", ""))
	p.cheats_text = str(d.get("cheats_text", ""))
	return p


## True for a profile that plays with an advantage (only Brutal is allowed to).
func has_cheats() -> bool:
	return info_omniscient or handicap_pct != 100


## Think period in ticks at the given shared-clock scale (never below 1).
func think_ticks() -> int:
	return maxi(1, think_period_ticks)


func dump() -> Dictionary:
	var d: Dictionary = {"label": label, "label_cheats": label_cheats, "cheats_text": cheats_text}
	for k: String in INT_FIELDS:
		d[k] = get(k)
	for k: String in BOOL_FIELDS:
		d[k] = get(k)
	return d
