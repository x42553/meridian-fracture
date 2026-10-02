"""Ability registry (ability_kinds.json) loading, template resolution (spec data_balance 7.4) and parameter validation (V-ABL-*).

resolve(reg, entity, emit) returns the resolved abilities of one unit/summon/structure:  {kind name: Resolved}.
`emit(rule, field, message, expected, found)` reports a problem (the caller supplies file/entity/line).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from .context import Ctx

NUM_TYPES = {"cells", "cells_s", "s", "smt", "pct", "pcts", "deg", "deg_s", "bp", "crps"}
INT_TYPES = {"n", "x", "x100", "credits", "hp"}
STR_RE = re.compile(r"^[a-z0-9_.:#-]*$")
PCT_TYPES = {"pct", "pcts"}


@dataclass
class Resolved:
    kind: str
    entry: str
    template: str
    implicit: bool
    params: dict = field(default_factory=dict)  # merged, defaults NOT materialised (only file-provided values)


class Registry:
    def __init__(self, data: object) -> None:
        d = data if isinstance(data, dict) else {}
        self.kinds: dict = d.get("kinds", {}) if isinstance(d.get("kinds"), dict) else {}
        self.templates: dict = d.get("templates", {}) if isinstance(d.get("templates"), dict) else {}
        self.aliases: dict = d.get("aliases", {}) if isinstance(d.get("aliases"), dict) else {}
        self.implicit: list = d.get("implicit", []) if isinstance(d.get("implicit"), list) else []
        self.def_params: dict = d.get("def_params", {}) if isinstance(d.get("def_params"), dict) else {}
        self.ok = bool(self.kinds and self.templates)

    def template_kind(self, tname: str) -> str | None:
        t = self.templates.get(tname)
        return t.get("kind") if isinstance(t, dict) else None

    def alias_for_template(self, tname: str) -> list[str]:
        return sorted(a for a, t in self.aliases.items() if t == tname)


@dataclass
class Entity:
    """What the resolver needs to know about a def."""
    scope: str                    # unit | structure
    entries: list                 # ability entries as listed by the sheet (or defaulted from unit_assignments)
    ability_params: dict
    tags: set                     # unit tags (bible tags, or a summon's unit_tags)
    family: str
    archetype: str


def implicit_templates(reg: Registry, ent: Entity) -> list[str]:
    out: list[str] = []
    for r in reg.implicit:
        if not isinstance(r, dict):
            continue
        when = r.get("when", "")
        kind, _, val = when.partition(":")
        if (kind == "tag" and val in ent.tags) or (kind == "family" and val == ent.family) or (kind == "archetype" and val == ent.archetype):
            out.extend(t for t in r.get("templates", []) if isinstance(t, str))
    return out


def resolve(reg: Registry, ent: Entity, emit, ctx: Ctx) -> dict[str, Resolved]:
    res: dict[str, Resolved] = {}
    used_keys: set[str] = set()
    for tname in implicit_templates(reg, ent):
        kind = reg.template_kind(tname)
        if kind is None:
            emit("V-REF-04", "abilities", f"implicit template {tname!r} does not exist in ability_kinds.json", "known template", tname)
            continue
        ov = ent.ability_params.get(tname)
        if ov is not None:
            used_keys.add(tname)
        res[kind] = Resolved(kind, tname, tname, True, _merge(reg.templates[tname].get("params"), ov))
    seen_explicit: dict[str, str] = {}
    for entry in ent.entries:
        if not isinstance(entry, str):
            continue
        if entry.startswith("ability."):
            tname: str | None = entry
        elif entry in reg.aliases:
            tname = reg.aliases[entry]
            if tname is None:
                used_keys.add(entry)
                continue  # framework name that produces no ability (amphibious, unmanned, breach_charge, dual_purpose)
        else:
            emit("V-REF-04", f"abilities[{entry}]", f"unknown ability name {entry!r}: neither an alias nor an 'ability.*' template id (see ability_kinds.json aliases)",
                 "alias or ability.* template id", entry)
            continue
        kind = reg.template_kind(tname)  # type: ignore[arg-type]
        if kind is None:
            emit("V-REF-04", f"abilities[{entry}]", f"template {tname!r} does not exist in ability_kinds.json", "known template", tname)
            continue
        if kind in seen_explicit:
            emit("V-ABL-02", f"abilities[{entry}]", f"two explicit abilities of kind {kind!r} ({seen_explicit[kind]!r} and {entry!r}); at most one per kind",
                 "one ability per kind", entry)
        seen_explicit[kind] = entry
        ov = ent.ability_params.get(entry)
        if ov is not None:
            used_keys.add(entry)
        res[kind] = Resolved(kind, entry, tname, False, _merge(reg.templates[tname].get("params"), ov))  # type: ignore[arg-type]
    for k in ent.ability_params:
        if k not in used_keys:
            emit("V-ABL-01", f"ability_params.{k}", f"ability_params key {k!r} is not an entry of 'abilities' nor an implicit template of this def",
                 "an entry of abilities", k)
    for r in res.values():
        validate_resolved(reg, r, ent, emit, ctx)
    return res


def _merge(base: object, over: object) -> dict:
    d = dict(base) if isinstance(base, dict) else {}
    if isinstance(over, dict):
        d.update(over)
    return d


def validate_resolved(reg: Registry, r: Resolved, ent: Entity, emit, ctx: Ctx) -> None:
    ks = reg.kinds.get(r.kind)
    if not isinstance(ks, dict):
        emit("V-ABL-01", f"abilities[{r.entry}]", f"ability kind {r.kind!r} is not in the registry", "known kind", r.kind)
        return
    if ent.scope not in ks.get("scopes", []):
        emit("V-ABL-01", f"abilities[{r.entry}]", f"ability kind {r.kind!r} is not allowed on a {ent.scope}", "scope in " + "|".join(ks.get("scopes", [])), ent.scope)
    spec = ks.get("params", {})
    for k, v in r.params.items():
        if k not in spec:
            emit("V-ABL-01", f"abilities[{r.entry}].{k}", f"unknown parameter {k!r} for ability kind {r.kind!r}", "one of " + ", ".join(sorted(spec)), k)
            continue
        for rule, msg, exp, found in check_value(spec[k], v, ctx):
            emit(rule, f"abilities[{r.entry}].{k}", msg, exp, found)
    for k, ps in spec.items():
        if ps.get("req") and k not in r.params:
            emit("V-ABL-01", f"abilities[{r.entry}].{k}", f"required parameter {k!r} of ability kind {r.kind!r} is missing (template {r.template!r} does not supply it; "
                 f"give it in ability_params)", "value of type " + str(ps.get("type")), "<absent>")


def _dec_ok(v: float, max_dec: int) -> bool:
    return abs(v * 10 ** max_dec - round(v * 10 ** max_dec)) < 1e-6


def check_value(spec: dict, v: object, ctx: Ctx) -> list[tuple[str, str, str, str]]:
    """Validate one value against a registry param spec. Returns [(rule, message, expected, found)]."""
    t = spec.get("type", "")
    out: list[tuple[str, str, str, str]] = []
    lo, hi = spec.get("min"), spec.get("max")

    def bad(msg: str, exp: str = "", rule: str = "V-ABL-01") -> list:
        return [(rule, msg, exp or t, repr(v))]

    if t.startswith("[") and t.endswith("]"):
        if not isinstance(v, list):
            return bad("must be an array")
        if lo is not None and len(v) < lo:
            out.append(("V-ABL-01", f"array too short ({len(v)} items)", f">= {lo} items", f"{len(v)} items"))
        if hi is not None and len(v) > hi:
            out.append(("V-ABL-01", f"array too long ({len(v)} items)", f"<= {hi} items", f"{len(v)} items"))
        inner = t[1:-1]
        if inner == "{}":
            items = spec.get("items", {})
            for i, e in enumerate(v):
                if not isinstance(e, dict):
                    out.append(("V-ABL-01", f"element {i} must be an object", "object", repr(e)))
                    continue
                for k in e:
                    if k not in items:
                        out.append(("V-ABL-01", f"element {i}: unknown key {k!r}", "one of " + ", ".join(sorted(items)), k))
                for k, ips in items.items():
                    if k in e:
                        out += [(a, f"element {i}.{k}: {b}", c, d) for a, b, c, d in check_value(ips, e[k], ctx)]
                    elif ips.get("req"):
                        out.append(("V-ABL-01", f"element {i}: required key {k!r} missing", k, "<absent>"))
        else:
            sub = {"type": inner}
            for i, e in enumerate(v):
                out += [(a, f"element {i}: {b}", c, d) for a, b, c, d in check_value(sub, e, ctx)]
        return out
    if t in ("unit_ids", "structure_ids"):
        return check_value({"type": "[" + t[:-1] + "]"}, v, ctx) if isinstance(v, list) else bad("must be an array of ids")
    if t == "bool":
        return [] if isinstance(v, bool) else bad("must be true or false")
    if t == "str":
        return [] if isinstance(v, str) and STR_RE.match(v) else bad("must be a string of [a-z0-9_.:#-]")
    if t.startswith("enum:"):
        opts = t[5:].split("|")
        return [] if v in opts else bad("not an allowed value", "one of " + "|".join(opts))
    if t in ("unit_id", "structure_id", "zone_id", "summon_id"):
        if not isinstance(v, str):
            return bad("must be an id string")
        if v == "" and spec.get("def") == "":
            return []
        if t == "unit_id" and v not in ctx.unit_ids() and v not in ctx.summons():
            return [("V-REF-01", "unit id does not exist (bible units and summons)", "existing unit id", v)]
        if t == "structure_id" and v not in ctx.structure_ids():
            return [("V-REF-01", "structure id does not exist in the bible", "existing structure id", v)]
        if t == "zone_id":
            z = ctx.zone_ids()
            if not re.match(r"^zone\.[a-z0-9_]+$", v):
                return [("V-SCH-03", "zone id must look like zone.<name>", "zone.<name>", v)]
            if z is not None and v not in z:
                return [("V-REF-01", "zone id does not exist in zone_templates.json", "existing zone id", v)]
        if t == "summon_id":
            sm = ctx.summons().get(v)
            if sm is None:
                return [("V-REF-01", "summon id does not exist in any units_<code>.json summons list", "existing summon id", v)]
            if sm.get("class") != "drone":
                return [("V-ABL-04", "referenced summon is not class 'drone'", "class drone", str(sm.get("class")))]
        return []
    if t in INT_TYPES or t in NUM_TYPES:
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return bad("must be a number")
        if t in INT_TYPES and not float(v).is_integer():
            return [("V-SCH-05", "must be an integer", "integer", repr(v))]
        if not _dec_ok(float(v), 2 if t in PCT_TYPES else 3):
            return [("V-SCH-06" if t in PCT_TYPES else "V-SCH-04", "too many decimals", "<= 2 decimals" if t in PCT_TYPES else "<= 3 decimals", repr(v))]
        if lo is not None and v < lo:
            out.append(("V-ABL-01", "value below the registry minimum", f">= {lo}", repr(v)))
        if hi is not None and v > hi:
            out.append(("V-ABL-01", "value above the registry maximum", f"<= {hi}", repr(v)))
        return out
    return bad(f"registry type {t!r} is not understood by the validator")
