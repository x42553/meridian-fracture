class_name NetTransportFault
extends NetTransport
## Decorator that applies a NetFaultProfile (latency, jitter, loss, duplication, reorder, freeze, bandwidth,
## forced disconnect) to any NetTransport under a NetClock, with a seeded RNG so runs are reproducible
## (docs/spec/net.md 5.11).
##
## Model (send side): every send() gets a delivery time; poll() hands the messages that are due to the inner
## transport (so the inner transport's own delivery adds at most one poll interval). Ordered mode reproduces
## ENet reliable channels: a loss event adds one rto (geometric, max 8) and delivery is FIFO per
## (peer, channel) with head-of-line blocking. Unordered mode reproduces raw UDP: loss drops the message,
## reorder adds extra delay, dup sends a copy later. During a freeze the endpoint neither services the inner
## transport nor releases messages; events already received are held back too.

var _inner: NetTransport
var _profile: NetFaultProfile
var _clock: NetClock
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t0_us: int = 0
var _out: Array[_Item] = []
var _seq: int = 0
var _last_at: Dictionary = {}
var _peer_last_at: Dictionary = {}
var _link_free_at: Dictionary = {}
var _last_released: Dictionary = {}
var _corrupt: Dictionary = {}
var _freeze_until_us: int = -1
var _cut: bool = false
var _stats: Dictionary = {}

## When true every scheduled delivery time (us, absolute clock time) is appended to `schedule`
## (reproducibility tests: same seed => identical schedule).
var record_schedule: bool = false
var schedule: PackedInt64Array = PackedInt64Array()


class _Item extends RefCounted:
	var is_disconnect: bool = false
	var peer: int = 0
	var channel: int = 0
	var data: PackedByteArray = PackedByteArray()
	var code: int = 0
	var graceful: bool = true
	var at: int = 0
	var seq: int = 0


static func wrap(inner: NetTransport, profile: NetFaultProfile, clock: NetClock, rng_seed: int) -> NetTransportFault:
	var t: NetTransportFault = NetTransportFault.new()
	t._inner = inner
	t._profile = profile
	t._clock = clock
	t._rng.seed = rng_seed
	t._t0_us = clock.now_us()
	t._reset_stats()
	return t


func _reset_stats() -> void:
	_stats = {"sent": 0, "delayed": 0, "dropped": 0, "retransmitted": 0, "duplicated": 0, "reordered": 0,
		"corrupted": 0, "held": 0, "delivered": 0, "max_delay_ms": 0.0}


func set_profile(p: NetFaultProfile) -> void:
	_profile = p


## Freezes this endpoint (neither sends nor delivers) for `ms` from now: the "laptop lid closed" case.
func freeze_for_ms(ms: int) -> void:
	_freeze_until_us = maxi(_freeze_until_us, _clock.now_us() + ms * 1000)


## Test hook: flips one payload byte of the next message sent to that peer on that channel.
func corrupt_next(peer_id: int, channel: int) -> void:
	_corrupt[peer_id * 8 + channel] = true


## Counters: sent, delayed, dropped (loss events), retransmitted (ordered mode: loss events that cost an rto),
## duplicated, reordered (actual inversions observed at release), corrupted, held (messages whose delivery
## was pushed back by a freeze), delivered, max_delay_ms.
func stats() -> Dictionary:
	return _stats.duplicate()


## Messages still waiting for their delivery time.
func pending_count() -> int:
	return _out.size()


func inner_transport() -> NetTransport:
	return _inner


# ---- delegation -----------------------------------------------------------------------------------------

func listen(port: int, max_peers: int) -> int:
	return _inner.listen(port, max_peers)


func connect_to(address: String, port: int, connect_data: int) -> int:
	return _inner.connect_to(address, port, connect_data)


func flush() -> void:
	_inner.flush()


func peer_ids() -> PackedInt32Array:
	return _inner.peer_ids()


func peer_state(peer_id: int) -> int:
	return _inner.peer_state(peer_id)


func peer_address(peer_id: int) -> String:
	return _inner.peer_address(peer_id)


func peer_stats(peer_id: int) -> NetPeerStats:
	return _inner.peer_stats(peer_id)


func set_timeouts(limit: int, min_ms: int, max_ms: int) -> void:
	_inner.set_timeouts(limit, min_ms, max_ms)


func local_port() -> int:
	return _inner.local_port()


func pop_traffic() -> PackedInt64Array:
	return _inner.pop_traffic()


func close() -> void:
	_out.clear()
	_inner.close()


# ---- freeze helpers ---------------------------------------------------------------------------------------

## End of the freeze covering `t` (us), or -1 when not frozen at `t`.
func _freeze_end(t: int) -> int:
	var end: int = -1
	if t < _freeze_until_us:
		end = _freeze_until_us
	if _profile.freeze_every_ms > 0 and _profile.freeze_ms > 0:
		var period: int = _profile.freeze_every_ms * 1000
		var el: int = t - _t0_us
		if el >= period and (el % period) < _profile.freeze_ms * 1000:
			end = maxi(end, t - (el % period) + _profile.freeze_ms * 1000)
	return end


# ---- send path ---------------------------------------------------------------------------------------------

func _uniform(lo: float, hi: float) -> float:
	return lo + _rng.randf() * (hi - lo)


func _insert(item: _Item) -> void:
	_seq += 1
	item.seq = _seq
	var i: int = _out.size()
	while i > 0 and _out[i - 1].at > item.at:
		i -= 1
	_out.insert(i, item)
	if record_schedule:
		schedule.append(item.at)


