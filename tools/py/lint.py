#!/usr/bin/env python3
"""Project linter for Meridian Fracture (rules L000-L009). Python 3.9+, stdlib only.

Invoked by `tools/gd check`; also usable standalone:

    tools/py/lint.py [--rules L003,L005] [--summary] [--json FILE] [--list-allows] [paths...]

Paths are files or directories (relative to the project root or to game/). Output is one line per
violation, `path:line: RULE message`, sorted; exit status 1 when anything was found.

Escape hatch (a reason is mandatory, otherwise L000 fires and nothing is suppressed):
    some_call()          # lint-allow: L003 reason text     -> suppresses that line
    # lint-allow: L003 reason text                          -> a comment-only line suppresses the NEXT line
    # lint-allow-file: L003 reason text                     -> whole file (use sparingly; audit with --list-allows)
    Several rule ids: `# lint-allow: L003,L008 reason`.  In .tscn/.tres/.cfg/project.godot use `;` instead of `#`.

Rules
    L001  every literal res:// path in .gd/.tscn/.tres/.cfg/.json/.godot/shader files exists with EXACT case
    L002  file-name hygiene under game/: lowercase snake_case ASCII, no spaces, no Windows-reserved names, path < 150
    L003  determinism bans in src/core, src/sim, src/map, src/data (RNG, clocks, floats, float builtins, delta)
    L004  class_name prefix per module directory + global uniqueness
    L005  dependency direction between modules (identifier mentions and res://src/<module> paths); src/ never references res://tests/
    L006  print()/printerr()/push_warning() outside core/log.gd (tests and tools are exempt); TODO without TODO(module)
    L007  .gd files longer than 1500 lines
    L008  `var x =` without a type or `:=` in sim/core/map/data/net/ai
    L009  file name must be the snake_case of its class_name
    L010  CRLF line endings in game text files (docs/ARCHITECTURE.md section 10: LF only; keeps hashes identical on Windows)
"""
from __future__ import annotations

import argparse
import bisect
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

RULES: Dict[str, str] = {
    "L000": "malformed lint-allow directive",
    "L001": "res:// path does not exist (exact case)",
    "L002": "file name hygiene",
    "L003": "determinism ban in a deterministic module",
    "L004": "class_name prefix / uniqueness",
    "L005": "dependency direction",
    "L006": "print/TODO hygiene",
    "L007": "file too long",
    "L008": "untyped variable in a typed module",
    "L009": "file name does not match class_name",
    "L010": "CRLF line endings (LF only)",
    "L011": "invisible / format character in a script (lost by the exported script tokenizer)",
}

MAX_LINES = 1500
MAX_PATH = 150
DETERMINISTIC_MODULES = ("core", "sim", "map", "data")
TYPED_MODULES = ("sim", "core", "map", "data", "net", "ai")
WINDOWS_RESERVED = {"con", "prn", "aux", "nul"} | {f"com{i}" for i in range(1, 10)} | {f"lpt{i}" for i in range(1, 10)}
UPPERCASE_OK = {"README", "README.md", "LICENSE", "LICENSE.txt", "LICENSE.md", "OFL.txt", "COPYING", "NOTICE",
                "AUTHORS", "CHANGELOG.md", "CONTRIBUTING.md", "NOTICE.txt"}

# module directory -> allowed class_name pattern (core is free-form)
CLASS_PREFIX: Dict[str, "re.Pattern[str]"] = {
    "data": re.compile(r"^(Def[A-Z0-9]\w*|GameData)$"),
    "map": re.compile(r"^Map[A-Z0-9]\w*$"),
    "sim": re.compile(r"^Sim[A-Z0-9]\w*$"),
    "net": re.compile(r"^Net[A-Z0-9]\w*$"),
    "ai": re.compile(r"^Ai[A-Z0-9]\w*$"),
    "view": re.compile(r"^(View|Fx)[A-Z0-9]\w*$"),
    "ui": re.compile(r"^Ui[A-Z0-9]\w*$"),
    "audio": re.compile(r"^Snd[A-Z0-9]\w*$"),
    "app": re.compile(r"^App[A-Z0-9]\w*$"),
}
CLASS_PREFIX_HINT = {"data": "Def* or GameData", "map": "Map*", "sim": "Sim*", "net": "Net*", "ai": "Ai*",
                     "view": "View* or Fx*", "ui": "Ui*", "audio": "Snd*", "app": "App*"}

