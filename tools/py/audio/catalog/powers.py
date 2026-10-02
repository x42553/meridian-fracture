"""powers.py - `snd.power.<class>.<activate|loop|end>` and `snd.power.barrage.warning|impact` (audio spec 4.8)."""
from __future__ import annotations

from catalog import AssetSpec, add

CLASSES = ("recon", "repair", "buff", "shield", "cloak", "smoke", "barrage", "generic")
ROOT_HZ = {"buff": 220.0, "generic": 196.0}
for c in CLASSES:
    p = {"cls": c}
    if c in ROOT_HZ:
        p["root_hz"] = ROOT_HZ[c]
    add(AssetSpec(f"sfx/power/{c}_activate", "power_activate", channels="both", exciter=0.2, lufs=-17.0, params=dict(p), tags=("power",)))
    add(AssetSpec(f"sfx/power/{c}_loop", "power_loop", channels="mono", loop=True, peak_db=-6.0, lufs=-24.0, params=dict(p), tags=("power", "loop")))
    add(AssetSpec(f"sfx/power/{c}_end", "power_end", channels="both", lufs=-17.0, params=dict(p), tags=("power",)))
add(AssetSpec("sfx/power/barrage_warning", "barrage_warning", channels="stereo", peak_db=-4.0, lufs=-16.0, tags=("power", "warning")))
add(AssetSpec("sfx/power/barrage_impact", "barrage_impact", variants=3, channels="mono", exciter=0.6, tags=("power",)))
