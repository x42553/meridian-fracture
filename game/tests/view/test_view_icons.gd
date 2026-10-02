extends RefCounted
## VIEW-M9: ViewIconBake. Framing maths, cache keys, the disk cache-hit path (< 2 ms per icon), request bookkeeping and the
## headless fallbacks. The pixel checks (corner alpha 0, non-empty body) need a renderer: `tools/gd run res://tests/visual/icon_check.tscn`.

const TEST_DIR: String = "user://cache/icons_test"


func _bake() -> ViewIconBake:
	var b: ViewIconBake = ViewIconBake.new()
	b.setup_standalone()
	b.cache_dir = TEST_DIR
	b.render_enabled = false
	return b


## The test runner's root is busy during _initialize: nodes go in deferred and are in the tree one frame later.
func _attach(n: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child.call_deferred(n)
	await tree.process_frame


func _clean() -> void:
	var da: DirAccess = DirAccess.open(TEST_DIR)
	if da != null:
		for f: String in da.get_files():
			da.remove(f)


func test_frame_camera_fits_every_shape(t: TestCtx) -> void:
	var boxes: Array[AABB] = [
		AABB(Vector3(-1.4, 0.0, -2.6), Vector3(2.8, 1.9, 5.2)),  # tank
		AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 6.5, 1.2)),  # tower
		AABB(Vector3(-5.0, 0.0, -4.0), Vector3(10.0, 3.0, 8.0)),  # structure
		AABB(Vector3(-4.5, 0.5, -3.0), Vector3(9.0, 1.2, 6.0)),  # aircraft
	]
	for aspect: float in [4.0 / 3.0, 188.0 / 124.0, 2.0]:
		for b: AABB in boxes:
			var pose: Dictionary = ViewIconBake.frame_camera(b, ViewIconBake.YAW_DEG, ViewIconBake.PITCH_DEG, ViewIconBake.FOV_DEG, aspect, ViewIconBake.MARGIN)
			var cb: Basis = pose["basis"] as Basis
			var pos: Vector3 = pose["pos"] as Vector3
			var tan_v: float = tan(deg_to_rad(ViewIconBake.FOV_DEG) * 0.5)
			var rot: Basis = Basis(Vector3.UP, deg_to_rad(ViewIconBake.YAW_DEG))
			var lo: Vector2 = Vector2(INF, INF)
			var hi: Vector2 = Vector2(-INF, -INF)
			for i: int in 8:
				var v: Vector3 = cb.inverse() * (rot * b.get_endpoint(i) - pos)
				var p: Vector2 = Vector2(v.x / (-v.z * tan_v * aspect), v.y / (-v.z * tan_v))
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			var half: float = maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
			t.check(half <= ViewIconBake.MARGIN * 1.01, "bounds inside the margin (%.3f) size %s aspect %.2f" % [half, b.size, aspect])
			t.check(half >= ViewIconBake.MARGIN * 0.96, "and fill it (%.3f)" % half)
			t.check(absf((lo.x + hi.x) * 0.5) < 0.02 and absf((lo.y + hi.y) * 0.5) < 0.02, "centred")


func test_content_key_separates_size_look_and_version(t: TestCtx) -> void:
	var a: String = ViewIconBake.content_key(0x1234, 7, Vector2i(188, 124))
	t.eq(a, ViewIconBake.content_key(0x1234, 7, Vector2i(188, 124)), "stable")
	t.ne(a, ViewIconBake.content_key(0x1234, 7, Vector2i(128, 96)), "size is part of the key")
	t.ne(a, ViewIconBake.content_key(0x1235, 7, Vector2i(188, 124)), "content hash is part of the key")
	t.ne(a, ViewIconBake.content_key(0x1234, 8, Vector2i(188, 124)), "style look is part of the key")
	t.check(a.contains("_v%d_" % ViewIconBake.VERSION), "studio version is part of the key")


func test_cache_hit_path_is_fast_and_async(t: TestCtx) -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var b: ViewIconBake = _bake()
	await _attach(b)
	var ids: PackedStringArray = PackedStringArray()
	for rid: String in b.recipe_book().ids():
		if rid.begins_with("unit.napc.") or rid.begins_with("structure.napc."):
			ids.append(rid)
			if ids.size() >= 16:
				break
	t.gt(ids.size(), 5, "recipes to test with")
	var style: StringName = &"napc"
	var sz: int = ViewIconBake.S_CARD
	var px: Vector2i = ViewIconBake.SIZES[sz]
	# fabricate the cache files a real bake would have written (transparent corners, opaque body)
	for rid2: String in ids:
		var img: Image = Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(px.x / 4, px.y / 4, px.x / 2, px.y / 2), Color(0.3, 0.6, 0.3, 1.0))
		img.save_png(b.cache_path(b.cache_key_for(StringName(rid2), style, 10000, sz)))
	var got: Array = []
	b.icon_ready.connect(func(tag: StringName) -> void: got.append(tag))
	for rid3: String in ids:
		t.is_null(b.request(StringName(rid3), StringName(rid3), style, 10000, sz), "first request is asynchronous: null")
	await b.wait_idle()
	t.eq(got.size(), ids.size(), "icon_ready fired once per request")
	t.eq(int(b.stats["hits"]), ids.size(), "every request was a disk cache hit")
	t.eq(int(b.stats["bakes"]), 0, "nothing rendered")
	var avg_us: float = float(b.stats["hit_us_sum"]) / float(maxi(ids.size(), 1))
	t.note("cache hit: avg %.0f us, max %d us over %d icons" % [avg_us, int(b.stats["hit_us_max"]), ids.size()])
	t.lt(avg_us, 2000.0, "cache-hit path under 2 ms per icon on average")
	var tex: Texture2D = b.request(&"again", StringName(ids[0]), style, 10000, sz)
	t.not_null(tex, "second request is served from memory")
	t.eq(tex.get_width(), px.x, "texture width")
	t.eq(tex.get_height(), px.y, "texture height")
	t.eq(tex.get_image().get_pixel(0, 0).a, 0.0, "corner alpha 0 survives the cache")
	# memory hit timing
	var t0: int = Time.get_ticks_usec()
	for i: int in 200:
		b.request(&"again", StringName(ids[0]), style, 10000, sz)
	t.lt(float(Time.get_ticks_usec() - t0) / 200.0, 50.0, "memory hit under 50 us")
	b.queue_free()
	_clean()


