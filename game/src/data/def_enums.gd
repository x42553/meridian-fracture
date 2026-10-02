class_name DefEnums
extends RefCounted
## Single source of truth for every integer code of the data domain (data_balance 4.1). Codes are used by replays,
## events and checksums and are append-only. `*_NAMES` arrays are index == code and match `global.json` /
## TAXONOMY ids (the loader verifies them, V-CNF-05).

## Def kinds. Bible id prefixes unit. structure. research. power. superweapon. faction. roster. modifier. selector.;
## balance-owned prefixes warch. zone. neutral. summon. ability.
enum Kind {
	UNIT = 0, STRUCTURE = 1, WEAPON_ARCH = 2, PROJECTILE = 3, RESEARCH = 4, POWER = 5, SUPERWEAPON = 6,
	ZONE = 7, NEUTRAL = 8, FACTION = 9, ROSTER = 10, MODIFIER = 11, SELECTOR = 12, ABILITY = 13, COUNT = 14,
}
const KIND_NAMES: PackedStringArray = [
	"unit", "structure", "warch", "projectile", "research", "power", "superweapon", "zone", "neutral",
	"faction", "roster", "modifier", "selector", "ability",
]
## Required id prefix per kind ("" = none; units also accept "summon.").
const KIND_PREFIX: PackedStringArray = [
	"unit.", "structure.", "warch.", "", "research.", "power.", "superweapon.", "zone.", "neutral.",
	"faction.", "roster.", "modifier.", "selector.", "ability.",
]

## Resolver stat vocabulary. 0..12 may appear in bible modifiers; 13..15 exist only in balance effects (layer 3).
enum Stat {
	COST = 0, BUILD_TIME = 1, HEALTH = 2, SPEED = 3, DAMAGE = 4, RANGE = 5, RELOAD = 6, REARM = 7, SIGHT = 8,
	POWER = 9, REPAIR_RATE = 10, REPAIR_COST = 11, PROJ_SPEED = 12, RESIST = 13, PROD_RATE = 14, REARM_RATE = 15,
	COUNT = 16,
}
const STAT_COUNT_BIBLE: int = 13
const STAT_NAMES: PackedStringArray = [
	"cost_credits", "build_time_seconds", "health", "movement_speed", "weapon_damage", "weapon_range_cells",
	"reload_interval_seconds", "rearm_time_seconds", "sight_cells", "power_output", "repair_progress_rate",
	"repair_credit_cost_per_health", "projectile_flight_speed", "damage_resistance", "production_rate", "rearm_rate",
]

enum DamageType { BULLET = 0, AP = 1, HE = 2, THERMAL = 3, RAIL = 4, KINETIC = 5, EMP = 6, COUNT = 7 }
const DAMAGE_NAMES: PackedStringArray = ["bullet", "ap", "he", "thermal", "rail", "kinetic", "emp"]
## ResistGroup bit mask values (global.json resist_groups order).
const RG_BULLET: int = 1
const RG_EXPLOSIVE: int = 2
const RG_BEAM: int = 4
const RG_THERMAL: int = 8
const RG_RAIL: int = 16
const RG_KINETIC: int = 32
const RG_EMP: int = 64
const RESIST_GROUP_NAMES: PackedStringArray = ["bullet", "explosive", "beam", "thermal", "rail", "kinetic", "emp"]
## Frozen per-damage-type group mask (verified against global.json).
const DAMAGE_GROUP_MASK: PackedInt32Array = [1, 2, 2, 12, 16, 32, 64]

enum ArmorClass {
	INFANTRY = 0, LIGHT_VEHICLE = 1, MEDIUM_ARMOR = 2, HEAVY_ARMOR = 3, AIR_LIGHT = 4, AIR_HEAVY = 5, SHIP_LIGHT = 6,
	SHIP_HEAVY = 7, BUILDING_LIGHT = 8, BUILDING_HEAVY = 9, FORTRESS = 10, COUNT = 11,
}
const ARMOR_NAMES: PackedStringArray = [
	"infantry", "light_vehicle", "medium_armor", "heavy_armor", "air_light", "air_heavy", "ship_light", "ship_heavy",
	"building_light", "building_heavy", "fortress",
]

