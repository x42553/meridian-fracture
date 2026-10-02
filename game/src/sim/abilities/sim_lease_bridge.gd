class_name SimLeaseBridge
extends RefCounted
## The ONLY translation from DefEffect ops to combat state (abilities 5.2.4): leases in SimCombatMods, the two immunity
## flags, weapon locks and marks. Local stats (SPEED / SIGHT / HEALTH) are not leases: SimStats folds them.

const C := preload("res://src/sim/combat/sim_combat_consts.gd")


static func fxk(src_kind: int, id: int) -> int:
	return SimAbilityConsts.fxk(src_kind, id)


## Lease key of a timed effect: a src_key below 2^24 is a power index, otherwise a complete FXK.
static func key_of_source(src_key: int) -> int:
	return fxk(SimAbilityConsts.SRC_POWER, src_key) if src_key >= 0 and src_key < (1 << 24) else src_key


## Combat lease stat of a STAT_MOD effect, -1 when the stat is not a lease (local or per-player).
static func stat_of(fx: DefEffect) -> int:
	match fx.stat:
		DefEnums.Stat.DAMAGE:
			return C.STAT_DMG_OUT
		DefEnums.Stat.RANGE:
			return C.STAT_RANGE
		DefEnums.Stat.RELOAD:
			return C.STAT_RELOAD
		DefEnums.Stat.REARM_RATE:
			return C.STAT_REARM_RATE
	return -1


## Local stat index (SimAbilityConsts.K_*) of a STAT_MOD effect, -1 when it is not a local stat.
static func local_stat_of(fx: DefEffect) -> int:
	if fx.op != DefEnums.EffectOp.STAT_MOD:
		return -1
	match fx.stat:
		DefEnums.Stat.SPEED:
			return SimAbilityConsts.K_SPEED
		DefEnums.Stat.SIGHT:
			return SimAbilityConsts.K_SIGHT
		DefEnums.Stat.HEALTH:
			return SimAbilityConsts.K_HEALTH
	return -1


## Damage-type bits of a RESIST_MOD (group_mask 0 = every weapon group except EMP) packed with the fire-mode
## restriction as combat's lease filter (types | req << 15 | forbid << 19).
static func filter_of(world: SimWorld, fx: DefEffect) -> int:
	var types: int = C.DT_MASK_ALL_WEAPON
	if fx.group_mask != 0:
		types = 0
		var gmt: PackedInt32Array = world.data.damage.group_mask
		for dt: int in DefEnums.DamageType.COUNT:
			if (gmt[dt] & fx.group_mask) != 0:
				types |= 1 << dt
	var req: int = 0
	var forbid: int = 0
	var fm: int = fx.fire_mode_mask
	if fm == 1 or fm == 4 or fm == 5:  # direct (melee counts as direct fire)
		req = C.DC_DIRECT
		forbid = C.DC_SPLASH | C.DC_INDIRECT | C.DC_STRATEGIC
	elif fm == 2:
		req = C.DC_INDIRECT
	return types | (req << 15) | (forbid << 19)


## Holds the effect on `e` for `ticks` under `key`. bp_override != 0 replaces the effect's own magnitude;
## src_team is the marking team of a MARK. Effects that are not leases do nothing here.
static func hold(world: SimWorld, e: SimEntity, key: int, fx: DefEffect, bp_override: int, ticks: int, src_team: int = -1) -> void:
	if ticks <= 0 or e.combat == null:
		return
	var bp: int = bp_override if bp_override != 0 else fx.delta_bp
	match fx.op:
		DefEnums.EffectOp.STAT_MOD:
			var st: int = stat_of(fx)
			if st >= 0:
				SimCombatMods.apply(world, e, key, st, bp, 0, ticks)
		DefEnums.EffectOp.RESIST_MOD:
			SimCombatMods.apply(world, e, key, C.STAT_TAKEN, bp, filter_of(world, fx), ticks)
		DefEnums.EffectOp.IMMUNITY:
			var what: int = immunity_of(fx)
			if (what & 1) != 0:
				SimCombatMods.apply(world, e, key, C.STAT_FLAG_SUP_IMMUNE, 0, 0, ticks)
				SimDamage.clear_suppression(world, e)
			if (what & 2) != 0:
				SimCombatMods.apply(world, e, key, C.STAT_FLAG_EMP_IMMUNE, 0, 0, ticks)
		DefEnums.EffectOp.DISABLE:
			lock_weapons(world, e, world.tick + ticks)
		DefEnums.EffectOp.MARK:
			var mbp: int = bp_override if bp_override != 0 else int(fx.params.get("damage_bonus_bp", fx.delta_bp))
			SimCombatMods.apply(world, e, key, C.STAT_MARK, mbp, SimCombatMods.mark_filter(src_team, true), ticks)


static func release(_world: SimWorld, e: SimEntity, key: int) -> void:
	SimCombatMods.clear_key(e, key)


## combat.lock_weapons: weapons stay locked until `until` (never shortened). FIX (AB2, asked by CBC): goes through
## combat's own lock_weapons so the F_WEAPONS_OFF mirror and EV_WEAPON_LOCK stay right; the raw write is the fallback for
## worlds without a combat stage.
static func lock_weapons(world: SimWorld, e: SimEntity, until: int) -> void:
	if world != null and world.combat != null:
		world.combat.lock_weapons(world, e, until)
		return
	var cc: SimCompCombat = e.combat
	if cc != null and until > cc.wlock_until:
		cc.wlock_until = until


## Bit 1 suppression, bit 2 emp: read from the effect's params (strings or lists of strings, any key).
static func immunity_of(fx: DefEffect) -> int:
	var m: int = 0
	for k: Variant in fx.params.keys():
		m |= _immunity_bits(fx.params[k])
	m |= _immunity_bits(fx.flag)
	return m


static func _immunity_bits(v: Variant) -> int:
	if v is String:
		var s: String = v
		var m: int = 0
		if s.contains("suppress"):
			m |= 1
		if s == "emp" or s.begins_with("emp_"):
			m |= 2
		return m
	if v is Array:
		var acc: int = 0
		for x: Variant in v:
			acc |= _immunity_bits(x)
		return acc
	return 0
