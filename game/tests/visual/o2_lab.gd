extends Node
## VIEW-O2 / M9 live lab: runs the REAL game (boot.tscn: session, view stage, HUD, presenter, view adapter) and drives it through the
## same public paths the player uses, so the screenshot shows what a match shows.
##   tools/gd shot res://tests/visual/o2_lab.tscn out.png --size 1920x1080 --frames 900 -- --autostart=match --with-ui --bots --fresh-settings
##     --no-audio --speed=0 --lab=group|place_ok|place_bad|place_far|cards [--tab=N] [--dx=6 --dy=0] [--map-seed=S]
## group    : spawns a mixed army at the base, selects it and queues move / attack-move waypoints (range rings + order lines).
## place_*  : builds a Generator through the sidebar model, starts its placement and puts the cursor on a valid / occupied / far cell.
## cards    : opens sidebar tab `--tab` (0 structures .. 7 powers) after a short warm-up.
## The sim is paused when the picture is taken. Prints LAB lines (icon prewarm report included).

var _lab: String = "group"
var _tab: int = 0
var _dx: int = 6
var _dy: int = 0
var _zoom: float = -1.0
var _after: int = 0
var _g: UiScreenGame = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lab="):
			_lab = a.substr(6)
		elif a.begins_with("--tab="):
			_tab = a.substr(6).to_int()
		elif a.begins_with("--dx="):
			_dx = a.substr(5).to_int()
		elif a.begins_with("--dy="):
			_dy = a.substr(5).to_int()
		elif a.begins_with("--after="):
			_after = a.substr(8).to_int()
		elif a.begins_with("--zoom="):
			_zoom = a.substr(7).to_float()
	var boot: Node = (load("res://src/app/boot.tscn") as PackedScene).instantiate()
	add_child(boot)
	_drive.call_deferred()


func _drive() -> void:
	var scenes: Node = get_tree().root.get_node("AppScenes")
	while not (scenes.get("screen") is UiScreenGame) or (scenes.get("screen") as UiScreenGame).ctx == null:
		await get_tree().process_frame
	_g = scenes.get("screen") as UiScreenGame
	var sim: UiSimPort = _g.ctx.sim
	while sim.tick() < maxi(40, _after):
		await get_tree().process_frame
	match _lab:
		"group":
			await _lab_group()
		"cards":
			_g.hud.sidebar().select_tab(_tab, true)
			await _settle(30)
		_:
			await _lab_place()
	await _report_icons()
	_g.ctx.session.request_pause(true)
	print("LAB ready lab=%s tick=%d" % [_lab, sim.tick()])


func _settle(frames: int) -> void:
	for _i: int in frames:
		await get_tree().process_frame


func _base_cell() -> Vector2i:
	var hq: int = _g.actions.hq()
	var row: UiEntityRow = UiEntityRow.new()
	if hq > 0 and _g.ctx.sim.read(hq, row):
		return Vector2i(row.x >> 10, row.y >> 10)
	return Vector2i(48, 48)


func _report_icons() -> void:
	var view: UiViewPortWorld = _g.ctx.view as UiViewPortWorld
	var guard: int = 0
	while view.icons != null and not view.icons.is_idle() and guard < 1200:
		await get_tree().process_frame
		guard += 1
	await _settle(4)
	if view.prewarm_report.is_empty():
		print("LAB prewarm: no report")
	else:
		var st: Dictionary = view.icons.stats
		print("LAB prewarm: %d icons in %.0f ms; bakes=%d disk_hits=%d bake_ms_sum=%.0f" % [int(view.prewarm_report["count"]), float(view.prewarm_report["ms"]),
			int(st["bakes"]), int(st["hits"]), float(st["bake_ms_sum"])])


func _lab_group() -> void:
	var w: SimWorld = _g.ctx.world()
	var pid: int = _g.ctx.local_pid
	var base: Vector2i = _base_cell()
	var picks: Array = [["unit.napc.bastion_heavy_tank", 3], ["unit.napc.paladin_howitzer", 2], ["unit.napc.sentinel_aa", 2], ["unit.napc.rifle_squad", 2], ["unit.napc.javelin_team", 2]]
	var ids: PackedInt32Array = PackedInt32Array()
	var k: int = 0
	for pick: Array in picks:
		var found: int = w.data.unit_idx(str(pick[0]))
		if found < 0:
			continue
		for n: int in int(pick[1]):
			var cx: int = base.x - 3 + (k % 6) * 2
			var cy: int = base.y + 6 + (k / 6) * 2
			k += 1
			var e: SimEntity = w.spawn_unit(found, pid, cx * SimConfig.CELL + SimConfig.CELL / 2, cy * SimConfig.CELL + SimConfig.CELL / 2)
			ids.append(e.id)
	await _settle(4)
	_g.selection.replace(ids, _g.ctx.sim)
	var legs: Array = [[UiOrderIntent.Kind.MOVE, 6, 9, false], [UiOrderIntent.Kind.MOVE, 12, 5, true], [UiOrderIntent.Kind.ATTACK_MOVE, 17, 9, true], [UiOrderIntent.Kind.MOVE, 14, 15, true]]
	for leg: Array in legs:
		var it: UiOrderIntent = UiOrderIntent.make(int(leg[0]), ids, (base.x + int(leg[1])) * 1024 + 512, (base.y + int(leg[2])) * 1024 + 512)
		it.queued = bool(leg[3])
		_g.bus.dispatch(it)
	_g.ctx.view.focus_on_sim((base.x + 6) * 1024, (base.y + 9) * 1024, true)
	await _settle(12)


func _lab_place() -> void:
	var presenter: UiHudPresenter = _g.presenter
	var model: UiBuildModel = presenter.model()
	var gen: UiBuildItem = null
	for it: UiBuildItem in model.items(UiBuildModel.Tab.STRUCTURES):
		if it.kind == UiBuildItem.Kind.STRUCTURE and it.id.ends_with("generator"):
			gen = it
	if gen == null:
		print("LAB no generator card")
		return
	_g.bus.build_start(gen.def_idx)
	var guard: int = 0
	while guard < 3000:
		await get_tree().process_frame
		guard += 1
		if presenter.model().item_for(UiBuildItem.Kind.STRUCTURE, gen.def_idx).state in [UiBuildItem.State.READY, UiBuildItem.State.PLACING]:
			break
	if not _g.placement.active:
		presenter.begin_placement(gen.def_idx)
	var base: Vector2i = _base_cell()
	var target: Vector2i = Vector2i(base.x + _dx, base.y + _dy)
	if _lab == "place_far":
		target = Vector2i(base.x + 16, base.y + 2)
	var view: UiViewPort = _g.ctx.view
	view.focus_on_sim(target.x * 1024, target.y * 1024, true)
	if _zoom >= 0.0:
		var cs: Dictionary = view.camera_state()
		cs["zoom"] = _zoom
		view.set_camera_state(cs, true)
	await _settle(20)
	var p: Vector3 = view.sim_to_world(target.x * 1024 + 512, target.y * 1024 + 512)
	var screen: Vector2 = view.camera().unproject_position(p)
	presenter.world_motion(screen)
	await _settle(20)
	presenter.world_motion(screen + Vector2(0.5, 0.0))
	await _settle(10)
	print("LAB placement active=%s valid=%s reason=%d anchor=%s" % [_g.placement.active, _g.placement.valid, _g.placement.reason, _g.placement.anchor])
