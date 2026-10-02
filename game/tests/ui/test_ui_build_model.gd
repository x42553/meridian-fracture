extends RefCounted
## Card states of the sidebar build model (ui.md 5.10.2 / 5.10.4, 10.2 `test_ui_build_model`): locked / available /
## unaffordable / building / queued / ready / placing / on hold / blocked, tabs and slots, dirty tracking, producer
## choice, tooltips and the power cards, over the scripted fixture port; plus one REAL-world pass.

const HQ: String = "structure.shared.headquarters"
const BARRACKS: String = "structure.shared.barracks"
const FACTORY: String = "structure.shared.factory"
const RIFLE: String = "unit.napc.rifle_squad"
const TANK: String = "unit.napc.guardian_tank"
const ROSTER: String = "roster.napc.vanilla"

const S := UiBuildItem.State
const K := UiBuildItem.Kind


func _rig(credits: int = 5000) -> Array:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, ROSTER, credits)
	f.add_player(1, "Foe", 2, ROSTER)
	f.set_viewer(0)
	f.spawn(HQ, 0, 20, 20, 1)
	var m := UiBuildModel.new()
	m.rebuild(f, f.roster_of(0))
	m.refresh(f)
	return [f, m]


func _st(f: UiSimPortFixture, m: UiBuildModel, def_id: String) -> UiBuildItem:
	return m.item_for(K.STRUCTURE, f.data().structure_idx(def_id))


func _un(f: UiSimPortFixture, m: UiBuildModel, def_id: String) -> UiBuildItem:
	return m.item_for(K.UNIT, f.data().unit_idx(def_id))


func test_tabs_slots_and_static_fields(t: TestCtx) -> void:
	var r: Array = _rig()
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var total: int = 0
	for tab: int in UiBuildModel.TAB_COUNT:
		var arr: Array[UiBuildItem] = m.items(tab)
		total += arr.size()
		for i: int in arr.size():
			if not t.eq(arr[i].slot, i, "slot = index within tab %d" % tab):
				return
			t.eq(arr[i].tab, tab)
	t.check(total > 20, "a roster has a full card set (%d)" % total)
	var b: UiBuildItem = _st(f, m, BARRACKS)
	t.check(b != null and b.tab == UiBuildModel.Tab.STRUCTURES, "barracks on the structures tab")
	t.eq(b.cost, f.data().structures[b.def_idx].cost)
	t.check(b.hotkey_label.begins_with("Alt+") or b.hotkey_label.begins_with("Option+"), "card hotkey label")
	var rifle: UiBuildItem = _un(f, m, RIFLE)
	t.eq(rifle.tab, UiBuildModel.Tab.INFANTRY)
	t.eq(_un(f, m, TANK).tab, UiBuildModel.Tab.VEHICLES)
	t.check(m.items(99).is_empty(), "unknown tab is empty")


func test_structure_states(t: TestCtx) -> void:
	var r: Array = _rig(300)
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var fac: UiBuildItem = _st(f, m, FACTORY)
	t.eq(fac.state, S.UNAFFORDABLE, "cost > credits")
	f.set_credits(0, 9000)
	m.refresh(f)
	t.eq(fac.state, S.AVAILABLE, "affordable again")
	f.force_rule("check_build", UiSimPort.Rule.NO_PREREQ)
	m.refresh(f)
	t.eq(fac.state, S.LOCKED, "missing prerequisite")
	t.check(fac.is_locked_out())
	f.force_rule("check_build", UiSimPort.Rule.OK)
	# building: head of the construction queue, another def queued behind
	var bar: UiBuildItem = _st(f, m, BARRACKS)
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 250, 600, PackedInt32Array([fac.def_idx]))
	m.refresh(f)
	t.eq(bar.state, S.BUILDING)
	t.eq(bar.progress_permille, 250)
	t.check(bar.eta_ticks > 0, "eta from the sim")
	t.eq(fac.state, S.QUEUED, "a def behind the head is QUEUED")
	t.eq(fac.queued, 1)
	# ready to place, and placing
	f.set_construction(UiSimPort.Construction.READY_TO_PLACE, bar.def_idx, 1000, 600)
	m.refresh(f)
	t.eq(bar.state, S.READY)
	t.eq(bar.eta_ticks, 0)
	t.eq(m.ready_count(UiBuildModel.Tab.STRUCTURES), 1, "tab badge counts the ready card")
	m.placing_def = bar.def_idx
	m.refresh(f)
	t.eq(bar.state, S.PLACING)
	m.placing_def = -1
	# on hold and blocked queue states
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 100, 600, PackedInt32Array(), UiSimPort.QueueState.HELD)
	m.refresh(f)
	t.eq(bar.state, S.ON_HOLD)
	t.check(bar.is_sweeping(), "held cards keep the sweep")
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 100, 600, PackedInt32Array(), UiSimPort.QueueState.PREREQ_LOST)
	m.refresh(f)
	t.eq(bar.state, S.BLOCKED)
	t.check(bar.reason_text != "", "blocked cards say why")
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 100, 600, PackedInt32Array(), UiSimPort.QueueState.WAIT_FUNDS)
	m.refresh(f)
	t.eq(bar.state, S.BUILDING, "waiting for credits still builds")
	t.eq(bar.reason_text, "Waiting for credits")


