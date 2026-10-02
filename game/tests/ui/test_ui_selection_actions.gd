extends RefCounted
## Keyboard / menu selection commands over the fixture port (ui.md 5.5.4, 5.11.7, 10.2 `test_ui_selection_actions`).

const RIFLE: String = "unit.napc.rifle_squad"
const TANK: String = "unit.napc.guardian_tank"
const COLLECTOR: String = "unit.shared.collector"
const ENGINEER: String = "unit.shared.engineer"
const BARRACKS: String = "structure.shared.barracks"
const FACTORY: String = "structure.shared.factory"
const HQ: String = "structure.shared.headquarters"
const ON: Rect2 = Rect2(100.0, 100.0, 40.0, 40.0)
const OFF: Rect2 = Rect2(4000.0, 100.0, 40.0, 40.0)


## The bits of UiViewPort the actions use.
class FakeView extends RefCounted:
	var rects: Dictionary = {}
	var focused: Array[Vector2i] = []
	var focus_x: float = 0.0
	var focus_z: float = 0.0

	func entity_screen_rect(eid: int) -> Rect2:
		return rects.get(eid, Rect2(-100.0, -100.0, 10.0, 10.0))

	func focus_on_sim(x: int, y: int, _instant: bool = false) -> void:
		focused.append(Vector2i(x, y))

	func camera_state() -> Dictionary:
		return {"focus_x": focus_x, "focus_z": focus_z}


func _world() -> Array:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 1000)
	f.add_player(1, "Foe", 2, "roster.napc.canada")
	f.set_viewer(0)
	var v := FakeView.new()
	var sel := UiSelection.new()
	var act := UiSelectionActions.new()
	act.setup(f, v, sel, null)
	return [f, v, sel, act]


func test_same_type_on_screen_excludes_offscreen_twins(t: TestCtx) -> void:
	var w: Array = _world()
	var f: UiSimPortFixture = w[0]
	var v: FakeView = w[1]
	var act: UiSelectionActions = w[3]
	var d: int = f.data().unit_idx(RIFLE)
	f.spawn(RIFLE, 0, 1, 1, 11)
	f.spawn(RIFLE, 0, 2, 1, 12)
	f.spawn(RIFLE, 0, 3, 1, 13)
	f.spawn(RIFLE, 1, 4, 1, 14)
	f.spawn(TANK, 0, 5, 1, 15)
	f.row_of(13).flags |= UiEntityRow.F_LOADED
	v.rects = {11: ON, 12: OFF, 13: ON, 14: ON, 15: ON}
	t.eq(act.same_type_on_screen(UiSimPort.KIND_UNIT, d), PackedInt32Array([11]), "only the on-screen own, non-contained twin")
	t.eq(act.same_type_on_map(UiSimPort.KIND_UNIT, d), PackedInt32Array([11, 12]), "the whole map: both, but not the enemy or the contained one")


func test_all_military(t: TestCtx) -> void:
	var w: Array = _world()
	var f: UiSimPortFixture = w[0]
	var v: FakeView = w[1]
	var act: UiSelectionActions = w[3]
	f.spawn(TANK, 0, 1, 1, 21)
	f.spawn(TANK, 0, 2, 1, 22)
	f.spawn(COLLECTOR, 0, 3, 1, 23)
	f.spawn(ENGINEER, 0, 4, 1, 24)
	f.spawn(BARRACKS, 0, 5, 1, 25)
	f.spawn(TANK, 1, 6, 1, 26)
	v.rects = {21: ON, 22: OFF, 23: ON, 24: ON, 25: ON, 26: ON}
	t.eq(act.all_military(false), PackedInt32Array([21, 22]), "structures, collectors, engineers and enemies are not military")
	t.eq(act.all_military(true), PackedInt32Array([21]), "on screen drops the off-screen tank")


func test_next_idle_walks_ascending_and_centres_camera(t: TestCtx) -> void:
	var w: Array = _world()
	var f: UiSimPortFixture = w[0]
	var v: FakeView = w[1]
	var sel: UiSelection = w[2]
	var act: UiSelectionActions = w[3]
	f.spawn(TANK, 0, 1000, 2000, 31)
	f.spawn(TANK, 0, 3000, 4000, 32).order_kind = UiEntityRow.O_MOVING
	f.spawn(RIFLE, 0, 5000, 6000, 33)
	f.spawn(COLLECTOR, 0, 7000, 8000, 34)
	t.eq(act.next_idle(1), 31)
	t.eq(sel.ids, PackedInt32Array([31]), "the unit is selected")
	t.eq(v.focused.back(), Vector2i(1000, 2000), "and the camera is centred on it")
	t.eq(act.next_idle(1), 33, "the moving tank is skipped")
	t.eq(act.next_idle(1), 31, "wraps to the first")
	t.eq(act.next_idle(-1), 33, "backwards")
	t.eq(v.focused.size(), 4)


func test_next_idle_none(t: TestCtx) -> void:
	var w: Array = _world()
	var act: UiSelectionActions = w[3]
	var keys: Array[StringName] = []
	act.nothing_found.connect(func(k: StringName) -> void: keys.append(k))
	t.eq(act.next_idle(1), -1)
	t.eq(keys.size(), 1)
	t.eq(act.next_collector(), -1)
	t.eq(act.next_producer(), -1)
	t.eq(act.hq(), -1)
	t.eq(keys.size(), 4)


func test_collectors_and_producers_cycle(t: TestCtx) -> void:
	var w: Array = _world()
	var f: UiSimPortFixture = w[0]
	var act: UiSelectionActions = w[3]
	f.spawn(COLLECTOR, 0, 1, 1, 41)
	f.spawn(COLLECTOR, 0, 2, 1, 42)
	f.spawn(BARRACKS, 0, 3, 1, 43)
	f.spawn(FACTORY, 0, 4, 1, 44)
	f.spawn(HQ, 0, 5, 1, 45)
	t.eq(act.next_collector(), 41)
	t.eq(act.next_collector(), 42)
	t.eq(act.next_collector(), 41, "wraps")
	t.eq(act.next_producer(), 43)
	t.eq(act.next_producer(), 44)
	t.eq(act.next_producer(), 43, "the HQ is not a producer")


func test_hq_picks_nearest_own(t: TestCtx) -> void:
	var w: Array = _world()
	var f: UiSimPortFixture = w[0]
	var v: FakeView = w[1]
	var act: UiSelectionActions = w[3]
	f.spawn(HQ, 0, 10 * 1024, 10 * 1024, 51)
	f.spawn(HQ, 0, 100 * 1024, 100 * 1024, 52)
	f.spawn(HQ, 1, 11 * 1024, 11 * 1024, 53)
	v.focus_x = 290.0
	v.focus_z = 290.0
	t.eq(act.hq(), 52, "nearest to the camera focus (world metres -> sim units)")
	v.focus_x = 0.0
	v.focus_z = 0.0
	t.eq(act.hq(), 51)
