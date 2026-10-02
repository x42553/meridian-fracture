#!/usr/bin/env python3
"""Generator for the Han Empire (VIEW-M8 F-han) recipes: styles/han.json + unit.han.* + structure.han.* (+ summons).

  python3 tools/py/gen_recipes_han.py            # (re)write every Han file under game/data/recipes
  python3 tools/py/gen_recipes_han.py --only unit.han.ox_tank,styles

The output is plain JSON (hand-editable afterwards; this script is only a convenience to share op snippets such as the sensor
crown or the parked drones between recipes). Stdlib only. Never touches recipes without `meta.han_gen` (other factions, stubs)."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[2] / "game" / "data" / "recipes"
Op = Any


# ------------------------------------------------------------------------------------------------ json layout
def fmt(o: Any, ind: int = 0, w: int = 150) -> str:
    """One compact line when short, otherwise one entry per line (ops stay diffable)."""
    flat = json.dumps(o, separators=(", ", ": "), ensure_ascii=False)
    if len(flat) + ind <= w or not isinstance(o, (list, dict)):
        return flat
    pad = " " * (ind + 2)
    if isinstance(o, list):
        return "[\n" + ",\n".join(pad + fmt(x, ind + 2, w) for x in o) + "\n" + " " * ind + "]"
    return "{\n" + ",\n".join(pad + json.dumps(k) + ": " + fmt(v, ind + 2, w) for k, v in o.items()) + "\n" + " " * ind + "}"


def clean(o: Any) -> Any:
    """Round floats to 4 decimals (keeps 0.0 style ints) so float noise never reaches the JSON."""
    if isinstance(o, float):
        r = round(o, 4)
        return int(r) if r == int(r) and abs(r) < 1e9 and o == int(o) else r
    if isinstance(o, list):
        return [clean(x) for x in o]
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    return o


def write(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(fmt(clean(obj)) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------------------------------ op snippets
def brush(col: str, mat: str = "", team: Any = None) -> Op:
    r: List[Any] = ["brush", col]
    if mat or team is not None:
        r.append(mat or "paint")
    if team is not None:
        r.append(team)
    return r


def box(c: List[Any], s: List[Any], b: Any = 0.0) -> Op:
    return ["box", c, s, b]


def cyl(a: List[Any], b: List[Any], r: Any, segs: int = 8, bevel: Any = 0.0) -> Op:
    return ["cyl", a, b, r, segs, bevel]


def push(pos: List[Any], do: List[Op], euler: List[Any] = None) -> Op:
    d: Dict[str, Any] = {"pos": pos}
    if euler is not None:
        d["euler"] = euler
    return {"push": d, "do": do}


def part(kind: str, pivot: List[Any], do: List[Op], param: Any = None, extra: Any = None) -> Op:
    d: Dict[str, Any] = {"kind": kind, "pivot": pivot}
    if param is not None:
        d["param"] = param
    if extra is not None:
        d["extra"] = extra
    return {"part": d, "do": do}


def crown(x: Any, y: Any, z: Any, r: float = 0.2, h: float = 0.3, n: int = 6, spin: Any = 0.3, tier: int = 1) -> List[Op]:
    """HAN sensor crown: mast stub, porcelain ring disc, `n` crimson tines, emissive jade core (RADAR part = slow spin, `spin` = rate scale)."""
    inner: List[Op] = [
        ["tier", tier],
        brush("sec"), cyl([x, f"({y})+0.14", z], [x, f"({y})+0.17", z], r * 1.02, 10, 0.0),
        brush("acc"),
        {"for": "k", "n": n, "do": [box([f"({x})+cos(k*TAU/{n})*{r}", f"({y})+0.17+{h * 0.5}", f"({z})+sin(k*TAU/{n})*{r}"], [max(0.05, r * 0.16), h, max(0.05, r * 0.16)], 0.0)]},
        ["tier", 0],
        brush("mix(light,base,0.35)", "emissive"),
        box([x, f"({y})+0.21", z], [max(0.1, r * 0.4), max(0.08, r * 0.3), max(0.1, r * 0.4)], 0.0),
    ]
    head: List[Op] = [["tier", 0], brush("metal", "metal"), cyl([x, y, z], [x, f"({y})+0.14", z], 0.06, 5, 0.0)]
    if spin:
        return head + [part("radar", [x, f"({y})+0.14", z], inner, extra=spin)]
    return head + inner


def drone(x: Any, y: Any, z: Any, s: float = 1.0, eye: bool = True) -> List[Op]:
    """Parked HAN quad drone: porcelain body, jade cross arms, four rotor discs, jade eye lens facing -Z."""
    ops: List[Op] = [
        ["tier", 2],
        brush("sec"),
        box([x, f"({y})+{0.05 * s}", z], [0.2 * s, 0.07 * s, 0.24 * s], 0.0),
        brush("base"),
        box([x, f"({y})+{0.05 * s}", z], [0.5 * s, 0.02 * s, 0.05 * s], 0.0),
        box([x, f"({y})+{0.05 * s}", z], [0.05 * s, 0.02 * s, 0.5 * s], 0.0),
        brush("dark", "metal"),
    ]
    for dx in (-1, 1):
        for dz in (-1, 1):
            ops.append(cyl([f"({x})+{dx * 0.24 * s}", f"({y})+{0.07 * s}", f"({z})+{dz * 0.24 * s}"],
                           [f"({x})+{dx * 0.24 * s}", f"({y})+{0.085 * s}", f"({z})+{dz * 0.24 * s}"], 0.09 * s, 6, 0.0))
    if eye:
        ops += [brush("mix(light,base,0.35)", "emissive"), box([x, f"({y})+{0.055 * s}", f"({z})-{0.125 * s}"], [0.07 * s, 0.05 * s, 0.02 * s], 0.0)]
    ops.append(["tier", 0])
    return ops


def diamond(x: Any, y: Any, z: Any, s: float = 0.24, face: str = "x", col: str = "acc") -> List[Op]:
    """HAN faction emblem (diamond) as a flat 0.012 m extrusion on a vertical cheek (face 'x' = +-X side, 'z' = front/back)."""
    h = s * 0.5
    prof = [[0, h], [h * 0.8, 0], [0, -h], [-h * 0.8, 0]]
    # extrude profile is [[x, y]...] with x forward (-Z), extruded along +-X between x0 and x1
    return [brush(col), ["extrude", [[a, b] for a, b in prof], f"({x})-0.006", f"({x})+0.006", 0.0]]


def write_unit(uid: str, archetype: str, params: Dict[str, Any] = None, slots: Dict[str, List[Op]] = None,
               ops_after: List[Op] = None, meta: Dict[str, Any] = None, style: str = "auto", sockets: Any = None) -> None:
    r: Dict[str, Any] = {"schema": "meridian.recipe/1", "id": uid, "archetype": archetype, "style": style}
    if params:
        r["params"] = params
    if slots:
        r["slots"] = slots
    if ops_after:
        r["ops_after"] = ops_after
    m: Dict[str, Any] = {"han_gen": True}
    if meta:
        m.update(meta)
    r["meta"] = m
    write(ROOT / (uid + ".json"), r)


# ------------------------------------------------------------------------------------------------ styles
def emblem_cheeks(f0: Any, y0: Any, xr: Any, s: float = 0.34) -> List[Op]:
    """HAN diamond emblem stamped flat on both vertical cheeks (0.012 m extrusion; profile x = forward = -Z)."""
    h = s * 0.5
    prof = [[f"({f0})+{-h * 0.75}", y0], [f0, f"({y0})+{h}"], [f"({f0})+{h * 0.75}", y0], [f0, f"({y0})-{h}"]]
    return [{"mirror_x": [brush("acc"), ["extrude", prof, f"({xr})", f"({xr})+0.014", 0.0]]}]


def shared_struct_extra() -> List[Op]:
    """HAN structure dialect for every shared structure archetype (slot `extra`, only the footprint variables fw / fh that the
    builder injects into every structure): two porcelain standards on the plinth margin of the front half. Footprints above 4
    cells (3x3 halls, airfield) carry the sensor crown on top; the 1x1 / 2x2 buildings (triangle budget 3000) a crimson lantern."""
    big = [brush("sec"), box([0, 1.4, 0], [0.16, 2.8, 0.16], 0.0),
           brush("acc"), box([0, 0.5, 0], [0.2, 0.14, 0.2], 0.0), box([0, 1.7, 0], [0.19, 0.08, 0.19], 0.0)] + crown(0, 2.8, 0, 0.2, 0.34, n=6, spin=0.3, tier=1)
    small = [brush("sec"), box([0, 1.15, 0], [0.16, 2.3, 0.16], 0.0), brush("acc"), box([0, 0.45, 0], [0.2, 0.12, 0.2], 0.0)] + lantern(0, 2.3, 0, 0.13)
    return [{"let": {"hxx": "fw*1.5-0.25", "hyy": "fh*1.5-0.25"}},
            {"if": "fw*fh > 4", "then": [{"mirror_x": [push(["hxx-0.24", 0.16, "hyy*0.5"], big)]}],
             "else": [{"if": "fw*fh > 1", "then": [{"mirror_x": [push(["hxx-0.135", 0.16, "hyy*0.5"], small)]}]}]}]


def build_styles() -> None:
    kit = {
        "barrel_len": 1.75, "barrel_r": 0.068, "deck": "drone_rack", "glacis": 0.85, "helmet": "wrap", "hull_top": 1.06,
        "hull_w": 1.72, "len": 3.0, "muzzle": "sleeve", "roof": "crown", "skirt": "modules", "track_w": 0.4, "track_x": 0.8,
        "turret_h": 0.36, "turret_hl": 0.7, "turret_hw": 0.7, "turret_n": 12, "turret_rot": 15.0, "turret_shift": 0.0,
        "turret_top": 0.78, "turret_z": 0.1, "wheel_n": 4, "wheel_r": 0.27,
    }
    han = {
        "emblem": "diamond",
        "kit": kit,
        "material": {"dirt": 0.2, "dirt_color": "#24322c", "emissive": 2.6, "panel": 0.9, "wear": 0.25, "wear_color": "#efebdd"},
        "palette": {"acc": "#ab1d2c", "base": "#2d8862", "concrete": "#858a80", "dark": "#16483a", "glass": "#153b38",
                    "light": "#f2fff6", "metal": "#3a403e", "plate": "#0f1614", "rubber": "#151515", "sec": "#ece7d9"},
        "slots": {"extra": shared_struct_extra()},
        "team_plate": "band",
    }
    # subfaction kit-bash: slot `deck` exists on veh_tank / veh_apc / veh_amphib (hull-deck level, variables hl / hw only)
    china_deck: List[Op] = [{"mirror_x": [
        brush("sec"), box(["hw-0.2", 1.17, "hl-0.55"], [0.03, 0.2, 0.3], 0.0), box(["hw-0.2", 1.17, "hl-1.0"], [0.03, 0.2, 0.3], 0.0),
        brush("acc"), box(["hw-0.2", 1.29, "hl-0.775"], [0.035, 0.03, 0.75], 0.0),
        # flank plates (wheeled hulls: visible above the wheel arches)
        brush("sec"), box(["hw+0.025", 0.96, -0.3], [0.03, 0.2, 0.3], 0.0), box(["hw+0.025", 0.96, 0.3], [0.03, 0.2, 0.3], 0.0)]}]
    vietnam_deck: List[Op] = [{"mirror_x": [{"for": "j", "n": 3, "do": [
        brush("j % 2 == 0 ? 'base' : 'mix(acc,dark,0.55)'"), push(["hw-0.1", 1.12, "-hl*0.5+j*hl*0.45"], [box([0, 0, 0], [0.09, 0.03, 0.22], 0.0)], [0, 0, "j % 2 == 0 ? 25 : -25"]),
        push(["hw+0.03", 0.98, "-hl*0.4+j*hl*0.4"], [box([0, 0, 0], [0.03, 0.09, 0.22], 0.0)], [0, 0, "j % 2 == 0 ? 20 : -20"])]}]}]
    cambodia_deck: List[Op] = [{"mirror_x": [
        brush("dark", "metal"), cyl(["hw-0.2", 1.2, "hl-0.9"], ["hw-0.2", 1.2, "hl-0.35"], 0.14, 8, 0.0),
        brush("acc"), cyl(["hw-0.2", 1.2, "hl-0.72"], ["hw-0.2", 1.2, "hl-0.66"], 0.15, 8, 0.0),
        brush("dark", "metal"), cyl(["hw+0.09", 0.98, -0.5], ["hw+0.09", 0.98, 0.1], 0.1, 8, 0.0),
        brush("acc"), cyl(["hw+0.09", 0.98, -0.28], ["hw+0.09", 0.98, -0.22], 0.11, 8, 0.0)]}]
    styles = {
        "han": han,
        "han.china": {"extends": "han", "emblem": "hex_notch", "kit": {"skirt": "layered"}, "palette": {"acc": "#de4649"}, "slots": {"deck": china_deck}},
        "han.vietnam": {"extends": "han", "emblem": "triple_bar", "kit": {"skirt": "fabric"}, "palette": {"acc": "#bc044e"}, "slots": {"deck": vietnam_deck}},
        "han.cambodia": {"extends": "han", "emblem": "ring", "palette": {"acc": "#ab360a"}, "slots": {"deck": cambodia_deck}},
    }
    write(ROOT / "styles" / "han.json", {"schema": "meridian.styles/1", "styles": dict(sorted(styles.items()))})


# ------------------------------------------------------------------------------------------------ infantry
def mini_crown(x: Any, y: Any, z: Any, r: float = 0.12, h: float = 0.15, n: int = 4) -> List[Op]:
    """Backpack crown for infantry (cheap: disc + n tines + core, RADAR part)."""
    return [
        ["tier", 0], brush("metal", "metal"), cyl([x, y, z], [x, f"({y})+0.1", z], 0.018, 5, 0.0),
        part("radar", [x, f"({y})+0.1", z], [
            brush("sec"), cyl([x, f"({y})+0.1", z], [x, f"({y})+0.125", z], r, 8, 0.0),
            brush("acc"),
            {"for": "k", "n": n, "do": [box([f"({x})+cos(k*TAU/{n})*{r}", f"({y})+{0.125 + h * 0.5}", f"({z})+sin(k*TAU/{n})*{r}"], [0.035, h, 0.035], 0.0)]},
            brush("mix(light,base,0.35)", "emissive"), box([x, f"({y})+0.15", z], [0.06, 0.05, 0.06], 0.0),
        ], extra=0.3),
    ]


def at_member(i: str, n: int, ph: str, body: List[Op], rad: float = 0.42) -> List[Op]:
    """Attach `body` (soldier-local coords) to squad member `i` of `n` (inf_rifle / inf_at / inf_support diamond layout)."""
    a0 = "PI*0.5" if n == 2 else "0"
    fx = "0" if n == 1 else f"sin({i}*TAU/{n}+{a0})*{rad}"
    fz = "0" if n == 1 else f"-cos({i}*TAU/{n}+{a0})*{rad}"
    return [["member", int(i), n],
            part("body_bob", [0, 0, 0], [push([fx, 0, fz], body)], param=ph, extra=0),
            ["member", 0, 0]]


def build_infantry() -> None:
    # Banner Infantry: the bearer at the back of the diamond carries a crimson banner on a porcelain-topped pole.
    banner = [["tier", 1], brush("metal", "metal"), box([0.0, 0.97, 0.3], [0.022, 0.46, 0.022], 0.0),
              brush("acc"), box([0.0, 1.09, 0.45], [0.02, 0.2, 0.3], 0.0),
              brush("sec"), box([0.0, 1.21, 0.3], [0.05, 0.05, 0.05], 0.0), ["tier", 0]]
    write_unit("unit.han.banner_infantry", "inf_rifle", params={"helmet": "wrap"}, slots={"gear": at_member("2", 4, "0.625", banner)})
    # Lance Team: crimson band + flared porcelain back-blast cone on each tube
    lance: List[Op] = []
    for i in range(2):
        lance += at_member(str(i), 3, f"({i}+0.5)/3", [
            ["tier", 2], brush("acc"), cyl([0.2, 0.72, -0.28], [0.2, 0.72, -0.36], 0.088, 8, 0.0),
            brush("sec"), ["frustum", [0.2, 0.72, 0.25], [0.2, 0.72, 0.4], 0.065, 0.12, 8], ["tier", 0]], rad=0.44)
    write_unit("unit.han.lance_team", "inf_at", params={"helmet": "wrap"}, slots={"gear": lance})
    # Link Operator: backpack mast + crown (the 5-cell command-field provider must read)
    op = mini_crown(0.1, 0.84, 0.3, r=0.13, h=0.17)
    write_unit("unit.han.link_operator", "inf_support", params={"gadget": "radio", "helmet": "wrap"},
               slots={"gear": at_member("0", 2, "0.25", op, rad=0.36)})
    # Canopy Ranger: brown leaf-clip mantle over the jade tunic, round helmet, 3 members (the mantles would not fit the 1.4k
    # triangle budget of a 4-man squad)
    mantle: List[Op] = []
    for i in range(3):
        mantle += at_member(str(i), 3, f"({i}+0.5)/3", [["tier", 1], brush("mix(acc,dark,0.55)"), cyl([-0.25, 0.78, 0.04], [0.25, 0.78, 0.04], 0.15, 4, 0.0), ["tier", 0]])
    write_unit("unit.han.canopy_ranger", "inf_rifle", params={"helmet": "round", "n": 3}, slots={"gear": mantle})
    # Mekong Field Engineer: hard-hat, tool belt, folding boom antenna (DEPLOY part: rests along the back, rises on the 2 s
    # deployment) + mini crown
    boom = [["tier", 1], brush("acc"), box([0, 0.5, 0.0], [0.42, 0.05, 0.26], 0.005),
            brush("metal", "metal"), cyl([0.0, 0.7, 0.3], [0.0, 0.84, 0.3], 0.02, 5, 0.0),
            part("deploy", [0.0, 0.78, 0.34], [brush("metal", "metal"), box([0.0, 0.78, 0.66], [0.028, 0.028, 0.6], 0.0),
                                                 brush("sec"), ["dome", [0.0, 0.78, 0.96], [0, 0, 1], 0.075, 0.05, 8, 2]], param=0.143), ["tier", 0]] + mini_crown(0.0, 0.84, 0.3, r=0.11, h=0.14)
    write_unit("unit.han.mekong_field_engineer", "inf_support", params={"gadget": "tool", "helmet": "cap"},
               slots={"gear": at_member("0", 2, "0.25", boom, rad=0.36)})


# ------------------------------------------------------------------------------------------------ vehicles
def plate(cx: Any, cy: Any, cz: Any, w: Any, l: Any) -> Op:
    """Team plate (three-layer: dark gasket + team field) through the archetype macro."""
    return {"call": "team_panel", "args": {"center": [cx, cy, cz], "size": [w, 0.02, l]}}


def fenders(x: Any, y: Any, zc: Any, l: Any, w: Any = 0.18) -> Op:
    """Team stripes on both track covers (art direction 5.4.3: second plate so one stays visible when the turret turns)."""
    return {"mirror_x": [plate(x, y, zc, w, l)]}


def lantern(x: Any, y: Any, z: Any, r: float = 0.09) -> List[Op]:
    """Crimson dot lantern (emissive, command units)."""
    return [brush("acc", "emissive"), ["dome", [x, y, z], [0, 1, 0], r, r * 0.95, 8, 2]]


def eye(x: Any, y: Any, z: Any, w: float = 0.16, h: float = 0.07, bezel: bool = True) -> List[Op]:
    """Unmanned-unit 'eye' lens: emissive jade slot facing -Z (dark bezel behind it)."""
    bz: List[Op] = [brush("dark", "metal"), box([x, y, f"({z})+0.012"], [w + 0.05, h + 0.04, 0.03], 0.0)] if bezel else []
    return bz + [brush("mix(light,base,0.35)", "emissive"), box([x, y, z], [w, h, 0.03], 0.0)]


def tank_ops(guard: bool) -> List[Op]:
    """Extras on top of veh_tank: porcelain turret cap, crown (behind the team plate), parked drone."""
    turret: List[Op] = [
        brush("sec"),
        cyl(["-turret_hw*0.05", "top_y+0.004", "turret_z-0.46"], ["-turret_hw*0.05", "top_y+0.03", "turret_z-0.46"], 0.16, 10, 0.0),
    ]
    if guard:
        # porcelain shoulder plates with a crimson top line on both turret cheeks
        turret += [{"mirror_x": [brush("sec"), box(["turret_hw*0.98+0.05", "ty0+turret_h*0.5", "turret_z+0.02"], [0.1, "turret_h*0.8", "turret_hl*1.1"], 0.012),
                                 brush("acc"), box(["turret_hw*0.98+0.05", "ty0+turret_h*0.9", "turret_z+0.02"], [0.11, 0.05, "turret_hl*1.12"], 0.0)]}]
        turret += crown(0, "top_y", "turret_z+0.5", 0.15, 0.15, n=8, spin=0.3)
    else:
        turret += crown(0, "top_y", "turret_z+0.47", 0.17, 0.26)
    ops: List[Op] = [part("turret", [0, "hull_top", "turret_z"], turret), fenders("hw+0.1", 0.998, 0.1, 0.95)] + \
        emblem_cheeks(0, 0.7, "track_x+track_w*0.5+0.106", 0.3)
    if guard:
        # fume extractor on the long gun (same barrel part as the archetype's gun macro)
        ops.append(part("barrel", [0, "hull_top", "turret_z"], [
            brush("sec"), cyl([0, "gy", "fz-0.14-barrel_len*0.36+0.17"], [0, "gy", "fz-0.14-barrel_len*0.36-0.17"], "barrel_r*2.1", 10, 0.01),
            brush("acc"), cyl([0, "gy", "fz-0.14-barrel_len*0.36-0.17"], [0, "gy", "fz-0.14-barrel_len*0.36-0.21"], "barrel_r*2.2", 10, 0.0)],
            param=0.12, extra=0.32))
    else:
        ops += drone(0.12, "hull_top+0.14", "hl*0.55+0.25", 1.0)
    return ops


def build_vehicles() -> None:
    write_unit("unit.han.ox_tank", "veh_tank", params={"roof": "none"}, ops_after=tank_ops(False))
    write_unit("unit.han.imperial_guard_tank", "veh_tank", params={
        "roof": "none", "len": 3.3, "hull_w": 1.86, "hull_top": 1.12, "glacis": 0.9, "turret_hw": 0.78, "turret_hl": 0.78,
        "barrel_len": 2.55, "barrel_r": 0.072, "muzzle": "plain", "aps": True, "deck": "none"},
        ops_after=tank_ops(True))

    # Firefly AA drone: quad-tube pod on a round jade turret, eye lens, crown (detector)
    fire: List[Op] = [
        brush("base"), cyl(["-hw*0.45", "deck_y+0.11", "-hl+0.55"], ["-hw*0.45", "deck_y+0.2", "-hl+0.55"], 0.19, 6, 0.0),
        part("turret", [0, "deck_y", "tur_z"], eye(0, "ty0+0.16", "tur_z-tur_hl*0.96", 0.3, 0.1, bezel=False)),
    ] + crown(0, "deck_y", "rz", 0.24, 0.3, spin=0.3, tier=2) + [fenders("hw+0.1", 0.913, 0.2, 1.4)]
    write_unit("unit.han.firefly_aa_drone", "veh_aa", params={"payload": "missile", "roof": "crown", "skirt": "slab", "turret_n": 8, "turret_rot": 22.5, "tur_hw": 0.7, "tur_hl": 0.68},
               ops_after=fire)

    # Nest Rocket Drone: 12-tube modular launcher; the cab is closed over into a sensor head with an eye lens
    nest: List[Op] = [
        brush("base"), box([0, "deck_y+0.36", "-(cab_z0+0.65)"], ["2*(hw-0.14)+0.06", 0.74, 1.34], 0.05),
        brush("sec"), box([0, "deck_y+0.75", "-(cab_z0+0.2)"], ["2*(hw-0.14)-0.1", 0.05, 0.36], 0.02),
        ] + eye(0, "deck_y+0.42", "-(cab_z0+1.32)", 0.5, 0.12) + [
        {"call": "team_panel", "args": {"center": [0, "deck_y+0.785", "-(cab_z0+0.4)"], "size": ["hw*1.0", 0.02, 0.5]}},
        fenders("hw+0.1", 0.913, 0.0, 1.6),
    ]
    write_unit("unit.han.nest_rocket_drone", "veh_rocket", params={"pods": "grid", "unmanned": True, "roof": "crown"}, ops_after=nest)

    # Jade Carrier: compact 4-wheel box, porcelain cab, roof drone rack, crown on the cab (detector)
    write_unit("unit.han.jade_carrier", "veh_apc", params={"axles": 2, "body_len": 3.3, "body_w": 1.66, "roof": "drone_rack", "deck": "none", "skirt": "modules"},
               ops_after=crown(-0.34, "body_top", -0.55, 0.13, 0.2, spin=0.3, tier=1) + drone(0.12, "body_top+0.06", "hl*0.52+0.02", 0.8) + [plate(0.28, "body_top+0.012", -0.72, 0.5, 0.55)])

    # Lotus Drone Tender: Jade hull with a 4-petal drone dock ring and a manipulator arm on the roof
    petals: List[Op] = []
    for a in range(4):
        petals.append(push([0, "body_top+0.1", "hl*0.52+0.12"], [push([0.16, 0.0, 0.0], [
            brush("sec" if a % 2 == 0 else "base"), box([0.3, 0.0, 0.0], [0.6, 0.04, 0.38], 0.006),
            brush("acc"), box([0.61, 0.0, 0.0], [0.04, 0.05, 0.39], 0.0)], [0, 0, 46])], [0, a * 90 + 45, 0]))
    petals.append(brush("dark")); petals.append(cyl([0, "body_top+0.1", "hl*0.52+0.12"], [0, "body_top+0.14", "hl*0.52+0.12"], 0.2, 10, 0.0))
    arm: List[Op] = [brush("dark", "metal"), cyl(["-hw*0.55", "body_top", "-0.35"], ["-hw*0.55", "body_top+0.12", "-0.35"], 0.11, 8, 0.0),
                     push(["-hw*0.55", "body_top+0.12", "-0.35"], [
                         brush("dark"), box([0, 0.26, 0], [0.09, 0.5, 0.09], 0.0), brush("acc"), box([0, 0.52, 0], [0.12, 0.1, 0.12], 0.0),
                         push([0, 0.52, 0], [brush("dark"), box([0, 0, -0.32], [0.08, 0.08, 0.6], 0.0), brush("acc"), box([0, 0, -0.64], [0.14, 0.06, 0.1], 0.0)], [-18, 0, 0])])]
    write_unit("unit.han.lotus_drone_tender", "veh_apc", params={"axles": 2, "body_len": 3.3, "body_w": 1.66, "roof": "none", "deck": "none", "skirt": "modules"},
               ops_after=petals + drone(0, "body_top+0.14", "hl*0.52+0.12", 0.75) + arm + [plate(0.28, "body_top+0.012", -0.72, 0.5, 0.55)])

    # Reed Rocket Skimmer: small amphibious hover skimmer, rocket pod, reed-green skirt + float collar, unmanned (eye)
    reed: List[Op] = [brush("mix(base,sec,0.4)"), {"for": "j", "n": 9, "do": [{"mirror_x": [box(["hw+0.06", 0.62, "-hl+0.45+j*(lb_len-0.9)/8"], [0.05, 0.42, "(lb_len-0.9)/8-0.05"], 0.005)]}]},
                      brush("sec"), {"mirror_x": [cyl(["hw+0.03", 0.36, "-hl+0.3"], ["hw+0.03", 0.36, "hl-0.3"], 0.13, 8, 0.01)]},
                      plate(0, 1.045, "-hl+1.45", 0.9, 0.5)]
    write_unit("unit.han.reed_rocket_skimmer", "veh_lightarty", params={"chassis": "skimmer", "payload": "rocket_pod", "roof": "none"}, ops_after=reed)

    # ---- walkers
    lanterns: List[Op] = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            lanterns += lantern(f"{sx}*(hw-0.05)", "body_y+0.9", f"{sz}*(hl-0.65)", 0.16)
    wplates: List[Op] = [{"mirror_x": [plate("hw-0.5", "body_top+0.075", "hl*0.28", 0.5, 0.6)]}]
    write_unit("unit.han.dragon_command_walker", "veh_walker", params={"roof": "none"}, ops_after=lanterns + wplates)
    # Long Command Walker: wider stance, porcelain ID plates on the flanks, outrigger ring (front/rear pads join the side ones on deploy)
    plates: List[Op] = [brush("sec")]
    for sx in (-1, 1):
        for k in (-1, 0, 1):
            plates.append(box([f"{sx}*(hw+0.255)", "body_y+0.55", k * 0.42], [0.02, 0.2, 0.3], 0.0))
    ring: List[Op] = [brush("sec"),
                      box([0, "body_y+0.14", "-(hl+0.42)"], ["body_w+1.3", 0.22, 0.3], 0.02), box([0, "body_y+0.14", "hl+0.42"], ["body_w+1.3", 0.22, 0.3], 0.02),
                      {"mirror_x": [box(["hw+0.55", "body_y+0.14", 0], [0.3, 0.22, "body_len+1.1"], 0.02)]},
                      brush("acc"),
                      box([0, "body_y+0.26", "-(hl+0.42)"], ["body_w+1.34", 0.04, 0.32], 0.0), box([0, "body_y+0.26", "hl+0.42"], ["body_w+1.34", 0.04, 0.32], 0.0),
                      {"mirror_x": [box(["hw+0.55", "body_y+0.26", 0], [0.32, 0.04, "body_len+1.14"], 0.0)]},
                      plate(0, "body_y+0.29", "-(hl+0.42)", 1.6, 0.18), plate(0, "body_y+0.29", "hl+0.42", 1.6, 0.18)]
    # command-field extension: a second, interleaved ring of tines that rises 0.7 m on the 3 s deployment (SLIDE_Y)
    ext: List[Op] = [part("slide_y", [0, "body_top+0.6", "hl-0.55"], [
        brush("acc"), {"for": "k", "n": 8, "do": [box(["cos((k+0.5)*TAU/8)*0.42", "body_top+0.98", "hl-0.55+sin((k+0.5)*TAU/8)*0.42"], [0.06, 0.34, 0.06], 0.0)]},
        brush("mix(light,base,0.35)", "emissive"), {"for": "k", "n": 8, "do": [box(["cos((k+0.5)*TAU/8)*0.42", "body_top+1.17", "hl-0.55+sin((k+0.5)*TAU/8)*0.42"], [0.08, 0.05, 0.08], 0.0)]}],
        extra=0.7)]
    rig: List[Op] = []
    for (pz, ang, prm) in (("-(hl+0.05)", 45, 0.857), ("hl+0.05", 135, 0.143)):
        rig.append(part("deploy", [0, "body_y+0.3", pz], [push([0, "body_y+0.3", pz], [
            brush("metal", "metal"), box([0, 0, 0.5], [0.16, 0.14, 1.0], 0.02), brush("acc"), box([0, 0, 1.02], [0.34, 0.1, 0.3], 0.03)], [ang, 0, 0])], param=prm))
    write_unit("unit.han.long_command_walker", "veh_walker",
               params={"roof": "none", "stance_x": 2.45, "stance_z": 1.75, "body_w": 2.6, "body_len": 3.9, "knee_y": 1.6},
               ops_after=lanterns + wplates + plates + ring + ext + rig)

    # ---- air
    fair: List[Op] = [
        brush("base"), ["extrude", [[-0.55, 0.9], [-0.35, 1.2], [0.4, 1.27], [1.2, 1.1], [1.8, 0.95], [1.2, 0.9], [-0.5, 0.88]], -0.17, 0.17, 0.03],
        brush("sec"), ["extrude", [[-0.3, 1.19], [0.4, 1.265], [1.15, 1.115], [0.4, 1.28], [-0.3, 1.21]], -0.06, 0.06, 0.0],
    ] + eye(0, 0.98, -1.95, 0.14, 0.05) + [
        {"mirror_x": [brush("acc"), box([1.92, 0.7, 1.32], [0.24, 0.03, 0.78], 0.0), box([0.42, 1.05, 1.9], [0.04, 0.5, 0.5], 0.0)]}]
    write_unit("unit.han.swallow_interceptor", "air_jet", params={"wing": "swept", "tail": "twin"}, ops_after=fair)
    # Silkwing: crimson leading-edge strips, porcelain trailing-edge strips, jade eye at the nose (flying-wing plan)
    wing: List[Op] = [{"mirror_x": [
        push([1.79, 1.0, -0.4], [brush("acc"), box([0, 0, 0], [4.9, 0.03, 0.2], 0.0)], [0, -48.7, 0]),
        push([1.9, 1.0, 1.75], [brush("sec"), box([0, 0, 0], [3.7, 0.03, 0.16], 0.0)], [0, 9.0, 0]),
    ]}] + eye(0, 0.86, -2.62, 0.5, 0.06)
    write_unit("unit.han.silkwing_drone_bomber", "air_bomber", ops_after=wing)

    # ---- ships
    rackpad: List[Op] = [brush("metal", "metal"), box([0, "fb+0.03", "hl*0.5+0.4"], [0.5, 0.05, 0.55], 0.0)] + drone(0, "fb+0.06", "hl*0.5+0.4", 1.1)
    write_unit("unit.han.canal_patrol_boat", "ship_patrol", params={"cabin": "closed", "gun": "auto", "roof": "none"},
               ops_after=rackpad + crown(0, "fb+0.72", "hl*0.05-0.6", 0.15, 0.2, spin=0.3) + [plate(0, "fb+0.03", -0.66, 1.0, 0.36)])
    esc: List[Op] = crown(0, "fb+1.7", "-hl*0.12-0.75", 0.22, 0.3, spin=0.3) + [brush("metal", "metal"), box([0, "fb+0.09", "hl-0.85"], [1.5, 0.05, 1.3], 0.0)] + \
        drone(-0.4, "fb+0.11", "hl-0.85", 1.7) + drone(0.4, "fb+0.11", "hl-0.85", 1.7) + [{"mirror_x": [plate("se_beam*0.5-0.35", "fb+0.05", "hl-0.85", 0.4, 1.3)]}]
    write_unit("unit.han.jade_escort", "ship_escort", params={"helipad": False, "vls_rows": 2, "roof": "none"}, ops_after=esc)
    emp: List[Op] = crown("sc_beam*0.5-0.3", "fb+3.5", "-hl*0.05+0.6", 0.3, 0.42, n=8, spin=0.3)
    write_unit("unit.han.emperor_drone_ship", "ship_carrier", params={"deck": "drones", "roof": "none"}, ops_after=emp)


# ------------------------------------------------------------------------------------------------ structures
def build_structures() -> None:
    y0 = 0.16
    # Dragon Tooth Launcher: the macro's tapering tower gets two shrinking porcelain/crimson eave tiers, a crown and two crimson
    # lanterns on the cap, and a parked drone pair on the front apron.
    tooth: List[Op] = [
        brush("sec"), box([0, y0 + 1.42, 0], [3.2, 0.12, 3.2], 0.02), box([0, y0 + 2.0, 0], [2.92, 0.12, 2.92], 0.02),
        brush("acc"), box([0, y0 + 1.5, 0], [3.34, 0.07, 3.34], 0.01), box([0, y0 + 2.08, 0], [3.06, 0.07, 3.06], 0.01),
        {"mirror_x": lantern(1.18, y0 + 2.8, 1.18, 0.14) + lantern(1.18, y0 + 2.8, -1.18, 0.14)},
    ] + crown(1.08, y0 + 2.74, -1.08, 0.2, 0.3, spin=0.3, tier=1) + [
        {"mirror_x": [plate(1.16, y0 + 2.744, 0.0, 0.3, 1.6)]},
        brush("metal", "metal"), box([-1.6, y0 + 0.03, 2.1], [1.3, 0.05, 0.75], 0.0)] + drone(-1.85, y0 + 0.06, 2.1, 0.9) + drone(-1.35, y0 + 0.06, 2.1, 0.9)
    write_struct("structure.han.dragon_tooth_launcher", "str_defense_adv", {"kit": "dragon_tooth"}, tooth)

    # Dragonfall Field Foundry: the assembly hall gets a second, shrinking tier with a porcelain cap and a crimson eave, the big
    # sensor crown on the gantry arch and crimson lanterns on its ends; the three capsule cradles are the drone-rack analogue.
    hall: List[Op] = [
        brush("base"), box([2.2, y0 + 5.43, -3.55], [5.6, 1.3, 2.9], 0.04),
        brush("sec"), box([2.2, y0 + 6.16, -3.55], [6.0, 0.16, 3.2], 0.03),
        brush("acc"), box([2.2, y0 + 6.27, -3.55], [6.2, 0.07, 3.4], 0.01),
        brush("mix(light,base,0.35)", "emissive"), {"for": "i", "n": 5, "do": [box(["2.2+(i-2)*1.0", y0 + 5.5, -2.08], [0.14, 0.5, 0.03], 0.0)]},
    ] + crown(0, y0 + 6.98, 2.2, 0.7, 0.95, n=8, spin=0.2, tier=0) + lantern(-5.3, y0 + 7.0, 2.2, 0.3) + lantern(5.3, y0 + 7.0, 2.2, 0.3)
    write_struct("structure.han.dragonfall_field_foundry", "str_superweapon", {"kit": "assembly_hall"}, hall)


def write_struct(sid: str, archetype: str, params: Dict[str, Any], ops: List[Op]) -> None:
    write_unit(sid, archetype, params=params, slots={"extra": []}, ops_after=ops)


def build_units() -> None:
    build_infantry()
    build_vehicles()


def main() -> int:
    only = ""
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
    build_styles()
    build_units()
    build_structures()
    return 0


if __name__ == "__main__":
    sys.exit(main())
