class_name AiWorldView
extends RefCounted
## THE only reader of SimWorld in the AI (ai.md 3.3). Every accessor is a PURE read as of the tick of the think; the AI
## never writes the world (lint: test_ai_purity_lint). Fog policy (T2): static terrain, start positions, deposit sites and
## opponents' rosters are public; enemy entities obey fog unless `omniscient` (Brutal only, camouflage/detection is still
## honoured); `cell_visible`, `targetable_now` and `power_target_ok` always use REAL vision because the sim validates
## commands against real vision. Enemy hidden data (queues, credits, power state) is never readable.
## Subclassable: tests/ai/ai_mock_world_view.gd overrides the accessors with scripted data.

var omniscient: bool = false

var _w: SimWorld = null
var _me: int = 0
var _tick: int = 0
var _dt: int = 1
var _enemy_cache: PackedInt32Array = PackedInt32Array()
var _enemy_cache_tick: int = -1
var _pres: SimPlacementResult = SimPlacementResult.new()


func _init(p_me: int = 0, p_omniscient: bool = false) -> void:
	_me = p_me
	omniscient = p_omniscient


## Binds the world for this think (no per-entity work). `world` is a SimWorld (typed RefCounted at the net seam).
func begin_think(world: RefCounted, dt: int) -> void:
	_w = world as SimWorld
	_dt = dt
	if _w != null:
		_tick = _w.tick


func bound() -> bool:
	return _w != null


func tick() -> int:
	return _tick


func think_dt() -> int:
	return _dt


func me() -> int:
	return _me


func match_running() -> bool:
	return _w != null and _w.match_state == SimWorld.MATCH_RUNNING


## The GameData of the bound world.
func game_data() -> GameData:
	return _w.data


# ---------------------------------------------------------------------------------------------- players / rules
## Player slots in the world (vacant pids included); iterate 0..player_slots()-1 with player_alive().
func player_slots() -> int:
	return _w.players.size()


func player_count() -> int:
	var n: int = 0
	for p: SimPlayer in _w.players:
		if p.controller != SimPlayer.Controller.NONE:
			n += 1
	return n


func player_alive(p: int) -> bool:
	if p < 0 or p >= _w.players.size():
		return false
	var pl: SimPlayer = _w.players[p]
	return pl.controller != SimPlayer.Controller.NONE and pl.eliminated == 0


func team_of(p: int) -> int:
	return _w.team_of(p)


func is_enemy(p: int) -> bool:
	return p != _me and player_alive(p) and _w.rel(_me, p) == SimWorld.Rel.ENEMY


func is_ally(p: int) -> bool:
	return p != _me and _w.rel(_me, p) == SimWorld.Rel.ALLY


func roster_of(p: int) -> int:
	return _w.players[p].roster_idx


func roster_id_of(p: int) -> String:
	return _w.players[p].roster.id


func credits() -> int:
	return _w.players[_me].credits


func income_total() -> int:
	return _w.economy.income_total(_me)


func income_per_minute() -> int:
	return _w.economy.q_income_per_minute(_me)


func power_supply() -> int:
	return _w.economy.power_supply(_me)


func power_demand() -> int:
	return _w.economy.power_demand(_me)


func power_shortage() -> bool:
	return _w.power.is_shortage(_me)


func unit_cap() -> int:
	return _w.rules.unit_cap


func unit_count() -> int:
	return _w.players[_me].unit_count


func unit_cap_room() -> int:
	return _w.economy.unit_cap_room(_me)


func handicap() -> int:
	return _w.players[_me].handicap


func rule_flag(flag: int) -> bool:
	match flag:
		AiTypes.RF_FOG:
			return _w.rules.fog != 0
		AiTypes.RF_SUPERWEAPONS:
			return _w.rules.superweapons != 0
		AiTypes.RF_SHARED_VISION:
			return _w.rules.shared_vision != 0
	return false


