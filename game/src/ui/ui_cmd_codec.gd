class_name UiCmdCodec
extends RefCounted
## The ONLY file that names sim ops for the UI (ui.md 6.1): one static builder per UI action, each calling the
## `SimCmd` builder of the same name and returning the `PackedInt32Array` that net carries ([op, fields..., ids...],
## no pid). `queued` (Shift or the W latch) sets mode = QM_APPEND on the ops the catalog flags M_QUEUE and is ignored
## on the others. `describe()` renders a command for test goldens and logs.

enum Queue { REPLACE = 0, APPEND = 1 }  ## = SimOrder.QM_*; QM_FRONT is never produced by the UI
enum Hold { PRODUCER = 0, CONSTRUCTION = 1, RESEARCH = 2 }  ## which hold op a queue kind maps to
const MAX_IDS: int = 512  ## id-list cap of an M_IDS op (sim_core 4.8)
const FLAG_FORCED: int = 1  ## ATTACK flags bit0
const FLAG_CLEAR: int = 1  ## SET_RALLY flags bit0
const MF_SPEED_MATCH: int = 2  ## MOVE / ATTACK_MOVE / PATROL flags b1
const MF_REVERSE: int = 4  ## b2

## Field names by FT_* (SimCmd.FT_TARGET ... FT_ANGLE) for describe().
const _FT_NAMES: PackedStringArray = ["target", "x", "y", "def", "count", "mode", "flags", "angle"]

## Ops the UI builds -> wire field count (for verify_against_sim) and whether they carry ids.
const _ASSUMED: Dictionary = {
	1: [4, true], 2: [0, true], 3: [0, true], 4: [4, true], 5: [2, true], 6: [2, true], 7: [2, true], 8: [2, true],
	9: [2, true], 10: [4, true], 11: [2, true], 12: [2, true], 40: [3, true], 41: [4, true], 42: [4, true],
	43: [0, true], 44: [4, true], 45: [1, true], 46: [0, true], 47: [2, true], 100: [1, true], 101: [1, true],
	102: [2, true], 103: [5, true], 104: [2, true], 105: [4, true], 120: [2, false], 121: [1, false], 122: [1, false],
	123: [4, false], 124: [3, false], 125: [2, false], 126: [1, true], 127: [4, true], 128: [1, false],
	129: [1, false], 130: [1, false], 131: [1, false], 132: [0, true], 133: [1, true], 134: [0, true],
	140: [5, false], 141: [3, false],
}


## QM_APPEND when `queued` and the op is flagged M_QUEUE, else QM_REPLACE.
static func queue_mode(op: int, queued: bool) -> int:
	if queued and (SimCmd.meta_of(op) & SimCmd.M_QUEUE) != 0:
		return Queue.APPEND
	return Queue.REPLACE


# ---- unit orders (flagged Q take `queued`) ---------------------------------------------------------------------------
static func move(ids: PackedInt32Array, x: int, y: int, queued: bool, flags: int = 0) -> PackedInt32Array:
	return SimCmd.move(ids, x, y, queue_mode(SimCmd.MOVE, queued), flags)


