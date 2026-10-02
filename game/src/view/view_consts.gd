class_name ViewConsts
extends RefCounted
## Unit conversions, angle helpers and enums of the presentation layer (render spec 4.1, 4.2).
## Presentation code only: floats are fine here, nothing in this file feeds back into the simulation.

const M_PER_UNIT: float = 3.0 / 1024.0  ## sim sub-cell unit -> metres (exact in float32)
const UNIT_PER_M: float = 1024.0 / 3.0
const CELL_M: float = 3.0
const BAT_TO_RAD: float = TAU / 4096.0
const TELEPORT_SNAP_UNITS: int = 6144  ## |curr - prev| above this in one tick = snap, no interpolation (6 cells)
const FOG_UPDATE_S: float = 0.1  ## sim vision stride 2 at 20 TPS = 10 Hz; cross-fade length
const GROUND_LIFT_M: float = 0.02  ## units rest 2 cm above the interpolated terrain height (z-fight guard)

## VQ2A readability boost: PURELY visual uniform scale applied on top of recipe.scale * archetype.scale * pres_scale_bp for every
## unit-like archetype (sim radii and footprints are untouched). Keyed by the archetype size_class for the unit archetypes (veh_ inf_ air_ ship_);
## structures, summons and projectiles are never boosted (structures are built for their footprint cells). The tank hull (3.5 m) grows to 4.2 m, i.e. half-length 2.1 m, still inside the art
## direction 5.7 footprint rule L/2 <= 1.3 * r * 3 m = 2.15 m; infantry squads read at about 110 px wide at the default framing.
const VISUAL_BOOST: Dictionary = {"inf": 1.35, "light": 1.2, "medium": 1.2, "heavy": 1.15, "huge": 1.1, "air": 1.2, "ship": 1.1}
static var visual_boost_enabled: bool = true  ## QA switch (before / after shots, tests); never part of any setting


## Boost factor of a unit archetype (veh_ / inf_ / air_ / ship_ ids keyed by their size_class); 1.0 for structures, summons,
## projectiles, unknown classes or when the QA switch is off.
static func visual_boost(arch_id: StringName, size_class: StringName) -> float:
	if not visual_boost_enabled:
		return 1.0
	var a: String = String(arch_id)
	if not (a.begins_with("veh_") or a.begins_with("inf_") or a.begins_with("air_") or a.begins_with("ship_")):
		return 1.0
	return float(VISUAL_BOOST.get(String(size_class), 1.0))


# visual state
const VS_HIDDEN: int = 0
const VS_VISIBLE: int = 1
const VS_GHOST: int = 2
const VS_DYING: int = 3

# motion classes (identical to data's MoveClass)
const MOTION_FOOT: int = 0
const MOTION_WHEELED: int = 1
const MOTION_TRACKED: int = 2
const MOTION_AMPHIBIOUS: int = 3
const MOTION_NAVAL: int = 4
const MOTION_SUB: int = 5
const MOTION_AIR_FIXED: int = 6
const MOTION_AIR_HOVER: int = 7
const MOTION_STATIC: int = 8

# fog states (one byte per cell)
const FOG_SHROUD: int = 0
const FOG_FOG: int = 1
const FOG_VISIBLE: int = 2

# view-derived death kinds
const DK_VEHICLE: int = 1
const DK_INFANTRY: int = 2
const DK_CRASH: int = 3
const DK_AIR_EXPLODE: int = 4
const DK_SINK: int = 5
const DK_STRUCTURE: int = 6
const DK_DRONE: int = 7
const DK_SILENT: int = 8

# structure phases
const PH_ACTIVE: int = 0
const PH_BUILDUP: int = 1
const PH_SELLING: int = 2
const PH_UNDEPLOY: int = 3

# instance flags (u_state.z, float-encoded int; bit values are the cross-shader contract of unit.gdshader)
const UF_FOG_DIM: int = 1
const UF_GHOST: int = 2
const UF_SUBMERGED: int = 4
const UF_UNPOWERED: int = 8
const UF_CLOAKED: int = 16
const UF_EMP: int = 32
const UF_WRECK: int = 64
const UF_SUPPRESSED: int = 128
const UF_DECOY_ID: int = 256
const UF_STRUCT: int = 512  ## structure look: cracks / paint loss from `damage`, u_anim.y = power-fade depth (VIEW-W2)


## Sim heading (bat 0..4095) -> view yaw in radians (model -Z forward -> sim heading).
static func yaw_of_bat(bat: int) -> float:
	return -float(bat) * BAT_TO_RAD - PI * 0.5


## Turret yaw relative to the hull from a hull-relative bat angle.
static func turret_yaw(rel_bat: int) -> float:
	return -float(wrap_bat(rel_bat)) * BAT_TO_RAD


## Turret yaw from absolute angles (tools and tests only).
static func rel_yaw(abs_bat: int, hull_bat: int) -> float:
	return turret_yaw(abs_bat - hull_bat)


static func wrap_bat(d: int) -> int:
	return ((d + 2048) & 4095) - 2048


## Shortest-way interpolation in bat; the result is NOT wrapped.
static func lerp_bat(a: int, b: int, t: float) -> float:
	return float(a) + float(wrap_bat(b - a)) * t


## Quarter turns clockwise seen from above (structures store 1024 * orient in `facing`).
static func struct_rot(facing: int) -> int:
	return ((facing + 512) >> 10) & 3


## Sim sub-cell units -> world XZ metres (terrain height is added by the caller).
static func sim_to_world_xz(x: int, y: int) -> Vector2:
	return Vector2(float(x) * M_PER_UNIT, float(y) * M_PER_UNIT)


## World XZ metres -> sim sub-cell units, rounded once (the UI turns this into SimCommand ints).
static func world_to_sim_xz(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * UNIT_PER_M), roundi(p.y * UNIT_PER_M))


static func has_flag(flags: int, bit: int) -> bool:
	return (flags & bit) != 0
