extends "res://tests/visual/terrain_lab.gd"
## VIEW-W1/W4/O1 integrated acceptance: a REAL SimWorld (real GameData, generated map, real movement / orders / combat) with two
## small NAPC / NEC armies rendered through ViewWorld with interpolation on the generated terrain. Units carry the proof
## archetypes until faction recipes land; structures show recipe placeholders.
##   tools/gd shot res://tests/visual/vw_battle.tscn out.png --size 1920x1080 -- --tick=100 --view=fight
## Args (besides terrain_lab's --seed/--size/--biome/--yaw/--zoom): --tick=N (sim ticks to run before the frame), --n=units per
## side, --view=fight|hq|wide, --sel=N (own units selected), --alpha=0..1, --observer, --fog.

const C: int = SimConfig.CELL

var sim: SimWorld = null
var vw: ViewWorld = null
var army_a: PackedInt32Array = PackedInt32Array()
var army_b: PackedInt32Array = PackedInt32Array()
var _alpha: float = 0.5
var _meet: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_build_sim()
	_build_view()
	_place_structures()
	var target: int = int(_args.get("tick", "0"))
	_alpha = float(_args.get("alpha", "0.5"))
	_run_to(target)
	_select()
	_frame_camera()
	print("VW_BATTLE tick=", sim.tick, " entities=", vw.entity_count(), " stats=", vw.stats()["ms"])


func _build_sim() -> void:
	var d: GameData = GameData.load_default()
	for s: DefStructure in d.structures:
		map.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	var rosters: PackedStringArray = PackedStringArray(["roster.napc.vanilla", "roster.nec.vanilla"])
	for i: int in 2:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": rosters[i], "team": i + 1, "color": [1, 0][i], "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "vw_lab"}, "rules": {"victory": 0, "fog": 1 if _args.has("fog") else 0}, "players": pl})
	sim = SimWorld.create(d, cfg, map)
	var s0: int = map.spawns[1]
	var s1: int = map.spawns[MapData.SPAWN_STRIDE + 1]
	var p0: Vector2 = Vector2(float(s0 % map.w), float(s0 / map.w))
	var p1: Vector2 = Vector2(float(s1 % map.w), float(s1 / map.w))
	_meet = (p0 + p1) * 0.5
	var n: int = int(_args.get("n", "6"))
	army_a = _army(0, _meet + Vector2(-7.0, 0.0), n)
	army_b = _army(1, _meet + Vector2(7.0, 0.0), n)
	sim.submit_raw(0, SimCmd.attack_move(army_a, int((_meet.x + 12.0) * C), int(_meet.y * C)))
	sim.submit_raw(1, SimCmd.attack_move(army_b, int((_meet.x - 12.0) * C), int(_meet.y * C)))


## One Barracks per side next to the armies (SPAWNED reason PLACED: the build-up plays in the first 30 ticks).
func _place_structures() -> void:
	var idx: int = sim.data.structure_idx("structure.shared.barracks")
	if idx < 0:
		return
	for pid: int in 2:
		var at: Vector2 = _meet + Vector2(-8.0 if pid == 0 else 8.0, -9.0)
		var e: SimEntity = sim.spawn_structure(idx, pid, int(at.x) * C + C, int(at.y) * C + C, 0, 0, 500, 0, SimEvent.SPAWN_PLACED)
		if e != null:
			(army_a if pid == 0 else army_b).append(e.id)


## n vehicles (two types) and n squads of the roster's armed units around `at`.
func _army(pid: int, at: Vector2, n: int) -> PackedInt32Array:
	var p: SimPlayer = sim.players[pid]
	var veh: Array[int] = []
	var inf: Array[int] = []
	for ui: int in p.roster.producible_units:
		var u: DefUnit = sim.data.units[ui]
		if u.weapons.is_empty():
			continue
		if u.move_class == DefEnums.MoveClass.FOOT:
			inf.append(ui)
		elif u.move_class == DefEnums.MoveClass.TRACKED or u.move_class == DefEnums.MoveClass.WHEELED:
			veh.append(ui)
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var pool: Array[int] = veh if i % 2 == 0 else inf
		if pool.is_empty():
			continue
		var ui2: int = pool[(i / 2) % pool.size()]
		var cell: int = int(at.y + float(i % 4) * 3.0 - 4.0) * map.w + int(at.x + float(i / 4) * (-3.0 if pid == 0 else 3.0))
		var free: int = SimMovement.find_free_cell_near(sim, cell, SimEntity.Layer.GROUND, 8)
		if free < 0:
			continue
		var x: int = (free % map.w) * C + C / 2
		var y: int = (free / map.w) * C + C / 2
		var e: SimEntity = sim.spawn_unit(ui2, pid, x, y, 0 if pid == 0 else 2048, 0, 500, 0, SimEvent.SPAWN_INITIAL)
		if e != null:
			out.append(e.id)
	return out


