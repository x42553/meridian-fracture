class_name AppPerfProbe
extends RefCounted
## Frame-time probe for scripted GUI matches (`--perf-log=<file>` of the test boot, tools/py/perf_run.py): per frame wall time,
## the engine's script/process time, draw calls, objects, memory, entities and the sim step cost. Writes one JSON line per
## `SAMPLE_EVERY` frames plus a summary object (avg / p50 / p95 / p99 / worst frame ms, fps) at `finish()`.
## Frames before `warmup_ticks` sim ticks (loading, first-frame shader compiles, the opening) are excluded from the statistics.

const SAMPLE_EVERY: int = 60

var path: String = ""
var warmup_ticks: int = 100
## > 0: sample every N sim ticks instead of every SAMPLE_EVERY frames (headless soak: one frame advances many ticks).
var sample_ticks: int = 0
var _next_sample_tick: int = 0
var label: String = ""
var _file: FileAccess
var _last_us: int = 0
var _frames_ms: PackedFloat32Array = PackedFloat32Array()
var _proc_ms: PackedFloat32Array = PackedFloat32Array()
var _n: int = 0
var _tick0: int = -1
var _mem0: float = 0.0
var _draws_max: int = 0
var _draws_sum: float = 0.0
var _ents_max: int = 0
var _prims_max: int = 0
var _step_us_max: int = 0
var _step_us_sum: float = 0.0
var _step_samples: int = 0
var _mem_peak: float = 0.0
var _vram_peak: float = 0.0
var _objs_max: int = 0
var _hitches: int = 0
var _vp: RID = RID()
var _last_tick: int = 0
var _last_step_total_us: int = 0
## Frames slower than this get their own `{"slow": ...}` line (tick, ticks advanced, sim ms in the frame, view ms): the hitch hunter.
var slow_ms: float = 12.0
var _slow_logged: int = 0
var _last_rs: Dictionary = {}
var _sync0: int = -1
var _sync0_ms: float = 0.0
var _sync_now: Array = [0, 0.0, ""]
var _gpu_sum: float = 0.0
var _gpu_n: int = 0
var _gpu_max: float = 0.0
var _cpu_render_sum: float = 0.0


static func create(p_path: String, p_label: String = "") -> AppPerfProbe:
	var p: AppPerfProbe = AppPerfProbe.new()
	p.path = p_path
	p.label = p_label
	p._file = FileAccess.open(p_path, FileAccess.WRITE)
	return p


