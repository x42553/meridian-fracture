class_name AiComposition
extends RefCounted
## Target role shares of the army (ai.md 5.6.1): w[r] = base[phase][r] x group_mult(r) x product(counter multipliers of the
## active enemy-composition triggers, AiTech), then the EFFECTIVE shares are normalised over the roles that can be produced
## right now (`share_q8`, sum 256). From Medium up the weights are also scaled by a STAT multiplier: how much damage per credit the
## role's def deals against the armor classes of the enemy units seen (resolved AiUnitProfile.dps_x100, so a damage-matrix change
## in the balance data changes the composition without any code change). Roles whose weight share is >= PULL_PCT but which are not producible yet are listed in `pull`
## so AiTech can build the missing structures (tech pull). The role -> def choice (`pick_def`) is the lowest-tier producible def
## of the role, the highest one in the late phase. Recomputed at most every UPDATE_TICKS.

const UPDATE_TICKS: int = 20
const PULL_PCT: int = 15
const DETECTOR_MIN_PCT: int = 10
const STAT_MIN_VALUE: int = 1500  ## visible enemy value needed before the stat multiplier is used
const STAT_MULT_MIN_Q8: int = 192
const STAT_MULT_MAX_Q8: int = 358

var doctrine: AiDoctrine = null
var roles: PackedInt32Array = PackedInt32Array()  ## composition roles (weight > 0 in some phase), ascending bit
var comp_role_of_def: PackedInt32Array = PackedInt32Array()  ## by unit def: primary composition role or -1
var weight: PackedInt32Array = PackedInt32Array()  ## final weights by role (0 = unwanted)
var share_q8: PackedInt32Array = PackedInt32Array()  ## effective shares over producible roles
var producible: PackedByteArray = PackedByteArray()
var def_pick: PackedInt32Array = PackedInt32Array()  ## role -> def to build now, -1 none
var pull: PackedInt32Array = PackedInt32Array()  ## roles that want a structure that is not there yet
var phase: int = AiTypes.Phase.OPENING
var phase_override: int = -1  ## the brain (AI-06) may force a phase
var water_pct: int = 0
var updates: int = 0
var armor_mix: PackedInt32Array = PackedInt32Array()  ## seen enemy value by armor class (last snapshot with >= STAT_MIN_VALUE)
var stat_mult_q8: PackedInt32Array = PackedInt32Array()  ## by role (256 = neutral)
var _calc_tick: int = -1000
var _hub: WeakRef = null


func setup(ctx: AiContext, doc: AiDoctrine, hub: AiEconomy) -> void:
	_hub = weakref(hub)
	doctrine = doc
	var nu: int = ctx.view.game_data().units.size()
	comp_role_of_def.resize(nu)
	comp_role_of_def.fill(-1)
	weight.resize(AiTypes.ROLE_COUNT)
	share_q8.resize(AiTypes.ROLE_COUNT)
	producible.resize(AiTypes.ROLE_COUNT)
	def_pick.resize(AiTypes.ROLE_COUNT)
	def_pick.fill(-1)
	stat_mult_q8.resize(AiTypes.ROLE_COUNT)
	stat_mult_q8.fill(256)
	armor_mix.resize(AiUnitProfile.NCLASS)
	roles.resize(0)
	for r: int in AiTypes.ROLE_COUNT:
		var wanted: bool = false
		for ph: PackedInt32Array in doc.composition:
			if ph[r] > 0:
				wanted = true
		if wanted and ctx.res.has_role(r):
			roles.append(r)
			for d: int in ctx.res.units_of(r):
				if comp_role_of_def[d] < 0:
					comp_role_of_def[d] = r
	# water fraction of the map (sampled) for the naval group multiplier
	var v: AiWorldView = ctx.view
	var n: int = 0
	var wet: int = 0
	for y: int in range(0, v.map_h(), 3):
		for x: int in range(0, v.map_w(), 3):
			n += 1
			if v.is_water(x, y):
				wet += 1
	water_pct = wet * 100 / maxi(n, 1)


func is_comp_role(r: int) -> bool:
	return roles.has(r)


func pick_def(role: int) -> int:
	return def_pick[role]


