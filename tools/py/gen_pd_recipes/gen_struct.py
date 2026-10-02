"""PD-specific structures: Sea Spear Battery (advanced defence) and Tempest Swarm Hub (superweapon site)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pdlib import *  # noqa
from gen_sea import mini_drone, pad


def sea_spear_battery():
    ops = [
        # folded sensor mast (SLIDE_Y) on the plinth corner and a drone pad with a stowed quad-drone
        C("sensor_mast", base=["hw-0.75", 0.16, "-hh+0.8"], h=2.6, folded=1.0),
        *pad("-hw+0.95", 0.16, "hh-1.5", 0.36),
        BR("acc"), TIER(1), BOX([0, 0.19, "hh-1.72"], ["pw-1.6", 0.03, 0.08], 0.0), TIER(0),
        C("team_panel", center=[0, 0.2, "hh-0.62"], size=["pw-1.5", 0.02, 0.6]),
    ]
    return recipe("structure.pd.sea_spear_battery", "str_defense_adv", {"kit": "sea_spear"}, None, ops,
                  {"role": "advanced_defense", "icon": {"yaw": 160, "pitch": 30, "margin": 0.8}})


def tempest_swarm_hub():
    ops = [
        *pad("-hw+1.7", 0.16, "hh-1.25", 0.5), *pad("hw-1.7", 0.16, "hh-1.25", 0.5),
        C("sensor_crown", center=["hw-0.9", 0.16, "-hh+0.9"], n=6, r=0.3),
    ]
    return recipe("structure.pd.tempest_swarm_hub", "str_superweapon", {"kit": "hive_tower"}, None, ops,
                  {"role": "superweapon", "icon": {"yaw": 160, "pitch": 32, "margin": 0.85}})


RECIPES = ["sea_spear_battery", "tempest_swarm_hub"]


# ================================================================================================ summons (PD trim on the shared summon archetypes)
def _petrel_ops():
    import gen_air
    return gen_air.petrel_fighter()["ops_after"]


def summon_patrol_aircraft():
    ops = [o for o in _petrel_ops() if not (isinstance(o, dict) and o.get("slot") in ("top_air_jet", "emb_air_jet"))]
    return recipe("summon.pd.patrol_aircraft", "air_jet", {"wing": "swept", "tail": "twin", "fold": True}, None, ops,
                  {"role": "summon", "icon": {"yaw": 150, "pitch": 28, "margin": 0.8}})


def summon_decoy_transport():
    import gen_ground
    r = gen_ground.wake_skimmer()
    r["id"] = "summon.pd.decoy_transport"
    r["style"] = "owner"
    r["meta"] = {"role": "summon", "icon": {"yaw": 150, "pitch": 24, "margin": 0.78}}
    return r


def summon_workshop_aircraft():
    ops = [MIR(BR("acc"), BOX([0.91, 1.35, 0.6], [0.03, 0.14, 3.8], 0.0)), BR("acc"), BOX([0, 2.06, 2.9], [1.9, 0.03, 0.4], 0.0)]
    return recipe("summon.pd.workshop_aircraft", "sum_cargo", None, None, ops, {"role": "summon"})


def _drone_ring(rid):
    ops = [TIER(2), BR("acc"), FOR("i", 3, PUSH(["(i-1)*1.5", 0, "abs(i-1)*0.7"], None,
                                                CYL([0, 0.5, 0], [0, 0.53, 0], 0.27, 8, 0.0),
                                                BR("sec"), BOX([0, 0.85, 0.2], [0.08, 0.05, 0.16], 0.0), BR("acc"))), TIER(0)]
    return recipe(rid, "sum_drone_swarm", None, None, ops, {"role": "summon"})


def summon_interceptor_drone():
    return _drone_ring("summon.pd.interceptor_drone")


def summon_surface_strike_drone():
    return _drone_ring("summon.pd.surface_strike_drone")


def summon_tempest_strike_drone():
    return _drone_ring("summon.pd.tempest_strike_drone")


RECIPES += ["summon_patrol_aircraft", "summon_decoy_transport", "summon_workshop_aircraft", "summon_interceptor_drone",
            "summon_surface_strike_drone", "summon_tempest_strike_drone"]
