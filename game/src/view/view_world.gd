class_name ViewWorld
extends Node3D
## Root of the presentation layer (render spec 3.0 / 3.1 / 5.2): mirrors the sim entities as ViewEntity records, drives them
## every rendered frame (two-sample interpolation, visibility, animation channels) and owns the overlays. It reads the sim
## and NEVER writes it. Subsystems that later waves deliver (water, atmosphere, fog texture, decor, FX, projectiles, ghosts,
## zones, warnings ...) are not declared here yet; `stats()["ms"]` reports the cost of the ones that exist.

signal build_progress(fraction: float, stage: String)
signal build_finished()

const PROOF_TANK: StringName = &"proof.veh_tank"
const PROOF_SQUAD: StringName = &"proof.inf_squad"
const RECONCILE_EVERY: int = 30
const FULL_UPDATE_EVERY: int = 12  ## frames between updates of off-screen entities (5 Hz at 60 fps)
const VIS_REFRESH_EVERY: int = 12
const STATIC_SAMPLE_EVERY: int = 6  ## ticks between samples of structures

var sim: SimWorld = null
var local_pid: int = 0
var observer: bool = false
var quality: ViewQuality = null
var defs: ViewDefAdapter = null
var opts: ViewBuildOptions = null

var camera: ViewCamera = null
var terrain: ViewTerrain = null
var models: ViewModelBuilder = null
## Set by `AppViewStage.abort()` (quit during loading): `build_async` returns at its next yield point.
var aborted: bool = false
var materials: ViewMaterials = null
var book: ViewRecipeBook = null
var backend: ViewUnitBackend = null
var router: ViewEventRouter = null
var selection: ViewSelection = null
var health_bars: ViewHealthBars = null
var picker: ViewPicker = null
# VIEW-W2 / VIEW-O3 state views (created by ViewStateOverlays; `fx` exists from creation on and is a no-op until an FxManager is bound)
var state: ViewStateOverlays = null
var fx: ViewFxPort = null
var scaffolds: ViewScaffolds = null
var rubble: ViewRubble = null
var ghosts: ViewGhosts = null
var zones: ViewZones = null
var status_marks: ViewStatusMarks = null
var warnings: ViewWarnings = null
var float_text: ViewFloatText = null
var debug: ViewDebugOverlay = null

# per-frame state read by entities / overlays
var frame_no: int = 0
var tick: int = 0
var alpha: float = 0.0
var time: float = 0.0
var match_over: bool = false
var drive_camera: bool = true  ## call camera.advance(dt) in frame(); false when the app drives it

var _by_id: Dictionary = {}  # int -> ViewEntity
var _active: Array[ViewEntity] = []
var _air: Array[ViewEntity] = []
var _dispose_q: Array[ViewEntity] = []
var phase_ids: Dictionary = {}  # structure id -> true while its phase is not ACTIVE (health bars)
var _units_root: Node3D = null
var _last_tick: int = -1
var _prev_calls: int = 0
var _vis_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
var _roster_of: Dictionary = {}  # owner -> roster id
var _stamp: int = 0
var _speed: float = 1.0
var _paused: bool = false
var _sea: float = -1000.0
var _ms: Dictionary = {"router": 0.0, "sample": 0.0, "entities": 0.0, "overlays": 0.0, "camera": 0.0, "total": 0.0}
var _zones_seen: int = 0
var _bound: bool = false
var _created_camera: bool = false
var _team_ver: int = -1


## Registers the shader globals FIRST, then builds the node tree (spec 3.1).
static func create(q: ViewQuality) -> ViewWorld:
	ViewGlobals.ensure()
	var w: ViewWorld = ViewWorld.new()
	w.name = "ViewWorld"
	w.quality = q
	w._init_subsystems()
	return w


