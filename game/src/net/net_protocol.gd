class_name NetProtocol
extends RefCounted
## Single source of truth for the network protocol: constants, enums (integer values are wire/file
## format, never renumber), per-message limits, FNV-1a / mix32 / lobby RNG, text sanitising and small
## address helpers. See docs/spec/net.md sections 3.8, 4.1-4.3.
##
## Enum members must be qualified: NetProtocol.KickReason.KICKED_BY_HOST. Plain constants are accessed
## as NetProtocol.NAME.

# ---- versions, ports, channels ------------------------------------------------------------------
const PROTO_VERSION: int = 1
const DEFAULT_PORT: int = 27615
const PORT_SCAN_COUNT: int = 10
const DISCOVERY_PORT: int = 27614
const CH_CTRL: int = 0
const CH_TURN: int = 1
const CH_BULK: int = 2
const CHANNEL_COUNT: int = 3
const MAX_PLAYERS: int = 8
const MAX_SPECTATORS: int = 8
const ENET_MAX_PEERS: int = 24
const MAX_UNAUTH_PEERS: int = 8
const MAX_CONN_PER_IP: int = 4
## ENet connect data sent by clients: "MF" + protocol version (hosts refuse connections without the magic).
const CONNECT_MAGIC: int = 0x4D460000

# ---- timing (mirror SimConfig; asserted equal by test_net_protocol) -----------------------------------
const TURN_TICKS: int = 2
const TICK_US: int = 50_000
const TURN_MS: int = 100
const CHECKSUM_PERIOD_TICKS: int = 20
const D_MIN_LAN: int = 2
const D_MIN_LOCAL: int = 1
const D_MAX: int = 8
const REORDER_WINDOW: int = 32
const INPUT_LOOKAHEAD: int = D_MAX + 2

# ---- limits -------------------------------------------------------------------------------------------
const MAX_CMD_INTS: int = 1024
const MAX_CMDS_PER_TURN: int = 64
const MAX_INPUT_BYTES: int = 6200
const MAX_BUNDLE_BYTES: int = 52000
const MAX_CONFIG_JSON: int = 65536
const MAX_LAUNCH_PACKET: int = 40000
const MAX_SNAPSHOT: int = 3072
const MAX_CATCHUP_CHUNK: int = 60000
const MAX_CATCHUP_RAW: int = 262144
const LOCAL_QUEUE_MAX: int = 256
const NAME_MAX_CHARS: int = 24
const CHAT_MAX_BYTES: int = 200
const NAME_MAX_BYTES: int = 48

# ---- timers (ms) --------------------------------------------------------------------------------------
const PING_INTERVAL_MS: int = 500
const CONNECT_TIMEOUT_MS: int = 6000
const JOIN_REPLY_TIMEOUT_MS: int = 5000
const HANDSHAKE_TIMEOUT_MS: int = 5000
## ENetPacketPeer.set_timeout(limit, min_ms, max_ms) triples: [limit, min_ms, max_ms].
const TIMEOUTS_LOBBY: PackedInt32Array = [32, 5000, 15000]
const TIMEOUTS_GAME: PackedInt32Array = [32, 5000, 12000]
const TIMEOUTS_LOADING: PackedInt32Array = [64, 20000, 60000]
const STALL_UI_MS: int = 400
const STALL_INFO_PERIOD_MS: int = 250
const STALL_PROMPT_MS: int = 8000
const AUTO_DROP_DEFAULT_MS: int = 60000
const DISCONNECT_ACT_MS: int = 5000
const HITCH_MS: int = 1000
const QUARANTINE_MS: int = 3000
const DELAY_EVAL_MS: int = 500
const DELAY_FRAME_MARGIN_MS: int = 34
const DELAY_RAISE_STALL_MS: int = 400
const DELAY_LOWER_HOLD_MS: int = 8000
const DELAY_LOWER_MARGIN_MS: int = 60
const MAX_TICKS_PER_POLL: int = 8
const MAX_ELAPSED_US: int = 250000
const ACC_CAP_TICKS: int = 4
const MAX_PAUSES_PER_PLAYER: int = 3
const MAX_PAUSE_MS: int = 120000
const LOAD_TIMEOUT_MS: int = 120000
const COUNTDOWN_S: int = 3
const DISCOVERY_INTERVAL_MS: int = 1000
const DISCOVERY_STALE_MS: int = 4000
const DISCOVERY_BREAKER_FAILS: int = 5
const DISCOVERY_BREAKER_MS: int = 30000
const LOBBY_SNAPSHOT_MIN_MS: int = 100
const AI_THINK_PERIOD_TURNS: int = 5
const AI_MAX_CMDS_PER_THINK: int = 64
const AI_BOUNDARY_BUDGET_US: int = 8000
const VIOLATION_KICK_SCORE: int = 12
const VIOLATION_DECAY_MS: int = 5000
## Game speed table (percent); code 2 (100 %) is the default.
const SPEED_PCT: PackedInt32Array = [50, 75, 100, 125, 150, 200]
## Net-reserved sim command type (reserved range 240..255).
const T_RESIGN: int = 250
const TAKEOVER_AI_LEVEL: int = 1

