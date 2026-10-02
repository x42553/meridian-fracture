import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

def side_plates(zs, fbv, heights, tones=("base*0.82", "sec", "mix(dark,base,0.3)", "base*1.12"), half="sp_beam"):
    """bolt-on hull-side repair plates (mirrored); zs are z expressions; `half` is the beam parameter name."""
    ops = []
    for i, z in enumerate(zs):
        ops += [["brush", tones[i % len(tones)]],
                ["box", ["%s*0.5+0.02" % half, fbv, z], [0.05, heights[i % len(heights)], 0.9 if i % 2 == 0 else 0.7], 0.0]]
    return [mirror(ops)]

def fenders(n, zs_expr, xexpr, y):
    """tyre fenders hung on the hull side."""
    return [mirror([["brush", "rubber", "rubber"], loop("k", n, [
        ["cyl", [xexpr, y, zs_expr], [add(xexpr, 0.1) if not isinstance(xexpr, str) else "(%s)+0.1" % xexpr, y, zs_expr], 0.14, 8, 0.0]])])]

def delta():
    ops = []
    ops += side_plates(["hl*-0.10", "hl*0.55"], "fb*0.55", [0.32, 0.26])
    ops += [mirror([["brush", "rubber", "rubber"], loop("k", 3, [
        ["cyl", ["sp_beam*0.5+0.02", "fb*0.45", "lerp(-hl*0.2,hl*0.75,k/2)"], ["sp_beam*0.5+0.12", "fb*0.45", "lerp(-hl*0.2,hl*0.75,k/2)"], 0.11, 6, 0.0]])])]
    ops += [
        # module rail plate under the deck gun + cyan lock collar on the barrel base
        ["brush", "sec"], ["box", [0, "fb+0.05", "-hl*0.5"], [0.86, 0.10, 0.86], 0.02],
        part("barrel", [["brush", "acc", "emissive"], ["cyl", [0, "fb+0.36*0.36/0.42", "-hl*0.5-0.36*0.6-0.05"], [0, "fb+0.36*0.36/0.42", "-hl*0.5-0.36*0.6-0.11"], 0.11, 8, 0.0]],
             pivot=[0, "fb+0.14*0.36/0.42", "-hl*0.5"], param=1.0, extra=0.25, trunnion=["fb+0.36*0.36/0.42", "-hl*0.5"]),
        # push-bar at the flat bow
        ["brush", "dark", "metal"], ["box", [0, "fb-0.18", "-hl+0.15"], ["sp_beam*0.62", 0.1, 0.1], 0.0],
        # cyan work-light bar on the cabin roof
        ["brush", "acc", "emissive"], ["box", [0, "fb+0.79", "hl*0.05-0.5"], ["sp_beam-0.9", 0.035, 0.012], 0.0],
    ]
    recipe("unit.ae.delta_patrol_boat", "ship_patrol", params={"bow": "blunt", "cabin": "closed", "gun": "auto"}, ops_after=ops)

def anchor():
    ops = []
    ops += side_plates(["hl*-0.35", "hl*0.10", "hl*0.5"], "fb*0.62", [0.4, 0.5, 0.36], half="se_beam")
    ops += [mirror([["brush", "rubber", "rubber"], loop("k", 4, [
        ["cyl", ["se_beam*0.5+0.02", "fb*0.45", "lerp(-hl*0.4,hl*0.8,k/3)"], ["se_beam*0.5+0.12", "fb*0.45", "lerp(-hl*0.4,hl*0.8,k/3)"], 0.13, 8, 0.0]])])]
    # aft crane (starboard quarter) and a stowage frame
    ops += crane("se_beam*0.32", "hl-1.35", "fb", 2.6, 2.4, yaw=35)
    ops += [["brush", "sec"], ["box", ["-se_beam*0.30", "fb+0.16", "hl-1.35"], [0.9, 0.32, 0.9], 0.02]]
    ops += patch(["-se_beam*0.30", "fb+0.32", "hl-1.35"], [0.9, 0.02, 0.9], "base*0.82", 2)
    # cyan lock collar on the forward gun
    ops += [part("barrel", [["brush", "acc", "emissive"], ["cyl", [0, "fb+0.36*0.5/0.42", "-hl+1.55-0.5*0.6-0.05"], [0, "fb+0.36*0.5/0.42", "-hl+1.55-0.5*0.6-0.11"], 0.11, 8, 0.0]],
                 pivot=[0, "fb+0.14*0.5/0.42", "-hl+1.55"], param=1.0, extra=0.25, trunnion=["fb+0.36*0.5/0.42", "-hl+1.55"])]
    recipe("unit.ae.anchor_escort", "ship_escort", params={"helipad": False, "bow": "blunt"}, ops_after=ops)

def sovereign():
    ops = []
    ops += side_plates(["hl*-0.55", "hl*-0.15", "hl*0.30", "hl*0.62"], "fb*0.6", [0.5, 0.42, 0.56, 0.4], half="ss_beam")
    ops += [mirror([["brush", "rubber", "rubber"], loop("k", 5, [
        ["cyl", ["ss_beam*0.5+0.02", "fb*0.45", "lerp(-hl*0.5,hl*0.8,k/4)"], ["ss_beam*0.5+0.14", "fb*0.45", "lerp(-hl*0.5,hl*0.8,k/4)"], 0.16, 8, 0.0]])])]
    # A-frame gantry crane over the stern: two legs, cross-beam, trolley and hoist
    ops += [mirror([["brush", "dark", "metal"], ["cyl", ["ss_beam*0.5-0.2", "fb", "hl-0.45"], ["ss_beam*0.5-0.45", "fb+3.1", "hl-0.85"], 0.09, 6, 0.0]]),
            ["brush", "base*0.82"], ["box", [0, "fb+3.15", "hl-0.85"], ["ss_beam-0.9", 0.16, 0.18], 0.0],
            ["brush", "metal", "metal"], ["cyl", [0.4, "fb+3.05", "hl-0.85"], [0.4, "fb+1.7", "hl-0.85"], 0.014, 4, 0.0, False],
            ["box", [0.4, "fb+1.66", "hl-0.85"], [0.16, 0.12, 0.12], 0.0],
            ["brush", "acc", "emissive"], ["box", [-0.9, "fb+3.28", "hl-0.85"], [0.09, 0.09, 0.09], 0.0]]
    # module clamps (cyan) on both forward gun pairs
    for zc in ("-hl+1.9", "-hl+4.1"):
        ops += [part("barrel", [["brush", "acc", "emissive"], ["box", [0, "fb+0.36*1.714", "%s-0.72*0.6-0.75" % zc], [0.40, 0.22, 0.06], 0.0]],
                     pivot=[0, "fb+0.14*1.714", zc], param=1.0, extra=0.25, trunnion=["fb+0.36*1.714", zc])]
    recipe("unit.ae.sovereign_arsenal_ship", "ship_siege", ops_after=ops)

if __name__ == "__main__":
    delta(); anchor(); sovereign()
