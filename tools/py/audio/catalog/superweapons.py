"""superweapons.py - `snd.sw.<name>.<charge|launch|loop|impact|end>` for the 8 superweapons (audio spec 5.12).
Phases used per weapon follow the 5.12 table.  charge and loop are seamless loops; launch/impact/end are one-shots.
Flat (non-positional) launches and ends keep a stereo master plus a mono twin; positional launches/impacts are mono."""
from __future__ import annotations

from catalog import AssetSpec, add

# (name, phase, recipe, channels, loop, variants, exciter)
SW = [
    ("atlas", "launch", "sw_atlas_launch", "both", False, 1, 0.5),
    ("atlas", "impact", "sw_atlas_impact", "mono", False, 3, 0.9),
    ("aurora", "charge", "sw_aurora_charge", "mono", True, 1, 0.0),
    ("aurora", "launch", "sw_aurora_launch", "both", False, 1, 0.6),
    ("aurora", "loop", "sw_aurora_loop", "mono", True, 1, 0.0),
    ("aurora", "impact", "sw_aurora_impact", "both", False, 1, 0.6),
    ("aurora", "end", "sw_aurora_end", "both", False, 1, 0.4),
    ("helios", "charge", "sw_helios_charge", "mono", True, 1, 0.0),
    ("helios", "launch", "sw_helios_launch", "both", False, 1, 0.5),
    ("helios", "loop", "sw_helios_loop", "mono", True, 1, 0.1),
    ("helios", "end", "sw_helios_end", "both", False, 1, 0.2),
    ("perun", "launch", "sw_perun_launch", "mono", False, 1, 0.5),
    ("perun", "impact", "sw_perun_impact", "mono", False, 1, 0.9),
    ("tempest", "launch", "sw_tempest_launch", "mono", False, 1, 0.3),
    ("tempest", "loop", "sw_tempest_loop", "mono", True, 1, 0.1),
    ("tempest", "end", "sw_tempest_end", "both", False, 1, 0.1),
    ("dragonfall", "launch", "sw_dragonfall_launch", "both", False, 1, 0.5),
    ("dragonfall", "loop", "sw_dragonfall_loop", "mono", True, 1, 0.2),
    ("dragonfall", "impact", "sw_dragonfall_impact", "mono", False, 3, 0.9),
    ("dragonfall", "end", "sw_dragonfall_end", "both", False, 1, 0.4),
    ("horizon", "charge", "sw_horizon_charge", "mono", True, 1, 0.1),
    ("horizon", "launch", "sw_horizon_launch", "mono", False, 1, 0.7),
    ("horizon", "impact", "sw_horizon_impact", "mono", False, 3, 0.9),
    ("trident", "launch", "sw_trident_launch", "both", False, 1, 0.2),
    ("trident", "loop", "sw_trident_loop", "mono", True, 1, 0.1),
    ("trident", "end", "sw_trident_end", "both", False, 1, 0.6),
]
LOOP_LUFS = -22.0
for name, phase, recipe, ch, loop, var, exc in SW:
    add(AssetSpec(f"sfx/sw/{name}_{phase}", recipe, variants=var, channels=ch, loop=loop, peak_db=-6.0 if loop else -1.5,
                  lufs=LOOP_LUFS if loop else -15.0, exciter=exc, tags=("sw", name)))