static func stop(ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.stop(ids)


static func scatter(ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.scatter(ids)


static func patrol(ids: PackedInt32Array, x: int, y: int, queued: bool, flags: int = 0) -> PackedInt32Array:
	return SimCmd.patrol(ids, x, y, queue_mode(SimCmd.PATROL, queued), flags)


static func load_units(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.load(ids, target, queue_mode(SimCmd.LOAD, queued))


static func garrison(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.garrison(ids, target, queue_mode(SimCmd.GARRISON, queued))


static func capture(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.capture(ids, target, queue_mode(SimCmd.CAPTURE, queued))


static func repair(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.repair(ids, target, queue_mode(SimCmd.REPAIR, queued))


static func salvage(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.salvage(ids, target, queue_mode(SimCmd.SALVAGE, queued))


## HARVEST target 0 at the deposit cell's centre (the sim takes the deposit cell nearest to x, y).
static func harvest(ids: PackedInt32Array, x: int, y: int, queued: bool) -> PackedInt32Array:
	return SimCmd.harvest(ids, 0, x, y, queue_mode(SimCmd.HARVEST, queued))


## RETURN_CARGO: target = refinery, 0 = nearest.
static func return_cargo(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.return_cargo(ids, target, queue_mode(SimCmd.RETURN_CARGO, queued))


static func follow(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.follow(ids, target, queue_mode(SimCmd.FOLLOW, queued))


## ATTACK; `forced` sets flags bit0 (target is own / allied / neutral).
static func attack(ids: PackedInt32Array, target: int, queued: bool, forced: bool = false) -> PackedInt32Array:
	return SimCmd.attack(ids, target, queue_mode(SimCmd.ATTACK, queued), FLAG_FORCED if forced else 0)


static func attack_move(ids: PackedInt32Array, x: int, y: int, queued: bool, flags: int = 0) -> PackedInt32Array:
	return SimCmd.attack_move(ids, x, y, queue_mode(SimCmd.ATTACK_MOVE, queued), flags)


## GUARD: target 0 guards the point (x, y).
static func guard(ids: PackedInt32Array, target: int, x: int, y: int, queued: bool) -> PackedInt32Array:
	return SimCmd.guard(ids, target, x, y, queue_mode(SimCmd.GUARD, queued))


static func hold(ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.hold(ids)


## FORCE_FIRE has no queue mode. target 0 = ground point; count 0 = until replaced.
static func force_fire(ids: PackedInt32Array, target: int, x: int, y: int, count: int = 0) -> PackedInt32Array:
	return SimCmd.force_fire(ids, target, x, y, count)


## 0 aggressive, 1 defensive, 2 hold fire, 3 guard.
static func set_stance(ids: PackedInt32Array, stance: int) -> PackedInt32Array:
	return SimCmd.set_stance(ids, stance)


static func scuttle(ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.scuttle(ids)


## RETURN_TO_BASE: target = the clicked airfield / carrier, 0 = nearest free pad or the carrier.
static func return_to_base(ids: PackedInt32Array, target: int, queued: bool) -> PackedInt32Array:
	return SimCmd.return_to_base(ids, target, queue_mode(SimCmd.RETURN_TO_BASE, queued))


# ---- abilities -------------------------------------------------------------------------------------------------------
## DEPLOY: def -1 = the unit's deploy ability (an MCV becomes T_DEPLOY_MCV in the sim).
static func deploy(ids: PackedInt32Array, slot: int = -1) -> PackedInt32Array:
	return SimCmd.deploy(ids, slot)


static func undeploy(ids: PackedInt32Array, slot: int = -1) -> PackedInt32Array:
	return SimCmd.undeploy(ids, slot)


## SET_MODE with an explicit target mode index (never -1 = cycle).
static func set_mode(ids: PackedInt32Array, slot: int, mode: int) -> PackedInt32Array:
	return SimCmd.set_mode(ids, slot, mode)


## USE_ABILITY op 0 (start); x, y -1 = none.
static func use_ability(ids: PackedInt32Array, slot: int, target: int = 0, x: int = -1, y: int = -1) -> PackedInt32Array:
	return SimCmd.use_ability(ids, slot, 0, target, x, y)


## USE_ABILITY op 1 (cancel).
static func cancel_ability(ids: PackedInt32Array, slot: int) -> PackedInt32Array:
	return SimCmd.use_ability(ids, slot, 1, 0, -1, -1)


static func set_autocast(ids: PackedInt32Array, slot: int, on: bool) -> PackedInt32Array:
	return SimCmd.set_autocast(ids, slot, 1 if on else 0)


## UNLOAD: mode 0 all cargo / 1 one passenger (target); (x, y) = the drop point inside the map (the carrier's own position).
static func unload(carrier_ids: PackedInt32Array, all: bool, passenger: int, x: int, y: int) -> PackedInt32Array:
	return SimCmd.unload(carrier_ids, 0 if all else 1, passenger, x, y)


# ---- economy ---------------------------------------------------------------------------------------------------------
static func build_start(struct_def: int, count: int = 1) -> PackedInt32Array:
	return SimCmd.build_start(struct_def, count)


static func build_cancel(queue_index: int) -> PackedInt32Array:
	return SimCmd.build_cancel(queue_index)


## BUILD_PLACE: (cx, cy) = top-left CELL (whole cells), rot 0-3 clockwise quarter turns.
static func build_place(struct_def: int, cx: int, cy: int, rot: int = 0) -> PackedInt32Array:
	return SimCmd.build_place(struct_def, cx, cy, rot)


static func train(producer: int, unit_def: int, count: int = 1) -> PackedInt32Array:
	return SimCmd.train(producer, unit_def, count)


static func train_cancel(producer: int, queue_index: int) -> PackedInt32Array:
	return SimCmd.train_cancel(producer, queue_index)


## Hold / resume a queue: PRODUCER -> QUEUE_HOLD (ids = producers), CONSTRUCTION -> BUILD_HOLD, RESEARCH -> RESEARCH_HOLD.
static func queue_hold(which: int, producer_ids: PackedInt32Array, hold_on: bool) -> PackedInt32Array:
	var m: int = 1 if hold_on else 0
	match which:
		Hold.CONSTRUCTION:
			return SimCmd.build_hold(m)
		Hold.RESEARCH:
			return SimCmd.research_hold(m)
	return SimCmd.queue_hold(producer_ids, m)


## SET_RALLY: mode 0 set, `clear` sets flags bit0.
static func set_rally(producer_ids: PackedInt32Array, x: int, y: int, target: int = 0, clear: bool = false) -> PackedInt32Array:
	return SimCmd.set_rally(producer_ids, x, y, target, FLAG_CLEAR if clear else 0)


static func set_primary(producer: int) -> PackedInt32Array:
	return SimCmd.set_primary(producer)


static func research(res_def: int) -> PackedInt32Array:
	return SimCmd.research(res_def)


static func research_cancel(queue_index: int) -> PackedInt32Array:
	return SimCmd.research_cancel(queue_index)


static func sell(struct_ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.sell(struct_ids)


## SET_STRUCT_REPAIR mode: 0 off / 1 on / 2 toggle.
static func set_struct_repair(struct_ids: PackedInt32Array, mode: int) -> PackedInt32Array:
	return SimCmd.set_struct_repair(struct_ids, mode)


static func undeploy_hq(hq_ids: PackedInt32Array) -> PackedInt32Array:
	return SimCmd.undeploy_hq(hq_ids)


## USE_POWER: `power_idx` is the roster's power index (the sim derives the slot); angle 0-4095.
static func use_power(power_idx: int, x: int, y: int, angle: int, target: int = 0) -> PackedInt32Array:
	return SimCmd.use_power(power_idx, x, y, angle, target)


static func launch_superweapon(x: int, y: int, angle: int) -> PackedInt32Array:
	return SimCmd.launch_superweapon(x, y, angle)


# ---- helpers ---------------------------------------------------------------------------------------------------------
## Ascending chunks of at most `max_ids` (a guard only: MAX_SELECT keeps every user action in one chunk).
static func split_ids(ids: PackedInt32Array, max_ids: int = MAX_IDS) -> Array[PackedInt32Array]:
	var s: PackedInt32Array = ids.duplicate()
	s.sort()
	var out: Array[PackedInt32Array] = []
	var i: int = 0
	while i < s.size():
		out.append(s.slice(i, mini(i + max_ids, s.size())))
		i += max_ids
	return out


## The single float -> int step (5.8.2): world metres to sim units, clamped inside the map.
static func world_to_sim(wx: float, wz: float, map_w_cells: int, map_h_cells: int) -> Vector2i:
	return Vector2i(
		clampi(roundi(wx * 1024.0 / 3.0), 0, map_w_cells * 1024 - 1),
		clampi(roundi(wz * 1024.0 / 3.0), 0, map_h_cells * 1024 - 1))


## Minimap: normalised (0..1) to sim units, clamped.
static func norm_to_sim(nx: float, ny: float, map_w_cells: int, map_h_cells: int) -> Vector2i:
	return Vector2i(
		clampi(roundi(nx * map_w_cells * 1024.0), 0, map_w_cells * 1024 - 1),
		clampi(roundi(ny * map_h_cells * 1024.0), 0, map_h_cells * 1024 - 1))


## Binary angle 0..4095 of a direction (0 = +x east, increasing toward +y south), for line powers.
static func angle_of(dx: float, dy: float) -> int:
	var a: int = roundi(atan2(dy, dx) * 4096.0 / TAU)
	return posmod(a, 4096)


## Cell centre in sim units.
static func cell_center(c: int) -> int:
	return c * 1024 + 512


## "MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=0": op name, ids (M_IDS ops), then the op's fields in wire order.
static func describe(cmd: PackedInt32Array) -> String:
	if cmd.is_empty():
		return "EMPTY"
	var op: int = cmd[0]
	if not SimCmd.is_known(op):
		return "OP%d raw=%s" % [op, cmd]
	var lay: PackedInt32Array = SimCmd.layout_of(op)
	var parts: PackedStringArray = PackedStringArray([SimCmd.name_of(op)])
	var has_ids: bool = (SimCmd.meta_of(op) & SimCmd.M_IDS) != 0
	var first_id: int = 1 + lay.size()
	if has_ids:
		var ids: PackedStringArray = PackedStringArray()
		for i: int in range(first_id, cmd.size()):
			ids.append(str(cmd[i]))
		parts.append("ids=[%s]" % ",".join(ids))
	for i: int in lay.size():
		var v: int = cmd[1 + i] if 1 + i < cmd.size() else 0
		parts.append("%s=%d" % [_FT_NAMES[lay[i]], v])
	return " ".join(parts)


## Contract check: every op the UI builds is known and its wire arity / id flag equal the one assumed here.
static func verify_against_sim() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	for op: int in _ASSUMED:
		var row: Array = _ASSUMED[op]
		if not SimCmd.is_known(op):
			problems.append("op %d unknown to SimCmd" % op)
			continue
		if SimCmd.layout_of(op).size() != int(row[0]):
			problems.append("%s: layout %d != assumed %d" % [SimCmd.name_of(op), SimCmd.layout_of(op).size(), int(row[0])])
		var has_ids: bool = (SimCmd.meta_of(op) & SimCmd.M_IDS) != 0
		if has_ids != bool(row[1]):
			problems.append("%s: M_IDS %s != assumed %s" % [SimCmd.name_of(op), has_ids, bool(row[1])])
	return problems
