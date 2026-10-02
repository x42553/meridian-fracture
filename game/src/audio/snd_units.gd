class_name SndUnits
extends RefCounted
## Sim units to metres, size classes, material and warhead tables, the frozen weapon-archetype table (audio spec 5.4).

const M_PER_UNIT: float = SndConfig.M_PER_UNIT

enum Mat { DIRT = 0, CONCRETE = 1, METAL = 2, FLESH = 3, WOOD = 4, WATER = 5 }
const MAT_NAMES: PackedStringArray = ["dirt", "concrete", "metal", "flesh", "wood", "water"]
enum Size { TINY = 0, SMALL = 1, MEDIUM = 2, LARGE = 3, HUGE = 4 }
const SIZE_NAMES: PackedStringArray = ["small", "small", "medium", "large", "huge"]  ## TINY plays the small sound
enum Kind { BULLET = 0, EXPLOSIVE = 1, ENERGY = 2, RAIL = 3, KINETIC = 4, EMP = 5 }
enum VoiceClass { INFANTRY = 0, VEHICLE = 1, HEAVY = 2, AIR = 3, NAVAL = 4, SUPPORT = 5, STRUCTURE = 6 }
const VOICE_CLASS_NAMES: PackedStringArray = ["infantry", "vehicle", "heavy", "air", "naval", "support", "structure"]

## Flight classes of the archetype table: 0 none/hitscan, 1 bullet-like, 2 missile, 3 arc, 4 bomb, 5 torpedo.
const FLIGHT_NONE: int = 0
const FLIGHT_BULLET: int = 1
const FLIGHT_MISSILE: int = 2
const FLIGHT_ARC: int = 3
const FLIGHT_BOMB: int = 4
const FLIGHT_TORPEDO: int = 5

## (name, damage type name, flight class) in frozen DefEnums.WeaponArch order.
const ARCH_TABLE: Array = [
	["small_arms", "bullet", 1], ["machine_gun", "bullet", 1], ["autocannon", "bullet", 1], ["tank_cannon", "ap", 3],
	["siege_gun", "he", 3], ["demolition_cannon", "he", 3], ["at_missile", "ap", 2], ["aa_missile", "ap", 2],
	["flak", "he", 3], ["artillery_shell", "he", 3], ["rocket_barrage", "he", 3], ["mortar", "he", 3],
	["missile_artillery", "ap", 2], ["beam_thermal", "thermal", 0], ["rail_gun", "rail", 0], ["torpedo", "ap", 5],
	["depth_charge", "he", 0], ["bomb", "he", 4], ["air_missile", "ap", 2], ["emp_pulse", "emp", 0],
	["canister", "bullet", 1], ["grenade_launcher", "he", 1], ["breach_charge", "he", 0], ["naval_gun", "ap", 3],
	["naval_bombard", "he", 3], ["cruise_missile", "he", 2], ["drone_missile", "ap", 2],
]
const DTYPE_NAMES: PackedStringArray = ["bullet", "ap", "he", "thermal", "rail", "kinetic", "emp"]
## damage type index (DT_*) to warhead kind.
const DTYPE_KIND: PackedByteArray = [0, 1, 1, 2, 3, 4, 5]
## ArmorClass index to material: infantry FLESH; vehicles, air, ships METAL; buildings CONCRETE.
const ARMOR_MATERIAL: PackedByteArray = [3, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1]
## MapTerrain id (0..14) to material.
const TERRAIN_MATERIAL: PackedByteArray = [5, 5, 5, 0, 0, 0, 0, 1, 4, 1, 1, 1, 1, 1, 1]


static func to_world(x: int, y: int, h: float = 1.5) -> Vector3:
	return Vector3(float(x) * M_PER_UNIT, h, float(y) * M_PER_UNIT)


static func cell_of(v: int) -> int:
	return v >> SndConfig.CELL_SHIFT


static func arch_name(arch: int) -> String:
	return ARCH_TABLE[arch][0] if arch >= 0 and arch < ARCH_TABLE.size() else ""


static func arch_flight(arch: int) -> int:
	return int(ARCH_TABLE[arch][2]) if arch >= 0 and arch < ARCH_TABLE.size() else 0


static func arch_kind(arch: int) -> int:
	if arch < 0 or arch >= ARCH_TABLE.size():
		return Kind.BULLET
	return kind_of_dtype(DTYPE_NAMES.find(String(ARCH_TABLE[arch][1])))


static func kind_of_dtype(dtype: int) -> int:
	return int(DTYPE_KIND[dtype]) if dtype >= 0 and dtype < DTYPE_KIND.size() else Kind.EXPLOSIVE


## Size class from a splash radius in sub-cells: 0 TINY, <= 819 SMALL, <= 1536 MEDIUM, <= 2560 LARGE, else HUGE.
static func size_of_radius(r: int, small: int = 819, medium: int = 1536, large: int = 2560) -> int:
	if r <= 0:
		return Size.TINY
	if r <= small:
		return Size.SMALL
	if r <= medium:
		return Size.MEDIUM
	if r <= large:
		return Size.LARGE
	return Size.HUGE


static func material_of_armor(armor: int) -> int:
	return int(ARMOR_MATERIAL[armor]) if armor >= 0 and armor < ARMOR_MATERIAL.size() else Mat.METAL


static func material_of_terrain(terrain_id: int) -> int:
	return int(TERRAIN_MATERIAL[terrain_id]) if terrain_id >= 0 and terrain_id < TERRAIN_MATERIAL.size() else Mat.DIRT


## Structure footprint area (cells) to the collapse class: 0 s1 (<= 1), 1 s2 (<= 4), 2 s3 (<= 9), 3 s4.
static func area_class(cells: int) -> int:
	if cells <= 1:
		return 0
	if cells <= 4:
		return 1
	if cells <= 9:
		return 2
	return 3
