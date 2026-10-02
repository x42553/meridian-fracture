#!/usr/bin/env python3
"""Validate game/data/recipes (render spec 7.9, checks V-RCP-01 .. 12). Stdlib only, never writes.

  python3 tools/py/validate_recipes.py                 # everything
  python3 tools/py/validate_recipes.py --strict        # warnings fail too (exit 2)
  python3 tools/py/validate_recipes.py --only V-RCP-04,V-RCP-05     # report only these rules (prefixes work)
  python3 tools/py/validate_recipes.py --json          # machine-readable report
  python3 tools/py/validate_recipes.py --list-rules

Rules (V-RCP-09 is the Godot test tests/view/test_view_recipes.gd: it needs the mesh builder):
  01 every JSON file parses; schema matches; index / styles keys sorted; ids equal file names
  02 index.json equals the sorted list of recipe files; every unit / summon / structure / neutral def has a recipe (else the
     assignments rule that would generate it is named; a def with NO rule is a warning); footprints.json is current
  03 archetype, style, extends, slot, macro, op, part and material names exist
  04 recipe params are declared by the archetype and have the declared type; kit values of styles fit some archetype
  05 every expression parses (Python re-implementation of the ViewExpr grammar), every identifier resolves in the interpreter's
     compile-order scope, functions exist with the right arity, no division by a literal 0
  06 palette keys and hex colours are valid; a recipe (archetype + recipe ops) carries at least one team-masked surface
  07 for-loops are bounded (literal n <= 64, nesting <= 3) and op lists are at most 8 deep
  08 armed units have a muzzle0_0 socket; units with deployable_mode have DEPLOY / SLIDE parts or meta.deploy = "pose" (warning)
  10 structure recipes: door_exit socket anchored on door_cx / door_cz; refinery dock socket; airfield uses the pad variables
  11 style emblems belong to the abstract set (no real-world marks)
  12 styles/<faction>.json files only define ids of their own faction; palette / team_plate / material sanity; extends chains
Exit codes: 0 clean, 1 errors, 2 warnings (only with --strict), 3 usage error.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import recipe_lib as rl  # noqa: E402

RULES = {
    "V-RCP-01": "JSON parses, schema matches, sorted keys where required, ids equal file names",
    "V-RCP-02": "index.json / footprints.json current; every def has a recipe or a rule",
    "V-RCP-03": "archetype / style / extends / slot / macro / op / part / material names exist",
    "V-RCP-04": "recipe params declared by the archetype with the declared type",
    "V-RCP-05": "expressions parse, identifiers resolve, functions and arity, no literal division by zero",
    "V-RCP-06": "palette keys and colours valid; a team-masked surface exists",
    "V-RCP-07": "loops bounded, op-list depth",
    "V-RCP-08": "armed units have muzzle0_0; deployable units have deploy parts",
    "V-RCP-10": "structure anchors: door_exit, dock, pads",
    "V-RCP-11": "emblem values",
    "V-RCP-12": "styles/<faction>.json ownership, palette / material / team_plate sanity, extends",
}
EMBLEMS = {"none", "bar", "bar_notch", "triple_bar", "chevron", "double_chevron", "ring", "hex_notch", "wedge", "diamond"}
TEAM_PLATES = {"band", "panel", "none"}
SIZE_CLASSES = {"inf", "squad", "light", "medium", "heavy", "huge", "air", "ship", "structure"}
MATS = {"paint", "metal", "glass", "rubber", "emissive"}
MAX_FOR, MAX_NEST, MAX_DEPTH = 64, 3, 8
GLOBAL_NAMES = {"seed", "PI", "TAU", "true", "false"}
STYLE_KEYS = {"emblem", "kit", "material", "palette", "slots", "team_plate", "extends"}

E, W = "error", "warning"


# ---------------------------------------------------------------------------------------------- source facts
class Facts:
    """Names the interpreter and macros define, read from the GDScript sources (single source of truth)."""

    def __init__(self, view_src: Path = rl.VIEW_SRC) -> None:
        model = view_src / "model"
        interp = (model / "view_recipe_interpreter.gd").read_text(encoding="utf-8")
        expr = (model / "view_expr.gd").read_text(encoding="utf-8")
        book = (model / "view_recipe_book.gd").read_text(encoding="utf-8")
        self.prims: Dict[str, Tuple[str, int]] = {}
        blk = interp[interp.index("const PRIMS"):interp.index("const BLOCK_KEYS")]
        for m in re.finditer(r'"(\w+)": \[K\.\w+, "([^"]*)", (\d+)\]', blk):
            self.prims[m.group(1)] = (m.group(2), int(m.group(3)))
        allowed = interp[interp.index("const BLOCK_ALLOWED"):interp.index("const MATS")]
        self.block_allowed: Dict[str, List[str]] = {}
        for m in re.finditer(r'"(\w+)": \[([^\]]*)\]', allowed):
            self.block_allowed[m.group(1)] = re.findall(r'"(\w+)"', m.group(2))
        parts = interp[interp.index("const PARTS"):interp.index("const DEFAULT_PALETTE")]
        self.parts = set(re.findall(r'"(\w+)": \d+', parts))
        pal = interp[interp.index("const DEFAULT_PALETTE"):]
        pal = pal[:pal.index("}")]
        self.palette = set(re.findall(r'"(\w+)": "#', pal))
        fb = expr[expr.index("const FUNCS"):]
        fb = fb[:fb.index("\n}")]
        self.funcs = {m.group(1): int(m.group(2)) for m in re.finditer(r'"(\w+)": \[FN_\w+, (\d+)\]', fb)}
        mp = re.search(r"const MAX_PADS: int = (\d+)", book)
        self.max_pads = int(mp.group(1)) if mp else 8
        self.macros: Dict[str, Dict[str, Tuple[str, str]]] = {}
        self.team_macros: Set[str] = set()
        for fn in ("view_recipe_macros.gd", "view_macros_structures.gd", "view_macros_landmarks.gd"):
            self._read_macros((model / fn).read_text(encoding="utf-8"))
        # macros that forward to another macro file inherit the team flag conservatively via their own body text
        self.struct_vars = {"fw", "fh", "door_cx", "door_cz", "exit_dir", "dock_cx", "dock_cz", "dock_dir", "pads_n"}
        for i in range(self.max_pads):
            self.struct_vars.add("pad_x%d" % i)
            self.struct_vars.add("pad_z%d" % i)

    def _read_macros(self, src: str) -> None:
        sigs = src[src.index("const SIGS"):]
        sigs = sigs[:sigs.index("\n}")]
        for m in re.finditer(r'^\t"(\w+)": "([^"]*)",?', sigs, re.M):
            args: Dict[str, Tuple[str, str]] = {}
            for tok in m.group(2).split():
                head, _, dflt = tok.partition("=")
                name, _, typ = head.partition(":")
                args[name] = (typ, dflt)
            self.macros[m.group(1)] = args
        # team flag: macro -> function body mentions a team-masked brush or a team panel
        funcs = {}
        for fm in re.finditer(r"^static func (_\w+)\(.*?(?=^static func |\Z)", src, re.M | re.S):
            funcs[fm.group(1)] = fm.group(0)
        for dm in re.finditer(r'"(\w+)": (?:return )?(_\w+)\(', src):
            body = funcs.get(dm.group(2), "")
            if "_team_panel(" in body or "PAINT, 1.0" in body or "_team(" in body or "team_panel" in body:
                self.team_macros.add(dm.group(1))


# ---------------------------------------------------------------------------------------------- expression parser
class ExprError(Exception):
    pass


_TOK = re.compile(r"\s*(?:(\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)|([A-Za-z_][A-Za-z_0-9]*)|('[^']*')|(<=|>=|==|!=|[-+*/%<>?:(),]))")


def tokenize(src: str) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    pos = 0
    while pos < len(src):
        if src[pos:].strip() == "":
            break
        m = _TOK.match(src, pos)
        if not m:
            raise ExprError("unexpected '%s' at column %d" % (src[pos:].strip()[:1], pos + 1))
        pos = m.end()
        if m.group(1) is not None:
            out.append(("num", m.group(1)))
        elif m.group(2) is not None:
            out.append(("id", m.group(2)))
        elif m.group(3) is not None:
            out.append(("str", m.group(3)))
        else:
            out.append(("op", m.group(4)))
    return out


class ExprParser:
    """Recursive descent over the ViewExpr grammar; collects identifiers and reports functions / arity / literal /0."""

    def __init__(self, src: str, funcs: Dict[str, int]) -> None:
        self.toks = tokenize(src)
        self.i = 0
        self.funcs = funcs
        self.ids: Set[str] = set()
        self.warnings: List[str] = []

    def peek(self) -> Optional[Tuple[str, str]]:
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self) -> Tuple[str, str]:
        t = self.peek()
        if t is None:
            raise ExprError("unexpected end of expression")
        self.i += 1
        return t

    def accept(self, kind: str, val: str) -> bool:
        t = self.peek()
        if t is not None and t[0] == kind and t[1] == val:
            self.i += 1
            return True
        return False

    def parse(self) -> None:
        if not self.toks:
            raise ExprError("empty expression")
        self.ternary()
        if self.peek() is not None:
            raise ExprError("unexpected '%s'" % self.peek()[1])

    def ternary(self) -> None:
        self.orx()
        if self.accept("op", "?"):
            self.ternary()
            if not self.accept("op", ":"):
                raise ExprError("expected ':' in the conditional")
            self.ternary()

    def orx(self) -> None:
        self.andx()
        while self.accept("id", "or"):
            self.andx()

    def andx(self) -> None:
        self.notx()
        while self.accept("id", "and"):
            self.notx()

    def notx(self) -> None:
        if self.accept("id", "not"):
            self.notx()
        else:
            self.cmp()

    def cmp(self) -> None:
        self.add()
        t = self.peek()
        while t is not None and t[0] == "op" and t[1] in ("<", ">", "<=", ">=", "==", "!="):
            self.i += 1
            self.add()
            t = self.peek()

    def add(self) -> None:
        self.mul()
        t = self.peek()
        while t is not None and t[0] == "op" and t[1] in ("+", "-"):
            self.i += 1
            self.mul()
            t = self.peek()

    def mul(self) -> None:
        self.unary()
        t = self.peek()
        while t is not None and t[0] == "op" and t[1] in ("*", "/", "%"):
            self.i += 1
            nt = self.peek()
            if t[1] in ("/", "%") and nt is not None and nt[0] == "num" and float(nt[1]) == 0.0:
                raise ExprError("division by the literal 0")
            self.unary()
            t = self.peek()

    def unary(self) -> None:
        if self.accept("op", "-"):
            self.unary()
        else:
            self.primary()

    def primary(self) -> None:
        kind, val = self.take()
        if kind in ("num", "str"):
            return
        if kind == "op" and val == "(":
            self.ternary()
            if not self.accept("op", ")"):
                raise ExprError("missing ')'")
            return
        if kind == "id":
            if self.accept("op", "("):
                if val not in self.funcs:
                    raise ExprError("unknown function '%s'" % val)
                n = 0
                if not self.accept("op", ")"):
                    while True:
                        self.ternary()
                        n += 1
                        if self.accept("op", ")"):
                            break
                        if not self.accept("op", ","):
                            raise ExprError("expected ',' or ')' in the call of '%s'" % val)
                if n != self.funcs[val]:
                    raise ExprError("function '%s' takes %d argument(s), got %d" % (val, self.funcs[val], n))
                return
            if val in ("and", "or", "not"):
                raise ExprError("unexpected keyword '%s'" % val)
            self.ids.add(val)
            return
        raise ExprError("unexpected '%s'" % val)


def parse_expr(src: str, funcs: Dict[str, int]) -> Set[str]:
    p = ExprParser(src, funcs)
    p.parse()
    return p.ids


# ---------------------------------------------------------------------------------------------- report
class Issue:
    def __init__(self, rule: str, sev: str, where: str, msg: str) -> None:
        self.rule, self.sev, self.where, self.msg = rule, sev, where, msg

    def as_dict(self) -> Dict[str, str]:
        return {"rule": self.rule, "severity": self.sev, "where": self.where, "message": self.msg}


class Report:
    def __init__(self) -> None:
        self.issues: List[Issue] = []

    def add(self, rule: str, sev: str, where: str, msg: str) -> None:
        self.issues.append(Issue(rule, sev, where, msg))

    def err(self, rule: str, where: str, msg: str) -> None:
        self.add(rule, E, where, msg)

    def warn(self, rule: str, where: str, msg: str) -> None:
        self.add(rule, W, where, msg)

    def count(self, sev: str) -> int:
        return sum(1 for i in self.issues if i.sev == sev)


# ---------------------------------------------------------------------------------------------- op walker
class Walker:
    """Mirrors ViewRecipeInterpreter's compile pass over one effective op tree (archetype ops with the recipe's slots)."""

    def __init__(self, facts: Facts, rep: Report, palette_keys: Set[str], where: str) -> None:
        self.f = facts
        self.rep = rep
        self.pal = palette_keys
        self.where = where
        self.scope: Set[str] = set(GLOBAL_NAMES)
        self.slots: Dict[str, Any] = {}
        self.sockets: Dict[str, Any] = {}
        self.parts: Set[str] = set()
        self.macros_called: Set[str] = set()
        self.team = False
        self.meta: Dict[str, Any] = {}
        self.text_hits: Set[str] = set()   # identifiers used anywhere (for V-RCP-10 checks)
        self.slot_stack: List[str] = []
        self.max_depth = 0
        self.errors = 0

    def E(self, rule: str, path: str, msg: str) -> None:
        self.errors += 1
        self.rep.err(rule, self.where, "%s: %s" % (path, msg))

    # ---- expressions
    def expr(self, src: str, path: str, force: bool = True) -> None:
        try:
            ids = parse_expr(src, self.f.funcs)
        except ExprError as e:
            self.E("V-RCP-05", path, "%s in \"%s\"" % (e, src))
            return
        for name in ids:
            self.text_hits.add(name)
            if name not in self.scope:
                self.E("V-RCP-05", path, "unknown identifier '%s' in \"%s\"" % (name, src))

    def is_word(self, s: str) -> bool:
        return bool(re.fullmatch(r"[A-Za-z_][A-Za-z_0-9.]*", s))

    def num(self, v: Any, path: str) -> None:
        if isinstance(v, bool) or isinstance(v, (int, float)):
            return
        if isinstance(v, str):
            self.expr(v, path)
            return
        self.E("V-RCP-05", path, "expected a number or an expression, got %s" % type(v).__name__)

    def vec(self, v: Any, n: int, path: str) -> None:
        if not isinstance(v, list) or len(v) != n:
            self.E("V-RCP-05", path, "expected a vector of %d numbers" % n)
            return
        for x in v:
            self.num(x, path)

    def veclist(self, v: Any, n: int, path: str) -> None:
        if not isinstance(v, list):
            self.E("V-RCP-05", path, "expected a list of %d-vectors" % n)
            return
        for x in v:
            self.vec(x, n, path)

    def colour(self, v: Any, path: str) -> None:
        if isinstance(v, list) and len(v) == 3:
            if not all(isinstance(x, (int, float)) for x in v):
                self.E("V-RCP-06", path, "colour components must be numbers")
            return
        if not isinstance(v, str):
            self.E("V-RCP-06", path, "expected a colour")
            return
        if self.try_colour(v):
            return
        if v.startswith("#"):
            self.E("V-RCP-06", path, "invalid colour '%s'" % v)
            return
        if re.fullmatch(r"[A-Za-z_]\w*", v) and v not in self.scope:
            self.E("V-RCP-06", path, "unknown palette key '%s' (palette keys: %s)" % (v, ", ".join(sorted(self.pal))))
            return
        self.expr(v, path)

    def try_colour(self, s: str) -> bool:
        s = s.strip()
        if s in self.pal:
            return True
        if s.startswith("#"):
            return bool(re.fullmatch(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{8}|[0-9a-fA-F]{3})", s))
        if s.startswith("mix(") and s.endswith(")"):
            parts = s[4:-1].split(",")
            return len(parts) == 3 and self._isfloat(parts[2]) and self.try_colour(parts[0]) and self.try_colour(parts[1])
        star = s.rfind("*")
        if star > 0 and self._isfloat(s[star + 1:]):
            return self.try_colour(s[:star])
        return False

    @staticmethod
    def _isfloat(s: str) -> bool:
        try:
            float(s.strip())
            return True
        except ValueError:
            return False

    def gen(self, v: Any, path: str, force: bool = False) -> None:
        if isinstance(v, str):
            if v == "" or (not force and self.is_word(v) and v not in self.scope and v not in ("true", "false", "PI", "TAU")):
                return
            self.expr(v, path)
        elif isinstance(v, list):
            for x in v:
                self.gen(x, path, force)

    # ---- ops
    def run(self, ops: Any, path: str, depth: int = 1, nest: int = 0) -> None:
        if not isinstance(ops, list):
            self.E("V-RCP-03", path, "expected an op array")
            return
        if depth > MAX_DEPTH:
            self.E("V-RCP-07", path, "op-list depth exceeds %d" % MAX_DEPTH)
            return
        self.max_depth = max(self.max_depth, depth)
        for i, op in enumerate(ops):
            self.op(op, "%s[%d]" % (path, i), depth, nest)

    def op(self, op: Any, path: str, depth: int, nest: int) -> None:
        if isinstance(op, list):
            self.prim(op, path)
        elif isinstance(op, dict):
            self.block(op, path, depth, nest)
        else:
            self.E("V-RCP-03", path, "an op is an array [name, args...] or an object")

    def prim(self, op: List[Any], path: str) -> None:
        if not op or not isinstance(op[0], str):
            self.E("V-RCP-03", path, "an op array starts with its name")
            return
        name = op[0]
        if name not in self.f.prims:
            self.E("V-RCP-03", path, "unknown op '%s'" % name)
            return
        types, req = self.f.prims[name]
        args = op[1:]
        if len(args) < req:
            self.E("V-RCP-03", "%s/%s" % (path, name), "takes at least %d argument(s), got %d" % (req, len(args)))
            return
        if len(args) > len(types):
            self.E("V-RCP-03", "%s/%s" % (path, name), "takes at most %d argument(s), got %d" % (len(types), len(args)))
            return
        p = "%s/%s" % (path, name)
        for t, a in zip(types, args):
            self.typed(t, a, p)
        if name == "brush" and len(args) >= 3 and args[2] not in (0, 0.0, False):
            self.team = True
        if name == "brush" and len(args) >= 2 and isinstance(args[1], str) and args[1] not in MATS:
            self.E("V-RCP-03", p, "unknown material '%s' (%s)" % (args[1], ", ".join(sorted(MATS))))
        if name == "socket":
            self.sockets[str(args[0])] = args
            if len(args) >= 4 and isinstance(args[3], str) and args[3] not in self.f.parts and self.is_word(args[3]) and args[3] not in self.scope:
                self.E("V-RCP-03", p, "unknown part '%s'" % args[3])
        if name == "meta":
            self.meta[str(args[0])] = args[1] if len(args) > 1 else None

    def typed(self, t: str, a: Any, p: str) -> None:
        if t == "n":
            self.num(a, p)
        elif t == "v":
            self.vec(a, 3, p)
        elif t == "w":
            self.vec(a, 2, p)
        elif t == "c":
            self.colour(a, p)
        elif t in ("s", "M", "K", "?"):
            self.gen(a, p)
        elif t == "N":
            if not isinstance(a, str):
                self.E("V-RCP-03", p, "expected a name")
        elif t == "P":
            self.veclist(a, 2, p)
        elif t == "Q":
            self.veclist(a, 3, p)
        elif t == "R":
            self.veclist(a, 4, p)
        elif t == "G":
            if isinstance(a, list) and a and a[0] == "ngon":
                if len(a) < 5:
                    self.E("V-RCP-03", p, "ngon takes [\"ngon\", c, rx, rz, n, rot?]")
                else:
                    self.vec(a[1], 3, p)
                    for x in a[2:]:
                        self.num(x, p)
            else:
                self.veclist(a, 3, p)
        elif t == "A":
            if not isinstance(a, list):
                self.E("V-RCP-05", p, "expected a list of numbers")
            else:
                for x in a:
                    self.num(x, p)

    def block(self, d: Dict[str, Any], path: str, depth: int, nest: int) -> None:
        keys = [k for k in d if k in self.f.block_allowed]
        if len(keys) != 1:
            self.E("V-RCP-03", path, "an op object has exactly one block key (%s), found %s" % (", ".join(self.f.block_allowed), list(d)))
            return
        k = keys[0]
        for other in d:
            if other not in self.f.block_allowed[k]:
                self.E("V-RCP-03", path, "'%s' does not take the key '%s'" % (k, other))
                return
        seg = "%s/%s" % (path, k)
        if k == "let":
            if not isinstance(d["let"], dict):
                self.E("V-RCP-03", seg, "let takes an object")
                return
            for name, val in d["let"].items():
                self.gen(val, "%s/%s" % (seg, name))
                self.scope.add(name)
        elif k == "for":
            var = d["for"]
            if not isinstance(var, str):
                self.E("V-RCP-03", seg, "the loop variable is a name")
                return
            if nest + 1 > MAX_NEST:
                self.E("V-RCP-07", seg, "for nesting exceeds %d" % MAX_NEST)
                return
            n = d.get("n")
            if isinstance(n, (int, float)) and not isinstance(n, bool):
                if n > MAX_FOR or n < 0:
                    self.E("V-RCP-07", seg, "n = %s is outside 0..%d" % (n, MAX_FOR))
            elif n is None:
                self.E("V-RCP-03", seg, "for needs n")
            else:
                self.num(n, seg + "/n")
            self.scope.add(var)
            self.run(d.get("do", []), seg + "/do", depth + 1, nest + 1)
        elif k == "if":
            self.gen(d["if"], seg, True)
            self.run(d.get("then", []), seg + "/then", depth + 1, nest)
            if "else" in d:
                self.run(d["else"], seg + "/else", depth + 1, nest)
        elif k == "switch":
            self.gen(d["switch"], seg, True)
            cases = d.get("cases", {})
            if not isinstance(cases, dict):
                self.E("V-RCP-03", seg, "cases is an object")
                return
            for ck, cv in cases.items():
                self.run(cv, "%s/case.%s" % (seg, ck), depth + 1, nest)
            if "default" in d:
                self.run(d["default"], seg + "/default", depth + 1, nest)
        elif k == "mirror_x":
            self.run(d["mirror_x"], seg, depth + 1, nest)
        elif k == "push":
            p = d["push"]
            if not isinstance(p, dict):
                self.E("V-RCP-03", seg, "push takes {pos, euler}")
                return
            self.vec(p.get("pos", [0, 0, 0]), 3, seg + "/pos")
            self.vec(p.get("euler", [0, 0, 0]), 3, seg + "/euler")
            self.run(d.get("do", []), seg + "/do", depth + 1, nest)
        elif k == "part":
            q = d["part"]
            if not isinstance(q, dict):
                self.E("V-RCP-03", seg, "part takes {kind, pivot, param, extra, trunnion}")
                return
            kind = str(q.get("kind", ""))
            if kind not in self.f.parts:
                self.E("V-RCP-03", seg, "unknown part kind '%s'" % kind)
            self.parts.add(kind)
            self.vec(q.get("pivot", [0, 0, 0]), 3, seg + "/pivot")
            self.num(q.get("param", 0.0), seg + "/param")
            self.num(q.get("extra", 0.0), seg + "/extra")
            self.vec(q.get("trunnion", [0, 0]), 2, seg + "/trunnion")
            self.run(d.get("do", []), seg + "/do", depth + 1, nest)
        elif k == "call":
            self.call(d, seg)
        elif k == "slot":
            name = str(d["slot"])
            self.slot_stack.append(name)
            if len(self.slot_stack) > MAX_DEPTH:
                self.E("V-RCP-07", seg, "slot recursion")
            elif name in self.slots:
                self.run(self.slots[name], "%s/slot.%s" % (path, name), depth + 1, nest)
            self.slot_stack.pop()

    def call(self, d: Dict[str, Any], seg: str) -> None:
        name = str(d["call"])
        sig = self.f.macros.get(name)
        if sig is None:
            self.E("V-RCP-03", seg, "unknown macro '%s'" % name)
            return
        self.macros_called.add(name)
        if name in self.f.team_macros:
            self.team = True
        args = d.get("args", {})
        if not isinstance(args, dict):
            self.E("V-RCP-03", seg, "args must be an object")
            return
        for an, av in args.items():
            if an not in sig:
                self.E("V-RCP-03", seg, "macro '%s' has no argument '%s' (takes: %s)" % (name, an, ", ".join(sig)))
                continue
            self.typed({"n": "n", "v": "v", "w": "w", "c": "c", "s": "s", "A": "A"}[sig[an][0]], av, "%s/%s" % (seg, an))


# ---------------------------------------------------------------------------------------------- the validator
class Validator:
    def __init__(self, recipes: Path = rl.RECIPES, balance: Path = rl.BALANCE, facts: Optional[Facts] = None) -> None:
        self.dir = recipes
        self.balance = balance
        self.f = facts or Facts()
        self.rep = Report()
        self.archetypes: Dict[str, Dict[str, Any]] = {}
        self.recipes: Dict[str, Dict[str, Any]] = {}
        self.styles_raw: Dict[str, Dict[str, Any]] = {}
        self.style_src: Dict[str, str] = {}
        self.palette_keys: Set[str] = set(self.f.palette)
        self.assign: Dict[str, Any] = {}

    # ---- loading (V-RCP-01)
    def read(self, path: Path) -> Optional[Any]:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            self.rep.err("V-RCP-01", path.name, "does not parse: %s" % e)
            return None

    def load(self) -> None:
        for p in sorted((self.dir / "archetypes").glob("*.json")):
            d = self.read(p)
            if d is None:
                continue
            if d.get("schema") != rl.ARCH_SCHEMA:
                self.rep.err("V-RCP-01", "archetypes/" + p.name, "schema must be \"%s\"" % rl.ARCH_SCHEMA)
            if d.get("id") != p.stem:
                self.rep.err("V-RCP-01", "archetypes/" + p.name, "id \"%s\" must equal the file name" % d.get("id"))
            self.archetypes[p.stem] = d
        for p in rl.recipe_files(self.dir):
            d = self.read(p)
            if d is None:
                continue
            if d.get("schema") != rl.RECIPE_SCHEMA:
                self.rep.err("V-RCP-01", p.name, "schema must be \"%s\"" % rl.RECIPE_SCHEMA)
            if d.get("id") != p.stem:
                self.rep.err("V-RCP-01", p.name, "id \"%s\" must equal the file name" % d.get("id"))
            self.recipes[p.stem] = d
        sources = [self.dir / "styles.json"] + sorted((self.dir / "styles").glob("*.json"))
        for p in sources:
            if not p.exists():
                continue
            d = self.read(p)
            if d is None:
                continue
            rel = p.relative_to(self.dir).as_posix()
            if d.get("schema") != rl.STYLES_SCHEMA or not isinstance(d.get("styles"), dict):
                self.rep.err("V-RCP-01", rel, "expected schema \"%s\" with a 'styles' object" % rl.STYLES_SCHEMA)
                continue
            keys = list(d["styles"].keys())
            if keys != sorted(keys):
                self.rep.err("V-RCP-01", rel, "style keys are not sorted")
            for sid, st in d["styles"].items():
                if not isinstance(st, dict):
                    self.rep.err("V-RCP-01", rel, "style '%s' must be an object" % sid)
                    continue
                if sid in self.styles_raw:
                    # later source is merged over the earlier one (ViewRecipeBook.add_styles merge)
                    self.rep.warn("V-RCP-12", rel, "style '%s' is also defined in %s (merged over it)" % (sid, self.style_src[sid]))
                    self._merge(self.styles_raw[sid], st)
                else:
                    self.styles_raw[sid] = json.loads(json.dumps(st))
                    self.style_src[sid] = rel
                for pk in (st.get("palette") or {}):
                    self.palette_keys.add(pk)
        idx = self.dir / "index.json"
        if idx.exists():
            d = self.read(idx)
            if d is not None and d.get("schema") != rl.INDEX_SCHEMA:
                self.rep.err("V-RCP-01", "index.json", "schema must be \"%s\"" % rl.INDEX_SCHEMA)
        ap = self.dir / "assignments.json"
        if ap.exists():
            d = self.read(ap)
            if d is not None:
                self.assign = d
                if d.get("schema") != rl.ASSIGN_SCHEMA:
                    self.rep.err("V-RCP-01", "assignments.json", "schema must be \"%s\"" % rl.ASSIGN_SCHEMA)
        for name in ("footprints.json",):
            fp = self.dir / name
            if fp.exists():
                d = self.read(fp)
                if d is not None and d.get("schema") != rl.FOOTPRINTS_SCHEMA:
                    self.rep.err("V-RCP-01", name, "schema must be \"%s\"" % rl.FOOTPRINTS_SCHEMA)

    @staticmethod
    def _merge(dst: Dict[str, Any], src: Dict[str, Any]) -> None:
        for k, v in src.items():
            if isinstance(v, dict) and isinstance(dst.get(k), dict):
                Validator._merge(dst[k], v)
            else:
                dst[k] = json.loads(json.dumps(v))

    # ---- index, defs, assignments (V-RCP-02)
    def check_index(self) -> None:
        idx = self.dir / "index.json"
        if not idx.exists():
            self.rep.err("V-RCP-02", "index.json", "missing (run tools/py/gen_recipe_index.py)")
        else:
            ids = self.read(idx)
            if ids is not None:
                want = sorted(self.recipes)
                have = ids.get("ids", [])
                if have != sorted(have):
                    self.rep.err("V-RCP-01", "index.json", "ids are not sorted")
                if have != want:
                    missing = sorted(set(want) - set(have))[:5]
                    extra = sorted(set(have) - set(want))[:5]
                    self.rep.err("V-RCP-02", "index.json", "does not equal the recipe files (missing %s, stale %s); run tools/py/gen_recipe_index.py" % (missing, extra))
        try:
            import gen_recipe_index as gi
            fp = self.dir / "footprints.json"
            if not fp.exists() or fp.read_text(encoding="utf-8") != gi.footprints_text(self.balance):
                self.rep.err("V-RCP-02", "footprints.json", "missing or out of date (run tools/py/gen_recipe_index.py)")
        except (OSError, ValueError, KeyError) as e:
            self.rep.err("V-RCP-02", "footprints.json", "cannot be checked: %s" % e)

    def check_defs(self) -> None:
        defs = rl.collect_defs(self.balance)
        for def_id in defs.all_ids():
            res = rl.resolve(def_id, defs, self.assign)
            if def_id in self.recipes:
                continue
            if res.matched:
                self.rep.err("V-RCP-02", def_id, "no recipe file (rule: %s -> %s); run tools/py/gen_recipe_stubs.py" % (res.rule, res.archetype))
            else:
                self.rep.err("V-RCP-02", def_id, "no recipe file and no assignments rule; add a rule and run tools/py/gen_recipe_stubs.py")
        for def_id in defs.all_ids():
            res = rl.resolve(def_id, defs, self.assign)
            if not res.matched:
                self.rep.warn("V-RCP-02", def_id, "no assignments rule matches; the stub generator falls back to '%s'" % self.assign.get("default_archetype"))
        # rules must point at archetypes or fallbacks that exist
        have = set(self.archetypes)
        fb = self.assign.get("fallbacks", {})
        names = set(self.assign.get("balance_to_view", {}).values()) | {r["then"] for r in self.assign.get("ability_rules", [])}
        names |= {p["archetype"] for p in self.assign.get("patterns", [])} | {o["archetype"] for o in self.assign.get("overrides", {}).values()}
        for n in sorted(names):
            if n not in have and n not in fb:
                self.rep.err("V-RCP-03", "assignments.json", "view archetype '%s' has no file in archetypes/ and no fallback" % n)
        for n, f in fb.items():
            if f["archetype"] not in have:
                self.rep.err("V-RCP-03", "assignments.json", "fallback '%s' names the missing archetype '%s'" % (n, f["archetype"]))
        stale = [r for r in self.recipes if r not in defs.all_ids() and not self.recipes[r].get("meta", {}).get("stub")]
        _ = stale  # hand-authored recipes for ids that are not defs are legal (test recipes, future defs)

    # ---- archetypes and recipes (V-RCP-03 .. 08)
    def scope_for(self, arch: Dict[str, Any], extra: bool) -> Set[str]:
        return set(GLOBAL_NAMES) | (set(self.f.struct_vars) if extra else set()) | set(arch.get("defaults", {}))

    def check_archetype(self, aid: str, arch: Dict[str, Any]) -> None:
        where = "archetypes/%s.json" % aid
        sc = arch.get("size_class", "medium")
        if sc not in SIZE_CLASSES:
            self.rep.err("V-RCP-03", where, "size_class '%s' is not one of %s" % (sc, ", ".join(sorted(SIZE_CLASSES))))
        for k, v in (arch.get("defaults") or {}).items():
            if not isinstance(v, (int, float, str, bool)):
                self.rep.err("V-RCP-04", where, "default '%s' must be a number, string or bool" % k)
        for key in arch:
            if key not in ("schema", "id", "size_class", "scale", "bevel", "meta", "defaults", "derive", "slots", "ops") and not key.startswith("_"):
                self.rep.warn("V-RCP-03", where, "unknown key '%s'" % key)
        w = self.walk(where, arch, {}, [], {})
        if w is not None and not w.team and arch.get("size_class") not in ("inf", "squad") and not str(aid).startswith(("proj_", "neu_", "gen_neutral")):
            self.rep.warn("V-RCP-06", where, "no team-masked surface (brush team mask or a team macro) in the archetype ops")

    def walk(self, where: str, arch: Dict[str, Any], rslots: Dict[str, Any], after: List[Any], sockets: Dict[str, Any]) -> Optional[Walker]:
        w = Walker(self.f, self.rep, self.palette_keys, where)
        extra = arch.get("size_class") == "structure"
        w.scope = self.scope_for(arch, extra)
        slots = dict(arch.get("slots") or {})
        slots.update(rslots or {})
        w.slots = slots
        for k, v in (arch.get("derive") or {}).items():
            w.gen(v, "%s/derive/%s" % (where, k), True)
            w.scope.add(k)
        w.run(arch.get("ops", []), "ops")
        w.run(after or [], "ops_after")
        for name, sd in (sockets or {}).items():
            if isinstance(sd, dict):
                w.sockets[name] = sd
                w.vec(sd.get("pos", [0, 0, 0]), 3, "sockets/%s/pos" % name)
                w.vec(sd.get("dir", [0, 1, 0]), 3, "sockets/%s/dir" % name)
        for sname, sops in slots.items():
            if not isinstance(sops, list):
                w.E("V-RCP-03", "slots/%s" % sname, "a slot is an op array")
        return w

    def check_recipe(self, rid: str, r: Dict[str, Any]) -> None:
        where = rid + ".json"
        aid = r.get("archetype")
        arch = self.archetypes.get(aid) if isinstance(aid, str) else None
        if arch is None:
            self.rep.err("V-RCP-03", where, "unknown archetype '%s'" % aid)
            return
        style = r.get("style", "auto")
        if style not in ("auto", "owner") and style not in self.styles_raw:
            self.rep.err("V-RCP-03", where, "unknown style '%s'" % style)
        defaults = arch.get("defaults") or {}
        for k, v in (r.get("params") or {}).items():
            if k not in defaults:
                self.rep.err("V-RCP-04", where, "params/%s: not declared by archetype '%s' (declares: %s)" % (k, aid, ", ".join(defaults)))
                continue
            d = defaults[k]
            ok = isinstance(v, bool) if isinstance(d, bool) else (isinstance(v, str) if isinstance(d, str) else (isinstance(v, (int, float, str)) and not isinstance(v, bool)))
            if not ok:
                self.rep.err("V-RCP-04", where, "params/%s: expected %s, got %r" % (k, type(d).__name__, v))
                continue
            if isinstance(d, (int, float)) and not isinstance(d, bool) and isinstance(v, str):
                w0 = Walker(self.f, self.rep, self.palette_keys, where)
                w0.scope = self.scope_for(arch, arch.get("size_class") == "structure")
                w0.expr(v, "params/%s" % k)
        for key in r:
            if key not in ("schema", "id", "archetype", "style", "scale", "seed", "bevel", "params", "kits", "slots", "ops_after", "sockets", "meta") and not key.startswith("_"):
                self.rep.warn("V-RCP-03", where, "unknown key '%s'" % key)
        w = self.walk(where, arch, r.get("slots") or {}, r.get("ops_after") or [], r.get("sockets") or {})
        if w is None:
            return
        # V-RCP-06: the effective model carries a team surface (unit archetypes only; inf squads paint jackets)
        if not w.team and arch.get("size_class") not in ("inf", "squad") and not rid.startswith("proj.") and not rid.startswith("neutral."):
            self.rep.warn("V-RCP-06", where, "no team-masked surface in the effective ops")
        self.check_anchors(rid, r, arch, w)

    def check_anchors(self, rid: str, r: Dict[str, Any], arch: Dict[str, Any], w: Walker) -> None:
        where = rid + ".json"
        if rid.startswith("structure.") and arch.get("size_class") == "structure":
            # V-RCP-10 (static): door_exit anchored on the data anchors; refinery dock; airfield pads
            sk = w.sockets.get("door_exit")
            if sk is None:
                self.rep.err("V-RCP-10", where, "structure recipe has no door_exit socket")
            else:
                text = json.dumps(sk["pos"] if isinstance(sk, dict) else (sk[1] if len(sk) > 1 else []))
                if "door_cx" not in text or "door_cz" not in text:
                    self.rep.err("V-RCP-10", where, "door_exit must be placed at (door_cx, door_cz)")
            if rid.endswith(".refinery") and "dock" not in w.sockets:
                self.rep.err("V-RCP-10", where, "refinery needs a dock socket at (dock_cx, dock_cz)")
            if rid.endswith(".airfield") and not any(n.startswith("pad_x") for n in w.text_hits):
                self.rep.err("V-RCP-10", where, "airfield must place its pads with pad_x0.. / pad_z0..")
            if "footprint" not in w.meta:
                self.rep.warn("V-RCP-10", where, "no ['meta', 'footprint', ['fw', 'fh']] op")
        # V-RCP-08: armed units
        if rid.startswith("unit."):
            u = self.unit_facts.get(rid)
            if u is not None:
                if u["weapons"] and "muzzle0_0" not in w.sockets:
                    self.rep.err("V-RCP-08", where, "armed unit without a muzzle0_0 socket")
                if "deployable_mode" in u["abilities"] and not (w.parts & {"deploy", "deploy_z", "slide_y", "slide_z"} or w.meta.get("deploy") == "pose"
                                                                or w.macros_called & {"spade_pair", "outriggers", "sensor_mast", "wing", "flight_deck"}):
                    self.rep.warn("V-RCP-08", where, "deployable_mode unit without DEPLOY / SLIDE parts or meta.deploy = \"pose\"")

    # ---- styles (V-RCP-03 / 11 / 12)
    def check_styles(self) -> None:
        for sid, st in sorted(self.styles_raw.items()):
            where = "style " + sid
            for k in st:
                if k not in STYLE_KEYS and not k.startswith("_"):
                    self.rep.warn("V-RCP-03", where, "unknown key '%s'" % k)
            ext = st.get("extends")
            if ext is not None:
                chain, cur = [sid], ext
                while cur is not None:
                    if cur not in self.styles_raw:
                        self.rep.err("V-RCP-03", where, "extends unknown style '%s'" % cur)
                        break
                    if cur in chain:
                        self.rep.err("V-RCP-12", where, "extends cycle: %s" % " -> ".join(chain + [cur]))
                        break
                    chain.append(cur)
                    cur = self.styles_raw[cur].get("extends")
            em = st.get("emblem")
            if em is not None and em not in EMBLEMS:
                self.rep.err("V-RCP-11", where, "emblem '%s' is not in the abstract set %s" % (em, sorted(EMBLEMS)))
            tp = st.get("team_plate")
            if tp is not None and tp not in TEAM_PLATES:
                self.rep.err("V-RCP-12", where, "team_plate '%s' is not one of %s" % (tp, sorted(TEAM_PLATES)))
            for pk, pv in (st.get("palette") or {}).items():
                if not (isinstance(pv, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", pv)):
                    self.rep.err("V-RCP-06", where, "palette.%s must be #rrggbb, got %r" % (pk, pv))
            mat = st.get("material") or {}
            for mk, mv in mat.items():
                if mk.endswith("_color"):
                    if not (isinstance(mv, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", mv)):
                        self.rep.err("V-RCP-06", where, "material.%s must be #rrggbb" % mk)
                elif not isinstance(mv, (int, float)) or isinstance(mv, bool):
                    self.rep.err("V-RCP-12", where, "material.%s must be a number" % mk)
            if not st.get("extends"):
                missing = sorted(self.f.palette - set((st.get("palette") or {}).keys()))
                if missing and sid != "neutral":
                    self.rep.warn("V-RCP-12", where, "palette lacks %s (the interpreter default is used)" % missing)
            all_defaults: Dict[str, Any] = {}
            for a in self.archetypes.values():
                for k, v in (a.get("defaults") or {}).items():
                    all_defaults.setdefault(k, v)
            for kk, kv in (st.get("kit") or {}).items():
                if kk not in all_defaults:
                    self.rep.warn("V-RCP-04", where, "kit.%s is not a parameter of any archetype" % kk)
                    continue
                d = all_defaults[kk]
                ok = isinstance(kv, bool) if isinstance(d, bool) else (isinstance(kv, str) if isinstance(d, str) else (isinstance(kv, (int, float)) and not isinstance(kv, bool)))
                if not ok:
                    self.rep.warn("V-RCP-04", where, "kit.%s should be %s (the archetype default's type); it is ignored otherwise" % (kk, type(d).__name__))
            for sname, sops in (st.get("slots") or {}).items():
                w = Walker(self.f, self.rep, self.palette_keys, where + "/slots/" + sname)
                w.scope = set(GLOBAL_NAMES) | set(all_defaults) | set(self.f.struct_vars) | {"hl", "hw", "tk", "ty0", "gy", "top_y", "fz"}
                w.slots = {}
                w.run(sops, "slot")
        # V-RCP-12: style files only define their own faction
        sdir = self.dir / "styles"
        if sdir.exists():
            for p in sorted(sdir.glob("*.json")):
                d = self.read(p)
                if not isinstance(d, dict) or not isinstance(d.get("styles"), dict):
                    continue
                base = p.stem
                for sid in d["styles"]:
                    if not (sid == base or sid.startswith(base + ".")):
                        self.rep.err("V-RCP-12", "styles/" + p.name, "style '%s' does not belong in styles/%s.json (own faction only)" % (sid, base))

    # ---- driver
    def run(self) -> Report:
        self.load()
        defs_units = {}
        try:
            for f in sorted(self.balance.glob("units_*.json")):
                sheet = rl.load_json(f)
                for u in sheet.get("units", []):
                    defs_units[u["id"]] = {"weapons": u.get("weapons", []), "abilities": [str(a) for a in u.get("abilities", [])]}
            g = rl.load_json(self.balance / "global.json")
            for uid, a in g.get("unit_assignments", {}).items():
                if uid in defs_units:
                    defs_units[uid]["abilities"] = sorted(set(defs_units[uid]["abilities"]) | set(a.get("abilities", [])))
        except (OSError, ValueError):
            pass
        self.unit_facts = defs_units
        self.check_index()
        try:
            self.check_defs()
        except (OSError, ValueError, KeyError) as e:
            self.rep.err("V-RCP-02", "balance", "cannot read the def lists: %s" % e)
        for aid, arch in sorted(self.archetypes.items()):
            self.check_archetype(aid, arch)
        for rid, r in sorted(self.recipes.items()):
            self.check_recipe(rid, r)
        self.check_styles()
        return self.rep


def select(rep: Report, only: List[str]) -> List[Issue]:
    if not only:
        return rep.issues
    pre = [o.upper() for o in only]
    return [i for i in rep.issues if any(i.rule.startswith(p) for p in pre)]


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--only", default="", help="comma separated rule ids / prefixes")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--list-rules", action="store_true")
    ap.add_argument("--limit", type=int, default=60, help="max issues printed per rule (default 60)")
    args = ap.parse_args(argv)
    if args.list_rules:
        for k, v in RULES.items():
            print("%s  %s" % (k, v))
        print("V-RCP-09  (Godot) tests/view/test_view_recipes.gd: every recipe builds, budgets, determinism")
        return 0
    v = Validator()
    rep = v.run()
    issues = select(rep, [o for o in args.only.split(",") if o])
    if args.json:
        print(json.dumps([i.as_dict() for i in issues], indent=2))
    else:
        shown: Dict[str, int] = {}
        for i in issues:
            shown[i.rule] = shown.get(i.rule, 0) + 1
            if shown[i.rule] <= args.limit:
                print("[%s] %s %s: %s" % (i.rule, i.sev, i.where, i.msg))
            elif shown[i.rule] == args.limit + 1:
                print("[%s] ... more (use --limit)" % i.rule)
        ne = sum(1 for i in issues if i.sev == E)
        nw = sum(1 for i in issues if i.sev == W)
        print("recipes: %d archetypes, %d recipes, %d styles: %d error(s), %d warning(s)" % (len(v.archetypes), len(v.recipes), len(v.styles_raw), ne, nw))
    if any(i.sev == E for i in issues):
        return 1
    if args.strict and any(i.sev == W for i in issues):
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
