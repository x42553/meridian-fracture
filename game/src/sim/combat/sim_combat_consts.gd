class_name SimCombatConsts
extends RefCounted
## Combat constants (combat 4.1). Numbers of the kernel/data vocabularies mirror SimEntity / DefEnums (their numbers
## win). Damage types follow the FROZEN data vocabulary: bullet 0, ap 1, he 2, thermal 3, rail 4, kinetic 5, emp 6.

# ---- layers / kinds / relations (mirrors) ----
const LAYER_GROUND: int = 0
const LAYER_AIR: int = 1
const LAYER_SURFACE: int = 2
const LAYER_UNDERWATER: int = 3
const KIND_UNIT: int = 0
const KIND_STRUCTURE: int = 1
const KIND_WRECK: int = 2
const REL_SELF: int = 0
const REL_ALLY: int = 1
const REL_ENEMY: int = 2
const REL_NEUTRAL: int = 3

# ---- target filter bits (weapon target mask) ----
const TF_GROUND: int = 1
const TF_AIR: int = 2
const TF_SURFACE: int = 4
const TF_UNDERWATER: int = 8
const TF_STRUCTURE: int = 16
const TF_WRECK: int = 32

# ---- damage types (DefEnums.DamageType) ----
const DT_BULLET: int = 0
const DT_AP: int = 1
const DT_HE: int = 2
const DT_THERMAL: int = 3
const DT_RAIL: int = 4
const DT_KINETIC: int = 5
const DT_EMP: int = 6
const DT_COUNT: int = 7
const DT_MASK_ALL_WEAPON: int = 0x7FBF  ## every type bit (0..14) except DT_EMP (bit 6)

# ---- delivery and damage-class bits ----
const DELIV_DIRECT: int = 0
const DELIV_INDIRECT: int = 1
const DELIV_STRATEGIC: int = 2
const DC_DIRECT: int = 1
const DC_INDIRECT: int = 2
const DC_SPLASH: int = 4
const DC_STRATEGIC: int = 8

# ---- resistance / lease filter packing: types | req << 15 | forbid << 19 ----
const FILTER_ALL_WEAPON: int = DT_MASK_ALL_WEAPON
const FILTER_DIRECT_ONLY: int = DT_MASK_ALL_WEAPON | (DC_DIRECT << 15) | ((DC_SPLASH | DC_INDIRECT | DC_STRATEGIC) << 19)
const COND_ON_WATER: int = 1

# ---- projectile kinds / flags ----
const PK_HITSCAN: int = 0
const PK_BULLET: int = 1
const PK_MISSILE: int = 2
const PK_ARC: int = 3
const PK_BOMB: int = 4
const PK_STRIKE: int = 5
const PK_SWEEP: int = 6
const PK_BEAM: int = 7
const PF_GUIDED: int = 1
const PF_APS_INTERCEPTABLE: int = 2
const PF_ZONE_INTERCEPTABLE: int = 4
const PF_BLOCKED_BY_HOSTILES: int = 8
const PF_AIRBURST_ON_EXPIRE: int = 16
const PF_STRATEGIC: int = 32
const PI_PACKET: int = 1
const PI_FORCED: int = 2
const PI_SUPPRESSIVE: int = 4
const PI_CHAIN: int = 8
const PI_REMOTE: int = 16
const PI_ENEMY_ONLY: int = 32

# ---- mounts, stances, target sources ----
const MK_TURRET: int = 0
const MK_FIXED: int = 1
const MK_HULL: int = 2
const WC_ANTI_AIR: int = 1
const WC_ANTI_SUB: int = 2
const WC_ANTI_ARMOR: int = 4
const WC_ANTI_INF: int = 8
const WC_ARTILLERY: int = 16
const WC_ANTI_STRUCT: int = 32
const AM_MOVE: int = 0
const AM_ENGAGE: int = 1
const ST_AGGRESSIVE: int = 0
const ST_DEFENSIVE: int = 1
const ST_HOLD_FIRE: int = 2
const ST_GUARD: int = 3
const TS_NONE: int = 0
const TS_AUTO: int = 1
const TS_ORDER: int = 2
const TS_FORCE: int = 3
const TS_RETAL: int = 4
const TS_GUARD: int = 5

# ---- SimCompCombat.cflags ----
const CF_DEAD: int = 1
const CF_DYING: int = 2
const CF_UNTARGETABLE: int = 4
const CF_SUMMONED: int = 8
const CF_DECOY: int = 16
const CF_INVULNERABLE: int = 32
const CF_NO_WRECK: int = 64
const CF_SCUTTLED: int = 128
const CF_HAS_AA: int = 256
const CF_HAS_ASW: int = 512
const CF_SUPPRESSIBLE: int = 1024
const CF_ENEMY_ONLY: int = 2048

