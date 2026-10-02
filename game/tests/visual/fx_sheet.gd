extends Node3D
## VIEW-F1 / F2 visual acceptance and performance harness (spike contact sheets 0-3 through the recipe engine).
##   tools/gd run res://tests/visual/fx_sheet.tscn --gui --size 1280x720 -- --mode=sheet --sheet=0 --out=/abs/sheet_0.png
##   tools/gd shot res://tests/visual/fx_sheet.tscn out.png --size 1280x720 --frames 30 -- --mode=single --fx=expl_large --t=0.5
## Modes: sheet (6 effects x 3 time offsets composited into one PNG; --sheet=0..3, --per=6, --out=, --full to keep native frames),
##   single (spawn --fx=<id> --t=<s> [--dist= --look=x,y,z --a=x,y,z --b=x,y,z --s=scale] and hold; DevShot captures),
##   chaos (200 shots/s, ~20 explosions/s stress; prints RESULT|chaos|json), count (--n=60 simultaneous composites; RESULT|count|json).
## Common args: --quality=0..3 --seed=N --biome=0..3 --night --nofx (baseline) --tag= --secs=N --rate=x.
## Effects step with an explicit fx.advance(1/60) (deterministic); chaos / count use the real frame clock.

const CW: int = 640
const CH: int = 360

var terrain: ViewTerrain = null
var water: ViewWater = null
var atmo: ViewAtmosphere = null
var scorch: ViewScorchLayer = null
var fx: FxManager = null
var book: FxRecipeBook = null
var cam: Camera3D = null
var map: MapData = null
var label: Label = null

var _args: Dictionary = {}
var _site: Vector3 = Vector3.ZERO
var _water_site: Vector3 = Vector3.ZERO
var _sea: float = 0.0
var _props: Array[Node3D] = []
var _mover: Node3D = null
var _mover_from: Vector3 = Vector3.ZERO
var _mover_to: Vector3 = Vector3.ZERO
var _mover_dur: float = 1.0
var _mover_t0: float = 0.0
var _mover_hide: bool = false
var _swap: Array = []
var _collapse: Array = []
var _record: bool = false
var _samples: Dictionary = {"dt": [], "cpu": [], "proc": [], "draws": [], "prims": []}
var _chaos_on: bool = false
var _carry: Dictionary = {}
var _dust_units: Array[Node3D] = []
var _dust_dir: Array[Vector3] = []


func _ready() -> void:
	_args = _parse_args()
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	_build_world()
	_run.call_deferred()


