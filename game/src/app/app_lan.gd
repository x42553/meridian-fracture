class_name AppLan
extends RefCounted
## LAN glue of the app (ui.md 5.15, net.md 3.0 / 5.9): hosts a game (`host_lan`), joins one (`join_lan`), builds the LAN browser's
## discovery object and keeps the small persistent helpers of the LAN screens (recent hosts, the one-time firewall explainer). A
## LAN session is the SAME object as a skirmish session (`NetSession`, `AppMatchContext`, `AppNet` polling, `AppMatch.begin_build` as
## the world builder); only the role and the transport differ. This class creates the context, hands it to `AppNet`, registers it as
## `AppState.match_ctx` and binds the session to the screen flow:
##   LAN_LOBBY --phase LOADING--> LOADING --match_started--> IN_MATCH,
##   launch_aborted (LOADING) -> LAN_LOBBY with the reason, kicked / host left in a lobby or loading -> LAN_BROWSER / MAIN_MENU.
## Presentation code only: nothing here touches the sim; the lobby is edited through `NetLobby` (see `UiLobbyNet`).

const HELP_KEY: StringName = &"net/help_shown"
const RECENT_KEY: StringName = &"net/recent_hosts"
const LAST_ADDRESS_KEY: StringName = &"net/last_address"
const TITLE: String = "LAN Game"

## Every session started by this class keeps its flow binding alive through its own signals; nothing else is retained.


## Hosts a game and returns the new `AppMatchContext` (session in the LOBBY phase), or null when no port could be opened (the reason
## is `NetSession.last_create_error`). `p` keys, all optional: `lobby_name`, `password`, `port`, `advertise` (bool, default the
## setting `net/discovery`), `spectators` (bool, default true), `player_name`, `with_view`, `countdown_s`, `discovery_port`,
## `discovery_targets` (PackedStringArray), `match_seed` (tests), `bind` (bool, default true: wire the flow), `title`.
static func host_lan(p: Dictionary = {}) -> AppMatchContext:
	var made: Dictionary = _make(p)
	if made.is_empty():
		return null
	var ctx: AppMatchContext = made["ctx"] as AppMatchContext
	var o: NetSessionOptions = made["opts"] as NetSessionOptions
	o.port = int(p.get("port", _setting_int(&"net/port", NetProtocol.DEFAULT_PORT)))
	o.password = str(p.get("password", ""))
	o.allow_spectators = bool(p.get("spectators", true))
	o.discovery_enabled = bool(p.get("advertise", _setting_bool(&"net/discovery", true)))
	o.allow_public_discovery = _setting_bool(&"net/allow_public_discovery", false)
	if p.has("discovery_port"):
		o.discovery_port = int(p["discovery_port"])
	if p.has("discovery_targets"):
		o.discovery_targets = p["discovery_targets"] as PackedStringArray
	if int(p.get("match_seed", -1)) >= 0:
		o.match_seed_override = int(p["match_seed"])  # tests: the same lobby then plays the same match run after run
		o.unix_time_override = 1_790_000_000
	var lobby_name: String = str(p.get("lobby_name", ""))
	var session: NetSession = NetSession.host(o, lobby_name)
	if session == null:
		Log.warn("app", "host_lan: " + NetSession.last_create_error)
		return null
	_adopt(ctx, session, p)
	return ctx


## Joins the game at `address` (an IP, a host name or "address:port"; `port` applies when the address carries none). Returns the new
## context (session CONNECTING) or null when the address is unusable (`NetSession.last_create_error`). The result arrives through the
## session's `phase_changed` (LOBBY), `join_rejected` and `net_error` signals. `p`: `player_name`, `with_view`, `spectator` (join as
## spectator), `discovery_port`, `bind`, `title`.
static func join_lan(address: String, port: int = NetProtocol.DEFAULT_PORT, password: String = "", p: Dictionary = {}) -> AppMatchContext:
	var made: Dictionary = _make(p)
	if made.is_empty():
		return null
	var ctx: AppMatchContext = made["ctx"] as AppMatchContext
	var o: NetSessionOptions = made["opts"] as NetSessionOptions
	o.password = password
	o.join_as_spectator = bool(p.get("spectator", false))
	o.allow_public_discovery = _setting_bool(&"net/allow_public_discovery", false)
	var session: NetSession = NetSession.join(o, address, port)
	if session == null:
		Log.warn("app", "join_lan: " + NetSession.last_create_error)
		return null
	_adopt(ctx, session, p)
	return ctx


