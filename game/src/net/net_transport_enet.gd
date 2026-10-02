class_name NetTransportEnet
extends NetTransport
## NetTransport over Godot's ENetConnection / ENetPacketPeer (docs/spec/net.md 3.2, 5.1): reliable + ordered
## channels, quiet UDP port scan, dual-stack bind ("*" then "0.0.0.0"), own 6 s connect timeout, async
## hostname resolution, per-peer stats. No SceneTree needed.
##
## Peer ids: host = 1; a client sees the server as 1; remote clients get 2, 3, ... (never reused).
## A peer that is not STATE_CONNECTED is never asked for statistics (the engine logs an ERROR for that).

const _MAX_EVENTS_PER_POLL: int = 256
const _RESOLVE_LIMIT_MS: int = 5000

var _clock: NetClock
var _host: ENetConnection = null
var _is_client: bool = false
var _port: int = 0
var _peers: Dictionary = {}       # id -> ENetPacketPeer
var _ids: Dictionary = {}         # ENetPacketPeer instance id -> transport id
var _up: Dictionary = {}          # id -> true once EVENT_CONNECT was seen
var _addr: Dictionary = {}        # id -> String
var _stats: Dictionary = {}       # id -> NetPeerStats (byte counters; RTT copied from ENet while connected)
var _next_remote_id: int = 2
var _timeouts: PackedInt32Array = NetProtocol.TIMEOUTS_LOBBY
var _connect_deadline_us: int = -1
var _resolve_id: int = -1
var _resolve_deadline_us: int = -1
var _pending_port: int = 0
var _pending_data: int = 0


func _init(clock: NetClock = null) -> void:
	_clock = clock if clock != null else NetClock.real()


func listen(port: int, max_peers: int) -> int:
	if _host != null:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535 or max_peers < 1:
		return ERR_INVALID_PARAMETER
	for p in range(port, mini(port + NetProtocol.PORT_SCAN_COUNT, 65536)):
		# quiet probe first: a failed ENet bind logs an engine ERROR, a failed UDP bind does not
		var probe: PacketPeerUDP = PacketPeerUDP.new()
		var probe_err: int = probe.bind(p, "*")
		probe.close()
		if probe_err != OK:
			continue
		var host: ENetConnection = ENetConnection.new()
		var err: int = host.create_host_bound("*", p, max_peers, NetProtocol.CHANNEL_COUNT, 0, 0)
		if err != OK:
			err = host.create_host_bound("0.0.0.0", p, max_peers, NetProtocol.CHANNEL_COUNT, 0, 0)
		if err == OK:
			_host = host
			_port = p
			_is_client = false
			return OK
	return ERR_ALREADY_IN_USE


func connect_to(address: String, port: int, connect_data: int) -> int:
	if _host != null:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535 or address.is_empty():
		return ERR_INVALID_PARAMETER
	var host: ENetConnection = ENetConnection.new()
	var err: int = host.create_host(1, NetProtocol.CHANNEL_COUNT)
	if err != OK:
		return err
	_host = host
	_is_client = true
	_connect_deadline_us = _clock.now_us() + NetProtocol.CONNECT_TIMEOUT_MS * 1000
	if address.is_valid_ip_address():
		_start_connect(address, port, connect_data)
	else:
		_resolve_id = IP.resolve_hostname_queue_item(address)
		_resolve_deadline_us = _clock.now_us() + _RESOLVE_LIMIT_MS * 1000
		_pending_port = port
		_pending_data = connect_data
		if _resolve_id == IP.RESOLVER_INVALID_ID:
			_resolve_id = -1
			_fail_connect()
	return OK


func _start_connect(ip: String, port: int, data: int) -> void:
	var peer: ENetPacketPeer = _host.connect_to_host(ip, port, NetProtocol.CHANNEL_COUNT, data)
	if peer == null:
		_fail_connect()
		return
	_register(1, peer, ip)
	if _timeouts.size() == 3:
		peer.set_timeout(_timeouts[0], _timeouts[1], _timeouts[2])


func _fail_connect() -> void:
	_connect_deadline_us = -1
	var peer: ENetPacketPeer = _peers.get(1) as ENetPacketPeer
	if peer != null:
		peer.reset()
	_forget(1)
	_queue(NetTransportEvent.disconnected(1, 0))


func _register(id: int, peer: ENetPacketPeer, addr: String) -> void:
	_peers[id] = peer
	_ids[peer.get_instance_id()] = id
	_addr[id] = addr
	if not _stats.has(id):
		_stats[id] = NetPeerStats.new()


func _forget(id: int) -> void:
	var peer: ENetPacketPeer = _peers.get(id) as ENetPacketPeer
	if peer != null:
		_ids.erase(peer.get_instance_id())
	_peers.erase(id)
	_up.erase(id)
	_addr.erase(id)
	_stats.erase(id)


