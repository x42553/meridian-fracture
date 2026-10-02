class_name AiContext
extends RefCounted
## Per-controller bundle handed to every module (ai.md 3.5b). `brain` is a plain RefCounted until the brain task lands
## (AiBrain owns wants/ops/phase); the extra fields below are derived once at bootstrap.

var view: AiWorldView = null
var kb: AiKnowledge = null
var cmd: AiCommandBuilder = null
var cfg: AiConfig = null
var diff: AiDifficultyProfile = null
var pers: AiPersonality = null
var rng: AiRng = null
var shared: AiSharedData = null
var brain: RefCounted = null
var tick: int = 0
var dt: int = 1  ## ticks since the previous think (>= 1)
# ---- additions (derived at bootstrap) ----
var store: AiDataStore = null
var telemetry: AiTelemetry = null
var roster_idx: int = -1
var res: AiRoleResolver = null  ## roles of my roster
var tech: AiTechGraph = null  ## prerequisite graph of my roster
var pid: int = 0


## Profile of one of MY unit defs (built lazily, shared with the other AIs of the same roster).
func unit_profile(def_idx: int) -> AiUnitProfile:
	return shared.unit_profile(roster_idx, def_idx)


func struct_profile(def_idx: int) -> AiUnitProfile:
	return shared.struct_profile(roster_idx, def_idx)


## Profile of a def owned by ANY player p (enemy rosters are public).
func unit_profile_of(p: int, def_idx: int) -> AiUnitProfile:
	return shared.unit_profile(view.roster_of(p), def_idx)


func struct_profile_of(p: int, def_idx: int) -> AiUnitProfile:
	return shared.struct_profile(view.roster_of(p), def_idx)


func tune(path: String, default_value: int = 0) -> int:
	return store.tune(path, default_value)
