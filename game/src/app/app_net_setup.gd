class_name AppNetSetup
extends RefCounted
## Pure builders behind `AppNet` (ui.md 5.3, net.md 5.9): the `NetSessionOptions` of a session and the completion of a UI-side
## match config (lobby / `--autostart` shape: seed, map, rules, players) into the strict net.md 7.1 `MatchConfig` that
## `NetSession.local_from_config` validates. Skirmish and LAN share the session; only the way the config is made differs.

## Options for a session (LOCAL today; the LAN roles add transport and discovery on top of the same object).
## `p`: player_name, with_view, unpaced, discard_events, max_ticks_per_poll, ai (AppAiHook), job_sink (Callable(AppMatchJob) told about
## every world job, the loading screen and the view hand-over read it), events (bool: the world records sim events for the view).
static func make_options(data: GameData, p: Dictionary = {}) -> NetSessionOptions:
	var o: NetSessionOptions = NetSessionOptions.from_game_data(data)
	o.player_name = NetProtocol.sanitize_name(str(p.get("player_name", "Commander")))
	if o.player_name == "":
		o.player_name = "Commander"
	o.color_count = 12
	o.ai_level_count = AiFactory.level_count()
	o.ai_style_count = AiFactory.style_count()
	o.discovery_enabled = false
	o.countdown_s = 0
	o.allow_spectators = false
	o.record_replay = true
	o.record_command_log = true
	o.auto_clear_events = bool(p.get("discard_events", false))
	var unpaced: bool = bool(p.get("unpaced", false))
	o.speed_pct_override = 0 if unpaced else -1
	o.max_ticks_per_poll = int(p.get("max_ticks_per_poll", 32 if unpaced else NetProtocol.MAX_TICKS_PER_POLL))
	o.map_validator = AppMatch.validate_map
	var ai: AppAiHook = p.get("ai", null) as AppAiHook
	if ai != null:
		o.ai_factory = ai.make
		o.ai_release = ai.release
		o.ai_think_period = AppAiHook.think_period_turns
		o.ai_default_handicap = AiFactory.level_handicap_pct
	var with_view: bool = bool(p.get("with_view", false))
	var events: bool = bool(p.get("events", true))
	var sink: Callable = p.get("job_sink", Callable()) as Callable
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var job: AppMatchJob = AppMatch.begin_build(cfg, with_view)
		if sink.is_valid():
			sink.call(job)
		return AppNetWorldJob.new(job, events)
	return o


## The start-position layout net accepts (`NetMatchConfig.LAYOUTS`: 2, 4, 6, 8) for `players` slots: the map generator also knows a
## 3-slot layout, which net does not, so three players play on the 4-slot layout.
static func net_layout(players: int) -> int:
	for l: int in NetMatchConfig.LAYOUTS:
		if l >= players:
			return l
	return NetMatchConfig.LAYOUTS[NetMatchConfig.LAYOUTS.size() - 1]