## Recomputes phase, weights, producibility and shares (cached UPDATE_TICKS).
func update(ctx: AiContext, budget: AiBudget) -> void:
	if ctx.tick - _calc_tick < UPDATE_TICKS:
		return
	var eco: AiEconomy = _hub.get_ref()
	if eco == null or not budget.spend(4 + roles.size()):
		return
	_calc_tick = ctx.tick
	updates += 1
	phase = phase_override if phase_override >= 0 else doctrine.phase_at(ctx.tick, ctx.diff.tech_delay_x100)
	var base: PackedInt32Array = doctrine.composition[phase]
	var v: AiWorldView = ctx.view
	var pers: AiPersonality = ctx.pers
	var have: PackedInt32Array = v.struct_counts()
	var water_q8: int = clampi(water_pct * 256 / 15, 0, 256)
	if not eco.placer.dock_placeable(ctx):
		water_q8 = 0
	var detector_low: bool = eco.tech.trigger_active(AiTypes.Cat.CAMO) and eco.army_units > 0 \
		and eco.detector_alive * 100 < DETECTOR_MIN_PCT * eco.army_units
	var total_w: int = 0
	var total_prod: int = 0
	weight.fill(0)
	producible.fill(0)
	def_pick.fill(-1)
	# pass 1: which def would each role build now
	for r0: int in roles:
		for d0: int in ctx.res.units_of(r0):
			if ctx.tech.missing_for_unit(d0, have).is_empty():
				if def_pick[r0] < 0 or phase == AiTypes.Phase.LATE:
					def_pick[r0] = d0
	_stat_mults(ctx)
	var siege_q8: int = _siege_mult_q8(ctx)
	for r: int in roles:
		var w: int = base[r] * 16
		if w <= 0:
			continue
		w = w * _group_pct(r, pers, water_q8) / 100
		w = w * eco.tech.counter_mult_q8(r) >> 8
		w = w * stat_mult_q8[r] >> 8
		if r == AiTypes.R_ARTILLERY or r == AiTypes.R_HEAVY:
			w = w * siege_q8 >> 8  # known enemy defensive structures: artillery outranges them (AiSiege)
		var picked: int = def_pick[r]
		if detector_low and picked >= 0 and ctx.res.has_bit(picked, AiTypes.R_DETECTOR):
			w = w * 2
		weight[r] = w
		total_w += w
		if picked >= 0:
			producible[r] = 1
			total_prod += w
	pull.resize(0)
	share_q8.fill(0)
	for r2: int in roles:
		if weight[r2] <= 0:
			continue
		if producible[r2] == 1:
			share_q8[r2] = weight[r2] * 256 / maxi(total_prod, 1)
		elif weight[r2] * 100 >= PULL_PCT * maxi(total_w, 1):
			pull.append(r2)


## stat_mult_q8[r] = (damage per credit of the role's def against the seen armor mix) / (the mean over the producible roles),
## clamped to [0.75, 1.4]; neutral for Easy and while too little of the enemy has been seen.
func _stat_mults(ctx: AiContext) -> void:
	stat_mult_q8.fill(256)
	if ctx.cfg.level == AiTypes.Difficulty.EASY:
		return
	var t: AiEntityTable = ctx.kb.enemy_units
	var snap: PackedInt32Array = PackedInt32Array()
	snap.resize(AiUnitProfile.NCLASS)
	var seen: int = 0
	for r: int in t.count:
		var p: AiUnitProfile = ctx.unit_profile_of(t.owner[r], t.def[r])
		if p == null:
			continue
		snap[p.armor_class] += p.value
		seen += p.value
	if seen >= STAT_MIN_VALUE:
		armor_mix = snap
	var total: int = 0
	for v: int in armor_mix:
		total += v
	if total < STAT_MIN_VALUE:
		return
	var scores: PackedInt32Array = PackedInt32Array()
	scores.resize(AiTypes.ROLE_COUNT)
	var sum: int = 0
	var n: int = 0
	for role: int in roles:
		var d: int = def_pick[role]
		var p2: AiUnitProfile = ctx.unit_profile(d) if d >= 0 else null
		if p2 == null or p2.cost <= 0:
			continue
		var dmg: int = 0
		for c: int in AiUnitProfile.NCLASS:
			dmg += armor_mix[c] / 16 * p2.dps_x100[c] / 16
		scores[role] = dmg * 1000 / (total / 256 + 1) / p2.cost
		sum += scores[role]
		n += 1
	if n < 2 or sum <= 0:
		return
	var mean: int = maxi(sum / n, 1)
	for role2: int in roles:
		if def_pick[role2] >= 0:
			stat_mult_q8[role2] = clampi(scores[role2] * 256 / mean, STAT_MULT_MIN_Q8, STAT_MULT_MAX_Q8)


## Q8 multiplier (256 = none) of the artillery / heavy weights: 1.4 with two known enemy ground defenses, 1.8 with four or more.
func _siege_mult_q8(ctx: AiContext) -> int:
	var g: AiGhostTable = ctx.kb.ghosts
	var n: int = 0
	for i: int in g.count:
		if g.owner[i] >= 0 and g.eid[i] > 0 and g.kind[i] != AiTypes.StructKind.AA_BATTERY and AiForce.is_defense_kind(g.kind[i]):
			n += 1
	if n >= 4:
		return 460
	if n >= 2:
		return 360
	return 256


func _group_pct(r: int, pers: AiPersonality, water_q8: int) -> int:
	match r:
		AiTypes.R_FIGHTER, AiTypes.R_BOMBER, AiTypes.R_EW_AIR:
			return pers.air * 2
		AiTypes.R_BOAT_LIGHT, AiTypes.R_ESCORT_SHIP, AiTypes.R_SIEGE_SHIP, AiTypes.R_CARRIER, AiTypes.R_SUBMARINE:
			return pers.naval * 2 * water_q8 / 256
		AiTypes.R_ARTILLERY, AiTypes.R_HEAVY:
			return pers.siege * 2
		AiTypes.R_INFANTRY_BASIC, AiTypes.R_INFANTRY_AT, AiTypes.R_INFANTRY_SUPPORT:
			return pers.infantry * 2
	return 100


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([phase, updates])
	v.append_array(share_q8)
	return AiRng.hash_ints(v)
