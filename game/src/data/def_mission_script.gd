class_name DefMissionScript
extends RefCounted
## Compiles the `triggers` of a mission (conditions + actions) for DefMissionParser. The grammar is documented in the header of
## DefMissionParser (COND / ACTION sections).

const MAX_DEPTH: int = 8
const MAX_NODES: int = 64
const COND_KEYS: Dictionary = {
	"time": ["kind", "cmp", "seconds", "ticks"], "timer": ["kind", "timer"], "objective": ["kind", "objective", "state"],
	"count": ["kind", "owner", "of", "def", "tag", "area", "cmp", "value"],
	"structure": ["kind", "state", "owner", "def", "placed"], "area_left": ["kind", "owner", "area", "def", "tag"],
	"credits": ["kind", "owner", "cmp", "value"], "research": ["kind", "owner", "research"],
	"power": ["kind", "owner", "cmp", "value"], "support_power": ["kind", "owner", "slot", "state"],
	"superweapon": ["kind", "owner", "state"], "defeated": ["kind", "owner"], "no_assets": ["kind", "owner"],
	"wave": ["kind", "wave", "state"], "trigger": ["kind", "trigger", "cmp", "value"],
}
const STRUCT_STATES: PackedStringArray = ["exists", "powered", "destroyed", "captured"]  ## index == SimMissionConst.ST_*

var p: DefMissionParser = null
var _nodes: int = 0


func _init(parser: DefMissionParser) -> void:
	p = parser


func parse_triggers(v: Variant) -> void:
	if not (v is Array):
		p.fail("V-MIS-02", "triggers", "must be an array")
		return
	var arr: Array = v
	if arr.size() > DefMissionParser.MAX_TRIGGERS:
		p.fail("V-MIS-02", "triggers", "more than %d triggers" % DefMissionParser.MAX_TRIGGERS)
		return
	var by_id: Dictionary = {}
	for tv: Variant in arr:
		if tv is Dictionary:
			by_id[str((tv as Dictionary).get("id", ""))] = tv
	var ids: PackedStringArray = PackedStringArray(by_id.keys())
	ids.sort()
	for id: String in ids:
		p.m.triggers.append(_trigger(by_id[id] as Dictionary, id))
	for tv: Variant in arr:
		if not (tv is Dictionary):
			p.fail("V-MIS-02", "triggers", "every trigger must be an object")


func _trigger(d: Dictionary, id: String) -> DefMissionTrigger:
	var w: String = "triggers[%s]" % id
	var t: DefMissionTrigger = DefMissionTrigger.new()
	p.check_keys(d, ["id", "once", "enabled", "edge", "cooldown_s", "when", "then"], w)
	t.id = id
	if not DefMissionParser.id_ok(id):
		p.fail("V-MIS-01", w, "'%s' is not a valid trigger id" % id)
	t.once = p.bool_of(d, "once", true, w)
	t.enabled = p.bool_of(d, "enabled", true, w)
	t.edge = p.bool_of(d, "edge", false, w)
	t.cooldown = p.int_of(d, "cooldown_s", 0, 36000, 0, w) * SimConfig.TPS
	_nodes = 0
	if d.has("when") and d["when"] is Dictionary:
		t.when = cond(d["when"] as Dictionary, 0, w + ".when")
	else:
		p.fail("V-MIS-02", w, "'when' (a condition object) is required")
	var acts: Variant = d.get("then", [])
	if not (acts is Array) or (acts as Array).is_empty():
		p.fail("V-MIS-02", w, "'then' must be a non-empty array of actions")
		return t
	if (acts as Array).size() > DefMissionParser.MAX_ACTIONS:
		p.fail("V-MIS-02", w, "'then' has more than %d actions" % DefMissionParser.MAX_ACTIONS)
		return t
	for i: int in (acts as Array).size():
		var av: Variant = (acts as Array)[i]
		if av is Dictionary:
			t.then.append(action(av as Dictionary, "%s.then[%d]" % [w, i]))
		else:
			p.fail("V-MIS-02", w, "then[%d] must be an object" % i)
	return t


