class_name SimDeath
extends RefCounted
## Health, death, wrecks, chain effects and the crash of aircraft (combat 5.11, task CB-07). Stateless statics; the
## persistent state lives in SimCompCombat (dying_until, crash_v*, wreck_*) and SimCombatSystem (chain_q).
##
## The kernel defers every kill to stage 11: `SimCombatSystem.on_dying` calls `SimDeath.on_dying` once per dead entity
## (ascending id) before removal. There the ordered sequence runs: links, occupants, wreck, chain blast, crash,
## EV_DEATH, lingering corpse. Data note: the data module has no death profile, so `compile` DERIVES one per def from
## its tags / abilities / stats and stores it in the SimCombatDef (chain and crash warheads live in the neutral
## warhead table and are referenced with SimProjectiles.NEUTRAL_REF).

const CHAIN_REC: int = 6  ## chain_q record: x, y, warhead ref, pid, source id, delay
const SINK_TICKS: int = 40
const CRASH_TICKS: int = 30
const LAND_LAYERS: int = 5  ## ground | surface: layer mask of chain / crash blasts
const GARRISON_HURT_BP: int = 2500
const REINFORCED_HURT_BP: int = 3000
const DK_FLAG_WRECK: int = 1
const DK_FLAG_CRASH: int = 2
const DK_FLAG_DECOY: int = 4
const DK_FLAG_SUMMONED: int = 8
const DK_FLAG_STRUCT: int = 16
const DK_FLAG_OCC: int = 32
const DK_FLAG_UNIT: int = 64
const DK_FLAG_AIR: int = 128


# ---------------------------------------------------------------------------------------------- compile (match start)
## Derives the death profile of every def and writes it into the SimCombatDefs of every table (player tables and the
## neutral one). Chain / crash warheads are appended to the neutral table. Call after the tables were built.
static func compile(world: SimWorld, cs: SimCombatSystem) -> void:
	var d: GameData = world.data
	var nt: SimCombatTables = cs.neutral_tables
	var all: Array[SimCombatTables] = [nt]
	for t: SimCombatTables in cs.tables:
		if t != null:
			all.append(t)
	for i: int in d.units.size():
		var pr: PackedInt32Array = _unit_profile(d.units[i], nt)
		for t: SimCombatTables in all:
			var c: SimCombatDef = t.units[i]
			if c != null:
				_apply(c, pr)
	for i: int in d.structures.size():
		var pr: PackedInt32Array = _struct_profile(d.structures[i], nt)
		for t: SimCombatTables in all:
			var c: SimCombatDef = t.structures[i]
			if c != null:
				_apply(c, pr)
	for i: int in d.neutrals.size():
		var pr: PackedInt32Array = PackedInt32Array([SimCombatConsts.DK_STRUCTURE, 1, 0, -1, 0, -1, 3, 0, -1])
		if d.neutrals[i].neutral_kind == DefEnums.NeutralKind.CIVILIAN_GARRISON:
			pr[3] = SimCombatConsts.CARGO_EJECT_HURT
			pr[4] = GARRISON_HURT_BP
		for t: SimCombatTables in all:
			var c: SimCombatDef = t.neutrals[i]
			if c != null:
				_apply(c, pr)


## Profile row: [death_kind, dying_ticks, wreck_hp_bp, cargo_mode, eject_hurt_bp, chain_wh, chain_delay, crash_ticks, crash_wh].
static func _unit_profile(u: DefUnit, nt: SimCombatTables) -> PackedInt32Array:
	var pr: PackedInt32Array = PackedInt32Array([SimCombatConsts.DK_VEHICLE, 1, 0, -1, 0, -1, 3, CRASH_TICKS, -1])
	var tags: int = u.tags
	if (tags & DefEnums.UT_AIRCRAFT) != 0:
		if (tags & DefEnums.UT_UNMANNED) != 0:
			pr[0] = SimCombatConsts.DK_AIR_EXPLODE
		else:
			pr[0] = SimCombatConsts.DK_CRASH
			pr[1] = CRASH_TICKS
			pr[8] = _add_blast(nt, "crash." + u.id, clampi(u.health / 20, 30, 300), 1536)
	elif (tags & DefEnums.UT_INFANTRY) != 0:
		pr[0] = SimCombatConsts.DK_INFANTRY
	elif (tags & (DefEnums.UT_SHIP | DefEnums.UT_SUBMARINE)) != 0:
		pr[0] = SimCombatConsts.DK_SINK
		pr[1] = SINK_TICKS
	if (tags & DefEnums.UT_LAND_VEHICLE) != 0 and (tags & DefEnums.UT_COMBAT) != 0:
		pr[2] = 3000
	var tra: DefAbility = u.ability_of(DefEnums.AbilityKind.TRANSPORT)
	if tra != null or (tags & DefEnums.UT_TRANSPORT) != 0:
		pr[3] = SimCombatConsts.CARGO_DIE
		if tra != null and int(tra.params.get("passenger_damage_reduction_bp", 0)) > 0:
			pr[3] = SimCombatConsts.CARGO_EJECT_HURT
			pr[4] = REINFORCED_HURT_BP
	return pr


