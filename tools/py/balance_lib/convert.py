"""Designer-unit -> integer conversions, a straight mirror of DefConvert (spec data_balance 5.2.2). `milli(v)` is the one float step."""
from __future__ import annotations

TPS = 20
CELL = 1024
TURN = 4096


def milli(v: float | int) -> int:
    """Round a JSON number to integer thousandths (half away from zero); numbers have <= 3 decimals so this is exact."""
    x = round(abs(v) * 1000 + 1e-9)
    return -x if v < 0 else x


def rdiv(n: int, d: int) -> int:
    """Half-away-from-zero integer division (GDScript: (2*|n| + d) / (2*d) * sign(n) with truncating division)."""
    q = (2 * abs(n) + d) // (2 * d)
    return -q if n < 0 else q


def ceil_div(n: int, d: int) -> int:
    return (n + d - 1) // d


def cells_to_units(x: float) -> int:
    return rdiv(milli(x) * CELL, 1000)


def cells_s_to_upt(x: float) -> int:
    return rdiv(milli(x) * CELL, 1000 * TPS)


def s_to_ticks(x: float) -> int:
    return ceil_div(milli(x) * TPS, 1000)


def s_to_mt(x: float) -> int:
    return milli(x) * TPS


def pct_to_bp(x: float) -> int:
    return rdiv(milli(x) * 100, 1000)


def deg_to_a(x: float) -> int:
    return rdiv(milli(x) * TURN, 360000)


def deg_s_to_apt(x: float) -> int:
    return max(1, rdiv(milli(x) * TURN, 360000 * TPS)) if x > 0 else 0


# self-test vectors taken from the spec tables (5.2.2) -- (function, input, expected)
VECTORS = [
    (cells_to_units, 7.0, 7168), (cells_to_units, 0.55, 563), (cells_to_units, 1.0, 1024), (cells_to_units, 0.001, 1),
    (cells_s_to_upt, 1.0, 51), (cells_s_to_upt, 2.0, 102), (cells_s_to_upt, 3.2, 164), (cells_s_to_upt, 16.0, 819),
    (s_to_ticks, 1.05, 21), (s_to_ticks, 1.051, 22), (s_to_ticks, 0.05, 1), (s_to_ticks, 0.06, 2), (s_to_ticks, 8, 160), (s_to_ticks, 45, 900),
    (s_to_ticks, 75, 1500), (s_to_ticks, 27.5, 550), (s_to_ticks, 1.2, 24),
    (s_to_mt, 1.2, 24000), (s_to_mt, 0.25, 5000),
    (pct_to_bp, 10, 1000), (pct_to_bp, 0.5, 50), (pct_to_bp, 12.5, 1250), (pct_to_bp, -15, -1500),
    (deg_to_a, 90, 1024), (deg_to_a, 360, 4096),
    (deg_s_to_apt, 180, 102), (deg_s_to_apt, 90, 51), (deg_s_to_apt, 120, 68), (deg_s_to_apt, 150, 85),
]


def self_test() -> list[str]:
    bad = []
    for fn, x, want in VECTORS:
        got = fn(x)
        if got != want:
            bad.append(f"{fn.__name__}({x}) = {got}, expected {want}")
    for n, d, want in ((5, 2, 3), (-5, 2, -3), (4, 2, 2), (1, 3, 0), (0, 5, 0)):
        if rdiv(n, d) != want:
            bad.append(f"rdiv({n},{d}) = {rdiv(n, d)}, expected {want}")
    return bad
