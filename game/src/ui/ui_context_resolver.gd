class_name UiContextResolver
extends RefCounted
## The right-click / armed-click decision table (ui.md 5.7): pure and deterministic. `resolve` turns
## (selection capabilities, what is under the cursor, modifiers, armed mode) into a `UiOrderIntent`; every unit ends
## in at most one intent (first matching rule wins) and a mixed selection yields the further intents in `extra`, in
## rule order. `make_target` is the only impure part (pick + port reads).

const MOD_QUEUE: int = 1  ## the queue / add gesture (Shift; = UiKeymap.MOD_SHIFT after mods_of)
const MOD_FORCE: int = 2  ## the force-fire gesture (Ctrl, Option on macOS; = UiKeymap.MOD_CTRL after mods_of)

const DENY_OFF_MAP: StringName = &"order.deny.off_map"
const DENY_CANNOT_HIT: StringName = &"order.deny.cannot_hit"
const DENY_NO_WEAPON: StringName = &"order.deny.no_weapon"
const DENY_NO_VALID: StringName = &"order.deny.no_valid_order"
const DENY_BLOCKED: StringName = &"order.deny.blocked"
const DENY_NOT_VISIBLE: StringName = &"order.deny.not_visible"
const DENY_FOLLOW_TARGET: StringName = &"order.deny.follow_target"
const DENY_GUARD_ENEMY: StringName = &"order.deny.guard_enemy"
const DENY_GUARD_TARGET: StringName = &"order.deny.guard_target"
const DENY_NOT_SELLABLE: StringName = &"order.deny.not_sellable"
const DENY_NOT_REPAIRABLE: StringName = &"order.deny.not_repairable"
const DENY_RALLY_TARGET: StringName = &"order.deny.rally_target"



## Pure resolution. `mods` = MOD_QUEUE | MOD_FORCE. `armed` = UiModes.Armed.
static func resolve(sel: UiSelectionInfo, tgt: UiTarget, mods: int, armed: int) -> UiOrderIntent:
	var queue: bool = (mods & MOD_QUEUE) != 0
	var force: bool = (mods & MOD_FORCE) != 0
	if armed == UiModes.Armed.WAYPOINT:
		armed = UiModes.Armed.NONE
		queue = true
	# tool modes act on the clicked structure and need no unit selection
	match armed:
		UiModes.Armed.SELL:
			return _finish(_armed_sell(tgt), queue)
		UiModes.Armed.REPAIR:
			return _finish(_armed_repair(tgt), queue)
		UiModes.Armed.PING, UiModes.Armed.POWER, UiModes.Armed.SUPERWEAPON, UiModes.Armed.PLACE, UiModes.Armed.ABILITY:
			return _none(tgt)
	if sel.mode == UiSelection.Mode.NONE or sel.mode == UiSelection.Mode.FOREIGN:
		return _none(tgt)
	if armed != UiModes.Armed.NONE:
		return _finish(_resolve_armed(sel, tgt, armed), queue, sel)
	if tgt.kind == UiTarget.Kind.NONE:
		return UiOrderIntent.denied(DENY_OFF_MAP)
	if tgt.kind == UiTarget.Kind.ENEMY and not tgt.visible and not tgt.ghost:
		return UiOrderIntent.denied(DENY_NOT_VISIBLE)
	var st := _State.new()
	st.left = _all_idx(sel)
	var list: Array[UiOrderIntent] = []
	for rule: int in range(1, 17):
		if st.left.is_empty():
			break
		_apply_rule(rule, sel, tgt, force, st, list)
	if list.is_empty():
		return UiOrderIntent.denied(_deny_reason(sel, tgt, st))
	return _finish(list, queue, sel)


## Cursor state (UiCursors.State integer) for an intent.
static func cursor_for(intent: UiOrderIntent) -> int:
	return intent.cursor


