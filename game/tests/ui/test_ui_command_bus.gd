extends RefCounted
## The only path UI -> sim (ui.md 3.3, 5.8, 10.2 `test_ui_command_bus`) over the recorder net port and the fixture.

const TANK: String = "unit.napc.guardian_tank"
const RIFLE: String = "unit.napc.rifle_squad"


class Rig extends RefCounted:
	var sim: UiSimPortFixture
	var net: UiNetPortRecorder = UiNetPortRecorder.new()
	var audio: UiAudioPortRecorder = UiAudioPortRecorder.new()
	var fb: UiFeedback = UiFeedback.new()
	var bus: UiCommandBus = UiCommandBus.new()
	var issued: Array[PackedInt32Array] = []
	var refusals: Array[Vector2i] = []


func _rig() -> Rig:
	var r := Rig.new()
	r.sim = UiSimPortFixture.load_file("hud_mid_match")
	r.fb.setup(null, null, r.audio, null)
	r.bus.setup(r.net, r.sim, null, r.audio, r.fb)
	r.bus.issued.connect(func(_k: int, c: PackedInt32Array) -> void: r.issued.append(c))
	r.bus.refused.connect(func(k: int, why: int) -> void: r.refusals.append(Vector2i(k, why)))
	return r


func _ids(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


func _last(r: Rig) -> String:
	return UiCmdCodec.describe(r.net.sent.back()) if not r.net.sent.is_empty() else "<nothing sent>"


func test_typed_helpers_emit_golden_arrays(t: TestCtx) -> void:
	var r: Rig = _rig()
	var d: GameData = r.sim.data()
	var narwhal: int = d.unit_idx("unit.napc.narwhal_amphibious_tank")
	t.check(r.bus.train(88, narwhal, 5), "train")
	t.eq(r.net.sent.back(), PackedInt32Array([124, 88, narwhal, 5]), "Shift+card is ONE train with count 5")
	t.check(r.bus.train_cancel(88, 1))
	t.eq(_last(r), "TRAIN_CANCEL target=88 mode=1")
	t.check(r.bus.queue_hold(UiCmdCodec.Hold.PRODUCER, _ids([88]), true))
	t.eq(_last(r), "QUEUE_HOLD ids=[88] mode=1")
	t.check(r.bus.queue_hold(UiCmdCodec.Hold.CONSTRUCTION, PackedInt32Array(), true))
	t.eq(_last(r), "BUILD_HOLD mode=1")
	t.check(r.bus.queue_hold(UiCmdCodec.Hold.RESEARCH, PackedInt32Array(), false))
	t.eq(_last(r), "RESEARCH_HOLD mode=0")
	var radar: int = d.structure_idx("structure.shared.radar")
	t.check(r.bus.build_start(radar))
	t.eq(_last(r), "BUILD_START def=%d count=1" % radar)
	t.check(r.bus.build_cancel(0))
	t.eq(_last(r), "BUILD_CANCEL mode=0")
	t.check(r.bus.build_place(9, 30, 41, 1))
	t.eq(r.net.sent.back(), PackedInt32Array([123, 9, 30, 41, 1]), "whole cells + rotation")
	t.check(r.bus.research(2))
	t.eq(_last(r), "RESEARCH def=2")
	t.check(r.bus.research_cancel(0))
	t.eq(_last(r), "RESEARCH_CANCEL mode=0")
	t.check(r.bus.set_primary(88))
	t.eq(_last(r), "SET_PRIMARY target=88")
	t.check(r.bus.set_rally(_ids([88, 89]), 10240, 12288))
	t.eq(_last(r), "SET_RALLY ids=[88,89] x=10240 y=12288 target=0 flags=0")
	t.check(r.bus.set_struct_repair(_ids([90]), 1))
	t.eq(_last(r), "SET_STRUCT_REPAIR ids=[90] mode=1")
	t.check(r.bus.undeploy_hq(_ids([1])))
	t.eq(_last(r), "UNDEPLOY_HQ ids=[1]")
	t.check(r.bus.sell(_ids([90, 89])))
	t.eq(_last(r), "SELL ids=[89,90]")


func test_typed_unit_helpers(t: TestCtx) -> void:
	var r: Rig = _rig()
	t.check(r.bus.stance(_ids([1002, 1001]), 1))
	t.eq(_last(r), "SET_STANCE ids=[1001,1002] mode=1")
	t.check(r.bus.hold(_ids([1001])))
	t.eq(_last(r), "HOLD ids=[1001]")
	t.check(r.bus.simple(UiOrderIntent.Kind.STOP, _ids([1001, 1003])))
	t.eq(_last(r), "STOP ids=[1001,1003]")
	t.check(r.bus.simple(UiOrderIntent.Kind.SCATTER, _ids([1001])))
	t.eq(_last(r), "SCATTER ids=[1001]")
	t.check(r.bus.simple(UiOrderIntent.Kind.RETURN_CASH, _ids([1004])))
	t.eq(_last(r), "RETURN_CARGO ids=[1004] target=0 mode=0")
	t.check(r.bus.simple(UiOrderIntent.Kind.SCUTTLE, _ids([1001])))
	t.eq(_last(r), "SCUTTLE ids=[1001]")
	t.check(not r.bus.simple(UiOrderIntent.Kind.MOVE, _ids([1001])), "only the four simple kinds")
	t.check(r.bus.follow(_ids([1001, 1002]), 1003))
	t.eq(_last(r), "FOLLOW ids=[1001,1002] target=1003 mode=0")
	t.check(not r.bus.follow(_ids([1001, 1003]), 1003), "a unit cannot follow itself")
	t.check(r.bus.return_to_base(_ids([1001]), 0))
	t.eq(_last(r), "RETURN_TO_BASE ids=[1001] target=0 mode=0")
	t.check(r.bus.harvest(_ids([1004]), 48, 17))
	t.eq(r.net.sent.back(), PackedInt32Array([10, 0, 49664, 17920, 0, 1004]), "HARVEST at the deposit cell centre")
	t.check(r.bus.use_ability(_ids([1001]), 2, 0, 5000, 6000))
	t.eq(_last(r), "USE_ABILITY ids=[1001] def=2 mode=0 target=0 x=5000 y=6000")
	t.check(r.bus.cancel_ability(_ids([1001]), 2))
	t.eq(_last(r), "USE_ABILITY ids=[1001] def=2 mode=1 target=0 x=-1 y=-1")
	t.check(r.bus.set_mode(_ids([1001]), 1, 1))
	t.eq(_last(r), "SET_MODE ids=[1001] def=1 mode=1")
	t.check(r.bus.set_autocast(_ids([1001]), 0, true))
	t.eq(_last(r), "SET_AUTOCAST ids=[1001] def=0 mode=1")


func test_refusal_by_rule_sends_nothing(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.sim.force_rule("check_train", UiSimPort.Rule.NO_PREREQ)
	t.check(not r.bus.train(88, 0, 1))
	t.eq(r.net.sent.size(), 0, "nothing sent")
	t.eq(r.refusals, [Vector2i(SimCmd.TRAIN, UiSimPort.Rule.NO_PREREQ)] as Array[Vector2i])
	t.eq(r.audio.count_of(&"ui"), 1, "the error cue plays for a UI pre-check refusal")
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.ERROR)
	r.sim.force_rule("check_build", UiSimPort.Rule.QUEUE_FULL)
	t.check(not r.bus.build_start(3))
	r.sim.force_rule("check_research", UiSimPort.Rule.NOT_AVAILABLE)
	t.check(not r.bus.research(1))
	t.eq(r.net.sent.size(), 0)
	t.eq(r.refusals.size(), 3)


func test_place_refusal_plays_place_fail(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.sim.set_bad_site(9, 30, 41, 2)
	t.check(not r.bus.build_place(9, 30, 41, 0))
	t.eq(r.refusals.back(), Vector2i(SimCmd.BUILD_PLACE, UiSimPort.Rule.BAD_SITE))
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.PLACE_FAIL)
	t.check(r.bus.build_place(9, 31, 41, 0))
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.PLACE_OK)


