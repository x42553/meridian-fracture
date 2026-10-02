extends Node3D
## INT3 acceptance scene: a REAL generated-map match rendered through AppViewStage (which attaches the FX layer itself) where player 0's
## superweapon is forced ready and launched at the enemy start through CMD_LAUNCH_SUPERWEAPON, so the warning marker, the countdown
## label and the impact come from the kernel's own events. Sim at 20 Hz against the frame clock; the camera parks on the target.
##   tools/gd run res://tests/visual/int3_sw.tscn --gui --size 1600x900 --allow-errors -- --roster=roster.def.vanilla
##       --caps=200,330,420 --out=/abs/sw   [--zoom=0.3 --launch=40 --seed=3]
## Prints `INT3_SW cap <path> tick=<n> fx=<live instances>` per capture and the router counters at the end.

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")

var world: SimWorld = null
var stage: AppViewStage = null

var _args: Dictionary = {}
var _frame_no: int = 0
var _acc: int = 0
var _caps: PackedInt32Array = PackedInt32Array()
var _out: String = ""
var _target: Vector2i = Vector2i.ZERO
var _launch_tick: int = 40
var _zoom: float = 0.3


func _ready() -> void:
	_args = _parse()
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var roster: String = str(_args.get("roster", "roster.def.vanilla"))
	var m: Dictionary = SimMatchKit.make_match({"rosters": PackedStringArray([roster, "roster.nec.vanilla"]), "seed": int(_args.get("seed", "3")),
		"size": 96, "bots": false})
	world = m["world"] as SimWorld
	if world == null:
		get_tree().quit(1)
		return
	var s0: int = world.map.spawns[0]
	var s1: int = world.map.spawns[1]
	S.base(world, 0, s0 % world.map.w + 8, s0 / world.map.w + 8)  # a powered base with Radar, Laboratory and the launcher next to the start
	S.force_ready(world, 0)
	world.clear_events()
	_target = Vector2i(s1 % world.map.w + 2, s1 / world.map.w + 2)
	_launch_tick = int(_args.get("launch", "40"))
	_zoom = float(_args.get("zoom", "0.3"))
	stage = AppViewStage.new()
	add_child(stage)
	stage.build_sync(world, 0)
	for s: String in str(_args.get("caps", "")).split(",", false):
		_caps.append(int(s))
	_out = str(_args.get("out", "user://int3_sw"))
	var cam: ViewCamera = stage.view.camera
	cam.snap_to(Vector2(float(_target.x), float(_target.y)) * ViewConsts.CELL_M, 0.0, _zoom)
	cam.advance(0.0)
	stage.view.reconcile()


func _parse() -> Dictionary:
	var d: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d


func _process(delta: float) -> void:
	if world == null or stage == null:
		return
	_frame_no += 1
	var events: PackedInt32Array = PackedInt32Array()
	if _acc % 3 == 0:
		if world.tick == _launch_tick:
			S.launch(world, 0, _target.x, _target.y, 0)
		world.step()
		events = world.events.take()
	var alpha: float = float(_acc % 3) / 3.0 + 0.17
	_acc += 1
	stage.frame(delta, alpha, events)
	if _caps.has(_frame_no):
		await RenderingServer.frame_post_draw
		var path: String = "%s_%d.png" % [_out, _frame_no]
		get_viewport().get_texture().get_image().save_png(path)
		print("INT3_SW cap ", path, " tick=", world.tick, " fx=", stage.fx_stage.fx.live_instances())
	if _caps.size() > 0 and _frame_no >= _caps[_caps.size() - 1] + 4:
		print("INT3_SW done tick=", world.tick, " router=", stage.fx_stage.router.stats)
		get_tree().quit()
