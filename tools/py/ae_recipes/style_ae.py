"""Writes styles/ae.json (faction style + 3 subfaction overlays)."""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aelib import *
from aestruct import front_slot, extra_slot, LETS

SKIRT = [
    {"let": {"aeL": "(2*hl-0.6)/4", "aeX": "hw*1.16+0.03"}},
    {"for": "j", "n": 4, "do": [
        {"let": {"aeZ": "-hl+0.3+aeL*(j+0.5)", "aeH": "0.34+(j%2)*0.08", "aeY": "0.74-(j%2)*0.03+(j==2?0.04:0)"}},
        ["brush", "j == 0 ? 'base' : (j == 1 ? 'base*0.82' : (j == 2 ? 'mix(dark,base,0.3)' : 'base*1.12'))"],
        ["box", ["aeX", "aeY", "aeZ"], [0.08, "aeH", "aeL-0.07"], 0.0],
        ["tier", 2],
        ["brush", "metal", "metal"],
        {"for": "k", "n": 2, "do": [
            ["cyl",
             ["aeX+0.04", "aeY+aeH*0.5-0.05", "aeZ+(k*2-1)*(aeL*0.5-0.1)"],
             ["aeX+0.065", "aeY+aeH*0.5-0.05", "aeZ+(k*2-1)*(aeL*0.5-0.1)"],
             0.03, 4, 0.0]]},
        ["tier", 0],
    ]},
]

def sub_extra(kind):
    base = extra_slot()[1]["then"]
    lite_base = extra_slot()[1]["else"][0]["then"]
    add = []
    lite_add = []
    if kind == "nigeria":
        # comm_mast + civic_beacon: radio mast with two guy wires and a pulsing cyan beacon (rear-right corner)
        add = [
            {"let": {"aeMx": "aePW*0.5+0.1", "aeMz": "aeBK+0.4", "aeMh": "0.7*aeHC"}},
            ["brush", "metal", "metal"],
            ["cyl", ["aeMx", 0, "aeMz"], ["aeMx", "aeMh", "aeMz"], 0.05, 6, 0.0],
            ["cyl", ["aeMx", "aeMh*0.8", "aeMz"], ["aeMx-0.9", 0.1, "aeMz+0.9"], 0.012, 4, 0.0, False],
            ["cyl", ["aeMx", "aeMh*0.8", "aeMz"], ["aeMx+0.6", 0.1, "aeMz+0.9"], 0.012, 4, 0.0, False],
            {"part": {"kind": "blink", "param": 0.25}, "do": [["brush", "acc", "emissive"], ["box", ["aeMx", "aeMh+0.1", "aeMz"], [0.14, 0.14, 0.14], 0.0]]},
        ]
        lite_add = [
            {"let": {"aeMx": "aePW*0.5+0.1", "aeMz": "aeBK+0.4", "aeMh": "0.7*aeHC"}},
            ["brush", "metal", "metal"],
            ["box", ["aeMx", "aeMh*0.5", "aeMz"], [0.1, "aeMh", 0.1], 0.0],
            {"part": {"kind": "blink", "param": 0.25}, "do": [["brush", "acc", "emissive"], ["box", ["aeMx", "aeMh+0.1", "aeMz"], [0.14, 0.14, 0.14], 0.0]]},
        ]
    elif kind == "kongo":
        # reed_screen (ochre slats on the right wall) + snorkel_stack (capped intake pipe at the rear)
        add = [
            {"let": {"aeRx": "aePW*0.5+0.1", "aeRz": "aeBK+3.2"}},
            ["brush", "base*1.15"],
            loop("j", 4, [["box", ["aeRx", 0.85, "aeRz+j*0.4"], [0.06, 1.7, 0.14], 0.0]]),
            ["brush", "metal", "metal"],
            ["cyl", ["aePW*0.5-0.5", 0, "aeBK-0.05"], ["aePW*0.5-0.5", "0.5*aeHC", "aeBK-0.05"], 0.09, 6, 0.0],
            ["box", ["aePW*0.5-0.5", "0.5*aeHC+0.08", "aeBK-0.13"], [0.2, 0.16, 0.26], 0.0],
        ]
        lite_add = [
            {"let": {"aeRx": "aePW*0.5+0.1", "aeRz": "aeBK+1.6"}},
            ["brush", "base*1.15"],
            ["tier", 1],
            loop("j", 2, [["box", ["aeRx", 0.85, "aeRz+j*0.3"], [0.06, 1.7, 0.12], 0.0]]),
            ["tier", 0], ["brush", "metal", "metal"],
            ["box", ["aePW*0.5-0.5", "0.25*aeHC", "aeBK-0.05"], [0.14, "0.5*aeHC", 0.14], 0.0],
        ]
    elif kind == "south_africa":
        # rangefinder_box: 0.6 x 0.3 x 0.3 box with two lenses on a short mast (front-left corner)
        add = [
            {"let": {"aeFx": "-aePW*0.5+0.6", "aeFz": "aeHH-0.6", "aeFh": "0.3*aeHC"}},
            ["brush", "metal", "metal"],
            ["box", ["aeFx", "aeFh*0.5", "aeFz"], [0.12, "aeFh", 0.12], 0.0],
            ["brush", "sec"],
            ["box", ["aeFx", "aeFh+0.16", "aeFz"], [0.62, 0.3, 0.3], 0.0],
            ["brush", "glass", "glass"],
            loop("s", 2, [["box", ["aeFx+(s*2-1)*0.2", "aeFh+0.16", "aeFz+0.155"], [0.13, 0.13, 0.03], 0.0]]),
        ]
        lite_add = [
            {"let": {"aeFx": "-aePW*0.5+0.6", "aeFz": "aeHH-0.6", "aeFh": "0.3*aeHC"}},
            ["brush", "metal", "metal"],
            ["box", ["aeFx", "aeFh*0.5", "aeFz"], [0.12, "aeFh", 0.12], 0.0],
            ["brush", "sec"],
            ["box", ["aeFx", "aeFh+0.16", "aeFz"], [0.62, 0.3, 0.3], 0.0],
            ["brush", "glass", "glass"],
            ["box", ["aeFx", "aeFh+0.16", "aeFz+0.155"], [0.46, 0.13, 0.03], 0.0],
        ]
    return [LETS, {"if": "fw*fh >= 9", "then": base + add, "else": [{"if": "fw*fh >= 4", "then": lite_base + lite_add}]}]


