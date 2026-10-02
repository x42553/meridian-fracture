class_name NetDelayPolicy
extends RefCounted
## Adaptive input delay (docs/spec/net.md 5.5.6). Host-only, wall-clock driven, outside the simulation: it only
## proposes a new D; the decision travels inside a bundle (CK_INPUT_DELAY) so every peer applies it at the same turn.
## Floats are fine here (never part of the deterministic core).

const RING_MAX: int = 20
const RAISE_COOLDOWN_MS: int = 1000
const STALL_RAISE_COOLDOWN_MS: int = 2000

class PeerEntry extends RefCounted:
	var rtt_ms: float = 0.0
	var jit_ms: float = 0.0
	var samples: int = 0
	var quarantine_until_ms: int = 0
	var ring: Array = []  # [t_ms, slack_min_ms, stall_ms]


var _d_min: int = NetProtocol.D_MIN_LAN
var _d_max: int = NetProtocol.D_MAX
var _turn_ms: int = NetProtocol.TURN_MS
var _peers: Dictionary = {}
var last_change_ms: int = 0
var below_since_ms: int = -1


## turn_ms = 100 * 100 / speed_pct (wall ms per turn).
func configure(d_min: int, d_max: int, turn_ms: int) -> void:
	_d_min = clampi(d_min, 1, NetProtocol.D_MAX)
	_d_max = clampi(d_max, _d_min, NetProtocol.D_MAX)
	_turn_ms = maxi(turn_ms, 1)


## Restarts the cooldowns at `now_ms` (match start / a decided change) and forgets nothing else.
func reset(now_ms: int, _d: int) -> void:
	last_change_ms = now_ms
	below_since_ms = -1


func get_turn_ms() -> int:
	return _turn_ms


func feed_pong(peer_id: int, now_ms: int, rtt_ms: int, slack_min_ms: int, stall_ms: int, _episodes: int, hitch: bool) -> void:
	var c: PeerEntry = _peers.get(peer_id) as PeerEntry
	if c == null:
		c = PeerEntry.new()
		_peers[peer_id] = c
	if hitch or rtt_ms > NetProtocol.HITCH_MS:
		c.quarantine_until_ms = now_ms + NetProtocol.QUARANTINE_MS
		return
	if now_ms < c.quarantine_until_ms:
		return
	var s: float = float(rtt_ms)
	if c.samples == 0:
		c.rtt_ms = s
		c.jit_ms = 0.0
	else:
		c.jit_ms += (absf(s - c.rtt_ms) - c.jit_ms) / 8.0
		c.rtt_ms += (s - c.rtt_ms) / 8.0
	c.samples += 1
	c.ring.append([now_ms, slack_min_ms, stall_ms])
	while c.ring.size() > RING_MAX:
		c.ring.pop_front()


func remove_peer(peer_id: int) -> void:
	_peers.erase(peer_id)


## Desired D (== current_d when unchanged). Call every DELAY_EVAL_MS.
func evaluate(now_ms: int, current_d: int) -> int:
	var need_ms: float = 0.0
	var stall10: int = 0
	var stall8: int = 0
	var min_slack8: int = 1 << 30
	var have_slack: bool = false
	for pid: Variant in _peers:
		var c: PeerEntry = _peers[pid] as PeerEntry
		if c.samples == 0:
			continue
		need_ms = maxf(need_ms, c.rtt_ms + 2.0 * c.jit_ms + float(NetProtocol.DELAY_FRAME_MARGIN_MS))
		var s10: int = 0
		var s8: int = 0
		for r: Variant in c.ring:
			var rec: Array = r as Array
			var t: int = int(rec[0])
			if t >= now_ms - 10000:
				s10 += int(rec[2])
			if t >= now_ms - 8000:
				s8 += int(rec[2])
				min_slack8 = mini(min_slack8, int(rec[1]))
				have_slack = true
		stall10 = maxi(stall10, s10)
		stall8 = maxi(stall8, s8)
	var d_target: int = clampi(ceili(need_ms / float(_turn_ms)), _d_min, _d_max)
	var since: int = now_ms - last_change_ms
	var new_d: int = current_d
	if d_target > current_d and since >= RAISE_COOLDOWN_MS:
		new_d = d_target
	elif stall10 >= NetProtocol.DELAY_RAISE_STALL_MS and current_d < _d_max and since >= STALL_RAISE_COOLDOWN_MS:
		new_d = current_d + 1
	elif d_target < current_d and have_slack and stall8 == 0 and min_slack8 >= _turn_ms + NetProtocol.DELAY_LOWER_MARGIN_MS \
			and since >= NetProtocol.DELAY_LOWER_HOLD_MS:
		new_d = current_d - 1
	new_d = clampi(new_d, _d_min, _d_max)
	if new_d != current_d:
		last_change_ms = now_ms
		for pid: Variant in _peers:
			(_peers[pid] as PeerEntry).ring.clear()
	return new_d


func peer_rtt_ms(peer_id: int) -> int:
	var c: PeerEntry = _peers.get(peer_id) as PeerEntry
	return 0 if c == null else roundi(c.rtt_ms)


func peer_jitter_ms(peer_id: int) -> int:
	var c: PeerEntry = _peers.get(peer_id) as PeerEntry
	return 0 if c == null else roundi(c.jit_ms)
