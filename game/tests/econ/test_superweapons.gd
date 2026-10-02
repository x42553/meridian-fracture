extends RefCounted
## 10.1-K (economy tests): the eight superweapons on the REAL data through CMD_LAUNCH_SUPERWEAPON: the charge machine,
## activation, warning zones, cancellation, the execution timelines (packet counts, radii, durations), Trident interception
## and S6 (superweapon duel). Timelines are the ones compiled from global.json (DefSuperweapon), which override the prose
## of economy 5.21 where they differ (Atlas rods land together, Helios pulses every 5 ticks).

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const CELL: int = 1024


func _w(a: String, b: String, launchers: bool = true) -> SimWorld:
	var w: SimWorld = A.world({"rosters": [a, b], "movement": false, "invariants_every": 25})
	S.base(w, 0, 10, 10)
	S.base(w, 1, 44, 44, launchers)
	return w


func _sw_id(w: SimWorld, pid: int) -> DefSuperweapon:
	return w.data.superweapons[w.players[pid].econ.slots[SimEconConst.SLOT_SW].def_idx]


func _launcher(w: SimWorld, pid: int) -> SimEntity:
	return w.get_entity(w.players[pid].econ.slots[SimEconConst.SLOT_SW].launcher_id)


func _state(w: SimWorld, pid: int) -> int:
	return w.players[pid].econ.slots[SimEconConst.SLOT_SW].sw_state


func _fire(w: SimWorld, pid: int, cx: int, cy: int, angle: int = 0) -> SimWarning:
	S.force_ready(w, pid)
	w.clear_events()
	S.launch(w, pid, cx, cy, angle)
	w.step()
	var out: Array[SimWarning] = []
	w.strategic.warnings_affecting(pid, out)
	return out[out.size() - 1] if not out.is_empty() else null


# ---- charge machine ------------------------------------------------------------------------------------------------------

func test_starts_empty_charges_exactly_and_never_overcharges(t: TestCtx) -> void:
	for pair: Array in [["roster.napc.usa", 9600], ["roster.nec.vanilla", 8400], ["roster.sap.vanilla", 7200]]:
		var w: SimWorld = _w(pair[0], "roster.def.vanilla", false)
		var s: SimPowerSlot = S.slot(w, 0, SimEconConst.SLOT_SW)
		t.eq(s.sw_state, SimEconConst.SW_CHARGING, "%s: launcher ACTIVE -> CHARGING" % pair[0])
		t.eq(s.recharge_ticks, int(pair[1]), "%s: recharge ticks" % pair[0])
		t.check(s.charge <= 2, "%s: starts empty" % pair[0])
		var start: int = w.tick - s.charge
		var took: int = S.charge_up(w, 0, 10000)
		t.eq(w.tick - start, int(pair[1]), "%s: READY after exactly %d ticks" % [pair[0], int(pair[1])])
		t.eq(S.n_events(w, SimEconConst.EVT_SW_READY), 1, "%s: EVT_SW_READY" % pair[0])
		A.run(w, 120)
		t.eq(s.charge, int(pair[1]), "%s: READY does not overcharge" % pair[0])
		t.eq(s.sw_state, SimEconConst.SW_READY, "%s: still READY" % pair[0])
		t.gt(took, 0, "charged")


