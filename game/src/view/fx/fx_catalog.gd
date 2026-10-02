class_name FxCatalog
extends RefCounted
## fx-id resolution (render spec 5.9.2-5.9.4): explicit `pres_fx` string -> effect, else defaults by weapon archetype /
## warhead / damage type / death kind. Pure lookups (no engine calls), allocation-light; ids that the recipe book does not know
## fall back through default_fx_for_missing() with a single Log.warn per id.
##
## Tables can be overridden by `fx.json -> mappings` (muzzle_by_family, impact_rules, death_by_kind, arc_apex); the constants
## below are the spec defaults, so an empty book still resolves the spec vocabulary.

## DefWeaponArch index (0..26) -> family name (TAXONOMY 10, render 5.9.2).
const FAMILIES: PackedStringArray = [
	"small_arms", "machine_gun", "autocannon", "tank_cannon", "siege_gun", "demolition_cannon", "at_missile", "aa_missile", "flak",
	"artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "beam_thermal", "rail_gun", "torpedo", "depth_charge", "bomb",
	"air_missile", "emp_pulse", "canister", "grenade_launcher", "breach_charge", "naval_gun", "naval_bombard", "cruise_missile",
	"drone_missile",
]
## Damage types of an impact (DefWeaponArch.dtype / EXPLOSION.g).
const DTYPES: PackedStringArray = ["bullet", "ap", "he", "thermal", "rail", "kinetic", "emp"]
const DTYPE_OF_FAMILY: PackedInt32Array = [
	0, 0, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 4, 2, 2, 2, 2, 6, 0, 2, 2, 2, 2, 2, 2,
]
## Default muzzle id per archetype ("" = none).
const MUZZLES: PackedStringArray = [
	"muzzle_small_arms", "muzzle_mg", "muzzle_autocannon", "muzzle_cannon", "muzzle_siege", "muzzle_demolition", "muzzle_at_missile",
	"muzzle_aa_missile", "muzzle_flak", "muzzle_artillery", "muzzle_rocket", "muzzle_mortar", "muzzle_missile_art", "muzzle_beam_thermal",
	"muzzle_rail", "muzzle_torpedo", "muzzle_depth_charge", "", "muzzle_air_missile", "muzzle_emp", "muzzle_canister", "muzzle_grenade",
	"", "muzzle_naval_gun", "muzzle_bombard", "muzzle_cruise", "muzzle_drone_missile",
]
## Default impact id per archetype (used when the archetype has no splash: hit_* and beam impacts).
const DEFAULT_IMPACTS: PackedStringArray = [
	"hit_bullet", "hit_bullet", "hit_bullet_hv", "expl_small", "expl_medium", "expl_medium", "expl_small", "expl_air_burst",
	"expl_air_burst", "expl_large", "expl_small", "expl_small", "expl_medium", "beam_thermal_hit", "hit_rail", "expl_underwater",
	"expl_underwater_big", "expl_medium", "expl_small", "emp_pulse", "hit_bullet", "expl_small", "expl_medium", "expl_small",
	"expl_large", "expl_large", "expl_small",
]
## Trail effect per archetype ("" = none).
const TRAILS: PackedStringArray = [
	"", "", "", "", "", "", "trail_missile", "trail_missile_white", "", "trail_shell", "trail_rocket", "trail_shell", "trail_missile", "",
	"", "trail_torpedo", "", "", "trail_missile", "", "", "trail_shell", "", "", "trail_shell", "trail_missile", "trail_missile",
]
const DEFAULT_RULES: Array[Array] = [
	["dtype == 'emp'", "emp_pulse"],
	["dtype == 'kinetic'", "expl_kinetic"],
	["strategic", "expl_strategic_large"],
	["splash_m <= 0.01 and dtype == 'rail'", "hit_rail"],
	["splash_m <= 0.01 and dtype == 'thermal'", "beam_thermal_hit"],
	["splash_m <= 0.01", "hit_bullet"],
	["splash_m <= 3.0", "expl_small"],
	["splash_m <= 5.0", "expl_medium"],
	["true", "expl_large"],
]
const DEATH_DEFAULTS: Dictionary = {
	"infantry": "death_infantry", "crash": "aircraft_crash", "air_explode": "death_air_explode", "structure": "building_collapse",
	"drone": "death_drone", "silent": "death_silent",
}
# DefEnums.SizeClass values used by death_id
const SC_LIGHT: int = 1
const SC_MEDIUM: int = 2
const SC_SHIP_MEDIUM: int = 8
# ViewConsts death kinds
const DK_VEHICLE: int = 1
const DK_INFANTRY: int = 2
const DK_CRASH: int = 3
const DK_AIR_EXPLODE: int = 4
const DK_SINK: int = 5
const DK_STRUCTURE: int = 6
const DK_DRONE: int = 7
const DK_SILENT: int = 8
const RESULT_ENTITY: int = 1
const RESULT_WATER: int = 3
const RESULT_INTERCEPTED: int = 4
const RESULT_EXPIRED: int = 5
const UNITS_TO_M: float = 3.0 / 1024.0

