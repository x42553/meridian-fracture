extends RefCounted
## VIEW-01 acceptance: quality tables, renderer clamps, recommendation, auto ladder (render spec 10.1 test_view_quality).

const KEYS: Array[String] = ["low", "medium", "high", "ultra"]


func _json() -> Dictionary:
	return ViewQuality.load_presets()


func test_preset_tables_equal_quality_json(t: TestCtx) -> void:
	var j: Dictionary = _json()
	t.check(j.has("presets"), "quality.json loads")
	var presets: Dictionary = j["presets"] as Dictionary
	for p in 4:
		var q: ViewQuality = ViewQuality.create(j, p)
		var table: Dictionary = presets[KEYS[p]] as Dictionary
		for k: Variant in table:
			t.eq(q.values[k], table[k], "%s.%s" % [KEYS[p], k])
	var hi: ViewQuality = ViewQuality.create(j, ViewQuality.Preset.HIGH)
	t.eq(hi.get_int(&"msaa"), 2, "HIGH msaa 4x")
	t.near(hi.get_float(&"mesh_lod_threshold"), 1.0, 1.0e-9, "HIGH lod threshold")
	t.eq(hi.shadow_cascades(), 4, "HIGH cascades")
	t.eq(ViewQuality.create(j, ViewQuality.Preset.LOW).shadow_cascades(), 0, "LOW blob shadows")
	t.eq(ViewQuality.create(j, ViewQuality.Preset.MEDIUM).shadow_cascades(), 2, "MEDIUM cascades")
	t.eq(ViewQuality.create(j, ViewQuality.Preset.ULTRA).fx_quality(), 3, "ULTRA fx quality")
	t.eq(ViewQuality.create(j, ViewQuality.Preset.LOW).get_int(&"unit_shader_quality"), 0, "LOW shader quality 0")
	t.check(hi.get_bool(&"glow"), "HIGH glow on")
	t.check(not ViewQuality.create(j, ViewQuality.Preset.LOW).get_bool(&"ssao"), "LOW ssao off")


func test_renderer_clamps(t: TestCtx) -> void:
	var j: Dictionary = _json()
	var c: ViewQuality = ViewQuality.create(j, ViewQuality.Preset.ULTRA, ViewQuality.Renderer.COMPATIBILITY)
	t.eq(c.get_string(&"ssao"), "off", "Compat ssao off")
	t.check(not c.get_bool(&"ssil"), "Compat ssil off")
	t.check(not c.get_bool(&"fxaa"), "Compat fxaa off")
	t.eq(c.unit_backend(), "batch", "Compat batch backend")
	t.check(not c.get_bool(&"fx_distort"), "Compat fx distort off")
	t.near(c.get_float(&"fx_compat_boost"), 1.6, 1.0e-9, "Compat FX boost")
	t.eq(c.get_string(&"scaling_mode"), "bilinear", "Compat bilinear scaling")
	t.eq(c.get_int(&"msaa"), 2, "Compat ultra MSAA is capped at 4x")
	var m: ViewQuality = ViewQuality.create(j, ViewQuality.Preset.HIGH, ViewQuality.Renderer.MOBILE)
	t.eq(m.get_string(&"ssao"), "off", "Mobile ssao off")
	t.eq(m.unit_backend(), "batch", "Mobile batch backend")
	t.check(m.get_bool(&"fxaa") == false, "Mobile keeps the preset's fxaa")
	var f: ViewQuality = ViewQuality.create(j, ViewQuality.Preset.HIGH, ViewQuality.Renderer.FORWARD_PLUS)
	t.eq(f.unit_backend(), "nodes", "Forward+ AUTO = nodes")
	t.eq(f.get_string(&"ssao"), "medium_half", "Forward+ keeps ssao")
	t.eq(f.ssao_settings(), {"enabled": true, "level": 2, "half_size": true}, "ssao_settings")