func test_unit_cards_follow_producers(t: TestCtx) -> void:
	var r: Array = _rig(2000)
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var rifle: UiBuildItem = _un(f, m, RIFLE)
	var tank: UiBuildItem = _un(f, m, TANK)
	t.eq(rifle.state, S.LOCKED, "no barracks yet")
	t.eq(tank.state, S.LOCKED, "no factory yet")
	f.spawn(BARRACKS, 0, 30, 20, 2)
	f.spawn(FACTORY, 0, 40, 20, 3)
	m.refresh(f)
	t.eq(rifle.state, S.AVAILABLE)
	t.eq(rifle.producer_eid, 2, "the only barracks is the producer")
	t.eq(tank.producer_eid, 3)
	f.set_credits(0, 10)
	m.refresh(f)
	t.eq(rifle.state, S.UNAFFORDABLE)
	f.set_credits(0, 2000)
	f.set_producer(2, PackedInt32Array([rifle.def_idx, rifle.def_idx, tank.def_idx]), 400, 300)
	m.refresh(f)
	t.eq(rifle.state, S.BUILDING, "head of the queue")
	t.eq(rifle.queued, 2, "two rifle squads queued incl. the one building")
	t.eq(rifle.progress_permille, 400)
	t.eq(tank.state, S.AVAILABLE, "the tank is trained elsewhere; barracks queue does not touch it")
	f.set_producer(3, PackedInt32Array([rifle.def_idx, tank.def_idx]), 0, 300)
	f.set_producer(2, PackedInt32Array(), 0, 300)
	m.refresh(f)
	t.eq(tank.state, S.QUEUED, "behind another head in the factory queue")
	f.set_producer(3, PackedInt32Array([tank.def_idx]), 200, 300, UiSimPort.QueueState.UNIT_CAP)
	m.refresh(f)
	t.eq(tank.state, S.BLOCKED, "unit cap parks the head")
	t.eq(tank.reason_text, "Unit cap reached")


func test_progress_only_touches_sweeping_items(t: TestCtx) -> void:
	var r: Array = _rig()
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var bar: UiBuildItem = _st(f, m, BARRACKS)
	var fac: UiBuildItem = _st(f, m, FACTORY)
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 100, 600)
	m.refresh(f)
	m.take_changed()
	f.set_construction(UiSimPort.Construction.BUILDING, bar.def_idx, 600, 600)
	m.refresh_progress(f)
	t.eq(bar.progress_permille, 600, "20 Hz progress update")
	t.eq(fac.state, S.AVAILABLE, "states are left to refresh()")
	t.check(m.take_changed().has(bar), "the progress change is reported")
	t.check(m.take_changed().is_empty(), "drained once")
	m.refresh(f)
	t.check(not m.take_changed().has(fac), "an unchanged card is not reported")
	f.set_credits(0, 0)
	m.refresh(f)
	t.check(m.take_changed().has(fac), "affordability change is reported")


