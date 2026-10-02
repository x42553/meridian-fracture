class_name NetPlayerSlot
extends RefCounted
## One lobby slot (docs/spec/net.md 4.5). `index` equals the sim pid at launch.

## 0..7; == pid at launch.
var index: int = 0
## NetProtocol.SlotKind.
var kind: int = 1
## 0 none; 1 = host; >= 2 remote (HUMAN); AI slots keep 0.
var peer_id: int = 0
## Sanitised, <= 24 chars, unique among slots (suffix " (2)").
var name: String = ""
## One of the roster ids or a random token (spec 5.3.4).
var roster_id: String = "random"
## 0 none, 1..4 = A..D.
var team: int = 0
## 0..color_count-1, unique among non-closed slots.
var color: int = 0
## -1 random, else 0..layout_players-1, unique.
var start: int = -1
## 50..200 step 5 (spec 5.3.6).
var handicap_pct: int = 100
## AI slots and the host are always ready.
var ready: bool = false
## Transport-connected (AI = true).
var connected: bool = false
## 0..ai_level_count-1.
var ai_level: int = 1
var ai_style: int = 0
## bit0 = fog cheat; passed through to players[].ai.flags.
var ai_flags: int = 0
## Display only, host-measured.
var ping_ms: int = 0


func duplicate_slot() -> NetPlayerSlot:
	var s: NetPlayerSlot = NetPlayerSlot.new()
	s.index = index
	s.kind = kind
	s.peer_id = peer_id
	s.name = name
	s.roster_id = roster_id
	s.team = team
	s.color = color
	s.start = start
	s.handicap_pct = handicap_pct
	s.ready = ready
	s.connected = connected
	s.ai_level = ai_level
	s.ai_style = ai_style
	s.ai_flags = ai_flags
	s.ping_ms = ping_ms
	return s


## true for HUMAN and AI slots (the ones that become players at launch).
func is_active() -> bool:
	return kind == NetProtocol.SlotKind.HUMAN or kind == NetProtocol.SlotKind.AI