## Call once per rendered frame (after `await process_frame`).
func frame(ctx: AppMatchContext) -> void:
	var now: int = Time.get_ticks_usec()
	var dt_ms: float = float(now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	var w: SimWorld = ctx.world()
	if w == null or dt_ms <= 0.0:
		return
	if w.tick < warmup_ticks:
		return
	if _tick0 < 0:
		_tick0 = w.tick
		_mem0 = float(OS.get_static_memory_usage()) / 1048576.0
	if not _vp.is_valid():
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			_vp = tree.root.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(_vp, true)
	var rs: Dictionary = ctx.stage.fx_stage.router.stats if ctx.stage != null and ctx.stage.fx_stage != null and ctx.stage.fx_stage.router != null else {}
	var router_delta: Dictionary = {}
	for k: String in ["events", "handled", "spawns", "handle_us"]:
		router_delta[k] = int(rs.get(k, 0)) - int(_last_rs.get(k, 0))
	_last_rs = rs.duplicate()
	if ctx.stage != null and ctx.stage.view != null and ctx.stage.view.models != null:
		var mb: ViewModelBuilder = ctx.stage.view.models
		if _sync0 < 0:
			_sync0 = mb.stat_sync_builds  # builds up to here belong to the loading screen
			_sync0_ms = mb.stat_sync_ms
		_sync_now = [mb.stat_sync_builds - _sync0, mb.stat_sync_ms - _sync0_ms, mb.stat_sync_last]
	var ticks_now: int = w.tick - _last_tick
	_last_tick = w.tick
	_n += 1
	_frames_ms.append(dt_ms)
	if dt_ms > slow_ms and _slow_logged < 400 and _file != null and ctx.session != null and ctx.session.lockstep != null:
		var ls2: Dictionary = ctx.session.lockstep.stats()
		var tot: int = int(ls2.get("step_cost_total_us", 0))
		var vst: Dictionary = ctx.stage.view.stats() if ctx.stage != null and ctx.stage.view != null else {}
		_file.store_line(JSON.stringify({"slow": {"tick": w.tick, "frame_ms": snapped(dt_ms, 0.01), "ticks": ticks_now,
			"sim_ms": snapped(float(tot - _last_step_total_us) / 1000.0, 0.01), "ents": w.entities.size(), "view_ms": vst.get("ms", {}), "router": router_delta, "model_sync": _sync_now,
			"proc_ms": snapped(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0, 0.01),
			"render_cpu_ms": snapped(RenderingServer.viewport_get_measured_render_time_cpu(_vp), 0.01) if _vp.is_valid() else 0.0,
			"gpu_ms": snapped(RenderingServer.viewport_get_measured_render_time_gpu(_vp), 0.01) if _vp.is_valid() else 0.0}}))
		_slow_logged += 1
	if ctx.session != null and ctx.session.lockstep != null and ticks_now > 0:
		_last_step_total_us = int(ctx.session.lockstep.stats().get("step_cost_total_us", 0))
	if _vp.is_valid():
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_gpu_sum += gpu
		_gpu_n += 1
		_gpu_max = maxf(_gpu_max, gpu)
		_cpu_render_sum += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
	_proc_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	if dt_ms > 33.4:
		_hitches += 1
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_draws_max = maxi(_draws_max, draws)
	_draws_sum += float(draws)
	if sample_ticks > 0:
		if w.tick < _next_sample_tick:
			return
		_next_sample_tick = w.tick - w.tick % sample_ticks + sample_ticks
	elif _n % SAMPLE_EVERY != 0:
		return
	var ents: int = w.entities.size()
	_ents_max = maxi(_ents_max, ents)
	var prims: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_prims_max = maxi(_prims_max, prims)
	var mem: float = float(OS.get_static_memory_usage()) / 1048576.0
	_mem_peak = maxf(_mem_peak, mem)
	var vram: float = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	_vram_peak = maxf(_vram_peak, vram)
	var objs: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_objs_max = maxi(_objs_max, objs)
	var st: Dictionary = ctx.session.stats() if ctx.session != null else {}
	var ls: Dictionary = ctx.session.lockstep.stats() if ctx.session != null and ctx.session.lockstep != null else {}
	var step_us: int = int(ls.get("step_cost_us", 0))  # EWMA of one sim step in microseconds
	_step_us_max = maxi(_step_us_max, step_us)
	_step_us_sum += float(step_us)
	_step_samples += 1
	var vstats: Dictionary = ctx.stage.view.stats() if ctx.stage != null and ctx.stage.view != null else {}
	var rec: Dictionary = {"tick": w.tick, "frame_ms": snapped(dt_ms, 0.01), "proc_ms": snapped(_proc_ms[_proc_ms.size() - 1], 0.01),
		"draws": draws, "prims": prims, "ents": ents, "visible": int(vstats.get("visible", 0)), "mem_mb": snapped(mem, 0.1),
		"vram_mb": snapped(vram, 0.1), "objs": objs, "step_load_pct": int(st.get("load_pct", 0)), "speed_pct": int(st.get("speed_pct", 0)),
		"gpu_ms": snapped(RenderingServer.viewport_get_measured_render_time_gpu(_vp), 0.01) if _vp.is_valid() else 0.0,
		"render_cpu_ms": snapped(RenderingServer.viewport_get_measured_render_time_cpu(_vp), 0.01) if _vp.is_valid() else 0.0,
		"view_ms": vstats.get("ms", {}), "step_avg_ms": snapped(float(ls.get("step_cost_total_us", 0)) / maxf(1.0, float(ls.get("steps_timed", 1))) / 1000.0, 0.001),
		"step_max_ms": snapped(float(ls.get("step_cost_max_us", 0)) / 1000.0, 0.01), "ai_us": st.get("ai_us", {})}
	if _file != null:
		_file.store_line(JSON.stringify(rec))


func finish(ctx: AppMatchContext) -> Dictionary:
	var s: Dictionary = {"label": label, "frames": _n, "ticks": (ctx.world().tick - _tick0) if ctx.world() != null and _tick0 >= 0 else 0}
	if _n > 0:
		var sorted: PackedFloat32Array = _frames_ms.duplicate()
		sorted.sort()
		var psorted: PackedFloat32Array = _proc_ms.duplicate()
		psorted.sort()
		var sum: float = 0.0
		for v: float in _frames_ms:
			sum += v
		var avg: float = sum / float(_n)
		s["avg_ms"] = snapped(avg, 0.01)
		s["fps_avg"] = snapped(1000.0 / avg, 0.1)
		s["p50_ms"] = snapped(sorted[int(_n * 0.5)], 0.01)
		s["p95_ms"] = snapped(sorted[mini(_n - 1, int(_n * 0.95))], 0.01)
		s["p99_ms"] = snapped(sorted[mini(_n - 1, int(_n * 0.99))], 0.01)
		s["worst_ms"] = snapped(sorted[_n - 1], 0.01)
		s["hitches_gt33ms"] = _hitches
		if ctx.stage != null and ctx.stage.view != null:
			s["backend"] = ctx.stage.view.backend.stats()
			if ctx.stage.fx_stage != null:
				var fs: Dictionary = ctx.stage.fx_stage.stats()
				s["fx_meshes_live"] = fs.get("meshes", 0)
		s["model_sync_builds_in_match"] = _sync_now[0]
		s["model_sync_ms_in_match"] = snapped(float(_sync_now[1]), 0.1)
		s["model_sync_last"] = _sync_now[2]
		s["gpu_ms_avg"] = snapped(_gpu_sum / maxf(1.0, float(_gpu_n)), 0.01)  # root viewport render time on the GPU (0 where timestamps are unsupported)
		s["gpu_ms_worst"] = snapped(_gpu_max, 0.01)
		s["render_cpu_ms_avg"] = snapped(_cpu_render_sum / maxf(1.0, float(_gpu_n)), 0.01)
		s["proc_avg_ms"] = snapped(_avg(psorted), 0.01)
		s["proc_p95_ms"] = snapped(psorted[mini(_n - 1, int(_n * 0.95))], 0.01)
		s["draws_avg"] = snapped(_draws_sum / float(_n), 1.0)
		s["draws_max"] = _draws_max
		s["prims_max"] = _prims_max
		s["entities_max"] = _ents_max
		s["objects_max"] = _objs_max
		s["mem_mb_start"] = snapped(_mem0, 0.1)
		s["mem_mb_peak"] = snapped(_mem_peak, 0.1)
		s["mem_mb_end"] = snapped(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)
		s["vram_mb_peak"] = snapped(_vram_peak, 0.1)
		s["sim_step_ms_avg_ewma"] = snapped(_step_us_sum / maxf(1.0, float(_step_samples)) / 1000.0, 0.01)
		var ls: Dictionary = ctx.session.lockstep.stats() if ctx.session != null and ctx.session.lockstep != null else {}
		var steps: int = int(ls.get("steps_timed", 0))
		s["sim_step_ms_avg"] = snapped(float(ls.get("step_cost_total_us", 0)) / maxf(1.0, float(steps)) / 1000.0, 0.001)  # every step of the match
		s["sim_step_ms_worst"] = snapped(float(ls.get("step_cost_max_us", 0)) / 1000.0, 0.01)
		s["sim_steps"] = steps
	if _file != null:
		_file.store_line(JSON.stringify({"summary": s}))
		_file.close()
	return s


static func _avg(a: PackedFloat32Array) -> float:
	var t: float = 0.0
	for v: float in a:
		t += v
	return t / maxf(1.0, float(a.size()))
