class_name SimAuraSystem
extends RefCounted
## Auras, command fields, Relay networked fire and free healing (abilities 5.7), plus the detector state updates.
## Owned by SimAbilitySystem (`world.abilities.aura`, updated in stage 7f).
##
## Model. Every aura-type ability (relay_field, command_field, aura_regen, heal, suppression_support, ew_jammer) belongs
## to one of six GROUPS; a group's providers never stack (the "fields do not stack" rule): a recipient is COVERED by a
## group when at least one active provider of the recipient's scope reaches its cell (integer cell disc of radius
## `(radius_u + 512) >> 10`, i.e. the same discs as vision), and its effect magnitude is the largest among the covering
## providers. A recipient's covered groups are the bits of `abil.aura_bits`; the authoritative coverage set of a group is
## `cov_ids[g]` (ascending recipient ids) with `cov_val[g]` (the magnitude, bp), both hashed.
##
## Cadence. Providers are re-evaluated EVERY tick (alive, not inside, functional, powered with the retain-after-power-
## loss grace, not suppressed, deployed where required): a change marks the group dirty and its coverage is recomputed
## in the same update ("destroyed Relay clears at once", "power shortage at tick 100 switches the field off at 100").
## Moving recipients and providers are caught by the periodic poll of every group with providers or covered members
## (even ticks). The poll is provider-centred (one spatial circle query per active provider), sorted and diffed against
## the previous set; only the diff touches combat leases.
##
## Effects: relay / command field -> lease DMG_OUT +bp (key FXK(SRC_GROUP, group)); suppression_support -> lease
## SUP_RECOVER +bp; ew_jammer -> local SIGHT -bp (SimStats through aura_extra_bp); aura_regen / heal -> membership of
## the free-healing pass (every 10 ticks, `abil.heal_frac` accumulator, 1/1000 hp).
## Deviation from the spec text: no SimCoverGrid instances - coverage is recomputed from the providers and diffed, which
## has no incremental state to drift; the result (recipient sets, magnitudes, timing) is the specified one.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const G_RELAY: int = 0
const G_CMD: int = 1
const G_APRON: int = 2
const G_HEAL: int = 3
const G_SUPREC: int = 4
const G_JAM: int = 5
const G_COUNT: int = 6
const G_ALL: int = 63
const POLL_MASK: int = 1  ## groups are polled on ticks where (tick & POLL_MASK) == 0
const HOSPITAL_ID: int = -100  ## slot ab_idx of the virtual heal slot of a neutral Field Hospital
const HOSPITAL_RADIUS_U: int = 5120
const HOSPITAL_RATE_BPS: int = 200
const HP_MILLI_DIV: int = 20  ## hp_max * rate_bps / 20 = milli-hp per 10-tick pass
const PC_VER: int = 0
const PC_OWNER: int = 1
const PC_RADIUS: int = 2
const PC_MAG: int = 3
const PC_TMASK: int = 4
const PC_SEL: int = 5
const PC_CMDB: int = 6
const PC_REQDEP: int = 7
const PC_POWREQ: int = 8
const PC_RETAIN: int = 9
const PC_RATE: int = 10
const PC_IDLE: int = 11
const PC_CAP: int = 12
const PC_N: int = 13
const KIND_OF_GROUP: PackedInt32Array = [29, 8, 32, 6, 10, 14]  ## AK_* of each group's provider slot

var prov_ids: PackedInt32Array = PackedInt32Array()  ## ascending entities with an aura provider slot (checked every tick)
var det_ids: PackedInt32Array = PackedInt32Array()  ## ascending entities with a detector slot and no provider slot (units every 4th tick)
var active: Array[PackedInt32Array] = []  ## per group: ascending ids of the ACTIVE providers (derived from the slots)
var cov_ids: Array[PackedInt32Array] = []  ## per group: covered recipients, ascending (hashed)
var cov_val: Array[PackedInt32Array] = []  ## per group: magnitude bp of each covered recipient (hashed)
var heal_members: PackedInt32Array = PackedInt32Array()  ## ascending ids in the free-healing pass (derived)
var dirty: int = 0  ## groups whose coverage must be recomputed this update
var win_bp: PackedInt32Array = PackedInt32Array()  ## per (pid, group): window magnitude override, 0 none (hashed)
var win_rad: PackedInt32Array = PackedInt32Array()  ## per (pid, group): extra radius in units (hashed)
var win_until: PackedInt32Array = PackedInt32Array()  ## per (pid, group): first tick the window no longer applies (hashed)
var stat_polls: int = 0
var stat_transitions: int = 0