# ---------------------------------------------------------------------------------------------------- shared lookups
func _cmp(d: Dictionary, w: String) -> int:
	var s: String = p.str_of(d, "cmp", 1, 2, ">=", w)
	var i: int = DefMissionCond.CMP_NAMES.find(s)
	if i < 0:
		p.fail("V-MIS-02", w, "cmp must be one of %s" % ", ".join(DefMissionCond.CMP_NAMES))
		return 0
	return i


## Entity filter: of / def / tag -> [of_kind, def_idx, tag_mask]. `default_of`: -1 = infer (unit when nothing is given).
func _filter(d: Dictionary, w: String, units_only: bool = false) -> PackedInt32Array:
	var of_kind: int = DefMissionCond.OF_UNIT
	var explicit: bool = false
	if d.has("of"):
		var s: String = p.str_of(d, "of", 3, 9, "unit", w)
		var names: PackedStringArray = ["unit", "structure", "any"]
		of_kind = names.find(s)
		if of_kind < 0:
			p.fail("V-MIS-02", w, "of must be unit, structure or any")
			of_kind = 0
		explicit = true
	var def_idx: int = -1
	if d.has("def"):
		var id: String = p.str_of(d, "def", 1, 80, "", w)
		var kind_of_def: int = -1
		if id.begins_with("unit."):
			kind_of_def = DefMissionCond.OF_UNIT
			def_idx = p.data.unit_idx(id)
		elif id.begins_with("structure."):
			kind_of_def = DefMissionCond.OF_STRUCTURE
			def_idx = p.data.structure_idx(id)
		if kind_of_def < 0 or def_idx < 0:
			p.fail("V-MIS-03", w, "unknown unit / structure def '%s'" % id)
		elif explicit and of_kind != kind_of_def:
			p.fail("V-MIS-05", w, "'of' contradicts the def '%s'" % id)
		else:
			of_kind = kind_of_def
	var mask: int = 0
	if d.has("tag"):
		var tv: Variant = d["tag"]
		var names2: PackedStringArray = PackedStringArray()
		if tv is String:
			names2.append(tv)
		elif tv is Array:
			for e: Variant in tv as Array:
				names2.append(str(e))
		else:
			p.fail("V-MIS-02", w, "tag must be a string or an array of strings")
		if of_kind == DefMissionCond.OF_ANY:
			p.fail("V-MIS-05", w, "a tag needs of unit or structure")
		for n: String in names2:
			var bit: int = p.data.tags.unit_bit(n) if of_kind == DefMissionCond.OF_UNIT else p.data.tags.structure_bit(n)
			if bit == 0:
				p.fail("V-MIS-03", w, "unknown %s tag '%s'" % ["unit" if of_kind == DefMissionCond.OF_UNIT else "structure", n])
			mask |= bit
	if units_only and of_kind != DefMissionCond.OF_UNIT:
		p.fail("V-MIS-05", w, "this action only addresses units")
	return PackedInt32Array([of_kind, def_idx, mask])


func _area(d: Dictionary, w: String, key: String = "area", required: bool = false) -> int:
	return p.ref_of(p.area_ix, "area", key, d, w, required)