# ---- lease stats (SimCombatMods) ----
const STAT_DMG_OUT: int = 0
const STAT_RELOAD: int = 1
const STAT_RANGE: int = 2
const STAT_TAKEN: int = 3
const STAT_MARK: int = 4
const STAT_EMP_RECOVER: int = 5
const STAT_SUP_RECOVER: int = 6
const STAT_REARM_RATE: int = 7
const STAT_FLAG_EMP_IMMUNE: int = 8
const STAT_FLAG_SUP_IMMUNE: int = 9
const STAT_NONE: int = -1  ## empty lease slot
const MARK_GROUND_ONLY: int = 256  ## STAT_MARK filter bit: only ground weapons benefit

# ---- damage instance flags ----
const DF_NONLETHAL: int = 1
const DF_FORCED: int = 2
const DF_SUPPRESSIVE: int = 4
const DF_PACKET: int = 8
const DF_CHAIN: int = 16
const DF_CRASH: int = 32

# ---- death ----
const DK_NONE: int = 0
const DK_VEHICLE: int = 1
const DK_INFANTRY: int = 2
const DK_CRASH: int = 3
const DK_AIR_EXPLODE: int = 4
const DK_SINK: int = 5
const DK_STRUCTURE: int = 6
const DK_DRONE: int = 7
const DK_SILENT: int = 8
const CAUSE_DAMAGE: int = 0
const CAUSE_SCUTTLE: int = 1
const CAUSE_EXPIRE: int = 2
const CAUSE_ORPHAN: int = 3
const CAUSE_CARGO: int = 4
const CAUSE_RESIGN: int = 5
const CARGO_DIE: int = 0
const CARGO_EJECT_HURT: int = 1
const CARGO_EJECT: int = 2
const EC_INFANTRY: int = 1
const EC_VEHICLE: int = 2
const EC_AIRCRAFT: int = 4
const EC_SHIP: int = 8
const EC_STRUCTURE: int = 16
const WF_SALVAGEABLE: int = 1
const WF_CONSUMED: int = 2

# ---- air ----
const AIR_PARKED: int = 0
const AIR_TAKEOFF: int = 1
const AIR_TRANSIT: int = 2
const AIR_ATTACK: int = 3
const AIR_PATROL: int = 4
const AIR_RETURN: int = 5
const AIR_LANDING: int = 6
const AIR_REARM: int = 7
const AIR_NO_BASE: int = 8
const AIR_DOCKED: int = 9
const AP_APPROACH: int = 0
const AP_RUN: int = 1
const AP_RELEASE: int = 2
const AP_EGRESS: int = 3
const AP_HOVER: int = 4
const AP_PURSUE: int = 5
const AS_HOVER: int = 0
const AS_MISSILE_RUN: int = 1
const AS_BOMB_RUN: int = 2
const AS_STRAFE: int = 3
const AS_DOGFIGHT: int = 4
const AS_NONE: int = 5
const MI_NONE: int = 0
const MI_ATTACK: int = 1
const MI_ATTACK_MOVE: int = 2
const MI_PATROL: int = 3
const MI_MOVE: int = 4
const MI_RETURN: int = 5
const MI_ESCORT: int = 6
const HOME_AIRFIELD: int = 0
const HOME_CARRIER: int = 1
const BAY_EMPTY: int = 0
const BAY_DOCKED: int = 1
const BAY_AWAY: int = 2
const BAY_REARM: int = 3

# ---- orders / commands (kernel numbering) ----
const ORD_ATTACK: int = 40
const ORD_ATTACK_MOVE: int = 41
const ORD_GUARD: int = 42
const ORD_HOLD: int = 43
const ORD_FORCE_FIRE: int = 44
const CMD_ATTACK: int = 40
const CMD_ATTACK_MOVE: int = 41
const CMD_GUARD: int = 42
const CMD_HOLD: int = 43
const CMD_FORCE_FIRE: int = 44
const CMD_SET_STANCE: int = 45
const CMD_SCUTTLE: int = 46
const CMD_RETURN_TO_BASE: int = 47

# ---- mount state layout inside SimCompCombat.mnt (stride MS) ----
const MS: int = 10
const M_CD: int = 0
const M_BURST: int = 1
const M_NEXT: int = 2
const M_AMMO: int = 3
const M_ANGLE: int = 4
const M_TARGET: int = 5
const M_AIM_SINCE: int = 6
const M_BEAM: int = 7
const M_SHOTS: int = 8
const M_DOT: int = 9
const MAX_MOUNTS: int = 4
const MAX_MODS: int = 10
const MODS_STRIDE: int = 5
const MOD_KEY: int = 0
const MOD_STAT: int = 1
const MOD_BP: int = 2
const MOD_EXPIRE: int = 3
const MOD_FILTER: int = 4