# identifier prefix -> owning module (used by L005)
PREFIX_MODULE = {"Sim": "sim", "Def": "data", "Map": "map", "View": "view", "Fx": "view", "Ui": "ui", "Net": "net",
                 "Ai": "ai", "Snd": "audio", "App": "app"}
MODULE_IDENT = re.compile(r"\b(Sim|Def|Map|View|Fx|Ui|Net|Ai|Snd|App)[A-Z0-9][A-Za-z0-9_]*\b|\bGameData\b")
# modules a module must not mention (spec L005 + architecture section 5: data may not reach up into map)
FORBIDDEN: Dict[str, Set[str]] = {
    "core": {"sim", "data", "map", "view", "ui", "net", "ai", "audio", "app"},
    "data": {"map", "sim", "view", "ui", "net", "ai", "audio", "app"},
    "map": {"sim", "view", "ui", "net", "ai", "audio", "app"},
    "sim": {"view", "ui", "net", "ai", "audio", "app"},
    "net": {"view", "ui", "audio", "app"},
    "ai": {"view", "ui", "audio", "app"},
}
# core classes that legitimately carry a Sim prefix (docs/ARCHITECTURE.md sections 2 and 3)
CORE_SIM_NAMES = {"SimRng", "SimConfig"}

GD_TOKEN = re.compile(
    r"""(?P<tq>[rR]?(?:\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''))"""
    r"""|(?P<str>[rR]?(?:"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))"""
    r"""|(?P<cmt>\#[^\n]*)"""
)
ALLOW_RE = re.compile(r"lint-allow(-file)?:\s*(L\d{3}(?:\s*,\s*L\d{3})*)(?:\s+(\S.*))?")
RES_PATH_RE = re.compile(r"res://[^\"'\s<>|]*")
CLASS_NAME_RE = re.compile(r"^[ \t]*(?:@[A-Za-z_]\w*(?:\([^)\n]*\))?[ \t]+)*class_name[ \t]+([A-Za-z_]\w*)", re.M)
NUMBER_RE = re.compile(r"(?<![\w.])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.\d*|\.\d[\d_]*|\d[\d_]*)(?:[eE][+-]?\d+)?)")
VAR_UNTYPED_RE = re.compile(r"^[ \t]*(?:@[A-Za-z_]\w*(?:\([^)\n]*\))?[ \t]+)*(?:static[ \t]+)?var[ \t]+([A-Za-z_]\w*)[ \t]*(?:=|$)", re.M)
PRINT_RE = re.compile(r"(?<![.\w])(print|printerr|prints|printt|print_rich|print_debug|print_verbose|printraw|push_warning)[ \t]*\(")
TODO_RE = re.compile(r"\bTODO\b(?!\([A-Za-z_][\w-]*\))")
RAND_RE = re.compile(r"(?<![.\w])(?<!func )(randi|randf|randomize|randi_range|randf_range|randfn|rand_from_seed|RandomNumberGenerator|shuffle|pick_random)\b|\.\s*(shuffle|pick_random)\b")
CLOCK_RE = re.compile(r"\bTime\s*\.\s*\w+|\bOS\s*\.\s*get_ticks\w*|\bEngine\s*\.\s*get_\w*frames\w*")
FLOAT_TYPE_RE = re.compile(r"\b(float|Vector[234]|Transform2D|Transform3D|Basis|Quaternion|Color|AABB|Rect2|Plane|Projection|"
                           r"PackedFloat32Array|PackedFloat64Array|PackedVector2Array|PackedVector3Array|PackedVector4Array|PackedColorArray)\b")
DELTA_RE = re.compile(r"\bdelta\b")
FLOAT_CONST_RE = re.compile(r"(?<![.\w])(PI|TAU|INF|NAN)\b")
FLOAT_FUNC_RE = re.compile(r"(?<![.\w])(?<!func )(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|sqrt|pow|exp|log|floor|ceil|round|fmod|fposmod|"
                           r"lerp|lerpf|smoothstep|floori|ceili|roundi|floorf|ceilf|roundf|deg_to_rad|rad_to_deg|snappedf|move_toward|"
                           r"absf|signf|clampf|minf|maxf)[ \t]*\(")
VECTOR_METHOD_RE = re.compile(r"\.\s*(length_squared|normalized|distance_to|distance_squared_to)\s*\(")


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    rule: str
    message: str


