# MERIDIAN FRACTURE — Networking, Lobby & Replays (`docs/spec/net.md`)

> Domain architect: **Networking / lobby / replays**. Binding parent: `docs/ARCHITECTURE.md` (wins on conflict, except where §13 (XR-20) requests an explicit amendment).
> Engine: Godot 4.7.2 stable, GDScript only. Targets: Windows x86_64, Debian/Linux x86_64, macOS universal.
> **Evidence base.** Every engine claim below was checked either in `tools/godot_docs` (class XML) or by running the real 4.7.2 binary (experiments E1-E10, listed in §5.1), and the lockstep algorithm was validated in a virtual-time prototype (host + 3 clients, jitter/loss/drift/freeze/pause/drop; 0 checksum mismatches in every run). Numbers marked *(measured)* or *(prototype)* come from those runs.
> Assumptions about other domains are tagged `ASSUMPTION(domain)`; they are collected as numbered requests `[XR-n]` in §13.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**One-paragraph architecture.** Meridian Fracture multiplayer is *deterministic lockstep over a star topology*. Every peer (host included) runs the identical headless `SimWorld`; only **commands** (int arrays) cross the network. Time is divided into **turns of 2 ticks (100 ms)**. Each human sends one `TURN_INPUT` per turn (empty = heartbeat) addressed to turn `T + D` (`D` = adaptive **input delay**, default 2 turns = 200 ms). The **host closes turn N into a `TURN_BUNDLE`** once every active human's input for N (and the host's AI injections) is present, and relays that bundle to all peers; a peer executes turn N only when bundle N is in hand (the *barrier*). The host is authoritative for **command order and turn assignment only**; it never simulates on anyone's behalf and never validates game semantics (each peer's `CommandSystem` validates deterministically). The transport is Godot's **`ENetConnection` / `ENetPacketPeer`** (reliable ordered channels), LAN discovery is **UDP broadcast** with a directed-broadcast candidate set, and **single-player uses the same pipeline with no sockets** (`Role.LOCAL`).

```
  Client B                          HOST H (also a player, runs AI)                      Client C
  boundary E: fill-up               collects inputs, closes bundles in order              boundary E: fill-up
  TURN_INPUT(turn E+D) ----------->                                  <------------------- TURN_INPUT(turn E+D)
                                    barrier: all humans present for N? + host AI/local injection reached N?
                                    close TURN_BUNDLE(N) = groups by pid ascending (+ AI, + T_RESIGN, + ctrl records)
  <------------------ TURN_BUNDLE(N) --------------- broadcast --------------------------> TURN_BUNDLE(N)
  every peer executes bundle N at its own boundary N (barrier: no bundle => wait), submit -> step, step
  every 20 ticks: CHECKSUM_REPORT(tick, sim checksum, input chain) ---> host compares ---> DESYNC_NOTICE if different
```

### 1.1 What this module owns
* All of `game/src/net/*` (file list in §2): transport abstraction (ENet, in-memory loopback, fault injection), wire codec, lockstep runner, host turn assembler, adaptive input delay, stall/drop/pause/speed control, lobby data model + lobby protocol, launch (config -> load -> ack -> start) handshake, LAN discovery, desync detection + diagnostics, replay recorder/player/autosave, determinism self-test, host-side AI runner hookup, security limits for all remote input.
* The **MatchConfig JSON schema** (§7.1) as the single authoritative description of a match (lobby output, replay header, `SimWorld` input).
* Persistent files in `user://replays/`, `user://desync/`, `user://logs/net*.log`.
* Tests and harnesses under `game/tests/net/**` and `game/tests/fixtures/net/**`; lobby option data `game/data/net/lobby_options.json`.
* The net-reserved sim command type range and its single injected command `T_RESIGN` (§6.1).

### 1.2 What this module does NOT own
| Not owned | Owner | Interface used |
|---|---|---|
| `SimWorld`, command vocabulary/validation, checksum computation, state dump | sim | `NetSimAdapter` (§3.3) — a thin seam so net compiles and is testable against `NetSimAdapterFake` before sim exists |
| Map generation, map content hash, start-position layout | map | `NetWorldJob` (§3.3) + `map_validator` callable |
| AI brains and difficulty semantics | ai | injected `ai_factory` callable (net must not depend on `ai/`; ARCHITECTURE §5) |
| Lobby / HUD / stall / desync / replay screens, chat rendering, colour palette art | ui | `NetLobby`/`NetSession` signals + state objects (§3) |
| Autoload wiring, settings persistence (`user://settings.cfg`), world-building composition, export presets | app / build | `NetSessionOptions` (§3.1), keys in §7.3, requests [XR-14][XR-15] |
| Roster definitions, data hash | data | `roster_ids` list + `data_hash` injected via `NetSessionOptions` |
| Test runner, `tools/gd`, Linux container runs | qa | conventions in §10 |
| **Out of scope for v1** | — | Internet play/NAT traversal/matchmaking, accounts, anti-map-hack (unavoidable in lockstep), voice, save/load games (replays only), host migration, mid-match rejoin of a dropped human (documented path in §12: replay catch-up) |

