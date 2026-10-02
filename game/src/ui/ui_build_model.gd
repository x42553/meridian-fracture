class_name UiBuildModel
extends RefCounted
## The 8 sidebar tabs as lists of `UiBuildItem` (ui.md 5.10.2) and their state derivation from the `UiSimPort`
## (5.10.4). `rebuild` creates the static structure of a roster; `refresh` re-derives states at 2 Hz;
## `refresh_progress` updates only progress / ETA of items in production at 20 Hz. Items whose displayed values
## changed are collected in `changed` (the presenter drains it and refreshes the cards). Pure: never mutates the sim.

enum Tab { STRUCTURES = 0, DEFENSE = 1, INFANTRY = 2, VEHICLES = 3, AIRCRAFT = 4, NAVAL = 5, RESEARCH = 6, POWERS = 7 }
const TAB_COUNT: int = 8
const TAB_TITLES: PackedStringArray = ["STRUCTURES", "DEFENSE", "INFANTRY", "VEHICLES", "AIRCRAFT", "NAVAL", "RESEARCH", "POWERS"]
const TAB_IDS: Array[StringName] = [&"structures", &"defense", &"infantry", &"vehicles", &"aircraft", &"naval", &"research", &"powers"]
const TAB_GLYPHS: PackedInt32Array = [0, 5, 1, 2, 3, 4, 24, 6]
## Alt + these keys for the grid slots 0..11 (`card_1`..`card_12`).
const CARD_KEYS: PackedStringArray = ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"]
const MIN_SLOTS: int = 12

## The structure card currently in placement (set by the presenter from `UiPlacement`): PLACING instead of READY.
var placing_def: int = -1
## Items whose visible values changed since the last `take_changed()`.
var changed: Array[UiBuildItem] = []

var _tabs: Array = []  ## Array of Array[UiBuildItem]
var _by_key: Dictionary = {}  ## kind * 65536 + def_idx -> UiBuildItem
var _sig: Dictionary = {}  ## UiBuildItem -> int
var _data: GameData = null
var _roster: DefRoster = null
var _owned: Dictionary = {}  ## structure def -> completed count
var _cs: PackedInt32Array = PackedInt32Array()
var _cq: PackedInt32Array = PackedInt32Array()
var _rs: PackedInt32Array = PackedInt32Array()
var _q: PackedInt32Array = PackedInt32Array()
var _qi: PackedInt32Array = PackedInt32Array()
var _tmp: PackedInt32Array = PackedInt32Array()
var _row: UiEntityRow = UiEntityRow.new()
var _credits: int = 0
var _tick: int = 0
var _low_power: bool = false


static func tab_of_queue_kind(queue_kind: int) -> int:
	match queue_kind:
		DefEnums.QueueKind.INFANTRY:
			return Tab.INFANTRY
		DefEnums.QueueKind.AIRCRAFT:
			return Tab.AIRCRAFT
		DefEnums.QueueKind.NAVAL:
			return Tab.NAVAL
	return Tab.VEHICLES  ## VEHICLE and COLLECTOR (the Collector sits with the factory units)