@dataclass
class Report:
    violations: List[Violation] = field(default_factory=list)
    suppressed: int = 0
    files: int = 0
    allows: List[Tuple[str, int, str, str, bool]] = field(default_factory=list)  # path, line, rules, reason, file-level

    def by_rule(self) -> Dict[str, int]:
        out: Dict[str, int] = {}
        for v in self.violations:
            out[v.rule] = out.get(v.rule, 0) + 1
        return dict(sorted(out.items()))


class SourceFile:
    """A file plus derived views used by the rules."""

    def __init__(self, path: Path, root: Path, game: Path) -> None:
        self.path = path
        self.rel = path.relative_to(root).as_posix() if _is_under(path, root) else path.as_posix()
        self.rel_game = path.relative_to(game).as_posix() if _is_under(path, game) else None
        self.ext = path.suffix.lower()
        self.name = path.name
        raw = path.read_bytes()
        self.crlf_line = next((i for i, l in enumerate(raw.split(b"\n"), start=1) if l.endswith(b"\r")), 0)
        self.text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n")
        self.lines = self.text.split("\n")
        self._starts: Optional[List[int]] = None
        parts = (self.rel_game or "").split("/")
        self.module: Optional[str] = parts[1] if len(parts) > 2 and parts[0] == "src" else None
        self.code = self.text
        self.strings: List[Tuple[int, str]] = []   # (line, content incl. quotes)
        self.comments: List[Tuple[int, str]] = []  # (line, text after the #)
        self.file_allows: Set[str] = set()
        self.line_allows: Dict[int, Set[str]] = {}
        self.bad_allows: List[Tuple[int, str]] = []
        self.allow_records: List[Tuple[int, str, str, bool]] = []
        if self.ext == ".gd":
            self._tokenise_gd()
        else:
            self._scan_allows_plain()

    def line_of(self, offset: int) -> int:
        if self._starts is None:
            self._starts = [0]
            for m in re.finditer("\n", self.text):
                self._starts.append(m.end())
        return bisect.bisect_right(self._starts, offset)

    def _tokenise_gd(self) -> None:
        def blank(m: "re.Match[str]") -> str:
            return re.sub(r"[^\n]", " ", m.group(0))

        for m in GD_TOKEN.finditer(self.text):
            line = self.line_of(m.start())
            kind = m.lastgroup
            if kind == "str":
                self.strings.append((line, m.group(0)))
            elif kind == "cmt":
                self.comments.append((line, m.group(0)[1:]))
        self.code = GD_TOKEN.sub(blank, self.text)
        code_lines = self.code.split("\n")
        for line, text in self.comments:
            self._register_allow(line, text, code_lines[line - 1].strip() == "" if line - 1 < len(code_lines) else True)

    def _scan_allows_plain(self) -> None:
        # ';' comments in .tscn/.tres/.cfg/.godot; '#' in shaders is a preprocessor directive, use // there.
        for i, raw in enumerate(self.lines, start=1):
            if self.ext in (".gdshader", ".gdshaderinc"):
                idx = raw.find("//")
            elif self.ext == ".json":
                idx = -1
            else:
                idx = raw.find(";")
            if idx < 0:
                continue
            self._register_allow(i, raw[idx + 1:], raw[:idx].strip() == "")

    def _register_allow(self, line: int, text: str, comment_only: bool) -> None:
        if "lint-allow" not in text:
            return
        m = ALLOW_RE.search(text)
        if not m:
            self.bad_allows.append((line, "malformed lint-allow (expected `lint-allow: L003 reason`)"))
            return
        file_level = bool(m.group(1))
        rules = [r.strip() for r in m.group(2).split(",")]
        reason = (m.group(3) or "").strip()
        unknown = [r for r in rules if r not in RULES or r == "L000"]
        if unknown:
            self.bad_allows.append((line, f"lint-allow names unknown rule(s) {','.join(unknown)}"))
            return
        if not reason:
            self.bad_allows.append((line, "lint-allow needs a reason after the rule id"))
            return
        self.allow_records.append((line, ",".join(rules), reason, file_level))
        if file_level:
            self.file_allows.update(rules)
            return
        target = line + 1 if comment_only else line
        self.line_allows.setdefault(target, set()).update(rules)

    def allowed(self, rule: str, line: int) -> bool:
        return rule in self.file_allows or rule in self.line_allows.get(line, ())


def _is_under(p: Path, base: Path) -> bool:
    try:
        p.relative_to(base)
        return True
    except ValueError:
        return False