var _buf: PackedInt32Array = PackedInt32Array()
var _keys: PackedInt64Array = PackedInt64Array()
var _sel_names: PackedStringArray = PackedStringArray()
var _sel_idx: PackedInt32Array = PackedInt32Array()
var _pc: Dictionary = {}  ## (entity id * 8 + slot) -> PackedInt32Array of the slot's parameters (PC_*), revalidated per research version
var _elists: Dictionary = {}  ## same key -> PackedInt32Array of the command field's eligible unit defs
var _pre: PackedInt32Array = PackedInt32Array()  ## per unit def: static group prefilter bits (built on first poll)
var _tags: PackedInt32Array = PackedInt32Array()  ## per unit def: tags (base data)
var _masks: Dictionary = {}  ## (pid * 4096 + selector) -> PackedByteArray of the recipient roster (lookups only)


func _init() -> void:
	for _g: int in G_COUNT:
		active.append(PackedInt32Array())
		cov_ids.append(PackedInt32Array())
		cov_val.append(PackedInt32Array())
	var n: int = (SimConfig.MAX_PLAYERS + 1) * G_COUNT
	win_bp.resize(n)
	win_rad.resize(n)
	win_until.resize(n)


# ---- registration ----------------------------------------------------------------------------------------------

## A provider / detector / regen slot was added to e (called by SimAbilitySystem._add_slot).
func on_slot_added(_world: SimWorld, e: SimEntity, kind: int) -> void:
	if group_of_kind(kind) >= 0:
		SimAbilitySystem._insert(prov_ids, e.id)
		SimAbilitySystem._erase(det_ids, e.id)
	elif kind == K.AK_DETECTOR and _find(prov_ids, e.id) < 0:
		SimAbilitySystem._insert(det_ids, e.id)
	if kind == K.AK_REGEN:
		SimAbilitySystem._insert(heal_members, e.id)
	if group_of_kind(kind) >= 0:
		dirty |= G_ALL


static func group_of_kind(kind: int) -> int:
	match kind:
		K.AK_RELAY_FIELD:
			return G_RELAY
		K.AK_COMMAND_FIELD:
			return G_CMD
		K.AK_AURA_REGEN:
			return G_APRON
		K.AK_HEAL:
			return G_HEAL
		K.AK_SUPPRESSION_SUPPORT:
			return G_SUPREC
		K.AK_EW_JAMMER:
			return G_JAM
	return -1


## The entity left the world: drops it from every registry.
func on_remove(_world: SimWorld, e: SimEntity) -> void:
	for sl: int in K.MAX_SLOTS:
		_pc.erase(e.id * 8 + sl)
		_elists.erase(e.id * 8 + sl)
	SimAbilitySystem._erase(prov_ids, e.id)
	SimAbilitySystem._erase(det_ids, e.id)
	for g: int in G_COUNT:
		if _find(active[g], e.id) >= 0:
			SimAbilitySystem._erase(active[g], e.id)
			dirty |= 1 << g
		_forget_in(g, e.id)
	SimAbilitySystem._erase(heal_members, e.id)


## Drops e from the coverage sets (releasing the group effects it held) and from the provider registries; its
## slots are re-registered by the caller (owner change, def change).
func forget(world: SimWorld, e: SimEntity) -> void:
	for g: int in G_COUNT:
		if _find(cov_ids[g], e.id) >= 0:
			_release(world, g, e.id)
			_forget_in(g, e.id)
		if _find(active[g], e.id) >= 0:
			SimAbilitySystem._erase(active[g], e.id)
	if e.abil != null:
		e.abil.aura_bits = 0
	SimAbilitySystem._erase(heal_members, e.id)
	if e.abil != null:
		for s: int in e.abil.n_slots:
			if e.abil.slots[s * K.SLOT_STRIDE + K.SL_KIND] == K.AK_REGEN:
				SimAbilitySystem._insert(heal_members, e.id)
				break
	dirty |= G_ALL


func _forget_in(g: int, id: int) -> void:
	var i: int = _find(cov_ids[g], id)
	if i >= 0:
		cov_ids[g].remove_at(i)
		cov_val[g].remove_at(i)


static func _find(arr: PackedInt32Array, id: int) -> int:
	var lo: int = 0
	var hi: int = arr.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if arr[mid] < id:
			lo = mid + 1
		else:
			hi = mid
	return lo if lo < arr.size() and arr[lo] == id else -1


func mark_all() -> void:
	dirty |= G_ALL


## A restamp trigger: something about a provider changed (deploy finished, research done ...).
func mark_provider(_eid: int) -> void:
	dirty |= G_ALL


## Window hook of the power / global-effect layer (Treaty Coordination, Central Priority, Reserve Bandwidth): for
## `pid` and `group`, magnitude `bp` (0 = unchanged) and `radius_add_u` apply until `until_tick`. Re-issues the leases.
func set_window(pid: int, group: int, bp: int, radius_add_u: int, until_tick: int) -> void:
	if pid < 0 or pid > SimConfig.MAX_PLAYERS or group < 0 or group >= G_COUNT:
		return
	var i: int = pid * G_COUNT + group
	win_bp[i] = bp
	win_rad[i] = radius_add_u
	win_until[i] = until_tick
	dirty |= 1 << group


