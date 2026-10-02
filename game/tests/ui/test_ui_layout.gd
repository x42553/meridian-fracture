extends RefCounted
## Scale rule, size classes and layout maths (ui.md 5.4, 4.6.1, test row `test_ui_layout`).


func test_factor_table(t: TestCtx) -> void:
	var rows: Array = [
		[Vector2i(1920, 1080), 1.0, 1.0, 1920.0, 1080.0],
		[Vector2i(1600, 900), 1.0, 0.8333, 1920.0, 1080.0],
		[Vector2i(1280, 720), 1.0, 0.75, 1706.7, 960.0],
		[Vector2i(1366, 768), 1.0, 0.75, 1821.3, 1024.0],
		[Vector2i(1024, 576), 1.0, 0.75, 1365.3, 768.0],
		[Vector2i(2560, 1440), 1.0, 1.3333, 1920.0, 1080.0],
		[Vector2i(3440, 1440), 1.0, 1.3333, 2580.0, 1080.0],
		[Vector2i(3840, 2160), 1.0, 2.0, 1920.0, 1080.0],
		[Vector2i(3840, 2160), 1.25, 2.5, 1536.0, 864.0],
		[Vector2i(1920, 1080), 1.5, 1.5, 1280.0, 720.0],
		[Vector2i(1920, 1080), 2.0, 2.0, 960.0, 540.0],
		[Vector2i(1280, 720), 2.0, 1.3333, 960.0, 540.0],
		[Vector2i(3840, 2160), 2.0, 4.0, 960.0, 540.0],
		[Vector2i(5120, 2880), 1.0, 2.0, 2560.0, 1440.0],
	]
	for row: Array in rows:
		var px: Vector2i = row[0]
		var f: float = UiLayout.factor(px, float(row[1]))
		t.near(f, float(row[2]), 0.001, "factor %s @%s" % [px, row[1]])
		var ls: Vector2 = UiLayout.logical_size(px, f)
		t.near(ls.x, float(row[3]), 0.1, "logical w %s" % px)
		t.near(ls.y, float(row[4]), 0.1, "logical h %s" % px)


func test_factor_exact_cases(t: TestCtx) -> void:
	t.eq(UiLayout.factor(Vector2i(1920, 1080), 1.0), 1.0)
	t.eq(UiLayout.factor(Vector2i(3840, 2160), 1.0), 2.0)
	t.eq(UiLayout.factor(Vector2i(5120, 2880), 1.0), 2.0)
	t.near(UiLayout.factor(Vector2i(2560, 1440), 1.0), 1.3333, 0.0001)
	# absolute guard
	t.eq(UiLayout.factor(Vector2i(320, 200), 0.1), 0.5)


func test_minimap_size(t: TestCtx) -> void:
	t.near(UiLayout.minimap_size(960.0), 297.0, 0.001)
	t.near(UiLayout.minimap_size(1080.0), 300.0, 0.001)
	t.near(UiLayout.minimap_size(800.0), 209.0, 0.001)
	t.near(UiLayout.minimap_size(720.0), 180.0, 0.001)
	t.near(UiLayout.minimap_size(600.0), 180.0, 0.001)


func test_size_classes(t: TestCtx) -> void:
	t.eq(UiLayout.size_class(799.0), UiLayout.SizeClass.COMPACT)
	t.eq(UiLayout.size_class(800.0), UiLayout.SizeClass.REGULAR)
	t.eq(UiLayout.size_class(1299.0), UiLayout.SizeClass.REGULAR)
	t.eq(UiLayout.size_class(1300.0), UiLayout.SizeClass.LARGE)
	t.eq(UiLayout.log_lines(UiLayout.SizeClass.COMPACT), 4)
	t.eq(UiLayout.log_lines(UiLayout.SizeClass.REGULAR), 6)
	t.eq(UiLayout.log_lines(UiLayout.SizeClass.LARGE), 10)


func test_bottom_panel_width(t: TestCtx) -> void:
	t.near(UiLayout.bottom_panel_width(1358.0), 900.0, 0.001)
	t.near(UiLayout.bottom_panel_width(700.0), 660.0, 0.001)
	t.near(UiLayout.bottom_panel_width(500.0), 600.0, 0.001)
	t.near(UiLayout.bottom_panel_width(1900.0, UiLayout.SizeClass.LARGE), 1000.0, 0.001)
	t.near(UiLayout.playfield_width(1920.0), 1572.0, 0.001)


func test_metrics_table(t: TestCtx) -> void:
	t.eq(UiMetrics.SIDEBAR_W, 348)
	t.eq(UiMetrics.TAB_SIZE * 8 + UiMetrics.TAB_GAP * 7, 318, "8 tabs fit the 320 px inner width")
	t.eq(UiMetrics.GROUP_BADGE.x * 10.0 + float(UiMetrics.GROUP_GAP) * 9.0, 636.0, "10 group badges")
	t.eq(UiMetrics.MIN_WINDOW, Vector2i(1024, 576))
	t.check(UiMetrics.FS_SMALL >= UiMetrics.MIN_ESSENTIAL_PX and UiMetrics.FS_CAPTION >= UiMetrics.MIN_ESSENTIAL_PX and UiMetrics.FS_HEAD >= UiMetrics.MIN_ESSENTIAL_PX, "no essential text below 14 px")


func test_apply_sets_window(t: TestCtx) -> void:
	var w := Window.new()
	w.size = Vector2i(1280, 720)
	var f: float = UiLayout.apply(w, 1.0)
	t.near(f, 0.75, 0.0001)
	t.near(w.content_scale_factor, 0.75, 0.0001)
	t.eq(w.min_size, Vector2i(1024, 576))
	w.free()
