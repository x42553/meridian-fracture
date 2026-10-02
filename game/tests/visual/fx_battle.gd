extends "res://tests/visual/vw_battle.gd"
## VIEW-F3/F4/W3 integrated acceptance: the vw_battle scene (REAL SimWorld, generated map, two armies with real combat) with the FX
## layer attached (FxStage: manager + fx.json + event router + projectile mirror). The sim runs LIVE at 20 Hz against a 60 fps clock,
## so muzzle flashes, tracers, projectiles, explosions, deaths and burning wrecks come from the kernel's own events.
##   tools/gd run res://tests/visual/fx_battle.tscn --gui --size 1600x900 --allow-errors -- --n=14 --caps=100,170,260,400 --out=/abs/fxb
##     -> /abs/fxb_100.png ... ; add --bench=600 to print the perf report (RESULT|fx_battle|json) and quit.
## Args (besides vw_battle's): --caps=frames (PNG captures), --out=prefix, --pre=N (silent warm-up ticks), --follow (camera tracks the fight),
## --bench=N (frames to measure), --fog (real fog), --keep (do not quit after the captures),
## --chaos=k (adds synthetic kernel events at k x the spec's chaos-battle rates: 187 shots/s, 60 hits/s, 19 explosions/s, 0.9 vehicle
## kills/s, 0.25 building collapses/s, 0.3 EMP/s, missiles / shells / beams; positions in the visible ground, ids of the real armies).

var stage: FxStage = null

var _acc: int = 0
var _frame_no: int = 0
var _caps: PackedInt32Array = PackedInt32Array()
var _out: String = ""
var _samples: Array[float] = []
var _fx_samples: Array[float] = []
var _vw_samples: Array[float] = []
var _draws: Array[float] = []
var _prims: Array[float] = []
var _bench_total: int = 0
var _counts: Dictionary = {}
var _quit_at: int = -1
var _pre_left: int = 0
var _chaos: float = 0.0
var _carry: Dictionary = {}
var _serial: int = 100000


func _build_view() -> void:
	super._build_view()
	stage = FxStage.attach(vw)
	stage.name = "FxStage"
	if _args.has("quality"):
		stage.fx.set_quality(int(_args["quality"]) as FxManager.Quality)
	vw.selection.set_selection(PackedInt32Array())
	if _args.has("prewarm"):
		var t0: int = Time.get_ticks_usec()
		stage.prewarm(8)
		print("FX_BATTLE prewarm ms=", float(Time.get_ticks_usec() - t0) / 1000.0, " effects=", stage.book.ids().size())
	for s: String in str(_args.get("caps", "")).split(",", false):
		_caps.append(int(s))
	_out = str(_args.get("out", "user://fx_battle"))
	_bench_total = int(_args.get("bench", "0"))
	_pre_left = int(_args.get("pre", "0"))
	_chaos = float(_args.get("chaos", "0"))
	if not _caps.is_empty():
		_quit_at = _caps[_caps.size() - 1] + 4


## The live loop replaces the batch run of vw_battle.
func _run_to(_target: int) -> void:
	for i: int in _pre_left:
		sim.step()
		vw.frame(1.0 / 60.0, 1.0, sim.events.take())
	_pre_left = 0


func _process(delta: float) -> void:
	if vw == null:
		return
	_frame_no += 1
	var t0: int = Time.get_ticks_usec()
	var events: PackedInt32Array = PackedInt32Array()
	if _acc % 3 == 0:
		sim.step()
		events = sim.events.take()
		_count(events)
		if _chaos > 0.0:
			events.append_array(_chaos_events(sim.tick))
	var alpha: float = float(_acc % 3) / 3.0 + 0.17
	_acc += 1
	vw.frame(delta, alpha, events)
	var t1: int = Time.get_ticks_usec()
	if _args.has("follow") and _frame_no % 30 == 0:
		_frame_camera()
	if _bench_total > 0 and _frame_no > 60:
		var vp: RID = get_viewport().get_viewport_rid()
		_samples.append(delta * 1000.0)
		_vw_samples.append(float(t1 - t0) / 1000.0)
		_fx_samples.append(float(stage.stat_frame_us) / maxf(float(stage.stat_frames), 1.0) / 1000.0)
		_draws.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		_prims.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
		if vp.is_valid() and _frame_no >= 60 + _bench_total:
			_report()
			get_tree().quit()
			return
	if _caps.has(_frame_no):
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s_%d.png" % [_out, _frame_no]
		img.save_png(path)
		print("FX_BATTLE cap ", path, " tick=", sim.tick, " entities=", vw.entity_count(), " fx=", stage.fx.live_instances())
	if _quit_at > 0 and _frame_no >= _quit_at and not _args.has("keep"):
		print("FX_BATTLE done counts=", _counts, " router=", stage.router.stats)
		get_tree().quit()


func _count(events: PackedInt32Array) -> void:
	var o: int = 0
	while o + SimEvent.STRIDE <= events.size():
		var c: int = events[o]
		_counts[c] = (_counts.get(c, 0) as int) + 1
		o += SimEvent.STRIDE


