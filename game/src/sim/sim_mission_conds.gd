class_name SimMissionConds
extends RefCounted
## Condition evaluator of the mission system: pure reads of the world and of the SimMissionSystem state (ints only, no side
## effects, no RNG). Semantics per DefMissionCond.Op; selectors that name several players SUM counts / credits / power, require
## ALL for defeated / no_assets and accept ANY for research / support_power / superweapon.


static func compare(a: int, cmp: int, b: int) -> bool:
	match cmp:
		DefMissionCond.Cmp.GE:
			return a >= b
		DefMissionCond.Cmp.LE:
			return a <= b
		DefMissionCond.Cmp.EQ:
			return a == b
		DefMissionCond.Cmp.GT:
			return a > b
		DefMissionCond.Cmp.LT:
			return a < b
	return a != b


static func eval(s: SimMissionSystem, w: SimWorld, c: DefMissionCond) -> bool:
	if c == null:
		return false
	match c.op:
		DefMissionCond.Op.ALL:
			for ch: DefMissionCond in c.children:
				if not eval(s, w, ch):
					return false
			return true
		DefMissionCond.Op.ANY:
			for ch: DefMissionCond in c.children:
				if eval(s, w, ch):
					return true
			return false
		DefMissionCond.Op.NOT:
			return c.children.is_empty() or not eval(s, w, c.children[0])
		DefMissionCond.Op.TIME:
			return compare(w.tick, c.cmp, c.value)
		DefMissionCond.Op.TIMER:
			return s.timer_state[c.ref] == SimMissionConst.TM_EXPIRED
		DefMissionCond.Op.OBJECTIVE:
			return s.obj_state[c.ref] == c.state
		DefMissionCond.Op.COUNT:
			return compare(s.count(w, c.owner_mode, c.owner_val, c.of_kind, c.def_idx, c.tag_mask, c.area), c.cmp, c.value)
		DefMissionCond.Op.STRUCTURE:
			return _structure(s, w, c)
		DefMissionCond.Op.AREA_LEFT:
			return s.latch[c.ref] == 1 and s.count(w, c.owner_mode, c.owner_val, DefMissionCond.OF_UNIT, c.def_idx, c.tag_mask, c.area) == 0
		DefMissionCond.Op.CREDITS:
			var total: int = 0
			for pid: int in s.pids_of(w, c.owner_mode, c.owner_val):
				if pid >= 0:
					total += w.players[pid].credits
			return compare(total, c.cmp, c.value)
		DefMissionCond.Op.POWER:
			var bal: int = 0
			for pid: int in s.pids_of(w, c.owner_mode, c.owner_val):
				if pid >= 0:
					bal += w.players[pid].power_supply - w.players[pid].power_demand
			return compare(bal, c.cmp, c.value)
		DefMissionCond.Op.RESEARCH:
			for pid: int in s.pids_of(w, c.owner_mode, c.owner_val):
				var pe: SimPlayerEcon = w.players[pid].econ if pid >= 0 else null
				if pe != null and c.ref < pe.researched.size() and pe.researched[c.ref] != 0:
					return true
			return false
		DefMissionCond.Op.SUPPORT_POWER:
			return _support_power(s, w, c)
		DefMissionCond.Op.SUPERWEAPON:
			for pid: int in s.pids_of(w, c.owner_mode, c.owner_val):
				var pe2: SimPlayerEcon = w.players[pid].econ if pid >= 0 else null
				if pe2 == null:
					continue
				var sl: SimPowerSlot = pe2.slots[SimEconConst.SLOT_SW]
				if c.state == 0 and sl.last_activation_tick >= 0:
					return true
				if c.state == 1 and sl.def_idx >= 0 and sl.sw_state == SimEconConst.SW_READY:
					return true
			return false
		DefMissionCond.Op.DEFEATED:
			var ps: PackedInt32Array = s.pids_of(w, c.owner_mode, c.owner_val)
			for pid: int in ps:
				if pid < 0 or w.players[pid].eliminated == 0:
					return false
			return not ps.is_empty()
		DefMissionCond.Op.NO_ASSETS:
			var ps2: PackedInt32Array = s.pids_of(w, c.owner_mode, c.owner_val)
			for pid: int in ps2:
				if pid < 0 or w.players[pid].struct_count != 0 or w.players[pid].rebuilders != 0:
					return false
			return not ps2.is_empty()
		DefMissionCond.Op.WAVE:
			if s.wave_spawned[c.ref] == 0:
				return false
			if c.state == 0:
				return true
			for id: int in s.wave_ids[c.ref]:
				if w.is_alive(id):
					return false
			return true
		DefMissionCond.Op.TRIGGER:
			return compare(s.trig_fired[c.ref], c.cmp, c.value)
	return false


static func _support_power(s: SimMissionSystem, w: SimWorld, c: DefMissionCond) -> bool:
	for pid: int in s.pids_of(w, c.owner_mode, c.owner_val):
		var pe: SimPlayerEcon = w.players[pid].econ if pid >= 0 else null
		if pe == null:
			continue
		var sl: SimPowerSlot = pe.slots[c.ref]
		if sl.def_idx < 0:
			continue
		if c.state == 0 and sl.announced and w.tick >= sl.ready_tick:
			return true
		if c.state == 1 and sl.uses >= c.value:
			return true
	return false


static func _structure(s: SimMissionSystem, w: SimWorld, c: DefMissionCond) -> bool:
	if c.ref >= 0:  # a placed structure
		var id: int = s.placed_id[c.ref]
		if id <= 0:
			return false
		var e: SimEntity = w.get_entity(id)
		var alive: bool = e != null and (e.flags & SimFlags.F_GONE) == 0
		var owner_ok: bool = true
		if c.owner_mode == DefMissionCond.OWN_PID and alive:
			owner_ok = e.owner == c.owner_val
		match c.state:
			SimMissionConst.ST_EXISTS:
				return alive and owner_ok
			SimMissionConst.ST_POWERED:
				return alive and owner_ok and (e.flags & SimFlags.F_POWERED) != 0
			SimMissionConst.ST_DESTROYED:
				return not alive
			SimMissionConst.ST_CAPTURED:
				return alive and e.owner != s.placed_owner0[c.ref] and owner_ok
		return false
	for e2: SimEntity in s.collect(w, c.owner_mode, c.owner_val, DefMissionCond.OF_STRUCTURE, c.def_idx, 0, -1):
		if (e2.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
			continue
		if c.state == SimMissionConst.ST_EXISTS or (e2.flags & SimFlags.F_POWERED) != 0:
			return true
	return false
