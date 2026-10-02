extends RefCounted
## VIEW-W1 test kit (no class_name; tests preload it): a real SimWorld on the combat test data, a flat fixture terrain, a
## ViewCamera without input and a ViewWorld built synchronously on top of them.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")
const CELL: int = SimConfig.CELL


## Real world: both players on the vanilla test roster, real combat / movement / orders (vision and abilities stages off).
static func sim(n_players: int = 2, seed_value: int = 4242) -> SimWorld:
	return CombatWK.world(n_players, seed_value)


## ViewWorld on `w` (flat terrain fixture, camera 1920x1080 over the map centre). The caller frees it with free_view().
static func view(w: SimWorld, pid: int = 0, cam_focus_cells: Vector2 = Vector2(48.0, 48.0), zoom: float = 0.35) -> ViewWorld:
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.MEDIUM)
	var vw: ViewWorld = ViewWorld.create(q)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(Fx.source(96, func(_x: int, _y: int) -> int: return 0), 2, ViewDetailTextures.build(64), false, false)
	vw.add_child(ter)
	vw.terrain = ter
	var cam: ViewCamera = ViewCamera.new()
	cam.auto_input = false
	cam.edge_scroll_enabled = false
	cam.view_size_override = Vector2(1920.0, 1080.0)
	vw.add_child(cam)
	vw.camera = cam
	vw.drive_camera = false
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.build_terrain = false
	opts.create_camera = false
	opts.prewarm_scope = 0
	opts.screenshot_mode = true
	vw.build_sync(w, pid, opts)
	cam.configure(Rect2(Vector2.ZERO, ter.world_size()), ter)
	cam.snap_to(cam_focus_cells * ViewConsts.CELL_M, 0.0, zoom)
	cam.advance(0.0)
	return vw


static func free_view(vw: ViewWorld) -> void:
	vw.teardown()
	vw.free()


static func tank(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return CombatWK.tank(w, owner, cx, cy)


static func rifle(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return CombatWK.rifle(w, owner, cx, cy)


## One rendered frame at tick alpha `a` with the events the sim produced since the last take().
static func frame(vw: ViewWorld, a: float = 0.5, dt: float = 1.0 / 60.0) -> void:
	vw.frame(dt, a, vw.sim.events.take())


## Steps the sim n ticks and renders one frame.
static func step_frame(vw: ViewWorld, n: int, a: float = 0.5) -> void:
	vw.sim.run(n)
	frame(vw, a)