func test_headless_miss_is_skipped_not_stuck(t: TestCtx) -> void:
	_clean()
	var b: ViewIconBake = _bake()
	await _attach(b)
	var rid: StringName = StringName(b.recipe_book().ids()[0])
	t.is_null(b.request(&"x", rid, &"neutral", 10000, ViewIconBake.S_ICON), "no cache file, no renderer: null")
	await b.wait_idle()
	t.eq(int(b.stats["skipped"]), 1, "counted as skipped")
	t.check(b.is_idle(), "queue drained")
	t.is_null(b.peek(rid, &"neutral", 10000, ViewIconBake.S_ICON), "nothing in memory")
	b.queue_free()


func test_requests_dedupe_and_share_content(t: TestCtx) -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var b: ViewIconBake = _bake()
	await _attach(b)
	var rid: StringName = StringName(b.recipe_book().ids()[0])
	var px: Vector2i = ViewIconBake.SIZES[ViewIconBake.S_ICON]
	var img: Image = Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
	img.save_png(b.cache_path(b.cache_key_for(rid, &"neutral", 10000, ViewIconBake.S_ICON)))
	var tags: Array = []
	b.icon_ready.connect(func(tag: StringName) -> void: tags.append(tag))
	b.request(&"a", rid, &"neutral", 10000, ViewIconBake.S_ICON)
	b.request(&"b", rid, &"neutral", 10000, ViewIconBake.S_ICON)
	b.request(&"a", rid, &"neutral", 10000, ViewIconBake.S_ICON)
	t.eq(b.pending(), 1, "one job for one (recipe, style, size)")
	await b.wait_idle()
	t.eq(tags.size(), 2, "both distinct tags are told, each once")
	b.queue_free()
	_clean()


func test_style_changes_the_key(t: TestCtx) -> void:
	var b: ViewIconBake = _bake()
	var rid: StringName = &"unit.napc.rifle_squad"
	if not b.recipe_book().has_recipe(rid):
		rid = StringName(b.recipe_book().ids()[0])
	var k1: String = b.cache_key_for(rid, &"napc", 10000, ViewIconBake.S_CARD)
	var k2: String = b.cache_key_for(rid, &"def", 10000, ViewIconBake.S_CARD)
	t.ne(k1, k2, "the same recipe under two faction styles caches separately")
	b.free()


func test_frame_camera_reserves_the_card_strip(t: TestCtx) -> void:
	var aspect: float = 188.0 / 124.0
	var r: float = ViewIconBake.RESERVE[ViewIconBake.S_CARD]
	t.gt(r, 0.0, "cards reserve room for the cost strip")
	for b: AABB in [AABB(Vector3(-1.4, 0.0, -2.6), Vector3(2.8, 1.9, 5.2)), AABB(Vector3(-5.0, 0.0, -4.0), Vector3(10.0, 6.0, 8.0))]:
		var pose: Dictionary = ViewIconBake.frame_camera(b, ViewIconBake.YAW_DEG, ViewIconBake.PITCH_DEG, ViewIconBake.FOV_DEG, aspect, ViewIconBake.MARGIN, r)
		var cb: Basis = pose["basis"] as Basis
		var tan_v: float = tan(deg_to_rad(ViewIconBake.FOV_DEG) * 0.5)
		var rot: Basis = Basis(Vector3.UP, deg_to_rad(ViewIconBake.YAW_DEG))
		var lo_y: float = INF
		var hi_y: float = -INF
		for i: int in 8:
			var v: Vector3 = cb.inverse() * (rot * b.get_endpoint(i) - (pose["pos"] as Vector3))
			var y: float = v.y / (-v.z * tan_v)
			lo_y = minf(lo_y, y)
			hi_y = maxf(hi_y, y)
		t.check(lo_y >= -1.0 + 2.0 * r - 0.01, "the lowest %.0f%% of the frame stays free (%.3f)" % [r * 100.0, lo_y])
		t.check(hi_y <= 1.0, "and the top is inside the frame")
