class_name AppShowcase
extends Node3D
## The main-menu 3D backdrop (ui.md 5.1.3): a small generated map with a handful of the featured faction's units, seen through
## the real view (`AppViewStage`: terrain, atmosphere, water, decor, unit models) from a slowly orbiting camera. The map comes
## from `MapGenJob` on its worker thread, the world and the view are then built synchronously in one frame (the menu hides
## the hitch behind its fade). Static tableau: the sim never steps. `ready_to_show` fires after that frame.

signal ready_to_show()

const SIZE_CELLS: int = 96
const ORBIT_DEG_S: float = 2.2
const ZOOM: float = 0.09
const SEED: int = 4711
## Degrees added to the rig's pitch: negative = a lower, more cinematic angle.
const PITCH_BIAS: float = -16.0

var stage: AppViewStage = null
var world: SimWorld = null
var is_ready: bool = false
var yaw_deg: float = 28.0

var _data: GameData = null
var _faction: String = ""
var _job: MapGenJob = null
var _map: MapData = null
var _focus_m: Vector2 = Vector2.ZERO
var _t: float = 0.0


## Starts building for the faction `code` ("napc"). Polls in `_process`.
func begin(data: GameData, faction_code: String) -> void:
	_data = data
	_faction = faction_code.to_lower()
	var family: int = 2 if _faction in ["pd", "sap"] else 0
	var biome: int = 1
	_job = MapGenJob.begin({"family": family, "size": SIZE_CELLS, "seed": SEED + _faction.hash() % 97, "layout_players": 2,
		"params": {"biome": biome}}, null, true)


func _exit_tree() -> void:
	if _job != null:
		_job.cancel()  # joins the generator thread before the node (and the quit) goes on
		_job = null


func _process(delta: float) -> void:
	if is_ready:
		_t += delta
		yaw_deg += ORBIT_DEG_S * delta
		_place_camera()
		stage.frame(delta, 1.0, PackedInt32Array())
		return
	if _job == null:
		return
	if not _job.step(0):
		return
	_map = _job.result()
	_job = null
	if _map == null:
		Log.warn("ui", "showcase: map generation failed")
		return
	_build()


func _build() -> void:
	var r_main: DefRoster = _data.roster_for(_faction.to_upper(), "")
	var rivals: PackedStringArray = ["NEC", "DEF", "HAN", "OLM"]
	var r_rival: DefRoster = _data.roster_for(rivals[(_faction.hash() & 0xFF) % rivals.size()] if _faction.to_upper() != "NEC" else "DEF", "")
	if r_main == null or r_rival == null:
		return
	var players: Array = []
	for i: int in 2:
		var r: DefRoster = r_main if i == 0 else r_rival
		players.append({"pid": i, "kind": "ai", "name": "Showcase %d" % i, "roster": r.id, "team": i + 1, "color": [1, 0][i], "start": i,
			"handicap": 100, "ai": {"level": 0, "style": 0, "flags": 0}})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": 11, "map": {"family": _map.family}, "rules": {"start_mode": SimMatchRules.START_NONE,
		"fog": false, "victory": 0, "start_credits": 0, "neutral_structures": 0}, "players": players})
	world = SimMatchSetup.create_world(_data, cfg, _map)
	if world == null:
		return
	_place_units(r_main, r_rival)
	stage = AppViewStage.new()
	stage.with_fx = false
	stage.name = "ShowcaseStage"
	stage.mood_id = &"arid_dusk"
	add_child(stage)
	stage.build_sync(world, -1, AppViewStage.make_quality())
	if stage.view.camera != null:
		stage.view.camera.edge_scroll_enabled = false
		stage.view.camera.auto_input = false
	stage.view.drive_camera = false
	is_ready = true
	_place_camera()
	world.events.clear()
	ready_to_show.emit()


## A loose formation of the featured roster's armed units in front of its start, a few rival units further out.
func _place_units(r_main: DefRoster, r_rival: DefRoster) -> void:
	var cell0: int = _map.spawns[1]
	var cell1: int = _map.spawns[MapData.SPAWN_STRIDE + 1]
	var p0: Vector2 = Vector2(float(cell0 % _map.w), float(cell0 / _map.w))
	var p1: Vector2 = Vector2(float(cell1 % _map.w), float(cell1 / _map.w))
	var dir: Vector2 = (p1 - p0).normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var centre: Vector2 = p0 + dir * 12.0
	_focus_m = centre * ViewConsts.CELL_M
	var picks: Array[int] = _armed_units(r_main)
	var slots: Array[Vector2] = [Vector2(0, 0), Vector2(-3.2, 2.8), Vector2(3.2, 2.8), Vector2(-6.0, 6.0), Vector2(6.2, 6.0), Vector2(0.0, 5.6),
		Vector2(-2.6, 9.0), Vector2(2.8, 9.0)]
	for i: int in slots.size():
		if picks.is_empty():
			break
		var at: Vector2 = centre + side * slots[i].x - dir * slots[i].y
		_spawn(picks[i % picks.size()], 0, at, dir)
	var rival_picks: Array[int] = _armed_units(r_rival)
	for i: int in mini(3, rival_picks.size()):
		_spawn(rival_picks[i], 1, centre + dir * (14.0 + float(i) * 3.5) + side * (float(i) - 1.0) * 4.0, -dir)


func _armed_units(r: DefRoster) -> Array[int]:
	var veh: Array[int] = []
	var inf: Array[int] = []
	for ui: int in r.producible_units:
		var u: DefUnit = r.units[ui]
		if u == null or u.weapons.is_empty():
			continue
		if u.move_class == DefEnums.MoveClass.FOOT:
			inf.append(ui)
		elif u.move_class == DefEnums.MoveClass.TRACKED or u.move_class == DefEnums.MoveClass.WHEELED:
			veh.append(ui)
	var out: Array[int] = []
	for i: int in maxi(veh.size(), inf.size()):
		if i < veh.size():
			out.append(veh[i])
		if i < inf.size():
			out.append(inf[i])
	return out


func _spawn(def_idx: int, pid: int, at_cells: Vector2, face: Vector2) -> void:
	var cell: int = SimMovement.find_free_cell_near(world, int(at_cells.y) * _map.w + int(at_cells.x), SimEntity.Layer.GROUND, 8)
	if cell < 0:
		return
	var facing: int = posmod(roundi(atan2(face.y, face.x) * 4096.0 / TAU), 4096)
	world.spawn_unit(def_idx, pid, (cell % _map.w) * SimConfig.CELL + SimConfig.CELL / 2, (cell / _map.w) * SimConfig.CELL + SimConfig.CELL / 2,
		facing, 0, 500, 0, SimEvent.SPAWN_INITIAL)


## The orbit: the subject sits right of centre (the menu column is on the left), so the focus is shifted along the camera's left.
func _place_camera() -> void:
	var cam: ViewCamera = stage.view.camera
	if cam == null:
		return
	var yaw: float = deg_to_rad(yaw_deg)
	var right: Vector2 = Vector2(cos(yaw), -sin(yaw))
	cam.snap_to(_focus_m - right * 5.0, yaw_deg, ZOOM, PITCH_BIAS)
	cam.advance(0.0)
