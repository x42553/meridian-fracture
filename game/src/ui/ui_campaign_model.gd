class_name UiCampaignModel
extends RefCounted
## The campaign list as the campaign screen shows it (MIS2): every mission of `GameData` in menu order (group, order, id) with its
## state (locked / unlocked / completed), best time and difficulty from `AppCampaign`, the faction of the human slot, a one-line
## teaser from the briefing, and the position of its node on the campaign map. Pure: no nodes, unit-tested.
##
## Unlock rule: missions of group "operation" need the tutorial ("Field Training", group "tutorial") completed, or any operation
## completed already (a player who skipped the training is not locked out again), or no tutorial in the data. Every other group
## is always open. `AppCampaign.unlock_all` (debug) opens everything.
## Map layout: the tutorial is the hub in the middle, the operations sit on a ring around it in order, mission groups of any other
## name (demo, custom) line up along the lower edge. Positions are fractions of the map area (0..1).

enum State { LOCKED = 0, UNLOCKED = 1, COMPLETED = 2 }

const GROUP_TUTORIAL: String = "tutorial"
const GROUP_OPERATION: String = "operation"
const GROUP_DEMO: String = "demo"  ## listed on the map but never recommended / offered as the next mission
const RING_R: float = 0.31
const HUB_Y: float = 0.45
const TEASER_CHARS: int = 150

class Entry extends RefCounted:
	var id: String = ""
	var title: String = ""
	var group: String = ""
	var order: int = 0
	var faction_code: String = ""
	var faction_name: String = ""
	var roster_id: String = ""
	var state: int = State.LOCKED
	var best_ticks: int = 0
	var best_difficulty: int = -1
	var teaser: String = ""
	var pos: Vector2 = Vector2(0.5, 0.5)
	var index: int = 0  ## position in menu order
	var objectives_primary: int = 0
	var objectives_secondary: int = 0

	func playable() -> bool:
		return state != State.LOCKED


var entries: Array[Entry] = []
var _by_id: Dictionary = {}
var _campaign: AppCampaign = null


static func build(data: GameData, campaign: AppCampaign) -> UiCampaignModel:
	var m: UiCampaignModel = UiCampaignModel.new()
	m._campaign = campaign
	var table: DefMissionTable = DefMissionTable.of(data)
	if table == null:
		return m
	var defs: Array[DefMission] = table.missions.duplicate()
	defs.sort_custom(_menu_before)
	for def: DefMission in defs:
		var id: String = def.id
		var n: Entry = Entry.new()
		n.id = id
		n.title = def.ui_title
		n.group = def.group
		n.order = def.order
		n.index = m.entries.size()
		_fill_faction(data, def, n)
		n.teaser = teaser_of(def)
		for o: DefMissionObjective in def.objectives:
			if o.initial == 0 or o.kind == DefMissionObjective.Kind.HIDDEN:
				continue  # revealed later: not part of the first look
			if o.kind == DefMissionObjective.Kind.PRIMARY:
				n.objectives_primary += 1
			elif o.kind == DefMissionObjective.Kind.SECONDARY:
				n.objectives_secondary += 1
		m.entries.append(n)
		m._by_id[id] = n
	m.refresh()
	m._layout()
	return m


## Menu order: the tutorial group, the operations, then every other group by name; inside a group by `order`, then id.
static func _menu_before(a: DefMission, b: DefMission) -> bool:
	var ra: int = _group_rank(a.group)
	var rb: int = _group_rank(b.group)
	if ra != rb:
		return ra < rb
	if ra == 2 and a.group != b.group:
		return a.group < b.group
	if a.order != b.order:
		return a.order < b.order
	return a.id < b.id


static func _group_rank(group: String) -> int:
	return 0 if group == GROUP_TUTORIAL else (1 if group == GROUP_OPERATION else 2)


static func _fill_faction(data: GameData, def: DefMission, n: Entry) -> void:
	for p: DefMissionPlayer in def.players:
		if not p.human:
			continue
		n.roster_id = p.roster
		if p.roster_idx >= 0 and p.roster_idx < data.rosters.size():
			var f: int = data.rosters[p.roster_idx].faction
			if f >= 0 and f < data.factions.size():
				n.faction_code = data.factions[f].code.to_lower()
				n.faction_name = data.factions[f].ui_name
		return


