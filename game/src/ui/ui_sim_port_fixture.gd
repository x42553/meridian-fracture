class_name UiSimPortFixture
extends UiSimPort
## Deterministic scripted stand-in for the simulation (ui.md 3.2, 7.12): players, entities, fog, production, powers
## and events are plain data loaded from `tests/fixtures/ui/<name>.json` (`load_file` / `from_dict`) or built in code
## (`add_player`, `add_entity`, `spawn`). It never mutates GameData. `advance(ticks)` moves time and re-derives
## construction / queue / cooldown / charge progress linearly. Ids in JSON are strings resolved through GameData.

const DEFAULT_MAP: int = 128
const QUEUE_MAX: int = 5
const PPM: int = 1000000  ## internal progress unit (millionths)
## Directory (under res://) of the named fixture files, see `load_file`.
const FIXTURE_DIR: String = "tests/fixtures/ui"

static var _shared_data: GameData = null

var _data: GameData = null
var _tick: int = 0
var _alpha: float = 0.0
var _local: int = 0
var _viewer: int = 0
var _map_w: int = DEFAULT_MAP
var _map_h: int = DEFAULT_MAP
var _rules: int = RF_FOG | RF_SUPERWEAPONS
var _players: Dictionary = {}  ## pid -> {name, team, color, roster: DefRoster, credits, harvested, supply, demand, cap, active, stats}
var _entities: Dictionary = {}  ## id -> UiEntityRow
var _ids_sorted: PackedInt32Array = PackedInt32Array()
var _ids_dirty: bool = true
var _hidden: Dictionary = {}  ## id -> true: an enemy the viewer cannot see
var _orders: Dictionary = {}  ## id -> PackedInt32Array flat [kind, x, y, target]*n
var _vis: Dictionary = {}  ## cell key -> Vis override
var _default_vis: int = Vis.VISIBLE
var _blocked: Dictionary = {}  ## cell key -> true (impassable for every move class)
var _deposits: Dictionary = {}  ## cell key -> amount
var _cons: Dictionary = {}  ## construction dict (see _default_construction)
var _prod: Dictionary = {}  ## producer id -> {queue: PackedInt32Array, progress: int, total: int, qstate: int, rate: int}
var _research: Dictionary = {}
var _researched: Dictionary = {}
var _powers: Dictionary = {}  ## power def idx -> {status, ready_tick, cooldown, slot}
var _sw: Dictionary = {}
var _warnings: Array[Dictionary] = []
var _script_events: Array[Dictionary] = []  ## {at_tick, rec}
var _event_cursor: int = 0
var _pending_events: PackedInt32Array = PackedInt32Array()
var _sell: Dictionary = {}  ## id -> refund override
var _override: Dictionary = {}  ## "check_train" ... -> Rule
var _bad_sites: Dictionary = {}  ## "s:x:y" -> reason
var _place_reason: int = 0
var selected: PackedInt32Array = PackedInt32Array()  ## the JSON `selected: true` entities (for screens / tests)
var _caps: UiUnitCaps = null


# ---- loading ---------------------------------------------------------------------------------------------------------
## Shipped balance data, loaded once per process (0.35 s).
static func shared_data() -> GameData:
	if _shared_data == null:
		_shared_data = GameData.load_default()
	return _shared_data


## Reads `<FIXTURE_DIR>/<name>.json` (or a full res:// path). Null (and an error) when it cannot be parsed.
static func load_file(path: String, game_data: GameData = null) -> UiSimPortFixture:
	var full: String = path if path.begins_with("res://") else "res://%s/%s.json" % [FIXTURE_DIR, path]
	if not FileAccess.file_exists(full):
		push_error("UiSimPortFixture: missing %s" % full)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
	if not (parsed is Dictionary):
		push_error("UiSimPortFixture: %s is not a JSON object" % full)
		return null
	return from_dict(parsed as Dictionary, game_data)


## Builds a fixture from the 7.12 dictionary. `data` = GameData used to resolve ids (default: shipped data).
static func from_dict(d: Dictionary, game_data: GameData = null) -> UiSimPortFixture:
	var f := UiSimPortFixture.new()
	f._data = game_data if game_data != null else shared_data()
	f._load(d)
	return f


## An empty fixture (no players): build it up with add_player / add_entity.
static func blank(game_data: GameData = null, map_cells: int = DEFAULT_MAP) -> UiSimPortFixture:
	var f := UiSimPortFixture.new()
	f._data = game_data if game_data != null else shared_data()
	f._map_w = map_cells
	f._map_h = map_cells
	return f


