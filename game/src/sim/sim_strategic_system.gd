class_name SimStrategicSystem
extends RefCounted
## Strategic framework (economy 3.6 / 5.16 / 5.19; task EC3B, E7 + E8): support-power slots, validation, cost, cooldown,
## the effect scheduler, warning records, the windows registry and the CMD_USE_POWER / CMD_LAUNCH_SUPERWEAPON executors.
## Not a pipeline stage: SimPowerSystem (stage 4) calls `update` at the end of its pass and hashes `hash_into` through its
## `hash_state`. The slots themselves live in SimPlayerEcon.slots (hashed there).
##
## The work is split over three classes: this one (state, scheduler, warnings, commands, queries), SimStrategicEffects (the
## power recipes: classification, vision / terrain rules, activation, windows, `emit_packet`) and SimSuperweapons (charge
## machine, launch, timelines, danger). The effects themselves run in SimPowerFx / SimSummons / the zone system (AB3).
##
## Scheduler: records ordered by (tick, seq); `seq` is a monotonic counter so the order is total. Everything random is drawn
## at activation (one `world.rng.next_u32()` per activation) and stored in the record, so execution never touches the RNG.

const HISTORY_TICKS: int = 40  ## a DONE / CANCELLED warning stays queryable this long
const MAX_SCHED: int = 256
const REFRESH_TICKS: int = 10  ## affected_mask period
const MARGIN_U: int = 3072  ## players owning an entity within 3 cells of the zone are affected
## Scheduler kinds private to this domain (SimEconConst.SK_* stop at 14).
const SK_DONE: int = 20  ## warning end: phase DONE, EVT_SW_DONE

var warnings: Array[SimWarning] = []  ## ascending id
var sched: Array[SimScheduled] = []  ## ascending (tick, seq)
var next_warning_id: int = 1
var next_seq: int = 1
var windows: PackedInt32Array = PackedInt32Array()  ## triples [pid, p_idx, until_tick] of running non-instant effects
var stat_activations: int = 0
var stat_launches: int = 0

var _wref: WeakRef = null


# ---- setup ---------------------------------------------------------------------------------------------------------

## Economy's init_world calls this once: registers the two command executors.
func setup(world: SimWorld) -> void:
	_wref = weakref(world)
	if world.commands != null:
		world.commands.register_executor(SimCmd.USE_POWER, Callable(self, "handle_command"))
		world.commands.register_executor(SimCmd.LAUNCH_SUPERWEAPON, Callable(self, "handle_command"))


func init_world(world: SimWorld) -> void:
	setup(world)


## Idempotent: (re)binds the 3 support-power slots and the superweapon slot of a player to its roster.
func init_player(world: SimWorld, pid: int, _roster_idx: int) -> void:
	var p: SimPlayer = world.players[pid]
	if p.econ == null or p.roster == null:
		return
	for i: int in mini(p.roster.power_list.size(), SimEconConst.SLOT_SW):
		p.econ.slots[i].def_idx = p.roster.power_list[i]
	if world.rules.superweapons != 0:
		p.econ.slots[SimEconConst.SLOT_SW].def_idx = p.roster.superweapon


func _w() -> SimWorld:
	return _wref.get_ref() as SimWorld if _wref != null else null


# ---- stage-4 body --------------------------------------------------------------------------------------------------

func update(world: SimWorld) -> void:
	var tick: int = world.tick
	for p: SimPlayer in world.players:
		var pe: SimPlayerEcon = p.econ
		if pe == null:
			continue
		# the superweapon first: a launcher lost or shut down this tick cancels its warning before the timeline runs
		SimSuperweapons.step(world, self, p, pe)
		if p.eliminated == 0:
			_step_powers(world, p, pe, tick)
	_run_due(world, tick)
	_refresh_warnings(world, tick)