func _build_view() -> void:
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	vw = ViewWorld.create(q)
	vw.terrain = terrain
	vw.camera = cam
	vw.drive_camera = false
	add_child(vw)
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.build_terrain = false
	opts.create_camera = false
	opts.screenshot_mode = true
	opts.prewarm_scope = 0
	vw.build_sync(sim, -1 if _args.has("observer") else 0, opts)


func _run_to(target: int) -> void:
	for i: int in target:
		sim.step()
		vw.frame(1.0 / 60.0, 1.0, sim.events.take())
	vw.frame(1.0 / 60.0, _alpha, sim.events.take())


func _select() -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var want: int = int(_args.get("sel", "5"))
	if _args.has("selstruct"):
		for e: SimEntity in sim.structures_of(0):
			ids.append(e.id)
	for id: int in army_a:
		if ids.size() >= want:
			break
		if vw.has_entity(id) and not vw.entity_view(id).dead:
			ids.append(id)
	vw.selection.set_selection(ids)
	if not army_b.is_empty() and vw.has_entity(army_b[0]):
		vw.selection.set_hover(army_b[0])


func _frame_camera() -> void:
	var view: String = str(_args.get("view", "fight"))
	var focus: Vector2 = _meet
	if view == "fight" and not _args.has("focus"):
		var sum: Vector2 = Vector2.ZERO
		var n: int = 0
		for id: int in army_a + army_b:
			var e: SimEntity = sim.get_entity(id)
			if e != null and (e.flags & SimFlags.F_GONE) == 0:
				sum += Vector2(float(e.x), float(e.y)) / float(C)
				n += 1
		if n > 0:
			focus = sum / float(n)
	var zoom: float = float(_args.get("zoom", "0.12"))
	if view == "hq":
		var s0: int = map.spawns[1]
		focus = Vector2(float(s0 % map.w), float(s0 / map.w) + 3.0)
		zoom = float(_args.get("zoom", "0.2"))
	elif view == "wide":
		zoom = float(_args.get("zoom", "0.6"))
	if _args.has("focus"):
		var p: PackedStringArray = str(_args["focus"]).split(",")
		focus = Vector2(float(p[0]), float(p[1]))
	cam.snap_to(focus * ViewConsts.CELL_M, float(_args.get("yaw", "0")), zoom)
	cam.advance(0.0)
	_fit_shadows()


var _bench_frames: int = 0
var _bench_sum: float = 0.0
var _bench_worst: float = 0.0


## --bench=N: N frames with a real renderer, the sim advancing one tick every third frame; prints the script cost and quits.
func _process(delta: float) -> void:
	if vw == null:
		return
	if _args.has("bench"):
		var total: int = int(_args["bench"])
		if _bench_frames % 3 == 0:
			sim.step()
		var a: float = float(_bench_frames % 3) / 3.0
		vw.frame(delta, a, sim.events.take())
		if _bench_frames >= 30:
			var ms: float = (vw.stats()["ms"] as Dictionary)["total"] as float
			_bench_sum += ms
			_bench_worst = maxf(_bench_worst, ms)
		_bench_frames += 1
		if _bench_frames >= total + 30:
			print("VW_BENCH entities=", vw.entity_count(), " avg_ms=", _bench_sum / float(total), " worst_ms=", _bench_worst, " draws=", vw.stats()["draws"])
			get_tree().quit()
		return
	vw.frame(delta, _alpha, PackedInt32Array())

