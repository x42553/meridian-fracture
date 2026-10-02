class_name AiTypes
extends RefCounted
## All enums and constants of the AI module (ai.md 4.1). No logic, only a few name lookups. The integer values are
## normative: telemetry, the decision trace and the tests use them. The AI module is NOT part of the deterministic core
## (it may use floats), but every decision below is integer arithmetic so a run is reproducible.

enum Difficulty { EASY = 0, MEDIUM = 1, HARD = 2, BRUTAL = 3 }
enum Phase { OPENING = 0, BUILDUP = 1, MIDGAME = 2, LATE = 3, DESPERATE = 4 }
enum Posture { TURTLE = 0, BALANCED = 1, AGGRESSIVE = 2, ALL_IN = 3 }
enum Style { PUSH = 0, PRONG = 1, RAID = 2, CREEP = 3, LANDING = 4, AIR = 5, FORTRESS = 6 }
enum Expand { EARLY = 0, DEFENDED = 1, LATE = 2, MINIMAL = 3 }
enum OpType { NONE = 0, ATTACK = 1, DEFEND = 2, HARASS = 3, EXPAND = 4, CAPTURE = 5, SALVAGE = 6, LANDING = 7, NAVAL = 8, AIR = 9, HUNT = 10 }
enum OpState { NEW = 0, FORMING = 1, STAGING = 2, ADVANCING = 3, ENGAGING = 4, SIEGING = 5, RETREATING = 6, CLEANUP = 7, DONE = 8, FAILED = 9 }
enum SquadKind { RESERVE = 0, MAIN = 1, FLANK = 2, DEFENSE = 3, HARASS = 4, SCOUT = 5, AIR_STRIKE = 6, AIR_PATROL = 7, TRANSPORT = 8, NAVAL = 9, ENGINEER = 10, CAPTURE = 11, SALVAGE = 12, EXPANSION = 13, REPAIR = 14 }
enum WantKind { STRUCT = 0, UNIT_ROLE = 1, UNIT_DEF = 2, RESEARCH = 3 }
enum WantOrigin { EMERGENCY = 0, OPENER = 1, TARGET = 2, POWER_GRID = 3, ECONOMY = 4, TECH = 5, COUNTER = 6, DEFENSE = 7, EXPANSION = 8, SUPERWEAPON = 9, ARMY = 10 }
enum WantState { OPEN = 0, ISSUED = 1, DONE = 2, DROPPED = 3 }
enum StructKind { HQ = 0, GENERATOR = 1, REFINERY = 2, BARRACKS = 3, FACTORY = 4, DOCK = 5, RADAR = 6, AIRFIELD = 7, LAB = 8, WATCHTOWER = 9, AT_TURRET = 10, AA_BATTERY = 11, ADV_DEFENSE = 12, SUPERWEAPON = 13, RELAY = 14, OTHER = 15 }
enum Cat { AIR = 0, ARMOR = 1, INFANTRY = 2, ARTILLERY = 3, NAVAL = 4, SUB = 5, CAMO = 6, STATIC_DEF = 7, LIGHT = 8, TRANSPORT = 9, COUNT = 10 }
enum OrderKind { IDLE = 0, MOVE = 1, ATTACK_MOVE = 2, ATTACK = 3, GUARD = 4, DEPLOYING = 5, DEPLOYED = 6, PACKING = 7, LOADING = 8, UNLOADING = 9, HARVEST = 10, REPAIR = 11, CAPTURE = 12, SALVAGE = 13, RETURNING = 14, OTHER = 15 }
enum Rule { OK = 0, NEED_PREREQ = 1, NO_CREDITS = 2, QUEUE_FULL = 3, LIMIT = 4, POWER = 5, UNIT_CAP = 6, NOT_PLACEABLE = 7, BUSY = 8, LOCKED = 9, OTHER = 15 }
enum PowerStatus { READY = 0, COOLDOWN = 1, LOCKED_PREREQ = 2, UNPOWERED = 3, NO_CREDITS = 4 }
enum SwStatus { NONE = 0, CHARGING = 1, READY = 2, WARNING = 3 }
enum TargetRule { ANY = 0, VISIBLE = 1, EXPLORED = 2, OWN_AREA = 3 }
enum MapFamily { OPEN = 0, URBAN = 1, COAST = 2 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2, AMPHIBIOUS = 3, NAVAL = 4, SUBMERGED = 5, AIR = 6 }  ## local alias of DefEnums.MoveClass (AIR_FIXED = 6)
enum PowerArch { REVEAL = 0, REVEAL_CORRIDOR = 1, STRIKE = 2, BUFF = 3, BUFF_MOVE = 4, PRODUCTION = 5, REPAIR_ZONE = 6, SMOKE = 7, DECOY = 8, MARK = 9, GUARD_STRUCT = 10, CAMO_HOLD = 11, TRANSPORT_BUFF = 12, ECON_BOOST = 13, FIELD_BOOST = 14, ANTI_EMP = 15, SW_MULTI_CIRCLE = 16, SW_DISC_RING = 17, SW_LINE = 18, SW_AREA_DRONES = 19, SW_DROP = 20, SW_SHIELD = 21, SW_DISABLE_ZONE = 22 }
enum Err { NONE = 0, CMD_LOOP = 1, NO_EFFECT = 2, ROLE_MISSING = 3, DATA_MISSING = 4, BUDGET_DEBT = 5, EXCEPTION_BURST = 6, OP_TIMEOUT = 7, STALL_ECON = 8, STALL_QUEUE = 9, STALL_ARMY = 10, STALL_POWER = 11 }
enum Intent { NONE = 0, BUILD_START = 1, BUILD_PLACE = 2, BUILD_CANCEL = 3, TRAIN = 4, TRAIN_CANCEL = 5, QUEUE_HOLD = 6, RESEARCH = 7, SET_RALLY = 8, STRUCT_REPAIR = 9, MOVE = 10, ATTACK_MOVE = 11, ATTACK = 12, FORCE_FIRE = 13, GUARD = 14, STOP = 15, SCATTER = 16, DEPLOY = 17, PACK = 18, SET_MODE = 19, USE_ABILITY = 20, LOAD = 21, UNLOAD = 22, GARRISON = 23, CAPTURE = 24, REPAIR = 25, SALVAGE = 26, HARVEST = 27, RETURN_TO_BASE = 28, USE_POWER = 29, LAUNCH_SW = 30, HOLD = 31, SET_STANCE = 32, COUNT = 33 }
enum Tele { FIRST_SCOUT_SENT = 1, FIRST_BARRACKS = 2, FIRST_FACTORY = 3, FIRST_RADAR = 4, FIRST_LAB = 5, FIRST_TANK = 6, FIRST_AA = 7, FIRST_SIEGE = 8, FIRST_AIRCRAFT = 9, FIRST_NAVAL = 10, SW_STRUCT_DONE = 11, SW_LAUNCHED = 12, POWER_USED = 13, ATTACK_LAUNCHED = 14, ATTACK_CONTACT = 15, ATTACK_ABORTED = 16, EXPANSION_DEPLOYED = 17, DEFEND_STARTED = 18, STALL = 19, CMD_REJECTED = 20, AI_ERROR = 21, TECH_SWITCH = 22, RETREAT_ORDERED = 23, DISPERSAL = 24, SALVAGE_DONE = 25, LANDING_LAUNCHED = 26, PHASE_CHANGE = 27, POSTURE_CHANGE = 28, OPENER_DONE = 29, SAFE_MODE = 30,
	SIEGE_STARTED = 31, CAPTURE_STARTED = 32, CAPTURE_DONE = 33, NAVAL_LAUNCHED = 34, AIR_SORTIE = 35, UNIT_RETREAT = 36, LANDING_DONE = 37, EXPAND_OP = 38 }
