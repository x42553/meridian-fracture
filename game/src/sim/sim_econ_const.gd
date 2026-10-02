class_name SimEconConst
extends RefCounted
## Constants of the economy domain (economy 4.1 / 6): validation reasons, structure states, power classes, queue
## states, ledger reasons, knob ids, event codes and the tuning numbers of placement / lifecycle / power. Constants
## only, no logic. The integer values are normative (they reach the checksum and the event stream).

# ---- RSN_*: validation reasons (0 = OK) ----
const RSN_OK: int = 0
const RSN_NOT_OWNER: int = 1
const RSN_NOT_AVAILABLE: int = 2
const RSN_PREREQ: int = 3
const RSN_QUEUE_FULL: int = 4
const RSN_NO_CREDITS: int = 5
const RSN_UNIT_CAP: int = 6
const RSN_STRATEGIC_LIMIT: int = 7
const RSN_NOT_READY: int = 8
const RSN_BAD_TARGET: int = 9
const RSN_OUT_OF_RADIUS: int = 10
const RSN_TERRAIN: int = 11
const RSN_STRUCTURE_BLOCK: int = 12
const RSN_UNIT_BLOCK: int = 13
const RSN_NEEDS_SHORE: int = 14
const RSN_DEPOSIT: int = 15
const RSN_DEBRIS: int = 16
const RSN_APRON: int = 17
const RSN_NO_POWER: int = 18
const RSN_COOLDOWN: int = 19
const RSN_NO_VISION: int = 20
const RSN_NOT_EXPLORED: int = 21
const RSN_WRONG_KIND: int = 22
const RSN_BUSY: int = 23
const RSN_NO_HQ: int = 24
const RSN_GARRISONED: int = 25
const RSN_FRIENDLY: int = 26
const RSN_LOCKED: int = 27
const RSN_FEATURE_OFF: int = 28
const RSN_NO_LAUNCHER: int = 29
const RSN_NOT_CHARGED: int = 30
const RSN_EXPIRING: int = 31
const RSN_DECOY: int = 32
const RSN_INVALID_INDEX: int = 33
const RSN_HOLD: int = 34

# ---- ST_*: structure state (SimCompEcon.st) ----
const ST_BUILDUP: int = 0
const ST_ACTIVE: int = 1
const ST_SELLING: int = 2
const ST_UNDEPLOYING: int = 3

# ---- PC_*: power class ----
const PC_NONE: int = 0
const PC_ECON: int = 1
const PC_PRODUCER: int = 2
const PC_SENSOR: int = 3
const PC_DEFENSE: int = 4
const PC_RELAY: int = 5
const PC_STRATEGIC: int = 6

# ---- PROD_*: producer / rate index ----
const PROD_NONE: int = 0
const PROD_BARRACKS: int = 1
const PROD_FACTORY: int = 2
const PROD_AIRFIELD: int = 3
const PROD_DOCK: int = 4
const PROD_REFINERY: int = 5
const PROD_CONSTRUCTION: int = 6
const PROD_RESEARCH: int = 7
const PROD_COUNT: int = 8

# ---- QS_*: head-of-queue state ----
const QS_EMPTY: int = 0
const QS_ACTIVE: int = 1
const QS_HOLD: int = 2
const QS_PAUSED_PREREQ: int = 3
const QS_PAUSED_FUNDS: int = 4
const QS_PAUSED_CAP: int = 5
const QS_PAUSED_EXIT: int = 6
const QS_PAUSED_SHUTDOWN: int = 7
const QS_READY: int = 8

# ---- CR_*: ledger reasons ----
const CR_START: int = 0
const CR_CONSTRUCTION: int = 1
const CR_PRODUCTION: int = 2
const CR_RESEARCH: int = 3
const CR_POWER_USE: int = 4
const CR_REPAIR: int = 5
const CR_HARVEST: int = 6
const CR_SALVAGE: int = 7
const CR_SELL: int = 8
const CR_REFUND: int = 9
const CR_DEPOT: int = 10
const CR_OTHER: int = 11

