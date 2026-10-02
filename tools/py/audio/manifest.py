"""manifest.py - writes `audio_manifest.json` (generated, committed), the runtime `asset_index.json` (shipped) and
delegates provenance.json / NOTICE.txt to provenance.py.  Everything is sorted and byte-stable on re-run.

Manifest entry (audio spec 7.8) - keys written by render.py: file, bank, category, channels, loop, duration_samples,
bytes, sha256, pcm_sha256, recipe_hash, lufs_i, true_peak_db, seam_score, flavour, seam_src, len_delta, snr_db and,
for `channels: "both"` assets, mono_file/mono_bytes/mono_sha256/mono_pcm_sha256.  Optional `prov` (dict) is merged into
the PROVENANCE entry by voice assets (model, voice, text, ...).
Index entry: {"f": primary file, "b": bank, "c": channels, "l": loop 0/1, "n": duration samples[, "m": 1 = a
`.mono.ogg` twin of the (stereo) primary exists]}; "groups": number of `_1.._N` variants of an asset group."""
from __future__ import annotations

import json
import platform
import re
import sys
from pathlib import Path

import dsp

ROOT = Path(__file__).resolve().parent.parent.parent.parent
AUDIO_ROOT = ROOT / "game" / "assets" / "audio"
MANIFEST_SCHEMA = "meridian.audio.assets/1"
INDEX_SCHEMA = "meridian.audio.index/1"
SFX_PREFIXES = ("sfx/", "ui/", "alarm/", "amb/")


def generator_info() -> dict:
    import numpy
    import soundfile
    return {"dsp_version": dsp.DSP_VERSION, "python": platform.python_version(), "numpy": numpy.__version__,
            "soundfile": soundfile.__version__, "libsndfile": soundfile.__libsndfile_version__,
            "platform": f"{sys.platform}-{platform.machine().lower()}"}


def dumps(obj, compact: bool = False) -> str:
    if compact:
        return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
    return json.dumps(obj, sort_keys=True, indent=1, ensure_ascii=True) + "\n"


def write_if_changed(path: Path, text: str) -> bool:
    if path.exists() and path.read_text() == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return True


def load(root: Path = AUDIO_ROOT) -> dict:
    p = root / "audio_manifest.json"
    if p.exists():
        return json.loads(p.read_text())
    return {"schema": MANIFEST_SCHEMA, "generator": {}, "totals": {"files": 0, "bytes": 0}, "assets": {}, "qa": {}}


def file_count_bytes(entry: dict) -> tuple[int, int]:
    n, b = 1, entry["bytes"]
    if "mono_file" in entry:
        n, b = n + 1, b + entry["mono_bytes"]
    return n, b


def build_index(assets: dict) -> dict:
    idx: dict = {}
    groups: dict[str, int] = {}
    for aid, e in sorted(assets.items()):
        row = {"f": e["file"], "b": e["bank"], "c": e["channels"], "l": 1 if e["loop"] else 0, "n": e["duration_samples"]}
        if "mono_file" in e:
            row["m"] = 1
        idx[aid] = row
    cand: dict[str, list[int]] = {}
    for aid in assets:
        m = re.match(r"^(.*)_(\d+)$", aid)
        if m:
            cand.setdefault(m.group(1), []).append(int(m.group(2)))
    for g, nums in cand.items():
        nums.sort()
        if len(nums) >= 2 and nums == list(range(1, len(nums) + 1)):
            groups[g] = len(nums)
    return {"schema": INDEX_SCHEMA, "assets": idx, "groups": dict(sorted(groups.items()))}


def write_all(assets: dict, prev: dict, qa: dict | None = None, root: Path = AUDIO_ROOT, rerendered: set[str] | None = None) -> dict:
    """Write manifest, index, provenance and notice for the full asset dict; returns the manifest."""
    import provenance
    files = bytes_ = 0
    for e in assets.values():
        n, b = file_count_bytes(e)
        files, bytes_ = files + n, bytes_ + b
    man = {"schema": MANIFEST_SCHEMA, "generator": generator_info(), "totals": {"files": files, "bytes": bytes_},
           "qa": qa if qa is not None else prev.get("qa", {}), "assets": dict(sorted(assets.items()))}
    write_if_changed(root / "audio_manifest.json", dumps(man))
    write_if_changed(root / "asset_index.json", dumps(build_index(assets), compact=True))
    prov_path = root / "provenance.json"
    prev_prov = json.loads(prov_path.read_text()) if prov_path.exists() else {"files": []}
    write_if_changed(prov_path, dumps(provenance.build(assets, prev_prov, man["generator"])))
    write_if_changed(root / "NOTICE.txt", provenance.notice(assets))
    return man