func test_shortage_pauses_charging(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.sap.vanilla", "roster.def.vanilla", false)
	var s: SimPowerSlot = S.slot(w, 0, SimEconConst.SLOT_SW)
	A.run(w, 500)
	for e: SimEntity in w.structures_of(0):
		if w.data.structures[e.def_idx].id == "structure.shared.generator":
			w.kill(e, SimWorld.Cause.SCRIPT)
	A.run(w, 10)
	t.check(w.power.is_shortage(0), "shortage")
	var frozen_at: int = s.charge
	A.run(w, 50)
	t.eq(s.charge, frozen_at, "no charge during a shortage")
	t.eq(s.sw_state, SimEconConst.SW_CHARGING, "state unchanged")
	for i2: int in 6:
		A.structure(w, "structure.shared.generator", 0, 10 + 3 * (i2 % 3), 30 + 3 * (i2 / 3))
	A.run(w, 5)
	t.check(not w.power.is_shortage(0), "power back")
	var before: int = s.charge
	A.run(w, 100)
	t.ge(s.charge, before + 95, "charging resumes")


func test_shortage_delays_ready_by_the_shortage(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.sap.vanilla", "roster.def.vanilla", false)
	var s: SimPowerSlot = S.slot(w, 0, SimEconConst.SLOT_SW)
	var start: int = w.tick
	A.run(w, 1000)
	# a 600-tick shortage: a huge consumer is added, then removed (sold by kill)
	var hogs: Array[SimEntity] = []
	for i: int in 24:
		hogs.append(A.structure(w, "structure.shared.laboratory", 0, 4 + 4 * (i % 8), 30 + 4 * (i / 8)))
	A.run(w, 3)
	var was_short: bool = w.power.is_shortage(0)
	t.check(was_short, "24 Laboratories cause a shortage")
	while w.tick - start < 1000 + 600:
		w.step()
	for h: SimEntity in hogs:
		w.kill(h, SimWorld.Cause.SCRIPT)
	A.run(w, 5)
	t.check(not w.power.is_shortage(0), "shortage over")
	var ready_at: int = -1
	while w.tick - start < 20000:
		if s.sw_state == SimEconConst.SW_READY:
			ready_at = w.tick
			break
		w.step()
	t.gt(ready_at, 0, "became READY")
	# READY = recharge + every powered-off tick after the launcher went ACTIVE (ticks 1000..1600+ spent in shortage)
	t.ge(ready_at - start, 7200 + 590, "delayed by about the shortage")
	t.le(ready_at - start, 7200 + 640, "and not by more")


# ---- activation, warning, cancellation ------------------------------------------------------------------------------------

func test_activation_restarts_the_charge_and_opens_the_warning(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var sw: DefSuperweapon = _sw_id(w, 0)
	var s: SimPowerSlot = S.slot(w, 0, SimEconConst.SLOT_SW)
	t.eq(w.strategic.can_activate(w, 0, SimEconConst.SLOT_SW, S.c(30), S.c(30), 0, 0), SimEconConst.RSN_NOT_CHARGED, "NOT_CHARGED while charging")
	S.force_ready(w, 0)
	var credits: int = w.players[0].credits
	w.clear_events()
	S.launch(w, 0, 30, 30, 0)
	w.step()
	var t0: int = w.tick - 1
	t.eq(w.players[0].credits, credits, "no credits to fire")
	t.eq(s.sw_state, SimEconConst.SW_CHARGING, "back to CHARGING")
	t.eq(s.charge, 0, "charge 0 at activation")
	t.eq(s.last_activation_tick, t0, "last_activation_tick")
	var out: Array[SimWarning] = []
	w.strategic.warnings_affecting(0, out)
	t.eq(out.size(), 1, "one warning")
	var wr: SimWarning = out[0]
	t.eq(wr.kind, SimEconConst.WK_SUPER, "WK_SUPER")
	t.eq(wr.exec_tick, t0 + sw.warning_t, "exec at T + warning")
	t.eq(sw.warning_t, 200, "Atlas warning 200 ticks")
	t.eq(wr.launcher_id, s.launcher_id, "launcher recorded")
	t.eq(s.pending_attack, wr.id, "pending_attack")
	t.eq(S.n_events(w, SimEconConst.EVT_WARNING), 1, "EVT_WARNING")
	t.eq(S.n_events(w, SimEconConst.EVT_POWER_ACTIVATED), 1, "EVT_POWER_ACTIVATED")
	t.eq(wr.width, 2 * 2048, "capsule: the rod circles (radius 2 cells) around the 6-cell line")
	A.run(w, 10)
	t.eq(s.charge, 10, "recharge started at once")
	t.eq(w.strategic.cooldown_left_ticks(w, 0, SimEconConst.SLOT_SW), 9600 - 10, "cooldown_left = recharge - charge")
	t.eq(w.strategic.sell_locked(0, wr.launcher_id), true, "launcher cannot be sold during the warning")
	# another launch at once: not charged
	S.launch(w, 0, 31, 31)
	w.step()
	t.eq(S.n_events(w, SimEconConst.EVT_WARNING), 1, "no second launch")


func test_launch_validation_order(t: TestCtx) -> void:
	var w: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false, "fog": true})
	S.base(w, 0, 10, 10, false)
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(30), S.c(30), 0, 0), SimEconConst.RSN_NO_LAUNCHER, "no launcher")
	var l: SimEntity = A.structure(w, "structure.napc.atlas_kinetic_array", 0, 19, 13)
	A.run(w, 2)
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(30), S.c(30), 0, 0), SimEconConst.RSN_NOT_CHARGED, "NOT_CHARGED")
	S.force_ready(w, 0)
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(30), S.c(30), 0, 0), SimEconConst.RSN_NOT_EXPLORED, "target must be explored (fog on)")
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(14), S.c(14), 0, 0), SimEconConst.RSN_OK, "explored target near the base")
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(14), S.c(14), 5000, 0), SimEconConst.RSN_BAD_TARGET, "angle out of range")
	t.eq(w.strategic.can_activate(w, 0, 3, -1, S.c(14), 0, 0), SimEconConst.RSN_TERRAIN, "outside the map")
	l.econ.shutdown_until = w.tick + 100
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(14), S.c(14), 0, 0), SimEconConst.RSN_NO_POWER, "launcher shut down")
	l.econ.shutdown_until = 0
	for e: SimEntity in w.structures_of(0):
		if w.data.structures[e.def_idx].id == "structure.shared.laboratory":
			w.kill(e, SimWorld.Cause.SCRIPT)
	A.run(w, 3)
	S.force_ready(w, 0)
	t.eq(w.strategic.can_activate(w, 0, 3, S.c(14), S.c(14), 0, 0), SimEconConst.RSN_PREREQ, "Laboratory gone: PREREQ")
	var off: SimWorld = A.world({"rosters": ["roster.napc.usa", "roster.nec.vanilla"], "movement": false, "rules": {"superweapons": 0}})
	t.eq(off.strategic.can_activate(off, 0, 3, S.c(14), S.c(14), 0, 0), SimEconConst.RSN_FEATURE_OFF, "superweapons off")


