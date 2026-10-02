class_name UiSimPort
extends RefCounted
## Everything the UI reads from the simulation (ui.md 3.2.1). Abstract: adapters are `UiSimPortWorld` (real
## `SimWorld`) and `UiSimPortFixture` (scripted, tests / screenshots). Reads are as-of the end of the last executed
## tick and pure. The UI never writes the sim: orders travel as commands through `UiCommandBus` / `UiNetPort`.

enum Rel { SELF = 0, ALLY = 1, ENEMY = 2, NEUTRAL = 3 }  ## = SimWorld.Rel
enum Vis { SHROUD = 0, FOG = 1, VISIBLE = 2 }
## Numerically = SimCommand.Err: a check_* result and a CMD_REJECTED error share one text table `reject.<n>`.
enum Rule {
	OK = 0, UNKNOWN_OP = 1, BAD_PLAYER = 2, ELIMINATED = 3, MATCH_ENDED = 4, BAD_FIELD = 5, NO_ACTORS = 6, NO_TARGET = 7,
	WRONG_KIND = 8, NOT_AVAILABLE = 9, NO_PREREQ = 10, NO_CREDITS = 11, QUEUE_FULL = 12, BAD_SITE = 13, NO_VISION = 14,
	NOT_READY = 15, UNIT_CAP = 16, BLOCKED = 17, DISABLED = 18, NOT_ALLOWED = 19, BAD_ORDER = 20, INSIDE = 21,
}
enum QueueState { RUNNING = 0, WAIT_FUNDS = 1, UNIT_CAP = 2, LOW_POWER = 3, PREREQ_LOST = 4, HELD = 5, EXIT_BLOCKED = 6, SHUTDOWN = 7 }
enum PowerStatus { READY = 0, COOLDOWN = 1, LOCKED_PREREQ = 2, UNPOWERED = 3, NO_CREDITS = 4 }
enum SwStatus { NONE = 0, CHARGING = 1, READY = 2, WARNING = 3 }
enum Construction { IDLE = 0, BUILDING = 1, READY_TO_PLACE = 2, PAUSED = 3 }

const DF_STRUCTURE: int = 1  ## def_flags() bits
const DF_COUNTS_FOR_CAP: int = 2  ## false for summons, decoys, drones
const DF_MCV: int = 4
const DF_COLLECTOR: int = 8
const RF_FOG: int = 1
const RF_SUPERWEAPONS: int = 2
const RF_SHARED_VISION: int = 4
const RF_VETERANCY: int = 8

## Kinds selecting a def table (= SimEntity.Kind for the two the UI selects).
const KIND_UNIT: int = 0
const KIND_STRUCTURE: int = 1
const KM_UNIT: int = 1  ## own_ids kind_mask bits
const KM_STRUCTURE: int = 2

# construction_state() out indices
const CS_STATE: int = 0
const CS_DEF: int = 1
const CS_PROGRESS: int = 2
const CS_READY_DEF: int = 3
const CS_ETA: int = 4
const CS_RATE: int = 5
const CS_QSTATE: int = 6
# queue_info() out indices
const QI_PROGRESS: int = 0
const QI_ETA: int = 1
const QI_RATE: int = 2
const QI_QSTATE: int = 3
# strategic_warnings() record stride and fields
const WARN_STRIDE: int = 12
# order_queue() record stride
const OQ_STRIDE: int = 4


## DF_* bits of a def straight from the GameData tables (shared by the adapters). `roster` (may be null) resolves
## the viewer's modified defs.
static func compute_def_flags(d: GameData, roster: DefRoster, kind: int, def_idx: int) -> int:
	if d == null or def_idx < 0:
		return 0
	if kind == KIND_STRUCTURE:
		return DF_STRUCTURE
	var u: DefUnit = null
	if roster != null and def_idx < roster.units.size():
		u = roster.units[def_idx]
	if u == null and def_idx < d.units.size():
		u = d.units[def_idx]
	if u == null:
		return 0
	var f: int = 0
	if u.pop > 0:
		f |= DF_COUNTS_FOR_CAP
	if (u.tags & DefEnums.UT_COLLECTOR) != 0:
		f |= DF_COLLECTOR
	for a: DefAbility in u.abilities:
		if a.kind == DefEnums.AbilityKind.DEPLOY_STRUCTURE:
			f |= DF_MCV
		elif a.kind == DefEnums.AbilityKind.HARVEST:
			f |= DF_COLLECTOR
	return f


func _ni(fn: String) -> void:
	push_error("NOT IMPLEMENTED: UiSimPort.%s" % fn)


# ---- time / identity ------------------------------------------------------------------------------------------------
## Sim tick (20 per game second at 100 % speed).
func tick() -> int:
	_ni("tick")
	return 0


## 0..1 within the current tick (view-only float).
func tick_alpha() -> float:
	return 0.0


## -1 = observer / replay.
func local_pid() -> int:
	_ni("local_pid")
	return -1


## Whose fog / economy the HUD shows; -1 = omniscient observer.
func viewer_pid() -> int:
	_ni("viewer_pid")
	return -1