# ---- DOCK_* / SALV_* / H_* / W_* ----
const DOCK_DENIED: int = 0
const DOCK_WAIT: int = 1
const DOCK_GRANTED: int = 2
const SALV_FAILED: int = 0
const SALV_RUNNING: int = 1
const SALV_DONE: int = 2
const H_IDLE: int = 0
const H_SEEK: int = 1
const H_TO_FIELD: int = 2
const H_HARVEST: int = 3
const H_TO_REFINERY: int = 4
const H_WAIT_DOCK: int = 5
const H_DOCK_IN: int = 6
const H_UNLOAD: int = 7
const H_DOCK_OUT: int = 8
const H_FLEE: int = 9
const H_BLOCKED: int = 10
const W_NONE: int = 0
const W_CAPTURE: int = 1
const W_REPAIR: int = 2
const W_SALVAGE: int = 3

# ---- RC_* repairer category, RS_* repair source bits ----
const RC_ENGINEER: int = 0
const RC_TECHNICIAN: int = 1
const RC_TENDER: int = 2
const RC_PIONEER: int = 3
const RC_FIELD_ENGINEER: int = 4
const RC_WRENCH: int = 5
const RC_PAD: int = 6
const RS_UNIT: int = 1
const RS_WRENCH: int = 2
const RS_PAD: int = 4

# ---- EF_*: entity econ flags (SimCompEcon.flags) ----
const EF_TEMPORARY: int = 1
const EF_DECOY: int = 2
const EF_NO_REPAIR: int = 4
const EF_NO_CAPTURE: int = 8
const EF_NO_SALVAGE: int = 16
const EF_FREE: int = 32
const EF_CAPPED: int = 64
const EF_SUMMON: int = 128
const EF_NO_VISION_GRANT: int = 256
const EF_SELL_LOCKED: int = 512

# ---- PF_*: player flags ----
const PF_CAN_SALVAGE: int = 1
const PF_SAP_RESERVE: int = 2
const PF_AMPHIBIOUS_COLLECTORS: int = 4
const PF_ELIMINATED: int = 8
const PF_SUPERWEAPONS_OFF: int = 16

# ---- PW_*: power state ----
const PW_NORMAL: int = 0
const PW_SHORTAGE: int = 1

# ---- SLOT_*, SW_*, AT_*, WK_*, TK_*, VR_*, EK_*, SK_*, PKT_*, TS_*, BR_*, WF_* ----
const SLOT_P0: int = 0
const SLOT_P1: int = 1
const SLOT_P2: int = 2
const SLOT_SW: int = 3
const SLOT_COUNT: int = 4
const SW_NONE: int = 0
const SW_CHARGING: int = 1
const SW_READY: int = 2
const AT_WARNING: int = 0
const AT_EXEC: int = 1
const AT_DONE: int = 2
const AT_CANCELLED: int = 3
const WK_SUPER: int = 0
const WK_POWER: int = 1
const WK_SCAN: int = 2
const TK_NONE: int = 0
const TK_POINT: int = 1
const TK_AREA: int = 2
const TK_LINE: int = 3
const TK_OWN_STRUCTURE: int = 4
const TK_OWN_UNIT: int = 5
const VR_NONE: int = 0
const VR_EXPLORED: int = 1
const VR_CURRENT: int = 2
const EK_REVEAL_ZONE: int = 1
const EK_RECON_SUMMON: int = 2
const EK_BUFF: int = 3
const EK_WINDOW: int = 4
const EK_STRUCT_BUFF: int = 5
const EK_REPAIR: int = 6
const EK_SMOKE: int = 7
const EK_DECOY: int = 8
const EK_BOMBARD: int = 9
const EK_MARK: int = 10
const SK_PACKET: int = 1
const SK_SPAWN_ZONE: int = 2
const SK_END_ZONE: int = 3
const SK_APPLY_FX: int = 4
const SK_SPAWN_SUMMON: int = 5
const SK_ASSEMBLE: int = 6
const SK_EXPIRE_ENTITY: int = 7
const SK_WINDOW_END: int = 8
const SK_WARNING_END: int = 9
const SK_BEAM_PULSE: int = 10
const SK_REVEAL_START: int = 11
const SK_REVEAL_END: int = 12
const SK_DROP_PAYLOAD: int = 13
const SK_MARK_STRIKE: int = 14
const PKT_INTERCEPTABLE: int = 1
const PKT_BEAM: int = 2
const PKT_EMP: int = 4
const PKT_ENEMY_ONLY: int = 8
const PKT_STRATEGIC: int = 16
const PKT_IGNORE_SMOKE: int = 32
const PKT_SHELL: int = 64
const TS_NONE: int = 0
const TS_HOVER: int = 1
const TS_FLY_TO_HOVER: int = 2
const TS_FLY_TO_DROP: int = 3
const TS_ORBIT: int = 4
const TS_CAPSULE: int = 5
const TS_ENGINE: int = 6
const TS_DECOY: int = 7
const TS_STATION: int = 8
const BR_NONE: int = 0
const BR_ASSAULT_STRUCTURES: int = 1
const BR_SWARM_ZONE: int = 2
const WF_SALVAGEABLE: int = 1
const WF_PAID_BASIS_LOCKED: int = 2

