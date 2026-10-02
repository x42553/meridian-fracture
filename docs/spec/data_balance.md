# MERIDIAN FRACTURE — Data, Modifier Resolution & Balance-Schema Spec

> **Domain:** Game data (`game/src/data/*`), modifier resolution, balance-data schemas (`game/data/balance/*`), validators, data hash.
> **Status:** v1 for reconciliation. Binding inputs: `docs/ARCHITECTURE.md` (wins on conflict), `Input/meridian_agent_reference/*` (bible; read-only).
> **Bible facts used here were machine-verified** against `meridian_factions.json` (156 units, 29 structures, 40 research, 48 powers, 8 superweapons, 98 modifiers, 27 selectors, 32 rosters). Every numeric example in this document was computed (and re-checked) with a Python reference implementation of the algorithms in §5, not typed by hand.
> **Project rules that shape this module (enforced by `tools/gd check` → `tools/py/lint.py`, verified by reading the linter):** `src/data` may contain **no float literal, float type, float builtin (`round floor ceil sqrt pow … roundi floori ceili absf clampf`), `INF/NAN`, clock or RNG (L003)** except in files named `*_loader.gd` or `*_parse.gd` — so every place that touches a raw JSON number is `DefNumParse` (`def_num_parse.gd`) and nothing else spells a float; class names in `src/data` are `Def*` or `GameData` (L004) with file = snake_case(class) (L009); `src/data` must not mention `Sim*/Map*/Net*/Ai*/View*/Fx*/Ui*/Snd*/App*` identifiers in code (L005; `SimConfig`/`SimRng` live in `core` and are allowed); every `var` is typed (L008); ≤ 1500 lines per file (L007); LF line endings (L010); every literal `res://` path must exist with exact case (L001).
> **Engine facts verified empirically on Godot 4.7.2 (see §5.2/§8):** `JSON` parses *every* number (even `1`) to `float`; `roundi` is half-away-from-zero; `int / int` truncates toward zero; `-1 >> n` is a parse error for constant operands (avoid negative shifts); `PackedInt32Array` silently wraps values ≥ 2^31; `Object.get_property_list()` lists a derived script's variables *before* its base script's; `Array[String].sort()` compares code points (`.` < `0-9` < `_` < `a-z`).

**Notation used throughout.** `u` = sub-cell **units** (`Fp.CELL = 1024` per cell). `t` = **ticks** (`SimConfig.TPS = 20`). `mt` = **milli-ticks** (1 tick = 1000 mt; used only for weapon reload). `bp` = **basis points** (1/100 %; 10000 bp = 100 %). `upt` = units per tick. `a` = angle units (4096 per turn). Designer files use *cells, seconds, percent, degrees* (§5.2); every runtime `Def*` field is an `int` (or bool / String id / packed int array).

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

### 1.1 What this domain owns

1. **`GameData`** — the single immutable object holding every converted, int-only definition table for a process: units, structures, weapon archetypes, research, powers, superweapons, zones, neutrals, factions, rosters, modifiers, selectors, ability templates, economy constants, damage/armor table, movement/terrain table, body (size-class) table, tag registries. It is a plain `RefCounted` (never an autoload); `SimWorld` receives it by reference (ARCHITECTURE §5).
2. **The loading pipeline** *bible JSON + balance JSON → int-only Def tables* (§5.1), including the float→int conversion rules (§5.2), the def-index assignment (sorted-ID order, §5.3) and the **data hash** + per-file/per-table hashes for the lobby handshake (§5.11).
3. **The modifier resolution engine** (§5.4–5.9): compilation of the 27 bible selectors (+ balance-defined and inline selectors), the four-layer model *base → parent faction → subfaction → research/temporary*, "add within layer, multiply across layers", half-up rounding, cost/build-time ≥ 60 % and reload ≥ 50 % floors, ≤ 50 % combined-resistance cap, conditional modifiers compiled to condition codes, no-same-source stacking, scope rules (service-unit exclusion, transport exceptions, superweapon exclusions).
4. **Roster resolution** (§5.7): `roster + delta (replacements, removals, unavailable powers) → resolved def set` per roster (32 rosters + a `base_roster`), including bible `unit_overrides`, faction-trait grants, research/power lists and the "replaced units keep role tags" invariant.
5. **The runtime layer-3 contract** (`DefLayer3`, `DefStatMath`, §5.8): the *only* place where research/temporary effects are folded into stats, so combat/abilities/economy never re-implement rounding.
6. **Balance-layer JSON schemas and the source map** for `game/data/balance/*.json` (§7): how the loader consumes the balance framework's `global.json` (vocabulary, weapon/role archetypes, structures, defenses, economy, superweapon numbers) and the per-unit sheets `units_<code>.json`, plus `structures` (overlay), `ability_kinds`, `research_effects`, `power_actions`, `zone_templates`, `faction_traits`, `neutral_structures`, `manifest` — with designer units, required/optional fields, and one worked entry each; the plug-in interface (`DefDomainCompiler`) through which combat/abilities/economy-owned files join the same load, hash and validation.
7. **Validation**: the exact rule list (§5.12), the in-engine `DefValidator`, and the design of `tools/py/validate_balance.py` (+ `tools/py/balance_lib/*`).
8. **Dev ergonomics**: debug hot-reload (`DefHotReload`), the *data browser* API for the in-game Field Manual (`DefBrowser`) and for AI queries (`DefQuery`).
9. **Vocabulary registries** other domains must share: `DefEnums` (stat ids, condition codes, effect ops, ability kinds, tag bit positions, flags, plus the TAXONOMY-frozen damage types, armor classes, layers, movement classes, terrain kinds, fire modes and weapon archetypes) — every integer code is defined *once*, here (§4.1), and equals `docs/balance/TAXONOMY.md` where that file speaks.

### 1.2 What this domain does NOT own (and who does)

| Not owned | Owner | Boundary |
|---|---|---|
| Simulation behaviour: production queues, economy ticks, power grid, movement, combat pipeline, ability *execution*, zones/powers *execution*, vision | `sim/*` domains | Data supplies typed, int-converted parameters and the shared math (`DefStatMath`); the sim owns state, timing and checksum of that state. |
| Damage/armor/movement/weapon-archetype **vocabulary and numbers**, role archetypes, unit/structure stat proposals, economy/power design numbers | balance framework (`docs/balance/TAXONOMY.md`, `game/data/balance/global.json`, `tools/py/balance_calc.py`) and BAL authors | This spec **adopts** TAXONOMY's frozen codes and specifies how the loader consumes `global.json` (§7.3); it adds validators but never edits those numbers. |
| Domain-owned data files: `combat_*.json`; `abilities.json`, `aura_classes.json`, `statuses.json`, `zones.json`, `effects.json`; `economy.json`, `structure_rules.json`, `powers.json`, `superweapons.json`, `neutral_structures.json`, `repair_profiles.json`, `summons.json`; `ai/*.json` | combat / abilities / economy / ai specs | The data module supplies the *loader framework* for them (manifest, ids, hash, validation hooks, the `DefDomainCompiler` plug-in of §3.12). Where such a file overlaps a schema in §7, §7.0 states the recommended owner. |
| Terrain, pathing grids, map generation, deposit *placement* | `map/*` | `DefNeutral`/`DefEnums.MoveClass`/`DefStructure.fp_*` are the contract. |
| Lobby transport, ENet, replay file format | `net/*` | Data provides `GameData.handshake()` / `diff_handshake()`; net carries them. |
| Procedural model recipes, VFX, audio events, UI text | `view/`, `audio/`, `ui/` | Data carries only *ids* (`pres_*` fields, excluded from the hash). |
| Editing the bible | nobody (read-only) | `game/data/bible/` is a verbatim mirror written by `tools/py/sync_bible.py`. |

### 1.3 Design stance (decisions that shape everything below)

* **The bible is canonical; balance never overrides it.** Where the bible has a non-null value the balance file may only omit it or repeat it identically (`V-CNF-01` errors otherwise). `null` = unspecified (never zero/free/instant).
* **Resolved defs are per roster, computed once at load** (32 + base). The sim never applies parent/subfaction modifiers at runtime; it reads `roster.units[def]`. Only *layer 3* (research/temporary) is dynamic, via `DefLayer3` + `DefStatMath`.
* **Every Def is a typed core + an extensible `params` blob.** Other architects can add ability/effect parameters without touching loader code: parameter names carry their *unit suffix* (`radius_cells`, `deploy_s`, `damage_bonus_pct`), and one generic converter turns them into ints with runtime-suffixed names (`radius_u`, `deploy_t`, `damage_bonus_bp`) (§5.10).
* **No directory scanning, no float math on sim values, no hash-order iteration.** A `manifest.json` lists the balance files; every iteration is over sorted ids (DR-6).
* **Bible prose is data too.** Numbers inside `effect_text` (e.g. "7-cell-radius", "12 seconds", "10% more") are cross-checked against the encoded params (`V-CNF-06`), so no bible-specified value is silently dropped.

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All paths under `game/src/data/` (module `data`, deps: `core` only). One class per file, snake_case file = class name, each ≤ 1500 lines (lint L007), static typing everywhere (L008). **No sibling `preload`; sibling classes are referenced by `class_name`** (avoids cyclic-preload errors). *Name collision to reconcile:* the abilities spec (task AB-01) also creates `DefAbility`, `DefEffect` and `DefZone` in `src/data`; `class_name` must be unique (L004), so exactly one definition survives — this spec's field lists (§4.2) are a superset designed to host both (CMR-3).

| Path | `class_name` | Responsibility |
|---|---|---|
| `game_data.gd` | `GameData` | Facade + immutable table holder: all `Array[Def*]`, id↔index maps, `economy`, `damage`, `tags`, rosters, hashes, handshake, `load_default/load_from_paths/load_from_sources`. |
| `def_enums.gd` | `DefEnums` | All integer enums/consts (Kind, Stat, DamageType, MoveClass, Layer, Cond, EffectOp, AbilityKind, ZoneKind, flags, tag bit positions) + name↔int tables. **Single source of truth for codes.** |
| `def_num_parse.gd` | `DefNumParse` | **The only class that touches a float** (lint-exempt by its `_parse.gd` name): `milli(v, ctx, rep) -> int` (the one float step, §5.2.1), `is_number`, `is_integral`. |
| `def_convert.gd` | `DefConvert` | Static, **int-only** designer-unit → runtime-unit conversions on milli values (`cells_to_units`, `seconds_to_ticks`, …), suffix-driven `convert_params`; calls `DefNumParse.milli` for raw JSON numbers. |
| `def_format.gd` | `DefFormat` | Integer-math display strings (`cells_text(u)`, `seconds_text(t)`, `percent_text(bp)`) for the Field Manual and dev overlays — no floats in `src/data`. |
| `def_stat_math.gd` | `DefStatMath` | Static layered-stat math: `fold2`, `apply_bp`, floors/caps, resist cap, `final_damage`, `rescale_hp`. Used by resolver **and** sim. |
| `def_hash.gd` | `DefHash` | 32-bit FNV-1a mixing, canonical JSON hash, reflection-based Def hash. |
| `def_domain_compiler.gd` | `DefDomainCompiler` | Plug-in interface for domain-owned balance files (combat, abilities, economy, …): `collect_ids`, `compile`, `validate`, `table_hashes`. |
| `def_ids.gd` | `DefIds` | Sorted-id → dense index registry per kind; duplicate/prefix checks. |
| `def_tags.gd` | `DefTags` | Per-kind tag registries (bible tags = fixed bits, balance extras = sorted bits ≥ first free bit). |
| `def_sources.gd` | `DefSources` | Parsed-but-unconverted inputs (`bible: Dictionary`, `balance: Dictionary[path→Dictionary]`, manifest, read errors). Built from disk or from test dictionaries. |
| `def_load_report.gd` | `DefLoadReport` | Ordered error/warning/info list with rule ids (`V-…`), `is_ok()`, `text()`. |
| `def_loader.gd` | `DefLoader` | Pipeline driver (phases P0–P9), file I/O, manifest, bible ingestion, bible↔balance merge policy. |
| `def_loader_vocab.gd` | `DefLoaderVocab` | Phase P2: `global.json` vocabulary → `DefDamageTable`, `DefMoveTable`, `DefBodyTable`, 27 `DefWeaponArch`, `DefEconomy` (+ bible `mechanical_conventions` overrides), frozen-enum verification (`V-CNF-05`). |
| `def_loader_balance.gd` | `DefLoaderBalance` | `global.json` + `units_<code>.json` + `structures.json` → `DefUnit/DefStructure/DefWeaponSlot/DefAbility` (role-archetype defaults, weapon instances, summons, derived caches). |
| `def_loader_rules.gd` | `DefLoaderRules` | Bible + balance files → `DefResearch/DefPower/DefFaction/DefNeutral/DefZone` (research, powers, traits, neutrals, zone templates). |
| `def_loader_effects.gd` | `DefLoaderEffects` | Effect records (`DefEffect`), condition and inline-selector compilation, and superweapon compilation from the bible ⊕ `global.json → superweapons` (§7.11). |
| `def_base.gd` | `DefBase` | Base of every def: `id`, `index`, `kind`, `tags`, `params`, `ui_*`. |
| `def_unit.gd` | `DefUnit` | Unit / summon / drone definition (base **and** roster-resolved clone). |
| `def_structure.gd` | `DefStructure` | Structure definition (base and resolved clone). |
| `def_weapon_arch.gd` | `DefWeaponArch` | One of the 27 TAXONOMY weapon archetypes (damage type, fire mode, projectile kind/speed, targets, splash, interception class, derived tags). |
| `def_weapon_slot.gd` | `DefWeaponSlot` | A weapon instance (archetype + numbers) on a unit/structure; holds the *resolved* numbers the combat system reads. |
| `def_damage_table.gd` | `DefDamageTable` | Damage types (+resist-group masks, non-lethal), armor classes, matrix (bp), resistance cap. |
| `def_move_table.gd` | `DefMoveTable` | Movement classes: default layers + terrain speed multipliers (bp) per class × terrain kind. |
| `def_body_table.gd` | `DefBodyTable` | Size classes: radius, turn rate, mass, structure footprints. |
| `def_ability.gd` | `DefAbility` | Ability instance: `kind`, template ref, converted params. |
| `def_ability_kinds.gd` | `DefAbilityKinds` | Registry of ability kinds with param specs, templates, framework-name aliases and implicit rules (validation + defaults); parsed from `ability_kinds.json` (§7.4). |
| `def_effect.gd` | `DefEffect` | One effect record (op, stat/delta, selector, conditions, duration, stack group, params). |
| `def_cond_val.gd` | `DefCondVal` | Conditional stat variant `{stat, cond, value}` (e.g. Gate Guard damage in a garrison). |
| `def_research.gd` | `DefResearch` | Research upgrade (bible fields + effects). |
| `def_power.gd` | `DefPower` (+ `DefPowerAction` in `def_power_action.gd`) | Support power and its action list. |
| `def_superweapon.gd` | `DefSuperweapon` (+ `DefImpactPacket` in `def_impact_packet.gd`) | Strategic weapon geometry, packets, timings. |
| `def_zone.gd` | `DefZone` | Area-effect / decoy / puck / shelter / smoke / repair-station template. |
| `def_neutral.gd` | `DefNeutral` | Neutral map structure (garrison, capturable, deposit). |
| `def_faction.gd` | `DefFaction` | Faction membership lists + trait grants + player-scope params. |
| `def_economy.gd` | `DefEconomy` | Global rule constants (economy, repair, research, floors/caps, vision, combat globals). |
| `def_modifier.gd` | `DefModifier` | Compiled bible typed modifier. |
| `def_selector.gd` | `DefSelector` | Compiled selector (bible / balance / inline). |
| `def_resolver.gd` | `DefResolver` | Selector matching, modifier accumulation, layered fold, conditional variants. |
| `def_roster_builder.gd` | `DefRosterBuilder` | Availability, overrides, trait grants, lists, self-checks vs `resolved`. |
| `def_roster.gd` | `DefRoster` | The resolved def set of one roster + derived lookup tables. |
| `def_cond_application.gd` | `DefCondApplication` | One conditional bible modifier of a roster with its resolved target sets (for consumers that handle conditions dynamically). |
| `def_compilers.gd` | `DefCompilers` | Static registry of `DefDomainCompiler` plug-ins (one line per domain). |
| `def_player_view.gd` | `DefPlayerView` | Per-player facade over (roster, layer 3): flat resolved tables in the accessor shapes the economy/abilities/combat specs requested (`ResolvedRoster`). |
| `def_layer3.gd` | `DefLayer3` | Per-player runtime overlay of completed research (stat/resist/param/flag/ability grants); owned by `SimPlayer`. |
| `def_validator.gd` | `DefValidator` | In-engine validation facade (FAST at release, FULL at debug/CI): `validate_sources`, `validate_data`, `check_frozen`, the shared `RANGES` table. |
| `def_validator_source.gd` | `DefValidatorSource` | Source-level rules `V-SCH/REF/CMP/CNF/RNG` on the parsed inputs. |
| `def_validator_data.gd` | `DefValidatorData` | Table-level rules `V-MOD/ROS/TIER/ROLE/EFF/ABL/DET` on the built `GameData`. |
| `def_query.gd` | `DefQuery` | Deterministic read-only queries for AI/sim (`cheapest_unit_with`, `counters_of`, …). |
| `def_browser.gd` | `DefBrowser` | Field-Manual cards/tech tree/roster diff: ints and preformatted strings only (`DefFormat`); the UI module converts to floats if it wants. |
| `def_hot_reload.gd` | `DefHotReload` | Debug-build polling reload (never during a networked match). |

### 2.1 Classes and concepts that other specs also define (collision list; one owner each)

`class_name` must be globally unique (lint L004) and one concept needs one implementation, so the reconciler has to keep exactly one definition per row. The recommendation column is what this spec's text assumes; every alternative needs the renames shown.

| Class / concept | Also specified by | Recommended resolution |
|---|---|---|
| `DefWeaponArch` | FRAMEWORK §3.2 (BAL-1) | **This spec's class (§4.2)**, a superset. Field renames from the framework's: `damage_type→dtype`, `projectile_kind→proj_kind`, `projectile_speed_upt→proj_speed`, `target_layer_mask→target_mask`, `splash_units→splash_radius`, `splash_edge_pct→splash_edge_bp` (×100), `scatter_units→scatter`, `min_range_units→min_range`, `turret_per_tick→turret_turn`; added: `id`, `tags`, range/reload bands. |
| `DefBalanceGlobal` (`GameData.balance`) | FRAMEWORK §3.1 (BAL-1) | **Not created.** Phase P2 builds the same integer tables into `GameData.damage` (`matrix_pct`, `group_mask`, `nonlethal_mask`), `moves` (`speed_bp`, `layer`), `bodies`, `weapon_archs`, `economy` (§4.2). Name map: `matrix_pct→damage.matrix_pct`, `type_group_mask→damage.group_mask`, `terrain_speed_pct→moves.speed_bp` (×100), `size_radius_units→bodies.radius_u`, `size_turn_per_tick→bodies.turn_apt`, `size_accel_ticks→` `movement_defaults` (per unit `accel_t`), `resist_cap_pct→economy.resist_cap_bp` (×100), `weapon_arch→weapon_archs`. Its bible-anchor checks are `V-CNF-05`. |
| `DefEconomyConsts` | FRAMEWORK §3.2 | Merged into `DefEconomy` (§4.2); e.g. `collector_capacity→collector_capacity_cr`, `harvest_credits_per_pulse / harvest_pulse_ticks→harvest_mcpt`, `salvage_pct→salvage_payout_bp`, `sell_refund_pct→sell_refund_bp`, `power_shortage_speed_pct→power_shortage_rate_bp`, `queue_length→queue_length_n`. |
| `DefDamageMath` | FRAMEWORK §3.3 | Keep as the **combat helper** class it describes (`splash_falloff_pct`, `health_after`, `ramp_bp`, `flight_ticks`, `cap_resistance`); its `final_damage(raw, bonus_bp, matrix_pct, res_pct, falloff_pct)` becomes a one-line wrapper of `DefStatMath.final_damage(…, res_pct·100, …, eco)` so that **one formula exists**; both must agree on the shared vectors of §10. |
| `DefPercentMath` | FRAMEWORK §3.3 | Not created (or a thin wrapper if BAL-1's tests are kept): `half_up_div→DefConvert.rdiv`, `ceil_div→DefConvert.ceil_div`, `layer_mul(acc, d)→DefStatMath.fold2` (one rounding for two layers instead of one per layer), `seconds_to_ticks`, `cells_to_units`, `speed_to_upt`, `deg_s_to_binary_per_tick→DefConvert.*`. **Semantic trap:** the framework's `apply_bp(value, bp)` takes a *factor* (10000 = ×1); `DefStatMath.apply_bp(v, delta_bp)` takes a *delta* (0 = ×1). |
| `DefAbility`, `DefEffect`, `DefZone` | abilities spec §4.9/§7 (task AB-01: `def_ability.gd`, `def_effect.gd`, `def_zone.gd`, positional `p: PackedInt32Array` param vectors) | **One definition.** §4.2's records are designed to host both: typed core + sorted `params`. If the abilities spec's classes win, `DefLayer3`, `DefLoaderRules` and §7.5 must be adapted to their field names (`EffectKind`, `def_mask`, `p[]`); the resolver, hash and validators are unaffected. |
| `DefWeapon`, `DefProjectile`, `DefWarhead`, `DefMount`, `DefCarrier`, `DefAir`, `DefDeath`, `DefCombat` | combat spec (`combat_*.json` + `DefCombatCompiler`) | Different names ⇒ no collision. The numbers modifiers touch (`damage range reload proj_speed`) must live in `DefWeaponSlot` (or combat's compiled weapon must extend it) so that `DefStatMath` remains the only arithmetic (CMR-6). |
| `DefEconRules`, `DefStructureRules`, `DefPowerRecipe`, `DefSuperweaponRules`, `DefRepairProfile`, `DefSummon`, `DefNeutral` | economy spec (`economy.json` + six more files) | `DefNeutral` collides (economy: typed loader of `neutral_structures.json`); the others plug in through `DefDomainCompiler`. `DefEconomy` field values may be overridden by `economy.json` (precedence, §7.0); a differing value is reported (`V-CNF-09`). |

**Tests** (`game/tests/unit/`, QA harness of `docs/spec/qa_tooling.md`: a `RefCounted` script named `test_*.gd` whose `func test_*(t: TestCtx)` methods are the tests; `t.eq` is type-strict, so `t.eq(x, 7168)` also proves `x` is an `int`): `test_data_convert.gd`, `test_data_format.gd`, `test_data_statmath.gd`, `test_data_hash.gd`, `test_data_loader.gd`, `test_data_units.gd`, `test_data_rules.gd`, `test_data_selectors.gd`, `test_data_resolver.gd`, `test_data_roster.gd`, `test_data_layer3.gd`, `test_data_playerview.gd`, `test_data_validator.gd`, `test_data_query.gd`, `test_data_hotreload.gd`; cross-module scenario `game/tests/scenarios/test_data_scenario.gd`; fixtures `game/tests/fixtures/data/*` (never scanned as tests); golden files `game/tests/golden/data_hash.json`, `convert_vectors.json`, `resolver_golden.json`. Dev CLI (run with `tools/gd run res://tests/tools/data_cli.gd -- --validate|--hash|--dump <kind>|--update-goldens`). Run: `tools/gd check src/data` and `tools/gd test data`.

**Tools** (`tools/py/`): `validate_balance.py` (CLI), `balance_lib/{load,schema,convert,resolver,rules_source,rules_resolved,prose,report}.py`, `gen_convert_vectors.py`; `sync_bible.py` (exists: mirror + `manifest.json`, `--check`) is used, not owned, by this module.

**Data** (`game/data/balance/`): `manifest.json`; `global.json` (**owned by the balance framework**, consumed by key, §7.3); `units_<code>.json` (`<code>` ∈ `shared napc nec olm def pd han ae sap`); `structures.json` (overlay: abilities/flags/exits/masks/extra tags only); `ability_kinds.json`, `research_effects.json`, `power_actions.json`, `zone_templates.json`, `faction_traits.json`, `neutral_structures.json` (the last four are fallbacks, §7.0); machine-readable schemas in `game/data/balance/schema/*.schema.json` (same JSON-Schema subset as the bible's `validate_reference.py`). Files owned by other domains are listed in §7.0.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

### 3.0 Lifecycle, call order, ownership

```
BOOT (app)        GameData.load_default()                   ── once per process; ~150-250 ms; returns null on ERROR (report in GameData.last_report)
LOBBY (net)       GameData.handshake()  ⇄  peers; mismatch → GameData.diff_handshake(local, remote) shown, match start blocked
MATCH START (sim) for each player: p.roster = data.rosters[cfg.roster_idx];  p.view = DefPlayerView.new(data, p.roster)   # owns p.view.layer3
TICK              sim reads   world.data.units[..] / p.roster.units[def] / p.roster.structures[def]   (pure field reads, zero allocation)
RESEARCH DONE     ProductionSystem (tick step 2):  p.view.apply_research(research_idx)                 (players in ascending pid order)
DEBUG             app _process @1 Hz:  DefHotReload.poll() → reload() → App swaps default GameData for *new* matches only
```

**Ownership.** `GameData` owns every `Def*`, `DefRoster`, table and string. All of it is **immutable after `build()` returns** (nobody writes a field; tests may assert via `DefValidator.check_frozen`). `SimWorld` keeps a *reference* to one `GameData`; two worlds in one process share it. `DefRoster` objects are owned by `GameData.rosters`; players hold references. `DefLayer3` lives inside the player's `DefPlayerView` and is owned by `SimPlayer` (mutable, checksummed). `PackedInt32Array` fields are copy-on-write values: reading them never aliases mutable state. Nothing in this module holds a `Node`, signal, timer, thread or `await` (DR-8); `DefHotReload` is *driven by* the app layer.

### 3.1 `GameData`

```gdscript
class_name GameData extends RefCounted

const FORMAT_VERSION: int = 1                       # part of data_hash
const BIBLE_PATH: String = "res://data/bible/meridian_factions.json"
const BALANCE_DIR: String = "res://data/balance"    # contains manifest.json
const NEUTRAL_PLAYER_ROSTER: int = -1               # use base_roster for pid -1 (neutrals)

 ## Cached per process. Returns null if any ERROR-level problem exists; `last_report` explains.
static func load_default(force_reload: bool = false) -> GameData
 ## Uncached. Used by tests, fixtures and hot reload. `compilers` = domain plug-ins (§3.12); default = DefCompilers.all().
static func load_from_paths(bible_path: String, balance_dir: String, level: int = DefValidator.LEVEL_FULL, compilers: Array[DefDomainCompiler] = []) -> GameData
 ## Uncached, from parsed dictionaries (unit tests; negative tests mutate a DefSources.deep_copy() first).
static func load_from_sources(src: DefSources, level: int = DefValidator.LEVEL_FULL, compilers: Array[DefDomainCompiler] = []) -> GameData
static var last_report: DefLoadReport

 # ---- tables (dense, index == position; sorted-id order; see §5.3) ----
var units: Array[DefUnit]               # bible units + balance summons/drones, sorted by id (156 + summons)
var structures: Array[DefStructure]     # 29
var weapon_archs: Array[DefWeaponArch]  # 27, index == TAXONOMY WeaponArch (frozen)
var research: Array[DefResearch]        # 40
var powers: Array[DefPower]             # 48
var superweapons: Array[DefSuperweapon] # 8
var zones: Array[DefZone]
var neutrals: Array[DefNeutral]
var factions: Array[DefFaction]         # 8
var rosters: Array[DefRoster]           # 32, sorted by roster id
var modifiers: Array[DefModifier]       # 98
var selectors: Array[DefSelector]       # 27 bible + balance extras + inline (sorted by id)
var abilities: Array[DefAbility]        # ability templates (ability_kinds.json → templates), sorted by id
var stack_groups: PackedStringArray     # effect stack-group names, sorted; DefEffect.stack_group indexes it
var economy: DefEconomy
var damage: DefDamageTable
var moves: DefMoveTable
var bodies: DefBodyTable
var tags: DefTags
var ids: DefIds                         # id↔index registry (behind idx()/id_of()); populated in P3
var ext: Dictionary                     # domain compiler outputs: domain_id (String) -> RefCounted owned by that compiler (§3.12)
var base_roster: DefRoster              # all defs, no modifiers/replacements; used for pid -1, tests, Field Manual "raw"
var report: DefLoadReport               # warnings/infos of the successful load

 # ---- hashes (§5.11) ----
func data_hash() -> int                 # 0 ≤ h < 2^32 (net XR-11 asks for a method)
var table_hashes: Dictionary            # String -> int (fixed keys, see §5.11)
func file_hashes() -> Dictionary        # String(path) -> int ; computed lazily from retained sources (≈50 ms)
func handshake(include_files: bool = false) -> Dictionary   # {"format":int,"hash":int,"tables":{..}, "files":{..}?}
static func diff_handshake(local: Dictionary, remote: Dictionary) -> PackedStringArray  # human-readable, deterministic order
func is_hot_swap_compatible(other: GameData) -> bool        # same id lists per kind ⇒ indices equal ⇒ values may be swapped
func drop_sources() -> void                                 # release the retained parsed sources after computing (and caching) file_hashes() once; release builds call it after the first handshake

 # ---- lookup (never error; -1 when unknown) ----
func idx(kind: int, id: String) -> int                     # kind = DefEnums.Kind.*
func unit_idx(id: String) -> int
func structure_idx(id: String) -> int
func weapon_arch_idx(id: String) -> int                    # "warch.tank_cannon" -> 3
func research_idx(id: String) -> int
func power_idx(id: String) -> int
func superweapon_idx(id: String) -> int
func zone_idx(id: String) -> int
func neutral_idx(id: String) -> int
func faction_idx(id: String) -> int
func roster_idx(id: String) -> int
func roster_ids() -> PackedStringArray                    # the 32 playable ids, ascending (net XR-11)
func roster_faction(roster_idx: int) -> int                # DefFaction index
func selector_idx(id: String) -> int
func id_of(kind: int, index: int) -> String                # "" when out of range
func count(kind: int) -> int
func def_of(kind: int, index: int) -> DefBase              # null when out of range
func roster_for(faction_code: String, sub_key: String = "") -> DefRoster   # ("NAPC","canada"); sub_key "" = vanilla; null if unknown
func vanilla_roster_of(faction: int) -> DefRoster
func ref(kind: int, index: int) -> int                     # packed (kind << 24) | index, for messages that may point at any def
static func ref_kind(r: int) -> int
static func ref_index(r: int) -> int
```

### 3.2 `DefSources`, `DefLoader`, `DefLoadReport`

```gdscript
class_name DefSources extends RefCounted
var bible: Dictionary                    # parsed meridian_factions.json
var balance: Dictionary                  # "global.json" -> Dictionary, exactly the manifest's files
var manifest_files: PackedStringArray    # from manifest.json, validated sorted+unique
var raw_texts: Dictionary                # path -> String (kept only for line-numbered error messages; may be empty in tests)
var read_errors: PackedStringArray
static func from_disk(bible_path: String, balance_dir: String) -> DefSources
static func from_dicts(bible: Dictionary, balance: Dictionary) -> DefSources
func deep_copy() -> DefSources

class_name DefLoader extends RefCounted
 ## Phases P0..P9 of §5.1. Returns null when report.errors is non-empty.
static func build(src: DefSources, level: int, compilers: Array[DefDomainCompiler]) -> GameData

class_name DefLoadReport extends RefCounted
enum Sev { ERROR = 0, WARN = 1, INFO = 2 }
var errors: PackedStringArray
var warnings: PackedStringArray
var infos: PackedStringArray
func add(sev: int, rule: String, where: String, msg: String) -> void   # stores "RULE where: msg"
func is_ok() -> bool                                                   # errors.is_empty()
func text(max_lines: int = 200) -> String
```

### 3.3 `DefNumParse` and `DefConvert` (static; identical rounding is mirrored in `tools/py/balance_lib/convert.py`, parity enforced by `game/tests/golden/convert_vectors.json`)

`DefNumParse` is the **only** place in `src/data` where a float exists (its `_parse.gd` file name is what the linter's L003 exemption keys on; nothing else in the module may spell a float literal, type or builtin — every raw JSON number reaches the rest of the module as a `Variant` handed to `DefNumParse.milli`).

```gdscript
class_name DefNumParse extends RefCounted
 ## JSON number → integer milli-units (x·1000, exact). Reports V-SCH-04 when x has > 3 decimals, is NaN/inf, or |x| ≥ 2^40. `rep` may be null (returns 0 and push_error).
static func milli(v: Variant, ctx: String, rep: DefLoadReport) -> int
static func is_number(v: Variant) -> bool                  # TYPE_INT or TYPE_FLOAT
static func is_integral(v: Variant) -> bool                # a number whose milli value is a multiple of 1000

class_name DefConvert extends RefCounted
static func rdiv(n: int, d: int) -> int                    # round-half-away-from-zero division, d > 0 (== roundi semantics), integer math only
static func ceil_div(n: int, d: int) -> int                # n ≥ 0, d > 0
static func cells_to_units(cells_milli: int) -> int        # rdiv(c·Fp.CELL, 1000)
static func cells_s_to_upt(cps_milli: int) -> int          # cells/second → upt: rdiv(c·Fp.CELL, 1000·SimConfig.TPS)   (≥ 1 enforced by callers)
static func seconds_to_ticks(sec_milli: int) -> int        # ceil_div(ms·TPS, 1000)
static func seconds_to_mt(sec_milli: int) -> int           # ms·TPS  (exact; 1 tick = 1000 mt)
static func pct_to_bp(pct_milli: int) -> int               # rdiv(p·100, 1000); files allow ≤ 2 decimals of a percent
static func deg_to_angle(deg_milli: int) -> int            # rdiv(d·Fp.TURN, 360000)
static func deg_s_to_apt(deg_per_s_milli: int) -> int      # rdiv(d·Fp.TURN, 360000·TPS), min 1 when input > 0
static func crps_to_mcpt(credits_per_s_milli: int) -> int   # rdiv(c, TPS): 100 cr/s → 5000 milli-credits per tick
static func pcts_to_bps(pct_per_s_milli: int) -> int         # rdiv(p·100, 1000): 1 %/s → 100 bp/s
 ## Suffix-driven blob conversion (§5.10). Returns {runtime_key: int|bool|String|PackedInt32Array|Array|Dictionary}, keys in sorted order.
static func convert_params(raw: Dictionary, ctx: String, data: GameData, rep: DefLoadReport) -> Dictionary   # `data` may be under construction: only .ids, .tags, .damage are read
```

`DefFormat` (integer-math display strings; used by `DefBrowser`, dev overlays and the Field Manual):
```gdscript
class_name DefFormat extends RefCounted
static func cells_text(u: int) -> String            # 7168 → "7.0" (one decimal, half-up: (u·10 + 512) / 1024)
static func speed_text(upt: int) -> String          # 102 upt → "2.0" cells/s (upt·TPS·10 / 1024, half-up)
static func seconds_text(t: int) -> String          # 550 t → "27.5" ((t·10 + 10) / 20)
static func mt_seconds_text(mt: int) -> String      # 24000 mt → "1.2" ((mt·10 + 10000) / 20000)
static func percent_text(bp: int) -> String         # 1000 → "10", -1500 → "-15", 1250 → "12.5"
```

### 3.4 `DefStatMath` (static, pure, allocation-free — the *only* layered-stat arithmetic in the code base)

```gdscript
class_name DefStatMath extends RefCounted
 ## fold two static layers in ONE rounding: half_up(base·(10000+s1)·(10000+s2) / 10^8); factors clamped ≥ 0. base ≥ 0, ≤ 100000.
static func fold2(base: int, s1_bp: int, s2_bp: int) -> int
 ## single-layer application (used for layer 3): half_up(v·(10000+d)/10^4), clamped ≥ 0
static func apply_bp(v: int, delta_bp: int) -> int
 ## floors/caps by stat (§5.5.4). base = the *unmodified* base value; economy = DefEconomy
static func clamp_stat(stat: int, base: int, v: int, eco: DefEconomy) -> int
 ## complete static fold with clamp: clamp_stat(stat, base, fold2(base, s1, s2))
static func resolve_static(stat: int, base: int, s1_bp: int, s2_bp: int, eco: DefEconomy) -> int
 ## runtime: clamp_stat(stat, base, apply_bp(resolved, l3_bp))
static func effective(stat: int, base: int, resolved: int, l3_bp: int, eco: DefEconomy) -> int
static func resist_total_bp(sum_bp: int, eco: DefEconomy) -> int        # min(max(sum,0), resist_cap_bp = 5000)
 ## per-hit damage, ONE rounding (TAXONOMY): max(1, half_up(raw·bonus_bp·matrix_pct·(10000−resist)·falloff_pct / 10^12)); 0 if raw, bonus, matrix or falloff ≤ 0. Same result as balance_calc.final_damage.
static func final_damage(raw: int, bonus_bp: int, matrix_pct: int, resist_bp: int, falloff_pct: int, eco: DefEconomy) -> int
static func rescale_hp(hp: int, old_max: int, new_max: int) -> int      # max(1, rdiv(hp·new_max, old_max)); keeps hp ratio when max changes
static func stack_pick(group_best_bp: int, candidate_bp: int) -> int    # same-stack-group rule: larger |delta| wins (ties: keep existing)
```

### 3.5 `DefHash` (static)

```gdscript
class_name DefHash extends RefCounted
const OFFSET: int = 2166136261         # 0x811C9DC5
const PRIME: int = 16777619            # 0x01000193
static func mix_byte(h: int, b: int) -> int                    # ((h ^ (b & 0xFF)) * PRIME) & 0xFFFFFFFF
static func mix_int(h: int, v: int) -> int                     # z=(|v|<<1)|sign, LEB128 bytes (7 bits, low first, 0x80 = more); |v| < 2^62
static func mix_str(h: int, s: String) -> int                  # UTF-8 bytes then 0xFF terminator
static func mix_variant(h: int, v: Variant) -> int             # tagged, dictionaries by sorted String key; float ⇒ error(V-DET-01) in debug
static func hash_def(h: int, d: Object) -> int                 # reflection: script vars in get_property_list() order, skipping names starting "_", "ui_", "pres_"; shape signature mixed once per script
static func hash_json(v: Variant) -> int                       # canonical JSON hash: numbers → DefNumParse.milli; dict keys sorted; whitespace/CRLF/key-order independent
```

### 3.6 `DefRoster` (resolved def set of one roster; immutable)

```gdscript
class_name DefRoster extends RefCounted
var index: int
var id: String                              # "roster.napc.canada"
var faction: int                            # DefFaction index
var parent: int                             # roster index of vanilla; -1 for vanilla/base
var is_vanilla: bool
var units: Array[DefUnit]                   # size == data.units.size(); resolved clone or null (not in roster)
var structures: Array[DefStructure]         # size == data.structures.size()
var producible_units: PackedInt32Array      # ascending by (tier, cost, index); excludes summons/drones
var producible_structures: PackedInt32Array # ascending by (build_tier, cost, index); excludes HQ
var spawnables: PackedInt32Array            # summon/drone unit indices reachable from this roster's powers/abilities/superweapon
var research_list: PackedInt32Array         # [shared0, shared1, exclusive?] (2 for vanilla, 3 otherwise)
var power_list: PackedInt32Array            # [shared0, shared1, third]
var superweapon: int                        # DefSuperweapon index
var superweapon_def: DefSuperweapon         # resolved clone (packets scaled by matching modifiers)
var modifier_list: PackedInt32Array         # modifier indices, parents first
var player_params: Dictionary               # merged DefFaction.player_params (e.g. defense_reserve_t)
var replaced_by: Dictionary                 # baseline unit index -> replacement unit index (this roster only)
var ui_title: String
var ui_identity: String
var ui_lore: String
var ui_opening: String
var ui_counterplay: String

func has_unit(unit_idx: int) -> bool
func has_structure(structure_idx: int) -> bool
func unit(unit_idx: int) -> DefUnit                     # null when absent
func structure(structure_idx: int) -> DefStructure
func units_produced_by(structure_idx: int) -> PackedInt32Array      # roster-available, producible, ascending (tier, cost, index)
static func prereqs_met(requires_mask: int, owned_structure_mask: int) -> bool   # (owned & req) == req
func selector_units(sel_idx: int) -> PackedInt32Array              # units of THIS roster matched by a selector (incl. include_replacements closure); cached
func selector_structures(sel_idx: int) -> PackedInt32Array
func selector_mask_units(sel_idx: int) -> PackedByteArray          # size == data.units.size(), 1 = matched (abilities: `selector_mask(id)`)
func selector_mask_structures(sel_idx: int) -> PackedByteArray
func conditional_applications() -> Array[DefCondApplication]       # the 6 bible conditional modifiers of this roster with their resolved unit sets, for consumers that prefer dynamic handling (§5.5.5)
func static_sums(kind: int, def_idx: int, stat: int) -> PackedInt32Array   # [S1, S2] bp: the parent/subfaction layer sums already folded into the clone's resolved value ([0, 0] when none; kind = UNIT or STRUCTURE). For consumers that must re-fold with their own base (a lease/basis-point combat model); the baked clone value stays the default
func research_slot(research_idx: int) -> int                        # position in research_list or -1
func power_slot(power_idx: int) -> int
func hash_into(h: int) -> int
```

### 3.7 `DefLayer3` (per-player runtime overlay; owned by `SimPlayer`)

```gdscript
class_name DefLayer3 extends RefCounted
var data: GameData                          # not owned; DefLayer3 lives ≤ one match, GameData never references it (no cycle)
var roster: DefRoster
var version: int                            # ++ on every apply_research (consumers cache derived values keyed by it)
var completed: PackedInt32Array             # research indices in completion order
func _init(d: GameData, r: DefRoster) -> void
func is_done(research_idx: int) -> bool
 ## Applies every effect of a completed research (stat/resist accumulate; param/flag/grant recorded). Idempotent guard: a second call for the same index is a no-op + push_error.
func apply_research(research_idx: int) -> void
 ## Σ unconditional research delta (bp) for (stat, def); does NOT include temporary effects.
func unit_stat_bp(stat: int, unit_idx: int) -> int
func struct_stat_bp(stat: int, struct_idx: int) -> int
 ## Σ unconditional research resistance (bp) whose group mask intersects the damage type's `group_mask`, before the 50 % cap.
func unit_resist_bp(dtype: int, unit_idx: int) -> int
func struct_resist_bp(dtype: int, struct_idx: int) -> int
 ## Effective value: DefStatMath.effective(stat, base, resolved, unit_stat_bp + extra_bp, eco). `extra_bp` = Σ distinct-source *temporary* deltas (abilities domain).
func effective_unit_stat(stat: int, unit_idx: int, extra_bp: int = 0) -> int      # looks up base/resolved from roster
func effective_struct_stat(stat: int, struct_idx: int, extra_bp: int = 0) -> int
 ## Ability/def/player parameter after completed PARAM_MODs (order: set → add → mul_bp; §5.8).
func ability_param(unit_idx: int, kind: int, key: String, base: int) -> int
func struct_ability_param(struct_idx: int, kind: int, key: String, base: int) -> int
func def_param(unit_idx: int, key: String, base: int) -> int
func struct_def_param(struct_idx: int, key: String, base: int) -> int      # e.g. emp_recovery_bp of Radar/defenses
func player_param(key: String, base: int) -> int
func has_flag(unit_idx: int, flag: String) -> bool
func granted_abilities(unit_idx: int) -> Array[DefAbility]                   # research-granted (runtime) abilities of a unit def
 ## Conditional (runtime-evaluated) research effects that target this unit def; abilities domain evaluates `effect.cond_codes` / `cond_params` per entity.
func cond_effects_of_unit(unit_idx: int) -> Array[DefEffect]
func cond_effects_of_struct(struct_idx: int) -> Array[DefEffect]
func checksum() -> int                                                        # DefHash over completed + all accumulators; sim adds it to SimWorld.checksum()
```

### 3.8 `DefResolver`, `DefRosterBuilder`, `DefValidator`, `DefTags`, `DefMoveTable`, `DefBodyTable`, `DefIds`

```gdscript
class_name DefResolver extends RefCounted
static func compile_selector(data: GameData, src: Dictionary, id: String, rep: DefLoadReport) -> DefSelector
static func matches_unit(sel: DefSelector, unit_tags: int, unit_idx: int, unit_class: int, weapon_tags: int) -> bool   # weapon_tags = DefUnit.weapon_tags
static func matches_structure(sel: DefSelector, struct_tags: int, struct_idx: int, weapon_tags: int) -> bool
static func matches_weapon(sel: DefSelector, weapon_tags: int) -> bool
static func matches_projectile(sel: DefSelector, proj_tags: int) -> bool

class_name DefRosterBuilder extends RefCounted
static func build_all(data: GameData, rep: DefLoadReport) -> void          # fills data.rosters + data.base_roster
static func build_one(data: GameData, roster_idx: int, rep: DefLoadReport) -> DefRoster

class_name DefValidator extends RefCounted
enum { LEVEL_FAST = 0, LEVEL_FULL = 1 }
static func validate_sources(src: DefSources, rep: DefLoadReport, level: int) -> void        # V-SCH/REF/CMP/CNF/RNG on raw inputs
static func validate_data(data: GameData, rep: DefLoadReport, level: int) -> void            # V-MOD/ROS/TIER/ROLE/EFF/ABL on tables
static func check_frozen(data: GameData) -> bool                                             # debug: re-hash and compare to data_hash

class_name DefTags extends RefCounted
func unit_bit(name: String) -> int            # 0 when unknown
func unit_mask(names: PackedStringArray) -> int
func unit_names(mask: int) -> PackedStringArray
 # identical triples for structure_*, weapon_*, projectile_*
func unit_extra_first_bit() -> int            # 29 (bible tags occupy bits 0..28)

class_name DefMoveTable extends RefCounted
const TERRAIN_COUNT: int = 8
var speed_bp: PackedInt32Array                 # [move_class * TERRAIN_COUNT + terrain_kind]; 0 = impassable, 10000 = nominal (global.json movement_classes[*].terrain_speed_pct × 100)
var layer: PackedInt32Array                    # per MoveClass: the Layer the class lives in
var layer_mask: PackedInt32Array               # per MoveClass: default LayerMask (AMPHIBIOUS = L_GROUND|L_WATER, SUBMERGED = L_UNDER|L_WATER)
func speed_bp_at(move_class: int, terrain_kind: int) -> int
func passable(move_class: int, terrain_kind: int) -> bool   # speed_bp_at > 0
 ## Effective speed on one cell, ONE rounding: table value, per-unit DEEP override (Tide Tank) and the water multiplier (Canada) combined:
 ##   bp = deep_speed_bp if (terrain_kind == DEEP and deep_speed_bp > 0) else speed_bp_at(...);  wm = water_mult_bp on SHALLOW/DEEP else 10000;  half_up(nominal_upt · bp · wm / 10^8)
static func effective_speed(table: DefMoveTable, nominal_upt: int, move_class: int, terrain_kind: int, deep_speed_bp: int, water_mult_bp: int) -> int

class_name DefBodyTable extends RefCounted
var radius_u: PackedInt32Array                 # per SizeClass
var turn_apt: PackedInt32Array
var mass: PackedInt32Array
var is_structure: PackedByteArray
var fp_w: PackedInt32Array                     # structures s1..s4 (0 for unit classes)
var fp_h: PackedInt32Array

class_name DefIds extends RefCounted
func assign(kind: int, ids: PackedStringArray, rep: DefLoadReport) -> void  # sorts (code-point), rejects duplicates/bad prefix, builds maps
func index_of(kind: int, id: String) -> int
func id_of(kind: int, index: int) -> String
func ids(kind: int) -> PackedStringArray
```

### 3.9 `DefQuery` (AI / UI helper; static, deterministic, read-only)

```gdscript
class_name DefQuery extends RefCounted
static func units_with(roster: DefRoster, all_mask: int, none_mask: int = 0) -> PackedInt32Array           # unit tag masks (DefEnums.UT_*), ascending index
static func structures_with(roster: DefRoster, all_mask: int, none_mask: int = 0) -> PackedInt32Array     # structure tag masks (DefEnums.ST_*)
static func cheapest_unit_with(roster: DefRoster, all_mask: int, none_mask: int = 0, max_tier: int = 3) -> int   # -1 if none; ties → lower index
static func cheapest_structure_with(roster: DefRoster, all_mask: int, none_mask: int = 0) -> int
static func dps_x100(slot: DefWeaponSlot) -> int                                        # damage·hits_per_volley·100·TPS·1000 / reload_mt   (140 dmg / 24000 mt → 11666 = 116.66 dps, the framework's tank reference)
static func unit_dps_x100(data: GameData, roster: DefRoster, unit_idx: int, vs_armor: int) -> int   # Σ slots · matrix_pct[dtype][armor] / 100
static func counters_of(data: GameData, roster: DefRoster, target_unit: int, max_tier: int = 3, limit: int = 5) -> PackedInt32Array
                                                                                       # rank by dps_vs_target·100/cost desc; ties lower index; only units whose attack_layer_mask can hit the target's layer
static func tech_path(roster: DefRoster, kind: int, idx: int) -> PackedInt32Array      # structure indices to build, dependency order (topological; ties lower index)
static func min_time_to_ticks(roster: DefRoster, kind: int, idx: int) -> int           # Σ build_ticks of tech_path + own build/research time (single builder; for AI/balance reports)
static func replacement_of(roster: DefRoster, baseline_unit: int) -> int               # -1 if not replaced
```

### 3.10 `DefBrowser` (Field Manual; UI-side; **ints and preformatted strings only** — no floats in `src/data`, the UI converts if it wants; never feeds the sim)

```gdscript
class_name DefBrowser extends RefCounted
static func unit_card(data: GameData, roster: DefRoster, unit_idx: int) -> Dictionary
static func structure_card(data: GameData, roster: DefRoster, structure_idx: int) -> Dictionary
static func research_card(data: GameData, roster: DefRoster, research_idx: int) -> Dictionary
static func power_card(data: GameData, roster: DefRoster, power_idx: int) -> Dictionary
static func superweapon_card(data: GameData, roster: DefRoster) -> Dictionary
static func faction_card(data: GameData, faction_idx: int) -> Dictionary
static func roster_card(data: GameData, roster: DefRoster) -> Dictionary                # delta vs vanilla: replaced/removed/unavailable/modifiers
static func tech_tree(data: GameData, roster: DefRoster) -> Dictionary                  # {"nodes":[{kind,idx,tier,requires:[..]}], "edges":[[a,b],..]}
static func compare_rosters(data: GameData, a: DefRoster, b: DefRoster) -> Dictionary
static func search(data: GameData, roster: DefRoster, text: String, limit: int = 20) -> Array[Dictionary]
```
Card schema (stable keys; all values JSON-like; every number is an `int` in runtime units, every `text.*` entry is a display string produced by `DefFormat`): `unit_card` → `{id, name, role_text, tier, class, tags:[String], cost, build_t, health, base:{cost, build_t, health, speed_upt, sight_u}, speed_upt, water_mult_bp, deep_speed_bp, sight_u, armor_class:String, move_class:String, layers:[String], producer:{id,name}, requires:[{id,name}], replaces:{id,name}|null, replaced_by:[{id,name}], weapons:[{name, archetype:String, damage, hits, dps_x100, range_u, min_range_u, reload_mt, damage_type:String, fire_mode:String, targets:[String], splash_u, suppressive:bool}], abilities:[{kind:String, summary:String}], modifiers:[{modifier_id, source_text, stat:String, delta_bp:int, layer:int, conditional:bool}], strong_vs:[String], weak_vs:[String], counters:[{id,name}], text:{build:"27.5 s", speed:"2.0 cells/s", sight:"9.0", range:"7.0", reload:"1.2 s", ...}}`.

### 3.11 `DefHotReload` (debug only)

```gdscript
class_name DefHotReload extends RefCounted
func _init(bible_path: String = GameData.BIBLE_PATH, balance_dir: String = GameData.BALANCE_DIR) -> void
func enabled() -> bool                      # OS.is_debug_build() and not disabled by --no-data-reload
func poll() -> bool                         # true if any watched file's FileAccess.get_modified_time changed since last snapshot; call ≤ 1 Hz
func reload() -> GameData                   # builds a NEW GameData (LEVEL_FULL); null + report on error; never mutates the current one
```
Semantics: a running `SimWorld` keeps the `GameData` it was created with. The app may call `SimWorld.swap_data(new)` **only** when `!world.is_networked && new.is_hot_swap_compatible(old)` (value-only edits); otherwise the new data applies to the next match.

### 3.12 `DefDomainCompiler` and `DefCompilers` (plug-ins for domain-owned balance files)

The concurrent specs of the combat, abilities and economy domains each define their own `game/data/balance/*.json` files and `Def*` classes. They join the **same** load (ids, sorted iteration, hashing, validation, hot reload, handshake) through this interface instead of a second loader:

```gdscript
class_name DefDomainCompiler extends RefCounted
func domain_id() -> String                                                     # "combat", "abilities", "economy", … (unique, lowercase)
func file_names() -> PackedStringArray                                         # manifest files owned by this compiler (must appear in manifest.json)
func collect_ids(src: DefSources, ids: DefIds, rep: DefLoadReport) -> void    # P3: declare ids so other files can reference them
func compile(src: DefSources, data: GameData, rep: DefLoadReport) -> void     # P4-P6: convert to ints; store tables in data.ext[domain_id()] and/or fill common defs
func validate(data: GameData, rep: DefLoadReport, level: int) -> void         # P9: domain rules (rule ids prefixed by the domain, e.g. V-CMB-*)
func table_hashes(data: GameData) -> Dictionary                               # {"combat": int, …} folded into data_hash in sorted-key order

class_name DefCompilers extends RefCounted
static func all() -> Array[DefDomainCompiler]     # fixed list, sorted by domain_id; each domain adds ONE line here (CMR-26)
```
Rules: compilers run **after** P3 (so ids of common kinds exist) and in `domain_id` order; a compiler reads only `DefSources`, `data.ids/tags/damage/moves/bodies/economy` and common defs; it may append `DefWeaponSlot`s/`DefAbility`s to common defs **only** through the documented fields of §4.2 (never by replacing them); its `params` blobs pass through `DefConvert.convert_params` (suffix rules of §5.10.1) unless the compiler declares its own converter and states so in its spec. Compiler tables are part of the hash and of `check_frozen`.

### 3.13 `DefPlayerView` (per-player facade: roster + layer 3, in the accessor shapes other specs asked for)

`GameData` is immutable and shared, so the "per-player resolved tables" that the economy (`GameData.res(pid) -> ResolvedRoster`), abilities (`resolved_def(pid, def)`), combat (`pmount/pdef/presist`) and AI (`unit_def(def, pid)`) specs request live on the **player**: `SimPlayer.view = DefPlayerView.new(data, roster)`; those specs' `world.data.res(pid)` calls become `world.players[pid].view`.

```gdscript
class_name DefPlayerView extends RefCounted
var data: GameData
var roster: DefRoster
var layer3: DefLayer3
var version: int                                   # layer3.version at the last refresh
 # ---- economy-shaped flat tables (field names = economy spec §3.8 ResolvedRoster); index = def index; layers 1-3 (static + permanent research) applied ----
var unit_cost: PackedInt32Array                    # 0 for units not in the roster
var unit_ticks: PackedInt32Array
var unit_available: PackedInt32Array               # 1 = producible in this roster (tier prerequisites NOT evaluated)
var unit_cap_cost: PackedInt32Array                # DefUnit.pop
var unit_rearm_ticks: PackedInt32Array
var struct_cost: PackedInt32Array
var struct_ticks: PackedInt32Array
var struct_available: PackedInt32Array
var struct_power: PackedInt32Array                 # signed: + supply / − demand
var unit_repair_cost_bp: PackedInt32Array
var struct_repair_cost_bp: PackedInt32Array
var struct_repair_rate_bp: PackedInt32Array
var research_available: PackedInt32Array           # 1 = in roster.research_list
var power_of_slot: PackedInt32Array                # power index per slot 0..2
var super_idx: int
func _init(d: GameData, r: DefRoster) -> void      # builds layer3 and runs refresh()
func apply_research(research_idx: int) -> void     # layer3.apply_research + refresh() (the single call the sim makes)
func refresh() -> void                             # recompute the flat tables iff layer3.version != version
 # ---- abilities-shaped ----
func resolved_stats(kind: int, def_idx: int) -> PackedInt32Array   # indexed by DefEnums.Stat: static+research value (no temporary effects); 0 where n/a
func base_stats(kind: int, def_idx: int) -> PackedInt32Array       # unmodified base values (for the 50 % reload floor etc.)
 # ---- combat-shaped ----
func slot(unit_idx: int, slot_idx: int) -> DefWeaponSlot           # the roster clone's slot
func effective_slot_value(unit_idx: int, slot_idx: int, stat: int, extra_bp: int = 0) -> int   # damage/range/reload/proj_speed after research (+ temporaries)
func research_resist_bp(kind: int, def_idx: int, damage_type: int) -> int                      # Σ unconditional research resistance, uncapped
func checksum() -> int                             # == layer3.checksum(); flat tables are derived and not hashed
```
`refresh()` costs ≈ 60 defs × 6 lookups ≈ 30 µs; it runs only on research completion. Economy/production read the flat arrays directly (one `PackedInt32Array` index per query).

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.0 Field rules (apply to every Def)

1. **Only** `int`, `bool`, `String` (ids / labels), `PackedInt32Array`, `Array[<owned child Def>]`, `Dictionary` of those (the converted `params`), `PackedByteArray` (footprint) may appear. **No `float`, no `Vector*`, no `Color`, no object reference to another Def** (cross-references are **indices**). `DefHash` treats a `float` as a bug (V-DET-01).
2. Field-name prefixes control the hash: `_x` (private cache), `ui_x` (label/text), `pres_x` (presentation ids: recipe/icon/sound/fx/hints) are **excluded** from `data_hash`; everything else is hashed. Renaming/adding a gameplay field automatically changes the hash (DR-13 spirit).
3. `index` is the position in the owning `GameData` array; `id` is the canonical string. Indices are **per kind**; a `DefRef` packs `(kind<<24)|index` where a message may point at any def.
4. Base defs live in `GameData.*`; **resolved clones** (`DefRoster.units[i]`, `.structures[i]`) are the same class with layer-1/2 results folded in. Systems read the *owner's roster* clone; base defs serve tooling and floors/caps.
5. Units of measure in Def fields: distances `u`, speeds `upt`, times `t` (ticks) or `mt` (reload only), percentages `bp`, angles `a`, money/HP `int`. Suffixes `_u/_upt/_t/_mt/_bp/_a/_apt/_cr/_hp/_n/_x` are used in `params` keys (§5.10).

### 4.1 Enumerations (`DefEnums`) — integer codes

**Vocabulary frozen by `docs/balance/TAXONOMY.md` (final authority; mirrored 1:1 in `game/data/balance/global.json`).** The loader **verifies** that `global.json` carries exactly these ids/indices (`V-CNF-05`); the integers are used by replays, events and checksums and are append-only.

| Enum | Values (index = integer code) |
|---|---|
| `DamageType` | `BULLET 0, AP 1, HE 2, THERMAL 3, RAIL 4, KINETIC 5, EMP 6` (`COUNT 7`); `EMP` is **non-lethal** (never reduces health below 1) |
| `ResistGroup` (bit mask) | `BULLET 1, EXPLOSIVE 2, BEAM 4, THERMAL 8, RAIL 16, KINETIC 32, EMP 64`; per-type `group_mask`: bullet→1, ap→2, he→2, thermal→4\|8, rail→16, kinetic→32, emp→64. A resistance source names groups; it applies to a hit iff `type.group_mask & source.group_mask ≠ 0` |
| `ArmorClass` | `INFANTRY 0, LIGHT_VEHICLE 1, MEDIUM_ARMOR 2, HEAVY_ARMOR 3, AIR_LIGHT 4, AIR_HEAVY 5, SHIP_LIGHT 6, SHIP_HEAVY 7, BUILDING_LIGHT 8, BUILDING_HEAVY 9, FORTRESS 10` (`COUNT 11`) |
| `Layer` / `LayerMask` | `GROUND 0, AIR 1, SURFACE_WATER 2, UNDERWATER 3` / `L_GROUND 1, L_AIR 2, L_WATER 4, L_UNDER 8` |
| `MoveClass` | `FOOT 0, WHEELED 1, TRACKED 2, AMPHIBIOUS 3, NAVAL 4, SUBMERGED 5, AIR_FIXED 6, AIR_HOVER 7, STATIC 8` |
| `TerrainKind` | `ROAD 0, OPEN 1, ROUGH 2, FOREST 3, MARSH 4, SHALLOW 5, DEEP 6, CLIFF 7` (ASSUMPTION(map): the map maps every tile to one kind) |
| `FireMode` | `DIRECT 0, INDIRECT 1, MELEE 2` (drives the Dust Screen "direct-fire" rule) |
| `Interceptable` | `NONE 0, TRIDENT 1, APS_TRIDENT 2` (`TRIDENT` = artillery shells/rockets, Trident only; `APS_TRIDENT` = ordinary guided missiles, Ural/Arjun APS **and** Trident) |
| `WeaponArch` | 27 archetypes, index frozen: `small_arms 0, machine_gun 1, autocannon 2, tank_cannon 3, siege_gun 4, demolition_cannon 5, at_missile 6, aa_missile 7, flak 8, artillery_shell 9, rocket_barrage 10, mortar 11, missile_artillery 12, beam_thermal 13, rail_gun 14, torpedo 15, depth_charge 16, bomb 17, air_missile 18, emp_pulse 19, canister 20, grenade_launcher 21, breach_charge 22, naval_gun 23, naval_bombard 24, cruise_missile 25, drone_missile 26` |

**Enums defined by the data domain** (integer codes fixed here):

* **Kind** `UNIT 0, STRUCTURE 1, WEAPON_ARCH 2, PROJECTILE 3 (reserved: combat may compile its own templates; the data module has none), RESEARCH 4, POWER 5, SUPERWEAPON 6, ZONE 7, NEUTRAL 8, FACTION 9, ROSTER 10, MODIFIER 11, SELECTOR 12, ABILITY 13`; `COUNT 14`. Bible id prefixes: `unit. structure. research. power. superweapon. faction. roster. modifier. selector.`; balance-owned prefixes: `warch. zone. neutral. summon. ability.` (weapon-instance labels `weapon.<code>.<name>` and trait ids `trait.<code>.<name>` are unique labels, not `Kind`s; role archetypes are referenced by their bare `global.json` key); inline selectors `inline.<owner id>#<n>`. (`warch.<name>` = weapon archetype, e.g. `warch.tank_cannon`.)
* **Stat** (resolver vocabulary; "B" = number of the 98 bible modifiers using it):

| id | JSON name | B | targets (entity → field) | base unit | floor / cap (§5.5.4) |
|---|---|---|---|---|---|
| 0 `COST` | `cost_credits` | 27 | unit/structure/drone → `cost` | credits | ≥ ceil(60 % base), skip if base 0 |
| 1 `BUILD_TIME` | `build_time_seconds` | 18 | unit/structure/drone → `build_ticks` | ticks | ≥ ceil(60 % base) |
| 2 `HEALTH` | `health` | 24 | unit/structure → `health` | hp | ≥ 1 |
| 3 `SPEED` | `movement_speed` | 13 | unit → `speed`; with cond `ON_WATER` → `water_mult_bp` | upt / bp | ≥ 1 (skipped if base 0) |
| 4 `DAMAGE` | `weapon_damage` | 2 | weapon slots → `damage`; superweapon packets | hp/hit | ≥ 1 (0 stays 0) |
| 5 `RANGE` | `weapon_range_cells` | 4 | weapon slots → `range` (max only; ≥ `min_range`+1) | u | ≥ 1 |
| 6 `RELOAD` | `reload_interval_seconds` | 3 | weapon slots → `reload_mt`/`reload_ticks` | mt | ≥ max(1 mt, ceil(50 % base)) |
| 7 `REARM` | `rearm_time_seconds` | 1 | aircraft → `rearm_t` | ticks | ≥ ceil(50 % base) (balance decision, not bible) |
| 8 `SIGHT` | `sight_cells` | 1 | unit/structure → `sight` | u | ≥ 1 |
| 9 `POWER` | `power_output` | 2 | structure → `power` (only when base > 0) | power | ≥ 0 |
| 10 `REPAIR_RATE` | `repair_progress_rate` | 1 | structure → `repair_rate_bp` (base 10000 = nominal) | bp | ≥ 1 |
| 11 `REPAIR_COST` | `repair_credit_cost_per_health` | 1 | unit/structure → `repair_cost_bp` (cost of 100 % hp as bp of paid price) | bp | ≥ 0 |
| 12 `PROJ_SPEED` | `projectile_flight_speed` | 1 | weapon slots → `proj_speed` (skipped if 0 = hitscan) | upt | ≥ 1 |
| 13 `RESIST` | `damage_resistance` | 0 | runtime only (RESIST_MOD) | bp | total ≤ 5000 |
| 14 `PROD_RATE` | `production_rate` | 0 | runtime only, structure queues | bp of nominal | ≥ 0 |
| 15 `REARM_RATE` | `rearm_rate` | 0 | runtime only, airfield service | bp of nominal | ≥ 0 |

  `STAT_COUNT_BIBLE = 13` (ids 0-12 may appear in typed bible modifiers); ids 13-15 exist only in balance effects (layer 3).
* **ProjKind** (from the archetype's `projectile_kind`): `BULLET 0, SHELL 1, MISSILE 2, ROCKET 3, BEAM 4, RAIL 5, TORPEDO 6, BOMB 7, FIELD 8, PELLETS 9, GRENADE 10, CHARGE 11`.
* **SizeClass** (order of `global.json → size_classes`, append-only): `INF 0, LIGHT 1, MEDIUM 2, HEAVY 3, HUGE 4, AIR_MEDIUM 5, AIR_LARGE 6, SHIP_SMALL 7, SHIP_MEDIUM 8, SHIP_LARGE 9, S1 10, S2 11, S3 12, S4 13`.
* **UnitClass** `SERVICE 0, BASELINE 1, UNIQUE 2, SUMMON 3, DRONE 4` (bible `roster_class` = service/baseline_combat/unique_subfaction; SUMMON = temporary power/superweapon entities; DRONE = carrier-launched, replaced by their carrier).
* **RosterKind** `VANILLA 0, SUBFACTION 1`. **QueueKind** `NONE 0, INFANTRY 1, VEHICLE 2, AIRCRAFT 3, NAVAL 4, COLLECTOR 5`.
* **TargetMode** `NONE 0, POINT 1, LINE 2, OWN_STRUCTURE 3`. **TargetVision** `ANY 0, EXPLORED 1, CURRENT 2` (rule.combat.targeting_and_warnings). **ZoneKind** `BUFF 0, SMOKE 1, INTERCEPT 2, DEBRIS 3, DECOY 4, PUCK 5, SHELTER 6, COVER 7, REPAIR 8, REVEAL 9`. **ZoneShape** `CIRCLE 0, LINE 1`. **Affects** (bit flags) `FRIENDLY 1, ENEMY 2, ALL 3`. **NeutralKind** `CIVILIAN_GARRISON 0, POWER_SUBSTATION 1, OBSERVATION_POST 2, SALVAGE_DEPOT 3, DEPOSIT 4` (5 `FIELD_HOSPITAL` and 6 `HARBOR_TERMINAL` are reserved for the additional neutrals proposed by the economy spec; append-only).
* **SwAction** `KINETIC_VOLLEY 0, EMP_BURST 1, BEAM_SWEEP 2, BUNKER_BUSTER 3, DRONE_SWARM 4, ENGINE_DROP 5, RAIL_STRIKE 6, INTERCEPT_ZONE 7`. **PowerOp** `ZONE 1, SUMMON 2, STRIKE 3, MARK 4, GLOBAL_EFFECT 5`. **EffectOp** `STAT_MOD 1, RESIST_MOD 2, PARAM_MOD 3, GRANT_ABILITY 4, SET_FLAG 5, IMMUNITY 6, HEAL 7, CAMOUFLAGE 8, REVEAL 9, DISABLE 10, MARK 11, SPAWN_ZONE 12`. **ParamOp** `SET 0, ADD 1, MUL_BP 2`. **ParamScope** `ABILITY 0, DEF 1, PLAYER 2`. **Membership** `CONTINUOUS 0, LATCHED 1`.

**Condition codes `Cond`** (evaluated at runtime by the abilities/combat domains unless folded statically, §5.9):

| code | name | source | evaluation |
|---|---|---|---|
| 0 | `NONE` | | |
| 1 | `ON_WATER` | bible `"The vehicle is on water."` | **folded statically** into `water_mult_bp` (§5.5.5) — no runtime check |
| 2 | `IN_CIVILIAN_GARRISON` | bible `"The infantry unit occupies a marked civilian garrison."` | runtime flag on the entity; weapon slot exposes `cond_vals` |
| 3 | `PAID_VEHICLE_REPAIR` | bible `"The target is receiving paid land-vehicle repairs."` | **folded statically** into `repair_cost_bp` (stat is only read by credit-charging repair) |
| 10 | `NEAR_FRIENDLY_UNIT` | research/power prose | `{radius_u, unit_ids(+replacements)}` |
| 11 | `NEAR_FRIENDLY_STRUCTURE` | research prose | `{radius_u, structure_ids \| selector, powered}` |
| 12 | `TARGET_NEAR_FRIENDLY_UNIT` | research prose | `{radius_u, unit_ids(+replacements)}` measured around the *target* |
| 13 | `IN_RELAY_FIELD` | NEC | `{powered}` |
| 14 | `STATIONARY` | prose | `{for_t}` ticks without moving |
| 15 | `OUT_OF_COMBAT` | prose | `{for_t}` ticks without dealing/taking damage (firing or damage resets) |
| 16 | `RECENTLY_DISEMBARKED` | prose | `{within_t}` |
| 17 | `DEPLOYED` | prose | ability `deploy` in deployed state |
| 18 | `CAMOUFLAGED` | prose | entity currently concealed |
| 19 | `IN_ZONE` | prose | `{zone_id}` |
| 20 | `STRUCTURE_POWERED` | prose | owner-of-structure power OK |
| 21 | `ON_WATER_RT` | prose (Sealed Compartments) | entity currently over water (runtime form of code 1, for effects) |
| 22 | `BEHIND_COVER` | TAXONOMY §5 | stationary behind portable cover (Vanguard) |

**Placement flags `PlaceFlag`** (bit flags in `DefStructure.place_mask`; from bible `structures[*].conditions[]`): `PLACE_SHORELINE 1` (`"Valid shoreline placement."`), `PLACE_MAX_ONE_STRATEGIC 2` (`"Maximum one strategic structure per player."` — also sets `max_per_player = 1`), `PLACE_NO_RADIUS_EXTENSION 4` (`"Normal construction radius; does not extend it."`).

**Flags.**
`UnitFlag`: `UF_FIRE_STATIONARY 1, UF_HOVER_FIRE 2, UF_NO_COMBAT_MODS 4, UF_NO_COMMAND_BUFF 8, UF_NO_REPAIR 16, UF_NO_CAPTURE 32, UF_NO_SALVAGE 64, UF_NON_BLOCKING 128, UF_HARMLESS 256, UF_PRODUCIBLE 512 (derived), UF_UNARMED 1024 (derived)`.
`WeaponFlag`: `WF_SUPPRESSIVE 1, WF_STATIONARY_FIRE 2, WF_NEEDS_LOS 4, WF_POINT_DEFENSE 8, WF_HOMING 16`.
`StructFlag`: `SF_POWERED_DEFENSE 1, SF_NO_BUILD 2 (HQ), SF_SELLABLE 4, SF_REPAIRABLE 8, SF_CAPTURE_IMMUNE 16, SF_STRATEGIC 32, SF_RELAY 64, SF_PRODUCTION 128`.

**AbilityKind** (ids fixed; parameter specs in §7.4): `1 DETECTOR, 2 CAMOUFLAGE, 3 DEPLOY, 4 MODE_SWITCH, 5 TRANSPORT, 6 HEAL, 7 REPAIR, 8 COMMAND_FIELD, 9 INTERCEPTOR, 10 SUPPRESSION_SUPPORT, 11 DECOY_SPAWN, 12 SENSOR_PUCK, 13 SMOKE_LAUNCHER, 14 EW_JAMMER, 15 DISEMBARK_BUFF, 16 PORTABLE_COVER, 17 SALVAGE, 18 FRONTAL_SHIELD, 19 CARRIER, 20 SENSOR_MAST, 21 CAPTURE, 22 HARVEST, 23 DEPLOY_STRUCTURE, 24 SUBMERGE, 25 SORTIE, 26 SPOTTER, 27 REGEN, 28 DIRECTIONAL_ARMOR, 29 RELAY_FIELD, 30 SERVICE_PADS, 31 REFINERY, 32 AURA_REGEN, 33 DEFENSE_POWER_RESERVE, 34 SUMMON_ORBIT`; `COUNT = 40` (35-39 reserved for reconciler additions; `ability_mask` is one `int`, so ≤ 62).

**Tag bit positions** (fixed for bible tags so hot code uses constants; balance-added tags take bits ≥ first free bit in sorted-name order; max 62 per namespace, V-SCH-08):
* Unit tags `UT_*` = `1 << bit`: `aircraft 0, amphibious 1, anti_air 2, anti_submarine 3, anti_tank 4, artillery 5, capture 6, carrier 7, collector 8, combat 9, command 10, construction 11, detector 12, electronic_warfare 13, ground 14, ground_attack 15, infantry 16, land_vehicle 17, light 18, repair 19, scout 20, service 21, ship 22, siege 23, specialist 24, submarine 25, tank 26, transport 27, unmanned 28`; extras from bit 29.
* Structure tags `ST_*`: `advanced_defense 0, defense 1, relay 2, structure 3, superweapon 4`; extras from bit 5 (free tags for AI/UI, e.g. `anti_air`, `production`).
* Weapon-archetype tags (derived at load from archetype attributes, §5.9.2): `thermal_beam` (damage type thermal), `guided_missile` (`Interceptable == APS_TRIDENT`), `direct_fire`, `indirect_fire`, `anti_air` (targets include air), `anti_ground`, `anti_sub`.
* **Locked tags** — the 15 tags used by bible selectors (`aircraft amphibious artillery combat defense ground infantry land_vehicle light scout ship superweapon tank transport unmanned`) may **never** be added via `tags_add` (V-CNF-03).

### 4.2 Def classes — field lists

**`DefBase`**: `id: String`, `index: int`, `kind: int`, `tags: int`, `params: Dictionary`, `ui_name: String`, `ui_text: String`.

**`DefUnit extends DefBase`** (unit, service unit, summon, drone; base and resolved clone)

| field | type | meaning |
|---|---|---|
| `faction` | int | `DefFaction` index; −1 shared (service units, shared summons) |
| `introduced_by` | int | roster index (unique units); −1 |
| `replaces` | int | unit index this unit replaces (bible `replaces_unit_id`); −1 |
| `replaced_by` | PackedInt32Array | derived: all units whose `replaces` is this unit (ascending) |
| `unit_class` | int | `UnitClass` |
| `tier` | int | 1-3 (0 for SUMMON/DRONE) |
| `producer` | int | structure index (bible `producer_structure_id`); −1 for summons |
| `requires` | PackedInt32Array | structure indices (bible `requires_all_structure_ids`, ascending) |
| `requires_mask` | int | bit *i* = structure index *i* (29 structures ≤ 62) |
| `cost` | int | credits; −1 when not purchasable (summon); for DRONE = replacement cost |
| `build_ticks` | int | ticks (DRONE = replacement time); 0 when not purchasable |
| `pop` | int | unit-cap weight (default 1) |
| `health` | int | hp |
| `armor_class` | int | `ArmorClass` |
| `move_class` | int | `MoveClass` |
| `size_class` | int | `SizeClass` (radius/turn defaults; mass for crush/push rules) |
| `layer_mask` / `home_layer` | int | layers the unit may occupy / spawn layer (defaults from the movement class' layer) |
| `speed` | int | upt on nominal terrain (the movement system multiplies by `DefMoveTable.speed_bp`); 0 = immobile |
| `deep_speed_bp` | int | per-unit override of the class' `DEEP` terrain multiplier (Tide Tank 6000, PD Collector 7000 (bible)); 0 = use `DefMoveTable` |
| `water_mult_bp` | int | multiplier applied on cells the map flags as water (`SHALLOW`, `DEEP`) on top of the terrain table; base 10000; **carries the resolved `ON_WATER` modifiers** (Canada 12000) |
| `accel_t` | int | ticks to full speed (framework `movement_defaults.accel_ticks`) |
| `turn_rate` | int | hull turn, angle units/tick |
| `radius` | int | collision/selection radius (u) |
| `sight` | int | u |
| `flags` | int | `UnitFlag` bits |
| `repair_cost_bp` | int | cost of restoring 100 % health, bp of paid price (base = `economy.repair_cost_bp`) |
| `lifetime_t` | int | ticks; 0 = permanent (summons) |
| `rearm_t` | int | aircraft: pad rearm ticks (`rearm_s_full`; STAT 7 target); 0 = n/a |
| `weapons` | Array[DefWeaponSlot] | resolved slots |
| `abilities` | Array[DefAbility] | ≤ 1 per kind |
| `ability_slot_of_kind` | PackedInt32Array | size `AbilityKind.COUNT`, slot or −1 |
| `cond_vals` | Array[DefCondVal] | conditional variants of unit-level stats |
| `ability_mask` | int | derived; bit per `AbilityKind` |
| `detect_radius` | int | derived (u; 0 none) |
| `cloak_delay_t` | int | derived from `camouflage` (0 none) |
| `max_range` / `min_range` | int | derived over slots (u) |
| `attack_layer_mask` | int | derived: union of slot `target_mask` |
| `weapon_tags` | int | derived: OR of the archetype tag masks of all slots (selector clause `has_weapon_tags`) |
| `transport_squads` / `transport_vehicles` | int | derived from `transport` |
| `speed_water` | int | derived: `DefMoveTable.effective_speed(speed, move_class, DEEP, deep_speed_bp, water_mult_bp)` — the unit's speed on deep water (0 = its class cannot enter deep water); the name the AI spec reads |
| `pres_recipe` `pres_icon` `pres_snd_profile` `pres_ai_role` | String | ids/hints; default recipe/icon = the def id |
| `pres_scale_bp` | int | model scale (10000 = 1.0) |

**`DefWeaponArch extends DefBase`** (27 rows; `id = "warch.<name>"`, `index` = frozen `WeaponArch`): `dtype: int`, `fire_mode: int`, `proj_kind: int`, `proj_speed: int` (upt; 0 = hitscan/beam), `homing: bool`, `target_mask: int` (default layer targets), `splash_radius: int`, `splash_edge_bp: int`, `scatter: int`, `range_lo/range_hi: int` (u band), `min_range: int`, `reload_lo_mt/reload_hi_mt: int`, `turret_turn: int` (apt), `interceptable: int`, `suppressive_default: bool`, `tags` (derived weapon tags), `params`.

**There is no `DefWeapon` and no `DefProjectile` class.** TAXONOMY makes projectile kind, speed, homing and interceptability attributes of the 27 weapon archetypes, and every weapon is a per-owner instance of one archetype, so the two roles are `DefWeaponArch` (the shared, locked attributes and bands) and `DefWeaponSlot` (the owner's numbers). A bible "projectile" selector therefore matches slots by their archetype's derived tags (§5.4).

**`DefWeaponSlot`** (a weapon instance on a unit/structure; the resolved numbers **combat reads**): `arch: int` (`WeaponArch`), `slot: int`, `mount: int` (0 hull, 1 turret), `mode_mask: int` (bit *m* = active in mode *m*; 0 = always; mode 0 = mobile/default, `deploy` deployed = mode 1, `mode_switch` modes numbered in declaration order), `damage: int` (per hit), `hits_per_volley: int`, `dtype: int` (from the archetype, locked), `fire_mode: int` (locked), `interceptable: int` (locked), `proj_kind: int` (locked), `range: int` (u), `min_range: int` (u), `reload_mt: int`, `reload_ticks: int` (= `ceil_div(reload_mt, 1000)`, ≥ 1; conservative fallback), `proj_speed: int` (upt), `homing: bool`, `splash_radius: int`, `splash_edge_bp: int`, `scatter: int`, `target_mask: int` (layers), `flags: int` (`WeaponFlag`), `ammo_volleys: int` (0 = unlimited), `turret_turn: int` (apt; 0 fixed), `fire_arc: int` (angle units), `ramp_t: int`, `ramp_max_bp: int` (continuous beams: focus time and max damage multiplier, e.g. 5 s / 15000), `deploy_t: int` (artillery deploy, informational), `requires_surface_t: int` (submarine cruise missile: the boat must have been surfaced this long; 0 = none), `cond_vals: Array[DefCondVal]`.

**`DefDamageTable`**: `damage_ids: PackedStringArray` (index = `DamageType`), `group_mask: PackedInt32Array` (per damage type), `nonlethal_mask: int` (bit per damage type), `armor_ids: PackedStringArray` (index = `ArmorClass`), `matrix_pct: PackedInt32Array` (`[dtype * 11 + armor]`, integer percent exactly as in `global.json`; 0 = cannot damage), `matrix_bp: PackedInt32Array` (derived, `matrix_pct · 100`; the shape the AI spec reads as `dmg_matrix_bp`), `resist_cap_bp: int`, `min_damage: int` (1).

**`DefMoveTable`**: `speed_bp: PackedInt32Array` (`[move_class * 8 + terrain_kind]`; 0 = impassable, 10000 = nominal; from `movement_classes[*].terrain_speed_pct`), `layer: PackedInt32Array` (per `MoveClass`, `Layer`), `layer_mask: PackedInt32Array` (per class: default `layer_mask`; AMPHIBIOUS = `L_GROUND|L_WATER`, SUBMERGED = `L_UNDER|L_WATER`).

**`DefBodyTable`**: per `SizeClass`: `radius_u`, `turn_apt`, `mass`, `is_structure: bool`, `fp_w`, `fp_h` (structures s1..s4).

**`DefStructure extends DefBase`**: `faction`, `requires`, `requires_mask`, `cost`, `build_ticks` (0 with `SF_NO_BUILD`), `power` (signed; + supply, − demand; bible `power_supply_delta`), `health`, `armor_class`, `size_class` (s1-s4), `radius` (u), `fp_w`, `fp_h` (cells), `fp_mask: PackedByteArray` (empty = solid rectangle, else row-major `fp_w*fp_h`, 1 = blocked), `exit_dx`, `exit_dy` (cell offset of unit exit), `sight`, `flags` (StructFlag), `queue_kind`, `queues` (1), `max_per_player` (0 = unlimited), `place_mask`, `build_radius` (u; HQ = 8 cells; 0 otherwise), `deploy_unit` (unit index, HQ ← MCV; else −1), `deploy_t` (HQ deploy ticks), `starts_deployed: bool`, `superweapon` (index if launcher else −1), `repair_rate_bp` (base 10000), `repair_cost_bp`, `sell_bp`, `detect_radius`, `pads` (Airfield), `weapon_tags` (derived), `weapons`, `abilities`, `ability_slot_of_kind`, `ability_mask`, `cond_vals`, `pres_recipe`, `pres_icon`, `pres_snd_profile`.

**`DefAbility`**: `id: String` (template id; "" for an inline/instance ability), `index: int` (index in `GameData.abilities` for templates; −1 for instances), `kind: int`, `template: int` (for instances: the template index it came from, else −1), `slot: int` (position in the owner's `abilities`), `stack_group: int` (−1), `params: Dictionary` (converted; runtime-suffixed keys; every default materialised).
**`DefCondVal`**: `stat: int`, `cond: int`, `value: int`.
**`DefEffect`**: `op: int`, `stat: int` (−1), `delta_bp: int` (STAT_MOD delta / RESIST_MOD reduction), `group_mask: int` (RESIST_MOD: `ResistGroup` bits; **0 = every weapon group except EMP**), `fire_mode_mask: int` (bit per `FireMode`; 0 = any), `frontal_arc_a: int` (0 = none; full-front arc in angle units), `selector: int` (−1 = none), `cond_codes: PackedInt32Array`, `cond_params: Array[Dictionary]` (parallel), `duration_t: int` (0 = permanent), `stack_group: int` (−1), `membership: int`, `scope: int` (ParamScope), `param_op: int`, `key: String` (runtime key, e.g. `cooldown_t`), `value: int`, `ability_kind: int` (−1), `ability: DefAbility` (GRANT_ABILITY payload or null), `flag: String`, `filter: Dictionary`, `params: Dictionary`.
**`DefCondApplication`**: `modifier: int`, `cond: int`, `stat: int`, `delta_bp: int`, `layer: int`, `units: PackedInt32Array`, `structures: PackedInt32Array`.
**`DefModifier`**: `owner_is_roster: bool`, `owner: int` (faction or roster index), `layer: int` (1 parent, 2 subfaction), `stat: int`, `delta_bp: int` (bible percent × 100), `selector: int`, `cond: int` (selector's single bible condition or 0), `ui_source_text`.
**`DefSelector`**: `kind_mask: int` (bit per `Kind`: UNIT, STRUCTURE, WEAPON_ARCH, PROJECTILE), `unit_all/unit_any/unit_none: int`, `struct_all/struct_any/struct_none: int`, `weapon_all/weapon_any/weapon_none: int`, `proj_all/proj_any/proj_none: int` (tag masks in the respective namespace; for the PROJECTILE kind the tags are the archetype's derived weapon tags), `has_weapon_mask: int` (unit/structure kinds: entity must own ≥ 1 slot whose archetype has any of these weapon tags; 0 = no clause), `explicit_units: PackedInt32Array`, `explicit_structs: PackedInt32Array` (sorted), `include_replacements: bool`, `unit_class_mask: int` (0 = any), `extra_superweapons: PackedInt32Array`, `cond: int`, `unresolved: int` (0 none, 1 carrier drones, 2 thermal-beam, 3 guided missiles).
**`DefResearch`**: `faction`, `introduced_by`, `tier` (2\|3), `cost`, `time_t`, `requires_mask`, `inherited: bool`, `effects: Array[DefEffect]`, `ui_effect_text`. **`DefPower`**: `faction`, `introduced_by`, `tier`, `cost`, `cooldown_t`, `requires_mask`, `requires_powered: bool`, `target_mode`, `target_vision`, `radius`, `length`, `width` (u), `warning_t`, `actions: Array[DefPowerAction]`, `ui_effect_text`. **`DefPowerAction`**: `op, zone (-1), summon (-1), count, radius, duration_t, warning_t, effects: Array[DefEffect], impacts: Array[DefImpactPacket], params`.
**`DefSuperweapon`**: `faction`, `launcher` (structure), `requires_mask`, `recharge_t`, `warning_t`, `max_charges` (1), `starts_charged` (false), `target_vision` (EXPLORED), `action_kind` (SwAction), `packets: Array[DefImpactPacket]`, `zone`, `summon`, `summon_count`, `radius`, `duration_t`, `params`. **`DefImpactPacket`**: `damage, dtype, radius, edge_bp, delay_t, offset_x, offset_y (u, local frame: +x along the committed line/orientation), target_mask, non_lethal: bool, params`.
**`DefZone`**: `zone_kind, shape, radius, length, width, duration_t, affects, follow_source: bool, hp (0 = indestructible), target_mask, visible_to_enemy: bool, max_per_owner (0 = unlimited), effects: Array[DefEffect]`, `params`, `pres_recipe`.
**`DefNeutral`**: `neutral_kind, health, armor_class, fp_w, fp_h, sight, capturable: bool, capture_t, garrison_squads, reward: Dictionary (credits_cr, power_n, reveal_radius_u, income_mcpt; deposits: credits_per_cell_cr, cells_n), params, pres_recipe`.
**`DefFaction`**: `code: String` ("NAPC"), `baseline_units` (bible order), `structures`, `shared_research`, `shared_powers`, `vanilla_power`, `superweapon`, `vanilla_roster`, `sub_rosters`, `passive_modifiers`, `grants: Array[DefEffect]` (GRANT_ABILITY records applied to roster clones at build time), `player_params: Dictionary`, `ui_motto/lore/identity/opening/counterplay`, `ui_traits: PackedStringArray`, `pres_palette`.

**`DefEconomy`** — every field `int`; names are the **runtime-suffixed** names the converter produces (§5.10.1). ★ = bible-fixed (validated by V-CNF-05, authoritative over any file). Source: `game/data/balance/global.json` blocks `production`, `economy`, `power`, `detection`, `resistance_rules` (design values of the balance framework), overridden field-by-field by `economy.json` when the economy domain supplies it (§7.0).

| group | fields (runtime name = value in current `global.json`; ★ bible) |
|---|---|
| rules | `start_cr` 7500★ ← `economy.start_credits`; `unit_cap_n` 150 (ARCH §12); `queue_length_n` 5 ← `production.queue_length`; `build_radius_u` 8192★ (bible HQ text); `power_shortage_rate_bp` 5000★ ← `production.power_shortage_speed_pct`; `cancel_refund_bp` 10000; `sell_refund_bp` 5000 |
| harvest | `collector_capacity_cr` 600 ← `economy.collector.capacity_credits`; `harvest_mcpt` 1000 ← `harvest_credits_per_pulse/harvest_pulse_ticks` (1 credit/tick = 20 cr/s); `unload_mcpt` 6000 ← `unload_credits_per_pulse/unload_pulse_ticks`; `unload_overhead_t` 40; `refinery_free_collectors_n` 1★; `deposit_cr_per_cell` 600 / `deposit_rich_cr_per_cell` 1200 ← `economy.deposit` |
| repair | `repair_rate_bps` 100★ ← `economy.repair.engineer_pct_per_s_x100`; `repair_cost_bp` 5000★ ← `full_repair_cost_pct_of_price` (0.5 % of price per 1 % hp); `regen_out_of_combat_t` 120★ (6 s, apron/Section Logistics/Watershed/Fuel Caches) |
| research | `research_tier2_t` 900★, `research_tier3_t` 1500★ (bible `mechanical_conventions`) |
| floors/caps | `floor_cost_bp` 6000★ ← `production.cost_floor_pct`; `floor_build_bp` 6000★; `floor_reload_bp` 5000★; `floor_rearm_bp` 5000 (balance); `resist_cap_bp` 5000★ ← `resistance_rules.cap_pct`; `min_damage` 1 |
| vision | `detector_default_radius_u` 5120★ ← `detection.default_radius_cells`; `watchtower_detect_u` 4096★; `aa_battery_detect_u` 5120★; `camouflage_default_delay_t` 120★ |
| combat | `suppress_hits_n` 3★; `suppress_window_t` 40★; `suppress_slow_bp` 2500★; `suppress_t` 60★; `cover_build_t` 80★; `cover_life_t` 900★; `cover_resist_bp` 2000★; `wreck_life_t` 1200★; `salvage_t` 160★; `salvage_payout_bp` 2000★; `sub_surface_t` 160★; `garrison_squads_n` 4★; `transport_default_squads_n` 2★; `intercept_packet_charges_n` 8★; `intercept_packet_reduction_bp` 5000★ |

### 4.3 Roster-level tables produced by `DefRosterBuilder` (memory layout)

`DefRoster.units` / `.structures` are dense arrays sized to the *global* counts (index = def index) with `null` holes, so the sim does `roster.units[e.def]` without hashing. With ≈ 190 unit defs and 29 structures a roster stores ≈ 40 non-null objects; 33 rosters ≈ 1,300 small objects (~2 MB total). Weapon slots and abilities of a clone are **deep copies** (a resolved slot never aliases the base slot). Besides the baked values a roster stores the layer sums it folded: `sums_s1` / `sums_s2: PackedInt32Array` indexed `[(kind_slot * def_count + def) * 13 + stat]` (`kind_slot` 0 units, 1 structures; 13 = `STAT_COUNT_BIBLE`), exposed by `DefRoster.static_sums`; they are part of the roster hash.

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Loading pipeline (bible JSON + balance JSON → int-only Def tables)

`DefLoader.build(src, level)` runs these phases in order. Every loop iterates **sorted ids or sorted keys** (never file order, never directory order). Any `ERROR` aborts after the phase finishes (so one run reports many problems) and `build` returns `null`.

| Phase | Work | Output |
|---|---|---|
| **P0 Read** (`DefSources.from_disk`) | Read `balance/manifest.json` (`{"format":1,"files":[sorted unique relative paths]}`); read the bible; for every file: `FileAccess.get_file_as_string`, strip a UTF-8 BOM, `JSON.new().parse(text)` (error → `V-SCH-01 path:line: msg`), require top-level object. **No `DirAccess` listing** — the manifest is the file list (platform-independent order, DR-6). | `DefSources` |
| **P1 Source validation** | `DefValidator.validate_sources` (FULL: all `V-SCH/REF/CMP/CNF/RNG`; FAST: `V-SCH-01/02`, counts, `V-CMP-01..03`). | report |
| **P2 Vocabularies** | `global.json` (balance framework, §7.3) → `DefDamageTable` (`damage_types`, `resist_groups`, `armor_classes`, `damage_matrix`, `resistance_rules`), `DefMoveTable` (`terrain_kinds`, `movement_classes`), `DefBodyTable` (`size_classes`), `DefWeaponArch` ×27 (`weapon_archetypes`), `DefEconomy` (`production`, `economy`, `power`, `detection`; then **bible `mechanical_conventions` values are authoritative** and overwrite/verify: floors 60/60/50 %, cap 50 %, shortage 50 %, research 45/75 s, start 7500), `DefTags` (bible tag sets must be ⊆ the fixed tables of §4.1; extras from the sheets' `tags_add`). **Every vocabulary entry is checked against the frozen `DefEnums` codes (`V-CNF-05`).** | `damage`, `moves`, `bodies`, `weapon_archs`, `economy`, `tags` |
| **P3 Ids** | Collect ids per kind (bible registries + balance-owned ids), `DefIds.assign` per kind (code-point sort, duplicate/prefix check). **Frozen enumerations are not sorted**: weapon archetypes (`warch.<name>`), damage types, armor classes, size classes, movement classes, terrain kinds take their TAXONOMY/`global.json` `index`. Inline selectors are numbered later (P6) and appended after the sorted named selectors. Domain compilers run `collect_ids` here (§3.12). | index maps |
| **P4 Base defs** | structures (bible + `global.json → structures/defenses` + overlay `structures.json`) → units (bible fields ⊕ `units_<code>.json` sheets per §5.2.4, role-archetype defaults, weapon slots from archetypes, abilities) → ability templates → zones → neutrals; then each `DefDomainCompiler.compile`. All cross references are **strings → indices** through the P3 maps, so P4 order is irrelevant to correctness. | base `Def*` |
| **P5 Derived caches** | `requires_mask`, `ability_slot_of_kind`, `ability_mask`, `detect_radius`, `cloak_delay_t`, `max_range`, `min_range`, `attack_layer_mask`, `transport_*`, `replaced_by`, `UF_PRODUCIBLE`, `UF_UNARMED`. | |
| **P6 Rules** | research → powers → superweapons → factions (+ traits) → effects (selectors/conditions compiled; inline selectors appended; `stack_groups` registry sorted). | rule defs |
| **P7 Modifiers** | bible `modifiers` → `DefModifier` (sorted by id); bible `selectors` → `DefSelector` (§5.4). | |
| **P8 Rosters** | `DefRosterBuilder.build_all`: 32 rosters + `base_roster` (§5.7). | `rosters` |
| **P9 Validate + hash + freeze** | `DefValidator.validate_data` (+ each compiler's `validate`); `table_hashes` (core + compilers), `data_hash` (§5.11); publish. | `GameData` |

Budget: ≈ 150–250 ms total on a mid-range CPU (§9). `level = LEVEL_FAST` (release) skips the expensive cross-checks (`V-CNF-06`, `V-MOD-12`, `V-ROLE-*`, `V-TIER-04`), but **all** structural/reference errors still abort the load.

### 5.2 Numeric conversion — designer units → ints (implements ARCHITECTURE §3)

#### 5.2.1 The one float step (`DefNumParse.milli`, the only float-touching function in `src/data`)

Godot's `JSON` yields `float` for every number (verified: `{"a":1}` → `1.0`). Decimal→double parsing could differ by an ulp between builds, and `ceili(seconds * 20.0)` is a known trap (`ceili(21.000000000000004) == 22`). Therefore:

```
milli(v):  m = float(v) * 1000.0 ;  r = roundi(m)                       # roundi = half away from zero
           if not is_finite(m) or abs(m - float(r)) > 0.001 or abs(r) >= 2^40:  V-SCH-04 (more than 3 decimals / NaN / huge)
           return r                                                     # exact integer milli-units
```
Legal designer numbers have ≤ 3 decimals, so `|m − r| < 1e-9` on every IEEE-754 platform and the rounding is unambiguous. The function lives in `def_num_parse.gd` because the project linter (L003) forbids float literals, types and builtins in `src/data` except in files named `*_loader.gd` / `*_parse.gd`; every other file receives the JSON value as an untyped `Variant` and passes it straight to `DefNumParse.milli`. **All later arithmetic is integer.** Integer-typed fields (credits, hp, counts, tier…) additionally require `r % 1000 == 0` (`V-SCH-05`) and use `r / 1000`.

#### 5.2.2 Conversion table (`T = SimConfig.TPS = 20`, `CELL = Fp.CELL = 1024`, `TURN = Fp.TURN = 4096`)

| file unit (suffix) | runtime unit (suffix) | formula on milli `x` | notes / examples |
|---|---|---|---|
| cells (`_cells`) | u (`_u`) | `rdiv(x·CELL, 1000)` | 7.0 → 7168; 0.55 → 563; 1.0 → 1024; 0.001 → 1 |
| cells/second (`_cells_s`) | upt (`_upt`) | `rdiv(x·CELL, 1000·T)` | 1.0 → 51 (51.2); 2.0 → 102 (102.4); 3.2 → 164 (163.84); 16.0 → 819 |
| seconds (`_s`) | ticks (`_t`) | `ceil_div(x·T, 1000)` | 1.05 → 21; 1.051 → 22; 0.05 → 1; 0.06 → 2; 8 → 160; 45 → 900; 75 → 1500 |
| seconds, reload (weapon `reload_s`; param `_smt`) | milli-ticks (`_mt`) | `x·T` (exact, no rounding) | 1.2 → 24000 mt (= 24.000 ticks); 0.25 → 5000 mt |
| percent (`_pct`) | basis points (`_bp`) | `rdiv(x·100, 1000)` | 10 → 1000; 0.5 → 50; 12.5 → 1250; ≤ 2 decimals allowed (`V-SCH-06`) |
| bible `delta_percent` (int) | `delta_bp` | `pct·100` | +10 → 1000, −15 → −1500 |
| degrees (`_deg`) | angle units (`_a`) | `rdiv(x·TURN, 360000)` | 90 → 1024; 360 → 4096 |
| degrees/second (`_deg_s`) | angle/tick (`_apt`) | `max(1, rdiv(x·TURN, 360000·T))` for x > 0 | 180 → 102; 90 → 51; 120 → 68 |
| credits/second (`_crps`) | milli-credits/tick (`_mcpt`) | `rdiv(x, T)` | 100 cr/s → 5000 |
| percent/second (`_pcts`) | bp/second (`_bps`) | `rdiv(x·100, 1000)` | 1 %/s → 100 |
| hundredths (`_x100`) | same suffix | passthrough int (the framework's `*_x100` fields are already scaled) | `pct_max_health_per_s_x100: 200` = 2.00 %/s |
| credits `_credits`, hit points `_hp`, counts `_n`, dimensionless `_x` | `_cr`, `_hp`, `_n`, `_x` | `x / 1000` (integral required) | |
| bible fraction constants (0.6, 0.5) | bp | `rdiv(x·10000, 1000)` | 0.6 → 6000; 0.5 → 5000 |

`rdiv(n, d) = (2·|n| + d) / (2·d) · sign(n)` with truncating integer division; for `n ≥ 0` this is **half-up**. `ceil_div(n, d) = (n + d − 1) / d` for `n ≥ 0`. Non-zero converted speeds must be ≥ 1 upt, ranges ≥ 1 u, durations ≥ 1 t (`V-RNG-03`). Reload is the only duration kept sub-tick: repeated ±10 % modifiers on 4-6 tick weapons would otherwise quantise to 0 %/±20 %; with `mt` the average rate is exact provided combat uses an absolute `next_fire_mt` accumulator (ASSUMPTION(combat), CMR-10; `reload_ticks = ceil_div(reload_mt, 1000)` is the conservative fallback).

#### 5.2.3 Parity with Python
`tools/py/gen_convert_vectors.py` writes `game/tests/golden/convert_vectors.json` (≥ 300 cases: every row above, both sides of every rounding boundary, 0, negatives for offsets, 2-3 decimal edge cases, rejected inputs). `test_data_convert.gd` asserts GDScript = vectors; `validate_balance.py --self-test` asserts Python = vectors.

#### 5.2.4 Bible ⊕ balance merge policy (null handling)

For every field that the bible *also* specifies:

| bible | balance | result |
|---|---|---|
| non-null | absent | bible value (converted) |
| non-null | present, equal (after conversion) | bible value; `V-CNF-02` INFO "redundant" (WARN under `--strict-redundant`) |
| non-null | present, different | **ERROR `V-CNF-01`** listing both values (never a silent override) |
| `null` | present | balance value |
| `null` | absent | **ERROR `V-CMP-04`** (incomplete) unless the def is exempt (summons without `cost`, `SF_NO_BUILD` structures without `build_time`) |

Mapping of bible unit `base_stats` → sheet fields → Def fields: `cost_credits → cost_credits → cost`, `build_time_seconds → build_time_s → build_ticks`, `health → health → health`, `movement_speed → speed_cells_s → speed` (bible unit: cells/second), `damage → weapons[0].damage`, `weapon_range_cells → weapons[0].range_cells` (a non-null bible `damage`/`weapon_range_cells` binds **slot 0**). Structures: `cost_credits`, `build_time_seconds → build_time_s`, `power_supply_delta → power_delta` (always non-null; `global.json → structures` must repeat it identically, `V-CNF-01`). Research/powers/superweapons: cost, tier, cooldown, recharge, warning, time are bible-only (balance may not set them: `V-CNF-04`; `global.json → superweapons.<w>.recharge_s/warning_s` are bible copies and are verified equal). Bible **tags are immutable**; balance may only add non-locked tags (`tags_add`).

### 5.3 Def index assignment and id maps

* One namespace per `Kind`. Ids of a kind are sorted with GDScript `Array[String].sort()` (code-point order, verified: `.`(0x2E) < digits < `_`(0x5F) < `a-z`), duplicates are an error, and the **position is the dense index**. Examples (final, since the sets are fixed by the bible): factions `0 ae, 1 def, 2 han, 3 napc, 4 nec, 5 olm, 6 pd, 7 sap`; superweapons `0 ae.horizon_mass_driver … 7 sap.trident_interception_array`; structures `0 ae.forge_cannon, 1 ae.horizon_mass_driver, 2 def.citadel_mortar, 3 def.perun_missile_complex, 4 han.dragon_tooth_launcher, 5 han.dragonfall_field_foundry, 6 napc.atlas_kinetic_array, 7 napc.bulwark_cannon, 8 nec.aurora_microwave_array, 9 nec.lance_rail_emplacement, 10 nec.relay, 11 olm.helios_reflector, 12 olm.sunwall_projector, 13 pd.sea_spear_battery, 14 pd.tempest_swarm_hub, 15 sap.bastion_missile_tower, 16 sap.trident_interception_array, 17 shared.aa_battery, 18 shared.airfield, 19 shared.anti_tank_turret, 20 shared.barracks, 21 shared.dock, 22 shared.factory, 23 shared.generator, 24 shared.headquarters, 25 shared.laboratory, 26 shared.radar, 27 shared.refinery, 28 shared.watchtower` (so a T3 factory unit has `requires_mask = 1<<22 | 1<<26 | 1<<25`); rosters `0 ae.kongo, 1 ae.nigeria, 2 ae.south_africa, 3 ae.vanilla, 4 def.kazakhstan, 5 def.north_korea, 6 def.russia, 7 def.vanilla, 8 han.cambodia, 9 han.china, 10 han.vanilla, 11 han.vietnam, 12 napc.canada, 13 napc.mexico, 14 napc.usa, 15 napc.vanilla, 16 nec.alpine_brotherhood, 17 nec.eurocorps, 18 nec.nordics, 19 nec.vanilla, 20 olm.algeria, 21 olm.el_andalus, 22 olm.saudi_arabia, 23 olm.vanilla, 24 pd.australia, 25 pd.indonesia, 26 pd.japan, 27 pd.vanilla, 28 sap.india, 29 sap.pakistan, 30 sap.thailand, 31 sap.vanilla`.
* **Frozen enumerations** (not id-sorted): `WeaponArch` (27, ids `warch.<name>`), `DamageType`, `ArmorClass`, `SizeClass`, `MoveClass`, `TerrainKind`, `Layer`, `FireMode` use the indices of TAXONOMY/`global.json`; the loader verifies each and refuses to start on any deviation (`V-CNF-05`).
* Units: 156 bible ids + balance `summon.*` ids in one table; `summon.*` sort before `unit.*`, so absolute unit indices shift when a summon is added. That is intentional and harmless: indices are internal, the hash covers them, replays record `table_hashes["ids"]`.
* Indices are never persisted anywhere except replays/desync dumps (which also store the id-table hash). Saved games/settings use string ids.
* `DefIds` refuses ids that violate `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$` and ids whose prefix does not match the kind (`V-SCH-03`).

### 5.4 Tags, selectors and the unresolved domains

#### 5.4.1 Tag namespaces
Each entity kind that selectors can address has its own tag namespace and bitmask: **unit**, **structure**, **weapon** (= the derived tags of a weapon *archetype*, §5.9.2) and **projectile** (same derived tags: projectile kind, speed and interceptability live on the archetype), managed by `DefTags`. Bible tags have the fixed bit positions of §4.1; balance may add *free* tags via `tags_add` (unit/structure entries). A tag name that is unknown in a namespace has mask `0`: as an `all_tags` member it makes the selector unmatchable for that kind (`V-MOD-02` ERROR if unmatchable for *every* kind the selector lists), inside `any_tags`/`exclude_tags` it is ignored with a WARN.

#### 5.4.2 Compilation (`DefResolver.compile_selector`)
Input is the bible shape `{entity_kinds, all_tags, any_tags, exclude_tags, explicit_entity_ids, conditions, additional_superweapon_ids, unresolved_target_domain}` (bible selectors; balance-owned `selector.balance.*` blocks, §7.5) **or** the inline shape used inside effects: `{"kinds":[..], "tags_all":[..], "tags_any":[..], "tags_none":[..], "unit_ids":[..], "structure_ids":[..], "include_replacements":bool, "classes":["baseline","unique",…]}`. Output `DefSelector` (§4.2). `conditions[]` maps to one `cond` code via the table in §5.9.1 (more than one condition, or an unknown string ⇒ ERROR `V-MOD-04`). `unresolved_target_domain` maps to `unresolved` 1/2/3 by exact string (§5.9.2) and the built-in resolution of that domain is applied (adds the derived archetype tags `thermal_beam` / `guided_missile` to `weapon_all`/`proj_all`); an unknown string ⇒ ERROR `V-MOD-05`.

#### 5.4.3 Match semantics (identical to the bible's own `validate_reference.py`; enforced by the golden test `V-MOD-12`)
An entity of kind `K` with tag mask `T` and index `i` (and unit class `C`) is matched iff
`kind_mask ∋ K` **and** (`explicit_K` empty **or** `i ∈ explicit_K`) **and** `T & all == all` **and** (`any == 0` **or** `T & any ≠ 0`) **and** `T & none == 0` **and** (`unit_class_mask == 0` **or** `C ∈ unit_class_mask`) **and** (`has_weapon_mask == 0` **or** `weapon_tags & has_weapon_mask ≠ 0`, units/structures only). Explicit ids and tags are **conjunctive** (for the three explicit selectors the tag lists are empty). A **superweapon** is matched iff its index ∈ `extra_superweapons` (bible `additional_superweapon_ids`) and it is the roster's superweapon. For units, `T` is the roster-effective mask = base tags ∪ `unit_overrides.add_tags`. With `include_replacements`, an explicit unit id `x` also matches every roster unit `u` whose `replaces` chain reaches `x` (chain length is 1 in the bible; implemented as a loop with a depth cap of 4).

#### 5.4.4 Golden conformance (the proof that selector semantics are right)
For each of the 32 rosters and each entry of `rosters[*].resolved.modifier_applications` (158 entries), `DefRoster.selector_units/structures` of the compiled selector must equal `eligible_unit_ids` / `eligible_structure_ids`, and the superweapon match must equal `eligible_superweapon_ids`; `conditions` must equal the selector's; `unresolved_target_domain` must equal the selector's. This is a load-time check in FULL mode and a unit test (`test_data_resolver.gd::golden_applications`). Verified with both a Python prototype and a throw-away GDScript prototype on Godot 4.7.2 (fixed tag-bit tables of §4.1, availability per §5.7, matching per §5.4.3): **156 units / 29 structures / 0 unknown bible tags; the 32 availability lists and 32 modifier lists equal the bible's `resolved` block; 0 mismatches over all 158 applications** (152 unconditional, 6 conditional: Canada ×1 `ON_WATER`, El Andalus ×1 `IN_CIVILIAN_GARRISON`, the four AE rosters ×1 `PAID_VEHICLE_REPAIR`). The unoptimised GDScript loop (dictionary-based, all 32 rosters + all 158 comparisons) took **6 ms**.

The 27 selectors, with tag sets, match counts over the 156 bible units / 29 structures, and how many modifiers use each, are listed in **Appendix 5.14.1**.

### 5.5 The modifier model (layers, rounding, floors/caps, conditionals, stacking, scope)

#### 5.5.1 Layers
| L | name | source | applied | 
|---|---|---|---|
| 0 | base specification | bible value (if non-null) else balance value, converted (§5.2) | — |
| 1 | `parent_faction` | bible modifiers whose `layer == "parent_faction"` (owner `faction.*`, 20 of them) | at roster build |
| 2 | `subfaction` | bible modifiers whose `layer == "subfaction"` (owner `roster.*`, 78 of them) | at roster build |
| 3 | `research_and_temporary_effects` | research effects (permanent), power/aura/zone effects (timed) | at runtime, by `DefLayer3` + abilities |

The loader verifies `owner` prefix ↔ `layer` (`faction.` ⇒ 1, `roster.` ⇒ 2; `V-MOD-03`). A vanilla roster uses layer 1 only; a subfaction uses its faction's layer-1 modifiers plus its own layer-2 modifiers (`resolved.modifier_ids = faction.passive_modifier_ids + roster.own_modifier_ids`, re-derived and verified).

#### 5.5.2 Accumulation
For a roster, every applicable modifier is matched against every entity of the roster (§5.5.6 says which entity/field a stat targets) and adds its `delta_bp` to `S[L]` of that `(target, stat)`. **Within a layer, deltas of the same stat add** (`S_L = Σ Δ`); the bible has no same-layer overlap today (0 cases in 158 applications) but layer 3 does (Relay + Combined Arms Window + command field), so the rule is implemented and tested. **No same-source stacking**: a modifier id is applied at most once per target (a roster lists each id once), and the loader rejects two modifiers with equal `(owner, stat, selector)` in one roster (`V-MOD-09`).

#### 5.5.3 Formulas
```
static  (layers 0-2, at load):  resolved = clamp_stat( stat, base, half_up( base · (10000 + S1) · (10000 + S2) / 10^8 ) )
runtime (layer 3):              effective = clamp_stat( stat, base, half_up( resolved · (10000 + S3) / 10^4 ) )
half_up(n / d) = (2n + d) / (2d)   [n ≥ 0]         factor (10000 + S) is clamped to ≥ 0
```
This is the bible's `base × Π_layers(1 + ΣΔ/100)` with **one rounding for layers 0-2** (exact rational arithmetic; e.g. 1.10 × 0.90 = 0.99 exactly) and a **second rounding for layer 3** (the sim caches `resolved`, so re-folding from base each time a buff toggles is avoided; the deviation from a single-shot fold is ≤ 1 unit and is identical on every peer). Overflow bound: `base ≤ 100 000` (validator `V-RNG-01`) and each factor ≤ 30 000 ⇒ `100000 · 30000 · 30000 = 9·10^13 ≪ 2^62`.

#### 5.5.4 Floors, caps and clamps (`DefStatMath.clamp_stat`; values come from `DefEconomy`, i.e. the bible `mechanical_conventions`)
| stat | rule |
|---|---|
| `COST`, `BUILD_TIME` | `v ≥ ceil_div(base · 6000, 10000)` when `base > 0` ("cannot fall below 60 % of the base specification"; **ceil** so the result is never below 60 %). Applies at both stages. Static duration modifiers scale the *duration* (−20 % ⇒ 0.80×); "faster production" is the separate rate stat `PROD_RATE` and never touches `build_ticks`. |
| `RELOAD` | `v ≥ max(1, ceil_div(base · 5000, 10000))` ("reload interval cannot fall below 50 %"). |
| `REARM` | same 50 % floor (`floor_rearm_bp`, a balance decision; the bible is silent). |
| damage resistance | `resist_total = min(max(Σ_sources bp, 0), 5000)`; sources add (§5.8.3); a successful *projectile interception* bypasses the cap (combat logic). |
| `HEALTH`, `SPEED`, `SIGHT`, `RANGE`, `PROJ_SPEED`, `DAMAGE` | `v ≥ 1` (a stat with base 0 is a no-op target, see below). |
| `POWER`, `REPAIR_COST` | `v ≥ 0`; `POWER` applies only to `power > 0` (generators). |
| base = 0 / not applicable | modifier is a **no-op**, reported as INFO (`V-MOD-06`): HQ `cost`/`build_time` (`SF_NO_BUILD`), immobile `speed`, hitscan `proj_speed`, unarmed unit `DAMAGE`. Running all 158 applications of the real bible over stub bases yields **570 effective (target, modifier) applications and exactly 2 no-ops**: Nigeria's structure build-time bonus on the HQ (null build time, `SF_NO_BUILD`) and El Andalus' garrison damage bonus on the unarmed Mirage Observer. |

#### 5.5.5 Conditional modifiers (selector `conditions[]` ≠ ∅)
The resolver **never applies a conditional modifier to the unconditional sums.** It supports exactly the combinations below (anything else is `V-MOD-07` ERROR — extend this table together with the abilities domain):

| cond | stat | compile-time handling | runtime cost |
|---|---|---|---|
| `ON_WATER` | `SPEED` | the delta is added to the layer sums of `water_mult_bp` **only** (base 10000; `speed` on land is untouched). Canada Beaver: `fold2(10000, 0, 2000) = 12000`. | none (movement multiplies `speed × DefMoveTable.speed_bp × water_mult_bp` on water cells; TAXONOMY §8: "bible water-speed bonuses are modifiers on top of the table") |
| `IN_CIVILIAN_GARRISON` | `DAMAGE` | for every slot of every matched unit: `cond_vals += {stat:DAMAGE, cond:2, value: resolve(base, S1+C1, S2+C2)}` where `C_L` = Σ conditional deltas of layer *L*. | combat reads `slot.value_when(DAMAGE, 2, slot.damage)` when the shooter is garrisoned |
| `PAID_VEHICLE_REPAIR` | `REPAIR_COST` | `repair_cost_bp` is *only* read by repair sources that charge credits, so the condition is inherently true where the stat is used ⇒ folded into `repair_cost_bp` of every matched unit (AE: `5000 → 3750`). Free repairs (powers, stations) never read it. | none |

At most **one distinct condition per (target, stat)** (`V-MOD-08`); the resolver stores one `DefCondVal` per (stat, cond) with the full layered value (not a delta), so consumers never re-fold.

#### 5.5.6 Which entity and field a stat targets (selector `entity_kinds` decides the domain)
* `unit` selector → the roster's unit clones (SERVICE, BASELINE, UNIQUE, DRONE; SUMMON only if tagged so — they are not, §5.9.2 U1). Stats `DAMAGE/RANGE/RELOAD/PROJ_SPEED` expand to **every weapon slot** of the matched unit (all modes).
* `structure` selector → the roster's structure clones; weapon stats expand to the structure's slots.
* `weapon` selector → every slot (of any unit or structure of the roster) whose **weapon archetype's derived tags** (`DefWeaponArch.tags`, §5.9.2) match; `projectile` selector → every slot whose archetype's derived tags match (projectile kind, speed and interceptability are archetype attributes, so both kinds use the same tag namespace).
* `additional_superweapon_ids` → the roster's `superweapon_def` packets (`DAMAGE` only).
* A single modifier is applied at most once per slot (dedupe key `(modifier, unit|structure, slot)`).
* `RANGE` scales only the max range; `min_range` is unchanged and `range = max(range, min_range + 1)`.
* Units that carry per-mode weapon sets (`deploy`, `mode_switch`) receive the modifier on all sets.

#### 5.5.7 How each bible scope rule is honoured
| bible rule | mechanism | check |
|---|---|---|
| Combat modifiers exclude the 4 service units | combat selectors require tag `combat`; service units never have it | `V-MOD-10` lists every (modifier, service unit) match; the allowed set is exactly `{pd.indonesia.02→landing_transport, ae.01→collector/mcv/landing_transport}` (verified: these are the only 4 matches in all 32 rosters) |
| Transport bonuses include any unit tagged Transport | `selector.all_transports` = tag `transport` only | Indonesia +20 % health hits Kancil, Leviathan and the Landing Transport |
| Structure modifiers apply only to the named class | tags / explicit ids (`defense` → 11 structures, `non_superweapon` → 21, `structures` → 29) | golden |
| Replaced units keep role tags | tags(replacement) ⊇ tags(replaced) (48/48 hold; only `amphibious`, `detector`, `light` are ever added) | `V-ROS-06` |
| Temporary superweapon units get no unit modifiers | SUMMON defs have no `combat` tag + `UF_NO_COMBAT_MODS` | `V-ROLE-05` |
| Superweapon geometry/reach unaffected by unit range modifiers | RANGE/RELOAD never target superweapons | `V-MOD-01` |
| Nigeria's construction bonus does not change Horizon | `non_superweapon_structures`; recharge is a superweapon field | golden |
| Kazakhstan discounts the Refinery, not Collectors | explicit structure id; the free Collector's `cost` is a unit stat | golden |

### 5.6 Worked numeric examples (bases = current `global.json` role archetypes / `balance_calc.py resolve` output; every result recomputed by the reference implementation)

Cross-check: for ten unit/roster pairs (Guardian/NAPC, Narwhal & Beaver & Paladin/Canada, Raptor/USA, Imperial Guard Tank/China, Ural/Russia, Marte/Eurocorps, Firefly/Cambodia, Bulwark/Thailand) the layered products and the rounded results below are **identical** to `python3 tools/py/balance_calc.py resolve <unit> <roster> --styled` (the balance framework's independent implementation of the bible rule): same `bp` products (e.g. Narwhal health 12100), same half-up rounding, same reload ceil.

Notation: bases are the framework's *pre-modifier* numbers (the framework's `modifier_compensation` policy keeps passive modifiers out of base stats). `fold` = §5.5.3 static formula.

| # | case (real bible modifiers) | computation | result |
|---|---|---|---|
| 1 | NAPC vanilla **Guardian Tank** (`mbt_t1`): cost 850, health 907, build 27.5 s = 550 t — `napc.02` cost +10 %, `napc.01` health +10 % (parent) | 850·1.10; 907·1.10 = 997.7 | cost **935**, health **998**, build **550 t** |
| 2 | **Canada Narwhal** health 907, cost 810 — parent `napc.01` +10 % **and** sub `canada.01` +10 % (amphibious combat units): layers multiply | 907·1.10·1.10 = 1097.47; cost 810·1.10 = 891 | health **1097**, cost **891** |
| 3 | **Canada Beaver** (`veh_scout`) health 602, cost 485 | 602·1.21 = 728.42; 485·1.10 = 533.5 | health **728**, cost **534** (half-up) |
| 4 | **Canada Beaver on water** (`canada.03` +20 % *on water*, cond `ON_WATER`): speed 3.2 cps = 164 upt; amphibious `DEEP` table value 70 % | `water_mult_bp = fold(10000, 0, 2000) = 12000`; deep-water speed = `DefMoveTable.effective_speed(164, AMPHIBIOUS, DEEP, 0, 12000)` = half_up(164·7000·12000 / 10^8) = 137.76 | `speed` **164**, `water_mult_bp` **12000**, derived `speed_water` **138** (one rounding) |
| 5 | **Canada Paladin** (`arty_howitzer`) reload 3.5 s = 70 000 mt — `canada.04` reload +15 % (increases are uncapped) | 70 000·1.15 | **80 500 mt** (`reload_ticks` = ceil = **81**); floor 35 000 mt not reached |
| 6 | **USA Raptor** cost 1050, rearm 8 s = 160 t; **Guardian** build 550 t — `usa.01` aircraft cost −15 %, `usa.02` aircraft rearm −20 %, `usa.03` land-vehicle build time +15 % | 1050·0.85 = 892.5; 160·0.80; 550·1.15 = 632.5 | cost **893**, rearm **128 t** (6.4 s), build **633 t** |
| 7 | **Han China Imperial Guard Tank** health 1588 — parent `han.03` −10 %, sub `china.01` +15 % (the bible's own "1.10 × 0.90" pattern) | 1588·0.90·1.15 = 1643.58 | **1644** |
| 8 | **Russia Ural** cost 1425, speed 1.8 cps = 92 upt — parent `def.01` −10 %, sub `russia.02` +10 % cost; parent `def.03` −10 %, sub `russia.03` −10 % speed | 1425·0.9·1.1 = 1410.75; 92·0.81 = 74.52 | cost **1411**, speed **75** upt |
| 9 | **Generator** power 150 — OLM parent `olm.05` +25 %; Saudi sub `saudi_arabia.01` +20 % | OLM vanilla 187.5 → half-up; Saudi 150·1.25·1.20 | **188** / **225** |
| 10 | **Eurocorps Marte** cost 1400 — parent `nec.01` +5 % (all combat units), sub `eurocorps.02` +10 % (tanks) | 1400 · 1.05 · 1.10 | **1617** |
| 11 | **AE repair cost** (`ae.01` −25 %, cond `PAID_VEHICLE_REPAIR`, static fold): base 5000 bp; Buffalo paid price 850 | repair_cost_bp = 3750; full repair = rdiv(850·3750, 10000) | **319** credits (vs 425 in other factions) |
| 12 | **Cambodia Firefly** cost 940 — `cambodia.01` unmanned −15 % | 940·0.85 | **799** |
| 13 | **Floor (synthetic)**: Han Banner Infantry cost 250: parent −15 % ⇒ 212.5 → 213; hypothetical layer-3 −30 % | apply_bp(213, −3000) = 149; floor = ceil_div(250·6000, 10000) = 150 | **150** |
| 14 | **Add within layer 3**: damage 140 with Relay +10 %, Combined Arms Window +10 % (distinct sources, same layer) | 140·(1+0.10+0.10) = 168 (multiplicative would give 169) | **168** |
| 15 | **Layer 3 on a slowed weapon**: Thailand Bulwark reload 1.2 s = 24 000 mt, `thailand.04` +10 % ⇒ 26 400; power `assault_coordination` −15 % (layer 3) | apply_bp(26 400, −1500) = 22 440; floor 12 000 | **22 440 mt** |
| 16 | **Resistance cap**: Dust Screen 30 % + Steel Advance 20 % + Protected Advance 15 % = 65 % | min(6500, 5000); 100 · matrix 100 % · (1 − 0.50) | **50** |
| 17 | **Per-hit damage** (TAXONOMY pipeline, one rounding): Guardian cannon 141 `ap` (the styled proposal) vs `medium_armor` (100 %), Adaptive Plating (group `explosive`) 10 % | `final_damage(141, 10000, 100, 1000, 100, eco)` = 141 · 0.90 = 126.9 | **127** (min 1) |
| 18 | **HP rescale** (AE Circular Armor +10 % while a Buffalo (900 hp) stands at 600/900) | max 990; rdiv(600·990, 900) | **660/990** (ratio kept) |
| 19 | **Sight** (Nordics scouts/artillery +20 %): Surveyor APC 12 cells = 12288 u | 12288·1.20 | **14746 u** (14.4 cells) |
| 20 | **Garrison** (El Andalus `el_andalus.02` +20 % weapon damage, cond `IN_CIVILIAN_GARRISON`): Gate Guard `small_arms` 26 dmg ×2 hits | `cond_vals += {DAMAGE, 2, fold(26, 0, 2000) = 31}` | **31** per hit when garrisoned, 26 otherwise |

### 5.7 Roster resolution (`DefRosterBuilder`)

**Inputs.** `DefFaction`, roster source record (`kind`, `delta.{replacements, removed_without_replacement_unit_ids, unavailable_support_power_ids}`, `own_modifier_ids`, `exclusive_research_id`, `exclusive_support_power_id`, `resolved.unit_overrides`), the base defs and modifiers.

**Algorithm (per roster; `base_roster` contains every def, has no replacements, and skips steps 3, 4, 5 and 7).**
1. *Availability.* `units = []`; for each `u` in `faction.baseline_unit_ids` (bible order): skip if `u ∈ removed`; else append `replacement_of(u)` if `u` is replaced, else `u`. Append the 4 service units. Structures = `faction.structure_ids`. Then **spawnables**: every `SUMMON/DRONE` def whose `faction ∈ {this, shared}` and that is referenced (transitively) by an ability/power/zone/superweapon of this roster.
2. *Clone.* Each available def is deep-copied (`weapons`, `abilities`, `cond_vals`). Effective tags = base | `unit_overrides[unit].add_tags`. Bible override `water_speed_fraction_of_land_speed` (0.7 for PD Collectors) ⇒ `move_class = AMPHIBIOUS` (if it was WHEELED/TRACKED) and `deep_speed_bp = 7000` (= 70 % of land speed on `DEEP`; equals the amphibious class default, kept explicit because the bible states it). `unit_overrides` is the only field read from the derived `resolved` block; everything else is recomputed and compared (step 7).
3. *Modifiers* `faction.passive_modifier_ids` then `own_modifier_ids`: accumulate and fold (§5.5); conditional variants per §5.5.5; derived fields recomputed (`repair_cost_bp`, `max_range`, `attack_layer_mask`, …).
4. *Trait grants* (`DefFaction.grants`): each `GRANT_ABILITY` record adds its ability to the matching roster clones **unless the target already has that kind** (then `replace:true` overwrites params, else no-op + INFO). `player_params` are copied to `DefRoster.player_params`. Examples: NAPC Factory apron → `structure.shared.factory` gets `AURA_REGEN`; AE → `unit.shared.engineer` gets `SALVAGE`; SAP → player param `defense_reserve_t`.
5. *Lists.* `research_list = faction.shared_research + [exclusive]`, `power_list = faction.shared_powers + [exclusive or vanilla_only]` (subfactions **lose** the vanilla-only power via `unavailable_support_power_ids`), `superweapon`, `superweapon_def` = clone with `DAMAGE` modifiers matched through `additional_superweapon_ids`. `producible_units` ordered by `(tier, cost, index)`.
6. *Selector caches* are lazy (`selector_units`).
7. *Self-check against the bible's derived block* (any mismatch = `V-ROS-01` ERROR): `combat_unit_ids`, `service_unit_ids`, `structure_ids`, `research_ids`, `support_power_ids`, `superweapon_id`, `modifier_ids`, and the golden `modifier_applications` of §5.4.4; plus each unit's `requires_all_structure_ids == [producer] + tier_requirements[tier]`.

**Subfaction deltas (24 rosters; indices per §5.3)** — each subfaction: exactly 2 replacements, 1 removal, the vanilla-only power unavailable, 1 exclusive research, 1 third power:

| roster (idx) | replaces -> replacement | removed | exclusive research | third power |
|---|---|---|---|---|
| ae.kongo (0) | mamba_apc->okapi_amphibious_carrier; reclaimer->river_warden | sovereign_arsenal_ship | watershed_logistics | concealed_crossing |
| ae.nigeria (1) | union_guard->civic_rifle_team; weaver_aa->lagos_drone_guard | kiln_assault_crawler | municipal_reserves | civil_defense_net |
| ae.south_africa (2) | buffalo_tank->rhino_rail_tank; forge_howitzer->protea_gun_carrier | hammerhead_gunship | precision_machining | counterbattery_solution |
| def.kazakhstan (4) | mule_apc->steppe_recon_carrier; anvil_rocket_battery->saker_missile_truck | colossus_siege_tank | mobile_dispatch | transit_priority |
| def.north_korea (5) | line_conscript->fortress_guard; signal_officer->echo_team | boreal_missile_submarine | buried_command_lines | false_front |
| def.russia (6) | hammer_tank->ural_assault_tank; colossus_siege_tank->bear_siege_crawler | burya_bomber | layered_protection | steel_advance |
| han.cambodia (8) | jade_carrier->lotus_drone_tender; link_operator->mekong_field_engineer | emperor_drone_ship | modular_servicing | repair_swarm |
| han.china (9) | ox_tank->imperial_guard_tank; dragon_command_walker->long_command_walker | silkwing_drone_bomber | guard_integration | central_priority |
| han.vietnam (11) | banner_infantry->canopy_ranger; nest_rocket_drone->reed_rocket_skimmer | dragon_command_walker | hidden_relays | broken_contact |
| napc.canada (12) | pathfinder_apc->beaver_amphibious_apc; guardian_tank->narwhal_amphibious_tank | titan_gunship | sealed_compartments | floating_workshop |
| napc.mexico (13) | rifle_squad->vanguard_rifle_squad; combat_medic->aguila_breach_team | liberty_arsenal_ship | section_logistics | coordinated_advance |
| napc.usa (14) | falcon_interceptor->raptor_multirole_fighter; titan_gunship->condor_stealth_bomber | bastion_heavy_tank | dispersed_runways | rapid_turnaround |
| nec.alpine_brotherhood (16) | sapper->alpine_pioneer; archer_spg->ibex_crawler_gun | concord_monitor | tunnel_workshops | emergency_earthworks |
| nec.eurocorps (17) | leopard_tank->marte_heavy_mbt; argent_rail_tank->charlemagne_siege_tank | aster_ew_aircraft | shared_fire_solutions | armored_overwatch |
| nec.nordics (18) | surveyor_apc->fen_recon_carrier; archer_spg->fjord_missile_carrier | argent_rail_tank | dispersed_links | silent_watch |
| olm.algeria (20) | caravan_apc->dune_rover; sandglass_mortar->scorpion_rocket_buggy | sunlance_beam_tank | distributed_fuel_caches | false_convoy |
| olm.el_andalus (21) | wayfarer_guard->gate_guard; lantern_escort->strait_frigate | sunlance_beam_tank | harbor_militia | straits_crossfire |
| olm.saudi_arabia (22) | crescent_aa->dawn_laser_aa; sunlance_beam_tank->ifrit_prism_tank | beacon_missile_ship | thermal_reservoirs | capacitor_discharge |
| pd.australia (24) | breaker_howitzer->outrider_howitzer; petrel_fighter->wedge_recon_fighter | leviathan_assault_carrier | forward_fire_control | long_watch |
| pd.indonesia (25) | wake_skimmer->kancil_landing_skimmer; ranger_marine->island_raider | tempest_carrier | distributed_beachheads | feint_landing |
| pd.japan (26) | tide_tank->shinano_adaptive_tank; tempest_carrier->shogun_drone_carrier | breaker_howitzer | predictive_maintenance | precision_window |
| sap.india (28) | bulwark_tank->arjun_assault_tank; elephant_siege_tank->gaj_siege_platform | sarus_gunship | integrated_protection | assault_coordination |
| sap.pakistan (29) | monsoon_howitzer->shaheen_missile_battery; combat_pioneer->watchpost_recon_team | citadel_monitor | observer_network | counterlaunch_plot |
| sap.thailand (30) | jackal_apc->naga_amphibious_carrier; shield_rifle_squad->river_marine | elephant_siege_tank | rapid_ferry_drills | mobile_reserve |

**Invariants validated (all ERROR unless noted).** `V-ROS-02` every replaced/removed/replacement id exists and belongs to the roster's faction; replaced ∈ baseline; `replacement.replaces == replaced` and `replacement.introduced_by == roster`; `V-ROS-03` exactly 2 replacements + 1 removal per subfaction, none for vanilla, replaced ∩ removed = ∅; a replaced unit is **not** buildable (absent from the roster); `V-ROS-04` `unavailable_support_power_ids == [faction.vanilla_only_power]`; `V-ROS-05` every roster unit's producer and prerequisite structures are in the roster's structure set; `V-ROS-06` tags(replacement) ⊇ tags(replaced) (the 9 replacements that add tags add only `amphibious`, `detector` or `light`); `V-ROS-07` a replacement keeps *its own* tier/producer (7 replacement tanks move T1→T2 and require Radar — data, not inherited); `V-ROS-08` (WARN) a replacement does not silently reuse an ability template that is "special" on the replaced unit unless listed in `keeps_abilities` (prototype priority: never inherit both abilities).

### 5.8 Runtime layer 3 — research and temporary effects (`DefLayer3`, `DefStatMath`)

**5.8.1 Research (permanent).** `DefLayer3.apply_research(r)` visits `DefResearch.effects` in file order:
* `STAT_MOD` **without runtime conditions** → for every roster def matched by the effect's selector (`roster.selector_units/structures`, replacements closure applied), `unit_stat_bp[stat][def] += delta_bp` (or `struct_stat_bp`). `stack_group` dedupe: an existing entry of the same group is replaced only by a larger |delta| (`DefStatMath.stack_pick`).
* `RESIST_MOD` (unconditional) → `unit_resist_bp[dtype][def] += delta_bp` for every damage type whose `group_mask & effect.group_mask ≠ 0` (`group_mask == 0` ⇒ every weapon group except EMP). Fire-mode / frontal-arc / target-state filters (`fire_mode_mask`, `frontal_arc_a`, `Cond` codes) make the effect *conditional* (kept in `cond_effects`).
* any effect with `cond_codes` (≠ ∅) → appended to `cond_effects_of_unit(def)` for each matched def; the abilities domain evaluates the conditions per entity and adds the delta to its temporary `extra_bp` (this is how "+10 % after 6 s out of combat" and "inside a powered Relay field" stay outside the static sums).
* `PARAM_MOD` → recorded as `(scope, target defs or player, ability_kind, key, op, value)`; read through `ability_param/def_param/player_param`, which apply **all SET first (last wins, in research completion order), then ADD, then MUL_BP** (`MUL_BP` stores a *factor*: file `mul_pct: 125` ⇒ 12500 ⇒ `value = half_up(value · factor_bp / 10000)`; several factors multiply in completion order); `filter` (e.g. "only when repairing defensive structures") is exposed to the ability via `DefEffect.filter`.
* `GRANT_ABILITY` → appended to `granted_abilities(def)` (skipped if the def already has the kind; `replace:true` overrides params); `SET_FLAG` → `has_flag`.
* `version += 1`. Consumers that cache derived values (speed, max HP) key them by `layer3.version`.

**5.8.2 Effective stats.** `effective = clamp(apply_bp(resolved, research_bp + extra_bp))` (§5.5.3) where `extra_bp` = Σ **distinct-stack-group** temporary deltas of the entity (Relay field, command field, powers, zones — abilities domain). Research and temporary deltas are the **same layer** and therefore **add** ("+10 % research" and "+15 % Relay" = +25 %, not ×1.265). Effects sharing a `stack_group` count once per entity: the one with the largest |delta| wins, ties keep the earlier source; e.g. two overlapping Relays = one +10 %, and Treaty Coordination raises the group's value to +15 % instead of adding a second +10 %.

**5.8.3 Resistance and the damage pipeline.** `resist_total_bp = min(5000, Σ over distinct stack groups of (research resist for the hit's damage type + temporary resist matching the hit's damage group, fire mode, arc and target state))`. Sources of different names **add** (TAXONOMY §5: Adaptive Plating 10 + Steel Advance 20 + Protected Advance 15 = 45), identical sources never stack, the total is clipped at 50 %; only a successful interception bypasses the cap. The whole per-hit computation is **one** half-up rounding (TAXONOMY `damage_rounding: single_step_half_up_min_1`, identical to `balance_calc.final_damage`):
`final = max(1, half_up( raw · bonus_bp/10000 · matrix_pct/100 · (10000 − resist_bp)/10000 · falloff_pct/100 ))` — implemented once as `DefStatMath.final_damage(raw, bonus_bp, matrix_pct, resist_bp, falloff_pct, eco)` (`resist_bp` is clamped to `[0, resist_cap_bp]` inside the function — `resist_total_bp` exists for callers that need the capped number itself; returns 0 if any of raw/bonus/matrix/falloff is ≤ 0, e.g. rail vs aircraft; EMP results are clamped by combat so hp ≥ 1). `bonus_bp` = `10000 + Σ layer-3 damage deltas` (the static bible layers are already folded into `slot.damage`).

**5.8.4 Max-HP changes.** When `effective HEALTH` changes (research completion or an aura), the sim keeps the ratio: `hp = DefStatMath.rescale_hp(hp, old_max, new_max)` (never below 1). Losing a bonus never kills.

**5.8.5 Rates.** `PROD_RATE`/`REARM_RATE` are additive bp on a nominal 10000: `rate_bp = 10000 · shortage_factor` then `+ Σ`, e.g. Mobilization Order (+25 %) = 12500; power shortage multiplies the base by `power_shortage_rate_bp / 10000` (5000). Progress accumulates in the production system as `progress += rate_bp` per tick until `progress ≥ build_ticks · 10000` (ASSUMPTION(sim)). Build-time *modifiers* (layers 1-2) already changed `build_ticks`; rates are separate, so "−20 % build time" and "+25 % faster" are never conflated.

### 5.9 Conditions and unresolved domains — the complete lists

#### 5.9.1 Every distinct condition string in the bible (`conditions[]` occurrences: selectors 3, roster modifier_applications 6, structures 10) and its code
| # | exact bible string | occurs in | code | how honoured |
|---|---|---|---|---|
| 1 | `The vehicle is on water.` | `selector.amphibious_vehicles_on_water`; `roster.napc.canada` application of `modifier.napc.canada.03` | `Cond.ON_WATER = 1` | static: adds to `water_mult_bp` only (§5.5.5); no runtime evaluation |
| 2 | `The infantry unit occupies a marked civilian garrison.` | `selector.garrisoned_combat_infantry`; `roster.olm.el_andalus` application of `modifier.olm.el_andalus.02` | `Cond.IN_CIVILIAN_GARRISON = 2` | runtime: entity flag `in_garrison` set by the garrison system; weapon slots carry `cond_vals[{DAMAGE,2,v}]` |
| 3 | `The target is receiving paid land-vehicle repairs.` | `selector.land_vehicle_repairs`; 4 AE rosters' application of `modifier.ae.01` | `Cond.PAID_VEHICLE_REPAIR = 3` | static fold into `repair_cost_bp` (stat only read by credit-charging repair) |
| 4 | `Maximum one strategic structure per player.` | 8 superweapon structures | `PlaceFlag.PLACE_MAX_ONE_STRATEGIC = 2` and `max_per_player = 1` | CommandSystem placement validation (§6) |
| 5 | `Normal construction radius; does not extend it.` | `structure.nec.relay` | `PlaceFlag.PLACE_NO_RADIUS_EXTENSION = 4` | placement must lie inside an HQ `build_radius`; a Relay is never a build-radius source |
| 6 | `Valid shoreline placement.` | `structure.shared.dock` | `PlaceFlag.PLACE_SHORELINE = 1` | placement requires ≥ 1 adjacent water cell reachable by ships (map domain predicate) |

An unknown condition string is `V-MOD-04` (ERROR): a new bible condition can never be silently ignored.

#### 5.9.2 `unresolved_target_domain` strings (3 distinct; each on 1 selector; each resolved and documented)
The balance framework's weapon archetypes (TAXONOMY §10) make two of the three domains directly expressible: **weapon/projectile attributes are archetype attributes**, from which `DefWeaponArch.tags` are derived at load (`thermal_beam` ⇔ `dtype == THERMAL`; `guided_missile` ⇔ `interceptable == APS_TRIDENT`; also `direct_fire`, `indirect_fire`, `anti_air`, `anti_ground`, `anti_sub`). Weapon-kind and projectile-kind selectors match a slot through `slot.arch`.

| id | exact bible string | selector | resolution (decision) |
|---|---|---|---|
| **U1** | `Carrier-launched drones are also unmanned, but their pricing/replacement costs are unspecified.` | `selector.unmanned_combat_units` (Cambodia `cost −15 %`) | Carrier-launched drones are `DefUnit`s of class `DRONE` tagged `combat unmanned` (+`aircraft`). Their `cost` is the **replacement cost** and `build_ticks` the replacement time (framework: `carriers.drone_replace_cost_credits` 120, `drone_replace_s` 14 — balance-defined, since the bible leaves them unspecified). They are in a roster iff their carrier is; the selector matches them by tags, so Cambodia's −15 % applies to the replacement cost and `research.pd.integrated_flight_decks`/`predictive_maintenance` scale `carrier.replace_s`. *Power/superweapon summons (`SUMMON`) never carry `combat`* and stay outside every combat selector (bible: Tempest drones and Dragonfall engines are "temporary superweapon units"; Japan's note). |
| **U2** | `Thermal-beam weapons and defenses; exact weapon registry is not yet specified.` | `selector.thermal_beam_weapons` (Saudi `weapon_damage +15 %`, + Helios via `additional_superweapon_ids`) | **A slot is a "thermal-beam weapon" iff its archetype has `dtype == THERMAL`** — in the framework exactly `beam_thermal` (Sunlance, Ifrit, Sunwall, Dawn laser AA). The +15 % applies to `slot.damage` of every such slot of every unit/structure of the roster and to Helios' packet(s); unit-only cooling upgrades (`reload`) do not touch Helios (bible superweapon_note). |
| **U3** | `Ordinary guided-missile projectile templates; exact weapon registry is not yet specified.` | `selector.ordinary_guided_missiles` (Pakistan `projectile_flight_speed +20 %`) | **A projectile is an "ordinary guided missile" iff its archetype has `interceptable == APS_TRIDENT`** (`at_missile`, `aa_missile`, `missile_artillery`, `air_missile`, `cruise_missile`, `drone_missile` — the same set Ural/Arjun APS may intercept, "one incoming ordinary missile"). The +20 % applies to `slot.proj_speed` of those slots. Superweapon packets are not projectiles of any archetype and are excluded (bible `exclude_tags: [superweapon]`); shells/rockets (`TRIDENT`) are Trident-interceptable but not "guided missiles". |

`V-MOD-13` requires that every resolved selector of an *owned* modifier matches ≥ 1 entity in at least one roster that owns it (e.g. Saudi must have ≥ 1 `beam_thermal` slot; Pakistan ≥ 1 `APS_TRIDENT` slot), so an unresolved domain can never become a dead modifier by accident.

### 5.10 Parameter blobs, abilities, effects, powers (the extension mechanism)

**5.10.1 Suffix-driven conversion.** In any `params`-like object, every numeric value's key must end in a unit suffix; `DefConvert.convert_params` converts by suffix and **renames** the key to its runtime suffix so unit confusion is impossible in code (`deploy_s: 3` ⇒ `deploy_t: 60`).

| file suffix | runtime suffix | value | | file suffix | runtime suffix | value |
|---|---|---|---|---|---|---|
| `_cells` | `_u` | int | | `_pct` | `_bp` | int |
| `_cells_s` | `_upt` | int | | `_deg` | `_a` | int |
| `_s` | `_t` | int (ticks, ceil) | | `_deg_s` | `_apt` | int |
| `_smt` | `_mt` | int (exact) | | `_credits` | `_cr` | int |
| `_n` | `_n` | int | | `_hp` | `_hp` | int |
| `_x` | `_x` | int (dimensionless) | | `_bp` (already bp) | `_bp` | int |
| `_crps` (credits/second) | `_mcpt` (milli-credits/tick) | int `rdiv(x, TPS)` | | `_pcts` (percent/second) | `_bps` (bp/second) | int |
| `_x100` | `_x100` | int passthrough (already hundredths) | | | | |

Other value types: `bool` → `bool`; `String` → `String` (charset `[a-z0-9_.:#-]`); `*_id` → `*_idx` (int; the id's kind is chosen by the key prefix `unit_ summon_ structure_ weapon_ projectile_ zone_ research_ power_ ability_ faction_ roster_ neutral_`); `*_ids` → `*_idx` `PackedInt32Array` (**ascending**, or in file order if the key ends `_seq_ids`); `*_tags` → `*_mask` (namespace by key prefix `unit_ structure_ weapon_ projectile_`); `*_types` (damage type names) → `*_mask` (bit per `DamageType`); `*_groups` (resist group names) → `*_mask` (`ResistGroup` bits); nested objects/arrays recurse (an array key's suffix applies to every element). A numeric key without a known suffix is `V-SCH-07`. Output keys are inserted in sorted order.

**5.10.2 Ability kinds and templates.** `ability_kinds.json` (§7.4) has (a) `kinds`: for every `AbilityKind` a param spec (`type`, `req`, `def`, `min`, `max`, `doc`) plus allowed scopes; (b) `templates`: named, parameterised instances (`ability.deploy.default`); (c) `aliases`: the balance framework's bare ability names → template ids; (d) `implicit`: templates every unit gets from a bible tag, an archetype family or an archetype. A unit/structure lists abilities as bare framework names or `ability.*` template ids, with per-entry `ability_params` overrides. The loader validates against the spec, **fills every default into the converted `params`** (runtime code never carries defaults), and stores at most one ability per kind per def (`ability_slot_of_kind`; a later entry of the same kind replaces an earlier/implicit one).

**5.10.3 Effects.** The same `DefEffect` record encodes research, faction traits, zone effects, power global effects and superweapon secondary effects. Op-specific fields are in §7.5; the runtime meaning of each op belongs to the abilities/combat domains, the *data* meaning (which fields, what units, what layer) is fixed here.

**5.10.4 Prose-number cross-check (`V-CNF-06`).** Every research/power/superweapon/trait entry carries `bible_numbers: [...]`. The validator extracts every number from the bible `effect_text` (regex `(?<![A-Za-z0-9_.])\d+(?:\.\d+)?(?![A-Za-z0-9_])`; number words `one…twelve` are extracted as numbers too) and checks (a) each prose number appears among the entry's leaf param values **in file units** (cells/seconds/percent/counts — the same units the prose uses, so equality is exact) or in `bible_numbers`, and (b) `bible_numbers ⊆` prose numbers (no invented numbers). Numbers the author deliberately did not encode (e.g. "from 12 to 9 seconds" where 12 already sits in a unit ability) are acknowledged by listing them in `bible_numbers`. Designer-chosen values that the prose leaves open (e.g. the radius of "near a powered Barracks") are listed in `designer_params: ["radius_cells"]` so reviewers see them. WARN by default, ERROR with `--strict`.

### 5.11 Data hash, per-file hashes and the lobby handshake

**Primitives (`DefHash`).** 32-bit FNV-1a: `mix_byte(h,b) = ((h ^ b) * 16777619) & 0xFFFFFFFF`, `OFFSET = 2166136261`. `mix_int(h, v)`: `z = (|v| << 1) | (v<0)`, then LEB128 (7 bits per byte, low first, `0x80` = more) — **no negative shifts anywhere**; requires |v| < 2^62. `mix_str`: UTF-8 bytes then `0xFF`. `mix_variant` prefixes a type byte (`nil 0, true 1, false 2, int 3, string 5, Array 6 + size, Dictionary 7 + size + (key, value) in sorted-key order, PackedInt32Array 9 + size`). A `float` is a bug (V-DET-01): `mix_variant` mixes only its type byte (`4`, no arithmetic — the file stays lint-clean) and increments `DefHash.float_hits`, which `DefValidator` requires to be 0.

**Reflection hash of a Def.** `hash_def(h, d)`: (1) once per script, mix the ordered list of *hashed* property names from `get_property_list()` (usage `PROPERTY_USAGE_SCRIPT_VARIABLE`, skipping names starting `_`, `ui_`, `pres_`) — derived-class properties come before base-class ones on Godot 4.7.2; the order is a pure function of the script, hence identical everywhere and any field rename/add changes the hash; (2) mix each property value with `mix_variant`, owned child defs recursively via `hash_def`.

**Tables and the data hash.**
```
table_hash(T) = fold over defs of T in index order:  h = hash_def(h, def)            (h0 = OFFSET)
table_hashes  = { "ids", "global", "weapon_archs", "abilities", "units", "structures", "research",
                  "powers", "superweapons", "zones", "neutrals", "factions", "selectors", "modifiers", "rosters",
                  + one key per registered DefDomainCompiler (its table_hashes()) }
   "ids"     : for kind in Kind order: mix_str(kind_name); for id in sorted ids of that kind: mix_str(id)
   "global"  : economy (all fields), damage table (ids, group masks, matrix, cap), move table (terrain speeds, layers), body table, tags registries (names in bit order)
   "rosters" : per roster in index order: id, kind, lists, player_params, every non-null resolved unit/structure clone (index + hash_def), superweapon_def
data_hash = OFFSET; mix_int(FORMAT_VERSION); for key in the fixed order above (core keys first, then compiler keys sorted): mix_str(key); mix_int(table_hashes[key])
```
The handshake carries these 15 core table hashes plus one per registered compiler (the net spec's "16 tables" is descriptive, not a constant). Including the **resolved rosters** in the hash means two peers running different resolver code (or different `DefStatMath` rounding) are rejected at the lobby even if their JSON is identical.

**Per-file hashes** (diagnosis only; computed lazily by `GameData.file_hashes()`): `DefHash.hash_json(parsed_file)` for the bible and every manifest file, keyed by path relative to `res://data/` (e.g. `bible/meridian_factions.json`, `balance/units_napc.json`). Canonicalisation: numbers → `DefNumParse.milli` (exact `x·1000`), dictionary keys sorted, strings UTF-8 ⇒ independent of whitespace, CRLF/LF and key order. Raw-byte hashes are deliberately **not** used (Windows checkouts may convert line endings).

**Handshake.** `handshake()` → `{"format": FORMAT_VERSION, "hash": data_hash, "tables": table_hashes[, "files": file_hashes()]}`. Protocol (net domain carries it): client sends `{format, hash, tables}` in its lobby join; host compares `hash`; on mismatch the client is refused with `diff_handshake(host, client)` = sorted lines `format: 1 vs 2`, `table units differs`, and — when both sides include `files` (the client is asked to resend with `include_files=true` after a mismatch) — `file balance/units_napc.json differs`, `file balance/x.json missing on remote`. Replays store `format`, `hash` and `tables["ids"]`; playback with equal `ids` but different `hash` warns "balance changed since recording; may desync". `SimWorld.checksum()` mixes `data_hash` into its seed so every desync dump names the data version.

### 5.12 Validation — the exact rule list

`S` = severity (E error blocks load/CI, W warning, I info). `Where`: **PY** = `tools/py/validate_balance.py` (source level), **ENG** = `DefValidator` (level: F = FAST+FULL, U = FULL only). Rule ids are shared so reports correlate.

| Rule | S | Check | Where |
|---|---|---|---|
| **V-SCH-01** | E | Every manifest file exists, is valid JSON, top-level object, `schema` key == expected (`meridian.balance.<name>/1`; `global.json` instead carries `version == 1`); manifest lists exactly the expected file set (no missing/extra) | PY, ENG-F |
| V-SCH-02 | E | Unknown keys (typo protection) outside `params`/`extra`; **duplicate keys in a JSON object** | PY (dup), PY+ENG-U (unknown) |
| V-SCH-03 | E | Ids match `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$`, kind prefix correct, no duplicate id per kind across files | PY, ENG-F |
| V-SCH-04 | E | Numeric literal with > 3 decimals, NaN/inf, or \|x\| ≥ 2^40 | PY, ENG-F |
| V-SCH-05 | E | Integer-typed field (credits, hp, counts, tier, pads…) not integral | PY, ENG-F |
| V-SCH-06 | E | `_pct` value with > 2 decimals; delta ≤ −100 % | PY, ENG-F |
| V-SCH-07 | E | Numeric param key without a recognised unit suffix | PY, ENG-F |
| V-SCH-08 | E | > 62 tags in a namespace; tag name not `[a-z][a-z0-9_]*` | PY, ENG-F |
| V-SCH-09 | W | Entries inside a file not sorted by id (diff-stability lint) | PY |
| **V-REF-01** | E | Every referenced id exists in the right table (units, structures, weapons, projectiles, zones, summons, abilities, research, powers, neutrals, factions, rosters, selectors, stack groups) | PY, ENG-F |
| V-REF-02 | E/W | Kind mismatch (`summon_id` → non-summon; `drone_id` → non-DRONE) = E; `pres_recipe`/`pres_icon`/`pres_snd_profile` id absent from `game/data/recipes` / `game/data/audio/events.json` = E if the registry exists else W | PY |
| V-REF-03 | W | Orphans: ability template, zone, summon, role archetype not referenced | PY, ENG-U |
| V-REF-04 | E | `role`/`archetype`, `weapons[].archetype`, `armor_class`, `size_class`, `movement_class`, `layer`, `damage_type`, terrain and ability alias names exist in `global.json`/registries | PY, ENG-F |
| **V-CMP-01** | E | Every one of the 156 bible units has exactly one entry in the file matching its faction (`units_<code>` / `units_shared`); none for unknown ids | PY, ENG-F |
| V-CMP-02 | E | 29 structures ↔ `structures.json` | PY, ENG-F |
| V-CMP-03 | E | 40 research ↔ `research_effects.json`, 48 powers ↔ `power_actions.json`, 8 superweapons ↔ `global.json → superweapons` (each of the 8 keys present and mapped, §7.11), 8 factions ↔ `faction_traits.json`; every entry has ≥ 1 effect/action (or the owning domain's equivalent files when a plug-in replaces the fallback) | PY, ENG-F |
| V-CMP-04 | E | Required sheet fields present where the bible value is null or the field is not bible-specified: unit `cost_credits` + `build_time_s` (unless SUMMON), `health`, `armor_class`, `movement_class`, `size_class` (or `radius_cells`), `speed_cells_s` (unless `static`), `vision_cells`, and per weapon `archetype damage reload_s range_cells`; structures take their numbers from `global.json → structures/defenses/superweapons.common` (`health armor_class footprint vision_cells cost build_time_s power_delta`) — a bible structure without a mapped key, or a null bible build time without a `global.json` value (the Relay), ⇒ E; anything missing after role-archetype defaults ⇒ E | PY, ENG-F |
| V-CMP-05 | E | Armed/unarmed: units whose bible text says "Unarmed"/"No weapon" (Engineer, Combat Medic, Mirage Observer, Link Operator, Mekong Field Engineer, Reef Technician, Aster EW Aircraft, Collector, MCV, Landing Transport) have no weapons; every other combat unit has ≥ 1 | PY, ENG-U |
| **V-CNF-01** | E | Balance value ≠ non-null bible value (report both) | PY, ENG-F |
| V-CNF-02 | I | Balance repeats an equal bible value (W with `--strict-redundant`) | PY |
| V-CNF-03 | E | `tags_add` contains a locked tag (15 selector tags) or a bible tag of another meaning | PY, ENG-F |
| V-CNF-04 | E | Balance sets a bible-only field (tier, prerequisites, research/power cost/cooldown/tier, superweapon recharge/warning/charges, faction membership) | PY |
| V-CNF-05 | E | `global.json` (a) carries **exactly the frozen vocabulary** of `DefEnums`/TAXONOMY — damage types (7, indices, groups, `nonlethal`), resist groups, armor classes (11), layers, fire modes, size classes, terrain kinds (8), movement classes (9, indices), weapon archetypes (27, indices) — and (b) its ★ constants equal the bible (`mechanical_conventions`, HQ radius, structure costs/build times/power, service-unit costs, superweapon recharge/warning) | PY, ENG-F |
| V-CNF-06 | W/E | Prose-number cross-check (§5.10.4) | PY |
| V-CNF-07 | W | The bible mirror is stale: sha-256 of `game/data/bible/meridian_factions.json` ≠ its `game/data/bible/manifest.json` entry, or ≠ `Input/meridian_agent_reference/meridian_factions.json` (`tools/py/sync_bible.py --check`) | PY |
| V-CNF-08 | E | A weapon instance overrides an **archetype-locked** field (`damage_type`, `fire_mode`, projectile kind, `interceptable_by`) or sets `targets_override` outside the layer set; only numbers (and `suppressive`, `targets_override` ⊆ layers) may vary | PY, ENG-F |
| V-CNF-09 | W (E with `--strict`) | **Two sources set the same field with different values** and the precedence of §7.0 picks one: e.g. `economy.json` vs `global.json → economy` (Collector capacity 500 vs 600, deposit sizes, regrowth), `structures.json` vs `global.json → structures`, `abilities.json → slots` vs a sheet's `abilities`, `global.json → economy.collector.capacity_credits` vs `service_units.collector.capacity_credits` (today 600 vs 500 inside one file). The report lists both values and the winner; a CI gate runs with `--strict` | PY, ENG-U |
| **V-RNG-01** | E | Values inside the ranges of `DefValidator.RANGES` / `balance_lib/ranges.py` (one table, both sides; cost 50-6000; build 2-120 s; hp 20-100 000 (also the cap for any layered base value); speed 0.3-14 cps; sight 2-20 cells; radius 0.2-2.5 cells; damage 1-100 000; range 0.5-60 cells; reload 0.05-60 s; footprint 1-8 cells) | PY, ENG-U |
| V-RNG-02 | W | Tier-curve outliers: cost, hp, DPS, DPS/cost outside `tier_curves[tier][role]` bands | PY |
| V-RNG-03 | E | A non-zero converted speed < 1 upt, range < 1 u, duration < 1 t, reload_mt < 1 | PY, ENG-F |
| V-RNG-04 | E | Damage matrix complete (7 damage types × 11 armor classes), integer percent 0-300, `emp` row present (`emp` vs infantry 0 allowed; `rail`/`kinetic` vs aircraft 0 allowed) | PY, ENG-F |
| V-RNG-05 | E | Movement table complete (9 `MoveClass` × 8 `TerrainKind`, 0-200 %); `static` all 0; `air_*` all > 0; `naval` 0 on every non-water kind; `foot/wheeled/tracked` 0 on `DEEP` and `CLIFF`; `amphibious` `DEEP` > 0; each class' layer valid | PY, ENG-F |
| **V-TIER-01** | E | `requires == [producer] + tier_requirements[tier]` (units); research/power `requires == tier_requirements[tier]` | PY, ENG-F |
| V-TIER-02 | E | Structure prerequisite graph acyclic; HQ has no prerequisites; MCV deployment is *not* an edge | PY, ENG-F |
| V-TIER-03 | E | **Land-only playability**: the transitive prerequisite closure of every non-naval unit, structure, research and power contains no `structure.shared.dock` (rule.design.technology) | PY, ENG-U |
| V-TIER-04 | W | Per roster: ≥ 1 T1 anti-infantry-capable unit, ≥ 1 T1/T2 anti-armor unit, ≥ 1 detector, ≥ 1 anti-air, ≥ 1 artillery/siege — all reachable without Dock; a roster that moves its tank T1→T2 still has a T1 anti-armor answer | PY, ENG-U |
| V-TIER-05 | W | Within a faction and role tag, cost and build time are non-decreasing with tier | PY |
| **V-ROLE-01** | E | Tag ⇒ capability: `anti_air` ⇒ a weapon with `L_AIR`; `anti_submarine` ⇒ `L_UNDER`; `artillery` ⇒ a weapon with `fire_mode == INDIRECT`; `anti_tank`/`ground_attack` ⇒ a weapon hitting `L_GROUND` | PY, ENG-U |
| V-ROLE-02 | E | `detector`⇒DETECTOR, `transport`⇒TRANSPORT, `carrier`⇒CARRIER, `command`⇒COMMAND_FIELD, `collector`⇒HARVEST, `construction`⇒DEPLOY_STRUCTURE, `capture`⇒CAPTURE, `repair`⇒REPAIR, `electronic_warfare`⇒EW_JAMMER, `submarine`⇒SUBMERGE | PY, ENG-U |
| V-ROLE-03 | E | Movement: `infantry`⇒FOOT; `ship`⇒NAVAL; `submarine`⇒SUBMERGED; `aircraft`⇒AIR_*; `amphibious`⇒AMPHIBIOUS; `land_vehicle`⇒WHEELED/TRACKED/AMPHIBIOUS; `ground`⇒`L_GROUND ∈ layer_mask` | PY, ENG-U |
| V-ROLE-04 | E | `unmanned` set == the 6 bible units + DRONE class (README role-tag rule) | PY, ENG-U |
| V-ROLE-05 | E | SUMMON defs have neither `combat` nor `service`; DRONE have `combat`+`unmanned`; SERVICE have `service` and not `combat` | PY, ENG-F |
| **V-MOD-01** | E | Stat applicable to the selector's entity kind (table §4.1); `RANGE/RELOAD` never target superweapons | ENG-F |
| V-MOD-02 | E | Selector tag unknown/unmatchable (§5.4.1) | ENG-F |
| V-MOD-03 | E | Modifier `layer` ↔ owner prefix; layer ∈ {1,2} | ENG-F |
| V-MOD-04 | E | Unknown condition string, or > 1 condition on a selector | ENG-F |
| V-MOD-05 | E | `unresolved_target_domain` string not one of the three known ones (§5.9.2) | ENG-F |
| V-MOD-06 | I | No-op application (base 0 / N/A); the real bible must report exactly the 2 no-ops of §5.5.4 (test-pinned) | ENG-U |
| V-MOD-07 | E | Unsupported (cond, stat) combination (§5.5.5) | ENG-F |
| V-MOD-08 | E | > 1 distinct condition on one (target, stat) | ENG-F |
| V-MOD-09 | E | Duplicate `(owner, stat, selector)` in one roster (same-source stacking) | ENG-F |
| V-MOD-10 | E | Service-unit scope: (modifier, service unit) matches ⊆ allowed set | ENG-U |
| V-MOD-11 | E | Static factor ≤ 0 (`10000 + S ≤ 0`) or folded result outside V-RNG-01 | ENG-F |
| **V-MOD-12** | E | **Golden**: resolved selector matches == bible `modifier_applications` for all 32 rosters | ENG-U, PY |
| V-MOD-13 | E | Every owned selector matches ≥ 1 entity in ≥ 1 owning roster (dead-modifier check, incl. unresolved domains) | ENG-U |
| **V-ROS-01** | E | Recomputed roster availability/lists/modifier ids == bible `resolved` block | ENG-F |
| V-ROS-02 | E | Replaced/removed/replacement ids exist, belong to the faction; `replacement.replaces == replaced`; `introduced_by == roster` | ENG-F |
| V-ROS-03 | E | Subfaction: exactly 2 replacements + 1 removal, replaced ∩ removed = ∅; vanilla: none; a replaced unit is absent from the roster | ENG-F |
| V-ROS-04 | E | `unavailable_support_power_ids == [faction.vanilla_only_power]` (subfaction) / `[]` (vanilla) | ENG-F |
| V-ROS-05 | E | Every roster unit's producer + prerequisites ∈ roster structures; research/power prerequisites too | ENG-F |
| V-ROS-06 | E | tags(replacement) ⊇ tags(replaced) | ENG-F, PY |
| V-ROS-07 | I | Replacement tier/producer differ from the replaced unit (reported: 7 tanks T1→T2) | ENG-U |
| V-ROS-08 | W | A replacement reuses an ability template that is special on the replaced unit without `keeps_abilities` | PY, ENG-U |
| **V-EFF-01** | E | Effect `op` known; required fields per op present with right types (§7.5) | PY, ENG-F |
| V-EFF-02 | E | Dead effect: selector matches nothing in *every* roster owning the research/trait (unless `may_be_empty_in` lists it) | ENG-U |
| V-EFF-03 | E | Any effect with a radius or area condition has a `stack_group` | PY, ENG-F |
| V-EFF-04 | E/W | Temporary effect needs `duration_s > 0` (E); power `cooldown ≥ max duration` (W) | PY |
| V-EFF-05 | E | zone/summon/ability references exist and have the right class | PY, ENG-F |
| V-EFF-06 | E | `PARAM_MOD` key exists in the target kind's spec and ≥ 1 matched def has that ability | ENG-U |
| V-EFF-07 | W | `GRANT_ABILITY` target already has the kind (no-op) | ENG-U |
| V-EFF-08 | E | Superweapon compile (§7.11) consistent with the numbers in the bible prose (packet counts, radii, timings, charges) — the prose check of §5.10.4 applied to `global.json → superweapons` | PY |
| **V-ABL-01** | E | Ability kind known; required params present; unknown params rejected; ranges | PY, ENG-F |
| V-ABL-02 | E | ≤ 1 ability per kind per def | PY, ENG-F |
| V-ABL-03 | E | `deploy`/`mode_switch` weapon-slot indices valid; `mode_mask` consistent | PY, ENG-F |
| V-ABL-04 | E | `carrier.drone_id` is DRONE; `decoy_spawn/smoke_launcher/sensor_puck` zone kinds match | PY, ENG-F |
| V-ABL-05 | W | Sheet ↔ `global.json → unit_assignments` agree: `archetype` equal; every framework ability name of the assignment appears in the sheet's `abilities` (or is produced by its alias' kind/mechanism, §7.4) and vice versa; `tags` (style tags) are keys of `style_tags`; `tier` equals the assignment's override if any | PY |
| **V-DET-01** | E | A `float` (or NaN) inside any Def/params (debug builds scan reflectively) | ENG-U |
| V-DET-02 | E | `params` keys not in sorted order / non-int leaf where int required | ENG-U |
| V-DET-03 | E | `check_frozen`: recomputed hash ≠ `data_hash` | ENG-U (tests) |
| V-HASH-01 | E | Recomputed `data_hash` ≠ `game/tests/golden/data_hash.json` (CI only; refresh after an intended change with `tools/gd run res://tests/tools/data_cli.gd -- --update-goldens`) | test |

**5.12.1 `tools/py/validate_balance.py` design.** Pure standard library (ARCH: `tools/py` = stdlib + numpy + Pillow; numpy not needed). Pipeline: (1) *load* — read the bible and every manifest file with `json.load(object_pairs_hook=…)` that rejects duplicate keys (`V-SCH-02`) and records line numbers; (2) *schema* — the JSON-Schema-subset validator copied from the bible's `validate_reference.py` (types, required, enum, pattern, min/max, `additionalProperties:false`) run against `game/data/balance/schema/*.schema.json`; (3) *convert* — `balance_lib/convert.py` mirrors `DefConvert` (same `milli/rdiv/ceil_div` code) to check ranges on converted values; (4) *references* — build per-kind id sets (bible ∪ balance) and resolve every reference; (5) *merge* — bible⊕balance policy of §5.2.4; (6) *rules* — `rules_source.py` (SCH/REF/CMP/CNF/RNG/ABL/EFF-structure/prose) and `rules_resolved.py` (TIER/ROLE/MOD/ROS using `balance_lib/resolver.py`, a straight port of §5.4-5.7 that also produces `resolver_golden.json`); (7) *report* — grouped by rule id, `--json`, exit codes below. The framework's own checks are reused, not re-implemented: `balance_lib/rules_source.py` imports `tools/py/balance_calc.py` for `fair_cost_deviation` (fed with the sheet plus the `unit_assignments` ability names) and `final_damage` (cross-check vectors), and runs `balance_calc.py validate` as the first step of `--strict`. Options: `--strict` (WARN→error, prose check → error), `--strict-redundant`, `--only`, `--files a.json,b.json` (partial run for authors), `--list-designer-params`, `--self-test`, `--bible PATH`, `--balance DIR`. It never writes into `game/`; golden generators write only to paths given on the command line.

**Exit codes / output.** `validate_balance.py`: `0` clean, `1` errors, `2` warnings with `--strict`, `3` usage. `--json` writes `{rule, severity, where, message}` records; default output groups by rule id. `--only V-CMP,V-CNF` filters; `--self-test` checks converter parity vectors.

### 5.13 Dev ergonomics, data browser, AI queries

**Hot reload (debug builds).** `DefHotReload.poll()` compares `FileAccess.get_modified_time` of the bible and each manifest file against a stored snapshot (≤ 1 Hz, driven by the app's `_process`). `reload()` runs the complete pipeline on the files as they are on disk and returns a *new* `GameData` (never mutates the old one). On error the previous data stays active and the report is shown in a dev overlay. A new `GameData` is used by the Field Manual and by the *next* match; a running local match may adopt it via `SimWorld.swap_data` only if `is_hot_swap_compatible` (identical id lists ⇒ identical indices) and the match is not networked. `enabled()` is `OS.is_debug_build()` and `res://` is a real directory (in exported builds `res://` is a PCK with meaningless mtimes; a dev may pass `--data-root=<dir>` so the loader reads a filesystem copy). `poll()` costs one stat per file (≈ 20 files).

**AI queries** (`DefQuery`, §3.9) use only roster tables: `units_with` filters `roster.producible_units` by tag masks (order: ascending index); `cheapest_*` = min `cost`, tie → lower index; `counters_of` scores `unit_dps_x100(vs target's armor) · 100 / cost` (integers), sorted descending with ties → lower index, and only units whose `attack_layer_mask` contains the target's `home_layer` bit; `tech_path` is a topological order of `requires` (Kahn, ties by lowest structure index); `min_time_to_ticks` sums `build_ticks` along the chain (single-builder pessimistic bound). Example: *cheapest anti-air defense for `roster.def.russia`* = `cheapest_structure_with(roster, DefEnums.ST_DEFENSE | data.tags.structure_bit("anti_air"))` → `structure.shared.aa_battery` (900 credits, bible fixed); *cheapest anti-air unit* = `cheapest_unit_with(roster, UT_ANTI_AIR)`.

**Field Manual** (`DefBrowser`): cards join bible prose (`role_and_abilities`, `effect_text`, `lore`, `traits_text`), base vs resolved stats, applying modifiers (`source_text`, layer, conditional flag — found by re-matching `roster.modifier_list` selectors), strong/weak-versus derived from the damage matrix (top-2 / bottom-2 armor classes by `matrix_pct` of the unit's best weapon), prerequisites and tech tree, replacement relations, and roster deltas versus vanilla. Cards carry runtime-unit ints plus preformatted display strings from `DefFormat` (`cells_text(7168) = "7.0"`, `seconds_text(550) = "27.5"`, `percent_text(1000) = "10"`; integer math only, so `src/data` stays float-free); the UI module may convert to floats for layout; nothing flows back into the sim.

### 5.14 Appendices to §5 (generated from the bible by the reference implementation)

#### 5.14.1 The 27 bible selectors
Columns: kind = `entity_kinds`; `C1/C2/C3` = condition codes of §5.9.1; `U1/U2/U3` = unresolved domains of §5.9.2; `mods` = number of the 98 modifiers that use it; `matches` = units/structures matched among the 156 bible units / 29 structures by *base* tags (roster overrides can only add `amphibious` to the PD Collector, a `service` unit, which no combat selector matches).

| # | selector | kind | all_tags | any_tags | exclude | explicit / extra | cond | unres | mods | matches (units/structs) |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | aircraft | unit | combat aircraft | - | - | - | - | - | 7 | 19/0 |
| 1 | aircraft_or_ships | unit | combat | aircraft ship | - | - | - | - | 1 | 45/0 |
| 2 | airfields | structure | - | - | - | id:airfield | - | - | 1 | 0/1 |
| 3 | all_transports | unit | transport | - | - | - | - | - | 1 | 18/0 |
| 4 | amphibious_combat_units | unit | combat amphibious | - | - | - | - | - | 1 | 12/0 |
| 5 | amphibious_combat_vehicles | unit | combat amphibious land_vehicle | - | - | - | - | - | 1 | 12/0 |
| 6 | amphibious_vehicles | unit | combat amphibious land_vehicle | - | - | - | - | - | 2 | 12/0 |
| 7 | amphibious_vehicles_on_water | unit | combat amphibious land_vehicle | - | - | - | C1 ON_WATER | - | 1 | 12/0 |
| 8 | combat_infantry | unit | combat infantry | - | - | - | - | - | 17 | 37/0 |
| 9 | combat_units | unit | combat | - | - | - | - | - | 2 | 152/0 |
| 10 | defensive_structures | structure | defense | - | - | - | - | - | 6 | 0/11 |
| 11 | garrisoned_combat_infantry | unit | combat infantry | - | - | - | C2 IN_GARRISON | - | 1 | 37/0 |
| 12 | generators | structure | - | - | - | id:generator | - | - | 3 | 0/1 |
| 13 | ground_combat_units | unit | combat ground | - | - | - | - | - | 1 | 107/0 |
| 14 | land_artillery | unit | combat land_vehicle artillery | - | - | - | - | - | 5 | 16/0 |
| 15 | land_combat_vehicles | unit | combat land_vehicle | - | - | - | - | - | 21 | 70/0 |
| 16 | land_vehicle_repairs | unit | land_vehicle | - | - | - | C3 PAID_REPAIR | - | 1 | 73/0 |
| 17 | light_land_vehicles | unit | combat land_vehicle light | - | - | - | - | - | 7 | 19/0 |
| 18 | non_superweapon_structures | structure | - | - | superweapon | - | - | - | 1 | 0/21 |
| 19 | ordinary_guided_missiles | projectile | - | - | superweapon | - | - | U3 | 1 | 0/0 |
| 20 | refineries | structure | - | - | - | id:refinery | - | - | 1 | 0/1 |
| 21 | scouts_or_artillery | unit | combat | scout artillery | - | - | - | - | 1 | 40/0 |
| 22 | ships | unit | combat ship | - | - | - | - | - | 4 | 26/0 |
| 23 | structures | structure | - | - | - | - | - | - | 1 | 0/29 |
| 24 | tanks | unit | combat tank | - | - | - | - | - | 8 | 25/0 |
| 25 | thermal_beam_weapons | weapon | - | - | - | sw:helios_reflector | - | U2 | 1 | 0/0 |
| 26 | unmanned_combat_units | unit | combat unmanned | - | - | - | - | U1 | 1 | 6/0 |

Two selectors are definitional duplicates (`amphibious_combat_vehicles` = `amphibious_vehicles`, both `combat amphibious land_vehicle`; `amphibious_vehicles_on_water` adds condition C1); they stay separate ids (the bible references each) and all compile.

#### 5.14.2 All 98 bible modifiers grouped by stat kind (the resolver's vocabulary)
`L` = layer (P = parent faction = 1, S = subfaction = 2); `owner` `F:` faction / `R:` roster. Counts: 13 stat kinds — cost 27, health 24, build time 18, speed 13, range 4, reload 3, power 2, damage 2, rearm 1, sight 1, repair rate 1, repair cost 1, projectile speed 1. All 98 use operation `add_percent_within_layer`; all `delta_percent` are integers.


**S0 `cost_credits`** (27)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.02 | F:napc | P | +10% | land_combat_vehicles |  |
| napc.usa.01 | R:napc.usa | S | -15% | aircraft |  |
| napc.mexico.01 | R:napc.mexico | S | -15% | combat_infantry |  |
| napc.mexico.03 | R:napc.mexico | S | +20% | aircraft |  |
| nec.01 | F:nec | P | +5% | combat_units |  |
| nec.eurocorps.02 | R:nec.eurocorps | S | +10% | tanks |  |
| nec.alpine_brotherhood.02 | R:nec.alpine_brotherhood | S | -15% | defensive_structures |  |
| olm.algeria.01 | R:olm.algeria | S | -15% | light_land_vehicles |  |
| olm.algeria.04 | R:olm.algeria | S | +15% | tanks |  |
| olm.el_andalus.03 | R:olm.el_andalus | S | +15% | aircraft |  |
| def.01 | F:def | P | -10% | land_combat_vehicles |  |
| def.russia.02 | R:def.russia | S | +10% | land_combat_vehicles |  |
| def.kazakhstan.02 | R:def.kazakhstan | S | -15% | refineries |  |
| def.north_korea.03 | R:def.north_korea | S | -10% | defensive_structures |  |
| def.north_korea.04 | R:def.north_korea | S | +25% | aircraft |  |
| pd.indonesia.03 | R:pd.indonesia | S | +15% | tanks |  |
| pd.japan.02 | R:pd.japan | S | +10% | combat_units |  |
| han.01 | F:han | P | -15% | combat_infantry |  |
| han.china.02 | R:han.china | S | +10% | land_combat_vehicles |  |
| han.vietnam.02 | R:han.vietnam | S | -10% | light_land_vehicles |  |
| han.vietnam.03 | R:han.vietnam | S | +20% | tanks |  |
| han.cambodia.01 | R:han.cambodia | S | -15% | unmanned_combat_units | UNRES |
| ae.nigeria.01 | R:ae.nigeria | S | -15% | combat_infantry |  |
| ae.kongo.03 | R:ae.kongo | S | +20% | land_artillery |  |
| ae.south_africa.02 | R:ae.south_africa | S | +15% | land_combat_vehicles |  |
| sap.india.03 | R:sap.india | S | -10% | generators |  |
| sap.thailand.01 | R:sap.thailand | S | -15% | amphibious_combat_vehicles |  |

**S1 `build_time_seconds`** (18)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.usa.03 | R:napc.usa | S | +15% | land_combat_vehicles |  |
| napc.canada.02 | R:napc.canada | S | -15% | ships |  |
| napc.mexico.02 | R:napc.mexico | S | -20% | combat_infantry |  |
| nec.eurocorps.03 | R:nec.eurocorps | S | +10% | land_combat_vehicles |  |
| nec.alpine_brotherhood.03 | R:nec.alpine_brotherhood | S | +20% | aircraft |  |
| olm.algeria.02 | R:olm.algeria | S | -15% | light_land_vehicles |  |
| def.02 | F:def | P | -10% | land_combat_vehicles |  |
| def.north_korea.02 | R:def.north_korea | S | -15% | combat_infantry |  |
| pd.australia.02 | R:pd.australia | S | -15% | airfields |  |
| pd.australia.04 | R:pd.australia | S | +15% | ships |  |
| pd.indonesia.01 | R:pd.indonesia | S | -15% | combat_infantry |  |
| han.02 | F:han | P | -15% | combat_infantry |  |
| han.china.03 | R:han.china | S | +10% | combat_infantry |  |
| han.cambodia.03 | R:han.cambodia | S | +20% | tanks |  |
| ae.nigeria.02 | R:ae.nigeria | S | -15% | combat_infantry |  |
| ae.nigeria.03 | R:ae.nigeria | S | -10% | non_superweapon_structures |  |
| ae.south_africa.03 | R:ae.south_africa | S | +15% | combat_infantry |  |
| sap.india.02 | R:sap.india | S | +15% | land_combat_vehicles |  |

**S2 `health`** (24)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.01 | F:napc | P | +10% | land_combat_vehicles |  |
| napc.canada.01 | R:napc.canada | S | +10% | amphibious_combat_units |  |
| nec.nordics.03 | R:nec.nordics | S | -10% | tanks |  |
| nec.eurocorps.01 | R:nec.eurocorps | S | +15% | tanks |  |
| nec.alpine_brotherhood.01 | R:nec.alpine_brotherhood | S | +15% | combat_infantry |  |
| olm.03 | F:olm | P | -10% | combat_infantry |  |
| olm.04 | F:olm | P | -10% | light_land_vehicles |  |
| olm.algeria.03 | R:olm.algeria | S | -10% | light_land_vehicles |  |
| olm.el_andalus.01 | R:olm.el_andalus | S | +15% | ships |  |
| def.russia.01 | R:def.russia | S | +15% | land_combat_vehicles |  |
| def.kazakhstan.03 | R:def.kazakhstan | S | -15% | land_combat_vehicles |  |
| def.north_korea.01 | R:def.north_korea | S | +20% | combat_infantry |  |
| pd.02 | F:pd | P | -15% | defensive_structures |  |
| pd.australia.03 | R:pd.australia | S | -10% | land_combat_vehicles |  |
| pd.indonesia.02 | R:pd.indonesia | S | +20% | all_transports |  |
| pd.japan.03 | R:pd.japan | S | -10% | defensive_structures |  |
| han.03 | F:han | P | -10% | land_combat_vehicles |  |
| han.china.01 | R:han.china | S | +15% | land_combat_vehicles |  |
| ae.nigeria.04 | R:ae.nigeria | S | -10% | aircraft |  |
| ae.kongo.02 | R:ae.kongo | S | +10% | combat_infantry |  |
| sap.01 | F:sap | P | +15% | defensive_structures |  |
| sap.india.01 | R:sap.india | S | +15% | land_combat_vehicles |  |
| sap.thailand.03 | R:sap.thailand | S | -10% | defensive_structures |  |
| sap.pakistan.03 | R:sap.pakistan | S | -15% | light_land_vehicles |  |

**S3 `movement_speed`** (13)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.canada.03 | R:napc.canada | S | +20% | amphibious_vehicles_on_water | COND:ON_WATER |
| nec.nordics.02 | R:nec.nordics | S | +15% | amphibious_vehicles |  |
| olm.01 | F:olm | P | +10% | combat_infantry |  |
| olm.02 | F:olm | P | +10% | light_land_vehicles |  |
| olm.saudi_arabia.03 | R:olm.saudi_arabia | S | -10% | land_combat_vehicles |  |
| def.03 | F:def | P | -10% | land_combat_vehicles |  |
| def.russia.03 | R:def.russia | S | -10% | land_combat_vehicles |  |
| def.kazakhstan.01 | R:def.kazakhstan | S | +20% | ground_combat_units |  |
| pd.01 | F:pd | P | +15% | ships |  |
| han.vietnam.01 | R:han.vietnam | S | +10% | combat_infantry |  |
| ae.kongo.01 | R:ae.kongo | S | +20% | amphibious_vehicles |  |
| sap.02 | F:sap | P | -10% | land_combat_vehicles |  |
| sap.thailand.02 | R:sap.thailand | S | +10% | combat_infantry |  |

**S4 `weapon_damage`** (2)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| olm.saudi_arabia.02 | R:olm.saudi_arabia | S | +15% | thermal_beam_weapons | UNRES |
| olm.el_andalus.02 | R:olm.el_andalus | S | +20% | garrisoned_combat_infantry | COND:IN_GARRISON |

**S5 `weapon_range_cells`** (4)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| pd.australia.01 | R:pd.australia | S | +15% | land_artillery |  |
| ae.02 | F:ae | P | -10% | land_artillery |  |
| ae.south_africa.01 | R:ae.south_africa | S | +10% | land_combat_vehicles |  |
| sap.pakistan.01 | R:sap.pakistan | S | +15% | land_artillery |  |

**S6 `reload_interval_seconds`** (3)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.canada.04 | R:napc.canada | S | +15% | land_artillery |  |
| pd.japan.01 | R:pd.japan | S | -10% | aircraft_or_ships |  |
| sap.thailand.04 | R:sap.thailand | S | +10% | tanks |  |

**S7 `rearm_time_seconds`** (1)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| napc.usa.02 | R:napc.usa | S | -20% | aircraft |  |

**S8 `sight_cells`** (1)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| nec.nordics.01 | R:nec.nordics | S | +20% | scouts_or_artillery |  |

**S9 `power_output`** (2)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| olm.05 | F:olm | P | +25% | generators |  |
| olm.saudi_arabia.01 | R:olm.saudi_arabia | S | +20% | generators |  |

**S10 `repair_progress_rate`** (1)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| han.cambodia.02 | R:han.cambodia | S | +25% | structures |  |

**S11 `repair_credit_cost_per_health`** (1)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| ae.01 | F:ae | P | -25% | land_vehicle_repairs | COND:PAID_REPAIR |

**S12 `projectile_flight_speed`** (1)

| modifier | owner | L | delta | selector | flags |
|---|---|---|---|---|---|
| sap.pakistan.02 | R:sap.pakistan | S | +20% | ordinary_guided_missiles | UNRES |

**Reading the table.** Same-roster multi-layer stacking occurs in 40 (target, stat) pairs over the 32 rosters (e.g. Russia cost −10 % ⊗ +10 % = 0.99; Saudi generator +25 % ⊗ +20 % = 1.50; defensive-structure health: Japan 0.85 ⊗ 0.90 = 0.765, Thailand 1.15 ⊗ 0.90 = 1.035); same-layer additive stacking never occurs in the bible's typed modifiers (0 cases) but is exercised by layer 3.

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 The data module consumes and emits **no sim commands and no sim events**
`data/` is a pure library (DR-8, DR-9). What it *is* the authority for are the **integer codes** carried by other domains' commands/events — all defined in §4.1 (`Kind`, `Stat`, `DamageType`, `Cond`, `EffectOp`, `AbilityKind`, `PlaceFlag`, `TargetMode`, `TargetVision`, flags, tag bits) — and the **validation predicates** those commands must call.

### 6.2 Def-referencing commands and the data predicates their validation must use
(Command names/codes belong to the sim/net domains; names below are suggestions. A def index in a command is always in the namespace implied by the command; `DefRoster` of the *issuing player* is authoritative, never the global table.)

| Command (owner: sim) | def fields | Validation the CommandSystem must perform with data (all pure, O(1)) |
|---|---|---|
| `BUILD` {structure_def, cell_x, cell_y} | `structure` index | `roster.has_structure(d)`; `!(s.flags & SF_NO_BUILD)`; `DefRoster.prereqs_met(s.requires_mask, owned_mask)`; if `s.max_per_player > 0` count owned+queued < limit (strategic: 1); `s.place_mask` bits: `PLACE_SHORELINE` ⇒ adjacent water, `PLACE_NO_RADIUS_EXTENSION` ⇒ inside some own HQ `build_radius` and never a radius source; footprint `s.fp_w × s.fp_h` (+`fp_mask`) on buildable cells; cost/time = **roster clone** `s.cost`, `s.build_ticks` |
| `TRAIN` {producer_entity, unit_def, n} | `unit` index | `roster.has_unit(d)`; `u.unit_class ∈ {SERVICE, BASELINE, UNIQUE}`; `u.producer == producer.def`; `prereqs_met(u.requires_mask, owned_mask)`; queue length ≤ `economy.queue_length_n`; a **replaced unit is rejected** (absent from the roster) |
| `RESEARCH` {research_def} | `research` index | `roster.research_slot(d) ≥ 0`; `prereqs_met(r.requires_mask, owned_mask)`; `!view.layer3.is_done(d)`; not already queued; `r.cost`, `r.time_t` |
| `POWER` {power_def, x, y, angle?} | `power` index | `roster.power_slot(d) ≥ 0`; `prereqs_met(p.requires_mask, owned_mask)` and, if `p.requires_powered`, prerequisites powered; cooldown ready (never reset by rebuilding prerequisites); credits ≥ `p.cost`; target check by `p.target_vision` (`ANY` none, `EXPLORED` explored terrain, `CURRENT` currently visible) and `p.target_mode` geometry |
| `SUPERWEAPON` {x, y, angle?} | — | `roster.superweapon ≥ 0`; launcher present (`sw.launcher`) and charged; `sw.target_vision == EXPLORED` |
| `DEPLOY` {entity} | — | `u.ability_slot_of_kind[DEPLOY_STRUCTURE] ≥ 0` (MCV → HQ: `s.deploy_unit == u.index`) or `DEPLOY`/`MODE_SWITCH` |

### 6.3 What other domains must add (flags)
* **sim**: per-player `roster: DefRoster` and `view: DefPlayerView` (which owns the `DefLayer3`); call `view.apply_research` on research completion; add `view.checksum()` and `data.data_hash()` to `SimWorld.checksum()`; apply `DefStatMath.rescale_hp` on max-HP changes; implement `SimWorld.swap_data` (debug, non-networked only).
* **abilities/zones/combat**: evaluate `Cond` codes 2 and 10-22 (§4.1; 21 = runtime `ON_WATER`, 22 = `BEHIND_COVER`), honour `stack_group`, read weapon numbers only from `DefWeaponSlot`, use `reload_mt` with an absolute `next_fire_mt` accumulator, route all resistance through `DefStatMath.resist_total_bp/final_damage`.
* **net**: carry `GameData.handshake()`; refuse on mismatch with `diff_handshake`; store `format/hash/tables["ids"]` in replays.
* **events**: any `SimEvent` that names a def carries the def *index* plus the kind implied by the event type (e.g. `UNIT_SPAWNED.def` is a unit index); never a string.
* Events emitted by this module: **none** (load problems go through `DefLoadReport` → `Log`; the app raises its own `data_reloaded` notification).

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.0 Source map, ownership and precedence (read this first)

Several architects specify balance files concurrently. The **data module reads exactly the manifest's files** (§7.2); the table states who owns each file's *content and schema*, which loader consumes it, and — where two specs claim the same file or class — the **recommended owner** (the reconciler decides; nothing below depends on the choice except the plug-in list).

| File / block | Owner of content | Consumed by | Status / recommendation |
|---|---|---|---|
| `game/data/bible/meridian_factions.json` (+`manifest.json`, mirrored by `tools/py/sync_bible.py`) | bible (read-only) | `DefLoader` | canonical for everything it specifies |
| `balance/manifest.json` | data | `DefSources` | §7.2 |
| **`balance/global.json`** (exists; 127 KB) | **balance framework** (`docs/balance/TAXONOMY.md`, `FRAMEWORK.md`, `tools/py/balance_calc.py`) | `DefLoader` P2 + `DefLoaderBalance` | vocabulary, weapon/role archetypes, structures, defenses, economy/power/production, carriers, superweapon & support-power damage numbers; consumed **by key** (§7.3); unlisted keys are ignored by the loader |
| `balance/units_<code>.json` ×9 | data schema (§7.6-§7.7); numbers by the faction balance authors, seeded from `balance_calc.py proposals --styled` | `DefLoaderBalance` | the framework's `<faction>.json` (FRAMEWORK §7.3): unit sheets (FRAMEWORK §4.5), weapon instances (FRAMEWORK §4.4), summons and drones, in the framework's field names |
| `balance/structures.json` | data | `DefLoaderBalance` | **overlay only** (§7.8: abilities, flags, exits, footprint masks, extra tags); all numbers come from `global.json → structures/defenses/superweapons.common` |
| `balance/ability_kinds.json` | data registry v1 (§7.4) | `DefAbilityKinds` | superset of the framework's 16 `ability_templates` (templates, framework-name aliases, implicit rules). **Note:** the abilities spec's `abilities.json` (ability defs + `slots` assignment per unit/structure) is a different file; when it is adopted, its `slots` supersede the sheets' `abilities` (setting both differently is `V-CNF-09`) and this registry shrinks to the alias/implicit table used by the balance tools |
| `balance/research_effects.json`, `power_actions.json`, `zone_templates.json`, `faction_traits.json`, `neutral_structures.json` | data **fallback schemas** (§7.9-§7.14) | `DefLoaderRules` | **Use only if the owning domain supplies no equivalent.** Recommended owners: research/trait/zone/status encodings → **abilities** (`effects.json`, `zones.json`, `statuses.json`, `aura_classes.json`); power targeting/recipes, superweapon rules, neutral structures → **economy** (`powers.json`, `superweapons.json`, `neutral_structures.json`, `repair_profiles.json`, `summons.json`). The coverage tables of §7.9-§7.11 remain valid as a completeness checklist for whichever schema is adopted |
| `combat_rules.json`, `combat_warheads.json`, `combat_projectiles.json`, `combat_weapons.json`, `combat_loadouts.json` | **combat** | `DefCombatCompiler` (plug-in, §3.12) | combat's warhead/projectile/weapon/mount schemas are the *behavioural* description; the numbers that bible modifiers touch live in `DefWeaponSlot` (`damage range reload_mt proj_speed`) — recommended: combat's compiled weapon becomes/extends `DefWeaponSlot` so `DefStatMath` stays the only arithmetic |
| `abilities.json`, `aura_classes.json`, `statuses.json`, `zones.json`, `effects.json` | **abilities** | `DefAbilityCompiler` (plug-in) | see the fallback-schemas row |
| `economy.json`, `structure_rules.json`, `powers.json`, `superweapons.json`, `neutral_structures.json`, `repair_profiles.json`, `summons.json` | **economy** | `DefEconCompiler` (plug-in) | `economy.json` overrides `DefEconomy` fields of the same meaning (recommended: harvest/deposit/refund constants are economy's; floors/caps/bible constants stay ★); `structure_rules.json` must not repeat footprints/health (they come from `global.json`) |
| `balance/ai/*.json` | **ai** | `AiDataStore` (outside `data_hash`; AI is not sim state) | no data-module involvement |

**Precedence rules.** (P1) A non-null bible value is never overridden (`V-CNF-01`). (P2) `global.json` is the authority for vocabulary, archetypes, structures, defenses and design numbers; the loader verifies its vocabulary against `DefEnums` (`V-CNF-05`). (P3) A unit sheet's explicit number overrides the role-archetype default; sheets are the runtime truth for units. (P4) A domain-owned file is authoritative for its own schema; two files defining the same field meaning is an ERROR (`V-CNF-09`, checked by the PY validator over the manifest's ids). (P5) Unknown top-level keys of `global.json` are ignored (they serve `balance_calc.py`); unknown keys in files the data module owns are errors.

**Renames since the first publication of this spec** (other specs refer to the old names): `abilities.json` (registry) → `ability_kinds.json`; `powers.json` → `power_actions.json` (economy's M3 "data's `powers.json`" = this file); `zones.json` → `zone_templates.json` (abilities' generated `zones.json` is their own); `factions.json` → `faction_traits.json`; `neutrals.json` → `neutral_structures.json` (economy's M15 "data's `neutrals.json`"); `superweapons.json` → removed, compiled from `global.json → superweapons` (§7.11); `weapons_<code>.json` and projectile registries → weapon instances inside `units_<code>.json` (§7.6); `DefWeapon`/`DefProjectile` → `DefWeaponArch` + `DefWeaponSlot`; `speed_water` → derived cache of the same name plus `deep_speed_bp`/`water_mult_bp`. The reconciler may swap any of these names back; the schemas do not depend on them.

### 7.1 Conventions common to the files the data module owns

* **Envelope.** Data-owned files are JSON objects `{"schema": "meridian.balance.<name>/1", …}` (`global.json` carries `"version": 1` instead). Keys starting with `_` are documentation, ignored by loader, schema check and table hashes (they do change the per-file diagnostic hash). UTF-8, LF, 2-space indent, **entries sorted by id** (lint `V-SCH-09`). Strict JSON: no comments, no trailing commas.
* **Designer units and field names follow the balance framework** so unit sheets, role archetypes and `balance_calc.py` output are shape-compatible: `cost_credits`, `build_time_s`, `health`, `speed_cells_s`, `vision_cells`, `radius_cells`, `turn_deg_s`, `reload_s`, `range_cells`, `*_pct`, `*_s`, `*_cells`. Numbers have ≤ 3 decimals (`*_pct` ≤ 2). Suffix rules of §5.10.1 apply to every `params` object. Enumerations are lowercase strings validated against `DefEnums`.
* **Notation** in the field tables: `int` integral; `num` decimal; `pct` percent decimal; `id<unit>` = string id of that kind; `[T]` array; `{}` object; `req` required, `opt` optional (default shown), `req*` = required *only when the bible value is null* (bible non-null ⇒ omit or repeat identically, §5.2.4).
* **Presentation ids** (`pres: {recipe, icon, snd_profile, ai_role, scale_pct}`) are opaque strings for `view/`, `audio/`, `ai/`; existence is checked only when a registry exists (ASSUMPTION(view): `game/data/recipes/<recipe id>.json`; ASSUMPTION(audio): `game/data/audio/events.json`). **Default**: `recipe` and `icon` = the def id. They compile to `pres_*` fields, which are excluded from every hash.
* **Selectors and conditions inside effects** use the compact forms of §7.5.

### 7.2 `game/data/balance/manifest.json`
```json
{
  "schema": "meridian.balance.manifest/1",
  "format": 1,
  "files": [
    "ability_kinds.json", "faction_traits.json", "global.json", "neutral_structures.json", "power_actions.json",
    "research_effects.json", "structures.json",
    "units_ae.json", "units_def.json", "units_han.json", "units_napc.json", "units_nec.json",
    "units_olm.json", "units_pd.json", "units_sap.json", "units_shared.json", "zone_templates.json"
  ]
}
```
`files` sorted ascending, unique, every file must exist, no file outside the list is read (`V-SCH-01`). Files owned by registered `DefDomainCompiler`s (e.g. `combat_weapons.json`, `effects.json`, `economy.json`) are appended to this list when their compiler is registered; the manifest is also the hot-reload watch list and the per-file-hash key set.

### 7.3 `global.json` — what the loader consumes (keys of the existing file)

`global.json` is authored by the balance framework and enforced by `python3 tools/py/balance_calc.py validate`; **its shape is not redefined here**. The loader reads these keys (all others — `scaling`, `targets`, `style_tags`, `faction_styles`, `modifier_compensation`, `ability_value_pct`, `naval`, `artillery`, `veterancy`, `notes`… — are design inputs of the Python tools and ignored):

| key (path) | shape in the file | consumer → Def | conversion / notes |
|---|---|---|---|
| `version` | int | format gate | must be 1 |
| `conventions.{tps,cell_units}` | 20 / 1024 | assert | must equal `SimConfig.TPS`, `Fp.CELL` (`V-CNF-05`) |
| `damage_types[]` | `{id,index,groups[],nonlethal,label}` ×7 | `DefDamageTable.damage_ids/group_mask/nonlethal_mask` | ids/indices must equal `DamageType`; `groups` → `ResistGroup` bits |
| `resist_groups[]` | 7 strings | group bit = list index | bullet 1, explosive 2, beam 4, thermal 8, rail 16, kinetic 32, emp 64 |
| `armor_classes[]` | `{id,index,layer,label}` ×11 | `DefDamageTable.armor_ids` | index frozen (`ArmorClass`) |
| `damage_matrix` | `{dtype: {armor: pct}}` | `matrix_pct[dtype*11+armor]` | integer percent, 0 = cannot damage |
| `resistance_rules` | `{cap_pct:50, min_damage:1, formula, …}` | `economy.resist_cap_bp`, `min_damage` | cap must equal the bible (50) |
| `layers[]`, `fire_modes[]` | strings | verify `Layer`, `FireMode` | direct 0, indirect 1, melee 2 |
| `size_classes{}` | `{radius_cells, turn_deg_s, mass, structure, footprint?}` ×14 | `DefBodyTable` | radius → u, turn → apt |
| `terrain_kinds[]`, `movement_classes{}` | 8 strings; `{index, layer, terrain_speed_pct{kind:pct}, note?}` ×9 | `DefMoveTable.speed_bp`, `layer`, `layer_mask` | pct×100 → bp; index frozen (`MoveClass`) |
| `weapon_archetypes{}` | `{index, damage_type, fire_mode, projectile_kind, projectile_speed_cells_s, homing, targets[], splash_cells, splash_edge_pct, scatter_cells, range_cells_band[lo,hi], min_range_cells, reload_s_band[lo,hi], turret_deg_s, interceptable_by, suppressive_default}` ×27 | `DefWeaponArch` | index = `WeaponArch`; `warch.<name>` ids |
| `archetypes{}` | 32 **role archetypes**: `{family, tier, producer, size_class, armor_class, movement_class, layer, cost_credits, build_time_s, health, speed_cells_s, vision_cells, radius_cells, weapons[], transport_capacity_squads?, rearm_s_full?, sortie_cycle_s?, aura_radius_cells?, drone_*?, …}` | defaults for sheets naming an `archetype`; tier/band validators | scalar keys are exactly the sheet keys of §7.7 |
| `unit_assignments{}` | `{unit id: {archetype, tags[], abilities[], tier?}}` ×156 | validators (`V-ABL-05`, `V-TIER-*`); default `archetype`, `abilities` and `tags` when a sheet omits them | style `tags` document how the numbers were derived |
| `service_units{}` | engineer, collector, mcv, landing_transport: cost, build_time_s, health, armor_class, speed, vision, radius, producer, capacity… | defaults for `units_shared.json` | costs are bible ★ (500/1400/3000/900) |
| `structures{}` | headquarters, generator, refinery, barracks, factory, dock, radar, airfield, laboratory, watchtower, anti_tank_turret, aa_battery, advanced_defense, superweapon, relay: `{cost_credits, build_time_s, health, armor_class, footprint[w,h], radius_cells, vision_cells, power_delta, pads?, detector_radius_cells?, deploy_s?}` | `DefStructure` numbers | ids map by short name (`structure.shared.<key>`; `advanced_defense` → the 8 `advanced_defense`-tagged; `superweapon` → the 8 strategic structures; `relay` → `structure.nec.relay`); `cost`, `power_delta`, `build_time_s` must equal the bible where non-null (`V-CNF-01`) |
| `defenses.shared{}`, `defenses.advanced{}` | weapon lists of watchtower / AT turret / AA battery; per-faction advanced defenses `{faction, health, weapon{…}, turret_deg_s}` | structure weapon slots, advanced-defense `health` | weapon entry shape = §7.6 |
| `detection`, `vision_defaults_cells` | `{default_radius_cells:5, watchtower_cells:4, aa_battery_cells:5}`; `{role: cells}` | `economy.detector_*`, validators | ★ bible |
| `production`, `economy`, `power` | see §4.2 `DefEconomy` mapping | `DefEconomy` | ★ values re-verified against the bible |
| `carriers{}` | `{drone_count, drone_health, drone_armor_class, drone_speed_cells_s, drone_replace_s, drone_replace_cost_credits, drone_weapon{}, drone_leash_cells, counted_in_unit_cap:false}` | DRONE defs (U1) | replacement cost/time → `cost`/`build_ticks` of the DRONE def |
| `superweapons{}`, `support_power_damage{}` | per weapon: `recharge_s, warning_s, packets[]{radius_cells, damage, damage_type, edge_pct, offset_cells, delay_ticks\|at_s}` etc.; strikes `{warning_s, shells, over_s, zone_radius_cells, shell{…}}` | `DefSuperweapon.packets/params`; strike `DefImpactPacket`s | recharge/warning are bible copies (verified); see §7.11 |
| `movement_defaults` | `{accel_ticks{size_class: t}, per_unit_override_fields:[accel_ticks, deep_speed_pct, turn_deg_s], …}` | `DefUnit.accel_t` default | the three override fields are exactly what a sheet may set per unit |
| `aircraft.pads_per_airfield`, `ability_templates{}` | 4; 16 templates | `service_pads` default; alias table §7.4 | |

Excerpts (verbatim from the file):
```json
"damage_types": [ {"id":"ap","index":1,"groups":["explosive"],"nonlethal":false}, {"id":"thermal","index":3,"groups":["beam","thermal"],"nonlethal":false}, {"id":"emp","index":6,"groups":["emp"],"nonlethal":true} ],
"weapon_archetypes": { "tank_cannon": {"index":3,"damage_type":"ap","fire_mode":"direct","projectile_kind":"shell","projectile_speed_cells_s":16,"homing":true,
    "targets":["ground","surface_water"],"splash_cells":0.5,"splash_edge_pct":50,"scatter_cells":0.0,"range_cells_band":[6.5,9.0],"min_range_cells":0.0,
    "reload_s_band":[1.0,1.6],"turret_deg_s":90,"interceptable_by":"none","suppressive_default":false} },
"archetypes": { "mbt_t1": {"family":"tank","tier":1,"producer":"factory","size_class":"medium","armor_class":"medium_armor","movement_class":"tracked","layer":"ground",
    "cost_credits":850,"build_time_s":27.5,"health":900,"speed_cells_s":2.0,"vision_cells":9.0,"radius_cells":0.55,
    "weapons":[{"archetype":"tank_cannon","damage":140,"hits_per_volley":1,"reload_s":1.2,"range_cells":7.0}]} },
"structures": { "generator": {"cost_credits":600,"build_time_s":25,"health":1200,"armor_class":"building_light","footprint":[2,2],"radius_cells":1.0,"vision_cells":6.0,"power_delta":150} }
```
**Conversions of the excerpt** (checked by `test_data_loader`): `tank_cannon` → `DefWeaponArch{dtype:1, fire_mode:0, proj_kind:1 (shell), proj_speed:819, homing:true, target_mask:5, splash_radius:512, splash_edge_bp:5000, scatter:0, range_lo:6656, range_hi:9216, reload_lo_mt:20000, reload_hi_mt:32000, turret_turn:51, interceptable:0, tags: direct_fire|anti_ground}`; `mbt_t1` weapon 0 → slot `{damage:140, hits_per_volley:1, reload_mt:24000, reload_ticks:24, range:7168}`; `generator` → `{cost:600, build_ticks:500, health:1200, armor_class:8, fp_w:2, fp_h:2, radius:1024, sight:6144, power:150}`.

### 7.4 `game/data/balance/ability_kinds.json` — ability kind registry and templates

```
{ "schema": "meridian.balance.ability_kinds/1",
  "kinds":     { "<kind name>": { "id": int, "scopes": ["unit"|"structure"|"player"], "params": { "<file key>": {"type","req","def","min","max","doc"} } } },
  "templates": { "ability.<kind>.<variant>": { "kind": "<kind>", "params": { "<file key>": <value in file units> } } },
  "aliases":   { "<bare framework ability name>": "ability.<kind>.<variant>" },
  "implicit":  [ { "when": "tag:detector" | "family:aircraft" | "archetype:<id>", "templates": ["ability.…"] } ],
  "def_params":{ "<file key>": {"type","def","scopes":[…]} } }
```
`kinds[*].id` must equal `DefEnums.AbilityKind`; `params.<key>.type` ∈ the suffix types of §5.10.1 plus `bool`, `str`, `enum:<a|b>`, `unit_id`, `unit_ids`, `structure_id`, `structure_ids`, `zone_id`, `[ {…} ]` (typed sub-spec). **Registry v1** (`*` = required; `=v` default; params in file units). Owner of *behaviour*: abilities/zones/combat domains (ASSUMPTION(abilities): they adopt or amend this table; the reconciler edits `ability_kinds.json` + `DefEnums`, no loader code). The abilities catalog (`docs/spec/abilities_catalog.md`) already maps every unit and structure row onto these kinds and parameter names, and its per-row `key=value` cells are the source of the per-unit `ability_params` when its compiler is adopted:

| id | kind | params | scope | used by (bible) |
|---|---|---|---|---|
| 1 | `detector` | `radius_cells*` | unit, structure | 42 units; Watchtower 4, AA Battery 5; default 5 |
| 2 | `camouflage` | `delay_s*`, `needs_stationary=false`, `needs_no_attack=true`, `moving_ok=false`, `reveal_on_fire=true`, `reveal_on_damage=true`, `reveal_s=0`, `keeps_abilities_active=false` | unit | Condor (6 s, no attack), Mirage/Watchpost/River Warden (6 s stationary), Canopy Ranger (6 s stationary, no fire), Dune Rover (6 s no fire, `moving_ok`, `reveal_s=6`); research grants: Caravan APC, Link Operator |
| 3 | `deploy` | `deploy_s*`, `pack_s=0`, `immobile=true`, `turn_locked=false`, `range_bonus_pct=0`, `damage_bonus_pct=0`, `deployed_slots_n=[]`, `command_radius_bonus_cells=0` | unit | Paladin/Monsoon/Outrider/Shaheen/Ifrit 3 s, Archer, Sandglass, Saker 1 s, Ibex 2 s, Charlemagne 4 s (+25 % range), Gaj 4 s (+20 %), Fortress Guard 3 s, Long Command Walker 3 s (+2 cells), Mekong 2 s |
| 4 | `mode_switch` | `switch_s*`, `modes*: [{id: str, slots_n: [int]}]`, `switch_at_structure_id=""` | unit | Shinano 3 s, Protea 3 s, Shogun (wings), Raptor (loadout only at an Airfield) |
| 5 | `transport` | `capacity_squads_n*`, `capacity_vehicles_n=0`, `load_s=1`, `unload_s=1`, `unload_speed_pct=100`, `passenger_damage_reduction_pct=0`, `passengers_fire=false`, `excluded_unit_tags=[]`, `unload_moving_speed_pct=0` | unit | APCs 2 squads, Okapi 3, Leviathan 4, Landing Transport 4 squads or 2 non-amphibious vehicles; Kancil `unload_speed_pct=150`; Beaver reinforced passengers |
| 6 | `heal` | `rate_pct_per_s*`, `radius_cells*`, `target_unit_tags=["infantry"]`, `needs_out_of_combat_s=0` | unit | Combat Medic (infantry only) |
| 7 | `repair` | `rate_pct_per_s*`, `cost=paid\|free`, `target_unit_tags=[]`, `target_structure_tags=[]`, `radius_cells=0`, `one_target=true`, `can_self=false`, `can_repair_transport_riding=false` | unit | Engineer 1 %/s paid, Reef Technician, Lotus Tender, Lagos drone (free), Reclaimer, Alpine/Combat Pioneer, Mekong, River Warden |
| 8 | `command_field` | `radius_cells*`, `damage_bonus_pct*`, `deploy_s=0`, `stack_group*`, `eligible_unit_ids=[]` | unit | Link Operator, Dragon (5 cells, +10 %), Mekong, Long Walker |
| 9 | `interceptor` | `cooldown_s*`, `charges_n=1`, `range_cells*` | unit | Ural 12 s, Arjun 15 s |
| 10 | `suppression_support` | `recovery_bonus_pct*`, `radius_cells*` | unit | Signal Officer (50 %, 5 cells), Echo Team |
| 11 | `decoy_spawn` | `zone_id*`, `cooldown_s*`, `max_active_n=1` | unit | Echo Team (40 s) |
| 12 | `sensor_puck` | `zone_id*`, `cooldown_s*` | unit | Civic Rifle Team (30 s) |
| 13 | `smoke_launcher` | `zone_id*`, `radius_cells*`, `duration_s*`, `cooldown_s*` | unit | Naga (4 cells, 6 s, 40 s) |
| 14 | `ew_jammer` | `radius_cells*`, `sight_penalty_pct*` | unit | Aster (5 cells, 25 %) |
| 15 | `disembark_buff` | `duration_s*`, `damage_bonus_pct=0`, `damage_taken_reduction_pct=0`, `refresh_on_reboard=false` | unit | Island Raider (+20 %, 6 s), River Marine (−20 %, 6 s) |
| 16 | `portable_cover` | `build_s*`, `pack_s=0`, `lifetime_s*`, `resist_pct*`, `resist_groups=["bullet"]`, `pieces_per_builder_n=1`, `zone_id*`, `stationary_only=true` | unit | Vanguard (4 s/2 s pack, 20 %), Sapper, Combat Pioneer, Alpine Pioneer shelter (45 s, 25 %) |
| 17 | `salvage` | `action_s*`, `payout_pct*`, `wreck_life_s=60` | unit | Reclaimer, River Warden; AE trait grants Engineer |
| 18 | `frontal_shield` | `arc_deg*`, `reduction_pct*`, `resist_groups=["bullet"]` | unit | Gate Guard (25 %) |
| 19 | `carrier` | `wings*: [{id, drone_id, wing_size_n}]`, `replace_s*`, `launch_range_cells*` | unit | Tempest, Emperor, Shogun |
| 20 | `sensor_mast` | `deploy_s*`, `reveal_radius_cells*`, `immobile=true` | unit | Fen (6 cells) |
| 21 | `capture` | `capture_s*` | unit | Engineer |
| 22 | `harvest` | `capacity_credits*` | unit | Collector |
| 23 | `deploy_structure` | `structure_id*`, `deploy_s*` | unit | MCV → HQ |
| 24 | `submerge` | `surface_s*` | unit | Boreal (8 s) |
| 25 | `sortie` | `endurance_s=0`, `hover_when_firing=false` | unit | all aircraft (ammo = weapon `ammo_volleys`; rearm = unit `rearm_s_full`) |
| 26 | `spotter` | `radius_cells*`, `artillery_range_bonus_pct=0` | unit | Mirage Observer, Watchpost |
| 27 | `regen` | `rate_pct_per_s*`, `idle_s*`, `cap_pct=100`, `target=self\|passengers`, `source_structure_ids=[]`, `source_radius_cells=0`, `source_powered=false` | unit | granted by research: Section Logistics, Watershed Logistics |
| 28 | `directional_armor` | `front_arc_deg*`, `front_reduction_pct*`, `rear_increase_pct=0` | unit | Marte, Ibex, Bear, Imperial Guard… (bible: "frontal protection") |
| 29 | `relay_field` | `radius_cells*`, `damage_bonus_pct*`, `powered_required=true`, `retain_after_power_loss_s=0`, `requires_deployed=false`, `radius_upgradeable=true`, `stack_group*` | structure, unit | Relay (6 cells, +10 %); Fen via research |
| 30 | `service_pads` | `pads_n*`, `service_rate_pct=100` | structure | Airfield (4) |
| 31 | `refinery` | `free_collector_id*`, `unload_slots_n=1` | structure | Refinery |
| 32 | `aura_regen` | `radius_cells*`, `rate_pct_per_s*`, `cap_pct*`, `idle_s*`, `target_selector*`, `stack_group*` | structure | NAPC Factory apron (trait grant) |
| 33 | `defense_power_reserve` | `reserve_s*`, `recharge_s*`, `continuous_power_s*` | player | SAP trait |
| 34 | `summon_orbit` | `orbit_radius_cells*` | unit (SUMMON) | UAV, drones, patrol aircraft, balloon |

**Template resolution.** A unit's or structure's ability list is built in four steps: (1) **implicit** templates whose `when` matches (`tag:<bible unit tag>`, `family:<archetype family>`, `archetype:<id>`); (2) the sheet's `abilities` entries — a bare framework name is replaced by `aliases[name]`, an `ability.*` id is used as is; (3) an entry whose **kind equals the kind of an earlier entry replaces it** (so an explicit `transport_3` replaces the implicit two-squad transport, an explicit `ability.mode_switch.shinano` replaces nothing); (4) `ability_params[<entry>]` overrides individual template params (validated against the kind's spec, converted by suffix, **every default materialised**). At most one ability per kind per def (`V-ABL-02`). The result is `DefAbility` instances (§4.2) with `template = <template index>` and `slot` = position.

**Framework names → templates (`aliases`).** `unit_assignments[*].abilities` uses 22 names (`global.json → ability_value_pct` lists 26; `detector`, `jammer`, `dual_purpose`, `transport_4` are unused there). The template params are `global.json → ability_templates[<name>].defaults` renamed to registry keys; numbers the bible prose fixes (Charlemagne +25 % range …) are per-unit `ability_params`:

| framework name | template id | kind | template params (file units) and the renames applied to the framework's field names |
|---|---|---|---|
| `deployable_mode` | `ability.deploy.default` | `deploy` | `deploy_s 3`, `pack_s 2` (framework: same names); `weapon_range_pct: 125` → `range_bonus_pct: 25`; `locks_hull` → `immobile`+`turn_locked`; `long_walker_radius_plus` → `command_radius_bonus_cells`. Shinano and Protea replace it with `ability.mode_switch.default` (`switch_s 3`); the acceptable kinds for `V-ABL-05` are `{deploy, mode_switch}` |
| `suppressive_deploy` | `ability.deploy.suppressive` | `deploy` | `deploy_s 3`, deployed slot `suppressive` (Fortress Guard) |
| `camouflage` | `ability.camouflage.default` | `camouflage` | `delay_s 6`, `needs_stationary true`, `needs_no_attack true`; `reveal_hold_s` → `reveal_s`; `while_moving` → `moving_ok` |
| `stealth` | `ability.camouflage.moving` | `camouflage` | `delay_s 6`, `moving_ok true`, `needs_no_attack true` (Condor) |
| `heal_aura` | `ability.heal.default` | `heal` | `pct_max_health_per_s_x100: 200` → `rate_pct_per_s 2`, `radius_cells 4` |
| `repair_aura`, `drone_repair` | `ability.repair.default` | `repair` | `pct_max_health_per_s_x100` → `rate_pct_per_s`; `cost_pct_of_paid_price_per_s_x100` → the economy rule `repair_cost_bp` (a unit that repairs for free sets `cost free`) |
| `command_field` | `ability.command_field.default` | `command_field` | `radius_cells 5`, `damage_pct` → `damage_bonus_pct 10`, `stack_group "command_field"` |
| `aps_interception` | `ability.interceptor.default` | `interceptor` | `cooldown_s 12`, `range_cells 3`; Arjun `cooldown_s 15` |
| `smoke` | `ability.smoke_launcher.default` | `smoke_launcher` | `radius_cells 4`, `duration_s 6`, `cooldown_s 40` |
| `decoy` | `ability.decoy_spawn.default` | `decoy_spawn` | `cooldown_s 40`; `lifetime_s`/`health` live in the zone `zone.decoy_tank` |
| `cover_builder` | `ability.portable_cover.default` | `portable_cover` | `build_s 4`, `lifetime_s 45`, `bullet_resist_pct` → `resist_pct 20`, `pieces_per_builder` → `pieces_per_builder_n` |
| `sensor` | `ability.sensor_puck.default` (Civic) / `ability.sensor_mast.default` (Fen) | `sensor_puck` / `sensor_mast` | puck: `cooldown_s 30`, zone `zone.sensor_puck` (radius 4, 20 s); mast: `reveal_radius_cells 6`, `deploy_s` from the sheet |
| `salvage` | `ability.salvage.default` | `salvage` | `time_s` → `action_s 8`, `payout_pct_of_paid_cost` → `payout_pct 20`, `wreck_lifetime_s` → `wreck_life_s 60` |
| `transport_3` | `ability.transport.squads3` | `transport` | `capacity_squads_n 3` (implicit two-squad and four-squad transports: `ability.transport.squads2` / `squads4`) |
| `shield_front` | `ability.frontal_shield.default` | `frontal_shield` | `arc_deg 180`, `reduction_pct 25`, `resist_groups ["bullet"]` |
| `frontal_armor` | `ability.directional_armor.default` | `directional_armor` | `front_arc_deg 120`, `front_reduction_pct` from the bible prose of the unit (per-unit `ability_params`) |
| `multirole` | `ability.mode_switch.multirole` | `mode_switch` | `switch_s 0`, `switch_at_structure_id "structure.shared.airfield"`, modes `air` (slot 0) / `ground` (slot 1); Shogun overrides `modes` with its wing configurations |
| `spotter` | `ability.spotter.default` | `spotter` | `radius_cells` from `vision_cells` of the sheet (default 12) |
| `jammer` (unused) | `ability.ew_jammer.default` | `ew_jammer` | `radius_cells 5`, `sight_pct: −25` → `sight_penalty_pct 25` |
| `amphibious` | — | — | movement class `amphibious` (+ optional `deep_speed_pct`); **no** `DefAbility` |
| `breach_charge` | — | — | weapon archetype `breach_charge`; **no** `DefAbility` |
| `unmanned` | — | — | unit tag `unmanned` (already a bible tag); **no** `DefAbility` |
| `detector`, `dual_purpose`, `transport_4` (unused) | `ability.detector.default` / — / `ability.transport.squads4` | `detector` / — / `transport` | `dual_purpose` = a weapon with `targets_override ["air","ground"]`, no ability |

**Implicit templates (`implicit`).** `tag:detector` → `ability.detector.default` (radius 5, bible); `family:aircraft` → `ability.sortie.default`; `archetype:veh_scout` → `ability.transport.squads2`; `archetype:veh_assault_carrier` → `ability.transport.squads4`; `archetype:veh_command` → `ability.command_field.default`; `archetype:air_ew` → `ability.ew_jammer.default`; `archetype:ship_carrier` → `ability.carrier.default` (the drone wings are given per unit through `ability_params`: `wings: [{id, drone_id, wing_size_n}]`, `wing_size_n` 6 from `global.json → carriers.drone_count`); `archetype:ship_sub` → `ability.submerge.default` (`surface_s 8`); `archetype:service.engineer` → `ability.repair.engineer`, `ability.capture.default`; `archetype:service.collector` → `ability.harvest.default` (`capacity_credits 600`); `archetype:service.mcv` → `ability.deploy_structure.hq`; `archetype:service.landing_transport` → `ability.transport.landing` (4 squads or 2 vehicles).

`ability_kinds.json` also holds `def_params` — the registry of **def-scope** parameter/flag keys usable by `param_mod`/`set_flag` — e.g. `{"emp_recovery_pct": {"type":"pct","def":100,"scopes":["unit","structure"]}, "command_field_eligible": {"type":"bool","def":false,"scopes":["unit"]}}`; converted defaults live in `DefUnit.params` / `DefStructure.params` (`emp_recovery_bp: 10000`).

Template example and use:
```json
{ "templates": {
    "ability.detector.default":   { "kind": "detector", "params": { "radius_cells": 5 } },
    "ability.deploy.default":     { "kind": "deploy",   "params": { "deploy_s": 3, "pack_s": 2 } },
    "ability.interceptor.default":{ "kind": "interceptor", "params": { "cooldown_s": 12, "charges_n": 1, "range_cells": 3 } } },
  "aliases": { "deployable_mode": "ability.deploy.default", "aps_interception": "ability.interceptor.default" },
  "implicit": [ { "when": "tag:detector", "templates": ["ability.detector.default"] } ] }
```
A unit lists `"abilities": ["deployable_mode"], "ability_params": { "deployable_mode": { "deploy_s": 4, "range_bonus_pct": 25 } }` (Charlemagne). Converted: `DefAbility{kind:3, template: <idx of ability.deploy.default>, slot: 0, params:{command_radius_bonus_u:0, damage_bonus_bp:0, deploy_t:80, deployed_slots_n:[], immobile:true, pack_t:40, range_bonus_bp:2500, turn_locked:false}}` — every default is materialised, keys sorted.

### 7.5 Effect, selector and condition vocabulary (used by research, traits, zones, powers, superweapon side effects)

**Ownership.** Section 7.0 recommends that the abilities domain owns the *spelling* of effects (`effects.json`, `zones.json`, `statuses.json`). What this section fixes regardless of who owns the file is the **field meaning that `DefEffect` must be able to carry** (§4.2) and the spelling used by the data module's fallback files (`research_effects.json`, `power_actions.json`, `zone_templates.json`, `faction_traits.json`). Any adopted alternative spelling must compile to exactly these `DefEffect` fields.

**Selector forms** (`"selector"`): a string id (bible `selector.*` or a balance-owned `selector.balance.*`); an array of ids (union); or an inline object
`{"kinds":["unit"], "tags_all":[…], "tags_any":[…], "tags_none":[…], "unit_ids":[…], "structure_ids":[…], "classes":["baseline","unique","service","drone"], "include_replacements":false, "has_weapon_tags":[…]}`. `has_weapon_tags` (unit/structure kinds) means "owns ≥ 1 weapon slot whose weapon archetype carries any listed derived weapon tag" (`thermal_beam guided_missile direct_fire indirect_fire anti_air anti_ground anti_sub`, §5.9.2) — e.g. Capacitor Discharge targets `{"kinds":["unit","structure"],"has_weapon_tags":["thermal_beam"]}`.
**Named balance selectors** live in a top-level `"selectors": { "selector.balance.<name>": <inline object> }` block of `research_effects.json` (sorted; usable from every file); example: `"selector.balance.infantry_and_land_vehicles": {"kinds":["unit"],"tags_all":["combat"],"tags_any":["infantry","land_vehicle"]}` (the Relay field's target set). Inline selectors compile to `inline.<owner id>#<n>` (§5.4.2).

**Condition forms** (`"cond": [ … ]`, all must hold; each `{"code": "<name>", …}`; code → `Cond` integer of §4.1): `on_water` (21 when used inside an effect, runtime), `in_garrison` (2), `paid_repair` (3; bible selectors only, statically folded, §5.5.5, **not allowed inside an effect**, `V-EFF-01`), `near_friendly_unit {radius_cells*, unit_ids*, include_replacements=false}` (10), `near_friendly_structure {radius_cells*, structure_ids | selector, powered=false}` (11), `target_near_friendly_unit {radius_cells*, unit_ids*, include_replacements=false}` (12), `in_relay_field {powered=true}` (13), `stationary {for_s*}` (14), `out_of_combat {for_s*}` (15), `recently_disembarked {within_s*}` (16), `deployed` (17), `camouflaged` (18), `in_zone {zone_id*}` (19), `structure_powered` (20), `behind_cover` (22). Evaluation belongs to the abilities/combat domains; the data module compiles the code and the converted parameters.

| `op` (`EffectOp`) | fields (file units) | runtime meaning (data view) |
|---|---|---|
| `stat_mod` (1) | `stat*` (bible stat name, or `production_rate` / `rearm_rate`), `delta_pct*` (int), `selector*`, `cond=[]`, `stack_group?`, `duration_s=0` (0 = permanent), `membership="continuous"\|"latched"` | layer-3 percentage on a resolver stat (§5.8) |
| `resist_mod` (2) | `pct*`, `groups=[]` (`bullet explosive beam thermal rail kinetic emp`; `[]` = every weapon group **except** `emp`), `fire_modes=[]` (`direct indirect melee`; `[]` = any), `frontal_arc_deg=0` (0 = all directions; > 0 = only hits arriving inside ± half the arc of the target's facing), `selector*`, `cond=[]`, `stack_group?`, `duration_s=0` | adds `pct` to the target's damage-taken reduction for hits with `type.group_mask & groups ≠ 0`, `1 << fire_mode ∈ fire_modes`, inside the arc; **total capped at 50 %** (TAXONOMY §5) |
| `param_mod` (3) | `scope="ability"\|"def"\|"player"`, `ability?` (kind name), `key*` (file key with unit suffix), exactly one of `set`/`add`/`mul_pct`, `selector` (not for `player`), `filter={}` | changes a converted param after conversion by the key's suffix (`cooldown_s: 9` ⇒ `cooldown_t` 180) |
| `grant_ability` (4) | `ability*` (template id / bare framework name / `{ref,params}` / inline `{kind,params}`), `replace=false`, `selector*` | adds an ability instance (skipped if the kind exists) |
| `set_flag` (5) | `flag*`, `selector*` | boolean def flag (`has_flag`) |
| `immunity` (6) | `kind*` (`suppression`\|`emp`), `selector*`, `duration_s*` | temporary immunity |
| `heal` (7) | `rate_pct_per_s*`, `cost="free"\|"paid"`, `cannot_fire=false`, `ends_on_move=false`, `selector*` | repair/heal field on zone occupants |
| `camouflage` (8) | `max_s*`, `breaks_on=["move","fire","detect"]`, `selector*` | temporary concealment |
| `reveal` (9) | `detect=false` | reveal terrain/units (and detect camouflage when `detect`) |
| `disable` (10) | `what*` (`weapons`\|`structure`), `duration_s*`, `selector*` | EMP-like shutdown; never kills |
| `mark` (11) | `duration_s*`, `damage_bonus_pct*` | marks targets; friendly weapons deal bonus damage to them |
| `spawn_zone` (12) | `zone*`, `at*` (`initial_positions`\|`target`), `duration_s?`, `cluster_radius_cells?` | creates a zone (Broken Contact smoke) |

**Static vs runtime conditions.** In a bible *selector*'s `conditions[]` the codes `on_water` and `paid_repair` are folded statically for the specific stats of §5.5.5. In an *effect's* `cond` list every code is **runtime-evaluated** (including `on_water`, e.g. Sealed Compartments' resistance) and `paid_repair` is not allowed (`V-EFF-01`).

Worked effects (converted result after `⇒`):

* Joint Tactical Links: `{"op":"stat_mod","stat":"weapon_range_cells","delta_pct":10,"selector":{"unit_ids":["unit.napc.sentinel_aa","unit.napc.aegis_frigate"],"include_replacements":true},"cond":[{"code":"near_friendly_unit","radius_cells":6,"unit_ids":["unit.napc.rifle_squad","unit.napc.javelin_team"],"include_replacements":true}],"stack_group":"research.napc.joint_tactical_links"}` ⇒ `DefEffect{op:1, stat:5, delta_bp:1000, selector:<inline idx>, cond_codes:[10], cond_params:[{radius_u:6144, unit_idx:[…], include_replacements:true}], duration_t:0, stack_group:<idx>}`. The effect is *conditional*, so `DefLayer3` exposes it via `cond_effects_of_unit` instead of summing it (§5.8.1).
* Adaptive Plating: `{"op":"resist_mod","pct":10,"groups":["explosive"],"selector":"selector.land_combat_vehicles"}` ⇒ `DefEffect{op:2, delta_bp:1000, group_mask:2, fire_mode_mask:0, frontal_arc_a:0, selector:<idx of selector.land_combat_vehicles>}` (`ap` and `he` both carry group 2; `thermal` 4\|8, `rail` 16, `bullet` 1 do not intersect — "not beam, rail or bullet").
* Dust Screen: `{"op":"resist_mod","pct":30,"fire_modes":["direct"],"selector":{"kinds":["unit"],"tags_all":["ground"]},"stack_group":"smoke"}` ⇒ `DefEffect{op:2, delta_bp:3000, group_mask:0, fire_mode_mask:1, frontal_arc_a:0, …}` (`fire_mode_mask` bit `1 << FireMode`: direct 1, indirect 2, melee 4; `group_mask 0` = all weapon groups except EMP).
* Gate Guard shield: `{"op":"resist_mod","pct":25,"groups":["bullet"],"frontal_arc_deg":180,...}` ⇒ `group_mask:1, frontal_arc_a:2048`.

### 7.6 Weapon instances — the `weapons` list of `units_<code>.json`

Weapons are **instances of the 27 weapon archetypes** (`global.json → weapon_archetypes`, TAXONOMY §10); there are no separate projectile or weapon registries. The instance shape is the balance framework's (FRAMEWORK §4.4). An instance is a value object: it is compiled into one `DefWeaponSlot` **per owner** (deep-copied into every roster clone); its id is a label that lets several units of one faction file share one instance, it has **no def index**, and is unique across all files (`V-SCH-03`). Structure and defense weapons come from `global.json → defenses` in the same shape; a sheet that omits `weapons` inherits the role archetype's `weapons[]` (anonymous instances, slot order preserved).

| key | type | req | file unit | → `DefWeaponSlot` / rule |
|---|---|---|---|---|
| `id` | `weapon.<code>.<name>` | req | | label; sorted list (`V-SCH-09`) |
| `archetype` | key of `weapon_archetypes` | req | | `arch`; **locks** `dtype`, `fire_mode`, `proj_kind`, `interceptable`, `homing`, `proj_speed` (`V-CNF-08`) |
| `damage` | int | req | hp per hit, before modifiers | `damage` (≥ 1; framework lint: ≥ 25 unless documented) |
| `hits_per_volley` | int | opt 1 | | `hits_per_volley` (DPS = damage·hits/reload) |
| `reload_s` | num | req (`emp_pulse`: 0) | s, ≤ 3 decimals, inside the archetype band ±10 % | `reload_mt = ms·TPS` (exact), `reload_ticks = ceil_div(reload_mt, 1000)` |
| `range_cells` | num | req | cells | `range` (max); inside band ±10 % (`V-RNG-02`) |
| `min_range_cells` | num | opt (archetype) | cells | `min_range` |
| `splash_cells`, `scatter_cells` | num | opt (archetype; override ±30 %) | cells | `splash_radius`, `scatter` |
| `splash_edge_pct` | pct | opt (archetype) | % of damage at the splash edge | `splash_edge_bp` |
| `targets_override` | [layer] | opt null | `ground air surface_water underwater` | `target_mask` (only the documented cases: laser AA `["air"]`, dual-purpose flak `["air","ground"]`) |
| `turret_deg_s` | num | opt (archetype) | °/s | `turret_turn` (apt) |
| `arc_deg` | num | opt 360 | ° (full width of the firing arc) | `fire_arc` (a) |
| `suppressive` | bool | opt (archetype) | | `WF_SUPPRESSIVE` |
| `flags` | [enum] | opt | `stationary_fire needs_los point_defense` | `WF_STATIONARY_FIRE`, `WF_NEEDS_LOS`, `WF_POINT_DEFENSE` |
| `deploy_s` | num | opt 0 | s | `deploy_t` (informational; the `deploy` ability enforces it) |
| `ammo_volleys` | int | opt 0 (∞) | volleys per sortie | `ammo_volleys` |
| `ramp_seconds`, `ramp_max_pct` | num, pct | opt 0 / 100 | s, % | `ramp_t`, `ramp_max_bp` (beams only) |
| `requires_surface_s` | num | opt 0 | s | `requires_surface_t` (submarine cruise missile) |
| `mount` | `hull`\|`turret` | opt (`turret` iff `turret_deg_s > 0` and the owner is neither infantry nor aircraft) | | `mount` |
| `modes` | [int] | opt `[]` = always | mode numbers (§4.2 `mode_mask`) | `mode_mask` |
| `notes` | str | opt | | ignored |

Derived at load: `WF_HOMING` from the archetype, `target_mask` from `archetype.targets`, weapon tags from the archetype (§5.9.2). Bible `damage` / `weapon_range_cells` (null today) would bind slot 0 (§5.2.4).

```json
{ "id": "weapon.napc.guardian_cannon", "archetype": "tank_cannon", "damage": 141, "hits_per_volley": 1, "reload_s": 1.2, "range_cells": 7.0 },
{ "id": "weapon.olm.sunlance_beam", "archetype": "beam_thermal", "damage": 50, "reload_s": 0.25, "range_cells": 9.0, "ramp_seconds": 5.0, "ramp_max_pct": 150 }
```
Converted (`Guardian`, the `proposals --styled --faction napc` number 141): `DefWeaponSlot{arch:3, slot:0, mount:1, mode_mask:0, damage:141, hits_per_volley:1, dtype:1, fire_mode:0, interceptable:0, proj_kind:1, range:7168, min_range:0, reload_mt:24000, reload_ticks:24, proj_speed:819, homing:true, splash_radius:512, splash_edge_bp:5000, scatter:0, target_mask:5, flags:16, ammo_volleys:0, turret_turn:51, fire_arc:4096, ramp_t:0, ramp_max_bp:10000}` (`16 c/s → rdiv(16000·1024, 1000·20) = 819`; `0.5 cells → 512`; `90°/s → rdiv(90000·4096, 360000·20) = 51`; `360° → 4096`). Sunlance: `reload_mt = 5000`, `reload_ticks = 5`, `ramp_t = 100`, `ramp_max_bp = 15000`, `proj_speed = 0` (beam: hitscan), `dps_x100 = 20000` (200 DPS base, ramping to 300).

### 7.7 `units_<code>.json` — unit sheets, weapons, summons and drones

`{"schema":"meridian.balance.units/1","faction":"faction.napc"|null,"units":[…],"weapons":[…],"summons":[…]}`. `<code>` ∈ `ae def han napc nec olm pd sap shared`; `units_shared.json` has `"faction": null` and the 4 service units (plus shared summons). Every bible unit of that faction appears **exactly once** in `units` (`V-CMP-01`). The framework's `<faction>.json` (FRAMEWORK §7.3) is this file. All three lists are sorted by `id`. The sheet keys are FRAMEWORK §4.5 verbatim plus the few keys the game needs:

| key | type | req | file unit | → `DefUnit` / rule |
|---|---|---|---|---|
| `id` | `unit.<code>.<name>` | req | | identity (must be a bible unit id of this file's faction) |
| `archetype` | key of `archetypes` or `service.<name>` | req | | defaults; **must equal** `unit_assignments[id].archetype` (`V-ABL-05`) |
| `tier` | int 1-3 | opt | | must equal the bible tier (`V-CNF-01`; kept because FRAMEWORK carries tier overrides, e.g. Narwhal/Shinano T2) |
| `size_class`, `armor_class`, `movement_class`, `layer` | str | opt (archetype) | vocabulary ids | `size_class`, `armor_class`, `move_class`, `home_layer` / `layer_mask` |
| `cost_credits` | int | req* (bible non-null only for the 4 service units) | credits | `cost` |
| `build_time_s` | num | req | s | `build_ticks = ceil_div(ms·20, 1000)` |
| `health` | int | req | hp | `health` |
| `speed_cells_s` | num | req unless `static` | cells/s | `speed` (upt) |
| `vision_cells`, `radius_cells` | num | req | cells | `sight`, `radius` |
| `turn_deg_s` | num | opt (`size_classes`) | °/s | `turn_rate` (apt) |
| `accel_ticks` | int | opt (`movement_defaults.accel_ticks[size]`) | ticks | `accel_t` |
| `deep_speed_pct` | pct \| null | opt null | % of land speed on `DEEP` | `deep_speed_bp` (Tide Tank 60) |
| `rearm_s_full` | num | req for aircraft (archetype) | s | `rearm_t` (stat 7 target) |
| `pop_n` | int | opt 1 (Collector, MCV, summons, drones: 0) | | `pop` |
| `weapons` | [weapon id] | opt (archetype's weapons) | ids of the `weapons` list | `weapons[]` slots; slot number = list position |
| `abilities` | [str] | opt (= `unit_assignments[id].abilities`) | bare framework names **or** `ability.*` template ids (§7.4) | `abilities[]` (implicit ones added, §7.4) |
| `ability_params` | {key: {param: value}} | opt | param keys and units of the registry (§7.4), keyed by an entry of `abilities` | overrides the template's params before conversion |
| `tags` | [style tag] | opt (= `unit_assignments[id].tags`) | keys of `global.json → style_tags` | documentation for the fair-cost lint; **not** `DefBase.tags` |
| `tags_add` | [unit tag] | opt | free unit tags for AI/UI (never a locked tag, `V-CNF-03`) | `tags` |
| `flags` | [enum] | opt | `fire_stationary hover_fire no_combat_mods no_command_buff no_repair no_capture no_salvage non_blocking harmless` | `flags` |
| `dps_vs_primary`, `range_cells` | num | opt | derived helpers of the framework (`balance_calc.py check`) | ignored by the loader; `validate_balance.py` recomputes them and warns above 1 % deviation |
| `pres` | {`recipe`, `icon`, `snd_profile`, `ai_role`, `scale_pct`} | opt | ids / hints | `pres_*` (defaults: recipe and icon = the def id) |
| `params` | {} | opt | suffix-typed keys (§5.10.1) | `params` (converted, sorted) — the extension point for domain-specific unit numbers |
| `notes` | str | opt | | ignored |

**Fallback order** for every numeric key the sheet omits: role archetype (unstyled numbers) → `service_units` row → `size_classes` / `movement_defaults`. The loader never applies `style_tags`, `faction_styles` or `modifier_compensation`: they are design-time inputs of `balance_calc.py proposals --styled`, whose output the balance authors paste into the sheets; a sheet's numbers are the runtime truth. If the abilities domain supplies `abilities.json → slots` (source map, §7.0), sheets omit `abilities` / `ability_params` (setting both with different content is `V-CNF-09`).

`summons` entries (power / superweapon summons and carrier drones; ids `summon.<code>.<name>`) use the same keys plus **`class`** (`summon`\|`drone`, req) and **`unit_tags`** = the complete unit-tag list (req; bible tags do not exist for them; `V-ROLE-05`; the style-tag key `tags` is not used); `lifetime_s` (num, opt 0 = permanent → `lifetime_t`). There is no `archetype` for them: `size_class armor_class movement_class layer health speed_cells_s vision_cells radius_cells` are all required. For `drone` the fields `cost_credits` / `build_time_s` are the **replacement** cost and time.

```json
{ "schema": "meridian.balance.units/1", "faction": "faction.napc",
  "units": [
    { "id": "unit.napc.beaver_amphibious_apc", "archetype": "veh_scout", "tier": 1,
      "cost_credits": 485, "build_time_s": 15.5, "health": 602, "speed_cells_s": 3.2, "vision_cells": 12.0, "radius_cells": 0.45,
      "weapons": ["weapon.napc.beaver_mg"], "abilities": ["amphibious"],
      "tags": ["weak_gun", "sturdy"], "dps_vs_primary": 18.1, "range_cells": 6.0 },
    { "id": "unit.napc.guardian_tank", "archetype": "mbt_t1", "tier": 1,
      "cost_credits": 850, "build_time_s": 27.5, "health": 907, "speed_cells_s": 2.0, "vision_cells": 9.0, "radius_cells": 0.55,
      "weapons": ["weapon.napc.guardian_cannon"], "abilities": [], "tags": [], "dps_vs_primary": 117.5, "range_cells": 7.0 },
    { "id": "unit.napc.raptor_multirole_fighter", "archetype": "air_fighter", "tier": 2,
      "cost_credits": 1050, "build_time_s": 29.0, "health": 705, "speed_cells_s": 7.0, "vision_cells": 11.0, "radius_cells": 0.5, "rearm_s_full": 8,
      "weapons": ["weapon.napc.raptor_aam", "weapon.napc.raptor_agm"], "abilities": ["multirole"], "tags": ["weaker_gun"] } ],
  "weapons": [
    { "id": "weapon.napc.beaver_mg", "archetype": "machine_gun", "damage": 9, "hits_per_volley": 2, "reload_s": 1.0, "range_cells": 6.0 },
    { "id": "weapon.napc.guardian_cannon", "archetype": "tank_cannon", "damage": 141, "hits_per_volley": 1, "reload_s": 1.2, "range_cells": 7.0 },
    { "id": "weapon.napc.raptor_aam", "archetype": "aa_missile", "damage": 86, "reload_s": 1.0, "range_cells": 8.0, "ammo_volleys": 6, "modes": [0] },
    { "id": "weapon.napc.raptor_agm", "archetype": "air_missile", "damage": 70, "reload_s": 1.5, "range_cells": 6.0, "ammo_volleys": 4, "modes": [1] } ],
  "summons": [
    { "id": "summon.napc.uav", "class": "summon", "unit_tags": ["aircraft", "summoned"], "size_class": "air_medium", "armor_class": "air_light",
      "movement_class": "air_hover", "layer": "air", "health": 60, "speed_cells_s": 6.0, "vision_cells": 7.0, "radius_cells": 0.5, "lifetime_s": 12,
      "pop_n": 0, "flags": ["no_combat_mods", "harmless"], "abilities": ["ability.summon_orbit.default", "detector"],
      "ability_params": { "ability.summon_orbit.default": { "orbit_radius_cells": 7 }, "detector": { "radius_cells": 7 } } } ] }
```
(The Beaver/Guardian/Raptor bodies are the framework's styled proposals; the Raptor's second weapon and the UAV numbers are **example values** for the schema — final numbers belong to the NAPC balance author.)

Converted results (checked by `test_data_units`): **Guardian** — `cost 850, build_ticks 550, health 907, speed 102 (2.0 c/s → 102.4), sight 9216, radius 563 (0.55·1024 = 563.2), turn_rate 85 (medium 150°/s), accel_t 6, size_class 2, armor_class 2, move_class 2 (TRACKED), pop 1, weapons[0].damage 141`. **Beaver** — `cost 485, build_ticks 310, health 602, speed 164 (3.2 c/s = 163.84), move_class 3 (AMPHIBIOUS), size_class 1, armor_class 1, abilities [DETECTOR{radius_u 5120} (implicit: bible tag detector), TRANSPORT{capacity_squads_n 2, …} (implicit: archetype veh_scout)]` — the framework name `amphibious` produces **no** `DefAbility`: it is the movement class plus the class' `DEEP` multiplier (70 %, no per-unit override); Sealed Compartments (`resist_mod … cond on_water`) and Canada's `+20 % on water` (`water_mult_bp`) sit on top. **Raptor** — `rearm_t 160`, `weapons[0].mode_mask 1`, `weapons[1].mode_mask 2` (mode 0 → bit 0, mode 1 → bit 1), ability `mode_switch` from the `multirole` template.

### 7.8 `structures.json` — structure overlay (abilities, flags, exits, masks)

`{"schema":"meridian.balance.structures/1","structures":[…]}` — a list of `{id, …}` entries sorted by id, one for each bible structure that needs anything **beyond** the numbers of `global.json → structures / defenses / superweapons.common` (§7.3). Those blocks give cost, build time, power, health, armor class, footprint, radius and sight; the bible gives tags, prerequisites, `deployment_unit_id`, `can_start_deployed` and placement conditions. The overlay therefore never repeats a number: repeating one is `V-CNF-09` unless equal (INFO), setting a different one is an error.

| key | type | req | file unit | → `DefStructure` |
|---|---|---|---|---|
| `id` | `structure.<code>.<name>` | req | | identity |
| `exit` | {`dx`,`dy`} | opt (0, `fp_h`) | cells | `exit_dx`, `exit_dy` |
| `footprint_mask` | [str] | opt | rows of `X` (blocked) / `.` (free), `fp_h` rows of `fp_w` chars | `fp_mask` |
| `queues_n` | int | opt 1 | | `queues` |
| `flags` | [enum] | opt | `powered_defense sellable repairable capture_immune relay production` (adds to the derived set) | `flags` |
| `sell_pct`, `repair_rate_pct` | pct | opt (economy) | % | `sell_bp`, `repair_rate_bp` |
| `abilities`, `ability_params`, `tags_add`, `pres`, `notes` | as units | opt | | as units |
| `params` | {} | opt | suffix-typed keys (§5.10.1) | `params` — the extension point for domain-specific structure numbers (the economy spec's `apron`, `berth`, `dock`, `power_class`, `repair_basis_cost`, `sell_locked_during_warning` fit here as `apron_cells`, `berth_cells`, …) |

Derived without an overlay entry: abilities from the `global.json` structure block — `DETECTOR` when the block has `detector_radius_cells` (Watchtower 4, AA Battery 5), `SERVICE_PADS{pads_n}` from `pads` (Airfield 4), `REFINERY{free_collector_id: unit.shared.collector, unload_slots_n}` for the Refinery block, and `DefStructure.deploy_t` from `deploy_s` (HQ, 3 s); extra structure tags `anti_air`, `anti_ground`, `anti_sub` (free tags, added when any weapon slot's archetype carries the matching derived weapon tag, so `DefQuery.cheapest_structure_with(roster, ST_DEFENSE | structure_bit("anti_air"))` needs no hand-written `tags_add`); `queue_kind` from the producer relation (units whose `producer_structure_id` is this structure and whose archetype `producer` is `barracks`→INFANTRY, `factory`→VEHICLE, `airfield`→AIRCRAFT, `dock`→NAVAL, `refinery`→COLLECTOR); `SF_POWERED_DEFENSE` for tag `defense`; `SF_STRATEGIC` for tag `superweapon`; `SF_RELAY` for tag `relay`; `SF_PRODUCTION` for every structure that is a `producer_structure_id`; `SF_CAPTURE_IMMUNE` for production, strategic structures and the HQ; `SF_SELLABLE` / `SF_REPAIRABLE` unless it is the HQ (bible: the HQ is the construction anchor); `SF_NO_BUILD` for `build_time_seconds == null && cost == 0` (HQ); `build_radius` = `economy.build_radius_cells` for the HQ; placement flags from the bible `conditions[]` (§5.9.1). Bible-derived and **not** settable here: cost, power, prerequisites, tags, `deployment_unit_id`, `can_start_deployed`, `max_per_player`.

```json
{ "schema": "meridian.balance.structures/1",
  "structures": [
    { "id": "structure.nec.relay", "flags": ["repairable", "sellable"],
      "abilities": ["ability.relay_field.default"], "ability_params": { "ability.relay_field.default": { "radius_cells": 6, "damage_bonus_pct": 10, "stack_group": "relay_field" } } },
    { "id": "structure.shared.refinery", "exit": { "dx": 0, "dy": 2 } },
    { "id": "structure.shared.airfield", "footprint_mask": ["XXXX", "XXXX", "XXXX"], "exit": { "dx": 0, "dy": 3 } } ] }
```
Converted (`Relay`, numbers from `global.json → structures.relay`): `cost 600, build_ticks 300 (15 s, ours), power −20, health 900, armor_class 8, fp 1×1, radius 512, sight 8192, flags SF_RELAY|SF_REPAIRABLE|SF_SELLABLE, abilities [RELAY_FIELD{radius_u 6144, damage_bonus_bp 1000, powered_required true, retain_after_power_loss_t 0, radius_upgradeable true, stack_group <idx of "relay_field">}], place_mask PLACE_NO_RADIUS_EXTENSION (4)` (no `SF_PRODUCTION`: no unit names the Relay as producer). (The Relay's radius 6 / +10 % come from the bible prose and are checked by the prose cross-check; the Watchtower's detector radius 4 comes from `global.json → structures.watchtower.detector_radius_cells`, equal to `detection.watchtower_cells`.)

### 7.9 `research_effects.json` — the 40 research upgrades

`{"schema":"meridian.balance.research_effects/1","selectors":{"selector.balance.<name>":{…}},"research":{"research.…":{"bible_numbers":[…],"effects":[…],"designer_params":[…]?,"may_be_empty_in":[roster ids]?}}}` (**fallback schema**, §7.0: the abilities domain's `effects.json` replaces it if adopted; the coverage table below is the completeness checklist either way). Cost, tier, time, prerequisites, faction and inheritance are **bible-only** (`V-CNF-04`). Each entry has ≥ 1 effect (`V-CMP-03`). Coverage of all 40 (ops from §7.5; "+repl" = `include_replacements`; every numeric value is the bible's):

| research | effects (op → params) | targets / conditions |
|---|---|---|
| `napc.adaptive_plating` | `resist_mod` groups `explosive` 10 % ("not beam, rail or bullet") | selector `land_combat_vehicles` |
| `napc.joint_tactical_links` | `stat_mod` weapon_range_cells +10 % | units Sentinel AA, Aegis Frigate (+repl); cond `near_friendly_unit` 6 cells [Rifle Squad, Javelin Team +repl] |
| `napc.dispersed_runways` | `param_mod` ability `service_pads.pads_n` add 2 | structure Airfield (service rate unchanged) |
| `napc.sealed_compartments` | `resist_mod` groups `explosive` 15 % | units Beaver, Narwhal; cond `on_water` (runtime, code 21) |
| `napc.section_logistics` | `grant_ability` `regen` rate 1 %/s, idle 6 s, source Barracks powered (radius = designer param) | selector `combat_infantry` |
| `nec.sensor_fusion` | `param_mod` `detector.radius_cells` add 2 | Surveyor APC, Rapier AA, Horizon Escort (+repl → Fen) |
| `nec.distributed_control` | `param_mod` `relay_field.radius_cells` set 8; `relay_field.retain_after_power_loss_s` set 10 | structure Relay |
| `nec.dispersed_links` | `grant_ability` `relay_field` radius 4, `powered_required:false`, `requires_deployed:true`, `radius_upgradeable:false`, group `relay_field` | unit Fen Recon Carrier |
| `nec.shared_fire_solutions` | `stat_mod` reload −10 % | Marte, Charlemagne; cond `in_relay_field` powered |
| `nec.tunnel_workshops` | `param_mod` `repair.rate_pct_per_s` mul_pct 125, filter `target_structure_tags:[defense]` | Engineer, Alpine Pioneer |
| `olm.thermal_shrouds` | `stat_mod` sight_cells +10 %; `resist_mod` groups `thermal` 10 % (thermal-beam) | selector `light_land_vehicles` |
| `olm.optical_mesh` | `grant_ability` `camouflage` delay 6 s, stationary, no attack | Caravan APC (+repl; Dune Rover keeps its own) |
| `olm.thermal_reservoirs` | `stat_mod` reload −10 % | Ifrit Prism Tank, Dawn Laser AA (not Helios) |
| `olm.distributed_fuel_caches` | `stat_mod` movement_speed +10 % | Dune Rover, Scorpion; cond `out_of_combat` 6 s (firing/damage ends it) |
| `olm.harbor_militia` | `stat_mod` weapon_damage +10 % | Gate Guard; cond `near_friendly_structure` 6 cells [Factory, Dock], group per unit (no stacking between buildings) |
| `def.standardized_parts` | `stat_mod` repair_credit_cost_per_health −15 % | selector `land_vehicle_repairs` (anywhere) |
| `def.coordinated_barrages` | `stat_mod` reload −10 % | Anvil, Colossus (+repl); cond `stationary` 4 s |
| `def.layered_protection` | `param_mod` `interceptor.cooldown_s` set 9; `grant_ability` `ability.interceptor.ural` cooldown 9 | Ural; Bear |
| `def.mobile_dispatch` | `stat_mod` sight_cells +15 %; `param_mod` `deploy.pack_s` set 0 | Steppe Recon Carrier, Saker |
| `def.buried_command_lines` | `param_mod` scope def `emp_recovery_pct` mul_pct 75 | structure Radar ∪ `defensive_structures` |
| `pd.expeditionary_maintenance` | `param_mod` `repair.rate_pct_per_s` mul_pct 125 | Reef Technician |
| `pd.integrated_flight_decks` | `stat_mod` rearm_time_seconds −15 %; `param_mod` `carrier.replace_s` mul_pct 85 | selector `aircraft`; Tempest Carrier (+repl → Shogun) |
| `pd.forward_fire_control` | `stat_mod` reload −10 % | Outrider; cond `target_near_friendly_unit` 6 cells [Wedge Recon Fighter] |
| `pd.distributed_beachheads` | `stat_mod` movement_speed +15 %; `param_mod` `repair.can_repair_transport_riding` set 1 | Reef Technician |
| `pd.predictive_maintenance` | `param_mod` `mode_switch.switch_s` set 2; `carrier.replace_s` mul_pct 80 | Shinano; Shogun |
| `han.resilient_mesh` | `param_mod` scope def `emp_recovery_pct` mul_pct 75 | selector `unmanned_combat_units` |
| `han.distributed_cognition` | `param_mod` `command_field.radius_cells` set 7 | Link Operator, Dragon, Mekong, Long Walker (+repl) |
| `han.guard_integration` | `set_flag` `command_field_eligible` | Imperial Guard Tank |
| `han.hidden_relays` | `grant_ability` `camouflage` delay 6 s, stationary, no attack, `keeps_abilities_active:true` | Link Operator |
| `han.modular_servicing` | `param_mod` `repair.rate_pct_per_s` mul_pct 150 | Lotus Drone Tender |
| `ae.recovery_winches` | `param_mod` `salvage.action_s` set 5 | Reclaimer, River Warden, Engineer |
| `ae.circular_armor` | `stat_mod` health +10 % (HP rescale, §5.8.4) | selector `land_combat_vehicles` |
| `ae.municipal_reserves` | `stat_mod` health +10 % | Civic Rifle Team; cond `near_friendly_structure` 6 cells [Barracks, Refinery], no stacking |
| `ae.watershed_logistics` | `grant_ability` `regen` target `passengers` rate 1 %/s, idle 6 s | Okapi (free healing does not repair the carrier) |
| `ae.precision_machining` | `stat_mod` reload −10 % (all firing modes) | Rhino, Protea |
| `sap.layered_fieldworks` | `resist_mod` groups `explosive` 10 % | selector `combat_infantry`; cond `near_friendly_structure` 4 cells `defensive_structures`, stack group `layered_fieldworks` (overlaps do not stack) |
| `sap.reserve_capacitors` | `param_mod` scope player, ability `defense_power_reserve.reserve_s` set 35 | player |
| `sap.integrated_protection` | `param_mod` `interceptor.cooldown_s` set 10; `grant_ability` `ability.interceptor.arjun` cooldown 10 | Arjun; Gaj |
| `sap.rapid_ferry_drills` | `param_mod` `transport.load_s` and `unload_s` mul_pct 60 (does not change passenger attack speed) | Naga |
| `sap.observer_network` | `stat_mod` reload −10 % | Shaheen; cond `target_near_friendly_unit` 6 cells [Watchpost Recon Team] |

Worked entry:
```json
"research.sap.integrated_protection": {
  "bible_numbers": [15, 10],
  "effects": [
    { "op": "param_mod", "scope": "ability", "ability": "interceptor", "key": "cooldown_s", "set": 10,
      "selector": { "unit_ids": ["unit.sap.arjun_assault_tank"] } },
    { "op": "grant_ability", "ability": { "ref": "ability.interceptor.arjun", "params": { "cooldown_s": 10 } },
      "selector": { "unit_ids": ["unit.sap.gaj_siege_platform"] } } ] }
```
`bible_numbers` acknowledges the prose "falls from 15 to 10 seconds; Gaj gains one interceptor with the same cooldown" (15 is the base already in `ability.interceptor.arjun`). Both effects are unconditional param changes ⇒ `DefLayer3.ability_param(arjun, INTERCEPTOR, "cooldown_t", 300)` returns `200` after completion; `granted_abilities(gaj)` returns the interceptor.

### 7.10 `power_actions.json` — the 48 support powers (fallback schema; economy's `powers.json` replaces it if adopted, §7.0)

`{"schema":"meridian.balance.power_actions/1","powers":{"power.…":{"bible_numbers":[…],"target":{…},"warning_s"?,"actions":[…]}}}`. Cost, tier, cooldown, prerequisites, `requires_powered_prerequisites` are bible-only.

| field | type | meaning |
|---|---|---|
| `target` | {`mode`: `none\|point\|line\|own_structure`, `vision`: `any\|explored\|current`, `radius_cells`?, `length_cells`?, `width_cells`?} | rule.combat.targeting_and_warnings: recon powers `any`; "scouted" decoys `explored`; everything else `current` |
| `warning_s` | num | visible warning before effect (strikes, Wideband Scan) |
| `actions` | [ action ] | ≥ 1; executed in order at activation (+ `delay_s`) |

Actions: `{"op":"zone","zone":"zone.x" | "inline":{DefZone fields},"radius_cells"?,"length_cells"?,"width_cells"?,"duration_s"?}` (inline zones get id `zone.<power id without "power.">`); `{"op":"summon","summon_id","count_n"=1,"at"="target","lifetime_s"?}`; `{"op":"strike","damage_ref":"<key of global.json → support_power_damage>" | "impacts":[{"damage","damage_type","radius_cells","edge_pct"=100,"delay_s"=0,"offset_cells":[dx,dy]?}],"shells_n"?,"waves_n"?,"duration_s"?,"pattern"="random_in_radius"|"fixed"}` (the three bible strike powers use `damage_ref`; the shell numbers are the balance framework's — `counterbattery_mission`: 6 shells over 4 s, `artillery_shell` 320 hp, splash 1.6 cells, edge 30 %; `tremor_barrage`: 4 waves × 6 shells over 8 s, 260 hp; `counterlaunch_plot`: 3 shells per mark, gap 0.6 s, ≤ 6 marks, 260 hp; compile rule: `count = shells`, one prototype `DefImpactPacket`, shell *k* of *n* lands at `delay_t = k·duration_t / n` (truncating) and its position is drawn by the power system with `SimRng`); `{"op":"mark","find_radius_cells","lookback_s","mark_s","damage_bonus_pct"?,"then_strike"?}`; `{"op":"global_effect","duration_s","effects":[…]}`.

| power | target (vision) | actions |
|---|---|---|
| `napc.uav_sweep` | point (any) | summon `summon.napc.uav` (orbit 7 cells: sight+detect 7), lifetime 12 s |
| `napc.field_repair_drop` | point (current) | summon cargo aircraft; zone `zone.repair_station` r5, 10 s, heal 2 %/s free, land vehicles, group `repair_station` |
| `napc.combined_arms_window` | point r6 (current) | zone r6, 15 s: `stat_mod` weapon_damage +10 % on `combat_infantry ∪ land_combat_vehicles ∪ aircraft` (ships, structures excluded; adds with Relay, same layer 3) |
| `napc.rapid_turnaround` | own_structure Airfield (current) | global_effect 20 s: `stat_mod` rearm_rate +50 % on the chosen structure |
| `napc.floating_workshop` | point (current) | zone `zone.repair_station` r5, 20 s, 1.5 %/s, vehicles + ships, placeable on water |
| `napc.coordinated_advance` | point r6 (current) | zone 12 s: `stat_mod` movement_speed +25 % infantry; `immunity` suppression; clears existing suppression |
| `nec.survey_drone` | point (any) | summon drone 15 s (sight/detect 6) |
| `nec.counterbattery_mission` | point r4 (current) | `warning_s` 5; strike `damage_ref counterbattery_mission` (6 shells over 4 s, r4) |
| `nec.treaty_coordination` | none | global_effect 20 s: `param_mod` `relay_field.damage_bonus_pct` set 15 (group `relay_field` ⇒ replaces 10) |
| `nec.silent_watch` | point r6 (current) | zone up to 15 s: `camouflage` stationary ground units; breaks on move/fire/detect |
| `nec.armored_overwatch` | point r6 (current) | zone 15 s: `stat_mod` weapon_range_cells +10 % `tanks`, cond `stationary` (moving removes it) |
| `nec.emergency_earthworks` | point r5 (current) | zone 15 s: `resist_mod` groups `explosive` 20 % on `combat_infantry ∪ defensive_structures` (not vehicles) |
| `olm.dust_screen` | point r6 (current) | zone `zone.smoke_dust_screen` r6, 12 s |
| `olm.mobile_workshop` | point (current) | zone REPAIR r5, 15 s, 2 %/s, land vehicles, destructible (hp) |
| `olm.open_corridor` | point r6 (current) | zone 12 s, `membership: latched`: `stat_mod` movement_speed +25 % `land_combat_vehicles` |
| `olm.capacitor_discharge` | point r6 (current) | zone 10 s: `stat_mod` weapon_damage +20 % on selector `{kinds:[unit,structure], has_weapon_tags:[thermal_beam]}`; then `disable` weapons 4 s |
| `olm.false_convoy` | point (explored) | zone DECOY ×4 light vehicles, 25 s, hp 1, no damage/collision/capture |
| `olm.straits_crossfire` | point r6 (current) | zone 15 s: `stat_mod` weapon_range_cells +10 %, sight_cells +20 % on `combat_infantry ∪ ships` |
| `def.mobilization_order` | none | global_effect 20 s: `stat_mod` production_rate +25 % on Barracks, Factory |
| `def.tremor_barrage` | point r5 (current) | `warning_s` 6; strike `damage_ref tremor_barrage` (4 waves × 6 shells over 8 s, r5) |
| `def.redundant_orders` | point r6 (current) | zone 10 s: `immunity` emp on friendly land vehicles |
| `def.steel_advance` | point r6 (current) | zone 12 s: `resist_mod` (default groups) 20 % + `stat_mod` movement_speed −20 % on land vehicles |
| `def.transit_priority` | point r7 (current) | zone 15 s: `stat_mod` movement_speed +35 % on Collectors, ground transports |
| `def.false_front` | point r6 (explored) | zone DECOY Radar 30 s + 3 decoy tanks |
| `pd.maritime_patrol` | line 20×6 (any) | summon patrol aircraft 12 s: reveal + detect corridor, land and water |
| `pd.expeditionary_workshop` | point (current) | summon aircraft; zone REPAIR 20 s r5, 1.5 %/s, vehicles + ships, land or water |
| `pd.joint_landing` | none | global_effect 15 s: `resist_mod` (default groups) 20 % for 6 s on units that disembark (cond `recently_disembarked` within 6 s; reboarding cannot refresh) |
| `pd.long_watch` | point r7 (any) | zone REVEAL 18 s, `detect:false` |
| `pd.feint_landing` | point (explored) | zone DECOY ×3 transports 25 s (land or water) |
| `pd.precision_window` | point r6 (current) | zone 10 s: `stat_mod` weapon_damage +20 % on `aircraft ∪ ships` |
| `han.wideband_scan` | point r7 (any) | `warning_s` 2; zone REVEAL `detect:true` 6 s |
| `han.software_surge` | point r6 (current) | zone 12 s: `stat_mod` reload −25 % `unmanned_combat_units`; then `disable` weapons 3 s (SUMMON excluded by class) |
| `han.reserve_bandwidth` | none | global_effect 20 s: `param_mod` `command_field.radius_cells` add 3 (damage stays +10 %) |
| `han.central_priority` | none | global_effect 15 s: `param_mod` `command_field.damage_bonus_pct` set 20 |
| `han.broken_contact` | point r6 (current) | zone 10 s: `stat_mod` movement_speed +20 % `ground_combat_units`; `spawn_zone` smoke 6 s at initial positions |
| `han.repair_swarm` | point r5 (current) | zone 10 s: `heal` 2 %/s free on unmanned land units + structures |
| `ae.survey_network` | point r7 (any) | zone REVEAL 12 s, `detect:false`, highlights salvageable wrecks |
| `ae.field_refurbishment` | point r6 (current) | zone 10 s: `heal` 3 %/s land vehicles, `cannot_fire`, `ends_on_move` |
| `ae.recovery_priority` | none | global_effect 20 s: `stat_mod` movement_speed +25 % Engineer, Reclaimer; `param_mod` `salvage.action_s` set 3 (payout unchanged) |
| `ae.civil_defense_net` | point r6 (current) | zone 15 s: `stat_mod` sight_cells +25 % `combat_infantry`; `immunity` suppression |
| `ae.concealed_crossing` | line 16×4 (current) | zone `zone.smoke_dust_screen` shape line 16×4, 12 s, land or water |
| `ae.counterbattery_solution` | point r9 (any) | mark: find r9, lookback 8 s (reveal), mark 12 s, +15 % damage from friendly ground weapons |
| `sap.recon_balloon` | point (any) | summon tethered balloon 20 s (sight/detect 6) |
| `sap.emergency_fortification` | point r6 (current) | zone 15 s: `resist_mod` (default groups = all except `emp`) 25 % on defenses + production structures (not the superweapon) |
| `sap.protected_advance` | point r6 (current) | zone 12 s: `resist_mod` (default groups) 15 % on `combat_infantry ∪ land_combat_vehicles` |
| `sap.assault_coordination` | point r6 (current) | zone 12 s: `stat_mod` reload −15 %, sight_cells +15 % on `tanks` |
| `sap.mobile_reserve` | point r7 (current) | zone 15 s: `stat_mod` movement_speed +30 % ground transports; `param_mod` `transport.unload_moving_speed_pct` set 50 |
| `sap.counterlaunch_plot` | point r8 (current) | mark enemy artillery that fired within 8 s in r8; `warning_s` 5; strike `damage_ref counterlaunch_plot` at the **marked positions** |

Worked entries:
```json
"power.olm.dust_screen": { "bible_numbers": [6, 12, 30],
  "target": { "mode": "point", "vision": "current", "radius_cells": 6 },
  "actions": [ { "op": "zone", "zone": "zone.smoke_dust_screen", "radius_cells": 6, "duration_s": 12 } ] },
"power.nec.counterbattery_mission": { "bible_numbers": [5, 4, 6], "warning_s": 5,
  "target": { "mode": "point", "vision": "current", "radius_cells": 4 },
  "actions": [ { "op": "strike", "pattern": "random_in_radius",
                 "damage_ref": "counterbattery_mission" } ] },
"power.han.central_priority": { "bible_numbers": [15, 20],
  "target": { "mode": "none", "vision": "current" },
  "actions": [ { "op": "global_effect", "duration_s": 15,
                 "effects": [ { "op": "param_mod", "scope": "ability", "ability": "command_field", "key": "damage_bonus_pct", "set": 20,
                                "selector": { "unit_ids": ["unit.han.link_operator", "unit.han.dragon_command_walker"], "include_replacements": true },
                                "stack_group": "command_field" } ] } ] }
```
(the Central Priority prose also says "instead of +10 %": 10 is in `ability.command_field.default`; `bible_numbers` lists 15 and 20.)
Converted (`power.nec.counterbattery_mission`; `global.json → support_power_damage.counterbattery_mission`): `DefPower{warning_t:100, target_mode:1 (POINT), target_vision:2 (CURRENT), radius:4096, actions:[DefPowerAction{op:3 (STRIKE), count:6, duration_t:80, radius:4096, impacts:[DefImpactPacket{damage:320, dtype:2, radius:1638, edge_bp:3000, delay_t:0, non_lethal:false}]}]}`; shell *k* = 0…5 lands at tick `k·80/6` = 0, 13, 26, 40, 53, 66 (positions drawn by the power system). `edge_pct 30 → 3000`, `splash 1.6 cells → 1638`.

### 7.11 Superweapons — compiled from `global.json → superweapons` and the bible (no separate file)

The balance framework already carries every superweapon number (`global.json → superweapons.*`, FRAMEWORK §5.11: geometry, damage, timings, drone and engine stats), and the bible carries recharge, warning, launcher and prerequisites (bible-only, `V-CNF-04`; the framework's `recharge_s` / `warning_s` are verified equal). A second file would duplicate both, so **`DefLoaderEffects` compiles `DefSuperweapon` from bible ⊕ `global.json`**; the only data-module knowledge is the mapping below (bible id → `SwAction`, which `global.json` key feeds which field). File units → converted units follow §5.2.2; every packet offset is in the local frame of the committed line (`+x` along the orientation given by the `SUPERWEAPON_FIRE` angle, FRAMEWORK §6).

| superweapon (structure) | `global.json` key | `SwAction` | compile rule (file value → converted) |
|---|---|---|---|
| `napc.atlas_kinetic_array` | `atlas` | `KINETIC_VOLLEY` (0) | 3 packets from `packets[]`: `{radius_cells 2.0, damage 2400, kinetic, edge_pct 50, offset_cells −3/0/+3, delay_ticks 0}` → `{radius 2048, damage 2400, dtype 5, edge_bp 5000, offset_x −3072/0/3072, delay_t 0}` |
| `nec.aurora_microwave_array` | `aurora` | `EMP_BURST` (1) | `radius_cells 8.0 → radius 8192`; packet `{damage 150, emp, edge_pct 100, non_lethal true}` → `{damage 150, dtype 6, edge_bp 10000, non_lethal true}`; effects: `disable weapons weapon_disable_s 8 → 160 t` on enemy vehicles + aircraft, `disable structure structure_shutdown_s 18 → 360 t` on enemy powered structures; `infantry_unaffected`, `bypasses_trident` → `params` |
| `olm.helios_reflector` | `helios` | `BEAM_SWEEP` (2) | one packet `{damage 620 per second, thermal, radius 1536 (half of width 3.0), edge_bp 10000, per_second true}`; `params {line_len_u 16384, width_u 3072, traverse_t 240, hit_every_t 5}` (per-hit damage = `rdiv(dps · hit_every_t, TPS)` = 155, four hits per second; the Saudi +15 % thermal modifier scales the packet `damage`) |
| `def.perun_missile_complex` | `perun` | `BUNKER_BUSTER` (3) | packets `core {radius 3072, damage 5200, he, edge_bp 5000}` and `fragmentation_ring {radius 7168, damage 400, he, edge_bp 3000}`, both at offset 0 |
| `pd.tempest_swarm_hub` | `tempest` | `DRONE_SWARM` (4) | `summon = summon.pd.tempest_strike_drone` (health 90, armor `air_light`, speed 8.0 → 410 upt, weapon `drone_missile` 60 hp / 2.0 s / 4.5 cells), `summon_count 24`, `radius 6144`, `duration_t 400` (`attack_window_s 20`); each hit is a packet, drones are shootable by ordinary AA |
| `han.dragonfall_field_foundry` | `dragonfall` | `ENGINE_DROP` (5) | `capsule_count 3` inside `radius 5120`; capsule `{health 1500, armor heavy_armor, unfold_t 100}`; engine summon `summon.han.dragonfall_engine` `{health 3200, armor heavy_armor, speed 1.0 → 51 upt, lifetime_t 1200, weapon siege_gun 420 hp / 3.5 s / 8.0 cells, splash 0.7, scatter 1.2}`; flags `no_command_buff no_repair no_capture no_salvage`; each shot is a packet |
| `ae.horizon_mass_driver` | `horizon` | `RAIL_STRIKE` (6) | 3 packets `{radius 3072, damage 1300, kinetic, edge_bp 5000, offset_x −5120/0/5120, delay_t 0/90/180}` (`at_s 0/4.5/9.0`), `line_len_u 10240`, `duration_t 180`; debris zone `zone.horizon_debris` (`land_vehicle_speed_pct 65 → 6500 bp`, `duration_t 400`, blocks construction) |
| `sap.trident_interception_array` | `trident` | `INTERCEPT_ZONE` (7) | zone `zone.trident_interception` `radius 6144`, `duration_t 500`, `charges 24`, `charges_per_ordinary_projectile 1`, `charges_per_strategic_packet 8` (= `DefEconomy.intercept_packet_charges_n`), `strategic_reduction_pct 50 → 5000 bp`; bypass list (beam, bullet, emp, units inside, weapons fired from inside) → `params` |

Common fields (`superweapons.common` and the bible): `recharge_t` = 9600 for the six 480 s weapons (Aurora 420 s = 8400, Trident 360 s = 7200), `warning_t` = 200 (Aurora 160, Trident 120), `max_charges 1`, `starts_charged false`, `target_vision EXPLORED`, `launcher` = the faction's `*_array/_reflector/_complex/_hub/_foundry/_driver` structure. `V-EFF-08` checks the packet counts, radii and timings against the bible prose numbers; `V-CNF-05` re-verifies that `global.json`'s recharge/warning equal the bible.

Converted (`Atlas`): `DefSuperweapon{action_kind:0, recharge_t:9600, warning_t:200, max_charges:1, starts_charged:false, target_vision:1, packets:[DefImpactPacket{damage:2400, dtype:5, radius:2048, edge_bp:5000, delay_t:0, offset_x:-3072, offset_y:0}, {…, offset_x:0}, {…, offset_x:3072}]}` (`480 s → 9600 t`, `10 s → 200 t`). Roster clones scale packet `damage` only when a modifier lists the superweapon (`additional_superweapon_ids`; Saudi Arabia: Helios).

### 7.12 `zone_templates.json` — area/decoy/puck/shelter/smoke/repair templates (fallback; abilities' `zones.json` replaces it if adopted, §7.0)
`{"schema":"meridian.balance.zone_templates/1","zones":{"zone.<name>":{…}}}` — fields: `kind*` (`buff smoke intercept debris decoy puck shelter cover repair reveal`), `shape="circle"|"line"`, `radius_cells`, `length_cells`, `width_cells`, `duration_s*`, `affects="friendly"|"enemy"|"all"`, `follow_source=false`, `hp=0` (destructible/shootable when > 0), `targets=[layers]`, `visible_to_enemy=true`, `max_per_owner_n=0`, `effects=[…]` (§7.5), `params={}`, `pres`. Shared templates: `zone.smoke_dust_screen`, `zone.repair_station`, `zone.portable_cover`, `zone.infantry_shelter`, `zone.sensor_puck`, `zone.decoy_light_vehicle`, `zone.decoy_tank`, `zone.decoy_radar`, `zone.decoy_transport`, `zone.trident_interception`, `zone.horizon_debris`; powers may define inline zones.
```json
"zone.smoke_dust_screen": { "kind": "smoke", "shape": "circle", "radius_cells": 6, "duration_s": 12, "affects": "all",
  "effects": [ { "op": "resist_mod", "pct": 30, "fire_modes": ["direct"], "selector": { "kinds": ["unit"], "tags_all": ["ground"] },
                 "stack_group": "smoke" } ] },
"zone.portable_cover": { "kind": "cover", "shape": "circle", "radius_cells": 1.2, "duration_s": 45, "affects": "friendly", "max_per_owner_n": 0,
  "effects": [ { "op": "resist_mod", "pct": 20, "groups": ["bullet"], "selector": { "kinds": ["unit"], "tags_all": ["infantry"] }, "stack_group": "cover" } ] }
```
("All ground units inside, friendly or enemy, take 30 % less **direct-fire** weapon damage; artillery and area blasts unaffected" ⇒ `fire_modes:["direct"]` (TAXONOMY: `FireMode.DIRECT`; indirect and melee are untouched), `affects:"all"`; shared by Naga smoke, Broken Contact, Concealed Crossing — the "shared Dust Screen rule". Converted effect: `DefEffect{op:2, delta_bp:3000, group_mask:0, fire_mode_mask:1}`.)

### 7.13 `faction_traits.json` — faction traits and player-scope parameters
`{"schema":"meridian.balance.faction_traits/1","factions":{"faction.<code>":{"pres":{"palette":"palette.<code>"},"traits":{"trait.<code>.<name>":{…}},"player_params":{}}}}`. Each bible `traits_text[i]` (3 per faction) must be **covered exactly once** by a trait entry (`"covers":[i]`), which is one of: `"grant"` (adds an ability to defs at roster build: `{"selector":…, "ability":…}`), `"player"` (player-scope ability, e.g. SAP reserve), `"encoded_in"` (already typed elsewhere: modifier ids / structure ability / unit overrides), `"text_only"` (no mechanics). Coverage:

| faction | trait | covers | encoding |
|---|---|---|---|
| NAPC | `factory_apron` | 1 | `grant` on `structure.shared.factory`: `aura_regen` radius 5 cells, 1 %/s, cap 75 %, idle 6 s, targets `land_combat_vehicles`, group `factory_apron`; `bible_numbers [5,1,75,6]` |
| NAPC | (typed) | 0, 2 | `encoded_in` modifiers `napc.01/02`; strengths text `text_only` |
| NEC | `networked_fire` | 0 | `encoded_in` `structure.nec.relay` ability `relay_field` (6 cells, +10 %, group `relay_field`, targets `selector.balance.infantry_and_land_vehicles`); 1: modifier `nec.01`; 2: text |
| OLM | — | 0, 1 | `encoded_in` modifiers `olm.01-05`; 2: text |
| DEF | — | 0 | `encoded_in` `def.01-03`; 1 ("no free units…"): `text_only`; 2: text |
| PD | `amphibious_collectors` | 0 | `encoded_in` bible `unit_overrides` (`add_tags:[amphibious]`, water speed 70 %); 1, 2: modifiers `pd.01/02` |
| HAN | `command_field` | 2 | `encoded_in` unit abilities `command_field` (Link Operator, Dragon; 5 cells, +10 %, group `command_field`); 0, 1: modifiers `han.01-03` |
| AE | `salvage` | 0 | `grant` `salvage` (8 s, 20 %, wreck 60 s) to `unit.shared.engineer`; Reclaimer/River Warden carry it natively; 1, 2: modifiers `ae.01/02` |
| SAP | `power_reserve` | 1 | `player`: `defense_power_reserve` reserve 20 s, recharge 60 s continuous; 0, 2: modifiers `sap.01/02` |

### 7.14 `neutral_structures.json` — neutral map objects (map generator places them; sim treats them as pid −1; fallback, economy's `neutral_structures.json` replaces it if adopted, §7.0)
`{"schema":"meridian.balance.neutral_structures/1","neutrals":{"neutral.<name>":{…}}}` — `kind*` (`civilian_garrison power_substation observation_post salvage_depot deposit`), `health`, `armor_class`, `footprint {w,h}`, `sight_cells`, `capturable=false`, `capture_s`, `garrison_squads_n` (garrison: bible **4**), `reward {credits, power_n, reveal_radius_cells, income_crps, credits_per_cell, cells_n}`, `pres`. Initial set: `neutral.civilian_garrison` (4 squads; occupants of El Andalus gain the garrison damage bonus, cond code 2), `neutral.power_substation` (capture ⇒ +power), `neutral.observation_post` (capture ⇒ permanent reveal radius), `neutral.salvage_depot` (capture ⇒ one-time credits), and two **deposit** kinds that mirror `global.json → economy.deposit` (`credits_per_cell` 600 / `rich_credits_per_cell` 1200; a standard field is 24 cells = 14 400 credits, a rich field 16 cells = 19 200; **finite**, `regrow: false`; harvested by Collectors — the *only* economy source; a conflicting number in both files is `V-CNF-09`). Enemy production structures and superweapons are **never** capturable (Engineer text; `SF_CAPTURE_IMMUNE`).
```json
"neutral.civilian_garrison": { "kind": "civilian_garrison", "health": 1200, "armor_class": "building_light", "footprint": { "w": 2, "h": 2 },
  "sight_cells": 6, "garrison_squads_n": 4 },
"neutral.salvage_field": { "kind": "deposit", "health": 1, "armor_class": "building_light", "footprint": { "w": 3, "h": 3 }, "sight_cells": 0,
  "reward": { "credits_per_cell": 600, "cells_n": 24 } }
```
Converted (`neutral.salvage_field`): `DefNeutral{neutral_kind:4 (DEPOSIT), health:1, armor_class:8, fp_w:3, fp_h:3, sight:0, capturable:false, reward:{cells_n:24, credits_per_cell_cr:600}}` (the standard field holds `24·600 = 14 400`).

### 7.15 Presentation and audio references (ids only)
`pres_recipe`/`pres_icon`/`pres_snd_profile`/`pres_ai_role`/`pres_scale_bp`/`pres_palette` are opaque strings/ints excluded from every hash; the JSON spelling is the `pres` object of unit/structure/neutral/faction entries (§7.7). Defaults: recipe and icon = the def id; `snd_profile` from the archetype's family. The validators check existence against `game/data/recipes/<id>.json` (the directory exists and is being filled by the view domain) and `game/data/audio/events.json` when those registries exist (`V-REF-02`: ERROR if the registry exists, WARN otherwise). The audio domain maps a profile to its event ids (`select move attack die build_complete …`); the data layer never stores audio behaviour. Weapon and projectile visuals are chosen by the view domain from the weapon *archetype* id (`warch.<name>`), so weapon instances carry no presentation fields.

### 7.16 Bible mirror and provenance
`game/data/bible/meridian_factions.json` is a byte-for-byte copy of `Input/meridian_agent_reference/meridian_factions.json` written by `tools/py/sync_bible.py`, which also writes `game/data/bible/manifest.json` (`files.<name>.{bytes, sha256, source_sha256}`) and mirrors `meridian_factions.schema.json`. `python3 tools/py/sync_bible.py --check` (exit 1 on drift) is what `V-CNF-07` runs. Nothing in `game/data/bible/` is ever hand-edited. The loader reads only `meridian_factions.json` (not the schema, the `.md` or the manifest).

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

| Rule | How the data domain complies |
|---|---|
| **DR-1** ints only | Every Def field is `int`/`bool`/`String`/packed-int/child-Def/`params` of those (§4.0). The *only* float operations in the module are `float(v) * 1000.0` + `roundi` inside `DefNumParse.milli` on parse-time literals, guarded by `\|m − r\| ≤ 0.001` (≤ 3 decimals ⇒ unambiguous on every IEEE-754 platform). The project linter enforces the boundary: rule L003 rejects float literals, types and builtins anywhere in `src/data` except files named `*_loader.gd` / `*_parse.gd`, and `def_num_parse.gd` is the only float-touching file. `DefValidator` (debug) reflects over all defs and errors on any `TYPE_FLOAT` (V-DET-01). Display strings come from the integer-only `DefFormat`. |
| **DR-2** no engine RNG | None used. Random *patterns* named in data (`pattern:"random_in_radius"`) are executed by the sim with `SimRng`. |
| **DR-3** no wall-clock in the sim | `data/` never calls `Time.*`/`OS.get_ticks_*` (lint L003 greps for them); `FileAccess.get_modified_time` is used only by `DefHotReload` (dev, app-driven, never during a networked match); load-time benchmarks live in tests. |
| **DR-4** no float builtins on sim values | `roundi` appears only in `DefNumParse.milli` (`DefHash.hash_json` calls it); all runtime math is integer (`DefStatMath`, `DefConvert`). |
| **DR-5** integer semantics | All formulas use non-negative operands except signed deltas, for which `rdiv` (sign-symmetric half-away) is used; no `>>` on negative values (Godot 4.7.2 rejects constant negative shifts); products bounded < 2^62 (§5.5.3; `final_damage`: 10^5·3·10^4·300·10^4·100 = 9·10^17); `ceil_div` only for `n ≥ 0`. Integer division is intentional: the project sets `gdscript/warnings/integer_division=0` (verified: with the warning set to *error*, a `@warning_ignore("integer_division")` placed above the `func` line does **not** cover the body — keep the project setting, do not rely on per-function annotations). |
| **DR-6** iteration order | Files come from the manifest (no `DirAccess`); ids sorted by code point; `Dictionary` params are built by inserting keys in sorted order and hashed by sorted keys; sets are ascending `PackedInt32Array`s; nothing iterates a Dictionary in insertion order to make a decision. |
| **DR-7** total orders | Only `Array[String].sort()` (unique keys) and `sort_custom` with comparators ending in the def index (`(tier, cost, index)`, `(score desc, index)`). |
| **DR-8** no Node/signal/await | `data/` is `RefCounted`/static only. `DefHotReload` is polled by the app. |
| **DR-9** no hidden global state | Immutable `GameData` (may be cached per process: `GameData._cache`; two worlds share it read-only). `GameData.last_report` is diagnostic and never read by the sim. Mutable state lives in `DefLayer3` (inside `DefPlayerView`), owned by `SimPlayer`. |
| **DR-10** convert once, hash the result | §5.2 + §5.11: the converted tables *and the resolved rosters* are hashed; the hash goes into the lobby handshake. |
| **DR-11** bounded work | Load-time work is bounded by data size; runtime data access is O(1) (dense arrays, bit masks); `DefLayer3.ability_param` scans ≤ (number of completed research effects on that key) — ≤ 10 for any player. |
| **DR-12/14/15** | `DefQuery`/`DefBrowser` are read-only for AI/UI and cannot mutate defs (defs have no setters used after freeze; `check_frozen` in tests). |

**Other project lint rules and how the module meets them** (`tools/gd check src/data` must print 0 violations; the run is part of every task's acceptance):

| Rule | Consequence in this module |
|---|---|
| L003 (floats/RNG/clocks/`delta`) | see DR-1; no `randi`, `shuffle`, `pick_random`, `Time.*`; sorting is `Array.sort()` / `sort_custom` with total orders; a `float` never appears outside `def_num_parse.gd` |
| L004 / L009 (class prefix, file = snake_case(class)) | every class is `Def*` or `GameData`; `DefLoaderBalance` → `def_loader_balance.gd`; inner helper classes are not used (one class per file) |
| L005 (dependency direction) | `src/data` mentions only `core` names (`Fp`, `SimConfig`, `SimRng`, `Log`, `Checksum`) and other `Def*`; anything about `SimWorld`, `SimPlayer`, `AiXxx`, `NetXxx` appears **only in comments/strings**, never in code (the linter blanks comments and strings before matching) |
| L006 | no `print()`; diagnostics go through `DefLoadReport` and `Log.warn/error`; every `TODO` is written `TODO(data): …` |
| L007 | ≤ 1500 lines per file: the validator is three classes — `DefValidator` (driver + FAST rules), `DefValidatorSource` (V-SCH/REF/CMP/CNF/RNG on raw inputs) and `DefValidatorData` (V-MOD/ROS/TIER/ROLE/EFF/ABL on tables); `DefLoaderBalance`, `DefLoaderRules` and `DefResolver` are budgeted at ≤ 1200 lines each (§11) |
| L008 | every `var` is typed (`var x: int = 0` or `:=`) |
| L001 / L002 / L010 | `res://data/...` literals must exist with exact case (`res://data/bible/meridian_factions.json` and `res://data/balance` exist today; `manifest.json` is created by BAL-00 before DATA-03's tests reference it); file names are lowercase snake_case; LF only |

**Platform pitfalls handled explicitly.** (1) Windows checkouts with CRLF: JSON parsing is unaffected; hashes are canonical, not byte-based. (2) `PackedInt32Array` wraps at 2^31 (verified): hashes are stored in `int`, never in `PackedInt32Array`; masks use `int`. (3) `String` comparison and `sort()` are code-point based on all platforms (verified) — file names and ids are ASCII. (4) `get_property_list()` order is a pure function of the script (derived variables before base variables on 4.7.2). (5) No locale-dependent formatting (`str(float)`, `%f`) is used in any key, id or hash. (6) Exact-case file names; no reserved Windows names; manifest paths are relative and use `/`.

**What enters the checksum.** Defs are immutable and covered by `data_hash`; therefore (a) `SimWorld.checksum()` **seeds with `data_hash`** (so any desync dump names the data version), and (b) the only mutable data-module state that must be checksummed per player is `DefPlayerView.checksum()` = `DefLayer3.checksum()`: `mix(version)`, `completed` (in completion order), the accumulator arrays (`unit_stat_bp`, `struct_stat_bp`, `unit_resist_bp`, `struct_resist_bp`), the recorded `param_mods` (scope, target, kind, key, op, value in application order), flags and granted abilities. The flat tables of `DefPlayerView` are derived from those and are not hashed. Any new persistent field added to `DefLayer3` must be added to that function in the same change (DR-13).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

**Per tick: zero allocation, zero dictionary lookups on the data side.** The sim reads `roster.units[e.def]` (one array index) and int fields. Costs of the calls that do run in-tick:

| Call | Cost | Frequency / worst case |
|---|---|---|
| `roster.units[def].health / .speed / .sight …` | 2 loads | per entity per use; 400 entities × ~10 reads = 4 000 loads/tick ≈ 0.05 ms |
| `DefStatMath.effective(...)` | ≈ 10 integer ops + 1 clamp | recompute only on `layer3.version` change or buff toggle (cache in the entity); worst 400 entities on a research completion = 400 × 0.5 µs = 0.2 ms once |
| `DefStatMath.final_damage(...)` | 1 array read (`matrix_pct`) + 10 int ops ≈ 0.5 µs | per hit; worst 600 hits/s ≈ 0.3 ms/s |
| `DefMoveTable.effective_speed(...)` | 1 array read + 6 int ops ≈ 0.4 µs | per moving entity per repath/terrain change (movement caches it per cell class), not per tick |
| `DefLayer3.unit_stat_bp/resist_bp` | 1 array read | per stat query (cached per version) |
| `DefLayer3.ability_param(...)` | linear scan of `param_mods` (≤ ~10) | per ability activation only (not per tick) |
| `DefPlayerView.refresh()` | ≈ 60 defs × 6 lookups ≈ 30 µs | once per research completion |
| `DefRoster.prereqs_met` | 1 AND + compare | per UI refresh / AI decision / command validation |
| `DefQuery.*` | ≤ 40 defs × ≤ 3 slots | AI ≤ 1 Hz per player ⇒ < 0.1 ms/s |

**Load-time budget (mid-range CPU, GDScript; measured micro-benchmarks on Godot 4.7.2 in parentheses).**

| Phase | Estimate | Basis |
|---|---|---|
| P0 read + parse bible (640 KB) + `global.json` (128 KB) + 9 sheet files + overlays (~0.5 MB) | 15-25 ms | bible `JSON.parse_string` measured **8 ms** |
| P1 source validation (FULL) | 20-40 ms | ~50 k checks |
| P2-P5 vocabularies (7×11 matrix, 9×8 speeds, 27 archetypes) + ~330 defs + derived caches | 30-50 ms | object creation measured 2 ms/1000 objects; conversion ≈ 0.05 ms/def |
| P6-P7 rules + selectors (27 + inline ~90) + modifiers | 10-15 ms | |
| P8 rosters (32 + base; ~40 clones each; 158 applications) | 25-40 ms | availability + matching + golden compare for all 32 rosters measured **6 ms** in an unoptimised GDScript prototype; clone = reflective copy ≈ 30 µs |
| P9 validate (FULL: golden, tag⇔capability, playability) + hash | 40-60 ms | reflect-hash **20 ms / 1000 defs** (31 props) ⇒ ≈ 35 ms for ~1 800 clones |
| **Total (`LEVEL_FULL`)** | **≈ 150-250 ms** | one-off at boot; hot reload same |
| Total (`LEVEL_FAST`, release) | ≈ 90-150 ms | skips V-CNF-06/V-MOD-12/V-ROLE/V-TIER-04 |
| `file_hashes()` (lazy, only after a mismatch) | ≈ 50-100 ms | canonical hash of the bible tree measured **48 ms** |

**Memory.** ≈ 330 base defs + ≈ 1 300 roster clones + selector/modifier tables + ~1.5 MB retained parsed sources (for `file_hashes`; released by `GameData.drop_sources()` in release builds after the handshake) ⇒ ≈ 4-6 MB.

**Worst cases and mitigations.** (1) Reload storm during editing: `poll()` at 1 Hz costs ~20 `stat` calls; `reload()` only when mtimes changed (≈ 250 ms; dev only). (2) Adding 100 more units: linear, still < 400 ms. (3) 8 players finishing research on the same tick: 8 × `apply_research` (≤ 3 effects × ≤ 30 defs) + 8 × `refresh()` ≈ 0.4 ms. (4) Field Manual open: `DefBrowser.unit_card` re-matches ≤ 5 modifiers × 1 unit ≈ 0.05 ms; `tech_tree` builds ≤ 60 nodes. (5) AI `counters_of` across 40 candidates × 3 slots ≈ 0.05 ms. (6) A domain plug-in with a slow `compile` adds directly to boot: each `DefDomainCompiler` should stay < 30 ms (`test_data_loader` prints per-phase timings and warns above budget). Mitigations: dense arrays instead of dictionaries, bit masks for tags/prereqs, lazy per-roster selector caches, `LEVEL_FAST` in release, no per-tick `PackedInt32Array` creation (results of `DefQuery` are allocated once per call, outside the sim loop).

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

All tests are `game/tests/unit/test_data_*.gd` (QA harness: `extends RefCounted`, `func test_x(t: TestCtx) -> void`, one fresh instance per test; `t.eq` is **type-strict**, so `t.eq(DefConvert.cells_to_units(7000), 7168)` also proves the result is an `int`), runnable with `tools/gd test data`; the lint gate is `tools/gd check src/data`. A test kit `DefTestKit` (`game/tests/fixtures/data/def_test_kit.gd`; `fixtures/` is never scanned as tests) builds **stub sheet data in memory** for the *real* bible and the *real* `global.json` (every unit: cost `100+index`, health 1000, speed 3.0 cps, sight 8 cells, one 50-damage weapon…) so resolver tests are exact and independent of the evolving balance sheets; explicit-base tests below override the relevant entries.

### 10.1 Unit tests
| Test | Cases → expected |
|---|---|
| **convert** (vs `convert_vectors.json`, ≥ 300 rows) | cells: 7.0→7168, 7.5→7680, 0.45→461, 0.55→563, 1.0→1024, 0.001→1, 0.0005→**error V-SCH-04**; cps: 1.0→51, 2.0→102, 3.0→154, 3.2→164, 2.6→133, 8.0→410; seconds: 1.05→21, 1.051→22, 0.05→1, 0.06→2, 0→0, 15.5→310, 27.5→550, 45→900, 75→1500; reload 1.2 s→24000 mt, 0.25 s→5000 mt, 1.6 s→32000 mt; pct: 10→1000, 12.5→1250, 0.005→**V-SCH-06**; deg: 90→1024, 360→4096; deg/s: 90→51, 120→68, 150→85, 180→102, 720→410; `1e12`→error; NaN→error; `rdiv(-7,2)=-4`, `rdiv(7,2)=4`, `rdiv(5,2)=3`, `ceil_div(21001,1000)=22`; `DefNumParse.is_integral(3.0)`, `not is_integral(3.5)` |
| **format** | `cells_text(7168)="7.0"`, `cells_text(563)="0.5"`, `speed_text(102)="2.0"`, `seconds_text(550)="27.5"`, `mt_seconds_text(24000)="1.2"`, `percent_text(1000)="10"`, `percent_text(-1500)="-15"`, `percent_text(1250)="12.5"` |
| **stat math** | `fold2(800,1000,0)=880`; `fold2(420,1000,0)=462`; `fold2(400,1000,1000)=484`; `fold2(500,-1000,1500)=518`; `fold2(1100,-1000,1000)=1089`; `fold2(1400,500,1000)=1617`; `fold2(150,2500,0)=188`; `fold2(150,2500,2000)=225`; `fold2(133,-1000,-1000)=108`; `resolve_static(COST,200,-1500,0)=170`; `effective(COST,200,170,-3000)=120` (floor); `effective(RELOAD,40000,44000,-1500)=37400`; `effective(RELOAD,40000,20000,-5000)=20000` (50 % floor); `apply_bp(55,2000)=66`; `resist_total_bp(6500)=5000`; **`final_damage(raw,bonus,matrix,resist,falloff)`**: `(141,10000,100,1000,100)=127`, `(140,10000,100,0,100)=140`, `(100,10000,100,6500,100)=50` (cap clamped inside), `(140,10000,0,0,100)=0` (rail vs aircraft), `(1,10000,6,5000,100)=1` (min 1), `(140,11000,100,0,100)=154`, `(2400,10000,130,0,50)=1560` (kinetic vs building at the splash edge), `(5200,10000,70,0,100)=3640` (Perun core vs fortress) — each also equals `balance_calc.final_damage` from the Python side; `rescale_hp(300,400,440)=330`; `rescale_hp(1,1000,1)=1`; `dps_x100` of the framework reference tank (140 dmg, 24000 mt)=**11666**, of the styled Guardian (141)=11750, of the Sunlance beam (50 dmg, 5000 mt)=20000 |
| **hash** | `mix_int` LEB128 vectors (0→`00`, 1→`02`, −1→`03`, 63→`7E`, 64→`80 01`); `mix_byte(OFFSET, 0x61) = 0xE40C292C` (the standard FNV-1a-32 vector for `"a"`); canonical JSON hash equal for whitespace/CRLF/key-order variants, different for 1-milli change; a `float` inside a `Def` bumps `DefHash.float_hits` |
| **move table** | `speed_bp_at(FOOT, DEEP)==0`; `(FOOT, ROAD)==11000`; `(WHEELED, ROAD)==13000`; `(WHEELED, FOREST)==0`; `(TRACKED, FOREST)==5500`; `(AMPHIBIOUS, SHALLOW)==9000`; `(AMPHIBIOUS, DEEP)==7000`; `(NAVAL, OPEN)==0`; `(NAVAL, DEEP)==10000`; `(STATIC, *)==0`; `(AIR_FIXED, *)==10000`; `passable(FOOT, SHALLOW)==true`; layer masks: `AMPHIBIOUS → L_GROUND\|L_WATER`, `SUBMERGED → L_UNDER\|L_WATER`; **`effective_speed`**: Canada Beaver (164 upt) on `DEEP` with `water_mult_bp 12000` → **138**; Tide Tank (102 upt) on `DEEP` with `deep_speed_bp 6000` → **61**; tracked tank (102) on `FOREST` → **56**; wheeled (164) on `ROAD` → **213** |
| **ids/tags** | 29 structures get the indices of §5.3 (e.g. `structure.shared.radar == 26`); `UT_*` bits match §4.1 (`UT_COMBAT == 1<<9`); tags_add of a locked tag → V-CNF-03; unknown tag in `all_tags` → V-MOD-02; weapon archetype ids `warch.tank_cannon == 3`, `warch.drone_missile == 26` (frozen, not sorted) |
| **global.json consumption** (§7.3) | `damage.matrix_pct[AP*11+HEAVY_ARMOR]==90`, `[EMP*11+INFANTRY]==0`; `damage.group_mask == [1,2,2,12,16,32,64]`; `nonlethal_mask == 1<<6`; `moves.speed_bp[AMPHIBIOUS*8+DEEP]==7000`; `bodies.radius_u[MEDIUM]==563`, `turn_apt[MEDIUM]==85`; `weapon_archs[3]`: `{dtype:1, fire_mode:0, proj_kind:1, proj_speed:819, homing:true, target_mask:5, splash_radius:512, splash_edge_bp:5000, range_lo:6656, range_hi:9216, reload_lo_mt:20000, reload_hi_mt:32000, turret_turn:51, interceptable:0}`; `weapon_archs[13].tags` has `thermal_beam`; `[7].tags` has `anti_air` and `guided_missile`; structure `generator` → `{cost:600, build_ticks:500, health:1200, armor_class:8, fp 2×2, radius:1024, sight:6144, power:150}`; `economy.start_cr==7500`, `floor_cost_bp==6000`, `resist_cap_bp==5000`; a mutated vocabulary (swap two damage type indices) → `V-CNF-05` |
| **unit sheets** (§7.6-§7.7) | Guardian: `cost 850, build_ticks 550, health 907, speed 102, sight 9216, radius 563, turn_rate 85, accel_t 6, size_class 2, weapons[0]={arch:3, damage:141, reload_mt:24000, reload_ticks:24, range:7168, proj_speed:819, turret_turn:51, mount:1}`; Beaver: `build_ticks 310, speed 164, move_class 3`, abilities `[DETECTOR r5120, TRANSPORT squads 2]`; Raptor: `rearm_t 160`, `weapons[0].mode_mask==1`, `weapons[1].mode_mask==2`, `weapons[0].ammo_volleys==6`; Sunlance-type beam: `reload_mt 5000, ramp_t 100, ramp_max_bp 15000`; a sheet with `damage_type` on a weapon → V-CNF-08; a missing sheet → V-CMP-01 |
| **abilities registry** (§7.4) | Charlemagne `deployable_mode` + `ability_params {deploy_s:4, range_bonus_pct:25}` ⇒ `DefAbility{kind:3, params:{command_radius_bonus_u:0, damage_bonus_bp:0, deploy_t:80, deployed_slots_n:[], immobile:true, pack_t:40, range_bonus_bp:2500, turn_locked:false}}`; an explicit `transport_3` replaces the implicit two-squad transport (`ability_slot_of_kind[TRANSPORT]` unchanged, `capacity_squads_n==3`); two entries of one kind → the later wins; unknown param → V-ABL-01 |
| **superweapons** (§7.11) | Atlas → `{action_kind:0, recharge_t:9600, warning_t:200, packets:[{damage:2400, dtype:5, radius:2048, edge_bp:5000, offset_x:-3072}, {…,0}, {…,3072}]}`; Aurora `recharge_t 8400, warning_t 160`, disable 160 t / 360 t; Helios packet `damage 620` per second, `hit_every_t 5`, `traverse_t 240`; Horizon packets `delay_t 0/90/180`; Trident `charges 24`, `strategic_reduction 5000`; recharge/warning mismatch vs bible → V-CNF-05 |
| **selectors** | 27 compile; `land_combat_vehicles` matches 70 of 156 units, `combat_infantry` 37, `defensive_structures` 11 of 29, `non_superweapon_structures` 21, `structures` 29, `all_transports` 18 (incl. Landing Transport); `thermal_beam_weapons` (unresolved U2) matches every unit/structure slot of archetype `beam_thermal` (Sunlance, Ifrit, Dawn, Sunwall); `ordinary_guided_missiles` (U3) matches the `APS_TRIDENT` archetypes; unknown condition string → V-MOD-04; **golden**: all 158 `modifier_applications` reproduced (0 mismatches) |
| **modifier folding (stub bases)** | Canada Narwhal health 1000 → **1210**, Beaver 1000 → 1210, Paladin reload ×1.15, Beaver `water_mult_bp == 12000` and `speed` unchanged (§5.6 #4); USA aircraft cost −15 %; Russia Ural cost 0.99×; Saudi generator **225**, OLM vanilla **188**; Han China vehicles health 1.035×; Nigeria build-time modifier leaves Horizon Mass Driver and HQ unchanged; Kazakhstan Refinery −15 % while `unit.shared.collector.cost == 1400`; Indonesia Landing Transport health +20 %; AE `repair_cost_bp == 3750` on Collector/MCV/Landing Transport and land vehicles, 5000 elsewhere; El Andalus Gate Guard `cond_vals` has `{DAMAGE, 2, 1.20×}`; **real numbers** (`global.json` styled proposals): Guardian/NAPC cost **935**, health **998**; Narwhal/Canada health **1097**, cost **891**; Raptor/USA cost **893**, rearm **128 t**; Ural/Russia cost **1411**, speed **75**; Marte/Eurocorps cost **1617**; each equals `balance_calc.py resolve … --styled` |
| **roster resolution** | 32 rosters + base; sizes: 21 rosters (12 combat + 4 service + 14 structures), 7 vanilla (13+4+14), 3 NEC subfactions (12+4+15), NEC vanilla (13+4+15); Canada: has Beaver, Narwhal; lacks Pathfinder, Guardian, Titan; `power_list == [uav_sweep, field_repair_drop, floating_workshop]`; `research_list == [adaptive_plating, joint_tactical_links, sealed_compartments]`; `replaced_by[pathfinder]==beaver`; PD vanilla Collector `move_class==AMPHIBIOUS`, `deep_speed_bp==7000`, tag `amphibious`; every roster: `V-ROS-01` clean; a replaced unit id passed to `has_unit` → false |
| **layer 3** | Fresh `DefLayer3` on `roster.ae.vanilla`: `apply_research(circular_armor)` ⇒ `unit_stat_bp(HEALTH, buffalo)==1000`, `effective_unit_stat(HEALTH, buffalo)==` base 440 for base 400, `version==1`; applying twice ⇒ `push_error` + no change; `adaptive_plating` ⇒ `unit_resist_bp(AP, guardian)==1000`, `(HE)==1000`, `(BULLET)==0`, `(THERMAL)==0`, `(RAIL)==0`; `sap.integrated_protection` ⇒ `ability_param(arjun, INTERCEPTOR, "cooldown_t", 300)==200`, `granted_abilities(gaj)` has INTERCEPTOR; `sensor_fusion` ⇒ `ability_param(fen, DETECTOR, "radius_u", 5120)==7168` (replacement inherits); `joint_tactical_links` is *conditional* ⇒ `cond_effects_of_unit(sentinel_aa).size()==1`, `unit_stat_bp(RANGE, sentinel_aa)==0`; same-group effects: larger \|Δ\| wins, ties keep first; `checksum()` changes with every apply and is identical across two identical sequences |
| **player view** | `DefPlayerView` on `roster.napc.vanilla` (stub bases): `unit_cost`, `unit_ticks`, `struct_power[generator]==150`, `resolved_stats(UNIT, guardian)[HEALTH]` equal the roster clone; after `apply_research(adaptive_plating)` `research_resist_bp(UNIT, guardian, AP)==1000` and `version` incremented; `refresh()` is a no-op when nothing changed; `checksum()==layer3.checksum()` |
| **plug-in compilers** | a dummy `DefDomainCompiler` registered for the test: its file appears in the manifest, its ids exist in `DefIds`, its table hash is folded into `data_hash` (removing the compiler changes the hash), a `compile` error aborts the load with the rule id, `file_hashes()` lists its file |
| **query** | `tech_path(napc vanilla, bastion_heavy_tank)` = `[generator, refinery, factory, radar, laboratory]`, `min_time_to_ticks` = 3700 + bastion build ticks (185 s of structures: 500+800+800+600+1000); `cheapest_structure_with(def.russia, ST_DEFENSE \| anti_air)` = `structure.shared.aa_battery`; `cheapest_unit_with(any roster, UT_DETECTOR \| UT_SCOUT)` returns the T1 APC of that roster; `units_with` results ascending; `counters_of` ties break to lower index |

### 10.2 Validator (negative) tests — one mutated `DefSources.deep_copy()` per rule, expecting the rule id
`V-SCH-01` remove a manifest file; `V-SCH-02` add a typo key `"helth"`; `V-SCH-04` `0.0005`; `V-SCH-05` `cost_credits: 800.5`; `V-SCH-07` param `radius: 5`; `V-REF-01` weapon id typo in a sheet; `V-REF-04` unknown `archetype` key; `V-CMP-01` delete a unit entry; `V-CMP-04` delete `health` from a sheet whose archetype is removed; `V-CMP-05` give Combat Medic a weapon; `V-CNF-01` set Engineer `cost_credits: 600` (bible 500); `V-CNF-03` `tags_add:["tank"]`; `V-CNF-04` set a research `cooldown`; `V-CNF-05` change `production.cost_floor_pct` to 50 or swap two damage-type indices; `V-CNF-08` give a weapon instance `damage_type: "he"`; `V-CNF-09` give `economy.json`-style override `collector_capacity_cr 500` against `global.json` 600; `V-RNG-01` tank health 999999; `V-RNG-04` remove one matrix cell; `V-RNG-05` set `movement_classes.foot.terrain_speed_pct.deep` to 50; `V-TIER-03` make a land unit require `structure.shared.dock` (needs a mutated *bible* copy); `V-ROLE-01` remove the AA weapon from Sentinel AA; `V-ROLE-05` tag a summon `combat`; `V-MOD-04` alter a selector condition string; `V-MOD-07` attach cond `IN_GARRISON` to a health modifier; `V-ROS-06` drop a tag of a replacement; `V-EFF-02` point a research selector at a unit the roster lacks; `V-ABL-01` unknown ability param; `V-ABL-05` drop `deployable_mode` from Paladin; `V-DET-01` inject a `float` into a `params` dictionary. Every clean-data run must print **0 errors**; warnings are listed in a reviewed allow-list `game/tests/golden/validator_allow.json`. The Python side runs the same mutations through `validate_balance.py --self-test` (each expected rule id must fire).

### 10.3 Scenario tests (`game/tests/scenarios/test_data_scenario.gd`, no `SimWorld` needed)
1. *Tech gating*: for each of the 32 rosters walk `producible_units` with an owned-structure mask growing along `tech_path`; assert every unit is reachable, the Dock is never in the closure of a land/air unit, and each roster has the T1 anti-armor/detector/anti-air/siege answers (V-TIER-04).
2. *Roster matrix*: for every roster resolve all 158 modifier applications against the stub bases and compare with an independent Python-generated table (`resolver_golden.json`, generated by `tools/py/balance_lib/resolver.py` from the same stub) — Python and GDScript agree on every (roster, def, stat) value (~2 300 values).
3. *Research flow*: Canada plays `sealed_compartments`; the resistance query with `on_water` handled by a test double ⇒ explosive (`AP`/`HE`) 15 % on Narwhal, 0 % on Guardian (absent).
4. *Hot reload*: copy the fixture dataset to a temp dir, load, edit one health value, `poll()==true`, `reload()` returns data with the new value and `is_hot_swap_compatible(old)==true`; delete a unit ⇒ `false`; break JSON ⇒ `reload()==null` with the rule id and line number, old data untouched.
5. *Framework parity*: for the ten pairs of §5.6 run `balance_calc.py resolve` once (Python, offline) into `game/tests/golden/framework_resolve.json`; the GDScript resolver must reproduce cost, health, build ticks, speed and reload for every pair.

### 10.4 Determinism tests
* **Double load**: `GameData.load_from_paths` twice ⇒ identical `data_hash` and `table_hashes`; every table hash equal.
* **Permutation invariance**: build `DefSources` with dictionaries re-inserted in shuffled key order (test-only shuffle with a fixed-seed local RNG) and CRLF/whitespace-mangled text for the disk path ⇒ identical `data_hash`.
* **Single-change sensitivity**: change one damage-matrix cell ⇒ `data_hash`, `table_hashes["global"]` and every `rosters` hash change; `diff_handshake(a, b)` returns exactly `["table global differs", "table rosters differs", "table units differs"…]` in sorted order, and with `files` exactly `["file balance/global.json differs"]`.
* **Cross-platform golden**: `game/tests/golden/data_hash.json` holds `{format, hash, tables}`; test compares on macOS arm64 and (via `tools/gd linux test data_hash`) Linux x86_64; CI fails on any difference. Update only with `tools/gd run res://tests/tools/data_cli.gd -- --update-goldens` after an intended data change.
* **Frozen**: after load `check_frozen(data)` and after a full `SimWorld` soak the recomputed `data_hash` is unchanged (nothing mutated a def).

### 10.5 Visual / golden-text tests
Field Manual is drawn by `ui/`; the data contract is tested as **golden JSON**: `DefBrowser.unit_card` for (`roster.napc.vanilla`, Guardian) and (`roster.napc.canada`, Narwhal), `roster_card(roster.napc.canada)` (replaced/removed/unavailable + 6 modifiers with `conditional` flags), and `tech_tree(roster.def.russia)` are compared with checked-in JSON (ints plus `DefFormat` text, so the golden is locale- and float-independent). UI screenshot tests (owned by `ui/`) then verify that these cards render (no missing keys).

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Milestones for other domains: **M1** (after DATA-03 + DATA-04 + a stub balance from DATA-11): `GameData.load_default()` returns all tables so sim/AI/UI can integrate; **M2** (DATA-06): `DefRoster`s + `DefStatMath`; **M3** (DATA-07..09): `DefLayer3`/`DefPlayerView`, validators, browser, hot reload. Dependency order: `DATA-01 → DATA-02 → DATA-03 → (DATA-04 ‖ DATA-05 ‖ DATA-10 ‖ DATA-11) → DATA-06 → DATA-07 → (DATA-08 ‖ DATA-09)`; BAL tasks depend only on DATA-10 (Python validator), TAXONOMY and `global.json`. **Every GDScript task is accepted only with `tools/gd check src/data` (lint L001-L010 + compile) at 0 violations and `tools/gd test data` green; no file exceeds 1500 lines.**

| Id | Title (≈ lines) | Files owned | Depends on | Acceptance tests |
|---|---|---|---|---|
| **DATA-01** | Foundation utilities (≈ 1 500 GD + 250 py) | `def_enums.gd def_num_parse.gd def_convert.gd def_format.gd def_stat_math.gd def_hash.gd def_ids.gd def_tags.gd def_load_report.gd def_sources.gd`; `tests/unit/test_data_convert.gd test_data_format.gd test_data_statmath.gd test_data_hash.gd`; `tools/py/gen_convert_vectors.py`; `tests/golden/convert_vectors.json` | core: `SimConfig.TPS`, `Fp.CELL`, `Fp.TURN`, `Log` | §10.1 *convert*, *format*, *stat math*, *hash*, *ids/tags*: all listed vectors; Python and GDScript agree on all ≥ 300 vectors; `def_num_parse.gd` is the only file with a float (lint L003 clean) |
| **DATA-02** | Def classes (≈ 1 700) | `def_base.gd def_unit.gd def_structure.gd def_weapon_arch.gd def_weapon_slot.gd def_damage_table.gd def_move_table.gd def_body_table.gd def_ability.gd def_ability_kinds.gd def_effect.gd def_cond_val.gd def_cond_application.gd def_research.gd def_power.gd def_power_action.gd def_superweapon.gd def_impact_packet.gd def_zone.gd def_neutral.gd def_faction.gd def_economy.gd def_modifier.gd def_selector.gd def_domain_compiler.gd def_compilers.gd` | DATA-01 | every class instantiates; reflective `copy_resolved()` deep-copies weapons/abilities/cond_vals (mutating the clone leaves the base intact); a test enumerates every script variable and asserts it is hashed or prefixed `_`/`ui_`/`pres_`; no float-typed property; `DefMoveTable.effective_speed` vectors of §10.1 |
| **DATA-03** | Loader core + `GameData` facade (≈ 1 900) | `game_data.gd def_loader.gd`; `tests/unit/test_data_loader.gd` | DATA-01/02 | P0-P3 + bible ingestion + P9 hash: counts 156/29/40/48/8/98/27/32/8; indices of §5.3; merge policy (V-CNF-01, V-CMP-04); manifest errors; error messages carry file:line; `handshake()` / `diff_handshake()`; a dummy `DefDomainCompiler` joins the load (§10.1 *plug-in compilers*) |
| **DATA-04** | Vocabulary + balance loader (≈ 2 300) | `def_loader_vocab.gd` (P2: `global.json` → damage/move/body tables, 27 weapon archetypes, economy; ≤ 700 lines), `def_loader_balance.gd` (P4: units, structures, weapon instances, summons, ability instantiation, derived caches; ≤ 1200 lines); `tests/unit/test_data_units.gd` | DATA-03 | the §7.3/§7.6/§7.7 worked examples convert to exactly the numbers printed there (`tank_cannon` record, Guardian 850/550/907/102/9216/563/85, weapon 7168/24000/819/51/512, Beaver 310/164, Raptor `rearm_t 160`, Sunlance `ramp_t 100`); vocabulary mismatch ⇒ `V-CNF-05`; ability defaults materialised (Charlemagne); derived caches (`max_range`, `attack_layer_mask`, `detect_radius`, `speed_water`, …) |
| **DATA-05** | Rules loader (≈ 2 100) | `def_loader_rules.gd` (research, powers, factions, neutrals, zones; ≤ 1100), `def_loader_effects.gd` (effects, conditions, inline selectors, superweapon compilation of §7.11; ≤ 1100); `tests/unit/test_data_rules.gd` | DATA-04 | 40/48/8 entries convert; JTL example → the `DefEffect` printed in §7.5; Atlas/Aurora/Helios/Horizon/Trident rows of §7.11; the counterbattery strike schedule 0,13,26,40,53,66; inline selector/zone ids deterministic; stack-group registry sorted; trait `covers` coverage V-CMP-03 |
| **DATA-06** | Resolver + rosters (≈ 2 400) | `def_resolver.gd def_roster_builder.gd def_roster.gd`; `tests/unit/test_data_selectors.gd test_data_resolver.gd test_data_roster.gd` | DATA-02..05 | **golden 158 applications = 0 mismatches**; all §5.6 numbers; §10.1 *modifier folding*, *roster resolution*; `V-ROS-01` clean ×32 |
| **DATA-07** | `DefLayer3` + `DefPlayerView` (≈ 1 300) | `def_layer3.gd def_player_view.gd`; `tests/unit/test_data_layer3.gd test_data_playerview.gd` | DATA-06 | §10.1 *layer 3*, *player view*; economy/abilities/combat accessor shapes of §3.13 exist with the requested field names |
| **DATA-08** | In-engine validator (≈ 2 200) | `def_validator.gd def_validator_source.gd def_validator_data.gd`; `tests/unit/test_data_validator.gd` | DATA-06/07 | §10.2 negative tests for every ENG rule; clean shipped data ⇒ 0 errors and only allow-listed warnings; `check_frozen`; float scan (V-DET-01) |
| **DATA-09** | Query, browser, format, hot reload, CLI (≈ 1 700) | `def_query.gd def_browser.gd def_hot_reload.gd`; `tests/tools/data_cli.gd`; `tests/unit/test_data_query.gd test_data_hotreload.gd` | DATA-06/07 | §10.1 *query*; §10.3 hot-reload scenario; golden card JSONs (§10.5); CLI `--validate --hash --dump --update-goldens` |
| **DATA-10** | Python validator + schemas (≈ 2 500 py) | `tools/py/validate_balance.py`, `tools/py/balance_lib/*.py`, `game/data/balance/schema/*.schema.json` | DATA-01 vectors, `balance_calc.py` | runs clean (0 errors) on the shipped balance; each §10.2 mutation yields its rule id (`--self-test`); parity with the GDScript golden (V-MOD-12); reuses `balance_calc.fair_cost_deviation` / `final_damage`; `--list-designer-params`, `--json`, `--strict` |
| **DATA-11** | Test kit + fixtures + stub balance (≈ 900 GD) | `game/tests/fixtures/data/def_test_kit.gd`, `game/tests/fixtures/data/*`, `tests/golden/data_hash.json`, `tests/golden/resolver_golden.json`, `tests/golden/framework_resolve.json`, `tests/scenarios/test_data_scenario.gd` | DATA-03 | kit builds stub sheets for all 156 bible units that pass `V-CMP/V-RNG`; golden files regenerate deterministically |
| **BAL-00** | Shared balance files | `manifest.json ability_kinds.json structures.json units_shared.json` (29 structures' overlay, 4 service units + shared summons, ability registry) | DATA-10, TAXONOMY, `global.json` | `validate_balance.py --strict` clean for these files; tier-curve warnings reviewed |
| **BAL-01…08** | Faction sheets (one task per faction; = FRAMEWORK BAL-5) | `units_<code>.json` (13 baseline + 6 unique units, weapon instances, summons/drones) | BAL-00, CMR-21c | strict validation; fair-cost deviation within the framework tolerances; all 4 rosters of the faction pass `V-TIER-04`; every bible ability sentence has a matching ability/param (prose check) |
| **BAL-09** | Research/power/zone/trait/neutral encodings (fallback files) | `research_effects.json power_actions.json zone_templates.json faction_traits.json neutral_structures.json` (40 + 48 + zones + 8 + neutrals) — **skipped where the abilities/economy domains supply their own files** | BAL-00, DATA-10 | strict validation incl. `V-CNF-06` prose numbers; `V-EFF-02` no dead effects |

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| 1 | **Vocabulary drift** with `docs/balance/TAXONOMY.md`, the map (terrain kinds), combat (damage pipeline), abilities (kinds/ops). | The damage types, armor classes, movement classes, terrain kinds, fire modes and weapon archetypes are **frozen by TAXONOMY** and verified at load (`V-CNF-05`); `DefEnums` is the registry of everything else (stats, conditions, ops, ability kinds); ability params are *data* (`ability_kinds.json`) plus one enum line. The reconciler edits those places and never loader code; suffix-driven conversion means new params need no code. |
| 2 | **Anchor deviation**: weapon reload stored in milli-ticks (`reload_mt`) instead of ticks. | Adopt (amendment request CMR-23). Fallback already in every slot: `reload_ticks = ceil(reload_mt/1000)`. If rejected, fast-weapon modifiers quantise (±10 % on 5 ticks becomes 0 %/+20 %). |
| 3 | **Two-stage rounding** (layers 0-2 one rounding, layer 3 second) differs from a single-shot fold by ≤ 1 unit. | Accept: deterministic and cache-friendly. Rejected alternative: keep static multipliers as rationals per (def, stat) (2 ints × 13 stats × 1 300 clones) — more state, no gameplay value. |
| 4 | **Bible ambiguities** requiring designer values: research/power radii not in prose (e.g. "near a powered Barracks"), Relay build time (null; `global.json` supplies 15 s), HQ deploy, structure footprints, capture rewards, carrier drone replacement cost/time (U1; `global.json → carriers`), "moderate" damage levels. | Every such value is authored in balance (mostly already in `global.json`), listed in the entry's `designer_params`, surfaced by `validate_balance.py --list-designer-params`, and never contradicts the bible. Review that list once per balance milestone. |
| 5 | **Unresolved domains U1-U3** could be resolved differently by combat. | The resolutions are **structural** (thermal-beam ⇔ archetype damage type `thermal`; guided missile ⇔ `interceptable == APS_TRIDENT`; carrier drones ⇔ class `DRONE`), enforced by `V-MOD-13`; changing them is a one-rule edit in `DefResolver` plus re-validation. |
| 6 | **Conditional stats beyond the three bible conditions** (new bible revisions). | Fail loudly (`V-MOD-04/07/08`); extend §5.5.5 table + abilities domain together. Only `ON_WATER→water_mult_bp`, `IN_CIVILIAN_GARRISON→DAMAGE` and `PAID_REPAIR→REPAIR_COST` exist today. |
| 7 | **Indices are not stable across data versions** (sorted-id assignment; a new `summon.*` shifts unit indices). | Persist only string ids (settings, saves); replays store `hash` + `tables["ids"]`; playback warns on mismatch. No migration layer needed. |
| 8 | **Godot exports skip `.json`** unless included. | Export preset `include_filter` (CMR-20) + a headless exported-binary smoke test (`--check-data`) in CI; `GameData.load_default()` fails loudly with the missing path. |
| 9 | **Speed quantisation** (1 upt = 0.0195 cells/s; ≤ 1 % error at 1 cps). | Accept; `V-RNG-02` warns for speeds < 1.0 cps. If ever a problem, widen `speed` to milli-upt without touching the resolver (only `DefConvert.cells_s_to_upt` and the movement system). |
| 10 | **Replacement units inheriting both abilities** (bible prototype priority). | Abilities are declared per unit (no implicit inheritance beyond the documented `implicit` table, which is keyed by tag/archetype and therefore *not* inherited through `replaces`); lint `V-ROS-08` + `keeps_abilities` acknowledgement. |
| 11 | **Hash sensitivity to script edits** (adding a Def field changes `data_hash`). | Intended (DR-13 spirit, catches version skew); golden files are regenerated by a single command (`data_cli --update-goldens`); the lobby message names the differing table. |
| 12 | **Prose-number check false positives/negatives** (numbers in words > twelve, ranges). | Warn-level by default; `bible_numbers` acknowledgement; `--strict` only in CI after authoring stabilises. |
| 13 | **Balance authoring scale** (~150 units, ~250 weapon instances, 40+48+8 effect entries). | The framework's archetypes + `proposals --styled` seed the sheets (CMR-21c), a strict validator checks them, eight parallel BAL tasks, and the stub balance (`DefTestKit`) lets every other domain develop against real ids immediately. |
| 14 | **Helios / superweapon scaling** must reuse the generic `DAMAGE` path. | Superweapon damage lives in `packets[].damage` (Helios: one thermal packet holding damage per second, converted to per-hit damage by `hit_every_t`), so `additional_superweapon_ids` scales exactly that field; other packet sets scale only if a modifier lists the superweapon. |
| 15 | **Open question — per-match rule overrides** (start credits, unit cap, superweapons off). | `MatchRules` (app/sim) overrides `DefEconomy` values *at world creation* as sim state; `GameData` stays immutable and shared. |
| 16 | **Open question — modding / multiple balance presets.** | Out of scope for v1. The manifest already gives a place: a future `presets/<name>/manifest.json` selected by `MatchConfig` and folded into `data_hash`. |
| 17 | **Class and concept collisions with the balance framework, abilities, economy and combat specs** (§2.1: `DefWeaponArch`, `DefBalanceGlobal`, `DefEconomyConsts`, `DefDamageMath`, `DefPercentMath`, `DefAbility`, `DefEffect`, `DefZone`, `DefNeutral`). Two implementations of one concept, or a duplicate `class_name`, breaks `tools/gd check` (L004) and forks the damage formula. | Adopt the single-owner table of §2.1 (this spec's classes as the superset, `DefDamageMath` kept as combat helpers around one `final_damage`, `DefPercentMath`/`DefBalanceGlobal`/`DefEconomyConsts` not created), executed by the reconciler through CMR-3, 6, 21, 25. |
| 18 | **Economy constants have two authorities**: `global.json → economy/production/power` (framework: Collector 600, 20 cr/s harvest, 120 cr/s unload, 600/1200 credits per deposit cell, no regrowth; and 500 in `service_units.collector` inside the same file) vs the economy spec (M16: cap 500, 25/50 cr/s, fields 8k/12k/20k, idle regrowth). Pacing checks of the framework (`balance_calc.py econ/pacing`) were tuned on its own numbers. | Precedence of §7.0 makes the domain file win; `V-CNF-09` reports every differing value so nothing changes silently. Recommended: economy owns harvest/deposit/regrowth (its `economy.json` wins), the framework re-runs `econ/pacing` against it and updates `global.json` accordingly; the bible-fixed numbers (start 7500, floors, cap, costs) stay ★. |
| 19 | **Float boundary and lint.** A future author who writes `0.5` or `round()` in `src/data` breaks `tools/gd check` (L003), and a float leaking into a Def breaks determinism. | Only `def_num_parse.gd` touches floats; DATA-01 acceptance includes the lint gate; `DefValidator` scans reflectively for `TYPE_FLOAT` (V-DET-01); `DefHash` counts float hits. |
| 20 | **The framework's ability vocabulary (22 names used, 26 valued) is smaller than the bible's prose abilities**; the abilities domain publishes a full catalogue (`abilities.json → slots`). | `ability_kinds.json` supplies templates for the framework names and the implicit rules; when the abilities catalogue is adopted its `slots` supersede the sheets' `abilities` (`V-CNF-09`), and the alias table remains only for the balance tools. |
| 21 | **Styled proposals vs bible modifiers (double counting).** The framework already offsets each faction's base stats to compensate its passive modifiers (`modifier_compensation`); the resolver then applies the bible's modifiers on top — correct, but a designer who pastes unstyled numbers into a styled faction, or styles twice, silently shifts balance. | `validate_balance.py` compares every sheet with `balance_calc.py propose … --styled` and warns beyond the framework tolerances (`scaling.tolerances`); the unstyled reference numbers are the archetypes'. |
| 22 | **`global.json` key names are an interface** (`structures`, `defenses`, `superweapons.*`, `carriers`, `support_power_damage`, `movement_defaults`, …). A rename inside the framework silently orphans a loader path. | `V-CNF-05` asserts every consumed key exists with the expected shape; the framework's `validate` gate should assert the same list (CMR-21e); `global.json.version` bump discipline (CMR-21f). |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

1. **core** — constants `SimConfig.TPS: int = 20`, `Fp.CELL: int = 1024`, and **`Fp.TURN: int = 4096`** (angle units per full turn), used by `DefConvert`; static `Log.info/warn/error(tag: String, msg: String)` (the `DefLoadReport` mirrors into it). `src/data` is lint-restricted to `core` + `data` identifiers (L005) and to float-free code outside `def_num_parse.gd` (L003).
2. **core** — `Checksum` should use the same FNV-1a-32 parameters as `DefHash` (offset 2166136261, prime 16777619, 32-bit mask, byte-wise) and expose a `Checksum.seed(with: int)`-style entry so `SimWorld.checksum()` can start from `data.data_hash()`.
3. **abilities** — *class-name and ownership collision* (§2.1): task AB-01 creates `DefAbility`, `DefEffect`, `DefZone` in `src/data`, and this spec defines the same three; keep **one**. Recommendation: this spec's records (§4.2) host both designs (typed core + sorted `params`, `DefEffect.group_mask/fire_mode_mask/frontal_arc_a`, `DefZone` as in §4.2); AB-01 reduces to `DefAbilityCompiler` (a `DefDomainCompiler`, §3.12) that fills them from `abilities.json/aura_classes.json/statuses.json/zones.json/effects.json`; adopt `Cond` codes 2 and 10-22 and the `AbilityKind` ids of §4.1; when `abilities.json → slots` is adopted, sheets stop listing abilities (`V-CNF-09`). Also confirm that `DefLayer3` (§3.7) replaces any parallel research-overlay in `SimAbilitySystem` (one accumulator, one checksum).
4. **sim** — `SimWorld._init(data: GameData, cfg)`; `SimPlayer.roster: DefRoster` and `SimPlayer.view: DefPlayerView` (created at match start: `DefPlayerView.new(data, roster)`; it owns the `DefLayer3`); the specs that ask for `GameData.res(pid)` / `resolved_def(pid, def)` / `pdef(...)` use `world.players[pid].view` (§3.13). `SimWorld.checksum()` mixes `data.data_hash()` first and `p.view.checksum()` for each player in pid order.
5. **sim** — optional `SimWorld.swap_data(new: GameData) -> bool` for the dev hot-swap path (only when `!is_networked && new.is_hot_swap_compatible(data)`).
6. **combat** — weapon numbers that bible modifiers touch (`damage`, `range`, `reload_mt`, `proj_speed`, `hits_per_volley`) must live in `DefWeaponSlot` (or combat's compiled weapon class must **extend** it) so that roster clones carry the resolved values and `DefStatMath` stays the only arithmetic; combat's warhead/projectile/mount tables may add fields but never restate a formula; register `DefCombatCompiler` in `DefCompilers.all()` (CMR-26) and list its files in the manifest. If combat prefers its own weapon numbers plus per-(pid, def) basis points (`presist`, `static_bp`, `tmp_bp`), `DefRoster.static_sums(kind, def, stat)` returns the exact layer sums `[S1, S2]` behind every baked value so that combat can re-fold once with its own base; the recommended default remains the baked slot (no second rounding).
7. **sim/CommandSystem** — validate every def-referencing command with the predicates of §6.2 (`roster.has_unit/has_structure/research_slot/power_slot`, `DefRoster.prereqs_met`, `max_per_player`, `place_mask`, cooldown/credits/`target_vision`); replaced or absent defs are rejected; use the **owner's roster clone** for cost/time.
8. **sim/Production** — call `p.view.apply_research(idx)` on research completion in tick step 2 (players in ascending pid); use `unit.cost`/`build_ticks` and the rate model of §5.8.5 (`progress += rate_bp` until `≥ build_ticks·10000`, `rate_bp = 10000·shortage + Σ PROD_RATE`).
9. **sim/Economy** — read only `data.economy` fields (§4.2) for harvest/unload/repair/refunds/power shortage; repair charging uses `unit.repair_cost_bp` and `structure.repair_rate_bp`; `Collector` and MCV carry `pop 0` (unit-cap exempt); deposits: `neutral.salvage_field` semantics of §7.14.
10. **sim/Combat** — cooldown accumulator on `reload_mt` (absolute `next_fire_mt += reload_mt`, clamp to now when idle); damage only through `DefStatMath.final_damage(raw, bonus_bp, matrix_pct, resist_bp, falloff_pct, eco)` with `data.damage.matrix_pct[dtype*11+armor]`; resistance sums through `DefStatMath.resist_total_bp` (cap 50 %); conditional slot variants via `DefCondVal` (garrison); interception via `DefWeaponSlot.interceptable` (`NONE/TRIDENT/APS_TRIDENT`) and `economy.intercept_packet_*`; suppression via `WF_SUPPRESSIVE` + `economy.suppress_*`; non-lethal types via `damage.nonlethal_mask`; beam ramp via `ramp_t/ramp_max_bp`; read weapon numbers only from `DefWeaponSlot`.
11. **sim/Abilities + Zones** — implement `AbilityKind` 1-34 and `EffectOp` 1-12 semantics on the *converted params* of §7.4/§7.5 (or return an amended registry); evaluate `Cond` codes 2 and 10-22; honour `stack_group` (largest |Δ| per group per entity) and add temporary deltas to research deltas as **one** layer-3 sum (`extra_bp`); use `DefLayer3.cond_effects_of_unit/_struct`, `ability_param`, `struct_ability_param`, `def_param`, `player_param`, `has_flag`, `granted_abilities`; on max-HP change use `DefStatMath.rescale_hp`; SUMMON entities carry `UF_NO_COMBAT_MODS`; movement multiplies `speed × DefMoveTable.speed_bp × water_mult_bp` through `DefMoveTable.effective_speed`.
12. **sim/Vision** — use `unit.sight`, `unit.detect_radius`, `unit.cloak_delay_t` and `economy.detector_default_radius_u`, `camouflage_default_delay_t`.
13. **map** — reconcile `DefEnums.MoveClass` with the pathing classes; map every concrete terrain tile to one of the 8 `TerrainKind`s (TAXONOMY ASSUMPTION(map)); expose `MapData` predicates for `PLACE_SHORELINE` (adjacent navigable water) and footprint placement using `fp_w/fp_h/fp_mask`; the generator places `DefNeutral` indices (deposits, garrisons, substations) with the finite-field sizes of §7.14 and never requires water for baseline economy; hull radius ≥ 0.9 cell ⇒ deep water only (TAXONOMY §6).
14. **net** — lobby carries `GameData.handshake()` (`{format, hash, tables}`), host refuses mismatches with `GameData.diff_handshake`, client resends with `include_files=true` after a refusal; replay header stores `format`, `hash`, `tables["ids"]`; uses `GameData.roster_ids()` / `roster_faction()` / `data_hash()` (method form).
15. **view** — recipe registry: `game/data/recipes/<recipe id>.json` (default recipe id = def id; the directory exists) so `V-REF-02` can check existence; `ViewModelBuilder` must tolerate missing recipes with a placeholder + `Log.warn`; weapon/projectile visuals are chosen from the weapon *archetype* id (`warch.<name>`) and `DefWeaponSlot.proj_kind`.
16. **audio** — `game/data/audio/events.json` listing event ids and `snd.profile.*` profile ids (for `V-REF-02`); the audio domain maps profile → events.
17. **ui** — Field Manual and sidebar use `DefBrowser` / `DefFormat` / `DefRoster.units_produced_by`; show `DefLoadReport.text()` in a dev overlay after a failed hot reload; never read JSON directly.
18. **ai** — use `DefQuery` and roster tables only; treat `pres_ai_role` as a hint; field-name mapping for what the AI spec asks: `DefUnit.speed_water` is provided as a derived cache (effective speed on deep water incl. `deep_speed_bp` and `water_mult_bp`, 0 = cannot enter), `GameData.dmg_matrix_bp` is `GameData.damage.matrix_bp` (derived, `matrix_pct·100`), `stationary_fire` is `UF_FIRE_STATIONARY` / `WF_STATIONARY_FIRE`.
19. **app/tooling (`tools/gd`, `tools/py`)** — `tools/gd run res://tests/tools/data_cli.gd -- --validate|--hash|--dump <kind>|--update-goldens` is the dev CLI (no new `tools/gd` subcommand needed); CI runs `python3 tools/py/sync_bible.py --check`, `python3 tools/py/balance_calc.py validate`, `python3 tools/py/validate_balance.py --strict`, `tools/gd check`, `tools/gd test data`, and `tools/gd linux test data_hash` for the cross-platform golden.
20. **export/build** — `export_presets.cfg` must ship non-resource files: `include_filter="data/*.json,data/*/*.json"` (all three platforms); CI smoke-tests an exported headless binary with `--check-data` (loads `GameData`, prints `data_hash`).
21. **balance framework (`docs/balance`, `tools/py/balance_calc.py`, `global.json`)** — (a) adopt the class map of §2.1 (no `DefBalanceGlobal`/`DefEconomyConsts`/`DefPercentMath`; `DefDamageMath` as combat helpers around the single `DefStatMath.final_damage`) or send amendments; (b) fix `service_units.collector.capacity_credits` (500) to equal `economy.collector.capacity_credits` (600) and assert it in `validate`; (c) `balance_calc.py proposals --styled --json [--faction f]` emitting FRAMEWORK §4.5 sheets and §4.4 weapon instances with ids `weapon.<code>.<name>` (the seed of `units_<code>.json`); (d) let `balance_calc.py check` accept `{"units":[…],"weapons":[…]}` files; (e) keep the `global.json` keys consumed in §7.3 stable and extend `validate` to assert them; (f) bump `version` on every vocabulary change; (g) the file names `game/data/balance/<faction>.json` of FRAMEWORK §7.3 are `units_<code>.json` here.
22. **qa** — a golden-file helper for `TestCtx` (read expected JSON, compare, and rewrite when the test run is started with `--update-goldens`), and `tools/gd linux` printing `GameData.handshake()` for the cross-platform golden test; the existing `TestCtx.eq` type strictness is relied upon (§10).
23. **reconciler** — ARCHITECTURE §3 amendment: "Weapon reload intervals are stored as **milli-ticks** (`reload_mt`, exact `ms·TPS`); all other durations remain ticks (`ceil`)"; create `docs/AMENDMENTS.md` (referenced by ARCHITECTURE §2, not yet present) and record it there.
24. **reconciler** — adopt §5.5 as *the* definition of layered stat math (two-stage half-up rounding, ceil floors, additive layer 3, additive resistance with 50 % cap) so combat/abilities specs reference `DefStatMath` instead of restating formulas; adopt the source map and precedence rules of §7.0 and the collision table of §2.1.
25. **economy** — (a) `DefNeutral` collides with this spec's class (economy: "typed loader of `neutral_structures.json`"): compile into this spec's `DefNeutral` (§4.2) or rename yours (`DefNeutralRules`); (b) decide the authority for the constants of risk 18 (`economy.json` vs `global.json`) and tell the framework owner; (c) register `DefEconCompiler` in `DefCompilers.all()` (CMR-26); (d) `power_actions.json` (§7.10) is a fallback — if `powers.json` recipes are adopted, keep `DefPower.actions` (`DefPowerAction{op, zone, summon, count, radius, duration_t, warning_t, effects, impacts, params}`) as the compile target so `SimPowerFx` reads one shape.
26. **all domains with plug-in compilers (combat, abilities, economy)** — each adds exactly ONE line to `DefCompilers.all()` (sorted by `domain_id`) and lists its files in `game/data/balance/manifest.json`; a compiler may append `DefWeaponSlot`s/`DefAbility`s to common defs only through the fields of §4.2 and reports errors with its own rule-id prefix (`V-CMB-*` combat, `V-AB-*` abilities, `V-ECO-*` economy; `V-ABL-*` is this spec's ability-registry checks).
