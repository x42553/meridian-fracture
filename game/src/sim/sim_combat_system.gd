class_name SimCombatSystem
extends SimSystem
## Pipeline stage 8 "combat" (combat 3.1 / 3.2 / 3.7): components, lifecycle hooks, lease upkeep, status timers, the
## read API and the damage flush. The only writer of `SimEntity.hp` (through SimDamage.flush, heal, rescale_hp).
## Later tasks fill P2 (air / carriers), P3 (scans), P4 (weapons), P5 (projectiles) and the death sequence; the
## phase skeleton of `update` and the id lists they iterate are already here.

const CNT_SCANS: int = 0
const CNT_SHOTS: int = 1
const CNT_IMPACTS: int = 2
const CNT_DAMAGE: int = 3
const CNT_PROJ: int = 4
const CNT_N: int = 5

var armed_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids with >= 1 mount or an air / carrier component
var wreck_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of KIND_WRECK entities
var status_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids with a live timer (EMP, lock, suppression, lease, dying)
var air_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of aircraft / drones (not airfields)
var carrier_ids: PackedInt32Array = PackedInt32Array()  ## ascending ids of carriers
var scan_cursor: int = 0  ## round-robin position in armed_ids (checksummed)
var counters: PackedInt32Array = PackedInt32Array()  ## deterministic perf counters (CNT_*), not checksummed
var dmg_queue: PackedInt32Array = PackedInt32Array()  ## SimDamage queue, stride 10, empty between ticks
var scratch_hitf: int = 0  ## HITF_* bits of the last SimDamage.taken_bp call (scratch)
var alert_tick: PackedInt32Array = PackedInt32Array()  ## per pid: last EV_ATTACK_ALERT tick (output throttle, not hashed)
var alert_x: PackedInt32Array = PackedInt32Array()
var alert_y: PackedInt32Array = PackedInt32Array()
var tables: Array[SimCombatTables] = []  ## per pid (null for vacant pids)
var neutral_tables: SimCombatTables = null  ## base defs for neutral owners and defs outside a roster
var matrix_bp: PackedInt32Array = PackedInt32Array()  ## [dtype * n_armor + armor] copy of the data matrix (bp)
var n_armor: int = DefEnums.ArmorClass.COUNT
var proj: SimProjectiles = SimProjectiles.new()  ## projectile pool (P5), hashed
var weapons: SimWeapons = SimWeapons.new()  ## P4 driver (scratch only)
var scan_buf: PackedInt32Array = PackedInt32Array()  ## scratch for spatial queries of scans / assist
var urgent_used: int = 0  ## urgent scans spent this tick (scratch, cap 16)
var salvage_enabled: int = 0  ## 1 when some player's roster has the salvage ability (derived from the data at init; wrecks exist only then)
var chain_q: PackedInt32Array = PackedInt32Array()  ## chain strikes over the per-tick cap, SimDeath.CHAIN_REC ints each (checksummed)
var chain_tick: int = -1  ## scratch: tick of chain_n
var chain_n: int = 0  ## scratch: chain strikes spawned in chain_tick
var _registered: bool = false


func _init() -> void:
	stage_no = 8
	counters.resize(CNT_N)


## Builds the compiled tables (one per player view + the neutral one), the matrix copy and the alert throttle.
func init_world(world: SimWorld) -> void:
	matrix_bp = world.data.damage.matrix_bp.duplicate()
	n_armor = DefEnums.ArmorClass.COUNT
	neutral_tables = SimCombatTables.build(world.data, null)
	tables.clear()
	for p: SimPlayer in world.players:
		tables.append(SimCombatTables.build(world.data, p.view) if p.view != null else null)
	var n: int = SimConfig.MAX_PLAYERS + 1
	alert_tick.resize(n)
	alert_tick.fill(SimCombatConsts.NEVER)
	alert_x.resize(n)
	alert_y.resize(n)
	SimDeath.compile(world, self)
	salvage_enabled = 0
	for p2: SimPlayer in world.players:
		if p2.view == null:
			continue
		for u: DefUnit in p2.view.roster.units:
			if u != null and ((u.ability_mask >> DefEnums.AbilityKind.SALVAGE) & 1) == 1:
				salvage_enabled = 1
	_register(world)


