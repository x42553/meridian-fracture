import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def wheel_z(j):  # apc wheel z positions
    return "lerp(az0,az1,%s*0.5)" % j

def apc_common(tag):
    ops = []
    # steel-ringed tyres: cyan hub dot on each outer face
    ops.append(mirror([["tier", 2], ["brush", "acc", "emissive"], loop("j", 3, [
        ["box", ["wx+tire_w*0.5+0.015", "tire_r", "lerp(az0,az1,j*0.5)"], [0.05, 0.10, 0.10], 0.0]]), ["tier", 0]]))
    # steel wheel rings
    ops.append(mirror([["tier", 2], ["brush", "metal", "metal"], loop("j", 3, [
        ["cyl", ["wx+tire_w*0.5-0.005", "tire_r", "lerp(az0,az1,j*0.5)"], ["wx+tire_w*0.5+0.012", "tire_r", "lerp(az0,az1,j*0.5)"], "tire_r*0.62", 8, 0.0]]), ["tier", 0]]))
    # mismatched bolt-on fender/side panels between the axles
    ops.append(mirror([loop("j", 2, [
        ["brush", "j == 0 ? 'base*0.82' : 'mix(dark,base,0.3)'"],
        ["box", ["hw+0.035", "0.99+j*0.03", "lerp(az0,az1,0.25+j*0.5)"], [0.06, "0.34+j*0.06", "(az1-az0)/2-0.62"], 0.0],
        ["tier", 2], ["brush", "metal", "metal"],
        ["cyl", ["hw+0.06", "1.16+j*0.05", "lerp(az0,az1,0.25+j*0.5)-0.2"], ["hw+0.085", "1.16+j*0.05", "lerp(az0,az1,0.25+j*0.5)-0.2"], 0.03, 4, 0.0],
        ["tier", 0]])]))
    # push-bar + tow hooks
    ops += [["tier", 2], ["brush", "dark", "metal"],
            ["box", [0, 0.62, "-hl-0.14"], ["hw*1.6", 0.12, 0.10], 0.0],
            loop("s", 2, [["box", ["(s*2-1)*hw*0.6", 0.66, "-hl-0.07"], [0.09, 0.09, 0.16], 0.0]]), ["tier", 0]]
    return ops

def mamba():
    slots = {"skirt": [], "deck": [
        # spare wheel standing on the rear deck (steel ring + cyan hub), stowage crate
        ["brush", "rubber", "rubber"],
        ["cyl", ["-hw*0.45", "body_top+0.34", "hl*0.62"], ["-hw*0.45+0.24", "body_top+0.34", "hl*0.62"], 0.30, 12, 0.0],
        ["tier", 2], ["brush", "metal", "metal"],
        ["cyl", ["-hw*0.45+0.22", "body_top+0.34", "hl*0.62"], ["-hw*0.45+0.26", "body_top+0.34", "hl*0.62"], 0.18, 8, 0.0],
        ["brush", "acc", "emissive"],
        ["cyl", ["-hw*0.45+0.25", "body_top+0.34", "hl*0.62"], ["-hw*0.45+0.28", "body_top+0.34", "hl*0.62"], 0.06, 6, 0.0], ["tier", 0],
    ] + box(["hw*0.35", "body_top+0.10", "hl*0.62"], [0.5, 0.18, 0.7], "sec", 0.0)}
    ops_after = apc_common("mamba") + [
        # cyan work-light bar on the cab roof
        ["tier", 2], ["brush", "dark"], ["box", [0, "body_top+0.05", "-hl+0.16"], ["hw*1.2", 0.07, 0.10], 0.0],
        ["brush", "acc", "emissive"], ["box", [0, "body_top+0.05", "-hl+0.105"], ["hw*1.05", 0.04, 0.012], 0.0], ["tier", 0],
        # detector: small ball sensor on the cab roof
        ["tier", 2], call("ball_sensor", center=["hw*0.42", "body_top+0.06", "-hl*0.12"], r=0.17), ["tier", 0],
    ]
    recipe("unit.ae.mamba_apc", "veh_apc", params={"tire_r": 0.44, "tire_w": 0.34}, slots=slots, ops_after=ops_after)

def okapi():
    z0 = "hl*0.68"
    L = "hl*0.62"
    hold = [
        # tall, bulky cargo hold behind the cab / RWS, clean sheet panels with vertical ribs
        ["brush", "base*1.12"],
        ["box", [0, "body_top+0.34", z0], ["hw*1.62", 0.68, L], 0.03],
        ["tier", 2], ["brush", "sec"],
        loop("k", 5, [["box", ["hw*1.62*(k-2)/5", "body_top+0.34", "%s-(%s)*0.5-0.005" % (z0, L)], [0.05, 0.66, 0.03], 0.0]]), ["tier", 0],
        ["brush", "base*0.82"],
        ["box", [0, "body_top+0.71", z0], ["hw*1.66", 0.05, "%s+0.04" % L], 0.0],
        ["brush", "dark"],
        loop("s", 2, [["box", ["(s*2-1)*hw*0.5", "body_top+0.75", z0], [0.06, 0.05, "%s*0.9" % L], 0.0]]),
        ["brush", "sec"],
        ["box", ["-hw*0.30", "body_top+0.76", z0], [0.5, 0.06, 0.5], 0.01],
        ["brush", "dark"],
        ["box", [0, "body_top+0.28", "%s+(%s)*0.5+0.01" % (z0, L)], ["hw*1.2", 0.5, 0.05], 0.0],
        ["brush", "acc", "emissive"],
        ["box", [0, "body_top+0.60", "%s+(%s)*0.5+0.03" % (z0, L)], ["hw*1.0", 0.04, 0.012], 0.0],
    ]
    ops_after = [
        mirror([["brush", "acc", "emissive"], loop("j", 3, [
            ["box", ["hw+0.02", "tire_r", "lerp(-hl*0.55,hl*0.6,j*0.5)"], [0.05, 0.10, 0.10], 0.0]])]),
        ["tier", 2], ["brush", "dark", "metal"],
        ["box", [0, 0.72, "-hl-0.10"], ["hw*1.4", 0.12, 0.09], 0.0],
        # cyan work-light bar on the cab roof
        ["brush", "acc", "emissive"], ["box", [0, "body_top+0.04", "-hl+0.15"], ["hw*1.0", 0.04, 0.012], 0.0], ["tier", 0],
        ["tier", 2], call("ball_sensor", center=["hw*0.5", "body_top+0.02", "-hl*0.62"], r=0.15), ["tier", 0],
    ]
    recipe("unit.ae.okapi_amphibious_carrier", "veh_amphib", params={"float": "pontoon", "body_top": 1.34, "roof": "snorkel"},
           slots={"deck": hold, "roof": []}, ops_after=ops_after)

if __name__ == "__main__":
    mamba(); okapi()