func _process(delta: float) -> void:
	if _chaos_on:
		_chaos_step(delta)
	if _record:
		var vp: RID = get_viewport().get_viewport_rid()
		(_samples.dt as Array).append(delta * 1000.0)
		(_samples.cpu as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		(_samples.proc as Array).append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		(_samples.draws as Array).append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		(_samples.prims as Array).append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if _mover != null:
		_update_mover()


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var biome: int = int(_args.get("biome", "0"))
	map = MapGenerator.generate({
		"family": int(_args.get("family", "2")), "size": int(_args.get("size", "160")), "seed": int(_args.get("seed", "1337")),
		"layout_players": 2, "params": {"biome": biome},
	})
	var src: ViewTerrainSource = ViewTerrainSource.from_map(map)
	_sea = src.sea_level_m
	var qs: Dictionary = ViewQuality.load_presets()
	var q: ViewQuality = ViewQuality.create(qs, int(_args.get("quality", "2")), ViewQuality.detect_renderer())
	var detail: ViewDetailTextures = ViewDetailTextures.build(256)
	var moods: Dictionary = ViewMoodDef.load_all()
	var mood: ViewMoodDef = ViewMoodDef.for_map(map.biome, map.family, moods, _args.has("night"))
	terrain = ViewTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(src, 2, detail, false)
	terrain.apply_mood(mood)
	atmo = ViewAtmosphere.new()
	atmo.name = "Atmosphere"
	add_child(atmo)
	atmo.setup()
	atmo.apply_quality(q)
	atmo.apply_mood(mood)
	water = ViewWater.new()
	water.name = "Water"
	add_child(water)
	water.build(terrain, detail, false)
	water.apply_mood(mood)
	scorch = ViewScorchLayer.new()
	scorch.setup(terrain.world_size(), q.get_int(&"scorch_res"))
	terrain.set_scorch_texture(scorch.texture)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 38.0
	cam.near = 1.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_find_sites()
	if not _args.has("nofx"):
		book = FxRecipeBook.new()
		if not book.load_file():
			push_error("fx.json: %s" % "; ".join(book.errors()))
		fx = FxManager.new()
		fx.name = "Fx"
		add_child(fx)
		fx.setup(cam, int(_args.get("quality", "2")) as FxManager.Quality, book, terrain, scorch)
		if _args.get("mode", "sheet") != "chaos" and _args.get("mode", "sheet") != "count":
			fx.set_process(false)
		fx.camera_shake.connect(func(_a: float, _p: Vector3) -> void: pass)
	_build_hud()
	atmo.fit_shadows(50.0, 52.0, 38.0)


func _find_sites() -> void:
	var best: float = 1.0e9
	var size: Vector2 = terrain.world_size()
	var pts: Array[Vector2] = []
	for i: int in 9:
		var ang: float = float(i) / 8.0 * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * 26.0)
	pts.append(Vector2.ZERO)
	var wbest: float = 1.0e9
	var x: float = 60.0
	while x < size.x - 60.0:
		var z: float = 60.0
		while z < size.y - 60.0:
			var lo: float = 1.0e9
			var hi: float = -1.0e9
			var wet: int = 0
			for o: Vector2 in pts:
				var h: float = terrain.height_at(x + o.x, z + o.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				if terrain.is_water_at(x + o.x, z + o.y):
					wet += 1
			var d: Vector2 = Vector2(x, z) - size * 0.5
			var score: float = (hi - lo) + d.length() * 0.004
			if wet == 0 and score < best:
				best = score
				_site = Vector3(x, terrain.height_at(x, z), z)
			if wet == pts.size() and d.length() < wbest:
				wbest = d.length()
				_water_site = Vector3(x, terrain.height_at(x, z), z)
			z += 8.0
		x += 8.0
	if _water_site == Vector3.ZERO:
		_water_site = _site + Vector3(60.0, 0.0, 0.0)
	_water_site.y = _sea
	print("FX_SHEET site=", _site, " water=", _water_site)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12.0, 8.0)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	layer.add_child(label)


func _g(p: Vector3, site: Vector3) -> Vector3:
	var x: float = site.x + p.x
	var z: float = site.z + p.z
	var base: float = site.y if site == _water_site else terrain.height_at(x, z)
	return Vector3(x, base + p.y, z)


func _place_camera(look: Vector3, dist: float, pitch_deg: float = 52.0, yaw_deg: float = 20.0) -> void:
	var pitch: float = deg_to_rad(pitch_deg)
	var yaw: float = deg_to_rad(yaw_deg)
	var dir: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.global_position = look + dir * dist
	cam.look_at(look, Vector3.UP)
	fx.camera_focus_dist = dist
	fx.sync_camera()


# ------------------------------------------------------------------ props
func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D, emissive: bool = false) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _make_tank(color: Color) -> Node3D:
	var n: Node3D = Node3D.new()
	_box(Vector3(3.2, 1.0, 5.4), Vector3(0.0, 0.75, 0.0), color, n)
	_box(Vector3(2.2, 0.75, 2.6), Vector3(0.0, 1.6, 0.3), color.lightened(0.08), n)
	_box(Vector3(0.28, 0.28, 3.6), Vector3(0.0, 1.65, -2.0), color.darkened(0.25), n)
	for x: float in [-1.75, 1.75]:
		_box(Vector3(0.6, 0.7, 5.6), Vector3(x, 0.4, 0.0), Color(0.09, 0.09, 0.1), n)
	return n