func _init_subsystems() -> void:
	defs = ViewDefAdapter.new()
	book = ViewRecipeBook.new()
	materials = ViewMaterials.new()
	models = ViewModelBuilder.new()
	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	backend = ViewNodeBackend.new()
	router = ViewEventRouter.new()
	selection = ViewSelection.new()
	selection.name = "Selection"
	add_child(selection)
	health_bars = ViewHealthBars.new()
	health_bars.name = "HealthBars"
	add_child(health_bars)
	picker = ViewPicker.new()
	state = ViewStateOverlays.new()
	state.name = "StateOverlays"
	add_child(state)
	fx = state.fx


# ---- build ------------------------------------------------------------------------------------------------------------

## Coroutine: `await view.build_async(...)`. Yields between the heavy stages so the loading screen keeps animating.
func build_async(w: SimWorld, local_player: int, options: ViewBuildOptions = null) -> void:
	_begin_build(w, local_player, options)
	build_progress.emit(0.02, "materials")
	await _yield()
	if aborted:
		return
	_build_terrain_and_camera()
	build_progress.emit(0.30, "terrain")
	await _yield()
	if aborted:
		return
	_prewarm_models()
	while models.pending() > 0:
		models.pump(4.0)
		build_progress.emit(0.30 + 0.5 * (1.0 - float(models.pending()) / 64.0), "models")
		await _yield()
		if aborted:
			return
	models.pump(4.0)
	_finish_build()


## Synchronous build for tools and tests (same stages, no yields).
func build_sync(w: SimWorld, local_player: int, options: ViewBuildOptions = null) -> void:
	_begin_build(w, local_player, options)
	_build_terrain_and_camera()
	_finish_build()


func _exit_tree() -> void:
	if models != null:
		models.cancel()  # background model builds must not outlive the node (quit during loading hung Main::cleanup)


func _yield() -> void:
	if is_inside_tree():
		await get_tree().process_frame


func _begin_build(w: SimWorld, local_player: int, options: ViewBuildOptions) -> void:
	sim = w
	local_pid = local_player
	observer = local_player < 0
	opts = options if options != null else ViewBuildOptions.new()
	if quality == null:
		quality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = opts.screenshot_mode
	defs.setup(sim.data)
	book.load_all()
	if opts.proof_fallback:
		book.add_recipe({"schema": "meridian.recipe/1", "id": String(PROOF_TANK), "archetype": "veh_tank"}, "proof")
		book.add_recipe({"schema": "meridian.recipe/1", "id": String(PROOF_SQUAD), "archetype": "inf_squad"}, "proof")
		book.link()
	materials.setup(book, quality)
	models.setup(book, quality)
	backend.setup(_units_root, materials, quality)
	router.setup(self)
	_roster_of.clear()
	for p: SimPlayer in sim.players:
		_roster_of[p.pid] = defs.roster_id(p.roster_idx)


func _build_terrain_and_camera() -> void:
	if terrain == null and opts.build_terrain and sim.map != null:
		var src: ViewTerrainSource = ViewTerrainSource.from_map(sim.map)
		var detail: ViewDetailTextures = ViewDetailTextures.build(256)
		terrain = ViewTerrain.new()
		terrain.name = "Terrain"
		add_child(terrain)
		var sub: int = opts.terrain_subdiv if opts.terrain_subdiv > 0 else quality.get_int(&"terrain_subdiv")
		terrain.build(src, maxi(sub, 1), detail, false)
	if terrain != null and terrain.src != null:
		_sea = terrain.src.sea_level_m
	if camera == null and opts.create_camera:
		_created_camera = true
		camera = ViewCamera.new()
		camera.name = "Camera"
		add_child(camera)
		if opts.screenshot_mode:
			camera.edge_scroll_enabled = false
			camera.auto_input = false
	if camera != null and terrain != null and camera.height_func.is_null():
		camera.configure(Rect2(Vector2.ZERO, terrain.world_size()), terrain)
	# rings / bars / picker
	selection.setup(self)
	health_bars.setup(self)
	picker.setup(self)
	state.setup(self)
	scaffolds = state.scaffolds
	rubble = state.rubble
	ghosts = state.ghosts
	zones = state.zones
	status_marks = state.marks
	warnings = state.warnings
	float_text = state.float_text
	debug = state.debug