# ---- enumerations (integer values are wire/file format) ---------------------------------------------
enum SlotKind { CLOSED = 0, OPEN = 1, HUMAN = 2, AI = 3 }
enum LobbyPhase { OPEN = 0, COUNTDOWN = 1, LOADING = 2, IN_GAME = 3, ENDED = 4 }
enum LobbyOp {
	SET_ROSTER = 1, SET_TEAM = 2, SET_COLOR = 3, SET_START = 4, SET_READY = 5, SET_NAME = 6,
	MOVE_TO_SLOT = 7, TO_SPECTATOR = 8, TO_PLAYER = 9,
}
enum RejectReason {
	NONE = 0, PROTO_MISMATCH = 1, SIM_MISMATCH = 2, DATA_MISMATCH = 3, LOBBY_FULL = 4, IN_PROGRESS = 5,
	BANNED = 6, BAD_PASSWORD = 7, BAD_REQUEST = 8, SPECTATORS_CLOSED = 9, HOST_BUSY = 10, TOO_MANY_CONNECTIONS = 11,
}
enum KickReason {
	NONE = 0, KICKED_BY_HOST = 1, BANNED = 2, HOST_LEFT = 3, PROTOCOL_VIOLATION = 4, TIMEOUT = 5,
	DROPPED_UNRESPONSIVE = 6, DUPLICATE_SESSION = 7, SHUTDOWN = 8, VERSION = 9,
}
enum AbortReason {
	NONE = 0, HUMAN_LEFT = 1, LOAD_TIMEOUT = 2, LOAD_FAILED = 3, MAP_MISMATCH = 4, INIT_MISMATCH = 5,
	CONFIG_INVALID = 6, HOST_CANCEL = 7,
}
enum PlayerRole { PR_NONE = 0, PR_HUMAN = 1, PR_AI = 2, PR_DROPPED = 3 }
enum PlayerNetStatus { ACTIVE = 0, STALLED = 1, DISCONNECTED = 2, DROPPED = 3, AI_TAKEOVER = 4, RESIGNED = 5, LEFT = 6, DEFEATED = 7 }
enum CtrlKind { INPUT_DELAY = 1, PLAYER_STATUS = 2, SPEED = 3, MATCH_END = 4, PAUSE = 5 }
enum StallReason { NETWORK = 0, DISCONNECTED = 1, SLOW_CPU = 2, LOADING = 3 }
enum StallAction { STALL_WAIT = 0, STALL_DROP_RESIGN = 1, STALL_DROP_AI = 2 }
enum DesyncKind { NONE = 0, SIM = 1, INPUT_CHAIN = 2, BOTH = 3 }
enum PauseError { OK = 0, NOT_ALLOWED = 1, BUDGET_EXHAUSTED = 2, ALREADY = 3, NOT_PLAYING = 4 }
enum PausePolicy { HOST_ONLY = 0, ANY_PLAYER = 1, DISABLED = 2 }
enum OnDisconnect { RESIGN = 0, AI = 1 }
enum ResignReason { SURRENDER = 0, DISCONNECT = 1, KICKED = 2, TIMEOUT = 3 }
enum PeerState { GONE = 0, CONNECTING = 1, CONNECTED = 2 }
enum BundleResult { OK = 0, DUPLICATE = 1, TOO_FAR = 2, MALFORMED = 3, WRONG_STATE = 4 }
enum ReplayRec { TURNS = 1, CHECK = 2, PARTS = 3, EVENT = 4, END = 5 }
enum ReplayEvent { PLAYER_STATUS = 1, CHAT = 2 }
enum MatchEndReason { SIM_DECIDED = 0, NO_HUMANS_LEFT = 1, HOST_CLOSED = 2, ABANDONED = 3, DESYNC = 4 }
enum NetErrorCode { REPLAY_WRITE = 1, NO_CHECKSUM = 2, HOST_PROTOCOL = 3, TRANSPORT = 4, BUILD_FAILED = 5 }
enum LogLevel { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
enum Msg {
	JOIN_REQUEST = 0x01, JOIN_REJECT = 0x02, JOIN_ACCEPT = 0x03, LOBBY_SNAPSHOT = 0x04, LOBBY_ACTION = 0x05,
	CHAT = 0x06, LEAVE = 0x07, KICKED = 0x08, MAP_PING = 0x09, DATA_DIFF = 0x0A,
	LAUNCH_COUNTDOWN = 0x10, LAUNCH_ABORT = 0x11, LAUNCH_CONFIG = 0x12, LOAD_PROGRESS = 0x13, LOAD_DONE = 0x14,
	START = 0x15, LOAD_STATUS = 0x16, RETURN_TO_LOBBY = 0x17, LOAD_FAILED = 0x18,
	TURN_INPUT = 0x20, TURN_BUNDLE = 0x21, PING = 0x22, PONG = 0x23, STALL_INFO = 0x24, PAUSE_REQUEST = 0x25, RESUME = 0x26,
	CHECKSUM_REPORT = 0x30, DESYNC_NOTICE = 0x31, PARTS_REQUEST = 0x32, PARTS_REPORT = 0x33, MATCH_END = 0x34,
	CATCHUP_REQUEST = 0x40, CATCHUP_CHUNK = 0x41, CATCHUP_DONE = 0x42,
}

## Message direction codes used by MSG_TABLE.
const DIR_C2H: int = 0
const DIR_H2C: int = 1
const DIR_BOTH: int = 2
## Rate classes (mirror NetRateLimiter.Class) returned by msg_rate_class.
const RATE_INPUT: int = 0
const RATE_PONG: int = 1
const RATE_CHECK: int = 2
const RATE_LOBBY: int = 3
const RATE_CHAT: int = 4
const RATE_PAUSE: int = 5
const RATE_MISC: int = 6

## §4.3 matrix: type -> [direction, channel, max_bytes, rate_class (-1 = not rate limited)].
## Phase permissions live in NetSession; this table is direction, channel, size and rate class only.
const MSG_TABLE: Dictionary = {
	0x01: [0, 0, 8192, 6], 0x02: [1, 0, 200, -1], 0x03: [1, 0, 16, -1], 0x04: [1, 0, 3072, -1],
	0x05: [0, 0, 80, 3], 0x06: [2, 0, 260, 4], 0x07: [0, 0, 4, 6], 0x08: [1, 0, 120, -1],
	0x09: [2, 0, 8, 6], 0x0A: [1, 0, 3200, -1],
	0x10: [1, 0, 4, -1], 0x11: [1, 0, 120, -1], 0x12: [1, 0, 40000, -1], 0x13: [0, 0, 4, 6],
	0x14: [0, 0, 16, 6], 0x15: [1, 0, 12, -1], 0x16: [1, 0, 24, -1], 0x17: [1, 0, 2, -1], 0x18: [0, 0, 120, 6],
	0x20: [0, 1, 6200, 0], 0x21: [1, 1, 52000, -1], 0x22: [1, 1, 12, -1], 0x23: [0, 1, 24, 1],
	0x24: [1, 1, 200, -1], 0x25: [0, 1, 4, 5], 0x26: [1, 1, 12, -1],
	0x30: [0, 0, 16, 2], 0x31: [1, 0, 120, -1], 0x32: [1, 0, 80, -1], 0x33: [0, 0, 64, 2], 0x34: [1, 0, 16, -1],
	0x40: [0, 0, 8, 6], 0x41: [1, 2, 60000, -1], 0x42: [1, 0, 8, -1],
}


static func is_known_msg(type: int) -> bool:
	return MSG_TABLE.has(type)


## Maximum message size in bytes for `type` (-1 for an unknown type).
static func msg_max_bytes(type: int) -> int:
	var row: Array = MSG_TABLE.get(type, []) as Array
	return -1 if row.is_empty() else int(row[2])


## ENet channel for `type` (-1 unknown).
static func msg_channel(type: int) -> int:
	var row: Array = MSG_TABLE.get(type, []) as Array
	return -1 if row.is_empty() else int(row[1])


## DIR_C2H / DIR_H2C / DIR_BOTH (-1 unknown).
static func msg_dir(type: int) -> int:
	var row: Array = MSG_TABLE.get(type, []) as Array
	return -1 if row.is_empty() else int(row[0])


## Rate-limiter class for a message received by the host (RATE_*), -1 when not limited or unknown.
static func msg_rate_class(type: int) -> int:
	var row: Array = MSG_TABLE.get(type, []) as Array
	return -1 if row.is_empty() else int(row[3])


static func msg_name(type: int) -> String:
	var k: Variant = Msg.find_key(type)
	return "MSG_%02X" % type if k == null else str(k)


## The ENet connect data a well-behaved client sends.
static func connect_data() -> int:
	return CONNECT_MAGIC | PROTO_VERSION


static func has_connect_magic(data: int) -> bool:
	return (data & 0xFFFF0000) == CONNECT_MAGIC


# ---- hashing / RNG ------------------------------------------------------------------------------------

## FNV-1a 32 over bytes[from, to) (to = -1: end). `basis` chains calls: fnv1a32(b2, fnv1a32(b1)) == fnv1a32(b1 + b2).
static func fnv1a32(bytes: PackedByteArray, basis: int = 0x811C9DC5, from: int = 0, to: int = -1) -> int:
	var h: int = basis & 0xFFFFFFFF
	var end: int = bytes.size() if to < 0 or to > bytes.size() else to
	var i: int = maxi(from, 0)
	while i < end:
		h = ((h ^ bytes[i]) * 0x01000193) & 0xFFFFFFFF
		i += 1
	return h


## murmur3 fmix32, 32-bit masked.
static func mix32(x: int) -> int:
	var h: int = x & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x85EBCA6B) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 0xC2B2AE35) & 0xFFFFFFFF
	h ^= h >> 16
	return h


