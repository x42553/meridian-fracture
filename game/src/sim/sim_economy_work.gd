class_name SimEconomyWork
extends RefCounted
## Engineer-class work of the economy (economy 5.10 - 5.13, task EC3A / E6): the paid repair primitive, the repair
## categories, capture evaluation of neutral tech structures, wreck salvage and the geometry helpers the three order
## handlers (SimOrderRepair / SimOrderCapture / SimOrderSalvage) share. Stateless statics: every piece of state lives
## in components (all hashed): the target's SimCompEcon (repair accumulators, claim, capture channel / progress), the
## wreck's SimCompEcon (salvage claim) and the order (phase, counters).
##
## Encodings that reuse existing SimCompEcon fields (so no new hashed field exists):
##   repair_src_mask   = (tick << 3) | source bits (RS_UNIT | RS_WRENCH | RS_PAD) of the LAST tick a repair step ran.
##                       Read it through `repair_sources(ec, tick)`.
##   unit_repairer_id / unit_repairer_tick   the unit claim of a repair target, and of a WRECK the salvager's claim.
## A land vehicle gets its SimCompEcon lazily (`ensure_econ`) the first time a repair step needs its accumulators, and a
## wreck the first time a salvager claims it (wrecks that nobody salvages stay component-free).

const REACH_U: int = 1536  ## 1.5 cells from the footprint edge (economy 5.13)
const REACH_SLACK_U: int = 1024  ## beyond reach + slack a working unit goes back to APPROACH
const CLAIM_STALE_TICKS: int = 10
const CLAIM_WAIT_TICKS: int = 100
const PAD_RATE_BP: int = 300  ## RC_PAD: 3 % of max hp per second
const HP_UNIT: int = 10000 * SimConfig.TPS  ## one hp in (hp * bp) accumulator units
const CAPTURE_MAX_CHANNELERS: int = 3
const CAPTURE_IDLE_TICKS: int = 100
const CAPTURE_DECAY: int = 2
const CAPTURE_PROGRESS_PERIOD: int = 20
const CAPTURE_CONTEST_PERIOD: int = 40
const REPAIR_FUNDS_PERIOD: int = 100
const FALLBACK_BASIS: int = 600
const HQ_BASIS: int = 3000
const MOVE_RETRY_TICKS: int = 10
const MOVE_MAX_RETRIES: int = 30


# ------------------------------------------------------------------------------------------------- defs and geometry
## The unit's roster-resolved def (the player's clone carries trait grants such as African Empire salvage).
static func udef(world: SimWorld, e: SimEntity) -> DefUnit:
	if e.owner >= 0 and e.owner < world.players.size():
		var r: DefRoster = world.players[e.owner].roster
		if r != null and r.has_unit(e.def_idx):
			return r.unit(e.def_idx)
	return world.data.units[e.def_idx]


## The entity's SimCompEcon, created on demand (deterministic: the component mask is hashed).
static func ensure_econ(e: SimEntity) -> SimCompEcon:
	if e.econ == null:
		var ec: SimCompEcon = SimCompEcon.new()
		ec.paid_cost = e.paid_cost
		if (e.flags & SimFlags.F_NO_REPAIR) != 0:
			ec.flags |= SimEconConst.EF_NO_REPAIR
		if (e.flags & SimFlags.F_NO_CAPTURE) != 0:
			ec.flags |= SimEconConst.EF_NO_CAPTURE
		e.econ = ec
	return e.econ


static func is_structure_like(e: SimEntity) -> bool:
	return e.kind == SimEntity.Kind.STRUCTURE or e.kind == SimEntity.Kind.NEUTRAL


## Footprint half extents (sub-cell units) of a structure / neutral; a unit uses its radius.
static func half_extent(world: SimWorld, e: SimEntity, out: PackedInt32Array) -> void:
	var w: int = 0
	var h: int = 0
	if e.kind == SimEntity.Kind.STRUCTURE:
		var d: DefStructure = world.data.structures[e.def_idx]
		w = d.fp_w
		h = d.fp_h
		if d.fp_w != d.fp_h and (((e.facing >> 10) & 3) & 1) == 1 and (d.place_mask & DefEnums.PLACE_SHORELINE) != 0:
			w = d.fp_h
			h = d.fp_w
	elif e.kind == SimEntity.Kind.NEUTRAL:
		var n: DefNeutral = world.data.neutrals[e.def_idx]
		w = n.fp_w
		h = n.fp_h
	out[0] = w * (SimConfig.CELL / 2) if w > 0 else e.radius
	out[1] = h * (SimConfig.CELL / 2) if h > 0 else e.radius