### 1.3 Decisions that reconcilers must know (summary)
1. **`ENetConnection` directly, not `ENetMultiplayerPeer`/`SceneMultiplayer`/RPC** (amends ARCHITECTURE §9 wording; same ENet library) — §5.1.
2. **Host relays *bundles*, not individual inputs.** Clients never talk to each other. Order authority = bundle group order (pid ascending, then submission order).
3. **Fill-up rule**: at every turn boundary each human sends packets for every turn up to `E + D` (gap turns empty). This makes input-delay changes trivial and keeps every player's packet stream gap-free (§5.5.3).
4. **Adaptive `D`** from RTT + jitter + observed slack/stalls with hitch quarantine (a 3 s freeze must *not* raise everyone's latency for a minute) — §5.5.6, validated by prototype.
5. **Two independent divergence detectors**: `input_chain` (net layer; proves every peer executed identical command streams) and `SimWorld` checksum (sim layer). *chain equal + checksum differs => simulation nondeterminism; chain differs => netcode/serialisation bug.* This split is the main diagnostic.
6. **`MatchConfig` is a plain JSON dictionary** (ints/strings/bools only, canonical key order); replay header == network launch payload == `SimWorld` input.
7. **The single-player path is `Role.LOCAL` of the same `NetSession`** (no sockets, `D_min = 1`), and skirmish setup reuses `NetLobbyState`.
8. Everything that touches remote bytes goes through a bounds-checked `NetReader`; no `bytes_to_var`/`str_to_var`/`Expression`/`load()` of remote data anywhere; JSON only for the size-capped launch config, schema-whitelisted.

### 1.4 Alignment with the specs published concurrently (ai, data_balance, economy, combat, abilities; checked at 14:15)

| Topic | What the other spec says | What this spec does |
|---|---|---|
| AI contract | `ai.md` builds on `ai_factory(pid, level, style, seed) -> Callable(world, out)`, `AiFactory.level_count/style_count/level_handicap_pct`, phase-staggered cadence, requests per-level periods `[5,3,2,1]` (13.16) | Adopted verbatim: §5.6 (`opts.ai_think_period`, `ai_default_handicap`, `ai_release`, CPU governor) |
| Handicap / income | `ai.md` uses `handicap_pct` (Brutal 120) but its item 7 still lists `income_bp` and `ai = {difficulty, seed_salt}` | `handicap` percent is the only per-player economy knob (§5.3.6, XR-9: sim converts to `income_bp = handicap * 100`); `players[].ai = {level, style, flags}`; the thinker seed is derived by net, so no `seed_salt`. `ai.md` items 7 and 16 are superseded |
| Data handshake | `data_balance.md` §5.11: net carries `GameData.handshake()` (`format`, `hash`, 16 `tables`, optional `files`) and shows `diff_handshake`; replays store `format`, `hash`, `tables["ids"]` | Adopted: `JOIN_REQUEST` table/file hashes, `DATA_DIFF` (§5.3.1), `MatchConfig.versions.data_format/data_ids`, soft/hard replay gate (§5.8) |
| Match rules | `economy.md` reads `MatchRules.start_credits/unit_cap/superweapons`; `abilities.md` reads `MatchRules.fog`, `vision_stride`, `vision_budget` and requires them identical on all clients | `rules` is schema-driven (`rules_schema` in `lobby_options.json`, §7.1/§7.2) with exactly these keys, host-chosen; snapshot and config carry them generically |
| Commands | `economy.md` assumes `SimCommand{type,pid,seq,ids,a..e}` with blocks of 100 per domain (economy 100-199, abilities 100-119 overlap — a reconciler item, not net's); `combat.md` uses `CMD_*` 40..47; `combat.md` has `CAUSE_RESIGN = 5` | Net is agnostic: commands are `PackedInt32Array [type, args...]` (XR-2); net-reserved block `240..255` with `T_RESIGN = 250`; sim decides the `SimCommand` <-> ints mapping |
| Validation | `economy.md`: every command is re-validated in the sim because the network is untrusted; `cmd.pid` must equal the authenticated sender | Same principle: host stamps the pid; no pid on the wire |
| Test convention | `data_balance.md` uses `func run(t: TestCtx)`; the QA runner discovers `test_*` methods and still accepts `run` | This spec uses `func test_*(t: TestCtx)` |
| Match end | `economy.md`/`combat.md`: victory evaluation lives in sim-core cleanup | XR-6: `is_match_over()/match_result()/is_player_active()` |

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All under `game/src/net/`, one class per file, `Net*` prefix, snake_case file names. `net` may depend on `core`, `data`, `map`, `sim` only (never `ai`, `view`, `ui`, `app`).

| File | `class_name` | Responsibility |
|---|---|---|
| `net_protocol.gd` | `NetProtocol` | Constants, enums (integer values), limits, per-message permission table, FNV-1a, `mix32`, `lobby_rand`, text sanitising, reject/kick text helpers |
| `net_writer.gd` | `NetWriter` | Append-only little-endian byte builder (`u8/u16/u32/i16/varint/zvarint/str/bytes`) |
| `net_reader.gd` | `NetReader` | Bounds-checked cursor with sticky `ok` flag; never raises engine errors on malformed input |
| `net_codec.gd` | `NetCodec` | Static encode/decode of handshake, turn, control, checksum, pause/stall, catch-up messages; canonical turn core bytes |
| `net_lobby_codec.gd` | `NetLobbyCodec` | Static encode/decode of lobby snapshot/action/chat/launch messages; config deflate/inflate |
| `net_bundle.gd` | `NetBundle` | Immutable-after-build decoded turn bundle (groups, ctrl records, canonical core bytes, hash) |
| `net_clock.gd` | `NetClock` | Monotonic microsecond time source: real (`Time.get_ticks_usec`) or manual (tests/virtual time) |
| `net_transport_event.gd` | `NetTransportEvent` | One transport event (`CONNECTED`, `DISCONNECTED`, `PACKET`) |
| `net_transport.gd` | `NetTransport` | Abstract peer-id-based reliable transport API (§3.2) |
| `net_transport_enet.gd` | `NetTransportEnet` | `ENetConnection` implementation: port scan, dual-stack bind, timeouts, connect timeout, per-peer stats |
| `net_loopback_hub.gd` | `NetLoopbackHub` | In-process message switch connecting several `NetTransportLoopback` endpoints |
| `net_transport_loopback.gd` | `NetTransportLoopback` | Socket-free transport (unit tests, virtual-time scenarios) |
| `net_fault_profile.gd` | `NetFaultProfile` | Latency/jitter/loss/dup/reorder/freeze/bandwidth profile + named presets |
| `net_transport_fault.gd` | `NetTransportFault` | Decorator that applies a `NetFaultProfile` to any `NetTransport` under a `NetClock` |
| `net_peer_stats.gd` | `NetPeerStats` | Per-peer RTT/jitter/loss/bytes counters (smoothed) |
| `net_rate_limiter.gd` | `NetRateLimiter` | Token bucket + violation score used per peer |
| `net_peer_info.gd` | `NetPeerInfo` | Host-side record of one remote connection (address, handshake state, slot/pid, limiter, stats) |
| `net_sim_adapter.gd` | `NetSimAdapter` | Seam between net and the simulation (§3.3) |
| `net_sim_adapter_world.gd` | `NetSimAdapterWorld` | Adapter over the real `SimWorld` (ASSUMPTION(sim) names; the only file to touch if sim renames APIs) |
| `net_sim_adapter_fake.gd` | `NetSimAdapterFake` | Deterministic hash-only fake sim used by net tests, harness and CI before/without sim (algorithm fixed in §10.2, with golden values) |
| `net_world_job.gd` | `NetWorldJob` | Time-sliceable "build the world from config" job interface + sync wrapper |
| `net_lockstep.gd` | `NetLockstep` | Pacing accumulator, barrier, turn execution, fill-up rule, input chain, checksum snapshots (host and clients) |
| `net_turn_host.gd` | `NetTurnHost` | Host-only: input collection, contiguity/ooo/dup handling, bundle closing, stall report, pause/speed/drop/AI-takeover state |
| `net_delay_policy.gd` | `NetDelayPolicy` | Adaptive input-delay controller (RTT/jitter/slack/stall, hitch quarantine) |
| `net_ai_runner.gd` | `NetAiRunner` | Host-side scheduler that calls injected AI thinkers and turns their output into pid groups for a target turn |
| `net_lobby_state.gd` | `NetLobbyState` | Lobby data model (map, rules, 8 slots, spectators, revision) + validation helpers |
| `net_player_slot.gd` | `NetPlayerSlot` | One slot (`CLOSED/OPEN/HUMAN/AI`, roster, team, colour, start, handicap, ready, ...) |
| `net_match_config.gd` | `NetMatchConfig` | Build/normalise/validate/canonicalise the MatchConfig dictionary; lobby -> config; random resolution |
| `net_lobby.gd` | `NetLobby` | Lobby protocol logic (host authority, client mirror), permissions, chat, kick/ban, start validation, countdown |
| `net_discovery.gd` | `NetDiscovery` | LAN announce (broadcast candidates) + browse (bound listener), expiry, circuit breaker |
| `net_discovery_entry.gd` | `NetDiscoveryEntry` | One discovered game (address, port, name, players, hashes, last-seen) |
| `net_session_options.gd` | `NetSessionOptions` | All injected dependencies and tunables (§3.1) |
| `net_session.gd` | `NetSession` | Façade + phase state machine + message router + per-frame `poll()`; the only class `app/ui` drive |
| `net_launch.gd` | `NetLaunch` | Launch handshake orchestration (countdown, config broadcast, load, ack collection, start/abort) |
| `net_desync.gd` | `NetDesync` | Checksum/chain exchange, comparison, sub-checksum localisation, diagnostic package writer |
| `net_self_test.gd` | `NetSelfTest` | Determinism self-test (same match twice / net vs replay) |
| `net_replay.gd` | `NetReplay` | Static: replay format constants, paths, autosave rotation, crash recovery, metadata listing |
| `net_replay_data.gd` | `NetReplayData` | Parsed replay (header, turn index, checks, parts, events, end, flags) with tolerant loader |
| `net_replay_recorder.gd` | `NetReplayRecorder` | Append-only recorder (file or memory), periodic flush, finalise |
| `net_replay_player.gd` | `NetReplayPlayer` | Playback runner: speed, pause, seek by re-simulation, checksum verification |

Other files owned by this domain:

| Path | Purpose |
|---|---|
| `game/data/net/lobby_options.json` | Lobby option tables (§7.2) |
| `game/tests/net/test_net_*.gd` | Unit/scenario tests (§10) — discovered by the QA runner (`test_*.gd`, `func test_*(t: TestCtx)`) |
| `game/tests/net/net_harness.gd`, `selftest_main.gd`, `desync_diff.gd`, `make_replay_fixture.gd` | Runnable scripts (not `test_*`, so not auto-discovered) |
| `game/tests/net/profiles.json`, `game/tests/net/scripts/*.json` | Fault profiles, scripted command files |
| `game/tests/fixtures/net/replays/*.mfreplay` | Golden replays for cross-platform verification |
| `tools/py/net_two_process.py` | Orchestrator (host + N client processes) — **requested from the tooling owner** [XR-18] |

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Conventions: `##` doc-comments are part of the contract. All ints are GDScript 64-bit ints; wire widths are stated in §4. `Error` = Godot `Error` enum. Every method that takes remote-derived data is *total*: it returns an error code/`null`, never raises an engine error.

### 3.0 Integration contract (frame order and memory ownership)

```
app autoload  _process(delta):                     # delta is NOT used by net (NetClock is monotonic wall time)
    var ticks: int = session.poll()                 # 1 call per rendered frame, before view/ui update
    # view/ui/audio: read session.world() (read-only), drain world.events, interpolate with session.tick_alpha()
    # headless runners set opts.auto_clear_events = true so the session clears events itself
```

Fixed order inside `NetSession.poll()` (must not be reordered; each step is O(work available), never blocking):

| # | Step | Notes |
|---|---|---|
| 1 | `now = clock.now_us()` | single time sample for the whole poll |
| 2 | `discovery.poll()` | only if announcing/browsing |
| 3 | `transport.poll()`; drain `take_events()`; dispatch (cap 256 events per poll; remainder next frame) | decode -> permission/rate check -> handler |
| 4 | `launch.step(now, budget_us = 4000)` | time-sliced world build (`NetWorldJob.step`) while `LOADING`; keeps ENet serviced |
| 5 | host: `turn_host.close_ready()`; send bundles; feed the local `NetLockstep` | |
| 6 | `lockstep.update()` -> 0..`MAX_TICKS_PER_POLL`(8) sim ticks | at each turn boundary: apply bundle, **fill-up send**, host AI injection, checksum snapshots |
| 7 | host: `turn_host.close_ready()` again | local fill-up may complete a turn: saves one frame of latency |
| 8 | timers: ping, stall info, lobby snapshot coalescing, delay policy, timeouts, replay flush | |
| 9 | `transport.flush()` | packets created this frame leave this frame |

Re-entrancy: signals are emitted synchronously from inside `poll()`. A handler may call any other public method (`host_start()`, `submit_command()`, `lobby.*`), but `shutdown()`/`leave()` called from a handler is *deferred* to the end of the current `poll()`, and `poll()` itself must never be called re-entrantly (asserted in debug builds).

Ownership: `NetSession` owns every component and the `NetSimAdapter`/world; components never hold a strong reference back to `NetSession` (they use `Callable`s), so `shutdown()` (idempotent) is enough to break cycles. `take_events()` transfers ownership of the returned array. `NetBundle` and `NetReplayData` are immutable after construction. `NetLobbyState` is owned by `NetLobby`; UI code must treat it as read-only (mutations only through `NetLobby` methods) — use `state.duplicate_state()` if a stable copy is needed. `PackedByteArray`/`PackedInt32Array` arguments are copied on write by the engine; no method retains a caller's array by reference except where stated.

### 3.1 `NetSessionOptions` and `NetSession`

```gdscript
class_name NetSessionOptions extends RefCounted
## identity / versions
var player_name: String = "Commander"        # sanitised by NetProtocol.sanitize_name
var game_version: String = ""                # ProjectSettings application/config/version
var sim_version: int = 0                     # SimConfig.SIM_VERSION            [XR-8]
var data_hash: int = 0                       # GameData.data_hash (u32); must equal data_handshake.call(false)["hash"]   [XR-11]
var data_handshake: Callable = Callable()    # (include_files: bool) -> Dictionary  = GameData.handshake: {format:int, hash:int, tables:{String->int}, files?:{String->int}}   [XR-11]
var data_diff: Callable = Callable()         # (local: Dictionary, remote: Dictionary) -> PackedStringArray = GameData.diff_handshake (sorted, human readable)
var roster_ids: PackedStringArray = PackedStringArray()   # sorted, exactly the 32 playable roster ids (GameData.rosters[i].id)
var color_count: int = 12
var ai_level_count: int = 4                  # AI levels 0..n-1                 [XR-13]
var ai_style_count: int = 4                  # AI styles 0..n-1                (AiFactory.style_count())
var ai_default_handicap: Callable = Callable()   # (level: int) -> int, optional = AiFactory.level_handicap_pct: lobby default handicap of an AI slot (Brutal = 120)
var ai_think_period: Callable = Callable()   # (level: int) -> int turns between thinks, optional = AiFactory.think_period_turns (AI spec request 13.16: [5, 3, 2, 1] for Easy..Brutal); default NetProtocol.AI_THINK_PERIOD_TURNS
var ai_release: Callable = Callable()        # (pid: int) -> void, optional = AiFactory.release: called by NetAiRunner.remove_ai and at match end
## behaviour
var port: int = NetProtocol.DEFAULT_PORT
var password: String = ""                    # "" = open. Casual barrier only (§5.12)
var allow_spectators: bool = true
var dedicated: bool = false                  # host has no local slot and no local input (headless host / tests)
var discovery_enabled: bool = true
var min_input_delay_turns: int = NetProtocol.D_MIN_LAN   # local sessions force NetProtocol.D_MIN_LOCAL
var fixed_input_delay_turns: int = 0         # > 0 disables adaptation (golden replays, deterministic tests)
var auto_clear_events: bool = false
var record_replay: bool = true
var record_chat: bool = true                # chat lines stored as replay EVENT records
var replay_autosave_count: int = 3
var allow_solo: bool = false                 # dev/testing: start with a single active player
var countdown_s: int = 3
var speed_pct_override: int = -1             # -1 = use MatchConfig.net.speed_pct; 0 = UNPACED (headless soak/tests: ignore the wall-clock accumulator, run up to max_ticks_per_poll ticks per poll, barrier still enforced); 50..200 = force
var max_ticks_per_poll: int = NetProtocol.MAX_TICKS_PER_POLL   # unpaced runs raise this (64-512; the AI soak harness uses it)
## injected dependencies (net never imports ai/, app/, ui/)
var clock: NetClock = null                   # null -> NetClock.real()
var transport_factory: Callable = Callable() # () -> NetTransport; null Callable -> NetTransportEnet
var world_builder: Callable = Callable()     # (config: Dictionary) -> NetWorldJob      [XR-14]
var ai_factory: Callable = Callable()        # (pid:int, level:int, style:int, rng_seed:int) -> Callable   [XR-13]
var map_validator: Callable = Callable()     # (family:int, size:int, layout_players:int) -> String ("" = valid)   [XR-12]
var log_sink: Callable = Callable()          # (level:int, text:String) -> void; null -> core Log
```

```gdscript
class_name NetSession extends RefCounted

enum Role { NONE = 0, HOST = 1, CLIENT = 2, LOCAL = 3 }
enum Phase { IDLE = 0, CONNECTING = 1, LOBBY = 2, COUNTDOWN = 3, LOADING = 4, WAIT_START = 5,
             PLAYING = 6, PAUSED = 7, ENDED = 8, DESYNCED = 9, DISCONNECTED = 10 }

## Construction. Each returns null on immediate failure (bad options: missing world_builder, roster_ids.size() != 32; no free port); see `NetSession.last_create_error`.
static func host(opts: NetSessionOptions, lobby_name: String = "") -> NetSession
static func join(opts: NetSessionOptions, address: String, port: int = NetProtocol.DEFAULT_PORT) -> NetSession
## Skirmish: same launch pipeline, Role.LOCAL, no transport. `lobby` comes from the skirmish setup screen
## (a NetLobbyState with HUMAN slot 0 = local player, AI/CLOSED elsewhere).
static func local(opts: NetSessionOptions, lobby: NetLobbyState) -> NetSession
## Tests/tools: start directly from a finished MatchConfig dictionary.
static func local_from_config(opts: NetSessionOptions, config: Dictionary) -> NetSession
static var last_create_error: String

var role: int                    # Role
var phase: int                   # Phase (read-only for callers)
var lobby: NetLobby              # valid in LOBBY..ENDED (all roles); state lives in lobby.state
var discovery: NetDiscovery      # host announces / client browses; null for LOCAL
var local_peer_id: int           # host = 1, LOCAL = 1
var local_pid: int               # -1 for spectators / before launch

func poll() -> int               # §3.0. Returns sim ticks executed this call.
func tick_alpha() -> float       # in [0,1): fraction of the current 50 ms tick elapsed (VIEW-ONLY float; §8)
func shutdown() -> void          # idempotent. Host: sends KICKED(HOST_LEFT) to every peer with a graceful disconnect, then service(0) up to 10 x with 5 ms sleeps (<= 50 ms total) so the packets leave, then destroys the ENet host. Finalises the replay, stops discovery

## ---- match (valid in PLAYING/PAUSED/ENDED) ----
func world() -> RefCounted       # the SimWorld (read-only for everybody but the adapter)
func adapter() -> NetSimAdapter
func config() -> Dictionary      # the normalised MatchConfig (deep copy)
func submit_command(ints: PackedInt32Array) -> bool   # UiCommandBus entry point. false = rejected (not playing/too long/queue full)
func surrender() -> bool         # submit_command([T_RESIGN, ResignReason.SURRENDER]); the player stays connected as an observer
func request_pause(want_paused: bool) -> int          # 0 = sent, else NetProtocol.PauseError
func host_set_speed(speed_pct: int) -> bool           # host only; table NetProtocol.SPEED_PCT
func host_resolve_stall(pid: int, action: int) -> void   # host only; NetProtocol.STALL_* (WAIT / DROP_RESIGN / DROP_AI)
func host_return_to_lobby() -> void                   # host only, phase ENDED
func leave() -> void             # clean leave (LEAVE message + disconnect); host leaving ends the match for everyone
func send_chat(text: String, team_only: bool = false) -> void
func send_map_ping(cell_x: int, cell_y: int) -> void  # non-sim UI signal relayed to teammates
## ---- introspection ----
func player_status(pid: int) -> int          # NetProtocol.PlayerNetStatus
func waiting_list() -> Array[Dictionary]     # [{pid:int, name:String, reason:int, wait_ms:int}] non-empty while stalled
func is_paused() -> bool
func stats() -> Dictionary                   # §4.7 (HUD/net overlay)
func replay_path() -> String                 # "" if not recording
func advertised_addresses() -> PackedStringArray   # host: "ip:port" strings to tell friends (private IPv4 first, then others), from IP.get_local_interfaces() + local_port()

signal phase_changed(phase: int, previous: int)
signal lobby_changed()                                        # NetLobbyState changed (re-render from lobby.state)
signal chat_received(channel: int, from_pid: int, from_name: String, text: String)  # from_pid 255 = system
signal countdown_changed(seconds_left: int)                   # 0 = aborted
signal join_rejected(reason: int, info: Dictionary)           # RejectReason + {host_version, host_data_hash, ...}
signal kicked(reason: int, detail: String)                    # KickReason
signal load_progress(pids: PackedInt32Array, percents: PackedInt32Array)
signal launch_aborted(reason: int, detail: String)            # back to LOBBY
signal match_started()
signal stall_changed(waiting: Array)                          # Array[Dictionary] as waiting_list(); empty = resumed
signal stall_prompt(pids: PackedInt32Array)                   # host only: offer WAIT / DROP_RESIGN / DROP_AI
signal pause_changed(paused: bool, by_pid: int)
signal player_status_changed(pid: int, status: int)
signal speed_changed(speed_pct: int)
signal input_delay_changed(turns: int)
signal match_ended(result: Dictionary)                        # {reason:int (MatchEndReason), sim_reason:int, winner_team:int, final_tick:int, final_checksum:int}
signal desync_detected(report: Dictionary)                    # §7.5
signal net_error(code: int, text: String)
signal map_ping(from_pid: int, cell_x: int, cell_y: int)
```

Call/phase legality: `submit_command` only in `PLAYING`/`PAUSED`; `host_*` only when `role == HOST`; violations return `false`/error and log at `warn`.

### 3.2 Transport layer

```gdscript
class_name NetClock extends RefCounted
static func real() -> NetClock                 # Time.get_ticks_usec()
static func manual(start_us: int = 0) -> NetClock
func now_us() -> int
func advance_us(us: int) -> void               # manual clocks only (asserts otherwise)
```

```gdscript
class_name NetTransportEvent extends RefCounted
enum Kind { CONNECTED = 1, DISCONNECTED = 2, PACKET = 3 }
var kind: int
var peer_id: int             # transport-level id: host = 1; clients see the server as 1; remote clients 2,3,... never reused per transport instance
var channel: int             # PACKET only
var data: PackedByteArray    # PACKET only (whole message, ENet reassembles fragments)
var code: int                # CONNECTED: connect_data supplied by the remote; DISCONNECTED: disconnect code (0 = transport timeout/none)
var address: String          # CONNECTED on the listening side: remote IP string
```

```gdscript
class_name NetTransport extends RefCounted     # abstract: base methods push_error("NOT IMPLEMENTED") and return ERR_UNAVAILABLE
func listen(port: int, max_peers: int) -> int                  # host. Scans port..port+PORT_SCAN_COUNT-1 (quiet UDP probe first). Returns Error; chosen port in local_port()
func connect_to(address: String, port: int, connect_data: int) -> int   # client. Returns OK immediately; success/failure arrives as events (own 6 s CONNECT_TIMEOUT)
func poll() -> void                                            # service(0) loop (cap 256 events); fills the event queue
func take_events() -> Array[NetTransportEvent]
func send(peer_id: int, channel: int, data: PackedByteArray) -> int   # v1: always reliable + ordered. ERR_INVALID_PARAMETER if channel >= CHANNEL_COUNT (never sent: ENet would log an engine ERROR)
func flush() -> void
func disconnect_peer(peer_id: int, code: int, graceful: bool) -> void  # graceful = disconnect_later (queued packets delivered first)
func close() -> void
func peer_ids() -> PackedInt32Array
func peer_state(peer_id: int) -> int                           # PeerState (§4.2): 0 gone, 1 connecting, 2 connected
func peer_address(peer_id: int) -> String
func peer_stats(peer_id: int) -> NetPeerStats
func set_timeouts(limit: int, min_ms: int, max_ms: int) -> void   # all current and future peers (NetProtocol.TIMEOUTS_*)
func local_port() -> int
func pop_traffic() -> PackedInt64Array                         # [bytes_sent, bytes_recv, pkts_sent, pkts_recv] since last call (ENet pop_statistic)
```
`NetTransportEnet` adds nothing public; internally it maps `ENetPacketPeer` objects (stable identity across events, E1) to transport peer ids via `get_instance_id()`, assigns ids on `EVENT_CONNECT`, drops them on `EVENT_DISCONNECT`, and never touches a peer whose `get_state() != STATE_CONNECTED`. `NetLoopbackHub`: `func endpoint(peer_id: int) -> NetTransportLoopback`; `func connect_endpoints(a: NetTransportLoopback, b: NetTransportLoopback) -> void`; `func deliver_all() -> void` (delivers everything due at the shared clock). `NetTransportFault`: `static func wrap(inner: NetTransport, profile: NetFaultProfile, clock: NetClock, rng_seed: int) -> NetTransportFault`; `func set_profile(p: NetFaultProfile) -> void`; `func freeze_for_ms(ms: int) -> void`; `func corrupt_next(peer_id: int, channel: int) -> void` (test hook: flips one payload byte of the next message to that peer/channel); `func stats() -> Dictionary` (delayed/dropped-and-retransmitted/duplicated/reordered counters).

```gdscript
class_name NetPeerStats extends RefCounted
var rtt_ms: float; var rtt_var_ms: float; var last_rtt_ms: float   # ENet PEER_ROUND_TRIP_TIME(_VARIANCE) / PEER_LAST_ROUND_TRIP_TIME (includes remote frame delay: measured 26 ms avg between two 60 Hz processes on 127.0.0.1)
var packet_loss: float                                            # PEER_PACKET_LOSS / PACKET_LOSS_SCALE (0..1)
var bytes_in: int; var bytes_out: int; var last_seen_ms: int
```

### 3.3 `NetSimAdapter` (the seam to sim) and `NetWorldJob`

```gdscript
class_name NetSimAdapter extends RefCounted     # abstract; NetSimAdapterWorld (real) and NetSimAdapterFake (tests) implement it
func world() -> RefCounted                      # underlying SimWorld / fake, for view + AI reads
func current_tick() -> int                      # 0 right after world construction
func submit_command(pid: int, ints: PackedInt32Array) -> void   # queue for the NEXT step(); applied by CommandSystem in that tick (pipeline step 1). Must tolerate malformed ints deterministically (ignore + count)
func step() -> void                             # run exactly ONE tick of the pipeline (ARCH §6), incl. the every-20-ticks checksum snapshot
func checksum_at(tick: int) -> int              # u32 snapshot taken at the end of `tick` (tick % 20 == 0); -1 if not retained (retain >= 64 snapshots)
func checksum_parts_at(tick: int) -> PackedInt32Array   # per-system sub-checksums of that snapshot (same length/order every peer)
func checksum_part_names() -> PackedStringArray          # e.g. ["entities","players","rng","map","production","economy","orders","combat","zones","vision"]
func checksum_now() -> int                      # full checksum of the current state (used at tick 0 and at match end)
func map_hash() -> int                          # u32 hash of all static+initial map layers (compared in LOAD_DONE)
func is_match_over() -> bool
func match_result() -> Dictionary               # {winner_team:int (-1 = none), reason:int}
func is_player_active(pid: int) -> bool         # false when defeated/resigned (AI runner stops thinking for them)
func dump_state() -> String                     # deterministic text dump (entities sorted by id) for desync diffs
func clear_events() -> void
```

`NetSimAdapterWorld extends NetSimAdapter` (`_init(world: SimWorld)`) is a pure forwarding shim — the **only** file that changes if sim renames anything. ASSUMPTION(sim) mapping: `current_tick()` -> `world.tick`; `step()` -> `world.step()`; `submit_command(pid, ints)` -> `world.submit_raw(pid, ints)` [XR-2]; `checksum_at(t)` -> `world.checksum_at(t)`; `checksum_parts_at(t)` -> `world.checksum_parts_at(t)`; `checksum_part_names()` -> `SimWorld.CHECKSUM_PART_NAMES`; `checksum_now()` -> `world.checksum()`; `map_hash()` -> `world.map.content_hash()`; `is_match_over()`/`match_result()`/`is_player_active(pid)`/`dump_state()`/`clear_events()` -> same-named `SimWorld` methods [XR-1,4,5,6]. `NetSimAdapterFake extends NetSimAdapter` (`_init(map_seed: int = 0, end_tick: int = -1)`; exact algorithm and goldens in §10.2; extra test hooks `inject_divergence(at_tick: int, part: int)` and `resigned(pid) -> bool`) ships in `src/net/` because the harness and CI use it, but is never constructed by shipping game code.

```gdscript
class_name NetWorldJob extends RefCounted       # produced by opts.world_builder(config)
## Time-sliced world construction so the main thread keeps servicing ENet during map generation.
func step(budget_us: int) -> bool               # true when finished (call again otherwise). Sync jobs finish in one call
func progress_pct() -> int                      # 0..100
func error() -> String                          # "" = ok
func take_adapter() -> NetSimAdapter            # valid once step() returned true and error() == ""
static func sync(builder: Callable) -> NetWorldJob   # wraps `() -> NetSimAdapter` into a one-step job (fallback when map/sim cannot slice)
```
If the builder is not sliceable, `NetLaunch` raises the ENet timeouts to `TIMEOUTS_LOADING` (limit 64, 20 s/60 s) for the duration of the call.

### 3.4 Lockstep core

```gdscript
class_name NetBundle extends RefCounted         # one executed turn
var turn: int                                   # u32
var flags: int                                  # bit0 = has_ctrl
var pids: PackedInt32Array                      # strictly ascending, only pids with >= 1 command
var group_cmds: Array                           # Array[Array[PackedInt32Array]] parallel to pids (command int arrays, [type, args...])
var ctrl: Array                                 # Array[PackedInt32Array]: [kind, args...] (CtrlKind, §4.2)
static func build(turn: int, pids: PackedInt32Array, group_cmds: Array, ctrl: Array) -> NetBundle
func core_bytes() -> PackedByteArray            # canonical sim-relevant bytes: u32 turn | u8 groups | groups (no flags/ctrl/hash); feeds input_chain + replay
func wire_bytes() -> PackedByteArray            # full TURN_BUNDLE message incl. trailing FNV
func command_count() -> int
```

```gdscript
class_name NetLockstep extends RefCounted       # pacing + barrier + execution; identical code on host, client, spectator
var on_send_input: Callable      # (turn:int, exec_turn:int, cmds:Array) -> void     cmds: Array[PackedInt32Array]; host wires it to NetTurnHost.on_input
var on_turn_begin: Callable      # (turn:int, bundle:NetBundle) -> void              recorder, AI runner (host), status display
var on_checksum: Callable        # (tick:int, checksum:int, chain:int) -> void       every CHECKSUM_PERIOD ticks + at match end
var on_stall_changed: Callable   # (stalled:bool, stall_ms:int) -> void              stall_ms counts from the moment the bundle was due
var on_match_over: Callable      # () -> void
var on_boundary: Callable        # (turn:int, target_turn:int) -> void     after the local fill-up; host: AI production + injection frontier (§5.6)
var on_ctrl: Callable            # (turn:int, ctrl:PackedInt32Array) -> void   every ctrl record as it is applied (status display, HUD, replay events)
var on_pause: Callable           # (paused:bool) -> void
func setup(sim: NetSimAdapter, clock: NetClock, local_pid: int, initial_delay: int, speed_pct: int) -> void
func start() -> void                                    # pre-roll: turns 0..D0-1 are implicitly empty; sent_through = D0-1
func push_bundle(b: NetBundle) -> int                   # BundleResult: OK / DUPLICATE / TOO_FAR / MALFORMED / WRONG_STATE (§5.5.5)
func submit_local(ints: PackedInt32Array) -> bool       # queue for the next boundary (max LOCAL_QUEUE_MAX = 256 pending; FIFO)
func update(max_ticks: int = NetProtocol.MAX_TICKS_PER_POLL) -> int   # §3.0 step 6; returns ticks executed; speed_pct 0 = unpaced (ignores the accumulator, barrier still enforced)
func tick_alpha() -> float
func set_speed_pct(pct: int) -> void
func resume(resume_turn: int) -> void                  # RESUME(R): _resume_turn = max(_resume_turn, R); if paused and _resume_turn >= _paused_at_turn: unpause and clear _pause_after_turn
func exec_turn() -> int                                 # next turn to begin (== current_tick()/2 when at a boundary)
func delay_turns() -> int
func is_paused() -> bool
func is_stalled() -> bool
func input_chain() -> int                               # FNV-1a chain over core_bytes of every executed turn
func take_report() -> Dictionary                        # PONG payload since last call: {slack_min_ms, stall_ms, episodes, hitch, load_pct, exec_turn}
func stats() -> Dictionary
```

```gdscript
class_name NetTurnHost extends RefCounted       # host only
enum InputResult { OK = 0, DUPLICATE = 1, LATE = 2, TOO_FAR = 3, WRONG_PLAYER = 4, TOO_BIG = 5, BUFFERED = 6 }
func setup(clock: NetClock, cfg: Dictionary) -> void   # {initial_delay, min_delay, max_delay, fixed_delay, speed_pct, pause_policy, auto_drop_ms, on_disconnect}
func set_player(pid: int, role: int, peer_id: int) -> void          # role: NetProtocol.PR_NONE/PR_HUMAN/PR_AI/PR_DROPPED
func on_input(pid: int, turn: int, exec_turn: int, cmds: Array) -> int   # network TURN_INPUT (pid stamped by the caller from the peer record) or local fill-up
func note_injection_through(turn: int) -> void          # host-local fill-up frontier: AI + local human inputs exist through `turn`
func add_ai_commands(turn: int, pid: int, cmds: Array) -> void
func close_ready() -> Array[NetBundle]                  # closes every turn whose barrier is satisfied (bounded 16 per call)
func on_pong(peer_id: int, sample: Dictionary) -> void  # {rtt_ms, slack_min_ms, stall_ms, episodes, hitch, exec_turn, load_pct}
func evaluate(now_us: int) -> void                      # delay policy, stall timers, pause budget, auto-drop, disconnect grace
func request_pause(pid: int, want_paused: bool) -> int  # PauseError
func resume_pause(by_pid: int) -> int
func set_speed(speed_pct: int) -> void
func drop_player(pid: int, mode: int, reason: int) -> void   # mode STALL_DROP_RESIGN / STALL_DROP_AI; queues T_RESIGN or AI takeover at the next closable turn
func peer_disconnected(peer_id: int) -> void
func waiting() -> Array[Dictionary]                     # players blocking the current turn
func next_close_turn() -> int
func delay_turns() -> int
func stats() -> Dictionary
func _bundle_for_peer(b: NetBundle, peer_id: int) -> NetBundle   # virtual hook, default: identity. Called for every bundle sent to a client; tests override it to inject relay faults (e.g. swap two commands => INPUT_CHAIN desync)
```

```gdscript
class_name NetDelayPolicy extends RefCounted
func configure(d_min: int, d_max: int, turn_ms: int) -> void       # turn_ms = 100 * 100 / speed_pct (wall ms per turn)
func reset(now_ms: int, d: int) -> void
func feed_pong(peer_id: int, now_ms: int, rtt_ms: int, slack_min_ms: int, stall_ms: int, episodes: int, hitch: bool) -> void
func remove_peer(peer_id: int) -> void
func evaluate(now_ms: int, current_d: int) -> int                  # desired D (== current_d if unchanged); algorithm §5.5.6
func peer_rtt_ms(peer_id: int) -> int
func peer_jitter_ms(peer_id: int) -> int
```

```gdscript
class_name NetAiRunner extends RefCounted
var think_period_turns: int = NetProtocol.AI_THINK_PERIOD_TURNS     # default 5; per-AI period = ai_think_period(level) when provided (stored per pid)
func setup(ai_factory: Callable, base_seed: int, think_period: Callable = Callable(), release: Callable = Callable(), governor: bool = true) -> void   # base_seed = MatchConfig.seed; governor = wall-clock CPU governor (off when unpaced)
func add_ai(pid: int, level: int, style: int) -> void              # creates the thinker via ai_factory(pid, level, style, mix32(base_seed ^ (pid+1)*0x9E3779B9))
func remove_ai(pid: int) -> void
func has_ai(pid: int) -> bool
func ai_pids() -> PackedInt32Array                                  # ascending
func produce(exec_turn: int, target_turn: int, sim: NetSimAdapter, out_groups: Array) -> void   # appends [pid:int, cmds:Array[PackedInt32Array]] in ascending pid order
func stats() -> Dictionary                                          # {think_us:{pid:int}, dropped_cmds:int}
```

### 3.5 Lobby

For a non-host peer the `int` returned by the edit methods only reports *local pre-validation and sending* (`OK` = message sent); the authoritative outcome (accepted, swapped, refused) is the next `LOBBY_SNAPSHOT`, so the UI must render from `lobby.state`, never from its own request.

```gdscript
class_name NetLobby extends RefCounted
enum Result { OK = 0, DENIED = 1, INVALID = 2, LOCKED = 3, CONFLICT = 4, FULL = 5 }
enum StartError { OK = 0, NO_PLAYERS = 1, NOT_ENOUGH_PLAYERS = 2, HUMAN_NOT_READY = 3, HUMAN_DISCONNECTED = 4,
                  BAD_ROSTER = 5, COLOR_CONFLICT = 6, START_CONFLICT = 7, TOO_MANY_PLAYERS = 8, MAP_INVALID = 9,
                  SINGLE_TEAM = 10, ALREADY_LAUNCHING = 11, AI_UNAVAILABLE = 12 }
signal changed()
signal chat_received(channel: int, from_slot: int, from_name: String, text: String)
signal countdown_changed(seconds_left: int)
var state: NetLobbyState                                 # read-only for UI
func is_host() -> bool
func local_slot() -> int                                 # -1 if spectator / not seated
## ---- any seated peer: edits ITS OWN slot (host applies directly, clients send LOBBY_ACTION) ----
func set_roster(roster_id: String) -> int                # one of opts.roster_ids or a random token (§5.3.4)
func set_team(team: int) -> int                          # 0 = no team, 1..4 = A..D
func set_color(color: int) -> int                        # conflict => the two slots swap colours
func set_start(start: int) -> int                        # -1 random, else 0..layout_players-1; conflict => swap
func set_ready(ready: bool) -> int
func set_name(name: String) -> int
func move_to_slot(slot: int) -> int                      # only into an OPEN slot
func become_spectator() -> int
func become_player() -> int
func send_chat(text: String, team_only: bool) -> void
## ---- host only ----
func host_set_slot_kind(slot: int, kind: int) -> int     # CLOSED/OPEN/AI (HUMAN slots are filled by joins); closing a HUMAN slot kicks its peer
func host_set_ai(slot: int, level: int, style: int) -> int   # also sets handicap_pct = opts.ai_default_handicap(level) when provided (Brutal = 120) and resets ai_flags; the host may edit the handicap afterwards
func host_set_slot_roster(slot: int, roster_id: String) -> int
func host_set_slot_team(slot: int, team: int) -> int
func host_set_slot_color(slot: int, color: int) -> int
func host_set_slot_start(slot: int, start: int) -> int
func host_set_slot_handicap(slot: int, handicap_pct: int) -> int     # 50..200 step 5
func host_set_map(family: int, size: int, map_seed: int, layout_players: int) -> int   # slots >= layout_players are forced CLOSED
func host_set_rules(rules: Dictionary) -> int            # keys/ranges in §7.1; unknown keys rejected
func host_set_net_options(opts: Dictionary) -> int       # speed_pct, pause_policy, on_disconnect, auto_drop_ms, allow_spectators
func host_kick(peer_id: int, ban_for_session: bool) -> int
func host_start() -> int                                 # returns StartError; OK begins COUNTDOWN
func host_cancel_start() -> void
static func start_error_text(code: int) -> String
```

```gdscript
class_name NetMatchConfig extends RefCounted             # static helpers over the MatchConfig Dictionary (schema §7.1)
static func from_lobby(state: NetLobbyState, match_seed: int, versions: Dictionary, now_unix: int) -> Dictionary   # resolves random rosters/starts (§5.3.5)
static func normalize(raw: Variant) -> Dictionary        # {} on ANY violation: whitelisted keys, int-valued floats -> int, ranges, roster/id checks are done by validate()
static func validate(cfg: Dictionary, opts: NetSessionOptions) -> String   # "" = ok, else a human-readable error (versions, ranges, uniqueness, roster ids)
static func canonical_json(cfg: Dictionary) -> String    # JSON.stringify(cfg, "", true): sorted keys, no indent, ints only (never floats)
static func config_hash(json_bytes: PackedByteArray) -> int     # FNV-1a 32 over the exact transmitted UTF-8 bytes
static func pid_of_peer(cfg: Dictionary, peer_id: int) -> int   # -1 if not a player
static func team_of(cfg: Dictionary, pid: int) -> int
```

### 3.6 Discovery

```gdscript
class_name NetDiscovery extends RefCounted
signal entries_changed()
var browse_error: String                  # "" or e.g. "port_in_use" (another instance already listens; UI hint: join by IP)
var announce_ok: bool                     # false if every target failed for > 10 s (UI hint: firewall / local-network permission, §5.13)
func setup(clock: NetClock, game_version: String, proto: int, sim_version: int, data_hash: int) -> void
func start_announce(get_info: Callable, game_port: int) -> void    # get_info: () -> Dictionary (fields of the §4.4 discovery datagram); sends every 1 s (+-100 ms jitter)
func stop_announce(send_closed: bool = true) -> void               # sends a CLOSED datagram so browsers drop the entry at once
func start_browse() -> int                                         # binds UDP DISCOVERY_PORT on 0.0.0.0. ERR_UNAVAILABLE if in use
func stop_browse() -> void
func poll() -> void
func entries() -> Array[NetDiscoveryEntry]                         # sorted by (host_name, address); entries expire after 4 s without an announce
func set_targets_override(targets: PackedStringArray) -> void      # tests / CI without broadcast (e.g. ["127.0.0.1"])
static func broadcast_candidates(ipv4_addresses: PackedStringArray) -> PackedStringArray   # §5.2, pure function (unit-tested)
```
```gdscript
class_name NetDiscoveryEntry extends RefCounted
var address: String; var port: int; var host_name: String; var game_version: String
var proto_version: int; var sim_version: int; var data_hash: int; var session_id: int
var flags: int; var humans: int; var slots_total: int; var slots_free: int; var ai_count: int
var map_family: int; var map_size: int; var last_seen_ms: int; var compatible: bool     # compatible = proto/sim/data_hash all equal to local
```

### 3.7 Desync, self-test, replays

```gdscript
class_name NetDesync extends RefCounted
func setup(adapter: NetSimAdapter, is_host: bool, local_pid: int, match_id: String, config_json: String) -> void
func local_snapshot(tick: int, checksum: int, chain: int) -> void         # called from NetLockstep.on_checksum; stores checksum + parts (ring of 64)
func on_report(pid: int, tick: int, checksum: int, chain: int) -> void    # host: compare against own snapshot (holds reports until the host reaches `tick`)
func on_notice(tick: int, kind: int, entries: Array) -> void              # client: DESYNC_NOTICE from host
func on_parts(pid: int, tick: int, parts: PackedInt32Array) -> void
func write_package(replay_bytes: PackedByteArray, log_lines: PackedStringArray) -> Dictionary   # writes user://desync/* and returns the §7.5 report
static func classify(local_chain: int, remote_chain: int, local_sum: int, remote_sum: int) -> int    # DesyncKind
```
```gdscript
class_name NetSelfTest extends RefCounted
## Runs `ticks` of the same match through (A) the LOCAL net pipeline with scripted commands (and AI if a factory is given)
## and (B) a fresh world driven by A's recorded replay; compares every checksum snapshot, the input chain, and dump_state hashes.
static func run_double(config: Dictionary, world_builder: Callable, script: Array, ticks: int, ai_factory: Callable = Callable()) -> Dictionary
## => {ok:bool, ticks:int, compared:int, first_mismatch_tick:int (-1), chain_a:int, chain_b:int, final_a:int, final_b:int, state_hash_a:int, state_hash_b:int, mode:String}
```
```gdscript
class_name NetReplay extends RefCounted                   # static helpers
const EXT: String = "mfreplay"
static func replay_dir() -> String                        # "user://replays" (created on demand)
static func begin_recording_path() -> String              # "user://replays/_recording.mfreplay.tmp"
static func finalize_autosave(tmp_path: String, keep: int) -> String     # rotates autosave_1..keep, returns new autosave_1 path
static func recover_orphans() -> PackedStringArray        # renames a leftover _recording tmp to crash_<unix>.mfreplay; call once at boot
static func list_replays() -> Array[Dictionary]           # metadata only (header + trailer): {path, size, match_id, map, players:[{name,roster,team}], duration_ticks, finalized, game_version, mtime}
static func save_copy(from_path: String, display_name: String) -> String # sanitised file name; returns new path or ""
static func delete_replay(path: String) -> bool           # only inside replay_dir() and only *.mfreplay
```
```gdscript
class_name NetReplayRecorder extends RefCounted
func open_file(path: String, config: Dictionary, meta: Dictionary) -> int      # Error; writes header, keeps the file open
func open_memory(config: Dictionary, meta: Dictionary) -> void                  # tests / desync package
func record_turn(bundle: NetBundle) -> void              # writes a TURNS record only if the bundle has commands (gap counting for empty turns)
func record_check(tick: int, checksum: int, chain: int) -> void
func record_parts(tick: int, parts: PackedInt32Array) -> void    # every 200 ticks
func record_event(turn: int, kind: int, args: PackedInt32Array, text: String = "") -> void   # PLAYER_STATUS / CHAT
func flush() -> void                                     # FileAccess.flush(); called after each CHECK record (<= 1 s of data at risk)
func finish(result: Dictionary) -> void                 # END record + trailer, closes the file
func abort() -> void
func to_bytes() -> PackedByteArray                       # memory mode (also valid mid-match for desync packages)
```
```gdscript
class_name NetReplayData extends RefCounted
var config: Dictionary; var replay_meta: Dictionary; var format_version: int
var turns: PackedInt32Array               # turn numbers that have commands, ascending
var bodies: Array                         # Array[PackedByteArray] core bodies parallel to `turns` (group_count + groups; turn number implicit)
var checks: PackedInt64Array              # flattened [tick, checksum, chain, ...] triples
var parts: Array                          # [{tick:int, parts:PackedInt32Array}]
var events: Array                         # [{turn:int, kind:int, args:PackedInt32Array, text:String}]
var end: Dictionary                       # {} if not finalized: {final_tick, final_checksum, final_chain, reason, winner_team, total_turns}
var finalized: bool; var truncated: bool
static func load_file(path: String) -> NetReplayData      # null on unreadable/invalid header; tolerant of truncation
static func from_bytes(bytes: PackedByteArray) -> NetReplayData
func total_turns() -> int
func header_error() -> String
```
```gdscript
class_name NetReplayPlayer extends RefCounted
const SPEEDS: PackedFloat32Array = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]   # + MAX (unbounded, time-sliced)
var error_text: String = ""                              # set when setup() fails (version gate, corrupt data)
var strict: bool = false                                  # true: any versions.* difference refuses (tests, verify_file, golden replays)
var allow_version_mismatch: bool = false                 # developer override of the whole version gate
var warning: String = ""                                 # set when playback is allowed despite a data_hash difference
signal verify_failed(tick: int, expected: int, actual: int)          # first mismatch only per run
signal finished()
func setup(data: NetReplayData, world_builder: Callable, clock: NetClock) -> int   # Error; builds the world through the same NetWorldJob path
func poll(budget_us: int = 6000) -> void                 # advance according to speed/pause; fast-forward/seek work is time-sliced by budget_us
func adapter() -> NetSimAdapter
func set_speed(multiplier: float) -> void                # 0 = MAX
func set_paused(p: bool) -> void
func seek_tick(target_tick: int) -> void                 # backwards => rebuild world and re-simulate from 0 (sliced); forward => fast-forward
func current_tick() -> int; func end_tick() -> int; func progress() -> float
func is_seeking() -> bool
func verified_through_tick() -> int                      # last tick whose CHECK record matched
static func verify_file(path: String, world_builder: Callable, max_ticks: int = 0) -> Dictionary   # headless full run => {ok, ticks, compared, first_mismatch_tick, final_checksum}
```

### 3.8 Static helpers used across the module

```gdscript
class_name NetProtocol extends RefCounted     # constants/enums: §4.1; functions:
static func fnv1a32(bytes: PackedByteArray, basis: int = 0x811C9DC5, from: int = 0, to: int = -1) -> int   # `basis` chains calls: fnv1a32(b2, fnv1a32(b1)) == fnv1a32(b1 + b2)
static func mix32(x: int) -> int                              # murmur3 fmix32, 32-bit masked
static func lobby_rand(rng_seed: int, index: int) -> int      # mix32((rng_seed + (index+1)*0x9E3779B9) & 0xFFFFFFFF)
static func sanitize_name(s: String) -> String                # strips control chars/BBCode brackets, trims, <= 24 chars, "" -> "Player"
static func sanitize_text(s: String, max_bytes: int) -> String # chat: control chars removed, whitespace collapsed, cut on a UTF-8 boundary
static func describe_reject(reason: int, info: Dictionary) -> String   # English default of net.err.* (§5.13)
static func describe_kick(reason: int, detail: String) -> String
static func is_private_ipv4(ip: String) -> bool               # 10/8, 172.16/12, 192.168/16, 169.254/16, 127/8, 100.64/10
static func is_valid_utf8(bytes: PackedByteArray, from: int, length: int) -> bool   # strict RFC 3629 scan in GDScript: rejects NUL, overlong forms, surrogates, > U+10FFFF, truncated sequences
static func parse_address(text: String) -> Dictionary         # join-by-IP input => {ok:bool, host:String, port:int, error:String}: trims; accepts `1.2.3.4`, `1.2.3.4:27615`, `name`, `name:27615`, `[fe80::1]:27615`, bare IPv6 (no port); default port 27615; port 1..65535; length <= 255; zone ids (`%en0`) rejected
```

### 3.9 Wire helpers and internal components (signatures other net files depend on)

```gdscript
class_name NetWriter extends RefCounted          # append-only, little-endian; grows by doubling; methods return self for chaining
func u8(v: int) -> NetWriter                      # masks to 8 bits (same for u16/u32/i8/i16: masking, never errors)
func u16(v: int) -> NetWriter
func u32(v: int) -> NetWriter
func i8(v: int) -> NetWriter
func i16(v: int) -> NetWriter
func varint(v: int) -> NetWriter                  # 0 <= v <= 0xFFFFFFFF, canonical LEB128
func zvarint(v: int) -> NetWriter                 # int32 -> zigzag -> varint
func str_(s: String, max_bytes: int) -> NetWriter     # u8 len + UTF-8; truncates on a code-point boundary at max_bytes
func bytes_(b: PackedByteArray) -> NetWriter          # varint len + raw
func raw(b: PackedByteArray) -> NetWriter             # no length prefix
func size() -> int
func to_bytes() -> PackedByteArray
```
```gdscript
class_name NetReader extends RefCounted          # bounds-checked cursor over a PackedByteArray; never touches the engine on overrun
func _init(buf: PackedByteArray, start: int = 0, end: int = -1) -> void
var ok: bool = true                               # sticky: false after ANY overrun / malformed field
func left() -> int
func pos() -> int
func u8() -> int                                  # u16/u32/i8/i16 alike: on overrun ok = false, cursor to end, returns 0
func u16() -> int
func u32() -> int
func i8() -> int
func i16() -> int
func varint() -> int                              # canonical only: overlong / > 5 bytes / > 0xFFFFFFFF => ok = false
func zvarint() -> int
func str_(max_bytes: int) -> String               # len > max_bytes or invalid UTF-8 (NetProtocol.is_valid_utf8) => ok = false, ""
func bytes_(max_len: int) -> PackedByteArray
func raw(n: int) -> PackedByteArray
```
`NetCodec` (static): for every message `X` of §4.4 there is `encode_x(fields: Dictionary) -> PackedByteArray` and `decode_x(bytes: PackedByteArray) -> Dictionary` (**empty on any failure**, including leftover bytes); dictionary keys are the snake_case field names of the layout (`decode_turn_input(b) -> {turn:int, exec_turn:int, cmds:Array[PackedInt32Array]}`, `decode_pong(b) -> {seq, echo_ms, exec_turn, slack_min_ms, stall_ms, episodes, load_pct, hitch}`). Special cases: `encode_bundle(b: NetBundle) -> PackedByteArray`, `decode_bundle(bytes: PackedByteArray) -> NetBundle` (**null on failure**), `encode_turn_core(turn: int, pids: PackedInt32Array, group_cmds: Array) -> PackedByteArray` (the canonical chain/replay bytes), `peek_type(bytes: PackedByteArray) -> int` (-1 if empty), `encode_commands(cmds: Array, w: NetWriter) -> bool` / `decode_commands(r: NetReader, max_cmds: int) -> Array` (shared by input, bundle and replay records). `NetLobbyCodec` (static): `encode_snapshot(state: NetLobbyState) -> PackedByteArray`, `decode_snapshot(bytes: PackedByteArray, opts: NetSessionOptions) -> NetLobbyState` (null on failure or out-of-range fields), `encode_action(op: int, args: Dictionary)`/`decode_action(bytes) -> Dictionary`, `encode_chat_c2h/decode_chat_c2h`, `encode_chat_h2c/decode_chat_h2c`, `deflate_config(json: String) -> PackedByteArray` (LAUNCH_CONFIG packet), `inflate_config(packet: PackedByteArray) -> String` ("" on any failure, size and hash verified).

```gdscript
class_name NetRateLimiter extends RefCounted     # one per remote peer (NetPeerInfo.limiter)
enum Class { INPUT = 0, PONG = 1, CHECK = 2, LOBBY = 3, CHAT = 4, PAUSE = 5, MISC = 6 }
# token buckets (rate/s, burst): INPUT 40/64, PONG 8/16, CHECK 4/8, LOBBY 10/20, CHAT 1/5 (i.e. 5 per 5 s), PAUSE 1/2, MISC 5/10
func allow(cls: int, now_us: int) -> bool
func add_violation(weight: float, now_us: int) -> float    # returns the decayed score after adding (decay 1 point per VIOLATION_DECAY_MS)
func score(now_us: int) -> float
```
```gdscript
class_name NetLaunch extends RefCounted          # owned by NetSession; the launch handshake of §5.4 (host and client halves)
func begin_countdown(seconds: int) -> void                             # host
func step(now_us: int, budget_us: int) -> void                         # countdown ticks, world-job slicing, LOAD_STATUS cadence, LOAD_TIMEOUT
func on_message(peer_id: int, type: int, r: NetReader) -> void         # LAUNCH_*, LOAD_*, START handlers (per-role)
func abort(reason: int, pid: int, detail: String) -> void             # host: LAUNCH_ABORT to everybody, back to LOBBY
func reference() -> Dictionary                                         # {config:Dictionary, config_json:String, config_hash:int, map_hash:int, checksum0:int} (host: the truth peers are compared with)
func take_adapter() -> NetSimAdapter                                   # once the local job finished; null before
```

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 `NetProtocol` constants (single source of truth; never duplicate numbers elsewhere)

| Constant | Value | Meaning |
|---|---|---|
| `PROTO_VERSION` | `1` (u16) | Wire protocol. Bump on ANY incompatible layout change (except frozen prefixes, §4.4) |
| `DEFAULT_PORT` / `PORT_SCAN_COUNT` | `27615` / `10` | ENet game port and fallback range 27615..27624 (UDP) |
| `DISCOVERY_PORT` | `27614` | UDP LAN discovery (outside the game range on purpose) |
| `CH_CTRL` / `CH_TURN` / `CH_BULK` / `CHANNEL_COUNT` | `0` / `1` / `2` / `3` | ENet channels, all reliable+ordered (§5.1) |
| `MAX_PLAYERS` / `MAX_SPECTATORS` | `8` / `8` | slots (pid 0..7) / observers |
| `ENET_MAX_PEERS` | `24` | > slots so overflow joiners still receive a `JOIN_REJECT` with reason |
| `MAX_UNAUTH_PEERS` / `MAX_CONN_PER_IP` | `8` / `4` | flood limits before `JOIN_REQUEST` |
| `TURN_TICKS` | `2` | = `SimConfig.TURN_TICKS` [XR-8]; `TICK_US = 1_000_000 / SimConfig.TPS = 50_000`, `TURN_MS = 100` at 100 % speed |
| `CHECKSUM_PERIOD_TICKS` | `20` | = `SimConfig.CHECKSUM_PERIOD` (snapshot + exchange every 20 ticks = 10 turns = 1 s) |
| `D_MIN_LAN` / `D_MIN_LOCAL` / `D_MAX` | `2` / `1` / `8` | input delay in turns (default = `D_MIN_LAN`) |
| `REORDER_WINDOW` | `32` | turns of out-of-order buffering (inputs at host, bundles at clients) |
| `INPUT_LOOKAHEAD` | `D_MAX + 2` | host rejects `TURN_INPUT.turn > next_close + INPUT_LOOKAHEAD` |
| `MAX_CMD_INTS` / `MAX_CMDS_PER_TURN` | `1024` / `64` | ints per command / commands per player per turn |
| `MAX_INPUT_BYTES` / `MAX_BUNDLE_BYTES` | `6200` / `52000` | max `TURN_INPUT` / `TURN_BUNDLE` message size |
| `MAX_CONFIG_JSON` / `MAX_LAUNCH_PACKET` / `MAX_SNAPSHOT` | `65536` / `40000` / `3072` | bytes (inflated JSON / compressed `LAUNCH_CONFIG` packet / `LOBBY_SNAPSHOT`) |
| `LOCAL_QUEUE_MAX` | `256` | pending local commands per client |
| `PING_INTERVAL_MS` | `500` | host->client `PING` cadence |
| `CONNECT_TIMEOUT_MS` / `JOIN_REPLY_TIMEOUT_MS` / `HANDSHAKE_TIMEOUT_MS` | `6000` / `5000` / `5000` | client ENet connect / client waits for accept / host waits for `JOIN_REQUEST` |
| `TIMEOUTS_LOBBY` / `TIMEOUTS_GAME` / `TIMEOUTS_LOADING` | `(32,5000,15000)` / `(32,5000,12000)` / `(64,20000,60000)` | `ENetPacketPeer.set_timeout(limit, min_ms, max_ms)`; dead-peer detection measured 4.8-6.5 s for min 3000-5000 |
| `STALL_UI_MS` / `STALL_INFO_PERIOD_MS` / `STALL_PROMPT_MS` | `400` / `250` / `8000` | client overlay threshold / host `STALL_INFO` cadence / host prompt threshold |
| `AUTO_DROP_DEFAULT_MS` / `DISCONNECT_ACT_MS` | `60000` / `5000` | auto action on an unresponsive human / on a transport-disconnected human (0 = never/manual) |
| `HITCH_MS` / `QUARANTINE_MS` | `1000` / `3000` | stall episodes or RTT samples above this are hitches; their peer is ignored by the delay policy for 3 s |
| `DELAY_EVAL_MS` / `DELAY_FRAME_MARGIN_MS` | `500` / `34` | policy cadence / two 60 Hz frames of margin |
| `DELAY_RAISE_STALL_MS` / `DELAY_LOWER_HOLD_MS` / `DELAY_LOWER_MARGIN_MS` | `400` / `8000` / `60` | §5.5.6 |
| `MAX_TICKS_PER_POLL` / `MAX_ELAPSED_US` / `ACC_CAP_TICKS` | `8` / `250000` / `4` | spiral-of-death guards (§5.5.2) |
| `MAX_PAUSES_PER_PLAYER` / `MAX_PAUSE_MS` | `3` / `120000` | pause budget |
| `LOAD_TIMEOUT_MS` / `COUNTDOWN_S` | `120000` / `3` | launch |
| `DISCOVERY_INTERVAL_MS` / `DISCOVERY_STALE_MS` / `DISCOVERY_BREAKER_FAILS` / `DISCOVERY_BREAKER_MS` | `1000` / `4000` / `5` / `30000` | announce cadence / entry expiry / per-target circuit breaker |
| `LOBBY_SNAPSHOT_MIN_MS` | `100` | snapshot coalescing |
| `NAME_MAX_CHARS` / `CHAT_MAX_BYTES` | `24` / `200` | |
| `AI_THINK_PERIOD_TURNS` / `AI_MAX_CMDS_PER_THINK` / `AI_BOUNDARY_BUDGET_US` | `5` / `64` / `8000` | default AI cadence (per AI, phase-staggered by pid) / commands kept per think / wall-clock AI budget per boundary (paced sessions) |
| `VIOLATION_KICK_SCORE` / `VIOLATION_DECAY_MS` | `12` / `5000` | a peer is kicked at score >= 12; score decays 1 per 5 s |
| `SPEED_PCT` | `[50, 75, 100, 125, 150, 200]` | code 2 (100 %) = "Medium" = default (bible: medium game speed) |
| `T_RESIGN` | `250` | net-reserved sim command type (§6.1); reserved range `240..255` |
| `TAKEOVER_AI_LEVEL` | `1` | AI level used when a dropped human is replaced by AI (style 0) |

### 4.2 Enumerations (integer values are wire/file format; never renumber)

GDScript rule (verified on 4.7.2): enum members **must be qualified by the enum name** — `NetProtocol.KickReason.KICKED` works, `NetProtocol.KICKED` is a parse error — and member names may repeat across enums (`NONE` below is legal in several). Where this document writes a bare member (`PR_HUMAN`, `STALL_DROP_AI`, `HUMAN`, `SIM`) it means the qualified form. Plain `const`s (`T_RESIGN`, `SPEED_PCT`, ports, limits) are accessed as `NetProtocol.NAME`.

```gdscript
enum SlotKind      { CLOSED = 0, OPEN = 1, HUMAN = 2, AI = 3 }
enum LobbyPhase    { OPEN = 0, COUNTDOWN = 1, LOADING = 2, IN_GAME = 3, ENDED = 4 }
enum LobbyOp       { SET_ROSTER = 1, SET_TEAM = 2, SET_COLOR = 3, SET_START = 4, SET_READY = 5, SET_NAME = 6,
                     MOVE_TO_SLOT = 7, TO_SPECTATOR = 8, TO_PLAYER = 9 }
enum RejectReason  { NONE = 0, PROTO_MISMATCH = 1, SIM_MISMATCH = 2, DATA_MISMATCH = 3, LOBBY_FULL = 4, IN_PROGRESS = 5,
                     BANNED = 6, BAD_PASSWORD = 7, BAD_REQUEST = 8, SPECTATORS_CLOSED = 9, HOST_BUSY = 10, TOO_MANY_CONNECTIONS = 11 }
enum KickReason    { NONE = 0, KICKED_BY_HOST = 1, BANNED = 2, HOST_LEFT = 3, PROTOCOL_VIOLATION = 4, TIMEOUT = 5,
                     DROPPED_UNRESPONSIVE = 6, DUPLICATE_SESSION = 7, SHUTDOWN = 8, VERSION = 9 }
enum AbortReason   { NONE = 0, HUMAN_LEFT = 1, LOAD_TIMEOUT = 2, LOAD_FAILED = 3, MAP_MISMATCH = 4, INIT_MISMATCH = 5,
                     CONFIG_INVALID = 6, HOST_CANCEL = 7 }
enum PlayerRole    { PR_NONE = 0, PR_HUMAN = 1, PR_AI = 2, PR_DROPPED = 3 }            # host barrier membership
enum PlayerNetStatus { ACTIVE = 0, STALLED = 1, DISCONNECTED = 2, DROPPED = 3, AI_TAKEOVER = 4, RESIGNED = 5, LEFT = 6, DEFEATED = 7 }
enum CtrlKind      { INPUT_DELAY = 1, PLAYER_STATUS = 2, SPEED = 3, MATCH_END = 4, PAUSE = 5 }
enum StallReason   { NETWORK = 0, DISCONNECTED = 1, SLOW_CPU = 2, LOADING = 3 }
enum StallAction   { STALL_WAIT = 0, STALL_DROP_RESIGN = 1, STALL_DROP_AI = 2 }
enum DesyncKind    { NONE = 0, SIM = 1, INPUT_CHAIN = 2, BOTH = 3 }
enum PauseError    { OK = 0, NOT_ALLOWED = 1, BUDGET_EXHAUSTED = 2, ALREADY = 3, NOT_PLAYING = 4 }
enum PausePolicy   { HOST_ONLY = 0, ANY_PLAYER = 1, DISABLED = 2 }                    # default 1
enum OnDisconnect  { RESIGN = 0, AI = 1 }                                             # default 0
enum ResignReason  { SURRENDER = 0, DISCONNECT = 1, KICKED = 2, TIMEOUT = 3 }         # T_RESIGN arg 1
enum PeerState     { GONE = 0, CONNECTING = 1, CONNECTED = 2 }
enum BundleResult  { OK = 0, DUPLICATE = 1, TOO_FAR = 2, MALFORMED = 3, WRONG_STATE = 4 }
enum ReplayRec     { TURNS = 1, CHECK = 2, PARTS = 3, EVENT = 4, END = 5 }
enum ReplayEvent   { PLAYER_STATUS = 1, CHAT = 2 }
enum MatchEndReason{ SIM_DECIDED = 0, NO_HUMANS_LEFT = 1, HOST_CLOSED = 2, ABANDONED = 3, DESYNC = 4 }   # CK_MATCH_END / MATCH_END / replay END / match_ended.reason
enum NetErrorCode  { REPLAY_WRITE = 1, NO_CHECKSUM = 2, HOST_PROTOCOL = 3, TRANSPORT = 4, BUILD_FAILED = 5 }   # net_error(code, text)
enum LogLevel      { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }                       # opts.log_sink(level, text)
enum Msg           { JOIN_REQUEST = 0x01, JOIN_REJECT = 0x02, JOIN_ACCEPT = 0x03, LOBBY_SNAPSHOT = 0x04, LOBBY_ACTION = 0x05,
                     CHAT = 0x06, LEAVE = 0x07, KICKED = 0x08, MAP_PING = 0x09, DATA_DIFF = 0x0A,
                     LAUNCH_COUNTDOWN = 0x10, LAUNCH_ABORT = 0x11, LAUNCH_CONFIG = 0x12, LOAD_PROGRESS = 0x13, LOAD_DONE = 0x14,
                     START = 0x15, LOAD_STATUS = 0x16, RETURN_TO_LOBBY = 0x17, LOAD_FAILED = 0x18,
                     TURN_INPUT = 0x20, TURN_BUNDLE = 0x21, PING = 0x22, PONG = 0x23, STALL_INFO = 0x24, PAUSE_REQUEST = 0x25, RESUME = 0x26,
                     CHECKSUM_REPORT = 0x30, DESYNC_NOTICE = 0x31, PARTS_REQUEST = 0x32, PARTS_REPORT = 0x33, MATCH_END = 0x34,
                     CATCHUP_REQUEST = 0x40, CATCHUP_CHUNK = 0x41, CATCHUP_DONE = 0x42 }   # message type byte (table in §4.3)
```

### 4.3 Wire primitives and framing

* Little-endian everywhere. `u8/u16/u32`, `i8/i16`. **`varint`** = unsigned LEB128, canonical (no overlong forms, at most 5 bytes, value <= 0xFFFFFFFF); **`zvarint`** = zigzag(int32) then varint (`zz = ((v << 1) ^ (v >> 31)) & 0xFFFFFFFF`); **`str`** = `u8 len` + UTF-8 (field cap stated; longer or invalid UTF-8 => decode error; validity is checked by `NetProtocol.is_valid_utf8` **before** the engine decoder runs, because `get_string_from_utf8()` on invalid bytes logs `Unicode parsing error` engine messages — measured — and a NUL byte silently truncates the string); **`bytes`** = `varint len` + raw.
* One message per ENet packet: `[u8 type][body]`. ENet reassembles fragments (verified: 4 MB reliable packet delivered intact and in order), so message length == packet length. No per-packet header (ENet already provides sequencing, acks, connection ids).
* `NetReader` contract: every accessor bounds-checks; on overrun it sets `ok = false`, moves the cursor to the end and returns `0`/`""`; a decoder returns `null`/`{}` if `ok` is false **or** bytes remain unread (`left() != 0`). No decoder ever calls `PackedByteArray.decode_*` out of range (that logs an engine ERROR, which the QA runner counts as a test failure) and none uses `StreamPeerBuffer` (past-end reads return garbage silently — measured).
* Direction/channel/limits/phase matrix (enforced by `NetSession` before any handler runs; violations score per §5.12):

| Code | Message | Dir | Ch | Max bytes | Allowed when | Rate |
|---|---|---|---|---|---|---|
| 0x01 | `JOIN_REQUEST` | C->H | 0 | 8192 (about 450 without file hashes) | peer in `HANDSHAKE`; once per connection (the file-hash retry is a fresh connection) | 1 |
| 0x02 | `JOIN_REJECT` | H->C | 0 | 200 | client `CONNECTING` | — |
| 0x03 | `JOIN_ACCEPT` | H->C | 0 | 16 | client `CONNECTING` | — |
| 0x04 | `LOBBY_SNAPSHOT` | H->C | 0 | 3072 | client in any post-accept phase | 10/s |
| 0x05 | `LOBBY_ACTION` | C->H | 0 | 80 | lobby `OPEN` (`SET_READY(false)` also in `COUNTDOWN`) | 10/s |
| 0x06 | `CHAT` | both | 0 | 260 | seated/spectator, any phase after accept | 5 per 5 s |
| 0x07 | `LEAVE` | C->H | 0 | 4 | any | 1/s |
| 0x08 | `KICKED` | H->C | 0 | 120 | any | — |
| 0x09 | `MAP_PING` | both | 0 | 8 | `PLAYING` | 2/s |
| 0x0A | `DATA_DIFF` | H->C | 0 | 3200 | right after a `JOIN_REJECT(DATA_MISMATCH)` | — |
| 0x10 | `LAUNCH_COUNTDOWN` | H->C | 0 | 4 | lobby | — |
| 0x11 | `LAUNCH_ABORT` | H->C | 0 | 120 | `COUNTDOWN..WAIT_START` | — |
| 0x12 | `LAUNCH_CONFIG` | H->C | 0 | 40000 | `COUNTDOWN`/`LOBBY` | — |
| 0x13 | `LOAD_PROGRESS` | C->H | 0 | 4 | `LOADING` | 4/s |
| 0x14 | `LOAD_DONE` | C->H | 0 | 16 | `LOADING`; once | 1 |
| 0x15 | `START` | H->C | 0 | 12 | `WAIT_START` | — |
| 0x16 | `LOAD_STATUS` | H->C | 0 | 24 | `LOADING` | 4/s |
| 0x17 | `RETURN_TO_LOBBY` | H->C | 0 | 2 | `ENDED` | — |
| 0x18 | `LOAD_FAILED` | C->H | 0 | 120 | `LOADING`; once | 1 |
| 0x20 | `TURN_INPUT` | C->H | 1 | 6200 | host phase `PLAYING`/`PAUSED` | 40/s burst 64 |
| 0x21 | `TURN_BUNDLE` | H->C | 1 | 52000 | `WAIT_START` (buffered), `PLAYING`, `PAUSED` | — |
| 0x22 | `PING` | H->C | 1 | 12 | game phases | — |
| 0x23 | `PONG` | C->H | 1 | 24 | game phases | 8/s |
| 0x24 | `STALL_INFO` | H->C | 1 | 200 | `PLAYING` | — |
| 0x25 | `PAUSE_REQUEST` | C->H | 1 | 4 | `PLAYING`/`PAUSED` | 1/s |
| 0x26 | `RESUME` | H->C | 1 | 12 | `PAUSED` | — |
| 0x30 | `CHECKSUM_REPORT` | C->H | 0 | 16 | `PLAYING`..`ENDED` | 4/s |
| 0x31 | `DESYNC_NOTICE` | H->C | 0 | 120 | game phases | — |
| 0x32 | `PARTS_REQUEST` | H->C | 0 | 80 | game phases | — |
| 0x33 | `PARTS_REPORT` | C->H | 0 | 64 | after `PARTS_REQUEST` | 2/s |
| 0x34 | `MATCH_END` | H->C | 0 | 16 | `PLAYING`/`ENDED` | — |
| 0x40 | `CATCHUP_REQUEST` | C->H | 0 | 8 | spectator, `WAIT_START` | 1/s |
| 0x41 | `CATCHUP_CHUNK` | H->C | 2 | 60000 | spectator catching up | — |
| 0x42 | `CATCHUP_DONE` | H->C | 0 | 8 | spectator catching up | — |

### 4.4 Message layouts (byte-exact)

**Frozen prefixes.** `JOIN_REQUEST` and `JOIN_REJECT` must stay decodable by any future version: their first fields (`type`, `proto_version`) never move. A host that sees `proto_version != PROTO_VERSION` **must not parse further**; it answers `JOIN_REJECT(PROTO_MISMATCH)` built from the frozen layout below and closes gracefully.

```
JOIN_REQUEST 0x01 (C->H)                                  | golden (proto 1, no flags, sim 7, data 0x11223344, nonce 0xCAFEBABE, "0.3.1", "Bob"):
  u8  type=0x01                                            | 01 01 00 00 07 00 00 00 44 33 22 11 BE BA FE CA 05 30 2E 33 2E 31 03 42 6F 62   (26 bytes)
  u16 proto_version
  u8  flags               bit0 spectator, bit1 has_password, bit2 has_tables, bit3 has_files
  u32 sim_version
  u32 data_hash
  u32 client_nonce        random per process start (ban key together with IP)
  str game_version        <= 24 bytes (informational)
  str name                <= 48 bytes (sanitised by host)
  [flags.bit1] u8[32] pw_proof = ("%d:%s" % [session_id, password]).sha256_buffer()   # String.sha256_buffer(); session_id from discovery or from JOIN_REJECT(BAD_PASSWORD)
  [flags.bit2] u8 data_format, u8 n(<=32), n x { str table_name(<=32), u32 hash }        # GameData.handshake(false): format + table_hashes (16 tables, ~250 bytes)
  [flags.bit3] u16 n(<=160), n x { str path(<=64), u32 hash }                            # GameData.handshake(true).files, sent only on the retry after DATA_DIFF.wants_files (<= 8 KB)

JOIN_REJECT 0x02 (H->C)
  u8  type=0x02
  u16 host_proto_version
  u8  reason              RejectReason
  u32 host_sim_version
  u32 host_data_hash
  u32 host_session_id
  str host_game_version   <= 24
  str detail              <= 96 (English, informational; UI builds its own text from reason + numbers)

JOIN_ACCEPT 0x03 (H->C)
  u8  type=0x03
  u16 peer_id             >= 2
  u32 session_id
  u8  slot                0..7 seated, 255 spectator
  u8  phase               LobbyPhase        # immediately followed by a LOBBY_SNAPSHOT message

DATA_DIFF 0x0A (H->C)                            # sent right after JOIN_REJECT(DATA_MISMATCH) when the JOIN_REQUEST carried tables (bit2)
  u8  type=0x0A
  u8  flags               bit0 wants_files (host can also compare per-file hashes: the client should retry once with flags.bit3)
  u8  n                   0..32
  n x str line(<=96)      opts.data_diff(host_handshake, client_handshake): e.g. "table units differs", "file balance/units_napc.json differs"
```

```
LOBBY_SNAPSHOT 0x04 (H->C)                     # full state, last-writer-wins by revision; host coalesces to >= 100 ms apart
  u8  type=0x04
  u32 revision            monotonically increasing; clients ignore snapshots with revision <= their current
  u8  phase               LobbyPhase
  u8  flags               bit0 password_set, bit1 allow_spectators
  str host_name           <= 48
  u8  map_family          0 open land, 1 urban routes, 2 coast & river
  u8  map_size_div8       size/8 (12..32 => 96..256)
  u32 map_seed
  u8  layout_players      2|4|6|8
  u8  rule_count          0..16
  rule_count x { str key(<=24), i32 value }      # schema-driven MatchRules (lobby_options.json "rules_schema"); bool = 0/1; the host validates keys and ranges, clients just mirror
  u8  speed_code          index into SPEED_PCT
  u8  pause_policy        PausePolicy
  u8  on_disconnect       OnDisconnect
  u16 auto_drop_s         0 = off
  8 x slot:
    u8 kind (SlotKind)  u16 peer_id  str name(<=48)  str roster(<=40: roster id or random token)  u8 team  u8 color
    u8 start (255 = random)  u8 handicap_div5 (10..40)  u8 flags (bit0 ready, bit1 connected)  u8 ai_level  u8 ai_style  u8 ai_flags  u16 ping_ms
  u8  spectator_count     0..8
  spectator_count x { u16 peer_id, str name(<=48) }
LOBBY_ACTION 0x05 (C->H):  u8 type, u8 op(LobbyOp), then per op:
  SET_ROSTER: str(<=40) | SET_TEAM: u8 | SET_COLOR: u8 | SET_START: u8 (255 = random) | SET_READY: u8 | SET_NAME: str(<=48)
  MOVE_TO_SLOT: u8 slot | TO_SPECTATOR: — | TO_PLAYER: —
CHAT 0x06:  C->H: u8 type, u8 channel(0 all,1 team), bytes text(<=200)
            H->C: u8 type, u8 channel, u8 from_slot(255 = system), str from_name(<=48), bytes text(<=200)
LEAVE 0x07 (C->H): u8 type, u8 reason(0 normal)          KICKED 0x08 (H->C): u8 type, u8 reason(KickReason), str detail(<=96)
MAP_PING 0x09: C->H: u8 type, u16 cell_x, u16 cell_y      H->C (team only): u8 type, u8 from_pid, u16 cell_x, u16 cell_y
```

```
LAUNCH_COUNTDOWN 0x10 (H->C): u8 type, u8 seconds_left (0 = aborted)
LAUNCH_ABORT     0x11 (H->C): u8 type, u8 reason(AbortReason), u8 pid(255 none), str detail(<=96)
LAUNCH_CONFIG    0x12 (H->C): u8 type, u32 json_len, u32 json_fnv (FNV-1a of the inflated UTF-8 bytes), <zlib/DEFLATE bytes = rest of packet>
                              inflate with PackedByteArray.decompress_dynamic(MAX_CONFIG_JSON, FileAccess.COMPRESSION_DEFLATE); bounded => zip-bomb safe
LOAD_PROGRESS    0x13 (C->H): u8 type, u8 pct        LOAD_STATUS 0x16 (H->C): u8 type, u8 n, n x { u8 pid, u8 pct }
LOAD_DONE        0x14 (C->H): u8 type, u32 map_hash, u32 checksum0
LOAD_FAILED      0x18 (C->H): u8 type, u8 reason(AbortReason), str detail(<=96)
START            0x15 (H->C): u8 type, u32 config_hash, u8 input_delay, u16 speed_pct     | golden: 15 AE BA A5 8F 02 64 00  (hash 0x8FA5BAAE, D=2, 100 %)
RETURN_TO_LOBBY  0x17 (H->C): u8 type
```

```
TURN_INPUT 0x20 (C->H, ch1)          | golden (turn 5, exec_turn 3, one command [3,17,4096]): 20 05 00 00 00 03 00 00 00 01 03 06 22 80 40   (15 bytes)
  u8  type=0x20
  u32 turn                 target execution turn (>= sender's exec_turn; the host stamps the pid from the connection: there is NO pid field)
  u32 exec_turn            sender's current execution turn (stall UI, lag diagnostics; not trusted for anything else)
  varint cmd_count         0..64 (0 = heartbeat)
  cmd_count x { varint n (1..1024); n x zvarint }        # n ints: [command_type(0..255), args...]

TURN_BUNDLE 0x21 (H->C, ch1)         | golden: turn 5, pid0:[[3,17,4096]], pid4:[[7,-1]]  =>
  u8  type=0x21                        21 05 00 00 00 00 02 00 01 03 06 22 80 40 04 01 02 0E 01 98 E8 2D EF   (23 bytes; FNV 0xEF2DE898 over bytes [1..end-4))
  u32 turn                 == previous bundle turn + 1 (bundles are strictly contiguous)
  u8  flags                bit0 has_ctrl (other bits must be 0)
  u8  group_count          0..8
  group_count x { u8 pid (0..7, strictly ascending); varint cmd_count (1..64); cmd_count x { varint n; n x zvarint } }
  [flags.bit0] u8 ctrl_count (1..8); ctrl_count x ctrl record          | golden: turn 6 + CK_INPUT_DELAY(3):  21 06 00 00 00 01 00 01 01 03 F1 F5 90 5B
  u32 hash                 FNV-1a 32 over bytes [1 .. position of hash), i.e. everything after `type`
ctrl records:  CK_INPUT_DELAY(1): u8 kind, u8 d(1..8)  |  CK_PLAYER_STATUS(2): u8 kind, u8 pid, u8 status, u8 aux
               CK_SPEED(3): u8 kind, u16 speed_pct(50..200)  |  CK_MATCH_END(4): u8 kind, u8 reason  |  CK_PAUSE(5): u8 kind, u8 by_pid(255 = host)

PING 0x22 (H->C): u8 type, u32 seq, u32 host_ms (low 32 bits of clock ms; RTT = (now_ms - echo_ms) & 0xFFFFFFFF, wrap-safe)        | golden (seq 7, 123456 ms): 22 07 00 00 00 40 E2 01 00
PONG 0x23 (C->H): u8 type, u32 seq, u32 echo_ms, u32 exec_turn, i16 slack_min_ms, u16 stall_ms, u8 episodes, u8 load_pct, u8 flags(bit0 hitch)
                  golden (seq 7, echo 123456, exec 310, slack -12, no stall, load 35 %): 23 07 00 00 00 40 E2 01 00 36 01 00 00 F4 FF 00 00 00 23 00
STALL_INFO 0x24 (H->C): u8 type, u32 turn, u8 n(0..8), n x { u8 pid, u8 reason(StallReason), u16 wait_ms }        # sent every 250 ms while the barrier is blocked; a final n=0 message clears the overlay
PAUSE_REQUEST 0x25 (C->H): u8 type, u8 want_paused          RESUME 0x26 (H->C): u8 type, u32 resume_turn, u8 by_pid
CHECKSUM_REPORT 0x30 (C->H): u8 type, u32 tick, u32 checksum, u32 input_chain   | golden (tick 4200, 0xE50086E1, 0xA6C168F3): 30 68 10 00 00 E1 86 00 E5 F3 68 C1 A6
DESYNC_NOTICE 0x31 (H->C): u8 type, u32 tick, u8 kind(DesyncKind), u8 n, n x { u8 pid, u32 checksum, u32 chain }
PARTS_REQUEST 0x32 (H->C): u8 type, u32 tick, u8 n(<=16), n x u32 host_parts      PARTS_REPORT 0x33 (C->H): u8 type, u32 tick, u8 n(<=16), n x u32
MATCH_END 0x34 (H->C): u8 type, u32 final_tick, u32 final_checksum, u8 reason(MatchEndReason), i8 winner_team
CATCHUP_REQUEST 0x40 (C->H): u8 type, u32 from_turn
CATCHUP_CHUNK 0x41 (H->C, ch2): u8 type, u32 first_turn, u16 turn_count, u32 raw_len, <DEFLATE of raw = concatenated replay TURNS records (§4.8) for turns >= first_turn>
CATCHUP_DONE 0x42 (H->C): u8 type, u32 next_live_turn
```

**Discovery datagram** (UDP, `DISCOVERY_PORT`, one datagram per announce, <= 128 bytes; unknown flag bits ignored; `layout_version` bump = ignore):

```
off size field
 0   4  magic "MFDS" (4D 46 44 53)
 4   1  layout_version = 1
 5   1  kind: 1 ANNOUNCE, 2 CLOSED
 6   2  proto_version
 8   4  session_id
12   2  game_port
14   4  data_hash
18   4  sim_version
22   1  flags: bit0 has_password, bit1 in_progress, bit2 full, bit3 spectators_allowed, bit4 dedicated
23   1  humans (connected human players)      24 1 slots_total (non-closed player slots)      25 1 slots_free (OPEN slots)
26   1  map_family                            27 1 map_size_div8                              28 1 ai_count        29 1 reserved(0)
30   .. str host_name (<=24 bytes)            .. str game_version (<=16 bytes)
golden (session 0xDEADBEEF, port 27615, data 0x11223344, sim 7, humans 2, total 4, free 2, family 0, 128 cells, "Simon's game", "0.3.1"):
4D 46 44 53 01 01 01 00 EF BE AD DE DF 6B 44 33 22 11 07 00 00 00 00 02 04 02 00 10 00 00 0C 53 69 6D 6F 6E 27 73 20 67 61 6D 65 05 30 2E 33 2E 31   (49 bytes)
```
The browser derives the join address from the datagram's **source IP** (`PacketPeerUDP.get_packet_ip()`), never from the payload (multi-homed hosts, NAT-free LAN correctness).

### 4.5 Lobby data model

```gdscript
class_name NetPlayerSlot extends RefCounted
var index: int = 0                # 0..7; == pid at launch
var kind: int = 1                 # SlotKind
var peer_id: int = 0              # 0 none; 1 = host; >= 2 remote (HUMAN); AI slots keep 0
var name: String = ""             # sanitised, <= 24 chars, unique among slots (suffix " (2)")
var roster_id: String = "random"  # one of 32 roster ids or a random token (§5.3.4)
var team: int = 0                 # 0 none, 1..4 = A..D
var color: int = 0                # 0..color_count-1, unique among non-closed slots
var start: int = -1               # -1 random else 0..layout_players-1, unique
var handicap_pct: int = 100       # 50..200 step 5 (§5.3.6)
var ready: bool = false           # AI slots and the host are always ready
var connected: bool = false       # transport-connected (AI = true)
var ai_level: int = 1             # 0..ai_level_count-1
var ai_style: int = 0
var ai_flags: int = 0             # bit0 fog_cheat (default set for the top AI level by the AI domain); passed through to players[].ai.flags
var ping_ms: int = 0              # display only, host-measured
func duplicate_slot() -> NetPlayerSlot
```
```gdscript
class_name NetLobbyState extends RefCounted
var revision: int = 0
var phase: int = 0                # LobbyPhase
var host_name: String = ""
var session_id: int = 0           # random u32 at lobby creation
var password_set: bool = false
var allow_spectators: bool = true
var map_family: int = 0
var map_size: int = 128           # cells, multiple of 8, 96..256
var map_seed: int = 0             # u32
var layout_players: int = 4       # 2|4|6|8 ; slots >= layout_players are CLOSED
var rules: Dictionary = {}        # key:String -> int (bools as 0/1) for every key of lobby_options.json rules_schema; defaults: start_credits 7500, unit_cap 150, superweapons 1, fog 1, shared_vision 0, veterancy 0, vision_stride 2, vision_budget 128
var speed_code: int = 2           # -> SPEED_PCT
var pause_policy: int = 1
var on_disconnect: int = 0
var auto_drop_ms: int = 60000
var slots: Array[NetPlayerSlot] = []           # always 8
var spectators: Array[Dictionary] = []         # [{peer_id:int, name:String}]
func slot_of_peer(peer_id: int) -> int         # -1 if none
func active_slot_indices() -> PackedInt32Array # kind HUMAN or AI, ascending
func human_count() -> int
func ai_count() -> int
func first_open_slot() -> int                  # -1 if none
func duplicate_state() -> NetLobbyState
static func create_default(host_name: String, session_id: int, map_seed: int, opts: NetSessionOptions) -> NetLobbyState   # slot 0 HUMAN(host), slot 1 OPEN(...), defaults from lobby_options.json
static func create_skirmish(local_name: String, local_roster: String, opts: NetSessionOptions) -> NetLobbyState      # slot 0 HUMAN, slot 1 AI, rest CLOSED
```
```gdscript
class_name NetPeerInfo extends RefCounted      # host-side record per remote connection
var peer_id: int; var address: String; var stage: int     # 0 HANDSHAKE, 1 LOBBY, 2 LOADING, 3 LOADED, 4 PLAYING, 5 LEFT
var connected_at_ms: int; var nonce: int; var name: String; var slot: int = -1; var is_spectator: bool
var limiter: NetRateLimiter; var violations: float; var last_violation_ms: int
var loaded: bool; var load_pct: int; var map_hash: int; var checksum0: int
var catchup_next: int = -1                                  # spectator catch-up cursor
var stats: NetPeerStats
```
```gdscript
class_name NetFaultProfile extends RefCounted
var name: String = "custom"
var latency_ms: float = 0.0         # one-way base delay
var jitter_ms: float = 0.0          # uniform in [-jitter, +jitter]
var loss_pct: float = 0.0           # ordered mode: each loss event adds rto_ms (geometric retransmits); unordered mode: message dropped
var rto_ms: float = -1.0            # < 0 => 2*latency + 4*jitter + 33 (matches ENet's RTT+4*var + frame time)
var dup_pct: float = 0.0            # unordered mode only (ordered mode dedups like ENet)
var reorder_pct: float = 0.0        # unordered mode: extra delay uniform [0, 2*latency + jitter]
var ordered: bool = true            # true = FIFO per (peer, channel) (ENet reliable model); false = raw UDP-like
var bandwidth_kbps: int = 0         # 0 = unlimited; adds size*8/kbps serialisation delay (FIFO)
var freeze_every_ms: int = 0        # every period the endpoint neither sends nor delivers for freeze_ms (frame hitch / suspend)
var freeze_ms: int = 0
var disconnect_after_ms: int = 0    # 0 = never
static func preset(name: String) -> NetFaultProfile
# presets: lan{0.5,0.3} wifi{10,8,loss 1} bad_wifi{30,25,loss 3} internet{75,15,loss 1} awful{150,60,loss 4}
#          raw_chaos{20,15,dup 3,reorder 10, ordered=false} local{0.1,0}
```

### 4.6 Lockstep state (exact fields; implementers must not add sim-visible state)

```gdscript
# NetLockstep (all peers)
var _sim: NetSimAdapter; var _clock: NetClock; var _local_pid: int = -1
var _tick_us: int = 50_000; var _speed_pct: int = 100; var _delay: int = 2
var _acc_us: int = 0; var _last_us: int = 0
var _queue: Dictionary = {}          # turn:int -> NetBundle, received and contiguous, not yet executed (insertion ordered)
var _arrival_us: Dictionary = {}     # turn:int -> int (poll time the bundle became executable) for slack measurement
var _next_push: int = 0              # next bundle turn expected; _ooo holds turns in (_next_push, _next_push + REORDER_WINDOW]
var _ooo: Dictionary = {}
var _sent_through: int = -1          # highest turn for which this peer produced a TURN_INPUT (pre-roll: D0-1)
var _pending: Array[PackedInt32Array] = []
var _chain: int = 0x811C9DC5         # FNV-1a input chain over core_bytes of executed turns
var _paused: bool = false; var _pause_after_turn: int = -1; var _paused_at_turn: int = -1; var _resume_turn: int = -1   # RESUME watermark
var _stall_since_us: int = -1; var _stall_is_hitch: bool = false
var _rep_slack_min_ms: int = 32767; var _rep_stall_ms: int = 0; var _rep_episodes: int = 0; var _rep_hitch: bool = false
var _step_cost_us_ewma: int = 0; var _over: bool = false
```
```gdscript
# NetTurnHost (host only)
var _role: PackedInt32Array          # size 8, PlayerRole
var _peer_of: PackedInt32Array       # size 8, transport peer id (0 for AI/none)
var _recv_through: PackedInt32Array  # size 8, contiguous inputs received through this turn; init D0-1; -1 for non-humans
var _inputs: Array[Dictionary]       # size 8: turn -> Array[PackedInt32Array] (contiguous and out-of-order within REORDER_WINDOW)
var _next_close: int = 0
var _inject_through: int = -1        # host-local fill-up frontier (local human + AI); set to D0-1 at start (pre-roll), then advanced by note_injection_through(); only enforced if the host has a local human or any AI
var _ai_cmds: Dictionary             # turn -> Array of [pid, Array[PackedInt32Array]]
var _ctrl_queue: Array[PackedInt32Array]         # ctrl records to attach to the next closed bundle
var _resign_queue: Dictionary        # pid -> ResignReason (a T_RESIGN command is injected into that pid's group at the next close)
var _delay: int; var _delay_min: int; var _delay_max: int; var _fixed_delay: int
var _policy: NetDelayPolicy; var _speed_pct: int
var _paused_from: int = -1; var _pause_by: int = 255; var _pause_started_us: int; var _pauses_used: PackedInt32Array   # size 8
var _block_since_us: Dictionary      # pid -> us when the current turn started waiting on that pid
var _prompted: Dictionary            # pid -> true when the host prompt was already raised
var _last_stall_info_us: int
```
```gdscript
# NetDelayPolicy per peer
class PeerEntry: rtt_ms: float; jit_ms: float; samples: int; quarantine_until_ms: int; ring: Array  # ring of [t_ms, slack_min_ms, stall_ms] (<= 20)
# globals: last_change_ms: int; below_since_ms: int
```

### 4.7 `stats()` dictionary (HUD / net overlay; all keys always present)

`{role, phase, tick, turn, delay_turns, speed_pct, rtt_ms:{pid:int}, jitter_ms:{pid:int}, stall_ms:int, stall_count:int, slack_ms:int, bundles_buffered:int, kbps_in:float, kbps_out:float, pkts_in:int, pkts_out:int, load_pct:int, dropped_cmds:int, violations:int, dup_in:int, late_in:int, ooo_in:int, ai_us:{pid:int}, chain:int, last_checksum_tick:int, transport:String}`

### 4.8 Replay file format (`*.mfreplay`, format_version 1)

```
FileHeader (16 bytes, fixed)              HeaderJson (json_len bytes, UTF-8)
  0  4  magic "MFRP" (4D 46 52 50)          {"replay": {"format":1,"recorder_peer":1,"recorder_pid":0,"started_unix":1790677613,
  4  2  format_version u16 = 1                          "os":"macOS","arch":"arm64","engine":"4.7.2-stable","game_version":"0.1.0"},
  6  2  flags u16 = 0 (reserved)              "config": <MatchConfig, §7.1>}          # canonical JSON (sorted keys, ints only)
  8  4  json_len u32                         ("config" inside the header is byte-identical to the LAUNCH_CONFIG json when recorded by host/clients)
 12  4  json_fnv u32 (FNV-1a of HeaderJson bytes)
Records* : u8 type | varint payload_len | payload        (unknown types skipped via payload_len; forward compatible)
  0x01 TURNS  : varint gap | u8 group_count | groups      # gap = number of EMPTY turns since the previous TURNS record (first record: gap = turn number). Turn = last_turn + 1 + gap. groups exactly as in TURN_BUNDLE
  0x02 CHECK  : u32 tick | u32 checksum | u32 input_chain          # every 20 ticks (the ARCH §6 snapshot cadence)
  0x03 PARTS  : u32 tick | u8 n | n x u32                          # sub-checksums, every 200 ticks
  0x04 EVENT  : u32 turn | u8 kind (ReplayEvent) | PLAYER_STATUS: u8 pid,u8 status,u8 aux | CHAT: u8 pid, bytes text
  0x05 END    : u32 final_tick | u32 final_checksum | u32 final_chain | u8 reason (MatchEndReason) | i8 winner_team | u32 total_turns     (18-byte payload)
Trailer (after END, 8 bytes): u32 end_record_size (= 20) | "MFRE" (4D 46 52 45)     # lets the replay browser read the result by seeking to EOF-8
```
Finalised = END record + valid trailer. A file without them (crash/kill) is **truncated but playable**: the loader stops at the first incomplete record and sets `truncated = true`. Size reference: empty turns cost 0 bytes, a typical command ~10-25 bytes, CHECK 15 bytes/s => 1 h of an 8-player match ~ 0.5-3 MB.

### 4.9 Reference command int-array contract (net's view of a command)

A command is `PackedInt32Array` = `[type, a0, a1, ...]`: `type` in `0..255`, `1 <= size <= 1024`, all values int32. **No pid, no sequence number, no timestamp inside** — the pid is stamped by the host from the connection and travels as the bundle group id. Order of execution within a turn = ascending pid, then the order the player issued them. Everything else about a command (meaning, ownership checks, target validity) belongs to `sim` [XR-2].

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Transport: decision, evidence, parameters

**Decision: `ENetConnection` + `ENetPacketPeer` (the ENet library Godot ships), reliable + ordered channels, driven by our own `NetTransport` abstraction.** Not `ENetMultiplayerPeer`/`SceneMultiplayer`/RPC, not raw `PacketPeerUDP` for gameplay, not `StreamPeerTCP`.

| Option | Verdict | Reason |
|---|---|---|
| `ENetConnection` (chosen) | yes | Reliable/ordered/fragmenting/ack/RTT built in; connect-data and disconnect-code ints (used for magic/reject codes); per-peer `set_timeout`, RTT stats; no `SceneTree` needed => unit-testable in one process (two hosts on 127.0.0.1, verified) and runs under `--headless` |
| `ENetMultiplayerPeer` + `MultiplayerAPI` RPC | no | Adds peer-id remapping, node-path caches and RPC checksums for features we do not use; no access to connect data; couples the session to the `SceneTree`; hides service/flush timing that determines lockstep latency |
| `PacketPeerUDP` for gameplay | no | We would re-implement reliability, ordering, fragmentation, congestion. Kept only for LAN discovery |
| `StreamPeerTCP`/`TCPServer` | no | Head-of-line blocking on loss is the same as ENet-reliable but without RTT stats, without connect data, Nagle tuning is not exposed |
| Unreliable + redundant last-N-turns (GGPO style) | future | Removes retransmit stalls on lossy links; unnecessary for LAN (loss < 3 %, ENet RTO ~ RTT + 4 var) and doubles the state machine. Protocol is transport-agnostic (dup/ooo tolerant, §5.5.5), so it can be added without a format change |

**Why reliable + ordered fits lockstep.** Every input must arrive exactly once, or the barrier stalls forever/desyncs; ENet reliable channels retransmit with RTO = RTT + 4 x variance (doubling) and never reorder within a channel. Head-of-line blocking is harmless for lockstep because turn N+1 is useless without turn N anyway. Prototype: with 3 % loss and 30+-25 ms links the adaptive delay settles at D = 4 with 0.9 % of time stalled.

**Evidence (experiments on the real 4.7.2 binary; scratch project outside the repo).**

| # | Finding | Consequence in this spec |
|---|---|---|
| E1 | `ENetConnection.service(0)` returns `[event, ENetPacketPeer, data:int, channel:int]`; on `EVENT_RECEIVE` the payload is `peer.get_packet()`. Connect `data` (0xABCD1234) reaches the host in `EVENT_CONNECT`; disconnect `data` (777) reaches the remote in `EVENT_DISCONNECT`. 1 B .. 4 MB reliable packets arrive intact, in order. The same `ENetPacketPeer` object is returned for a peer across events | Magic/proto in connect data; reject/kick codes in disconnect data; no app-level fragmentation |
| E2 | Bind on a used port: `create_host_bound` -> `ERR_CANT_CREATE (20)` **and an engine ERROR line**; `PacketPeerUDP.bind` -> `ERR_UNAVAILABLE (2)`, quiet. A second UDP bind of the same port in one process fails (no reuse) | Quiet UDP probe before creating the ENet host; only one discovery *listener* per machine, so hosting never binds the discovery port |
| E3 | Limited broadcast `255.255.255.255` -> `put_packet` FAILED (no route in this VM); directed `/24` guess FAILED because the NIC is `/16`; `172.16.255.255` delivered, looped back to a local listener with the LAN source IP. `IP.get_local_interfaces()` gives `name/friendly/index/addresses` but **no netmask**. Multicast send failed here; multicast join works only on an IPv4-bound socket (dual-stack `*` fails on macOS) and logs an ERROR for interfaces without IPv4 | Broadcast candidate set with per-target circuit breaker (§5.2); multicast deferred |
| E4 | `create_host_bound("*")` and `("::")` are dual-stack (accept `127.0.0.1`, `::1`, `localhost`, and `localhost` resolves to `::1` first); `"0.0.0.0"` is IPv4-only | Host binds `"*"`, falls back to `"0.0.0.0"` (IPv6-disabled kernels/containers); tests connect to `127.0.0.1` literally |
| E5 | A peer that stops servicing is detected after **6.5 s** with `set_timeout(32, 5000, 30000)` and **4.8 s** with `(32, 3000, 6000)` | Game timeouts `(32, 5000, 12000)`; the 8 s stall prompt therefore applies to *slow-but-alive* peers, dead ones surface as `DISCONNECTED` first |
| E6 | Bundle codec cost (8 groups x 4 cmds x 15 ints = 1335 B): encode 180 us, decode 209 us; FNV-1a 26 us; fuzz of 20 000 random/mutated buffers: 66 ms, zero engine errors | §9 budget; `NetReader` design validated |
| E7 | `JSON.parse_string` yields **floats** for every number and `inf` for `1e400`; malformed input -> null + engine ERROR (use `JSON.new().parse()`); `StreamPeerBuffer` past-end reads return garbage silently; `PackedByteArray.decode_u32` out of range logs an ERROR; `get_string_from_utf8()` on invalid bytes logs `Unicode parsing error` engine messages and replaces bytes with U+FFFD (an embedded NUL truncates silently); `decompress_dynamic` supports DEFLATE/GZIP/Brotli only (not ZSTD), enforces `max_output_size` (8 MB-of-zeros bomb with a 64 KiB cap -> empty result in 100 us) | JSON only for the size-capped launch config with integer normalisation; DEFLATE for all compressed payloads; custom `NetReader` |
| E8 | ENet compression on 90-byte payloads: range coder -13 %, zlib -16 %; **mismatched compression modes refuse to connect**. Connecting to a closed port reports failure only after **31.5 s**. `send()` on a channel >= the configured count returns 31 and logs an ERROR | `COMPRESS_NONE`; own 6 s connect timeout; channel range asserted before sending |
| E9 | Two real headless processes on 127.0.0.1: connect data, a `KICKED` message followed by `peer_disconnect_later(4242)` arrive in that order. App-level RTT between two ~16 ms service loops: avg 26 ms, p95 47 ms (RTT includes the remote frame time). `get_statistic` on a disconnected peer logs `Parameter "peer" is null` | Delay policy adds a 34 ms frame margin; never touch stats of a peer whose `get_state() != STATE_CONNECTED` |
| E10 | ENet cost on one machine with 8 connected peers: `service(0)` idle **9 us**; sending 8 x 120 B + `flush()` **42 us**; 2400/2400 packets received | §9 budget uses these numbers |

**Parameters.**
* Host: `ENetConnection.create_host_bound(bind, port, ENET_MAX_PEERS=24, CHANNEL_COUNT=3, 0, 0)`; bind `"*"` then `"0.0.0.0"`. Port scan: for `p` in `port .. port+9`: `PacketPeerUDP.bind(p, "*")` (quiet probe) -> close -> create the ENet host; first success wins (if creation still fails after a successful probe — race, or a different address family holding the port — continue with the next port); none => `ERR_ALREADY_IN_USE` surfaced to UI (`net.err.no_port`). The chosen port is announced and shown in the lobby ("192.168.1.20:27617").
* Client: `create_host(1, CHANNEL_COUNT)` then `connect_to_host(ip, port, CHANNEL_COUNT, connect_data)`, `connect_data = 0x4D460000 | PROTO_VERSION` ("MF" + proto). The host `disconnect_now`s any ENet peer whose connect data lacks the magic (foreign ENet clients). Hostnames (non-literal, `!address.is_valid_ip_address()`) are resolved **asynchronously** with `IP.resolve_hostname_queue_item` polled in `poll()` (5 s limit) so an mDNS lookup can never freeze the frame.
* Every message uses `ENetPacketPeer.FLAG_RELIABLE`. Channels: 0 control/lobby/checksums, 1 turns/pings (isolated so a large config never delays a turn), 2 bulk catch-up.
* MTU: ENet default (1400 B datagram). Steady-state messages are 15-500 B (one datagram); anything larger is fragmented and retransmitted per fragment by ENet.
* Bandwidth limits 0 (unlimited); compression none; ENet ping interval left at the 500 ms default.
* `NetTransportEnet.poll()` = `service(0)` until `EVENT_NONE` (cap 256), never a blocking timeout; `flush()` once per frame after all sends.
* IPv6: game traffic works over IPv6 literals (dual-stack socket); discovery is IPv4-only in v1 (broadcast is an IPv4 concept; IPv6 link-local multicast needs interface scoping Godot cannot express).

### 5.2 LAN discovery (`NetDiscovery`)

**Broadcast, not multicast (v1).** Measured (E3): the OS/Godot combination gives no way to pick the multicast egress interface (`IP_MULTICAST_IF` is not exposed), so multicast leaves through the default-route NIC exactly like limited broadcast, without its ubiquity; joining requires an IPv4-bound socket and interface names and logs engine ERRORs on interfaces without IPv4; Wi-Fi access points and IGMP snooping filter multicast more aggressively than broadcast. `DISCOVERY_MCAST = "239.255.76.15"` is reserved for a later opt-in second channel.

**Announce (host).** One unbound `PacketPeerUDP`; `set_broadcast_enabled(true)` **before** the first `set_dest_address` (the order verified in E3); every `DISCOVERY_INTERVAL_MS` (1000 +- 100 ms) send the §4.4 datagram to every *target*:

```
targets = ["127.0.0.1"] + broadcast_candidates(local IPv4 addresses)
broadcast_candidates(ips): out = ["255.255.255.255"]
  for ip a.b.c.d in ips (from IP.get_local_interfaces(); skip 127.x; skip 169.254.x if any other address exists):
      out += [a.b.c.255, a.b.255.255];  if a == 10: out += ["10.255.255.255"]
  dedupe preserving order; cap 12.
  e.g. 172.16.223.202 -> [255.255.255.255, 172.16.223.255, 172.16.255.255]     (the third is the real /16 broadcast, measured to work)
       192.168.1.20   -> [255.255.255.255, 192.168.1.255, 192.168.255.255]
       10.4.7.9       -> [255.255.255.255, 10.4.7.255, 10.4.255.255, 10.255.255.255]
```
A wrong candidate is harmless: the OS either refuses (`EHOSTUNREACH`, measured) or sends one ~50-byte unicast datagram to an unused host address. **Circuit breaker:** `put_packet != OK` five times in a row disables that target for 30 s (no log spam); `announce_ok` is true while any target succeeded in the last 10 s. Interface list is refreshed every 10 s (Wi-Fi roaming, VPN up/down).

**Browse (client).** `PacketPeerUDP.bind(DISCOVERY_PORT, "0.0.0.0")`; `ERR_UNAVAILABLE` => `browse_error = "port_in_use"` (UI: "Another Meridian Fracture window on this PC is already listening for LAN games. Use Join by IP."). Each datagram is validated: length 30..128, magic, `layout_version == 1`, `kind` in {1,2}, strings within caps and valid UTF-8, source IP private/loopback/link-local (`NetProtocol.is_private_ipv4`, overridable by setting `net/allow_public_discovery`), <= 5 datagrams/s per source. Entry key = `(source_ip, session_id)`; refresh `last_seen`; `kind == CLOSED` removes at once; entries not refreshed for 4 s expire; max 64 entries. `compatible = (proto, sim_version, data_hash all equal)` — incompatible games are listed greyed with the mismatch reason, not hidden, so players learn *why* they cannot join.

**Silent failure hints (no false alarms).** If the browser has heard nothing for 8 s after `start_browse()` the UI may show `net.help.no_games` (firewall/permission text, §5.13). If `announce_ok` stays false for 10 s the host lobby shows `net.help.announce_blocked`. Direct join by IP is always available and needs only the host's inbound rule for the game port.

### 5.3 Handshake and lobby rules (`NetLobby`, `NetLobbyState`, `NetMatchConfig`)

**5.3.1 Join.** Client: `connect_to` (<= 6 s) -> `JOIN_REQUEST` -> `JOIN_ACCEPT|JOIN_REJECT` (<= 5 s) -> `LOBBY_SNAPSHOT` (<= 2 s). Host on `CONNECTED`: verify connect-data magic; refuse if `MAX_UNAUTH_PEERS` or `MAX_CONN_PER_IP` exceeded (`disconnect_now`, code `TOO_MANY_CONNECTIONS`); start a 5 s handshake timer. On `JOIN_REQUEST`, checks in this order, first failure wins: (1) `proto_version` (frozen prefix; no further parsing), (2) `sim_version`, (3) `data_hash`, (4) ban list (IP **or** nonce), (5) phase (`IN_GAME` non-spectator -> `IN_PROGRESS`; `COUNTDOWN/LOADING` -> `HOST_BUSY`), (6) password proof, (7) capacity (`LOBBY_FULL`, `SPECTATORS_CLOSED`). A rejected peer receives `JOIN_REJECT` then `disconnect_peer(peer, code = reason, graceful = true)`. `game_version` strings are informational only: **only proto, sim_version and data_hash gate joining** (two builds with equal data and sim behave identically by definition; a differing string alone yields a warning line in chat).

**Data-mismatch diagnosis (carries `GameData.handshake()`, data spec §5.11).** A client with `opts.data_handshake` set always sends its table hashes (`flags.bit2`: `format` + the 16 `table_hashes`, ~250 bytes). On `DATA_MISMATCH` the host answers `JOIN_REJECT` **followed by** `DATA_DIFF` = `opts.data_diff(host_handshake, client_handshake)` (sorted lines such as `table units differs`, `format: 1 vs 2`) and sets `wants_files` when it can also compare per-file hashes. The client session then reconnects **once**, this time with `flags.bit3` (`GameData.handshake(true).files`, <= 160 paths, <= 8 KB), and the second `DATA_DIFF` adds lines like `file balance/units_napc.json differs` / `missing on remote`. The UI receives one `join_rejected(DATA_MISMATCH, info)` with `info.diff_lines` (combined, capped at 32) after the retry finishes (or immediately if the host did not ask for files). A client without `data_handshake` (tests) gets only the hash numbers.

**Clear mismatch message** (UI text built from `JOIN_REJECT` numbers, keys in §5.13): `"Version mismatch. Host: 0.3.1 (data 9F3A21C4). You: 0.3.0 (data 12AB77E0). All players must run the same build."` with the failing check named (`protocol` / `simulation` / `game data`). The hash shown is `%08X` of the u32.

**5.3.2 Permissions** (host validates every `LOBBY_ACTION`; unknown/illegal => ignored, score +1):

| Field | Seated human on own slot | Host on any slot |
|---|---|---|
| roster (32 ids or random token), team (0..4), colour (0..11), start (-1..N-1), name, ready | yes, only while lobby `OPEN` | yes |
| handicap, slot kind (`CLOSED/OPEN/AI`), AI level/style | no | yes |
| map family/size/seed/layout, rules, speed, pause policy, on-disconnect, auto-drop, spectators | no | yes |
| kick / ban | no | yes |

`bible rule.design.roster_selection`: **a roster is atomic** — the lobby stores exactly one of the 32 roster ids per player; there is no per-unit or mixed-subfaction picking, and subfactions are chosen from the same list as vanilla (grouped by faction in the UI).

**5.3.3 Normalisation rules (all deterministic, applied by the host).** Any host change to map, layout, rules or net options, and any change to a *human* slot by the host, clears the `ready` flag of every human except the host (AI slots stay ready), so nobody launches into settings they did not see. Names: `sanitize_name`, unique among seated slots (`"Bob"`, `"Bob (2)"`). Colour conflict: if another non-closed slot holds the colour, **the two slots swap colours**. Start-position conflict: **swap** likewise (a slot with `-1` just takes it). `layout_players` shrink: slots `>= layout_players` become `CLOSED` (a human there is moved to the first OPEN slot, else spectator). New joiner: lowest-index `OPEN` slot, default roster `"random"`, colour = lowest unused, team 0, start -1, not ready. Host slot 0 is `HUMAN` unless `opts.dedicated`. AI slots are always `ready`. Changing an AI slot's level applies `opts.ai_default_handicap(level)` to its `handicap_pct` (Brutal's +20 % economy bonus is visible in the lobby as handicap 120 and labelled by the UI).

**5.3.4 Random tokens** (roster only; colours are always concrete): `"random"` (any of the 32), `"random.vanilla"` (8), `"random.subfaction"` (24), `"random.<fac>"` for each faction code found in the roster ids (`napc nec olm def pd han ae sap`, 4 each). Candidates are the matching ids in ascending string order.

**5.3.5 Resolution at launch** (`NetMatchConfig.from_lobby`, host only, result embedded in the config so clients never re-derive it). With `rs = match_seed ^ 0xA5A5A5A5` and a counter `c = 0` shared across steps: (1) for slots ascending: roster tokens -> `candidates[lobby_rand(rs, c++) % n]`; (2) `team_final = team if team > 0 else 8 + pid`; (3) starts: fixed starts are reserved; remaining active slots are grouped by `team_final` (groups ordered by their lowest slot index), the *group order* is shuffled with Fisher-Yates `for i = n-1 .. 1: j = lobby_rand(rs, c++) % (i+1); swap(i, j)`, members ascending; free start indices ascending; assign consecutive free indices group by group. [XR-12: map orders start indices so that adjacent indices are adjacent on the map, making teammates neighbours]. (4) AI names `"AI <pid+1>"` (locale-free; UI decorates with roster and level). Test vectors: `mix32(1) = 0x514E28B7`, `mix32(0xDEADBEEF) = 0x0DE5C6A9`, `lobby_rand(1, 0..3) = 96A0F96B, 12BC8390, 971E9964, 79ADC7E7`, Fisher-Yates over `[0..7]` with seed 12345 gives `[7,3,2,0,1,6,5,4]`.

**5.3.6 Handicap** (`handicap_pct`, 50..200 step 5, default 100): scales that player's **starting credits and credit income from harvesting/salvage** by `pct/100` (integer math, truncating, in sim). It must not change unit cost, build time, health, damage or reload, so the bible's floors (cost/build time >= 60 %, reload >= 50 %, resistance <= 50 %) and modifier layering are untouched. [XR-9]

**5.3.7 Start validation** (`host_start`, first failing check returns its `StartError`): (1) >= 1 active slot (`NO_PLAYERS`); (2) >= 2 active slots unless `allow_solo` (`NOT_ENOUGH_PLAYERS`); (3) every HUMAN slot connected (`HUMAN_DISCONNECTED`) and ready — the host counts as ready (`HUMAN_NOT_READY`); (4) every active slot has a valid roster id or random token (`BAD_ROSTER`); (5) colours unique (`COLOR_CONFLICT`); (6) concrete starts unique and `< layout_players` (`START_CONFLICT`); (7) active count <= `layout_players` (`TOO_MANY_PLAYERS`); (8) `map_validator(family, size, layout_players) == ""` (`MAP_INVALID`); (9) at least two distinct `team_final` values unless `allow_solo` (`SINGLE_TEAM`); (10) not already launching (`ALREADY_LAUNCHING`); (11) no AI slot while `opts.ai_factory` is null (`AI_UNAVAILABLE`). Success sets `phase = COUNTDOWN` and starts the countdown.

**5.3.8 Countdown.** `COUNTDOWN_S` (3) seconds, `LAUNCH_COUNTDOWN(n)` at 1 Hz. While counting the lobby is locked (`LOCKED`) except `SET_READY(false)` and `LEAVE`, which abort (`LAUNCH_COUNTDOWN(0)`, phase back to `OPEN`). Harness/tests use `countdown_s = 0`.

**5.3.9 Kick/ban.** `host_kick(peer, ban)`: `KICKED(KICKED_BY_HOST|BANNED)` then graceful disconnect; the slot becomes `OPEN`; a ban adds `(ip, nonce)` to an in-memory set that lives as long as the `NetSession` ("ban for session"). In-game kicks go through `drop_player` (§5.5.10).

**5.3.10 Chat.** `sanitize_text`: remove control characters (< 0x20, 0x7F), collapse runs of whitespace, cut at 200 bytes on a UTF-8 boundary; the UI must render as plain text (BBCode disabled) [XR-16]. Rate: 5 messages per 5 s (token bucket, refill 1/s); excess dropped silently for the sender and scored. Channel 1 (team) is relayed only to slots whose `team_final` equals the sender's (teams 0 are alone). System messages use `from_slot = 255`. Chat is not part of the sim; it is stored as replay `EVENT`s only when `opts.record_chat`.

**5.3.11 Snapshots.** Each accepted mutation increments `revision`; the host sends a full snapshot to every peer at most every 100 ms (coalesced timer) and immediately on join/kick/phase change. `ping_ms` refreshes once per second and only bumps `revision` if it changed by >= 10 ms.

### 5.4 Launch sequence (config broadcast -> load map -> ack -> start tick 0)

| Step | Host | Client | Failure handling |
|---|---|---|---|
| 0 | `host_start()` validates, `phase = COUNTDOWN`, `LAUNCH_COUNTDOWN(3..1)` | shows countdown | abort => `LAUNCH_COUNTDOWN(0)` |
| 1 | `match_seed` = 32 random bits (`Crypto.generate_random_bytes(4)`), `match_id` = 8 random bytes hex; `cfg = NetMatchConfig.from_lobby(...)`; `json = canonical_json(cfg)`; `config_hash = fnv1a32(json_bytes)`; `phase = LOADING`; ENet timeouts -> `TIMEOUTS_LOADING` | | |
| 2 | `LAUNCH_CONFIG` = header + `DEFLATE(json)` to every peer; own `world_builder(cfg)` job starts | inflate (bounded 64 KiB) -> verify `json_len`/`json_fnv` -> `JSON.new().parse` -> `NetMatchConfig.normalize` -> `validate` (versions block == local, roster ids exist, ranges) -> `world_builder(cfg)` job | invalid => `LOAD_FAILED(CONFIG_INVALID)` -> host aborts |
| 3 | every poll: `job.step(4 ms)`; send `LOAD_STATUS` (4 Hz) aggregating all `LOAD_PROGRESS` | `job.step(4 ms)` per poll; `LOAD_PROGRESS` when pct changed (max 4 Hz) | job error => `LOAD_FAILED(LOAD_FAILED)` |
| 4 | when own job done: `ref_map_hash = adapter.map_hash()`, `ref_c0 = adapter.checksum_now()` (tick 0) | when done: send `LOAD_DONE{map_hash, checksum0}`; phase `WAIT_START` | client silent > 120 s => `LAUNCH_ABORT(LOAD_TIMEOUT, pid)`; client disconnect => `LAUNCH_ABORT(HUMAN_LEFT, pid)` |
| 5 | compare every `LOAD_DONE` with the reference: `map_hash` differs => `LAUNCH_ABORT(MAP_MISMATCH, pid, detail = both hashes)`; only `checksum0` differs => `INIT_MISMATCH` | | abort => everybody back to `LOBBY` with the message (`net.err.map_mismatch`), lobby unlocked, both hashes logged at `error` |
| 6 | all match: create `NetTurnHost` (roles from cfg, `_recv_through = D0-1`), `NetAiRunner`, recorder (`config` header), `lockstep.start()`; send `START{config_hash, D0, speed}`; ENet timeouts -> `TIMEOUTS_GAME`; phase `PLAYING` | on `START`: verify `config_hash` == own; create lockstep, recorder; `lockstep.start()`; phase `PLAYING`. Bundles that arrived before `START` (different ENet channel => no ordering guarantee) sit in the pre-start buffer (<= 64) | hash mismatch => local abort, message `net.err.config_mismatch` |

Tick 0 = the world exactly as built. `D0 = fixed_input_delay_turns` if set, else `D_MIN_LOCAL` for `LOCAL`, else `min_input_delay_turns` (default 2). Turns `0 .. D0-1` are *implicit* empty bundles (pre-roll): the host closes them immediately, so first real barrier is turn `D0`.

#### 5.4.1 Session phase machine (`NetSession.Phase`)

| Role | From | Event | To | Side effects |
|---|---|---|---|---|
| host | `IDLE` | `host()` ok | `LOBBY` | listen, start announce, lobby state created |
| host | `LOBBY` | `host_start()` ok | `COUNTDOWN` | lobby locked, `LAUNCH_COUNTDOWN` |
| host | `COUNTDOWN` | countdown reaches 0 | `LOADING` | §5.4 steps 1-3 |
| host | `COUNTDOWN` | unready / leave / `host_cancel_start()` | `LOBBY` | `LAUNCH_COUNTDOWN(0)`, unlock |
| host | `LOADING` | own job done and all `LOAD_DONE` match | `PLAYING` | `START`, recorder, `TIMEOUTS_GAME` |
| host | `LOADING` | mismatch / timeout / human left / load failure | `LOBBY` | `LAUNCH_ABORT`, unlock, timeouts back to lobby values |
| client | `IDLE` | `join()` | `CONNECTING` | connect timer 6 s |
| client | `CONNECTING` | `JOIN_ACCEPT` + `LOBBY_SNAPSHOT` | `LOBBY` | |
| client | `CONNECTING` | `JOIN_REJECT` / timeout | `IDLE` | `join_rejected` / `net_error(TRANSPORT)` |
| client | `LOBBY` | `LAUNCH_COUNTDOWN(n>0)` | `COUNTDOWN` | |
| client | `COUNTDOWN` | `LAUNCH_COUNTDOWN(0)` | `LOBBY` | |
| client | `LOBBY`/`COUNTDOWN` | `LAUNCH_CONFIG` | `LOADING` | validate, start world job, `TIMEOUTS_LOADING` |
| client | `LOADING` | job done, `LOAD_DONE` sent | `WAIT_START` | |
| client | `WAIT_START` | `START` (hash ok) | `PLAYING` | recorder, lockstep start, `TIMEOUTS_GAME` |
| client | `LOADING`/`WAIT_START` | `LAUNCH_ABORT` | `LOBBY` | |
| both | `PLAYING` | executed bundle carries `CK_PAUSE` | `PAUSED` | at boundary N+1 |
| both | `PAUSED` | `RESUME` | `PLAYING` | |
| both | `PLAYING`/`PAUSED` | `is_match_over()` | `ENDED` | final checksum, replay finalised, `match_ended` |
| both | `PLAYING`/`PAUSED` | desync notice / detection | `DESYNCED` | terminal, package written |
| both | `ENDED` | `RETURN_TO_LOBBY` / `host_return_to_lobby()` | `LOBBY` | |
| client | any | `KICKED` / transport lost | `DISCONNECTED` | `kicked` or `net_error`, replay finalised (`ABANDONED` if match not over) |
| LOCAL | `IDLE` | `local()` ok | `LOADING` | §5.9 |
| LOCAL | `LOADING` | job done | `PLAYING` | `START` local |
| any | any | `shutdown()` / `leave()` | `IDLE` | sockets closed, recorder finalised |

Impossible transitions (e.g. `PLAYING -> LOBBY` without `ENDED`) raise `net_error(TRANSPORT)` in debug builds and are ignored in release.

### 5.5 Lockstep protocol

#### 5.5.1 Vocabulary and invariants

| Term | Definition |
|---|---|
| tick / turn | sim tick = 50 ms (`TPS = 20`); **turn N = ticks 2N and 2N+1**. Turn N's commands are submitted before tick 2N is stepped, so `CommandSystem` applies them in tick 2N step 1; tick 2N+1 receives none |
| `E` | the turn about to begin at a boundary (`current_tick / 2`) |
| `D` | input delay in turns. A command entered while turn `E-1` runs is sent at boundary `E` as part of `TURN_INPUT(target = E + D)` and executes at the beginning of turn `E + D` |
| bundle | `TURN_BUNDLE(N)`: everything every player does in turn N, in canonical order (pid ascending; within a pid, submission order) |
| barrier | a peer may begin turn E only if `bundle(E)` is present. The host may close bundle N only if every active human's input for N is present (and the host's own fill-up frontier reaches N) |
| pre-roll | turns `0 .. D0-1` are implicit empty bundles on every peer; nobody sends inputs for them |
| **I1** | each human's `TURN_INPUT` turn numbers are gap-free and strictly +1 (enforced by the fill-up rule) |
| **I2** | bundles are gap-free, strictly +1, identical bytes on every peer |
| **I3** | nothing time-dependent enters the sim: only `(turn, pid, ints)` in bundle order |