## Requests the (recipe, style) models the rosters of the match can produce, on worker threads: every producible unit and structure, the
## start HQ + MCV, the summons / drones the roster can spawn, and the neutral structures of the map. Anything missed here is built
## synchronously mid-match (`models.stat_sync_builds`): a 20-30 ms hitch the first time that structure / unit appears.
func _prewarm_models() -> void:
	if opts.prewarm_scope <= 0:
		return
	var seen: Dictionary = {}
	var styles: Dictionary = {}  # style ids of the shooters: projectile meshes are styled by the shooter
	for p: SimPlayer in sim.players:
		if p.roster == null or p.controller == SimPlayer.Controller.NONE:
			continue
		var showable: PackedInt32Array = defs.roster_showable(p.roster_idx)
		for i: int in range(0, showable.size(), 2):
			_request_model(showable[i], showable[i + 1], p.pid, seen, styles)
	for e: SimEntity in sim.entities:
		if e.kind == SimEntity.Kind.NEUTRAL:
			_request_model(SimEntity.Kind.NEUTRAL, e.def_idx, e.owner, seen, styles)
	for rid: String in book.ids():  # projectile meshes (ViewProjectiles builds them on first launch otherwise)
		if rid.begins_with("proj."):
			models.request(StringName(rid), &"auto", 10000)
			for sid: Variant in styles:
				models.request(StringName(rid), sid as StringName, 10000)


func _request_model(kind: int, def_idx: int, pid: int, seen: Dictionary, styles: Dictionary) -> void:
	var vd: ViewDef = defs.def_for(kind, def_idx)
	if vd == null:
		return
	var rid: StringName = _recipe_for(vd)
	var sid: StringName = _style_for(vd, pid)
	styles[sid] = true
	var key: StringName = ViewModelBuilder.key_of(rid, sid, vd.scale_bp)
	if seen.has(key):
		return
	seen[key] = true
	models.request(rid, sid, vd.scale_bp)


func _finish_build() -> void:
	bind_world()
	if _created_camera and camera != null:
		_snap_to_start()
	build_progress.emit(1.0, "done")
	build_finished.emit()


## Camera on the local player's start cell (yaw 0, ViewCamera.START_ZOOM); the map centre for observers.
func _snap_to_start() -> void:
	var focus: Vector2 = Vector2.ZERO
	if terrain != null:
		focus = terrain.world_size() * 0.5
	for slot: SimPlayerSlot in sim.config.players:
		if slot.pid == local_pid and sim.map != null:
			var rec: int = slot.start * MapData.SPAWN_STRIDE
			if rec >= 0 and rec + 1 < sim.map.spawns.size():
				var cell: int = sim.map.spawns[rec + 1]
				focus = Vector2(float(cell % sim.map.w) + 0.5, float(cell / sim.map.w) + 0.5) * ViewConsts.CELL_M
	camera.snap_to(focus, 0.0, ViewCamera.START_ZOOM)
	camera.start_anchor = focus
	camera.set_view_margins(camera.view_margin_px)


## Mirrors every entity that already exists (initial HQ / units / neutrals). Their tick-0 SPAWNED events are then duplicates.
func bind_world() -> void:
	_last_tick = sim.tick
	tick = sim.tick
	for e: SimEntity in sim.by_id:  # by_id, not entities: spawns of the current tick are queued into the lists at the next step
		if e == null or _by_id.has(e.id) or (e.flags & SimFlags.F_GONE) != 0:
			continue
		_create_from_entity(e)
	_bound = true