func test_unit_cap_counts_queued_units(t: TestCtx) -> void:
	var r: Rig = _rig()
	var unit_count: int = r.sim.unit_count()
	(r.sim._players[0] as Dictionary)["cap"] = unit_count + 2 + 3
	t.check(r.bus.train(88, 0, 3), "2 queued + 3 new fits exactly")
	t.check(not r.bus.train(88, 0, 4), "one over the cap")
	t.eq(r.refusals.back().y, UiSimPort.Rule.UNIT_CAP)


func test_turn_budget_and_duplicates(t: TestCtx) -> void:
	var r2: Rig = _rig()
	r2.net.tick_value = 100
	for i: int in 40:
		t.check(r2.bus.dispatch(_move_intent([1001], 1000 + i, 5)) == 1, "command %d accepted" % (i + 1))
	t.eq(r2.bus.turn_count(), 40)
	t.eq(r2.bus.dispatch(_move_intent([1001], 3000, 5)), 0, "the 41st command of the turn is refused")
	t.eq(r2.refusals.back(), Vector2i(SimCmd.MOVE, UiCommandBus.REFUSE_RATE))
	t.eq(r2.net.sent.size(), 40)
	t.eq(r2.audio.count_of(&"ui"), 1, "one error cue")
	r2.bus.dispatch(_move_intent([1001], 3001, 5))
	t.eq(r2.audio.count_of(&"ui"), 1, "at most once per second")
	r2.net.tick_value = 102
	t.eq(r2.bus.dispatch(_move_intent([1001], 3000, 5)), 1, "the next turn starts a fresh budget")
	r2.net.tick_value = 200
	r2.bus.begin_turn_budget(200)
	t.eq(r2.bus.turn_count(), 0)