static func _struct_profile(s: DefStructure, nt: SimCombatTables) -> PackedInt32Array:
	var pr: PackedInt32Array = PackedInt32Array([SimCombatConsts.DK_STRUCTURE, 1, 0, -1, 0, -1, 3, 0, -1])
	var strategic: bool = (s.flags & DefEnums.SF_STRATEGIC) != 0 or (s.tags & DefEnums.ST_SUPERWEAPON) != 0
	if strategic or s.power > 0 or s.queue_kind == DefEnums.QueueKind.COLLECTOR:
		var r: int = maxi(1536, s.radius * 2)
		if strategic:
			r = 3072
		pr[5] = _add_blast(nt, "chain." + s.id, clampi(s.health / 10, 40, 500), r)
	return pr


static func _add_blast(nt: SimCombatTables, label: String, damage: int, radius: int) -> int:
	var w: SimCombatWarhead = SimCombatWarhead.new()
	w.id = label
	w.damage = damage
	w.dtype = SimCombatConsts.DT_HE
	w.delivery = SimCombatConsts.DELIV_DIRECT
	w.splash_r = radius
	w.splash_inner = radius / 4
	w.splash_edge_bp = 2500
	w.layer_mask = LAND_LAYERS
	w.friendly_fire = 1
	return nt.add_warhead(w) | SimProjectiles.NEUTRAL_REF


static func _apply(c: SimCombatDef, pr: PackedInt32Array) -> void:
	c.death_kind = pr[0]
	c.dying_ticks = pr[1]
	c.wreck_hp_bp = pr[2]
	c.cargo_mode = pr[3]
	c.eject_hurt_bp = pr[4]
	c.chain_wh = pr[5]
	c.chain_delay = pr[6]
	c.crash_ticks = pr[7]
	c.crash_wh = pr[8]


