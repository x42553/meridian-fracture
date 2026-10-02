"""catalog - declarative asset specs: the single source of truth for what the audio generators produce.

`AssetSpec` follows audio spec 7.8.  Each `catalog/<family>.py` module registers its specs at import time with
`add()`/`add_group()`; `all_specs()` imports the SFX-pipeline modules (T2/T3) once and returns them sorted by id.
Music (T4) and voice (T5) keep their own catalogs (`catalog/music.py`, `catalog/voice.py`) and are not part of the
`sfx` pipeline.

Asset ids and files (lower-case `[a-z0-9_]`, <= 100 chars): a spec with `variants == 1` is the asset `<id>`; with more
variants it is the group `<id>` made of the assets `<id>_1 .. <id>_N`.  File names: `channels="mono"` ->
`<asset>.mono.ogg`, `"stereo"` -> `<asset>.ogg`, `"both"` -> both files (3D events take the `.mono.ogg`).

Event id -> asset group rule (used by the events scaffolder): `snd.<a>.<b>.<c>` -> `sfx/<a>/<b>_<c>` for the families
weapon, proj, impact, explosion, death, collapse, loop, air, struct, eco, power, sw, intercept; `snd.ui.x` -> `ui/x`;
`snd.alarm.x` -> `alarm/x`; `snd.amb.x` -> `amb/x`; weapon flavours live in `sfx/weapon_fx/<faction>/<archetype>`.
"""
from __future__ import annotations

import importlib
from dataclasses import dataclass, field

SFX_MODULES = ("weapons", "impacts", "movement", "structures", "powers", "superweapons", "ui_alarms", "ambience")
FACTIONS = ("napc", "nec", "olm", "def", "pd", "han", "ae", "sap")


@dataclass(frozen=True)
class AssetSpec:
    id: str                    # "sfx/weapon/small_arms"  (variants -> small_arms_1..n)
    recipe: str                # "rifle_shot"  (function registered in tools/py/audio/sfx/*.py)
    variants: int = 1
    channels: str = "mono"     # "mono" | "stereo" | "both" (both -> <id>.ogg stereo + <id>.mono.ogg)
    loop: bool = False
    peak_db: float = -1.5      # true-peak ceiling; loops -6
    lufs: float | None = None  # loudness target (loops, beds, alarms, ui); None = peak-normalise
    exciter: float = 0.0       # psychoacoustic bass amount
    quality: str = "sfx"       # oggtools preset: sfx 0.38 | ambience 0.55 | voice 0.50 | music 0.45
    params: dict = field(default_factory=dict)   # recipe parameters, incl. faction flavour axes
    salt: int = 0              # extra RNG salt (bump to re-roll one asset)
    tags: tuple[str, ...] = ()
    qa: str = ""               # QA class override (see qa_thresholds.classify)
    flavour: str | None = None # faction code of a weapon flavour asset


_SPECS: dict[str, AssetSpec] = {}


def add(spec: AssetSpec) -> AssetSpec:
    if spec.id in _SPECS:
        raise ValueError(f"duplicate asset spec {spec.id}")
    if not valid_id(spec.id):
        raise ValueError(f"bad asset id {spec.id!r}")
    if spec.channels not in ("mono", "stereo", "both"):
        raise ValueError(f"{spec.id}: channels {spec.channels!r}")
    if spec.loop and spec.peak_db > -6.0:
        raise ValueError(f"{spec.id}: loops need peak_db <= -6")
    _SPECS[spec.id] = spec
    return spec


def valid_id(asset_id: str) -> bool:
    if len(asset_id) > 100:
        return False
    for seg in asset_id.split("/"):
        if not seg or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_" for c in seg):
            return False
        if seg in ("con", "prn", "aux", "nul") or (seg.startswith(("com", "lpt")) and seg[3:].isdigit()):
            return False
    return True


def all_specs() -> list[AssetSpec]:
    for m in SFX_MODULES:
        importlib.import_module(f"catalog.{m}")
    return sorted(_SPECS.values(), key=lambda s: s.id)


def asset_ids(spec: AssetSpec) -> list[tuple[int, str]]:
    """[(variant_number, asset_id)]; variant numbers are 1-based, single-variant specs use number 1 and the bare id."""
    if spec.variants == 1:
        return [(1, spec.id)]
    return [(v, f"{spec.id}_{v}") for v in range(1, spec.variants + 1)]


def files_of(spec: AssetSpec, asset_id: str) -> dict[str, str]:
    """{'stereo': rel path or absent, 'mono': ...} relative to game/assets/audio."""
    out: dict[str, str] = {}
    if spec.channels in ("stereo", "both"):
        out["stereo"] = asset_id + ".ogg"
    if spec.channels in ("mono", "both"):
        out["mono"] = asset_id + ".mono.ogg"
    return out


def primary_file(spec: AssetSpec, asset_id: str) -> str:
    f = files_of(spec, asset_id)
    return f.get("stereo") or f["mono"]


def bank_of(asset_id: str) -> str:
    p = asset_id.split("/")
    if p[0] in ("sfx", "ui", "alarm"):
        return f"fx_{p[2]}" if p[:2] == ["sfx", "weapon_fx"] else "core"
    if p[0] == "amb":
        return "amb"
    if p[0] == "mus":
        if p[1] == "menu" or (p[1] == "stinger" and p[2].startswith("match_start")):
            return "mus_common"
        if p[1] == "stinger":
            return "mus_" + p[2].split("_")[0]
        return "mus_" + p[1]
    if p[0] == "vox":
        return "vox_" + p[1]
    if p[0] == "resp":
        return "resp_" + p[1]
    raise ValueError(asset_id)


def category_of(asset_id: str) -> str:
    p = asset_id.split("/")
    if p[0] == "sfx":
        return p[1]
    return p[0]
