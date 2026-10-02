# MERIDIAN FRACTURE — Art Direction & Content Style Guide (the visual bible)

> **Domain:** art direction · **Version:** 1.0 · **Binding for:** the eight faction content designers, the render / model / terrain / UI / VFX implementers and the QA reviewer.
> **Machine-readable twin:** `game/data/recipes/style.json` (schema `meridian.style/1`, ~114 KB). Every palette hex, size card, tier and threshold in the tables below is generated from that file, and the hexes quoted in prose live in `palettes`, `shared_colors`, `ui.tokens`, `ui.chrome` and `vfx.colors`; if prose and JSON ever disagree, **the JSON wins** and the prose is a bug.
> **Evidence policy.** Numbers tagged **MEASURED** were taken from proof renders made for this document (Godot 4.7.2, Forward+, Metal, 1920x1080) with the models spike shader and builder (`prototypes/models`), the terrain spike's mood/atmosphere code, the UI spike theme and the VFX spike recipes. Screens were inspected, not assumed. Anything not tagged MEASURED is a design decision or a target.
> **Peer specs.** Written in parallel with `render.md`, `sim_core.md` (master events and flags), `terrain_movement.md` (`MapData`), `qa.md` / `qa_tooling.md`, `data_balance.md`, `net.md`, `combat.md`, `economy.md`, `abilities.md` and `audio.md`; each was consulted for the interfaces this document touches. Where this document adopts a peer decision it says so; where it deliberately differs (Color-to-Vector4 uniform fix, Filmic tonemapper, sun direction, look presets, team-plate anatomy, player colours) the difference is listed in section 12 (RK-1, RK-17 to RK-26) with a recommended resolution.
> **Look in one sentence.** *Stylised hard-surface realism seen through a 55-degree tabletop camera: chunky, bevelled, slightly weathered near-future machines with a dark/mid/light value structure, one signature accent colour per faction, and a bright, neutral, always-legible owner plate.*

**How to read this document**

| You are... | Read first | Then |
|---|---|---|
| Faction content designer (models, 8 of you) | 5.3 palettes, 5.4 team colour, **your faction in 5.5**, 5.6 (subfactions + unique units), 5.7 size cards, 5.8 readability, 5.9 structures | 5.10 animation, 5.16 QA checklist (you will be reviewed against it) |
| Render / model implementer | 5.2 colour pipeline (**contains a shader defect fix**), 4.4 vertex/uniform contract, 5.14 lighting | 13 (requests to you) |
| UI implementer | 5.11 emblems, 5.12 UI language, 7.5 UI data | 13 |
| VFX implementer | 5.13 VFX style, 4.6 tiers | 6 (event mapping) |
| Terrain / map implementer | 5.14 look presets per map biome and terrain palettes | 13 |
| QA reviewer | 5.16 checklist and screenshot protocol, 10 test plan | 5.15 do/don't |

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**Purpose.** Make ~185 procedural models (156 unit definitions, 29 structure definitions, re-skinned for 8 factions and 24 subfactions), every UI screen and every effect feel like **one** AAA game with **eight** clearly different dialects, using no external art. This document turns the bible's one-line `visual_direction` strings and the models spike's findings into rules a machine can lint and an agent can review.

**Owned by this domain**

1. The look: value structure, saturation and contrast targets, material and wear language, scale exaggeration (5.1).
2. The colour pipeline contract between authored hex values and what the player sees, including a **defect found in the spike** and the team-colour system (5.2, 5.4).
3. Exact palettes for the 8 factions and their 24 subfaction accent variants, neutral/civilian props (5.3, 5.6).
4. Shape language, panel/greeble vocabulary, signature details and per-archetype adaptations for each faction (5.5).
5. Subfaction differentiation: accent variants, band patterns, insignia, kit-bash parts, and the visual recipe of all 48 unique units (5.6).
6. Size cards in cells and metres for every archetype and structure footprint (5.7); RTS-distance readability rules (5.8); structure vocabulary incl. superweapon landmarks (5.9); animation principles (5.10).
7. Faction emblems and 24 subfaction glyphs as procedural vector data (5.11).
8. UI visual language: tokens, typography, chrome, iconography, faction-tinted skins (5.12).
9. VFX style: colour by damage type, scale tiers, status looks (5.13).
10. Lighting / environment presets per map biome (8 looks plus a QA reference, chosen from `MapData.biome` and `MapData.family`), terrain colour sets, fog-of-war look (5.14).
11. Do/don't lists and the screenshot-based QA checklist (5.15, 5.16).
12. `style.json`, its loader (`ViewStyle`), its validator (`tools/py/check_style.py`) and the visual test boards.

**NOT owned (and who owns it)**

| Not mine | Owner | Interface |
|---|---|---|
| `ViewMeshBuilder`, `ViewMaterials`, `unit.gdshader`, `ViewModelRig`, `ViewModelBuilder` (cache), `ViewRecipeBook` / interpreter / macros, `styles.json`, `moods.json`, `fx.json`, `quality.json`, LOD, recipe file format | render domain (`docs/spec/render.md`, written in parallel) | I supply palettes, roles, constraints, values and a list of required changes (section 13); the divergences between the two specs are tabulated in 12 (RK-17 and following) and 13 |
| Individual unit/structure **recipes** (`game/data/recipes/<id>.json`) | the eight faction content designers | they obey 5.3-5.10 and the Recipe Style Contract (5.5.9) |
| Terrain mesh, water shader, `ViewAtmosphere` implementation, fog texture | render domain (view side), map domain (`MapData`, terrain_movement.md) | I supply `ViewMoodDef` looks, terrain palettes and the biome to look table |
| HUD layout, screen flows, hotkeys, `UiTheme` code | UI domain | I supply tokens and skins; the UI domain implements them |
| Sim stats, damage types, weapon archetypes, footprints | combat / data-balance / economy | I **consume** them read-only (size cards follow `docs/balance/TAXONOMY.md`) |
| Audio | audio domain | none |
| Cameras / input | render (`ViewCamera`) / UI domains | I define the reference camera *tiers* (zoom stops of render.md 5.4) used for readability, not their controls |

**Hard constraints inherited from `docs/ARCHITECTURE.md`.** No external art (only OFL/MIT/CC0 fonts); all models are procedural single-mesh recipes; team colour via instance uniform; visuals never feed back into the sim (DR-12/DR-15); all art data is float-friendly because it lives in `view/`, `ui/` and `data/recipes/`.

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

| Path | `class_name` | Module | Responsibility |
|---|---|---|---|
| `game/data/recipes/style.json` | — | data | The visual bible as data (palettes, player colours, size cards, tiers, emblems, UI tokens, looks, thresholds). Written by this spec; edited only through PRs that also re-run `check_style.py`. |
| `docs/spec/art_direction.md` | — | docs | This document. |
| `game/src/view/view_style.gd` | `ViewStyle` | view | Loads and validates `style.json`; typed read-only accessors (section 3). One instance, created by `App` at boot, passed by reference to `ViewWorld` (and through it to `ViewMaterials`, `ViewModelBuilder`, `ViewAtmosphere`, `FxCatalog`, `ViewSelection`, `ViewHealthBars`) and to the UI root. |
| `game/src/view/view_palette.gd` | `ViewPalette` | view | Typed record of one faction (or subfaction) palette; `material_style()` for `ViewMaterials.unit_material`. |
| `game/src/view/view_mood_def.gd` | `ViewMoodDef` | view | Look (lighting + terrain-colour) preset record (promotion of the terrain spike class, fields extended in 4.3). |
| `game/src/view/fx_style.gd` | `FxStyle` | view (fx) | Resolves damage type + splash radius to a tier, colours, light/shake/scorch numbers. Pure lookup, no nodes; called by render's `FxCatalog` / `FxEventRouter` (render.md 3.6). |
| `game/src/ui/ui_emblem.gd` | `UiEmblem` | ui | Interprets the emblem op lists on any `CanvasItem`; sub-badges and pips. |
| `game/src/view/view_emblem_geometry.gd` | `ViewEmblemGeometry` | view | Converts the same op lists to flat polygons for `ViewMeshBuilder` (world insignia on hulls, roofs and fascias). |
| `game/src/ui/ui_skin.gd` (spike class, UI domain) | `UiSkin` | ui | Gains `static func from_style(style: ViewStyle, faction_code: String) -> UiSkin`. Data owned here, code owned by UI. |
| `game/src/ui/ui_palette.gd` (spike class, UI domain) | `UiPalette` | ui | Constants must equal `style.ui.tokens`; a unit test asserts equality. |
| `tools/py/check_style.py` | — | tools | Validator: schema, hex, gamut, ΔE00 tables, CVD simulation, contrast ratios, size-card rules, emblem coordinates. Exit 1 on error. |
| `game/tests/unit/test_view_style.gd` | — | tests | Unit tests (section 10). |
| `game/tests/visual/art_boards.gd` + `art_boards.tscn` | — | tests | Screenshot boards used by the QA checklist (family, matrix, look, structure, emblem, ui, vfx, silhouette, icons). |
| `tools/py/art_report.py` | — | tools | Reads the boards' log lines (`PLATE ...`, `LOOK ...`) and prints the ΔE / IoU tables checked in 5.16. |
| `tools/py/gen_recipe_styles.py` (render domain, requested in R-2 and R-9) | — | tools | Generates the `palette` blocks of `styles.json` and the whole of `moods.json` from `style.json`, so that every hex exists once. |

Module rule check: `ViewStyle` reads only `core/` (hash helper) and JSON; it never touches `sim/`. `UiEmblem` and `FxStyle` depend on `ViewStyle` only.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

All classes below live in presentation modules. Floats and `Color` are allowed (DR-15). **Nothing here is called from `sim/`, `net/` or `ai/`.**

```gdscript
class_name ViewStyle
extends RefCounted
# Immutable after load. Not an autoload: App creates it once and injects it.

const PATH: String = "res://data/recipes/style.json"
const SCHEMA: String = "meridian.style/1"
const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]   # bible order == faction index

# Parse + validate. On any violation: push_error("style.json: <json path>: <reason>") and return null.
static func load_file(path: String = PATH) -> ViewStyle
static func from_dict(d: Dictionary) -> ViewStyle                       # tests / tools

func faction_index(code: String) -> int                                  # "napc" -> 0 ... "sap" -> 7; -1 if unknown
func palette(faction_code: String) -> ViewPalette                        # vanilla palette; cached; null only for unknown codes
func palette_for_roster(roster_id: String) -> ViewPalette                # "roster.napc.usa" -> sub variant; "roster.napc.vanilla" -> vanilla
func palette_by_id(palette_id: String) -> ViewPalette                    # "palette.napc" | "palette.napc.usa"; matches DefFaction/DefRoster.pres_palette
func sub_index(roster_id: String) -> int                                 # 0 vanilla, 1..3 subfaction (drives pips and accent rule)
func neutral_palette() -> ViewPalette                                    # civic / salvage props

func player_color(color_id: int, cvd: bool = false) -> Color             # ids 0..11 (cvd: 0..7; ids >= 8 fall back to the default set)
func player_color_count(cvd: bool = false) -> int                        # 12 / 8
func team_uniform(color_id: int, cvd: bool = false, cloak: float = 0.0) -> Vector4   # (r, g, b, cloak) raw sRGB, w = cloak level 0..1 (render.md 4.4); PASS THIS TO set_instance_shader_parameter(&"u_team", ...) (see 5.2.1)
func default_color_for_slot(slot: int) -> int                            # style.player_colors.assign_order[slot & 7]
func plate_contrast(faction_code: String, color_id: int, cvd: bool = false) -> float   # ΔE00 (authored) between the team colour and the faction primary; lobby shows a hint if < 20

func archetype(archetype_id: String) -> Dictionary                       # size card, 4.2; {} if unknown. Read-only.
func structure(key: String) -> Dictionary                                # structure card, 4.2 ("factory", "neutral.substation", ...)
func camera_tier(tier: String) -> Dictionary                             # "NEAR" | "MID" | "FAR" | "MAX"
func look(id: Variant) -> ViewMoodDef                                    # int LookId or String "temperate_day" / "look.temperate_day"
func look_count() -> int                                                 # 8 game looks (+ studio_neutral at id 8 for QA)
func look_for_map(map_biome: int, map_family: int, night: bool = false) -> ViewMoodDef   # MapData.biome / MapData.family (terrain_movement.md) -> look, table in 5.14.2 (the same function as render.md's ViewMoodDef.for_map); night = the optional night_ops lighting over the terrain set of the map's day look

func emblem_ops(faction_code: String) -> Array                           # op list, 5.11
func sub_glyph_ops(sub_key: String) -> Array                             # "napc.usa"
func kit_part_text(kit_id: String) -> String
func kit_part_applies(kit_id: String) -> PackedStringArray               # families the part may be used on: "veh" "ship" "air" "inf" "struct" (5.6.5)
func unique_unit(unit_id: String) -> Dictionary                          # {replaces, archetype, recipe, kit}; {} if not a unique unit

func ui_token(name: String) -> Color                                     # "TEXT", "BG_PANEL", ...
func skin(faction_code: String) -> Dictionary                            # {accent: Color, accent2: Color, tint: Color}
func fx_tier(tier: int) -> Dictionary                                    # 4.6
func threshold(name: String) -> float                                    # style.thresholds.*
func shared_color(name: String) -> Color                                 # style.shared_colors.*: "tail_light", "hazard_black", "wreck_plate", "plinth_concrete"
func fx_color(name: String) -> Color                                     # style.vfx.colors.* (named effect colours of 5.13)
func chrome() -> Dictionary                                              # style.ui.chrome (5.12.4), read-only
func data_hash() -> int                                                  # FNV-1a of the canonical text; QA/screenshots only, never networked
```

```gdscript
class_name ViewPalette
extends RefCounted
var id: String                 # "palette.napc" | "palette.napc.usa"
var faction: String            # "napc"
var sub_index: int             # 0 vanilla, 1..3
var primary: Color; var secondary: Color; var accent: Color; var dark: Color
var emissive: Color; var emissive_alt: Color
var metal: Color; var glass: Color; var rubber: Color; var light: Color; var team_key: Color
var area_mix: Dictionary       # {primary, secondary, dark, accent, team} fractions, sum 1.0
var panel_m: float; var bevel_m: float; var greeble_per_m2: float; var chamfer: String
var band: String; var glyph: String; var kit: PackedStringArray     # subfaction only ("" / [] for vanilla)

func role_color(role: StringName) -> Color      # &"primary" ... &"team_key"; push_error + magenta on unknown role
func material_style() -> Dictionary             # {wear, dirt, panel, wear_color: Color, dirt_color: Color, emissive: float, quality: 1.0} -> ViewMaterials.unit_material()
func cache_key() -> String                      # == id; the model cache key is (recipe_id, palette.cache_key())
```

```gdscript
class_name FxStyle
extends RefCounted
static func tier_for_splash(splash_units: int) -> int                    # sim units (1024 per cell); thresholds 751 / 1502 / 2355 / 3413; 0 for splash 0
static func impact_tier(proj_kind: int, splash_units: int) -> int        # max(tier_for_splash, floor by projectile kind: HITSCAN 0, BULLET 0, MISSILE 1, ARC 1, BOMB 3, STRIKE 5, SWEEP 5, BEAM 0)  (combat.md PK_*)
func colors(dtype: int, faction_code: String = "") -> Dictionary         # {core: Color, glow: Color, hdr: float}; thermal glow = faction emissive mixed 25% white
func tier(t: int) -> Dictionary                                          # same as ViewStyle.fx_tier
func hp_color(fraction: float) -> Color                                  # ramp with 0.66 / 0.33 breakpoints
func relation_color(relation: int) -> Color                              # REL_SELF 0, REL_ALLY 1, REL_ENEMY 2, REL_NEUTRAL 3 (combat.md)
```

```gdscript
class_name UiEmblem
extends RefCounted
# ops: Array of ["poly"|"line"|"circle"|"arc", ...] in the unit square (y down), see 5.11.
static func draw_ops(ci: CanvasItem, ops: Array, rect: Rect2, c1: Color, c2: Color, bg: Color) -> void
static func draw_faction(ci: CanvasItem, style: ViewStyle, faction_code: String, rect: Rect2, sub_index: int = 0, sub_key: String = "") -> void
static func draw_badge(ci: CanvasItem, glyph_ops: Array, rect: Rect2, c1: Color, c2: Color, bg: Color) -> void   # lower-right quadrant disc
static func draw_pips(ci: CanvasItem, sub_index: int, rect: Rect2, c1: Color) -> void                             # used below 48 px
const MIN_STROKE_PX: float = 1.5

class_name ViewEmblemGeometry
extends RefCounted
# ASSUMPTION(render): ViewMeshBuilder exposes brush(), set_part(), prism() as in render.md 3.5 (lifted from prototypes/models).
static func polygons(ops: Array, size_m: float) -> Array[PackedVector2Array]      # convex-decomposed, model-plane metres, origin at the centre, +Y up
static func stamp(b: ViewMeshBuilder, ops: Array, centre: Vector3, normal: Vector3, up: Vector3, size_m: float, c1: Color, c2: Color, thickness_m: float = 0.012) -> void
```

**Call order.** (1) `App.boot` → `ViewStyle.load_file()` (once, ~2 ms; failure aborts to an error screen in dev, falls back to a built-in minimal NAPC palette in release). (2) Map load → `ViewAtmosphere.apply_mood(style.look_for_map(map.biome, map.family, settings.night))`. (3) Match start → for each player `style.palette_for_roster(roster_id)`; `ViewModelBuilder.get_model(recipe_id, style_id)` builds or fetches meshes; `ViewMaterials.unit_material(style_id)` creates one material per palette from `palette.material_style()` (render.md 3.5). (4) Entity spawn → `rig.set_instance_shader_parameter(&"u_team", style.team_uniform(color_id, cvd, cloak))` (a `Vector4`, never a `Color`; 5.2.1). (5) UI build → `UiTheme.build(UiSkin.from_style(style, faction_code))`. (6) VFX on each sim event → `FxStyle.tier_for_splash(...)`, `colors(...)`. No per-tick work.

**Memory ownership.** `ViewStyle` owns every `Dictionary`/`Array` it returns; callers must not mutate them (`duplicate(true)` if needed). `Color`/`Vector4` are returned by value. `ViewPalette` instances are cached inside `ViewStyle` and shared. Nothing is freed before shutdown.

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations (frozen: appear in map files, settings and screenshots)

```
FactionIndex   NAPC 0, NEC 1, OLM 2, DEF 3, PD 4, HAN 5, AE 6, SAP 7                    # bible order
LookId         TEMPERATE_DAY 0, ARID_DAY 1, ARID_DUSK 2, URBAN_OVERCAST 3, COASTAL_MORNING 4,
               TUNDRA_DAWN 5, MONSOON_HAZE 6, NIGHT_OPS 7, STUDIO_NEUTRAL 8 (QA only)   # art presets; NOT MapData.biome
MapBiome       TEMPERATE 0, DESERT 1, ARCTIC 2, TROPICAL 3                              # == terrain_movement.md MapData.biome (owned there, read only here)
MapFamily      OPEN 0, URBAN 1, COAST_RIVER 2                                           # == terrain_movement.md MapData.family
PlayerColorId  crimson 0, azure 1, emerald 2, amber 3, violet 4, cyan 5, orange 6, magenta 7, lime 8, slate 9, brown 10, white 11   # == net.md lobby ids
CvdMode        OFF 0, SAFE 1                                                            # one CVD-safe set covers protan, deutan and tritan (5.4.2)
FxTier         S0 0 (spark), S1 1, S2 2, S3 3, S4 4, S5 5 (strategic)
Relation       SELF 0, ALLY 1, ENEMY 2, NEUTRAL 3                                       # == combat.md REL_*
DamageType     BULLET 0, AP 1, HE 2, THERMAL 3, RAIL 4, KINETIC 5, EMP 6                # == TAXONOMY.md (authoritative)
CameraTier     NEAR 0, MID 1, FAR 2, MAX 3
```

### 4.2 Cards

`archetype(id)` → `Dictionary`
`{size_class: String, radius_cells: float, class_radius_cells: float, length_m: float, width_m: float, height_m: float, length_cells: float, width_cells: float, team_area_min_m2: float, altitude_m: float, soldiers: int, note: String}`

`structure(key)` → `Dictionary`
`{footprint_cells: [int, int], footprint_m: [float, float], body_h_m: float, landmark_h_m: float, note: String}`

### 4.3 `ViewMoodDef` (fields; superset of the terrain spike class, names kept)

```
var mood_name: String; var look_id: int
var sun_elevation_deg: float; var sun_azimuth_deg: float; var sun_color: Color; var sun_energy: float
var fill_color: Color; var fill_energy: float                    # camera-following fill, no shadows
var sky_top: Color; var sky_horizon: Color; var ground_horizon: Color; var ground_bottom: Color
var ambient_energy: float
var fog_color: Color; var fog_density: float; var fog_sun_scatter: float; var fog_aerial: float
var exposure: float; var white_point: float                      # tonemapper is Filmic (5.2.2)
var saturation: float; var contrast: float; var brightness: float
var glow_intensity: float; var glow_threshold: float; var ssao_intensity: float
var water_shallow: Color; var water_deep: Color; var water_absorb: float
var terrain: Dictionary                                          # grass_a/b, dry_a/b, dirt_a/b, rock_a/b, sand_a/b, snow, road, foliage_a/b (Colors)
var note: String
```

### 4.4 Vertex and instance-uniform contract this spec relies on (defined by render.md, verified in the models spike)

`COLOR` = paint rgb (sRGB) + `a` = team mask; `CUSTOM0.x` = `(ao4<<4)|(wear<<3)|Mat`; `Mat` PAINT 0, METAL 1, GLASS 2, RUBBER 3, EMISSIVE 4. Instance uniforms as defined by the render spec (render.md 4.3-4.4, ASSUMPTION(render)): `u_team` (rgb = **raw sRGB player colour written as a `Vector4`**, w = cloak level 0..1), `u_anim` (structures: sink depth m; move, roll_m, turret_yaw), `u_aux` (recoil, deploy / door / activity, spin angle, barrel elevation), `u_state` (damage, selected, flags, hit_flash). Part kinds 0-24 as in render.md 4.2 (0-15 spike-verified; 15 DEPLOY and 16 DEPLOY_Z are the hinge kinds this spec uses for folding wings, vanes, ramps and outriggers; 17-18 SLIDE_Y/Z are masts and gangways). This spec asks for one addition, **25 SWAY** (cloth, pennants, whips), request R-4.

### 4.5 Palette roles (the only way recipes may name a colour)

`primary`, `secondary`, `accent`, `dark`, `emissive`, `emissive_alt`, `metal`, `glass`, `rubber`, `light`, `team_key`. Recipes call `brush_role(&"accent", Mat.PAINT, team_mask)`; the builder resolves the role through the active `ViewPalette` (cache key includes `palette.id`, so a subfaction gets its own mesh variants only where accent geometry exists).

**Aliases for render.md 5.8.3 / 5.8.4** (its style palettes carry ten keys; `styles.json` `palette` blocks should be generated from `style.json`, tool `gen_recipe_styles.py`, not typed twice): `base` = `primary`, `sec` = `secondary`, `acc` = `accent`, `dark`, `metal`, `rubber`, `glass`, `light` are identical; `plate` (the dark border of `team_panel`) = `dark`; `concrete` = `neutral_palette.primary`. Three keys are new for render: `emissive`, `emissive_alt` and `team_key` (the neutral field paint of the team plate, always `#C6C6C6`).

### 4.6 VFX tier record

`fx_tier(t)` → `{tier: int, splash_m: [min, max], fireball_r_m: float, dur_s: float, smoke_s: float, light: [energy, range_m, time_s], shake: float, scorch_r_m: float, scorch_life_s: int, debris: int, examples: String}` (values in 5.13).

### 4.7 Emblem op record (JSON, unit square, y down)

`["poly", [x, y, ...], role, "fill"]`, `["poly", [...], role, "stroke", width]`, `["line", [x, y, ...], role, width]`, `["circle", cx, cy, r, role, "fill"]`, `["circle", cx, cy, r, role, "stroke", width]`, `["arc", cx, cy, r, a0_deg, a1_deg, role, width]`; `role` ∈ `c1` (faction emblem colour), `c2` (secondary), `dim` (c1 at 35 % alpha), `bg` (panel colour). Widths are fractions of the emblem size; renderers clamp to ≥ 1.5 px.


---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 The look

#### 5.1.1 Six pillars

1. **Read first, admire second.** At the RTS camera a player must recover *owner, faction, class, health and activity* of any object within half a second. Order of information: **silhouette > team plate > faction value/hue > accent > detail**. Detail exists to reward zooming in; it is never load-bearing for identification.
2. **One grammar, eight dialects.** Every model uses the same hard-surface grammar (real bevels, panel seams, chipped edges, greebles at 0.1-0.5 m) so that all 185 models sit in one world. Factions differ by *proportion, edge style, signature parts and palette*, not by rendering technique.
3. **Chunky, heroic, planted.** Vehicles are drawn at about 1:2.3 of real size with oversized turrets, guns, wheels and tracks; infantry is 1.25 m (about 1:1.45). Silhouettes have big, simple masses first and one or two memorable protrusions.
4. **Three-value discipline.** Each model owns a dark mass, a mid mass and a light mass in stable proportions (5.3.3). Accent colours occupy ≤ 8 % of the visible top-view area.
5. **Bright neutral owner plate.** The player colour lives only on dedicated plates (5.4). Faction paint never tries to be a team colour.
6. **Restraint with light.** Emissives ≤ 3 % of area, no bloom crutch, no full-screen flash; effects must be readable *on top of* units, not instead of them.

#### 5.1.2 Value and saturation targets (authored albedo; generated from `style.json`)

| Role | L* range across the 8 factions | C* range | Rule |
|---|---|---|---|
| primary | 31-85 (dark-mid factions 31-56; light factions OLM 85, SAP 74) | 11-43 | Never above C* 45: hulls are quieter than accents and than team plates (C* 60-100). |
| secondary | 33-96 | 1-54 | Trim, skirts, caps. Must differ from primary by ΔE00 ≥ 25 (all factions: 28-58). |
| accent | 40-85 | 39-81 | ≤ 8 % of visible area; the only saturated colour on the hull. |
| dark | 18-29 | 2-49 | Undercarriage, tracks, panel recesses; ≥ 12 % of visible area on every model. |
| metal | 22-33 | 1-7 | Weapons and tools; roughness 0.36-0.6, metallic 0.9 (shader). |
| glass | 16-25 | 7-31 | Cabin and lens glass; faint emission 12 % of paint. |
| rubber | 5-7 | 0 | Tyres, tracks, seals. |
| light | 92-99 | 3-38 | Head-lamps (emissive). |
| terrain (all looks) | 22-97 (road darkest, snow lightest) | ≤ 57 (grass), ≤ 54 otherwise (foliage tops the rest) | Ground is always less saturated than a team plate (C* 60-100). |

**Contrast targets.** Adjacent masses differ by ≥ 12 L*; the team field is ≥ 25 ΔE00 from anything within 0.15 m (guaranteed by the plate anatomy, 5.4.3); primary vs lit ground ΔE00 ≥ 12 in day looks *or* the model meets the dark-mass rule (see the known-risk table in 5.14.5).

#### 5.1.3 Materials and wear (shader classes from the spike, faction-tuned)

Five classes only: PAINT (rough 0.5-0.68, metallic 0.04), METAL, GLASS, RUBBER, EMISSIVE. Wear and dirt are *per-faction material styles* (`ViewPalette.material_style()`, table in 5.3.2): DEF and AE weather heavily, NEC/HAN/PD stay clean. Edge chipping only on edges flagged `wear`. Panel seams use the faction panel module (`panel_m`) and fade with distance (shader). No image textures, no tiling noise that reads as texture at FAR.

#### 5.1.4 Scale exaggeration and proportion language

* Vehicle length is the reference: tank hull 3.5 m; gun barrel 0.5-0.75 × hull length; turret ring ≥ 0.40 × hull width. Wheels/road wheels are 15-25 % oversized.
* Infantry `model_scale = 1.25` on the 1.0 m soldier: a soldier is 1.25 m, squad footprint 1.9 × 1.7 m (0.63 × 0.57 cells).
* Ratios that *carry faction identity* (hull W/L and H/L) are listed per faction in 5.5.

#### 5.1.5 Detail budget by distance

| Camera tier (5.8.1) | px per metre across the view | What must read | What may exist |
|---|---|---|---|
| MAX (H 84 m) | 16 | class blob, team plate, faction hue/value, landmark tips | nothing finer than 0.55 m |
| FAR (H 65 m) | 20 | + accent stripes, barrel direction, wheels vs tracks, structure roof gear | features ≥ 0.40 m |
| MID (H 43 m) | 27 | + panel seams, kit parts, insignia glyph blobs | features ≥ 0.30 m load-bearing; 0.10 m decoration |
| NEAR (H 34 m) | 33 | + latches, bolts, stencils, emblem shape | 0.08 m detail |

### 5.2 The colour pipeline contract (what the player sees vs what is authored)

#### 5.2.1 Defect found in the spike: `Color` instance uniforms are linearised twice — **must be fixed**

**Observation (MEASURED).** `GeometryInstance3D.set_instance_shader_parameter(&"u_team", <Color>)` converts an sRGB `Color` to *linear* before upload, even for a `vec4` uniform without `source_color`. The spike shader then applied `pow(x, 2.2)` again (`v_team = to_lin(team)`). Probe (flat team plate, emission only, Linear tonemapper, no lights, no post): authored `#2C86F0` rendered `#063CE0`; passing a `Vector4` rendered `#2988F1`. With the full spike pipeline (Filmic, sun 1.9, fill 0.45, 8 players × 8 faction tanks): mean authored→rendered ΔE00 **14.5** (max 22.7), hue errors up to 21° (azure → violet-blue, orange → red, crimson and orange 5.6 ΔE apart). After the fix: mean **5.4**, max **8.8**, azure -16° being the worst hue error. This is engine behaviour measured in Godot 4.7.2, not a project-file bug, and it applies only to **instance** uniforms. The peer spec `render.md` 4.4 states the opposite ("values are not sRGB-converted by the engine"), which is wrong for Godot 4.7.2 as measured here; the batch backend's plain material uniform (`mm_team`, no `source_color` hint) is not affected.

**Required fix (one of):**
```gdscript
# A (preferred, no shader change): send raw sRGB as a Vector4.
rig.set_instance_shader_parameter(&"u_team", style.team_uniform(color_id, cvd, cloak))   # Vector4(r, g, b, cloak)
# B: keep Color but declare the uniform  "instance uniform vec4 u_team : source_color"  and DELETE  v_team = to_lin(team)  from unit.gdshader.
```
In the render spec's classes this means: `ViewModelRig.setup(m, mat, team)`, `ViewUnitBackend.add(...)` / `set_team(...)` and the node backend's `P_TEAM` write must convert `Color` to `Vector4(c.r, c.g, c.b, cloak)` at the write site (request R-1). Acceptance: test V1 (10.3): the swatch probe renders `#2C86F0` as `#2988F1` within 3 levels per channel, and a deliberate `Color` build must fail it.

#### 5.2.2 Tonemapper, grade and reference lighting

* **Tonemapper = Filmic** (`Environment.TONE_MAPPER_FILMIC`), `tonemap_white` 4.5-6.0. MEASURED plate fidelity, 8 players × 8 factions, Vector4 path, key-paint plate (shader factor 0.909, 5.4.3), no team glow:

| Tonemapper | mean ΔE00 authored→rendered | max | worst hue shifts (deg) | rendered min pairwise ΔE00 (default set) |
|---|---:|---:|---|---:|
| **Filmic** | **5.4** | **8.8** | azure -16, magenta -9, amber +9, orange +8 | **17.4** |
| ACES | 8.7 | 11.2 | azure -15, orange +12, amber +9 | 17.2 |
| AgX | 7.9 | 11.9 | azure -17, violet -6 | 17.1 |
| Filmic + 0.3 team glow | 6.6 | 9.8 | azure -22 | 16.8 |

  Decision: Filmic, **no team glow** (adding it made fidelity worse). If the render domain keeps ACES (render.md 5.6 says ACES), or changes the tonemapper for any other reason, palette hexes must be re-verified with the harness (10.3) before merge.
* **Grade limits:** saturation ≤ 1.12, contrast ≤ 1.10, brightness 1.0; no per-look hue rotation.
* **Reference lighting `studio_neutral`** (look id 8): white sun 1.45 at elevation 48°/azimuth 300°, white fill 0.30, neutral ambient 0.85, no fog, no grade. All palette and plate measurements in this document and in the QA checklist are taken under it. Game looks then shift colours by the amounts in 5.14.4.
* **Authored vs rendered (MEASURED, `studio_neutral`, Filmic):** a primary's rendered mid-tone is 0..+14 L* brighter than the authored hex (NAPC +12, NEC +12, HAN +14, AE +10, DEF +6, OLM 0) with hue drift ≤ 5° and ΔE00 4-13. Design palettes at the authored value; judge them in renders. The larger hue shifts (NAPC olive +21° toward yellow-green under `temperate_day`, DEF -17° toward brick) come from the look's lighting, table in 5.14.4.

