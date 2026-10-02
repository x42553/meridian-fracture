"""PD ships: Reef Patrol Boat, Trident Escort, Tempest Carrier, Shogun Drone Carrier."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pdlib import *  # noqa


def mini_drone(cx, cy, cz, s=1.0, col="sec"):
    """Small folded quad-drone (pad dressing). Coordinates may be expressions."""
    return [
        BR(col), BOX([cx, f"({cy})+{0.05*s}", cz], [0.16 * s, 0.05 * s, 0.2 * s], 0.0),
        BR("dark"), BOX([cx, f"({cy})+{0.045*s}", cz], [0.34 * s, 0.014 * s, 0.03 * s], 0.0), BOX([cx, f"({cy})+{0.045*s}", cz], [0.03 * s, 0.014 * s, 0.34 * s], 0.0),
        BR("acc"), BOX([cx, f"({cy})+{0.085*s}", f"({cz})-{0.1*s}"], [0.05 * s, 0.014 * s, 0.03 * s], 0.0),
    ]


def pad(cx, cy, cz, r=0.42, drone=True):
    ops = [BR("acc"), CYL([cx, f"({cy})+0.005", cz], [cx, f"({cy})+0.03", cz], r, 10, 0.0),
           BR("dark"), CYL([cx, f"({cy})+0.03", cz], [cx, f"({cy})+0.042", cz], r * 0.78, 10, 0.0)]
    if drone:
        ops += mini_drone(cx, f"({cy})+0.042", cz, r / 0.42 * 0.9)
    return ops


def reef_patrol_boat():
    ops = [
        C("team_panel", center=[0, "fb+0.02", -0.95], size=[0.7, 0.02, 0.3]),
        *PAT("ship_patrol"), *EMB("ship_patrol"), *TOP("ship_patrol"),
    ]
    return recipe("unit.pd.reef_patrol_boat", "ship_patrol", {"bow": "sharp", "cabin": "closed", "gun": "mg"}, None, ops,
                  {"role": "patrol_boat", "icon": {"yaw": 150, "pitch": 30, "margin": 0.8}})


def trident_escort():
    mx, my, mz = 0, "fb+3.42", "-hl*0.12-0.55"
    arms = [BR("metal", "metal"), CYL([mx, "fb+3.05", mz], [mx, f"{my}+0.32", mz], 0.03, 6, 0.0),
            BR("acc"), CYL([mx, f"{my}-0.02", mz], [mx, f"{my}+0.05", mz], 0.075, 8, 0.0)]
    for i in range(3):
        arms.append(PUSH([mx, f"{my}+0.02", mz], [0, 120 * i + 90, 0],
                         BR("metal", "metal"), CYL([0.0, 0, 0], [0.5, -0.04, 0], 0.018, 5, 0.0),
                         BR("light", "emissive"), BOX([0.53, -0.05, 0], [0.09, 0.07, 0.09], 0.0)))
    ops = [
        *arms,
        *mini_drone(0, "fb+0.05", "hl-0.85", 1.5),
        MIR(C("team_panel", center=["se_beam*0.5-0.27", "fb+0.03", "-hl+2.3"], size=[0.42, 0.02, 1.2])),
        *PAT("ship_escort"), *EMB("ship_escort"), *TOP("ship_escort"),
    ]
    return recipe("unit.pd.trident_escort", "ship_escort", {"bow": "sharp", "helipad": True, "vls_rows": 3}, None, ops,
                  {"role": "escort", "icon": {"yaw": 150, "pitch": 30, "margin": 0.8}})


def tempest_carrier():
    ops = [
        TIER(1),
        *pad(-0.75, "fb+0.5", -1.2, 0.5), *pad(-0.75, "fb+0.5", 0.9, 0.5),
        TIER(0),
        BR("sec"), DOME(["sc_beam*0.5-0.3", "fb+3.55", "-hl*0.05+0.7"], [0, 1, 0], 0.2, 0.2, 8, 3),
        *PAT("ship_carrier"), *EMB("ship_carrier"), *TOP("ship_carrier"),
    ]
    return recipe("unit.pd.tempest_carrier", "ship_carrier", {"deck": "drones", "bow": "sharp"}, None, ops,
                  {"role": "carrier", "icon": {"yaw": 150, "pitch": 32, "margin": 0.82}})


def shogun_carrier():
    dy = "fb+0.52"
    rails = []
    # port half: strike-drone launch rails (coral) with a drone waiting at the aft end of each rail
    for k, x in enumerate((-1.75, -1.0)):
        rails += [BR("acc"), BOX([x, f"{dy}+0.03", -0.6], [0.16, 0.06, 6.6], 0.01),
                  BR("dark"), BOX([x, f"{dy}+0.065", -0.6], [0.06, 0.02, 6.6], 0.0),
                  BR("metal", "metal"), BOX([x, f"{dy}+0.09", "-hl+2.6"], [0.34, 0.06, 0.14], 0.01)]
        rails += mini_drone(x, f"{dy}+0.06", 2.3, 1.0)
    # starboard half: white interceptor cradles with drones
    cradles = []
    for k in range(4):
        z = -2.7 + 1.6 * k
        cradles += [BR("sec"), BOX([0.75, f"{dy}+0.05", z], [1.05, 0.10, 0.75], 0.02),
                    BR("acc"), BOX([0.75, f"{dy}+0.105", z + 0.36], [1.05, 0.012, 0.04], 0.0)]
        cradles += mini_drone(0.75, f"{dy}+0.10", z, 1.2, col="sec")
    ball = [BR("sec"), CYL(["sc_beam*0.5-0.3", "fb+3.55", "-hl*0.05+0.7"], ["sc_beam*0.5-0.3", "fb+4.35", "-hl*0.05+0.7"], 0.11, 8, 0.0),
            BR("sec"), DOME(["sc_beam*0.5-0.3", "fb+4.3", "-hl*0.05+0.7"], [0, 1, 0], 0.42, 0.42, 10, 4),
            DOME(["sc_beam*0.5-0.3", "fb+4.3", "-hl*0.05+0.7"], [0, -1, 0], 0.42, 0.4, 10, 3),
            BR("light", "emissive"), BOX(["sc_beam*0.5-0.3", "fb+4.32", "-hl*0.05+0.7-0.4"], [0.4, 0.05, 0.03], 0.0)]
    ops = [TIER(1), *rails, *cradles, TIER(0), *ball, *PAT("ship_carrier"), *EMB("ship_carrier")]
    return recipe("unit.pd.shogun_drone_carrier", "ship_carrier", {"deck": "none", "bow": "sharp"}, None, ops,
                  {"role": "carrier", "icon": {"yaw": 150, "pitch": 32, "margin": 0.82}})


RECIPES = ["reef_patrol_boat", "trident_escort", "tempest_carrier", "shogun_carrier"]