## The discovery object of the LAN browser (call `start_browse()`, `poll()` each frame, read `entries()`); null without game data.
static func make_browser(p: Dictionary = {}) -> NetDiscovery:
	var data: GameData = _data()
	if data == null:
		return null
	var o: NetSessionOptions = AppNetSetup.make_options(data, {"player_name": _player_name(p)})
	o.allow_public_discovery = _setting_bool(&"net/allow_public_discovery", false)
	if p.has("discovery_port"):
		o.discovery_port = int(p["discovery_port"])
	return NetSession.create_browser(o)


## Leaves the running LAN session (client: LEAVE; host: the game closes for everybody) and clears `AppState.match_ctx`.
static func leave() -> void:
	var net_node: Node = _autoload("AppNet")
	if net_node != null:
		var c: AppMatchContext = net_node.get("ctx") as AppMatchContext
		if c != null and c.session != null and c.session.role != NetSession.Role.LOCAL:
			c.session.leave()
		net_node.call("end_session")
		return
	var state: Node = _autoload("AppState")
	if state != null and state.get("match_ctx") is AppMatchContext:
		var mc: AppMatchContext = state.get("match_ctx") as AppMatchContext
		if mc.session != null:
			mc.session.leave()
		mc.dispose()
		state.set("match_ctx", null)


## The session of the current context (null when none). `AppState.match_ctx` first, then the context `AppNet` still polls (after a
## match the LAN context is detached from `AppState` so that leaving the end screen does not dispose it, see `return_to_lobby`).
static func current_session() -> NetSession:
	var c: AppMatchContext = _current_ctx()
	if c == null or c.session == null or c.disposed:
		return null
	return c.session


## True when the running context is a LAN game (host or client), e.g. to label the end screen's button "Back to the lobby".
static func is_lan_match() -> bool:
	var s: NetSession = current_session()
	return s != null and s.role != NetSession.Role.LOCAL


## LAN, after a match: makes the lobby available again and returns true when the caller should navigate to `lobby {lan: true}`.
## The host sends everybody back to the lobby (`NetSession.host_return_to_lobby`); a client is back once the host did that (its
## session is in the LOBBY phase again; before that this returns false and the end screen keeps waiting). The context is detached
## from `AppState.match_ctx` because `UiScreenEnd.exit` disposes that one; `AppNet` keeps polling it and the lobby screen finds it by
## `current_session()`.
static func return_to_lobby() -> bool:
	var c: AppMatchContext = _current_ctx()
	if c == null or c.session == null or c.disposed or c.session.role == NetSession.Role.LOCAL:
		return false
	var s: NetSession = c.session
	if s.role == NetSession.Role.HOST and (s.phase == NetSession.Phase.ENDED or s.phase == NetSession.Phase.DESYNCED):
		s.host_return_to_lobby()
	if s.phase != NetSession.Phase.LOBBY:
		return false
	_detach_from_state(c)
	return true


# ---------------------------------------------------------------- persistent helpers

## Whether the one-time firewall explainer was shown (`net/help_shown`, ui.md 5.15).
static func help_shown() -> bool:
	return _setting_bool(HELP_KEY, false)


static func mark_help_shown() -> void:
	var st: Node = _autoload("AppSettings")
	if st != null:
		st.call("set_value", HELP_KEY, true)


## Recent direct-connect targets, newest first (at most 8, `net/recent_hosts`).
static func recent_hosts() -> PackedStringArray:
	var st: Node = _autoload("AppSettings")
	if st != null and st.get("store") is AppSettingsStore:
		var v: Variant = (st.get("store") as AppSettingsStore).get_value(RECENT_KEY)
		if v is PackedStringArray:
			return v as PackedStringArray
	return PackedStringArray()


## Puts `target` ("address:port") first in the recent list (deduplicated, capped at 8) and remembers it as the last address.
static func remember_host(target: String) -> void:
	var st: Node = _autoload("AppSettings")
	if st == null or target.strip_edges().is_empty():
		return
	st.call("set_value", RECENT_KEY, merge_recent(recent_hosts(), target))
	st.call("set_value", LAST_ADDRESS_KEY, target)


## Pure: `list` with `target` moved / added to the front, at most `limit` entries.
static func merge_recent(list: PackedStringArray, target: String, limit: int = 8) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var t: String = target.strip_edges()
	if t.is_empty():
		return list
	out.append(t)
	for e: String in list:
		if e != t and out.size() < limit:
			out.append(e)
	return out


