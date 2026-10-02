class_name ViewEventRouter
extends RefCounted
## Walks one event batch in emission order and applies the lifecycle / hit / fire reactions to the entity mirror (render spec
## 6.2). The batch is the kernel's own layout `[type, tick, x, y, a, b, c, d, e, f]` (stride 10; sim_core wins over the render
## spec's a..h draft) with the codes of the domain blocks (core 1-9, combat 200-229, abilities 230-259, economy 300-499).
## The reaction names of the spec table (DIED, DAMAGE, WEAPON_FIRED, ...) map to those codes in NAME_TABLE. Records are
## self-contained: handlers use the payload, never the live entity. FX reactions belong to the FX wave: it plugs in through
## `extra_handler` (called with `(events, o)` for every record) or replaces this router's table.
##
## Payloads used (after x, y in the header):
##   SPAWNED  a id . b kind . c def . d owner . e facing . f reason        REMOVED  a id . b kind . c def . d owner . e reason
##   OWNER_CHANGED a id . b old . c new . d reason
##   EV_DEATH a id . b def . c death_kind | cause << 4 | flags << 8 . d killer . e pids . f facing | layer << 12 | dying << 16
##   EV_HIT   a victim . b damage . c attacker . d dtype | dc << 8 | flags << 16 . e hp . f hp_max
##   EV_FIRE  a shooter . b weapon arch . c mount | barrel << 4 | kind << 8 | result << 12 . d target . e, f impact
##   EVT_UNIT_PRODUCED a owner . b unit id . c def . d producer id      EVT_STRUCTURE_SELLING a owner . b id . c until tick

const H_NONE: int = 0
const H_SPAWNED: int = 1
const H_REMOVED: int = 2
const H_DIED: int = 3
const H_OWNER: int = 4
const H_HIT: int = 5
const H_FIRE: int = 6
const H_PRODUCED: int = 7
const H_SELLING: int = 8
const H_CRASH: int = 9
const H_MATCH_END: int = 10

## Spec reaction name -> [handler, class that owns the constant, constant name]. `_validate_codes` checks every entry.
const NAME_TABLE: Array[Array] = [
	[H_SPAWNED, "SimEvent", "SPAWNED"],
	[H_REMOVED, "SimEvent", "REMOVED"],
	[H_OWNER, "SimEvent", "OWNER_CHANGED"],
	[H_MATCH_END, "SimEvent", "MATCH_END"],
	[H_DIED, "SimCombatConsts", "EV_DEATH"],
	[H_HIT, "SimCombatConsts", "EV_HIT"],
	[H_FIRE, "SimCombatConsts", "EV_FIRE"],
	[H_CRASH, "SimCombatConsts", "EV_CRASH"],
	[H_PRODUCED, "SimEconConst", "EVT_UNIT_PRODUCED"],
	[H_SELLING, "SimEconConst", "EVT_STRUCTURE_SELLING"],
]

## Death windows in ticks (render spec 5.9.4 `meta.death.ticks`): vehicle 2, infantry 2, crash 30, air_explode 1, sink 60, structure 7,
## drone 1, silent 8. Index = ViewConsts.DK_*.
const DYING_TICKS: Array[int] = [2, 2, 2, 30, 1, 60, 7, 1, 8]
const SILENT_TICKS: int = 8
const HIT_KILL_BLOW: int = 1

## Optional hook of later waves (FX router): `func(events: PackedInt32Array, o: int) -> void`, called for every record.
var extra_handler: Callable = Callable()
## Test seam: class name -> constant map; empty = read the live script constants.
var const_maps: Dictionary = {}

var _v: ViewWorld = null
var _table: Dictionary = {}  # event code -> handler id
var _stats: Dictionary = {"events": 0, "unknown": 0, "spawned": 0, "duplicates": 0, "died": 0, "hit": 0, "fire": 0}
var _known_ignored: Dictionary = {}


func setup(v: ViewWorld) -> void:
	_v = v
	rebuild_table()
	var bad: PackedStringArray = _validate_codes()
	for n: String in bad:
		Log.error("view.events", "consumed event constant missing in the kernel: %s (handler ignored)" % n)
	_known_ignored.clear()
	for name_: String in ["CASH", "CMD_REJECTED", "ORDER_FAILED", "PLAYER_ELIMINATED", "NAV_CHANGED"]:
		var c: Variant = _constants_of("SimEvent").get(name_)
		if c is int:
			_known_ignored[c as int] = true


## Builds code -> handler from the constants that exist; a missing constant is skipped (reported by _validate_codes).
func rebuild_table() -> void:
	_table.clear()
	for row: Array in NAME_TABLE:
		var code: Variant = _constants_of(row[1] as String).get(row[2] as String)
		if code is int:
			_table[code as int] = row[0] as int


## Consumed constant names ("SimEvent.SPAWNED") that do not exist in the (possibly injected) constant maps.
func _validate_codes() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Array in NAME_TABLE:
		if not _constants_of(row[1] as String).has(row[2] as String):
			out.append("%s.%s" % [row[1], row[2]])
	return out


func _constants_of(cls: String) -> Dictionary:
	if const_maps.has(cls):
		return const_maps[cls] as Dictionary
	match cls:
		"SimEvent":
			return (SimEvent as GDScript).get_script_constant_map()
		"SimCombatConsts":
			return (SimCombatConsts as GDScript).get_script_constant_map()
		"SimEconConst":
			return (SimEconConst as GDScript).get_script_constant_map()
	return {}


