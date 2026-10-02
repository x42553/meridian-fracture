class_name DefRoster
extends RefCounted
## Resolved def set of one roster (data_balance 3.6). The loader creates the shell (id, index, faction, parent, kind);
## `DefRosterBuilder` (DATA-06) fills the resolved clones, lists and selector caches. Immutable after build.

var index: int = -1
var id: String = ""  ## "roster.napc.canada"
var faction: int = -1  ## DefFaction index
var parent: int = -1  ## roster index of vanilla; -1 for vanilla / base
var is_vanilla: bool = false
var units: Array[DefUnit] = []  ## size == data.units.size(): resolved clone or null (not in roster)
var structures: Array[DefStructure] = []  ## size == data.structures.size()
var producible_units: PackedInt32Array = PackedInt32Array()  ## ascending (tier, cost, index); excludes summons/drones
var producible_structures: PackedInt32Array = PackedInt32Array()  ## ascending (build_tier, cost, index); excludes HQ
var spawnables: PackedInt32Array = PackedInt32Array()  ## summon/drone unit indices reachable from this roster
var research_list: PackedInt32Array = PackedInt32Array()  ## [shared0, shared1, exclusive?]
var power_list: PackedInt32Array = PackedInt32Array()  ## [shared0, shared1, third]
var superweapon: int = -1  ## DefSuperweapon index
var superweapon_def: DefSuperweapon = null  ## resolved clone
var modifier_list: PackedInt32Array = PackedInt32Array()  ## modifier indices, parents first
var player_params: Dictionary = {}
var replaced_by: Dictionary = {}  ## baseline unit index -> replacement unit index (this roster only)
var hq_idx: int = -1  ## structure index of the start HQ (SF_NO_BUILD structure), requested by the kernel
var mcv_idx: int = -1  ## unit index of the HQ's deploy unit (MCV)
var sums_d: int = 0  ## def stride of the layer-sum arrays (max(units, structures))
var sums_s1: PackedInt32Array = PackedInt32Array()  ## [(kind_slot * sums_d + def) * 13 + stat] parent-layer sums (bp)
var sums_s2: PackedInt32Array = PackedInt32Array()  ## same, subfaction layer
var cond_apps: Array[DefCondApplication] = []  ## the conditional bible modifiers of this roster
var applied_count: int = 0  ## (target, stat) folds that changed a value (diagnostic, not hashed)
var noop_count: int = 0  ## folds that were no-ops (base 0), diagnostic
var _data_ref: WeakRef = null  ## GameData (weak: GameData owns the rosters)
var _sel_cache: Dictionary = {}  ## selector index -> [units, structures] (PackedInt32Array pair)
var ui_title: String = ""
var ui_identity: String = ""
var ui_lore: String = ""
var ui_opening: String = ""
var ui_counterplay: String = ""


## Binds the roster to its GameData (weakly) so selector queries work; DefRosterBuilder calls this.
func bind(data: GameData) -> void:
	_data_ref = weakref(data)
	_sel_cache.clear()


## Units of THIS roster matched by a selector (include_replacements closure applied); cached.
func selector_units(sel_idx: int) -> PackedInt32Array:
	return _matches(sel_idx)[0]


func selector_structures(sel_idx: int) -> PackedInt32Array:
	return _matches(sel_idx)[1]


