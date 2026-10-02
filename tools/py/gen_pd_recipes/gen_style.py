"""Builds game/data/recipes/styles/pd.json (faction style + three subfaction overlays)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pdlib import *  # noqa

# ------------------------------------------------------------------------------------------ palette (render spec 5.8.4 + art 5.3)
PALETTE = {  # art_direction 5.3.1 (style.json palette.pd) + the two structure/plate extras
    "acc": "#ff6f5b", "base": "#1791be", "concrete": "#6f8797", "dark": "#0f3a63", "glass": "#173a56",
    "light": "#f4fbff", "metal": "#3e4548", "plate": "#0c1822", "rubber": "#151515", "sec": "#f1f4f6",
}

KIT = {
    "barrel_len": 1.9, "barrel_r": 0.07, "deck": "drone_pad", "glacis": 1.1, "helmet": "round", "hull_top": 1.06,
    "hull_w": 1.72, "len": 3.6, "muzzle": "sleeve", "roof": "cupola", "skirt": "none", "track_w": 0.32,
    "track_x": 0.78, "turret_h": 0.34, "turret_hl": 0.72, "turret_hw": 0.66, "turret_n": 10, "turret_rot": 18.0,
    "turret_shift": 0.0, "turret_top": 0.74, "wheel_n": 4, "wheel_r": 0.27,
}

MATERIAL = {"dirt": 0.2, "dirt_color": "#2c3a44", "emissive": 2.5, "panel": 0.6, "wear": 0.3, "wear_color": "#e4eef4"}


# ------------------------------------------------------------------------------------------ band patterns (both flanks; boxes carry no bevel: 12 tris each)
def band_solid(tier=1):
    return [MIR(TIER(tier), BR("acc"), BOX(["kb_x", "kb_y", "(kb_z0+kb_z1)*0.5"], [0.03, "kb_h", "kb_z1-kb_z0"], 0.0))]


def band_wave():
    n = "clamp(round((kb_z1-kb_z0)/0.32),4,8)"
    return [LET(kb_n=n),
            MIR(TIER(2), BR("acc"), FOR("i", "kb_n", BOX(
                ["kb_x", "kb_y+0.05*sin((i+0.5)*(kb_z1-kb_z0)/kb_n/0.5*TAU)", "kb_z0+(kb_z1-kb_z0)*(i+0.5)/kb_n"],
                [0.03, "kb_h*0.72", "(kb_z1-kb_z0)/kb_n+0.03"], 0.0)))]


def band_diag():
    n = "clamp(round((kb_z1-kb_z0)/0.42),4,8)"
    return [LET(kb_n=n),
            MIR(TIER(2), BR("acc"), FOR("i", "kb_n", PUSH(
                ["kb_x", "kb_y", "kb_z0+(kb_z1-kb_z0)*(i+0.5)/kb_n"], [38, 0, 0],
                BOX([0, 0, 0], [0.03, "kb_h*1.7", 0.06], 0.0))))]


def band_pin():
    return [MIR(TIER(2), BR("acc"),
                BOX(["kb_x", "kb_y+0.03", "(kb_z0+kb_z1)*0.5"], [0.03, 0.03, "kb_z1-kb_z0"], 0.0),
                BOX(["kb_x", "kb_y-0.03", "(kb_z0+kb_z1)*0.5"], [0.03, 0.03, "kb_z1-kb_z0"], 0.0))]


# ------------------------------------------------------------------------------------------ emblem (ring) + sub pips (1 Australia, 2 Indonesia, 3 Japan)
def emblem(pips):
    ops = [TIER(2), BR("acc"),
           CYL(["ke_x", "ke_y", "ke_z"], ["ke_x+0.016", "ke_y", "ke_z"], "ke_r", 8, 0.0),
           BR("dark"),
           CYL(["ke_x+0.008", "ke_y", "ke_z"], ["ke_x+0.022", "ke_y", "ke_z"], "ke_r*0.62", 8, 0.0)]
    if pips:
        ops.append(BR("sec"))
        for k in range(pips):
            ops.append(BOX(["ke_x+0.01", "ke_y-ke_r*1.0", f"ke_z+ke_r*(1.1+{0.42*k})"], [0.02, "ke_r*0.3", "ke_r*0.3"], 0.0))
    return [MIR(*ops)]


# ------------------------------------------------------------------------------------------ kit-bash parts (kit_parts of the art bible), each about 100 tris
def top_recon_pod():  # australia: recon_pod
    y = "kt_y+0.11*kt_r"
    return [BR("metal", "metal"), BOX(["kt_x", "kt_y+0.04*kt_r", "kt_z"], ["0.06*kt_r", "0.09*kt_r", "0.30*kt_r"], 0.0),
            BR("sec"), CYL(["kt_x", y, "kt_z+0.3*kt_r"], ["kt_x", y, "kt_z-0.28*kt_r"], "0.1*kt_r", 8, 0.0),
            FRU(["kt_x", y, "kt_z-0.28*kt_r"], ["kt_x", y, "kt_z-0.42*kt_r"], "0.1*kt_r", "0.05*kt_r", 8),
            BR("acc"), CYL(["kt_x", y, "kt_z-0.415*kt_r"], ["kt_x", y, "kt_z-0.46*kt_r"], "0.05*kt_r", 6, 0.0)]


def top_grab_rails():  # indonesia: grab_rails
    return [MIR(TIER(2), BR("acc"),
                BOX(["kt_r*0.6", "kt_y+0.2", "kt_z"], [0.045, 0.045, "kt_r*1.1"], 0.0),
                BOX(["kt_r*0.6", "kt_y+0.1", "kt_z-0.55*kt_r"], [0.04, 0.2, 0.04], 0.0),
                BOX(["kt_r*0.6", "kt_y+0.1", "kt_z+0.55*kt_r"], [0.04, 0.2, 0.04], 0.0))]


def top_sensor_ball():  # japan: sensor_ball on a short mast + drone-bay hatch light
    return [BR("metal", "metal"), CYL(["kt_x", "kt_y", "kt_z"], ["kt_x", "kt_y+0.16*kt_r", "kt_z"], "0.04*kt_r", 6, 0.0),
            BR("sec"), DOME(["kt_x", "kt_y+0.12*kt_r", "kt_z"], [0, 1, 0], "0.17*kt_r", "0.17*kt_r", 8, 3),
            DOME(["kt_x", "kt_y+0.12*kt_r", "kt_z"], [0, -1, 0], "0.17*kt_r", "0.15*kt_r", 8, 2),
            BR("light", "emissive"), BOX(["kt_x", "kt_y+0.16*kt_r", "kt_z-0.15*kt_r"], ["0.16*kt_r", "0.03*kt_r", 0.02], 0.0)]


# ------------------------------------------------------------------------------------------ structure dialect: front apron (quay rail, bollards, life ring)
def quay_front():
    return [IF("fw*fh>1", [
        LET(qz="fh*1.5-0.2", qx0="-(fw*1.5-0.45)", qx1="fw*1.5-0.45", qn="max(floor((fw*3-0.9)/0.95),2)"),
        TIER(1), BR("acc"),
        FOR("i", "qn+1",
            LET(px="qx0+(qx1-qx0)*i/qn"),
            IF("abs(px-door_cx)>1.7", [BOX(["px", 0.32, "qz"], [0.05, 0.64, 0.05], 0.0)])),
        IF("door_cx-1.6-qx0>0.4", [BOX(["(qx0+door_cx-1.6)*0.5", 0.62, "qz"], ["door_cx-1.6-qx0", 0.04, 0.04], 0.0)]),
        IF("qx1-door_cx-1.6>0.4", [BOX(["(door_cx+1.6+qx1)*0.5", 0.62, "qz"], ["qx1-door_cx-1.6", 0.04, 0.04], 0.0)]),
        TIER(0)])]


def quay_extra(pips=0):
    """Life ring, bollards and the painted faction ring on the quay (sub pips 1-3 on the ring for the three rosters)."""
    ops = [
        TIER(1),
        BR("sec"), CYL(["-(fw*1.5-0.62)", 0.42, "fh*1.5-0.24"], ["-(fw*1.5-0.62)", 0.42, "fh*1.5-0.19"], 0.17, 8, 0.0),
        BR("acc"), CYL(["-(fw*1.5-0.62)", 0.42, "fh*1.5-0.19"], ["-(fw*1.5-0.62)", 0.42, "fh*1.5-0.165"], 0.125, 8, 0.0),
        BR("metal", "metal"),
        MIR(CYL(["fw*1.5-0.3", 0.0, "fh*1.5-0.62"], ["fw*1.5-0.3", 0.3, "fh*1.5-0.62"], 0.08, 6, 0.0)),
        TIER(2),
        BR("acc"), CYL(["fw*1.5-1.25", 0.16, "fh*1.5-0.6"], ["fw*1.5-1.25", 0.172, "fh*1.5-0.6"], 0.34, 6, 0.0),
        BR("dark"), CYL(["fw*1.5-1.25", 0.168, "fh*1.5-0.6"], ["fw*1.5-1.25", 0.178, "fh*1.5-0.6"], 0.2, 6, 0.0),
    ]
    if pips:
        ops.append(BR("sec"))
        for k in range(pips):
            ops.append(BOX([f"fw*1.5-1.25+{0.16*(k-(pips-1)/2)}", 0.18, "fh*1.5-0.6"], [0.09, 0.012, 0.09], 0.0))
    ops.append(TIER(0))
    return [IF("fw*fh>1", ops)]


# family -> anchors. Every expression uses only archetype defaults + hl/hw/ty0/top_y/gy/fz (style slots are validated stand-alone).
ANCH = {
    "veh_tank": {"band": ("hw+0.004", 0.98, "-hl+glacis+0.05", "hl-0.15", 0.1),
                 "emb": ("turret_hw*0.945", "ty0+turret_h*0.4", "turret_z+turret_hl*0.34", 0.16),
                 "top": ("-(turret_hw+0.03)", "ty0+turret_h*0.35", "turret_z-0.05", 0.9)},
    "veh_amphib": {"pat": ("hw+0.004", 0.97, "-hl+0.5", "hl-0.3", 0.1),
                   "emb": ("hw-0.10", 1.32, 0.35, 0.15),
                   "top": ("-hw*0.45", "body_top", "hl*0.3", 0.7)},
    "veh_aa": {"band": ("hw+0.004", 0.96, "-hl+0.5", "hl-0.5", 0.1),
               "emb": ("hw+0.004", "deck_y-0.06", "-hl*0.15", 0.1),
               "top": ("-hw*0.55", "deck_y", "-hl+0.6", 0.6)},
    "veh_howitzer": {"band": ("hw+0.004", 0.98, "-hl+0.7", "hl-0.3", 0.1),
                     "emb": ("hw+0.004", "deck_y-0.08", "-hl*0.55", 0.11),
                     "top": ("hw*0.55", "deck_y", "-hl*0.6", 0.6)},
    "veh_hovercarrier": {"pat": ("hw+0.004", 1.0, "-hl+1.4", "hl-1.5", 0.12),
                         "emb": ("hw-0.2", 1.75, "hl-1.1", 0.2),
                         "top": ("-hw*0.5", "1.3", "-hl*0.05", 0.9)},
    "air_jet": {"band": (0.385, 0.75, 0.2, 1.6, 0.09),
                "emb": (0.36, 0.86, -0.15, 0.13),
                "top": (0, 1.06, 0.9, 0.7)},
    "air_heli": {"band": (0.415, 1.05, 0.3, 1.3, 0.1),
                 "emb": (0.42, 1.0, 0.15, 0.14),
                 "top": (0, 1.72, 0.9, 0.7)},
    "ship_patrol": {"pat": ("sp_beam*0.5+0.004", "0.62", "-hl*0.5", "hl-0.4", 0.1),
                    "emb": ("sp_beam*0.5-0.33", "0.62+0.4", "hl*0.05+0.15", 0.14),
                    "top": (0, "0.62+0.74", "hl*0.05+0.5", 0.6)},
    "ship_escort": {"pat": ("se_beam*0.5+0.004", "1.0", "-hl+1.2", "hl-1.0", 0.13),
                    "emb": ("se_beam*0.5-0.05", "1.35", "-hl*0.12+0.9", 0.18),
                    "top": (0, "0.9+0.32", "hl-2.2", 0.8)},
    "ship_carrier": {"pat": ("sc_beam*0.5+0.004", "1.0", "-hl+1.2", "hl-1.0", 0.14),
                     "emb": ("sc_beam*0.5-0.05", "1.55", "-hl*0.05+1.1", 0.22),
                     "top": ("-sc_beam*0.5+0.7", "1.55", "hl*0.2", 0.9)},
}


def anchor_lets(prefix, a):
    x, y, z0, z1, h = a
    return LET(**{prefix + "_x": x, prefix + "_y": y, prefix + "_z0": z0, prefix + "_z1": z1, prefix + "_h": h})


def build_slots(sub):
    """sub in {None, 'australia', 'indonesia', 'japan'}: slot table for that style layer."""
    out = {}
    pattern = {None: None, "australia": band_wave, "indonesia": band_diag, "japan": band_pin}[sub]
    pips = {None: 0, "australia": 1, "indonesia": 2, "japan": 3}[sub]
    top = {None: None, "australia": top_recon_pod, "indonesia": top_grab_rails, "japan": top_sensor_ball}[sub]
    for fam, an in ANCH.items():
        if "band" in an:
            x, y, z0, z1, h = an["band"]
            out["band_" + fam] = [anchor_lets("kb", an["band"])] + (pattern() if pattern else band_solid())
        if "pat" in an:
            out["pat_" + fam] = ([anchor_lets("kb", an["pat"])] + pattern()) if pattern else []
        if "emb" in an:
            x, y, z, r = an["emb"]
            out["emb_" + fam] = [LET(ke_x=x, ke_y=y, ke_z=z, ke_r=r)] + emblem(pips)
        if "top" in an:
            x, y, z, r = an["top"]
            out["top_" + fam] = ([LET(kt_x=x, kt_y=y, kt_z=z, kt_r=r)] + top()) if top else []
    return out


def build_style():
    slots = build_slots(None)
    slots["front"] = quay_front()
    slots["extra"] = quay_extra(0)
    styles = {
        "pd": {"emblem": "ring", "kit": KIT, "material": MATERIAL, "palette": PALETTE, "slots": slots, "team_plate": "band"},
        "pd.australia": {"extends": "pd", "emblem": "ring", "palette": {"acc": "#d94e3e"}, "slots": dict(build_slots("australia"), extra=quay_extra(1))},
        "pd.indonesia": {"extends": "pd", "emblem": "ring", "palette": {"acc": "#ff6c7f"}, "slots": dict(build_slots("indonesia"), extra=quay_extra(2))},
        "pd.japan": {"extends": "pd", "emblem": "ring", "palette": {"acc": "#ef7d3d"}, "slots": dict(build_slots("japan"), extra=quay_extra(3))},
    }
    return {"schema": "meridian.styles/1", "styles": styles}


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "styles"), exist_ok=True)
    dump(os.path.join(ROOT, "styles", "pd.json"), build_style())
    print("styles/pd.json written")