## The only impure part: view.pick + view.pick_ground + port reads -> UiTarget. `view` is a UiViewPort (duck-typed:
## pick, pick_ground, world_to_sim). An explored cell with a deposit becomes Kind.DEPOSIT (eid -1, cell centre).
static func make_target(port: UiSimPort, view: Object, screen: Vector2, viewer_pid: int, caps: UiUnitCaps = null) -> UiTarget:
	var c: UiUnitCaps = caps if caps != null else UiUnitCaps.shared_for(port)
	var eid: int = int(view.call("pick", screen, 0xFF))
	var row := UiEntityRow.new()
	if eid >= 0 and port.read(eid, row):
		return from_row(port, row, viewer_pid, c)
	var g: Variant = view.call("pick_ground", screen)
	if not (g is Vector3) or (g as Vector3).x == INF or (g as Vector3).z == INF or is_inf((g as Vector3).x):
		return UiTarget.new()
	var cell: Vector2i = view.call("world_to_sim", g)
	var cx: int = cell.x >> 10
	var cy: int = cell.y >> 10
	if port.visibility(cx, cy) >= UiSimPort.Vis.FOG and port.deposit_at(cx, cy) > 0:
		return UiTarget.deposit(UiCmdCodec.cell_center(cx), UiCmdCodec.cell_center(cy))
	var t: UiTarget = UiTarget.ground(cell.x, cell.y)
	var mask: int = 0
	for mc: int in DefEnums.MoveClass.COUNT:
		if port.passable(cx, cy, mc):
			mask |= 1 << mc
	t.passable_mask = mask
	t.visible = port.visibility(cx, cy) == UiSimPort.Vis.VISIBLE
	return t


## UiTarget of an already-read entity row (make_target's entity branch; also used by tests over the fixture).
static func from_row(port: UiSimPort, row: UiEntityRow, viewer_pid: int, c: UiUnitCaps) -> UiTarget:
	var t := UiTarget.new()
	t.eid = row.id
	t.def_idx = row.def_idx
	t.owner = row.owner
	t.layer = row.layer
	t.x = row.x
	t.y = row.y
	t.entity_kind = row.kind
	t.ghost = (row.flags & UiEntityRow.F_GHOST) != 0
	t.visible = not t.ghost and port.can_target(row.id)
	t.hp_permille = row.hp_permille()
	t.damaged = row.hp_max > 0 and row.hp < row.hp_max
	t.repairing = (row.flags & UiEntityRow.F_REPAIRING) != 0
	t.selling = (row.flags & UiEntityRow.F_SELLING) != 0
	var rel: int = port.rel(viewer_pid, row.owner) if row.owner >= 0 else UiSimPort.Rel.NEUTRAL
	if row.kind == UiEntityRow.K_WRECK:
		t.kind = UiTarget.Kind.WRECK
	else:
		match rel:
			UiSimPort.Rel.SELF:
				t.kind = UiTarget.Kind.OWN
			UiSimPort.Rel.ALLY:
				t.kind = UiTarget.Kind.ALLY
			UiSimPort.Rel.ENEMY:
				t.kind = UiTarget.Kind.ENEMY
			_:
				t.kind = UiTarget.Kind.NEUTRAL
	var d: GameData = port.data()
	var kind_key: int = UiSimPort.KIND_STRUCTURE if row.is_structure() else UiSimPort.KIND_UNIT
	if row.kind != UiEntityRow.K_WRECK and row.kind != UiEntityRow.K_NEUTRAL_STRUCTURE:
		t.caps = c.caps_of(kind_key, row.def_idx)
	t.is_producer = (t.caps & UiUnitCaps.CAP_PRODUCER) != 0
	if d != null:
		if row.kind == UiEntityRow.K_NEUTRAL_STRUCTURE:
			t.capturable = row.capturable and rel != UiSimPort.Rel.SELF and rel != UiSimPort.Rel.ALLY
			t.garrisonable = row.garrison_free > 0
		elif row.kind == UiEntityRow.K_STRUCTURE and row.def_idx >= 0 and row.def_idx < d.structures.size():
			var s: DefStructure = d.structures[row.def_idx]
			t.is_refinery = s.queue_kind == DefEnums.QueueKind.COLLECTOR
			t.is_airfield = s.queue_kind == DefEnums.QueueKind.AIRCRAFT or s.pads > 0
		elif row.kind == UiEntityRow.K_UNIT and row.def_idx >= 0 and row.def_idx < d.units.size():
			var u: DefUnit = d.units[row.def_idx]
			for a: DefAbility in u.abilities:
				if a.kind == DefEnums.AbilityKind.TRANSPORT:
					t.transport_free = maxi(row.cargo_cap - row.cargo, 0)
					var veh: int = int(a.params.get("capacity_vehicles_n", 0))
					t.transport_vehicle_free = veh if row.cargo == 0 else 0
				elif a.kind == DefEnums.AbilityKind.CARRIER:
					t.is_carrier = true
		elif row.kind == UiEntityRow.K_WRECK and row.def_idx >= 0 and row.def_idx < d.units.size():
			t.salvageable = t.kind == UiTarget.Kind.WRECK and rel != UiSimPort.Rel.SELF and rel != UiSimPort.Rel.ALLY \
				and (d.units[row.def_idx].tags & DefEnums.UT_LAND_VEHICLE) != 0
	return t


