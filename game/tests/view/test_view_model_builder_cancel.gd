extends RefCounted
## HARD1: quitting while the loading screen builds models hung the process (`Main::cleanup` waited for WorkerThreadPool tasks of freed script
## objects). ViewModelBuilder.cancel() / the PREDELETE hook join every background build; ViewWorld aborts its async build.


func test_cancel_joins_every_inflight_build(t: TestCtx) -> void:
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var b: ViewModelBuilder = ViewModelBuilder.new()
	b.setup(book, ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	var asked: int = 0
	for rid: String in book.ids():
		if rid.begins_with("unit.") or rid.begins_with("structure."):
			b.request(StringName(rid), &"auto", 10000)
			asked += 1
			if asked >= 120:
				break
	t.gt(asked, 40, "enough recipes to keep the pool busy")
	t.gt(b.pending(), 0, "builds are in flight")
	b.cancel()
	t.eq(b.pending(), 0, "cancel() joined and forgot every task")
	t.lt(b.cached_count(), asked, "queued builds were skipped, not all finished")
	# the builder is reusable afterwards
	b.request(&"unit.napc.guardian_tank", &"auto", 10000)
	var guard: int = 0
	while b.pending() > 0 and guard < 4000:
		b.pump(4.0)
		guard += 1
		OS.delay_msec(2)
	t.eq(b.pending(), 0, "a request after cancel() builds normally")


func test_freeing_a_builder_with_builds_in_flight_does_not_hang_or_error(t: TestCtx) -> void:
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var b: ViewModelBuilder = ViewModelBuilder.new()
	b.setup(book, ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	var n: int = 0
	for rid: String in book.ids():
		if rid.begins_with("unit."):
			b.request(StringName(rid), &"auto", 10000)
			n += 1
			if n >= 60:
				break
	var ref: WeakRef = weakref(b)
	b = null  # a running task may still hold the object for a moment; whoever drops the last reference runs the PREDELETE hook (no self-join)
	var guard: int = 0
	while ref.get_ref() != null and guard < 600:
		await (Engine.get_main_loop() as SceneTree).process_frame
		guard += 1
	t.is_null(ref.get_ref(), "the builder is freed once its tasks are done (no hang, no deadlock)")
	t.gt(n, 20)


func test_view_world_abort_stops_the_async_build(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 4, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	if not t.not_null(w, "a world"):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var vw: ViewWorld = ViewWorld.create(ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.LOW))
	tree.root.add_child(vw)
	await tree.process_frame  # inside the tree: `_yield` really suspends
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.prewarm_scope = 1
	opts.bake_icons = false
	var finished: Array[bool] = [false]
	vw.build_finished.connect(func() -> void: finished[0] = true)
	var done: Array[bool] = [false]
	var run: Callable = func() -> void:
		await vw.build_async(w, 0, opts)
		done[0] = true
	run.call()  # runs up to its first yield
	vw.aborted = true
	var guard: int = 0
	while not done[0] and guard < 600:
		await tree.process_frame
		guard += 1
	t.check(done[0], "the coroutine ended after the abort (no suspended state left behind)")
	t.check_false(finished[0], "and it did not pretend to be finished")
	tree.root.remove_child(vw)
	vw.free()
