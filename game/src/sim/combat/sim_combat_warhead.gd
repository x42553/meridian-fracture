class_name SimCombatWarhead
extends RefCounted
## Compiled warhead (combat 4.2 DefWarhead, all ints, immutable after SimCombatTables built it). Private to combat:
## derived from a DefWeaponSlot + its DefWeaponArch (unit/structure weapons) or from a DefImpactPacket
## (superweapons / powers), never from a combat_*.json file.

var id: String = ""
var idx: int = -1
var damage: int = 0  ## base hp damage per instance (per dot tick for beams / sweeps)
var dtype: int = 0  ## DT_*
var delivery: int = 0  ## DELIV_*
var splash_r: int = 0  ## outer radius, units (0 = single victim)
var splash_inner: int = 0  ## full-damage radius (<= splash_r)
var splash_edge_bp: int = 0  ## fraction of full damage at splash_r
var splash_min_r: int = 0  ## annulus: victims closer than this take nothing (Perun ring); 0 = disc
var layer_mask: int = 0  ## victim layers affected: bit (1 << LAYER_*)
var friendly_fire: int = 0  ## 1 = splash may hurt owner / allies / neutrals; 0 = enemies only (Aurora)
var packet: int = 0  ## 1 = strategic impact packet (Trident 8-charge rule)
var suppressive: int = 0  ## 1 = counts toward suppression
var emp_unit_ticks: int = 0  ## weapons-off ticks for victims whose class is in emp_class_mask (non-structures)
var emp_struct_ticks: int = 0  ## shutdown ticks for powered structures
var emp_class_mask: int = 0  ## EC_*
var nonlethal: int = 0  ## 1 = never reduces hp below 1 (forced 1 when dtype == DT_EMP)


## Warhead of a weapon instance. Splash inner radius = splash_r / 4 (the data has no inner radius: request to data).
static func from_slot(s: DefWeaponSlot, arch: DefWeaponArch, nonlethal_mask: int, label: String) -> SimCombatWarhead:
	var w: SimCombatWarhead = SimCombatWarhead.new()
	w.id = label
	w.damage = s.damage
	w.dtype = s.dtype
	w.delivery = SimCombatConsts.DELIV_INDIRECT if s.fire_mode == DefEnums.FireMode.INDIRECT else SimCombatConsts.DELIV_DIRECT
	w.splash_r = s.splash_radius
	w.splash_inner = s.splash_radius / 4
	w.splash_edge_bp = s.splash_edge_bp
	w.layer_mask = s.target_mask & 15
	w.friendly_fire = 1 if s.splash_radius > 0 else 0
	w.suppressive = 1 if ((s.flags & DefEnums.WF_SUPPRESSIVE) != 0 or (arch != null and arch.suppressive_default)) else 0
	if s.dtype == SimCombatConsts.DT_EMP:
		w.emp_unit_ticks = SimCombatConsts.EMP_UNIT_TICKS_DEFAULT
		w.emp_struct_ticks = SimCombatConsts.EMP_STRUCT_TICKS_DEFAULT
		w.emp_class_mask = SimCombatConsts.EC_VEHICLE | SimCombatConsts.EC_AIRCRAFT | SimCombatConsts.EC_SHIP | SimCombatConsts.EC_STRUCTURE
	w.nonlethal = 1 if ((nonlethal_mask >> s.dtype) & 1) == 1 else 0
	return w


## Warhead of a strategic impact packet; `sw` (may be null) supplies EMP durations (params weapon_disable_t /
## structure_shutdown_t) and `packet` marks Trident-reducible impacts (never EMP or beams).
static func from_packet(p: DefImpactPacket, sw: DefSuperweapon, nonlethal_mask: int, label: String) -> SimCombatWarhead:
	var w: SimCombatWarhead = SimCombatWarhead.new()
	w.id = label
	w.damage = p.damage
	w.dtype = p.dtype
	w.delivery = SimCombatConsts.DELIV_STRATEGIC
	w.splash_r = p.radius
	w.splash_inner = 0
	w.splash_edge_bp = p.edge_bp
	w.layer_mask = p.target_mask & 15 if p.target_mask != 0 else 15
	var emp: bool = p.dtype == SimCombatConsts.DT_EMP
	w.friendly_fire = 0 if emp else 1
	w.packet = 0 if (emp or bool(p.params.get("per_second", false))) else 1
	w.nonlethal = 1 if (p.non_lethal or ((nonlethal_mask >> p.dtype) & 1) == 1) else 0
	if emp:
		var unit_t: int = SimCombatConsts.EMP_UNIT_TICKS_DEFAULT
		var struct_t: int = SimCombatConsts.EMP_STRUCT_TICKS_DEFAULT
		if sw != null:
			unit_t = int(sw.params.get("weapon_disable_t", unit_t))
			struct_t = int(sw.params.get("structure_shutdown_t", struct_t))
		w.emp_unit_ticks = unit_t
		w.emp_struct_ticks = struct_t
		w.emp_class_mask = SimCombatConsts.EC_VEHICLE | SimCombatConsts.EC_AIRCRAFT | SimCombatConsts.EC_SHIP | SimCombatConsts.EC_STRUCTURE
	return w