func _report() -> void:
	var fxs: Dictionary = stage.fx.get_stats()
	var out: Dictionary = {
		"frames": _samples.size(), "entities": vw.entity_count(), "sim_tick": sim.tick,
		"frame_ms": _summ(_samples), "view_script_ms": _summ(_vw_samples), "fx_script_ms_avg": _summ(_fx_samples),
		"draw_calls": _summ(_draws), "primitives": _summ(_prims),
		"fx": {"requests": fxs["requests"], "spawned": fxs["spawned"], "culled": fxs["culled"], "rate_dropped": fxs["rate_dropped"],
			"spawn_us_avg": fxs["spawn_us_avg"], "process_us_avg": fxs["process_us_avg"], "batches_shown": fxs["batches_shown"]},
		"router": stage.router.stats, "damage_emitters": stage.router.ambient.active_count(),
		"meshes": stage.projectiles.live_meshes(), "events": _counts.size(),
	}
	print("RESULT|fx_battle|", JSON.stringify(out))


static func _summ(arr: Array[float]) -> Dictionary:
	if arr.is_empty():
		return {}
	var a: Array[float] = arr.duplicate()
	a.sort()
	var n: int = a.size()
	var sum: float = 0.0
	for v: float in a:
		sum += v
	return {"mean": snappedf(sum / float(n), 0.001), "p50": snappedf(a[n / 2], 0.001), "p95": snappedf(a[mini(int(float(n) * 0.95), n - 1)], 0.001),
		"p99": snappedf(a[mini(int(float(n) * 0.99), n - 1)], 0.001), "max": snappedf(a[n - 1], 0.001)}


# ---- synthetic chaos load (the spec's 5.9.1 chaos battle through the real router) ----
const CHAOS_RATES: Array = [["rifle", 150.0], ["cannon", 20.0], ["missile", 6.0], ["rail", 8.0], ["artillery", 2.0], ["beam", 0.7], ["hit", 60.0],
	["expl_small", 10.0], ["expl_medium", 6.0], ["expl_large", 3.0], ["vehicle", 0.9], ["building", 0.25], ["emp", 0.3]]


func _rand_cell() -> Vector2i:
	var rect: Rect2 = cam.visible_ground_rect() if cam != null else Rect2(100, 100, 100, 100)
	var p: Vector2 = Vector2(randf_range(rect.position.x + 8.0, rect.end.x - 8.0), randf_range(rect.position.y + 8.0, rect.end.y - 8.0))
	return ViewConsts.world_to_sim_xz(p)


func _rand_id(pool: PackedInt32Array) -> int:
	return pool[randi() % pool.size()] if not pool.is_empty() else -1


func _chaos_events(tick: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for row: Array in CHAOS_RATES:
		var key: String = row[0] as String
		var c: float = float(_carry.get(key, 0.0)) + float(row[1]) * _chaos / 20.0
		while c >= 1.0:
			c -= 1.0
			_chaos_one(key, tick, out)
		_carry[key] = c
	return out


func _chaos_one(key: String, tick: int, out: PackedInt32Array) -> void:
	var p: Vector2i = _rand_cell()
	var q: Vector2i = p + Vector2i(randi_range(-6000, 6000), randi_range(-6000, 6000))
	var a: int = _rand_id(army_a)
	var b: int = _rand_id(army_b)
	var hs: int = SimCombatConsts.PK_HITSCAN << 8
	match key:
		"rifle":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_FIRE, tick, p.x, p.y, a, 0, hs | ((1 + randi() % 2) << 12), b, q.x, q.y))
		"cannon":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_FIRE, tick, p.x, p.y, a, 3, SimCombatConsts.PK_BULLET << 8, b, q.x, q.y))
			_serial += 1
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_PROJ_SPAWN, tick, p.x, p.y, _serial, 3, 0 | (SimCombatConsts.PK_BULLET << 4) | (6 << 16), b, q.x, q.y))
		"missile":
			_serial += 1
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_FIRE, tick, p.x, p.y, a, 6, SimCombatConsts.PK_MISSILE << 8, b, q.x, q.y))
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_PROJ_SPAWN, tick, p.x, p.y, _serial, 6, 0 | (SimCombatConsts.PK_MISSILE << 4) | (16 << 16), b, q.x, q.y))
		"artillery":
			_serial += 1
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_FIRE, tick, p.x, p.y, a, 9, SimCombatConsts.PK_ARC << 8, -1, q.x, q.y))
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_PROJ_SPAWN, tick, p.x, p.y, _serial, 9, 0 | (SimCombatConsts.PK_ARC << 4) | (36 << 16), -1, q.x, q.y))
		"rail":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_FIRE, tick, p.x, p.y, a, 14, hs | (1 << 12), b, q.x, q.y))
		"beam":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_BEAM_START, tick, p.x, p.y, a, 13, 0, b, 40))
		"hit":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_HIT, tick, p.x, p.y, b, 5, a, 0, 60, 100))
		"expl_small":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_IMPACT, tick, p.x, p.y, 0, -1, 1, 1024, 100, 0))
		"expl_medium":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_IMPACT, tick, p.x, p.y, 0, -1, 0, 1700, 100, 0))
		"expl_large":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_IMPACT, tick, p.x, p.y, 0, -1, 0, 3100, 100, 0))
		"vehicle":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_DEATH, tick, p.x, p.y, -5, 0, ViewConsts.DK_VEHICLE, a, 0, 0))
		"building":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_DEATH, tick, p.x, p.y, -6, 0, ViewConsts.DK_STRUCTURE, a, 0, 0))
		"emp":
			out.append_array(ViewTestEvents.make(SimCombatConsts.EV_IMPACT, tick, p.x, p.y, 0, -1, 0, 3400, 100, 0))
