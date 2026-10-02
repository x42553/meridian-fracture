"""ability_kinds.json rules: kind ids, param specs, templates, aliases, implicit rules, def_params (V-ABL-01, V-REF-*)."""
from __future__ import annotations

import re

from .abilities import INT_TYPES, NUM_TYPES, check_value
from .context import Ctx, LoadedFile
from .rules_files import add

SCALARS = INT_TYPES | NUM_TYPES | {"bool", "str", "unit_id", "structure_id", "zone_id", "summon_id"}
KNOWN_LIST = {"unit_ids", "structure_ids"}


def type_ok(t: object) -> bool:
    if not isinstance(t, str):
        return False
    if t in SCALARS or t in KNOWN_LIST or t.startswith("enum:"):
        return True
    return t.startswith("[") and t.endswith("]") and (t[1:-1] == "{}" or type_ok(t[1:-1]))


def check_registry(ctx: Ctx, lf: LoadedFile) -> None:
    d = lf.data
    assert isinstance(d, dict)
    kinds = d.get("kinds") if isinstance(d.get("kinds"), dict) else {}
    templates = d.get("templates") if isinstance(d.get("templates"), dict) else {}
    aliases = d.get("aliases") if isinstance(d.get("aliases"), dict) else {}
    ids: dict[int, str] = {}
    for kn, ks in kinds.items():
        if not isinstance(ks, dict):
            continue
        if not re.match(r"^[a-z][a-z0-9_]*$", kn):
            add(ctx, "V-SCH-03", lf, f"kind name {kn!r} must be lowercase snake_case", kinds, kn, entity=kn, field="name")
        kid = ks.get("id")
        if isinstance(kid, int):
            if kid in ids:
                add(ctx, "V-ABL-01", lf, f"kind id {kid} is used by both {ids[kid]!r} and {kn!r}", ks, "id", entity=kn, field="id", expected="unique id", found=kid)
            ids[kid] = kn
        check_param_specs(ctx, lf, kn, ks.get("params"), "params")
    if ids and sorted(ids) != list(range(1, len(ids) + 1)):
        add(ctx, "V-ABL-01", lf, "kind ids must be dense 1..N (DefEnums.AbilityKind is append-only)", kinds, next(iter(kinds)), expected=list(range(1, len(ids) + 1)), found=sorted(ids))
    for tn, t in templates.items():
        if not isinstance(t, dict):
            continue
        kn = t.get("kind")
        m = re.match(r"^ability\.([a-z0-9_]+)\.([a-z0-9_]+)$", tn)
        if not m:
            add(ctx, "V-SCH-03", lf, f"template id {tn!r} must look like ability.<kind>.<variant>", templates, tn, entity=tn, field="id", expected="ability.<kind>.<variant>", found=tn)
        elif m.group(1) != kn:
            add(ctx, "V-SCH-03", lf, f"template {tn!r} has kind {kn!r}; the id must be ability.{kn}.<variant>", templates, tn, entity=tn, field="kind", expected=f"ability.{kn}.*", found=tn)
        ks = kinds.get(kn)
        if not isinstance(ks, dict):
            add(ctx, "V-REF-04", lf, f"template {tn!r} refers to unknown kind {kn!r}", t, "kind", entity=tn, field="kind", expected="a key of kinds", found=kn)
            continue
        spec = ks.get("params", {}) if isinstance(ks.get("params"), dict) else {}
        for pk, pv in (t.get("params") or {}).items():
            if pk not in spec:
                add(ctx, "V-ABL-01", lf, f"template {tn!r}: unknown parameter {pk!r} for kind {kn!r}", t.get("params"), pk, entity=tn, field=f"params.{pk}",
                    expected="one of " + ", ".join(sorted(spec)), found=pk)
                continue
            for rule, msg, exp, found in check_value(spec[pk], pv, ctx):
                if rule == "V-ABL-01" and "too short" in msg:
                    continue  # templates may carry an intentionally empty list that the unit's ability_params fills in
                add(ctx, rule, lf, f"template {tn!r} {pk}: {msg}", t.get("params"), pk, entity=tn, field=f"params.{pk}", expected=exp, found=found)
    for an, tn in aliases.items():
        if tn is not None and tn not in templates:
            add(ctx, "V-REF-04", lf, f"alias {an!r} points to unknown template {tn!r}", aliases, an, entity=an, field="aliases", expected="existing template id or null", found=tn)
    g = ctx.g
    names = set(a for v in g.get("unit_assignments", {}).values() for a in v.get("abilities", [])) | (set(g.get("ability_value_pct", {})) - {"note"})
    names = {n for n in names if not (isinstance(n, str) and n.startswith("ability.") and n in templates)}  # a template id needs no alias
    for n in sorted(names - set(aliases)):
        add(ctx, "V-REF-04", lf, f"framework ability name {n!r} (global.json unit_assignments / ability_value_pct) has no entry in aliases (use null when it produces no ability)",
            d, "aliases", entity=n, field="aliases", expected="alias entry", found="<absent>")
    families = {a.get("family") for a in ctx.arch.values() if isinstance(a, dict)}
    for i, r in enumerate(d.get("implicit") or []):
        if not isinstance(r, dict):
            continue
        kind, _, val = str(r.get("when", "")).partition(":")
        ok = {"tag": val in ctx.bible_unit_tags(), "family": val in families,
              "archetype": val in ctx.arch or (val.startswith("service.") and val[8:] in ctx.service)}.get(kind, False)
        if not ok:
            add(ctx, "V-REF-04", lf, f"implicit rule {i}: {r.get('when')!r} does not match any bible tag / archetype family / archetype", d.get("implicit"), i,
                entity=f"implicit[{i}]", field="when", expected="tag:<bible tag> | family:<family> | archetype:<id>", found=r.get("when"))
        for tn in r.get("templates", []):
            if tn not in templates:
                add(ctx, "V-REF-04", lf, f"implicit rule {i}: unknown template {tn!r}", d.get("implicit"), i, entity=f"implicit[{i}]", field="templates", expected="existing template", found=tn)
    for pk, ps in (d.get("def_params") or {}).items():
        if isinstance(ps, dict):
            if not type_ok(ps.get("type")):
                add(ctx, "V-ABL-01", lf, f"def_params.{pk}: unknown type {ps.get('type')!r}", d["def_params"], pk, entity=pk, field="type", expected="registry type", found=ps.get("type"))
            elif "def" in ps:
                for rule, msg, exp, found in check_value({"type": ps["type"]}, ps["def"], ctx):
                    add(ctx, rule, lf, f"def_params.{pk} default: {msg}", d["def_params"], pk, entity=pk, field="def", expected=exp, found=found)
    orphan_templates(ctx, lf, templates, aliases, d)