Latency of a command issued `tau` ms into turn `E-1`: `(D + 1) * 100 - tau` ms in `(D*100, (D+1)*100]`; D = 2 => 200-300 ms, mean 250 ms (prototype: mean 242 ms, p95 285 ms). D = 1 (local): 100-200 ms (prototype 138 ms).

#### 5.5.2 Pacing and the runner (`NetLockstep.update`)

```
update():
  now = clock.now_us();  elapsed = clamp(now - _last_us, 0, MAX_ELAPSED_US=250000);  _last_us = now
  if _over or _paused: return 0
  _acc_us += elapsed * _speed_pct / 100                       # integer math
  ticks = 0
  while _acc_us >= _tick_us and ticks < MAX_TICKS_PER_POLL(8):
      if _tick % 2 == 0:                                      # turn boundary
          E = _tick / 2
          if _pause_after_turn >= 0 and _pause_after_turn == E - 1:                # armed by CK_PAUSE in bundle E-1 (>= 0: -1 means 'none', and E-1 == -1 at E = 0)
              if _resume_turn >= E: _pause_after_turn = -1                          # the RESUME already arrived (quick toggle): never pause
              else: _paused = true; _paused_at_turn = E; on_pause(true); break
          b = _queue.get(E)
          if b == null: _stall_begin(now);  break             # BARRIER: wait; keep _acc_us (capped below)
          _stall_end(now);  _begin_turn(E, b, now)
      t0 = usec();  _sim.step();  cost = usec() - t0
      _tick += 1;  _acc_us -= _tick_us;  ticks += 1
      if _tick % CHECKSUM_PERIOD_TICKS == 0: on_checksum(_tick, _sim.checksum_at(_tick), _chain)
      if _sim.is_match_over(): _finish(); break
  _acc_us = min(_acc_us, ACC_CAP_TICKS * _tick_us)            # never bank more than 4 ticks: no spiral of death, no fast-forward after a stall
  return ticks
```
* Pacing is per tick (not per turn) so view interpolation sees a steady 20 Hz; only even ticks need the barrier. `tick_alpha() = _acc_us / _tick_us` clamped to [0,1) (view-only float).
* A frame hitch of any length advances at most `MAX_TICKS_PER_POLL = 8` ticks (= 4 turns) per poll, so catching up 1 s of backlog takes 3 frames at 60 FPS; the accumulator cap discards the rest of the debt (game time is *not* wall time after a stall).
* `_begin_turn(E, b, now)` order (this order is part of the contract):
  1. `slack`: `due_us = now - (_acc_us - _tick_us)`; `slack_ms = (due_us - _arrival_us[E]) / 1000` (negative if the bundle arrived after it was due); update the report window.
  2. `on_turn_begin(E, b)` (recorder).
  3. `_chain = fnv1a32(b.core_bytes(), _chain)`.
  4. for each group in bundle order, for each command: `_sim.submit_command(pid, ints)`.
  5. ctrl records in order: `INPUT_DELAY` => `_delay = d`; `SPEED` => `_speed_pct`; `PAUSE` => `_pause_after_turn = E`; `PLAYER_STATUS`/`MATCH_END` => callbacks.
  6. **fill-up** (5.5.3) and `on_boundary(E, target)` (host: AI production + injection frontier).
  7. erase `_queue[E]`.

