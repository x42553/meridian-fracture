class_name SimMoveConfig
extends RefCounted
## Movement enums, result codes and tuning constants (terrain_movement 4.3; integer values are binding).
## Everything here is a count or a fixed-point constant (DR-1/DR-11): budgets are units of work, never time.

# ---- movement state (SimCompMove.state) ----
const MS_IDLE: int = 0
const MS_WAIT_PATH: int = 1
const MS_MOVING: int = 2
const MS_BLOCKED: int = 3
const MS_NO_PATH: int = 4
const MS_ARRIVED: int = 5
const MS_PAUSED: int = 6
const MS_GLIDE: int = 7
const MS_FACING: int = 8
const MS_SIDESTEP: int = 9
const MS_EVICT: int = 10
# ---- flags (SimCompMove.flags bit set; the entity-level mirrors are SimFlags F_MOVING/F_AIRBORNE/F_BLOCKED/F_ON_WATER) ----
const MF_ON_WATER: int = 1
const MF_REVERSING: int = 2
const MF_PATH_PARTIAL: int = 4
const MF_PRECISE: int = 8
const MF_SPEED_MATCH: int = 16
const MF_ATTACK_MOVE: int = 32
# ---- goal kinds ----
const GK_NONE: int = 0
const GK_POINT: int = 1
const GK_NEAR: int = 2
const GK_FOLLOW: int = 3
const GK_APPROACH: int = 4
const GK_FACE: int = 5
const GK_SIDESTEP: int = 6
const GK_GLIDE: int = 7
const GK_EVICT: int = 8
# ---- result codes (SimCompMove.result) ----
const RS_NONE: int = 0
const RS_OK: int = 1
const RS_PARTIAL: int = 2
const RS_NO_PATH: int = 3
const RS_CANCELLED: int = 4
const RS_STUCK: int = 5
const RS_IMMOBILE: int = 6
const RS_BAD_TARGET: int = 7
const RS_NO_MOVE: int = 8
# ---- opts bits for SimMovement.go_* ----
const OPT_SPEED_MATCH: int = 2
const OPT_REVERSE_OK: int = 4
const OPT_PRECISE: int = 8
const OPT_NO_SLOT: int = 16
const OPT_ATTACK_MOVE: int = 32
const OPT_PRIO_ECON: int = 64
# ---- turn modes ----
const TM_INSTANT: int = 0
const TM_PIVOT: int = 1
const TM_ARC: int = 2
const TM_BANK: int = 3
# ---- separation hash layers ----
const HL_GROUND: int = 0
const HL_WATER: int = 1
const HL_SUB: int = 2
const HL_AIR_LOW: int = 3
const HL_AIR_HIGH: int = 4
const HL_COUNT: int = 5
# ---- air modes (SimCompMove.air_mode) ----
const AM_PARKED: int = 0
const AM_TAKEOFF: int = 1
const AM_CRUISE: int = 2
const AM_ORBIT: int = 3
const AM_HOVER: int = 4
const AM_APPROACH: int = 5
const AM_LANDING: int = 6
# ---- speed / geometry constants ----
const CELL: int = 1024
const SPEED_Q: int = 16  ## Q4: stored speeds are units/tick * 16
const SEP_BUCKET_SHIFT: int = 11  ## separation bucket = 2 cells
const SEP_MAX_NEIGHBOURS: int = 16  ## spec 12; 16 keeps a 30-unit pile from freezing pairs on top of each other
const SEP_OVERLAP_NUM: int = 7  ## min distance = (ri + rj) * 7 / 8
const IDLE_SEP_STRIDE: int = 3
const WP_REACH_MIN: int = 384  ## units
const ARRIVE_EPS: int = 256  ## units (exact goals); MF_PRECISE uses ARRIVE_EPS_PRECISE
const ARRIVE_EPS_PRECISE: int = 48
const STUCK_STRIDE: int = 10
const STUCK_MIN_PCT: int = 20
const STUCK_REPATH_TICKS: int = 40  ## = global.json movement_defaults.stuck_repath_ticks (first repath after 4 stuck strides)
const PATH_WAIT_MAX: int = 60  ## ticks in MS_WAIT_PATH before RS_NO_PATH (3 s)
const REPATH_MIN_INTERVAL: int = 20
const VALIDITY_STRIDE: int = 8
const FOLLOW_STRIDE: int = 5
const PACK_RETRY_TICKS: int = 20  ## abilities.request_pack is asked at most once per this many ticks
const SIDESTEP_MIN_INTERVAL: int = 20
# ---- movement_defaults of global.json that the data domain does not expose (values equal the file) ----
const DECEL_PCT_OF_ACCEL: int = 70
const REVERSE_SPEED_PCT: int = 50
const WATER_HYSTERESIS: int = 6  ## ticks between accepted F_ON_WATER flips
# ---- path service budgets (per tick, all counts; 5.3.5) ----
const PATH_BASE: int = 1600
const PATH_PER_PENDING: int = 200
const PATH_PENDING_CAP: int = 8
const PATH_MAX_DELIVERIES: int = 16
const PATH_DIRTY_WAIT: int = 4  ## ticks an abstract-phase request waits for a dirty graph
const CACHE_CAP: int = 64
const CACHE_TTL: int = 100
const NAV_DIRTY_BUDGET: int = 12
const SIDESTEP_PER_TICK: int = 8
const ALT_GOAL_RINGS: int = 24
# ---- movement events (block 100-129, sim_core 6.2; payload a.b.c.d.e.f, x/y in the header) ----
const EV_MOVE_FAILED: int = 100  ## unit id . RS_* . order type (0 = not from an order)
const EV_MEDIUM_CHANGED: int = 101  ## unit id . 1 entered / 0 left water
const EV_STUCK: int = 108  ## unit id . stuck count
const EV_LAYER_CHANGED: int = 109  ## unit id . new layer (SimEntity.Layer): submarine surfaced (2) / submerged (3)

## entity flag bits movement writes (16-19).
const F_MIRROR_MASK: int = SimFlags.F_MOVING | SimFlags.F_AIRBORNE | SimFlags.F_BLOCKED | SimFlags.F_ON_WATER