func stats() -> Dictionary:
	return _stats


## One sequential pass over the batch in emission order.
func process(events: PackedInt32Array) -> void:
	var o: int = 0
	var n: int = events.size()
	var hook: bool = extra_handler.is_valid()
	while o + SimEvent.STRIDE <= n:
		_stats["events"] = (_stats["events"] as int) + 1
		var h: int = _table.get(events[o], H_NONE) as int
		if h != H_NONE:
			_dispatch(h, events, o)
		elif not _known_ignored.has(events[o]):
			_stats["unknown"] = (_stats["unknown"] as int) + 1
		if hook:
			extra_handler.call(events, o)
		o += SimEvent.STRIDE


func _dispatch(h: int, ev: PackedInt32Array, o: int) -> void:
	match h:
		H_SPAWNED:
			_on_spawned(ev, o)
		H_REMOVED:
			_on_removed(ev, o)
		H_DIED:
			_on_died(ev, o)
		H_HIT:
			_on_hit(ev, o)
		H_FIRE:
			_on_fire(ev, o)
		H_OWNER:
			_on_owner(ev, o)
		H_PRODUCED:
			_on_produced(ev, o)
		H_SELLING:
			_on_selling(ev, o)
		H_CRASH:
			_on_crash(ev, o)
		H_MATCH_END:
			_v.match_over = true
		_:
			pass


func _on_spawned(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	if _v.has_entity(id):
		_stats["duplicates"] = (_stats["duplicates"] as int) + 1
		return
	_stats["spawned"] = (_stats["spawned"] as int) + 1
	_v.create_entity(id, ev[o + 5], ev[o + 6], ev[o + 7], ev[o + 2], ev[o + 3], ev[o + 8], ev[o + 9], ev[o + 1])


func _on_removed(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve == null:
		return
	var reason: int = ev[o + 8]
	var tick: int = ev[o + 1]
	match reason:
		SimEvent.REM_KILLED:
			ve.sim_gone = true
			if not ve.dead:
				_v.dispose_entity(ve)  # no DIED seen (a wreck shot to pieces, a silent kill): nothing to show
		SimEvent.REM_SOLD, SimEvent.REM_DEPLOYED:
			_v.dispose_entity(ve)
		_:
			ve.sim_gone = true
			if not ve.dead:
				ve.dead = true
				ve.dying_kind = ViewConsts.DK_SILENT
				ve.dying_until_tick = tick + SILENT_TICKS
			ve.dying_start_tick = tick


func _on_died(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve == null:
		return
	_stats["died"] = (_stats["died"] as int) + 1
	var tick: int = ev[o + 1]
	var dk: int = ev[o + 6] & 15
	var sim_ticks: int = (ev[o + 9] >> 16) & 0xFFFF
	if dk <= 0 or dk >= DYING_TICKS.size():
		dk = ViewConsts.DK_STRUCTURE if ve.kind != SimEntity.Kind.UNIT else (ViewConsts.DK_INFANTRY if ve.motion == ViewConsts.MOTION_FOOT else ViewConsts.DK_VEHICLE)
	var window: int = DYING_TICKS[dk]
	if dk == ViewConsts.DK_CRASH or dk == ViewConsts.DK_SINK:
		window = maxi(window, sim_ticks)
	ve.dead = true
	ve.dying_kind = dk
	ve.dying_start_tick = tick
	ve.dying_until_tick = tick + window
	ve.hp = 0
	ve.killer_id = ev[o + 7]
	ve.death_x = ev[o + 2]
	ve.death_y = ev[o + 3]


func _on_crash(ev: PackedInt32Array, o: int) -> void:
	# start (b == 0): the fall is already scheduled by DIED (dying_kind CRASH); nothing else to mirror
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve != null and ev[o + 5] == 0 and ve.dead and ve.dying_kind == ViewConsts.DK_CRASH:
		ve.dying_until_tick = maxi(ve.dying_until_tick, ev[o + 1] + ev[o + 6])


func _on_hit(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve == null:
		return
	_stats["hit"] = (_stats["hit"] as int) + 1
	var dmg_flags: int = (ev[o + 7] >> 16) & 0xFFFF
	ve.on_hit(ev[o + 5], dmg_flags)
	ve.hp = ev[o + 8]
	ve.max_hp = maxi(ve.max_hp, ev[o + 9])
	if _v.health_bars != null:
		_v.health_bars.mark_damaged(ve.id, ev[o + 1])


func _on_fire(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve == null:
		return
	_stats["fire"] = (_stats["fire"] as int) + 1
	var c: int = ev[o + 6]
	ve.on_fire(c & 15, (c >> 4) & 15)


func _on_owner(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = _v.entity_view(ev[o + 4])
	if ve != null:
		_v.set_entity_owner(ve, ev[o + 6])


func _on_produced(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewStructure = _v.entity_view(ev[o + 7]) as ViewStructure
	if ve != null:
		ve.open_door()


func _on_selling(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewStructure = _v.entity_view(ev[o + 5]) as ViewStructure
	if ve == null:
		return
	var tick: int = ev[o + 1]
	ve.begin_phase(ViewConsts.PH_SELLING, tick, ev[o + 6] - tick if ev[o + 6] > tick else ViewStructure.DEFAULT_SELL_TICKS)
	_v.note_phase(ve)
