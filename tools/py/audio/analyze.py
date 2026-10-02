"""analyze.py - objective audio QA (no listening required): loudness, peaks, envelope, spectrum, stereo, loop seam,
codec round-trip, feature vectors, and spectrogram/contact-sheet PNG rendering.  numpy + Pillow (+ soundfile via
oggtools for decoding).  ffmpeg is used only by the optional `ffmpeg_ebur128` cross-check."""
from __future__ import annotations

import re
import subprocess

import numpy as np
from PIL import Image, ImageDraw

import dsp
from dsp import SR, Array

_MAGMA = [(0.00, (0, 0, 4)), (0.15, (28, 16, 68)), (0.35, (111, 26, 110)), (0.55, (188, 55, 84)),
          (0.75, (249, 142, 8)), (0.90, (252, 216, 90)), (1.00, (252, 255, 240))]


def _lut() -> Array:
    xs = np.linspace(0, 1, 256)
    stops = np.array([s[0] for s in _MAGMA])
    cols = np.array([s[1] for s in _MAGMA], dtype=np.float64)
    return np.stack([np.interp(xs, stops, cols[:, c]) for c in range(3)], axis=1).astype(np.uint8)


LUT = _lut()


def ffmpeg_ebur128(path: str, pad_to: float = 1.0) -> dict:
    """Optional cross-check: integrated LUFS / LRA / true peak via ffmpeg's ebur128 (short files zero-padded)."""
    filt = f"apad=whole_dur={pad_to},ebur128=peak=true"
    p = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", path, "-af", filt, "-f", "null", "-"],
                       capture_output=True, text=True)
    txt = p.stderr.split("Summary:")[-1]

    def g(rx: str) -> float | None:
        m = re.search(rx, txt)
        return float(m.group(1)) if m else None
    return {"lufs_i": g(r"I:\s+(-?[\d.]+) LUFS"), "lra": g(r"LRA:\s+([\d.]+) LU"), "true_peak_db": g(r"Peak:\s+(-?[\d.]+) dBFS")}


def _k_coefs() -> tuple[tuple[Array, Array], tuple[Array, Array]]:
    """BS.1770 K-weighting stages at 44.1 kHz, derived exactly like libebur128 (bilinear transform of the analog
    prototype parameters), so the numpy meter tracks ffmpeg's ebur128 to a few hundredths of a LU."""
    fs = float(SR)
    f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = np.tan(np.pi * f0 / fs)
    vh = 10.0 ** (g / 20.0)
    vb = vh ** 0.4996667741545416
    a0 = 1.0 + k / q + k * k
    b1 = np.array([(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0])
    a1 = np.array([1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0])
    f0, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * f0 / fs)
    a0 = 1.0 + k / q + k * k
    b2 = np.array([1.0, -2.0, 1.0])
    a2 = np.array([1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0])
    return (b1, a1), (b2, a2)


def k_weight(x: Array) -> Array:
    """ITU-R BS.1770 K-weighting (shelf + RLB high-pass)."""
    (b1, a1), (b2, a2) = _k_coefs()
    return dsp.biquad_coef(dsp.biquad_coef(x, b1, a1), b2, a2)


def lufs_integrated(x: Array, pad_to: float = 1.0) -> float:
    """Gated integrated loudness (400 ms blocks, 75 % overlap, -70 abs / -10 rel gates); short sounds are zero-padded."""
    y = k_weight(dsp.to_stereo(x) if x.ndim == 2 else x[:, None])
    n_min = int(pad_to * SR)
    if len(y) < n_min:
        y = np.concatenate([y, np.zeros((n_min - len(y), y.shape[1]))])
    blk, step = int(0.4 * SR), int(0.1 * SR)
    c = np.cumsum(np.concatenate([np.zeros((1, y.shape[1])), y * y]), axis=0)
    starts = np.arange(0, len(y) - blk + 1, step)
    z = ((c[starts + blk] - c[starts]) / blk).sum(axis=1)
    l = -0.691 + 10 * np.log10(z + 1e-12)
    keep = z[l > -70.0]
    if keep.size == 0:
        return -70.0
    gate = -0.691 + 10 * np.log10(keep.mean()) - 10.0
    keep = z[l > gate]
    return float(-0.691 + 10 * np.log10(keep.mean() + 1e-12))


def true_peak_db(x: Array) -> float:
    return float(dsp.lin_to_db(dsp.true_peak(x)))


def rms_of(x: Array) -> float:
    return float(np.sqrt(np.mean(x * x))) if x.size else 0.0


