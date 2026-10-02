class_name NetFaultProfile
extends RefCounted
## Latency / jitter / loss / duplication / reorder / freeze / bandwidth description applied by
## NetTransportFault (docs/spec/net.md 4.5, 5.11).

var name: String = "custom"
## One-way base delay.
var latency_ms: float = 0.0
## Uniform in [-jitter, +jitter].
var jitter_ms: float = 0.0
## Ordered mode: each loss event adds rto_ms (geometric retransmits, max 8). Unordered mode: the message is dropped.
var loss_pct: float = 0.0
## < 0 => 2*latency + 4*jitter + 33 (matches ENet's RTT + 4*var + frame time).
var rto_ms: float = -1.0
## Unordered mode only (ordered mode dedups like ENet).
var dup_pct: float = 0.0
## Unordered mode: extra delay uniform [0, 2*latency + jitter].
var reorder_pct: float = 0.0
## true = FIFO per (peer, channel) (ENet reliable model); false = raw UDP-like.
var ordered: bool = true
## 0 = unlimited; adds size*8/kbps serialisation delay (FIFO per link).
var bandwidth_kbps: int = 0
## Every period the endpoint neither sends nor delivers for freeze_ms (frame hitch / suspend); first freeze after one period.
var freeze_every_ms: int = 0
var freeze_ms: int = 0
## 0 = never; otherwise all peers are cut this long after the decorator was created.
var disconnect_after_ms: int = 0

const PRESET_NAMES: PackedStringArray = ["lan", "wifi", "bad_wifi", "internet", "awful", "raw_chaos", "local"]


func effective_rto_ms() -> float:
	return rto_ms if rto_ms >= 0.0 else 2.0 * latency_ms + 4.0 * jitter_ms + 33.0


## Named preset (lan, wifi, bad_wifi, internet, awful, raw_chaos, local) or null for an unknown name.
static func preset(preset_name: String) -> NetFaultProfile:
	var p: NetFaultProfile = NetFaultProfile.new()
	p.name = preset_name
	match preset_name:
		"lan":
			p.latency_ms = 0.5
			p.jitter_ms = 0.3
		"wifi":
			p.latency_ms = 10.0
			p.jitter_ms = 8.0
			p.loss_pct = 1.0
		"bad_wifi":
			p.latency_ms = 30.0
			p.jitter_ms = 25.0
			p.loss_pct = 3.0
		"internet":
			p.latency_ms = 75.0
			p.jitter_ms = 15.0
			p.loss_pct = 1.0
		"awful":
			p.latency_ms = 150.0
			p.jitter_ms = 60.0
			p.loss_pct = 4.0
		"raw_chaos":
			p.latency_ms = 20.0
			p.jitter_ms = 15.0
			p.dup_pct = 3.0
			p.reorder_pct = 10.0
			p.ordered = false
		"local":
			p.latency_ms = 0.1
		_:
			return null
	return p


## Builds a profile from a Dictionary (game/tests/net/profiles.json entries): optional "preset" base plus
## any field name as key. Returns null for an unknown preset.
static func from_dict(d: Dictionary) -> NetFaultProfile:
	var p: NetFaultProfile = NetFaultProfile.new()
	if d.has("preset"):
		p = preset(str(d["preset"]))
		if p == null:
			return null
	if d.has("name"):
		p.name = str(d["name"])
	for k: String in ["latency_ms", "jitter_ms", "loss_pct", "rto_ms", "dup_pct", "reorder_pct"]:
		if d.has(k):
			p.set(k, float(d[k]))
	for k: String in ["bandwidth_kbps", "freeze_every_ms", "freeze_ms", "disconnect_after_ms"]:
		if d.has(k):
			p.set(k, int(d[k]))
	if d.has("ordered"):
		p.ordered = bool(d["ordered"])
	return p


func duplicate_profile() -> NetFaultProfile:
	return NetFaultProfile.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"name": name, "latency_ms": latency_ms, "jitter_ms": jitter_ms, "loss_pct": loss_pct, "rto_ms": rto_ms,
		"dup_pct": dup_pct, "reorder_pct": reorder_pct, "ordered": ordered, "bandwidth_kbps": bandwidth_kbps,
		"freeze_every_ms": freeze_every_ms, "freeze_ms": freeze_ms, "disconnect_after_ms": disconnect_after_ms,
	}
