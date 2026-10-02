class_name UiBench
extends Control
## Benchmark harness (run with a real renderer, vsync off): every scenario warms up, then averages SAMPLE frames.
## "work" = time from the start of the frame (process_frame) to RenderingServer.frame_pre_draw, i.e. all scripts
## PLUS the deferred CanvasItem redraw callbacks (`_draw` of every dirty Control) -- the true CPU cost of the UI.
## render cpu / gpu come from the viewport's measured render times (previous frame).

const WARMUP := 30
const SAMPLE := 150
const ALL_KINDS: Array[String] = ["infantry", "infantry_at", "medic", "engineer", "tank_light", "tank_medium", "tank_heavy", "apc", "artillery", "aa", "recon", "collector", "mcv", "jet", "gunship", "bomber", "boat", "frigate", "arsenal", "barge", "headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory", "tower", "turret", "aa_battery", "cannon", "superweapon"]

var host: Node
var faction: String = "napc"
var _vp: RID
var _work_us: int = 0
var _scr: UiScreenHud
var _tick: int = 0

func _init(h: Node, f: String) -> void:
	host = h
	faction = f

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_run.call_deferred()

func _frame(per_frame: Callable) -> void:
	await get_tree().process_frame
	_tick += 1
	var t0: int = Time.get_ticks_usec()
	if per_frame.is_valid():
		per_frame.call()
	await RenderingServer.frame_pre_draw
	_work_us = Time.get_ticks_usec() - t0

func _measure(label: String, per_frame: Callable = Callable(), extra: Callable = Callable()) -> void:
	for i in WARMUP:
		await _frame(per_frame)
	var work: float = 0.0
	var gpu: float = 0.0
	var rcpu: float = 0.0
	var calls: float = 0.0
	var t_start: int = Time.get_ticks_usec()
	for i in SAMPLE:
		await _frame(per_frame)
		work += float(_work_us) / 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var wall: float = float(Time.get_ticks_usec() - t_start) / 1000.0 / float(SAMPLE)
	var tail: String = ""
	if extra.is_valid():
		tail = " | " + String(extra.call())
	print("BENCH | %-52s | frame %6.2f ms (%5.0f fps) | work %5.2f ms | render cpu %5.2f ms | gpu %5.2f ms | draw calls %4.0f%s" % [label, wall, 1000.0 / wall, work / SAMPLE, rcpu / SAMPLE, gpu / SAMPLE, calls / SAMPLE, tail])