## Builds the eight tabs for `roster` (static per roster). `port` supplies GameData.
func rebuild(port: UiSimPort, roster: DefRoster) -> void:
	_data = port.data()
	_roster = roster
	_tabs.clear()
	_by_key.clear()
	_sig.clear()
	changed.clear()
	for i: int in TAB_COUNT:
		var arr: Array[UiBuildItem] = []
		_tabs.append(arr)
	if roster == null or _data == null:
		return
	for si: int in roster.producible_structures:
		var s: DefStructure = roster.structures[si]
		if s == null:
			continue
		var it: UiBuildItem = _new_item(UiBuildItem.Kind.STRUCTURE, si, s)
		it.cost = s.cost
		it.total_seconds = float(s.build_ticks) / 20.0
		it.power_delta = s.power
		it.tier = 0
		it.glyph = UiGlyphs.Glyph.STRUCTURES
		it.role_glyph = UiGlyphs.role_glyph_structure(s)
		it.tab = Tab.DEFENSE if (s.tags & (DefEnums.ST_DEFENSE | DefEnums.ST_ADVANCED_DEFENSE)) != 0 else Tab.STRUCTURES
		if (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
			it.glyph = UiGlyphs.Glyph.MISSILE
		_add(it)
	for ui: int in roster.producible_units:
		var u: DefUnit = roster.units[ui]
		if u == null:
			continue
		var it2: UiBuildItem = _new_item(UiBuildItem.Kind.UNIT, ui, u)
		it2.cost = u.cost
		it2.total_seconds = float(u.build_ticks) / 20.0
		it2.tier = clampi(u.tier, 1, 3)
		var prod: DefStructure = roster.structures[u.producer] if u.producer >= 0 and u.producer < roster.structures.size() else null
		it2.queue_kind = prod.queue_kind if prod != null else DefEnums.QueueKind.VEHICLE
		it2.tab = tab_of_queue_kind(it2.queue_kind)
		it2.glyph = TAB_GLYPHS[it2.tab]
		it2.role_glyph = UiGlyphs.role_glyph_unit(u)
		it2.replaced_by_roster = u.unit_class == DefEnums.UnitClass.UNIQUE
		_add(it2)
	for ri: int in roster.research_list:
		if ri < 0 or ri >= _data.research.size():
			continue
		var r: DefResearch = _data.research[ri]
		var it3: UiBuildItem = _new_item(UiBuildItem.Kind.RESEARCH, ri, r)
		it3.cost = r.cost
		it3.total_seconds = float(r.time_t) / 20.0
		it3.tier = clampi(r.tier, 1, 3)
		it3.tab = Tab.RESEARCH
		it3.glyph = UiGlyphs.Glyph.GEAR
		it3.role_glyph = UiGlyphs.Glyph.GEAR
		it3.description = r.ui_effect_text if r.ui_effect_text != "" else r.ui_text
		_add(it3)
	if roster.superweapon >= 0 and roster.superweapon_def != null:
		var sw: DefSuperweapon = roster.superweapon_def
		var it4: UiBuildItem = _new_item(UiBuildItem.Kind.SUPERWEAPON, roster.superweapon, sw)
		it4.tier = 3
		it4.total_seconds = float(sw.recharge_t) / 20.0
		it4.tab = Tab.POWERS
		it4.glyph = UiGlyphs.Glyph.MISSILE
		it4.role_glyph = UiGlyphs.Glyph.MISSILE
		it4.power_idx = roster.superweapon
		_add(it4)
	for pi: int in roster.power_list:
		if pi < 0 or pi >= _data.powers.size():
			continue
		var p: DefPower = _data.powers[pi]
		var it5: UiBuildItem = _new_item(UiBuildItem.Kind.POWER, pi, p)
		it5.cost = p.cost
		it5.tier = 0
		it5.total_seconds = float(p.cooldown_t) / 20.0
		it5.tab = Tab.POWERS
		it5.glyph = UiGlyphs.Glyph.POWERS
		it5.role_glyph = UiGlyphs.Glyph.POWERS
		it5.power_idx = pi
		it5.target_mode = p.target_mode
		it5.description = p.ui_effect_text if p.ui_effect_text != "" else p.ui_text
		_add(it5)
	for t: int in TAB_COUNT:
		var arr2: Array = _tabs[t]
		for i2: int in arr2.size():
			var item: UiBuildItem = arr2[i2]
			item.slot = i2
			item.hotkey_label = UiKeymap.instance().label(StringName("card_%d" % (i2 + 1))) if i2 < CARD_KEYS.size() else ""  # "Option+Q" on macOS


func items(tab: int) -> Array[UiBuildItem]:
	if tab < 0 or tab >= _tabs.size():
		return []
	var out: Array[UiBuildItem] = []
	out.assign(_tabs[tab] as Array)
	return out


func item_for(kind: int, def_idx: int) -> UiBuildItem:
	return _by_key.get(_key(kind, def_idx)) as UiBuildItem


## Items drained by the presenter after a refresh.
func take_changed() -> Array[UiBuildItem]:
	var out: Array[UiBuildItem] = changed
	changed = []
	return out


## Number of READY structure cards + finished-looking cards of a tab (the tab badge).
func ready_count(tab: int) -> int:
	var n: int = 0
	for it: UiBuildItem in items(tab):
		if it.state == UiBuildItem.State.READY or (it.kind == UiBuildItem.Kind.POWER or it.kind == UiBuildItem.Kind.SUPERWEAPON) and it.state == UiBuildItem.State.AVAILABLE:
			n += 1
	return n


## Tab that holds the structure def (or unit producer) named by a "Needs X" requirement, for the 1.5 s pulse.
func tab_of_structure(struct_def: int) -> int:
	var it: UiBuildItem = item_for(UiBuildItem.Kind.STRUCTURE, struct_def)
	return it.tab if it != null else Tab.STRUCTURES


# ---- refresh ----------------------------------------------------------------------------------------------------------
## Re-derives every card state (2 Hz and after the relevant events). `selected_producers` = selected producer eids.
func refresh(port: UiSimPort, selected_producers: PackedInt32Array = PackedInt32Array()) -> void:
	if _roster == null:
		return
	_credits = port.credits()
	_tick = port.tick()
	_low_power = port.power_demand() > port.power_supply()
	_scan_owned(port)
	port.construction_state(_cs)
	port.construction_queue(_cq)
	port.research_state(_rs)
	for t: int in TAB_COUNT:
		for it: UiBuildItem in (_tabs[t] as Array):
			match it.kind:
				UiBuildItem.Kind.STRUCTURE:
					_derive_structure(port, it)
				UiBuildItem.Kind.UNIT:
					_derive_unit(port, it, selected_producers)
				UiBuildItem.Kind.RESEARCH:
					_derive_research(port, it)
				UiBuildItem.Kind.POWER:
					_derive_power(port, it)
				UiBuildItem.Kind.SUPERWEAPON:
					_derive_superweapon(port, it)
			_note(it)


## 20 Hz: progress, ETA and rate of items in production / cooling down; states are left to `refresh`.
func refresh_progress(port: UiSimPort) -> void:
	if _roster == null:
		return
	_tick = port.tick()
	port.construction_state(_cs)
	port.research_state(_rs)
	for t: int in TAB_COUNT:
		for it: UiBuildItem in (_tabs[t] as Array):
			if not it.is_sweeping():
				continue
			match it.kind:
				UiBuildItem.Kind.STRUCTURE:
					if _cs[UiSimPort.CS_DEF] == it.def_idx:
						it.progress_permille = _cs[UiSimPort.CS_PROGRESS]
						it.eta_ticks = _cs[UiSimPort.CS_ETA]
						it.rate_pct = _cs[UiSimPort.CS_RATE]
				UiBuildItem.Kind.UNIT:
					if it.producer_eid > 0:
						port.queue_info(it.producer_eid, _qi)
						it.progress_permille = _qi[UiSimPort.QI_PROGRESS]
						it.eta_ticks = _qi[UiSimPort.QI_ETA]
						it.rate_pct = _qi[UiSimPort.QI_RATE]
				UiBuildItem.Kind.RESEARCH:
					if _rs.size() > 2 and _rs[0] == it.def_idx:
						it.progress_permille = _rs[1]
						it.eta_ticks = _rs[2]
				UiBuildItem.Kind.POWER:
					_power_progress(port, it)
				UiBuildItem.Kind.SUPERWEAPON:
					it.progress_permille = port.sw_charge_permille()
					it.eta_ticks = maxi(port.sw_ready_tick() - _tick, 0) if port.sw_status() == UiSimPort.SwStatus.CHARGING else -1
			_note(it)


func _scan_owned(port: UiSimPort) -> void:
	_owned.clear()
	port.own_ids(UiSimPort.KM_STRUCTURE, _tmp)
	for id: int in _tmp:
		if port.read(id, _row) and (_row.flags & (UiEntityRow.F_CONSTRUCTING | UiEntityRow.F_GHOST)) == 0:
			_owned[_row.def_idx] = int(_owned.get(_row.def_idx, 0)) + 1


func _derive_structure(port: UiSimPort, it: UiBuildItem) -> void:
	_reset_dynamic(it)
	var st: int = _cs[UiSimPort.CS_STATE]
	var head: int = _cs[UiSimPort.CS_DEF]
	var qs: int = _cs[UiSimPort.CS_QSTATE]
	it.queue_state = qs
	if st != UiSimPort.Construction.IDLE and head == it.def_idx:
		if st == UiSimPort.Construction.READY_TO_PLACE:
			it.state = UiBuildItem.State.PLACING if placing_def == it.def_idx else UiBuildItem.State.READY
			it.progress_permille = 1000
			it.eta_ticks = 0
			it.queued = 1
			return
		it.progress_permille = _cs[UiSimPort.CS_PROGRESS]
		it.eta_ticks = _cs[UiSimPort.CS_ETA]
		it.rate_pct = _cs[UiSimPort.CS_RATE]
		it.queued = 1 + _count_in(_cq, it.def_idx)
		if qs == UiSimPort.QueueState.HELD:
			it.state = UiBuildItem.State.ON_HOLD
		elif qs == UiSimPort.QueueState.PREREQ_LOST or qs == UiSimPort.QueueState.SHUTDOWN or st == UiSimPort.Construction.PAUSED:
			it.state = UiBuildItem.State.BLOCKED
			it.reason_text = _queue_reason(qs)
		else:
			it.state = UiBuildItem.State.BUILDING
			it.reason_text = _queue_reason(qs) if qs != UiSimPort.QueueState.RUNNING else ""
		return
	var behind: int = _count_in(_cq, it.def_idx)
	if behind > 0:
		it.state = UiBuildItem.State.QUEUED
		it.queued = behind
		return
	var r: int = port.check_build(it.def_idx)
	it.blocked_reason = r
	if r == UiSimPort.Rule.NO_PREREQ or r == UiSimPort.Rule.NOT_AVAILABLE:
		it.state = UiBuildItem.State.LOCKED
		it.requires_text = _missing_text(_roster.structures[it.def_idx].requires)
		if r == UiSimPort.Rule.NOT_AVAILABLE and (_roster.structures[it.def_idx].flags & DefEnums.SF_STRATEGIC) != 0:
			it.requires_text = "Already built"
		return
	if r == UiSimPort.Rule.QUEUE_FULL:
		it.state = UiBuildItem.State.BLOCKED
		it.reason_text = "Construction queue full"
		return
	it.state = UiBuildItem.State.UNAFFORDABLE if _credits < it.cost else UiBuildItem.State.AVAILABLE


func _derive_unit(port: UiSimPort, it: UiBuildItem, selected: PackedInt32Array) -> void:
	_reset_dynamic(it)
	var u: DefUnit = _roster.units[it.def_idx]
	var prods: PackedInt32Array = PackedInt32Array()
	port.producers(it.queue_kind, prods)
	if prods.is_empty():
		it.state = UiBuildItem.State.LOCKED
		it.requires_text = _missing_text(u.requires if u != null else PackedInt32Array())
		if it.requires_text == "" and u != null and u.producer >= 0:
			it.requires_text = _struct_name(u.producer)
		it.blocked_reason = UiSimPort.Rule.NO_PREREQ
		return
	var p: int = UiProducerPicker.pick(port, it.queue_kind, it.def_idx, selected)
	if p < 0:
		var r0: int = port.check_train(prods[0], it.def_idx)
		it.blocked_reason = r0
		if r0 == UiSimPort.Rule.NO_PREREQ or r0 == UiSimPort.Rule.NOT_AVAILABLE:
			it.state = UiBuildItem.State.LOCKED
			it.requires_text = _missing_text(u.requires if u != null else PackedInt32Array())
		else:
			it.state = UiBuildItem.State.BLOCKED
			it.reason_text = "Queue full" if r0 == UiSimPort.Rule.QUEUE_FULL else "Cannot train now"
		return
	it.producer_eid = p
	var n: int = port.queue_of(p, _q)
	port.queue_info(p, _qi)
	var qs: int = _qi[UiSimPort.QI_QSTATE]
	it.queue_state = qs
	var count: int = _count_in(_q, it.def_idx)
	if n > 0 and _q[0] == it.def_idx:
		it.queued = count
		it.progress_permille = _qi[UiSimPort.QI_PROGRESS]
		it.eta_ticks = _qi[UiSimPort.QI_ETA]
		it.rate_pct = _qi[UiSimPort.QI_RATE]
		if qs == UiSimPort.QueueState.HELD:
			it.state = UiBuildItem.State.ON_HOLD
		elif qs == UiSimPort.QueueState.PREREQ_LOST or qs == UiSimPort.QueueState.UNIT_CAP or qs == UiSimPort.QueueState.EXIT_BLOCKED or qs == UiSimPort.QueueState.SHUTDOWN:
			it.state = UiBuildItem.State.BLOCKED
			it.reason_text = _queue_reason(qs)
		else:
			it.state = UiBuildItem.State.BUILDING
			it.reason_text = _queue_reason(qs) if qs != UiSimPort.QueueState.RUNNING else ""
		return
	if count > 0:
		it.state = UiBuildItem.State.QUEUED
		it.queued = count
		return
	it.state = UiBuildItem.State.UNAFFORDABLE if _credits < it.cost else UiBuildItem.State.AVAILABLE


func _derive_research(port: UiSimPort, it: UiBuildItem) -> void:
	_reset_dynamic(it)
	if port.research_done(it.def_idx):
		it.state = UiBuildItem.State.DONE
		return
	var active: int = _rs[0] if _rs.size() > 0 else -1
	var qs: int = _rs[3] if _rs.size() > 3 else 0
	it.queue_state = qs
	if active == it.def_idx:
		it.progress_permille = _rs[1]
		it.eta_ticks = _rs[2]
		it.queued = 1
		if qs == UiSimPort.QueueState.HELD:
			it.state = UiBuildItem.State.ON_HOLD
		elif qs == UiSimPort.QueueState.PREREQ_LOST or qs == UiSimPort.QueueState.SHUTDOWN:
			it.state = UiBuildItem.State.BLOCKED
			it.reason_text = _queue_reason(qs)
		else:
			it.state = UiBuildItem.State.BUILDING
			it.reason_text = _queue_reason(qs) if qs != UiSimPort.QueueState.RUNNING else ""
		return
	var queued_n: int = _rs[4] if _rs.size() > 4 else 0
	for i: int in queued_n:
		if _rs.size() > 5 + i and _rs[5 + i] == it.def_idx:
			it.state = UiBuildItem.State.QUEUED
			it.queued = 1
			return
	var r: int = port.check_research(it.def_idx)
	it.blocked_reason = r
	if r == UiSimPort.Rule.NO_PREREQ or r == UiSimPort.Rule.NOT_AVAILABLE:
		it.state = UiBuildItem.State.LOCKED
		var rd: DefResearch = _data.research[it.def_idx]
		it.requires_text = _mask_text(rd.requires_mask)
		return
	it.state = UiBuildItem.State.UNAFFORDABLE if _credits < it.cost else UiBuildItem.State.AVAILABLE


func _derive_power(port: UiSimPort, it: UiBuildItem) -> void:
	_reset_dynamic(it)
	var s: int = port.power_status(it.def_idx)
	var slot: int = port.power_slot(it.def_idx)
	if slot >= 0:
		it.hotkey_label = UiKeymap.instance().label(StringName("power_%d" % (slot + 1)))
	match s:
		UiSimPort.PowerStatus.READY:
			it.state = UiBuildItem.State.AVAILABLE
		UiSimPort.PowerStatus.COOLDOWN:
			it.state = UiBuildItem.State.COOLDOWN
			_power_progress(port, it)
		UiSimPort.PowerStatus.LOCKED_PREREQ:
			it.state = UiBuildItem.State.LOCKED
			it.requires_text = _mask_text((_data.powers[it.def_idx] as DefPower).requires_mask)
		UiSimPort.PowerStatus.UNPOWERED:
			it.state = UiBuildItem.State.BLOCKED
			it.reason_text = "Offline: low power"
		UiSimPort.PowerStatus.NO_CREDITS:
			it.state = UiBuildItem.State.UNAFFORDABLE


func _power_progress(port: UiSimPort, it: UiBuildItem) -> void:
	var total: int = maxi(port.power_total_cooldown_ticks(it.def_idx), 1)
	var remaining: int = maxi(port.power_ready_tick(it.def_idx) - _tick, 0)
	it.progress_permille = clampi(1000 - remaining * 1000 / total, 0, 1000)
	it.eta_ticks = remaining
	it.total_seconds = float(total) / 20.0


func _derive_superweapon(port: UiSimPort, it: UiBuildItem) -> void:
	_reset_dynamic(it)
	var sw: DefSuperweapon = _roster.superweapon_def
	it.hotkey_label = UiKeymap.instance().label(&"superweapon")
	match port.sw_status():
		UiSimPort.SwStatus.NONE:
			it.state = UiBuildItem.State.LOCKED
			it.requires_text = _struct_name(sw.launcher) if sw != null else ""
		UiSimPort.SwStatus.CHARGING:
			it.progress_permille = port.sw_charge_permille()
			it.eta_ticks = maxi(port.sw_ready_tick() - _tick, 0)
			if _low_power:
				it.state = UiBuildItem.State.BLOCKED
				it.reason_text = "No power: recharge paused"
			else:
				it.state = UiBuildItem.State.COOLDOWN
		UiSimPort.SwStatus.READY:
			it.state = UiBuildItem.State.AVAILABLE
			it.progress_permille = 1000
		UiSimPort.SwStatus.WARNING:
			it.state = UiBuildItem.State.ON_HOLD
			it.reason_text = "LAUNCHING"
			it.progress_permille = 1000


func _reset_dynamic(it: UiBuildItem) -> void:
	it.state = UiBuildItem.State.AVAILABLE
	it.progress_permille = 0
	it.eta_ticks = -1
	it.rate_pct = 100
	it.queued = 0
	it.blocked_reason = 0
	it.queue_state = 0
	it.requires_text = ""
	it.reason_text = ""
	it.producer_eid = -1


func _queue_reason(qs: int) -> String:
	match qs:
		UiSimPort.QueueState.WAIT_FUNDS:
			return "Waiting for credits"
		UiSimPort.QueueState.UNIT_CAP:
			return "Unit cap reached"
		UiSimPort.QueueState.LOW_POWER:
			return "Low power: half speed"
		UiSimPort.QueueState.PREREQ_LOST:
			return "Prerequisite lost"
		UiSimPort.QueueState.HELD:
			return "On hold"
		UiSimPort.QueueState.EXIT_BLOCKED:
			return "Exit blocked"
		UiSimPort.QueueState.SHUTDOWN:
			return "Producer offline"
	return ""


## "Radar + Laboratory": the required structures the viewer does not own (all of them when nothing is owned).
func _missing_text(requires: PackedInt32Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for si: int in requires:
		if int(_owned.get(si, 0)) == 0:
			names.append(_struct_name(si))
	return " + ".join(names)


func _mask_text(mask: int) -> String:
	var names: PackedStringArray = PackedStringArray()
	for si: int in 62:
		if (mask >> si) & 1 == 1 and int(_owned.get(si, 0)) == 0:
			names.append(_struct_name(si))
	return " + ".join(names)


func _struct_name(si: int) -> String:
	if _roster != null:
		var s: DefStructure = _roster.structure(si)
		if s != null:
			return s.ui_name
	if _data != null and si >= 0 and si < _data.structures.size():
		return _data.structures[si].ui_name
	return "?"


func _new_item(kind: int, def_idx: int, d: DefBase) -> UiBuildItem:
	var it := UiBuildItem.new()
	it.kind = kind
	it.def_idx = def_idx
	it.id = d.id
	it.display_name = d.ui_name if d.ui_name != "" else d.id
	it.description = d.ui_text
	if d is DefUnit:
		it.recipe = (d as DefUnit).pres_recipe
	elif d is DefStructure:
		it.recipe = (d as DefStructure).pres_recipe
	return it


func _add(it: UiBuildItem) -> void:
	(_tabs[it.tab] as Array).append(it)
	_by_key[_key(it.kind, it.def_idx)] = it


static func _key(kind: int, def_idx: int) -> int:
	return kind * 65536 + def_idx


static func _count_in(arr: PackedInt32Array, def_idx: int) -> int:
	var n: int = 0
	for v: int in arr:
		if v == def_idx:
			n += 1
	return n


func _note(it: UiBuildItem) -> void:
	var sig: int = hash([it.state, it.progress_permille, it.queued, it.blocked_reason, it.queue_state, it.remaining_whole_seconds(), it.rate_pct, it.producer_eid, it.requires_text, it.reason_text, _credits >= it.cost])
	if int(_sig.get(it, -1)) != sig:
		_sig[it] = sig
		if not changed.has(it):
			changed.append(it)


# ---- tooltips ---------------------------------------------------------------------------------------------------------
## `UiTooltipBody` spec of a card (5.10.9): name, tier line, COST / TIME / POWER / HOTKEY, text, requirement, hint.
func tooltip_spec(it: UiBuildItem) -> Dictionary:
	var spec: Dictionary = {"title": it.display_name}
	var tag: String = ""
	match it.kind:
		UiBuildItem.Kind.STRUCTURE:
			tag = "STRUCTURE" if it.tab == Tab.STRUCTURES else "DEFENSE"
		UiBuildItem.Kind.UNIT:
			tag = "TIER %d // %s" % [it.tier, TAB_TITLES[it.tab]]
		UiBuildItem.Kind.RESEARCH:
			tag = "TIER %d // RESEARCH" % it.tier
		UiBuildItem.Kind.POWER:
			tag = "SUPPORT POWER"
		UiBuildItem.Kind.SUPERWEAPON:
			tag = "SUPERWEAPON"
	if it.replaced_by_roster:
		tag += " // UNIQUE"
	spec["tag"] = tag
	var stats: Array[Dictionary] = []
	if it.cost > 0:
		stats.append({"label": "COST", "value": "$" + UiBuildItem.group_digits(it.cost)})
	if it.total_seconds > 0.0:
		var lbl: String = "COOLDOWN" if it.kind == UiBuildItem.Kind.POWER else ("RECHARGE" if it.kind == UiBuildItem.Kind.SUPERWEAPON else "TIME")
		stats.append({"label": lbl, "value": UiBuildItem.mmss(int(ceilf(it.total_seconds)))})
	if it.kind == UiBuildItem.Kind.STRUCTURE:
		stats.append({"label": "POWER", "value": "%+d" % it.power_delta, "tone": &"ok" if it.power_delta > 0 else &"warn"})
	if it.hotkey_label != "":
		stats.append({"label": "HOTKEY", "value": it.hotkey_label})
	spec["stats"] = stats
	if it.description != "":
		spec["text"] = it.description
	if it.requires_text != "":
		spec["warn"] = "Requires " + it.requires_text
	elif it.reason_text != "":
		spec["warn"] = it.reason_text
	match it.kind:
		UiBuildItem.Kind.POWER, UiBuildItem.Kind.SUPERWEAPON:
			spec["hint"] = "LMB target"
		UiBuildItem.Kind.RESEARCH:
			spec["hint"] = "LMB research  //  RMB cancel"
		UiBuildItem.Kind.STRUCTURE:
			spec["hint"] = "LMB build / place  //  RMB hold / cancel"
		_:
			spec["hint"] = "LMB build  //  RMB hold / cancel  //  Shift x5"
	return spec
