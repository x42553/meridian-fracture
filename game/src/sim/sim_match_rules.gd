class_name SimMatchRules
extends RefCounted
## Match rules (sim_core 3.8 / 4.11): 13 int fields, all part of the checksum (`world` part, FIELDS order).
## The first eight are the lobby schema (net.md 7.1 `rules`); the rest are kernel / dev only and never sent by the
## lobby. Game speed, pause policy, input delay and disconnect policy are net's and deliberately not rules.

const START_HQ: int = 0  ## start_mode: a deployed HQ
const START_MCV: int = 1
const START_NONE: int = 2

## Hash / dump order (sim_core 8.2, `world` part).
const FIELDS: PackedStringArray = [
	"start_credits", "unit_cap", "superweapons", "fog", "shared_vision", "veterancy", "vision_stride", "vision_budget",
	"start_mode", "neutral_structures", "victory", "end_when_no_humans", "allow_debug",
]
## Inclusive validation ranges, parallel to FIELDS.
const MIN_VALUES: PackedInt32Array = [0, 20, 0, 0, 0, 0, 1, 16, 0, 0, 0, 0, 0]
const MAX_VALUES: PackedInt32Array = [100000, 500, 1, 1, 1, 1, 4, 512, 2, 1, 1, 1, 1]
## Lobby rules that net writes as JSON booleans.
const _BOOL_LOBBY: PackedStringArray = ["superweapons", "fog", "shared_vision", "veterancy"]
## Number of leading FIELDS that belong to the lobby schema.
const _LOBBY_COUNT: int = 8

var start_credits: int = SimConfig.DEFAULT_START_CREDITS  ## 0..100000
var unit_cap: int = SimConfig.DEFAULT_UNIT_CAP  ## 20..500 non-structure entities per player
var superweapons: int = 1
var fog: int = 1
var shared_vision: int = 0
var veterancy: int = 0  ## bible: off
var vision_stride: int = 2  ## performance knobs that must be identical on all peers
var vision_budget: int = 128
var start_mode: int = START_HQ
var neutral_structures: int = 1
var victory: int = 1  ## 0 = sandbox: no elimination-by-assets, no match end
var end_when_no_humans: int = 1
var allow_debug: int = 0


## Lobby-shaped dictionary: the eight lobby keys (four as booleans, as net writes them) plus every kernel-only key
## whose value differs from its default.
func to_dict() -> Dictionary:
	var d: Dictionary = {}
	var def: SimMatchRules = SimMatchRules.new()
	for i: int in FIELDS.size():
		var n: String = FIELDS[i]
		var v: int = get(n)
		if i >= _LOBBY_COUNT and v == def.get(n):
			continue
		if _BOOL_LOBBY.has(n):
			d[n] = v != 0
		else:
			d[n] = v
	return d


## Reads known keys, folds booleans to 0/1, converts numbers with int(); unknown keys are ignored.
static func from_dict(d: Dictionary) -> SimMatchRules:
	var r: SimMatchRules = SimMatchRules.new()
	for n: String in FIELDS:
		if not d.has(n):
			continue
		var v: Variant = d[n]
		if v is bool:
			r.set(n, 1 if v else 0)
		elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			r.set(n, int(v))
	return r


## Appends the 13 rule ints in FIELDS order.
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(start_credits)
	buf.append(unit_cap)
	buf.append(superweapons)
	buf.append(fog)
	buf.append(shared_vision)
	buf.append(veterancy)
	buf.append(vision_stride)
	buf.append(vision_budget)
	buf.append(start_mode)
	buf.append(neutral_structures)
	buf.append(victory)
	buf.append(end_when_no_humans)
	buf.append(allow_debug)


## "rules.<name> out of range" for every field outside its range.
func validate() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in FIELDS.size():
		var v: int = get(FIELDS[i])
		if v < MIN_VALUES[i] or v > MAX_VALUES[i]:
			out.append("rules.%s out of range" % FIELDS[i])
	return out