#### 5.5.3 The fill-up rule (input sending)

At every boundary `E`, after ctrl records were applied: `target = E + _delay`. While `_sent_through < target`: `_sent_through += 1` and send `TURN_INPUT(turn = _sent_through, exec_turn = E, cmds)`, where `cmds` is the next up-to-64 pending commands (bounded by 6144 encoded bytes; FIFO; the rest stay pending for the next boundary) **only for the last packet of the loop (`_sent_through == target`)**; gap packets are empty. Consequences:

| Boundary | D (after ctrl) | target | `_sent_through` before | packets sent |
|---|---|---|---|---|
| E=10 | 2 | 12 | 11 | [12 + cmds] |
| E=11 | 2 | 13 | 12 | [13 + cmds] |
| E=12 (bundle carries `INPUT_DELAY=3`) | 3 | 15 | 13 | [14 empty, 15 + cmds] — delay **increase** inserts gap turns |
| E=13 | 3 | 16 | 15 | [16 + cmds] |
| E=14 (bundle carries `INPUT_DELAY=2`) | 2 | 16 | 16 | [] — delay **decrease** skips one boundary; pending commands wait for E=15 |
| E=15 | 2 | 17 | 16 | [17 + cmds] |

Every human therefore sends **exactly one packet per turn on average and never leaves a gap** (I1), which is what makes the host's contiguity test valid. Empty packets are the heartbeat (10 bytes: `20 <turn:4> <exec:4> 00`). The host's own local human and its AI use the same rule against `NetTurnHost` directly.

