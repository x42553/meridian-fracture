class_name SimCombatMods
extends RefCounted
## Lease slots (combat 3.6 / 4.3): temporary combat modifiers pushed by abilities, zones and auras into
## `SimCompCombat.mods` (MAX_MODS slots of [key, stat, bp, expire_tick, filter]; an empty slot is the canonical
## [0, STAT_NONE, 0, 0, 0]). A lease is live while `expire_tick > tick`. Same (key, stat) never stacks; different
## keys add. Reads are pure (no lazy clearing), mutations happen only from sim systems.


## Creates / refreshes the lease (key, stat) for `ticks` ticks from world.tick. An existing live lease keeps the
## larger |bp| (ties keep the old value and filter) and the later expiry. A full table evicts the earliest expiry
## (lowest slot on ties); a new lease that expires before every slot is dropped. No-op when nothing changes.
static func apply(world: SimWorld, e: SimEntity, key: int, stat: int, bp: int, filter: int, ticks: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null or ticks <= 0 or stat < 0 or (e.flags & SimFlags.F_GONE) != 0:
		return
	var tick: int = world.tick
	var expire: int = tick + ticks
	if cc.mods.is_empty():
		_alloc(cc)
	var free_slot: int = -1
	var min_slot: int = 0
	var min_exp: int = 0x7FFFFFFF
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		var s: int = cc.mods[b + SimCombatConsts.MOD_STAT]
		var ex: int = cc.mods[b + SimCombatConsts.MOD_EXPIRE]
		if s == SimCombatConsts.STAT_NONE or ex <= tick:
			if free_slot < 0:
				free_slot = i
			continue
		if s == stat and cc.mods[b + SimCombatConsts.MOD_KEY] == key:
			var old_bp: int = cc.mods[b + SimCombatConsts.MOD_BP]
			var new_bp: int = old_bp
			var new_filter: int = cc.mods[b + SimCombatConsts.MOD_FILTER]
			if absi(bp) > absi(old_bp):
				new_bp = bp
				new_filter = filter
			var new_exp: int = maxi(ex, expire)
			if new_bp != old_bp or new_filter != cc.mods[b + SimCombatConsts.MOD_FILTER] or new_exp != ex:
				cc.mods[b + SimCombatConsts.MOD_BP] = new_bp
				cc.mods[b + SimCombatConsts.MOD_FILTER] = new_filter
				cc.mods[b + SimCombatConsts.MOD_EXPIRE] = new_exp
				_touch(world, e, cc)
			return
		if ex < min_exp:
			min_exp = ex
			min_slot = i
	var slot: int = free_slot
	if slot < 0:
		if expire < min_exp:
			return
		slot = min_slot
	var w: int = slot * SimCombatConsts.MODS_STRIDE
	cc.mods[w + SimCombatConsts.MOD_KEY] = key
	cc.mods[w + SimCombatConsts.MOD_STAT] = stat
	cc.mods[w + SimCombatConsts.MOD_BP] = bp
	cc.mods[w + SimCombatConsts.MOD_EXPIRE] = expire
	cc.mods[w + SimCombatConsts.MOD_FILTER] = filter
	_touch(world, e, cc)


## Removes every lease of `key` (all stats).
static func clear_key(e: SimEntity, key: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null or cc.mods.is_empty():
		return
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		if cc.mods[b + SimCombatConsts.MOD_STAT] != SimCombatConsts.STAT_NONE and cc.mods[b + SimCombatConsts.MOD_KEY] == key:
			_empty(cc, b)
			cc.mods_dirty = 1


## Removes every lease.
static func clear_all(cc: SimCompCombat) -> void:
	if cc.mods.is_empty():
		return
	for i: int in SimCombatConsts.MAX_MODS:
		_empty(cc, i * SimCombatConsts.MODS_STRIDE)
	cc.mods_dirty = 1


## Additive bp delta of the live leases of `stat`; when dtype >= 0 only leases whose filter matches (dtype, dc).
static func sum_bp(cc: SimCompCombat, stat: int, tick: int, dtype: int = -1, dc: int = 0) -> int:
	var total: int = 0
	if cc.mods.is_empty():
		return 0
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		if cc.mods[b + SimCombatConsts.MOD_STAT] != stat or cc.mods[b + SimCombatConsts.MOD_EXPIRE] <= tick:
			continue
		if dtype >= 0 and not SimCombatConsts.filter_match(cc.mods[b + SimCombatConsts.MOD_FILTER], dtype, dc):
			continue
		total += cc.mods[b + SimCombatConsts.MOD_BP]
	return total


## true when a live boolean lease of `stat` (STAT_FLAG_*) exists.
static func has_flag(cc: SimCompCombat, stat: int, tick: int) -> bool:
	if cc.mods.is_empty():
		return false
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		if cc.mods[b + SimCombatConsts.MOD_STAT] == stat and cc.mods[b + SimCombatConsts.MOD_EXPIRE] > tick:
			return true
	return false


## STAT_MARK filter for the marking `team` (bit team & 7), optionally restricted to ground weapons.
static func mark_filter(team: int, ground_only: bool) -> int:
	return (1 << (team & 7)) | (SimCombatConsts.MARK_GROUND_ONLY if ground_only else 0)


## Victim-side STAT_MARK bonus for an attacker of `atk_team` (`atk_ground`: shooter is on LAYER_GROUND).
static func mark_bp(cc: SimCompCombat, tick: int, atk_team: int, atk_ground: bool) -> int:
	var total: int = 0
	if cc.mods.is_empty() or atk_team < 0:
		return 0
	var bit: int = 1 << (atk_team & 7)
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		if cc.mods[b + SimCombatConsts.MOD_STAT] != SimCombatConsts.STAT_MARK or cc.mods[b + SimCombatConsts.MOD_EXPIRE] <= tick:
			continue
		var f: int = cc.mods[b + SimCombatConsts.MOD_FILTER]
		if (f & bit) == 0 or ((f & SimCombatConsts.MARK_GROUND_ONLY) != 0 and not atk_ground):
			continue
		total += cc.mods[b + SimCombatConsts.MOD_BP]
	return total


## Combat upkeep (P1): clears expired slots, recomputes agg_* and mods_next_expiry. Returns true while a live
## lease remains.
static func refresh(cc: SimCompCombat, tick: int) -> bool:
	if cc.mods.is_empty():
		return false
	if cc.mods_dirty == 0 and (cc.mods_next_expiry == 0 or tick < cc.mods_next_expiry):
		return cc.mods_next_expiry != 0
	var dmg: int = 0
	var rel: int = 0
	var rng: int = 0
	var next: int = 0
	for i: int in SimCombatConsts.MAX_MODS:
		var b: int = i * SimCombatConsts.MODS_STRIDE
		var s: int = cc.mods[b + SimCombatConsts.MOD_STAT]
		if s == SimCombatConsts.STAT_NONE:
			continue
		var ex: int = cc.mods[b + SimCombatConsts.MOD_EXPIRE]
		if ex <= tick:
			_empty(cc, b)
			continue
		if next == 0 or ex < next:
			next = ex
		var bp: int = cc.mods[b + SimCombatConsts.MOD_BP]
		if s == SimCombatConsts.STAT_DMG_OUT:
			dmg += bp
		elif s == SimCombatConsts.STAT_RELOAD:
			rel += bp
		elif s == SimCombatConsts.STAT_RANGE:
			rng += bp
	cc.agg_dmg_bp = dmg
	cc.agg_reload_bp = rel
	cc.agg_range_bp = rng
	cc.mods_next_expiry = next
	cc.mods_dirty = 0
	return next != 0


static func _alloc(cc: SimCompCombat) -> void:
	cc.mods.resize(SimCombatConsts.MAX_MODS * SimCombatConsts.MODS_STRIDE)
	cc.mods.fill(0)
	for i: int in SimCombatConsts.MAX_MODS:
		cc.mods[i * SimCombatConsts.MODS_STRIDE + SimCombatConsts.MOD_STAT] = SimCombatConsts.STAT_NONE


static func _empty(cc: SimCompCombat, b: int) -> void:
	cc.mods[b + SimCombatConsts.MOD_KEY] = 0
	cc.mods[b + SimCombatConsts.MOD_STAT] = SimCombatConsts.STAT_NONE
	cc.mods[b + SimCombatConsts.MOD_BP] = 0
	cc.mods[b + SimCombatConsts.MOD_EXPIRE] = 0
	cc.mods[b + SimCombatConsts.MOD_FILTER] = 0


static func _touch(world: SimWorld, e: SimEntity, cc: SimCompCombat) -> void:
	cc.mods_dirty = 1
	if world.combat != null:
		world.combat.note_status(e.id)