## GameData.pres_names (sorted unique `fx` strings); index = EXPLOSION.d - 1. Set by the router.
var pres_names: PackedStringArray = PackedStringArray()

var _book: FxRecipeBook = null
var _rules: Array = []  # [ViewExpr, StringName]
var _scope: ViewExpr.Scope = ViewExpr.Scope.new()
var _frame: Array = []
var _muzzle_by_family: Dictionary = {}
var _death_by_kind: Dictionary = {}
var _warned: Dictionary = {}
var _fallbacks: Dictionary = {}


func _init(book: FxRecipeBook = null) -> void:
	setup(book)


## (Re)binds to a compiled book and compiles `mappings.impact_rules`.
func setup(book: FxRecipeBook) -> void:
	_book = book
	_rules.clear()
	_muzzle_by_family.clear()
	_death_by_kind.clear()
	_scope = ViewExpr.Scope.new()
	for nm: String in ["dtype", "splash_m", "strategic", "result"]:
		_scope.slot(StringName(nm))
	var raw: Array = []
	if book != null and book.mappings.get("impact_rules", null) is Array:
		raw = book.mappings["impact_rules"] as Array
	var quiet_was: bool = ViewExpr.quiet
	ViewExpr.quiet = true
	if raw.is_empty():
		for r: Array in DEFAULT_RULES:
			_add_rule(r[0] as String, r[1] as String)
	else:
		for r: Variant in raw:
			if r is Dictionary:
				_add_rule(str((r as Dictionary).get("if", "false")), str((r as Dictionary).get("fx", "")))
	ViewExpr.quiet = quiet_was
	_frame = _scope.make_frame()
	if book != null:
		_muzzle_by_family = book.mappings.get("muzzle_by_family", {}) as Dictionary if book.mappings.get("muzzle_by_family", {}) is Dictionary else {}
		_death_by_kind = book.mappings.get("death_by_kind", {}) as Dictionary if book.mappings.get("death_by_kind", {}) is Dictionary else {}


func _add_rule(cond: String, fx_id: String) -> void:
	var e: ViewExpr = ViewExpr.compile(cond, _scope, "")
	if e == null:
		Log.warn("view", "FxCatalog: bad impact rule '%s': %s" % [cond, ViewExpr.last_error])
		return
	_rules.append([e, StringName(fx_id)])


## "muzzle_" family effect of a weapon archetype; a non-empty `pres_muzzle` (the def's `pres_fx.muzzle`) wins. &"" = no muzzle fx.
func muzzle_id(warch: int, pres_muzzle: String = "") -> StringName:
	if pres_muzzle != "":
		return _known(StringName(pres_muzzle))
	if warch < 0 or warch >= FAMILIES.size():
		return &""
	var fam: String = FAMILIES[warch]
	var id: String = str(_muzzle_by_family.get(fam, MUZZLES[warch]))
	if id == "":
		return &""
	return _known(StringName(id))


## Effect of a projectile impact. `result` = PROJECTILE_IMPACT.f (1 entity, 2 ground, 3 water, 4 intercepted, 5 expired),
## `splash_radius_units` = PROJECTILE_IMPACT.g (sim units, 1024 per cell of 3 m), `target_air` = the entity hit is airborne.
func impact_id(warch: int, result: int, splash_radius_units: int, target_air: bool = false) -> StringName:
	var fam: int = clampi(warch, 0, FAMILIES.size() - 1)
	var splash_m: float = float(splash_radius_units) * UNITS_TO_M
	if result == RESULT_INTERCEPTED:
		return _known(&"aps_flash")
	if result == RESULT_WATER:
		if fam == 15:
			return _known(&"expl_underwater")
		if fam == 16:
			return _known(&"expl_underwater_big")
		return _known(&"impact_water")
	if result == RESULT_EXPIRED:
		return _known(&"expl_air_burst" if (fam == 7 or fam == 8) else &"hit_flak_small")
	if result == RESULT_ENTITY and target_air:
		return _known(&"expl_air_burst")
	if splash_m <= 0.01:
		var dflt: String = DEFAULT_IMPACTS[fam]
		if dflt.begins_with("hit_") or dflt.begins_with("beam_") or dflt == "emp_pulse":
			return _known(StringName(dflt))
	return _rule_fx(DTYPES[DTYPE_OF_FAMILY[fam]], splash_m, false, result)


## EXPLOSION event: data fx name when `fx_kind` > 0 (index + 1 into `pres_names`) and known, else the 5.9.3 rules by
## radius and damage type (0 bullet, 1 ap, 2 he, 3 thermal, 4 rail, 5 kinetic, 6 emp).
func explosion_id(fx_kind: int, radius_units: int, damage_type: int) -> StringName:
	if fx_kind > 0:
		if fx_kind <= pres_names.size():
			var nm: StringName = StringName(pres_names[fx_kind - 1])
			if _book != null and _book.has(nm):
				return nm
			return default_fx_for_missing(nm)
		return default_fx_for_missing(StringName("pres_%d" % fx_kind))
	var dt: String = DTYPES[clampi(damage_type, 0, DTYPES.size() - 1)]
	return _rule_fx(dt, float(radius_units) * UNITS_TO_M, false, 2)


