class_name NetPeerInfo
extends RefCounted
## Host-side record per remote connection (docs/spec/net.md 4.5), plus the bookkeeping the session keeps for it
## (handshake deadline, ping state, reported exec turn).

enum Stage { HANDSHAKE = 0, LOBBY = 1, LOADING = 2, LOADED = 3, PLAYING = 4, LEFT = 5 }

var peer_id: int = 0
var address: String = ""
var stage: int = Stage.HANDSHAKE
var connected_at_ms: int = 0
## Client nonce from JOIN_REQUEST (ban key together with the address).
var nonce: int = 0
var name: String = ""
## Lobby slot index (== pid at launch), -1 when not seated.
var slot: int = -1
var is_spectator: bool = false
var limiter: NetRateLimiter = NetRateLimiter.new()
var violations: float = 0.0
var last_violation_ms: int = 0
var loaded: bool = false
var load_pct: int = 0
var map_hash: int = 0
var checksum0: int = 0
## Spectator catch-up cursor (spectators are not part of this build; kept for the wire contract).
var catchup_next: int = -1
var stats: NetPeerStats = NetPeerStats.new()

# session bookkeeping
## Handshake timer start (clock us); the peer is dropped when no JOIN_REQUEST arrives within HANDSHAKE_TIMEOUT_MS.
var handshake_since_us: int = 0
## Last time (clock us) anything arrived from the peer while loading (LOAD_TIMEOUT).
var last_load_msg_us: int = 0
var join_game_version: String = ""
var last_ping_seq: int = 0
var rtt_ms: int = 0
var jitter_ms: int = 0
var exec_turn: int = 0
var load_pct_sent: int = -1
## A LOAD_DONE / LOAD_FAILED was already received (both are once-only).
var load_reported: bool = false
## Total violation points ever scored (for stats).
var violation_total: int = 0
