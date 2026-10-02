class_name SimCombatDef
extends RefCounted
## Compiled combat view of one def for one player view (private to combat; built by SimCombatTables, immutable
## afterwards except by tests). Replaces the spec's DefCombat: derived from the roster clone's DefWeaponSlots,
## abilities and armor class, never from a combat_*.json file.

## Mount table stride and column indices (`mounts`).
const MT: int = 15
const MT_SLOT: int = 0  ## index into the def's weapons[]
const MT_KIND: int = 1  ## MK_*
const MT_ARC_CENTER: int = 2  ## bat, relative to the hull
const MT_ARC_HALF: int = 3  ## >= 2048 = 360 degrees
const MT_TURN: int = 4  ## bat/tick, 0 for a fixed mount
const MT_AIM_TOL: int = 5
const MT_OFF_FWD: int = 6
const MT_OFF_SIDE: int = 7
const MT_BARRELS: int = 8
const MT_INDEP: int = 9  ## 1 = own target selection (AA, ASW, secondary guns)
const MT_WCLASS: int = 10  ## WC_*
const MT_WH: int = 11  ## warhead index in the owning SimCombatTables
const MT_MODE_MASK: int = 12  ## DefWeaponSlot.mode_mask (0 = always)
const MT_REQ_DEPLOYED: int = 13  ## -1 any, 0 must be undeployed, 1 must be deployed
const MT_FLAGS: int = 14  ## DefWeaponSlot.flags (WF_*)

var kind: int = 0  ## SimEntity.Kind
var def_idx: int = -1
var tags: int = 0  ## UT_* / ST_* of the def
var armor: int = 0  ## DefEnums.ArmorClass
var n_mounts: int = 0
var mounts: PackedInt32Array = PackedInt32Array()  ## n_mounts * MT
var prof: PackedInt32Array = PackedInt32Array()  ## n_mounts * SimWeaponProfile.PN (derived by SimWeaponProfile.derive)
var cflags: int = 0  ## static CF_* bits (CF_HAS_AA, CF_HAS_ASW, CF_SUPPRESSIBLE)
var prio: int = 0  ## threat priority 0..15
var stance_default: int = 0
var needs_power: int = 0  ## powered defence (SF_POWERED_DEFENSE): non-functional without F_POWERED
var emp_susceptible: int = 0  ## structures: shut down by EMP
var garrison_fire: int = 1
var is_aircraft: int = 0
var pad_count: int = 0  ## airfield pads (structures)
var carrier_bays: int = 0  ## drone bays (carriers)
var resist_rows: PackedInt32Array = PackedInt32Array()  ## stride 4: [filter, bp, layer, cond] (base layer rows)
var dir_rows: PackedInt32Array = PackedInt32Array()  ## stride 5: [filter, arc_center, arc_half, bp, layer]
var static_resist: PackedInt32Array = PackedInt32Array([0, 0])  ## unconditional faction sums [parent, sub] in bp
var aps_count: int = 0
var aps_cooldown: int = 0
var aps_radius: int = 0
# ---- death profile (SimDeath.compile fills it; combat 5.11) ----
var death_kind: int = SimCombatConsts.DK_NONE  ## DK_*
var dying_ticks: int = 1  ## > 1: the corpse lingers (CF_DYING) before removal
var wreck_hp_bp: int = 0  ## > 0: land combat vehicles leave a wreck
var cargo_mode: int = -1  ## CARGO_* for containers, -1 = no occupants possible
var eject_hurt_bp: int = 0  ## CARGO_EJECT_HURT: fraction of hp_max taken by each passenger
var chain_wh: int = -1  ## warhead ref (SimProjectiles.NEUTRAL_REF | idx in the neutral table), -1 = no chain blast
var chain_delay: int = 3
var crash_ticks: int = 30  ## DK_CRASH fall time
var crash_wh: int = -1  ## warhead ref of the ground impact
# ---- aircraft (SimAirSortie.derive fills them for is_aircraft defs; combat 5.12) ----
var air_style: int = SimCombatConsts.AS_NONE  ## AS_*
var air_hover: int = 0  ## 1 = rotor craft (move class AIR_HOVER)
var takeoff_ticks: int = 20
var landing_ticks: int = 30
var fuel_max: int = 3600  ## airborne ticks of fuel
var fuel_reserve: int = 200
var rearm_ticks: int = 240  ## full rearm from empty at rate 10000
var retarget_r: int = 8192  ## next-target search radius after a kill
var patrol_r: int = 12288
var orbit_r: int = 4096
var hover_bp: int = 7000  ## hover distance = range * hover_bp
var egress: int = 8192  ## bomb / missile run egress length
var strafe_min_sep: int = 1024
var strafe_max: int = 60  ## ticks of one strafing pass
var am_mode: int = 0  ## 1 = fires while flying attack-move (aircraft)
var st_ver: int = -1  ## DefPlayerView.version the stat cache `st` was built for (-1 = stale)
var st: PackedInt32Array = PackedInt32Array()  ## per mount: damage, range, reload_mt, proj_speed (SimCombatSystem.slot_stat cache)
var slots: Array[DefWeaponSlot] = []  ## the roster clone's slots (read-only references)


## Index into the def's weapons[] of mount `m`.
func slot_of_mount(m: int) -> int:
	return mounts[m * MT + MT_SLOT]


## Column `col` (SimCombatDef.MT_*) of mount `m`.
func mount_val(m: int, col: int) -> int:
	return mounts[m * MT + col]


## Column `col` (SimWeaponProfile.PF_*) of mount `m`.
func pf(m: int, col: int) -> int:
	return prof[m * SimWeaponProfile.PN + col]