def build():
    ae = {
        "emblem": "ring",
        "kit": {
            "barrel_len": 2.0, "barrel_r": 0.08, "deck": "none", "glacis": 0.6, "hull_top": 1.12, "hull_w": 2.0, "len": 3.5,
            "muzzle": "plain", "roof": "rails", "skirt": "patches", "track_w": 0.46, "track_x": 0.92, "turret_h": 0.44,
            "turret_hl": 0.86, "turret_hw": 0.8, "turret_n": 6, "turret_rot": 30.0, "turret_shift": 0.0, "turret_top": 0.8,
            "turret_z": 0.16, "wheel_n": 5, "wheel_r": 0.36,
        },
        "material": {"dirt": 0.6, "dirt_color": "#3a2c1a", "emissive": 2.8, "panel": 0.75, "wear": 0.6, "wear_color": "#c8b48a"},
        "palette": {
            "acc": "#12d6f2", "base": "#8f6524", "concrete": "#7d7568", "dark": "#2b2d30", "glass": "#12363e", "light": "#fff0c0",
            "metal": "#34373a", "plate": "#16171a", "rubber": "#101010", "sec": "#4b4e53",
        },
        "slots": {"skirt": SKIRT, "front": front_slot(), "extra": extra_slot()},
        "team_plate": "band",
    }
    styles = {"ae": ae}
    subs = {
        "nigeria": {"acc": "#03b3cb", "emblem": "triple_bar", "kit": {"roof": "mast"}},
        "kongo": {"acc": "#26d8dd", "emblem": "chevron", "kit": {"roof": "snorkel"}},
        "south_africa": {"acc": "#4cd2ff", "emblem": "hex_notch", "kit": {"roof": "sensors"}},
    }
    for name, d in subs.items():
        styles["ae." + name] = {"extends": "ae", "emblem": d["emblem"], "kit": d["kit"], "palette": {"acc": d["acc"]},
                                "slots": {"extra": sub_extra(name)}}
    def srt(st):
        out = {}
        for k in sorted(st):
            v = st[k]
            out[k] = dict(sorted(v.items())) if k in ("kit", "material", "palette") else v
        return out
    return {"schema": "meridian.styles/1", "styles": {k: srt(styles[k]) for k in sorted(styles)}}


if __name__ == "__main__":
    d = build()
    with open(ROOT + "/styles/ae.json", "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print("styles/ae.json written")
