class_name NetLobbyState
extends RefCounted
## The replicated lobby model (docs/spec/net.md 4.5). Owned by NetLobby; UI code treats it as read-only (use
## duplicate_state() for a stable copy). Defaults come from game/data/net/lobby_options.json through
## NetMatchConfig.options(). `opts` arguments are NetSessionOptions, read by property name (duck typed) so this
## file compiles without it.

var revision: int = 0
## NetProtocol.LobbyPhase.
var phase: int = 0
var host_name: String = ""
## Random u32 at lobby creation.
var session_id: int = 0
var password_set: bool = false
var allow_spectators: bool = true
var map_family: int = 0
## Cells, multiple of 8, 96..256.
var map_size: int = 128
## u32.
var map_seed: int = 0
## 2 | 4 | 6 | 8; slots >= layout_players are CLOSED.
var layout_players: int = 4
## key -> int (bools as 0/1) for every key of lobby_options.json rules_schema.
var rules: Dictionary = {}
## Index into NetProtocol.SPEED_PCT.
var speed_code: int = 2
var pause_policy: int = 1
var on_disconnect: int = 0
var auto_drop_ms: int = 60000
## Always 8.
var slots: Array[NetPlayerSlot] = []
## [{peer_id: int, name: String}]. Untyped on purpose: NetLobbyCodec.dict_to_state assigns it through Object.set(),
## which silently refuses an untyped Array for an Array[Dictionary] property.
var spectators: Array = []


func _init() -> void:
	rules = NetMatchConfig.default_rules()
	for i: int in NetProtocol.MAX_PLAYERS:
		var s: NetPlayerSlot = NetPlayerSlot.new()
		s.index = i
		s.kind = NetProtocol.SlotKind.CLOSED
		s.color = i
		slots.append(s)


## -1 if none.
func slot_of_peer(peer_id: int) -> int:
	if peer_id <= 0:
		return -1
	for s: NetPlayerSlot in slots:
		if s.kind == NetProtocol.SlotKind.HUMAN and s.peer_id == peer_id:
			return s.index
	return -1


## Slots of kind HUMAN or AI, ascending.
func active_slot_indices() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: NetPlayerSlot in slots:
		if s.is_active():
			out.append(s.index)
	return out


func human_count() -> int:
	var n: int = 0
	for s: NetPlayerSlot in slots:
		if s.kind == NetProtocol.SlotKind.HUMAN:
			n += 1
	return n


func ai_count() -> int:
	var n: int = 0
	for s: NetPlayerSlot in slots:
		if s.kind == NetProtocol.SlotKind.AI:
			n += 1
	return n


## -1 if none.
func first_open_slot() -> int:
	for s: NetPlayerSlot in slots:
		if s.kind == NetProtocol.SlotKind.OPEN:
			return s.index
	return -1


func duplicate_state() -> NetLobbyState:
	var c: NetLobbyState = NetLobbyState.new()
	c.revision = revision
	c.phase = phase
	c.host_name = host_name
	c.session_id = session_id
	c.password_set = password_set
	c.allow_spectators = allow_spectators
	c.map_family = map_family
	c.map_size = map_size
	c.map_seed = map_seed
	c.layout_players = layout_players
	c.rules = rules.duplicate()
	c.speed_code = speed_code
	c.pause_policy = pause_policy
	c.on_disconnect = on_disconnect
	c.auto_drop_ms = auto_drop_ms
	c.slots = []
	for s: NetPlayerSlot in slots:
		c.slots.append(s.duplicate_slot())
	c.spectators = []
	for sp: Variant in spectators:
		c.spectators.append((sp as Dictionary).duplicate())
	return c


static func _opt(opts: RefCounted, key: String, def: Variant) -> Variant:
	if opts == null:
		return def
	var v: Variant = opts.get(key)
	return def if v == null else v


static func _apply_defaults(st: NetLobbyState, opts: RefCounted) -> void:
	var o: Dictionary = NetMatchConfig.options()
	var dm: Dictionary = (o.get("defaults", {}) as Dictionary).get("map", {}) as Dictionary
	var dn: Dictionary = (o.get("defaults", {}) as Dictionary).get("net", {}) as Dictionary
	st.map_family = int(dm.get("family", 0))
	st.map_size = int(dm.get("size", 128))
	st.layout_players = int(dm.get("layout_players", 4))
	st.speed_code = int(dn.get("speed_code", 2))
	st.pause_policy = int(dn.get("pause_policy", 1))
	st.on_disconnect = int(dn.get("on_disconnect", 0))
	st.auto_drop_ms = int(dn.get("auto_drop_ms", NetProtocol.AUTO_DROP_DEFAULT_MS))
	st.allow_spectators = bool(_opt(opts, "allow_spectators", bool(dn.get("allow_spectators", true))))
	st.password_set = str(_opt(opts, "password", "")) != ""


static func _make_host(st: NetLobbyState, hname: String, opts: RefCounted, roster: String) -> void:
	var s: NetPlayerSlot = st.slots[0]
	if bool(_opt(opts, "dedicated", false)):
		s.kind = NetProtocol.SlotKind.OPEN
		return
	s.kind = NetProtocol.SlotKind.HUMAN
	s.peer_id = 1
	s.name = NetProtocol.sanitize_name(hname)
	s.roster_id = roster
	s.ready = true
	s.connected = true


static func _ai_handicap(opts: RefCounted, level: int) -> int:
	var c: Variant = _opt(opts, "ai_default_handicap", null)
	if c is Callable and (c as Callable).is_valid():
		return clampi(int((c as Callable).call(level)), 50, 200)
	return 100


## Slot 0 HUMAN (the host; OPEN for a dedicated host), the other slots below layout_players OPEN, the rest CLOSED.
static func create_default(host_name_: String, session_id_: int, map_seed_: int, opts: RefCounted = null) -> NetLobbyState:
	var st: NetLobbyState = NetLobbyState.new()
	st.host_name = NetProtocol.sanitize_name(host_name_)
	st.session_id = session_id_ & 0xFFFFFFFF
	st.map_seed = map_seed_ & 0xFFFFFFFF
	_apply_defaults(st, opts)
	_make_host(st, host_name_, opts, "random")
	for i: int in range(1, st.layout_players):
		st.slots[i].kind = NetProtocol.SlotKind.OPEN
	return st


## Slot 0 HUMAN (local player), slot 1 AI (medium, random roster), everything else CLOSED. Skirmish setup screens
## raise slots with the same edit rules as a LAN lobby.
static func create_skirmish(local_name: String, local_roster: String, opts: RefCounted = null) -> NetLobbyState:
	var st: NetLobbyState = NetLobbyState.new()
	st.host_name = NetProtocol.sanitize_name(local_name)
	_apply_defaults(st, opts)
	st.allow_spectators = false
	_make_host(st, local_name, opts, local_roster)
	var ai: NetPlayerSlot = st.slots[1]
	ai.kind = NetProtocol.SlotKind.AI
	ai.name = "AI 2"
	ai.roster_id = "random"
	ai.ready = true
	ai.connected = true
	ai.ai_level = 1
	ai.handicap_pct = _ai_handicap(opts, ai.ai_level)
	return st