func _window(pid: int, group: int, tick: int) -> int:
	if pid < 0 or pid > SimConfig.MAX_PLAYERS:
		return -1
	var i: int = pid * G_COUNT + group
	return i if win_until[i] > tick else -1


# ---- the update (stage 7f) -------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	var tick: int = world.tick
	# windows that ended change the magnitudes of their groups
	for i: int in win_until.size():
		if win_until[i] != 0 and win_until[i] <= tick:
			win_until[i] = 0
			win_bp[i] = 0
			win_rad[i] = 0
			dirty |= 1 << (i % G_COUNT)
	for id: int in prov_ids:
		var e: SimEntity = world.by_id[id]
		if e != null:
			_refresh_entity(world, e)
	for did: int in det_ids:  # detector-only entities: structures every tick (power flips), units every 4th tick
		var de: SimEntity = world.by_id[did]
		if de != null and (de.kind != SimEntity.Kind.UNIT or ((tick + did) & 3) == 0):
			_refresh_entity(world, de)
	var poll: bool = (tick & POLL_MASK) == 0
	for g: int in G_COUNT:
		if ((dirty >> g) & 1) != 0 or (poll and (not active[g].is_empty() or not cov_ids[g].is_empty())):
			_poll_group(world, g)
	dirty = 0
	if tick % K.HEAL_PERIOD == 0 and not heal_members.is_empty():
		_heal_pass(world)


# ---- providers -------------------------------------------------------------------------------------------------

func _refresh_entity(world: SimWorld, e: SimEntity) -> void:
	var ab: SimCompAbility = e.abil
	if ab == null:
		return
	for s: int in ab.n_slots:
		var kind: int = ab.slots[s * K.SLOT_STRIDE + K.SL_KIND]
		if kind == K.AK_DETECTOR:
			_refresh_detector(world, e, s)
			continue
		var g: int = group_of_kind(kind)
		if g < 0:
			continue
		var was: bool = _find(active[g], e.id) >= 0
		var now: bool = _provider_active(world, e, s, kind)
		if now != was:
			if not (kind == K.AK_COMMAND_FIELD and ab.slots[s * K.SLOT_STRIDE + K.SL_N] > 0):  # an embedded deploy owns SL_STATE
				ab.slots[s * K.SLOT_STRIDE + K.SL_STATE] = 1 if now else 0
			if now:
				SimAbilitySystem._insert(active[g], e.id)
			else:
				SimAbilitySystem._erase(active[g], e.id)
			dirty |= 1 << g


## Alive, outside containers, functional, powered (with the grace timer), unsuppressed, deployed where required.
func _provider_active(world: SimWorld, e: SimEntity, s: int, kind: int) -> bool:
	if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or e.owner < 0:
		return false
	if (e.flags & (SimFlags.F_UNDER_CONSTRUCTION | SimFlags.F_SELLING)) != 0:
		return false
	var ab: SimCompAbility = e.abil
	var b: int = s * K.SLOT_STRIDE
	if world.combat != null and not world.combat.is_functional(world, e):
		return false
	if e.kind == SimEntity.Kind.UNIT and (kind == K.AK_COMMAND_FIELD or kind == K.AK_SUPPRESSION_SUPPORT):
		if world.combat != null and world.combat.is_suppressed(e):
			return false
	# deployed requirement: relay_field.requires_deployed, command_field with deploy_t > 0 (its own slot)
	if kind == K.AK_COMMAND_FIELD and ab.slots[b + K.SL_N] > 0:
		if ab.slots[b + K.SL_STATE] != SimMode.MODE_DEPLOYED or ab.slots[b + K.SL_AUX0] >= 0:
			return false
	elif kind == K.AK_RELAY_FIELD:
		var pc: PackedInt32Array = _params(world, e, s)
		if pc[PC_REQDEP] != 0 and not SimMode.is_deployed(world, e):
			return false
	# power with the retain-after-power-loss grace
	var needs_power: bool = kind == K.AK_RELAY_FIELD and _params(world, e, s)[PC_POWREQ] != 0
	if needs_power and e.kind == SimEntity.Kind.STRUCTURE and not _powered(world, e):
		var was: bool = _find(active[G_RELAY], e.id) >= 0
		var retain: int = _params(world, e, s)[PC_RETAIN]
		if not was or retain <= 0:
			ab.slots[b + K.SL_T_END] = 0
			return false
		if ab.slots[b + K.SL_T_END] == 0:
			ab.slots[b + K.SL_T_END] = world.tick + retain
		if world.tick >= ab.slots[b + K.SL_T_END]:
			ab.slots[b + K.SL_T_END] = 0
			return false
		return true
	ab.slots[b + K.SL_T_END] = 0
	return true


static func _powered(world: SimWorld, e: SimEntity) -> bool:
	if world.power == null or e.econ == null:
		return true
	return (e.flags & SimFlags.F_POWERED) != 0