def envelope(x: Array, win_ms: float = 1.0, hop_div: int = 4) -> tuple[Array, int]:
    """Short-time RMS envelope of the mono mix; returns (env, hop_samples)."""
    m = dsp.to_mono(x)
    w = max(2, int(SR * win_ms / 1000))
    hop = max(1, w // hop_div)
    c = np.cumsum(np.r_[0.0, m * m])
    if len(m) <= w:
        return np.array([rms_of(m)]), hop
    idx = np.arange(0, len(m) - w, hop)
    return np.sqrt((c[idx + w] - c[idx]) / w), hop


def metrics(x: Array, loop: bool = False) -> dict:
    """Objective descriptors of a float signal (mono (n,) or stereo (n,2))."""
    m = dsp.to_mono(x)
    pk = float(np.max(np.abs(x)))
    e, hop = envelope(dsp.highpass(m, 150.0, 2), 4.0, 16)          # transient rise is judged above the sub band
    # attack = 10 -> 90 % rise to the MEDIAN level of the first 40 ms (4 ms envelope of the >150 Hz signal; the window
    # starts at the onset = first sample above 2 % of the global maximum).  Measures how punchy the onset is, not how
    # long the sound swells; the median makes it independent of random noise peaks.
    emax = float(e.max()) + 1e-12
    onset = int(np.argmax(e >= 0.02 * emax))
    win = e[onset:onset + max(1, int(0.040 * SR / hop))]
    ep = float(np.median(win)) + 1e-12                # median level of the first 40 ms: robust against random noise peaks
    lo10 = onset + int(np.argmax(win >= 0.1 * ep))
    hi90 = onset + int(np.argmax(win >= 0.9 * ep))
    attack_ms = max(hi90 - lo10, 0) * hop / SR * 1000.0
    # slower envelope for decay times
    es, hops = envelope(x, 10.0, 2)
    esm = float(es.max()) + 1e-12
    edb = 20 * np.log10(es / esm + 1e-9)
    ip2 = int(np.argmax(es))

    def t_below(db: float) -> float:
        idx = np.nonzero(edb[ip2:] < db)[0]
        return float((idx[0] if idx.size else len(edb) - ip2) * hops / SR)
    nfft = 2048
    mm = np.pad(m, (0, nfft - len(m))) if len(m) < nfft else m
    frames = np.lib.stride_tricks.sliding_window_view(mm, nfft)[::nfft // 2] * np.hanning(nfft)
    ps = np.mean(np.abs(np.fft.rfft(frames, axis=1)) ** 2, axis=0)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    tot = ps.sum() + 1e-30
    d = {
        "duration_s": round(len(x) / SR, 3),
        "duration_samples": int(len(x)),
        "channels": 1 if x.ndim == 1 else x.shape[1],
        "peak_db": round(float(dsp.lin_to_db(pk)), 2),
        "true_peak_db": round(true_peak_db(x), 2),
        "rms_db": round(float(dsp.lin_to_db(rms_of(m))), 2),
        "crest_db": round(float(dsp.lin_to_db(pk) - dsp.lin_to_db(rms_of(m))), 2),
        "lufs_i": round(lufs_integrated(x), 2),
        "dc": round(float(np.mean(m)), 6),
        "nan": bool(np.isnan(x).any()),
        "clipped_samples": int(np.sum(np.abs(x) >= 0.9999)),
        "x0": round(float(np.max(np.abs(np.atleast_1d(x[0])))), 5),
        "x_end": round(float(np.max(np.abs(np.atleast_1d(x[-1])))), 5),
        "attack_ms": round(float(attack_ms), 2),
        "t20_ms": round(t_below(-20) * 1000, 0),
        "t40_ms": round(t_below(-40) * 1000, 0),
        "centroid_hz": round(float((ps * f).sum() / tot), 0),
        "band_lt200_pct": round(float(100 * ps[f < 200].sum() / tot), 2),
        "band_200_2k_pct": round(float(100 * ps[(f >= 200) & (f < 2000)].sum() / tot), 2),
        "band_2k_6k_pct": round(float(100 * ps[(f >= 2000) & (f < 6000)].sum() / tot), 2),
        "band_gt6k_pct": round(float(100 * ps[f >= 6000].sum() / tot), 2),
    }
    if x.ndim == 2:
        l, r = x[:, 0], x[:, 1]
        d["lr_corr"] = round(float(np.corrcoef(l, r)[0, 1]) if l.std() > 1e-9 and r.std() > 1e-9 else 1.0, 3)
        ll, lr = dsp.lowpass(l, 140.0, 4), dsp.lowpass(r, 140.0, 4)
        d["lf_corr"] = round(float(np.corrcoef(ll, lr)[0, 1]) if ll.std() > 1e-9 and lr.std() > 1e-9 else 1.0, 3)
        d["mono_loss_db"] = round(float(dsp.lin_to_db(rms_of((l + r) / 2) / (np.sqrt((rms_of(l) ** 2 + rms_of(r) ** 2) / 2) + 1e-12))), 2)
    if loop:
        d["seam_score"] = round(dsp.seam_score(x), 2)
    return d


def feature_vector(m: dict) -> Array:
    """Distinctiveness features (audio spec 10.2): log centroid, log t20, log t40, 4 band shares, crest."""
    tot = m["band_lt200_pct"] + m["band_200_2k_pct"] + m["band_2k_6k_pct"] + m["band_gt6k_pct"] + 1e-9
    return np.array([np.log(max(m["centroid_hz"], 1.0)), np.log(max(m["t20_ms"], 1.0)), np.log(max(m["t40_ms"], 1.0)),
                     m["band_lt200_pct"] / tot, m["band_200_2k_pct"] / tot, m["band_2k_6k_pct"] / tot, m["band_gt6k_pct"] / tot,
                     m["crest_db"] / 10.0])


def codec_roundtrip(orig: Array, dec: Array) -> dict:
    """Compare decoded OGG with the 16-bit source: length delta, SNR, edge error."""
    n = min(len(dec), len(orig))
    a, b = orig[:n], dec[:n]
    err = a - b
    snr = float(dsp.lin_to_db(rms_of(a) / (rms_of(err) + 1e-12)))
    return {"len_delta": int(len(dec) - len(orig)), "snr_db": round(snr, 1)}


def spectrogram(x: Array, width: int = 640, height: int = 210, fmin: float = 40.0, fmax: float = 20000.0,
                range_db: float = 78.0, wave_h: int = 46) -> Image.Image:
    """Log-frequency spectrogram (magma) with a waveform strip on top and axis ticks."""
    m = dsp.to_mono(x)
    n = len(m)
    nfft = 2048 if n > 8192 else 1024
    hop = max(64, (n - nfft) // max(1, width - 1)) if n > nfft else 64
    mm = np.pad(m, (0, max(0, nfft + hop * (width - 1) - n)))
    frames = np.lib.stride_tricks.sliding_window_view(mm, nfft)[::hop][:width] * np.hanning(nfft)
    mag = np.abs(np.fft.rfft(frames, axis=1)).T                      # (bins, cols)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    rows = np.geomspace(fmin, fmax, height)
    img = np.stack([np.interp(rows, f, mag[:, c]) for c in range(mag.shape[1])], axis=1)
    db = 20 * np.log10(img + 1e-9)
    db = np.clip((db - (db.max() - range_db)) / range_db, 0, 1)
    rgb = LUT[(db[::-1] * 255).astype(np.uint8)]
    spec = Image.fromarray(rgb, "RGB")
    if spec.width != width:
        spec = spec.resize((width, height))
    out = Image.new("RGB", (width + 34, wave_h + height + 16), (14, 14, 18))
    out.paste(spec, (34, wave_h))
    d = ImageDraw.Draw(out)
    # waveform strip (per-column peak)
    cols = np.array_split(np.abs(x if x.ndim == 1 else x.max(axis=1)), width)
    pk = max(1e-9, float(np.max(np.abs(x))))
    for i, c in enumerate(cols):
        h = int((c.max() / pk) * (wave_h / 2 - 1)) if c.size else 0
        d.line([(34 + i, wave_h // 2 - h), (34 + i, wave_h // 2 + h)], fill=(120, 200, 255))
    for fr, lab in ((100, "100"), (1000, "1k"), (10000, "10k")):
        y = wave_h + int((1 - np.log(fr / fmin) / np.log(fmax / fmin)) * (height - 1))
        d.line([(30, y), (34 + width, y)], fill=(70, 70, 90))
        d.text((2, y - 5), lab, fill=(200, 200, 210))
    dur = n / SR
    step = 0.1 if dur < 1 else (0.5 if dur < 4 else (1 if dur < 12 else (5 if dur < 60 else 10)))
    tt = 0.0
    while tt <= dur:
        xx = 34 + int(tt / dur * (width - 1))
        d.line([(xx, wave_h + height), (xx, wave_h + height + 4)], fill=(200, 200, 210))
        d.text((xx + 2, wave_h + height + 3), f"{tt:g}s", fill=(200, 200, 210))
        tt += step
    return out


def contact_sheet(items: list[tuple[str, Array, str]], path: str, cols: int = 2, cell_w: int = 640, cell_h: int = 210) -> None:
    """items = [(title, signal, subtitle)]; renders a labelled grid of spectrograms."""
    tiles = []
    for title, x, sub in items:
        sp = spectrogram(x, cell_w, cell_h)
        tile = Image.new("RGB", (sp.width, sp.height + 26), (14, 14, 18))
        tile.paste(sp, (0, 26))
        dd = ImageDraw.Draw(tile)
        dd.text((6, 3), title, fill=(255, 255, 255))
        dd.text((6, 14), sub, fill=(160, 210, 160))
        tiles.append(tile)
    rows = (len(tiles) + cols - 1) // cols
    W, H = tiles[0].width, tiles[0].height
    sheet = Image.new("RGB", (W * cols, H * rows), (14, 14, 18))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * W, (i // cols) * H))
    sheet.save(path)


def sheet_for(items: list[tuple[str, Array, str]], path: str, cols: int = 2) -> None:
    """Alias kept for callers that only want a sheet."""
    contact_sheet(items, path, cols)