func test_recommend(t: TestCtx) -> void:
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, ViewQuality.Renderer.FORWARD_PLUS), ViewQuality.Preset.HIGH, "discrete -> HIGH")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, ViewQuality.Renderer.FORWARD_PLUS), ViewQuality.Preset.MEDIUM, "integrated -> MEDIUM")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, ViewQuality.Renderer.FORWARD_PLUS, "Apple M5 Max (Apple9)"), ViewQuality.Preset.HIGH, "Apple Silicon -> HIGH")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, ViewQuality.Renderer.FORWARD_PLUS, "Intel(R) UHD Graphics"), ViewQuality.Preset.MEDIUM, "other integrated -> MEDIUM")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_CPU, ViewQuality.Renderer.FORWARD_PLUS), ViewQuality.Preset.LOW, "CPU -> LOW")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_OTHER, ViewQuality.Renderer.FORWARD_PLUS), ViewQuality.Preset.LOW, "other -> LOW")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, ViewQuality.Renderer.COMPATIBILITY), ViewQuality.Preset.MEDIUM, "Compat is capped at MEDIUM")
	t.eq(ViewQuality.recommend(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, ViewQuality.Renderer.MOBILE), ViewQuality.Preset.MEDIUM, "Mobile is capped at MEDIUM")


func test_from_settings_overrides(t: TestCtx) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("video", "quality", 1)
	cfg.set_value("video", "msaa", 3)
	cfg.set_value("video", "fps_cap", 144)
	cfg.set_value("video", "health_bars", 2)
	cfg.set_value("video", "unit_backend", 0)
	cfg.set_value("access", "reduce_flash", true)
	cfg.set_value("access", "colour_mode", "deutan")
	var q: ViewQuality = ViewQuality.from_settings(cfg, _json(), ViewQuality.Renderer.FORWARD_PLUS)
	t.eq(q.preset, ViewQuality.Preset.MEDIUM, "quality 1 = MEDIUM")
	t.eq(q.get_int(&"msaa"), 3, "override beats the preset")
	t.eq(q.get_string(&"shadow_mode"), "cascades2", "untouched keys stay at the preset")
	t.eq(q.target_fps, 144, "fps_cap becomes the auto target")
	t.eq(q.extras["health_bars"], 2, "passthrough key kept")
	t.eq(q.unit_backend(), "nodes", "unit_backend 0 forces nodes")
	t.check(q.reduce_flash and not q.reduce_motion, "access flags")
	t.eq(q.colour_mode, ViewTeamColors.MODE_DEUTAN, "colour mode parsed")
	var auto_cfg: ConfigFile = ConfigFile.new()
	auto_cfg.set_value("video", "quality", 4)
	var a: ViewQuality = ViewQuality.from_settings(auto_cfg, _json(), ViewQuality.Renderer.FORWARD_PLUS)
	t.check(a.auto_mode and a.preset_cap == ViewQuality.Preset.ULTRA, "quality 4 = auto with ULTRA cap")
	ViewMeshBuilder.default_compat_layout = false


func test_auto_steps_down_then_scale(t: TestCtx) -> void:
	var q: ViewQuality = ViewQuality.create(_json(), ViewQuality.Preset.HIGH)
	var changes: Array = []
	var auto: ViewQualityAuto = ViewQualityAuto.new()
	auto.setup(q, func(p: int, r: String) -> void: changes.append([p, r]))
	for i in 150:
		auto.sample(0.04)
	t.eq(q.preset, ViewQuality.Preset.MEDIUM, "6 s of 40 ms frames at HIGH -> MEDIUM (2 bad windows)")
	for i in 150:
		auto.sample(0.04)
	t.eq(q.preset, ViewQuality.Preset.LOW, "continued -> LOW")
	t.near(q.get_float(&"render_scale"), 0.75, 1.0e-9, "LOW starts at 0.75")
	for i in 150:
		auto.sample(0.04)
	t.near(q.get_float(&"render_scale"), 0.65, 1.0e-9, "then render_scale 0.65")
	for i in 150:
		auto.sample(0.04)
	t.near(q.get_float(&"render_scale"), 0.55, 1.0e-9, "then 0.55")
	for i in 600:
		auto.sample(0.04)
	t.near(q.get_float(&"render_scale"), 0.55, 1.0e-9, "and no lower")
	t.eq(changes.size(), 4, "four notifications")
	t.eq((changes[0] as Array)[0], ViewQuality.Preset.MEDIUM, "first on_change carries the new preset")