enum Layer { GROUND = 0, AIR = 1, SURFACE_WATER = 2, UNDERWATER = 3, COUNT = 4 }
const LAYER_NAMES: PackedStringArray = ["ground", "air", "surface_water", "underwater"]
const L_GROUND: int = 1
const L_AIR: int = 2
const L_WATER: int = 4
const L_UNDER: int = 8

enum MoveClass {
	FOOT = 0, WHEELED = 1, TRACKED = 2, AMPHIBIOUS = 3, NAVAL = 4, SUBMERGED = 5, AIR_FIXED = 6, AIR_HOVER = 7,
	STATIC = 8, COUNT = 9,
}
const MOVE_NAMES: PackedStringArray = [
	"foot", "wheeled", "tracked", "amphibious", "naval", "submerged", "air_fixed", "air_hover", "static",
]

enum TerrainKind { ROAD = 0, OPEN = 1, ROUGH = 2, FOREST = 3, MARSH = 4, SHALLOW = 5, DEEP = 6, CLIFF = 7, COUNT = 8 }
const TERRAIN_NAMES: PackedStringArray = ["road", "open", "rough", "forest", "marsh", "shallow", "deep", "cliff"]

enum FireMode { DIRECT = 0, INDIRECT = 1, MELEE = 2, COUNT = 3 }
const FIRE_NAMES: PackedStringArray = ["direct", "indirect", "melee"]

## Interceptable: TRIDENT = artillery shells/rockets (Trident only); APS_TRIDENT = ordinary guided missiles.
enum Interceptable { NONE = 0, TRIDENT = 1, APS_TRIDENT = 2 }
const INTERCEPT_NAMES: PackedStringArray = ["none", "trident", "aps_trident"]

enum WeaponArch {
	SMALL_ARMS = 0, MACHINE_GUN = 1, AUTOCANNON = 2, TANK_CANNON = 3, SIEGE_GUN = 4, DEMOLITION_CANNON = 5,
	AT_MISSILE = 6, AA_MISSILE = 7, FLAK = 8, ARTILLERY_SHELL = 9, ROCKET_BARRAGE = 10, MORTAR = 11,
	MISSILE_ARTILLERY = 12, BEAM_THERMAL = 13, RAIL_GUN = 14, TORPEDO = 15, DEPTH_CHARGE = 16, BOMB = 17,
	AIR_MISSILE = 18, EMP_PULSE = 19, CANISTER = 20, GRENADE_LAUNCHER = 21, BREACH_CHARGE = 22, NAVAL_GUN = 23,
	NAVAL_BOMBARD = 24, CRUISE_MISSILE = 25, DRONE_MISSILE = 26, COUNT = 27,
}
const WEAPON_ARCH_NAMES: PackedStringArray = [
	"small_arms", "machine_gun", "autocannon", "tank_cannon", "siege_gun", "demolition_cannon", "at_missile",
	"aa_missile", "flak", "artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "beam_thermal",
	"rail_gun", "torpedo", "depth_charge", "bomb", "air_missile", "emp_pulse", "canister", "grenade_launcher",
	"breach_charge", "naval_gun", "naval_bombard", "cruise_missile", "drone_missile",
]

enum ProjKind {
	BULLET = 0, SHELL = 1, MISSILE = 2, ROCKET = 3, BEAM = 4, RAIL = 5, TORPEDO = 6, BOMB = 7, FIELD = 8,
	PELLETS = 9, GRENADE = 10, CHARGE = 11, COUNT = 12,
}
const PROJ_NAMES: PackedStringArray = [
	"bullet", "shell", "missile", "rocket", "beam", "rail", "torpedo", "bomb", "field", "pellets", "grenade", "charge",
]