# ------------------------------------------------------------------------------------------------- definitions
## DefRoster of a player (modifiers folded in); research effects are in cost()/ticks() below.
func roster(of_player: int = -1) -> DefRoster:
	return _w.players[_me if of_player < 0 else of_player].roster


func unit_def(def_idx: int, of_player: int = -1) -> DefUnit:
	return roster(of_player).unit(def_idx)


func structure_def(def_idx: int, of_player: int = -1) -> DefStructure:
	return roster(of_player).structure(def_idx)


func power_def(power_idx: int) -> DefPower:
	return _w.data.powers[power_idx] if power_idx >= 0 and power_idx < _w.data.powers.size() else null


func research_def(res_idx: int) -> DefResearch:
	return _w.data.research[res_idx] if res_idx >= 0 and res_idx < _w.data.research.size() else null


func neutral_def(def_idx: int) -> DefNeutral:
	return _w.data.neutrals[def_idx] if def_idx >= 0 and def_idx < _w.data.neutrals.size() else null


## My live unit cost / build ticks / structure cost / ticks / power (research and handicap-free values of the player's view).
func unit_cost(def_idx: int) -> int:
	return _w.players[_me].view.unit_cost[def_idx]


func unit_ticks(def_idx: int) -> int:
	return _w.players[_me].view.unit_ticks[def_idx]


func struct_cost(def_idx: int) -> int:
	return _w.players[_me].view.struct_cost[def_idx]


func struct_ticks(def_idx: int) -> int:
	return _w.players[_me].view.struct_ticks[def_idx]


func struct_power(def_idx: int) -> int:
	return _w.players[_me].view.struct_power[def_idx]


# ----------------------------------------------------------------------------------------------- own entities
## Ascending ids of my live units and structures (borrowed: never write, never keep across thinks).
func own_ids() -> PackedInt32Array:
	return _w.own_ids(_me)


func alive(eid: int) -> bool:
	return _w.is_alive(eid)


## out = [def, owner, kind, x, y, vx, vy, hp, hp_max, flags(EF_*), order_kind, ticks_since_combat, layer, paid_cost, container]
## (AiTypes.ROW_*); false if the entity is gone.
func read_row(eid: int, out: PackedInt32Array) -> bool:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or (e.flags & SimFlags.F_GONE) != 0:
		return false
	if out.size() < AiTypes.ROW_SIZE:
		out.resize(AiTypes.ROW_SIZE)
	out[0] = e.def_idx
	out[1] = e.owner
	out[2] = e.kind
	out[3] = e.x
	out[4] = e.y
	out[5] = e.vx
	out[6] = e.vy
	out[7] = e.hp
	out[8] = e.hp_max
	out[9] = _ef(e)
	out[10] = _order_kind(e)
	out[11] = _w.combat.ticks_since_combat(_w, e)
	out[12] = e.layer
	out[13] = e.paid_cost
	out[14] = e.container_id
	return true