## Order handlers (attack, attack-move, guard, hold, force-fire, return-to-base), the idle engagement handler and the
## executors of CMD_SET_STANCE / CMD_SCUTTLE. Once per world (init_world may run again in tests).
func _register(world: SimWorld) -> void:
	if _registered or world.orders == null or world.commands == null:
		return
	_registered = true
	for t: int in [SimOrder.T_ATTACK, SimOrder.T_ATTACK_MOVE, SimOrder.T_GUARD, SimOrder.T_HOLD, SimOrder.T_FORCE_FIRE, SimOrder.T_RETURN_BASE]:
		if not world.orders.has_handler(t):
			world.orders.register_handler(t, SimOrderCombat.new(t))
	world.orders.register_idle(SimOrderCombat.new(SimOrder.T_NONE))
	world.commands.register_executor(SimCmd.SET_STANCE, SimOrderCombat.cmd_set_stance)
	world.commands.register_executor(SimCmd.SCUTTLE, SimOrderCombat.cmd_scuttle)


# ---- tables ----
func tables_of(pid: int) -> SimCombatTables:
	if pid >= 0 and pid < tables.size() and tables[pid] != null:
		return tables[pid]
	return neutral_tables


## The compiled def of an entity (its owner's table, else the neutral one); null for unknown defs.
func def_for(_world: SimWorld, e: SimEntity) -> SimCombatDef:
	var d: SimCombatDef = tables_of(e.owner).def_of(e.kind, e.def_idx)
	if d == null:
		d = neutral_tables.def_of(e.kind, e.def_idx)
	return d


## Damage matrix in bp for (damage type, armor class).
func matrix(dtype: int, armor: int) -> int:
	return matrix_bp[dtype * n_armor + armor]


## The victim owner's permanent research resistance against `dtype` (bp, unconditional, layer 3).
func research_resist_bp(world: SimWorld, v: SimEntity, dtype: int) -> int:
	if v.owner < 0 or v.owner >= world.players.size() or (v.kind != SimEntity.Kind.UNIT and v.kind != SimEntity.Kind.STRUCTURE):
		return 0
	var view: DefPlayerView = world.players[v.owner].view
	if view == null:
		return 0
	return view.research_resist_bp(SimDefs.DEF_KIND[v.kind], v.def_idx, dtype)


## Static EMP duration reduction (bp) from the def param `emp_recovery_bp` (Buried Command Lines / Resilient Mesh
## multiply it to 7500 -> 2500 reduction), 0 without research.
func emp_recover_bp(world: SimWorld, v: SimEntity) -> int:
	if v.owner < 0 or v.owner >= world.players.size():
		return 0
	var view: DefPlayerView = world.players[v.owner].view
	if view == null:
		return 0
	var folded: int = 10000
	if v.kind == SimEntity.Kind.UNIT:
		folded = view.layer3.def_param(v.def_idx, "emp_recovery_bp", 10000)
	elif v.kind == SimEntity.Kind.STRUCTURE:
		folded = view.layer3.struct_def_param(v.def_idx, "emp_recovery_bp", 10000)
	return clampi(10000 - folded, 0, 10000)


# ---- pipeline stage 8 ----
func update(world: SimWorld) -> void:
	_upkeep(world)
	SimDeath.drain_chains(world, self)
	SimAirSortie.update_all(world, self)  # P2 (carriers: CB-09)
	urgent_used = 0
	SimTargeting.run_scans(world, self)  # P3
	weapons.update_all(world, self)  # P4
	proj.update(world)  # P5
	SimDamage.flush(world)