enum Why { NONE = 0, WANT_ISSUED = 1, BURN_GATED = 2, NO_FUNDS = 3, PREREQ_MISSING = 4, LAUNCH_GATE_RATIO = 5, LAUNCH_GATE_TIME = 6, ABORT_RATIO = 7, RETREAT_HP = 8, POWER_BENEFIT_LOW = 9, POWER_GATE = 10, SW_HOLD = 11, SW_FIRE = 12, BLACKLISTED = 13, REJECTED = 14, THROTTLED = 15 }
## Derived event record codes (ai.md 5.3.2 / 6.2; AI-internal, append-only). Record layout: [code, a, b, c, d, e].
enum Ev { OWN_SPAWNED = 1, OWN_LOST = 2, OWN_DAMAGED = 3, UNSEEN_HIT = 4, ENEMY_SEEN = 5, ENEMY_GONE = 6, ENEMY_ARTY_FIRED = 7, WRECK_SEEN = 8, SW_WARNING = 9, POWER_STATE = 10, INCOME = 11, RESEARCH_DONE = 12, CONSTRUCTION_READY = 13, PRODUCTION_DONE = 14, PLAYER_DEFEATED = 15, CAMO_ALERT = 16 }

const AI_EXEC_LAG: int = 6
const AI_MAX_CMDS_PER_THINK: int = 64
const AI_MAX_IDS_PER_CMD: int = 48
const AI_LEVEL_COUNT: int = 4
const AI_STYLE_COUNT: int = 4
const TAKEOVER_LEVEL: int = 1
const GLOBAL_WU_PER_TICK: int = 2400  ## match-wide budget the factory divides among live thinkers (ai.md 5.2)