## Detector state mirror: OFF while EMP-shut or (powered defence) unpowered; every flip restamps the detection disc.
func _refresh_detector(world: SimWorld, e: SimEntity, s: int) -> void:
	if (e.flags & SimFlags.F_GONE) != 0:
		return
	var ab: SimCompAbility = e.abil
	var b: int = s * K.SLOT_STRIDE
	var on: bool = true
	var cc: SimCompCombat = e.combat
	if cc != null and cc.emp_until > world.tick and not SimCombatMods.has_flag(cc, C.STAT_FLAG_EMP_IMMUNE, world.tick):
		on = false
	elif e.kind == SimEntity.Kind.STRUCTURE and world.power != null and e.econ != null and (e.flags & SimFlags.F_POWERED) == 0 \
			and (world.data.structures[e.def_idx].flags & DefEnums.SF_POWERED_DEFENSE) != 0:
		on = false
	var now: int = K.DET_ON if on else K.DET_OFF
	if ab.slots[b + K.SL_STATE] != now:
		ab.slots[b + K.SL_STATE] = now
		if world.vision != null:
			world.vision.request_restamp(e.id)


## Slot parameter of a provider slot; a neutral Field Hospital answers from its constants.
func _pp(world: SimWorld, e: SimEntity, s: int, key: String, default: int) -> int:
	if e.abil.slots[s * K.SLOT_STRIDE + K.SL_AB_IDX] == HOSPITAL_ID:
		match key:
			"radius_u":
				return HOSPITAL_RADIUS_U
			"rate_bps":
				return HOSPITAL_RATE_BPS
			"target_unit_mask":
				return DefEnums.UT_INFANTRY
		return default
	return world.abilities.sp(world, e, s, key, default)


## Cached parameters of a provider slot (PC_* fields), refilled when the owner's research version changes.
func _params(world: SimWorld, e: SimEntity, s: int) -> PackedInt32Array:
	var key: int = e.id * 8 + s
	var ver: int = 0
	if e.owner >= 0 and e.owner < world.players.size():
		ver = world.players[e.owner].view.layer3.version
	var pc: Variant = _pc.get(key)
	if pc != null and (pc as PackedInt32Array)[PC_VER] == ver and (pc as PackedInt32Array)[PC_OWNER] == e.owner:
		return pc as PackedInt32Array
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(PC_N)
	out[PC_VER] = ver
	out[PC_OWNER] = e.owner
	var kind: int = e.abil.slots[s * K.SLOT_STRIDE + K.SL_KIND]
	var g: int = group_of_kind(kind)
	out[PC_RADIUS] = _pp(world, e, s, "radius_u", 5120)
	match g:
		G_RELAY:
			out[PC_MAG] = _pp(world, e, s, "damage_bonus_bp", 0)
			out[PC_REQDEP] = _pp(world, e, s, "requires_deployed", 0)
			out[PC_POWREQ] = _pp(world, e, s, "powered_required", 1)
			out[PC_RETAIN] = _pp(world, e, s, "retain_after_power_loss_t", 0)
		G_CMD:
			out[PC_MAG] = _pp(world, e, s, "damage_bonus_bp", 0)
			var bonus: int = 0
			for j: int in e.abil.n_slots:
				if e.abil.slots[j * K.SLOT_STRIDE + K.SL_KIND] == K.AK_DEPLOY:
					bonus += world.abilities.sp(world, e, j, "command_radius_bonus_u", 0)
			out[PC_CMDB] = bonus
			var el: PackedInt32Array = PackedInt32Array()
			var da: DefAbility = world.abilities.slot_def(world, e, s)
			if da != null:
				var lst: Variant = da.params.get("eligible_unit_idx", [])
				if lst is Array or lst is PackedInt32Array:
					for x: Variant in lst:
						el.append(int(x))
			_elists[key] = el
		G_SUPREC:
			out[PC_MAG] = _pp(world, e, s, "recovery_bonus_bp", 0)
		G_JAM:
			out[PC_MAG] = _pp(world, e, s, "sight_penalty_bp", 0)
		G_HEAL:
			out[PC_MAG] = 1
			out[PC_TMASK] = _pp(world, e, s, "target_unit_mask", DefEnums.UT_INFANTRY)
			out[PC_RATE] = _pp(world, e, s, "rate_bps", 0)
			out[PC_IDLE] = _pp(world, e, s, "needs_out_of_combat_t", 0)
			out[PC_CAP] = 10000
		G_APRON:
			out[PC_MAG] = 1
			var da2: DefAbility = world.abilities.slot_def(world, e, s)
			var name: String = str(da2.params.get("target_selector", "")) if da2 != null else ""
			out[PC_SEL] = _selector_index(world, name) if not name.is_empty() else -1
			out[PC_RATE] = _pp(world, e, s, "rate_bps", 0)
			out[PC_IDLE] = _pp(world, e, s, "idle_t", 0)
			out[PC_CAP] = _pp(world, e, s, "cap_bp", 10000)
	_pc[key] = out
	return out