func test_producer_picker(t: TestCtx) -> void:
	var r: Array = _rig()
	var f: UiSimPortFixture = r[0]
	f.spawn(BARRACKS, 0, 30, 20, 2)
	f.spawn(BARRACKS, 0, 32, 24, 3)
	var rifle: int = f.data().unit_idx(RIFLE)
	var qk: int = f.data().structures[f.data().structure_idx(BARRACKS)].queue_kind
	t.eq(UiProducerPicker.pick(f, qk, rifle, PackedInt32Array()), 2, "lowest id when all equal")
	f.set_producer(2, PackedInt32Array([rifle, rifle]), 100, 300)
	t.eq(UiProducerPicker.pick(f, qk, rifle, PackedInt32Array()), 3, "shortest queue wins")
	t.eq(UiProducerPicker.pick(f, qk, rifle, PackedInt32Array([2])), 2, "a selected producer wins")
	f.row_of(3).is_primary = true
	t.eq(UiProducerPicker.pick(f, qk, rifle, PackedInt32Array()), 3, "the primary building wins over queue length")
	f.force_rule("check_train", UiSimPort.Rule.NO_PREREQ)
	t.eq(UiProducerPicker.pick(f, qk, rifle, PackedInt32Array()), -1, "nobody can train it")


func test_power_and_superweapon_cards(t: TestCtx) -> void:
	var r: Array = _rig()
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var powers: Array[UiBuildItem] = []
	var sw: UiBuildItem = null
	for it: UiBuildItem in m.items(UiBuildModel.Tab.POWERS):
		if it.kind == K.POWER:
			powers.append(it)
		elif it.kind == K.SUPERWEAPON:
			sw = it
	if not t.check(not powers.is_empty(), "the roster has support powers"):
		return
	var p: UiBuildItem = powers[0]
	f.set_power(p.def_idx, UiSimPort.PowerStatus.READY, 0, 1200, 0)
	m.refresh(f)
	t.eq(p.state, S.AVAILABLE)
	t.eq(p.hotkey_label, "F5", "slot 0 = F5")
	f.set_power(p.def_idx, UiSimPort.PowerStatus.COOLDOWN, f.tick() + 600, 1200, 0)
	m.refresh(f)
	t.eq(p.state, S.COOLDOWN)
	t.eq(p.progress_permille, 500, "half the cooldown elapsed")
	t.eq(p.remaining_whole_seconds(), 30)
	f.set_power(p.def_idx, UiSimPort.PowerStatus.LOCKED_PREREQ, 0, 1200, 0)
	m.refresh(f)
	t.eq(p.state, S.LOCKED)
	f.set_power(p.def_idx, UiSimPort.PowerStatus.UNPOWERED, 0, 1200, 0)
	m.refresh(f)
	t.eq(p.state, S.BLOCKED)
	if sw != null:
		t.eq(sw.state, S.LOCKED, "no launcher: superweapon locked")
		f.set_superweapon(UiSimPort.SwStatus.READY, sw.def_idx, 1000, 0, 1)
		m.refresh(f)
		t.eq(sw.state, S.AVAILABLE)
		t.eq(sw.hotkey_label, "F8")


func test_tooltip_spec_and_formatting(t: TestCtx) -> void:
	var r: Array = _rig()
	var f: UiSimPortFixture = r[0]
	var m: UiBuildModel = r[1]
	var fac: UiBuildItem = _st(f, m, FACTORY)
	var spec: Dictionary = m.tooltip_spec(fac)
	t.eq(spec["title"], fac.display_name)
	var labels: PackedStringArray = PackedStringArray()
	for s: Dictionary in spec["stats"]:
		labels.append(str(s["label"]))
	t.check(labels.has("COST") and labels.has("TIME") and labels.has("POWER"), "structure tooltip rows: %s" % [labels])
	t.eq(UiBuildItem.group_digits(12450), "12,450")
	t.eq(UiBuildItem.group_digits(-1200), "-1,200")
	t.eq(UiBuildItem.mmss(75), "1:15")
	t.eq(UiBuildItem.ticks_to_seconds(21), 2, "rounded up")