func _step_powers(world: SimWorld, p: SimPlayer, pe: SimPlayerEcon, tick: int) -> void:
	for i: int in SimEconConst.SLOT_SW:
		var s: SimPowerSlot = pe.slots[i]
		if s.def_idx < 0:
			continue
		if s.ready_tick > 0 and s.ready_tick == tick and s.uses > 0:
			world.emit(SimEconConst.EVT_POWER_READY, 0, 0, p.pid, i)
		if not s.announced:
			var d: DefPower = world.data.powers[s.def_idx]
			if d.requires_mask == 0:
				continue  # never locked: nothing to announce (test fixtures; every real power needs a Radar)
			if prereqs_present(pe, d.requires_mask) and (not d.requires_powered or prereqs_online(world, p.pid, d.requires_mask)):
				s.announced = true
				world.emit(SimEconConst.EVT_POWER_UNLOCKED, 0, 0, p.pid, i)


# ---- validation and AI / UI state ---------------------------------------------------------------------------------

## Every structure of `mask` (bit = s_idx) has an ACTIVE, non-temporary instance (SimPlayerEcon.struct_count).
static func prereqs_present(pe: SimPlayerEcon, mask: int) -> bool:
	var m: int = mask
	var i: int = 0
	while m != 0:
		if (m & 1) != 0 and (i >= pe.struct_count.size() or pe.struct_count[i] <= 0):
			return false
		m >>= 1
		i += 1
	return true


## Every structure of `mask` has an instance that is online (ACTIVE, not shut down, powered by its class rule).
func prereqs_online(world: SimWorld, pid: int, mask: int) -> bool:
	var m: int = mask
	var i: int = 0
	while m != 0:
		if (m & 1) != 0:
			var ok: bool = false
			for e: SimEntity in world.structures_of(pid):
				if e.def_idx == i and (e.flags & SimFlags.F_GONE) == 0 and world.economy.life.structure_online(world, e):
					ok = true
					break
			if not ok:
				return false
		m >>= 1
		i += 1
	return true


## Reason code (RSN_*, 0 = OK) - first failure wins (economy 5.16).
func can_activate(world: SimWorld, pid: int, slot: int, tx: int, ty: int, angle: int, target_id: int) -> int:
	if pid < 0 or pid >= world.players.size() or slot < 0 or slot >= SimEconConst.SLOT_COUNT:
		return SimEconConst.RSN_INVALID_INDEX
	var p: SimPlayer = world.players[pid]
	if p.econ == null or p.eliminated != 0:
		return SimEconConst.RSN_INVALID_INDEX
	if slot == SimEconConst.SLOT_SW:
		return SimSuperweapons.can_launch(world, pid, tx, ty, angle)
	return SimStrategicEffects.can_use(world, p, slot, tx, ty, angle, target_id)


func slot_info(pid: int, slot: int) -> SimPowerSlot:
	var w: SimWorld = _w()
	if w == null or pid < 0 or pid >= w.players.size() or slot < 0 or slot >= SimEconConst.SLOT_COUNT or w.players[pid].econ == null:
		return null
	return w.players[pid].econ.slots[slot]


## Support powers: ready_tick - tick; superweapon: recharge_ticks - charge (0 when READY, the full recharge when there is no launcher).
func cooldown_left_ticks(world: SimWorld, pid: int, slot: int) -> int:
	var s: SimPowerSlot = slot_info(pid, slot)
	if s == null or s.def_idx < 0:
		return 0
	if slot == SimEconConst.SLOT_SW:
		if s.sw_state == SimEconConst.SW_READY:
			return 0
		var rt: int = s.recharge_ticks if s.recharge_ticks > 0 else world.data.superweapons[s.def_idx].recharge_t
		return rt - s.charge
	return maxi(s.ready_tick - world.tick, 0)


## Appends the live (WARNING / EXEC) warnings whose zone is visible to `pid` (including its own).
func warnings_affecting(pid: int, out: Array) -> void:
	for w: SimWarning in warnings:
		if w.phase <= SimEconConst.AT_EXEC and ((w.affected_mask >> pid) & 1) != 0:
			out.append(w)


## Hostile live warnings whose zone (with the 3-cell margin) contains an entity of `pid`.
func attacks_pending_against(pid: int, out: Array) -> void:
	var world: SimWorld = _w()
	if world == null:
		return
	var team: int = world.team_of(pid)
	for w: SimWarning in warnings:
		if w.phase > SimEconConst.AT_EXEC or world.team_of(w.owner) == team:
			continue
		for id: int in world.own_ids(pid):
			var e: SimEntity = world.by_id[id]
			if e != null and (e.flags & SimFlags.F_GONE) == 0 and SimSuperweapons.in_zone(w, e.x, e.y, MARGIN_U):
				out.append(w)
				break


