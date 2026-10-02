"""structures.py - `snd.struct.*` and `snd.eco.*` (audio spec 4.8): construction-complete cues for the 15 structure kinds,
sell / repair / salvage, power, unit-out, hums (loops) and cash ticks."""
from __future__ import annotations

from catalog import AssetSpec, add

KINDS = ("hq", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory", "watchtower", "turret",
         "aa_battery", "relay", "superweapon", "adv_defense")
for k in KINDS:
    add(AssetSpec(f"sfx/struct/online_{k}", "struct_online", channels="both", exciter=0.4, lufs=-17.0, params={"kind": k}, tags=("struct",)))
add(AssetSpec("sfx/struct/sell", "struct_sell", channels="both", exciter=0.2, lufs=-17.0, tags=("struct",)))
add(AssetSpec("sfx/struct/repair", "struct_repair", channels="mono", loop=True, peak_db=-6.0, lufs=-24.0, tags=("struct", "loop")))
add(AssetSpec("sfx/struct/salvage", "struct_salvage", channels="mono", loop=True, peak_db=-6.0, lufs=-24.0, tags=("struct", "loop")))
add(AssetSpec("sfx/struct/power_down", "power_down", channels="both", exciter=0.4, lufs=-16.0, tags=("struct", "power")))
add(AssetSpec("sfx/struct/power_up", "power_up", channels="both", exciter=0.3, lufs=-15.0, tags=("struct", "power")))
add(AssetSpec("sfx/struct/defense_offline", "defense_offline", channels="mono", exciter=0.3, lufs=-18.0, tags=("struct",)))
for k in ("infantry", "vehicle", "aircraft", "ship"):
    add(AssetSpec(f"sfx/struct/unit_out_{k}", "unit_out", channels="both", exciter=0.2, lufs=-17.0, params={"kind": k}, tags=("struct",)))
add(AssetSpec("sfx/struct/captured", "struct_captured", channels="both", lufs=-17.0, tags=("struct",)))
add(AssetSpec("sfx/struct/hq_deploy", "hq_deploy", channels="both", exciter=0.4, lufs=-17.0, tags=("struct",)))
for k, lufs in (("generator", -26.0), ("radar", -28.0), ("lab", -28.0), ("airfield", -28.0), ("refinery", -26.0)):
    add(AssetSpec(f"sfx/struct/hum_{k}", "struct_hum", channels="mono", loop=True, peak_db=-6.0, lufs=lufs, exciter=0.1, params={"kind": k}, tags=("struct", "loop")))
add(AssetSpec("sfx/eco/cash", "cash_tick", variants=3, channels="stereo", peak_db=-6.0, lufs=-24.0, tags=("eco",)))
add(AssetSpec("sfx/eco/cash_big", "cash_big", channels="stereo", peak_db=-5.0, lufs=-20.0, tags=("eco",)))
