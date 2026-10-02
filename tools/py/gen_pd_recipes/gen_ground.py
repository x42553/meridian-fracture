"""PD ground units: infantry, tanks, amphibious skimmers, AA, howitzers, assault carrier."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pdlib import *  # noqa

ICON = {"yaw": 150, "pitch": 24, "margin": 0.78}
ICON_INF = {"yaw": 160, "pitch": 24, "margin": 0.78}


# ================================================================================================ infantry
def squad_extras(n, radius, body_ops, only=None):
    """Per-soldier extras (inside a body_bob part, tagged with the member) replicating the archetype's formation maths."""
    return FOR("i", only if only is not None else "n",
               LET(a0="(n) == 2 ? PI*0.5 : 0",
                   fx=f"((n) == 1 ? 0 : sin(i*TAU/(n) + a0)*{radius}) + (rnd(i)-0.5)*0.05",
                   fz=f"((n) == 1 ? 0 : -cos(i*TAU/(n) + a0)*{radius}) + (rnd(i+9)-0.5)*0.05",
                   ph="(i + 0.5)/(n)"),
               ["member", "i", "n"],
               PART("body_bob", [0, 0, 0], "ph", 0, None, PUSH(["fx", 0, "fz"], None, *body_ops)),
               ["member", 0, 0])


def ranger_marine():
    body = [
        TIER(2),
        # snorkel mask pushed up on the helmet, coral J-tube snorkel on the left of the helmet, coral dry bag across the pack
        BR("glass", "glass"), BOX([0, 0.985, -0.115], [0.16, 0.05, 0.03], 0.0),
        BR("acc"), BOX([-0.125, 1.0, -0.03], [0.02, 0.32, 0.02], 0.0), BOX([-0.125, 1.16, -0.07], [0.02, 0.02, 0.1], 0.0),
        CYL([-0.15, 0.80, 0.27], [0.15, 0.80, 0.27], 0.085, 8, 0.0),
        TIER(0)]
    return recipe("unit.pd.ranger_marine", "inf_rifle", {"n": 3, "kit": "rifle", "helmet": "round"},
                  ops_after=[squad_extras(3, 0.42, body)], meta={"role": "infantry", "icon": ICON_INF})


def island_raider():
    body = [
        TIER(2),
        # lighter kit: mask up, oversized bright dry bag slung low, coral wrist bands
        BR("glass", "glass"), BOX([0, 0.99, -0.115], [0.16, 0.05, 0.03], 0.0),
        BR("acc"), CYL([0.0, 0.40, 0.30], [0.0, 0.86, 0.30], 0.12, 8, 0.0),
        BOX([0.235, 0.60, -0.22], [0.11, 0.11, 0.05], 0.0), BOX([-0.235, 0.50, 0.0], [0.11, 0.05, 0.11], 0.0),
        TIER(0)]
    return recipe("unit.pd.island_raider", "inf_rifle", {"n": 3, "kit": "rifle", "helmet": "wrap"},
                  ops_after=[squad_extras(3, 0.42, body)], meta={"role": "infantry", "icon": ICON_INF})


def harpoon_team():
    body = [
        TIER(2),
        BR("acc"), CYL([-0.19, 0.80, 0.27], [0.19, 0.80, 0.27], 0.09, 8, 0.0),
        # missile nose out of the tube, coral collar, four folded fins
        BR("sec"), FRU([0.20, 0.72, -0.62], [0.20, 0.72, -0.86], 0.052, 0.012, 6),
        BR("acc"), CYL([0.20, 0.72, -0.60], [0.20, 0.72, -0.64], 0.08, 6, 0.0),
        BR("sec"), BOX([0.20, 0.72, 0.16], [0.38, 0.012, 0.15], 0.0), BOX([0.20, 0.72, 0.16], [0.012, 0.3, 0.15], 0.0),
        TIER(0)]
    return recipe("unit.pd.harpoon_team", "inf_at", {"n": 2, "launcher": "tube", "helmet": "round"},
                  ops_after=[squad_extras(2, 0.44, body)], meta={"role": "anti_tank", "icon": ICON_INF})