func _make_building() -> Node3D:
	var n: Node3D = Node3D.new()
	_box(Vector3(10.0, 7.0, 10.0), Vector3(0.0, 3.5, 0.0), Color(0.55, 0.57, 0.6), n)
	_box(Vector3(10.4, 0.5, 10.4), Vector3(0.0, 7.2, 0.0), Color(0.3, 0.3, 0.33), n)
	_box(Vector3(9.0, 0.6, 0.15), Vector3(0.0, 4.5, 5.05), Color(0.9, 0.75, 0.4), n, true)
	_box(Vector3(9.0, 0.6, 0.15), Vector3(0.0, 2.2, 5.05), Color(0.9, 0.75, 0.4), n, true)
	return n


func _make_plane() -> Node3D:
	var n: Node3D = Node3D.new()
	_box(Vector3(1.2, 1.0, 9.0), Vector3.ZERO, Color(0.55, 0.58, 0.62), n)
	_box(Vector3(9.0, 0.18, 2.4), Vector3(0.0, 0.0, 0.5), Color(0.5, 0.53, 0.58), n)
	_box(Vector3(3.0, 0.18, 1.4), Vector3(0.0, 0.2, 3.8), Color(0.5, 0.53, 0.58), n)
	return n


func _add_prop(n: Node3D, pos: Vector3) -> Node3D:
	add_child(n)
	n.global_position = pos
	_props.append(n)
	return n


func _clear_props() -> void:
	for p: Node3D in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	_mover = null
	_swap = []
	_collapse = []


func _start_mover(n: Node3D, from: Vector3, to: Vector3, dur: float, hide_end: bool) -> void:
	_add_prop(n, from)
	_mover = n
	_mover_from = from
	_mover_to = to
	_mover_dur = dur
	_mover_t0 = fx.now()
	_mover_hide = hide_end


func _update_mover() -> void:
	var k: float = clampf((fx.now() - _mover_t0) / _mover_dur, 0.0, 1.0)
	var p: Vector3 = _mover_from.lerp(_mover_to, k)
	if _mover_from.y < 1.0 and _mover_to.y < 1.0:
		p.y = terrain.height_at(p.x, p.z)
	_mover.global_position = p
	if k >= 1.0 and _mover_hide:
		_mover.visible = false


func _apply_prop(kind: String, e: Dictionary, site: Vector3) -> void:
	match kind:
		"tanks":
			var i: int = 0
			for p: Vector3 in [Vector3(-5, 0, 3), Vector3(4, 0, -2), Vector3(1, 0, 6)]:
				var tk: Node3D = _make_tank(Color(0.3, 0.34, 0.22))
				var w: Vector3 = _g(p, site)
				_add_prop(tk, w)
				tk.rotation.y = float(i) * 2.1 + 0.4
				i += 1
		"tank_destroy":
			var w: Vector3 = _g(Vector3.ZERO, site)
			var tk: Node3D = _add_prop(_make_tank(Color(0.3, 0.34, 0.22)), w)
			var wreck: Node3D = _add_prop(_make_tank(Color(0.06, 0.055, 0.05)), w)
			wreck.visible = false
			wreck.rotation.y = 0.35
			_swap = [tk, wreck, fx.now() + 0.1]
		"building_collapse":
			var b: Node3D = _add_prop(_make_building(), _g(Vector3.ZERO, site))
			_collapse = [b, fx.now() + 0.15]
		"plane_line":
			var plane: Node3D = _make_plane()
			_start_mover(plane, _g(Vector3(-60, 22, 0), site), _g(Vector3(60, 22, 0), site), 2.0, false)
			fx.start_stamper(&"aircraft_contrail", plane, 2.8, 4.0, 1.0)
		"plane_crash":
			var a: Vector3 = e.a
			var flight: float = clampf(a.distance_to(e.b as Vector3) / 40.0, 1.0, 2.5)
			var plane: Node3D = _make_plane()
			_start_mover(plane, _g(a, site), _g(e.b as Vector3, site), flight, true)
			plane.look_at_from_position(_g(a, site), _g(e.b as Vector3, site), Vector3.UP)
		"tank_move":
			var tank: Node3D = _make_tank(Color(0.3, 0.34, 0.22))
			_start_mover(tank, _g(Vector3(-26, 0, 0), site), _g(Vector3(26, 0, 0), site), 3.4, false)
			tank.rotation.y = -PI * 0.5
			fx.start_stamper(&"vehicle_dust", tank, 1.1, 4.0, 1.0)
		"welder":
			var wb: Node3D = _box(Vector3(3.0, 1.0, 3.0), Vector3(0, 0.5, 0), Color(0.5, 0.5, 0.52), self)
			wb.global_position = _g(Vector3(0, 0.5, 0), site)
			_props.append(wb)


