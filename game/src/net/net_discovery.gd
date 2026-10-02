class_name NetDiscovery
extends RefCounted
## LAN discovery over UDP broadcast (docs/spec/net.md 3.6, 4.4 datagram, 5.2). Announce-only protocol: a host sends one
## <= 128 byte datagram per second to every target (127.0.0.1 + broadcast candidates); a browser binds
## DISCOVERY_PORT and keeps a table of games keyed by (source ip, session id) that expire after 4 s without an
## announce. The datagram is never answered, so spoofed packets cannot trigger replies.
##
## Announcing and browsing use separate sockets and can run in one instance. Time comes from the injected NetClock.

signal entries_changed()

const MAGIC: PackedByteArray = [0x4D, 0x46, 0x44, 0x53]
const LAYOUT_VERSION: int = 1
const KIND_ANNOUNCE: int = 1
const KIND_CLOSED: int = 2
const MIN_DATAGRAM: int = 30
const MAX_DATAGRAM: int = 128
const MAX_ENTRIES: int = 64
const MAX_TARGETS: int = 12
const MAX_PER_SOURCE_PER_S: int = 5
const IFACE_REFRESH_MS: int = 10000
const ANNOUNCE_OK_WINDOW_MS: int = 10000

## "" or "port_in_use" / "bind_failed" (UI hint: join by IP).
var browse_error: String = ""
## false when every target failed for more than 10 s (UI hint: firewall / local-network permission).
var announce_ok: bool = true
## UDP port used by both halves (tests use another port).
var port: int = NetProtocol.DISCOVERY_PORT
## Accept datagrams from non-private source addresses (settings net/allow_public_discovery).
var allow_public: bool = false
## Test hook: (target: String, data: PackedByteArray) -> int (Error) replaces the real socket send.
var send_override: Callable = Callable()

var _clock: NetClock = null
var _game_version: String = ""
var _proto: int = NetProtocol.PROTO_VERSION
var _sim: int = 0
var _data_hash: int = 0
var _get_info: Callable = Callable()
var _game_port: int = 0
var _announcing: bool = false
var _tx: PacketPeerUDP = null
var _targets_override: PackedStringArray = PackedStringArray()
var _targets: PackedStringArray = PackedStringArray()
var _targets_at_us: int = -1
var _next_send_us: int = 0
var _seq: int = 0
var _last_ok_us: int = 0
var _fail_count: Dictionary = {}
var _disabled_until_us: Dictionary = {}
var _rx: PacketPeerUDP = null
var _browsing: bool = false
var _browse_started_us: int = 0
var _heard_any: bool = false
var _table: Dictionary = {}
var _src_window: Dictionary = {}
var _last_info: Dictionary = {}


func setup(clock: NetClock, game_version: String, proto: int, sim_version: int, data_hash: int) -> void:
	_clock = clock
	_game_version = game_version
	_proto = proto
	_sim = sim_version
	_data_hash = data_hash


# ---- pure helpers -----------------------------------------------------------------------------------------

## Limited broadcast plus the /24 and /16 broadcast of every private-looking address (spec 5.2). Pure function.
static func broadcast_candidates(ipv4_addresses: PackedStringArray) -> PackedStringArray:
	var valid: Array = []
	for ip: String in ipv4_addresses:
		var p: PackedStringArray = ip.split(".")
		if p.size() != 4:
			continue
		var ok: bool = true
		var v: PackedInt32Array = PackedInt32Array()
		for s: String in p:
			if s.is_empty() or not s.is_valid_int() or s.length() > 3 or s.to_int() < 0 or s.to_int() > 255:
				ok = false
				break
			v.append(s.to_int())
		if ok:
			valid.append(v)
	var have_other: bool = false
	for v: PackedInt32Array in valid:
		if v[0] != 127 and not (v[0] == 169 and v[1] == 254):
			have_other = true
	var out: PackedStringArray = PackedStringArray()
	out.append("255.255.255.255")
	for v: PackedInt32Array in valid:
		if v[0] == 127 or (v[0] == 169 and v[1] == 254 and have_other):
			continue
		var c24: String = "%d.%d.%d.255" % [v[0], v[1], v[2]]
		var c16: String = "%d.%d.255.255" % [v[0], v[1]]
		for c: String in [c24, c16]:
			if not out.has(c):
				out.append(c)
		if v[0] == 10 and not out.has("10.255.255.255"):
			out.append("10.255.255.255")
	if out.size() > MAX_TARGETS:
		out = out.slice(0, MAX_TARGETS)
	return out