func _run() -> void:
	await get_tree().process_frame
	print("BENCH | env | %s %s | %s | window %s | msaa2d=%d msaa3d=%d" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(), get_window().size, get_viewport().msaa_2d, get_viewport().msaa_3d])
	_scr = UiScreenHud.new(host, faction, 2, UiCooldownSweep.Backend.SHADER)
	add_child(_scr)
	while not _scr.bake_done:
		await get_tree().process_frame
	var vp: Viewport = get_viewport()
	# --- whole-scene scenarios
	await _measure("3D battlefield + HUD (animated)")
	_scr.hud.visible = false
	await _measure("3D battlefield only (HUD hidden)")
	_scr.hud.visible = true
	vp.disable_3d = true
	await _measure("HUD only, animated (3D disabled)")
	_scr.set_process(false)
	await _measure("HUD only, idle (3D disabled)")
	vp.msaa_2d = Viewport.MSAA_DISABLED
	await _measure("HUD idle, MSAA 2D off")
	vp.msaa_2d = Viewport.MSAA_2X
	await _measure("HUD idle, MSAA 2D 2x")
	vp.msaa_2d = Viewport.MSAA_4X
	await _measure("HUD idle, MSAA 2D 4x (project default)")
	vp.msaa_2d = Viewport.MSAA_8X
	await _measure("HUD idle, MSAA 2D 8x")
	vp.msaa_2d = Viewport.MSAA_4X
	get_window().content_scale_factor = 1.5
	await _measure("HUD idle at UI scale 1.5")
	get_window().content_scale_factor = 1.0
	_scr.hud.visible = false
	await _measure("empty viewport (HUD hidden, 3D disabled)")
	# --- overlay + minimap with many entities
	_scr.hud.visible = true
	_scr.set_process(true)
	var ents: Array[Dictionary] = _scr.world.entities
	var base_count: int = ents.size()
	for i in 400:
		ents.append({"kind": "tank_medium", "team": i % 3, "pos": Vector3(0.0, 0.0, 0.0), "hp": 0.3 + 0.7 * float((i * 37) % 100) / 100.0, "selected": i % 4 == 0, "radius": 1.8, "struct": false, "node": null, "vel": Vector3.ZERO})
	var mover: Callable = func() -> void:
		var t: float = float(_tick) * 0.02
		for i in range(base_count, ents.size()):
			var a: float = float(i) * 0.37 + t * (0.3 + float(i % 5) * 0.1)
			ents[i]["pos"] = Vector3(20.0 + cos(a) * (10.0 + float(i % 40)), 0.0, sin(a) * (8.0 + float(i % 30)))
		if _tick % 3 == 0:
			_scr._feed_minimap()
	var ov_extra: Callable = func() -> String:
		return "overlay draw %d us (%d visible) | minimap draw %d us | entities %d" % [_scr.hud.overlay.last_draw_us, _scr.hud.overlay.last_visible, _scr.hud.minimap.last_draw_us, ents.size()]
	await _measure("HUD + 400 moving entities (overlay + minimap dots)", mover, ov_extra)
	var t0: int = Time.get_ticks_usec()
	var picked: int = 0
	for i in 200:
		picked += UiPicking.box_select(_scr.world.camera, ents, Rect2(200.0, 150.0, 1200.0, 700.0)).size()
	print("BENCH | UiPicking.box_select over %d entities: %.1f us/call (%d picked)" % [ents.size(), float(Time.get_ticks_usec() - t0) / 200.0, picked / 200])
	t0 = Time.get_ticks_usec()
	for i in 200:
		UiPicking.ray_pick(_scr.world.camera, ents, Vector2(700.0, 500.0))
	print("BENCH | UiPicking.ray_pick over %d entities: %.1f us/call" % [ents.size(), float(Time.get_ticks_usec() - t0) / 200.0])
	ents.resize(base_count)
	_scr.hud.visible = false
	_scr.set_process(false)
	# --- widget micro benchmarks
	await _sweep_bench()
	await _stylebox_bench()
	await _text_bench()
	# --- theme + icons (no frames needed)
	var t1: int = Time.get_ticks_usec()
	for i in 20:
		UiTheme.build(_scr.skin)
	print("BENCH | UiTheme.build (all styleboxes, 8 faction re-tints share the recipe): %.2f ms/build" % [float(Time.get_ticks_usec() - t1) / 1000.0 / 20.0])
	vp.disable_3d = false
	await _icon_bench()
	print("BENCH | memory | video %.1f MB | textures %.1f MB | static %.1f MB | nodes %d" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	print("BENCH | done")
	get_tree().quit()

func _holder() -> Control:
	var h := Control.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	return h

func _sweep_bench() -> void:
	for spec in [["SHADER", UiCooldownSweep.Backend.SHADER], ["TEXTURE_PROGRESS", UiCooldownSweep.Backend.TEXTURE_PROGRESS], ["POLYGON (GDScript fan)", UiCooldownSweep.Backend.POLYGON]]:
		var h: Control = _holder()
		var sweeps: Array[UiCooldownSweep] = []
		for i in 100:
			var s := UiCooldownSweep.new(spec[1])
			s.size = Vector2(94.0, 62.0)
			s.position = Vector2(float(i % 16) * 100.0 + 10.0, float(i / 16) * 68.0 + 10.0)
			h.add_child(s)
			sweeps.append(s)
		var upd: Callable = func() -> void:
			var t: float = float(_tick) * 0.01
			for i in sweeps.size():
				sweeps[i].progress = fposmod(t + float(i) * 0.013, 1.0)
		await _measure("100 clock-wipe sweeps, progress changes every frame: %s" % spec[0], upd)
		h.queue_free()
		await get_tree().process_frame

func _stylebox_bench() -> void:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color("#35465a"))
	img.fill_rect(Rect2i(2, 2, 44, 44), Color("#141e2a"))
	var tex := ImageTexture.create_from_image(img)
	var makers: Array = [
		["UiStyleBox (GDScript _draw, chamfer+gradient+glow)", func() -> StyleBox: return UiTheme.panel_box(_scr.skin)],
		["StyleBoxFlat (built-in, rounded+border)", func() -> StyleBox:
			var f := StyleBoxFlat.new()
			f.bg_color = Color("#141e2a")
			f.border_color = Color("#35465a")
			f.set_border_width_all(1)
			f.set_corner_radius_all(4)
			return f],
		["StyleBoxTexture (9-slice from generated Image)", func() -> StyleBox:
			var t := StyleBoxTexture.new()
			t.texture = tex
			t.texture_margin_left = 6.0
			t.texture_margin_top = 6.0
			t.texture_margin_right = 6.0
			t.texture_margin_bottom = 6.0
			return t],
	]
	for m in makers:
		var h: Control = _holder()
		var panels: Array[Panel] = []
		var sb: StyleBox = (m[1] as Callable).call()
		for i in 500:
			var p := Panel.new()
			p.add_theme_stylebox_override("panel", sb)
			p.size = Vector2(90.0, 50.0)
			p.position = Vector2(float(i % 20) * 94.0 + 10.0, float(i / 20) * 54.0 + 10.0)
			h.add_child(p)
			panels.append(p)
		var redraw: Callable = func() -> void:
			for p in panels:
				p.queue_redraw()
		await _measure("500 Panels redrawn every frame: %s" % m[0], redraw)
		h.queue_free()
		await get_tree().process_frame

