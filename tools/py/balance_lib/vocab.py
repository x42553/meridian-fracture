"""Frozen vocabulary (docs/balance/TAXONOMY.md section 11 / DefEnums). global.json must carry exactly this (V-CNF-05)."""
from __future__ import annotations

DAMAGE_TYPES = ["bullet", "ap", "he", "thermal", "rail", "kinetic", "emp"]
DAMAGE_GROUPS = {"bullet": ["bullet"], "ap": ["explosive"], "he": ["explosive"], "thermal": ["beam", "thermal"], "rail": ["rail"], "kinetic": ["kinetic"],
                 "emp": ["emp"]}
NONLETHAL = {"emp"}
RESIST_GROUPS = ["bullet", "explosive", "beam", "thermal", "rail", "kinetic", "emp"]
ARMOR_CLASSES = ["infantry", "light_vehicle", "medium_armor", "heavy_armor", "air_light", "air_heavy", "ship_light", "ship_heavy", "building_light",
                 "building_heavy", "fortress"]
LAYERS = ["ground", "air", "surface_water", "underwater"]
FIRE_MODES = ["direct", "indirect", "melee"]
SIZE_CLASSES = ["inf", "light", "medium", "heavy", "huge", "air_medium", "air_large", "ship_small", "ship_medium", "ship_large", "s1", "s2", "s3", "s4"]
UNIT_SIZE_CLASSES = SIZE_CLASSES[:10]
TERRAIN_KINDS = ["road", "open", "rough", "forest", "marsh", "shallow", "deep", "cliff"]
MOVE_CLASSES = ["foot", "wheeled", "tracked", "amphibious", "naval", "submerged", "air_fixed", "air_hover", "static"]
WEAPON_ARCHETYPES = ["small_arms", "machine_gun", "autocannon", "tank_cannon", "siege_gun", "demolition_cannon", "at_missile", "aa_missile", "flak",
                     "artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "beam_thermal", "rail_gun", "torpedo", "depth_charge", "bomb",
                     "air_missile", "emp_pulse", "canister", "grenade_launcher", "breach_charge", "naval_gun", "naval_bombard", "cruise_missile",
                     "drone_missile"]
# weapon-instance fields fixed by the archetype (V-CNF-08)
ARCHETYPE_LOCKED = ["damage_type", "fire_mode", "projectile_kind", "interceptable_by"]

UNIT_FLAGS = ["fire_stationary", "hover_fire", "no_combat_mods", "no_command_buff", "no_repair", "no_capture", "no_salvage", "non_blocking", "harmless"]
STRUCT_FLAGS = ["powered_defense", "sellable", "repairable", "capture_immune", "relay", "production"]
WEAPON_FLAGS = ["stationary_fire", "needs_los", "point_defense"]

# bible-unit ids that the bible describes as unarmed (V-CMP-05)
UNARMED_UNITS = ["unit.shared.engineer", "unit.shared.collector", "unit.shared.mobile_construction_vehicle", "unit.shared.landing_transport",
                 "unit.napc.combat_medic", "unit.olm.mirage_observer", "unit.han.link_operator", "unit.han.mekong_field_engineer",
                 "unit.pd.reef_technician", "unit.nec.aster_ew_aircraft"]
UNIT_CODES = ["ae", "def", "han", "napc", "nec", "olm", "pd", "sap", "shared"]
