extends Node3D
## VIEW-F4 full-match FX acceptance: a REAL bot-vs-bot match (SimMatchKit: real GameData, generated map, every real system, all factions)
## rendered through AppViewStage (terrain, water, atmosphere, decor, ViewWorld) with the FX layer attached (FxStage). Sim ticks at 20 Hz against
## a 60 fps clock; the camera follows the last exchange of fire. Everything on screen comes from the kernel's own events.
##   tools/gd run res://tests/visual/fx_match.tscn --gui --size 1600x900 --allow-errors -- --rosters=roster.pd.vanilla,roster.ae.vanilla
##       --pre=3000 --caps=60,180,320 --out=/abs/m   [--seed=N --family=0|1|2 --zoom=0.16 --bench=600 --quit=N]
## Prints the event-type histogram of the run and (--bench) RESULT|fx_match|json.

var world: SimWorld = null
var match_dict: Dictionary = {}
var stage: AppViewStage = null
var fxs: FxStage = null

var _args: Dictionary = {}
var _frame_no: int = 0
var _acc: int = 0
var _focus: Vector2 = Vector2.ZERO
var _focus_t: Vector2 = Vector2.ZERO
var _caps: PackedInt32Array = PackedInt32Array()
var _out: String = ""
var _counts: Dictionary = {}
var _bench: int = 0
var _draws: Array[float] = []
var _frames_ms: Array[float] = []
var _view_ms: Array[float] = []
var _quit_frame: int = -1
var _zoom: float = 0.16


func _ready() -> void:
	_args = _parse()
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var rosters: PackedStringArray = PackedStringArray(str(_args.get("rosters", "roster.napc.vanilla,roster.nec.vanilla")).split(","))
	match_dict = SimMatchKit.make_match({"rosters": rosters, "seed": int(_args.get("seed", "3")), "family": int(_args.get("family", "0")),
		"size": int(_args.get("size", "96"))})
	world = match_dict["world"] as SimWorld
	if world == null:
		push_error("fx_match: no world")
		get_tree().quit(1)
		return
	var pre: int = int(_args.get("pre", "0"))
	if pre > 0:
		SimMatchKit.run(match_dict, pre)
	stage = AppViewStage.new()
	add_child(stage)
	stage.build_sync(world, 0)
	fxs = stage.fx_stage  # AppViewStage attaches the FX layer itself
	if _args.has("quality"):
		fxs.fx.set_quality(int(_args["quality"]) as FxManager.Quality)
	for hb: String in str(_args.get("hide", "")).split(",", false):
		fxs.fx.hidden_batches[StringName(hb)] = true
	for s: String in str(_args.get("caps", "")).split(",", false):
		_caps.append(int(s))
	_out = str(_args.get("out", "user://fx_match"))
	_bench = int(_args.get("bench", "0"))
	_zoom = float(_args.get("zoom", "0.16"))
	if not _caps.is_empty():
		_quit_frame = _caps[_caps.size() - 1] + 4
	if _args.has("quit"):
		_quit_frame = int(_args["quit"])
	var s0: int = world.map.spawns[1]
	_focus = Vector2(float(s0 % world.map.w), float(s0 / world.map.w))
	_focus_t = _focus
	_place_camera(true)
	stage.view.reconcile()


func _parse() -> Dictionary:
	var d: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _place_camera(snap: bool) -> void:
	var cam: ViewCamera = stage.view.camera
	if cam == null:
		return
	_focus = _focus.lerp(_focus_t, 1.0 if snap else 0.06)
	cam.snap_to(_focus * ViewConsts.CELL_M, 0.0, _zoom)
	cam.advance(0.0)


func _process(delta: float) -> void:
	if world == null or stage == null:
		return
	_frame_no += 1
	var t0: int = Time.get_ticks_usec()
	var events: PackedInt32Array = PackedInt32Array()
	if _acc % 3 == 0:
		for b: SimBot in match_dict["bots"] as Array:
			b.think(world)
		world.step()
		events = world.events.take()
		_scan(events)
	var alpha: float = float(_acc % 3) / 3.0 + 0.17
	_acc += 1
	stage.frame(delta, alpha, events)
	var t1: int = Time.get_ticks_usec()
	_place_camera(false)
	if _bench > 0 and _frame_no > 60:
		_frames_ms.append(delta * 1000.0)
		_view_ms.append(float(t1 - t0) / 1000.0)
		_draws.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		if _frame_no >= 60 + _bench:
			print("RESULT|fx_match|", JSON.stringify(_report()))
			get_tree().quit()
			return
	if _caps.has(_frame_no):
		await RenderingServer.frame_post_draw
		var path: String = "%s_%d.png" % [_out, _frame_no]
		get_viewport().get_texture().get_image().save_png(path)
		print("FX_MATCH cap ", path, " tick=", world.tick, " entities=", stage.view.entity_count(), " fx=", fxs.fx.live_instances())
	if _quit_frame > 0 and _frame_no >= _quit_frame:
		print("FX_MATCH done tick=", world.tick, " events=", _counts, " router=", fxs.router.stats)
		get_tree().quit()


## Camera target: the most recent shot / blast / death of the batch; event histogram.
func _scan(ev: PackedInt32Array) -> void:
	var o: int = 0
	while o + SimEvent.STRIDE <= ev.size():
		var c: int = ev[o]
		_counts[c] = (_counts.get(c, 0) as int) + 1
		if c == SimCombatConsts.EV_FIRE or c == SimCombatConsts.EV_IMPACT or c == SimCombatConsts.EV_DEATH:
			_focus_t = Vector2(float(ev[o + 2]) / 1024.0, float(ev[o + 3]) / 1024.0)
		o += SimEvent.STRIDE


func _report() -> Dictionary:
	var fxst: Dictionary = fxs.fx.get_stats()
	return {"frames": _frames_ms.size(), "tick": world.tick, "entities": stage.view.entity_count(), "view_frame_ms": _sum(_view_ms), "frame_ms": _sum(_frames_ms),
		"draw_calls": _sum(_draws), "fx": {"requests": fxst["requests"], "spawned": fxst["spawned"], "culled": fxst["culled"], "rate_dropped": fxst["rate_dropped"],
		"spawn_us_avg": fxst["spawn_us_avg"], "process_us_avg": fxst["process_us_avg"]}, "router": fxs.router.stats, "events": _counts}


static func _sum(arr: Array[float]) -> Dictionary:
	if arr.is_empty():
		return {}
	var a: Array[float] = arr.duplicate()
	a.sort()
	var n: int = a.size()
	var s: float = 0.0
	for v: float in a:
		s += v
	return {"mean": snappedf(s / float(n), 0.001), "p50": snappedf(a[n / 2], 0.001), "p95": snappedf(a[mini(int(float(n) * 0.95), n - 1)], 0.001), "max": snappedf(a[n - 1], 0.001)}
