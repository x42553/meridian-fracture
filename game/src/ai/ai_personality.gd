class_name AiPersonality
extends RefCounted
## Resolved personality vector of one AI (ai.md 4.3 / 5.14): base row of the roster (ai_personality.json) -> style
## (5.14.4) -> seeded jitter (5.14.3). Draw order is FIXED: (0) wildcard style picks, (1) jitter per numeric field in the
## declaration order of JITTER_FIELDS, (2) attack style primary/alternate, (3) first-attack and wave-interval jitter.
## Draws (4) optional opener steps and (5) superweapon timing belong to AiBuildPlanner / AiSuperweapon (ctx.rng continues).

const JITTER_FIELDS: PackedStringArray = [
	"aggression", "tech", "economy", "defense_pct", "harass_pct", "air", "naval", "siege", "infantry", "micro", "sw_priority",
]
const STYLE_CODES: Dictionary = {"P": 0, "PR": 1, "R": 2, "C": 3, "L": 4, "A": 5, "F": 6}
const EXPAND_CODES: Dictionary = {"E": 0, "D": 1, "L": 2, "M": 3}

var aggression: int = 50
var tech: int = 50
var economy: int = 55
var defense_pct: int = 15  ## 0..40
var harass_pct: int = 10
var air: int = 15
var naval: int = 10
var siege: int = 40
var infantry: int = 40
var dispersion: int = 3  ## 1..6 cells
var eco_x10: int = 0  ## AIT: Collectors per Refinery x10 added to the base ratio and the global boost (-10..+10; a roster's economic appetite, not jittered)
var micro: int = 50
var style: int = AiTypes.Style.PUSH
var style_alt: int = AiTypes.Style.PRONG
var attack_style: int = AiTypes.Style.PUSH  ## the drawn one of style / style_alt
var expand: int = AiTypes.Expand.DEFENDED
var flags: int = 0
var retreat_hp_pct: int = 35
var return_hp_pct: int = 85
var sw_priority: int = 60
var first_attack_jitter_pct: int = 0  ## -15..+25
var wave_interval_jitter_pct: int = 0  ## -20..+20
var sw_jitter_pct: int = 0  ## drawn later by AiSuperweapon (-10..+10)
var style_mode: int = 0  ## the applied lobby style 0..3 (wildcard resolved to 0..2)
var first_attack_scale_pct: int = 100  ## style multipliers on first_attack_min_s / wave_interval_s
var wave_interval_scale_pct: int = 100
var posture_threshold_shift: int = 0  ## 0 or -10 (aggressive style)
var roster_id: String = ""


## Builds the personality for one AI. `over` = AiConfig.personality_override (field -> int). Consumes exactly the draws
## documented above from `rng`.
static func build(store: AiDataStore, p_roster_id: String, lobby_style: int, diff: AiDifficultyProfile, rng: AiRng, over: Dictionary = {}) -> AiPersonality:
	var p: AiPersonality = AiPersonality.new()
	p.roster_id = p_roster_id
	var row: Dictionary = store.personality_row(p_roster_id)
	for k: String in ["aggression", "tech", "economy", "defense_pct", "harass_pct", "air", "naval", "siege", "infantry", "micro",
			"dispersion", "retreat_hp_pct", "return_hp_pct", "sw_priority", "eco_x10"]:
		if row.has(k):
			p.set(k, int(row[k]))
	p.style = int(STYLE_CODES.get(str(row.get("style", "P")), 0))
	p.style_alt = int(STYLE_CODES.get(str(row.get("style_alt", "PR")), 1))
	p.expand = int(EXPAND_CODES.get(str(row.get("expand", "D")), 1))
	for fl: Variant in row.get("flags", []):
		var b: int = AiTypes.doctrine_bit(str(fl))
		if b >= 0:
			p.flags |= 1 << b
	# (0) wildcard: seeded pick of doctrine / aggressive / defensive, then a uniform attack-style pick
	var mode: int = lobby_style
	var wild_style: int = -1
	if lobby_style == 3:
		mode = rng.pick_weighted(PackedInt32Array([40, 30, 30]))
		wild_style = rng.range_i(0, 4)  # PUSH, PRONG, RAID, CREEP, LANDING
	p.style_mode = mode
	p._apply_style(mode)
	# (1) jitter, declaration order
	var j: int = diff.jitter_pct
	for f: String in JITTER_FIELDS:
		var r: int = rng.range_i(-j, j)
		var v: int = int(p.get(f))
		p.set(f, clampi(v * (100 + r) / 100, 0, 40 if f == "defense_pct" else 100))
	# (2) attack style between primary and alternate
	p.attack_style = p.style if rng.pick_weighted(PackedInt32Array([70, 30])) == 0 else p.style_alt
	if wild_style >= 0:
		p.attack_style = wild_style
	# (3) timing jitter
	p.first_attack_jitter_pct = rng.range_i(-15, 25)
	p.wave_interval_jitter_pct = rng.range_i(-20, 20)
	for k: String in over:
		if k in p:
			p.set(k, int(over[k]))
	return p


## Style effects (ai.md 5.14.4) applied before the jitter.
func _apply_style(mode: int) -> void:
	match mode:
		1:  # aggressive
			aggression = mini(100, aggression + 20)
			harass_pct = mini(100, harass_pct + 10)
			defense_pct = maxi(0, defense_pct - 5)
			first_attack_scale_pct = 80
			wave_interval_scale_pct = 80
			posture_threshold_shift = -10
		2:  # defensive
			aggression = maxi(0, aggression - 20)
			defense_pct = mini(40, defense_pct + 8)
			first_attack_scale_pct = 130
			wave_interval_scale_pct = 120
			if expand == AiTypes.Expand.EARLY:
				expand = AiTypes.Expand.DEFENDED
			# FORTRESS / CREEP weights x2 are applied through style_weight()


func has_flag(doctrine: int) -> bool:
	return (flags & (1 << doctrine)) != 0


## Weight (x100) the strategy gives an attack style: primary 70, alternate 30, doubled for FORTRESS/CREEP when defensive.
func style_weight(s: int) -> int:
	var w: int = 0
	if s == style:
		w += 70
	if s == style_alt:
		w += 30
	if style_mode == 2 and (s == AiTypes.Style.FORTRESS or s == AiTypes.Style.CREEP):
		w *= 2
	return w


func first_attack_ticks(diff: AiDifficultyProfile) -> int:
	return diff.first_attack_min_s * SimConfig.TPS * first_attack_scale_pct / 100 * (100 + first_attack_jitter_pct) / 100


func wave_interval_ticks(diff: AiDifficultyProfile) -> int:
	return diff.wave_interval_s * SimConfig.TPS * wave_interval_scale_pct / 100 * (100 + wave_interval_jitter_pct) / 100


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([aggression, tech, economy, defense_pct, harass_pct, air, naval, siege, infantry,
		dispersion, micro, style, style_alt, attack_style, expand, flags, retreat_hp_pct, return_hp_pct, sw_priority,
		first_attack_jitter_pct, wave_interval_jitter_pct])
	return AiRng.hash_ints(v)
