import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

AZ = "lerp((-hl+0.44)+0.3+0.22,(hl-0.4)-0.3-0.24,(i+1)/6)"

def aa_hub_dots():
    return mirror([["tier", 2], ["brush", "acc", "emissive"], loop("i", 4, [
        ["box", ["trk_x+trk_w*0.5+0.02", 0.32, AZ], [0.05, 0.10, 0.10], 0.0]]), ["tier", 0]])

def aa_common():
    return [
        ["tier", 2], ["brush", "dark", "metal"],
        ["box", [0, 0.62, "-hl-0.12"], ["hw*1.55", 0.13, 0.10], 0.0],
        loop("s", 2, [["box", ["(s*2-1)*hw*0.62", 0.62, "-hl-0.05"], [0.09, 0.09, 0.16], 0.0]]),
        ["tier", 0],
        aa_hub_dots(),
        # quad-tube module: cyan lock-collar frame around the pack (moves with the elevating launcher)
        part("barrel", [push([0, "py", "tur_z"], [
            ["brush", "acc", "emissive"],
            ["box", [0, 0.335, -0.22], [0.72, 0.04, 0.06], 0.0],
            ["box", [0, -0.335, -0.22], [0.72, 0.04, 0.06], 0.0],
            ["tier", 2],
            ["box", [0.335, 0, -0.22], [0.04, 0.7, 0.06], 0.0],
            ["box", [-0.335, 0, -0.22], [0.04, 0.7, 0.06], 0.0],
            ["tier", 0],
            ["tier", 2], ["brush", "metal", "metal"],
            ["box", [0, 0, 0.48], [0.5, 0.5, 0.1], 0.0], ["tier", 0],
        ], [22, 0, 0])], pivot=[0, "deck_y", "tur_z"], param=0.5, extra=0.12, trunnion=["py", "tur_z"]),
    ]

def aa_turret_extras(lagos=False):
    do = [
        # side ammo boxes bolted to the turret cheeks, mismatched tones
        ["brush", "base*0.82"],
        ["box", ["tur_hw+0.14", "ty0+0.22", "tur_z+0.05"], [0.24, 0.38, 0.62], 0.0],
        ["brush", "sec"],
    ] + ([] if lagos else [
        ["box", ["-tur_hw-0.14", "ty0+0.22", "tur_z+0.05"], [0.24, 0.38, 0.62], 0.0],
    ]) + [
        ["tier", 2], ["brush", "dark"],
        ["box", ["tur_hw+0.14", "ty0+0.42", "tur_z+0.05"], [0.26, 0.04, 0.3], 0.0], ["tier", 0],
        ["tier", 2], ["brush", "metal", "metal"],
        ["cyl", ["tur_hw+0.14", "ty0+0.46", "tur_z+0.05"], ["tur_hw+0.14", "ty0+0.49", "tur_z+0.05"], 0.03, 4, 0.0],
        ["tier", 0],
    ]
    if lagos:
        do += [
            # drone bay on the left turret cheek: docked repair drone in a cyan-lit cradle
            ["tier", 2], ["brush", "sec"],
            ["box", ["-tur_hw-0.24", "ty0+0.12", "tur_z+0.05"], [0.56, 0.26, 0.66], 0.0],
            ["brush", "acc", "emissive"],
            loop("s", 2, [loop("t", 2, [["box", ["-tur_hw-0.24+(s*2-1)*0.24", "ty0+0.27", "tur_z+0.05+(t*2-1)*0.27"], [0.05, 0.05, 0.05], 0.0]])]),
            ["tier", 0],
            # the drone itself: body, X frame, four rotor pads (static while docked; LOD0 only, 0.4 m is invisible at the RTS camera)
            ["tier", 2], ["brush", "base*0.82"],
            ["box", ["-tur_hw-0.24", "ty0+0.36", "tur_z+0.05"], [0.22, 0.10, 0.30], 0.0],
            ["brush", "metal", "metal"],
            ["box", ["-tur_hw-0.24", "ty0+0.40", "tur_z+0.05"], [0.56, 0.03, 0.05], 0.0],
            ["box", ["-tur_hw-0.24", "ty0+0.40", "tur_z+0.05"], [0.05, 0.03, 0.56], 0.0],
            ["brush", "dark"],
            loop("s", 2, [loop("t", 2, [["box", ["-tur_hw-0.24+(s*2-1)*0.26", "ty0+0.43", "tur_z+0.05+(t*2-1)*0.26"], [0.16, 0.02, 0.16], 0.0]])]),
            ["tier", 0],
            # comm mast, guy wires and beacon
            ["brush", "metal", "metal"],
            ["box", ["tur_hw*0.55", "top_y+0.78", "tur_z+tur_hl*0.55"], [0.07, 1.46, 0.07], 0.0],
            ["tier", 2],
            ["cyl", ["tur_hw*0.55", "top_y+1.1", "tur_z+tur_hl*0.55"], ["tur_hw*0.55+0.5", "top_y+0.05", "tur_z+tur_hl*0.55+0.25"], 0.008, 4, 0.0, False],
            ["cyl", ["tur_hw*0.55", "top_y+1.1", "tur_z+tur_hl*0.55"], ["tur_hw*0.55-0.5", "top_y+0.05", "tur_z+tur_hl*0.55+0.25"], 0.008, 4, 0.0, False],
            ["tier", 0],
            part("blink", [["brush", "acc", "emissive"], ["box", ["tur_hw*0.55", "top_y+1.55", "tur_z+tur_hl*0.55"], [0.13, 0.13, 0.13], 0.0]], param=0.5),
        ]
    return [part("turret", do, pivot=[0, "deck_y", "tur_z"])]

def weaver():
    recipe("unit.ae.weaver_aa", "veh_aa", ops_after=aa_common() + aa_turret_extras(False))

def lagos():
    recipe("unit.ae.lagos_drone_guard", "veh_aa", ops_after=aa_common() + aa_turret_extras(True))

if __name__ == "__main__":
    weaver(); lagos()