Start: `_sent_through = D0 - 1`, so the first boundary (E = 0) sends turn `D0`. A dedicated host (no local human) runs the same loop with `local_pid = -1`: it sends nothing, but `on_boundary(E, target)` still fires so AI production and the injection frontier advance. A `LOCAL` session with zero humans (AI-vs-AI soak, self-test) is valid for the same reason.

#### 5.5.4 Host barrier and bundle assembly (`NetTurnHost.close_ready`)

```
close_ready():   # bounded: at most 16 bundles per call
  while out.size() < 16:
    N = _next_close
    if _paused_from >= 0 and N >= _paused_from: break
    blocked = [pid for pid in 0..7 if _role[pid] == PR_HUMAN and _recv_through[pid] < N]
    if blocked: _note_blocked(blocked, N); break                       # stall bookkeeping (5.5.7)
    if _needs_inject and _inject_through < N: break                    # host's own fill-up (local human + AI) not there yet
    for pid in 0..7 ascending:
        cmds = []
        if _resign_queue.has(pid): cmds.append([T_RESIGN, reason]); _resign_queue.erase(pid)     # first in the group
        if _role[pid] == PR_HUMAN: cmds += _inputs[pid].pop(N, [])
        elif _role[pid] == PR_AI:  cmds += ai_cmds_for(N, pid)
        cmds = cmds[0 : MAX_CMDS_PER_TURN]                             # overflow dropped + counted (dropped_cmds)
        if cmds: groups.append(pid, cmds)
    ctrl = _ctrl_queue.pop_front(up to 8)
    out.append(NetBundle.build(N, ...));  _next_close = N + 1
    for ctrl PAUSE in ctrl: _paused_from = N + 1
  return out
```
`_needs_inject = (host has a local human) or (ai_count > 0)`. A dedicated host without AIs skips the frontier test.

**Host authority is order-only.** Pid stamping (from the connection, never from the payload) + ascending-pid group order + the host's choice of *which turn* a late-but-legal input lands in are the only decisions the host makes. It never inspects `ints[1:]`, never simulates, never rejects on game semantics; every peer's `CommandSystem` deterministically ignores illegal commands. Injected content is limited to: AI commands (§5.6), `T_RESIGN` on behalf of departed players (§5.5.10) and ctrl records.

#### 5.5.5 Late, duplicate, out-of-order handling

ENet-reliable never duplicates or reorders within a channel, but the protocol is *defensive* (transport-agnostic, fault-injection tested, malicious-peer safe):

| Situation | Host `on_input` (per human) | Client `push_bundle` |
|---|---|---|
| `turn <= recv_through` / `turn < next_push` | `DUPLICATE`: ignore, `dup_in++`, score +1 | `DUPLICATE`: ignore, `dup_in++` |
| `turn < next_close` but > `recv_through` | `LATE` (only possible after the player was dropped/taken over): ignore | — |
| `turn == recv_through + 1` / `next_push` | accept; then drain buffered successors while contiguous | accept; drain `_ooo` |
| within `REORDER_WINDOW` (32) ahead | store (`BUFFERED`); a second copy => `DUPLICATE`; barrier still requires contiguity | store in `_ooo` |
| beyond window, or `turn > next_close + INPUT_LOOKAHEAD` | `TOO_FAR`: drop, score +3 | `TOO_FAR`: host protocol error => `net_error` + leave |
| encoded size > 6200 B, > 64 commands, command size 0 or > 1024, `ints[0]` outside 0..255 | `TOO_BIG`/malformed: drop the whole packet, score +3 (the fill-up rule means the client will not resend; the host treats the turn as **empty** for that player and keeps I1 by advancing `recv_through`) | bundle hash mismatch, non-ascending pids, group > 64 cmds => `MALFORMED`: protocol error |
| sender is not a `PR_HUMAN` (dropped, taken over by AI, spectator) | `WRONG_PLAYER`: ignored **without** a violation score (legitimate in-flight packets right after a drop); a spectator or unseated peer sending inputs is scored +1 | — |

Note on `TOO_BIG`: dropping a malformed input *without* advancing `recv_through` would stall the whole match; therefore, whenever the `turn` field itself was decodable, the host substitutes an empty input for that turn and scores the sender (3 points; 4 such packets within 20 s => kick). If even the header is undecodable (turn unknown) the packet is dropped (+3) and the resulting gap stalls only that sender's own stream: the host prompts/auto-drops it like any unresponsive human (§5.5.7).

#### 5.5.6 Adaptive input delay (`NetDelayPolicy`)