func _text_bench() -> void:
	var h: Control = _holder()
	var labels: Array[Label] = []
	for i in 300:
		var l := Label.new()
		l.text = "12,450"
		l.add_theme_font_size_override("font_size", 14)
		l.position = Vector2(float(i % 20) * 90.0 + 10.0, float(i / 20) * 24.0 + 10.0)
		h.add_child(l)
		labels.append(l)
	var upd: Callable = func() -> void:
		for i in labels.size():
			labels[i].text = str(_tick * 7 + i)
	await _measure("300 Labels, text changes every frame", upd)
	h.queue_free()
	await get_tree().process_frame
	var d := _DrawText.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(d)
	var upd2: Callable = func() -> void:
		d.tick = _tick
		d.queue_redraw()
	await _measure("300 draw_string calls in one Control, redrawn every frame", upd2)
	d.queue_free()
	await get_tree().process_frame

func _icon_bench() -> void:
	var b := UiIconBaker.new()
	add_child(b)
	var kinds := PackedStringArray(ALL_KINDS)
	await b.bake(kinds, Vector2i(188, 124), Color("#39c5ff"), Color("#ffb733"))
	print("BENCH | icons: %d x 188x124 in ONE batch: build %.1f ms | GPU wait %.1f ms | readback+upload %.1f ms | per icon total %.2f ms" % [b.last_count, b.last_build_ms, b.last_wait_ms, b.last_readback_ms, (b.last_build_ms + b.last_wait_ms + b.last_readback_ms) / float(b.last_count)])
	await b.bake(kinds, Vector2i(96, 64), Color("#39c5ff"), Color("#ffb733"))
	print("BENCH | icons: %d x 96x64 in ONE batch: build %.1f ms | GPU wait %.1f ms | readback+upload %.1f ms | per icon total %.2f ms" % [b.last_count, b.last_build_ms, b.last_wait_ms, b.last_readback_ms, (b.last_build_ms + b.last_wait_ms + b.last_readback_ms) / float(b.last_count)])
	var total: float = 0.0
	var n: int = 12
	for i in n:
		var t0: int = Time.get_ticks_usec()
		await b.bake(PackedStringArray([ALL_KINDS[i]]), Vector2i(188, 124), Color("#ff5533"), Color("#ffb733"))
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	print("BENCH | icons: %d x 188x124 one-per-call (each awaited): %.2f ms per icon wall time" % [n, total / float(n)])
	print("BENCH | icon cache: %d textures" % b.cached_count())

class _DrawText extends Control:
	var tick: int = 0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var f: Font = UiFonts.get_font(UiFonts.Role.NUM)
		for i in 300:
			draw_string(f, Vector2(float(i % 20) * 90.0 + 10.0, float(i / 20) * 24.0 + 26.0), str(tick * 7 + i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
