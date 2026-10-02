class_name AiTechGraph
extends RefCounted
## Prerequisite DAG of the structures of ONE roster (ai.md 5.5.3). Edges come from DefStructure.requires; the start HQ is
## always owned (a preset), so it never appears in a `missing` list. `missing(def, have, pending)` returns the structures
## still to BUILD to reach `def`, in dependency order (a DFS post-order that visits prerequisites by ascending depth, then
## index), excluding what is owned (`have`, counts by structure def index) and what is under construction (`pending`).

var data: GameData = null
var roster: DefRoster = null
var depth: PackedInt32Array = PackedInt32Array()  ## by structure def: longest requires-chain length (HQ = 0)
var hq: int = -1
var _visiting: PackedByteArray = PackedByteArray()


static func build(p_data: GameData, p_roster: DefRoster) -> AiTechGraph:
	var g: AiTechGraph = AiTechGraph.new()
	g.data = p_data
	g.roster = p_roster
	g.hq = p_roster.hq_idx
	var n: int = p_data.structures.size()
	g.depth.resize(n)
	g.depth.fill(-1)
	g._visiting.resize(n)
	for i: int in n:
		g._depth_of(i)
	return g


func _depth_of(s: int) -> int:
	if depth[s] >= 0:
		return depth[s]
	var d: int = 0
	if _visiting[s] == 0:
		_visiting[s] = 1
		for q: int in _reqs(s):
			d = maxi(d, 1 + _depth_of(q))
		_visiting[s] = 0
	depth[s] = d
	return d


func _reqs(s: int) -> PackedInt32Array:
	var d: DefStructure = roster.structure(s)
	if d == null:
		d = data.structures[s]
	return d.requires


## Prerequisites of `s` sorted by (depth, index) - the deterministic visit order.
func ordered_requires(s: int) -> PackedInt32Array:
	var r: PackedInt32Array = _reqs(s).duplicate()
	for i: int in range(1, r.size()):
		var v: int = r[i]
		var j: int = i - 1
		while j >= 0 and (depth[r[j]] > depth[v] or (depth[r[j]] == depth[v] and r[j] > v)):
			r[j + 1] = r[j]
			j -= 1
		r[j + 1] = v
	return r


## Structures still to build (dependency order) so that `def_idx` can be built/used. `have`/`pending` are counts indexed by
## structure def (either may be empty). Includes `def_idx` itself unless owned/pending.
func missing(def_idx: int, have: PackedInt32Array = PackedInt32Array(), pending: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	_collect(def_idx, have, pending, out)
	return out


func _collect(s: int, have: PackedInt32Array, pending: PackedInt32Array, out: PackedInt32Array) -> void:
	if s < 0 or s >= depth.size() or s == hq or out.has(s):
		return
	if s < have.size() and have[s] > 0:
		return
	if s < pending.size() and pending[s] > 0:
		return
	for q: int in ordered_requires(s):
		_collect(q, have, pending, out)
	out.append(s)


## Structures a UNIT def needs before its producer can train it (producer first, then its own requires).
func missing_for_unit(unit_def: int, have: PackedInt32Array = PackedInt32Array(), pending: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var u: DefUnit = roster.unit(unit_def)
	if u == null:
		return out
	var need: PackedInt32Array = u.requires.duplicate()
	if u.producer >= 0 and not need.has(u.producer):
		need.append(u.producer)
	for s: int in need:
		_collect(s, have, pending, out)
	return out


## Tier at which `role` first becomes producible (AiRoleResolver.min_tier), -1 if the roster has no such role.
func reachable_tier(res: AiRoleResolver, role: int) -> int:
	return res.min_tier(role)


## Number of structures on the longest path to `def_idx` (0 for the HQ / free structures): the "tech distance".
func tier_of(def_idx: int) -> int:
	return depth[def_idx] if def_idx >= 0 and def_idx < depth.size() else 0