func teardown() -> void:
	for ve: ViewEntity in _active.duplicate():
		ve.dispose(self)
	_active.clear()
	_air.clear()
	_by_id.clear()
	phase_ids.clear()
	state.clear()
	_bound = false
	ViewGlobals.screenshot_mode = false


func set_local_player(pid: int, as_observer: bool = false) -> void:
	local_pid = pid
	observer = as_observer or pid < 0
	for ve: ViewEntity in _active:
		ve.vis_ver = -1
		ve.next_vis_frame = 0
	if state != null:
		state.clear()  # zones, warnings and ghosts are per viewer: they are rebuilt at the next sync


func set_game_speed(speed: float, paused: bool) -> void:
	_speed = speed
	_paused = paused


func apply_quality(q: ViewQuality) -> void:
	quality = q
	materials.set_quality(q)


# ---- frame ------------------------------------------------------------------------------------------------------------

## THE only per-frame entry point (render spec 3.0). `events` = world.events.take() of this rendered frame.
func frame(dt: float, alpha_in: float, events: PackedInt32Array) -> void:
	if sim == null:
		return
	var t0: int = Time.get_ticks_usec()
	frame_no += 1
	time += dt
	ViewGlobals.tick(dt)
	if camera != null:
		if drive_camera:
			camera.advance(dt)
		_vis_rect = camera.visible_ground_rect()
	var t1: int = Time.get_ticks_usec()
	if ViewTeamColors.version != _team_ver:
		_team_ver = ViewTeamColors.version  # colour-blind mode / palette change: rewrite the material uniforms once
		materials.refresh_team_colors()
		for ve0: ViewEntity in _active:
			ve0.team_color = ViewTeamColors.color(ve0.team_index)
	tick = sim.tick
	alpha = 1.0 if (_paused or sim.match_state != SimWorld.MATCH_RUNNING) else clampf(alpha_in, 0.0, 1.0)
	router.process(events)
	state.consume(events)
	var t2: int = Time.get_ticks_usec()
	if frame_no % RECONCILE_EVERY == 0:
		reconcile()
	if tick != _last_tick:
		_sample_tick()
		_last_tick = tick
	_prev_calls = 0
	var t3: int = Time.get_ticks_usec()
	_entity_loop(dt)
	var t4: int = Time.get_ticks_usec()
	backend.flush()
	selection.update(dt)
	health_bars.update(dt)
	state.update(dt)
	var t5: int = Time.get_ticks_usec()
	_ms["camera"] = float(t1 - t0) / 1000.0
	_ms["router"] = float(t2 - t1) / 1000.0
	_ms["sample"] = float(t3 - t2) / 1000.0
	_ms["entities"] = float(t4 - t3) / 1000.0
	_ms["overlays"] = float(t5 - t4) / 1000.0
	_ms["total"] = float(t5 - t0) / 1000.0


## Optional exact mode (sim_core 3.10): the net adapter calls this right before every world.step().
func capture_prev(w: SimWorld) -> void:
	_prev_calls += 1
	var by_id: Array[SimEntity] = w.by_id
	for ve: ViewEntity in _active:
		if ve.sim_gone or ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL:
			continue
		if ve.id < by_id.size():
			var e: SimEntity = by_id[ve.id]
			if e != null:
				ve.capture(e)


func _sample_tick() -> void:
	var shift: bool = _prev_calls == 0
	var by_id: Array[SimEntity] = sim.by_id
	var n: int = by_id.size()
	var phase: int = tick % STATIC_SAMPLE_EVERY
	for ve: ViewEntity in _active:
		if ve.sim_gone:
			continue
		var e: SimEntity = by_id[ve.id] if ve.id < n else null
		if e == null:
			ve.sim_gone = true
			continue
		if ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL:
			if ve.id % STATIC_SAMPLE_EVERY != phase and ve.max_hp > 0:
				continue
		ve.sample(self, e, shift)


