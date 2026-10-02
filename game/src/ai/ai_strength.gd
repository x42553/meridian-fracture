class_name AiStrength
extends RefCounted
## Lanchester-square group strength ratio (ai.md 5.3.4). Pure integer math; magnitudes: hp <= 2e5, dps_x100 <= 2e6 so the
## largest product (hp x dps x 256) is ~1e14 < 2^62.

const NCLASS: int = DefEnums.ArmorClass.COUNT
const MAX_RATIO_Q8: int = 16 * 256  ## returned when the defender cannot hurt the attacker at all


## Q8 ratio attacker strength / defender strength.
##   home_adv_pct : defender home advantage on its damage (tuning strength.home_adv_pct, default 10)
##   noise_q8     : signed Q8 estimate noise (see noise_q8()), 0 = none
static func ratio_q8(att: AiStrengthGroup, def: AiStrengthGroup, home_adv_pct: int = 0, noise: int = 0) -> int:
	if att.hp <= 0:
		return 0
	if def.hp <= 0:
		return MAX_RATIO_Q8
	var acc_a: int = 0
	var acc_d: int = 0
	for c: int in NCLASS:
		acc_a += (def.hp_by_class[c] * 256 / def.hp) * att.dps_x100_by_class[c]
		acc_d += (att.hp_by_class[c] * 256 / att.hp) * def.dps_x100_by_class[c]
	var dps_a: int = acc_a >> 8
	var dps_d: int = acc_d >> 8
	# range advantage: ~3 % per cell, clamped
	var dr_cells: int = 8 * (att.avg_range - def.avg_range) / Fp.CELL
	var f_range: int = clampi(256 + dr_cells, 205, 320)
	dps_a = dps_a * f_range >> 8
	dps_d = dps_d * (256 + 256 * home_adv_pct / 100) >> 8
	# artillery screen: mostly artillery with little screening hp fights at a disadvantage
	var tot_a: int = att.total_dps_x100()
	if tot_a > 0 and att.arty_dps_x100 * 100 / tot_a > 40 and (att.hp - att.arty_hp) * 100 / att.hp < 30:
		dps_a = dps_a * 205 >> 8
	if dps_d <= 0:
		return MAX_RATIO_Q8
	if dps_a <= 0:
		return 0
	var r: int = att.hp * dps_a * 256 / maxi(1, def.hp * dps_d)
	r = mini(r, MAX_RATIO_Q8 * 8)
	return r * (256 + noise) >> 8


## Stable estimate noise for (target, 200-tick epoch): in [-n, +n] Q8 with n = est_noise_pct x 256 / 100. Not a draw, so it
## does not flicker inside an epoch.
static func noise_q8(tick: int, target_key: int, est_noise_pct: int, epoch_ticks: int = 200) -> int:
	if est_noise_pct <= 0:
		return 0
	var n: int = est_noise_pct * 256 / 100
	var h: int = AiRng.mix32((tick / maxi(epoch_ticks, 1)) * 0x9E3779B1 + target_key * 0x85EBCA6B)
	return h % (2 * n + 1) - n


## True when a Q8 ratio meets a launch threshold given as x100 (130 = 1.30).
static func meets(ratio: int, threshold_x100: int) -> bool:
	return ratio >= threshold_x100 * 256 / 100