## Size == data.units.size(), 1 = matched.
func selector_mask_units(sel_idx: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(units.size())
	for i: int in selector_units(sel_idx):
		m[i] = 1
	return m


func selector_mask_structures(sel_idx: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(structures.size())
	for i: int in selector_structures(sel_idx):
		m[i] = 1
	return m


## The conditional (runtime-evaluated / statically folded) bible modifiers of this roster with their resolved sets.
func conditional_applications() -> Array[DefCondApplication]:
	return cond_apps


## [S1, S2] bp layer sums folded into the clone's resolved value ([0, 0] when none). kind = UNIT or STRUCTURE; weapon
## stats report the sums of weapon slot 0.
func static_sums(kind: int, def_idx: int, stat: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array([0, 0])
	if sums_d <= 0 or stat < 0 or stat >= DefEnums.STAT_COUNT_BIBLE or def_idx < 0 or def_idx >= sums_d:
		return out
	var ks: int = 0 if kind == DefEnums.Kind.UNIT else 1
	var i: int = (ks * sums_d + def_idx) * DefEnums.STAT_COUNT_BIBLE + stat
	if i < sums_s1.size():
		out[0] = sums_s1[i]
		out[1] = sums_s2[i]
	return out


func _matches(sel_idx: int) -> Array:
	if _sel_cache.has(sel_idx):
		return _sel_cache[sel_idx]
	var us: PackedInt32Array = PackedInt32Array()
	var ss: PackedInt32Array = PackedInt32Array()
	var data: GameData = _data_ref.get_ref() as GameData if _data_ref != null else null
	if data != null and sel_idx >= 0 and sel_idx < data.selectors.size():
		var sel: DefSelector = data.selectors[sel_idx]
		for u: DefUnit in units:
			if u != null and DefResolver.unit_matches(data, sel, u):
				us.append(u.index)
		for s: DefStructure in structures:
			if s != null and DefResolver.matches_structure(sel, s.tags, s.index, s.weapon_tags):
				ss.append(s.index)
	var res: Array = [us, ss]
	_sel_cache[sel_idx] = res
	return res


func has_unit(unit_idx: int) -> bool:
	return unit_idx >= 0 and unit_idx < units.size() and units[unit_idx] != null


func has_structure(structure_idx: int) -> bool:
	return structure_idx >= 0 and structure_idx < structures.size() and structures[structure_idx] != null


## The roster clone of a unit def, null when absent.
func unit(unit_idx: int) -> DefUnit:
	return units[unit_idx] if unit_idx >= 0 and unit_idx < units.size() else null


func structure(structure_idx: int) -> DefStructure:
	return structures[structure_idx] if structure_idx >= 0 and structure_idx < structures.size() else null


## Roster-available producible units of one structure, in `producible_units` order.
func units_produced_by(structure_idx: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for u: int in producible_units:
		var d: DefUnit = units[u]
		if d != null and d.producer == structure_idx:
			out.append(u)
	return out


## (owned & req) == req.
static func prereqs_met(requires_mask: int, owned_structure_mask: int) -> bool:
	return (owned_structure_mask & requires_mask) == requires_mask


func research_slot(research_idx: int) -> int:
	return research_list.find(research_idx)


func power_slot(power_idx: int) -> int:
	return power_list.find(power_idx)


## Mixes the roster (lists, params, every non-null clone) into `h`.
func hash_into(h: int) -> int:
	h = DefHash.mix_str(h, id)
	h = DefHash.mix_int(h, faction)
	h = DefHash.mix_int(h, parent)
	h = DefHash.mix_variant(h, is_vanilla)
	h = DefHash.mix_variant(h, producible_units)
	h = DefHash.mix_variant(h, producible_structures)
	h = DefHash.mix_variant(h, spawnables)
	h = DefHash.mix_variant(h, research_list)
	h = DefHash.mix_variant(h, power_list)
	h = DefHash.mix_int(h, superweapon)
	h = DefHash.mix_variant(h, modifier_list)
	h = DefHash.mix_variant(h, player_params)
	h = DefHash.mix_int(h, hq_idx)
	h = DefHash.mix_int(h, mcv_idx)
	if sums_d > 0:  # rosters built by DefRosterBuilder (hand-made test rosters have no layer sums)
		h = DefHash.mix_variant(h, sums_s1)
		h = DefHash.mix_variant(h, sums_s2)
		for ca: DefCondApplication in cond_apps:
			h = DefHash.hash_def(h, ca)
	var rb: Array = replaced_by.keys()
	rb.sort()
	for k: int in rb:
		h = DefHash.mix_int(DefHash.mix_int(h, k), replaced_by[k])
	for i: int in units.size():
		if units[i] != null:
			h = DefHash.hash_def(DefHash.mix_int(h, i), units[i])
	for i: int in structures.size():
		if structures[i] != null:
			h = DefHash.hash_def(DefHash.mix_int(h, i), structures[i])
	if superweapon_def != null:
		h = DefHash.hash_def(h, superweapon_def)
	return h