# ---------------------------------------------------------------------------------------------------- conditions
func cond(d: Dictionary, depth: int, w: String) -> DefMissionCond:
	var c: DefMissionCond = DefMissionCond.new()
	_nodes += 1
	if _nodes > MAX_NODES:
		p.fail("V-MIS-05", w, "condition tree has more than %d nodes" % MAX_NODES)
		return c
	if depth > MAX_DEPTH:
		p.fail("V-MIS-05", w, "condition tree deeper than %d" % MAX_DEPTH)
		return c
	for comb: String in ["all", "any", "not"]:
		if d.has(comb):
			if d.size() != 1:
				p.fail("V-MIS-05", w, "'%s' must be the only key of its object" % comb)
			c.op = ["all", "any", "not"].find(comb)
			var sub: Variant = d[comb]
			if comb == "not":
				if sub is Dictionary:
					c.children.append(cond(sub as Dictionary, depth + 1, w + ".not"))
				else:
					p.fail("V-MIS-05", w, "'not' takes one condition object")
			elif sub is Array and not (sub as Array).is_empty():
				for i: int in (sub as Array).size():
					if (sub as Array)[i] is Dictionary:
						c.children.append(cond((sub as Array)[i] as Dictionary, depth + 1, "%s.%s[%d]" % [w, comb, i]))
					else:
						p.fail("V-MIS-05", w, "'%s' entries must be condition objects" % comb)
			else:
				p.fail("V-MIS-05", w, "'%s' takes a non-empty array of conditions" % comb)
			return c
	var kind: String = p.str_of(d, "kind", 1, 20, "", w, true)
	if not COND_KEYS.has(kind):
		p.fail("V-MIS-05", w, "unknown condition kind '%s'" % kind)
		return c
	p.check_keys(d, PackedStringArray(COND_KEYS[kind]), w)
	c.op = DefMissionCond.OP_NAMES.find(kind)
	match c.op:
		DefMissionCond.Op.TIME:
			c.cmp = _cmp(d, w)
			c.value = p.ticks_of(d, w, 0, 36000)
			if c.value < 0:
				p.fail("V-MIS-05", w, "time needs 'seconds' or 'ticks'")
		DefMissionCond.Op.TIMER:
			c.ref = p.ref_of(p.timer_ix, "timer", "timer", d, w)
		DefMissionCond.Op.OBJECTIVE:
			c.ref = p.ref_of(p.obj_ix, "objective", "objective", d, w)
			c.state = _state_of(d, w, DefMissionObjective.STATE_NAMES)
		DefMissionCond.Op.COUNT:
			_owner(c, d, w, false, true)
			var f: PackedInt32Array = _filter(d, w)
			c.of_kind = f[0]
			c.def_idx = f[1]
			c.tag_mask = f[2]
			c.area = _area(d, w)
			c.cmp = _cmp(d, w)
			c.value = p.int_of(d, "value", 0, 100000, 0, w, true)
		DefMissionCond.Op.STRUCTURE:
			_structure(c, d, w)
		DefMissionCond.Op.AREA_LEFT:
			_owner(c, d, w, false)
			var f2: PackedInt32Array = _filter(d, w, true)
			c.of_kind = f2[0]
			c.def_idx = f2[1]
			c.tag_mask = f2[2]
			c.area = _area(d, w, "area", true)
			c.ref = p.m.latches
			p.m.latches += 1
		DefMissionCond.Op.CREDITS, DefMissionCond.Op.POWER:
			_owner(c, d, w, false)
			c.cmp = _cmp(d, w)
			c.value = p.int_of(d, "value", -100000, 1000000, 0, w, true)
		DefMissionCond.Op.RESEARCH:
			_owner(c, d, w, true)
			var rid: String = p.str_of(d, "research", 1, 80, "", w, true)
			c.ref = p.data.research_idx(rid)
			if c.ref < 0:
				p.fail("V-MIS-03", w, "unknown research '%s'" % rid)
		DefMissionCond.Op.SUPPORT_POWER:
			_owner(c, d, w, true)
			c.ref = p.int_of(d, "slot", 0, 2, 0, w, true)
			c.state = _state_of(d, w, PackedStringArray(["ready", "used"]))
			c.value = 1
		DefMissionCond.Op.SUPERWEAPON:
			_owner(c, d, w, true)
			c.state = _state_of(d, w, PackedStringArray(["fired", "ready"]))
		DefMissionCond.Op.DEFEATED, DefMissionCond.Op.NO_ASSETS:
			_owner(c, d, w, false)
		DefMissionCond.Op.WAVE:
			c.ref = p.ref_of(p.wave_ix, "wave", "wave", d, w)
			c.state = _state_of(d, w, PackedStringArray(["spawned", "cleared"]))
		DefMissionCond.Op.TRIGGER:
			c.ref = p.ref_of(p.trig_ix, "trigger", "trigger", d, w)
			c.cmp = _cmp(d, w)
			c.value = p.int_of(d, "value", 0, 100000, 1, w)
	return c


func _state_of(d: Dictionary, w: String, names: PackedStringArray) -> int:
	var s: String = p.str_of(d, "state", 1, 12, "", w, true)
	var i: int = names.find(s)
	if i < 0 and s != "":
		p.fail("V-MIS-02", w, "state must be one of %s" % ", ".join(names))
	return maxi(i, 0)