func poll() -> void:
	if _host == null:
		return
	var now: int = _clock.now_us()
	if _resolve_id >= 0:
		var st: int = IP.get_resolve_item_status(_resolve_id)
		if st == IP.RESOLVER_STATUS_DONE:
			var ip: String = IP.get_resolve_item_address(_resolve_id)
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
			if ip.is_empty():
				_fail_connect()
			else:
				_start_connect(ip, _pending_port, _pending_data)
		elif st == IP.RESOLVER_STATUS_ERROR or st == IP.RESOLVER_STATUS_NONE or now >= _resolve_deadline_us:
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
			_fail_connect()
	if _is_client and _connect_deadline_us >= 0 and not _up.has(1) and now >= _connect_deadline_us:
		_fail_connect()
	if _host == null:
		return
	for _n in _MAX_EVENTS_PER_POLL:
		var ev: Array = _host.service(0)
		var kind: int = int(ev[0])
		if kind == ENetConnection.EVENT_NONE or kind == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1] as ENetPacketPeer
		if peer == null:
			continue
		match kind:
			ENetConnection.EVENT_CONNECT:
				_on_connect(peer, int(ev[2]))
			ENetConnection.EVENT_DISCONNECT:
				var did: int = int(_ids.get(peer.get_instance_id(), 0))
				if did != 0:
					_forget(did)
					_queue(NetTransportEvent.disconnected(did, int(ev[2])))
			ENetConnection.EVENT_RECEIVE:
				var data: PackedByteArray = peer.get_packet()
				var rid: int = int(_ids.get(peer.get_instance_id(), 0))
				if rid != 0:
					var stats: NetPeerStats = _stats.get(rid) as NetPeerStats
					if stats != null:
						stats.bytes_in += data.size()
						stats.last_seen_ms = _clock.now_us() / 1000
					_queue(NetTransportEvent.packet(rid, int(ev[3]), data))


func _on_connect(peer: ENetPacketPeer, data: int) -> void:
	var id: int = int(_ids.get(peer.get_instance_id(), 0))
	if id == 0:
		if _is_client:
			return
		id = _next_remote_id
		_next_remote_id += 1
		_register(id, peer, peer.get_remote_address())
		if _timeouts.size() == 3:
			peer.set_timeout(_timeouts[0], _timeouts[1], _timeouts[2])
	_up[id] = true
	if _is_client:
		_connect_deadline_us = -1
	_queue(NetTransportEvent.connected(id, data, peer.get_remote_address()))


func send(peer_id: int, channel: int, data: PackedByteArray) -> int:
	if channel < 0 or channel >= NetProtocol.CHANNEL_COUNT or data.is_empty():
		return ERR_INVALID_PARAMETER
	var peer: ENetPacketPeer = _peers.get(peer_id) as ENetPacketPeer
	if peer == null or not _up.has(peer_id) or peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_UNAVAILABLE
	var err: int = peer.send(channel, data, ENetPacketPeer.FLAG_RELIABLE)
	if err == OK:
		var stats: NetPeerStats = _stats.get(peer_id) as NetPeerStats
		if stats != null:
			stats.bytes_out += data.size()
	return err


func flush() -> void:
	if _host != null:
		_host.flush()


func disconnect_peer(peer_id: int, code: int, graceful: bool) -> void:
	var peer: ENetPacketPeer = _peers.get(peer_id) as ENetPacketPeer
	if peer == null:
		return
	if peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		# still connecting / already closing: nothing to say to the remote, just forget it
		peer.reset()
		_forget(peer_id)
		return
	if graceful:
		peer.peer_disconnect_later(code)
	else:
		peer.peer_disconnect_now(code)
		_host.flush()
		_forget(peer_id)


func close() -> void:
	if _host == null:
		return
	for id: Variant in _peers.keys():
		var peer: ENetPacketPeer = _peers[id] as ENetPacketPeer
		if peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			peer.peer_disconnect_now(0)
	_host.flush()
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
	_resolve_id = -1
	_host.destroy()
	_host = null
	_peers.clear()
	_ids.clear()
	_up.clear()
	_addr.clear()
	_stats.clear()
	_connect_deadline_us = -1
	_port = 0


func peer_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: Variant in _peers:
		out.append(int(k))
	out.sort()
	return out


func peer_state(peer_id: int) -> int:
	if not _peers.has(peer_id):
		return NetProtocol.PeerState.GONE
	return NetProtocol.PeerState.CONNECTED if _up.has(peer_id) else NetProtocol.PeerState.CONNECTING


func peer_address(peer_id: int) -> String:
	return str(_addr.get(peer_id, ""))


func peer_stats(peer_id: int) -> NetPeerStats:
	var cached: NetPeerStats = _stats.get(peer_id) as NetPeerStats
	if cached == null:
		return NetPeerStats.new()
	var peer: ENetPacketPeer = _peers.get(peer_id) as ENetPacketPeer
	if peer != null and _up.has(peer_id) and peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		cached.rtt_ms = peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		cached.rtt_var_ms = peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)
		cached.last_rtt_ms = peer.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)
		cached.packet_loss = peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	return cached.duplicate_stats()


func set_timeouts(limit: int, min_ms: int, max_ms: int) -> void:
	_timeouts = PackedInt32Array([limit, min_ms, max_ms])
	for k: Variant in _peers:
		(_peers[k] as ENetPacketPeer).set_timeout(limit, min_ms, max_ms)


func local_port() -> int:
	if _host == null:
		return 0
	return _port if not _is_client else _host.get_local_port()


func pop_traffic() -> PackedInt64Array:
	if _host == null:
		return PackedInt64Array([0, 0, 0, 0])
	return PackedInt64Array([
		int(_host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)),
		int(_host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)),
		int(_host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)),
		int(_host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)),
	])