func _load(d: Dictionary) -> void:
	var m: Dictionary = d.get("map", {})
	_map_w = int(m.get("w", DEFAULT_MAP))
	_map_h = int(m.get("h", DEFAULT_MAP))
	_viewer = int(d.get("viewer", 0))
	_local = int(d.get("local", _viewer))
	_tick = int(d.get("tick", 0))
	_rules = int(d.get("rules", _rules))
	for p: Variant in d.get("players", []):
		var pd: Dictionary = p
		var pid: int = int(pd.get("pid", _players.size()))
		add_player(pid, str(pd.get("name", "P%d" % pid)), int(pd.get("team", pid + 1)), str(pd.get("roster", d.get("roster", ""))),
			int(pd.get("credits", 0)), int(pd.get("color", pid)))
		var pl: Dictionary = _players[pid]
		pl["harvested"] = int(pd.get("harvested", 0))
		pl["supply"] = int(pd.get("power_supply", 0))
		pl["demand"] = int(pd.get("power_demand", 0))
		pl["cap"] = int(pd.get("unit_cap", 150))
		pl["active"] = bool(pd.get("active", true))
		pl["stats"] = (pd.get("stats", {}) as Dictionary).duplicate()
	for e: Variant in d.get("entities", []):
		_load_entity(e as Dictionary)
	_load_construction(d.get("construction", {}))
	for pr: Variant in d.get("producers", []):
		_load_producer(pr as Dictionary)
	var rs: Dictionary = d.get("research", {})
	if not rs.is_empty():
		var r_p: int = int(rs.get("progress_permille", 0))
		_research = {"active": _res_idx(rs.get("active", null)), "progress": r_p * 1000, "rate": 100,
			"total": _total_from(r_p, int(rs.get("eta_ticks", 0)), 100), "qstate": int(rs.get("queue_state", 0)), "queue": _res_list(rs.get("queue", []))}
	for r: Variant in d.get("researched", []):
		_researched[_res_idx(r)] = true
	var pw: Dictionary = d.get("powers", {})
	for id: Variant in pw:
		var idx: int = _data.power_idx(str(id))
		if idx < 0:
			push_error("UiSimPortFixture: unknown power %s" % str(id))
			continue
		var row: Dictionary = pw[id]
		_powers[idx] = {"status": int(row.get("status", PowerStatus.READY)), "ready_tick": int(row.get("ready_tick", 0)),
			"cooldown": int(row.get("cooldown_ticks", 0)), "slot": int(row.get("slot", _powers.size()))}
	var sw: Dictionary = d.get("superweapon", {})
	if not sw.is_empty():
		_sw = {"status": int(sw.get("status", SwStatus.NONE)), "charge": int(sw.get("charge_permille", 0)),
			"ready_tick": int(sw.get("ready_tick", 0)), "def": _data.superweapon_idx(str(sw.get("def", ""))) if sw.has("def") else -1,
			"launcher": int(sw.get("launcher", 0)), "t0": _tick, "c0": int(sw.get("charge_permille", 0))}
	for w: Variant in d.get("warnings", []):
		_load_warning(w as Dictionary)
	for ev: Variant in d.get("events", []):
		_load_event(ev as Dictionary)
	for c: Variant in d.get("deposits", []):
		var cd: Dictionary = c
		_deposits[_key(int(cd["x"]), int(cd["y"]))] = int(cd.get("amount", 1000))
	for c2: Variant in d.get("blocked", []):
		var bd: Dictionary = c2
		_blocked[_key(int(bd["x"]), int(bd["y"]))] = true
	if d.has("default_visibility"):
		_default_vis = int(d["default_visibility"])


func _load_entity(ed: Dictionary) -> void:
	var row := UiEntityRow.new()
	row.id = int(ed["id"])
	var def_id: String = str(ed.get("def", ""))
	row.def_idx = -1
	if def_id.begins_with("structure."):
		row.kind = UiEntityRow.K_STRUCTURE
		row.flags |= UiEntityRow.F_STRUCT
		row.def_idx = _data.structure_idx(def_id)
	elif def_id.begins_with("neutral."):
		row.kind = UiEntityRow.K_NEUTRAL_STRUCTURE
		row.flags |= UiEntityRow.F_STRUCT
		row.def_idx = _data.neutral_idx(def_id)
		_neutral_fields(row, ed)
	else:
		row.kind = UiEntityRow.K_WRECK if bool(ed.get("wreck", false)) else UiEntityRow.K_UNIT
		row.def_idx = _data.unit_idx(def_id) if def_id != "" else int(ed.get("def_idx", -1))
	if def_id != "" and row.def_idx < 0:
		push_error("UiSimPortFixture: unknown def %s" % def_id)
	row.owner = int(ed.get("owner", -1))
	row.x = int(ed.get("x", 0))
	row.y = int(ed.get("y", 0))
	row.prev_x = row.x
	row.prev_y = row.y
	row.hp_max = int(ed.get("hp_max", ed.get("hp", 100)))
	row.hp = int(ed.get("hp", row.hp_max))
	row.order_kind = int(ed.get("order", 0))
	row.facing = int(ed.get("facing", 0))
	row.layer = int(ed.get("layer", 0))
	row.stance = int(ed.get("stance", 0 if row.kind == UiEntityRow.K_UNIT else -1))
	row.mode = int(ed.get("mode", 0))
	row.cargo = int(ed.get("cargo", 0))
	row.cargo_cap = int(ed.get("cargo_cap", 0))
	row.ammo = int(ed.get("ammo", -1))
	row.vet = int(ed.get("vet", 0))
	row.squad = int(ed.get("squad", 1))
	row.squad_max = int(ed.get("squad_max", row.squad))
	row.container = int(ed.get("container", -1))
	row.paid_cost = int(ed.get("paid_cost", 0))
	row.rally_x = int(ed.get("rally_x", -1))
	row.rally_y = int(ed.get("rally_y", -1))
	row.rally_target = int(ed.get("rally_target", 0))
	row.queue_len = int(ed.get("queue_len", 0))
	row.is_primary = bool(ed.get("primary", false))
	for fl: Variant in ed.get("flags", []):
		row.flags |= _flag_of(str(fl))
	if row.container >= 0:
		row.flags |= UiEntityRow.F_LOADED
	_put(row, not bool(ed.get("visible", true)), bool(ed.get("ghost", false)))
	if bool(ed.get("selected", false)):
		selected.append(row.id)
	if ed.has("orders"):
		var q: PackedInt32Array = PackedInt32Array()
		for o: Variant in ed["orders"]:
			for v: Variant in (o as Array):
				q.append(int(v))
		_orders[row.id] = q


