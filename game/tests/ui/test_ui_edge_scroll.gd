extends RefCounted
## Edge scroll band and drag threshold (ui.md 5.5.2 / 5.5.5, 10.2 `test_ui_edge_scroll`): pure functions.

const VIEW: Rect2 = Rect2(0.0, 0.0, 1920.0, 1080.0)


func test_edge_direction_worked_values(t: TestCtx) -> void:
	var cases: Array = [
		[Vector2(2, 300), Vector2(-1, 0)], [Vector2(1919, 1079), Vector2(1, 1)], [Vector2(-40, 300), Vector2(0, 0)],
		[Vector2(960, 3), Vector2(0, -1)], [Vector2(6, 540), Vector2(-1, 0)], [Vector2(7, 540), Vector2(0, 0)],
		[Vector2(960, 540), Vector2(0, 0)], [Vector2(1914, 540), Vector2(1, 0)], [Vector2(1913, 540), Vector2(0, 0)],
		[Vector2(0, 0), Vector2(-1, -1)], [Vector2(1920, 540), Vector2(0, 0)], [Vector2(960, 1079), Vector2(0, 1)],
		[Vector2(960, 1081), Vector2(0, 0)],
	]
	for c: Array in cases:
		t.eq(UiInputController.edge_direction(c[0], VIEW), c[1], "edge_direction%s" % c[0])
	t.eq(UiInputController.edge_direction(Vector2(20, 300), VIEW, 24.0), Vector2(-1, 0), "margin is a parameter")
	t.eq(UiInputController.edge_direction(Vector2(110, 4), Rect2(100, 0, 200, 100)), Vector2(0, -1), "views need not start at 0")


func test_drag_threshold(t: TestCtx) -> void:
	var p: Vector2 = Vector2(100, 100)
	t.check(not UiInputController.drag_exceeded(p, Vector2(103, 104)), "distance 5.0")
	t.check(not UiInputController.drag_exceeded(p, Vector2(104, 104)), "distance 5.66")
	t.check(UiInputController.drag_exceeded(p, Vector2(106, 100)), "distance 6.0 counts")
	t.check(UiInputController.drag_exceeded(p, Vector2(105, 105)), "distance 7.07")
	t.check(UiInputController.drag_exceeded(p, Vector2(104, 104), 5.0), "the threshold is a parameter")