func _owner(c: Object, d: Dictionary, w: String, single: bool, allow_neutral: bool = false, key: String = "owner") -> void:
	if not d.has(key):
		p.fail("V-MIS-02", w, "missing required field '%s'" % key)
		return
	var sel: PackedInt32Array = p.owner_sel(d[key], w + "." + key, single, allow_neutral)
	if sel.is_empty():
		return
	c.set("owner_mode", sel[0])
	c.set("owner_val", sel[1])


func _structure(c: DefMissionCond, d: Dictionary, w: String) -> void:
	c.state = _state_of(d, w, STRUCT_STATES)
	c.of_kind = DefMissionCond.OF_STRUCTURE
	if d.has("placed"):
		c.ref = p.ref_of(p.placed_ix, "placed structure", "placed", d, w)
		if d.has("def"):
			p.fail("V-MIS-05", w, "give 'placed' or 'def', not both")
		c.owner_mode = -1  # no owner constraint
		if d.has("owner"):
			_owner(c, d, w, true)
	else:
		if c.state >= 2:
			p.fail("V-MIS-05", w, "state %s needs a 'placed' id" % STRUCT_STATES[c.state])
		_owner(c, d, w, false)
		var f: PackedInt32Array = _filter({"def": d.get("def", "")} if d.has("def") else {}, w)
		if not d.has("def") or f[0] != DefMissionCond.OF_STRUCTURE:
			p.fail("V-MIS-05", w, "needs a structure 'def' or a 'placed' id")
		c.def_idx = f[1]


# ---------------------------------------------------------------------------------------------------- actions
func action(d: Dictionary, w: String) -> DefMissionAction:
	var a: DefMissionAction = DefMissionAction.new()
	var name: String = p.str_of(d, "do", 1, 20, "", w, true)
	a.op = DefMissionAction.OP_NAMES.find(name)
	if a.op < 0:
		p.fail("V-MIS-05", w, "unknown action '%s'" % name)
		return a
	match a.op:
		DefMissionAction.Op.SET_OBJECTIVE:
			p.check_keys(d, ["do", "objective", "state"], w)
			a.ref = p.ref_of(p.obj_ix, "objective", "objective", d, w)
			a.value = _state_of(d, w, DefMissionObjective.STATE_NAMES)
		DefMissionAction.Op.SHOW_MESSAGE:
			p.check_keys(d, ["do", "message", "announcer"], w)
			a.ref = p.ref_of(p.msg_ix, "message", "message", d, w)
			a.announcer = p.str_of(d, "announcer", 0, 60, "", w)
		DefMissionAction.Op.TIMER_START:
			p.check_keys(d, ["do", "timer", "seconds"], w)
			a.ref = p.ref_of(p.timer_ix, "timer", "timer", d, w)
			a.value = p.int_of(d, "seconds", 1, 36000, 0, w) * SimConfig.TPS
		DefMissionAction.Op.TIMER_STOP:
			p.check_keys(d, ["do", "timer"], w)
			a.ref = p.ref_of(p.timer_ix, "timer", "timer", d, w)
		DefMissionAction.Op.SPAWN_UNITS:
			_spawn_units(a, d, w)
		DefMissionAction.Op.SPAWN_STRUCTURE:
			_spawn_structure(a, d, w)
		DefMissionAction.Op.GIVE_CREDITS:
			p.check_keys(d, ["do", "owner", "amount"], w)
			_owner(a, d, w, true)
			a.value = p.int_of(d, "amount", -100000, 100000, 0, w, true)
			if a.value == 0:
				p.fail("V-MIS-02", w, "amount must not be 0")
		DefMissionAction.Op.GRANT_POWER, DefMissionAction.Op.LOCK_POWER:
			p.check_keys(d, ["do", "owner", "slot"], w)
			_owner(a, d, w, true)
			a.value = p.int_of(d, "slot", 0, 2, 0, w, true)
		DefMissionAction.Op.REVEAL_AREA:
			p.check_keys(d, ["do", "owner", "area", "seconds"], w)
			_owner(a, d, w, false)
			if a.owner_mode != DefMissionCond.OWN_PID and a.owner_mode != DefMissionCond.OWN_TEAM:
				p.fail("V-MIS-05", w, "reveal_area needs a slot or team:N")
			a.area = _area(d, w, "area", true)
			a.value = p.int_of(d, "seconds", 1, 3600, 10, w) * SimConfig.TPS
		DefMissionAction.Op.CHANGE_AI:
			_change_ai(a, d, w)
		DefMissionAction.Op.TRANSFER, DefMissionAction.Op.DESTROY:
			_target_action(a, d, w)
		DefMissionAction.Op.ORDER_UNITS:
			p.check_keys(d, ["do", "owner", "area", "def", "tag", "order"], w)
			_owner(a, d, w, false)
			var f: PackedInt32Array = _filter(d, w, true)
			a.of_kind = f[0]
			a.def_idx = f[1]
			a.tag_mask = f[2]
			a.area = _area(d, w)
			_order(a, d, w, true)
		DefMissionAction.Op.ELIMINATE, DefMissionAction.Op.WIN, DefMissionAction.Op.LOSE:
			p.check_keys(d, ["do", "owner"], w)
			_owner(a, d, w, true)
		DefMissionAction.Op.TRIGGER_ENABLE, DefMissionAction.Op.TRIGGER_DISABLE:
			p.check_keys(d, ["do", "trigger"], w)
			a.ref = p.ref_of(p.trig_ix, "trigger", "trigger", d, w)
		DefMissionAction.Op.CAMERA_HINT:
			_camera_hint(a, d, w)
		DefMissionAction.Op.MUSIC_STATE:
			p.check_keys(d, ["do", "state"], w)
			a.value = _state_of(d, w, DefMissionAction.MUSIC_NAMES)
	return a