class Linter:
    def __init__(self, root: Path, game: Path, rules: Optional[Set[str]] = None) -> None:
        self.root = root
        self.game = game
        self.rules = rules or set(RULES)
        self.files: List[SourceFile] = []
        self.report = Report()
        self._dir_cache: Dict[Path, List[str]] = {}
        self._registry: Dict[str, Tuple[str, Optional[str], int]] = {}  # class_name -> (rel path, module, line)

    # -- collection ------------------------------------------------------------------------------
    def collect(self) -> None:
        exts = {".gd", ".tscn", ".tres", ".cfg", ".json", ".godot", ".gdshader", ".gdshaderinc"}
        stack = [self.game]
        while stack:
            d = stack.pop()
            try:
                entries = sorted(os.scandir(d), key=lambda e: e.name)
            except OSError:
                continue
            for e in entries:
                if e.name in (".godot", ".import") or e.name.startswith(".git"):
                    continue
                if e.is_dir(follow_symlinks=False):
                    stack.append(Path(e.path))
                elif os.path.splitext(e.name)[1].lower() in exts:
                    try:
                        self.files.append(SourceFile(Path(e.path), self.root, self.game))
                    except OSError:
                        continue
        self.report.files = len(self.files)
        for f in self.files:
            if f.ext == ".gd":
                for m in CLASS_NAME_RE.finditer(f.code):
                    name = m.group(1)
                    self._registry.setdefault(name, (f.rel, f.module, f.line_of(m.start(1))))
            for rec in f.allow_records:
                self.report.allows.append((f.rel, rec[0], rec[1], rec[2], rec[3]))

    # -- reporting ---------------------------------------------------------------------------------
    def add(self, f: SourceFile, line: int, rule: str, message: str) -> None:
        if rule not in self.rules and rule != "L000":
            return
        if rule != "L000" and f.allowed(rule, line):
            self.report.suppressed += 1
            return
        self.report.violations.append(Violation(f.rel, line, rule, message))

    def add_path(self, rel: str, rule: str, message: str) -> None:
        if rule in self.rules:
            self.report.violations.append(Violation(rel, 1, rule, message))

    INVISIBLE = re.compile("[\u00ad\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u2064\ufeff]")

    def rule_l011(self, f) -> None:
        """A string literal holding U+FEFF (BOM) was silently emptied by the exported (tokenized) scripts: begins_with("") is always true
        and the first character of every JSON file was cut off. Use unicode_at(0) == 0xFEFF / "\\uFEFF" escapes only."""
        if "L011" not in self.rules:
            return
        for i, raw in enumerate(f.lines, start=1):
            m = self.INVISIBLE.search(raw)
            if m:
                self.add(f, i, "L011", f"invisible character U+{ord(m.group(0)):04X}; spell it with unicode_at()/char() instead of a literal")

    # -- run all rules -----------------------------------------------------------------------------
    def run(self) -> Report:
        self.collect()
        for f in self.files:
            for line, msg in f.bad_allows:
                self.add(f, line, "L000", msg)
            self.rule_l001(f)
            if f.crlf_line:
                self.add(f, f.crlf_line, "L010", "CRLF line ending; convert the file to LF (git: `* text=auto eol=lf`)")
            if f.ext == ".gd":
                self.rule_l011(f)
                self.rule_l003(f)
                self.rule_l004_l009(f)
                self.rule_l005(f)
                self.rule_l006(f)
                self.rule_l007(f)
                self.rule_l008(f)
        self.rule_l002()
        self.rule_l004_unique()
        self.report.violations.sort(key=lambda v: (v.path, v.line, v.rule, v.message))
        return self.report

    # -- L001 ---------------------------------------------------------------------------------------
    def _listdir(self, d: Path) -> List[str]:
        got = self._dir_cache.get(d)
        if got is None:
            try:
                got = os.listdir(d)
            except OSError:
                got = []
            self._dir_cache[d] = got
        return got

    def _resolve_exact(self, rel: str, want_dir: bool) -> Optional[str]:
        """None when `rel` (relative to game/) exists with exact case; otherwise a description of the problem."""
        cur = self.game
        parts = [p for p in rel.split("/") if p]
        for i, part in enumerate(parts):
            names = self._listdir(cur)
            if part in names:
                cur = cur / part
                continue
            for n in names:
                if n.lower() == part.lower():
                    return f"case mismatch: '{part}' is '{n}' on disk (Linux is case sensitive)"
            return f"'{'/'.join(parts[:i + 1])}' does not exist"
        if want_dir and not cur.is_dir():
            return f"'{rel}' is not a directory"
        return None

    def rule_l001(self, f: SourceFile) -> None:
        if "L001" not in self.rules:
            return
        if f.ext == ".gd":
            sources = [(line, s) for line, s in f.strings]
        else:
            sources = []
            for i, raw in enumerate(f.lines, start=1):
                if "res://" in raw:
                    sources.append((i, raw))
        for line, chunk in sources:
            for m in RES_PATH_RE.finditer(chunk):
                self._check_res_path(f, line, m.group(0))

    def _check_res_path(self, f: SourceFile, line: int, path: str) -> None:
        path = path.rstrip(".,;:)")
        rel = path[len("res://"):]
        if not rel or rel.split("/", 1)[0] in (".godot", "addons"):
            return  # engine cache and the (optional, never shipped) addons dir named by directory_rules
        cut = min((rel.find(ch) for ch in "%{*$?[\\" if ch in rel), default=-1)
        if cut >= 0:
            # a format/glob placeholder: only the directory part before it can be verified
            head = rel[:cut]
            rel = head[: head.rfind("/") + 1] if "/" in head else ""
            if not rel:
                return
        want_dir = rel.endswith("/")
        problem = self._resolve_exact(rel.rstrip("/"), want_dir)
        if problem:
            self.add(f, line, "L001", f"res://{rel}: {problem}")

    # -- L002 ---------------------------------------------------------------------------------------
    def rule_l002(self) -> None:
        if "L002" not in self.rules:
            return
        stack = [self.game]
        while stack:
            d = stack.pop()
            try:
                entries = sorted(os.scandir(d), key=lambda e: e.name)
            except OSError:
                continue
            for e in entries:
                if e.name in (".godot", ".import") or e.name.startswith(".git") or e.name == ".DS_Store":
                    continue
                rel = os.path.relpath(e.path, self.root).replace(os.sep, "/")
                is_dir = e.is_dir(follow_symlinks=False)
                problem = self._name_problem(e.name, is_dir)
                if problem:
                    self.add_path(rel, "L002", problem)
                if len(rel) >= MAX_PATH:
                    self.add_path(rel, "L002", f"path is {len(rel)} chars long (limit {MAX_PATH - 1}); Windows path limits")
                if is_dir:
                    stack.append(Path(e.path))

    @staticmethod
    def _name_problem(name: str, is_dir: bool) -> Optional[str]:
        stem = name.split(".")[0].lower() if not name.startswith(".") else ""
        if stem in WINDOWS_RESERVED:
            return f"'{name}' is a reserved Windows device name"
        if name in UPPERCASE_OK and not is_dir:
            return None
        if name.startswith("."):
            return None  # hidden files (.gdignore, .gitkeep, .godot handled above)
        if " " in name:
            return f"'{name}' contains a space"
        if not name.isascii():
            return f"'{name}' contains non-ASCII characters"
        pattern = r"[a-z0-9_]+" if is_dir else r"[a-z0-9_]+(\.[a-z0-9_]+)*"
        if not re.fullmatch(pattern, name):
            why = "uppercase letters" if any(c.isupper() for c in name) else "characters other than a-z 0-9 _" + ("" if is_dir else " and dots")
            return f"'{name}' must be lowercase snake_case ASCII (found {why})"
        return None

    # -- L003 ---------------------------------------------------------------------------------------
    def rule_l003(self, f: SourceFile) -> None:
        if f.module not in DETERMINISTIC_MODULES or "L003" not in self.rules:
            return
        floats_ok = f.module == "data" and (f.name.endswith("_loader.gd") or f.name.endswith("_parse.gd"))
        for i, line in enumerate(f.code.split("\n"), start=1):
            if not line.strip():
                continue
            for m in RAND_RE.finditer(line):
                self.add(f, i, "L003", f"'{m.group(0).strip('. ')}' is non-deterministic; use SimRng (DR-2)")
            for m in CLOCK_RE.finditer(line):
                self.add(f, i, "L003", f"'{re.sub(chr(32), '', m.group(0))}' reads a clock or frame counter; the sim has no wall-clock (DR-3)")
            if floats_ok:
                continue
            for m in NUMBER_RE.finditer(line):
                tok = m.group(0)
                if tok.lower().startswith(("0x", "0b")):
                    continue
                if "." in tok or "e" in tok.lower():
                    self.add(f, i, "L003", f"float literal '{tok}' in a deterministic module; use integers / Fp (DR-1)")
            for m in FLOAT_TYPE_RE.finditer(line):
                self.add(f, i, "L003", f"float type '{m.group(0)}' in a deterministic module (DR-1)")
            for m in DELTA_RE.finditer(line):
                self.add(f, i, "L003", "'delta' (frame time) must not exist in the sim (DR-3)")
            for m in FLOAT_CONST_RE.finditer(line):
                self.add(f, i, "L003", f"float constant '{m.group(1)}' in a deterministic module (DR-1)")
            for m in FLOAT_FUNC_RE.finditer(line):
                self.add(f, i, "L003", f"float builtin '{m.group(1)}()'; use Fp.* / integer math (DR-4)")
            for m in VECTOR_METHOD_RE.finditer(line):
                self.add(f, i, "L003", f"'.{m.group(1)}()' is float / int32-overflow prone; use Fp helpers (DR-1)")

    # -- L004 / L009 --------------------------------------------------------------------------------
    def rule_l004_l009(self, f: SourceFile) -> None:
        for m in CLASS_NAME_RE.finditer(f.code):
            name = m.group(1)
            line = f.line_of(m.start(1))
            pattern = CLASS_PREFIX.get(f.module or "")
            if pattern is not None and not pattern.match(name):
                self.add(f, line, "L004", f"class_name '{name}' in src/{f.module}/ must be {CLASS_PREFIX_HINT[f.module or '']}")
            stem = f.name[:-3]
            if name.lower() != stem.replace("_", "").lower() and "L009" in self.rules:
                self.add(f, line, "L009", f"file '{f.name}' should be '{_snake(name)}.gd' for class_name {name}")

    def rule_l004_unique(self) -> None:
        if "L004" not in self.rules:
            return
        seen: Dict[str, Tuple[SourceFile, int]] = {}
        for f in self.files:
            if f.ext != ".gd":
                continue
            for m in CLASS_NAME_RE.finditer(f.code):
                name = m.group(1)
                line = f.line_of(m.start(1))
                if name in seen:
                    other, oline = seen[name]
                    self.add(f, line, "L004", f"class_name '{name}' is already declared in {other.rel}:{oline}")
                else:
                    seen[name] = (f, line)

    # -- L005 ---------------------------------------------------------------------------------------
    def rule_l005(self, f: SourceFile) -> None:
        mod = f.module
        if mod is not None and "L005" in self.rules:
            for line, s in f.strings:
                if "res://tests/" in s:
                    self.add(f, line, "L005", "shipped code must not reference res://tests/ (tests are excluded from exports)")
        if mod not in FORBIDDEN or "L005" not in self.rules:
            return
        forbidden = FORBIDDEN[mod]
        allowed_here = {"core": {"core"}, "data": {"core", "data"}, "map": {"core", "data", "map"},
                        "sim": {"core", "data", "map", "sim"}, "net": {"core", "data", "map", "sim", "net", "ai"},
                        "ai": {"core", "data", "map", "sim", "ai", "net"}}[mod]
        for i, line in enumerate(f.code.split("\n"), start=1):
            for m in MODULE_IDENT.finditer(line):
                ident = m.group(0)
                target = "data" if ident == "GameData" else PREFIX_MODULE[m.group(1)]
                if target not in forbidden:
                    continue
                declared = self._registry.get(ident)
                if declared is not None and declared[1] in allowed_here:
                    continue  # e.g. SimRng / SimConfig live in core on purpose
                if ident in CORE_SIM_NAMES and "core" in allowed_here:
                    continue
                self.add(f, i, "L005", f"src/{mod} must not depend on {target} ('{ident}'); allowed direction: core <- data <- map <- sim <- net/ai")
        for line, s in f.strings:
            m = re.search(r"res://src/([a-z_]+)/", s)
            if m and m.group(1) in forbidden:
                self.add(f, line, "L005", f"src/{mod} must not reference res://src/{m.group(1)}/ (dependency direction)")

    # -- L006 ---------------------------------------------------------------------------------------
    def rule_l006(self, f: SourceFile) -> None:
        if "L006" not in self.rules:
            return
        in_src = f.rel_game is not None and f.rel_game.startswith("src/")
        if in_src and f.rel_game != "src/core/log.gd":
            for i, line in enumerate(f.code.split("\n"), start=1):
                for m in PRINT_RE.finditer(line):
                    self.add(f, i, "L006", f"{m.group(1)}() outside core/log.gd; use Log.info/warn/error")
        for line, text in f.comments:
            if TODO_RE.search(text):
                self.add(f, line, "L006", "TODO without an owner tag; write TODO(module): what")

    # -- L007 / L008 --------------------------------------------------------------------------------
    def rule_l007(self, f: SourceFile) -> None:
        n = len(f.lines) - (1 if f.lines and f.lines[-1] == "" else 0)
        if n > MAX_LINES:
            self.add(f, MAX_LINES + 1, "L007", f"file has {n} lines (limit {MAX_LINES}); split by responsibility")

    def rule_l008(self, f: SourceFile) -> None:
        if f.module not in TYPED_MODULES or "L008" not in self.rules:
            return
        for m in VAR_UNTYPED_RE.finditer(f.code):
            self.add(f, f.line_of(m.start(1)), "L008", f"'var {m.group(1)}' has no type; write `var {m.group(1)}: T =` or `var {m.group(1)} :=`")