# ---- rules -----------------------------------------------------------------------------------------------------------
class _State:
	extends RefCounted
	var left: PackedInt32Array = PackedInt32Array()  ## indices into sel.ids of the units not yet assigned, ascending
	var cannot_hit: int = 0  ## units consumed by rule 12
	var blocked: bool = false
	var armed_units: int = 0


static func _apply_rule(rule: int, sel: UiSelectionInfo, tgt: UiTarget, force: bool, st: _State, out: Array[UiOrderIntent]) -> void:
	var k: int = tgt.kind
	match rule:
		1:  # FORCE
			if not force or k == UiTarget.Kind.ENEMY or k == UiTarget.Kind.NONE:
				return
			var ground_like: bool = k == UiTarget.Kind.GROUND or k == UiTarget.Kind.WRECK or k == UiTarget.Kind.DEPOSIT
			var sub: PackedInt32Array = _take(sel, st, func(c: int) -> bool:
				if (c & UiUnitCaps.CAP_ARMED) == 0 or (c & UiUnitCaps.CAP_STRUCTURE) != 0:
					return false
				return (c & UiUnitCaps.CAP_HIT_GROUND) != 0 if ground_like else UiUnitCaps.hits(c, tgt.layer))
			if sub.is_empty():
				return
			if ground_like:
				var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.FORCE_FIRE, sub, tgt.x, tgt.y)
				out.append(it)
			else:
				var it2: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, sub, tgt.x, tgt.y, tgt.eid)
				it2.force = true
				it2.cursor = UiOrderIntent.CUR_FORCE_FIRE
				out.append(it2)
		2:  # CAPTURE
			if tgt.capturable:
				_simple(sel, st, out, UiOrderIntent.Kind.CAPTURE, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_CAPTURE) != 0)
		3:  # GARRISON
			if tgt.garrisonable and (k == UiTarget.Kind.NEUTRAL or k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY):
				_simple(sel, st, out, UiOrderIntent.Kind.GARRISON, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_GARRISON) != 0 and (c & UiUnitCaps.CAP_SERVICE) == 0)
		4:  # LOAD
			if (k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY) and (tgt.transport_free > 0 or tgt.transport_vehicle_free > 0) and not sel.has_id(tgt.eid):
				var sub4: PackedInt32Array = _take(sel, st, func(c: int) -> bool:
					if (c & UiUnitCaps.CAP_PASSENGER) == 0 or (c & UiUnitCaps.CAP_TRANSPORT) != 0:
						return false
					if (c & UiUnitCaps.CAP_VEHICLE) != 0:
						return tgt.transport_vehicle_free > 0
					return tgt.transport_free > 0)
				if not sub4.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.LOAD, sub4, tgt.x, tgt.y, tgt.eid))
		5:  # REPAIR_UNIT
			if (k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY) and tgt.entity_kind == UiTarget.EntityKind.UNIT and tgt.damaged and (tgt.caps & UiUnitCaps.CAP_VEHICLE) != 0:
				_simple(sel, st, out, UiOrderIntent.Kind.REPAIR, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_REPAIR_VEHICLE) != 0, true)
		6:  # REPAIR_STRUCT
			if (k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY) and tgt.entity_kind == UiTarget.EntityKind.STRUCTURE and tgt.damaged:
				_simple(sel, st, out, UiOrderIntent.Kind.REPAIR, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_REPAIR_STRUCT) != 0)
		7:  # SALVAGE
			if tgt.salvageable:
				_simple(sel, st, out, UiOrderIntent.Kind.SALVAGE, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_SALVAGE) != 0)
		8:  # HARVEST_DEPOSIT
			if k == UiTarget.Kind.DEPOSIT:
				var sub8: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_COLLECTOR) != 0)
				if not sub8.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.HARVEST, sub8, tgt.x, tgt.y, -1))
		9:  # RETURN_CASH
			if k == UiTarget.Kind.OWN and tgt.is_refinery:
				_simple(sel, st, out, UiOrderIntent.Kind.RETURN_CASH, tgt, func(c: int) -> bool: return (c & UiUnitCaps.CAP_COLLECTOR) != 0)
		10:  # RETURN_BASE
			if k == UiTarget.Kind.OWN and (tgt.is_airfield or tgt.is_carrier):
				_simple(sel, st, out, UiOrderIntent.Kind.RETURN_BASE, tgt, func(c: int) -> bool: return (c & (UiUnitCaps.CAP_AIR | UiUnitCaps.CAP_CARRIER_DRONE)) != 0)
		11:  # ATTACK
			if k != UiTarget.Kind.ENEMY:
				return
			var visible: bool = tgt.visible and not tgt.ghost
			var sub11: PackedInt32Array = _take(sel, st, func(c: int) -> bool:
				if (c & UiUnitCaps.CAP_ARMED) == 0 or (c & (UiUnitCaps.CAP_STRUCTURE | UiUnitCaps.CAP_SERVICE)) != 0 or not UiUnitCaps.hits(c, tgt.layer):
					return false
				return visible or (c & UiUnitCaps.CAP_MOBILE) != 0)
			if sub11.is_empty():
				return
			if visible:
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, sub11, tgt.x, tgt.y, tgt.eid))
			else:
				var g: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK_MOVE, sub11, tgt.x, tgt.y)
				g.cursor = UiOrderIntent.CUR_ATTACK
				out.append(g)
		12:  # CANNOT_HIT
			if k != UiTarget.Kind.ENEMY:
				return
			var sub12: PackedInt32Array = _take(sel, st, func(c: int) -> bool:
				return (c & UiUnitCaps.CAP_ARMED) != 0 and (c & UiUnitCaps.CAP_STRUCTURE) == 0 and not UiUnitCaps.hits(c, tgt.layer))
			st.cannot_hit += sub12.size()
		13:  # RALLY
			if k == UiTarget.Kind.NONE or k == UiTarget.Kind.ENEMY:
				return
			var sub13: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_STRUCTURE) != 0 and (c & UiUnitCaps.CAP_PRODUCER) != 0)
			if not sub13.is_empty():
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.SET_RALLY, sub13, tgt.x, tgt.y, tgt.eid if k == UiTarget.Kind.OWN else -1))
		14:  # MOVE_GROUND
			if k != UiTarget.Kind.GROUND:
				return
			if tgt.passable_mask >= 0 and sel.move_mask != 0 and (tgt.passable_mask & sel.move_mask) == 0:
				st.blocked = true
				return
			var sub14: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
			if not sub14.is_empty():
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, sub14, tgt.x, tgt.y))
		15:  # MOVE_TO_ENTITY
			if (k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY or k == UiTarget.Kind.NEUTRAL or k == UiTarget.Kind.WRECK or k == UiTarget.Kind.DEPOSIT) and not sel.has_id(tgt.eid):
				var sub15: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not sub15.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, sub15, tgt.x, tgt.y))
		16:  # ENEMY_UNARMED_MOVE
			if k != UiTarget.Kind.ENEMY:
				return
			var sub16: PackedInt32Array = _take(sel, st, func(c: int) -> bool:
				return (c & UiUnitCaps.CAP_MOBILE) != 0 and (c & UiUnitCaps.CAP_ARMED) == 0 and (c & (UiUnitCaps.CAP_COLLECTOR | UiUnitCaps.CAP_MCV | UiUnitCaps.CAP_CAPTURE | UiUnitCaps.CAP_TRANSPORT)) == 0)
			if not sub16.is_empty():
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, sub16, tgt.x, tgt.y))


