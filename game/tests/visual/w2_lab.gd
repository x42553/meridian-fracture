extends "res://tests/visual/terrain_lab.gd"
## VIEW-W2 / VIEW-O3 acceptance lab: a REAL SimWorld (real GameData, generated map, four factions) rendered through ViewWorld with an
## FxManager bound to the FX port. One scenario per screenshot; the sim is stepped in 20 Hz ticks with three rendered frames per tick so
## every dt-based animation runs at real speed and the capture is deterministic.
##   tools/gd shot res://tests/visual/w2_lab.tscn out.png --size 1920x1080 -- --players=4 --scene=buildup [--tick=N] [--zoom=Z] [--yaw=D]
## Scenes: buildup (5 stages x 3 factions), sell, damage (hp stages), destroyed (--tick after the kill), wrecks (--tick after the kill),
##   ghost (fogged remembered structure), zones (every zone type), warn (Atlas, Helios, Horizon, Perun), marks (status marks), power
##   (low power dimming), idle (activity: door, unload arm, radar)

const C: int = SimConfig.CELL
const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla", "roster.def.vanilla", "roster.ae.vanilla"]

var sim: SimWorld = null
var vw: ViewWorld = null
var fx: FxManager = null
var stage: Vector2 = Vector2(96, 96)  ## cell coordinates of the stage centre
var ids: Dictionary = {}  ## name -> entity id
var _scene: String = "buildup"
var _frozen: bool = false


func _ready() -> void:
	super._ready()
	_scene = str(_args.get("scene", "buildup"))
	_build_sim()
	_build_view()
	stage = _flat_spot()
	print("W2_LAB scene=", _scene, " stage=", stage)
	_look(stage, 0.2)  # the camera must be in place before FX are spawned (the FX manager culls by distance)
	call("_scene_" + _scene)
	_freeze()


func _freeze() -> void:
	_frozen = true
	if fx != null:
		fx.set_process(false)


func _process(_dt: float) -> void:
	pass


# ---- world -----------------------------------------------------------------------------------------------------------

func _build_sim() -> void:
	var d: GameData = GameData.load_default()
	for s: DefStructure in d.structures:
		map.set_footprint(SimEntity.Kind.STRUCTURE, s.index, MapFootprint.new(s.fp_w, s.fp_h, s.fp_mask, (s.place_mask & DefEnums.PLACE_SHORELINE) != 0))
	var pl: Array = []
	var n: int = mini(int(_args.get("players", "4")), 4)
	for i: int in n:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": ROSTERS[i], "team": i + 1, "color": i, "start": i, "handicap": 100})
	if _args.has("ally"):
		pl[1]["team"] = 1
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 7, "map": {"id": "w2_lab"}, "rules": {"victory": 0, "fog": 1 if _args.has("fog") else 0}, "players": pl})
	sim = SimWorld.create(d, cfg, map)


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
	opts.screenshot_mode = false
	opts.prewarm_scope = 0
	vw.build_sync(sim, -1 if _args.has("observer") else 0, opts)
	if not _args.has("nofx"):
		var book: FxRecipeBook = FxRecipeBook.new()
		book.load_file()
		fx = FxManager.new()
		fx.name = "Fx"
		add_child(fx)
		fx.setup(cam.camera, FxManager.Quality.HIGH, book, terrain, null)
		vw.fx.bind(fx)
	ViewGlobals.screenshot_mode = false


## The flattest 40 x 40 cell patch within 45 cells of the map centre (structures need level ground).
func _flat_spot() -> Vector2:
	var best: Vector2 = Vector2(float(map.w) * 0.5, float(map.h) * 0.5)
	var best_v: float = 1.0e9
	for gx: int in range(-45, 46, 9):
		for gz: int in range(-45, 46, 9):
			var cx: float = float(map.w) * 0.5 + float(gx)
			var cz: float = float(map.h) * 0.5 + float(gz)
			var lo: float = 1.0e9
			var hi: float = -1.0e9
			for ox: int in range(-20, 21, 5):
				for oz: int in range(-20, 21, 5):
					var h: float = terrain.height_at((cx + float(ox)) * 3.0, (cz + float(oz)) * 3.0)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					if terrain.is_water_at((cx + float(ox)) * 3.0, (cz + float(oz)) * 3.0):
						hi += 50.0
			if hi - lo < best_v:
				best_v = hi - lo
				best = Vector2(cx, cz)
	return best


func _idx(id: String) -> int:
	return sim.data.structure_idx(id)