func get_warning(id: int) -> SimWarning:
	for w: SimWarning in warnings:
		if w.id == id:
			return w
	return null


## true while a launcher has an attack in its WARNING phase (a sale is refused meanwhile).
func sell_locked(pid: int, eid: int) -> bool:
	for w: SimWarning in warnings:
		if w.owner == pid and w.launcher_id == eid and w.phase == SimEconConst.AT_WARNING and w.kind == SimEconConst.WK_SUPER:
			return true
	return false


# ---- windows -------------------------------------------------------------------------------------------------------

## A running non-instant effect of power `p_idx` (Mobilization Order, Treaty, Joint Landing ...) of the player.
func window_active(world: SimWorld, pid: int, p_idx: int) -> bool:
	var i: int = 0
	while i + 2 < windows.size():
		if windows[i] == pid and windows[i + 1] == p_idx and windows[i + 2] > world.tick:
			return true
		i += 3
	return false


## Effective knob value (economy 4.5).
func knob(world: SimWorld, pid: int, k: int) -> int:
	return world.economy.knob(pid, k)


func on_unit_spawned(world: SimWorld, ent: SimEntity) -> void:
	SimPowerFx.on_unit_spawn(world, ent)  # idempotent: the zone system already forwards every spawn


## The launcher of a superweapon died, was sold or lost (hook; update() detects the same conditions by polling).
func on_structure_lost(world: SimWorld, ent: SimEntity, cause: int) -> void:
	if ent.owner < 0 or ent.owner >= world.players.size() or world.players[ent.owner].econ == null:
		return
	var s: SimPowerSlot = world.players[ent.owner].econ.slots[SimEconConst.SLOT_SW]
	if s.launcher_id == ent.id:
		SimSuperweapons.launcher_lost(world, self, ent.owner, s, 3 if cause == 3 else 1)


## EMP shutdown of a launcher (hook): the warning attack of that launcher is cancelled.
func on_shutdown_started(world: SimWorld, ent: SimEntity) -> void:
	SimSuperweapons.cancel_for_launcher(world, self, ent.owner, ent.id, 2)


# ---- commands ------------------------------------------------------------------------------------------------------

## CMD_USE_POWER (140) and CMD_LAUNCH_SUPERWEAPON (141). Returns a SimCommand.Err; the RSN_* is left in cmd.detail.
func handle_command(world: SimWorld, cmd: SimCommand) -> int:
	var rsn: int = SimEconConst.RSN_NOT_AVAILABLE
	if cmd.pid < 0 or cmd.pid >= world.players.size() or world.players[cmd.pid].econ == null:
		return SimCommand.Err.BAD_PLAYER
	match cmd.op:
		SimCmd.USE_POWER:
			rsn = use_power(world, cmd.pid, cmd.def, cmd.x, cmd.y, cmd.angle, cmd.target)
		SimCmd.LAUNCH_SUPERWEAPON:
			rsn = SimSuperweapons.launch(world, self, cmd.pid, cmd.x, cmd.y, cmd.angle)
	if rsn == SimEconConst.RSN_OK:
		return SimCommand.Err.OK
	cmd.detail = rsn
	return SimEconomySystem.err_of(rsn)


## Fires support power `p_idx` of the player (must be one of its three). RSN_*.
func use_power(world: SimWorld, pid: int, p_idx: int, x: int, y: int, angle: int, target_id: int) -> int:
	var p: SimPlayer = world.players[pid]
	var slot: int = p.roster.power_slot(p_idx) if p.roster != null else -1
	if slot < 0 or slot >= SimEconConst.SLOT_SW or p.econ == null or p.econ.slots[slot].def_idx != p_idx:
		return SimEconConst.RSN_NOT_AVAILABLE
	var r: int = can_activate(world, pid, slot, x, y, angle, target_id)
	if r != SimEconConst.RSN_OK:
		return r
	stat_activations += 1
	return SimStrategicEffects.activate(world, self, p, slot, x, y, angle, target_id)


