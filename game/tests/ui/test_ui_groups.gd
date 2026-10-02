extends RefCounted
## Control groups and bookmarks (ui.md 5.11.3, 10.2 `test_ui_groups`) over the fixture port.

const TANK: String = "unit.napc.guardian_tank"


func _world() -> UiSimPortFixture:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 1000)
	f.add_player(1, "Foe", 2, "roster.napc.canada")
	f.set_viewer(0)
	return f


func test_assign_add_and_recall(t: TestCtx) -> void:
	var f: UiSimPortFixture = _world()
	for i: int in 5:
		f.spawn(TANK, 0, i * 1024, 0, 10 + i)
	var g := UiControlGroups.new()
	var fired: Array[int] = []
	g.changed.connect(func(i: int) -> void: fired.append(i))
	g.assign(3, PackedInt32Array([12, 10, 11, 10]))
	t.eq(g.members(3), PackedInt32Array([10, 11, 12]), "assign stores ascending unique ids")
	g.add_to(3, PackedInt32Array([14, 11]))
	t.eq(g.members(3), PackedInt32Array([10, 11, 12, 14]), "add_to merges")
	g.assign(3, PackedInt32Array([13]))
	t.eq(g.members(3), PackedInt32Array([13]), "assign replaces")
	t.eq(fired, [3, 3, 3])
	g.assign(0, PackedInt32Array([10, 11]))
	t.eq(g.recall(0, f), PackedInt32Array([10, 11]), "digit 0 is group 0")
	t.eq(g.count(0, f), 2)
	g.assign(10, PackedInt32Array([10]))
	t.eq(g.members(10), PackedInt32Array(), "out-of-range indices are ignored")
	t.check(g.is_empty(9))


func test_recall_skips_and_drops_dead(t: TestCtx) -> void:
	var f: UiSimPortFixture = _world()
	f.spawn(TANK, 0, 0, 0, 1)
	f.spawn(TANK, 0, 1024, 0, 2)
	f.spawn(TANK, 0, 2048, 0, 3)
	f.spawn(TANK, 1, 4096, 0, 4)  # an enemy id smuggled into a group is dropped too
	var loaded: UiEntityRow = f.spawn(TANK, 0, 0, 0, 5)
	loaded.flags |= UiEntityRow.F_LOADED
	var g := UiControlGroups.new()
	g.assign(1, PackedInt32Array([1, 2, 3, 4, 5]))
	t.eq(g.count(1, f), 3, "count: alive, own, uncontained")
	f.remove_entity(2)
	t.eq(g.recall(1, f), PackedInt32Array([1, 3]), "dead, foreign and contained members are not recalled")
	t.eq(g.members(1), PackedInt32Array([1, 3, 5]), "dead / foreign dropped permanently; the contained one stays")
	f.remove_entity(1)
	f.remove_entity(3)
	t.eq(g.recall(1, f), PackedInt32Array(), "only the contained member is left: nothing to select")
	f.remove_entity(5)
	g.recall(1, f)
	t.check(g.is_empty(1), "an all-dead group ends up empty")
	t.eq(g.centroid_sim(1, f), Vector2i(-1, -1), "no centroid for an empty group")


func test_double_tap_window(t: TestCtx) -> void:
	var g := UiControlGroups.new()
	t.check(not g.register_press(2, 1000), "first press")
	t.check(g.register_press(2, 1349), "second press 349 ms later is a double tap")
	t.check(not g.register_press(2, 1400), "the detector reset after a double tap")
	t.check(not g.register_press(2, 2000))
	t.check(not g.register_press(2, 2351), "351 ms is too late")
	t.check(not g.register_press(3, 2400), "another group restarts")
	t.check(g.register_press(3, 2500))
	g.double_tap_ms = 200
	g.register_press(4, 5000)
	t.check(not g.register_press(4, 5250), "the window is configurable")


func test_centroid_and_cycling(t: TestCtx) -> void:
	var f: UiSimPortFixture = _world()
	f.spawn(TANK, 0, 0, 0, 1)
	f.spawn(TANK, 0, 2048, 4096, 2)
	var g := UiControlGroups.new()
	g.assign(5, PackedInt32Array([1, 2]))
	t.eq(g.centroid_sim(5, f), Vector2i(1024, 2048), "centroid of (0,0) and (2048,4096)")
	g.assign(8, PackedInt32Array([2]))
	t.eq(g.next_nonempty(-1), 5)
	t.eq(g.next_nonempty(5), 8, "skips empty groups")
	t.eq(g.next_nonempty(8), 5, "cycles")
	g.clear_all()
	t.eq(g.next_nonempty(0), -1)


func test_bookmarks(t: TestCtx) -> void:
	var b := UiBookmarks.new()
	t.eq(b.get_slot(0), {}, "unset slot is empty")
	var st: Dictionary = {"focus_x": 12.5, "focus_z": 40.0, "yaw": 30.0, "zoom": 60.0, "pitch_bias": 0.0}
	b.set_slot(2, st)
	st["yaw"] = 99.0
	t.eq(b.get_slot(2)["yaw"], 30.0, "stored by value")
	t.check(b.has_slot(2) and not b.has_slot(1))
	b.set_slot(7, st)
	t.eq(b.get_slot(7), {}, "only 4 slots")
	b.clear(2)
	t.check(not b.has_slot(2))
