class_name SimMatchSetup
extends RefCounted
## Match setup glue between the data, map and sim domains (integration task INT1): the things nobody else owns
## because data may not mention Map* (lint L005) and the map generator knows nothing of GameData.
##
## `register_map_defs` puts the footprint of every structure / neutral def on a (generated or loaded) MapData and
## maps its neutral kinds to neutral defs; without it the world spawns structures that occupy no cells. Call it on
## the template map once, BEFORE SimWorld.create (the world clones the map and the clone shares the tables).
## `create_world` = register_map_defs + SimWorld.create. Both are idempotent and deterministic (def index order).

## Footprint of a structure def: solid rectangle / mask; only shoreline structures (Dock) can be rotated.
static func structure_footprint(d: DefStructure) -> MapFootprint:
	return MapFootprint.new(d.fp_w, d.fp_h, d.fp_mask, (d.place_mask & DefEnums.PLACE_SHORELINE) != 0)


## Neutral defs carry a square footprint (fp_w x fp_h cells, no mask, never rotated).
static func neutral_footprint(d: DefNeutral) -> MapFootprint:
	return MapFootprint.new(d.fp_w, d.fp_h)


## Registers footprints for every DefStructure (SimEntity.Kind.STRUCTURE) and DefNeutral (Kind.NEUTRAL), then maps
## each neutral kind id of `map.neutral_ids` to its DefNeutral index (a kind whose id is unknown stays scenery).
static func register_map_defs(map: MapData, data: GameData) -> void:
	for s: DefStructure in data.structures:
		map.set_footprint(SimEntity.Kind.STRUCTURE, s.index, structure_footprint(s))
	for n: DefNeutral in data.neutrals:
		map.set_footprint(SimEntity.Kind.NEUTRAL, n.index, neutral_footprint(n))
	for nk: int in map.neutral_ids.size():
		var ni: int = data.neutral_idx(map.neutral_ids[nk])
		if ni >= 0:
			map.set_neutral_def(nk, ni, SimEntity.Kind.NEUTRAL)


## Radius (cells) of the start area every player has explored at tick 0. The map generator puts the two "start" deposit
## fields 11 cells from the spawn (map_gen.json fields[0].dist_cells) and a Collector must see a field as explored before it
## harvests it (SimOrderHarvest._field_ok), so with fog on the start fields have to be part of the initial exploration.
const START_REVEAL_CELLS: int = 16
const START_REVEAL_TICKS: int = 40  ## how long the source lives; exploration itself is permanent
const SHAPE_DISC: int = 0  ## the vision system's disc shape (SimAbilityConsts.SHAPE_DISC), copied so this glue does not depend on the abilities files


## Explores a START_REVEAL_CELLS disc around every player's start cell (no-op with fog off). Idempotent per world only in
## effect (a second call adds a second source). Deterministic: players in pid order.
static func reveal_start_areas(world: SimWorld) -> void:
	if world == null or world.vision == null:
		return
	for s: SimPlayerSlot in world.config.players:
		var rec: int = s.start * MapData.SPAWN_STRIDE
		if s.pid >= world.players.size() or rec < 0 or rec + 1 >= world.map.spawns.size():
			continue
		var cell: int = world.map.spawns[rec + 1]
		world.vision.add_temp_source(world.vision.group_of(s.pid), SHAPE_DISC, world.map.center_x(cell), world.map.center_y(cell),
			0, 0, START_REVEAL_CELLS * SimConfig.CELL, false, world.tick + START_REVEAL_TICKS, 0)


## The validating world factory for real matches: registers the defs on `map`, then SimWorld.create (null + Log.error on
## any problem) and explores the start areas (reveal_start_areas).
static func create_world(data: GameData, cfg: SimMatchConfig, map: MapData, opts: Dictionary = {}) -> SimWorld:
	if map != null and data != null:
		register_map_defs(map, data)
	var w: SimWorld = SimWorld.create(data, cfg, map, opts)
	reveal_start_areas(w)
	return w