# ---------------------------------------------------------------------------------------------- the death sequence
## Stage 11, once per kill (ascending id), before removal. Idempotent per entity by construction (the kernel calls it once).
static func on_dying(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cause: int, killer_id: int, killer_pid: int) -> void:
	var cc: SimCompCombat = e.combat
	if cc == null:
		return
	cc.cflags |= SimCombatConsts.CF_DEAD
	if e.kind == SimEntity.Kind.WRECK:  # a wreck is only removed: no chain, no wreck, no occupants
		if (cc.wreck_flags & SimCombatConsts.WF_CONSUMED) == 0:
			world.emit(SimCombatConsts.EV_WRECK_REMOVE, e.x, e.y, e.id, 1)
		return
	if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE and e.kind != SimEntity.Kind.NEUTRAL:
		return
	var tick: int = world.tick
	var cd: SimCombatDef = cs.def_for(world, e)
	var dk: int = cd.death_kind if cd != null else SimCombatConsts.DK_SILENT
	var dying: int = cd.dying_ticks if cd != null else 1
	if cd != null and dk == SimCombatConsts.DK_CRASH and e.layer != SimCombatConsts.LAYER_AIR:
		dk = SimCombatConsts.DK_VEHICLE  # a parked aircraft is a ground wreck, it does not fall
		dying = 1
	var flags: int = 0
	# (1) links: target, beams, salvo remainder; pads and bays
	SimTargeting.clear_target(e)
	SimAirSortie.release_links(world, cs, e)
	# (3) occupants
	var kid: int = killer_id if killer_id > 0 else -1
	if cd != null and cd.cargo_mode >= 0 and _occupants(world, cs, e, cd, killer_id, killer_pid) > 0:
		flags |= DK_FLAG_OCC
	# (4) wreck
	if cd != null and _make_wreck(world, cs, e, cd, cause, killer_pid):
		flags |= DK_FLAG_WRECK
	# (5) chain effect
	if cd != null and cd.chain_wh >= 0:
		_chain(world, cs, e.x, e.y, cd.chain_wh, killer_pid if killer_pid >= 0 else e.owner, e.id, cd.chain_delay)
	# (6) aircraft crash
	if dk == SimCombatConsts.DK_CRASH:
		flags |= DK_FLAG_CRASH
		cc.dying_until = tick + dying
		cc.death_kind = dk
		cc.crash_vx = e.vx
		cc.crash_vy = e.vy
		cs.note_status(e.id)
		world.emit(SimCombatConsts.EV_CRASH, e.x, e.y, e.id, 0, dying)
	if dying > 1:
		cc.cflags |= SimCombatConsts.CF_DYING
	if (cc.cflags & SimCombatConsts.CF_DECOY) != 0:
		flags |= DK_FLAG_DECOY
	if (cc.cflags & SimCombatConsts.CF_SUMMONED) != 0:
		flags |= DK_FLAG_SUMMONED
	if e.kind == SimEntity.Kind.UNIT:
		flags |= DK_FLAG_UNIT
		if cd != null and cd.is_aircraft == 1:
			flags |= DK_FLAG_AIR
	elif e.kind == SimEntity.Kind.STRUCTURE:
		flags |= DK_FLAG_STRUCT
	# (8) EV_DEATH (player statistics are the kernel's) and the lingering corpse
	world.emit(SimCombatConsts.EV_DEATH, e.x, e.y, e.id, e.def_idx, dk | (cause << 4) | (flags << 8), kid,
		(killer_pid + 1) | ((e.owner + 1) << 8), e.facing | (e.layer << 12) | (dying << 16))
	if dying > 1:
		world.remove_deferred(e.id, tick + dying)


## Passengers of a dying container (units with container_id == e.id). Returns how many there were.
static func _occupants(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cd: SimCombatDef, killer_id: int, killer_pid: int) -> int:
	if e.cargo != null:  # FIX (abilities AB2): containers of the abilities domain eject through SimTransport
		var cids: PackedInt32Array = SimTransport.cargo_of(e)
		if cids.is_empty():
			return 0
		# abilities 5.10.4: transports and garrisons eject their passengers hurt (SimTransport.eject_loss_bp: 40 %, Beaver
		# 20 %, garrison 35 %), never below 1 hp; a passenger with no legal cell drowns (CAUSE_CARGO). This replaces
		# combat's CARGO_DIE default for containers that carry a cargo component.
		SimTransport.eject_all(world, e, SimTransport.eject_loss_bp(world, e))
		for cid: int in cids:
			world.emit(SimCombatConsts.EV_EJECT, e.x, e.y, e.id, cid, 0 if e.kind != SimEntity.Kind.UNIT else 1)
		return cids.size()
	var ids: PackedInt32Array = PackedInt32Array()
	for u: SimEntity in world.units:
		if u.container_id == e.id and (u.flags & SimFlags.F_GONE) == 0:
			ids.append(u.id)
	for id: int in ids:
		var p: SimEntity = world.get_entity(id)
		if cd.cargo_mode == SimCombatConsts.CARGO_DIE:
			cs.kill(world, p, SimCombatConsts.CAUSE_CARGO, killer_id, killer_pid)
			continue
		_eject(world, e, p)
		if cd.cargo_mode == SimCombatConsts.CARGO_EJECT_HURT and p.hp_max > 0:
			var hurt: int = SimDamage.mul(p.hp_max, cd.eject_hurt_bp)
			p.hp = maxi(1, p.hp - hurt)  # non-lethal
		var reason: int = 0 if e.kind != SimEntity.Kind.UNIT else 1
		world.emit(SimCombatConsts.EV_EJECT, e.x, e.y, e.id, p.id, reason)
	return ids.size()


