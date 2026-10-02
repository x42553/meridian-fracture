"""`gd docs`: pretty-print the Godot class reference (tools/godot_docs XML) so agents can verify APIs.

The XML in this checkout carries signatures only (descriptions are empty), which is exactly what is
needed to check that a method/property/signal/enum exists and how it is spelled. Descriptions are
printed when a future checkout contains them.
"""
from __future__ import annotations

import difflib
import functools
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Tuple

from . import env

GLOBAL_SCOPES = ("@GlobalScope", "@GDScript")


def docs_root() -> Path:
    """tools/godot_docs when present; otherwise the reference is generated from the engine binary itself
    (`godot --headless --doctool`) into .cache/godot_docs, so a fresh checkout / CI runner needs no download."""
    if (env.DOCS_ROOT / "doc" / "classes").is_dir():
        return env.DOCS_ROOT
    generated = env.CACHE / "godot_docs"
    if not (generated / "doc" / "classes").is_dir():
        binary = env.godot_bin()
        if not binary.exists():
            env.die(f"class reference missing ({env.DOCS_ROOT}) and no Godot binary to generate it: {binary}", 2)
        generated.mkdir(parents=True, exist_ok=True)
        print(f"gd docs: generating the class reference from {binary.name} into {env.rel_to_root(generated)} ...", file=sys.stderr, flush=True)
        r = subprocess.run([str(binary), "--headless", "--doctool", str(generated)], capture_output=True, text=True, cwd=str(generated))
        if r.returncode != 0 or not (generated / "doc" / "classes").is_dir():
            env.die("godot --doctool failed: " + (r.stderr or r.stdout)[-300:], 1)
    return generated


@functools.lru_cache(maxsize=1)
def class_index() -> Dict[str, Path]:
    root = docs_root()
    index: Dict[str, Path] = {}
    patterns = ["doc/classes/*.xml", "modules/*/doc_classes/*.xml", "platform/*/doc_classes/*.xml"]
    for pat in patterns:
        for p in sorted(root.glob(pat)):
            index.setdefault(p.stem, p)
    return index


@functools.lru_cache(maxsize=512)
def load_class(name: str) -> Optional[ET.Element]:
    p = class_index().get(name)
    if p is None:
        return None
    return ET.parse(p).getroot()


def resolve_class_name(name: str) -> Optional[str]:
    idx = class_index()
    if name in idx:
        return name
    lower = {k.lower(): k for k in idx}
    return lower.get(name.lower())


def ancestry(cls: str) -> List[str]:
    chain = [cls]
    seen = {cls}
    while True:
        root = load_class(chain[-1])
        parent = root.get("inherits") if root is not None else None
        if not parent or parent in seen:
            return chain
        chain.append(parent)
        seen.add(parent)


def _type(el: ET.Element) -> str:
    t = el.get("type", "void")
    enum = el.get("enum")
    if enum and t in ("int", "Variant"):
        return f"{enum}"  # e.g. Node.ProcessMode instead of a bare int
    return t


def _params(el: ET.Element) -> str:
    parts = []
    for p in sorted(el.findall("param"), key=lambda e: int(e.get("index", "0"))):
        s = f"{p.get('name')}: {_type(p)}"
        if p.get("default") is not None:
            s += f" = {p.get('default')}"
        parts.append(s)
    if "vararg" in (el.get("qualifiers") or ""):
        parts.append("...")
    return ", ".join(parts)


def method_signature(el: ET.Element, cls: str = "") -> str:
    quals = (el.get("qualifiers") or "").split()
    ret = el.find("return")
    rtype = _type(ret) if ret is not None else "void"
    prefix = " ".join(q for q in quals if q in ("static", "virtual", "abstract")) + (" " if any(q in quals for q in ("static", "virtual", "abstract")) else "")
    suffix = " const" if "const" in quals else ""
    return f"{prefix}{rtype} {el.get('name')}({_params(el)}){suffix}"


def _desc(el: ET.Element) -> str:
    d = el.find("description")
    text = (d.text or "").strip() if d is not None else ""
    return text


def _print_desc(text: str, indent: str = "      ") -> None:
    for line in text.splitlines():
        print(f"{indent}{line.strip()}")