def check_param_specs(ctx: Ctx, lf: LoadedFile, kn: str, specs: object, where: str) -> None:
    if not isinstance(specs, dict):
        return
    for pk, ps in specs.items():
        if not isinstance(ps, dict):
            continue
        t = ps.get("type")
        fld = f"{where}.{pk}"
        if not type_ok(t):
            add(ctx, "V-ABL-01", lf, f"parameter {pk!r} of kind {kn!r} has unknown type {t!r}", specs, pk, entity=kn, field=fld + ".type", expected="registry type (see schema _doc)", found=t)
            continue
        if not ps.get("req") and "def" not in ps:
            add(ctx, "V-ABL-01", lf, f"optional parameter {pk!r} of kind {kn!r} needs a default ('def') because the loader materialises every default", specs, pk,
                entity=kn, field=fld, expected="def", found="<absent>")
        if isinstance(ps.get("min"), (int, float)) and isinstance(ps.get("max"), (int, float)) and ps["min"] > ps["max"]:
            add(ctx, "V-ABL-01", lf, f"parameter {pk!r} of kind {kn!r}: min > max", specs, pk, entity=kn, field=fld, expected="min <= max", found=f"{ps['min']} > {ps['max']}")
        if "def" in ps and t != "[{}]":
            for rule, msg, exp, found in check_value({**ps, "min": None, "max": None} if isinstance(t, str) and t.startswith("[") else ps, ps["def"], ctx):
                add(ctx, rule, lf, f"kind {kn!r} parameter {pk!r} default: {msg}", specs, pk, entity=kn, field=fld + ".def", expected=exp, found=found)
        if t == "[{}]":
            if not isinstance(ps.get("items"), dict):
                add(ctx, "V-ABL-01", lf, f"parameter {pk!r} of kind {kn!r} is a list of objects and needs an 'items' sub-spec", specs, pk, entity=kn, field=fld, expected="items", found="<absent>")
            else:
                check_param_specs(ctx, lf, kn, ps["items"], fld + ".items")


def orphan_templates(ctx: Ctx, lf: LoadedFile, templates: dict, aliases: dict, d: dict) -> None:
    """V-REF-03 (W): a template nothing references. Only evaluated once every sheet exists, because until then the users are not authored yet."""
    if not (all(ctx.files.get(f"units_{c}.json") and ctx.files[f"units_{c}.json"].ok for c in ("ae", "def", "han", "napc", "nec", "olm", "pd", "sap", "shared"))
            and ctx.files.get("structures.json") and ctx.files["structures.json"].ok):
        return
    used = {v for v in aliases.values() if v}
    for r in d.get("implicit") or []:
        used.update(r.get("templates", []) if isinstance(r, dict) else [])
    for f in ctx.files.values():
        if not f.ok or not (f.name.startswith("units_") or f.name == "structures.json"):
            continue
        for lst in ("units", "summons", "structures"):
            for e in f.data.get(lst) or []:  # type: ignore[union-attr]
                if isinstance(e, dict):
                    used.update(a for a in (e.get("abilities") or []) if isinstance(a, str) and a.startswith("ability."))
    for tn, t in templates.items():
        if tn not in used and not (isinstance(t, dict) and t.get("external")):
            add(ctx, "V-REF-03", lf, f"template {tn!r} is not referenced by an alias, an implicit rule or any sheet (mark it with 'external' when another data file uses it)",
                templates, tn, entity=tn, field="id", expected="referenced", found="orphan")
