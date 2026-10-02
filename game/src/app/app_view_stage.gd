class_name AppViewStage
extends Node3D
## The composed 3D presentation of a match (ui.md 5.3 VIEW phase): a `ViewWorld` (terrain, camera, entities, rings, bars,
## picker) plus the world-look stack the view delivers as separate parts and nobody composes yet: mood, atmosphere (sun, sky,
## grade), water, decor, fog of war and the minimap bake. `build_async` is a coroutine that yields between stages so the
## loading screen keeps animating; `frame` is the per-rendered-frame entry point. Presentation only, never mutates the sim.

signal build_progress(fraction: float, stage: String)

var view: ViewWorld = null
var atmosphere: ViewAtmosphere = null
var water: ViewWater = null
var decor: ViewDecor = null
var fog: ViewFogOfWar = null
var minimap: ViewMinimapSource = null
var mood: ViewMoodDef = null
var fx_stage: FxStage = null
var quality: ViewQuality = null
var sim: SimWorld = null
var local_pid: int = -1
var built: bool = false
## Set by `abort()`: the async build returns at its next yield point.
var aborted: bool = false
## Include water / decor / atmosphere (a lean stage is enough for tests that only need the world mirror).
var full_look: bool = true
## Forces a mood of `moods.json` ("" = by map biome / family); the menu showcase uses the dusk look.
var mood_id: StringName = &""
## Attach the FX layer (`FxStage`: muzzle flashes, tracers, explosions, wrecks, construction dust, superweapons). The menu showcase
## and lean tests switch it off.
var with_fx: bool = true
## `--no-fx` (AppBootHook): the FX layer stays off for every match stage of this process (diagnostics, bisecting a rendering problem).
static var fx_globally_off: bool = false
## `--mood=<id>` (AppBootHook): force a mood for every match stage of this process (screenshots of each colour grading).
static var forced_mood: StringName = &""

var _frames: int = 0
var _mm_material: Material = null
var _fog_mode: int = ViewFogOfWar.MODE_NONE


## The view quality for a match: the saved settings when the settings autoload exists, else HIGH.
static func make_quality() -> ViewQuality:
	var presets: Dictionary = ViewQuality.load_presets()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var st: Node = tree.root.get_node_or_null("AppSettings") if tree != null else null
	if st != null and st.get("store") is AppSettingsStore:
		var overrides: Dictionary = st.get("overrides") as Dictionary if st.get("overrides") is Dictionary else {}
		var cfg: ConfigFile = AppApply.quality_config(st.get("store") as AppSettingsStore, overrides)
		var q: ViewQuality = ViewQuality.from_settings(cfg, presets)
		if q != null:
			return q
	return ViewQuality.create(presets, ViewQuality.Preset.HIGH, ViewQuality.detect_renderer())


## Coroutine: builds everything for `w` as seen by `pid` (-1 = observer). The stage must already be in the tree.
func build_async(w: SimWorld, pid: int, q: ViewQuality = null) -> void:
	sim = w
	local_pid = pid
	quality = q if q != null else make_quality()
	view = ViewWorld.create(quality)
	view.name = "ViewWorld"
	view.build_progress.connect(func(f: float, s: String) -> void: build_progress.emit(f * 0.75, s))
	add_child(view)
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.prewarm_scope = 1
	opts.bake_icons = false
	await view.build_async(w, pid, opts)
	if aborted:
		build_progress.emit(1.0, "aborted")  # the loading job frees a cancelled stage on its final progress signal
		return
	if full_look:
		await _build_look()
		if aborted:
			build_progress.emit(1.0, "aborted")
			return
	_finish()
	_attach_fx(true)
	build_progress.emit(0.98, "fx")
	if fx_stage != null:
		await _yield()
		if aborted:
			build_progress.emit(1.0, "aborted")
			return
	build_progress.emit(1.0, "done")
	built = true


## Synchronous variant for tools and tests (no yields).
func build_sync(w: SimWorld, pid: int, q: ViewQuality = null) -> void:
	sim = w
	local_pid = pid
	quality = q if q != null else make_quality()
	view = ViewWorld.create(quality)
	view.name = "ViewWorld"
	add_child(view)
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.prewarm_scope = 0
	opts.bake_icons = false
	view.build_sync(w, pid, opts)
	_build_look_sync()
	_finish()
	_attach_fx(false)
	built = true