static var _half: PackedInt32Array = PackedInt32Array([0, 0])


## true if `e` is within `reach` of the target: structure-like targets by the distance to the footprint rectangle, units
## by the distance between the centres minus the target radius.
static func in_reach(world: SimWorld, e: SimEntity, t: SimEntity, reach: int) -> bool:
	if is_structure_like(t):
		half_extent(world, t, _half)
		var dx: int = maxi(absi(e.x - t.x) - _half[0], 0)
		var dy: int = maxi(absi(e.y - t.y) - _half[1], 0)
		return dx * dx + dy * dy <= reach * reach
	var ddx: int = e.x - t.x
	var ddy: int = e.y - t.y
	var r: int = reach + t.radius
	return ddx * ddx + ddy * ddy <= r * r


## Approach range handed to SimMovement.approach_entity so that the circle test of the movement (centre distance minus
## the target radius) leaves the unit inside `reach` of the footprint rectangle: a non-square footprint has a larger
## circumscribed radius than its short half extent.
static func approach_range(world: SimWorld, t: SimEntity, reach: int) -> int:
	if not is_structure_like(t):
		return reach
	half_extent(world, t, _half)
	var lo: int = mini(_half[0], _half[1])
	var hi: int = maxi(_half[0], _half[1])
	return maxi(reach - (hi - lo), 512)


## Shared APPROACH step of the three handlers. Returns 1 when the unit is close enough (movement stopped), 0 while it
## is still on its way, -1 when it cannot get there. `o.t0` = tick of the last move request, `o.p1` = retry counter.
static func approach_step(world: SimWorld, e: SimEntity, t: SimEntity, o: SimOrder, reach: int) -> int:
	if in_reach(world, e, t, reach):
		SimMovement.stop(world, e)
		return 1
	var requested: bool = o.t0 != 0  # movement state before our own request is stale
	if requested and SimMovement.path_failed(e):
		return -1
	var settled: bool = requested and SimMovement.at_goal(e)
	if settled and in_reach(world, e, t, reach + REACH_SLACK_U):
		SimMovement.stop(world, e)
		return 1
	if o.t0 == 0 or (settled and world.tick - o.t0 >= MOVE_RETRY_TICKS) or (not SimMovement.is_moving(e) and world.tick - o.t0 >= MOVE_RETRY_TICKS):
		o.p1 += 1
		if o.p1 > MOVE_MAX_RETRIES:
			return -1
		o.t0 = maxi(world.tick, 1)
		if not SimMovement.approach_entity(world, e, t.id, approach_range(world, t, reach)):
			return -1
	return 0


## EVT_ORDER_FAILED (economy 6.2) with the RSN; the dispatcher adds the kernel ORDER_FAILED with `o.fail`.
static func fail(world: SimWorld, e: SimEntity, o: SimOrder, rsn: int) -> int:
	o.fail = SimEconomySystem.err_of(rsn)
	world.emit(SimEconConst.EVT_ORDER_FAILED, e.x, e.y, e.owner, e.id, o.type, rsn)
	return SimOrder.FAILED