const RF_FOG: int = 1
const RF_SUPERWEAPONS: int = 2
const RF_SHARED_VISION: int = 4

# entity flag bits returned by AiWorldView.e_flags
const EF_CAMO: int = 1
const EF_DEPLOYED: int = 2
const EF_EMP: int = 4
const EF_UNPOWERED: int = 8
const EF_UNDER_CONSTRUCTION: int = 16
const EF_GARRISONED: int = 32
const EF_LOADED: int = 64
const EF_DECOY: int = 128
const EF_MOVING: int = 256
const EF_SUPPRESSED: int = 512
const EF_REPAIRING: int = 1024
const EF_HELD: int = 2048

## Role bit indices (AiUnitProfile.role_mask, 64-bit; ai.md 4.1).
const R_INFANTRY_BASIC: int = 0
const R_INFANTRY_AT: int = 1
const R_INFANTRY_SUPPORT: int = 2
const R_SCOUT_LIGHT: int = 3
const R_TANK_MAIN: int = 4
const R_AA_MOBILE: int = 5
const R_ARTILLERY: int = 6
const R_HEAVY: int = 7
const R_COMMAND_WALKER: int = 8
const R_FIGHTER: int = 9
const R_BOMBER: int = 10
const R_EW_AIR: int = 11
const R_BOAT_LIGHT: int = 12
const R_ESCORT_SHIP: int = 13
const R_SIEGE_SHIP: int = 14
const R_CARRIER: int = 15
const R_SUBMARINE: int = 16
const R_AMPH_TRANSPORT: int = 17
const R_ENGINEER: int = 18
const R_COLLECTOR: int = 19
const R_MCV: int = 20
const R_LANDING_TRANSPORT: int = 21
const R_DETECTOR: int = 22
const R_HEALER: int = 23
const R_REPAIRER: int = 24
const R_COMMAND_PROVIDER: int = 25
const R_SPOTTER: int = 26
const R_SALVAGER: int = 27
const R_AMPHIBIOUS: int = 28
const R_UNMANNED: int = 29
const R_KITER: int = 30
const R_STATIONARY_FIRE: int = 31
const R_COMBAT: int = 32
const R_STRUCTURE: int = 33
const ROLE_COUNT: int = 34
const ROLE_NAMES: PackedStringArray = [
	"INFANTRY_BASIC", "INFANTRY_AT", "INFANTRY_SUPPORT", "SCOUT_LIGHT", "TANK_MAIN", "AA_MOBILE", "ARTILLERY", "HEAVY",
	"COMMAND_WALKER", "FIGHTER", "BOMBER", "EW_AIR", "BOAT_LIGHT", "ESCORT_SHIP", "SIEGE_SHIP", "CARRIER", "SUBMARINE",
	"AMPH_TRANSPORT", "ENGINEER", "COLLECTOR", "MCV", "LANDING_TRANSPORT", "DETECTOR", "HEALER", "REPAIRER",
	"COMMAND_PROVIDER", "SPOTTER", "SALVAGER", "AMPHIBIOUS", "UNMANNED", "KITER", "STATIONARY_FIRE", "COMBAT", "STRUCTURE",
]

## Unit-handler bit indices (AiUnitProfile.handler_mask; behaviours in ai.md 5.9.5).
const HANDLER_NAMES: PackedStringArray = [
	"DEPLOY_SIEGE", "MODE_SWITCH", "LOADOUT", "CAMO_HOLD", "ESCORT_PROVIDER", "HEALER_FOLLOW", "REPAIR_FOLLOW", "SPOTTER_LINK",
	"AP_INTERCEPT", "TRANSPORT_SHUTTLE", "SMOKE_ON_RETREAT", "DECOY_PLACE", "PUCK_PLACE", "COVER_DEPLOY", "BREACH_ASSAULT",
	"SALVAGE", "CARRIER_ESCORT", "EW_ESCORT", "MAST_DEPLOY", "WING_SWITCH", "SHOOT_SCOOT", "SUB_BOMBARD", "LANDING_BONUS",
	"GARRISON_PREF",
]

