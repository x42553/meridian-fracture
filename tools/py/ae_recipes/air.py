import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def sunbird():
    ops = []
    # charcoal / darker repair patches bolted on the wing tops (mismatched tones), mirrored
    ops.append(mirror([
        ["brush", "sec"], ["box", [0.72, 0.722, 0.62], [0.36, 0.02, 0.82], 0.0],
        ["brush", "base*0.82"], ["box", [1.72, 0.712, 0.95], [0.36, 0.02, 0.52], 0.0],
        ["tier", 2], ["brush", "metal", "metal"],
        ["cyl", [0.72, 0.732, 0.30], [0.72, 0.762, 0.30], 0.03, 4, 0.0], ["cyl", [0.72, 0.732, 0.94], [0.72, 0.762, 0.94], 0.03, 4, 0.0],
        ["tier", 0],
    ]))
    # cyan intake rings (frame in front of each intake)
    ops.append(mirror([["brush", "acc", "emissive"],
        ["box", [0.44, 0.78, -0.37], [0.26, 0.03, 0.03], 0.0], ["box", [0.44, 0.46, -0.37], [0.26, 0.03, 0.03], 0.0],
        ["box", [0.31, 0.62, -0.37], [0.03, 0.32, 0.03], 0.0], ["box", [0.57, 0.62, -0.37], [0.03, 0.32, 0.03], 0.0]]))
    # cranked wing tips: canted charcoal tip fins give the "crank-wing" outline
    ops.append(mirror([push([2.05, 0.66, 1.35], [["brush", "sec"], ["box", [0.02, 0.0, 0.0], [0.05, 0.42, 0.62], 0.0]], [0, 0, -38]),
                       ["brush", "acc", "emissive"], ["box", [2.16, 0.86, 1.25], [0.04, 0.05, 0.10], 0.0]]))
    # charcoal dorsal spine plate + tail patch
    ops += [["brush", "sec"], ["box", [0, 1.03, 1.55], [0.22, 0.03, 0.55], 0.0]]
    recipe("unit.ae.sunbird_interceptor", "air_jet", params={"wing": "swept", "tail": "twin"}, ops_after=ops)

def hammerhead():
    ops = []
    # patchwork armour: bolt-on plates of different tones on the fuselage flanks
    ops.append(mirror([
        ["brush", "sec"], ["box", [0.43, 1.12, -0.35], [0.06, 0.46, 0.72], 0.0],
        ["brush", "base*0.82"], ["box", [0.43, 1.18, 0.40], [0.06, 0.40, 0.55], 0.0],
        ["tier", 2], ["brush", "metal", "metal"],
        ["cyl", [0.46, 1.30, -0.62], [0.49, 1.30, -0.62], 0.03, 4, 0.0], ["cyl", [0.46, 1.30, -0.08], [0.49, 1.30, -0.08], 0.03, 4, 0.0],
        ["cyl", [0.46, 1.34, 0.20], [0.49, 1.34, 0.20], 0.03, 4, 0.0], ["cyl", [0.46, 1.34, 0.60], [0.49, 1.34, 0.60], 0.03, 4, 0.0],
        ["tier", 0],
        # engine cowling repair plates
        ["brush", "mix(dark,base,0.3)"], ["box", [0.36, 1.76, 0.40], [0.28, 0.03, 0.55], 0.0],
    ]))
    # chin module: mount plate over the chin turret, cyan lock collar
    ops += [# armoured cheek blocks either side of the cockpit + belly armour tub (boxier, patchwork silhouette)
            mirror([["brush", "sec"], ["box", [0.52, 1.02, -0.95], [0.30, 0.42, 0.85], 0.02],
                    ["brush", "base*1.12"], ["box", [0.50, 1.36, -0.95], [0.26, 0.05, 0.75], 0.0]]),
            ["brush", "sec"], ["box", [0, 0.70, 0.05], [0.85, 0.22, 1.7], 0.02],
            ["brush", "sec"], ["box", [0, 0.88, -1.50], [0.42, 0.22, 0.55], 0.02],
            ["brush", "acc", "emissive"], ["box", [0, 0.88, -1.79], [0.36, 0.06, 0.04], 0.0],
            # cyan collar at the rotor hub
            ["cyl", [0, 1.98, 0.15], [0, 2.02, 0.15], 0.17, 10, 0.0]]
    recipe("unit.ae.hammerhead_gunship", "air_heli", ops_after=ops)

if __name__ == "__main__":
    sunbird(); hammerhead()