# ---- packet choke point --------------------------------------------------------------------------------------------

## Strategic damage enters combat here (economy 5.20). Trident's rules run inside combat's detonation, so this builds the
## warhead of the packet and lets combat detonate it at once; see SimStrategicEffects.emit_packet.
func emit_packet(world: SimWorld, pk: SimImpactPacket) -> void:
	SimStrategicEffects.emit_packet(world, pk)


# ---- warnings ------------------------------------------------------------------------------------------------------

## Creates a warning record (WARNING phase) with its scheduler entry and mirror zone; returns it.
func add_warning(world: SimWorld, kind: int, src_idx: int, owner: int, launcher_id: int, geom: PackedInt32Array, warn_t: int, span_t: int) -> SimWarning:
	var w: SimWarning = SimWarning.new()
	w.id = next_warning_id
	next_warning_id += 1
	w.kind = kind
	w.src_idx = src_idx
	w.owner = owner
	w.launcher_id = launcher_id
	w.x = geom[0]
	w.y = geom[1]
	w.x2 = geom[2]
	w.y2 = geom[3]
	w.radius = geom[4]
	w.width = geom[5]
	w.angle = geom[6]
	w.start_tick = world.tick
	w.exec_tick = world.tick + warn_t
	w.end_tick = w.exec_tick + span_t
	w.phase = SimEconConst.AT_WARNING
	w.refresh_tick = world.tick + REFRESH_TICKS
	w.affected_mask = SimSuperweapons.affected_mask(world, w)
	var zid: int = -1
	if world.zones != null and warn_t > 0:
		if w.width > 0:
			zid = world.zones.spawn_warning(SimZoneConsts.WK_LINE, owner, (w.x + w.x2) / 2, (w.y + w.y2) / 2, w.angle, SimSuperweapons.line_len(w), w.width, warn_t)
		else:
			zid = world.zones.spawn_warning(SimZoneConsts.WK_CIRCLE, owner, w.x, w.y, w.angle, w.radius, 0, warn_t)
	w.payload_ids = PackedInt32Array([zid])
	warnings.append(w)
	world.emit(SimEconConst.EVT_WARNING, w.x, w.y, w.id, owner, kind, src_idx, w.x, w.y)
	return w


## Cancels a warning in its WARNING phase: no effect runs, no refund. `cause`: 1 destroyed, 2 shutdown, 3 sold.
func cancel_warning(world: SimWorld, w: SimWarning, cause: int) -> void:
	if w.phase != SimEconConst.AT_WARNING:
		return
	w.phase = SimEconConst.AT_CANCELLED
	w.end_tick = world.tick
	var i: int = sched.size() - 1
	while i >= 0:
		if sched[i].attack_id == w.id:
			sched.remove_at(i)
		i -= 1
	if world.zones != null and w.payload_ids.size() > 0 and w.payload_ids[0] >= 0:
		world.zones.end_zone(w.payload_ids[0], SimZoneConsts.ZE_CANCELLED)
	if w.owner >= 0 and w.owner < world.players.size() and world.players[w.owner].econ != null:
		var s: SimPowerSlot = world.players[w.owner].econ.slots[SimEconConst.SLOT_SW]
		if s.pending_attack == w.id:
			s.pending_attack = 0
	world.emit(SimEconConst.EVT_SW_CANCELLED, w.x, w.y, w.owner, w.src_idx, cause, w.id)


func _refresh_warnings(world: SimWorld, tick: int) -> void:
	var i: int = warnings.size() - 1
	while i >= 0:
		var w: SimWarning = warnings[i]
		if w.phase >= SimEconConst.AT_DONE:
			if tick >= w.end_tick + HISTORY_TICKS:
				warnings.remove_at(i)
		elif tick >= w.refresh_tick:
			w.affected_mask = SimSuperweapons.affected_mask(world, w)
			w.refresh_tick = tick + REFRESH_TICKS
		i -= 1


# ---- scheduler -----------------------------------------------------------------------------------------------------