def print_class(cls: str, show_all: bool = False) -> None:
    root = load_class(cls)
    assert root is not None
    chain = ancestry(cls)
    src = class_index()[cls]
    print(f"{cls}" + (f"  <  {'  <  '.join(chain[1:])}" if len(chain) > 1 else "") + f"    [{src.relative_to(docs_root())}]")
    brief = (root.findtext("brief_description") or "").strip()
    if brief:
        print(f"\n{brief}")
    desc = (root.findtext("description") or "").strip()
    if desc:
        print()
        _print_desc(desc, "  ")
    classes = chain if show_all else [cls]
    for c in classes:
        r = load_class(c)
        if r is None:
            continue
        heading = "" if c == cls else f" (inherited from {c})"
        _print_sections(r, heading)
    if not show_all and len(chain) > 1:
        print(f"\n(inherited members: `gd docs {cls} --all`, or `gd docs {cls} <member>` to look one up)")


def _print_sections(r: ET.Element, heading: str) -> None:
    def section(title: str) -> None:
        print(f"\n{title}{heading}")

    ctors = r.findall("constructors/constructor")
    if ctors:
        section("CONSTRUCTORS")
        for m in ctors:
            print(f"  {m.get('name')}({_params(m)})")
    members = r.findall("members/member")
    if members:
        section("PROPERTIES")
        for m in members:
            default = f" = {m.get('default')}" if m.get("default") not in (None, "") else ""
            acc = []
            if m.get("setter"):
                acc.append(f"set: {m.get('setter')}")
            if m.get("getter"):
                acc.append(f"get: {m.get('getter')}")
            print(f"  {m.get('name')}: {_type(m)}{default}" + (f"    ({', '.join(acc)})" if acc else ""))
    methods = r.findall("methods/method")
    if methods:
        section("METHODS")
        for m in methods:
            print(f"  {method_signature(m)}")
    ops = r.findall("operators/operator")
    if ops:
        section("OPERATORS")
        for m in ops:
            ret = m.find("return")
            print(f"  {_type(ret) if ret is not None else 'void'} {m.get('name')}({_params(m)})")
    sigs = r.findall("signals/signal")
    if sigs:
        section("SIGNALS")
        for m in sigs:
            print(f"  {m.get('name')}({_params(m)})")
    consts = r.findall("constants/constant")
    if consts:
        enums: Dict[str, List[ET.Element]] = {}
        plain: List[ET.Element] = []
        for c in consts:
            (enums.setdefault(c.get("enum"), []) if c.get("enum") else plain).append(c)  # type: ignore[arg-type]
        if plain:
            section("CONSTANTS")
            for c in plain:
                print(f"  {c.get('name')} = {c.get('value')}")
        for enum_name, items in enums.items():
            section(f"ENUM {enum_name}")
            print("  " + ", ".join(f"{c.get('name')}={c.get('value')}" for c in items))
    theme = r.findall("theme_items/theme_item")
    if theme:
        section("THEME ITEMS")
        for m in theme:
            default = f" = {m.get('default')}" if m.get("default") else ""
            print(f"  {m.get('data_type')}: {m.get('name')}: {m.get('type')}{default}")
    anns = r.findall("annotations/annotation")
    if anns:
        section("ANNOTATIONS")
        for m in anns:
            print(f"  {m.get('name')}({_params(m)})")


def find_members(cls: str, member: str) -> List[Tuple[str, str, ET.Element]]:
    """Every (declaring class, kind, element) named `member` in cls and its ancestors."""
    out: List[Tuple[str, str, ET.Element]] = []
    kinds = [("method", "methods/method"), ("property", "members/member"), ("signal", "signals/signal"),
             ("constant", "constants/constant"), ("theme item", "theme_items/theme_item"),
             ("constructor", "constructors/constructor"), ("operator", "operators/operator"),
             ("annotation", "annotations/annotation")]
    for c in ancestry(cls):
        r = load_class(c)
        if r is None:
            continue
        for kind, path in kinds:
            for el in r.findall(path):
                name = el.get("name") or ""
                if name == member or name == f"operator {member}" or (kind == "annotation" and name in (member, "@" + member)):
                    out.append((c, kind, el))
    return out


