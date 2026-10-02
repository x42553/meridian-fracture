"""verify_capture.py - prove the engine's mixed output across the music loop point equals the sample-exact source stems.
Input: analysis/capture/seam_combat.wav captured from Master by tests/t_capture.gd (4 stems, intensity 1, play(from=length-1 s))."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
cap, sr = sf.read(str(ROOT / "analysis" / "capture" / "seam_combat.wav"), dtype="float64")
stems = [sf.read(str(ROOT / "assets/audio/music/combat_tense" / f"{s}.ogg"), dtype="float64")[0] for s in ("drums", "bass", "pads", "lead")]
mix = sum(stems)
N = len(mix)
start = int(round(53.8571 * sr))
exp = np.concatenate([mix[start:], mix[: 4 * sr]])                 # what a perfect loop would emit after play(from)
seam_idx_exp = N - start                                            # index in `exp` where the loop wraps
# align with FFT cross-correlation: capture[5000:25000] ~ exp[k:k+20000]  =>  exp_index = capture_index + lag
probe = cap[5000:25000, 0]
ref = exp[:70000, 0]
nfft = 1 << 18
xc = np.fft.irfft(np.fft.rfft(ref, nfft) * np.conj(np.fft.rfft(probe, nfft)), nfft)[: len(ref) - len(probe)]
k = int(np.argmax(xc))
lag = k - 5000
i0, i1 = max(0, -lag), min(len(cap), len(exp) - lag)
c, e = cap[i0:i1], exp[i0 + lag:i1 + lag]
g = float(np.dot(c[:, 0], e[:, 0]) / np.dot(e[:, 0], e[:, 0]))
err = c - g * e
snr = 20 * np.log10(np.sqrt(np.mean(c ** 2)) / (np.sqrt(np.mean(err ** 2)) + 1e-12))
seam_cap = (N - start) - lag
steps = np.abs(np.diff(cap[:, 0]))
near = steps[max(0, seam_cap - 96): seam_cap + 96]
away = np.concatenate([steps[:max(0, seam_cap - 2000)], steps[seam_cap + 2000:]])
print(json.dumps({"alignment_lag_samples": lag, "engine_gain_vs_offline_sum_db": round(20 * np.log10(g), 3), "match_snr_db_vs_offline_sum": round(float(snr), 1),
                  "seam_index_in_capture": int(seam_cap), "max_step_within_96_samples_of_seam": round(float(near.max()), 5), "p99_step_elsewhere": round(float(np.percentile(away, 99)), 5),
                  "seam_over_p99": round(float(near.max() / np.percentile(away, 99)), 2), "frames_compared": int(len(c)), "capture_peak": round(float(np.abs(cap).max()), 3)}, indent=1))