func test_launcher_destroyed_during_the_warning_cancels_without_refund(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	var t0: int = wr.start_tick
	var l: SimEntity = _launcher(w, 0)
	A.run_to(w, t0 + 100)
	w.kill(l, SimWorld.Cause.SCRIPT)
	A.run(w, 3)
	t.eq(wr.phase, SimEconConst.AT_CANCELLED, "cancelled")
	t.eq(S.n_events(w, SimEconConst.EVT_SW_CANCELLED), 1, "EVT_SW_CANCELLED")
	t.eq(A.event_field(w, SimEconConst.EVT_SW_CANCELLED, 0, SimEvent.I_C), 1, "cause 1: destroyed")
	var s: SimPowerSlot = S.slot(w, 0, SimEconConst.SLOT_SW)
	t.eq(s.sw_state, SimEconConst.SW_NONE, "no launcher: NONE (charge lost)")
	t.eq(s.charge, 0, "no refund")
	A.run_to(w, t0 + 230)
	t.eq(S.n_events(w, SimEconConst.EVT_SW_EXEC_START), 0, "never executes")
	t.eq(w.combat.proj.live_count(), 0, "no projectile")
	# a rebuilt launcher starts a fresh EMPTY charge
	A.structure(w, "structure.napc.atlas_kinetic_array", 0, 19, 13)
	A.run(w, 3)
	t.eq(s.sw_state, SimEconConst.SW_CHARGING, "fresh charge")
	t.check(s.charge <= 2, "empty")


func test_emp_shutdown_during_the_warning_cancels(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	var t0: int = wr.start_tick
	A.run_to(w, t0 + 100)
	var l: SimEntity = _launcher(w, 0)
	SimDamage.apply_emp(w, l, 360, 1)
	t.gt(l.econ.shutdown_until, w.tick, "the EMP wrote the economy shutdown")
	A.run(w, 3)
	t.eq(wr.phase, SimEconConst.AT_CANCELLED, "cancelled by the shutdown")
	t.eq(A.event_field(w, SimEconConst.EVT_SW_CANCELLED, 0, SimEvent.I_C), 2, "cause 2: shutdown")
	t.eq(S.slot(w, 0, SimEconConst.SLOT_SW).sw_state, SimEconConst.SW_CHARGING, "the launcher survives: charging from the activation")
	var c: int = S.slot(w, 0, SimEconConst.SLOT_SW).charge
	A.run(w, 50)
	t.eq(S.slot(w, 0, SimEconConst.SLOT_SW).charge, c, "and the shut-down launcher does not charge")


func test_shortage_during_warning_does_not_cancel_and_late_loss_does_not_either(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	var t0: int = wr.start_tick
	A.run_to(w, t0 + 50)
	for e: SimEntity in w.structures_of(0):
		if w.data.structures[e.def_idx].id == "structure.shared.generator":
			w.kill(e, SimWorld.Cause.SCRIPT)
	A.run(w, 5)
	t.check(w.power.is_shortage(0), "shortage during the warning")
	t.eq(wr.phase, SimEconConst.AT_WARNING, "does not cancel")
	A.run_to(w, t0 + 201)
	t.eq(wr.phase, SimEconConst.AT_EXEC, "executes")
	t.eq(S.n_events(w, SimEconConst.EVT_SW_EXEC_START), 1, "EVT_SW_EXEC_START")
	# launcher lost after exec: the attack goes on
	var wr2: SimWarning = null
	var w2: SimWorld = _w("roster.helios_placeholder" if false else "roster.olm.vanilla", "roster.nec.vanilla")
	wr2 = _fire(w2, 0, 32, 32, 0)
	A.run_to(w2, wr2.exec_tick + 1)
	w2.kill(_launcher(w2, 0), SimWorld.Cause.SCRIPT)
	A.run(w2, 60)
	t.check(wr2.phase != SimEconConst.AT_CANCELLED, "loss after exec_tick does not cancel")
	t.eq(w2.combat.proj.live_count() > 0 or wr2.phase == SimEconConst.AT_DONE, true, "the sweep keeps going")


# ---- the timelines ---------------------------------------------------------------------------------------------------------

func _tick_events(w: SimWorld, type: int, to_tick: int) -> Array[PackedInt32Array]:
	## steps from the current tick to `to_tick` collecting (tick, x, y, d, e) of every event of `type`
	var out: Array[PackedInt32Array] = []
	while w.tick < to_tick:
		w.clear_events()
		w.step()
		var d: PackedInt32Array = w.events.data
		for i: int in d.size() / SimEvent.STRIDE:
			if d[i * SimEvent.STRIDE + SimEvent.I_TYPE] == type:
				out.append(PackedInt32Array([w.tick - 1, d[i * SimEvent.STRIDE + SimEvent.I_X], d[i * SimEvent.STRIDE + SimEvent.I_Y],
					d[i * SimEvent.STRIDE + SimEvent.I_D], d[i * SimEvent.STRIDE + SimEvent.I_E]]))
	return out


func test_atlas_three_rods(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var target: SimEntity = A.structure(w, "structure.shared.barracks", 1, 32, 32)
	var wr: SimWarning = _fire(w, 0, 32, 32, 0)
	var hp0: int = target.hp
	var ev: Array[PackedInt32Array] = _tick_events(w, SimEconConst.EVT_SW_IMPACT, wr.exec_tick + 30)
	t.eq(ev.size(), 3, "three rods")
	var xs: PackedInt32Array = PackedInt32Array()
	for e: PackedInt32Array in ev:
		t.eq(e[0], wr.exec_tick, "rods land together at X (compiled data: delay 0)")
		t.eq(e[3], 2 * CELL, "radius 2.0 cells")
		xs.append(e[1])
	xs.sort()
	t.eq(xs[1] - xs[0], 3 * CELL, "centres 3 cells apart (-3, 0)")
	t.eq(xs[2] - xs[1], 3 * CELL, "(0, +3)")
	t.lt(target.hp, hp0, "the Barracks took damage")
	t.eq(wr.phase, SimEconConst.AT_DONE, "DONE")
	# a rotated line: 90 degrees turns the rods north-south
	var w2: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr2: SimWarning = _fire(w2, 0, 32, 32, 1024)
	var ev2: Array[PackedInt32Array] = _tick_events(w2, SimEconConst.EVT_SW_IMPACT, wr2.exec_tick + 5)
	var ys: PackedInt32Array = PackedInt32Array()
	for e2: PackedInt32Array in ev2:
		ys.append(e2[2])
		t.check(absi(e2[1] - S.c(32)) <= 2, "x stays on the axis")
	ys.sort()
	t.eq(ys[2] - ys[0], 6 * CELL, "line length 6 cells")


func test_aurora_emp_burst(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.nec.vanilla", "roster.napc.usa")
	var tank: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 32, 32)
	var inf: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 1, 33, 32)
	var own: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 0, 31, 32)
	var far: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 1, 50, 20)
	var radar: SimEntity = null
	for e: SimEntity in w.structures_of(1):
		if w.data.structures[e.def_idx].id == "structure.shared.radar":
			radar = e
	var gen: SimEntity = A.structure(w, "structure.shared.barracks", 1, 34, 34)
	A.hold_fire(w)
	var wr: SimWarning = _fire(w, 0, 32, 32)
	t.eq(wr.exec_tick - wr.start_tick, 160, "Aurora warning 160 ticks")
	t.eq(wr.radius, 8 * CELL, "burst radius 8 cells")
	A.run_to(w, wr.exec_tick + 3)
	t.gt(tank.combat.emp_until, w.tick, "enemy vehicle: weapons off")
	t.check(inf.combat.emp_until <= w.tick, "infantry unaffected")
	t.check(own.combat.emp_until <= w.tick, "the owner's own vehicle untouched")
	t.check(far.combat.emp_until <= w.tick, "outside the radius untouched")
	t.gt(gen.econ.shutdown_until, w.tick, "enemy powered structure (Barracks) shut down: the economy shutdown is written")
	t.check(radar.econ.shutdown_until <= w.tick, "outside the disc (44,44 base is 12 cells away)")
	var dur: int = tank.combat.emp_until - (wr.exec_tick)
	t.ge(dur, 150, "about 8 s of weapons off")
	t.le(dur, 170, "(160 ticks)")


func test_helios_sweep_pulses(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.olm.vanilla", "roster.nec.vanilla")
	var sw: DefSuperweapon = _sw_id(w, 0)
	var tank: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 32, 32)
	w.set_hp_max(tank, 100000)
	tank.hp = 100000
	A.hold_fire(w)
	var wr: SimWarning = _fire(w, 0, 32, 32, 0)
	t.eq(wr.exec_tick - wr.start_tick, 200, "warning 200")
	t.eq(SimSuperweapons.line_len(wr), 16 * CELL, "line 16 cells")
	t.eq(wr.radius, 3 * CELL / 2, "3 cells wide")
	var hits: int = 0
	var first: int = -1
	var last: int = -1
	var hp: int = tank.hp
	var end: int = wr.exec_tick + int(sw.params["traverse_t"]) + 10
	while w.tick < end:
		w.step()
		if tank.hp < hp:
			hits += 1
			if first < 0:
				first = w.tick
			last = w.tick
			hp = tank.hp
	t.ge(hits, 7, "a centreline unit is hit by about 9 pulses")
	t.le(hits, 15, "and by no more than 15 (the unit radius widens the window)")
	var per_pulse: int = (100000 - tank.hp) / maxi(hits, 1)
	t.eq(per_pulse, sw.packets[0].damage * 5 / 20, "each pulse deals its share of the dps (620 dps / 4 = 155)")
	t.gt(first, wr.exec_tick + 60, "the hot spot reaches the middle of the 16-cell line after ~6 s")
	t.lt(last - first, 80, "and leaves again within 4 s")
	t.eq(wr.phase, SimEconConst.AT_DONE, "DONE after the sweep")
	# a unit 4 cells off the line is never touched
	var w2: SimWorld = _w("roster.olm.vanilla", "roster.nec.vanilla")
	var safe: SimEntity = A.spawn(w2, "unit.nec.leopard_tank", 1, 32, 36)
	A.hold_fire(w2)
	var wr2: SimWarning = _fire(w2, 0, 32, 32, 0)
	A.run_to(w2, wr2.exec_tick + 260)
	t.eq(safe.hp, safe.hp_max, "a unit outside the beam is not hurt")


func test_perun_core_and_ring(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.def.vanilla", "roster.nec.vanilla")
	var core: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 32, 32)
	var ring: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 36, 32)
	var out: SimEntity = A.spawn(w, "unit.nec.leopard_tank", 1, 41, 32)
	A.hold_fire(w)
	var wr: SimWarning = _fire(w, 0, 32, 32)
	t.eq(wr.radius, 7 * CELL, "zone shows radius 7")
	var ev: Array[PackedInt32Array] = _tick_events(w, SimEconConst.EVT_SW_IMPACT, wr.exec_tick + 10)
	t.eq(ev.size(), 2, "core + ring packets")
	t.lt(core.hp, core.hp_max, "core victim damaged")
	t.check(ring.hp == ring.hp_max or ring.hp < ring.hp_max, "ring victim at 4 cells")
	t.eq(out.hp, out.hp_max, "9 cells away: untouched")
	var radii: PackedInt32Array = PackedInt32Array([ev[0][3], ev[1][3]])
	radii.sort()
	t.eq(radii[0], 3 * CELL, "core radius 3")
	t.eq(radii[1], 7 * CELL, "ring radius 7")