enum SizeClass {
	INFANTRY = 0, LIGHT = 1, MEDIUM = 2, HEAVY = 3, HUGE = 4, AIR_MEDIUM = 5, AIR_LARGE = 6, SHIP_SMALL = 7,
	SHIP_MEDIUM = 8, SHIP_LARGE = 9, S1 = 10, S2 = 11, S3 = 12, S4 = 13, COUNT = 14,
}
const SIZE_NAMES: PackedStringArray = [
	"inf", "light", "medium", "heavy", "huge", "air_medium", "air_large", "ship_small", "ship_medium", "ship_large",
	"s1", "s2", "s3", "s4",
]

enum UnitClass { SERVICE = 0, BASELINE = 1, UNIQUE = 2, SUMMON = 3, DRONE = 4 }
const UNIT_CLASS_NAMES: PackedStringArray = ["service", "baseline", "unique", "summon", "drone"]
enum RosterKind { VANILLA = 0, SUBFACTION = 1 }
enum QueueKind { NONE = 0, INFANTRY = 1, VEHICLE = 2, AIRCRAFT = 3, NAVAL = 4, COLLECTOR = 5 }
enum TargetMode { NONE = 0, POINT = 1, LINE = 2, OWN_STRUCTURE = 3 }
enum TargetVision { ANY = 0, EXPLORED = 1, CURRENT = 2 }
enum ZoneKind {
	BUFF = 0, SMOKE = 1, INTERCEPT = 2, DEBRIS = 3, DECOY = 4, PUCK = 5, SHELTER = 6, COVER = 7, REPAIR = 8, REVEAL = 9,
}
enum ZoneShape { CIRCLE = 0, LINE = 1 }
const AFFECTS_FRIENDLY: int = 1
const AFFECTS_ENEMY: int = 2
const AFFECTS_ALL: int = 3
enum NeutralKind { CIVILIAN_GARRISON = 0, POWER_SUBSTATION = 1, OBSERVATION_POST = 2, SALVAGE_DEPOT = 3, DEPOSIT = 4, FIELD_HOSPITAL = 5, HARBOR_TERMINAL = 6 }
enum SwAction {
	KINETIC_VOLLEY = 0, EMP_BURST = 1, BEAM_SWEEP = 2, BUNKER_BUSTER = 3, DRONE_SWARM = 4, ENGINE_DROP = 5,
	RAIL_STRIKE = 6, INTERCEPT_ZONE = 7,
}
enum PowerOp { ZONE = 1, SUMMON = 2, STRIKE = 3, MARK = 4, GLOBAL_EFFECT = 5 }
enum EffectOp {
	STAT_MOD = 1, RESIST_MOD = 2, PARAM_MOD = 3, GRANT_ABILITY = 4, SET_FLAG = 5, IMMUNITY = 6, HEAL = 7,
	CAMOUFLAGE = 8, REVEAL = 9, DISABLE = 10, MARK = 11, SPAWN_ZONE = 12,
}
enum ParamOp { SET = 0, ADD = 1, MUL_BP = 2 }
enum ParamScope { ABILITY = 0, DEF = 1, PLAYER = 2 }
enum Membership { CONTINUOUS = 0, LATCHED = 1 }

## Condition codes (evaluated at runtime by abilities/combat unless folded statically, data_balance 5.9).
enum Cond {
	NONE = 0, ON_WATER = 1, IN_CIVILIAN_GARRISON = 2, PAID_VEHICLE_REPAIR = 3, NEAR_FRIENDLY_UNIT = 10,
	NEAR_FRIENDLY_STRUCTURE = 11, TARGET_NEAR_FRIENDLY_UNIT = 12, IN_RELAY_FIELD = 13, STATIONARY = 14,
	OUT_OF_COMBAT = 15, RECENTLY_DISEMBARKED = 16, DEPLOYED = 17, CAMOUFLAGED = 18, IN_ZONE = 19,
	STRUCTURE_POWERED = 20, ON_WATER_RT = 21, BEHIND_COVER = 22,
}
## Exact bible condition strings -> Cond (also the placement-condition strings of structures, see PLACE_*).
const COND_TEXT_ON_WATER: String = "The vehicle is on water."
const COND_TEXT_GARRISON: String = "The infantry unit occupies a marked civilian garrison."
const COND_TEXT_PAID_REPAIR: String = "The target is receiving paid land-vehicle repairs."
const PLACE_TEXT_STRATEGIC: String = "Maximum one strategic structure per player."
const PLACE_TEXT_NO_EXTENSION: String = "Normal construction radius; does not extend it."
const PLACE_TEXT_SHORELINE: String = "Valid shoreline placement."