## capturable / garrison_free of a neutral row from its DefNeutral (JSON keys `capturable`, `garrison_free` override).
func _neutral_fields(row: UiEntityRow, ed: Dictionary) -> void:
	if row.def_idx < 0 or row.def_idx >= _data.neutrals.size():
		return
	var n: DefNeutral = _data.neutrals[row.def_idx]
	row.capturable = bool(ed.get("capturable", n.capturable))
	row.garrison_free = int(ed.get("garrison_free", maxi(n.garrison_squads - row.cargo, 0)))


func _load_construction(c: Dictionary) -> void:
	_cons = _default_construction()
	if c.is_empty():
		return
	_cons["state"] = int(c.get("state", Construction.IDLE))
	_cons["def"] = _struct_idx(c.get("def", null))
	_cons["progress"] = int(c.get("progress_permille", 0)) * 1000
	_cons["rate"] = int(c.get("rate_pct", 100))
	_cons["qstate"] = int(c.get("queue_state", QueueState.RUNNING))
	_cons["queue"] = _struct_list(c.get("queue", []))
	_cons["ready_def"] = _struct_idx(c.get("ready_def", null))
	var eta: int = int(c.get("eta_ticks", 0))
	_cons["total"] = _total_from(int(c.get("progress_permille", 0)), eta, int(_cons["rate"]))


func _load_producer(pd: Dictionary) -> void:
	var id: int = int(pd["id"])
	if not _entities.has(id):
		var row := UiEntityRow.new()
		row.id = id
		row.kind = UiEntityRow.K_STRUCTURE
		row.flags = UiEntityRow.F_STRUCT
		row.def_idx = _struct_idx(pd.get("def", null))
		row.owner = int(pd.get("owner", _viewer))
		row.x = int(pd.get("x", 30 * 1024))
		row.y = int(pd.get("y", 30 * 1024))
		row.hp = 1000
		row.hp_max = 1000
		_put(row, false, false)
	var q: PackedInt32Array = PackedInt32Array()
	for u: Variant in pd.get("queue", []):
		q.append(_data.unit_idx(str(u)) if u is String else int(u))
	var prog: int = int(pd.get("progress_permille", 0))
	var rate: int = int(pd.get("rate_pct", 100))
	var eta: int = int(pd.get("eta_ticks", 0))
	_prod[id] = {"queue": q, "progress": prog * 1000, "rate": rate, "qstate": int(pd.get("queue_state", QueueState.RUNNING)),
		"total": _total_from(prog, eta, rate) if eta > 0 else _unit_ticks(q)}
	(_entities[id] as UiEntityRow).queue_len = q.size()


func _load_warning(w: Dictionary) -> void:
	var src: int = 0
	if w.has("sw"):
		src = _data.superweapon_idx(str(w["sw"]))
	elif w.has("power"):
		src = _data.power_idx(str(w["power"]))
	else:
		src = int(w.get("src", 0))
	_warnings.append({"id": int(w.get("id", 1)), "owner": int(w.get("owner", 0)), "kind": int(w.get("kind", 0)), "src": src,
		"x": int(w.get("x", 0)), "y": int(w.get("y", 0)), "x2": int(w.get("x2", 0)), "y2": int(w.get("y2", 0)),
		"radius": int(w.get("radius", 0)), "width": int(w.get("width", 0)), "angle": int(w.get("angle", 0)),
		"start": int(w.get("start_tick", 0)), "exec": int(w.get("exec_tick", 0)), "end": int(w.get("end_tick", int(w.get("exec_tick", 0)) + 40))})


func _load_event(e: Dictionary) -> void:
	var code: int = UiEv.by_name(StringName(str(e.get("type", "")).to_lower().trim_prefix("evt_").trim_prefix("ev_")))
	if code < 0:
		push_error("UiSimPortFixture: unknown event type %s" % str(e.get("type", "")))
		return
	var at: int = int(e.get("at_tick", 0))
	_script_events.append({"at": at, "rec": PackedInt32Array([code, at, int(e.get("x", 0)), int(e.get("y", 0)), int(e.get("a", 0)),
		int(e.get("b", 0)), int(e.get("c", 0)), int(e.get("d", 0)), int(e.get("e", 0)), int(e.get("f", 0))])})
	_script_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))


# ---- programmatic building (tests, screenshots) ------------------------------------------------------------------------
## Adds a player. `roster_id` is a GameData roster id ("" = the first roster).
func add_player(pid: int, p_name: String, team: int, roster_id: String, credits_v: int = 0, color: int = -1) -> void:
	var idx: int = _data.roster_idx(roster_id) if roster_id != "" else 0
	_players[pid] = {"name": p_name, "team": team, "color": pid if color < 0 else color, "roster": _data.rosters[maxi(idx, 0)],
		"credits": credits_v, "harvested": 0, "supply": 0, "demand": 0, "cap": 150, "active": true, "stats": {}}


func set_viewer(pid: int, local: int = -2) -> void:
	_viewer = pid
	_local = pid if local == -2 else local


## Registers a row (the fixture keeps the instance). `hidden` = an enemy outside the viewer's vision; `ghost` = a
## remembered structure. Returns the row for further tweaks.
func add_entity(row: UiEntityRow, hidden: bool = false, ghost: bool = false) -> UiEntityRow:
	_put(row, hidden, ghost)
	return row


