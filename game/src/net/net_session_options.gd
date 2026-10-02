class_name NetSessionOptions
extends RefCounted
## Everything a NetSession needs from the outside (docs/spec/net.md 3.1). Net never imports ai/app/ui: the game
## data handshake, the roster list, the AI factory and the world builder all arrive here as values or Callables.
## Build one with `NetSessionOptions.from_game_data(data)` (fills the version, hash, handshake and roster fields) and
## then set `world_builder` (and `ai_factory`).

# ---- identity / versions ----------------------------------------------------------------------------------
## Sanitised by NetProtocol.sanitize_name.
var player_name: String = "Commander"
## Informational (ProjectSettings application/config/version); only proto / sim_version / data_hash gate joining.
var game_version: String = ""
## SimConfig.SIM_VERSION.
var sim_version: int = 0
## GameData.data_hash() (u32); must equal data_handshake.call(false)["hash"].
var data_hash: int = 0
## (include_files: bool) -> Dictionary = GameData.handshake: {format, hash, tables:{String->int}, files?:{String->int}}.
var data_handshake: Callable = Callable()
## (local: Dictionary, remote: Dictionary) -> PackedStringArray = GameData.diff_handshake.
var data_diff: Callable = Callable()
## Sorted, exactly the 32 playable roster ids.
var roster_ids: PackedStringArray = PackedStringArray()
var color_count: int = 12
## AI levels 0..n-1.
var ai_level_count: int = 4
var ai_style_count: int = 4
## (level: int) -> int, optional: lobby default handicap of an AI slot (Brutal = 120).
var ai_default_handicap: Callable = Callable()
## (level: int) -> int turns between thinks, optional (default NetProtocol.AI_THINK_PERIOD_TURNS).
var ai_think_period: Callable = Callable()
## (pid: int) -> void, optional: called by NetAiRunner.remove_ai and at match end.
var ai_release: Callable = Callable()

# ---- behaviour --------------------------------------------------------------------------------------------
var port: int = NetProtocol.DEFAULT_PORT
## "" = open. Casual barrier only.
var password: String = ""
var allow_spectators: bool = true
## Host has no local slot and no local input (headless host / tests).
var dedicated: bool = false
var discovery_enabled: bool = true
## UDP port of the LAN discovery datagrams (tests use another port).
var discovery_port: int = NetProtocol.DISCOVERY_PORT
## Non-empty: the discovery announcer sends only to these targets (tests / CI without broadcast, e.g. ["127.0.0.1"]).
var discovery_targets: PackedStringArray = PackedStringArray()
## Accept announce datagrams from non-private source IPs (settings net/allow_public_discovery).
var allow_public_discovery: bool = false
var min_input_delay_turns: int = NetProtocol.D_MIN_LAN
## > 0 disables adaptation (golden replays, deterministic tests).
var fixed_input_delay_turns: int = 0
var auto_clear_events: bool = false
## Record every match (all roles) into a NetReplayRecorder (memory mirror; written to `replay_dir` when that is set).
var record_replay: bool = true
## Record the in-match chat lines as replay events.
var record_chat: bool = true
## How many autosave_N.mfreplay files are kept (NetReplay.finalize_autosave).
var replay_autosave_count: int = 3
## Folder of the replay files ("" = memory only, nothing is written). from_game_data sets NetReplay.default_dir().
var replay_dir: String = ""
## Size cap of all autosaves together (0 = NetReplay.AUTOSAVE_MAX_BYTES).
var replay_max_bytes: int = 0
## Record every executed command into a SimCommandLog (NetSession.command_log()).
var record_command_log: bool = true
## Dev / testing: start with a single active player.
var allow_solo: bool = false
var countdown_s: int = NetProtocol.COUNTDOWN_S
## -1 = use MatchConfig.net.speed_pct; 0 = UNPACED (ignore the wall-clock accumulator, run up to max_ticks_per_poll
## ticks per poll, barrier still enforced); 50..200 = force.
var speed_pct_override: int = -1
var max_ticks_per_poll: int = NetProtocol.MAX_TICKS_PER_POLL
## Where desync packages are written ("user://desync" by default; tests use their own directory).
var desync_dir: String = "user://desync"
## Package retention (newest N packages are kept).
var desync_keep: int = 10
## Random per process (ban key together with the IP). 0 = generated.
var client_nonce: int = 0
## Client with a password: the session id of the game when known from discovery (0 = learn it from BAD_PASSWORD).
var join_session_id: int = 0
## Client: join as a spectator (lobby only in this build; spectators are removed when a match launches).
var join_as_spectator: bool = false
## Tests: fixed match seed / unix time for the launch config (-1 = random / system time).
var match_seed_override: int = -1
var unix_time_override: int = -1

# ---- injected dependencies --------------------------------------------------------------------------------
## null -> NetClock.real().
var clock: NetClock = null
## () -> NetTransport; invalid -> NetTransportEnet. A client that must reconnect (data diff / password retry) calls
## the factory again, so it has to return a FRESH transport each time.
var transport_factory: Callable = Callable()
## (config: Dictionary) -> NetWorldJob.
var world_builder: Callable = Callable()
## (pid: int, level: int, style: int, rng_seed: int) -> Callable(world, out: Array).
var ai_factory: Callable = Callable()
## (family: int, size: int, layout_players: int) -> String ("" = valid).
var map_validator: Callable = Callable()
## (level: int, text: String) -> void; invalid -> core Log.
var log_sink: Callable = Callable()


## Options filled from a loaded GameData: sim/data versions, handshake + diff callables, the sorted roster list and
## the application version. Callers still set world_builder / ai_factory / map_validator / transport_factory.
static func from_game_data(data: GameData) -> NetSessionOptions:
	var o: NetSessionOptions = NetSessionOptions.new()
	o.sim_version = SimConfig.SIM_VERSION
	o.data_hash = data.data_hash()
	o.data_handshake = data.handshake
	o.data_diff = GameData.diff_handshake
	var ids: PackedStringArray = PackedStringArray()
	for r: DefRoster in data.rosters:
		ids.append(r.id)
	ids.sort()
	o.roster_ids = ids
	o.game_version = str(ProjectSettings.get_setting("application/config/version", ""))
	o.replay_dir = NetReplay.default_dir()
	return o


## A field-by-field copy (Callables and the clock are shared). Sessions never mutate the caller's options: they
## duplicate them first.
func duplicate_options() -> NetSessionOptions:
	var c: NetSessionOptions = NetSessionOptions.new()
	for p: Dictionary in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			c.set(str(p["name"]), get(str(p["name"])))
	return c
