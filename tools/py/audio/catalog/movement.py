"""movement.py - `snd.loop.*` engine / step / air loops and `snd.air.*` one-shots (audio spec 4.8).
Loop loudness targets (5.1): tracked / wheeled / boat -22 LUFS, rotor -20, footsteps -24 (K-weighted, gated)."""
from __future__ import annotations

from catalog import AssetSpec, add

LOOPS = [
    ("engine_wheeled", "engine_wheeled", {}, -22.0, 0.15),
    ("engine_tracked", "engine_tracked", {}, -22.0, 0.15),
    ("engine_tracked_heavy", "engine_tracked", {"heavy": True}, -22.0, 0.15),
    ("engine_amphibious", "engine_tracked", {"amphibious": True}, -22.0, 0.15),
    ("engine_boat_small", "engine_boat", {}, -22.0, 0.1),
    ("engine_boat_large", "engine_boat", {"large": True}, -22.0, 0.15),
    ("engine_sub", "engine_sub", {}, -24.0, 0.2),
    ("step_foot", "step_foot", {}, -24.0, 0.0),
    ("air_jet", "air_jet", {}, -22.0, 0.1),
    ("air_rotor", "air_rotor", {}, -21.5, 0.1),
    ("air_drone", "air_drone", {}, -24.0, 0.0),
]
for name, recipe, params, lufs, exc in LOOPS:
    add(AssetSpec(f"sfx/loop/{name}", recipe, channels="mono", loop=True, peak_db=-6.0, lufs=lufs, exciter=exc, params=params, tags=("loop",)))

add(AssetSpec("sfx/air/takeoff", "air_takeoff", channels="mono", exciter=0.3, lufs=-18.0, tags=("air",)))
add(AssetSpec("sfx/air/landing", "air_landing", channels="mono", exciter=0.3, lufs=-18.0, tags=("air",)))
add(AssetSpec("sfx/air/crash_fall", "air_crash_fall", channels="mono", exciter=0.2, lufs=-18.0, tags=("air",)))