func _entity_loop(dt: float) -> void:
	var by_id: Array[SimEntity] = sim.by_id
	var n: int = by_id.size()
	var fog_ver: int = 0 if observer else sim.fog.fog_version(local_pid)
	var rect: Rect2 = _vis_rect
	var fno: int = frame_no
	_dispose_q.clear()
	for ve: ViewEntity in _active:
		var e: SimEntity = by_id[ve.id] if ve.id < n else null
		if e == null and not ve.sim_gone:
			ve.sim_gone = true
			if not ve.dead:
				_dispose_q.append(ve)
				continue
		if ve.dead or ve.sim_gone:
			if tick >= ve.dying_until_tick:
				_dispose_q.append(ve)
				continue
		# visibility (cached per fog_version, refreshed every VIS_REFRESH_EVERY frames)
		if ve.vis_ver != fog_ver or fno >= ve.next_vis_frame:
			ve.vis_ver = fog_ver
			ve.next_vis_frame = fno + VIS_REFRESH_EVERY + (ve.id & 3)
			var vs_new: int = _visibility(ve, e)
			if vs_new != ve.vs:
				ve.vs = vs_new
				backend.set_visible(ve, vs_new != ViewConsts.VS_HIDDEN)
		if ve.vs == ViewConsts.VS_HIDDEN:
			continue
		var inside: bool = rect.has_point(Vector2(ve.wx, ve.wz))
		ve.in_view = inside
		if not inside and fno < ve.next_full_frame:
			continue
		var step_dt: float = dt
		if not inside:
			step_dt = dt * float(maxi(fno - ve.last_frame, 1))
			ve.next_full_frame = fno + FULL_UPDATE_EVERY + (ve.id % 5)
		ve.last_frame = fno
		if ve.dead:
			_dying(ve, step_dt)
		ve.update(self, e, step_dt, alpha, inside)
		if ve.dead and ve.dying_kind == ViewConsts.DK_SILENT:
			_silent_shrink(ve)
	for ve: ViewEntity in _dispose_q:
		dispose_entity(ve)


func _dying(ve: ViewEntity, dt: float) -> void:
	if ve is ViewUnit:
		(ve as ViewUnit).dying_pose(self, dt)


func _silent_shrink(ve: ViewEntity) -> void:
	var span: float = float(maxi(ve.dying_until_tick - ve.dying_start_tick, 1))
	var k: float = clampf((float(ve.dying_until_tick) - (float(tick) + alpha)) / span, 0.0, 1.0)
	ve.scale_k = k
	var b: Basis = ve.xf.basis.scaled(Vector3(k, k, k))
	backend.set_xform(ve, Transform3D(b, ve.xf.origin))


## Visibility rules of spec 5.3 (fog, stealth, containers, dying records, neutral structures).
func _visibility(ve: ViewEntity, e: SimEntity) -> int:
	if ve.dead or ve.sim_gone:
		if not observer and not sim.cell_visible(local_pid, ve.x_cur >> 10, ve.y_cur >> 10):
			return ViewConsts.VS_HIDDEN
		return ViewConsts.VS_DYING
	if (ve.sim_flags & SimFlags.F_INSIDE) != 0:
		return ViewConsts.VS_HIDDEN
	if observer or e == null:
		return ViewConsts.VS_VISIBLE
	if e.owner == local_pid or sim.entity_visible(local_pid, e):
		return ViewConsts.VS_VISIBLE
	if ve.kind == SimEntity.Kind.NEUTRAL or (ve.kind == SimEntity.Kind.STRUCTURE and ve.owner < 0):
		if sim.cell_explored(local_pid, ve.x_cur >> 10, ve.y_cur >> 10):
			return ViewConsts.VS_VISIBLE
	return ViewConsts.VS_HIDDEN