# ---- CF_*: per-cell placement flags (SimPlacementResult.cells) ----
const CF_OK: int = 0
const CF_TERRAIN: int = 1
const CF_STRUCTURE: int = 2
const CF_UNIT: int = 3
const CF_DEPOSIT: int = 4
const CF_DEBRIS: int = 5
const CF_APRON: int = 6
const CF_SHORE: int = 7

# ---- K_*: knob table ids (SimPlayerEcon.knob_*) ----
const K_SAP_RESERVE_TICKS: int = 0
const K_PAD_EXTRA: int = 1
const K_REARM_RATE_BP: int = 2
const K_SALVAGE_TICKS: int = 3
const K_REPAIR_RATE_TECH_BP: int = 4
const K_REPAIR_RATE_TENDER_BP: int = 5
const K_REPAIR_RATE_DEF_BP: int = 6
const K_REPAIR_COST_ENG_VEH_BP: int = 7
const K_EMP_RECOVERY_STRUCT_BP: int = 8
const K_EMP_RECOVERY_UNMANNED_BP: int = 9
const K_RELAY_RADIUS_CELLS: int = 10
const K_RELAY_HOLD_TICKS: int = 11
const K_RELAY_DAMAGE_BP: int = 12
const K_CMD_RADIUS_CELLS: int = 13
const K_CMD_DAMAGE_BP: int = 14
const K_PROD_RATE_BARRACKS_BP: int = 15
const K_PROD_RATE_FACTORY_BP: int = 16
const K_JOINT_LANDING: int = 17
const K_RECOVERY_PRIORITY: int = 18
const K_COUNT: int = 19
## Combine modes of a knob (economy 4.5).
const KM_NONE: int = 0
const KM_MUL: int = 1
const KM_ADD: int = 2
const KM_OVR: int = 3
const KM_MIN: int = 4
const KNOB_MODE: PackedInt32Array = [0, 0, 1, 4, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2, 3, 1, 1, 3, 3]
## Default base value per knob (SAP_RESERVE_TICKS is 400 for SAP rosters, set by init_player).
const KNOB_DEFAULT: PackedInt32Array = [0, 0, 10000, 160, 10000, 10000, 10000, 10000, 10000, 10000, 6, 0, 1000, 5, 1000, 10000, 10000, 0, 0]
## Neutral element of the temporary layer per mode (MUL 10000, ADD 0, OVR / MIN: the base itself).
const KNOB_NEUTRAL_MUL: int = 10000

