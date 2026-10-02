"""Authoring helpers for the African Empire recipes (VIEW-M8, F-ae).

The files under game/data/recipes/{unit,structure,summon}.ae.*.json and styles/ae.json are HAND-AUTHORED data; this folder is the
script that wrote them (shared snippets such as bolted patch plates, cyan lock collars, cranes live here once). Run `./all.sh` to
regenerate every AE recipe; then `python3 tools/py/validate_recipes.py` and `tools/gd test view_ae`. Editing the JSON by hand is
also fine - the generator only ever writes the AE ids listed in all.sh."""
import json, os
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "game", "data", "recipes"))

def add(a, d):
    """a + d where either may be an expression string."""
    if isinstance(a, (int, float)) and isinstance(d, (int, float)):
        return round(a + d, 4)
    if isinstance(d, (int, float)) and d == 0:
        return a
    if isinstance(a, (int, float)) and a == 0:
        return d
    return "(%s)+(%s)" % (a, d)

TONES = ["base", "base*0.82", "mix(dark,base,0.3)", "base*1.12"]
def tone(i):
    return TONES[i % 4]

def box(c, s, col=None, bev=0.012, mat=None):
    ops = []
    if col is not None:
        b = ["brush", col]
        if mat: b.append(mat)
        ops.append(b)
    ops.append(["box", c, s, bev])
    return ops

def bolt_quad(c, s, r=0.028, h=0.03):
    ops = [["tier", 2], ["brush", "metal", "metal"]]
    for sx in (-1, 1):
        for sz in (-1, 1):
            p = [add(c[0], round(sx * s[0] * 0.38, 4)), add(c[1], round(s[1] * 0.5, 4)), add(c[2], round(sz * s[2] * 0.38, 4))]
            q = [p[0], add(p[1], h), p[2]]
            ops.append(["cyl", p, q, r, 6, 0.0])
    ops.append(["tier", 0])
    return ops

def plate(c, s, col, bolts=True, bev=0.012):
    ops = box(c, s, col, bev)
    if bolts:
        ops += bolt_quad(c, s)
    return ops

def write_recipe(rid, obj):
    path = os.path.join(ROOT, rid + ".json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")

def recipe(rid, archetype, params=None, slots=None, ops_after=None, sockets=None, meta=None, scale=None, style="auto"):
    d = {"schema": "meridian.recipe/1", "id": rid, "archetype": archetype, "style": style}
    if scale: d["scale"] = scale
    if params: d["params"] = params
    if slots is not None: d["slots"] = slots
    if ops_after: d["ops_after"] = ops_after
    if sockets: d["sockets"] = sockets
    if meta: d["meta"] = meta
    write_recipe(rid, d)

def bolts_top(c, s, n=2, axis="z"):
    """n bolt heads (4-seg) along the given axis on the top face."""
    ops = [["tier", 2], ["brush", "metal", "metal"]]
    for k in range(n):
        t = (k / max(n - 1, 1) - 0.5) * 0.76
        if axis == "z":
            p = [c[0], add(c[1], round(s[1] * 0.5, 4)), add(c[2], round(t * s[2], 4))]
        else:
            p = [add(c[0], round(t * s[0], 4)), add(c[1], round(s[1] * 0.5, 4)), c[2]]
        ops.append(["cyl", p, [p[0], add(p[1], 0.03), p[2]], 0.03, 4, 0.0])
    ops.append(["tier", 0])
    return ops

def patch(c, s, col, n=2, axis="z", bev=0.01):
    """a bolt-on repair patch: plate + n bolt heads."""
    return box(c, s, col, bev) + (bolts_top(c, s, n, axis) if n else [])

def loop(var, n, do):
    return {"for": var, "n": n, "do": do}

def mirror(do):
    return {"mirror_x": do}

def part(kind, do, pivot=None, param=None, extra=None, trunnion=None):
    p = {"kind": kind}
    if pivot is not None: p["pivot"] = pivot
    if param is not None: p["param"] = param
    if extra is not None: p["extra"] = extra
    if trunnion is not None: p["trunnion"] = trunnion
    return {"part": p, "do": do}

def push(pos, do, euler=None):
    d = {"pos": pos}
    if euler is not None: d["euler"] = euler
    return {"push": d, "do": do}

def call(name, **args):
    return {"call": name, "args": args}

def glow(p0, p1, r, segs=10, col="acc"):
    """emissive cyan lock collar / ring between two points."""
    return [["brush", col, "emissive"], ["cyl", p0, p1, r, segs, 0.0]]

def cyan_dot(c, s=(0.05, 0.10, 0.10)):
    return [["brush", "acc", "emissive"], ["box", c, list(s), 0.0]]

def crane(x, z, y0, h, jib, yaw=0.0, r=0.07, lamp=True):
    """jib crane: mast (dark), slewed jib (box), cable + hook, cyan lamp at the tip. Coordinates are expressions or numbers."""
    top = add(y0, h)
    ops = [["brush", "dark", "metal"],
           ["cyl", [x, y0, z], [x, top, z], r, 6, 0.0],
           ["brush", "sec"],
           ["box", [x, add(y0, 0.18), z], [0.3, 0.36, 0.3], 0.0],
           push([x, top, z], [
               ["brush", "base*0.82"],
               ["box", [0, 0.05, "%s*-0.45" % jib], [0.1, 0.1, jib], 0.0],
               ["box", [0, 0.16, 0.12], [0.16, 0.16, 0.24], 0.0],
               ["brush", "metal", "metal"],
               ["cyl", [0, 0.0, "%s*-0.9" % jib], [0, -h * 0.28 if isinstance(h, (int, float)) else "-(%s)*0.28" % h, "%s*-0.9" % jib], 0.012, 4, 0.0, False],
               ["box", [0, -h * 0.28 - 0.04 if isinstance(h, (int, float)) else "-(%s)*0.28-0.04" % h, "%s*-0.9" % jib], [0.09, 0.07, 0.06], 0.0],
           ] + ([["brush", "acc", "emissive"], ["box", [0, 0.12, "%s*-1.0" % jib], [0.07, 0.07, 0.07], 0.0]] if lamp else []), [0, yaw, 0])]
    return ops