## Id-set diff between the sim and the mirror (first frame, missed events, replay seek).
func reconcile() -> void:
	_stamp += 1
	for e: SimEntity in sim.by_id:  # by_id, not entities: entities spawned this tick are only listed after the next step
		if e == null:
			continue
		var ve: ViewEntity = _by_id.get(e.id) as ViewEntity
		if ve == null:
			if (e.flags & SimFlags.F_GONE) == 0:
				_create_from_entity(e)
			continue
		ve.stamp = _stamp
		if (e.flags & SimFlags.F_GONE) != 0 and not ve.dead:
			ve.dead = true
			ve.dying_kind = ViewConsts.DK_SILENT
			ve.dying_start_tick = tick
			ve.dying_until_tick = tick + ViewEventRouter.SILENT_TICKS
	for ve2: ViewEntity in _active:
		if ve2.stamp != _stamp and not ve2.sim_gone:
			ve2.sim_gone = true
			if not ve2.dead:
				ve2.dead = true
				ve2.dying_kind = ViewConsts.DK_SILENT
				ve2.dying_start_tick = tick
				ve2.dying_until_tick = tick + ViewEventRouter.SILENT_TICKS


# ---- entity lifecycle -------------------------------------------------------------------------------------------------

func has_entity(id: int) -> bool:
	return _by_id.has(id)


func entity_view(id: int) -> ViewEntity:
	return _by_id.get(id) as ViewEntity


## Aircraft records (picker candidates).
func air_list() -> Array[ViewEntity]:
	return _air


func entity_count() -> int:
	return _active.size()


## Active records (read-only iteration; do not keep across frames).
func entities() -> Array[ViewEntity]:
	return _active


