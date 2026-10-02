class_name SimSteering
extends RefCounted
## Pure static integer math of the steering law (terrain_movement 5.1 / 5.4.2). No state, no allocation.
## Speeds are Q4 (units/tick * 16), angles are binary (4096 = full turn).


## abs of the signed heading error des - facing, in -2048..2047.
static func angle_err(des: int, facing: int) -> int:
	return ((des - facing + 2048) & 4095) - 2048


## The top speed of 5.1 in Q4: terrain percent (bp), water multiplier (bp, only on water cells), suppression (bp,
## 10000 = none) and the formation cap (0 = none). All rounding half-up.
static func top_speed_q4(speed_upt: int, kind_bp: int, on_water: bool, water_mult_bp: int, supp_bp: int, cap_q4: int) -> int:
	var v: int = (speed_upt * 16 * kind_bp + 5000) / 10000
	if on_water:
		v = (v * water_mult_bp + 5000) / 10000
	if supp_bp != 10000:
		v = (v * supp_bp + 5000) / 10000
	if cap_q4 > 0 and v > cap_q4:
		v = cap_q4
	return v


## Turn step per tick (angle units). TM_ARC vehicles turn at 25 % of the rate at rest and 100 % at full speed.
static func turn_step_rate(mode: int, turn_rate: int, spd_abs: int, vcur_q4: int) -> int:
	if mode != SimMoveConfig.TM_ARC:
		return turn_rate
	var frac: int = mini(256, spd_abs * 256 / maxi(1, vcur_q4))
	return (turn_rate * (64 + ((192 * frac) >> 8))) >> 8


## Fraction (0..256) of the top speed allowed while the remaining heading error is `a` (>= 0). TM_INSTANT (infantry)
## follows the pivot curve: a turn-rate-limited unit at full speed would otherwise circle a goal closer than its
## turn radius forever (the spec's f = 256 for TM_INSTANT); with real infantry turn rates the difference is nil.
static func heading_factor(mode: int, a: int) -> int:
	if mode == SimMoveConfig.TM_BANK:
		return 256
	if mode == SimMoveConfig.TM_PIVOT or mode == SimMoveConfig.TM_INSTANT:
		if a <= 256:
			return 256
		if a <= 768:
			return 256 - ((a - 256) * 256) / 512
		return 0
	if a <= 256:
		return 256
	return maxi(64, 256 - ((a - 256) * 192) / 768)


## Fastest speed (Q4) from which `decel_q4` can still stop within `rd - goal_range` units, looking one tick ahead.
static func arrival_speed(decel_q4: int, spd_abs: int, rd: int, goal_range: int) -> int:
	var rdp: int = maxi(0, rd - goal_range)
	return Fp.isqrt(32 * decel_q4 * maxi(0, rdp - (spd_abs >> 4)))


## One step of the speed law (signed).
static func speed_law(spd: int, target: int, accel_q4: int, decel_q4: int) -> int:
	if target > spd:
		return mini(spd + accel_q4, target)
	return maxi(spd - decel_q4, target)


## Displacement of one tick at signed Q4 speed `spd` along `facing`: half-up, Q4 x Q16 = Q20.
static func vel_x(spd: int, facing: int) -> int:
	return (spd * Fp.cos(facing) + 524288) >> 20


static func vel_y(spd: int, facing: int) -> int:
	return (spd * Fp.sin(facing) + 524288) >> 20
