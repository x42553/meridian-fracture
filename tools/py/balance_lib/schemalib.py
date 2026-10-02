"""JSON-Schema subset validator for game/data/balance/schema/*.schema.json (stdlib only).

Supported keywords: type (name or list; 'integer' accepts integral floats), enum, const, pattern, minimum, maximum, minItems, maxItems, uniqueItems,
items, properties, required, additionalProperties (bool or schema), patternProperties, $ref ('#/definitions/x', 'file.schema.json',
'file.schema.json#/definitions/x'), anyOf.  Extensions: 'x-rule' (rule id to report for errors raised AT this node;
only affects errors about the node's own value, never required/unknown-key errors or children), 'x-forbidden' ({key: rule}: presence of the key is reported with that rule instead of V-SCH-02),
'x-doc' (ignored).  Keys starting with '_' are documentation and never validated.

Default rule ids: unknown key V-SCH-02, missing required V-CMP-04, non-integral integer V-SCH-05, other type/shape V-SCH-10, enum V-REF-04,
bounds V-RNG-01, pattern V-SCH-10 (schemas set x-rule 'V-SCH-03' on id patterns).
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .jsonio import LDict, LList, line_of


@dataclass
class SchemaError:
    path: tuple
    rule: str
    message: str
    expected: str = ""
    found: str = ""
    line: int = 0


def _tname(v: object) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int):
        return "integer"
    if isinstance(v, float):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    return "object"


def _is_type(v: object, t: str) -> bool:
    if t == "integer":
        return (isinstance(v, int) and not isinstance(v, bool)) or (isinstance(v, float) and v.is_integer())
    if t == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    return _tname(v) == t or (t == "object" and isinstance(v, dict)) or (t == "array" and isinstance(v, list))


def _show(v: object) -> str:
    s = json.dumps(v) if not isinstance(v, (LDict, LList)) else json.dumps(v)
    return s if len(s) <= 60 else s[:57] + "..."


class SchemaSet:
    def __init__(self, schema_dir: Path) -> None:
        self.dir = Path(schema_dir)
        self._cache: dict[str, dict] = {}

    def load(self, name: str) -> dict:
        if name not in self._cache:
            self._cache[name] = json.loads((self.dir / name).read_text(encoding="utf-8"))
        return self._cache[name]

    def names(self) -> list[str]:
        return sorted(p.name for p in self.dir.glob("*.schema.json"))

    def validate(self, data: object, schema_name: str) -> list[SchemaError]:
        errs: list[SchemaError] = []
        root = self.load(schema_name)
        self._node(data, root, (schema_name, root), (), errs, None, 0)
        return errs

    # ---- internals
    def _resolve(self, ref: str, ctx: tuple) -> tuple[str, dict, dict]:
        fname, root = ctx
        if ref.startswith("#"):
            base_name, base, frag = fname, root, ref[1:]
        else:
            fn, _, frag = ref.partition("#")
            base_name, base = fn, self.load(fn)
        node = base
        for part in [p for p in frag.split("/") if p]:
            node = node[part]
        return base_name, base, node

    def _node(self, v: object, sch: dict, ctx: tuple, path: tuple, errs: list[SchemaError], parent, key) -> None:
        line = line_of(parent, key) if parent is not None else 1
        if "$ref" in sch:
            fname, root, node = self._resolve(sch["$ref"], ctx)
            merged = dict(node)
            for k, x in sch.items():
                if k != "$ref":
                    merged[k] = x
            self._node(v, merged, (fname, root), path, errs, parent, key)
            return
        rule = sch.get("x-rule")

        def err(default: str, msg: str, exp: str = "", found: str = "") -> None:
            errs.append(SchemaError(path, rule or default, msg, exp, found, line))

        if "type" in sch:
            types = sch["type"] if isinstance(sch["type"], list) else [sch["type"]]
            if not any(_is_type(v, t) for t in types):
                if "integer" in types and _is_type(v, "number"):
                    err("V-SCH-05", "value must be integral", "integer", _show(v))
                else:
                    err("V-SCH-10", "wrong JSON type", "|".join(types), f"{_tname(v)} {_show(v)}")
                return
        if "const" in sch and v != sch["const"]:
            err("V-SCH-10", "value must equal the constant", _show(sch["const"]), _show(v))
        if "enum" in sch and v not in sch["enum"]:
            err("V-REF-04", "value not in the allowed set", "one of " + "|".join(str(x) for x in sch["enum"]), _show(v))
        if isinstance(v, str) and "pattern" in sch and not re.search(sch["pattern"], v):
            err("V-SCH-10", "string does not match the required pattern", sch["pattern"], _show(v))
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            if "minimum" in sch and v < sch["minimum"]:
                err("V-RNG-01", "value below minimum", f">= {sch['minimum']}", _show(v))
            if "maximum" in sch and v > sch["maximum"]:
                err("V-RNG-01", "value above maximum", f"<= {sch['maximum']}", _show(v))
        if isinstance(v, list):
            if "minItems" in sch and len(v) < sch["minItems"]:
                err("V-SCH-10", "too few array items", f">= {sch['minItems']} items", f"{len(v)} items")
            if "maxItems" in sch and len(v) > sch["maxItems"]:
                err("V-SCH-10", "too many array items", f"<= {sch['maxItems']} items", f"{len(v)} items")
            if sch.get("uniqueItems"):
                seen: list = []
                for i, x in enumerate(v):
                    if x in seen:
                        errs.append(SchemaError(path + (i,), rule or "V-SCH-10", "duplicate array item", "unique items", _show(x), line_of(v, i)))
                    seen.append(x)
            if "items" in sch:
                for i, x in enumerate(v):
                    self._node(x, sch["items"], ctx, path + (i,), errs, v, i)
        if isinstance(v, dict):
            props = sch.get("properties", {})
            forb = sch.get("x-forbidden", {})
            for req in sch.get("required", []):
                if req not in v:
                    errs.append(SchemaError(path + (req,), "V-CMP-04", "required field missing", "present", "<absent>", getattr(v, "line", line)))
            pp = sch.get("patternProperties", {})
            ap = sch.get("additionalProperties", True)
            for k in v:
                if k.startswith("_"):
                    continue
                kline = line_of(v, k)
                if k in forb:
                    errs.append(SchemaError(path + (k,), forb[k], "field is not settable in this file (owned by another source)", "absent", _show(v[k]), kline))
                    continue
                if k in props:
                    self._node(v[k], props[k], ctx, path + (k,), errs, v, k)
                    continue
                hit = False
                for pat, psch in pp.items():
                    if re.search(pat, k):
                        self._node(v[k], psch, ctx, path + (k,), errs, v, k)
                        hit = True
                        break
                if hit:
                    continue
                if ap is False:
                    known = sorted(props)
                    hint = ""
                    close = [p for p in known if p.startswith(k[:3])] if len(k) >= 3 else []
                    if close:
                        hint = f" (did you mean {', '.join(close[:3])}?)"
                    errs.append(SchemaError(path + (k,), "V-SCH-02", "unknown key" + hint, "one of the schema keys", k, kline))
                elif isinstance(ap, dict):
                    self._node(v[k], ap, ctx, path + (k,), errs, v, k)
        if "anyOf" in sch:
            trial_best = None
            for sub in sch["anyOf"]:
                te: list[SchemaError] = []
                self._node(v, sub, ctx, path, te, parent, key)
                if not te:
                    trial_best = None
                    break
                trial_best = trial_best or te
            if trial_best:
                errs.extend(trial_best)


def entity_field(data: object, path: tuple) -> tuple[str, str]:
    """Split an error path into (entity id, field path): the entity is the deepest object on the path that has a string 'id'."""
    cur = data
    entity = ""
    cut = 0
    for i, p in enumerate(path):
        try:
            cur = cur[p]  # type: ignore[index]
        except (KeyError, IndexError, TypeError):
            break
        if isinstance(cur, dict) and isinstance(cur.get("id"), str):
            entity = cur["id"]
            cut = i + 1
    rest = ".".join(str(p) if not isinstance(p, int) else f"[{p}]" for p in path[cut:]).replace(".[", "[")
    return entity, rest
