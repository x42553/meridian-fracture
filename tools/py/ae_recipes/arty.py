import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

HZ = "lerp((-hl+0.44)+0.32+0.22,(hl-0.42)-0.32-0.24,(i+1)/5)"

def hz_hub_dots():
    return mirror([["tier", 2], ["brush", "acc", "emissive"], loop("i", 3, [
        ["box", ["trk_x+trk_w*0.5+0.02", 0.35, HZ], [0.05, 0.10, 0.10], 0.0]]), ["tier", 0]])

def crane_arm():
    """repair / salvage crane on the rear deck: post, slewing jib, cable and hook (asymmetric, right side)."""
    return [
        ["brush", "dark", "metal"],
        ["cyl", ["hw*0.62", "deck_y", "hl-0.55"], ["hw*0.62", "deck_y+0.95", "hl-0.55"], 0.07, 6, 0.0],
        ["brush", "sec"],
        ["box", ["hw*0.62", "deck_y+0.14", "hl-0.55"], [0.26, 0.28, 0.26], 0.0],
        push(["hw*0.62", "deck_y+0.95", "hl-0.55"], [
            ["brush", "base*0.82"],
            ["box", [0, 0.06, -0.45], [0.09, 0.09, 1.1], 0.0],
            ["brush", "metal", "metal"],
            ["cyl", [0, 0.02, -1.0], [0, -0.50, -1.0], 0.012, 4, 0.0, False],
            ["box", [0, -0.54, -1.0], [0.08, 0.06, 0.05], 0.0],
            ["brush", "acc", "emissive"],
            ["box", [0, 0.11, 0.05], [0.07, 0.03, 0.07], 0.0],
        ], [-18, 25, 0]),
    ]

def welds(c_expr_list):
    return []

def forge():
    ops_after = [
        ["brush", "dark", "metal"],
        ["box", [0, 0.68, "-hl-0.12"], ["hw*1.5", 0.12, 0.10], 0.0],
        loop("s", 2, [["box", ["(s*2-1)*hw*0.6", 0.68, "-hl-0.05"], [0.09, 0.09, 0.14], 0.0]]),
        hz_hub_dots(),
        # welded casemate: cross-seam straps and a bolted plate on the roof
        part("turret", [
            ["brush", "dark"],
            ["box", [0, "deck_y+0.70", "tz+0.86"], ["hw*1.5", 0.07, 0.07], 0.0],
            ["box", [0, "deck_y+0.42", "tz+0.86"], ["hw*1.5", 0.07, 0.07], 0.0],
            ["box", ["hw*0.86", "deck_y+0.56", "tz+0.30"], [0.06, 0.6, 0.06], 0.0],
            ["box", ["-hw*0.86", "deck_y+0.56", "tz+0.30"], [0.06, 0.6, 0.06], 0.0],
        ] + patch(["-hw*0.30", "deck_y+1.05", "tz+0.05"], [0.55, 0.04, 0.5], "sec", 2, "z") + [
            # repair crane arm on the rear of the casemate roof (swings with the turret): mast, jib, cable, hook, cyan lamp
            ["brush", "dark", "metal"],
            ["cyl", ["hw*0.55", "deck_y+0.95", "tz+0.62"], ["hw*0.55", "deck_y+1.95", "tz+0.62"], 0.08, 6, 0.0],
            ["brush", "sec"], ["box", ["hw*0.55", "deck_y+1.02", "tz+0.62"], [0.30, 0.16, 0.30], 0.0],
            push(["hw*0.55", "deck_y+1.95", "tz+0.62"], [
                ["brush", "base*0.82"],
                ["box", [0, 0.05, "1.5*-0.45"], [0.11, 0.11, 1.5], 0.0],
                ["box", [0, 0.16, 0.12], [0.18, 0.16, 0.26], 0.0],
                ["brush", "metal", "metal"],
                ["cyl", [0, 0.0, "1.5*-0.9"], [0, -0.75, "1.5*-0.9"], 0.014, 4, 0.0, False],
                ["box", [0, -0.79, "1.5*-0.9"], [0.10, 0.08, 0.07], 0.0],
                ["brush", "acc", "emissive"], ["box", [0, 0.12, "1.5*-1.0"], [0.08, 0.08, 0.08], 0.0],
            ], [12, 180, 0]),
        ], pivot=[0, "deck_y", "tz"]),
    ]
    recipe("unit.ae.forge_howitzer", "veh_howitzer",
           params={"turret_n": 4, "turret_rot": 45.0, "gun_len": 2.5, "gun_r": 0.145, "muzzle": "plain"},
           ops_after=ops_after)

