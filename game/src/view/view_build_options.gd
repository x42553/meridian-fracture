class_name ViewBuildOptions
extends RefCounted
## Options of ViewWorld.build_async (render spec 3.1). Presentation only.

var mood: StringName = &""  ## "" = derive from MapData.biome and family (VIEW-03 atmosphere; ignored until it lands)
var night_allowed: bool = true
var deposit_source: int = 0  ## 0 = MapData per-cell deposits, 1 = DEPOSIT entities (risk R24)
var terrain_subdiv: int = -1  ## -1 = from quality
var screenshot_mode: bool = false  ## freezes view_time to 0, disables edge scroll, fixed RNG seeds
var rng_seed: int = 1
var prewarm_scope: int = 1  ## 0 none, 1 = rosters present in the match, 2 = all rosters
var bake_icons: bool = true
var unit_backend: int = -1  ## -1 = auto (ViewQuality), 0 nodes, 1 batch (the batch backend is not implemented yet: nodes are used)
## VW additions
var build_terrain: bool = true  ## false: the caller supplies `world.terrain` (and camera) before build_async
var proof_fallback: bool = true  ## units without a recipe use the proof archetypes (veh_tank / inf_squad) until faction content lands
var create_camera: bool = true  ## false: the caller supplies `world.camera`