## Structure with its top-left cell at (cx, cy) relative to the stage centre.
func _place(id: String, pid: int, dx: int, dy: int, reason: int = SimEvent.SPAWN_INITIAL, flags: int = 0) -> SimEntity:
	var idx: int = _idx(id)
	var s: DefStructure = sim.data.structures[idx]
	var cx: int = int(stage.x) + dx
	var cy: int = int(stage.y) + dy
	var x: int = cx * C + s.fp_w * C / 2
	var y: int = cy * C + s.fp_h * C / 2
	var e: SimEntity = sim.spawn_structure(idx, pid, x, y, 0, flags, 500, 0, reason)
	if e == null:
		push_error("w2_lab: could not place %s" % id)
	return e


func _unit(pid: int, foot: bool) -> int:
	for ui: int in sim.players[pid].roster.producible_units:
		var u: DefUnit = sim.data.units[ui]
		if u.weapons.is_empty():
			continue
		if foot and u.move_class == DefEnums.MoveClass.FOOT:
			return ui
		if not foot and (u.move_class == DefEnums.MoveClass.TRACKED or u.move_class == DefEnums.MoveClass.WHEELED):
			return ui
	return -1


func _spawn_unit(pid: int, foot: bool, dx: float, dy: float) -> SimEntity:
	var ui: int = _unit(pid, foot)
	var x: int = int((stage.x + dx) * float(C))
	var y: int = int((stage.y + dy) * float(C))
	return sim.spawn_unit(ui, pid, x, y, 0, 0, 500, 0, SimEvent.SPAWN_INITIAL)


## One sim tick with three rendered frames.
func _tick(n: int = 1) -> void:
	for i: int in n:
		sim.step()
		var ev: PackedInt32Array = sim.events.take()
		for k: int in 3:
			vw.frame(1.0 / 60.0, float(k + 1) / 3.0, ev if k == 0 else PackedInt32Array())
			if fx != null:
				fx.advance(1.0 / 60.0)


func _look(focus_cells: Vector2, zoom: float, yaw: float = 0.0, bias: float = 0.0) -> void:
	var z: float = float(_args.get("zoom", str(zoom)))
	var yw: float = float(_args.get("yaw", str(yaw)))
	cam.snap_to(focus_cells * ViewConsts.CELL_M, yw, z, bias)
	cam.advance(0.0)
	_fit_shadows()
	print("W2_LAB cam zoom=", z, " height=", cam.current_height(), " focus=", cam.current_focus())
	if fx != null:
		fx.sync_camera()
	vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())


func _after(default_ticks: int) -> int:
	return int(_args.get("tick", str(default_ticks)))


# ---- scenes ----------------------------------------------------------------------------------------------------------

## Build-up sequence: the Factory of three factions at five stages of the rise (spawned 27 / 21 / 15 / 9 / 3 ticks before the capture).
func _scene_buildup() -> void:
	var spawn_at: Array[int] = [27, 21, 15, 9, 3]
	var total: int = spawn_at[0]
	var kit: String = str(_args.get("def", "structure.shared.factory"))
	for step_i: int in total + 1:
		for k: int in spawn_at.size():
			if spawn_at[k] == total - step_i and (not _args.has("k") or int(_args.get("k")) == k):
				for pid: int in mini(sim.players.size(), 3):
					_place(kit, pid, -10 + k * 5, -8 + pid * 5, SimEvent.SPAWN_PLACED, SimFlags.F_UNDER_CONSTRUCTION)
		_tick()
	_look(stage + Vector2(2.0, -4.0) if not _args.has("k") else stage + Vector2(-10.0 + float(int(_args.get("k"))) * 5.0 + 1.5, -5.0), 0.22, float(_args.get("yaw", "0")))


func _scene_sell() -> void:
	var e: SimEntity = _place("structure.shared.factory", 0, -4, -4)
	_tick(4)
	sim.emit(SimEconConst.EVT_STRUCTURE_SELLING, e.x, e.y, 0, e.id, sim.tick + 40)
	_tick(_after(20))
	_look(stage, 0.16)


## hp stages: 100 / 70 / 50 / 30 / 12 percent of the same building.
func _scene_damage() -> void:
	var fracs: Array[float] = [1.0, 0.70, 0.5, 0.3, 0.12]
	for k: int in fracs.size():
		var e: SimEntity = _place(str(_args.get("def", "structure.shared.factory")), 0, -10 + k * 5, -4)
		e.hp = int(float(e.hp_max) * fracs[k])
	_tick(_after(60))
	_look(stage + Vector2(2.0, -1.0), 0.3, float(_args.get("yaw", "0")))


