class_name SimAbilityConsts
extends RefCounted
## Enums and constants of the abilities domain (abilities 4.1). No logic. Codes owned by other domains are mirrored
## here for readability; their numbers win (DefEnums for data ids, SimCombatConsts for lease stats).

# ---- sizing ----
const MAX_SLOTS: int = 6
const SLOT_STRIDE: int = 8
const MAX_FX: int = 10
const FX_STRIDE: int = 4
const MAX_GROUPS: int = 8
const MAX_TEMP_SRC: int = 64
const MAX_ZONES: int = 96
const ZONE_MEMBERS: int = 64
const WHEEL_SIZE: int = 1024
const MAX_SIGHT_CELLS: int = 32
const LEASE_HOLD: int = 1000000
const HEAL_PERIOD: int = 10
const MAX_COND_FX: int = 24

# ---- slot layout: base = s * SLOT_STRIDE ----
const SL_KIND: int = 0
const SL_AB_IDX: int = 1
const SL_STATE: int = 2
const SL_T_END: int = 3
const SL_N: int = 4
const SL_AUX0: int = 5
const SL_AUX1: int = 6
const SL_FLAGS: int = 7
const SF_AUTOCAST: int = 1
const SF_GRANTED: int = 2
const SF_SUSPENDED: int = 4
const SF_ENABLED: int = 8

# ---- timed-effect entry layout: base = i * FX_STRIDE ----
const FX_IDX: int = 0
const FX_SRC: int = 1
const FX_EXPIRE: int = 2
const FX_AUX: int = 3  ## tick at which the effect was applied (end_on FIRE baseline)

# ---- slot states of the kinds this task drives ----
const DET_OFF: int = 0
const DET_ON: int = 1
const CAM_ARMING: int = 0
const CAM_CLOAKED: int = 1
const SUB_SUBMERGED: int = 0
const SUB_SURFACING: int = 1
const SUB_SURFACED: int = 2
const SUB_DIVING: int = 3

# ---- lease keys FXK(src_kind, id) = (src_kind << 24) | id ----
const SRC_RESEARCH: int = 1
const SRC_POWER: int = 2
const SRC_GROUP: int = 3
const SRC_TRAIT: int = 4
const SRC_ZONE: int = 5
const SRC_ABILITY: int = 6
const SRC_DISEMBARK: int = 7
const SRC_COND: int = 8
const SRC_SUPERWEAPON: int = 9

# ---- derived flags (SimCompStats.flags) ----
const DF_IMMOBILE: int = 1
const DF_TURN_LOCKED: int = 2
const DF_EXPOSED: int = 4  ## camouflage locked (deployed sensor mast)
const DF_CAMO_GRANTED: int = 8
const DF_UNLOAD_MOVING: int = 16
const DF_NO_CMD_FIELD: int = 32
const DF_UNCONTROLLABLE: int = 64
const DF_IN_GARRISON: int = 128
const DF_BUSY: int = 256

# ---- watch flags (SimCompAbility.watch) ----
const WF_STILL: int = 1
const WF_COMBAT: int = 2
const WF_MOVE_EVENT: int = 4
const WF_CELL: int = 8
const WF_CLOAK: int = 16
const WF_TARGET: int = 32
const WF_END_ON: int = 64  ## pending end_on effects (every-tick pass)
const WF_NEAR: int = 128  ## near-friendly-unit / structure conditions (every 10 ticks)

# ---- end_on events ----
const RE_MOVE: int = 1
const RE_FIRE: int = 2
const RE_DETECT: int = 4
const RE_LOAD: int = 8
const RE_OWNER: int = 16

# ---- removal reasons ----
const RR_EXPIRED: int = 0
const RR_EVENT: int = 1
const RR_EVICTED: int = 2
const RR_OWNER: int = 3
const RR_DEATH: int = 4
const RR_CLEARED: int = 5

# ---- local stat cache indices (SimCompStats.vals / extra / dirty bits) ----
const K_SPEED: int = 0
const K_SIGHT: int = 1
const K_HEALTH: int = 2
const K_COUNT: int = 3
const K_ALL: int = 7

# ---- stealth kinds ----
const SK_CAMOUFLAGE: int = 1
const SK_SUBMARINE: int = 2
const SK_DECOY: int = 4

# ---- vision ----
const SHAPE_DISC: int = 0
const SHAPE_CAPSULE: int = 1
const VF_STATIC: int = 1  ## structure, stamped once
const VF_INACTIVE: int = 2  ## in cargo, dead, being removed
const VF_UNDER_CONSTRUCTION: int = 4  ## stamped with the reduced radius
const CONSTRUCTION_SIGHT_CELLS: int = 3
const DEFAULT_DETECT_U: int = 5120