## "windows" | "macos" | "linux": the firewall help text to show (`OS.get_name()`; cosmetic only, net.md 5.13).
static func platform_key(os_name: String = "") -> String:
	var n: String = (os_name if os_name != "" else OS.get_name()).to_lower()
	if n.begins_with("windows"):
		return "windows"
	if n == "macos" or n == "ios":
		return "macos"
	return "linux"


## The English firewall / permission text of the platform (net.md 5.13) followed by the ports line.
static func firewall_text(platform: String, port: int = NetProtocol.DEFAULT_PORT) -> Dictionary:
	var body: String
	var title: String
	match platform:
		"windows":
			title = "Windows Firewall"
			body = "Windows may ask whether to allow Meridian Fracture through the firewall. Choose Private networks and click Allow.\n\nMissed it? Windows Security > Firewall & network protection > Allow an app through firewall > Meridian Fracture > tick Private."
		"macos":
			title = "macOS Local Network permission"
			body = "macOS may ask whether Meridian Fracture can find and connect to devices on your local network. Choose Allow.\n\nMissed it? System Settings > Privacy & Security > Local Network > enable Meridian Fracture."
		_:
			title = "Linux firewall"
			body = "If you use ufw: sudo ufw allow %d:%d/udp\n\nWith nftables or iptables allow inbound UDP %d-%d on your LAN interface." % [
				NetProtocol.DISCOVERY_PORT, NetProtocol.DEFAULT_PORT + NetProtocol.PORT_SCAN_COUNT - 1, NetProtocol.DISCOVERY_PORT, NetProtocol.DEFAULT_PORT + NetProtocol.PORT_SCAN_COUNT - 1]
	var ports: String = "Ports used: UDP %d (game; %d-%d if busy) and UDP %d (LAN discovery). Joining by IP only needs the host's game port." % [
		port, NetProtocol.DEFAULT_PORT, NetProtocol.DEFAULT_PORT + NetProtocol.PORT_SCAN_COUNT - 1, NetProtocol.DISCOVERY_PORT]
	return {"title": title, "body": body, "ports": ports}


# ---------------------------------------------------------------- context construction

## Context + options shared by host and join. Empty when the game data is missing.
static func _make(p: Dictionary) -> Dictionary:
	var data: GameData = _data()
	if data == null:
		Log.error("app", "LAN: the game data could not be loaded")
		return {}
	var headless: bool = DisplayServer.get_name() == "headless"
	var with_view: bool = bool(p.get("with_view", not headless))
	var ctx: AppMatchContext = AppMatchContext.new()
	ctx.ai = AppAiHook.new()
	var wctx: WeakRef = weakref(ctx)  # weak: the context owns the session, whose options hold the callables below
	var o: NetSessionOptions = AppNetSetup.make_options(data, {"player_name": _player_name(p), "with_view": with_view, "unpaced": false,
		"discard_events": not with_view, "events": with_view, "ai": ctx.ai,
		"job_sink": func(job: AppMatchJob) -> void:
			var c: AppMatchContext = wctx.get_ref() as AppMatchContext
			if c != null:
				c.job = job})
	o.countdown_s = int(p.get("countdown_s", NetProtocol.COUNTDOWN_S))
	o.allow_spectators = true
	o.discovery_enabled = false
	o.record_chat = _setting_bool(&"net/record_chat", true)
	if p.has("fixed_delay"):
		o.fixed_input_delay_turns = int(p["fixed_delay"])
	var inner: Callable = o.world_builder
	o.world_builder = func(cfg: Dictionary) -> NetWorldJob:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null:
			# the loading screen reads the config before match_started; the seat of this peer is known from the config itself
			c.config = cfg.duplicate(true)
			if c.session != null:
				c.local_pid = NetMatchConfig.pid_of_peer(cfg, c.session.local_peer_id)
		return inner.call(cfg) as NetWorldJob
	ctx.data = data
	ctx.title = str(p.get("title", TITLE))
	return {"ctx": ctx, "opts": o}