func _scene_destroyed() -> void:
	var a: SimEntity = _place("structure.shared.factory", 0, -14, -6)
	var b: SimEntity = _place("structure.shared.generator", 1, -3, -4)
	var c: SimEntity = _place("structure.shared.headquarters", 2, 5, -6)
	_tick(6)
	for e: SimEntity in [a, b, c]:
		sim.kill(e, SimCombatConsts.CAUSE_DAMAGE, 0, 3)
	_tick(_after(10))
	for e2: SimEntity in [a, b, c]:
		var ve: ViewEntity = vw.entity_view(e2.id)
		print("W2_LAB destroyed sink=", (ve as ViewStructure).sink_m if ve != null else -1.0, " h=", ve.height_m if ve != null else 0.0, " wy=", ve.wy if ve != null else 0.0, " id=", e2.id, " view=", ve != null, " dead=", ve.dead if ve != null else false, " kind=", ve.dying_kind if ve != null else -1, " until=", ve.dying_until_tick if ve != null else -1, " tick=", sim.tick)
	if fx != null:
		print("W2_LAB fxstats=", fx.get_stats(), " live=", fx.live_instances())
	print("W2_LAB fx calls=", vw.fx.stat_calls, " fwd=", vw.fx.stat_forwarded, " missing=", vw.fx.missing_ids(), " heaps=", vw.rubble.heap_count())
	_look(stage + Vector2(-1.0, -2.0), 0.22, float(_args.get("yaw", "0")))


func _scene_wrecks() -> void:
	var victims: Array[SimEntity] = []
	for k: int in 6:
		var pid: int = k % 3
		var u: SimEntity = _spawn_unit(pid, k >= 4, -12.0 + float(k) * 5.0, 0.0)
		if u != null:
			victims.append(u)
	_tick(4)
	for u2: SimEntity in victims:
		sim.kill(u2, SimCombatConsts.CAUSE_DAMAGE, 0, 3)
	_tick(_after(20))
	var nw: int = 0
	for ve: ViewEntity in vw.entities():
		if ve.kind == SimEntity.Kind.WRECK:
			nw += 1
	print("W2_LAB wrecks sim=", sim.wrecks.size(), " view=", nw, " victims=", victims.size(), " salvage=", sim.combat.salvage_enabled)
	_look(stage, 0.1, float(_args.get("yaw", "0")))


func _scene_ghost() -> void:
	# local player 0 has a scout next to an enemy factory; then the scout leaves and the factory stays remembered
	var enemy: SimEntity = _place("structure.shared.factory", 1, 0, -4)
	var enemy2: SimEntity = _place("structure.shared.radar", 1, 8, -4)
	enemy2.hp = int(float(enemy2.hp_max) * 0.45)
	var scout: SimEntity = _spawn_unit(0, false, -6.0, 0.0)
	_tick(12)
	ids["enemy"] = enemy.id
	sim.remove_entity(scout.id, SimEvent.REM_SCRIPT)
	_tick(_after(40))
	print("W2_LAB ghosts=", vw.ghosts.count, " ids=", vw.ghosts.ids(), " enemy_vs=", vw.entity_view(enemy.id).vs)
	_look(stage + Vector2(4.0, 0.0), 0.16, float(_args.get("yaw", "0")))


func _scene_zones() -> void:
	var sets: Dictionary = {
		"a": ["zone.smoke_dust_screen", "zone.repair_station", "zone.sensor_puck"],
		"b": ["zone.infantry_shelter", "zone.portable_cover", "zone.horizon_debris"],
		"c": ["zone.decoy_tank", "zone.trident_interception", "zone.repair_station"],
	}
	var names: Array = sets[str(_args.get("set", "a"))] as Array
	var col: int = 0
	for nm: String in names:
		var zi: int = sim.data.zone_idx(nm)
		var px: int = int((stage.x - 13.0 + float(col) * 13.0) * float(C))
		var py: int = int((stage.y + 0.0) * float(C))
		var zid: int = sim.zones.create_zone(zi, 0, px, py, 0, sim.tick + 20 * 60)
		print("W2_LAB zone ", nm, " -> ", zid)
		col += 1
	_tick(_after(24))
	_look(stage + Vector2(0.0, 2.0), 1.0, float(_args.get("yaw", "0")))


