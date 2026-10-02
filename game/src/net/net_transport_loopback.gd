class_name NetTransportLoopback
extends NetTransport
## Socket-free transport for unit tests and virtual-time scenarios (docs/spec/net.md 3.2). Created by
## NetLoopbackHub.endpoint(). Same peer-id rules and event semantics as NetTransportEnet.

## Address other endpoints see for this one (CONNECTED.address on the listening side, peer_address()).
var address: String = "127.0.0.1"

var _hub_ref: WeakRef
var _inbox: Array[NetTransportEvent] = []
var _peers: Dictionary = {}          # id -> _Peer
var _next_remote_id: int = 2
var _port: int = 0
var _max_peers: int = 0
var _connect_due_us: int = -1
var _sent_bytes: int = 0
var _recv_bytes: int = 0
var _sent_pkts: int = 0
var _recv_pkts: int = 0


class _Peer extends RefCounted:
	var remote_ref: WeakRef
	var remote_id: int = 0
	var state: int = NetProtocol.PeerState.CONNECTING
	var stats: NetPeerStats = NetPeerStats.new()

	func remote() -> NetTransportLoopback:
		return remote_ref.get_ref() as NetTransportLoopback


## Created by NetLoopbackHub.endpoint(). Endpoints only hold weak references to the hub and to each other
## (no reference cycles): keep the hub alive for as long as its endpoints are used.
func _init(hub: NetLoopbackHub) -> void:
	_hub_ref = weakref(hub)


func _hub() -> NetLoopbackHub:
	return _hub_ref.get_ref() as NetLoopbackHub


func listen(port: int, max_peers: int) -> int:
	var hub: NetLoopbackHub = _hub()
	if hub == null:
		return ERR_UNAVAILABLE
	if _port != 0:
		return ERR_ALREADY_IN_USE
	for p in range(port, port + NetProtocol.PORT_SCAN_COUNT):
		if hub._claim_port(p, self):
			_port = p
			_max_peers = max_peers
			return OK
	return ERR_ALREADY_IN_USE


func connect_to(_address: String, port: int, connect_data: int) -> int:
	var hub: NetLoopbackHub = _hub()
	if hub == null:
		return ERR_UNAVAILABLE
	if _peers.has(1) or _connect_due_us >= 0:
		return ERR_ALREADY_IN_USE
	var host: NetTransportLoopback = hub._listener(port)
	if host == null or not host._has_capacity():
		_connect_due_us = hub.clock.now_us() + hub.connect_fail_ms * 1000
		return OK
	_link_to(host, connect_data)
	return OK


func _has_capacity() -> bool:
	return _peers.size() < _max_peers


## Client side of connect_endpoints(). Returns the id the host uses for this endpoint (0 on failure).
func _link_to(host: NetTransportLoopback, connect_data: int) -> int:
	if _peers.has(1) or host == self:
		return 0
	var hid: int = host._next_remote_id
	host._next_remote_id += 1
	var mine: _Peer = _Peer.new()
	mine.remote_ref = weakref(host)
	mine.remote_id = hid
	var theirs: _Peer = _Peer.new()
	theirs.remote_ref = weakref(self)
	theirs.remote_id = 1
	_peers[1] = mine
	host._peers[hid] = theirs
	host._inbox.append(NetTransportEvent.connected(hid, connect_data, address))
	_inbox.append(NetTransportEvent.connected(1, 0, host.address))
	return hid


func poll() -> void:
	var hub: NetLoopbackHub = _hub()
	if hub != null and _connect_due_us >= 0 and hub.clock.now_us() >= _connect_due_us:
		_connect_due_us = -1
		_inbox.append(NetTransportEvent.disconnected(1, 0))
	_pump()


func _pump() -> void:
	var hub: NetLoopbackHub = _hub()
	var now_ms: int = 0 if hub == null else hub.clock.now_us() / 1000
	for e in _inbox:
		var p: _Peer = _peers.get(e.peer_id) as _Peer
		match e.kind:
			NetTransportEvent.Kind.CONNECTED:
				if p == null:
					continue
				p.state = NetProtocol.PeerState.CONNECTED
			NetTransportEvent.Kind.DISCONNECTED:
				_peers.erase(e.peer_id)
			NetTransportEvent.Kind.PACKET:
				if p == null:
					continue
				p.stats.bytes_in += e.data.size()
				p.stats.last_seen_ms = now_ms
				_recv_bytes += e.data.size()
				_recv_pkts += 1
		_queue(e)
	_inbox.clear()


func send(peer_id: int, channel: int, data: PackedByteArray) -> int:
	if channel < 0 or channel >= NetProtocol.CHANNEL_COUNT or data.is_empty():
		return ERR_INVALID_PARAMETER
	var p: _Peer = _peers.get(peer_id) as _Peer
	var remote: NetTransportLoopback = null if p == null else p.remote()
	if p == null or remote == null or p.state != NetProtocol.PeerState.CONNECTED:
		return ERR_UNAVAILABLE
	remote._inbox.append(NetTransportEvent.packet(p.remote_id, channel, data))
	p.stats.bytes_out += data.size()
	_sent_bytes += data.size()
	_sent_pkts += 1
	return OK


func disconnect_peer(peer_id: int, code: int, graceful: bool) -> void:
	var p: _Peer = _peers.get(peer_id) as _Peer
	if p == null:
		return
	var remote: NetTransportLoopback = p.remote()
	if remote != null:
		if not graceful:
			var keep: Array[NetTransportEvent] = []
			for e in remote._inbox:
				if not (e.kind == NetTransportEvent.Kind.PACKET and e.peer_id == p.remote_id):
					keep.append(e)
			remote._inbox = keep
		remote._inbox.append(NetTransportEvent.disconnected(p.remote_id, code))
	_peers.erase(peer_id)
	if graceful:
		_inbox.append(NetTransportEvent.disconnected(peer_id, 0))


func close() -> void:
	for id: Variant in _peers.keys():
		disconnect_peer(int(id), 0, false)
	var hub: NetLoopbackHub = _hub()
	if _port != 0 and hub != null:
		hub._release_listener(_port, self)
	_port = 0
	_connect_due_us = -1


func peer_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: Variant in _peers:
		out.append(int(k))
	out.sort()
	return out


func peer_state(peer_id: int) -> int:
	var p: _Peer = _peers.get(peer_id) as _Peer
	return NetProtocol.PeerState.GONE if p == null else p.state


func peer_address(peer_id: int) -> String:
	var p: _Peer = _peers.get(peer_id) as _Peer
	var remote: NetTransportLoopback = null if p == null else p.remote()
	return "" if remote == null else remote.address


func peer_stats(peer_id: int) -> NetPeerStats:
	var p: _Peer = _peers.get(peer_id) as _Peer
	return NetPeerStats.new() if p == null else p.stats.duplicate_stats()


func set_timeouts(_limit: int, _min_ms: int, _max_ms: int) -> void:
	pass


func local_port() -> int:
	return _port


func pop_traffic() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([_sent_bytes, _recv_bytes, _sent_pkts, _recv_pkts])
	_sent_bytes = 0
	_recv_bytes = 0
	_sent_pkts = 0
	_recv_pkts = 0
	return out