## Deterministic lobby random number `index` of stream `rng_seed`.
static func lobby_rand(rng_seed: int, index: int) -> int:
	return mix32((rng_seed + (index + 1) * 0x9E3779B9) & 0xFFFFFFFF)


## Cheap sanity check of a zlib stream header (CM = 8, header checksum, no preset dictionary) and the
## minimum size (2 header + 4 Adler bytes). Callers run it before PackedByteArray.decompress_dynamic so
## that obviously foreign data never reaches the engine inflater (which logs an ERROR on failure).
static func looks_like_zlib(bytes: PackedByteArray, from: int = 0) -> bool:
	if bytes.size() - from < 7:
		return false
	var cmf: int = bytes[from]
	var flg: int = bytes[from + 1]
	return (cmf & 0x0F) == 8 and (cmf >> 4) <= 7 and ((cmf << 8) | flg) % 31 == 0 and (flg & 0x20) == 0


# ---- text ---------------------------------------------------------------------------------------------

static func _is_bad_char(c: int) -> bool:
	if c < 0x20 or c == 0x7F or (c >= 0x80 and c <= 0x9F):
		return true
	# zero-width / bidi override / BOM characters that could spoof chat lines
	return (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF


static func _cp_utf8_len(c: int) -> int:
	if c < 0x80:
		return 1
	if c < 0x800:
		return 2
	if c < 0x10000:
		return 3
	return 4


## Cuts `s` to at most `max_bytes` UTF-8 bytes on a code-point boundary.
static func truncate_utf8(s: String, max_bytes: int) -> String:
	var total: int = 0
	var n: int = s.length()
	for i in n:
		total += _cp_utf8_len(s.unicode_at(i))
		if total > max_bytes:
			return s.substr(0, i)
	return s


## Lobby/player name: control characters and BBCode brackets removed, trimmed, <= 24 characters (and <= 48
## UTF-8 bytes so it always fits the wire field), "" -> "Player".
static func sanitize_name(s: String) -> String:
	var out: String = ""
	for i in s.length():
		var c: int = s.unicode_at(i)
		if _is_bad_char(c) or c == 0x5B or c == 0x5D:
			continue
		out += String.chr(c)
	out = out.strip_edges()
	if out.length() > NAME_MAX_CHARS:
		out = out.substr(0, NAME_MAX_CHARS)
	out = truncate_utf8(out, NAME_MAX_BYTES).strip_edges()
	return "Player" if out.is_empty() else out


## Chat text: control characters removed, whitespace runs collapsed to one space, trimmed, cut on a UTF-8 boundary.
static func sanitize_text(s: String, max_bytes: int) -> String:
	var out: String = ""
	var last_space: bool = true
	for i in s.length():
		var c: int = s.unicode_at(i)
		if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0xA0:
			if not last_space:
				out += " "
				last_space = true
			continue
		if _is_bad_char(c):
			continue
		out += String.chr(c)
		last_space = false
	return truncate_utf8(out.strip_edges(), max_bytes).strip_edges()


## Strict RFC 3629 scan of bytes[from, from+length): rejects NUL, overlong forms, surrogates, > U+10FFFF,
## stray/truncated sequences. Never raises an engine error (bad ranges return false).
static func is_valid_utf8(bytes: PackedByteArray, from: int, length: int) -> bool:
	if from < 0 or length < 0 or from + length > bytes.size():
		return false
	var i: int = from
	var end: int = from + length
	while i < end:
		var b: int = bytes[i]
		if b == 0:
			return false
		if b < 0x80:
			i += 1
			continue
		var need: int = 0
		var lo: int = 0x80
		var hi: int = 0xBF
		if b >= 0xC2 and b <= 0xDF:
			need = 1
		elif b >= 0xE0 and b <= 0xEF:
			need = 2
			if b == 0xE0:
				lo = 0xA0
			elif b == 0xED:
				hi = 0x9F
		elif b >= 0xF0 and b <= 0xF4:
			need = 3
			if b == 0xF0:
				lo = 0x90
			elif b == 0xF4:
				hi = 0x8F
		else:
			return false
		if i + need >= end:
			return false
		var c1: int = bytes[i + 1]
		if c1 < lo or c1 > hi:
			return false
		for k in range(2, need + 1):
			var ck: int = bytes[i + k]
			if ck < 0x80 or ck > 0xBF:
				return false
		i += need + 1
	return true


## Number of UTF-8 bytes of a String.
static func utf8_size(s: String) -> int:
	return s.to_utf8_buffer().size()


# ---- reject / kick texts ------------------------------------------------------------------------------

static func _hex8(v: int) -> String:
	return "%08X" % (v & 0xFFFFFFFF)


## English default of the net.err.* join-failure texts. `info` keys (all optional): host_game_version,
## host_proto_version, host_sim_version, host_data_hash, local_game_version, local_proto_version,
## local_sim_version, local_data_hash, detail.
static func describe_reject(reason: int, info: Dictionary) -> String:
	var hv: String = str(info.get("host_game_version", ""))
	var lv: String = str(info.get("local_game_version", ""))
	match reason:
		RejectReason.PROTO_MISMATCH:
			return "Version mismatch (protocol). Host: %s (protocol %d). You: %s (protocol %d). All players must run the same build." % [
				hv, int(info.get("host_proto_version", 0)), lv, int(info.get("local_proto_version", PROTO_VERSION))]
		RejectReason.SIM_MISMATCH:
			return "Version mismatch (simulation). Host: %s (simulation %d). You: %s (simulation %d). All players must run the same build." % [
				hv, int(info.get("host_sim_version", 0)), lv, int(info.get("local_sim_version", 0))]
		RejectReason.DATA_MISMATCH:
			return "Version mismatch (game data). Host: %s (data %s). You: %s (data %s). All players must run the same build." % [
				hv, _hex8(int(info.get("host_data_hash", 0))), lv, _hex8(int(info.get("local_data_hash", 0)))]
		RejectReason.LOBBY_FULL:
			return "The game is full."
		RejectReason.IN_PROGRESS:
			return "The match has already started."
		RejectReason.BANNED:
			return "The host removed you from this game."
		RejectReason.BAD_PASSWORD:
			return "Wrong password."
		RejectReason.BAD_REQUEST:
			return "The host could not understand the join request."
		RejectReason.SPECTATORS_CLOSED:
			return "This game does not allow spectators."
		RejectReason.HOST_BUSY:
			return "The host is starting the game. Try again in a moment."
		RejectReason.TOO_MANY_CONNECTIONS:
			return "Too many connections from this address."
	return ""


static func describe_kick(reason: int, detail: String) -> String:
	var text: String
	match reason:
		KickReason.KICKED_BY_HOST:
			text = "The host removed you from the game."
		KickReason.BANNED:
			text = "The host removed you from this game."
		KickReason.HOST_LEFT:
			text = "The host left the game."
		KickReason.PROTOCOL_VIOLATION:
			text = "Disconnected: protocol violation."
		KickReason.TIMEOUT:
			text = "Connection timed out."
		KickReason.DROPPED_UNRESPONSIVE:
			text = "You were dropped because you stopped responding."
		KickReason.DUPLICATE_SESSION:
			text = "Another session with the same identity joined."
		KickReason.SHUTDOWN:
			text = "The host closed the game."
		KickReason.VERSION:
			text = "Version mismatch."
		_:
			text = "Disconnected."
	if not detail.is_empty():
		text += " (" + detail + ")"
	return text


# ---- addresses ----------------------------------------------------------------------------------------

## 10/8, 172.16/12, 192.168/16, 169.254/16, 127/8, 100.64/10.
static func is_private_ipv4(ip: String) -> bool:
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return false
	var v: PackedInt32Array = PackedInt32Array()
	for p in parts:
		if p.is_empty() or not p.is_valid_int():
			return false
		var n: int = p.to_int()
		if n < 0 or n > 255 or p.length() > 3:
			return false
		v.append(n)
	if v[0] == 10 or v[0] == 127:
		return true
	if v[0] == 172 and v[1] >= 16 and v[1] <= 31:
		return true
	if v[0] == 192 and v[1] == 168:
		return true
	if v[0] == 169 and v[1] == 254:
		return true
	return v[0] == 100 and v[1] >= 64 and v[1] <= 127


static func _addr_fail(err: String) -> Dictionary:
	return {"ok": false, "host": "", "port": 0, "error": err}


static func _valid_hostname(h: String) -> bool:
	if h.is_empty() or h.length() > 253:
		return false
	var numeric: bool = true
	for i in h.length():
		var c: int = h.unicode_at(i)
		var is_digit: bool = c >= 0x30 and c <= 0x39
		var is_alpha: bool = (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
		if not (is_digit or is_alpha or c == 0x2E or c == 0x2D or c == 0x5F):
			return false
		if not (is_digit or c == 0x2E):
			numeric = false
	if numeric:
		return h.is_valid_ip_address()
	return h[0] != "." and h[h.length() - 1] != "."


## Join-by-address input => {ok, host, port, error}. Accepts `1.2.3.4`, `1.2.3.4:27615`, `name`, `name:27615`,
## `[fe80::1]:27615` and bare IPv6 (no port); default port 27615; port 1..65535; zone ids (%en0) rejected.
static func parse_address(text: String) -> Dictionary:
	var t: String = text.strip_edges()
	if t.is_empty():
		return _addr_fail("empty address")
	if t.length() > 255:
		return _addr_fail("address too long")
	if t.contains("%"):
		return _addr_fail("zone ids are not supported")
	var host: String = ""
	var port_text: String = ""
	if t.begins_with("["):
		var close: int = t.find("]")
		if close < 0:
			return _addr_fail("missing ]")
		host = t.substr(1, close - 1)
		var rest: String = t.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return _addr_fail("bad port")
			port_text = rest.substr(1)
			if port_text.is_empty():
				return _addr_fail("bad port")
		if not host.contains(":") or not host.is_valid_ip_address():
			return _addr_fail("bad IPv6 address")
	elif t.count(":") >= 2:
		if not t.is_valid_ip_address():
			return _addr_fail("bad IPv6 address")
		host = t
	elif t.count(":") == 1:
		var idx: int = t.find(":")
		host = t.substr(0, idx)
		port_text = t.substr(idx + 1)
		if port_text.is_empty():
			return _addr_fail("bad port")
	else:
		host = t
	if not (host.contains(":") or _valid_hostname(host)):
		return _addr_fail("bad host")
	var port: int = DEFAULT_PORT
	if not port_text.is_empty():
		if port_text.length() > 5 or not port_text.is_valid_int() or port_text.begins_with("+") or port_text.begins_with("-"):
			return _addr_fail("bad port")
		port = port_text.to_int()
		if port < 1 or port > 65535:
			return _addr_fail("bad port")
	return {"ok": true, "host": host, "port": port, "error": ""}
