class_name SimPipeline
extends RefCounted
## The fixed 11-stage table (sim_core 2.2 / 3.10): instantiates the domain systems (the stub classes are
## overwritten by their owners, so the names stay valid) or takes test overrides.

const STAGE_NAMES: PackedStringArray = SimSystem.STAGE_NAMES
## Class names of the stages, index = stage_no - 1 (what `opts.disable` matches).
const CLASS_NAMES: PackedStringArray = [
	"SimCommandSystem", "SimProductionSystem", "SimEconomySystem", "SimPowerSystem", "SimOrderSystem",
	"SimMovementSystem", "SimAbilitySystem", "SimCombatSystem", "SimZoneSystem", "SimVisionSystem", "SimCleanupSystem",
]
## Stages the kernel needs: they cannot be disabled.
const KERNEL_STAGES: PackedInt32Array = [1, 5, 11]


## `disable`: class names replaced by a plain SimSystem stub (PackedStringArray or Array of String).
## `systems`: SimSystem instances whose `stage_no` replaces that stage (test doubles; they must subclass the
## stub class of the stage so the world's typed member accepts them).
static func create(disable: Variant = null, systems: Variant = null) -> Array[SimSystem]:
	var out: Array[SimSystem] = [
		SimCommandSystem.new(), SimProductionSystem.new(), SimEconomySystem.new(), SimPowerSystem.new(),
		SimOrderSystem.new(), SimMovementSystem.new(), SimAbilitySystem.new(), SimCombatSystem.new(),
		SimZoneSystem.new(), SimVisionSystem.new(), SimCleanupSystem.new(),
	]
	if disable != null:
		for n: Variant in disable:
			var idx: int = CLASS_NAMES.find(str(n))
			if idx < 0:
				Log.error("pipeline", "disable: unknown stage class '%s'" % str(n))
			elif KERNEL_STAGES.has(idx + 1):
				Log.error("pipeline", "disable: '%s' is a kernel stage" % str(n))
			else:
				var stub: SimSystem = SimSystem.new()
				stub.stage_no = idx + 1
				out[idx] = stub
	if systems != null:
		for v: Variant in systems:
			var s: SimSystem = v as SimSystem
			if s == null or s.stage_no < 1 or s.stage_no > out.size():
				Log.error("pipeline", "systems: entry is not a SimSystem with a stage_no 1..11")
				continue
			out[s.stage_no - 1] = s
	return out
