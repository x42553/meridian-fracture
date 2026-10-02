#!/usr/bin/env python3
"""pck_list.py - list / audit a Godot .pck (format v2/v3) without the engine.

  python3 tools/py/pck_list.py FILE.pck                 summary by extension
  python3 tools/py/pck_list.py FILE.pck --list          every entry: size md5 path
  python3 tools/py/pck_list.py A.pck --compare B.pck    same entry set + md5s? (exit 1 when not)
  python3 tools/py/pck_list.py FILE.pck --audit         check the shipping rules (runtime data in, tests/tools/docs out)
"""
from __future__ import annotations

import argparse
import collections
import struct
import sys


def read_pck(path):
    with open(path, "rb") as f:
        data = f.read(64)
        if data[:4] != b"GDPC":
            raise SystemExit(f"{path}: not a .pck (magic {data[:4]!r})")
        fmt, vmaj, vmin, vpat = struct.unpack_from("<4I", data, 4)
        if fmt >= 2:
            flags, file_base, dir_off = struct.unpack_from("<IQQ", data, 20)
        else:
            raise SystemExit(f"{path}: pack format {fmt} unsupported")
        f.seek(dir_off)
        n = struct.unpack("<I", f.read(4))[0]
        entries = []
        for _ in range(n):
            plen = struct.unpack("<I", f.read(4))[0]
            p = f.read(plen).rstrip(b"\0").decode("utf-8")
            off, size = struct.unpack("<QQ", f.read(16))
            md5 = f.read(16).hex()
            eflags = struct.unpack("<I", f.read(4))[0]
            entries.append((p, size, md5, eflags, off))
    return {"format": fmt, "engine": f"{vmaj}.{vmin}.{vpat}", "entries": entries}


REQUIRED_PREFIXES = ["res://data/", "res://assets/fonts/", "res://assets/shaders/", "res://assets/audio/", "res://src/"]
FORBIDDEN_PARTS = ["tests/", "tools/", "prototypes/", "docs/", "Input/"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pck")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--compare")
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--project", help="game/ directory: check every shippable project file is in the pck")
    a = ap.parse_args()
    pk = read_pck(a.pck)
    pk["entries"] = [(p[6:] if p.startswith("res://") else p, *rest) for p, *rest in pk["entries"]]
    ents = pk["entries"]
    if a.list:
        for p, s, m, _, _ in ents:
            print(f"{s:>10} {m} {p}")
        return 0
    if a.compare:
        other = read_pck(a.compare)
        other["entries"] = [(p[6:] if p.startswith("res://") else p, *rest) for p, *rest in other["entries"]]
        da = {p: m for p, _, m, _, _ in ents}
        db = {p: m for p, _, m, _, _ in other["entries"]}
        only_a = sorted(set(da) - set(db))
        only_b = sorted(set(db) - set(da))
        diff = sorted(p for p in set(da) & set(db) if da[p] != db[p])
        print(f"entries: {len(da)} vs {len(db)}; only-in-A {len(only_a)}, only-in-B {len(only_b)}, md5-differs {len(diff)}")
        for p in (only_a + only_b + diff)[:20]:
            print("  ", p)
        return 0 if not (only_a or only_b or diff) else 1
    exts = collections.Counter()
    sizes = collections.Counter()
    for p, s, _, _, _ in ents:
        e = p.rsplit(".", 1)[-1] if "." in p.rsplit("/", 1)[-1] else "(none)"
        exts[e] += 1
        sizes[e] += s
    print(f"{a.pck}: pack format {pk['format']} engine {pk['engine']} entries {len(ents)} total {sum(s for _, s, *_ in ents)/1e6:.1f} MB")
    for e, c in exts.most_common():
        print(f"  {e:<14} {c:>6} files {sizes[e]/1e6:>8.2f} MB")
    if a.audit:
        paths = [p for p, *_ in ents]
        bad = [p for p in paths if any(p.startswith(x) for x in FORBIDDEN_PARTS) or p.endswith(".md")]
        print(f"forbidden entries (tests/tools/prototypes/docs/Input/*.md): {len(bad)}")
        for p in bad[:10]:
            print("   ", p)
        # runtime data types that must be present
        need = {
            "json": "res://data/", "ogg": ".oggvorbisstr", "font": ".fontdata", "gdshader": ".gdshader",
        }
        have = {
            "json (data)": sum(1 for p in paths if p.startswith("data/") and p.endswith(".json")),
            "json (anywhere)": sum(1 for p in paths if p.endswith(".json")),
            "ogg (oggvorbisstr)": sum(1 for p in paths if p.endswith(".oggvorbisstr")),
            "ttf/otf/fontdata": sum(1 for p in paths if p.endswith((".fontdata", ".ttf", ".otf"))),
            "png/ctex": sum(1 for p in paths if p.endswith((".png", ".ctex"))),
            "gdshader(+.remap)": sum(1 for p in paths if ".gdshader" in p),
            "gdshaderinc": sum(1 for p in paths if ".gdshaderinc" in p),
            "cfg/txt/csv": sum(1 for p in paths if p.endswith((".cfg", ".txt", ".csv"))),
            "gd/gdc (+.remap)": sum(1 for p in paths if ".gd" in p.rsplit("/", 1)[-1]),
            "tscn/scn": sum(1 for p in paths if ".tscn" in p or ".scn" in p),
        }
        for k, v in have.items():
            print(f"  {k:<22} {v}")
        missing = []
        if a.project:
            import os
            have_set = set(paths)
            for dp, dn, fn in os.walk(a.project):
                dn[:] = [d for d in dn if d not in (".godot", "tests")]
                for f in fn:
                    if f.endswith((".import", ".uid", ".md5", ".md", ".DS_Store", ".gdignore")) or f in ("export_presets.cfg", "project.godot"):
                        continue
                    rel = os.path.relpath(os.path.join(dp, f), a.project)
                    cand = {rel, rel + ".remap"}
                    if rel.endswith(".ogg"):
                        cand.add(rel)  # imported: located via the .import remap
                    if not (cand & have_set) and not any(q.startswith(".godot/imported/" + f + "-") for q in paths):
                        missing.append(rel)
            print(f"project files missing from the pck: {len(missing)}")
            for m in missing[:20]:
                print("   ", m)
        return 1 if (bad or missing) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
