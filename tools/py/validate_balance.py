#!/usr/bin/env python3
"""Validate game/data/balance/*.json (spec docs/spec/data_balance.md 5.12 / 7.x). Stdlib only, never writes into game/.

  python3 tools/py/validate_balance.py                       # everything the manifest lists + global.json + the bible prerequisites
  python3 tools/py/validate_balance.py --strict              # warnings also fail (exit 2); V-CNF-09 becomes an error
  python3 tools/py/validate_balance.py --only units_napc.json[,units_han.json]   # report only these files (rule prefixes work too: --only V-CMP,V-CNF)
  python3 tools/py/validate_balance.py --json                # machine-readable report
  python3 tools/py/validate_balance.py --list-rules          # the rule table

--only names: manifest.json, global.json, bible (prerequisite graph), any manifest file, or a rule id prefix such as V-CMP / V-ABL-05.
Waivers: tools/py/balance_lib/waivers.json lists warnings that are accepted on purpose (rule, id '<file>:<entity>.<field>', reason). A waived warning
does not count (`--strict` exits 0), `-v` still prints it, a waiver that matches nothing is reported as V-WAIVER-01 (warning). `--no-waivers` ignores the file.
Exit codes: 0 clean, 1 errors, 2 warnings (only with --strict), 3 usage error.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from balance_lib import convert  # noqa: E402
from balance_lib.context import EXPECTED_FILES, ROOT, Ctx  # noqa: E402
from balance_lib.report import E, I, RULES, SEV_NAME, W, Report  # noqa: E402
from balance_lib.rules_files import check_cross_file_ids, check_file, check_manifest  # noqa: E402
from balance_lib.rules_global import check_bible, check_global  # noqa: E402
from balance_lib.rules_registry import check_registry  # noqa: E402
from balance_lib.rules_structures import check_structures_file  # noqa: E402
from balance_lib.rules_units import check_units_file  # noqa: E402

WAIVERS = HERE / "balance_lib" / "waivers.json"
SCOPES = ["manifest.json", "global.json", "bible"] + EXPECTED_FILES


def run(balance: Path, bible: Path, strict: bool = False, strict_redundant: bool = False) -> tuple[Ctx, Report]:
    rep = Report(strict=strict, strict_redundant=strict_redundant)
    ctx = Ctx(balance, bible, rep)
    check_manifest(ctx)
    for name in sorted(ctx.files):
        if name == "manifest.json":
            continue
        lf = ctx.files[name]
        check_file(ctx, lf)
    check_cross_file_ids(ctx)
    for lf in ctx.units_files():
        check_units_file(ctx, lf)
    st = ctx.files.get("structures.json")
    if st and st.ok and ctx.b_structs:
        check_structures_file(ctx, st)
    ak = ctx.files.get("ability_kinds.json")
    if ak and ak.ok:
        check_registry(ctx, ak)
    check_global(ctx)
    check_bible(ctx)
    return ctx, rep


def finding_id(f) -> str:
    return f"{f.file}:{f.entity}" + (f".{f.field}" if f.field and not f.entity.endswith("." + f.field) else "")


def apply_waivers(rep: Report, path: Path, check_stale: bool) -> int:
    """Downgrades the waived warnings to INFO ('waived: <reason>') and returns how many. Errors are never waived."""
    if not path.is_file():
        return 0
    doc = json.loads(path.read_text(encoding="utf-8"))
    table: dict[tuple[str, str], str] = {}
    for w in doc.get("waivers", []):
        if not (w.get("rule") and w.get("id") and str(w.get("reason", "")).strip()):
            rep.add("V-WAIVER-01", "waivers.json", f"waiver without rule / id / reason: {w}", sev=E)
            continue
        table[(w["rule"], w["id"])] = str(w["reason"])
    used: set[tuple[str, str]] = set()
    for f in rep.findings:
        key = (f.rule, finding_id(f))
        if f.severity == W and key in table:
            f.severity = I
            f.message = f"(waived: {table[key]}) " + f.message
            used.add(key)
    if check_stale:
        for key in sorted(set(table) - used):
            rep.add("V-WAIVER-01", "waivers.json", f"stale waiver {key[0]} {key[1]!r} matches no finding (remove it)", entity=key[1])
    return len(used)


def select(rep: Report, only: list[str]) -> list:
    files = {o for o in only if o in SCOPES}
    rules = [o.upper() for o in only if o not in SCOPES]
    out = []
    for f in rep.findings:
        if files and f.file not in files:
            continue
        if rules and not any(f.rule.startswith(r) for r in rules):
            continue
        out.append(f)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Validate the Meridian Fracture balance data files.", epilog=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true", help="warnings fail the run (exit 2); V-CNF-09 is an error")
    ap.add_argument("--strict-redundant", action="store_true", help="V-CNF-02 (balance repeats a bible value) becomes a warning")
    ap.add_argument("--only", action="append", default=[], metavar="NAME[,NAME]", help="report only these files / rule prefixes (repeatable)")
    ap.add_argument("--no-waivers", action="store_true", help="ignore tools/py/balance_lib/waivers.json")
    ap.add_argument("--list-rules", action="store_true", help="print the rule table and exit")
    ap.add_argument("--json", action="store_true", help="print a JSON report instead of text")
    ap.add_argument("--self-test", action="store_true", help="check the converter against the spec vectors and exit")
    ap.add_argument("-v", "--verbose", action="store_true", help="also print INFO findings")
    ap.add_argument("--bible", default=str(ROOT / "game/data/bible/meridian_factions.json"), help="bible JSON (default: the mirror in game/data/bible)")
    ap.add_argument("--balance", default=str(ROOT / "game/data/balance"), help="balance directory (default: game/data/balance)")
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 3 if e.code else 0
    if args.list_rules:
        for rid, (sev, text, ext) in sorted(RULES.items()):
            print(f"{rid:9} {SEV_NAME[sev]:5} {'(ext) ' if ext else ''}{text}")
        return 0
    if args.self_test:
        bad = convert.self_test()
        print("self-test: " + ("ok (%d converter vectors)" % len(convert.VECTORS) if not bad else "FAILED\n  " + "\n  ".join(bad)))
        return 1 if bad else 0
    only = [x.strip() for o in args.only for x in o.split(",") if x.strip()]
    for o in only:
        if o not in SCOPES and not o.upper().startswith("V-"):
            print(f"usage: unknown --only name {o!r}; use one of {', '.join(SCOPES)} or a rule prefix like V-CMP", file=sys.stderr)
            return 3
    bal, bib = Path(args.balance), Path(args.bible)
    if not bal.is_dir():
        print(f"usage: balance directory {bal} does not exist", file=sys.stderr)
        return 3
    ctx, rep = run(bal, bib, args.strict, args.strict_redundant)
    waived = 0
    if not args.no_waivers and bal.resolve() == (ROOT / "game/data/balance").resolve():  # the waivers describe the shipped data only
        waived = apply_waivers(rep, WAIVERS, check_stale=not only)
    found = select(rep, only)
    sub = Report(strict=args.strict)
    sub.findings = found
    n = {E: sub.count(E), W: sub.count(W), I: sub.count(I)}
    if args.json:
        print(json.dumps({"findings": [f.as_dict() for f in found], "summary": {"errors": n[E], "warnings": n[W], "info": n[I], "strict": args.strict,
                                                                                  "exit_code": sub.exit_code()}}, indent=2))
        return sub.exit_code()
    shown = [f for f in found if f.severity != I or args.verbose]
    by_rule: dict[str, list] = {}
    for f in shown:
        by_rule.setdefault(f.rule, []).append(f)
    for rid in sorted(by_rule):
        sev = RULES[rid][0]
        print(f"== {rid} ({SEV_NAME[sev]}) {RULES[rid][1]}")
        for f in sorted(by_rule[rid], key=lambda x: (x.file, x.line, x.entity)):
            print("  " + f.text())
    scope = ", ".join(only) if only else "all files"
    print(f"validate_balance: {n[E]} error(s), {n[W]} warning(s), {n[I]} info{'' if args.verbose or not n[I] else ' (use -v)'}{f', {waived} waived' if waived else ''} [{scope}]"
          + (" --strict" if args.strict else ""))
    return sub.exit_code()


if __name__ == "__main__":
    sys.exit(main())
