"""qa_thresholds.py - per-class asset QA limits (audio spec 10.2, loudness targets 5.1).

`classify(spec, asset_id)` -> class name; `LIMITS[class]` -> `Limits`.  Every number that is not literally in the spec
is marked `[tune]`.  `qa/qa_assets.py` evaluates them on the *decoded* OGG."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Limits:
    min_s: float
    max_s: float
    tp_max: float                       # true-peak ceiling of the decoded OGG (dBTP)
    lufs_window: tuple[float, float] | None = None   # absolute window (LUFS-I); None = informational
    lufs_tol: float | None = None       # +-LU around the catalog target when the spec has one
    attack_ms_max: float | None = None
    centroid_min: float | None = None
    band_200_2k_min: float | None = None
    seam_max: float | None = None
    lf_corr_min: float | None = None    # stereo LF L/R correlation
    snr_min: float = 8.0                # [tune] waveform SNR floor for noisy SFX (perceptual codec); voice uses 18 (spec)
    ends_faded: bool = True             # |x_end| <= 0.003 for one-shots


LIMITS: dict[str, Limits] = {
    "small_arms": Limits(0.4, 1.6, -1.4, attack_ms_max=6.0, centroid_min=700.0, band_200_2k_min=15.0),
    "cannon": Limits(1.0, 4.5, -1.4, attack_ms_max=10.0, band_200_2k_min=4.0),
    # faction flavours re-voice a base sound (pitch/brightness/tail/drive/layer): same classes, slightly relaxed [tune]
    "small_arms_fx": Limits(0.4, 1.6, -1.4, attack_ms_max=10.0, centroid_min=480.0, band_200_2k_min=12.0),
    "cannon_fx": Limits(1.0, 4.5, -1.4, attack_ms_max=32.0, band_200_2k_min=3.0),
    "explosion": Limits(1.5, 8.0, -1.4, attack_ms_max=12.0, band_200_2k_min=5.0, lf_corr_min=0.93),
    "death": Limits(0.2, 6.0, -1.4, attack_ms_max=20.0),                       # [tune]
    "impact": Limits(0.15, 2.0, -1.4, attack_ms_max=12.0),                     # [tune] bullet impacts 0.2-0.5 s, kinetic 1.5 s
    "proj": Limits(0.6, 4.0, -1.4),                                            # [tune] flight sounds: soft onsets allowed
    "oneshot": Limits(0.2, 12.0, -1.4),                                        # [tune] structures, powers, superweapons, air
    "loop": Limits(2.0, 24.0, -4.0, lufs_tol=1.0, seam_max=4.0, ends_faded=False),
    "ui": Limits(0.05, 4.0, -3.0, lufs_window=(-30.0, -13.0)),                 # [tune] window covers hover -28 ... confirm -18
    "alarm": Limits(0.05, 4.0, -3.0, lufs_window=(-18.0, -12.0)),              # 5.1: alarms/countdown -16...-14
    "ambience": Limits(16.0, 24.0, -9.0, lufs_tol=1.0, seam_max=4.0, ends_faded=False),
}

# every decoded asset (10.2, first row)
DC_MAX = 0.005
X0_MAX = 0.02
XEND_MAX = 0.003


def classify(spec, asset_id: str) -> str:
    """QA class of an asset (AssetSpec.qa overrides)."""
    if spec.qa:
        return spec.qa
    p = asset_id.split("/")
    if p[0] == "amb":
        return "ambience"
    if spec.loop:
        return "loop"
    if p[0] == "ui":
        return "ui"
    if p[0] == "alarm":
        return "alarm"
    fam = p[1] if len(p) > 1 else ""
    if fam in ("weapon", "weapon_fx"):
        arch = p[-1].rsplit("_", 1)[0] if p[-1][-1:].isdigit() else p[-1]
        small = arch in ("small_arms", "machine_gun", "autocannon")
        return ("small_arms" if small else "cannon") + ("_fx" if fam == "weapon_fx" else "")
    return {"explosion": "explosion", "collapse": "explosion", "death": "death", "impact": "impact",
            "intercept": "impact", "proj": "proj"}.get(fam, "oneshot")