# ------------------------------------------------------------------ sheet table (the 23 spike effects under their recipe-engine ids)
func _table() -> Array[Dictionary]:
	var t: Array[Dictionary] = []
	t.append({"id": &"muzzle_small_arms", "a": Vector3(-10, 1.3, 0), "b": Vector3(10, 1.0, -2), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 24.0, "times": [0.04, 0.09, 0.2]})
	t.append({"id": &"muzzle_mg", "a": Vector3(-10, 1.3, 2), "b": Vector3(10, 0.8, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 24.0, "times": [0.12, 0.25, 0.5]})
	t.append({"id": &"muzzle_cannon", "a": Vector3(-14, 1.6, 0), "b": Vector3(14, 0, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 34.0, "times": [0.06, 0.24, 0.6]})
	t.append({"id": &"cannon_impact", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1, 0), "dist": 20.0, "times": [0.1, 0.4, 1.3]})
	t.append({"id": &"muzzle_at_missile", "a": Vector3(-18, 1.5, 0), "b": Vector3(18, 0.5, -4), "s": 1.0, "look": Vector3(0, 2, -2), "dist": 46.0, "times": [0.3, 0.72, 1.6]})
	t.append({"id": &"muzzle_artillery", "a": Vector3(-32, 1.5, 4), "b": Vector3(28, 0, -6), "s": 1.0, "look": Vector3(-2, 6, -1), "dist": 84.0, "times": [0.12, 1.2, 2.3]})
	t.append({"id": &"expl_large", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 3, 0), "dist": 52.0, "times": [0.12, 0.5, 1.7]})
	t.append({"id": &"muzzle_beam_thermal", "a": Vector3(-16, 2.5, 0), "b": Vector3(16, 0, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 40.0, "times": [0.3, 0.9, 1.7]})
	t.append({"id": &"muzzle_rail", "a": Vector3(-16, 2.5, 0), "b": Vector3(16, 0.5, -3), "s": 1.0, "look": Vector3(0, 1, -1), "dist": 40.0, "times": [0.04, 0.14, 0.4]})
	t.append({"id": &"emp_pulse", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 10.0, "look": Vector3(0, 0.5, 0), "dist": 38.0, "times": [0.12, 0.45, 0.95], "prop": "tanks"})
	t.append({"id": &"vehicle_destroy", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1, 0), "dist": 28.0, "times": [0.12, 0.7, 3.0], "prop": "tank_destroy"})
	t.append({"id": &"building_collapse", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 3, 0), "dist": 58.0, "times": [0.35, 1.1, 3.2], "prop": "building_collapse"})
	t.append({"id": &"hit_infantry", "a": Vector3(0, 1.0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.8, 0), "dist": 10.0, "times": [0.05, 0.15, 0.4]})
	t.append({"id": &"aircraft_contrail", "a": Vector3(0, 22, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 12, 0), "dist": 105.0, "times": [0.7, 1.4, 2.4], "prop": "plane_line", "nospawn": true})
	t.append({"id": &"aircraft_crash", "a": Vector3(-30, 40, 0), "b": Vector3(15, 0, -5), "s": 1.0, "look": Vector3(-6, 12, -2), "dist": 88.0, "times": [0.5, 1.3, 2.4], "prop": "plane_crash"})
	t.append({"id": &"impact_ground", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.4, 0), "dist": 8.0, "times": [0.04, 0.15, 0.4]})
	t.append({"id": &"impact_water", "a": Vector3(0, 0.05, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.6, 0), "dist": 12.0, "times": [0.12, 0.4, 1.0], "site": "water"})
	t.append({"id": &"vehicle_dust", "a": Vector3.ZERO, "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 0.5, 0), "dist": 42.0, "times": [0.9, 1.8, 3.0], "prop": "tank_move", "nospawn": true})
	t.append({"id": &"construction_sparks", "a": Vector3(0, 1.2, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 1.0, 0), "dist": 9.0, "times": [0.3, 0.9, 1.8], "prop": "welder"})
	t.append({"id": &"sw_warning_marker", "a": Vector3(0, 0, 0), "b": Vector3(10, 0, 0), "s": 12.0, "look": Vector3(0, 6, 0), "dist": 58.0, "times": [0.5, 5.0, 9.5], "prop": "tanks"})
	t.append({"id": &"sw_orbital_strike", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 8, 0), "dist": 82.0, "times": [0.17, 0.5, 1.3]})
	t.append({"id": &"sw_shockwave", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 2, 0), "dist": 112.0, "times": [0.15, 0.6, 1.7]})
	t.append({"id": &"sw_microwave_dome", "a": Vector3(0, 0, 0), "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 6, 0), "dist": 112.0, "times": [0.4, 1.5, 3.2], "prop": "tanks"})
	return t


# ------------------------------------------------------------------ runs
func _run() -> void:
	var mode: String = "baseline" if _args.has("nofx") else str(_args.get("mode", "sheet"))
	match mode:
		"sheet":
			await _run_sheet()
		"single":
			await _run_single()
		"chaos":
			await _run_chaos()
		"count":
			await _run_count()
		_:
			await _run_baseline()


func _step(dt: float) -> void:
	fx.advance(dt)
	if _mover != null:
		_update_mover()
	if not _swap.is_empty() and fx.now() >= (_swap[2] as float):
		(_swap[0] as Node3D).visible = false
		(_swap[1] as Node3D).visible = true
	if not _collapse.is_empty():
		var k: float = clampf((fx.now() - (_collapse[1] as float)) / 1.3, 0.0, 1.0)
		(_collapse[0] as Node3D).scale.y = lerpf(1.0, 0.12, k * k)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _entry_points(e: Dictionary) -> Array:
	var site: Vector3 = _water_site if str(e.get("site", "")) == "water" else _site
	return [site, _g(e.a as Vector3, site), _g(e.b as Vector3, site) if (e.b as Vector3) != Vector3.ZERO else Vector3.ZERO, _g(e.look as Vector3, site)]


func _capture_entry(e: Dictionary) -> Array[Image]:
	fx.clear_all()
	_clear_props()
	var pts: Array = _entry_points(e)
	var site: Vector3 = pts[0] as Vector3
	_place_camera(pts[3] as Vector3, e.dist as float)
	label.text = String(e.id)
	await _frames(3)
	var t0: float = fx.now()
	_apply_prop(str(e.get("prop", "")), e, site)
	_mover_t0 = t0
	if not e.get("nospawn", false):
		fx.spawn(e.id as StringName, pts[1] as Vector3, pts[2] as Vector3, e.s as float)
	var out: Array[Image] = []
	for tt: Variant in e.times as Array:
		while fx.now() - t0 < float(tt) - 0.0005:
			_step(1.0 / 60.0)
		label.text = "%s   t=%.2fs" % [String(e.id), float(tt)]
		await RenderingServer.frame_post_draw
		out.append(get_viewport().get_texture().get_image())
	return out


func _run_sheet() -> void:
	var table: Array[Dictionary] = _table()
	var idx: int = int(_args.get("sheet", "0"))
	var per: int = int(_args.get("per", "6"))
	var lo: int = idx * per
	var hi: int = mini(lo + per, table.size())
	if lo >= table.size():
		print("FX_SHEET index out of range")
		get_tree().quit(1)
		return
	fx.force = true
	fx.prewarm()
	await _frames(8)
	fx.clear_all()
	fx.force = false
	await _frames(4)
	var sheet: Image = Image.create_empty(3 * CW, (hi - lo) * CH, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.02, 1.0))
	var out: String = str(_args.get("out", "user://fx_sheet_%d.png" % idx))
	for row: int in range(lo, hi):
		var imgs: Array[Image] = await _capture_entry(table[row])
		for c: int in imgs.size():
			var im: Image = imgs[c]
			im.convert(Image.FORMAT_RGBA8)
			if _args.has("full"):
				im.save_png(out.get_base_dir().path_join("full_%s_%d.png" % [String(table[row].id), c]))
			im.resize(CW, CH, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, CW, CH), Vector2i(c * CW, (row - lo) * CH))
	sheet.save_png(out)
	print("FX_SHEET saved ", out, " effects=", hi - lo, " errors=", book.errors().size())
	get_tree().quit(0)