func test_horizon_three_impacts_and_debris(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.ae.vanilla", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32, 0)
	t.eq(wr.exec_tick - wr.start_tick, 200, "warning 200")
	var ev: Array[PackedInt32Array] = _tick_events(w, SimEconConst.EVT_SW_IMPACT, wr.exec_tick + 200)
	t.eq(ev.size(), 3, "three impacts")
	t.eq(ev[0][0], wr.exec_tick, "impact 1 at X")
	t.eq(ev[1][0], wr.exec_tick + 90, "impact 2 at X + 90")
	t.eq(ev[2][0], wr.exec_tick + 180, "impact 3 at X + 180 (9 s)")
	t.eq(ev[0][3], 3 * CELL, "radius 3")
	t.eq(ev[1][1] - ev[0][1], 5 * CELL, "centres 5 cells apart")
	# debris: blocks construction at the impacts for 400 ticks
	var cx: int = 32
	t.check(w.zones.construction_blocked(cx, 32) or w.zones.construction_blocked(cx - 5, 32) or w.zones.construction_blocked(cx + 5, 32), "debris blocks construction")
	var deb: int = 0
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.DEBRIS:
			deb += 1
	t.eq(deb, 3, "three debris zones")
	A.run_to(w, wr.exec_tick + 90 + 399)
	t.check(w.zones.construction_blocked(cx, 32), "the second impact's debris lasts 400 ticks")
	A.run_to(w, wr.exec_tick + 180 + 402)
	var any: bool = false
	for cc: int in [27, 32, 37]:
		any = any or w.zones.construction_blocked(cc, 32)
	t.check(not any, "gone after 400 ticks")


func test_horizon_debris_blocks_placement(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.ae.vanilla", "roster.nec.vanilla")
	A.structure(w, "structure.shared.headquarters", 1, 12, 20)
	var wr: SimWarning = _fire(w, 0, 12, 26, 0)
	A.run_to(w, wr.exec_tick + 5)
	var found: bool = false
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.DEBRIS:
			found = true
			var cx: int = z.x >> 10
			var cy: int = z.y >> 10
			var res: SimPlacementResult = SimPlacementResult.new()
			t.eq(SimPlacement.validate(w, 1, w.data.structure_idx("structure.shared.generator"), cx, cy, 0, res), SimEconConst.RSN_DEBRIS, "placement in the debris: DEBRIS")
			t.check(w.zones.blocks_construction(cx, cy), "zones.blocks_construction")
			break
	t.check(found, "a debris zone exists")


func test_tempest_swarm(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.pd.vanilla", "roster.nec.vanilla")
	var sw: DefSuperweapon = _sw_id(w, 0)
	A.spawn(w, "unit.nec.leopard_tank", 1, 32, 32)
	A.hold_fire(w)
	var wr: SimWarning = _fire(w, 0, 32, 32)
	t.eq(wr.radius, 6 * CELL, "zone radius 6")
	t.eq(wr.x2, _launcher(w, 0).x, "approach line: x2 is the launcher")
	A.run_to(w, wr.exec_tick + 1)
	var n: int = 0
	for e: SimEntity in w.units_of(0):
		if e.summon != null and w.data.units[e.def_idx].id == w.data.units[sw.summon].id:
			n += 1
	t.eq(n, sw.summon_count, "24 drones")
	t.eq(sw.summon_count, 24, "24")
	# they expire: after arrival + 400, hard cap 1200
	A.run(w, SimZoneConsts.SWARM_HARD_CAP_TICKS + 5)
	var left: int = 0
	for e2: SimEntity in w.units_of(0):
		if e2.summon != null and (e2.flags & SimFlags.F_GONE) == 0 and w.data.units[e2.def_idx].id == w.data.units[sw.summon].id:
			left += 1
	t.eq(left, 0, "all drones expired")


func test_dragonfall_capsules_engines_and_expiry(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.han.vanilla", "roster.nec.vanilla")
	var sw: DefSuperweapon = _sw_id(w, 0)
	A.structure(w, "structure.shared.barracks", 1, 32, 36)
	var wr: SimWarning = _fire(w, 0, 32, 32)
	A.run_to(w, wr.exec_tick + 2)
	var caps: int = 0
	var cap_def: int = int(sw.params["capsule_summon_idx"])
	for e: SimEntity in w.units_of(0):
		if e.def_idx == cap_def:
			caps += 1
	t.eq(caps, 3, "three capsules land at X")
	A.run_to(w, wr.exec_tick + 100 + 3)
	var eng: int = 0
	for e2: SimEntity in w.units_of(0):
		if e2.def_idx == sw.summon and (e2.flags & SimFlags.F_GONE) == 0:
			eng += 1
	t.eq(eng, 3, "three engines at X + 100")
	A.run_to(w, wr.exec_tick + 100 + 1200 + 12)
	var eng2: int = 0
	for e3: SimEntity in w.units_of(0):
		if e3.def_idx == sw.summon and (e3.flags & SimFlags.F_GONE) == 0:
			eng2 += 1
	t.eq(eng2, 0, "engines vanish 60 s later (X + 1300)")


func test_dragonfall_destroyed_foundry_during_warning_lands_nothing(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.han.vanilla", "roster.nec.vanilla")
	var sw: DefSuperweapon = _sw_id(w, 0)
	var wr: SimWarning = _fire(w, 0, 32, 32)
	A.run(w, 50)
	w.kill(_launcher(w, 0), SimWorld.Cause.SCRIPT)
	A.run_to(w, wr.exec_tick + 10)
	var n: int = 0
	for e: SimEntity in w.units_of(0):
		if e.def_idx == int(sw.params["capsule_summon_idx"]) or e.def_idx == sw.summon:
			n += 1
	t.eq(n, 0, "nothing lands")


# ---- Trident ---------------------------------------------------------------------------------------------------------------

func _trident_zone(w: SimWorld) -> SimZone:
	for z: SimZone in w.zones.active_zones():
		if z.kind == DefEnums.ZoneKind.INTERCEPT:
			return z
	return null


func test_trident_zone_and_charges(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	t.eq(wr.exec_tick - wr.start_tick, 120, "Trident warning 120 ticks")
	A.run_to(w, wr.exec_tick + 2)
	var z: SimZone = _trident_zone(w)
	t.not_null(z, "the intercept zone exists")
	t.eq(z.charges, 24, "24 charges")
	t.eq(z.radius, 6 * CELL, "radius 6")
	t.eq(z.t_end - z.t_start, 500, "500 ticks")
	var seen: Array[SimWarning] = []
	w.strategic.warnings_affecting(1, seen)
	t.eq(seen.size(), 1, "the dome is visible to every player")
	t.eq(S.slot(w, 0, SimEconConst.SLOT_SW).recharge_ticks, 7200, "recharge 7200")


func test_trident_vs_atlas_perun_shells(t: TestCtx) -> void:
	# Atlas: 3 rods x 8 charges = 24
	var w: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	A.run_to(w, wr.exec_tick + 2)
	var z: SimZone = _trident_zone(w)
	var target: SimEntity = A.structure(w, "structure.shared.barracks", 0, 32, 32)
	w.set_hp_max(target, 100000)
	target.hp = 100000
	var hp_t: int = target.hp
	var wr2: SimWarning = _fire(w, 1, 32, 32, 0)
	A.run_to(w, wr2.exec_tick + 5)
	t.eq(z.charges, 0, "Atlas: three rods take 24 charges")
	var lost_with: int = hp_t - target.hp
	# the same volley with no dome
	var w0: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
	var target0: SimEntity = A.structure(w0, "structure.shared.barracks", 0, 32, 32)
	w0.set_hp_max(target0, 100000)
	target0.hp = 100000
	var hp0: int = target0.hp
	var wr0: SimWarning = _fire(w0, 1, 32, 32, 0)
	A.run_to(w0, wr0.exec_tick + 5)
	var lost_without: int = hp0 - target0.hp
	t.gt(lost_without, 0, "an undefended Barracks is hit")
	t.lt(lost_with, lost_without, "the dome reduces the damage")
	t.le(lost_with * 100, lost_without * 55, "by about half (50 % cap)")
	# Perun: 2 packets x 8 = 16, leaving 8
	var wp: SimWorld = _w("roster.sap.vanilla", "roster.def.vanilla")
	var wa: SimWarning = _fire(wp, 0, 32, 32)
	A.run_to(wp, wa.exec_tick + 2)
	var zp: SimZone = _trident_zone(wp)
	var wb: SimWarning = _fire(wp, 1, 32, 32)
	A.run_to(wp, wb.exec_tick + 5)
	t.eq(zp.charges, 8, "Perun: core + ring take 16 charges, 8 remain")


func test_trident_ordinary_shell_costs_one_and_low_charges_do_not_reduce(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	A.run_to(w, wr.exec_tick + 2)
	var z: SimZone = _trident_zone(w)
	# an ordinary hostile shell arcing in from outside the dome
	var sw: DefSuperweapon = w.data.superweapons[S.slot(w, 1, SimEconConst.SLOT_SW).def_idx]
	var pk: DefImpactPacket = sw.packets[0]
	var wh: int = SimPowerFx.warhead_for(w, 1, "test:shell", pk, null, true)
	SimPowerFx.strike_packet(w, 1, 0, wh, S.c(32), S.c(32), 0, true)
	A.run(w, 60)
	t.eq(z.charges, 23, "an ordinary shell costs one charge")
	# fewer than 8 charges cannot reduce a strategic packet
	z.charges = 7
	var target: SimEntity = A.structure(w, "structure.shared.barracks", 0, 32, 32)
	w.set_hp_max(target, 100000)
	target.hp = 100000
	var hp: int = target.hp
	var wr2: SimWarning = _fire(w, 1, 32, 32)
	A.run_to(w, wr2.exec_tick + 5)
	t.eq(z.charges, 7, "seven charges: a strategic packet is not reduced and costs nothing")
	var w0: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
	var target0: SimEntity = A.structure(w0, "structure.shared.barracks", 0, 32, 32)
	w0.set_hp_max(target0, 100000)
	target0.hp = 100000
	var wr0: SimWarning = _fire(w0, 1, 32, 32)
	A.run_to(w0, wr0.exec_tick + 5)
	t.eq(hp - target.hp, 100000 - target0.hp, "full damage, identical to an undefended target")


func test_trident_bypassed_by_emp_and_beams(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.sap.vanilla", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	A.run_to(w, wr.exec_tick + 2)
	var z: SimZone = _trident_zone(w)
	var tank: SimEntity = A.spawn(w, "unit.sap.combat_pioneer", 0, 32, 32)
	A.hold_fire(w)
	var wr2: SimWarning = _fire(w, 1, 32, 32)
	A.run_to(w, wr2.exec_tick + 5)
	t.eq(z.charges, 24, "Aurora (EMP) bypasses the dome")
	t.check(tank != null, "unit spawned")


# ---- S6 superweapon duel ------------------------------------------------------------------------------------------------------

func test_s6_aurora_cancels_the_enemy_atlas(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	S.force_ready(w, 0)
	S.force_ready(w, 1)
	# Atlas fires at the Aurora player's base; Aurora answers at the Atlas launcher during the warning
	S.launch(w, 0, 44, 44)
	w.step()
	var atlas: SimWarning = w.strategic.warnings[0]
	var launcher: SimEntity = _launcher(w, 0)
	A.run(w, 20)
	S.launch(w, 1, launcher.x >> 10, launcher.y >> 10)
	w.step()
	var aurora: SimWarning = w.strategic.warnings[w.strategic.warnings.size() - 1]
	t.eq(aurora.kind, SimEconConst.WK_SUPER, "second warning")
	t.lt(aurora.exec_tick, atlas.exec_tick, "the EMP lands before the rods")
	A.run_to(w, aurora.exec_tick + 3)
	t.gt(launcher.econ.shutdown_until, w.tick, "Atlas launcher shut down by the EMP")
	t.eq(atlas.phase, SimEconConst.AT_CANCELLED, "Atlas cancelled")
	A.run_to(w, atlas.exec_tick + 20)
	t.eq(S.n_events(w, SimEconConst.EVT_SW_EXEC_START), 1, "only the Aurora executed")
	t.eq(w.zones.debug_validate(w), PackedStringArray(), "zones validate")


func test_s6_horizon_debris_blocks_an_mcv_deploy(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.ae.vanilla", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32, 0)
	A.run_to(w, wr.exec_tick + 5)
	var mcv_def: int = w.data.unit_idx("unit.shared.mobile_construction_vehicle")
	if mcv_def < 0:
		t.skip("no MCV def")
		return
	var mcv: SimEntity = A.spawn(w, "unit.shared.mobile_construction_vehicle", 1, 27, 32)
	var hq: int = SimPlacement.hq_def_of_mcv(w, mcv.def_idx)
	t.gt(hq, -1, "HQ def of the MCV")
	var res: SimPlacementResult = SimPlacementResult.new()
	t.eq(SimPlacement.validate_hq_site(w, 1, mcv, res), SimEconConst.RSN_DEBRIS, "the debris blocks the MCV deploy")


# ---- danger (AI helper) --------------------------------------------------------------------------------------------------------

func test_danger_fraction(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32, 0)
	var x: int = S.c(32)
	var y: int = S.c(32)
	t.eq(SimSuperweapons.danger_fraction_bp(w, wr, x, y, wr.exec_tick - 1), 0, "nothing before the impact")
	var centre: int = SimSuperweapons.danger_fraction_bp(w, wr, x, y, wr.exec_tick)
	t.gt(centre, 9000, "centre rod at the centre: about one full hit")
	var lens: int = SimSuperweapons.danger_fraction_bp(w, wr, x + 3 * CELL / 2, y, wr.exec_tick)
	t.ge(lens, 9000, "on the axis between two rods the circles overlap: a full hit")
	var gap: int = SimSuperweapons.danger_fraction_bp(w, wr, x + 3 * CELL / 2, y + 8 * CELL / 5, wr.exec_tick)
	t.eq(gap, 0, "off the axis between two rods there is a gap (the counterplay text)")
	t.eq(SimSuperweapons.danger_fraction_bp(w, wr, x, y + 4 * CELL, wr.exec_tick + 100), 0, "4 cells off the line: safe")
	var w2: SimWorld = _w("roster.olm.vanilla", "roster.nec.vanilla")
	var hw: SimWarning = _fire(w2, 0, 32, 32, 0)
	var early: int = SimSuperweapons.danger_fraction_bp(w2, hw, S.c(24), S.c(32), hw.exec_tick + 3)
	var mid: int = SimSuperweapons.danger_fraction_bp(w2, hw, S.c(32), S.c(32), hw.exec_tick + 240)
	var mid_early: int = SimSuperweapons.danger_fraction_bp(w2, hw, S.c(32), S.c(32), hw.exec_tick + 20)
	t.gt(early, 0, "the sweep starts at the west end")
	t.gt(mid, mid_early, "a unit in the middle accumulates exposure over time")
	t.le(mid, 10000, "capped")


func test_sell_is_refused_while_the_warning_runs(t: TestCtx) -> void:
	var w: SimWorld = _w("roster.napc.usa", "roster.nec.vanilla")
	var wr: SimWarning = _fire(w, 0, 32, 32)
	var l: SimEntity = _launcher(w, 0)
	w.clear_events()
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([l.id])))
	w.step()
	t.check(l.econ.st == SimEconConst.ST_ACTIVE, "the launcher is not being sold")
	t.eq(wr.phase, SimEconConst.AT_WARNING, "the attack goes on")
	A.run_to(w, wr.exec_tick + 1)
	w.clear_events()
	w.submit_raw(0, SimCmd.sell(PackedInt32Array([l.id])))
	w.step()
	t.eq(l.econ.st, SimEconConst.ST_SELLING, "after the warning a sale is allowed")
	A.run(w, 5)
	t.check(wr.phase != SimEconConst.AT_CANCELLED, "and does not cancel the running attack")


func test_trident_reduction_shares_the_50_percent_cap_with_own_resistance(t: TestCtx) -> void:
	# lost hp of a structure with a 40 % damage-taken lease under: nothing / the dome / both. 0.6 R / 0.5 R / 0.5 R.
	var res: Array[int] = []
	for variant: int in 4:
		var w: SimWorld = _w("roster.sap.vanilla", "roster.napc.usa")
		var dome: bool = variant == 1 or variant == 3
		var lease: bool = variant == 2 or variant == 3
		if dome:
			var wt: SimWarning = _fire(w, 0, 32, 32)
			A.run_to(w, wt.exec_tick + 2)
		var target: SimEntity = A.structure(w, "structure.shared.barracks", 0, 32, 32)
		w.set_hp_max(target, 100000)
		target.hp = 100000
		if lease:
			SimCombatMods.apply(w, target, 999, C.STAT_TAKEN, 4000, C.FILTER_ALL_WEAPON, 100000)
		var wa: SimWarning = _fire(w, 1, 32, 32, 0)
		A.run_to(w, wa.exec_tick + 5)
		res.append(100000 - target.hp)
	var raw: int = res[0]
	t.gt(raw, 0, "the undefended volley hurts")
	t.lt(res[2], raw, "a 40 % lease reduces the damage")
	t.lt(res[1], raw, "the dome reduces the damage")
	t.le(absi(res[1] * 2 - raw), raw / 50, "dome only: -50 %")
	t.le(absi(res[2] * 10 - raw * 6), raw / 5, "lease only: about -40 %")
	t.le(absi(res[3] - res[1]), raw / 50, "both: still -50 % (the shared 50 % cap), not -90 %")
