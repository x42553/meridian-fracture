"""AE structure dialect (style slots `front` / `extra`, common structure scope: pw ph hw aeHH ap fz aeBK bd bz aePW aeK aeHC fw fh)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *

LETS = {"let": {"aePW": "fw*3-1.0", "aeHH": "(fh*3-0.5)*0.5", "aeBK": "-aeHH+0.25", "aeK": "clamp(min(fw*3-0.5,fh*3-0.5)/5.5,0.8,1.25)",
                "aeHC": "(max(fw,fh)>=4 ? 14 : (max(fw,fh)>=3 ? 12 : 8))-0.35", "aeFZ": "aeHH-(fw*fh>1 ? 1.0 : 0.3)"}}


def front_slot():
    """caged cyan core on the front-right apron (skipped on 1x1 structures)."""
    core = [
        {"let": {"aeCx": "hw-0.85", "aeCz": "aeHH-0.6"}},
        ["brush", "dark"], ["box", ["aeCx", 0.08, "aeCz"], [0.9, 0.16, 0.9], 0.0],
        ["brush", "acc", "emissive"], ["cyl", ["aeCx", 0.16, "aeCz"], ["aeCx", 1.12, "aeCz"], 0.2, 8, 0.0],
        ["brush", "metal", "metal"],
        loop("s", 2, [loop("t", 2, [["cyl", ["aeCx+(s*2-1)*0.4", 0.12, "aeCz+(t*2-1)*0.4"], ["aeCx+(s*2-1)*0.4", 1.5, "aeCz+(t*2-1)*0.4"], 0.035, 4, 0.0]])]),
        loop("h", 2, [
            ["box", ["aeCx", "0.3+h*1.1", "aeCz+0.4"], [0.83, 0.04, 0.04], 0.0], ["box", ["aeCx", "0.3+h*1.1", "aeCz-0.4"], [0.83, 0.04, 0.04], 0.0],
            ["box", ["aeCx+0.4", "0.3+h*1.1", "aeCz"], [0.04, 0.04, 0.83], 0.0], ["box", ["aeCx-0.4", "0.3+h*1.1", "aeCz"], [0.04, 0.04, 0.83], 0.0]]),
    ]
    return [LETS, {"if": "fw*fh >= 9", "then": core}]

def extra_slot():
    pipe_x = "-(aePW*0.5+0.15)"
    pipes = [
        {"let": {"aePx": pipe_x, "aePy": "1.1*clamp(aeK,0.85,1.2)", "aePz0": "aeBK+0.8", "aePz1": "aeFZ-1.9"}},
        ["brush", "metal", "metal"],
        ["cyl", ["aePx", "aePy", "aePz0"], ["aePx", "aePy", "aePz1"], 0.11, 8, 0.0],
        ["cyl", ["aePx", 0.1, "aePz0"], ["aePx", "aePy", "aePz0"], 0.11, 8, 0.0],
        ["cyl", ["aePx", "aePy", "aePz1"], ["aePx", "aePy+0.9", "aePz1"], 0.09, 8, 0.0],
        ["brush", "dark"],
        loop("j", 3, [["box", ["aePx+0.08", "aePy-0.2", "lerp(aePz0,aePz1,(j+0.5)/3)"], [0.16, 0.06, 0.12], 0.0]]),
        ["brush", "acc"],
        loop("j", 2, [["cyl", ["aePx", "aePy", "lerp(aePz0,aePz1,0.28+j*0.44)"], ["aePx", "aePy", "lerp(aePz0,aePz1,0.28+j*0.44)+0.07"], 0.145, 8, 0.0]]),
    ]
    scrap = [
        {"let": {"aeSx": "aePW*0.5+0.13", "aeSz": "aeBK+1.0"}},
        ["tier", 1],
        loop("j", 3, [
            ["brush", "j == 0 ? 'base*0.82' : (j == 1 ? 'sec' : 'mix(dark,base,0.3)')"],
            ["box", ["aeSx+(j-1)*0.02", "0.07+j*0.14", "aeSz+(j-1)*0.05"], [0.30, 0.14, 0.9], 0.0]]),
        ["brush", "rubber", "rubber"],
        ["cyl", ["aeSx", 0.02, "aeSz+1.25"], ["aeSx", 0.62, "aeSz+1.25"], 0.2, 6, 0.0],
        ["brush", "sec"],
        ["cyl", ["aeSx", 0.02, "aeSz+1.75"], ["aeSx", 0.62, "aeSz+1.75"], 0.2, 6, 0.0],
        ["tier", 0],
    ]
    jib = [
        {"let": {"aeH": "0.62*aeHC", "aeJ": "clamp(aePW*0.45,1.8,3.6)"}},
        ["brush", "dark", "metal"],
        ["cyl", ["-(aePW*0.5+0.1)", 0, "aeBK+0.4"], ["-(aePW*0.5+0.1)", "aeH", "aeBK+0.4"], 0.09, 6, 0.0],
        ["brush", "sec"], ["box", ["-(aePW*0.5+0.1)", 0.2, "aeBK+0.4"], [0.3, 0.4, 0.3], 0.0],
        push(["-(aePW*0.5+0.1)", "aeH", "aeBK+0.4"], [
            ["brush", "base*0.82"],
            ["box", [0, 0.05, "aeJ*-0.45"], [0.1, 0.1, "aeJ"], 0.0],
            ["box", [0, 0.16, 0.12], [0.16, 0.16, 0.24], 0.0],
            ["brush", "metal", "metal"],
            ["cyl", [0, 0, "aeJ*-0.85"], [0, -1.6, "aeJ*-0.85"], 0.012, 4, 0.0, False],
            ["box", [0, -1.64, "aeJ*-0.85"], [0.09, 0.07, 0.06], 0.0],
            ["brush", "acc", "emissive"], ["box", [0, 0.12, "aeJ*-1.0"], [0.07, 0.07, 0.07], 0.0],
        ], [0, -90, 0]),
    ]
    lite = [
        {"let": {"aeH": "0.62*aeHC", "aeJ": "clamp(aePW*0.45,1.8,3.6)", "aeMx": "-(aePW*0.5+0.1)"}},
        ["brush", "dark", "metal"],
        ["box", ["aeMx", "aeH*0.5", "aeBK+0.4"], [0.14, "aeH", 0.14], 0.0],
        push(["aeMx", "aeH", "aeBK+0.4"], [
            ["brush", "base*0.82"],
            ["box", [0, 0.05, "aeJ*-0.45"], [0.1, 0.1, "aeJ"], 0.0],
            ["brush", "metal", "metal"],
            ["cyl", [0, 0, "aeJ*-0.85"], [0, -1.4, "aeJ*-0.85"], 0.012, 4, 0.0, False],
            ["brush", "acc", "emissive"], ["box", [0, 0.12, "aeJ*-1.0"], [0.07, 0.07, 0.07], 0.0],
        ], [0, -90, 0]),
    ]
    return [LETS, {"if": "fw*fh >= 9", "then": pipes + scrap + jib, "else": [{"if": "fw*fh >= 4", "then": lite}]}]

if __name__ == "__main__":
    import json
    print(json.dumps(front_slot())[:100])