## Puts a passenger back on the map at the nearest free cell of the container (or on it when none is free).
static func _eject(world: SimWorld, c: SimEntity, p: SimEntity) -> void:
	var map: MapData = world.map
	var cell: int = clampi(c.y >> 10, 0, map.h - 1) * map.w + clampi(c.x >> 10, 0, map.w - 1)
	var free: int = SimMovement.find_free_cell_near(world, cell, p.layer, 4)
	var px: int = c.x
	var py: int = c.y
	if free >= 0:
		px = map.center_x(free)
		py = map.center_y(free)
	world.set_pos(p, px, py, true)
	world.set_inside(p, -1, false)
	p.flags &= ~SimFlags.F_GARRISONED


## Wreck of a land combat vehicle killed by an enemy while a salvage-capable player exists. True when created.
static func _make_wreck(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cd: SimCombatDef, cause: int, killer_pid: int) -> bool:
	if e.kind != SimEntity.Kind.UNIT or cd.wreck_hp_bp <= 0 or cause != SimCombatConsts.CAUSE_DAMAGE or cs.salvage_enabled == 0:
		return false
	if killer_pid < 0 or world.rel(killer_pid, e.owner) != SimCombatConsts.REL_ENEMY or e.paid_cost <= 0:
		return false
	if (e.combat.cflags & (SimCombatConsts.CF_SUMMONED | SimCombatConsts.CF_DECOY | SimCombatConsts.CF_SCUTTLED | SimCombatConsts.CF_NO_WRECK)) != 0:
		return false
	var hp: int = maxi(SimCombatConsts.WRECK_HP_MIN, SimDamage.mul(e.hp_max, cd.wreck_hp_bp))
	var w: SimEntity = world.spawn_wreck(e, true, hp, SimCombatConsts.WRECK_TICKS)
	if w == null:
		return false
	var wc: SimCompCombat = w.combat
	wc.wreck_value = e.paid_cost
	wc.wreck_expire = world.tick + SimCombatConsts.WRECK_TICKS
	wc.wreck_flags = SimCombatConsts.WF_SALVAGEABLE
	wc.wreck_owner_pid = e.owner
	wc.wreck_src_def = e.def_idx
	world.emit(SimCombatConsts.EV_WRECK_ADD, w.x, w.y, w.id, e.def_idx, wc.wreck_expire, e.owner, wc.wreck_flags, wc.wreck_value)
	return true


# ---------------------------------------------------------------------------------------------- chain effects
## Spawns the strike at (x, y), at most CHAIN_CAP per tick; the rest waits in cs.chain_q (hashed) in dying order.
static func _chain(world: SimWorld, cs: SimCombatSystem, x: int, y: int, wh_ref: int, pid: int, src_id: int, delay: int) -> void:
	var tick: int = world.tick
	if cs.chain_tick != tick:
		cs.chain_tick = tick
		cs.chain_n = 0
	if cs.chain_n >= SimCombatConsts.CHAIN_CAP or not cs.chain_q.is_empty():
		cs.chain_q.append_array(PackedInt32Array([x, y, wh_ref, pid, src_id, delay]))
		return
	cs.chain_n += 1
	cs.proj.spawn_remote(world, pid, src_id, SimCombatConsts.PK_STRIKE, wh_ref, x, y, x, y, delay, 10000, SimCombatConsts.PI_CHAIN)


## P1: releases deferred chain strikes (oldest first, at most CHAIN_CAP per tick).
static func drain_chains(world: SimWorld, cs: SimCombatSystem) -> void:
	if cs.chain_q.is_empty():
		return
	var tick: int = world.tick
	if cs.chain_tick != tick:
		cs.chain_tick = tick
		cs.chain_n = 0
	var used: int = 0
	var q: PackedInt32Array = cs.chain_q
	while used * CHAIN_REC < q.size() and cs.chain_n < SimCombatConsts.CHAIN_CAP:
		var b: int = used * CHAIN_REC
		cs.chain_n += 1
		cs.proj.spawn_remote(world, q[b + 3], q[b + 4], SimCombatConsts.PK_STRIKE, q[b + 2], q[b], q[b + 1], q[b], q[b + 1], q[b + 5], 10000, SimCombatConsts.PI_CHAIN)
		used += 1
	cs.chain_q = q.slice(used * CHAIN_REC)


