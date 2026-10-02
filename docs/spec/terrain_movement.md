# MERIDIAN FRACTURE — Domain Spec: Terrain, Pathfinding, Movement & Map Generation

> Status: v0.2, written by the *Terrain / pathfinding / movement / map-generation* domain architect and **aligned with the concurrently published specs** (`sim_core.md`, `data_balance.md` + `docs/balance/TAXONOMY.md` + `game/data/balance/global.json`, `combat.md`, `abilities.md`, `economy.md`, `net.md`, `ai.md`, `render.md`, `qa.md`). Binding on implementers once the reconciler has merged it; where it disagrees with `docs/ARCHITECTURE.md` the anchor wins (no disagreement is intended — every deviation is listed in §13). Where two peer specs disagree with each other, §12 records the conflict, the choice made here, and the compatibility shim that keeps both callers working.
> Evidence: every performance figure in §9 and every generator statistic in §5.12 was measured in this session with the stock Godot 4.7.2 binary (headless, typed GDScript, Apple M5 Max, machine shared with other agents, so *loaded* runs were 1.3–2× slower than the unloaded figures quoted). Micro-benchmarks and a full generator prototype (v4, re-run after the alignment changes) were written for this spec; their structure is reproduced in §5, their results in §9 and §5.12.
> Conventions: `ASSUMPTION(domain)` marks an interface I depend on but do not own. `TODO(module)` tags follow ARCHITECTURE §13. "cell" = one terrain tile (`Fp.CELL = 1024` units). All arithmetic is integer; "half-up" rounding is `(v + d/2) / d` for non-negative `v`. Angles are binary angles 0..4095 (0 = +x/east, increasing toward +y/south). Numbers taken from the frozen vocabulary are quoted with their source (`TAXONOMY §8`, `global.json`), never redefined.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

### 1.1 What this domain owns

**A. The `map/` module** (`core, data → map`, no `Node`s):

