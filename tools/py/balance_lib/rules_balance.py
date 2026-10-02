"""Framework cross-checks on unit sheets: fair-cost deviation and stat bands (V-RNG-02), derived helpers (V-RNG-06), tier monotonicity (V-TIER-05).

Reuses tools/py/balance_calc.py (fair_cost_deviation, effective_dps) so there is exactly one formula.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from .context import Ctx, LoadedFile, num
from .rules_files import add

_BC = None
_BC_FAILED = False


def balance_calc(ctx: Ctx):
    global _BC, _BC_FAILED
    if _BC is None and not _BC_FAILED:
        here = str(Path(__file__).resolve().parents[1])
        if here not in sys.path:
            sys.path.insert(0, here)
        os.environ["MERIDIAN_BALANCE_GLOBAL"] = str(ctx.dir / "global.json")
        try:
            import balance_calc as bc  # noqa: WPS433
            _BC = bc
        except Exception:  # noqa: BLE001 - any import problem just disables the framework cross-check
            _BC_FAILED = True
    return _BC


def framework_names(reg_aliases: dict, entries: list) -> list[str]:
    out = []
    for n in entries:
        if not isinstance(n, str):
            continue
        if n.startswith("ability."):
            rev = sorted(a for a, t in reg_aliases.items() if t == n)
            out.append(rev[0] if rev else n)
        else:
            out.append(n)
    return out


def check_balance(ctx: Ctx, lf: LoadedFile, units: list[dict]) -> None:
    bc = balance_calc(ctx)
    if bc is None:
        return
    reg = ctx.files.get("ability_kinds.json")
    aliases = reg.data.get("aliases", {}) if reg and reg.ok and isinstance(reg.data.get("aliases"), dict) else {}  # type: ignore[union-attr]
    tol = ctx.g.get("scaling", {}).get("tolerances", {})
    rows: dict[str, list[tuple[int, float, float, str]]] = {}
    for e in units:
        uid = e.get("id")
        arch_id = e.get("archetype")
        a = ctx.arch.get(arch_id) if isinstance(arch_id, str) else None
        if not isinstance(uid, str) or a is None or uid not in ctx.b_units:
            continue

        def W(field: str, msg: str, exp: object, found: object, rule: str = "V-RNG-02") -> None:
            add(ctx, rule, lf, msg, e, field if field in e else "id", entity=uid, field=field, expected=exp, found=found)
        # effective numbers
        eff = {k: num(ctx.eff(e, k)) for k in ("cost_credits", "health", "speed_cells_s", "vision_cells", "radius_cells")}
        if eff["cost_credits"] is None or eff["health"] is None or eff["speed_cells_s"] is None or eff["vision_cells"] is None:
            continue
        ua = ctx.ua.get(uid, {})
        entries = e["abilities"] if isinstance(e.get("abilities"), list) else ua.get("abilities", [])
        weapons_by_id = {w["id"]: w for w in _weapon_list(lf)}
        if "weapons" in e:
            ws = [weapons_by_id[i] for i in e["weapons"] if isinstance(i, str) and i in weapons_by_id] if isinstance(e["weapons"], list) else []
        else:
            ws = list(a.get("weapons", []))
        full = []
        for w in ws:
            if not all(num(w.get(k)) is not None for k in ("damage", "reload_s", "range_cells")) or w.get("archetype") not in bc.WA or not num(w.get("reload_s")):
                full = None
                break
            full.append({**w, "hits_per_volley": w.get("hits_per_volley", 1)})
        if full is None:
            continue
        rearm_full = num(e.get("rearm_s_full"))
        mult = (rearm_full / a["rearm_s_full"]) if (rearm_full is not None and a.get("rearm_s_full")) else 1.0
        if "drone_weapon" in a:
            dps = a["dps_ref"]
        else:
            try:
                dps = bc.effective_dps(a, full, mult) if full else 0.0
            except Exception:  # noqa: BLE001
                continue
        rng = max((float(w["range_cells"]) for w in full), default=0.0)
        aircraft = a.get("family") == "aircraft"
        helper_key = "sortie_avg_dps_vs_primary" if aircraft else "dps_vs_primary"
        for key, calc in ((helper_key, dps), ("range_cells", rng)):
            given = num(e.get(key))
            if given is not None and calc and abs(given - calc) / calc > 0.01:
                W(key, f"derived helper {key} deviates {abs(given - calc) / calc * 100:.1f} % from the value recomputed from the weapons (limit 1 %)", round(calc, 1), given, "V-RNG-06")
            elif given is not None and not calc and given:
                W(key, f"derived helper {key} is set but the weapons give 0", 0, given, "V-RNG-06")
        unit = {"archetype": arch_id, "health": eff["health"], "speed_cells_s": eff["speed_cells_s"], "vision_cells": eff["vision_cells"], "cost_credits": eff["cost_credits"],
                "range_cells": rng, "dps_vs_primary": dps, "sortie_avg_dps_vs_primary": dps, "abilities": framework_names(aliases, entries)}
        try:
            dev = bc.fair_cost_deviation(unit) * 100
        except Exception:  # noqa: BLE001
            continue
        lim = tol.get("power_index_pct", 8)
        if abs(dev) > lim:
            W("cost_credits", f"fair-cost deviation {dev:+.1f} % (limit +-{lim} %) for archetype {arch_id}: cost {eff['cost_credits']:.0f} vs stats/abilities",
              f"within +-{lim} %", f"{dev:+.1f} %")
        for key, akey, tk in (("cost_credits", "cost_credits", "cost_pct"), ("health", "health", "health_pct"), ("speed_cells_s", "speed_cells_s", "speed_pct"),
                              ("vision_cells", "vision_cells", "vision_pct"), ("radius_cells", "radius_cells", "radius_pct")):
            v, base = eff[key], num(a.get(akey))
            if v is None or not base or tk not in tol:
                continue
            d = (v / base - 1) * 100
            if abs(d) > tol[tk]:
                W(key, f"{key} {d:+.0f} % vs archetype {arch_id} (limit +-{tol[tk]} %)", f"{base * (1 - tol[tk] / 100):.4g}..{base * (1 + tol[tk] / 100):.4g}", v)
        tier = e.get("tier", ctx.b_units[uid].get("tier"))
        for tag in ("tank", "anti_air", "artillery", "anti_tank", "aircraft", "ship"):
            if tag in ctx.b_units[uid].get("tags", []) and isinstance(tier, int):
                rows.setdefault(tag, []).append((tier, eff["cost_credits"], num(e.get("build_time_s")) or num(ctx.eff(e, "build_time_s")) or 0.0, uid))
    for tag, lst in sorted(rows.items()):
        tiers = sorted({t for t, _, _, _ in lst})
        prev = None
        for t in tiers:
            cost = min(c for tt, c, _, _ in lst if tt == t)
            bt = min(b for tt, _, b, _ in lst if tt == t)
            uid = [u for tt, c, _, u in lst if tt == t and c == cost][0]
            if prev and (cost < prev[1] or bt < prev[2]):
                e = next(x for x in units if x.get("id") == uid)
                add(ctx, "V-TIER-05", lf, f"role tag {tag!r}: the cheapest tier-{t} unit ({cost:.0f} cr, {bt}s) is cheaper/faster than the cheapest tier-{prev[0]} unit "
                    f"({prev[1]:.0f} cr, {prev[2]}s)", e, "id", entity=uid, field="cost_credits", expected=f">= tier {prev[0]}: {prev[1]:.0f} cr / {prev[2]} s", found=f"{cost:.0f} cr / {bt} s")
            prev = (t, cost, bt)


def _weapon_list(lf: LoadedFile) -> list[dict]:
    w = lf.data.get("weapons") if isinstance(lf.data, dict) else None
    return [x for x in w if isinstance(x, dict) and isinstance(x.get("id"), str)] if isinstance(w, list) else []
