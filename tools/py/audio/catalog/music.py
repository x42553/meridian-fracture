"""catalog/music.py - what the music generator produces (AUD-T4): specs only, no DSP.

  tracks()     8 factions x (combat 24 bars, calm 12 bars at 0.6 x tempo) + the menu theme; 4 stems each (drums, bass, pads, lead)
  stingers()   per faction riser (2 bars), victory, defeat + the global match-start sting (25 assets)

Asset ids (audio spec 7.8): `mus/<faction>/<combat|calm>/<stem>` (bass = `.mono.ogg`, the others stereo), `mus/menu/<stem>`,
`mus/stinger/<faction>_<riser|victory|defeat>`, `mus/stinger/match_start`.  `music_json()` mirrors the `tracks` / `stingers`
sections of game/data/audio/music.json; `verify.check_data()` compares it with the authored file (they must agree).
"""
from __future__ import annotations

from dataclasses import dataclass

FACTIONS = ("napc", "nec", "olm", "def", "pd", "han", "ae", "sap")
STEMS = ("drums", "bass", "pads", "lead")
MONO_STEMS = ("bass",)
BAR_BEATS = 4
CALM_RATIO = 0.6
# mix loudness (sum of the four stems, LUFS-I) and the ceiling of the sum (spec 10.2 music row)
MIX_LUFS = {"combat": -14.4, "calm": -16.1}
MIX_TOL = 1.0
MIX_TP_MAX = -2.0
# relative loudness of the stems BEFORE the shared master gain (the game crossfades them by intensity)
STEM_LUFS = {
    "combat": {"drums": -19.0, "bass": -21.0, "pads": -24.0, "lead": -22.0},
    "calm": {"drums": -28.0, "bass": -25.0, "pads": -22.0, "lead": -24.0},
}
STEM_TOL = 1.5
STINGER_LUFS = -14.0
STINGER_SECONDS = {"victory": 6.5, "defeat": 6.5, "match_start": 2.5}


@dataclass(frozen=True)
class TrackSpec:
    id: str              # "napc.combat" (music.json track key)
    flavour: str         # key of music.flavours.FLAVOURS
    style: str           # "combat" | "calm"
    bars: int
    bpm: float
    folder: str          # "mus/napc/combat"
    faction: str | None  # None = menu
    mode: str
    root_midi: int

    @property
    def length_samples(self) -> int:
        return round(self.bars * BAR_BEATS * 60.0 / self.bpm * 44100)

    @property
    def beat_count(self) -> int:
        return self.bars * BAR_BEATS

    @property
    def lufs(self) -> float:
        return MIX_LUFS[self.style]

    def stem_ids(self) -> list[str]:
        return [f"{self.folder}/{s}" for s in STEMS]

    def channels(self, stem: str) -> str:
        return "mono" if stem in MONO_STEMS else "stereo"


@dataclass(frozen=True)
class StingerSpec:
    id: str              # "mus/stinger/napc_victory"
    key: str             # music.json stinger key "stinger.napc.victory"
    flavour: str
    kind: str            # riser | victory | defeat | match_start
    faction: str | None
    bpm: float           # riser tempo (combat tempo); 0 for the others
    bars: int            # riser length in bars; 0 for the others
    seconds: float       # nominal length (riser: derived from bpm)

    @property
    def length_samples(self) -> int:
        if self.kind == "riser":
            return round(self.bars * BAR_BEATS * 60.0 / self.bpm * 44100)
        return round(self.seconds * 44100)


def tracks() -> list[TrackSpec]:
    from music import flavours as fl
    out: list[TrackSpec] = []
    for f in FACTIONS:
        fv = fl.FLAVOURS[f]
        for style, bars in (("combat", fl.BARS["combat"]), ("calm", fl.BARS["calm"])):
            out.append(TrackSpec(f"{f}.{style}", f, style, bars, fv.tempo(style), f"mus/{f}/{style}", f, fv.mode, fv.root))
    m = fl.FLAVOURS["menu"]
    out.append(TrackSpec("menu.theme", "menu", "combat", 24, m.bpm, "mus/menu", None, m.mode, m.root))
    return out


def stingers() -> list[StingerSpec]:
    from music import flavours as fl
    out: list[StingerSpec] = []
    for f in FACTIONS:
        bpm = fl.FLAVOURS[f].bpm
        out.append(StingerSpec(f"mus/stinger/{f}_riser", f"stinger.{f}.riser", f, "riser", f, bpm, 2, 0.0))
        for kind in ("victory", "defeat"):
            out.append(StingerSpec(f"mus/stinger/{f}_{kind}", f"stinger.{f}.{kind}", f, kind, f, 0.0, 0, STINGER_SECONDS[kind]))
    out.append(StingerSpec("mus/stinger/match_start", "stinger.match_start", "menu", "match_start", None, 0.0, 0, STINGER_SECONDS["match_start"]))
    return out


def music_json() -> dict:
    """The `tracks` and `stingers` sections exactly as authored in game/data/audio/music.json."""
    tr = {}
    for t in tracks():
        tr[t.id] = {"folder": t.folder, "bpm": t.bpm, "bars": t.bars, "bar_beats": BAR_BEATS, "beat_count": t.beat_count,
                    "length_samples": t.length_samples, "stems": list(STEMS), "mono_stems": list(MONO_STEMS), "mode": t.mode, "root_midi": t.root_midi}
    st = {}
    for s in stingers():
        d: dict = {"stream": s.id}
        if s.kind == "riser":
            d.update({"bpm": s.bpm, "bars": s.bars})
        st[s.key] = d
    return {"tracks": tr, "stingers": st}


def all_asset_ids() -> list[str]:
    ids = [i for t in tracks() for i in t.stem_ids()] + [s.id for s in stingers()]
    return sorted(ids)
