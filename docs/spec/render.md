# MERIDIAN FRACTURE — Render / View Domain Specification

> **Domain:** 3D presentation (`game/src/view/**`, `game/assets/shaders/**`, `game/data/recipes/**`). **Author role:** domain architect, render.
> **Authority:** subordinate to `docs/ARCHITECTURE.md` (the anchor wins on conflict) and to the bible. The concurrently published domain specs disagree with each other in places (event codes, def index spaces, deposit model); this spec therefore follows `sim_core.md` for everything the view reads from the kernel (entity fields, flag bits, the MASTER event catalog, the fog API, call order), `data_balance.md` for definitions, `terrain_movement.md` for `MapData` and footprints, `net.md` for the frame driver and `qa.md`/`qa_tooling.md` for test and lint conventions. The proposals of `combat.md`, `economy.md` and `abilities.md` are consumed through the alias table of section 6.2.3. Every dependency on a domain without a published spec (`ui`, `audio`, `app`) or on a name that no published spec defines is marked `ASSUMPTION(domain)` and listed in section 13.
> **Provenance of numbers:** three throw-away spikes were run before this spec: models `[M]` (`prototypes/models`), terrain `[T]` (`prototypes/terrain`), VFX `[F]` (`prototypes/vfx`). Their `REPORT.md` files are **not on disk**; the measured numbers quoted here come from the briefing that accompanied this task, and the *proven code* is on disk under `prototypes/*/src` and `prototypes/*/shaders` and is the reference implementation to lift from (paths are cited per class). Hardware for every measurement: Apple M5 Max, Metal, Godot 4.7.2, shared machine, so deltas below 0.3 ms are noise and GPU timestamps read 0.0 on Metal.
> **Reading rule:** *Section 4* is the contract between shaders, builders and runtime code (vertex layout, instance uniforms, global uniforms, enums). *Section 7* is the contract with faction designers (recipe JSON). *Section 13* is the contract with other domains.

**Key decisions (index).** (1) Every unit/structure = one mesh, one surface, one material per faction look, animated in the vertex shader from 4-8 instance floats; team colour on masked surfaces only (§4.2-4.4, §5.8). (2) Recipes are JSON op lists (archetype + style + slots + macros) interpreted at load into `ViewMeshBuilder` calls; ~215 recipes, ~330 meshes, built lazily and threaded (§5.8, §7). (3) Two unit backends chosen by renderer capability: node + instance uniforms (Forward+) or MultiMesh batches (Mobile, Compatibility) (§4.4, §5.12). (4) Terrain = 32-cell chunks of a baked heightfield + one splat shader; water = one plane; fog of war = one byte per cell uploaded at 10 Hz and cross-faded on the GPU; unit visibility is decided on the CPU from the sim (§5.3, §5.5, §5.7). (5) VFX = 34 MultiMesh ring-buffer batches animated by `fx_time`, admission by token buckets and culling, data-driven recipes in `fx.json`, no GPU particles, no Decal nodes (§5.9). (6) Interaction overlays are instanced quads/ribbons with constant-pixel-size shaders (§5.10). (7) Four quality presets plus a renderer clamp table and an auto-downgrade ladder; nothing is keyed on the OS name (§4.9, §5.12). (8) The view reads the sim only (ids + its own two-sample snapshots, because the kernel stores no "previous" fields), consumes the MASTER event catalog of `sim_core.md` as one flat int32 batch per rendered frame, isolates every foreign name in four adapter classes (`ViewSimReader`, `ViewDefAdapter`, `ViewTerrainSource`, `ViewEventRouter`) and adds nothing to the checksum (§6, §8). (9) Work is split into 35 tasks in 6 waves; content tasks (recipes, fx) carry the visual bar through mandatory screenshot rounds (§10.4, §11).

**Conventions used below.** `m` = metres; 1 sim cell = 3 m (`Fp.CELL = 1024` sim units per cell, so **1 sim unit = 3/1024 m**, exactly representable in float32). `bat` = binary angle (4096 per turn). "Sim" objects (`SimWorld`, `SimEntity`, `SimEvent`) are read-only for this domain (DR-12, DR-15). Model space is **+X right, +Y up, −Z forward, metres, origin on the ground** (units) or **at the footprint centre on the ground with the front/door on +Z** (structures; see §5.1). All view code may use floats, engine RNG and wall time; none of it may write to the sim.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

### 1.1 Owned by this domain

1. **View layer** (`ViewWorld` and friends): mirrors `SimWorld` entities/projectiles/zones/warnings into scene nodes, interpolates `prev -> curr` with the network tick alpha, owns node lifetime and pooling, coordinate mapping, draw order, ray picking for the UI (spatial hash, no physics).
2. **RTS camera** (`ViewCamera`): pan, zoom-to-cursor, orbit, edge scroll, map clamp, focus, shake hook, cinematic mode, ground picking.
3. **World rendering:** terrain (chunked heightfield + splat shader), water, decorations, scorch/tread overlay, blob shadows, atmosphere/sun/sky/fog/grading and the five moods (temperate, arid, arctic, tropical, urban-night), **fog-of-war texture pipeline**, the global-uniform contract shared by every shader, the minimap **source** (baked terrain texture + fog shader; the widget itself is `ui`).
4. **Procedural model toolkit:** `ViewMeshBuilder`, the recipe schema and interpreter (`game/data/recipes/**`), macros, styles/palettes for the 8 factions (+24 subfaction accents), `ViewModelBuilder`/cache, `ViewModelRig`, unit/structure shader, materials, LOD policy, animation model (shader-driven), construction/deploy/destruction visuals, icon and portrait baking.
5. **VFX:** `FxManager` (pooled MultiMesh ring buffers animated by a global clock), data-driven effect recipes (`fx.json`), event router (`SimEvent -> effect`), per-weapon / per-death / per-superweapon / per-power mappings, quality scaling, screen-shake hook.
6. **Interaction visuals:** selection rings/brackets, health bars, status marks, rally lines, waypoint paths, placement ghost with per-cell validity, build-radius overlay, range circles, strategic warning zones, zone visuals (smoke/repair/intercept/debris/reveal), remembered-structure ghosts, floating "+$" text, AI debug overlay (3D part).
7. **Quality system:** Low/Medium/High/Ultra presets, renderer capability fallbacks (Forward+, Mobile, Compatibility), auto-downgrade, performance instrumentation, screenshot-based visual test procedure, the tools/py scripts for recipe validation and stubs.

### 1.2 Explicitly NOT owned

| Not owned | Owner | Boundary |
|---|---|---|
| Any sim state, ticking, events, fog *computation*, wreck/death *rules* | sim domains | I read `SimWorld` through the documented read API and consume `SimEvent`s; I never call a mutating method. |
| Map generation, `MapData`, pathing grids, biome choice, deposit placement, footprints | `map/` | I read only fields published in `terrain_movement.md` 3.3/3.6/4.1 (listed in §3.4 and §13-map). The single adapter class `ViewTerrainSource` isolates all `MapData` coupling. |
| 2D HUD, sidebar, minimap *widget*, selection box drawing, hotkeys, cursors, command issuing, menus, loading screen, tooltips, Field Manual | `ui/` | I supply `ViewPicker`, `ViewMinimapSource`, icons/portraits (`ViewIconBake`), team colours, and overlay APIs the UI drives (`ViewSelection.set_selection`, `ViewPlacementGhost.show`). |
| Audio | `audio/` | Audio reads the same events. I only expose `ViewCamera.listener_transform()`. |
| Balance numbers, weapon/warhead/projectile definitions | balance/data | I own the **fx id vocabulary** (§5.9) and its defaults; balance authors reference ids from it (`pres_fx`, the `fx` strings of `combat_warheads.json`). |
| Settings screen and persistence of accessibility options (`[access] colour_mode, reduce_motion, reduce_flash`) | `ui`/`app` | I read the three keys through `ViewQuality.from_settings` and implement their effect on the 3D world (§5.12); the toggles themselves are `ui`. |
| `project.godot`, autoloads, export presets, settings UI, scene flow, frame driver | `app/` + tooling | I request exact entries (§13-app); `ViewGlobals` self-registers what is missing so nothing breaks if a request is late. |
| The bible and its numbers | nobody | Palettes come from each faction's `visual_direction`; geometry of strategic effects comes from the bible/economy radii (×3 m per cell). |

### 1.3 Design stance (decisions that shape everything below)

* **100 % procedural art** (zero imported meshes/textures): meshes from recipes, textures from noise at boot or from `tools/py` (numpy+Pillow), audio not mine. `[M]`, `[T]`, `[F]` proved this is cohesive and cheap.
* **The view is a pure function of sim state + events** plus its own float animation state. It never feeds back (DR-12/15).
* **Shader-driven animation.** Every unit/structure is ONE `MeshInstance3D` (or one MultiMesh instance) with ONE surface sharing ONE `ShaderMaterial` per faction style; team colour and all animation ride on per-instance data. `[M]`: 400 mixed units = 42 draw calls incl. 4 shadow cascades on Forward+.
* **Short-lived VFX are MultiMesh ring-buffer instances animated by `fx_time`** (never `GPUParticles3D`: 33-36 µs frame cost per active system `[F]`).
* **Everything visual is data**: recipes, styles, moods, quality tables, fx recipes are JSON under `game/data/recipes/`; code contains mechanisms, not looks.
* **Three renderers, one code base**: Forward+ is the design target; Mobile and Compatibility are supported through capability-selected backends and downgrades (§5.12), never OS-name checks.
* **Deterministic *inputs*, non-deterministic *look***: procedural seeds derive from recipe ids so every client builds identical meshes, but VFX randomness is presentation-only and may differ between clients/replays.

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All classes live in `game/src/view/` (module prefix `View*` / `Fx*`, lint L004). One class per file, file = snake_case of the class name (L009), ≤ 1500 lines (L007). Subfolders are organisational only. "Lift" = start from the named prototype file, clean it, adopt it.

### 2.1 Runtime code

| Path (under `game/src/view/`) | class_name | Responsibility | Lift from |
|---|---|---|---|
| `view_world.gd` | `ViewWorld` | Root node; owns all subsystems; `build_async`, per-frame `frame(dt, alpha, events)`, optional `capture_prev`, entity mirroring, queries for UI | new |
| `view_build_options.gd` | `ViewBuildOptions` | Typed options bag for `build_async` (mood override, subdiv, screenshot mode, prewarm scope) | new |
| `view_entity.gd` | `ViewEntity` | Base per-entity view record (typed fields §4.5, two-sample snapshot buffer), shared by units/structures/wrecks | new |
| `view_sim_reader.gd` | `ViewSimReader` | Static, null-safe, allocation-free reads of data that lives inside another domain's component (turret angle, collector fill, rally, capture progress, weapon ranges, zone charges); the ONLY view file that touches `e.combat`/`e.eco`/`e.abil`/`e.zone` internals | new |
| `view_def_adapter.gd` | `ViewDefAdapter` | Resolves `(kind, def_idx)` to a `ViewDef` from `GameData` (both index-space variants), weapon-id to archetype mapping, roster to style ids; the ONLY view file that reads `Def*` fields | new |
| `view_def.gd` | `ViewDef` | Plain record: bible id, faction code, recipe/icon ids, scale, move class, size class, radius, footprint, needs-power, HQ flag, weapon archetypes per mount | new |
| `view_unit.gd` | `ViewUnit` | Unit/aircraft/ship/infantry animation state machine + rig driving (roll, gait, turret, recoil, altitude, bob, deploy, cloak, sink) | new |
| `view_structure.gd` | `ViewStructure` | Structure states: buildup, active (spin/door/activity), unpowered, selling, undeploying, damage stages, dying | new |
| `view_projectiles.gd` | `ViewProjectiles` | Mirror of `world.projectiles` for missiles/bombs/rockets (meshes + trails); analytic arcs | new |
| `view_event_router.gd` | `ViewEventRouter` | Single per-frame pass over the MASTER event batch (stride 10, sequential, in emission order): decodes records, dispatches to lifecycle, entity state, FX router, overlays; asserts at start-up that every consumed `SimEvent` constant exists | new |
| `view_picker.gd` | `ViewPicker` | Ray/box picking against pick volumes via spatial hash + structure grid (no physics) | new |
| `view_consts.gd` | `ViewConsts` | Unit conversions, angle helpers, enums (§4.1-4.3) | new |
| `view_layers.gd` | `ViewLayers` | Render priorities, visual-layer cull bits, y-offsets for overlays | new |
| `view_globals.gd` | `ViewGlobals` | Registers/updates every global shader parameter (§4.6) before any material exists | `view_unit_material.gd`, `view_fog_of_war.gd`, `view_atmosphere.gd` |
| `view_team_colors.gd` | `ViewTeamColors` | The 12 lobby colours (+4 derived), colour-blind palette modes, shape-pip ids, contrast helpers | `proto_main.gd` TEAMS |
| `view_quality.gd` | `ViewQuality` | Preset tables, renderer capability clamp, application to viewport/env/shadows/FX | new |
| `view_quality_auto.gd` | `ViewQualityAuto` | Frame-time window sampler, hysteresis, step-down/up | new |
| `view_instance_buffer.gd` | `ViewInstanceBuffer` | Bulk-written MultiMesh (stride 20: 12 xform + 4 colour + 4 custom) used by every overlay batch | `view_blob_shadows.gd` |
| `view_float_text.gd` | `ViewFloatText` | Pool of 24 `Label3D` for "+$" and damage numbers | new |
| `backend/view_unit_backend.gd` | `ViewUnitBackend` | Abstract: `add/remove/set_transform/push_*`; selected by capability | new |
| `backend/view_node_backend.gd` | `ViewNodeBackend` | One `ViewModelRig` (MeshInstance3D + instance uniforms) per entity; Forward+ default | `view_model_rig.gd` |
| `backend/view_batch_backend.gd` | `ViewBatchBackend` | MultiMesh per (model, team material), INSTANCE_CUSTOM path; Compatibility/Mobile default | `proto_main.gd` bench `mm` path |
| `camera/view_camera.gd` | `ViewCamera` | RTS rig, smoothing, clamp, shake, cinematic | `view_rts_camera.gd` |
| `terrain/view_terrain_source.gd` | `ViewTerrainSource` | Adapter: `MapData` + `MapImages` -> view arrays (corner heights, terrain ids, flags, deco, sea level, deposit cells); the ONLY file that touches `MapData` | `map_terrain_data.gd` |
| `terrain/view_terrain_bake.gd` | `ViewTerrainBake` | Threaded height/normal/cavity/chunk baking (static funcs) | `view_terrain.gd` |
| `terrain/view_terrain_layers.gd` | `ViewTerrainLayers` | Control textures, road raster, water-depth raster | `view_terrain.gd` |
| `terrain/view_terrain.gd` | `ViewTerrain` | Chunk nodes, material, `height_at`, `normal_at`, `raycast`, shadows toggle | `view_terrain.gd` |
| `terrain/view_detail_textures.gd` | `ViewDetailTextures` | Two 256² noise/normal atlases (boot, ~60 ms) | `view_detail_textures.gd` |
| `terrain/view_water.gd` | `ViewWater` | 4-triangle sea plane + water shader params | `view_water.gd` |
| `terrain/view_atmosphere.gd` | `ViewAtmosphere` | Sky, sun, ambient, SSAO/glow/fog, grade LUT, `fit_shadows` | `view_atmosphere.gd` |
| `terrain/view_mood_def.gd` | `ViewMoodDef` | Mood data class + loader from `moods.json` | `view_mood_def.gd` |
| `terrain/view_fog_of_war.gd` | `ViewFogOfWar` | Byte-grid -> two ping-pong R8 textures, cross-fade, globals | `view_fog_of_war.gd` |
| `terrain/view_decor.gd` | `ViewDecor` | Trees/rocks/crystals/scrap MultiMesh groups, deposit visuals | `view_decor.gd` |
| `terrain/view_decor_meshes.gd` | `ViewDecorMeshes` | Procedural low-poly decor meshes | `view_decor_meshes.gd` |
| `terrain/view_scorch_layer.gd` | `ViewScorchLayer` | CPU-painted 1024² overlay: scorch, craters, tread marks | `view_scorch_layer.gd` |
| `terrain/view_blob_shadows.gd` | `ViewBlobShadows` | Low-preset contact/blob shadows (one MultiMesh) | `view_blob_shadows.gd` |
| `terrain/view_minimap_source.gd` | `ViewMinimapSource` | Baked minimap ImageTexture, fog material, world<->minimap mapping | `view_minimap.gd` (variant B) |
| `model/view_mesh_builder.gd` | `ViewMeshBuilder` | Primitive builder (box, prism, extrude, lathe, wheel, track, pocket, greebles, mirror, LOD tiers) | `view_mesh_builder.gd` (models) |
| `model/view_expr.gd` | `ViewExpr` | Expression compiler (string -> RPN) + evaluator shared by model and fx recipes | new |
| `model/view_recipe.gd` | `ViewRecipe` | Parsed recipe/archetype/style data classes (RefCounted) | new |
| `model/view_recipe_book.gd` | `ViewRecipeBook` | Loads/validates all recipe JSON, index, archetypes, styles; lookup + merge | new |
| `model/view_recipe_interpreter.gd` | `ViewRecipeInterpreter` | Executes op lists on a `ViewMeshBuilder` (let/for/if/switch/mirror/push/part/tier/call) | new |
| `model/view_recipe_macros.gd` | `ViewRecipeMacros` | Native composite builders: vehicle/infantry/air kit (§5.8.5) | `view_sample_models.gd` helpers |
| `model/view_macros_structures.gd` | `ViewMacrosStructures` | Native composite builders: buildings, ships, superweapons | `view_sample_models.gd` |
| `model/view_model.gd` | `ViewModel` | `{key, mesh, info}` product of a build | new |
| `model/view_model_info.gd` | `ViewModelInfo` | Metadata: aabb, radius, height, sockets (inner class `ViewSocket`), part mask, member count, tri counts | new |
| `model/view_model_builder.gd` | `ViewModelBuilder` | Cache + sync/async (WorkerThreadPool) builds + placeholder + optional disk cache | `view_sample_models.gd` |
| `model/view_model_rig.gd` | `ViewModelRig` | MeshInstance3D + `push_anim/aux/state/mounts` (node backend handle) | `view_model_rig.gd` |
| `model/view_materials.gd` | `ViewMaterials` | Unit materials per look (4 compile variants: node, batch, per-material-uniform, ghost), scaffold material, shared overlay materials | `view_unit_material.gd` |
| `model/view_icon_bake.gd` | `ViewIconBake` | SubViewport baker, disk cache, async queue, placeholders | `proto_main.gd` `_mode_icons` |
| `fx/fx_manager.gd` | `FxManager` | Pools, clock, budgets, culling, emitters/trackers/stampers, lights, stats | `fx_manager.gd` |
| `fx/fx_batch.gd` | `FxBatch` | MultiMesh ring buffer per look | `fx_batch.gd` |
| `fx/fx_assets.gd` | `FxAssets` | Procedural noise atlas, HDR ramp, palette; meshes; materials | `fx_assets.gd` |
| `fx/fx_recipe_book.gd` | `FxRecipeBook` | Loads/compiles `fx.json` into `FxDef` op lists (inner class); executes them (`run(def, a, b, s)`) | new (replaces `fx_recipes.gd`) |
| `fx/fx_catalog.gd` | `FxCatalog` | fx-id resolution: explicit `pres_fx` string -> effect, else defaults by weapon archetype / projectile kind / warhead / death kind | new |
| `fx/fx_event_router.gd` | `FxEventRouter` | Pure mapping `SimEvent -> FxManager calls`, visibility gate, shake amounts | new |
| `overlay/view_selection.gd` | `ViewSelection` | Selection rings/brackets, hover highlight, aura rings | new |
| `overlay/view_health_bars.gd` | `ViewHealthBars` | Screen-constant-size bars (one MultiMesh) | new |
| `overlay/view_status_marks.gd` | `ViewStatusMarks` | Status icons/rings (buff, mark, EMP, suppressed, cloaked, decoy-identified) | new |
| `overlay/view_lines.gd` | `ViewLines` | Rally lines, waypoint paths, order lines (pixel-width ribbons) | new |
| `overlay/view_placement_ghost.gd` | `ViewPlacementGhost` | Ghost model + per-cell validity grid + build-radius overlay | new |
| `overlay/view_placement_state.gd` | `ViewPlacementState` | Validator-neutral record the UI fills from `SimPlacement.validate` (economy) or `MapBuildRules.check` (map): origin, size, rotation, per-cell `CF_*` codes | new |
| `overlay/view_range_rings.gd` | `ViewRangeRings` | Max/min range circles for selected or placed defenses | new |
| `overlay/view_warnings.gd` | `ViewWarnings` | Strategic warning zones (circle, capsule, rods) from `SW_WARNING`/`POWER_WARNING` events, gated by the "affected" rule (§5.9.5) | new |
| `overlay/view_zones.gd` | `ViewZones` | Visuals of ZONE entities (smoke, repair, intercept dome, debris, reveal) | new |
| `overlay/view_ghosts.gd` | `ViewGhosts` | Remembered enemy structures (`world.fog.ghosts(pid)` records) | new |
| `overlay/view_debug_overlay.gd` | `ViewDebugOverlay` | `AiDebugFrame` circles/lines/heat + view stats (F-keys) | new |

### 2.2 Shaders (`game/assets/shaders/`; lint L001 checks `#include` paths)

| File | Purpose | Lift from |
|---|---|---|
| `unit.gdshader` | Units, structures, wrecks, ghosts. Compile variants by `#define`: default (instance uniforms), `MM` (INSTANCE_CUSTOM), `MATU` (plain uniforms, per-material), `GHOST` (blend_mix placement ghost) | `models/shaders/unit.gdshader` |
| `terrain.gdshader` (+`TERRAIN_LOW`) | 6-layer splat, triplanar rock, roads, wet sand, caustics, scorch, cloud shadows, fog | `terrain/shaders/terrain.gdshader` |
| `water.gdshader` (+`WATER_LOW`) | Sea/lake/river | `terrain/shaders/water.gdshader` |
| `decor.gdshader` | Wind-swayed MultiMesh decor | `terrain/shaders/decor.gdshader` |
| `blob_shadow.gdshader` | Low-preset contact shadow | `terrain/shaders/blob_shadow.gdshader` |
| `minimap_fog.gdshader` | canvas_item fog applied to the minimap texture | same |
| `ring.gdshader` | Selection/range/build-radius/warning/aura ring family (modes §4.7) | new |
| `health_bar.gdshader` | Screen-constant-size bars (POSITION written in vertex) with a per-player shape pip (colour-blind cue, §5.12) | new |
| `line.gdshader` | Pixel-width ribbon lines (rally, waypoints, AI debug) | new |
| `ghost_grid.gdshader` | Placement footprint cell grid | new |
| `scaffold.gdshader` | Construction scaffold cage | new |
| `fx_sprites/ribbon/ring/dome/column/shimmer.gdshader` | VFX (Forward+/Mobile/Compat compile verified) | `vfx/shaders/*` |
| includes: `fog_of_war.gdshaderinc`, `atmosphere.gdshaderinc`, `fx_common.gdshaderinc`, `view_common.gdshaderinc` (rot mats, hashes, noise, `to_lin`) | shared code | terrain/vfx includes |

### 2.3 Data, tests, tools (owned)

* Data: `game/data/recipes/{index,styles,moods,fx,quality,assignments}.json`, `archetypes/*.json`, `<recipe id>.json` (≈215 files); no README is created there (this spec is the reference).
* Tests: `game/tests/view/test_*.gd` (§10), fixtures/scenes `game/tests/view/scenes/*.tscn` + scripts for `tools/gd shot`.
* Tools: `tools/py/validate_recipes.py`, `tools/py/gen_recipe_index.py`, `tools/py/gen_recipe_stubs.py`, optional `tools/py/gen_view_textures.py` (§11 VIEW-T9).

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

### 3.0 Frame order, tick order and ownership

ASSUMPTION(app): the app calls the view exactly once per rendered frame (request 30), **after** `NetSession.poll()` (net.md 3.0; the session steps the world inside `poll()`), **after** it drained the frame's event batch, and **before** the UI update. The view never runs in `_physics_process` and never runs the sim.

```
AppMain._process(delta):
    var ticks: int = session.poll()                                   # net: 0..8 sim steps this frame
    var world: SimWorld = session.world()                             # read-only for everybody but the net adapter
    var batch: PackedInt32Array = world.events.take()                 # sim_core 5.7: ONE take() per rendered frame, O(1); the SAME array goes to view, audio, ui and the host AI
    var alpha: float = session.tick_alpha()                           # [0,1) fraction of the current 50 ms tick   (view-only float)
    view.frame(delta, alpha, batch)                                   # THE ONLY per-frame view entry point (sequence below)
    audio.frame(delta, batch); ui.frame(delta, batch)                 # read the same batch; nobody keeps it across frames
```

`ViewWorld.frame(dt, alpha, events)` sequence (each step has a hard cost bound, §9):

| # | Step | Notes |
|--:|---|---|
| 1 | `ViewGlobals.tick(dt)` | advances `view_time` (ambient shader time; frozen in screenshot mode); `fx_time` is advanced later by `fx.advance` |
| 2 | `camera.advance(dt)` | smoothing, clamp, shake, cinematic; then `vis_rect = camera.visible_ground_rect()` (4 rays) |
| 3 | pause and pacing | `fx.paused = sim.paused != 0`; `fx.time_scale = clamp(sim.rules.speed_pct / 100.0, 0.25, 4.0)` (animation clocks that integrate `dt` use `dt * time_scale`, 0 while paused); while `sim.paused != 0` or the match has ended, `alpha` is forced to 1.0 so entities rest exactly on the last simulated state |
| 4 | `router.process(events)` | ONE sequential pass over the batch in emission order (§6.2): creates/disposes `ViewEntity`s, queues FX, sets flash/recoil/deploy/phase timers, feeds overlays |
| 5 | every 30th frame: `_reconcile()` | id-set diff `sim.entities` vs `_by_id` (repairs missed events, first frame, replay seek) |
| 6 | `if sim.tick != _last_tick: _sample_tick()` | two-sample shift (below): `prev := cur; cur := read(world)` for every entity that is in view or animated |
| 7 | `fog.sync(sim.fog, fog_pid)`; `fog.advance(dt)`; `_drain_deposits()` | uploads only when `fog_version` changed (<= 10 Hz); deposit cells changed since last frame patch decor and minimap |
| 8 | entity loop (`_active`) | visibility (cached per `fog_version`), interpolation, animation, uniform pushes (§5.2); off-screen entities update at 5 Hz |
| 9 | `projectiles.update(alpha)`, structure phase timers | <= 64 mirrored projectiles |
| 10 | overlays: `selection`, `health_bars`, `status_marks`, `lines`, `warnings`, `zones`, `remembered`, `ghost` | each <= 0.1 ms typical |
| 11 | `fx.advance(dt)` | clock, token buckets, scheduled sub-effects, emitters/trackers/stampers, lights |
| 12 | `blob_shadows.update()` | Low preset only, every 2nd frame |
| 13 | `quality_auto.sample(dt)` | 2 µs |

**Two-sample buffer (the kernel stores no "previous" fields).** `SimEntity` has `x, y, facing` only; interpolation needs the state one tick earlier, so every `ViewEntity` keeps `x_prev/x_cur, y_prev/y_cur, facing_prev/facing_cur` and per-mount turret angles (§4.5). Two modes, identical results whenever a frame executes at most one tick (the 60 FPS / 20 TPS common case):

* **Frame-granular (default, needs nothing from net):** step 6 shifts `cur` into `prev` and reads the new `cur` once per rendered frame in which `sim.tick` advanced. A frame that executed k > 1 ticks (catch-up after a hitch, at most 8) interpolates over a k-tick span, i.e. moves up to k times faster for one tick interval and never jumps backwards (worked example in §5.1); the teleport guard of §5.1 cannot trigger from legal movement because 8 ticks of the fastest aircraft (12 cells/s) are 4.8 cells < 6 cells.
* **Exact (optional hook, sim_core 3.10 / R16):** if the net adapter calls `view.capture_prev(world)` before every `world.step()`, `prev` is read from the world immediately before the last step and step 6 only reads `cur`. `ViewWorld` detects the hook by a counter (`_prev_calls_this_frame > 0`) and then skips the shift. Cost of one hook call: about 0.5 µs per entity that is moving, airborne or armed (idle entities keep `prev == cur` and are skipped; at most ~600 of 1 200 qualify), so <= 0.3 ms per step.

**Sim read surface used per frame** (all read-only; names of `sim_core.md` 3.4 unless marked; `ASSUMPTION` items are listed in section 13):

| API | Used for | Calls per frame | Cost |
|---|---|--:|---|
| `sim.tick`, `sim.paused`, `sim.rules.speed_pct`, `session.tick_alpha()` | interpolation, pause, pacing | 4 | ~0 |
| `sim.entity(id) -> SimEntity` (null when never allocated or removed; dead-but-not-removed entities are returned) | entity loop | N visible + N/12 off-screen | 0.3 µs |
| `SimEntity` fields `id, kind, def_idx, owner, x, y, facing, layer, hp, max_hp, flags, holder, born, expires, t_hit, t_fire, t_disabled, t_shutdown, t_suppressed, orders` and the `SimFlags.F_*` bits of sim_core 4.3 | placement, samples, states | <= 10 reads per sampled entity | ~1 µs |
| `ViewSimReader.*` (ASSUMPTION(combat, economy, abilities): `e.combat` mount angles, `e.eco` collector fill / rally / capture progress, `e.zone` charges, `world.combat` range queries) | turrets, cargo bins, rally lines, dome brightness, range rings | <= 1 per animated part | 0.2 µs |
| `sim.entity_visible(pid, e)`, `sim.cell_visible(pid, cx, cy)`, `sim.fog.fog_bytes(pid)`, `sim.fog.fog_version(pid)`, `sim.fog.ghosts(pid)` (request 9) | visibility, fog texture, remembered structures | N (cached per `fog_version`) + 3 | 0.4 µs each; upload only on version change |
| `sim.projectiles` SoA arrays (ASSUMPTION(combat), combat.md 4.4) | missile / rocket / torpedo mirrors | <= 64 slots by serial (no full-pool scan) | 5 µs per mirrored projectile |
| `sim.query_radius(x, y, r, out, need, avoid)` | picking candidates, warning "affected" test | 1-3 per pick, 10 Hz per active warning | 4-15 µs |
| `sim.map` (`MapData`): `occ` (structure id per cell), `deposit`, `drain_deposit_dirty(out)` | structure picking grid, deposit visuals | 1-3 | O(1) / O(changed) |
| `sim.players[pid]`: `color, roster_idx, faction_idx, team, eliminated` | team colours, styles | on spawn / owner change | ~0 |
| `sim.rules`: `fog_mode, shared_vision, speed_pct, wrecks` | fog mode, pacing | 1 | ~0 |
| `sim.data` (`GameData`) through `ViewDefAdapter` only | defs, footprints, weapon archetypes | on spawn / event | 0.3 µs (array index) |
| the event batch | router | 1 pass | 3 µs per event |

The view never calls `combat.range_max_eff` or other computing queries per frame; range rings call them only when shown (<= 12 rings, on selection change). It never stores an `Array` returned by `units_of()`/`units`/`entities` across frames (sim_core R16: lists are compacted every tick); it iterates `sim.entities` by index inside `frame()` only.

Ownership: `ViewWorld` owns every child node and every `ViewEntity`; `ViewModelBuilder` owns meshes (shared by reference, never mutated after build); `ViewMaterials` owns materials; `ViewTerrain` owns chunk meshes and the height array (`PackedFloat32Array hv`); `FxManager` owns all batch nodes; overlays own their `ViewInstanceBuffer`s. Nothing in the view holds a strong reference *from* the sim to the view (no callbacks registered in the sim).

### 3.1 `ViewWorld` (root)

```gdscript
class_name ViewWorld extends Node3D

signal build_progress(fraction: float, stage: String)   # 0..1 over all stages; stage is a short label for the loading screen
signal build_finished()

var sim: SimWorld                     # read-only reference; set by build_async
var local_pid: int = 0                # whose fog / ownership colouring applies; -1 = observer (sees everything)
var observer: bool = false
var quality: ViewQuality
var defs: ViewDefAdapter              # the only reader of GameData in the view (built in build_async from sim.data)
# subsystems (all created in _init, configured in build_async; UI may call their public API)
var camera: ViewCamera;            var terrain: ViewTerrain;        var water: ViewWater
var atmosphere: ViewAtmosphere;    var fog: ViewFogOfWar;           var decor: ViewDecor
var scorch: ViewScorchLayer;       var blob_shadows: ViewBlobShadows
var models: ViewModelBuilder;      var materials: ViewMaterials;    var icons: ViewIconBake
var fx: FxManager;                 var projectiles: ViewProjectiles
var selection: ViewSelection;      var health_bars: ViewHealthBars; var status_marks: ViewStatusMarks
var lines: ViewLines;              var ghost: ViewPlacementGhost;   var range_rings: ViewRangeRings
var warnings: ViewWarnings;        var zones: ViewZones;            var remembered: ViewGhosts
var float_text: ViewFloatText;     var minimap: ViewMinimapSource;  var debug: ViewDebugOverlay

static func create(q: ViewQuality) -> ViewWorld                    # registers globals FIRST (ViewGlobals.ensure), then builds the node tree
func build_async(w: SimWorld, local_player: int, opts: ViewBuildOptions = null) -> void   # coroutine: `await view.build_async(...)`; yields at most every 8 ms
func teardown() -> void                                            # frees per-match nodes/resources; keeps compiled shaders and model cache
func frame(dt: float, alpha: float, events: PackedInt32Array) -> void   # §3.0; `events` = world.events.take() of this rendered frame (stride 10, read-only, not retained)
func capture_prev(w: SimWorld) -> void                             # OPTIONAL pre-step hook named by sim_core 3.10; makes interpolation exact when a frame runs several ticks (§3.0)
func set_local_player(pid: int, as_observer: bool = false) -> void # switches fog group, colours; observer uploads an all-visible fog texture
func set_game_speed(speed: float, paused: bool) -> void            # manual override for tools and tests; in a match `frame` derives both from sim.paused and sim.rules.speed_pct
func apply_quality(q: ViewQuality) -> void                         # live change; terrain re-bake only if subdiv changed (~200 ms, threaded)

# ---- queries (UI / audio / AI debug); all O(1) unless stated
func entity_view(id: int) -> ViewEntity                            # null when unknown
func entity_world_pos(id: int, with_height: bool = false) -> Vector3   # interpolated; with_height adds ViewModelInfo.height (floating labels)
func entity_socket(id: int, socket: StringName) -> Vector3         # world position of a model socket incl. turret yaw/barrel recoil; falls back to entity_world_pos + 1.2 m
func entity_screen_rect(id: int) -> Rect2                          # projected pick-volume bounds in viewport px (box select, tooltips); O(8 corners)
func pick(screen_pos: Vector2, filter: int = ViewPicker.PICK_ANY) -> int        # entity id or -1; §5.11
func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int           # fills `out` (cleared), returns count; hidden-by-fog excluded
func pick_ground(screen_pos: Vector2) -> Vector3                   # Vector3.INF on miss
func sim_to_world(x: int, y: int) -> Vector3                       # includes terrain height
func world_to_sim(p: Vector3) -> Vector2i                          # roundi(p * 1024/3), clamped to the map; UI turns it into the ints of a SimCommand (x, y in sub-cell units)
func stats() -> Dictionary                                         # entities, visible, draw calls, prims, fx stats, ms per subsystem (debug overlay / tests)
func rebuild_models() -> void                                      # debug builds only: re-read recipes, clear the model cache, rebuild the mesh of every live entity (hot reload)
```

```gdscript
class_name ViewBuildOptions extends RefCounted
var mood: StringName = &""                 # "" = derive from MapData.biome and family (§5.6)
var night_allowed: bool = true             # false: an urban map with biome 0 uses temperate_day instead of urban_night
var deposit_source: int = 0                # 0 = MapData per-cell deposits (terrain_movement 3.3), 1 = DEPOSIT entities (sim_core 4.12); see risk R24
var terrain_subdiv: int = -1               # -1 = from quality
var screenshot_mode: bool = false          # freezes view_time/fx_time to 0 unless set, disables edge scroll, fixed RNG seeds (QA-XR-28: frozen animation clocks and seeded VFX RNG)
var rng_seed: int = 1                      # FX / decor jitter seed in screenshot_mode
var prewarm_scope: int = 1                 # 0 none, 1 = rosters present in the match, 2 = all 32 rosters (contact-sheet tests)
var bake_icons: bool = true                # bake/load icons for the local roster during load
var unit_backend: int = -1                 # -1 = auto (ViewQuality caps), 0 nodes, 1 batch
```

`build_async` stages (progress weights; slices of ≤ 8 ms, `await get_tree().process_frame` between slices; the app keeps `session.poll()` running): 0.02 globals + materials + `ViewDefAdapter.setup(sim.data)` · 0.20 terrain (source adapter, threaded bake, textures) · 0.05 water + atmosphere + detail atlases · 0.10 decor · 0.03 minimap bake · 0.30 models (`request()` for every (recipe, style) the rosters in `sim.players` can produce, then `pump(4 ms)` per frame) · 0.05 FX setup + prewarm · 0.15 material prewarm (hidden instance per style for 3 frames) · 0.10 icons for the local roster · finish: `camera.configure`, `camera.snap_to(local start cell, yaw 0, zoom 0.35)`, `fog.setup`, signals connected (`fx.camera_shake -> camera.add_shake`), `bind_world` mirrors the entities that already exist (initial HQ / MCVs / neutral structures / deposits; the tick-0 `SPAWNED` events of the first batch are then ignored as duplicates), `build_finished`.

### 3.2 Entity records, sim seams and the rig

```gdscript
class_name ViewEntity extends RefCounted     # fields: §4.5. Subclasses ViewUnit, ViewStructure add state machines.
func update(v: ViewWorld, e: SimEntity, dt: float, alpha: float, in_view: bool) -> void   # §5.2; never allocates
func on_fire(mount: int, barrel: int) -> void          # recoil kick (set recoil=1), muzzle flash light hint
func on_hit(hp_lost: int, dmg_flags: int) -> void      # flash=1 unless the kill-blow bit (1) is set, health-bar mark; hp itself is re-read from the entity at the next sample
func on_state(st: int, value: int, ticks: int) -> void # SimEvent.ST_* (deploy / pack ease over `ticks`, cloak, EMP, shutdown, suppressed, landed / takeoff, selling, powered, mode-switch, repairing)
func dispose(v: ViewWorld) -> void                     # returns rig/slot to the backend
```

```gdscript
class_name ViewSimReader extends RefCounted     # static, null-safe, allocation-free; the ONLY view file that reads component internals of other domains (§3.0)
static func turret_rel_bat(e: SimEntity, mount: int) -> int            # combat mnt[mount*MS + M_ANGLE]: bat relative to the hull; -1 when the entity has no such mount
static func mount_count(e: SimEntity) -> int                            # 0..4 (combat n_mounts)
static func collector_fill_permille(e: SimEntity) -> int                # economy cargo * 1000 / capacity; -1 when not a collector
static func rally_of(e: SimEntity, out: PackedInt32Array) -> bool       # out = [x, y, target_id]; false when the structure has no rally point
static func capture_progress_permille(e: SimEntity) -> int              # -1 when none; only used while request 8 is not delivered
static func weapon_ranges(w: SimWorld, e: SimEntity, out: PackedInt32Array) -> int   # [max0, min0, max1, min1, ...] sim units via world.combat range queries; returns the mount count; on selection change only
static func zone_charges(e: SimEntity) -> int                           # abilities zone component charges; -1 when unreadable

class_name ViewDef extends RefCounted           # plain record built by ViewDefAdapter
var kind: int; var def_idx: int; var id: String; var faction_code: String    # SimEntity.Kind, sim index, bible id, "napc" ("" = shared)
var recipe_id: StringName; var icon_id: StringName; var scale_bp: int = 10000  # pres_recipe / pres_icon (default = id), pres_scale_bp
var unit_class: int; var move_class: int; var size_class: int; var layer: int; var radius_m: float
var fp_w: int; var fp_h: int; var rotatable: bool                         # structures: footprint cells of orientation 0
var needs_power: bool; var is_hq: bool; var is_defense: bool
var warch: PackedInt32Array                                              # DefWeaponArch index per mount 0..3, -1 = none
var door_cx: float; var door_cz: float; var exit_dir: int; var dock_cx: float; var dock_cz: float; var dock_dir: int; var pads: PackedFloat32Array   # anchors in metres from the footprint centre (§7.3); pads = x, z pairs
var zone_kind: int; var zone_shape: int; var zone_radius_m: float; var zone_length_m: float; var zone_width_m: float; var visible_to_enemy: bool   # zones only

class_name ViewDefAdapter extends RefCounted    # the ONLY view file that reads Def* fields
func setup(data: GameData) -> void                                       # detects the index-space variant once (per-kind vs one dense space, risk R25); builds nothing eagerly
func def_for(kind: int, def_idx: int) -> ViewDef                          # cached; unknown -> placeholder ViewDef + one Log.warn
func weapon_arch(weapon_def_idx: int) -> int                              # DefWeaponArch index 0..26 or -1 (request 4); one Log.warn per unknown index
func roster_id(roster_idx: int) -> String                                 # "roster.napc.canada"
func power_key(power_idx: int) -> StringName; func superweapon_key(sw_idx: int) -> StringName   # last id segment, e.g. &"atlas_kinetic_array" (fx.json keys)

class_name ViewEventRouter extends RefCounted
func setup(v: ViewWorld) -> void                                          # builds the handler table and runs _validate_codes()
func process(events: PackedInt32Array) -> void                            # one sequential pass, o += 10; also calls FxEventRouter.on_event(events, o)
func _validate_codes() -> PackedStringArray                               # consumed SimEvent constant names that do not exist (empty = all present)
```

```gdscript
class_name ViewUnitBackend extends RefCounted   # abstract; ViewNodeBackend / ViewBatchBackend implement
func setup(parent: Node3D, mats: ViewMaterials, q: ViewQuality) -> void
func add(ve: ViewEntity, model: ViewModel, style_id: StringName, team: Color, team_index: int) -> void   # sets ve.rig/ve.slot
func remove(ve: ViewEntity) -> void
func set_visible(ve: ViewEntity, vis: bool) -> void
func set_xform(ve: ViewEntity, xf: Transform3D) -> void
func push_anim(ve: ViewEntity) -> void      # u_anim: (sink_depth_m, move, roll, turret_yaw)
func push_aux(ve: ViewEntity) -> void       # u_aux : (recoil, deploy_or_activity, spin_angle, elevation)
func push_state(ve: ViewEntity) -> void     # u_state: (damage, selected, flags, flash)
func push_mounts(ve: ViewEntity) -> void    # u_mnt1..3 (only entities with extra mounts)
func set_team(ve: ViewEntity, team: Color, team_index: int) -> void
func set_shadow(ve: ViewEntity, on: bool) -> void
func flush() -> void                        # batch backend writes MultiMesh buffers here; node backend no-op
func stats() -> Dictionary
```
`ViewNodeBackend` keeps a free-list of rigs per model key (max 64 each) so death / production churn reuses nodes and instance-uniform slots instead of allocating; `remove()` hides and parks, `add()` pops. `ViewBatchBackend` swaps the removed instance with the last one in its MultiMesh.

```gdscript
class_name ViewModelRig extends MeshInstance3D      # node-backend handle; wraps set_instance_shader_parameter
const P_TEAM: StringName = &"u_team"; const P_ANIM: StringName = &"u_anim"; const P_AUX: StringName = &"u_aux"
const P_STATE: StringName = &"u_state"; const P_MNT1: StringName = &"u_mnt1"  # ... P_MNT2/3
func setup(m: Mesh, mat: Material, team: Color) -> ViewModelRig
# values live in ViewEntity; the rig only forwards them. Writes are skipped when the packed Color equals the cached last write.
```

### 3.3 `ViewCamera`

```gdscript
class_name ViewCamera extends Node3D
signal view_changed(height: float, pitch_deg: float, yaw_deg: float)   # when |Δheight| > 0.25 m or yaw/pitch changed > 0.1°
signal cinematic_changed(active: bool)                                   # UI hides HUD / shows letterbox

@export var height_min: float = 34.0;  @export var height_max: float = 84.0       # m above focus (setting "wide view": 110)
@export var pitch_near_deg: float = 46.0; @export var pitch_far_deg: float = 61.0
@export var fov_deg: float = 38.0                                                  # vertical (KEEP_HEIGHT)
@export var pan_speed: float = 1.1          # m/s per metre of camera distance (constant screen speed)
@export var edge_scroll_enabled: bool = true; @export var edge_margin_px: int = 10
@export var pan_smooth: float = 11.0; @export var zoom_smooth: float = 9.0; @export var rot_smooth: float = 12.0   # 1/s, frame-rate independent
@export var zoom_step: float = 0.08; @export var key_rotate_deg_per_s: float = 100.0; @export var orbit_deg_per_px: float = 0.22
@export var clamp_margin_m: float = 14.0
@export var auto_input: bool = true         # false: caller drives pan_screen/zoom_by/rotate_yaw itself (tests, replays)
var camera: Camera3D                        # child, near/far managed here
var height_func: Callable                   # (x: float, z: float) -> float   = ViewTerrain.height_at
var ground_pick_func: Callable              # (origin: Vector3, dir: Vector3) -> Vector3 (INF on miss) = ViewTerrain.raycast
var view_margin_px: Vector4 = Vector4.ZERO  # (left, top, right, bottom) HUD-occluded pixels; focus_on() centres in the free area

static func ensure_input_actions() -> void  # registers cam_* actions (below) if absent; never overwrites user bindings
func configure(map_rect_m: Rect2, terrain_ref: ViewTerrain) -> void
func snap_to(focus_xz: Vector2, yaw_deg: float, zoom01: float, pitch_bias_deg: float = 0.0) -> void
func set_pose(cell_x: float, cell_y: float, yaw_deg: float, pitch_deg: float, zoom01: float) -> void   # QA-XR-28 absolute pose in map cells; pitch_deg is converted to the tilt bias for this zoom (clamped 22..82); instant
func focus_on(p: Vector3, instant: bool = false) -> void
func focus_on_sim(x: int, y: int, instant: bool = false) -> void
func pan_world(delta_xz: Vector2) -> void
func pan_screen(dir: Vector2, dt: float) -> void            # dir.y = -1 moves toward the top of the screen
func rotate_yaw(deg: float) -> void; func tilt(deg: float) -> void
func zoom_by(steps: float, cursor: Vector2 = Vector2(-1.0, -1.0)) -> void   # >0 zooms in; cursor >= 0 drifts focus toward the ground point under it
func reset_orientation() -> void
func advance(dt: float) -> void                              # called by ViewWorld.frame (auto_input reads InputMap in here)
func add_shake(amount: float) -> void                        # trauma in [0,1]; already distance-attenuated by the caller
func cinematic_play(keys: Array[Dictionary], loop: bool = false) -> void   # key: {t, focus:Vector3, yaw_deg, height, pitch_deg, fov_deg?, ease?}
func cinematic_stop() -> void
func is_cinematic() -> bool
func screen_to_ground(p: Vector2) -> Vector3
func visible_ground_rect() -> Rect2                          # AABB (m, xz) of the frustum's ground footprint
func current_focus() -> Vector3; func current_height() -> float; func current_pitch_deg() -> float; func current_yaw_deg() -> float
func listener_transform() -> Transform3D                     # audio listener: camera transform at the focus point height
static func edge_scroll_dir(mouse: Vector2, view_size: Vector2, margin: int) -> Vector2
```

Input actions (registered at runtime; UI may rebind): `cam_pan_left/right/up/down` (Left/Right/Up/Down arrows; **WASD only when the setting `camera/wasd_pan` is on**, because A/S/G/D are command hotkeys), `cam_rotate_left/right` (Q/E), `cam_zoom_in/out` (wheel, KP+/KP-, PageUp/PageDown), `cam_orbit` (middle mouse: yaw by dx, tilt by dy), `cam_reset` (Home). Everything else (centre on base, jump to alert) is UI calling `focus_on`.

### 3.4 World rendering

```gdscript
class_name ViewTerrainSource extends RefCounted            # the only class that reads MapData (fields: terrain_movement.md 3.3 / 4.1 / 5.14)
const HEIGHT_M_PER_LEVEL: float = 0.05                     # view-owned constant (terrain_movement 5.14): height levels 0..255 = 0..12.75 m
var width: int; var height: int; var seed_value: int; var family: int; var biome: int; var deco_seed: int   # cells; MapData.w, h, seed, family (0 open, 1 urban, 2 coast), biome (0 temperate, 1 desert, 2 arctic, 3 tropical), deco_seed
var corner_m: PackedFloat32Array       # (width+1)*(height+1) lattice-corner heights in metres = MapImages.corner_height(map, cx, cy) * HEIGHT_M_PER_LEVEL
var terrain: PackedByteArray           # width*height terrain ids 0..14 (MapTerrain.T_DEEP_WATER .. T_MOUNTAIN), shared copy-on-write with MapData
var flags: PackedByteArray             # width*height MapData.SF_* bits: SHORE 1, NOBUILD 2, BLOCK 4 (boulder), START 8, RAMP 16
var deco: PackedByteArray              # width*height per-cell hash byte: decor scatter and urban-block building heights
var sea_level_m: float                 # derived: (max height level over DEEP_WATER and SHALLOW cells + 0.5) * HEIGHT_M_PER_LEVEL; -1000.0 when the map has no water
var start_cells: PackedInt32Array      # cell index per MapData.spawns entry (stride 6: slot, cell, facing, orbit, team_hint, reserved), in slot order
var neutrals: PackedInt32Array         # MapData.neutrals (stride 8: kind, cell, w, h, variant, flags, orbit, reserved); kind NK_SCENERY = boulder props, the others are sim entities
var fields: PackedInt32Array           # MapData.fields (stride 10: id, center_cell, radius, cells, total, kind, orbit, hint_cell, ...): deposit discs for the minimap tint
static func from_map(m: MapData) -> ViewTerrainSource
func size_m() -> Vector2
func deposit_fraction(i: int) -> float             # deposit[i] / deposit_max[i]; 0.0 when the cell holds no deposit
func deposit_cells(out: PackedInt32Array) -> int   # cells with deposit_max > 0 (initial decor build)
func drain_deposit_changes(out: PackedInt32Array) -> int   # wraps MapData.drain_deposit_dirty(out): cell indices changed since the previous call (list cleared by MapData; only the view calls it)

class_name ViewTerrain extends Node3D
const CHUNK_CELLS: int = 32
var src: ViewTerrainSource; var material: ShaderMaterial; var water_depth_tex: ImageTexture
var subdiv: int = 2; var step_m: float; var vw: int; var vh: int; var hv: PackedFloat32Array
func build(source: ViewTerrainSource, sub: int, detail: ViewDetailTextures, low_shader: bool, threaded: bool = true) -> void
func height_at(x: float, z: float) -> float                # bilinear on hv; clamps to the map
func normal_at(x: float, z: float) -> Vector3
func is_water_at(x: float, z: float) -> bool               # height_at < water level
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 3000.0) -> Vector3   # no physics; Vector3.INF on miss
func apply_mood(m: ViewMoodDef) -> void
func set_scorch_texture(t: Texture2D) -> void
func set_shadow_casting(on: bool) -> void
func world_size() -> Vector2

class_name ViewAtmosphere extends Node3D
func setup() -> void
func apply_mood(m: ViewMoodDef) -> void                    # sun, sky, ambient, fog, grade LUT, tonemap, atm_* globals
func fit_shadows(height: float, pitch_deg: float, fov_deg: float, aspect: float = 1.78) -> float   # sets max distance + splits; returns the camera near plane to use (0.6*height, min 2 m)
func apply_quality(q: ViewQuality) -> void                 # cascades, atlas size, SSAO/SSIL/glow, PCF
func set_night(k: float) -> void                           # 0..1 -> atm_night global

class_name ViewMoodDef extends RefCounted
static func load_all(path: String = "res://data/recipes/moods.json") -> Dictionary    # id -> ViewMoodDef
static func for_map(biome: int, family: int, moods: Dictionary, night_allowed: bool = true) -> ViewMoodDef   # biome 0 temperate_day, 1 arid_dusk, 2 arctic_day, 3 tropical_day; family 1 (urban) + biome 0 + night_allowed -> urban_night (§5.6)

class_name ViewWater extends Node3D
func build(t: ViewTerrain, tex: ViewDetailTextures, low_shader: bool, extent_m: float = 6000.0) -> void
func apply_mood(m: ViewMoodDef) -> void

class_name ViewFogOfWar extends RefCounted
const STATE_SHROUD: int = 0; const STATE_FOG: int = 1; const STATE_VISIBLE: int = 2
func setup(w: int, h: int, origin_m: Vector2, cell_m: float) -> void
func submit(states: PackedByteArray) -> void               # raw sim bytes (0 shroud, 1 fog, 2 visible); no conversion
func sync(api: SimFogApi, pid: int) -> bool                # uploads api.fog_bytes(pid) iff api.fog_version(pid) changed; true when an upload happened
func advance(dt: float) -> void
func set_mode(fog_mode: int) -> void                       # SimMatchRules.fog_mode: 0 none (all-visible texture), 1 explored-stays-visible (fow_fog_dim = 0), 2 shroud + fog (fow_fog_dim = 1)
func set_enabled(on: bool) -> void                         # false: all-visible texture (observer)
func current_texture() -> ImageTexture

class_name ViewDecor extends Node3D
func build(t: ViewTerrain, src: ViewTerrainSource, q: ViewQuality) -> void
func apply_mood(m: ViewMoodDef) -> void
func apply_deposit_changes(src: ViewTerrainSource, cells: PackedInt32Array, n: int) -> void   # per frame, O(changed): cluster scale = deposit fraction, hidden at 0 (cells from src.drain_deposit_changes)
func regroup(groups_per_side: int) -> void

class_name ViewScorchLayer extends RefCounted
var texture: ImageTexture
func setup(map_size_m: Vector2, res: int = 1024) -> void
func paint(world_xz: Vector2, radius_m: float, kind: int = KIND_SCORCH) -> void    # 2-4 µs; kinds: SCORCH, CRATER, TREAD, RUBBLE_STAIN
func paint_tread(a_xz: Vector2, b_xz: Vector2, width_m: float) -> void
func flush() -> void                                        # <= 2 Hz; 0.65-1.2 ms upload

class_name ViewBlobShadows extends Node3D
func setup(capacity: int) -> void
func update(t: ViewTerrain, positions: PackedVector3Array, radii: PackedFloat32Array, alphas: PackedFloat32Array) -> void

class_name ViewMinimapSource extends RefCounted
var texture: ImageTexture            # one texel per cell, palette+hillshade, baked once per map
func bake(t: ViewTerrainSource, mood: ViewMoodDef) -> ImageTexture          # 21-42 ms at 192² [T]; threadable
func update_deposits(src: ViewTerrainSource, cells: PackedInt32Array, n: int) -> void   # re-tints depleted deposit texels; texture upload at <= 2 Hz
func make_material(local_fog: bool = true) -> ShaderMaterial               # minimap_fog.gdshader; UI assigns it to its TextureRect
func world_to_uv(p: Vector3) -> Vector2; func uv_to_world(uv: Vector2) -> Vector3

class_name ViewGlobals extends RefCounted
static func ensure() -> void          # idempotent; registers every global (§4.6) not already declared in project.godot
static func tick(dt: float) -> void   # view_time
```

### 3.5 Model toolkit

```gdscript
class_name ViewMeshBuilder extends RefCounted     # lifted from the spike; ONE ArrayMesh, ONE surface, thread-safe (no engine singletons used except Geometry2D)
enum Mat { PAINT, METAL, GLASS, RUBBER, EMISSIVE }                       # 0..4
enum Part { STATIC, TURRET, BARREL, WHEEL, TRACK, ROTOR, TAIL_ROTOR, RADAR, LEG_A, LEG_B, ARM_A, ARM_B, BODY_BOB, DOOR, BLINK, DEPLOY,
            DEPLOY_Z, SLIDE_Y, SLIDE_Z, TURRET1, BARREL1, TURRET2, BARREL2, TURRET3, BARREL3 }   # 0..24, §4.2
var paint: Color; var team_mask: float; var mat: int; var ao: float = 1.0; var tier: int = 0; var default_bevel: float = 0.0
var jitter: float = 0.035; var model_scale: float = 1.0; var pack_half: bool = true
func seed_rng(s: int) -> ViewMeshBuilder
func brush(c: Color, m: int = Mat.PAINT, team: float = 0.0) -> ViewMeshBuilder
func set_part(kind: int, pivot_pos: Vector3 = Vector3.ZERO, param: float = 0.0, extra: float = 0.0, trunnion_yz: Vector2 = Vector2.ZERO) -> ViewMeshBuilder
func clear_part() -> ViewMeshBuilder
func member(index: int, count: int) -> ViewMeshBuilder      # NEW: UV2 = (index, count) for subsequent gait parts 8..12 (squad members that fall as hp drops)
func socket(sock_name: StringName, pos: Vector3, dir: Vector3, on_part: int = Part.STATIC, pivot: Vector3 = Vector3.ZERO) -> void   # NEW: named attach point; a moving part reuses the last set_part() record of that kind (pivot, param, extra, trunnion)
func push(t: Transform3D) -> void; func pop() -> void; static func xf(pos: Vector3, euler_deg: Vector3 = Vector3.ZERO) -> Transform3D
func box(center: Vector3, size: Vector3, bevel: float = -1.0) -> void
func tapered_box(center: Vector3, size_bottom: Vector2, size_top: Vector2, height: float, top_shift: Vector2 = Vector2.ZERO, bevel: float = -1.0) -> void
func extrude(profile: PackedVector2Array, x0: float, x1: float, bevel: float = -1.0) -> void      # CONVEX side profile (x forward, y up)
func prism(a: PackedVector3Array, b: PackedVector3Array, bevel: float = -1.0) -> void              # convex n-gon loft
static func ngon(center: Vector3, rx: float, rz: float, n: int, rot_deg: float = 0.0) -> PackedVector3Array
func pocket_box(center: Vector3, size: Vector3, pockets: Array[Rect2], depth: float) -> void
func lathe(from: Vector3, to: Vector3, profile: PackedVector3Array, segments: int = 12, smooth_deg: float = 38.0) -> void   # (radius, along, wear)
func cylinder(from: Vector3, to: Vector3, radius: float, segments: int = 12, bevel: float = 0.0, caps: bool = true) -> void
func frustum(from: Vector3, to: Vector3, r_from: float, r_to: float, segments: int = 12, caps: bool = true) -> void
func dome(base: Vector3, up: Vector3, radius: float, height: float, segments: int = 12, rings: int = 4) -> void
func wheel(center: Vector3, radius: float, width: float, tyre: Color, hub: Color, detail: int = 2, segments: int = 14, animated: bool = true) -> void
func track_belt(x_center: float, width: float, circles: Array[Vector3], thickness: float = 0.06, samples: int = 12) -> void   # circles: (z, y, radius)
func greebles(center: Vector3, normal: Vector3, u_half: Vector3, v_half: Vector3, count: int, size_min: float, size_max: float, h_min: float, h_max: float, cyl_prob: float = 0.25) -> void
func mark() -> PackedInt32Array; func mirror_x(m: PackedInt32Array) -> void
func vertex_count() -> int; func triangle_count() -> int; func tier_triangle_counts() -> Vector3i
func build(mesh_name: String = "") -> ArrayMesh              # LODs, custom_aabb (animated sweep included), meta "rest_aabb"
func info() -> ViewModelInfo                                 # valid after build()
```

```gdscript
class_name ViewExpr extends RefCounted
class Scope extends RefCounted:
    func slot(name: StringName) -> int            # declares or returns the frame slot of a variable
    func has_name(name: StringName) -> bool
static func compile(src: String, scope: Scope, ctx: String = "") -> ViewExpr    # null (+ push_error naming ctx and column) on syntax/unknown-name error
func eval(frame: Array) -> Variant                # frame[slot] holds float | bool | String | Vector3
func eval_float(frame: Array) -> float
func is_const() -> bool

class_name ViewRecipeBook extends RefCounted
func load_all(dir: String = "res://data/recipes") -> bool          # false + errors collected on any schema violation
func has_recipe(id: StringName) -> bool
func recipe(id: StringName) -> ViewRecipe                           # null if unknown (ViewModelBuilder then builds a placeholder + Log.warn once)
func style(style_id: StringName) -> Dictionary                      # fully merged (extends chain resolved)
func style_for_roster(roster_id: String) -> StringName              # "roster.napc.canada" -> &"napc.canada" (falls back to faction, then &"neutral")
func style_for_def(def_id: String, owner_roster_id: String) -> StringName   # unit.napc.* -> that faction's style; *.shared.* -> owner's style
func ids() -> PackedStringArray                                     # sorted; equals index.json
func errors() -> PackedStringArray

class_name ViewRecipeInterpreter extends RefCounted
func run(r: ViewRecipe, style: Dictionary, b: ViewMeshBuilder) -> void     # deterministic; pure function of (recipe, style, seed); thread-safe
# op set: §5.8.3. Errors carry the op path "unit.napc.guardian_tank/ops[14]/for[3]/box" and abort the build (placeholder used).

class_name ViewModelBuilder extends RefCounted
signal model_ready(key: StringName)
func setup(book: ViewRecipeBook, q: ViewQuality) -> void
func get_model(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000) -> ViewModel   # sync, cached; placeholder when the recipe is missing/invalid
func request(recipe_id: StringName, style_id: StringName, scale_bp: int = 10000) -> void         # background build on WorkerThreadPool; finalised by pump()
func pump(budget_ms: float = 4.0) -> int                            # main-thread finalisation (ArrayMesh creation); returns number finished
func pending() -> int
func clear() -> void
static func key_of(recipe_id: StringName, style_id: StringName, scale_bp: int) -> StringName    # "unit.napc.guardian_tank@napc#10000"

class_name ViewModel extends RefCounted
var key: StringName; var mesh: ArrayMesh; var info: ViewModelInfo

class_name ViewModelInfo extends RefCounted
var rest_aabb: AABB; var radius: float; var height: float; var hover: float       # radius = max horizontal extent from origin; hover = default air altitude (m)
var parts_mask: int                    # bit k set = Part kind k present
var members: int = 1                   # squad size (gait parts)
var footprint: Vector2i                # cells (structures)
var death_kind: StringName; var death_ticks: int; var buildup_ticks: int = 30; var spawn_fx: StringName   # recipe meta (§5.9.4, §5.2, §6.2.2); empty / 0 = derive from the def
var sockets: Dictionary                # StringName -> ViewSocket {pos, dir, part, pivot}
var tris: Vector3i; var verts: int; var build_ms: float; var content_hash: int
func socket_world(sock_name: StringName, xf: Transform3D, turret_yaw: float, elev: float, recoil: float) -> Vector3    # replicates the vertex-shader transform of the socket's part

class_name ViewMaterials extends RefCounted
enum Variant { NODE, BATCH, MATERIAL_UNIFORMS, GHOST }
func setup(book: ViewRecipeBook, q: ViewQuality) -> void
func unit_material(style_id: StringName, variant: int = Variant.NODE, team_index: int = 0) -> ShaderMaterial   # cached; BATCH is per (style, team_index)
func scaffold_material() -> ShaderMaterial
func set_quality(q: ViewQuality) -> void        # writes the `quality` uniform on every cached material
func set_night(k: float) -> void

class_name ViewIconBake extends Node
signal icon_ready(key: StringName)
enum Size { ICON, PORTRAIT }                    # 128x96 and 384x288
func setup(models: ViewModelBuilder, mats: ViewMaterials) -> void
func request(recipe_id: StringName, style_id: StringName, size: int = Size.ICON) -> Texture2D   # cached texture or a flat placeholder; queues a bake (max 1 per frame)
func is_ready(recipe_id: StringName, style_id: StringName, size: int = Size.ICON) -> bool
func flush_disk_cache() -> void                 # user://cache/icons/
```

### 3.6 VFX

```gdscript
class_name FxManager extends Node3D
signal camera_shake(amount: float, world_pos: Vector3)      # ViewWorld connects this to ViewCamera.add_shake (140 m linear falloff already applied)
enum Quality { LOW, MEDIUM, HIGH, ULTRA }; enum Kind { POINT, LINE, AREA }; enum Cls { TINY, SMALL, MEDIUM, LARGE, BEAM, SUPER }
var quality: Quality; var paused: bool; var time_scale: float = 1.0; var force: bool   # force bypasses budgets/culling (prewarm, sheets)
var hidden_batches: Dictionary                              # debug: batch names to drop (bisect artifacts)
var camera_focus_dist: float = 60.0                         # metres camera -> focus; ViewWorld.frame sets it from ViewCamera (height / sin(pitch)); used by the admission distance rule (§5.9.1)

func setup(cam: Camera3D, q: Quality, recipes: FxRecipeBook, ground: ViewTerrain, scorch_layer: ViewScorchLayer) -> void
func advance(dt: float) -> void                             # explicit stepping (set_process(false)); the ONLY clock writer of `fx_time`
func now() -> float
func set_quality(q: Quality) -> void
func spawn(id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, scale: float = 1.0) -> int   # handle > 0, or -1 (culled/rate-limited/unknown); a = origin, b = target (LINE) or b.x = duration (AREA)
func cancel(handle: int) -> void                            # SUPER-class effects only (warning markers)
func schedule(delay: float, id: StringName, a: Vector3, b: Vector3, s: float) -> void   # re-culled when it fires
func start_loop(id: StringName, a: Vector3, b: Vector3, scale: float, interval: float, duration: float) -> int
func start_stamper(id: StringName, node: Node3D, spacing: float, duration: float, scale: float = 1.0) -> int   # every N metres travelled, <= 8 per frame
func start_tracker(id: StringName, from_cb: Callable, to_cb: Callable, interval: float, duration: float, scale: float = 1.0) -> int   # NEW: endpoints re-evaluated each emit (continuous beams, Helios spot, repair tethers)
func stop_emitter(handle: int) -> void
func prewarm() -> void; func clear_all() -> void
func get_stats() -> Dictionary; func reset_stats() -> void
# primitives used by the recipe interpreter (public so native escape-hatch effects can call them)
func sprites(batch: StringName, pos: Vector3, size_m: float, life: float, param: float = 1.0, palette: int = 0) -> void
func puff(batch: StringName, pos: Vector3, size_m: float, life: float, alpha: float = 1.0) -> void
func ribbon(batch: StringName, from: Vector3, to: Vector3, life: float, width: float, tail: float, flight: float, linger: float, arc: Vector3, palette: int) -> void
func tracer(from: Vector3, to: Vector3, speed: float, tail: float, width: float, palette: int, arc: Vector3 = Vector3.ZERO) -> void
func trail(from: Vector3, to: Vector3, flight: float, linger: float, width: float, arc: Vector3 = Vector3.ZERO, batch: StringName = &"trail") -> void
func cone(from: Vector3, dir: Vector3, length: float, width: float, life: float) -> void
func beam(from: Vector3, to: Vector3, life: float, width: float) -> void; func rail(from: Vector3, to: Vector3, life: float, width: float) -> void
func bolt(from: Vector3, to: Vector3, life: float, width: float, arc_h: float) -> void; func shimmer(from: Vector3, to: Vector3, life: float, width: float) -> void
func ring(batch: StringName, pos: Vector3, radius: float, life: float, palette: int = 0) -> void
func dome(pos: Vector3, radius: float, life: float, mode: int = 0) -> void
func column(batch: StringName, pos: Vector3, radius: float, height: float, life: float) -> void
func light_flash(pos: Vector3, color: Color, energy: float, range_m: float, dur: float) -> void
func scorch(pos: Vector3, radius: float, life: float, hot: float) -> void        # paints ViewScorchLayer (terrain-only) + optional ground glow sprite; NO Decal nodes
func shake(amount: float, pos: Vector3) -> void

class_name FxRecipeBook extends RefCounted
func load_file(path: String = "res://data/recipes/fx.json") -> bool
func has(id: StringName) -> bool
func def(id: StringName) -> FxDef                            # FxDef: id, cls, kind, radius, nominal_scale, layers (compiled ops)
func run(d: FxDef, m: FxManager, a: Vector3, b: Vector3, s: float) -> void     # interprets the layer list (expression scope: §7.5)
func ids() -> PackedStringArray
func errors() -> PackedStringArray

class_name FxCatalog extends RefCounted
func muzzle_id(warch: int) -> StringName                    # `warch` = DefWeaponArch index (0..26); "muzzle_" + archetype family (§5.9.2); a `pres_fx.muzzle` string on the def wins when present
func impact_id(warch: int, result: int, splash_radius_units: int) -> StringName   # PROJECTILE_IMPACT result 1..5 (§5.9.3)
func explosion_id(fx_kind: int, radius_units: int, damage_type: int) -> StringName   # EXPLOSION event: data fx name when fx_kind > 0 and known, else §5.9.3 rules
func trail_id(warch: int) -> StringName
func death_id(death_kind: int, size_class: int, flags: int) -> StringName
func default_fx_for_missing(id: StringName) -> StringName   # fallback + one-time Log.warn

class_name FxEventRouter extends RefCounted
func setup(v: ViewWorld) -> void
func on_event(ev: PackedInt32Array, o: int) -> void         # ev = the frame batch, o = base index of one 10-int record: type ev[o], tick ev[o+1], a ev[o+2] ... h ev[o+9]; no copy, no allocation; switch on type, §6.2
```

### 3.7 Overlays and picking

```gdscript
class_name ViewInstanceBuffer extends RefCounted        # bulk MultiMesh writer, stride 20 floats, colour+custom both enabled (Compat pitfall)
func setup(parent: Node3D, mesh: Mesh, mat: Material, capacity: int, cast_shadow: bool = false) -> void   # sets multimesh.custom_aabb to the map bounds + 100 m (one AABB, so no wrong culling)
func begin() -> void
func push(xf: Transform3D, color: Color, custom: Color) -> void      # drops silently at capacity, counting overflow
func commit() -> void                                                # assigns `buffer`, sets visible_instance_count

class_name ViewSelection extends Node3D
func setup(v: ViewWorld) -> void
func set_selection(ids: PackedInt32Array) -> void                    # UI calls on change; also drives u_state.y = 1 on the rigs
func set_hover(id: int) -> void                                       # -1 clears
func set_aura(id: int, color: Color, until_tick: int) -> void
func update(dt: float) -> void

class_name ViewHealthBars extends Node3D
enum Mode { NEVER, SELECTED, DAMAGED, ALWAYS }                        # default DAMAGED (selected + hovered + hurt within 8 s + all under construction)
func setup(v: ViewWorld) -> void
func set_mode(m: int) -> void
func mark_damaged(id: int, tick: int) -> void
func update(dt: float) -> void

class_name ViewLines extends Node3D
func set_rally_sources(structure_ids: PackedInt32Array) -> void       # producers whose rally point is drawn (selected)
func set_order_sources(unit_ids: PackedInt32Array) -> void            # selected units whose queued orders are drawn (cap 32 units x 8 waypoints)
func set_preview(points: PackedVector3Array, color: Color) -> void    # transient path/drag preview
func update(dt: float) -> void

class_name ViewPlacementState extends RefCounted      # validator-neutral; the UI fills it from SimPlacement.validate (economy.md 3.4) or MapBuildRules.check (terrain_movement 3.6) and reuses one instance
const CF_OK: int = 0; const CF_TERRAIN: int = 1; const CF_STRUCTURE: int = 2; const CF_UNIT: int = 3; const CF_DEPOSIT: int = 4
const CF_DEBRIS: int = 5; const CF_APRON: int = 6; const CF_SHORE: int = 7; const CF_KEEPOUT: int = 8   # 0-7 = economy SimPlacementResult numbering, 8 = map PR_KEEPOUT / PR_HALO / PR_NOBUILD
var def_idx: int; var origin_cx: int; var origin_cy: int; var rot: int    # rot 0..3 = clockwise quarter turns seen from above
var w: int; var h: int                    # footprint size AFTER rotation
var cells: PackedByteArray                # w*h CF_* codes, row-major; empty = colour all cells by `valid`
var valid: bool; var in_radius: bool

class_name ViewPlacementGhost extends Node3D
func show_structure(def_idx: int, recipe_id: StringName, style_id: StringName, rot: int) -> void
func update_cursor(world_pos: Vector3, state: ViewPlacementState) -> void   # snaps to the cell grid, colours per-cell CF_* states
func show_build_radius(on: bool) -> void                              # dashed 8-cell circle around every ACTIVE friendly HQ
func hide_ghost() -> void

class_name ViewRangeRings extends Node3D
func show_for(ids: PackedInt32Array) -> void                          # max (and min) range of the selected armed entities (range_max_eff / range_min_of)
func show_preview(center: Vector3, range_m: float, min_range_m: float = 0.0) -> void
func hide_all() -> void

class_name ViewWarnings extends Node3D    # source: SW_WARNING / POWER_WARNING (+ SW_LAUNCHED / SW_CANCELLED) events; shown when the local team is affected (§5.9.5); ignores fog and decoys
class_name ViewZones extends Node3D       # source: ZONE entities (SPAWNED / REMOVED events, geometry from the zone def + entity x, y, facing)
class_name ViewGhosts extends Node3D      # source: sim.fog.ghosts(pid) (request 9), reconciled on ghost_version change or every 0.5 s
class_name ViewStatusMarks extends Node3D # source: STATE (cloak, EMP, shutdown, suppressed, repairing), POWER_USED (buff rings), HEAL, SALVAGE events
class_name ViewFloatText extends Node3D
func popup(text: String, world_pos: Vector3, color: Color, size_m: float = 0.9) -> void   # 1.2 s rise+fade; pool of 24, oldest recycled

class_name ViewPicker extends RefCounted
const PICK_UNITS: int = 1; const PICK_STRUCTURES: int = 2; const PICK_WRECKS: int = 4; const PICK_OWN: int = 8; const PICK_ENEMY: int = 16
const PICK_NEUTRAL: int = 32; const PICK_AIR: int = 64; const PICK_GHOSTS: int = 128; const PICK_ANY: int = 0xFF
func setup(v: ViewWorld) -> void
func pick(screen_pos: Vector2, filter: int) -> int
func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int
```

```gdscript
class_name ViewProjectiles extends Node3D
func setup(v: ViewWorld, cap: int) -> void
func spawn(proj_id: int, warch: int, shooter_id: int, sx: int, sy: int, ex: int, ey: int, flight_ticks: int, tick: int) -> void   # from PROJECTILE_LAUNCHED (proj_id = combat's serial)
func finish(proj_id: int, result: int) -> void                         # from PROJECTILE_IMPACT (result 1 entity, 2 ground, 3 water, 4 intercepted, 5 expired)
func update(alpha: float) -> void                                       # mirrors pool slots by serial (missiles, rockets, torpedoes) and animates arcs analytically (bombs, shells)
```
Every overlay / helper node above implements the same two-method contract, called by `ViewWorld`: `setup(v: ViewWorld) -> void` once, `update(dt: float) -> void` once per frame (steps 9-10 of §3.0); none keeps a `SimEntity` reference.

### 3.8 Quality

```gdscript
class_name ViewQuality extends RefCounted
enum Preset { LOW, MEDIUM, HIGH, ULTRA }
enum Renderer { FORWARD_PLUS, MOBILE, COMPATIBILITY }
var preset: int = Preset.HIGH; var renderer: int; var values: Dictionary   # resolved key->value table (§4.9), overrides applied, caps clamped
static func detect_renderer() -> int                          # from RenderingServer.get_current_rendering_method(), never from OS name
static func from_settings(cfg: ConfigFile, presets_json: Dictionary) -> ViewQuality      # keys: user://settings.cfg [video] and [access] (§7.7)
var reduce_flash: bool; var reduce_motion: bool; var colour_mode: int      # [access]; ViewTeamColors.MODE_NORMAL 0, PROTAN 1, DEUTAN 2, TRITAN 3, HIGH_CONTRAST 4 (§5.12)
func get_int(key: StringName) -> int; func get_float(key: StringName) -> float; func get_bool(key: StringName) -> bool
func apply_to_viewport(vp: Viewport) -> void                  # msaa, screen_space_aa, scaling mode/scale, debanding, mesh_lod_threshold, taa
func fx_quality() -> int                                      # FxManager.Quality

class_name ViewQualityAuto extends RefCounted
func setup(q: ViewQuality, on_change: Callable) -> void       # on_change(new_preset: int, reason: String)
func sample(dt: float) -> void                                # p95 over 3 s windows; step down after 2 bad windows, up after 10 good ones (max once per 30 s)

class_name ViewTeamColors extends RefCounted
enum Mode { NORMAL, PROTAN, DEUTAN, TRITAN, HIGH_CONTRAST }         # [access] colour_mode (§5.12)
static func set_mode(m: int) -> void                           # re-publishes the palette; ViewWorld rewrites u_team / mm_team of live entities once
static func color(id: int) -> Color                            # id 0..15 = SimPlayer.color (12..15 = 0..3 lightened 25 %), mode dependent; UiTheme.team_colors() returns color(0..7)
static func pip_shape(id: int) -> int                          # 0 circle, 1 triangle, 2 square, 3 diamond, 4 cross, 5 hexagon, 6 star, 7 bar; ids 8..15 repeat with an outline
static func contrast_against(c: Color, palette: Dictionary) -> float   # faction-paint collision helper for tests
```

### 3.9 Memory ownership summary

| Memory | Owner | Lifetime / rule |
|---|---|---|
| `ViewEntity` objects, rigs / batch slots | `ViewWorld` (`_by_id: Dictionary` int->ViewEntity, `_active: Array[ViewEntity]`) | created on `SPAWNED` / reconcile, freed after the dying window (`DIED` + recipe `meta.death.ticks`) or immediately on a silent `REMOVED` |
| `ArrayMesh` per model | `ViewModelBuilder._models` | shared by reference; never mutated; freed by `clear()` at teardown |
| Materials | `ViewMaterials` | one material per *material key* (`style.material`, i.e. ≈ 8 faction looks; subfaction styles share their parent's) x 4 variants, batch variant per (key, player colour); persist across matches |
| Terrain arrays (`hv`, control textures) | `ViewTerrain` | freed at `teardown()` |
| FX rings / lights | `FxManager` | persist across matches; `clear_all()` at teardown |
| Packed scratch arrays for picking / events | `ViewPicker`, `ViewEventRouter` | reused; cleared on use |
| Anything read from the sim | sim | view keeps **ids and snapshots (ints/floats)**, never a `SimEntity` reference across frames (entities can be freed) |

---
## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Units, conversions and constants (`ViewConsts`)

```gdscript
const M_PER_UNIT: float = 3.0 / 1024.0        # sim sub-cell unit -> metres (exact in float32)
const UNIT_PER_M: float = 1024.0 / 3.0
const CELL_M: float = 3.0
const BAT_TO_RAD: float = TAU / 4096.0
const TELEPORT_SNAP_UNITS: int = 6144          # |curr - prev| above this in one tick = snap, no interpolation (6 cells)
const FOG_UPDATE_S: float = 0.1                # sim vision stride 2 at 20 TPS = 10 Hz; cross-fade length
const GROUND_LIFT_M: float = 0.02              # units rest 2 cm above the interpolated terrain height (z-fight guard)
static func yaw_of_bat(bat: int) -> float      # -bat*BAT_TO_RAD - PI/2   (model -Z forward -> sim heading)
static func turret_yaw(rel_bat: int) -> float  # -wrap_bat(rel_bat) * BAT_TO_RAD; rel_bat = combat's mount angle, ALREADY relative to the hull (combat.md 5.2, mnt[M_ANGLE])
static func rel_yaw(abs_bat: int, hull_bat: int) -> float   # turret_yaw(abs_bat - hull_bat); only for tools and tests that hold absolute angles
static func wrap_bat(d: int) -> int            # ((d + 2048) & 4095) - 2048
static func lerp_bat(a: int, b: int, t: float) -> float   # a + wrap_bat(b - a) * t: shortest way round; the result is in bat and is NOT wrapped
static func struct_rot(facing: int) -> int     # ((facing + 512) >> 10) & 3: quarter turns clockwise seen from above (structures store 1024 * orient in `facing`, ASSUMPTION(production))
```

Worked example: sim `(x=51200, y=30720, facing=1024)` -> world `(150.0, h, 90.0)`, yaw `-1024*BAT_TO_RAD - PI/2 = -PI` (facing south = +Z: rotating −Z by π about Y gives +Z (verified)). Combat mount angle `M_ANGLE = 512` (hull-relative) -> shader yaw `-0.7854` rad; `M_ANGLE = 3900` -> `wrap_bat = -196` -> `+0.3007` rad (turret 17.2° counter-clockwise seen from above). Absolute helper: turret `3900`, hull `200` -> `wrap(3700) = -396` -> `+0.6075` rad. `lerp_bat(4090, 10, 0.5) = 4090 + 16*0.5 = 4098` (passes through north-east zero, never the long way round). `struct_rot(0) = 0`, `struct_rot(1024) = 1`, `struct_rot(700) = 1`, `struct_rot(3072) = 3`; `yaw = -rot * PI/2` maps the model front (+Z, south) to west for rot 1 (clockwise seen from above (verified)).

### 4.2 Enumerations

**Material classes** (`ViewMeshBuilder.Mat`, 3 bits in CUSTOM0.x): `PAINT 0, METAL 1, GLASS 2, RUBBER 3, EMISSIVE 4`.

**Part kinds** (`ViewMeshBuilder.Part`, CUSTOM0.y). `param` = CUSTOM0.z/255, `extra` = CUSTOM1.w (metres unless noted), `pivot` = CUSTOM1.xyz in *model space*. Kinds 0-15 are spike-verified `[M]`; 16-24 are additive extensions of the same shader pattern (unverified, low risk).

| # | Kind | param | extra | Vertex-shader behaviour |
|--:|---|---|---|---|
| 0 | STATIC | random panel-grid seed (builder-assigned) | – | none |
| 1 | TURRET | – | – | yaw about pivot by `u_anim.w` |
| 2 | BARREL | elevation scale (0..1 of 90°) | recoil travel m | translate +Z by `u_aux.x*extra`, elevate about trunnion `UV2=(y,z)` by `u_aux.w*param*π/2`, then yaw (`u_anim.w`) |
| 3 | WHEEL | – | radius m | rotate about X at pivot by `-u_anim.z/max(extra,0.05)` |
| 4 | TRACK | – | – | no vertex motion; fragment tread scroll `s = UV.y - u_anim.z` (UV = lateral m, arc-length m; belt oriented so the top run moves forward) |
| 5 | ROTOR | – | – | rotate Y by `u_aux.z` (spin **angle**, CPU-integrated) |
| 6 | TAIL_ROTOR | – | – | rotate X by `1.7 * u_aux.z` |
| 7 | RADAR | – | – | rotate Y by `u_aux.z` (radars, vent fans; `extra` = rate multiplier, 0 = 1) |
| 8/9 | LEG_A/LEG_B | gait phase 0..1 | stride m per cycle (0 = 0.9) | swing X by `±sin(ph)*u_anim.y*0.75`, `ph = u_anim.z*TAU/stride + param*TAU` (locked to roll distance: no foot sliding; walkers use stride ≈ 3.2 m) |
| 10/11 | ARM_A/ARM_B | gait phase | stride m (0 = 0.9) | swing X by `∓0.8*sin(ph)*u_anim.y*0.75` |
| 12 | BODY_BOB | gait phase | stride m (0 = 0.9) | `y += abs(sin(ph))*0.035*u_anim.y`; if `UF_SUPPRESSED` crouch: `y -= 0.22` |
| 13 | DOOR | – | slat travel m | `y += u_aux.y*extra` (slats stack under the lintel: slat i travels `2.88-0.25i`) |
| 14 | BLINK | phase | – | emission gated by `step(0.55, fract(fx_time*0.9 + param))`; slowed ×0.25 when `UF_UNPOWERED` |
| 15 | DEPLOY | direction: angle = `u_aux.y*(param*2-1)*2.2` rad | – | rotate X about pivot (spades, stabilisers) |
| 16 | DEPLOY_Z | same | – | rotate Z about pivot (outriggers, fold-out mast arms) |
| 17 | SLIDE_Y | – | travel m | `y += u_aux.y*extra` (masts, hoists, crane arms) |
| 18 | SLIDE_Z | – | travel m | `z += u_aux.y*extra` (rail extension, gangways) |
| 19/20 | TURRET1/BARREL1 | as 1/2 | as 1/2 | as 1/2 with `u_mnt1 = (yaw, elevation, recoil)` |
| 21/22 | TURRET2/BARREL2 | as 1/2 | as 1/2 | `u_mnt2` |
| 23/24 | TURRET3/BARREL3 | as 1/2 | as 1/2 | `u_mnt3` (`MAX_MOUNTS = 4` in combat.md: mount 0 uses kinds 1/2) |

Gait parts (8-12) additionally read `UV2 = (member_index, member_count)`: the vertex is collapsed to a point when `(1 - u_state.x) <= member_index/member_count` (member 0 is never hidden while the entity exists). This is how "squads show several soldiers who fall as health drops" (ARCH §12) costs nothing: hp fraction 0.74 with 4 members hides member 3, 0.49 hides members 2-3, 0.24 hides 1-3.

**Instance flags** (`u_state.z`, float-encoded int, exact below 2^24):

| Bit | Name | Meaning |
|--:|---|---|
| 1 | `UF_FOG_DIM` | dim by the nearest-cell fog state (neutral structures in explored-but-fogged cells); ignores bilinear smoothing so it agrees with sim visibility |
| 2 | `UF_GHOST` | remembered structure: desaturate 70 %, darken to 45 %, emissive off, animations frozen |
| 4 | `UF_SUBMERGED` | lowered hull, blue tint, no specular |
| 8 | `UF_UNPOWERED` | emissive ×0.25, blink slowed, radar stops (the view eases the spin rate to 0) |
| 16 | `UF_CLOAKED` | fresnel+noise shimmer, albedo ×0.35 (allies see it; enemies get it only when detected) |
| 32 | `UF_EMP` | flicker + cyan arcs tint |
| 64 | `UF_WRECK` | burnt: albedo ×0.25, team mask off, roughness 0.9, sparse embers |
| 128 | `UF_SUPPRESSED` | infantry crouch (BODY_BOB) |
| 256 | `UF_DECOY_ID` | identified decoy: scanline hologram overlay |

**Other enums** (`ViewConsts`): `VS_HIDDEN 0, VS_VISIBLE 1, VS_GHOST 2, VS_DYING 3` (visual state); `MOTION_FOOT 0, WHEELED 1, TRACKED 2, AMPHIBIOUS 3, NAVAL 4, SUB 5, AIR_FIXED 6, AIR_HOVER 7, STATIC 8` (identical to data's `MoveClass`, data_balance.md 4.1; a recipe's `meta.motion` overrides the def, e.g. the command walker is class `TRACKED` but uses the leg gait); `FOG_SHROUD 0, FOG_FOG 1, FOG_VISIBLE 2`; `DK_VEHICLE 1, DK_INFANTRY 2, DK_CRASH 3, DK_AIR_EXPLODE 4, DK_SINK 5, DK_STRUCTURE 6, DK_DRONE 7, DK_SILENT 8` (view-derived death kinds, §5.9.4; numbering kept from combat.md so fx ids read the same); `PH_ACTIVE 0, PH_BUILDUP 1, PH_SELLING 2, PH_UNDEPLOY 3` (structure phases).

**Sim mirrors** are referenced through the sim's own constants (`SimEntity.Kind.*`, `SimEntity.Layer.*`, `SimWorld.Rel.*`, `SimFlags.F_*`, `SimEvent.*`), never re-declared in `view/`, except in the fixture builder of the tests: `Kind UNIT 0, STRUCTURE 1, WRECK 2, ZONE 3, DEPOSIT 4`; `Layer GROUND 0, AIR 1, SURFACE 2, UNDERWATER 3`; `Rel SELF 0, ALLY 1, ENEMY 2, NEUTRAL 3`. Flag bits the view reads (sim_core 4.3): `F_DEAD 0, F_REMOVING 1, F_INSIDE 2, F_TEMPORARY 3, F_SUMMONED 4, F_DECOY 6, F_UNTARGETABLE 9, F_NO_SELECT 10, F_TETHERED 11, F_EXPIRE_KILLS 15, F_MOVING 16, F_AIRBORNE 17, F_BLOCKED 18, F_ON_WATER 19, F_FIRING 20, F_ENGAGED 21, F_WEAPONS_OFF 22, F_DEPLOYED 24, F_DEPLOYING 25, F_CLOAKED 26, F_ABILITY_ACTIVE 27, F_POWERED 28, F_REPAIR_ON 29, F_SELLING 30`. Mapping from sim flags and timers to the shader flags above: `UF_CLOAKED = F_CLOAKED`; `UF_EMP` = an `ST_EMP` / `ST_SHUTDOWN` state is active (set by the `STATE` event for its duration; `_reconcile` restores it from `tick < t_disabled` for units and `tick < t_shutdown` for structures, which also cover non-EMP lockouts, so the event wins when both exist); `UF_SUPPRESSED = tick < t_suppressed`; `UF_UNPOWERED = def.needs_power and not F_POWERED`; `UF_SUBMERGED = layer == UNDERWATER`; `UF_WRECK = kind == WRECK`; `UF_GHOST` and `UF_FOG_DIM` are view decisions (§5.3); `UF_DECOY_ID = F_DECOY and sim.fog.decoy_identified(local_pid, e)` (request 10).

### 4.3 Mesh vertex layout (adopted from `[M]`, verified on Forward+, Mobile and Compatibility)

One `ArrayMesh`, one surface, `PRIMITIVE_TRIANGLES`, 16-bit indices when `verts < 65536`.

| Attribute | Format | Content |
|---|---|---|
| `ARRAY_VERTEX` | Vector3 | model space, metres (after `model_scale`) |
| `ARRAY_NORMAL` | Vector3 | flat per face except lathes (smooth below 38°) |
| `ARRAY_COLOR` | RGBA8 | rgb = paint (sRGB), **a = team mask** 0..1 |
| `ARRAY_TEX_UV` | float2 | planar face coordinates in metres (+ random offset ≤ 3 m) for panel lines; TRACK: (lateral m, arc-length m) |
| `ARRAY_TEX_UV2` | float2 | BARREL: `(trunnion_y, trunnion_z)`; gait parts 8-12: `(member_index, member_count)`; otherwise 0 |
| `ARRAY_CUSTOM0` | `ARRAY_CUSTOM_RGBA8_UNORM`, `PackedByteArray` 4 B | x = `(ao4<<4)\|(wear<<3)\|mat`, y = part kind, z = param 0..255, **w unused (Compat drops it, reads 1.0)** |
| `ARRAY_CUSTOM1` | `ARRAY_CUSTOM_RGBA_HALF`, `PackedByteArray` 8 B via `encode_half` (truncating: pivot error < 4 mm for abs(coordinate) < 8 m, < 8 mm below 16 m; verified 7.5 mm worst case on ±10 m, so pivots and extras must stay within ±16 m) | xyz = pivot (model space), w = extra |
| flags | `(ARRAY_CUSTOM_RGBA8_UNORM << ARRAY_FORMAT_CUSTOM0_SHIFT) \| (ARRAY_CUSTOM_RGBA_HALF << ARRAY_FORMAT_CUSTOM1_SHIFT)` | presence bits derived from the arrays |

Engine stride 52 B/vertex (half) or 60 B (float); tank 14.0 k verts (incl. LOD copies) ≈ 740 KB. **Winding:** Godot front faces are clockwise; the builder auto-orients every polygon against an outward reference normal, so authors never think about winding. LODs are index subsets: LOD1 key `0.02` (≈ 31 m at 1080p / fov 38°), LOD2 key `0.06` (≈ 94 m) share the vertex buffer; bevel strips exist only in LOD0, so LOD1/2 reference duplicated plain faces and half-segment lathes (+35 % vertices, −42 % primitives in a 400-unit frame `[M]`).

### 4.4 Per-instance data

**Node backend (Forward+, Mobile):** `GeometryInstance3D.set_instance_shader_parameter(name, Color)`; values are **not** sRGB-converted by the engine (team colour is authored sRGB and converted in the shader).

| Uniform (vec4) | x | y | z | w | Written |
|---|---|---|---|---|---|
| `u_team` | r | g | b | cloak level 0..1 | spawn, owner change, cloak change |
| `u_anim` | structures: **sink depth in metres** (0 = complete; the shader does `p.y -= u_anim.x`, so it needs no model height); units: unused | move 0..1 (eased) | roll distance m | turret yaw rad (relative to hull; Godot CCW-positive) | per frame when changed |
| `u_aux` | recoil 0..1 | deploy / door / activity 0..1 | spin angle rad (rotors, radars; integrated on the CPU from the eased `spin` rate so start / stop never pops) | barrel elevation 0..1 | per frame when changed |
| `u_state` | damage 0..1 (soot) | selected/hover 0..1 (rim) | flags (§4.2) | hit flash 0..1 | on change |
| `u_mnt1..u_mnt3` | yaw rad | elevation 0..1 | recoil 0..1 | – | only entities with independent extra mounts |

Blinkers read the **global** `fx_time` (no per-instance time, so they cost no writes and freeze with pause / game speed). Rotors and radars use a CPU-integrated angle in `u_aux.z` (`angle += spin*dt`, wrapped at 8π; `spin` eased 0 <-> 28 rad/s for rotors, 0 <-> 1.2 rad/s for radars over 1 s) because `spin*fx_time` would jump in phase whenever the rate changes; only spinning entities in view are written (≤ ~70 per frame). Instance-uniform capacity: 16 vec4 slots are reserved per instance regardless of how many are declared, and the default global buffer (65 536 entries) allows 4096 instances; we request `rendering/limits/global_shader_variables/buffer_size = 262144` (16 384 instances; **inferred, untested above 800 instances `[M]`**: VIEW-M3 must render 5000 node instances to confirm) in §13-app. Compatibility caps at ~256 instance-uniform users, hence the batch backend there.

**Batch backend (`MM` variant):** `MultiMesh` with `use_colors = true` and `use_custom_data = true` (both, always; Compat feeds custom data into COLOR otherwise), stride 20 floats (12 transform + 4 colour=white + 4 custom). `INSTANCE_CUSTOM = (roll_m, turret_yaw, recoil, damage)`; team colour via material uniform `mm_team` (one material per style × player colour); no per-instance elevation, deploy / door activity, spin rate or flags on this path (artillery stays in its travel pose, barrels rest level, rotors and radars spin at a fixed rate per part kind, cloak / EMP / unpowered looks are unavailable); damage soot and squad-member hiding work through `.w`. `MultiMesh.buffer` must always equal `instance_count*20` floats even when `visible_instance_count` is smaller.

**Material-uniform variant (`MATU`):** plain `uniform` copies of the same names, one `ShaderMaterial` duplicate per entity; used by structures on Compatibility (≤ ~250 structures) and by icon baking.

### 4.5 `ViewEntity` (typed fields; one instance per mirrored sim entity)

```gdscript
class_name ViewEntity extends RefCounted
# identity (set once, from the SPAWNED payload: the sim entity may already be gone when the event is processed)
var id: int; var def_idx: int; var kind: int; var owner: int; var layer: int
var vdef: ViewDef                     # ViewDefAdapter record: bible id, faction code, recipe / icon ids, scale, move class, size class, footprint, needs_power, is_hq
var recipe_id: StringName; var style_id: StringName; var model: ViewModel
var team_index: int; var team_color: Color
var motion: int                       # MOTION_*
var radius_m: float; var height_m: float; var pick_half: Vector3      # pick volume = box centred at (0, height/2, 0) yawed with the entity
var members: int = 1                  # squad size (from ViewModelInfo)
# backend handle
var rig: ViewModelRig; var slot: int = -1
# visibility
var vs: int = ViewConsts.VS_HIDDEN; var in_view: bool; var next_full_frame: int; var vis_ver: int = -1   # vis_ver = fog_version the cached visibility was computed for
# two-sample snapshot (ints copied from the sim; the kernel stores no previous values, §3.0)
var x_prev: int; var y_prev: int; var x_cur: int; var y_cur: int     # sub-cell units
var facing_prev: int; var facing_cur: int                            # bat 0..4095
var mnt_prev: PackedInt32Array; var mnt_cur: PackedInt32Array        # turret angle per mount in bat RELATIVE to the hull (ViewSimReader.turret_rel_bat), size = mount count 0..4
var sim_gone: bool                    # DIED / REMOVED seen: the record now animates on its own until dying_until_tick
# interpolated placement (world space, floats)
var wx: float; var wy: float; var wz: float; var yaw: float
var normal: Vector3 = Vector3.UP; var normal_frame: int      # smoothed terrain normal, recomputed every 3rd frame
# animation channels (mirror the instance uniforms)
var roll_m: float; var move01: float; var turret_yaw: float; var elevation: float; var recoil: float
var deploy: float; var spin: float; var spin_angle: float; var build: float; var damage: float; var selected: float; var flash: float
var flags: int; var cloak: float; var mnt: PackedFloat32Array      # UF_* shader flags; cloak level; 9 floats: (yaw, elev, recoil) x mounts 1..3
var last_anim: Color; var last_aux: Color; var last_state: Color   # last pushed values (skip identical writes)
# mirrored gameplay snapshots (ints; refreshed by every sample)
var hp: int; var max_hp: int; var sim_flags: int; var holder: int = 0; var expires: int = 0
var dying_until_tick: int = -1; var dying_kind: int
# fx handles
var stamper: int = -1; var damage_emitter: int = -1; var wake: int = -1

class_name ViewUnit extends ViewEntity
var alt: float; var alt_target: float; var bank: float; var pitch_air: float   # aircraft: altitude m, eased target, bank and pitch rad
var airborne: bool                                                              # last sampled F_AIRBORNE
var sink: float                                                                 # 0..1 sinking ships, 0..1 submerge depth for subs (layer UNDERWATER -> 1)
var deploy_target: float; var deploy_rate: float
var bob_phase: float                                                            # naval bob offset (from id hash)

class_name ViewStructure extends ViewEntity
var phase: int; var phase_t0: int; var phase_ticks: int   # PH_ACTIVE / PH_BUILDUP / PH_SELLING / PH_UNDEPLOY; start tick and length (recipe meta.buildup_ticks, default 30 = economy.md 5.3; STATE durations override)
var footprint: Vector2i; var rot: int                     # cells (before rotation), quarter turns clockwise (ViewConsts.struct_rot(facing))
var door_t: float; var door_dir: int                      # 0 idle, +1 opening, -1 closing
var activity: float; var powered: bool; var needs_power: bool; var scaffold: MeshInstance3D
var damage_stage: int                                     # 0 none, 1 smoke (<66 % hp), 2 fire (<33 %)
var occupants: int                                        # garrison windows: LOADED - UNLOADED counter, reconciled every 2 s from F_INSIDE and holder
```

### 4.6 Global shader parameters (declared once by `ViewGlobals.ensure()`; names are the cross-shader contract)

| Name | Type | Writer | Read by |
|---|---|---|---|
| `fx_time` | float | `FxManager.advance` (pause / game-speed / fixed-step aware; never `TIME`) | fx_*, unit (blink; rotors / radars only in the `MM` variant), ring, line |
| `fx_lod` | float 0..1 | `FxManager.set_quality` | fx_sprites (thins cluster quads via UV2.x) |
| `view_time` | float | `ViewGlobals.tick` (frozen at 0 in screenshot mode) | terrain, water, decor, ring, health_bar |
| `atm_sun_dir` / `atm_sun_color` | vec3 | `ViewAtmosphere.apply_mood` (to-sun unit vector; linear × energy) | water, terrain, unit (spec fill), fx |
| `atm_sky_horizon` / `atm_sky_zenith` | vec3 | same (linear) | water reflection, decor |
| `atm_cloud` | vec4 | same: `(strength, scale 1/m, drift x, drift z)` | terrain, decor |
| `atm_night` | float 0..1 | `ViewAtmosphere.set_night` | unit / decor emissive multiplier `1 + 1.2*atm_night` |
| `fow_curr`, `fow_prev` | sampler2D (R8, `texelFetch`) | `ViewFogOfWar` | terrain, water, decor, unit (`UF_FOG_DIM`), minimap_fog |
| `fow_blend` | float | `ViewFogOfWar.advance` | same |
| `fow_rect` | vec4 `(origin.x, origin.z, 1/size.x, 1/size.z)` m | `ViewFogOfWar.setup` | same |
| `fow_cells` | vec2 | same | same |
| `fow_fog_dim` | float 0/1 | `ViewFogOfWar.set_mode` (1 for `fog_mode` 2, 0 for mode 1 "explored-stays-visible") | same: 1 = state 1 (fog) is dimmed, 0 = state 1 renders like visible |

Registration rule: `ViewGlobals.ensure()` first checks `ProjectSettings.has_setting("shader_globals/<name>")`, then a static guard; it **never** calls `global_shader_parameter_get_list()` (editor-only, errors at runtime `[T]`). Numeric globals `fx_time`, `fx_lod`, `view_time` should also be declared in `project.godot [shader_globals]` (§13-app). Samplers are runtime-registered before any material compiles. `view_common.gdshaderinc` declares `fx_time`, `view_time`, `atm_night`; `fog_of_war.gdshaderinc` the `fow_*`; `atmosphere.gdshaderinc` the `atm_*`; a global must be declared by exactly one include per shader (`fx_common.gdshaderinc` includes `view_common.gdshaderinc` and adds only `fx_lod`).

### 4.7 Overlay shader modes and FX batches

**`ring.gdshader` `mode` uniform** (one material per mode, `unshaded`, `blend_premul_alpha`, `depth_draw_never`, quad in XZ spanning [-1,1], instance transform = translate·scale(R,1,R)): `0 SELECT_RING` (ring + 4 gaps), `1 SELECT_RECT` (corner brackets for a w×h-cell footprint; `INSTANCE_CUSTOM.xy = half extents m`), `2 RANGE` (thin dashed; `INSTANCE_CUSTOM.x = inner radius/outer radius` for min range), `3 BUILD_RADIUS` (dashed + 6 % fill), `4 WARN_CIRCLE` (hatched fill, rotating spokes, sweep = elapsed/duration), `5 WARN_CAPSULE` (`custom.xy = half length, half width`), `6 AURA` (soft pulsing ring), `7 TARGET_PING` (attack-move / rally ping), `8 ZONE_DISC` (smoke/repair/reveal discs, per-kind tint in `COLOR`). `INSTANCE_CUSTOM.w = phase seed`.

**`FxBatch` inventory** (spike inventory `[F]` with rings enlarged where the 5x load test overwrote live instances; caps are hard limits = ring size; `wake` is new: mode 5 `WAKE` of `fx_ring.gdshader`, `blend_mix` foam streak from the noise atlas, quad stretched along the heading by basis scale (length, 1, width), decays over 4 s):

| Batch | Cap | Look | Batch | Cap | Look |
|---|--:|---|---|--:|---|
| `gglow` | 96 | ground glow (flat, additive; hot ground) | `trail` | 96 | smoke ribbon |
| `smoke` | 192 | 10-quad cluster | `trail_dark` | 32 | dark ribbon |
| `dustring` | 64 | 12-quad cluster | `contrail` | 32 | white ribbon |
| `dustcol` | 96 | 9-quad cluster | `firetrail` | 32 | fire ribbon |
| `puff_dust` | 768 | single billboard | `tracer` | 640 | streak ribbon |
| `puff_smoke` | 640 | single billboard | `beam` | 32 | thermal beam |
| `puff_white` | 1024 | single billboard | `rail` | 32 | rail helix |
| `fire` | 128 | 14-quad cluster, HDR ramp | `arc` | 128 | lightning |
| `debris` | 256 | 12-quad ballistic | `cone` | 256 | muzzle cone |
| `rubble` | 48 | 20-quad, persists 30 s | `shimmer` | 16 | heat refraction ribbon |
| `sparks` | 320 | 20-quad streaks | `ring_add` | 32 | additive shock ring |
| `splash` | 48 | 16-quad droplets | `ring_distort` | 32 | refraction ring |
| `flash` | 256 | star flash | `ring_emp` / `marker` | 16 / 16 | EMP ring / warning ring |
| `glow` | 192 | additive glow | `ripple` | 32 | water ripple |
| `haze` | 16 | refraction disc | `dome` | 8 | hex energy dome |
| `beacon` / `strike` | 16 / 16 | columns | `wake` (new) | 128 | ship wake foam quads (flat, alpha) |

`INSTANCE_CUSTOM = (spawn_time, lifetime, palette_index + random_seed_fraction, param)`. Ribbons encode geometry in the instance transform: `basis.x = parabolic arc offset`, `basis.y = B − A`, `basis.z = (tail m, flight s, linger s)`, `origin = A`, width in `custom.w`. Palette (8x1): 0 warm flash, 1 white-hot, 2 red, 3 green, 4 blue-white, 5 neutral shell, 6 fire orange, 7 EMP violet.

### 4.8 Render priorities and visual layers (`ViewLayers`)

| Item | `render_priority` / layer |
|---|---|
| terrain, decor, units, structures | opaque pass (priority 0) |
| water | −20 (first transparent) |
| refraction FX (`shimmer`, `ring_distort`, `haze`) | −10 / −9 (must precede smoke/fire; screen copy contains only the opaque scene, so **no distortion over water**: disabled when `terrain.is_water_at(centre)`) |
| FX premul sprites | −4 … 3 (per batch, table in `FxAssets`) |
| ghost model | 5 |
| selection / range / warning rings | 6 |
| lines (rally, waypoints) | 7 |
| placement grid | 8 |
| health bars, status marks | 9 (`depth_test_disabled`) |
| visual layer bits (`Camera3D.cull_mask`, `VisualInstance3D.layers`) | bit 0 world, 1 units, 2 fx, 3 overlays, 4 minimap-only, 19 icon studio (own world, isolated) |

### 4.9 Quality table (`quality.json` keys; defaults per preset)

| Key | LOW | MEDIUM | HIGH | ULTRA | Notes |
|---|---|---|---|---|---|
| `render_scale` | 0.75 | 1.0 | 1.0 | 1.0 | `scaling_3d_scale` |
| `scaling_mode` | FSR1 | BILINEAR | BILINEAR | BILINEAR | FSR2 / MetalFX only by user option |
| `msaa` | off | off | 4x | 8x | Mobile: 2x/4x/4x (nearly free); Compat: 2x/4x/4x |
| `fxaa` | off | on | off | off | Forward+/Mobile only |
| `shadow_mode` | blob | 2 cascades | 4 cascades | 4 cascades | |
| `shadow_atlas` | – | 2048 | 4096 | 8192 | `directional_shadow_atlas_set_size` |
| `shadow_filter` | – | SOFT_LOW | SOFT_HIGH | SOFT_ULTRA | |
| `decor_casts_shadow` | – | false | true | true | |
| `ssao` | off | low, half | medium, half | high, full | Forward+ only |
| `ssil` | off | off | off | on | Forward+ only |
| `glow` | off | on | on | on | HDR threshold from mood |
| `terrain_shader` | LOW | FULL | FULL | FULL | `#define TERRAIN_LOW` |
| `terrain_subdiv` | 1 | 2 | 2 | 2 | 3 m vs 1.5 m step |
| `water_shader` | LOW | FULL | FULL | FULL | `WATER_LOW`: one normal layer, no foam lace |
| `decor_density` | 0.5 | 0.8 | 1.0 | 1.0 | |
| `decor_groups` | 4 | 5 | 6 | 6 | groups per map side |
| `unit_shader_quality` | 0 | 1 | 1 | 1 | `quality` uniform (0 = no procedural noise; −14 % at 4K) |
| `mesh_lod_threshold` | 2.0 | 1.25 | 1.0 | 0.75 | `Viewport.mesh_lod_threshold` |
| `blob_contact_shadows` | on | off | off | off | |
| `cloud_shadows` | off | on | on | on | |
| `fx_quality` | LOW | MEDIUM | HIGH | ULTRA | fx_lod 0.45/0.7/1/1; distance ×0.6/0.8/1/1.4; lights 0/3/6/6; refraction off/off/on/on |
| `scorch_res` | 512 | 1024 | 1024 | 1024 | |
| `tread_marks` | off | on | on | on | |
| `proj_mesh_cap` | 32 | 64 | 64 | 96 | |
| `unit_backend` | AUTO | AUTO | AUTO | AUTO | AUTO = nodes on Forward+, batch on Mobile and Compat |

**Renderer clamps** (applied after the preset; never by OS name): Mobile: `ssao = ssil = off`, `unit_backend = batch`; Compatibility: additionally `fxaa = off`, `taa = off`, `scaling_mode = BILINEAR`, `ssao = off` (unverified), `fx.distort = off`, FX `compat_boost = 1.6` on cluster sprites, scorch layer only (no Decal nodes anywhere), separate colour grade `compat_grade` from the mood; MetalFX modes offered only when `RenderingServer.get_current_rendering_driver_name() == "metal"`; FSR2/MetalFX-temporal disable MSAA and require `render_scale ≤ 1`.

### 4.10 Style, mood and recipe records

`ViewStyle` (Dictionary from `styles.json`, merged along `extends`): `palette{base,dark,sec,acc,metal,rubber,glass,light,plate,concrete}` (sRGB hex), `material{wear,dirt,panel,wear_color,dirt_color,emissive}`, `kit{…}` archetype parameter defaults (§7.2), `team_plate: "band"|"panel"|"none"`, `emblem: String`. `ViewMoodDef` fields: as the spike (`sun_elevation_deg, sun_azimuth_deg, sun_color, sun_energy, sky_top, sky_horizon, ground_horizon, ground_bottom, ambient_energy, fog_color, fog_density, fog_sun_scatter, fog_aerial, exposure, white_point, saturation, contrast, brightness, lift, gamma, gain, glow_intensity, glow_threshold, ssao_intensity, dryness, cloud_strength, water_shallow, water_deep, water_absorb, foliage_a, foliage_b, palette{grass_a…snow_c}`) plus new `night: float`, `compat_grade{lift,gamma,gain}`, `wet: float` (roads/sand roughness), `decor_kit: String` (which tree/rock set). `ViewRecipe`: `{id, archetype, style, scale, seed, params, kits, ops_after, sockets, meta}` (§7.3).

---
## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Coordinate mapping, orientation, placement

* **Position.** `wx = x*3/1024`, `wz = y*3/1024` (floats). `wy` = ground height: units `terrain.height_at(wx, wz) + 0.02`; structures the mean of `height_at` at the footprint centre and 4 corners `+ 0.02` and the model carries a 1.2 m foundation skirt below origin (hides slope); naval `sea_level + bob`; aircraft `smoothed_ground + alt`.
* **Interpolation.** `pos = prev + (curr - prev) * alpha`, where prev / curr are the view's two samples (`x_prev/x_cur`, `y_prev/y_cur`, §3.0) and `alpha = session.tick_alpha()`. If `|Δx|` or `|Δy|` between the two samples exceeds 6144 units (6 cells: teleport, unload from a transport, spawn at a pad, ability jump) `alpha` is forced to 1 for that entity until the next sample. Facing and turret angles use `lerp_bat` (shortest way) between `facing_prev/cur` and `mnt_prev/cur`. The picture lags the sim by at most one tick (50 ms) plus half a frame.
  *Worked example, one tick per frame.* A Guardian tank (speed 102 units/tick, data_balance.md 7.7) samples `x_prev = 51200`, `x_cur = 51302`. At `alpha = 0.5` the interpolated `x = 51251`, `wx = 51251*3/1024 = 150.15 m`; at `alpha = 0.99` `wx = 150.29 m`; on the next tick `x_prev = 51302`, so motion is continuous.
  *Worked example, catch-up.* One frame runs 3 ticks: the samples span `51302 -> 51608` (306 units = 0.90 m). The previous frame ended at `alpha = 0.9` of the old span (`x = 51292`); the new frame starts at `alpha ≈ 0.05` of the new span (`x = 51317`): a forward step of about 25 units (7 cm), never backwards, followed by 3x normal speed for one 50 ms interval. With the exact hook (`capture_prev`) the span is the last tick only and the speed-up disappears.
* **Yaw.** Units: `yaw = -bat*TAU/4096 - PI/2` (§4.1). Model −Z is forward.
* **Structures.** Front (doors, exits, berth) is **+Z (south)** so the default camera (looking north, yaw 0) sees it; this deliberately differs from the units' −Z and agrees with the footprints (`exit_dir` 1024 = south, `door` on the south side, terrain_movement.md 7.3). `yaw = -rot * PI/2` with `rot = ViewConsts.struct_rot(e.facing)` (clockwise quarter turns seen from above, identical to `MapFootprint` orientation 0..3; structures store `1024 * orient` in `facing`, ASSUMPTION(production): the PLACE executor sets it; only the Dock is rotatable). Origin = footprint centre (`SimEntity.x, y` of a structure is the footprint centre, sim_core 4.2). The recipe receives `fw, fh` (footprint cells of orientation 0) and the door / exit / dock / pad anchors of `footprints.json` (§7.3) and must fit inside `(fw*3 - 0.5) x (fh*3 - 0.5)` m.
* **Sizes** (TAXONOMY §6, 1 cell = 3 m): `inf` radius 1.2 m, `light` 1.35, `medium` 1.65, `heavy` 2.4, `huge` 3.0, `ship_small` 1.8, `ship_medium` 3.0, `ship_large` 4.2. Model radius (max horizontal extent) must be within ±15 % of `radius_cells*3*1.05`; enforced by `test_view_recipes`. `pres_scale_bp` (default 10000, from `style_tags large/compact` = 12500/8800) multiplies the whole model (`model_scale`), collision is the sim's.
* **Squads.** A squad is one entity: the model contains `members` soldiers (rifle 4, AT 3, support 2, special 3, engineer 1) laid out in a 1.9 m disc, built with `model_scale 1.25` for RTS readability (`[M]`: unreadable at 1.0).

### 5.2 Entity update (the hot loop)

**Creation** (`SPAWNED`, or `_reconcile` for an entity that exists in the sim but not in `_by_id`). Everything comes from the event payload, because the sim entity may already be gone when the batch is processed (a unit produced and killed inside one frame): `def = defs.def_for(kind, def_idx)` (`ViewDef`; `kind` from the def table, the payload has no kind); `recipe_id = def.recipe_id` (default = the def id); `style_id = book.style_for_def(def.id, roster_id_of(owner))` where `roster_id_of` = `sim.data.rosters[sim.players[owner].roster_idx].id` (neutral owner -> style `neutral`); `model = models.get_model(recipe_id, style_id, def.scale_bp)` (placeholder + one `Log.warn` when missing); pick `ViewUnit` / `ViewStructure` by kind (wrecks are `ViewUnit` with `UF_WRECK`); `team_index = sim.players[owner].color` (neutral -1); `backend.add(ve, model, style_id, team_color, team_index)`; samples `x_prev = x_cur = payload x`, `facing` from the payload, `hp = max_hp` until the first `_sample_tick` reads the real entity; register in `_by_id`, `_active` and `_air_ids` (layer AIR). Duplicate `SPAWNED` (the tick-0 events of the first batch after `bind_world`) are ignored. Kind ZONE is routed to `ViewZones`, kind DEPOSIT to `ViewDecor` (entity mode only, risk R24), never to `_by_id`. **Disposal:** at `dying_until_tick` (or immediately for silent removals): `backend.remove`, erase from the containers, stop its emitters.

For each `ViewEntity` in `_active` (created by lifecycle events; order = ascending id), per frame:

```
e = sim.entity(ve.id)                                    # null once the sim entity is gone (ve.sim_gone): the record then animates from its cached samples until dying_until_tick
vis = _visibility(ve, e)                                 # §5.3 (int compare + one bit test; cached per fog_version and per cell change)
if vis != ve.vs: backend.set_visible(...); ve.vs = vis   # hidden entities cost nothing further
if vis == VS_HIDDEN: continue
if not ve.in_view and frame < ve.next_full_frame: continue # off-screen: full update every 12th frame (5 Hz at 60 fps)
# placement
pos = interp(ve.x_prev, ve.x_cur, ve.y_prev, ve.y_cur, alpha)   # §5.1
step = |pos_xz - ve.wxz|;  ve.roll_m += step                     # wheels/tracks/gait
move01 -> move_toward(target = step/dt > 0.25 m/s, dt/0.15)
yaw = yaw_of_bat(lerp_bat(facing_prev, facing_cur, alpha))       # float bat; any multiple of 2*PI is harmless
turret_yaw = -lerp_bat(mnt_prev[0], mnt_cur[0], alpha) * BAT_TO_RAD    # mount angles are hull-relative already (combat.md 5.2); mounts 1..3 fill ve.mnt
# ground alignment (MOTION_TRACKED 0.85, WHEELED 0.8, AMPHIBIOUS 0.5, FOOT 0, NAVAL/AIR see below)
every 3rd frame (id % 3 == frame % 3): n_t = terrain.normal_at(pos); ve.normal = ve.normal.slerp(n_t, 1 - exp(-10 dt)) (slerp only when changed > 0.5°)
xf = Transform3D(Basis(Quaternion(UP, lerp(UP, ve.normal, tilt))) * Basis(UP, yaw), Vector3(wx, wy, wz))
# channels
recoil -= dt/0.28 (clamped >= 0);  u_aux.x = recoil^1.6      # sharp kick, slow return
flash  -= dt*8;  deploy -> move_toward(deploy_target, deploy_rate*dt)
damage = clamp((1 - hp/max_hp - 0.2)/0.8, 0, 1)              # soot starts below 80 % hp; squads use hp directly in the shader
selected = move_toward(selected, target, dt*8)               # rim fade 0.12 s
# dust / wake / contrail: distance accumulators, no per-unit emitter objects
dust_acc += step;  if dust_acc >= 2.5 and speed > 1.0 and not on road: fx.spawn(&"vehicle_dust", pos, ZERO, size_scale); dust_acc = 0
# push (only when the packed Color differs from last_*)
backend.set_xform / push_anim / push_aux / push_state
```

`_sample_tick()` (step 6 of §3.0) is the only place that reads the world for an entity: `e = sim.entity(id)`; `x_cur, y_cur, facing_cur, hp, max_hp, sim_flags, holder, expires` from the fields, `mnt_cur[m] = ViewSimReader.turret_rel_bat(e, m)`; entities that are hidden, off-screen and static are sampled at 5 Hz only. It also derives the shader flags of §4.2 (`UF_*`) and the structure `powered` bit from `sim_flags`, so no other per-frame sim call exists.

Rules per motion class:

| Motion | Rules |
|---|---|
| FOOT | no tilt; gait from `roll_m` and `move01`; crouch flag while `tick < t_suppressed`; members hidden by hp; `y = terrain height` |
| WHEELED / TRACKED | tilt to slope; tracks and wheels from `roll_m`; barrels recoil; `UF_UNPOWERED` n/a; dust when fast |
| AMPHIBIOUS (skimmers, Leviathan, amphibious carriers) | tilt 0.5; hover bob `0.05*sin(fx_time*2.1+phase)`; wide low-alpha skirt dust puffs on land / spray on water through the distance accumulator (`F_ON_WATER` selects spray) |
| NAVAL | `y = sea_level + bob`; `bob = A*sin(fx_time*1.3 + phase)`, `pitch = 0.6*A*sin(fx_time*1.1+phase+1)`, `roll = 0.8*A*sin(fx_time*0.9+phase+2)` rad with `A = 0.05 / 0.03 / 0.018 rad` for small / medium / large hulls; wake ribbon `wake` batch every 1.4 m when `speed > 0.5 m/s` |
| SUB | `sink` eases (1.5 s) toward 1 while `layer == UNDERWATER` and toward 0 on `SURFACE` (`set_layer` is readable every frame): 0 surfaced, 1 submerged (`y = sea_level - 0.75*hull_h`, top stays 0.15 m above the surface so the owner keeps a visible shape; `UF_SUBMERGED`); firing from the surface needs no event (bible: surfaces 8 s when firing) |
| AIR_FIXED / AIR_HOVER | `alt_target = meta.hover` while `F_AIRBORNE`, 0 otherwise; `alt` eases at 2.5 m/s, so take-off and landing are the ramps between the two (`STATE landed / takeoff` add dust and gear cues only); cruise `meta.hover` (jet 16 m, bomber 18, EW 20, heli 7, drone 9, UAV 14, balloon 12, cargo 15); `bank = clamp(yaw_rate*0.35, ±0.5)` rad; `pitch_air = clamp(vspeed*0.05, ±0.25)`; rotors `spin` eased 0 -> 28 rad/s over 1 s once airborne or moving (angle integrated into `u_aux.z`); contrail puff every 6 m for fixed wing above 8 m/s; death: §5.9.4 |
| STATIC (structures, summons) | structure state machine below; no per-frame transform writes |

**Structure state machine** (`ViewStructure`; driven by the `SPAWNED` reason, `STATE` events, the `F_*` flags and the `PRODUCTION_COMPLETE` / `HARVEST_DELIVERED` events of sim_core 6.2):

| State | Visual | Numbers |
|---|---|---|
| BUILDUP | model rises from below ground: `build = clamp((tick + alpha - t0)/phase_ticks, 0, 1)` -> `u_anim.x = (1 - ease(build))*(height + 1.5)` metres of sink (shader: `p.y -= u_anim.x`); terrain hides the buried part; **scaffold cage** (shared mesh scaled to footprint × `height*ease(build)`) shown while `build < 1`; 3 spark emitters (`weld_tick`, 0.3 s interval, max 3 per structure, nearest 12 structures only); ground dust ring at start; on completion white flash + `build_complete` ring | starts at a `SPAWNED` with reason PLACED (2) or DEPLOYED (3); `t0` = event tick; `phase_ticks` = recipe `meta.buildup_ticks` (default 30 = economy.md 5.3 `buildup_ticks`) unless a `STATE ST_BUILDUP` (request 6) carries a duration; structures spawned with reason INITIAL or SCRIPT start ACTIVE; `ease(x) = x*x*(3-2x)` |
| ACTIVE | idle animation: RADAR `spin` 1.2 rad/s when powered (eased, angle integrated); blinkers; smoke stacks `puff_white` every 2 s (refinery/generator); door opens on `PRODUCTION_COMPLETE` with `c` = this structure (0.6 s open, 1.0 s hold, 0.6 s close via `u_aux.y`); refinery unload arm cycles `u_aux.y` 0..1 at 0.5 Hz for 1.2 s after each `HARVEST_DELIVERED` with `b` = this structure; airfield: nothing per pad | `powered = (sim_flags & F_POWERED) != 0`, re-read at every sample (no polling call) |
| UNPOWERED / EMP | `UF_UNPOWERED` (emissive ×0.25, radar stops) when `needs_power and not F_POWERED`; EMP: `UF_EMP` + `emp_arc` loop while `tick < t_shutdown` | `needs_power` = `def.power < 0` or the powered-defense flag (`ViewDef`) |
| SELLING | reverse of BUILDUP over the duration of `STATE ST_SELLING` (default 40 ticks = economy.md `sell_ticks`); `build = 1 - progress`; scaffold shown; disposed by `REMOVED` with reason SOLD (1) | `F_SELLING` is the persistent mirror (used by `_reconcile`) |
| UNDEPLOYING (HQ -> MCV) | optional: reverse buildup while `F_DEPLOYING` is set on an HQ (economy.md `CMD_UNDEPLOY_HQ`; not in the MASTER command catalog, request 12) | |
| Damage | `hp_frac < 0.66`: `damage_smoke` emitter (light); `< 0.33`: + `damage_fire`; shader soot from `damage`; emitters capped at 24 scene-wide, nearest-to-camera win | hysteresis 5 % |
| DYING | `DIED`: keep 7 ticks (0.35 s) shaking (`y` jitter 0.1 m) and darkening, then hide behind `building_collapse` | `dying_kind = DK_STRUCTURE` |

**Wrecks** (kind WRECK entities, sim_core 4.2: `def_idx` = the dead unit's def, `owner` = its original owner, `expires = born + 1200` ticks, flags `F_UNTARGETABLE | F_NO_SELECT`): the source unit's model (style from the roster of `owner`) with `UF_WRECK`; static pose from `meta.wreck` (turret yaw offset, tilt `[3, 0, -6]` deg), plus `wreck_tick` loop (smoke + embers) for the first 14 s and thin smoke afterwards until 8 s before expiry; the last 1.5 s (`expires - tick <= 30`) it sinks 0.6 m into the ground. No team colour. Wrecks without `F_NO_SALVAGE` get a faint pulsing cyan `AURA` ring only when the local player's faction is African Empire (`sim.players[local_pid].faction_idx` resolves to code `ae`); the sim alone decides eligibility through the flag. A vehicle that leaves no wreck entity (rules or def) leaves only the scorch stain.

### 5.3 Visibility rules (fog, stealth, ghosts)

Evaluated per entity and cached in `ve.vis_ver`: recomputed when `sim.fog.fog_version(pid)` changed, when the entity moved to another cell, or on every 12th frame:

| Entity | State |
|---|---|
| `sim_flags & F_INSIDE` (loaded in a transport or garrison) | `VS_HIDDEN` |
| observer (`local_pid == -1`) | `VS_VISIBLE` |
| `sim.entity_visible(local_pid, e)` (own, allied and enemy entities that pass fog, stealth, detection and decoy rules: sim_core 3.4.4) | `VS_VISIBLE` |
| enemy **structure** that fails the test | `VS_HIDDEN`; `ViewGhosts` shows the ghost record if one exists for this entity id |
| neutral (owner −1) **structure** | fog cell state ≥ 1 (explored): `VS_VISIBLE`, plus `UF_FOG_DIM` when the state is 1 and `fog_mode == 2` |
| any other unit / wreck that fails the test | `VS_HIDDEN` |
| dying record (`sim_gone`) | stays `VS_DYING` until `dying_until_tick`; hidden if `sim.cell_visible(local_pid, cx, cy)` is false at the death cell |

Cloaked entity of the local team: `UF_CLOAKED` (from `F_CLOAKED`), cloak level eased 0->0.85 over 0.6 s (`STATE ST_CLOAKED / ST_DECLOAKED` restart the ease with a shimmer ping). An enemy unit that is visible only because it is detected also carries `UF_CLOAKED` (shimmer) so players see that it is a detected stealth unit. Hidden entities keep their `ViewEntity` (cheap: skipped after the visibility test) so that reveal is instantaneous; there is no fade (opaque pipeline; hidden = node `visible=false`, or the batch instance collapsed).

### 5.4 Camera rules

```
ease(z)  = 0.35 z^2 + 0.65 z                                  z in [0,1], 0 = closest
H(z)     = lerp(height_min, height_max, ease(z))              m above the focus (34 .. 84; "wide view" 110)
pitch(z) = clamp(lerp(46 deg, 61 deg, ease(z)) + bias, 22, 82) deg   bias in [-14, 14] via tilt()
dist     = H / sin(pitch);   offset = Vector3(0, sin p, cos p) * dist, rotated about Y by yaw;   camera = focus + offset, look_at(focus)
near     = max(2, 0.6*H);  far = 1500          # 0.6H keeps a 14 m structure at the bottom screen edge unclipped (depth 25.4 m vs near 20.4 m at H = 34)
pan      = normalise(dir) * pan_speed * dist * dt;  fwd = (-sin yaw, -cos yaw);  right = (cos yaw, -sin yaw);  delta = right*dir.x - fwd*dir.y
smooth   : k = 1 - exp(-rate*dt) with rate pan 11, zoom 9, rot 12 (1/s);  focus_y follows the ground with 0.7*pan rate
zoom     : zoom_t -= steps*0.08;  with cursor: focus_t += (hit.xz - focus_t) * clamp(steps*0.08*1.5, -0.4, 0.4)
clamp    : focus in map_rect.grow(-14 m)
focus_on : target -= right * (view_margin.z - view_margin.x)/2/viewport_w * ground_width_at_focus   # centres in the HUD-free area
```

| Zoom | H (m) | pitch | distance | px/m @1080p | px per cell | tank (3.5 m) | ground footprint (16:9) |
|---:|---:|---:|---:|---:|---:|---:|---|
| 0.00 | 34.0 | 46.0° | 47 m | 33 | 100 | 116 px | 58 x 51 m (19 x 17 cells), width 46 m bottom / 92 m top |
| 0.50 | 54.6 | 52.2° | 69 m | 23 | 68 | 79 px | 85 x 65 m |
| 1.00 | 84.0 | 61.0° | 96 m | 16.3 | 49 | 57 px | 118 x 79 m (39 x 26 cells) |

**Shake.** `trauma = min(1, trauma + amount)`; decays `1.6/s`; offset = `trauma² * (0.4 m * H/34)` on the camera's local x/y and roll `trauma² * 0.5°`, driven by three incommensurate sines (35, 53, 71 rad/s) so it is smooth and frame-rate independent; applied to the child `Camera3D` transform only (never to the focus, so the clamp is unaffected). `FxManager.shake(amount, pos)` attenuates linearly to 0 at 140 m from the camera before emitting.
**Cinematic.** `cinematic_play(keys)`: keys sorted by `t` (s); focus follows a Catmull-Rom spline through `focus`, `yaw/height/pitch/fov` interpolate with smootherstep; input ignored (`cinematic_changed(true)`); Esc or any key cancels when `skippable`; on end it blends back to the saved player state over 0.6 s. Uses: match intro (2.5 s descent to the HQ), replay director cuts, optional superweapon-impact cut (off by default). `visible_ground_rect()`: four corner rays intersected with the heightfield (fallback: plane `y = water_level`), AABB, grown by 10 m.

### 5.5 Terrain rules (`[T]` design adopted)

* **Height bake.** `vw = w*subdiv + 1`. Base data = `src.corner_m` (lattice corners: `MapImages.corner_height` × 0.05 m, terrain_movement.md 3.9; the sim only uses terrain ids for gameplay, so heights are a pure view asset). For every vertex: Catmull-Rom on the 4x4 corner heights **clamped to the middle pair** (no cliff ringing), plus view-only relief noise `FastNoiseLite(simplex_smooth, f 0.09, 3 oct, seed=map seed) * 0.45 m` scaled by `0.08` on ROAD and PAVEMENT cells (ids 9, 10), by `smoothstep(9, 16, dist_to_start_cell)` near start cells and by 0 on water, beach and `SF_RAMP` cells (shorelines, ramps and gameplay-relevant heights stay exact). Rows baked with `WorkerThreadPool.add_group_task` (rows, then chunks): subdiv 2 at 192² = 160-230 ms threaded vs 250-380 ms single.
* **Chunks.** `CHUNK_CELLS = 32` (96 m); `ceil(w/32) x ceil(h/32)` chunks, edge chunks smaller (map sizes are multiples of 8, not 32); one shared index array per distinct chunk size, checkerboard diagonal `((i+j)&1)`. Arrays: position, normal (central difference of the **global** grid -> no seams), `COLOR.r` = cavity `clamp(0.5 - lap*0.05, 0, 1)` with a 4-cell Laplacian (gain ≤ 0.05 or camouflage blotches appear `[T]`), no UVs (shader uses world XZ). 256² at subdiv 2 = 524 k triangles in 64 chunks (192²: 295 k, measured 4.4-4.7 ms for the whole scene at 1080p High). **Map edge:** the map ends in a 2-cell MOUNTAIN rim (terrain_movement.md 3.3); beyond it the view adds a *void skirt*, four flat quads at rim height extending 400 m, unshaded near-black (the fog shader returns shroud outside `fow_rect`), so the sky never shows through below the horizon when the camera tilts.
* **Textures.** `ctrl_a` RGBA8 (grass, dirt, rock, sand) and `ctrl_b` RGBA8 (snow, urban, deposit, rubble) at 1 texel/cell (bilinear; the shader domain-warps the lookup by ±2.5 m), filled from the terrain ids by the table below (bilinear filtering across cells plus the shader's domain warp gives soft 3 m borders; no CPU smoothing pass); `ctrl_flags` R8 (NEAREST) = `MapData.flags` (`SF_SHORE` wet sand and foam, `SF_RAMP` suppresses the cliff-rock blend); `road_cov` R8 and `road_info` RGBA8 (roads, next bullet); `water_depth` R8 at vertex resolution `(sea_level - h + 2)/8`; `shore_dist` R8 (÷85 -> cells; two-pass chamfer over water cells from the nearest land or ford cell); `stamps` = `ViewScorchLayer.texture`. The `deposit` weight is `deposit_fraction(i)` on deposit cells, re-painted for changed cells only, so a depleted field fades from the ground. The shader blends six looks (grass, dirt, rock, sand, snow, urban/rubble) plus the deposit overlay; moisture-style variation comes from shader noise seeded by `deco_seed`, the data has no moisture layer.

| Terrain id (name) | Weights (`ctrl_a` grass, dirt, rock, sand; `ctrl_b` snow, urban, deposit, rubble) | Notes |
|---|---|---|
| 0 deep_water, 1 shallow | sand 1.0 | sea bed, tinted by the depth raster; no decor (reeds on shallow cells with `shore_dist <= 1`) |
| 2 ford | sand 0.6, dirt 0.4 | wet look (`wet` from the mood); lies at or below the water plane |
| 3 beach | sand 1.0 | wet band from `SF_SHORE` |
| 4 grass | grass 1.0 (arctic biome: snow 1.0) | tropical biome uses the lush palette |
| 5 dirt | dirt 1.0 (arctic: dirt 0.5, snow 0.5) | desert base terrain |
| 6 sand | sand 1.0 (arctic: snow 0.6, sand 0.4) | |
| 7 rock | rock 1.0 | |
| 8 forest | grass 0.7, dirt 0.3 (arctic: snow 0.6, dirt 0.4) | darker; trees come from decor |
| 9 road | urban 0.2 | asphalt from the road textures |
| 10 pavement | urban 1.0 | concrete plaza |
| 11 rubble | rubble 0.8, dirt 0.2 | |
| 12 urban_block | urban 1.0 | buildings come from decor |
| 13 cliff | rock 1.0 | triplanar by slope; on `SF_RAMP` cells the rock weight is scaled by 0.15, so ramps read as dirt paths |
| 14 mountain | rock 1.0 (arctic: snow cap above 60 % of the local relief) | includes the 2-cell map rim |

* **Roads (derived from ROAD cells, id 9).** The generator paints 3-wide once-bent trunks on open and coast maps and a lattice of 4-wide streets and 6-wide avenues on urban maps (terrain_movement.md 5.12), so the view derives everything from the cell mask. `road_cov` = 255 on ROAD cells, one 3x3 blur, sampled bilinearly and thresholded in the shader with `smoothstep(0.35, 0.65, cov)` (rounded corners, soft edge). `road_info` (NEAREST, one texel per cell) stores run-length markings, computed only when `family == URBAN` (paint on jagged diagonal trunks would step by 3 m): `rh` and `rv` = lengths of the horizontal and vertical ROAD run through the cell; the cell is a *street cell* iff `min(rh, rv) <= 8 and max(rh, rv) >= 2*min(rh, rv)` **and** the pair (start of the short run, its length `n`) is identical over at least 12 consecutive cells along the street axis (a perfectly straight street: a trunk of slope 1/4 or 1/9 shifts its window every 4 or 9 cells and is rejected, a lattice street between two junctions at pitch 16 has exactly 12); then `R = 255`, `G = 128` (street runs horizontally, across axis vertical) or `255` (vertical), `B = k` (cell index inside the short run), `A = n` (its length); every other cell (junctions, trunks, non-road) has `R = 0`. The shader reconstructs `across = (k + frac)/n` exactly (`frac` = fractional position inside the cell along the across axis) and paints centre dashes where `abs(across - 0.5)*n*3 m < 0.12 m` and `fract(along/12 m) < 0.5`, edge lines 0.15 m inside both kerbs and a 3 m zebra crossing on street cells that touch a junction cell. Trunk roads and junctions get worn asphalt (two-octave mottling, edge crumble from the `cov` gradient) without paint. Worked example: an avenue 6 cells wide, cell row 2 of 6: `k = 2, n = 6`, at `frac = 0.5` -> `across = 2.5/6 = 0.417`, distance from the centre line `0.083*6*3 = 1.5 m`, no dash; row 2 at `frac = 1.0` -> `across = 0.5`, centre line. PAVEMENT (id 10) is a concrete plaza, not a road.
* **Shader.** 6 layers with noise-modulated "height" blending, slope -> triplanar cracked rock (`steep = smoothstep(0.20, 0.40, 1 - N.y + noise*0.1)`), asphalt roads (painted markings on urban streets, worn asphalt elsewhere), wet sand and underwater tint from the depth raster, caustics (skipped in `TERRAIN_LOW`), scorch/tread overlay with bump from the alpha gradient, baked cavity AO, cloud shadows from `atm_cloud`, fog of war. ~16 texture taps. `smoothstep(e0 >= e1)` is undefined: never write it.
* **API costs.** `height_at` 0.32-0.57 µs, `normal_at` ≈ 4x that, `raycast` 8.5-11.4 µs (adaptive march `step = clamp((y - h)*0.45, step_m*0.5, 30)` + 8 bisection steps, no physics engine).
* **Water shader** (`water.gdshader`, one 4-triangle plane of 6 km, `blend_mix`, **no screen or depth texture reads**, so no extra full-screen copy pass; disabling it changes frame time by < 0.3 ms `[T]`): body colour from the depth raster and the shore-distance field (`deepness = max(1 - exp(-depth*absorb), smoothstep(1, 12, shore))`), three scrolling normal layers (calmer near the shore), analytic sky reflection with Schlick Fresnel plus sun glitter from `atm_sun_dir / atm_sun_color / atm_sky_*`, pulsing foam band and lace at the waterline, fog of war. Ship wakes are `wake` foam quads (FX), never a depth-copy effect. `WATER_LOW` keeps one normal layer and drops the lace.
* **Terrain LOD:** none. At the 34-84 m camera the whole 524 k-triangle terrain is cheap; the budget goes to shadows and MSAA instead `[T]`. Chunk frustum culling is the only culling.
* **Decor** (all placement from terrain ids, flags and the `deco` byte, so every client draws the same scatter). Trees only on FOREST cells (id 8; 1-4 per cell from `deco` bits, conifers above 8 m or in the arctic biome), rocks on ROCK, CLIFF and MOUNTAIN cells (larger on cliffs), boulders from `neutrals` entries of kind NK_SCENERY (`w`x`h` cells, mesh = `variant`) plus one small rock on any other `SF_BLOCK` cell, reeds on SHALLOW cells with `shore_dist <= 1` (temperate and tropical only), crystal / scrap clusters on every cell with `deposit_max > 0` (scale `0.35 + 0.65*deposit_fraction`, hidden at 0, updated from `drain_deposit_changes`), and **urban blocks** on URBAN_BLOCK cells (id 12): one building per merged rectangle of at most 3x3 cells, height `6 + (deco & 7)*0.7` m (6.0 .. 10.9 m, inside the near-plane rule of §5.4), three variants (office block, apartment slab, warehouse), lit windows at night (`atm_night`); the sim treats these cells as impassable and LOS-blocking (`vis_h 2`), so the picture agrees with pathing. **Never on open ground, road, pavement, ford, beach or deep cells.** Instances bucketed into `decor_groups²` MultiMeshInstance3D (a MultiMesh is culled as ONE AABB): 4-6 per side = 56-94 MultiMeshes, 1.3-0.76 Mprims/frame vs 5.4 for one global MultiMesh `[T]`. Wind sway in the vertex shader (world-space gust, also in the shadow pass). Regroup costs 1-3 ms.
* **Scorch/tread layer.** RGBA8 overlay (`scorch_res` 512/1024), stamps 14/28/56 px picked by `radius_m*2*px_per_m`; `paint` 2-4 µs; `flush()` at ≤ 2 Hz (0.65-1.2 ms). Tread marks: `paint_tread(a, b, 1.1 m)` per vehicle every 1.2 m of travel while in view on non-road ground; no decal nodes anywhere (Decal does not render in Compatibility and costs +0.3-1.4 ms at 64-1024 decals `[T]`).
* **Minimap source.** One texel per cell: palette colour × hillshade (`shade = clamp(0.55 + 0.75*N·L, 0.35, 1.3)` with `L = (-0.55, 0.75, -0.45)`), water by `shore_dist/40`; baked once per map (21-42 ms at 192²; deposit cells gold, re-tinted when depleted via `update_deposits`) and shown with `minimap_fog.gdshader` (same fog textures as the world). Unit dots and the camera frustum quad are drawn by the UI from `ViewWorld.entity_world_pos` and `camera.visible_ground_rect()`. An optional SubViewport minimap is not built (+3.5 ms, 456 draws `[T]`). The pre-match map preview (lobby, before any `ViewWorld` exists) uses `MapImages.minimap_image` of terrain_movement.md 3.9; the in-game texture is baked by `ViewMinimapSource` so that hillshade, mood palette and fog shader agree with the world.

### 5.6 Atmosphere, moods, shadows

* **Sun.** `to_sun = (cos(el) sin(az), sin(el), cos(el) cos(az))`, `sun.basis = Basis.looking_at(-to_sun, UP)`; `atm_sun_color = linear(sun_color) * sun_energy`. Sky: `ProceduralSkyMaterial`, `Sky.process_mode = PROCESS_MODE_QUALITY`, `radiance_size = 128` (AUTOMATIC selects INCREMENTAL = per-frame work). Ambient from sky, reflections from sky, no baked GI, no probes (`atm_*` globals fake reflections in water/terrain).
* **Post.** ACES tonemap (AGX costs −0.2 ms, kept as option), exposure/white point from the mood, glow `SOFTLIGHT` with `hdr_threshold` **above lit-terrain brightness** (else explosions get a milky plate `[F]`; for FX-heavy moods threshold 1.0-1.15 with `glow_hdr_scale 2`, FX HDR cores 3-9), SSAO, exponential fog with aerial perspective, a 256-px `GradientTexture1D` colour-correction LUT `out = lift*(1-x) + gain*x^(1/gamma)` per channel (split toning).
* **Shadow fit** `fit_shadows(H, pitch, fov, aspect)`: `a_bot = pitch + fov/2`, `a_top = clamp(pitch - fov/2, 8°, 89°)`; `far_depth = H/sin(a_top)*cos(a_top - pitch)`; `directional_shadow_max_distance = far_depth*(1 + 0.05*aspect) + 12`; splits `0.16/0.38/0.68`, blend on, `shadow_bias 0.04`, `normal_bias 1.4`, `fade_start 0.9`. Results: 89 m at H = 34, 114 m at 54, 141 m at 84. Re-run when `view_changed` fires. Aircraft shadows are real (16 m altitude at 40° sun elevation displaces the shadow 19 m: strong altitude cue); on LOW a blob shadow with alpha `1 - alt/40` is used.
* **Moods** (`moods.json`): `MapData.biome` 0 -> `temperate_day`, 1 (desert) -> `arid_dusk`, 2 -> `arctic_day`, 3 (tropical) -> `tropical_day`; `MapData.family == 1` (urban) with biome 0 and `night_allowed` -> `urban_night`; `ViewBuildOptions.mood` overrides everything. `temperate_day` and `arid_dusk` use the numbers of the spike (`[T]` `view_mood_def.gd`); starting values for the three new moods (to be tuned with the screenshot loop of §10.4, ≥ 3 rounds):

| Field | arctic_day | urban_night | tropical_day |
|---|---|---|---|
| sun el / az | 22° / 200° | 35° / 40° (moon) | 58° / 215° |
| sun colour × energy | (0.85, 0.90, 1.0) × 1.35 | (0.55, 0.65, 1.0) × 0.45 | (1.0, 0.94, 0.82) × 1.65 |
| sky top / horizon | (0.32, 0.52, 0.86) / (0.80, 0.88, 0.96) | (0.02, 0.04, 0.12) / (0.08, 0.10, 0.20) | (0.14, 0.44, 0.86) / (0.72, 0.87, 0.95) |
| ground horizon / bottom | (0.75, 0.80, 0.86) / (0.55, 0.60, 0.66) | (0.05, 0.06, 0.10) / (0.02, 0.02, 0.04) | (0.55, 0.68, 0.62) / (0.20, 0.28, 0.24) |
| ambient energy | 0.95 (snow bounce) | 0.35 (cool) | 0.85 |
| fog colour / density / aerial / sun scatter | (0.78, 0.86, 0.95) / 0.0016 / 0.40 / 0.25 | (0.06, 0.08, 0.16) / 0.0022 / 0.50 / 0.05 | (0.70, 0.86, 0.90) / 0.0014 / 0.45 / 0.30 |
| exposure / white point | 1.10 / 5.0 | 1.35 / 4.0 | 1.12 / 5.0 |
| saturation / contrast | 0.92 / 1.05 | 1.10 / 1.10 | 1.22 / 1.05 |
| lift / gamma / gain | (0.02, 0.03, 0.05) / (1, 1, 1.03) / (0.97, 1.0, 1.04) | (0.02, 0.03, 0.06) / (1, 1, 1.02) / (0.95, 0.98, 1.05) | (0.008, 0.020, 0.020) / (1, 1, 1) / (1.03, 1.0, 0.94) |
| glow intensity / threshold | 0.50 / 1.05 | 0.90 / 0.85 | 0.45 / 1.15 |
| ssao intensity, cloud strength | 1.3, 0.10 | 1.8, 0.05 | 1.5, 0.22 |
| water shallow / deep / absorb | (0.30, 0.62, 0.68) / (0.05, 0.20, 0.36) / 0.55 | (0.05, 0.18, 0.26) / (0.01, 0.04, 0.10) / 0.6 | (0.10, 0.74, 0.70) / (0.02, 0.24, 0.44) / 0.34 |
| terrain palette | snow-dominant: grass (0.30, 0.40, 0.28)/(0.45, 0.55, 0.38), dirt (0.28, 0.24, 0.20)/(0.40, 0.35, 0.30), rock (0.32, 0.34, 0.38)/(0.55, 0.57, 0.62), sand (0.70, 0.68, 0.62)/(0.84, 0.82, 0.76), snow (0.94, 0.97, 1.0) | dark, blue-shifted asphalt-rich: grass (0.14, 0.22, 0.12)/(0.20, 0.30, 0.16), dirt (0.20, 0.16, 0.13)/(0.28, 0.23, 0.19), rock (0.22, 0.22, 0.24)/(0.34, 0.34, 0.38) | lush: grass (0.14, 0.44, 0.12)/(0.28, 0.64, 0.20), dirt (0.42, 0.30, 0.18)/(0.60, 0.44, 0.28), rock (0.42, 0.40, 0.38)/(0.62, 0.60, 0.56), sand (0.86, 0.78, 0.58)/(0.95, 0.90, 0.72) |
| `night` / `wet` / decor kit | 0 / 0.1 / conifers | 1.0 / 0.6 (roads reflect the sky) / lamp posts + rubble | 0 / 0.25 / palms + broadleaf |

`night = 1` multiplies unit/structure/decor emissive by `1 + 1.2*atm_night` and adds street-lamp emissive props in `ViewDecor` (no dynamic lights). Compatibility uses `compat_grade` (its ambient/ground come out much darker and its look brighter/bluer `[M][T]`).

### 5.7 Fog-of-war pipeline

Sim side (sim_core 3.3 `SimFogApi`, replaced by the vision domain in `init_world`, abilities.md 5.9): `world.fog.fog_bytes(pid)` = `w*h` bytes `0 shroud / 1 fog / 2 visible`, `fog_version(pid)` increments on change (vision stride 2 -> ≤ 10 Hz); shared vision is already folded into the pid's bytes. View side:

1. `sync(api, pid)`: if `api.fog_version(pid) != last`, `submit(api.fog_bytes(pid))`: `cur = 1 - cur; Image.set_data(w, h, false, FORMAT_R8, bytes); tex[cur].update(img); blend = 0; publish fow_curr/fow_prev` (4-12 µs at 192²; 256² = 64 KB). The byte array is read-only for the view (copy-on-write in `set_data`).
2. Every frame `advance(dt)`: `blend = min(1, blend + dt/0.1)` -> `fow_blend`. Shaders `texelFetch` the 4 nearest cells of both textures, bilinear on the decoded booleans, `smoothstep(0.32, 0.68, s + noise*0.35)` for organic edges. Terrain: shroud black, fog `mix(luma, albedo, 0.45)*0.42` scaled by `fow_fog_dim`, visible untouched; positions outside `fow_rect` read as shroud (the void skirt of §5.5). Cost 0.1-0.4 ms GPU.
3. `rules.fog_mode` (sim_core 4.11): 2 (shroud + fog) is the default; 1 (explored-stays-visible) uses the bytes as they are with `fow_fog_dim = 0`, so explored terrain is drawn undimmed while unexplored terrain stays black; 0 (none) and observers upload an all-2 texture once (`set_mode(0)` / `set_enabled(false)`). Replays and observers: `set_local_player(pid | -1)` switches the pid whose bytes are shown.
4. Unit shaders do **not** hide by fog (CPU visibility of §5.3 is authoritative because the sim's visibility is cell-exact, while the shader smooths across cells and would disagree at edges); only `UF_FOG_DIM` reads the **nearest-cell** state for neutral structures.

---

### 5.8 Procedural model toolkit

#### 5.8.1 Build pipeline (`ViewModelBuilder.get_model(recipe_id, style_id, scale_bp)`)

```
key      = recipe_id + "@" + style_id + "#" + scale_bp                        cache key
recipe   = book.recipe(recipe_id)          (missing/invalid -> placeholder box sized by size_class + Log.warn once)
style    = book.style(style_id)            (extends chain merged; palette, material, kit, slots)
arch     = book.archetype(recipe.archetype)
params   = recipe.params  (+)  style.kit  (+)  arch.defaults       # left wins; unknown recipe params are errors
scope    = slots for params, palette colours, `derive` lets, PI, TAU; structures additionally get the footprint anchors of `footprints.json` (§7.3): `fw, fh, door_cx, door_cz, exit_dir, dock_cx, dock_cz, dock_dir, pads_n` (metres from the footprint centre, +Z south; §7.3) and the functions `pad_x(i)`, `pad_z(i)` (0 outside 0..pads_n-1)
seed     = fnv1a32(recipe_id) xor fnv1a32(style_id)                          # same look on every client
b        = ViewMeshBuilder.new(); b.seed_rng(seed); b.default_bevel = recipe/arch bevel
run: arch.ops  (slots resolved: recipe.slots > style.slots > arch default)  then recipe.ops_after
b.model_scale = recipe.scale * arch.scale * scale_bp/10000        # arch.scale: 1.25 for the inf_* archetypes (RTS readability), 1.0 otherwise
mesh = b.build(key); info = b.info(); info.content_hash = fnv1a(vertex bytes)
```

Pure function of (recipe, style, scale): no engine singletons except `RandomNumberGenerator` (local) and `Geometry2D.convex_hull`, so builds run on `WorkerThreadPool` and finalise (ArrayMesh creation) on the main thread in `pump(budget_ms)`. Cost `[M]`: 0.7 µs/vertex, tank 9.9 ms, APC 6.1, howitzer 8.4, squad 3.3, gunship 4.9, boat 2.5, factory 6.3 (2x under load); interpreter overhead ≈ +25 % (RPN expressions, ~2400 evaluations per tank). A 4-player match needs ~100 models = 0.6-1.0 s single-threaded, ~0.25 s on 4 threads; worst case (8 different rosters, ~280 models) ~2 s single / ~0.6 s threaded, hidden behind the loading screen. Optional disk cache `user://cache/models/<content_key>.res` (`ResourceSaver`), keyed by FNV-1a of the canonical recipe+archetype+style JSON and `ViewMeshBuilder.VERSION`; enabled only if `pump` time exceeds 1.2 s on the reference low-end machine (task VIEW-M10), invalidation by key so a stale entry is impossible.

#### 5.8.2 Size and budget discipline (enforced by `test_view_recipes`)

| Class | Footprint / extent (m) | Height | LOD0 tris | LOD1 tris | Notes |
|---|---|---|--:|--:|---|
| squad (`inf_*`) | disc ≤ 1.9 (x1.25 scale) | ≤ 1.6 | ≤ 1.4 k | ≤ 0.8 k | 1-4 members |
| light vehicle | 3.4 x 1.9 | ≤ 2.0 | ≤ 3.5 k | ≤ 2.0 k | radius 1.35 m |
| medium vehicle / tank | 3.6 x 2.0 | ≤ 2.4 | ≤ 5.0 k | ≤ 2.8 k | `[M]` tank 4750 -> 2650 |
| heavy / siege | 4.8 x 2.6 | ≤ 2.9 | ≤ 6.5 k | ≤ 3.6 k | radius 2.4 m |
| huge (walker, Leviathan) | 7.0 x 4.6 | ≤ 5.0 | ≤ 8.0 k | ≤ 4.5 k | |
| fixed-wing | span ≤ 6 | ≤ 1.6 | ≤ 3.0 k | ≤ 1.7 k | altitude via `meta.hover` |
| helicopter / tiltrotor | fuselage ≤ 4.5, rotor ≤ 5.2 | ≤ 2.6 | ≤ 3.5 k | ≤ 2.0 k | |
| patrol boat / small ship | 5 x 2 | ≤ 2.6 | ≤ 2.0 k | ≤ 1.2 k | |
| escort / submarine | 9-10 x 3 | ≤ 4.5 | ≤ 5.0 k | ≤ 2.8 k | |
| large ship (siege, carrier) | 12-13 x 4.6 | ≤ 5.5 | ≤ 8.0 k | ≤ 4.5 k | |
| structure 1x1 / 2x2 | (fw x fh)*3 - 0.5 | ≤ 8 | ≤ 3.0 k | ≤ 1.7 k | |
| structure 3x3 / 4x3 / 4x4 (HQ) / 6x3 / 6x4 (airfield) | idem | ≤ 12 | ≤ 5.0-8.0 k | ≤ 2.8-4.5 k | footprints differ between the specs (R5); the recipe fits whatever `fw, fh` it is given |
| superweapon 4x4 | 11.5 x 11.5 | ≤ 14 | ≤ 10.0 k | ≤ 5.5 k | 14 m cap keeps it inside the camera near-plane rule (§5.4) |

Vertex cap 65 535 (16-bit indices); per-model VRAM ≤ 900 KB; resident total ≤ 120 MB (`[M]` ~110 MB for 250 models at full detail; `ARRAY_FLAG_COMPRESS_ATTRIBUTES` untested: measured in VIEW-M10 before adoption). Tier policy: tier 0 = essential mass, tier 1 = detail (LOD0+LOD1), tier 2 = micro detail (LOD0 only); tier-2 primitives ≤ 35 % of LOD0 triangles. Team-masked area (top-projected) must be 4-12 % of the model. Build time budget ≤ 20 ms per model single-threaded (warn > 20, fail > 60).

#### 5.8.3 The op language (recipe and archetype `ops` arrays)

An `ops` array is executed top to bottom. A **primitive op** is an array `[name, args…]`, a **block op** is an object. Every numeric slot accepts a JSON number **or a string expression**; vectors are arrays of numeric slots; colour slots accept a palette key (`"base"`), `"#rrggbb"`, `"dark*1.2"` or `"mix(base,acc,0.3)"`; a colour string that is none of these is compiled as an *expression* whose string result is parsed the same way (`"i % 2 == 0 ? 'base' : 'sec'"`). Errors carry the op path (`unit.napc.guardian_tank/ops[14]/for[3]/box`) and abort the build (placeholder used, `Log.error`).

*Expressions (`ViewExpr`)*: numbers, identifiers (params, palette-free lets, loop vars, `PI`, `TAU`), `+ - * / %`, unary `-`, comparisons, `and or not`, ternary `c ? a : b`, string literals in single quotes with `==`/`!=`, parentheses. Functions: `min max abs sqrt sin cos tan atan2 floor ceil round sign fract clamp lerp pow deg rad rnd(n)` (`rnd(n)` = deterministic hash of `(seed, n)` in [0,1); model recipes must be deterministic, so `rand()` is not available to them). Division by zero yields 0 and a validator warning. Compiled once per string to RPN with variables bound to frame slots at compile time (no dictionary lookups at run time).

| Op (JSON) | Builder call | Notes |
|---|---|---|
| `["brush", col, mat?, team?]` | `brush` | `mat` ∈ paint (default), metal, glass, rubber, emissive; `team` 0..1 or `true` (= 1: surface takes the player colour) |
| `["ao", v]`, `["bevel", v]`, `["jitter", v]`, `["seed", n]` | fields | `ao` 0..1 baked occlusion (quantised 4 bit) |
| `["box", c, size, bevel?]` | `box` | |
| `["tbox", c, size_bottom2, size_top2, height, shift2?, bevel?]` | `tapered_box` | |
| `["extrude", [[x,y],…], x0, x1, bevel?]` | `extrude` | CONVEX profile, x forward |
| `["prism", ["ngon", c, rx, rz, n, rot], ["ngon", c2, rx2, rz2, n, rot], bevel?]` or point lists | `prism` | turrets, boat hulls |
| `["pocket", c, size, [[x,y,w,h],…], depth]` | `pocket_box` | louvres, skylights |
| `["lathe", from, to, [[r,d,wear],…], segs?, smooth?]` | `lathe` | |
| `["cyl", from, to, r, segs?, bevel?, caps?]`, `["frustum", from, to, r0, r1, segs?, caps?]`, `["dome", base, up, r, h, segs?, rings?]` | `cylinder/frustum/dome` | |
| `["wheel", c, r, w, tyre, hub, detail?, segs?, animated?]` | `wheel` | WHEEL part, `extra = r` |
| `["track", x, width, [[z,y,r],…], thickness?, samples?]` | `track_belt` | TRACK part |
| `["greeble", c, normal, u_half, v_half, count, smin, smax, hmin, hmax, cylp?]` | `greebles` | tier ≥ 1 |
| `["socket", name, pos, dir, part?, pivot?]` | `socket` | e.g. `muzzle0_0`, `exhaust0`, `weld0`, `door_exit`, `top`; with `part` (name) and no `pivot`, the pivot / param / extra / trunnion of the **last `part` block of that kind** in this build are reused, so a muzzle socket declared after the turret block still rotates, recoils and elevates with it |
| `["member", i, n]`, `["scale", s]`, `["tier", n]` | fields | `member` tags following gait parts with (index, count) |
| `["meta", key, value]` | `ViewModelInfo` | `hover`, `motion`, `members`, `footprint`, `wreck`, `death` (`{kind, ticks}`, §5.9.4), `buildup_ticks` (§5.2), `spawn_fx` (fx id played on `SPAWNED`, §6.2.2) |
| `{"let": {"a": expr, …}}` | scope | ordered |
| `{"for": "i", "n": expr, "do": [ops]}` | loop | `n` ≤ 64 |
| `{"if": expr, "then": [ops], "else": [ops]}` | branch | |
| `{"switch": expr, "cases": {"modules": [ops], …}, "default": [ops]}` | branch | string or number keys |
| `{"mirror_x": [ops]}` | `mark` + ops + `mirror_x` | pivots mirrored |
| `{"push": {"pos": v, "euler": v}, "do": [ops]}` | `push/pop` | euler in degrees |
| `{"part": {"kind": name, "pivot": v, "param": e, "extra": e, "trunnion": [y,z]}, "do": [ops]}` | `set_part` … restore | previous part state restored after the block |
| `{"call": name, "args": {…}}` | native macro | §5.8.5 |
| `{"slot": name}` | inline op list | resolution: `recipe.slots[name]` > `style.slots[name]` > `arch.slots[name]` > nothing |

Loop and depth limits: `for` nesting ≤ 3, total executed primitives ≤ 4000, op-list depth ≤ 8 (validator).

#### 5.8.4 Faction identity, palettes and team colour

* **Style = palette + material + kit + slots.** Palettes come from the bible's `visual_direction`; sRGB hex; keep paint albedo in 0.3-0.5 luma (brighter overexposes under ACES: pastel `[T]`).

| Style | Palette (bible) | Signature kit (from `visual_direction`) |
|---|---|---|
| `napc` | olive `#4d592e`, cream `#d6c799`, rescue orange `#ed5e0f` | broad hulls, **modular armour skirts**, visible crew cabins (glazed cabs), orange hazard bands, round hatches |
| `nec` | slate blue `#455c80`, white `#e6ebf0`, amber `#f29e1a` | low profiles, angular hex turrets, **fold-out sensor masts** (`SLIDE_Y`), amber lamps |
| `olm` | ivory `#d9caa6`, copper `#b3663a`, deep teal `#0f4d54` | **heat shields** (copper fin stacks on turrets), **fabric screens** (drape panels), **articulated wheels** (swing-arm wheel pods) |
| `def` | oxide red `#8c3826`, gray `#4d4f52`, pale yellow `#e0d180` | **slab armour**, **exposed running gear**, **standardised containers** on decks |
| `pd` | ocean blue `#1a5c99`, coral `#f27352`, white `#edf0f2` | **sealed hulls** (smooth, few greebles), **folding flight surfaces** (`DEPLOY_Z`), **deck-mounted drones** |
| `han` | jade `#337a5c`, crimson `#b31f29`, porcelain `#ebe6d6` | compact modular hulls, **sensor crowns** (antenna rings), **drone racks** |
| `ae` | ochre `#b38029`, charcoal `#292b2e`, bright cyan `#1acce6` | **repairable panels** (bolted plates, contrasting cyan replacements), **reinforced wheels**, **interchangeable weapon modules** (mount plates) |
| `sap` | sand `#c2a875`, indigo `#292666`, saffron `#f5990f` | **layered armour**, **deployable braces** (`DEPLOY_Z` outriggers), **prominent interception sensors** (dishes, ball sensors) |

* Subfaction styles (`napc.usa`, `napc.canada`, …) `extend` the parent and change only `palette.acc/sec` trim, `emblem`, and 1-2 kit values so subfactions read as siblings (emblems are abstract geometric marks such as bar, chevron, notch, ring or wedge; never a real-world flag, crest or logo, QA checklist V-IP1); they add no geometry except their unique units.
* **Team colour.** Only surfaces with `team_mask` > 0 take the player colour (front band, roof stripe, rear plate, squad jackets, flags, launcher tips): the faction paint stays recognisable. The `team_panel` macro always emits a dark `plate` border 2 cm wider under the team surface so a red team on DEF oxide hulls (or orange on NAPC) still separates `[M]` pitfall 7. 12 player colours in `ViewTeamColors`, indexed by the lobby colour id of `net.md` 7.2 and `SimPlayer.color` and equal to the lobby swatches (sRGB hex): `0 crimson #D93A3A`, `1 azure #2F7DE1`, `2 emerald #2DB56A`, `3 amber #F2B234`, `4 violet #8B5CD6`, `5 cyan #27C4D6`, `6 orange #F0782A`, `7 magenta #D9479B`, `8 lime #9BD13B`, `9 slate #8A97A8`, `10 brown #8C5A3B`, `11 white #ECECEC` (ids 12-15, allowed by `SimPlayerSlot.color`, reuse 0-3 lightened by 25 %). Colour-blind modes (`ViewTeamColors.set_mode`, §5.12) swap the first eight for an Okabe-Ito based set; `contrast_against(color, palette)` helper flags collisions in tests. The same colour drives selection rings, minimap dots and health-bar pips.
* **Shared service units and shared structures** use the **owner's** style (`style_for_def`), so a player's Collector, Engineer, MCV, Landing Transport, HQ, Refinery, Barracks… all wear their faction. Neutral structures use style `neutral` (grey concrete, hazard yellow); neutral ownership (`owner = -1`) uses the team colour `(0.62, 0.62, 0.60)`.

#### 5.8.5 Native macros (`ViewRecipeMacros`, `ViewMacrosStructures`; args by name)

| Group | Macro (args) |
|---|---|
| Common | `hatch(c, r, body, ring)`, `whip(base, tip, r, col)`, `team_panel(center, size, col?)`, `light_pair(center, spacing, size, col)`, `vent(center, size, slats)`, `pipe(from, to, r, col)`, `greeble_patch(center, hu, hv, count)`, `hazard_stripes(center, size, n)` |
| Running gear | `track_run(x, width, z_front, z_rear, sprocket_r, road_n, road_r, tk)`, `wheel_row(x, z0, z1, n, r, width, detail)`, `axles(x, zs, r, width, arch)`, `swing_wheels(x, zs, r)` (OLM), `crawler_pods(…)` (siege crawlers), `hover_skirt(len, wid, h)` |
| Hull & armour | `hull(profile, half_w, bevel)` (`wedge, slab, boxy, boat, walker`), `skirt(kind, x, y, len, h)` (`modules, slab, cage, fabric, layered, none`), `plates(kind, …)` (`bolted` for AE), `container(center, size, col)`, `mount_plate(center, size)` |
| Weapons | `turret_ngon(pivot, n, rot, hw, hl, h, top, shift, y0, mount)`, `gun(mount, y, z, len, r, muzzle)` (`plain, brake, sleeve, coil, prism, bore, twin, gatling`), `rws(center, mount)`, `missile_rack(center, cols, rows, elev, mount)`, `rocket_pods(center, cols, rows)`, `launcher_tube(center, len)`, `flak_twin(center)`, `dome_emitter(center, r)`, `spade_pair(z, x)` (DEPLOY), `outriggers(z, span)` (DEPLOY_Z) |
| Sensors | `sensor_mast(base, h, folded)` (SLIDE_Y), `sensor_crown(center, n, r)`, `radar_dish(center, r, spin)` (RADAR), `ball_sensor(center, r)` |
| Infantry | `soldier(x, z, phase, member, count, kit, helmet)`, `squad(n, layout, kits)`; kits: `rifle, hmg, shield, launcher, tripod, medic, radio, scope, tool, breach, torch, hook`; helmets: `round, angular, cap, wrap` |
| Air | `fuselage(profile)`, `wing(span, chord, sweep, thick, fold)` (fold = DEPLOY_Z), `rotor_main(hub, blades, radius, chord)` (ROTOR), `rotor_tail(pos)`, `tilt_nacelle(pos, r)`, `nozzle(pos, r)`, `gear(pos)`, `drone_body(…)` |
| Ships | `hull_ship(len, beam, draft, bow, freeboard)`, `superstructure(len, wid, tiers)`, `vls(center, rows, cols)`, `ship_turret(pos, barrels, mount)`, `flight_deck(len, wid)`, `deck_drones(n)`, `sail(pos, h)` (sub) |
| Structures | `foundation(fw, fh, depth)`, `wall_block(c, size, sec)`, `roller_door(center, w, h, slats)` (DOOR), `window_strip(c, n, size)` (emissive), `stack(c, r, h, cap)`, `silo(c, r, h)`, `crane(c, reach)` (SLIDE_Y/DEPLOY), `pad(c, size, mark)`, `dome_shell(c, r)`, `pylon_ring(c, r, n)`, `launch_rail(c, len, elev)`, `silo_cluster(c, n)`, `turret_base(c, r)` |

Adding a macro is a code change (VIEW-M2/M3); adding a look is a JSON change. Both must keep the tier / part / brush state balanced (interpreter restores brush after `call`).

#### 5.8.6 Archetype catalogue (56 files under `game/data/recipes/archetypes/`)

Balance archetype (`global.json → unit_assignments`) -> view archetype -> what varies by recipe/style. Sizes are targets of §5.8.2.

| View archetype | Balance archetypes | Motion | Animated parts | Key params (default) |
|---|---|---|---|---|
| `inf_rifle` (15) | inf_line | foot | LEG/ARM/BODY_BOB | `n` 4, `kit` rifle\|hmg\|shield, `helmet`, `pack` |
| `inf_at` (8) | inf_at | foot | same | `n` 3, `launcher` tube\|tripod\|twin |
| `inf_support` (8) | inf_support | foot | same | `n` 2, `gadget` medic\|radio\|scope\|tool\|echo\|shield |
| `inf_special` (6) | inf_combat_spec | foot | same | `n` 3, `gear` breach\|pioneer\|sapper\|torch\|hook |
| `inf_engineer` (1) | service.engineer | foot | same | `n` 1, toolbox, orange helmet |
| `veh_apc` (10) | veh_scout | wheeled | WHEEL, TURRET/BARREL (RWS), RADAR | `axles` 3, `cab` glazed\|armoured, `roof` rws\|radar\|drone_rack\|mast\|open, `bed` |
| `veh_amphib` (6) | veh_scout + amphibious | amphibious | TURRET, waterjet spin | `float` skirt\|pontoon\|hover, `roof` |
| `veh_lightarty` (3) | arty_light | wheeled | WHEEL, DEPLOY | `chassis` truck\|buggy\|skimmer, `payload` mortar\|rocket_pod |
| `veh_tank` (15) | mbt_t1, mbt_t2, mbt_t2_rail | tracked | TRACK, WHEEL, TURRET, BARREL (+TURRET1/BARREL1 for secondary) | full spike parameter set (§7.2), `class` medium\|heavy, `float_skirt` (amphibious) |
| `veh_siege` (10) | siege_ap/he/rail/beam/demo | tracked | TRACK, TURRET, BARREL, DEPLOY | `weapon` twin\|rail\|prism\|siege\|ram\|dome, `treads` tracks\|crawler |
| `veh_aa` (10) | veh_aa, _beam, _flak | tracked | TURRET (elevating), RADAR | `payload` missile\|flak\|laser\|drone_bay |
| `veh_howitzer` (8) | arty_howitzer | tracked | TRACK, TURRET, BARREL (elevation ties to deploy), DEPLOY spades | `gun_len`, `crawler`, `carrier` |
| `veh_rocket` (5) | arty_rocket, arty_missile | tracked/wheeled | TURRET, BARREL elevation, DEPLOY | `pods` grid\|canister\|drone_nest, `unmanned` |
| `veh_walker` (2) | veh_command | tracked (legs) | LEG_A/B (stride 3.2 m), RADAR | 4 legs, cockpit dome, sensor crown |
| `veh_hovercarrier` (1) | veh_assault_carrier | amphibious | DEPLOY ramp, TURRET | skirt, ramp, siege gun |
| `veh_collector` (1) | service.collector | wheeled | WHEEL, SLIDE (scoop), bin fill `u_aux.y` | `scoop` |
| `veh_mcv` (1) | service.mcv | tracked | TRACK, DEPLOY (hint) | boxy fold-up HQ silhouette |
| `veh_landing` (1) | service.landing_transport (built at the Dock) | naval | ramp DEPLOY_Z | landing craft |
| `air_jet` (10) | air_fighter | air_fixed | BLINK, nozzle glow | `wing` delta\|swept\|forward, `tail` single\|twin, `fold` |
| `air_heli` (4) | air_gunship | air_hover | ROTOR, TAIL_ROTOR, TURRET (chin) | `rotors` main+tail\|coax\|tilt, `stubs` |
| `air_bomber` (3) | air_bomber | air_fixed | BLINK | `plan` flying_wing\|heavy\|drone |
| `air_drone` (1) | air_drone | air_hover | ROTOR (4 small) | pods |
| `air_ew` (1) | air_ew | air_fixed | RADAR (radome) | disc |
| `ship_patrol` (8) | ship_patrol | naval | RADAR, TURRET | `bow`, `cabin`, `gun` |
| `ship_escort` (9) | ship_escort | naval | RADAR, TURRET x2 (mount 0 gun, mount 1 AA) | `vls`, `helipad` |
| `ship_siege` (5) | ship_siege | naval | TURRET, DEPLOY | `battery` guns\|missile_cells |
| `ship_carrier` (3) | ship_carrier | naval | SLIDE (pods), BLINK | `deck`, `deck_drones` |
| `ship_sub` (1) | ship_sub | sub | RADAR mast | `sail` |
| Structures (15) | `str_headquarters, generator, refinery, barracks, factory, dock, radar, airfield, laboratory, watchtower, at_turret, aa_battery, relay, defense_adv, superweapon` | static | RADAR, DOOR, SLIDE, BLINK, TURRET/BARREL (defenses), DEPLOY | `fw`, `fh`, `height`, `roof`, `door` side, per-faction `kit` |
| Others (13) | `sum_uav, sum_balloon, sum_cargo, sum_drone_swarm, sum_capsule, sum_engine, sum_station, sum_cover, neu_building, proj_missile, proj_bomb, proj_torpedo, proj_rocket` | – | – | – |

#### 5.8.7 Unit -> archetype assignment (generated into `assignments.json`; `tools/py/gen_recipe_stubs.py` reads it)

`inf_rifle`: ae.civic_rifle_team, ae.union_guard, def.fortress_guard, def.line_conscript, han.banner_infantry, han.canopy_ranger, napc.rifle_squad, napc.vanguard_rifle_squad, nec.jager_squad, olm.gate_guard, olm.wayfarer_guard, pd.island_raider, pd.ranger_marine, sap.river_marine, sap.shield_rifle_squad · `inf_at`: ae.pike_team, def.recoil_team, han.lance_team, napc.javelin_team, nec.spike_team, olm.needle_team, pd.harpoon_team, sap.kavach_team · `inf_support`: def.echo_team, def.signal_officer, han.link_operator, han.mekong_field_engineer, napc.combat_medic, olm.mirage_observer, pd.reef_technician, sap.watchpost_recon_team · `inf_special`: ae.reclaimer, ae.river_warden, napc.aguila_breach_team, nec.alpine_pioneer, nec.sapper, sap.combat_pioneer · `inf_engineer`: shared.engineer · `veh_apc`: ae.mamba_apc, def.mule_apc, def.steppe_recon_carrier, han.jade_carrier, han.lotus_drone_tender, napc.pathfinder_apc, nec.surveyor_apc, olm.caravan_apc, olm.dune_rover, sap.jackal_apc · `veh_amphib`: ae.okapi_amphibious_carrier, napc.beaver_amphibious_apc, nec.fen_recon_carrier, pd.kancil_landing_skimmer, pd.wake_skimmer, sap.naga_amphibious_carrier · `veh_lightarty`: han.reed_rocket_skimmer, olm.sandglass_mortar, olm.scorpion_rocket_buggy · `veh_tank`: ae.buffalo_tank, ae.rhino_rail_tank, def.hammer_tank, def.ural_assault_tank, han.imperial_guard_tank, han.ox_tank, napc.guardian_tank, napc.narwhal_amphibious_tank, nec.leopard_tank, nec.marte_heavy_mbt, olm.sirocco_tank, pd.shinano_adaptive_tank, pd.tide_tank, sap.arjun_assault_tank, sap.bulwark_tank · `veh_siege`: ae.kiln_assault_crawler, def.bear_siege_crawler, def.colossus_siege_tank, napc.bastion_heavy_tank, nec.argent_rail_tank, nec.charlemagne_siege_tank, olm.ifrit_prism_tank, olm.sunlance_beam_tank, sap.elephant_siege_tank, sap.gaj_siege_platform · `veh_aa`: ae.lagos_drone_guard, ae.weaver_aa, def.porcupine_aa, han.firefly_aa_drone, napc.sentinel_aa, nec.rapier_aa, olm.crescent_aa, olm.dawn_laser_aa, pd.storm_aa, sap.vajra_aa · `veh_howitzer`: ae.forge_howitzer, ae.protea_gun_carrier, napc.paladin_howitzer, nec.archer_spg, nec.ibex_crawler_gun, pd.breaker_howitzer, pd.outrider_howitzer, sap.monsoon_howitzer · `veh_rocket`: def.anvil_rocket_battery, def.saker_missile_truck, han.nest_rocket_drone, nec.fjord_missile_carrier, sap.shaheen_missile_battery · `veh_walker`: han.dragon_command_walker, han.long_command_walker · `veh_hovercarrier`: pd.leviathan_assault_carrier · `veh_collector`/`veh_mcv`/`veh_landing`: shared.collector / shared.mobile_construction_vehicle / shared.landing_transport · `air_jet`: ae.sunbird_interceptor, def.kite_interceptor, han.swallow_interceptor, napc.falcon_interceptor, napc.raptor_multirole_fighter, nec.kestrel_interceptor, olm.shrike_interceptor, pd.petrel_fighter, pd.wedge_recon_fighter, sap.garuda_interceptor · `air_heli`: ae.hammerhead_gunship, napc.titan_gunship, pd.osprey_strike_tiltrotor, sap.sarus_gunship · `air_bomber`: def.burya_bomber, han.silkwing_drone_bomber, napc.condor_stealth_bomber · `air_drone`: olm.nightjar_strike_drone · `air_ew`: nec.aster_ew_aircraft · `ship_patrol`: ae.delta_patrol_boat, def.picket_boat, han.canal_patrol_boat, napc.riverwatch_patrol_boat, nec.skerry_patrol_boat, olm.corsair_patrol_boat, pd.reef_patrol_boat, sap.estuary_patrol_boat · `ship_escort`: ae.anchor_escort, def.rampart_escort, han.jade_escort, napc.aegis_frigate, nec.horizon_escort, olm.lantern_escort, olm.strait_frigate, pd.trident_escort, sap.shield_escort · `ship_siege`: ae.sovereign_arsenal_ship, napc.liberty_arsenal_ship, nec.concord_monitor, olm.beacon_missile_ship, sap.citadel_monitor · `ship_carrier`: han.emperor_drone_ship, pd.shogun_drone_carrier, pd.tempest_carrier · `ship_sub`: def.boreal_missile_submarine. (Sum = 156 (verified).) Structures: `structure.shared.<x>` -> `str_<x>` (12), `structure.<fac>.<advanced defense>` -> `str_defense_adv` (8, weapon kit per faction), `structure.<fac>.<superweapon>` -> `str_superweapon` (8), `structure.nec.relay` -> `str_relay`. Neutrals and summons are named differently by the concurrently published specs (data_balance.md 7.14 `neutral.civilian_garrison, power_substation, observation_post, salvage_depot, salvage_field`; economy.md 7.5 `neutral.substation, salvage_depot, field_hospital, observation_tower, civilian_garrison, harbor_terminal`; terrain_movement.md 7.3 footprints `neutral.garrison_house, substation, outpost`; summons `summon.<code>.<name>` in data_balance.md 7.7 versus `summon.uav, cargo_aircraft, tempest_drone, dragonfall_capsule, dragonfall_engine, repair_station, decoy_*` in economy.md 7.7), so `assignments.json` maps them by **pattern** (§7.4) to the `neu_building` archetype with one of six kits (`garrison, substation, outpost, depot, hospital, harbor`) and to the summon archetypes (`sum_uav, sum_balloon, sum_cargo, sum_drone_swarm, sum_capsule, sum_engine, sum_station, sum_cover`); decoy summons reuse the archetype of the unit they mimic (`model_role`, e.g. `veh_apc` for `decoy_light_vehicle`) in the owner's style. Any def id without a matching rule gets a stub from `gen_recipe_stubs.py` and a validator warning (V-RCP-02), so a renamed def can never fail silently. Carrier drone wings (combat.md 13-19: Tempest strike, Shogun strike, Shogun interceptor, Emperor strike) use `sum_drone_swarm` kits. Deposits are decor (crystal / scrap clusters), not recipes.

**Total model count:** 156 unit recipes + 29 structure recipes + 6 neutral + ~20 summon/projectile/cover = ~211 recipes -> ~330 built meshes (service units and shared structures x 8 styles), of which a match builds only those its rosters use.

#### 5.8.8 Animation model (all shader-driven; CPU writes ≤ 5 floats per moving entity per frame)

| Family | Parts (kind) and driver | Value semantics |
|---|---|---|
| Wheels | WHEEL, `-u_anim.z/r` | `roll_m` integrated from interpolated motion; reverse motion turns them back |
| Tracks | TRACK (tread scroll `UV.y - roll`) + WHEEL (sprockets, road wheels) | same roll, so belt and wheels never slip |
| Turret / barrel | TURRET/BARREL, `u_anim.w` yaw, `u_aux.x` recoil (travel `extra` m along +Z), `u_aux.w` elevation | recoil kick on `WEAPON_FIRED` (mount and barrel from `muzzle_idx`), decays 0.28 s; secondary mounts via `u_mnt1..3` |
| Rotors / radar / fans | ROTOR, TAIL_ROTOR, RADAR: angle in `u_aux.z`, `angle += spin*dt` | `spin` eased to 0 when parked / unpowered so the phase never pops; 28 rad/s = 27° per frame at 60 fps, below the 45° Nyquist of a 4-blade rotor; only spinning entities in view are written; integration uses `dt * time_scale` (0 while paused) |
| Infantry | LEG/ARM/BODY_BOB: walk cycle phase locked to `roll_m` (stride 0.9 m), `u_anim.y` amplitude; per-member phase offsets; crouch flag; hidden members by hp | members 0..n−1 stay visible while `hp/max_hp > i/n` |
| Deploy / pack | DEPLOY, DEPLOY_Z (spades, outriggers), BARREL elevation ties to deploy, SLIDE (masts) | `u_aux.y` eased over the `duration_ticks` of `STATE ST_DEPLOYING / ST_PACKING` (default 60 ticks = 3 s when the event carries 0, bible: Paladin 3 s); `F_DEPLOYED` is the persistent mirror |
| Doors / activity | DOOR (10 slats per roller door), SLIDE_Y/Z | `u_aux.y` 0..1 |
| Blinkers | BLINK (emissive) | free, phase per emitter |
| Damage | shader soot + embers (`u_state.x`), squads hide members, structures smoke/fire emitters | thresholds §5.2 |
| Cloak / EMP / ghost / wreck | flags §4.2 | |
| Construction | `u_anim.x` = sink depth `(1 - ease(build))*(height + 1.5)` m, scaffold cage | §5.2 |

**Unit shader stages** (`unit.gdshader`, `[M]` verified): *vertex* decodes CUSTOM0/1, applies the part transform of §4.2 (turret / barrel / wheel / rotor / gait / door / deploy), hides gait members by hp, passes paint / team / flags to the fragment stage. *Fragment* per material class: PAINT (team mask blends `team * (0.30 + 0.9*luma + 0.10)` into the paint, panel seams at 0.45-1.4 m cells with screen-space AA that fades below 0.16 cell/px, edge chipping only where the builder set the `wear` flag, roughness 0.5-0.68), METAL (metallic 0.9, roughness 0.36-0.6), GLASS (dark, glossy, faint emission), RUBBER (rough; TRACK adds the scrolling tread ridges), EMISSIVE (`paint * emissive_strength * blink`, ×`(1 + 1.2*atm_night)`); height-based dirt (heavier low on the model and on downward faces); damage soot + embers from `u_state.x`; thin Fresnel selection rim from `u_state.y` (a wide rim washes the whole APC pale: keep the exponent at 5); hit flash; flag effects of §4.2; `AO` from the baked 4-bit occlusion; `quality = 0` removes the two procedural noise taps (−14 % at 4K). Panel-line and noise inputs use object-space position, so they do not swim while a unit moves.

`ViewModelInfo.socket_world()` reproduces the shader transform on the CPU for muzzle / exhaust / weld points: base `xf`, then for sockets on `BARREL` parts recoil (+Z `recoil*extra`), elevation about the trunnion, then turret yaw about the pivot. FX use it so tracers leave the barrel tip even while the turret slews.

#### 5.8.9 LOD, culling, batching

Mesh LOD is automatic (index subsets, `Viewport.mesh_lod_threshold` scaled by quality). At the RTS camera (47-96 m) units are at LOD1 (LOD2 beyond ~94 m at 1080p; thresholds double at 4K: LOD0 up to ~63 m). Models never have separate impostors. `custom_aabb` covers animated sweeps so culling is correct while turrets swing. Node backend: entities sharing (mesh, material) are auto-instanced by Forward+ (400 mixed units = 42 draws incl. 4 cascades, 13-14 without shadows `[M]`); Mobile/Compat do not auto-instance (801 draws for the same scene) -> batch backend. MultiMesh has no per-instance culling, so the batch backend groups by model and gives each MultiMesh a tight `custom_aabb` = union of member bounds rebuilt when membership changes by more than 10 %.

#### 5.8.10 Icons and portraits (`ViewIconBake`)

One persistent `SubViewport` (`own_world_3d = true`, `transparent_bg = true`, `Environment.BG_CLEAR_COLOR`, `msaa_3d = 4x`, `mesh_lod_threshold = 0`, `UPDATE_DISABLED`), studio key light `(-52°, -38°)` energy 1.9 + fill, `Camera3D` fov 30°. Per request: place a `MATU`-variant rig with team colour = the style's `acc` (icons are faction-branded, not player-coloured), yaw 150° (3/4 front view), camera pitch 24°, framed from `rest_aabb` with margin 0.78 (bounding-sphere fit is loose for elongated models), `UPDATE_ONCE`, two `frame_post_draw` waits, `get_image()`, `ImageTexture.create_from_image` (0.8 ms at 256x192), save `user://cache/icons/<key>.png`. Cost `[M]`: ~19 ms per icon warm (2 frame waits), first icon 2.7 s on a cold Metal shader cache; the local roster (~35 defs) bakes in ~0.7 s, one per frame, while the loading screen shows. Size ICON 128x96, PORTRAIT 384x288. Key = `content_hash + size`; a stale file is impossible. Optional pre-bake into `res://assets/icons/` for releases (`gd run res://tests/view/bake_icons.gd`).

---
### 5.9 VFX system

#### 5.9.1 Architecture, admission and budgets (`[F]` design adopted, three fixes)

Three tiers: **(A)** `FxBatch` MultiMesh ring buffers (34 batches incl. the new `wake`, ≈ 5.7 k instance slots, one draw per *active* batch, no per-frame CPU work; an instance is degenerate once `fx_time - spawn > life`); **(B)** small node pools: 6 shadowless `OmniLight3D` (quadratic energy decay), **no `Decal` nodes** (see below); **(C)** emitters for long-lived sources: `start_loop` (fixed anchor), `start_stamper` (every N metres of a node's travel, ≤ 8 per frame), `start_tracker` (endpoints re-evaluated each emit through Callables, for continuous beams, Helios spot, repair tethers). Sub-effects go through `schedule()` and are re-culled when they fire.

Admission at `spawn()` (culling happens only at spawn):

```
accept(def, a, b, s):   token bucket of def.cls >= 1                                        else stat_rate_dropped
  r    = def.radius * s                        d = |camera_position - a|                    (LINE effects pass if either end is visible)
  ok_d = cls == SUPER  or  d <= CLS_MAX_DIST[cls] * dist_mult + camera_focus_dist            # FIX 1: add the camera->focus distance
  ok_px= r * px_per_rad / max(d, 0.5) >= CLS_MIN_PX[cls]          px_per_rad = viewport_h / (2 tan(fov/2))   (1568 at 1080p, fov 38)
  ok_f = unproject_position(a) inside viewport +- px  (or behind camera and d < r)
```

| Class | max dist (m) | min px | refill /s | burst | Class | max dist | min px | refill | burst |
|---|--:|--:|--:|--:|---|--:|--:|--:|--:|
| TINY | 70 | 2.5 | 500 | 60 | BEAM | 200 | 3 | **90** | **24** |
| SMALL | 110 | 4 | 200 | 40 | SUPER | ∞ | 0 | 10 | 4 |
| MEDIUM | 200 | 6 | 60 | 20 | LARGE | 350 | 8 | 30 | 10 |

*FIX 1:* the spike measured distance from the camera *position*; at the 96 m maximum zoom TINY's 70 m silently culled everything at the focus (contrail puffs vanished `[F]`), hence `+ camera_focus_dist`. *FIX 2:* BEAM refill 30 → 90/s, burst 8 → 24 because continuous beams (Sunlance/Sunwall/Dawn) re-emit segments every 0.07 s; beam segments spawned by an admitted tracker skip the bucket and are capped at 24 live trackers. *FIX 3:* no Decal nodes: persistent marks are `ViewScorchLayer` paints, hot ground is a `gglow` sprite of 2 s life (Decal does not render in Compatibility, costs +0.3-1.4 ms at 64-1024 `[T]`, and projects onto units).

Measured behaviour `[F]` (Forward+, 1728x1051, HIGH): chaos battle (187 shots/s, 60 hits/s, ~19 explosions/s, 0.9 vehicle kills/s, 0.25 building collapses/s, 0.3 EMP/s, 20 dust-stampers) = frame p50 9.26 ms vs 8.33 baseline, render-thread CPU unchanged (0.78 ms), 402 draws (+6), 77 k primitives (+60 k), 66 µs per composite spawn, 27 % culled; 5x load: 208 µs `_process`, 49 % rate-limited, ring pressure on sparks/puff_smoke/debris/dustcol/smoke/ring_distort (rings enlarged in §4.7). Per-spawn script cost 10-60 µs (MultiMesh) vs 40-90 µs CPUParticles vs 100 µs 40 quad nodes. `GPUParticles3D`: 33-36 µs of frame time per active system, 720 systems = 76 ms: **forbidden** in `view/`.

The interpreted recipe adds ≈ 40-80 µs per composite spawn (RPN expressions); at the measured 400 spawns/s that is < 3 % of one core; constant sub-expressions are folded at compile time.

#### 5.9.2 Weapon mapping (27 archetypes, TAXONOMY §10; ids are the `pres_fx` vocabulary)

`FxCatalog.muzzle_id(warch)`: `"muzzle_" + family(archetype)` from the table below, unless the def carries an explicit `pres_fx.muzzle` string. `warch` (the `DefWeaponArch` index 0..26 of data_balance.md 4.2) comes from `ViewDefAdapter.weapon_arch(weapon_def_idx)`: `WEAPON_FIRED.b`, `PROJECTILE_*.b` and `BEAM.b` carry combat's weapon def index, and `GameData.weapon_arch_of(weapon_def_idx)` (request 4) is a pure table lookup. The projectile visual follows the archetype attributes (`proj_kind`, `proj_speed`, `homing`, `dtype`): `proj_speed == 0` and `proj_kind` BULLET or PELLETS -> instant tracer at 150 m/s; BEAM or RAIL -> tracker beam / rail helix (`BEAM` events); BULLET with speed -> tracer at `proj_speed`; MISSILE, ROCKET, TORPEDO -> mirrored mesh + trail; SHELL, GRENADE -> parabolic ribbon + tracer head; BOMB -> falling mesh; CHARGE -> column; FIELD -> dome / zone. Arc apex height factor (apex = factor × distance) is view data in `fx.json → mappings.arc_apex`: artillery_shell 0.25, mortar 0.35, missile_artillery 0.50, naval_bombard 0.20, cruise_missile 0.60, grenade_launcher 0.30, siege_gun 0.08, demolition_cannon 0.15 (combat's own `arc_bp` is view-only data on its side; the numbers may move there later without changing behaviour). Impact fx per §5.9.3.

| # | Archetype | Muzzle id | Projectile visual / trail | Recoil / shake | Default impact |
|--:|---|---|---|---|---|
| 0 | small_arms | `muzzle_small_arms` cone 1.8 m 0.075 s + flash | tracer w 0.11 (tail 3.4 m) | kick 0.4 | `hit_bullet` |
| 1 | machine_gun | `muzzle_mg` (6 staggered flashes 0.065 s) | tracer | 0.4 | `hit_bullet` |
| 2 | autocannon | `muzzle_autocannon` | tracer w 0.2 palette 0 | 0.6 | `hit_bullet_hv` |
| 3 | tank_cannon | `muzzle_cannon` cone 4.6 m, glow, smoke puffs x2, light 2.2 | tracer w 0.3 palette 1, 120 m/s | 1.0 / shake 0.10 | `expl_small` |
| 4 | siege_gun | `muzzle_siege` (cal ×1.4) | tracer 100 m/s | 1.0 / 0.16 | `expl_medium` |
| 5 | demolition_cannon | `muzzle_demolition` (short, wide) | slow shell arc | 1.0 / 0.2 | `expl_medium` + dust |
| 6 | at_missile | `muzzle_at_missile` (backblast puffs) | `proj_missile` + `trail_missile` | – | `expl_small` |
| 7 | aa_missile | `muzzle_aa_missile` | `proj_missile` + white trail | – | `expl_air_burst` |
| 8 | flak | `muzzle_flak` | tracer, airburst at end | 0.5 | `expl_air_burst` |
| 9 | artillery_shell | `muzzle_artillery` cone 6 m, big glow, smoke ×2, light 3.0 | arc ribbon + tracer head, trail 2.4 s | 1.0 / 0.18 | `expl_large` |
| 10 | rocket_barrage | `muzzle_rocket` (salvo puffs) | `proj_rocket` + `trail_rocket` per rocket | – | `expl_small` per rocket |
| 11 | mortar | `muzzle_mortar` (thump puff) | short arc | – | `expl_small` |
| 12 | missile_artillery | `muzzle_missile_art` | missile arc high + trail | – | `expl_medium` |
| 13 | beam_thermal | `muzzle_beam_thermal` (source glow) | **tracker beam** (segments 0.14 s every 0.07 s) + shimmer | – | `beam_thermal_hit` loop |
| 14 | rail_gun | `muzzle_rail` (blue flash, light) | rail helix 0.5 s | 1.0 / 0.10 | `hit_rail` |
| 15 | torpedo | `muzzle_torpedo` (splash) | `proj_torpedo` + bubble trail | – | `expl_underwater` |
| 16 | depth_charge | `muzzle_depth_charge` (drop splash) | sinking barrel | – | `expl_underwater_big` |
| 17 | bomb | none (release puff) | `proj_bomb` falling | – | `expl_medium`/`expl_large` |
| 18 | air_missile | `muzzle_air_missile` | `proj_missile` | – | `expl_small` |
| 19 | emp_pulse | `muzzle_emp` | – | – | `emp_pulse` |
| 20 | canister | `muzzle_canister` (wide cone) | 5 spread tracers | 0.8 | `hit_bullet` x5 |
| 21 | grenade_launcher | `muzzle_grenade` | small arc | – | `expl_small` |
| 22 | breach_charge | none | – | – | `expl_medium` (short) |
| 23 | naval_gun | `muzzle_naval_gun` (cone + spray) | tracer | 0.8 | `expl_small` |
| 24 | naval_bombard | `muzzle_bombard` (heavy) | arc | 1.0 / 0.25 | `expl_large` |
| 25 | cruise_missile | `muzzle_cruise` (vertical flame column) | high arc missile | – | `expl_large` |
| 26 | drone_missile | `muzzle_drone_missile` | `proj_missile` | – | `expl_small` |

**Projectile mirror** (`ViewProjectiles`, cap `proj_mesh_cap`): `PROJECTILE_LAUNCHED` (`a` proj_id = combat's serial, `b` weapon def idx, `c` shooter, `d, e` start, `f, g` end, `h` flight ticks) creates a record; `PROJECTILE_IMPACT` (`a` proj_id) or `u = 1` plus 2 ticks ends it. MISSILE / ROCKET / TORPEDO archetypes use a pooled rig (`proj.missile`, `proj.rocket`, `proj.torpedo`, dark neutral paint with team-coloured fins). Homing weapons (`DefWeaponArch.homing`) are mirrored from the pool when it is readable (`sim.projectiles`, ASSUMPTION(combat) combat.md 4.4: slot found once by `serial == proj_id`, then position `lerp((px, py), (x, y), alpha)` of the slot **validated by serial** every frame, else the projectile ended; yaw from `heading`, pitch from the vertical component of the arc); every other kind, and homing kinds when the pool is not readable, is analytic from the launch event: `u = clamp((tick + alpha - t_launch) / flight, 0, 1)`, `p = lerp(start, end, u) + up * 4 * apex * u * (1 - u)`, `apex = factor * distance` (bombs: `apex = 0`, straight fall, tumble; shells: no mesh, the FX ribbon `artillery_shell`). A smoke trail puff every 1.5 m of travel (distance accumulator) plus the launch `trail` ribbon. When the cap is reached the oldest mesh projectile is recycled and only its trail is kept. Continuous beams and sweeps never enter this class (trackers, `BEAM`).

Muzzle origin: `entity_socket(shooter, "muzzle{mount}_{barrel}")` (fallback `muzzle{mount}`, `muzzle0`, `top`) with `mount = f & 15` and `barrel = f >> 4` of `WEAPON_FIRED.f = muzzle_idx` (ASSUMPTION(combat) layout, request 3, matching combat.md 6.2); target end: the aim point `(d, e)` of the event, height = terrain + 0.9 m (ground), + `height*0.6` when `c` is a unit / structure / air target. `WEAPON_FIRED` triggers `ViewEntity.on_fire(mount, barrel)` (recoil = 1) even when the FX is culled. **Hit or miss of an instant weapon is inferred inside the batch** (the event carries no result): a `DAMAGE` event with the same attacker (`b`) and target (`a`) in the same tick means *hit* (spark at the event position `g, h`); none means *miss* and the tracer ends 0.8 m + 6 % of the range beside the target, on the side given by the id parity, with a ground spark. Request 3 asks combat for the `result` in the high bits of `f`; the inference stays as the fallback.

#### 5.9.3 Impact and explosion defaults (`FxCatalog.impact_id`)

Explosion size from the splash outer radius `R_m = units * 3/1024` (`PROJECTILE_IMPACT.g`, `EXPLOSION.c`): `r = clamp(0.55*R_m + 0.5, 1.0, 12.0)` m (1-cell splash -> 2.15, 1.6 -> 3.1, 2.5 -> 4.6, 3 -> 5.5, 7 -> 12). Composition scales with `r` exactly as the spike's `explode` (glow, star flash, ground glow, fire, smoke, sparks; `r ≥ 1.2` debris; `r ≥ 2.4` distort + additive rings and dust ring; `r ≥ 4.5` dust column; light `3 + 0.9r` energy, range `6 + 3r`, life `0.2 + 0.02r`; scorch radius `0.95r`, life 45 s (90 s for `r ≥ 6`); shake `0.10 r/1.8` capped 1).

| Condition | id |
|---|---|
| no splash, bullet | `hit_bullet` (dust puff + debris + sparks; on structure `hit_bullet_structure`, on water `impact_water` small, on air `hit_flak_small`) |
| no splash, rail / beam | `hit_rail` (ring 5 m blue, sparks, scorch 1.2 m) / `beam_thermal_hit` |
| explosive, `R_m ≤ 3` | `expl_small` (r ≈ 1.8 x s) |
| explosive, `3 < R_m ≤ 5` | `expl_medium` (r ≈ 3.6 x s) |
| explosive, `5 < R_m ≤ 8` | `expl_large` (r ≈ 8 x s) |
| strategic (`SW_IMPACT`, or an `EXPLOSION` whose `fx_kind` names a strategic effect) | `expl_strategic_large`, `expl_fragment_ring` (annulus packets) |
| damage type KINETIC (5) | `expl_kinetic` (white-blue core, deep shock ring, long dust column) |
| damage type EMP (6) | `emp_pulse` (scale = radius m) |
| `PROJECTILE_IMPACT.f` result 3 (water) | `impact_water` splash + ripple; `expl_underwater` (water column + foam) for torpedo and depth charge archetypes |
| result 1 (entity) and the target's layer is AIR | `expl_air_burst` (flash + smoke puff, no debris) |
| result 4 (intercepted) | `aps_flash` (small flash + ring) at the event position |
| result 5 (expired) | `expl_air_burst` for aa_missile and flak archetypes, else a small puff |

Damage type of an impact comes from the archetype (`DefWeaponArch.dtype`: BULLET 0, AP 1, HE 2, THERMAL 3, RAIL 4, KINETIC 5, EMP 6) or from `EXPLOSION.g`. The `EXPLOSION` event names an fx through `fx_kind` (`d`): a value > 0 is an index into `GameData.pres_names` (sorted unique `fx` strings of warheads, weapons, zones and powers; request 4), resolved by `FxCatalog.explosion_id`; 0 means "auto" (the rules above). Hit reactions: `DAMAGE` events are coalesced per victim per frame by the router: `ViewEntity.on_hit` sets `flash = 1` (decays over 0.125 s) and marks the health bar; flag bit 1 (kill blow) suppresses the flash. `STATE ST_SUPPRESSED`: crouch flag + pip.

#### 5.9.4 Deaths (`DIED`: `a` id, `b` def, `c` owner, `d, e` x, y, `f` killer, `g` killer owner, `h` reason)

The MASTER event carries no death kind, so the view classifies the death from the `ViewDef` and the entity's last samples: kind STRUCTURE -> `DK_STRUCTURE`; MOTION_FOOT -> `DK_INFANTRY`; NAVAL or SUB (or last layer SURFACE / UNDERWATER) -> `DK_SINK`; last layer AIR -> `DK_CRASH` for fixed wing and helicopters, `DK_AIR_EXPLODE` for drones, missiles and any `F_SUMMONED` aircraft; `F_SUMMONED` or `F_TEMPORARY` ground units of size class LIGHT or smaller and reason `DIE_PARENT_LOST (4)` -> `DK_DRONE`; everything else `DK_VEHICLE`. A recipe's `meta.death` (`crash | air_explode | sink | vehicle | drone | silent`) overrides the rule. **Silent removals** (`REMOVED` with reason EXPIRED 2, CONSUMED 4 or SCRIPT 5 and no preceding `DIED`) use `DK_SILENT`. The dying window is view data (`meta.death.ticks` per archetype: vehicle 2, infantry 2, crash 30, air_explode 1, sink 60, structure 7, drone 1, silent 8), because the sim removes a dead entity in the same tick (`DIED` and `REMOVED` are emitted back to back by cleanup, sim_core 5.4) and the `ViewEntity` outlives it.

| `dying_kind` | View behaviour | FX id (scaled by radius class) |
|---|---|---|
| `DK_VEHICLE` 1 | hide model 1 tick after the event (the explosion covers the swap); a wreck entity, if the sim creates one, appears through its own `SPAWNED` with reason WRECK (5) in the same tick | `death_vehicle_light/medium/heavy` = r 1.8/3.6/5.0, debris burst (turret pop), `wreck_start` loop 12 s if a wreck exists |
| `DK_INFANTRY` 2 | last member falls; squad model hidden | `death_infantry` (dust puff, 3 sparks; no gore) |
| `DK_CRASH` 3 | keep the record 30 ticks: roll 2.5 rad/s, position advances by the last per-tick velocity `(x_cur - x_prev, y_cur - y_prev)` decaying by 15/16 per tick (the same rule as combat.md 5.11), altitude falls with a stylised `g = 16 m/s²` from its cruise height (16 m in 1.41 s = 28 ticks) plus `firetrail` and dark `trail_dark`; ground impact when `alt` reaches 0 (forced at tick 30) | `aircraft_crash` composite, `expl_large` x0.8, `wreck_start` |
| `DK_AIR_EXPLODE` 4 | hide immediately | `death_air_explode` (flash + 12 debris + smoke ribbon) |
| `DK_SINK` 5 | ship keeps the record 60 ticks: `sink` 0->1 (drops 0.9 x hull height, list 20°), bubbles/foam ring, oil fire loop 6 s | `death_sink_small/large` (explosion at waterline + `impact_water` ripples) |
| `DK_STRUCTURE` 6 | 7-tick shake then hide | `building_collapse` with `s = max(fw, fh)*1.5/7`, scorch `r*1.25` 120 s, rubble 30 s, dust ring |
| `DK_DRONE` 7 | hide | `death_drone` (small flash + sparks) |
| `DK_SILENT` 8 | 0.4 s shrink + shimmer | `death_silent` |

**Explosion dedupe.** Chain warheads of the sim (structure explosions) arrive as `EXPLOSION` or `PROJECTILE_IMPACT` events. The router looks ahead over the current batch (combat's damage stage precedes cleanup inside a tick, sim_core 5.3): if it contains an explosion with radius >= 2 m within 1.5 cells of the death position, the `death_*` effect drops its own fireball and adds only the secondary elements (debris, fire, sink), so nothing detonates twice. A chain explosion that fires later (`chain_delay`) is simply additive.

#### 5.9.5 Superweapons (bible geometry, cell = 3 m; warning geometry from `SW_WARNING`, execution from `SW_LAUNCHED`, `SW_IMPACT`, `EXPLOSION`, `BEAM` and the summon `SPAWNED` events)

| Superweapon | Warning zone drawn | Pre-impact (from warning `exec_tick`) | Execution FX | Notes |
|---|---|---|---|---|
| Atlas Kinetic Array | 3 discs r 6 m at line offsets 0, −3, +3 cells (rods 9 m apart, line length 18 m) | 3 penetrator columns (`strike`, r 3.2 m, 90 m tall) starting 0.27 s before each impact, staggered by the packet ticks (X, X+4, X+8) | per rod: `sw_atlas_rod` = `explosion_large` x0.85 + 12 m distort ring + long dust column, shake 0.7 | scorch r 7 m 90 s |
| Aurora Microwave Array | disc r 24 m | 1.0 s charge shell building on the launcher | `sw_microwave_dome`: hex dome r 24 m 4.5 s, EMP ring 24 m, haze, 8 arcs to the rim; EMP status visuals on victims | enemy-only; friendly units show nothing |
| Helios Reflector | capsule 48 m x 9 m | 1.0 s aiming beam from 80 m up to the start | tracker beam from sky to the moving hot spot `A + (B−A)*(t − t0 − delay)/duration` (12 s), `beam_tick` glow + sparks + scorch strip, shimmer ribbon | no sweep event exists: A and B are the capsule ends from `SW_WARNING` (centre ∓ dir × `h`/2 with `dir` from `e`), duration 12 s and delay from `fx.json → superweapons.helios_reflector`; `SW_LAUNCHED` starts the timeline |
| Perun Missile Complex | disc r 21 m (UI shows 7 cells) | 1.2 s ribbon streak from the map edge | X: `sw_shockwave` core (9 m fireball) ; X + 6 ticks: 21 m annulus wave (distort + additive rings, dust ring 19 m, column 14 m) | matches spike `sw_shockwave` |
| Tempest Swarm Hub | disc r 18 m + approach line | launch smoke + 24 drone summons appear as air units (ordinary entities) | drone hits are ordinary FX | drones shootable; `SW_LAUNCHED` = hub burst |
| Dragonfall Foundry | disc r 15 m | 3 capsule streaks (ribbon + fire) land at pre-drawn points | capsule = unit (`sum_capsule`); assemble burst at +5 s (sparks, dust, shake) | engines are units (`sum_engine`) |
| Horizon Mass Driver | capsule 30 m, impacts at −5 / 0 / +5 cells (r 9 m) | 3 mass-driver rods (kinetic columns) | impacts at X, X+90, X+180 ticks: `expl_kinetic` r 9 m; debris zone: `zone_debris` dust haze 20 s | |
| Trident Interception Array | disc r 18 m for 500 ticks, **visible to all players** | – | `sw_intercept_dome`: cyan hex dome 25 s, brightness ∝ charges/24; each `INTERCEPT` event: flash at its position `(c, d)` + ring on the dome | ends early at 0 charges |

Warning presentation (`ViewWarnings`): created by `SW_WARNING` (`a` owner pid, `b` sw idx, `c, d` x, y, `e` angle, `f` warning ticks, `g` launcher id, `h` extent units; broadcast to every player and never fog-gated, sim_core 6.2) and by `POWER_WARNING` (same layout for support-power warnings such as Wideband Scan and Counterlaunch Plot, request 5). Geometry comes from the sw idx (`fx.json → superweapons.<id>`: shape, radius / length / width in metres = bible cells × 3) and `h`. A warning is shown when the local team is *affected*, the bible wording of "visible to affected players": the owner's team, or any team owning an entity inside the shape grown by 3 cells (`sim.query_radius` on the bounding circle, filtered by the exact shape and by `team`; recomputed every 10 ticks while the warning lives); **regardless of fog and decoys**. Hostile = red hatch, own launch = amber; countdown as a clock-sweep spoke + pip ring, pulse rate rising toward `exec = event tick + f`; a `beacon` column at the centre; `SW_CANCELLED` (`a` owner, `b` sw idx) and launcher loss cancel instantly (`fx.cancel(handle)`); `SW_LAUNCHED` swaps the countdown for the pre-impact timeline and the record ends with the last `SW_IMPACT` (`f` packet_index) or after `duration` from `fx.json`. Because warnings are events, a viewer that attaches mid-match (replay seek) misses them: `_reconcile` rebuilds active warnings once from `sim.players[pid].sw_state == WARNING` (`sw_x, sw_y, sw_angle, sw_warn_until`, sim_core 4.6).

#### 5.9.6 Support powers (48) by effect kind (economy.md 5.17-5.18; cast anchor = `POWER_USED`: `a` pid, `b` power idx, `c, d` x, y, `e` angle, `f` duration ticks)

| EK (count) | Visual |
|---|---|
| BUFF (19) | activation: `power_cast_ring` at the target point with the power's radius (cells x 3 m); each affected entity gets an `AURA` ring in the power theme colour for the effect duration (affected = entities of the caster's team inside the disc at the `POWER_USED` tick, found with `sim.query_radius`; ring lifetime = `f`; exact per-entity buff state would need request 13; themes: damage orange, speed green, defence blue, range/sight violet, camouflage grey, cap 64 rings); penalty phases (Capacitor Discharge, Software Surge): rings turn red for the penalty |
| WINDOW (6) | pulse on the HQ + HUD timer (UI); no world effect |
| STRUCT_BUFF (1) | sparkle loop on the targeted airfield for 20 s |
| REVEAL_ZONE (3) | `power_scan_ring` sweep + faint grid disc for the duration (`REVEAL_AREA`: `b, c` x, y, `d` radius units, `e` duration ticks); Wideband Scan first draws its `POWER_WARNING` |
| RECON_SUMMON (4) | the summon is an entity (UAV / drone / balloon / patrol aircraft: `sum_*` models) with contrail; arrival ring |
| REPAIR (6) | `zone_repair`: pulsing green disc + rising motes loop; healed entities pulse (`HEAL` events); cargo-drop variants show the shootable aircraft and a crate fall column |
| SMOKE (3) | `zone_smoke`: puffs across the disc / capsule (cap 8 spawns/s), 5 s life, grey-white |
| DECOY (3) | `decoy_spawn` flash + ring at each decoy (decoys use the roster's unit model; identified ones `UF_DECOY_ID`) |
| BOMBARD (3) | warning zone; shells: `artillery_shell` from off-map (start = target + dir*140 m, +90 m up), impact `expl_medium` at shell radius 1.5 cells; Tremor Barrage 20 shells over 3 s stays inside the LARGE bucket |
| MARK (1) | crosshair `AURA` ring for 4 s on enemy units inside the zone with `tick - t_fire <= 160` at the `POWER_USED` tick (the bible's "fired in the last 8 seconds") |

#### 5.9.7 Zones (ZONE entities, sim_core 4.2) and statuses

`ViewZones` mirrors ZONE entities: `SPAWNED` (kind ZONE) starts a `ZONE_DISC` instance (cap 32) at the entity position; geometry comes from the zone def (`DefZone.zone_kind, shape, radius`, capsule `length` x `width`, data_balance.md 4.2) and `facing` (capsule orientation), the lifetime from `expires`; tint by kind (`BUFF 0, SMOKE 1, INTERCEPT 2, DEBRIS 3, DECOY 4, PUCK 5, SHELTER 6, COVER 7, REPAIR 8, REVEAL 9`) plus a loop emitter; `REMOVED` fades over 0.4 s. Zones whose def has `visible_to_enemy == false` are drawn only for the owner's team. INTERCEPT zones (Trident dome) brightness = `ViewSimReader.zone_charges(e) / 24`, constant 1.0 when the component is unreadable. `ViewStatusMarks`: `STATE` events drive shader flags (cloak, EMP, shutdown, suppressed) and the pip row; `UF_DECOY_ID` from `F_DECOY` and `decoy_identified` (request 10); pips in the health bar row: buff blue, marked red, suppressed yellow, EMP cyan.

#### 5.9.8 Persistent damage, emitters, wrecks

Damage emitters (`damage_smoke`, `damage_fire`) 0.4 s interval, one per damaged entity, capped at 24 scene-wide (nearest to the camera win, re-evaluated at 2 Hz); wreck loops `wreck_tick` 0.22 s interval for 14 s (`puff_smoke` size 4.2 x s life 5 s + 45 % fire sprite), then thin smoke every 1.5 s until 8 s before expiry. Scorch/crater stamps: `ViewScorchLayer` (§5.5).

#### 5.9.9 Event gating

`FxEventRouter._allowed(x, y, id_a, id_b)`: true if either entity has a `ViewEntity` with `vs == VS_VISIBLE`, or `sim.cell_visible(local_pid, x >> 10, y >> 10)` (current vision, fog cells excluded), or the event is a global / strategic one (`SW_WARNING`, `POWER_WARNING`, `SW_LAUNCHED`, and `SW_IMPACT` / `POWER_USED` inside a visible or affected zone). Otherwise the event still updates entity state (recoil, hp) but spawns no FX (no information leak through fog, and cheaper). `sim.paused != 0` freezes `fx_time` (blinkers freeze; rotor / radar angles integrate `dt * time_scale`, so they stop too; water / wind keep running on `view_time`).

#### 5.9.10 Prewarm and first-spawn hitch

Cold first spawn of each recipe hitches 14-32 ms on Metal (1-4 display frames) `[F]`. `ViewWorld.build_async` calls `fx.prewarm()` (every registered effect once, `force = true`, in front of the camera) behind the loading screen, then `clear_all()` 8 frames later; unit materials are prewarmed by rendering one hidden instance of each style for 3 frames; `RENDERING_INFO_PIPELINE_COMPILATIONS_*` must be flat for 30 frames before the loading screen ends (test V-11).

### 5.10 Interaction overlays

* **Selection** (`ViewSelection`, one `ViewInstanceBuffer` per mode, terrain-aligned quads lifted 0.08 m, vertex pulled 0.15 m toward the camera): unit ring radius `max(radius_m*1.25, 0.9)`, stroke 6 % of R, own `(0.55, 1.0, 0.6)`, selected allies blue, selected enemies red; structure brackets around the footprint rect + 0.3 m margin (corner arm length `min(w,h)*0.22`); hover = thin white ring at 60 % alpha; the selected model also gets the shader rim (`u_state.y`); group members (Ctrl+n) get a tiny number pip via the health-bar pip row. Cap 512 instances.
* **Health bars** (`ViewHealthBars`, `health_bar.gdshader`): quad of `width_px x 5 px` (+1 px border), NDC-offset in the vertex shader from the projected anchor (model top + 0.6 m), so size is constant at any zoom. Widths: inf 28, light 36, medium 44, heavy 56, huge 72, air 36, ship small/medium/large 40/60/84, structures `clamp(fw*22, 44, 130)`. Colour: `> 60 %` green `(0.20, 0.90, 0.30)`, `30-60 %` yellow `(0.95, 0.85, 0.20)`, `< 30 %` red `(0.95, 0.20, 0.15)`; squads draw tick marks at member thresholds; construction / selling bars cyan-white. Mode `DAMAGED` (default): selected or hovered, or `hp < max_hp` with a `DAMAGE` event within 8 s (fade 0.5 s); enemy bars only when selected/hovered. `custom = (hp_frac, width_px, colour_id, pips_mask)`; the bar's left end carries the player's shape pip in the player colour (colour-blind cue, §5.12). Cap 512.
* **Rally lines / order lines** (`ViewLines`, `line.gdshader`): ribbon strips with `VERTEX` = point, `NORMAL` = tangent, `UV = (side ±1, distance m)`; the vertex shader offsets by `side * width_px/2` perpendicular to the projected tangent (constant 3 px) and animates dashes `fract((dist - view_time*3.0)/1.2)`. Ground-following: sample `height_at` every 3 m (+0.15 m). Order lines come from `SimEntity.orders` (`SimOrder.type, target, x, y`) of the **selected own units only** (enemy orders are never read); rally lines from `ViewSimReader.rally_of(structure)` (ASSUMPTION(economy): `SimCompProd.rally_on / rally_x / rally_y / rally_target`). Colours by order type (sim_core 4.7): move `T_MOVE 16` and patrol `T_PATROL 17` green `(0.30, 1.0, 0.40)`, attack `T_ATTACK 32` and force fire `T_FORCE_FIRE 34` red `(1.0, 0.30, 0.25)`, attack-move `T_ATTACK_MOVE 33` orange `(1.0, 0.60, 0.15)`, guard `T_GUARD 35` blue `(0.30, 0.60, 1.0)`, capture / repair / salvage `50 / 51 / 52` yellow `(1.0, 0.90, 0.30)`, harvest / return cash `48 / 49` gold `(0.95, 0.75, 0.20)`, load / unload / garrison `64-66` white; rally green with a `TARGET_PING` end ring (harvest rally yellow). Cap 32 units x 8 waypoints + 16 rally lines; rebuilt only when selection or orders change (compared by a cheap hash of ids + order types + targets), ≤ 10 Hz.
* **Placement ghost** (`ViewPlacementGhost`): the structure model in the `GHOST` material variant (alpha 0.55, tint green / red by `state.valid`), snapped to the cell grid at the footprint centre `(origin + size/2) * 3 m` and rotated by `state.rot` (only the Dock rotates); `ghost_grid.gdshader` draws one tile per footprint cell from a `w x h` R8 texture of `state.cells` (`CF_OK` green 35 %, `CF_TERRAIN` / `CF_STRUCTURE` red, `CF_UNIT` orange, `CF_DEPOSIT` magenta, `CF_DEBRIS` orange, `CF_APRON` yellow, `CF_SHORE` cyan, `CF_KEEPOUT` light-red hatch). The apron / reserve cells (`MapFootprint.reserve_cells(orient)`, terrain_movement.md 3.6) and the gap-1 halo (`ring_cells`) are drawn as a faint outline so the player sees why a neighbour is refused. The build-radius overlay is a `BUILD_RADIUS` ring `R = 8 cells = 24 m` around every completed HQ owned by the local player (`ViewDef.is_hq`; the rule is centre-to-nearest-footprint-point ≤ 8 cells, economy.md 5.3, so a footprint that touches the ring is legal; allied HQs and MCVs do not extend it). Range preview for defenses via `ViewRangeRings.show_preview`.
* **Range rings** (`ViewRangeRings`): maximum and minimum weapon range in metres `= units*3/1024` from `ViewSimReader.weapon_ranges(e)` (ASSUMPTION(combat): `world.combat.range_max_eff(e, mount)` and `range_min_of`, combat.md 3.7; called on selection change only); dashed, anti-air cyan, ground white, artillery orange (by the archetype's `target_mask` and `fire_mode`); cap 12 rings; shown for selected armed entities when the UI asks and while placing a defense.
* **Remembered structures** (`ViewGhosts`): a ghost record `(eid, def_idx, owner, x, y, facing, hp_pct, seen_tick)` from `sim.fog.ghosts(local_pid)` (request 9; abilities.md 5.9.7 `SimGhost`) -> model of that def in the owner's style, `UF_GHOST`, `damage` from `hp_pct`; removed when the record leaves the list (structure seen again, or its cell is visible and empty). Reconciled on a `ghost_version` change or every 0.5 s.
* **Floating text** (`ViewFloatText`): `Label3D` with `billboard = BILLBOARD_ENABLED`, `fixed_size = true`, `no_depth_test = true`, `font_size 32`, `pixel_size` chosen so text is ≈ 22 px tall; gold `(1.0, 0.85, 0.25)` "+$n" for `HARVEST_DELIVERED` (`c` amount, aggregated per refinery over 0.5 s, shown at the refinery) and for `SALVAGE` phase 1 (`c` credits, at the wreck) when the collector or salvager belongs to the local player, rising 1.2 m and fading over 1.2 s; pool 24. Font supplied by `ui` (`ViewFloatText.font`), default `ThemeDB.fallback_font`.
* **AI/debug** (`ViewDebugOverlay`): `AiDebugFrame` circles (`x, y, r, argb, label_idx`) as `RANGE`-mode rings with `Label3D` labels (cap 48), lines via `ViewLines`, threat heat as a `heat_w x heat_h` texture on a ground quad with the fog-free `ring` shader; the frame comes from `ai.debug_frame(pid)` (null unless the thinker runs at `debug_level >= 2`); toggled by `ui`. View stats overlay (F3, `ViewWorld.stats()`). Both overlays exist only in debug builds (`OS.is_debug_build()`); release exports draw no bible or data ids anywhere (QA checklist V-ID1).

### 5.11 Picking (`ViewPicker`; no physics engine, `physics/common/enable_object_picking = false`)

```
pick(screen_pos, filter):
  o, d = camera.project_ray_origin(p), camera.project_ray_normal(p)
  G    = terrain.raycast(o, d)                                   # 8.5-11.4 us; INF on miss (then only air units are candidates)
  cand = []                                                      # deduped ids
  (a) units/wrecks:  sim.query_radius(G.x -> units, G.z -> units, 4608, cand, SimTag.ALIVE, 0)  # 4.5 cells: covers the largest structure half-diagonal (6x4 airfield: 3.6 cells) + unit radius; ascending ids
  (b) structures:    DDA-walk sim.map.occ (structure entity id per cell, -1 none) from the cell of G back toward the camera's ground foot for up to L = ceil(14 m / tan(pitch) / 3) + 2 cells (<= 10):  id = occ[cell] >= 0
  (c) aircraft:      all ids in ViewWorld._air_ids (<= 60)
  for id in cand: ve = _by_id[id]; skip VS_HIDDEN / filter mismatch
      t = ray_vs_obb(o, d, centre = (wx, wy + h/2, wz), half = ve.pick_half, yaw)      # slab test in entity space (~1.5 us)
      air: half extents floored at 1.2 m and screen fallback |unproject(centre) - p| < 22 px when t misses
      keep min t;  tie (|Δt| < 0.01 m): non-wreck > wreck, unit > structure, lower id
```
`pick_half`: units `(radius_m*0.9, height/2, radius_m*0.9)`; structures `(fw*1.5 − 0.25, height/2, fh*1.5 − 0.25)` rotated by `rot`. Cost ≈ 60-90 µs per pick; `pick_box` projects each visible matching entity's base / mid / top with `unproject_position` and accepts when the mid point is in the rect (units) or the centre is in the rect (structures): 1.2 ms per call for 400 entities (UI calls at ≤ 30 Hz while dragging). Fog-hidden and container-hidden entities are never returned. Filters are bitmasks (`PICK_*`, §3.7); `PICK_GHOSTS` returns the eid of a remembered structure; whether an attack order on it is legal is decided by the sim (sim_core 5.5 requires visibility, combat.md 6.1 accepts `SimVision.is_known`: reconciliation item, R4).

### 5.12 Quality presets, fallbacks, auto-downgrade, measurement

* **First-run recommendation** (`ViewQuality.recommend`): `RenderingServer.get_video_adapter_type()`: `DISCRETE_GPU` -> HIGH; `INTEGRATED_GPU` -> MEDIUM; `CPU` (lavapipe / software) or `OTHER` -> LOW; renderer Mobile -> cap at MEDIUM, Compatibility -> cap at MEDIUM. Apple-silicon integrated GPUs start at HIGH via the auto-upgrade path (adapter type alone cannot tell them apart from Intel iGPUs and is not name-matched).
* **Auto (`ViewQualityAuto`)**: sample `delta` (ignore > 250 ms hitches: alt-tab, load); 3 s windows; `target = 1000/target_fps` (default 60 -> 16.7 ms; 120 Hz displays quantise to 8.33). Step **down** one preset when `p95 > 1.25*target` for 2 consecutive windows (min preset LOW); step **up** when `p95 < 0.6*target` for 10 consecutive windows, at most once per 30 s, never above the user's cap, never within 120 s of a down-step. Emits `on_change(new_preset, reason)`; UI shows a toast. GPU timing is unavailable on Metal (`viewport_get_measured_render_time_gpu` = 0.0), so wall-clock frame time is the only signal.
* **Application order** (`ViewQuality.apply_*`): viewport (msaa, fxaa, taa, scaling, debanding, lod threshold) -> `RenderingServer.directional_shadow_atlas_set_size`, `directional_soft_shadow_filter_set_quality`, `environment_set_ssao_quality` -> `ViewAtmosphere.apply_quality` -> materials (`quality` uniform, shader variants) -> `FxManager.set_quality` -> decor density/groups (regroup 1-3 ms) -> terrain re-bake only when `terrain_subdiv` changed. A change never restarts the match.
* **Renderer-specific behaviour** — Forward+: everything. **Mobile:** same look minus SSAO/SSIL, ~2x faster on TBDR GPUs (1080p full 2.33 ms vs 4.4-4.7 `[T]`), MSAA nearly free, decals fine, no auto-instancing -> batch backend. **Compatibility:** all our shaders compile (global uniforms, `texelFetch`, `#include`, canvas fog shader) after the instance-uniform and MultiMesh-colour fixes; no Decal rendering, no FXAA/SMAA/TAA; instance-uniform users capped at ~256 -> batch backend; cluster sprites of FX look smaller/dimmer (root cause not isolated: LDR clamp or `skip_vertex_transform` instance handling) -> `compat_boost` and a dedicated tuning pass before Compat counts as playable-with-downgrades (risk R3); 1080p reference: full 6.36 ms, Low 1.78.
* **Reference numbers `[T]`** (M5 Max, 1080p / 1440p, whole scene incl. terrain 295 k tris, 3.5 k decor, water, 150 units): Low 1.46 / 2.23 ms, Medium 3.31 / 5.42, High 4.4-4.7 / 7.87, Ultra 8.9-9.1 / 14.7. Deltas at High/1080p: no SSAO −1.0 ms, SSAO high full-res +0.9, SSIL +0.9, no glow −0.6, shadows off −1.4 (Mprims 1.32 -> 0.41), 2 cascades −0.3, atlas 2048 / 8192 −0.35 / +0.6, PCF hard / ultra −0.96 / +0.47, MSAA off / 2x / 8x −1.4 / −0.9 / +1.0, FXAA −1.2, scaling 0.67: bilinear −2.1, FSR1 −1.95, MetalFX spatial −1.96, FSR2 −0.7, MetalFX temporal −0.4; units 0/150/400 = free; blob shadows instead of maps −1.4; AGX −0.2. At 4K (GPU-bound, unit sheet `[M]`): full 19-29 ms, no post 13.5-15, no MSAA 13.7-20, quality=0 shader 16.6-24, Low 8.3.
* **Measuring** (no GPU timestamps on Metal, 120 Hz present cap on macOS): (1) `RenderingServer.force_draw(false)` back-to-back throughput, p50 of 150 frames, min over 3-4 passes, after ≥ 3 s warm-up; (2) `viewport_get_measured_render_time_cpu`; (3) `RENDERING_INFO_TOTAL_DRAW_CALLS/PRIMITIVES/OBJECTS_IN_FRAME`; (4) script ms per subsystem from `ViewWorld.stats()`. Resolution is set through `Viewport.scaling_3d_scale` (>1 = supersample) because the OS window cannot exceed the panel. Do not trust deltas < 0.3 ms on a shared machine.

* **Accessibility** (`[access]` keys of `settings.cfg`, QA-XR-13; read by `ViewQuality.from_settings`, applied live). `colour_mode` (`normal`, `protan`, `deutan`, `tritan`, `high_contrast`): `ViewTeamColors.set_mode` re-publishes the palette (materials rewrite `u_team` / `mm_team` once, about 400 writes). The three colour-blind modes map ids 0-7 to an Okabe-Ito based set: blue `#0072B2`, orange `#E69F00`, sky `#56B4E9`, bluish green `#009E73`, yellow `#F0E442`, vermillion `#D55E00`, reddish purple `#CC79A7`, light grey `#F2F2F2` (ids 8-11 keep their normal colours and rely on the pips). **Every** mode draws a **shape pip** per player index (circle, triangle, square, diamond, cross, hexagon, star, bar for ids 0-7; ids 8-15 repeat with an outline) at the left end of health bars and at the north point of selection rings; `high_contrast` raises chroma by 20 % and adds a 1 px white outline to bars and rings. `reduce_flash`: FX light energy ×0.4, star-flash and glow sprites capped at 60 % size and 50 % alpha, at most 3 flash-class spawns per second per screen quarter, camera `shake` amounts ×0, blinkers never above 2 Hz. `reduce_motion`: camera shake ×0.2, constant edge-scroll speed (no acceleration), cinematic key moves become cuts, construction sink animation shortened to 0.25 s. QA checklist V-A01 verifies separability under simulated protanopia, deuteranopia and tritanopia.

### 5.13 How each bible / architecture rule in this domain is honoured

| Rule | Treatment |
|---|---|
| Faction `visual_direction` (8) | palette + kit table §5.8.4; every unit and structure of a faction wears it; shared structures/service units wear the *owner's* style |
| 3 subfactions per faction (unique units, modifiers) | unique units have their own recipes (same archetype family as the unit they replace, different kit: e.g. `beaver_amphibious_apc` = `veh_amphib`); subfaction styles extend the parent style with accent/emblem only; economy modifiers have no visual |
| Hidden enemy units are not rendered (ARCH §8) | CPU visibility §5.3; no fog-shader hiding for units |
| Remembered structure ghosts (abilities.md 5.9.7, sim_core `SimFogApi`) | `ViewGhosts` from `sim.fog.ghosts(pid)` |
| "Strategic warning zones are visible to affected players and cannot be hidden by fog or decoys" | `ViewWarnings` driven by the "affected" test of §5.9.5 (owner team or any team with an entity inside the zone + 3 cells), no fog test |
| Superweapon geometry (radii, lengths, spacing, timings) | §5.9.5 uses bible/economy numbers x 3 m; impacts are event-driven so visuals cannot drift from damage |
| Infantry are squads (one entity, several soldiers that fall as health drops) | member hiding by hp (§4.2), no extra nodes |
| Camouflage / detection / decoys / suppression / cover / smoke (rule.combat.*) | `UF_CLOAKED`, `UF_DECOY_ID`, `UF_SUPPRESSED`, `sum_cover` models, `zone_smoke`; sim decides, view mirrors |
| Submarines surface 8 s when firing; wrecks persist 60 s | `sink` state machine; wreck view with expiry sink |
| Power loss (rule.design.power_loss) | `UF_UNPOWERED` on structures whose `power_class` needs power; defenses go dark |
| Veterancy disabled | no insignia; health-bar pip row reserved |
| No real-world flags, emblems, logos or brand marks; no bible ids visible to the player (QA V-IP1, V-ID1) | emblems are abstract marks (§5.8.4); debug overlays and ids compiled out of release builds (§5.10) |
| Carriers replenish only their own drones; garrisons hold four squads | launch puff at the carrier when a tethered drone (`F_TETHERED`, `parent` = carrier) is `SPAWNED`; dock puff when it becomes `F_INSIDE`; lit windows from the `LOADED` / `UNLOADED` occupant counter |
| Presentation is a pure function of sim state + events (DR-12/15) | §8; `test_view_readonly` proves the checksum chain is unchanged |
| 60 FPS, ~400 entities, integrated-class GPU at Low | §9 budgets + Low preset table; risk R1 records that integrated hardware was not measured |

---
## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 Commands and events emitted by this domain

**Commands consumed: none. Sim events emitted: none.** The view never submits a `SimCommand` and never appends to `world.events` (DR-12). It offers the UI the *means* to build commands (`ViewPicker`, `pick_ground`, `world_to_sim`, `ViewPlacementGhost`), nothing more. Godot signals emitted (all presentation-local): `ViewWorld.build_progress(fraction, stage)`, `ViewWorld.build_finished()`, `ViewCamera.view_changed(height, pitch, yaw)`, `ViewCamera.cinematic_changed(active)`, `FxManager.camera_shake(amount, pos)`, `ViewIconBake.icon_ready(key)`, `ViewModelBuilder.model_ready(key)`, `ViewQualityAuto.on_change` callable.

### 6.2 Events consumed

#### 6.2.1 The batch contract

The view consumes the **MASTER event catalog of `sim_core.md` 6.2**, which is authoritative (`qa.md` R30 and the QA sim adapter make the same choice). One rendered frame delivers one batch: the `PackedInt32Array` returned by `world.events.take()` (sim_core 3.7 / 5.7), records of **10 int32** `[type, tick, a, b, c, d, e, f, g, h]` (sim_core 4.9), `tick` non-decreasing, emission order = stage order inside a tick. Rules:

* `ViewEventRouter.process(events)` walks the batch **once, sequentially, in emission order** (`o = 0; while o < events.size(): dispatch(events, o); o += 10`). The batch is read-only and never retained; nothing is copied; `FxEventRouter.on_event(events, o)` reads the same record in place.
* Records are **self-contained**: handlers use the payload, never the live entity, because the entity may already be removed when the batch is processed (a unit produced and killed inside one frame). `sim.entity(id)` is used only for optional refreshes and null is always tolerated.
* Ordering guarantees the router relies on (sim_core 5.4): `SPAWNED` precedes every other event of its entity; `DIED` precedes `REMOVED` (back to back, same tick); the `SPAWNED` of a wreck follows the `DIED` of its unit in the same tick; per-tick emission order = stage order (commands, production, economy, power, orders, movement, abilities, combat, zones, vision, cleanup).
* Handlers switch on the symbolic class constants `SimEvent.<NAME>`; the numeric codes 0x01-0x74 are not repeated in view code. `ViewEventRouter._validate_codes()` runs at start-up: it reads the constant map of `SimEvent` and `push_error`s once for every consumed name that does not exist, then ignores that handler, so a rename in the kernel fails loudly in the first test run instead of silently dropping effects.
* Types the view does not consume are UI / audio business and are skipped without a count: `CASH` (income floaters come from `HARVEST_DELIVERED`), `BUILD_STARTED`, `BUILD_READY`, `BUILD_CANCELLED`, `QUEUE_BLOCKED`, `RESEARCH_*`, `TECH_*`, `BUILD_PROGRESS`, `UNIT_CAP_REACHED`, `POWER_READY`, `SW_CHARGING`, `REVEALED`, `HIDDEN`, `BASE_UNDER_ATTACK`, `UNIT_UNDER_ATTACK`, `HARVESTER_UNDER_ATTACK`, `ORDER_FAILED`, `CMD_REJECTED`, `PLAYER_ELIMINATED`, `CHECKPOINT`. Unknown types are counted in `stats().events_unknown` and ignored.
* Catch-up bursts (a frame that ran 8 ticks): lifecycle events, deaths and state events are always processed; cosmetic `WEAPON_FIRED` beyond 300 per frame apply their recoil kick but spawn no FX (§9.4).

#### 6.2.2 Reaction table

| Event (code) | Payload used | View reaction |
|---|---|---|
| `SPAWNED` 0x01 | `a` id, `b` def idx, `c` owner, `d, e` x, y, `f` facing, `g` reason (`SPAWN_INITIAL 0, PRODUCED 1, PLACED 2, DEPLOYED 3, SUMMONED 4, WRECK 5, SCRIPT 6`), `h` parent | create the `ViewEntity` (kinds ZONE and DEPOSIT go to `ViewZones` / `ViewDecor`); PRODUCED: `exit_dust`; PLACED or DEPLOYED: structure BUILDUP with `t0` = the event tick (§5.2) and a dust ring; SUMMONED: `spawn_shimmer`; WRECK: wreck model at the dead unit's pose; `h != 0` with `F_TETHERED` (carrier drone): launch puff at the parent's bay socket; recipe `meta.spawn_fx` plays for any reason (e.g. the Dragonfall capsule-to-engine assemble burst); duplicates of `bind_world` are ignored |
| `REMOVED` 0x02 | `a` id, `b` def, `c` owner, `d, e` x, y, `f` reason (`REM_KILLED 0, SOLD 1, EXPIRED 2, DEPLOYED 3, CONSUMED 4, SCRIPT 5`) | KILLED: only sets `sim_gone` (the dying window began at `DIED`); SOLD: dispose (the sell animation already ran); DEPLOYED: dispose the MCV instantly (the HQ has its own PLACED-style `SPAWNED`); EXPIRED, CONSUMED, SCRIPT: `DK_SILENT` (0.4 s shrink + shimmer; a wreck consumed by salvage sparkles) |
| `DIED` 0x03 | `a` id, `b` def, `c` owner, `d, e` x, y, `f` killer, `g` killer owner, `h` reason (`DIE_COMBAT 0, SCUTTLE 1, EXPIRED 2, DEFEAT 3, PARENT_LOST 4, SCRIPT 5`) | classify (§5.9.4), start the dying window, death FX, scorch stain; defeat cascades (up to 6 deaths per tick per eliminated player, sim_core 5.9) are thinned by the FX admission rules |
| `OWNER_CHANGED` 0x04 | `a` id, `b` old, `c` new, `d, e` x, y, `f` reason (0 capture, 1 script) | recolour (`u_team`), capture flash ring, health-bar colour; the style stays (a captured neutral structure keeps the `neutral` look) |
| `STATE` 0x05 | `a` id, `b` state, `c` value, `d` duration ticks (0 = open), `e, f` x, y | `ViewEntity.on_state`: `ST_DEPLOYING 1` and `ST_PACKING 3` ease `deploy` over `d`; `ST_DEPLOYED 2`, `ST_PACKED 4` set it; `ST_CLOAKED 5`, `ST_DECLOAKED 6` cloak ease + shimmer ping; `ST_EMP 7` `UF_EMP` for `d` ticks (0 = until the next STATE) + `emp_arc` loop; `ST_SHUTDOWN 8` structure shutdown look; `ST_SUPPRESSED 9` crouch + pip; `ST_LANDED 10`, `ST_TAKEOFF 11` dust and gear cue; `ST_SELLING 12` reverse buildup over `d`; `ST_POWERED 13` refresh `UF_UNPOWERED`; `ST_MODE_SWITCH 14` short shimmer (`c` = new mode); `ST_REPAIRING 15` wrench sparks while `c` = 1. Flags stay the persistent truth for `_reconcile` |
| `LOADED` 0x06, `UNLOADED` 0x07 | `a` passenger, `b` carrier, `c, d` x, y | hide / show (`F_INSIDE` is authoritative); carrier door cycle; `unload_puff` on UNLOADED; occupant counter of a garrison building `b` |
| `DAMAGE` 0x10 | `a` target, `b` attacker, `c` hp lost, `d` damage type, `e` weapon def idx, `f` flags (1 kill blow, 2 suppressive, 4 splash, 8 crush), `g, h` x, y | coalesced per victim per frame: `on_hit` (flash unless kill blow), health-bar mark, hit spark at `(g, h)` for instant weapons (hit inference, §5.9.2) |
| `WEAPON_FIRED` 0x11 | `a` shooter, `b` weapon def idx, `c` target (0 = ground), `d, e` aim x, y, `f` muzzle_idx (`mount \| barrel << 4`), `g, h` muzzle x, y | `on_fire(mount, barrel)` recoil; muzzle FX at the socket (§5.9.2); instant weapons: tracer to `(d, e)`, hit or miss inferred |
| `PROJECTILE_LAUNCHED` 0x12 | `a` proj_id, `b` weapon idx, `c` shooter, `d, e` start, `f, g` end, `h` flight ticks | `ViewProjectiles.spawn`; shells and bombs: analytic FX from start, end and flight |
| `PROJECTILE_IMPACT` 0x13 | `a` proj_id, `b` weapon idx, `c, d` x, y, `e` target, `f` result (1 entity, 2 ground, 3 water, 4 intercepted, 5 expired), `g` splash radius units, `h` owner | free the mirrored projectile; impact FX by result and archetype (§5.9.3), scorch; shake comes from the effect recipe |
| `EXPLOSION` 0x14 | `a, b` x, y, `c` radius units, `d` fx_kind, `e` owner, `f` source id, `g` damage type | `FxCatalog.explosion_id(fx_kind, c, g)` -> effect at `(a, b)`, scorch, shake from the recipe; used by combat, power and ability effects |
| `BEAM` 0x15 | `a` shooter, `b` weapon idx, `c` target, `d` start (1) / stop (0), `e, f` target x, y | start / stop a `start_tracker` beam (segments 0.14 s every 0.07 s) from the muzzle socket to the target entity, or to `(e, f)` for a ground target |
| `INTERCEPT` 0x16 | `a` interceptor id, `b` proj_id, `c, d` x, y, `e` charges or cooldown ticks | `aps_flash` at `(c, d)`; when `a` is a zone, dome ring pulse and charge brightness |
| `HEAL` 0x17 | `a` target, `b` amount, `c` source, `d` kind (1 engineer, 2 medic, 3 aura, 4 station, 5 drone, 6 structure auto-repair), `e, f` x, y | green motes (`repair_mote`) on the target; at most one per target per 20 ticks |
| `SALVAGE` 0x19 | `a` salvager, `b` wreck, `c` credits, `d` phase (0 start, 1 done, 2 aborted), `e, f` x, y | 0: `salvage_sparkle` loop on the wreck; 1: stop, "+$c" floater (local player's only), wreck consumed; 2: stop |
| `HARVEST_DELIVERED` 0x21 | `a` collector, `b` refinery, `c` amount, `d` pid | refinery unload arm cycle, "+$" floater (local player's only, aggregated per refinery over 0.5 s), collector bin empties |
| `POWER_LOW` 0x22, `POWER_RESTORED` 0x23 | `a` pid, `b` produced, `c` consumed | refresh `UF_UNPOWERED` of that owner's structures at the next sample (`F_POWERED` is the truth) |
| `PRODUCTION_COMPLETE` 0x26 | `a` pid, `b` def, `c` producer id, `d` spawned id | producer door cycle (0.6 / 1.0 / 0.6 s), exit dust |
| `POWER_USED` 0x30 | `a` pid, `b` power idx, `c, d` x, y, `e` angle, `f` duration ticks | cast FX anchor and buff rings (§5.9.6) |
| `SW_READY` 0x33 | `a` pid, `b` sw idx, `c` launcher id | launcher armed glow (faster BLINK) until `SW_LAUNCHED` or `SW_CANCELLED` |
| `SW_WARNING` 0x34 | `a` owner, `b` sw idx, `c, d` x, y, `e` angle, `f` warning ticks, `g` launcher id, `h` extent units | `ViewWarnings.add`, shown when the local team is affected (§5.9.5) |
| `SW_LAUNCHED` 0x35 | `a` owner, `b` sw idx, `c, d` x, y, `e` angle | launch FX at the launcher, pre-impact timeline (§5.9.5) |
| `SW_CANCELLED` 0x36 | `a` owner, `b` sw idx, `c` reason (1 launcher destroyed, 2 EMP shutdown) | cancel warning and pre-impact FX instantly |
| `SW_IMPACT` 0x37 | `a` owner, `b` sw idx, `c, d` x, y, `e` radius units, `f` packet index | per-packet impact FX |
| `ABILITY` 0x40 | `a` unit, `b` ability idx, `c` action (0 use, 1 on, 2 off), `d, e` x, y, `f` target | by the ability's `AbilityKind`: DECOY_SPAWN `decoy_spawn`, SMOKE_LAUNCHER launcher puff, PORTABLE_COVER build motes, SENSOR_PUCK deploy blip; CAMOUFLAGE none (`STATE` covers it) |
| `REVEAL_AREA` 0x42 | `a` pid, `b, c` x, y, `d` radius units, `e` duration ticks, `f` detects | scan pulse ring and faint grid disc for the caster's team |
| `MATCH_END` 0x71 | `a` winner team, `b` reason, `c` tick | optional victory / defeat camera orbit (`cinematic_play`, setting `camera/end_orbit`); clocks keep running |
| `PAUSED` 0x72, `UNPAUSED` 0x73 | `a` pid | none (the view follows `sim.paused` every frame; the overlay is `ui`) |

#### 6.2.3 Alias table: proposals of the other specs and their MASTER equivalents

The router keys on the MASTER names only. The numeric ranges proposed elsewhere (combat 200-229, abilities 230-259, economy 300-499, movement 0x40-0x49) are **not** consumed; each proposal is listed with the master event that carries its information and what is lost or derived (the reconcilers should make the master authoritative, `qa.md` XR-30).

| Proposal (source) | MASTER equivalent | Gap and treatment |
|---|---|---|
| `EV_FIRE` 200 (combat) | `WEAPON_FIRED` (+ `DAMAGE` for the outcome) | `result` and projectile kind absent: kind from the archetype, outcome inferred (§5.9.2); request 3 |
| `EV_PROJ_SPAWN` 201, `EV_PROJ_END` 202 | `PROJECTILE_LAUNCHED`, `PROJECTILE_IMPACT` (results 4 and 5) | end reasons APS, zone, sweep-done folded into `result` |
| `EV_IMPACT` 203, `EV_HIT` 204 | `PROJECTILE_IMPACT` / `EXPLOSION`, `DAMAGE` | total damage absent (shake from the recipe); hp after and hp max are read from the entity |
| `EV_BEAM_START/END` 205/206, `EV_SWEEP` 207 | `BEAM`; none | Helios hot spot derived from the warning geometry (§5.9.5) |
| `EV_DEATH` 208, `EV_WRECK_ADD/REMOVE` 209/210, `EV_CRASH` 219 | `DIED`, wreck `SPAWNED` (reason 5) / `REMOVED`; none | death kind, visual ticks and crash timeline are view data (§5.9.4) |
| `EV_INTERCEPT` 211 | `INTERCEPT` | |
| `EV_SUPPRESS` 212, `EV_EMP` 213, `EV_WEAPON_LOCK` 220 | `STATE ST_SUPPRESSED / ST_EMP`, flag `F_WEAPONS_OFF` | |
| `EV_ATTACK_ALERT` 214 | `BASE_UNDER_ATTACK` and siblings | UI and audio only |
| `EV_AIR_STATE` 215, `EV_REARM` 216 | `STATE ST_LANDED / ST_TAKEOFF`, flag `F_AIRBORNE`; none | rearm sparks need request 7 |
| `EV_DRONE` 217, `EV_EJECT` 218, abilities `EV_LOADED/UNLOADED/EJECTED/GARRISON_CHANGED` 240-244 | `SPAWNED` (with `parent`), `F_INSIDE`, `LOADED` / `UNLOADED` | occupant counter kept by the view |
| `EV_CLOAK_CHANGED` 230, `EV_MODE_STARTED/CHANGED` 234/235 | `STATE ST_CLOAKED / ST_DECLOAKED`, `ST_DEPLOYING / ST_PACKING / ST_MODE_SWITCH` | |
| `EV_VIS_CHANGED` 231, `EV_GHOST_ADDED/REMOVED` 232/233 | polling: `entity_visible`, `fog.ghosts` | request 9 |
| `EV_ABILITY_USED` 236, `EV_ZONE_SPAWNED/ENDED` 246/247, `EV_SUMMONED` 248, `EV_SUMMON_EXPIRED` 249 | `ABILITY`; ZONE entity `SPAWNED` / `REMOVED`; `SPAWNED` reason 4; `REMOVED` reason 2 | |
| `EV_FX_APPLIED/REMOVED` 238/239, `EV_MARKED` 258, `EV_BUFF_APPLIED` 259 | none (`POWER_USED` approximation, §5.9.6) | request 13 |
| `EV_SCAN_WARNING` 250 | none | request 5 (`POWER_WARNING`) |
| `EV_SALVAGE_DONE` 251, `EV_CAPTURE_DONE` 252, `EV_REPAIR_PULSE` 254, `EV_DECOY_IDENTIFIED` 255 | `SALVAGE`, `OWNER_CHANGED`, `HEAL`; none | request 10 for decoys |
| `EV_SWARM_LAUNCHED` 256, `EV_ENGINE_ASSEMBLED` 257 | `SW_LAUNCHED`; engine `SPAWNED` + capsule `REMOVED` (recipe `meta.spawn_fx`) | |
| economy `EVT_STRUCTURE_PLACED/ACTIVE/SELLING/SOLD` 303-315, `EVT_UNIT_PRODUCED` 305 | `SPAWNED` reason 2, `STATE ST_SELLING`, `REMOVED` reason 1; `PRODUCTION_COMPLETE` | build-up length: request 6 |
| `EVT_POWER_SHORTAGE/RESTORED` 311/312, `EVT_CAPTURE_PROGRESS` 324, `EVT_DEPOSIT_DEPLETED/REGROWN` 322/323 | `POWER_LOW` / `POWER_RESTORED`; none; `MapData.drain_deposit_dirty` polling | request 8 for capture progress |
| `EVT_POWER_ACTIVATED` 402, `EVT_WARNING` 404, `EVT_SW_CANCELLED/EXEC_START/IMPACT/DONE` 406-409 | `POWER_USED`, `SW_WARNING`, `SW_CANCELLED`, `SW_LAUNCHED`, `SW_IMPACT` | |
| movement `EV_MEDIUM_CHANGED` 0x41, `EV_AIR_TAKEOFF/LANDED` 0x42/0x43, `EV_BOARDED/UNBOARDED` 0x44/0x45, `EV_DOCKED/UNDOCKED` 0x46/0x47 | flag `F_ON_WATER` transitions, `STATE ST_TAKEOFF / ST_LANDED`, `LOADED` / `UNLOADED`, `HARVEST_DELIVERED` | |

#### 6.2.4 Events the view asks to add (details in section 13)

`WEAPON_FIRED.f` high bits `result` (request 3); `POWER_WARNING` 0x38 with the layout of `SW_WARNING` (request 5); `STATE` values `ST_BUILDUP 16` (request 6), `ST_REARMING 17` (request 7), `ST_BUFF 18` and `ST_MARKED 19` (request 13); `CAPTURE_PROGRESS` 0x1A (request 8); `EXPLOSION.d` = index into `GameData.pres_names` (request 4). Every one of them is optional: the view degrades to the fallback named in the text.

### 6.3 What other domains must add (details in section 13)

The MASTER catalog as the single event table with the ordering guarantees of 6.2.1; structure orientation in `SimEntity.facing`; the fallbacks-eliminating additions of 6.2.4; `SimFogApi.ghosts` and `decoy_identified`; the optional pre-step hook; string presentation ids on defs; footprint anchors (`door`, `exit_dir`, `dock`, `pads`) reachable from `GameData`.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.1 File inventory (`game/data/recipes/`)

| File | Content | Sorted / rules |
|---|---|---|
| `index.json` | `{"schema":"meridian.recipes.index/1","ids":[…]}` sorted list of every recipe id (data domain check V-REF-02) | written by `tools/py/gen_recipe_index.py`, validated |
| `styles.json` | 8 faction styles + 24 subfaction styles (`extends`) + `neutral` | keys sorted |
| `archetypes/<name>.json` | 56 archetypes (§5.8.6) | one per file |
| `<recipe id>.json` | one recipe per def id (e.g. `unit.napc.guardian_tank.json`, `structure.shared.factory.json`, `summon.napc.uav.json`, `proj.missile.json`) | data_balance.md 7.15: default recipe id = def id; neutrals and summons may also be covered by `assignments.json` patterns |
| `assignments.json` | balance archetype -> view archetype rules + per-unit overrides + glob patterns for neutrals and summons (input to the stub generator) | |
| `fx.json` | effects, templates, default mapping tables | keys sorted |
| `moods.json` | 5 moods and the biome / family mapping | |
| `quality.json` | preset tables (§4.9) + renderer clamps | |

All files: UTF-8, LF, 2-space indent, strict JSON (no comments, no trailing commas), `schema` string on the root, keys starting with `_` ignored (documentation).

### 7.2 Archetype (`archetypes/veh_tank.json`, the spike tank converted; condensed)

Merge order for parameter `p`: **recipe.params > style.kit > archetype.defaults**. `derive` lets are evaluated top to bottom after the merge. `slot` ops are filled by `recipe.slots > style.slots > archetype.slots`.

```json
{
  "schema": "meridian.archetype/1",
  "id": "veh_tank",
  "size_class": "medium",
  "meta": { "motion": "tracked", "wreck": { "turret_yaw_deg": 25, "tilt_deg": [3, 0, -6] } },
  "defaults": {
    "len": 3.5, "hull_w": 1.92, "hull_top": 1.16, "glacis": 0.75, "track_w": 0.46, "track_x": 0.88, "wheel_n": 5, "wheel_r": 0.30,
    "skirt": "modules", "turret_n": 8, "turret_rot": 22.5, "turret_hw": 0.74, "turret_hl": 0.96, "turret_h": 0.42, "turret_top": 0.72,
    "turret_z": 0.18, "turret_shift": 0.06, "barrel_len": 2.0, "barrel_r": 0.075, "muzzle": "brake", "roof": "cupola", "deck": "none",
    "float_skirt": false
  },
  "derive": {
    "hl": "len*0.5", "hw": "hull_w*0.5", "tk": 0.07, "ty0": "hull_top+0.07",
    "gy": "ty0+turret_h*0.5", "top_y": "ty0+turret_h", "fz": "turret_z-turret_hl*(1+turret_top)*0.5+turret_shift*0.5"
  },
  "slots": { "skirt": [], "roof": [], "deck": [] },
  "ops": [
    ["bevel", 0.04],
    { "mirror_x": [
      { "call": "track_run", "args": { "x": "track_x", "width": "track_w", "z_front": "hl-0.42", "z_rear": "-hl+0.44", "sprocket_r": 0.34, "road_n": "wheel_n", "road_r": "wheel_r", "tk": "tk" } },
      { "slot": "skirt" }
    ] },
    ["brush", "dark"], ["ao", 0.7],
    ["box", [0, 0.58, 0], ["(track_x-track_w*0.5-0.02)*2", 0.55, "len-0.15"], 0.03],
    ["ao", 1.0],
    ["brush", "base"],
    ["extrude", [["-hl", 0.86], ["-hl", "hull_top-0.10"], ["-hl+0.5", "hull_top"], ["hl-glacis", "hull_top"], ["hl", 0.92], ["hl-0.05", 0.86]], "-hw", "hw", 0.05],
    { "slot": "deck" },
    { "call": "team_panel", "args": { "center": [0, "hull_top+0.014", "-(hl-glacis)*0.5-0.35"], "size": ["hw*1.2", 0.03, 0.34] } },
    { "call": "light_pair", "args": { "center": [0, 0.97, "-hl+0.02"], "spacing": "(hw-0.28)*2", "size": [0.20, 0.09, 0.05], "col": "light" } },
    { "part": { "kind": "turret", "pivot": [0, "hull_top", "turret_z"] }, "do": [
      { "call": "turret_ngon", "args": { "pivot": [0, "hull_top", "turret_z"], "n": "turret_n", "rot": "turret_rot", "hw": "turret_hw", "hl": "turret_hl", "h": "turret_h", "top": "turret_top", "shift": "turret_shift", "y0": "ty0" } },
      { "slot": "roof" }
    ] },
    { "call": "gun", "args": { "mount": 0, "pivot": [0, "hull_top", "turret_z"], "y": "gy", "z": "fz-0.14", "len": "barrel_len", "r": "barrel_r", "muzzle": "muzzle" } },
    { "if": "float_skirt", "then": [ { "call": "hover_skirt", "args": { "len": "len", "wid": "hull_w+0.3", "h": 0.5 } } ] },
    ["socket", "muzzle0_0", [0, "gy", "fz-0.14-barrel_len-0.3"], [0, 0, -1], "barrel"],
    ["socket", "exhaust0", [0.5, 0.95, "hl"], [0, 1, 0]],
    ["socket", "top", [0, "top_y+0.5", 0], [0, 1, 0]]
  ]
}
```

**Style** (`styles.json`, excerpt): kit values override the archetype defaults for every unit of the faction; `slots` supply faction-specific part lists; subfaction styles `extend`.

```json
{
  "schema": "meridian.styles/1",
  "styles": {
    "napc": {
      "palette": { "base": "#4d592e", "dark": "#2b331a", "sec": "#d6c799", "acc": "#ed5e0f", "metal": "#525450", "rubber": "#121210",
                   "glass": "#173340", "light": "#ffd98c", "plate": "#1a1a18", "concrete": "#807d75" },
      "material": { "wear": 0.5, "dirt": 0.5, "panel": 0.65, "wear_color": "#c7bda8", "dirt_color": "#4d3d2b", "emissive": 2.5 },
      "kit": { "skirt": "modules", "turret_n": 8, "turret_rot": 22.5, "muzzle": "brake", "roof": "cupola", "helmet": "round" },
      "slots": {
        "skirt": [
          { "for": "i", "n": 6, "do": [
            ["brush", "i % 2 == 0 ? 'base' : 'sec'", "paint", "i == 0 ? 1 : 0"],
            ["box", ["track_x+track_w*0.5+0.06", 0.70, "-hl+0.25+(len-0.5)/6*(i+0.5)"], [0.09, 0.40, "(len-0.5)/6-0.07"], 0.02]
          ] }
        ]
      },
      "team_plate": "band", "emblem": "none"
    },
    "nec": {
      "palette": { "base": "#455c80", "dark": "#293850", "sec": "#e6ebf0", "acc": "#f29e1a", "metal": "#4d525c", "rubber": "#0f0f12",
                   "glass": "#264d6b", "light": "#ffbf4d", "plate": "#14181f", "concrete": "#8a8f96" },
      "material": { "wear": 0.4, "dirt": 0.35, "panel": 0.7, "wear_color": "#d9dde2", "dirt_color": "#3a3f47", "emissive": 2.5 },
      "kit": { "len": 3.8, "hull_w": 1.80, "hull_top": 0.98, "glacis": 1.25, "track_w": 0.40, "track_x": 0.82, "wheel_n": 6, "wheel_r": 0.25,
               "skirt": "slab", "turret_n": 6, "turret_rot": 30.0, "turret_hw": 0.62, "turret_hl": 1.15, "turret_h": 0.30, "turret_top": 0.55,
               "turret_z": 0.42, "turret_shift": 0.15, "barrel_len": 2.7, "barrel_r": 0.058, "muzzle": "plain", "roof": "mast" },
      "team_plate": "band"
    },
    "napc.canada": { "extends": "napc", "palette": { "acc": "#e8e8e8", "sec": "#c9d2c0" }, "kit": { "float_skirt": false }, "emblem": "bar_notch" }
  }
}
```

The kit table above reproduces the spike's four verified tank styles (NAPC modular-skirt octagon turret, NEC low hexagonal wedge with mast, DEF boxy slab with container, HAN compact round turret with sensor crown) `[M]`.

Second archetype (squads; shows `members`, the gait parts through the `soldier` macro, and the readability scale). `soldier` calls `member(i, n)`, sets gait phase `(i+0.5)/n` in CUSTOM0.z and emits every primitive of the soldier under LEG_A/LEG_B/ARM_A/BODY_BOB parts:

```json
{
  "schema": "meridian.archetype/1",
  "id": "inf_rifle",
  "size_class": "inf",
  "scale": 1.25,
  "meta": { "motion": "foot" },
  "defaults": { "n": 4, "kit": "rifle", "helmet": "round", "spread": 0.55, "pack": "small" },
  "slots": { "gear": [] },
  "ops": [
    ["meta", "members", "n"],
    { "for": "i", "n": "n", "do": [
      { "call": "soldier", "args": {
        "x": "cos(i*TAU/n + 0.6)*spread*(0.6 + 0.4*rnd(i))",
        "z": "sin(i*TAU/n + 0.6)*spread*(0.6 + 0.4*rnd(i+9))",
        "phase": "(i + 0.5)/n", "member": "i", "count": "n", "kit": "kit", "helmet": "helmet", "pack": "pack" } }
    ] },
    { "slot": "gear" },
    ["socket", "muzzle0_0", [0.20, 0.64, -0.62], [0, 0, -1]],
    ["socket", "top", [0, 1.35, 0], [0, 1, 0]]
  ]
}
```

### 7.3 Recipes

**Unit** (`unit.napc.guardian_tank.json`): archetype + params + optional extra parts. Unit recipes stay short; unique parts go into `slots` or `ops_after`.

```json
{
  "schema": "meridian.recipe/1",
  "id": "unit.napc.guardian_tank",
  "archetype": "veh_tank",
  "style": "auto",
  "scale": 1.0,
  "params": { "len": 3.5, "wheel_n": 5, "barrel_len": 2.0, "skirt": "modules", "roof": "cupola" },
  "slots": {
    "roof": [
      { "call": "hatch", "args": { "c": ["turret_hw*0.36", "top_y", "turret_z+turret_hl*0.30"], "r": 0.15, "body": "sec", "ring": "acc" } },
      { "call": "whip", "args": { "base": ["-turret_hw*0.6", "top_y", "turret_z+turret_hl*0.85"], "tip": ["-turret_hw*0.62", "top_y+1.15", "turret_z+turret_hl*0.9"], "r": 0.011, "col": "metal" } }
    ]
  },
  "ops_after": [],
  "meta": { "role": "tank", "icon": { "yaw": 150, "pitch": 24, "margin": 0.78 } }
}
```
`style: "auto"` -> `unit.<fac>.*` uses that faction's style; `*.shared.*` recipes are instantiated with the **owner's** style (`ViewRecipeBook.style_for_def`).

**Structure** (`structure.shared.factory.json`, excerpt showing footprint anchors, front on +Z, 10-slat roller door driven by `u_aux.y`). The builder injects `fw, fh` (footprint cells of orientation 0, from `DefStructure.fp_w / fp_h`, so a reconciled footprint never needs a recipe edit) and the anchors of `footprints.json` (terrain_movement.md 7.3) as variables: `door_cx, door_cz` = centre of the door / interaction cell in metres from the footprint centre (+Z = south; for the 4x3 factory with `door [1, 3]`: `cx = (1 + 0.5 - 2) * 3 = -1.5`, `cz = (3 + 0.5 - 1.5) * 3 = 6.0`, one cell outside the south wall), `exit_dir` (bat, 1024 = south), `dock_cx, dock_cz, dock_dir` (refinery bay), `pads_n` and `pad_x(i)`, `pad_z(i)` (airfield pad centres); missing anchors default to the middle of the south side:

```json
{
  "schema": "meridian.recipe/1",
  "id": "structure.shared.factory",
  "archetype": "str_factory",
  "style": "auto",
  "params": { "height": 6.5, "hall_h": 3.6, "door_w": "min(3.76, fw*3-1.6)", "roof": "skylights", "stacks": 2 },
  "ops_after": [
    { "for": "i", "n": 10, "do": [
      { "part": { "kind": "door", "extra": "2.88-0.25*i" }, "do": [
        ["brush", "i % 3 == 0 ? 'sec*0.85' : 'sec'"],
        ["box", ["door_cx", "0.29+0.30*i", "fh*1.5-0.03"], ["door_w", 0.28, 0.07], 0.01]
      ] }
    ] },
    ["socket", "door_exit", ["door_cx", 0, "door_cz"], [0, 0, 1]],
    ["socket", "weld0", [1.2, "height", 0.8], [0, 1, 0]],
    ["meta", "footprint", ["fw", "fh"]]
  ]
}
```
Structures always start with `foundation(fw, fh, 1.2)` (skirt below origin) and stay inside `(fw*3-0.5) x (fh*3-0.5)` m. Rotation is not authored: the whole model is yawed by `-rot * PI/2` at placement (§5.1).

### 7.4 Index and assignments

Patterns use `fnmatch` semantics on the def id (`*` matches any run of characters including dots) and are evaluated top to bottom after exact ids and `overrides`; an optional `"style": "owner"` instantiates the match with the owning player's style; a def that matches nothing gets a generated stub and warning V-RCP-02.

```json
{ "schema": "meridian.recipes.index/1", "ids": ["neutral.civilian_garrison", "neutral.field_hospital", "proj.bomb", "proj.missile", "structure.ae.forge_cannon", "unit.ae.anchor_escort"] }
```
```json
{
  "schema": "meridian.recipes.assignments/1",
  "balance_to_view": { "inf_line": "inf_rifle", "inf_at": "inf_at", "inf_support": "inf_support", "inf_combat_spec": "inf_special", "service.engineer": "inf_engineer",
    "veh_scout": "veh_apc", "arty_light": "veh_lightarty", "mbt_t1": "veh_tank", "mbt_t2": "veh_tank", "mbt_t2_rail": "veh_tank",
    "siege_ap": "veh_siege", "siege_he": "veh_siege", "siege_rail": "veh_siege", "siege_beam": "veh_siege", "siege_demo": "veh_siege",
    "veh_aa": "veh_aa", "veh_aa_beam": "veh_aa", "veh_aa_flak": "veh_aa", "arty_howitzer": "veh_howitzer", "arty_rocket": "veh_rocket", "arty_missile": "veh_rocket",
    "veh_command": "veh_walker", "veh_assault_carrier": "veh_hovercarrier", "service.collector": "veh_collector", "service.mcv": "veh_mcv", "service.landing_transport": "veh_landing",
    "air_fighter": "air_jet", "air_gunship": "air_heli", "air_bomber": "air_bomber", "air_drone": "air_drone", "air_ew": "air_ew",
    "ship_patrol": "ship_patrol", "ship_escort": "ship_escort", "ship_siege": "ship_siege", "ship_carrier": "ship_carrier", "ship_sub": "ship_sub" },
  "ability_rules": [ { "when_view": "veh_apc", "has_ability": "amphibious", "then": "veh_amphib" } ],
  "patterns": [
    { "match": "neutral.*garrison*", "archetype": "neu_building", "params": { "kit": "garrison" } },
    { "match": "neutral.*substation", "archetype": "neu_building", "params": { "kit": "substation" } },
    { "match": "neutral.*outpost", "archetype": "neu_building", "params": { "kit": "outpost" } },
    { "match": "neutral.observation_*", "archetype": "neu_building", "params": { "kit": "outpost" } },
    { "match": "neutral.salvage_depot", "archetype": "neu_building", "params": { "kit": "depot" } },
    { "match": "summon.*uav", "archetype": "sum_uav" },
    { "match": "summon.*decoy_light_vehicle", "archetype": "veh_apc", "style": "owner" },
    { "match": "summon.*dragonfall_capsule", "archetype": "sum_capsule" }
  ],
  "overrides": { "unit.olm.dune_rover": { "archetype": "veh_apc", "params": { "chassis": "buggy" } } }
}
```

### 7.5 `fx.json`

Root: `{"schema":"meridian.fx/1","classes":{…},"mappings":{…},"effects":{…}}` (`classes.*.max_dist` 0 = unlimited). An **effect** = `{class, kind, radius, scale, vars, layers}`; `extends` (single inheritance, child `vars` override, child `layers` replace when present); `template: true` effects are not spawnable. `kind` ∈ point / line / area. Layer `op` set: `sprites, puff, ring, dome, column, ribbon, tracer, trail, cone, beam, rail, bolt, shimmer, light, scorch, shake, fx` (schedule a sub-effect), `loop`, `for`, `if`, `native` (escape hatch to a GDScript function registered in `FxRecipeBook.natives`, e.g. the random EMP arcs). Every layer accepts `when` (expression, skip if false) and `delay` (seconds; > 0 becomes `schedule`).

*Expression scope:* `a`, `b` (Vector3 anchors), `s` (scale argument), `dist = |b−a|`, `flight = dist/speed` helpers, plus `vars`; `impact_rules` additionally see `dtype` (name of the data `DamageType`: bullet, ap, he, thermal, rail, kinetic, emp), `splash_m`, `strategic` (bool: `SW_IMPACT`, or an `EXPLOSION` whose `fx_kind` names a strategic effect) and `result` (`PROJECTILE_IMPACT.f`); functions of §5.8.3 plus `rand()` (uniform 0..1, presentation-only RNG, FX scope only; model recipes use the deterministic `rnd(n)`), `randr(lo, hi)`, `rsq()` (uniform in [-1, 1], fresh on every call). *Positions:* `at` (`"a"` | `"b"`, default `a`), `along` (metres from the anchor along `dir(a→b)`), `off` (3 expressions, added last); the `fx` (sub-effect) op also takes `b_at` / `b_off` for the child's `b` anchor. Sizes in metres, times in seconds, `pal` = palette index (§4.7).

```json
{
  "schema": "meridian.fx/1",
  "classes": {
    "tiny":   { "max_dist": 70,   "min_px": 2.5, "refill": 500, "burst": 60 },
    "small":  { "max_dist": 110,  "min_px": 4,   "refill": 200, "burst": 40 },
    "medium": { "max_dist": 200,  "min_px": 6,   "refill": 60,  "burst": 20 },
    "large":  { "max_dist": 350,  "min_px": 8,   "refill": 30,  "burst": 10 },
    "beam":   { "max_dist": 200,  "min_px": 3,   "refill": 90,  "burst": 24 },
    "super":  { "max_dist": 0,    "min_px": 0,   "refill": 10,  "burst": 4 }
  },
  "mappings": {
    "muzzle_by_family": { "small_arms": "muzzle_small_arms", "machine_gun": "muzzle_mg", "tank_cannon": "muzzle_cannon", "siege_gun": "muzzle_siege", "artillery_shell": "muzzle_artillery", "beam_thermal": "muzzle_beam_thermal", "rail_gun": "muzzle_rail" },
    "impact_rules": [
      { "if": "dtype == 'emp'", "fx": "emp_pulse" },
      { "if": "dtype == 'kinetic'", "fx": "expl_kinetic" },
      { "if": "strategic", "fx": "expl_strategic_large" },
      { "if": "splash_m <= 0.01 and dtype == 'rail'", "fx": "hit_rail" },
      { "if": "splash_m <= 0.01 and dtype == 'thermal'", "fx": "beam_thermal_hit" },
      { "if": "splash_m <= 0.01", "fx": "hit_bullet" },
      { "if": "splash_m <= 3.0", "fx": "expl_small" },
      { "if": "splash_m <= 5.0", "fx": "expl_medium" },
      { "if": "true", "fx": "expl_large" }
    ],
    "death_by_kind": { "vehicle": "death_vehicle", "infantry": "death_infantry", "crash": "aircraft_crash", "air_explode": "death_air_explode", "sink": "death_sink", "structure": "building_collapse", "drone": "death_drone", "silent": "death_silent" },
    "arc_apex": { "artillery_shell": 0.25, "mortar": 0.35, "missile_artillery": 0.5, "naval_bombard": 0.2, "cruise_missile": 0.6, "grenade_launcher": 0.3, "siege_gun": 0.08, "demolition_cannon": 0.15 },
    "explosion_kinds": ["auto", "strategic", "kinetic", "emp", "underwater", "air_burst", "fragment_ring"],
    "superweapons": {
      "atlas_kinetic_array": { "shape": "rods", "radius_m": 6.0, "offsets_cells": [-3, 0, 3], "rod_ticks": [0, 4, 8] },
      "helios_reflector": { "shape": "capsule", "length_m": 48.0, "width_m": 9.0, "sweep_s": 12.0 },
      "trident_interception_array": { "shape": "disc", "radius_m": 18.0, "visible_to_all": true }
    }
  },
  "effects": {
    "tpl_explosion": {
      "template": true, "class": "medium", "kind": "point", "radius": 8.0,
      "layers": [
        { "op": "sprites", "batch": "glow",   "off": [0, "r*0.3", 0], "size": "r*1.7", "life": "0.16+0.012*r", "param": 0.7, "pal": 0 },
        { "op": "sprites", "batch": "flash",  "off": [0, "r*0.3", 0], "size": "r*2.2", "life": 0.13, "param": 1.0, "pal": 0 },
        { "op": "sprites", "batch": "gglow",  "size": "r*2.2", "life": "0.45+0.05*r", "param": 1.0, "pal": 6 },
        { "op": "sprites", "batch": "fire",   "size": "r", "life": "0.55+0.11*r" },
        { "op": "sprites", "batch": "smoke",  "size": "r", "life": "1.7+0.3*r" },
        { "op": "sprites", "batch": "sparks", "size": "r", "life": "0.65+0.04*r" },
        { "op": "sprites", "batch": "debris", "size": "r", "life": "1.0+0.06*r", "when": "r >= 1.2" },
        { "op": "ring", "batch": "ring_distort", "radius": "r*2.4", "life": "0.5+0.03*r", "when": "r >= 2.4" },
        { "op": "ring", "batch": "ring_add",     "radius": "r*2.2", "life": "0.55+0.02*r", "when": "r >= 2.4" },
        { "op": "sprites", "batch": "dustring", "size": "r*1.25", "life": "1.1+0.08*r", "when": "r >= 2.4" },
        { "op": "sprites", "batch": "dustcol",  "size": "r", "life": "2.2+0.2*r", "when": "r >= 4.5" },
        { "op": "light", "off": [0, "r*0.8", 0], "color": [1.0, 0.62, 0.25], "energy": "3+r*0.9", "range": "6+r*3", "life": "0.2+0.02*r" },
        { "op": "scorch", "radius": "r*0.95", "life": "r >= 6 ? 90 : 45", "hot": "r >= 1.2 ? 1 : 0" },
        { "op": "shake", "amount": "shake" }
      ]
    },
    "expl_small":  { "extends": "tpl_explosion", "vars": { "r": "1.8*s", "shake": "0.12*s" } },
    "expl_medium": { "extends": "tpl_explosion", "vars": { "r": "3.6*s", "shake": "0.30*s" } },
    "expl_large":  { "extends": "tpl_explosion", "class": "large", "vars": { "r": "8.0*s", "shake": "0.70*s" } },
    "muzzle_cannon": {
      "class": "medium", "kind": "line", "radius": 3.0,
      "vars": { "speed": 120 },
      "layers": [
        { "op": "cone",    "along": 0, "length": "4.6*s", "width": "2.4*s", "life": 0.11 },
        { "op": "sprites", "batch": "flash", "along": "0.9*s", "size": "3.0*s", "life": 0.10, "pal": 0 },
        { "op": "sprites", "batch": "glow",  "along": "0.6*s", "size": "6.0*s", "life": 0.16, "pal": 0 },
        { "op": "puff", "batch": "puff_smoke", "along": "1.4*s", "off": [0, 0.2, 0], "size": "2.6*s", "life": 1.5, "alpha": 0.55 },
        { "op": "puff", "batch": "puff_smoke", "along": "2.6*s", "off": [0, 0.3, 0], "size": "3.4*s", "life": 1.9, "alpha": 0.40 },
        { "op": "light", "along": "1.5*s", "off": [0, 0.8, 0], "color": [1.0, 0.7, 0.35], "energy": 2.2, "range": "9*s", "life": 0.12 },
        { "op": "tracer", "along": "3.0*s", "to": "b", "speed": "speed", "tail": 6.0, "width": "0.30*s", "pal": 1 },
        { "op": "shake", "amount": "0.10*s" },
        { "op": "fx", "id": "expl_small", "at": "b", "delay": "dist/speed", "scale": "s" }
      ]
    },
    "sw_shockwave": {
      "class": "super", "kind": "area", "radius": 26.0, "scale": 1.0,
      "layers": [
        { "op": "fx", "id": "expl_large", "scale": "1.125*s" },
        { "op": "ring", "batch": "ring_distort", "radius": "21*s", "life": 1.6 },
        { "op": "ring", "batch": "ring_add", "radius": "21*s", "life": 1.7 },
        { "op": "ring", "batch": "ring_add", "radius": "11*s", "life": 0.9 },
        { "op": "sprites", "batch": "dustring", "size": "19*s", "life": 3.4 },
        { "op": "sprites", "batch": "dustcol",  "size": "14*s", "life": 8.0 },
        { "op": "sprites", "batch": "smoke", "off": [0, "6*s", 0], "size": "12*s", "life": 6.0 },
        { "op": "sprites", "batch": "glow",  "off": [0, "6*s", 0], "size": "40*s", "life": 0.45, "param": 0.6, "pal": 1 },
        { "op": "light", "off": [0, "10*s", 0], "color": [1.0, 0.85, 0.6], "energy": 14, "range": "80*s", "life": 0.7 }
      ]
    },
    "emp_pulse": {
      "class": "large", "kind": "area", "radius": 1.0, "scale": 10.0,
      "layers": [
        { "op": "ring", "batch": "ring_emp", "radius": "s", "life": 1.15, "pal": 7 },
        { "op": "ring", "batch": "ring_emp", "radius": "s*0.7", "life": 0.85, "pal": 4 },
        { "op": "ring", "batch": "ring_distort", "radius": "s", "life": 0.9 },
        { "op": "for", "var": "i", "n": 14, "do": [
          { "op": "fx", "id": "emp_arc", "at": "a", "off": ["rsq()*s*0.9", 0.25, "rsq()*s*0.9"], "b_at": "a", "b_off": ["rsq()*s*0.9", 0.25, "rsq()*s*0.9"], "delay": "rand()*0.8", "scale": 1.0 }
        ] }
      ]
    }
  }
}
```

**Effect catalogue** (ids; class in brackets): weapons `muzzle_*` (27, §5.9.2); impacts `hit_bullet, hit_bullet_hv, hit_bullet_structure, hit_rail, beam_thermal_hit, hit_flak_small [tiny/small]`, `expl_small/medium/large/kinetic/strategic_large/fragment_ring/air_burst [medium/large]`, `expl_underwater, expl_underwater_big, impact_water, impact_ground [small/medium]`, `emp_pulse, emp_arc, aps_flash`; deaths `death_vehicle_light/medium/heavy, death_infantry, aircraft_crash, death_air_explode, death_sink_small/large, death_drone, death_silent, building_collapse, collapse_burst, wreck_start, wreck_tick, damage_smoke, damage_fire`; locomotion `vehicle_dust, wake_foam, aircraft_contrail, rotor_wash, spawn_shimmer`; construction `build_dust, weld_tick, construction_sparks, build_complete, sell_dust, rearm_sparks, repair_mote, repair_pulse, unload_puff, exit_dust`; economy `credit_sparkle, salvage_sparkle, capture_flash`; strategic `sw_atlas_rod, sw_charge_dome, sw_microwave_dome, sw_helios_start, beam_helios_tick, sw_shockwave, sw_intercept_dome, sw_tempest_launch, sw_dragonfall_capsule, sw_assemble_burst, sw_horizon_impact, sw_warning_marker`; powers `power_cast_ring, power_scan_ring, zone_repair, zone_smoke, zone_debris, decoy_spawn, power_struct_glow`; beams `beam_thermal, beam_tick, beam_rail, rail_impact`. About 105 concrete ids plus ~10 templates; the 34 spike recipes are the seed.

**Prototype lineage** (the 34 spike recipes `[F]` `fx_recipes.gd`, all requested effect families, become these ids; behaviour and numbers are preserved unless §5.9 says otherwise): `rifle_shot -> muzzle_small_arms` (+ tracer, `hit_bullet`), `mg_burst -> muzzle_mg`, `cannon_shot -> muzzle_cannon`, `cannon_impact -> expl_small` (+ `puff_dust`), `explosion_small/medium/large -> expl_small/medium/large`, `missile_launch -> muzzle_at_missile` (variants `muzzle_air_missile`, `muzzle_drone_missile`), `artillery_shell -> muzzle_artillery` (+ arc, `expl_large`), `beam_thermal -> muzzle_beam_thermal` + tracker, `beam_tick -> beam_tick`, `beam_rail -> muzzle_rail`, `rail_impact -> hit_rail`, `emp_pulse`, `emp_arc` (same), `vehicle_destroy -> death_vehicle_light/medium/heavy`, `wreck_tick`, `wreck_start`, `building_collapse`, `collapse_burst` (same), `infantry_hit -> hit_infantry`, `contrail_puff` / `aircraft_contrail -> aircraft_contrail`, `aircraft_crash`, `impact_ground`, `impact_water`, `vehicle_dust`, `construction_sparks`, `weld_tick` (same), `sw_warning_marker` (kept as the beacon column; the zone itself is `ViewWarnings`), `sw_orbital_strike` + `strike_one -> sw_atlas_rod`, `sw_shockwave` (same), `sw_microwave_dome` (same).

### 7.6 `moods.json` (excerpt; numbers of the spike's temperate mood)

```json
{
  "schema": "meridian.moods/1",
  "biome_to_mood": { "0": "temperate_day", "1": "arid_dusk", "2": "arctic_day", "3": "tropical_day" },
  "family_override": { "1": { "when_biome": 0, "mood": "urban_night", "needs": "night_allowed" } },
  "moods": {
    "temperate_day": {
      "sun_elevation_deg": 40.0, "sun_azimuth_deg": 222.0, "sun_color": "#fff0d1", "sun_energy": 1.55,
      "sky_top": "#2b61c7", "sky_horizon": "#a8c7eb", "ground_horizon": "#94a3a3", "ground_bottom": "#3d4542",
      "ambient_energy": 0.78, "fog_color": "#a3c2e6", "fog_density": 0.0011, "fog_sun_scatter": 0.25, "fog_aerial": 0.35,
      "exposure": 1.18, "white_point": 5.0, "saturation": 1.12, "contrast": 1.06, "brightness": 1.0,
      "lift": [0.012, 0.018, 0.03], "gamma": [1.0, 1.0, 1.02], "gain": [1.03, 1.0, 0.95],
      "glow_intensity": 0.45, "glow_threshold": 1.15, "ssao_intensity": 1.5, "dryness": 0.0, "cloud_strength": 0.12,
      "water_shallow": "#299ea3", "water_deep": "#082e57", "water_absorb": 0.42,
      "foliage_a": "#29571a", "foliage_b": "#578024", "night": 0.0, "wet": 0.0, "decor_kit": "broadleaf",
      "compat_grade": { "lift": [0.0, 0.0, 0.0], "gamma": [0.92, 0.92, 0.95], "gain": [0.95, 0.95, 0.93] },
      "palette": { "grass_a": "#3d6b1f", "grass_b": "#6b9933", "dry_a": "#7a6b38", "dry_b": "#9e8c4d", "dirt_a": "#4a3826", "dirt_b": "#735940",
                   "rock_a": "#454240", "rock_b": "#756e66", "sand_a": "#b8a675", "sand_b": "#dbc996", "snow_c": "#edf5ff" }
    }
  }
}
```

### 7.7 `quality.json` and settings keys

```json
{
  "schema": "meridian.quality/1",
  "presets": {
    "low":    { "render_scale": 0.75, "scaling_mode": "fsr1", "msaa": 0, "fxaa": false, "shadow_mode": "blob", "ssao": "off", "ssil": false, "glow": false, "terrain_shader": "low", "terrain_subdiv": 1, "water_shader": "low", "decor_density": 0.5, "decor_groups": 4, "unit_shader_quality": 0, "mesh_lod_threshold": 2.0, "blob_contact_shadows": true, "cloud_shadows": false, "fx_quality": "low", "scorch_res": 512, "tread_marks": false, "proj_mesh_cap": 32 },
    "medium": { "render_scale": 1.0, "scaling_mode": "bilinear", "msaa": 0, "fxaa": true, "shadow_mode": "cascades2", "shadow_atlas": 2048, "shadow_filter": "soft_low", "decor_casts_shadow": false, "ssao": "low_half", "ssil": false, "glow": true, "terrain_shader": "full", "terrain_subdiv": 2, "water_shader": "full", "decor_density": 0.8, "decor_groups": 5, "unit_shader_quality": 1, "mesh_lod_threshold": 1.25, "blob_contact_shadows": false, "cloud_shadows": true, "fx_quality": "medium", "scorch_res": 1024, "tread_marks": true, "proj_mesh_cap": 64 },
    "high":   { "render_scale": 1.0, "scaling_mode": "bilinear", "msaa": 2, "fxaa": false, "shadow_mode": "cascades4", "shadow_atlas": 4096, "shadow_filter": "soft_high", "decor_casts_shadow": true, "ssao": "medium_half", "ssil": false, "glow": true, "terrain_shader": "full", "terrain_subdiv": 2, "water_shader": "full", "decor_density": 1.0, "decor_groups": 6, "unit_shader_quality": 1, "mesh_lod_threshold": 1.0, "blob_contact_shadows": false, "cloud_shadows": true, "fx_quality": "high", "scorch_res": 1024, "tread_marks": true, "proj_mesh_cap": 64 },
    "ultra":  { "render_scale": 1.0, "scaling_mode": "bilinear", "msaa": 3, "fxaa": false, "shadow_mode": "cascades4", "shadow_atlas": 8192, "shadow_filter": "soft_ultra", "decor_casts_shadow": true, "ssao": "high_full", "ssil": true, "glow": true, "terrain_shader": "full", "terrain_subdiv": 2, "water_shader": "full", "decor_density": 1.0, "decor_groups": 6, "unit_shader_quality": 1, "mesh_lod_threshold": 0.75, "blob_contact_shadows": false, "cloud_shadows": true, "fx_quality": "ultra", "scorch_res": 1024, "tread_marks": true, "proj_mesh_cap": 96 }
  },
  "renderer_clamps": {
    "mobile": { "ssao": "off", "ssil": false, "unit_backend": "batch" },
    "compatibility": { "ssao": "off", "ssil": false, "fxaa": false, "scaling_mode": "bilinear", "unit_backend": "batch", "fx_distort": false, "fx_compat_boost": 1.6 }
  }
}
```

`user://settings.cfg` keys read by `ViewQuality.from_settings` (written by `ui`/`app`; names follow QA-XR-13 where it defines them): `[video] quality` (0-3, 4 = auto), `renderer`, `fps_cap`, `render_scale`, `scaling_mode`, `msaa`, `fxaa`, `shadow_mode`, `ssao`, `ssil`, `glow`, `decor_density`, `health_bars` (0 never, 1 selected, 2 damaged, 3 always), `unit_backend` (-1 auto), `night_maps` (0 or 1, default 1), `wide_view`, `camera_wasd`; `[access] colour_mode` (`normal`, `protan`, `deutan`, `tritan`, `high_contrast`), `reduce_motion`, `reduce_flash`, `edge_scroll_enabled`, `edge_scroll_speed`. `target_fps` for the auto ladder = `fps_cap` when > 0, else the display refresh rate. Any key present overrides the preset value; unknown keys are ignored with one warning.

### 7.8 `project.godot` entries this domain needs (requested from app/tooling, §13)

```ini
[shader_globals]
fx_time={ "type": "float", "value": 0.0 }
fx_lod={ "type": "float", "value": 1.0 }
view_time={ "type": "float", "value": 0.0 }

[rendering]
limits/global_shader_variables/buffer_size=262144
lights_and_shadows/directional_shadow/size=4096
anti_aliasing/quality/msaa_3d=0            ; set at runtime from ViewQuality
environment/defaults/default_clear_color=Color(0.043, 0.055, 0.078, 1)
```

### 7.9 Validation (`tools/py/validate_recipes.py`, CI + `gd check`-adjacent; the Godot test `test_view_recipes` is authoritative)

| Id | Check |
|---|---|
| V-RCP-01 | every JSON file parses; `schema` matches; keys sorted where required; ids equal file names |
| V-RCP-02 | `index.json` equals the sorted list of `<recipe id>.json` files; every bible unit (156) and structure (29), every neutral and summon def (ids read from `balance/*.json`, `neutral_structures.json`, `summons.json`) has a recipe, an exact `assignments.json` rule or a matching pattern; otherwise a stub is generated and the warning names the def |
| V-RCP-03 | `archetype`, `style`, `extends`, `slot` names, macro names and op names exist |
| V-RCP-04 | recipe `params` ⊆ archetype `defaults` ∪ archetype-declared extra keys; types match |
| V-RCP-05 | every expression compiles (Python re-implementation of the grammar), every identifier resolves in scope, division by literal 0 rejected |
| V-RCP-06 | palette keys and hex colours valid; `team` mask used on ≥ 1 op |
| V-RCP-07 | loops bounded (`n ≤ 64`, nest ≤ 3), op-list depth ≤ 8 |
| V-RCP-08 | armed units have sockets `muzzle{m}_{b}` for every mount `m` and barrel `b` in `combat_loadouts.json`; units with `deployable_mode` have DEPLOY/SLIDE parts or `meta.deploy = "pose"` |
| V-RCP-09 (Godot) | every recipe builds for every style it can be instantiated with: triangle / vertex / size / build-time budgets (§5.8.2), radius within ±15 % of the size class, no NaN, deterministic content hash on two builds, part mask matches archetype |
| V-RCP-10 | structure recipes: socket `door_exit` within 0.75 m of `(door_cx, door_cz)` derived from `footprints.json`; the airfield has pad markings at `pad_x(i), pad_z(i)`; the refinery has a `dock` socket at `(dock_cx, dock_cz)` |
| V-RCP-11 | `styles.json` `emblem` values belong to the abstract set `none, bar, bar_notch, triple_bar, chevron, double_chevron, ring, hex_notch, wedge, diamond` (QA V-IP1: no real-world marks) |
| V-FX-01 | `fx.json` compiles; every `fx` reference resolves; no cycles; every id referenced by `mappings` exists (including the `fx` strings of `combat_warheads.json` and `pres_fx`); `superweapons` entries match the bible geometry (radii and lengths in cells x 3 m); layer count ≤ 40 |

---
## 8. Determinism notes (DR-x compliance; what enters the checksum)

**Nothing this domain owns enters `SimWorld.checksum()`, and no sim field is added for the view.** The view is downstream of the deterministic core: it reads, it never writes.

| Rule | Compliance |
|---|---|
| DR-1/DR-4 ints only, no float builtins in sim | not applicable to `view/`; L003 does not scan `src/view` (only core, sim, map, data). Floats, `sin/cos/sqrt/lerp` are used freely here (DR-15) |
| DR-2 no engine RNG in the sim | `randf()/randi()/RandomNumberGenerator` are used in `view/` **for presentation only** (FX jitter, decor variation). They never select anything that flows back. In `screenshot_mode` the FX RNG is seeded (`ViewBuildOptions.rng_seed`) for reproducible images |
| DR-3 no wall clock in the sim | the view uses `delta`, `Time`, `TIME`; the sim's tick clock is read only as `sim.tick`, `sim.paused` and `alpha` |
| DR-6/DR-7 iteration order | `_active` iterates in ascending entity id (so screenshots are reproducible); no `Dictionary` iteration order is relied upon for output |
| DR-8 no Node/threads in the sim | opposite side of the wall: the view uses Nodes and `WorkerThreadPool` (model builds, terrain bake); worker tasks touch only view data (recipes, arrays), never `SimWorld` |
| DR-9 no hidden global state in the sim | view statics (`ViewGlobals._done`, model cache) are presentation-only and reset by `teardown()` |
| DR-12 events are output-only | the view receives the frame's batch from `events.take()` (called by the app, sim_core 5.7), reads it in place and never appends, clears or retains it; `test_view_readonly` proves the checksum chain of a scenario is identical with and without a `ViewWorld` attached (600 frames) |
| DR-13 checksum coverage | no new persistent sim field is introduced by this spec; the view keeps **snapshots** (positions, facing, mount angles, `hp`, `max_hp`, flags, `holder`) that are derived and rebuilt from the sim on reconcile |
| DR-14/DR-15 floats only in AI/UI/view | interpolation, camera, shake, FX are float and never feed back; UI turns pixels into `SimCommand`s of ints using `ViewWorld.world_to_sim` (rounded once) |

Additional guarantees and hooks:

* **Read-only guard (lint proposal L011 to QA; L001-L010 are taken, qa_tooling.md 3):** files under `src/view/` must not call `SimWorld` mutators (`submit`, `apply_turn`, `step`, `spawn_*`, `kill`, `despawn`, `transfer_owner`, `set_pos`, `set_layer`, `set_inside`, `refresh_stats`, `eliminate`, `end_match`, `add_credits`, `try_spend`, `events.take/clear/emit`) or `MapData` mutators (`harvest`, `regrow`, `occupy`, `vacate`, `patch_*`) and must not assign to `SimEntity`, `SimPlayer` or component members; a grep-based rule with a one-entry allowlist (`ViewTerrainSource.drain_deposit_changes` calls the output-only `MapData.drain_deposit_dirty`, which is not checksummed) is cheap and catches accidents. `capture_prev` and the reader classes only read.
* **Look determinism:** meshes are pure functions of `(recipe, style, scale)` with seeds `fnv1a(recipe_id) xor fnv1a(style_id)`; two clients build bit-identical vertex data on the same platform, and equal within 1 mm across platforms (float math in the builder), which is enough because nothing in the sim depends on it. The cache key uses the recipe/style **content hash**, so hot-reloaded recipes never serve stale meshes.
* **Map look data:** heights and the `deco` byte are excluded from `map_hash` and covered by `MapData.visual_hash()` only (terrain_movement.md 3.3); the view logs that hash at build time, and a mismatch between peers is a warning that can change the picture but never the simulation.
* **Replay / desync tooling:** the view exposes no state to the desync dump; a mismatch is always a sim bug. Visual differences between clients (VFX jitter) are expected and harmless.
* **Data hash:** recipes, fx, moods, quality are presentation data; they are *excluded* from the lobby data hash (data_balance.md: `pres_*` are excluded). Optional diagnostic only: `ViewRecipeBook.content_hash()` is logged so support can tell whether two players run different recipe packs; a mismatch does **not** block a match.
* **Threading safety of builds:** `ViewRecipeInterpreter` and `ViewMeshBuilder` use only local state plus read-only shared dictionaries (`ViewRecipe`, styles); the test builds 100 models on 4 threads and compares content hashes with the single-thread build.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

The view has no per-tick cost (the sim is untouched); the budget is **per rendered frame**. Reference scenario: 8 players, 400 mixed entities (130 tanks, 60 APCs, 50 howitzers, 100 squads, 30 gunships, 20 boats, 10 structures in view; 300 more structures off-screen), map 256², 1080p, High preset, Forward+, M5 Max `[M][T][F]`.

### 9.1 CPU (main thread) per frame

Per moving, visible entity: `sim.entity` 0.3 µs + cached visibility 0.3 + interpolation 0.6 + `height_at` 0.4 + `normal_at` every 3rd frame 0.7 + transform build/set ≈ 2.0 (`set_instance_shader_parameter` 0.4-1.1 µs per call `[M]`) + 2 changed uniform writes 1.5 + animation channels 0.7 ≈ **6.5 µs**; idle visible entity 0.8 µs; hidden 0.3 µs.

| Item | Estimate (M5) | Mid-range x86 (≈ 2x) | Basis |
|---|--:|--:|---|
| `camera.advance`, visible rect | 0.05 ms | 0.1 | 4 raycasts = 45 µs |
| `router.process` (60 events/frame typical, 300 worst) | 0.2 / 1.0 | 0.4 / 2.0 | 3 µs decode each |
| FX spawns (397/s at 60 fps = 6.6/frame) | 0.45 | 0.9 | 66 µs per composite spawn `[F]` |
| Reconcile sweep (1 per 30 frames) | 0.005 | 0.01 | 400 ids |
| Tick sample (`_sample_tick`, on 1 of 3 frames, only entities in view or animated) | 0.2 | 0.4 | 1.5 µs x 400 / 3: ~8 field reads, one `ViewSimReader` read, flag decode |
| Fog sync + advance | 0.02 (+0.02 at 10 Hz) | 0.04 | version compare, 4-12 µs upload |
| **Entity loop** (60 % moving) | **1.65** | **3.3** | 400 x (0.6 x 6.5 + 0.4 x 0.8) |
| Projectiles (≤ 64 mirrored) | 0.3 | 0.6 | 5 µs each |
| Overlays (selection 100, bars 60, lines, warnings, zones, ghosts) | 0.4 | 0.8 | |
| `fx.advance` | 0.2 | 0.4 | 208 µs measured at 5x load `[F]` |
| Batch backend `flush` (Mobile/Compat only) | 0.1 | 0.2 | ~40 MultiMesh buffer assignments |
| **Total** | **≈ 3.5 ms** | **≈ 6.9 ms** | |

That leaves ≥ 9 ms of a 16.6 ms frame for engine + sim (1 tick per 3 frames) + net + UI on mid-range CPUs. The optional `capture_prev` hook (§3.0) adds up to 0.3 ms per executed step at 1 200 entities and only exists when net calls it. The GPU thread is separate: render-thread CPU for 400 units measured 0.14-0.28 ms (Low) `[M]`, 0.78 ms in the chaos battle `[F]`.

### 9.2 GPU and draw calls

* **Reference GPU cost (M5 Max, 1080p, whole scene)**: Low 1.46, Medium 3.31, High 4.4-4.7, Ultra 8.9-9.1 ms (1440p: 2.23 / 5.42 / 7.87 / 14.7) `[T]`; units are effectively free at 0-400 (instanced); the 400-unit sheet at 4K is fill/post-bound (full 19-29 ms, MSAA 4x and SSAO+glow are the two big costs) `[M]`.
* **Draw calls (Forward+, High)**: units ≈ 42 with 4 cascades / 14 without (identical mesh+material auto-instance), terrain ≈ 24 visible chunks x (1 + shadow cascades that see them), decor 56-94 MultiMeshes, FX ≈ 100 (34 batches, one draw per *active* batch), overlays ≈ 12. **Budget: ≤ 120 typical, ≤ 250 worst (all passes).** Mobile and Compatibility do not auto-instance: **batch backend** keeps units at ~40-80 draws instead of 801 `[M]`; budget ≤ 450 total.
* **Primitives**: main pass ≤ 1.2 M for 400 entities at LOD1 (measured 707 k for the sheet scene) + terrain 524 k (256², subdiv 2) at High; shadow passes ≤ 1.5 M.
* **Integrated GPUs (not measured, risk R1):** scaling the M5 Low figure (1.46 ms) by a plausible 10-25x gap to UHD 770 / Vega 8 / Iris Xe gives 15-35 ms at native 1080p, i.e. **Low needs `render_scale 0.75` (0.56x pixels) and may still fall short on the weakest parts**; `ViewQualityAuto` therefore continues below the Low preset by lowering `render_scale` in 0.1 steps to 0.55 (FSR1), then disables cloud shadows / glow / decor. The 60 FPS-at-Low goal must be verified on one Intel and one AMD iGPU before release (task VIEW-Q3).

### 9.3 Memory and load time

| Item | Size |
|---|---|
| Model meshes resident (≈ 100 models, 4 players; ≤ 280 worst) | 45 MB (≤ 120 MB); 52 B/vertex; tank 740 KB |
| Terrain 256²: `hv` 1.05 MB, chunk vertex data ≈ 10.5 MB + 3.1 MB indices, ctrl 0.5 MB, road textures 0.3 MB, depth 0.26 MB, shore 64 KB, scorch 4 MB (1024²), fog 2 x 64 KB, detail atlases 0.7 MB | ≈ 21 MB |
| FX: noise atlas 0.35 MB (256² RGBA8 + mips), ramp/palette tiny, ring buffers ≈ 5.7 k x 80 B = 0.45 MB | ≈ 1 MB |
| Decor: 3.5-9 k instances x 80 B (urban maps add 1-3 k merged buildings) + meshes | < 1 MB |
| Icons (35 x 128x96 RGBA8) + portraits on demand | ≈ 2 MB |
| **View-owned VRAM/RAM total** | **≈ 75-160 MB** (+ render targets ≈ 60-120 MB at 1080p HDR) |

Load stages (cold shader cache | warm): globals/materials 5 ms · terrain bake 350 ms (256², threaded) · terrain textures 60 ms · detail atlases 60 ms · water/atmosphere 10 ms · decor 120-235 ms · minimap bake 70 ms · models 0.25-0.6 s threaded (≈ 100 models) · FX prewarm 0.15 s · material prewarm 0.5-1 s cold, 50 ms warm · icons 0.7 s (first icon 2.7 s cold Metal) · **total ≈ 3-4 s cold, 1.5-2 s warm**, sliced to ≤ 8 ms per frame so the loading screen and net stay responsive.

### 9.4 Worst cases and mitigations

| Case | Effect | Mitigation |
|---|---|---|
| 1200 entities (8 players x 150 cap) | entity loop ≈ 5 ms (10 ms mid-range) | off-screen entities at 5 Hz (about half are off-screen on big maps); far entities (> 120 m from the focus) at 20 Hz; change-detection on all pushes; `ViewQualityAuto`; instance-uniform buffer raised to 16 384 instances |
| FX storm (5x chaos) | 49 % of requests rate-limited, ring overwrites | token buckets, hard ring caps (enlarged rings §4.7), LOW `fx_lod 0.45` thins cluster sprites |
| Catch-up frame (8 ticks at once, > 600 events) | event burst | lifecycle / state / death events always processed; cosmetic `WEAPON_FIRED` beyond 300 per frame are dropped (their recoil kick still applied); interpolation spans 8 ticks for that frame (§3.0) |
| Urban family maps (up to ~9 k URBAN_BLOCK cells at 192², ~16 k at 256²) | 1-3 k merged building instances on top of the decor | merged rectangles of at most 3x3 cells, part of the `decor_groups²` MultiMeshes, shadows only on HIGH / ULTRA (`decor_casts_shadow`) |
| Select-all (200+ units) | 200 rings + 200 bars | one MultiMesh each; overlay cost ≤ 0.2 ms |
| Cold first spawn / shader compile | 14-32 ms hitches on Metal | prewarm, `RENDERING_INFO_PIPELINE_COMPILATIONS_*` flat before the loading screen ends |
| Compatibility with 400 units | 801 draws / 9 ms render CPU per naive path | batch backend, MultiMesh per (model, team material) |
| 4K + Ultra | 19-30 ms (fill / post bound) | MSAA 4x default at High, FSR / MetalFX spatial at `render_scale 0.67-0.77`, `unit_shader_quality 0` (−14 %) |
| Long matches: leak growth | `ViewEntity`, nodes, FX handles | ids never reused so dictionaries are cleaned on dispose; soak test (§10) asserts node count and `Performance.get_monitor(OBJECT_NODE_COUNT)` flat after 60 min of AI-vs-AI |

---

## 10. Test plan (unit / scenario / determinism / visual)

Runner: `tools/gd test view` (headless unless a real renderer is needed), files `game/tests/view/test_*.gd` (`extends RefCounted`, one `func test_*(t: TestCtx) -> void` per case, a fresh instance per test; qa_tooling.md 5). `TestCtx.eq` is type-strict (int 1 != float 1.0), so float expectations below use `t.near(actual, expected, eps)`; tests that provoke a `push_error` (invalid recipe, bad expression) declare it with `t.expect_errors(n)`; long tests call `t.set_timeout(s)`. Visual tests need a window (macOS) or xvfb (`gd linux`, lavapipe software Vulkan, 12-16 s per shot); headless has no renderer (`DevShot` exits with `SHOT_FAIL`).

### 10.1 Unit tests (headless)

| File | Concrete cases and expected values |
|---|---|
| `test_view_consts` | sim `(51200, 30720)` -> world `(150.0, 90.0)`; `yaw_of_bat(0) = −π/2`, `(1024) = −π`, `(2048) = −3π/2`; `turret_yaw(512) = −0.7854`, `turret_yaw(3900) = +0.3007`; `rel_yaw(1536, 1024) = −0.7854`, `rel_yaw(3900, 200) = +0.6075`; `wrap_bat(3700) = −396`; `lerp_bat(4090, 10, 0.5) = 4098`; `struct_rot(0, 700, 1024, 3072) = 0, 1, 1, 3`; interpolation example of §5.1: `x_prev 51200, x_cur 51302, alpha 0.5` -> `wx = 150.15 ± 0.01`; `world_to_sim(sim_to_world(x, y)) == (x, y)` for 1000 random ints (round-trip exact within 1 unit) |
| `test_view_expr` | `1+2*3` = 7; `min(3,4)` = 3; `lerp(0,10,0.25)` = 2.5; `a>2 ? 5 : 6` with a=3 -> 5; `len*0.5` with len=3.5 -> 1.75; `5/0` -> 0 (+ warning flag); `skirt=='modules'` with 'modules' -> true; unknown identifier -> compile error containing the name and column; nesting depth 9 -> error; constant folding: `2*3+x` compiles to 2 ops; 10 000 evaluations of a 20-token program ≤ 30 ms |
| `test_view_mesh_builder` | `box(0, 1³, bevel 0)`: 24 vertices / 12 triangles; `box(0, 1³, 0.05)`: 120 vertices, tris (LOD0, LOD1, LOD2) = (44, 12, 12); **winding:** for every triangle of box / prism / lathe / extrude / track_belt / pocket_box the right-hand normal points *into* the solid (clockwise front faces): `cross(b−a, c−a)·(tri_centroid − model_centroid) < 0` for 100 % of triangles of convex primitives; `mirror_x` doubles vertices, negates x and pivot.x, keeps winding valid; `model_scale 1.25` scales AABB by 1.25; pivot half-encoding error < 4 mm for abs(x) < 8 m and < 8 mm for 8..16 m (`encode_half` truncates; measured worst 7.5 mm on ±10 m); `custom_aabb` ⊇ rest AABB grown by the animated sweep radius; gait parts carry `UV2 = (index, count)`; `wheel` sets part 3 with `extra = radius`; identical seeds -> identical arrays |
| `test_view_recipe_interp` | tiny archetype with `for`, `if`, `switch`, `mirror_x`, `push`, `part`, `call`, `slot`: expected vertex/triangle counts and part masks; slot precedence recipe > style > archetype; error path text `id/ops[3]/for[1]/box` on a bad argument; `for n = 65` rejected; executed-primitive cap 4000 rejected; determinism: same inputs -> same `content_hash`; thread build equals main-thread build |
| `test_view_recipes` (V-RCP-09) | every recipe x every valid style builds; budgets of §5.8.2 hold (tris, verts < 65 535, size class radius ±15 %, height caps, build ≤ 60 ms hard / 20 ms soft); team-masked area 4-12 %; sockets `muzzle{m}_{b}` exist for each mount in `combat_loadouts.json`; `top` socket exists; no NaN; unit tank part mask ⊇ {TURRET, BARREL, TRACK, WHEEL} |
| `test_view_camera` | `zoom 0.5`: H = 54.625, pitch 52.19°, distance 69.1; `snap_to` then `screen_to_ground(viewport centre)` = focus ± 0.05 m; focus request `(−100, −100)` on `map_rect (0,0,576,576)` clamps to `(14, 14)`; `edge_scroll_dir((5,540),(1920,1080),10) = (−1, 0)`, `((1915,1075)) = (1, 1)`, `((−1,5)) = (0, 0)`; smoothing frame-rate independence: 60 x 1/60 s equals 30 x 1/30 s within 1 mm; shake: `add_shake(1)` -> at 0.25 s trauma 0.6, at 0.625 s 0.0 (decay 1.6/s); focus unaffected by shake; cinematic keys `t=0 (0,0,0)` and `t=4 (40,0,0)`: at t=2 focus.x = 20 ± 0.01; `cinematic_changed` emitted once each way; `visible_ground_rect` at H = 34 ≈ 58 x 51 m footprint area ±10 % |
| `test_view_terrain` | fixture 96², 104² (partial chunks: 4x4 with last chunk 8 cells), 256²: chunk counts 9 / 16 / 64, triangle count `w*h*subdiv²*2` (256²: 524 288); `height_at` at grid vertices equals `hv`; between vertices monotone between neighbours; normals unit length; **seam test:** chunk-edge vertices of neighbours have equal position and normal (≤ 1e-5); `raycast` from `(100, 500, 100)` straight down hits `(100, h, 100)` within 0.02 m; `raycast` at 30° above horizontal toward a ramp hits within 0.05 m of the analytic intersection; miss returns `Vector3.INF`; road raster: `road_cov` is 255 in the interior of a 3-wide trunk and <= 128 one cell outside it |
| `test_view_fog` | `submit([0,1,2,…])` bytes equal the texture image bytes; `advance(0.05)` -> `fow_blend 0.5`, `advance(0.06)` -> 1.0; `sync(api, pid)` with a fake `SimFogApi` and unchanged `fog_version` performs 0 uploads (counter); `set_enabled(false)` -> all bytes 2; `set_mode(1)` -> `fow_fog_dim 0`, `set_mode(2)` -> 1, `set_mode(0)` -> all bytes 2 |
| `test_fx_manager` | `TINY` bucket: 100 immediate spawns at a visible point = 60 accepted; after `advance(0.1)` 50 more; distance rule: camera focus distance 96 m -> TINY 166 m limit (rejects 200 m, accepts 150 m), MEDIUM 296 m; behind-camera effect rejected unless `d < r`; `force=true` bypasses; ring overwrite counter after `capacity+5` emits = 5; `cancel(handle)` empties the SUPER batch; `schedule(0.5)` fires at `now ≥ 0.5`; `start_tracker` calls its Callables once per interval; quality LOW: `fx_lod 0.45`, lights 0; `pause` freezes `fx_time`; every effect in `fx.json` spawns with `force` and adds ≥ 1 live instance or light or scorch; interpreted `expl_medium` produces the same batch set as the spike's `explosion_medium` |
| `test_view_picker` | fixture camera H 34 at `(150, 90)`; tank at the focus: `pick(centre) = tank`; 3x3 factory 2 cells north (height 6.5): click on its roof -> factory; click on the ground behind it (hidden by the building) -> factory (nearest ray hit); gunship at 7 m altitude directly above a ground unit: click on the gunship's screen position -> gunship, click 30 px below -> ground unit; wreck vs unit tie -> unit; hidden (fog) enemy never returned; `pick_box` returns exactly the own units whose centre projects inside the rect, ascending ids; filter masks respected; 400 entities `pick_box` ≤ 2 ms |
| `test_view_quality` | preset tables equal `quality.json`; Compat clamp: `ssao off`, `fxaa off`, `unit_backend batch`, `fx_distort off`; Mobile clamp: `ssao off`; `recommend()`: discrete -> HIGH, integrated -> MEDIUM, CPU -> LOW; auto: 6 s of 40 ms frames at HIGH -> MEDIUM (2 bad windows), then continued -> LOW, then `render_scale` steps 0.75 -> 0.65 -> 0.55; 30 s of 8 ms frames -> at most one step up, never within 120 s of a down-step; hitch frames (> 250 ms) ignored |
| `test_view_materials` | one material per (style, variant); `MM` variant source starts with `#define MM 1`; `set_quality` writes the uniform to all cached materials; unit shader has no `TIME` token; `fow_*` declared once per shader |
| `test_view_events` | synthetic batches built by `ViewTestEvents.make(type, tick, a..h)` (stride 10): `SPAWNED` creates a `ViewEntity` from the payload alone, a duplicate is ignored; `DIED` + `REMOVED(KILLED)` in one frame keep the record for the dying window (vehicle 2 ticks, structure 7, crash 30) then dispose, and the wreck `SPAWNED` (reason 5) of the same tick appears with `UF_WRECK`; `WEAPON_FIRED` sets `recoil = 1` even when the FX is culled; `DAMAGE` sets `flash = 1`, a kill-blow flag does not; hit inference: a `DAMAGE` with the same attacker and target in the tick -> hit spark, none -> miss tracer; `SPAWNED` reason PLACED -> `BUILDUP` with `t0 = event tick`, INITIAL -> ACTIVE without animation; `PRODUCTION_COMPLETE` -> producer `door_dir = +1`; `STATE ST_SELLING` -> SELLING over `d` ticks; `REMOVED(SOLD)` disposes at once; `_validate_codes` reports a constant removed from a fake `SimEvent` map exactly once |
| `test_view_sim_reader` | with a fixture entity that has no `combat` / `eco` / `zone` component every reader returns its documented default (`turret_rel_bat = -1`, `collector_fill_permille = -1`, `zone_charges = -1`, `rally_of = false`); with a fixture component the values are returned unchanged; no reader allocates (200 000 calls stay flat in `Performance.OBJECT_COUNT`) |
| `test_view_def_adapter` | the same unit and structure fixture through both index-space variants (per-kind `data_balance.md` and single dense space `sim_core.md`) yields identical `ViewDef` records (id, recipe id defaulting to the def id, `scale_bp`, move class, size class, radius, footprint from `fp_w / fp_h`, `needs_power`, `is_hq`); `weapon_arch(999)` returns -1 with one `Log.warn`; roster id -> style id mapping for all 32 rosters |
| `test_view_terrain_source` | fixture `MapData` (`MapData.create` + `finalize`): corner heights equal `MapImages.corner_height * 0.05`; `sea_level_m = (max water height level + 0.5) * 0.05` and `-1000.0` without water; splat table: GRASS in the arctic biome -> snow 1.0, RAMP cell rock weight x 0.15; urban avenue of 6 rows: `road_info` k = 0..5, n = 6, `G` = horizontal; a 12-cell street segment between two junctions is fully classified; 3-wide trunks of slope 1 (diagonal), 1/4 and 1/9 have no street cells; `drain_deposit_changes` returns a harvested cell once and then an empty list |
| `test_view_a11y` | `set_mode(deutan)` publishes the eight Okabe-Ito colours for ids 0-7 and leaves 8-11; the shape pip differs for ids 0-7; `reduce_flash` caps light energy at 0.4 x, sprite size at 0.6 x and alpha at 0.5 x; `reduce_motion` scales shake by 0.2; `normal` restores the lobby swatches exactly |
| `test_view_ids` | recipe / fx id references from `combat_warheads.json` (`fx` strings), `combat_weapons.json` and `pres_fx` in balance resolve (or fall back with a single `Log.warn`); every `fx.json` mapping key names a real archetype, superweapon or power |

### 10.2 Scenario tests (real `SimWorld`; QA `TestCtx` helpers)

* **Mirror:** build a world with 100 mixed entities, `bind_world`, run 200 ticks of movement orders; each frame `frame(1/60, alpha, events.take())`; assert every live entity has a `ViewEntity`, positions equal `lerp(prev sample, cur sample, alpha)` ± 1e-4, removed entities disappear, `_reconcile()` repairs a deliberately dropped `SPAWNED`. **Catch-up:** run 3 steps between two frames; over the next 10 frames no entity moves backwards (projected on its velocity), and with `capture_prev` installed the interpolation span is one tick.
* **Visibility:** two-player world, enemy tank enters/leaves vision: `VS_VISIBLE` iff `sim.entity_visible(pid, e)`; enemy structure leaves vision -> `ViewGhosts` shows exactly one ghost at the last pose (from `fog.ghosts`); stealth unit hidden until detected; `fog_mode 1` leaves explored terrain undimmed.
* **Squads:** rifle squad (4 members) takes damage to 74 % -> member 3 hidden, 49 % -> 2-3, 24 % -> 1-3; member 0 always visible.
* **Structure lifecycle:** place -> `BUILDUP` progress equals `(tick+alpha−t0)/phase_ticks` ± 0.01 with `t0` = the `SPAWNED` tick and `phase_ticks` 30, scaffold visible, complete -> flash; sell -> `STATE ST_SELLING` reverse over its duration, `REMOVED(SOLD)` disposes.
* **Deaths:** a tank killed in combat produces `DIED`, `REMOVED`, wreck `SPAWNED` in one batch: the dying record lasts 2 ticks, the wreck record has `UF_WRECK` and sinks 0.6 m during its last 1.5 s (`expires`); an aircraft kill runs the 30-tick crash and ends with `aircraft_crash`; a ship sinks over 60 ticks; a structure shakes 7 ticks; a chain explosion in the same batch removes the death fireball (dedupe).
* **Urban map:** generated urban fixture: buildings exist only on URBAN_BLOCK cells with heights `6 + (deco & 7) * 0.7`, street markings only on street cells, none on trunks or junctions.
* **Warnings:** launch Atlas -> `SW_WARNING` -> `ViewWarnings` shows 3 discs (r 6 m, 9 m apart) for the owner's team and for any team with an entity inside the zone + 3 cells, none for a third team elsewhere, all regardless of fog; destroying the launcher during the warning (`SW_CANCELLED`) cancels within 1 frame; the Trident zone is visible to all for 500 ticks.
* **Long soak (nightly):** 60-minute AI-vs-AI 8-player match with the view attached in a headless-safe mode: node count, `ViewEntity` count and RAM flat ±5 % after minute 10; zero `push_error`.

### 10.3 Determinism tests

* `test_view_readonly`: the same 2-player scenario run twice (with and without a `ViewWorld`, 600 frames of `frame()`), checksum chains equal at every 20th tick; a grep test over `src/view/**` for forbidden mutators (L011 proposal, §8).
* Recipe hash: two builds and a 4-thread build give identical `content_hash`; `gd linux test view_recipes` gives equal **1 mm-quantised** hashes (cross-platform).
* No `TIME` in gameplay-relevant animation shaders: a test greps `assets/shaders/{unit,fx_*,ring,line,health_bar}.gdshader` for `\bTIME\b` (terrain / water / decor use `view_time`).

### 10.4 Visual test procedure (`tools/gd shot`, inspected with the image reader)

For every visual task: build a dedicated scene under `game/tests/view/scenes/` with a script that accepts options after `--` (`--seed`, `--mood`, `--faction`, `--pose=rest|action`, `--quality`, `--cam_h`), then

```
tools/gd shot res://tests/view/scenes/shot_rts_battle.tscn /tmp/battle_h45.png --frames 40 --size 1920x1080 -- --cam_h=45 --seed=7
tools/gd shot ... --rendering-method mobile        # and gl_compatibility
tools/gd linux shot ...                            # Debian container, lavapipe: shader-compile + smoke check
```

Every scene below is also registered in `game/tests/visual/cases.json` with `owner: view` (qa.md 5.9): the scene and its deterministic fixture are mine, QA supplies capture, the automatic checks VA-1..VA-5, review records and goldens; QA-XR-28 injectables are `ViewWorld.create(q)` + `await build_async(world, pid, opts)` (no autoload), `ViewCamera.set_pose`, and `screenshot_mode`. Open every PNG with the image reader (Read on the .png), compare with the checklist, change code / recipes, repeat. **At least three inspected rounds per system** (the spikes needed 3-6 to reach the current look); record the round count and the decisive changes in the task report. `screenshot_mode` freezes `view_time`/`fx_time` and seeds RNGs so images are comparable; `DevShot` waits N frames then captures the root viewport (`SHOT_OK path WxH`).

| Id | Scene | Acceptance checklist |
|---|---|---|
| V-1 | `shot_model_sheet` per faction x {rest, action}: every archetype instance on a labelled grid, side-by-side tank row for all 8 factions | silhouettes distinguishable between factions at 60 m; palette matches `visual_direction`; team colour on ≥ 3 surfaces and separated from paint by the plate; no inverted faces (black holes), no z-fighting, no floating parts; turret / barrel / rotors visibly animated in `action`; tri counts printed within budget |
| V-2 | `shot_rts_battle`: 400 entities, 8 teams, H 45 and 60, crops A/B/C as in `[M]` (`3x` and `6x`) | tank ≥ 90 px (H 45) / 70 px (H 60) long at 1080p; squads legible at 6x crop; team colours distinct; shadows stable; no shimmering panel lines (aliasing speckle on cream roofs was the v4 fix) |
| V-3 | `shot_terrain` x5 moods x {lake, mesa} | no cliff ringing, no 10 m camouflage blotches, roads crisp, shore foam band, no texture repetition visible at H 60, mood palettes recognisable |
| V-4 | `shot_water` | depth tint, glitter, foam, no screen-texture seams; refraction rings disabled over water |
| V-5 | `shot_fog`: shroud / fog / visible with own and enemy units | smooth organic edges; hidden enemy absent; ghost structure present and desaturated; minimap matches |
| V-6 | `shot_buildup`: factory at build = 0, 0.25, 0.5, 0.75, 1.0 (+ sell reverse) | rises from below ground, scaffold matches height, sparks at the top edge, flash at completion |
| V-7 | `shot_overlays`: selection rings / brackets, health bars (3 zoom levels), rally + order lines, placement ghost valid and invalid with per-cell colours, build radius, range rings | constant-size bars and lines; ghost cells coloured per `CF_*`; rings not buried on slopes |
| V-8 | `shot_warnings`: 8 superweapon warning zones + Trident | shapes match bible geometry (rods 9 m apart r 6 m; capsule 48 x 9 m; r 24 / 21 / 18 / 15 m discs); visible under full shroud |
| V-9 | `shot_fx` sheets 0-3 (23 spike effects + new) and `shot_sw` (8 superweapons at 3 times each) | spike look preserved (beams, rail, fireballs, sparks, trails, domes, columns strong); no milky plate around explosions; additive discs not clipped by terrain; wreck smoke readable on dark hulls |
| V-10 | V-2 and V-9 sheet 1 on `mobile` and `gl_compatibility` | same layout, missing features degrade as designed (no SSAO / distortion), no black units, no red trunks / glowing crowns (MultiMesh colour pitfall) |
| V-11 | `shot_prewarm` log check | pipeline compilation counters flat for 30 frames after prewarm; first spawn of each recipe < 16 ms in the log |
| V-12 | `shot_icons`: local roster icons on the UI background | corner alpha 0.0; models framed with margin 0.78; faction-branded team colour |
| V-13 | quality ladder LOW..ULTRA same scene | each step visibly improves (shadows, AO, AA) and the frame-time table (§9) is recorded |
| V-14 | night mood | emissive windows / lights pop, no dynamic lights needed, readability preserved |
| V-15 | camera path (cinematic) frames | smooth, no clipping through terrain |
| V-16 | `shot_colourblind`: eight teams of one faction under `normal`, `protan`, `deutan`, `tritan`, `high_contrast` | all eight colours separable by hue or luminance in the simulated modes, shape pips visible on bars and rings, `reduce_flash` explosion visibly calmer |
| V-17 | `shot_urban` (urban family, day and `urban_night`) | building blocks on URBAN_BLOCK cells only, painted dashes and crosswalks on streets, worn asphalt on trunks, lit windows at night, units readable against dark asphalt |

Automated pixel assertions accompany the images: frame not black (> 5 % pixels above luma 0.05), corner alpha of icons = 0, mean team-colour pixel count > threshold, difference vs the previous golden within a tolerance (informational, never blocking).

### 10.5 Performance tests

`game/tests/view/bench_view.gd` (run with a real renderer, output JSON): warm-up 3 s, then 240 frames; reports script ms per subsystem (`ViewWorld.stats()`), `RENDERING_INFO_*` draws / prims / objects, `viewport_get_measured_render_time_cpu`, and `force_draw` throughput p50 (min of 3 passes). Gates: script total ≤ 3.7 ms (M5 reference, 400 entities) / ≤ 1.5x the recorded baseline elsewhere; draws ≤ 250; prims ≤ 1.2 M main pass; FX spawn ≤ 100 µs interpreted; model build ≤ 20 ms; model batch (100 models, 4 threads) ≤ 0.6 s; terrain bake 256² ≤ 450 ms; `pick` ≤ 120 µs; `pick_box` (400) ≤ 2 ms. A shader zoo scene instantiates every material variant on every renderer and fails on any engine `ERROR:` line (`gd shot` counts them).

---
## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Sizes are GDScript lines unless marked JSON / py. "sim fixture" = until the real `SimWorld` is usable (sim_core publishes `SimTestKit.make_world` and friends, sim_core 3.9) a task uses `game/tests/view/view_fixture_world.gd` (a minimal read-compatible stand-in owned by VIEW-S1); integration tests switch to the real world once sim_core lands, the fixture stays for unit tests of components that other domains have not delivered. Every task ends with `tools/gd check` clean and its tests green (ARCH §13).

| Id | Task | Files owned (under `game/src/view/` unless noted) | Deps | Size | Acceptance |
|---|---|---|---|--:|---|
| **VIEW-01** | Core, globals, quality tables | `view_consts, view_layers, view_globals, view_team_colors, view_instance_buffer, view_quality, view_quality_auto`; `assets/shaders/{view_common,fog_of_war,atmosphere}.gdshaderinc`; `data/recipes/quality.json` | none | 1300 | `test_view_consts`, `test_view_quality`, `test_view_a11y` (palette modes, `reduce_*` scaling), globals register twice without error, headless import clean |
| **VIEW-T1** | Recipe tooling (py) | `tools/py/{validate_recipes,gen_recipe_index,gen_recipe_stubs}.py`; `data/recipes/{assignments,index}.json`; JSON schemas in the scripts | none (bible + balance `unit_assignments`) | 900 py | stubs generated for all 156 unit and 29 structure defs and, through the `assignments.json` patterns, for every neutral and summon id found in the balance files; `index.json` sorted; validators pass on the example recipes of §7; py unit tests |
| **VIEW-S1** | Sim seams: reader, def adapter, placement state, event fixtures | `view_sim_reader, view_def, view_def_adapter, overlay/view_placement_state`; `game/tests/view/{view_fixture_world.gd, view_test_events.gd}` | 01 | 1300 | `test_view_sim_reader`, `test_view_def_adapter` (both index-space variants), `ViewTestEvents.make` covers every event type of §6.2.2; no other view file reads `Def*` fields or component internals (grep test) |
| **VIEW-M1** | Mesh builder + expression engine | `model/view_mesh_builder, view_expr, view_model_info` | 01 | 1800 | `test_view_mesh_builder` (120 vertices, tris (44, 12, 12) for the bevelled unit box; all triangles wind clockwise-front; half error bounds), `test_view_expr`; spike sample models reproduced through the API |
| **VIEW-M2** | Recipe system + model builder | `model/view_recipe, view_recipe_book, view_recipe_interpreter, view_recipe_macros (common+vehicle+infantry+air), view_model, view_model_builder` | M1 | 2400 | `test_view_recipe_interp` (all ops, slots, errors with op path), threaded build == single-thread `content_hash`, placeholder for a missing recipe with one `Log.warn`, `veh_tank` archetype reproduces the 4 spike tank styles (V-1 screenshot round 1) |
| **VIEW-M3** | Unit shader, materials, rig, backends | `assets/shaders/unit.gdshader` (default, `MM`, `MATU`, `GHOST`); `model/view_materials, view_model_rig`; `backend/{view_unit_backend, view_node_backend, view_batch_backend}` | 01, M1 | 1900 | `test_view_materials`; V-1 (units, big, factions, rts scenes of the spike) identical look on Forward+; V-10 on Mobile and Compat (no black units, no camo wear); 400 units = ≤ 45 draws Forward+; batch backend ≤ 120 draws on Compat; 5000 node instances render with `buffer_size 262144` (confirms the inferred limit) |
| **VIEW-M4** | Structure / ship / superweapon macros | `model/view_macros_structures` | M2 | 1500 | macro unit tests (each macro emits within its bounding box, balanced brush / part state); contact sheet of every macro |
| **VIEW-M5** | Archetypes A: ground vehicles (13) | `data/recipes/archetypes/veh_*.json` | M2, M3 | 1800 JSON | V-1 per archetype (rest + action), tri budgets, sockets for every mount, deploy poses for artillery |
| **VIEW-M6** | Archetypes B: infantry, air, ships (15) | `archetypes/{inf_*,air_*,ship_*}.json` | M2, M3 | 1500 JSON | same; squads hide members by hp (scenario test); aircraft rotors / nozzles animated |
| **VIEW-M7** | Archetypes C: structures, neutrals, summons, projectiles (28) | `archetypes/{str_*,neu_*,sum_*,proj_*}.json` | M4 | 2000 JSON | V-1 structure sheet at 3 footprints each; V-6 build-up with scaffold; footprint discipline test |
| **VIEW-M8a-d** | Styles + faction recipes, 2 factions per task: (a) NAPC + NEC, (b) OLM + DEF, (c) PD + HAN, (d) AE + SAP | `data/recipes/styles.json` (own sections), `<recipe id>.json` for that faction's 19 units x + shared-structure kits + advanced defense + superweapon + subfaction styles | M5-M7 | 2500 JSON each | V-1 for both factions (side-by-side against the other factions), V-RCP-01..09 green for their ids, ≥ 3 inspected rounds documented, palette vs `visual_direction` check, team-plate contrast test |
| **VIEW-M9** | Icons and portraits | `model/view_icon_bake` | M3 | 600 | V-12; cache hit path < 2 ms per icon; corner alpha 0 |
| **VIEW-M10** | Model performance | disk cache option, `ARRAY_FLAG_COMPRESS_ATTRIBUTES` trial, thread tuning (edits inside M2 files after M2 lands) | M2 | 500 | 100-model batch ≤ 0.6 s on 4 threads; report of VRAM per model before / after compression; decision recorded |
| **VIEW-02** | Terrain | `terrain/{view_terrain_source, view_terrain_bake, view_terrain_layers, view_terrain, view_detail_textures}`; `assets/shaders/terrain.gdshader` | 01; map (`MapData`, `MapImages`: published) or a `MapData.create` fixture | 2300 | `test_view_terrain` (chunks, seams, raycast), `test_view_terrain_source` (corner heights, sea level, splat table, road run-length, deposit drain); V-3 temperate + arid + arctic + tropical, V-17 urban; 256² bake ≤ 450 ms threaded; `TERRAIN_LOW` compiles on all renderers |
| **VIEW-03** | Water, atmosphere, moods, fog, minimap source | `terrain/{view_water, view_atmosphere, view_mood_def, view_fog_of_war, view_minimap_source}`; `assets/shaders/{water,minimap_fog}.gdshader`; `data/recipes/moods.json` | 01, 02 | 1900 | `test_view_fog`; V-3 (5 moods), V-4, V-5, V-14, V-17 night; `fit_shadows` = 89 / 114 / 141 m at H 34 / 54 / 84 |
| **VIEW-04** | Decor, scorch / tread layer, blob shadows | `terrain/{view_decor, view_decor_meshes, view_scorch_layer, view_blob_shadows}`; `assets/shaders/{decor,blob_shadow}.gdshader` | 02 | 1900 | decor only on FOREST, ROCK, CLIFF, MOUNTAIN, `SF_BLOCK`, shore-shallow and deposit cells plus URBAN_BLOCK buildings (test against `MapData` fixtures), groups 4-6 give 56-94 MultiMeshes, deposit clusters shrink with `drain_deposit_changes`, scorch paint ≤ 5 µs, flush ≤ 1.2 ms |
| **VIEW-05** | Camera | `camera/view_camera` | 01, 02 | 800 | `test_view_camera`; V-15; input actions registered without overriding bindings |
| **VIEW-W1** | World, entity mirror, lifecycle events | `view_world, view_build_options, view_entity, view_unit, view_structure (basic), view_event_router (lifecycle + hit / fire)` | 01, S1, 02, M2, M3 (03 soft: fog / atmosphere are wired when it lands) | 2400 | `test_view_events`, mirror scenario incl. the catch-up case, visibility scenario, squads scenario, deaths scenario, reconcile repair; script ≤ 2 ms for 400 entities (bench) |
| **VIEW-W2** | Structure states, wrecks, ghosts, zones, statuses | `view_structure (full), overlay/{view_ghosts, view_zones, view_status_marks}`; `assets/shaders/scaffold.gdshader` | W1, M7 | 1800 | structure lifecycle scenario, V-6, ghost scenario, wreck timing (60 s) test |
| **VIEW-W3** | Projectile mirror | `view_projectiles` | W1, F1 | 700 | missile follows the pool slot exactly; arcs match start / end / flight; cap respected |
| **VIEW-W4** | Picking | `view_picker` | W1 | 600 | `test_view_picker` incl. timings |
| **VIEW-F1** | FxManager port | `fx/{fx_manager, fx_batch, fx_assets}`; `assets/shaders/{fx_sprites, fx_ribbon, fx_ring, fx_dome, fx_column, fx_shimmer}.gdshader` + `fx_common.gdshaderinc` | 01, 04 | 1900 | `test_fx_manager` (buckets, cull with focus-distance fix, rings, cancel, tracker); spike sheets 0-3 reproduce (V-9); Mobile compiles |
| **VIEW-F2** | FX recipe engine | `fx/{fx_recipe_book, fx_catalog}` | F1, M1 (`ViewExpr`) | 1400 | interpreted `expl_*` matches the spike's batch set; `fx.json` compiler errors include the layer path; ≤ 100 µs per composite spawn |
| **VIEW-F3** | FX content | `data/recipes/fx.json` (~115 effects) | F2 | 2500 JSON | V-9 sheets (weapons 27, impacts, deaths, powers, zones, superweapons 8); no milky plates; ≥ 3 inspected rounds |
| **VIEW-F4** | FX event router | `fx/fx_event_router`; remaining `view_event_router` mappings | F2, W1 | 1500 | all events of §6.2.2 covered by a table-driven test over `ViewTestEvents`; hit / miss inference; explosion dedupe; visibility gating test; shake amounts; damage emitter cap 24 |
| **VIEW-O1** | Selection, health bars | `overlay/{view_selection, view_health_bars}`; `assets/shaders/{ring, health_bar}.gdshader` | W1 | 1400 | V-7 (rings not buried on slopes, bars constant size), shape pips per player index (V-16); caps 512 |
| **VIEW-O2** | Lines, placement ghost, range rings | `overlay/{view_lines, view_placement_ghost, view_range_rings}`; `assets/shaders/{line, ghost_grid}.gdshader` | W1 (O1 soft) | 1500 | V-7 ghost per-cell colours from `ViewPlacementState.cells` (filled from both validators in tests); build-radius ring = 24 m |
| **VIEW-O3** | Warnings, float text, debug overlay | `overlay/{view_warnings, view_debug_overlay}`, `view_float_text` | W1, F1 | 1000 | V-8, warning scenario (affected test, cancel), AI debug fixture |
| **VIEW-Q1** | Quality application + auto | integration in `view_quality*`, `ViewWorld.apply_quality`, settings keys | 01, 03, M3, F1 | 900 | live preset switch without restart; renderer clamps; auto test; accessibility keys live (`colour_mode`, `reduce_*`); V-13, V-16 |
| **VIEW-Q2** | Test scenes, cases, bench | `game/tests/view/**` (unit tests of §10, scenes, `game/tests/visual/cases.json` entries with `owner: view`, `bench_view.gd`; the fixture world and `ViewTestEvents` are VIEW-S1's) | continuous | 1500 | all §10 gates wired into `tools/gd test view` |
| **VIEW-Q3** | Hardware and Compatibility validation | measurement report in the task summary; fixes inside existing files | Q1, F3 | 600 | Intel + AMD iGPU numbers at Low; Compat FX cluster-sprite fix or documented downgrade; one Debian container run of V-2 (`gd linux shot`) |
| **VIEW-T9** (optional) | Terrain PBR pack | `tools/py/gen_view_textures.py`; `game/assets/textures/terrain_*.png`; terrain shader hook | 02 | 800 py | tileable 512² albedo / normal / roughness for grass, dirt, rock, sand, snow, asphalt, scrap; before / after screenshots |

**Waves (parallelism):** W-A: 01, T1, M1 · W-B: S1, 02, 05, M2, M3, Q2 (starts, continuous) · W-C: 03, 04, M4, M5, W1 · W-D: F1, M6, M7, W2, W4, O1, O2 · W-E: F2, W3, O3, M8a-d (four content agents in parallel), M9, Q1 · W-F: F3, F4, M10, Q3, T9, polish rounds. Critical paths: 01 -> M1 -> M2 -> M5 / M7 -> M8 (content) and 01 -> 02 -> 04 -> F1 -> F2 -> F3 / F4. Content tasks (M5-M8, F3) carry the visual quality bar: each must show its inspected screenshot rounds.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| R1 | "60 FPS at Low on integrated GPUs" is **unmeasured**: the spikes ran on an M5 Max only; a 10-25x weaker iGPU may miss it at native 1080p | ship the ladder `render_scale 0.75 -> 0.55` (FSR1), cheap-shader variants and auto-downgrade; measure on one Intel and one AMD iGPU in VIEW-Q3; if still short, lower the LOD threshold and decor density further and document the minimum spec |
| R2 | Authoring volume: ~215 recipes / ~330 meshes must look cohesive and distinct in 8 factions | archetype + style + slots keep unit recipes ≤ 20 lines; stubs generated; contact-sheet review per faction; ≥ 3 inspected rounds; four parallel faction tasks with a shared reviewer checklist (V-1) |
| R3 | Compatibility renderer: FX cluster sprites render smaller / dimmer (root cause not isolated), no Decal, no SSAO / AA variants, brighter look | Compat is "playable with downgrades": `compat_boost`, `compat_grade`, batch backend; dedicated pass VIEW-Q3; if the cause stays unknown, replace multi-quad clusters by per-quad instances on Compat only |
| R4 | The domain specs disagree with the MASTER event catalog (numeric ranges, payload shape) and the catalog lacks some information (death kind, hit result, buff state, ghost list); also attack orders on ghosts (sim_core 5.5 demands visibility, combat.md 6.1 accepts `is_known`) | the MASTER catalog is consumed by symbolic name with `_validate_codes()`; alias table 6.2.3; every gap has a derived fallback and an optional request (6.2.4, §13 3-13); a scripted scenario replays the same actions through `ViewTestEvents` |
| R5 | Footprint disagreement between specs (HQ 3x3 vs 4x4, refinery 3x3 vs 4x3, barracks 2x2 vs 3x3, factory 3x3 vs 4x3, airfield 6x3 vs 6x4 vs 4x3) and any later change | recipes take `fw, fh` and the door / exit / dock / pad anchors from the footprint at build time (the model is generated to fit, §7.3); V-RCP-10 checks the door socket; nothing is hard-coded per structure |
| R6 | Player colours can clash with faction paint (`[M]` pitfall 7) | team-plate rule + `contrast_against` test; optional lobby rule (net/ui): disallow a colour whose hue is within 25° of the chosen faction's dominant paint; the selection ring and minimap always carry the pure colour |
| R7 | GPU timing is unavailable on Metal; shared-machine noise ±0.3 ms; 120 Hz present cap | measurement protocol §5.12; treat sub-0.3 ms deltas as noise; verify GPU-bound claims with Instruments / RenderDoc on other hardware in Q3 |
| R8 | Instance-uniform capacity (4096 default; ~256 Compat) | raise `global_shader_variables/buffer_size` to 262 144; batch backend on Compat / Mobile; assert at runtime and fall back automatically when engine errors "Too many instances using shader instance variables" |
| R9 | Submarines under alpha water read as invisible or as surface ships | "awash" look (top 0.15 m above the surface, dark, wake) for the owner; enemies see nothing unless detected; revisit after V-4 (option: draw own submerged units in a late pass without depth test) |
| R10 | Match-start model builds for 8 rosters (≈ 2 s single-threaded) | lazy per-roster, threaded, disk cache option; loading screen budget 4 s cold |
| R11 | Pick volumes for odd silhouettes and small fast aircraft | OBB + 22 px screen fallback for air; tune `pick_half` per size class with `test_view_picker`; UI may add its own click tolerance |
| R12 | `MapData` is published, but sea level, roads, shore distance, moisture and building heights are view-derived and may diverge from the generator's intent | derivation rules in §5.5 with worked examples; `test_view_terrain_source`; screenshot rounds V-3 (4 biomes) and V-17 (urban); requests 23-25 pin the generator properties the view relies on |
| R13 | Tall structures near the bottom edge could clip the near plane | `near = 0.6 H`, structure height cap 14 m; test with the 14 m superweapon at the bottom edge at H = 34 |
| R14 | LOD popping with `mesh_lod_threshold` | screenshot pair test around the switch distances; hysteresis is engine-side; adjust keys 0.02 / 0.06 if visible |
| R15 | Refraction FX do not distort water (screen copy excludes the transparent pass) | disable distortion over water; alternative (open): render water with lower priority than distortion and accept a full-screen copy after water (+cost) |
| R16 | Screenshot reproducibility across renderers | `screenshot_mode` freezes clocks / RNG; comparisons use tolerance and human review, never exact hashes across renderers |
| R17 | Font for 3D floating text | `ViewFloatText.font` provided by `ui`; fallback `ThemeDB.fallback_font` |
| R18 | Infantry "fall" animation: members simply disappear | v1 acceptable (dust puff); v2: shader-time collapse when the member index becomes hidden |
| R19 | 3D health bars vs `ui`-drawn bars | 3D MultiMesh bars are one draw call and zoom-independent; `ui` may set `Mode.NEVER` and draw its own |
| R20 | Colour-blind separability of eight teams with only 4-12 % of a model team-coloured | implemented in §5.12: Okabe-Ito based palette modes, shape pips on bars and rings for every mode, `high_contrast`; QA V-A01 and scene V-16 verify; residual risk: at long range a unit's identity rests on the pip and the minimap |
| R21 | Terrain relief noise (0.45 m) makes units float / sink relative to sim heights | masked to ≈ 0 on roads and start plateaus; units use the *rendered* height, so they always touch the visible ground |
| R22 | ArrayMesh disk cache correctness (LOD indices, custom arrays) untested | VIEW-M10 verifies save / load equality before enabling; cache key includes builder version |
| R23 | Per-frame `Node3D` transform writes for ~400 rigs are **unmeasured** (spikes measured only instance-uniform writes: 0.3-0.9 ms per 800 calls); the 2 µs/entity estimate may be optimistic on mid-range CPUs | VIEW-W1's bench measures it; mitigations already specified (off-screen 5 Hz, skip unchanged pushes); if the loop exceeds 2.5 ms at 400 entities, make the batch backend the default on all renderers (bulk buffer writes, ~0.6 µs per entity) |
| R24 | **Deposit model conflict**: `MapData` per-cell amounts (terrain_movement.md 3.3), DEPOSIT entities (sim_core 4.12) and economy's `SimDepositTable` | the view implements the `MapData` per-cell reader (`ViewTerrainSource.deposit_*`, VIEW-04) and a ~60-line entity adapter (`ViewBuildOptions.deposit_source = 1`); the economy table is never read; the reconcilers pick one and the other adapter is deleted |
| R25 | **Def index-space conflict**: per-kind indices (data_balance.md) vs one dense entity-def space (sim_core R1) | `ViewDefAdapter` supports both behind `def_for(kind, def_idx)`; `test_view_def_adapter` runs both; only that file changes when the reconcilers decide |
| R26 | Component names and internals differ between specs (`SimCombatComp` vs `SimCompCombat`, `mnt`, `M_ANGLE`, rally, cargo) | every read is in `ViewSimReader` with null-safe defaults (turrets stay at rest angle, bins empty, no rally line); `test_view_sim_reader` with fixture components; R26 closes when the components are delivered |
| R27 | Frame-granular interpolation runs 3x fast for one tick after a k-tick catch-up frame | rare (hitches only), never backwards, invisible in the common 1-tick frame; the optional `capture_prev` hook (request 11) removes it |
| R28 | Painted street markings only exist for perfectly straight axis-aligned streets (run-length rule with a 12-cell straightness test); a rotated urban layout gets worn asphalt only, and a trunk shallower than about 1/12 on an urban map would be painted with a 3 m lateral step every 36 m | acceptable degradation; V-17 documents which layouts get markings; if ugly, raise the straightness threshold or disable paint on trunks (`ROAD` runs of width 3) |
| Q1 | Should structures face south (+Z) or follow `facing`? | orientation 0 faces south (+Z) so doors and exits are visible from the default camera and agree with `footprints.json` (`exit_dir` 1024); `facing = 1024 * orient` rotates the whole model clockwise (only the Dock rotates, request 2) |
| Q2 | Default health-bar mode | `DAMAGED` (selected, hovered, hurt within 8 s, construction); `ALWAYS` is a setting |
| Q3 | Wide view (110 m) | off by default (shadow fit and LODs are tuned for 84 m); setting `wide_view` |
| Q4 | WASD panning | off by default (A / S / G / D are command hotkeys); arrows + edge scroll + MMB orbit |
| Q5 | Are Decals needed anywhere? | no; scorch layer + `gglow` cover everything; keeps Compat parity |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

Requests 1-13 are the ones the body of this spec refers to by number; 14 and up are grouped by recipient. "Optional" means the view has a documented fallback and nothing is blocked.

**Contract additions referenced from the text (1-13)**

1. **sim_core (5.7, 3.7): batch and ordering guarantees.** One `events.take()` per rendered frame, handed read-only to view, audio, ui and the host AI (already stated); the ordering guarantees of §6.2.1 written down as normative (`SPAWNED` first for an entity, `DIED` before `REMOVED` back to back, the wreck's `SPAWNED` after the `DIED` of its unit, stage order inside a tick); the event names and enum values exposed as class constants exactly as the catalog spells them (`SimEvent.SPAWNED`, `DIED`, `STATE`, ..., `ST_DEPLOYING` ... `ST_REPAIRING`, `SPAWN_*`, `REM_*`, `DIE_*`, `SimFlags.F_*`) so the view can validate them at start-up.
2. **sim_core + production: structure orientation.** `spawn_structure(...)` (or the PLACE executor right after it) stores `facing = 1024 * orient` (orient 0..3, clockwise seen from above, `MapFootprint` orientation) for rotatable structures and leaves 0 for all others; the `PLACE` wire schema gets an `ANGLE` field (or `COUNT` as orientation) for the Dock (economy.md `CMD_BUILD_PLACE(s_idx, cx, cy, rot)`); `SPAWNED.f` carries it.
3. **combat: `WEAPON_FIRED` layout and readable state.** Confirm `f = muzzle_idx = mount | barrel << 4` and add the outcome in the high bits, `f = muzzle_idx | result << 8` (0 projectile, 1 hit, 2 miss, 3 beam); emit the instant weapon's `DAMAGE` in the same tick as its `WEAPON_FIRED` (the view's hit inference pairs them); keep `mnt[m * MS + M_ANGLE]` relative to the hull and readable from `e.combat` with the constants `MS`, `M_ANGLE` public; keep `world.projectiles` (combat.md 4.4: `alive, serial, kind, pdef, x, y, px, py, heading`) public read-only with `serial == PROJECTILE_LAUNCHED.a`; expose per-mount `range_max_eff(e, m)` and `range_min_of(e, m)` as static queries (combat.md 3.7).
4. **data (+ combat): weapon and fx lookups.** `GameData.weapon_arch_of(weapon_def_idx: int) -> int` (pure table lookup, `DefWeaponArch` index 0..26 or -1) for the weapon def index carried by `WEAPON_FIRED.b`, `PROJECTILE_*.b`, `BEAM.b`, `DAMAGE.e`; `GameData.pres_names: PackedStringArray` (sorted unique presentation `fx` strings of warheads, weapons, zones and powers; `EXPLOSION.d` indexes it, 0 = auto) with `pres_name(idx) -> String`; `GameData.id_of(kind, idx)` (published) for superweapon and power ids.
5. **sim_core + economy / abilities: `POWER_WARNING` 0x38** with the layout of `SW_WARNING` (`a` owner pid, `b` power idx, `c, d` x, y, `e` angle, `f` warning ticks, `g` source id, `h` extent units), never fog-gated, for Wideband Scan and the Counterlaunch-style delayed powers; in `SW_WARNING`, `h` is the length of a capsule or the radius of a disc in sub-cell units.
6. **economy / production (optional): `STATE ST_BUILDUP = 16`** (`c` 0 start / 1 done, `d` duration ticks) at structure placement; else the recipe default of 30 ticks (economy.md 5.3) applies.
7. **combat / economy (optional): `STATE ST_REARMING = 17`** (`c` 1 begin / 0 end) for aircraft on a pad; else no rearm sparks.
8. **economy (optional): `CAPTURE_PROGRESS` 0x1A** (`a` structure id, `b` leading pid, `c` progress permille) every 10 ticks while a capture channel runs; else no progress ring.
9. **sim_core + vision: remembered structures.** `SimFogApi.ghosts(pid) -> Array` of records with `eid, def_idx, owner, x, y, facing, hp_pct, seen_tick` (abilities.md 5.9.7 `SimGhost`) and `SimFogApi.ghost_version(pid) -> int` (increments on any change), so the view depends on the kernel hook and not on `SimVisionSystem`.
10. **sim_core + vision: `SimFogApi.decoy_identified(pid, e) -> bool`** (abilities.md `SimVision.decoy_identified`) for the `UF_DECOY_ID` overlay.
11. **net + app (optional): exact interpolation hook.** `NetSession` exposes `var pre_step: Callable` and calls it with the world before every `world.step()`; the app sets it to `view.capture_prev`. Also: while `sim.paused != 0` or the match has ended, `tick_alpha()` may keep running; the view forces `alpha = 1` in those states.
12. **economy (optional): HQ undeploy.** `CMD_UNDEPLOY_HQ` (economy.md) has no opcode in the sim_core catalog; if it is added, the HQ carries `F_DEPLOYING` for the duration so the view can play the reverse build-up.
13. **abilities / economy (optional): per-entity buffs.** `STATE ST_BUFF = 18` (`c` theme: 1 damage, 2 speed, 3 defence, 4 range or sight, 5 camouflage, 6 penalty; `d` duration) and `ST_MARKED = 19` (`c` 1 / 0), emitted for each affected entity; else the view approximates from `POWER_USED` (§5.9.6).

**sim_core (kernel)**

14. Keep the read surface of §3.0 stable and public: `entity(id)`, `entities`, `tick`, `paused`, `rules.{fog_mode, shared_vision, speed_pct, wrecks}`, `players[pid].{color, roster_idx, faction_idx, team, eliminated, sw_state, sw_x, sw_y, sw_angle, sw_warn_until}`, `query_radius`, `entity_visible`, `cell_visible`, `fog`, `map`, `data`; `SimEntity.{x, y, facing, layer, hp, max_hp, flags, holder, born, expires, t_hit, t_fire, t_disabled, t_shutdown, t_suppressed, orders}`; `SimOrder.{type, target, x, y}`.
15. Document `facing` (0 = +x east, increasing toward +y south; already in 4.2) as the only orientation of units and state that `x, y` of a structure is the footprint centre (already in 4.2).
16. Flag ownership: the movement domain sets `F_MOVING, F_AIRBORNE, F_ON_WATER` every tick; the power domain sets `F_POWERED` for every structure on each power update; abilities set `F_CLOAKED, F_DEPLOYED, F_DEPLOYING`; combat sets `F_FIRING, F_WEAPONS_OFF` (the view derives its look from them and from `t_*` timers, with no event polling).

**data / balance**

17. `pres_recipe`, `pres_icon`, `pres_scale_bp` on `DefUnit`, `DefStructure`, `DefNeutral`, `DefZone` (published in data_balance.md 4.2 / 7.15); `style_tags large / compact` -> `pres_scale_bp` 12500 / 8800; `DefFaction.pres_palette` = style id (`napc`, ...); roster -> style mapping `roster.napc.canada` -> `napc.canada`.
18. Either index space is fine for the view: per-kind indices (data_balance.md 3.1 `unit_idx`, `structure_idx`) or the single dense entity-def space of sim_core R1; state which one `SimEntity.def_idx` uses. `ViewDefAdapter` reads `DefUnit.{faction, unit_class, move_class, size_class, radius, layer_mask, flags, weapons[].arch, weapons[].mount}` and `DefStructure.{faction, fp_w, fp_h, fp_mask, power, flags, size_class}`, `DefZone.{zone_kind, shape, radius, length, width, visible_to_enemy}`, `DefWeaponArch.{dtype, proj_kind, proj_speed, homing, target_mask, fire_mode}`.
19. Footprint anchors reachable per structure def: `GameData.footprint(structure_idx) -> MapFootprint` (or through `GameData.terrain`), giving `door`, `exit_dir`, `dock`, `pads`, `reserve`, `rotatable` (terrain_movement.md 3.6 / 7.3).
20. Deployable units need `deploy_s` / `pack_s` so the view animates the same duration (default 3 s; `STATE` durations override); superweapon and power ids follow the bible (`superweapon.<code>.<name>`, `power.<code>.<name>`); `fx.json` uses the last segment.
21. `pres_fx` strings and the `fx` strings of `combat_warheads.json` use the vocabulary of §5.9.2 / §7.5, or are omitted (defaults are derived from archetype, projectile kind and splash).
22. Neutral and summon def ids: reconcile the spellings (§5.8.7) or keep the six neutral kits and eight summon kits reachable by the patterns of §7.4.

**map / movement**

23. `MapData` read-only fields as published (terrain_movement.md 3.3 / 4.1): `w, h, seed, family, biome, terrain, height, flags, deco, deco_seed, deposit, deposit_max, occ, fields, neutrals, spawns`; `MapImages.corner_height`; `drain_deposit_dirty` is called by the view only (it clears the list).
24. Keep these generator properties (the view relies on them, §5.5): water cells (ids 0, 1) have `height` at or below the sea level and ford cells (id 2) at or below it too, so `max height over water cells` is the sea level; the 2-cell MOUNTAIN rim; urban streets axis-aligned (street cells are recognised by run lengths, anything else gets no paint); heights 0..255 at 0.05 m per level.
25. `NK_SCENERY` boulders (variant = `hash & 3`) and `SF_BLOCK` cells are drawn as rocks by the view; `neutrals` entries of the other kinds are sim entities and appear through `SPAWNED`.

**economy / production / power**

26. `SimCompProd.rally_on, rally_x, rally_y, rally_target` and `SimCompEcon.cargo` (+ the capacity from `DefEconomy.collector_capacity_cr`) readable for `ViewSimReader` (rally lines, collector bin fill); `HARVEST_DELIVERED` once per unload pulse; `F_POWERED` semantics as request 16; `F_SELLING` mirrors `STATE ST_SELLING`.
27. `SimPlacement.validate` result mapping: the UI copies `SimPlacementResult.cells` (`CF_OK 0` ... `CF_SHORE 7`) into `ViewPlacementState`; map's `PR_KEEPOUT / PR_HALO / PR_NOBUILD` become `CF_KEEPOUT 8`; `rot` is clockwise quarter turns seen from above.

**abilities / vision / zones**

28. `F_CLOAKED` is set for a cloaked entity whether or not the local player detects it; `entity_visible(pid, e)` returns true for own and allied cloaked entities and for detected enemy ones (the view then adds the shimmer).
29. ZONE entities: `x, y, facing` and `expires` on the entity, geometry from the def; optional `zone.charges` for the Trident dome brightness (`ViewSimReader.zone_charges`).

**net / app**

30. `NetSession.tick_alpha()` (published) and the frame order of §3.0 (`session.poll()` -> `events.take()` -> `view.frame(delta, alpha, batch)` -> audio -> ui); request 11 for the optional hook.
31. `project.godot`: `[shader_globals]` `fx_time`, `fx_lod`, `view_time` (§7.8); `rendering/limits/global_shader_variables/buffer_size=262144`; `physics/common/enable_object_picking=false` (already); no `[input]` needed (actions registered at runtime).
32. Settings keys of §7.7 (`[video]`, `[access]`) and a settings screen for quality (preset, render scale, scaling mode, AA, shadows, health bars, night maps, wide view, WASD panning) and for the accessibility toggles; call `ViewQuality.from_settings` at boot and `ViewWorld.apply_quality` on change; create `user://cache/` (models, icons).
33. Loading screen consumes `ViewWorld.build_progress(fraction, stage)`; `await view.build_async(world, local_pid, opts)` with no more than 8 ms per frame; the app keeps `NetSession.poll()` running during the load (net.md `launch.step` budget); drop the world reference on `phase_changed(IDLE)` / `match_ended` (net.md XR-17).
34. Log through `Log.info/warn/error` only (L006); the view calls no `print`.

**ui**

35. Use `ViewWorld.pick / pick_box / pick_ground / entity_screen_rect / world_to_sim`; drive `ViewSelection.set_selection`, `set_hover`, `ViewHealthBars.set_mode`, `ViewLines.set_*_sources`, `ViewPlacementGhost.show_structure / update_cursor / show_build_radius / hide_ghost` (filling one reusable `ViewPlacementState`), `ViewRangeRings.show_for`; assign `ViewMinimapSource.make_material()` to the minimap `TextureRect` and draw dots / camera quad from `entity_world_pos` and `camera.visible_ground_rect()`; icons via `ViewIconBake.request` (`icon_ready` signal).
36. Provide the font for `ViewFloatText`; set `camera.view_margin_px` to the sidebar width; disable `camera.edge_scroll_enabled` while dragging a selection box near the edge; do not consume `_unhandled_input` mouse wheel / MMB events that belong to the camera; take slot colours from `ViewTeamColors` (the lobby swatches of net.md 7.2 are the same values) and expose the accessibility toggles of request 32.
37. Render `AiDebugFrame` panel text; the view draws circles / lines / heat (`ViewDebugOverlay`), debug builds only.

**audio**

38. Read the same batch; use `ViewCamera.listener_transform()`; no other view dependency.

**qa / tooling**

39. `tools/gd test view` discovery of `game/tests/view/test_*.gd` (qa_tooling.md 5); lint proposal L011 (view read-only guard, §8; L010 is taken by the CRLF rule); visual scenes registered in `game/tests/visual/cases.json` with `owner: view` (qa.md 5.9), injectables per QA-XR-28 (`ViewWorld.create(q)` + `await build_async(world, pid, opts)` instead of `ViewRoot.new(adapter, pid)`; the view needs the real `SimWorld`, not the QA adapter; `ViewCamera.set_pose`; `screenshot_mode`).
40. `tools/gd shot` already forwards args after `--`; confirm `--rendering-method` is accepted together with a scene that reads `--quality`; `gd linux shot` (lavapipe, amd64) is used for shader-compile smoke tests, and `linux-arm64-gl` (Compatibility only) for layout checks (qa.md 5.9).
41. QA checklist items V-T01 .. V-R01, V-A01, V-IP1, V-ID1 are the acceptance language for terrain, unit silhouettes, colour-blind separability, no real-world marks and no visible ids; the view scenes V-1 .. V-17 of §10.4 map onto them.