func send(peer_id: int, channel: int, data: PackedByteArray) -> int:
	if channel < 0 or channel >= NetProtocol.CHANNEL_COUNT or data.is_empty():
		return ERR_INVALID_PARAMETER
	if _cut or _inner.peer_state(peer_id) != NetProtocol.PeerState.CONNECTED:
		return ERR_UNAVAILABLE
	var p: NetFaultProfile = _profile
	var now: int = _clock.now_us()
	var payload: PackedByteArray = data
	var ckey: int = peer_id * 8 + channel
	if _corrupt.has(ckey):
		_corrupt.erase(ckey)
		payload = data.duplicate()
		payload[payload.size() - 1] = payload[payload.size() - 1] ^ 0x01
		_stats["corrupted"] = int(_stats["corrupted"]) + 1
	_stats["sent"] = int(_stats["sent"]) + 1
	var base: int = now
	var fe: int = _freeze_end(now)
	if fe >= 0:
		base = fe
		_stats["held"] = int(_stats["held"]) + 1
	var lat_ms: float = maxf(0.1, p.latency_ms + (_uniform(-p.jitter_ms, p.jitter_ms) if p.jitter_ms > 0.0 else 0.0))
	var lat_us: int = int(lat_ms * 1000.0)
	var tx_us: int = 0
	if p.bandwidth_kbps > 0:
		tx_us = payload.size() * 8 * 1000 / p.bandwidth_kbps
		var start: int = maxi(base, int(_link_free_at.get(peer_id, 0)))
		_link_free_at[peer_id] = start + tx_us
		base = start
	if p.ordered:
		var k: int = 0
		while p.loss_pct > 0.0 and k < 8 and _rng.randf() * 100.0 < p.loss_pct:
			k += 1
		if k > 0:
			_stats["dropped"] = int(_stats["dropped"]) + k
			_stats["retransmitted"] = int(_stats["retransmitted"]) + k
		var at: int = base + tx_us + lat_us + int(float(k) * p.effective_rto_ms() * 1000.0)
		at = maxi(at, int(_last_at.get(ckey, 0)) + 1)
		_last_at[ckey] = at
		_peer_last_at[peer_id] = maxi(int(_peer_last_at.get(peer_id, 0)), at)
		_enqueue_send(peer_id, channel, payload, at, now)
	else:
		if p.loss_pct > 0.0 and _rng.randf() * 100.0 < p.loss_pct:
			_stats["dropped"] = int(_stats["dropped"]) + 1
			return OK
		var extra_us: int = 0
		if p.reorder_pct > 0.0 and _rng.randf() * 100.0 < p.reorder_pct:
			extra_us = int(_uniform(0.0, 2.0 * lat_ms + p.jitter_ms) * 1000.0)
		var at2: int = base + tx_us + lat_us + extra_us
		_enqueue_send(peer_id, channel, payload, at2, now)
		if p.dup_pct > 0.0 and _rng.randf() * 100.0 < p.dup_pct:
			_stats["duplicated"] = int(_stats["duplicated"]) + 1
			_enqueue_send(peer_id, channel, payload, at2 + int(_uniform(0.0, lat_ms + p.jitter_ms) * 1000.0), now)
	return OK


func _enqueue_send(peer_id: int, channel: int, payload: PackedByteArray, at: int, now: int) -> void:
	var it: _Item = _Item.new()
	it.peer = peer_id
	it.channel = channel
	it.data = payload
	it.at = at
	if at > now:
		_stats["delayed"] = int(_stats["delayed"]) + 1
	_stats["max_delay_ms"] = maxf(float(_stats["max_delay_ms"]), float(at - now) / 1000.0)
	_insert(it)


func disconnect_peer(peer_id: int, code: int, graceful: bool) -> void:
	if not graceful:
		var keep: Array[_Item] = []
		for it in _out:
			if it.peer != peer_id:
				keep.append(it)
		_out = keep
		_inner.disconnect_peer(peer_id, code, false)
		return
	var now: int = _clock.now_us()
	var at: int = maxi(now + int(maxf(0.1, _profile.latency_ms) * 1000.0), int(_peer_last_at.get(peer_id, 0)) + 1)
	var it2: _Item = _Item.new()
	it2.is_disconnect = true
	it2.peer = peer_id
	it2.code = code
	it2.at = at
	_insert(it2)


# ---- poll path -----------------------------------------------------------------------------------------------

func poll() -> void:
	var now: int = _clock.now_us()
	if _profile.disconnect_after_ms > 0 and not _cut and now - _t0_us >= _profile.disconnect_after_ms * 1000:
		_cut_all()
	if _freeze_end(now) >= 0:
		return
	while not _out.is_empty() and _out[0].at <= now:
		var it: _Item = _out.pop_front()
		_release(it)
	_inner.poll()
	for e in _inner.take_events():
		_queue(e)


func _release(it: _Item) -> void:
	if it.is_disconnect:
		_inner.disconnect_peer(it.peer, it.code, true)
		return
	var key: int = it.peer * 8 + it.channel
	if it.seq < int(_last_released.get(key, 0)):
		_stats["reordered"] = int(_stats["reordered"]) + 1
	else:
		_last_released[key] = it.seq
	if _inner.send(it.peer, it.channel, it.data) == OK:
		_stats["delivered"] = int(_stats["delivered"]) + 1


func _cut_all() -> void:
	_cut = true
	_out.clear()
	for id in _inner.peer_ids():
		_inner.disconnect_peer(id, 0, false)
		_queue(NetTransportEvent.disconnected(id, 0))


func take_events() -> Array[NetTransportEvent]:
	if _freeze_end(_clock.now_us()) >= 0:
		var none: Array[NetTransportEvent] = []
		return none
	return super.take_events()