def reef_technician():
    body = [
        TIER(2),
        # backpack with an articulated coral arm folded over the shoulder, welding lamp at the tip
        BR("acc"),
        CYL([0.06, 0.82, 0.30], [0.05, 1.22, 0.32], 0.026, 6, 0.0),
        CYL([0.05, 1.22, 0.32], [0.20, 1.24, 0.02], 0.022, 6, 0.0),
        BR("metal", "metal"), BOX([0.05, 1.22, 0.32], [0.07, 0.07, 0.07], 0.0),
        BR("dark"), BOX([0.20, 1.20, 0.0], [0.07, 0.08, 0.10], 0.0),
        BR("light", "emissive"), BOX([0.20, 1.19, -0.06], [0.04, 0.04, 0.02], 0.0),
        BR("acc"), BOX([0.0, 0.62, 0.36], [0.30, 0.06, 0.03], 0.0),
        TIER(0)]
    return recipe("unit.pd.reef_technician", "inf_support", {"n": 2, "gadget": "tool", "helmet": "round"},
                  ops_after=[squad_extras(2, 0.36, body)], meta={"role": "support", "icon": ICON_INF})


# ================================================================================================ tanks
def tide_roof(extra_ops=()):
    """Turret roof (inside the TURRET part): white commander cupola with coral ring, rear snorkel with coral cap, emblem, kit-bash part."""
    return [
        BR("acc"), CYL(["-turret_hw*0.38", "top_y-0.005", "turret_z+turret_hl*0.15"], ["-turret_hw*0.38", "top_y+0.03", "turret_z+turret_hl*0.15"], 0.215, 10, 0.0),
        BR("sec"), DOME(["-turret_hw*0.38", "top_y+0.03", "turret_z+turret_hl*0.15"], [0, 1, 0], 0.18, 0.09, 8, 2),
        BR("metal", "metal"),
        BOX([0, "top_y+0.2", "turret_z+turret_hl*0.55"], [0.09, 0.5, 0.09], 0.0),
        BOX([0, "top_y+0.44", "turret_z+turret_hl*0.55-0.07"], [0.10, 0.09, 0.2], 0.0),
        BR("acc"), BOX([0, "top_y+0.34", "turret_z+turret_hl*0.55"], [0.14, 0.04, 0.14], 0.0),
        *EMB("veh_tank"),
        *extra_ops,
    ]


def tide_hull_ops():
    """Common Tide hull dressing: bow loft, flotation sponsons, coral waterline band."""
    return [
        # boat-like prow: plan-view point in front of the glacis
        BR("base"),
        ["prism", [["-(hw-0.06)", 0.86, "-hl+0.03"], ["hw-0.06", 0.86, "-hl+0.03"], ["hw-0.06", 0.925, "-hl+0.03"], ["-(hw-0.06)", 0.925, "-hl+0.03"]],
         [["-0.16", 0.875, "-hl-0.40"], [0.16, 0.875, "-hl-0.40"], [0.16, 0.905, "-hl-0.40"], ["-0.16", 0.905, "-hl-0.40"]], 0.0],
        SPONSON("track_x+track_w*0.5-0.02", 0.72, 0.17, "hl-0.2", "-hl+0.7", rings=("hl*0.3", "-hl*0.3"), nose=0.42),
        *BAND("veh_tank"),
    ]


def tide_tank():
    slots = {"roof": tide_roof(TOP("veh_tank"))}
    return recipe("unit.pd.tide_tank", "veh_tank", {"len": 3.3, "roof": "snorkel"}, slots, tide_hull_ops(),
                  {"role": "tank", "icon": ICON})


