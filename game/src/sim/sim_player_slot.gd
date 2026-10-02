class_name SimPlayerSlot
extends RefCounted
## One `players[]` entry of the match config (sim_core 3.8 / 4.11). Pids need not be contiguous: missing pids
## become vacant players in the world.

const HUMAN: int = 0
const AI: int = 1

var pid: int = 0  ## 0..7
var kind: int = HUMAN
var name: String = ""  ## label only, never hashed
var roster: String = ""  ## roster id, e.g. roster.napc.canada
var team: int = 1  ## final team id 1..15
var color: int = 0  ## 0..11, view only
var start: int = 0  ## spawn SLOT index (record `start` of map.spawns), unique per player
var handicap: int = 100  ## 50..200 percent
var ai_level: int = 0
var ai_style: int = 0
var ai_flags: int = 0  ## bit0 = fog cheat (read by the AI runner, not the sim)


## net.md 7.1 shape: kind is "human" / "ai"; AI slots carry `ai = {level, style, flags}`.
func to_dict() -> Dictionary:
	var d: Dictionary = {
		"pid": pid, "kind": "ai" if kind == AI else "human", "name": name, "roster": roster, "team": team,
		"color": color, "start": start, "handicap": handicap,
	}
	if kind == AI:
		d["ai"] = {"level": ai_level, "style": ai_style, "flags": ai_flags}
	return d


## Accepts net's JSON shape (numbers may be floats: read with int()); missing keys keep their defaults.
static func from_dict(d: Dictionary) -> SimPlayerSlot:
	var s: SimPlayerSlot = SimPlayerSlot.new()
	s.pid = int(d.get("pid", 0))
	var k: Variant = d.get("kind", "human")
	s.kind = (AI if k == "ai" else HUMAN) if k is String else int(k)
	s.name = str(d.get("name", ""))
	s.roster = str(d.get("roster", ""))
	s.team = int(d.get("team", 1))
	s.color = int(d.get("color", 0))
	s.start = int(d.get("start", 0))
	s.handicap = int(d.get("handicap", 100))
	var ai: Variant = d.get("ai", null)
	if ai is Dictionary:
		var a: Dictionary = ai
		s.ai_level = int(a.get("level", 0))
		s.ai_style = int(a.get("style", 0))
		s.ai_flags = int(a.get("flags", 0))
	return s