# ---------------------------------------------------------------------------------------------- crash (P1)
## A falling aircraft: pos += crash_v, crash_v = crash_v * 15 / 16 (truncating); at dying_until the ground impact.
## Returns true while the entity still needs upkeep.
static func crash_step(world: SimWorld, cs: SimCombatSystem, e: SimEntity, cc: SimCompCombat) -> bool:
	var tick: int = world.tick
	if cc.dying_until <= 0 or cc.death_kind != SimCombatConsts.DK_CRASH:
		return false
	if tick >= cc.dying_until:
		cc.dying_until = 0
		var cd: SimCombatDef = cs.def_for(world, e)
		var pid: int = cc.last_attacker_pid if cc.last_attacker_pid >= 0 else e.owner
		if cd != null and cd.crash_wh >= 0:
			cs.proj.spawn_remote(world, pid, e.id, SimCombatConsts.PK_STRIKE, cd.crash_wh, e.x, e.y, e.x, e.y, 0, 10000, SimCombatConsts.PI_CHAIN)
		world.emit(SimCombatConsts.EV_CRASH, e.x, e.y, e.id, 1, 0)
		return false
	world.set_pos(e, e.x + cc.crash_vx, e.y + cc.crash_vy)
	cc.crash_vx = cc.crash_vx * 15 / 16
	cc.crash_vy = cc.crash_vy * 15 / 16
	return true


# ---------------------------------------------------------------------------------------------- wrecks: salvage API (3.3)
static func wreck_can_be_salvaged_by(world: SimWorld, wreck: SimEntity, salvager_pid: int) -> bool:
	if wreck == null or wreck.kind != SimEntity.Kind.WRECK or (wreck.flags & (SimFlags.F_GONE | SimFlags.F_NO_SALVAGE)) != 0 or wreck.combat == null:
		return false
	var wc: SimCompCombat = wreck.combat
	if (wc.wreck_flags & SimCombatConsts.WF_SALVAGEABLE) == 0 or (wc.wreck_flags & SimCombatConsts.WF_CONSUMED) != 0:
		return false
	return world.team_of(salvager_pid) != world.team_of(wc.wreck_owner_pid)


## Atomic: consumes the wreck (removal scheduled, EV_WRECK_REMOVE reason 2) and returns half_up(value * pct / 100); -1 if
## not eligible.
static func try_salvage(world: SimWorld, wreck_id: int, salvager_pid: int, payout_pct: int) -> int:
	var w: SimEntity = world.get_entity(wreck_id)
	if not wreck_can_be_salvaged_by(world, w, salvager_pid):
		return -1
	var wc: SimCompCombat = w.combat
	wc.wreck_flags |= SimCombatConsts.WF_CONSUMED
	var payout: int = (wc.wreck_value * payout_pct + 50) / 100
	world.emit(SimCombatConsts.EV_WRECK_REMOVE, w.x, w.y, w.id, 2)
	world.remove_entity(w.id, SimEvent.REM_CONSUMED)
	return payout


# ---------------------------------------------------------------------------------------------- cleanup pass (stage 11)
## Expired wrecks leave (EV_WRECK_REMOVE reason 0); a consumed wreck nobody removed yet is dropped (reason 2).
static func cleanup(world: SimWorld, cs: SimCombatSystem) -> void:
	if cs.wreck_ids.is_empty():
		return
	var tick: int = world.tick
	var ids: PackedInt32Array = cs.wreck_ids.duplicate()
	for id: int in ids:
		var w: SimEntity = world.get_entity(id)
		if w == null or (w.flags & SimFlags.F_GONE) != 0 or w.combat == null:
			continue
		var wc: SimCompCombat = w.combat
		if (wc.wreck_flags & SimCombatConsts.WF_CONSUMED) != 0:
			world.emit(SimCombatConsts.EV_WRECK_REMOVE, w.x, w.y, w.id, 2)
			world.remove_entity(id, SimEvent.REM_CONSUMED)
		elif tick >= wc.wreck_expire:
			world.emit(SimCombatConsts.EV_WRECK_REMOVE, w.x, w.y, w.id, 0)
			world.remove_entity(id, SimEvent.REM_EXPIRED)