func test_auto_up_step_rules(t: TestCtx) -> void:
	var q: ViewQuality = ViewQuality.create(_json(), ViewQuality.Preset.MEDIUM)
	q.preset_cap = ViewQuality.Preset.HIGH
	var auto: ViewQualityAuto = ViewQualityAuto.new()
	var ups: Array[float] = []
	var clock: Array[float] = [0.0]
	auto.setup(q, func(p: int, _r: String) -> void:
		if p > ViewQuality.Preset.MEDIUM:
			ups.append(clock[0]))
	# 30 s of 8 ms frames: 10 good windows -> exactly one step up, to HIGH (the cap)
	for i in 3750:
		clock[0] += 0.008
		auto.sample(0.008)
	t.eq(q.preset, ViewQuality.Preset.HIGH, "30 s of 8 ms frames -> one step up")
	t.eq(ups.size(), 1, "at most one step up")
	for i in 20000:
		auto.sample(0.008)
	t.eq(q.preset, ViewQuality.Preset.HIGH, "never above the user's cap")
	# a down-step blocks up-steps for 120 s
	var q2: ViewQuality = ViewQuality.create(_json(), ViewQuality.Preset.HIGH)
	var a2: ViewQualityAuto = ViewQualityAuto.new()
	a2.setup(q2, Callable())
	for i in 150:
		a2.sample(0.04)
	t.eq(q2.preset, ViewQuality.Preset.MEDIUM, "down to MEDIUM")
	for i in 4000:  # 32 s of fast frames: 10 good windows but still inside the 120 s lockout
		a2.sample(0.008)
	t.eq(q2.preset, ViewQuality.Preset.MEDIUM, "no step up within 120 s of a down-step")
	for i in 15000:  # +120 s
		a2.sample(0.008)
	t.eq(q2.preset, ViewQuality.Preset.HIGH, "step up after the lockout")


func test_auto_ignores_hitches(t: TestCtx) -> void:
	var q: ViewQuality = ViewQuality.create(_json(), ViewQuality.Preset.HIGH)
	var auto: ViewQualityAuto = ViewQualityAuto.new()
	auto.setup(q, Callable())
	for i in 400:
		auto.sample(0.6)  # alt-tab hitches: ignored
	t.eq(q.preset, ViewQuality.Preset.HIGH, "hitch frames > 250 ms are ignored")
	for i in 400:
		auto.sample(0.016)
	t.eq(q.preset, ViewQuality.Preset.HIGH, "16 ms frames are fine at 60 fps")


func test_apply_to_viewport(t: TestCtx) -> void:
	var vp: SubViewport = SubViewport.new()
	var q: ViewQuality = ViewQuality.create(_json(), ViewQuality.Preset.LOW)
	q.apply_to_viewport(vp)
	t.eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "LOW msaa off")
	t.eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR, "LOW uses FSR1")
	t.near(vp.scaling_3d_scale, 0.75, 1.0e-6, "LOW render scale")
	t.near(vp.mesh_lod_threshold, 2.0, 1.0e-6, "LOW lod threshold")
	q.set_preset(ViewQuality.Preset.ULTRA)
	q.apply_to_viewport(vp)
	t.eq(vp.msaa_3d, Viewport.MSAA_8X, "ULTRA msaa 8x")
	t.eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "ULTRA bilinear")
	vp.free()
