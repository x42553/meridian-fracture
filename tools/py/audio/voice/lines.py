"""lines.py - the announcer line catalogue: a mirror of game/data/audio/announcer.json (the captions live THERE and are what
the game shows / speaks through OS TTS) expanded into one job per pack x line x take.

Packs: `computer` (EVA voice, chain computer) + one per faction (Kokoro voice + `officer` / `radio` chain from announcer.json,
radio profile from factions.json).  Every line exists in every pack (V-AUD-19), including the 8 faction mottos.
Asset ids: `vox/<pack>/<line>` for single-take lines, `vox/<pack>/<line>_<n>` for lines with `variants: n`.
Take 2 is spoken slower with an alert intonation, so the two takes of a repeated line do not sound identical.
"""
from __future__ import annotations

import json
from dataclasses import dataclass

import manifest as mf

DATA = mf.ROOT / "game" / "data" / "audio"
LANG = "en-us"
# words the G2P front end may mangle -> respelling sent to the engine (captions keep the original text)
PRONUNCIATION: dict[str, str] = {"Canceled": "Cancelled", "Defenses": "Defences"}
FAST_CATEGORIES = {"alert", "sw"}


@dataclass(frozen=True)
class VoiceLine:
    pack: str
    line: str
    take: int
    takes: int
    asset_id: str
    caption: str
    tts_text: str
    voice: str
    chain: str          # computer | officer | radio
    style: str | None   # radio style of the pack's faction (None for the computer pack)
    speed: float
    category: str
    open_ms: float
    close_ms: float
    hiss_db: float


def load() -> tuple[dict, dict]:
    ann = json.loads((DATA / "announcer.json").read_text(encoding="utf-8"))
    fac = json.loads((DATA / "factions.json").read_text(encoding="utf-8"))
    return ann, fac


def tts_text(text: str, category: str, take: int) -> str:
    t = text
    for a, b in PRONUNCIATION.items():
        t = t.replace(a, b)
    if take >= 2 and category in FAST_CATEGORIES | {"prod", "eco"} and t.endswith("."):
        t = t[:-1] + "!"
    return t


def speed_of(category: str, line: str, take: int) -> float:
    s = 1.06 if category in FAST_CATEGORIES else 1.0
    if line.startswith("match_start_"):
        s = 0.94
    return round(s * (0.93 if take >= 2 else 1.0), 3)


def asset_id(pack: str, line: str, take: int, takes: int) -> str:
    return f"vox/{pack}/{line}" + (f"_{take}" if takes > 1 else "")


def all_lines() -> list[VoiceLine]:
    ann, fac = load()
    out: list[VoiceLine] = []
    for pack, pd in ann["packs"].items():
        radio = fac["factions"].get(pack, {}).get("radio")
        for lid, ln in ann["lines"].items():
            takes = int(ln.get("variants", 1))
            for take in range(1, takes + 1):
                cat = ln.get("category", "prod")
                out.append(VoiceLine(pack, lid, take, takes, asset_id(pack, lid, take, takes), ln["text"], tts_text(ln["text"], cat, take),
                                     pd["voice"], pd["chain"], radio["style"] if radio else None, speed_of(cat, lid, take), cat,
                                     float(radio["squelch_open_ms"]) if radio else 0.0, float(radio["squelch_close_ms"]) if radio else 0.0,
                                     float(radio["hiss_db"]) if radio else -60.0))
    return sorted(out, key=lambda v: v.asset_id)


@dataclass(frozen=True)
class BarkLine:
    """Optional Phase-B unit bark (spec 5.10): `resp/<faction>/voice/<class>_<type>_<n>`; text from responses.json `barks`."""
    faction: str
    cls: str
    typ: str
    n: int
    asset_id: str
    caption: str
    tts_text: str
    voice: str
    style: str
    speed: float
    open_ms: float
    close_ms: float
    hiss_db: float


def all_barks() -> list[BarkLine]:
    ann, fac = load()
    resp = json.loads((DATA / "responses.json").read_text(encoding="utf-8"))
    out: list[BarkLine] = []
    for f, fd in fac["factions"].items():
        radio = fd["radio"]
        voice = ann["packs"][fd.get("announcer_pack", f)]["voice"]
        for cls, by_type in resp["barks"].items():
            for typ, texts in by_type.items():
                for n, text in enumerate(texts, 1):
                    out.append(BarkLine(f, cls, typ, n, f"resp/{f}/voice/{cls}_{typ}_{n}", text, tts_text(text, "bark", 1), voice, radio["style"],
                                        1.08 if typ == "attack" else 1.04, float(radio["squelch_open_ms"]), float(radio["squelch_close_ms"]), float(radio["hiss_db"])))
    return sorted(out, key=lambda b: b.asset_id)