func _run_single() -> void:
	var id: StringName = StringName(str(_args.get("fx", "expl_large")))
	var table: Array[Dictionary] = _table()
	var e: Dictionary = {"id": id, "a": Vector3.ZERO, "b": Vector3.ZERO, "s": 1.0, "look": Vector3(0, 2, 0), "dist": 50.0, "times": [0.5]}
	for row: Dictionary in table:
		if row.id == id:
			e = row.duplicate()
	if _args.has("a"):
		e.a = _vec(str(_args["a"]))
	if _args.has("b"):
		e.b = _vec(str(_args["b"]))
	if _args.has("look"):
		e.look = _vec(str(_args["look"]))
	if _args.has("dist"):
		e.dist = float(_args["dist"])
	if _args.has("s"):
		e.s = float(_args["s"])
	var t_hold: float = float(_args.get("t", str((e.times as Array)[1] if (e.times as Array).size() > 1 else 0.5)))
	fx.force = true
	fx.prewarm()
	await _frames(6)
	fx.clear_all()
	fx.force = false
	var pts: Array = _entry_points(e)
	_place_camera(pts[3] as Vector3, e.dist as float)
	await _frames(2)
	var t0: float = fx.now()
	_apply_prop(str(e.get("prop", "")), e, pts[0] as Vector3)
	_mover_t0 = t0
	if not e.get("nospawn", false):
		fx.spawn(id, pts[1] as Vector3, pts[2] as Vector3, e.s as float)
	while fx.now() - t0 < t_hold - 0.0005:
		_step(1.0 / 60.0)
	label.text = "%s   t=%.2fs" % [String(id), t_hold]
	print("FX_SINGLE ", id, " t=", t_hold, " live=", fx.live_instances())