func test_identical_consecutive_command_is_dropped(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.net.tick_value = 40
	t.eq(r.bus.dispatch(_move_intent([1001], 4096, 8192)), 1)
	t.eq(r.bus.dispatch(_move_intent([1001], 4096, 8192)), 0, "key repeat / double click in the same turn")
	t.eq(r.net.sent.size(), 1)
	t.eq(r.refusals.size(), 0, "a duplicate is not an error")
	t.eq(r.bus.dispatch(_move_intent([1001], 4097, 8192)), 1)
	t.eq(r.bus.dispatch(_move_intent([1001], 4096, 8192)), 1, "only CONSECUTIVE duplicates are dropped")
	r.net.tick_value = 42
	t.eq(r.bus.dispatch(_move_intent([1001], 4096, 8192)), 1, "and only inside one turn")


func test_observer_port_refuses_everything(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.net.observer = true
	t.check(not r.bus.hold(_ids([1001])))
	t.check(not r.bus.train(88, 0, 1))
	t.eq(r.bus.dispatch(_move_intent([1001], 1, 1)), 0)
	t.eq(r.net.sent.size(), 0)
	for ref: Vector2i in r.refusals:
		t.eq(ref.y, UiCommandBus.REFUSE_NOT_ALLOWED)
	t.eq(r.refusals.size(), 3)
	var null_port := UiNetPortNull.new()
	r.bus.setup(null_port, r.sim, null, r.audio, r.fb)
	t.check(not r.bus.hold(_ids([1001])), "the null port refuses too")
	var full := UiNetPortRecorder.new()
	full.accept = false
	r.bus.setup(full, r.sim, null, r.audio, r.fb)
	t.check(not r.bus.hold(_ids([1001])), "a stalled port refuses")


func _move_intent(ids: Array, x: int, y: int) -> UiOrderIntent:
	return UiOrderIntent.make(UiOrderIntent.Kind.MOVE, PackedInt32Array(ids), x, y)


func test_dispatch_sends_primary_then_extras_in_order(t: TestCtx) -> void:
	var r: Rig = _rig()
	var prim: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.CAPTURE, _ids([1003]), 100, 200, 1004)
	var extra: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.MOVE, _ids([1002, 1001]), 100, 200, -1)
	prim.extra.append(extra)
	t.eq(r.bus.dispatch(prim), 2)
	t.eq(r.net.described(), PackedStringArray(["CAPTURE ids=[1003] target=1004 mode=0", "MOVE ids=[1001,1002] x=100 y=200 mode=0 flags=0"]))
	t.eq(r.issued.size(), 2)


