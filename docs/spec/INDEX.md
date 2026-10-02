# Spec navigator (generated)

The specs are very large. Do NOT read them whole. Use this index to jump to the sections you need with `sed -n 'START,ENDp' file`.

Each spec follows the 13-heading SPEC FORMAT (1 Purpose, 2 Files/classes, 3 Public API, 4 Data structures/fields, 5 Rules, 6 Commands/events, 7 Data schemas, 8 Determinism, 9 Perf, 10 Tests, 11 Work breakdown, 12 Risks, 13 Cross-module requests).


## docs/spec/abilities.md  (1319 lines, 171 KB)

- L1-6 (6 lines): # MERIDIAN FRACTURE: Abilities, Stealth, Vision, Timed Effects, Zones and Transports (domain spec v2)
- L7-57 (51 lines): ## 1. Purpose & scope
- L58-97 (40 lines): ## 2. Files & classes
- L98-125 (28 lines): ## 3. Public API
- L126-133 (8 lines): # lifecycle. Names follow combat.md 3.2; aliases on_entity_added / on_entity_removed exist for economy's hook 
- L134-137 (4 lines): # timed effects (economy.md ask 17)
- L138-297 (160 lines): # queries: movement / vision / production / AI
- L298-303 (6 lines): # combat (combat.md 3.3 to 3.7)
- L304-305 (2 lines): # economy / power
- L306-308 (3 lines): # data
- L309-313 (5 lines): # sim-core
- L314-479 (166 lines): ## 4. Data structures & fields
- L480-946 (467 lines): ## 5. Rules & algorithms
- L947-1010 (64 lines): ## 6. Commands consumed / events emitted
- L1011-1078 (68 lines): ## 7. Data files & schemas you need
- L1079-1109 (31 lines): ## 8. Determinism notes
- L1110-1152 (43 lines): ## 9. Performance budget
- L1153-1226 (74 lines): ## 10. Test plan
- L1227-1245 (19 lines): ## 11. Work breakdown: agent-sized implementation tasks
- L1246-1301 (56 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1302-1319 (18 lines): ## 13. CROSS_MODULE_REQUESTS

## docs/spec/abilities_catalog.md  (422 lines, 52 KB)

- L1-4 (4 lines): # Meridian Fracture: Ability Catalog (appendix to abilities.md)
- L5-14 (10 lines): ## 0. How to read this file
- L15-55 (41 lines): ## 1. Primitive index
- L56-258 (203 lines): ## 2. Units (156)
- L259-296 (38 lines): ## 2b. Structures (29) and neutral map objects (2)
- L297-341 (45 lines): ## 3. Research (40)
- L342-394 (53 lines): ## 4. Support powers (48)
- L395-407 (13 lines): ## 5. Superweapons (8)
- L408-414 (7 lines): ## 6. CUSTOM and flavor-only rows
- L415-422 (8 lines): ## 7. Verification summary

## docs/spec/ai.md  (2006 lines, 249 KB)

- L1-8 (8 lines): # MERIDIAN FRACTURE — Skirmish AI Specification
- L9-41 (33 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L42-159 (118 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L160-191 (32 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L192-254 (63 lines): ## One instance per match, built by app/ (AppMatch.make_ai_thinker, XR-14). Handed to net as `opts.ai_factory 
- L255-267 (13 lines): # --- players / rules
- L268-274 (7 lines): # --- definitions (DefRoster of the player: modifiers + research already applied)
- L275-292 (18 lines): # --- own entities (ids ascending; the returned array is borrowed: never write, never keep across thinks)
- L293-298 (6 lines): # --- enemies (fog-honoring unless omniscient); results appended ascending by id; return count
- L299-310 (12 lines): # --- rule validators (mirror CommandSystem validation; used to avoid rejected commands)
- L311-317 (7 lines): # --- production / construction state
- L318-349 (32 lines): # --- public map info (treated as public knowledge, T2)
- L350-359 (10 lines): # economy (class 1)
- L360-381 (22 lines): # unit orders (class 2 unless stated; unit lists are chunked to <= 48 ids per command; one order per unit per 
- L382-389 (8 lines): # powers (class 0)
- L390-446 (57 lines): # Module convention (duck-typed; every AiXxx module in 2.4 implements these):
- L447-527 (81 lines): # Returns Q8 ratio (attacker strength / defender strength). See 5.3.4.
- L528-528 (1 lines): ## Drives net's LOCAL pipeline unpaced (speed_pct = 0, max_ticks_per_poll 64..512, auto_clear_events = true) w
- L529-557 (29 lines): ## so the AI runs with the production cadence, sanitisation and input delay. Metrics are read from session.wor
- L558-591 (34 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L592-663 (72 lines): # entity flag bits returned by AiWorldView.e_flags (ASSUMPTION(sim) provides equivalents)
- L664-1444 (781 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1445-1501 (57 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1502-1741 (240 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1742-1757 (16 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1758-1804 (47 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1805-1914 (110 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1915-1935 (21 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1936-1965 (30 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1966-2006 (41 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/art_direction.md  (2017 lines, 227 KB)

- L1-21 (21 lines): # MERIDIAN FRACTURE — Art Direction & Content Style Guide (the visual bible)
- L22-56 (35 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L57-80 (24 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L81-87 (7 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L88-93 (6 lines): # Immutable after load. Not an autoload: App creates it once and injects it.
- L94-165 (72 lines): # Parse + validate. On any violation: push_error("style.json: <json path>: <reason>") and return null.
- L166-174 (9 lines): # ops: Array of ["poly"|"line"|"circle"|"arc", ...] in the unit square (y down), see 5.11.
- L175-185 (11 lines): # ASSUMPTION(render): ViewMeshBuilder exposes brush(), set_part(), prism() as in render.md 3.5 (lifted from pr
- L186-249 (64 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L250-305 (56 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L306-307 (2 lines): # A (preferred, no shader change): send raw sRGB as a Vector4.
- L308-1672 (1365 lines): # B: keep Color but declare the uniform  "instance uniform vec4 u_team : source_color"  and DELETE  v_team = t
- L1673-1716 (44 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1717-1777 (61 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1778-1788 (11 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1789-1846 (58 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1847-1900 (54 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1901-1919 (19 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1920-1967 (48 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1968-2017 (50 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/audio.md  (1753 lines, 227 KB)

- L1-10 (10 lines): # MERIDIAN FRACTURE — Audio Engine & Audio Asset Pipeline (domain spec)
- L11-38 (28 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L39-121 (83 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L122-142 (21 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L143-143 (1 lines): ## One-time init from app boot. Loads + validates game/data/audio/*.json, builds buses (SndBus.setup), creates
- L144-147 (4 lines): ## announcer, music director shell and settings. Returns false only when a *data* error makes audio unusable (
- L148-148 (1 lines): ## Called by the app (or the view's builder) once the battlefield exists AND the game `Camera3D` is current in
- L149-153 (5 lines): ## (spike rule 2; e.g. the `ViewWorld` node after `build_async`). Creates the 3D pool + listener under `world_
- L154-159 (6 lines): ## Match lifecycle. begin_match builds SndSoundBank, requests the needed banks (threaded), starts CALM music +
- L160-160 (1 lines): ## --- per-frame feeds (see 3.2 for order) ---------------------------------------------------------------
- L161-161 (1 lines): ## `batch` = `world.events.take()` of this frame (sim_core §3.7): a flat `PackedInt32Array` of 10-int records
- L162-162 (1 lines): ## `[type, tick, a, b, c, d, e, f, g, h]` (`SimEvent` catalogue). The app takes it ONCE and hands the same arr
- L163-165 (3 lines): ## audio never retains it. `alpha` = view interpolation factor (0..1), unused by events (loops smooth themselv
- L166-166 (1 lines): ## Camera pose, pushed by the app every frame after the view's own frame update (3.2), from the view camera's 
- L167-167 (1 lines): ## focus = ground point under the screen centre (`ViewCamera.current_focus()`); basis = orientation of the gam
- L168-168 (1 lines): ## `listener_transform()`); only its yaw about +Y is used, extracted convention-free as atan2(basis.z.x, basis
- L169-173 (5 lines): ## height = camera height above the focus in metres (`ViewCamera.current_height()`; 34-84 m, wide view 110 m) 
- L174-252 (79 lines): ## --- calls from UI / net / view -------------------------------------------------------------------------
- L253-255 (3 lines): ## Audio space: p' = focus + (p - focus) * inv_scale, inv_scale = 1 / zoom_scale (5.3). Set once per frame by 
- L256-257 (2 lines): ## Level estimate (dB) the voice would have at the listener: def.volume_db + gain + attenuation_db(def, d_eff)
- L258-309 (52 lines): ## Start by id (event lookup) or by def (already resolved). `pitch_mul` multiplies the def's pitch (engine RPM
- L310-317 (8 lines): # --- per weapon_def_idx (the index carried by WEAPON_FIRED / DAMAGE / PROJECTILE_* / BEAM) ---
- L318-326 (9 lines): # --- per entity def idx (single dense space; index = SimEntity.def_idx) ---
- L327-474 (148 lines): # --- powers, superweapons (DefPower / DefSuperweapon idx) ---
- L475-545 (71 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L546-588 (43 lines): # --- bookkeeping owned by SndVoicePool ---
- L589-596 (8 lines): # SndSimBridge candidate table (preallocated, capacity 512; parallel arrays, no per-event objects; the input b
- L597-602 (6 lines): # SndLoopManager
- L603-603 (1 lines): # SndScheduler: capacity 64, sorted by due_ms; item = {due_ms, def, pos, flavour, gain_db, tag}
- L604-606 (3 lines): # SndAnnouncer
- L607-608 (2 lines): # SndCombatMeter
- L609-668 (60 lines): # SndMusicDirector
- L669-1022 (354 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1023-1123 (101 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1124-1464 (341 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1465-1483 (19 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1484-1535 (52 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1536-1635 (100 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1636-1661 (26 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1662-1701 (40 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1702-1753 (52 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/combat.md  (1470 lines, 161 KB)

- L1-9 (9 lines): # MERIDIAN FRACTURE — Combat Domain Specification
- L10-39 (30 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L40-73 (34 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L74-138 (65 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L139-162 (24 lines): # --- methods of SimCombatSystem ---
- L163-226 (64 lines): # --- methods of SimCombatSystem ---
- L227-244 (18 lines): # --- methods of SimCombatSystem ---
- L245-257 (13 lines): # sim_core ---------------------------------------------------------------------------------------------------
- L258-261 (4 lines): # movement ---------------------------------------------------------------------------------------------------
- L262-265 (4 lines): # vision -----------------------------------------------------------------------------------------------------
- L266-268 (3 lines): # power / economy --------------------------------------------------------------------------------------------
- L269-271 (3 lines): # zone system ------------------------------------------------------------------------------------------------
- L272-290 (19 lines): # data -------------------------------------------------------------------------------------------------------
- L291-295 (5 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L296-300 (5 lines): # --- layers / kinds (ASSUMPTION(sim_core); mirrored here, sim_core's numbers win) ---
- L301-308 (8 lines): # --- target filter bits (DefWeapon.target_mask). Structures are KIND_STRUCTURE regardless of layer ---
- L309-311 (3 lines): # --- damage types: FROZEN seed ids (ARCHITECTURE Appendix A); TAXONOMY.md may append ids >= 7, never renumber
- L312-313 (2 lines): # THERMAL is its own id; the "beam family" resistance key covers {DT_BEAM, DT_THERMAL}: GameData.dt_cover_mask
- L314-316 (3 lines): # --- delivery of the primary hit, and damage-class bits carried by every damage INSTANCE ---
- L317-322 (6 lines): # --- resistance / lease filter packing (fits int32) ---
- L323-332 (10 lines): # --- projectile kinds / flags ---
- L333-340 (8 lines): # --- mounts, stances, target sources ---
- L341-344 (4 lines): # --- SimCompCombat.cflags ---
- L345-355 (11 lines): # --- lease stats (SimCombatMods) ---
- L356-358 (3 lines): # --- damage instance flags ---
- L359-365 (7 lines): # --- death ---
- L366-373 (8 lines): # --- air ---
- L374-377 (4 lines): # --- orders / commands (block reservations requested in §13-3) ---
- L378-494 (117 lines): # --- mount state layout inside SimCompCombat.mnt (stride MS = 10) ---
- L495-497 (3 lines): # ---- identity ----
- L498-509 (12 lines): # ---- stance / target  (writers: SimOrderCombat, SimTargeting, SimWeapons) ----
- L510-511 (2 lines): # ---- timestamps (READ by abilities / vision) ----
- L512-514 (3 lines): # ---- statuses ----
- L515-518 (4 lines): # ---- leases ----
- L519-520 (2 lines): # ---- point defence ----
- L521-522 (2 lines): # ---- requests to abilities (written by combat; abilities read, act, and the state shows up in inbox) ----
- L523-524 (2 lines): # ---- inbox (written by movement / abilities EVERY tick before step 8) ----
- L525-526 (2 lines): # ---- wreck (KIND_WRECK only) ----
- L527-528 (2 lines): # ---- dying ----
- L529-534 (6 lines): # ---- per-tick scratch (NOT checksummed; reset lazily by tick stamp) ----
- L535-543 (9 lines): # aircraft
- L544-599 (56 lines): # airfield
- L600-981 (382 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L982-1046 (65 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1047-1224 (178 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1225-1250 (26 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1251-1272 (22 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1273-1359 (87 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1360-1381 (22 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1382-1413 (32 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1414-1470 (57 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/data_balance.md  (2151 lines, 303 KB)

- L1-12 (12 lines): # MERIDIAN FRACTURE — Data, Modifier Resolution & Balance-Schema Spec
- L13-48 (36 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L49-129 (81 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L130-557 (428 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L558-747 (190 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L748-1379 (632 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1380-1405 (26 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1406-1952 (547 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1953-1987 (35 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1988-2023 (36 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L2024-2070 (47 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L2071-2093 (23 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L2094-2122 (29 lines): ## 12. Risks, open questions and your recommended resolution for each
- L2123-2151 (29 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/economy.md  (1868 lines, 223 KB)

- L1-7 (7 lines): # MERIDIAN FRACTURE — Economy, Production, Construction, Research, Support Powers & Superweapons (Domain Spec 
- L8-49 (42 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L50-100 (51 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L101-138 (38 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L139-144 (6 lines): # --- ledger: the ONLY functions that change SimPlayerEcon.credits --------------------------------
- L145-147 (3 lines): # --- unit cap -------------------------------------------------------------------------------------
- L148-153 (6 lines): # --- SimWorld hooks (called synchronously by sim-core; section 3.9) --------------------------------
- L154-159 (6 lines): # --- refinery dock protocol (called by SimOrderHarvest; deterministic FIFO) -------------------------
- L160-164 (5 lines): # --- paid repair primitive (Engineer-class units, wrench, airfield pads) --------------------------
- L165-168 (4 lines): # --- capture -----------------------------------------------------------------------------------------
- L169-176 (8 lines): # --- salvage (African Empire hooks) -------------------------------------------------------------------
- L177-195 (19 lines): # --- read-only queries (UI / AI) -----------------------------------------------------------------------
- L196-202 (7 lines): # --- validation (read-only; identical checks are re-run when the command executes) ------------------
- L203-214 (12 lines): # --- catalog queries for the sidebar / AI --------------------------------------------------------------
- L215-224 (10 lines): # --- internal-but-shared (used by SimStructureLife / strategic) ---------------------------------------
- L225-267 (43 lines): # Fills `out` (caller-owned, reused; no allocation) and returns out.reason (RSN_*, 0 = valid).
- L268-274 (7 lines): # --- validation & AI/UI state ---------------------------------------------------------------------------
- L275-277 (3 lines): # --- packet choke point: ALL strategic damage goes through here -------------------------------------------
- L278-281 (4 lines): # --- player-wide windows (Mobilization Order, Central Priority, Joint Landing, ...) ------------------------
- L282-341 (60 lines): # --- hooks -------------------------------------------------------------------------------------------------
- L342-347 (6 lines): # --- SimEconomySystem (abilities #12, combat 3.8) ---
- L348-350 (3 lines): # --- SimPowerSystem (abilities #10, combat 3.8: "SimPower.is_powered / defense_online") ---
- L351-366 (16 lines): # --- SimProductionSystem / SimStrategicSystem read helpers (AI knowledge layer) ---
- L367-407 (41 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L408-417 (10 lines): # ledger ----------------------------------------------------------------------------------------------
- L418-421 (4 lines): # unit cap ----------------------------------------------------------------------------------------------
- L422-427 (6 lines): # counters (ACTIVE, non-EF_TEMPORARY structures only; index = s_idx) -----------------------------------------
- L428-433 (6 lines): # power ------------------------------------------------------------------------------------------------------
- L434-439 (6 lines): # player-wide queues (head at index 0) -----------------------------------------------------------------------
- L440-443 (4 lines): # rates & knobs ----------------------------------------------------------------------------------------------
- L444-445 (2 lines): # strategic --------------------------------------------------------------------------------------------------
- L446-460 (15 lines): # cached id lists (ascending entity id; maintained by on_entity_added/died) ----------------------------------
- L461-474 (14 lines): # --- structure lifecycle (structures only) ---
- L475-480 (6 lines): # --- capture (capturable structures) ---
- L481-494 (14 lines): # --- collector unit ---
- L495-499 (5 lines): # --- refinery dock (Refinery structures only) ---
- L500-652 (153 lines): # --- engineer-class units ---
- L653-1167 (515 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1168-1251 (84 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1252-1631 (380 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1632-1664 (33 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1665-1683 (19 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1684-1733 (50 lines): ## 10. Test plan (unit / scenario / determinism / visual)
- L1734-1754 (21 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1755-1815 (61 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1816-1868 (53 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/net.md  (1977 lines, 216 KB)

- L1-9 (9 lines): # MERIDIAN FRACTURE — Networking, Lobby & Replays (`docs/spec/net.md`)
- L10-68 (59 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L69-128 (60 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L129-163 (35 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L164-177 (14 lines): ## identity / versions
- L178-193 (16 lines): ## behaviour
- L194-209 (16 lines): ## injected dependencies (net never imports ai/, app/, ui/)
- L210-212 (3 lines): ## Construction. Each returns null on immediate failure (bad options: missing world_builder, roster_ids.size()
- L213-213 (1 lines): ## Skirmish: same launch pipeline, Role.LOCAL, no transport. `lobby` comes from the skirmish setup screen
- L214-215 (2 lines): ## (a NetLobbyState with HUMAN slot 0 = local player, AI/CLOSED elsewhere).
- L216-230 (15 lines): ## Tests/tools: start directly from a finished MatchConfig dictionary.
- L231-243 (13 lines): ## ---- match (valid in PLAYING/PAUSED/ENDED) ----
- L244-346 (103 lines): ## ---- introspection ----
- L347-459 (113 lines): ## Time-sliced world construction so the main thread keeps servicing ENet during map generation.
- L460-470 (11 lines): ## ---- any seated peer: edits ITS OWN slot (host applies directly, clients send LOBBY_ACTION) ----
- L471-537 (67 lines): ## ---- host only ----
- L538-538 (1 lines): ## Runs `ticks` of the same match through (A) the LOCAL net pipeline with scripted commands (and AI if a facto
- L539-540 (2 lines): ## and (B) a fresh world driven by A's recorded replay; compares every checksum snapshot, the input chain, and
- L541-657 (117 lines): ## => {ok:bool, ticks:int, compared:int, first_mismatch_tick:int (-1), chain_a:int, chain_b:int, final_a:int, 
- L658-674 (17 lines): # token buckets (rate/s, burst): INPUT 40/64, PONG 8/16, CHECK 4/8, LOBBY 10/20, CHAT 1/5 (i.e. 5 per 5 s), PA
- L675-1013 (339 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L1014-1014 (1 lines): # presets: lan{0.5,0.3} wifi{10,8,loss 1} bad_wifi{30,25,loss 3} internet{75,15,loss 1} awful{150,60,loss 4}
- L1015-1020 (6 lines): #          raw_chaos{20,15,dup 3,reorder 10, ordered=false} local{0.1,0}
- L1021-1037 (17 lines): # NetLockstep (all peers)
- L1038-1055 (18 lines): # NetTurnHost (host only)
- L1056-1057 (2 lines): # NetDelayPolicy per peer
- L1058-1089 (32 lines): # globals: last_change_ms: int; below_since_ms: int
- L1090-1427 (338 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1428-1549 (122 lines): # host, inside NetLockstep.on_boundary(E, target)          (E = turn about to begin, target = E + D)
- L1550-1602 (53 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1603-1738 (136 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1739-1764 (26 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1765-1794 (30 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1795-1888 (94 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1889-1912 (24 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1913-1943 (31 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1944-1977 (34 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/qa.md  (1506 lines, 259 KB)

- L1-9 (9 lines): # MERIDIAN FRACTURE - Quality Assurance, CI, Packaging & Release (`docs/spec/qa.md`)
- L10-92 (83 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L93-171 (79 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L172-179 (8 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L180-232 (53 lines): # 124 = killed by `gd` (timeout/stall) and 128+n = signal are produced OUTSIDE Godot. 2 and 3 deliberately equ
- L233-264 (32 lines): # Owns the adapters (main and twin), AIs and metrics for its whole duration; closes them before returning on E
- L265-396 (132 lines): # opts: map_family:int = OPEN, map_size:int = 96, rules:Dictionary, ai_levels:Array[int] (per player, -1 = non
- L397-483 (87 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L484-1009 (526 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1010-1050 (41 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1051-1103 (53 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1104-1104 (1 lines): # meridian chain v1 scenario=D01 engine=4.7.2-stable sim_version=1 data_hash=1a2b3c4d
- L1105-1251 (147 lines): # columns: tick checksum input_chain   (checksum and input_chain are u32, lowercase hex, 8 digits)
- L1252-1278 (27 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1279-1298 (20 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1299-1403 (105 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1404-1431 (28 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1432-1468 (37 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1469-1506 (38 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/qa_tooling.md  (183 lines, 18 KB)

- L1-5 (5 lines): # QA & Tooling Manual (agent handbook)
- L6-17 (12 lines): ## 0. Rules of the road
- L18-90 (73 lines): ## 1. Commands
- L91-110 (20 lines): ## 2. Writing tests
- L111-131 (21 lines): ## 3. Lint (`tools/py/lint.py`, run by `gd check`; `--summary`, `--rules L003,L005`, `--list-allows`, `--json`
- L132-144 (13 lines): ## 4. Cross-platform
- L145-165 (21 lines): ## 5. Bible mirror, export, packaging, CI
- L166-183 (18 lines): ## 6. Gotchas discovered

## docs/spec/render.md  (2393 lines, 309 KB)

- L1-13 (13 lines): # MERIDIAN FRACTURE — Render / View Domain Specification
- L14-50 (37 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L51-152 (102 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L153-225 (73 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L226-245 (20 lines): # subsystems (all created in _init, configured in build_async; UI may call their public API)
- L246-341 (96 lines): # ---- queries (UI / audio / AI debug); all O(1) unless stated
- L342-535 (194 lines): # values live in ViewEntity; the rig only forwards them. Writes are skipped when the packed Color equals the c
- L536-600 (65 lines): # op set: §5.8.3. Errors carry the op path "unit.napc.guardian_tank/ops[14]/for[3]/box" and abort the build (p
- L601-748 (148 lines): # primitives used by the recipe interpreter (public so native escape-hatch effects can call them)
- L749-858 (110 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L859-866 (8 lines): # identity (set once, from the SPAWNED payload: the sim entity may already be gone when the event is processed
- L867-868 (2 lines): # backend handle
- L869-870 (2 lines): # visibility
- L871-875 (5 lines): # two-sample snapshot (ints copied from the sim; the kernel stores no previous values, §3.0)
- L876-878 (3 lines): # interpolated placement (world space, floats)
- L879-883 (5 lines): # animation channels (mirror the instance uniforms)
- L884-886 (3 lines): # mirrored gameplay snapshots (ints; refreshed by every sample)
- L887-1003 (117 lines): # fx handles
- L1004-1028 (25 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1029-1034 (6 lines): # placement
- L1035-1037 (3 lines): # ground alignment (MOTION_TRACKED 0.85, WHEELED 0.8, AMPHIBIOUS 0.5, FOOT 0, NAVAL/AIR see below)
- L1038-1042 (5 lines): # channels
- L1043-1044 (2 lines): # dust / wake / contrail: distance accumulators, no per-unit emitter objects
- L1045-1577 (533 lines): # push (only when the packed Color differs from last_*)
- L1578-1667 (90 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1668-2063 (396 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L2064-2090 (27 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L2091-2151 (61 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L2152-2234 (83 lines): ## 10. Test plan (unit / scenario / determinism / visual)
- L2235-2277 (43 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L2278-2317 (40 lines): ## 12. Risks, open questions and your recommended resolution for each
- L2318-2393 (76 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/sim_core.md  (1877 lines, 258 KB)

- L1-10 (10 lines): # Simulation Core — Domain Specification (`sim_core`)
- L11-47 (37 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L48-121 (74 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L122-193 (72 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L194-421 (228 lines): # ---- load-time only (the ONLY place a float touches a sim number; DR-10; lint-allow'ed) ----
- L422-520 (99 lines): # reasons live in SimEvent: CASH_START 0, CASH_HARVEST 1, CASH_SALVAGE 2, CASH_REFUND 3, CASH_SELL 4, CASH_SPE
- L521-521 (1 lines): # lobby schema (net.md 7.1 `rules`):  start_credits 7500 · unit_cap 150 · superweapons 1 · fog 1 · shared_visi
- L522-578 (57 lines): # kernel / dev only (never sent by the lobby):  start_mode 0 · neutral_structures 1 · victory 1 · end_when_no_
- L579-787 (209 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L788-1155 (368 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1156-1421 (266 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1422-1526 (105 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1527-1643 (117 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1644-1688 (45 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1689-1747 (59 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1748-1773 (26 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1774-1830 (57 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1831-1877 (47 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/terrain_movement.md  (1857 lines, 251 KB)

- L1-8 (8 lines): # MERIDIAN FRACTURE — Domain Spec: Terrain, Pathfinding, Movement & Map Generation
- L9-80 (72 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L81-138 (58 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L139-153 (15 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L154-159 (6 lines): # ---- terrain types (byte values stored in MapData.terrain), 16 ----
- L160-162 (3 lines): # ---- TerrainKind (mirror of DefEnums.TerrainKind, TAXONOMY §11; equality asserted at load) ----
- L163-165 (3 lines): # ---- MoveClass (mirror of DefEnums.MoveClass, TAXONOMY §11; equality asserted at load) ----
- L166-171 (6 lines): # ---- nav profiles (a profile = a class with its own weight vector; air and static have none) ----
- L172-200 (29 lines): # ---- terrain flag bits (terrain.json "flags") ----
- L201-206 (6 lines): # ---- static flag bits (MapData.flags) ----
- L207-211 (5 lines): # ---- list strides (public PackedInt32Array fields) ----
- L212-220 (9 lines): # ---- identity (sim_core R7 names) ----
- L221-238 (18 lines): # ---- construction / lifecycle ----
- L239-246 (8 lines): # ---- coordinates ----
- L247-251 (5 lines): # ---- terrain, kinds, speeds ----
- L252-263 (12 lines): # ---- predicates used by other domains (all O(1), all pure) ----
- L264-269 (6 lines): # ---- structures (called by production/economy/cleanup) ----
- L270-281 (12 lines): # ---- deposits (economy; per-cell stock, FRAMEWORK §5.8) ----
- L282-443 (162 lines): # ---- view layers (read-only; render.md §13-9; not in map_hash) ----
- L444-456 (13 lines): # ---- primitives named by combat.md 3.8 / economy.md 13-15 ----
- L457-469 (13 lines): # ---- goals (return false and set result RS_* if refused: RS_IMMOBILE for a deployed/packing unit — the call 
- L470-478 (9 lines): # ---- status (read by handlers, combat, AI, view) ----
- L479-589 (111 lines): # ---- air primitives (combat.md 3.8 / 13-23) ----
- L590-648 (59 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L649-652 (4 lines): # ---- movement state (SimMoveComp.state) ----
- L653-655 (3 lines): # ---- flags (SimMoveComp.flags bit set; the entity-level mirrors are SimFlags F_MOVING/F_AIRBORNE/F_BLOCKED/F
- L656-658 (3 lines): # ---- goal kinds ----
- L659-661 (3 lines): # ---- result codes (SimMoveComp.result) ----
- L662-663 (2 lines): # ---- opts bits for SimMovement.go_* ----
- L664-665 (2 lines): # ---- turn modes ----
- L666-667 (2 lines): # ---- separation hash layers ----
- L668-669 (2 lines): # ---- air modes (SimMoveComp.air_mode) ----
- L670-682 (13 lines): # ---- speed / geometry constants ----
- L683-698 (16 lines): # ---- path service budgets (per tick, all counts; §5.3.5) ----
- L699-702 (4 lines): # --- profile copy: derived from SimMoveProfiles[def_idx] at on_spawn (exempt: recomputed from the def) ---
- L703-708 (6 lines): # --- dynamic state ---
- L709-713 (5 lines): # --- goal and path ---
- L714-716 (3 lines): # --- stuck / blocking ---
- L717-719 (3 lines): # --- scripted glide and layer change ---
- L720-765 (46 lines): # --- aircraft (unused = 0 for ground) ---
- L766-879 (114 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L880-1390 (511 lines): # inner loop (locals cached: wgt, node_of, g, vis, closed, parent, head, e_node, e_next, e_g, col, row, STEP_O
- L1391-1425 (35 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1426-1474 (49 lines): # SimOrderMove (T_MOVE) -- the whole handler, condensed
- L1475-1574 (100 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1575-1606 (32 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1607-1670 (64 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1671-1751 (81 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1752-1776 (25 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1777-1811 (35 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1812-1857 (46 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/spec/ui.md  (3795 lines, 479 KB)

- L1-10 (10 lines): # MERIDIAN FRACTURE — UI/UX, Input, Screens & App Shell (`docs/spec/ui.md`)
- L11-96 (86 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L97-283 (187 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L284-322 (39 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L323-323 (1 lines): # ---- autoload scripts have NO class_name; initialise lazily (measured E1) ----------------------------------
- L324-372 (49 lines): # game/src/app/app_settings.gd   (autoload "AppSettings")
- L373-385 (13 lines): # ---- flow --------------------------------------------------------------------------------------------------
- L386-396 (11 lines): # game/src/app/app_state.gd      (autoload "AppState")
- L397-412 (16 lines): # game/src/app/app_scenes.gd     (autoload "AppScenes")
- L413-423 (11 lines): # game/src/app/app_net.gd        (autoload "AppNet", process_priority = -100, process_mode ALWAYS)
- L424-424 (1 lines): # _process(): if session != null: var t := session.poll(); if match_ctx != null and phase in PLAYING/PAUSED/EN
- L425-426 (2 lines): #             OS.low_processor_usage_mode is forced false while is_multiplayer() (net.md R10)
- L427-482 (56 lines): # ---- match glue --------------------------------------------------------------------------------------------
- L483-559 (77 lines): # ---- boot, logging, crash ----------------------------------------------------------------------------------
- L560-579 (20 lines): # ---- time / identity ---------------------------------------------------------------------------------------
- L580-587 (8 lines): # ---- viewer economy ----------------------------------------------------------------------------------------
- L588-600 (13 lines): # ---- entities ----------------------------------------------------------------------------------------------
- L601-618 (18 lines): # ---- production / research (viewer) ------------------------------------------------------------------------
- L619-630 (12 lines): # ---- support powers / superweapon (viewer) -----------------------------------------------------------------
- L631-633 (3 lines): # ---- map ---------------------------------------------------------------------------------------------------
- L634-655 (22 lines): # ---- events (called by AppEvents only) ---------------------------------------------------------------------
- L656-670 (15 lines): # ---- camera (UI-driven) ------------------------------------------------------------------------------------
- L671-678 (8 lines): # ---- picking (ViewPicker: hidden-by-fog, contained and camouflaged entities are never returned) ------------
- L679-690 (12 lines): # ---- interaction visuals owned by the view -----------------------------------------------------------------
- L691-693 (3 lines): # ---- minimap sources (the widget itself is UiMinimap) ------------------------------------------------------
- L694-700 (7 lines): # ---- icons, models, backdrops (ViewIconBake / ViewModelBuilder) --------------------------------------------
- L701-727 (27 lines): # ---- quality, palette, accessibility -----------------------------------------------------------------------
- L728-728 (1 lines): # UiNetPortSession: forwards to NetSession (the pid is stamped by net from the connection; sim_core v2.1 §4.8 
- L729-729 (1 lines): # UiNetPortRecorder: appends every submitted array to `sent: Array[PackedInt32Array]` (tests compare UiCmdCode
- L730-748 (19 lines): # UiNetPortNull: can_submit() == false (observers, replays, main-menu showcase)
- L749-931 (183 lines): # UiAudioPortSnd forwards to the `Snd` autoload; UiAudioPortNull ignores everything; UiAudioPortRecorder recor
- L932-1236 (305 lines): # typed helpers used by widgets and tests (each builds the array through UiCmdCodec, pre-validates per 5.8.4, 
- L1237-1754 (518 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L1755-3020 (1266 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L3021-3240 (220 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L3241-3419 (179 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L3420-3443 (24 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L3444-3502 (59 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L3503-3626 (124 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L3627-3662 (36 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L3663-3711 (49 lines): ## 12. Risks, open questions and your recommended resolution for each
- L3712-3795 (84 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/balance/FRAMEWORK.md  (1434 lines, 133 KB)

- L1-13 (13 lines): # MERIDIAN FRACTURE — Balance Framework (v1)
- L14-65 (52 lines): ## 1. Purpose & scope (what you own; what you explicitly do NOT own)
- L66-88 (23 lines): ## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECT
- L89-95 (7 lines): ## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memo
- L96-134 (39 lines): ## Immutable, integer-only view of game/data/balance/global.json. Built once by GameData; shared read-only by 
- L135-135 (1 lines): ## Parse and validate. Returns null (after push_error naming the offending key) if any table is malformed, any
- L136-136 (1 lines): ## any matrix cell is outside 0..200, or any bible anchor is violated (start credits 7500, Generator 600/25 s/
- L137-139 (3 lines): ## resist cap 50, floors 60/60/50, build radius 8, superweapon 5000/90 s/-200). Never partially loads.
- L140-146 (7 lines): ## O(1) matrix lookup. Preconditions: 0 <= dtype < DAMAGE_TYPE_COUNT, 0 <= armor < ARMOR_CLASS_COUNT (asserted
- L147-203 (57 lines): ## Load-time only (string ids appear in data files, never in the sim).
- L204-204 (1 lines): ## Single-rounding pipeline. raw >= 0 per-hit weapon damage; bonus_bp = product of weapon-damage bonuses (1000
- L205-205 (1 lines): ## matrix_pct = DefBalanceGlobal.damage_pct(); res_pct = SUM of applicable bible resistances (capped here); fa
- L206-208 (3 lines): ## Returns 0 if any factor is 0, else max(1, half_up(raw * bonus_bp * matrix * (100 - min(50, res)) * falloff 
- L209-210 (2 lines): ## Splash falloff: 100 at edge_dist 0, linearly down to edge_pct at radius; 0 beyond. All args in sim units. I
- L211-212 (2 lines): ## Health after a hit: non-lethal types clamp at 1.
- L213-214 (2 lines): ## Beam focus ramp as a bonus_bp factor: 10000 at focus 0, ramp_max_pct*100 at focus >= ramp_ticks.
- L215-223 (9 lines): ## Projectile flight time in ticks: ceil(distance_units / speed_upt), min 1; hitscan (speed 0) returns 0.
- L224-245 (22 lines): ## One layer step of the bible rule: acc' = half_up(acc * (10000 + layer_delta_sum_bp) / 10000). Start with ac
- L246-400 (155 lines): ## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)
- L401-1163 (763 lines): ## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each b
- L1164-1179 (16 lines): ## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for tho
- L1180-1326 (147 lines): ## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)
- L1327-1338 (12 lines): ## 8. Determinism notes (DR-x compliance; what enters the checksum)
- L1339-1348 (10 lines): ## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)
- L1349-1380 (32 lines): ## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)
- L1381-1395 (15 lines): ## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files 
- L1396-1417 (22 lines): ## 12. Risks, open questions and your recommended resolution for each
- L1418-1434 (17 lines): ## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

## docs/balance/TAXONOMY.md  (354 lines, 27 KB)

- L1-10 (10 lines): # MERIDIAN FRACTURE — Balance Taxonomy (v1)
- L11-19 (9 lines): ## 1. Design intent in one paragraph
- L20-47 (28 lines): ## 2. Damage types (7)
- L48-74 (27 lines): ## 3. Armor classes (11)
- L75-137 (63 lines): ## 4. Damage matrix (integer percent)
- L138-169 (32 lines): ## 5. Resistances and damage modifiers (bible text → pipeline)
- L170-190 (21 lines): ## 6. Size classes
- L191-201 (11 lines): ## 7. Layers and target sets
- L202-226 (25 lines): ## 8. Movement classes and terrain
- L227-283 (57 lines): ## 9. Role archetypes (32) and bible role tags
- L284-330 (47 lines): ## 10. Weapon archetypes (27)
- L331-347 (17 lines): ## 11. Enumerations with frozen integer values
- L348-354 (7 lines): ## 12. Change control