## Structure placement flags (DefStructure.place_mask).
const PLACE_SHORELINE: int = 1
const PLACE_MAX_ONE_STRATEGIC: int = 2
const PLACE_NO_RADIUS_EXTENSION: int = 4

## Unit / weapon / structure flags.
const UF_FIRE_STATIONARY: int = 1
const UF_HOVER_FIRE: int = 2
const UF_NO_COMBAT_MODS: int = 4
const UF_NO_COMMAND_BUFF: int = 8
const UF_NO_REPAIR: int = 16
const UF_NO_CAPTURE: int = 32
const UF_NO_SALVAGE: int = 64
const UF_NON_BLOCKING: int = 128
const UF_HARMLESS: int = 256
const UF_PRODUCIBLE: int = 512
const UF_UNARMED: int = 1024
const UNIT_FLAG_NAMES: PackedStringArray = [
	"fire_stationary", "hover_fire", "no_combat_mods", "no_command_buff", "no_repair", "no_capture", "no_salvage",
	"non_blocking", "harmless",
]
const WF_SUPPRESSIVE: int = 1
const WF_STATIONARY_FIRE: int = 2
const WF_NEEDS_LOS: int = 4
const WF_POINT_DEFENSE: int = 8
const WF_HOMING: int = 16
const SF_POWERED_DEFENSE: int = 1
const SF_NO_BUILD: int = 2
const SF_SELLABLE: int = 4
const SF_REPAIRABLE: int = 8
const SF_CAPTURE_IMMUNE: int = 16
const SF_STRATEGIC: int = 32
const SF_RELAY: int = 64
const SF_PRODUCTION: int = 128

## Ability kinds (ids fixed; names = ability_kinds.json keys upper-cased). COUNT 40 (35..39 reserved).
enum AbilityKind {
	DETECTOR = 1, CAMOUFLAGE = 2, DEPLOY = 3, MODE_SWITCH = 4, TRANSPORT = 5, HEAL = 6, REPAIR = 7, COMMAND_FIELD = 8,
	INTERCEPTOR = 9, SUPPRESSION_SUPPORT = 10, DECOY_SPAWN = 11, SENSOR_PUCK = 12, SMOKE_LAUNCHER = 13,
	EW_JAMMER = 14, DISEMBARK_BUFF = 15, PORTABLE_COVER = 16, SALVAGE = 17, FRONTAL_SHIELD = 18, CARRIER = 19,
	SENSOR_MAST = 20, CAPTURE = 21, HARVEST = 22, DEPLOY_STRUCTURE = 23, SUBMERGE = 24, SORTIE = 25, SPOTTER = 26,
	REGEN = 27, DIRECTIONAL_ARMOR = 28, RELAY_FIELD = 29, SERVICE_PADS = 30, REFINERY = 31, AURA_REGEN = 32,
	DEFENSE_POWER_RESERVE = 33, SUMMON_ORBIT = 34, COUNT = 40,
}
## Index = AbilityKind value (0 and 35..39 are "").
const ABILITY_NAMES: PackedStringArray = [
	"", "detector", "camouflage", "deploy", "mode_switch", "transport", "heal", "repair", "command_field",
	"interceptor", "suppression_support", "decoy_spawn", "sensor_puck", "smoke_launcher", "ew_jammer",
	"disembark_buff", "portable_cover", "salvage", "frontal_shield", "carrier", "sensor_mast", "capture", "harvest",
	"deploy_structure", "submerge", "sortie", "spotter", "regen", "directional_armor", "relay_field", "service_pads",
	"refinery", "aura_regen", "defense_power_reserve", "summon_orbit", "", "", "", "", "",
]