def _snake(name: str) -> str:
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s).lower()


def run(root: Path, game: Path, targets: Optional[Sequence[Path]] = None, rules: Optional[Set[str]] = None) -> Report:
    """Lint the project. `targets` (files/dirs) restricts which violations are reported; cross-file rules
    (class_name registry, uniqueness) always see the whole project."""
    linter = Linter(root.resolve(), game.resolve(), rules)
    report = linter.run()
    if targets:
        resolved = [Path(t).resolve() for t in targets]
        keep: List[Violation] = []
        for v in report.violations:
            p = (root / v.path).resolve()
            if any(p == t or _is_under(p, t) for t in resolved):
                keep.append(v)
        report.violations = keep
    return report


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Meridian Fracture project linter")
    ap.add_argument("paths", nargs="*", help="files or directories (project-root or game/-relative); default: everything under game/")
    ap.add_argument("--root", default=os.environ.get("GD_ROOT") or str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--game", default=None, help="Godot project dir (default <root>/game)")
    ap.add_argument("--rules", help="comma separated rule ids (default all)")
    ap.add_argument("--summary", action="store_true", help="print counts per rule instead of every violation")
    ap.add_argument("--json", metavar="FILE", help="write violations as JSON")
    ap.add_argument("--list-allows", action="store_true", help="list every lint-allow directive (audit)")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args(argv)
    if args.list_rules:
        for rid, desc in RULES.items():
            print(f"{rid}  {desc}")
        return 0
    root = Path(args.root).resolve()
    game = Path(args.game).resolve() if args.game else Path(os.environ.get("GD_GAME_DIR") or root / "game").resolve()
    targets: List[Path] = []
    for p in args.paths:
        cand = Path(p)
        for base in (Path.cwd(), root, game):
            if (base / cand).exists():
                targets.append(base / cand)
                break
        else:
            print(f"lint: path not found: {p}", file=sys.stderr)
            return 2
    rules = {r.strip() for r in args.rules.split(",")} if args.rules else None
    if rules and not rules <= set(RULES):
        print(f"lint: unknown rule id(s): {', '.join(sorted(rules - set(RULES)))}", file=sys.stderr)
        return 2
    report = run(root, game, targets or None, rules)
    if args.list_allows:
        for path, line, rl, reason, file_level in report.allows:
            print(f"{path}:{line}: {'ALLOW-FILE' if file_level else 'ALLOW'} {rl} {reason}")
        return 0
    if args.json:
        Path(args.json).write_text(json.dumps([v.__dict__ for v in report.violations], indent=1))
    if args.summary:
        for rid, n in report.by_rule().items():
            print(f"{rid}  {n:5d}  {RULES[rid]}")
        print(f"total {len(report.violations)} violation(s), {report.suppressed} suppressed, {report.files} files scanned")
    else:
        for v in report.violations:
            print(f"{v.path}:{v.line}: {v.rule} {v.message}")
        print(f"lint: {report.files} files, {len(report.violations)} violation(s)"
              + (f", {report.suppressed} suppressed by lint-allow" if report.suppressed else ""), file=sys.stderr)
    return 1 if report.violations else 0


if __name__ == "__main__":
    sys.exit(main())
