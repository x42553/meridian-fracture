"""Helpers for the PD recipe generator (author-side only; output is plain JSON under game/data/recipes).

Run `python3 tools/py/gen_pd_recipes/gen_all.py [id-substring ...]` to rewrite styles/pd.json and the 21 authored PD recipes
(19 units, structure.pd.sea_spear_battery, structure.pd.tempest_swarm_hub). The JSON files are the source of truth: edit either side,
but a regeneration overwrites the recipe files."""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "data", "recipes")


def dump(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)
        f.write("\n")


def C(name, **args):
    return {"call": name, "args": args}


def LET(**kw):
    return {"let": kw}


def SLOT(name):
    return {"slot": name}


def MIR(*ops):
    return {"mirror_x": list(ops)}


def PUSH(pos, euler, *ops):
    d = {"pos": pos}
    if euler is not None:
        d["euler"] = euler
    return {"push": d, "do": list(ops)}


def PART(kind, pivot=None, param=None, extra=None, trunnion=None, *ops):
    d = {"kind": kind}
    if pivot is not None:
        d["pivot"] = pivot
    if param is not None:
        d["param"] = param
    if extra is not None:
        d["extra"] = extra
    if trunnion is not None:
        d["trunnion"] = trunnion
    return {"part": d, "do": list(ops)}


def FOR(var, n, *ops):
    return {"for": var, "n": n, "do": list(ops)}


def IF(cond, then, els=None):
    d = {"if": cond, "then": list(then)}
    if els is not None:
        d["else"] = list(els)
    return d


def SWITCH(expr, cases, default=None):
    d = {"switch": expr, "cases": cases}
    if default is not None:
        d["default"] = default
    return d


def BR(col, mat=None, team=None):
    a = ["brush", col]
    if mat is not None:
        a.append(mat)
    if team is not None:
        a.append(team)
    return a


def BOX(c, size, bevel=0.0):
    return ["box", c, size, bevel]


def CYL(a, b, r, segs=10, bevel=0.0, caps=True):
    return ["cyl", a, b, r, segs, bevel, caps]


def FRU(a, b, r0, r1, segs=10, caps=True):
    return ["frustum", a, b, r0, r1, segs, caps]


def DOME(base, up, r, h, segs=12, rings=3):
    return ["dome", base, up, r, h, segs, rings]


def TIER(n):
    return ["tier", n]


def recipe(rid, arch, params=None, slots=None, ops_after=None, meta=None, scale=None):
    r = {"schema": "meridian.recipe/1", "id": rid, "archetype": arch, "style": "auto"}
    if scale is not None:
        r["scale"] = scale
    if params:
        r["params"] = params
    if slots:
        r["slots"] = slots
    r["ops_after"] = ops_after or []
    if meta:
        r["meta"] = meta
    return r


def write_recipe(r):
    dump(os.path.join(ROOT, r["id"] + ".json"), r)


# ------------------------------------------------------------------------------------------ kit slots (per archetype family, see gen_style.ANCH)
def BAND(fam):
    return [SLOT("band_" + fam)]


def PAT(fam):
    return [SLOT("pat_" + fam)]


def EMB(fam):
    return [SLOT("emb_" + fam)]


def TOP(fam):
    return [SLOT("top_" + fam)]


def SPONSON(x, y, r, zr, zf, rings=(0.0,), nose=0.4, col="sec", segs=8):
    """White flotation sponson pair (mirror_x) with coral rings; zr rear z, zf front z (zf < zr). ~160 tris per side."""
    ops = [BR(col), CYL([x, y, zr], [x, y, zf], r, segs, 0.0),
           FRU([x, y, zf], [x, y, f"({zf})-{nose}"], r, f"{r}*0.3", segs),
           FRU([x, y, zr], [x, y, f"({zr})+0.16"], r, f"{r}*0.55", segs),
           TIER(2), BR("acc")]
    for z in rings:
        ops.append(CYL([x, y, f"({z})+0.05"], [x, y, f"({z})-0.05"], f"{r}+0.012", segs, 0.0))
    ops.append(TIER(0))
    return MIR(*ops)