static func friendly(world: SimWorld, a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and world.team_of(a) == world.team_of(b)


# ------------------------------------------------------------------------------------------------------- repair
## The paid REPAIR ability of a unit (roster clone), null for units without it and for the free healing kinds.
static func repair_ability(world: SimWorld, u: SimEntity) -> DefAbility:
	var a: DefAbility = udef(world, u).ability_of(DefEnums.AbilityKind.REPAIR)
	if a == null or str(a.params.get("cost", "paid")) != "paid":
		return null
	return a


## RC_* of a repair ability from its target masks (economy 5.10): structures only -> PIONEER (defenses) or
## FIELD_ENGINEER; unmanned targets -> TENDER; ships -> TECHNICIAN; else ENGINEER.
static func repair_category(a: DefAbility) -> int:
	var um: int = int(a.params.get("target_unit_mask", 0))
	var sm: int = int(a.params.get("target_structure_mask", 0))
	if um == 0 and sm != 0:
		return SimEconConst.RC_PIONEER if (sm & DefEnums.ST_STRUCTURE) == 0 else SimEconConst.RC_FIELD_ENGINEER
	if (um & DefEnums.UT_UNMANNED) != 0:
		return SimEconConst.RC_TENDER
	if (um & DefEnums.UT_SHIP) != 0:
		return SimEconConst.RC_TECHNICIAN
	return SimEconConst.RC_ENGINEER


## Tag test of a repair ability's unit mask: `unmanned` is a required tag, the remaining tags are any-of.
static func unit_mask_fits(um: int, tags: int) -> bool:
	if um == 0:
		return false
	if (um & DefEnums.UT_UNMANNED) != 0 and (tags & DefEnums.UT_UNMANNED) == 0:
		return false
	var rest: int = um & ~DefEnums.UT_UNMANNED
	return rest == 0 or (tags & rest) != 0


static func structure_tags(world: SimWorld, t: SimEntity) -> int:
	if t.kind == SimEntity.Kind.STRUCTURE:
		return world.data.structures[t.def_idx].tags | DefEnums.ST_STRUCTURE
	return DefEnums.ST_STRUCTURE


## RSN_OK when `repairer` may repair `target` (economy 5.10 legal targets; hp is not checked: a full target ends the
## order with DONE).
static func repair_can_target(world: SimWorld, repairer: SimEntity, target: SimEntity) -> int:
	if repairer == null or target == null or (target.flags & SimFlags.F_GONE) != 0:
		return SimEconConst.RSN_BAD_TARGET
	var a: DefAbility = repair_ability(world, repairer)
	if a == null:
		return SimEconConst.RSN_WRONG_KIND
	if target.id == repairer.id and not bool(a.params.get("can_self", false)):
		return SimEconConst.RSN_BAD_TARGET
	if not friendly(world, repairer.owner, target.owner):
		return SimEconConst.RSN_BAD_TARGET
	if (target.flags & (SimFlags.F_NO_REPAIR | SimFlags.F_INSIDE)) != 0 or (target.econ != null and (target.econ.flags & SimEconConst.EF_NO_REPAIR) != 0):
		return SimEconConst.RSN_DECOY
	if target.hp_max <= 0:
		return SimEconConst.RSN_BAD_TARGET
	if is_structure_like(target):
		if target.econ == null or target.econ.st != SimEconConst.ST_ACTIVE:
			return SimEconConst.RSN_LOCKED
		if (structure_tags(world, target) & int(a.params.get("target_structure_mask", 0))) == 0:
			return SimEconConst.RSN_WRONG_KIND
		return SimEconConst.RSN_OK
	if target.kind != SimEntity.Kind.UNIT:
		return SimEconConst.RSN_BAD_TARGET
	if not unit_mask_fits(int(a.params.get("target_unit_mask", 0)), world.data.units[target.def_idx].tags):
		return SimEconConst.RSN_WRONG_KIND
	return SimEconConst.RSN_OK


## Credits basis of a repair: the paid price, or for free assets the def price (HQ: the MCV; neutral structures 600).
static func repair_basis_cost(world: SimWorld, t: SimEntity) -> int:
	if t.paid_cost > 0:
		return t.paid_cost
	var c: int = 0
	match t.kind:
		SimEntity.Kind.UNIT:
			c = world.data.units[t.def_idx].cost
		SimEntity.Kind.STRUCTURE:
			var sd: DefStructure = world.data.structures[t.def_idx]
			if world.economy.life.is_hq_def(t.def_idx):
				c = t.econ.mcv_paid_cost if t.econ != null else 0
				if c <= 0:
					c = world.data.units[sd.deploy_unit].cost if sd.deploy_unit >= 0 else HQ_BASIS
			else:
				c = sd.cost
		SimEntity.Kind.NEUTRAL:
			c = int(world.data.neutrals[t.def_idx].params.get("repair_basis_cost_cr", FALLBACK_BASIS))
	return c if c > 0 else FALLBACK_BASIS


static func _half_up(v: int, mul: int) -> int:
	return (v * mul + 5000) / 10000


## Repair sources that acted on `ec` during the last two ticks (0 when none): RS_UNIT | RS_WRENCH | RS_PAD.
static func repair_sources(ec: SimCompEcon, tick: int) -> int:
	if ec == null or ec.repair_src_mask == 0:
		return 0
	return (ec.repair_src_mask & 7) if (ec.repair_src_mask >> 3) >= tick - 1 else 0


static func _stamp_source(ec: SimCompEcon, tick: int, bit: int) -> void:
	var cur: int = ec.repair_src_mask
	var bits: int = (cur & 7) if (cur >> 3) == tick else 0
	ec.repair_src_mask = (tick << 3) | bits | bit


## THE paid repair primitive (economy 5.11). `repairer` null = wrench / pad. Returns the hit points restored this call;
## 0 when nothing was due; -1 when the step is paused because the payer lacks the credits (no hp, accumulators
## untouched). The payer is the repairer's owner (wrench / pad: the target's owner).
static func repair_step(world: SimWorld, repairer: SimEntity, target: SimEntity, rc: int, src_bit: int) -> int:
	if target.hp_max <= 0 or target.hp >= target.hp_max or (target.flags & SimFlags.F_GONE) != 0:
		return 0
	var tick: int = world.tick
	var eco: DefEconomy = world.data.economy
	var payer: int = repairer.owner if repairer != null else target.owner
	if payer < 0 or payer >= world.players.size() or target.owner < 0 or target.owner >= world.players.size():
		return 0
	var tv: DefPlayerView = world.players[target.owner].view
	var rate_bp: int = eco.repair_rate_bps
	if repairer != null:
		var a: DefAbility = repair_ability(world, repairer)
		if a != null:
			rate_bp = int(a.params.get("rate_bps", eco.repair_rate_bps))
	elif rc == SimEconConst.RC_PAD:
		rate_bp = PAD_RATE_BP
	var cost_bp: int = eco.repair_cost_bp
	var structure_target: bool = is_structure_like(target)
	if target.kind == SimEntity.Kind.STRUCTURE:
		var srate: int = tv.struct_repair_rate_bp[target.def_idx]
		rate_bp = _half_up(rate_bp, srate if srate > 0 else 10000)
		var scost: int = tv.struct_repair_cost_bp[target.def_idx]
		cost_bp = scost if scost > 0 else cost_bp
	elif target.kind == SimEntity.Kind.UNIT:
		var ucost: int = tv.unit_repair_cost_bp[target.def_idx]
		cost_bp = ucost if ucost > 0 else cost_bp
	var econ: SimEconomySystem = world.economy
	match rc:
		SimEconConst.RC_TECHNICIAN:
			rate_bp = _half_up(rate_bp, econ.knob(payer, SimEconConst.K_REPAIR_RATE_TECH_BP))
		SimEconConst.RC_TENDER:
			rate_bp = _half_up(rate_bp, econ.knob(payer, SimEconConst.K_REPAIR_RATE_TENDER_BP))
		SimEconConst.RC_ENGINEER, SimEconConst.RC_PIONEER, SimEconConst.RC_FIELD_ENGINEER:
			if structure_target and (structure_tags(world, target) & DefEnums.ST_DEFENSE) != 0:
				rate_bp = _half_up(rate_bp, econ.knob(payer, SimEconConst.K_REPAIR_RATE_DEF_BP))
	if rc == SimEconConst.RC_ENGINEER and target.kind == SimEntity.Kind.UNIT and (world.data.units[target.def_idx].tags & DefEnums.UT_LAND_VEHICLE) != 0:
		cost_bp = _half_up(cost_bp, econ.knob(payer, SimEconConst.K_REPAIR_COST_ENG_VEH_BP))
	var ec: SimCompEcon = ensure_econ(target)
	var acc: int = ec.repair_acc_hp + target.hp_max * rate_bp
	var h: int = mini(acc / HP_UNIT, target.hp_max - target.hp)
	var acc_rem: int = acc % HP_UNIT
	if h <= 0:
		ec.repair_acc_hp = acc_rem
		_stamp_source(ec, tick, src_bit)
		return 0
	var cacc: int = ec.repair_acc_cost + repair_basis_cost(world, target) * cost_bp * h
	var den: int = 10000 * target.hp_max
	var whole: int = cacc / den
	if whole > world.players[payer].credits:
		return -1
	if whole > 0 and not econ.spend(world, payer, whole, SimEconConst.CR_REPAIR):
		return -1
	ec.repair_acc_cost = cacc % den
	ec.repair_acc_hp = acc_rem
	world.combat.heal(world, target, h)
	_stamp_source(ec, tick, src_bit)
	return h


## true if the target's unit claim is held by somebody else who refreshed it recently.
static func claimed_by_other(world: SimWorld, ec: SimCompEcon, me: int) -> bool:
	var c: int = ec.unit_repairer_id
	return c != 0 and c != me and world.tick - ec.unit_repairer_tick <= CLAIM_STALE_TICKS and world.is_alive(c)


static func claim(world: SimWorld, ec: SimCompEcon, me: int) -> void:
	ec.unit_repairer_id = me
	ec.unit_repairer_tick = world.tick


static func release_claim(ec: SimCompEcon, me: int) -> void:
	if ec != null and ec.unit_repairer_id == me:
		ec.unit_repairer_id = 0
		ec.unit_repairer_tick = 0


# ------------------------------------------------------------------------------------------------------- capture
## true if the unit type may capture (bible tag `capture`: the CAPTURE ability).
static func can_capture(world: SimWorld, u: SimEntity) -> bool:
	return udef(world, u).has_ability(DefEnums.AbilityKind.CAPTURE)


## RSN_OK when `capturer` may start capturing `target` (economy 5.13 preconditions).
static func capture_can_target(world: SimWorld, capturer: SimEntity, target: SimEntity) -> int:
	if capturer == null or target == null or (target.flags & SimFlags.F_GONE) != 0:
		return SimEconConst.RSN_BAD_TARGET
	if not can_capture(world, capturer):
		return SimEconConst.RSN_WRONG_KIND
	if target.kind != SimEntity.Kind.NEUTRAL or target.econ == null:
		return SimEconConst.RSN_WRONG_KIND
	if not world.data.neutrals[target.def_idx].capturable:
		return SimEconConst.RSN_WRONG_KIND
	if (target.econ.flags & SimEconConst.EF_NO_CAPTURE) != 0:
		return SimEconConst.RSN_LOCKED
	if capturer.owner >= 0 and target.owner >= 0 and world.team_of(capturer.owner) == world.team_of(target.owner):
		return SimEconConst.RSN_FRIENDLY
	if hostile_garrison(world, capturer, target):
		return SimEconConst.RSN_GARRISONED
	return SimEconConst.RSN_OK


## An occupant of the structure that is not on the capturer's team (a scan; used at order time only).
static func hostile_garrison(world: SimWorld, capturer: SimEntity, target: SimEntity) -> bool:
	var team: int = world.team_of(capturer.owner)
	for u: SimEntity in world.units:
		if u.container_id == target.id and (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) == SimFlags.F_INSIDE and world.team_of(u.owner) != team:
			return true
	return false


## One tick of channelling by `capturer` on `target` (called by SimOrderCapture in stage 5, evaluated by the next stage 3).
static func capture_channel(capturer: SimEntity, target: SimEntity) -> void:
	if target.econ != null and capturer.owner >= 0 and capturer.owner < target.econ.cap_chan.size():
		target.econ.cap_chan[capturer.owner] += 1


## Stage 3: evaluates every capturable neutral that has channelers or stored progress.
static func update_captures(world: SimWorld) -> void:
	for e: SimEntity in world.neutrals:
		var ec: SimCompEcon = e.econ
		if ec == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var busy: bool = ec.cap_progress > 0
		if not busy:
			for c: int in ec.cap_chan:
				if c > 0:
					busy = true
					break
		if busy:
			_eval_capture(world, e, ec)


static func _eval_capture(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	var nd: DefNeutral = world.data.neutrals[e.def_idx]
	var need: int = nd.capture_t
	var tick: int = world.tick
	var owner_team: int = world.team_of(e.owner)
	var team: int = -2
	var contested: bool = false
	for pid: int in ec.cap_chan.size():
		if ec.cap_chan[pid] <= 0:
			continue
		var t: int = world.team_of(pid)
		if t == owner_team and owner_team >= 0:
			continue
		if team == -2:
			team = t
		elif team != t:
			contested = true
	if need <= 0 or not nd.capturable:
		ec.cap_chan.fill(0)
		return
	if team == -2:
		if ec.cap_progress > 0 and tick - ec.cap_last_tick >= CAPTURE_IDLE_TICKS:
			ec.cap_progress = maxi(0, ec.cap_progress - CAPTURE_DECAY)
			if ec.cap_progress == 0:
				ec.cap_pid = -1
	elif contested:
		if tick % CAPTURE_CONTEST_PERIOD == 0:
			world.emit(SimEconConst.EVT_CAPTURE_CONTESTED, e.x, e.y, e.id)
	else:
		var n: int = 0
		var lowest: int = -1
		var best_pid: int = -1
		var best_n: int = 0
		for pid2: int in ec.cap_chan.size():
			var c2: int = ec.cap_chan[pid2]
			if c2 <= 0 or world.team_of(pid2) != team:
				continue
			n += c2
			if lowest < 0:
				lowest = pid2
			if c2 > best_n:
				best_n = c2
				best_pid = pid2
		n = mini(n, CAPTURE_MAX_CHANNELERS)
		if ec.cap_pid != -1 and world.team_of(ec.cap_pid) != team:
			ec.cap_progress = maxi(0, ec.cap_progress - n)
			if ec.cap_progress == 0:
				ec.cap_pid = lowest
		else:
			if ec.cap_pid == -1:
				ec.cap_pid = lowest
			ec.cap_progress += n
			ec.cap_last_tick = tick
		if ec.cap_progress >= need:
			var old: int = e.owner
			ec.cap_progress = 0
			ec.cap_pid = -1
			ec.cap_chan.fill(0)
			if world.change_owner(e.id, best_pid, SimEvent.OWNER_CAPTURE):
				world.emit(SimEconConst.EVT_STRUCTURE_CAPTURED, e.x, e.y, best_pid, e.id, old)
			return
	if ec.cap_progress > 0 and tick % CAPTURE_PROGRESS_PERIOD == 0:
		world.emit(SimEconConst.EVT_CAPTURE_PROGRESS, e.x, e.y, ec.cap_pid, e.id, ec.cap_progress * 10000 / need)
	ec.cap_chan.fill(0)


# ------------------------------------------------------------------------------------------------------- salvage
## The SALVAGE ability of the unit's roster def, null for everybody but the African Empire salvagers.
static func salvage_ability(world: SimWorld, u: SimEntity) -> DefAbility:
	return udef(world, u).ability_of(DefEnums.AbilityKind.SALVAGE)


## Effective salvage duration in ticks: the ability's action time, MIN-combined with the knob (Winches, Recovery Priority).
static func salvage_duration(world: SimWorld, u: SimEntity, a: DefAbility) -> int:
	var base: int = int(a.params.get("action_t", world.data.economy.salvage_t))
	return mini(base, world.economy.knob(u.owner, SimEconConst.K_SALVAGE_TICKS))


## RSN_OK when `salvager` may salvage `wreck` now (player flag -> wreck flag -> team -> claim -> remaining life).
static func salvage_can_target(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> int:
	if salvager == null or wreck == null:
		return SimEconConst.RSN_BAD_TARGET
	var a: DefAbility = salvage_ability(world, salvager)
	if a == null:
		return SimEconConst.RSN_WRONG_KIND
	if wreck.kind != SimEntity.Kind.WRECK or (wreck.flags & (SimFlags.F_GONE | SimFlags.F_NO_SALVAGE)) != 0 or wreck.combat == null:
		return SimEconConst.RSN_BAD_TARGET
	var wc: SimCompCombat = wreck.combat
	if (wc.wreck_flags & SimCombatConsts.WF_SALVAGEABLE) == 0 or (wc.wreck_flags & SimCombatConsts.WF_CONSUMED) != 0:
		return SimEconConst.RSN_BAD_TARGET
	if world.team_of(salvager.owner) == world.team_of(wc.wreck_owner_pid):
		return SimEconConst.RSN_FRIENDLY
	if wreck.econ != null and claimed_by_other(world, wreck.econ, salvager.id):
		return SimEconConst.RSN_BUSY
	var mine: bool = wreck.econ != null and wreck.econ.unit_repairer_id == salvager.id
	if not mine and wc.wreck_expire - world.tick < salvage_duration(world, salvager, a):
		return SimEconConst.RSN_EXPIRING
	return SimEconConst.RSN_OK


## Takes the wreck's claim (progress 0) and announces it. false if somebody else holds it.
static func salvage_begin(world: SimWorld, salvager: SimEntity, wreck: SimEntity, duration: int) -> bool:
	var ec: SimCompEcon = ensure_econ(wreck)
	if claimed_by_other(world, ec, salvager.id):
		return false
	claim(world, ec, salvager.id)
	world.emit(SimEconConst.EVT_SALVAGE_STARTED, wreck.x, wreck.y, salvager.owner, salvager.id, wreck.id, world.tick + duration)
	return true


## One tick of salvaging: refreshes the claim and freezes the wreck's expiry. SALV_FAILED when the claim was lost.
static func salvage_tick(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> int:
	var ec: SimCompEcon = wreck.econ
	if ec == null or ec.unit_repairer_id != salvager.id:
		return SimEconConst.SALV_FAILED
	ec.unit_repairer_tick = world.tick
	if wreck.expire_tick != 0:
		wreck.expire_tick += 1
	if wreck.combat != null:
		wreck.combat.wreck_expire += 1
	return SimEconConst.SALV_RUNNING


## Pays the wreck out through the combat wreck API. Returns the credits paid, -1 if the wreck is no longer eligible.
static func salvage_finish(world: SimWorld, salvager: SimEntity, wreck: SimEntity, a: DefAbility) -> int:
	var pct: int = int(a.params.get("payout_bp", world.data.economy.salvage_payout_bp)) / 100
	var x: int = wreck.x
	var y: int = wreck.y
	var payout: int = world.combat.try_salvage(world, wreck.id, salvager.owner, pct)
	if payout < 0:
		return -1
	world.economy.earn(world, salvager.owner, payout, SimEconConst.CR_SALVAGE, x, y)
	world.emit(SimEconConst.EVT_SALVAGE_PAID, x, y, salvager.owner, payout, x, y)
	return payout


## Salvage credits as basis points of the player's total income (harvest + salvage + depot): the bible's
## African Empire snowball check (balance target: below 1500 bp in even fights).
static func salvage_share_bp(world: SimWorld, pid: int) -> int:
	var pe: SimPlayerEcon = world.players[pid].econ if pid >= 0 and pid < world.players.size() else null
	if pe == null:
		return 0
	var total: int = pe.stat_harvested + pe.stat_salvaged + pe.stat_depot
	return pe.stat_salvaged * 10000 / total if total > 0 else 0


# ------------------------------------------------------------------------------------------------ stage 3 pass
## Capture evaluation, the wrench loop and the airfield pad repair (once per tick, ascending ids).
static func update(world: SimWorld) -> void:
	update_captures(world)
	for e: SimEntity in world.structures:
		var ec: SimCompEcon = e.econ
		if ec != null and ec.repair_on and (e.flags & SimFlags.F_GONE) == 0:
			_wrench(world, e, ec)
	_pads(world)


static func _wrench(world: SimWorld, e: SimEntity, ec: SimCompEcon) -> void:
	if ec.st != SimEconConst.ST_ACTIVE:
		return
	if e.hp >= e.hp_max:
		ec.repair_on = false
		e.flags &= ~SimFlags.F_REPAIR_ON
		world.emit(SimEconConst.EVT_REPAIR_STATE, e.x, e.y, e.owner, e.id, 0)
		return
	var h: int = repair_step(world, null, e, SimEconConst.RC_WRENCH, SimEconConst.RS_WRENCH)
	if h < 0 and world.tick % REPAIR_FUNDS_PERIOD == 0:
		world.emit(SimEconConst.EVT_INSUFFICIENT_FUNDS, e.x, e.y, e.owner, e.id, 0)


## Aircraft parked on an online airfield's pad are repaired at 3 %/s (RC_PAD), paid by their owner.
static func _pads(world: SimWorld) -> void:
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null or p.eliminated != 0:
			continue
		for fid: int in pe.producer_ids[SimEconConst.PROD_AIRFIELD]:
			var af: SimEntity = world.get_entity(fid)
			if af == null or af.prod == null or (af.flags & SimFlags.F_GONE) != 0 or not world.economy.life.structure_online(world, af):
				continue
			for aid: int in af.prod.pad_ent:
				if aid == 0:
					continue
				var ac: SimEntity = world.get_entity(aid)
				if ac == null or ac.air == null or ac.hp >= ac.hp_max or (ac.flags & SimFlags.F_GONE) != 0:
					continue
				if ac.air.state == SimCombatConsts.AIR_PARKED or ac.air.state == SimCombatConsts.AIR_REARM:
					repair_step(world, null, ac, SimEconConst.RC_PAD, SimEconConst.RS_PAD)
