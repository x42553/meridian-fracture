"""ambience.py - `snd.amb.*` stereo beds (16-24 s loops, audio spec 4.8 / 5.1: wind -26, coast -26, city -30 LUFS)."""
from __future__ import annotations

from catalog import AssetSpec, add

for name, recipe, lufs in (("wind_open", "amb_wind_open", -26.0), ("city_hum", "amb_city_hum", -30.0), ("coast_waves", "amb_coast_waves", -26.0),
                           ("river_flow", "amb_river_flow", -27.0), ("forest", "amb_forest", -29.0), ("battle_far", "amb_battle_far", -32.0)):
    add(AssetSpec(f"amb/{name}", recipe, channels="stereo", loop=True, peak_db=-9.0, lufs=lufs, quality="ambience", tags=("ambience", "loop")))
