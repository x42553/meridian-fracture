class_name NetPeerStats
extends RefCounted
## Per-peer RTT / jitter / loss / byte counters (docs/spec/net.md 3.2). ENet fills the RTT fields from its
## own smoothed statistics; other transports feed samples through add_rtt_sample().

## Smoothed round-trip time and its variance (ms). Includes the remote's frame delay.
var rtt_ms: float = 0.0
var rtt_var_ms: float = 0.0
var last_rtt_ms: float = 0.0
## 0..1
var packet_loss: float = 0.0
var bytes_in: int = 0
var bytes_out: int = 0
## Transport-clock milliseconds of the last received packet (0 = never).
var last_seen_ms: int = 0

var _has_rtt: bool = false


## RFC 6298 style smoothing (alpha 1/8, beta 1/4) for transports without their own estimator.
func add_rtt_sample(ms: float) -> void:
	last_rtt_ms = ms
	if not _has_rtt:
		rtt_ms = ms
		rtt_var_ms = ms / 2.0
		_has_rtt = true
		return
	rtt_var_ms += (absf(ms - rtt_ms) - rtt_var_ms) / 4.0
	rtt_ms += (ms - rtt_ms) / 8.0


func reset() -> void:
	rtt_ms = 0.0
	rtt_var_ms = 0.0
	last_rtt_ms = 0.0
	packet_loss = 0.0
	bytes_in = 0
	bytes_out = 0
	last_seen_ms = 0
	_has_rtt = false


func duplicate_stats() -> NetPeerStats:
	var s: NetPeerStats = NetPeerStats.new()
	s.rtt_ms = rtt_ms
	s.rtt_var_ms = rtt_var_ms
	s.last_rtt_ms = last_rtt_ms
	s.packet_loss = packet_loss
	s.bytes_in = bytes_in
	s.bytes_out = bytes_out
	s.last_seen_ms = last_seen_ms
	s._has_rtt = _has_rtt
	return s