func e_def(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.def_idx if e != null else -1


func e_owner(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.owner if e != null else -1


func e_kind(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.kind if e != null else -1


func e_x(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.x if e != null else 0


func e_y(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.y if e != null else 0


func e_hp(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.hp if e != null else 0


func e_hp_max(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.hp_max if e != null else 0


func e_layer(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.layer if e != null else 0


func e_flags(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return _ef(e) if e != null else 0


func e_order(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return _order_kind(e) if e != null else AiTypes.OrderKind.IDLE


func e_ticks_since_combat(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return _w.combat.ticks_since_combat(_w, e) if e != null else AiTypes.NEVER


func e_last_hit(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or e.combat == null or e.combat.last_hit_tick <= SimCombatConsts.NEVER:
		return -1
	return e.combat.last_hit_tick


func e_last_fire(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or e.combat == null or e.combat.last_fire_tick <= SimCombatConsts.NEVER:
		return -1
	return e.combat.last_fire_tick


## Loaded passenger squads. TODO(sim): SimCompCargo is a stub, so this counts the entities inside the container.
func e_cargo(eid: int) -> int:
	var n: int = 0
	for e: SimEntity in _w.units_of(_me):
		if e.container_id == eid and (e.flags & SimFlags.F_GONE) == 0:
			n += 1
	return n


func e_ammo(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return _w.combat.ammo_of(e, 0) if e != null else -1


## Stable mode index of a mode-switch unit (SimCompCombat.ext_mode, published by the abilities module); 0 without a combat
## component. The deployed state is in e_flags (EF_DEPLOYED).
func e_mode(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return maxi(e.combat.ext_mode, 0) if e != null and e.combat != null else 0


## Sortie state of an aircraft (SimCombatConsts.AIR_*; PARKED = 0 = on a pad with a full load), AIR_PARKED for anything else.
func e_air_state(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return SimAirSortie.sortie_state(e) if e != null else SimCombatConsts.AIR_PARKED


## Fuel / sortie mission of an aircraft: the mission code (SimCombatConsts.MI_*), 0 when none.
func e_air_mission(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.air.mission if e != null and e.air != null else 0


## Container (transport) entity id the unit sits in, -1 when it is not loaded.
func e_container(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.container_id if e != null else -1


## Free cargo slots of a transport of mine (squad slots); 0 for anything that is not a transport.
func cargo_free(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	if e == null or e.cargo == null:
		return 0
	return maxi(e.cargo.cap_slots - e.cargo.n_pax, 0)


## True when the wreck can be salvaged by ME right now (enemy wreck, flagged salvageable, not consumed).
func wreck_salvageable(id: int) -> bool:
	var e: SimEntity = _w.get_entity(id)
	return e != null and SimDeath.wreck_can_be_salvaged_by(_w, e, _me)


# ---------------------------------------------------------------------------------------------------- enemies
## Enemy units AND structures (not allies, not neutral), ascending eid; fog-honouring unless omniscient. Cached per tick.
func visible_enemy_ids(out: PackedInt32Array) -> int:
	if _enemy_cache_tick != _tick:
		_enemy_cache_tick = _tick
		if omniscient:
			_enemy_cache.resize(0)
			for e: SimEntity in _w.entities:
				if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
					continue
				if e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE:
					continue
				if _w.rel(_me, e.owner) == SimWorld.Rel.ENEMY and _w.fog.entity_revealed(_me, e):
					_enemy_cache.append(e.id)
		else:
			_w.visible_enemy_ids(_me, _enemy_cache)
	out.resize(_enemy_cache.size())
	for i: int in _enemy_cache.size():
		out[i] = _enemy_cache[i]
	return _enemy_cache.size()


func enemies_in_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int:
	return _w.enemies_in_circle(_me, x, y, r, out, omniscient)


## Real vision on the entity (what the sim requires for an ATTACK command).
func targetable_now(eid: int) -> bool:
	var e: SimEntity = _w.get_entity(eid)
	return e != null and (e.flags & SimFlags.F_GONE) == 0 and _w.entity_visible(_me, e)


func cell_visible(cx: int, cy: int) -> bool:
	return _w.cell_visible(_me, cx, cy)


func cell_explored(cx: int, cy: int) -> bool:
	return _w.cell_explored(_me, cx, cy)


# --------------------------------------------------------------------------------------------- rule validators
## Rule.* for starting construction of a structure (the same code path as the BUILD_START executor).
func can_build(struct_def: int) -> int:
	var rsn: int = _w.production.can_queue_structure(_w, _me, struct_def)
	if rsn == SimEconConst.RSN_OK and credits() < struct_cost(struct_def) / 4:
		return AiTypes.Rule.NO_CREDITS
	return _rule_of(rsn)


func can_place(struct_def: int, cx: int, cy: int, rot: int = 0) -> bool:
	return SimPlacement.validate(_w, _me, struct_def, cx, cy, rot, _pres) == SimEconConst.RSN_OK


func can_train(producer_eid: int, unit_def_idx: int) -> int:
	var rsn: int = _w.production.can_queue_unit(_w, _me, producer_eid, unit_def_idx)
	if rsn == SimEconConst.RSN_OK and unit_cap_room() <= 0:
		return AiTypes.Rule.UNIT_CAP
	return _rule_of(rsn)


func can_research(res_def: int) -> int:
	return _rule_of(_w.production.can_queue_research(_w, _me, res_def))


static func _rule_of(rsn: int) -> int:
	match rsn:
		SimEconConst.RSN_OK:
			return AiTypes.Rule.OK
		SimEconConst.RSN_PREREQ, SimEconConst.RSN_NO_HQ:
			return AiTypes.Rule.NEED_PREREQ
		SimEconConst.RSN_NOT_AVAILABLE, SimEconConst.RSN_LOCKED, SimEconConst.RSN_FEATURE_OFF:
			return AiTypes.Rule.LOCKED
		SimEconConst.RSN_QUEUE_FULL:
			return AiTypes.Rule.QUEUE_FULL
		SimEconConst.RSN_NO_CREDITS:
			return AiTypes.Rule.NO_CREDITS
		SimEconConst.RSN_STRATEGIC_LIMIT:
			return AiTypes.Rule.LIMIT
		SimEconConst.RSN_UNIT_CAP:
			return AiTypes.Rule.UNIT_CAP
		SimEconConst.RSN_NO_POWER:
			return AiTypes.Rule.POWER
		SimEconConst.RSN_BUSY, SimEconConst.RSN_HOLD:
			return AiTypes.Rule.BUSY
	return AiTypes.Rule.OTHER


## My support-power slot index (0..2) of power_def, -1 if my roster does not have it.
func power_slot(power_def_idx: int) -> int:
	var pe: SimPlayerEcon = _w.players[_me].econ
	for i: int in 3:
		if i < pe.slots.size() and pe.slots[i].def_idx == power_def_idx:
			return i
	return -1


func power_status(power_def_idx: int) -> int:
	var s: int = power_slot(power_def_idx)
	var pd: DefPower = power_def(power_def_idx)
	if s < 0 or pd == null:
		return AiTypes.PowerStatus.LOCKED_PREREQ
	var pe: SimPlayerEcon = _w.players[_me].econ
	var owned: int = 0
	for i: int in mini(pe.struct_count.size(), 60):
		if pe.struct_count[i] > 0:
			owned |= 1 << i
	if not DefRoster.prereqs_met(pd.requires_mask, owned):
		return AiTypes.PowerStatus.LOCKED_PREREQ
	if pe.slots[s].ready_tick > _tick:
		return AiTypes.PowerStatus.COOLDOWN
	if pd.requires_powered and not pe.powers_online:
		return AiTypes.PowerStatus.UNPOWERED
	if credits() < pd.cost:
		return AiTypes.PowerStatus.NO_CREDITS
	return AiTypes.PowerStatus.READY


func power_ready_tick(power_def_idx: int) -> int:
	var s: int = power_slot(power_def_idx)
	if s < 0:
		return -1
	return _w.players[_me].econ.slots[s].ready_tick


## DefPower.target_vision against REAL vision.
func power_target_ok(power_def_idx: int, x: int, y: int) -> bool:
	var pd: DefPower = power_def(power_def_idx)
	if pd == null or x < 0 or y < 0 or x >= _w.map.w * SimConfig.CELL or y >= _w.map.h * SimConfig.CELL:
		return false
	var cx: int = x >> SimConfig.CELL_SHIFT
	var cy: int = y >> SimConfig.CELL_SHIFT
	match pd.target_vision:
		DefEnums.TargetVision.EXPLORED:
			return cell_explored(cx, cy)
		DefEnums.TargetVision.CURRENT:
			return cell_visible(cx, cy)
	return true


func sw_status() -> int:
	var pe: SimPlayerEcon = _w.players[_me].econ
	if pe.slots.size() <= SimEconConst.SLOT_SW or pe.slots[SimEconConst.SLOT_SW].def_idx < 0:
		return AiTypes.SwStatus.NONE
	match pe.slots[SimEconConst.SLOT_SW].sw_state:
		SimEconConst.SW_CHARGING:
			return AiTypes.SwStatus.CHARGING
		SimEconConst.SW_READY:
			return AiTypes.SwStatus.READY
	return AiTypes.SwStatus.NONE


func sw_ready_tick() -> int:
	var pe: SimPlayerEcon = _w.players[_me].econ
	if pe.slots.size() <= SimEconConst.SLOT_SW:
		return -1
	var s: SimPowerSlot = pe.slots[SimEconConst.SLOT_SW]
	return _tick + maxi(s.recharge_ticks - s.charge, 0)


func sw_launcher_eid() -> int:
	var pe: SimPlayerEcon = _w.players[_me].econ
	if pe.slots.size() <= SimEconConst.SLOT_SW:
		return 0
	return pe.slots[SimEconConst.SLOT_SW].launcher_id


## Active HOSTILE superweapon warnings visible to me (the strategic warning zones cannot be hidden):
## [owner, sw_idx, x, y, angle, start_tick, impact_tick] * n; returns the number of ints (7 n). (x, y) is the target point (the middle of a line), impact_tick the
## tick the attack executes (warning end). Allied and own warnings are not listed.
func strategic_warnings(out: PackedInt32Array) -> int:
	out.resize(0)
	if _w == null or _w.strategic == null:
		return 0
	var live: Array = []
	_w.strategic.warnings_affecting(_me, live)
	for wv: Variant in live:
		var wr: SimWarning = wv as SimWarning
		if wr.kind != SimEconConst.WK_SUPER or wr.phase != SimEconConst.AT_WARNING or not is_enemy(wr.owner):
			continue
		var cx: int = wr.x
		var cy: int = wr.y
		if wr.width > 0:
			cx = (wr.x + wr.x2) / 2
			cy = (wr.y + wr.y2) / 2
		out.append(wr.owner)
		out.append(wr.src_idx)
		out.append(cx)
		out.append(cy)
		out.append(wr.angle)
		out.append(wr.start_tick)
		out.append(wr.exec_tick)
	return out.size()


# ------------------------------------------------------------------------------ production / construction state
## out = [state 0 idle / 1 building / 2 ready_to_place / 3 paused, def, progress_pct, ready_def]
func construction_state(out: PackedInt32Array) -> void:
	_w.production.construction_state(_me, out)


func queue_of(producer_eid: int, out: PackedInt32Array) -> int:
	return _w.production.queue_of(producer_eid, out)


func queue_progress_pct(producer_eid: int) -> int:
	return _w.production.queue_progress_pct(producer_eid)


func research_active() -> int:
	return _w.production.research_active(_me)


func research_done(res_def: int) -> bool:
	return _w.production.research_done(_me, res_def)


func pads_free(airfield_eid: int) -> int:
	var e: SimEntity = _w.get_entity(airfield_eid)
	return SimAirSortie.pads_free(_w, e) if e != null else 0


## Structures of mine ACTIVE per def index (borrowed array; index = structure def).
func struct_counts() -> PackedInt32Array:
	return _w.players[_me].econ.struct_count


func struct_count(struct_def: int) -> int:
	var c: PackedInt32Array = _w.players[_me].econ.struct_count
	return c[struct_def] if struct_def >= 0 and struct_def < c.size() else 0


## Structure defs waiting in the construction queue (borrowed).
func construction_queue() -> PackedInt32Array:
	return _w.players[_me].econ.cq_def


func has_hq() -> bool:
	return _w.players[_me].econ.active_hq_count > 0


## Active producer ids (all queue kinds, ascending; borrowed) and the SimEconConst.PROD_* kind of one.
func producer_ids() -> PackedInt32Array:
	return _w.players[_me].econ.producer_flat


func producer_kind(eid: int) -> int:
	var e: SimEntity = _w.get_entity(eid)
	return e.prod.kind if e != null and e.prod != null else 0


func refinery_ids() -> PackedInt32Array:
	return _w.players[_me].econ.refinery_ids


## Ids of my collectors (units with the harvest ability).
func collector_ids(out: PackedInt32Array) -> void:
	_w.economy.q_collectors(_me, out)


## Units the production queue of `producer_eid` can currently be offered (ascending def index).
func buildable_units(producer_eid: int, out: PackedInt32Array, include_locked: bool = false) -> void:
	_w.production.q_buildable_units(_w, _me, producer_eid, out, include_locked)


func buildable_structures(out: PackedInt32Array, include_locked: bool = false) -> void:
	_w.production.q_buildable_structures(_w, _me, out, include_locked)


func researchable(out: PackedInt32Array, include_locked: bool = false) -> void:
	_w.production.q_researchable(_w, _me, out, include_locked)


# ------------------------------------------------------------------------------------ public map info (T2)
func map_w() -> int:
	return _w.map.w


func map_h() -> int:
	return _w.map.h


func passable(cx: int, cy: int, move_class: int) -> bool:
	return _w.map.passable(cx, cy, move_class)


func region(cx: int, cy: int, move_class: int) -> int:
	return _w.map.region(cx, cy, move_class)


func is_water(cx: int, cy: int) -> bool:
	return _w.map.is_water(cx, cy)


func map_family() -> int:
	return _w.map.get_family()


## [cx0, cy0, cx1, cy1, ...] indexed by start index.
func start_positions() -> PackedInt32Array:
	return _w.map.start_cells


## Start cell x / y of player p (-1 when unknown).
func start_cell_x(p: int) -> int:
	var i: int = _start_index(p)
	return _w.map.start_cells[2 * i] if i >= 0 and 2 * i + 1 < _w.map.start_cells.size() else -1


func start_cell_y(p: int) -> int:
	var i: int = _start_index(p)
	return _w.map.start_cells[2 * i + 1] if i >= 0 and 2 * i + 1 < _w.map.start_cells.size() else -1


func _start_index(p: int) -> int:
	for s: SimPlayerSlot in _w.config.players:
		if s.pid == p:
			return s.start
	return -1


## Deposit FIELDS (economy field index 0..n-1). x/y are the field centre in sub-cells; left is the remaining credits.
func deposit_ids(out: PackedInt32Array) -> int:
	var n: int = _w.economy.deposits.count
	out.resize(n)
	for i: int in n:
		out[i] = i
	return n


func deposit_x(id: int) -> int:
	return _w.economy.deposits.x[id]


func deposit_y(id: int) -> int:
	return _w.economy.deposits.y[id]


func deposit_left(id: int) -> int:
	return _w.economy.deposits.stock(_w.map, id)


func deposit_klass(id: int) -> int:
	return _w.economy.deposits.klass[id]


func deposit_radius(id: int) -> int:
	return _w.economy.deposits.radius[id]


func deposit_cap(id: int) -> int:
	return _w.economy.deposits.cap[id]


func deposit_harvesters(id: int) -> int:
	return _w.economy.deposits.harvesters[id]


func deposit_max_harvesters(id: int) -> int:
	return _w.economy.deposits.max_harvesters(id)


## Alive neutral entities (capturable / garrisonable structures), ascending id.
func neutral_ids(out: PackedInt32Array) -> int:
	out.resize(0)
	for e: SimEntity in _w.neutrals:
		if (e.flags & SimFlags.F_GONE) == 0:
			out.append(e.id)
	return out.size()


func wrecks_in_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var r2: int = r * r
	for e: SimEntity in _w.wrecks:
		if (e.flags & SimFlags.F_GONE) != 0:
			continue
		var dx: int = e.x - x
		var dy: int = e.y - y
		if dx * dx + dy * dy <= r2:
			out.append(e.id)
	return out.size()


## out = [x, y, paid_cost, expire_tick, def, original_owner]
func wreck_info(id: int, out: PackedInt32Array) -> void:
	out.resize(6)
	var e: SimEntity = _w.get_entity(id)
	if e == null:
		out.fill(0)
		return
	out[0] = e.x
	out[1] = e.y
	out[2] = e.paid_cost
	out[3] = e.expire_tick
	out[4] = e.def_idx
	out[5] = e.owner


# ------------------------------------------------------------------------------------------- flag translation
func _ef(e: SimEntity) -> int:
	var f: int = e.flags
	var r: int = 0
	if (f & SimFlags.F_CLOAKED) != 0:
		r |= AiTypes.EF_CAMO
	if (f & (SimFlags.F_DEPLOYED | SimFlags.F_DEPLOYING)) != 0:
		r |= AiTypes.EF_DEPLOYED
	if (f & SimFlags.F_EMP_SHUT) != 0:
		r |= AiTypes.EF_EMP
	if e.kind == SimEntity.Kind.STRUCTURE and (f & SimFlags.F_POWERED) == 0 and (f & SimFlags.F_UNDER_CONSTRUCTION) == 0 \
			and _w.data.structures[e.def_idx].power < 0:
		r |= AiTypes.EF_UNPOWERED
	if (f & SimFlags.F_UNDER_CONSTRUCTION) != 0:
		r |= AiTypes.EF_UNDER_CONSTRUCTION
	if (f & SimFlags.F_GARRISONED) != 0:
		r |= AiTypes.EF_GARRISONED
	if (f & SimFlags.F_INSIDE) != 0:
		r |= AiTypes.EF_LOADED
	if (f & SimFlags.F_DECOY) != 0:
		r |= AiTypes.EF_DECOY
	if (f & SimFlags.F_MOVING) != 0:
		r |= AiTypes.EF_MOVING
	if (f & SimFlags.F_SUPPRESSED) != 0:
		r |= AiTypes.EF_SUPPRESSED
	if (f & SimFlags.F_REPAIR_ON) != 0:
		r |= AiTypes.EF_REPAIRING
	if not e.orders.is_empty() and e.orders[0].type == SimOrder.T_HOLD:
		r |= AiTypes.EF_HELD
	return r


static func _order_kind(e: SimEntity) -> int:
	if e.orders.is_empty():
		return AiTypes.OrderKind.IDLE
	match e.orders[0].type:
		SimOrder.T_MOVE, SimOrder.T_PATROL, SimOrder.T_FOLLOW:
			return AiTypes.OrderKind.MOVE
		SimOrder.T_ATTACK_MOVE:
			return AiTypes.OrderKind.ATTACK_MOVE
		SimOrder.T_ATTACK, SimOrder.T_FORCE_FIRE:
			return AiTypes.OrderKind.ATTACK
		SimOrder.T_GUARD, SimOrder.T_HOLD:
			return AiTypes.OrderKind.GUARD
		SimOrder.T_DEPLOY, SimOrder.T_DEPLOY_MCV:
			return AiTypes.OrderKind.DEPLOYING
		SimOrder.T_UNDEPLOY:
			return AiTypes.OrderKind.PACKING
		SimOrder.T_LOAD:
			return AiTypes.OrderKind.LOADING
		SimOrder.T_UNLOAD:
			return AiTypes.OrderKind.UNLOADING
		SimOrder.T_HARVEST:
			return AiTypes.OrderKind.HARVEST
		SimOrder.T_REPAIR:
			return AiTypes.OrderKind.REPAIR
		SimOrder.T_CAPTURE, SimOrder.T_GARRISON:
			return AiTypes.OrderKind.CAPTURE
		SimOrder.T_SALVAGE:
			return AiTypes.OrderKind.SALVAGE
		SimOrder.T_RETURN_CARGO, SimOrder.T_RETURN_BASE, SimOrder.T_LAND:
			return AiTypes.OrderKind.RETURNING
	return AiTypes.OrderKind.OTHER
