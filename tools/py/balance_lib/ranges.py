"""The one RANGES table (V-RNG-01), mirrored by DefValidator.RANGES on the engine side. Values are in FILE units (cells, seconds, credits, hp)."""
from __future__ import annotations

# key -> (lo, hi) inclusive
RANGES: dict[str, tuple[float, float]] = {
    "cost_credits": (50, 6000),
    "build_time_s": (2, 120),
    "health": (20, 100000),
    "speed_cells_s": (0.3, 14),
    "vision_cells": (2, 20),
    "radius_cells": (0.2, 2.5),
    "damage": (1, 100000),
    "range_cells": (0.5, 60),
    "reload_s": (0.05, 60),
    "footprint": (1, 8),
}

# sheet field -> RANGES key (unit and summon entries)
UNIT_FIELDS = {k: k for k in ("cost_credits", "build_time_s", "health", "speed_cells_s", "vision_cells", "radius_cells")}
