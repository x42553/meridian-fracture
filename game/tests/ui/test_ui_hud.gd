extends RefCounted
## HUD / presenter / placement / targeting / minimap over the scripted fixture (`hud_mid_match`) and the recorder net port
## (ui.md 5.10, 5.11, 5.12, 10.2 + UI-08b "presenter cadence test", "rotation of the Dock"), plus one real-world pass
## (SimPlacement ghost validity, a real BUILD_START / BUILD_PLACE round trip).

const H := preload("res://tests/ui/ui_harness.gd")
const _Rig := preload("res://tests/ui/ui_hud_rig.gd")


func _rig(size: Vector2i = Vector2i(1920, 1080), fixture: String = "hud_mid_match") -> Array:
	var h: H.Rig = await H.make(size)
	var r: _Rig = _Rig.new()
	r.build(h.root, {"fixture": UiSimPortFixture.load_file(fixture), "render": false})
	await H.frames(2)
	return [h, r]


func _power(f: UiSimPortFixture, supply: int, demand: int) -> void:
	var p: Dictionary = f._players[0]
	p["supply"] = supply
	p["demand"] = demand


func _sent(r: _Rig) -> PackedStringArray:
	return (r.net as UiNetPortRecorder).described()


func test_layout_size_classes(t: TestCtx) -> void:
	for sz: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var a: Array = await _rig(sz)
		var h: H.Rig = a[0]
		var r: _Rig = a[1]
		await H.frames(2)
		var sb: Rect2 = r.hud.sidebar().get_global_rect()
		t.eq(sb.size.x, float(UiMetrics.SIDEBAR_W), "sidebar width at %s" % [sz])
		t.check(is_equal_approx(sb.end.x, float(sz.x)), "sidebar hugs the right edge")
		var bp: Rect2 = r.hud.bottom().get_global_rect()
		t.check(bp.end.x <= sb.position.x + 1.0, "bottom panel stays left of the sidebar")
		t.check(bp.end.y <= float(sz.y), "bottom panel inside the window")
		t.check(bp.position.x >= 0.0, "bottom panel inside the window (left)")
		t.eq(r.hud.size_class, UiLayout.size_class(float(sz.y)))
		var m: Vector4 = r.hud.occluded_margins()
		t.eq(m.z, float(UiMetrics.SIDEBAR_W), "camera margin right = sidebar")
		t.check(m.w > 100.0, "camera margin bottom covers the panel")
		H.done(h)