Inputs: per remote human `c`, from each `PONG` (every 500 ms): `rtt` (host clock, includes the client's frame delay), `slack_min_ms`, `stall_ms` (sum of stall episodes <= 1000 ms), `hitch`. `turn_ms = 100 * 100 / speed_pct` (integer; 100 ms at 100 %).

```
feed_pong(c, now_ms, rtt_ms, slack_min, stall_ms, episodes, hitch):
    if hitch or rtt_ms > HITCH_MS(1000): c.quarantine_until = now_ms + QUARANTINE_MS(3000); return
    if now_ms < c.quarantine_until: return                                  # freeze/suspend/debugger must not change everyone's latency
    first sample: rtt = s, jit = 0; else: jit += (|s - rtt| - jit) / 8;  rtt += (s - rtt) / 8          # EWMA alpha 1/8 (floats; host-only)
    c.ring.push([now_ms, slack_min, stall_ms]);  keep the newest 20 (10 s)
evaluate(now_ms, D):                                                         # every DELAY_EVAL_MS = 500
    need_ms  = max_c( c.rtt + 2 * c.jit + DELAY_FRAME_MARGIN_MS(34) )        # +2*jitter ~ 95th percentile; +34 = two 60 Hz frames
    d_target = clamp( ceil(need_ms / turn_ms), D_min, D_max )
    stall10  = max_c( sum(stall_ms of ring samples in the last 10 s) )
    stall8   = max_c( sum(... last 8 s) );   min_slack8 = min_c( min(slack_min of samples in the last 8 s) )
    if   d_target > D and now - last_change >= 1000:                                   new = d_target        # RTT/jitter says we need more
    elif stall10 >= DELAY_RAISE_STALL_MS(400) and D < D_max and now - last_change >= 2000:   new = D + 1    # observed stalls
    elif d_target < D and stall8 == 0 and min_slack8 >= turn_ms + DELAY_LOWER_MARGIN_MS(60)
         and now - last_change >= DELAY_LOWER_HOLD_MS(8000):                           new = D - 1           # earned headroom
    else new = D
    if new != D: last_change = now; clear ALL rings (prevents wind-up: old stalls must not trigger a second raise); queue CK_INPUT_DELAY(new)
```
`fixed_input_delay_turns > 0` bypasses the policy entirely. `D_min = D_MIN_LAN(2)` (`min_input_delay_turns`), `D_MIN_LOCAL(1)` for `LOCAL`. Decisions travel only inside bundles (I2), so every peer applies a change at the same turn.

Reference outcomes (prototype, host + 3 clients, 120 s virtual time, ENet-like RTO = 2*lat + 4*jit + 33 ms; **all runs 0 checksum/chain mismatches**):

| Profile (one-way lat +- jit, loss) | measured RTT/jit (ms) | final D | command latency avg / p95 (ms) | client stalls (3 clients) | game speed vs wall |
|---|---|---|---|---|---|
| LAN 0.5+-0.3 | 19 / 4 | 2 | 242 / 285 | 0 | 100 % |
| Wi-Fi 10+-8, 1 % | 48 / 17 | 2 | 242 / 286 | 1 stall, 16 ms | 100 % |
| Bad Wi-Fi 30+-25, 3 % | 94 / 31 | 4 (3 at 1 s, 4 at 3 s) | 439 / 488 | 50 stalls, 3.2 s total | 100 % |
| Internet 75+-15, 1 % | 170 / 16 | 5 (3, 4, 5 at 1/7/15 s) | 522 / 586 | 35 stalls, 2.2 s | 100 % |
| Awful 150+-60, 4 % | 409 / 130 | 8 (cap) | 959 / 1374 | 589 stalls | ~87 % |
| Wired LAN with `min_input_delay_turns = 1` (advanced) | 18 / 4 | 1 | 138 / 185 | 0 | 100 % |
| Wi-Fi + clock drift +-150 ppm, 300 s | 42 / 11 | 2 | 242 / 285 | 7 stalls, 199 ms | 100 % |
| LAN + 3 s freeze of one client at 20 s | 17 / 1 | 2 (unchanged: quarantine) | 309 / 296 (max 3072 = the frozen turn) | others wait ~2.8 s | resumes |

#### 5.5.7 Stall handling ("Waiting for player X")

* **Client stall episode**: begins at the boundary where `_acc_us >= _tick_us`, `_tick` even and `_queue[E]` is missing; `due_us` is its start; it ends when the turn begins. Episodes > `HITCH_MS` set `_rep_hitch` and are *not* added to `_rep_stall_ms`; shorter ones are (and `_rep_episodes++`). The client reports these in every `PONG` and resets them. `on_stall_changed(true)` fires once the episode reaches `STALL_UI_MS = 400` (no flicker for sub-frame jitter), `(false)` when it ends.
* **Host blocked set**: `close_ready` records for each pid blocking turn N the time the block started (`_block_since_us`). Every 250 ms, if any pid has been blocking >= 400 ms, the host broadcasts `STALL_INFO(turn N, [(pid, reason, wait_ms)])`; when the block clears it sends one `n = 0` message. Reason: `DISCONNECTED` (transport state gone), `SLOW_CPU` (peer alive, RTT normal, its last reported `exec_turn` is >= 3 turns behind `N - D`), else `NETWORK`. The overlay text is "Waiting for {names}... {seconds}" (`net.stall.waiting`); if no `STALL_INFO` arrives while stalled >= 1.5 s the client shows "Waiting for host..." (host itself is the slow party or the link died).
* **Host prompt**: `stall_prompt(pids)` when a pid has blocked >= `STALL_PROMPT_MS` (8 s) or is `DISCONNECTED`. Options: **Wait** (suppresses that pid's prompt for 30 s), **Drop (player resigns)**, **Replace with AI** (`host_resolve_stall`). Automatic: if `auto_drop_ms > 0` (default 60 000) a *connected but unresponsive* human is dropped with the `on_disconnect` policy after that time; a `DISCONNECTED` human after `min(auto_drop_ms, DISCONNECT_ACT_MS = 5 s)`. `auto_drop_ms == 0` means only manual.
* The timeline of a dead peer: freeze at t=0; overlay at 0.4 s; ENet marks the peer disconnected at ~6.5 s (measured) => reason `DISCONNECTED`, immediate prompt, auto action at ~11.5 s (or manual); a live-but-slow peer reaches the prompt at 8 s and auto-drop at 60 s.

#### 5.5.8 Pause and unpause

* `PAUSE_REQUEST(1)` from human `p` is accepted iff `pause_policy` allows (`HOST_ONLY`: `p` is the host's pid; `DISABLED`: never; `ANY_PLAYER`: any), not already paused, and the pauser has `< MAX_PAUSES_PER_PLAYER (3)` used (the host is unlimited). Accepted => `CK_PAUSE(p)` is queued into the **next bundle to close**, N. Everybody executes N (both ticks) and then stops at boundary `N+1` (`_pause_after_turn = N`); the host sets `_paused_from = N + 1`. The order is fixed by the bundle stream => all peers pause at the same sim tick.
* While paused: no boundaries => no `TURN_INPUT`; `PING/PONG`, chat, `STALL_INFO` continue; local commands keep queuing (sent after resume). ENet timeouts keep running (the pause must not hide a dead peer).
* Resume: `PAUSE_REQUEST(0)` by the pauser or the host, or automatic after `MAX_PAUSE_MS` (120 s). **`resume_pause` first cancels a `CK_PAUSE` that is still waiting in `_ctrl_queue`** (the pause never happens); otherwise, if `_paused_from >= 0`, the host sends `RESUME(resume_turn = _paused_from, by_pid)` and clears `_paused_from`; otherwise (nothing pending, nothing active) `PauseError.NOT_ALLOWED`; a second `PAUSE_REQUEST(1)` while a pause is pending or active returns `PauseError.ALREADY`. The host applies its own `RESUME` locally with `lockstep.resume(R)` at the moment it sends it. Peers keep a **watermark** `_resume_turn = max(_resume_turn, R)`: a pause armed for boundary `E` is skipped if `_resume_turn >= E` (RESUME overtook the execution of the pause bundle on a slow peer), and a paused peer resumes as soon as `_resume_turn >= _paused_at_turn`. Without the cancel rule and the watermark a fast pause/resume toggle deadlocks the match (found and fixed in the design prototype). The next bundle (`N+1`) closes immediately after a resume because every input through `N + D` was already sent before the pause.
* Pause is not recorded in replays (it does not change simulation).

#### 5.5.9 Game speed

Host-controlled: `host_set_speed(pct)` with `pct` in `SPEED_PCT` queues `CK_SPEED(pct)`; each peer applies it when it executes that bundle (`_speed_pct`), so all displays change together. It only scales the pacing accumulator (`acc += elapsed * pct / 100`) and `turn_ms` in the delay policy; it never reaches the sim. Lobby default 100 % ("Medium", bible preset). Headless soak runs set `opts.speed_pct_override = 0` (*unpaced*): `NetLockstep.set_speed_pct(0)`, and `update(max_ticks)` runs up to `opts.max_ticks_per_poll` ticks per call, ignoring the wall-clock accumulator, with the barrier still enforced. `MatchConfig.net.speed_pct` itself always stays one of `SPEED_PCT`.

#### 5.5.10 Surrender, leave, disconnect, drop, AI takeover

| Event | How detected | Sim effect (via commands only) | Barrier | `PlayerNetStatus` |
|---|---|---|---|---|
| **Surrender** | UI -> `submit_command([T_RESIGN, SURRENDER])` (normal input) | `CommandSystem` eliminates the player at the executing turn | player stays in the barrier and keeps sending heartbeats (spectates their own match) until they leave | `RESIGNED` (host sets when it sees the command) |
| **Clean leave** | `LEAVE` | host injects `[T_RESIGN, DISCONNECT]` first in that pid's group of the next closed turn (or takeover if `on_disconnect == AI`) | removed from the barrier for turns >= the injection turn | `LEFT` |
| **Transport drop** | `DISCONNECTED` event | none yet; `STALL_INFO(DISCONNECTED)` and prompt; after `min(auto_drop_ms, 5 s)` or manual: policy `RESIGN` => `[T_RESIGN, DISCONNECT]`; `AI` => takeover | as above | `DISCONNECTED` -> `DROPPED`/`AI_TAKEOVER` |
| **Host drops / kicks** | UI or auto | `[T_RESIGN, KICKED|TIMEOUT]` or takeover; the peer (if alive) gets `KICKED` | as above | `DROPPED` / `AI_TAKEOVER` |
| **AI takeover** | `drop_player(pid, STALL_DROP_AI)` | none by itself: from the next host boundary `NetAiRunner` produces that pid's commands; buffered human inputs for turns >= N are discarded; turns N..N+D-1 carry no commands for the pid | pid leaves the barrier (`PR_AI`) | `AI_TAKEOVER` (level = `NetProtocol.TAKEOVER_AI_LEVEL = 1`, style 0) |
| **Host quits** | clients' `DISCONNECTED` | match ends; clients finalise their replay, show `net.err.host_left` | — | — |
| **Spectator leaves/lags** | `LEAVE`/timeout | none | never in the barrier | — |

Every status change is also emitted as `CK_PLAYER_STATUS(pid, status, aux)` in **the same bundle** that carries its `T_RESIGN` injection (both are queued in the same call), so all peers and the replay agree.

#### 5.5.11 End of match

Any `step()` that makes `is_match_over()` true stops the lockstep on that peer at the same tick (determinism). It emits a final `on_checksum(end_tick, checksum_now(), chain)` (any tick, not only multiples of 20). The host broadcasts `MATCH_END{final_tick, final_checksum, reason, winner_team}` after seeing its own end; a client whose `(tick, checksum)` differs raises a `SIM` desync at `final_tick`. Bundles arriving afterwards are ignored. The recorder writes `END`; phase `ENDED`; the host may `host_return_to_lobby()` (`RETURN_TO_LOBBY`): all slots keep their settings, `ready` reset.

#### 5.5.12 Worked timeline (LAN, D = 2, 100 ms turns)

`t = 10.000 s`: all peers begin turn 100 (tick 200). Player B enters an attack order at `10.030 s`. Boundary 101 at `10.100 s`: B's fill-up sends `TURN_INPUT(turn 103, exec 101, [[ATTACK, ...]])` (15+ bytes). Host receives at `~10.102 s`; A's and C's inputs for turn 103 (sent at their own boundary 101) are already in => bundle 103 closes at once, is sent (`~10.103 s`) and arrives at B, A, C at `~10.105 s`. Boundary 103 is at `10.300 s`: all execute the attack in tick 206. **Latency 270 ms, slack 195 ms** (allowed RTT before a stall: ~190 ms). If B's Wi-Fi delays that bundle by 250 ms, boundary 103 stalls B for 55 ms (`slack -55`), the policy sees `stall_ms 55` — below the 400 ms raise threshold — nothing changes; repeated stalls summing to 400 ms within 10 s raise `D` to 3.

### 5.6 AI runner hookup (host only)

`net/` must not depend on `ai/` (ARCHITECTURE §5), so the AI is injected: `opts.ai_factory(pid, level, style, rng_seed) -> Callable thinker`, `thinker.call(world: RefCounted, out: Array) -> void` appends `PackedInt32Array` commands to `out` (ordinary commands; the AI reads the world only through the sim's public query API, ARCHITECTURE §1.4). `app/` builds the factory around `AiBrain` [XR-13].

```
# host, inside NetLockstep.on_boundary(E, target)          (E = turn about to begin, target = E + D)
groups = []
ai_runner.produce(E, target, sim, groups)      # for pid in ai_pids ascending:
                                               #   skip unless (E + pid) % think_period_turns == 0       # 5 turns = 500 ms, phase-staggered by pid
                                               #   skip if not sim.is_player_active(pid)                 # defeated AIs stop thinking
                                               #   cmds = []; thinker.call(sim.world(), cmds)             # reads state at tick 2E (before this turn's commands run)
                                               #   sanitise: each cmd size 1..1024 and cmd[0] in 0..255 else drop; keep <= 64 cmds and <= 6144 encoded bytes
for g in groups: turn_host.add_ai_commands(target, g.pid, g.cmds)
turn_host.note_injection_through(target)        # the host's own fill-up frontier advances (local human + AI together)
```
* AI commands reach every peer **only** through the bundle of turn `target` (group id = the AI's pid) — identical on all machines and recorded in replays, so playback never needs the AI.
* Determinism of the *match* never depends on the AI (I3). For headless AI-vs-AI soak/replay reproducibility the thinker's private RNG is seeded with `mix32(match_seed ^ ((pid+1) * 0x9E3779B9))` (never the sim RNG, whose state is in the checksum). Same seed + same AI code => same replay; verified by `NetSelfTest` in AI mode.
* **Cadence.** Each AI thinks when `(E + pid) % period(pid) == 0`, with `period(pid) = opts.ai_think_period(level)` (default 5 turns; the AI domain asks for `[5, 3, 2, 1]` for Easy..Brutal). A thinker must accept any period >= 1 turn (its `dt` grows when it was skipped).
* **CPU governor (paced sessions only).** `produce()` measures each think with `Time.get_ticks_usec()`; per boundary the total is capped at `AI_BOUNDARY_BUDGET_US = 8000`: once exceeded, the remaining due thinkers are marked *overdue* and run first (pid order) at the next boundary. A thinker that exceeds 12 ms twice in a row has its period doubled (max 20 turns) and a warning is logged. All of this is outside the sim, so it cannot affect determinism of the match. **Unpaced/headless runs (`speed_pct_override = 0`) disable the governor** (every due thinker runs on schedule), which makes AI-vs-AI matches reproducible per seed. `stats().ai_us` exposes the last think time per pid.
* AI takeover for a dropped human uses the same runner (`add_ai(pid, TAKEOVER_AI_LEVEL, 0)`). The AI is created at the boundary after the drop turn N; turns N..N+D-1 carry nothing for that pid.

### 5.7 Desync detection and diagnostics (`NetDesync`)

**Cadence and data.** Every 20 ticks (after `step()` of tick `T`, `T % 20 == 0`) each peer takes `(checksum_at(T), input_chain)`; parts are kept in a ring of 64 snapshots. Clients send `CHECKSUM_REPORT` (13 bytes, ch0) to the host; the host records its own snapshot and compares each report on arrival (`pending` holds reports for ticks the host has not reached yet; reports older than the ring are ignored). Spectators report too but never halt the match (they raise a per-spectator warning).

**Classification** (`NetDesync.classify`): `chain` differs => `INPUT_CHAIN` (the peers did not execute identical command streams: relay/serialisation/injection bug in net); chain equal but checksum differs => `SIM` (nondeterministic simulation: DR violation, platform difference, uninitialised state); both differ => `BOTH` (report chain first). The odd-one-out is found by grouping reports by `(checksum, chain)`; with two players both are listed as "differs".

**On mismatch** (host): phase -> `DESYNCED` and the host's lockstep stops. It broadcasts `DESYNC_NOTICE(tick, kind, [(pid, checksum, chain)])` and `PARTS_REQUEST(tick, host_parts)` (its own sub-checksums for that tick travel in the request). Every peer stops its lockstep on receipt of either message, computes `parts_diff` locally (names from `checksum_part_names()` whose value differs from `host_parts`, using its own ring), writes its package immediately and raises `desync_detected`. Clients also answer `PARTS_REPORT(tick, parts)` so the host can list, per diverging peer, which subsystems differ; the host waits up to 2 s for those reports and then finalises its package (the host package is the authoritative multi-peer view). `DESYNC` is terminal: there is no "continue anyway".

**Log line** (level `error`, greppable, one per peer): 
`[net] DESYNC match=<id8> tick=4200 kind=SIM last_good_tick=4180 local(pid=1)=1A2B3C4D chain=A6C168F3 remote(pid=0)=99887766 chain=A6C168F3 parts_diff=[economy,production] platform=macOS/arm64 engine=4.7.2-stable`. At `debug`: `[net] chk t=<tick> sum=<hex> chain=<hex>` per snapshot.

**Package** (`user://desync/`, prefix `desync_<match8>_p<pid>_t<tick>`): `.json` (§7.5), `.state.txt` (`adapter.dump_state()`, deterministic text), `.mfreplay` (copy of the flushed recording file: all bundles + CHECK/PARTS records so far), `.checks.csv` (`tick,checksum,chain,part0,part1,...`). Only the newest 10 packages are kept (older files with that prefix and extension set are deleted; nothing else is ever deleted). Offline localisation: `tools/gd run game/tests/net/desync_diff.gd -- a.mfreplay b.mfreplay --tick=4200` re-simulates both replays to the tick (each is faithful to its origin machine because same-machine replay is deterministic) and prints the first differing `dump_state()` lines.

**UI hook.** `NetSession.desync_detected(report)`; text keys `net.desync.title/body`: "The game states of the players diverged at {mm:ss} (tick {tick}). The match cannot continue. Diagnostic files were saved to {path}." Buttons: Show folder, Save replay, Leave. The world stays readable so the view can freeze on the last frame.

**Determinism self-test (`NetSelfTest.run_double`).** (A) run `ticks` through a `LOCAL` session with the script (and AI if given), recording to memory; (B) build a second world and drive it with A's replay via `NetReplayPlayer` (unpaced); compare every 20-tick `(checksum, chain)`, the final checksum and `hash(dump_state())`. With `--twice` also run A a second time and compare A1 vs A2 (needs a deterministic AI). Any mismatch => `first_mismatch_tick` and the `parts` names. CLI: `tools/gd run game/tests/net/selftest_main.gd -- --config=cfg.json --ticks=6000 [--script=s.json] [--ai] [--twice]` prints `SELFTEST OK ticks=6000 chain=0x... final=0x...` (or `FAIL tick=...`), exit code 0/1. Cross-process/cross-platform: run the CLI in two processes / the Linux container and diff the printed chains.

### 5.8 Replays (`NetReplayRecorder`, `NetReplayData`, `NetReplayPlayer`, `NetReplay`)

**Recording.** Every peer (host, client, spectator, LOCAL) starts a recorder at `START`: `open_file(NetReplay.begin_recording_path(), cfg, meta)` writes header + JSON (the exact launch JSON, so `config_hash` is reproducible). `on_turn_begin` => `record_turn(bundle)`: a bundle without commands writes nothing (the next TURNS record's `gap` accounts for it); `on_checksum` => `record_check` (+ `record_parts` every 200 ticks, i.e. every 10 CHECKs); status changes => `EVENT`; chat => `EVENT` if enabled; `flush()` after every CHECK (<= 1 s of data lost on crash). `finish(result)` at match end/leave writes END + trailer. Recording never blocks: a failed write disables the recorder and raises `net_error(REPLAY_WRITE)` once.

**Autosave of the last match.** Recording goes to `user://replays/_recording.mfreplay.tmp`. On finish, `finalize_autosave(tmp, keep)` rotates: delete `autosave_<keep>`, rename `autosave_i` -> `autosave_{i+1}` for `i = keep-1 .. 1`, rename tmp -> `autosave_1.mfreplay` (delete-then-rename because Windows refuses to rename onto an existing file). `recover_orphans()` at boot renames a leftover tmp to `crash_<unix>.mfreplay` (truncated but playable). Manual save = `save_copy(autosave_1, name)`; names go through `String.validate_filename()` + `[A-Za-z0-9 _.-]`, <= 48 chars, collision => `_2`, `_3`.

**Loading.** `NetReplayData.load_file`: header magic/version/`json_len <= 1 MiB`/`json_fnv`; JSON -> `NetMatchConfig.normalize`; records parsed sequentially with `NetReader`; an incomplete/oversized (> 1 MiB) record or unknown structure ends parsing with `truncated = true` (everything before it is kept); unknown record types are skipped by length; a second END or records after END are ignored. Metadata listing reads only header + trailer (`EOF-8`), not the stream.

**Playback (`NetReplayPlayer.poll`).** Version gate (hard/soft): `versions.sim` and `versions.data_ids` (the id-table hash) must equal local, else `setup` returns `ERR_INVALID_DATA` with `error_text = net.err.replay_version`; if only `versions.data_hash` differs (same ids, changed balance/resolver) playback is allowed with `warning = net.warn.replay_balance` ("balance changed since recording; playback may diverge") and the verification banner is labelled advisory. `NetReplayPlayer.strict = true` (tests, `verify_file`, D3) turns every difference into a refusal; `allow_version_mismatch` is the developer override of all of it. The world is built through the same `NetWorldJob`. Per tick: at even ticks look up the next TURNS body (`turns[_ti] == E`), submit its commands, chain-update with the reconstructed `core_bytes` (empty turns included), `step()`; after each multiple-of-20 tick compare with the next CHECK: on the first mismatch emit `verify_failed(tick, expected, actual)` once and continue (viewers see "Replay diverged at mm:ss: recorded on a different build?"); `verified_through_tick()` advances otherwise. Speeds `0.25, 0.5, 1, 2, 4, 8` scale the accumulator (ticks/poll cap = `8 * speed`), `MAX` runs sliced by `budget_us` (default 6 ms) so the UI stays responsive. Pause freezes the accumulator. **Seek**: forward = fast-forward (sliced, events discarded via `clear_events()` each step); backward = rebuild the world (sliced job) and re-simulate from tick 0 to the target while verifying every CHECK (these CHECK records are the "keyframes": they prove the rebuilt state equals the recorded one); `progress()` and `is_seeking()` drive a progress bar. A 30-minute game seeks to its end in roughly `ticks * mean_tick_cost` (sim budget: 36 000 ticks x ~1.5 ms ~ 54 s worst case at MAX, faster in headless soak).

**Replay used by tests.** `game/tests/fixtures/net/replays/*.mfreplay` are golden recordings (2p vs AI, 4p FFA, one with pause/drop events). `NetReplayPlayer.verify_file(path, builder)` runs them headless on macOS, in the Linux container and on Windows CI; any mismatch fails with the first bad tick and parts diff — this *is* the cross-platform determinism test. `make_replay_fixture.gd` regenerates them (only on an intentional sim version bump; the commit must bump `SimConfig.SIM_VERSION`).

### 5.9 Single-player path (skirmish == multiplayer code path)

`NetSession.local(opts, lobby_state)` runs `Role.LOCAL`: **no `NetTransport` object exists** (no sockets, no ENet), everything else is the multiplayer pipeline:

1. `NetMatchConfig.from_lobby` -> `canonical_json` -> `parse` -> `normalize` -> `validate` (the same validation a client would apply to a remote config).
2. `world_builder(cfg)` job (time-sliced across polls; `LOADING` phase and `load_progress` signal work identically).
3. Reference `map_hash/checksum0` computed and "acknowledged" by the same code (self-compare is trivially equal); `START` is a local call.
4. `NetTurnHost` with the local human as `PR_HUMAN` and `NetAiRunner` for the AI slots; `NetLockstep.on_send_input` calls `NetTurnHost.on_input` directly (exactly what the host does for its own player in multiplayer); bundles are pushed straight into `NetLockstep.push_bundle`.
5. `D = D_MIN_LOCAL = 1`, delay policy disabled (no remote peers), speed selectable, pause always allowed, recorder + autosave on, desync self-check limited to `input_chain` vs replay (tests).

Therefore a bug in command ordering, fill-up, bundle assembly, AI injection, recording or replay shows up in single-player too, and `NetSelfTest` can prove local == replay. Skirmish setup reuses `NetLobbyState` (`create_skirmish`) so options/validation are shared with LAN.

### 5.10 Spectators (optional feature; Phase 3)

Join with `flags.bit0`: appended to `spectators`, never seated, not in the barrier (`PR_NONE`), receives bundles and `MATCH_END`, sends `PONG`/`CHECKSUM_REPORT` only. Joining before launch takes part in the normal launch (builds the world, sends `LOAD_DONE`). **Late join** (`IN_GAME`, `allow_spectators`): after `JOIN_ACCEPT` the host sends `LAUNCH_CONFIG`; the spectator builds the world and sends `LOAD_DONE`, which must equal the host's stored tick-0 reference; then `CATCHUP_REQUEST(0)`; the host streams `CATCHUP_CHUNK` (DEFLATE of replay TURNS records, <= 60 KB per chunk, <= 4 chunks per poll, channel 2) while the spectator runs its lockstep *unpaced* on those turns; `CATCHUP_DONE(next_live_turn)` switches to live bundles (contiguity kept). Cost: 1 h = 36 000 turns ~ 1 MB raw / ~200 KB deflated, dominated by sim re-simulation time (~20x real time => ~3 min). A lagging spectator never stalls the match (it is not in the barrier); the host disconnects it with `KickReason.TIMEOUT` when its reported `exec_turn` trails `next_close` by more than 1200 turns (2 minutes), and every client caps its `_queue` at 4096 bundles (beyond that it treats the host as faulty). The same mechanism is the documented upgrade path for a future *rejoin* of a dropped human (not in v1 because the host would also have to re-admit the pid into the barrier deterministically).

### 5.11 Fault injection and the two-process harness

**`NetTransportFault` model** (decorator over any `NetTransport`, driven by a `NetClock`, seeded `RandomNumberGenerator` so runs are reproducible):
```
send(peer, ch, data):
  lat = max(0.1, latency_ms + uniform(-jitter_ms, +jitter_ms));  if endpoint frozen: hold until the freeze ends
  ordered (ENet-reliable model):  k = 0; while rand()*100 < loss_pct and k < 8: k += 1
                                  deliver_at = max(now + lat + k * rto, last_deliver[peer, ch] + 1 us)      # head-of-line blocking
  unordered (raw UDP model):      if rand()*100 < loss_pct: drop
                                  deliver_at = now + lat + (rand()*100 < reorder_pct ? uniform(0, 2*lat + jitter) : 0)
                                  if rand()*100 < dup_pct: also deliver a copy at deliver_at + uniform(0, lat + jitter)
  bandwidth_kbps > 0: add size*8/kbps ms, FIFO per link
poll(): deliver everything with deliver_at <= clock.now_us(), in (deliver_at, sequence) order
```
Presets and expected outcomes are in §5.5.6. `raw_chaos` (unordered, dup 3 %, reorder 10 %, no loss) must still produce identical checksum/chain on every peer — it proves the dup/ooo handling of §5.5.5. `freeze_for_ms(3000)` reproduces the "laptop lid closed" case.

**Harness (`game/tests/net/net_harness.gd`, run via `tools/gd run … -- args`).**
`--role=host|client|local|selftest --port=27615 --connect=127.0.0.1:27615 --players=N --ai=K --sim=fake|real --turns=N --script=file.json --fault=<preset> --fixed-delay=D --speed=0 --seed=S --out=file.json --record=path --countdown=0`. Host: creates the session, fills the lobby (`--players` humans incl. itself, `--ai` AI slots), waits for the clients (10 s), `host_start()`, runs until turn `N`, prints one line `NETTEST role=host pid=0 ticks=3000 chain=0x8FA5BAAE final=0xD8534782 checks=150 desync=0 stalls=0 delay=2 bytes_out=...` and writes the JSON; client: `join`, roster/ready, run. Scripted commands (§7.6) are injected when the local `exec_turn == cmd.turn - D - 1` (with `--fixed-delay` the resulting bundles are byte-identical run to run, so the final checksum is a golden). `tools/py/net_two_process.py` launches the host and N clients (`127.0.0.1`, unique ports), waits, parses the `NETTEST` lines and asserts equal `chain/final/checks`, `desync=0`, exit codes 0 [XR-18]. Under `--sim=fake` it runs before the sim exists.

### 5.12 Security and robustness (LAN threat model: hostile or buggy peers, no internet exposure)

| Threat | Mitigation |
|---|---|
| Malformed/truncated/garbage packets | Every decoder is total (`NetReader`, sticky `ok`, leftover bytes => reject); returns `null`/`{}`; sender scored +3; fuzz-tested (20 000 buffers/message type, zero engine errors) |
| Oversize messages | `data.size()` checked against the §4.3 table **before** decoding; ints/command 1024, commands/turn 64, bundle 52 000 B, config 64 KiB inflated |
| Flooding | Token buckets per message class (§4.3), 4 connections/IP, 8 unauthenticated peers, 5 s handshake timeout, `disconnect_now` on wrong connect magic; violation score (weights: malformed 3, oversize 3, too-far 3, wrong-phase 1, rate 1, duplicate 1, unknown type 2; decay 1 per 5 s) kicks at 12 with `KickReason.PROTOCOL_VIOLATION` |
| Wrong role/phase messages | The §4.3 matrix is enforced in `NetSession` before dispatch (e.g., a client sending `TURN_BUNDLE`, or `TURN_INPUT` during `LOBBY`, is dropped + scored) |
| pid spoofing | There is no pid in `TURN_INPUT`; the host stamps it from the connection |
| Version/data drift | Gate on proto/sim/data hash at join, re-checked in the launch config (`versions`) and by `config_hash` in `START`; map and tick-0 checksum compared in `LOAD_DONE` |
| Code/data injection | Forbidden on remote data: `bytes_to_var`, `str_to_var`, `PacketPeer.get_var`, `decode_var`, `JSON.to_native`, `Expression`, `load()`/`ResourceLoader` with remote-derived paths, `OS.execute`. Roster ids are looked up in the injected list (never used as paths); names/chat are inert strings (control characters stripped; UI renders them without BBCode) |
| JSON abuse | Only the launch config is JSON: <= 64 KiB, parsed by `JSON.new().parse()`, then **rebuilt** by `NetMatchConfig.normalize` from a whitelist of keys with integer coercion (finite, integral, in range; floats rejected); depth is bounded by the fixed schema |
| Zip bomb | `decompress_dynamic(MAX_CONFIG_JSON, DEFLATE)` (bounded; measured 100 us for an 8 MB bomb) |
| Memory growth | Bounded windows (32 turns), `_pending` 256, ban set 256, discovery table 64, no unbounded logs (in-memory ring of 400 lines) |
| Reflection/amplification | Discovery is announce-only: no query/response, so a spoofed datagram cannot trigger replies |
| Password | `sha256("<session_id>:<password>")` proof: keeps casual joiners out; it is NOT secure against a sniffer (plain UDP) |
| Cheating | Maphack/omniscient fog is inherent to lockstep; LAN trust model. Command-ownership cheats are neutralised because every peer's `CommandSystem` rejects them identically; debug/cheat commands must be compiled out or gated off in multiplayer [XR-10] |
| Filesystem | Replay/desync file names are generated locally and sanitised; deletions are restricted to `user://replays/*.mfreplay` and prefix-matched `user://desync/desync_*` files this module created |

### 5.13 Firewall / permission behaviour and UI text

| OS | What happens | What the UI says (English defaults; keys `net.help.*`) |
|---|---|---|
| Windows | First `bind`/`listen` (hosting, or opening the LAN browser) triggers a **Windows Defender Firewall** prompt per program and per profile; the *Public* profile blocks by default | "Windows may ask whether to allow Meridian Fracture through the firewall. Choose **Private networks** and click Allow. Missed it? Windows Security > Firewall & network protection > Allow an app through firewall > Meridian Fracture > tick Private." |
| macOS | (a) macOS firewall prompt on first listen if the firewall is enabled; (b) **macOS 15+ "Local Network" privacy prompt** on first LAN traffic (broadcast or connect to a LAN address). No dedicated export option exists in 4.7.2's macOS preset: `application/additional_plist_content` must inject `NSLocalNetworkUsageDescription` (verified option list in `tools/godot_docs/platform/macos`); app sandbox stays off (if ever enabled, `network_client` **and** `network_server` entitlements are required) [XR-15]. If the user denies, sends silently fail or are dropped | "macOS may ask whether Meridian Fracture can find and connect to devices on your local network. Choose **Allow**. Missed it? System Settings > Privacy & Security > Local Network > enable Meridian Fracture." |
| Linux (Debian) | No prompt; a distro firewall may drop inbound UDP | "If you use ufw: `sudo ufw allow 27614:27624/udp`. With nftables/iptables allow inbound UDP 27614-27624 on your LAN interface." |
| All | ports | "Ports used: UDP 27615 (game; 27615-27624 if busy) and UDP 27614 (LAN discovery). Joining by IP only needs the host's game port." |

Rules for the UI: show a one-time explainer *before* the first socket is opened (setting `net/help_shown`), so the OS dialog is expected; show `net.help.no_games` after 8 s of empty browse and `net.help.announce_blocked` when `announce_ok` is false for 10 s; never block the menu waiting for the OS dialog (sockets are created lazily and nothing waits on them). Default English strings for errors: `net.err.connect_timeout` "Could not reach {address}:{port} within 6 seconds. Check the address, that the host has opened a game, and that UDP {port} is allowed through the host's firewall."; `net.err.proto|sim|data` = the mismatch text of §5.3.1 naming the failing layer; `net.err.full` "The game is full."; `net.err.in_progress` "The match has already started."; `net.err.banned` "The host removed you from this game."; `net.err.bad_password` "Wrong password."; `net.err.host_busy` "The host is starting the game. Try again in a moment."; `net.err.no_port` "No free network port (27615-27624). Close other instances of the game."; `net.err.map_mismatch` "{name} generated a different map (host {h1}, {name} {h2}). Both computers must run the same version. Details were written to the log."; `net.err.config_mismatch` "The match settings were corrupted in transit."; `net.err.host_left` "The host left the game."; `net.stall.waiting` "Waiting for {names}... {seconds} s"; `net.stall.waiting_host` "Waiting for the host..."; `net.pause.by` "{name} paused the game ({left} pauses left)"; `net.desync.title/body` as §5.7; `net.err.replay_version` "This replay was recorded with a different game version and cannot be played back exactly."

### 5.14 How the bible rules in this domain are honoured

| Bible source | Rule | Where honoured |
|---|---|---|
| `rule.design.roster_selection` | Choose one of 32 rosters before the match; cannot mix subfaction packages | Roster is one atomic id per player in the lobby (§5.3.2); vanilla and subfactions are one list; random tokens resolve to a whole roster |
| `mechanical_conventions.starting_preset` (HQ + 7,500 credits, veterancy disabled) and `rule.design.economy` ("medium game speed") | Default match | Lobby defaults `start_credits = 7500`, `veterancy = false`, speed code 2 = 100 % "Medium" (§7.2); the deployed HQ start itself is sim/data |
| `rule.design.caps_and_interpretation` (cost/build-time floor 60 %, reload floor 50 %, resistance cap 50 %) | Layered modifiers with caps | Net never transmits derived stats, only roster ids and per-player `handicap_pct`, which is economic only (§5.3.6) so caps and layering stay in `data`; `versions.data_hash` guarantees identical resolved tables |
| `prototype_priorities` (three map families, >= 2 exits, no mandatory water, every roster playable on land) | Map families | `map_family` 0 open land / 1 urban routes / 2 coast & river; no roster-to-map coupling in the lobby, any roster on any family |
| `metadata.expected_counts` (8 factions x 4 = 32 rosters) | Content size | `opts.roster_ids` must contain exactly 32 ids at session creation (asserted; a different count fails `NetMatchConfig.validate` and blocks hosting) |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 Sim commands: what net carries and what net injects

* **Carried opaque.** Every player command is a `PackedInt32Array [type, args...]` produced by the UI (`UiCommandBus`) and consumed by `SimWorld` through `NetSimAdapter.submit_command(pid, ints)`. Net validates only the envelope: `1 <= size <= 1024`, `0 <= ints[0] <= 255`. Semantics, ownership, target legality: sim (deterministic, identical on all peers).
* **Net-reserved command types `240..255`** — sim must not allocate them for gameplay [XR-2]. v1 defines one:

| Type | Name | ints | Meaning | Who issues |
|---|---|---|---|---|
| `250` | `T_RESIGN` | `[250, reason]`, `reason` = `ResignReason` (0 surrender, 1 disconnect, 2 kicked, 3 timeout) | The player is eliminated when this command executes (structures/units per sim's elimination rules; victory evaluation in the same tick's CleanupSystem). Idempotent; legal in any state; afterwards the sim ignores every other command from that pid | the player himself (`NetSession.surrender()` via the normal input path) or the **host on behalf of** a departed/dropped/kicked human (placed first in that pid's group of the bundle at the injection turn) |

`reason` is informational (sim may emit a `PLAYER_RESIGNED(pid, reason)` event for UI/audio; net does not read sim events).
* **Sim-side obligations** (also [XR-1]..[XR-10]): unknown or malformed command => deterministic ignore + counter (never an engine error); commands of a resigned/defeated pid ignored; debug/cheat commands unavailable in multiplayer matches.

### 6.2 Net control records (inside `TURN_BUNDLE`; they never reach the sim)

| Kind | Code | Args | Effect on every peer when the bundle executes |
|---|---|---|---|
| `INPUT_DELAY` | 1 | `u8 d` | `_delay = d`; next fill-up uses it (§5.5.3) |
| `PLAYER_STATUS` | 2 | `u8 pid, u8 status (PlayerNetStatus), u8 aux` | UI/replay bookkeeping; `aux` = AI level for `AI_TAKEOVER`, `ResignReason` for `DROPPED/RESIGNED/LEFT` |
| `SPEED` | 3 | `u16 speed_pct` | pacing multiplier (not sim state) |
| `MATCH_END` | 4 | `u8 reason (MatchEndReason)` | host-declared end (e.g. `NO_HUMANS_LEFT`); sim-decided ends need no record |
| `PAUSE` | 5 | `u8 by_pid` | pause after this turn (§5.5.8) |

### 6.3 Events emitted (signals of `NetSession`; codes are the enums of §4.2)

| Signal | Fires when | Payload / meaning | Consumers |
|---|---|---|---|
| `phase_changed(phase, previous)` | any `Phase` transition | `NetSession.Phase` | app scene flow, ui |
| `lobby_changed()` | lobby state revision applied | re-read `lobby.state` | ui lobby screen |
| `chat_received(channel, from_pid, from_name, text)` | chat line (lobby or match), `from_pid` 255 = system | 0 all / 1 team | ui |
| `countdown_changed(s)` | 3, 2, 1, 0 (aborted) | seconds left | ui, audio |
| `join_rejected(reason, info)` | `JOIN_REJECT` received | `RejectReason`; `info` = {host_version, host_proto, host_sim, host_data_hash, my_*, session_id, detail} | ui (`describe_reject`) |
| `kicked(reason, detail)` | `KICKED` / host gone | `KickReason` | ui |
| `load_progress(pids, percents)` | `LOAD_STATUS` | per-player 0..100 | ui loading screen |
| `launch_aborted(reason, detail)` | `LAUNCH_ABORT` | `AbortReason`, human-readable detail | ui |
| `match_started()` | `START` applied, tick 0 | — | app: switch to game scene, view builds `ViewWorld` |
| `stall_changed(waiting)` | overlay state changes | `[{pid,name,reason,wait_ms}]`, empty = resumed | ui overlay |
| `stall_prompt(pids)` | host only, §5.5.7 | offer `StallAction` | ui dialog -> `host_resolve_stall` |
| `pause_changed(paused, by_pid)` | pause/resume applied | | ui, audio |
| `player_status_changed(pid, status)` | `CK_PLAYER_STATUS` executed or local detection | `PlayerNetStatus` | ui scoreboard |
| `speed_changed(pct)` / `input_delay_changed(turns)` | ctrl record executed | | ui HUD |
| `match_ended(result)` | sim over, host closed, abandoned, desync | `{reason (MatchEndReason), sim_reason, winner_team, final_tick, final_checksum}` | ui score screen |
| `desync_detected(report)` | §5.7 | report dictionary (§7.5) | ui dialog |
| `net_error(code, text)` | non-fatal problems (replay write failed, no checksum snapshot, ...) | codes: `1 REPLAY_WRITE`, `2 NO_CHECKSUM`, `3 HOST_PROTOCOL`, `4 TRANSPORT`, `5 BUILD_FAILED` | ui toast |
| `map_ping(from_pid, x, y)` | teammate ping | cells | ui minimap |
| `NetDiscovery.entries_changed()` | browse table changed | | ui server list |
| `NetReplayPlayer.verify_failed(tick, expected, actual)` / `finished()` | §5.8 | | ui replay screen |

Replay `EVENT` records mirror `PLAYER_STATUS` and chat so a replay viewer can show them. Net consumes **no sim events**; it reads sim state only through `NetSimAdapter` (`is_match_over`, `match_result`, `is_player_active`).

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.1 `MatchConfig` (authoritative schema; JSON; ints/strings/bools only)

Produced by `NetMatchConfig.from_lobby`, sent in `LAUNCH_CONFIG`, stored in the replay header (`"config"`), consumed by `world_builder`. **Canonical form**: `JSON.stringify(cfg, "", true)` (sorted keys, no whitespace); the hash is over the exact transmitted bytes. `normalize()` rebuilds the dictionary from this whitelist; any unknown key, wrong type, non-integral/non-finite number, out-of-range value or duplicate pid/colour/start => `{}` (rejected).

| Key | Type | Range / values | Notes |
|---|---|---|---|
| `format` | int | `1` | schema version |
| `match_id` | string | 16 hex | metadata, never read by sim |
| `created_unix` | int | >= 0 | metadata, never read by sim |
| `versions.game` | string | <= 24 chars | informational |
| `versions.proto` / `versions.sim` | int | must equal local | |
| `versions.data_hash` | int | u32, must equal local | |
| `versions.data_format` / `versions.data_ids` | int | `GameData.FORMAT_VERSION` / `table_hashes["ids"]`, must equal local | recorded so replay playback can tell "same ids, changed balance" from "different content" (§5.8) |
| `seed` | int | u32 | sim RNG seed |
| `map.family` / `map.size` / `map.seed` / `map.layout_players` | int | 0..2 / 96..256 step 8 / u32 / 2,4,6,8 | `map.params` = `{}` reserved |
| `rules.<key>` | int or bool | **exactly the keys of `lobby_options.json` `rules_schema`**, each within its `min`/`max`; unknown keys rejected | the sim's `MatchRules` fields. Current union: `start_credits` 0..100000 (7500, bible preset), `unit_cap` 20..500 (150, ARCH §12), `superweapons` (true), `fog` (true), `shared_vision` (false), `veterancy` (false, bible), `vision_stride` 1..4 (2) and `vision_budget` 16..512 (128) — the last two are performance knobs that MUST be identical on all peers (abilities spec §5.9), hence host-chosen, not per-client settings |
| `net.turn_ticks` / `net.checksum_period` | int | must equal `SimConfig` (2 / 20) | |
| `net.input_delay` | int | 1..8 | initial D0 |
| `net.speed_pct` | int | one of `SPEED_PCT` | pacing only; **not under `rules`** so sim cannot read it by accident |
| `net.pause_policy` / `net.on_disconnect` / `net.auto_drop_ms` / `net.allow_spectators` | int/int/int/bool | 0..2 / 0..1 / 0..600000 / | |
| `players[]` | array 1..8 | sorted by `pid` | |
| `players[].pid` | int | 0..7 unique | |
| `players[].kind` | string | `"human"` \| `"ai"` | |
| `players[].peer` | int | human >= 1 (host = 1), ai = 0 | transport peer id at launch |
| `players[].name` | string | 1..24 chars, sanitised | AI: `"AI <pid+1>"` |
| `players[].roster` | string | one of the 32 ids (concrete, random already resolved) | |
| `players[].team` | int | final team id: `1..4` or `8 + pid` | |
| `players[].color` / `start` / `handicap` | int | 0..11 unique / 0..layout-1 unique / 50..200 step 5 | |
| `players[].ai` | object | `{level:int, style:int, flags:int}` only when `kind == "ai"`; `flags` bit0 = fog cheat (default from the AI domain: set for its top level) | |

Worked example (pretty-printed for reading; a 2-human + 1-AI match, host is pid 0):
```json
{
  "created_unix": 1790677613,
  "format": 1,
  "map": {"family": 0, "layout_players": 4, "params": {}, "seed": 20240517, "size": 128},
  "match_id": "a3f19c0e5b7d2468",
  "net": {"allow_spectators": true, "auto_drop_ms": 60000, "checksum_period": 20, "input_delay": 2, "on_disconnect": 0, "pause_policy": 1, "speed_pct": 100, "turn_ticks": 2},
  "players": [
    {"color": 1, "handicap": 100, "kind": "human", "name": "Simon", "peer": 1, "pid": 0, "roster": "roster.napc.canada", "start": 0, "team": 1},
    {"color": 4, "handicap": 100, "kind": "human", "name": "Mia", "peer": 2, "pid": 1, "roster": "roster.nec.vanilla", "start": 1, "team": 1},
    {"ai": {"flags": 0, "level": 2, "style": 0}, "color": 0, "handicap": 100, "kind": "ai", "name": "AI 3", "peer": 0, "pid": 2, "roster": "roster.han.china", "start": 2, "team": 10}
  ],
  "rules": {"fog": true, "shared_vision": false, "start_credits": 7500, "superweapons": true, "unit_cap": 150, "veterancy": false, "vision_budget": 128, "vision_stride": 2},
  "seed": 3141592653,
  "versions": {"data_format": 1, "data_hash": 2882343476, "data_ids": 1360295431, "game": "0.1.0", "proto": 1, "sim": 1}
}
```
(Slot 2 had team `0` "no team" in the lobby => `team = 8 + pid = 10`. Colours were auto-assigned/chosen; `start` values were `-1` and resolved.) [XR-9: `SimWorld` must accept exactly this dictionary and ignore `net`, `versions`, `match_id`, `created_unix`.]

### 7.2 `game/data/net/lobby_options.json` (lobby choices; UI text comes from `data/text` via the `key`s)

```json
{
  "format": 1,
  "speeds": [{"code":0,"pct":50,"key":"very_slow"},{"code":1,"pct":75,"key":"slow"},{"code":2,"pct":100,"key":"medium","default":true},
             {"code":3,"pct":125,"key":"fast"},{"code":4,"pct":150,"key":"faster"},{"code":5,"pct":200,"key":"turbo"}],
  "map_families": [{"id":0,"key":"open_land"},{"id":1,"key":"urban_routes"},{"id":2,"key":"coast_river"}],
  "map_sizes": [96,128,160,192,224,256],
  "layout_players": [2,4,6,8],
  "teams": [{"id":0,"key":"none"},{"id":1,"key":"a"},{"id":2,"key":"b"},{"id":3,"key":"c"},{"id":4,"key":"d"}],
  "handicaps": [50,60,70,80,90,100,110,120,130,140,150,175,200],
  "colors": [{"id":0,"key":"crimson","srgb":"D93A3A"},{"id":1,"key":"azure","srgb":"2F7DE1"},{"id":2,"key":"emerald","srgb":"2DB56A"},
             {"id":3,"key":"amber","srgb":"F2B234"},{"id":4,"key":"violet","srgb":"8B5CD6"},{"id":5,"key":"cyan","srgb":"27C4D6"},
             {"id":6,"key":"orange","srgb":"F0782A"},{"id":7,"key":"magenta","srgb":"D9479B"},{"id":8,"key":"lime","srgb":"9BD13B"},
             {"id":9,"key":"slate","srgb":"8A97A8"},{"id":10,"key":"brown","srgb":"8C5A3B"},{"id":11,"key":"white","srgb":"ECECEC"}],
  "ai_levels": [{"id":0,"key":"easy"},{"id":1,"key":"medium"},{"id":2,"key":"hard"},{"id":3,"key":"brutal"}],
  "pause_policies": [{"id":0,"key":"host_only"},{"id":1,"key":"any_player","default":true},{"id":2,"key":"disabled"}],
  "on_disconnect": [{"id":0,"key":"resign","default":true},{"id":1,"key":"ai"}],
  "auto_drop_ms": [0, 30000, 60000, 120000],
  "rules_schema": [{"key":"start_credits","type":"int","min":0,"max":100000,"step":500,"default":7500},
                   {"key":"unit_cap","type":"int","min":20,"max":500,"step":10,"default":150},
                   {"key":"superweapons","type":"bool","default":true},
                   {"key":"fog","type":"bool","default":true},
                   {"key":"shared_vision","type":"bool","default":false},
                   {"key":"veterancy","type":"bool","default":false},
                   {"key":"vision_stride","type":"int","min":1,"max":4,"default":2,"advanced":true},
                   {"key":"vision_budget","type":"int","min":16,"max":512,"default":128,"advanced":true}],
  "defaults": {"map": {"family":0,"size":128,"layout_players":4},
               "net": {"speed_code":2,"pause_policy":1,"on_disconnect":0,"auto_drop_ms":60000,"allow_spectators":true}}
}
```
The `srgb` values are defaults for lobby swatches and tests; the authoritative team-colour palette lives in `ui/view` (`UiTheme`), indexed by the same `id`s [XR-16]. `ai_levels`/styles are owned by `ai`; the file is the fallback used when `opts.ai_level_count` is not supplied.

### 7.3 `user://settings.cfg` — `[net]` section (owned/persisted by `app`; read into `NetSessionOptions`)

```ini
[net]
player_name="Simon"            ; default: sanitised OS user name, else "Commander"
port=27615
last_address="192.168.1.20:27615"
recent_hosts=["192.168.1.20:27615"]   ; <= 8, most recent first (quick join)
discovery=true
allow_public_discovery=false   ; accept announce datagrams from non-private source IPs
min_input_delay=2              ; advanced: 1..4 (LAN default 2)
auto_drop_ms=60000
replay_autosave_count=3
record_chat=true
show_net_overlay=false
help_shown=false               ; one-time firewall/permission explainer
log_to_file=false              ; user://logs/net_<match8>.log (<= 2 MB, rotates once)
```

### 7.4 Replay header — see §4.8 (binary container + canonical JSON `{"replay":{...},"config":{...}}`).

### 7.5 Desync report (`desync_<match8>_p<pid>_t<tick>.json`; also the `desync_detected` payload)

```json
{
  "format": 1, "kind": "sim", "tick": 4200, "time": "2026-09-29 14:03:11", "match_id": "a3f19c0e5b7d2468",
  "local": {"peer": 2, "pid": 1, "checksum": 439041101, "chain": 2797693171, "parts": [11, 22, 33, 44, 55, 66, 77, 88, 99, 100]},
  "reports": [{"pid": 0, "checksum": 2575857510, "chain": 2797693171, "parts": [11, 22, 33, 44, 55, 66, 700, 88, 99, 100]}],
  "part_names": ["entities","players","rng","map","production","economy","orders","combat","zones","vision"],
  "parts_diff": ["orders"],
  "last_good_tick": 4180,
  "versions": {"game": "0.1.0", "proto": 1, "sim": 1, "data_hash": 2882343476, "data_format": 1, "data_ids": 1360295431},
  "platform": {"os": "macOS", "arch": "arm64", "engine": "4.7.2-stable", "cpus": 18},
  "net": {"role": "client", "delay": 2, "rtt_ms": {"0": 24}, "violations": 0, "dup_in": 0, "late_in": 0},
  "files": {"state": "desync_a3f19c0e_p1_t4200.state.txt", "replay": "desync_a3f19c0e_p1_t4200.mfreplay", "checks": "desync_a3f19c0e_p1_t4200.checks.csv"},
  "message": "The game states diverged at 03:30 (tick 4200) in: orders."
}
```

### 7.6 Test data

`game/tests/net/profiles.json` (custom `NetFaultProfile`s by name; presets are built in) and scripted commands for the harness:
```json
{ "format": 1, "cmds": [ {"turn": 5, "pid": 0, "ints": [1, 2, 3]}, {"turn": 7, "pid": 1, "ints": [9]},
                         {"turn": 12, "pid": 0, "ints": [4, -5, 262144]}, {"turn": 12, "pid": 1, "ints": [7, 7]}, {"turn": 12, "pid": 1, "ints": [8]} ] }
```
`turn` is the **execution** turn: the harness submits a command when the local `exec_turn == turn - D - 1` (D fixed). This script with `NetSimAdapterFake` and D = 2 yields the golden values in §10.2.

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

**Boundary.** `net/` is outside the deterministic core (it may use wall time, floats, signals, `Dictionary`, engine RNG for *non-sim* purposes), but it is the **only writer of simulation input**, and what it writes is strictly `(turn, pid, ints[])` tuples in bundle order, applied at tick `2N` (I3). RTT, `D`, pacing, speed, pause, stalls, AI timing, wall clocks and frame rates can change *when* turn N executes on a machine, never *what* it contains. Prototype evidence: 300 s with +-150 ppm clock drift, 3 s freezes, pauses, drops and 4 % loss produced identical checksums and input chains on every peer.

| Rule | Compliance in this domain |
|---|---|
| DR-1 ints only | Commands are `PackedInt32Array`; codec is integer-only (`zvarint`); `NetBundle` never stores floats; MatchConfig has no floats (`normalize` rejects them) |
| DR-2 no engine randomness in sim | Sim RNG seed = `MatchConfig.seed`, chosen once by the host (`Crypto.generate_random_bytes`) and transmitted. Lobby randomness (`lobby_rand`) is host-only and its *results* are embedded in the config. AI RNG is private to the thinker, never `SimRng` |
| DR-3 no wall clock in sim | `Time`/`NetClock` used only in `net/`; nothing time-derived is passed to `submit_command` |
| DR-5 integer division | `zvarint` uses masked 32-bit arithmetic; FNV multiplies stay < 2^57 (no 64-bit overflow); pacing math is integer microseconds |
| DR-6/7 iteration and ordering | Groups are emitted for `pid = 0..7` by index (no dictionary iteration); commands keep submission order; `players[]` sorted by pid; JSON keys sorted; dictionaries in net are keyed by ints/strings for *lookup* only |
| DR-8 | Not applicable to `net/`, but no net callback runs *inside* a sim tick: `on_turn_begin`/`on_boundary` run between ticks |
| DR-9 no global state | Two `NetSession`s can coexist in one process (tests do this); the only static is `NetSession.last_create_error` (diagnostic text, never read by sim) |
| DR-10 data hash | `versions.data_hash` + `sim` + `proto` gate join and launch; `config_hash` in `START` |
| DR-12 events output-only | Net never reads sim events; it uses only the adapter queries in §3.3 |
| DR-13 checksum coverage | Net adds **no** persistent sim state. Per-player `handicap`, `team`, `color`, `start`, `roster`, `rules` enter the sim through the config, and sim must checksum whatever it stores from them [XR-9] |
| DR-14 AI/UI use of floats | AI output is int arrays; UI commands are int arrays |

**What is compared for divergence.** (1) *Sim checksum* (`SimWorld.checksum()` snapshot every 20 ticks; owned by sim, carried by net); (2) *input chain* `FNV-1a32` over `NetBundle.core_bytes()` of every executed turn, empty turns included, seeded with `0x811C9DC5` (owned by net, **not** part of the sim checksum, so it can never create a false sim desync); (3) `config_hash`, `map_hash`, tick-0 checksum at launch. Canonical bytes are *re-encoded* from decoded groups (never the raw wire bytes), and the decoders reject non-canonical varints, so equal decoded content implies equal chain input on every platform.

**Cross-platform specifics.** `PackedByteArray.encode_u32` is little-endian by definition; `JSON.stringify(cfg, "", true)` orders keys by string comparison (identical everywhere) and integers print without exponent; `%08X` formatting is display-only. `Dictionary` insertion order is never relied upon for anything hashed.

**Implementer hazards (each has a test).** Never derive sim behaviour from `speed_pct`, `D`, `turn_ms` or frame delta; never call `adapter.submit_command` outside `_begin_turn`; never reorder groups or commands; never run the AI on a client; never let a decode failure silently substitute content into a bundle (a malformed bundle is a protocol error, not an empty turn — the only sanctioned substitution is the *host's* empty input for an over-size `TURN_INPUT`, §5.5.5, which is counted in `stats().dropped_cmds` and scored against the sender).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

Net cost is per *turn* (10 Hz), not per tick: on the 19 non-boundary ticks per second the only net code is the loop overhead in `update()` (an integer add/compare and `step()` dispatch, < 2 us).

| Work | Rate | Cost (measured E6 or reasoned) | Worst case |
|---|---|---|---|
| `service(0)` + event drain | every frame | **9 us** idle with 8 peers (measured); +10 us per event | 8 peers x 10 events: 0.2 ms |
| Host: `send` to 8 peers + `flush()` | 10/s | **42 us** for 8 x 120 B (measured, all 2400/2400 packets received) | 8 x 6 KB fragmenting: < 1 ms |
| Client: encode `TURN_INPUT` | 10/s | 15-40 B: ~10 us | 64 cmds x 15 ints: ~0.5 ms |
| Host: decode `TURN_INPUT` | 70/s (7 clients) | ~15 us typical | 7 x 0.5 ms = 3.5 ms on one boundary frame |
| Host: assemble + encode bundle | 10/s | 37 B: ~30 us; 1335 B: **180 us** | 8 x 64 cmds: ~2 ms |
| Client: decode bundle + hash verify | 10/s | 1335 B: **209 us** + FNV 26 us | ~2 ms |
| `_begin_turn` (chain FNV, submit, fill-up, callbacks) | 10/s | < 100 us + `submit_command` per command (sim) | 512 cmds x 5 us = 2.5 ms |
| Checksum report + compare | 1/s | 13-byte message, compare O(peers) | negligible (sim checksum cost is sim's; budget <= 1 ms) |
| AI thinkers (host) | default period 5 => <= 2 per boundary; per-level periods [5,3,2,1] => up to 8 (all Brutal) | AI budget <= 3 ms each | governor caps AI time at 8 ms per boundary (overdue thinkers rotate); throttled if > 12 ms twice (§5.6) |
| Recorder | per non-empty turn | 5-20 us append; `flush()` 1/s ~ 0.1 ms | 0.5 ms |
| Delay policy `evaluate` | 2/s | < 50 us | — |
| Discovery announce | 1/s | <= 12 `put_packet` ~ 0.2 ms | 0.3 ms |
| Lobby snapshot | <= 10/s in lobby only | encode ~60 us, <= 1.3 KB x peers | 0.5 ms |

* **Per-frame steady state at 60 FPS**: idle frames ~0.1 ms of net; boundary frames (1 in 6) ~0.3-0.6 ms; heavy 8-player boundary ~3 ms (+ AI up to 6 ms on the host). Budget stated in ARCH terms: net <= 1 ms average, <= 8 ms worst frame.
* **Bandwidth** (prototype, 4 peers): 4 KB/s aggregate; per client downstream ~1.3 KB/s typical (bundle 37-200 B x 10/s + ~36 B/packet ENet/UDP/IP overhead); worst 8 players heavy APM: bundle ~1.3 KB x 10/s = 13 KB/s per client (0.1 Mbit/s), host upstream 7 x 13 = 91 KB/s (0.73 Mbit/s), client upstream <= 6 KB/s. LAN and Wi-Fi are far above this.
* **Memory**: bundles are dropped after execution (<= ~12 alive); pending inputs bounded (32-turn windows x 8); recorder writes to disk (nothing retained); the desync package copies the recording file once; discovery table <= 64; ban set <= 256.
* **Catch-up after a stall**: <= 8 ticks per poll (4 turns); a 1 s backlog is absorbed in 3 frames; the accumulator cap discards anything older.
* **Slow machine**: if `sim.step()` averages > 50 ms the whole match slows to that machine (the barrier); `NetLockstep` reports `load_pct = 100 * ewma(step_cost) / tick_us` (0..255) in `PONG`; the host labels the peer `SLOW_CPU` in `STALL_INFO` and the overlay says "{name}'s computer is running slowly".
* **Large lobbies**: 24 peers max; snapshot fan-out 24 x 1.3 KB at <= 10/s is trivial.
* **Mitigations catalogue**: sliced world build; pre-sized `PackedByteArray` writers (double-on-grow); no per-tick allocation in the runner (reused arrays; per-turn `NetBundle` objects only); ring buffers instead of unbounded arrays; message dispatch by `match` on `int` codes.

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

### 10.1 Conventions
Files `game/tests/net/test_net_*.gd` (`extends RefCounted`, `func test_*(t: TestCtx)`); the QA runner fails a test on **any engine error**, so tests that intentionally provoke one (`decompress` of garbage, closed-port connect) declare `t.expect_errors(n)`. Virtual-time tests use `NetClock.manual()`, a 60 Hz frame loop (`advance_us(16667)`, per-peer phase offsets) and `NetTransportLoopback` + `NetTransportFault`; socket tests bind ports from a test range (`28100 + OS.get_process_id() % 300`) and never touch 27614/27615. Every scenario test also asserts "0 engine errors, 0 checksum/chain mismatches" implicitly through the runner.

### 10.2 Reference vectors (these are the acceptance numbers; all were produced by scratch code in the design phase)

| Vector | Value |
|---|---|
| FNV-1a 32 | `""` = `811C9DC5`, `"a"` = `E40C292C`, `"foobar"` = `BF9CF968` |
| varint | `0`=`00`, `127`=`7F`, `128`=`80 01`, `16383`=`FF 7F`, `16384`=`80 80 01`, `2^32-1`=`FF FF FF FF 0F`; overlong `80 00` and any 6-byte form rejected |
| zvarint | `0`=`00`, `-1`=`01`, `1`=`02`, `-2`=`03`, `2147483647`=`FE FF FF FF 0F`, `-2147483648`=`FF FF FF FF 0F` |
| messages | the hex goldens in §4.4 (`JOIN_REQUEST` 26 B, `TURN_INPUT` 15 B, `TURN_BUNDLE` 23 B and 14 B, `PING`, `PONG` 20 B, `CHECKSUM_REPORT`, `START`, discovery announce 49 B) |
| lobby RNG | `mix32(0)=0`, `mix32(1)=514E28B7`, `mix32(DEADBEEF)=0DE5C6A9`; `lobby_rand(1,0..3)=96A0F96B,12BC8390,971E9964,79ADC7E7`; shuffle of `[0..7]`, seed 12345 => `[7,3,2,0,1,6,5,4]` |
| broadcast candidates | `172.16.223.202` => `[255.255.255.255, 172.16.223.255, 172.16.255.255]`; `192.168.1.20` => `[255.255.255.255, 192.168.1.255, 192.168.255.255]`; `10.4.7.9` => `[255.255.255.255, 10.4.7.255, 10.4.255.255, 10.255.255.255]` |

**`NetSimAdapterFake` (exact algorithm; `mix(h,v) = ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF`).** `state = 12345`, `state_b = 0x2545F491`, `tick = 0`, `pending = []`. `submit_command(pid, ints)` appends. `step()`: for each pending `(pid, ints)` in call order `state = mix(state, 0x1000 + pid)` then `state = mix(state, v)` for each `v`; clear pending; `state = (state * 1103515245 + 12345 + tick) & 0xFFFFFFFF`; `state_b = mix(state_b, tick)`; `tick += 1`; if `tick % 20 == 0` store snapshot `total = mix(state, state_b)`, `parts = [state, state_b]` (names `["cmds","clock"]`, retain 64). `checksum_now() = mix(state, state_b)`; `map_hash() = fnv1a32(("fake-map:" + str(seed)).to_utf8_buffer())`; `dump_state() = "state=%08X\nstate_b=%08X\ntick=%d\n"`; command type 250 marks the pid resigned (`is_player_active` false); test hook `inject_divergence(at_tick, part)` flips bit 0 of that part once. **Golden** for script S0 (§7.6: turn 5 pid0 `[1,2,3]`; turn 7 pid1 `[9]`; turn 12 pid0 `[4,-5,262144]` and pid1 `[7,7]`,`[8]`; any pipeline, D fixed):

| tick | checksum | input chain | parts (`cmds`, `clock`) |
|---|---|---|---|
| 20 | `E7DDB1C4` | `A6C168F3` | `E50086E1`, `C8E2374D` |
| 40 | `9C652497` | `A46D1BD5` | `1985D524`, `047C9649` |
| 60 | `8F911C91` | `338B671A` | `AC325A1E`, `49FC95D5` |
| 80 | `45C83A4B` | `3DD9FC11` | `E5D90FE8`, `99B23881` |
| 100 | `F3AE0C0D` | `8FA5BAAE` | `D8534782`, `16D3F85D` |

### 10.3 Unit tests

| File | Cases (expected results) |
|---|---|
| `test_net_codec.gd` | varint/zvarint vectors; every §4.4 golden byte-exact (encode) and round-trips (decode); bundle rejects: non-ascending pids, 9 groups, 0 or 65 commands, `n = 0` or `1025`, unknown flag bit, `ctrl_count` 0 or 9, trailing byte, flipped hash bit, truncation at **every** length; **fuzz**: 20 000 random + 20 000 single/multi-byte mutations per decoder => no engine error, and any accepted buffer re-encodes to identical bytes (canonical); encoders return empty for over-limit input |
| `test_net_protocol.gd` | RNG vectors; `sanitize_name`: `"  Bob  "`->`"Bob"`, `"[b]X[/b]"` -> no brackets, control chars removed, 30 chars -> 24, `""`->`"Player"`; `sanitize_text` never splits a UTF-8 sequence (`"é"` x 150 -> <= 200 valid bytes); `is_valid_utf8` table (`Bob`, `Zoë 日本` and the 4-byte emoji `F0 9F 98 80` valid; `FF FE 41`, truncated `41 C3`, embedded `41 00 42`, overlong `C0 80`, surrogate `ED A0 80`, `F4 90 80 80` invalid, all without any engine message); `is_private_ipv4` table (10.1.2.3 yes, 172.32.0.1 no, 100.64.0.1 yes, 8.8.8.8 no); `parse_address` table (`"192.168.1.20"` -> port 27615, `" 10.0.0.5:28000 "` -> 28000, `"[fe80::1]:27620"`, `"host.local"`, rejects `"1.2.3.4:0"`, `"1.2.3.4:70000"`, `"fe80::1%en0"`, empty string, 300 chars); `describe_reject(DATA_MISMATCH, ...)` contains both hashes as 8 upper-case hex digits |
| `test_net_transport_loopback.gd` | ordering per channel; channel isolation; disconnect code delivered after queued packets (`graceful`); `take_events` drains; sending on channel 3 returns `ERR_INVALID_PARAMETER` |
| `test_net_transport_enet.gd` | two `NetTransportEnet` in one process: connect data delivered; 4 MB message intact; `KICKED`+graceful disconnect arrives in order with the code; occupy 27615..27616 with UDP sockets => host listens on 27617 **with zero engine errors** (probe is quiet); connect to a closed local port => `DISCONNECTED` within 6.0-6.5 s (real clock, `expect_errors(0)`); dual-stack: connect to `127.0.0.1` and `::1` succeed when bound `"*"` (skip `::1` if the machine has no IPv6); peer stats never read after disconnect |
| `test_net_fault.gd` | ordered mode never reorders 10 000 messages; unordered `raw_chaos` reorders/duplicates within tolerance; latency mean within +-10 % of profile, jitter bounds respected; loss in ordered mode inflates delay by multiples of `rto`; `freeze_for_ms` holds delivery exactly; same seed => identical delivery schedule |
| `test_net_lockstep_unit.gd` | §5.5.3 fill-up table reproduced (feed `INPUT_DELAY` 3 at E=12, 2 at E=14 and assert the exact packet turns sent); barrier: bundles 0..2 only => `update()` stops at tick 6 with `is_stalled()`, resumes when bundle 3 arrives; `MAX_TICKS_PER_POLL`=8 and accumulator cap after a 5 s clock jump; S0 goldens (chain + fake checksums) at ticks 20..100; pause armed by `CK_PAUSE` at turn 9 => `is_paused()` at boundary 10 and no `on_send_input` while paused; `SPEED` 200 % halves wall time; `match_over` stops updates and emits a final checksum |
| `test_net_turn_host.gd` | every row of the §5.5.5 table (DUPLICATE, LATE, BUFFERED then drained, TOO_FAR at `next_close + D_MAX + 3`, TOO_BIG substitutes empty); `close_ready` blocks on the slowest human then releases 16 max per call; groups ascending, `T_RESIGN` first; AI group merged; ctrl attached once; drop-AI discards buffered inputs >= N; `waiting()` reasons; prompt at 8 s (manual clock); auto-drop at 60 s and at 5 s for `DISCONNECTED`; pause budget (4th request `BUDGET_EXHAUSTED`); `PAUSE_REQUEST` by non-pauser cannot resume |
| `test_net_delay_policy.gd` | (a) LAN samples (rtt 20, jit 4) => D stays 2; (b) rtt 250/jit 50 => `ceil((250+100+34)/100) = 4`, reached within two evaluations (>= 1 s cooldown); (c) one `hitch` PONG or rtt 3000 => 3 s quarantine, D unchanged; (d) stall samples 250 + 250 ms within 10 s => raise once (2->3), rings cleared, no second raise for 2 s; (e) D=4, no stalls, slack >= 160 for 8 s and `d_target = 2` => 3 at t >= 8 s, 2 at t >= 16 s; (f) `fixed_input_delay` bypass; (g) 200 % speed => `turn_ms = 50`, same RTT => larger D |
| `test_net_lobby.gd` | join accept/reject for each `RejectReason` (message text checked); permissions matrix (client editing another slot ignored + scored); colour swap and start swap; AI level change applies the default handicap (Brutal 120); layout shrink closes slots; unique names; countdown lock and abort by `SET_READY(false)`; kick/ban blocks re-join (same IP or same nonce); every `StartError` reachable; snapshot revision ordering (older snapshot ignored); chat rate limit (6th message in 5 s dropped); password proof accepted/rejected |
| `test_net_match_config.gd` | round-trip of the §7.1 example; `normalize` rejects: unknown key, `1.5`, `nan`/`inf` (`1e400`), negative pid, duplicate pid/colour/start, roster not in list, `size = 100`, 9 players, `players` not sorted, oversize string, nesting > schema; float-valued integers (`3141592653.0`) accepted and coerced to int; `canonical_json` byte-stable; `random.*` resolution reproducible (same seed => same rosters/starts) and independent of slot edit order |
| `test_net_discovery.gd` | golden datagram decode/encode; garbage/oversize/bad-magic/bad-UTF-8 ignored; expiry at 4 s (manual clock) and immediate removal on `CLOSED`; candidate table; circuit breaker after 5 failures; real UDP unicast test with `set_targets_override(["127.0.0.1"])` on a test discovery port |
| `test_net_replay.gd` | record -> load -> `verify_file` OK; loader survives truncation at every 97th byte offset (`truncated == true`, prefix verified) and rejects corrupt header fnv; unknown record types skipped; seek forward/backward to tick 1000 yields the same `dump_state` hash as a straight run; speed 4x advances 4x ticks per wall time; `verify_failed` fires once at the injected divergence; autosave rotation over 5 matches with keep 3 => names/contents; `recover_orphans`; `save_copy` sanitises `"../x"` |
| `test_net_desync.gd` | injected divergence in `clock` at tick 400 on one client => detected on the first report after tick 400 (<= 1.2 s virtual), `kind == SIM`, `parts_diff == ["clock"]`, files written (`.json`, `.state.txt`, `.mfreplay`, `.checks.csv`), 11th package deletes the oldest; chain-fault injection (host encodes different command order for one client) => `kind == INPUT_CHAIN`; classify table |
| `test_net_security.gd` | per message type: oversize, truncated, wrong phase, wrong role => dropped + scored, session survives; 12 points kick with `PROTOCOL_VIOLATION`; 5th connection from one IP refused; 9th unauthenticated peer refused; handshake timeout 5 s; wrong connect magic => `disconnect_now`; zip bomb config => `LOAD_FAILED`, no crash (`expect_errors(1)`) |

### 10.4 Scenario tests (`test_net_scenarios.gd`; virtual time, host + 3 clients, `NetSimAdapterFake`, S0-style random scripts unless stated)

| ID | Setup | Expected (tolerances from the prototype) |
|---|---|---|
| S1 | `lan`, 120 s | every peer at tick 2397-2400; 0 mismatches; `delay_turns == 2` always; command latency avg 240 +-20 ms, p95 <= 300; 0 stalls; total wire <= 6 KB/s |
| S2 | `wifi`, 120 s | D stays 2; total stall <= 100 ms; 0 mismatches |
| S3 | `bad_wifi`, 120 s | final D in [3,5]; total client stall <= 5 s; avg latency <= 520 ms; 0 mismatches |
| S4 | `internet`, 120 s | final D in [4,6]; avg latency <= 650 ms |
| S5 | `awful`, 120 s | D == 8; ticks >= 80 % of 2400; 0 mismatches |
| S6 | `wifi`, clocks +150/-150 ppm, 300 s | D == 2, <= 15 stalls, 0 mismatches |
| S7 | `lan`, client 2 frozen 3 s at 20 s | others stall 2.5-3.2 s; **D unchanged** (quarantine); tick spread <= 2 after resume; 0 mismatches |
| S8 | `lan`, pause at 10 s, resume at 13 s | all peers report the same `current_tick` for the whole pause; total ticks = expected - 60 +-2; `pause_changed` fired on all; requester's `pauses_used == 1` |
| S9 | `lan`, client 1 frozen 10 s at 30 s; host `DROP_AI` at 40 s (stub thinker emits `[9,pid]` each think) | game continues; from the next boundary the bundles contain pid 1 AI commands; `player_status(1) == AI_TAKEOVER` on all peers; 0 mismatches |
| S10 | as S9 with `DROP_RESIGN` | the turn after the drop has `[250, 1]` first in pid 1's group on every peer; fake `is_player_active(1) == false` everywhere |
| S11 | `raw_chaos` (unordered, dup 3 %, reorder 10 %) | identical chains; `dup_in > 0` and `ooo_in > 0`; 0 mismatches |
| S12 | LOCAL, 3 stub AIs, 6000 ticks | `NetSelfTest.run_double` ok; final checksum equals a second identical run |
| S13 | injected sim divergence (fake `inject_divergence(400, 1)` on client 2) | §10.3 desync row; all peers `phase == DESYNCED`; package exists on every peer |
| S14 | one relayed bundle corrupted in flight (`NetTransportFault.corrupt_next`) | bundle hash mismatch => `net_error(HOST_PROTOCOL)` on that client, **no desync report** |
| S15 | client with `data_hash + 1` joins (stub `data_handshake` whose table `units` differs; second variant also differs in file `balance/units_napc.json`) | `JOIN_REJECT(DATA_MISMATCH)` + `DATA_DIFF` lines `table units differs`; the client reconnects once with file hashes and the UI gets `file balance/units_napc.json differs`; text lists both hashes; lobby unchanged |
| S16 | lobby full / banned / wrong password / spectators closed | the matching `RejectReason` |
| S17 | launch with one client whose builder returns another `map_hash` | `LAUNCH_ABORT(MAP_MISMATCH, pid)`; everybody back in `LOBBY`, unlocked |
| S18 | client leaves during `LOADING` | `LAUNCH_ABORT(HUMAN_LEFT, pid)` |
| S19 | 8-player lobby (5 humans + 3 AI) full launch | all `LOAD_DONE` within 120 s; `START`; 60 s of play; 0 mismatches |
| S20 (phase 3) | spectator joins at 60 s of a running match | catches up unpaced, then follows live; its chain equals the players' at every checksum tick |

### 10.5 Determinism tests
* **D1** `NetSelfTest.run_double` (fake sim, S0-like random script, 6000 ticks): `ok`, `compared == 300`.
* **D2** Same script through (a) 2-peer loopback, (b) LOCAL, (c) replay playback: final checksum and chain identical (for S0 with D = 2: `F3AE0C0D` / `8FA5BAAE` at tick 100).
* **D3** Golden replays (`game/tests/fixtures/net/replays/*.mfreplay`) verified on macOS arm64, Linux container (Debian, x86_64) and Windows: every CHECK matches (this is the cross-platform sim determinism gate, owned jointly with sim/QA).
* **D4** With the real sim: 6-minute 4-AI headless match => `run_double` ok; run twice in two processes and diff the printed chains.

### 10.6 Process-level tests (`tools/py/net_two_process.py` + `net_harness.gd`)

| ID | Command shape | Pass criteria |
|---|---|---|
| P1 | host + 1 client on `127.0.0.1`, `--sim=fake`, 3000 ticks, script S0-extended, `--fixed-delay=2` | both print equal `chain/final/checks`; `desync=0`; exit 0; total < 30 s |
| P2 | host + 2 clients, `--fault=wifi` on all, 6000 ticks | same; `stalls` small |
| P3 | host + client + 2 AI, real sim, scripted commands | same |
| P4 | as P1 inside the Debian container (`tools/gd linux`) with the client on macOS (if reachable) or both inside | same |
| P5 | `kill -STOP` the client for 20 s with `auto_drop_ms = 8000` | host sees `DISCONNECTED` at ~6.5 s, auto-drops at ~11.5 s, completes the match; the stopped client exits non-zero after `SIGCONT` (expected) |

### 10.7 Visual tests (screenshots read by an agent; scenes owned by `ui`, data owned here)
V1 lobby with 8 slots (humans, AI, closed, open), team colours, ping column; V2 mismatch dialog text (all three failing layers); V3 stall overlay with two names and a countdown; V4 desync dialog; V5 replay controls (speed chips, timeline with CHECK markers, "verified through" indicator); V6 net overlay (F3-style) showing RTT, D, kbps, load; V7 LAN browser with one compatible and one incompatible (greyed, reason) entry. Net supplies deterministic fixtures via `NetLobbyState.create_default(...)` and a `stats()` stub.

### 10.8 Gates
`tools/gd check` clean for `src/net` and `tests/net`; `tools/gd test net` (all unit + scenario) < 120 s on a laptop; P1 on every commit; D3 on the three OSes before any `SimConfig.SIM_VERSION` change is accepted; a change that alters any golden in §10.2 must be a deliberate `PROTO_VERSION` bump.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Common Definition of Done (ARCHITECTURE Appendix B): `tools/gd check` clean; tests below pass via `tools/gd test net`; static typing everywhere; `##` docs on public API; no `print` (use `Log`); no `TODO` without `TODO(net)`; stubs `push_error("NOT IMPLEMENTED")`. Line counts include tests.

| ID | Task | Files owned | Depends on | Acceptance tests | ~Lines |
|---|---|---|---|---|---|
| **NET-1** | Wire layer: protocol constants/enums, `NetWriter`, `NetReader`, `NetCodec`, `NetLobbyCodec`, `NetBundle` | `net_protocol.gd net_writer.gd net_reader.gd net_codec.gd net_lobby_codec.gd net_bundle.gd`; `test_net_codec.gd test_net_protocol.gd` | none (optional core `Log`) | all §10.2 vectors byte-exact; fuzz 20 000 x 2 per decoder with zero engine errors; canonical re-encode property; size-limit rejects | 2000 |
| **NET-2** | Transports: clock, event, abstract transport, ENet, loopback hub/endpoint, fault profile/decorator, peer stats, rate limiter | `net_clock.gd net_transport_event.gd net_transport.gd net_transport_enet.gd net_loopback_hub.gd net_transport_loopback.gd net_fault_profile.gd net_transport_fault.gd net_peer_stats.gd net_rate_limiter.gd`; `test_net_transport_*.gd test_net_fault.gd` | NET-1 (tests only) | E1-E9 behaviours as tests (4 MB message, connect/disconnect codes, quiet port scan to 27617, dual-stack, 6 s connect timeout, no stats on dead peers); fault stats within tolerance; seeded reproducibility | 2200 |
| **NET-3** | Sim seam + lockstep runner: `NetSimAdapter`, `NetSimAdapterFake`, `NetSimAdapterWorld` (thin, NOT IMPLEMENTED stubs until sim API lands), `NetWorldJob`, `NetLockstep` | `net_sim_adapter.gd net_sim_adapter_fake.gd net_sim_adapter_world.gd net_world_job.gd net_lockstep.gd`; `test_net_lockstep_unit.gd` | NET-1; sim (XR-1,4,6) only for the real adapter | fill-up table §5.5.3; barrier/stall; caps; S0 goldens (§10.2); pause/speed; match-over final checksum | 1700 |
| **NET-4** | Host turn assembly: `NetTurnHost`, `NetDelayPolicy`, `NetAiRunner` | `net_turn_host.gd net_delay_policy.gd net_ai_runner.gd`; `test_net_turn_host.gd test_net_delay_policy.gd test_net_ai_runner.gd` | NET-1, NET-3; ai (XR-13) via stub callable | §5.5.5 table rows; barrier/16-cap; `T_RESIGN` first; policy cases (a)-(g); AI cadence `(E+pid)%period` incl. per-level periods, sanitising, governor (overdue thinkers run first next boundary; disabled when unpaced) | 2200 |
| **NET-5** | Lobby model + MatchConfig + options data | `net_lobby_state.gd net_player_slot.gd net_match_config.gd`; `game/data/net/lobby_options.json`; `test_net_match_config.gd` | NET-1; data (XR-11) list injected | §7.1 round trip, normalize rejects, RNG vectors, random-resolution reproducibility, canonical JSON stability | 1600 |
| **NET-6** | Lobby protocol | `net_lobby.gd net_peer_info.gd`; `test_net_lobby.gd` | NET-1, NET-2, NET-5 | permissions, swaps, join/reject matrix, countdown, kick/ban, StartError coverage, chat limits, snapshot ordering | 1500 |
| **NET-7** | LAN discovery | `net_discovery.gd net_discovery_entry.gd`; `test_net_discovery.gd` | NET-1 | golden datagram, expiry, candidates, breaker, unicast UDP loopback test | 800 |
| **NET-8** | Replays | `net_replay.gd net_replay_data.gd net_replay_recorder.gd net_replay_player.gd`; `test_net_replay.gd` | NET-1, NET-3 | §10.3 replay row; golden fixture round trip; seek equivalence | 1800 |
| **NET-9** | Desync + self-test | `net_desync.gd net_self_test.gd`; `test_net_desync.gd` (S13/S14 logic at unit level); `game/tests/net/desync_diff.gd selftest_main.gd` | NET-1, NET-3, NET-8 | classification table; package files + retention; `run_double` ok/fail detection | 1000 |
| **NET-10** | Session façade + launch | `net_session_options.gd net_session.gd net_launch.gd`; `test_net_session.gd test_net_security.gd` | NET-1..NET-9 | phase machine; launch success/abort matrix (S15-S19); LOCAL path parity (S12/D2); message matrix + violation scoring; `poll()` order | 2500 |
| **NET-11** | Scenario suite + process harness | `game/tests/net/test_net_scenarios.gd net_harness.gd make_replay_fixture.gd profiles.json scripts/*.json`; fixtures; `tools/py/net_two_process.py` (with tooling owner, XR-18) | NET-10 | S1-S19, P1-P3, D1-D2; fixtures generated | 2300 |
| **NET-12** (optional, phase 3) | Spectators + late-join catch-up | additions in session/turn host/codec/replay; `test_net_spectator.gd` | NET-10, NET-8 | S20 | 700 |
| **NET-13** | Real-sim integration | `NetSimAdapterWorld` filled in; real-sim scenario P3/D3/D4; perf capture; UX review with app/ui | sim, map, ai, app, ui delivered | D3 on 3 OSes; P3; measured budgets vs §9 | 600 |

Suggested order and parallelism: NET-1 first (everything imports it) -> {NET-2, NET-3, NET-5, NET-7, NET-8} in parallel -> {NET-4, NET-6, NET-9} in parallel -> NET-10 -> NET-11 (+ NET-12) -> NET-13. NET-1..NET-11 need **no** other domain to be finished: they run against `NetSimAdapterFake`, stub callables and the injected roster list.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| R1 | macOS 15+ **Local Network** permission and application firewall cannot be verified from CLI; denial makes discovery/connect fail silently | Ship `NSLocalNetworkUsageDescription` via `application/additional_plist_content` [XR-15]; one-time explainer before first socket; empty-browse hint; manual real-Mac checklist in NET-13 (allow, deny, revoke) |
| R2 | Broadcast filtered (VPN, guest Wi-Fi, client isolation) or wrong netmask guess | Candidate set + circuit breaker + Join-by-IP + recent hosts; documented that VPN overlays (Tailscale/ZeroTier) work through manual IP |
| R3 | Windows firewall profile "Public" blocks inbound by default; limited broadcast leaves only one NIC | UI text names "Private networks"; directed candidates cover secondary NICs; test on a real Windows machine in NET-13 (no Windows CI assumed) |
| R4 | Map/sim world build blocks the main thread for seconds | `NetWorldJob.step(budget)` slicing requested from app/map [XR-12][XR-14]; fallback `NetWorldJob.sync` + `TIMEOUTS_LOADING` (20-60 s) so ENet cannot time out during a synchronous build |
| R5 | A slow machine (`sim.step()` > 50 ms) slows everybody (barrier) | `load_pct` in PONG, `SLOW_CPU` label, host can drop; sim owns the per-tick budget; publish minimum spec |
| R6 | Cross-platform sim nondeterminism (floats, dictionary order) | Not net's bug, but net makes it *visible*: chain-vs-checksum classification, per-part localisation, golden replays on 3 OSes as a CI gate |
| R7 | Host is a single point of failure (no migration, no rejoin) | v1 accepted; every client keeps a replay; upgrade path = catch-up mechanism (§5.10) + re-admitting a pid into the barrier; decide after playtests |
| R8 | Reliable-only transport stalls on lossy Wi-Fi (Bad Wi-Fi profile: D=4, 0.9 % stalled) | Acceptable for LAN; protocol is dup/ooo tolerant so a redundant-unreliable mode can be added without a format change |
| R9 | `SimWorld` API names/behaviour differ from ASSUMPTION(sim) | All contact is in `NetSimAdapterWorld` (~100 lines); requests XR-1..XR-8 list exact needs |
| R10 | Background throttling (macOS App Nap, `low_processor_usage_mode`, minimized window) stalls the whole match | `OS.low_processor_usage_mode = false` in multiplayer; Info.plist `NSAppSleepDisabled` via additional plist content; poll every rendered frame [XR-14][XR-15] |
| R11 | Two instances on one PC fight over UDP 27614 | By design only the *browser* binds it; second browser reports `port_in_use`; dev flows use `127.0.0.1` join; hosting never binds it |
| R12 | Chat/name injection into rich text | `sanitize_*` strips control chars; UI must not enable BBCode for remote strings [XR-16] |
| R13 | JSON floats (`JSON.parse_string` returns floats) corrupting seeds/hashes | Ints <= 2^32 are exact in doubles; `normalize` coerces only finite integral values and rebuilds from a whitelist; hash is over transmitted bytes, never re-serialised |
| R14 | Replay invalidation on every sim change | `sim_version` gate + clear message; golden fixtures regenerated only with a `SimConfig.SIM_VERSION` bump (commit rule); replays are for viewing/testing, not archival |
| R15 | Pause abuse / grief | Budget 3 pauses x 120 s per player, host-configurable policy, only pauser/host can resume |
| R16 | Handicap semantics may be redefined by the economy owner | Contract fixed in §5.3.6 (economic only); any other meaning needs an amendment because it would touch the bible caps |
| R17 | Sim does not retain 64 checksum snapshots / parts | Then `PARTS_REQUEST` degrades to "parts unavailable" and desync still detected via total checksum; request in XR-4 |
| R18 | ENet quirks: events for removed peers, `get_packet_flags` after `get_packet`, stats on dead peers | Guard every access with `get_state()`; do not call `get_packet_flags`; covered by transport tests |
| Q1 | Should LAN default to D = 1 for snappier control? | No: ARCH default is 2; adaptive lowering below 2 only via advanced `min_input_delay=1`, and only when slack proves it |
| Q2 | Should the map seed be user-enterable ("map code")? | Yes: `host_set_map(..., map_seed, ...)`; UI shows it as 8 hex digits |
| Q3 | > 8 players / teams > 4 | No (ARCH: 8 players); team ids 1..4 plus "none" cover 8 players in up to 4 teams |
| Q4 | Save/load games | Out of scope; replays are the persistence mechanism; a future save = replay + periodic state snapshot (needs sim serialisation) |
| Q5 | Rejoin after a crash | v2 via catch-up (needs barrier re-admission rule); v1 offers AI takeover |
| Q6 | Where does the skirmish setup UI live? | `ui/`, over `NetLobbyState.create_skirmish` and `NetSession.local` |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**sim**
1. **XR-1 Tick API.** `SimWorld.step() -> void` runs exactly one tick of the ARCHITECTURE §6 pipeline; `SimWorld.tick: int` (0 after construction); commands submitted before `step()` are applied in step 1 of that tick. `SimWorld.clear_events() -> void` (headless runners).
2. **XR-2 Command envelope.** `SimWorld.submit_raw(pid: int, ints: PackedInt32Array) -> void` (or `SimCommand.from_ints(pid, ints)` + `submit`): malformed/unknown commands are ignored deterministically and counted, never an engine error. Command `type = ints[0]` in `0..255`, size `1..1024`, all int32. **Reserve types `240..255` for `net/`.** `SimCommand.to_ints()` must produce the same arrays the UI submits.
3. **XR-3 `T_RESIGN = 250`** `[250, reason]` (reason 0 surrender, 1 disconnect, 2 kicked, 3 timeout): eliminates the issuing pid at the executing tick (structures/units per sim rules, victory evaluation same tick), idempotent, legal from any state, all later commands from that pid ignored (combat's `CAUSE_RESIGN = 5` death cause is the natural sink for the eliminated player's entities). Optional sim event `PLAYER_RESIGNED(pid, reason)`. If sim-core prefers to allocate this command inside its own block, `NetProtocol.T_RESIGN` becomes an alias of that value — what matters is exactly one command with these semantics that both the UI and net can submit (the AI spec also lists an optional `RESIGN`; it should use the same one).
4. **XR-4 Checksums.** `SimWorld.checksum() -> int` (u32, full, on demand); snapshot at the end of every tick with `tick % 20 == 0` retained for **>= 64 snapshots**: `checksum_at(tick) -> int` (-1 if absent), `checksum_parts_at(tick) -> PackedInt32Array` (fixed length/order, total = f(parts), computed in the same pass), `CHECKSUM_PART_NAMES: PackedStringArray`.
5. **XR-5 State dump.** `SimWorld.dump_state() -> String`: deterministic text (players, RNG state, map mutable layers summary, entities sorted by id, one line each with all checksummed fields).
6. **XR-6 Match state.** `is_match_over() -> bool`, `match_result() -> Dictionary {winner_team:int (-1 none), reason:int}`, `is_player_active(pid:int) -> bool` (false when defeated/resigned).
7. **XR-7 Deterministic construction.** Building the same MatchConfig on any platform yields identical `checksum()` at tick 0 and identical `map_hash()` (`u32` over all static and initial layers).
8. **XR-8 `SimConfig`.** `TPS = 20`, `TURN_TICKS = 2`, `CHECKSUM_PERIOD = 20`, and `SIM_VERSION: int` (bumped on every intentional change of simulation behaviour or map generation).
9. **XR-9 Config consumption.** Sim provides `MatchConfig.from_dict(d: Dictionary) -> MatchConfig` (and `SimWorld.create(cfg)`) accepting exactly the §7.1 dictionary (`seed`, `map`, `rules`, `players[]`) and ignoring `net`, `versions`, `match_id`, `created_unix`. `rules` keys are the sim's `MatchRules` fields (`lobby_options.json` `rules_schema` must be kept in sync: current union `start_credits, unit_cap, superweapons, fog, shared_vision, veterancy, vision_stride, vision_budget`). `players[].team` is the final team id, `color` a palette index (view only), `start` an index into the map's start-position list, `players[].ai = {level, style, flags}` (the AI spec's `difficulty`/`seed_salt` are not needed: net derives the thinker seed). `handicap` is a percent 50..200 (step 5): the sim converts it to its internal income multiplier (`income_bp = handicap * 100`), scales **starting credits** (`start_credits * handicap / 100`, truncating) and **harvest/salvage income** with it, stores it in player state and checksums it; it must not touch costs, build times, health, damage or reload (bible caps).
10. **XR-10 No debug commands in multiplayer.** Cheat/debug command types are rejected unless the config explicitly enables a dev flag (never set by the lobby).

**data** — 11. **XR-11** Already published by the data spec and adopted here: `GameData.data_hash: int` (u32), `GameData.handshake(include_files: bool = false) -> Dictionary` (`{format, hash, tables{16}, files?}`), `static GameData.diff_handshake(local, remote) -> PackedStringArray`, `GameData.rosters[i].id` (32 ids, sorted). App wires them into `NetSessionOptions.data_hash/data_handshake/data_diff/roster_ids`. Net additionally needs `GameData.FORMAT_VERSION` and `table_hashes["ids"]` (both inside `handshake()`), which it stores in `MatchConfig.versions`.

**map** — 12. **XR-12** `MapGenerator.validate_params(family:int, size:int, layout_players:int) -> String` ("" = ok); start-position indices ordered around the map so adjacent indices are adjacent positions (teammates end up neighbours); `MapData.content_hash() -> int`; a time-sliced generation entry point (`begin(config)`, `step(budget_us) -> bool`, `progress_pct()`) usable by `NetWorldJob`.

**ai** — 13. **XR-13** A factory usable as `ai_factory(pid, level, style, rng_seed) -> Callable` whose callable is `(world, out: Array) -> void` appending `PackedInt32Array` commands; per-think budget <= 3 ms typical; level/style enumerations and display names (`level_names()`, `style_names()`); private seeded RNG (never `SimRng`); must read the world only via the public query API. Already published by the AI spec and adopted: `AiFactory.make(pid, level, style, seed) -> Callable`, `level_count()`, `style_count()`, `level_handicap_pct(level)` (Brutal = 120, wired to `NetSessionOptions.ai_default_handicap`), thinker seed = `mix32(match_seed ^ ((pid+1) * 0x9E3779B9))`. The AI spec's items 16-17 (per-tick `AiManager.update`, `attach_midgame`, `ai_fog_cheat` toggle) are superseded by the injected-thinker contract (§5.6) and `players[].ai.flags` bit0.

**app** — 14. **XR-14** Autoload `AppNet`: builds `NetSessionOptions` from settings (§7.3) and `GameData`, owns the current `NetSession`, calls `session.poll()` **every rendered frame before view/ui update** (not from `_physics_process`), sets `OS.low_processor_usage_mode = false` in multiplayer, calls `NetReplay.recover_orphans()` once at boot, provides `AppMatch.begin_build(config) -> NetWorldJob` (sliceable) and `AppMatch.make_ai_thinker(...)`. Settings keys of §7.3. Set `application/config/version` in `project.godot` (net reads it as `game_version`).

**build / app** — 15. **XR-15** `export_presets.cfg` macOS: `application/additional_plist_content` containing `<key>NSLocalNetworkUsageDescription</key><string>Meridian Fracture uses your local network to find and join LAN games.</string>` and `<key>NSAppSleepDisabled</key><true/>`; keep `codesign/entitlements/app_sandbox/enabled` off (if ever on: `network_client` and `network_server` = true). Verify the plist fragment format against a real export (the 4.7.2 docs here list the option but carry no description). All platforms: make sure `res://data/**/*.json` (lobby options, bible, balance) is packed into the PCK — Godot exports non-resource files only through `include_filter` (e.g. `data/*.json, data/*/*.json`). Windows/Linux: nothing else to export; document ports in the installer/readme.

**ui** — 16. **XR-16** Screens: LAN browser (server list incl. greyed incompatible entries with reason), join-by-IP (+ recent hosts), lobby (8 slots, roster picker grouped by faction with the 32 rosters, team/colour/start/handicap, AI level/style, map/rules/speed panels, ready, chat, kick/ban), skirmish setup over `NetLobbyState.create_skirmish`, loading screen (`load_progress`), in-game overlays (stall "Waiting for ...", pause banner, host stall prompt Wait/Drop/AI, net overlay from `stats()`), desync dialog, replay browser/player controls (speeds, seek bar with CHECK markers, verify banner), surrender button -> `NetSession.surrender()`. Use the `net.*` string keys of §5.13 in `data/text`. **Render remote strings (names, chat) as plain text, BBCode disabled.** Team-colour palette indexed 0..11 consistent with `lobby_options.json`. First-run network explainer before opening sockets.

**view / audio** — 17. **XR-17** Use `NetSession.tick_alpha()` for interpolation; drain `world.events` after every `poll()`; drop world references on `phase_changed(IDLE)`/`match_ended`; audio cues for `countdown_changed`, `pause_changed`, `player_status_changed`.

**qa / tooling** — 18. **XR-18** `tools/py/net_two_process.py` (spawn host + N clients through `tools/gd run … -- args`, collect `NETTEST` lines, compare, exit code); `tools/gd run` must pass user args after `--` and propagate exit codes; test runner support for `expect_errors` (present); Debian-container variant of P1; storage for `tests/fixtures/net/replays` and a CI job for D3 on macOS, Linux and Windows.

**core** — 19. **XR-19** `Log` API (`Log.debug/info/warn/error(tag: String, msg: String)`) with an injectable sink for tests.

**architecture** — 20. **XR-20 Amendments to `docs/ARCHITECTURE.md`** (record in `docs/AMENDMENTS.md`): (a) §9 "Godot `ENetMultiplayerPeer`" -> "`ENetConnection`/`ENetPacketPeer` (same ENet library), reliable ordered channels; `ENetMultiplayerPeer`/RPC not used"; (b) §9/§6 clarify that clients execute *host-relayed bundles* and that inputs are gap-free per player (fill-up rule) with adaptive `D >= 2` (local `D = 1`); (c) §9 checksum exchange also carries the net `input_chain` for NET-vs-SIM classification; (d) designate this document's §7.1 as the `MatchConfig` schema of record (ARCH §9/§12 mention `MatchConfig`/`MatchRules` without a definition); (e) §11 test naming: `func test_*(t: TestCtx)` (the runner's convention) supersedes `func run(t)`.
