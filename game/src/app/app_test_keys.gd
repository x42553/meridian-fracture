class_name AppTestKeys
extends RefCounted
## Scripted real input events of the GUI test boot (`--keys=<script>`, task HOT1): key presses and mouse moves / clicks pushed into the
## root viewport at given sim ticks, so a live match can be driven like a player does and screenshotted (`--cap=`). Screenshots and
## regression runs only; nothing here is reachable in a normal start.
##
## Script: steps separated by `;`, each `<what>@<tick>`:
##   `F5@80`            a key chord ("F5", "Ctrl+1", "Alt+Q": `UiActions.parse_chord`) pressed and released
##   `move:X,Y@T`       the pointer moves to window pixel X, Y
##   `click:X,Y@T`      a left click at window pixel X, Y
##   `movehq:DX,DY@T`   the pointer moves to the screen position of the local HQ plus DX, DY cells (needs the camera on the base)
##   `clickhq:DX,DY@T`  a left click there
## Printed lines: `APPKEYS tick=<n> <step>` (greppable).

var _steps: Array[Dictionary] = []
var _next: int = 0


static func parse(text: String) -> AppTestKeys:
	if text.strip_edges() == "":
		return null
	var k: AppTestKeys = AppTestKeys.new()
	for raw: String in text.split(";", false):
		var parts: PackedStringArray = raw.strip_edges().split("@")
		if parts.size() != 2 or not parts[1].is_valid_int():
			continue
		var what: String = parts[0]
		var entry: Dictionary = {"tick": int(parts[1]), "what": what, "kind": "key", "x": 0, "y": 0}
		for kind: String in ["movehq", "clickhq", "move", "click"]:
			if what.begins_with(kind + ":"):
				var xy: PackedStringArray = what.substr(kind.length() + 1).split(",")
				entry["kind"] = kind
				entry["x"] = int(xy[0]) if xy.size() > 0 else 0
				entry["y"] = int(xy[1]) if xy.size() > 1 else 0
		k._steps.append(entry)
	k._steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) < int(b["tick"]))
	return k


## Once per frame while the match plays: runs every step whose tick has come.
func step(tree: SceneTree, ctx: AppMatchContext) -> void:
	while _next < _steps.size() and ctx.tick() >= int(_steps[_next]["tick"]):
		var s: Dictionary = _steps[_next]
		_next += 1
		_run(tree, ctx, s)


func _run(tree: SceneTree, ctx: AppMatchContext, s: Dictionary) -> void:
	var kind: String = str(s["kind"])
	var pos: Vector2 = Vector2(float(int(s["x"])), float(int(s["y"])))
	if kind == "movehq" or kind == "clickhq":
		pos = _hq_screen(ctx, int(s["x"]), int(s["y"]))
	_say("APPKEYS tick=%d %s at=%s" % [ctx.tick(), str(s["what"]), str(pos)])
	match kind:
		"key":
			var packed: int = UiActions.parse_chord(str(s["what"]))
			if packed == 0:
				return
			for down: bool in [true, false]:
				var ev: InputEventKey = UiKeymap.unpack(packed)
				ev.pressed = down
				tree.root.push_input(ev)
		"move", "movehq":
			_motion(tree, pos)
		"click", "clickhq":
			_motion(tree, pos)
			for down: bool in [true, false]:
				var e: InputEventMouseButton = InputEventMouseButton.new()
				e.position = pos
				e.global_position = pos
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = down
				e.button_mask = (MOUSE_BUTTON_MASK_LEFT if down else 0) as MouseButtonMask
				tree.root.push_input(e)


static func _motion(tree: SceneTree, pos: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	tree.root.push_input(e)


## Window pixel of the local player's first structure (the HQ) shifted by cells.
static func _hq_screen(ctx: AppMatchContext, dx: int, dy: int) -> Vector2:
	var w: SimWorld = ctx.world()
	if w == null or ctx.view == null or ctx.local_pid < 0:
		return Vector2.ZERO
	var best: SimEntity = null
	for e: SimEntity in w.structures_of(ctx.local_pid):
		if best == null or e.id < best.id:
			best = e
	var cam: Camera3D = ctx.view.camera()
	if best == null or cam == null:
		return Vector2.ZERO
	var world: Vector3 = ctx.view.sim_to_world(best.x + dx * 1024, best.y + dy * 1024)
	return cam.unproject_position(world)


static func _say(line: String) -> void:
	# lint-allow: L006 greppable test-boot protocol line (APPKEYS ...)
	print(line)