## Scale to pass to spawn() so an `expl_*` effect matches the splash: r = clamp(0.55 R + 0.5, 1, 12) m against the id's base radius.
func explosion_scale(id: StringName, splash_radius_units: int) -> float:
	var r: float = clampf(0.55 * float(splash_radius_units) * UNITS_TO_M + 0.5, 1.0, 12.0)
	var base: float = 1.0
	if id == &"expl_small":
		base = 1.8
	elif id == &"expl_medium":
		base = 3.6
	elif id == &"expl_large":
		base = 8.0
	else:
		return 1.0
	return clampf(r / base, 0.5, 3.0)


func trail_id(warch: int) -> StringName:
	if warch < 0 or warch >= TRAILS.size() or TRAILS[warch] == "":
		return &""
	return _known(StringName(TRAILS[warch]))


## `death_kind` = ViewConsts.DK_*, `size_class` = DefEnums.SizeClass (vehicles: <= LIGHT light, MEDIUM medium, else heavy; ships:
## < SHIP_MEDIUM small, else large), `flags` is reserved (bit 0 = a wreck follows; the router starts `wreck_start` itself).
func death_id(death_kind: int, size_class: int, _flags: int = 0) -> StringName:
	var id: String = ""
	match death_kind:
		DK_VEHICLE:
			id = "death_vehicle_light" if size_class <= SC_LIGHT else ("death_vehicle_medium" if size_class == SC_MEDIUM else "death_vehicle_heavy")
		DK_SINK:
			id = "death_sink_small" if size_class < SC_SHIP_MEDIUM else "death_sink_large"
		DK_INFANTRY:
			id = str(_death_by_kind.get("infantry", DEATH_DEFAULTS["infantry"]))
		DK_CRASH:
			id = str(_death_by_kind.get("crash", DEATH_DEFAULTS["crash"]))
		DK_AIR_EXPLODE:
			id = str(_death_by_kind.get("air_explode", DEATH_DEFAULTS["air_explode"]))
		DK_STRUCTURE:
			id = str(_death_by_kind.get("structure", DEATH_DEFAULTS["structure"]))
		DK_DRONE:
			id = str(_death_by_kind.get("drone", DEATH_DEFAULTS["drone"]))
		DK_SILENT:
			id = str(_death_by_kind.get("silent", DEATH_DEFAULTS["silent"]))
		_:
			return &""
	return _known(StringName(id))


## Arc apex factor (apex = factor x distance) of an archetype family, from `mappings.arc_apex` (0 = flat).
func arc_apex(warch: int) -> float:
	if warch < 0 or warch >= FAMILIES.size() or _book == null:
		return 0.0
	var m: Variant = _book.mappings.get("arc_apex", null)
	if m is Dictionary:
		return float((m as Dictionary).get(FAMILIES[warch], 0.0))
	return 0.0


## Fallback for an effect id the book does not know (one Log.warn per id): the nearest family default, or &"" for none.
func default_fx_for_missing(id: StringName) -> StringName:
	if _fallbacks.has(id):
		return _fallbacks[id] as StringName
	var s: String = String(id)
	var fb: String = ""
	if s.begins_with("muzzle_"):
		fb = "muzzle_small_arms"
	elif s.begins_with("expl_") or s.begins_with("hit_"):
		fb = "expl_small" if s.begins_with("expl_") else "hit_bullet"
	elif s.begins_with("death_"):
		fb = "death_vehicle_medium"
	elif s.begins_with("trail_"):
		fb = ""
	elif s.begins_with("sw_") or s.begins_with("power_") or s.begins_with("zone_"):
		fb = "power_cast_ring"
	var out: StringName = StringName(fb)
	if fb != "" and (_book == null or not _book.has(out)):
		out = &""
	if not _warned.has(id):
		_warned[id] = true
		Log.warn("view", "FxCatalog: unknown fx '%s' -> '%s'" % [s, String(out)])
	_fallbacks[id] = out
	return out


# ---------------------------------------------------------------------------------------------- internals
func _rule_fx(dtype: String, splash_m: float, strategic: bool, result: int) -> StringName:
	var fr: Array = _frame
	fr[_scope.slot(&"dtype")] = dtype
	fr[_scope.slot(&"splash_m")] = splash_m
	fr[_scope.slot(&"strategic")] = 1.0 if strategic else 0.0
	fr[_scope.slot(&"result")] = float(result)
	for r: Array in _rules:
		if (r[0] as ViewExpr).eval_bool(fr):
			return _known(r[1] as StringName)
	return _known(&"expl_small")


func _known(id: StringName) -> StringName:
	if _book == null or _book.has(id):
		return id
	return default_fx_for_missing(id)