func test_real_world_locks_and_costs(t: TestCtx) -> void:
	var mi: Dictionary = SimMatchKit.make_match({"seed": 2, "bots": false})
	var w: SimWorld = mi["world"]
	if not t.not_null(w, "world"):
		return
	var sim := UiSimPortWorld.new(w, 0)
	var m := UiBuildModel.new()
	m.rebuild(sim, sim.roster_of(0))
	m.refresh(sim)
	var locked: int = 0
	var open: int = 0
	for tab: int in UiBuildModel.TAB_COUNT:
		for it: UiBuildItem in m.items(tab):
			if it.state == S.LOCKED:
				locked += 1
				if it.kind != K.POWER and it.kind != K.SUPERWEAPON:
					t.check(it.requires_text != "" or it.kind == K.RESEARCH, "%s names what it needs" % it.display_name)
			else:
				open += 1
	t.check(open > 0 and locked > 0, "start state: some cards open (%d), some locked (%d)" % [open, locked])
	# after the start: the first structure card starts a real build
	var bus := UiCommandBus.new()
	var net := UiNetPortLoopback.new(w, 0)
	bus.setup(net, sim, null, UiAudioPortNull.new(), null)
	var first: UiBuildItem = null
	for it2: UiBuildItem in m.items(UiBuildModel.Tab.STRUCTURES):
		if it2.state == S.AVAILABLE:
			first = it2
			break
	if not t.not_null(first, "an available structure card"):
		return
	t.check(bus.build_start(first.def_idx, 1), "the bus accepts the build")
	w.step()
	w.step()
	m.refresh(sim)
	t.eq(first.state, S.BUILDING, "the real world reports the build")
	t.check(first.progress_permille >= 0 and first.eta_ticks > 0)


func test_canada_roster_replacements_and_states(t: TestCtx) -> void:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 5000)
	f.set_viewer(0)
	f.spawn(HQ, 0, 20, 20, 1)
	var m := UiBuildModel.new()
	m.rebuild(f, f.roster_of(0))
	m.refresh(f)
	var veh: PackedStringArray = PackedStringArray()
	for it: UiBuildItem in m.items(UiBuildModel.Tab.VEHICLES):
		veh.append(it.id)
	t.check(veh.has("unit.napc.narwhal_amphibious_tank"), "Narwhal is on the VEHICLES tab: %s" % [veh])
	t.check(not veh.has(TANK), "the replaced Guardian is not")
	for it2: UiBuildItem in m.items(UiBuildModel.Tab.AIRCRAFT):
		t.check(not it2.id.contains("titan_gunship"), "Titan Gunship is absent from AIRCRAFT")
	var nar: UiBuildItem = _un(f, m, "unit.napc.narwhal_amphibious_tank")
	t.check(nar != null and nar.replaced_by_roster, "the subfaction unit carries the UNIQUE badge flag")
	# WAIT_FUNDS keeps BUILDING; low power doubles the ETA
	f.spawn(FACTORY, 0, 40, 20, 3)
	f.set_producer(3, PackedInt32Array([nar.def_idx]), 372, 754)
	m.refresh(f)
	t.eq(nar.state, S.BUILDING)
	t.eq(nar.progress_permille, 372)
	var eta_full: int = nar.eta_ticks
	f.set_producer(3, PackedInt32Array([nar.def_idx]), 372, 754, UiSimPort.QueueState.WAIT_FUNDS)
	m.refresh(f)
	t.eq(nar.state, S.BUILDING, "WAIT_FUNDS keeps the state")
	t.eq(nar.reason_text, "Waiting for credits")
	f.set_producer(3, PackedInt32Array([nar.def_idx]), 372, 754, UiSimPort.QueueState.LOW_POWER, 50)
	m.refresh(f)
	t.check(nar.eta_ticks >= eta_full * 2 - 2, "half speed doubles the ETA (%d -> %d)" % [eta_full, nar.eta_ticks])
	# producer picker: queues (2, 0) -> the empty one
	f.spawn(FACTORY, 0, 44, 24, 4)
	f.set_producer(3, PackedInt32Array([nar.def_idx, nar.def_idx]), 100, 754)
	m.refresh(f)
	t.eq(nar.producer_eid, 4, "the empty factory is chosen")
	# a completed research shows DONE
	var done_idx: int = -1
	for it3: UiBuildItem in m.items(UiBuildModel.Tab.RESEARCH):
		done_idx = it3.def_idx
		break
	if done_idx >= 0:
		f._researched[done_idx] = true
		m.refresh(f)
		t.eq(m.item_for(K.RESEARCH, done_idx).state, S.DONE)