# ---- CMD_*: the economy block of the master command catalog (SimCmd owns the values) ----
const CMD_BUILD_START: int = 120
const CMD_BUILD_CANCEL: int = 121
const CMD_BUILD_HOLD: int = 122
const CMD_BUILD_PLACE: int = 123
const CMD_TRAIN: int = 124
const CMD_TRAIN_CANCEL: int = 125
const CMD_QUEUE_HOLD: int = 126
const CMD_SET_RALLY: int = 127
const CMD_SET_PRIMARY: int = 128
const CMD_RESEARCH: int = 129
const CMD_RESEARCH_CANCEL: int = 130
const CMD_RESEARCH_HOLD: int = 131
const CMD_SELL: int = 132
const CMD_SET_STRUCT_REPAIR: int = 133
const CMD_UNDEPLOY_HQ: int = 134
const CMD_USE_POWER: int = 140
const CMD_LAUNCH_SUPERWEAPON: int = 141

# ---- EVT_*: economy event block 300..499 (SimEvent.BLOCK_ECONOMY_*); fields per economy 6.2, after x / y ----
const EVT_CMD_REJECTED: int = 300
const EVT_PLACE_REJECTED: int = 301
const EVT_STRUCTURE_READY: int = 302
const EVT_STRUCTURE_PLACED: int = 303
const EVT_STRUCTURE_ACTIVE: int = 304
const EVT_UNIT_PRODUCED: int = 305
const EVT_QUEUE_STATE: int = 306
const EVT_RESEARCH_COMPLETE: int = 307
const EVT_CREDITS_GAINED: int = 308
const EVT_INSUFFICIENT_FUNDS: int = 309
const EVT_UNIT_CAP_REACHED: int = 310
const EVT_POWER_SHORTAGE: int = 311
const EVT_POWER_RESTORED: int = 312
const EVT_SAP_RESERVE_EMPTY: int = 313
const EVT_STRUCTURE_SOLD: int = 314
const EVT_STRUCTURE_SELLING: int = 315
const EVT_REPAIR_STATE: int = 316
const EVT_HQ_DEPLOYED: int = 317
const EVT_HQ_UNDEPLOYED: int = 318
const EVT_ORDER_FAILED: int = 319
const EVT_COLLECTOR_ATTACKED: int = 320
const EVT_NO_REFINERY: int = 321
const EVT_DEPOSIT_DEPLETED: int = 322
const EVT_DEPOSIT_REGROWN: int = 323
const EVT_CAPTURE_PROGRESS: int = 324
const EVT_CAPTURE_CONTESTED: int = 325
const EVT_STRUCTURE_CAPTURED: int = 326
const EVT_SALVAGE_STARTED: int = 327
const EVT_SALVAGE_PAID: int = 328
const EVT_WRECKS_HIGHLIGHTED: int = 329
const EVT_POWER_UNLOCKED: int = 400
const EVT_POWER_READY: int = 401
const EVT_POWER_ACTIVATED: int = 402
const EVT_POWER_EFFECT_END: int = 403
const EVT_WARNING: int = 404
const EVT_SW_READY: int = 405
const EVT_SW_CANCELLED: int = 406
const EVT_SW_EXEC_START: int = 407
const EVT_SW_IMPACT: int = 408
const EVT_SW_DONE: int = 409
const EVT_SUMMON_EXPIRED: int = 410

# ---- tuning numbers of this slice ----
const BUILDUP_TICKS: int = 30  ## inert BUILDUP after placement
const SELL_TICKS: int = 40
const UNDEPLOY_TICKS: int = 40
const INCOME_BUCKET_TICKS: int = 100
const INCOME_BUCKETS: int = 12
const POWER_RECHECK_TICKS: int = 100
const SAP_ADEQUATE_TICKS: int = 1200  ## continuous adequate power before the reserve refills
const APRON_SCAN_CELLS: int = 3  ## neighbour search margin for the apron rule
const SITE_MAX_PROBES: int = 400
const BUILD_RADIUS_U: int = 8192  ## default build radius (8 cells) when a def carries none
const COLLECTOR_QUEUE_KIND: int = 5  ## DefEnums.QueueKind.COLLECTOR

## Ledger reason -> SimEvent.CASH_* code used for the kernel ledger.
const CR_TO_CASH: PackedInt32Array = [0, 5, 5, 5, 5, 5, 1, 2, 4, 3, 1, 6]