## Doctrine flag bits (AiPersonality.flags; assigned per roster in ai.md 5.14.2).
const DOCTRINE_NAMES: PackedStringArray = [
	"PRESERVE_VEHICLES", "APRON_RETREAT", "AIR_LOADOUT", "AMPHIBIOUS_ROUTES", "RELAY_NETWORK", "SENSOR_MAST", "SIEGE_DEPLOY",
	"SHELTER_COVER", "POWER_RICH", "SMOKE_RETREAT", "COLLECTOR_RAID", "DECOYS", "COMMAND_FIELD", "SALVAGE", "GARRISON",
	"CAPTURE_POINTS", "DEFENSE_CLUSTER", "INTERCEPTOR_ESCORT", "OBSERVER_LINK", "MODE_SWITCH", "CAMO_AMBUSH", "TRANSPORT_ASSAULT",
	"REPAIR_TENDERS", "TWO_FRONT", "SHOOT_SCOOT", "STAGED_PUSH",
]

const LEVEL_KEYS: PackedStringArray = ["ai.level.easy", "ai.level.medium", "ai.level.hard", "ai.level.brutal"]
const STYLE_KEYS: PackedStringArray = ["ai.style.doctrine", "ai.style.aggressive", "ai.style.defensive", "ai.style.wildcard"]
const LEVEL_IDS: PackedStringArray = ["easy", "medium", "hard", "brutal"]
const INTENT_NAMES: PackedStringArray = [
	"NONE", "BUILD_START", "BUILD_PLACE", "BUILD_CANCEL", "TRAIN", "TRAIN_CANCEL", "QUEUE_HOLD", "RESEARCH", "SET_RALLY",
	"STRUCT_REPAIR", "MOVE", "ATTACK_MOVE", "ATTACK", "FORCE_FIRE", "GUARD", "STOP", "SCATTER", "DEPLOY", "PACK", "SET_MODE",
	"USE_ABILITY", "LOAD", "UNLOAD", "GARRISON", "CAPTURE", "REPAIR", "SALVAGE", "HARVEST", "RETURN_TO_BASE", "USE_POWER",
	"LAUNCH_SW", "HOLD", "SET_STANCE",
]


## Bit index of a role name, -1 when unknown.
static func role_bit(role_name: String) -> int:
	return ROLE_NAMES.find(role_name)


static func handler_bit(handler_name: String) -> int:
	return HANDLER_NAMES.find(handler_name)


static func doctrine_bit(flag_name: String) -> int:
	return DOCTRINE_NAMES.find(flag_name)


## 1 << role as a role_mask value.
static func role_flag(role: int) -> int:
	return 1 << role

# entity kinds as read through AiWorldView.read_row (mirror SimEntity.Kind; the numbers are part of the sim's wire/hash layout)
const KIND_UNIT: int = 0
const KIND_STRUCTURE: int = 1
const KIND_WRECK: int = 2
const KIND_ZONE: int = 3
const KIND_NEUTRAL: int = 4

# read_row layout: out = [def, owner, kind, x, y, vx, vy, hp, hp_max, flags, order_kind, ticks_since_combat, layer, paid_cost, container]
const ROW_DEF: int = 0
const ROW_OWNER: int = 1
const ROW_KIND: int = 2
const ROW_X: int = 3
const ROW_Y: int = 4
const ROW_VX: int = 5
const ROW_VY: int = 6
const ROW_HP: int = 7
const ROW_HP_MAX: int = 8
const ROW_FLAGS: int = 9
const ROW_ORDER: int = 10
const ROW_SINCE_COMBAT: int = 11
const ROW_LAYER: int = 12
const ROW_PAID: int = 13
const ROW_CONTAINER: int = 14
const ROW_SIZE: int = 15

const NEVER: int = -1000000
const AIR_PARKED: int = 0  ## AiWorldView.e_air_state: on a pad, fully loaded (mirrors the sortie machine's AIR_PARKED)
const AIR_TAKEOFF: int = 1
const AIR_TRANSIT: int = 2
const AIR_ATTACK: int = 3
const AIR_PATROL: int = 4
const AIR_RETURN: int = 5
const AIR_LANDING: int = 6
const AIR_REARM: int = 7
const AIR_NO_BASE: int = 8
const AIR_DOCKED: int = 9