## Inserts a record ordered by (tick, seq). false (and an error) when the 256-record cap is hit.
func schedule(tick: int, kind: int, owner: int, src_idx: int, attack_id: int, x: int = 0, y: int = 0, r: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> bool:
	if sched.size() >= MAX_SCHED:
		Log.error("strategic", "scheduler full (%d records): dropped kind %d" % [MAX_SCHED, kind])
		return false
	var rec: SimScheduled = SimScheduled.new()
	rec.tick = tick
	rec.seq = next_seq
	next_seq += 1
	rec.kind = kind
	rec.owner = owner
	rec.src_idx = src_idx
	rec.attack_id = attack_id
	rec.x = x
	rec.y = y
	rec.r = r
	rec.a = a
	rec.b = b
	rec.c = c
	rec.d = d
	var at: int = sched.size()
	while at > 0 and sched[at - 1].tick > tick:
		at -= 1
	sched.insert(at, rec)
	return true


func pending_count() -> int:
	return sched.size()


func _run_due(world: SimWorld, tick: int) -> void:
	var guard: int = 0
	while not sched.is_empty() and sched[0].tick <= tick and guard < 4 * MAX_SCHED:
		var rec: SimScheduled = sched[0]
		sched.remove_at(0)
		guard += 1
		_run(world, rec)


func _run(world: SimWorld, rec: SimScheduled) -> void:
	match rec.kind:
		SimEconConst.SK_WARNING_END:
			SimSuperweapons.warning_end(world, self, rec)
		SimEconConst.SK_PACKET:
			var w: SimWarning = get_warning(rec.attack_id)
			if w == null or w.phase == SimEconConst.AT_CANCELLED:
				return
			world.emit(SimEconConst.EVT_SW_IMPACT, rec.x, rec.y, rec.src_idx, rec.x, rec.y, rec.r, rec.a)
		SimEconConst.SK_WINDOW_END:
			SimStrategicEffects.window_end(world, self, rec)
		SK_DONE:
			var w2: SimWarning = get_warning(rec.attack_id)
			if w2 != null and w2.phase == SimEconConst.AT_EXEC:
				w2.phase = SimEconConst.AT_DONE
				w2.end_tick = world.tick
				if w2.owner >= 0 and w2.owner < world.players.size() and world.players[w2.owner].econ != null:
					var sl: SimPowerSlot = world.players[w2.owner].econ.slots[SimEconConst.SLOT_SW]
					if sl.pending_attack == w2.id:
						sl.pending_attack = 0
				world.emit(SimEconConst.EVT_SW_DONE, w2.x, w2.y, w2.id)
		_:
			Log.error("strategic", "unknown scheduled kind %d" % rec.kind)


# ---- windows registry ----------------------------------------------------------------------------------------------

func set_window(pid: int, p_idx: int, until: int) -> void:
	var i: int = 0
	while i + 2 < windows.size():
		if windows[i] == pid and windows[i + 1] == p_idx:
			windows[i + 2] = until
			return
		i += 3
	windows.append(pid)
	windows.append(p_idx)
	windows.append(until)


func clear_window(pid: int, p_idx: int) -> void:
	var i: int = 0
	while i + 2 < windows.size():
		if windows[i] == pid and windows[i + 1] == p_idx:
			windows.remove_at(i + 2)
			windows.remove_at(i + 1)
			windows.remove_at(i)
			return
		i += 3


# ---- hash ----------------------------------------------------------------------------------------------------------

## Appends nothing while the system is pristine (keeps the goldens of matches that never use a power).
func hash_into(buf: PackedInt32Array) -> void:
	if next_warning_id == 1 and next_seq == 1 and stat_activations == 0 and stat_launches == 0 and windows.is_empty() and warnings.is_empty() and sched.is_empty():
		return
	buf.append(next_warning_id)
	buf.append(next_seq)
	buf.append(stat_activations)
	buf.append(stat_launches)
	buf.append(warnings.size())
	for w: SimWarning in warnings:
		w.hash_into(buf)
	buf.append(sched.size())
	for r: SimScheduled in sched:
		r.hash_into(buf)
	buf.append(windows.size())
	buf.append_array(windows)
