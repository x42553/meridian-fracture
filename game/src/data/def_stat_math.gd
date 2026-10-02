class_name DefStatMath
extends RefCounted
## The ONLY layered-stat arithmetic of the code base (data_balance 3.4 / 5.5.3): half-up rounding, floors, caps,
## the single-rounding damage formula. Pure, static, allocation-free. Bounds: base <= 100000, factors <= 30000, so
## every product stays below 2^62.


## Two static layers in ONE rounding: half_up(base * (10000+s1) * (10000+s2) / 10^8), factors clamped >= 0.
static func fold2(base: int, s1_bp: int, s2_bp: int) -> int:
	var f1: int = maxi(0, 10000 + s1_bp)
	var f2: int = maxi(0, 10000 + s2_bp)
	return (2 * base * f1 * f2 + 100000000) / 200000000


## Single layer (layer 3): half_up(v * (10000+d) / 10^4), clamped >= 0.
static func apply_bp(v: int, delta_bp: int) -> int:
	var f: int = maxi(0, 10000 + delta_bp)
	return (2 * v * f + 10000) / 20000


## Floors/caps per stat (data_balance 5.5.4). `base` = the unmodified base value, `eco` = DefEconomy.
static func clamp_stat(stat: int, base: int, v: int, eco: DefEconomy) -> int:
	match stat:
		DefEnums.Stat.COST:
			if base <= 0:
				return maxi(v, 0)
			return maxi(v, DefConvert.ceil_div(base * eco.floor_cost_bp, 10000))
		DefEnums.Stat.BUILD_TIME:
			if base <= 0:
				return maxi(v, 0)
			return maxi(v, DefConvert.ceil_div(base * eco.floor_build_bp, 10000))
		DefEnums.Stat.RELOAD:
			return maxi(v, maxi(1, DefConvert.ceil_div(maxi(base, 0) * eco.floor_reload_bp, 10000)))
		DefEnums.Stat.REARM:
			if base <= 0:
				return maxi(v, 0)
			return maxi(v, DefConvert.ceil_div(base * eco.floor_rearm_bp, 10000))
		DefEnums.Stat.HEALTH, DefEnums.Stat.SIGHT, DefEnums.Stat.RANGE, DefEnums.Stat.REPAIR_RATE:
			return maxi(v, 1)
		DefEnums.Stat.SPEED, DefEnums.Stat.PROJ_SPEED, DefEnums.Stat.DAMAGE:
			return maxi(v, 1) if base > 0 else maxi(v, 0)
		_:
			return maxi(v, 0)


## Complete static fold with clamp: clamp_stat(stat, base, fold2(base, s1, s2)).
static func resolve_static(stat: int, base: int, s1_bp: int, s2_bp: int, eco: DefEconomy) -> int:
	return clamp_stat(stat, base, fold2(base, s1_bp, s2_bp), eco)


## Runtime: clamp_stat(stat, base, apply_bp(resolved, l3_bp)).
static func effective(stat: int, base: int, resolved: int, l3_bp: int, eco: DefEconomy) -> int:
	return clamp_stat(stat, base, apply_bp(resolved, l3_bp), eco)


## min(max(sum, 0), resist_cap_bp).
static func resist_total_bp(sum_bp: int, eco: DefEconomy) -> int:
	return mini(maxi(sum_bp, 0), eco.resist_cap_bp)


## Per-hit damage with ONE half-up rounding (TAXONOMY): max(min_damage, half_up(raw*bonus*matrix*(10000-resist)*falloff
## / 10^12)); 0 if raw, bonus, matrix or falloff <= 0. Equals `balance_calc.final_damage`.
static func final_damage(raw: int, bonus_bp: int, matrix_pct: int, resist_bp: int, falloff_pct: int, eco: DefEconomy) -> int:
	if raw <= 0 or bonus_bp <= 0 or matrix_pct <= 0 or falloff_pct <= 0:
		return 0
	var res: int = resist_total_bp(resist_bp, eco)
	var num: int = raw * bonus_bp * matrix_pct * (10000 - res) * falloff_pct
	return maxi(eco.min_damage, (2 * num + 1000000000000) / 2000000000000)


## Keeps the hp ratio when the max changes: max(1, rdiv(hp * new_max, old_max)).
static func rescale_hp(hp: int, old_max: int, new_max: int) -> int:
	if old_max <= 0:
		return maxi(1, new_max)
	return maxi(1, DefConvert.rdiv(hp * new_max, old_max))


## Same-stack-group rule: the larger |delta| wins, ties keep the existing one.
static func stack_pick(group_best_bp: int, candidate_bp: int) -> int:
	return candidate_bp if absi(candidate_bp) > absi(group_best_bp) else group_best_bp
