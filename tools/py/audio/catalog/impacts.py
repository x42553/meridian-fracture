"""impacts.py - projectile flight, impacts, explosions, collapses, deaths, interception (audio spec 4.8 families
`snd.proj`, `snd.impact`, `snd.explosion`, `snd.collapse`, `snd.death`, `snd.intercept`).

Positional sounds are mono; sounds that also play flat (huge blasts, big collapses) keep a stereo master and a mono
twin (`channels="both"`)."""
from __future__ import annotations

from catalog import AssetSpec, add

# ---- projectile flight
add(AssetSpec("sfx/proj/missile", "missile_flight", variants=2, channels="mono", loop=True, peak_db=-6.0, lufs=-22.0, tags=("proj", "loop")))
add(AssetSpec("sfx/proj/torpedo", "torpedo_flight", variants=2, channels="mono", loop=True, peak_db=-6.0, lufs=-22.0, tags=("proj", "loop")))
add(AssetSpec("sfx/proj/shell_whistle", "shell_whistle", variants=2, channels="mono", lufs=-19.0, tags=("proj",)))
add(AssetSpec("sfx/proj/bomb_whistle", "bomb_whistle", variants=2, channels="mono", lufs=-19.0, tags=("proj",)))

# ---- impacts
for mat, exc in (("dirt", 0.2), ("concrete", 0.0), ("metal", 0.0), ("flesh", 0.2), ("wood", 0.1), ("water", 0.0)):
    add(AssetSpec(f"sfx/impact/bullet_{mat}", f"bullet_{mat}", variants=2, channels="mono", exciter=exc, tags=("impact",)))
add(AssetSpec("sfx/impact/energy_small", "energy_small", variants=2, channels="mono", tags=("impact",)))
add(AssetSpec("sfx/impact/energy_large", "energy_large", channels="mono", exciter=0.3, tags=("impact",)))
add(AssetSpec("sfx/impact/rail", "rail_hit", channels="mono", exciter=0.5, tags=("impact",)))
add(AssetSpec("sfx/impact/kinetic", "kinetic_hit", channels="mono", exciter=0.7, tags=("impact",)))
add(AssetSpec("sfx/impact/emp", "emp_hit", channels="mono", exciter=0.5, tags=("impact",)))
add(AssetSpec("sfx/intercept/aps", "aps_pop", channels="mono", tags=("intercept",)))
add(AssetSpec("sfx/intercept/zone", "zone_snap", channels="mono", tags=("intercept",)))

# ---- explosions (land)
for size, ch, exc in (("small", "mono", 0.7), ("medium", "mono", 0.7), ("large", "mono", 0.7), ("huge", "both", 0.6)):
    add(AssetSpec(f"sfx/explosion/{size}", "explosion", variants=3, channels=ch, exciter=exc, params={"size": size}, tags=("explosion",)))
# ---- explosions (water)
for size in ("small", "medium", "large"):
    add(AssetSpec(f"sfx/explosion/water_{size}", "explosion_water", variants=2, channels="mono", exciter=0.5, params={"size": size}, tags=("explosion", "water")))
# ---- collapses by footprint area class
for i, (scale, ch) in enumerate(((1.0, "mono"), (2.0, "mono"), (3.0, "both"), (4.0, "both")), start=1):
    add(AssetSpec(f"sfx/collapse/s{i}", "building_collapse", channels=ch, exciter=1.0, params={"scale": scale}, tags=("collapse",)))
# ---- deaths
add(AssetSpec("sfx/death/infantry", "infantry_fall", variants=6, channels="mono", tags=("death",)))
add(AssetSpec("sfx/death/decoy", "decoy_pop", channels="mono", tags=("death",)))
add(AssetSpec("sfx/death/ship", "ship_sink", channels="both", exciter=0.5, tags=("death",)))
add(AssetSpec("sfx/death/sub", "sub_implode", channels="mono", exciter=0.5, tags=("death",)))
add(AssetSpec("sfx/death/drone", "drone_pop", channels="mono", tags=("death",)))