def shinano_tank():
    """Tide hull + two-mode turret: a folding long-barrel siege module half-unfolded on the turret rear (hazard hinge), sensor ball."""
    hinge_y, hinge_z = "top_y+0.05", "turret_z+turret_hl*0.72"
    siege = PUSH([0, hinge_y, hinge_z], [-15, 0, 0],
                 BR("sec"), BOX([0, 0.03, 0.34], [0.30, 0.20, 0.62], 0.0),
                 BR("metal", "metal"), CYL([0, 0.03, 0.05], [0, 0.03, 2.3], 0.07, 6, 0.0),
                 BR("sec"), CYL([0, 0.03, 0.55], [0, 0.03, 1.8], 0.10, 8, 0.0),
                 BR("acc"), CYL([0, 0.03, 1.8], [0, 0.03, 1.86], 0.108, 8, 0.0))
    roof = tide_roof([
        BR("dark"), BOX([0, hinge_y, hinge_z], [0.62, 0.10, 0.22], 0.0),
        BR("acc"), FOR("k", 3, BOX(["-0.2+0.2*k", f"{hinge_y}+0.055", hinge_z], [0.09, 0.012, 0.2], 0.0)),
        siege,
        BR("metal", "metal"), CYL(["-turret_hw*0.55", "top_y", "turret_z-turret_hl*0.4"], ["-turret_hw*0.55", "top_y+0.1", "turret_z-turret_hl*0.4"], 0.04, 6, 0.0),
        BR("sec"), DOME(["-turret_hw*0.55", "top_y+0.08", "turret_z-turret_hl*0.4"], [0, 1, 0], 0.13, 0.13, 8, 3),
        BR("light", "emissive"), BOX(["-turret_hw*0.55", "top_y+0.2", "turret_z-turret_hl*0.4-0.12"], [0.1, 0.025, 0.02], 0.0),
    ])
    ops = tide_hull_ops() + [
        MIR(BR("dark", "metal"), TIER(1), BOX(["hw+0.012", 1.0, "-hl*0.2"], [0.02, 0.26, 0.3], 0.0),
            BR("metal", "metal"), BOX(["hw+0.03", 0.95, "-hl*0.2"], [0.03, 0.05, 0.05], 0.0), TIER(0)),
    ]
    return recipe("unit.pd.shinano_adaptive_tank", "veh_tank", {"len": 3.3, "roof": "snorkel"}, {"roof": roof}, ops,
                  {"role": "tank", "deploy": "pose", "icon": ICON})


# ================================================================================================ amphibious skimmers
def wake_skimmer():
    ops = [C("team_panel", center=[0, "body_top+0.02", -0.75], size=["hw*0.9", 0.02, 0.5]), *PAT("veh_amphib"), *EMB("veh_amphib"), *TOP("veh_amphib")]
    return recipe("unit.pd.wake_skimmer", "veh_amphib", {"float": "hover", "roof": "sensors", "deck": "none"}, None, ops,
                  {"role": "scout_transport", "icon": ICON})


def kancil_skimmer():
    ramp = PART("deploy", [0, 0.72, "-hl-0.13"], 0.143, 0, None,
                BR("sec"), BOX([0, 1.16, "-hl-0.13"], ["body_w-0.32", 0.9, 0.07], 0.0),
                BR("acc"), BOX([0, 0.75, "-hl-0.13"], ["body_w-0.32", 0.09, 0.09], 0.0),
                BR("dark"), BOX([0, 1.16, "-hl-0.17"], [0.14, 0.62, 0.02], 0.0),
                BR("acc"), BOX([0, 1.55, "-hl-0.13"], ["body_w-0.32", 0.06, 0.09], 0.0))
    rails = MIR(TIER(1), BR("acc"),
                BOX(["hw-0.10", "body_top+0.08", "(hl-0.3-hl+0.6)*0.5"], [0.05, 0.05, "hl*2-0.9"], 0.0),
                FOR("k", 3, BOX(["hw-0.10", "body_top+0.03", "-hl+0.6+(hl*2-0.9)*k/2"], [0.04, 0.1, 0.04], 0.0)),
                TIER(0))
    ops = [ramp, rails, C("team_panel", center=[0, "body_top+0.02", -0.75], size=["hw*0.9", 0.02, 0.5]), *PAT("veh_amphib"), *EMB("veh_amphib")]
    return recipe("unit.pd.kancil_landing_skimmer", "veh_amphib",
                  {"float": "hover", "roof": "rails", "deck": "none", "body_w": 2.1, "body_len": 3.9}, None, ops,
                  {"role": "landing_transport", "icon": ICON})