func set_viewer_pid(_pid: int) -> void:
	_ni("set_viewer_pid")


func player_count() -> int:
	_ni("player_count")
	return 0


## False when defeated / resigned.
func player_active(_pid: int) -> bool:
	_ni("player_active")
	return false


func team_of(_pid: int) -> int:
	_ni("team_of")
	return -1


## Palette index 0..11.
func color_of(_pid: int) -> int:
	_ni("color_of")
	return 0


func name_of(_pid: int) -> String:
	_ni("name_of")
	return ""


func roster_of(_pid: int) -> DefRoster:
	_ni("roster_of")
	return null


## Rel between two owners (pids or -1).
func rel(_a: int, _b: int) -> int:
	_ni("rel")
	return Rel.NEUTRAL


func data() -> GameData:
	_ni("data")
	return null


## DF_* bits of a def; `kind` selects the table (KIND_UNIT / KIND_STRUCTURE).
func def_flags(_kind: int, _def_idx: int) -> int:
	_ni("def_flags")
	return 0


## Identity in sim_core v2; the single seam if the reconcilers ever move to one dense def space.
func table_idx(_kind: int, def_idx: int) -> int:
	return def_idx


## Inverse of table_idx.
func sim_def(_kind: int, table_index: int) -> int:
	return table_index


## RF_* rule flag.
func rule_flag(_flag: int) -> bool:
	_ni("rule_flag")
	return false


func map_w() -> int:
	_ni("map_w")
	return 0


func map_h() -> int:
	_ni("map_h")
	return 0


# ---- viewer economy -------------------------------------------------------------------------------------------------
func credits() -> int:
	_ni("credits")
	return 0


## Monotonic (harvest + salvage); the UI derives income per minute.
func harvested_total() -> int:
	_ni("harvested_total")
	return 0


func power_supply() -> int:
	_ni("power_supply")
	return 0


## Sum of the negative deltas as a positive number.
func power_demand() -> int:
	_ni("power_demand")
	return 0


func unit_cap() -> int:
	_ni("unit_cap")
	return 0


## Cap weight of the viewer's non-structure entities.
func unit_count() -> int:
	_ni("unit_count")
	return 0


## Observer overview of any player (fog and viewer ignored; replays, spectating, the scoreboard): `credits`, `earned` (harvested
## total), `spent`, `units` (cap weight), `structs`, `army_n` / `army_value` (military units and what they cost), `kills`, `losses`,
## `army_x` / `army_y` (centroid of the army, -1 without one), `base_x` / `base_y` (centroid of the structures, -1 without one),
## `active` (0 = defeated / resigned), `present` (0 = vacant slot), `commands`. Empty for an invalid pid. The default reads nothing.
func player_overview(_pid: int, out: Dictionary) -> void:
	out.clear()


## Fills `out` with the keys of ui.md 4.9.1 (units_built, units_lost, harvested, value_destroyed, ...).
func player_stats(_pid: int, _out: Dictionary) -> void:
	_ni("player_stats")


# ---- entities -------------------------------------------------------------------------------------------------------
func alive(_eid: int) -> bool:
	_ni("alive")
	return false


## Fills `out`; false if the entity is gone.
func read(_eid: int, _out: UiEntityRow) -> bool:
	_ni("read")
	return false


## Viewer's entities, ascending id; kind_mask bits KM_UNIT / KM_STRUCTURE. Returns the count.
func own_ids(_kind_mask: int, _out: PackedInt32Array) -> int:
	_ni("own_ids")
	return 0


## Viewer's alive, on-map, selectable units with an empty order queue, ascending.
func idle_units(_out: PackedInt32Array) -> int:
	_ni("idle_units")
	return 0


## Viewer's alive entities of that (kind, def), ascending.
func ids_of_def(_kind: int, _def_idx: int, _out: PackedInt32Array) -> int:
	_ni("ids_of_def")
	return 0


## Everything the viewer may draw on the minimap: own + allied + visible enemies + remembered structure ghosts.
func snapshot(_out: UiEntitySnapshot) -> void:
	_ni("snapshot")


## Vis for the viewer (an omniscient viewer sees VISIBLE everywhere).
func visibility(_cx: int, _cy: int) -> int:
	_ni("visibility")
	return Vis.SHROUD


## True for own / allied entities and for enemies passing the fog rule; false for remembered ghosts.
func can_target(_eid: int) -> bool:
	_ni("can_target")
	return false


func can_attack(_shooter_eid: int, _target_eid: int, _force: bool) -> bool:
	_ni("can_attack")
	return false


## Flattened [kind, x, y, target_id] * n (kind = SimOrder.T_*); returns n.
func order_queue(_eid: int, _out: PackedInt32Array) -> int:
	_ni("order_queue")
	return 0


## Effective maximum weapon range in sim units (0 = unarmed).
func range_max(_eid: int) -> int:
	_ni("range_max")
	return 0


## Detector radius in sim units (0 = not a detector).
func detect_radius(_eid: int) -> int:
	_ni("detect_radius")
	return 0


