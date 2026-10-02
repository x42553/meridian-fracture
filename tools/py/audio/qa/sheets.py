"""sheets.py - spectrogram contact sheets (waveform strip + log-frequency magma spectrogram) of generated assets.

`build(root, ids, out_dir, per=8)` decodes the OGGs and writes `<out_dir>/<group>_<n>.png`; the caller LOOKS at them
(image reader).  Titles carry duration, true peak, LUFS, crest and (loops) the seam score."""
from __future__ import annotations

from pathlib import Path

import analyze
import oggtools


def build(root: Path, manifest: dict, ids: list[str], out_dir: Path, per: int = 8, cols: int = 2, tag: str = "") -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    groups: dict[str, list[str]] = {}
    for aid in ids:
        parts = aid.split("/")
        key = "_".join(parts[:2]) if parts[0] == "sfx" else parts[0]
        groups.setdefault(key, []).append(aid)
    written: list[Path] = []
    for key, members in sorted(groups.items()):
        for i in range(0, len(members), per):
            items = []
            for aid in members[i:i + per]:
                e = manifest["assets"][aid]
                x = oggtools.decode(root / e["file"])
                m = analyze.metrics(x, e["loop"])
                sub = f"{m['duration_s']}s pk {m['true_peak_db']} lufs {m['lufs_i']} crest {m['crest_db']}"
                if e["loop"]:
                    sub += f" seam {m.get('seam_score')}"
                items.append((f"{aid} [{'st' if m['channels'] == 2 else 'mono'}]", x, sub))
            p = out_dir / f"{tag}{key}_{i // per + 1}.png"
            analyze.contact_sheet(items, str(p), cols=cols)
            written.append(p)
    return written
