"""Loading and shared lookups for validate_balance.py: manifest, balance files, global.json, the bible, effective-value resolution."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from . import vocab
from .jsonio import LDict, parse
from .report import Report
from .schemalib import SchemaSet

ROOT = Path(__file__).resolve().parents[3]
EXPECTED_FILES = sorted(
    ["ability_kinds.json", "faction_traits.json", "global.json", "map_gen.json", "neutral_structures.json", "power_actions.json", "research_effects.json",
     "structures.json", "terrain.json", "zone_templates.json"] + [f"units_{c}.json" for c in vocab.UNIT_CODES])
SCHEMA_NAME = {"global.json": None}  # global.json carries "version": 1 instead of a schema key
ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")


def schema_key(fname: str) -> str | None:
    """Expected value of the "schema" key of a data-owned file (meridian.balance.<name>/1)."""
    if fname == "global.json":
        return None
    if fname == "manifest.json":
        return "meridian.balance.manifest/1"
    if fname.startswith("units_"):
        return "meridian.balance.units/1"
    return f"meridian.balance.{fname[:-5]}/1"


def unit_code(fname: str) -> str:
    return fname[len("units_"):-len(".json")]


@dataclass
class LoadedFile:
    name: str
    path: Path
    exists: bool = False
    text: str = ""
    data: object = None
    problems: list = field(default_factory=list)  # (line, rule, message) from the parser

    @property
    def ok(self) -> bool:
        return isinstance(self.data, dict)


class Ctx:
    def __init__(self, balance_dir: Path, bible_path: Path, rep: Report, schema_dir: Path | None = None) -> None:
        self.dir = Path(balance_dir)
        self.bible_path = Path(bible_path)
        self.rep = rep
        self.schemas = SchemaSet(schema_dir or self.dir / "schema")
        self.files: dict[str, LoadedFile] = {}
        self.manifest = self._load("manifest.json")
        self.g: dict = {}
        self.bible: dict = {}
        self.g_error = ""
        self.bible_error = ""
        self._load_global_bible()
        self.manifest_files: list[str] = []
        if self.manifest.ok and isinstance(self.manifest.data.get("files"), list):  # type: ignore[union-attr]
            self.manifest_files = [f for f in self.manifest.data["files"] if isinstance(f, str)]  # type: ignore[index]
        for n in sorted(set(self.manifest_files) | set(EXPECTED_FILES)):
            if n != "global.json":
                self.files[n] = self._load(n)
        # lookups
        self.arch: dict = self.g.get("archetypes", {})
        self.service: dict = self.g.get("service_units", {})
        self.wa: dict = self.g.get("weapon_archetypes", {})
        self.ua: dict = self.g.get("unit_assignments", {})
        self.b_units: dict = self.bible.get("units", {})
        self.b_structs: dict = self.bible.get("structures", {})
        self.conv: dict = self.bible.get("mechanical_conventions", {})
        self._locked: set[str] | None = None
        self._bible_tags: set[str] | None = None

    # ---- loading
    def _load(self, name: str) -> LoadedFile:
        p = self.dir / name
        lf = LoadedFile(name, p)
        if p.is_file():
            lf.exists = True
            lf.text = p.read_text(encoding="utf-8")
            lf.data, lf.problems = parse(lf.text)
        self.files[name] = lf
        return lf

    def _load_global_bible(self) -> None:
        gp = self.dir / "global.json"
        try:
            self.g = json.loads(gp.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            self.g_error = f"cannot read global.json: {e}"
        try:
            self.bible = json.loads(self.bible_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            self.bible_error = f"cannot read bible {self.bible_path}: {e}"

    # ---- file access
    def units_files(self) -> list[LoadedFile]:
        return [self.files[f"units_{c}.json"] for c in vocab.UNIT_CODES if f"units_{c}.json" in self.files and self.files[f"units_{c}.json"].ok]

    def all_weapons(self) -> dict[str, dict]:
        out: dict[str, dict] = {}
        for lf in self.units_files():
            for w in _dicts(lf.data.get("weapons")):  # type: ignore[union-attr]
                if isinstance(w.get("id"), str):
                    out.setdefault(w["id"], w)
        return out

    def summons(self) -> dict[str, dict]:
        out: dict[str, dict] = {}
        for lf in self.units_files():
            for s in _dicts(lf.data.get("summons")):  # type: ignore[union-attr]
                if isinstance(s.get("id"), str):
                    out.setdefault(s["id"], s)
        return out

    def unit_ids(self) -> set[str]:
        return set(self.b_units)

    def structure_ids(self) -> set[str]:
        return set(self.b_structs)

    def zone_ids(self) -> set[str] | None:
        """Zone ids from zone_templates.json, or None when the file is missing / has no id list (zone existence is then not checked)."""
        lf = self.files.get("zone_templates.json")
        if not lf or not lf.ok:
            return None
        z = lf.data.get("zones")  # type: ignore[union-attr]
        if isinstance(z, list):
            return {e["id"] for e in z if isinstance(e, dict) and isinstance(e.get("id"), str)}
        if isinstance(z, dict):
            return set(z)
        return None

    # ---- bible tags
    def bible_unit_tags(self) -> set[str]:
        if self._bible_tags is None:
            self._bible_tags = {t for u in self.b_units.values() for t in u.get("tags", [])}
        return self._bible_tags

    def locked_tags(self) -> set[str]:
        """Tags referenced by the bible selectors: adding them to a unit would change modifier scopes (V-CNF-03)."""
        if self._locked is None:
            s: set[str] = set()
            for sel in self.bible.get("selectors", {}).values():
                for k in ("all_tags", "any_tags", "exclude_tags"):
                    s.update(sel.get(k, []))
            self._locked = s
        return self._locked

    # ---- effective values
    def base_row(self, archetype: object) -> dict:
        """Role-archetype row (or service_units row for 'service.<name>')."""
        if not isinstance(archetype, str):
            return {}
        if archetype.startswith("service."):
            return self.service.get(archetype[len("service."):], {})
        return self.arch.get(archetype, {})

    def eff(self, entry: dict, key: str) -> object:
        """Sheet value, else role-archetype / service row default, else size-class radius (None when nothing supplies it)."""
        if key in entry:
            return entry[key]
        row = self.base_row(entry.get("archetype"))
        if key in row:
            return row[key]
        if key == "radius_cells":
            sc = self.g.get("size_classes", {}).get(self.eff(entry, "size_class"), {})
            return sc.get("radius_cells")
        return None


def _dicts(v: object) -> list[dict]:
    return [x for x in v if isinstance(x, dict)] if isinstance(v, list) else []


def dicts(v: object) -> list[dict]:
    return _dicts(v)


def num(v: object) -> float | None:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def is_ldict(v: object) -> bool:
    return isinstance(v, LDict)