# ---- production / research (viewer) ---------------------------------------------------------------------------------
## out = [Construction, def_idx, progress_permille, ready_def_idx, eta_ticks, rate_pct, queue_state] (CS_*).
func construction_state(_out: PackedInt32Array) -> void:
	_ni("construction_state")


## Structure defs queued BEHIND the head; returns n.
func construction_queue(_out: PackedInt32Array) -> int:
	_ni("construction_queue")
	return 0


## Own completed producer structures of a DefEnums.QueueKind, ascending id.
func producers(_queue_kind: int, _out: PackedInt32Array) -> int:
	_ni("producers")
	return 0


## Queued unit defs in order (slot 0 = in production); returns the length (<= 5).
func queue_of(_producer_eid: int, _out: PackedInt32Array) -> int:
	_ni("queue_of")
	return 0


## out = [progress_permille, eta_ticks, rate_pct, queue_state] (QI_*).
func queue_info(_producer_eid: int, _out: PackedInt32Array) -> void:
	_ni("queue_info")


## out = [active_def or -1, progress_permille, eta_ticks, queue_state, queued_count, queued_def0, ...].
func research_state(_out: PackedInt32Array) -> void:
	_ni("research_state")


func research_done(_res_idx: int) -> bool:
	_ni("research_done")
	return false


## Rule for enqueuing a structure (prereqs, queue full, limit); credits are NOT checked (progressive payment).
func check_build(_struct_def: int) -> int:
	_ni("check_build")
	return Rule.NOT_ALLOWED


## Top-left footprint cell (ax, ay), orient 0-3 = clockwise quarter turns: Rule.OK or BAD_SITE (detail: place_reason).
func check_place(_struct_def: int, _ax: int, _ay: int, _orient: int = 0) -> int:
	_ni("check_place")
	return Rule.NOT_ALLOWED


## SimPlacementResult for the ghost's per-cell colours (opaque to the UI).
func placement_result(_struct_def: int, _ax: int, _ay: int, _orient: int = 0) -> RefCounted:
	return null


func footprint_rotatable(_struct_def: int) -> bool:
	return false


## Last check_place failure: 1 outside radius, 2 blocked, 3 shoreline, 4 strategic limit, 5 shroud.
func place_reason() -> int:
	return 0


func check_train(_producer_eid: int, _unit_def: int) -> int:
	_ni("check_train")
	return Rule.NOT_ALLOWED


func check_research(_res_def: int) -> int:
	_ni("check_research")
	return Rule.NOT_ALLOWED


## [x0, y0, x1, y1, ...] centres of the viewer's active HQs.
func build_radius_centers(_out: PackedInt32Array) -> int:
	_ni("build_radius_centers")
	return 0


## Credits refunded by selling, 0 if not sellable.
func sell_value(_eid: int) -> int:
	return 0


func repair_cost_per_second(_eid: int) -> int:
	return 0


# ---- support powers / superweapon (viewer) --------------------------------------------------------------------------
## 0..2 = index in the viewer's roster powers; -1 if not in the roster.
func power_slot(_power_def: int) -> int:
	return -1


func power_status(_power_def: int) -> int:
	return PowerStatus.LOCKED_PREREQ


func power_ready_tick(_power_def: int) -> int:
	return 0


func power_total_cooldown_ticks(_power_def: int) -> int:
	return 0


## DefPower.target_vision against REAL vision.
func power_target_ok(_power_def: int, _x: int, _y: int) -> bool:
	return false


func sw_status() -> int:
	return SwStatus.NONE


## DefSuperweapon index of the viewer's roster, -1 none.
func sw_def() -> int:
	return -1


func sw_charge_permille() -> int:
	return 0


func sw_ready_tick() -> int:
	return 0


func sw_launcher_eid() -> int:
	return 0


## Stride WARN_STRIDE [id, owner, kind, src_idx, x, y, x2, y2, radius, width, angle, exec_tick] * n.
func strategic_warnings(_out: PackedInt32Array) -> int:
	return 0


# ---- scripted missions (MIS2) ---------------------------------------------------------------------------------------
## Id of the scripted mission this match runs ("" = a skirmish).
func mission_id() -> String:
	return ""


## Live mission state for the objectives panel and the timers, read-only. Layout: [result (0 none, 1 win, 2 lose), result tick,
## objective count, objective states x n (0 hidden, 1 active, 2 completed, 3 failed), timer count, (state 0 stopped / 1 running / 2
## expired, end tick, length ticks) x n]. false (and `out` cleared) when the match has no mission.
func mission_state(out: PackedInt32Array) -> bool:
	out.clear()
	return false


# ---- map ------------------------------------------------------------------------------------------------------------
func passable(_cx: int, _cy: int, _move_class: int) -> bool:
	_ni("passable")
	return false


## Resource under the pointer: live amount when visible, the static maximum when explored, 0 otherwise.
func deposit_at(_cx: int, _cy: int) -> int:
	_ni("deposit_at")
	return 0


# ---- events (AppEvents only) ----------------------------------------------------------------------------------------
## Stride-10 records [type, tick, x, y, a, b, c, d, e, f].
func take_events() -> PackedInt32Array:
	_ni("take_events")
	return PackedInt32Array()