## Removes from st.left and returns (ascending) the ids whose caps satisfy `pred`.
static func _take(sel: UiSelectionInfo, st: _State, pred: Callable) -> PackedInt32Array:
	var sub: PackedInt32Array = PackedInt32Array()
	var rest: PackedInt32Array = PackedInt32Array()
	for i: int in st.left:
		if bool(pred.call(sel.caps[i])):
			sub.append(sel.ids[i])
		else:
			rest.append(i)
	st.left = rest
	return sub


static func _all_idx(sel: UiSelectionInfo) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(sel.count)
	for i: int in sel.count:
		a[i] = i
	return a


## Rule with an entity target: one intent of `kind` aimed at tgt.eid for the units matching `pred`.
static func _simple(sel: UiSelectionInfo, st: _State, out: Array[UiOrderIntent], kind: int, tgt: UiTarget, pred: Callable, not_self: bool = false) -> void:
	var sub: PackedInt32Array = _take(sel, st, pred)
	if not_self and sub.has(tgt.eid):
		sub.remove_at(sub.find(tgt.eid))
	if not sub.is_empty():
		out.append(UiOrderIntent.make(kind, sub, tgt.x, tgt.y, tgt.eid))


static func _deny_reason(sel: UiSelectionInfo, tgt: UiTarget, st: _State) -> StringName:
	if st.blocked:
		return DENY_BLOCKED
	if st.cannot_hit > 0:
		return DENY_CANNOT_HIT
	if tgt.kind == UiTarget.Kind.ENEMY and (sel.caps_any & UiUnitCaps.CAP_ARMED) == 0:
		return DENY_NO_WEAPON
	return DENY_NO_VALID


