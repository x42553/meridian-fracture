class_name AiThinker
extends RefCounted
## The `(world, out)` callable of one AI slot (ai.md 3.2, net XR-13): tracks the catch-up clock `dt` between thinks, runs the
## bootstrap on the first think (also the entry for the AI takeover of a dropped human) and hands the world reference through
## to the controller. `think` appends only PackedInt32Array commands (<= 64) to `out`.

var cfg: AiConfig = null
var controller: AiController = null
var last_think_tick: int = -1
var thinks: int = 0


func _init(p_cfg: AiConfig, p_factory: AiFactory) -> void:
	cfg = p_cfg
	controller = AiController.new(p_cfg, p_factory.shared, p_factory.store, p_factory.telemetry)


func think(world: RefCounted, out: Array) -> void:
	var tick: int = int(world.get("tick"))
	var dt: int = 1 if last_think_tick < 0 else tick - last_think_tick
	if dt <= 0:
		return  # a second call in the same tick does nothing
	controller.step(world, dt, out)
	last_think_tick = tick
	thinks += 1


func state_hash() -> int:
	return controller.state_hash()


func debug_snapshot() -> Dictionary:
	return controller.debug_snapshot()


## AiPerf sample of the last think in microseconds (diagnostic only; 0 unless cfg.perf).
func last_think_us() -> int:
	return controller.perf.last_us