* `MapData`: the immutable-after-generation *static* layers (terrain type, derived terrain kind, height, flags, deco, field ids, start cells, neutral list, resource-field list, view layers: corner heights, moisture, shore distance, road polylines) and the *dynamic* layers that the sim mutates (structure occupancy = the world's structure grid, per-cell deposit stock), with incremental hashes so the dynamic state is checksummed in O(1) per tick. Serialisation (`to_bytes/from_bytes`), `map_hash`, per-world clone.
* The **terrain model**: 16 generator terrain *types* mapped onto the frozen 8 **TerrainKinds** (`road, open, rough, forest, marsh, shallow, deep, cliff`), speeds and passability read from `DefMoveTable` (never re-authored here), path-cost weights derived from them by one formula, shore/ford/beach/urban/cliff rules.
* **Navigation data**: seven *nav profiles* (foot, wheeled, tracked, amphibious, naval, naval-deep-only, submerged) × clearance sizes 1–3 (weights, clearance, abstract 8×8-block component graphs), integer line-of-sight, nearest-passable queries, cost estimates for AI, dynamic update on structure placement/removal, the predicate API other domains use (`passable`, `is_clear`, `is_water`, `region`, `water_body_size`, …).
* The **pathfinder** (`MapPathSearch`): integer-only, resumable, count-bounded; hybrid of direct LOS → fine bucket A* (short queries) → corridor A* over an abstract block graph (long queries) → cost-checked string-pull smoothing; partial-path fallback.
* **Terrain-side build predicates** (`MapFootprint`, `MapBuildRules`): footprint cell lists (rectangles and `fp_mask` shapes, four orientations), terrain/shore/berth rules used by economy's `SimPlacement`.
* The **map generator** (`MapGenerator`, `MapGenJob`, helpers): three families (open land, constrained urban routes, mixed coast/river), 2/3/4/6/8-slot fair layouts, the balance framework's deposit layout (FRAMEWORK §5.8), start areas, neutral structures, optional shore start (`start_near_water`), validation (public `MapGenValidate`), deterministic repair/regenerate loop, safe fallback template, sliceable job for the loading screen.
* **Interfaces for other modules**: the exact `MapData` field contract for `ViewTerrainSource` (render), `MapData.passable/region/get_family` (AI), `MapGenerator.validate_params/generate` + `MapGenJob` + `content_hash` (net, QA), `MapData.to_bytes/from_bytes` (net/replay).

**B. The movement stack in `sim/`:**

* `SimMovementSystem` (pipeline stage 6, a `SimSystem`), `SimMoveComp` (the entity's `move` slot), `SimMoveProfiles` (per-def movement profile derived from `DefUnit`), `SimPathService` (request queue, budget, cache), `SimSteering` (turn/speed/arrival math), `SimSeparation` (collision, pushing idle friendly units), `SimFormation` (group slot assignment), `SimAirMove` (flight kinematics), `SimExitMove` (spawn/exit search, eject from a footprint, scripted glide), `SimMovement` (static facade: the movement primitives that combat, economy, abilities and the AI call).
* **Order handlers** (`SimOrderHandler` subclasses registered with `world.orders`): `SimOrderMove` (`T_MOVE`, `T_PATROL`, `T_FOLLOW`, `T_FACE`), `SimOrderAir` (`T_LAND`), `SimOrderCargo` (`T_LOAD`, `T_UNLOAD`, `T_GARRISON` — the *walk-up/positioning* half; cargo state belongs to abilities' `SimTransport`, §5.8).

### 1.2 What this domain does NOT own (and the seam with each owner)

| Not owned | Owner | Seam |
|---|---|---|
| `SimWorld`/`SimEntity` layout, component-slot policy, order dispatcher and queue semantics, MASTER command and event catalogs, `world.set_pos/set_layer/set_inside`, shared `flags` bits, `SpatialHash`, checksum sections | sim_core | I register `SimOrderHandler`s and a `SimSystem`; I consume the MASTER command ops `MOVE 0x10`, `PATROL 0x17`, `LOAD 0x1A`, `UNLOAD 0x1B`, `GARRISON 0x1C`, `STOP 0x14`, `SCATTER 0x16` through the built-in order executor (**no new opcodes**); I write only `e.move`, flag bits 16–19, and `x, y, facing, layer` through `world.set_pos/set_layer`. |
| Target acquisition, attack / attack-move / guard / return-to-base orders, the aircraft sortie state machine (`SimCompAir`, fuel, ammo, rearm), suppression | combat | Combat calls the `SimMovement` primitives of §3.10 (`move_to`, `move_to_range`, `stop`, `turn_to`, `is_moving`, `air_fly_to`, `air_orbit`, `air_hover`, `air_face`, `air_takeoff`, `air_land_at`, `air_at_goal`, `pause/resume`). I never look at targets; I read `suppression_speed_bp(e)`. |
| Speed buffs/debuffs (Open Corridor, Steel Advance, Horizon debris slow, …), deploy/pack immobility, transports and garrisons (`SimTransport`: capacity, board/unload timing, ejection), zones | abilities / zones | I read `speed_units(e)`, `is_immobile(e)`, `is_turn_locked(e)` and call `request_pack(e)`, `SimTransport.board/garrison_enter/begin_unload`. Debris is a stat mod (never a map patch): the map has **no** dynamic speed patches. |
| Harvest state machine, refinery dock protocol/queue, construction/production queues, placement validity (`SimPlacement`), structure lifecycle, airfield pad assignment and rearm | economy / production | Economy calls `SimMovement.go_to/stop/glide/at_goal/path_failed/find_free_cell_near/eject_units_from_rect`, `MapData` deposit and terrain predicates, `MapBuildRules` terrain rules, `MapData.occupy/vacate`. |
| Unit numbers (speed, radius, accel, turn, size class), def loading, `movement_defaults`, structure footprints (`fp_w/fp_h/fp_mask/exit/place_mask`) | data / balance | I consume `DefUnit`, `DefMoveTable`, `DefBodyTable`, `DefStructure`, `global.json → movement_defaults`; I define only the terrain-type table (`terrain.json`), generator tuning (`map_gen.json`) and movement tuning that balance does not cover (`movement.json`). |
| Fog/shroud, detection, camouflage | vision / abilities | None: vision is a cell-granular disc that ignores terrain height (abilities §5.9.1), so this domain exports no line-of-sight for fog. `MapNav.los` is a *pathing* LOS. |
| Rendering (terrain mesh, water, decor), minimap widget, audio, UI | view / ui / audio | I provide the layers listed in §5.14 (`heights`, `types`, `flags`, `moisture`, `terrain_kind`, `shore_dist`, `roads`, `water_level_u`, `start_cells`, `fields`). `ViewTerrainSource` is the only reader. |
| Lobby, LAN transport of the map, replay files | net | I provide `MapData.to_bytes()/from_bytes()`, `content_hash()`, `MapGenerator.validate_params`, `MapGenJob`. |
| AI decisions and its own route graph / resource-site analysis | ai | I provide `MapData.passable/region/get_family`, `MapNav.estimate_cost/same_region`, and (optional, low priority) `MapRegions`. |

**Assumption register** (every interface this domain depends on but does not own; each is tagged `ASSUMPTION(domain)` where it is used, and the numbered request in §13 asks the owner to confirm it):

| Tag | What is assumed | Confirmed in |
|---|---|---|
| `ASSUMPTION(sim_core)` | `SimSystem` hooks, `SimOrderHandler` contract (`begin`+`tick` fused, `cancel`, `requires_target`), `world.set_pos/set_layer`, `units_of`, `query_radius`, flag bits 16–19, `move` slot, `STATE`/`ORDER_FAILED` events, `MapData` constructor contract (R7) | sim_core §3–§6 (published); §13-1..8 |
| `ASSUMPTION(data)` | `DefUnit` movement fields incl. the *resolved* per-player values, `DefMoveTable`, `DefBodyTable`, `movement_defaults`, loaders and hash for the three JSON files | data_balance §4.2, §7; §13-9..13 |
| `ASSUMPTION(abilities)` | `speed_units`, `is_immobile`, `is_turn_locked`, `request_pack`, `SimTransport.*`, `DF_UNLOAD_MOVING`, debris as a stat mod | abilities §3.2, §3.5, §5.10–5.11; §13-14, 15 |
| `ASSUMPTION(combat)` | calls the `SimMovement` primitives, `suppression_speed_bp`, registers `T_ATTACK_MOVE`, passes `takeoff_ticks`/`landing_ticks`, does not write aircraft `layer` | combat §3.7–3.8, §13-23/24; §13-16 |
| `ASSUMPTION(economy)` | `SimPlacement` composes `MapBuildRules`; structure lifecycle calls `occupy/vacate`; dock protocol drives `glide`; `airfield_pad_cell`; default rally | economy §3.7, §5.3, §5.9, §5.14; §13-17..19 |
| `ASSUMPTION(net)` | `NetWorldJob` can wrap `MapGenJob`; worker threads available | net §3.3, XR-12/14; §13-20 |
| `ASSUMPTION(ai)`, `ASSUMPTION(render)`, `ASSUMPTION(qa)` | read the predicate API, the render field contract, `MapGenerator.generate(map_cfg)`/`MapGenValidate` | §13-21..23 |

### 1.3 Decision digest (binding)

| # | Decision | Why |
|---|---|---|
| D-1 | Maps are **square**, `size ∈ {96,104,…,256}` (multiple of 8), cell index `cy*w+cx`. An **unplayable rim of `RIM_W = 6` cells** surrounds the playable interior (open/urban: outer 2 cells `MOUNTAIN`, next 4 `CLIFF`; coast: `DEEP` sea), and the outer `NAV_BORDER = 2` cells are always impassable in every nav profile, so no search or steering loop needs bounds checks. | Symmetry/rotation need w = h; the rim removes branches from hot loops (measured 15–25 % faster) and satisfies render's "≥ 6 cells of water or cliff at the edge". |
| D-2 | **Vocabulary is the frozen one**: `MoveClass` 0–8, `TerrainKind` 0–7, `Layer` 0–3, `SizeClass` (TAXONOMY §6/§8/§11). 16 generator *terrain types* map onto the 8 kinds (§4.2); **speeds and passability are read from `DefMoveTable.speed_bp`**; nav profiles, weights and the land-connectivity guarantee are **derived** from that table at load, so a change of the table changes no code. | One authority for terrain rules; TAXONOMY is frozen. |
| D-3 | Forest, marsh, shallow water and cliff behaviour is *purely data*: with today's table forest blocks wheeled only (tracked 55 %, foot 70 %, amphibious 50 %), shallow water is a ford for every ground class (foot 70, wheeled 50, tracked 65, amphibious 90), cliffs/mountains/urban blocks block everything on the ground. The generator's connectivity guarantee uses the **intersection** of the foot, wheeled and tracked passable sets ("land-only guarantee"), so it stays valid if balance later blocks forest for tracked (§12 R3). | The task text ("forest blocks vehicles") and TAXONOMY differ; data-driven derivation makes both work. |
| D-4 | Ground units collide with terrain **by centre cell only**; radius is used for *planning* (clearance) and unit↔unit separation. Structures block whole cells. No crushing. | Deterministic, cheap, no polygon math; matches C&C feel. |
| D-5 | Path cost model: baseline terrain (100 %) = weight **16**; step cost `(10·w+8)>>4` orthogonal, `(14·w+8)>>4` diagonal; weights derived from the speed table by one formula (§5.1). | One integer cost model shared by A*, LOS-cost, smoothing, AI estimates. |
| D-6 | Pathfinding = **hybrid**: path cache → integer LOS shortcut → fine **Dial-bucket A\*** for short queries (< 24 cells, ≤ 2400 expansions) → **corridor A\*** restricted to an abstract route over an 8×8-block *component graph* for every longer query → cost-checked string-pull smoothing. **No flow fields** (measured, §5.3.1). Group orders share one path per (profile,size,start-node,goal). | Measured over 1 200 random ≥ 60-cell queries: plain fine A* averages 0.9–3.8 k visited cells with 9–22 k worst cases; the corridor averages 0.5–0.9 k with a hard worst case of ≈ 2.3 k, for a mean cost penalty of 2–6 %. |
| D-7 | All per-tick work is bounded **by counts** (path budget in expansion-units, deliveries/tick, neighbours/unit, dirty-block budget); searches are resumable across ticks (DR-11). | Determinism and predictable frame time. |
| D-8 | MovementSystem is **two-phase**: snapshot (steer + separation from positions at tick start) then apply in ascending entity id; separation grids are rebuilt canonically every tick (no history dependence). | Order-independence (DR-6, DR-9). |
| D-9 | Speeds are `Q4` (units/tick × 16) internally. The per-tick top speed is `abilities.speed_units(e) × DefMoveTable.speed_bp[mc][kind] × water_mult_bp × suppression`, folded in Q4 with half-up rounding at each stage (§5.1); accel/decel come from `movement_defaults` (accel ticks per size class, decel = 70 % of the accel time). | Sub-unit accelerations without floats; data and abilities stay the only authorities on numbers. |
| D-10 | Amphibious units keep `entity.layer = GROUND`; water state is flag `F_ON_WATER` (+ `STATE` event). Speed/health "on water" conditions read that flag (data folds `ON_WATER` into `water_mult_bp`). Naval = `SURFACE`, submerged = `UNDERWATER`. | TAXONOMY §7/§8: amphibious is a ground-layer class; combat/abilities selectors use the condition, not a layer. |
| D-11 | **Kernel binding**: one `SimMoveComp` in the entity's `move` slot (`hash_into` + `HASH_EXEMPT`), positions only through `world.set_pos`, layers through `world.set_layer`, flag mirrors `F_MOVING/F_AIRBORNE/F_BLOCKED/F_ON_WATER`, order handlers are stateless `SimOrderHandler`s (state lives in the component and in the order's `phase/t0/p0/p1`), events only from the MASTER catalog (+ requested `STATE` codes). | sim_core §4.5, §5.6, §6.3. |
| D-12 | Aircraft never use the path service: direct flight with two kinematic models (fixed-wing bank/orbit, rotor hover). This domain exposes **flight primitives**; the sortie state machine, pad choice, fuel and rearm are combat's/economy's. Layer flips (`GROUND↔AIR`) happen inside `air_takeoff`/`air_land_at`. | combat.md §5.12, economy.md §5.14. |
| D-13 | Cargo: this domain walks passengers up to carriers/garrisons and positions carriers for unloading; capacity, timing, ejection and `container_id/holder` bookkeeping are abilities' `SimTransport` (sim_core `set_inside`). | abilities.md §5.10. |
| D-14 | Docking is a **scripted glide** (`SimMovement.glide`, exact tick count) driven by economy's dock protocol; queueing and arbitration are economy's. Exits/eviction: `find_free_cell_near`, `eject_units_from_rect`. | economy.md §5.9. |
| D-15 | Generator: seeded, integer, **fold-symmetric** (D1/D2/D4 exact for 2/4/8 slots; angular D-fold ≈ exact for 3/6), painting by **integer distance predicates on transformed control points**, **two phases** (expensive synthesis once; cheap layout/validation retried at corridor widths 5→7→9), then re-seed (≤ 2 attempts), then a **safe template**. Pure and thread-safe. Deposit layout = FRAMEWORK §5.8 (2 standard start fields, natural standard + rich, 2 further standard, 2 shared contested rich; 129.6 k credits reachable per slot). | Measured first-attempt success on the full matrix (§5.12.6). |
| D-16 | Connectivity is **constructive**: every start, field and neutral is joined by ≥ 5-cell-wide carved corridors (a size-2 unit needs 3 clear cells; 3-wide diagonal bands were measured to fragment). Validation is the safety net, not the mechanism. | Measured failures with 3-wide routes. |
| D-17 | Deposits are **per-cell stock in `MapData`** (FRAMEWORK: "a load of 600 empties exactly one cell", "nearest non-empty cell, lowest index"), finite, optional regrowth hook. `MapData` also publishes the field discs (`deposit_fields()`), the neutral list (`objects`, `neutral_spawns()`), so economy's `SimDepositTable` and sim_core's `objects` can be built from one source (§12 R1). | One authoritative grid, three read views. |
| D-18 | Net/replays carry **`MapData.to_bytes()`** (deflated layers) *or* the config (`MapGenerator.generate(map_cfg)` is a pure function); both are hash-verified (`map_hash`), so a generator-version change cannot silently alter an old replay. | Immunity to generator drift. |
| D-19 | Dynamic map state is hashed **incrementally** (`deposit_hash`, `occ_hash`, `nav_version`); `MapData.hash_state(buf)` appends `[w, h, deposit_hash, occ_hash, nav_version]`; a test recomputes from scratch. | Keeps the 20-tick checksum O(1). |
| D-20 | Data files: `terrain.json` (types → kinds, flags, colours), `map_gen.json` (generator), `movement.json` (turn modes, air kinematics, formation switch; engineering constants such as path budgets stay compile-time constants of `SimMoveConfig`). **No** movement-profile or footprint JSON: unit numbers come from `DefUnit`/`DefMoveTable`/`movement_defaults`, footprints from `DefStructure` + economy's `structure_rules.json`. | No second authority for numbers owned elsewhere. |

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

One class per file, snake_case file names, ≤ ~1500 lines each. Paths are relative to `game/`. Line estimates are for planning (§11).

### 2.1 `src/map/` (prefix `Map*`)

| File | `class_name` | Responsibility | ~LOC |
|---|---|---|---|
| `map_terrain.gd` | `MapTerrain` | Terrain-type ids, type→`TerrainKind` table, flags, nav-profile helpers (`profile_of`, `nav_size`), speed/weight/step tables derived from `DefMoveTable`, land-guarantee set; built from `terrain.json` + `DefMoveTable` (`MapTerrain.from_dict(d, moves)`; held by `GameData.terrain`). | 380 |
| `map_data.gd` | `MapData` | All layers + lists, predicates, `finalize()`, `clone_for_world()`, structure `occupy/vacate`, deposits/harvest, hashes, `to_bytes/from_bytes`, view-layer accessors, `make_flat`. | 1200 |
| `map_nav.gd` | `MapNav` | Owned by `MapData`. Per-profile weights, clearance, passability/LOS/cost queries, nearest-passable, dirty tracking, graph registry, cost estimates, region ids. | 950 |
| `map_nav_graph.gd` | `MapNavGraph` | One abstract block-component graph for a (profile,size): build, incremental relink, connected components, abstract A*. | 800 |
| `map_path_search.gd` | `MapPathSearch` | Resumable path search state machine (LOS → fine → abstract → corridor → smooth); scratch buffers. | 1100 |
| `map_footprint.gd` | `MapFootprint` | Static helper: footprint cell lists from `(fp_w, fp_h, fp_mask, orient, cx, cy)`, rotation of authored offsets, oriented sizes. | 200 |
| `map_build_rules.gd` | `MapBuildRules` | Terrain-side placement predicates for economy's `SimPlacement`: terrain/buildable/no-build cells, dock shoreline + berth rule, scan helper for AI. | 300 |
| `map_regions.gd` | `MapRegions` | **Optional (P3)** AI static analysis: regions, chokepoints. Not needed while `AiRouteGraph` exists (§5.13). | 650 |
| `map_gen_params.gd` | `MapGenParams` | Generator parameters from `config.map`, defaults, validation, canonical int serialisation. | 220 |
| `map_gen_tables.gd` | `MapGenTables` | Parsed `map_gen.json` (family parameters, deposit classes, neutral catalogue rules). | 150 |
| `map_generator.gd` | `MapGenerator` | Orchestration: phases, attempts, repair levels, progress callbacks, `validate_params`, telemetry report. | 500 |
| `map_gen_job.gd` | `MapGenJob` | Sliceable generation job for the loading screen (worker thread or stage-sliced): `begin/step/progress_pct/result/cancel`. | 200 |
| `map_gen_noise.gd` | `MapGenNoise` | Integer hash (`mix32`), lattice value noise, fBm, percentile helpers. | 250 |
| `map_gen_symmetry.gd` | `MapGenSymmetry` | Symmetry groups: `fold`, `img_pt`, start canonical anchors, start ordering by angle. | 450 |
| `map_gen_terrain.gd` | `MapGenTerrain` | Phase A: height, family classification, terraces/cliffs/ramps, water, moat ring, marsh, urban lattice, rim. | 1000 |
| `map_gen_layout.gd` | `MapGenLayout` | Phase B: primitives (`paint_disc2/seg2/route2`), starts, bay, gates, roads, fields, neutrals, beaches, flags. | 1100 |
| `map_gen_view.gd` | `MapGenView` | View layers: corner heights, moisture, shore distance, road polylines. | 250 |
| `map_gen_validate.gd` | `MapGenValidate` | Public validation V1–V12 + metrics + repair-level policy. | 650 |
| `map_gen_template.gd` | `MapGenTemplate` | Safe fallback map; flat/corridor/maze/urban fixture maps for tests. | 350 |

### 2.2 `src/sim/` (prefix `Sim*`; component under `src/sim/comp/`)

| File | `class_name` | Responsibility | ~LOC |
|---|---|---|---|
| `sim_move_config.gd` | `SimMoveConfig` | All movement enums (states, flags, goal kinds, result codes, air modes, turn modes, hash layers), tuning constants. | 250 |
| `comp/sim_move_comp.gd` | `SimMoveComp` | The `move` slot component (fields §4.4) + `hash_into` (stub created by sim_core task SC-04, body owned here). | 300 |
| `sim_move_profiles.gd` | `SimMoveProfiles` | Per-`def_idx` movement profile arrays derived from `DefUnit`, `DefMoveTable`, `DefBodyTable`, `movement_defaults`, `movement.json`. | 300 |
| `sim_path_service.gd` | `SimPathService` | Request queue, priorities, budget, cache, delivery, cancellation, repath policy hooks. | 900 |
| `sim_steering.gd` | `SimSteering` | Pure static integer math: angle diff, turn step, speed target, arrival, reverse decision. | 350 |
| `sim_separation.gd` | `SimSeparation` | Canonical per-layer bucket grids, neighbour scan, push weights, idle stride. | 450 |
| `sim_movement_system.gd` | `SimMovementSystem` | Stage 6 `SimSystem`: hooks (`init_world/update/on_spawn/on_dying/on_removed/hash_state`), phases A/B/C, terrain rule, medium switching, stuck detection, strided maintenance, adapters to abilities/combat. | 1300 |
| `sim_movement.gd` | `SimMovement` | Static facade: the movement primitives other domains call (§3.10). | 550 |
| `sim_formation.gd` | `SimFormation` | Slot assignment for same-tick group moves. | 350 |
| `sim_order_move.gd` | `SimOrderMove` | `SimOrderHandler` for `T_MOVE`, `T_PATROL`, `T_FOLLOW`, `T_FACE` (one class, four registered instances). | 450 |
| `sim_order_air.gd` | `SimOrderAir` | `SimOrderHandler` for `T_LAND`. | 100 |
| `sim_order_cargo.gd` | `SimOrderCargo` | `SimOrderHandler` for `T_LOAD`, `T_UNLOAD`, `T_GARRISON` (approach and positioning). | 350 |
| `sim_air_move.gd` | `SimAirMove` | Flight model, orbit/hover, takeoff/landing kinematics, layer flips. | 900 |
| `sim_exit_move.gd` | `SimExitMove` | `find_free_cell_near`, `eject_units_from_rect`, scripted glide, sidestep requests, spawn-point helper. | 500 |

### 2.3 Data and tests

| Path | Purpose |
|---|---|
| `data/balance/terrain.json` | 16 terrain types: kind, flags, buildable rule, minimap colour (§7.1). |
| `data/balance/movement.json` | Turn modes per class/size, air kinematics, formation switch (§7.2). Everything else comes from `global.json` (`movement_classes`, `size_classes`, `movement_defaults`, `naval`, `aircraft`). |
| `data/balance/map_gen.json` | Generator tuning: family parameters, deposit classes, layout, neutral rules (§7.4). |
| `tests/test_map_*.gd`, `tests/test_move_*.gd`, `tests/support/map_png.gd` | See §10 (unit, scenario, determinism, visual; the PNG dumper is a test helper, not shipped code). |

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

### 3.1 Conventions

* **Cell vs unit.** A *cell index* `i = cy * map.w + cx` (int32). A *position* is `(x, y)` in units, `cx = x >> 10`. `MapData.cell_x(i)` = `i % w`, `cell_y(i)` = `i / w`. Positions handed back from map functions are returned through **out-parameters** (`PackedInt32Array` of length ≥ 2, `out[0]=x, out[1]=y`) or as a cell index — never `Vector2i` (DR-1).
* **Profiles.** `np` is a `MapTerrain.NP_*` value (0..6); `size` is `MapTerrain.SZ_1..SZ_3`; `mc` is a `MoveClass` (0..8); `layer` is a `SimEntity.Layer` (0 ground, 1 air, 2 surface, 3 underwater).
* **Errors.** Functions that can fail return an error code or `-1`; nothing throws. Precondition violations `push_error` and return a safe value.
* **Static functions** never touch global state; every stateful object is reachable from `SimWorld` (DR-9). Systems never store `SimWorld` (sim_core §3.1): every entry point takes `world`.
* **Packed arrays alias** in 4.7.2: `.duplicate()` whenever an array crosses an ownership boundary.
* Every public method is documented with `##` comments in the implementation (§13 rule 5).

### 3.2 `MapTerrain` (instance = parsed `terrain.json` + `DefMoveTable`; held by `GameData.terrain`)

```gdscript
class_name MapTerrain extends RefCounted
# ---- terrain types (byte values stored in MapData.terrain), 16 ----
const T_DEEP := 0;  const T_SHALLOW := 1;  const T_FORD := 2;   const T_BEACH := 3
const T_GRASS := 4; const T_DIRT := 5;     const T_SAND := 6;   const T_ROCK := 7
const T_FOREST := 8; const T_ROAD := 9;    const T_PAVEMENT := 10; const T_RUBBLE := 11
const T_URBAN := 12; const T_CLIFF := 13;  const T_MOUNTAIN := 14; const T_MARSH := 15
const COUNT := 16
# ---- TerrainKind (mirror of DefEnums.TerrainKind, TAXONOMY §11; equality asserted at load) ----
const TK_ROAD := 0; const TK_OPEN := 1; const TK_ROUGH := 2; const TK_FOREST := 3
const TK_MARSH := 4; const TK_SHALLOW := 5; const TK_DEEP := 6; const TK_CLIFF := 7; const TK_COUNT := 8
# ---- MoveClass (mirror of DefEnums.MoveClass, TAXONOMY §11; equality asserted at load) ----
const MC_FOOT := 0; const MC_WHEELED := 1; const MC_TRACKED := 2; const MC_AMPHIBIOUS := 3; const MC_NAVAL := 4
const MC_SUBMERGED := 5; const MC_AIR_FIXED := 6; const MC_AIR_HOVER := 7; const MC_STATIC := 8; const MC_COUNT := 9
# ---- nav profiles (a profile = a class with its own weight vector; air and static have none) ----
const NP_FOOT := 0; const NP_WHEELED := 1; const NP_TRACKED := 2; const NP_AMPH := 3
const NP_NAVAL := 4; const NP_NAVAL_DEEP := 5; const NP_SUB := 6; const NP_COUNT := 7; const NP_NONE := -1
const SZ_1 := 1; const SZ_2 := 2; const SZ_3 := 3
const DEEP_ONLY_RADIUS := 922      # units (0.9 cell): naval hulls with radius >= this are deep-water only (TAXONOMY §6)
const LARGE_HULL_RADIUS := 1100    # units: naval hulls above this need 5-wide channels (SZ_3)
# ---- terrain flag bits (terrain.json "flags") ----
const TF_WATER := 1        # kind SHALLOW or DEEP: is_water(), F_ON_WATER, water_mult_bp applies
const TF_LAND := 2
const TF_BUILD := 4        # standard structures may stand here
const TF_BUILD_SHORE := 8  # only shoreline structures (Dock) may stand here (beach)
const TF_CROSSING := 16    # intended ground crossing (ford): part of the land-only guarantee although its kind is SHALLOW

static func from_dict(d: Dictionary, moves: DefMoveTable) -> MapTerrain  ## Parses terrain.json; push_error + null on schema error; derives every table below from `moves`.
static func load_default() -> MapTerrain          ## Cached singleton built from res://data/balance/terrain.json and the default DefMoveTable (global.json). Tests and single-argument MapGenerator.generate().
static func profile_of(move_class: int, radius_u: int) -> int   ## FOOT->NP_FOOT, WHEELED->NP_WHEELED, TRACKED->NP_TRACKED, AMPHIBIOUS->NP_AMPH, NAVAL->NP_NAVAL_DEEP if radius_u >= DEEP_ONLY_RADIUS else NP_NAVAL, SUBMERGED->NP_SUB, else NP_NONE
static func nav_size(move_class: int, radius_u: int) -> int     ## FOOT -> SZ_1; NAVAL/SUBMERGED with radius_u > LARGE_HULL_RADIUS -> SZ_3; every other profile -> SZ_2
static func mc_of_profile(np: int) -> int         ## NP_NAVAL_DEEP -> MC_NAVAL
func kind_of(t: int) -> int                       ## terrain type -> TerrainKind
func flags(t: int) -> int
func speed_bp(mc: int, t: int) -> int             ## DefMoveTable.speed_bp[mc * 8 + kind_of(t)]; 0 = impassable, 10000 = nominal
func weight(np: int, t: int) -> int               ## derived path weight 10..40, 0 = blocked (§5.1); NP_NAVAL_DEEP additionally blocks TK_SHALLOW
func step_o(w: int) -> int                        ## (10*w+8)>>4, table lookup, w in 0..40
func step_d(w: int) -> int                        ## (14*w+8)>>4
func guarantee(t: int) -> bool                    ## land-only guarantee set (§5.12): (TF_LAND or TF_CROSSING) and speed_bp > 0 for foot, wheeled AND tracked
func minimap_rgba(t: int) -> int                  ## 0xRRGGBBAA (view only)
func table_hash() -> int                          ## FNV-1a over all converted tables (DR-10 data hash input)
```

### 3.3 `MapData`

```gdscript
class_name MapData extends RefCounted
const RIM_W := 6            # unplayable rim (open/urban: 2 MOUNTAIN + 4 CLIFF; coast: DEEP)
const NAV_BORDER := 2       # cells at Chebyshev distance < 2 from the edge are impassable in every nav profile (also on make_flat maps)
# ---- static flag bits (MapData.flags) ----
const SF_SHORE := 1        # land cell 4-adjacent to water (dock/landing/foam)
const SF_NOBUILD := 2      # static no-build (deposit ring, neutral lots, rim)
const SF_BLOCK := 4        # static blocker prop (boulder, barricade): impassable to ALL profiles
const SF_START := 8        # inside a start disc (analysis only; no rule effect)
const SF_RAMP := 16        # cliff ramp cell (view mesh)
# ---- list strides (public PackedInt32Array fields) ----
const SPAWN_STRIDE := 6    # [start_index, cell, facing (toward centre), orbit (symmetry image k), team_hint (index & 1), reserved]
const NEUTRAL_STRIDE := 8  # [kind (index into neutral_ids), cell (top-left), w, h, variant, flags, orbit, reserved]
const FIELD_STRIDE := 10   # [id (1-based), center_cell, radius, cells, total, kind (FK_*), orbit, hint_cell, klass (0 standard, 1 rich), owner_start (-1 shared)]
const FK_START := 0; const FK_NATURAL := 1; const FK_NATURAL_RICH := 2; const FK_FURTHER := 3; const FK_CONTESTED := 4
# ---- identity (sim_core R7 names) ----
var w: int; var h: int; var n: int                 # cells; n = w*h
var map_hash: int                                   # u32, set by finalize(): FNV-1a over the static layers; lobby/replay handshake
var start_cells: PackedInt32Array                   # [cx0, cy0, cx1, cy1, ...] in START ORDER (counter-clockwise from the +x axis, i.e. adjacent indices are adjacent positions); HQ centre cell
var objects: Array                                  # [{def_id: String, cx: int, cy: int}] neutral structures, top-left cell, deterministic order (list order of `neutrals`); deposits are NOT listed here (they are `fields`, R1)
var seed_value: int; var family: int; var biome: int; var slots: int; var players: int; var gen_version: int    # biome: 0 temperate, 1 arid, 2 arctic, 3 urban (render.md §13-9)
var neutral_ids: PackedStringArray                  # index space of `neutrals[kind]`
var gen_params: PackedInt32Array                    # MapGenParams.to_ints() of the generating call (empty for make_flat); lets MapGenValidate.validate(map) recover `resources`, `start_near_water`, …
var tt: MapTerrain; var nav: MapNav; var nav_version: int
# ---- construction / lifecycle ----
static func create(tt: MapTerrain, size: int, fill_type: int = MapTerrain.T_GRASS) -> MapData
    ## Zeroed layers, uniform terrain, RIM_W rim (mountain/cliff). Used by the generator, templates and tests.
static func make_flat(w: int, h: int, start_cells: PackedInt32Array, map_hash: int) -> MapData
    ## sim_core R7 test map: all GRASS, no rim (only NAV_BORDER), the given start cells, `map_hash` pinned to the argument (finalize() does not overwrite it).
func finalize() -> void
    ## Once, after generation/load: (1) SF_SHORE; (2) `kind` and `buildable` layers; (3) water components (`water_comp`, sizes); (4) `shore_dist` if absent; (5) map_hash / visual_hash; (6) dynamic init:
    ## deposit = deposit_max, field_left, occ = -1, hashes; (7) MapNav weights + clearance for every used profile, graphs for every (profile,size) with >= 100 passable cells (`nav.prepare_all()`); (8) lock static layers.
func clone_for_world() -> MapData
    ## sim_core R7. Per-world instance: static arrays shared (PackedArray copy-on-write), dynamic arrays and the nav layers/graphs copied. SimWorld MUST own its own instance (two worlds side by side, DR-9).
func hash_state(buf: PackedInt32Array) -> void      ## sim_core R7: appends [w, h, deposit_hash, occ_hash, nav_version] (mutable state only; O(1))
func content_hash() -> int                          ## net XR-12: recomputes the u32 hash of all static layers from scratch; equals map_hash for an unmodified map
func to_bytes() -> PackedByteArray                  ## Header + DEFLATE(all static layers + lists + view layers). Byte-stable for equal maps.
static func from_bytes(tt: MapTerrain, b: PackedByteArray) -> MapData   ## null (+push_error) if corrupt/version mismatch; calls finalize().
func visual_hash() -> int                           ## FNV-1a-32 over heights/moisture/roads/deco (view only; mismatch = warning, not a desync)
func recompute_dynamic_hash() -> int                ## O(n) from scratch; tests assert == checksum_dynamic()
func checksum_dynamic() -> int                      ## O(1): mix(deposit_hash, occ_hash, nav_version)
func fair_slot_order(players: int) -> PackedInt32Array   ## start indices to fill for `players` (< slots): greedy farthest-point from index 0, ties lowest index (lobby helper)
# ---- coordinates ----
func idx(cx: int, cy: int) -> int
func cell_x(i: int) -> int
func cell_y(i: int) -> int
func in_bounds(cx: int, cy: int) -> bool
func idx_of_units(x: int, y: int) -> int           ## clamps into the map
func center_x(i: int) -> int                       ## (i % w) * 1024 + 512
func center_y(i: int) -> int
# ---- terrain, kinds, speeds ----
func terrain_at(i: int) -> int                     ## MapTerrain.T_*
func kind_at(i: int) -> int                        ## TerrainKind (static `kind` layer)
func kind_at_units(x: int, y: int) -> int
func speed_bp_at(mc: int, i: int) -> int           ## tt.speed_bp(mc, terrain[i]); 0 = impassable (static terrain only)
# ---- predicates used by other domains (all O(1), all pure) ----
func is_water(cx: int, cy: int) -> bool            ## kind SHALLOW or DEEP (fords are water)   [economy, abilities, ai]
func is_land(cx: int, cy: int) -> bool             ## not water (cliffs are land)              [abilities]
func is_buildable(cx: int, cy: int) -> bool        ## static: TF_BUILD terrain, no SF_NOBUILD/SF_BLOCK, inside the interior. Does NOT test structures/units/deposits.   [economy 5.3 rule 3]
func is_shore_buildable(cx: int, cy: int) -> bool ## TF_BUILD or TF_BUILD_SHORE terrain, no SF_NOBUILD/SF_BLOCK (dock footprints)
func is_passable_ground(cx: int, cy: int) -> bool ## static terrain: foot profile weight != 0, ignores structures and NAV_BORDER   [economy 5.3 rule 8 apron]
func passable(cx: int, cy: int, mc: int) -> bool  ## LIVE: nav weight != 0 of profile_of(mc, 500) (the small-hull profile for NAVAL; clearance is not tested — use `nav.passable(np, size, i)` for that), includes structures and NAV_BORDER; air classes -> inside the interior; static -> false   [ai, abilities]
func is_clear(cx: int, cy: int, layer: int) -> bool   ## no static blocker and no structure for an entity of `layer`: GROUND = foot profile passable and occ < 0; SURFACE = naval passable; UNDERWATER = sub passable; AIR = true inside the interior   [abilities unload search]
func water_body_size(cx: int, cy: int) -> int      ## cells of the 4-connected water component (SHALLOW+DEEP+FORD) containing the cell, 0 on land (static, precomputed)   [economy dock rule]
func has_adjacent_water(cx: int, cy: int) -> bool  ## SF_SHORE (land cell 4-adjacent to water)
func region(cx: int, cy: int, mc: int) -> int      ## abstract-graph component id of the cell for the class's (profile, default size), -1 if blocked/no graph   [ai]
func get_family() -> int                            ## FAM_OPEN 0 / FAM_URBAN 1 / FAM_COAST 2 (== `family`; a method because ai.md calls family())
# ---- structures (called by production/economy/cleanup) ----
func occupy(sid: int, cells: PackedInt32Array) -> int
    ## occ[cell] = sid on every cell; weight 0 in ALL nav profiles there; MapNav.on_cells_changed(bbox); nav_version++. Precondition: cells buildable and free (asserted in debug).
    ## Returns the changed bbox packed as (cx0 << 24) | (cy0 << 16) | (cx1 << 8) | cy1 (coordinates <= 255).
func vacate(sid: int) -> int                       ## Exact inverse (stored cell list); weights restored from terrain/flags; returns the packed bbox.
func structure_at(i: int) -> int                    ## structure entity id or -1  (= world.struct_grid of economy/render; there is exactly one copy)
# ---- deposits (economy; per-cell stock, FRAMEWORK §5.8) ----
func deposit_at(i: int) -> int
func field_of_cell(i: int) -> int                  ## 0 = none else 1-based field id
func field_remaining(field_id: int) -> int
func harvest_cell(i: int, want: int) -> int        ## removes min(want, deposit[i]); updates deposit_hash, field_left, dirty list; returns taken
func harvest_field(field_id: int, from_cell: int, want: int) -> int
    ## Takes up to `want` from the NON-EMPTY cell of the field nearest to `from_cell` (Chebyshev, then row-major index; the field's cell list is precomputed and sorted), one cell per call; returns taken (0 = field empty). A load of 600 empties exactly one 600-credit cell.
func regrow_field(field_id: int, amount: int) -> int   ## adds up to `amount` to the lowest-index cells below deposit_max; returns added (economy opt-in; FRAMEWORK default: no regrowth)
func nearest_deposit(from_i: int, max_ring: int) -> int    ## deterministic ring search (ring, then row-major) for a non-empty cell; -1 if none
func drain_deposit_dirty(out: PackedInt32Array) -> int     ## output-only list for the view; clears it; NOT checksummed
func deposit_fields() -> Array                     ## Array[Dictionary] {id, cx, cy, radius, klass_economy (0 start, 1 expansion, 2 rich), kind, cells, total}: economy's SimDepositTable build input (economy.md §13-13)
func neutral_spawns() -> Array                      ## Array[Dictionary] {type: String, cx, cy} = `objects` (economy.md §13-13 name)
# ---- view layers (read-only; render.md §13-9; not in map_hash) ----
var heights: PackedInt32Array      # (w+1)*(h+1) lattice-corner heights in 1/32 m
var moisture: PackedByteArray      # w*h, 0..255
var shore_dist: PackedByteArray    # w*h chamfer 3-4 distance from land in 1/3 cell, 0 on land, saturating 255
var roads: Array                   # Array[PackedInt32Array] polylines [x0,y0,x1,y1,...] in 1/16 cell (trunk roads of open/coast maps; urban streets are terrain)
var water_level_u: int             # sea plane height in 1/32 m (0 on dry maps)
```
Public read-only fields (no accessor cost): `terrain, kind, height, flags, buildable, deco, field_of: PackedByteArray`, `deposit, deposit_max, occ: PackedInt32Array`, `spawns, neutrals, fields: PackedInt32Array`. Full table in §4.1. **Other domains must not write these arrays directly** (the setters maintain hashes and nav). The dynamic part is *only* `occ`, `deposit`, `field_left` and the nav layers; everything else is immutable after `finalize()` (writes `push_error`).

### 3.4 `MapNav` (owned by `MapData` as `map.nav`; sim reaches it as `world.map.nav`)

```gdscript
class_name MapNav extends RefCounted
func w_at(np: int, i: int) -> int                            ## live weight, 0 = blocked (terrain, SF_BLOCK, structure, NAV_BORDER)
func clear_at(np: int, i: int) -> int                        ## 0..3 clearance (foot: 0/1)
func passable(np: int, size: int, i: int) -> bool            ## clear_at(np,i) >= size
func passable_units(np: int, size: int, x: int, y: int) -> bool
func los(np: int, size: int, c0: int, c1: int) -> bool       ## integer Bresenham, diagonal corner rule, every cell passable(size)
func los_cost(np: int, size: int, c0: int, c1: int) -> int   ## sum of step costs along the same line, -1 if blocked
func nearest_passable(np: int, size: int, i: int, max_ring: int) -> int   ## ring order then row-major; -1 if none
func prepare(keys: PackedInt32Array) -> void                 ## build abstract graphs for keys = np*4+size (idempotent)
func prepare_all() -> void                                   ## the eight keys that can occur — FOOT×1, WHEELED×2, TRACKED×2, AMPH×2, NAVAL×2, NAVAL_DEEP×{2,3}, SUB×2 — for every profile with >= 100 passable cells (a dry map gets four); MapData.finalize() calls it
func has_graph(np: int, size: int) -> bool
func node_of(np: int, size: int, i: int) -> int              ## abstract node id or -1 (no graph -> -1)
func same_region(np: int, size: int, a: int, b: int) -> bool ## abstract connectivity; true if no graph and both passable (conservative)
func region_id(np: int, size: int, i: int) -> int            ## abstract component id (cc) or -1
func region_size(np: int, size: int, i: int) -> int          ## cells in i's abstract component (0 if none/no graph)
func estimate_cost(np: int, size: int, a: int, b: int) -> int   ## cost units (10 = one baseline cell); -1 unreachable. = octile(a,rep_S)·w_S/16 + abstract A* cost + octile(rep_G,b)·w_G/16; ~0.3 ms; AI/eta use only.
func on_cells_changed(cx0: int, cy0: int, cx1: int, cy1: int) -> void   ## MapData internal; IMMEDIATE: weights in the rect (clr 0 on blocked cells, 1 on freed cells); DEFERRED: clearance in rect+3 and block relabel (queued for flush_dirty)
func flush_dirty(budget: int) -> int                         ## drains deferred work: clearance of queued rects (4 units each) then dirty (block,graph) relabels (1 unit each); returns units consumed (<= budget)
func pending_dirty() -> int
func validate_against_terrain() -> bool                      ## test hook: recompute everything from scratch and compare
```

### 3.5 `MapPathSearch` (one instance per `SimPathService`; scratch arrays sized `w*h`)

```gdscript
class_name MapPathSearch extends RefCounted
const ST_IDLE := 0; const ST_RUNNING := 1; const ST_DONE := 2; const ST_PARTIAL := 3; const ST_NO_PATH := 4
var status: int                       # ST_*
var path: PackedInt32Array            # result waypoints (cell indices), start cell EXCLUDED, last = goal (or best node when PARTIAL)
var path_cost: int                    # unsmoothed fine cost of the accepted route (cost units)
var expanded: int                     # fine+abstract expansions used (telemetry)
func _init(nav: MapNav)
var force_mode: int = 0               # test hook: 0 auto (§5.3.3), 1 fine A* only, 2 corridor only
func begin(np: int, size: int, start: int, goal: int, goal_r: int, avoid: PackedInt32Array) -> void
    ## goal_r: stop when Chebyshev distance to goal <= goal_r cells (0 = exact). avoid: <=16 cells treated as blocked for this search only.
    ## If a graph exists and start/goal are in different abstract components: status = ST_NO_PATH immediately (expanded = 0); the
    ## SimPathService, not the search, chooses an alternative reachable goal (§5.3.5).
func step(budget: int) -> int         ## runs until done or `budget` units consumed; returns units consumed (>=1 while RUNNING). Deterministic in `budget`.
func cancel() -> void
func state_ints(buf: PackedInt32Array) -> void   ## the resumable state (enters SimPathService.hash_state)
```

### 3.6 Footprints and terrain-side build rules

```gdscript
class_name MapFootprint extends RefCounted     # static helpers; the numbers (fp_w, fp_h, fp_mask, exit, apron, dock, berth, pads) belong to DefStructure / economy's structure_rules.json
static func cells(fp_w: int, fp_h: int, fp_mask: PackedByteArray, orient: int, cx: int, cy: int, out: PackedInt32Array) -> int
    ## Cell indices of the SOLID cells (fp_mask empty = full rectangle, else row-major fp_w*fp_h with 1 = blocked) when the authored shape is rotated by `orient` (0..3 = 0/90/180/270° clockwise, x east, y south)
    ## and its top-left cell (of the ORIENTED bounding box) is (cx, cy). Returns the count; -1 if any cell is outside the map.
static func oriented_size(fp_w: int, fp_h: int, orient: int) -> int    ## packed (w << 8) | h after rotation (swapped for odd orient)
static func rotate_offset(fp_w: int, fp_h: int, orient: int, dx: int, dy: int, out: PackedInt32Array) -> void
    ## An authored offset (dx,dy) in a w×h footprint maps to  0: (dx,dy)   1: (h-1-dy, dx)   2: (w-1-dx, h-1-dy)   3: (dy, w-1-dx);  out[0]=dx', out[1]=dy'. Angles (exit direction, dock facing) add orient*1024.

class_name MapBuildRules extends RefCounted    # pure terrain/occupancy predicates; economy's SimPlacement composes them with radius, prerequisites, units, aprons, zones
const PR_OK := 0; const PR_OUT_OF_BOUNDS := 1; const PR_TERRAIN := 2; const PR_OCCUPIED := 3; const PR_NOBUILD := 4; const PR_NEEDS_WATER := 5; const PR_WATER_EXIT := 6
static func check_land(map: MapData, cells: PackedInt32Array, shore_ok: bool = false, margin: int = 1) -> int
    ## First failing rule, in this order: any cell outside [margin, w-margin) -> PR_OUT_OF_BOUNDS; not buildable terrain (is_buildable, or is_shore_buildable when shore_ok) -> PR_TERRAIN; SF_NOBUILD/SF_BLOCK -> PR_NOBUILD; occ >= 0 -> PR_OCCUPIED.
static func check_berth(map: MapData, berth_cells: PackedInt32Array, min_body: int = 30) -> int
    ## Dock shoreline rule: every berth cell is DEEP water (a ship of any size can leave), all in one water body of >= min_body cells (map.water_body_size) whose naval component is >= 100 cells,
    ## else PR_NEEDS_WATER (not all water) / PR_WATER_EXIT (pond or land-locked).
static func scan(map: MapData, fp_w: int, fp_h: int, fp_mask: PackedByteArray, orient: int, ccx: int, ccy: int, radius: int, out: PackedInt32Array, max_out: int) -> int
    ## AI helper: valid top-left cells (check_land == PR_OK) within Chebyshev `radius` of (ccx,ccy), nearest ring first then row-major; bounded by max_out and 4*radius^2 checks.
```

### 3.7 Generator

```gdscript
class_name MapGenParams extends RefCounted
const VERSION := 2                                            # generator algorithm version — bump on ANY output-affecting change
const FAM_OPEN := 0; const FAM_URBAN := 1; const FAM_COAST := 2      # == net.md 7.1 `map.family`
var size: int = 128; var family: int = 0; var seed_value: int = 1; var slots: int = 2   # seed_value = net `map.seed` (`seed` would shadow the GDScript builtin); slots = net `map.layout_players` (2,3,4,6,8)
var water_pct: int = -1     # 0..40, -1 = family default (open 0, urban 0, coast 22)
var density: int = 50       # 0..100 clutter (forest/rock/cliff/urban lots)
var resources: int = 50     # 0..100; credit scale = (50 + resources) % of the tabled per-cell amounts (50 %..150 %)
var neutrals: int = 50      # 0..100 neutral-structure density
var biome: int = 0          # 0 temperate, 1 arid, 2 arctic (urban family forces 3)
var start_near_water: bool = false   # coast only: every start gets a bay with a valid Dock site inside the build radius (qa.md XR-24)
static func from_config(map_cfg: Dictionary) -> MapGenParams    ## reads family, size, seed (0..2^32-1), layout_players, params{water_pct, density, resources, neutrals, biome, start_near_water}; unknown keys ignored
static func min_size(slots: int) -> int                         ## {2: 96, 3: 112, 4: 128, 6: 160, 8: 192}
static func recommended_size(players: int) -> int              ## {2:128, 3:144, 4:160, 5..6:192, 7..8:224}
static func slots_for(players: int) -> int                     ## smallest of {2,3,4,6,8} >= players
func validate() -> String                                      ## "" if OK (size multiple of 8 in [max(96, min_size(slots)), 256], family 0..2, slots in {2,3,4,6,8}, ranges)
func to_ints() -> PackedInt32Array                             ## canonical serialisation (params hash / replay header)

class_name MapGenerator extends RefCounted
static func validate_params(family: int, size: int, layout_players: int) -> String    ## net XR-12 / lobby: "" = ok
static func generate(map_cfg: Dictionary, tables: MapGenTables = null, progress: Callable = Callable()) -> MapData
    ## PURE function of `config.map` (sim_core R8, qa XR-24): same dictionary => byte-identical map on every platform. tables == null => MapGenTables.load_default().
    ## progress.call(stage: int, pct: int) is invoked on the CALLING thread between stages (pct monotonic 0..100). Never returns null: worst case is the safe template.
static func generate_params(tt: MapTerrain, params: MapGenParams, tables: MapGenTables, progress: Callable = Callable()) -> MapData
static func generate_report(map_cfg: Dictionary, tables: MapGenTables = null) -> Dictionary
    ## {"map": MapData, "attempts": int, "layout_level": int, "template": bool, "failures": Array[String], "ms": Dictionary}
    ## `ms` (Time.get_ticks_usec based) is TELEMETRY ONLY — never used in any decision.

class_name MapGenJob extends RefCounted          # net.md NetWorldJob adapter (XR-12/XR-14): time-sliceable generation
static func begin(map_cfg: Dictionary, tables: MapGenTables = null, use_thread: bool = true) -> MapGenJob
func step(budget_us: int) -> bool     ## true when finished. Threaded mode: polls the worker (< 50 µs, never blocks). Unthreaded mode: runs whole stages until budget_us is exhausted (a stage is <= ~0.5 s at 256², so it may overshoot the budget by one stage). Slicing never changes the result.
func progress_pct() -> int            ## 0..100, monotonic
func result() -> MapData              ## valid after step() returned true (finalized, nav prepared); null on cancel
func cancel() -> void

class_name MapGenValidate extends RefCounted     # public: DA-29, map_validator, CI
static func validate(map: MapData) -> PackedStringArray       ## [] = valid; entries are "V1 starts_disconnected" … (rules V1–V12, §5.12.6)
static func metrics(map: MapData) -> Dictionary                ## {exits_per_start: PackedInt32Array, credits_reachable_per_start: PackedInt32Array, water_required: false, route_pct: int, fairness_spread_permille: int, dock_sites: PackedInt32Array, neutrals: int}
```

### 3.8 `MapRegions` (**optional, P3**; only if the AI domain drops its own `AiRouteGraph`)

```gdscript
class_name MapRegions extends RefCounted
static func build(map: MapData) -> MapRegions                 ## deterministic; <= 150 ms at 256^2 (§5.13)
var region_of: PackedInt32Array; var region_count: int; var region_center: PackedInt32Array; var region_area: PackedInt32Array
var chokes: PackedInt32Array           # stride 6: [region_a, region_b, center_cell, width_cells, min_clearance, kind]  kind: 0 open border, 1 choke (<=8 wide)
func region_neighbors(r: int) -> PackedInt32Array
func region_path(from_r: int, to_r: int) -> PackedInt32Array   ## fewest chokes then widest; deterministic tie-break lowest id
func choke_between(a: int, b: int) -> int                     ## index into chokes or -1
```

### 3.9 Debug images (tests only)

`tests/support/map_png.gd` (`MapPng.terrain(map, scale) -> Image`, `MapPng.overlay(...)`) dumps terrain, fields, neutrals, starts and nav components for the visual tests of §10.5. It is **not** shipped code: render owns the real textures (`ViewTerrainSource`, `ViewMinimapSource`).

### 3.10 Sim-side API

#### 3.10.1 `SimMovementSystem` (pipeline stage 6)

```gdscript
class_name SimMovementSystem extends SimSystem
func system_name() -> String                                 # "movement"
func init_world(world: SimWorld) -> void
    ## Once, after all systems exist and BEFORE initial entities: (1) SimMoveProfiles.build(world.data); (2) resolve adapters by has_method() on the stage objects (`ASSUMPTION(abilities)`, `ASSUMPTION(combat)`): `_speed` (speed_units), `_immob` (is_immobile,
    ## is_turn_locked, request_pack), `_supp` (suppression_speed_bp), `_cargo` (SimTransport) — any may be null (fallbacks in §5.1/§5.8); (3) path service + separation grids; (4) register the order handlers
    ## world.orders.register_handler(T_MOVE|T_PATROL|T_FOLLOW|T_FACE, SimOrderMove.new(type)), (T_LAND, SimOrderAir.new()), (T_LOAD|T_UNLOAD|T_GARRISON, SimOrderCargo.new(type)); (5) world.map.nav.prepare_all() if finalize() did not.
func update(world: SimWorld) -> void                         # stage 6, fixed order (§3.11)
func on_spawn(world: SimWorld, e: SimEntity) -> void         # UNIT entities whose def can move (move class != STATIC and speed > 0) get e.move = SimMoveComp.new() from SimMoveProfiles; appends the id to `_movers` (ids are monotonic => stays ascending)
func on_dying(world: SimWorld, e: SimEntity) -> void         # cancels the path request; passengers are abilities' business (SimTransport.eject_all)
func on_removed(world: SimWorld, e: SimEntity, reason: int) -> void   # removes the id from `_movers`
func on_owner_changed(world: SimWorld, e: SimEntity, old_owner: int) -> void   # goal cleared (orders are cleared by core)
func hash_state(world: SimWorld, buf: PackedInt32Array) -> void       # SimPathService state ints (§8); everything else is in components
func dump_state(world: SimWorld) -> Dictionary
var path: SimPathService; var sep: SimSeparation; var prof: SimMoveProfiles
static func of(world: SimWorld) -> SimMovementSystem         # `world.stages[SimPipeline.STAGE_MOVEMENT]` (= 6); sim_core is asked to expose `world.movement` (§13-1)
```

#### 3.10.2 `SimMovement` — the static facade (every other domain calls only this)

Naming: the first block carries the names combat.md §3.8 and economy.md §3.7/§13-15 already call, the second block is the richer API. Combat's `SimMovement.X` and economy's `world.movement.X` are the same functions (economy's wrappers add the `world` argument, §12 R6).

```gdscript
class_name SimMovement extends RefCounted
# ---- primitives named by combat.md 3.8 / economy.md 13-15 ----
static func move_to(world: SimWorld, e: SimEntity, x: int, y: int, flags: int = 0) -> void     # = go_to(..., flags -> opts)
static func move_to_range(world: SimWorld, e: SimEntity, tx: int, ty: int, range_units: int) -> void   # = go_near
static func stop(world: SimWorld, e: SimEntity, hard: bool = false) -> void   # soft = decelerate; hard = speed 0 now. Clears goal, cancels the path request, wakes the unit for separation.
static func turn_to(world: SimWorld, e: SimEntity, facing_bat: int) -> void   # = face: turn in place (INSTANT/PIVOT/BANK-rotor) or hull-only for ARC; done when |err| < 64
static func is_moving(e: SimEntity) -> bool                                    # |spd| > 0 or MS_MOVING/WAIT_PATH   (mirrors F_MOVING)
static func request_move(world: SimWorld, e: SimEntity, x: int, y: int, flags: int = 0) -> bool   # economy name (returns false if refused: immobile/def cannot move)
static func at_goal(e: SimEntity) -> bool                                      # state MS_ARRIVED
static func path_failed(e: SimEntity) -> bool                                  # state MS_NO_PATH (RS_NO_PATH) — a partial path that was walked to its end counts as arrived
static func find_free_cell_near(world: SimWorld, cell: int, layer: int, max_radius: int) -> int
    # nearest cell (ring order, then row-major = lowest index) that is passable for the layer's default profile/size, unoccupied by a structure and holds no mover disc; -1 if none (economy.md 5.4 exit search)
static func eject_units_from_rect(world: SimWorld, x0: int, y0: int, x1: int, y1: int, team: int) -> void
    # units of `team` (same team as the placer) whose centre lies in the cell rect [x0..x1]x[y0..y1] (inclusive) are moved out, ascending id: each to the nearest free cell outside the rect (ring order, max 6 rings) via world.set_pos, speed 0, goal cleared; no free cell => the unit stays and MS_EVICT starts
# ---- goals (return false and set result RS_* if refused: RS_IMMOBILE for a deployed/packing unit — the call also asks abilities.request_pack(e), at most once per 20 ticks, so a retry succeeds after unpacking; RS_NO_MOVE for a def that cannot move) ----
static func go_to(world: SimWorld, e: SimEntity, x: int, y: int, opts: int = 0) -> bool
static func go_near(world: SimWorld, e: SimEntity, x: int, y: int, range_units: int, opts: int = 0) -> bool
static func approach_entity(world: SimWorld, e: SimEntity, target_id: int, range_units: int, opts: int = 0) -> bool
    # Path to the target's nearest passable cell (structures: nearest cell of the footprint ring); stops as soon as dist(unit centre, target rect) <= range_units. Re-plans when the target moves > 3 cells.
static func follow(world: SimWorld, e: SimEntity, target_id: int, min_d: int, max_d: int, opts: int = 0) -> bool
static func pause(world: SimWorld, e: SimEntity) -> void       # keep goal+path, decelerate to 0 (MS_PAUSED)  [attack-move engagement]
static func resume(world: SimWorld, e: SimEntity) -> void
static func glide(world: SimWorld, e: SimEntity, x: int, y: int, ticks: int, face_angle: int = -1) -> void
    # scripted precise move: straight-line interpolation over EXACTLY `ticks` ticks (>= 1), no path, no terrain rule, immune to separation and not pushing others (MS_GLIDE); sets facing to face_angle (or the glide direction) at the start;
    # ends in MS_ARRIVED at (x,y). Economy's dock-in (12 ticks) / dock-out (8 ticks), undeploy exits.
static func sidestep(world: SimWorld, e: SimEntity, dir_angle: int, dist: int) -> void   # short deterministic goal; used to shove idle allies aside
static func request_layer(world: SimWorld, e: SimEntity, layer: int, ticks: int) -> void  # submarines: SURFACE <-> UNDERWATER after `ticks` (world.set_layer at the end + STATE event); abilities/combat call it
# ---- status (read by handlers, combat, AI, view) ----
static func state(e: SimEntity) -> int                         # MS_*
static func result(e: SimEntity) -> int                        # RS_* of the last finished/failed goal (persists until the next goal)
static func ack(world: SimWorld, e: SimEntity) -> void         # acknowledge a terminal state: MS_ARRIVED/MS_NO_PATH -> MS_IDLE (goal cleared, result kept)
static func dist_to_goal(e: SimEntity) -> int                  # units, exact (Fp.dist)
static func is_on_water(e: SimEntity) -> bool                  # F_ON_WATER
static func speed_q4(e: SimEntity) -> int
static func velocity(e: SimEntity, out: PackedInt32Array) -> void   # out[0], out[1] = displacement applied in the last tick (units/tick), i.e. combat's e.vx/e.vy
static func eta_ticks(world: SimWorld, e: SimEntity, x: int, y: int) -> int   # -1 unreachable; else estimate_cost·1024 / (10 · max(1, speed_units(e))) (terrain % and water ignored, stat modifiers included)
# ---- air primitives (combat.md 3.8 / 13-23) ----
static func air_fly_to(world: SimWorld, e: SimEntity, x: int, y: int) -> void     # fixed-wing: cruise to the point, then hold a pattern (orbit) around it; rotor: cruise, then hover. Layer must already be AIR (see air_takeoff)
static func air_orbit(world: SimWorld, e: SimEntity, cx: int, cy: int, r: int, dir: int = 1) -> void   # r = 0: default radius from movement.json; dir +1/-1
static func air_hover(world: SimWorld, e: SimEntity) -> void                      # rotor: decelerate to a stop and hold; fixed-wing: orbit around the current position at the default radius
static func air_face(world: SimWorld, e: SimEntity, facing_bat: int) -> void      # rotor: yaw in place at turn_rate; fixed-wing: no-op
static func air_takeoff(world: SimWorld, e: SimEntity, ticks: int = 0) -> void  # runway roll / vertical climb; layer -> AIR at alt >= 512 (exactly at tick `ticks` when > 0: combat's takeoff_ticks); STATE takeoff event; then a holding pattern at the takeoff point
static func air_land_at(world: SimWorld, e: SimEntity, x: int, y: int, heading: int = -1, ticks: int = 0) -> void   # approach, descend (exactly `ticks` ticks when > 0: combat's landing_ticks), touch down at (x,y) (a pad cell centre from economy's airfield_pad_cell); layer -> GROUND at touchdown; STATE landed event; heading -1 = straight-in
static func air_at_goal(e: SimEntity) -> bool                                     # fly_to: within arrival radius; land_at: touched down; takeoff: airborne
static func altitude(e: SimEntity) -> int                                         # units, view/audio only
```
Option bits for `go_*` (`opts`): `OPT_SPEED_MATCH = 2`, `OPT_REVERSE_OK = 4`, `OPT_PRECISE = 8`, `OPT_NO_SLOT = 16`, `OPT_ATTACK_MOVE = 32` (locomotion of combat's attack-move: engaged units are `pause`d, not stopped), `OPT_PRIO_ECON = 64` (path-service priority `PRIO_ECON` for goals set by economy/production; the default is `PRIO_ORDER`). The `flags` argument of `move_to/request_move` is passed through as `opts`.

#### 3.10.3 Order handlers (`SimOrderHandler` subclasses; contract of sim_core §3.6)

```gdscript
class_name SimOrderMove extends SimOrderHandler     # instances: T_MOVE(16), T_PATROL(17), T_FOLLOW(18), T_FACE(19)
func _init(order_type: int)
var requires_target: bool                            # true for T_FOLLOW and (SimOrderCargo) T_LOAD / T_GARRISON: the dispatcher calls target_lost -> FAILED when the target dies
func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int     # OK | Err.NOT_ALLOWED (no move slot / class STATIC / speed 0) | Err.NO_TARGET (T_FOLLOW: target not alive or self)
func begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int         # abilities.request_pack; T_MOVE: same-tick group + formation slot (§5.5); SimMovement.go_to/…; RUNNING
func tick(world: SimWorld, e: SimEntity, o: SimOrder) -> int          # polls SimMovement.state/result: ARRIVED -> DONE, NO_PATH/STUCK -> FAILED, waits while the unit is packing
func cancel(world: SimWorld, e: SimEntity, o: SimOrder) -> void       # SimMovement.stop(soft) if this order set the current goal
func target_lost(world: SimWorld, e: SimEntity, o: SimOrder) -> int   # FAILED

class_name SimOrderAir extends SimOrderHandler       # T_LAND(20): x,y = touchdown point; DONE when air_at_goal
class_name SimOrderCargo extends SimOrderHandler     # instances: T_LOAD(64), T_UNLOAD(65), T_GARRISON(66)
```
Order field use (sim_core §4.7): `x,y` goal; `target` entity; `arg`/`arg2` per §6.2; `p0` = goal cell, `p1` = phase counter (0 idle, 1 waiting for pack, 2 waiting for target); `t0` = tick begun; `OF_NO_FORMATION`, `OF_CYCLIC`, `OF_FORCED` as in sim_core. All handler state is in the order or in `SimMoveComp` (both hashed).

#### 3.10.4 Path service and formation

```gdscript
class_name SimPathService extends RefCounted
const PRIO_ORDER := 0; const PRIO_ECON := 1; const PRIO_REPATH := 2
func _init(map: MapData)
func request(e: SimEntity, goal_cell: int, goal_r: int, prio: int, flags: int, avoid: PackedInt32Array = PackedInt32Array()) -> int   # request id > 0; replaces e's previous request
func cancel(entity_id: int) -> void
func pending() -> int
func process(world: SimWorld) -> void                       # called first thing in SimMovementSystem.update; budgeted (§5.3.5)
func invalidate_cache() -> void
func state_ints(buf: PackedInt32Array) -> void

class_name SimFormation extends RefCounted
static func group_of(world: SimWorld, e: SimEntity, o: SimOrder, out: PackedInt32Array) -> int
    ## ids (ascending) of the owner's units whose head order is a PH_NEW T_MOVE with the same x,y and without OF_NO_FORMATION, ground classes only, <= 200; includes e. Called by the first such unit's begin() in the tick.
static func assign(world: SimWorld, ids: PackedInt32Array, tx: int, ty: int, flags: int, out_x: PackedInt32Array, out_y: PackedInt32Array) -> void
    ## out arrays are resized to ids.size(); slot i belongs to ids[i]. Snapped to passable cells (§5.5). The leader stores each member's slot in that member's SimMoveComp (fslot_x/fslot_y/fslot_tick).
```

#### 3.10.5 Flight and exits (internal to the facade, listed for the task owners)

`SimAirMove.step(world, e, mv)` (per tick, called from phase C for aircraft), `SimAirMove.takeoff/land/orbit/…` (bodies of the `air_*` primitives); `SimExitMove.find_free_cell_near`, `eject_units_from_rect`, `glide_step`, `sidestep_request`.

#### 3.10.6 Compatibility map (how each peer spec's calls land on this spec)

| Peer spec, as written there | Here |
|---|---|
| combat.md §3.8: `SimMovement.move_to(world, e, x, y, flags)`, `move_to_range(world, e, tx, ty, range)`, `stop(world, e)`, `turn_to(world, e, facing)`, `is_moving(e)` | identical names and arguments (§3.10.2) |
| combat.md §3.8: `air_fly_to`, `air_orbit`, `air_hover`, `air_face`, `air_takeoff`, `air_land_at`, `air_at_goal` | identical; `air_takeoff` / `air_land_at` take optional `ticks` (and `heading`) so combat's `takeoff_ticks` / `landing_ticks` are honoured |
| combat.md §13-24: `cc.ext_moving`, `e.vx / e.vy` written by movement | entity flag `F_MOVING`, `SimMovement.is_moving(e)`, `SimMovement.velocity(e, out)` (R2) |
| economy.md §3.7 / §13-15: `world.movement.request_move(ent, x, y, flags) -> bool`, `stop(ent)`, `path_failed(ent)`, `at_goal(ent)` | `SimMovement.request_move(world, ent, x, y, flags)`, `stop(world, ent)`, `path_failed(ent)`, `at_goal(ent)` (R6) |
| economy.md §5.4 / §5.3: `find_free_cell_near(cell, layer, max_radius)`, `eject_units_from_rect(x0, y0, x1, y1, team)` | same, `world` first |
| economy.md §5.9: dock-in 12 ticks / dock-out 8 ticks, "scripted mover" flag | `SimMovement.glide(world, e, x, y, ticks)` (no flag needed) |
| economy.md §13-13: `MapData.deposits`, `neutral_spawns`, `is_buildable`, `is_passable_ground`, `is_water`, `water_body_size` | `deposit_fields()`, `neutral_spawns()` and the same predicate names (§3.3) |
| abilities.md §13-8: `speed_units`, `is_immobile`, `is_turn_locked` read by movement; map `is_water/is_land/passable/is_clear/w/h` | consumed through the adapters of §3.10.1; the map predicates exist with those names |
| ai.md XR-14: `MapData.w/h/passable/region/family()/is_water`, start order, deposits, `MapGen.create(family, size, seed)` | same, `family()` = `get_family()`; generator entry = `MapGenerator.generate({family, size, seed, layout_players})` |
| net.md XR-12: `validate_params`, `content_hash()`, `begin/step/progress_pct` | `MapGenerator.validate_params`, `MapData.content_hash()`, `MapGenJob.begin/step/progress_pct/result` |
| qa.md XR-24: `MapGenerator.generate(map_cfg)`, `MapData.map_hash`, `map.start_near_water`, `map_validator` | same; `MapGenValidate.validate/metrics` |
| sim_core R7–R9: `w, h, start_cells, objects, map_hash, clone_for_world(), hash_state(buf), make_flat(...)` | same (§3.3) |
| render.md §13-9: `width, height, seed_value, biome, heights, types, flags, moisture, terrain_kind, shore_dist, roads, water_level_u, start_cells, deposits` | §5.14 table (`w`, `h` are the cell counts; every other field name matches) |
| data_balance.md §13-13: `PLACE_SHORELINE` predicate, `fp_w/fp_h/fp_mask` placement, neutrals from `DefNeutral`, deep-only hulls | `MapBuildRules.check_berth` + `has_adjacent_water`, `MapFootprint.cells`, `MapGenTables`, `NP_NAVAL_DEEP` |

### 3.11 Call and tick order

```
sim_core stage                  what happens in this domain
1  CommandSystem                built-in _exec_order -> world.orders.issue -> SimOrderMove/Cargo.can_issue (pure). No executor of mine.
2  ProductionSystem             SimPlacement -> MapBuildRules.check_land/check_berth ; SimMovement.eject_units_from_rect ; MapData.occupy(sid, cells) (nav weights NOW, clearance/graphs deferred, count-bounded)
                                produced units: SimMovement.find_free_cell_near for the exit, then world.orders.issue(T_MOVE) for the rally point (begins in stage 5 of the same tick)
3  EconomySystem                SimMovement.go_to/stop/glide/at_goal/path_failed ; MapData.harvest_field/regrow_field (dock queue and unload timers are economy's)
5  OrderSystem                  SimOrderMove/Air/Cargo.begin/tick/cancel: goals recorded, formation slots computed, path requests queued; abilities.request_pack / SimTransport.board|begin_unload|garrison_enter
6  MovementSystem.update():
     (a) map.nav.flush_dirty(NAV_DIRTY_BUDGET)             abstract graphs catch up with structure changes (count-bounded)
     (b) path_service.process(world)                       budgeted; delivers cache/LOS/search results to SimMoveComp
     (c) SimSeparation.rebuild(world)                       canonical bucket grids in ascending entity id
     (d) phase A  for each mover (ascending id): read speed/immobile inputs, goal/waypoint logic, desired heading+speed        (reads own state + map only)
     (e) phase B  for each mover/idle-scheduled unit: separation displacement from the tick-start snapshot
     (f) phase C  for each mover (ascending id): integrate via world.set_pos, terrain rule, medium switch, layer/alt (world.set_layer), flag mirrors, arrival, STATE events
     (g) strided maintenance: stuck detection, path validity, follow re-plan
7  AbilitySystem                (no call into me; stage 6 of the NEXT tick sees the new speed_units / is_immobile)
8  CombatSystem                 SimMovement.move_to/move_to_range/stop/pause/resume/turn_to/air_*  (goal recorded now, executed by stage 6 of the next tick: 1 tick latency, as combat.md §6 states)
9  ZoneSystem                   nothing (no map patches; debris is a stat mod and zones.blocks_construction)
11 CleanupSystem                economy/production vacate destroyed structures (MapData.vacate) in their on_removed hooks; my on_removed drops movers
```

Results produced in tick *t* (path delivered, arrival) are visible to the OrderSystem in tick *t+1*. A path served from cache or by the direct-LOS shortcut in (b) is used for steering in the **same** tick *t* (zero added latency for the common cases).

### 3.12 Who owns which memory

| Object | Owner | Lifetime / notes |
|---|---|---|
| `MapTerrain` | `GameData` | per process; immutable after `from_dict`. |
| `MapData` (template from generator/`from_bytes`) | the app/`MatchConfig` holder | discarded after `SimWorld` clones it (`clone_for_world`). |
| `MapData` (runtime) incl. `MapNav`, graphs | `SimWorld` (`world.map`) | one per world; never shared between worlds. |
| `MapPathSearch` scratch (`g, vis, closed, parent, buckets, entries` ≈ 2.6 MB at 256²), separation grids (≈ 90 kB), request tables, path cache | `SimPathService` / `SimSeparation` (owned by `SimMovementSystem`) | allocated once at `init_world`; **no per-tick allocation** in hot loops (path arrays are the only allocations: ~12/s). |
| `SimMoveComp` | the entity (`e.move`) | created by `SimMovementSystem.on_spawn`, freed with the entity. |
| `SimMoveProfiles` | `SimMovementSystem` | rebuilt if `GameData` changes (never mid-match). |
| pad, dock queue, cargo lists | economy / combat / abilities | not stored here (§5.6, §5.8, §5.9). |

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 `MapData` layers — static vs dynamic, and what is checksummed

`n = w*h`. "map_hash" = lobby/replay handshake (once). "tick checksum" = `SimWorld.checksum()` every 20 ticks (DR-13); the world's `map` section digest is `map.hash_state(buf)` (`deposit_hash`, `occ_hash`, `nav_version`, O(1)).

| Field | Type / size | Kind | Written by | map_hash | tick checksum |
|---|---|---|---|---|---|
| `w`, `h`, `n`, `seed_value`, `family`, `biome`, `slots`, `players`, `gen_version`, `gen_params` | int / `PackedInt32Array` | static | generator | ✓ | – |
| `terrain` | `PackedByteArray(n)` terrain type 0..15 | static | generator | ✓ | – |
| `kind` | `PackedByteArray(n)` `TerrainKind` 0..7 | static, derived in `finalize` (`tt.kind_of`) | `finalize` | – (derived) | – |
| `flags` | `PackedByteArray(n)` `SF_*` bits | static | generator + `finalize` | ✓ | – |
| `buildable` | `PackedByteArray(n)`: 0 no, 1 standard (`TF_BUILD`, no `SF_NOBUILD/SF_BLOCK`), 2 shore-only (`TF_BUILD_SHORE`) | static, derived | `finalize` | – | – |
| `water_comp`, `water_size` | `PackedInt32Array(n)` component id (−1 land); `PackedInt32Array(ncomp)` sizes (4-connected over SHALLOW+DEEP+FORD) | static, derived | `finalize` | – | – |
| `field_of` | `PackedByteArray(n)` 0 none, 1..64 field id | static | generator | ✓ | – |
| `deposit_max` | `PackedInt32Array(n)` initial credits per cell | static | generator | ✓ | – |
| `spawns` | `PackedInt32Array` stride 6 (§3.3); `start_cells` and `objects` are derived views of `spawns` / `neutrals` | static | generator | ✓ | – |
| `neutrals`, `fields`, `neutral_ids` | `PackedInt32Array` stride 8 / stride 10, `PackedStringArray` | static | generator | ✓ | – |
| `height` | `PackedByteArray(n)` 0..255 (generator internal, source of `heights`) | static (view) | generator | ✗ (`visual_hash`) | – |
| `heights`, `moisture`, `shore_dist`, `roads`, `water_level_u`, `deco`, `deco_seed` | view layers (§3.3, §5.14) | static (view) | generator / `finalize` | ✗ (`visual_hash`) | – |
| `deposit` | `PackedInt32Array(n)` remaining credits | **dynamic** | `harvest_cell/harvest_field/regrow_field` | initial = `deposit_max` | ✓ via `deposit_hash` |
| `field_left` | `PackedInt32Array(nfields+1)` | dynamic (derived) | `harvest_*` | – | ✓ (folded in `deposit_hash`) |
| `occ` | `PackedInt32Array(n)` structure entity id or **−1** (the world's structure grid) | **dynamic** | `occupy/vacate` | – | ✓ via `occ_hash` |
| `structs` | records `id → cell list` (Dictionary with int keys, keyed lookup only) | dynamic | `occupy/vacate` | – | ✓ (order-independent sum in `occ_hash`) |
| `nav` (`MapNav`) | `wgt[np]`, `clr[np]`: `PackedByteArray(n)` each (7 profiles); plus static `col`, `row`: `PackedInt32Array(n)` | dynamic (derived) | `occupy/vacate/finalize` | – | not hashed (derived); `validate_against_terrain()` in tests |
| `nav_version` | int | dynamic | every nav-affecting mutation | – | ✓ |
| `deposit_dirty` | `PackedInt32Array` | output-only | `harvest_*` | – | ✗ (DR-12) |

Hash definitions: `deposit_hash = Σ mix32(cell, amount)` (mod 2³², updated by subtracting the old term and adding the new one), `occ_hash = Σ mix32(sid, mix32(cell_i…))` over structures (one term per structure: the FNV of its sorted cell list), commutative sums, so no ordering dependence. `checksum_dynamic() = mix32(mix32(deposit_hash, occ_hash), nav_version)`; `hash_state(buf)` appends `[w, h, deposit_hash, occ_hash, nav_version]`.

### 4.2 Terrain types (`terrain.json`), their TerrainKind and derived path weights

`kind` is the **only** link to speeds: `speed_bp(mc, type) = DefMoveTable.speed_bp[mc*8 + kind]` (TAXONOMY §8 values: foot 110/100/80/70/60/70/0/0 for road/open/rough/forest/marsh/shallow/deep/cliff; wheeled 130/100/55/0/35/50/0/0; tracked 105/100/80/55/55/65/0/0; amphibious 105/100/75/50/80/90/70/0; naval 0/0/0/0/0/80/100/0; submerged …/0/100/0; air 100 everywhere; static 0). Weights `W` below are **derived** by the formula of §5.1 from exactly those numbers (columns are nav profiles; `–` = blocked).

| id | type key | kind | flags | buildable | FOOT | WHEELED | TRACKED | AMPH | NAVAL | NAVAL_DEEP | SUB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `deep_water` | DEEP | WATER | no | – | – | – | 23 | 16 | 16 | 16 |
| 1 | `shallow` | SHALLOW | WATER | no | 23 | 32 | 25 | 18 | 20 | – | – |
| 2 | `ford` | SHALLOW | WATER, CROSSING | no | 23 | 32 | 25 | 18 | 20 | – | – |
| 3 | `beach` | OPEN | LAND, BUILD_SHORE | docks only | 16 | 16 | 16 | 16 | – | – | – |
| 4 | `grass` | OPEN | LAND, BUILD | yes | 16 | 16 | 16 | 16 | – | – | – |
| 5 | `dirt` | OPEN | LAND, BUILD | yes | 16 | 16 | 16 | 16 | – | – | – |
| 6 | `sand` | OPEN | LAND, BUILD | yes | 16 | 16 | 16 | 16 | – | – | – |
| 7 | `rock` | ROUGH | LAND | no | 20 | 29 | 20 | 21 | – | – | – |
| 8 | `forest` | FOREST | LAND | no | 23 | – | 29 | 32 | – | – | – |
| 9 | `road` | ROAD | LAND | no | 15 | 12 | 15 | 15 | – | – | – |
| 10 | `pavement` | ROAD | LAND, BUILD | yes | 15 | 12 | 15 | 15 | – | – | – |
| 11 | `rubble` | ROUGH | LAND | no | 20 | 29 | 20 | 21 | – | – | – |
| 12 | `urban_block` | CLIFF | LAND | no | – | – | – | – | – | – | – |
| 13 | `cliff` | CLIFF | LAND | no | – | – | – | – | – | – | – |
| 14 | `mountain` | CLIFF | LAND | no | – | – | – | – | – | – | – |
| 15 | `marsh` | MARSH | LAND | no | 27 | 40 | 29 | 20 | – | – | – |

Notes: (1) A ford is a *shallow* cell (water for `is_water`, `F_ON_WATER`, `water_mult_bp` and sea-plane rendering) whose only extra meaning is the `CROSSING` flag, which puts it into the land-only guarantee set of §5.12; naval hulls with radius < 0.9 cell may sail over it (80 %), deep-only hulls (`NAVAL_DEEP`) may not. (2) `NAVAL_DEEP` is the `NAVAL` weight vector with `TK_SHALLOW` blocked (ship_medium/ship_large, TAXONOMY §6/§8 note). (3) Weights for wheeled marsh saturate at the clamp 40 (2.5× baseline) although the speed ratio is 2.86×. (4) If balance edits the speed table the numbers above change and **nothing else does**.

### 4.3 Enums and constants (integer values are binding)

```gdscript
class_name SimMoveConfig extends RefCounted
# ---- movement state (SimMoveComp.state) ----
const MS_IDLE := 0;  const MS_WAIT_PATH := 1; const MS_MOVING := 2;  const MS_BLOCKED := 3
const MS_NO_PATH := 4; const MS_ARRIVED := 5; const MS_PAUSED := 6;  const MS_GLIDE := 7
const MS_FACING := 8; const MS_SIDESTEP := 9; const MS_EVICT := 10
# ---- flags (SimMoveComp.flags bit set; the entity-level mirrors are SimFlags F_MOVING/F_AIRBORNE/F_BLOCKED/F_ON_WATER) ----
const MF_ON_WATER := 1;  const MF_REVERSING := 2; const MF_PATH_PARTIAL := 4; const MF_PRECISE := 8
const MF_SPEED_MATCH := 16; const MF_ATTACK_MOVE := 32
# ---- goal kinds ----
const GK_NONE := 0; const GK_POINT := 1; const GK_NEAR := 2; const GK_FOLLOW := 3; const GK_APPROACH := 4
const GK_FACE := 5; const GK_SIDESTEP := 6; const GK_GLIDE := 7; const GK_EVICT := 8
# ---- result codes (SimMoveComp.result) ----
const RS_NONE := 0; const RS_OK := 1; const RS_PARTIAL := 2; const RS_NO_PATH := 3; const RS_CANCELLED := 4
const RS_STUCK := 5; const RS_IMMOBILE := 6; const RS_BAD_TARGET := 7; const RS_NO_MOVE := 8
# ---- opts bits for SimMovement.go_* ----
const OPT_SPEED_MATCH := 2; const OPT_REVERSE_OK := 4; const OPT_PRECISE := 8; const OPT_NO_SLOT := 16; const OPT_ATTACK_MOVE := 32; const OPT_PRIO_ECON := 64
# ---- turn modes ----
const TM_INSTANT := 0; const TM_PIVOT := 1; const TM_ARC := 2; const TM_BANK := 3
# ---- separation hash layers ----
const HL_GROUND := 0; const HL_WATER := 1; const HL_SUB := 2; const HL_AIR_LOW := 3; const HL_AIR_HIGH := 4; const HL_COUNT := 5
# ---- air modes (SimMoveComp.air_mode) ----
const AM_PARKED := 0; const AM_TAKEOFF := 1; const AM_CRUISE := 2; const AM_ORBIT := 3; const AM_HOVER := 4; const AM_APPROACH := 5; const AM_LANDING := 6
# ---- speed / geometry constants ----
const CELL := 1024
const SPEED_Q := 16                    # Q4: stored speeds are units/tick * 16
const SEP_BUCKET_SHIFT := 11           # separation bucket = 2 cells
const SEP_MAX_NEIGHBOURS := 12
const SEP_OVERLAP_NUM := 7             # min distance = (ri+rj)*7/8
const IDLE_SEP_STRIDE := 3
const WP_REACH_MIN := 384              # units
const ARRIVE_EPS := 256                # units (exact goals); MF_PRECISE uses 48
const STUCK_STRIDE := 10; const STUCK_MIN_PCT := 20
const STUCK_REPATH_TICKS := 40         # = global.json movement_defaults.stuck_repath_ticks (first repath after 4 stuck strides)
const PATH_WAIT_MAX := 60              # ticks in MS_WAIT_PATH before RS_NO_PATH (3 s)
const REPATH_MIN_INTERVAL := 20
# ---- path service budgets (per tick, all counts; §5.3.5) ----
const PATH_BASE := 1600; const PATH_PER_PENDING := 200; const PATH_PENDING_CAP := 8; const PATH_MAX_DELIVERIES := 16
const CACHE_CAP := 64; const CACHE_TTL := 100; const NAV_DIRTY_BUDGET := 12; const SIDESTEP_PER_TICK := 8
```

`MapPathSearch` (map/ module, so its constants live there, not in `SimMoveConfig`): `NB := 128` (bucket slots), `FINE_CAP := 2400`, `MAX_EXPANSIONS := 12000`, `HIER_MIN_OCTILE := 240` (queries shorter than this use the fine search first), `DIRECT_LOS_EXTRA_DIV := 4` (direct path iff `los_cost <= octile + octile/4`), `CORRIDOR_DILATE := 0` (1 = also allow the 1-hop neighbours of the abstract route: quality mode), `SMOOTH_SPANS := [24,16,12,8,6,4,3,2]`, `MAX_WAYPOINTS := 160`, `ABS_BUCKETS := 1024`, `AVOID_MAX := 16`.

Other enums (values binding): terrain types, `TK_*`, `MC_*`, `NP_*`, `SZ_*`, `TF_*` in §3.2; `SF_*`, strides, `FK_*` in §3.3; `PR_*` in §3.6; `ST_*` in §3.5; generator constants in §3.7. The shared enums (`MoveClass`, `TerrainKind`, `Layer`, `SizeClass`, `SimFlags`, `SimOrder.T_*`) are mirrored from the frozen sources; `MapTerrain.from_dict` and `SimMovementSystem.init_world` assert equality with `DefEnums`/`SimFlags`/`SimOrder` and refuse to start on a mismatch.

Neutral structure ids used by the generator (`MapData.neutral_ids`, order binding; footprints come from `DefNeutral`/`neutral_structures.json`, never from here): `0 neutral.civilian_garrison`, `1 neutral.substation`, `2 neutral.salvage_depot`, `3 neutral.field_hospital`, `4 neutral.observation_tower`, `5 neutral.harbor_terminal` (economy.md §5.13 catalogue).

### 4.4 `SimMoveComp` — exact field list (all `int` unless noted; defaults in `[]`; every field is in `hash_into` unless listed in `HASH_EXEMPT`)

```gdscript
class_name SimMoveComp extends SimComponent
const HASH_EXEMPT: PackedStringArray = ["mc", "np", "nav_size", "radius", "mass", "turn_mode", "turn_rate", "accel_q4", "decel_q4", "reverse_pct", "speed_base", "hl", "cell", "cell_kind", "vcur_q4"]
# --- profile copy: derived from SimMoveProfiles[def_idx] at on_spawn (exempt: recomputed from the def) ---
var mc: int; var np: int; var nav_size: int; var radius: int; var mass: int; var turn_mode: int; var turn_rate: int
var accel_q4: int; var decel_q4: int; var reverse_pct: int
var speed_base: int          # base units/tick (DefUnit.speed): used only when abilities.speed_units is unavailable (unit tests)
# --- dynamic state ---
var state: int [MS_IDLE]; var flags: int [0]; var spd_q4: int [0]       # spd_q4 signed (negative = reversing)
var hl: int                   # current separation layer (HL_*), derived from class + MF_ON_WATER (exempt)
var speed_cap_q4: int [0]     # 0 = none (formation speed match)
var cell: int; var cell_kind: int; var vcur_q4: int   # derived caches (exempt): current cell index, its TerrainKind, last top speed (Q4)
var vx: int [0]; var vy: int [0]                       # displacement applied in the last tick (units); SimMovement.velocity
# --- goal and path ---
var goal_kind: int [GK_NONE]; var goal_x: int; var goal_y: int; var goal_range: int; var goal_target: int [-1]; var goal_cell: int [-1]; var goal_opts: int
var path: PackedInt32Array; var wp: int [0]; var path_ver: int [-1]; var req_id: int [0]; var wait: int [0]; var repath_at: int [0]
var result: int [RS_NONE]; var goal_tick: int [0]      # tick the goal was set
var fslot_x: int; var fslot_y: int; var fslot_tick: int [-1]   # formation slot written by the group leader's T_MOVE.begin for this member
# --- stuck / blocking ---
var stuck_x: int; var stuck_y: int; var stuck_cnt: int [0]; var nudge_t: int [0]; var nudge_dir: int [0]; var blocked_by: int [-1]; var blocked_t: int [0]
var water_t: int [-100]      # tick of the last accepted F_ON_WATER flip (6-tick hysteresis, §5.4.3)
# --- scripted glide and layer change ---
var g_x0: int; var g_y0: int; var g_x1: int; var g_y1: int; var g_t: int [0]; var g_n: int [0]      # glide from (g_x0,g_y0) to (g_x1,g_y1), g_t ticks done of g_n
var lr_layer: int [-1]; var lr_t: int [0]              # pending request_layer: target layer and ticks left
# --- aircraft (unused = 0 for ground) ---
var air_mode: int [AM_PARKED]; var alt: int [0]; var alt_goal: int [0]; var orbit_x: int; var orbit_y: int; var orbit_r: int; var orbit_dir: int [1]
var land_x: int; var land_y: int; var land_heading: int [-1]; var air_phase: int
func hash_into(buf: PackedInt32Array) -> void       # order fixed = declaration order above minus HASH_EXEMPT; path element-wise (size first)
```

Note: `entity.x, y, facing, layer, flags` stay on `SimEntity` (sim_core §4.2). `facing` is a binary angle 0..4095 (0 = +x, increasing toward +y).

### 4.5 Components owned elsewhere that this domain reads (no fields added here)

| Component / API | Owner | What I read or call |
|---|---|---|
| `SimEntity` | sim_core | `x, y, facing, layer, flags, owner, def_idx, holder, orders`; `world.set_pos/set_layer`, `world.units`, `world.by_id`, `world.tick`, `world.events.emit` |
| pad table (`SimCompProd.pad_ent`), `airfield_pad_cell()` | economy | pad cell → landing point handed to `air_land_at` by combat's sortie machine |
| dock queue (`SimCompEcon`) | economy | none: economy drives `glide` |
| cargo lists (`SimCompCargo`, `container_id`/`holder`) | abilities (`SimTransport`) | `SimTransport.can_board/board/garrison_enter/begin_unload/free_slots/cargo_of` |
| `SimCompCombat` (`ext_moving`, `still_ticks`) | combat | none written; combat reads `F_MOVING` and `SimMovement.is_moving` |

### 4.6 `SimMoveProfiles` — per-def movement profile (built once in `init_world`; replaces the former `DefMove`)

`SimMoveProfiles.build(data: GameData, tt: MapTerrain) -> SimMoveProfiles` fills parallel `PackedInt32Array`s indexed by `def_idx` (−1 for non-unit defs) from the frozen data objects (`ASSUMPTION(data)`: field names of data_balance §4.2):

```
mc          = DefUnit.move_class                      radius = DefUnit.radius (units)          home_layer = DefUnit.home_layer
np          = MapTerrain.profile_of(mc, radius)       nav_size = MapTerrain.nav_size(mc, radius)
mass        = DefBodyTable.mass[DefUnit.size_class]    speed_base = DefUnit.speed (units/tick)  turn_rate = DefUnit.turn_rate (angle units/tick)
accel_t     = DefUnit.accel_t                          (ticks to full speed; global.json movement_defaults.accel_ticks[size class] unless the sheet overrides)
accel_q4    = max(1, (speed_base*16 + accel_t/2) / accel_t)                        # Guardian: speed 102, accel_t 6 -> 272
decel_t     = max(1, (accel_t * 70 + 50) / 100)                                     # movement_defaults.decel_ticks_pct_of_accel = 70; accel_t 6 -> 4
decel_q4    = max(1, (speed_base*16 + decel_t/2) / decel_t)                         # Guardian -> 408
reverse_pct = 50 (movement_defaults.reverse_speed_pct) for WHEELED / TRACKED / AMPHIBIOUS, else 0
turn_mode   = FOOT -> INSTANT; WHEELED -> ARC; TRACKED -> PIVOT; AMPHIBIOUS -> ARC for size class light, PIVOT for medium and larger; NAVAL, SUBMERGED -> ARC; AIR_FIXED -> BANK; AIR_HOVER -> INSTANT   (movement.json `turn_mode_override` per unit id)
hl_default  = GROUND for FOOT/WHEELED/TRACKED/AMPHIBIOUS, WATER for NAVAL, SUB for SUBMERGED, AIR_HIGH for AIR_FIXED, AIR_LOW for AIR_HOVER
```
Worked numbers (data_balance §7.6 examples): Guardian (tracked, medium): `speed 102, radius 563, accel_t 6, turn_rate 85` → `np = NP_TRACKED, nav_size = 2, mass 3, accel_q4 = 272, decel_t = 4, decel_q4 = 408, TM_PIVOT`; Beaver (amphibious, speed 164): `np = NP_AMPH, nav_size 2`; infantry (`inf`, radius 410, accel_t 2): `nav_size 1, accel_q4 = 8·speed, decel_t 1`.

### 4.7 Path service and search structures (component layouts)

`SimPathService` request table is struct-of-arrays, slot-indexed, slots recycled through a free list (deterministic LIFO): `r_ent, r_np, r_size, r_start, r_goal, r_goal_r, r_prio, r_flags, r_seq, r_state (0 free / 1 queued / 2 active), r_avoid_off, r_avoid_n` (avoid cells are appended to `avoid_pool`, reset each tick when the queue is empty). Three FIFO queues (one per priority) hold slot indices. **Path cache**: `Dictionary` with int keys `key = goal_cell | (np << 20) | (size << 23) | (start_node << 26)` (np < 8 fits 3 bits, size 2 bits); values are slot indices into parallel arrays `c_path: Array[PackedInt32Array]`, `c_ver: PackedInt32Array` (`nav_version` when stored), `c_born: PackedInt32Array` (tick when stored); capacity 64, eviction FIFO through a ring of keys; a key is *inserted and evicted deterministically*, never iterated.

`MapNavGraph` (per profile,size): `nbx, nby` (block counts), `node_of_cell: PackedInt32Array(n)` (node id = `block*8 + local`, local ∈ 0..7, −1 = impassable for this size), `node_rep, node_cnt, node_sumw: PackedInt32Array(nbx*nby*8)`, `adj: PackedInt32Array(nodes*12)`, `deg: PackedByteArray(nodes)`, `cc: PackedInt32Array(nodes)` (abstract connected component, refreshed after each flush), `dirty: PackedByteArray(nbx*nby)`. A block with more than 8 components keeps the 8 largest (ties: lowest first-cell index); the rest of its cells are treated as impassable *for this graph only* (documented degradation; never occurs on generated terrain, possible in pathological structure mazes).

`MapPathSearch` scratch (allocated once, `n = w*h`): `g, vis, closed, parent: PackedInt32Array(n)`, `head: PackedInt32Array(128)`, entry pool `e_node, e_next, e_g: PackedInt32Array(4n)`, abstract arrays `a_g, a_par, a_closed, corr_stamp: PackedInt32Array(nodes)`, plus a monotonic `serial` so nothing is cleared between searches (only `head.fill(-1)`, 128 writes).

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Terrain model, movement classes, speed and cost derivation

**Movement classes → nav profile, terrain access** (`MoveClass` and the speed table are TAXONOMY §8; percentages are `DefMoveTable.speed_bp / 100`):

| `MoveClass` | Layer | Nav profile | Units (bible tags) | Passable kinds (today's table) |
|---|---|---|---|---|
| `FOOT` 0 | ground | `NP_FOOT` | `infantry` incl. Engineer | road 110, open 100, rough 80, forest 70, marsh 60, shallow 70; not deep, not cliff. Size 1: passes 1-cell alleys. |
| `WHEELED` 1 | ground | `NP_WHEELED` | light chassis (APCs, scouts, buggies), Collector, MCV | road 130 (Mamba "strong road mobility"), open 100, rough 55, marsh 35, shallow 50; **not forest**. |
| `TRACKED` 2 | ground | `NP_TRACKED` | tanks, siege, artillery, AA vehicles, walkers | road 105, open 100, rough 80, forest 55, marsh 55, shallow 65. |
| `AMPHIBIOUS` 3 | ground (mask ground+water) | `NP_AMPH` | `amphibious` vehicles, Landing Transport, PD Collectors | land like tracked (rough 75, forest 50, marsh 80) plus shallow 90 and **deep 70** (per-unit `deep_speed_bp`, e.g. Tide Tank 60). |
| `NAVAL` 4 | surface water | `NP_NAVAL` (radius < 0.9 cell) or `NP_NAVAL_DEEP` | `ship` (not submarine) | shallow 80 (small hulls only), deep 100. |
| `SUBMERGED` 5 | underwater | `NP_SUB` | `submarine` | deep 100 only. |
| `AIR_FIXED` 6, `AIR_HOVER` 7 | air | none | `aircraft` | everything inside the map (100 %). |
| `STATIC` 8 | ground | none | structures | occupy cells (speed 0 everywhere). |

**Weight derivation (the only formula).** For a nav profile and terrain type with reference speed percent `p = speed_bp(mc_of_profile, type) / 100 > 0`:
`w = clamp((1600 + p/2) / p, 10, 40)` (integer division; `p/2` truncating). `p = 0 → w = 0` (blocked). `NP_NAVAL_DEEP` additionally forces `w = 0` on kind `SHALLOW`. So baseline terrain (100 %) gives `w = 16`, a 130 % road 12, forest for foot 23, marsh for wheeled 40 (clamped), shallow for wheeled 32 (full table in §4.2). Amphibious planning uses the class table (deep = 70 % → 23) and ignores the per-unit `deep_speed_bp`. A blocked cell is `w = 0` in a profile if its terrain gives 0, or `flags & SF_BLOCK`, or `occ >= 0`, or it lies in the outer `NAV_BORDER` cells.

**Step cost** (cost units, 10 = one baseline cell): entering a cell of weight `w` costs `STEP_O[w] = (10*w + 8) >> 4` orthogonally and `STEP_D[w] = (14*w + 8) >> 4` diagonally; tables of length 41 built once. Heuristic `h(a,b) = 10*(dx+dy) - 6*min(dx,dy)` (octile at baseline weight). Faster-than-baseline terrain (roads, `w < 16`) makes `h` slightly inadmissible; this is accepted (paths on road-heavy routes may be ≤ 33 % longer than optimal on the road stretch) because a tight baseline `h` is what keeps A* focused — measured: with `h` scaled to the baseline the open-ground search visits 249 cells for a 248-cell route; with `h` at 80 % it visits 29 232 (44 % of the map).

**Effective speed** (phase A of every tick for every moving unit; all inputs are integers, every stage rounds half-up):

```
speed_upt = _speed(e)                     # abilities.speed_units(e) when the adapter exists (units/tick; research, auras, command fields, Open Corridor, debris …), else mv.speed_base
kind      = kind_at(cell)                 # cached in mv.cell_kind, recomputed when the cell changes
kind_bp   = tt.speed_bp(mc, terrain[cell]);  if mc == AMPHIBIOUS and kind == DEEP and unit.deep_speed_bp > 0: kind_bp = unit.deep_speed_bp
v_q4      = (speed_upt * 16 * kind_bp + 5000) / 10000
if kind is SHALLOW or DEEP:   v_q4 = (v_q4 * unit.water_mult_bp + 5000) / 10000          # Canada +20 % on water: 12000
if mc == FOOT and suppressed: v_q4 = (v_q4 * combat.suppression_speed_bp(e) + 5000) / 10000   # 7500 while suppressed (combat.md 3.7)
if mv.speed_cap_q4 > 0:       v_q4 = min(v_q4, mv.speed_cap_q4)                               # formation speed match
vcur_q4   = v_q4                          # the top speed the speed law of 5.4.2 steers toward this tick
```
`unit.deep_speed_bp` and `unit.water_mult_bp` are the *resolved* `DefUnit` values (data_balance §4.2: research and roster modifiers already folded, Canada's `ON_WATER` bonus is in `water_mult_bp`, nothing is re-evaluated at runtime). The largest intermediate is `speed_upt·16·kind_bp ≤ 800·16·13000 = 1.7·10⁸`.
Worked examples: Beaver (speed 164, `water_mult_bp` 12000) on deep water: `(164·16·7000 + 5000)/10000 = 1837`, then `(1837·12000 + 5000)/10000 = 2204` Q4 = 137.75 units/tick, i.e. data's `DefMoveTable.effective_speed(...) = 138` within 1/16 unit. Guardian (speed 102) under Open Corridor (abilities returns `speed_units = 128`) on a road: `(128·16·10500 + 5000)/10000 = 2150` Q4 = 134.4 units/tick = 2.63 cells/s; on rough ground (80 %): `1638`. Infantry (`speed_units` 87) suppressed in a forest: `(87·16·7000 + 5000)/10000 = 974`, then `× 7500 → 731`.

**How each bible movement rule is honored**

| Bible / balance rule | Implementation |
|---|---|
| "Forest (blocks vehicles, slows infantry)" (task text) vs TAXONOMY forest row | Data-driven (D-3): forest blocks wheeled, slows tracked/amphibious/foot per `DefMoveTable`; nav profiles and the generator guarantee follow the table; R3 records the design question. |
| "Every roster is playable on a land-only map"; "no faction needs a Dock to unlock land or air technology"; "avoid mandatory water for baseline economic access" | Generator: all starts/fields/neutrals connected on the **guarantee set** (land + fords, water excluded, intersection of foot/wheeled/tracked) — validation V1/V3/V5/V8 (§5.12.6). Rivers are crossable at fords; docks are optional (shoreline + berth rule); no footprint or unit requires water. |
| Landing Transport "provides a water-crossing option to every roster" | Deep water blocks foot/wheeled/tracked; Landing Transport is `AMPHIBIOUS` (deep 70 %) and carries them (`T_LOAD/T_UNLOAD`, §5.8); shallow water is crossable by every ground class. |
| PD Collectors "amphibious … 70 % of their land speed" | balance `unit_overrides`: `move_class = AMPHIBIOUS`, `deep_speed_bp = 7000`; nothing else here. |
| Canada "+20 % amphibious vehicle speed on water", Nordics/Kongo "+15/+20 % on land and water" | `water_mult_bp` (water cells only) / `speed` (everywhere), both resolved by data. |
| Mamba APC "strong road mobility", "Tide Tank slow movement on water" | Table value wheeled road 130 %; Tide Tank `deep_speed_bp` 6000 (TAXONOMY §8 note). |
| Open Corridor +25 %, Broken Contact +20 %, Coordinated Advance +25 %, Recovery Priority +25 %, Steel Advance −20 %, Transit Priority +35 %, Mobile Reserve +30 %, ships +15 % | temporary/static stat mods resolved by abilities into `speed_units(e)`; suppression −25 % from combat; movement multiplies terrain and water on top (formula above). |
| Horizon Mass Driver debris "slows all land vehicles by 35 % for 20 s and prevents new construction; never blocks movement" | abilities.md §5.11: `stat_mod SPEED −3500` on land vehicles standing on land + `zones.blocks_construction`. **The map has no dynamic slow patches**; nothing here changes weights, so no repaths. |
| "Titan Gunship … hovering", "Osprey hovers when firing" | `AIR_HOVER` (hover-capable, yaws in place); fighters/bombers/EW `AIR_FIXED` cannot hover (§5.6). |
| "Deploys … cannot move while deployed" (Charlemagne, Gaj, Long Walker, Fen mast, Fortress Guard…) | abilities `is_immobile/is_turn_locked`; `T_MOVE.begin` calls `request_pack` first and waits. |
| "Decoy … no collision", "non-blocking decoy transports" | `F_NO_COLLIDE` → excluded from the separation grids. |
| "Marked civilian garrisons hold four infantry squads" | `T_GARRISON` approach (§5.8); occupancy rules are `SimTransport`. |
| "Aircraft need powered Airfield pads to rearm; four pads (+2 research)" | economy `airfield_pad_*`; combat's sortie machine calls `air_land_at(pad cell)` (§5.6). |
| "Collectors … unload at a Refinery" | economy dock protocol; the dock-in/out motion is `glide` (§5.9). |
| Naval channel widths ≥ 3 / 4 / 6 cells for small / medium / large hulls; hull radius ≥ 0.9 cell is deep-only | Nav sizes: small/medium hulls need a 3-wide, large hulls (radius > 1.1 cell) a 5-wide deep channel; the generator's moat and bays are 7-wide deep (§5.12). |

### 5.2 Nav profiles, clearance, LOS, abstract graph

**Profile arrays** (`MapNav`): `wgt[np]: PackedByteArray(n)` and `clr[np]: PackedByteArray(n)` for the seven nav profiles (`NP_*`, §4.2; a profile with fewer than 100 passable cells — e.g. the three naval profiles on a dry map — is not materialised); plus shared static `col, row: PackedInt32Array(n)` (cell→x, y without division). The outer `NAV_BORDER = 2` cells are always `w = 0` in every profile (also on `make_flat` test maps), so 8-neighbour loops never test bounds.

**Clearance.** `clr = 0` if `w = 0`; else `1 + min(2, k)` where `k` = largest integer such that every cell within Chebyshev distance `k` is passable (`w != 0`). Equivalently the Chebyshev distance to the nearest blocked cell capped at 3. Initial computation is the classic two-pass transform (forward pass over W, NW, N, NE neighbours, backward pass over E, SE, S, SW, `c = min(c, min(neighbours)+1)`, cap 3): **15.6 ms at 256², 8.7 ms at 192²** per profile (measured). Foot profile: `clr ∈ {0,1}`. A unit of nav size `s` (`MapTerrain.nav_size(mc, radius)`) may stand on/plan through a cell iff `clr >= s`: size 1 = foot units (they fit 1-cell alleys), size 2 = every vehicle and small/medium hull (a 3-cell-wide passage), size 3 = large hulls, radius > 1.1 cells (a 5-cell-wide passage). All land vehicles therefore need ≥ 3-cell streets; the naval channel widths 3 / 4 / 6 of the balance framework are met by size 2 (3-wide) for small and medium hulls and size 3 (5-wide) for large hulls, and the generator's moat and canals are 7 wide.

**Diagonal rule.** A diagonal step `n → m` is legal iff both orthogonal cells shared by `n` and `m` have `w != 0` (no corner cutting) — automatic for size ≥ 2.

**Dynamic update.** `on_cells_changed(rect)` does the *cheap* part immediately: it recomputes `wgt` for every profile in the rect from `terrain/flags/occ`, sets `clr = 0` on newly blocked cells and `clr = 1` on newly freed cells (so LOS and `passable` are never optimistic about a blocked cell), and increments `nav_version`. The *expensive* part is queued and drained by `flush_dirty(budget)`: (1) `clr` recomputed in the rect expanded by 3 by direct ring testing (rings 1, 2, 3 with early exit: worst ≈ 48 reads, typical ≈ 10; a 4×4 footprint touches ≤ 100 cells ≈ 0.25 ms per profile; charged 4 units per rect), then (2) every 8×8 block intersecting the expanded rect is relabelled in each prepared graph (§5.2.1; 1 unit per (block, graph)). Until drained, planning data may be slightly stale (conservative for blocked cells), while the live weights that A\*, LOS and steering test stay exact.

**Integer LOS** (`MapNav.los`, used by smoothing, direct paths, waypoint validation, group attach). Bresenham on cell indices with the corner rule; at every visited cell test `clr[np][cell] >= size`:

```
dx = |x1-x0|; dy = |y1-y0|; sx = sign; sy = sign; err = dx - dy; (x,y) = (x0,y0)
loop: if clr[y*w+x] < size: return false
      if (x,y)==(x1,y1): return true
      e2 = 2*err; stepx = e2 > -dy; stepy = e2 < dx
      if stepx and stepy: if wgt[y*w+x+sx]==0 or wgt[(y+sy)*w+x]==0: return false     # diagonal corner rule (live weights)
      if stepx: err -= dy; x += sx
      if stepy: err += dx; y += sy
```
`los_cost` accumulates `STEP_O/STEP_D[wgt[next]]` for the same line (orthogonal or diagonal step as taken) and returns −1 if blocked. Measured **0.19 µs per cell**.

**Nearest passable.** Rings of increasing Chebyshev radius `1..max_ring`; within a ring iterate top row left→right, right column top→bottom, bottom row right→left, left column bottom→top (the ring walk used everywhere in this domain — fixed order = deterministic tie-break); first cell with `clr >= size` wins.

#### 5.2.1 Abstract block-component graph (`MapNavGraph`), one per prepared (np,size)

* **Blocks** are 8×8 cells (map sizes are multiples of 8 by ARCHITECTURE §3): `nbx = w/8`, `nby = h/8`; block `b = by*nbx + bx`. **Nodes** are the 4-connected components of cells with `clr >= size` *inside one block* (4-connectivity equals 8-connectivity-without-corner-cutting). Node id = `b*8 + local` (local index by first cell in row-major order; at most 8 kept, extras dropped as described in §4.7). `node_of_cell[i]` = node id or −1. Fully passable blocks take a fast path (one node, no flood): **6–10 ms per graph at 256²** (measured 6.2 / 8.4 / 10.0 ms for 12/25/35 % obstacle density; 9.4–9.7 ms urban).
* **Representative cell** `rep`: the node cell nearest (Chebyshev) to the block centre cell `(bx*8+3, by*8+3)`, ties → lowest cell index. `node_cnt`, `node_sumw` (sum of `wgt`) accumulate during labelling; `avg_w = node_sumw / node_cnt`.
* **Edges** (undirected, stored in both lists, at most 12 per node, overflow silently dropped after logging in debug): (1) *orthogonal*: for each pair of adjacent blocks, for each of the 8 border cell pairs `(a,b)` with both `node_of_cell >= 0`, link `node_of(a)`–`node_of(b)` if not already linked; (2) *diagonal*: for each block corner shared by four blocks, if the four corner cells all have `node_of_cell >= 0`, link the two diagonal pairs. Diagonal edges are essential — with orthogonal edges only the corridor for a diagonal route degenerates to a Manhattan staircase (measured: path 483 vs 248 cells). **Edge cost** = `octile10(rep_a, rep_b) * (avg_w_a + avg_w_b) / 32` (integer), i.e. octile distance scaled by mean local weight.
* **Connected components** `cc[node]` by BFS over `adj` (nodes ≤ 8192): refreshed at the end of every `flush_dirty` that changed any block (0.2–0.4 ms at 1000 nodes). `same_region` = `cc` equality of the two cells' nodes.
* **Dirty flush.** A dirty block is re-labelled (its 8 node slots cleared and rebuilt), then `relink(block, neighbour)` for its 8 neighbours: remove all edges between the two blocks' nodes, rescan the border. Cost per (block, graph): **≈ 60 µs**. `flush_dirty(budget)` first drains queued clearance rects (FIFO, 4 units each), then dirty (block, graph) units in ascending (graph key, block index) order, ≤ `NAV_DIRTY_BUDGET = 12` units per tick; while any dirty unit remains, searches that need the abstract phase are *deferred* (§5.3.5, step 5: at most 4 ticks, then served anyway) and only cached / LOS / bounded fine searches are served.
* **Abstract A\***: Dial buckets with 1024 circular slots (edge costs ≤ ~600), key clamped to the current key (consistent up to inadmissible road tweaks), LIFO within a bucket, neighbour order = `adj` order. Expansion cost 2 budget units. Measured: **≈ 0.2 ms** for a 32-node open route, **0.5 ms** for a 45-node urban route (390 pops).

### 5.3 Pathfinding

#### 5.3.1 Why this algorithm (measured comparison, 256×256)

| Approach | Measured / derived cost | Verdict |
|---|---|---|
| Flow field / Dijkstra map per destination (full map) | 64 221 cells visited, 85–89 ms (1.36–1.4 µs/cell) **per destination** | Rejected: even a bounded field costs ≥ 20 ms for a cross-map group and cannot be spread over ticks without stale-field bugs. Group reuse is achieved with shared *paths* instead. |
| Plain fine A\* with tight baseline heuristic | one cross-map query: open ground 249 visited / 0.63 ms; 25 % clutter 5 241 / 8.8 ms; 35 % clutter 10 634 / 17.5 ms; urban maze 8 700–9 000 / 14–15 ms. Over 300 random ≥ 60-cell pairs: mean 0.9–3.8 k visited, **worst 9.5–22 k** (16–38 ms) | Fine for short queries; unacceptable worst case for long ones. |
| **Corridor A\*** (fine search restricted to the nodes on an abstract route) | over the same 300 pairs per map: mean **0.5–0.9 k**, **worst 2.0–2.3 k** visited (incl. 2 × abstract pops); mean cost +1.7 … +5.9 %, max +11.8 … +22.3 % before smoothing | **Chosen for all long queries.** |
| Corridor + 1-hop dilation (optional quality mode) | mean 0.85–2.4 k, worst 4.3–7.9 k; mean cost +0.2 … +2.1 %, max +5.3 … +16.7 % | Kept as `CORRIDOR_DILATE` knob, off by default. |
| Ratio-based "unrestricted first if the abstract route is nearly straight" selector | tried at thresholds 8/8 … ∞: worse mean *and* worse worst case than always-corridor on every map (e.g. 25 % clutter: 1.9 k mean / 4.5 k worst vs 0.8 k / 2.3 k) | Rejected (measured). |
| JPS | – | Rejected: assumes uniform cost; roads/forest/fords make weights non-uniform. |
| HPA\* with portals + precomputed intra-cluster edges | derived: ≈ 10 portals × 256-cell Dijkstra per cluster ≈ 4.4 ms × 256 clusters ≈ 1.1 s per profile at load | Rejected: the component graph needs no intra-cluster edges (measured 6–10 ms labelling + 3.5 ms edges per graph). |

Short queries: 8–24-cell pairs need on average 32–161 fine expansions (worst 348–1 128; at 35 % clutter 7 of 396 exceed the 2 400-expansion cap — dead-end pockets — and fall through to the corridor). One weakness of the corridor is a perfectly straight open-ground route (a diagonal chain of blocks touches only at corner cells: 1 648 visits for a 248-cell diagonal); the LOS shortcut catches exactly those.

Choice: **path cache → integer LOS shortcut → fine Dial-bucket A\* (short queries, capped) → corridor A\* (long queries) → smoothing**, all integer, resumable, count-bounded. Group reuse: shared path per key (§5.3.5). Measured cost of the optimised inner loop: **1.6–1.7 µs per visited cell** (agrees with the 1.7 µs reference; a first-cut loop with a `match` per neighbour measured 2.9–3.4 µs — implementers must use offset tables).

#### 5.3.2 Fine search (`MapPathSearch`, phase FINE)

State: arrays from §4.7; `serial` increments per search (no clearing). Neighbour order fixed: **E, W, S, N, SE, SW, NE, NW** (offsets `+1, -1, +W, -W, +W+1, +W-1, -W+1, -W-1`) — this order is the tie-break. Buckets: `NB = 128` circular slots (`f & 127`); each entry `(node, g_at_push)`; LIFO per slot. `max step = STEP_D[40] = 35`, max `Δh = 14` ⇒ key spread ≤ 49 < 128; keys smaller than the current key are clamped to it (needed because `h` is not consistent on faster-than-baseline terrain — measured: without the clamp an inflated/inconsistent `h` degenerates to whole-map search).

```gdscript
# inner loop (locals cached: wgt, node_of, g, vis, closed, parent, head, e_node, e_next, e_g, col, row, STEP_O, STEP_D, offs, odx, ody)
while remaining > 0 and units < budget:
    var e := head[cur & 127]
    if e < 0: cur += 1; continue
    head[cur & 127] = e_next[e]; remaining -= 1
    var n := e_node[e]
    if closed[n] == serial or e_g[e] != g[n]: continue            # stale duplicate
    closed[n] = serial; units += 1; expanded += 1
    if reached(n): found = n; break
    var gn := g[n]; var nx := col[n]; var ny := row[n]
    for k in 8:
        var m := n + offs[k]
        var wc := wgt[m]
        if wc == 0 or closed[m] == serial: continue                # closed also encodes `avoid` cells (pre-marked)
        var nd := node_of[m]
        if nd < 0: continue                                       # not passable for this size
        if corridor and corr_stamp[nd] != corr_serial: continue
        var step: int
        if k < 4: step = STEP_O[wc]
        else:
            if wgt[n + odx[k]] == 0 or wgt[n + ody[k]] == 0: continue   # odx = ±1, ody = ±W
            step = STEP_D[wc]
        var ng := gn + step
        if vis[m] == serial and g[m] <= ng: continue
        vis[m] = serial; g[m] = ng; parent[m] = n
        var ddx := absi(nx + DX[k] - gx); var ddy := absi(ny + DY[k] - gy)
        var f := ng + 10*(ddx+ddy) - 6*mini(ddx, ddy)
        if f < cur: f = cur
        e_node[ne] = m; e_g[ne] = ng; e_next[ne] = head[f & 127]; head[f & 127] = ne; ne += 1; remaining += 1
```
*Goal test* `reached(n)`: `goal_r == 0 → n == goal`; else `max(|col[n]-gx|, |row[n]-gy|) <= goal_r`. *Best node* (for partial results) = lowest `h`, ties lowest `g`, then lowest index — tracked at push time. *Caps*: the entry pool has `4n` slots (overflow ⇒ stop as partial); `MAX_EXPANSIONS = 12000` per search. *Result*: walk `parent` from the reached node to `start`, reverse, drop the start cell, keep `path_cost = g[reached]`.

#### 5.3.3 Phase order of a search (`MapPathSearch.begin`)

Each phase consumes budget and may suspend at the budget end, resuming next tick; `serial` is incremented at the start of every fine phase:
0. **Reachability** (`PH_CC`, O(1)): if a graph exists for (np,size) and `cc[node_of(start)] != cc[node_of(goal)]` ⇒ `ST_NO_PATH` at once (`expanded == 0`; the service then picks an alternative goal, §5.3.5). Without this first step a short query to an unreachable goal would flood its component up to the 2 400-expansion cap.
1. **LOS** (`PH_LOS`): if `los_cost(start, goal) ∈ [0, octile + octile/4]` (mean weight ≤ 20) → result `[goal]` (cost 1 + ceil(len/8) units). Otherwise continue.
2. **Short** (`PH_FINE`): if `octile(start, goal) < HIER_MIN_OCTILE (240)` (24 baseline cells) → unrestricted fine A\*, capped at `FINE_CAP = 2400` expansions; success ⇒ smooth; cap hit ⇒ continue with 3.
3. **Abstract** (`PH_ABS`): `S = node_of(start)`, `G = node_of(goal)` (start/goal snapped by `nearest_passable(…, 3 / 6)` if their cells fail the size test). Abstract A\* on `S → G`.
4. **Corridor** (`PH_CORR`): fine A\* with `corr_stamp[node] = corr_serial` for every node on the abstract route (plus `S`, `G`; plus their 1-hop neighbours when `CORRIDOR_DILATE = 1`); only cells whose node is stamped are expanded. Expected ≤ 2.3 k expansions. If the open list is exhausted (stale graph / dead corridor): unrestricted fine A\* with `MAX_EXPANSIONS`; if that too fails → `ST_PARTIAL` to the best node.
5. **Smooth** (`PH_SMOOTH`).

Measured cost (256², one query): open 0.6 ms; long clutter/urban queries mean 0.9–1.6 ms, worst ≈ 3.9 ms (+0.2–0.5 ms abstract); short queries mean < 0.3 ms.

#### 5.3.4 Smoothing (cost-checked string pulling)

Input: fine cell path `p[0..n-1]` (with start), prefix costs `G[i]` (from parent chain). Output waypoint list. `i = 0; out = []; while i < n-1: for span in [24,16,12,8,6,4,3,2]: j = min(i+span, n-1); if j > i+1 and los_cost(p[i], p[j]) ≥ 0 and los_cost(p[i], p[j]) ≤ G[j] - G[i]: accept; if none accepted, j = i+1; out.append(p[j]); i = j.` A shortcut is accepted only if it is **no more expensive than the route it replaces** (so roads and fords are not cut across slow terrain). ≤ 8 LOS attempts per emitted waypoint; LOS cells are charged 1 unit per 8 cells. Result capped at `MAX_WAYPOINTS = 160` (longer routes: truncated and flagged partial, `repath` when consumed).

#### 5.3.5 `SimPathService`

**Request** = (entity, np, size, start cell, goal cell, goal radius, priority, flags, avoid cells). `np`/size come from the entity's `mv.np`/`mv.nav_size`; `start` = its current cell. A new request replaces (cancels) the entity's previous one. Priorities: `PRIO_ORDER` (player/AI orders: `T_MOVE`, attack-move locomotion, `T_FOLLOW`, `T_LOAD`/`T_GARRISON` approaches), `PRIO_ECON` (goals set by economy: collector trips, engineers, MCV), `PRIO_REPATH` (stuck, invalidation, follow); FIFO by `seq` within a priority; lower number first.

**Processing order for the head request** (each step charged to the budget):
1. **Snap.** Start cell fails `clr >= size` ⇒ `nearest_passable(np,size,start,3)` (units standing against a structure: factory exits, dock pads). Goal cell fails ⇒ `nearest_passable(…, goal, 6)` (or keep the ring cell chosen by the caller). None ⇒ `RS_NO_PATH`.
2. **Trivial.** `start == goal` (after snap) ⇒ arrived.
3. **Cache.** `key = goal | np<<20 | size<<23 | node_of(start)<<26`. Hit and `ver == nav_version` and `tick - born <= 100` ⇒ *attach* (below). 
4. **Reachability.** No graph (`prepare` not called for this key): `push_error`, fall back to fine A\* with `MAX_EXPANSIONS` and `same_region = true`. Graph present and `cc` differ ⇒ if `nav.pending_dirty() > 0` the verdict is not final (the graph may be stale): the request waits and is re-tested after the flush (≤ 4 ticks); otherwise alternative goal: scan rings `r = 1..24` around `goal`; among cells with `clr >= size` and same `cc` as the start take the one with minimum `octile(cell, goal)` (ties lowest index) within the first ring containing a candidate plus the next ring; mark result `RS_PARTIAL`. None ⇒ `RS_NO_PATH`.
5. **Search** (`MapPathSearch`, resumable, §5.3.3). While a search is active it is the head of its priority class (searches are serial; new higher-priority requests wait ≤ the remaining budget of the active one). If `nav.pending_dirty() > 0` a request that would need the abstract phase waits (skipped for up to 4 ticks, after which it is served with the stale-tolerant fallbacks of §5.3.3 step 4); cache hits, LOS paths and bounded fine searches are served regardless.
6. **Deliver** to the entity: `m.path`, `m.wp = 0`, `m.path_ver = nav_version`, `m.state = MS_MOVING`, flags (`MF_PATH_PARTIAL`), `m.req_id = 0`. Insert into the cache under `key` (if not partial).

**Attach (group reuse).** Cached `path` starts at the *leader's* start cell. For a follower in the same start node: find the smallest `k ∈ [0, 5]` with `los(follower_cell, path[k])`; if found, `m.path = cached`, `m.wp = k`; else issue an individual request (step 5). Cost ≤ 5 LOS (≈ 10 µs). Because `key` contains `node_of(start)` and the goal cell, a 30-unit group starting inside 1–3 blocks costs 1–3 searches; every later request in the same tick or within 5 s is a cache hit. Collector trips (same refinery bay ↔ same field) hit the cache after the first trip.

**Budget and accounting.** `budget = PATH_BASE + PATH_PER_PENDING * min(pending, 8)` with `PATH_BASE = 1600`, `PATH_PER_PENDING = 200` (≈ 2.7–5.4 ms at 1.7 µs/unit); deliveries per tick ≤ `PATH_MAX_DELIVERIES = 16`. Units: 1 per fine expansion, 2 per abstract expansion, `ceil(cells/8)` per LOS, 1 per cache hit/attach, 1 per snap. The count of units — never elapsed time — decides when a tick's work stops (DR-11). A search that is suspended keeps `serial`, buckets and entry pool untouched; the next tick's `process()` resumes it first.

**Latency handling.** A unit whose request is pending stays in `MS_WAIT_PATH`: it rotates toward the goal (pivot/instant units) or holds (ARC units) for at most `PATH_WAIT_MAX = 60` ticks, then fails with `RS_NO_PATH`. Cache hits and direct-LOS paths (the common cases) deliver in the same tick.

**Cancellation.** `SimMovement.stop`, a new goal, death, loading into a carrier → `cancel(entity_id)`; an active search for a cancelled request is aborted at the next `process()` (its scratch is reusable immediately because `serial` isolates it).

#### 5.3.6 Dynamic obstacles and repath triggers

| Trigger | Detection | Action |
|---|---|---|
| Structure placed/removed on or near a route | `path_ver != nav_version` *and* stride check (every 8 ticks, staggered by id): `los(cell, path[wp])` and up to two following segments still valid | invalid ⇒ `PRIO_REPATH` request from the current cell, keeping the same goal; valid ⇒ `path_ver = nav_version`. |
| Goal cell became impassable | at repath: snap goal (`nearest_passable`) | new goal cell; exact `goal_x/y` unchanged. |
| Stuck (§5.4.6) | `stuck_cnt` | repath with `avoid` = cells of blockers. |
| `FOLLOW` target moved > 3 cells from where the path was planned | stride 5, at most one re-plan / 20 ticks | new request to the target's current nearest passable cell. |
| Partial path consumed | `wp == path_n` and `MF_PATH_PARTIAL` | repath. |
| Path cache staleness | `ver != nav_version` or age > 100 ticks | miss. |
| Temporary units in corridors | *not* planned around (no crowd costs); handled by separation, push, sidestep, stuck escalation | – |
| Temporary speed effects (Horizon debris, Open Corridor, …) | stat mods inside abilities' `speed_units`; the map has no slow patches, so this is not an obstacle | none (no repath, `nav_version` unchanged). |

#### 5.3.7 Clearance, amphibious, naval, air

* **Large units.** `nav_size` (1–3) is fixed per unit from its move class and radius; the search only expands cells of its `(np,size)` graph (`node_of >= 0`), so 1–2-cell gaps between structures are foot-only. LOS/smoothing use the same clearance.
* **Amphibious mode switching.** `NP_AMPH` is a single graph where land cells carry vehicle weights and water cells `w = 23` (deep) / 18 (shallow); the route therefore flips between land and water wherever it is cheaper. Movement switches medium per cell (§5.4.3). No special path logic.
* **Naval / submerged.** `NP_NAVAL`, `NP_NAVAL_DEEP` and `NP_SUB` have their own graphs; land is blocked; `NP_SUB` and `NP_NAVAL_DEEP` additionally block `SHALLOW` and `FORD`. Size-3 ships need 5-wide deep water, which the 7-wide generated moat and canals provide.
* **Air.** No path service; direct flight (§5.6).

### 5.4 Movement, steering and collision

#### 5.4.1 Per-tick structure (`SimMovementSystem.update`)

Movers are the ids in `SimMovementSystem._movers` (entities with a `move` slot, appended in id order) that are not `F_GONE`/`F_INSIDE` and not parked aircraft (`AM_PARKED`) — idle units included, they still need separation — iterated in **ascending entity id**. Phase A and B read only the tick-start snapshot; phase C writes.

* **Phase A (intent)** per mover: goal/waypoint logic and steering (§5.4.2) produce `(new facing, new spd_q4)` and the movement vector `(vx, vy)`; idle units produce zeros. Phase A reads the speed inputs once per mover: `speed_units`, `is_immobile`, `is_turn_locked`, `suppression_speed_bp` (adapters of §3.10.1; fallbacks: `mv.speed_base`, `F_DEPLOYED|F_DEPLOYING`, 10000). Written to per-mover scratch arrays `sx, sy` (reused `PackedInt32Array`s sized to the mover count).
* **Phase B (separation)** per mover (idle units only when `(tick + id) % IDLE_SEP_STRIDE == 0` or their bucket is `hot`, §5.4.4): displacement `(px, py)` from the canonical grids (§5.4.4). Pure function of positions at tick start.
* **Phase C (apply)** in ascending id: `pos' = pos + (vx,vy) + (px,py)`, terrain rule, medium/layer switch, arrival, state advance, events, and the flag mirrors written into `e.flags` (only bits 16–19 are touched): `F_MOVING` = `spd_q4 ≠ 0` or state ∈ {MOVING, GLIDE}; `F_BLOCKED` = state `MS_BLOCKED` or `blocked_t ≥ 3`; `F_ON_WATER` = `MF_ON_WATER`; `F_AIRBORNE` = `layer == AIR`. Positions go through `world.set_pos` (which clamps to the map and re-buckets the spatial hash). Because A and B finished for all units, the result does not depend on iteration order except through the (deterministic) sequential terrain/occupancy checks of phase C.

#### 5.4.2 Steering (ground, naval, submerged; formulas in integers)

Let `T` be the target point: the centre of cell `path[wp]` for intermediate waypoints, the exact `(goal_x, goal_y)` for the final leg (no path ⇒ final leg straight to the goal). `d = T − pos`, `rd = Fp.dist(dx, dy)` (exact integer sqrt).

1. **Waypoint advance** (intermediate only): if `rd <= reach` where `reach = max(WP_REACH_MIN(384), (|spd_q4| >> 4) * 3)` then `wp += 1` and recompute (≤ 2 advances per tick). A unit may also skip `path[wp]` when `los(cell, path[wp+1])` holds and `rd <= 1536` (cheap corner cut, evaluated only when the next waypoint exists).
2. **Desired heading** `des = Fp.atan2(dy, dx)`; `err = ((des − facing + 2048) & 4095) − 2048` (range −2048..2047).
3. **Turn step** by `turn_mode`:
   * `TM_INSTANT`, `TM_PIVOT`: `rate = turn_rate`.
   * `TM_ARC` (wheeled, ships, subs, light amphibious): `frac = min(256, |spd_q4| * 256 / max(1, vcur_q4))`, `rate = (turn_rate * (64 + ((192 * frac) >> 8))) >> 8` (25 % of the turn rate at rest, 100 % at full speed — vehicles cannot pivot).
   * `facing = (facing + clamp(err, −rate, rate)) & 4095`; `a = |err − step|`.
4. **Heading factor** `f ∈ [0,256]` (fraction of `vcur_q4` allowed):
   * `TM_INSTANT`: `f = 256`.
   * `TM_PIVOT`: `a ≤ 256 → 256`; `a ≤ 768 → 256 − ((a − 256) * 256) / 512`; else `0` (tracked vehicles stop and pivot for turns > 67.5°).
   * `TM_ARC`: `a ≤ 256 → 256`; else `max(64, 256 − ((a − 256) * 192) / 768)` (creeps at ≥ 25 % while swinging round).
   * `v_turn = (vcur_q4 * f) >> 8`.
5. **Arrival braking** (final leg): `rd' = max(0, rd − goal_range)`; the stopping law looks one tick ahead, because a unit that moves `|spd_q4|/16` units per tick cannot react inside its last step: `v_arr = isqrt(32 * decel_q4 * max(0, rd' − (|spd_q4| >> 4)))` (units/tick × 16 that can still be stopped by `decel_q4` within the remaining distance); `target = min(v_turn, v_arr)`. Example, Guardian (`decel_q4 = 408`, `vcur_q4 = 1632`): at `rd' = 300` the lead term is `1632 >> 4 = 102`, `v_arr = isqrt(32·408·198) = 1607` — braking starts ≈ 2 ticks (≈ 0.3 cell) out; the continuous stopping distance is `vmax²/(2·decel) ≈ 204` units and the discrete braking sequence 1224, 816, 408, 0 covers 154. Without the lead term a full-speed Guardian reached the arrival radius at 0.85 `vmax` and had to be stopped by the overshoot clause of step 9 (measured in the independent 1-D simulation: arrival speed 1394 versus 713 with the lead).
6. **Reverse**: allowed when `reverse_pct > 0`, final leg, `|err| > 1536` (135°), `rd ≤ 4096` and (`|spd_q4| ≤ vcur_q4/4` or `MF_REVERSING` already set); then `target = −min(vcur_q4 * reverse_pct / 100, v_arr)`, `facing` is **not** turned, `MF_REVERSING` set; leave reverse when `|err| < 1024` (stop first). Used for short repositioning and backing out of factories.
7. **Speed law**: `if target > spd: spd = min(spd + accel_q4, target) else: spd = max(spd − decel_q4, target)` (signed, so it also brakes and reverses). Infantry (`accel_t 2`) reach speed in 2 ticks and stop in 1 (`decel_t 1`).
8. **Velocity**: `vx = (spd_q4 * Fp.cos(facing) + 524288) >> 20`, `vy = (spd_q4 * Fp.sin(facing) + 524288) >> 20` (Q4 × Q16 = Q20; half-up; `spd_q4 ≤ 7 400`, product < 5·10⁸).
9. **Arrival**: on the final leg, if `rd ≤ stop_r` where `stop_r = goal_range` (if > 0) else `ARRIVE_EPS (256)` (`MF_PRECISE`: 48), and `|spd_q4| ≤ 2·decel_q4` (or the unit would overshoot: `rd ≤ (|spd_q4| >> 4) + 1`): `state = MS_ARRIVED`, `result = RS_OK`, `spd_q4 = 0`; `MF_PRECISE` units snap onto the goal. `MS_ARRIVED` / `MS_NO_PATH` are *terminal states*: movement treats them as idle, they persist until the next `go_*`/`stop` or `SimMovement.ack`, and order handlers read them (then `ack`) in the next OrderSystem pass; `SimMovement.result` persists.
10. **Facing goal** (`GK_FACE`): same turn law without translation; done when `|err| < 64`.

**Infantry vs vehicles** (differences are entirely profile-driven, §4.6; one code path): infantry `TM_INSTANT`, `radius 410` (size class `inf`), `mass 1`, no reverse, 1-cell alleys (`nav_size 1`), `accel_t 2` / `decel_t 1` (stop within one tick), forest 70 %; tracked `TM_PIVOT`; wheeled/naval/sub `TM_ARC`; amphibious `TM_ARC` (light) or `TM_PIVOT` (medium and larger).

#### 5.4.3 Terrain rule, sliding, medium switching (phase C)

```
c  = cell(pos)                      c' = cell(pos')
if c' != c:
    ok = wgt[np][c'] != 0
    if ok and cell_x != cell_x' and cell_y != cell_y': ok = wgt[np][idx(cx',cy)] != 0 and wgt[np][idx(cx,cy')] != 0   # corner rule
    if not ok: try (x', y) then (x, y'); if both fail: pos' = pos; spd_q4 = spd_q4 / 2 (trunc toward 0); blocked_t += 1
if pos' out of [2048, map_units-2048]: clamp
```
Only the centre cell is tested (D-4): a size-2 unit may visually overlap a wall by up to its radius. Structures occupy whole cells and are already `wgt = 0`. After a successful cell change: `mv.cell = c'`, `mv.cell_kind = kind_at(c')`, and the top speed of §5.1 is recomputed with the new kind. The water flag follows the kind: `MF_ON_WATER` (and `F_ON_WATER`, `hl = HL_WATER`) is set when `cell_kind ∈ {SHALLOW, DEEP}` and cleared when it returns to land, but a flip is accepted only if the previous flip is ≥ 6 ticks old (`water_t`), so a unit walking a diagonal shoreline does not flicker; each accepted flip emits `STATE(ST_entered_water | ST_left_water)`. The speed law then ramps to the new top speed (e.g. 100 → 70 % for an amphibious tank entering deep water takes 1–2 ticks at `decel_q4` = `vmax/decel_t`). Ships and submarines set `MF_ON_WATER` permanently (no events); ships/subs use `HL_WATER`/`HL_SUB`.

#### 5.4.4 Separation, pushing and yielding (`SimSeparation`)

Grids: five hash layers (`HL_*`), bucket = 2048 units (2 cells), `head` arrays of `(w/2)²` int32 per layer rebuilt each tick by inserting movers **in ascending id** (`next[i] = head[b]; head[b] = i`), so bucket iteration order is canonical (descending insertion) and independent of history. Rebuild cost ≈ 0.09 µs/entity (measured 28 µs for 300). While inserting, every unit that currently has a goal and non-zero speed writes `hot[bucket] = tick` for its own bucket and the 8 neighbouring buckets (9 byte-writes; 2.7 k writes for 300 movers).

For unit `i` and each neighbour `j` in the 3×3 buckets of the same layer (stop after `SEP_MAX_NEIGHBOURS = 12` neighbours), skipping entities with `F_NO_COLLIDE`, `F_INSIDE`, parked aircraft, units in `MS_GLIDE` and units of another hash layer:

```
rs = ((r_i + r_j) * 7) >> 3                    # 12.5 % overlap tolerated (dense groups do not jitter)
dx = x_i − x_j; dy = y_i − y_j
if |dx| >= rs or |dy| >= rs: continue
d2 = dx² + dy²; if d2 >= rs²: continue
d  = max(|dx|,|dy|) + (min(|dx|,|dy|) * 3 >> 3)  # alpha-max-beta-min (≤ 4 % error, no sqrt)
if d == 0: dx = 2*((id_i ^ id_j) & 1) − 1; dy = 2*(((id_i ^ id_j) >> 1) & 1) − 1; d = 1   # deterministic direction
pen = rs − d
share = (w_j * 256) / (w_i + w_j)              # fraction of the penetration unit i resolves
push  = (pen * share) >> 8
px += dx * push / d;  py += dy * push / d      # truncating division toward zero, symmetric in sign
```
Yield weights `w = mass * (4 if the unit has an active goal and is not immobile else 1)`; an immobile (deployed, `abilities.is_immobile`) or **enemy** neighbour counts as `w = 65536` from `i`'s perspective (an enemy or a deployed unit is a wall; a moving heavy unit barely moves when shoving a light idle friend: share = 2/(24+2) ≈ 8 %). Total displacement is clamped per axis to `max(24, radius/3)`. Idle units (no goal) participate every `IDLE_SEP_STRIDE = 3` ticks, or every tick while their bucket is `hot` (a mover is within one bucket) — an order-independent wake rule because `hot` is fully written during grid construction, before phase B — this is the "push idle friendly units aside" behaviour: for equal masses the idle friend absorbs 80 % of the overlap, and a heavy mover shoving a light idle friend leaves ≈ 92 % to the friend. **Enemies:** against an enemy neighbour a unit with an active goal resolves the full penetration itself (share 256, the enemy is a wall), while a unit with no goal (or immobile) does not move at all (share 0) — so nobody ever shoves an enemy unit, and two enemy movers meeting head-on each retreat from the other.

Measured (300 entities, simplified loop): spread over the map 1.6 µs/entity/tick; six dense clumps of 50 (9.3 neighbour checks/entity, 0.83 overlaps/entity) **3.2 µs/entity/tick**, i.e. 0.95 ms for all of phases A–C skeleton.

`sidestep` (escalation from stuck detection, and to clear factory exits): `SimMovement.sidestep(ally, dir_angle, dist)` sets `GK_SIDESTEP` with a 2–3-cell target perpendicular to the requester's heading (side with the passable cell; tie → right side); at most one sidestep per ally per 20 ticks, ≤ 8 sidesteps per tick globally (extra requests wait one tick — count-bounded).

#### 5.4.5 Layers and hash-layer assignment

| Unit | `hl` | `entity.layer` (sim_core enum) |
|---|---|---|
| foot, wheeled, tracked, amphibious on land | `HL_GROUND` | `GROUND` |
| amphibious on shallow/deep water | `HL_WATER` | `GROUND` + `F_ON_WATER` (D-10) |
| naval | `HL_WATER` | `SURFACE` |
| submerged | `HL_SUB` | `UNDERWATER`; after `request_layer(SURFACE)` completes: `HL_WATER`, `SURFACE` |
| rotor aircraft airborne | `HL_AIR_LOW` | `AIR` (when `alt ≥ 512`) |
| fixed-wing airborne | `HL_AIR_HIGH` | `AIR` |
| parked / landed aircraft | none (`AM_PARKED`) | `GROUND` |

Movement writes `entity.layer` **only** for aircraft (`air_takeoff`/`air_land_at`) and submarines (`request_layer`), through `world.set_layer`; everything else is set at spawn by sim_core.

#### 5.4.6 Stuck detection and resolution

Every `STUCK_STRIDE = 10` ticks (staggered by `(tick + id) % 10 == 0`), for units with an active goal that are not paused, gliding or immobile (`abilities.is_immobile` or `vcur_q4 == 0`, e.g. a rooted or EMP-slowed unit is not "stuck"):
`expected = ((vcur_q4 * 10) >> 4) * STUCK_MIN_PCT / 100` units; `if dist²(pos, stuck_ref) < expected²: stuck_cnt += 1 else stuck_cnt = 0`; `stuck_ref = pos`. Escalation (the repath step sits at `STUCK_REPATH_TICKS = 40`, balance's `movement_defaults.stuck_repath_ticks`, i.e. 4 stride counts):

| `stuck_cnt` (×10 ticks) | Action |
|---|---|
| 1 | If `blocked_by` is an idle friendly unit: `sidestep` it. |
| 2 | Nudge: `nudge_t = 10`, lateral velocity of 40 % `vcur` toward `nudge_dir` (= +90° if `id` even else −90° of heading). |
| 4 (= 40 ticks) | Repath (`PRIO_REPATH`) with `avoid` = cells of `blocked_by` and ≤ 3 nearest idle/immobile neighbours (≤ 8 cells). |
| 6 | If `dist_to_goal ≤ 6 cells` (crowded destination) ⇒ arrive-near (`MS_ARRIVED`, `RS_OK`); else repath again. |
| 8 | Fail: `state = MS_IDLE`, `result = RS_STUCK` (the order handler returns FAILED ⇒ `ORDER_FAILED`). |

**Arrive-near** also triggers earlier when `blocked_t ≥ 8` and the blocker is an idle friendly within 4 cells of the goal (units queueing for a full formation stop instead of shoving).

#### 5.4.7 Bounded work summary (all by count)

`SEP_MAX_NEIGHBOURS = 12` per unit; idle separation stride 3; stuck stride 10; validity stride 8 (only if `nav_version` changed); follow stride 5; sidesteps ≤ 8/tick; path units ≤ 1600 + 200·min(pending, 8)/tick; deliveries ≤ 16/tick; dirty (block,graph) units ≤ 12/tick; group formation ≤ 200 units per group (larger selections are split in id order).

#### 5.4.8 State machine of `SimMoveComp.state`

| State | Entered when | Behaviour per tick | Leaves to |
|---|---|---|---|
| `MS_IDLE` | no goal; after `ack`/`stop`/glide end | takes part in separation only (stride 3, or every tick while a mover is near) | `MS_WAIT_PATH`/`MS_MOVING` on `go_*`; `MS_GLIDE`; `MS_FACING`; `MS_SIDESTEP`; `MS_EVICT` |
| `MS_WAIT_PATH` | `go_*` whose path is not available in the same tick | rotates toward the goal (`TM_INSTANT`/`TM_PIVOT`/`TM_BANK`) or holds (`TM_ARC`); at most `PATH_WAIT_MAX` ticks | `MS_MOVING` on delivery; `MS_NO_PATH` (`RS_NO_PATH`) on timeout or `ST_NO_PATH` without an alternative goal |
| `MS_MOVING` | a path / a direct goal exists | steering of §5.4.2 | `MS_ARRIVED` (`RS_OK`, or `RS_PARTIAL` when the walked path was partial); `MS_BLOCKED`; `MS_PAUSED`; `MS_NO_PATH` (repath failed) |
| `MS_BLOCKED` | the terrain rule rejected the move for ≥ 3 consecutive ticks (`blocked_t ≥ 3`) | as `MS_MOVING` plus the escalation of §5.4.6 | `MS_MOVING` when free again; `MS_NO_PATH` with `RS_STUCK` at stride count 8 |
| `MS_NO_PATH` | terminal: `RS_NO_PATH` or `RS_STUCK` | idle (separation as `MS_IDLE`) | `MS_IDLE` on `ack`/`stop`; `MS_WAIT_PATH`/`MS_MOVING` on the next `go_*` |
| `MS_ARRIVED` | terminal: goal reached | idle | `MS_IDLE` on `ack`/`stop`; the next `go_*` |
| `MS_PAUSED` | `pause` (combat engages during attack-move) | decelerate to 0, keep goal and path | `MS_MOVING` on `resume`; `MS_IDLE` on `stop` |
| `MS_GLIDE` | `glide` | linear interpolation, no terrain rule, no separation | `MS_ARRIVED` after exactly `ticks` ticks; any `stop`/`go_*` cancels in place |
| `MS_FACING` | `turn_to` / `T_FACE` | the turn law of §5.4.2 without translation | `MS_IDLE` when `\|err\| < 64` |
| `MS_SIDESTEP` | `sidestep` request | short two-cell goal, ignores formation | `MS_ARRIVED` → `MS_IDLE` |
| `MS_EVICT` | ejected unit with no free cell / unit standing on a blocked cell | moves at 2× speed toward the nearest passable cell, ignoring the blocked-cell weights | `MS_IDLE` on a passable cell or after 40 ticks |

A goal set by `go_*` while a unit is `MS_GLIDE`/`MS_EVICT` cancels those states; a refused `go_*` (immobile, `RS_NO_MOVE`) leaves the state untouched and sets `result`.

### 5.5 Formations (`SimFormation`, same-tick group moves)

Goal: arrival slots that keep the group's relative arrangement and avoid pile-ups; groups travel as independent units on shared paths. sim_core has **no group command**: the built-in executor turns `MOVE(ids, x, y)` into one `T_MOVE` per actor (same `x, y`, same tick), so the group is recovered inside the handler.

**Group detection.** `SimOrderMove.begin` of a unit `u` whose fresh `T_MOVE` has `OF_NO_FORMATION` clear and whose move class is ground calls `SimFormation.group_of(world, u, o, ids)`:

1. If `u.move.fslot_tick == world.tick` a group leader already assigned `u`'s slot in this tick's pass: use `(fslot_x, fslot_y)` and stop.
2. Otherwise collect the owner's alive units (`world.units_of(owner)`, ascending id) whose `orders[0]` is a `T_MOVE` in `PH_NEW` (not yet begun) or begun in this tick (`t0 == world.tick`) with the same `x, y`, `OF_NO_FORMATION` clear, ground class, with a `move` component, at most 200 (the first 200 by id; the remainder is a second group at its own `begin`). `u` is the lowest id among the not-yet-begun members and therefore the **leader**: it runs `assign` and writes every member's slot into that member's `SimMoveComp` (`fslot_x`, `fslot_y`, `fslot_tick = world.tick`). Members later in the same stage-5 pass find their slot ready (step 1).
3. A unit whose `T_MOVE` sits behind another order (queued with `QM_APPEND`) is not `PH_NEW` at issue time and forms no group; when its turn comes it looks for a group again with whichever units begin the same destination in that tick (typical for a group finishing the previous leg together).

**`SimFormation.assign` algorithm.**

1. `n = ids.size()` (≤ 200). `n == 1`: slot = target. Group centroid `C = (Σx / n, Σy / n)` (truncating, coordinates non-negative).
2. Heading `θ = Fp.atan2(ty − Cy, tx − Cx)`; if `|target − C| < 2048` (group already at the target) use `θ = facing` of the lowest-id unit instead. Forward `f = (cos θ, sin θ)`, right `r = (−sin θ, cos θ)` (Q16).
3. `rmax` = largest radius in the group; `spacing = clamp(2·rmax + EXTRA, 1024, 3072)` with `EXTRA = round(movement_defaults.formation_spacing_cells_extra · 1024) = 461` (0.45 cell); `cols = clamp(isqrt(3n/2), 1, 12)`; `rows = ceil(n / cols)`.
4. For each unit `u = ((x−Cx)·f_x + (y−Cy)·f_y) >> 16`, `v = ((x−Cx)·r_x + (y−Cy)·r_y) >> 16`. Sort units by key `((−u + 2²⁰) << 44) | ((v + 2²⁰) << 24) | id` (a `PackedInt64Array.sort()` — total order, ids < 2²⁴) → front-to-back order. Rows of `cols` in that order (last row possibly short, centred); inside a row sort by `(v, id)` and assign columns left→right.
5. Slot `(row i, col j)`: `lat = ((2j − (cols_in_row − 1)) * spacing) / 2` (truncating); `pos = T + f·(−i·spacing) + r·lat` (rows extend *behind* the target relative to travel direction).
6. Snap each slot: if its cell fails `clr >= nav_size` for the unit's profile, use `nearest_passable(np, size, cell, 8)`; none ⇒ the target itself.

All units of the group share the path `goal_cell` = cell of `T` (snapped once, so the path cache serves 1–3 searches); their final leg replaces the last waypoint by the slot (a unit skips ahead to its slot as soon as `los(cell, slot_cell)` holds within 6 cells of the goal). **Speed matching** is off by default (a MOVE command has no speed-match flag; `MOVE.FLAGS` bit0 is "no formation"); `movement.json → formation.speed_match = 1` turns it on for every formation of ≥ 2 units (`speed_cap_q4 = min(speed_base·16)` of the members), and `OPT_SPEED_MATCH` requests it per call (AI, combat).

*Worked example.* Four units (ids 10..13, radius 400) at cells (10,10),(11,10),(10,11),(11,11) i.e. positions (10240,10240),(11264,10240),(10240,11264),(11264,11264); target (20480, 10752). `C = (10752, 10752)`, `θ = 0`. `spacing = 2·400 + 461 = 1261`, `cols = 2`, `rows = 2`. Keys sort to order `[11, 13, 10, 12]` (u = +512 for 11, 13; v = −512, +512, …). Slots: unit 11 → (20480, 10122), unit 13 → (20480, 11382), unit 10 → (19219, 10122), unit 12 → (19219, 11382) (`lat = ±(1261/2) = ±630`). Expected by the unit test (§10).

### 5.6 Air movement (`SimAirMove`: flight primitives, not sorties)

**Split of responsibility (combat.md §5.12, economy.md §5.14).** Combat owns *what* an aircraft does (sortie state machine, targets, attack styles, fuel, ammo, pad choice through economy's `airfield_pad_acquire/release/cell`); this domain owns *how it flies*: the kinematics behind `air_fly_to`, `air_orbit`, `air_hover`, `air_face`, `air_takeoff`, `air_land_at`, `air_at_goal` (§3.10.2). Aircraft never use the path service, terrain or pads tables. The entity's `layer` changes **only inside `air_takeoff` (→ AIR) and `air_land_at` (→ GROUND)** via `world.set_layer`; combat must not write it for aircraft (§13). Parked aircraft (`AM_PARKED`) are skipped by the mover loop and the separation grids at zero cost; they remain ordinary ground targets.

**Models.** `AIR_FIXED` (fighters, bombers, EW; `global.json aircraft.fixed_wing_units`): cannot hover, `TM_BANK`, minimum airborne speed `movement.json air.fixed_min_speed_pct = 60` of `vcur`, hash layer `HL_AIR_HIGH`, cruise altitude 6144. `AIR_HOVER` (gunships, strike drones; `hover_units`): decelerates to a stop, free yaw at `turn_rate`, `HL_AIR_LOW`, cruise altitude 2560. Speed = `speed_units(e)` (air rows of the table are 100 %). Altitude and climb rates are cosmetic (view/audio) except that the layer flips when `alt ≥ 512`.

* **Flight step** (phase C, per airborne aircraft): `alt += clamp(alt_goal − alt, −descend, +climb)`; heading/speed by mode; integrate like §5.4.2 step 8; no terrain rule; `F_AIRBORNE` while `layer == AIR`. Within 2048 units of the map edge the desired heading is overridden toward the map centre (turn priority).
* **`air_fly_to(x, y)`**: `AM_CRUISE`. Fixed-wing steers with `TM_BANK` (`rate = turn_rate`, constant speed `vcur`); when `rd ≤ arrive_r = turn_radius + 512` (`turn_radius = v / ω`, e.g. 9 cells/s at 180°/s ⇒ 2.9 cells) it latches `at_goal` and continues in a holding pattern (`AM_ORBIT` of radius `movement.json air.orbit_r_default = 4096` around the point) until the next command. Rotor: ground-style steering with accel/decel and free rotation; arrives at `rd ≤ 256`, then `AM_HOVER`.
* **`air_orbit(cx, cy, r, dir)`**: `AM_ORBIT`; `radial = atan2(y − cy, x − cx)`; `tangent = radial + dir·1024`; `corr = clamp(((d − r) * 512) / r, −512, 512)`; `des = tangent − dir·corr` (outside the circle ⇒ aim inward). Rotor: flies the same law at reduced speed (no stall).
* **`air_hover`**: rotor → `AM_HOVER` (`spd → 0`, position held); fixed-wing → `air_orbit` around the current position with the default radius.
* **`air_face(bat)`**: rotor yaws in place at `turn_rate` (combat's `AS_HOVER` attack style needs this); fixed-wing: no-op.
* **`air_takeoff(ticks = 0)`**: from `AM_PARKED` on the ground. Fixed-wing: roll along `facing` accelerating with `accel_q4` (≈ 12 ticks to 60 % `vmax`) with `alt = 0`, then climb 128 units/tick; rotor: vertical climb 96 units/tick. When `alt ≥ 512`: `world.set_layer(e, AIR)`, `F_AIRBORNE`, event `STATE(id, ST_takeoff, 0, 0, x, y)`; the climb continues to cruise altitude and the aircraft then holds a pattern at the take-off point. With `ticks > 0` the climb rate is scaled so the layer flip happens exactly at tick `ticks` (combat's `takeoff_ticks`).
* **`air_land_at(x, y, heading = −1, ticks = 0)`**: `AM_APPROACH`: fixed-wing flies to the approach point `A = pad − dir·5120` (5 cells before the touchdown point along `heading`; −1 = the current bearing to the pad, straight-in) at `alt_goal = 1024`, then steers at the pad while `alt = 1024·dist/5120`, speed ramping down to 35 % `vmax` at touchdown; rotor flies above the pad, then descends at 64 units/tick. Touchdown (`AM_LANDING → AM_PARKED`): position snapped to `(x, y)`, `spd 0`, `world.set_layer(e, GROUND)`, `F_AIRBORNE` cleared, event `STATE(id, ST_landed, 0, 0, x, y)`; `air_at_goal` becomes true. With `ticks > 0` the final descent lasts exactly `ticks` ticks (combat's `landing_ticks`). The pad cell comes from economy's `airfield_pad_cell` (`ASSUMPTION(economy)`); who owns the pad is not this domain's business.
* **Aircraft separation**: air grids only (`HL_AIR_LOW/HIGH`), stride 2, radius 600; parked aircraft never collide. Combat moves crashing aircraft itself (it calls nothing here; the mover loop skips `F_DEAD`).
* **Order handler**: `T_LAND` (`SimOrderAir`) = `air_land_at(x, y)` and DONE on `air_at_goal`; it exists so the AI/QA can land aircraft without combat's sortie machine.

### 5.7 Naval, submerged, amphibious specifics

* Ships: `TM_ARC`, no reverse, `mass ≥ 3`, nav size 2 (small/medium hulls) or 3 (radius > 1.1 cell). Production places them in a berth water cell (economy); they leave through normal pathing. Shore contact is prevented by clearance (a size-2 ship stays ≥ 1 cell off land, a size-3 ship ≥ 2), shallow water costs `w = 20` (small hulls only) so ships prefer deep channels; hulls with radius ≥ 0.9 cell (`NP_NAVAL_DEEP`) never enter shallow water, including fords.
* Submarines: `NP_SUB` (deep only); `hl = HL_SUB`; surfacing/submerging is `SimMovement.request_layer(SURFACE|UNDERWATER, ticks)` called by abilities/combat (`want_surface`); the layer flips after `ticks`, emitting `STATE(id, ST_surfaced|ST_submerged)`. While `layer == SURFACE` the unit uses hash layer `HL_WATER`.
* Amphibious: §5.4.3; enters/leaves water anywhere a route crosses a shoreline (cliffs still block; forest at 50 %); `F_ON_WATER` toggles on SHALLOW/DEEP cells with events `STATE(ST_entered_water|ST_left_water)`; beaches are ordinary open ground (`w = 16`). Land passengers cannot board a carrier that floats farther than 2 cells off a reachable shore cell (`T_LOAD` fails, §5.8).
* Landing Transport unloading onto land: `T_UNLOAD` moves the carrier to the reachable cell nearest the drop point (its shore), then abilities' exit search places passengers (§5.8).

### 5.8 Boarding, unloading, garrison entry (`SimOrderCargo`; cargo state is abilities' `SimTransport`)

Division of labour (`ASSUMPTION(abilities)`: abilities.md §5.10, sim_core `set_inside`): `SimTransport` decides *whether* a passenger may enter (capacity in squad/vehicle slots, class exclusions, team/claim), *when* (`load_t`, `unload_t`, `unload_speed_bp`), *where passengers appear* (exit-cell ring search 1..3 over `map.passable`), what happens on carrier death (`eject_all`), and it owns `container_id`/`holder`, `F_INSIDE` and the `LOADED/UNLOADED` events. This domain moves units so those calls can be made.

**`T_LOAD`** (passenger `e`, `target` = transport):
1. `begin`: FAILED unless `SimTransport.can_board(world, carrier, e)`; otherwise `SimMovement.approach_entity(e, carrier, reach = 2048)` (the passenger walks to within 2 cells of the carrier's footprint; abilities.md: "orders walk the passenger to within 2 cells first"). A carrier that floats farther than 2 cells from any cell reachable for the passenger's profile makes the path end short: the order fails with `RS_NO_PATH` after arrival (UI: "transport must be at the shore").
2. `tick`: when `dist(e, carrier) ≤ 2048`: `SimTransport.board(world, carrier, e)` → true: DONE (the passenger is `F_INSIDE` from now on; the dispatcher skips it and `SimTransport` mirrors its position); false → FAILED. If the carrier moves, `approach_entity` re-plans (target moved > 3 cells, ≤ 1 re-plan per 20 ticks). Timeout: 600 ticks (30 s) → FAILED.
3. The carrier is not held here: it is `DF_IMMOBILE` for `load_t` after a passenger boards (abilities), which is all the "waits for its cargo" behaviour the bible asks for.

**`T_GARRISON`** (infantry, `target` = neutral garrison building): identical, with `SimTransport.can_board`/`garrison_enter`; approach target = the nearest passable cell adjacent to the footprint (`approach_entity` handles rectangle targets), reach 512 from the footprint edge.

**`T_UNLOAD`** (carrier `e`; `arg` bit0 = unload in place, bit1 = all; `x, y` = drop point):
1. `begin`: in place or no point ⇒ `SimMovement.stop(e)`; otherwise `go_near(x, y, 3072)` — the ring search of abilities starts at the requested point and covers rings 1..3, so the carrier must end within ~3 cells of it. A carrier that cannot enter the drop cell (a Landing Transport at a shoreline) stops at the reachable cell nearest to it (`nearest_passable` on its own profile) — the shore.
2. `tick`: once the carrier is stationary (`state ∈ {IDLE, ARRIVED}`, `spd_q4 = 0`, i.e. combat's `still_ticks ≥ 1` condition) call `SimTransport.begin_unload(world, carrier, mode, 0, drop_x, drop_y)` with `mode` 0 = all / 1 = one from `arg`, and the drop point when it is within 4 cells of the carrier, else the carrier position; then RUNNING until `SimTransport.cargo_of(carrier)` is empty (all) or one passenger has left (mode one) → DONE. Timeout `pax · unload_t + 100` ticks → FAILED. Unloading while moving ("Mobile Reserve") needs no code here: the ability lowers `speed_units` and sets `DF_UNLOAD_MOVING`; the handler simply does not require stationarity when that flag is set.
3. Structures (`UNLOAD` on a garrison building, `AK_ANY`): sim_core lets the cargo owner register its own executor; the handler is unit-only, so abilities' executor calls `SimTransport.begin_unload` directly for structures.

### 5.9 Exits, spawn placement, eject and scripted moves (`SimExitMove`)

**`find_free_cell_near(cell, layer, max_radius)`** (economy.md §5.4 exit search, `ASSUMPTION(economy)`). Default profile by layer: GROUND → `NP_WHEELED`/size 2 (conservative for infantry too), SURFACE → `NP_NAVAL`/size 2, UNDERWATER → `NP_SUB`/size 2, AIR → the cell itself. Rings `r = 0..max_radius` in the fixed ring order of §5.2 (ring 0 is the cell); a cell qualifies iff `nav.passable(np, size, i)`, `occ[i] < 0` and no living entity of the same layer with `F_NO_COLLIDE` clear has its centre within `600` units of the cell centre (`world.query_radius`, ≈ 7 µs per candidate cell; typical exit search tests 1–3 cells, worst 81). First qualifying cell wins (ties are impossible: ring order is a total order); −1 if none.

**`eject_units_from_rect(x0, y0, x1, y1, team)`** (placement of a structure over friendly units; economy.md §5.3): the cell rectangle is inclusive. Units of `team` (`world.team_of(owner) == team`) with a ground/surface layer whose centre lies inside are processed in **ascending id**: each is moved with `world.set_pos` to the nearest qualifying cell *outside the rectangle* (`find_free_cell_near` skipping cells inside the rectangle, 6 rings), `spd_q4 = 0`, goal cleared (`MS_IDLE`); if no cell exists the unit keeps its place and `MS_EVICT` starts (it drives out at the first opportunity, ignoring the blocked-cell weights, ≤ 40 ticks). Because the structure entity appears in the same tick, no unit may remain inside a footprint for longer than one pass. Enemy and neutral units are not moved (economy rejects such a placement).

**Glide (`SimMovement.glide`)**: `MS_GLIDE` interpolates `pos = p0 + (p1 − p0)·t/n` for `t = 1..n` (truncating division of the whole product, endpoints exact), writes `facing` once at the start (`face_angle`, default `atan2(p1 − p0)`) and ends in `MS_ARRIVED` at `p1`. While gliding the unit is excluded from steering and from the separation grids (others do not push it and it pushes nobody), the terrain rule is skipped (the target may lie inside a structure footprint: a Collector that "enters" its refinery), and a new goal/stop cancels it where it stands. Economy's dock-in is `glide(dock_cell, 12)`, dock-out `glide(exit_cell, 8)` (economy.md §5.9).

**Rally, clear-the-door.** Production spawns at the exit cell (`find_free_cell_near`) and issues `T_MOVE` to the rally point through `world.orders`; a unit with no rally simply idles at the exit and is pushed aside by later spawns (idle friendly units yield to movers, §5.4.4; further spawns take neighbouring free cells, so a door cannot deadlock until `QS_PAUSED_EXIT`). There is no automatic clear-the-door move (R9 recommends economy issue a short default rally).

**Sidestep** (escalation from stuck detection and to clear exits): `SimMovement.sidestep(ally, dir_angle, dist)` sets `GK_SIDESTEP` with a 2–3-cell target perpendicular to the requester's heading (side with the passable cell; tie → right side); at most one sidestep per ally per 20 ticks, ≤ 8 per tick globally (extra requests wait one tick — count-bounded).

### 5.10 Terrain-side build predicates, blocking and shoreline

Placement validity is economy's `SimPlacement.validate` (economy.md §5.3, ten ordered rules: margin, build radius, terrain, structure overlap, deposit, debris, units, apron, shore, strategic). This domain supplies the map facts those rules read and the blocking effect of a placed structure:

| economy rule | supplied by | note |
|---|---|---|
| 1 footprint inside the map with a 1-cell margin | `MapBuildRules.check_land(cells, margin = 1)` → `PR_OUT_OF_BOUNDS` | the rim (6 cells) is `SF_NOBUILD` and unbuildable terrain, so the margin is never the binding constraint |
| 3 terrain | `MapData.is_buildable` (`TF_BUILD` terrain: grass, dirt, sand, pavement; no `SF_NOBUILD/SF_BLOCK`) → `PR_TERRAIN`/`PR_NOBUILD` | beach only with `shore_ok` (Dock) |
| 4 structure overlap | `MapData.structure_at(i)` (`occ`) → `PR_OCCUPIED` | one grid: `world.struct_grid` of economy/render **is** `map.occ` |
| 5 deposit | `SF_NOBUILD` is set on every deposit cell and its Chebyshev-1 ring by the generator; economy's own `deposit_mask` (cell centre within a field radius) stays valid | collectors always keep a lane |
| 8 apron | `MapData.is_passable_ground(cx, cy)` (static terrain, ignores structures) | the apron cells themselves are economy's data (`structure_rules.json`) |
| 9 shore (Dock) | `MapBuildRules.check_berth(berth_cells)` + `has_adjacent_water`: every berth cell DEEP water, one water body of ≥ 30 cells (`water_body_size`), whose naval component has ≥ 100 cells | rotation of the berth is economy's (`MapFootprint.rotate_offset` helper); `PR_NEEDS_WATER`/`PR_WATER_EXIT` → economy's `NEEDS_SHORE` |

Mapping `PR_* → RSN_*` (economy.md §4.1): `PR_OUT_OF_BOUNDS, PR_TERRAIN → TERRAIN`; `PR_OCCUPIED → STRUCTURE_BLOCK`; `PR_NOBUILD → DEPOSIT` on deposit rings, `TERRAIN` elsewhere (economy distinguishes by its own deposit mask first); `PR_NEEDS_WATER, PR_WATER_EXIT → NEEDS_SHORE`.

* **Blocking.** `occupy(sid, cells)` sets `occ[cell] = sid` and weight 0 in all seven nav profiles there; clearance around it is recomputed (a 1-cell gap between two structures has `clr = 1` ⇒ foot-only; clearance/graph refresh is deferred, §5.2). Air and `STATIC` ignore it. No structure is walkable. `vacate(sid)` is the exact inverse from the stored cell list.
* **No global spacing rule.** Aprons (per structure, economy's data) are the only keep-clear areas; buildings may touch, walls of buildings are legal, and pathing degrades to "nearest reachable" (`RS_PARTIAL`). The AI must not seal its own base (it keeps ≥ 3-wide lanes: `MapBuildRules.scan` and `MapNav.passable` answer that). Vehicles need ≥ 3-wide passages; gaps of 1–2 cells between structures are foot-only (R7).
* **Slope.** The sim is 2-D. Steep terrain is already unbuildable because the generator classifies cliff bands and ramps (`ROCK`/`CLIFF`); the height layer is view-only.
* **Not here (owner):** build radius, prerequisites, power, unit blocking (`eject_units_from_rect` is called by economy), debris (`zones.blocks_construction`), strategic limit — all economy/abilities.
* **Neutral structures** are placed by the generator on cleared lots (`SF_NOBUILD` on lot + ring 1) and spawned by `SimWorld` from `map.objects` through `spawn_structure(-1, …)` (sim_core constructor step; economy.md §13-11). Like every structure entity (player structures, start HQs), they are registered on the map by the domain that owns structure lifecycle (economy's `SimStructureLife` in its `on_spawn`/`activate` hook): `MapData.occupy(id, cells)` with `MapFootprint.cells(...)`, and `vacate(id)` in `on_removed`.

### 5.11 Bible-rule compliance (movement/terrain domain, consolidated)

Covered rule-by-rule in §5.1 (terrain, water, forest, roads, amphibious, Collector, Mamba, speed powers, debris) and §5.5–5.10 (formations, air, garrisons, docks). Two cross-cutting guarantees deserve their own statement:

* **"Every roster is playable on a land-only map"** is enforced at four levels: (1) no footprint, unit or ability in this domain *requires* water; the Dock is the only water-dependent build and nothing unlocks through it; (2) the generator's connectivity validation (V1, V3, V5, V8) is evaluated on the guarantee set (land + fords; the intersection of the foot, wheeled and tracked passable sets) where deep and ordinary shallow water are impassable; (3) `water_pct = 0` produces a truly dry map (no moat, no beaches, no marsh) and the safe template is dry; (4) every neutral and every deposit lies in the starts' component, so no objective needs a transport.
* **"At least two exits from each starting area"** is guaranteed constructively (≥ 2 carved 5-wide gates per start: one toward the centre, ≥ 1 toward the nearest neighbour through an outward-bulging midpoint) and verified (V2).

### 5.12 Map generator

#### 5.12.1 Parameters, sizes, family defaults

`MapGenParams.from_config(map_cfg)` reads the lobby dictionary (net.md §7.1: `{"family": 0, "layout_players": 4, "params": {}, "seed": 20240517, "size": 128}`); every other parameter has a default. Unknown keys are ignored (forward compatible) but enter the canonical `to_ints()` only if known, so two peers with the same `config_hash` generate the same map.

| Param | Range | Default | Meaning |
|---|---|---|---|
| `size` | 96..256 step 8, ≥ `min_size(slots)` | `recommended_size(players)` = 2→128, 3→144, 4→160, 5–6→192, 7–8→224 | square map, includes the 6-cell rim |
| `family` | 0 open, 1 urban, 2 coast/river | 0 | see below |
| `seed` | 0..2³²−1 | 1 | all randomness derives from it (no RNG state) |
| `layout_players` (`slots`) | {2,3,4,6,8} | 2 | number of start positions; `min_size` = 96 / 112 / 128 / 160 / 192; unused slots keep their base area and fields (extra expansions); `MapData.fair_slot_order(players)` = greedy farthest-point order tells the lobby which start indices to fill |
| `water_pct` | 0..40 (−1 = family default) | open 0, urban 0, coast 22 | share of cells at or below sea level (histogram percentile) |
| `density` | 0..100 | 50 (coast 40) | clutter: forest 3·d ‰, rock band d ‰, plateau zone 250 + 4·d ‰ |
| `resources` | 0..100 | 50 | credit scale = `(50 + resources)` % of the tabled per-cell amounts (50 %..150 %) |
| `neutrals` | 0..100 | 50 | neutral count scale `(neutrals + 25)/75` |
| `biome` | 0..2 | 0 | temperate / arid (base DIRT + 18 % SAND) / arctic (view palette only); the urban family forces `MapData.biome = 3` |
| `start_near_water` | bool | false | coast only: every start gets a bay with a valid Dock site inside the build radius (qa.md XR-24, DA-29) |

Family definitions: **Open land** — rolling terrain, terraced plateaus with ramps, forests and rock bands, straight-ish trunk roads, open centre. **Urban** — flat; a street lattice (streets 4 wide, avenues 6 wide every third street, block pitch `16 + size/96`), building blocks (`URBAN_BLOCK`), parks (`GRASS`), plazas (`PAVEMENT`), foot-only 1-cell alleys, rubble patches (1/64 of street cells), many garrisonable neutrals; vehicles are confined to 4-wide streets (two usable lanes) and avenues. **Coast/river** — island falloff toward the map rim (sea), a meandering **moat river** ring around the centre (6 deep + 2 shallow bank cells each side = 10 wide), beaches, marsh fringes (land within 3 cells of water where a noise field exceeds a threshold), fords where the gate corridors cross water, and with `start_near_water` a straight canal (7 deep, 11 with banks) from each start's pocket to the sea.

#### 5.12.2 Integer noise (exact; test vectors in §10)

```gdscript
static func mix32(x: int, y: int, s: int) -> int:        # 32-bit result; all intermediates < 2^62
    var h: int = (x * 374761393 + y * 668265263 + s * 1274126177 + 1013904223) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) & 0xFFFFFFFF
static func hash2(x: int, y: int, s: int) -> int: return mix32(x, y, s) & 0xFFFF
static func vnoise(x: int, y: int, shift: int, s: int) -> int:        # 0..65535, lattice spacing 2^shift, smoothstep in Q16
    var cs: int = 1 << shift;  var xi: int = x >> shift;  var yi: int = y >> shift        # >> floors for negatives
    var fx: int = ((x & (cs - 1)) << 16) >> shift;  var fy: int = ((y & (cs - 1)) << 16) >> shift
    var sx: int = (((3 << 16) - 2 * fx) * fx >> 16) * fx >> 16;  var sy: int = (((3 << 16) - 2 * fy) * fy >> 16) * fy >> 16
    var a := hash2(xi, yi, s); var b := hash2(xi + 1, yi, s); var c := hash2(xi, yi + 1, s); var d := hash2(xi + 1, yi + 1, s)
    var top: int = a + (((b - a) * sx) >> 16);  var bot: int = c + (((d - c) * sx) >> 16)
    return top + (((bot - top) * sy) >> 16)
static func fbm(x: int, y: int, s: int, base_shift: int) -> int:      # 4 octaves, weights 8,4,2,1, /15
    return (vnoise(x,y,base_shift,s)*8 + vnoise(x,y,base_shift-1,s+1)*4 + vnoise(x,y,base_shift-2,s+2)*2 + vnoise(x,y,base_shift-3,s+3)) / 15
```
(Non-negative division, so truncation is exact.) The same code was executed in the engine and in an independent Python emulation and gave identical results (vectors in §10). Naive cost **3.85 µs per cell for 4 octaves**; a lattice-cached implementation (hash each lattice node once per octave, interpolate rows) is expected ≈ 2× faster and is an allowed optimisation because outputs are identical.

#### 5.12.3 Symmetry (`MapGenSymmetry`)

Doubled coordinates: `x2 = 2x + 1 − w`, `y2 = 2y + 1 − h` (odd; map centre = 0,0); cell of a doubled point `p` is `(p + w − 1) >> 1`; `R = w/2`.

| slots | group | images `k` (map `img_pt(k, x2, y2)`) | exact? |
|---|---|---|---|
| 2 | D1X (mirror x) | `k=1: (−x2, y2)` | exact |
| 4 | D2 (mirror x and y) | `k&1: −x2`, `k&2: −y2` | exact |
| 8 | D4 (dihedral, 8) | `k&1: sign x`, `k&2: sign y`, `k&4: swap` | exact |
| 3, 6 | DN (rotation by `k·4096/N`, Q16 rotation with half-up rounding; terrain folded by angle) | `(x2·c − y2·s + 32768) >> 16, (x2·s + y2·c + 32768) >> 16` | ≈ ±1 cell (measured 12–21 % of sampled cells differ in class, all on class boundaries) |

`fold(x2, y2) → (fu, fv)` (cells; the noise domain): D1X `fu = (|x2|−1) >> 1, fv = y2 >> 1`; D2 `fu = (|x2|−1) >> 1, fv = (|y2|−1) >> 1`; D4 additionally swap so `fu ≥ fv`; DN: `ang = atan2(y2, x2)`, `t = (ang·N) & 4095`, `if t > 2047: t = 4095 − t`, `a2 = t / N`, `r = isqrt(x2² + y2²)`, `fu = (r·cos a2) >> 17`, `fv = (r·sin a2) >> 17` (mirror fold inside each sector ⇒ continuous seams). **Every terrain-affecting per-cell random value uses `(fu, fv)`, never raw `(x, y)`** — this, plus the cliff rule below, gave 0/1000 mismatches for D1X/D2/D4 in the prototype (with forward-difference cliff detection and raw-coordinate scatter it was 5–6 %). In the v4 prototype the only residue is ≤ 0.7 % (7/1000) of sampled cells, all in neutral lots (axis-aligned lots of odd/even size land one cell off in mirrored images).

**Painting primitives** (`MapGenLayout`): a primitive is defined by control points in doubled coordinates; it is **painted once per image with the transformed control points**, and a cell is covered iff an exact integer predicate holds; all primitives are clipped to the playable interior `[RIM_W, size − RIM_W)`:
* disc: `dx² + dy² ≤ (2r)²` (doubled offsets);
* axis-aligned rectangle (`paint_rect2`: bay pockets and canals): `|dx| ≤ hx2 and |dy| ≤ hy2`, half extents swapped for D4 images with the swap bit; DN images keep the axes (the centre alone is rotated), so bays stay dock-friendly;
* segment of half-width `hw2` (doubled units): with `e = b − a`, `den = e·e`, `num = (p−a)·e`: `num ≤ 0 → |p−a|² ≤ hw2²`; `num ≥ den → |p−b|² ≤ hw2²`; else `cross² ≤ hw2² · den` (no division);
* route: `a → m → b` with `m` = midpoint displaced perpendicular by `((hash2(ax2+97, ay2+31, seed + bx2·3 + by2·5) − 32768) · amp2) >> 15` (`amp2 = 24` ⇒ ±12 cells), painted as two segments — `disp` is computed once from the canonical control points. Trunk routes also record their three control points per image as a road polyline (`MapData.roads`, 1/16 cell).
Mirror images of a predicate are exactly the predicate of the mirrored points, so D1X/D2/D4 maps are bit-symmetric; rotation images are symmetric to ≤ 1 cell and hole-free (rasterising transformed primitives avoids the gaps that mapping rasterised cell lists through a rounded rotation leaves — measured 22/24 failures with cell-list mapping, 0/24 with primitives).

Paint modes: `CLEAR` (forest/cliff/rock/urban/rubble/marsh → `DIRT`, deep and shallow water → `FORD`; open ground untouched = invisible gates), `FORCE t`, `ROAD` (water → `FORD`, else `t`). Each painted cell is recorded in the generator-local `keep` mask (excluded from beach/forest/scenery/marsh placement).

**Start order.** `img_pt(k, p0)` gives the start of image `k`; the published order (`start_cells`, `spawns`) sorts the starts by `atan2(y2, x2)` around the map centre, counter-clockwise from the +x axis (ties: lowest image index), so **adjacent start indices are adjacent positions** (net.md XR-12: teammates end up neighbours) and the 2-slot map has starts 0 (east) and 1 (west). `orbit` in `spawns` keeps the image index. `team_hint = index & 1`.

#### 5.12.4 Phase A — terrain synthesis (expensive, run once per attempt)

1. **Height & noise fields** for every cell (`fold` first): `base_shift = 5` (size < 200) else 6; `H0 = fbm(fu+4096, fv+4096, s, base_shift) >> 8`; `F2 = fbm(fu+5095, fv+4873, s+11, 4) >> 8` (forest), `F3 = fbm(fu+4429, fv+4651, s+23, 4) >> 8` (rock/plateau), `F4 = vnoise(fu+4096, fv+4096, 3, s+37) >> 8` (ramps/sand), `F5 = vnoise(fu+4096, fv+4096, 4, s+51) >> 8` (moat meander), coast: `F6 = vnoise(fu+5596, fv+5796, 3, s+63) >> 8` (marsh), where `s = seed_a`. Coast: `d_norm = (max(|x2|,|y2|) or isqrt(x2²+y2²)) · 100 / w`; `edge = clamp(d_norm − 60, 0, 40)`; `H = clamp(H0 − 3·edge, 0, 255)`. Urban: `H = 110 + ((H0 − 128) >> 3)`. `moisture = F2` (view layer).
2. **Thresholds by percentile** (histogram of 256 bins, so coverage is exact and independent of the noise distribution): `t_forest = top 3·density ‰ of F2`; `t_rock = top density ‰ of F3`; `t_plateau = top (250 + 4·density) ‰ of F3`; `t_water` = smallest `k` with `cum(H ≤ k) ≥ water_pct·n/100`; sand: `t_sand = top sand_‰ of F4` (arid biome).
3. **Classification** (non-urban): `H ≤ t_water` → `DEEP` if `H ≤ t_water − 10` else `SHALLOW`; else `FOREST` if `F2 > t_forest`; else `ROCK` if `t_rock < F3 ≤ t_rock + 40`; else `DIRT` if `F2 > t_forest − 30 and hash2(fu,fv,s+5)&7 == 0`; else base (`GRASS`, arid `DIRT`; `SAND` where `F4 > t_sand`). **Urban**: lattice on `lu = fu + 4096, lv = fv + 4096` (offsets keep the operands non-negative — GDScript `%` keeps the dividend's sign; measured bug otherwise): `pitch = 16 + w/96`; street if `lu % pitch < 4 or lv % pitch < 4 or lu % (3·pitch) < 6 or lv % (3·pitch) < 6` → `ROAD` (1/64 → `RUBBLE` by `hash2(lu,lv,s+13)&63 == 0`); else block `(lu/pitch, lv/pitch)`, `hb = hash2(bx,by,s+17)`: `hb&7 == 0` → `PAVEMENT` plaza, `hb&7 == 1` → `GRASS` park, else `URBAN_BLOCK`, with a 1-cell `PAVEMENT` alley through the block's middle row/column when `(hb>>3)&3 == 0`.
4. **Terraces, cliffs, ramps** (non-urban), on a copy: for interior non-water cells with `F3 ≥ t_plateau` (recorded in the `plateau` mask): `terr = H >> 5`; the cell is a **cliff-foot** if any 4-neighbour has a strictly higher `terr` (one-sided and 4-neighbourhood-symmetric ⇒ mirror/rot-90 exact); it becomes `ROCK` + `SF_RAMP` if `F4 > 168` (≈ 34 % ramps ⇒ cliff bands have gaps) else `CLIFF`.
5. **Moat and marsh (coast)**: `rc = R·26/100`; per cell `d2 = isqrt(x2²+y2²)` (doubled), `off = ((F5 − 128)·6) >> 7`, `dd = |d2 − 2·(rc + off)|`; `dd ≤ 6` → `DEEP` (6 cells wide), `dd ≤ 10` → `SHALLOW` (2-cell banks). Symmetric by construction (pure function of folded values). **Marsh**: land (`GRASS`/`DIRT`) within Chebyshev distance 3 of any water cell (three 8-neighbour dilations of the water mask — a symmetric operation, unlike a two-pass distance transform) whose `F6 > 120` becomes `MARSH`.
6. **Rim**: every cell with Chebyshev distance `< RIM_W = 6` from the edge: coast → `DEEP`; otherwise distance `< 2` → `MOUNTAIN`, else `CLIFF`. The result is saved as `terrain_base` (retries of phase B copy it).

Prototype cost (v4, unloaded, M5 Max; other agents were running, so ±20 %): noise+fold 342–374 ms at 192² (626 ms at 256², 86 ms at 96²), classify 13–19 ms, cliffs/moat/marsh 0–29 ms ⇒ **Phase A ≈ 0.37–0.42 s at 192²**.

#### 5.12.5 Phase B — layout (cheap, retried at `level = 0,1,2`)

`gate_w = 5 + 2·level`, `start_r = 13 + 2·level`. Steps (each painted in all images):
1. **Starts.** Canonical `p0` (doubled, relative to centre): D1X `(−(R·62/100)·2−1, (h·6/100)·2+1)`; D2 `(−(R·55/100)·2−1, −(R·55/100)·2−1)`; D4 `((R·68/100)·2+1, (R·24/100)·2+1)`; DN `a = 2048/N`, radius `R·64/100`: `p0 = (2·rad·cos a >> 16, 2·rad·sin a >> 16)`. `spawns` = cell of `img_pt(k, p0)` (published in angle order), facing toward the centre. Paint disc `start_r` with `FORCE GRASS` and set `SF_START` in radius `start_r+1`. The starting Headquarters (**3×3**, global.json) is centred on the start cell (top-left `(cx−1, cy−1)`); the disc guarantees `MapBuildRules.check_land` returns `PR_OK` for it (asserted in V9).
2. **Bay (coast with `start_near_water`).** Nearest axis direction of the outward vector (`d4 = ((atan2(p0) + 512) >> 10) & 3`, E/S/W/N). A **9×7-cell deep pocket** (axis-aligned; centre 10 cells from the start centre along the axis, i.e. its near edge 6 cells from the HQ) plus a straight 7-wide deep canal with 2-cell shallow banks running from the pocket's far edge to the rim/sea, painted `FORCE` before the gates so that gates convert crossed water to fords. Straight pocket walls are what makes a 3×3 Dock footprint plus its 3×2 berth fit: a disc-shaped pool of radius 4 failed V11 on 24/24 eight-slot maps (its flat sides are shorter than 3 cells), a rectangular pocket passes on every start. The pocket is registered as an exclusion disc against fields.
3. **Gates.** Routes from `p0` (all `CLEAR`, half-width `gate_w`): to the centre `(0,0)`; to each of the 2 nearest other starts via the midpoint scaled ×1.2 outward from the centre (so they bulge around the moat). Trunk `ROAD` (3 wide, `ROAD` mode) along start→centre and start→nearest neighbour. All routes use `amp2 = 24` meander.
4. **Fields** (table below; FRAMEWORK §5.8 layout). Order: CONTESTED (largest claim), START ×2, NATURAL, NATURAL_RICH, FURTHER ×2. For each: candidate search over angle offsets `[0, +300, −300, +600, −600, +900, −900]` (units of 4096/turn) × distance scales `[100, 85, 70, 120]` %; a site is valid iff, in *every* image, its centre is ≥ 14 cells from the map edge, not on water, and ≥ 10 cells (`3 + 3 + 4`) from every registered field centre and bay pocket of every image. Stamp: disc radius 7 `FORCE GRASS` (fields are cleared lots), then the `K` cells of the 7×7 window around the image centre with the smallest key `(dx²+dy²)·64 + (hash2(dx,dy,s+91) & 63)` (doubled offsets from that image's centre ⇒ identical cell count for all images; `PackedInt64Array.sort` with the cell index in the low bits) receive `per_cell` credits (K = 24 standard, 16 rich), so **totals are exactly equal across images** even under rotation; images whose centre lies within 2 cells of an earlier image's are skipped (self-symmetric anchors); then a corridor `CLEAR` of half-width `gate_w` + 3-wide `DIRT` path from `p0` to the field (not for START fields, which lie inside the start disc). Failure to place START or NATURAL ⇒ phase B fails for this level (next level / attempt); CONTESTED / NATURAL_RICH / FURTHER are optional (skipped symmetrically; V10 catches a credit deficit).
5. **Neutrals** (§5.12.8), **beaches** (land `GRASS/DIRT/MARSH` 4-adjacent to deep/shallow water and not in `keep` → `BEACH`), flags (`SF_SHORE`, `SF_NOBUILD` on deposit cells + ring, lots, rim), view layers (`MapGenView`: corner heights, shore distance, road polylines), `deco`.
6. `finalize()` → validate (§5.12.6).

**Field table** (`map_gen.json`; credits per cell at `resources = 50`, i.e. scale 100 %; numbers = `global.json → economy.deposit`):

| kind | `FK_*` | per slot | class | cells × credits | ≈total | anchor (canonical slot 0) |
|---|---|---|---|---|---|---|
| START | 0 | 2 | standard (`klass 0`) | 24 × 600 | 14 400 | 11 cells from the start, tangentially left and right of the outward direction (fallback: inward) — inside the 8–16-cell band |
| NATURAL | 1 | 1 | standard | 24 × 600 | 14 400 | `size·16/100` cells from the start, toward the centre rotated +450 units (39.6°) |
| NATURAL_RICH | 2 | 1 | rich (`klass 1`) | 16 × 1200 | 19 200 | same distance, rotated +100 units (8.8°) |
| FURTHER | 3 | 2 | standard | 24 × 600 | 14 400 | `size·22/100` toward the centre rotated −450; `size·20/100` toward the nearest neighbour start |
| CONTESTED | 4 | shared | rich | 16 × 1200 | 19 200 | midpoint(start, each of the 2 nearest starts) × 0.65 toward the centre; 2-slot maps: two fields on the mirror axis (x = 0) at `y = 0.65·y(p0) ± 0.35·R` (images dedupe ⇒ `slots` fields for slots ≥ 3, 2 for 2 slots) |

Reachable per slot (own fields + the contested fields between the two nearest starts): `2·14.4 + (14.4 + 19.2) + 2·14.4 + 2·19.2 = 129.6 k` credits — the balance framework's per-player budget (75 k minimum, 110 k target). At most 56 fields (8 slots) ⇒ `field_of` ids ≤ 64. `SF_NOBUILD` is set on every deposit cell and its Chebyshev-1 ring. `hint_cell` (AI refinery hint) = cell at distance 6 from the field centre toward the owning start. The economy class of a field: START → 0 (starter), NATURAL/FURTHER → 1 (expansion), NATURAL_RICH/CONTESTED → 2 (rich) (`deposit_fields()`).

#### 5.12.6 Validation (`MapGenValidate`), repair, attempts, template

After `finalize()` (which prepares the nav graphs, 10–13 ms per graph at 256²) and on the **guarantee set** (land + fords; deep and ordinary shallow water impassable) with 3×3 clearance ("vehicle c2" — every 8-neighbour also in the set; the size-2 vehicle rule):

| # | Check | Pass rule |
|---|---|---|
| V1 | All start cells in one component on foot (size 1) **and** vehicle c2 | equal component labels |
| V2 | ≥ 2 exits per start | ring at Chebyshev radius 20 around the start: contiguous arcs (≥ 3 cells) of cells in the main vehicle component; pass if `arcs ≥ 2` **or** covered ring cells ≥ 50 % (open terrain is one big arc — the first prototype metric wrongly failed it) |
| V3 | Fields reachable | every deposit cell and each field's centre in the start component on vehicle c2 |
| V4 | Buildable start area | ≥ 450 cells with `TF_BUILD` inside radius 14 of every start |
| V5 | Neutrals reachable | each lot touches the main component (a 5-wide corridor is carved from its anchor, so this is a safety net; a failing neutral fails the level) |
| V6 | Route fraction | main vehicle component ≥ `min_route_pct` of the **playable interior** (cells at distance ≥ `RIM_W` from the edge): **open 45 %, coast 35 %, urban 30 %** (measured minima over 672 maps: 59 / 48 / 41 %) |
| V7 | Fairness | for every field kind of the four owned kinds (START, NATURAL, NATURAL_RICH, FURTHER) and each slot: **detour ratio** `fine_cost(start_k, field_k) · 1000 / octile(start_k, field_k)` (fine A* with `force_mode = 1`, ≈ 6 searches per slot); spread `(max−min)/min ≤ 15 %` per field. *Do not* compare raw octile path cost across rotations — the cost metric is anisotropic (measured spread 8.0 % for 3 and 12.7 % for 6 slots on maps that are identical up to rounding); the detour ratio measured **0 ‰** for every 2/4/8-slot map and ≤ 17 ‰ for the 3-/6-slot maps. Exact groups additionally assert equal totals. |
| V8 | Water never required | V1/V3/V5 are evaluated on the guarantee set; additionally no start/field/neutral lot cell is `DEEP/SHALLOW` (fords are allowed on routes, not on lots) |
| V9 | Structural | rim intact (`RIM_W` band impassable); field ids ≤ 64; `Σ deposit_max` = `Σ fields.total`; spawn count = `slots`; the starting HQ (3×3, centred on each start cell) passes `MapBuildRules.check_land` |
| V10 | Economy budget | reachable credits per slot ≥ `75 000 · (50 + resources)/100` (own fields + the contested fields between the slot and its two nearest starts); measured 129 600 on every map except one 8-slot coast batch (115 200) |
| V11 | Shore start (only `start_near_water`) | every start has a Dock site: a 3×3 buildable footprint whose nearest edge is ≤ 8 cells from the HQ centre with a 3×2 berth of `DEEP` cells (any of the four rotations) in a water body of ≥ 30 cells (`check_berth`); measured on every start of 180 coast maps |
| V12 | Neutral separation | every neutral lot ≥ 18 cells from every start centre, ≥ 6 from field centres (by construction; checked) |

**Repair/regenerate loop (deterministic):**
```
for attempt in 0 .. MAX_ATTEMPTS-1:                            # MAX_ATTEMPTS = 2
    seed_a = seed if attempt == 0 else mix32(seed, attempt, 0x51ED)
    phase A(seed_a)                                            # expensive
    for level in 0 .. 2:                                       # corridors 5 -> 7 -> 9 wide, start discs 13 -> 15 -> 17
        phase B(level); finalize; validate                     # ~60-90 ms each at 192^2
        if pass: return map (report.attempts = attempt+1, layout_level = level)
return MapGenTemplate.make(params)                            # safe template, validates by construction
```
Measured (prototype v4, this session, after the alignment changes): **first-attempt, level-0 success 672/672 distinct maps** — open ×2/3/4/6/8 slots (96–256), urban ×2/3/4/6/8 (128–192), coast ×2/3/4/6/8 (96–256), coast with `start_near_water` ×2/3/4/6/8 (96–256), seeds `1000 + 7919·k`, 12–24 seeds per cell of the matrix. Failure history that fixed the rules: cleared radius `r+2` left blob-edge cells with clearance 1 (most maps failed V3) ⇒ larger cleared discs; 3-wide field routes still isolated a field in 2/24 four-slot maps ⇒ 5-wide corridors; a 3-wide urban street network gave a 15 % vehicle-route share and failed V6 ⇒ 4-wide streets, 6-wide avenues; neutral lots without a carved corridor were unreachable on 2 of 8 large maps ⇒ constructive corridors; a disc-shaped bay never had a straight 3-cell wall for a Dock ⇒ rectangular pocket. Expected cost = A + B + V; worst case bound = `MAX_ATTEMPTS · (A + 3·(B+V)) + T_template`.

`MapGenTemplate.make`: dry `GRASS/DIRT` map (folded hash scatter), rim, the same starts/gates/fields code at level 2, one small `ROCK` cluster per image at 0.35 R, no neutrals, no bays; asserted to pass V1–V10 for every slot count and size in tests.

#### 5.12.7 Time budget, progress and the loading job

Measured on the prototype (unloaded, M5 Max, generation only, no nav): **96² 0.10 s · 128² 0.20 s · 192² 0.42–0.48 s · 256² 0.66–0.76 s** (noise+fold is ≈ 80 % of it; `finalize` adds the nav layers/graphs: ≈ 0.3 s at 256², see §9.5).

| Stage (progress id) | ≈ share of the 256² total incl. nav (1.0 s) | pct range reported |
|---|---|---|
| `ST_HEIGHT` fold + noise | 63 % (626 ms) | 0–60 (updated every 8 rows) |
| `ST_CLASSIFY`, `ST_WATER`, `ST_CLIFFS` | 4 % | 60–64 |
| `ST_LAYOUT`, `ST_FIELDS`, `ST_NEUTRALS` | 3 % | 64–70 |
| `ST_FINALIZE` (view layers, kinds, water components, nav weights, clearance, graphs) | ≈ 28 % (≈ 0.3 s) | 70–92 |
| `ST_VALIDATE` | 5 % (two flood fills ≈ 52 ms, fairness searches) | 92–100 |

Targets: **< 1.5 s at 192² including nav on an M-class CPU**, **< 4 s on a weak laptop** (≈ 3× slower ⇒ 256²: 3 s; the 2× noise optimisation of §5.12.2 is *required* for 256² and recommended everywhere; for D1X/D2/D4 the noise may additionally be evaluated on the fundamental domain only and mirrored: 2×/4×/8× fewer evaluations).

**`MapGenJob`** (net.md `NetWorldJob`, XR-12): `begin(map_cfg, tables, use_thread = true)` starts one worker `Thread` that runs `MapGenerator.generate` and `nav.prepare_all()` on a private `MapData`; `step(budget_us)` only polls `thread.is_alive()` (< 50 µs) and returns true after `wait_to_finish()`; progress is an int written by the worker under a `Mutex`; `cancel()` sets a flag checked between stages. Without threads (headless tests, exports that disable them) `step` runs whole stages until the budget is spent — a stage is ≤ ~0.5 s at 256², so it may overshoot the 4 ms `launch.step` budget by one stage, which net's `TIMEOUTS_LOADING` (20–60 s) absorbs. The result of both modes is byte-identical (tested; the v4 prototype generated a 160² coast/4-slot bay map on a `Thread` while the main thread polled `is_alive()` every 2 ms and produced exactly the same terrain and deposit layers as the synchronous run).

#### 5.12.8 Neutral objects

`map_gen.json` lists, per neutral id, the count per slot by family, the anchor and the ring; footprints come from the data (`DefNeutral.fp_w/fp_h`, economy's `neutral_structures.json`) through `MapGenTables` (passed into `generate`, hashed with the data), never from this domain. Per item `j`: anchor `A` (canonical, doubled coordinates) → candidate ring positions at `angle = base + j·700 + retry·341` (alternating sign), radius from `r0` to `r1` cells → the first candidate whose lot (`w+2` × `h+2` cells) is land (not water/cliff/urban block), ≥ 10 cells from the edge, ≥ 18 cells from every start centre, ≥ 6 from every field centre and other lot, and free of deposits **in every image** → lot cleared to `GRASS` (`PAVEMENT` in urban), `SF_NOBUILD` on lot + ring 1, a 5-wide `CLEAR` corridor from the anchor to the lot, recorded in `neutrals` (`kind, top-left cell, w, h, variant = hash&3, flags, orbit`) and in `objects`; images replicate (self-symmetric duplicates skipped). The harbor terminal additionally requires `DEEP` water within 5 cells of the lot and allows `SHALLOW` in its ring. Defaults (economy.md §5.13 guidance: per 2 players 1 substation, 1 field hospital, 1 observation tower, 0.5 depot; urban garrison blocks; coast harbor terminals):

| neutral id | footprint | open | urban | coast | anchor (canonical slot 0) |
|---|---|---|---|---|---|
| `neutral.civilian_garrison` | 3×3 | 2 / slot | `6 + size/64` / slot | 2 / slot | natural field, ring 6–14 |
| `neutral.substation` | 2×2 | 1 / slot | 1 / slot | 1 / slot | first contested field, ring 7–12 |
| `neutral.field_hospital` | 2×3 | 1 / slot | 1 / slot | 1 / slot | natural field, ring 7–14, toward the centre |
| `neutral.observation_tower` | 1×1 | 1 / slot | 1 / slot | 1 / slot | first further field, ring 5–10 |
| `neutral.salvage_depot` | 3×3 | 1 / map | 1 / map | 1 / map | map centre, ring 0–8 |
| `neutral.harbor_terminal` | 3×3 (shore) | – | – | 1 / slot | 0.3 · start, ring 0–16, shore lot |

Measured neutrals per map (v4): open 5 (96², 2 slots) … 40 (192², 8 slots); urban up to 47; coast up to 49 (256², 8 slots). Counts scale with `(neutrals + 25)/75`. Scenery boulders (`SF_BLOCK`, 1–3 cells, no entity) are placed on `keep == 0` grass/dirt at 3 per orbit (open) and 2 (coast).

#### 5.12.9 Determinism and threading of the generator

No RNG object, no `randi/randf`, no `Dictionary` iteration in decisions, no float, no `Time` in decisions; all loops in fixed order; percentiles by histogram; sorts (`nearest starts`, field cells) use total-order keys with an index tie-break. Generation is a pure function `(MapTerrain tables, MapGenTables, MapGenParams, GEN_VERSION) → MapData`, reentrant (no static mutable state), safe on a worker `Thread`. Cross-platform identity is a tested requirement (§10: golden `map_hash` per (family, slots, size, seed) recorded on macOS and reproduced in the Debian container).

### 5.13 AI-facing analysis (`MapRegions`, **optional**)

`ai.md` builds its own `AiRouteGraph` (8×8 coarse graph per move class, threat-aware A*, choke and disjoint-route detection) and `AiResourceSites`. What the AI needs from the map is the predicate API (`passable`, `region`, `is_water`, `get_family`, `start_cells` in circular order, `deposit_fields`, `objects`) and cost estimates (`MapNav.estimate_cost`, `same_region`), all in §3.3/§3.4. `MapRegions` is therefore **P3 / not scheduled**; it stays specified (below) so that a later AI revision or the QA harness can request it without redesign.

Static, deterministic, built lazily (not part of the sim checksum): (1) vehicle c2 passable cells; (2) chamfer 3-4 distance transform `dt` (two passes, ≈ 25 ms at 256²); (3) region seeds: cells with `dt ≥ 4` sorted by key `(−dt, cell index)` (`PackedInt64Array.sort`), each accepted iff no already accepted seed lies within Chebyshev distance `max(6, dt)` (lookup in a 16-cell bucket grid); (4) multi-source BFS (Voronoi) in seed order ⇒ `region_of`; (5) region adjacency and chokes from 4-adjacent cell pairs with different regions: border length = `width_cells`, `center_cell` = median border cell, `min_clearance` = min `clr` on the border, `kind = 1` if `width ≤ 8`; `region_path` = Dijkstra on the region graph with cost `(choke ? 64 : 0) + 4096/width`. Estimated ≈ 100–150 ms at 256² (not measured; the task's acceptance measures it).

### 5.14 What the other consumers get

* **Render (`ViewTerrainSource.from_map`, render.md §13-9)** — the complete contract, all read-only:

| render field | `MapData` source | format |
|---|---|---|
| `width, height` | `w, h` | cells (multiple of 8) |
| `seed_value` | `seed_value` | int |
| `biome` | `biome` | 0 temperate, 1 arid, 2 arctic, 3 urban |
| `heights` | `heights` | `(w+1)(h+1)` lattice-corner heights, 1/32 m: `2 ×` the mean of the ≤ 4 adjacent cell heights, where plateau-zone cells (F3 ≥ t_plateau, non-water) use the terrace height `((H>>5)<<5) + ((H&31)>>2)` so cliffs stand between flat terraces; corner heights within `RIM_W` of the edge ramp linearly to −64 (−2 m) at the edge, below every sea plane |
| `types` | `terrain` | terrain type 0..15 (§4.2) |
| `flags` | `flags` | `SF_*` bits (shore, ramp, no-build, start) |
| `moisture` | `moisture` | 0..255 (noise F2) |
| `terrain_kind` | `kind` | `TerrainKind` 0..7 — decor is drawn only on `forest`, `rough`, `cliff`, `marsh` cells so it never contradicts pathing |
| `shore_dist` | `shore_dist` | chamfer 3-4 distance from land over water cells, 1/3 cell, 0 on land, saturating 255 |
| `roads` | `roads` | polylines `[x0,y0,x1,y1,…]` in 1/16 cell (trunk roads of open/coast maps; urban streets are terrain) |
| `water_level_u` | `water_level_u` | 1/32 m; coast `2·t_water + 1`, dry maps 0 |
| `start_cells` | `start_cells` | pairs in circular start order |
| `deposits` | `fields` (stride 10) | `(cx, cy, radius = 3, klass)`; per-cell stock changes are pushed through `drain_deposit_dirty` |

  Border: the outer 6 cells are `DEEP` (coast) or `MOUNTAIN/CLIFF` (others) and their corner heights ramp below the sea plane, so the sea plane hides the boundary. World position = `cell · 3.0 m`; the height scale is the 1/32 m of the table.
* **Minimap**: render bakes it from the same arrays (`ViewMinimapSource`); `MapTerrain.minimap_rgba` provides the palette.
* **Economy / production**: `deposit_fields()`, `neutral_spawns()`, `is_buildable`, `is_passable_ground`, `is_water`, `water_body_size`, `MapBuildRules`, `occupy/vacate`, `harvest_field`, `find_free_cell_near`, `eject_units_from_rect` (§3.3, §3.10.2).
* **Abilities / zones**: `passable`, `is_clear`, `is_water`, `is_land` for exit-cell search and reveal shapes; no LOS.
* **AI**: §5.13. **Net / QA**: `MapGenerator.validate_params/generate`, `MapGenJob`, `content_hash`, `MapGenValidate.validate/metrics` (DA-29: exits per start, reachable credits ≥ 60 000 (QA) / 75 000 (balance), no mandatory water).

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

This domain adds **no opcodes, no order types and no event codes of its own**: everything below is the sim_core MASTER catalog (sim_core §6.1, §6.2, §4.7), plus four `STATE` codes requested in §13. This domain has **no RNG draw sites** (every "random" value is a hash of canonical inputs; `SCATTER`'s two draws per actor belong to sim_core).

### 6.1 Commands consumed (through sim_core's built-in order executor; no domain executor is registered)

| Code | Name | Actor → order | Handler | Field use |
|---|---|---|---|---|
| 0x10 | `MOVE` (IDS, X, Y, MODE(Q), FLAGS) | each unit → `T_MOVE` | `SimOrderMove` | `FLAGS` bit0 → `OF_NO_FORMATION`; `MODE` = queue mode (`QM_APPEND` = Shift-click waypoints) |
| 0x14 | `STOP` (IDS) | `orders.clear` → `cancel` on begun orders | `SimOrderMove.cancel` → `SimMovement.stop(soft)` | – |
| 0x16 | `SCATTER` (IDS) | `T_MOVE`, `QM_REPLACE`, random target within 3 cells (sim_core draws) | `SimOrderMove` | no formation (targets differ) |
| 0x17 | `PATROL` (IDS, X, Y, MODE(Q)) | `T_PATROL`, `OF_CYCLIC` | `SimOrderMove` | Shift chains waypoints |
| 0x1A | `LOAD` (IDS passengers, TARGET transport) | `T_LOAD` | `SimOrderCargo` | eligibility by `SimTransport.can_board` |
| 0x1B | `UNLOAD` (IDS, X, Y, MODE(Q), FLAGS) | `T_UNLOAD` (`arg` = flags: bit0 in place, bit1 all) | `SimOrderCargo` | structures (`AK_ANY`) served by the cargo owner's executor |
| 0x1C | `GARRISON` (IDS, TARGET building) | `T_GARRISON` | `SimOrderCargo` | |
| 0x11 / 0x23 / 0x15 | `ATTACK_MOVE` / `RETURN_TO_BASE` / `GUARD` | `T_ATTACK_MOVE` / `T_RETURN_BASE` / `T_GUARD` | **combat** | combat calls `SimMovement.move_to(..., OPT_ATTACK_MOVE)`, `pause`, `resume`, `stop`, `air_*` |

Group semantics: sim_core creates one `T_MOVE` per actor in ascending id in one executor call; the formation slots are computed inside the first `begin()` of that tick (§5.5) as a pure function of the current positions, so all clients agree.

### 6.2 Orders handled (`SimOrder.T_*` values of sim_core §4.7)

| Order | Code | `x, y` | `target` | `arg` / `arg2` | Completion | Failure (order dropped, rest of the queue continues) |
|---|---|---|---|---|---|---|
| `T_MOVE` | 16 | goal (slot for group moves) | – | – | `MS_ARRIVED` (also after a partial path was walked to its end) | `RS_NO_PATH`, `RS_STUCK`, `RS_IMMOBILE`, `RS_NO_MOVE` → `ORDER_FAILED` (dispatcher) |
| `T_PATROL` | 17 | far end of the leg | – | `arg, arg2` = origin recorded at the first `begin` (bounce point) | each leg `DONE`; dispatcher re-appends (`OF_CYCLIC`); a lone patrol order swaps `(x,y)` with the origin on every arrival | leg unreachable |
| `T_FOLLOW` | 18 | – | unit to follow | `arg` = max distance (default 3072), `arg2` = min distance (default 1024) | never (runs while the target lives) | `target_lost` |
| `T_FACE` | 19 | – | – | `arg` = angle 0..4095 | `\|err\| < 64` | – |
| `T_LAND` | 20 | touchdown point | – | `arg` = heading (−1 straight-in) | `air_at_goal` | aircraft grounded |
| `T_LOAD` | 64 | – | transport | – | `SimTransport.board` returned true | `can_board` false, unreachable, timeout 600 ticks |
| `T_UNLOAD` | 65 | drop point (carrier position = in place) | – | flags bit0 in place, bit1 all | cargo emptied (all) / one left (one) | timeout `pax·unload_t + 100` |
| `T_GARRISON` | 66 | – | building | – | `SimTransport.garrison_enter` returned true | not allowed, unreachable, timeout 600 ticks |

Patrol legs: `begin` issues the leg as a child `T_ATTACK_MOVE(x, y)` with `QM_FRONT` when combat has registered that handler (`world.orders.has_handler`), so patrolling units engage; otherwise as a plain `go_to`. The parent stays at queue index 1 and finishes when the child is gone (`p1 = 1` marks "child issued"). Field use of `phase/t0/p0/p1` is in §3.10.3.

```gdscript
# SimOrderMove (T_MOVE) -- the whole handler, condensed
func begin(world, e, o) -> int:
    var mv := e.move
    o.t0 = world.tick;  o.p1 = 0
    if _immob != null and _immob.is_immobile(e) and not _immob.request_pack(e):   # deployed unit: packing started, wait
        o.p1 = 1;  return RUNNING
    return _start_leg(world, e, o)
func _start_leg(world, e, o) -> int:
    var gx := o.x;  var gy := o.y
    if (o.flags & OF_NO_FORMATION) == 0 and _ground(e.move):
        if e.move.fslot_tick != world.tick:                     # not yet assigned by an earlier member of this tick's group
            var ids := PackedInt32Array()
            if SimFormation.group_of(world, e, o, ids) > 1:
                var sx := PackedInt32Array();  var sy := PackedInt32Array()
                SimFormation.assign(world, ids, o.x, o.y, 0, sx, sy)      # writes fslot_* of every member incl. e
        if e.move.fslot_tick == world.tick:  gx = e.move.fslot_x;  gy = e.move.fslot_y
    if not SimMovement.go_to(world, e, gx, gy, _opts(o)):  return FAILED     # RS_IMMOBILE / RS_NO_MOVE in mv.result
    o.p0 = e.move.goal_cell;  return RUNNING
func tick(world, e, o) -> int:
    if o.p1 == 1:                                                 # waiting for the pack animation
        if _immob.is_immobile(e):  return RUNNING
        o.p1 = 0;  return _start_leg(world, e, o)
    match e.move.state:
        MS_ARRIVED:  SimMovement.ack(world, e);  return DONE
        MS_NO_PATH:  SimMovement.ack(world, e);  return FAILED
        MS_IDLE:     return DONE                                    # goal cleared by someone else (stop): nothing left to do
    return RUNNING
func cancel(world, e, o) -> void:
    if e.move != null and e.move.goal_tick >= o.t0:  SimMovement.stop(world, e)   # only if the current goal was set by this order
```

### 6.3 Events emitted (output-only; DR-12)

| Code | Name | Fields (`a·b·c·d·e·f`) | Emitted when | Consumers |
|---|---|---|---|---|
| 0x05 | `STATE` | `id · ST_landed (10) · 0 · 0 · x · y` | touchdown of `air_land_at` (existing code) | view (landing animation), audio, combat (starts rearm) |
| 0x05 | `STATE` | `id · ST_takeoff (11) · 0 · 0 · x · y` | layer flips to `AIR` in `air_takeoff` (existing code) | view, audio |
| 0x05 | `STATE` | `id · ST_entered_water (16) · 0 · 0 · x · y`, `id · ST_left_water (17) · …` | `F_ON_WATER` toggles for an amphibious unit (≥ 6 ticks apart per unit) — **requested code** | view (splash / wake), audio, abilities (`ON_WATER` is folded statically; informational) |
| 0x05 | `STATE` | `id · ST_surfaced (18) / ST_submerged (19) · new layer · 0 · x · y` | `request_layer` completed — **requested code** | view (submarine surfacing), audio |
| 0x60 | `ORDER_FAILED` | `unit · order_type · 0 · x · y` | emitted by the dispatcher when one of my handlers returns FAILED; the reason is `SimMovement.result(e)` (`RS_*`) | audio ("cannot reach"), AI |

`LOADED/UNLOADED` (0x06/0x07) belong to `SimTransport`. The former ideas `EV_STUCK`, `EV_NAV_CHANGED`, `EV_DOCKED` are not needed: stuck ends in `ORDER_FAILED` + `RS_STUCK`; the packed bbox returned by `occupy/vacate` can be attached by the caller to whatever event economy defines; docking events are economy's.

### 6.4 What other domains must add (summary; exact requests in §13)

sim_core: named system accessors (`world.movement`), `STATE` codes 16–19, confirm that `set_layer` for aircraft/submarines is written by movement, call `MapData.occupy` for neutral structures, `MapData.make_flat` in the test kit. combat: use the primitives and `F_MOVING`, drop `ext_moving`/`vx,vy` from its entity contract, leave aircraft layer flips to movement. abilities: keep `speed_units/is_immobile/is_turn_locked/request_pack`, `SimTransport`, and call `SimMovement.request_layer` for surfacing. economy/production: deposits and placement through `MapData`/`MapBuildRules`, exits through `find_free_cell_near`, docks through `glide`, a default rally. data: `DefUnit`/`DefMoveTable`/`DefBodyTable`/`movement_defaults`, `terrain.json`/`movement.json`/`map_gen.json` loaders and hashes. net: `MapGenJob`, `validate_params`, `content_hash`, `to_bytes`. render: the field contract of §5.14.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

Three files live in `game/data/balance/`, are read once by `GameData`, converted to ints (DR-10) and hashed into the data version. Times/speeds are authored in human units and converted by the loader with `Fp.milli`/`cells_to_units`/`seconds_to_ticks`; **the converted ints are what the sim sees**. Everything else this domain needs is *consumed* from the balance layer (§7.3) — there is deliberately no movement-profile or footprint file.

### 7.1 `terrain.json`

```json
{
  "schema": 1,
  "weight": {"scale": 1600, "min": 10, "max": 40},
  "types": [
    {"id": 0,  "key": "deep_water",  "kind": "deep",    "flags": ["water"],                    "buildable": "none",  "minimap": "0d2f6b"},
    {"id": 2,  "key": "ford",        "kind": "shallow", "flags": ["water", "crossing"],        "buildable": "none",  "minimap": "8fa8cc"},
    {"id": 3,  "key": "beach",       "kind": "open",    "flags": ["land", "build_shore"],      "buildable": "shore", "minimap": "d9cc8c"},
    {"id": 8,  "key": "forest",      "kind": "forest",  "flags": ["land"],                     "buildable": "none",  "minimap": "145219"},
    {"id": 15, "key": "marsh",       "kind": "marsh",   "flags": ["land"],                     "buildable": "none",  "minimap": "3f6650"}
  ]
}
```
Loader rules: exactly 16 entries with ids 0–15 in order; `kind` ∈ the eight `TerrainKind` names (checked against `DefEnums.TerrainKind`); `flags ⊂ {water, land, build, build_shore, crossing}` map to `TF_*`; `buildable ∈ {none, std, shore}` maps to `TF_BUILD` / `TF_BUILD_SHORE`; **speeds are never authored here** — the loader takes `speed_bp` from `DefMoveTable` and derives weights (§5.1). A type whose `kind` is water must carry the `water` flag and vice versa (validated). The table of §4.2 is the complete default file; default `minimap` colours: deep 0d2f6b, shallow 2f6fb0, ford 8fa8cc, beach d9cc8c, grass 5a9e47, dirt 8c7350, sand cbb273, rock 8c8c8c, forest 145219, road 595961, pavement 9a9aa0, rubble 806666, urban 803f33, cliff 33261a, mountain 0d0d0d, marsh 3f6650. `DEEP_ONLY_RADIUS = 922` (= `cells_to_units(0.9)`, TAXONOMY §6) and `LARGE_HULL_RADIUS = 1100` are code constants of `MapTerrain`; a unit test asserts the first equals the converted TAXONOMY value.

### 7.2 `movement.json` (only what balance does not already own)

```json
{
  "schema": 1,
  "turn_mode": {"foot": "instant", "wheeled": "arc", "tracked": "pivot",
                "amphibious": {"light": "arc", "default": "pivot"},
                "naval": "arc", "submerged": "arc", "air_fixed": "bank", "air_hover": "instant"},
  "turn_mode_override": {"unit.ae.kiln_assault_crawler": "pivot"},
  "air": {"fixed_min_speed_pct": 60, "orbit_r_cells": 4.0,
          "cruise_alt_cells": {"air_fixed": 6.0, "air_hover": 2.5},
          "climb_cells_s": {"air_fixed": 2.5, "air_hover": 1.9},
          "takeoff_roll_ticks": 12, "approach_cells": 5.0, "rotor_descend_cells_s": 1.25, "land_speed_pct": 35,
          "edge_avoid_cells": 2.0, "sep_radius_cells": 0.6, "sep_stride": 2},
  "formation": {"speed_match": 0}
}
```
Conversions (loader, `TPS = 20`): `orbit_r = cells_to_units(4.0) = 4096`; `cruise_alt = 6144 / 2560`; `climb = cps_to_units_per_tick(2.5 / 1.9) = 128 / 97`; `approach = 5120`; `rotor_descend = 64`; `edge_avoid = 2048`; `sep_radius = 614`. Everything else that affects results (path budgets, separation constants, stuck timings) is a compile-time constant of `SimMoveConfig`, versioned by `SIM_VERSION`. A `turn_mode_override` key is a unit id; unknown ids are a load error.

### 7.3 Consumed from the balance layer (no file of mine)

| Source | Keys / fields read | Used for |
|---|---|---|
| `global.json → movement_classes` (`DefMoveTable.speed_bp`, `layer`, `layer_mask`) | 9 classes × 8 kinds, TAXONOMY §8 | speeds, passability, weights, land-only guarantee |
| `global.json → size_classes` (`DefBodyTable`) | `radius_cells`, `turn_deg_s`, `mass` per class | radius, turn rate, mass (units) |
| `global.json → movement_defaults` | `accel_ticks{size}`, `decel_ticks_pct_of_accel` (70), `reverse_speed_pct` (50), `formation_spacing_cells_extra` (0.45), `stuck_repath_ticks` (40) | §4.6, §5.5, §5.4.6 |
| `DefUnit` | `move_class, size_class, speed, deep_speed_bp, water_mult_bp, accel_t, turn_rate, radius, home_layer, speed_water` | `SimMoveProfiles` (§4.6), speed formula (§5.1) |
| `global.json → naval.channel_width_cells_min` (3/4/6), `aircraft.fixed_wing_units` / `hover_units` | generator channel widths; which unit archetypes are fixed-wing | §5.12, §5.6 |
| `global.json → economy.deposit` (`credits_per_cell` 600, `rich_credits_per_cell` 1200, `standard_field_cells` 24, `rich_field_cells` 16, `map_budget.credits_per_player_reachable_min` 75 000) | field classes and V10 | §5.12.5 (override the defaults of `map_gen.json` when `GameData` is present) |
| `DefStructure` (`fp_w, fp_h, fp_mask, exit_dx, exit_dy, place_mask`) and economy's `structure_rules.json` (`apron`, `dock`, `berth`, `pads`) | footprints, berth rectangle, pad cells | `MapFootprint.cells`, dock rule (economy composes) |
| economy's `neutral_structures.json` / `DefNeutral` | `fp_w, fp_h`, ids | generator lots (`MapGenTables`) |

Worked example (Guardian, data_balance §7.6): `move_class 2 (TRACKED)`, `size_class 2 (medium)`, `speed 102`, `radius 563`, `turn_rate 85`, `accel_t 6` ⇒ profile `np = NP_TRACKED`, `nav_size = 2`, `mass = 3`, `accel_q4 = 272`, `decel_q4 = 408`, `TM_PIVOT`, `reverse_pct = 50` (§4.6).

### 7.4 `map_gen.json`

```json
{
  "schema": 1,
  "gen_version": 2,
  "layout": {"rim_w": 6, "start_r": 13, "start_r_step": 2, "gate_w": 5, "gate_w_step": 2, "route_amp2": 24,
             "moat_r_pct": 26, "moat_deep_half2": 6, "moat_bank_half2": 10, "marsh_reach": 3, "marsh_f6_min": 120,
             "exit_ring_r": 20, "min_buildable_start": 450, "start_buildable_r": 14, "max_attempts": 2,
             "field_clear_r": 7, "field_edge_margin": 14, "field_spacing": 10, "neutral_edge_margin": 10,
             "neutral_start_dist": 18, "neutral_field_dist": 6},
  "bay": {"pocket_cells": [9, 7], "near_edge_cells": 6, "canal_deep": 7, "canal_bank": 2},
  "families": {
    "open":  {"water_pct": 0,  "density": 50, "terraces": true,  "min_route_pct": 45},
    "urban": {"water_pct": 0,  "density": 50, "terraces": false, "min_route_pct": 30, "street_w": 4, "avenue_w": 6, "pitch_base": 16},
    "coast": {"water_pct": 22, "density": 40, "terraces": true,  "min_route_pct": 35, "moat": true, "marsh": true}
  },
  "deposit": {"standard": {"cells": 24, "per_cell": 600, "klass": 0}, "rich": {"cells": 16, "per_cell": 1200, "klass": 1}, "budget_min": 75000},
  "fields": [
    {"kind": "start",        "class": "standard", "per_slot": 2, "dist_cells": 11, "dir": "tangent_both"},
    {"kind": "natural",      "class": "standard", "per_slot": 1, "dist_pct_size": 16, "dir": "toward_plus_450"},
    {"kind": "natural_rich", "class": "rich",     "per_slot": 1, "dist_pct_size": 16, "dir": "toward_plus_100"},
    {"kind": "further",      "class": "standard", "per_slot": 2, "dist_pct_size": [22, 20], "dir": ["toward_minus_450", "nearest_start"]},
    {"kind": "contested",    "class": "rich",     "shared": true, "anchor": "pair_midpoint_65"}
  ],
  "neutrals": [
    {"id": "neutral.civilian_garrison", "count": {"open": "2", "urban": "6+size/64", "coast": "2"}, "anchor": "natural", "ring": [6, 14]},
    {"id": "neutral.substation",        "count": {"open": "1", "urban": "1", "coast": "1"}, "anchor": "contested", "ring": [7, 12]},
    {"id": "neutral.field_hospital",    "count": {"open": "1", "urban": "1", "coast": "1"}, "anchor": "natural", "ring": [7, 14]},
    {"id": "neutral.observation_tower", "count": {"open": "1", "urban": "1", "coast": "1"}, "anchor": "further", "ring": [5, 10]},
    {"id": "neutral.salvage_depot",     "count": {"open": "map1", "urban": "map1", "coast": "map1"}, "anchor": "center", "ring": [0, 8]},
    {"id": "neutral.harbor_terminal",   "count": {"open": "0", "urban": "0", "coast": "1"}, "anchor": "start_30", "ring": [0, 16], "shore": true}
  ],
  "biomes": [
    {"key": "temperate", "base": "grass", "sand_permille": 0},
    {"key": "arid",      "base": "dirt",  "sand_permille": 180},
    {"key": "arctic",    "base": "grass", "sand_permille": 0}
  ],
  "progress": {"height": [0, 60], "classify": [60, 64], "layout": [64, 70], "finalize": [70, 92], "validate": [92, 100]}
}
```
`count` strings are tiny integer expressions over `size` (`"6+size/64"`), `"map1"` = one per map. Any change to a value in this file changes generator output and therefore requires bumping `gen_version`, which must equal `MapGenParams.VERSION` (the loader rejects a mismatch). The `deposit` block is the default; when `GameData` provides `economy.deposit_*` its values win.

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

| Rule | Compliance in this domain |
|---|---|
| DR-1 ints only | Positions, speeds (Q4), angles, costs, weights, noise, hashes all `int`. `Vector2i` is not used. `bool` appears only in parameters/returns. The debug PNG helper (tests only) builds `Image`/`Color` but is never called from the sim or generator. |
| DR-2 no engine RNG | No `randi/randf/shuffle/pick_random`. Every "random" value is `mix32/hash2` of *(canonical inputs, seed)*: generator, coincident-unit separation direction, nudge direction (`id` parity). This domain owns **no draw site** of `world.rng`. |
| DR-3 no time | Sim code uses `world.tick` only. The generator's `ms` telemetry (`Time.get_ticks_usec`) is written to the report and never read by any decision; `MapGenJob.step(budget_us)` uses the clock only to decide *when to yield*, and slicing cannot change the result (stages are atomic). |
| DR-4 int math builtins | Only `Fp.sin/cos/atan2/isqrt/dist` (tables / exact integer sqrt). Separation uses alpha-max-beta-min (integer). Generator angle tables come from `Fp`. |
| DR-5 division/shift semantics | Divisions are on non-negative operands, or use `Fp.floor_div/floor_mod`; `>>` on negatives is an arithmetic (floor) shift on all three platforms and is used deliberately (`x >> shift` in the noise lattice); the one known trap — `%` on negative operands in the urban lattice — is removed by non-negative offsets (§5.12.4). Intermediates stay < 2⁶² (worst: `speed_upt·16·kind_bp < 1.7·10⁸`, `spd_q4·cos < 5·10⁸`, `x·374761393 ≈ 2⁴⁸`, `seed·1274126177 ≈ 2⁶¹`). |
| DR-6 iteration order | Entities in ascending id (`_movers` is appended in id order); grids rebuilt in ascending id each tick (no history dependence); path requests FIFO by `seq`; the path cache is a `Dictionary` with **int keys, looked up and evicted through a FIFO ring, never iterated**; `structs` is only keyed lookups (hash is an order-independent sum); neighbours in fixed E,W,S,N,SE,SW,NE,NW order; ring searches in fixed ring order. |
| DR-7 total-order sorts | Formation keys embed the entity id in the low bits (`PackedInt64Array.sort`); field-cell selection keys embed the cell index; nearest-start ordering uses the `PackedInt64Array` key `(dist² << 8) | index`. No `sort_custom` anywhere in this domain (the prototype's `sort_custom` on two-element neighbour lists is replaced by that key). |
| DR-8 no Node/threads/await | Sim classes are `RefCounted`. The generator is thread-*safe* (pure) and `MapGenJob` may run it on one worker thread; the sim itself never spawns threads. |
| DR-9 no hidden global state | Tables live in `MapTerrain`/`MapGenTables` instances held by `GameData` (or the cached `load_default()` singletons, immutable); `MapData` is cloned per world (`clone_for_world`); scratch buffers belong to `SimPathService`/`SimSeparation`; systems never store `SimWorld`. |
| DR-10 data conversion | `terrain.json`, `movement.json`, `map_gen.json` converted at load; converted ints hashed (`MapTerrain.table_hash`, movement/gen tables); the balance tables (`DefMoveTable`, `DefBodyTable`, `movement_defaults`) are hashed by data. |
| DR-11 bounded, deterministic pathing | Budget in *units of work* (§5.3.5), never elapsed time; caps by count on searches, neighbours, deliveries, dirty units, sidesteps, group size. |
| DR-12 events output-only | Events never read back; `deposit_dirty` is an output list. |
| DR-13 checksum coverage | Below. |
| DR-14 host-side AI | `MapRegions`/estimators are host-only conveniences; results enter the sim as ordinary commands. |
| DR-15 view floats | The view reads the integer layers and converts; nothing here produces floats. |

**What enters `SimWorld.checksum()` from this domain** (sim_core §8.2 folds these; sections in parentheses):
1. (entities) For every entity with an `e.move` slot, `SimMoveComp.hash_into(buf)` — all fields of §4.4 except `HASH_EXEMPT` (derived profile copies and per-cell caches), `path` element-wise with its size — appended by the kernel in the fixed slot order; plus `x, y, facing, layer, flags` (kernel).
2. (map) `map.hash_state(buf)` = `[w, h, deposit_hash, occ_hash, nav_version]`.
3. (movement) `SimMovementSystem.hash_state(world, buf)`: `SimPathService.state_ints`: `seq`, the three queue contents (slot indices in order), the request table (all live slots), the free list, `MapPathSearch.state_ints` (`serial`, `status`, `expanded`, `cur`, `remaining`, `ne`), the cache keys in ring order with `ver`, `born` and a fold of each cached path.
4. `SimSeparation`: nothing (rebuilt from entity state every tick). Pads, docks and cargo lists: not here (their owners hash them).

**Derived-state verification hooks (tests, also runnable in debug builds each 20 ticks):** `map.recompute_dynamic_hash() == map.checksum_dynamic()`; `map.nav.validate_against_terrain()`; graph relabel equals fresh rebuild; separation grids equal a fresh rebuild; `SimTestKit.check_hash_coverage(SimMoveComp.new(), SimMoveComp.HASH_EXEMPT)` reports nothing.

**Cross-platform integer hazards checked:** signed shifts, truncating division on negatives (only in symmetric push math where sign symmetry is intended), `int` is 64-bit on all export targets, no reliance on `Dictionary` ordering, no float→int conversions (`int(float)`) in sim code (the prototype used `int(sqrt(float(n)))` only as a *seed* for the exact integer square root; production uses `Fp.isqrt`).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

### 9.1 Measured primitives (this session; Godot 4.7.2 headless, typed GDScript, Apple M5 Max; "unloaded" best-of)

| Primitive | Result | Notes |
|---|---|---|
| Dial-bucket A\*, optimised loop (offset tables, no `match`) | **1.60–1.72 µs / visited cell** | agrees with the 1.7 µs reference; first-cut loop with `match` per neighbour: 2.9–3.4 µs |
| Same search with `h = 0` (Dijkstra / flow-field proxy), 256² | 60–64 k cells, **85–89 ms** | 1.36–1.40 µs/cell |
| Fine A\* open ground (12 % obstacles), cross-map 248 cells | 249 visited, **0.63 ms** | |
| Fine A\* 25 % / 35 % clutter, cross-map | 5 241 visited **8.8 ms** / 10 634 visited **17.5 ms** | |
| Fine A\* urban maze (street 3–4, pitch 16–20) | 8 703–8 978 visited, **14–15 ms** | |
| Abstract A\* (1 025–1 075 nodes) | 33–389 pops, **0.17–0.52 ms** | |
| Corridor A\* after abstract: 25 % / 35 % clutter / urban (single cross-map query) | 1 149 / 1 720 / 1 810–2 073 visited, **2.0 / 2.9 / 3.1–3.5 ms** | + abstract 0.2–0.5 ms |
| 300 random ≥ 60-cell pairs per map: plain fine vs corridor | fine mean 0.9–3.8 k / worst 9.5–22 k visited; corridor mean **0.5–0.9 k** / worst **2.0–2.3 k** | corridor cost ratio mean 1.017–1.059, max 1.118–1.223 |
| 8–24-cell pairs, fine A\* | mean 32–161, worst 348–1 128 (35 % clutter: 7/396 exceed 2 400) | |
| Block components + orthogonal/diagonal edges, 256² | labels **6.2–10.1 ms** + edges **3.1–3.7 ms** per graph | 1 025–1 075 nodes |
| Clearance transform (cap 3) | **8.7 ms** (192²), **15.6 ms** (256²) per profile | |
| Integer LOS | **0.19 µs / cell** | |
| 4-neighbour flood (validation) | 0.24 µs / cell (15.4 ms at 256²) | |
| Separation-grid rebuild | 28 µs for 300 entities (**0.09 µs/entity**) | |
| Movement skeleton (steer + separation + integrate) | spread over map **1.6 µs/entity**; six dense clumps of 50 (9.3 neighbour checks/entity) **3.2 µs/entity** | 600 spread entities: 0.97 ms |
| fBm noise 4 octaves, naive | **3.85 µs / cell** (142 ms at 192², 240 ms at 256²) | |
| Generator prototype v4 (all families; stage timings from dedicated runs, the 672-map sweep ran ≈ 1.3× slower under load) | **0.42–0.48 s / map at 192²** (noise+fold 342–374 ms); 256² 0.66–0.76 s; 96² 0.10 s; validation flood (two masks) 28 ms at 192² | |

### 9.2 Per-tick estimate — 256×256, 8 players, 1 200 unit entities of which **300 moving** (dense fights, worst realistic)

| Item | Derivation | M-class | Weak laptop (×2.5–3) |
|---|---|---|---|
| `flush_dirty` | ≤ 12 units × 60 µs, usually 0 | 0–0.7 ms | 0–2 ms |
| Separation-grid rebuild | 1 200 × 0.09 µs | 0.11 ms | 0.3 ms |
| Phases A+B+C, 300 movers | measured skeleton 3.2 µs × 300 = 0.95 ms × **2.5** for real logic (waypoints, states, medium, flag mirrors, speed inputs), + **1 µs/mover** for `world.set_pos`, the `speed_units` / `is_immobile` adapter calls and the flag write (estimate: two method calls ≈ 0.25 µs each, the spatial-hash `move` re-buckets every ≈ 4 cells of travel) | 2.7 ms | 7–8 ms |
| Idle units (900), separation every 3rd tick | 900/3 × ~1 µs | 0.3 ms | 0.8 ms |
| Strided maintenance (stuck /10, validity /8 after nav change, follow /5) | 300/10 × 1 µs + 300/8 × 6 µs burst | 0.1–0.3 ms (0.2 used) | 0.3–0.8 ms |
| Path service, average | ≈ 12 requests/s: 8 cache/LOS hits (1–3 units), 4 searches × ~1.3 ms mean (worst 3.9 ms) plus snapping/attach overhead → ≤ 0.5 ms/tick | 0.5 ms | 1.4 ms |
| **Average total** | 0.05 + 0.11 + 2.7 + 0.3 + 0.2 + 0.5 | **≈ 3.9 ms** | **≈ 10–12 ms** |
| Path service, cap | `1600 + 200·min(pending,8)` units × 1.7 µs | 2.7–5.4 ms | 7–15 ms |
| **Peak total (burst orders)** | avg without path (3.4 ms) + cap 5.4 | **≈ 8.8 ms** | **≈ 22–27 ms** |

The tick budget is 50 ms (20 TPS); movement averages ≈ 8 % and peaks at ≈ 18 % (M-class) / ≈ 50 % (weak laptop, only during order bursts). Because the constants are counts, a slow machine simply takes more wall time per tick — it never changes results (lockstep pace adapts through the net layer). Levers if profiling disagrees (all constants in `SimMoveConfig`): `PATH_BASE` 1600 → 1200, `SEP_MAX_NEIGHBOURS` 12 → 8, `IDLE_SEP_STRIDE` 3 → 4, adapter reads of `speed_units` every 2nd tick per unit (`(tick + id) & 1`, deterministic).

### 9.3 Worst cases and mitigations

| Case | Cost / behaviour | Mitigation |
|---|---|---|
| 10 group orders in one tick (8 AIs + human), 2–3 searches each ≈ 40 ms of work (corridor search mean 1–1.6 ms, worst ≈ 3.9 ms) | drained at 2.7–5.4 ms/tick ⇒ 8–15 ticks (0.4–0.75 s) for the last group; units start turning at once (`MS_WAIT_PATH`) | priorities (`PRIO_ORDER` first), shared paths, cache; direct-LOS and cache hits are zero-latency; scale budget with pending. |
| "Select all 200 → move" cross-map | ≈ 10 start nodes ⇒ 10 searches ≈ 15 ms ⇒ 3–6 ticks; the group scan in `begin` is one pass over ≤ 150 units per leader | same; formation ≤ 200 per group. |
| Unreachable goal | `cc` mismatch ⇒ ring scan ≤ 24 rings (≈ 2 400 cell tests ≈ 0.5 ms), **no flood** | nearest-reachable goal, `RS_PARTIAL`. |
| Path blocked mid-route by a building | validity stride (≤ 8 ticks) + one `PRIO_REPATH` search | staggered by id. |
| Superweapon destroys 30 structures | weights updated immediately (≈ 20 µs each); clearance/relabel deferred and drained at ≤ 12 units/tick (≈ 10 ticks); abstract-phase searches deferred meanwhile | count-bounded flush. |
| 1 000 units in a 20×20-cell blob | separation capped at 12 neighbours/unit ≈ 4 µs/unit | cap. |
| Follow-order swarm (50 followers on a fast target) | re-plan ≤ 1 per 20 ticks per follower ⇒ 2.5/tick × 0.6 ms | rate limit. |
| 100 aircraft | no terrain, no paths: ≈ 0.7 µs each, air separation stride 2 | – |
| 20 exit searches in one tick (mass production) | `find_free_cell_near` ≤ 81 candidate cells × 7 µs ≈ 0.6 ms each worst, typically 1–3 cells | economy spawns ≤ 1 unit per producer per tick. |

### 9.4 Memory (256², per world)

`MapData` layers ≈ 1.9 MB (byte layers 64 kB × 10 incl. `kind`, `buildable`, `shore_dist`, `moisture`, `height`; int32 layers 256 kB × 5 incl. `deposit`, `deposit_max`, `occ`, `water_comp`; `heights` 264 kB) + nav weights/clearance 7 × 2 × 64 kB = 0.9 MB + up to 8 graphs × 0.26 MB = 2.1 MB (four on a dry map ⇒ 1.0 MB) + search scratch ≈ 4.5 MB (`g, vis, closed, parent` 1 MB, entry pool 3 × 4n ints 3 MB, `col/row` 0.5 MB) + separation grids ≈ 0.1 MB + components ≈ 0.6 MB (1 200 movers × ~0.5 kB) ≈ **10 MB**. `to_bytes()` at 192²: ≈ 0.5 MB raw (incl. `heights`), ≈ 60–100 kB deflated (estimate; verify in TM-02).

### 9.5 Load and generation

`finalize()` at 256² (in the generator's worker thread): kinds/water components/shore distance ≈ 25 ms, nav weights 7 profiles ≈ 70 ms, clearance 7 profiles ≈ 109 ms, graphs ≤ 8 ≈ 60–80 ms ⇒ **≈ 0.3 s** (0.15 s at 192²). `clone_for_world()` copies weights, clearance and graphs (≈ 4 MB memcpy ≈ 2 ms) — the world constructor never recomputes them. Generation: §5.12.7 (measured 0.42–0.48 s at 192², 0.66–0.76 s at 256² before nav; target < 1.5 s at 192² including nav on M-class; < 4 s on a weak laptop *only with* the required noise optimisation).

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

All tests are `game/tests/test_*.gd` (`RefCounted`, `func run(t: TestCtx)`), run via `tools/gd test map_` / `tools/gd test move_`; scenario tests build a `SimWorld` (`SimTestKit.make_world`, or a real `GameData` where noted) on fixture maps from `MapGenTemplate` (`flat(w,h)`, `corridor(w, width)`, `forest_strip`, `river_with_ford`, `urban_maze(seed)`, `lake`) and stubs for the neighbouring systems (`StubAbilities` with `speed_units/is_immobile/is_turn_locked/request_pack`, `StubTransport`, `StubEconomy`). Expected values below are derived from the formulas in §5 or were measured with the prototypes; "±" gives the tolerated band.

### 10.1 Unit tests

| ID | Subject | Case → expected |
|---|---|---|
| U1 | integer noise KATs | `mix32(0,0,0)=3469031917`, `mix32(1,0,0)=2814734143`, `mix32(17,42,12345)=414332277`, `mix32(-5,7,99)=1917552722`, `mix32(4100,4200,2147483647)=3329929251`; `vnoise(100,200,5,777)=36241`, `vnoise(-37,91,4,5)=19981`; `fbm(4106,4116,1234,5)=25507`, `fbm(0,0,1,6)=20787` (identical in engine and independent Python emulation) |
| U2 | terrain tables (default `DefMoveTable`) | `kind_of`: deep→6, shallow/ford→5, beach/grass/dirt/sand→1, rock/rubble→2, forest→3, road/pavement→0, urban/cliff/mountain→7, marsh→4; weights: `weight(TRACKED, road)=15`, `weight(WHEELED, road)=12`, `weight(WHEELED, forest)=0`, `weight(TRACKED, forest)=29`, `weight(FOOT, forest)=23`, `weight(WHEELED, marsh)=40` (clamp), `weight(WHEELED, shallow)=32`, `weight(AMPH, deep)=23`, `weight(NAVAL, shallow)=20`, `weight(NAVAL_DEEP, shallow)=0`, `weight(SUB, deep)=16`; step tables `step_o(16)=10, step_d(16)=14, step_o(23)=14, step_o(12)=8, step_d(12)=11, step_o(40)=25, step_d(40)=35`; `nav_size(FOOT, 410)=1`, `(WHEELED, 461)=2`, `(TRACKED, 1024)=2`, `(NAVAL, 1434)=3`, `(NAVAL, 614)=2`; `profile_of(NAVAL, 614)=NP_NAVAL`, `(NAVAL, 1024)=NP_NAVAL_DEEP`, `(AIR_FIXED, 500)=NP_NONE`; `guarantee(ford)=true`, `guarantee(shallow)=false`, `guarantee(forest)=false` (wheeled blocked), and after editing the table so tracked forest = 0 nothing else changes; `DEEP_ONLY_RADIUS == cells_to_units(0.9)` |
| U3 | clearance | 12×12 fixture with corridors 1/2/3 cells wide: FOOT passable in all three; `passable(NP_WHEELED, SZ_2)` false in the 1- and 2-wide corridors, true on the centre line of the 3-wide one (`clr = 2`); 5×5 open room centre `clr = 3`; cells within `NAV_BORDER` are never passable, also on `make_flat` maps |
| U4 | LOS | diagonal wall gap (two blocked cells touching at a corner): `los` false (corner rule) for size 1; straight line through an open room true; `los_cost` on a straight 10-cell row of weight 16 = 100 |
| U5 | fine A\* | empty 16×16 interior, (2,2)→(13,9) with `force_mode = 1`: `path_cost = 138` (7 diagonal + 4 orthogonal), smoothed result `[goal]` (auto mode returns the same `[goal]` via the LOS shortcut); forest column x=8 (FOOT w=23), (2,7)→(13,7): `path_cost = 114` (10·10 + 14); symmetric maps give mirrored costs; same result whether searched with budget 50, 1600 or ∞ (resumability) |
| U6 | corridor search | on 30 `urban_maze` / 30 12–35 %-clutter fixtures, 200 pairs ≥ 60 cells each: result valid (every consecutive waypoint pair passes `los`), unsmoothed cost ≤ 1.25 × the unrestricted optimum for every pair and mean ≤ 1.06 × (`force_mode = 1` vs `2`; measured mean 1.017–1.059, max 1.118–1.223), `expanded` (corridor, incl. abstract pops ×2) ≤ 2 500 for every pair, unreachable pairs ⇒ `ST_NO_PATH` with `expanded == 0` |
| U7 | formation | worked example of §5.5 ⇒ slots `11→(20480,10122)`, `13→(20480,11382)`, `10→(19219,10122)`, `12→(19219,11382)`; 1 unit ⇒ target; 13 units ⇒ `cols = 4, rows = 4` (last row of 1 centred); ids permutation of the same positions ⇒ same slot set; `group_of` from the perspective of every member returns the same ids; a unit with `OF_NO_FORMATION` or a queued (non-`PH_NEW`) `T_MOVE` is excluded |
| U8 | speed law | Guardian (`speed_base 102`, `accel_t 6`): `spd_q4` after ticks 1..7 = 272, 544, 816, 1088, 1360, 1632, 1632; from full speed with target 0: 1224, 816, 408, 0 and 154 ± 20 units covered while braking; `vcur_q4` examples of §5.1: 2150 (road, `speed_units 128`), 1638 (rough), Beaver on deep water 2204, suppressed infantry in forest 731; infantry (`speed 87`, `accel_t 2`): `accel_q4 = 696`, `decel_q4 = 1392` (stops in one tick) |
| U9 | occupy/vacate | 4×4 footprint: 16 cells weight 0 on all 7 profiles, ring `clr = 1`, `vacate` restores byte-identical arrays and `recompute_dynamic_hash() == checksum_dynamic()`; occupy of two structures in either order ⇒ identical `checksum_dynamic()` and `hash_state` |
| U10 | build rules | `check_land`: rim cell ⇒ `PR_TERRAIN`; cell at index 0 with margin 1 ⇒ `PR_OUT_OF_BOUNDS`; deposit ring ⇒ `PR_NOBUILD`; occupied ⇒ `PR_OCCUPIED`; beach ⇒ `PR_TERRAIN`, with `shore_ok = true` ⇒ `PR_OK`; `check_berth`: berth on dry land ⇒ `PR_NEEDS_WATER`, 3×2 berth in a 60-cell pond ⇒ `PR_WATER_EXIT`, berth in `SHALLOW` ⇒ `PR_NEEDS_WATER`, berth in the sea ⇒ `PR_OK`; `scan` returns nearest ring first |
| U11 | footprints | `cells` of a 3×3 with `fp_mask` `..X/.XX/XXX` (row-major) at all four orientations; `rotate_offset(3,3,1,dx,dy)` = `(2−dy, dx)`, orient 2 = `(2−dx, 2−dy)`, orient 3 = `(dy, 2−dx)`; `oriented_size(4,3,1) = (3<<8)\|4`; a rotated footprint partly outside the map ⇒ −1 |
| U12 | deposits | `harvest_cell(i, 700)` on 600 ⇒ 600, then 0; `harvest_field(f, from, 600)` empties exactly the nearest non-empty cell of a 600-credit field (ties: lowest index) and 24 calls empty a standard field (14 400); `deposit_hash` incremental == recomputed; `field_remaining` decreases; `regrow_field` capped by `deposit_max`; `drain_deposit_dirty` lists changed cells once; `deposit_fields()` totals equal `Σ deposit_max` |
| U13 | serialisation | `from_bytes(to_bytes(m)).map_hash == m.map_hash`, `content_hash() == map_hash`, corrupt byte ⇒ `null`; view layers survive (`visual_hash` equal); `clone_for_world()` twice ⇒ independent dynamic state, equal static arrays |
| U14 | dirty flush | after random occupy/vacate sequences, `flush_dirty(∞)` yields graphs equal to freshly built ones (`node_of_cell`, `adj`, `cc`) |
| U15 | symmetry primitives | for D1X/D2/D4 and 200 random primitives (disc, segment, rectangle), painted cell sets are exact mirror images; DN: hole-free (every cell inside the analytic shape is painted in every image) |
| U16 | profiles | `SimMoveProfiles.build` on the fixture data: Guardian `np 2, nav_size 2, mass 3, accel_q4 272, decel_q4 408, TM_PIVOT, reverse 50`; a wheeled scout `TM_ARC`; infantry `nav_size 1, TM_INSTANT, reverse 0`; fighter `TM_BANK`, gunship `TM_INSTANT`; ship_large `np NAVAL_DEEP, nav_size 3` |
| U17 | predicates | `is_water` true on ford/shallow/deep, false on beach; `water_body_size` equal for all cells of one lake, 0 on land; `passable(cx,cy,mc)` false on a structure cell for every ground mc; `is_clear(…, AIR)` true inside the interior; `region()` equal for two cells of one component, −1 in a cliff |
| U18 | generator params | `validate_params(0, 96, 2) == ""`, `(0, 96, 4)` ⇒ size error, `(1, 100, 2)` ⇒ "size must be a multiple of 8", `(3, 128, 2)` ⇒ family error; `from_config` ignores unknown keys; `min_size = {2:96, 3:112, 4:128, 6:160, 8:192}` |
| U19 | hash coverage | `SimTestKit.check_hash_coverage(SimMoveComp.new(), SimMoveComp.HASH_EXEMPT)` returns `[]` |

### 10.2 Scenario tests (SimWorld; tick counts derived from §5.4)

| ID | Scenario | Expected |
|---|---|---|
| S1 | Guardian 50 cells across a flat map (`T_MOVE`) | arrives in **500–512 ticks** (independent 1-D simulation of the speed law: 505); `spd_q4` reaches 1632 at tick 6; final `\|pos − goal\| ≤ 256`; state `MS_ARRIVED`, `RS_OK`; order DONE at the next stage 5 |
| S2 | forest strip between two rooms | infantry crosses (time in the strip × 1/0.70); tracked crosses at 55 % (`(Δ cells/tick) / free-run = 0.55 ± 0.05`); a wheeled scout's order fails: `RS_NO_PATH` within `PATH_WAIT_MAX`, `ORDER_FAILED` emitted once, the rest of the queue continues |
| S3 | river with a 5-wide ford (`SHALLOW`) between two banks of deep water | wheeled, tracked and infantry path through the ford only (waypoints inside ford cells) at 50 / 65 / 70 % speed (ratio ± 0.05); amphibious crosses the deep river anywhere at `deep_speed_bp`; a naval small hull may sail over the ford (80 %), a deep-only hull (`radius ≥ 922`) may not |
| S4 | 30-unit group of the four ground classes (inf / light / medium / heavy: radius 410 / 461 / 563 / 819, speed 87 / 164 / 102 / 77, mass 1 / 2 / 3 / 5) ordered 30–40 cells across a flat map through one `MOVE` command (30 fresh `T_MOVE`s) | ≤ 3 searches (`SimPathService` counter), ≥ 27 cache/attach hits; all arrive within **500 ticks** (independent simulation of §5.4/§5.5 with these classes: 427–459 ticks for n = 30–50, 407–482 for n = 10–100; medium-only groups 340–364; the heavy class at 77 units/tick sets the pace); at rest min pair distance ≥ `0.75 × (r_i + r_j)` (simulation: ≥ 0.82 for 10–100 units) with ≤ 0.5 % of pairs below `0.85` for n ≥ 30 (simulation ≤ 0.46 %; ≤ 1 pair for n = 10); total motion of all units over the next 200 idle ticks ≤ 250 units (simulation 0–211) and no unit drifts more than 80 units after settling (simulation ≤ 59); slots match `SimFormation`; with `OF_NO_FORMATION` every unit goes to the exact point |
| S5 | idle friendly units in a 6-wide corridor, mover passes | mover reaches the far end; each idle unit displaced ≤ 3 cells; no unit inside a wall cell |
| S6 | 1-lane corridor fully blocked by an immobile enemy | escalation: sidestep skipped (enemy), repath at 20 ticks, nudge at 30, `RS_STUCK` at **tick 80 ± 10** after blocking begins (first repath at `STUCK_REPATH_TICKS = 40`); the order fails |
| S7 | building placed across the route mid-way | validity check detects within 8 ticks; new path avoids it; arrival; no unit enters a blocked cell (assert each tick) |
| S8 | amphibious tank crosses a lake | exactly one `STATE(ST_entered_water)` and one `ST_left_water`; cells/tick on deep water = `speed_water/1024` ± 5 % (`speed_water` = `effective_speed(speed, AMPH, DEEP, deep_speed_bp, water_mult_bp)`); `F_ON_WATER` true only between the events (≥ 6 ticks hysteresis at shorelines); `layer` stays `GROUND` |
| S9 | ships | size-2 ship cannot enter a 2-wide channel (`RS_NO_PATH`/partial), passes the 7-wide moat and bay canals; a size-3 hull needs 5-wide deep water; a deep-only hull never routes over a ford, a small hull does; no ship path cell on land |
| S10 | air | fixed-wing flies 100 cells: never below 60 % speed; reaches the holding pattern radius 4096 ± 512 and `air_at_goal` latches; `air_takeoff(ticks = 20)` flips `layer` to AIR at exactly tick 20 and emits `STATE(ST_takeoff)`; `air_land_at(x, y, −1, ticks = 30)` touches down exactly 30 ticks after the final descent starts, snaps to `(x, y)`, sets `GROUND`, emits `STATE(ST_landed)`; rotor: `air_hover` stops within braking distance, `air_face` yaws at `turn_rate`; parked aircraft cost nothing and never collide; the mover loop skips `F_DEAD` |
| S11 | transport (stub `SimTransport`) | 4 squads `T_LOAD` a Landing Transport floating 2 cells off shore: `board` called ≤ 60 ticks after issue; a carrier 3 cells off ⇒ order FAILED (`RS_NO_PATH`); `T_UNLOAD` with a land drop point moves the carrier to the shore cell nearest to it, calls `begin_unload` exactly once after it stopped, DONE when the stub's cargo list is empty; `T_GARRISON` approaches a building footprint edge within 512 |
| S12 | 3 collectors, 1 refinery (stub economy) | `glide(dock, 12)` and `glide(exit, 8)` take exactly 12 / 8 ticks; a gliding unit is not pushed by separation and does not push; interpolation endpoints exact |
| S13 | factory produces 10 tanks back-to-back with rally | `find_free_cell_near` returns distinct cells (no disc overlap); each tank clears the door ≤ 40 ticks after spawn; when all cells within 4 rings are taken the call returns −1 |
| S14 | building placed on friendly idle units | `eject_units_from_rect` moves them out in the same call, ascending id, each to the nearest free cell outside the rectangle; a boxed-in unit gets `MS_EVICT` and leaves ≤ 40 ticks; enemy units are not moved |
| S15 | stat-mod slow (stub `speed_units` × 0.65) on a tracked unit | moves at 65 ± 2 % of normal, infantry unaffected; `nav_version` unchanged, no repath |
| S16 | Open Corridor stub (`speed_units` × 1.25) | distance in 100 ticks = 1.25 × baseline ± 1 %; removal restores |
| S17 | deployed unit (stub `is_immobile = true`) receives `T_MOVE` | `request_pack` called once; the unit waits (no goal set) until `is_immobile` turns false, then moves; a lone `is_turn_locked` unit does not rotate |
| S18 | speed-match group (`movement.json formation.speed_match = 1`) | slowest member's `speed_base·16` caps everyone |
| S19 | patrol | two-point patrol bounces between origin and target for 3 000 ticks without queue growth; three chained patrol orders cycle P1→P2→P3→P1; with combat's `T_ATTACK_MOVE` registered the leg is a child order (engaged units pause and resume) |
| S20 | submarine surfacing | `request_layer(SURFACE, 40)`: layer flips at tick 40, `STATE(ST_surfaced, layer 2)` once; hash layer becomes `HL_WATER` |

### 10.3 Determinism tests

| ID | Test | Pass |
|---|---|---|
| D1 | scenarios S4 + S7 + S10 combined, 3 000 ticks, run twice in one process (two worlds side by side, DR-9) | identical checksum chain (every 20 ticks) |
| D2 | history independence | rebuild `SimSeparation` from scratch mid-run and compare to the incremental one; abort/restore the path service via its `state_ints` snapshot ⇒ same subsequent checksums |
| D3 | cross-platform | golden checksum chain for D1 recorded on macOS arm64, reproduced by `tools/gd linux test` (Debian x86_64) |
| D4 | generator goldens | `map_hash` for {open, urban, coast, coast+`start_near_water`} × {2,3,4,6,8 slots} × {min size, 128, 192} × seeds {1, 7, 12345} recorded on macOS, identical in the Linux container; main-thread vs worker-thread (`MapGenJob`) generation equal; `to_bytes` byte-identical |
| D5 | KATs (U1) on both platforms | identical |
| D6 | debug self-checks every 20 ticks in scenario runs | `recompute_dynamic_hash`, `validate_against_terrain`, graph rebuild equality all hold |

### 10.4 Generator statistical tests (nightly, 200 seeds per cell of the matrix)

* first-attempt/level-0 success ≥ 99 % (prototype v4: **672/672** distinct maps); after the loop 100 % valid; the template validates for every slot count/size;
* D1X/D2/D4: terrain mismatch between images ≤ 1 % of sampled cells and confined to neutral lots (prototype 0–0.7 %); DN3/DN6: ≤ 25 % of sampled cells (prototype 12–21 %, class-boundary cells);
* V7 detour-ratio spread ≤ 15 % (prototype 0 ‰ for exact groups, ≤ 17 ‰ for DN);
* V10: reachable credits per slot ≥ 75 000 (prototype 129 600; 115 200 in one coast/8-slot batch); field totals identical across images (assert), `Σ deposit_max = Σ fields.total`;
* V11: with `start_near_water` every start has a Dock site (prototype 180 coast maps, all starts);
* land-only guarantee: for `water_pct = 0` no `DEEP/SHALLOW/BEACH/FORD/MARSH` cell exists; for coast maps each start's component contains all fields and lots when every water cell except fords is deleted;
* neutrals per map within ±25 % of economy's guidance (1 substation, 1 field hospital, 1 observation tower per slot; 1 depot per map);
* soft timing check (telemetry): 192² ≤ 1.5 s M-class including nav, warn only.

### 10.5 Visual tests (agent inspects PNGs with the image reader)

`MapPng.terrain` dumps at 3–4 px/cell for each family × {2,4,8 slots} × 3 seeds (+ `start_near_water` coast), with overlays for fields (gold = standard, orange = rich), neutrals, starts and — for `MapRegions` if built — regions/chokes; plus a hillshade of `heights`. Checklist: (1) mirror/rotational symmetry visible; (2) start discs flat and clear with ≥ 2 wide exits; (3) coast: fords where routes cross the moat, beaches only on shore, marsh only within 3 cells of water, straight bay canals with a rectangular pocket next to every start, no field in water; (4) urban: lattice in *both* halves for 2 slots (regression for the negative-modulo bug), alleys thin, avenues 6 wide; (5) fields gold/orange, ring clear, neutrals on lots; (6) no isolated coloured islands; (7) hillshade shows flat terraces with cliff steps and a rim falling away at the edge. Movement visuals via `gd shot`: formation arrival, amphibious wake event, landing/takeoff.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

| ID | Task | Files (own) | Depends on | Acceptance | ~LOC |
|---|---|---|---|---|---|
| **TM-01** | Terrain tables & loader | `map_terrain.gd`, `data/balance/terrain.json`, `tests/test_map_terrain.gd` | data: `DefMoveTable`, `DefEnums` (or a fixture `DefMoveTable`) | U2; `table_hash` stable; JSON schema errors reported; enum mirrors asserted | 450 |
| **TM-02** | `MapData` core (layers, predicates, deposits, occupy/vacate, hashes, clone, `make_flat`, serialisation) | `map_data.gd`, tests | TM-01, core `Checksum`, `IntGrid` | U9 (map part), U12, U13, U17, incremental hashes | 1300 |
| **TM-03** | `MapNav` (weights, clearance, LOS, nearest, deferred update, region ids) | `map_nav.gd`, tests | TM-02 | U3, U4, U9, `validate_against_terrain` | 950 |
| **TM-04** | `MapNavGraph` | `map_nav_graph.gd`, tests | TM-03 | U14; node counts on fixtures (1 025–1 075 at 256², 12–35 % clutter); `estimate_cost` ≈ octile on open map | 850 |
| **TM-05** | `MapPathSearch` (LOS, fine, abstract + corridor, smooth, partial, resumable) + micro-bench | `map_path_search.gd`, `tests/bench_path.gd` | TM-03, TM-04 | U5, U6; bench: ≤ 1.9 µs/visited (M-class) | 1200 |
| **TM-06** | Footprints & terrain build rules | `map_footprint.gd`, `map_build_rules.gd`, tests | TM-02, TM-03 | U10, U11 | 500 |
| **TM-07** | Generator core: params, tables, noise, symmetry, phase A (3 families, marsh, rim) | `map_gen_params.gd`, `map_gen_tables.gd`, `map_gen_noise.gd`, `map_gen_symmetry.gd`, `map_gen_terrain.gd`, `data/balance/map_gen.json`, tests | TM-01, TM-02 | U1, U15, U18, exact symmetry, phase-A timing ≤ 0.5 s at 192² | 2000 |
| **TM-08** | Generator layout (starts, bay, gates, fields, neutrals), view layers, validation, orchestration, template, job | `map_gen_layout.gd`, `map_gen_view.gd`, `map_gen_validate.gd`, `map_generator.gd`, `map_gen_template.gd`, `map_gen_job.gd`, tests | TM-03, TM-04, TM-06, TM-07; data neutral footprints | §10.4 statistics, D4 goldens, progress monotonic, thread-safe, job equality | 2500 |
| **TM-09** | Test support + optional AI analysis | `tests/support/map_png.gd`; **P3:** `map_regions.gd` | TM-02..TM-04 | PNG dumps for §10.5; (`MapRegions` region/choke fixtures ≤ 150 ms at 256² only if scheduled) | 300 (+650) |
| **TM-10** | Movement core: config, component, profiles, path service | `sim_move_config.gd`, `comp/sim_move_comp.gd`, `sim_move_profiles.gd`, `sim_path_service.gd`, tests | TM-05; sim_core SC-04 (component stub), `DefUnit` | U16, U19, request/cache/attach unit tests; budget accounting (units consumed ≤ budget, resumable) | 1500 |
| **TM-11** | Movement system: steering, separation, terrain rule, stuck, adapters, facade | `sim_movement_system.gd`, `sim_steering.gd`, `sim_separation.gd`, `sim_movement.gd`, tests | TM-10; core `Fp`; sim_core `SimSystem` hooks | U8, S1, S2, S3, S5–S9, S15–S17, S20 | 2300 |
| **TM-12** | Order handlers & formation | `sim_order_move.gd`, `sim_formation.gd`, tests | TM-11; sim_core order dispatcher | U7, S4, S18, S19; `MOVE/STOP/SCATTER/PATROL` end to end through the command executor | 800 |
| **TM-13** | Air movement | `sim_air_move.gd`, `sim_order_air.gd`, tests | TM-11 | S10 | 1000 |
| **TM-14** | Cargo approach handlers | `sim_order_cargo.gd`, tests | TM-11; abilities `SimTransport` (stub in tests) | S11 | 350 |
| **TM-15** | Exits, eject, glide | `sim_exit_move.gd`, tests | TM-11 | S12–S14 | 500 |
| **TM-16** | Integration, determinism, perf | `tests/test_move_determinism.gd`, `tests/bench_move.gd`, golden files | all | D1–D6, perf table of §9 reproduced within ×1.5 | 700 |

Parallelism: TM-01→02→03→04→05 is the critical map chain; TM-06 and TM-07 start after TM-02; TM-08 after TM-04/06/07; the sim chain TM-10→11→{12,13,14,15} starts once TM-05 exists (TM-10 can begin against stubs that `push_error("NOT IMPLEMENTED")`); TM-13/TM-14/TM-15 are independent of each other. Every task ends with `tools/gd check` clean and its tests green.

---

## 12. Risks, open questions and your recommended resolution for each

The first block records **conflicts between concurrently published specs** that touch this domain: for each, what this spec does, and the shim that keeps both callers working until the reconcilers decide.

| # | Risk / question | Recommended resolution |
|---|---|---|
| R1 | **Three deposit models.** global.json / FRAMEWORK §5.8 / data_balance §7.14: per-cell stock (600 / 1 200 per cell, 24- and 16-cell fields, "a load of 600 empties exactly one cell", nearest non-empty cell). economy.md §5.9: field discs with caps 8 000 / 12 000 / 20 000, regrowth, `SimDepositTable`. sim_core §4.12: DEPOSIT entities with the amount in `SimEcoComp`. data_balance risk 18 already says the domain file (economy.json) wins the *constants*. | **Per-cell stock in `MapData` is the single mutable store** (O(1) `harvest_*`, incremental hash, view dirty list); everything else is a read view built from the same generator output: `deposit_fields()` (discs with `klass_economy` 0/1/2 for economy's table), `fields`/`objects` (sim_core's optional DEPOSIT entities as pure visual proxies, no state). The generator takes cell counts and per-cell credits from `GameData.economy.deposit_*`, so whichever constants win, the map follows (`resources` scales them). If economy keeps discs with caps, it uses `field_remaining(id)` as `stock` and `harvest_field` as the take. |
| R2 | **Ownership overlaps with combat/sim_core.** (a) combat.md §5.12 says aircraft layer flips are combat's; sim_core §4.2 says `set_layer` is movement's. (b) combat expects `e.vx/e.vy` and `cc.ext_moving` written by movement; sim_core has neither (it has `F_MOVING`). (c) cargo component/fields: sim_core `SimCargoComp` + `holder`, abilities `SimCompCargo` + `container_id`, combat `container_id`. (d) economy asks for `F_SCRIPTED_MOVE`/`F_NO_FOOTPRINT`. | (a) movement flips inside `air_takeoff(ticks)` / `air_land_at(…, ticks)` at combat's chosen durations; combat only observes `e.layer`. (b) `F_MOVING` + `SimMovement.is_moving` + `SimMovement.velocity(e, out)` replace `ext_moving`/`vx,vy`. (c) `set_inside/holder` (kernel) are the truth; abilities may alias `container_id`. (d) `glide` is the scripted-mover primitive (immune to steering/separation); no flag needed. |
| R3 | **Forest and tracked vehicles.** The task text says "forest blocks vehicles"; TAXONOMY §8 (frozen) gives tracked 55 % and amphibious 50 % in forest and blocks only wheeled. | This spec follows the table (D-3) and derives everything from it, so **flipping the two entries to 0 in `global.json` changes no code**: nav profiles, weights and the land-only guarantee (intersection of foot/wheeled/tracked) adapt, and the generator statistics stay valid because the guarantee never used forest. If the design intent is "forest blocks all vehicles", balance edits two numbers and TAXONOMY §8's note. |
| R4 | Amphibious `layer` semantics and "water" for conditions. | Amphibious units stay `GROUND` + `F_ON_WATER` (D-10, TAXONOMY §7 `layer_mask ground+water`); data folds `ON_WATER` into `water_mult_bp` statically, so nothing reads the flag except presentation. Water = kind SHALLOW or DEEP, hence fords and shallows count as water for `water_mult_bp` and `is_water`. Combat that wants surface targeting for swimmers must read `F_ON_WATER`, not `layer`. |
| R5 | **Footprint and placement authority.** global.json footprints (HQ 3×3, Refinery 3×3, Airfield 4×3 with 4 pads, Anti-tank turret 2×2, Watchtower 1×1) vs economy `structure_rules.json` (Airfield 6×3 with 6 pad cells, Anti-tank turret 1×1, plus exits, aprons, berth); data_balance says footprints come from `global.json`, economy says `structure_rules.json` owns them; economy's ten-rule `SimPlacement` vs the task's spacing/apron rule owned by the map. | Map side is *data-driven and agnostic*: `MapFootprint.cells` takes whatever `DefStructure` says; `MapBuildRules` supplies terrain/shore/occupancy only (§5.10); there is **no global spacing rule** in the map; aprons are economy's. The generator only assumes an HQ of 3×3 (asserted against `DefStructure` in V9) and a Dock of 3×3 with a 3×2 berth (V11). Reconcilers pick one footprint source. |
| R6 | **Movement API naming.** combat.md: static `SimMovement.move_to/…/air_*`; economy.md: `world.movement.request_move(ent, …)` with no `world` argument (systems must not store the world); abilities.md: `world.movement`; sim_core has no named system fields. | §3.10.2 defines one static facade `SimMovement` carrying every name the peers use (`move_to`, `move_to_range`, `stop`, `turn_to`, `is_moving`, `request_move`, `at_goal`, `path_failed`, `find_free_cell_near`, `eject_units_from_rect`, `air_*`) with `world` first. Economy's adapter adds the argument; sim_core is asked for `world.movement` (§13-1). |
| R7 | Vehicles need ≥ 3-wide passages; gaps of 1–2 cells between structures are foot-only, so players/AI can wall in vehicles (there is no spacing rule). | By design (C&C-like); pathing degrades to "nearest reachable" (`RS_PARTIAL`); AI must keep 3-wide lanes (`MapBuildRules.scan`, `MapNav.passable`); UI may show a "blocks vehicles" hint. |
| R8 | Path-latency bursts (10+ group orders) delay some groups by ≈ 0.4–0.75 s. | Accept; tune `PATH_BASE`/`PATH_PER_PENDING`; units already turn toward the goal. Optional: split `PRIO_ORDER` into human/AI classes if `players[pid].controller` is available. |
| R9 | No automatic "clear the door": a produced unit with no rally point idles at the exit and is pushed aside by later spawns; a full ring makes production pause (`QS_PAUSED_EXIT`). | Economy/production should issue a default rally 3 cells beyond the exit when the player set none (recommended; one `T_MOVE` per spawn). |
| R10 | 3-/6-slot maps are only approximately symmetric (≤ 1 cell, 12–21 % boundary-cell class differences); octile path costs are anisotropic. | Field totals are exactly equal, V7 uses the detour ratio (≤ 17 ‰ measured), own fields sit on straight carved routes. Lobby option "exact symmetry only" = 4-/8-slot map with empty slots (`fair_slot_order`). |
| R11 | GDScript speed on weak laptops (×2.5–3); `world.set_pos` + adapter calls add ≈ 1 µs per mover. | Profile with TM-16 early; levers in §9.2; all budgets are counts so results never change. |
| R12 | Worker-thread availability for `MapGenJob` (headless tests, exports). | Unthreaded mode is stage-sliced and result-identical; a stage is ≤ ~0.5 s at 256², absorbed by net's `TIMEOUTS_LOADING`; flag to sim/net owners in §13. |
| R13 | Seven nav profiles × sizes (at most eight (profile,size) graphs) cost memory (≈ 2.1 MB) and finalize time (≈ 0.3 s at 256²). | Only profiles with ≥ 100 passable cells get graphs (dry maps skip the three naval profiles); `prepare_all` runs in the worker thread; `clone_for_world` copies arrays only. Optional: merge profiles with identical weight vectors (deterministic, lowest profile index). |
| R14 | Speed authority: movement multiplies `abilities.speed_units(e)` (already includes research/aura/debris) by terrain and water, and combat's suppression. Double application (e.g. abilities also folding suppression or `ON_WATER`) would slow units twice. | data_balance §5.5.5 folds `ON_WATER` into `water_mult_bp` **only**; abilities.md §5.11 makes debris a stat mod; combat's suppression is separate by design. A test with all three stubs asserts the product (S15/S16/U8). |
| R15 | Data-hash sensitivity: tuning `terrain.json`, `map_gen.json` or the economy deposit constants changes maps (and weights, so all paths). | Intended (DR-10): the three files enter the data hash; `gen_version` must equal `MapGenParams.VERSION`; lobby compares `map_hash` after generation. |
| R16 | Start order and slot counts: net offers `layout_players` 2/4/6/8 and wants adjacent start indices adjacent; this generator also supports 3. | `start_cells` are in circular order (§5.12.3); `validate_params` accepts {2,3,4,6,8} — net may simply not offer 3. qa.md's automatic sizes (96 / 128 / 160 / 192 for 2 / 3–4 / 5–6 / 7–8 players) equal `min_size`; the lobby default `recommended_size` is one step larger. |
| R17 | Centre-cell terrain collision lets big units visually overlap walls by up to their radius. | Accept for v1; optional refinement: for `nav_size ≥ 3` require `clr ≥ 2` for the destination cell in phase C. |
| R18 | Generator changes between game versions alter maps of old replays. | Replays store `to_bytes()` or the config + `gen_version`; regenerate only in tests. |
| R19 | `Fp.isqrt`/`atan2` speed and exactness (used per unit per tick). | sim_core §3.2.2 already specifies exact `isqrt`; ≤ 0.5 µs each is assumed. |
| R20 | `SpatialHash` vs private separation grids. | Private 2-cell grids are kept (rebuild 0.09 µs/entity; the kernel's 4-cell hash returns sorted lists at ≈ 7 µs per query, which would cost ≈ 2 ms for 300 movers); `find_free_cell_near` and `eject_units_from_rect` use the kernel hash. |
| R21 | Fords make rivers non-navigable end-to-end for deep-only hulls. | Intended: the coast moat is a closed lake served by harbor terminals (small hulls and the Landing Transport pass fords), the surrounding sea and bay canals are navigable for every hull; a pure-naval family can be added later by omitting fords. |
| R22 | Alleys (1-wide `PAVEMENT`) are foot-only shortcuts in urban maps — good for flanking, they cost pathing extra nodes. | Accept; measured urban graph 725–794 nodes. |
| R23 | Generation of a 256² map takes 0.7 s even on M-class before nav (1.0 s with nav). | TM-07 must include the lattice-cache/fundamental-domain optimisation; acceptance timing test; the job hides it behind the loading screen. |
| R24 | Sub-cell ties: units exactly overlapping get a deterministic push direction from ids; two stacked spawns can still take ~10 ticks to unglue. | Spawn placement avoids overlap (`find_free_cell_near`); acceptable. |
| R25 | Terrace-quantised `heights` and the rim ramp were checked with a hillshade dump only. | View-only (not in `map_hash`); render can retune the formula without desync risk. |
| R26 | qa.md DA-29 says reachable credits ≥ 60 000 per player, balance says 75 000 (target 110 000). | The generator delivers 129 600; V10 enforces 75 000 × scale. |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**sim_core**
1. Typed, named system accessors on `SimWorld` — at least `movement: SimMovementSystem` (combat.md, economy.md and abilities.md all call `world.movement`/`world.combat`/`world.abilities`), or the constant `SimPipeline.STAGE_MOVEMENT = 6` with `world.stages[6]` guaranteed to be the movement system (`SimMovementSystem.of(world)` uses it).
2. Confirm the `move` slot (`SimMoveComp`, body owned here, `hash_into` + `HASH_EXEMPT`, file `src/sim/comp/sim_move_comp.gd`) and that `SimMovementSystem.on_spawn` may create it for UNIT entities; confirm `system_name() = "movement"`.
3. Event amendment for the master `STATE` catalog (sim_core §6.2): `ST_entered_water = 16`, `ST_left_water = 17` (amphibious crossing), `ST_surfaced = 18`, `ST_submerged = 19` (`value` = new layer), emitted by this domain; existing `ST_landed = 10` / `ST_takeoff = 11` are emitted by `air_land_at` / `air_takeoff`.
4. Confirm that `world.set_layer` for **aircraft and submarines** is written by movement (combat.md §5.12 claims the aircraft flips) and that `set_pos` clamps to the map (aircraft near the edge are steered back by movement, not by the clamp).
5. MapData contract (R7/R9): `w, h, start_cells (circular order), objects, map_hash, clone_for_world(), hash_state(buf), make_flat(w, h, start_cells, map_hash)` are provided as specified in §3.3; the constructor spawns neutral structures from `map.objects`, and the structure-lifecycle owner (economy) calls `map.occupy(structure_id, cells)` from its spawn hook for every structure, neutral or not, and `vacate` from `on_removed`; `world.struct_grid` requested by economy/render **is** `world.map.occ` (`MapData.structure_at(i)`) — do not add a second grid.
6. `SimTestKit.make_map(w, h)` = `MapData.make_flat(...)` (NAV_BORDER = 2 blocked cells, no rim) and a `TestMoveHandler` that yields to the real handlers once `SimOrderMove` is registered.
7. Order dispatcher facts relied on: `begin` and `tick` fused in one pass, `cancel` called on replace/clear, `OF_NO_FORMATION`, `OF_CYCLIC` re-append on DONE, `has_handler(type)`; `world.units_of(owner)` ascending; `world.query_radius/query_rect` sorted ascending and up to date after `set_pos`.
8. Cargo owner: assign `SimCargoComp`/`container_id` naming (abilities.md calls it `SimCompCargo`/`container_id`, sim_core `SimCargoComp`/`holder`); movement only needs `SimTransport.can_board/board/garrison_enter/begin_unload/cargo_of/free_slots` (abilities.md §3.5).

**data / balance**
9. `DefUnit` fields `move_class, size_class, speed, deep_speed_bp, water_mult_bp, accel_t, turn_rate, radius, home_layer` (per player: the resolved value, e.g. `world.players[pid].view.unit(def_idx)` — the exact accessor name is the data domain's), `DefMoveTable.speed_bp/layer/layer_mask`, `DefBodyTable.radius_u/mass/turn_apt`, and the `movement_defaults` block (`accel_ticks{size}`, `decel_ticks_pct_of_accel`, `reverse_speed_pct`, `formation_spacing_cells_extra`, `stuck_repath_ticks`) exposed on `GameData` (today they exist only in `global.json`).
10. Loaders and data-hash inclusion for `terrain.json`, `movement.json`, `map_gen.json` (`GameData.terrain: MapTerrain`, `GameData.map_tables: MapGenTables`); `MapGenTables` receives the neutral footprints from `DefNeutral`/`neutral_structures.json`.
11. **One authority** for deposits (R1): cell counts and credits per cell (`economy.deposit_*` in `global.json` vs `economy.json`), the map budget (75 000 / 110 000) and `start_field_distance_cells` (8–16); the generator follows `GameData.economy`.
12. Footprint authority (R5): HQ 3×3, Airfield 4×3 (global.json) vs 6×3 (economy), neutral sizes; the map generator asserts only HQ 3×3 and Dock 3×3 + 3×2 berth.
13. `DefUnit.speed_water` remains a derived cache (data_balance §4.2); movement does not read it (it recomputes in Q4), but AI does.

**abilities / zones**
14. Keep and confirm: `speed_units(e)` (units/tick, all stat effects, **not** terrain/water/suppression), `is_immobile(e)`, `is_turn_locked(e)`, `request_pack(e) -> bool`; `SimTransport` API as in abilities.md §3.5; debris as a stat mod on land vehicles standing on land plus `zones.blocks_construction`; `DF_UNLOAD_MOVING` readable from `SimStats.flags`.
15. Call `SimMovement.request_layer(world, e, layer, ticks)` for submarine surfacing/submerging (`want_surface`, `transition_s`).

**combat**
16. Use the primitives of §3.10.2 by name and the flag/query replacements of R2 (`F_MOVING`, `SimMovement.velocity`); pass `takeoff_ticks` / `landing_ticks` to `air_takeoff` / `air_land_at`; do not write `e.layer` for aircraft; register `T_ATTACK_MOVE` so patrol legs can be attack-moves; call `SimMovement.stop` on `clear_target`; skip crash motion in movement (combat moves dying aircraft itself, the mover loop ignores `F_DEAD`).

**economy / production**
17. Placement: compose `MapBuildRules.check_land/check_berth`, `MapData.is_buildable/is_passable_ground/water_body_size/structure_at`, and call `MapData.occupy(sid, cells)` / `vacate(sid)` (weights update immediately, clearance and graphs are deferred and count-bounded); call `SimMovement.eject_units_from_rect` before spawning the structure entity (§5.9).
18. Harvesting: build `SimDepositTable` from `MapData.deposit_fields()` (or read fields directly), take credits with `harvest_field(field_id, collector_cell, want)`, use `SimMovement.go_to/stop/at_goal/path_failed` for trips and `glide(dock_cell, 12)` / `glide(exit_cell, 8)` for the dock motion; regrowth (if any) via `regrow_field`.
19. Spawning: `SimMovement.find_free_cell_near(cell, layer, 4)` for the exit, pad cell for aircraft from `airfield_pad_cell` (movement never owns pads), default rally (R9); neutral structures from `MapData.neutral_spawns()`.

**net / app**
20. `MapGenerator.validate_params(family, size, layout_players)` in the lobby (`map_validator` callable), `MapGenJob.begin(map_cfg)` behind `opts.world_builder` (worker thread by default), `MapData.content_hash()` for `LOAD_DONE.map_hash` comparison, `to_bytes/from_bytes` if the host distributes the map instead of the config; `map` config keys `family, size, seed, layout_players, params{water_pct, density, resources, neutrals, biome, start_near_water}`.

**render / view / audio**
21. Read the map only through the field contract of §5.14 (`ViewTerrainSource.from_map`); use `STATE` events 10/11/16–19 for landing/take-off/splash/surfacing cues; `SimMovement.altitude(e)` and the `F_AIRBORNE` flag for aircraft shadows.

**ai**
22. `MapData.passable(cx, cy, mc)`, `region(cx, cy, mc)`, `is_water`, `get_family()`, `start_cells` in circular order, `deposit_fields()`, `objects`, `MapNav.estimate_cost/same_region`, `SimMovement.eta_ticks`; `MapRegions` only on request (P3); keep ≥ 3-cell vehicle lanes when placing structures.

**qa / tooling**
23. `MapGenerator.generate(map_cfg)` (pure), `MapGenValidate.validate/metrics` for DA-29 (exits per start, reachable credits, no mandatory water), config flag `start_near_water`, golden `map_hash` files under `game/tests/golden/`, test filters `map_` and `move_`, the Debian container run for D3/D4, the `MapPng` helper for visual checks.

**reconcilers**
24. Decide R1 (deposit authority), R2 (layer flip / velocity / cargo naming), R3 (forest for tracked/amphibious), R5 (footprint authority), R6 (movement API names) and record them in `docs/AMENDMENTS.md`; assign the four `STATE` codes of item 3.