## P1: lease expiry + aggregate refresh, EMP / weapon-lock expiry, suppression countdown; drops finished entries.
func _upkeep(world: SimWorld) -> void:
	if status_ids.is_empty():
		return
	var tick: int = world.tick
	var keep: PackedInt32Array = PackedInt32Array()
	for id: int in status_ids:
		var e: SimEntity = world.get_entity(id)
		if e == null or e._gone or e.combat == null:
			continue
		var cc: SimCompCombat = e.combat
		var active: bool = SimCombatMods.refresh(cc, tick)
		if cc.dying_until > 0 and SimDeath.crash_step(world, self, e, cc):
			active = true
		if cc.emp_until != 0:
			if tick >= cc.emp_until:
				cc.emp_until = 0
				if e.kind != SimEntity.Kind.STRUCTURE and cc.wlock_until <= tick:
					world.emit(SimCombatConsts.EV_WEAPON_LOCK, e.x, e.y, e.id, 0, 0)
			else:
				active = true
		if cc.wlock_until != 0:
			if tick >= cc.wlock_until:
				cc.wlock_until = 0
				if cc.emp_until == 0:
					world.emit(SimCombatConsts.EV_WEAPON_LOCK, e.x, e.y, e.id, 0, 1)
			else:
				active = true
		if cc.emp_until == 0:
			e.flags &= ~SimFlags.F_EMP_SHUT
		if cc.emp_until == 0 and cc.wlock_until == 0:
			e.flags &= ~SimFlags.F_WEAPONS_OFF
		if cc.sup_left_q8 > 0:
			cc.sup_left_q8 -= 256 * (10000 + SimCombatMods.sum_bp(cc, SimCombatConsts.STAT_SUP_RECOVER, tick)) / 10000
			if cc.sup_left_q8 <= 0:
				cc.sup_left_q8 = 0
				e.flags &= ~SimFlags.F_SUPPRESSED
				world.emit(SimCombatConsts.EV_SUPPRESS, e.x, e.y, e.id, 0)
			else:
				active = true
		if cc.dying_until > tick:
			active = true
		if active:
			keep.append(id)
	status_ids = keep


func cleanup(world: SimWorld) -> void:
	SimDeath.cleanup(world, self)


## The death sequence of combat 5.11 (wreck, occupants, chain blast, crash, EV_DEATH) runs here, at stage 11.
func on_dying(world: SimWorld, e: SimEntity, cause: int, killer_id: int, killer_pid: int) -> void:
	SimDeath.on_dying(world, self, e, cause, killer_id, killer_pid)


