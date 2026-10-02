extends RefCounted
## HARD1: the audio facade releases everything at quit (`AppAudio.uninstall` -> `SndManager.shutdown` + free): nothing of its object graph may stay
## alive in a reference cycle (it made every normal run end with `ObjectDB instances were leaked at exit` once audio was on).


func _graph(snd: SndManager) -> Dictionary:
	var g: Dictionary = {"store": weakref(snd.store), "index": weakref(snd.index), "map": weakref(snd.map), "scheduler": weakref(snd.scheduler),
		"fader": weakref(snd.fader), "reader": weakref(snd.reader), "loops": weakref(snd.loops), "meter": weakref(snd.meter), "pool": weakref(snd._pool),
		"announcer": weakref(snd._announcer), "music": weakref(snd._music), "library": weakref(snd._library), "bridge": weakref(snd.bridge)}
	return g


func test_setup_shutdown_free_leaves_nothing_alive(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var snd: SndManager = SndManager.new()
	snd.name = "SndLeakProbe"
	tree.root.add_child(snd)
	await tree.process_frame
	snd.set_process(false)
	if not t.check(snd.setup(), "audio setup"):
		snd.queue_free()
		return
	var g: Dictionary = _graph(snd)
	var ref: WeakRef = weakref(snd)
	snd.shutdown()
	tree.root.remove_child(snd)
	snd.free()
	snd = null
	await tree.process_frame
	var alive: PackedStringArray = PackedStringArray()
	for k: Variant in g.keys():
		if (g[k] as WeakRef).get_ref() != null:
			alive.append(str(k))
	t.is_null(ref.get_ref(), "the manager node is freed")
	t.eq(alive, PackedStringArray(), "no sub-object of the audio graph survives (a cycle keeps it alive)")


func test_a_played_match_leaves_nothing_alive(t: TestCtx) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "bots": true})
	var w: SimWorld = m["world"] as SimWorld
	if not t.not_null(w, "a world"):
		return
	var root3d: Node3D = Node3D.new()
	var cam: Camera3D = Camera3D.new()
	root3d.add_child(cam)
	tree.root.add_child(root3d)
	cam.current = true
	var snd: SndManager = SndManager.new()
	snd.name = "SndLeakProbe2"
	tree.root.add_child(snd)
	await tree.process_frame
	snd.set_process(false)
	if not t.check(snd.setup(), "audio setup"):
		return
	var ms: int = 100000
	snd.set_time_override(ms)
	snd.attach_world(root3d)
	snd.begin_match(SndMatchConfig.from_world(w, 0))
	var waited: int = 0
	while not snd.is_match_ready() and waited < 600:
		ms += 16
		snd.set_time_override(ms)
		snd._process(0.016)
		await tree.process_frame
		waited += 1
	for i: int in 120:
		for b: SimBot in m["bots"]:
			b.think(w)
		w.step()
		ms += 50
		snd.set_time_override(ms)
		snd.set_camera(Vector3.ZERO, Basis.IDENTITY, 55.0)
		snd.on_events(w, w.events.take(), 0.0)
		snd.on_frame(w, 0.0, 0.05)
		snd._process(0.05)
		if i % 20 == 0:
			await tree.process_frame
	var g: Dictionary = _graph(snd)
	g["world"] = weakref(w)
	g["bank"] = weakref(snd.bank)
	g["responses"] = weakref(snd.responses)
	g["countdown"] = weakref(snd.countdown)
	g["ambience"] = weakref(snd.ambience)
	g["cfg"] = weakref(snd._cfg)
	g["stats"] = weakref(snd.stats_obj)
	snd.end_match(SndMatchConfig.RESULT_ABORT)
	snd.detach_world()
	snd.shutdown()
	snd.index.release_banks(PackedStringArray())
	tree.root.remove_child(snd)
	snd.free()
	snd = null
	root3d.free()
	m.clear()
	w = null
	await tree.process_frame
	await tree.process_frame
	var alive: PackedStringArray = PackedStringArray()
	for k: Variant in g.keys():
		if (g[k] as WeakRef).get_ref() != null:
			alive.append(str(k))
	t.eq(alive, PackedStringArray(), "nothing of the audio graph or the world survives a played match")