## `FxStage.attach` (spec dev FX2 / RI2): the router hooks `view.router.extra_handler`, the state views' `ViewFxPort` is bound so the
## ids the router owns are not spawned twice, and the effect pipelines are compiled behind the loading screen (`prewarm`).
func _attach_fx(prewarm: bool) -> void:
	if not with_fx or fx_globally_off or view == null or view.terrain == null or view.camera == null:
		return
	fx_stage = FxStage.attach(view, quality)
	if view.fx != null:
		fx_stage.bind_port(view.fx)
	if prewarm:
		fx_stage.prewarm(6)
	AppApply.quality_sink = Callable(self, "_on_quality_config")


## Freezes / resumes the FX clock together with the game (pause menu, session pause).
func set_paused(paused: bool) -> void:
	if fx_stage != null and fx_stage.fx != null:
		fx_stage.fx.paused = paused


## Live quality switch (Options -> Graphics during a match): the world mirror, the atmosphere and the FX layer.
func apply_quality(q: ViewQuality) -> void:
	if q == null:
		return
	quality = q
	if view != null:
		view.apply_quality(q)
	if atmosphere != null:
		atmosphere.apply_quality(q)
	if fx_stage != null:
		fx_stage.apply_quality(q)


## `AppApply.quality_sink`: the `[video]` + `[access]` config after an Options change.
func _on_quality_config(cfg: ConfigFile) -> void:
	var q: ViewQuality = ViewQuality.from_settings(cfg, ViewQuality.load_presets())
	if q != null:
		apply_quality(q)


## Detaches the FX router before the world mirror goes away. Safe to call twice.
## Stops a running `build_async` at its next yield point (quit during loading): the coroutine ends instead of being left suspended at exit.
func abort() -> void:
	aborted = true
	if view != null and is_instance_valid(view):
		view.aborted = true


func teardown() -> void:
	if AppApply.quality_sink.is_valid() and AppApply.quality_sink.get_object() == self:
		AppApply.quality_sink = Callable()
	if fx_stage != null and is_instance_valid(fx_stage):
		fx_stage.detach()
	fx_stage = null


func _exit_tree() -> void:
	teardown()


func _yield() -> void:
	if is_inside_tree():
		await get_tree().process_frame


func _build_look() -> void:
	var t: ViewTerrain = view.terrain
	if t == null or t.src == null:
		return
	mood = _pick_mood()
	t.apply_mood(mood)
	atmosphere = ViewAtmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.setup()
	atmosphere.apply_quality(quality)
	atmosphere.apply_mood(mood)
	build_progress.emit(0.80, "atmosphere")
	await _yield()
	if aborted:
		return
	var detail: ViewDetailTextures = ViewDetailTextures.build(256)
	water = ViewWater.new()
	water.name = "Water"
	add_child(water)
	water.build(t, detail, false)
	water.apply_mood(mood)
	build_progress.emit(0.86, "water")
	await _yield()
	if aborted:
		return
	decor = ViewDecor.new()
	decor.name = "Decor"
	add_child(decor)
	decor.build(t, t.src, quality)
	decor.apply_mood(mood)
	build_progress.emit(0.92, "decor")
	await _yield()
	if aborted:
		return
	_bake_minimap(t.src)


func _build_look_sync() -> void:
	var t: ViewTerrain = view.terrain
	if t == null or t.src == null or not full_look:
		return
	mood = _pick_mood()
	t.apply_mood(mood)
	atmosphere = ViewAtmosphere.new()
	add_child(atmosphere)
	atmosphere.setup()
	atmosphere.apply_quality(quality)
	atmosphere.apply_mood(mood)
	water = ViewWater.new()
	add_child(water)
	water.build(t, ViewDetailTextures.build(128), false)
	water.apply_mood(mood)
	decor = ViewDecor.new()
	add_child(decor)
	decor.build(t, t.src, quality)
	decor.apply_mood(mood)
	_bake_minimap(t.src)


func _pick_mood() -> ViewMoodDef:
	var moods: Dictionary = ViewMoodDef.load_all()
	if mood_id != &"" and moods.has(String(mood_id)):
		return moods[String(mood_id)] as ViewMoodDef
	if forced_mood != &"" and moods.has(String(forced_mood)):
		return moods[String(forced_mood)] as ViewMoodDef
	return ViewMoodDef.for_map(sim.map.biome, sim.map.family, moods, bool(quality.extras.get("night_maps", true)) if quality != null else true,
		sim.map.seed_value, str(quality.extras.get("look", "auto")) if quality != null else "auto")


