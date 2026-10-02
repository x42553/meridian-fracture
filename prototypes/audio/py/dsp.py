"""dsp.py - compact numpy-only synthesis toolkit for Meridian Fracture audio generation.

Design rules
  * Dependencies: Python stdlib + numpy only (matches the tools/py rule).  scipy is *never* imported here;
    tests compare against scipy.signal.lfilter when it is installed.
  * Everything is float64, mono = shape (n,), stereo = shape (n, 2).  Sample rate is the module constant SR.
  * Determinism: every asset draws from rng_for(<asset name>) so adding/removing an asset never perturbs
    the others; no global RNG is touched.
  * Loops: noise and periodic material can be built in the frequency domain (colored_noise) or with
    frequencies snapped to whole cycles (snap_freq), which makes the loop point mathematically seamless.
  * No per-sample Python loops.  IIR filters run as FFT convolution with a closed-form biquad impulse
    response; time-varying filters use a cross-faded bank of static filters (sweep_filter).
"""
from __future__ import annotations

import wave
import zlib
from typing import Sequence

import numpy as np

SR: int = 44100
TAU: float = 2.0 * np.pi
Array = np.ndarray


# --------------------------------------------------------------------------------------------- basics
def rng_for(name: str, salt: int = 0) -> np.random.Generator:
    """Independent, reproducible RNG per asset: seed = (CRC32(name), salt)."""
    return np.random.default_rng([zlib.crc32(name.encode("utf-8")), salt & 0xFFFFFFFF])


def n_of(seconds: float) -> int:
    return int(round(seconds * SR))


def t_axis(n: int) -> Array:
    return np.arange(n, dtype=np.float64) / SR


def db_to_lin(db: float | Array) -> float | Array:
    return 10.0 ** (np.asarray(db) / 20.0) if not np.isscalar(db) else 10.0 ** (db / 20.0)


def lin_to_db(x: float | Array) -> float | Array:
    return 20.0 * np.log10(np.maximum(x, 1e-12))


def snap_freq(freq: float, seconds: float) -> float:
    """Snap a frequency to a whole number of cycles in `seconds` (=> periodic, click-free loops)."""
    return max(1, round(freq * seconds)) / seconds


def peak(x: Array) -> float:
    return float(np.max(np.abs(x))) if x.size else 0.0


def rms(x: Array) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0