func test_queue_mode_only_where_the_sim_has_one(t: TestCtx) -> void:
	var r: Rig = _rig()
	for kind: int in [UiOrderIntent.Kind.MOVE, UiOrderIntent.Kind.ATTACK_MOVE, UiOrderIntent.Kind.PATROL]:
		var it: UiOrderIntent = UiOrderIntent.make(kind, _ids([1001]), 10 + kind, 20)
		it.queued = true
		r.bus.dispatch(it)
	var atk: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, _ids([1001]), 0, 0, 2001)
	atk.queued = true
	r.bus.dispatch(atk)
	var ff: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.FORCE_FIRE, _ids([1001]), 30, 40)
	ff.queued = true
	r.bus.dispatch(ff)
	var stop: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.STOP, _ids([1001]), 0, 0)
	stop.queued = true
	r.bus.dispatch(stop)
	var d: PackedStringArray = r.net.described()
	t.check(d[0].ends_with("mode=1 flags=0"), d[0])
	t.check(d[1].contains("mode=1"), d[1])
	t.check(d[2].contains("mode=1"), d[2])
	t.check(d[3].begins_with("ATTACK ") and d[3].contains("mode=1"), d[3])
	t.eq(d[4], "FORCE_FIRE ids=[1001] target=0 x=30 y=40 count=0", "force-fire ignores Shift")
	t.eq(d[5], "STOP ids=[1001]", "stop ignores Shift")


func test_forced_attack_flag_and_move_flags(t: TestCtx) -> void:
	var r: Rig = _rig()
	var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, _ids([1001, 1002]), 0, 0, 3001)
	it.force = true
	r.bus.dispatch(it)
	t.eq(r.net.sent.back(), PackedInt32Array([40, 3001, 0, 1, 1001, 1002]), "flags bit0 = forced")
	r.bus.move_speed_match = true
	r.net.tick_value = 10
	r.bus.dispatch(_move_intent([1001], 15360, 30720))
	t.eq(r.net.sent.back(), PackedInt32Array([1, 15360, 30720, 0, 2, 1001]), "input/move_speed_match sets flag b1")
	r.bus.move_reverse = true
	r.bus.dispatch(_move_intent([1001], 15361, 30720))
	t.eq(r.net.sent.back()[4], 6, "b1 | b2")


func test_use_power_sends_the_power_index(t: TestCtx) -> void:
	var r: Rig = _rig()
	var d: GameData = r.sim.data()
	var repair: int = d.power_idx("power.napc.field_repair_drop")
	var uav: int = d.power_idx("power.napc.uav_sweep")
	t.eq(r.sim.power_slot(repair), 1, "the slot only orders the dock")
	t.check(r.bus.use_power(repair, 65536, 40960, 1024))
	t.eq(r.net.sent.back(), PackedInt32Array([140, repair, 65536, 40960, 1024, 0]), "the def field carries the power index")
	t.check(not r.bus.use_power(uav, 65536, 40960, 0), "on cooldown")
	t.eq(r.refusals.back(), Vector2i(SimCmd.USE_POWER, UiSimPort.Rule.NOT_READY))
	var locked: int = d.power_idx("power.napc.floating_workshop")
	t.check(not r.bus.use_power(locked, 1, 1, 0), "unpowered / locked")
	r.sim.set_power(repair, UiSimPort.PowerStatus.READY, 0, 0, 1)
	r.sim.set_default_visibility(UiSimPort.Vis.SHROUD)
	var vis_mode: int = d.powers[repair].target_vision
	if vis_mode != DefEnums.TargetVision.ANY:
		t.check(not r.bus.use_power(repair, 1000, 1000, 0), "needs vision")
		t.eq(r.refusals.back().y, UiSimPort.Rule.NO_VISION)