## Datagram bytes from field values: kind (default ANNOUNCE), proto_version, session_id, game_port, data_hash,
## sim_version, flags (or the bools has_password / in_progress / full / spectators_allowed / dedicated), humans,
## slots_total, slots_free, map_family, map_size (cells), ai_count, host_name (<= 24 B), game_version (<= 16 B).
static func encode_datagram(f: Dictionary) -> PackedByteArray:
	var flags: int = int(f.get("flags", 0))
	if bool(f.get("has_password", false)):
		flags |= NetDiscoveryEntry.F_PASSWORD
	if bool(f.get("in_progress", false)):
		flags |= NetDiscoveryEntry.F_IN_PROGRESS
	if bool(f.get("full", false)):
		flags |= NetDiscoveryEntry.F_FULL
	if bool(f.get("spectators_allowed", false)):
		flags |= NetDiscoveryEntry.F_SPECTATORS
	if bool(f.get("dedicated", false)):
		flags |= NetDiscoveryEntry.F_DEDICATED
	var w: NetWriter = NetWriter.new()
	w.raw(MAGIC).u8(LAYOUT_VERSION).u8(int(f.get("kind", KIND_ANNOUNCE)))
	w.u16(int(f.get("proto_version", NetProtocol.PROTO_VERSION))).u32(int(f.get("session_id", 0))).u16(int(f.get("game_port", 0)))
	w.u32(int(f.get("data_hash", 0))).u32(int(f.get("sim_version", 0))).u8(flags)
	w.u8(int(f.get("humans", 0))).u8(int(f.get("slots_total", 0))).u8(int(f.get("slots_free", 0)))
	w.u8(int(f.get("map_family", 0))).u8(clampi(int(f.get("map_size", 128)) / 8, 0, 255)).u8(int(f.get("ai_count", 0))).u8(0)
	w.str_(str(f.get("host_name", "")), 24).str_(str(f.get("game_version", "")), 16)
	var out: PackedByteArray = w.to_bytes()
	return out if out.size() <= MAX_DATAGRAM else PackedByteArray()


