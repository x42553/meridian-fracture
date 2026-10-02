extends Node3D
## VIEW-03 / VIEW-04 visual acceptance: a REAL generated map through the whole world-look stack (terrain, water, atmosphere and
## mood, decor, scorch layer, blob shadows, fog of war, minimap) seen through ViewCamera.
##   tools/gd shot res://tests/visual/atmosphere_lab.tscn out.png --size 1920x1080 -- --biome=0 --view=gameplay
## Args: --biome=0..3 --family=0|1|2 --seed=N --size=N --mood=<id> --view=<name> --focus=cx,cy --find=<terrain> --yaw=deg
##       --zoom=0..1 --bias=deg --fog=0|1|2 (0 none, 1 explored-visible, 2 shroud+fog fixture) --scorch --blob --ui (minimap)
##       --low (LOW shaders) --preset=0..3 --nodecor --nowater

const VIEWS: Dictionary = {
	"overview": [Vector2(96, 96), 0.0, 1.0, 0.0],
	"gameplay": [Vector2(92, 104), 15.0, 0.5, 0.0],
	"close": [Vector2(70, 80), 20.0, 0.0, 0.0],
	"far": [Vector2(96, 100), 15.0, 0.95, 0.0],
	"mid": [Vector2(60, 120), -20.0, 0.35, 0.0],
}
const FogFx := preload("res://tests/fixtures/view_fog_fixture.gd")

var terrain: ViewTerrain = null
var water: ViewWater = null
var atmo: ViewAtmosphere = null
var decor: ViewDecor = null
var scorch: ViewScorchLayer = null
var fog: ViewFogOfWar = null
var cam: ViewCamera = null
var map: MapData = null
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var biome: int = int(_args.get("biome", "0"))
	var family: int = int(_args.get("family", "0"))
	var t0: int = Time.get_ticks_usec()
	map = MapGenerator.generate({
		"family": family, "size": int(_args.get("size", "192")), "seed": int(_args.get("seed", "1337")),
		"layout_players": int(_args.get("players", "2")), "params": {"biome": biome},
	})
	if map == null:
		push_error("atmosphere_lab: map generation failed")
		return
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	var qs: Dictionary = ViewQuality.load_presets()
	var q: ViewQuality = ViewQuality.create(qs, int(_args.get("preset", "2")), ViewQuality.detect_renderer())
	var low: bool = _args.has("low")
	var detail: ViewDetailTextures = ViewDetailTextures.build(256)
	var moods: Dictionary = ViewMoodDef.load_all()
	var mood: ViewMoodDef = moods[_args["mood"]] as ViewMoodDef if _args.has("mood") else ViewMoodDef.for_map(map.biome, map.family, moods, not _args.has("day"))

	terrain = ViewTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(src, 2, detail, low)
	terrain.apply_mood(mood)

	atmo = ViewAtmosphere.new()
	atmo.name = "Atmosphere"
	add_child(atmo)
	atmo.setup()
	atmo.apply_quality(q)
	atmo.apply_mood(mood)

	if not _args.has("nowater"):
		water = ViewWater.new()
		water.name = "Water"
		add_child(water)
		water.build(terrain, detail, low)
		water.apply_mood(mood)

	scorch = ViewScorchLayer.new()
	scorch.setup(terrain.world_size(), q.get_int(&"scorch_res"))
	terrain.set_scorch_texture(scorch.texture)

	if not _args.has("nodecor"):
		decor = ViewDecor.new()
		decor.name = "Decor"
		add_child(decor)
		decor.build(terrain, src, q)
		decor.apply_mood(mood)

	fog = ViewFogOfWar.new()
	fog.setup(map.w, map.h, Vector2.ZERO, ViewConsts.CELL_M)
	var fmode: int = int(_args.get("fog", "0"))
	fog.set_mode(fmode)
	if fmode > 0:
		var centers: Array[Vector2i] = []
		for k: int in map.start_cells.size() / 2:
			centers.append(Vector2i(map.start_cells[k * 2], map.start_cells[k * 2 + 1]))
		var api: FogFx.Api = FogFx.Api.new()
		api.set_bytes(FogFx.discs(map.w, map.h, centers.slice(0, 1), float(_args.get("fogr", "22")), float(_args.get("fogr", "22")) * 1.8))
		fog.set_local_player(0)
		fog.sync(api, 0)
		fog.advance(1.0)

	cam = ViewCamera.new()
	cam.name = "Camera"
	cam.auto_input = false
	cam.edge_scroll_enabled = false
	add_child(cam)
	cam.configure(Rect2(Vector2.ZERO, terrain.world_size()), terrain)
	var v: Array = VIEWS.get(str(_args.get("view", "gameplay")), VIEWS["gameplay"])
	var focus: Vector2 = v[0] as Vector2
	if _args.has("focus"):
		var p: PackedStringArray = str(_args["focus"]).split(",")
		focus = Vector2(float(p[0]), float(p[1]))
	elif _args.has("find"):
		focus = _find_focus(str(_args["find"]), focus)
	elif not _args.has("view") and map.start_cells.size() >= 2:
		focus = Vector2(float(map.start_cells[0]), float(map.start_cells[1]) + 6.0)
	cam.snap_to(focus * ViewConsts.CELL_M, float(_args.get("yaw", str(v[1]))), float(_args.get("zoom", str(v[2]))), float(_args.get("bias", str(v[3]))))
	cam.advance(0.0)
	var near: float = atmo.fit_shadows(cam.current_height(), cam.current_pitch_deg(), cam.fov_deg)
	cam.camera.near = near
	if _args.has("scorch"):
		_paint_scorch(focus * ViewConsts.CELL_M)
	if _args.has("blob"):
		_blob_test(focus)
	if _args.has("ui"):
		_minimap(src, mood)
	print("ATMO_LAB mood=", mood.mood_name, " gen+build ms=", (Time.get_ticks_usec() - t0) / 1000, " decor=", decor.total_instances() if decor != null else 0,
		" mm=", decor.multimesh_count if decor != null else 0, " focus=", focus, " near=", near)