## Completes a UI-shape config (`AppMatch.simple_config`, `UiLobbyState.to_config`) into the net.md 7.1 dictionary: format, match
## id, versions, the full rules schema, the `net` block, and per player `peer`. Rules of the schema with a different name are
## dropped, the others are clamped. The first human is the local peer (1); further humans cannot exist in a LOCAL match and are
## played by an AI of `AppAiHook.takeover_level`. Team ids outside 1..4 become the private team `8 + pid`. Returns a raw
## dictionary; `NetSession.local_from_config` normalizes and validates it.
static func complete_config(cfg: Dictionary, opts: NetSessionOptions, unix_time: int = -1) -> Dictionary:
	var seed32: int = int(cfg.get("seed", 0)) & 0xFFFFFFFF
	var hs: Dictionary = opts.data_handshake.call(false) as Dictionary if opts.data_handshake.is_valid() else {}
	var tables: Dictionary = hs.get("tables", {}) as Dictionary
	var now: int = unix_time if unix_time >= 0 else int(Time.get_unix_time_from_system())
	var src_map: Dictionary = cfg.get("map", {}) as Dictionary
	var layout: int = net_layout(maxi(int(src_map.get("layout_players", 2)), (cfg.get("players", []) as Array).size()))
	var mission_id: String = str(cfg.get("mission", ""))
	var map: Dictionary = {"family": int(src_map.get("family", 0)), "size": maxi(int(src_map.get("size", 96)), MapGenParams.min_size(layout)),
		"seed": int(src_map.get("seed", 0)) & 0xFFFFFFFF, "layout_players": layout,
		"params": (src_map.get("params", {}) as Dictionary).duplicate() if mission_id != "" and src_map.get("params", {}) is Dictionary else {}}
	var src_rules: Dictionary = cfg.get("rules", {}) as Dictionary
	var rules: Dictionary = {}
	for e: Variant in NetMatchConfig.rules_schema():
		var row: Dictionary = e as Dictionary
		var key: String = str(row["key"])
		var v: int = int(src_rules.get(key, row["default"]))
		if str(row["type"]) == "bool":
			rules[key] = bool(src_rules.get(key, int(row["default"]) != 0))
		else:
			rules[key] = clampi(v, int(row["min"]), int(row["max"]))
	var src_net: Dictionary = cfg.get("net", {}) as Dictionary
	var speed: int = int(src_net.get("speed_pct", 100))
	if not NetProtocol.SPEED_PCT.has(speed):
		speed = 100
	var net: Dictionary = {"turn_ticks": NetProtocol.TURN_TICKS, "checksum_period": NetProtocol.CHECKSUM_PERIOD_TICKS,
		"input_delay": clampi(opts.fixed_input_delay_turns if opts.fixed_input_delay_turns > 0 else NetProtocol.D_MIN_LOCAL, 1, NetProtocol.D_MAX),
		"speed_pct": speed, "pause_policy": int(src_net.get("pause_policy", NetProtocol.PausePolicy.HOST_ONLY)),
		"on_disconnect": int(src_net.get("on_disconnect", NetProtocol.OnDisconnect.AI)), "auto_drop_ms": 0, "allow_spectators": false}
	var players: Array = []
	var human_seen: bool = false
	for pv: Variant in cfg.get("players", []) as Array:
		var d: Dictionary = pv as Dictionary
		var pid: int = int(d.get("pid", players.size()))
		var human: bool = str(d.get("kind", "human")) == "human"
		var as_ai: bool = not human or human_seen
		if human and not human_seen:
			human_seen = true
		var team: int = int(d.get("team", 8 + pid))
		var nm: String = NetProtocol.sanitize_name(str(d.get("name", "")))
		var p: Dictionary = {"pid": pid, "kind": "ai" if as_ai else "human", "peer": 0 if as_ai else 1,
			"name": nm if nm != "" else "Player %d" % (pid + 1), "roster": str(d.get("roster", "")),
			"team": team if (team >= 1 and team <= 4) else 8 + pid, "color": int(d.get("color", pid)), "start": int(d.get("start", pid)),
			"handicap": clampi(int(d.get("handicap", 100)) / 5 * 5, 50, 200)}
		if as_ai:
			var ai: Dictionary = d.get("ai", {}) as Dictionary
			p["ai"] = {"level": clampi(int(ai.get("level", AppAiHook.takeover_level)), 0, AiFactory.level_count() - 1),
				"style": clampi(int(ai.get("style", 0)), 0, AiFactory.style_count() - 1), "flags": clampi(int(ai.get("flags", 0)), 0, 255)}
		players.append(p)
	var full: Dictionary = {
		"format": NetMatchConfig.FORMAT,
		"match_id": "%08x%08x" % [NetProtocol.mix32(seed32 ^ 0x1D872B41), NetProtocol.mix32((now & 0xFFFFFFFF) ^ seed32 ^ 0x7F4A7C15)],
		"created_unix": maxi(now, 0),
		"versions": {"game": NetProtocol.truncate_utf8(opts.game_version, 24), "proto": NetProtocol.PROTO_VERSION, "sim": opts.sim_version,
			"data_hash": opts.data_hash & 0xFFFFFFFF, "data_format": int(hs.get("format", 0)), "data_ids": int(tables.get("ids", 0)) & 0xFFFFFFFF},
		"seed": seed32, "map": map, "rules": rules, "net": net, "players": players,
	}
	if mission_id != "":
		full["mission"] = mission_id  # MIS1: a scripted mission (SimMatchConfig.mission_id)
	return full