func _scene_warn() -> void:
	var sets: Dictionary = {
		"a": ["superweapon.napc.atlas_kinetic_array", "superweapon.olm.helios_reflector"],
		"b": ["superweapon.ae.horizon_mass_driver", "superweapon.def.perun_missile_complex"],
		"c": ["superweapon.pd.tempest_swarm_hub", "superweapon.nec.aurora_microwave_array"],
	}
	var col: int = 0
	for id: String in sets[str(_args.get("set", "a"))] as Array:
		var si: int = sim.data.superweapon_idx(id)
		if si < 0:
			print("W2_LAB missing superweapon ", id)
			continue
		var sw: DefSuperweapon = sim.data.superweapons[si]
		var tx: int = int((stage.x - 11.0 + float(col) * 22.0) * float(C))
		var ty: int = int((stage.y + 0.0) * float(C))
		var geom: PackedInt32Array = SimSuperweapons.geometry(sw, tx, ty, int(_args.get("angle", "300")), tx - 8 * C, ty)
		# player 1 fires: the local player 0 is hostile-affected (needs an entity of the local player near the zone)
		var w: SimWarning = sim.strategic.add_warning(sim, SimEconConst.WK_SUPER, si, 1 if not _args.has("own") else 0, 0, geom, sw.warning_t, SimSuperweapons.exec_span(sw))
		w.affected_mask |= 1
		_spawn_unit(0, true, float(tx) / float(C) - stage.x + 1.0, float(ty) / float(C) - stage.y + 1.0)  # the local player must own something inside the zone
		print("W2_LAB warning ", id, " geom=", geom, " exec=", w.exec_tick)
		col += 1
	_tick(_after(60))
	if _args.has("exec"):
		for w2: SimWarning in sim.strategic.warnings:
			w2.phase = SimEconConst.AT_EXEC
			w2.exec_tick = sim.tick - int(_args.get("exec"))
	_tick(2)
	for wid: int in vw.warnings.warning_ids():
		var rec: ViewWarnings.Rec = vw.warnings.rec_of(wid)
		print("W2_LAB rec ", wid, " prims=", rec.prims.size(), " fade=", rec.fade, " dying=", rec.dying, " label=", rec.label.text)
		for p: ViewWarnings.Prim in rec.prims:
			print("W2_LAB   prim mode=", p.mode, " c=", p.center, " hl=", p.hl, " r=", p.r, " vis=", p.node.visible, " verts=", (p.node.mesh as ArrayMesh).surface_get_array_len(0))
	_look(stage + Vector2(0.0, 2.0), 1.0, float(_args.get("yaw", "0")))


func _scene_marks() -> void:
	var emp: SimEntity = _spawn_unit(0, false, -8.0, 0.0)
	var sup: SimEntity = _spawn_unit(0, true, -4.0, 0.0)
	var clo: SimEntity = _spawn_unit(0, false, 0.0, 0.0)
	var emp_s: SimEntity = _place("structure.shared.radar", 0, 4, -3)
	var noP: SimEntity = _place("structure.shared.anti_tank_turret", 0, 10, -3)
	var cap: SimEntity = _place("structure.shared.watchtower", 1, 14, -3)
	_tick(6)
	emp.flags |= SimFlags.F_EMP_SHUT
	sup.flags |= SimFlags.F_SUPPRESSED
	clo.flags |= SimFlags.F_CLOAKED
	emp_s.flags |= SimFlags.F_EMP_SHUT
	noP.flags &= ~SimFlags.F_POWERED
	if cap.econ != null:
		cap.econ.cap_progress = 620
		cap.econ.cap_pid = 0
	_tick(_after(16))
	_look(stage + Vector2(3.0, 0.0), 0.06, float(_args.get("yaw", "0")))


func _scene_power() -> void:
	var a: SimEntity = _place("structure.shared.laboratory", 0, -14, -4)
	var b: SimEntity = _place("structure.shared.factory", 0, -4, -4)
	var c: SimEntity = _place("structure.shared.radar", 0, 6, -4)
	_tick(30)
	ids["a"] = a.id
	if _args.has("night"):
		ViewGlobals.set_value(ViewGlobals.G_ATM_NIGHT, 1.0)
	for e: SimEntity in [b, c]:  # the laboratory keeps its power: left = powered, middle and right = dark
		e.flags &= ~SimFlags.F_POWERED
	_tick(_after(20))
	_look(stage + Vector2(-2.0, 0.0), 0.2, float(_args.get("yaw", "0")))


func _scene_idle() -> void:
	_place("structure.shared.refinery", 0, -14, -4)
	_place("structure.shared.radar", 0, -4, -4)
	_place("structure.shared.generator", 0, 4, -4)
	_place("structure.shared.headquarters", 0, 12, -5)
	_tick(_after(40))
	_look(stage + Vector2(-1.0, 0.0), 0.2, float(_args.get("yaw", "0")))


## Floating numbers: income at a refinery, a sale, repair gains on a damaged structure.
func _scene_float() -> void:
	var ref: SimEntity = _place("structure.shared.refinery", 0, -8, -4)
	var hq: SimEntity = _place("structure.shared.headquarters", 0, 2, -5)
	hq.hp = hq.hp_max / 2
	_tick(6)
	sim.emit(SimEconConst.EVT_CREDITS_GAINED, ref.x, ref.y, 0, 1250, ref.x, ref.y)
	sim.emit(SimEconConst.EVT_STRUCTURE_SOLD, hq.x, hq.y, 0, hq.id, 900)
	for i: int in 6:
		_tick(1)
		hq.hp += hq.hp_max / 40
	_tick(_after(14))
	_look(stage + Vector2(-2.0, -2.0), 0.1, float(_args.get("yaw", "0")))