## Shared tail of every resolution: primary = list[0], extras in rule order, common modifiers, per-intent def.
static func _finish(list: Array[UiOrderIntent], queue: bool, sel: UiSelectionInfo = null) -> UiOrderIntent:
	if list.is_empty():
		return UiOrderIntent.denied(DENY_NO_VALID)
	var primary: UiOrderIntent = list[0]
	for i: int in list.size():
		var it: UiOrderIntent = list[i]
		it.queued = queue
		if sel != null and not it.ids.is_empty():
			var d: int = sel.def_of(it.ids[0])
			if d >= 0:
				it.def_idx = d
		if i > 0:
			primary.extra.append(it)
	return primary


static func _none(tgt: UiTarget) -> UiOrderIntent:
	var it := UiOrderIntent.new()
	match tgt.kind:
		UiTarget.Kind.OWN:
			it.cursor = UiOrderIntent.CUR_SELECT
		UiTarget.Kind.ENEMY, UiTarget.Kind.NEUTRAL, UiTarget.Kind.ALLY, UiTarget.Kind.WRECK:
			it.cursor = UiOrderIntent.CUR_INSPECT
		_:
			it.cursor = UiOrderIntent.CUR_DEFAULT
	return it


# ---- armed modes -----------------------------------------------------------------------------------------------------
static func _armed_sell(tgt: UiTarget) -> Array[UiOrderIntent]:
	if tgt.kind == UiTarget.Kind.OWN and tgt.entity_kind == UiTarget.EntityKind.STRUCTURE and (tgt.caps & UiUnitCaps.CAP_SELLABLE) != 0 and not tgt.selling:
		var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.SELL, PackedInt32Array([tgt.eid]), tgt.x, tgt.y, tgt.eid)
		it.def_idx = tgt.def_idx
		return [it]
	return [UiOrderIntent.denied(DENY_NOT_SELLABLE)]


