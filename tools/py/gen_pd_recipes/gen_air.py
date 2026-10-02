"""PD aircraft: Petrel, Wedge, Osprey."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pdlib import *  # noqa


def fold_tips(wing_wx, wzl1, wzt1, winglet=False, hinge_col="acc"):
    """Coral wing tips (and optional canted winglets) riding the fold parts, plus a coral hinge line at x = 1.1."""
    ops = []
    for side, param in ((1, 0.857), (-1, 0.143)):
        s = side
        ch = f"({wzl1}+{wzt1})*0.5"
        inner = [
            BR("acc"),
            BOX([f"{s}*({wing_wx}-0.17)", 0.66, ch], [0.34, 0.078, f"({wzt1})-({wzl1})+0.02"], 0.0),
        ]
        if winglet:
            inner += [PUSH([f"{s}*({wing_wx}-0.03)", 0.66, ch], [0, 0, -s * 22],
                           BOX([0, 0.19, 0], [0.04, 0.4, f"(({wzt1})-({wzl1}))*0.7"], 0.0))]
        ops.append(PART("deploy_z", [f"{s}*1.1", 0.66, 0.6], param, 0, None, *inner))
    hinge = MIR(BR("acc"), TIER(1),
                BOX([1.1, 0.665, "lerp(wzl0,wzl1,0.45)+(lerp(wzt0,wzt1,0.45)-lerp(wzl0,wzl1,0.45))*0.5"], [0.05, 0.085, "lerp(wzt0,wzt1,0.45)-lerp(wzl0,wzl1,0.45)"], 0.0),
                TIER(0))
    return ops + [hinge]


def petrel_fighter():
    ops = [
        # white belly + white nose radome + coral tail tips on the twin fins
        BR("sec"), BOX([0, 0.475, 0.2], [0.44, 0.04, 3.0], 0.0),
        FRU([0, 0.70, -2.62], [0, 0.70, -2.0], 0.02, 0.12, 6),
        BOX([0, 0.99, 1.7], [0.14, 0.05, 1.0], 0.0),
        MIR(PUSH([0.42, 0.85, 0], [0, 0, -14], BR("acc"), BOX([0, 0.78, 2.17], [0.055, 0.18, 0.46], 0.0))),
        *fold_tips(2.05, 0.9, 1.75),
        *BAND("air_jet"), *EMB("air_jet"), *TOP("air_jet"),
    ]
    return recipe("unit.pd.petrel_fighter", "air_jet", {"wing": "swept", "tail": "twin", "fold": True}, None, ops,
                  {"role": "fighter", "icon": {"yaw": 150, "pitch": 28, "margin": 0.8}})


def wedge_recon_fighter():
    ops = [
        BR("sec"), BOX([0, 0.475, 0.2], [0.44, 0.04, 3.0], 0.0),
        # dorsal sensor spine
        TIER(1),
        BOX([0, 1.10, 0.95], [0.16, 0.10, 2.0], 0.0),
        BR("acc"), BOX([0, 1.16, 0.95], [0.08, 0.02, 1.9], 0.0),
        BR("sec"), FRU([0, 1.1, -0.05], [0, 1.1, -0.35], 0.07, 0.03, 6),
        TIER(0),
        # chin sensor ball (low-poly), emissive slit
        BR("metal", "metal"), CYL([0, 0.5, -1.55], [0, 0.42, -1.55], 0.05, 6, 0.0),
        BR("sec"), DOME([0, 0.42, -1.55], [0, -1, 0], 0.17, 0.17, 8, 3),
        BR("light", "emissive"), BOX([0, 0.36, -1.7], [0.14, 0.03, 0.02], 0.0),
        BR("dark"), BOX([0, 1.09, -0.25], [0.3, 0.02, 0.5], 0.0), BOX([0, 1.09, 2.0], [0.26, 0.02, 0.35], 0.0),
        # fuselage recon pods (coral lens)
        MIR(BR("sec"), CYL([0.5, 0.55, 0.9], [0.5, 0.55, -0.1], 0.1, 8, 0.0),
            FRU([0.5, 0.55, -0.1], [0.5, 0.55, -0.32], 0.1, 0.04, 8),
            BR("acc"), CYL([0.5, 0.55, -0.31], [0.5, 0.55, -0.37], 0.05, 6, 0.0)),
        *fold_tips(1.9, 1.15, 1.95, winglet=True),
        *BAND("air_jet"), *EMB("air_jet"),
    ]
    return recipe("unit.pd.wedge_recon_fighter", "air_jet", {"wing": "delta", "tail": "single", "fold": True}, None, ops,
                  {"role": "recon_fighter", "icon": {"yaw": 150, "pitch": 28, "margin": 0.8}})


def osprey():
    tips = []
    for s in (1, -1):
        hub = [f"{s}*2.0", 1.42, 0.2]
        tips.append(PART("rotor", hub, None, None, None,
                         FOR("i", 3, PUSH(hub, [0, f"{s}*120*i", 0], BR("acc"), BOX([f"{s}*1.09", 0.004, 0], [0.24, 0.036, 0.17], 0.0)))))
    hinge = MIR(BR("acc"), TIER(1), CYL([1.72, 1.0, 0.3], [1.8, 1.0, 0.3], 0.24, 8, 0.0), TIER(0))
    ops = [
        BR("sec"), BOX([0, 0.72, 0.6], [0.52, 0.04, 2.8], 0.0),
        *tips, hinge, C("team_panel", center=[0, 1.43, 2.55], size=[0.24, 0.02, 0.7]),
        # rear cargo ramp seam + coral tail tips
        BR("acc"), BOX([0, 1.34, 3.86], [0.06, 0.18, 0.22], 0.0),
        *BAND("air_heli"), *EMB("air_heli"), *TOP("air_heli"),
    ]
    return recipe("unit.pd.osprey_strike_tiltrotor", "air_heli", {"rotors": "tilt", "stubs": "pods"}, None, ops,
                  {"role": "tiltrotor_gunship", "icon": {"yaw": 150, "pitch": 28, "margin": 0.8}})


RECIPES = ["petrel_fighter", "wedge_recon_fighter", "osprey"]
