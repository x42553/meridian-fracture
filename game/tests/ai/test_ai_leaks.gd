extends RefCounted
## HARD1: the AI module must not outlive its match. A released thinker (AiFactory.release / AppAiHook.shutdown) frees the whole object graph
## it built (thinker, controller, context, knowledge, scheduler, command builder, brain modules) and keeps neither the world nor the shared
## data alive: ctx.brain <-> module cycles are cut by `release`, and nothing in the factory / shared data points back at a thinker.

const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla"]


func _weak_graph(th: AiThinker) -> Dictionary:
	var ctx: AiContext = th.controller.ctx
	var g: Dictionary = {"thinker": weakref(th), "controller": weakref(th.controller), "ctx": weakref(ctx), "view": weakref(ctx.view),
		"kb": weakref(ctx.kb), "cmd": weakref(ctx.cmd), "scheduler": weakref(th.controller.scheduler)}
	if ctx.brain != null:
		g["brain"] = weakref(ctx.brain)
	return g


func _alive(g: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in g.keys():
		if (g[k] as WeakRef).get_ref() != null:
			out.append(str(k))
	return out


func test_factory_release_frees_the_whole_ai_graph(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"rosters": ROSTERS, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	if not t.not_null(w, "the match world builds"):
		return
	var factory: AiFactory = AiFactory.new()
	var calls: Array[Callable] = []
	for pid: int in 3:
		calls.append(factory.make(pid, pid + 1, pid, 7 + pid))
	var out: Array = []
	for _i: int in 60:
		for c: Callable in calls:
			out.clear()
			c.call(w, out)
		w.step()
	t.eq(factory.live_count(), 3, "three live thinkers")
	var graphs: Array[Dictionary] = []
	for pid: int in 3:
		graphs.append(_weak_graph(factory.thinker(pid)))
	t.check((graphs[0] as Dictionary).has("brain"), "the real brain is installed (the cycle under test)")
	calls.clear()
	for pid: int in 3:
		factory.release(pid)
	t.eq(factory.live_count(), 0, "released")
	for pid: int in 3:
		t.eq(_alive(graphs[pid]), PackedStringArray(), "thinker %d: nothing of its object graph is alive after release" % pid)


func test_ai_does_not_keep_the_world_alive(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"rosters": ROSTERS, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	var hook: AppAiHook = AppAiHook.new()
	var th: Callable = hook.make(1, 2, 0, 5)
	var out: Array = []
	for _i: int in 30:
		out.clear()
		th.call(w, out)
		w.step()
	var world_ref: WeakRef = weakref(w)
	th = Callable()
	hook.shutdown()
	m.clear()
	w = null
	hook = null
	t.is_null(world_ref.get_ref(), "after shutdown the world is only held by the match, not by the AI")


func test_a_second_release_and_a_release_of_an_unknown_pid_are_harmless(t: TestCtx) -> void:
	var factory: AiFactory = AiFactory.new()
	var c: Callable = factory.make(0, 1, 0, 3)
	t.check(c.is_valid(), "a thinker callable")
	factory.release(0)
	factory.release(0)
	factory.release(5)
	t.eq(factory.live_count(), 0)