static func _armed_repair(tgt: UiTarget) -> Array[UiOrderIntent]:
	if tgt.kind == UiTarget.Kind.OWN and tgt.entity_kind == UiTarget.EntityKind.STRUCTURE:
		var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.STRUCT_REPAIR, PackedInt32Array([tgt.eid]), tgt.x, tgt.y, tgt.eid)
		it.arg = 0 if tgt.repairing else 1
		it.def_idx = tgt.def_idx
		return [it]
	return [UiOrderIntent.denied(DENY_NOT_REPAIRABLE)]


static func _resolve_armed(sel: UiSelectionInfo, tgt: UiTarget, armed: int) -> Array[UiOrderIntent]:
	if tgt.kind == UiTarget.Kind.NONE:
		return [UiOrderIntent.denied(DENY_OFF_MAP)]
	var st := _State.new()
	st.left = _all_idx(sel)
	var out: Array[UiOrderIntent] = []
	var k: int = tgt.kind
	match armed:
		UiModes.Armed.ATTACK_MOVE:
			if k == UiTarget.Kind.ENEMY:
				_apply_rule(11, sel, tgt, false, st, out)
				var mv: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not mv.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, mv, tgt.x, tgt.y))
			else:
				var am: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_ARMED) != 0 and (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not am.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.ATTACK_MOVE, am, tgt.x, tgt.y))
				var um: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not um.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, um, tgt.x, tgt.y))
		UiModes.Armed.MOVE:
			var m2: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
			if not m2.is_empty():
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.MOVE, m2, tgt.x, tgt.y))
		UiModes.Armed.PATROL:
			var p: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
			if not p.is_empty():
				out.append(UiOrderIntent.make(UiOrderIntent.Kind.PATROL, p, tgt.x, tgt.y))
		UiModes.Armed.FOLLOW:
			if (k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY) and tgt.entity_kind == UiTarget.EntityKind.UNIT and not sel.has_id(tgt.eid):
				var f: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not f.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.FOLLOW, f, tgt.x, tgt.y, tgt.eid))
			else:
				return [UiOrderIntent.denied(DENY_FOLLOW_TARGET)]
		UiModes.Armed.GUARD:
			if k == UiTarget.Kind.ENEMY:
				return [UiOrderIntent.denied(DENY_GUARD_ENEMY)]
			if k == UiTarget.Kind.OWN or k == UiTarget.Kind.ALLY:
				var gu: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_ARMED) != 0 and (c & UiUnitCaps.CAP_MOBILE) != 0)
				if gu.has(tgt.eid):
					gu.remove_at(gu.find(tgt.eid))
				if not gu.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.GUARD, gu, tgt.x, tgt.y, tgt.eid))
			elif k == UiTarget.Kind.GROUND or k == UiTarget.Kind.DEPOSIT:
				var gp: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_ARMED) != 0 and (c & UiUnitCaps.CAP_MOBILE) != 0)
				if not gp.is_empty():
					out.append(UiOrderIntent.make(UiOrderIntent.Kind.GUARD, gp, tgt.x, tgt.y, -1))
			else:
				return [UiOrderIntent.denied(DENY_GUARD_TARGET)]
		UiModes.Armed.FORCE_FIRE:
			if k == UiTarget.Kind.ENEMY:
				_apply_rule(11, sel, tgt, false, st, out)
			else:
				_apply_rule(1, sel, tgt, true, st, out)
		UiModes.Armed.RALLY:
			if k == UiTarget.Kind.OWN or k == UiTarget.Kind.GROUND or k == UiTarget.Kind.DEPOSIT:
				var r: PackedInt32Array = _take(sel, st, func(c: int) -> bool: return (c & UiUnitCaps.CAP_STRUCTURE) != 0 and (c & UiUnitCaps.CAP_PRODUCER) != 0)
				# no producer selected: ids stay empty, the bus asks its rally_fallback (the active tab's producers)
				var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.SET_RALLY, r, tgt.x, tgt.y, tgt.eid if k == UiTarget.Kind.OWN else -1)
				out.append(it)
			else:
				return [UiOrderIntent.denied(DENY_RALLY_TARGET)]
	if out.is_empty():
		return [UiOrderIntent.denied(_deny_reason(sel, tgt, st))]
	return out
