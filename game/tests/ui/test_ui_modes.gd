extends RefCounted
## Armed modes, immediate feedback and the small port adapters (ui.md 3.2.3, 3.3, 5.7.2, 5.8.7).


func test_arm_disarm_and_signal(t: TestCtx) -> void:
	var m := UiModes.new()
	var changes: Array[Vector2i] = []
	m.changed.connect(func(a: int, p: int) -> void: changes.append(Vector2i(a, p)))
	t.eq(m.armed, UiModes.Armed.NONE)
	t.check(not m.is_click_mode())
	m.arm(UiModes.Armed.ATTACK_MOVE)
	t.eq(m.armed, UiModes.Armed.ATTACK_MOVE)
	t.check(m.is_click_mode(), "LMB issues while armed")
	m.arm(UiModes.Armed.GUARD, 3)
	t.eq(m.arg, 3)
	m.disarm()
	m.disarm()
	t.eq(changes, [Vector2i(1, 0), Vector2i(2, 1), Vector2i(0, 2)] as Array[Vector2i], "one signal per real change")
	t.eq(m.arg, -1)


func test_consume_sticky_and_shift(t: TestCtx) -> void:
	var m := UiModes.new()
	m.arm(UiModes.Armed.PATROL)
	m.consume(false)
	t.eq(m.armed, UiModes.Armed.NONE, "one issued order disarms")
	m.arm(UiModes.Armed.PATROL)
	m.consume(true)
	t.eq(m.armed, UiModes.Armed.PATROL, "Shift keeps the mode")
	m.disarm()
	m.sticky = true
	m.arm(UiModes.Armed.MOVE)
	m.consume(false)
	t.eq(m.armed, UiModes.Armed.MOVE, "input/sticky_modes keeps it too")


func test_waypoint_latch(t: TestCtx) -> void:
	var m := UiModes.new()
	m.arm(UiModes.Armed.WAYPOINT)
	t.check(m.waypoint_latch, "W toggles the latch, it is not a click mode")
	t.eq(m.armed, UiModes.Armed.NONE)
	t.check(not m.is_click_mode())
	t.eq(m.effective_mods(0), UiContextResolver.MOD_QUEUE, "the latch queues everything")
	t.eq(m.effective_mods(UiContextResolver.MOD_FORCE), UiContextResolver.MOD_FORCE | UiContextResolver.MOD_QUEUE)
	m.arm(UiModes.Armed.WAYPOINT)
	t.check(not m.waypoint_latch)
	t.eq(m.effective_mods(0), 0)
	m.arm(UiModes.Armed.WAYPOINT)
	m.clear_latch()
	t.check(not m.waypoint_latch, "Esc clears the latch")


func test_arming_plays_the_cue(t: TestCtx) -> void:
	var m := UiModes.new()
	var a := UiAudioPortRecorder.new()
	m.audio = a
	m.arm(UiModes.Armed.SELL)
	m.arm(UiModes.Armed.REPAIR)
	m.arm(UiModes.Armed.ATTACK_MOVE)
	var ids: Array = []
	for c: Array in a.calls:
		ids.append((c[1] as Array)[0])
	t.eq(ids, [UiAudioPort.SELL_MODE, UiAudioPort.REPAIR_MODE, UiAudioPort.CONFIRM])


func test_feedback_marker_ping_and_unit_response(t: TestCtx) -> void:
	var fb := UiFeedback.new()
	var audio := UiAudioPortRecorder.new()
	fb.setup(null, null, audio, null)
	var markers: Array[Vector3i] = []
	var pings: Array[Vector2i] = []
	fb.marker_requested.connect(func(k: int, x: int, y: int, _t: int) -> void: markers.append(Vector3i(k, x, y)))
	fb.ping_requested.connect(func(x: int, y: int) -> void: pings.append(Vector2i(x, y)))
	fb.on_screen = func(x: int, _y: int) -> bool: return x < 1000
	fb.order_issued(UiOrderIntent.Kind.MOVE, 500, 600, PackedInt32Array([1]), 7)
	t.eq(markers.back(), Vector3i(UiOrderIntent.MK_MOVE, 500, 600))
	t.eq(pings.size(), 0, "on-screen moves need no minimap ping")
	fb.order_issued(UiOrderIntent.Kind.MOVE, 5000, 600, PackedInt32Array([1]), 7)
	t.eq(pings, [Vector2i(5000, 600)] as Array[Vector2i], "off-screen moves ping the minimap")
	fb.order_issued(UiOrderIntent.Kind.ATTACK, 5000, 600, PackedInt32Array([1]), 7, 55)
	t.eq(pings.size(), 1, "attacks never ping")
	t.eq(audio.last_args(&"unit_ordered"), [UiAudioPort.Order.ATTACK, 7])
	fb.order_issued(UiOrderIntent.Kind.SET_RALLY, 1, 1, PackedInt32Array([88]), 3)
	t.eq(audio.last_args(&"ui")[0], UiAudioPort.RALLY_SET)
	fb.order_issued(UiOrderIntent.Kind.STOP, 0, 0, PackedInt32Array([1]), 7)
	t.eq(audio.last_args(&"unit_ordered"), [UiAudioPort.Order.STOP, 7])
	t.eq(fb.last_marker, UiOrderIntent.MK_RALLY, "a kind without a marker leaves the last one")


