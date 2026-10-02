class_name NetTransport
extends RefCounted
## Abstract peer-id-based reliable transport (docs/spec/net.md 3.2). Concrete: NetTransportEnet,
## NetTransportLoopback; NetTransportFault decorates any of them. Base methods push_error("NOT IMPLEMENTED")
## and return ERR_UNAVAILABLE (or an empty value); the event queue helpers are shared.
##
## Semantics every implementation follows:
##  * peer ids: the host is 1; a client sees the server as 1; remote clients get 2, 3, ... never reused.
##  * poll() only fills the event queue; take_events() transfers ownership of the queued events.
##  * send() is always reliable + ordered per channel; channel >= NetProtocol.CHANNEL_COUNT returns
##    ERR_INVALID_PARAMETER and is never handed to the engine (ENet would log an ERROR).
##  * disconnect_peer(graceful = true): queued packets are delivered first, the remote gets DISCONNECTED(code)
##    and the local side a DISCONNECTED(0) once the peer is gone. graceful = false: immediate, remote gets
##    DISCONNECTED(code), NO local event.

var _events: Array[NetTransportEvent] = []


## Host: scans port .. port + PORT_SCAN_COUNT - 1; the chosen port is local_port(). Returns an Error.
func listen(_port: int, _max_peers: int) -> int:
	return _unimplemented()


## Client: returns OK immediately; success/failure arrives as events (own CONNECT_TIMEOUT_MS).
func connect_to(_address: String, _port: int, _connect_data: int) -> int:
	return _unimplemented()


## Services the transport (never blocks) and fills the event queue.
func poll() -> void:
	_unimplemented()


## Returns and clears the queued events (ownership transfers to the caller).
func take_events() -> Array[NetTransportEvent]:
	var out: Array[NetTransportEvent] = _events
	_events = []
	return out


func send(_peer_id: int, _channel: int, _data: PackedByteArray) -> int:
	return _unimplemented()


## Pushes everything queued by send() onto the wire; call once per frame after all sends.
func flush() -> void:
	pass


func disconnect_peer(_peer_id: int, _code: int, _graceful: bool) -> void:
	_unimplemented()


## Drops every connection and releases sockets. Idempotent.
func close() -> void:
	pass


func peer_ids() -> PackedInt32Array:
	_unimplemented()
	return PackedInt32Array()


## NetProtocol.PeerState: 0 gone, 1 connecting, 2 connected.
func peer_state(_peer_id: int) -> int:
	_unimplemented()
	return NetProtocol.PeerState.GONE


func peer_address(_peer_id: int) -> String:
	_unimplemented()
	return ""


## Never null. Stats of a peer that is gone are zeroed (the engine is never asked about dead peers).
func peer_stats(_peer_id: int) -> NetPeerStats:
	_unimplemented()
	return NetPeerStats.new()


## Applies to all current and future peers: values of NetProtocol.TIMEOUTS_* ([limit, min_ms, max_ms]).
func set_timeouts(_limit: int, _min_ms: int, _max_ms: int) -> void:
	_unimplemented()


func local_port() -> int:
	return 0


## [bytes_sent, bytes_recv, pkts_sent, pkts_recv] since the last call.
func pop_traffic() -> PackedInt64Array:
	return PackedInt64Array([0, 0, 0, 0])


func _unimplemented() -> int:
	push_error("NOT IMPLEMENTED")
	return ERR_UNAVAILABLE


func _queue(e: NetTransportEvent) -> void:
	_events.append(e)
