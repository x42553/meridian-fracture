class_name DefWeaponArch
extends DefBase
## One of the 27 TAXONOMY weapon archetypes (id "warch.<name>", index == frozen DefEnums.WeaponArch; data_balance 4.2).
## Built from `global.json -> weapon_archetypes`; `tags` = derived weapon tags (WT_*).

var dtype: int = 0
var fire_mode: int = 0
var proj_kind: int = 0
var proj_speed: int = 0  ## upt, 0 = hitscan / beam
var homing: bool = false
var target_mask: int = 0  ## default layer targets
var splash_radius: int = 0
var splash_edge_bp: int = 0
var scatter: int = 0
var range_lo: int = 0  ## u band
var range_hi: int = 0
var min_range: int = 0
var reload_lo_mt: int = 0
var reload_hi_mt: int = 0
var turret_turn: int = 0  ## apt
var interceptable: int = 0
var suppressive_default: bool = false


func _init() -> void:
	kind = DefEnums.Kind.WEAPON_ARCH


## Builds all archetypes of `g` (global.json) in frozen index order. Vocabulary mismatches report V-CNF-05.
static func build_all(g: Dictionary, rep: DefLoadReport) -> Array[DefWeaponArch]:
	var out: Array[DefWeaponArch] = []
	var src: Dictionary = g.get("weapon_archetypes", {})
	for i: int in DefEnums.WeaponArch.COUNT:
		var name: String = DefEnums.WEAPON_ARCH_NAMES[i]
		var w: DefWeaponArch = DefWeaponArch.new()
		w.id = "warch." + name
		w.index = i
		w.kind = DefEnums.Kind.WEAPON_ARCH
		out.append(w)
		if not src.has(name):
			rep.error("V-CNF-05", "global.json weapon_archetypes", "missing archetype '%s'" % name)
			continue
		var d: Dictionary = src[name]
		var ctx: String = "global.json weapon_archetypes.%s" % name
		if int(d.get("index", -1)) != i:
			rep.error("V-CNF-05", ctx, "index %s != frozen %d" % [str(d.get("index")), i])
		w.dtype = _enum(DefEnums.DAMAGE_NAMES, d.get("damage_type", ""), ctx, rep)
		w.fire_mode = _enum(DefEnums.FIRE_NAMES, d.get("fire_mode", ""), ctx, rep)
		w.proj_kind = _enum(DefEnums.PROJ_NAMES, d.get("projectile_kind", ""), ctx, rep)
		w.interceptable = _enum(DefEnums.INTERCEPT_NAMES, d.get("interceptable_by", "none"), ctx, rep)
		w.proj_speed = DefConvert.cells_s_to_upt(DefNumParse.milli(d.get("projectile_speed_cells_s", 0), ctx, rep))
		w.homing = bool(d.get("homing", false))
		var tm: int = 0
		for layer: Variant in d.get("targets", []):
			tm |= DefEnums.layer_bit(str(layer))
		w.target_mask = tm
		w.splash_radius = DefConvert.cells_to_units(DefNumParse.milli(d.get("splash_cells", 0), ctx, rep))
		w.splash_edge_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(d.get("splash_edge_pct", 0), ctx, rep))
		w.scatter = DefConvert.cells_to_units(DefNumParse.milli(d.get("scatter_cells", 0), ctx, rep))
		w.min_range = DefConvert.cells_to_units(DefNumParse.milli(d.get("min_range_cells", 0), ctx, rep))
		var rb: Array = d.get("range_cells_band", [0, 0])
		w.range_lo = DefConvert.cells_to_units(DefNumParse.milli(rb[0], ctx, rep))
		w.range_hi = DefConvert.cells_to_units(DefNumParse.milli(rb[1], ctx, rep))
		var sb: Array = d.get("reload_s_band", [0, 0])
		w.reload_lo_mt = DefConvert.seconds_to_mt(DefNumParse.milli(sb[0], ctx, rep))
		w.reload_hi_mt = DefConvert.seconds_to_mt(DefNumParse.milli(sb[1], ctx, rep))
		w.turret_turn = DefConvert.deg_s_to_apt(DefNumParse.milli(d.get("turret_deg_s", 0), ctx, rep))
		w.suppressive_default = bool(d.get("suppressive_default", false))
		w.tags = derived_tags(w)
	return out


## Derived weapon tags (data_balance 5.9.2).
static func derived_tags(w: DefWeaponArch) -> int:
	var t: int = 0
	if w.dtype == DefEnums.DamageType.THERMAL:
		t |= DefEnums.WT_THERMAL_BEAM
	if w.interceptable == DefEnums.Interceptable.APS_TRIDENT:
		t |= DefEnums.WT_GUIDED_MISSILE
	if w.fire_mode == DefEnums.FireMode.INDIRECT:
		t |= DefEnums.WT_INDIRECT_FIRE
	else:
		t |= DefEnums.WT_DIRECT_FIRE
	if (w.target_mask & DefEnums.L_AIR) != 0:
		t |= DefEnums.WT_ANTI_AIR
	if (w.target_mask & (DefEnums.L_GROUND | DefEnums.L_WATER)) != 0:
		t |= DefEnums.WT_ANTI_GROUND
	if (w.target_mask & DefEnums.L_UNDER) != 0:
		t |= DefEnums.WT_ANTI_SUB
	return t


static func _enum(names: PackedStringArray, v: Variant, ctx: String, rep: DefLoadReport) -> int:
	var i: int = names.find(str(v))
	if i < 0:
		rep.error("V-CNF-05", ctx, "unknown vocabulary id '%s'" % str(v))
		return 0
	return i