func _spawn_units(a: DefMissionAction, d: Dictionary, w: String) -> void:
	p.check_keys(d, ["do", "owner", "def", "count", "area", "wave", "order", "facing"], w)
	_owner(a, d, w, true, true)
	var id: String = p.str_of(d, "def", 1, 80, "", w, true)
	a.def_idx = p.data.unit_idx(id) if id != "" else -1
	if id != "" and a.def_idx < 0:
		p.fail("V-MIS-03", w, "unknown unit '%s'" % id)
	a.of_kind = DefMissionCond.OF_UNIT
	a.count = p.int_of(d, "count", 1, 64, 1, w)
	a.area = _area(d, w, "area", true)
	a.value = p.int_of(d, "facing", 0, 4095, 0, w)
	if d.has("wave"):
		a.wave = p.ref_of(p.wave_ix, "wave", "wave", d, w)
	if d.has("order"):
		_order(a, d, w, false)


func _spawn_structure(a: DefMissionAction, d: Dictionary, w: String) -> void:
	p.check_keys(d, ["do", "owner", "def", "area", "cell", "id", "facing"], w)
	_owner(a, d, w, true, true)
	var id: String = p.str_of(d, "def", 1, 80, "", w, true)
	a.def_idx = p.data.structure_idx(id) if id != "" else -1
	if id != "" and a.def_idx < 0:
		p.fail("V-MIS-03", w, "unknown structure '%s'" % id)
	a.of_kind = DefMissionCond.OF_STRUCTURE
	a.value = p.int_of(d, "facing", 0, 3, 0, w)
	if d.has("area") == d.has("cell"):
		p.fail("V-MIS-05", w, "give exactly one of 'area' or 'cell'")
	if d.has("area"):
		a.area = _area(d, w, "area", true)
	elif d.has("cell"):
		_cell(a, d["cell"], w)
	if d.has("id"):
		a.placed = p.ref_of(p.placed_ix, "placed id", "id", d, w)