func _paint_scorch(c: Vector2) -> void:
	scorch.paint(c, float(_args.get("srad", "4")), ViewScorchLayer.Kind.CRATER if not _args.has("soot") else ViewScorchLayer.Kind.SCORCH)
	scorch.paint(c + Vector2(9, 3), 2.5, ViewScorchLayer.Kind.SCORCH)
	scorch.paint(c + Vector2(-8, 5), 2.0, ViewScorchLayer.Kind.SCORCH)
	scorch.paint(c + Vector2(3, 10), 3.0, ViewScorchLayer.Kind.RUBBLE_STAIN)
	scorch.paint_tread(c + Vector2(-14, -4), c + Vector2(6, -9), 1.1)
	scorch.paint_tread(c + Vector2(-14, -2), c + Vector2(6, -7), 1.1)
	scorch.flush()


func _blob_test(focus: Vector2) -> void:
	var bs: ViewBlobShadows = ViewBlobShadows.new()
	add_child(bs)
	bs.setup(64)
	var pos: PackedVector3Array = PackedVector3Array()
	var rad: PackedFloat32Array = PackedFloat32Array()
	for i: int in 24:
		pos.append(Vector3(focus.x * 3.0 + float(i % 6) * 5.0 - 12.0, 0.0, focus.y * 3.0 + float(i / 6) * 5.0 - 8.0))
		rad.append(1.6)
	bs.update(terrain, pos, rad)


func _minimap(src: ViewTerrainSource, mood: ViewMoodDef) -> void:
	var mm: ViewMinimapSource = ViewMinimapSource.new()
	mm.bake(src, mood)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var rect: TextureRect = TextureRect.new()
	rect.texture = mm.texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.custom_minimum_size = Vector2(280, 280)
	rect.size = Vector2(280, 280)
	rect.position = Vector2(20, 20)
	rect.material = mm.make_material(int(_args.get("fog", "0")) > 0)
	layer.add_child(rect)


func _find_focus(what: String, dflt: Vector2) -> Vector2:
	var ids: Dictionary = {"water": [1, 2], "deep": [0], "cliff": [13], "mountain": [14], "forest": [8], "urban": [12], "road": [9], "rock": [7], "sand": [6], "beach": [3], "shallow": [1]}
	var best: Vector2 = dflt
	var best_d: float = 1.0e9
	for i: int in map.n:
		var hit: bool = (what == "deposit" and map.deposit_max[i] > 0) or (ids.has(what) and (ids[what] as Array).has(int(map.terrain[i])))
		if hit and what == "mountain" and (i % map.w < 8 or i / map.w < 8 or i % map.w > map.w - 9 or i / map.w > map.h - 9):
			hit = false
		if hit:
			var p: Vector2 = Vector2(float(i % map.w), float(i / map.w))
			var d: float = p.distance_to(Vector2(float(map.w) * 0.5, float(map.h) * 0.5))
			if d < best_d:
				best_d = d
				best = p
	return best


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