## Radius of the provider in units after research, deployed bonus and windows.
func _radius_u(world: SimWorld, e: SimEntity, s: int, g: int) -> int:
	var pc: PackedInt32Array = _params(world, e, s)
	var r: int = pc[PC_RADIUS]
	if g == G_CMD and pc[PC_CMDB] != 0 and SimMode.is_deployed(world, e):
		r += pc[PC_CMDB]
	var w: int = _window(e.owner, g, world.tick)
	if w >= 0:
		r += win_rad[w]
	return r


func _magnitude(world: SimWorld, e: SimEntity, s: int, g: int) -> int:
	var v: int = _params(world, e, s)[PC_MAG]
	var w: int = _window(e.owner, g, world.tick)
	if w >= 0 and win_bp[w] > v and (g == G_RELAY or g == G_CMD):
		v = win_bp[w]
	return v


# ---- coverage --------------------------------------------------------------------------------------------------

func _poll_group(world: SimWorld, g: int) -> void:
	stat_polls += 1
	if _pre.is_empty():
		_build_prefilter(world)
	_keys.resize(0)
	var kind: int = KIND_OF_GROUP[g]
	var jam: bool = g == G_JAM
	for pid: int in active[g]:
		var p: SimEntity = world.by_id[pid]
		if p == null or p.abil == null:
			continue
		var s: int = p.abil.slot_of_kind(kind)
		if s < 0:
			continue
		var rc: int = (_radius_u(world, p, s, g) + 512) >> 10
		var mag: int = _magnitude(world, p, s, g)
		var pcx: int = p.x >> 10
		var pcy: int = p.y >> 10
		var team: int = p.team
		var pc: PackedInt32Array = _params(world, p, s)
		var tmask: int = pc[PC_TMASK]
		var sel: int = pc[PC_SEL]
		var elist: PackedInt32Array = _elists.get(p.id * 8 + s, PackedInt32Array()) if g == G_CMD else PackedInt32Array()
		_buf.resize(0)
		world.query_circle(p.x, p.y, (rc + 1) * SimConfig.CELL, _buf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
		var r2: int = rc * rc
		for id: int in _buf:
			var rec: SimEntity = world.by_id[id]
			var dx: int = (rec.x >> 10) - pcx
			var dy: int = (rec.y >> 10) - pcy
			if dx * dx + dy * dy > r2 or rec.owner < 0 or ((_pre[rec.def_idx] >> g) & 1) == 0:
				continue
			if (rec.team != team) != jam:  # friendly scopes need the same team, the jammer the other one
				continue
			match g:
				G_CMD:
					if rec.stats != null and (rec.stats.flags & K.DF_NO_CMD_FIELD) != 0:
						continue
					var tg: int = _tags[rec.def_idx]
					if not ((tg & DefEnums.UT_UNMANNED) != 0 and (tg & DefEnums.UT_COMBAT) != 0):
						if not (elist.has(rec.def_idx) or world.players[rec.owner].view.layer3.has_flag(rec.def_idx, "command_field_eligible")):
							continue
				G_APRON:
					if sel < 0:
						if (_tags[rec.def_idx] & (DefEnums.UT_COMBAT | DefEnums.UT_LAND_VEHICLE)) != (DefEnums.UT_COMBAT | DefEnums.UT_LAND_VEHICLE):
							continue
					else:
						var mk: PackedByteArray = _sel_mask(world, rec.owner, sel)
						if rec.def_idx >= mk.size() or mk[rec.def_idx] == 0:
							continue
				G_HEAL:
					if rec == p or (_tags[rec.def_idx] & tmask) == 0:
						continue
			_keys.append((id << 20) | (mag & 0xFFFFF))
	_keys.sort()
	# reduce to (id, max magnitude)
	var ids: PackedInt32Array = PackedInt32Array()
	var vals: PackedInt32Array = PackedInt32Array()
	var n: int = _keys.size()
	var i: int = 0
	while i < n:
		var id2: int = _keys[i] >> 20
		var v: int = _keys[i] & 0xFFFFF
		while i + 1 < n and (_keys[i + 1] >> 20) == id2:
			i += 1
			v = _keys[i] & 0xFFFFF
		ids.append(id2)
		vals.append(v)
		i += 1
	_apply_diff(world, g, ids, vals)


## Static per-def data of the poll: tags and the groups a unit def can ever receive.
func _build_prefilter(world: SimWorld) -> void:
	var n: int = world.data.units.size()
	_pre.resize(n)
	_tags.resize(n)
	for i: int in n:
		var u: DefUnit = world.data.units[i]
		var tg: int = u.tags
		var m: int = 0
		if (tg & DefEnums.UT_COMBAT) != 0 and (tg & (DefEnums.UT_INFANTRY | DefEnums.UT_LAND_VEHICLE)) != 0:
			m |= 1 << G_RELAY
		if (tg & DefEnums.UT_COMBAT) != 0:
			m |= 1 << G_CMD
		m |= (1 << G_APRON) | (1 << G_HEAL)
		if (tg & DefEnums.UT_INFANTRY) != 0:
			m |= 1 << G_SUPREC
		if u.sight > 0:
			m |= 1 << G_JAM
		_pre[i] = m
		_tags[i] = tg


func _sel_mask(world: SimWorld, pid: int, sel: int) -> PackedByteArray:
	var key: int = pid * 4096 + sel
	if not _masks.has(key):
		_masks[key] = world.players[pid].roster.selector_mask_units(sel)
	return _masks[key]


func _selector_index(world: SimWorld, name: String) -> int:
	var i: int = _sel_names.find(name)
	if i >= 0:
		return _sel_idx[i]
	var idx: int = world.data.selector_idx(name)
	_sel_names.append(name)
	_sel_idx.append(idx)
	return idx


func _apply_diff(world: SimWorld, g: int, ids: PackedInt32Array, vals: PackedInt32Array) -> void:
	var old_ids: PackedInt32Array = cov_ids[g]
	var old_val: PackedInt32Array = cov_val[g]
	var i: int = 0
	var j: int = 0
	var n_old: int = old_ids.size()
	var n_new: int = ids.size()
	while i < n_old or j < n_new:
		if j >= n_new or (i < n_old and old_ids[i] < ids[j]):
			_release(world, g, old_ids[i])
			i += 1
		elif i >= n_old or ids[j] < old_ids[i]:
			_acquire(world, g, ids[j], vals[j], false)
			j += 1
		else:
			if old_val[i] != vals[j]:
				_acquire(world, g, ids[j], vals[j], true)
			i += 1
			j += 1
	cov_ids[g] = ids
	cov_val[g] = vals


func _acquire(world: SimWorld, g: int, id: int, val: int, reissue: bool) -> void:
	var e: SimEntity = world.by_id[id]
	if e == null:
		return
	stat_transitions += 1
	var ab: SimCompAbility = SimStatus.ensure_abil(world, e)
	ab.aura_bits |= 1 << g
	var key: int = K.fxk(K.SRC_GROUP, g)
	match g:
		G_RELAY, G_CMD:
			if reissue:
				SimCombatMods.clear_key(e, key)
			SimCombatMods.apply(world, e, key, C.STAT_DMG_OUT, val, 0, K.LEASE_HOLD)
			if g == G_RELAY:
				SimCond.set_code(world, e, DefEnums.Cond.IN_RELAY_FIELD, true)
		G_SUPREC:
			if reissue:
				SimCombatMods.clear_key(e, key)
			SimCombatMods.apply(world, e, key, C.STAT_SUP_RECOVER, val, 0, K.LEASE_HOLD)
		G_JAM:
			SimStats.mark_dirty(world, e, 1 << K.K_SIGHT)
		G_APRON, G_HEAL:
			SimAbilitySystem._insert(heal_members, id)


func _release(world: SimWorld, g: int, id: int) -> void:
	var e: SimEntity = world.by_id[id]
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return
	stat_transitions += 1
	var ab: SimCompAbility = e.abil
	if ab != null:
		ab.aura_bits &= ~(1 << g)
	var key: int = K.fxk(K.SRC_GROUP, g)
	match g:
		G_RELAY, G_CMD, G_SUPREC:
			SimCombatMods.clear_key(e, key)
			if g == G_RELAY:
				SimCond.set_code(world, e, DefEnums.Cond.IN_RELAY_FIELD, false)
		G_JAM:
			SimStats.mark_dirty(world, e, 1 << K.K_SIGHT)
		G_APRON, G_HEAL:
			var other: int = G_HEAL if g == G_APRON else G_APRON
			if ab == null or (((ab.aura_bits >> other) & 1) == 0 and ab.slot_of_kind(K.AK_REGEN) < 0):
				SimAbilitySystem._erase(heal_members, id)


## Local SIGHT / SPEED / HEALTH extra bp of the aura groups that cover e (SimStats folds it): ew_jammer -bp on sight.
func extra_bp(e: SimEntity, k: int) -> int:
	var ab: SimCompAbility = e.abil
	if ab == null or k != K.K_SIGHT or ((ab.aura_bits >> G_JAM) & 1) == 0:
		return 0
	var i: int = _find(cov_ids[G_JAM], e.id)
	return -cov_val[G_JAM][i] if i >= 0 else 0


func is_covered(e: SimEntity, g: int) -> bool:
	return e.abil != null and ((e.abil.aura_bits >> g) & 1) != 0


# ---- free healing ----------------------------------------------------------------------------------------------

func _heal_pass(world: SimWorld) -> void:
	var members: PackedInt32Array = heal_members.duplicate()
	for id: int in members:
		var e: SimEntity = world.by_id[id]
		if e == null or (e.flags & SimFlags.F_GONE) != 0:
			continue
		var ab: SimCompAbility = e.abil
		if ab == null:
			continue
		# group heals on the entity itself
		if (e.flags & SimFlags.F_INSIDE) == 0 and e.hp < e.hp_max and e.hp_max > 0:
			var rate: int = 0
			var cap_hp: int = 0
			for g: int in [G_APRON, G_HEAL]:
				if ((ab.aura_bits >> g) & 1) != 0:
					var r: int = _group_rate(world, e, g)
					if r > 0:
						rate += r >> 32
						cap_hp = maxi(cap_hp, r & 0xFFFFFFFF)
			if rate > 0:
				_pour(world, e, rate, cap_hp)
		# regen abilities (self or passengers)
		for s: int in ab.n_slots:
			if ab.slots[s * K.SLOT_STRIDE + K.SL_KIND] == K.AK_REGEN:
				_regen(world, e, s)


## Highest applicable rate of the group at e packed as (rate_bps << 32) | hp_cap; 0 when no provider applies (idle /
## cap conditions fail).
func _group_rate(world: SimWorld, e: SimEntity, g: int) -> int:
	var best: int = 0
	var best_cap: int = 0
	var kind: int = KIND_OF_GROUP[g]
	var ecx: int = e.x >> 10
	var ecy: int = e.y >> 10
	for pid: int in active[g]:
		var p: SimEntity = world.by_id[pid]
		if p == null or p.abil == null or p.team != e.team or (g == G_HEAL and p == e):
			continue
		var s: int = p.abil.slot_of_kind(kind)
		if s < 0:
			continue
		var rc: int = (_radius_u(world, p, s, g) + 512) >> 10
		var dx: int = ecx - (p.x >> 10)
		var dy: int = ecy - (p.y >> 10)
		if dx * dx + dy * dy > rc * rc:
			continue
		var pc: PackedInt32Array = _params(world, p, s)
		var rate: int = pc[PC_RATE]
		var idle: int = pc[PC_IDLE]
		if idle > 0 and (world.combat == null or world.combat.ticks_since_combat(world, e) < idle):
			continue
		var cap_bp: int = pc[PC_CAP]
		var cap_hp: int = e.hp_max * cap_bp / 10000
		if e.hp >= cap_hp or rate <= best:
			continue
		best = rate
		best_cap = cap_hp
	return (best << 32) | best_cap if best > 0 else 0


## Adds hp_max * rate / 20 milli-hp to e's accumulator and heals the whole hit points, never above `cap_hp`.
func _pour(world: SimWorld, e: SimEntity, rate_bps: int, cap_hp: int) -> void:
	var ab: SimCompAbility = e.abil
	ab.heal_frac += e.hp_max * rate_bps / HP_MILLI_DIV
	var whole: int = ab.heal_frac / 1000
	if whole <= 0:
		return
	ab.heal_frac -= whole * 1000
	var room: int = maxi(mini(cap_hp, e.hp_max) - e.hp, 0)
	whole = mini(whole, room)
	if whole > 0 and world.combat != null:
		var got: int = world.combat.heal(world, e, whole)
		if got > 0 and world.tick % 20 == 0:  # throttled: one event per target per 20 ticks
			world.emit(K.EV_REPAIR_PULSE, e.x, e.y, e.id, -1, got)


func _regen(world: SimWorld, e: SimEntity, s: int) -> void:
	var a: SimAbilitySystem = world.abilities
	var rate: int = a.sp(world, e, s, "rate_bps", 0)
	var idle: int = a.sp(world, e, s, "idle_t", 0)
	var cap_bp: int = a.sp(world, e, s, "cap_bp", 10000)
	var da: DefAbility = a.slot_def(world, e, s)
	var target: String = str(da.params.get("target", "self")) if da != null else "self"
	if rate <= 0:
		return
	if target == "passengers":
		var c: SimCompCargo = e.cargo
		if c == null:
			return
		for i: int in c.n_pax:
			var p: SimEntity = world.by_id[c.pax[i]]
			if p == null:
				continue
			_regen_one(world, p, rate, idle, cap_bp)
		return
	if (e.flags & SimFlags.F_INSIDE) != 0 or e.hp >= e.hp_max:
		return
	if not _source_ok(world, e, s, da):
		return
	_regen_one(world, e, rate, idle, cap_bp)


func _regen_one(world: SimWorld, e: SimEntity, rate: int, idle: int, cap_bp: int) -> void:
	if e.hp_max <= 0 or e.hp >= e.hp_max * cap_bp / 10000:
		return
	if idle > 0 and (world.combat == null or world.combat.ticks_since_combat(world, e) < idle):
		return
	SimStatus.ensure_abil(world, e)
	_pour(world, e, rate, e.hp_max * cap_bp / 10000)


## Section Logistics: the regenerating unit must stand within source_radius of an own (powered) source structure.
func _source_ok(world: SimWorld, e: SimEntity, s: int, da: DefAbility) -> bool:
	if da == null:
		return true
	var lst: Variant = da.params.get("source_structure_idx", [])
	if not (lst is Array or lst is PackedInt32Array) or (lst as Variant).size() == 0:
		return true
	var radius: int = world.abilities.sp(world, e, s, "source_radius_u", 0)
	var powered: bool = world.abilities.sp(world, e, s, "source_powered", 0) != 0
	_buf.resize(0)
	world.query_circle(e.x, e.y, radius, _buf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.STRUCTURE))
	for id: int in _buf:
		var st: SimEntity = world.by_id[id]
		if st.team != e.team or (st.flags & (SimFlags.F_UNDER_CONSTRUCTION | SimFlags.F_SELLING)) != 0:
			continue
		var hit: bool = false
		for x: Variant in lst:
			if int(x) == st.def_idx:
				hit = true
				break
		if not hit:
			continue
		if powered and not _powered(world, st):
			continue
		return true
	return false


