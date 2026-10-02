class_name StratKit
extends RefCounted
## Helpers of the strategic-framework tests (EC3B): worlds on the REAL data with a powered base (generators, Radar,
## Laboratory, optional launcher) for chosen players, commands by SimCmd builders, and event / warning readers.

const A := preload("res://tests/support/ab2_kit.gd")
const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const CELL: int = 1024


static func c(cell: int) -> int:
	return cell * CELL + CELL / 2


## Powered base of player `pid` around (bx, by): 6 generators, Radar, Laboratory (+ the launcher of the roster's superweapon).
static func base(w: SimWorld, pid: int, bx: int, by: int, with_launcher: bool = true, lab: bool = true, settle: bool = true) -> void:
	for i: int in 6:
		A.structure(w, "structure.shared.generator", pid, bx + 3 * (i % 3), by + 3 * (i / 3))
	A.structure(w, "structure.shared.radar", pid, bx, by + 7)
	if lab:
		A.structure(w, "structure.shared.laboratory", pid, bx + 4, by + 7)
	if with_launcher and w.players[pid].econ.slots[SimEconConst.SLOT_SW].def_idx >= 0:
		var sw: DefSuperweapon = w.data.superweapons[w.players[pid].econ.slots[SimEconConst.SLOT_SW].def_idx]
		A.structure(w, w.data.structures[sw.launcher].id, pid, bx + 9, by + 3)
	w.players[pid].credits = 20000
	if settle:
		w.step()


static func power_idx(w: SimWorld, id: String) -> int:
	return w.data.power_idx(id)


static func sw_idx(w: SimWorld, id: String) -> int:
	for i: int in w.data.superweapons.size():
		if w.data.superweapons[i].id == id:
			return i
	return -1


static func use(w: SimWorld, pid: int, p_idx: int, cx: int, cy: int, angle: int = 0, target: int = 0) -> void:
	w.submit_raw(pid, SimCmd.use_power(p_idx, c(cx), c(cy), angle, target))


static func launch(w: SimWorld, pid: int, cx: int, cy: int, angle: int = 0) -> void:
	w.submit_raw(pid, SimCmd.launch_superweapon(c(cx), c(cy), angle))


static func slot(w: SimWorld, pid: int, s: int) -> SimPowerSlot:
	return w.players[pid].econ.slots[s]


## Steps until the slot-3 state of pid is READY (or `max_ticks`); returns the ticks it took.
static func charge_up(w: SimWorld, pid: int, max_ticks: int) -> int:
	var t0: int = w.tick
	while w.tick - t0 < max_ticks and slot(w, pid, SimEconConst.SLOT_SW).sw_state != SimEconConst.SW_READY:
		w.step()
	return w.tick - t0


## Fast-forward: the slot is charged (skips the 9600 ticks; every other rule is unchanged).
static func force_ready(w: SimWorld, pid: int) -> void:
	var s: SimPowerSlot = slot(w, pid, SimEconConst.SLOT_SW)
	s.charge = s.recharge_ticks
	s.sw_state = SimEconConst.SW_READY


## Number of events of `type` since the buffer was last cleared.
static func n_events(w: SimWorld, type: int) -> int:
	return A.count_events(w, type)


## Per kind, the effect the bible states, read from sim state after the power ran; "" = measured.
static func kind_effect(w: SimWorld, p: DefPower, pi: int) -> String:
	var k: int = SimStrategicEffects.kind_of(w, p)
	var zones: int = 0
	for z: SimZone in w.zones.active_zones():
		if z.power_idx == pi:
			zones += 1
	match k:
		SimEconConst.EK_BUFF:
			return "" if A.event_field(w, K.EV_BUFF_APPLIED, 0, SimEvent.I_C) > 0 or zones > 0 else "nothing buffed"
		SimEconConst.EK_WINDOW, SimEconConst.EK_STRUCT_BUFF:
			return "" if w.strategic.window_active(w, 0, pi) else "no window"
		SimEconConst.EK_BOMBARD:
			return "" if w.combat.proj.live_count() > 0 else "no shells"
		SimEconConst.EK_MARK:
			return "" if A.count_events(w, K.EV_MARKED) > 0 else "no artillery marked"
		SimEconConst.EK_RECON_SUMMON:
			return "" if w.zones.sum_ids.size() > 0 else "no aircraft"
		SimEconConst.EK_DECOY:
			return "" if w.zones.sum_ids.size() > 0 else "no decoys"
	return "" if zones > 0 or w.zones.sum_ids.size() > 0 else "no zone"
