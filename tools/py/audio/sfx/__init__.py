"""sfx - procedural sound-effect recipes (numpy only, built on dsp.py).

Recipe contract (audio spec 7.8): `fn(rng, variant, **params) -> ndarray`, mono (n,) or stereo (n,2), float64;
pure (no globals mutated, no I/O, no clock).  Looping recipes are circular by construction (frequency-domain noise,
whole-cycle-snapped oscillators, wrap-around placement, circular filters/echo/reverb).  Register with `@recipe`.
The mastering chain (level, exciter, dither, encoding) lives in render.py, not in recipes.
"""
from __future__ import annotations

import importlib
from typing import Callable

RECIPES: dict[str, Callable] = {}
MODULES = ("weapons", "projectiles", "impacts", "explosions", "structures", "powers", "superweapons", "ui",
           "alarms", "movement", "ambience")


def recipe(fn: Callable) -> Callable:
    if fn.__name__ in RECIPES:
        raise ValueError(f"duplicate recipe {fn.__name__}")
    RECIPES[fn.__name__] = fn
    return fn


def load_all() -> dict[str, Callable]:
    for m in MODULES:
        importlib.import_module(f"sfx.{m}")
    return RECIPES