func test_launch_superweapon(t: TestCtx) -> void:
	var r: Rig = _rig()
	t.check(not r.bus.launch_superweapon(65536, 40960, 0), "still charging")
	r.sim.advance(1900)
	t.check(r.bus.launch_superweapon(65536, 40960, 2048))
	t.eq(_last(r), "LAUNCH_SUPERWEAPON x=65536 y=40960 angle=2048")


func test_train_cancel_of_the_last_instance(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.sim.set_producer(88, _ids([17, 17, 21]))
	t.check(r.bus.train_cancel_def(88, 17))
	t.eq(_last(r), "TRAIN_CANCEL target=88 mode=1", "the LAST 17 of [17, 17, 21] is queue slot 1")
	t.check(r.bus.train_cancel_def(88, 21))
	t.eq(_last(r), "TRAIN_CANCEL target=88 mode=2")
	t.check(not r.bus.train_cancel_def(88, 99), "not queued: nothing sent")


func test_unload_one_command_per_carrier_at_its_position(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.sim.spawn(TANK, 0, 66560, 30720, 70)
	r.sim.spawn(TANK, 0, 1000, 2000, 71)
	t.check(r.bus.unload(_ids([71, 70])))
	t.eq(r.net.described(), PackedStringArray(["UNLOAD ids=[70] mode=0 target=0 x=66560 y=30720", "UNLOAD ids=[71] mode=0 target=0 x=1000 y=2000"]))
	t.check(r.bus.unload(_ids([70]), false, 1003))
	t.eq(_last(r), "UNLOAD ids=[70] mode=1 target=1003 x=66560 y=30720")


func test_deploy_toggle_splits_deployed_and_undeployed(t: TestCtx) -> void:
	var r: Rig = _rig()
	var mcv: UiEntityRow = r.sim.spawn("unit.shared.mobile_construction_vehicle", 0, 1, 1, 6)
	var howitzer: UiEntityRow = r.sim.spawn("unit.ae.forge_howitzer", 0, 2, 1, 7)
	var howitzer2: UiEntityRow = r.sim.spawn("unit.ae.forge_howitzer", 0, 3, 1, 8)
	howitzer.flags |= UiEntityRow.F_DEPLOYED
	howitzer2.flags |= UiEntityRow.F_DEPLOYED
	t.check(mcv.id == 6)
	t.check(r.bus.deploy_toggle(_ids([6])))
	t.eq(r.net.sent.back(), PackedInt32Array([100, -1, 6]), "DEPLOY def -1: the sim routes an MCV")
	r.net.tick_value = 2
	t.check(r.bus.deploy_toggle(_ids([8, 7, 6])))
	var cmds: PackedStringArray = r.net.described()
	t.eq(cmds.size(), 3, "one deploy + one undeploy for the deployed group")
	t.eq(cmds[1], "DEPLOY ids=[6] def=-1")
	t.check(cmds[2].begins_with("UNDEPLOY ids=[7,8] def="), cmds[2])


func test_dead_and_foreign_ids_are_pruned_before_send(t: TestCtx) -> void:
	var r: Rig = _rig()
	t.check(r.bus.hold(_ids([1001, 999999, 2001, 1002])), "one dead id, one enemy id")
	t.eq(_last(r), "HOLD ids=[1001,1002]")
	t.check(not r.bus.hold(_ids([999999, 2001])), "nothing eligible")
	t.eq(r.refusals.back(), Vector2i(SimCmd.HOLD, UiCommandBus.REFUSE_EMPTY))
	t.eq(r.net.sent.size(), 1)


func test_target_fog_check(t: TestCtx) -> void:
	var r: Rig = _rig()
	var hidden: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, _ids([1001]), 0, 0, 2002)
	t.eq(r.bus.dispatch(hidden), 0, "an enemy the viewer cannot see cannot be attacked")
	t.eq(r.refusals.back(), Vector2i(SimCmd.ATTACK, UiSimPort.Rule.NO_VISION))
	var visible: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, _ids([1001]), 0, 0, 2001)
	t.eq(r.bus.dispatch(visible), 1)
	var ally: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.LOAD, _ids([1003]), 0, 0, 3001)
	t.eq(r.bus.dispatch(ally), 1, "allies are always targetable")