# ---- research conditions (near friendly unit / structure, target near) ------------------------------------------

## Condition 10 / 11 of a bound effect: a friendly unit / structure of the listed defs within radius_u of e.
func near_friendly(world: SimWorld, e: SimEntity, code: int, params: Dictionary) -> bool:
	var radius: int = int(params.get("radius_u", 0))
	if radius <= 0 or e.owner < 0:
		return false
	_buf.resize(0)
	var kind: int = SimEntity.Kind.UNIT if code == DefEnums.Cond.NEAR_FRIENDLY_UNIT else SimEntity.Kind.STRUCTURE
	world.query_circle(e.x, e.y, radius, _buf, SimTag.ALIVE | SimTag.kind_bit(kind))
	var list: Variant = params.get("unit_idx" if kind == SimEntity.Kind.UNIT else "structure_idx", [])
	var sel: int = int(params.get("selector_idx", -1))
	var mask: PackedByteArray = PackedByteArray()
	if sel >= 0 and e.owner < world.players.size():
		mask = world.players[e.owner].roster.selector_mask_structures(sel) if kind == SimEntity.Kind.STRUCTURE else world.players[e.owner].roster.selector_mask_units(sel)
	for id: int in _buf:
		var o: SimEntity = world.by_id[id]
		if o == e or o.team != e.team or (o.flags & (SimFlags.F_UNDER_CONSTRUCTION | SimFlags.F_SELLING)) != 0:
			continue
		if _def_listed(o.def_idx, list, mask):
			return true
	return false