func _create_from_entity(e: SimEntity) -> ViewEntity:
	var reason: int = SimEvent.SPAWN_INITIAL
	if e.kind == SimEntity.Kind.WRECK:
		reason = SimEvent.SPAWN_WRECK
	elif (e.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
		reason = SimEvent.SPAWN_PLACED
	var ve: ViewEntity = create_entity(e.id, e.kind, e.def_idx, e.owner, e.x, e.y, e.facing, reason, e.born)
	return ve


## Creates the record from the SPAWNED payload alone (spec 5.2). Kind ZONE is counted and left to ViewZones (VIEW-W2).
func create_entity(id: int, kind: int, def_idx: int, own: int, x: int, y: int, facing: int, reason: int, ev_tick: int) -> ViewEntity:
	if kind == SimEntity.Kind.ZONE:
		_zones_seen += 1
		return null
	var vd: ViewDef = defs.def_for(kind, def_idx)
	var recipe: StringName = _recipe_for(vd)
	var style: StringName = _style_for(vd, own)
	var model: ViewModel = models.get_model(recipe, style, vd.scale_bp)
	var structural: bool = kind == SimEntity.Kind.STRUCTURE or kind == SimEntity.Kind.NEUTRAL
	var ve: ViewEntity
	if structural:
		ve = ViewStructure.new()
	else:
		ve = ViewUnit.new()
	ve.id = id
	ve.kind = kind
	ve.def_idx = def_idx
	ve.owner = own
	ve.vdef = vd
	ve.recipe_id = recipe
	ve.style_id = style
	ve.model = model
	ve.born_tick = ev_tick
	ve.layer = vd.layer
	ve.team_index = _team_index(own)
	ve.team_color = ViewTeamColors.color(ve.team_index)
	ve.motion = ViewConsts.MOTION_STATIC if structural else vd.move_class
	var info: ViewModelInfo = model.info
	ve.members = maxi(info.members, 1)
	ve.height_m = maxf(info.height, 0.5)
	ve.radius_m = maxf(vd.radius_m, 1.5) if structural else maxf(vd.radius_m, info.radius)
	ve.has_mounts = (info.parts_mask & ((1 << ViewMeshBuilder.Part.TURRET1) | (1 << ViewMeshBuilder.Part.TURRET2) | (1 << ViewMeshBuilder.Part.TURRET3))) != 0
	if structural:
		ve.pick_half = Vector3(float(maxi(vd.fp_w, 1)) * 1.5 - 0.25, ve.height_m * 0.5, float(maxi(vd.fp_h, 1)) * 1.5 - 0.25)
	else:
		var r: float = ve.radius_m * 0.9
		ve.pick_half = Vector3(r, ve.height_m * 0.5, r)
	ve.init_placement(x, y, facing)
	ve.derive_flags()
	ve.hp = 1
	ve.max_hp = 1
	backend.add(ve, model, style, ve.team_color, ve.team_index)
	_by_id[id] = ve
	ve.active_idx = _active.size()
	_active.append(ve)
	if kind == SimEntity.Kind.UNIT and (vd.layer == SimEntity.Layer.AIR or vd.move_class >= ViewConsts.MOTION_AIR_FIXED and vd.move_class <= ViewConsts.MOTION_AIR_HOVER):
		_air.append(ve)
	# first read of the live entity (hp, flags); prev = cur so nothing interpolates from the payload position
	var e: SimEntity = sim.get_entity(id)
	if e != null:
		ve.sample(self, e, false)
		ve.x_prev = ve.x_cur
		ve.y_prev = ve.y_cur
		ve.facing_prev = ve.facing_cur
		for m: int in ve.mnt_prev.size():
			ve.mnt_prev[m] = ve.mnt_cur[m]
		if e.hp_max > 0:
			ve.max_hp = e.hp_max
	if structural:
		var st: ViewStructure = ve as ViewStructure
		st.setup_structure(self)
		if reason == SimEvent.SPAWN_PLACED or reason == SimEvent.SPAWN_DEPLOYED:
			st.begin_phase(ViewConsts.PH_BUILDUP, ev_tick, info.buildup_ticks if info.buildup_ticks > 0 else ViewStructure.DEFAULT_BUILDUP_TICKS)
			phase_ids[id] = true
	else:
		(ve as ViewUnit).setup_motion()
	backend.set_visible(ve, false)
	ve.vs = ViewConsts.VS_HIDDEN
	ve.vis_ver = -2
	# frame-of-birth placement so the very first frame is already correct
	ve.wx = float(ve.x_cur) * ViewConsts.M_PER_UNIT
	ve.wz = float(ve.y_cur) * ViewConsts.M_PER_UNIT
	return ve


func note_phase(ve: ViewStructure) -> void:
	if ve.phase != ViewConsts.PH_ACTIVE:
		phase_ids[ve.id] = true


func dispose_entity(ve: ViewEntity) -> void:
	if _by_id.get(ve.id) != ve:
		return
	ve.dispose(self)
	_by_id.erase(ve.id)
	phase_ids.erase(ve.id)
	var i: int = ve.active_idx
	var last: ViewEntity = _active[_active.size() - 1]
	_active[i] = last
	last.active_idx = i
	_active.pop_back()
	ve.active_idx = -1
	_air.erase(ve)
	selection.entity_gone(ve.id)


func set_entity_owner(ve: ViewEntity, new_owner: int) -> void:
	ve.owner = new_owner
	ve.team_index = _team_index(new_owner)
	ve.team_color = ViewTeamColors.color(ve.team_index)
	backend.set_team(ve, ve.team_color, ve.team_index)
	if ve is ViewStructure:
		(ve as ViewStructure).on_captured(self)


func _team_index(own: int) -> int:
	if own < 0 or own >= sim.players.size():
		return -1
	return sim.players[own].color


func _recipe_for(vd: ViewDef) -> StringName:
	if book.has_recipe(vd.recipe_id):
		return vd.recipe_id
	if opts != null and opts.proof_fallback and (vd.kind == SimEntity.Kind.UNIT or vd.kind == SimEntity.Kind.WRECK):
		match vd.move_class:
			ViewConsts.MOTION_FOOT:
				return PROOF_SQUAD
			ViewConsts.MOTION_WHEELED, ViewConsts.MOTION_TRACKED, ViewConsts.MOTION_AMPHIBIOUS:
				return PROOF_TANK
	return vd.recipe_id


func _style_for(vd: ViewDef, own: int) -> StringName:
	return book.style_for_def(vd.id, _roster_of.get(own, "") as String)


# ---- ground helpers (entities call these) ------------------------------------------------------------------------------

func ground_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


func ground_normal(x: float, z: float) -> Vector3:
	return terrain.normal_at(x, z) if terrain != null else Vector3.UP


func sea_level() -> float:
	return _sea


# ---- queries ----------------------------------------------------------------------------------------------------------

func entity_world_pos(id: int, with_height: bool = false) -> Vector3:
	var ve: ViewEntity = entity_view(id)
	if ve == null:
		return Vector3.INF
	return Vector3(ve.wx, ve.wy + (ve.height_m if with_height else 0.0), ve.wz)


## World position of a model socket (turret yaw / barrel recoil applied); +1.2 m above the entity when the socket is missing.
func entity_socket(id: int, socket: StringName) -> Vector3:
	var ve: ViewEntity = entity_view(id)
	if ve == null:
		return Vector3.INF
	if ve.model == null or not ve.model.info.has_socket(socket):
		return Vector3(ve.wx, ve.wy + 1.2, ve.wz)
	return ve.model.info.socket_world(socket, ve.xf, ve.turret_yaw, ve.elevation, ve.recoil)


## Screen rectangle (viewport px) of the projected pick volume.
func entity_screen_rect(id: int) -> Rect2:
	var ve: ViewEntity = entity_view(id)
	if ve == null or camera == null:
		return Rect2()
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var basis_y: Basis = Basis(Vector3.UP, ve.yaw)
	var c: Vector3 = ve.pick_centre()
	for sx: int in 2:
		for sy: int in 2:
			for sz: int in 2:
				var corner: Vector3 = Vector3(ve.pick_half.x * (1.0 if sx == 1 else -1.0), ve.pick_half.y * (1.0 if sy == 1 else -1.0),
					ve.pick_half.z * (1.0 if sz == 1 else -1.0))
				var p: Vector2 = camera.world_to_screen(c + basis_y * corner)
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


func pick(screen_pos: Vector2, filter: int = ViewPicker.PICK_ANY) -> int:
	return picker.pick(screen_pos, filter)


func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int:
	return picker.pick_box(rect, filter, out)


func pick_ground(screen_pos: Vector2) -> Vector3:
	return camera.screen_to_ground(screen_pos) if camera != null else Vector3.INF


func sim_to_world(x: int, y: int) -> Vector3:
	var p: Vector2 = ViewConsts.sim_to_world_xz(x, y)
	return Vector3(p.x, ground_at(p.x, p.y), p.y)


func world_to_sim(p: Vector3) -> Vector2i:
	var s: Vector2i = ViewConsts.world_to_sim_xz(Vector2(p.x, p.z))
	if sim != null and sim.map != null:
		s.x = clampi(s.x, 0, sim.map.w * SimConfig.CELL - 1)
		s.y = clampi(s.y, 0, sim.map.h * SimConfig.CELL - 1)
	return s


func stats() -> Dictionary:
	var vis: int = 0
	for ve: ViewEntity in _active:
		if ve.vs != ViewConsts.VS_HIDDEN:
			vis += 1
	var d: Dictionary = {"entities": _active.size(), "visible": vis, "zones_seen": _zones_seen, "ms": _ms.duplicate(),
		"events": router.stats().duplicate(), "backend": backend.stats(), "state_ms": state.ms_last if state != null else 0.0}
	d["draws"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	d["model_sync"] = [models.stat_sync_builds, models.stat_sync_ms, models.stat_sync_last] if models != null else [0, 0.0, ""]
	return d
