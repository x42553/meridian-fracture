extends RefCounted
## QA2: Godot 4.7.2 publishes the cached operator evaluator of a GDScript function unsynchronised on its first execution, so a burst of worker
## threads starting the recipe interpreter together crashed ~2 % of exported match boots (SIGSEGV in a WorkerThread). ViewModelBuilder builds the first
## request of each distinct archetype (up to WARM_MAX) on the main thread before any worker runs; ViewTerrainBake / Layers run item 0 alone first.


func _builder() -> Array:
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var b: ViewModelBuilder = ViewModelBuilder.new()
	b.setup(book, ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	return [b, book]


func _unit(book: ViewRecipeBook) -> StringName:
	for rid: String in book.ids():
		var r: ViewRecipe = book.recipe(StringName(rid))
		if rid.begins_with("unit.") and r != null and r.arch != null:
			return StringName(rid)
	return &""


func _drain(b: ViewModelBuilder) -> void:
	var guard: int = 0
	while b.pending() > 0 and guard < 4000:
		b.pump(4.0)
		guard += 1
		OS.delay_msec(2)


func test_first_request_per_archetype_is_built_on_the_main_thread(t: TestCtx) -> void:
	ViewModelBuilder.reset_warm()
	var bb: Array = _builder()
	var b: ViewModelBuilder = bb[0] as ViewModelBuilder
	var book: ViewRecipeBook = bb[1] as ViewRecipeBook
	var seen_arch: Dictionary = {}
	var asked: Array[StringName] = []
	var n: int = 0
	for rid: String in book.ids():
		if not (rid.begins_with("unit.") or rid.begins_with("structure.")):
			continue
		n += 1
		if n % 4 != 0:
			continue  # every 4th recipe: a mix of archetypes
		var d: Dictionary = ViewModelBuilder.build_data(book, StringName(rid), &"auto", 10000)
		if not (d["placeholder"] as bool):  # some roster recipes need their team style (`team_key`): not buildable with 'auto'
			asked.append(StringName(rid))
		if asked.size() >= 60:
			break
	var ready: Array[int] = [0]
	b.model_ready.connect(func(_k: StringName) -> void: ready[0] += 1)
	var expect_sync: Array[StringName] = []
	for rid: StringName in asked:
		var r: ViewRecipe = book.recipe(rid)
		if r != null and r.arch != null and not seen_arch.has(r.arch.id) and expect_sync.size() < ViewModelBuilder.WARM_MAX:
			seen_arch[r.arch.id] = true
			expect_sync.append(rid)
		b.request(rid, &"auto", 10000)
	t.gt(expect_sync.size(), 3, "the sample covers several archetypes")
	for rid: StringName in expect_sync:
		t.check(b.has_model(rid, &"auto", 10000), "%s (first of its archetype) is cached right after request()" % rid)
	t.eq(b.stat_sync_builds, 0, "warm builds are not counted as mid-match hitches")
	t.ge(ready[0], expect_sync.size(), "model_ready fired for the warm builds")
	_drain(b)
	t.eq(b.pending(), 0, "the rest finished on the workers")
	for rid: StringName in asked:
		t.check(b.has_model(rid, &"auto", 10000), "%s built" % rid)
	ViewModelBuilder.reset_warm()


func test_warm_build_equals_worker_build(t: TestCtx) -> void:
	ViewModelBuilder.reset_warm()
	var bb: Array = _builder()
	var b: ViewModelBuilder = bb[0] as ViewModelBuilder
	var book: ViewRecipeBook = bb[1] as ViewRecipeBook
	var rid0: StringName = _unit(book)
	b.request(rid0, &"auto", 10000)  # warm (main thread)
	var m1: ViewModel = b.get_model(rid0, &"auto", 10000)
	t.eq(b.stat_sync_builds, 0, "served from the cache")
	var d: Dictionary = ViewModelBuilder.build_data(book, rid0, &"auto", 10000)  # what a worker computes
	t.eq(m1.info.verts, (d["info"] as ViewModelInfo).verts, "identical vertex count")
	t.eq(m1.info.rest_aabb, (d["info"] as ViewModelInfo).rest_aabb, "identical bounds")
	ViewModelBuilder.reset_warm()


func test_requests_from_a_worker_thread_stay_asynchronous(t: TestCtx) -> void:
	ViewModelBuilder.reset_warm()
	var bb: Array = _builder()
	var b: ViewModelBuilder = bb[0] as ViewModelBuilder
	var rid0: StringName = _unit(bb[1] as ViewRecipeBook)
	var tid: int = WorkerThreadPool.add_task(func() -> void: b.request(rid0, &"auto", 10000))
	WorkerThreadPool.wait_for_task_completion(tid)
	t.check_false(b.has_model(rid0, &"auto", 10000), "not built synchronously off the main thread")
	t.eq(b.pending(), 1, "queued for a worker")
	_drain(b)
	t.check(b.has_model(rid0, &"auto", 10000), "built after pump()")
	ViewModelBuilder.reset_warm()
