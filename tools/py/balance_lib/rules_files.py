"""File-level rules: manifest, envelope, JSON-Schema conformance, numeric literals, suffixes, sorting (V-SCH-*)."""
from __future__ import annotations

from .context import EXPECTED_FILES, ID_RE, Ctx, LoadedFile, schema_key
from .jsonio import LDict, LList, line_of
from .schemalib import entity_field

SUFFIXES = ("_cells_s", "_cells", "_s", "_smt", "_n", "_x100", "_x", "_pct", "_pcts", "_bp", "_deg_s", "_deg", "_credits", "_hp", "_crps")
SCHEMA_OF = {"structures.json": "structures.schema.json", "ability_kinds.json": "ability_kinds.schema.json", "manifest.json": "manifest.schema.json"}
LIST_KEYS = ("units", "weapons", "summons", "structures")


def add(ctx: Ctx, rule: str, lf: LoadedFile | str, msg: str, container: object = None, key: object = None, *, entity: str = "", field: str = "",
        expected: object = "", found: object = "", line: int | None = None, sev: str | None = None) -> None:
    name = lf if isinstance(lf, str) else lf.name
    if line is None:
        line = line_of(container, key) if container is not None else 0
    ctx.rep.add(rule, name, msg, line=line, entity=entity, field=field, expected=expected, found=found, sev=sev)


def schema_for(fname: str) -> str | None:
    if fname.startswith("units_"):
        return "units.schema.json"
    return SCHEMA_OF.get(fname)


def check_manifest(ctx: Ctx) -> None:
    m = ctx.manifest
    if not m.exists:
        add(ctx, "V-SCH-01", m, "manifest.json does not exist", expected="game/data/balance/manifest.json", found="<absent>")
        return
    common(ctx, m)
    if not m.ok:
        return
    files = ctx.manifest_files
    if files != sorted(files):
        add(ctx, "V-SCH-01", m, "manifest 'files' must be sorted ascending", m.data, "files", expected="sorted", found=files)  # type: ignore[arg-type]
    for f in sorted(set(EXPECTED_FILES) - set(files)):
        add(ctx, "V-SCH-01", m, f"manifest does not list the expected file {f}", m.data, "files", expected=f, found="<not listed>")  # type: ignore[arg-type]
    for f in sorted(set(files) - set(EXPECTED_FILES)):
        add(ctx, "V-SCH-01", m, f"manifest lists {f}, which is not in the expected file set (fine only if a DefDomainCompiler owns it)",
            m.data, "files", found=f, sev="W")  # type: ignore[arg-type]
    for p in sorted(ctx.dir.glob("*.json")):
        if p.name not in files and p.name != "manifest.json":
            add(ctx, "V-SCH-01", m, f"{p.name} exists in game/data/balance but is not listed in the manifest (it will not be read)", m.data, "files",  # type: ignore[arg-type]
                found=p.name, sev="W")


def check_file(ctx: Ctx, lf: LoadedFile) -> None:
    """Common checks of one manifest file (existence is reported by the caller)."""
    if not lf.exists:
        add(ctx, "V-SCH-01", lf, f"file {lf.name} does not exist", expected=f"game/data/balance/{lf.name}", found="<absent>", line=0)
        return
    common(ctx, lf)


def common(ctx: Ctx, lf: LoadedFile) -> None:
    for line, rule, msg in lf.problems:
        add(ctx, rule, lf, msg, line=line)
    if lf.data is None:
        return
    if not isinstance(lf.data, dict):
        add(ctx, "V-SCH-01", lf, "top-level JSON value must be an object", expected="object", found=type(lf.data).__name__, line=1)
        return
    want = schema_key(lf.name)
    got = lf.data.get("schema")
    if got != want:
        add(ctx, "V-SCH-01", lf, "wrong or missing 'schema' key", lf.data, "schema", field="schema", expected=want, found=got if got is not None else "<absent>")
    sch = schema_for(lf.name)
    if sch and (ctx.schemas.dir / sch).is_file():
        for e in ctx.schemas.validate(lf.data, sch):
            if e.path == ("schema",) and e.rule == "V-SCH-01" and got != want:
                continue  # already reported
            ent, fld = entity_field(lf.data, e.path)
            add(ctx, e.rule, lf, e.message, entity=ent, field=fld or ".".join(str(p) for p in e.path), expected=e.expected, found=e.found, line=e.line)
    scan(ctx, lf)