func _bake_minimap(src: ViewTerrainSource) -> void:
	minimap = ViewMinimapSource.new()
	minimap.bake(src, mood)


func _finish() -> void:
	if sim == null or view == null or view.terrain == null:
		return
	var w: int = sim.map.w
	var h: int = sim.map.h
	fog = ViewFogOfWar.new()
	fog.setup(w, h, Vector2.ZERO, ViewConsts.CELL_M)
	_fog_mode = ViewFogOfWar.MODE_SHROUD_FOG if sim.config.rules.fog != 0 and local_pid >= 0 else ViewFogOfWar.MODE_NONE
	fog.set_mode(_fog_mode)
	fog.set_local_player(local_pid)
	if _fog_mode != ViewFogOfWar.MODE_NONE:
		fog.sync(sim.fog, local_pid)
	_fit_camera()


## Camera clip planes and shadow cascades follow the rig height (ViewAtmosphere.fit_shadows).
func _fit_camera() -> void:
	var cam: ViewCamera = view.camera
	if cam == null or atmosphere == null:
		return
	cam.camera.near = atmosphere.fit_shadows(cam.current_height(), cam.current_pitch_deg(), cam.fov_deg)


## The `ViewMinimapSource` texture; null before the build.
func minimap_texture() -> Texture2D:
	return minimap.texture if minimap != null else null


## One shared material per stage (the observer's perspective switch flips its fog uniform in place).
func minimap_material() -> Material:
	if minimap == null:
		return null
	if _mm_material == null:
		_mm_material = minimap.make_material(_fog_mode != ViewFogOfWar.MODE_NONE)
	return _mm_material


## Replays and observers (task REP2): whose vision the world and the minimap show. -1 = everything (fog off); a pid = that player's
## fog (when the match has fog at all). Presentation only: the sim keeps every player's fog either way.
func set_perspective(pid: int) -> void:
	local_pid = pid
	if view != null:
		view.set_local_player(pid, pid < 0)
	if fog == null or sim == null:
		return
	_fog_mode = ViewFogOfWar.MODE_SHROUD_FOG if sim.config.rules.fog != 0 and pid >= 0 else ViewFogOfWar.MODE_NONE
	fog.set_local_player(pid)
	fog.set_mode(_fog_mode)
	if _fog_mode != ViewFogOfWar.MODE_NONE:
		fog.sync(sim.fog, pid)
	if _mm_material is ShaderMaterial:
		(_mm_material as ShaderMaterial).set_shader_parameter("fow_enabled", 1.0 if _fog_mode != ViewFogOfWar.MODE_NONE else 0.0)


## The viewed pid (-1 = everything).
func perspective() -> int:
	return local_pid


## A replay seek built a new `SimWorld` (the old one is dropped): the stage keeps its terrain, atmosphere and FX and re-mirrors the
## entities of the new world. The map is identical (same seed), so the terrain sources stay valid.
func rebind_world(w: SimWorld) -> void:
	sim = w
	if view == null:
		return
	view.sim = w
	view.teardown()
	view.bind_world()
	if fx_stage != null and fx_stage.router != null:
		fx_stage.router.sim = w
	if fog != null:
		fog.last_version = -1
		if _fog_mode != ViewFogOfWar.MODE_NONE:
			fog.sync(sim.fog, local_pid)


## THE per-rendered-frame entry point: view mirror + fog feed + cloud/cascade upkeep.
func frame(dt: float, alpha: float, events: PackedInt32Array) -> void:
	if view == null:
		return
	_frames += 1
	view.frame(dt, alpha, events)
	if fog != null:
		if _fog_mode != ViewFogOfWar.MODE_NONE and _frames % 6 == 0:
			fog.sync(sim.fog, local_pid)
		fog.advance(dt)
	if _frames % 15 == 0:
		_fit_camera()
	if minimap != null:
		minimap.flush(dt)


## A one-off terrain preview of a finished map for the lobby (no sim, no nodes): the minimap bake. Null on failure.
static func bake_preview(map: MapData) -> Texture2D:
	if map == null or not map.is_finalized():
		return null
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var q: ViewQuality = make_quality()
	var m: ViewMoodDef = ViewMoodDef.for_map(map.biome, map.family, ViewMoodDef.load_all(), bool(q.extras.get("night_maps", true)), map.seed_value,
		str(q.extras.get("look", "auto")))
	var mm: ViewMinimapSource = ViewMinimapSource.new()
	return mm.bake(src, m)
