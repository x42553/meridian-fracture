"""catalog/voice.py - what the voice pipeline produces (AUD-T5): specs only.

  announcer_lines()   VoiceLine per pack x line x take  (497 files in the spec's minimum; 9 packs x 57 = 513 here: every line
                      exists in every pack, including the 8 faction mottos, because V-AUD-19 asks for it)
  responses()         RespSpec per faction x class x type x variant (648 bleeps)
  barks()             optional Phase-B TTS barks `resp/<f>/voice/<class>_<type>_<n>` (624: no barks for structures)
QA numbers (spec 10.2): announcer lines 0.3-6 s, <= -1.5 dBTP, -18.0 +- 1.5 LUFS-I, mono, codec SNR >= 18 dB, > 6 kHz share <= 8 %
(computer / officer) or <= 1 % (radio); unit responses 0.15-0.7 s, <= -2.0 dBTP, -20 +- 2, mono, squelch present in the first 70 ms.
"""
from __future__ import annotations

LINE_LUFS = -18.0
LINE_LUFS_TOL = 1.5
LINE_TP = -1.5
LINE_SECONDS = (0.3, 6.0)
LINE_SNR_MIN = 18.0
HF_SHARE_MAX = {"computer": 8.0, "officer": 8.0, "radio": 1.0}
RESP_LUFS = -20.0
RESP_LUFS_TOL = 2.0
RESP_TP = -2.0
RESP_SECONDS = (0.15, 0.7)
QUALITY_MIN = 0.3
BARK_SECONDS = (0.25, 2.5)
BARK_SNR_MIN = 14.0
BARK_HF_MAX = 1.0


def announcer_lines():
    from voice import lines
    return lines.all_lines()


def responses():
    from voice import responses as r
    return r.all_specs()


def barks():
    from voice import lines
    return lines.all_barks()


def all_asset_ids() -> list[str]:
    return sorted([v.asset_id for v in announcer_lines()] + [s.asset_id for s in responses()] + [b.asset_id for b in barks()])
