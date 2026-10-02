import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

WZ = "lerp((-hl+0.44)+0.34+0.22,(hl-0.42)-0.34-0.24,i/max(wheel_n-1,1))"

def hub_dots(skip_ends=False):
    if skip_ends:
        wz = "lerp((-hl+0.44)+0.34+0.22,(hl-0.42)-0.34-0.24,(i+1)/max(wheel_n-1,1))"
        n = "wheel_n-2"
    else:
        wz = WZ
        n = "wheel_n"
    return mirror([["tier", 2], ["brush", "acc", "emissive"], loop("i", n, [
        ["box", ["track_x+track_w*0.5+0.02", "wheel_r+0.07", wz], [0.05, 0.10, 0.10], 0.0]]), ["tier", 0]])

def push_bar():
    return [["brush", "dark", "metal"],
            ["box", [0, 0.66, "-hl-0.13"], ["hw*1.55", 0.13, 0.10], 0.0],
            loop("s", 2, [["box", ["(s*2-1)*hw*0.62", 0.66, "-hl-0.06"], [0.09, 0.09, 0.16], 0.0]])]

def cheek_plates(sec_first=True):
    return [loop("s", 2, [
        ["brush", "s == 0 ? 'base*0.82' : 'sec'"],
        ["box", ["(s*2-1)*(turret_hw*0.86)", "ty0+turret_h*0.52", "turret_z-0.12"], [0.07, "turret_h*0.66", 0.52], 0.01]])]

def barrel_collar(r_expr="barrel_r*1.55+0.018"):
    return {"part": {"kind": "barrel", "pivot": [0, "hull_top", "turret_z"], "param": 0.12, "extra": 0.32, "trunnion": ["gy", "fz"]},
            "do": [["brush", "acc", "emissive"], ["cyl", [0, "gy", "fz-0.14-0.15"], [0, "gy", "fz-0.14-0.20"], r_expr, 12, 0.0]]}

def buffalo():
    roof = cheek_plates() + [
        ["brush", "metal", "metal"],
        loop("s", 2, [["cyl", ["(s*2-1)*turret_hw*0.42", "top_y+0.07", "turret_z+0.42"], ["(s*2-1)*turret_hw*0.42", "top_y+0.07", "turret_z-0.34"], 0.022, 5, 0.0]]),
        ["box", [0, "top_y+0.07", "turret_z+0.42"], ["turret_hw*0.84", 0.04, 0.04], 0.0],
        ["brush", "dark"],
        ["box", [0, "top_y+0.09", "turret_z+turret_hl*0.72"], [0.62, 0.07, 0.12], 0.0],
        ["brush", "acc", "emissive"],
        ["box", [0, "top_y+0.09", "turret_z+turret_hl*0.72+0.062"], [0.5, 0.035, 0.012], 0.0],
        ["brush", "metal", "metal"],
        ["box", [0, "gy", "fz-0.02"], [0.74, "turret_h*0.78", 0.10], 0.012],
        ["brush", "dark"],
        ["box", [0, "gy+turret_h*0.28", "fz-0.09"], [0.66, 0.05, 0.05], 0.0],
        ["box", [0, "gy-turret_h*0.28", "fz-0.09"], [0.66, 0.05, 0.05], 0.0],
    ]
    deck = [
        ["brush", "rubber", "rubber"],
        ["cyl", ["-hw*0.38", "hull_top+0.34", "hl*0.62+0.02"], ["-hw*0.38+0.26", "hull_top+0.34", "hl*0.62+0.02"], 0.34, 12, 0.0],
        ["brush", "metal", "metal"],
        ["cyl", ["-hw*0.38+0.24", "hull_top+0.34", "hl*0.62+0.02"], ["-hw*0.38+0.28", "hull_top+0.34", "hl*0.62+0.02"], 0.2, 10, 0.0],
        ["brush", "acc", "emissive"],
        ["cyl", ["-hw*0.38+0.27", "hull_top+0.34", "hl*0.62+0.02"], ["-hw*0.38+0.30", "hull_top+0.34", "hl*0.62+0.02"], 0.06, 8, 0.0],
    ] + patch(["hw*0.30", "hull_top+0.07", "hl*0.62-0.18"], [0.62, 0.10, 0.62], "base*0.82") \
      + patch(["hw*0.34", "hull_top+0.17", "hl*0.62-0.14"], [0.5, 0.09, 0.5], "sec", 0) \
      + patch(["hw*0.30", "hull_top+0.10", "hl*0.62+0.42"], [0.5, 0.16, 0.34], "mix(dark,base,0.3)", 0)
    ops_after = push_bar() + [barrel_collar(), hub_dots()]
    recipe("unit.ae.buffalo_tank", "veh_tank", slots={"roof": roof, "deck": deck}, ops_after=ops_after)

