class_name StratScenario
extends RefCounted
## The composite strategic scenario of task EC3B (determinism D1/D2/D3 of economy 10.3, S6/S8 flavour): 8 players, all eight
## factions on the REAL data, 4 v 4, a powered base with launcher each, small armies, every superweapon fired (Trident first,
## so Atlas / Perun / Horizon meet its dome), every player's three support powers, EMP on launchers during warnings.
## Everything after `build()` goes through commands, so a recorded SimCommandLog replays it exactly.
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_strategic.gd

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const TICKS: int = 1900
const ROSTERS: Array[String] = [
	"roster.napc.usa", "roster.nec.vanilla", "roster.olm.vanilla", "roster.def.vanilla",
	"roster.pd.vanilla", "roster.han.vanilla", "roster.ae.vanilla", "roster.sap.vanilla",
]
## superweapon launches: [tick, pid, target_x, target_y, angle]. Team A (pids 0-3) fires at team B's army column (x 46-48), team B at
## team A's (x 21-23). Trident (pid 7) goes up first over B's column; the Aurora (pid 1) is aimed at B's Horizon launcher so that
## it lands (tick 260) inside Horizon's warning (150 -> 350) and cancels it (S6).
const LAUNCHES: Array = [
	[30, 7, 48, 24, 0],  # Trident over B's column
	[60, 0, 48, 24, 0],  # Atlas: meets the dome
	[80, 3, 48, 24, 0],  # Perun: meets the dome
	[100, 1, 61, 39, 0],  # Aurora at the Horizon launcher
	[130, 2, 48, 24, 1024],  # Helios, north-south
	[150, 6, 22, 24, 0],  # Horizon: cancelled by the EMP
	[170, 4, 22, 40, 0],  # Tempest
	[190, 5, 22, 24, 0],  # Dragonfall
]


static func c(cell: int) -> int:
	return cell * 1024 + 512


static func build() -> SimWorld:
	var rows: PackedStringArray = A.MV.grid(72)
	var w: SimWorld = A.world({"rosters": ROSTERS, "teams": [1, 1, 1, 1, 2, 2, 2, 2], "rows": rows, "seed": 77, "movement": true, "invariants_every": 25,
		"rules": {"fog": false}})
	for pid: int in 8:
		var bx: int = 6 if pid < 4 else 52
		var by: int = 4 + 16 * (pid % 4)
		S.base(w, pid, bx, by, true, true, false)
		if pid == 0:
			A.structure(w, "structure.shared.airfield", 0, 28, 14)  # Rapid Turnaround's chosen structure
		_army(w, pid, bx + 15 if pid < 4 else bx - 6, by + 4)
	w.step()  # launchers are noticed by the strategic step
	for pid2: int in 8:
		S.force_ready(w, pid2)
	return w


static func _army(w: SimWorld, pid: int, cx: int, cy: int) -> void:
	var d: GameData = w.data
	var n: int = 0
	for u: DefUnit in d.units:
		if n >= 5:
			break
		if u.cost > 0 and not u.id.begins_with("summon.") and not u.id.begins_with("unit.drone") and w.players[pid].roster.has_unit(u.index) \
				and u.home_layer == SimEntity.Layer.GROUND and u.id.begins_with("unit.%s." % d.factions[w.players[pid].faction_idx].id.split(".")[-1]):
			A.spawn(w, u.id, pid, cx + n % 3, cy + n / 3)
			n += 1
	A.hold_fire(w)


## Commands of step `s` through `cmd_log` (a SimCommandLog) or straight into the world when cmd_log is null.
static func script(w: SimWorld, s: int, cmd_log: SimCommandLog = null) -> void:
	var d: GameData = w.data
	if s == 3:
		for pid: int in 8:
			var enemy_x: int = 58 if pid < 4 else 14
			for slot: int in 3:
				var p_idx: int = w.players[pid].econ.slots[slot].def_idx
				var p: DefPower = d.powers[p_idx]
				var k: int = SimStrategicEffects.kind_of(w, p)
				var hostile: bool = k == SimEconConst.EK_BOMBARD or k == SimEconConst.EK_MARK
				var tx: int = enemy_x if hostile else (21 if pid < 4 else 46)
				var ty: int = (40 if hostile else 8 + 16 * (pid % 4) + 4)
				var target: int = 0
				if p.params.has("target_structure_idx"):
					for e: SimEntity in w.structures_of(pid):
						if (p.params["target_structure_idx"] as PackedInt32Array).has(e.def_idx):
							target = e.id
				_send(w, cmd_log, pid, SimCmd.use_power(p_idx, c(tx), c(ty), (slot * 700) & 4095, target))
	for l: Array in LAUNCHES:
		if int(l[0]) == s:
			var pid2: int = int(l[1])
			_send(w, cmd_log, pid2, SimCmd.launch_superweapon(c(int(l[2])), c(int(l[3])), int(l[4])))


static func _send(w: SimWorld, cmd_log: SimCommandLog, pid: int, ints: PackedInt32Array) -> void:
	if cmd_log != null:
		cmd_log.submit(w, pid, ints)
	else:
		w.submit_raw(pid, ints)


static func run_chain(cmd_log: SimCommandLog = null) -> PackedInt64Array:
	var w: SimWorld = build()
	for s: int in TICKS:
		script(w, s, cmd_log)
		w.step()
	var out: PackedInt64Array = w.checksum_log.duplicate()
	out.append(w.checksum())
	out.append(w.events.digest())
	out.append(Checksum.fnv_string(w.dump_state()))
	return out


## Number of events of each type in the world's buffer accumulated by `run_counting` (below).
static func run_counting(cmd_log: SimCommandLog = null) -> Dictionary:
	var w: SimWorld = build()
	var cov: Dictionary = {}
	for s: int in TICKS:
		script(w, s, cmd_log)
		w.step()
		var dd: PackedInt32Array = w.events.data
		for i: int in dd.size() / SimEvent.STRIDE:
			var ty: int = dd[i * SimEvent.STRIDE + SimEvent.I_TYPE]
			cov[ty] = int(cov.get(ty, 0)) + 1
		w.clear_events()
	cov["_final"] = w.checksum()
	cov["_world"] = w
	return cov