def print_member(cls: str, member: str) -> bool:
    hits = find_members(cls, member)
    if not hits:
        return False
    for declaring, kind, el in hits:
        origin = "" if declaring == cls else f"   (inherited from {declaring})"
        if kind == "method":
            print(f"{declaring}.{method_signature(el)}{origin}")
        elif kind == "property":
            default = f" = {el.get('default')}" if el.get("default") not in (None, "") else ""
            print(f"{declaring}.{el.get('name')}: {_type(el)}{default}{origin}")
            for accessor in ("setter", "getter"):
                acc = el.get(accessor)
                if acc:
                    for d2, k2, e2 in find_members(cls, acc):
                        if k2 == "method":
                            print(f"    {accessor}: {method_signature(e2)}")
                            break
        elif kind == "signal":
            print(f"{declaring}.signal {el.get('name')}({_params(el)}){origin}")
        elif kind == "constant":
            enum = f"  (enum {el.get('enum')})" if el.get("enum") else ""
            print(f"{declaring}.{el.get('name')} = {el.get('value')}{enum}{origin}")
        elif kind == "theme item":
            print(f"{declaring} theme {el.get('data_type')} {el.get('name')}: {el.get('type')}{origin}")
        elif kind == "annotation":
            print(f"{el.get('name')}({_params(el)})")
        else:
            ret = el.find("return")
            print(f"{declaring} {kind} {_type(ret) if ret is not None else ''} {el.get('name')}({_params(el)}){origin}")
        d = _desc(el)
        if d:
            _print_desc(d)
    return True


def find(text: str, limit: int = 80) -> int:
    """Case-insensitive substring search over class names and member names."""
    needle = text.lower()
    n = 0
    print(f"classes matching '{text}':")
    for name in sorted(class_index()):
        if needle in name.lower():
            print(f"  {name}")
            n += 1
            if n >= limit:
                break
    print(f"members matching '{text}':")
    m = 0
    for name in sorted(class_index()):
        r = load_class(name)
        if r is None:
            continue
        for path in ("methods/method", "members/member", "signals/signal", "constants/constant", "annotations/annotation"):
            for el in r.findall(path):
                if needle in (el.get("name") or "").lower():
                    kind = path.split("/")[1]
                    print(f"  {name}.{el.get('name')}  [{kind}]")
                    m += 1
                    if m >= limit:
                        print(f"  ... (more, refine the search)")
                        return n + m
    return n + m


def cmd_docs(args: "object") -> int:
    if getattr(args, "find", None):
        find(args.find)  # type: ignore[attr-defined]
        return 0
    if getattr(args, "list", False):
        pat = (getattr(args, "cls", None) or "").lower()
        for name in sorted(class_index()):
            if pat in name.lower():
                print(name)
        return 0
    name = getattr(args, "cls", None)
    member = getattr(args, "member", None)
    if not name:
        env.die("usage: gd docs <Class> [member] | gd docs --find <text> | gd docs --list [filter]", 2)
    cls = resolve_class_name(name)
    if cls is None:
        # `gd docs roundi` -> global function; `gd docs Vector2i.length` -> Class.member spelling
        if "." in name:
            c2, m2 = name.split(".", 1)
            cls2 = resolve_class_name(c2)
            if cls2 and print_member(cls2, m2):
                return 0
        for scope in GLOBAL_SCOPES:
            if load_class(scope) is not None and print_member(scope, name):
                return 0
        near = difflib.get_close_matches(name, list(class_index()), n=6, cutoff=0.6)
        print(f"gd docs: no class or global named '{name}'" + (f". Did you mean: {', '.join(near)}?" if near else ""), file=sys.stderr)
        print("        try `gd docs --find <text>` to search all class and member names", file=sys.stderr)
        return 1
    if member:
        if print_member(cls, member):
            return 0
        cands = sorted({el.get("name") or "" for c in ancestry(cls) for path in ("methods/method", "members/member", "signals/signal", "constants/constant")
                        for el in (load_class(c).findall(path) if load_class(c) is not None else [])})  # type: ignore[union-attr]
        near = difflib.get_close_matches(member, cands, n=6, cutoff=0.5)
        print(f"gd docs: {cls} (or its ancestors {' < '.join(ancestry(cls)[1:])}) has no member '{member}'"
              + (f". Did you mean: {', '.join(near)}?" if near else ""), file=sys.stderr)
        return 1
    print_class(cls, show_all=bool(getattr(args, "all", False)))
    return 0