def rhino():
    roof = cheek_plates() + [
        # two capacitor cylinders either side of the rail barrel, cyan rings
        ["brush", "sec", "metal"],
        loop("s", 2, [["cyl", ["(s*2-1)*0.30", "gy", "fz-0.02"], ["(s*2-1)*0.30", "gy", "fz-1.12"], 0.125, 8, 0.0]]),
        ["brush", "acc", "emissive"],
        loop("s", 2, [loop("k", 3, [["cyl", ["(s*2-1)*0.30", "gy", "fz-0.30-0.30*k"], ["(s*2-1)*0.30", "gy", "fz-0.36-0.30*k"], 0.14, 8, 0.0]])]),
        ["brush", "metal", "metal"],
        ["box", [0, "gy", "fz+0.01"], [0.86, "turret_h*0.8", 0.10], 0.012],
        # rangefinder box on the turret roof, two lenses
        ["brush", "sec"],
        ["box", ["-turret_hw*0.30", "top_y+0.15", "turret_z+turret_hl*0.30"], [0.60, 0.24, 0.28], 0.015],
        ["brush", "glass", "glass"],
        loop("s", 2, [["cyl", ["-turret_hw*0.30+(s*2-1)*0.2", "top_y+0.15", "turret_z+turret_hl*0.30-0.14"], ["-turret_hw*0.30+(s*2-1)*0.2", "top_y+0.15", "turret_z+turret_hl*0.30-0.19"], 0.065, 8, 0.0]]),
        ["brush", "dark"],
        ["box", ["turret_hw*0.45", "top_y+0.08", "turret_z+turret_hl*0.62"], [0.5, 0.07, 0.12], 0.0],
        ["brush", "acc", "emissive"],
        ["box", ["turret_hw*0.45", "top_y+0.08", "turret_z+turret_hl*0.62+0.062"], [0.4, 0.035, 0.012], 0.0],
    ]
    deck = [
        # capacitor bank: two horizontal cylinders across the rear deck, cyan rings
        ["brush", "sec", "metal"],
        loop("s", 2, [["cyl", ["-hw*0.62", "hull_top+0.20", "hl*0.60+(s*2-1)*0.24"], ["hw*0.62", "hull_top+0.20", "hl*0.60+(s*2-1)*0.24"], 0.17, 8, 0.0]]),
        ["brush", "acc", "emissive"],
        loop("s", 2, [["cyl", ["hw*0.2", "hull_top+0.20", "hl*0.60+(s*2-1)*0.24"], ["hw*0.2+0.05", "hull_top+0.20", "hl*0.60+(s*2-1)*0.24"], 0.185, 8, 0.0]]),
    ] + patch(["hw*0.1", "hull_top+0.02", "hl*0.60-0.02"], [0.6, 0.04, 0.9], "base*0.82", 0)
    # barrel: cyan capacitor rings + long recoil sleeve above the barrel
    barrel = {"part": {"kind": "barrel", "pivot": [0, "hull_top", "turret_z"], "param": 0.12, "extra": 0.32, "trunnion": ["gy", "fz"]},
              "do": [["brush", "acc", "emissive"],
                     loop("k", 4, [["cyl", [0, "gy", "fz-0.14-0.15-barrel_len*(0.16+0.19*k)"], [0, "gy", "fz-0.14-0.15-barrel_len*(0.16+0.19*k)-0.05"], "barrel_r*1.6", 8, 0.0]]),
                     ["brush", "metal", "metal"],
                     ["cyl", [0, "gy+0.12", "fz-0.14+0.1"], [0, "gy+0.12", "fz-0.14-0.9"], 0.045, 6, 0.0]]}
    ops_after = push_bar() + [barrel, hub_dots(True)]
    recipe("unit.ae.rhino_rail_tank", "veh_tank",
           params={"len": 3.85, "hull_w": 2.08, "turret_hw": 0.84, "turret_hl": 0.92, "barrel_len": 3.1, "barrel_r": 0.062},
           slots={"roof": roof, "deck": deck}, ops_after=ops_after)

if __name__ == "__main__":
    buffalo(); rhino()