## Convenience: spawns a unit / structure by GameData id and returns its row (ids auto-increment when `id` is 0).
func spawn(def_id: String, owner: int, x: int, y: int, id: int = 0, hp_v: int = 100) -> UiEntityRow:
	var row := UiEntityRow.new()
	row.id = id if id > 0 else _next_id()
	if def_id.begins_with("structure."):
		row.kind = UiEntityRow.K_STRUCTURE
		row.flags |= UiEntityRow.F_STRUCT
		row.def_idx = _data.structure_idx(def_id)
	elif def_id.begins_with("neutral."):
		row.kind = UiEntityRow.K_NEUTRAL_STRUCTURE
		row.flags |= UiEntityRow.F_STRUCT
		row.def_idx = _data.neutral_idx(def_id)
		_neutral_fields(row, {})
	else:
		row.kind = UiEntityRow.K_UNIT
		row.def_idx = _data.unit_idx(def_id)
	if row.def_idx < 0:
		push_error("UiSimPortFixture.spawn: unknown def %s" % def_id)
	row.owner = owner
	row.x = x
	row.y = y
	row.prev_x = x
	row.prev_y = y
	row.hp = hp_v
	row.hp_max = hp_v
	if row.kind == UiEntityRow.K_UNIT:
		row.stance = 0
	_put(row, false, false)
	return row


func remove_entity(id: int) -> void:
	_entities.erase(id)
	_hidden.erase(id)
	_ids_dirty = true


func row_of(id: int) -> UiEntityRow:
	return _entities.get(id) as UiEntityRow


func hide_entity(id: int, hidden: bool = true) -> void:
	if hidden:
		_hidden[id] = true
	else:
		_hidden.erase(id)


## Forces a check_* result: name in {"check_build", "check_train", "check_research", "check_place"}; -1 clears it.
func force_rule(fn: String, rule: int) -> void:
	if rule < 0:
		_override.erase(fn)
	else:
		_override[fn] = rule


func set_visibility(cx: int, cy: int, v: int) -> void:
	_vis[_key(cx, cy)] = v


func set_default_visibility(v: int) -> void:
	_default_vis = v


func set_blocked(cx: int, cy: int, blocked: bool = true) -> void:
	if blocked:
		_blocked[_key(cx, cy)] = true
	else:
		_blocked.erase(_key(cx, cy))


func set_deposit(cx: int, cy: int, amount: int) -> void:
	_deposits[_key(cx, cy)] = amount


func set_bad_site(struct_def: int, ax: int, ay: int, reason: int) -> void:
	_bad_sites["%d:%d:%d" % [struct_def, ax, ay]] = reason


func set_sell_value(id: int, credits_v: int) -> void:
	_sell[id] = credits_v


func set_credits(pid: int, v: int) -> void:
	(_players[pid] as Dictionary)["credits"] = v


func set_orders(id: int, flat: PackedInt32Array) -> void:
	_orders[id] = flat


func set_rules(flags: int) -> void:
	_rules = flags


func set_power(power_def: int, status: int, ready_tick: int = 0, cooldown: int = 0, slot: int = -1) -> void:
	_powers[power_def] = {"status": status, "ready_tick": ready_tick, "cooldown": cooldown, "slot": _powers.size() if slot < 0 else slot}


func set_superweapon(status: int, sw_def_idx: int = -1, charge_permille: int = 0, ready_tick: int = 0, launcher: int = 0) -> void:
	_sw = {"status": status, "charge": charge_permille, "ready_tick": ready_tick, "def": sw_def_idx, "launcher": launcher, "t0": _tick, "c0": charge_permille}


## Sets the construction queue: state = Construction, the head def, progress permille, total ticks at 100 % and the queue.
func set_construction(state: int, def_idx: int, progress: int = 0, total_ticks: int = 600, queue: PackedInt32Array = PackedInt32Array(), qstate: int = 0) -> void:
	_cons = _default_construction()
	_cons["state"] = state
	_cons["def"] = def_idx
	_cons["progress"] = progress * 1000
	_cons["total"] = total_ticks
	_cons["queue"] = queue
	_cons["qstate"] = qstate
	if state == Construction.READY_TO_PLACE:
		_cons["ready_def"] = def_idx


## Sets the unit queue of a producer (the entity must exist).
func set_producer(id: int, queue: PackedInt32Array, progress: int = 0, total_ticks: int = 400, qstate: int = 0, rate_pct: int = 100) -> void:
	_prod[id] = {"queue": queue, "progress": progress * 1000, "rate": rate_pct, "qstate": qstate, "total": total_ticks}
	if _entities.has(id):
		(_entities[id] as UiEntityRow).queue_len = queue.size()


## Queues a scripted event record [type, tick, x, y, a..f]; delivered by the next take_events() once `tick >= at_tick`.
func push_event(rec: PackedInt32Array, at_tick: int = -1) -> void:
	var r: PackedInt32Array = rec.duplicate()
	r.resize(UiEv.STRIDE)
	var at: int = _tick if at_tick < 0 else at_tick
	r[UiEv.I_TICK] = at
	_script_events.append({"at": at, "rec": r})
	_script_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))


func set_alpha(a: float) -> void:
	_alpha = a


## Moves time forward: construction / queue / research progress, ready transitions and their events.
func advance(ticks: int) -> void:
	for _i: int in ticks:
		_tick += 1
		_step()


