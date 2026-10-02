class_name SimZoneConsts
extends RefCounted
## Constants of the zone / summon / power-glue half of the abilities domain (AB-07 / AB-08; abilities 4.6 to 4.8, 5.11,
## 5.12, 6.2). No logic. Zone kinds are DefEnums.ZoneKind (BUFF 0 ... REVEAL 9) plus the runtime-only WARNING kind.

# ---- zone table ----
const MAX_ZONES: int = 96
const MAX_MEMBERS: int = 64
const MAX_INTERCEPT: int = 8
const PERIOD_FAST: int = 4  ## membership pass of SMOKE / COVER / SHELTER / DEBRIS
const PERIOD_SLOW: int = 10  ## membership pass of REPAIR
const WARN_MARGIN_U: int = 3072  ## warning markers are visible to owners of entities within 3 cells of the shape
const WARN_PERIOD: int = 10
const ZK_WARNING: int = 20  ## runtime-only zone kind (spawn_warning)

# ---- zone state ----
const ZS_WARMUP: int = 0
const ZS_ACTIVE: int = 1

# ---- zone flags ----
const ZF_LATCHED_DONE: int = 1
const ZF_CANCELLED: int = 2
const ZF_BUILDER_ONLY: int = 4  ## cover: only the source entity may occupy it
const ZF_FOLLOW: int = 8  ## the zone moves with bind_eid
const ZF_ENDS_ON_MOVE: int = 16  ## repair: a unit that moves is excluded for the rest of the zone
const ZF_NO_BODY_HEAL: int = 32

# ---- zone end reasons (EV_ZONE_ENDED p2) ----
const ZE_EXPIRED: int = 0
const ZE_BODY: int = 1
const ZE_CANCELLED: int = 2
const ZE_BOUND: int = 3

# ---- warning kinds (spawn_warning) ----
const WK_CIRCLE: int = 0
const WK_LINE: int = 1

# ---- events (abilities 6.2; output only) ----
const EV_ZONE_SPAWNED: int = 246  ## p1 zone id, p2 zone kind, p3 owner pid, x, y
const EV_ZONE_ENDED: int = 247  ## p1 zone id, p2 reason ZE_*
const EV_SUMMONED: int = 248  ## p0 eid, p1 parent or -1, p2 SM_* flags
const EV_SUMMON_EXPIRED: int = 249  ## p0 eid
const EV_SWARM_LAUNCHED: int = 256  ## p1 target x, p2 target y, x, y hub
const EV_ENGINE_ASSEMBLED: int = 257  ## p0 engine eid, p1 capsule eid

# ---- power validation results (SimPowerFx.validate / apply) ----
const PW_OK: int = 0
const PW_ERR_UNKNOWN: int = 1  ## no such power
const PW_ERR_LIMIT: int = 2  ## the zone table (96) has no room
const PW_ERR_TARGET: int = 3  ## the chosen structure / entity is missing or of the wrong kind
const PW_ERR_NO_SUMMON: int = 4  ## the summon def of an action is not defined in the unit sheets
const PW_ERR_OWNER: int = 5  ## bad or eliminated owner

# ---- summon flags SM_* (SimCompSummon.flags; abilities 5.12) ----
const SM_TEMPORARY: int = 1
const SM_DECOY: int = 2
const SM_NO_SALVAGE: int = 4
const SM_NO_CAPTURE: int = 8
const SM_NO_REPAIR: int = 16
const SM_NO_HARVEST: int = 32
const SM_NO_CMD_FIELD: int = 64
const SM_NO_VISION_GRANT: int = 128
const SM_ENEMIES_ONLY: int = 256
const SM_NO_WRECK: int = 512
const SM_PACKET_WEAPONS: int = 1024
const SM_UNCONTROLLABLE: int = 2048
const SM_SHOOTABLE: int = 4096
const SM_BODY: int = 8192  ## the body of a zone (puck, station, pontoon)
const SM_DEFAULT_POWER: int = SM_TEMPORARY | SM_NO_SALVAGE | SM_NO_CAPTURE | SM_NO_REPAIR | SM_NO_HARVEST

# ---- summon drivers SD_* ----
const SD_NONE: int = 0
const SD_STATIC: int = 1  ## decoys, pucks, pontoons
const SD_ORBITER: int = 2  ## UAV, patrol aircraft, balloon, delivery aircraft: circle a centre (scripted motion)
const SD_SWARM: int = 3  ## Tempest drone
const SD_CAPSULE: int = 4  ## Dragonfall capsule: assembles, then becomes the engine
const SD_ENGINE: int = 5  ## Dragonfall engine
const SD_ATTACHED: int = 6  ## Lagos repair drone: orbits the parent

# ---- driver states (SimCompSummon.state) ----
const SS_APPROACH: int = 0
const SS_ATTACK: int = 1
const SS_ORBIT: int = 2
const SS_ASSEMBLING: int = 3
const SS_ADVANCE: int = 4

# ---- driver numbers ----
const DRIVER_PERIOD: int = 10
const SWARM_ATTACK_TICKS: int = 400
const SWARM_HARD_CAP_TICKS: int = 1200
const SWARM_MARGIN_U: int = 2048
const ENGINE_LIFE_TICKS: int = 1200
const ENGINE_NEAR_STRUCT_U: int = 20480
const ORBIT_ATTACHED_U: int = 1536  ## the Lagos drone orbits its parent at 1.5 cells
const ANGLE_PER_UNIT_Q: int = 652  ## 4096 / (2 pi), for the angular speed of an orbiting body

# ---- spawn-ability slot states (SimCompAbility slot SL_STATE of smoke_launcher / portable_cover / sensor_puck /
# decoy_spawn / summon_orbit) ----
const SA_READY: int = 0
const SA_BUILDING: int = 1
const SA_ACTIVE: int = 2
const SA_PACKING: int = 3
const SA_COOLDOWN: int = 4
const SA_RESPAWNING: int = 5
const SA_LAUNCH_RANGE_U: int = 12288  ## a launcher / puck / decoy is placed within 12 cells of its unit

# ---- src_key of zones / summons created by a unit ability: FXK(SRC_ABILITY, slot-of-entity) is not used; zones use
# FXK(SRC_ZONE, zone_idx) as documented in 5.11.2 ----