# ---- events 200..220 (combat 6.2) ----
const EV_FIRE: int = 200
const EV_PROJ_SPAWN: int = 201
const EV_PROJ_END: int = 202
const EV_IMPACT: int = 203
const EV_HIT: int = 204
const EV_BEAM_START: int = 205
const EV_BEAM_END: int = 206
const EV_SWEEP: int = 207
const EV_DEATH: int = 208
const EV_WRECK_ADD: int = 209
const EV_WRECK_REMOVE: int = 210
const EV_INTERCEPT: int = 211
const EV_SUPPRESS: int = 212
const EV_EMP: int = 213
const EV_ATTACK_ALERT: int = 214
const EV_AIR_STATE: int = 215
const EV_REARM: int = 216
const EV_DRONE: int = 217
const EV_EJECT: int = 218
const EV_CRASH: int = 219
const EV_WEAPON_LOCK: int = 220
## EV_HIT.d flag bits (dtype | dc << 8 | flags << 16).
const HITF_KILLED: int = 1
const HITF_SUPPRESSION: int = 2
const HITF_CAP: int = 4
const HITF_DIRECTIONAL: int = 8
const HITF_PACKET: int = 16
const HITF_EMP: int = 32

# ---- tuning constants (combat 4.1 defaults) ----
const SCAN_INTERVAL_UNIT: int = 6
const SCAN_INTERVAL_STRUCT: int = 8
const SCAN_INTERVAL_AIR: int = 4
const RESCORE_INTERVAL: int = 20
const SCAN_BUDGET_BASE: int = 24
const SCAN_CAND_CAP: int = 48
const ACQ_MARGIN: int = 1024
const PRIO_TIER: int = 4096
const STICK_BONUS: int = 2048
const FOCUS_BONUS: int = 1024
const FOCUS_TTL: int = 20
const THREAT_BONUS: int = 2048
const WOUNDED_MAX: int = 1024
const RETAL_MARGIN: int = 1024
const OVERKILL_PENALTY: int = 4096
const HIDE_GIVEUP_AUTO: int = 20
const HIDE_GIVEUP_ORDER: int = 200
const ASSIST_RADIUS: int = 8192
const ASSIST_COOLDOWN: int = 20
const LEASH_AGGRESSIVE: int = 8192
const LEASH_DEFENSIVE: int = 3072
const LEASH_GUARD: int = 6144
const GUARD_RADIUS: int = 10240
const RETURN_SLACK: int = 2048
const APPROACH_BP: int = 9000
const SUP_HITS: int = 3
const SUP_WINDOW: int = 40
const SUP_TAIL: int = 60
const SUP_SPEED_BP: int = 7500
const TAKEN_MIN_BP: int = 5000
const TAKEN_MAX_BP: int = 20000
const CHIP_FLOOR_BP: int = 500
const WRECK_TICKS: int = 1200
const WRECK_HP_MIN: int = 150
const PROJ_POOL: int = 4096
const PROJ_STRATEGIC_RESERVE: int = 256
const PROJ_SOFT_CAP: int = 3072
const CHAIN_CAP: int = 64
const ALERT_COOLDOWN: int = 200
const ALERT_DIST: int = 15360
const AIM_TOL_DEFAULT: int = 24
const TURRET_IDLE_RETURN: int = 60
const ACC_MIN_BP: int = 1000
const ACC_V_REF: int = 48
const NEVER: int = -100000  ## "long ago" timestamp
## EMP defaults when a weapon carries an EMP damage type but no duration data (Aurora seed).
const EMP_UNIT_TICKS_DEFAULT: int = 160
const EMP_STRUCT_TICKS_DEFAULT: int = 360
const EMP_RECOVER_MAX_BP: int = 5000
## Splash victims are found within splash_r + this margin (victim radius allowance).
const SPLASH_QUERY_MARGIN: int = 2560


## FILTER(types, req, forbid).
static func make_filter(types: int, req: int = 0, forbid: int = 0) -> int:
	return types | (req << 15) | (forbid << 19)


## match(filter, dtype, dc) of combat 4.1.
static func filter_match(filter: int, dtype: int, dc: int) -> bool:
	if (filter & (1 << dtype)) == 0:
		return false
	var req: int = (filter >> 15) & 15
	var forbid: int = (filter >> 19) & 15
	return (dc & req) == req and (dc & forbid) == 0


## Signed angle in [-2048, 2047] of any bat value (combat wrap_signed).
static func wrap_signed(a: int) -> int:
	return ((a + Fp.ANGLE_HALF) & Fp.ANGLE_MASK) - Fp.ANGLE_HALF
