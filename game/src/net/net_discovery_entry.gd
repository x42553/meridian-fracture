class_name NetDiscoveryEntry
extends RefCounted
## One LAN game seen by the browser (docs/spec/net.md 3.6, 5.2). `address` is the datagram's SOURCE ip, never a
## payload field.

## Datagram flag bits.
const F_PASSWORD: int = 1
const F_IN_PROGRESS: int = 2
const F_FULL: int = 4
const F_SPECTATORS: int = 8
const F_DEDICATED: int = 16

var address: String = ""
var port: int = 0
var host_name: String = ""
var game_version: String = ""
var proto_version: int = 0
var sim_version: int = 0
var data_hash: int = 0
var session_id: int = 0
var flags: int = 0
var humans: int = 0
var slots_total: int = 0
var slots_free: int = 0
var ai_count: int = 0
var map_family: int = 0
## Cells (the datagram carries size / 8).
var map_size: int = 0
var last_seen_ms: int = 0
## proto, sim version and data hash all equal to the local build.
var compatible: bool = true
## "" when compatible, else "protocol" / "simulation" / "game data" (the first failing layer).
var mismatch: String = ""


func has_password() -> bool:
	return (flags & F_PASSWORD) != 0


func in_progress() -> bool:
	return (flags & F_IN_PROGRESS) != 0


func is_full() -> bool:
	return (flags & F_FULL) != 0


func spectators_allowed() -> bool:
	return (flags & F_SPECTATORS) != 0


func is_dedicated() -> bool:
	return (flags & F_DEDICATED) != 0


## "address:port" to hand to NetSession.join / NetProtocol.parse_address.
func join_address() -> String:
	return "%s:%d" % [address, port]


## Stable signature of the user-visible fields (change detection for entries_changed).
func signature() -> String:
	return "%s|%d|%d|%d|%d|%d|%d|%s|%s" % [host_name, flags, humans, slots_total, slots_free, ai_count, map_family * 1000 + map_size, game_version, str(compatible)]
