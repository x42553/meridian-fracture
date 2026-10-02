class_name ViewFxPort
extends RefCounted
## Thin, always-present interface between the state views (ViewStructure, ViewRubble, ViewWrecks, ViewWarnings, ...) and the FX
## system. Everything the state views want to emit goes through spawn() / loop() / stop(); while no FxManager is bound (the FX
## system is built concurrently) or the effect id is not authored yet, the call is a counted no-op. A test can bind a recorder
## instead of a manager. Presentation only: nothing here touches the sim.
##
## Effect ids emitted by the state views (all optional in fx.json; unknown ids are skipped silently, never warned):
##   building_collapse (structure death, scale = footprint tier), weld_tick (scaffold welding), build_dust, build_complete,
##   sell_dust, damage_smoke, damage_fire, wreck_start, wreck_smoke, power_down, capture_flash, emp_arc, sw_warning_marker.
## The FX event router (F4) owns deaths, wreck loops, damage emitters and the warning marker once it is attached: see `event_router_active`.
## `suppressed` remains for ad-hoc de-duplication.

## Bound manager (FxManager). Null = no-op.
var target: FxManager = null
## id -> true: never forwarded (dedupe against another emitter of the same effect).
var suppressed: Dictionary = {}
## true while an FX event router (FxEventRouter.attach) is installed on the ViewWorld router: it then owns the event-driven effects
## (structure and unit deaths, wreck loops, damage emitters, the strategic warning marker), and the state views skip their own copies.
## ViewStateOverlays refreshes it every frame from `router.extra_handler.is_valid()`.
var event_router_active: bool = false
## Tests: when true every call is appended to `log` as [kind, id, a, b, scale] and forwarded nowhere.
var recording: bool = false
var log: Array = []
var stat_calls: int = 0
var stat_forwarded: int = 0
var stat_missing: int = 0

var _missing: Dictionary = {}


func bind(fx: FxManager) -> void:
	target = fx


func active() -> bool:
	return recording or target != null


## true when the bound manager knows effect `id` (always true while recording).
func has_effect(id: StringName) -> bool:
	if recording:
		return true
	if target == null:
		return false
	var book: FxRecipeBook = target.recipe_book()
	return book != null and book.has(id)


## One-shot effect at `a` (line effects: `b` is the end point, area effects: b.x may carry a duration). Returns the handle or -1.
func spawn(id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, scale_: float = 1.0) -> int:
	stat_calls += 1
	if suppressed.has(id):
		return -1
	if recording:
		log.append([&"spawn", id, a, b, scale_])
		return stat_calls
	if target == null:
		return -1
	if not has_effect(id):
		_note_missing(id)
		return -1
	stat_forwarded += 1
	return target.spawn(id, a, b, scale_)


## Repeating emitter (burning wreck, welding): `interval` and `duration` in seconds. Returns an emitter handle or -1.
func loop(id: StringName, a: Vector3, b: Vector3, scale_: float, interval: float, duration: float, delay: float = 0.0) -> int:
	stat_calls += 1
	if suppressed.has(id):
		return -1
	if recording:
		log.append([&"loop", id, a, b, scale_])
		return stat_calls
	if target == null:
		return -1
	if not has_effect(id):
		_note_missing(id)
		return -1
	stat_forwarded += 1
	return target.start_loop(id, a, b, scale_, interval, duration, delay)


func stop(handle: int) -> void:
	if handle > 0 and target != null and not recording:
		target.stop_emitter(handle)


## Cancels a running SUPER-class effect (a warning marker whose attack was cancelled).
func cancel(handle: int) -> void:
	if handle > 0 and target != null and not recording:
		target.cancel(handle)


func shake(amount: float, pos: Vector3) -> void:
	stat_calls += 1
	if recording:
		log.append([&"shake", &"", pos, Vector3.ZERO, amount])
	elif target != null:
		target.shake(amount, pos)


# ---- primitive pass-through (batches of FxManager: puff_smoke, puff_white, fire, sparks, flash, dustring, rubble, ...) ----

func sprites(batch_name: StringName, pos: Vector3, size_m: float, life: float, param: float = 1.0, palette: int = 0) -> void:
	stat_calls += 1
	if recording:
		log.append([&"sprites", batch_name, pos, Vector3(life, param, float(palette)), size_m])
	elif target != null:
		stat_forwarded += 1
		target.sprites(batch_name, pos, size_m, life, param, palette)


func puff(batch_name: StringName, pos: Vector3, size_m: float, life: float, alpha: float = 1.0) -> void:
	stat_calls += 1
	if recording:
		log.append([&"puff", batch_name, pos, Vector3(life, alpha, 0.0), size_m])
	elif target != null:
		stat_forwarded += 1
		target.puff(batch_name, pos, size_m, life, alpha)


func ring(batch_name: StringName, pos: Vector3, radius: float, life: float, palette: int = 0) -> void:
	stat_calls += 1
	if recording:
		log.append([&"ring", batch_name, pos, Vector3(life, float(palette), 0.0), radius])
	elif target != null:
		stat_forwarded += 1
		target.ring(batch_name, pos, radius, life, palette)


## One welding flash: the authored `weld_tick` effect when it exists, else sparks + flash sprites from the batch primitives.
func weld_spark(pos: Vector3) -> void:
	if suppressed.has(&"weld_tick"):
		return
	if has_effect(&"weld_tick"):
		spawn(&"weld_tick", pos, Vector3.ZERO, 2.4)
	else:
		sprites(&"sparks", pos, 1.9, 0.5, 0.9, 1)
		sprites(&"flash", pos + Vector3(0.0, 0.15, 0.0), 1.6, 0.08, 0.9, 1)


## Electric arc between two points: the authored `emp_arc` effect, else the manager's bolt ribbon.
func arc(a: Vector3, b: Vector3) -> void:
	if suppressed.has(&"emp_arc"):
		return
	if has_effect(&"emp_arc"):
		spawn(&"emp_arc", a, b, 1.0)
	elif recording:
		log.append([&"bolt", &"", a, b, 1.0])
	elif target != null:
		stat_forwarded += 1
		target.bolt(a, b, 0.25, 0.4, 1.0)


func column(batch_name: StringName, pos: Vector3, radius: float, height: float, life: float) -> void:
	stat_calls += 1
	if recording:
		log.append([&"column", batch_name, pos, Vector3(life, height, 0.0), radius])
	elif target != null:
		stat_forwarded += 1
		target.column(batch_name, pos, radius, height, life)


## Ids requested but not authored in the bound recipe book (diagnostics).
func missing_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _missing:
		out.append(String(k as StringName))
	out.sort()
	return out


## Number of recorded calls of `id` (tests).
func count_of(id: StringName) -> int:
	var n: int = 0
	for rec: Variant in log:
		if (rec as Array)[1] == id:
			n += 1
	return n


func _note_missing(id: StringName) -> void:
	stat_missing += 1
	_missing[id] = true
