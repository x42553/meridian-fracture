extends RefCounted
## VIEW-W2 / VIEW-O3 test kit (no class_name; tests preload it): a REAL SimWorld on the shipped balance data (four rosters: NAPC, NEC,
## DEF, AE so that wrecks and every structure recipe exist) on the flat 96 x 96 test map, a ViewWorld with a recording FX port on top
## (flat fixture terrain, camera over the map centre), and small stepping helpers. Sim and view are real; only the terrain is a fixture.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")
const C: int = SimConfig.CELL
const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.def.vanilla", "roster.ae.vanilla"]

static var _data: GameData = null


static func data() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


## Real world: `n` players (teams 1..n unless `teams` is given), fog on/off, full system pipeline.
static func sim(n: int = 2, fog: bool = false, teams: PackedInt32Array = PackedInt32Array()) -> SimWorld:
	var d: GameData = data()
	var map: MapData = SimTestKit.make_map()
	for s: DefStructure in d.structures:
		map.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	for i: int in n:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": ROSTERS[i], "team": teams[i] if i < teams.size() else i + 1,
			"color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "w2_kit"}, "rules": {"victory": 0, "fog": 1 if fog else 0}, "players": pl})
	return SimWorld.create(d, cfg, map)


## ViewWorld over `w` for `pid` (-1 observer): flat fixture terrain, camera on the map centre, the FX port in recording mode.
static func view(w: SimWorld, pid: int = 0, focus_cells: Vector2 = Vector2(48.0, 48.0), zoom: float = 0.4) -> ViewWorld:
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
	cam.snap_to(focus_cells * ViewConsts.CELL_M, 0.0, zoom)
	cam.advance(0.0)
	vw.fx.recording = true
	return vw


static func free_view(vw: ViewWorld) -> void:
	vw.teardown()
	vw.free()


## Structure with its top-left cell at (cx, cy).
static func place(w: SimWorld, id: String, pid: int, cx: int, cy: int, reason: int = SimEvent.SPAWN_INITIAL, flags: int = 0) -> SimEntity:
	var idx: int = w.data.structure_idx(id)
	var s: DefStructure = w.data.structures[idx]
	return w.spawn_structure(idx, pid, cx * C + s.fp_w * C / 2, cy * C + s.fp_h * C / 2, 0, flags, 500, 0, reason)


static func unit(w: SimWorld, pid: int, foot: bool, cx: int, cy: int) -> SimEntity:
	for ui: int in w.players[pid].roster.producible_units:
		var u: DefUnit = w.data.units[ui]
		if u.weapons.is_empty():
			continue
		if (foot and u.move_class == DefEnums.MoveClass.FOOT) or (not foot and (u.move_class == DefEnums.MoveClass.TRACKED or u.move_class == DefEnums.MoveClass.WHEELED)):
			return w.spawn_unit(ui, pid, cx * C + C / 2, cy * C + C / 2, 0, 0, 500)
	return null


## One sim tick and `frames` rendered frames (the events of the tick go to the first one).
static func tick(vw: ViewWorld, n: int = 1, frames: int = 3) -> void:
	for i: int in n:
		vw.sim.step()
		var ev: PackedInt32Array = vw.sim.events.take()
		for k: int in frames:
			vw.frame(1.0 / 60.0, float(k + 1) / float(frames), ev if k == 0 else PackedInt32Array())


static func structure_view(vw: ViewWorld, id: int) -> ViewStructure:
	return vw.entity_view(id) as ViewStructure