func _cell(a: DefMissionAction, v: Variant, w: String) -> void:
	if v is Array and (v as Array).size() == 2 and DefNumParse.is_integral((v as Array)[0]) and DefNumParse.is_integral((v as Array)[1]):
		a.cell_x = DefNumParse.whole((v as Array)[0], w, p.rep)
		a.cell_y = DefNumParse.whole((v as Array)[1], w, p.rep)
		if a.cell_x < 0 or a.cell_x > 255 or a.cell_y < 0 or a.cell_y > 255:
			p.fail("V-MIS-02", w, "cell must be inside 0..255")
	else:
		p.fail("V-MIS-02", w, "cell must be [x, y] (integers)")


func _order(a: DefMissionAction, d: Dictionary, w: String, required: bool) -> void:
	if not d.has("order"):
		if required:
			p.fail("V-MIS-02", w, "missing required field 'order'")
		return
	var od: Dictionary = p.entry(d["order"], w + ".order")
	p.check_keys(od, ["kind", "area"], w + ".order")
	var kind: String = p.str_of(od, "kind", 1, 12, "", w + ".order", true)
	a.order = DefMissionAction.ORDER_NAMES.find(kind)
	if a.order <= 0:
		p.fail("V-MIS-02", w, "order kind must be move, attack_move, guard or hold")
		a.order = 0
		return
	if a.order == DefMissionAction.ORD_HOLD:
		if od.has("area"):
			p.fail("V-MIS-05", w, "a hold order takes no area")
	else:
		a.order_area = _area(od, w + ".order", "area", true)


func _change_ai(a: DefMissionAction, d: Dictionary, w: String) -> void:
	p.check_keys(d, ["do", "owner", "active", "level", "style", "aggression"], w)
	_owner(a, d, w, true)
	if a.owner_mode == DefMissionCond.OWN_PID:
		var pl: DefMissionPlayer = p.slots.get(a.owner_val)
		if pl != null and pl.human:
			p.fail("V-MIS-05", w, "change_ai needs an AI player")
	if d.has("active"):
		a.ai_active = 1 if p.bool_of(d, "active", true, w) else 0
	a.ai_level = p.int_of(d, "level", 0, 15, -1, w)
	a.ai_style = p.int_of(d, "style", 0, 15, -1, w)
	a.ai_aggr = p.int_of(d, "aggression", 0, 100, -1, w)
	if a.ai_active < 0 and a.ai_level < 0 and a.ai_style < 0 and a.ai_aggr < 0:
		p.fail("V-MIS-05", w, "change_ai changes nothing")


func _target_action(a: DefMissionAction, d: Dictionary, w: String) -> void:
	var keys: PackedStringArray = ["do", "placed", "owner", "area", "def", "tag", "of"]
	if a.op == DefMissionAction.Op.TRANSFER:
		keys.append("to")
	p.check_keys(d, keys, w)
	if a.op == DefMissionAction.Op.TRANSFER:
		if not d.has("to"):
			p.fail("V-MIS-02", w, "missing required field 'to'")
		else:
			var sel: PackedInt32Array = p.owner_sel(d["to"], w + ".to", true, true)
			if not sel.is_empty():
				a.to_pid = sel[1]
	if d.has("placed"):
		for k: String in ["owner", "area", "def", "tag", "of"]:
			if d.has(k):
				p.fail("V-MIS-05", w, "'placed' cannot be combined with '%s'" % k)
		a.placed = p.ref_of(p.placed_ix, "placed id", "placed", d, w)
		return
	_owner(a, d, w, false, true)
	var f: PackedInt32Array = _filter(d, w)
	a.of_kind = f[0]
	a.def_idx = f[1]
	a.tag_mask = f[2]
	a.area = _area(d, w)
	if not d.has("def") and not d.has("tag") and not d.has("of") and not d.has("area"):
		p.fail("V-MIS-05", w, "this action needs a 'placed' id or a filter (def / tag / of / area)")


func _camera_hint(a: DefMissionAction, d: Dictionary, w: String) -> void:
	p.check_keys(d, ["do", "area", "cell", "seconds"], w)
	if d.has("area") == d.has("cell"):
		p.fail("V-MIS-05", w, "give exactly one of 'area' or 'cell'")
	if d.has("area"):
		a.area = _area(d, w, "area", true)
	elif d.has("cell"):
		_cell(a, d["cell"], w)
	a.value = p.int_of(d, "seconds", 1, 600, 5, w) * SimConfig.TPS