def true_peak(x: Array, oversample: int = 4) -> float:
    """Inter-sample (true) peak via FFT oversampling."""
    y = x if x.ndim == 2 else x[:, None]
    n = len(y)
    X = np.fft.rfft(y, axis=0)
    Xp = np.zeros((n * oversample // 2 + 1, y.shape[1]), dtype=np.complex128)
    Xp[: X.shape[0]] = X
    return float(np.max(np.abs(np.fft.irfft(Xp, n * oversample, axis=0)))) * oversample


def normalize(x: Array, peak_db: float = -1.0, tp: bool = True) -> Array:
    """Scale so the (true-)peak equals peak_db dBFS."""
    p = true_peak(x) if tp else peak(x)
    return x * (db_to_lin(peak_db) / p) if p > 1e-12 else x


def to_stereo(x: Array) -> Array:
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def to_mono(x: Array) -> Array:
    return x.mean(axis=1) if x.ndim == 2 else x


def fit(x: Array, n: int) -> Array:
    """Trim or zero-pad on the time axis to exactly n samples."""
    if len(x) >= n:
        return x[:n]
    pad = np.zeros((n - len(x),) + x.shape[1:])
    return np.concatenate([x, pad], axis=0)


def _bc(env: Array, x: Array) -> Array:
    """Broadcast a 1-D control curve against mono or stereo audio."""
    return env[:, None] if x.ndim == 2 else env


# --------------------------------------------------------------------------------------------- noise
def _edge(f: Array, fc: float, width_oct: float, rising: bool) -> Array:
    u = np.clip(np.log2(np.maximum(f, 1e-3) / fc) / width_oct + 0.5, 0.0, 1.0)
    s = u * u * (3.0 - 2.0 * u)
    return s if rising else 1.0 - s


def colored_noise(n: int, rng: np.random.Generator, exponent: float = 0.0,
                  lo: float | None = None, hi: float | None = None, skirt_oct: float = 0.5) -> Array:
    """Unit-RMS noise with PSD ~ f^-exponent (0 white, 1 pink, 2 brown, -1 blue, -2 violet), optional band [lo,hi] Hz.

    Built directly in the frequency domain, so the signal is exactly periodic over n samples: any loop
    made from it (and from circular convolution of it) has a mathematically seamless seam."""
    nf = n // 2 + 1
    f = np.arange(nf, dtype=np.float64) * SR / n
    ff = f.copy()
    ff[0] = ff[1] if nf > 1 else 1.0
    mag = ff ** (-exponent / 2.0)
    if lo:
        mag = mag * _edge(f, lo, skirt_oct, True)
    if hi:
        mag = mag * _edge(f, hi, skirt_oct, False)
    spec = mag * np.exp(1j * rng.uniform(0.0, TAU, nf))
    spec[0] = 0.0
    if n % 2 == 0:
        spec[-1] = spec[-1].real
    x = np.fft.irfft(spec, n)
    return x / (np.sqrt(np.mean(x * x)) + 1e-12)


def slow_noise(n: int, rng: np.random.Generator, hi_hz: float, lo_hz: float = 0.02) -> Array:
    """Smooth circular random modulator in roughly [-1, 1] (unit std, clipped at 3 sigma / 3)."""
    x = colored_noise(n, rng, 0.0, lo=lo_hz, hi=hi_hz, skirt_oct=0.4)
    return np.clip(x, -3.0, 3.0) / 3.0


def crackle(n: int, rng: np.random.Generator, density: Array | float, amp_pow: float = 2.0) -> Array:
    """Poisson impulse train with random polarity/amplitude. density = events/second (scalar or per-sample curve)."""
    d = np.full(n, float(density)) if np.isscalar(density) else np.asarray(density, dtype=np.float64)
    hit = rng.random(n) < (d / SR)
    amp = rng.random(n) ** amp_pow * rng.choice([-1.0, 1.0], n)
    return np.where(hit, amp, 0.0)


# --------------------------------------------------------------------------------------------- oscillators
def _freq_array(freq: float | Array, n: int | None) -> Array:
    if np.isscalar(freq):
        assert n is not None, "n required for scalar frequency"
        return np.full(n, float(freq))
    return np.asarray(freq, dtype=np.float64)


def phase_cycles(freq: float | Array, n: int | None = None) -> Array:
    """Phase in cycles for a (possibly time-varying) frequency in Hz."""
    return np.cumsum(_freq_array(freq, n)) / SR


def sine(freq: float | Array, n: int | None = None, phase0: float = 0.0) -> Array:
    return np.sin(TAU * (phase_cycles(freq, n) + phase0))


def _polyblep(t: Array, dt: Array) -> Array:
    y = np.zeros_like(t)
    m = t < dt
    if m.any():
        x = t[m] / dt[m]
        y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    if m.any():
        x = (t[m] - 1.0) / dt[m]
        y[m] = x * x + x + x + 1.0
    return y


def saw(freq: float | Array, n: int | None = None, phase0: float = 0.0) -> Array:
    """Band-limited (PolyBLEP) sawtooth."""
    f = _freq_array(freq, n)
    dt = np.minimum(np.abs(f) / SR, 0.49)
    ph = (np.cumsum(f) / SR + phase0) % 1.0
    return 2.0 * ph - 1.0 - _polyblep(ph, dt)


def square(freq: float | Array, n: int | None = None, pw: float = 0.5, phase0: float = 0.0) -> Array:
    f = _freq_array(freq, n)
    dt = np.minimum(np.abs(f) / SR, 0.49)
    ph = (np.cumsum(f) / SR + phase0) % 1.0
    y = np.where(ph < pw, 1.0, -1.0)
    return y + _polyblep(ph, dt) - _polyblep((ph - pw) % 1.0, dt)


def tri(freq: float | Array, n: int | None = None, phase0: float = 0.0) -> Array:
    return (2.0 / np.pi) * np.arcsin(np.sin(TAU * (phase_cycles(freq, n) + phase0)))


def fm(fc: float | Array, ratio: float, index: float | Array, n: int | None = None) -> Array:
    """2-operator FM: sin(2pi fc t + I(t) sin(2pi ratio*fc t)).  `index` may be a per-sample curve."""
    fcv = _freq_array(fc, n)
    pc = np.cumsum(fcv) / SR
    pm = np.cumsum(fcv * ratio) / SR
    return np.sin(TAU * pc + index * np.sin(TAU * pm))


def additive(freq: float | Array, amps: Sequence[float], n: int | None = None) -> Array:
    """Sum of harmonics with given amplitudes (harmonics above Nyquist are dropped per sample)."""
    f = _freq_array(freq, n)
    ph = np.cumsum(f) / SR
    y = np.zeros_like(f)
    for k, a in enumerate(amps, start=1):
        if a:
            y += a * np.sin(TAU * k * ph) * (f * k < SR * 0.48)
    return y


def harmonic_table(amps: Sequence[float], size: int = 2048) -> Array:
    ph = np.arange(size) / size
    tbl = sum(a * np.sin(TAU * (k + 1) * ph) for k, a in enumerate(amps))
    return tbl / (np.max(np.abs(tbl)) + 1e-12)


def wavetable_osc(table: Array, freq: float | Array, n: int | None = None) -> Array:
    ph = (phase_cycles(freq, n) % 1.0) * len(table)
    i0 = ph.astype(np.int64)
    fr = ph - i0
    return table[i0 % len(table)] * (1 - fr) + table[(i0 + 1) % len(table)] * fr


def modal(freqs: Sequence[float], taus: Sequence[float], gains: Sequence[float], n: int,
          rng: np.random.Generator | None = None, detune: float = 0.0) -> Array:
    """Bank of exponentially decaying sines: struck metal/glass/wood.  taus in seconds."""
    t = t_axis(n)
    y = np.zeros(n)
    for f, tau, g in zip(freqs, taus, gains):
        fd = f * (1.0 + (rng.uniform(-detune, detune) if rng is not None else 0.0))
        ph = rng.uniform(0, TAU) if rng is not None else 0.0
        y += g * np.exp(-t / tau) * np.sin(TAU * fd * t + ph)
    return y


def karplus_strong(freq: float, seconds: float, rng: np.random.Generator, decay: float = 0.996,
                   bright: float = 1.0) -> Array:
    """Plucked string.  Block-vectorised KS (blocks of one period), retuned exactly by resampling (<1 % ratio)."""
    n = n_of(seconds)
    d0 = max(2, int(round(SR / freq - 0.5)))
    f_actual = SR / (d0 + 0.5)
    y = np.zeros(n + d0 + 2)
    burst = rng.uniform(-1.0, 1.0, d0 + 1)
    if bright < 1.0:  # darker excitation
        burst = np.convolve(burst, [bright, 1 - bright], "same")
    y[: d0 + 1] = burst
    for s in range(d0 + 1, n + d0 + 1, d0):
        m = min(d0, len(y) - s)
        y[s:s + m] = decay * 0.5 * (y[s - d0:s - d0 + m] + y[s - d0 - 1:s - d0 - 1 + m])
    y = y[:n]
    return resample_ratio(y, f_actual / freq)[:n] if abs(f_actual / freq - 1) > 1e-4 else y


def resample_ratio(x: Array, ratio: float) -> Array:
    """Play back `ratio` times faster (pitch * ratio) with linear interpolation (used for tiny retunes / variants)."""
    src = np.arange(0.0, len(x) - 1, ratio)
    if x.ndim == 1:
        return np.interp(src, np.arange(len(x)), x)
    return np.stack([np.interp(src, np.arange(len(x)), x[:, c]) for c in range(x.shape[1])], axis=1)


# --------------------------------------------------------------------------------------------- envelopes
def env_points(n: int, pts: Sequence[tuple], sr: int = SR) -> Array:
    """Piece-wise envelope.  pts = [(t_s, value[, curve]), ...]; `curve` shapes the segment ARRIVING at that point:
    0 linear, k<0 fast-then-slow (exponential decay look), k>0 slow-then-fast (exponential attack look)."""
    ts = np.array([p[0] for p in pts], dtype=np.float64) * sr
    vs = np.array([p[1] for p in pts], dtype=np.float64)
    idx = np.arange(n, dtype=np.float64)
    out = np.full(n, vs[0])
    out[idx >= ts[-1]] = vs[-1]
    for i in range(1, len(pts)):
        lo, hi = ts[i - 1], ts[i]
        m = (idx >= lo) & (idx < hi)
        if not m.any():
            continue
        u = (idx[m] - lo) / max(hi - lo, 1e-9)
        k = pts[i][2] if len(pts[i]) > 2 else 0.0
        s = u if abs(k) < 1e-6 else np.expm1(k * u) / np.expm1(k)
        out[m] = vs[i - 1] + (vs[i] - vs[i - 1]) * s
    return out


def env_exp(n: int, tau: float, attack: float = 0.0008, delay: float = 0.0) -> Array:
    t = t_axis(n) - delay
    e = np.exp(-np.maximum(t, 0.0) / tau)
    if attack > 0:
        e = e * np.clip(t / attack, 0.0, 1.0)
    return np.where(t < 0, 0.0, e)


def env_adsr(n: int, a: float, d: float, s: float, r: float, curve_d: float = -4.0) -> Array:
    total = n / SR
    return env_points(n, [(0, 0), (a, 1, 1.0), (a + d, s, curve_d), (max(total - r, a + d), s), (total, 0, curve_d)])


def lfo(freq: float, n: int, phase0: float = 0.0) -> Array:
    return np.sin(TAU * (freq * t_axis(n) + phase0))


# --------------------------------------------------------------------------------------------- filters
def _rbj(kind: str, fc: float, q: float, gain_db: float) -> tuple[Array, Array]:
    fc = float(min(max(fc, 5.0), SR * 0.499))
    w0 = TAU * fc / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (gain_db / 40.0)
    sA = np.sqrt(A)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":  # constant 0 dB peak gain
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "allpass":
        b = [1 - alpha, -2 * cw, 1 + alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "lowshelf":
        b = [A * ((A + 1) - (A - 1) * cw + 2 * sA * alpha), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - 2 * sA * alpha)]
        a = [(A + 1) + (A - 1) * cw + 2 * sA * alpha, -2 * ((A - 1) + (A + 1) * cw),
             (A + 1) + (A - 1) * cw - 2 * sA * alpha]
    elif kind == "highshelf":
        b = [A * ((A + 1) + (A - 1) * cw + 2 * sA * alpha), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - 2 * sA * alpha)]
        a = [(A + 1) - (A - 1) * cw + 2 * sA * alpha, 2 * ((A - 1) - (A + 1) * cw),
             (A + 1) - (A - 1) * cw - 2 * sA * alpha]
    else:
        raise ValueError(kind)
    b_arr, a_arr = np.array(b, dtype=np.float64), np.array(a, dtype=np.float64)
    return b_arr / a_arr[0], a_arr / a_arr[0]


def _fftconv(x: Array, h: Array, out_len: int | None = None, circular: bool = False) -> Array:
    """Convolution along axis 0 (x mono/stereo, h mono).  circular=True wraps the tail onto the head (len(h) <= len(x))."""
    n = len(x) + len(h) - 1
    nfft = 1 << (n - 1).bit_length()
    H = np.fft.rfft(h, nfft)
    X = np.fft.rfft(x, nfft, axis=0)
    y = np.fft.irfft(X * (H[:, None] if x.ndim == 2 else H), nfft, axis=0)
    if circular:
        out = y[: len(x)].copy()
        tail = y[len(x):n]
        out[: len(tail)] += tail
        return out
    return y[: (out_len if out_len is not None else n)]


def biquad_ir(b: Array, a: Array, n: int) -> Array:
    """Closed-form impulse response (first n samples) of a stable biquad (a[0]==1)."""
    a1, a2 = a[1], a[2]
    h0 = b[0]
    h1 = b[1] - a1 * h0
    h2 = b[2] - a1 * h1 - a2 * h0
    disc = complex(a1 * a1 - 4 * a2)
    sq = np.sqrt(disc)
    p1, p2 = (-a1 + sq) / 2, (-a1 - sq) / 2
    h = np.zeros(n)
    h[0] = h0
    if n > 1:
        h[1] = h1
    if n > 2:
        k = np.arange(1, n, dtype=np.float64)
        if abs(p1 - p2) < 1e-6:  # critically damped: h[k] = (C + D k) p^k
            p = (p1 + p2) / 2
            d = h2 / (p * p) - h1 / p
            c = h1 / p - d
            hk = (c + d * k) * np.exp(k * np.log(p + 0j))
        else:
            det = p1 * p2 * (p2 - p1)
            A = (h1 * p2 * p2 - h2 * p2) / det
            B = (h2 * p1 - h1 * p1 * p1) / det
            hk = A * np.exp(k * np.log(p1 + 0j)) + B * np.exp(k * np.log(p2 + 0j))
        h[1:] = hk.real
        h[1] = h1
        h[2] = h2
    return h


def biquad(x: Array, kind: str, fc: float, q: float = 0.7071, gain_db: float = 0.0, circ: bool = False) -> Array:
    """One RBJ biquad section applied with FFT convolution of its exact impulse response (circ=True: wrap-around, for loops)."""
    b, a = _rbj(kind, fc, q, gain_db)
    r = float(np.max(np.abs(np.roots([1.0, a[1], a[2]]))))
    if r >= 1.0:
        raise ValueError("unstable filter")
    n_ir = int(min(max(64, np.ceil(np.log(1e-9) / np.log(max(r, 1e-6)))), len(x), 1 << 19))
    return _fftconv(x, biquad_ir(b, a, n_ir), len(x), circ)


def _butter_qs(order: int) -> list[float]:
    assert order % 2 == 0 and order >= 2, "even orders only"
    return [1.0 / (2.0 * np.sin((2 * k + 1) * np.pi / (2 * order))) for k in range(order // 2)]


def lowpass(x: Array, fc: float, order: int = 2, q: float | None = None, circ: bool = False) -> Array:
    """order 2 = single RBJ section (q default 0.7071); order 4/6/8 = Butterworth cascade."""
    if order == 2:
        return biquad(x, "lp", fc, q if q is not None else 0.7071, 0.0, circ)
    for qk in _butter_qs(order):
        x = biquad(x, "lp", fc, qk, 0.0, circ)
    return x


def highpass(x: Array, fc: float, order: int = 2, q: float | None = None, circ: bool = False) -> Array:
    if order == 2:
        return biquad(x, "hp", fc, q if q is not None else 0.7071, 0.0, circ)
    for qk in _butter_qs(order):
        x = biquad(x, "hp", fc, qk, 0.0, circ)
    return x


def bandpass(x: Array, lo: float, hi: float, order: int = 2, circ: bool = False) -> Array:
    return lowpass(highpass(x, lo, order, None, circ), hi, order, None, circ)


def resonator(x: Array, fc: float, q: float, circ: bool = False) -> Array:
    return biquad(x, "bp", fc, q, 0.0, circ)


def fft_filter(x: Array, gain_of_f) -> Array:
    """Zero-phase static filter: gain_of_f(freqs_hz) -> linear gain.  Circular by construction (length n)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    g = gain_of_f(f)
    X = np.fft.rfft(x, axis=0)
    return np.fft.irfft(X * (g[:, None] if x.ndim == 2 else g), n, axis=0)


def sweep_filter(x: Array, cutoff_hz: Array, kind: str = "lp", q: float = 0.7071, order: int = 2,
                 steps: int = 20, circ: bool = False) -> Array:
    """Time-varying filter: cross-fade a log-spaced bank of static filters according to cutoff_hz[n].
    Vectorised, unconditionally stable, ~1/6-octave resolution at steps=24 (use >=32 for high-Q sweeps)."""
    c = np.clip(np.asarray(cutoff_hz, dtype=np.float64), 20.0, SR * 0.45)
    lo, hi = float(c.min()), float(c.max())
    apply = lowpass if kind == "lp" else highpass
    if hi / lo < 1.03:
        return apply(x, float(np.sqrt(lo * hi)), order, q if order == 2 else None, circ)
    edges = np.geomspace(lo, hi, steps)
    bank = np.stack([apply(x, float(e), order, q if order == 2 else None, circ) for e in edges])
    pos = np.interp(np.log(c), np.log(edges), np.arange(steps))
    k0 = np.clip(np.floor(pos).astype(np.int64), 0, steps - 2)
    w = pos - k0
    idx = np.arange(len(x))
    lo_s, hi_s = bank[k0, idx], bank[k0 + 1, idx]
    wb = w[:, None] if x.ndim == 2 else w
    return lo_s * (1 - wb) + hi_s * wb


def bass_mono(x: Array, fc: float = 140.0, circ: bool = False) -> Array:
    """Mono-compatibility: collapse everything below fc to the centre (Linkwitz-Riley 4th-order crossover, flat sum)."""
    if x.ndim == 1:
        return x
    def lr4(sig: Array, kind: str) -> Array:
        return biquad(biquad(sig, kind, fc, 0.7071, 0.0, circ), kind, fc, 0.7071, 0.0, circ)
    low = lr4(x.mean(axis=1), "lp")
    return np.stack([low + lr4(x[:, 0], "hp"), low + lr4(x[:, 1], "hp")], axis=1)


def bass_exciter(x: Array, amount: float = 0.5, fc: float = 240.0, drive: float = 4.0, hp: float = 110.0,
                 circ: bool = False) -> Array:
    """Psychoacoustic bass: saturate the low band and add only the generated harmonics (>hp) so sub-bass content
    stays audible on small speakers.  Asymmetric bias adds even harmonics."""
    low = lowpass(x, fc, 2, None, circ)
    h = highpass(saturate(low * 2.5, drive, bias=0.12), hp, 2, None, circ)
    return x + amount * h


# --------------------------------------------------------------------------------------------- distortion / dynamics
def saturate(x: Array, drive: float = 2.0, bias: float = 0.0) -> Array:
    """tanh waveshaper, gain-compensated so small signals keep their level; bias adds even harmonics."""
    y = np.tanh(drive * (x + bias)) - np.tanh(drive * bias)
    return y / np.tanh(drive)


def hard_clip(x: Array, level: float = 0.7) -> Array:
    return np.clip(x, -level, level) / level


def wavefold(x: Array, k: float = 3.0) -> Array:
    return np.sin(k * x)


def bitcrush(x: Array, bits: int = 8, hold: int = 1) -> Array:
    q = 2.0 ** (bits - 1)
    y = np.round(x * q) / q
    if hold > 1:
        y = np.repeat(y[::hold], hold, axis=0)[: len(x)]
    return y


def limit(x: Array, ceiling_db: float = -1.0, lookahead_s: float = 0.004, release_s: float = 0.08) -> Array:
    """Block look-ahead peak limiter (vectorised gain computer, sequential release over ~lookahead blocks)."""
    c = db_to_lin(ceiling_db)
    pk = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    g = np.minimum(1.0, c / np.maximum(pk, 1e-9))
    blk = max(8, int(lookahead_s * SR))
    npad = (-len(g)) % blk
    gp = np.concatenate([g, np.ones(npad)])
    gb = gp.reshape(-1, blk).min(axis=1)
    gb = np.minimum(gb, np.minimum(np.r_[1.0, gb[:-1]], np.r_[gb[1:], 1.0]))
    rel = np.exp(-blk / (release_s * SR))
    out = np.empty_like(gb)
    s = 1.0
    for i, v in enumerate(gb):  # ~ n/blk iterations (a few hundred per second of audio)
        s = v if v < s else 1.0 - (1.0 - s) * rel
        s = min(s, v)
        out[i] = s
    centres = (np.arange(len(out)) + 0.5) * blk
    gs = np.interp(np.arange(len(g)), centres, out)
    y = x * _bc(gs, x)
    return np.clip(y, -c, c)


# --------------------------------------------------------------------------------------------- time / space
def echo(x: Array, time_s: float, feedback: float = 0.4, mix: float = 0.35, taps: int = 6,
         lp_hz: float | None = None, circular: bool = False) -> Array:
    """Finite-tap echo (each repeat progressively low-passed when lp_hz is given).  Length grows unless circular."""
    d = n_of(time_s)
    n = len(x)
    out = np.zeros((n if circular else n + d * taps,) + x.shape[1:])
    out[:n] += x
    rep = x
    for k in range(1, taps + 1):
        rep = lowpass(rep, lp_hz) if lp_hz else rep
        g = mix * feedback ** (k - 1)
        if circular:
            out += g * np.roll(rep, d * k, axis=0)
        else:
            out[d * k:d * k + n] += g * rep
    return out


def make_ir(rt60: float = 1.6, predelay: float = 0.012, damping_hz: float = 5500.0, size: float = 1.0,
            low_mult: float = 1.15, seed: str = "ir", early: int = 10, stereo: bool = True) -> Array:
    """Synthetic algorithmic reverb impulse response, energy-normalised, decorrelated L/R.
    Three decay bands (low / mid / damped-high), sparse early reflections, gentle build-up."""
    length = int((rt60 * 1.2 + predelay + 0.05) * SR)
    chans = []
    for ch in range(2 if stereo else 1):
        rng = rng_for(seed, 17 + ch)
        t = t_axis(length)
        ir = np.zeros(length)
        for lo, hi, rt in ((30.0, 400.0, rt60 * low_mult), (400.0, 3000.0, rt60),
                           (3000.0, min(damping_hz * 1.6, 18000.0), rt60 * min(1.0, damping_hz / 9000.0 + 0.15))):
            band = colored_noise(length, rng, 0.0, lo=lo, hi=hi, skirt_oct=0.6)
            ir += band * np.exp(-6.9078 * t / max(rt, 0.05))
        ir *= np.clip(1.0 - np.exp(-t / (0.006 * size + 1e-4)), 0.0, 1.0)  # build-up
        ir = lowpass(ir, damping_hz, 2)
        for _ in range(early):  # early reflections
            pos = int(rng.uniform(0.004, 0.04 + 0.05 * size) * SR)
            ir[pos:pos + 3] += rng.uniform(0.6, 1.6) * rng.choice([-1, 1]) * np.array([0.6, 1.0, 0.4]) * np.exp(-pos / SR / 0.05)
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])[:length]
        chans.append(ir)
    ir = np.stack(chans, axis=1) if stereo else chans[0]
    return ir / (np.sqrt(np.sum(ir * ir, axis=0)) + 1e-12)


def reverb(x: Array, ir: Array, wet: float = 0.3, dry: float = 1.0, circular: bool = False,
           tail: bool = True) -> Array:
    """Convolution reverb. mono in -> stereo out (L/R IR); stereo in -> per-channel IR.
    circular=True: FFT convolution at the signal length (tails wrap around: seamless loop).  Otherwise the output is
    extended by the IR length unless tail=False."""
    xs = to_stereo(x) if ir.ndim == 2 else x
    irs = ir if ir.ndim == 2 else ir
    n = len(xs)
    if circular:
        h = np.zeros((n,) + irs.shape[1:]) if irs.ndim == 2 else np.zeros(n)
        m = min(n, len(irs))
        h[:m] = irs[:m]
        X = np.fft.rfft(xs, axis=0)
        H = np.fft.rfft(h, axis=0)
        w = np.fft.irfft(X * H, n, axis=0)
        return dry * xs + wet * w
    out_len = n + len(irs) - 1 if tail else n
    if irs.ndim == 2:
        w = np.stack([_fftconv(xs[:, c], irs[:, c], out_len) for c in range(2)], axis=1)
    else:
        w = _fftconv(xs, irs, out_len)
    d = fit(xs, out_len)
    return dry * d + wet * w


def pan(x: Array, p: float | Array) -> Array:
    """Equal-power pan of a mono signal to stereo.  p in [-1 (L), +1 (R)] scalar or per-sample."""
    m = to_mono(x)
    ang = (np.asarray(p, dtype=np.float64) + 1.0) * np.pi / 4.0
    return np.stack([m * np.cos(ang), m * np.sin(ang)], axis=1)


def widen(x: Array, amount: float = 1.4) -> Array:
    """Mid/side width (1 = unchanged)."""
    x = to_stereo(x)
    m, s = (x[:, 0] + x[:, 1]) * 0.5, (x[:, 0] - x[:, 1]) * 0.5
    return np.stack([m + s * amount, m - s * amount], axis=1)


def haas(x: Array, ms: float = 12.0) -> Array:
    x = to_stereo(x)
    d = n_of(ms / 1000.0)
    r = np.concatenate([np.zeros(d), x[:, 1]])[: len(x)]
    return np.stack([x[:, 0], r], axis=1)


def decorrelate(x: Array, seed: str, length_ms: float = 18.0) -> Array:
    """Tone-neutral stereo spread: convolve L/R with different random-phase unit-magnitude FIRs (all-pass-like)."""
    m = to_mono(x)
    n = n_of(length_ms / 1000.0)
    outs = []
    for ch in range(2):
        rng = rng_for(seed, 91 + ch)
        spec = np.exp(1j * rng.uniform(0, TAU, n // 2 + 1))
        spec[0] = 1.0
        fir = np.fft.irfft(spec, n) * np.hanning(n) ** 0.5
        fir /= np.sqrt(np.sum(fir * fir))
        outs.append(_fftconv(m, fir, len(m)))
    return np.stack(outs, axis=1)


# --------------------------------------------------------------------------------------------- mixing / IO
def place(dst: Array, src: Array, start: int, gain: float = 1.0, wrap: bool = False) -> Array:
    """Add src into dst at sample `start` (mono src is broadcast to stereo dst).  wrap=True wraps around the end."""
    if dst.ndim == 2 and src.ndim == 1:
        src = np.stack([src, src], axis=1)
    n, m, s = len(dst), len(src), int(start)
    if wrap:
        s %= n
        done = 0
        while done < m:
            k = min(n - s, m - done)
            dst[s:s + k] += src[done:done + k] * gain
            done += k
            s = 0
        return dst
    e = min(n, s + m)
    if s >= n or e <= 0:
        return dst
    a = max(0, -s)
    dst[max(s, 0):e] += src[a:a + (e - max(s, 0))] * gain
    return dst


def fade(x: Array, fade_in: float = 0.0, fade_out: float = 0.0) -> Array:
    x = x.copy()
    n = len(x)
    fi, fo = min(n_of(fade_in), n), min(n_of(fade_out), n)
    if fi:
        x[:fi] *= _bc(0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi), x[:fi])
    if fo:
        x[n - fo:] *= _bc(0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo), x[n - fo:])
    return x


def loop_crossfade(x: Array, xf_s: float) -> Array:
    """For non-circular material: equal-power cross-fade the tail into the head; result is shorter by xf."""
    xf = n_of(xf_s)
    n = len(x) - xf
    t = np.arange(xf) / xf
    head, tail = x[:xf], x[n:n + xf]
    y = x[:n].copy()
    y[:xf] = head * _bc(np.sin(t * np.pi / 2), head) + tail * _bc(np.cos(t * np.pi / 2), tail)
    return y


def seam_score(x: Array) -> float:
    """|x[0]-x[-1]| relative to the typical sample-to-sample step (<~4 = inaudible seam; big = click)."""
    d = np.abs(np.diff(x, axis=0))
    typ = float(np.median(d) + 0.5 * np.std(d)) + 1e-9
    j = float(np.max(np.abs(x[0] - x[-1])))
    return j / typ


def write_wav(path: str, x: Array, dither_seed: str | None = None) -> None:
    """16-bit PCM WAV (stdlib wave), optional 1-LSB TPDF dither, hard guard against clipping wrap."""
    y = x.astype(np.float64)
    if dither_seed is not None:
        r = rng_for(dither_seed, 5)
        y = y + (r.random(y.shape) - r.random(y.shape)) / 32768.0
    pcm = np.clip(np.round(y * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path: str) -> Array:
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2, "16-bit PCM only"
        ch, raw = w.getnchannels(), w.readframes(w.getnframes())
    y = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return y.reshape(-1, ch) if ch > 1 else y


# --------------------------------------------------------------------------------------------- self test
def _selftest() -> None:
    rng = rng_for("selftest")
    x = rng.standard_normal(30000)
    try:
        from scipy.signal import lfilter  # verification only
    except ImportError:
        lfilter = None
    for kind, fc, q in (("lp", 1000, 0.707), ("hp", 60, 0.707), ("bp", 3000, 8.0), ("lowshelf", 200, 0.7), ("lp", 50, 12.0)):
        y = biquad(x, kind, fc, q, 6.0)
        if lfilter is not None:
            b, a = _rbj(kind, fc, q, 6.0)
            err = float(np.max(np.abs(y - lfilter(b, a, x))))
            print(f"biquad {kind:8s} fc={fc:5d} q={q:5.2f} max|err| vs scipy.lfilter = {err:.2e}")
            assert err < 1e-6, err
    n = 44100
    a = colored_noise(n, rng, 1.0)
    print("circular noise seam_score:", round(seam_score(a), 2), "(random pairs ~1-3)")
    print("selftest OK")


if __name__ == "__main__":
    _selftest()