def scan(ctx: Ctx, lf: LoadedFile) -> None:
    """Numeric literal rules (V-SCH-04/06/07), id shape (V-SCH-03) and sorting (V-SCH-09)."""
    data = lf.data
    suffix_files = lf.name.startswith("units_") or lf.name == "structures.json"

    def walk(v: object, rel: str, key: str, in_params: bool, ent: str) -> None:
        if isinstance(v, LDict):
            if isinstance(v.get("id"), str):
                ent, rel = v["id"], ""
            for k, x in v.items():
                if k.startswith("_"):
                    continue
                fld = f"{rel}.{k}" if rel else k
                if isinstance(x, (int, float)) and not isinstance(x, bool):
                    number(k, x, v.decs.get(k, 0), v, k, ent, fld)
                    if in_params and not k.endswith(SUFFIXES):
                        add(ctx, "V-SCH-07", lf, f"numeric key {k!r} in a params object has no unit suffix", v, k, entity=ent, field=fld,
                            expected="suffix " + " ".join(SUFFIXES[:8]) + " ...", found=k)
                else:
                    walk(x, fld, k, in_params or (k == "params" and suffix_files), ent)
        elif isinstance(v, LList):
            for i, x in enumerate(v):
                fld = f"{rel}[{i}]"
                if isinstance(x, (int, float)) and not isinstance(x, bool):
                    number(key, x, v.decs.get(i, 0), v, i, ent, fld)
                else:
                    walk(x, fld, key, in_params, ent)

    def number(key: str, x: float, decs: int, cont: object, k: object, ent: str, fld: str) -> None:
        if decs > 3:
            add(ctx, "V-SCH-04", lf, f"numeric literal has {decs} decimals (max 3)", cont, k, entity=ent, field=fld, expected="<= 3 decimals", found=x)
        if abs(x) >= 2 ** 40:
            add(ctx, "V-SCH-04", lf, "numeric literal magnitude >= 2^40", cont, k, entity=ent, field=fld, expected="|x| < 2^40", found=x)
        if key.endswith(("_pct", "_pcts")):
            if decs > 2:
                add(ctx, "V-SCH-06", lf, f"percent value has {decs} decimals (max 2)", cont, k, entity=ent, field=fld, expected="<= 2 decimals", found=x)
            if x <= -100 and key.endswith("_pct"):
                add(ctx, "V-SCH-06", lf, "percent delta <= -100 %", cont, k, entity=ent, field=fld, expected="> -100", found=x)

    if isinstance(data, LDict):
        walk(data, "", "", False, "")
        for lk in LIST_KEYS:
            lst = data.get(lk)
            if not isinstance(lst, list):
                continue
            ids = [(i, e.get("id")) for i, e in enumerate(lst) if isinstance(e, dict) and isinstance(e.get("id"), str)]
            for i, ident in ids:
                if not ID_RE.match(ident):
                    add(ctx, "V-SCH-03", lf, f"id {ident!r} does not match ^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$", lst, i, entity=ident, field="id",
                        expected="lowercase dotted id", found=ident)
            for (i0, a), (i1, b) in zip(ids, ids[1:]):
                if b < a:
                    add(ctx, "V-SCH-09", lf, f"entries of '{lk}' are not sorted by id: {b!r} comes after {a!r}", lst, i1, entity=b, field=lk,
                        expected=f"{b!r} before {a!r}", found=f"index {i1} after {i0}")
                    break
            if lk in ("weapons", "summons", "structures"):
                seen: dict[str, int] = {}
                for i, ident in ids:
                    if ident in seen:
                        add(ctx, "V-SCH-03", lf, f"duplicate id {ident!r} (first at line {line_of(lst, seen[ident])})", lst, i, entity=ident, field="id",
                            expected="unique id", found=ident)
                    seen.setdefault(ident, i)


def check_cross_file_ids(ctx: Ctx) -> None:
    """Weapon / summon ids must be unique across all units files (V-SCH-03)."""
    for lk, prefix in (("weapons", "weapon"), ("summons", "summon")):
        first: dict[str, str] = {}
        for lf in ctx.units_files():
            lst = lf.data.get(lk)  # type: ignore[union-attr]
            if not isinstance(lst, list):
                continue
            for i, e in enumerate(lst):
                ident = e.get("id") if isinstance(e, dict) else None
                if isinstance(ident, str):
                    if ident in first and first[ident] != lf.name:
                        add(ctx, "V-SCH-03", lf, f"{prefix} id {ident!r} is also defined in {first[ident]}", lst, i, entity=ident, field="id",
                            expected="unique across files", found=ident)
                    first.setdefault(ident, lf.name)
