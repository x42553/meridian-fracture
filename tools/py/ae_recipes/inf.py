import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def per_soldier(ops, r=0.42, cond=None):
    body = [
        {"let": {"a0": "(n) == 2 ? PI*0.5 : 0",
                 "fx": "((n) == 1 ? 0 : sin(i*TAU/(n) + a0)*%s) + (rnd(i)-0.5)*0.05" % r,
                 "fz": "((n) == 1 ? 0 : -cos(i*TAU/(n) + a0)*%s) + (rnd(i+9)-0.5)*0.05" % r,
                 "ph": "(i + 0.5)/(n)"}},
        ["member", "i", "n"],
        {"part": {"kind": "body_bob", "pivot": [0, 0, 0], "param": "ph", "extra": 0},
         "do": [{"push": {"pos": ["fx", 0, "fz"]}, "do": ops}]},
        ["member", 0, 0],
    ]
    if cond:
        body = [body[0], {"if": cond, "then": body[1:]}]
    return {"for": "i", "n": "n", "do": body}

def belt_lamp():
    return [["tier", 2], ["brush", "acc", "emissive"], ["box", [0, 0.505, -0.13], [0.08, 0.045, 0.02], 0.0], ["tier", 0]]

def chest_plate():
    return [["tier", 1], ["brush", "sec"], ["box", [0, 0.70, -0.118], [0.28, 0.20, 0.03], 0.0], ["tier", 0]]

def union_guard():
    ops = [per_soldier(chest_plate() + belt_lamp(), 0.42)]
    recipe("unit.ae.union_guard", "inf_rifle", params={"helmet": "angular"}, ops_after=ops)

def civic_rifle():
    pucks = [["tier", 2], ["brush", "acc", "emissive"],
             ["box", [-0.06, 0.74, -0.125], [0.11, 0.11, 0.025], 0.0],
             ["box", [0.07, 0.56, -0.125], [0.11, 0.11, 0.025], 0.0], ["tier", 0]]
    ops = [per_soldier(pucks, 0.42)]
    recipe("unit.ae.civic_rifle_team", "inf_rifle", params={"helmet": "angular"}, ops_after=ops)

def pike():
    launcher = [["tier", 2], ["brush", "acc", "emissive"],
                ["cyl", [0.20, 0.72, -0.09], [0.20, 0.72, -0.15], 0.095, 8, 0.0],
                ["brush", "metal", "metal"], ["box", [0.20, 0.79, 0.02], [0.10, 0.03, 0.30], 0.0], ["tier", 0]]
    ops = [per_soldier(launcher, 0.44, "i < 2"), per_soldier(chest_plate() + belt_lamp(), 0.44, "i >= 2")]
    recipe("unit.ae.pike_team", "inf_at", params={"helmet": "angular"}, ops_after=ops)

def crane_kit():
    return [["tier", 1], ["brush", "dark"], ["box", [0, 0.985, -0.09], [0.16, 0.10, 0.04], 0.0],
            ["brush", "metal", "metal"],
            ["box", [0.10, 0.98, 0.27], [0.07, 0.55, 0.07], 0.0],
            ["box", [0.10, 1.25, 0.11], [0.07, 0.07, 0.42], 0.0],
            ["tier", 2],
            ["cyl", [0.10, 1.23, -0.10], [0.10, 1.05, -0.10], 0.008, 4, 0.0, False],
            ["brush", "acc", "emissive"], ["box", [0.10, 1.27, -0.10], [0.09, 0.09, 0.09], 0.0], ["tier", 0]]

def reclaimer():
    ops = [per_soldier(crane_kit() + belt_lamp(), 0.44)]
    recipe("unit.ae.reclaimer", "inf_special", params={"gear": "torch", "helmet": "angular"}, ops_after=ops,
           sockets={"weld0": {"pos": [0.2, 0.62, -0.44], "dir": [0, 0, -1]}})

def river_warden():
    wrap = [["tier", 1], ["brush", "mix(base,glass,0.6)"],
            ["box", [0, 0.985, 0.0], [0.27, 0.05, 0.29], 0.0],
            ["box", [-0.20, 0.80, 0.0], [0.13, 0.09, 0.26], 0.0],
            ["box", [0.20, 0.80, 0.0], [0.13, 0.09, 0.26], 0.0],
            ["tier", 2], ["box", [0, 0.68, -0.118], [0.30, 0.06, 0.03], 0.0], ["tier", 0]]
    ops = [per_soldier(crane_kit() + wrap, 0.44)]
    recipe("unit.ae.river_warden", "inf_special", params={"gear": "torch", "helmet": "angular"}, ops_after=ops,
           sockets={"weld0": {"pos": [0.2, 0.62, -0.44], "dir": [0, 0, -1]}})

if __name__ == "__main__":
    union_guard(); civic_rifle(); pike(); reclaimer(); river_warden()
