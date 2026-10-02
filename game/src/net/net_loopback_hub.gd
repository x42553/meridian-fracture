class_name NetLoopbackHub
extends RefCounted
## In-process message switch connecting several NetTransportLoopback endpoints (docs/spec/net.md 3.2).
## The hub owns its endpoints; endpoints reference the hub and each other only weakly, so keep the hub in a
## variable for as long as the endpoints are in use.
## Zero latency: a message sent by one endpoint is in the remote endpoint's inbox immediately and becomes an
## event at the remote's next poll() (or at deliver_all()). Wrap an endpoint in NetTransportFault for latency.

## The shared clock (connect-failure timing). Manual by default so tests control it.
var clock: NetClock
## How long a connect to a missing / full listener takes to report DISCONNECTED (real ENet: CONNECT_TIMEOUT_MS).
var connect_fail_ms: int = NetProtocol.CONNECT_TIMEOUT_MS

var _endpoints: Dictionary = {}
var _listeners: Dictionary = {}
var _reserved: Dictionary = {}


func _init(clock_: NetClock = null) -> void:
	clock = clock_ if clock_ != null else NetClock.manual()


## The endpoint labelled `key` (created on first use). The label is hub-local; transport peer ids are assigned
## per connection (server = 1, remote clients 2, 3, ...).
func endpoint(key: int) -> NetTransportLoopback:
	if not _endpoints.has(key):
		_endpoints[key] = NetTransportLoopback.new(self)
	return _endpoints[key] as NetTransportLoopback


## Connects `client` to `host` directly (the host does not need to be listening on a known port): `client`
## sees `host` as peer 1, `host` assigns the next id >= 2. Returns the host-side peer id, or 0 on failure.
func connect_endpoints(client: NetTransportLoopback, host: NetTransportLoopback, connect_data: int = 0) -> int:
	return client._link_to(host, connect_data)


## Delivers every pending message of every endpoint into its event queue.
func deliver_all() -> void:
	for k: Variant in _endpoints:
		(_endpoints[k] as NetTransportLoopback)._pump()


## Marks a port as occupied so listen() skips it (port-scan tests).
func reserve_port(port: int) -> void:
	_reserved[port] = true


func release_port(port: int) -> void:
	_reserved.erase(port)


func _claim_port(port: int, host: NetTransportLoopback) -> bool:
	if _reserved.has(port) or (_listeners.has(port) and _listener(port) != null):
		return false
	_listeners[port] = weakref(host)
	return true


func _release_listener(port: int, host: NetTransportLoopback) -> void:
	var cur: WeakRef = _listeners.get(port) as WeakRef
	if cur != null and cur.get_ref() == host:
		_listeners.erase(port)


func _listener(port: int) -> NetTransportLoopback:
	var w: WeakRef = _listeners.get(port) as WeakRef
	return null if w == null else (w.get_ref() as NetTransportLoopback)