func test_card_clicks_become_commands(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var d: GameData = r.data
	var barracks: UiBuildItem = r.card("Barracks")
	t.check(barracks != null, "barracks card")
	r.hud.build_requested.emit(barracks, 1)
	t.eq(_sent(r)[_sent(r).size() - 1], "BUILD_START def=%d count=1" % barracks.def_idx, "structure card -> BUILD_START")
	var narwhal: UiBuildItem = r.card("Narwhal Amphibious Tank")
	if t.not_null(narwhal, "narwhal card"):
		r.hud.build_requested.emit(narwhal, 5)
		t.eq(r.net.sent.back(), PackedInt32Array([124, 88, narwhal.def_idx, 5]), "Shift+click = one TRAIN x5 on the factory")
	var rifle: UiBuildItem = r.card("Rifle Squad")
	r.hud.build_requested.emit(rifle, 1)
	t.eq(r.net.sent.back(), PackedInt32Array([124, 89, rifle.def_idx, 1]), "the empty barracks trains the squad")
	# locked card: nothing is sent, the tab pulses
	var n_before: int = r.net.sent.size()
	var lab: UiBuildItem = r.card("Laboratory")
	if lab != null:
		lab.state = UiBuildItem.State.LOCKED
		lab.requires_text = "Radar"
		r.hud.build_requested.emit(lab, 1)
		t.eq(r.net.sent.size(), n_before, "a locked card sends nothing")
	# RMB on the building radar card: hold; on a held card: cancel
	var radar: UiBuildItem = r.card("Radar")
	radar.state = UiBuildItem.State.BUILDING
	radar.queued = 1
	r.hud.build_hold_requested.emit(radar)
	t.eq(_sent(r)[_sent(r).size() - 1], "BUILD_HOLD mode=1", "RMB on the building card holds the construction queue")
	radar.state = UiBuildItem.State.ON_HOLD
	r.hud.build_cancel_requested.emit(radar)
	t.eq(_sent(r)[_sent(r).size() - 1], "BUILD_CANCEL mode=0")
	t.check(d != null)
	H.done(h)


func test_cards_reach_the_widgets(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var sb: UiSidebar = r.hud.sidebar()
	t.eq(sb.active_tab(), UiBuildModel.Tab.STRUCTURES)
	var radar: UiBuildItem = r.card("Radar")
	var card: UiBuildCard = sb.card_for(radar)
	t.check(card != null, "the radar item has a card in the grid")
	t.eq(radar.state, UiBuildItem.State.BUILDING)
	t.eq(radar.progress_permille, 372, "fixture progress")
	t.eq(sb.credits().target, 12450, "credit ticker target")
	t.eq(sb.power_bar().capacity, 300)
	t.eq(sb.power_bar().usage, 265)
	r.presenter.call(&"_show_tab", UiBuildModel.Tab.VEHICLES)
	t.eq(sb.active_tab(), UiBuildModel.Tab.VEHICLES)
	t.check(sb.card_count() >= 5, "vehicle cards shown (%d)" % sb.card_count())
	H.done(h)


func test_presenter_cadence(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	var fac: UiBuildItem = r.card("Factory")
	fac.state = UiBuildItem.State.AVAILABLE
	f.set_credits(0, 10)
	r.presenter.on_ticks(1)
	# progress / economy every batch, card STATES only at 2 Hz (10 ticks)
	t.eq(r.hud.sidebar().credits().target, 10, "credits follow every batch")
	t.eq(fac.state, UiBuildItem.State.AVAILABLE, "card state unchanged before 10 ticks")
	for _i: int in 2:
		r.presenter.on_ticks(3)
	t.eq(fac.state, UiBuildItem.State.AVAILABLE, "still before 10 ticks (7 so far)")
	r.presenter.on_ticks(3)
	t.eq(fac.state, UiBuildItem.State.UNAFFORDABLE, "the 10th tick refreshes the states")
	# feed at 2 ticks: revision moves at most once per batch of >= 2 ticks
	r.presenter.refresh_all()
	var feed: UiMinimapFeed = r.hud.minimap()._feed
	var rev: int = feed.revision
	r.presenter.on_ticks(1)
	t.eq(feed.revision, rev, "1 tick: no feed rebuild")
	r.presenter.on_ticks(1)
	t.eq(feed.revision, rev + 1, "2 ticks: one rebuild")
	r.presenter.on_ticks(40)
	t.eq(feed.revision, rev + 2, "a 40-tick batch is ONE rebuild, not twenty")
	H.done(h)


func test_alerts_and_low_power(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	# a structure attack alert (class d = 1) on the barracks (b = 89)
	f.push_event(PackedInt32Array([UiEv.ATTACK_ALERT, 0, 70000, 60000, 0, 89, 1, 1]))
	for _i: int in 3:
		r.pump(10)
	t.check(r.hud.ribbons().get_ribbon(&"base_attack") != null, "BASE UNDER ATTACK ribbon")
	t.check(r.hud.minimap().ping_count() >= 1, "minimap ping at the attack")
	t.check(r.hud.log_feed().line_count() >= 1, "log line")
	# demand > supply -> LOW POWER ribbon, cleared when restored
	_power(f, 100, 250)
	r.pump(25)
	t.check(r.hud.ribbons().get_ribbon(&"low_power") != null, "LOW POWER ribbon")
	t.check(r.hud.sidebar().power_bar().is_low(), "power bar flags low power")
	_power(f, 300, 250)
	r.pump(25)
	t.check(r.hud.ribbons().get_ribbon(&"low_power") == null, "ribbon cleared")
	# enemy superweapon warning from the fixture (it starts at tick 16900)
	f.advance(1700)
	r.pump(25)
	t.check(r.hud.ribbons().get_ribbon(&"sw_warning_3") != null, "enemy superweapon countdown ribbon")
	H.done(h)


func test_placement_flow(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	var rad: int = f.data().structure_idx("structure.shared.radar")
	var pl: UiPlacement = r.placement
	f.set_construction(UiSimPort.Construction.READY_TO_PLACE, rad, 1000, 600)
	r.presenter.refresh_all()
	var card: UiBuildItem = r.card("Radar")
	t.eq(card.state, UiBuildItem.State.READY)
	r.hud.place_requested.emit(card)
	t.check(pl.active and pl.def_idx == rad, "READY card click starts placement")
	t.eq(r.modes.armed, UiModes.Armed.PLACE, "armed mode PLACE")
	# poll only when the anchor changes
	t.check(pl.update_cell(30, 30), "first cell polls")
	var polls: int = pl.polls
	t.check(not pl.update_cell(30, 30), "same cell: no poll")
	t.eq(pl.polls, polls)
	t.check(pl.valid, "fixture accepts the cell")
	f.set_bad_site(rad, pl.anchor.x + 1, pl.anchor.y, 2)
	t.check(pl.update_cell(31, 30) and not pl.valid, "bad site")
	t.eq(pl.reason_text(), "Blocked")
	t.eq(pl.cursor_state(), UiOrderIntent.CUR_DENIED)
	# invalid click keeps the mode and sends nothing
	var n: int = r.net.sent.size()
	t.check(not pl.commit(), "invalid commit refused")
	t.check(pl.active and r.net.sent.size() == n, "mode kept, nothing sent")
	# valid commit -> BUILD_PLACE at the top-left cell
	pl.update_cell(40, 40)
	t.check(pl.commit(), "valid commit")
	var fp: Vector2i = pl.footprint_size(rad, 0)
	var at: Vector2i = UiPlacement.anchor_for(40, 40, fp.x, fp.y)
	t.eq(r.net.sent.back(), PackedInt32Array([123, rad, at.x, at.y, 0]), "BUILD_PLACE golden")
	t.check(not pl.active, "placement ended")
	t.eq(pl.card_def(), rad, "the card shows PLACING while the sim answers")
	H.done(h)


func test_placement_rotation_only_for_the_dock(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	var pl: UiPlacement = r.placement
	var dock: int = f.data().structure_idx("structure.shared.dock")
	var fac: int = f.data().structure_idx("structure.shared.factory")
	pl.begin(fac)
	pl.update_cell(20, 20)
	t.check(not pl.rotate(), "factory footprints do not rotate")
	t.eq(pl.orient, 0)
	pl.begin(dock)
	pl.update_cell(20, 20)
	var w0: Vector2i = pl.footprint_size(dock, 0)
	t.check(pl.rotate(), "the dock rotates")
	t.eq(pl.orient, 1)
	t.eq(pl.footprint_size(dock, 1), Vector2i(w0.y, w0.x), "footprint swaps w / h on a quarter turn")
	t.eq(pl.anchor, UiPlacement.anchor_for(20, 20, w0.y, w0.x), "anchor re-centres on the pointer cell")
	t.check(pl.rotate(3) and pl.orient == 0, "four quarter turns wrap")
	H.done(h)


func test_targeting_point_and_line(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	var tg: UiTargeting = r.targeting
	var uav: int = f.data().power_idx("power.napc.uav_sweep")
	var repair: int = f.data().power_idx("power.napc.field_repair_drop")
	# a power that is on cooldown refuses to start and says so
	r.hud.power_pressed.emit(uav)
	t.check(not tg.active, "cooldown power does not arm targeting")
	# a READY power arms; the preview follows the pointer; a click commits USE_POWER
	r.hud.power_pressed.emit(repair)
	t.check(tg.active, "ready power arms targeting")
	tg.update(30 * 1024, 30 * 1024)
	t.check(tg.valid and r.hud.overlay().has_preview(), "preview shown")
	var n: int = r.net.sent.size()
	t.check(tg.press(30 * 1024, 30 * 1024), "click commits")
	t.eq(r.net.sent.size(), n + 1)
	t.check(_sent(r)[_sent(r).size() - 1].begins_with("USE_POWER"), "USE_POWER command: %s" % [_sent(r)[_sent(r).size() - 1]])
	t.check(not tg.active and not r.hud.overlay().has_preview(), "ended, preview cleared")
	# Esc / RMB cancels
	r.hud.power_pressed.emit(repair)
	t.check(tg.active)
	tg.cancel()
	t.check(not tg.active)
	t.eq(UiTargeting.angle_of(0, 1024), 1024, "+y is a quarter turn")
	t.eq(UiTargeting.angle_of(-1024, 0), 2048)
	t.eq(UiTargeting.angle_of(1024, 0), 0)
	H.done(h)


func test_superweapon_targeting(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	r.hud.power_pressed.emit(UiPowerDock.SUPERWEAPON)
	t.check(not r.targeting.active, "charging superweapon refuses")
	f.set_superweapon(UiSimPort.SwStatus.READY, f.data().superweapon_idx("superweapon.napc.atlas_kinetic_array"), 1000, 0, 91)
	r.hud.power_pressed.emit(UiPowerDock.SUPERWEAPON)
	t.check(r.targeting.active and r.targeting.kind == UiTargeting.Kind.SUPERWEAPON, "ready superweapon arms")
	r.targeting.update(50 * 1024, 50 * 1024)
	t.check(r.targeting.radius_units > 0, "radius resolved from the def")
	if r.targeting.is_line():
		t.check(r.targeting.press(50 * 1024, 50 * 1024))
		t.check(r.targeting.release(52 * 1024, 50 * 1024))
	else:
		t.check(r.targeting.press(50 * 1024, 50 * 1024))
	t.check(_sent(r)[_sent(r).size() - 1].begins_with("LAUNCH_SUPERWEAPON"), "LAUNCH_SUPERWEAPON: %s" % [_sent(r)])
	H.done(h)


func test_minimap_feed_and_input(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	var feed := UiMinimapFeed.new()
	feed.rebuild(f)
	t.check(feed.dot_count() > 5, "own base and army are on the minimap (%d)" % feed.dot_count())
	var own: int = 0
	for o: int in feed.dots_own:
		own += o
	t.check(own > 0, "own blips flagged")
	# fog rule: an enemy the viewer cannot see never reaches the feed
	var foe: UiEntityRow = f.spawn("unit.napc.guardian_tank", 1, 100000, 100000, 5000)
	feed.rebuild(f)
	var with_foe: int = feed.dot_count()
	f.hide_entity(foe.id)
	feed.rebuild(f)
	t.eq(feed.dot_count(), with_foe - 1, "a fogged enemy is not on the minimap")
	# widget input: press = camera, double = snap, RMB = order with modifiers
	var mm: UiMinimap = r.hud.minimap()
	var got: Array = []
	mm.camera_requested.connect(func(n: Vector2) -> void: got.append(["cam", n]))
	mm.camera_snap.connect(func(n: Vector2) -> void: got.append(["snap", n]))
	mm.order_requested.connect(func(n: Vector2, m: int) -> void: got.append(["order", n, m]))
	var box: Rect2 = mm.get_global_rect()
	var mr: Rect2 = mm.map_rect()
	var c: Vector2 = box.position + mr.get_center()
	H.click(h.vp, c)
	t.check(got.size() >= 1 and got[0][0] == "cam", "LMB press asks for the camera")
	t.check((got[0][1] as Vector2).distance_to(Vector2(0.5, 0.5)) < 0.05, "at the map centre")
	H.click(h.vp, c, MOUSE_BUTTON_RIGHT)
	t.check(got.back()[0] == "order", "RMB orders")
	t.eq(mm.norm_to_sim(Vector2(0.5, 0.5)), Vector2i(64 * 1024, 64 * 1024), "norm -> sim units")
	H.done(h)


func test_bottom_panel_and_command_bar(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var f: UiSimPortFixture = r.sim as UiSimPortFixture
	# the fixture flags its `selected` entities: select them like a box would
	r.selection.replace(f.selected, f)
	r.pump(2)
	var view: UiSelectionView = r.hud.bottom().selection_view()
	t.check(not r.selection.is_empty(), "fixture selection")
	var cb: UiCommandBar = r.hud.bottom().commands()
	t.check(cb.button(&"stop").enabled, "mobile units can stop")
	t.check(cb.button(&"attack_move").enabled, "armed mobile units can attack-move")
	var n: int = r.net.sent.size()
	r.hud.command_pressed.emit(&"stop")
	t.eq(r.net.sent.size(), n + 1, "Stop -> one command")
	t.eq(_sent(r)[_sent(r).size() - 1].substr(0, 4), "STOP")
	r.hud.command_pressed.emit(&"attack_move")
	t.eq(r.modes.armed, UiModes.Armed.ATTACK_MOVE, "attack-move arms the mode, sends nothing yet")
	t.check(cb.button(&"attack_move").active, "armed button lights up")
	r.hud.command_pressed.emit(&"attack_move")
	t.eq(r.modes.armed, UiModes.Armed.NONE, "second press disarms")
	t.check(view.capacity() > 0)
	# empty selection disables the orders
	r.selection.clear()
	r.pump(2)
	t.check(not cb.button(&"stop").enabled, "no selection: orders disabled")
	H.done(h)


func test_camera_pad_and_group_bar(t: TestCtx) -> void:
	var a: Array = await _rig()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var ids: PackedInt32Array = r.own(UiSimPort.KM_UNIT)
	t.check(not ids.is_empty())
	var got: Array = []
	r.hud.group_pressed.connect(func(i: int, d: bool) -> void: got.append([i, d]))
	r.groups.assign(2, ids.slice(0, 3))
	r.pump(20)
	var gb: UiGroupBar = r.hud.bottom().group_bar()
	t.eq(int(gb.groups[2].get("count", 0)), mini(3, ids.size()), "badge shows the alive member count")
	var pad: UiCameraPad = r.hud.sidebar().camera_pad()
	var pads: Array = []
	pad.pad_pressed.connect(func(id: StringName) -> void: pads.append(id))
	var b0: Rect2 = pad.button_rect(0)
	H.click(h.vp, pad.get_global_rect().position + b0.get_center())
	t.eq(pads.size(), 1, "pad button emits once")
	H.done(h)


func test_real_world_placement_and_build(t: TestCtx) -> void:
	var a: Array = await _rig_real()
	var h: H.Rig = a[0]
	var r: _Rig = a[1]
	var w: SimWorld = r.world
	# start a real Generator, run the sim until READY, then place it through the placement flow
	var gen: UiBuildItem = r.card("Generator")
	if not t.not_null(gen, "generator card"):
		H.done(h)
		return
	w.players[0].credits = 5000
	t.check(r.click_card("Generator"), "card click")
	r.pump(2)
	t.eq(r.card("Generator").state, UiBuildItem.State.BUILDING, "the real world builds it")
	var guard: int = 0
	while r.card("Generator").state != UiBuildItem.State.READY and guard < 120:
		r.pump(10)
		guard += 1
	t.eq(r.card("Generator").state, UiBuildItem.State.READY, "ready after %d ticks" % (guard * 10))
	r.hud.place_requested.emit(r.card("Generator"))
	var pl: UiPlacement = r.placement
	t.check(pl.active)
	var c: Vector2i = r.base_center()
	# a cell far outside the build radius is invalid with the sim's own reason
	pl.update_cell(c.x / 1024 + 40, c.y / 1024)
	t.check(not pl.valid, "outside the build radius")
	t.check(pl.reason_text() != "", "reason text: %s" % pl.reason_text())
	# find a valid cell near the HQ by scanning (SimPlacement is the judge)
	var placed: bool = false
	for dy: int in range(-6, 7):
		for dx: int in range(-7, 8):
			if pl.update_cell(c.x / 1024 + dx, c.y / 1024 + dy) and pl.valid and not placed:
				t.check(pl.commit(), "commit on a valid cell")
				placed = true
	if t.check(placed, "some cell near the HQ accepts a generator"):
		r.pump(4)
		var n_gen: int = 0
		for e: SimEntity in w.structures_of(0):
			if e.def_idx == gen.def_idx:
				n_gen += 1
		t.check(n_gen >= 1, "the structure exists in the world")
	H.done(h)


func _rig_real() -> Array:
	var h: H.Rig = await H.make(Vector2i(1920, 1080))
	var r: _Rig = _Rig.new()
	r.build(h.root, {"seed": 2, "render": false})
	await H.frames(2)
	return [h, r]