# ================================================================================================ Storm AA
def storm_aa():
    # sixth tube row on the elevating box and a sealed radome over the dish
    third_row = PART("barrel", [0, "deck_y", "tur_z"], 0.5, 0.12, ["py", "tur_z"],
                     PUSH([0, "py", "tur_z"], [22, 0, 0],
                          BR("dark"), BOX([0, 0.33, 0.0], [0.66, 0.34, 1.4], 0.0),
                          TIER(2),
                          FOR("i", 2,
                              BR("sec"), CYL(["(i-0.5)*0.27", 0.405, -0.575], ["(i-0.5)*0.27", 0.405, -0.825], 0.105, 6, 0.0),
                              BR("acc"), CYL(["(i-0.5)*0.27", 0.405, -0.815], ["(i-0.5)*0.27", 0.405, -0.865], 0.075, 6, 0.0))))
    radome = [BR("acc"), CYL([0, "deck_y+0.02", "rz"], [0, "deck_y+0.08", "rz"], 0.6, 10, 0.0),
              BR("sec"), DOME([0, "deck_y+0.08", "rz"], [0, 1, 0], 0.54, 0.62, 10, 3)]
    ops = [
        SPONSON("trk_x+trk_w*0.5-0.02", 0.72, 0.17, "hl-0.25", "-hl+0.65", rings=("hl*0.3", "-hl*0.3"), nose=0.4),
        third_row, *radome, C("team_panel", center=[-0.35, "deck_y+0.02", "-hl+0.5"], size=[0.6, 0.02, 0.6]), *BAND("veh_aa"), *EMB("veh_aa"), *TOP("veh_aa"),
    ]
    return recipe("unit.pd.storm_aa", "veh_aa", {"payload": "missile", "skirt": "none", "hull_wid": 1.86, "trk_x": 0.8, "trk_w": 0.34, "roof": "mast"}, None, ops,
                  {"role": "anti_air", "icon": ICON})


# ================================================================================================ howitzers (8x8 sealed wheeled hulls)
def wheeled_howitzer_ops():
    """Four cheap road wheels a side (WHEEL parts, 8-sided), white fenders and a dark sill; the archetype's tracks are shrunk out of sight."""
    ops = []
    for i in range(4):
        z = f"lerp(-hl+0.75,hl-0.75,{i}/3)"
        ops.append(MIR(PART("wheel", ["hw-0.02", 0.42, z], 0, 0.42, None,
                            BR("rubber", "rubber"), CYL(["hw-0.19", 0.42, z], ["hw+0.15", 0.42, z], 0.42, 8, 0.0),
                            TIER(2), BR("metal", "metal"), BOX(["hw+0.16", 0.42, z], [0.01, 0.2, 0.2], 0.0), TIER(1)),
                       TIER(2), BR("sec"), BOX(["hw+0.02", 0.9, z], [0.30, 0.05, 0.92], 0.0), TIER(0)))
    ops.append(MIR(TIER(2), BR("dark"), BOX(["hw-0.05", 0.62, 0.0], [0.30, 0.22, "hl*2-0.5"], 0.0), TIER(0)))
    return ops


def breaker_howitzer():
    ops = wheeled_howitzer_ops() + [C("team_panel", center=[0, "deck_y+0.02", "-hl*0.74"], size=["hw*1.0", 0.02, 0.4]),
                                    *BAND("veh_howitzer"), *EMB("veh_howitzer"), *TOP("veh_howitzer")]
    return recipe("unit.pd.breaker_howitzer", "veh_howitzer",
                  {"skirt": "none", "trk_w": 0.12, "trk_x": 0.6, "gun_len": 3.6, "muzzle": "sleeve", "deck": "drone_pad", "hull_wid": 2.0}, None, ops,
                  {"role": "howitzer", "icon": ICON})