func test_unit_order_mapping_table(t: TestCtx) -> void:
	var K: Dictionary = UiOrderIntent.Kind
	var O: Dictionary = UiAudioPort.Order
	var rows: Array = [
		[K.MOVE, O.MOVE], [K.PATROL, O.MOVE], [K.ATTACK, O.ATTACK], [K.FORCE_FIRE, O.ATTACK], [K.ATTACK_MOVE, O.ATTACK],
		[K.GUARD, O.GUARD], [K.CAPTURE, O.CAPTURE], [K.SALVAGE, O.CAPTURE], [K.LOAD, O.LOAD], [K.GARRISON, O.LOAD],
		[K.HARVEST, O.HARVEST], [K.RETURN_CASH, O.HARVEST], [K.REPAIR, O.REPAIR], [K.RETURN_BASE, O.MOVE], [K.FOLLOW, O.MOVE],
		[K.SELL, O.SELL], [K.DEPLOY, O.DEPLOY], [K.UNLOAD, O.UNLOAD], [K.SCATTER, O.SCATTER], [K.STOP, O.STOP],
	]
	for row: Array in rows:
		t.eq(UiFeedback.unit_order_for(int(row[0])), int(row[1]), "intent %d" % int(row[0]))
	t.eq(UiFeedback.unit_order_for(K.SET_RALLY), -1)
	t.eq(UiFeedback.unit_order_for(K.DENIED), -1)


func test_feedback_denied(t: TestCtx) -> void:
	var fb := UiFeedback.new()
	var audio := UiAudioPortRecorder.new()
	fb.setup(null, null, audio, null)
	var shown: Array[StringName] = []
	fb.denied_shown.connect(func(_r: int, k: StringName) -> void: shown.append(k))
	fb.denied(UiSimPort.Rule.NO_PREREQ, &"reject.10", 12, false)
	t.eq(shown, [&"reject.10"] as Array[StringName])
	t.eq(audio.names(), PackedStringArray(["ui", "order_denied"]))
	t.eq(audio.last_args(&"order_denied"), [12, false])
	t.eq(fb.last_marker, UiOrderIntent.MK_DENIED)


func test_recorder_and_null_net_ports(t: TestCtx) -> void:
	var rec := UiNetPortRecorder.new()
	t.check(rec.submit(SimCmd.stop(PackedInt32Array([3]))))
	t.eq(rec.described(), PackedStringArray(["STOP ids=[3]"]))
	t.check(not rec.submit(PackedInt32Array()), "empty commands are refused")
	var big: PackedInt32Array = PackedInt32Array()
	big.resize(1025)
	big[0] = 2
	t.check(not rec.submit(big), "larger than 1024 ints")
	rec.observer = true
	t.check(not rec.can_submit())
	t.eq(rec.local_pid(), -1)
	var nul := UiNetPortNull.new()
	t.check(not nul.can_submit())
	t.check(not nul.submit(SimCmd.stop(PackedInt32Array([3]))))
	t.check(nul.is_observer())