#### 5.2.3 Palette-driven meshes

Models are built with **palette roles** (`brush_role`), never hex. The model cache key is `(recipe_id, style_id, scale)` (render.md 5.8.1; the style id is the palette id without its `palette.` prefix). Vanilla and the three subfactions of a faction therefore share meshes for everything that does not use the accent role, *provided the builder emits accent geometry as a separate index range*; if it cannot, each subfaction in a match builds its own variants (cost: ≤ 8 rosters × ~40 models × ~6 ms = 1.9 s worst case, hidden by the loading screen and cached on disk in `user://cache/models/`).

#### 5.2.4 Emissive language (all factions)

* Head-lamps: `light` role, warm white, front only, 0.20 × 0.09 m pairs. Tail-lights: `#FF1A0A` (HDR 2.0), rear corners, 0.16 × 0.07 m. These two rules make *facing* readable on every unit.
* Weapon / sensor glow: faction `emissive` (5.3.1). Status lamps: `emissive_alt`. Blinkers (`BLINK` part) 0.9 Hz.
* Budget: emissive pixels ≤ 3 % of a model's visible area; HDR ≤ 3.0 on units (glow threshold 1.0-1.2 in the day moods, 0.85 in `night_ops`), ≤ 6 on effects.
* Powered-off structures: emissives to 0 in 0.4 s (`EVT_POWER_SHORTAGE` and the structure's `F_POWERED` bit), desaturate 25 %.

### 5.3 Faction palettes

#### 5.3.1 Authored palettes (sRGB hex; full set incl. `metal`, `glass`, ... in `style.json → palettes`)

| Faction | primary | secondary | accent | dark | emissive | primary in Lab |
|---|---|---|---|---|---|---|
| NAPC | `#465229` | `#DBCFA6` | `#F0621A` | `#262E19` | `#FFB55A` | L33 C26 h119 |
| NEC | `#4A5D7C` | `#E9EEF3` | `#F5A623` | `#232D40` | `#FFC24A` | L39 C20 h274 |
| OLM | `#DAD5C0` | `#1F7F80` | `#C77A3A` | `#0F4B4E` | `#FFC060` | L85 C11 h100 |
| DEF | `#7C3325` | `#6E7175` | `#E4D48A` | `#2F3134` | `#FFE9A0` | L31 C39 h38 |
| PD | `#1791BE` | `#F1F4F6` | `#FF6F5B` | `#0F3A63` | `#CFF6FF` | L56 C35 h245 |
| HAN | `#2D8862` | `#ECE7D9` | `#B81F2E` | `#16483A` | `#7CFFC8` | L51 C38 h161 |
| AE | `#8F6524` | `#4B4E53` | `#12D6F2` | `#2B2D30` | `#3DE7FF` | L46 C43 h76 |
| SAP | `#CDB37A` | `#4B50A8` | `#F4A521` | `#2F3480` | `#FFB428` | L74 C33 h87 |

Role semantics per faction (what each colour *is*):

| Faction | primary | secondary | accent | dark | emissive / emissive_alt |
|---|---|---|---|---|---|
| NAPC | olive drab hull | cream modular tiles, cabin frames | rescue orange: hooks, beacons, chevrons, rotor tips | forest-black undercarriage | warm amber lamps / orange strobes |
| NEC | slate blue hull | white roof panels, mast heads | amber pinstripes, sensor slits | navy under-hull | amber sensor glow / cool-white status |
| OLM | ivory panels | mid-teal fabric screens | copper heat shields, pipes | deep teal lower hull | gold thermal lens / teal status lamps |
| DEF | oxide-red slabs | grey running gear, slab plates | pale yellow stencils, containers, hazard bands | graphite | pale-yellow lamps / hazard amber |
| PD | cerulean-ocean hull | white superstructure, caps, floats | coral waterline band, drone pads, hinge lines | navy | ice-white lamps / coral strobes |
| HAN | jade modules | porcelain caps, racks | crimson lines, lanterns | deep green | jade-white sensor glow / crimson dots |
| AE | ochre panels | charcoal panels | bright cyan lock collars, work lights | near-black charcoal | cyan / hazard amber |
| SAP | sand plates | indigo layers | saffron rims, feet, pennants | deep indigo | saffron sensor glow / lilac interception light |

| Faction | emissive_alt | metal | glass | rubber | light (head-lamp) | area mix % (primary / secondary / dark / accent / team) |
|---|---|---|---|---|---|---|
| NAPC | `#FF7A1A` | `#4A4F4B` | `#22404A` | `#151515` | `#FFE6B0` | 52 / 16 / 20 / 5 / 7 |
| NEC | `#DFF3FF` | `#30343B` | `#1B3A52` | `#151515` | `#FFE9B0` | 50 / 14 / 24 / 4 / 8 |
| OLM | `#37E0C8` | `#3E4245` | `#123B3F` | `#151515` | `#FFF0C8` | 42 / 22 / 18 / 10 / 8 |
| DEF | `#FFB020` | `#3A3B3D` | `#2A3A3C` | `#121212` | `#FFE9A0` | 44 / 24 / 18 / 6 / 8 |
| PD | `#FF6F5B` | `#3E4548` | `#173A56` | `#151515` | `#F4FBFF` | 46 / 26 / 12 / 8 / 8 |
| HAN | `#FF3B4A` | `#3A403E` | `#153B38` | `#151515` | `#F2FFF6` | 50 / 20 / 14 / 8 / 8 |
| AE | `#FFB020` | `#34373A` | `#12363E` | `#101010` | `#FFF0C0` | 44 / 22 / 18 / 8 / 8 |
| SAP | `#B8B4FF` | `#3C3E48` | `#1B2350` | `#141414` | `#FFF2CC` | 34 / 30 / 18 / 10 / 8 |

#### 5.3.2 Per-faction material and edge style (`ViewPalette.material_style()`, panel grammar)

| Faction | wear | dirt | panel | wear_color | dirt_color | emissive | panel module | bevel | greebles / m2 | edge style |
|---|---|---|---|---|---|---|---|---|---|---|
| NAPC | 0.45 | 0.45 | 0.65 | `#C9C3A8` | `#3A3020` | 2.5 | 0.90 m | 0.045 m | 0.35 | 45deg-medium |
| NEC | 0.25 | 0.2 | 0.8 | `#D6DCE4` | `#2C3038` | 2.5 | 0.60 m | 0.030 m | 0.15 | 30deg-sharp |
| OLM | 0.3 | 0.35 | 0.55 | `#EDE6D2` | `#8A7A5C` | 2.5 | 0.80 m | 0.050 m | 0.25 | rounded |
| DEF | 0.7 | 0.65 | 0.5 | `#B8ADA0` | `#3B2A20` | 2.2 | 1.30 m | 0.020 m | 0.3 | hard-weld |
| PD | 0.3 | 0.2 | 0.6 | `#E4EEF4` | `#2C3A44` | 2.5 | 1.10 m | 0.060 m | 0.15 | rounded-long |
| HAN | 0.25 | 0.2 | 0.9 | `#EFEBDD` | `#24322C` | 2.6 | 0.50 m | 0.040 m | 0.2 | rounded-module |
| AE | 0.6 | 0.6 | 0.75 | `#C8B48A` | `#3A2C1A` | 2.8 | 0.70 m | 0.035 m | 0.45 | patchwork |
| SAP | 0.45 | 0.5 | 0.7 | `#E6DCC0` | `#4A3F2C` | 2.6 | 0.80 m | 0.040 m | 0.3 | stepped |

#### 5.3.3 The three-value rule and area budgets

For every model, measured on the visible top-view silhouette at MID under `studio_neutral`:

* **dark mass** (L* ≤ 30) ≥ 12 % of area (tracks, undercarriage, weapons, panel recesses, weapon glass); **light mass** (L* ≥ 75) ≥ 8 % (trims, caps, markings); the remainder mid values.
* Area mix targets (percent of visible area): primary / secondary / dark / accent / team = the last column of the table above (for example NAPC 52 / 16 / 20 / 5 / 7). Tolerance ±6 points for primary/secondary/dark, accent ≤ 8, team 5-12 (5.4.3).
* **Light-hull factions (OLM, SAP) must carry ≥ 25 % dark area** (teal under-hull and screens, indigo layers): the ivory OLM hull is only ΔE00 6.0 from tundra snow in the lit sample (MEASURED, 5.14.5) and the sand SAP hull lives in the same lightness band as desert ground, so the dark mass carries the read.
* At most **three hues** per model beyond neutrals and the plate: primary, secondary, accent.

#### 5.3.4 Neutral / civilian / resource props

`neutral_palette` in `style.json`: civic concrete `#8A8E90`, light concrete `#C9CCCF`, civic blue `#2E6AA8` (signage, substations), dark `#4A4C50`, warm lamps `#FFE9B0`, roofs terracotta `#8F5A48` / slate `#4A4F57`. Salvage deposits and depots: gunmetal `#6C7784`, rust `#8C4E2F`, glint sprites `#FFE9A8` (richness = pile count 1-4, never colour). Neutral objects have **no team plate and no faction accent**; a captured structure keeps its neutral shell but gains a roof plate and pennant in the new owner's colour (`OWNER_CHANGED`).

### 5.4 Player colours and the team-colour system

#### 5.4.1 The sets

Chosen by simulated annealing over CIEDE2000 with Machado-2009 colour-vision-deficiency simulation (protan, deutan, tritan at severity 1.0), constrained to eight named hue families and chroma floors; the CVD set additionally keeps ΔE00 ≥ 14 from every faction primary. Ids and keys are the lobby ids of `docs/spec/net.md`.

| id | key | default hex | default Lab | CVD-safe hex | CVD Lab |
|---|---|---|---|---|---|
| 0 | crimson | `#D8323B` | L49 C73 h29 | `#CE251A` | L45 C80 h38 |
| 1 | azure | `#2C86F0` | L56 C62 h281 | `#6D99FA` | L64 C55 h284 |
| 2 | emerald | `#2FAE5E` | L63 C61 h149 | `#86C280` | L73 C42 h140 |
| 3 | amber | `#F5C13A` | L81 C71 h85 | `#E4CD19` | L82 C80 h96 |
| 4 | violet | `#7250D8` | L45 C80 h306 | `#7957CD` | L46 C70 h306 |
| 5 | cyan | `#25CDE0` | L76 C39 h212 | `#3CE0EA` | L82 C41 h204 |
| 6 | orange | `#F47B2A` | L65 C74 h56 | `#E9711E` | L61 C75 h56 |
| 7 | magenta | `#E0489F` | L55 C68 h347 | `#9E3773` | L40 C50 h346 |
| 8 | lime | `#9BD13B` | L78 C76 h121 | (not offered) | - |
| 9 | slate | `#8A97A8` | L62 C11 h265 | (not offered) | - |
| 10 | brown | `#8C5A3B` | L43 C31 h57 | (not offered) | - |
| 11 | white | `#ECECEC` | L93 C0 h158 | (not offered) | - |

| Set | authored min ΔE00 normal / protan / deutan / tritan | MEASURED rendered min ΔE00 (Filmic, plates) | authored→rendered mean / max |
|---|---|---|---|
| default (ids 0-7) | 22.6 / 8.5 / 9.0 / 8.7 | 17.4 / 6.9 / 6.2 / 8.0 | 5.4 / 8.8 |
| CVD-safe (ids 0-7) | 20.8 / 14.5 / 13.8 / 13.5 | 17.3 / 12.6 / 9.9 / 10.0 | 5.4 / 7.1 |

Rendered plate colours (expected pixel values under `studio_neutral`-like lighting, for QA): default `#CF3A49 #3A8FD0 #3FB273 #D8BF4D #8560CC #33C2CF #CC8342 #C955A7`; CVD `#CA2F2E #7E9CD1 #95B990 #D2C533 #8B67C6 #48C9D1 #C97A3B #A94687`.

Recommended slot assignment (`assign_order`): slot 0 → azure (1), 1 → crimson (0), 2 → emerald, 3 → amber, 4 → violet, 5 → cyan, 6 → orange, 7 → magenta. The first two seats are the most distinct pair (ΔE00 46). Ids 8-11 (lime, slate, brown, white) are optional lobby extras; they are not guaranteed distinct from ids 0-7 and are hidden when the CVD set is active.

#### 5.4.2 Colour-vision deficiency

* One CVD-safe set (`accessibility.cvd_palette = true`) is designed to work for protan, deutan and tritan simultaneously (min ΔE00 13.5+ authored under all three simulations) — no per-type modes.
* Colour is never the only cue. Always-on redundancy: (1) roster strip and lobby show the **player number 1-8** next to each swatch; (2) minimap blips use class shapes (dot infantry, square vehicle, diamond air, triangle naval, outlined square structure); (3) selection rings and brackets differ in pattern by relation (5.12.5); (4) hover tooltips name the owner; (5) a **shape pip per player index** (circle, triangle, square, diamond, cross, hexagon, star, bar; ids 8-15 repeat with an outline, render.md 5.12) at the left end of health bars and at the north point of selection rings.
* The default set is *not* CVD-safe (rendered min ΔE00 6.2 under deutan); the lobby shows a one-line hint offering the CVD set when the player's OS or profile reports it or on demand from Options → Accessibility.

#### 5.4.3 Plate anatomy — the fix for hull/team clashes (MEASURED)

**Problem.** A plain painted team patch disappears when hull and team hue coincide (measured authored ΔE00 between team colour and hull primary: PD × azure 12, HAN × emerald 14, SAP × amber 13, AE × brown 11, OLM × white 10; earlier spike palettes: 7 for PD × azure).

**Solution: three-layer plate, identical on every faction.** Geometry (metres, all boxes `default_bevel 0`):

| Layer | Extent beyond the field | Paint | Mask | Height above surface |
|---|---|---|---|---|
| gasket | outer edge +0.08 m beyond the field (0.04 m visible band) | palette `dark` | 0 | +0.009 |
| hairline | outer edge +0.04 m beyond the field (0.04 m visible band) | `#E6E6E6` | 0 | +0.013 |
| **field** | 0 | `team_key` `#C6C6C6` | **1.0** | +0.027 |

(Structure plates use the same layers scaled by 1.4: 0.055 m bands.)

The field is painted with the **neutral key**, never with faction paint: the shader computes `albedo = team × (0.40 + 0.9 × luma(paint))`, so key paint (linear luma 0.565) yields factor 0.909 on every faction and the rendered colour tracks the authored one (5.2.1). Because the field is bounded by a light hairline and a dark gasket, it reads against any hull, on any ground. Verified by eye on the worst pairs (NEC × azure, PD × azure, SAP × amber, AE × amber) on the 8-faction family board (27 m) and on the 8 × 8 matrix at 60 m and 84 m.

**Size and count rules.**
* Field minimum dimension **0.45 m** (7 px at MAX, 12 px at MID); aspect between 1:1 and 1:2.2.
* Team-coloured share of the **plan-view silhouette** (top-down, occlusion aware, barrels and gear included) = **5-12 %**. MEASURED on the eight proof tanks: 5.1-10.7 % (mean 7.5 %; NEC 5.1, PD 5.7, OLM 6.5, HAN 6.7, NAPC 7.9, SAP 8.4, AE 9.0, DEF 10.7), all readable at MAX. `team_area_min_m2` in 5.7 is the *designed* field area, i.e. the sum of all fields of the placement table below including vertical extras (skirt stripes, pennants), of which 45-100 % is visible from above. (The peer spec `render.md` 5.8.2 asks for 4-12 % masked top-projected area; 5-12 % satisfies both.)
* Two plates per ground vehicle at least (turret roof + hull front/deck) so one stays visible when the turret points away; aircraft: dorsal fuselage + both wing tops; ships: main hatch/forecastle + bridge roof; structures: roof plate of at least 1.0 m² and 2.5 % of the footprint (the larger applies) + pennant + front pad strip.
* **Quiet zone:** no accent-role geometry, emissive or contrasting greeble within 0.15 m of a plate; a roof gadget must cover ≤ 30 % of any plate (the HAN sensor crown in the proof covered the plate centre — a defect the QA check "plate visible ≥ 70 %" catches).
* No team glow, no gradient, no decal on the field.

**Placement table** (top-view surfaces first; positions relative to the hull)

| Archetype family | Plate 1 (field size, m) | Plate 2 | Extras |
|---|---|---|---|
| Infantry (per soldier) | vest/backpack panel 0.22 × 0.28 | helmet band 0.20 × 0.05 | none |
| Scout / APC / collector | roof 0.50 × 0.90 | hood or front deck 0.50 × 0.25 | antenna pennant 0.35 × 0.22 |
| Tanks T1/T2 | turret roof 0.55 × 1.00 | front deck 0.90 × 0.34 | skirt-cap stripe 0.12 × 1.2 |
| Heavy / siege / walker | turret or body roof 0.80 × 1.30 | front deck 1.10 × 0.45 | pennant on command walkers |
| Artillery | casemate roof 0.60 × 0.80 | rear deck 0.60 × 0.30 | — |
| AA vehicles | turret roof 0.50 × 0.70 | hull deck 0.70 × 0.30 | — |
| Fighters / drones | dorsal 0.45 × 1.10 | wing tops 0.30 × 0.60 each | fin flag |
| Gunships / bombers | dorsal 0.50 × 1.20 | wing/tail patches | — |
| Ships | main deck hatch 0.90 × 1.40 | bridge roof 0.60 × 0.60 | funnel band |
| Structures | roof plate ≥ 1.0 m² and ≥ 2.5 % of the footprint | front pad strip 0.35 m deep | pennant 0.56 × 0.36 on a 2.0 m mast (HQ, barracks, factory, dock, airfield, radar, laboratory) |

#### 5.4.4 Combining team colour with the faction palette — rules

1. Player colour appears **only** through mask > 0 geometry. Faction paint never uses a hue within 25° of a player colour at chroma > 50, except the faction's own accent (thin trim, ≤ 8 %).
2. Lobby hint: `ViewStyle.plate_contrast(faction, color_id, cvd) < 20` shows "low contrast on your faction — try X" (best free colour by ΔE). Authored low-contrast pairs (ΔE00 < 20):

| faction | default set: colours with authored dE00 < 20 to the faction primary | CVD set |
|---|---|---|
| NAPC | - | - |
| NEC | violet 15 | violet 15 |
| OLM | white 10 | - |
| DEF | crimson 19, brown 13 | crimson 16 |
| PD | azure 12, cyan 20, slate 16 | azure 16 |
| HAN | emerald 14 | - |
| AE | brown 11 | - |
| SAP | amber 13 | amber 15 |

3. Wrecks: team plates go neutral grey `#3A3A3A`, paint desaturates 60 %, `damage = 1.0`.
4. Selected units: the rim light (shader) and the ground ring or brackets use relation colours (5.12.5), never the player colour.
5. Team colour is per instance; **never** bake it into a mesh, an icon atlas shared between players, or a material.


### 5.5 Shape language per faction

#### 5.5.0 The shared grammar (all factions)

* **Axes.** Model space +X right, +Y up, −Z forward, metres, origin on the ground at the footprint centre. Front = −Z. Everything symmetric about X=0 except ≤ 15 % of greebles and one deliberate asymmetric feature (an antenna, a stowage box) per model.
* **Edges.** Every solid is bevelled (real geometry, 0.02-0.06 m by faction, `bevel_m`). No sharp 90° silhouette corners on anything larger than 0.5 m.
* **Panels.** Large flat faces > 1 m² are broken by a panel seam grid at the faction `panel_m` module, `pocket_box` recesses (0.03-0.05 m deep), or a contrasting insert. Never a single flat colour slab > 2 m² (checklist item F-7).
* **Greebles.** Density per faction (`greeble_per_m2`), placed with seeded RNG on top surfaces; tier 1 (LOD1 and below dropped). Sizes 0.10-0.45 m; taller than 0.45 m only if it is a named signature part.
* **Mass ordering.** Lowest and widest = dark undercarriage; hull = primary; turret/casemate = primary with the faction's turret shape; roof gadgets = secondary/metal; accent = pin-stripes, hooks, lenses, feet.
* **Running gear.** Tracked: belt + 4-8 road wheels, `TRACK` part scrolls with roll distance. Wheeled: wheel radius ≥ 0.30 m, `WHEEL` part. Walkers: `LEG_A/B`.
* **Parametric kit approach (proven in the spike and extended).** One recipe function per archetype family reads a **style dictionary** per faction; the faction identity lives in the dictionary and in ≤ 3 signature parts, so 8 factions × ~20 archetypes do not need 160 hand-modelled meshes. The medium-tank dictionaries below were rendered in the proof harness (they produced the family and matrix boards) and are the reference; where a faction card below lists a signature part that the proof did not model (OLM raised clearance and swaying cloth, PD fold hinges, SAP deploy pose), the card is normative and the proof is a subset:

| faction | len | hull_w | hull_top | glacis | track_w | wheel_n | wheel_r | skirt | turret_n | turret_hw | turret_hl | turret_h | turret_top | barrel_len | muzzle | roof | deck |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NAPC | 3.5 | 1.92 | 1.16 | 0.75 | 0.46 | 5 | 0.3 | modules | 8 | 0.74 | 0.96 | 0.42 | 0.72 | 2.0 | brake | cupola | none |
| NEC | 3.8 | 1.8 | 0.98 | 1.25 | 0.4 | 6 | 0.25 | slab | 6 | 0.62 | 1.15 | 0.3 | 0.55 | 2.7 | plain | mast | none |
| OLM | 3.7 | 1.7 | 1.04 | 0.95 | 0.3 | 5 | 0.34 | fabric | 10 | 0.66 | 0.8 | 0.36 | 0.72 | 2.2 | sleeve | dish | heat_shield |
| DEF | 3.4 | 2.06 | 1.24 | 0.4 | 0.5 | 6 | 0.34 | none | 4 | 0.86 | 0.86 | 0.52 | 0.9 | 1.85 | brake | cupola | container |
| PD | 3.6 | 1.94 | 1.06 | 1.1 | 0.34 | 5 | 0.27 | float | 12 | 0.66 | 0.72 | 0.34 | 0.74 | 1.9 | sleeve | snorkel | drone_pad |
| HAN | 3.0 | 1.72 | 1.06 | 0.85 | 0.4 | 4 | 0.27 | modules | 12 | 0.7 | 0.7 | 0.36 | 0.78 | 1.75 | sleeve | crown | drone_rack |
| AE | 3.5 | 2.0 | 1.12 | 0.6 | 0.46 | 5 | 0.36 | patches | 6 | 0.8 | 0.86 | 0.44 | 0.8 | 2.0 | plain | rails | spares |
| SAP | 3.5 | 2.06 | 1.2 | 0.35 | 0.48 | 5 | 0.3 | layered | 8 | 0.8 | 0.92 | 0.46 | 0.76 | 1.9 | brake | sensors | braces |

Enumerated feature values: `skirt` ∈ {modules, slab, none, fabric, float, layered, patches}; `roof` ∈ {cupola, mast, crown, dish, snorkel, rails, sensors}; `deck` ∈ {none, container, drone_rack, heat_shield, drone_pad, spares, braces}; `muzzle` ∈ {brake, plain, sleeve}; OLM `wheels=bogie` (swing-arm road wheels), AE `wheels=heavy` (steel-ringed), PD `bow=true` (boat prow profile), SAP `layers=true` + hull in `secondary` with `primary` turret/appliqué. Full dictionaries: `style.json → style_kits.tank_medium`.

* **Silhouette distinctness is checked two ways:** by eye on the family board (a desaturated screenshot must still let a reviewer tell the 8 tanks apart from the roof gadget, skirt style and deck kit) and numerically as a *copy-paste guard*: pairwise filled-mask IoU between factions for the same archetype must stay ≤ 0.95. MEASURED baseline for the proof set (transparent-background masks at MID, centroid aligned): tanks 0.73-0.94 (max NAPC/AE 0.94), 2×2 generators 0.66-0.92. Same-class silhouettes are *supposed* to be similar (a tank must read as a tank); faction identity is carried by palette, the signature parts and the interior structure, not by the outline alone.

#### 5.5.1 NAPC — "rescue-industrial"

*Bible:* olive, cream and rescue orange; broad hulls, modular armor, visible crew cabins. *Lore hook:* evacuation commands turned army; equipment looks like it can carry, repair and recover.

* **Silhouette.** Broad and upright: hull W/L 0.55, H/L 0.33, 45° glacis (0.75 m), large octagonal turret (rot 22.5°) with a rear bustle; an antenna whip. The "NAPC cadence": lower hull olive, side skirt made of 6 modular tiles alternating olive/cream, capped by a 0.04 m orange rail.
* **Panel/greeble vocabulary.** 0.90 m tiles, 45° medium chamfers, bolt rows on tile edges, stowage boxes, jerry cans, tow cable coils, recovery hooks. Wear 0.45 (chipped paint on edges, cream tiles show olive scuffs), dirt 0.45.
* **Signature (must appear on every vehicle ≥ light):** (1) **visible crew cabin** — glazed area ≥ 0.5 m² on APCs, trucks, gunships, ships; commander cupola with a cream hatch ring on tanks; (2) **orange recovery hook / tow eye** on the front; (3) **cream tile skirts**; (4) beacon bar (orange BLINK) on cabs and superstructures; (5) hazard chevrons (orange/black) on rear panels and structure aprons.
* **Motion feel.** Heavy and planted: slow ease-in on acceleration, brake dip 1.0°, long recoil settle (0.30 s).
* **Structure dialect.** Broad low-rise depots: cream upper walls over olive modular tiles, flat roofs with equipment rows, roll-up doors, orange safety rails, chevron aprons, an orange beacon on the tallest point, sandbag-free.
* **Never:** orange as a large area (> 8 %), rounded organic forms, exposed drone hardware.

| Archetype | NAPC adaptation |
|---|---|
| Rifle Squad / Javelin / Medic | olive kit, cream round helmets with an orange strap; leader has a whip radio pack. Javelin: 0.9 m olive tube on the shoulder. Medic: cream vest and big cream backpack with an orange bar — no cross symbol. |
| Pathfinder APC | 6-wheel, bubble cab with ≥ 0.5 m² glass, roof spinner, orange beacon, front tow eye. |
| Guardian / Bastion | kit dictionary; Bastion = 5.0 m hull, twin-barrel turret 1.25× wide, 8 skirt tiles per side, two cupolas. |
| Sentinel AA | Guardian chassis; roof quad-pod missile box (olive, orange caps) + cream rear radar spinner. |
| Paladin Howitzer | rear casemate (45° slopes), 3.4 m barrel raising to 55°, two orange-edged spades that swing down (DEPLOY). |
| Falcon / Titan | Falcon: slim twin-tail fighter, olive over cream belly, orange tail stripe. Titan: armoured hovering gunship with visible two-seat glazed cab, twin engine pods, orange rotor tips, chin cannon. |
| Riverwatch / Aegis / Liberty | open-deck patrol boat with bubble cab + 2 orange life-raft canisters; frigate with raked bow, glazed bridge, cream mast, orange helipad ring; arsenal ship = broad barge hull, 2 fore turrets, aft box launcher, orange deck-edge hazard. |
| Engineer / Collector / MCV / Landing Transport | olive coveralls + orange hard-hats; hopper truck with orange scoop teeth; cab + folded cream HQ crate with orange corner posts; flat-deck LCAC with orange skirt and bow ramp. |

#### 5.5.2 NEC — "precision instrumentation"

*Bible:* slate blue, white and amber; low profiles, angular turrets, fold-out sensor masts. *Lore hook:* a treaty of city leagues; standards documents you can see.

* **Silhouette.** Long, low wedge: hull L 3.8, W/L 0.47, H/L 0.26, very shallow glacis (1.25 m). Hexagonal low turret set forward (turret_z +0.42, rot 30°), thin 2.7 m gun, single **fold-out mast** with an amber head (RADAR part). Slab skirts with an amber pin-stripe.
* **Vocabulary.** 0.60 m fine seam grid, 30° sharp chamfers, recessed slots hiding amber slits, symmetric sensor pods (domes/cones 0.15-0.25 m). Clean: wear 0.25, dirt 0.20, greebles 0.15/m².
* **Signature:** (1) fold-out sensor mast (stowed 1.0 m, deployed 3-7 m in 1.2 s); (2) amber **slit lights** on the glacis and turret; (3) white roof panels with a thin amber border; (4) faceted diamond cut-outs; (5) data-line stripes (two 0.03 m lines).
* **Motion feel.** Precise: quick aim (turret 100°/s) with no overshoot, masts unfold with a soft click.
* **Structure dialect.** Horizontally stretched halls with sloped roofs, white roof panels, amber strip windows, tall thin masts and relay pylons.
* **Never:** boxy slab armour, hazard chevrons, more than one fold-out array per unit.

| Archetype | NEC adaptation |
|---|---|
| Jäger / Spike / Sapper | white helmets with amber visors, slim rifles, chest puck (amber dot). Spike: 1.2 m optical launcher on a bipod. Sapper: tool rack, folding spade. |
| Surveyor APC | low 6-wheel wedge, two roof masts (one stowed), amber slits, white roof. |
| Leopard / Argent Rail | kit dictionary; Argent: 4.0 m rail on a flat wedge hull, amber tip, white capacitor rings. |
| Rapier AA | low hull, rotating flat white array 1.4 m + two long missile pods; amber slit. |
| Archer SPG | low forward turret, 3.0 m thin barrel with white sleeve, rear spades. |
| Kestrel / Aster EW | sharp delta with canards, slate upper, white nose radome, amber wingtip lights; Aster = wide aircraft with a flat dorsal array 2.2 × 1.2 m, amber pulses, no weapons. |
| Skerry / Horizon / Concord | needle patrol hull; faceted angular escort with fold-out array and white VLS panels; low flat monitor barge with a long forward turret. |
| Engineer / Collector / MCV / Landing | slate coveralls with an amber helmet stripe; low articulated hopper; wedge carrier with HQ mast folded; white landing hull with an amber deck stripe. |

#### 5.5.3 OLM — "solar caravan"

*Bible:* ivory, copper and deep teal; heat shields, fabric screens and articulated wheels. *Lore hook:* water and power convoys; light, quick, sun-shaded.

* **Silhouette.** Light and leggy: raised ground clearance (+0.15 m), long wheelbase, large **ivory** panels over a dark-teal underbody; **fabric screens** (teal cloth, zig-zag hem 0.12 m, hung from copper rails) on flanks and turret cheeks break the outline; **heat shields**: three raised copper louvre plates over the rear deck; road wheels ≥ 0.34 m on **swing arms** (visible articulation) even on tracked tanks; low gun with a copper heat sleeve.
* **Vocabulary.** 0.80 m soft panels, rounded bevels 0.05, louvre pockets, copper piping along the roofline, thin gold emissive strips (solar glints). Wear 0.30, dirt 0.35 (dust: `#8A7A5C`).
* **Signature:** (1) draped teal fabric (SWAY part); (2) copper heat-shield stack; (3) visible swing arms; (4) gold thermal lens on beam weapons; (5) parasol / awning poles on APCs.
* **Motion feel.** Light, springy: wheel travel ±0.06 m, cloth sway 0.4 Hz, quick turret (140°/s).
* **Structure dialect.** Courtyards and tensile canopies (thin teal plates on posts), solar mirror rings (generator), copper domes, ivory walls, water tanks.
* **Never:** dark heavy hulls, hard slab armour, more than 25 % of area in copper.

| Archetype | OLM adaptation |
|---|---|
| Wayfarer / Needle / Mirage | ivory kit with teal neck-shade cloth; Needle: copper-banded tube on a tripod with a teal tarp; Mirage: hooded teal cloak, binoculars, shimmer when camouflaged. |
| Caravan APC | 6×6 with swing-arm wheels, teal awning over the roof, copper roll bar. |
| Sirocco / Sunlance | kit dictionary; Sunlance = longer hull, big copper-cradled lens with heat fins, gold emissive lens. |
| Crescent AA | two crescent-shaped missile-pod arcs on a rotating mount, teal side screens. |
| Sandglass Mortar | light 4-wheel with a swing-arm mortar tube, stabiliser feet on deploy. |
| Shrike / Nightjar | swept light fighter, ivory over teal belly, copper intake rings; dark-teal stealth flying-wing drone (no cockpit), copper edge lines. |
| Corsair / Lantern / Beacon | fast planing hull with a fabric canopy; sleek escort with a gold lantern lamp array on the mast; low hull with box launchers and a solar mirror mast. |
| Engineer / Collector / MCV / Landing | ivory coverall + teal hood; wheeled hopper with fabric cover; wheeled carrier with a folded HQ canopy; hover barge with a fabric skirt. |

#### 5.5.4 DEF — "heavy industry"

*Bible:* oxide red, gray and pale yellow; slab armor, exposed running gear, standardized containers. *Lore hook:* production quotas; ISO-container logistics; replaceable machines.

* **Silhouette.** Boxy and heavy: hull L 3.4, W/L 0.61, H/L 0.36; a square slab turret (n-gon 4, 0.86 × 0.86), short thick 1.85 m gun with a double-baffle brake; **no skirts** (exposed running gear: 6 road wheels of r 0.34, return rollers visible); a **standard container** (pale yellow, 1.0 × 0.55 × 1.4 half-height ISO box, door lines) strapped to the rear deck.
* **Vocabulary.** 1.30 m slab plates with 0.03 m proud weld beads, 0.02 m hard bevels, rivet rows every 0.20 m (0.03 m cylinders), stencilled numerals, yellow/black hazard tape, tow chains. Wear 0.70, dirt 0.65 (`#3B2A20`).
* **Signature:** (1) container on every deck; (2) pale-yellow numerals 0.5 m; (3) exposed road wheels; (4) chimney-like exhaust stacks; (5) big searchlights on structures.
* **Motion feel.** Ponderous: turret 60°/s, large recoil, engine rumble jitter (0.01 m).
* **Structure dialect.** Brutalist blocks in oxide panels, chimneys with pale-yellow bands, gantries, container stacks, buttresses.
* **Never:** skirts, smooth organic curves, cream or white.

| Archetype | DEF adaptation |
|---|---|
| Line Conscript / Recoil / Signal | oxide vest over grey kit, pale-yellow armband; Recoil: big disposable tube with a blast shield; Signal: radio backpack with two whips and a pennant. |
| Mule APC | boxy 6-wheel truck with a pale-yellow container body and slit windows. |
| Hammer / Colossus | kit dictionary; Colossus = 5.0 m slab hull, 2.2 m boxy turret, one short massive gun, two side sponsons, 8 exposed wheels a side. |
| Porcupine AA | open-mount quad flak barrels on a slab pedestal with a shield plate; pale-yellow ammo drums. |
| Anvil Rocket Battery | 6×6 truck; 4×10 tube block tilting to 55° on deploy; container-style side tanks. |
| Kite / Burya | straight-wing fighter, oxide nose, grey body, yellow numerals; four-engine straight-wing bomber, 8 m span, yellow stripes. |
| Picket / Rampart / Boreal | armoured slab boat with an HMG; slab-sided box escort with two turrets and a lattice mast; fat cylindrical submarine with a numeral on the sail and a missile hatch row. |
| Engineer / Collector / MCV / Landing | grey coverall + oxide vest; massive hopper with a bucket scoop; boxy carrier with a fold-out container HQ; slab landing barge. |

#### 5.5.5 PD — "amphibious task force"

*Bible:* ocean blue, coral orange and white; sealed hulls, folding flight surfaces, deck-mounted drones. *Lore hook:* sea lanes; everything is sealed, buoyant, foldable.

* **Silhouette.** Smooth sealed shapes with rounded chines; land vehicles have **boat-like prows** (pointed glacis) and **flotation sponsons** (white cylinders with a coral band, r 0.30 m) along the flanks; hatches with dark rubber seal rings; hinge lines visible where surfaces fold; a **deck drone pad** (coral disc with a small white quad-drone) on tanks, escorts and carriers.
* **Vocabulary.** 1.10 m long smooth panels, 0.06 m rounded bevels, hatch circles, seal beads, recessed handles. Wear 0.30, dirt 0.20 (salt-clean, `#2C3A44`).
* **Signature:** (1) **coral waterline band** on every hull; (2) flotation collars/sponsons; (3) deck drone pads; (4) folding wing/vane hinges (DEPLOY_Z hinge part); (5) snorkel stack with a coral cap; (6) white turret cap with a coral ring.
* **Motion feel.** Buoyant: idle pitch ±0.4° at 0.6 Hz on amphibious units; ships heave; wings fold in 1.2 s.
* **Structure dialect.** White domes and hangars on blue quay bases, crane gantries, sealed bulkhead doors, coral rails, life-ring props.
* **Never:** slab armour, angular faceting, matte military green.

| Archetype | PD adaptation |
|---|---|
| Ranger / Harpoon / Reef Technician | cerulean-white kit, snorkel mask on the helmet, coral dry-bag; Harpoon: tube with folding fins; Technician: backpack with an articulated coral arm. |
| Wake Skimmer | hovering boat hull, twin ducted fans aft, white cab, coral waterline. |
| Tide Tank | kit dictionary (float sponsons, bow profile, drone pad). |
| Storm AA | sealed hull, white radar dome, six-tube missile box that folds down, coral caps. |
| Breaker Howitzer | 8×8 sealed hull, long sleeved white barrel, coral muzzle ring. |
| Leviathan Assault Carrier | huge amphibious hull, bow ramp, twin sponsons, sealed siege turret, deck drone pads. |
| Petrel / Osprey | swept-wing fighter with visible fold hinges, white belly, coral wingtips; tiltrotor with two tilting nacelles (DEPLOY hinge), white belly, coral rotor tips. |
| Reef / Trident / Tempest | planing patrol hull with a white cabin and coral stripe; sleek white escort with a three-arm mast lamp; flat-deck carrier with coral drone pads and an island tower. |
| Engineer / Collector / MCV / Landing | cerulean coverall + white hat; amphibious hopper truck with floats; amphibious carrier with a folded HQ dome; hover barge with a white skirt. |

#### 5.5.6 HAN — "modular provincial"

*Bible:* jade green, crimson and porcelain; compact modular hulls, sensor crowns, standardized drone racks. *Lore hook:* central planning; everything is a standard module; command links are the weakness.

* **Silhouette.** Compact (hull L 3.0, 0.86 of standard), rounded-rectangle plan, near-circular turret (n-gon 12) with a **porcelain cap**, a **sensor crown** (6 tines, 0.16 m ring, emissive centre) on the turret, a **drone rack** (four cradles in a row, porcelain top) on the rear deck, module seams every 0.50 m as 0.01 m dark grooves with latch pins.
* **Vocabulary.** 0.50 m module grid, 0.04 m rounded bevels, latch pins (0.03 m cylinders) at module corners, standard ID plates (0.3 × 0.2 m, porcelain). Wear 0.25, dirt 0.20.
* **Signature:** (1) sensor crown; (2) drone racks; (3) crimson lines at module joints and crimson dot lanterns on command units; (4) porcelain caps; (5) **unmanned units have no hatches or cabins — an "eye" lens (emissive jade dot) instead**.
* **Readability-critical:** command-field providers (Link Operator, Dragon/Long Command Walker) must show the crown clearly (gameplay rule: the 5-cell field is tied to the provider). Mini-crown (0.3 m) on the operator's backpack; large crown (0.9 m) on the walker; crown tines lengthen on deploy.
* **Motion feel.** Swarm-like: drones bob in sync, crown rotates slowly (20°/s).
* **Structure dialect.** Tiered stacks of identical modules that shrink upward, porcelain roof caps, crimson eaves, sensor crown on top, drone racks on the side.
* **Never:** ragged wear, patchwork, large flat armour.

| Archetype | HAN adaptation |
|---|---|
| Banner / Lance / Link Operator | jade vest, porcelain helmet cap, crimson stripe; Lance: tube with a crimson band; Operator: backpack antenna crown (mini crown) + small jade dish. |
| Jade Carrier | compact 4-wheel box with a roof drone rack and a porcelain cab. |
| Ox Tank | kit dictionary. |
| Firefly AA / Nest Rocket | unmanned round base with a quad-barrel pod and eye lens; unmanned launcher block, 12 tubes in modular cells. |
| Dragon Command Walker | quad-legged walker, porcelain-capped body, large crown, crimson lanterns; 5-cell ground ring when active. |
| Swallow / Silkwing | canopy-less drone fighter, jade-white with crimson stripes; flying-wing drone bomber, porcelain top, crimson edge. |
| Canal / Jade Escort / Emperor Drone Ship | small boat with a drone rack; compact escort with a crown mast and aft racks; carrier deck with a grid of drone racks and a crown tower. |
| Engineer / Collector / MCV / Landing | jade with a crimson band; compact modular hopper; modular carrier with stacked HQ tiers folded; modular barge with a drone rack. |

#### 5.5.7 AE — "salvage works"

*Bible:* ochre, charcoal and bright cyan; repairable panels, reinforced wheels, interchangeable weapon modules. *Lore hook:* machines that are repaired, not replaced — you can see the repairs.

* **Silhouette.** Chunky, utilitarian, slightly asymmetric: hull W/L 0.57; bolt-on **side panels of visibly different tones** (4 panels: base, base −18 % light, dark +10 %, base +12 %) with visible bolts; **oversized reinforced road wheels** (r 0.36, steel rings with a cyan hub dot), even on tracked units; **weapon modules** on a standard rail with **cyan lock collars**; a front push-bar; spare panels / a spare wheel stowed on the rear deck; work lights.
* **Vocabulary.** 0.70 m irregular panels, 0.035 m bevels, bolts (0.028 m cylinders every 0.25 m), weld seams, patch plates, blocky serial-number decals. Wear 0.60, dirt 0.60 (`#3A2C1A`), emissive 2.8.
* **Signature:** (1) cyan module collars (emissive); (2) mismatched patch panels; (3) salvage crane arm on service/heavy units; (4) tow hooks; (5) cyan work-light bar.
* **Motion feel.** Robust: diesel idle shake (0.01 m), module swap slides 0.3 s with a small click.
* **Structure dialect.** Patchwork sheds, exposed pipes, jib cranes, scaffolding, caged cyan cores, scrap stacks.
* **Never:** clean uniform paint, smooth rounded shells, more than one cyan element cluster per model.

| Archetype | AE adaptation |
|---|---|
| Union Guard / Pike / Reclaimer | ochre tabard over charcoal armour plates, cyan belt lamp; Pike: stubby tube on a module collar; Reclaimer: welding mask, torch, backpack with a small crane arm (salvage read). |
| Mamba APC | high-clearance 6×6 with oversized steel-ringed tyres, patch panels, roof rails. |
| Buffalo | kit dictionary (patched skirts, heavy wheels, rail module). |
| Weaver AA | quad autocannon module on a rail, cyan collars, side ammo boxes. |
| Forge Howitzer | short fat barrel in a welded box turret, repair crane arm at the rear. |
| Kiln Assault Crawler | broad plough/shovel front, short cannon with a furnace muzzle (hazard-amber emissive). |
| Sunbird / Hammerhead | crank-wing fighter, ochre with charcoal patches, cyan intake ring; boxy armoured gunship with a chin module and patchwork armour. |
| Delta / Anchor / Sovereign | flat-bottom river boat with a module gun; chunky escort with mismatched panels and an aft crane; slow armoured barge with a heavy gun and crane. |
| Engineer / Collector / MCV / Landing | ochre coverall + cyan gloves; heavy hopper with a crane arm and reinforced wheels; reinforced carrier with HQ scaffolding folded; armoured barge. |

#### 5.5.8 SAP — "bastion corps"

*Bible:* sand, indigo and saffron; layered armor, deployable braces, prominent interception sensors. *Lore hook:* mutual protection; nothing moves without cover and a sensor watching the sky.

* **Silhouette.** Pyramidal / stepped: hull W/L 0.59, H/L 0.34, short steep glacis (0.35 m); **layered armour**: three stepped plates (dark / secondary / accent pin-stripe) up the glacis and turret front, each 0.08 m proud; sloped skirts in three tiers; **deployable braces** — four angled outrigger struts folded along the flanks (saffron feet), deployed via DEPLOY; **interception sensors** — two paddle panels (0.62 × 0.50 m, saffron rim, indigo face, emissive slit) on masts at the turret rear ("ears" from above).
* **Area mix rule.** Hull deck and glacis in `secondary`/`dark` indigo, turret and appliqué plates in `primary` sand (the SAP mix 34 / 30 / 18 / 10 / 8). This keeps the hull ΔE00 ≥ 40 from arid ground while sand remains the identity colour.
* **Vocabulary.** 0.80 m stepped plates, visible stair-step edges, buttress ribs, 0.04 m bevels. Wear 0.45, dirt 0.50.
* **Signature:** (1) paddle sensors; (2) stair-step armour; (3) saffron braces; (4) saffron pennant on command vehicles; (5) lilac interception glow.
* **Motion feel.** Measured: braces deploy with 4 % overshoot; sensor paddles sweep ±25° at 0.3 Hz.
* **Structure dialect.** Ziggurat-like stepped terraces (sand/indigo), corner buttresses, large interception panels.
* **Never:** smooth single-plane armour, thin gun-and-turret-only silhouettes, saffron as large areas.

| Archetype | SAP adaptation |
|---|---|
| Shield Rifle / Kavach / Pioneer | sand kit with an indigo shield plate on the arm, saffron sleeve tape; Kavach: heavy launcher on a bipod with a shield plate; Pioneer: pack of poles and braces with saffron tips. |
| Jackal APC | layered 6×6 with stepped plating and a roof sensor paddle. |
| Bulwark | kit dictionary. |
| Vajra AA | stepped hull, two paddle sensors, twin missile rack, saffron rims. |
| Monsoon Howitzer | stepped casemate, four corner braces with saffron feet. |
| Elephant Siege Tank | massive stepped hull, long sleeved "trunk" barrel 3.4 m, thick front braces. |
| Garuda / Sarus | broad swept-wing fighter with saffron leading edges and indigo top; armoured gunship with stepped panels and wing sensor pods. |
| Estuary / Shield Escort / Citadel | river boat with a sensor paddle; layered escort with two paddle sensors on the mast; fortress-ship with stepped armour tiers and a big turret. |
| Engineer / Collector / MCV / Landing | sand coverall + indigo helmet; layered hopper with braces; stepped carrier with a folded HQ terrace; armoured stepped barge. |

#### 5.5.9 Recipe Style Contract (RSC) — what every recipe must satisfy

1. **Colours by palette key** only (the roles of 4.5, spelled as render.md 5.8.3 colour slots such as `"base"` or `"acc"`), never `#rrggbb` literals (the validator rejects them); team areas only through the `team_panel` macro extended to the three-layer plate of 5.4.3 (request R-3).
2. **Declare** the render `archetype` (view archetype, render.md 5.8.6), the art `size_card` (must exist in `style.json → archetypes` or `structures`) and the roster `style`; kit-bash parts are style `slots` named `kit_<id>` (5.6.5) that the archetype calls at its anchors.
3. **Size:** bounding box within ±8 % of the size card (L, W, H, barrels and antennas excluded); footprint respects 5.7.
4. **Parts:** mandatory animated parts by archetype — tanks: `TURRET` + `BARREL` + `TRACK`/`WHEEL`; wheeled: `WHEEL` + optional `TURRET`; artillery: `TURRET` + `BARREL` (+ `DEPLOY`); AA: `TURRET` (+ `RADAR`); infantry: `LEG_A/B`, `ARM_A/B`, `BODY_BOB`; helicopters: `ROTOR` + `TAIL_ROTOR`; radar structures: `RADAR`; factories/docks/airfields: `DOOR`; all structures with lamps: `BLINK` on ≥ 1 beacon.
5. **Budgets:** triangles and vertices per archetype (9.2); LOD tiers assigned (tier 0 mass, tier 1 detail, tier 2 micro).
6. **Symmetry and asymmetry** as 5.5.0; `mirror_x` for the main masses.
7. **Front cues:** two head-lamps (emissive `light`), two tail-lights, a visible weapon or nose direction.
8. **Quiet zone** around plates (5.4.3); plate visible ≥ 70 %.
9. **Minimum feature size** 0.40 m for anything load-bearing for identification (5.8.3).
10. **Emissive area** ≤ 3 % of visible area; HDR ≤ 3.
11. **Signature parts** of the faction (bullet lists above) are present; ≥ 1 signature part is visible in the silhouette at FAR.
12. **Review:** the recipe passes the QA checklist (5.16) — turntable, family board, matrix, silhouette guard.


### 5.6 Subfactions: how 24 rosters differ *visually* without new palettes

A subfaction replaces exactly two baseline units with **unique units**, loses one, and inherits everything else (bible `rule.design.roster_selection`). Its look is therefore built from five layers, in this order of visibility at the RTS camera:

1. **Silhouette of the two unique units** (48 in total, recipes in 5.6.4) — the strongest cue.
2. **Kit-bash parts** (2-4 per subfaction, catalogue in 5.6.5) added to *every applicable shared unit* of that roster: a Canadian Guardian would not exist (replaced), but a Canadian Sentinel AA gets snorkel stack, float sponsons and a waterline band.
3. **Accent variant + band pattern**: same faction palette, the accent role shifted by a fixed rule; a 0.14-0.24 m band in a pattern unique within the faction.
4. **Insignia**: faction emblem + subfaction glyph on turret cheeks / tail fins / fascia (5.11); at < 48 px the glyph becomes 1-3 **pips**.
5. **Name**: title in tooltips and lobby ("Air Mobility Command").

#### 5.6.1 Accent variants (table)

**Accent rule (deterministic, data in `style.json → palettes["palette.<f>.<sub>"].accent`).** In CIE LCh with the parent accent as base, chroma preserved (gamut clamped): sub index **1**: lightness moved away from mid-grey by 12 L* (darker for light accents, lighter for dark ones); index **2**: hue -18°; index **3**: hue +18°. Sub index is the roster's order in the bible (`subfaction_roster_ids`). Sibling accents differ by ΔE00 ≥ 8 (AE cyan family 6.5: AE subfactions rely more on band and kit).

| roster | command title | pips | sub accent | band | glyph key | kit parts (shared units) |
|---|---|---|---|---|---|---|
| napc.usa | Air Mobility Command | 1 | `#C54600` | checker | napc.usa | `lift_ring`, `nav_light_bar`, `winglet_tips` |
| napc.canada | Northern Littoral Command | 2 | `#FF504A` | waterline | napc.canada | `waterline_band`, `snorkel_stack`, `float_sponson`, `wave_breaker` |
| napc.mexico | Federal Vanguard | 3 | `#CF7B00` | chevron | napc.mexico | `slat_cage`, `sandbag_roll`, `riot_shield_rack` |
| nec.nordics | Northern Watch | 1 | `#CE8700` | pinstripe | nec.nordics | `fold_mast_double`, `float_collar` |
| nec.eurocorps | Franco-German Armored Directorate | 2 | `#FF9F63` | block | nec.eurocorps | `applique_wedge`, `heavy_skirt` |
| nec.alpine_brotherhood | Pass and Tunnel Compact | 3 | `#D2B50F` | diag | nec.alpine_brotherhood | `rock_guard`, `roof_lamp_pair`, `shelter_roll` |
| olm.saudi_arabia | Solar Directorate | 1 | `#A35C1C` | wave | olm.saudi_arabia | `solar_fin`, `mirror_cap` |
| olm.algeria | Saharan Corridor Guard | 2 | `#D76F4E` | dash | olm.algeria | `sand_fender`, `jerry_rack`, `whip_pair` |
| olm.el_andalus | Western Straits Compact | 3 | `#B2852C` | checker | olm.el_andalus | `arched_screen`, `harbour_bollards` |
| def.russia | Northern Arsenal Command | 1 | `#C2B36B` | block | def.russia | `slab_addon`, `unit_numeral` |
| def.kazakhstan | Steppe Transit Command | 2 | `#F9CD8C` | dash | def.kazakhstan | `jerry_rack`, `whip_pair`, `dust_mesh_skirt` |
| def.north_korea | Fortress Reconstruction Bureau | 3 | `#CDDB90` | pinstripe | def.north_korea | `camo_net`, `decoy_frame`, `fortress_visor` |
| pd.australia | Southern Reach Command | 1 | `#D94E3E` | wave | pd.australia | `recon_pod`, `long_barrel_sleeve` |
| pd.indonesia | Archipelago Defense League | 2 | `#FF6C7F` | diag | pd.indonesia | `landing_ramp`, `grab_rails`, `outrigger_float` |
| pd.japan | Maritime Systems Authority | 3 | `#EF7D3D` | pinstripe | pd.japan | `sensor_ball`, `modular_hardpoint`, `drone_bay_hatch` |
| han.china | Imperial Standards Army | 1 | `#DE4649` | block | han.china | `numbered_module_plate`, `heavy_crown` |
| han.vietnam | Canopy Defense Command | 2 | `#BC044E` | dash | han.vietnam | `leaf_clip`, `reed_skirt` |
| han.cambodia | Mekong Reconstruction Authority | 3 | `#AB360A` | wave | han.cambodia | `repair_arm`, `tender_cradle`, `pipe_rack` |
| ae.nigeria | Civic Logistics Directorate | 1 | `#03B3CB` | checker | ae.nigeria | `comm_mast`, `drone_guard_cradle`, `civic_beacon` |
| ae.kongo | River Compact Guard | 2 | `#26D8DD` | wave | ae.kongo | `float_collar`, `reed_screen`, `snorkel_stack` |
| ae.south_africa | Southern Arsenal Union | 3 | `#4CD2FF` | block | ae.south_africa | `rangefinder_box`, `long_recoil_sleeve` |
| sap.india | Integrated Defense Command | 1 | `#CC8600` | block | sap.india | `layer_plate`, `command_pennant` |
| sap.thailand | River and Strait Command | 2 | `#FF9D60` | wave | sap.thailand | `float_collar`, `smoke_bank`, `mooring_hook` |
| sap.pakistan | Frontier Observation Command | 3 | `#D1B40B` | dash | sap.pakistan | `periscope_mast`, `missile_rail_cover` |

#### 5.6.2 Band patterns

Bands are 0.14-0.24 m tall: on vehicles at flank mid-height and glacis; aircraft: tail fins and rear fuselage; ships: hull side above the waterline; infantry: sleeve/shoulder 0.05 m; structures: fascia under the roof line and door lintel. Patterns:
`checker` two rows of alternating 0.12 m squares (accent/primary) · `waterline` one straight 0.14 m cream band low on the hull · `chevron` three nested V bars of 0.10 m, apex forward · `pinstripe` two 0.03 m lines 0.06 m apart · `block` three 0.30 × 0.14 m blocks evenly spaced · `diag` 0.12 m stripes at 45°, pitch 0.24 m · `wave` sinusoid amplitude 0.06 m, wavelength 0.50 m · `dash` 0.30 m dashes, 0.15 m gaps, 0.06 m thick.

#### 5.6.3 Insignia placement

Vehicles ≥ light: faction emblem 0.50 m on both turret cheeks (0.35 m on scouts) with the sub badge disc (40 % of emblem size) at its lower-right; aircraft: tail fin 0.60 m; ships: bow sides 0.70 m + bridge; structures: fascia sign 1.2-1.6 m (HQ additionally a roof marking 3.0 m); infantry: shoulder patch 0.06 m (colour only). Emblems on models are flat extruded polygons (`ViewEmblemGeometry.stamp`, 0.012 m thick), never textures.

#### 5.6.4 The 48 unique units — visual recipe as a delta from the unit they replace

Rule: a unique unit keeps the **size card of its archetype** (mismatch ≤ 8 %) and the **faction dictionary**, and changes 2-3 silhouette-relevant parts by ≥ 0.30 m so that the swap is readable at FAR. Archetypes are taken from `game/data/balance/global.json → unit_assignments`.

| unit | replaces | archetype | visual recipe (delta from the replaced unit) | kit parts |
|---|---|---|---|---|
| `napc.raptor_multirole_fighter` | Falcon Interceptor | air_fighter | Falcon fuselage class, canted twin tails, chined nose; 4 under-wing pylons: 2 cream-tipped AA rails + 2 orange-tipped AV pods that recolour with the loaded weapon set; USA tail checker band. | `winglet_tips`, `lift_ring` |
| `napc.condor_stealth_bomber` | Titan Gunship | air_bomber | Rotor-less faceted flying wing (sawtooth trailing edge), cream underside, one bomb-bay door line; camouflage = edge shimmer, cream fades to 35 % alpha. Silhouette change is total (gunship -> wing). | `nav_light_bar` |
| `napc.beaver_amphibious_apc` | Pathfinder APC | veh_scout | Boat-hull 6-wheel APC: raised prow, cream sponsons, prop-guard shrouds aft, snorkel stack, keeps the roof spinner and bubble cab. | `float_sponson`, `snorkel_stack`, `waterline_band` |
| `napc.narwhal_amphibious_tank` | Guardian Tank | mbt_t1 | Guardian turret on a sealed hull: folding wave-breaker vane on the glacis, cream sponsons folded up on the deck, aft water-jet ducts, sealed gun boot. Same size card as the Guardian (mbt_t1). | `wave_breaker`, `float_sponson`, `snorkel_stack` |
| `napc.vanguard_rifle_squad` | Rifle Squad | inf_line | Rifle squad with a folded portable cover shield on each back (olive plate, orange edge); deployed = 1.1 m cover panel stands in front (DEPLOY part). | `riot_shield_rack` |
| `napc.aguila_breach_team` | Combat Medic | inf_combat_spec | Heavy plate-carrier infantry: rectangular orange breach-charge pack, short grenade launcher, visored helmets; NO medical marking. | `breach_pack` |
| `nec.fen_recon_carrier` | Surveyor APC | veh_scout | Sealed amphibious hull with float collar; a fold-out mast unfolds to 6 m (amber head) on deploy - exposed, so the mast is bright. | `fold_mast_double`, `float_collar` |
| `nec.fjord_missile_carrier` | Archer SPG | arty_missile | Amphibious 6-wheel hull carrying a 4-tube canted missile pack; tube caps white, amber strip; tubes lie flat when moving, rise 35 deg to fire. | `float_collar` |
| `nec.marte_heavy_mbt` | Leopard Tank | mbt_t2 | Leopard silhouette x1.15, thicker glacis wedge with appliqué plates, larger angular turret, two mast stubs. | `applique_wedge`, `heavy_skirt` |
| `nec.charlemagne_siege_tank` | Argent Rail Tank | siege_rail | Longer rail gun on a heavier hull; deploy drops ground spades (DEPLOY) and the barrel extends telescopically +25 %. | `heavy_skirt` |
| `nec.alpine_pioneer` | Sapper | inf_combat_spec | Infantry with a grey-white shelter roll and folding spade on the back; the deployed shelter is a small tent prop (0.9 m). | `shelter_roll` |
| `nec.ibex_crawler_gun` | Archer SPG | arty_howitzer | Compact tracked howitzer: wide stubby crawler tracks with deep cleats, short thick barrel, front slab armour, rock-guard fenders; no wheels. | `rock_guard` |
| `olm.dawn_laser_aa` | Crescent AA | veh_aa_beam | Hooded lens turret replaces the missile pods: glass-copper prism lens, teal cooling fins, gold beam emitter. | `solar_fin` |
| `olm.ifrit_prism_tank` | Sunlance Beam Tank | siege_beam | Sunlance chassis with a faceted 6-face prism cluster in a copper cradle; deploy = outriggers + prism rises 0.6 m and opens. | `solar_fin`, `mirror_cap` |
| `olm.dune_rover` | Caravan APC | veh_scout | Open-cage 4-wheel dune buggy: roll cage, draped camo netting, cream/teal; camouflage shimmer. | `camo_net`, `sand_fender` |
| `olm.scorpion_rocket_buggy` | Sandglass Mortar | arty_light | Light buggy with a canted 12-tube copper rocket rack on a scorpion-tail arm over the rear. | `sand_fender` |
| `olm.gate_guard` | Wayfarer Guard | inf_line | Riot-shield infantry: teal-faced 0.5 m shield held in front; slower stride. | `riot_shield_rack` |
| `olm.strait_frigate` | Lantern Escort | ship_escort | Escort hull with a heavier forward gun house, shorter mast, extra deck gun, copper hull band. | `harbour_bollards` |
| `def.ural_assault_tank` | Hammer Tank | mbt_t2 | Hammer hull +15 %, two round APS pods on the turret cheeks, slab front plates; the deck container is replaced by an APS radar box. | `aps_pods`, `slab_addon` |
| `def.bear_siege_crawler` | Colossus Siege Tank | siege_demo | Very low wide crawler tracks, front wall of three slabs, one fat demolition cannon, tiny slit cupola. | `slab_addon` |
| `def.steppe_recon_carrier` | Mule APC | veh_scout | Lighter wheeled truck-cab with a tall extending recon mast and antenna fan; pale-yellow spare fuel drums. | `jerry_rack`, `whip_pair` |
| `def.saker_missile_truck` | Anvil Rocket Battery | arty_missile | 6x6 truck carrying two large single guided-missile canisters (Anvil has a rocket-pod block); raise 20 deg on deploy. | `jerry_rack` |
| `def.fortress_guard` | Line Conscript | inf_line | Infantry with a tripod heavy rifle (DEPLOY) and a slab shield; sandbag-coloured ground plate under the deployed team. | `riot_shield_rack`, `fortress_visor` |
| `def.echo_team` | Signal Officer | inf_support | Two-person team: radio pack + a flat decoy-tank frame strapped to the back that unfolds as the decoy. | `decoy_frame`, `camo_net` |
| `pd.outrider_howitzer` | Breaker Howitzer | arty_howitzer | 8x8 wheeled howitzer, barrel x1.35, wheeled stabiliser feet, coral muzzle brake, narrow-arc mount. | `long_barrel_sleeve`, `recon_pod` |
| `pd.wedge_recon_fighter` | Petrel Fighter | air_fighter | Delta-wing fighter with a sensor spine and a chin sensor ball; fold-able wingtips. | `recon_pod`, `winglet_tips` |
| `pd.kancil_landing_skimmer` | Wake Skimmer | veh_scout | Wake Skimmer hull widened with a bow ramp and grab rails; lighter turret. | `landing_ramp`, `grab_rails` |
| `pd.island_raider` | Ranger Marine | inf_line | Marine squad, lighter kit, snorkel masks pushed up on helmets, coral wrist bands, bright dry bags. | `dry_bag` |
| `pd.shinano_adaptive_tank` | Tide Tank | mbt_t1 | Tide hull with a two-mode turret: low mobile gun plus a folding long-barrel siege module that unfolds upward; coral hazard at the hinge. | `modular_hardpoint`, `sensor_ball` |
| `pd.shogun_drone_carrier` | Tempest Carrier | ship_carrier | Deck split in two: left half strike-drone launch rails (coral), right half interceptor cradles (white); sensor-ball tower. | `sensor_ball`, `drone_bay_hatch` |
| `han.imperial_guard_tank` | Ox Tank | mbt_t2 | Ox hull +10 %, long-barrel gun with fume extractor, porcelain shoulder plates and a crimson band; shorter crown. | `numbered_module_plate`, `heavy_crown` |
| `han.long_command_walker` | Dragon Command Walker | veh_command | Wider stance with a deployable outrigger ring; larger crown that extends 2 cells (tines lengthen on deploy). | `heavy_crown`, `numbered_module_plate` |
| `han.canopy_ranger` | Banner Infantry | inf_line | Rifle infantry with leaf-clip ghillie tunics (jade + brown) and low packs; camouflage shimmer. | `leaf_clip` |
| `han.reed_rocket_skimmer` | Nest Rocket Drone | arty_light | Small amphibious hovering skimmer with a 6-tube rocket pod and a reed-green skirt; unmanned (no hatch). | `reed_skirt`, `float_collar` |
| `han.lotus_drone_tender` | Jade Carrier | veh_scout | Jade Carrier hull with a lotus-petal drone dock ring (4 folding petals) on the roof and a small manipulator arm. | `tender_cradle`, `repair_arm` |
| `han.mekong_field_engineer` | Link Operator | inf_support | Operator with a folding boom antenna and tool belt; stationary deploy unfolds a mast (command-field provider stays readable via mini crown). | `boom_antenna` |
| `ae.civic_rifle_team` | Union Guard | inf_line | Riflemen with a belt of sensor pucks (cyan discs, 0.12 m). | `puck_belt` |
| `ae.lagos_drone_guard` | Weaver AA | veh_aa | AA vehicle with a small repair drone docked on the turret roof in a cyan-lit cradle. | `drone_guard_cradle`, `comm_mast` |
| `ae.okapi_amphibious_carrier` | Mamba APC | veh_scout | Amphibious wheeled carrier, tall bulky cargo hold with cleaner sheet panels (thin armour), float collar. | `float_collar`, `reed_screen` |
| `ae.river_warden` | Reclaimer | inf_combat_spec | Armed salvage infantry in reed-green cloth wrap with a cutting torch; camouflage shimmer. | `reed_wrap` |
| `ae.rhino_rail_tank` | Buffalo Tank | mbt_t2_rail | Buffalo hull with a long rail barrel between two capacitor cylinders (cyan rings); little splash. | `rangefinder_box`, `long_recoil_sleeve` |
| `ae.protea_gun_carrier` | Forge Howitzer | arty_howitzer | Gun on a turntable with a swappable canister shroud; module collar in cyan; switches 3 s. | `long_recoil_sleeve`, `rangefinder_box` |
| `sap.arjun_assault_tank` | Bulwark Tank | mbt_t2 | Bulwark with an APS ring: four small saffron radar patches on the turret corners, thicker layered front. | `layer_plate`, `aps_pods` |
| `sap.gaj_siege_platform` | Elephant Siege Tank | siege_he | Heavy platform with huge front braces (outrigger legs deploying), lowered chassis, long sleeved barrel. | `layer_plate`, `command_pennant` |
| `sap.naga_amphibious_carrier` | Jackal APC | veh_scout | Amphibious carrier with a six-tube smoke bank at the rear, serpentine wave-cut hull, float collar. | `smoke_bank`, `float_collar`, `mooring_hook` |
| `sap.river_marine` | Shield Rifle Squad | inf_line | Marines with lighter shields on the back and saffron life-vests. | `riot_shield_rack` |
| `sap.shaheen_missile_battery` | Monsoon Howitzer | arty_missile | Tracked missile battery with 4 long canted tubes; stabiliser legs deploy (DEPLOY part); sensor mast. | `missile_rail_cover`, `periscope_mast` |
| `sap.watchpost_recon_team` | Combat Pioneer | inf_support | Observers with a tripod optic and camouflage cloak; cloak shimmer. | `camo_net` |

#### 5.6.5 Kit-part catalogue (ids referenced above; `style.json → kit_parts`)

Every part lists the families it may be used on (column *applies to*; data `style.json → kit_applies`, API `ViewStyle.kit_part_applies`): `veh` ground vehicles, `ship`, `air`, `inf`, `struct`. A subfaction kit (2-4 parts, table in 5.6.1) is applied to every **shared** unit of the roster whose family the part lists; a unique unit uses 1-3 parts valid for its own family, and the build script rejects a mismatch (a slat cage on infantry, for example). Recipes implement each part once as a reusable function `kit_<id>(b, palette, anchor)`; anchors come from named marks in the archetype recipe (`hull_front`, `deck_rear`, `turret_cheek_l/r`, `roof_centre`, `flank_l/r`, `bow`, `stern`).

| kit part id | applies to | definition |
|---|---|---|
| `lift_ring` | vehicles, aircraft | Four rescue-orange airlift eyes (0.25 m rings) on the hull corners / fuselage hardpoints. |
| `nav_light_bar` | vehicles, aircraft, ships | Roof bar with two blinking navigation lights (BLINK part), 0.5 m. |
| `winglet_tips` | aircraft | 0.4 m canted winglets in the sub accent on aircraft wing tips. |
| `waterline_band` | vehicles, ships | Cream stripe 0.14 m high along the lower hull, above the tracks/keel. |
| `snorkel_stack` | vehicles | Vertical intake pipe (0.09 m radius, 0.7-1.0 m tall) with a capped top on the rear deck. |
| `float_sponson` | vehicles | Lengthwise cylinders (0.3 m radius) along both flanks, sub-accent band ring; folded flat as a box when stowed. |
| `wave_breaker` | vehicles | Hinged bow vane 0.9 x 0.4 m on the glacis (DEPLOY hinge part). |
| `slat_cage` | vehicles | Slat/cage armour: 0.05 m bars every 0.14 m, 0.35 m stand-off, around turret and hull sides. |
| `sandbag_roll` | vehicles | Two tan bolster rolls (0.25 m radius) across the front deck. |
| `riot_shield_rack` | infantry | Infantry: 0.5 x 0.7 m shield plate on the back in faction dark with accent edge. |
| `fold_mast_double` | vehicles | Two fold-out masts (5-6 m when deployed, 1.4 m stowed) with amber heads. |
| `float_collar` | vehicles | Inflatable-looking ring collar (0.22 m tube) around the lower hull; white with accent band. |
| `applique_wedge` | vehicles | Extra wedge armour block on the glacis (0.9 x 0.35 x 0.3 m), secondary colour with accent pin-stripe. |
| `heavy_skirt` | vehicles | Thicker side skirt (0.10 m) with three vertical ribs. |
| `rock_guard` | vehicles | Chunky front fenders / cowcatcher in dark grey, 0.4 m deep. |
| `roof_lamp_pair` | vehicles | Two roof floodlights (0.18 m) on stalks, warm-white emissive. |
| `shelter_roll` | infantry, vehicles | Grey-white rolled shelter (0.22 m dia, 0.6 m) on infantry backs / vehicle decks. |
| `solar_fin` | vehicles | Three raised reflective fins (gold) around the weapon mount or turret rim. |
| `mirror_cap` | vehicles | Gold faceted reflector cap (0.5 m) on the turret roof. |
| `sand_fender` | vehicles | Oversized wheel fenders (0.5 m wider) in accent copper. |
| `jerry_rack` | vehicles | Rack of 4 fuel cans (0.3 m) at the rear deck, pale-yellow / copper. |
| `whip_pair` | vehicles, ships | Two 2.0-2.4 m antenna whips, one with a tiny pennant. |
| `arched_screen` | vehicles | Arched (semi-circular) fabric screen on each flank, teal with copper edging. |
| `harbour_bollards` | ships, structures | Two mooring bollards on ships/boats and quay-side props on structures. |
| `slab_addon` | vehicles | Extra 0.12 m slab plates bolted over glacis and turret front. |
| `unit_numeral` | vehicles | Stencilled 3-digit numeral 0.5 m tall, pale yellow, on turret side / hull front. |
| `aps_pods` | vehicles | Two flat round pods (0.35 m dia) on the turret cheeks, dark with accent lens. |
| `dust_mesh_skirt` | vehicles | Fine mesh skirt (translucent look via alternating slats) in secondary. |
| `camo_net` | vehicles, infantry | Drab netting drape (angular cloth panel) over turret rear / deck; on infantry a cloak panel over the shoulders; olive-grey. |
| `decoy_frame` | vehicles, infantry | Folded flat decoy tank frame (0.9 x 0.5 m) strapped to infantry backs or vehicle sides. |
| `fortress_visor` | vehicles, infantry | Slit visor plate on helmets / cupola. |
| `recon_pod` | vehicles, aircraft | Under-wing / hull sensor pod 0.6 m with a coral lens. |
| `long_barrel_sleeve` | vehicles, ships | Barrel sleeve +25% length with a coral end ring. |
| `landing_ramp` | vehicles | Hinged bow ramp 1.4 x 0.9 m (DEPLOY hinge part), coral hinge line. |
| `grab_rails` | vehicles, ships | Perimeter rails 0.05 m tube in coral. |
| `outrigger_float` | vehicles | Small outrigger float arm each side (0.8 m), white with coral tip. |
| `sensor_ball` | vehicles, ships | White 0.45 m sphere on a short mast with an emissive slit. |
| `modular_hardpoint` | vehicles | Standard 0.3 x 0.3 m mounting plate with 4 bolts on hull sides. |
| `drone_bay_hatch` | vehicles, ships | Square roof hatch (0.7 m) with an accent perimeter light. |
| `numbered_module_plate` | vehicles, structures | Standardised 0.3 x 0.2 m ID plates (porcelain) on each hull module (vehicles) or wall module (structures). |
| `heavy_crown` | vehicles | Sensor crown with 8 tines instead of 6 (0.7 m tall). |
| `leaf_clip` | vehicles, infantry | Leaf-shaped camouflage clips (0.2 m, jade/brown) along the hull edges; on infantry on tunic and helmet. |
| `reed_skirt` | vehicles | Vertical reed-green slats along the lower hull. |
| `repair_arm` | vehicles | Small folding manipulator arm (1.0 m) on the roof, dark with accent joints. |
| `tender_cradle` | vehicles | Lotus-petal drone dock ring (4 folding petals) on the roof. |
| `pipe_rack` | vehicles | Coiled hose / pipe rack on the flank (0.6 m). |
| `comm_mast` | vehicles | 3 m radio mast with two guy wires and a cyan beacon. |
| `drone_guard_cradle` | vehicles | Small drone cradle (0.5 m) on the roof with cyan lights. |
| `civic_beacon` | vehicles, structures | Roof beacon (cyan) pulsing 1 Hz while the vehicle is idle or the structure is powered. |
| `reed_screen` | vehicles | Reed-slat screen (0.04 m slats) along flank, ochre. |
| `rangefinder_box` | vehicles | Roof rangefinder box 0.6 x 0.3 x 0.3 m with two lenses. |
| `long_recoil_sleeve` | vehicles | Extended recoil cylinder alongside the barrel (0.9 m). |
| `layer_plate` | vehicles | Third stepped armour layer (indigo, 0.08 m) on glacis and turret. |
| `command_pennant` | vehicles, ships | Saffron pennant on a 1.5 m whip (team-coloured mask on the flag). |
| `smoke_bank` | vehicles | Bank of six smoke tubes (0.08 m) at the rear deck. |
| `mooring_hook` | vehicles, ships | Bow mooring hook / tow eye in accent. |
| `periscope_mast` | vehicles, ships | Telescoping periscope mast (2 m) with a small lens head. |
| `missile_rail_cover` | vehicles | Rail cover panel on missile launchers, saffron end caps. |
| `dry_bag` | infantry | Infantry: bright coral dry bag (0.22 m dia, 0.45 m) on the back, snorkel mask pushed up on the helmet. |
| `breach_pack` | infantry | Infantry: rectangular rescue-orange charge pack (0.35 x 0.25 x 0.15 m) on the back and a short launcher (0.5 m) slung across the chest. |
| `puck_belt` | infantry | Infantry: belt of six sensor pucks (cyan discs, 0.12 m) worn as a bandolier. |
| `reed_wrap` | infantry | Infantry: reed-green cloth wrap (angular panels, SWAY part 25) over shoulders and torso, cutting-torch nozzle (0.4 m) on the right arm. |
| `boom_antenna` | infantry | Infantry: folding boom antenna (1.2 m, small dish) on the back; unfolds with the deploy state. |

### 5.7 Size cards

Units in the sim have a collision radius `r` in cells (TAXONOMY size classes); 1 cell = 3 m. The **visual footprint rule** keeps formations from visually interpenetrating: for ground vehicles and ships `L/2 ≤ 1.3 · r · 3 m` and `W/2 ≤ 0.95 · r · 3 m` (validated by `check_style.py`); infantry squads fit inside a circle of radius r; aircraft have no footprint rule (altitude separates them) but their shadow blob uses `r`. `model_scale` stays within [0.85, 1.15] except infantry (1.25).

| archetype | size class | r (cells) | L x W (m) | L x W (cells) | H (m) | team field area, designed (m2) | altitude | notes |
|---|---|---|---|---|---|---|---|---|
| inf_line | inf | 0.4 | 1.9 x 1.70 | 0.63 x 0.57 | 1.25 | 0.2 | - | 4 soldiers, 2x2 diamond, spacing 0.75 m; model_scale 1.25 on the 1.0 m soldier |
| inf_at | inf | 0.4 | 1.9 x 1.70 | 0.63 x 0.57 | 1.25 | 0.16 | - | 3 soldiers; launcher tube 0.9 m; one kneels |
| inf_support | inf | 0.4 | 1.5 x 1.30 | 0.50 x 0.43 | 1.25 | 0.1 | - | 2 soldiers; distinctive backpack/gear silhouette (0.5 m) |
| inf_combat_spec | inf | 0.4 | 1.8 x 1.60 | 0.60 x 0.53 | 1.25 | 0.14 | - | 3 soldiers; heavier kit |
| veh_scout | light | 0.45 | 3.4 x 1.80 | 1.13 x 0.60 | 1.70 | 0.7 | - | 4x4/6x6 wheeled; roof sensor spinner or mast |
| arty_light | light | 0.5 | 3.6 x 1.90 | 1.20 x 0.63 | 1.90 | 0.7 | - | light wheeled/skimmer chassis; rack raised to 2.6 m when firing |
| mbt_t1 | medium | 0.55 | 3.5 x 1.95 | 1.17 x 0.65 | 2.00 | 1.0 | - | hull top 1.16 m; turret to 2.0 m; barrel adds 1.6-2.7 m forward |
| mbt_t2 | medium | 0.6 | 3.9 x 2.10 | 1.30 x 0.70 | 2.20 | 1.1 | - | T1 style dict x1.10 length, heavier glacis, second sensor or APS feature |
| mbt_t2_rail | medium | 0.6 | 3.9 x 2.10 | 1.30 x 0.70 | 2.20 | 1.1 | - | long rail barrel 3.2 m with cyan-blue capacitor rings |
| veh_aa | medium | 0.55 | 3.6 x 2.00 | 1.20 x 0.67 | 2.50 | 1.0 | - | tall turret; radar/mast to 3.0 m; multi-barrel or launcher pods |
| veh_aa_beam | medium | 0.55 | 3.6 x 2.00 | 1.20 x 0.67 | 2.50 | 1.0 | - | lens turret instead of pods |
| veh_aa_flak | medium | 0.55 | 3.6 x 2.00 | 1.20 x 0.67 | 2.50 | 1.0 | - | twin flak barrels, open mount |
| arty_howitzer | medium | 0.6 | 4.0 x 2.00 | 1.33 x 0.67 | 2.30 | 1.0 | - | casemate turret to the rear; barrel raised to 3.5 m; rear spades (DEPLOY part) |
| arty_rocket | medium | 0.6 | 4.0 x 2.10 | 1.33 x 0.70 | 2.60 | 1.0 | - | rocket rack raised to 3.2 m |
| arty_missile | medium | 0.6 | 4.0 x 2.10 | 1.33 x 0.70 | 2.60 | 1.0 | - | canted tubes raised to 3.2 m |
| siege_ap | heavy | 0.8 | 5.0 x 2.70 | 1.67 x 0.90 | 2.50 | 1.6 | - | twin-gun heavy; hull top 1.35 m |
| siege_he | heavy | 0.8 | 5.0 x 2.70 | 1.67 x 0.90 | 2.50 | 1.6 | - | one fat siege gun |
| siege_rail | heavy | 0.8 | 5.0 x 2.70 | 1.67 x 0.90 | 2.40 | 1.6 | - | long rail gun; deployable variant adds outriggers |
| siege_beam | heavy | 0.8 | 5.0 x 2.70 | 1.67 x 0.90 | 2.60 | 1.6 | - | prism / lens array on a raised mount |
| siege_demo | heavy | 0.85 | 5.4 x 2.90 | 1.80 x 0.97 | 2.60 | 1.7 | - | very low wide crawler; short huge cannon |
| veh_command | huge | 1.0 | 5.2 x 4.40 | 1.73 x 1.47 | 4.20 | 2.2 | - | walker: 4-leg stance 4.4 m wide, body at 3.0 m, crown to 4.2 m |
| veh_assault_carrier | huge | 1.0 | 6.4 x 3.30 | 2.13 x 1.10 | 2.70 | 2.0 | - | amphibious hull; bow ramp; siege cannon |
| air_fighter | air_medium | 0.5 | 5.2 x 3.80 | 1.73 x 1.27 | 1.30 | 0.5 | 9.0 m | cruise altitude 9 m; shadow blob offset by altitude |
| air_gunship | air_large | 0.65 | 4.6 x 1.50 | 1.53 x 0.50 | 1.90 | 0.55 | 4.5 m | rotor disc 5.4 m; hover altitude 4.5 m (rotor top 6.8 m) |
| air_bomber | air_large | 0.7 | 6.6 x 8.00 | 2.20 x 2.67 | 1.70 | 0.7 | 11.0 m | flying-wing or delta; altitude 11 m |
| air_drone | air_medium | 0.5 | 2.8 x 3.00 | 0.93 x 1.00 | 0.80 | 0.3 | 6.0 m | quad/wing drone; altitude 6 m |
| air_ew | air_large | 0.6 | 6.0 x 6.40 | 2.00 x 2.13 | 1.90 | 0.6 | 10.0 m | jammer aircraft; large dorsal radome |
| ship_patrol | ship_small | 0.6 | 4.6 x 1.90 | 1.53 x 0.63 | 2.20 | 0.6 | - | mast to 3.2 m; draft 0.3 m |
| ship_escort | ship_medium | 1.0 | 7.6 x 2.70 | 2.53 x 0.90 | 3.30 | 1.2 | - | mast to 4.8 m; forward gun house, aft AA |
| ship_siege | ship_large | 1.3 | 9.8 x 3.50 | 3.27 x 1.17 | 3.60 | 1.6 | - | big gun turrets fore/aft; superstructure amidships |
| ship_carrier | ship_large | 1.5 | 11.6 x 4.80 | 3.87 x 1.60 | 3.60 | 2.0 | - | flight deck; island tower to 5.0 m |
| ship_sub | ship_medium | 0.9 | 6.8 x 1.70 | 2.27 x 0.57 | 1.70 | 0.5 | - | sail to 2.5 m; submerged: dark hull shape 1.2 m under the surface |
| service.engineer | inf | 0.4 | 1.5 x 1.20 | 0.50 x 0.40 | 1.25 | 0.1 | - | 2 engineers, tool bag + hard-hats in accent |
| service.collector | light | 0.6 | 4.2 x 2.30 | 1.40 x 0.77 | 2.40 | 0.8 | - | hopper truck with front scoop; hopper visibly fills (BODY_BOB/level uniform) |
| service.mcv | medium | 0.8 | 5.2 x 2.70 | 1.73 x 0.90 | 3.00 | 1.3 | - | boxy carrier with folded HQ frame on the bed; deploy part unfolds |
| service.landing_transport | light | 0.8 | 5.2 x 2.90 | 1.73 x 0.97 | 2.10 | 1.0 | - | amphibious flat-deck hover/LCAC style, ramp at the bow |

Formation and geometry conventions: an infantry squad of 4 stands on a diamond (0, −0.55), (±0.50, 0), (0, +0.55) m; casualties remove soldiers in reverse order at HP thresholds 75 / 50 / 25 % (the formation must still read with 3, 2, 1 soldiers). Barrels (up to 2.7 m), antennas (up to 3.2 m) and rotors are not counted in L × W × H but must stay within `r_m + 2.7 m` of the centre. Aircraft altitudes are the recommended `hover_m` for the view domain. Submarines draw a dark hull shape 1.2 m under the water surface when submerged.

**Conformance with render.md 5.1** (model radius = largest horizontal extent, allowed band ±15 % around `1.05 · r · 3 m`, measured here as the half-diagonal of L × W): inside the band are the 4-soldier squads, heavy / siege units, the walker and the assault carrier; medium vehicles and the MCV sit up to 4 % above it; **above the band** are the wheeled scout (+18 %), light artillery (+12 %), the collector (+10 %) and all ships (+7 % to +16 %); **below the band** are the 1-2 soldier squads (support -7 %, engineer -10 %). The cards obey the footprint rule above instead, because elongated hulls and boats cannot fit a circle; RK-22 asks the reconciler to relax the render test for them.

**Structures by footprint** (economy.md footprints; the airfield row follows `DefStructure.fp` whichever domain wins the 6 × 3 vs 4 × 3 discrepancy — the model builds for `fw × fh` from the def, pads occupy the middle row, 4 pads):

| structure | footprint (cells) | footprint (m) | body H (m) | landmark H (m) | notes |
|---|---|---|---|---|---|
| headquarters | 3 x 3 | 9 x 9 | 7.0 | 10.5 | tallest non-strategic; roof landmark + pennant; south apron 3x2 |
| generator | 2 x 2 | 6 x 6 | 3.4 | 7.2 | power: stacks / mirrors / dome / tiers |
| refinery | 3 x 3 | 9 x 9 | 5.5 | 8.0 | silos + intake bay on the south side (collector dock cell) |
| barracks | 2 x 2 | 6 x 6 | 3.6 | 5.5 | door bay faces south; recruitment banner |
| factory | 3 x 3 | 9 x 9 | 4.2 | 7.0 | wide roll-up door on the south face; gantry / crane |
| dock | 3 x 3 | 9 x 9 | 3.2 | 8.5 | quay with crane; 3x2 berth on the water side |
| radar | 2 x 2 | 6 x 6 | 3.0 | 8.0 | rotating dish/array is the landmark |
| airfield | 6 x 3 | 18 x 9 | 4.2 | 8.0 | footprint follows DefStructure.fp (6x3 in economy.md, 4x3 in balance); 4 pads in the middle row; tower 8 m |
| laboratory | 3 x 3 | 9 x 9 | 6.0 | 9.0 | dome / prism / array on the roof |
| watchtower | 1 x 1 | 3 x 3 | 7.5 | 7.5 | slim tower, 1.6 m wide, cab with glazing |
| anti_tank_turret | 1 x 1 | 3 x 3 | 2.3 | 2.3 | low bunker + traversing gun (economy 1x1; balance 2x2 - visual scales to fp) |
| aa_battery | 2 x 2 | 6 x 6 | 3.6 | 4.5 | launcher rack or flak mount on a bunker |
| advanced_defense | 2 x 2 | 6 x 6 | 4.8 | 6.0 | faction unique heavy turret / launcher |
| relay | 1 x 1 | 3 x 3 | 6.5 | 6.5 | NEC only: slim mast with 3 fold-out arms; 6-cell field ring on the ground |
| superweapon | 4 x 4 | 12 x 12 | 12.0 | 14.0 | unique landmark per faction; visible from MAX zoom |
| neutral.substation | 2 x 2 | 6 x 6 | 4.5 | 6.0 | civic grey with civic-blue trim; pylons |
| neutral.salvage_depot | 3 x 3 | 9 x 9 | 5.0 | 8.0 | scrap yard + crane; gunmetal / rust |
| neutral.field_hospital | 2 x 3 | 6 x 9 | 4.2 | 5.5 | white tent-hall with a civic-blue bar and beacons |
| neutral.observation_tower | 1 x 1 | 3 x 3 | 8.0 | 8.0 | lattice tower + cab |
| neutral.civilian_garrison | 3 x 3 | 9 x 9 | 8.0 | 10.0 | apartment block; garrison slits glow when occupied |
| neutral.harbor_terminal | 3 x 3 | 9 x 9 | 3.6 | 9.0 | shore only; cranes and container stacks |
| neutral.salvage_field | 3 x 3 | 9 x 9 | 1.6 | 2.6 | resource deposit: scrap heaps, glint sprites; richness by pile count |

Height budget (validated by `check_style.py`): **body height ≤ 0.9 × the short footprint side** (except watchtower, relay, strategic and neutral structures); **landmarks** (masts, stacks, domes, dishes, cranes) ≤ **1.45 × the short side** and ≤ 15 % of the footprint area (1x1 slender structures — watchtower, relay, observation tower, anti-tank bunker — are exempt because the tower *is* the landmark). An 8.0 m radar mast on a 2×2 hides about 5.6 m of ground behind it at 55° pitch. Superweapons: 12 m body, 14 m landmark (1.17×), visible at MAX. Absolute caps from render.md 5.8.2 and its risk R13 (near plane): 8 m for 1×1 and 2×2 structures, 12 m for larger ones, 14 m for superweapons. (MEASURED depth of a 14 m roof at the bottom screen edge, H = 34: 25.2 m against a near plane of 20.4 m.)

### 5.8 Readability rules at the RTS camera

#### 5.8.1 Reference camera tiers (1080p; scale px/m by `viewport_height / 1080`)

| tier | zoom z | camera height H (m) | pitch (deg) | distance (m) | px per metre across the view @1080p | px per metre along the ground depth | px per cell |
|---|---|---|---|---|---|---|---|
| NEAR | 0.0 | 34.0 | 46.0 | 47.3 | 33.2 | 23.9 | 100 |
| MID | 0.25 | 43.2 | 48.8 | 57.5 | 27.3 | 20.5 | 82 |
| FAR | 0.7 | 65.3 | 55.4 | 79.4 | 19.8 | 16.3 | 59 |
| MAX | 1.0 | 84.0 | 61.0 | 96.0 | 16.3 | 14.3 | 49 |

Tiers are zoom stops of the game camera of render.md 5.4 (`ease(z) = 0.35 z² + 0.65 z`, `H = 34 + 50·ease` m, `pitch = 46° + 15°·ease`, vertical FOV 38°, `distance = H / sin(pitch)`); the scale across the view is `1080 / (2 tan 19° · distance)` px/m and the scale along the ground depth is that times `sin(pitch)`. MEASURED figures in this document (fidelity, IoU, coverage) come from the proof harness at pitch 55°, FOV 40° and ray distances 45 / 60 / 84 m (ground-depth scale 27.0 / 20.3 / 14.6 px/m), i.e. within 10 % of the MID / FAR / MAX scale of the tiers. QA uses the **MID / FAR / MAX** rows.

#### 5.8.2 Rules RD-01..RD-14 (each is a checklist item in 5.16; "R-n" without D always means a cross-module request in section 13)

| Id | Rule | Threshold |
|---|---|---|
| RD-01 | **Class cue at FAR.** Tank: hull + turret + barrel, hull aspect ≥ 1.7. Scout/APC: short wheeled body + roof sensor. Artillery: oversized rear casemate + raised barrel. AA: tall turret with radar/pods (H ≥ 2.4 m). Siege/heavy: W ≥ 2.7 m with two visible masses. Walker: legs + negative space. Aircraft: wing or rotor disc. Ship: pointed bow + off-centre superstructure. | reviewer can name the class from a 20 px/m crop |
| RD-02 | **Silhouette vs ground.** Outer contour differs from the lit ground by ΔE00 ≥ 12, or the model owns a dark mass ≥ 12 % of its area. | ΔE00 ≥ 12 / dark ≥ 12 % |
| RD-03 | **Negative space.** At least one gap ≥ 0.20 m between turret/hull/gun or between legs, so units do not read as blobs. | ≥ 1 |
| RD-04 | **Protrusion cap.** ≤ 3 silhouette-defining protrusions per model. | ≤ 3 |
| RD-05 | **Team plate** per 5.4.3 (≥ 0.45 m field, 5-12 % of the plan-view silhouette, 2 plates, ≥ 70 % visible). | see 5.4.3 |
| RD-06 | **Minimum feature size:** identification features ≥ 0.40 m; accent stripes ≥ 0.12 m thick; text/numerals ≥ 0.40 m tall; decoration ≥ 0.08 m; a gun barrel ≥ 0.15 m diameter. | see left |
| RD-07 | **Height ordering** (top of body): infantry 1.25 < scout 1.7 < light artillery 1.9 < tank 2.0-2.2 < AA 2.5 ≈ heavy 2.5-2.6 < command walker 4.2 < structures ≥ 3.0; aircraft at their altitude with a ground shadow. | ±8 % |
| RD-08 | **Facing cues:** two warm head-lamps front, two red tail-lights rear, barrel/nose/bow forward; infantry weapons forward. | present |
| RD-09 | **Value spread:** dark ≥ 12 %, light ≥ 8 % of visible area (5.3.3). | measured |
| RD-10 | **Emissive budget:** ≤ 3 % of area, HDR ≤ 3.0. | measured |
| RD-11 | **Accent budget:** accent role ≤ 8 % of area; never adjacent to a plate (< 0.15 m). | measured |
| RD-12 | **Distinct class shapes within a faction:** IoU between different archetypes' silhouettes ≤ 0.80 (guards against reskins; target — baseline to be recorded by ART-5). | measured |
| RD-13 | **Copy-paste guard:** same archetype across factions IoU ≤ 0.95. | measured |
| RD-14 | **State cues never hide the plate:** smoke, fire and shimmer are drawn above/behind, plate stays ≥ 50 % visible at HP ≥ 33 %. | reviewed |

#### 5.8.3 State cues (what the player must be able to see)

| State | Cue |
|---|---|
| Selected | shader rim `#FFEAB3`, power 5 (thin, does not wash the hull) + ground brackets in relation colour (5.12.5) |
| Damaged 66-33 % | soot patches (shader damage 0.35-0.65) + thin grey smoke plume (S0 loop, 0.3 puffs/s, 1.2 m rise) |
| Damaged < 33 % | damage 0.65-1.0, dark smoke, embers `#FF7A2A` flicker 5 Hz; structures add fire jets and cracks |
| EMP-disabled | crawling cyan arcs (2 per 0.5 s) + emissive flicker 4 Hz + weapons-off icon |
| Suppressed | infantry kneel/lower (BODY_BOB damped), pale dust flicks, small icon |
| Camouflaged | shimmer: alpha 0.35, edge distortion; owner still sees a 60 % plate |
| Deployed | spades / braces / masts extended; foot-print mark 0.6 m |
| Under construction | rises out of the ground over the 30-tick build-up inside a scaffold cage with weld sparks (render.md 5.2 BUILDUP), then the cage disappears (5.9.6) |
| Powered down | emissives -80 %, radar stops within 2 s, "no power" glyph (UI) |
| Wreck | dark model, neutral grey plate, smoke 14 s |
| Garrisoned neutral block | garrison slits glow warm amber |

#### 5.8.4 Strategic-zoom markers and crowds

* When the camera is farther than the FAR tier (px/m < 18), the UI draws a 20 px **class glyph tinted with the player colour** above infantry squads, aircraft and units < 3 m; vehicles rely on the plate. Threshold: `style.camera_tiers` (FAR 20 px/m → glyphs appear below 18).
* Crowd: up to 400 entities at 60 FPS (ARCHITECTURE §8): formation spacing = collision radius, so with the footprint rule (5.7) no two bodies overlap by more than 15 % of their length. No per-unit effect may exceed S1 (1.6 m fireball) unless it is a kill.


### 5.9 Structure design vocabulary

The 29 structure definitions become **8 factions × 12 shared structures + 8 superweapons + 8 advanced defences + 1 Relay = 113 models**, produced from one **structure kit** per faction plus a function anchor per structure type. A structure must be identifiable by (1) its *function anchor* (what it does), (2) its *faction dialect* (whose it is), (3) its *roof* (what the RTS camera sees 70 % of the time).

#### 5.9.1 Universal anatomy (every structure, every faction)

1. **Plinth**: 0.16 m concrete slab (`#8A8E90`) of `(3·fw − 0.5) × (3·fh − 0.5)` m, i.e. the footprint minus a 0.25 m margin per side (render.md 5.1: nothing may leave it); four corner bollards (0.09 m radius, 0.36 m tall, faction `dark`); 0.9 m-deep hazard chevron strip on the south (approach) edge, alternating faction accent and near-black `#1B1B1A`.
2. **Body**: at most three stacked volumes; each level steps in by ≥ 0.25 m so the shadow line reads. Height budget 5.7.
3. **Roof**: carries the function cues (equipment rows, dishes, stacks, skylights) and the **roof team plate** (≥ 1.0 m² and ≥ 2.5 % of the footprint, double gasket, quiet zone).
4. **Front**: doors and bays face **south (+Z)** so the default camera sees them; bay openings show an emissive interior strip (warm `light`) so "open" reads.
5. **Landmark**: one narrow tall element (≥ 1.2 × body, ≤ 1.45 × short side, and never above the render caps of 8 m for 1×1 / 2×2, 12 m for larger structures and 14 m for superweapons) in `secondary` or `metal` with an accent ring, visible at MAX.
6. **Pennant**: team-colour flag 0.56 × 0.36 m on a 2.0 m mast on HQ, barracks, factory, dock, airfield, radar, laboratory (not on generators, defences, neutrals).
7. **Lighting**: window/strip emissives in `light`; one BLINK beacon on the tallest point (0.9 Hz; orange for NAPC, red for others).
8. **Damage / power / build states**: 5.9.6.

#### 5.9.2 Function anchors

| Structure | What identifies it (any faction) | Required animated parts |
|---|---|---|
| Headquarters 3×3 | tallest official building: central tower + wide entrance + pennant + 1.6 m emblem fascia + 3 m roof marking; 8-cell build radius shown by the UI ring, not by geometry | BLINK, small RADAR |
| Generator 2×2 | stacks / coolers / coils / mirror ring; steam puff (S0 loop, 0.2/s) while powered | BLINK |
| Refinery 3×3 | 2-3 silos (1.6 m Ø, 5.5 m) + intake funnel and conveyor on the south face where Collectors dock; free Collector emerges from the bay | DOOR (bay) |
| Barracks 2×2 | low hall, wide door bay south, recruitment banner, obstacle-pole rack, roof antenna | DOOR |
| Factory 3×3 | 3.8 m-wide roll-up door on the south face (10 slats stack under the lintel), roof gantry/crane, stacks; lit interior strips | DOOR, BLINK |
| Dock 3×3 (+3×2 berth) | quay platform, bollards, 8.5 m jib crane over the water side, fenders on the slip; must face water | BLINK (crane light) |
| Radar 2×2 | plain base + rotating dish/array 8.0 m high; stops when unpowered | RADAR (30°/s) |
| Airfield 6×3 | long apron with runway paint, 4 white pad rings in the middle row, hangar at one end, 8 m control tower at the other, windsock | SWAY, BLINK |
| Laboratory 3×3 | boxy building with a roof dome / prism / array; glowing lens in `emissive_alt`; pulses 0.5 Hz while researching | BLINK |
| Watchtower 1×1 | slim tower (1.6 m wide, 7.5 m), glazed cab, rotating searchlight | RADAR |
| Anti-tank turret 1×1 | low bunker + traversing gun; sandbag-coloured ring | TURRET, BARREL |
| AA battery 2×2 | bunker with launcher rack or flak mount; small spinner | TURRET, RADAR |
| Advanced defence 2×2 | faction heavy weapon (5.9.4) | TURRET, BARREL |
| Relay (NEC) 1×1 | 6.5 m mast with three fold-out arms; faint amber ground ring of radius 18 m (6 cells) drawn by the UI when powered | RADAR |
| Superweapon 4×4 | faction landmark (5.9.4) with 8-segment charge display | per faction |

#### 5.9.3 Faction structure dialects

| Faction | Massing | Roof | Walls | Openings | Signature elements |
|---|---|---|---|---|---|
| NAPC | broad low-rise depots | flat, equipment rows, orange rail | cream upper over olive tiles (0.9 m) | roll-up doors with orange lintel | beacon, chevron apron, tow-hook props |
| NEC | long, low, horizontal | single-slope with white panels | slate fine-seam panels | full-width amber strip windows | fold-out masts, relay pylons |
| OLM | courtyard + tensile canopies | thin teal canopy plates on posts, copper domes | ivory | arched teal doors | mirror rings, water tanks, sun-shade poles |
| DEF | brutalist blocks | flat with chimneys | oxide slabs with weld beads | steel roller doors, hazard tape | pale-yellow banded chimneys, container stacks, gantries |
| PD | rounded sealed domes / hangars | domes, white | white over cerulean base ring | sealed bulkhead doors with coral rims | cranes, life-ring props, coral rails |
| HAN | tiered stacks of identical modules | porcelain caps, crimson eaves | jade modules with 0.5 m grooves | narrow slit lamps | sensor crown, drone racks |
| AE | patchwork sheds | corrugated with skylights | ochre panels of mixed tones | wide rolling doors | exposed pipes, jib cranes, caged cyan cores, scrap stacks |
| SAP | ziggurat terraces | stepped roofs with big panels | sand over indigo | armoured slits | buttress braces, paddle sensors |

**Worked example (validated in the proof harness): the 2×2 Generator in eight dialects.** Same plinth, same roof plate, same footprint 6 × 6 m: NAPC cream/olive shed with twin orange-banded stacks and fuel tanks · NEC low sloped hall with a battery row and a 7 m fold-out mast · OLM ring of six copper-framed ivory mirrors around a teal receiver tower with a gold lens · DEF red block with two pale-banded chimneys (7.2 m) and a container stack · PD white dome on a cerulean ring with a coral band and a rooftop drone pad · HAN three shrinking jade modules with porcelain caps, crown and drone rack · AE patchwork shed, exposed pipes, jib crane and a caged cyan core · SAP stepped indigo/sand terraces with corner buttresses and a saffron-rimmed paddle sensor. Eight distinct silhouettes at 27 m and 60 m; pairwise filled-mask IoU 0.66-0.92.

#### 5.9.4 Superweapon landmarks and advanced defences

Superweapons (4×4 = 12 m footprint, plinth 11.5 m; body ≤ 12 m, landmark ≤ 14 m, the render.md near-plane cap). **Charge display:** 8 segments (`floor(charge × 8)` lit, `slot_info.charge`); *ready*: all segments pulse 1 Hz in the accent; *warning* (`EVT_WARNING`): pulse accelerates 1 → 4 Hz, a 3 m light column rises (colour: `WARN` amber for the owner's team, `DANGER` red for hostile viewers), siren cue; *executing* (`EVT_SW_EXEC_START`, then `EVT_SW_IMPACT` per packet): effect recipes in 5.13.4.

| Faction | Landmark silhouette | Description |
|---|---|---|
| NAPC Atlas Kinetic Array | **halo tower** | 14 m lattice mast (olive/cream) carrying an 8 m ring tilted 20° skyward with three emitter rods at 120°; orange hazard collar at the base; ring segments light amber |
| NEC Aurora Microwave Array | **billboard** | white pedestal 10 × 10 × 3 m carrying an 8 × 8 m phased-array panel tilted 55° with a 24-cell amber grid; four fold-out corner masts |
| OLM Helios Reflector | **sunflower** | 9 m ivory heliostat disc with a copper rim on a 9 m teal pylon (top at 14 m when tilted); slender copper arm with a gold receiver; disc slews (TURRET) to the committed line |
| DEF Perun Missile Complex | **gantry silo** | oxide block with silo doors (open in warning) and a 14 m gantry tower showing a pale-banded vertical missile when charged |
| PD Tempest Swarm Hub | **hive tower** | white cylinder 5 m Ø × 12 m with a honeycomb crown of 24 drone bays (coral caps) and a landing ring |
| HAN Dragonfall Field Foundry | **assembly hall** | jade hall 12 × 8 m, crimson gantry arch, three porcelain capsule cradles in a row, chimney crown |
| AE Horizon Mass Driver | **long barrel** | 14 m rail barrel at 25° on a charcoal mount, six cyan capacitor rings lighting base → muzzle; slews to the target azimuth |
| SAP Trident Interception Array | **three masts** | stepped indigo base with three 14 m sensor masts in a triangle, saffron-rimmed paddles; when active a translucent interception ring of radius 18 m (6 cells) is drawn on the ground, visible to all |

Advanced defences (2×2, body ≤ 4.8 m, landmark ≤ 6.0 m):

| Faction | Structure | Silhouette |
|---|---|---|
| NAPC | Bulwark Cannon | long cannon (3.0 m) in an armoured cream/olive casemate with orange lift rings; slow traverse |
| NEC | Lance Rail Emplacement | very long thin rail (4.2 m) over a low white bunker, amber tip |
| OLM | Sunwall Projector | copper prism/lens tower under a teal cowl, gold emitter, heat fins |
| DEF | Citadel Mortar | squat armoured pit, fat mortar tube at 70°, ammunition stacks |
| PD | Sea Spear Battery | white sealed box, six angled tubes with coral caps, small drone pad |
| HAN | Dragon Tooth Launcher | jade tower with six missile "teeth" up-forward, crimson caps |
| AE | Forge Cannon | rapid-cycling turret with a visible ammo drum and cyan cooling collars |
| SAP | Bastion Missile Tower | 6 m stepped tower with a twin-tube launcher on top, saffron caps, paddle sensor |

#### 5.9.5 Neutral structures and resource fields (neutral palette, no plate)

Substation 2×2 (civic grey, pylons, civic-blue trim) · Salvage depot 3×3 (scrap yard with a crane, gunmetal/rust) · Field hospital 2×3 (white tent-hall, civic-blue bar, beacons) · Observation tower 1×1 (lattice tower + cab, 8 m) · Civilian block 3×3 (apartment slab 8 m, garrison slits glow amber when occupied) · Harbor terminal 3×3 (shore only, cranes and container stacks) · **Salvage field** 3×3 (scrap heaps 1.6-2.6 m, glint sprites; 1-4 heaps by richness; depleted = flattened heaps and no glints, `EVT_DEPOSIT_DEPLETED`). A neutral structure being captured shows a 0.4 m progress ring in the capturer's colour (`EVT_CAPTURE_PROGRESS`).

#### 5.9.6 Structure state visuals

| State / event | Visual |
|---|---|
| Placement ghost (owned by `ViewPlacementGhost`) | valid cells `#5CE383` at 35 % alpha on a footprint grid; blocked cells `#FF5555` 35 % **plus a 45-degree hatch and a cross mark per blocked cell** (a state is never colour-only, qa.md V-S02); apron cells hatched `#FFB52A` |
| Build-up (`EVT_STRUCTURE_PLACED`, `F_UNDER_CONSTRUCTION`, 30 ticks = 1.5 s) | the model rises from below the ground inside a scaffold cage (render.md 5.2 BUILDUP: `u_anim.x = (1 - ease(build)) * (height + 1.5)` m), three weld spark emitters at the top edge (`sparks` + `flash`, 0.3 s tick), a ground dust ring (S1) at the start |
| Build-up complete (`EVT_STRUCTURE_ACTIVE`) | cage vanishes, lights flash once, doors cycle, the plate flashes white for 0.3 s (the hit-flash channel `u_state.w`) |
| Damage 66 / 33 % | soot, smoke plume S0 → S1 loop, fire jets < 33 %, cracks |
| `EVT_POWER_SHORTAGE` / `EVT_POWER_RESTORED` (per structure the `F_POWERED` bit) | emissives -80 % over 0.4 s / restore; radar and searchlights decelerate over 2 s; defences show a "no power" glyph |
| `EVT_STRUCTURE_SELLING` (`F_SELLING`), then `EVT_STRUCTURE_SOLD` | reverse of the build-up over the announced duration, dust ring, `+$` UI text at the end |
| `EVT_STRUCTURE_CAPTURED` (core `OWNER_CHANGED`) | plate/pennant cross-fade to the new colour in 0.6 s + white flash |
| Destroyed (`EV_DEATH`) | collapse recipe: tier by footprint (2×2: S3; 3×3: S4; 4×4 and HQ: S5), rubble stain 30 s, wreck-smoke 14 s |
| Repair mode | small wrench glyph (UI) + blue-white welding sparks (S0) every 0.3 s |

### 5.10 Animation principles

1. **Weight sets timing.** Heavier objects: longer ease-in/out, bigger recoil travel, lower frequencies. Light objects: snappy, small amplitude.
2. **The sim drives, the view interpolates.** Animation state is a pure function of interpolated sim state (`u_anim`, `u_aux`, `u_state`); no view-only gameplay timers. Randomness (idle jitter phase) is seeded from the entity id.
3. **Anticipation only where it teaches.** Deploy, fire, and warning states get anticipation; walking and idling do not.
4. **Everything animated is a shader part or a whole-model transform** (single-mesh constraint); secondary motion is limited to the part kinds of render.md 4.2 (TURRET / BARREL and the extra mounts, WHEEL, TRACK, ROTOR, RADAR, LEG / ARM / BODY_BOB, DOOR, BLINK, DEPLOY, DEPLOY_Z, SLIDE_Y, SLIDE_Z) plus the requested SWAY (R-4).
5. **Settle rule:** mechanical transitions end with a damped overshoot of 4 % and a 0.15 s settle (ζ ≈ 0.5); organic transitions (cloth, banners) use SWAY.

#### 5.10.1 Mass classes

| Class | Examples | Turret slew | Hull kick on fire (pitch) | Barrel recoil travel · out / return | Accel pitch · spring |
|---|---|---|---|---|---|
| light | scout, light artillery, drones | 180°/s | 0.4° | 0.05-0.15 m · 35 ms / 180 ms | 1.2° · 3.5 Hz |
| medium | T1/T2 tanks, AA, howitzers | 100°/s (howitzer 45°/s) | 0.6° (howitzer 1.4°) | tank 0.32 m · 50 / 250 ms; howitzer 0.60 m · 70 / 450 ms | 1.0° · 3 Hz |
| heavy | siege tanks, crawlers | 60°/s | 1.0° | 0.45 m · 60 / 350 ms | 0.7° · 2.5 Hz |
| huge | walkers, assault carrier | 40°/s | 0.5° | 0.40 m · 80 / 500 ms | 0.5° · 2 Hz |
| naval | escorts, monitors | 40°/s | roll 0.5° | 0.50 m · 70 / 400 ms | heave 0.05 m · 0.35 Hz |
| structures | defences | tank-like by size | — | as weapon class | — |

Whole-model motion (node transform, cheap): pitch back on acceleration, forward on braking, roll into turns 0.8°, damped spring per the table. Tracks/wheels are locked to roll distance (no sliding).

#### 5.10.2 Recoil and muzzle by weapon archetype family (TAXONOMY §10)

| Family | Archetypes | Muzzle | Recoil | Projectile look |
|---|---|---|---|---|
| Small arms | 0 small_arms, 1 machine_gun, 2 autocannon | 0.4-0.9 m yellow-white flash, 0.07 s | none / 0.05 m | tracer streak |
| Tank guns | 3 tank_cannon, 23 naval_gun | 2.4 m cone + smoke puffs, 0.11 s | 0.32-0.50 m | dark shell with short tracer |
| Siege | 4 siege_gun, 5 demolition_cannon | 3.6 m cone, heavy smoke | 0.45-0.60 m | fat slow shell, dust kick |
| Missiles | 6 at_missile, 7 aa_missile, 18 air_missile, 26 drone_missile | back-blast cone 3 m + white puff | rail slides 0.1 m | white-smoke trail, orange exhaust |
| Artillery | 9 artillery_shell, 11 mortar, 24 naval_bombard | 4-6 m flash + smoke ring | 0.60 m | high arc, dark shell |
| Rockets | 10 rocket_barrage, 12 missile_artillery, 25 cruise_missile | tube flashes in sequence 0.065 s apart | rack shake 0.03 m | thin trails |
| Beams / rails | 13 beam_thermal, 14 rail_gun | lens glow / capacitor flash | rail 0.35 m | 5.13 |
| Bombs / depth | 17 bomb, 16 depth_charge | release puff | — | tumbling dark casing |
| Special | 8 flak, 19 emp_pulse, 20 canister, 21 grenade_launcher, 22 breach_charge, 15 torpedo | flak: 3 m flash, air-burst puff (black-grey with orange core) at the target; others per 5.13 | small | per 5.13 |

#### 5.10.3 Deploy and transform sequences (design targets; driven by `u_aux.y` and `u_aux.w`, 0 → 1)

The render rig has two deploy channels: `u_aux.y` drives every DEPLOY / DEPLOY_Z / SLIDE part, `u_aux.w` drives the barrel elevation (render.md 4.4). Sequences below with more than two stages collapse to two (first stage on `u_aux.y`, second on `u_aux.w`, each eased by the CPU with its own curve); the fractions are the target the curves approximate. Deploy time comes from the def (`deploy_s`, default 3 s).

| Kind | Examples | Sequence (fractions of the deploy time) |
|---|---|---|
| Siege / artillery | Paladin 3 s, Charlemagne 4 s, Gaj 4 s, Monsoon 3 s | 0-30 % spades / outriggers drop and bite; 30-80 % barrel or rack elevates to its deployed angle; 80-100 % settle (4 % overshoot) |
| Missile truck | Saker 1 s, Shaheen 3 s | 0-40 % stabiliser legs; 40-100 % tubes rise 35-55° |
| Sensor mast | Fen carrier, NEC masts | 0-20 % hatch; 20-100 % telescoping mast extends (amber head ignites at 90 %) |
| Command field | Long Command Walker 3 s | outrigger ring drops 0-50 %; crown tines lengthen 50-100 % |
| Cover / shelter | Vanguard 4 s / 2 s pack, Alpine shelter | shield unfolds 0-100 % ; tent poles up 0-60 %, cloth 60-100 % |
| Adaptive turret | Shinano 3 s, Protea 3 s | fold-out siege module rotates up 0-70 %, locks 70-100 %; coral/cyan hinge glow |
| Wings / nacelles | PD fighters, Osprey | fold or tilt over 1.2 s (DEPLOY_Z / DEPLOY hinge parts) |
| Structure doors | Factory, barracks, refinery bay | open 0.8 s ease-out, close 0.8 s ease-in |

#### 5.10.4 Infantry, air, sea

* **Infantry:** walk cycle 0.9 s period locked to travelled distance (no foot slide); fire: arms raise 0.15 s; suppression: kneel; **casualties**: v2 target: soldier tilts to prone over 0.4 s, lies 2 s, dissolves over 1 s; v1 (render.md R18): the member is hidden by hp fraction with a dust puff; garrison/vehicle entry: squad shrinks and fades in 0.3 s. Squad remains readable with 3, 2, 1 soldiers.
* **Aircraft:** banking ≤ 25° (fighters ≤ 35° in hard turns), pitch ≤ 12°; rotor spin-up 1.2 s; gunship hover bob ±0.08 m at 0.5 Hz; takeoff / landing 1.5 s ease; contrails on fighters above altitude 9 m (`puff_white`, 5.5 m, 4.5 s); VTOL nacelles tilt 1.2 s.
* **Ships:** heave 0.05 m (small) / 0.03 m (large) at 0.35 Hz, roll ±1.5° at 0.25 Hz; bow wave and wake sprites scale with speed; submarine dive/surface 2.0 s ease with bubbles; sink (`DK_SINK`, `EV_DEATH`) 3.0 s: draft +2.5 m, tilt 12°, oil slick decal.

#### 5.10.5 Death sequences by `death_kind` (combat.md `DK_*`, carried by `EV_DEATH`)

| DK | Sequence |
|---|---|
| 1 vehicle | flash 0.15 s → explosion by size (light S1, medium S2, heavy/huge S3-S4) → darkened wreck (`damage = 1`, plate neutral) + smoke 14 s |
| 2 infantry | last soldier falls; dust puff S0; no wreck |
| 3 crash | spin 180°/s and fall 1.0-2.5 s with dark trail + fire ribbon, ground impact S3-S4, wreck |
| 4 air explode | mid-air fireball S2, debris shower |
| 5 sink | as ships above |
| 6 structure | collapse recipe 5.9.6 |
| 7 drone | pop S1 + falling debris |
| 8 silent | fade 0.4 s, no VFX |


### 5.11 Faction emblems and subfaction insignia (procedural vector definitions)

#### 5.11.1 Format and interpretation

Emblems are **data** (`style.json → emblems`), drawn by one interpreter for the UI (`UiEmblem`, CanvasItem) and converted to flat polygons for models (`ViewEmblemGeometry`). No bitmaps.

* Coordinate system: unit square, origin top-left, **y down**. Arc angles follow `CanvasItem.draw_arc` (0° = +x, positive = clockwise on screen).
* Ops: `poly` (fill or stroke, closed), `line` (open polyline), `circle` (fill or stroke), `arc` (stroke). All stars, rays and ngons are pre-expanded into `poly`/`line` in the data, so the interpreter needs only four op kinds.
* Widths are fractions of the emblem size, **clamped to ≥ 1.5 px**; strokes are anti-aliased; joins mitred; circles use 40 segments (UI) or 20 (world).
* Colour roles: UI — `c1` = skin accent, `c2` = skin accent2, `dim` = c1 at 35 % alpha, `bg` = `BG_PANEL`. World — `c1` = palette `accent`, `c2` = palette `secondary`, `dim` and `bg` = palette `dark`. The interpreter never receives hex.
* Sub-badge: a disc of 40 % emblem size in the lower-right quadrant (`bg` at 94 % alpha, ring in `c1` 6 % wide) holding the subfaction glyph in its inner 62 %.
* Size ladder: **≥ 96 px** emblem + badge; **48-95 px** emblem + badge; **24-47 px** emblem + **1-3 pips** under it (radius 6 % of size, gap 17 %); **16-23 px** emblem only + pips. Clear space 10 %. Never place an emblem on a team-colour field.

Worked example (NAPC emblem, 4 ops):
```json
[["poly",[0.15,0.08,0.85,0.08,0.85,0.5,0.5,0.95,0.15,0.5],"dim","fill"],
 ["poly",[0.15,0.08,0.85,0.08,0.85,0.5,0.5,0.95,0.15,0.5],"c1","stroke",0.065],
 ["poly",[0.15,0.08,0.85,0.08,0.85,0.21,0.15,0.21],"c1","fill"],
 ["poly",[0.5,0.25, 0.553,0.397, 0.709,0.402, 0.586,0.498, 0.629,0.648, 0.5,0.56, 0.371,0.648, 0.414,0.498, 0.291,0.402, 0.447,0.397],"c2","fill"]]
```

#### 5.11.2 The eight emblems (each has a unique outer silhouette so they separate at 16 px)

| Faction | Silhouette | Content | Ops |
|---|---|---|---|
| NAPC | heater shield (flat top, pointed base) | five-point star + top bar | 4 |
| NEC | open ring of 12 nodes | inner diamond | 14 |
| OLM | open crescent | sun disc with eight short rays | 10 |
| DEF | flat-top hexagon | double chevron | 4 |
| PD | disc | three waves | 5 |
| HAN | diamond | nested diamond + centre dot | 4 |
| AE | ten-ray sunburst | hub + centre dot | 12 |
| SAP | triangle (nested) | inner triangle + apex dot | 5 |

Rendered contact sheets (16/24/32/48/96 px, all 24 badges) were inspected: all eight emblems separate at 16 px; badges read from 48 px; pips read at 24 px. Alternatives rejected in review: a three-arc "signal" mark for SAP (reads as Wi-Fi), WiFi-like arcs for Nordics and Australia, a plain ring-with-ticks for Canada (indistinguishable from Pakistan's crosshair).

#### 5.11.3 Subfaction glyphs (abstract motifs — no flags, national symbols or religious symbols)

| Key | Motif | Sense | Key | Motif | Sense |
|---|---|---|---|---|---|
| napc.usa | swept wing | air mobility | def.north_korea | bunker trapezoid with slit | fortress |
| napc.canada | anchor | littoral | pd.australia | ballistic arc with end marker | long-range fires |
| napc.mexico | three ascending bars | resettled districts | pd.indonesia | three islands | archipelago |
| nec.nordics | four-point star + dot | watch | pd.japan | three hex cells | automation |
| nec.eurocorps | three chevrons | armoured directorate | han.china | square in square | standards |
| nec.alpine_brotherhood | peak with arch | pass and tunnel | han.vietnam | three leaves | canopy |
| olm.saudi_arabia | sun with eight rays | solar directorate | han.cambodia | river S-bend + node | Mekong authority |
| olm.algeria | double rail + arrowhead | corridor | ae.nigeria | three-node triangle | network |
| olm.el_andalus | arch gate + keystone | straits gate | ae.kongo | river fork (Y) | river compact |
| def.russia | three shrinking plates | layered arsenal | ae.south_africa | gear | arsenal union |
| def.kazakhstan | half sun on a horizon + rails | steppe transit | sap.india | six-spoke hub | integrated command |
| sap.thailand | fork (three prongs) | strait command | sap.pakistan | crosshair | observation |

#### 5.11.4 World use

Insignia on models are `ViewEmblemGeometry.stamp` polygons 0.012 m thick, sized per 5.6 (turret cheeks 0.50 m, tail fins 0.60 m, ship bows 0.70 m, structure fascia 1.2-1.6 m, HQ roof 3.0 m), painted with palette roles as above, `mask = 0`, no emissive. They may not sit on a team plate or within its quiet zone.

### 5.12 UI visual language

#### 5.12.1 Principles

*Field terminal*: dark glass consoles with **cut corners** and thin bracket accents; **one accent per faction skin**; numbers in a monospaced face; everything on a 4 px grid; motion short; the world is the star, the HUD is a frame around it. Neutral chrome, saturated only where information lives (accent, state colours, player colours).

#### 5.12.2 Colour tokens (the UI spike's `UiPalette`, promoted to the contract, with one deliberate change)

| token | hex |
|---|---|
| BG_DEEP | `#06080B` |
| BG_PANEL | `#0B1016` |
| BG_RAISED | `#121A23` |
| BG_CONTROL | `#182230` |
| BG_HOVER | `#213145` |
| LINE_DIM | `#212D3B` |
| LINE | `#35465A` |
| LINE_BRIGHT | `#5F7A96` |
| TEXT | `#E6EEF6` |
| TEXT_DIM | `#95A8BB` |
| TEXT_MUTE | `#7A8CA0` |
| TEXT_DISABLED | `#5D6F83` |
| CREDITS | `#FFD35C` |
| OK | `#5CE383` |
| WARN | `#FFB52A` |
| DANGER | `#FF5555` |
| POWER | `#49D0FF` |
| BLACK_A | `#0000008C` |

Change against the spike: its `TEXT_MUTE` (`#5D6F83`, 3.7:1) is renamed `TEXT_DISABLED` (disabled controls and decoration only, WCAG-exempt) and a new `TEXT_MUTE` (`#7A8CA0`) carries secondary captions at 5.5:1 on `BG_PANEL`, so that the automated `test_theme_contrast` of qa.md (every text/background token pair ≥ 4.5:1) passes without exceptions. MEASURED WCAG contrast: `TEXT` 16.3:1 on `BG_PANEL` (11.3 on hover); `TEXT_DIM` 7.8:1 (5.4 hover); `TEXT_MUTE` 5.5:1 on `BG_PANEL`, 5.1 on `BG_RAISED`, 4.6 on `BG_CONTROL` (do not use it on `BG_HOVER`, 3.8; use `TEXT_DIM` there); `TEXT_DISABLED` **3.7:1, never for essential information**; `CREDITS` 13.4; `OK` 11.6; `WARN` 10.8; `DANGER` 6.1; `POWER` 10.7. All faction accents are ≥ 4.9:1 on `BG_PANEL` (DEF 4.9, NEC 6.1, NAPC 7.1). `accent2` is ≥ 4.6:1 on `BG_PANEL` for every skin but drops to 4.2 (HAN) and 4.5 (SAP) on `BG_RAISED`: never use `accent2` for body text on raised panels.

State colours are also encoded by **shape or glyph** (check mark, warning triangle, close cross) because OK / CREDITS / WARN are within ΔE00 5-6 under deuteranopia.

#### 5.12.3 Typography (OFL fonts vendored with licence files)

| Role | Face | Use | Sizes at 1080p (scale with UI scale 75-150 %) |
|---|---|---|---|
| HEAD | Orbitron variable, wght 700, +1 px glyph spacing | headers, menu buttons, big numerals, titles; UPPERCASE | 14 (panel header), 20 (hero button), 40 (title), 56 (logo) |
| BODY | Rajdhani SemiBold | running text, tooltips, lists | 14 small, 15 body, 18 sub |
| BODY_BOLD | Rajdhani Bold | names, button labels | 15 |
| NUM | Share Tech Mono | credits, timers, costs, hotkeys | 15; 34 for the credits counter |

Rules: essential text ≥ 14 px at 1080p (qa.md V-H02), decorative micro-labels ≥ 11 px, no long all-caps text (headers and buttons only; qa.md A-17); an optional Atkinson Hyperlegible replaces BODY / BODY_BOLD from Options → Accessibility; headers UPPERCASE with tracking; body sentence case; numbers always NUM with thousands separators; text shadow (0, 1) black 60 %; no text on the 3D view except world labels ≥ 14 px with a 1 px outline.

#### 5.12.4 Chrome recipe (from the UI spike; all values in `style.json → ui.chrome`)

* **Panel**: vertical gradient `BG_RAISED.lerp(tint, 0.55)` → `BG_PANEL.lerp(tint, 0.25)` at alpha 0.94-0.97; 1 px `LINE` border; diagonal cuts 10 px on two opposite corners; accent bracket corners (12 px, 2 px) on those corners; padding 12/10. Sidebar: 18 px cut at bottom-left with bracket; ribbon: 12 px cuts on all corners, no brackets; inset: 4 px cuts, darker fill.
* **Buttons** (cut 6): normal `#1F2C3C→#141E2B` border `LINE`; hover `#2A3F57→#1A2A3C` border accent + glow accent α 0.22; pressed `#0D141C→#182638` border accent; disabled `#0F151C→#0C1218` border `LINE_DIM`. Accent button: fill `accent.lightened(0.12) → accent.darkened(0.42)`, border `accent.lightened(0.35)`, label `#10161D` (contrast ≥ 5.4:1 on every skin). Hero button: cut 12, HEAD 20 px, α 0.78.
* **Bars**: background inset (cut 3), fill `accent.lightened(0.25) → accent.darkened(0.35)`. Scrollbars 3 px padding, track black 35 %, grabber `accent.darkened(0.35)`. Tooltips: panel α 0.98, cut 8, bracket top-left only.
* **Timing:** hover 90 ms, press 60 ms, panel slide 180 ms, ease cubic-out; alert pulse 1 Hz; credit ticker rolls 300 ms; nothing else animates faster than 2 Hz. "Reduce motion" turns pulses into static highlights.

#### 5.12.5 Faction-tinted HUD skin

`UiSkin(accent, accent2, tint)`: `accent` = borders on hover, tab underline, progress fill, headings; `accent2` = badges and small ticks; `tint` = dark colour mixed into panel gradients (55 % top / 25 % bottom). The skin is per **faction** (subfactions use their parent's skin with the sub glyph in the header). Re-tinting = rebuild the `Theme` (~1 ms).

| faction | accent | accent2 | tint | contrast on BG_PANEL (accent / accent2) |
|---|---|---|---|---|
| NAPC | `#F07F2C` | `#C9D27A` | `#2A2F16` | 7.1 / 11.8 |
| NEC | `#5B93E0` | `#FFB733` | `#14243D` | 6.1 / 11.0 |
| OLM | `#2FC9BB` | `#D9803F` | `#0F2B2C` | 9.3 / 6.5 |
| DEF | `#E0503A` | `#F0DC8C` | `#341612` | 4.9 / 13.9 |
| PD | `#33A0EC` | `#FF7F5C` | `#0F2740` | 6.7 / 7.7 |
| HAN | `#33C98A` | `#E0424F` | `#0F2F22` | 9.0 / 4.6 |
| AE | `#26D6E8` | `#E0AA3C` | `#11292D` | 10.8 / 9.1 |
| SAP | `#F3A622` | `#7A72E6` | `#2C2412` | 9.4 / 4.9 |

Similar accents (NEC / PD blue, OLM / AE cyan-teal, NAPC / SAP orange-amber) are separated by the tint (navy vs teal-navy, deep teal vs blue-teal, olive-brown vs umber), the emblem shape and the faction name in the header; they never appear side by side in the HUD (only in the lobby, where emblems and names label them).

**Relation and health colours** (world-space UI). `SELF #5CE383`, `ALLY #49D0FF`, `ENEMY #FF5555`, `NEUTRAL #FFD35C`; HP ramp `#5CE383` ≥ 66 %, `#FFB52A` 33-66 %, `#FF5555` < 33 % with segment ticks at 33/66 %. Selection geometry is render.md 5.10 (`ViewSelection`): a **ring** under units (radius `max(1.25 × radius_m, 0.9 m)`, stroke 6 %), **corner brackets** around structure footprints (arm length 0.22 × the short side); this spec supplies the colours and the non-colour cue, so colour is never the only signal: SELF solid · ALLY solid + diamond pip at the top · ENEMY four notches + cross pip · NEUTRAL dashed. Health bars are screen-constant (`ViewHealthBars`: 28-72 px wide by size class, 5 px high, 1 px border, background `#06080B` at 70 %, frame in the relation colour), shown for selected / hovered / damaged units. render.md 5.10 hard-codes its own RGB values and 60 / 30 % breakpoints; art asks for the tokens above and the 66 / 33 % breakpoints of `ui.hp_ramp` (equal to the damage stages of 5.8.3), read from `ViewStyle` (request R-20).

**Notifications** (banner stack, spike-verified): DANGER red banner + `MISSILE`/`WARNING` glyph (enemy superweapon detected, base destroyed); WARN amber (base under attack); OK green + `BOLT` (own superweapon charging / ready); INFO in the skin accent (power, tech). Each has a glyph, a bold title and a dim subtitle, 1 Hz border pulse while active.

#### 5.12.6 Iconography

* Glyphs are vector, drawn in the unit square: **24 px grid, 1.8 px stroke** (2.0 at ≥ 32 px), minimum size 16 px, two roles only (main and `main.darkened(0.55)`), no gradients, angular geometry with cut corners.
* Existing set (29): STRUCTURES, INFANTRY, VEHICLES, AIRCRAFT, NAVAL, DEFENSE, POWERS, ATTACK_MOVE, GUARD, STOP, SCATTER, DEPLOY, SELL, REPAIR, WAYPOINT, CREDIT, BOLT, WARNING, CHEVRON_UP, CHEVRON_DOWN, CLOSE, CHECK, LOCK, CLOCK, GEAR, PLUS, MINUS, RADAR, MISSILE. **Additions required by this spec (16):** TANK, ARTILLERY, ANTI_AIR, SCOUT, TRANSPORT, ENGINEER, COLLECTOR, MCV, DRONE, SUBMARINE, CARRIER, SIEGE, COMMAND, CAMO (eye), EMP_OFF (bolt with slash), NO_POWER — used for build-card role overlays, strategic-zoom markers and status icons.
* **Baked unit icons** (`ViewIconBake`, render.md 5.8.10; the UI only displays them): 4:3, recommended 128 × 96 (256 × 192 on high-DPI) for build cards and 384 × 288 for portraits; rig constants in `style.json → ui.icon_rig`, taken from the models spike: model yawed 150° (three-quarter front view), camera pitch 24°, FOV 30°, bounding-sphere framing of `rest_aabb` with margin 0.78, key light euler (-52°, -38°) energy 1.9 `#FFEBC7`, cool fill euler (-30°, 140°) energy 0.45 `#8CB3FF`, MSAA 4×, transparent background, **no cast shadow**, drawn by the UI over its dark plate gradient (`#121A23 → #0B1016`). Team colour = the faction `accent` (icons are faction-branded, so the cache key needs no colour id; measured 19 ms per icon warm, ~0.7 s for a 35-def roster). Tier badge: T2 one chevron, T3 two chevrons, top-right; role glyph bottom-left (UI overlays).
* **Cursors**: 32 px vector, 2 px white stroke with 1 px dark outline; hover tint = relation colour (enemy red, ally cyan, neutral yellow, invalid grey with a slash). Set: default, move, attack, attack-move, guard, deploy, repair, sell, capture, force-fire, scroll ×8, invalid.
* **Minimap** (300 × 300): terrain from the look's terrain set (5.14.3); shroud black, fog dim (5.14.6); blips 2 px dot infantry, 3 px square vehicle, 3 px diamond air, 3 px triangle naval, 4 px outlined square structure, pulsing 8 px star superweapon, all in player colours; camera frustum 1 px white; alert ping = expanding ring in `WARN`, 1 Hz for 3 s.

#### 5.12.7 Accessibility

Contrast ≥ 4.5:1 for essential text (5.12.2); UI scale 75-150 %; high-contrast toggle (panels opaque, lines `LINE_BRIGHT`); reduce-motion; CVD palette (5.4.2); every state has a shape/glyph; all icons ≥ 16 px; tooltips readable for 4 s minimum.

### 5.13 VFX style guide

#### 5.13.1 Principles

1. **Telegraph → hit → aftermath.** Muzzle and projectile visible ≥ 0.2 s before impact; impact reads within 100 ms; aftermath (scorch, smoke, wreck) tells the story for 30-120 s.
2. **Colour temperature is a code:** bullets warm white-yellow · armour-piercing orange · high-explosive deep orange-red with dark smoke · thermal beams faction-hued · rails blue-white · kinetic white-hot · EMP cyan. Shape carries the same information: line (bullet), blob (AP/HE), continuous beam (thermal), instantaneous helix (rail), ring + arcs (EMP).
3. **Size honesty ("ring = truth").** For splash ≥ 3.0 m an additive shock ring expands to exactly the splash radius in 0.35 s. The fireball itself is a visual size (tier table), the ring is the gameplay truth.
4. **Faction tint only on energy effects** (thermal beams, rail streak bias 20 %, interception, construction sparks); other effects stay physically colour-coded so the player learns one language.
5. **Never obscure the plate:** smoke sprites draw behind/around units where possible; fireball alpha ≤ 0.85 after 0.25 s; total overdraw budget below.

#### 5.13.2 Damage-type table (ids == TAXONOMY `DamageType`)

| dtype | key | core | glow | HDR peak | shape |
|---|---|---|---|---|---|
| 0 | bullet | `#FFF3C4` | `#FFC23A` | 6.0 | tracer streak 1.2-2.0 m x 0.06-0.10 m; muzzle flash warm white; impact: dust puff (the look's sand colour) or metal sparks |
| 1 | ap | `#FFE7B0` | `#FF8A1F` | 8.0 | compact orange fireball + hard spark burst; missiles trail white smoke with orange exhaust |
| 2 | he | `#FFDCA0` | `#FF6A1A` | 9.0 | large fireball + AoE truth ring + dust ring + dark smoke column + debris |
| 3 | thermal | `#FFFFFF` | owner faction `emissive` (white-mixed 0.25) | 8.0 | continuous beam (0.9 m wide), white core, faction-hued body, heat shimmer, scorch mark, embers |
| 4 | rail | `#FFFFFF` | `#8FC4FF` | 10.0 | instant helical streak, blue-white; supersonic ring + lens flare; barrel capacitor glow |
| 5 | kinetic | `#FFF6E0` | `#FF8A2A` | 12.0 | orbital slug: sky streak + incandescent sheath, white flash, dust column, expanding ring |
| 6 | emp | `#D8F6FF` | `#58E1FF` | 6.0 | expanding cyan ring + crawling arcs + white sparks; victims flicker cyan |

Details by type:
* **bullet (0):** muzzle cone 0.4-0.9 m `#FFE08A`, 0.07 s; tracer core `#FFF3C4`, 1.2-2.0 m × 0.06-0.10 m at 150 m/s, one tracer per three rounds; impacts: ground = dust puff in the look's sand colour (`terrain.sand_b`, α 0.85) + 2 sparks; metal = 4 sparks `#FFC23A` 0.3 s; infantry = pale puff, no gore; water = 0.6 m splash; structure = chip debris.
* **ap (1):** muzzle cone 2.4 m + two smoke puffs; missiles: white-to-grey smoke trail `#F2F2F2 → #9A9A9A` with orange exhaust `#FF8A1F`; impact = compact fireball (tier), 12 sparks, thin dark smoke; a 0.06 s white-hot flash on armour hits.
* **he (2):** fireball (tier) + additive shock ring at the splash radius + dust ring tinted by terrain + smoke column `#2B2724` for `smoke_s` + debris; scorch mark.
* **thermal (3):** beam 0.9 m wide, white core, body = faction `emissive` mixed 25 % white; emitter flare 2.4 m; impact hot spot 4 m + sparks + embers; heat shimmer along the beam; **focus ramp feedback:** width 0.9 → 1.3 m and colour toward white as damage ramps to 190 %; scorch `#1E1A17` with ember rim `#FF7A2A`. (Only OLM fields thermal weapons today; the rule is generic.)
* **rail (4):** twisted double helix 0.75 m, white core, glow `#8FC4FF`, 0.5 s; capacitor flash (cyan-white) and a supersonic ring at the muzzle; impact = 5 m additive ring, flash, sparks, dust; AE rails bias 20 % toward `#7FE7FF`, NEC rails 20 % toward `#DFF3FF`.
* **kinetic (5):** strategic only. Sky streak 3.2 m wide, 90 m tall, 1.8 s, incandescent sheath `#FF8A2A → #FF4A10`; impact = white flash, dust column, ring, 9 m scorch.
* **emp (6):** ring `#7FE9FF` expands to the radius in 1.15 s; 14 arcs (0.18-0.40 s lifetime) inside 0.9 × radius; disc glow; victims flicker cyan 4 Hz; no camera shake; UI shows the weapons-off glyph.

#### 5.13.3 Scale tiers (`FxStyle.tier_for_splash(splash_units)`; 1 cell = 1024 units = 3 m)

| tier | splash radius (m) | fireball r (m) | core time (s) | smoke (s) | light energy / range / time | shake | scorch r / life | debris | typical sources |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0.0-0.0 | 0.25 | 0.15 | 0.0 | - | 0.0 | 0.2 m / 20 s | 0 | small arms, machine gun, autocannon, beams (per tick) |
| 1 | 0.1-2.2 | 1.6 | 0.45 | 1.2 | 2.2 / 6 m / 0.12 s | 0.05 | 1.2 m / 30 s | 4 | tank cannon, AT/AA/air/drone missiles (splash 0, floor tier 1), naval gun, missile artillery, torpedo hit |
| 2 | 2.2-4.4 | 2.6 | 0.7 | 1.8 | 3.0 / 10 m / 0.16 s | 0.15 | 2.2 m / 45 s | 8 | siege gun, rocket barrage, mortar, grenade, canister |
| 3 | 4.4-6.9 | 3.8 | 1.0 | 2.6 | 4.0 / 14 m / 0.20 s | 0.3 | 3.2 m / 60 s | 14 | artillery shell, naval bombard, bomb, flak airburst, cruise missile |
| 4 | 6.9-10.0 | 5.2 | 1.4 | 3.6 | 5.5 / 20 m / 0.25 s | 0.55 | 4.4 m / 90 s | 22 | demolition cannon, depth charge, heavy bomb, structure collapse (small) |
| 5 | > 10.0 | 8.0 | 2.5 | 6.0 | 14.0 / 80 m / 0.70 s | 1.0 | 9.0 m / 120 s | 40 | superweapon packets, structure collapse (large), aircraft crash |

Tier boundaries in sim units: S1 ≤ 751 (2.2 m), S2 ≤ 1502 (4.4 m), S3 ≤ 2355 (6.9 m), S4 ≤ 3413 (10 m), S5 beyond; splash 0 → S0. Worked example: tank cannon (splash 0.5 cells = 512 units) → S1 (fireball 1.6 m, light 2.2 for 0.12 s, shake 0.05, scorch mark 1.2 m for 30 s); artillery shell (1.6 cells = 1638 units) → S3 (fireball 3.8 m); demolition cannon (2.5 cells = 2560) → S4. Shake is normalised, full within 20 m of the camera focus, zero beyond 60 m. The continuous alternative of render.md 5.9.3, `r = clamp(0.55 · R_m + 0.5, 1, 12)` m, agrees with the tier fireball radius within 27 % from S1 to S4 (1.33 m against 1.6 m at 1.5 m splash, 2.15 against 2.6 at 3 m, 3.14 against 3.8 at 4.8 m, 4.6 against 5.2 at 7.5 m) and differs at S5 (12 m cap against 8 m); the tier table is the art target, check V-2 accepts either within ±25 %, and the shock ring, not the fireball, carries the true radius.

Variants by `EV_IMPACT.hit_kind` (0 ground, 1 unit, 2 structure, 3 air, 4 surface, 5 underwater, 6 wreck): ground = terrain-coloured dust ring; unit = sparks + smoke; structure = concrete-grey debris (`#8A8E90`) + dust; air = fireball only (flak: black-grey puff with orange core); surface = splash + foam + ripple; underwater = bubble column + dull blue flash; wreck = dark spark burst.

#### 5.13.4 Strategic effects (geometry from the bible)

| Weapon | Look | Colours | Scale / timing |
|---|---|---|---|
| Atlas (NAPC) | three vertical white-amber columns descending from the sky, 0.28 s apart | `#FFF6E0`, sheath `#FF8A2A` | columns 3.2 m wide, impact radius 2 cells (6 m), S5 flash + dust ring each |
| Aurora (NEC) | expanding dome + crawling arcs over the 8-cell zone; structures inside flicker | dome edge `#DFF3FF`, arcs EMP cyan | radius 24 m, 4.5 s dome, 18 s shutdown flicker on structures |
| Helios (OLM) | gold-white beam line 16 cells long × 3 wide traversed by a hot spot over 12 s | `#FFF1C0`, `#FFC060` | line 48 × 9 m, scorch trail, heat shimmer |
| Perun (DEF) | single bunker-buster missile from the silo, white smoke, then S5 core + ring | rocket `#FF6A1A`, smoke `#F2F2F2` | core 9 m radius, fragmentation ring to 21 m, dust column |
| Tempest (PD) | 24 drones (0.6 m, white/coral, red running lights) launch from the hub and swarm the 6-cell zone for 20 s | `#F1F4F6`, `#FF6F5B` | zone radius 18 m; individually shootable; approach direction visible |
| Dragonfall (HAN) | three capsules fall with jade-white contrails, unfold over 5 s into siege engines that expire after 60 s | `#7CFFC8`, porcelain | capsule 3 m; landing S3 dust; engines glow jade, fade with sparks |
| Horizon (AE) | three rail impacts along a 10-cell line over 9 s; tan dust haze marks the 20 s debris zone (hatched `#FFB52A` α 0.25 = "no construction") | `#8FC4FF` streaks, dust `#C4AE84` | circles of 3 cells (9 m) |
| Trident (SAP) | translucent interception dome radius 18 m, indigo lattice; each intercept = saffron flash at the boundary + thin line to the projectile | `#5A5FE0`, `#FFC060` | 25 s, 24 charges shown as pips |

**Warning marker** (`EVT_WARNING`, all three kinds `WK_SUPER`, `WK_POWER` for strikes and `WK_SCAN`): ground ring at the exact radius in `WARN` amber `#FFB52A` for the launcher's team and `DANGER` red `#FF5555` with a rotating hatch for hostile viewers (render.md 5.9.5 uses the same convention), countdown ticks; light column 3 m wide, 80 m tall; alarm cue. Never uses the player colour.

#### 5.13.5 Support-power classes (all 48 powers of the bible → 9 looks, `fx.power.<class>`)

| Class (`fx.power.*`) | Powers (bible names) | Look |
|---|---|---|
| Strike (`strike`) | Counterbattery Mission, Tremor Barrage, Counterlaunch Plot | warning ring with hatch at the truth radius (colours of the warning marker, 5.13.4) for the warning time (5 s / 6 s / 5 s), then shells sequenced at S2/S3 (six shells; four waves; shells on the marked positions); Counterlaunch also draws the Mark look on the enemy guns |
| Recon (`recon`) | UAV Sweep, Survey Drone, Maritime Patrol, Recon Balloon | shootable aerial prop (UAV, drone, patrol aircraft flying the 20 × 6-cell corridor, tethered balloon) + translucent sensor disc or corridor in the relation colour, α 0.12 |
| Reveal pulse (`reveal`) | Long Watch, Wideband Scan, Survey Network | thin expanding rings every 2 s with a scan-line wipe; Wideband Scan shows a red pre-warning ring to opponents 2 s before it detects; Survey Network adds a pale glint on salvageable wrecks |
| Repair (`repair`) | Field Repair Drop, Floating Workshop, Mobile Workshop, Expeditionary Workshop, Repair Swarm, Field Refurbishment | prop (station, pontoon, drone station, workshop drop, drone swarm) + rising green-white motes `#5CE383` and a wrench glyph on repaired units; Field Refurbishment adds a "cannot fire" flicker; **no cross symbols** |
| Buff zone (`buff`) | offence: Combined Arms Window, Armored Overwatch, Capacitor Discharge, Straits Crossfire, Precision Window, Software Surge, Assault Coordination · mobility: Coordinated Advance, Open Corridor, Transit Priority, Mobile Reserve · defence: Emergency Earthworks, Redundant Orders, Steel Advance, Joint Landing, Civil Defense Net, Emergency Fortification, Protected Advance · camouflage: Silent Watch | ground ring at the truth radius in the relation colour with faint rising motes; ring pattern by category (offence: outward ticks; mobility: flowing forward chevrons; defence: inner hex lattice α 0.10; camouflage: shimmer on the affected units, 5.13.6) and a 6 px category pip over affected units (up-triangle, arrowhead, shield pentagon: polygons drawn by the world-UI layer, not glyph-atlas icons). Capacitor Discharge and Software Surge end with a grey "cooling" pulse |
| Production / field (`production`) | Rapid Turnaround, Mobilization Order, Recovery Priority, Treaty Coordination, Reserve Bandwidth, Central Priority | no ground zone: the affected structures (Airfield, Barracks, Factory), Engineers / Reclaimers or command-field rings get a pulsing accent ring and sparks for the duration; field powers redraw the field ring in the relation colour at the new radius |
| Smoke (`smoke`) | Dust Screen, Broken Contact, Concealed Crossing | warm-grey volumetric smoke `#C9C6C0` (55 % opacity) with a faint white edge ring at the true radius; Concealed Crossing is a 16 × 4-cell corridor |
| Decoy (`decoy`) | False Convoy, False Front, Feint Landing | normal models including plates; detectors see a thin white dashed outline and the label DECOY |
| Mark (`mark`) | Counterbattery Solution | red crosshair sprite over marked units for the mark duration; the artillery that fired in the last 8 s is revealed with a red ring |

Mapping to the economy.md effect kinds used by render.md 5.9.6: Strike = BOMBARD, Recon = RECON_SUMMON, Reveal pulse = REVEAL_ZONE, Repair = REPAIR, Buff zone = BUFF (19 powers), Production / field = WINDOW + STRUCT_BUFF (render draws a pulse on the HQ plus the HUD timer; this spec adds the faint accent ring on the affected structures), Smoke = SMOKE, Decoy = DECOY, Mark = MARK. render.md tints BUFF auras by theme (damage orange, speed green, defence blue, range violet, camouflage grey); this spec asks for the relation colour plus the ring pattern and the category pip, so the category never depends on hue (RK-27). **Zone kind tints** (`DefZone.zone_kind`, render.md 5.9.7): BUFF relation colour α 0.14 · SMOKE `#C9C6C0` · INTERCEPT `#5A5FE0` lattice with `#FFC060` flashes · DEBRIS `#C4AE84` haze with the amber hatch of "no construction" · DECOY none (the models are the effect) · PUCK cyan `#26D8DD` · SHELTER grey-white `#E6E6E6` · COVER olive-grey `#8A8E7A` · REPAIR `#5CE383` motes · REVEAL relation colour α 0.12.

Unit abilities that reuse a look (the Naga carrier smoke bank, the Echo Team decoy) use the `smoke` and `decoy` recipes. **Catalogue ids** (`style.vfx.catalog`, 78): `fx.muzzle.<family>` (11) · `fx.impact.<dtype>.s<tier>` (18) · `fx.proj.<kind>` (10) · `fx.sw.<weapon>` (8) · `fx.status.<kind>` (6) · `fx.power.<class>` (9) · `fx.death.<kind>` (7) · `fx.env.<kind>` (9). These are **art look keys**, not `pres_fx` ids: `pres_fx` and `fx_override` use render.md's `fx.json` vocabulary, which must cover every key of this list (mapping owned by render, request R-15). Keys are frozen once shipped.

#### 5.13.6 Status, environment and aftermath

* Status: EMP = cyan arcs + flicker 4 Hz; suppression = pale dust flicks; camouflage = shimmer (alpha 0.35 + edge distortion); burning = embers `#FF7A2A` at 5 Hz; interception = saffron flash; construction sparks = white-blue welding (`sparks` + `flash`, 0.08 s tick).
* Vehicle dust: the look's dust colour (`terrain.sand_b`), puff 4.6 m × 2.0 s, α 0.85, emitted every 0.5 m while moving > 1.5 cells/s on non-road terrain. Water: wake and bow wave white `#F5FAFF` α 0.8. Aircraft above 9 m: white contrail (5.5 m, 4.5 s). Crash: dark trail + fire ribbon.
* Persistent marks are painted into the scorch layer (`ViewScorchLayer`, render.md 5.5; no `Decal` nodes anywhere): scorch by tier (radius 0.2-9 m, life 20-120 s, colour `#1E1A17`), rubble stain for collapsed structures 30 s, oil slick for sunk ships 60 s; at most 128 live marks, the oldest fade first.
* **Budgets:** ≤ 12 S3+ explosions in view; overdraw ≤ 6 additive layers; a single S4 effect ≤ 12 % of the screen; no full-screen flash; light flashes ≤ 6 concurrent; particle pool sizes belong to the FX manager and must be re-measured on integrated GPUs (not measured for this document).

### 5.14 Lighting and environment presets

**Terminology.** A **biome** is the map's terrain theme, `MapData.biome`: 0 temperate, 1 desert, 2 arctic, 3 tropical (terrain_movement.md 3.7; the art domain reads it and never writes it). A **look** is one art preset: a lighting mood plus a terrain colour set, ids `LookId` 0-8 (4.1). Every biome maps to one to three looks through the table in 5.14.2, so "presets per biome" means "looks per biome".

#### 5.14.1 The rig (all looks)

* **Key**: one `DirectionalLight3D`, 4-split cascaded shadows (`shadow_max` 110-140 m, bias 0.04, normal bias 1.4), colour/energy per mood. Azimuth 285°-325° with `to_sun = (cos(el)·sin(az), sin(el), cos(el)·cos(az))` and +Z = south: the sun stands **south-west, behind the camera's left shoulder** for the default camera (yaw 0 looks toward −Z), so the faces the player sees are lit and shadows fall up-right, behind the objects. Elevation 44-58° by day (58° overcast), 16-30° for the low-sun moods, 34° for the moon.
* **Fill**: second `DirectionalLight3D`, no shadows, **camera-relative** (yaw = camera yaw + 150°, pitch −30°), cool, energy 0.30-0.55, so no face is ever black when the player orbits.
* **Ambient** from the sky (energy 0.78-1.15), **SSAO** radius 1.0-2.2, intensity 1.4-2.2, glow (soft-light) threshold 1.0-1.2 (0.85 in `night_ops`, where lamps must bloom), **Filmic** tonemap, exposure 1.0-1.7 (night), fog exponential with aerial perspective.
* **Grade** limits: saturation ≤ 1.12, contrast ≤ 1.10, brightness 1.0. A split-toning LUT (render.md 5.6 lift / gamma / gain) is allowed only inside |lift| ≤ 0.03, |gain − 1| ≤ 0.05, |gamma − 1| ≤ 0.05 per channel and is the identity in `studio_neutral`; the fidelity figures in 5.14.4 were measured without a LUT and must be re-run when one is added.
* Water colours per look (shallow / deep / absorb); foam and wakes white.
* **Differences from the terrain spike and from render.md 5.6 (deliberate, listed in section 12, RK-17):** sun azimuth 285°-325° (front-lit, south-west) instead of the spike's 222° (north-west, backlit for the default camera); Filmic instead of ACES; a camera-following fill; look ids and the biome to look table of 5.14.2 instead of render.md's five moods.

#### 5.14.2 The looks (`style.json → looks["look.<name>"]`, ids frozen in 4.1) and the map → look table

| id | look | sun el / az (deg) | sun colour x energy | fill colour x energy | ambient | exposure / white | sat / contrast | fog density |
|---|---|---|---|---|---|---|---|---|
| 0 | temperate_day | 44 / 300 | `#FFF2D9` x1.55 | `#8CB2FF` x0.40 | 0.78 | 1.10 / 5.0 | 1.08 / 1.06 | 0.0011 |
| 1 | arid_day | 52 / 305 | `#FFF0CC` x1.75 | `#9EB8F2` x0.36 | 0.85 | 1.00 / 5.0 | 1.02 / 1.08 | 0.0016 |
| 2 | arid_dusk | 26 / 298 | `#FFDBB2` x1.80 | `#8094F2` x0.42 | 0.95 | 1.10 / 4.6 | 0.98 / 1.08 | 0.0012 |
| 3 | urban_overcast | 58 / 310 | `#EBF0FA` x0.95 | `#B2C7F2` x0.55 | 1.15 | 1.10 / 5.5 | 1.06 / 1.10 | 0.0022 |
| 4 | coastal_morning | 30 / 295 | `#FFE6C2` x1.60 | `#8CB8FF` x0.45 | 0.85 | 1.10 / 5.0 | 1.08 / 1.06 | 0.0018 |
| 5 | tundra_dawn | 16 / 290 | `#FFDBB8` x1.45 | `#CCD4EB` x0.35 | 0.85 | 1.05 / 5.0 | 1.02 / 1.06 | 0.0018 |
| 6 | monsoon_haze | 48 / 302 | `#FFF5DB` x1.20 | `#99C7E6` x0.50 | 1.0 | 1.05 / 5.0 | 1.10 / 1.05 | 0.0026 |
| 7 | night_ops | 34 / 300 | `#A8C2FF` x0.70 | `#738CF2` x0.30 | 0.95 | 1.70 / 5.0 | 1.04 / 1.10 | 0.0020 |
| 8 | studio_neutral | 48 / 300 | `#FFFFFF` x1.45 | `#FFFFFF` x0.30 | 0.85 | 1.00 / 5.0 | 1.00 / 1.00 | 0.0000 |

| look | sky top / horizon | ground horizon / bottom | fog colour | glow / threshold / SSAO | water shallow / deep / absorb |
|---|---|---|---|---|---|
| temperate_day | `#2B61C7` / `#A8C7EB` | `#94A3A3` / `#3D4542` | `#A3C2E6` (aerial 0.35, scatter 0.25) | 0.45 / 1.15 / 1.5 | `#29949E` / `#082E57` / 0.42 |
| arid_day | `#4275CC` / `#D1D6DB` | `#B8A88F` / `#574A3D` | `#D9CCB2` (aerial 0.45, scatter 0.35) | 0.50 / 1.10 / 1.7 | `#479994` / `#0D3352` / 0.48 |
| arid_dusk | `#3D5294` / `#F2B885` | `#9E806B` / `#332924` | `#C7A38C` (aerial 0.40, scatter 0.45) | 0.60 / 1.00 / 1.8 | `#478C8C` / `#0D2142` / 0.50 |
| urban_overcast | `#8594A8` / `#BDC4CC` | `#8C9194` / `#383B3D` | `#ADB8C4` (aerial 0.55, scatter 0.08) | 0.30 / 1.20 / 2.2 | `#336670` / `#0F2438` / 0.55 |
| coastal_morning | `#3875C7` / `#DBD6CC` | `#A8A8A3` / `#424747` | `#C7D1DB` (aerial 0.50, scatter 0.40) | 0.50 / 1.10 / 1.6 | `#339EA8` / `#083361` / 0.40 |
| tundra_dawn | `#708AB2` / `#E6D9CC` | `#CCC9C7` / `#757578` | `#D6D9DE` (aerial 0.40, scatter 0.40) | 0.55 / 1.05 / 1.6 | `#4C8594` / `#0F2947` / 0.50 |
| monsoon_haze | `#5C8CB2` / `#C7D6D1` | `#8C9E8C` / `#334238` | `#A8C7BD` (aerial 0.60, scatter 0.20) | 0.40 / 1.15 / 1.7 | `#388575` / `#0A3342` / 0.55 |
| night_ops | `#080D1F` / `#1A2442` | `#141A29` / `#05080D` | `#0F172B` (aerial 0.30, scatter 0.00) | 0.90 / 0.85 / 1.4 | `#0D2438` / `#030814` / 0.60 |
| studio_neutral | `#9E9E9E` / `#B8B8B8` | `#8C8C8C` / `#595959` | `#B8B8B8` (aerial 0.00, scatter 0.00) | 0.30 / 1.20 / 1.5 | `#338080` / `#0D334C` / 0.40 |

**Choosing the look** (`ViewStyle.look_for_map(map_biome, map_family, night)`, data `style.json → map_look`): deterministic from the two map fields, no RNG. The player may switch **Time of day** in Options → Graphics: *Auto* (the table) or *Night* (the `night_ops` lighting over the terrain set of the map's day look, so a desert map keeps its sand); it is a local, visual-only setting that is not part of the match configuration. `studio_neutral` is selectable only by the QA harness.

| MapData.biome | family 0 open | family 1 urban | family 2 coast_river |
|---|---|---|---|
| 0 temperate | `temperate_day` | `urban_overcast` | `coastal_morning` |
| 1 desert | `arid_day` | `arid_day` | `arid_dusk` |
| 2 arctic | `tundra_dawn` | `tundra_dawn` | `tundra_dawn` |
| 3 tropical | `monsoon_haze` | `monsoon_haze` | `monsoon_haze` |

| look | intent | used for (biome / family) | home factions |
|---|---|---|---|
| `temperate_day` | Default. Clear day, saturated greens, crisp shadows. | temperate / open | NAPC NEC DEF HAN |
| `arid_day` | Bleached noon, high sun, pale sky, heat haze. Hardest for ivory/sand hulls (OLM, SAP) and ochre (AE): keep the dark mass. | desert / open, desert / urban | OLM AE SAP |
| `arid_dusk` | Golden hour, long shadows to the north-east, warm skew. Stylised: hull colours shift strongly (median dE00 13.9) while plate hue drift stays within 6 degrees. | desert / coast_river | OLM AE SAP |
| `urban_overcast` | Flat overcast light, low shadow, high ambient, strong SSAO. Neutral grey ground makes every hue pop; NEC slate blue is the weakest hull. | temperate / urban | NEC DEF NAPC |
| `coastal_morning` | Low soft sun, cool haze; water and sand; hulls skew toward teal, olive NAPC shifts most. | temperate / coast_river | PD OLM AE |
| `tundra_dawn` | Snow, cold blue shadows, low warm sun. Hardest for OLM ivory; shadows are long and blue. | arctic / open, arctic / urban, arctic / coast_river | DEF NEC |
| `monsoon_haze` | Humid green haze, low contrast, teal fog; olive NAPC is weakest. | tropical / open, tropical / urban, tropical / coast_river | HAN PD SAP |
| `night_ops` | Optional time of day. Cool moon key, high exposure; team plates and lamps carry the read. Lighting over the map's day terrain set (temperate when selected directly). | night option | - |
| `studio_neutral` | QA reference lighting: white sun, neutral ambient, no grade. Palette and plate measurements are taken under this look only. | QA only | - |

Any faction may be played on any map: home-faction lists only bias the random map pick and marketing screens.

#### 5.14.3 Terrain colour sets (sRGB; spike palettes for temperate and arid, derived for the rest)

| look (terrain set) | grass a / b | dry a / b | dirt a / b | rock a / b | sand a / b | snow | road |
|---|---|---|---|---|---|---|---|
| temperate_day | `#3D6B1F` `#6B9933` | `#7A6B38` `#9E8C4C` | `#4A3826` `#735940` | `#454240` `#756E66` | `#B8A675` `#DBC996` | `#EDF5FF` | `#4D4E52` |
| arid_day | `#3D661F` `#668F30` | `#8F7547` `#B89961` | `#5C4230` `#85664A` | `#5C4F4A` `#998573` | `#BD9E70` `#E6C794` | `#E6E0EB` | `#57534F` |
| arid_dusk | `#3D661F` `#668F30` | `#8F7547` `#B89961` | `#5C4230` `#85664A` | `#5C4F4A` `#998573` | `#BD9E70` `#E6C794` | `#E6E0EB` | `#57534F` |
| urban_overcast | `#4A5A38` `#63744A` | `#6D6A58` `#8A8670` | `#4B4740` `#6A655B` | `#4A4C50` `#7C7E82` | `#9A9484` `#B5AF9C` | `#E6EAF0` | `#34363A` |
| coastal_morning | `#4F7034` `#79994A` | `#8A7C4A` `#B0A066` | `#5A4834` `#7E6A50` | `#5A5A58` `#8A8880` | `#BFB08A` `#DCCFAA` | `#EEF3F8` | `#4A4B4F` |
| tundra_dawn | `#5C6A4A` `#7C8A66` | `#7A7660` `#9A9680` | `#52483C` `#746858` | `#4A4C52` `#7A7C84` | `#A8A090` `#C8C0AE` | `#F1F5FA` | `#3E4046` |
| monsoon_haze | `#2F5A1E` `#4E8030` | `#6E6A3A` `#8C8850` | `#4A3A2A` `#6A5440` | `#3E4440` `#6A726C` | `#A89C78` `#C8BC96` | `#EAF2F0` | `#3F403F` |
| night_ops | `#3D6B1F` `#6B9933` | `#7A6B38` `#9E8C4C` | `#4A3826` `#735940` | `#454240` `#756E66` | `#B8A675` `#DBC996` | `#EDF5FF` | `#4D4E52` |

Rules for ground colours (enforced by `check_style.py`): chroma ≤ 60 (snow excluded; measured maxima: grass 57, everything else 54) and mean grass chroma ≤ 52; lightness 18-98 (measured 22-97); never a hue within 20° of a player colour at chroma > 55; road is always the darkest, most neutral ground tone (units must never blend into roads). `night_ops` uses the terrain set of the map's day look (the temperate set when selected directly) and `studio_neutral` the temperate set; both change lighting only.

#### 5.14.4 MEASURED look fidelity (8 tanks with the default player colours, Filmic, camera MID-NEAR; hull statistics exclude SAP, whose sampled deck is indigo)

| Look | hull colour shift vs `studio_neutral` (ΔE00, median / max) | team plate authored→rendered ΔE00 (mean / max, HAN excluded) | max plate hue drift |
|---|---|---|---|
| temperate_day | 6.2 / 8.1 | 8.5 / 10.0 | 15° |
| arid_day | 2.2 / 2.9 | 9.4 / 12.2 | 20° |
| arid_dusk | 13.9 / 23.8 | 5.0 / 7.4 | 6° |
| urban_overcast | 4.8 / 7.8 | 8.3 / 9.5 | 14° |
| coastal_morning | 7.7 / 16.5 | 7.1 / 9.1 | 13° |
| tundra_dawn | 14.7 / 16.8 | 8.3 / 16.3 | 17° |
| monsoon_haze | 4.0 / 5.2 | 8.0 / 10.1 | 19° |
| night_ops | 27.7 / 33.1 | 20.3 / 24.9 | 27° |

Acceptance for day looks: plate ΔE00 ≤ 16 and hue drift ≤ 20°; dusk and night are *stylised* and only need every plate pairwise-distinct (≥ 12 rendered ΔE00). Coastal and tundra shift olive NAPC by 16-17 ΔE00: reduce fog or ambient tint before touching palettes.

#### 5.14.5 Known low-contrast pairs and mitigations (MEASURED hull-vs-lit-ground / shadow, ΔE00)

| Pair | ΔE00 lit / shadow | Mitigation (mandatory) |
|---|---|---|
| NAPC on temperate_day | 13.3 / 13.0 | dark undercarriage + cream tiles + orange rail; plates; optional outline |
| NAPC on monsoon_haze | 10.0 / 8.3 | same; monsoon ground stays greyer than temperate |
| NAPC on coastal_morning (shadow) | 28.8 / 7.0 | shadow-side contrast comes from the dark mass |
| NAPC on night_ops | 5.7 / 10.3 | plates and lamps; night is optional |
| NEC on urban_overcast | 11.6 / 14.5 | white roof panels, amber slits, dark under-hull |
| AE on arid_day | 13.6 / 17.2 | charcoal panels and cyan; dark tracks/wheels ≥ 18 % |
| OLM on tundra_dawn | 6.0 / 13.5 | teal fabric screens and dark teal under-hull carry ≥ 25 % |
| All other faction × look pairs | lit ≥ 14 and shadow ≥ 10 | — |

All low pairs are addressed by the **dark-mass rule** (5.3.3) and by the optional **unit outline** (Options → Graphics → Unit outline: off / thin / bold; render domain, request R-16).

#### 5.14.6 Fog of war, shroud and remembered structures

Shroud (unexplored) is black, its edge broken by noise of ±0.175 on the cell state and a `smoothstep(0.32, 0.68)`; fog (explored, not visible): `mix(luma, albedo, 0.45) × 0.42` on terrain and `mix(luma, c, 0.5) × 0.45` on the minimap, both as in the terrain spike shaders; units in fog are not drawn (hidden enemies); remembered structures are desaturated 70 % and darkened to 45 % (render.md `UF_GHOST`); the decor / neutral-structure explored-but-hidden factor is 0.45. Values in `style.json → fog_of_war`.


### 5.15 Do / Don't

**Do**

1. Start from the archetype size card and the faction style dictionary; change proportions, not the grammar.
2. Block big masses first; add **one** memorable protrusion per faction signature; keep ≤ 3 silhouette protrusions.
3. Colour by palette **roles**; ≤ 3 hues plus neutrals; keep the accent ≤ 8 % of the visible area.
4. Bevel every edge; break every flat face larger than 1 m² with seams, pockets or an insert.
5. Put two plates on top-view surfaces, double-gasketed, ≥ 0.45 m, with a quiet zone.
6. Keep the dark mass ≥ 12 % and the light mass ≥ 8 %; light hulls carry ≥ 25 % dark.
7. Give every object a front: lamps, gun, prow, nose; a rear: tail-lights, exhaust.
8. Make the *functional* part big enough to read at FAR: dish, rack, pods, crane, stacks.
9. Show state with shader parameters (damage, selection, deploy, reveal), not extra geometry.
10. Test at MAX and FAR **before** polishing detail; test all eight player colours and the eight faction hulls side by side.
11. Use kit parts from the catalogue for subfaction variants; invent new parts only through this document.
12. Keep emissives small and motivated (lamps, lenses, slits, collars).
13. Bake per-vertex AO and wear flags into the mesh; let the shader do dirt and chipping.
14. Reuse insignia data; keep glyphs abstract.

**Don't**

1. No pure primaries (`#0000FF`, `#FF0000`) and no hull chroma above 45 (team plates and accents must be the most saturated things on screen).
2. Don't paint the player colour into faction paint, or put a plate on bare hull without the gasket.
3. Don't rely on details < 0.1 m for identification; don't place text or numerals under 0.4 m tall.
4. Don't put accent geometry, emissives or greebles within 0.15 m of a plate; don't let a roof gadget cover more than 30 % of a plate.
5. Don't use image textures or bitmap decals; everything is geometry, vertex data or shader.
6. Don't mix faction dialects (no NAPC hull with a HAN crown) unless a kit part says so.
7. Don't exceed the triangle / vertex / emissive budgets (9.2).
8. Don't change silhouettes with damage; damage is soot, embers, smoke.
9. Don't use national flags, religious symbols, real unit designations or real-world political emblems; keep emblems abstract.
10. Don't use mirror-polished metals or high-gloss clear coats (sky reflections shimmer at FAR).
11. Don't encode information in colour alone (CVD): pair with shape, glyph, number or position.
12. Don't hard-code a colour in any widget or recipe; read a token or a role.
13. Don't add bloom-dependent looks: every read must survive with glow off (Low preset); glow threshold ≥ 1.0 in the day moods (0.85 only in `night_ops`) and HDR ≤ 3 on units.
14. Don't add a fifth accent hue to a HUD skin; don't tint the whole HUD with the player colour.

### 5.16 QA review checklist (applicable by an agent looking at screenshots plus log lines)

#### 5.16.1 Screenshot protocol (1920 × 1080, Forward+, MSAA 4×, Filmic; `studio_neutral` unless stated)

| Board | Content | Camera | Output |
|---|---|---|---|
| B1 turntable | one def, 4 yaws (-30, 60, 150, 240), pose "action", azure plate | pitch 20°, framed on `rest_aabb` × 1.1, FOV 30° | `turn_<def>.png` |
| B2 family | the 8 faction variants of one archetype or structure, rest pose, azure | pitch 34°, distance 34 m (structures: 60 m, pitch 40°) | `family_<archetype>.png` |
| B3 matrix | 8 factions × 8 player colours of one archetype, logs `PLATE <faction> <colour> <#plate> HULL <#hull>` | MID, FAR, MAX poses of 5.8.1 | `matrix_<archetype>_<tier>.png` + log |
| B4 look | 8 tanks + 3 squads + a factory in each look, logs `LOOK <look> <faction> <i> PLATE .. HULL .. GROUND .. SHADOW ..` | NEAR/MID | `look_<name>.png`, `looks_sheet.png` |
| B5 silhouette | alpha masks of each faction/archetype, centroid aligned; prints IoU matrix | MID, transparent background | `silh_<archetype>.json` |
| B6 emblems | 8 emblems at 16/24/32/48/96 px + 24 badges + pips | 1:1 | `emblems.png` |
| B7 UI | HUD per faction skin at 1080p, 720p, UI 150 %, low-power state; main menu; lobby | in-game camera | `hud_<faction>_<res>.png` |
| B8 VFX | every damage type × tier strip; 8 superweapon effects; status effects | MID | `vfx_*.png` |
| B9 icons | baked icon sheet per roster in local colour | 256 × 192 | `icons_<roster>.png` |

#### 5.16.2 Checks (each: id, check, method, pass criterion)

**P — palette and colour**

| Id | Check | Method | Pass |
|---|---|---|---|
| P-1 | Dominant colours match the palette roles | B1 under `studio_neutral`: cluster the silhouette pixels; each cluster within ΔE00 ≤ 14 of a role colour (rendered = authored +0..14 L*) | all clusters mapped |
| P-2 | Team plate fidelity | B3 log: authored player colour vs `PLATE` pixel mean | mean ΔE00 ≤ 7, every colour ≤ 10 |
| P-3 | Players distinct | B3 log: 8 rendered plates | pairwise ≥ 15 (default), CVD-simulated ≥ 9 (CVD set) |
| P-4 | No pure primaries, hull chroma ≤ 45 | palette scan of the recipe | 0 violations |
| P-5 | Value spread | B1 luminance histogram of the silhouette | dark (L* ≤ 30) ≥ 12 %, light (L* ≥ 75) ≥ 8 % |
| P-6 | Area mix | pixel classification by role | each role within ±6 points (accent ≤ 8, team 5-12) |
| P-7 | Emissive budget | pixels with luminance > 0.9 and role emissive | ≤ 3 % of the silhouette |
| P-8 | Plate visible and quiet | B1/B3: plate pixels vs expected; nothing accent within 0.15 m | ≥ 70 % visible; 0 violations |

**F — form and faction**

| Id | Check | Method | Pass |
|---|---|---|---|
| F-1 | Size within the size card | measure `rest_aabb` excluding barrels/antennas | L, W, H within ±8 % |
| F-2 | Class cue readable | B3 at FAR: crop 20 px/m | reviewer names the class |
| F-3 | Faction signature parts present | B1: tick the list in the faction card (5.5.x) | all mandatory items present, ≥ 1 visible in the FAR silhouette |
| F-4 | Faction distinguishable | B2 desaturated | reviewer matches 8 tanks to 8 factions |
| F-5 | Copy-paste guard | B5 IoU same archetype across factions | ≤ 0.95 |
| F-6 | Class distinctness | B5 IoU different archetypes in one faction | ≤ 0.80 |
| F-7 | No flat slab > 2 m² | B1 close view + geometry face-area scan | 0 |
| F-8 | Minimum feature sizes | geometry scan of tagged identification parts | ≥ 0.40 m |
| F-9 | Front / rear cues | B1: head-lamps and tail-lights | both present |
| F-10 | Budgets | stats mode | tris/verts/build time within 9.2 |
| F-11 | Subfaction readable | B2 for the roster: unique units differ from replaced ones by ≥ 1 silhouette part; kit parts on shared units | yes |
| F-12 | Insignia legible | B6 + close B1 | emblem shape identifiable at NEAR |

**S — structures**

| Id | Check | Pass |
|---|---|---|
| S-1 | Plinth = `(3·fw − 0.5) × (3·fh − 0.5)` m (render.md 5.1: the model fits inside its footprint with a 0.25 m margin); bollards + chevrons on the south edge | exact |
| S-2 | Door / bay faces +Z; interior strip emissive | yes |
| S-3 | Roof plate ≥ 1.0 m² and ≥ 2.5 % of the footprint (MEASURED on the proof generators: 1.0-2.6 m² = 2.7-7.1 %, HAN 0 % because the crown covered it), pennant where required | yes |
| S-4 | Landmark visible at MAX; height budget 5.7 | yes |
| S-5 | 8 generators (or any structure) read as 8 different factions on B2 | yes |
| S-6 | States: build-up (rise + scaffold), damage, power-off, sell, captured recorded on a strip | all five |

**E — environment**

| Id | Check | Pass |
|---|---|---|
| E-1 | Look fidelity table 5.14.4 reproduced | within ±3 ΔE00 of the published numbers |
| E-2 | Low-contrast pairs (5.14.5) show the mitigation | dark mass ≥ 12 % visible |
| E-3 | Light direction: shadows fall up-right for camera yaw 0; no face is black when orbiting 360° | yes |
| E-4 | Terrain colours inside the ranges (5.14.3) | `check_style.py` |
| E-5 | Roads are the darkest ground tone | yes |

**U — UI**

| Id | Check | Pass |
|---|---|---|
| U-1 | Tokens equal `style.ui.tokens` | unit test |
| U-2 | Contrast of essential text | ≥ 4.5:1 (mute text only on disabled) |
| U-3 | Font sizes | essential ≥ 14 px at 1080p |
| U-4 | Skin per faction applied to borders, bars, headers only | screenshot |
| U-5 | Glyphs legible at 16 px; icons carry tier chevrons and role glyph | B9 |
| U-6 | No colour-only state | each state has glyph/shape |
| U-7 | HUD at 720p and UI 150 % has no overlap or clipping | B7 |

**V — VFX**

| Id | Check | Pass |
|---|---|---|
| V-1 | Colour by damage type (hue of core/glow within ΔE00 ≤ 20 of the table) | yes |
| V-2 | Tier matches splash (fireball radius within ±25 % of the tier, 5.13.3) | yes |
| V-3 | Shock ring reaches the splash radius | ±5 % |
| V-4 | Budgets: S3+ ≤ 12 in view, overdraw ≤ 6, S4 ≤ 12 % of the screen | yes |
| V-5 | Plate remains ≥ 50 % visible during effects at HP ≥ 33 % | yes |
| V-6 | No full-screen flash | yes |
| V-7 | Superweapon warning uses the relation colour, never the player colour | yes |

**AN — animation**

| Id | Check | Pass |
|---|---|---|
| AN-1 | Recoil travel and timing per 5.10.1 | ±20 % |
| AN-2 | Deploy phases per 5.10.3 with 4 % overshoot | yes |
| AN-3 | No foot / track slip | contact distance drift ≤ 2 % |
| AN-4 | Door 0.8 s; radar 30°/s; build-up 1.5 s (30 ticks) | ±10 % |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

**Commands: none consumed, none emitted.** Art direction has no sim presence (DR-12); `players[].color` is a lobby/config integer that the sim ignores.

**Events consumed (read-only, presentation).** Codes and layouts are those of the block owners, as fixed by the `docs/spec/sim_core.md` 6.2 registry: core events 1-8 (sim_core), **200-229 combat** (combat.md 6.2), **230-259 abilities** (abilities.md 6.2), **300-499 economy / production / power** (economy.md 6.2). Field letters follow each owner's table. Where two owners emit a similar event (sim_core 6.4 C lists them) the art rule is the same for whichever survives. The rules attach to the *meaning* of each event: if the reconciler renumbers or renames events again, only this table changes (render.md 6.2.3 keeps an alias table between the proposals and an earlier hexadecimal catalogue).

| Event (code) | Fields used | Style rule applied |
|---|---|---|
| `SPAWNED` (1) / `REMOVED` (2) | id, kind, `def_idx`, owner, facing, `reason` (SPAWN_PRODUCED, PLACED, DEPLOYED, SUMMONED, WRECK; REM_KILLED, SOLD, EXPIRED, DEPLOYED, CONSUMED) | node creation and removal; PLACED / DEPLOYED structure: build-up (5.9.6); SUMMONED: arrival; SOLD: reverse build-up; EXPIRED: fade 0.4 s |
| `OWNER_CHANGED` (3) | id, old, new, reason | plate and pennant cross-fade 0.6 s + white flash |
| `EV_FIRE` (200) | shooter, weapon idx, `mount \| barrel \| projkind \| result \| burst` (c), target, aim x / y | muzzle look by `DefWeapon.dtype` and TAXONOMY archetype (5.10.2, 5.13.2); recoil per mass class (5.10.1) |
| `EV_PROJ_SPAWN` (201) / `EV_PROJ_END` (202) | serial, projectile idx, kind, flight ticks, end x / y; end reason (expired, APS, zone, instant, sweep done) | projectile look and trail (5.10.2); interception flash on reason APS / zone |
| `EV_IMPACT` (203) | warhead idx, `hit_kind`, splash radius (units), total damage | tier = `FxStyle.impact_tier(kind, splash)`; surface variant by `hit_kind` (5.13.3); shake from tier |
| `EV_HIT` (204) | victim, damage, `dtype`, flags (killed, suppression, EMP), hp after, hp_max | hit flash (`u_state.w`), damage stage from hp / hp_max (5.8.3) |
| `EV_BEAM_START` / `EV_BEAM_END` (205 / 206) | shooter, weapon, mount, target, max ticks | thermal beam recipe with faction tint (5.13.2) |
| `EV_SWEEP` (207) | A, B, duration, delay, width | Helios hot spot (5.13.4) |
| `EV_DEATH` (208) | entity, def idx, `death_kind`, cause, flags (wreck, crash, decoy, structure, aircraft), facing, layer, `visual_ticks` | death sequence by `death_kind` (5.10.5), explosion tier by size class |
| `EV_WRECK_ADD` / `EV_WRECK_REMOVE` (209 / 210) | wreck id, source def, expiry tick | wreck look (dark, neutral plate), smoke 14 s, last 1.5 s sinks |
| `EV_INTERCEPT` (211) | serial, interceptor, kind (APS, zone, packet) | saffron flash (SAP), APS pod flash |
| `EV_SUPPRESS` (212), `EV_EMP` (213), `EV_WEAPON_LOCK` (220) | victim, duration, kind | status looks (5.13.6) and glyphs; the same states are readable as flags (below) |
| `EV_AIR_STATE` (215), `EV_REARM` (216), `EV_DRONE` (217), `EV_CRASH` (219) | aircraft, state, pad, carrier / drone, bay | gear, nacelle and rotor animation (5.10.4); rearm sparks; drone launch arcs; crash trail |
| `EV_CLOAK_CHANGED` (230), `EV_DECOY_IDENTIFIED` (255) | entity, concealed / revealed, reason | shimmer in / out (5.13.6); decoy outline (5.13.5) |
| `EV_GHOST_ADDED` / `EV_GHOST_REMOVED` (232 / 233) | structure, group, def | remembered-structure look (5.14.6) |
| `EV_MODE_STARTED` (234) / `EV_MODE_CHANGED` (235) | entity, slot, target mode | deploy and pack sequences (5.10.3) |
| `EV_FX_APPLIED` (238) / `EV_FX_REMOVED` (239), `EV_BUFF_APPLIED` (259) | entity, fx idx, expiry tick; power idx, entity count | buff-zone ring and category pip (5.13.5) |
| `EV_LOADED` / `EV_UNLOADED` (240 / 241), `EV_GARRISON_CHANGED` (243) | passenger, carrier, occupants | squad shrinks and fades 0.3 s (5.10.4); lit garrison windows |
| `EV_ZONE_SPAWNED` (246) / `EV_ZONE_ENDED` (247) | zone id, zone kind, owner | smoke, repair, decoy, intercept and reveal zone looks (5.13.5) |
| `EV_SUMMONED` (248), `EV_SUMMON_EXPIRED` (249) / `EVT_SUMMON_EXPIRED` (410) | entity, parent, flags | summon arrival and fade-out; engine assembled (257), swarm launched (256) use the Dragonfall and Tempest recipes (5.13.4) |
| `EV_SCAN_WARNING` (250) | power idx, radius, owner | Wideband Scan pre-warning ring for opponents (5.13.5) |
| `EV_SALVAGE_DONE` (251), `EV_CAPTURE_DONE` (252), `EV_REPAIR_PULSE` (254), `EV_MARKED` (258) | salvager, structure, target, mark | weld sparks and `+$`; capture flash; repair motes; red crosshair mark (5.13.5) |
| `EVT_STRUCTURE_PLACED` (303) / `EVT_STRUCTURE_ACTIVE` (304) | pid, entity, `s_idx` | build-up rise with scaffold, 30 ticks / activation flash (5.9.6) |
| `EVT_CREDITS_GAINED` (308) = core `CASH` (4), `EVT_SALVAGE_PAID` (328) | pid, amount, x, y | floating `+$` in `CREDITS` |
| `EVT_POWER_SHORTAGE` (311) / `EVT_POWER_RESTORED` (312) | pid | emissives -80 % over 0.4 s / restore; radar decelerates 2 s; per structure the `F_POWERED` bit |
| `EVT_STRUCTURE_SOLD` (314) / `EVT_STRUCTURE_SELLING` (315) | entity, end tick | reverse build-up over the announced duration |
| `EVT_REPAIR_STATE` (316), `EVT_HQ_DEPLOYED` (317) / `EVT_HQ_UNDEPLOYED` (318) | entity, on / off | wrench glyph and weld sparks; MCV to HQ unfold (5.10.3, 2.0 s) |
| `EVT_DEPOSIT_DEPLETED` / `EVT_DEPOSIT_REGROWN` (322 / 323), `EVT_CAPTURE_PROGRESS` (324), `EVT_STRUCTURE_CAPTURED` (326) | deposit idx; leading pid, entity, progress bp | field visual state; capture ring 0.4 m in the capturer's colour; plate cross-fade |
| `EVT_POWER_ACTIVATED` (402), `EVT_WARNING` (404), `EVT_SW_EXEC_START` (407), `EVT_SW_IMPACT` (408), `EVT_SW_DONE` (409) | power / superweapon def, warning id, `WK_*` (SUPER, POWER, SCAN), x, y, angle, radius, damage type | support-power class looks (5.13.5); warning marker in the relation colour for all three warning kinds; superweapon recipes (5.13.4) |

**Read every frame from the entity instead of an event** (`SimEntity.flags`, sim_core 4.3): `F_CLOAKED` (shimmer), `F_DEPLOYED` / `F_DEPLOYING`, `F_UNDER_CONSTRUCTION` (build-up), `F_POWERED`, `F_SELLING`, `F_REPAIR_ON`, `F_WEAPONS_OFF` and `F_EMP_SHUT` (EMP look), `F_SUPPRESSED` (infantry crouch), `F_GARRISONED`, `F_DECOY`, `F_SUMMONED`, `F_TEMPORARY`, `F_FIRING`, `F_MOVING`, `F_AIRBORNE`, `F_ON_WATER`. Nothing new is needed for these; the timers behind them (EMP, suppression, last hit) live in combat's component and are not read by this domain.

**What other domains must add or guarantee** (full list in section 13): (a) `DefWarhead` / `DefWeapon` carry `dtype`, `splash_radius`, projectile kind (already in combat.md) and *optional* `fx_override` ids that must exist in `style.vfx.catalog` if used; (b) `MapData.biome` and `MapData.family` exactly as published by terrain_movement.md (no new field); (c) `DefFaction.pres.palette` and `DefRoster.pres_palette` resolve to `style.json → palettes`; (d) `DefUnit.archetype` is readable by the view (size card lookup); (e) the sim_core 6.4 C overlaps (`EV_SUMMON_EXPIRED` 249 / `EVT_SUMMON_EXPIRED` 410, `EV_CAPTURE_DONE` 252 / `EVT_STRUCTURE_CAPTURED` 326, `EV_SALVAGE_DONE` 251 / `EVT_SALVAGE_PAID` 328) keep the variant that carries position and owner; the art rule is the same for either.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.1 `game/data/recipes/style.json` — top level

```
{ "schema": "meridian.style/1", "version": 1, "notes": [...], "faction_order": ["napc", ...],
  "palettes": { "palette.<code>": {...}, "palette.<code>.<sub>": {...} },  "neutral_palette": {...}, "shared_colors": {...},
  "sub_accent_rule": {...}, "kit_parts": { "<id>": "text" }, "kit_applies": { "<id>": ["veh", ...] }, "unique_units": { "unit.<id>": {...} },
  "player_colors": {...}, "team_plate": {...}, "size_classes": {...}, "cell_m": 3.0,
  "archetypes": { "<id>": {...} }, "structures": { "<key>": {...} }, "camera_tiers": {...},
  "style_kits": { "tank_medium": { "<code>": {...} } }, "emblems": {...},
  "ui": { "tokens", "type", "chrome", "skins", "icon_rig", "relation", "hp_ramp", "selection" },
  "vfx": { "damage_types", "tiers", "status", "budget", "faction_tint_bias", "colors", "catalog" },
  "lighting_rig": {...}, "fog_of_war": {...}, "looks": { "look.<name>": {...} }, "map_look": {...}, "thresholds": {...} }
```

### 7.2 Worked entries (real values from the file)

```json
"palette.napc": { "id": "palette.napc", "faction": "faction.napc", "code": "NAPC", "name": "North American Peace Corps",
  "primary": "#465229", "secondary": "#DBCFA6", "accent": "#F0621A", "dark": "#262E19", "emissive": "#FFB55A", "emissive_alt": "#FF7A1A",
  "metal": "#4A4F4B", "glass": "#22404A", "rubber": "#151515", "light": "#FFE6B0", "team_key": "#C6C6C6",
  "area_mix": {"primary": 0.52, "secondary": 0.16, "dark": 0.20, "accent": 0.05, "team": 0.07},
  "shader": {"wear": 0.45, "dirt": 0.45, "panel": 0.65, "wear_color": "#C9C3A8", "dirt_color": "#3A3020", "emissive": 2.5},
  "panel_m": 0.9, "bevel_m": 0.045, "greeble_per_m2": 0.35, "chamfer": "45deg-medium",
  "ui": {"accent": "#F07F2C", "accent2": "#C9D27A", "tint": "#2A2F16"}, "lch": {...} }

"palette.napc.usa": { "id": "palette.napc.usa", "parent": "palette.napc", "accent": "#C54600", "sub_index": 1,
  "band": "checker", "glyph": "napc.usa", "kit": ["lift_ring", "nav_light_bar", "winglet_tips"] }

"archetypes": { "mbt_t1": { "size_class": "medium", "radius_cells": 0.55, "class_radius_cells": 0.55, "length_m": 3.5, "width_m": 1.95,
  "height_m": 2.0, "length_cells": 1.17, "width_cells": 0.65, "team_area_min_m2": 1.0, "altitude_m": 0, "soldiers": 0, "note": "..." } }

"structures": { "factory": { "footprint_cells": [3, 3], "footprint_m": [9.0, 9.0], "body_h_m": 4.2, "landmark_h_m": 7.0, "note": "..." } }

"player_colors": { "default": [ {"id": 1, "key": "azure", "hex": "#2C86F0"}, ... ], "cvd": [...], "assign_order": [1,0,2,3,4,5,6,7], "metrics_authored": {...}, "metrics_rendered": {...} }

"vfx": { "tiers": [ { "tier": 3, "splash_m": [4.4, 6.9], "fireball_r_m": 3.8, "dur_s": 1.0, "smoke_s": 2.6, "light": [4.0, 14.0, 0.2], "shake": 0.3,
  "scorch_r_m": 3.2, "scorch_life_s": 60, "debris": 14, "examples": "artillery shell, ..." } ] }

"looks": { "look.temperate_day": { "id": 0, "label": "Temperate day", "sun": {"elevation_deg": 44, "azimuth_deg": 300, "color": "#FFF2D9", "energy": 1.55},
  "fill": {...}, "sky": {...}, "ambient_energy": 0.78, "fog": {...}, "tonemap": {"mode": "filmic", "exposure": 1.1, "white": 5.0},
  "grade": {...}, "post": {...}, "water": {...}, "terrain": {"grass_a": "#3D6B1F", ...} } }

"emblems": { "factions": { "napc": [ ["poly", [...], "dim", "fill"], ... ] }, "subs": { "napc.canada": [ ["circle", 0.5, 0.17, 0.1, "c2", "stroke", 0.07], ... ] } }
```

### 7.3 Recipe header fields this spec requires (recipe format owned by the render domain, render.md 7)

Each `game/data/recipes/<recipe id>.json` (render.md 7.3) additionally carries: `"size_card": "<id in style.archetypes | style.structures>"` (render's own `"archetype"` field names the *view* archetype, so the art field is called `size_card` to avoid the clash), and uses palette keys only (`"base"`, `"acc"`, ...; no `#rrggbb`). The roster `style` (`napc`, `napc.canada`, ...) is resolved from `palette.<code>[.<sub>]` (data_balance `pres.palette`); kit-bash parts arrive as style `slots` named `kit_<id>` (5.6.5). `"pres_scale_bp"` stays 10000 (12500 only for `large` style tags, render.md request 7). The validator cross-checks: `size_card` exists; every `kit_<id>` slot exists in `style.kit_parts` and lists the archetype's family in `kit_applies`; bounding box within 8 % of the card; palette keys only.

### 7.4 Registry ids defined by this file (for `V-REF-02`-style checks)

`palette.<code>`, `palette.<code>.<sub>`, `look.<name>`, `kit part ids`, `archetype ids`, `structure keys`. `DefFaction.pres.palette` = `palette.<code>` (data_balance §7.13); a roster may set `pres_palette` = `palette.<code>.<sub>`; if absent, the loader derives it (`palette_for_roster`).

### 7.5 UI data

`ui.tokens` (5.12.2), `ui.type`, `ui.chrome`, `ui.skins` (8 entries), `ui.icon_rig`, `ui.relation`, `ui.hp_ramp`, `ui.selection`. `UiPalette` constants and `UiSkin` table must be generated from or asserted against these (test U-1).

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

* **Nothing in this domain enters `SimWorld.checksum()` or any sim/net/data hash.** Style data lives in `view/`, `ui/`, `data/recipes/`; the fields `pres_recipe`, `pres_palette`, `pres_icon`, `pres_fx`, `pres_scale_bp` are excluded from the data-version hash (data_balance §7.15). Two clients with different style files (mod, corruption) stay in sync; they only look different. `ViewStyle.data_hash()` is for QA and screenshots and is **never** sent over the network.
* **DR-1/2/3/4/5:** not applicable to presentation code, but `FxStyle`/`ViewStyle` never read `SimRng`, `delta`, or sim state; VFX randomness comes from a view-local `FxRng` seeded from `entity_id ^ event_tick` so replays look identical run-to-run (cosmetic determinism, not required by the sim).
* **DR-12/DR-15:** all style lookups are one-way (sim events → style → pixels). Player colour ids arrive from `MatchConfig.players[].color` (an int index) and are never written back.
* **Cross-platform look:** hex → `Color` conversion is exact (`Color.html`); ΔE checks are executed in Python (tools) and the GDScript test only compares stored metrics, so there is no float-platform divergence in CI. Emblem geometry uses `Geometry2D`/plain arithmetic in view code only.
* **Headless:** `ViewStyle` must load and validate under `godot --headless` (no rendering server needed) so `tools/gd test` covers it on every platform, including the Debian container.


---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

### 9.1 Runtime cost of this domain

| Item | Cost | Reasoning / mitigation |
|---|---|---|
| Sim tick | **0** | no sim presence (section 8) |
| `ViewStyle.load_file` | ~2 ms once, ~114 KB JSON, ~1 MB resident | one `JSON.parse_string` + typed record build; failure path is fatal in dev |
| Palette / size / tier / token lookup | O(1) dictionary or array index, < 1 µs | all accessors return cached objects |
| `team_uniform` + `set_instance_shader_parameter` | 0.4-1.1 µs per call (spike), only at spawn and colour change | 400 units = 0.3-0.9 ms once per spawn wave, not per frame |
| `FxStyle.impact_tier` / `colors` | < 1 µs | per event; combat caps cosmetic `EV_FIRE` at 128/tick |
| `UiEmblem.draw_ops` | ~12 primitives per emblem; a HUD with 30 emblems ≈ 360 draw ops ≈ 0.05 ms | cache to a `ViewportTexture`/`ImageTexture` atlas if a screen shows > 60 emblems (lobby lists) |
| Emblem geometry on models | ≤ 60 triangles per emblem; ≤ 4 per model | tier 1 primitives, dropped at LOD1 |
| Materials | 1 `ShaderMaterial` per palette in the match (≤ 8 vanilla, ≤ 8 with sub variants); zero textures | instance uniforms keep batching (spike: 400 mixed units = 42 draw calls with shadows, 14 without) |
| Icon baking (`ViewIconBake`, render.md 5.8.10) | 19 ms per icon warm (2.7 s for the first icon on a cold Metal shader cache), 0.8 ms readback | bake the local roster (≤ 35 icons ≈ 0.7 s) during loading; cache PNGs in `user://cache/icons/` keyed by content hash + size (icons are faction-branded, so no colour id in the key) |
| Model build (`ViewModelBuilder`, render.md 5.8.1) | ~0.7 µs per vertex, 2.5-10 ms per model (spike, quiet machine; 2× under load) | ≤ 8 rosters × ~40 models ≈ 1.9 s worst case, hidden by the loading screen; threaded and optionally disk-cached by render.md |

### 9.2 Per-model budgets (checked by F-10 and the recipe validator)

The triangle caps are the **lower of this spec's proof measurements and render.md 5.8.2** (which enforces them in `test_view_recipes`); vertices follow the spike ratio of 2.9 vertices per LOD0 triangle (LOD copies included) and VRAM is 52 B per vertex.

| Family | LOD0 triangles | Vertices | Build time | VRAM | Spike reference |
|---|---:|---:|---:|---:|---|
| Infantry squad | ≤ 1,400 | ≤ 4,000 | ≤ 5 ms | ≤ 210 KB | 1,216 tris, 3.0k verts, 3.3 ms |
| Light vehicle (scout, APC, light artillery) | ≤ 3,500 | ≤ 9,500 | ≤ 7 ms | ≤ 500 KB | APC 2,984 tris, 8.3k verts |
| Medium vehicle (tanks T1/T2, AA, artillery) | ≤ 5,000 | ≤ 14,500 | ≤ 11 ms | ≤ 760 KB | tank 4,750 tris, 14.0k verts, 9.9 ms; howitzer 4,010 tris |
| Heavy / siege | ≤ 6,500 | ≤ 18,500 | ≤ 14 ms | ≤ 960 KB † | — |
| Huge (walker, assault carrier) | ≤ 8,000 | ≤ 23,000 | ≤ 16 ms | ≤ 1.2 MB † | — |
| Fixed-wing aircraft | ≤ 3,000 | ≤ 8,500 | ≤ 6 ms | ≤ 440 KB | — |
| Helicopter / tiltrotor | ≤ 3,500 | ≤ 9,500 | ≤ 7 ms | ≤ 500 KB | gunship 1,836 tris |
| Patrol boat / small ship | ≤ 2,000 | ≤ 5,500 | ≤ 5 ms | ≤ 290 KB | patrol boat 954 tris |
| Escort / submarine | ≤ 5,000 | ≤ 14,500 | ≤ 10 ms | ≤ 760 KB | — |
| Large ship (siege, carrier) | ≤ 8,000 | ≤ 23,000 | ≤ 16 ms | ≤ 1.2 MB † | — |
| Structures 1×1-2×2 | ≤ 3,000 | ≤ 8,500 | ≤ 8 ms | ≤ 440 KB | — |
| Structures 3×3 | ≤ 5,000 | ≤ 14,500 | ≤ 15 ms | ≤ 760 KB | factory 2,450 tris, 6.6k verts, 6.3 ms |
| Structures 4×3, 6×3 (airfield) | ≤ 8,000 | ≤ 23,000 | ≤ 16 ms | ≤ 1.2 MB † | — |
| Superweapons 4×4 | ≤ 10,000 | ≤ 29,000 | ≤ 20 ms | ≤ 1.5 MB † | — |

† render.md 5.8.2 states "per-model VRAM ≤ 900 KB", which the rows marked † exceed at 52 B per vertex; either the cap is raised for them to 1.5 MB (request R-28) or these families are held to about 17,000 vertices (5,900 triangles) — the reconciler decides, the art content is unaffected because silhouette and plate come first.

Whole-frame target: 400 mixed units at LOD1 ≈ 1.4 M primitives (spike: 2.43 M → 1.41 M with LODs). Total resident mesh memory for a full 8-roster match ≤ 110 MB (render.md: ≤ 120 MB; spike: ~110 MB for 250 models at full detail). LOD keys: render.md 4.3 (`0.02` ≈ 31 m and `0.06` ≈ 94 m at 1080p).

### 9.3 Quality presets (art features only; every downgrade is capability-guarded, never OS-guarded)

MSAA, shadows, SSAO, glow, scaling and renderer clamps belong to render.md 4.9 / 7.7 (`quality.json`); this table lists only what the art domain asks of each preset.

| Feature | Ultra | High | Medium | Low (integrated GPU target) |
|---|---|---|---|---|
| Unit shader `quality` (procedural noise) | 1.0 | 1.0 | 1.0 | 0.0 (render.md: −14 % at 4K) |
| Emblem geometry on models | all | all | tier 1 only | off (colour band only) |
| Scorch marks (`ViewScorchLayer`, no Decal nodes) / debris scale | 1.0 | 1.0 | 0.7 | 0.4 |
| VFX overdraw layers | 6 | 6 | 4 | 3 |
| Renderer | Forward+ | Forward+ | Forward+ / Mobile | Mobile / Compatibility (batch backend; see RK-8) |

Palettes, plates, silhouettes and emblems are identical at every preset: **readability never depends on quality**.

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

### 10.1 Unit tests (`game/tests/unit/test_view_style.gd`, run by `tools/gd test view_style`)

| # | Case | Expected |
|---|---|---|
| T1 | `ViewStyle.load_file()` | non-null; 8 palettes, 24 sub palettes; 36 archetype cards; 22 structure cards; 9 looks; 78 fx catalogue ids; 24 sub glyphs; 8 emblems; 63 kit parts; 48 unique units |
| T2 | `palette("napc").primary` / `.accent` / `.team_key` | `#465229` / `#F0621A` / `#C6C6C6` |
| T3 | `palette_for_roster("roster.napc.canada").accent`, `.sub_index`, `.band` | `#FF504A` (the parent accent `#F0621A` at hue -18°), 2, `waterline`; vanilla roster → sub_index 0 |
| T4 | `palette_for_roster("roster.xxx.unknown")` | `null` and one `push_error` |
| T5 | `player_color(1)` / `player_color(2, true)` / `player_color_count(false)` / `(true)` | `#2C86F0` / `#86C280` / 12 / 8 |
| T6 | `team_uniform(1)`, `team_uniform(1, false, 0.5).w` | `Vector4(0.1725, 0.5255, 0.9412, 0.0)` ± 0.003, `0.5` |
| T7 | `default_color_for_slot(0..7)` | `[1, 0, 2, 3, 4, 5, 6, 7]` |
| T8 | `archetype("mbt_t1")` | `length_m 3.5, width_m 1.95, height_m 2.0, radius_cells 0.55, team_area_min_m2 1.0` |
| T9 | `structure("factory")` | `footprint_cells [3, 3]`, `body_h_m 4.2` |
| T10 | `FxStyle.tier_for_splash` for 0, 512, 751, 752, 1638, 2560, 3414 | 0, 1, 1, 2, 3, 4, 5 |
| T11 | `FxStyle.impact_tier(PK_MISSILE, 0)`, `(PK_BULLET, 0)`, `(PK_STRIKE, 0)` | 1, 0, 5 |
| T12 | `look(0).mood_name`, `look("look.night_ops").sun_energy`, `look_count()`; `look_for_map(0, 1)`, `look_for_map(1, 2)`, `look_for_map(2, 0, true)` mood names | `"temperate_day"`, 0.70, 8; `"urban_overcast"`, `"arid_dusk"`, `"night_ops"`; all 12 (biome, family) cells return a look with id 0-7 |
| T13 | every emblem / glyph op has all coordinates in [−0.05, 1.05] and a valid kind | true |
| T14 | `UiEmblem.draw_ops` into transparent `SubViewport`s of 96 / 24 / 16 px for each of the 8 emblems, white ink | alpha > 0.3 coverage between 15 % and 75 % at 96 px and between 15 % and 85 % at 16 px (MEASURED at 96 px: AE 21.6 %, NEC 26.0 %, OLM 28.5 %, HAN 53.1 %, SAP 51.9 %, NAPC 55.7 %, PD 68.0 %, DEF 68.4 %; at 16 px: 21.9 %-79.7 %) |
| T15 | `UiPalette` constants vs `ui_token(name)` | identical for all 18 tokens (U-1) |
| T16 | two loads → `data_hash()` equal; mutated copy → hash differs | true |
| T17 | headless load (`--headless`) | passes on macOS, Linux container |
| T18 | `kit_part_applies("riot_shield_rack")`; for each of the 48 unique units every kit part lists the unit's family (`veh`/`ship`/`air`/`inf`) | `["inf"]`; true |

### 10.2 Validator tests (`tools/py/tests/test_check_style.py`, stdlib `unittest`)

Positive: shipped `style.json` exits 0 and prints the metrics table (default set min ΔE00 22.6; CVD set min 20.8 / 14.5 / 13.8 / 13.5; faction primaries min 13.9). Negative mutations (each must exit 1 with the named message): bad hex; `area_mix` sums 0.98; player colour pair ΔE00 < 20; CVD pair < 13.4; size card violating `L/2 ≤ 1.3 r` ; structure body above `0.9 × short side`; landmark above `1.45 × short side`; UI token text contrast < 4.5; terrain chroma > 60; emblem coordinate 1.2; missing kit part id; missing sub glyph; duplicate look id; `map_look` naming an unknown look; a kit part used on a family it does not list; a structure landmark above the render cap (8 / 12 / 14 m).

### 10.3 Visual / scenario tests (`game/tests/visual/art_boards.tscn`, screenshots through `tools/gd shot`, logs through `art_report.py`)

Reference numbers to reproduce (MEASURED with the proof harness; tolerance ±1.5 ΔE00 unless noted):

| Test | Expected |
|---|---|
| V1 swatch probe (flat team plate, Linear tonemapper, emission-only) | rendered = authored ± 3 levels per channel with the `Vector4` path (e.g. `#2C86F0` → `#2988F1`); the `Color` path must **fail** the probe (`#063CE0`) |
| V2 matrix 8 × 8 at MID, Filmic | authored→rendered mean ΔE00 5.4, max ≤ 10; rendered default plates pairwise min ≥ 15 (measured 17.4) |
| V3 CVD matrix | mean 5.4, max ≤ 8; simulated pairwise min ≥ 9 (measured 9.9 deutan) |
| V4 look boards | table 5.14.4 within ±3 ΔE00; hull-vs-ground table 5.14.5 within ±3 |
| V5 silhouette (tank, generator) | tank IoU 0.73-0.94 (max ≤ 0.95); generator 0.66-0.92 |
| V6 emblem sheet | 8 emblems separable at 16 px by eye; pips visible at 24 px |
| V7 family boards | reviewer completes F-4 (match 8 desaturated tanks to factions) with no errors |
| V8 HUD boards per skin | contrast checks U-2, no clipping at 720p and UI 150 % |
| V9 VFX strips | V-1..V-7 |

### 10.4 Determinism and regression

* `ViewStyle.data_hash()` is golden-file tested (`game/tests/fixtures/style.sha256`); changing `style.json` requires updating the hash in the same change (prevents silent art drift).
* A test asserts `FxStyle`/`ViewStyle` never reference `SimRng`, `delta`, or `Time.` (lint request R-25).
* Icon cache key includes the style hash, so any palette change invalidates icons automatically.
* CI runs `tools/py/check_style.py` on every change touching `game/data/recipes/**` or `docs/spec/art_direction.md`.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

| Task | Files owned | Size | Depends on | Acceptance |
|---|---|---|---|---|
| **ART-1 Style core** | `game/src/view/view_style.gd`, `view_palette.gd`, `view_mood_def.gd`, `game/tests/unit/test_view_style.gd` | ~650 lines | `style.json` (delivered with this spec) | T1-T9, T12, T16-T18; `tools/gd check` clean |
| **ART-2 Validator** | `tools/py/check_style.py`, `tools/py/tests/test_check_style.py` | ~600 lines Python | none | 10.2 positive + all negative mutations; wired into `gd check --lint-only` data step |
| **ART-3 Emblems** | `game/src/ui/ui_emblem.gd`, `game/src/view/view_emblem_geometry.gd`, tests T13-T14 | ~500 lines | ART-1; the render `ViewMeshBuilder` API for `stamp` (ASSUMPTION(render)) | T13, T14; B6 sheet equals the reviewed one (8 emblems, 24 badges) |
| **ART-4 FxStyle** | `game/src/view/fx_style.gd`, tests T10-T11 | ~300 lines | ART-1 | T10, T11; V9 strips use only catalogue ids |
| **ART-5 QA harness** | `game/tests/visual/art_boards.gd` + `.tscn`, `tools/py/art_report.py` | ~1,300 lines GDScript + ~350 Python | ART-1; render domain (recipes) for B1-B3/B5; UI domain for B7; ART-3 for B6; ART-4 for B8 | reproduces 10.3 V1-V6 numbers on the spike models; boards B1-B9 documented in `docs/STATUS.md` |
| **ART-6 Pipeline conformance** | `game/tests/visual/team_probe.gd`; patch list to `ViewModelRig` / `ViewUnitBackend` (owned by render) | ~200 lines | render domain implements R-1 | V1 passes (Vector4) and a deliberate `Color` build fails |
| **ART-7 UI integration** | `UiSkin.from_style` (patch in UI-owned file), `game/tests/unit/test_ui_tokens.gd`, icon rig constants test | ~350 lines | UI domain; ART-1 | T15; icon sheet B9 matches 5.12.6 rig |
| **ART-8 Mood conformance** | `game/tests/visual/mood_probe.gd` (+ patch list to `ViewAtmosphere`) | ~300 lines | render domain (`ViewAtmosphere`), map domain; ART-1 | for i in 0..7: measured sun direction equals the formula; V4 within tolerance; `look_for_map` covers all 12 cells |
| **ART-9 Gold standards** | recipes (content designers): per faction the T1 tank, an infantry squad, the 2×2 Generator and one unique unit (32 recipes) | content | render domain (recipe format), ART-1..ART-5 | each passes 5.16 checks P, F, S; used as reviewers' reference |
| **ART-10 Style review gate** | `docs/STATUS.md` section "Art review", PR template line | small | ART-2, ART-5 | every recipe PR attaches B1/B2/B3 and the report |

Order: ART-1 and ART-2 first (unblocks everyone); ART-6 immediately after the render domain lands `ViewModelRig`; ART-9 gates the content wave.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| RK-1 | **Spike shader defect** (`Color` instance uniform linearised twice) silently darkens and hue-shifts every team colour by ΔE00 up to 22.7. `render.md` 4.4 states the opposite of the measurement ("values are not sRGB-converted by the engine") | R-1 plus test V1; correct render.md 4.4; record in ARCHITECTURE §8 (amendment AM-1) |
| RK-2 | Tonemapper or light-rig changes shift the palettes (ACES: +3.3 mean ΔE00 against Filmic) | palettes verified only under Filmic + `studio_neutral`; any change re-runs V2-V4; render.md 5.6 selects ACES, see RK-17 |
| RK-3 | Subfaction identity on the 11 shared units is weak at FAR | the 48 unique-unit silhouettes carry it; kit parts, bands and pips at close zoom; F-11 gate; if playtests fail, add a 0.3 m sub-coloured pennant to all sub units |
| RK-4 | Low-contrast faction × look pairs (NAPC on grass, OLM on snow, AE on sand) | dark-mass rule (mandatory) + optional unit outline R-16; table 5.14.5 is the watch list |
| RK-5 | The default player set is not CVD-safe (rendered deutan min ΔE00 6.2) | CVD set + always-on redundancy (numbers, shapes); lobby hint from `plate_contrast`; qa.md's CVD ≥ 12 test runs on the CVD set |
| RK-6 | 185 models by 8 designers drift apart | one shared grammar, parametric kits, ART-9 gold standards, ART-2 / ART-5 automation, review gate |
| RK-7 | Per-roster mesh variants (accent geometry) cost build time and RAM | render's disk cache; if too slow adopt palette-slot paint (COLOR.r = role index, shader lookup) later, no change to this spec's data |
| RK-8 | The Compatibility renderer is darker and has no auto-instancing (spike) | compat multipliers as render.md 5.6 (`compat_grade`); start: ambient × 1.3, sun × 1.15, exposure × 1.1, unmeasured, verify with V4 under `--rendering-method gl_compatibility`; batch backend |
| RK-9 | Footprint and radius discrepancies between specs: airfield 6×3 vs 4×3, anti-tank turret 1×1 vs 2×2, ship radii 1.3 / 1.5 vs class 1.4 | models read `fw × fh` from the def; `style.json` follows economy.md footprints and balance unit radii; the reconciler decides, `check_style.py` constants are updated in one place |
| RK-10 | Cultural / political sensitivity of insignia | abstract motifs only (5.11.3), no flags or religious symbols (qa.md V-IP1); review list; sub glyphs are replaceable data |
| RK-11 | Fonts: licence files and coverage | vendor OFL texts with the TTFs (the UI spike ships Orbitron, Rajdhani and Share Tech Mono with OFL files); the optional Atkinson Hyperlegible (qa.md A-17) needs its OFL text too; Latin only |
| RK-12 | 14 m superweapon landmarks occlude ground and cost triangles | landmark ≤ 15 % of footprint area, ≤ 10,000 triangles (render.md), tier-1 / tier-2 detail dropped at LOD |
| RK-13 | Night readability | optional time of day, plates carry the read, never the default; V4 includes it |
| RK-14 | AE accent variants only ΔE00 6.5 apart | AE subfactions differ chiefly by band and kit; F-11 verifies |
| RK-15 | The proof harness is not in the repo | ART-5 rebuilds it; published numbers have tolerances, and `style.json → thresholds` keep margin (plate max 10 against measured 8.8) |
| RK-16 | `net.md` carries its own `srgb` hex for lobby colour ids 0-7 (`D93A3A`, `2F7DE1`, `2DB56A`, `F2B234`, `8B5CD6`, `27C4D6`, `F0782A`, `D9479B`) that differ from `style.player_colors` (ids 8-11 are identical) | ids and keys are the contract, the hex is not: net reads the hex from `style.json` (R-21); until then the `net.md` values are placeholders and the game renders `style.json` |
| RK-17 | **Looks and lighting differ from render.md 5.6 / 7.6**: five moods (`temperate_day`, `arid_dusk`, `arctic_day`, `tropical_day`, plus `urban_night` for urban temperate maps) chosen by `ViewMoodDef.for_map(biome, family, moods, night_allowed)`; ACES; sun azimuths 200°-222° (north-west, backlit for the default camera); split-toning LUT. This spec: eight looks plus a QA reference, Filmic, sun 285°-325° (front-lit), camera-following fill, bounded LUT, table in 5.14.2 | the art looks are authoritative for *values*; `moods.json` is generated from `style.json → looks` (field map in R-9) and `ViewMoodDef.for_map` is the same function as `ViewStyle.look_for_map` (one survives, the table of 5.14.2 wins). If the reconciler keeps ACES, V2-V4 must be re-run: plate error rises from mean 5.4 / max 8.8 to 8.7 / 11.2, above the threshold of 10 |
| RK-18 | **Two style sources**: render.md 4.10 / 5.8.4 define `styles.json` (palette keys base, dark, sec, acc, metal, rubber, glass, light, plate, concrete; `team_plate` band / panel / none; an `emblem` string) and call the merged Dictionary `ViewStyle`, which is also the class name of this spec's loader | `styles.json` palette blocks are generated from `style.json` through the alias table of 4.5 (tool `gen_recipe_styles.py`), emblems come from `style.emblems`, subfaction kit parts are style `slots`; rename render's record (`ViewStyleDef` or plain Dictionary) so `ViewStyle` names one class |
| RK-19 | **Player colours**: render.md 5.8.4 / 5.12 makes `ViewTeamColors` use the `net.md` lobby hex for ids 0-11 (`#D93A3A`, `#2F7DE1`, ...) and an Okabe-Ito set (`#0072B2`, `#E69F00`, `#56B4E9`, `#009E73`, `#F0E442`, `#D55E00`, `#CC79A7`, `#F2F2F2`) for the three colour-blind modes. MEASURED minimum pairwise ΔE00 (normal / protan / deutan / tritan) of ids 0-7: net.md hex 20.6 / 6.3 / **1.5** / 8.5; Okabe-Ito 21.7 / 12.2 / 11.6 / 10.9; this spec's default set 22.6 / 8.5 / 9.0 / 8.7; this spec's CVD set 20.8 / 14.5 / 13.8 / 13.5. qa.md `test_team_colour_delta_e` needs ≥ 20 normally and ≥ 12 under each simulation | ids and keys are the contract, the hex is not: `ViewTeamColors.color(id)` reads `style.player_colors` (default set for `NORMAL` and `HIGH_CONTRAST`, the CVD set for `PROTAN`, `DEUTAN` and `TRITAN`; one safe set covers all three, so the three modes may share it), and `contrast_against` is `plate_contrast`. Render's shape pips per player index (circle, triangle, square, diamond, cross, hexagon, star, bar) are adopted as the fifth redundancy cue (5.4.2). Only the CVD set passes the qa.md rule |
| RK-20 | **Biome to look mapping** is defined twice: render.md 5.6 (biome 0 to `temperate_day`, 1 to `arid_dusk`, 2 to `arctic_day`, 3 to `tropical_day`; urban family on biome 0 to `urban_night`) and 5.14.2 here (desert open / urban to `arid_day`, desert coast to `arid_dusk`, urban temperate to `urban_overcast`, coast temperate to `coastal_morning`, night as a local option). All specs now agree on the `MapData.biome` enum (0 temperate, 1 desert, 2 arctic, 3 tropical) | keep one table: the one of 5.14.2 (it was measured; a desert map by day should not default to dusk); render's `biome_to_mood` and `family_override` JSON blocks are generated from `style.json → map_look` (R-12) |
| RK-21 | **Structure build-up**: render.md draws it as a rise out of the ground inside a scaffold cage (no reveal channel is needed in the shader) | render.md adopted as is; this spec fixes only colours, sparks and timings (5.9.6) |
| RK-22 | **Numeric conflicts with render.md 5.8.2**: triangle caps, VRAM 900 KB per model, structure heights, team-masked area (4-12 % vs 5-12 %), and a model-radius test (±15 % of 1.05 r) that the art cards *and render.md's own size table* violate for elongated units (scouts +18 %, collectors +10 %, ships +7-16 % over the band) | lower triangle caps and the render height caps (8 / 12 / 14 m) adopted (9.2, 5.7); the 5-12 % team share satisfies both; the art cards keep the footprint rule `L/2 ≤ 1.3 r · 3 m`; the reconciler relaxes the render radius test to the footprint rule for wheeled units and ships; VRAM cap request R-28 |
| RK-23 | **VFX size**: render.md 5.9.3 computes the fireball radius continuously (`r = clamp(0.55 R_m + 0.5, 1, 12)`), this spec's tier table is discrete | they agree within 27 % from S1 to S4 (S1 low end worst) and differ at S5 (tier 8 m against a 12 m formula cap); the tier table is the target, V-2 accepts ±25 %, and the shock ring conveys the true radius anyway |
| RK-24 | **World-space UI values**: render.md 5.10 hard-codes selection colours, health-bar RGB and 60 / 30 % breakpoints, order-line colours, the gold `+$` floater `(1.0, 0.85, 0.25)` and one colour per placement-ghost cell reason (green, red, orange, magenta, yellow, cyan: colour only) | tokens and the 66 / 33 % breakpoints of `style.ui` win (the floater uses `CREDITS`); order lines keep render's palette, which is not a relation colour; ghost cells add the hatch and cross cues of 5.9.6; `ViewSelection`, `ViewHealthBars` and `ViewPlacementGhost` read the values through `ViewStyle` (R-20) |
| RK-25 | **QA gates in qa.md**: `test_team_colour_delta_e` (≥ 20 normal, ≥ 12 under each CVD simulation), `test_theme_contrast` (all pairs ≥ 4.5:1), V-H02 (fonts ≥ 14 px at 1080p), V-S02 (placement ghost readable without colour) | the CVD ≥ 12 rule is run on the CVD set (the only one that passes, RK-19) and ≥ 20 on both sets (RK-5); `TEXT_MUTE` re-tuned and `TEXT_DISABLED` added (5.12.2); type scale raised to 14 px; blocked ghost cells hatched and crossed (5.9.6) |
| RK-26 | **Event contract**: sim_core.md 6.2 fixes the blocks (core 1-8, combat 200-229, abilities 230-259, economy 300-499) and folds `EVT_CREDITS_GAINED`, `EV_CMD_REJECTED` and `EVT_ORDER_FAILED` into core events; a few facts are announced twice (`EV_SUMMON_EXPIRED` 249 / `EVT_SUMMON_EXPIRED` 410, `EV_CAPTURE_DONE` 252 / `EVT_STRUCTURE_CAPTURED` 326, `EV_SALVAGE_DONE` 251 / `EVT_SALVAGE_PAID` 328) | section 6 lists the events by the block owners' names and codes; the art rule is the same for whichever duplicate survives (R-27) |
| RK-27 | **VFX vocabulary**: render.md 5.9.5-5.9.7 colours warnings 'hostile red, own launch amber' and tints BUFF auras by theme (damage orange, speed green, defence blue, range violet, camouflage grey); its `fx.json` ids (`muzzle_small_arms`, `expl_small`, `hit_bullet`, ...) differ from this spec's `vfx.catalog` keys | warnings adopt render's colours through tokens (`DANGER` hostile, `WARN` own team, 5.13.4); buff auras use the relation colour with a ring pattern and category pip per category (colour-blind safe), the theme hues are optional secondary tints; `vfx.catalog` keys are *art looks that must exist*, not `pres_fx` ids: the render domain maps each key to effects of its `fx.json` (R-15) |
| OQ-1 | Separate HUD skins per subfaction? | No: parent skin + glyph; pips only in small sizes |
| OQ-2 | Change player colour mid-match? | No (baked into instances at spawn; lobby only) |
| OQ-3 | Are lobby ids 8-11 needed? | Keep as optional extras; remove without touching anything else |
| OQ-4 | Per-faction terrain sets? | No: the terrain set follows the look; factions never repaint the world except their own structures' plinths |
| OQ-5 | Player-coloured or faction-branded build icons? | Faction-branded (accent), as render.md 5.8.10: one icon per def, no colour id in the cache key |
| OQ-6 | Is night a per-map or a per-player option? | Per player: a local Options → Graphics setting (*Time of day: Auto / Night*), visual only: it never enters the match configuration or the sim, and every peer may render a different look |

### Amendments proposed to `docs/ARCHITECTURE.md` (for the reconcilers)

| # | Section | Proposed text |
|---|---|---|
| AM-1 | §8 | "Team colour is passed to `u_team` as a `Vector4` of raw sRGB (w = cloak level); passing a `Color` to an instance uniform is a defect (it is linearised by the engine and again by the shader)." |
| AM-2 | §8 | "The project tonemapper is Filmic; every palette value in `game/data/recipes/style.json` is verified under it." |
| AM-3 | §2 / §7 | "Presentation ids `palette.*`, `look.*` and `fx.*` are owned by `game/data/recipes/style.json`; `pres_*` fields refer to them and never enter a hash." |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

Class names are those of `docs/spec/render.md` (the peer spec written in parallel), of `docs/spec/sim_core.md` (master events and flags) and of `docs/spec/terrain_movement.md` (`MapData`). Requests marked *no change needed* record a point that the peer spec already covers; the numbers are kept so that references stay valid.

**render: rig, materials, shaders (`ViewModelRig`, `ViewUnitBackend`, `ViewMeshBuilder`, `ViewMaterials`, `unit.gdshader`)**

1. **R-1 Team uniform fix (blocking).** In `ViewModelRig.setup(m, mat, team)`, `ViewUnitBackend.add(...)` / `set_team(...)` and the node backend's `P_TEAM` write, convert the `Color` to `Vector4(c.r, c.g, c.b, cloak)` (raw sRGB, w = cloak level 0..1) before `set_instance_shader_parameter`; correct render.md 4.4. `ViewStyle.team_uniform(color_id, cvd, cloak)` returns exactly that. The batch backend's plain material uniform `mm_team` (no `source_color` hint) needs no change. Alternative: declare `instance uniform vec4 u_team : source_color;` and delete `v_team = to_lin(team)` in the vertex stage. Acceptance: test V1.
2. **R-2 One palette source.** `styles.json` palette blocks are generated from (or validated against) `style.json` with the alias table of 4.5 (`base` = `primary`, `sec` = `secondary`, `acc` = `accent`, `plate` = `dark`, `concrete` = `neutral_palette.primary`); three new palette keys for render: `emissive`, `emissive_alt`, `team_key`. The model cache key stays `recipe@style#scale` (render.md 5.8.1), so a subfaction style builds its own variants; optional: emit accent-role primitives in a separate index range so subfaction styles can share the rest.
3. **R-3 Plate and emblem macros.** Extend `team_panel(center, size, col?)` to the three-layer plate of 5.4.3 (gasket `dark` +0.08 m beyond the field, hairline `#E6E6E6` +0.04 m, field `team_key` mask 1.0; heights +0.009 / +0.013 / +0.027 m; structures × 1.4) and add `emblem(id, center, normal, up, size_m)` that calls `ViewEmblemGeometry.stamp` with palette colours (`c1` = accent, `c2` = secondary, `dim` and `bg` = dark, mask 0).
4. **R-4 Shader addition (one).** New part kind **25 SWAY** (cloth, pennants, antenna whips, windsocks): `p += sin(fx_time · ω + phase) · amp · height_factor`, amplitude from `extra`, phase from `param`, `ω` fixed per kind; global `fx_time` only, so no per-instance write. Nothing else is needed: folding wings, vanes, ramps and outriggers use render.md's DEPLOY / DEPLOY_Z hinges, construction uses its BUILDUP rise with scaffold, and two-stage sequences use `u_aux.y` for the hinge and `u_aux.w` for the barrel with different CPU curves.
5. **R-5 Squad readability (no change needed, kept as a constraint).** render.md 4.2 already hides gait members by hp fraction; art asks only that member 0 is never hidden while the entity lives and carries the squad insignia.
6. **R-6 Materials.** `ViewMaterials.unit_material(style_id, variant, team_index)` receives the `ViewPalette.material_style()` values (wear, dirt, panel, wear_color, dirt_color, emissive strength, `quality`); exactly one material per style (and per team index on the batch path), never per instance.
7. **R-7 Frame metadata (no change needed).** `ViewModelInfo.rest_aabb`, `height` and `radius` of render.md 3.5 are sufficient.
8. **R-8 LOD.** Emblem geometry and plate hairlines are tier 1 (dropped at LOD2); the gasket and the field exist at every LOD so the plate never disappears.

**render: atmosphere, terrain, quality (`ViewAtmosphere`, `ViewMoodDef`, `ViewTerrain`, `ViewFogOfWar`)**

9. **R-9 Looks.** `ViewAtmosphere.apply_mood(m: ViewMoodDef)` implements the fields of 4.3 and 5.14.1: sun direction `to_sun = (cos el · sin az, sin el, cos el · cos az)` with the azimuth range 285°-325°, **camera-following fill light** (yaw = camera yaw + 150°, pitch −30°, no shadows), tonemapper **Filmic**, exposure and white point per look, fog and aerial perspective per look, grade limits and the bounded LUT of 5.14.1. `moods.json` is generated from `style.json → looks` (field map: `sun.elevation_deg` → `sun_elevation_deg`, `sun.azimuth_deg` → `sun_azimuth_deg`, `sun.color` / `energy`, `sky.top` → `sky_top`, `sky.horizon`, `sky.ground_horizon`, `sky.ground_bottom`, `ambient_energy`, `fog.*` → `fog_color` / `fog_density` / `fog_sun_scatter` / `fog_aerial`, `tonemap.exposure` / `white` → `exposure` / `white_point`, `grade.*`, `post.glow_intensity` / `glow_hdr_threshold` → `glow_intensity` / `glow_threshold`, `post.ssao_intensity`, `water.*`, `terrain.*` → the `palette{grass_a … snow_c}` block with `snow` = `snow_c`).
10. **R-10 Terrain colours.** Terrain, water and decor shaders read `ViewMoodDef.terrain`; roads stay the darkest, most neutral ground tone; the chroma limits of 5.14.3 hold.
11. **R-11 Fog constants.** `style.fog_of_war` (terrain fog `mix(luma, albedo, 0.45) × 0.42`, minimap fog `mix(luma, c, 0.5) × 0.45`, black shroud, ghost look, explored-but-hidden factor 0.45), identical to the terrain spike shader.

**map (`MapData`, terrain_movement.md 3.7)**

12. **R-12 Map theme (no new field).** Read `MapData.biome` (0 temperate, 1 desert, 2 arctic, 3 tropical) and `MapData.family` (0 open, 1 urban, 2 coast_river) exactly as published; the view calls `ViewStyle.look_for_map(biome, family, night)` (table in 5.14.2, data `style.json → map_look`), deterministic and float-free on the input side. render.md's `ViewMoodDef.for_map` and its `biome_to_mood` / `family_override` blocks are generated from the same table (RK-20).

**data / balance / combat**

13. **R-13 Presentation ids.** `DefFaction.pres.palette = "palette.<code>"`, optional `DefRoster.pres_palette = "palette.<code>.<sub>"` (data_balance §7.13); `DefUnit.archetype` and `DefUnit.tier` readable by the view; `pres_scale_bp` stays 10000 unless a `large` / `compact` style tag says otherwise (the 1.25 infantry scale is applied by the render archetype, never twice).
14. **R-14 Reconcile discrepancies**: airfield 6×3 vs 4×3; anti-tank turret 1×1 vs 2×2; ship radii 1.3 / 1.5 vs size class 1.4; neutral structure names differ between economy.md and data_balance.md; combat.md still seeds `DT_EXPLOSIVE` / `DT_BEAM` while TAXONOMY freezes `AP` / `HE` / `THERMAL`. Art follows TAXONOMY and the economy.md footprints until told otherwise.
15. **R-15 FX ids.** `pres_fx` / `fx_override` strings on `DefWarhead` / `DefWeapon` / `DefZone` use render.md's `fx.json` vocabulary (5.9.2, 7.5), validated by V-REF-02; the keys of `style.vfx.catalog` are the art looks that vocabulary must cover (each key maps to one or more `fx.json` ids, table owned by render); tier and colour otherwise derive from `dtype`, splash radius and projectile kind. Guarantee that `EV_FIRE.b` (weapon idx) and `EV_IMPACT.a` (warhead idx) resolve to defs carrying `dtype`.

**render options and UI**

16. **R-16 Unit outline.** Optional readability outline (off / thin / bold; qa.md A-15 asks for unit outlines in the high-contrast mode): inverted-hull `next_pass` on the unit material (smoothed normals in `UV2`, as noted in the spike) or a screen-space edge pass; gated by the quality preset; default thin on Medium and above.
17. **R-17 Tokens and skins.** `UiSkin.from_style(style: ViewStyle, faction_code: String) -> UiSkin`; `UiPalette` constants generated from or asserted against `style.ui.tokens` (18 tokens, `TEXT_MUTE` re-tuned, `TEXT_DISABLED` new); `UiTheme` chrome numbers from `style.ui.chrome`; type scale from `style.ui.type` (14 px minimum).
18. **R-18 Glyphs and cursors.** Add the 16 glyphs of 5.12.6 to `UiGlyphs`, the cursor set, and the strategic-zoom class glyph markers (threshold px/m < 18).
19. **R-19 Emblem adoption.** Replace the hand-coded `UiEmblem` with the data-driven interpreter; the lobby shows `plate_contrast` hints; the roster strip shows player numbers; minimap blip shapes of 5.12.6.
20. **R-20 Relation UI.** `ViewSelection`, `ViewHealthBars`, banners and the placement ghost read colours, non-colour cues and breakpoints from `ViewStyle` (`ui.relation`, `ui.hp_ramp`, `ui.selection`): ring for units, brackets for structures, notch / pip cues by relation, hatched and crossed blocked cells.

**net / app / sim / abilities / tools / docs**

21. **R-21 Lobby colours.** `docs/spec/net.md` colour ids and keys stay; the swatch hex is read from `style.player_colors` (no duplicate table); the CVD option changes only local rendering (colour **ids** are identical on all clients); default seat order `assign_order`.
22. **R-22 Settings.** `user://settings.cfg`: `[accessibility] cvd_palette=false dyslexia_font=false high_contrast=false reduce_motion=false`, `[video] unit_outline=1 time_of_day=auto`, `[ui] scale=1.0`; `App` creates and injects `ViewStyle` (render.md's `[video]` keys are unaffected).
23. **R-23 Presentation state.** Nothing new: the view reads `SimEntity.flags` of sim_core 4.3 (`F_CLOAKED`, `F_DEPLOYED`, `F_DEPLOYING`, `F_UNDER_CONSTRUCTION`, `F_POWERED`, `F_SELLING`, `F_REPAIR_ON`, `F_WEAPONS_OFF`, `F_EMP_SHUT`, `F_SUPPRESSED`, `F_GARRISONED`, `F_DECOY`, `F_SUMMONED`). Request: keep these bits stable and written by their owners; add no view-only flag.
24. **R-24 Tooling.** `tools/gd shot <scene> <out.png> [--frames N] [--size WxH] -- <user args>` already forwards user args; additionally pass the scene's stdout lines through (or write `<out>.log`) so that the `PLATE` / `LOOK` lines reach `art_report.py`; `tools/gd test` runs `tools/py/check_style.py`; the proof scenes use `--rendering-method` where a look is compared across renderers.
25. **R-25 Lint.** New rules in `tools/py/lint.py` (numbered after L010): L011 no `Color("#...")` / `Color(r, g, b)` literals in `src/ui/**` widgets and `src/view/**` recipes (allowlist: `view_style.gd`, `ui_palette.gd`, `ui_skin.gd`, tests); L012 no `SimRng`, `Time.`, `randi` / `randf` or `delta` inside `fx_style.gd`, `view_style.gd`, `view_palette.gd`.
26. **R-26 Amendments.** Record AM-1 to AM-3 of section 12 in `docs/AMENDMENTS.md` against ARCHITECTURE §8.
27. **R-27 Duplicate events.** When the reconciler removes one of the duplicated announcements of sim_core 6.4 C, keep the variant that carries position and owner (`EVT_SALVAGE_PAID` with x / y, `EVT_STRUCTURE_CAPTURED` with old and new pid, `EV_SUMMON_EXPIRED` with the entity id and a position), so that floaters, capture flashes and fade-outs stay anchored without a lookup.
28. **R-28 VRAM cap.** render.md 5.8.2: raise "per-model VRAM ≤ 900 KB" to 1.5 MB for huge units, large ships, 4×3 / 6×3 structures and superweapons (the rows marked † in 9.2), or hold those families to about 17,000 vertices.