# ---- timer kinds ----
const TK_FX: int = 1
const TK_COOLDOWN: int = 2
const TK_CLOAK: int = 3
const TK_MODE: int = 4
const TK_BUILD: int = 5
const TK_DISEMBARK: int = 6
const TK_GRACE: int = 7
const TK_RESPAWN: int = 8
const TK_SUMMON: int = 9
const TK_WINDOW: int = 10

# ---- events (abilities 6.2; output only) ----
const EV_CLOAK_CHANGED: int = 230  ## p0 eid, p1 1 concealed / 0 revealed, p2 reason CR_*
const EV_VIS_CHANGED: int = 231  ## p0 eid, p1 group, p2 seen
const EV_GHOST_ADDED: int = 232  ## p0 eid, p1 group, p2 def idx
const EV_GHOST_REMOVED: int = 233  ## p0 eid, p1 group
const EV_FX_APPLIED: int = 238  ## p0 eid, p1 fx idx, p2 expire tick
const EV_FX_REMOVED: int = 239  ## p0 eid, p1 fx idx, p2 reason RR_*
const EV_MODE_STARTED: int = 234  ## p0 eid, p1 slot, p2 target mode
const EV_MODE_CHANGED: int = 235  ## p0 eid, p1 slot, p2 new mode
const EV_ABILITY_USED: int = 236  ## p0 eid, p1 kind, p2 slot
const EV_ABILITY_READY: int = 237  ## p0 eid, p1 slot
const EV_LOADED: int = 240  ## p0 passenger, p1 carrier
const EV_UNLOADED: int = 241  ## p0 passenger, p1 carrier
const EV_UNLOAD_BLOCKED: int = 242  ## p0 carrier, p1 reason
const EV_GARRISON_CHANGED: int = 243  ## p0 building, p1 occupants, p2 claim team
const EV_EJECTED: int = 244  ## p0 passenger, p1 cause (0 container died, 1 building destroyed), p2 hp lost
const EV_DROWNED: int = 245  ## p0 passenger
const EV_SCAN_WARNING: int = 250  ## p1 power idx, p2 radius cells, p3 owner pid (AB-07 / AB-08)
const EV_SALVAGE_DONE: int = 251  ## p0 salvager, p1 wreck, p2 credits
const EV_CAPTURE_DONE: int = 252  ## p0 capturer, p1 structure, p2 previous owner
const EV_REPAIR_PULSE: int = 254  ## p0 target, p1 healer or -1, p2 hp gained
const EV_DECOY_IDENTIFIED: int = 255  ## p0 eid, p1 group
const EV_MARKED: int = 258  ## p0 eid, p1 1 / 0
const EV_BUFF_APPLIED: int = 259  ## p1 power idx, p2 entity count, p3 owner pid (AB-08)
const CR_FIRE: int = 1
const CR_DAMAGE: int = 2
const CR_MOVE: int = 3
const CR_WORK: int = 4
const CR_ARMED: int = 5
const CR_DETECT: int = 6
const CR_GRANT: int = 7

# ---- data-side ability kinds executed here (DefEnums.AbilityKind ids) ----
const AK_DETECTOR: int = 1
const AK_CAMOUFLAGE: int = 2
const AK_DEPLOY: int = 3
const AK_MODE_SWITCH: int = 4
const AK_TRANSPORT: int = 5
const AK_HEAL: int = 6
const AK_REPAIR: int = 7
const AK_COMMAND_FIELD: int = 8
const AK_SUPPRESSION_SUPPORT: int = 10
const AK_DECOY_SPAWN: int = 11
const AK_SENSOR_PUCK: int = 12
const AK_SMOKE_LAUNCHER: int = 13
const AK_EW_JAMMER: int = 14
const AK_DISEMBARK_BUFF: int = 15
const AK_PORTABLE_COVER: int = 16
const AK_SALVAGE: int = 17
const AK_SENSOR_MAST: int = 20
const AK_DEPLOY_STRUCTURE: int = 23  ## economy's (MCV)
const AK_DEFENSE_POWER_RESERVE: int = 33  ## power's (SAP trait); no slot here
const AK_CAPTURE: int = 21
const AK_SUBMERGE: int = 24
const AK_SPOTTER: int = 26
const AK_REGEN: int = 27
const AK_RELAY_FIELD: int = 29
const AK_AURA_REGEN: int = 32
const AK_SUMMON_ORBIT: int = 34
## Bit i set = kind i gets a slot in SimCompAbility (the kinds executed by this domain).
const EXECUTED_MASK: int = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) \
	| (1 << 10) | (1 << 11) | (1 << 12) | (1 << 13) | (1 << 14) | (1 << 15) | (1 << 16) | (1 << 17) | (1 << 20) \
	| (1 << 21) | (1 << 24) | (1 << 26) | (1 << 27) | (1 << 29) | (1 << 32) | (1 << 34)


## Lease key (src_kind << 24) | id.
static func fxk(src_kind: int, id: int) -> int:
	return (src_kind << 24) | (id & 0xFFFFFF)