## The first sentence of the first briefing block, cut at `TEASER_CHARS`.
static func teaser_of(def: DefMission) -> String:
	if def.ui_briefing.is_empty():
		return ""
	var text: String = str((def.ui_briefing[0] as Dictionary).get("text", "")).strip_edges().replace("\n", " ")
	var cut: int = -1
	for stop: String in [". ", "! ", "? "]:
		var at: int = text.find(stop)
		if at >= 0 and (cut < 0 or at < cut):
			cut = at + 1
	if cut > 0 and cut <= TEASER_CHARS:
		return text.substr(0, cut)
	if text.length() <= TEASER_CHARS:
		return text
	return text.substr(0, TEASER_CHARS - 3).strip_edges() + "..."


## Re-reads states and bests from the campaign (call after a result was recorded).
func refresh() -> void:
	var tutorial_done: bool = false
	var has_tutorial: bool = false
	var op_done: bool = false
	for n: Entry in entries:
		if n.group == GROUP_TUTORIAL:
			has_tutorial = true
			tutorial_done = tutorial_done or _campaign.completed(n.id)
		elif n.group == GROUP_OPERATION and _campaign.completed(n.id):
			op_done = true
	var ops_open: bool = _campaign.unlock_all or not has_tutorial or tutorial_done or op_done
	for n: Entry in entries:
		n.best_ticks = _campaign.best_ticks(n.id)
		n.best_difficulty = _campaign.best_difficulty(n.id)
		if _campaign.completed(n.id):
			n.state = State.COMPLETED
		elif n.group == GROUP_OPERATION and not ops_open:
			n.state = State.LOCKED
		else:
			n.state = State.UNLOCKED


func entry(id: String) -> Entry:
	return _by_id.get(id) as Entry


func count() -> int:
	return entries.size()


func completed_count() -> int:
	var c: int = 0
	for n: Entry in entries:
		c += 1 if n.state == State.COMPLETED else 0
	return c


func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Entry in entries:
		out.append(n.id)
	return out


## The mission to offer next: the first unlocked, not completed one in menu order (the tutorial first); "" when everything is done.
func recommended() -> String:
	for n: Entry in entries:
		if n.state == State.UNLOCKED and n.group != GROUP_DEMO:
			return n.id
	return ""


## The mission after `id` in menu order that is open to play ("" = none): what the result screen's NEXT MISSION button starts.
func next_after(id: String) -> String:
	var cur: Entry = entry(id)
	if cur == null:
		return ""
	for i: int in range(cur.index + 1, entries.size()):
		if entries[i].playable() and entries[i].group != GROUP_DEMO:
			return entries[i].id
	return ""


## Lock explanation for the detail panel.
func lock_reason(id: String) -> String:
	var n: Entry = entry(id)
	if n == null or n.state != State.LOCKED:
		return ""
	return "Complete Field Training first."


## Group of the node in the menu: "FIELD TRAINING" / "OPERATIONS" / the upper-cased group word.
static func group_label(group: String, order: int = 0) -> String:
	match group:
		GROUP_TUTORIAL:
			return "TRAINING"
		GROUP_OPERATION:
			return "OPERATION %d" % order if order > 0 else "OPERATION"
	return group.to_upper()


# ---------------------------------------------------------------- map layout

func _layout() -> void:
	var tut: Array[Entry] = []
	var ops: Array[Entry] = []
	var rest: Array[Entry] = []
	for n: Entry in entries:
		match n.group:
			GROUP_TUTORIAL:
				tut.append(n)
			GROUP_OPERATION:
				ops.append(n)
			_:
				rest.append(n)
	var centre: Vector2 = Vector2(0.5, HUB_Y)
	for i: int in tut.size():
		tut[i].pos = centre + Vector2(float(i) * 0.12 - float(tut.size() - 1) * 0.06, 0.0)
	for i: int in ops.size():
		var ang: float = -PI * 0.5 + TAU * float(i) / float(maxi(ops.size(), 1))
		ops[i].pos = centre + Vector2(cos(ang) * RING_R * 1.18, sin(ang) * RING_R)
		if tut.is_empty() and ops.size() == 1:
			ops[i].pos = centre
	for i: int in rest.size():
		rest[i].pos = Vector2(0.5 + (float(i) - float(rest.size() - 1) * 0.5) * 0.16, 0.935)