## A new order ends the "idle position": the unit re-anchors where it becomes idle next.
func order_gate(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
	if e.combat != null:
		e.combat.anchor_on = 0
		if e.air != null and (o.type < SimOrder.T_ATTACK or o.type > SimOrder.T_RETURN_BASE):
			SimAirSortie.release_mission(world, e)  # a move / patrol / land order takes the controls
	return 0


# ---- lifecycle hooks (called by SimWorld) ----
func on_spawn(world: SimWorld, e: SimEntity) -> void:
	var cc: SimCompCombat = SimCompCombat.new()
	e.combat = cc
	cc.scan_next = world.tick
	cc.last_assist_tick = SimCombatConsts.NEVER
	var cd: SimCombatDef = def_for(world, e)
	cc.scan_next = world.tick + e.id % SimTargeting.scan_interval(e, cd)
	var armed_kind: bool = e.kind == SimEntity.Kind.UNIT or e.kind == SimEntity.Kind.STRUCTURE
	if cd != null and armed_kind:
		_init_mounts(cc, cd)
		cc.stance = cd.stance_default
		cc.cflags |= cd.cflags
		cc.aps_next.resize(cd.aps_count)
	if (e.flags & SimFlags.F_SUMMONED) != 0:
		cc.cflags |= SimCombatConsts.CF_SUMMONED
	if (e.flags & SimFlags.F_DECOY) != 0:
		cc.cflags |= SimCombatConsts.CF_DECOY
	if (e.flags & SimFlags.F_INVULNERABLE) != 0:
		cc.cflags |= SimCombatConsts.CF_INVULNERABLE
	var armed: bool = cc.n_mounts > 0
	if cd != null and e.kind == SimEntity.Kind.UNIT and cd.is_aircraft == 1:
		e.air = SimCompAir.new()
		_insert_sorted(air_ids, e.id)
		armed = true
		SimAirSortie.init_aircraft(world, e, cd)
	elif cd != null and e.kind == SimEntity.Kind.STRUCTURE and cd.pad_count > 0:
		var af: SimCompAir = SimCompAir.new()
		af.is_airfield = 1
		af.pad_occ.resize(cd.pad_count)
		af.pad_occ.fill(-1)
		e.air = af
		armed = true
	if cd != null and e.kind == SimEntity.Kind.UNIT and cd.carrier_bays > 0:
		var car: SimCompCarrier = SimCompCarrier.new()
		car.bay_id.resize(cd.carrier_bays)
		car.bay_id.fill(-1)
		car.bay_state.resize(cd.carrier_bays)
		car.bay_timer.resize(cd.carrier_bays)
		e.carrier = car
		_insert_sorted(carrier_ids, e.id)
		armed = true
	if armed:
		_insert_sorted(armed_ids, e.id)
	if e.kind == SimEntity.Kind.WRECK:
		_insert_sorted(wreck_ids, e.id)


func on_remove(world: SimWorld, e: SimEntity, _reason: int) -> void:
	_remove_sorted(armed_ids, e.id)
	_remove_sorted(wreck_ids, e.id)
	_remove_sorted(status_ids, e.id)
	_remove_sorted(air_ids, e.id)
	_remove_sorted(carrier_ids, e.id)
	if e.air != null and e.air.is_airfield == 0 and e.air.home_kind == SimCombatConsts.HOME_AIRFIELD:
		SimAirSortie.release_links(world, self, e)


## Capture: drops target, orders link (anchor, hold), leases and focus, resets the stance and asks for a rescan.
func on_owner_changed(world: SimWorld, e: SimEntity, _old_owner: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return
	cc.target_id = -1
	cc.target_src = SimCombatConsts.TS_NONE
	cc.ground_on = 0
	cc.anchor_on = 0
	cc.hold_pos = 0
	cc.focus_mask = 0
	cc.scan_next = world.tick
	SimCombatMods.clear_all(cc)
	var cd: SimCombatDef = def_for(world, e)
	if cd != null and (e.kind == SimEntity.Kind.UNIT or e.kind == SimEntity.Kind.STRUCTURE):
		cc.stance = cd.stance_default
		cc.cflags = (cc.cflags & ~(SimCombatConsts.CF_HAS_AA | SimCombatConsts.CF_HAS_ASW | SimCombatConsts.CF_SUPPRESSIBLE)) | cd.cflags
		if cd.n_mounts != cc.n_mounts:
			_init_mounts(cc, cd)
		cc.aps_next.resize(cd.aps_count)
	note_status(e.id)


## Everybody who was shooting at the eliminated player's entities drops the target and rescans.
func on_player_eliminated(world: SimWorld, pid: int) -> void:
	for id: int in armed_ids:
		var e: SimEntity = world.get_entity(id)
		if e == null or e.combat == null:
			continue
		var cc: SimCompCombat = e.combat
		if cc.target_id >= 0:
			var t: SimEntity = world.get_entity(cc.target_id)
			if t == null or t.owner == pid:
				SimTargeting.clear_target(e)
				cc.scan_next = world.tick
		for m: int in cc.n_mounts:
			var b: int = m * SimCombatConsts.MS + SimCombatConsts.M_TARGET
			var mt: SimEntity = world.get_entity(cc.mnt[b]) if cc.mnt[b] >= 0 else null
			if mt != null and mt.owner == pid and cc.mnt[b] >= 0 and _is_indep(world, e, m):
				cc.mnt[b] = -1
				cc.scan_next = world.tick


func _is_indep(world: SimWorld, e: SimEntity, m: int) -> bool:
	var cd: SimCombatDef = def_for(world, e)
	return cd != null and cd.n_mounts > 1 and cd.mount_val(m, SimCombatDef.MT_INDEP) == 1


## Authoritative system-private ints: scan cursor and the (normally empty) damage queue.
func hash_state(_world: SimWorld, buf: PackedInt32Array) -> void:
	buf.append(scan_cursor)
	buf.append(dmg_queue.size())
	buf.append_array(dmg_queue)
	buf.append(chain_q.size())
	buf.append_array(chain_q)
	proj.hash_into(buf)


## DEBUG mode 5: set the hit points of `target` to `count` (clamped 1..hp_max).
func on_debug(world: SimWorld, _pid: int, mode: int, target: int, _def_idx: int, count: int, _x: int, _y: int) -> int:
	if mode != 5:
		return -1
	var t: SimEntity = world.get_entity(target)
	if t == null:
		return SimCommand.Err.NO_TARGET
	t.hp = clampi(count, 1, maxi(t.hp_max, 1))
	return SimCommand.Err.OK


# ---- health (the only writers of SimEntity.hp: heal, rescale_hp, SimDamage.flush) ----
## Adds up to `amount` hp (> 0), never above hp_max, ignored for dead entities. Returns the hp actually restored.
func heal(_world: SimWorld, e: SimEntity, amount: int) -> int:
	if amount <= 0 or (e.flags & SimFlags.F_GONE) != 0 or e.hp_max <= 0:
		return 0
	var restored: int = mini(amount, e.hp_max - e.hp)
	if restored <= 0:
		return 0
	e.hp += restored
	return restored


## New hp_max (research): hp keeps its fraction (half-up), min 1 while alive. Delegates to the kernel's hp_max writer.
func rescale_hp(world: SimWorld, e: SimEntity, new_hp_max: int) -> void:
	world.set_hp_max(e, new_hp_max)


## Idempotent death request; the kernel finishes it at stage 11. `killer_id` / `killer_pid` -1 = none.
## The rest of the sequence (wrecks, occupants, chain effects, crash) runs in on_dying at stage 11.
func kill(world: SimWorld, e: SimEntity, cause: int, killer_id: int, killer_pid: int) -> void:
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return
	if e.combat != null:
		e.combat.cflags |= SimCombatConsts.CF_DEAD
	world.kill(e, cause, maxi(killer_id, 0), killer_pid)


## true iff WF_SALVAGEABLE and not consumed and team(salvager) != team(wreck owner) (allied wrecks pay nothing). The trait
## check and the 8 s action are economy's.
func wreck_can_be_salvaged_by(world: SimWorld, wreck: SimEntity, salvager_pid: int) -> bool:
	return SimDeath.wreck_can_be_salvaged_by(world, wreck, salvager_pid)


## Atomic: consumes an eligible wreck and returns half_up(wreck_value * payout_pct / 100), else -1.
func try_salvage(world: SimWorld, wreck_id: int, salvager_pid: int, payout_pct: int) -> int:
	return SimDeath.try_salvage(world, wreck_id, salvager_pid, payout_pct)


func scuttle(world: SimWorld, e: SimEntity) -> void:
	if e.combat != null:
		e.combat.cflags |= SimCombatConsts.CF_SCUTTLED
	kill(world, e, SimCombatConsts.CAUSE_SCUTTLE, -1, -1)


# ---- fire control (3.4; logic in SimTargeting) ----
func set_stance(e: SimEntity, stance: int) -> void:
	if e.combat != null:
		e.combat.stance = stance


## Validates can_engage (force for TS_FORCE) and sets the target; false when refused.
func set_target(world: SimWorld, e: SimEntity, target_id: int, src: int) -> bool:
	return SimTargeting.set_target(world, e, target_id, src)


func set_ground_target(e: SimEntity, gx: int, gy: int) -> void:
	SimTargeting.set_ground_target(e, gx, gy)


func clear_target(e: SimEntity, keep_auto: bool = false) -> void:
	SimTargeting.clear_target(e, keep_auto)


## Weapons offline until `until_tick` (never shortened): Aurora-class effects, Surge / Capacitor cooldowns, repair locks.
## Registers the entity for upkeep so the F_WEAPONS_OFF mirror and EV_WEAPON_LOCK come back with it.
func lock_weapons(world: SimWorld, e: SimEntity, until_tick: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null or until_tick <= world.tick or until_tick <= cc.wlock_until:
		return
	var was_off: bool = cc.emp_until > world.tick or cc.wlock_until > world.tick
	cc.wlock_until = until_tick
	e.flags |= SimFlags.F_WEAPONS_OFF
	note_status(e.id)
	if not was_off and e.kind != SimEntity.Kind.STRUCTURE:
		world.emit(SimCombatConsts.EV_WEAPON_LOCK, e.x, e.y, e.id, 1, 1)


## Coordinated Advance: "existing suppression is removed".
func clear_suppression(world: SimWorld, e: SimEntity) -> void:
	SimDamage.clear_suppression(world, e)


func can_attack(world: SimWorld, shooter: SimEntity, target: SimEntity, force: bool = false) -> bool:
	return SimTargeting.can_attack(world, shooter, target, force)


## Warhead reference of mount `m` for the projectile pool: index in the owner's tables (| NEUTRAL_REF when the def
## only exists in the neutral table).
func warhead_ref(_world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int) -> int:
	var idx: int = cd.mount_val(m, SimCombatDef.MT_WH)
	if tables_of(e.owner).def_of(e.kind, e.def_idx) == cd:
		return idx
	return idx | SimProjectiles.NEUTRAL_REF


# ---- read / query API (3.7) ----
func is_alive(e: SimEntity) -> bool:
	return (e.flags & SimFlags.F_GONE) == 0


## Alive, not EMP-shut (unless it carries an EMP-immune lease) and powered when it is a powered defence.
func is_functional(world: SimWorld, e: SimEntity) -> bool:
	if (e.flags & SimFlags.F_GONE) != 0:
		return false
	var cc: SimCompCombat = e.combat
	if cc == null:
		return true
	if cc.emp_until > world.tick and not SimCombatMods.has_flag(cc, SimCombatConsts.STAT_FLAG_EMP_IMMUNE, world.tick):
		return false
	if e.kind == SimEntity.Kind.STRUCTURE:
		var cd: SimCombatDef = def_for(world, e)
		if cd != null and cd.needs_power == 1 and (e.flags & SimFlags.F_POWERED) == 0:
			return false
	return true


func weapons_online(world: SimWorld, e: SimEntity) -> bool:
	if not is_functional(world, e):
		return false
	return e.combat == null or world.tick >= e.combat.wlock_until


func is_suppressed(e: SimEntity) -> bool:
	return e.combat != null and e.combat.sup_left_q8 > 0


## 7500 while suppressed, else 10000 (movement multiplies infantry speed).
func suppression_speed_bp(e: SimEntity) -> int:
	return SimCombatConsts.SUP_SPEED_BP if is_suppressed(e) else 10000


func ticks_since_combat(world: SimWorld, e: SimEntity) -> int:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return world.tick - SimCombatConsts.NEVER
	return world.tick - maxi(cc.last_fire_tick, maxi(cc.last_hit_tick, cc.last_dealt_tick))


## Remaining salvos of a mount (-1 = infinite, also for a missing mount).
func ammo_of(e: SimEntity, mount: int) -> int:
	if e.combat == null or mount < 0 or mount >= e.combat.n_mounts:
		return -1
	return e.combat.mnt[mount * SimCombatConsts.MS + SimCombatConsts.M_AMMO]


## Range in units of `mount` (-1 = the longest) after research and live range leases.
func range_max_eff(world: SimWorld, e: SimEntity, mount: int = -1) -> int:
	var cd: SimCombatDef = def_for(world, e)
	var cc: SimCompCombat = e.combat
	if cd == null or cc == null:
		return 0
	var lease: int = SimCombatMods.sum_bp(cc, SimCombatConsts.STAT_RANGE, world.tick)
	var best: int = 0
	for m: int in cd.n_mounts:
		if mount >= 0 and m != mount:
			continue
		best = maxi(best, DefStatMath.apply_bp(slot_stat(world, e, cd, m, DefEnums.Stat.RANGE), lease))
	return best


## Minimum range in units of `mount` (-1 = the shortest positive one); range modifiers never change it.
func range_min_of(world: SimWorld, e: SimEntity, mount: int = -1) -> int:
	var cd: SimCombatDef = def_for(world, e)
	if cd == null:
		return 0
	var best: int = 0
	for m: int in cd.n_mounts:
		if mount >= 0 and m != mount:
			continue
		var r: int = cd.slots[cd.slot_of_mount(m)].min_range
		if best == 0 or (r > 0 and r < best):
			best = r
	return best


## Expected damage per 100 ticks of `shooter` against `target` (incl. matrix; no modifiers from the other side).
func dp100(world: SimWorld, shooter: SimEntity, target: SimEntity) -> int:
	var cd: SimCombatDef = def_for(world, shooter)
	var td: SimCombatDef = def_for(world, target)
	if cd == null or td == null:
		return 0
	var total: int = 0
	for m: int in cd.n_mounts:
		var s: DefWeaponSlot = cd.slots[cd.slot_of_mount(m)]
		if ((s.target_mask >> target.layer) & 1) == 0:
			continue
		var wh: SimCombatWarhead = tables_of(shooter.owner).warheads[cd.mount_val(m, SimCombatDef.MT_WH)]
		var reload: int = maxi(slot_stat(world, shooter, cd, m, DefEnums.Stat.RELOAD), 1)
		total += slot_stat(world, shooter, cd, m, DefEnums.Stat.DAMAGE) * s.hits_per_volley * matrix(wh.dtype, td.armor) * 10 / reload
	return total


## A weapon stat of mount `m` (DefEnums.Stat.DAMAGE / RANGE / RELOAD (milli-ticks) / PROJ_SPEED) after the owner's
## static layers and permanent research (no temporary leases).
func slot_stat(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int, stat: int) -> int:
	var col: int = -1
	match stat:
		DefEnums.Stat.DAMAGE:
			col = 0
		DefEnums.Stat.RANGE:
			col = 1
		DefEnums.Stat.RELOAD:
			col = 2
		DefEnums.Stat.PROJ_SPEED:
			col = 3
		_:
			return 0
	var ver: int = 0
	if e.owner >= 0 and e.owner < world.players.size() and world.players[e.owner].view != null:
		ver = world.players[e.owner].view.version
	if cd.st_ver != ver or cd.st.size() != cd.n_mounts * 4:
		cd.st.resize(cd.n_mounts * 4)
		for mm: int in cd.n_mounts:
			cd.st[mm * 4] = _slot_stat_raw(world, e, cd, mm, DefEnums.Stat.DAMAGE)
			cd.st[mm * 4 + 1] = _slot_stat_raw(world, e, cd, mm, DefEnums.Stat.RANGE)
			cd.st[mm * 4 + 2] = _slot_stat_raw(world, e, cd, mm, DefEnums.Stat.RELOAD)
			cd.st[mm * 4 + 3] = _slot_stat_raw(world, e, cd, mm, DefEnums.Stat.PROJ_SPEED)
		cd.st_ver = ver
	return cd.st[m * 4 + col]


## Marks every cached weapon stat stale (tests that edit weapon slots; research bumps the view version instead).
func invalidate_stats() -> void:
	var lists: Array = []
	for t: SimCombatTables in tables:
		if t != null:
			lists.append(t)
	lists.append(neutral_tables)
	for tb: Variant in lists:
		for d: SimCombatDef in (tb as SimCombatTables).units:
			if d != null:
				d.st_ver = -1
		for d2: SimCombatDef in (tb as SimCombatTables).structures:
			if d2 != null:
				d2.st_ver = -1


func _slot_stat_raw(world: SimWorld, e: SimEntity, cd: SimCombatDef, m: int, stat: int) -> int:
	var si: int = cd.slot_of_mount(m)
	var view: DefPlayerView = world.players[e.owner].view if (e.owner >= 0 and e.owner < world.players.size()) else null
	if view != null and e.kind == SimEntity.Kind.UNIT and view.roster.has_unit(e.def_idx):
		return view.effective_slot_value(e.def_idx, si, stat)
	var s: DefWeaponSlot = cd.slots[si]
	var raw: int = 0
	match stat:
		DefEnums.Stat.DAMAGE:
			raw = s.damage
		DefEnums.Stat.RANGE:
			raw = s.range
		DefEnums.Stat.RELOAD:
			raw = s.reload_mt
		DefEnums.Stat.PROJ_SPEED:
			raw = s.proj_speed
		_:
			return 0
	if view != null and e.kind == SimEntity.Kind.STRUCTURE and view.roster.has_structure(e.def_idx) and e.def_idx < world.data.structures.size():
		var base_s: DefStructure = world.data.structures[e.def_idx]
		var bs: DefWeaponSlot = base_s.weapons[si] if si < base_s.weapons.size() else s
		var base_v: int = bs.damage if stat == DefEnums.Stat.DAMAGE else (bs.range if stat == DefEnums.Stat.RANGE else (bs.reload_mt if stat == DefEnums.Stat.RELOAD else bs.proj_speed))
		return DefStatMath.effective(stat, base_v, raw, view.layer3.struct_stat_bp(stat, e.def_idx), world.data.economy)
	return raw


## Registers `id` for P1 upkeep (idempotent, keeps the list ascending).
func note_status(id: int) -> void:
	_insert_sorted(status_ids, id)


func debug_string(world: SimWorld, e: SimEntity) -> String:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return "combat: none"
	return "combat: stance %d target %d(src %d) mounts %d cflags %d emp_until %d wlock %d sup %d mods %d hit %d dealt %d fire %d tick %d" % [
		cc.stance, cc.target_id, cc.target_src, cc.n_mounts, cc.cflags, cc.emp_until, cc.wlock_until, cc.sup_left_q8,
		cc.mods.size(), cc.last_hit_tick, cc.last_dealt_tick, cc.last_fire_tick, world.tick]


## Debug / test check that the derived id lists equal a recomputation from entity state (empty = ok). status_ids
## must be a superset of the entities that currently need upkeep.
func verify_indexes(world: SimWorld) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var armed: PackedInt32Array = PackedInt32Array()
	var wrecks: PackedInt32Array = PackedInt32Array()
	var airs: PackedInt32Array = PackedInt32Array()
	var carriers: PackedInt32Array = PackedInt32Array()
	var all: Array[SimEntity] = world.entities.duplicate()
	all.append_array(world._spawn_queue)  # spawned this tick, not listed yet (ids ascending)
	for e: SimEntity in all:
		if e._gone:
			continue
		var cc: SimCompCombat = e.combat
		if cc == null:
			continue
		if cc.n_mounts > 0 or e.air != null or e.carrier != null:
			armed.append(e.id)
		if e.kind == SimEntity.Kind.WRECK:
			wrecks.append(e.id)
		if e.air != null and e.air.is_airfield == 0:
			airs.append(e.id)
		if e.carrier != null:
			carriers.append(e.id)
		var timed: bool = cc.emp_until > 0 or cc.wlock_until > 0 or cc.sup_left_q8 > 0 or cc.dying_until > world.tick
		if timed and not status_ids.has(e.id):
			problems.append("status_ids misses %d" % e.id)
	if armed != armed_ids:
		problems.append("armed_ids differ")
	if wrecks != wreck_ids:
		problems.append("wreck_ids differ")
	if airs != air_ids:
		problems.append("air_ids differ")
	if carriers != carrier_ids:
		problems.append("carrier_ids differ")
	return problems


# ---- internals ----
func _init_mounts(cc: SimCompCombat, cd: SimCombatDef) -> void:
	cc.n_mounts = cd.n_mounts
	cc.mnt.resize(cd.n_mounts * SimCombatConsts.MS)
	cc.mnt.fill(0)
	for m: int in cd.n_mounts:
		var b: int = m * SimCombatConsts.MS
		var ammo: int = cd.slots[cd.slot_of_mount(m)].ammo_volleys
		cc.mnt[b + SimCombatConsts.M_AMMO] = ammo if ammo > 0 else -1
		cc.mnt[b + SimCombatConsts.M_ANGLE] = cd.mount_val(m, SimCombatDef.MT_ARC_CENTER)
		cc.mnt[b + SimCombatConsts.M_TARGET] = -1
		cc.mnt[b + SimCombatConsts.M_AIM_SINCE] = -1
		cc.mnt[b + SimCombatConsts.M_BEAM] = -1


static func _insert_sorted(a: PackedInt32Array, id: int) -> void:
	var i: int = a.bsearch(id)
	if i < a.size() and a[i] == id:
		return
	a.insert(i, id)


static func _remove_sorted(a: PackedInt32Array, id: int) -> void:
	var i: int = a.bsearch(id)
	if i < a.size() and a[i] == id:
		a.remove_at(i)