func _step() -> void:
	# construction
	if int(_cons.get("state", 0)) == Construction.BUILDING and _running(int(_cons["qstate"])):
		_cons["progress"] = mini(PPM, int(_cons["progress"]) + _rate_step(int(_cons["total"]), int(_cons["rate"])))
		if int(_cons["progress"]) >= PPM:
			_cons["state"] = Construction.READY_TO_PLACE
			_cons["ready_def"] = _cons["def"]
			_emit(UiEv.STRUCTURE_READY, 0, 0, _viewer, int(_cons["def"]))
	for id: Variant in _prod:
		var p: Dictionary = _prod[id]
		var q: PackedInt32Array = p["queue"]
		if q.is_empty() or not _running(int(p["qstate"])):
			continue
		p["progress"] = int(p["progress"]) + _rate_step(int(p["total"]), int(p["rate"]))
		if int(p["progress"]) >= PPM:
			var done: int = q[0]
			q.remove_at(0)
			p["queue"] = q
			p["progress"] = 0
			p["total"] = _unit_ticks(q)
			var prod_row: UiEntityRow = _entities.get(int(id)) as UiEntityRow
			if prod_row != null:
				prod_row.queue_len = q.size()
			_emit(UiEv.UNIT_PRODUCED, 0, 0, _viewer, 0, done, int(id))
	if not _research.is_empty() and int(_research["active"]) >= 0 and _running(int(_research["qstate"])):
		_research["progress"] = mini(PPM, int(_research["progress"]) + _rate_step(int(_research["total"]), 100))
		if int(_research["progress"]) >= PPM:
			var r_done: int = int(_research["active"])
			_researched[r_done] = true
			var rq: PackedInt32Array = _research["queue"]
			_research["active"] = rq[0] if not rq.is_empty() else -1
			if not rq.is_empty():
				rq.remove_at(0)
			_research["queue"] = rq
			_research["progress"] = 0
			_emit(UiEv.RESEARCH_COMPLETE, 0, 0, _viewer, r_done)


# ---- time / identity -------------------------------------------------------------------------------------------------
func tick() -> int:
	return _tick


func tick_alpha() -> float:
	return _alpha


func local_pid() -> int:
	return _local


func viewer_pid() -> int:
	return _viewer


func set_viewer_pid(pid: int) -> void:
	_viewer = pid


func player_count() -> int:
	return _players.size()


func player_active(pid: int) -> bool:
	return _players.has(pid) and bool((_players[pid] as Dictionary)["active"])


func team_of(pid: int) -> int:
	return int((_players[pid] as Dictionary)["team"]) if _players.has(pid) else -1


func color_of(pid: int) -> int:
	return int((_players[pid] as Dictionary)["color"]) if _players.has(pid) else 0


func name_of(pid: int) -> String:
	return str((_players[pid] as Dictionary)["name"]) if _players.has(pid) else ""


func roster_of(pid: int) -> DefRoster:
	return (_players[pid] as Dictionary)["roster"] as DefRoster if _players.has(pid) else null


func rel(a: int, b: int) -> int:
	if a < 0 or b < 0 or not _players.has(a) or not _players.has(b):
		return Rel.NEUTRAL
	if a == b:
		return Rel.SELF
	return Rel.ALLY if team_of(a) == team_of(b) else Rel.ENEMY


func data() -> GameData:
	return _data


func def_flags(kind: int, def_idx: int) -> int:
	return compute_def_flags(_data, roster_of(_viewer), kind, def_idx)


func rule_flag(flag: int) -> bool:
	return (_rules & flag) != 0


func map_w() -> int:
	return _map_w


func map_h() -> int:
	return _map_h


# ---- viewer economy --------------------------------------------------------------------------------------------------
func credits() -> int:
	return int((_players[_viewer] as Dictionary)["credits"]) if _players.has(_viewer) else 0


func harvested_total() -> int:
	return int((_players[_viewer] as Dictionary)["harvested"]) if _players.has(_viewer) else 0


func power_supply() -> int:
	return int((_players[_viewer] as Dictionary)["supply"]) if _players.has(_viewer) else 0


func power_demand() -> int:
	return int((_players[_viewer] as Dictionary)["demand"]) if _players.has(_viewer) else 0


func unit_cap() -> int:
	return int((_players[_viewer] as Dictionary)["cap"]) if _players.has(_viewer) else 0


func unit_count() -> int:
	var n: int = 0
	for id: Variant in _entities:
		var r: UiEntityRow = _entities[id]
		if r.owner == _viewer and r.kind == UiEntityRow.K_UNIT:
			n += 1
	return n


func player_stats(pid: int, out: Dictionary) -> void:
	out.clear()
	if _players.has(pid):
		out.merge((_players[pid] as Dictionary)["stats"] as Dictionary)


# ---- entities --------------------------------------------------------------------------------------------------------
func alive(eid: int) -> bool:
	return _entities.has(eid) and (_entities[eid] as UiEntityRow).hp > 0


func read(eid: int, out: UiEntityRow) -> bool:
	var r: UiEntityRow = _entities.get(eid) as UiEntityRow
	if r == null or r.hp <= 0:
		return false
	if _viewer >= 0 and _hidden.has(eid) and (r.flags & UiEntityRow.F_GHOST) == 0 and rel(_viewer, r.owner) != Rel.SELF and rel(_viewer, r.owner) != Rel.ALLY:
		return false  # fog integrity: an unseen enemy is not readable, only remembered ghosts are
	out.copy_from(r)
	return true