## Fixed bible tag bit positions (UT_* = 1 << bit). Balance-added tags take bits from the first free bit.
const UNIT_TAG_NAMES: PackedStringArray = [
	"aircraft", "amphibious", "anti_air", "anti_submarine", "anti_tank", "artillery", "capture", "carrier", "collector",
	"combat", "command", "construction", "detector", "electronic_warfare", "ground", "ground_attack", "infantry",
	"land_vehicle", "light", "repair", "scout", "service", "ship", "siege", "specialist", "submarine", "tank",
	"transport", "unmanned",
]
const UNIT_TAG_EXTRA_FIRST: int = 29
const STRUCT_TAG_NAMES: PackedStringArray = ["advanced_defense", "defense", "relay", "structure", "superweapon"]
const STRUCT_TAG_EXTRA_FIRST: int = 5
## Derived weapon-archetype tags (also the projectile namespace).
const WEAPON_TAG_NAMES: PackedStringArray = [
	"thermal_beam", "guided_missile", "direct_fire", "indirect_fire", "anti_air", "anti_ground", "anti_sub",
]
const WEAPON_TAG_EXTRA_FIRST: int = 7
## The 15 tags used by bible selectors; never addable via tags_add (V-CNF-03).
const LOCKED_TAGS: PackedStringArray = [
	"aircraft", "amphibious", "artillery", "combat", "defense", "ground", "infantry", "land_vehicle", "light", "scout",
	"ship", "superweapon", "tank", "transport", "unmanned",
]
const UT_AIRCRAFT: int = 1 << 0
const UT_AMPHIBIOUS: int = 1 << 1
const UT_ANTI_AIR: int = 1 << 2
const UT_ANTI_SUBMARINE: int = 1 << 3
const UT_ANTI_TANK: int = 1 << 4
const UT_ARTILLERY: int = 1 << 5
const UT_CAPTURE: int = 1 << 6
const UT_CARRIER: int = 1 << 7
const UT_COLLECTOR: int = 1 << 8
const UT_COMBAT: int = 1 << 9
const UT_COMMAND: int = 1 << 10
const UT_CONSTRUCTION: int = 1 << 11
const UT_DETECTOR: int = 1 << 12
const UT_ELECTRONIC_WARFARE: int = 1 << 13
const UT_GROUND: int = 1 << 14
const UT_GROUND_ATTACK: int = 1 << 15
const UT_INFANTRY: int = 1 << 16
const UT_LAND_VEHICLE: int = 1 << 17
const UT_LIGHT: int = 1 << 18
const UT_REPAIR: int = 1 << 19
const UT_SCOUT: int = 1 << 20
const UT_SERVICE: int = 1 << 21
const UT_SHIP: int = 1 << 22
const UT_SIEGE: int = 1 << 23
const UT_SPECIALIST: int = 1 << 24
const UT_SUBMARINE: int = 1 << 25
const UT_TANK: int = 1 << 26
const UT_TRANSPORT: int = 1 << 27
const UT_UNMANNED: int = 1 << 28
const ST_ADVANCED_DEFENSE: int = 1 << 0
const ST_DEFENSE: int = 1 << 1
const ST_RELAY: int = 1 << 2
const ST_STRUCTURE: int = 1 << 3
const ST_SUPERWEAPON: int = 1 << 4
const WT_THERMAL_BEAM: int = 1 << 0
const WT_GUIDED_MISSILE: int = 1 << 1
const WT_DIRECT_FIRE: int = 1 << 2
const WT_INDIRECT_FIRE: int = 1 << 3
const WT_ANTI_AIR: int = 1 << 4
const WT_ANTI_GROUND: int = 1 << 5
const WT_ANTI_SUB: int = 1 << 6
## Max tag bits per namespace (V-SCH-08).
const MAX_TAG_BITS: int = 62


## ResistGroup bit of a group name (0 when unknown).
static func resist_group_bit(name: String) -> int:
	var i: int = RESIST_GROUP_NAMES.find(name)
	return 0 if i < 0 else (1 << i)


## Layer mask bit of a layer name (0 when unknown).
static func layer_bit(name: String) -> int:
	var i: int = LAYER_NAMES.find(name)
	return 0 if i < 0 else (1 << i)