func test_session_port_forwards_by_name(t: TestCtx) -> void:
	var fake := FakeSession.new()
	var port := UiNetPortSession.new(fake)
	t.check(port.can_submit())
	t.check(port.submit(SimCmd.stop(PackedInt32Array([3]))))
	t.eq(fake.got.size(), 1)
	port.send_chat("hi", true)
	port.send_map_ping(4, 5)
	t.eq(fake.chats, ["hi:true"])
	t.eq(fake.pings, [Vector2i(4, 5)] as Array[Vector2i])
	t.eq(port.tick(), 77)
	t.eq(port.local_pid(), 2)
	var none := UiNetPortSession.new(null)
	t.check(not none.submit(SimCmd.stop(PackedInt32Array([3]))))
	t.check(none.is_observer())


class FakeSession extends RefCounted:
	var got: Array[PackedInt32Array] = []
	var chats: Array[String] = []
	var pings: Array[Vector2i] = []

	func submit_command(c: PackedInt32Array) -> bool:
		got.append(c)
		return true

	func can_submit() -> bool:
		return true

	func local_pid() -> int:
		return 2

	func tick() -> int:
		return 77

	func is_observer() -> bool:
		return false

	func pending_count() -> int:
		return got.size()

	func send_chat(text: String, team_only: bool) -> void:
		chats.append("%s:%s" % [text, team_only])

	func send_map_ping(cx: int, cy: int) -> void:
		pings.append(Vector2i(cx, cy))


func test_audio_adapters(t: TestCtx) -> void:
	var rec := UiAudioPortRecorder.new()
	rec.ui(UiAudioPort.CLICK)
	rec.unit_selected(3, false, 5)
	rec.unit_ordered(UiAudioPort.Order.MOVE, 3)
	rec.order_denied(3)
	t.eq(rec.names(), PackedStringArray(["ui", "unit_selected", "unit_ordered", "order_denied"]))
	t.eq(rec.last_args(&"unit_selected"), [3, false, 5])
	t.eq(rec.count_of(&"ui"), 1)
	rec.clear()
	t.eq(rec.calls.size(), 0)
	var nul := UiAudioPortNull.new()
	nul.ui(UiAudioPort.CLICK)
	nul.unit_selected(1, true, 1)
	t.check(not nul.captions_enabled())
	t.check(not nul.announce(&"x"))
	# without the Snd autoload the adapter is a silent no-op
	var snd := UiAudioPortSnd.new()
	snd.ui(UiAudioPort.CLICK)
	snd.unit_ordered(0, 0)
	t.check(not snd.announce(&"x"))
	t.check(not snd.captions_enabled())


func test_loopback_port_drives_a_world(t: TestCtx) -> void:
	var w: SimWorld = SimTestKit.make_world()
	var u: SimEntity = SimTestKit.spawn_rifle(w, 0, 30 * 1024, 30 * 1024)
	var net := UiNetPortLoopback.new(w, 0)
	t.check(net.can_submit())
	t.check(net.submit(SimCmd.move(PackedInt32Array([u.id]), 40 * 1024, 30 * 1024)))
	t.eq(net.pending_count(), 1)
	w.step()
	w.step()
	t.check(not u.orders.is_empty() and u.orders[0].type == SimOrder.T_MOVE, "the command reached the sim")
	t.eq(net.pending_count(), 0, "the pending counter follows the tick")
	t.check(not net.submit(PackedInt32Array()))
	t.eq(net.tick(), w.tick)
	t.check(net.surrender(), "surrender = RESIGN")
	t.check(not UiNetPortLoopback.new(w, -1).can_submit(), "observers cannot submit")


func test_world_adapter_as_observer(t: TestCtx) -> void:
	var w: SimWorld = SimTestKit.make_world()
	SimTestKit.spawn_rifle(w, 0, 30 * 1024, 30 * 1024)
	SimTestKit.spawn_rifle(w, 1, 60 * 1024, 60 * 1024)
	w.step()
	var port := UiSimPortWorld.new(w, -1)
	t.eq(port.viewer_pid(), -1)
	var ids := PackedInt32Array()
	t.eq(port.own_ids(3, ids), 0, "an observer owns nothing")
	var snap := UiEntitySnapshot.new()
	port.snapshot(snap)
	t.ge(snap.count, 2, "but the snapshot lists everything")
	t.eq(port.visibility(1, 1), UiSimPort.Vis.VISIBLE, "omniscient")
	t.eq(port.credits(), 0)
	t.check(port.can_target(w.units_of(1)[0].id))
	port.set_viewer_pid(1)
	t.eq(port.own_ids(UiSimPort.KM_UNIT, ids), 1, "a chosen perspective restores that player's view")