## Field dictionary (keys of encode_datagram plus layout_version) or {} for anything that is not a valid
## version-1 announce/closed datagram: wrong length, magic, layout, kind, oversize or non-UTF-8 strings, leftovers.
static func decode_datagram(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < MIN_DATAGRAM or bytes.size() > MAX_DATAGRAM:
		return {}
	for i: int in 4:
		if bytes[i] != MAGIC[i]:
			return {}
	if bytes[4] != LAYOUT_VERSION or (bytes[5] != KIND_ANNOUNCE and bytes[5] != KIND_CLOSED):
		return {}
	var r: NetReader = NetReader.new(bytes, 6)
	var out: Dictionary = {"layout_version": bytes[4], "kind": bytes[5]}
	out["proto_version"] = r.u16()
	out["session_id"] = r.u32()
	out["game_port"] = r.u16()
	out["data_hash"] = r.u32()
	out["sim_version"] = r.u32()
	var flags: int = r.u8()
	out["flags"] = flags
	out["has_password"] = (flags & NetDiscoveryEntry.F_PASSWORD) != 0
	out["in_progress"] = (flags & NetDiscoveryEntry.F_IN_PROGRESS) != 0
	out["full"] = (flags & NetDiscoveryEntry.F_FULL) != 0
	out["spectators_allowed"] = (flags & NetDiscoveryEntry.F_SPECTATORS) != 0
	out["dedicated"] = (flags & NetDiscoveryEntry.F_DEDICATED) != 0
	out["humans"] = r.u8()
	out["slots_total"] = r.u8()
	out["slots_free"] = r.u8()
	out["map_family"] = r.u8()
	out["map_size"] = r.u8() * 8
	out["ai_count"] = r.u8()
	r.u8()
	out["host_name"] = r.str_(24)
	out["game_version"] = r.str_(16)
	if not r.ok or r.left() != 0:
		return {}
	return out


## "ip:port" strings of this machine to tell friends (private IPv4 first, then the others).
static func advertised_addresses(game_port: int) -> PackedStringArray:
	var priv: PackedStringArray = PackedStringArray()
	var other: PackedStringArray = PackedStringArray()
	for itf: Variant in IP.get_local_interfaces():
		for a: Variant in (itf as Dictionary).get("addresses", []) as Array:
			var s: String = str(a)
			if s.contains(":") or not s.is_valid_ip_address() or s.begins_with("127.") or s.begins_with("169.254."):
				continue
			var entry: String = "%s:%d" % [s, game_port]
			if NetProtocol.is_private_ipv4(s):
				if not priv.has(entry):
					priv.append(entry)
			elif not other.has(entry):
				other.append(entry)
	priv.append_array(other)
	return priv


# ---- announce (host) --------------------------------------------------------------------------------------

## Tests / CI without broadcast: send only to these targets (empty array = automatic targets).
func set_targets_override(targets: PackedStringArray) -> void:
	_targets_override = targets
	_targets_at_us = -1


## get_info: () -> Dictionary with session_id, humans, slots_total, slots_free, map_family, map_size, ai_count,
## host_name and the flag bools (see encode_datagram). Sends every DISCOVERY_INTERVAL_MS (+-100 ms).
func start_announce(get_info: Callable, game_port: int) -> void:
	_get_info = get_info
	_game_port = game_port
	_announcing = true
	_tx = PacketPeerUDP.new()
	_tx.set_broadcast_enabled(true)
	var now: int = _clock.now_us()
	_next_send_us = now
	_last_ok_us = now
	announce_ok = true
	_fail_count.clear()
	_disabled_until_us.clear()
	_targets_at_us = -1


## send_closed: tell browsers to drop the entry at once.
func stop_announce(send_closed: bool = true) -> void:
	if not _announcing:
		return
	if send_closed:
		_send_all(KIND_CLOSED)
	_announcing = false
	if _tx != null:
		_tx.close()
		_tx = null


func is_announcing() -> bool:
	return _announcing


func _refresh_targets(now: int) -> void:
	if not _targets_override.is_empty():
		_targets = _targets_override
		_targets_at_us = now
		return
	if _targets_at_us >= 0 and now - _targets_at_us < IFACE_REFRESH_MS * 1000:
		return
	var ips: PackedStringArray = PackedStringArray()
	for itf: Variant in IP.get_local_interfaces():
		for a: Variant in (itf as Dictionary).get("addresses", []) as Array:
			var s: String = str(a)
			if not s.contains(":") and s.is_valid_ip_address():
				ips.append(s)
	var t: PackedStringArray = PackedStringArray(["127.0.0.1"])
	t.append_array(broadcast_candidates(ips))
	_targets = t
	_targets_at_us = now


func _build_datagram(kind: int) -> PackedByteArray:
	var info: Dictionary = {}
	if kind == KIND_ANNOUNCE and _get_info.is_valid():
		info = (_get_info.call() as Dictionary).duplicate()
		_last_info = info
	elif kind == KIND_CLOSED:
		info = _last_info.duplicate()
		if info.is_empty() and _get_info.is_valid():
			info = (_get_info.call() as Dictionary).duplicate()
	info["kind"] = kind
	info["proto_version"] = _proto
	info["sim_version"] = _sim
	info["data_hash"] = _data_hash
	info["game_port"] = _game_port
	info["game_version"] = _game_version
	return encode_datagram(info)


func _send_all(kind: int) -> void:
	var now: int = _clock.now_us()
	_refresh_targets(now)
	var data: PackedByteArray = _build_datagram(kind)
	if data.is_empty():
		return
	for t: String in _targets:
		if int(_disabled_until_us.get(t, 0)) > now:
			continue
		var err: int = _send_one(t, data)
		if err == OK:
			_fail_count[t] = 0
			_last_ok_us = now
		else:
			var n: int = int(_fail_count.get(t, 0)) + 1
			_fail_count[t] = n
			if n >= NetProtocol.DISCOVERY_BREAKER_FAILS:
				_fail_count[t] = 0
				_disabled_until_us[t] = now + NetProtocol.DISCOVERY_BREAKER_MS * 1000


func _send_one(target: String, data: PackedByteArray) -> int:
	if send_override.is_valid():
		return int(send_override.call(target, data))
	if _tx == null:
		return ERR_UNCONFIGURED
	var e: int = _tx.set_dest_address(target, port)
	if e != OK:
		return e
	return _tx.put_packet(data)


## true while `target` is switched off by the circuit breaker.
func target_disabled(target: String) -> bool:
	return int(_disabled_until_us.get(target, 0)) > _clock.now_us()


# ---- browse (client) --------------------------------------------------------------------------------------

## Binds the discovery port on 0.0.0.0. ERR_UNAVAILABLE (browse_error "port_in_use") when another instance listens.
func start_browse() -> int:
	stop_browse()
	browse_error = ""
	var s: PacketPeerUDP = PacketPeerUDP.new()
	var e: int = s.bind(port, "0.0.0.0")
	if e != OK:
		browse_error = "port_in_use" if (e == ERR_UNAVAILABLE or e == ERR_ALREADY_IN_USE) else "bind_failed"
		s.close()
		return ERR_UNAVAILABLE if browse_error == "port_in_use" else e
	_rx = s
	_browsing = true
	_browse_started_us = _clock.now_us()
	_heard_any = false
	return OK


func stop_browse() -> void:
	_browsing = false
	if _rx != null:
		_rx.close()
		_rx = null
	if not _table.is_empty():
		_table.clear()
		entries_changed.emit()


func is_browsing() -> bool:
	return _browsing


## true when nothing at all was heard for 8 s after start_browse() (UI: show the firewall / permission help).
func browse_silent() -> bool:
	return _browsing and not _heard_any and _clock.now_us() - _browse_started_us >= 8_000_000


func local_port() -> int:
	return _rx.get_local_port() if _rx != null else 0


func poll() -> void:
	var now: int = _clock.now_us()
	if _announcing:
		if now >= _next_send_us:
			_send_all(KIND_ANNOUNCE)
			_seq += 1
			var jitter: int = int(NetProtocol.mix32(_seq * 2654435761 + _game_port) % 201) - 100
			_next_send_us = now + (NetProtocol.DISCOVERY_INTERVAL_MS + jitter) * 1000
		announce_ok = now - _last_ok_us <= ANNOUNCE_OK_WINDOW_MS * 1000
	if _browsing and _rx != null:
		var n: int = 0
		while _rx.get_available_packet_count() > 0 and n < 64:
			n += 1
			var pkt: PackedByteArray = _rx.get_packet()
			if _rx.get_packet_error() != OK:
				continue
			handle_datagram(_rx.get_packet_ip(), pkt)
	_expire(now)


## Feeds one received datagram (public for tests). `source_ip` is the datagram's source address.
func handle_datagram(source_ip: String, bytes: PackedByteArray) -> void:
	if _clock == null:
		return
	var now: int = _clock.now_us()
	if not _source_allowed(source_ip, now):
		return
	if not allow_public and not NetProtocol.is_private_ipv4(source_ip):
		return
	var d: Dictionary = decode_datagram(bytes)
	if d.is_empty():
		return
	_heard_any = true
	var key: String = "%s#%d" % [source_ip, int(d["session_id"])]
	if int(d["kind"]) == KIND_CLOSED:
		if _table.erase(key):
			entries_changed.emit()
		return
	var e: NetDiscoveryEntry = _table.get(key) as NetDiscoveryEntry
	var is_new: bool = e == null
	if is_new:
		if _table.size() >= MAX_ENTRIES:
			return
		e = NetDiscoveryEntry.new()
		_table[key] = e
	var before: String = "" if is_new else e.signature()
	e.address = source_ip
	e.port = int(d["game_port"])
	e.host_name = str(d["host_name"])
	e.game_version = str(d["game_version"])
	e.proto_version = int(d["proto_version"])
	e.sim_version = int(d["sim_version"])
	e.data_hash = int(d["data_hash"])
	e.session_id = int(d["session_id"])
	e.flags = int(d["flags"])
	e.humans = int(d["humans"])
	e.slots_total = int(d["slots_total"])
	e.slots_free = int(d["slots_free"])
	e.ai_count = int(d["ai_count"])
	e.map_family = int(d["map_family"])
	e.map_size = int(d["map_size"])
	e.last_seen_ms = now / 1000
	e.mismatch = "protocol" if e.proto_version != _proto else ("simulation" if e.sim_version != _sim else ("game data" if e.data_hash != _data_hash else ""))
	e.compatible = e.mismatch == ""
	if is_new or e.signature() != before:
		entries_changed.emit()


func _source_allowed(ip: String, now: int) -> bool:
	if _src_window.size() > 256:
		_src_window.clear()
	var w: Array = _src_window.get(ip, [now, 0]) as Array
	if now - int(w[0]) >= 1_000_000:
		w = [now, 0]
	w[1] = int(w[1]) + 1
	_src_window[ip] = w
	return int(w[1]) <= MAX_PER_SOURCE_PER_S


func _expire(now: int) -> void:
	var dead: Array = []
	for k: Variant in _table:
		var e: NetDiscoveryEntry = _table[k] as NetDiscoveryEntry
		if now / 1000 - e.last_seen_ms > NetProtocol.DISCOVERY_STALE_MS:
			dead.append(k)
	for k: Variant in dead:
		_table.erase(k)
	if not dead.is_empty():
		entries_changed.emit()


## Live entries sorted by (host_name, address).
func entries() -> Array[NetDiscoveryEntry]:
	_expire(_clock.now_us())
	var out: Array[NetDiscoveryEntry] = []
	for k: Variant in _table:
		out.append(_table[k] as NetDiscoveryEntry)
	out.sort_custom(func(a: NetDiscoveryEntry, b: NetDiscoveryEntry) -> bool:
		if a.host_name != b.host_name:
			return a.host_name < b.host_name
		return a.address < b.address)
	return out


## Stops both halves and forgets all entries.
func close() -> void:
	stop_announce(true)
	stop_browse()