## Registers the session with its context: ports at `match_started`, result capture, `AppNet` polling, `AppState.match_ctx`, flow.
static func _adopt(ctx: AppMatchContext, session: NetSession, p: Dictionary) -> void:
	ctx.session = session
	var wctx: WeakRef = weakref(ctx)
	session.match_started.connect(func() -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c == null or c.disposed:
			return
		c.config = c.session.config()
		c.local_pid = c.session.local_pid
		c.build_ports(c.job.take_stage() if c.job != null else null))
	session.match_ended.connect(func(result: Dictionary) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null:
			c.last_end = result)
	var net_node: Node = _autoload("AppNet")
	if net_node != null:
		net_node.call("attach", ctx)
	else:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			ctx.driver = AppSessionDriver.new(ctx)
			tree.root.add_child(ctx.driver)
	var state: Node = _autoload("AppState")
	if state != null:
		var old: Variant = state.get("match_ctx")
		if old is AppMatchContext and old != ctx:
			(old as AppMatchContext).dispose()
		state.set("match_ctx", ctx)
		if bool(p.get("bind", true)):
			_bind_flow(ctx, state)


## Session -> screen flow for the lobby, loading and in-match phases of a LAN context.
static func _bind_flow(ctx: AppMatchContext, state: Node) -> void:
	var s: NetSession = ctx.session
	var wctx: WeakRef = weakref(ctx)
	s.phase_changed.connect(func(phase: int, _previous: int) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c == null or c.disposed:
			return
		var mode: int = _mode(state)
		if phase == NetSession.Phase.LOADING and mode == AppFlow.Mode.LAN_LOBBY:
			state.set("match_ctx", c)  # a second match of the same session: the loading screen reads it from here
			state.call("go", AppFlow.Mode.LOADING, {"kind": "match", "title": c.title})
		elif phase == NetSession.Phase.LOBBY and mode == AppFlow.Mode.END_SCREEN:
			# the host sent everybody back to the lobby after the match: a client follows without a button
			_detach_from_state(c)
			state.call("go", AppFlow.Mode.LAN_LOBBY, {"lan": true, "session": c.session}))
	s.match_started.connect(func() -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null and not c.disposed and _mode(state) == AppFlow.Mode.LOADING:
			state.call("go", AppFlow.Mode.IN_MATCH, {"ctx": c}))
	s.launch_aborted.connect(func(reason: int, detail: String) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null and not c.disposed and _mode(state) == AppFlow.Mode.LOADING:
			state.call("go", AppFlow.Mode.LAN_LOBBY, {"lan": true, "error": detail if detail != "" else "The launch was aborted.", "abort_reason": reason}))
	s.kicked.connect(func(reason: int, detail: String) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c == null or c.disposed:
			return
		var text: String = NetProtocol.describe_kick(reason, detail)
		var mode: int = _mode(state)
		if mode == AppFlow.Mode.LAN_LOBBY:
			_release(c)
			state.call("go", AppFlow.Mode.LAN_BROWSER, {"message": text})
		elif mode == AppFlow.Mode.LOADING:
			_release(c)
			state.call("go", AppFlow.Mode.MAIN_MENU, {"message": text}))


static func _current_ctx() -> AppMatchContext:
	var state: Node = _autoload("AppState")
	var c: AppMatchContext = state.get("match_ctx") as AppMatchContext if state != null else null
	if c == null:
		var net_node: Node = _autoload("AppNet")
		c = net_node.get("ctx") as AppMatchContext if net_node != null else null
	return c


static func _detach_from_state(ctx: AppMatchContext) -> void:
	var state: Node = _autoload("AppState")
	if state != null and state.get("match_ctx") == ctx:
		state.set("match_ctx", null)


static func _release(ctx: AppMatchContext) -> void:
	var net_node: Node = _autoload("AppNet")
	if net_node != null and net_node.get("ctx") == ctx:
		net_node.call("end_session")
	else:
		ctx.dispose()
		var state: Node = _autoload("AppState")
		if state != null and state.get("match_ctx") == ctx:
			state.set("match_ctx", null)


static func _mode(state: Node) -> int:
	var flow: AppFlow = state.get("flow") as AppFlow
	return flow.mode if flow != null else -1


static func _data() -> GameData:
	var state: Node = _autoload("AppState")
	if state != null and state.get("data") is GameData:
		return state.get("data") as GameData
	return GameData.load_default()


static func _player_name(p: Dictionary) -> String:
	if p.has("player_name"):
		return str(p["player_name"])
	var st: Node = _autoload("AppSettings")
	return str(st.call("get_str", &"net/player_name")) if st != null else "Commander"


static func _setting_bool(id: StringName, fallback: bool) -> bool:
	var st: Node = _autoload("AppSettings")
	return bool(st.call("get_bool", id)) if st != null else fallback


static func _setting_int(id: StringName, fallback: int) -> int:
	var st: Node = _autoload("AppSettings")
	return int(st.call("get_int", id)) if st != null else fallback


static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null