def protea():
    barrel = part("barrel", [
        # swappable canister shroud on the barrel + long recoil sleeve; cyan module collar at the breech
        ["brush", "sec", "metal"],
        ["cyl", [0, "gy", "gz-0.14-gun_len*0.55"], [0, "gy", "gz-0.14-gun_len*0.55-0.62"], "gun_r*2.5", 10, 0.01],
        ["brush", "acc", "emissive"],
        ["cyl", [0, "gy", "gz-0.14-gun_len*0.55+0.02"], [0, "gy", "gz-0.14-gun_len*0.55-0.03"], "gun_r*2.6", 10, 0.0],
        ["cyl", [0, "gy", "gz-0.14-0.12"], [0, "gy", "gz-0.14-0.18"], "gun_r*1.9", 10, 0.0],
        ["brush", "metal", "metal"],
        ["cyl", [0, "gy+gun_r*1.9", "gz-0.2"], [0, "gy+gun_r*1.9", "gz-1.1"], 0.05, 6, 0.0],
    ], pivot=[0, "deck_y", "tz"], param=0.37, extra=0.6, trunnion=["gy", "gz+0.14"])
    ops_after = [
        ["brush", "dark", "metal"],
        ["box", [0, 0.68, "-hl-0.12"], ["hw*1.5", 0.12, 0.10], 0.0],
        loop("s", 2, [["box", ["(s*2-1)*hw*0.6", 0.68, "-hl-0.05"], [0.09, 0.09, 0.14], 0.0]]),
        hz_hub_dots(),
        barrel,
        # turntable ring under the casemate + rangefinder box on the roof
        part("turret", [
            ["brush", "acc", "emissive"],
            ["cyl", [0, "deck_y+0.02", "tz"], [0, "deck_y+0.055", "tz"], "hw*0.98", 16, 0.0],
            ["brush", "sec"],
            ["box", ["hw*0.32", "deck_y+1.13", "tz+0.05"], [0.58, 0.22, 0.26], 0.015],
            ["brush", "glass", "glass"],
            loop("s", 2, [["cyl", ["hw*0.32+(s*2-1)*0.2", "deck_y+1.13", "tz-0.08"], ["hw*0.32+(s*2-1)*0.2", "deck_y+1.13", "tz-0.13"], 0.06, 8, 0.0]]),
        ], pivot=[0, "deck_y", "tz"]),
    ]
    recipe("unit.ae.protea_gun_carrier", "veh_howitzer",
           params={"turret_n": 12, "turret_rot": 15.0, "gun_len": 3.3, "gun_r": 0.095, "muzzle": "plain"},
           ops_after=ops_after)

def kiln():
    ops_after = [
        # broad plough / shovel on the front (-z): sloped blade, hazard chevrons, hydraulic rams
        ["brush", "dark", "metal"],
        push([0, 0.58, "-hl-0.12"], [
            ["tbox", [0, 0.46, 0], ["hull_wid*1.18", 0.42], ["hull_wid*1.18", 0.14], 1.05, [0, -0.28], 0.03],
            ["brush", "base*1.5"],
            loop("k", 6, [["box", ["hull_wid*1.18*(k-2.5)/6", 1.09, -0.36], ["hull_wid*1.18/6*0.5", 0.05, 0.05], 0.0]]),
            ["brush", "metal", "metal"],
            loop("s", 2, [["cyl", ["(s*2-1)*hw*0.7", 0.2, 0.55], ["(s*2-1)*hw*0.7", 0.6, -0.2], 0.07, 6, 0.0]]),
        ]),
        # furnace muzzle: dark bore ring with hazard-amber glow
        part("barrel", [
            ["brush", "base*1.6", "emissive"],
            ["cyl", [0, "gy", "gz-0.14-gun_len+0.06"], [0, "gy", "gz-0.14-gun_len-0.02"], 0.2, 10, 0.0],
            ["brush", "dark", "metal"],
            ["cyl", [0, "gy", "gz-0.14-gun_len+0.55"], [0, "gy", "gz-0.14-gun_len+0.42"], 0.29, 10, 0.0],
        ], pivot=[0, "deck_y", "tur_z"], param=0.25, extra=0.5, trunnion=["gy", "gz+0.14"]),
    ]
    recipe("unit.ae.kiln_assault_crawler", "veh_siege", params={"weapon": "siege", "muzzle": "bore", "gun_len": 1.9, "gun_r": 0.21}, ops_after=ops_after)

if __name__ == "__main__":
    forge(); protea(); kiln()