func _run_baseline() -> void:
	_place_camera(_site + Vector3(0, 1, 0), 70.0, 55.0, 10.0)
	await _frames(30)
	_record = true
	await get_tree().create_timer(float(_args.get("secs", "3"))).timeout
	_record = false
	print("RESULT|baseline|", JSON.stringify(_pack()))
	get_tree().quit(0)


# ------------------------------------------------------------------ performance
static func _summ(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {}
	var a: Array = arr.duplicate()
	a.sort()
	var n: int = a.size()
	var sum: float = 0.0
	for v: Variant in a:
		sum += float(v)
	return {"mean": snappedf(sum / float(n), 0.001), "p50": snappedf(float(a[n / 2]), 0.001), "p95": snappedf(float(a[mini(int(float(n) * 0.95), n - 1)]), 0.001), "p99": snappedf(float(a[mini(int(float(n) * 0.99), n - 1)]), 0.001), "max": snappedf(float(a[n - 1]), 0.001)}


func _pack() -> Dictionary:
	return {"frames": (_samples.dt as Array).size(), "frame_ms": _summ(_samples.dt), "render_cpu_ms": _summ(_samples.cpu), "script_ms": _summ(_samples.proc), "draw_calls": _summ(_samples.draws), "primitives": _summ(_samples.prims)}


func _reset_samples() -> void:
	for k: String in _samples:
		(_samples[k] as Array).clear()


func _rand_ground(margin: float = 0.08) -> Vector3:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var p: Vector2 = Vector2(randf_range(margin, 1.0 - margin) * vp.x, randf_range(0.22, 1.0 - margin) * vp.y)
	var o: Vector3 = cam.project_ray_origin(p)
	var n: Vector3 = cam.project_ray_normal(p)
	if absf(n.y) < 0.01:
		return _site
	var g: Vector3 = o + n * ((_site.y - o.y) / n.y)
	g.y = terrain.height_at(g.x, g.z)
	return g


func _chaos_rates() -> Array:
	return [[&"rifle", 150.0], [&"cannon", 20.0], [&"missile", 6.0], [&"rail", 8.0], [&"artillery", 2.0], [&"thermal", 1.0], [&"hit", 60.0],
		[&"exp_small", 10.0], [&"exp_medium", 6.0], [&"exp_large", 3.0], [&"vehicle", 0.9], [&"building", 0.25], [&"emp", 0.3]]


func _chaos_step(delta: float) -> void:
	var rate_mul: float = float(_args.get("rate", "1"))
	for r: Array in _chaos_rates():
		var key: StringName = r[0] as StringName
		var c: float = float(_carry.get(key, 0.0)) + float(r[1]) * delta * rate_mul
		while c >= 1.0:
			c -= 1.0
			_chaos_spawn(key)
		_carry[key] = c
	for i: int in _dust_units.size():
		var u: Node3D = _dust_units[i]
		u.global_position += _dust_dir[i] * 6.0 * delta
		var p: Vector3 = u.global_position
		p.y = terrain.height_at(p.x, p.z)
		u.global_position = p
		if p.distance_to(_site) > 45.0:
			_dust_dir[i] = (_site - p).normalized()


func _chaos_spawn(key: StringName) -> void:
	var p: Vector3 = _rand_ground()
	var ang: float = randf() * TAU
	var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
	match key:
		&"rifle":
			fx.spawn(&"muzzle_small_arms", p + Vector3(0, 1.3, 0), p + dir * randf_range(10.0, 25.0) + Vector3(0, 0.5, 0), 1.0)
		&"cannon":
			fx.spawn(&"muzzle_cannon", p + Vector3(0, 1.6, 0), p + dir * randf_range(14.0, 30.0), 1.0)
		&"missile":
			fx.spawn(&"muzzle_at_missile", p + Vector3(0, 1.5, 0), p + dir * randf_range(25.0, 45.0), 1.0)
		&"rail":
			fx.spawn(&"muzzle_rail", p + Vector3(0, 2.5, 0), p + dir * randf_range(20.0, 40.0), 1.0)
		&"artillery":
			fx.spawn(&"muzzle_artillery", p + Vector3(0, 1.5, 0), _rand_ground(), 1.0)
		&"thermal":
			fx.spawn(&"muzzle_beam_thermal", p + Vector3(0, 2.5, 0), p + dir * randf_range(18.0, 30.0), 1.0)
		&"hit":
			fx.spawn(&"hit_infantry", p + Vector3(0, 1.0, 0), Vector3.ZERO, 1.0)
		&"exp_small":
			fx.spawn(&"expl_small", p)
		&"exp_medium":
			fx.spawn(&"expl_medium", p)
		&"exp_large":
			fx.spawn(&"expl_large", p)
		&"vehicle":
			fx.spawn(&"vehicle_destroy", p)
		&"building":
			fx.spawn(&"building_collapse", p)
		&"emp":
			fx.spawn(&"emp_pulse", p, Vector3.ZERO, 10.0)


func _run_chaos() -> void:
	_place_camera(_site, 70.0, 55.0, 10.0)
	fx.force = true
	fx.prewarm()
	await _frames(8)
	fx.clear_all()
	fx.force = false
	for i: int in 20:
		var u: Node3D = _make_tank(Color(0.3, 0.34, 0.22))
		add_child(u)
		u.global_position = _rand_ground(0.2)
		_dust_units.append(u)
		_dust_dir.append(Vector3(cos(float(i) * 1.7), 0.0, sin(float(i) * 1.7)))
		fx.start_stamper(&"vehicle_dust", u, 1.6, 1000.0, 1.0)
	await _frames(30)
	var secs: float = float(_args.get("secs", "15"))
	_reset_samples()
	fx.reset_stats()
	_record = true
	await get_tree().create_timer(3.0).timeout
	_record = false
	var base: Dictionary = _pack()
	_chaos_on = true
	_reset_samples()
	fx.reset_stats()
	_record = true
	await get_tree().create_timer(secs).timeout
	_record = false
	_chaos_on = false
	var res: Dictionary = {
		"renderer": String(RenderingServer.get_current_rendering_method()), "viewport": get_viewport().get_visible_rect().size,
		"quality": int(fx.quality), "secs": secs, "rate_mul": float(_args.get("rate", "1")), "baseline": base, "chaos": _pack(),
		"fx_stats": fx.get_stats(),
	}
	print("RESULT|chaos|", JSON.stringify(res))
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(str(_args.get("out", "user://fx_chaos.png")))
	get_tree().quit(0)


func _run_count() -> void:
	var n: int = int(_args.get("n", "60"))
	_place_camera(_site, 60.0, 55.0, 10.0)
	fx.force = true
	fx.prewarm()
	await _frames(8)
	fx.clear_all()
	fx.force = false
	await _frames(20)
	_reset_samples()
	_record = true
	await get_tree().create_timer(3.0).timeout
	_record = false
	var base: Dictionary = _pack()
	# n simultaneous composites of mixed weight, refreshed every 2 s so that n are always alive
	var ids: Array[StringName] = [&"expl_medium", &"expl_small", &"muzzle_cannon", &"vehicle_destroy", &"muzzle_at_missile", &"emp_pulse"]
	fx.force = true
	_reset_samples()
	fx.reset_stats()
	_record = true
	var t_end: float = float(Time.get_ticks_msec()) / 1000.0 + float(_args.get("secs", "8"))
	var next: float = 0.0
	while float(Time.get_ticks_msec()) / 1000.0 < t_end:
		if float(Time.get_ticks_msec()) / 1000.0 >= next:
			next = float(Time.get_ticks_msec()) / 1000.0 + 2.0
			for i: int in n:
				var p: Vector3 = _rand_ground()
				var id: StringName = ids[i % ids.size()]
				fx.spawn(id, p + Vector3(0, 1.0, 0), p + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)), 10.0 if id == &"emp_pulse" else 1.0)
		await get_tree().process_frame
	_record = false
	fx.force = false
	var res: Dictionary = {"renderer": String(RenderingServer.get_current_rendering_method()), "n": n, "baseline": base, "count": _pack(), "fx_stats": fx.get_stats(),
		"live": fx.live_instances()}
	print("RESULT|count|", JSON.stringify(res))
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(str(_args.get("out", "user://fx_count.png")))
	get_tree().quit(0)


func _vec(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