static func _def_listed(def_idx: int, list: Variant, mask: PackedByteArray) -> bool:
	if list is Array or list is PackedInt32Array:
		for x: Variant in list:
			if int(x) == def_idx:
				return true
	return def_idx < mask.size() and mask[def_idx] != 0


## Condition 12: the attacker's current target lies within radius_u of a friendly unit of the listed defs.
func target_near(world: SimWorld, e: SimEntity, params: Dictionary) -> bool:
	var cc: SimCompCombat = e.combat
	if cc == null or cc.target_id < 0:
		return false
	var t: SimEntity = world.get_entity(cc.target_id)
	if t == null or (t.flags & SimFlags.F_GONE) != 0:
		return false
	var radius: int = int(params.get("radius_u", 0))
	_buf.resize(0)
	world.query_circle(t.x, t.y, radius, _buf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
	var list: Variant = params.get("unit_idx", [])
	var by_slot: bool = (list is Array or list is PackedInt32Array) and (list as Variant).size() == 0
	for id: int in _buf:
		var o: SimEntity = world.by_id[id]
		if o == e or o.team != e.team:
			continue
		if _def_listed(o.def_idx, list, PackedByteArray()):
			return true
		if by_slot and o.abil != null and o.abil.slot_of_kind(K.AK_SPOTTER) >= 0:  # no unit named: any spotter unit serves
			return true
	return false


# ---- hashing / validation --------------------------------------------------------------------------------------

func hash_into(buf: PackedInt32Array) -> void:
	for g: int in G_COUNT:
		buf.append(cov_ids[g].size())
		buf.append_array(cov_ids[g])
		buf.append_array(cov_val[g])
	buf.append_array(win_bp)
	buf.append_array(win_rad)
	buf.append_array(win_until)


func debug_validate(world: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for g: int in G_COUNT:
		var prev: int = 0
		for i: int in cov_ids[g].size():
			var id: int = cov_ids[g][i]
			if id <= prev:
				out.append("aura g%d: cov_ids not ascending at %d" % [g, id])
			prev = id
			var e: SimEntity = world.by_id[id] if id < world.by_id.size() else null
			if e != null and (e.abil == null or ((e.abil.aura_bits >> g) & 1) == 0):
				out.append("aura g%d: e%d covered without its aura bit" % [g, id])
		for pid: int in active[g]:
			var p: SimEntity = world.by_id[pid] if pid < world.by_id.size() else null
			if p == null:
				out.append("aura g%d: active provider %d does not exist" % [g, pid])
	return out