def outrider_howitzer():
    # wheeled stabiliser feet (DEPLOY_Z, symmetric fold) and a permanent recon pod on the forward deck
    stab = []
    for s, prm in ((1, 0.857), (-1, 0.143)):
        # stowed pose: a fold-down leg hangs against the hull side (pivot at its top); on deploy it swings out to a horizontal outrigger
        stab.append(PART("deploy_z", [f"{s}*(hw+0.24)", 1.12, 0.0], prm, 0, None,
                         TIER(2), BR("metal", "metal"), BOX([f"{s}*(hw+0.24)", 0.86, 0.0], [0.08, 0.5, 0.16], 0.0),
                         BR("acc"), BOX([f"{s}*(hw+0.24)", 0.56, 0.0], [0.2, 0.08, 0.34], 0.0)))
    pod = [BR("metal", "metal"), BOX(["-hw*0.5", "deck_y+0.05", "-hl*0.62"], [0.06, 0.1, 0.36], 0.0),
           BR("sec"), CYL(["-hw*0.5", "deck_y+0.15", "-hl*0.62+0.36"], ["-hw*0.5", "deck_y+0.15", "-hl*0.62-0.34"], 0.12, 8, 0.0),
           FRU(["-hw*0.5", "deck_y+0.15", "-hl*0.62-0.34"], ["-hw*0.5", "deck_y+0.15", "-hl*0.62-0.5"], 0.12, 0.05, 8),
           BR("acc"), CYL(["-hw*0.5", "deck_y+0.15", "-hl*0.62-0.495"], ["-hw*0.5", "deck_y+0.15", "-hl*0.62-0.55"], 0.06, 6, 0.0)]
    return recipe("unit.pd.outrider_howitzer", "veh_howitzer",
                  {"skirt": "none", "trk_w": 0.12, "trk_x": 0.6, "gun_len": 4.8, "muzzle": "brake", "deck": "none", "hull_wid": 2.0},
                  None, wheeled_howitzer_ops() + stab + pod + [C("team_panel", center=[0, "deck_y+0.02", "-hl*0.74"], size=["hw*1.0", 0.02, 0.4]),
                                                    *BAND("veh_howitzer"), *EMB("veh_howitzer")],
                  {"role": "howitzer", "icon": ICON})


# ================================================================================================ Leviathan assault carrier
def leviathan():
    pads = [
        TIER(1), BR("acc"),
        FOR("i", 2, CYL(["0.55-1.1*i", "dy+0.03", "-hl+4.0"], ["0.55-1.1*i", "dy+0.06", "-hl+4.0"], 0.42, 10, 0.0)),
        BR("dark"), FOR("i", 2, CYL(["0.55-1.1*i", "dy+0.06", "-hl+4.0"], ["0.55-1.1*i", "dy+0.075", "-hl+4.0"], 0.32, 10, 0.0)),
        BR("sec"), FOR("i", 2, BOX(["0.55-1.1*i", "dy+0.12", "-hl+4.0"], [0.26, 0.08, 0.26], 0.0)),
        TIER(0)]
    cap = PART("turret", [0, "dy+0.62", "tz"], None, None, None,
               BR("acc"), CYL([0, "dy+1.26", "tz+0.05"], [0, "dy+1.31", "tz+0.05"], 0.5, 10, 0.0),
               BR("sec"), DOME([0, "dy+1.31", "tz+0.05"], [0, 1, 0], 0.42, 0.2, 10, 3))
    ops = [SPONSON("hw+0.06", 0.95, 0.30, "hl-1.5", "-hl+1.5", rings=("-hl*0.05", "hl*0.25"), nose=0.6),
           *pads, cap, *PAT("veh_hovercarrier"), *EMB("veh_hovercarrier"), *TOP("veh_hovercarrier")]
    return recipe("unit.pd.leviathan_assault_carrier", "veh_hovercarrier", {"skirt": "none", "hc_wid": 2.85, "muzzle": "sleeve", "gun_len": 2.6}, None, ops,
                  {"role": "assault_carrier", "icon": {"yaw": 150, "pitch": 26, "margin": 0.8}})


RECIPES = ["ranger_marine", "island_raider", "harpoon_team", "reef_technician", "tide_tank", "shinano_tank",
           "wake_skimmer", "kancil_skimmer", "storm_aa", "breaker_howitzer", "outrider_howitzer", "leviathan"]