func own_ids(kind_mask: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.owner != _viewer or r.hp <= 0 or r.kind > UiEntityRow.K_STRUCTURE:
			continue
		if (kind_mask & (KM_STRUCTURE if r.kind == UiEntityRow.K_STRUCTURE else KM_UNIT)) != 0:
			out.append(id)
	return out.size()


func idle_units(out: PackedInt32Array) -> int:
	out.resize(0)
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.owner == _viewer and r.kind == UiEntityRow.K_UNIT and r.hp > 0 and r.order_kind == UiEntityRow.O_IDLE \
				and (r.flags & UiEntityRow.F_LOADED) == 0:
			out.append(id)
	return out.size()


func ids_of_def(kind: int, def_idx: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var want: int = UiEntityRow.K_STRUCTURE if kind == KIND_STRUCTURE else UiEntityRow.K_UNIT
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.owner == _viewer and r.kind == want and r.def_idx == def_idx and r.hp > 0:
			out.append(id)
	return out.size()


func snapshot(out: UiEntitySnapshot) -> void:
	out.clear()
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.hp <= 0 or (r.flags & UiEntityRow.F_LOADED) != 0:
			continue
		var fl: int = r.flags
		if _hidden.has(id) and (r.flags & UiEntityRow.F_GHOST) == 0 and _viewer >= 0:
			continue
		if _viewer >= 0 and (fl & UiEntityRow.F_GHOST) != 0 and r.owner == _viewer:
			continue
		out.push(id, r.x, r.y, r.def_idx, r.owner, fl | (r.kind << 16), r.hp * 100 / maxi(r.hp_max, 1))


func visibility(cx: int, cy: int) -> int:
	if _viewer < 0:
		return Vis.VISIBLE
	return int(_vis.get(_key(cx, cy), _default_vis))


func can_target(eid: int) -> bool:
	var r: UiEntityRow = _entities.get(eid) as UiEntityRow
	if r == null or r.hp <= 0:
		return false
	if _viewer < 0:
		return true
	var rl: int = rel(_viewer, r.owner)
	if rl == Rel.SELF or rl == Rel.ALLY:
		return true
	return not _hidden.has(eid) and (r.flags & UiEntityRow.F_GHOST) == 0


func can_attack(shooter_eid: int, target_eid: int, force: bool) -> bool:
	var s: UiEntityRow = _entities.get(shooter_eid) as UiEntityRow
	var t: UiEntityRow = _entities.get(target_eid) as UiEntityRow
	if s == null or t == null or s.hp <= 0 or t.hp <= 0 or s.id == t.id:
		return false
	if _caps == null:
		_caps = UiUnitCaps.new()
		_caps.setup(_data, roster_of(_viewer))
	var caps: int = _caps.caps_of(KIND_STRUCTURE if s.is_structure() else KIND_UNIT, s.def_idx)
	if (caps & UiUnitCaps.CAP_ARMED) == 0 or not UiUnitCaps.hits(caps, t.layer):
		return false
	return force or rel(s.owner, t.owner) == Rel.ENEMY


func order_queue(eid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var q: PackedInt32Array = _orders.get(eid, PackedInt32Array())
	out.append_array(q)
	return q.size() / OQ_STRIDE


func range_max(eid: int) -> int:
	var r: UiEntityRow = _entities.get(eid) as UiEntityRow
	if r == null or r.kind != UiEntityRow.K_UNIT or r.def_idx < 0 or r.def_idx >= _data.units.size():
		return 0
	return _data.units[r.def_idx].max_range


func detect_radius(eid: int) -> int:
	var r: UiEntityRow = _entities.get(eid) as UiEntityRow
	if r == null or r.def_idx < 0:
		return 0
	if r.kind == UiEntityRow.K_UNIT and r.def_idx < _data.units.size():
		return _data.units[r.def_idx].detect_radius
	if r.kind == UiEntityRow.K_STRUCTURE and r.def_idx < _data.structures.size():
		return _data.structures[r.def_idx].detect_radius
	return 0


# ---- production / research -------------------------------------------------------------------------------------------
func construction_state(out: PackedInt32Array) -> void:
	out.resize(7)
	out.fill(0)
	out[CS_STATE] = int(_cons.get("state", 0))
	out[CS_DEF] = int(_cons.get("def", -1))
	out[CS_PROGRESS] = int(_cons.get("progress", 0)) / 1000
	out[CS_READY_DEF] = int(_cons.get("ready_def", -1))
	out[CS_RATE] = int(_cons.get("rate", 100))
	out[CS_ETA] = _eta(int(_cons.get("progress", 0)), int(_cons.get("total", 600)), out[CS_RATE]) if out[CS_STATE] == Construction.BUILDING else 0
	out[CS_QSTATE] = int(_cons.get("qstate", 0))


func construction_queue(out: PackedInt32Array) -> int:
	out.resize(0)
	out.append_array(_cons.get("queue", PackedInt32Array()) as PackedInt32Array)
	return out.size()


func producers(queue_kind: int, out: PackedInt32Array) -> int:
	out.resize(0)
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.owner != _viewer or r.kind != UiEntityRow.K_STRUCTURE or r.hp <= 0 or (r.flags & UiEntityRow.F_CONSTRUCTING) != 0:
			continue
		if r.def_idx >= 0 and r.def_idx < _data.structures.size() and _data.structures[r.def_idx].queue_kind == queue_kind:
			out.append(id)
	return out.size()


func queue_of(producer_eid: int, out: PackedInt32Array) -> int:
	out.resize(0)
	if _prod.has(producer_eid):
		out.append_array((_prod[producer_eid] as Dictionary)["queue"] as PackedInt32Array)
	return out.size()


func queue_info(producer_eid: int, out: PackedInt32Array) -> void:
	out.resize(4)
	out.fill(0)
	if not _prod.has(producer_eid):
		return
	var p: Dictionary = _prod[producer_eid]
	out[QI_PROGRESS] = int(p["progress"]) / 1000
	out[QI_RATE] = int(p["rate"])
	out[QI_ETA] = _eta(int(p["progress"]), int(p["total"]), int(p["rate"])) if not (p["queue"] as PackedInt32Array).is_empty() else 0
	out[QI_QSTATE] = int(p["qstate"])


func research_state(out: PackedInt32Array) -> void:
	out.resize(0)
	if _research.is_empty():
		out.append_array(PackedInt32Array([-1, 0, 0, 0, 0]))
		return
	var q: PackedInt32Array = _research["queue"]
	var eta_r: int = _eta(int(_research["progress"]), int(_research["total"]), 100) if int(_research["active"]) >= 0 else 0
	out.append_array(PackedInt32Array([int(_research["active"]), int(_research["progress"]) / 1000, eta_r, int(_research["qstate"]), q.size()]))
	out.append_array(q)


func research_done(res_idx: int) -> bool:
	return _researched.has(res_idx)


func check_build(struct_def: int) -> int:
	if _override.has("check_build"):
		return int(_override["check_build"])
	var q: PackedInt32Array = _cons.get("queue", PackedInt32Array())
	if q.size() >= QUEUE_MAX:
		return Rule.QUEUE_FULL
	return Rule.OK if struct_def >= 0 and struct_def < _data.structures.size() else Rule.NOT_AVAILABLE


func check_place(struct_def: int, ax: int, ay: int, _orient: int = 0) -> int:
	if _override.has("check_place"):
		_place_reason = 2
		return int(_override["check_place"])
	var k: String = "%d:%d:%d" % [struct_def, ax, ay]
	if _bad_sites.has(k):
		_place_reason = int(_bad_sites[k])
		return Rule.BAD_SITE
	if ax < 0 or ay < 0 or ax >= _map_w or ay >= _map_h:
		_place_reason = 1
		return Rule.BAD_SITE
	_place_reason = 0
	return Rule.OK


func footprint_rotatable(struct_def: int) -> bool:
	return struct_def >= 0 and struct_def < _data.structures.size() and _data.structures[struct_def].place_mask != 0 and _data.structures[struct_def].id.ends_with("dock")


func place_reason() -> int:
	return _place_reason


func check_train(producer_eid: int, unit_def: int) -> int:
	if _override.has("check_train"):
		return int(_override["check_train"])
	if not _entities.has(producer_eid) or unit_def < 0 or unit_def >= _data.units.size():
		return Rule.NO_TARGET
	var q: PackedInt32Array = (_prod[producer_eid] as Dictionary)["queue"] if _prod.has(producer_eid) else PackedInt32Array()
	return Rule.QUEUE_FULL if q.size() >= QUEUE_MAX else Rule.OK


func check_research(res_def: int) -> int:
	if _override.has("check_research"):
		return int(_override["check_research"])
	if _researched.has(res_def):
		return Rule.NOT_AVAILABLE
	return Rule.OK if res_def >= 0 and res_def < _data.research.size() else Rule.NOT_AVAILABLE


func build_radius_centers(out: PackedInt32Array) -> int:
	out.resize(0)
	var n: int = 0
	for id: int in _sorted_ids():
		var r: UiEntityRow = _entities[id]
		if r.owner == _viewer and r.kind == UiEntityRow.K_STRUCTURE and r.hp > 0 and (r.flags & UiEntityRow.F_CONSTRUCTING) == 0 \
				and r.def_idx >= 0 and r.def_idx < _data.structures.size() and _data.structures[r.def_idx].build_radius > 0:
			out.append(r.x)
			out.append(r.y)
			n += 1
	return n


func sell_value(eid: int) -> int:
	if _sell.has(eid):
		return int(_sell[eid])
	var r: UiEntityRow = _entities.get(eid) as UiEntityRow
	if r == null or r.kind != UiEntityRow.K_STRUCTURE or r.owner != _viewer or (r.flags & UiEntityRow.F_SELLING) != 0 \
			or r.def_idx < 0 or r.def_idx >= _data.structures.size():
		return 0
	var s: DefStructure = _data.structures[r.def_idx]
	if (s.flags & DefEnums.SF_SELLABLE) == 0:
		return 0
	return r.paid_cost * s.sell_bp / 10000


# ---- powers / superweapon ----------------------------------------------------------------------------------------------
func power_slot(power_def: int) -> int:
	return int((_powers[power_def] as Dictionary)["slot"]) if _powers.has(power_def) else -1


func power_status(power_def: int) -> int:
	if not _powers.has(power_def):
		return PowerStatus.LOCKED_PREREQ
	var p: Dictionary = _powers[power_def]
	if _tick < int(p["ready_tick"]):
		return PowerStatus.COOLDOWN
	var st: int = int(p["status"])
	return PowerStatus.READY if st == PowerStatus.COOLDOWN else st


func power_ready_tick(power_def: int) -> int:
	return int((_powers[power_def] as Dictionary)["ready_tick"]) if _powers.has(power_def) else 0


func power_total_cooldown_ticks(power_def: int) -> int:
	return int((_powers[power_def] as Dictionary)["cooldown"]) if _powers.has(power_def) else 0


func power_target_ok(power_def: int, x: int, y: int) -> bool:
	var vis: int = visibility(x >> 10, y >> 10)
	if power_def < 0 or power_def >= _data.powers.size():
		return vis != Vis.SHROUD
	match _data.powers[power_def].target_vision:
		DefEnums.TargetVision.ANY:
			return true
		DefEnums.TargetVision.EXPLORED:
			return vis >= Vis.FOG
		_:
			return vis == Vis.VISIBLE


func sw_status() -> int:
	if _sw.is_empty():
		return SwStatus.NONE
	var st: int = int(_sw["status"])
	if st == SwStatus.CHARGING and _tick >= int(_sw["ready_tick"]):
		return SwStatus.READY
	return st


func sw_def() -> int:
	return int(_sw.get("def", -1))


func sw_charge_permille() -> int:
	if _sw.is_empty():
		return 0
	var st: int = sw_status()
	if st == SwStatus.READY or st == SwStatus.WARNING:
		return 1000
	var span: int = int(_sw["ready_tick"]) - int(_sw["t0"])
	if span <= 0:
		return int(_sw["charge"])
	return clampi(int(_sw["c0"]) + (_tick - int(_sw["t0"])) * (1000 - int(_sw["c0"])) / span, 0, 1000)


func sw_ready_tick() -> int:
	return int(_sw.get("ready_tick", 0))


func sw_launcher_eid() -> int:
	return int(_sw.get("launcher", 0))


func strategic_warnings(out: PackedInt32Array) -> int:
	out.resize(0)
	var n: int = 0
	for w: Dictionary in _warnings:
		if _tick < int(w["start"]) or _tick > int(w["end"]):
			continue
		out.append_array(PackedInt32Array([int(w["id"]), int(w["owner"]), int(w["kind"]), int(w["src"]), int(w["x"]), int(w["y"]),
			int(w["x2"]), int(w["y2"]), int(w["radius"]), int(w["width"]), int(w["angle"]), int(w["exec"])]))
		n += 1
	return n


# ---- map -------------------------------------------------------------------------------------------------------------
func passable(cx: int, cy: int, _move_class: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < _map_w and cy < _map_h and not _blocked.has(_key(cx, cy))


func deposit_at(cx: int, cy: int) -> int:
	if visibility(cx, cy) == Vis.SHROUD:
		return 0
	return int(_deposits.get(_key(cx, cy), 0))


# ---- events ----------------------------------------------------------------------------------------------------------
func take_events() -> PackedInt32Array:
	var out: PackedInt32Array = _pending_events
	_pending_events = PackedInt32Array()
	while _event_cursor < _script_events.size() and int(_script_events[_event_cursor]["at"]) <= _tick:
		out.append_array(_script_events[_event_cursor]["rec"] as PackedInt32Array)
		_event_cursor += 1
	return out


# ---- internals -------------------------------------------------------------------------------------------------------
static func _key(cx: int, cy: int) -> int:
	return cy * 4096 + cx


func _put(row: UiEntityRow, hidden: bool, ghost: bool) -> void:
	if row.kind == UiEntityRow.K_STRUCTURE:
		row.flags |= UiEntityRow.F_STRUCT
	if ghost:
		row.flags |= UiEntityRow.F_GHOST
	_entities[row.id] = row
	if hidden:
		_hidden[row.id] = true
	_ids_dirty = true


func _next_id() -> int:
	var m: int = 1000
	for id: Variant in _entities:
		m = maxi(m, int(id))
	return m + 1


func _sorted_ids() -> PackedInt32Array:
	if _ids_dirty:
		_ids_sorted = PackedInt32Array()
		for id: Variant in _entities:
			_ids_sorted.append(int(id))
		_ids_sorted.sort()
		_ids_dirty = false
	return _ids_sorted


func _emit(type: int, x: int, y: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> void:
	_pending_events.append_array(PackedInt32Array([type, _tick, x, y, a, b, c, d, e, f]))


static func _running(qstate: int) -> bool:
	return qstate == QueueState.RUNNING or qstate == QueueState.LOW_POWER


## Progress gained per tick (in PPM, millionths) at `rate_pct` for an item of `total` ticks at 100 %.
static func _rate_step(total: int, rate_pct: int) -> int:
	return maxi(1, PPM * rate_pct / 100 / maxi(total, 1))


static func _eta(progress_ppm: int, total: int, rate_pct: int) -> int:
	var step: int = _rate_step(total, rate_pct)
	return (maxi(PPM - progress_ppm, 0) + step - 1) / step


## Ticks at 100 % of an item that is at `progress` permille with `eta` ticks left at `rate_pct`.
static func _total_from(progress: int, eta: int, rate_pct: int) -> int:
	if eta <= 0 or progress >= 1000:
		return 600
	return maxi(1, eta * rate_pct * 10 / (1000 - progress))


func _unit_ticks(q: PackedInt32Array) -> int:
	if q.is_empty() or q[0] < 0 or q[0] >= _data.units.size():
		return 400
	return maxi(_data.units[q[0]].build_ticks, 1)


func _default_construction() -> Dictionary:
	return {"state": Construction.IDLE, "def": -1, "progress": 0, "total": 600, "rate": 100, "qstate": 0, "queue": PackedInt32Array(), "ready_def": -1}


func _struct_idx(v: Variant) -> int:
	if v == null:
		return -1
	if v is String:
		return _data.structure_idx(str(v))
	return int(v)


func _struct_list(a: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for v: Variant in a:
		out.append(_struct_idx(v))
	return out


func _res_idx(v: Variant) -> int:
	if v == null:
		return -1
	if v is String:
		return _data.research_idx(str(v))
	return int(v)


func _res_list(a: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for v: Variant in a:
		out.append(_res_idx(v))
	return out


static func _flag_of(name: String) -> int:
	match name:
		"ghost":
			return UiEntityRow.F_GHOST
		"camo":
			return UiEntityRow.F_CAMO
		"deployed":
			return UiEntityRow.F_DEPLOYED
		"emp":
			return UiEntityRow.F_EMP
		"unpowered":
			return UiEntityRow.F_UNPOWERED
		"constructing":
			return UiEntityRow.F_CONSTRUCTING
		"garrisoned":
			return UiEntityRow.F_GARRISONED
		"loaded":
			return UiEntityRow.F_LOADED
		"decoy":
			return UiEntityRow.F_DECOY
		"suppressed":
			return UiEntityRow.F_SUPPRESSED
		"repairing":
			return UiEntityRow.F_REPAIRING
		"selling":
			return UiEntityRow.F_SELLING
	return 0
