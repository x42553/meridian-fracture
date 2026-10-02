class_name AiConfig
extends RefCounted
## Construction parameters of one AI slot (ai.md 3.2). The roster is NOT passed by the factory: the thinker reads
## world.players[pid].roster at its first think.

var pid: int = 0
var level: int = AiTypes.Difficulty.MEDIUM  ## 0..3
var style: int = 0  ## 0..3 (ai.md 5.14.4)
@warning_ignore("shadowed_global_identifier")
var seed: int = 0  ## 32-bit, already mixed by net: mix32(match_seed ^ ((pid + 1) * 0x9E3779B9))
var debug_level: int = 0  ## 0 off, 1 trace ring, 2 trace + overlay frames
var perf: bool = false  ## enable AiPerf sampling (diagnostic only)
var personality_override: Dictionary = {}  ## tests: personality field -> int
var tuning_override: Dictionary = {}  ## harness param sweeps: "dotted.path" -> Variant
var wu_share: int = 0  ## per-AI average wu/tick cap set by the factory's global governor (0 = the difficulty profile's own)


static func make(p_pid: int, p_level: int, p_style: int, p_seed: int) -> AiConfig:
	var c: AiConfig = AiConfig.new()
	c.pid = p_pid
	c.level = clampi(p_level, 0, AiTypes.AI_LEVEL_COUNT - 1)
	c.style = clampi(p_style, 0, AiTypes.AI_STYLE_COUNT - 1)
	c.seed = p_seed
	return c