func test_feedback_and_denied_intents(t: TestCtx) -> void:
	var r: Rig = _rig()
	var markers: Array[int] = []
	r.fb.marker_requested.connect(func(k: int, _x: int, _y: int, _t: int) -> void: markers.append(k))
	var flashed: Array[PackedInt32Array] = []
	r.fb.flash_requested.connect(func(ids: PackedInt32Array) -> void: flashed.append(ids))
	r.bus.dispatch(_move_intent([1001], 100, 100))
	t.eq(markers, [UiOrderIntent.MK_MOVE] as Array[int])
	t.eq(flashed.size(), 1)
	t.eq(r.audio.last_args(&"unit_ordered")[0], UiAudioPort.Order.MOVE)
	var atk: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.ATTACK, _ids([1001]), 0, 0, 2001)
	r.bus.dispatch(atk)
	t.eq(r.audio.last_args(&"unit_ordered")[0], UiAudioPort.Order.ATTACK)
	r.audio.clear()
	var deny: UiOrderIntent = UiOrderIntent.denied(&"order.deny.cannot_hit")
	t.eq(r.bus.dispatch(deny), 0)
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.ERROR)
	t.eq(r.net.sent.size(), 2)
	var rally: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.SET_RALLY, _ids([88]), 500, 600, -1)
	r.bus.dispatch(rally)
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.RALLY_SET, "rally has a cue instead of a unit response")


func test_rally_fallback_uses_the_tab_producers(t: TestCtx) -> void:
	var r: Rig = _rig()
	var it: UiOrderIntent = UiOrderIntent.make(UiOrderIntent.Kind.SET_RALLY, PackedInt32Array(), 500, 600, -1)
	t.eq(r.bus.dispatch(it), 0, "no producer and no fallback: nothing to do")
	r.bus.rally_fallback = func() -> PackedInt32Array: return PackedInt32Array([89, 88])
	t.eq(r.bus.dispatch(it), 1)
	t.eq(_last(r), "SET_RALLY ids=[88,89] x=500 y=600 target=0 flags=0")


func test_resolver_to_bus_pipeline(t: TestCtx) -> void:
	var r: Rig = _rig()
	var sel := UiSelection.new()
	sel.replace(r.sim.selected, r.sim)
	var info: UiSelectionInfo = UiSelectionInfo.build(sel, r.sim)
	var tgt: UiTarget = UiTarget.entity(UiTarget.Kind.ENEMY, 2001, UiTarget.EntityKind.UNIT, 90112, 51200)
	var it: UiOrderIntent = UiContextResolver.resolve(info, tgt, UiContextResolver.MOD_QUEUE, UiModes.Armed.NONE)
	t.eq(r.bus.dispatch(it), 1)
	t.eq(_last(r), "ATTACK ids=[1001,1002] target=2001 mode=1 flags=0")


func test_ping_goes_through_the_net_port(t: TestCtx) -> void:
	var r: Rig = _rig()
	r.bus.ping(15360, 30720)
	t.eq(r.net.pings, [Vector2i(15, 30)] as Array[Vector2i])
	t.eq(r.audio.last_args(&"ui")[0], UiAudioPort.MINIMAP_PING)
