#!/usr/bin/env python3
"""Meridian Fracture balance calculator (stdlib only, offline, deterministic).

Single source of numbers: game/data/balance/global.json.  This tool holds no game-tuning numbers; it only implements the formulas
documented in docs/balance/FRAMEWORK.md and TAXONOMY.md plus model mechanics (formation spacing, scenario layouts, sampling rings).

Commands (python3 tools/py/balance_calc.py <cmd> [options]):
  table                       tier-curve tables (markdown)
  matrix                      damage-type x armor-class matrix
  propose  ARCH [--tier N] [--tags a,b] [--abilities x,y] [--faction F] [--cost N] [--json]
                              role + tier + style -> starting stats (fair cost, build time); --cost N scales HP/damage to a chosen price
  proposals [--faction F] [--styled] [--csv]   proposals for every bible combat unit (uses unit_assignments)
  resolve UNIT_ID ROSTER_ID [--styled]  base proposal -> final sim integers after the bible layering rule (integer recipe)
  check FILE.json             lint a designer's unit sheet against the framework (fair-cost deviation, bands)
  ttk                         unopposed time-to-kill grid (analytic, matrix included)
  duel A B                    discrete 1v1 from a shared start distance
  rps                         equal-cost group fights (engagement simulator)
  sorties                     aircraft sortie economics vs AA share
  defenses                    static-defense budgets (break-cost ratios, outranging)
  structures                  structure kill times
  sw                          superweapon / support-power damage budgets on reference clusters
  econ                        collector cycle, income, payback, expansion
  pacing                      build-order timelines (first scout/tank/AA/siege/T3/superweapon)
  power                       power balance per structure set
  modifiers [--emit]          passive-modifier value index + recommended base-stat compensation per roster (reads the bible)
  validate                    run every check against global.json targets; exit 1 on any failure
  report                      print every table as markdown (used to refresh FRAMEWORK.md)
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GLOBAL_PATH = Path(os.environ.get("MERIDIAN_BALANCE_GLOBAL", str(ROOT / "game" / "data" / "balance" / "global.json")))
BIBLE_PATH = ROOT / "Input" / "meridian_agent_reference" / "meridian_factions.json"
TPS = 20


# ---------------------------------------------------------------------------------------------- loading
def load_global(path: Path = GLOBAL_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


G = load_global()
ARMORS = [a["id"] for a in G["armor_classes"]]
DTYPES = [d["id"] for d in G["damage_types"]]
WA = G["weapon_archetypes"]
ARCH = G["archetypes"]


def pct(dtype: str, armor: str) -> int:
    return G["damage_matrix"][dtype][armor]


def final_damage(raw: int, matrix_pct: int, res_pct: int = 0, falloff_pct: int = 100, bonus_bp: int = 10000) -> int:
    """Integer damage pipeline (mirrors DefDamageMath.final_damage): ONE half-up rounding, min 1.
    final = raw * bonus_bp/10000 * matrix/100 * (100-min(50,res))/100 * falloff/100"""
    if raw <= 0 or matrix_pct <= 0 or falloff_pct <= 0 or bonus_bp <= 0:
        return 0
    res = min(int(G["resistance_rules"]["cap_pct"]), max(0, res_pct))
    num = raw * bonus_bp * matrix_pct * (100 - res) * falloff_pct
    den = 10000 * 100 * 100 * 100
    return max(1, (num * 2 + den) // (2 * den))


def md_table(headers, rows, align=None) -> str:
    align = align or ["l"] + ["r"] * (len(headers) - 1)
    sep = ["---:" if a == "r" else ":---" for a in align]
    out = ["| " + " | ".join(str(h) for h in headers) + " |", "| " + " | ".join(sep) + " |"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def fmt_t(s: float) -> str:
    s = int(round(s))
    return f"{s // 60}:{s % 60:02d}"


# ---------------------------------------------------------------------------------------------- weapons
def weapon_targets(w: dict) -> list:
    return w.get("targets_override", WA[w["archetype"]]["targets"])


def weapon_dps(w: dict, target_class: str) -> tuple[float, float]:
    """(raw_dps, dps_vs_target_class) for one weapon dict (archetype defaults + overrides)."""
    a = WA[w["archetype"]]
    raw = w["damage"] * w["hits_per_volley"] / w["reload_s"]
    if a["damage_type"] == "emp":
        return raw, raw
    return raw, raw * pct(a["damage_type"], target_class) / 100.0


def ttk_unopposed(att: dict, target: dict, res_pct: int = 0) -> float:
    """Analytic TTK: attacker's best weapon vs target (dict with health, armor_class).
    Discrete: ceil(hp/volley)-1 reloads + first-shot flight ignored. Returns seconds (continuous DPS estimate)."""
    best = None
    for w in att["weapons"]:
        a = WA[w["archetype"]]
        layer = target.get("layer", "ground")
        if layer not in weapon_targets(w):
            continue
        raw, d = weapon_dps(w, target["armor_class"])
        if d <= 0:
            continue
        if res_pct:
            d = d * (100 - min(50, res_pct)) / 100.0
        t = target["health"] / d
        if best is None or t < best:
            best = t
    return best if best is not None else float("inf")


# ---------------------------------------------------------------------------------------------- proposals
def tag_effects(tags):
    eff = dict(health=1.0, speed=1.0, damage=1.0, range=1.0, reload=1.0, vision=1.0, scatter=1.0, radius=1.0, ammo=1.0, rearm=1.0, remove_weapons=False)
    for t in tags:
        e = G["style_tags"][t]
        if "health_pct" in e:
            eff["health"] *= e["health_pct"] / 100.0
        if "speed_pct" in e:
            eff["speed"] *= e["speed_pct"] / 100.0
        if "damage_pct" in e:
            eff["damage"] *= e["damage_pct"] / 100.0
        if "range_pct" in e:
            eff["range"] *= e["range_pct"] / 100.0
        if "reload_pct" in e:
            eff["reload"] *= e["reload_pct"] / 100.0
        if "vision_pct" in e:
            eff["vision"] *= e["vision_pct"] / 100.0
        if "scatter_pct" in e:
            eff["scatter"] *= e["scatter_pct"] / 100.0
        if "radius_pct" in e:
            eff["radius"] *= e["radius_pct"] / 100.0
        if "ammo_pct" in e:
            eff["ammo"] *= e["ammo_pct"] / 100.0
        if "rearm_pct" in e:
            eff["rearm"] *= e["rearm_pct"] / 100.0
        if e.get("remove_weapons"):
            eff["remove_weapons"] = True
    return eff


def round_to(x: float, step: float) -> float:
    return math.floor(x / step + 0.5) * step


def producer_rate(producer: str, tier: int) -> float:
    r = G["production"]["rate_credits_per_s"]
    if producer == "factory":
        return r[f"factory_t{tier}"]
    return r[producer]


def effective_dps(arch: dict, weapons: list, rearm_mult: float = 1.0) -> float:
    """Fair-cost DPS of a (tag-adjusted) weapon set against the archetype's primary target class.
    Aircraft: sortie average (damage per sortie / cycle); carriers: drone wing; others: best sustained weapon."""
    tgt = arch["primary_target_class"]
    if arch["family"] == "aircraft" and weapons:
        w = weapons[0]
        at = WA[w["archetype"]]
        t2 = "air_light" if weapon_targets(w) == ["air"] else tgt
        sortie = w["damage"] * w["hits_per_volley"] * w.get("ammo_volleys", 1) * pct(at["damage_type"], t2) / 100.0
        cycle = arch["sortie_cycle_s"] - arch["rearm_s_full"] + arch["rearm_s_full"] * rearm_mult
        return sortie / cycle
    if "drone_weapon" in arch:
        dw = arch["drone_weapon"]
        return arch["drone_count"] * dw["damage"] * dw["hits_per_volley"] / dw["reload_s"] * pct(WA[dw["archetype"]]["damage_type"], tgt) / 100.0
    best = 0.0
    for w in weapons:
        if w["archetype"] in ("torpedo", "cruise_missile"):
            continue
        at = WA[w["archetype"]]
        t2 = "air_light" if weapon_targets(w) == ["air"] else tgt
        best = max(best, weapon_dps(w, t2)[1])
    if best <= 0 and weapons:
        best = max(weapon_dps(w, tgt)[1] for w in weapons)
    return best


def propose(arch_id: str, tier: int | None = None, tags=(), abilities=(), faction: str | None = None, target_cost: int | None = None,
            extra_offset_pct: float = 0.0) -> dict:
    """Starting stats for one unit: reference archetype x tag multipliers x faction style, cost from the fair-cost formula.
    target_cost: scale HP and damage linearly with cost/cost_ref first (equal efficiency), so a designer can pick the price and get the stats."""
    a = ARCH[arch_id]
    tier = tier or a["tier"]
    eff = tag_effects(tags)
    if target_cost:
        k = target_cost / a["cost_credits"]
        eff["health"] *= k
        eff["damage"] *= k
    style = G["faction_styles"].get(faction or "", {}) if faction else {}
    off = style.get("power_offset_pct", 0.0)
    off_f = ((1.0 + off / 100.0) * (1.0 + extra_offset_pct / 100.0)) ** 0.5   # applied to HP and to every weapon damage (PI moves by off)
    hp = a["health"] * eff["health"] * style.get("health_pct", 100) / 100.0
    if "unmanned" in abilities:
        hp *= style.get("unmanned_health_pct", 100) / 100.0
    speed = a["speed_cells_s"] * eff["speed"]
    vision = a["vision_cells"] * eff["vision"] * style.get("vision_pct", 100) / 100.0
    radius = a["radius_cells"] * eff["radius"] * style.get("radius_pct", 100) / 100.0
    rng = a["range_cells"] * eff["range"] * style.get("range_pct", 100) / 100.0
    weapons = [] if eff["remove_weapons"] else copy.deepcopy(a["weapons"])
    for w in weapons:
        w["damage"] = w["damage"] * eff["damage"] * style.get("damage_pct", 100) / 100.0
        w["reload_s"] = w["reload_s"] * eff["reload"] * style.get("reload_pct", 100) / 100.0
        w["range_cells"] = w["range_cells"] * eff["range"] * style.get("range_pct", 100) / 100.0
        if "ammo_volleys" in w:
            w["ammo_volleys"] = max(1, int(round(w["ammo_volleys"] * eff["ammo"])))
    arch_view = a
    if "drone_weapon" in a and eff["remove_weapons"]:
        arch_view = {k: v for k, v in a.items() if k != "drone_weapon"}
    dps = effective_dps(arch_view, weapons if not ("drone_weapon" in a) else [], eff["rearm"]) if (weapons or "drone_weapon" in a) else 0.0
    if "drone_weapon" in a and not eff["remove_weapons"]:
        dps *= eff["damage"] / eff["reload"]
    ex = a["power_exponents"]
    pi = (hp / a["health"]) ** ex["hp"]
    if a["dps_ref"] > 0:
        pi *= (dps / a["dps_ref"]) ** ex["dps"] if dps > 0 else 0.0
    if a["range_cells"] > 0 and rng > 0:
        pi *= (rng / a["range_cells"]) ** ex["range"]
    pi *= (speed / a["speed_cells_s"]) ** ex["speed"]
    pi *= (vision / a["vision_cells"]) ** ex["vision"]
    if a["dps_ref"] > 0 and dps == 0:   # deliberately unarmed variant of an armed archetype (e.g. no_gun): half price on the offensive share
        pi = (hp / a["health"]) ** ex["hp"] * (speed / a["speed_cells_s"]) ** ex["speed"] * (vision / a["vision_cells"]) ** ex["vision"] * 0.5
    ability_pct = sum(G["ability_value_pct"].get(x, 0) for x in abilities)
    cost = a["cost_credits"] * pi * (1 + ability_pct / 100.0)
    cost = round_to(cost, 5 if cost < 1000 else 25)
    rate = producer_rate(a["producer"], tier if a["producer"] == "factory" else a["tier"])
    build = max(1.0, round_to(cost / rate, 0.5))
    # power offset (docs FRAMEWORK 5.15): stats move, the price does not
    hp *= off_f
    dps *= off_f
    for w in weapons:
        w["damage"] = int(round(w["damage"] * off_f))
        w["reload_s"] = round(w["reload_s"], 2)
        w["range_cells"] = round(w["range_cells"], 2)
    move = "amphibious" if "amphibious" in abilities and a["movement_class"] in ("foot", "wheeled", "tracked") else a["movement_class"]
    extra = {}
    if a["family"] == "aircraft":
        extra["rearm_s_full"] = round(a["rearm_s_full"] * eff["rearm"], 2)
        extra["sortie_cycle_s"] = round(a["sortie_cycle_s"] - a["rearm_s_full"] + extra["rearm_s_full"], 2)
    return dict(extra, archetype=arch_id, tier=tier, health=int(round(hp)), speed_cells_s=round(speed, 2), vision_cells=round(vision, 1),
                radius_cells=round(radius, 2), range_cells=round(rng, 1), dps_vs_primary=round(dps, 1), cost_credits=int(cost),
                build_time_s=build, power_index=round(pi, 3), ability_value_pct=ability_pct, armor_class=a["armor_class"],
                movement_class=move, size_class=a["size_class"], layer=a["layer"], weapons=weapons, tags=list(tags),
                abilities=list(abilities))


def fair_cost_deviation(unit: dict) -> float:
    """unit: designer sheet with archetype + health/speed/vision/range/dps + cost. Returns cost/fair_cost - 1."""
    a = ARCH[unit["archetype"]]
    ex = a["power_exponents"]
    pi = (unit["health"] / a["health"]) ** ex["hp"]
    dps = unit.get("sortie_avg_dps_vs_primary", unit.get("dps_vs_primary", 0)) if a["family"] == "aircraft" else unit.get("dps_vs_primary", 0)
    if a["dps_ref"] > 0 and dps > 0:
        pi *= (dps / a["dps_ref"]) ** ex["dps"]
    if a["range_cells"] > 0 and unit.get("range_cells", 0) > 0:
        pi *= (unit["range_cells"] / a["range_cells"]) ** ex["range"]
    pi *= (unit["speed_cells_s"] / a["speed_cells_s"]) ** ex["speed"]
    pi *= (unit["vision_cells"] / a["vision_cells"]) ** ex["vision"]
    ab = sum(G["ability_value_pct"].get(x, 0) for x in unit.get("abilities", []))
    fair = a["cost_credits"] * pi * (1 + ab / 100.0)
    return unit["cost_credits"] / fair - 1.0


# ---------------------------------------------------------------------------------------------- engagement simulator
class Weapon:
    __slots__ = ("dtype", "dmg", "hits", "reload_s", "range", "min_range", "splash", "edge_pct", "proj_speed", "layers", "ramp_s", "ramp_max",
                 "deploy_s", "ammo", "homing", "scatter", "name")

    def __init__(self, wd: dict):
        a = WA[wd["archetype"]]
        self.name = wd["archetype"]
        self.dtype = a["damage_type"]
        self.dmg = float(wd["damage"])
        self.hits = int(wd.get("hits_per_volley", 1))
        self.reload_s = float(wd["reload_s"])
        self.range = float(wd["range_cells"])
        self.min_range = float(wd.get("min_range_cells", a.get("min_range_cells", 0.0)))
        self.splash = float(wd.get("splash_cells", a["splash_cells"]))
        self.edge_pct = float(wd.get("edge_pct", a["splash_edge_pct"]))
        self.proj_speed = float(a["projectile_speed_cells_s"])
        self.layers = tuple(wd.get("targets_override", a["targets"]))
        self.ramp_s = float(wd.get("ramp_seconds", 0.0))
        self.ramp_max = float(wd.get("ramp_max_pct", 100)) / 100.0
        self.deploy_s = float(wd.get("deploy_s", 0.0))
        self.ammo = int(wd.get("ammo_volleys", 0))
        self.homing = bool(a["homing"])
        self.scatter = float(wd.get("scatter_cells", a["scatter_cells"]))


class UType:
    def __init__(self, name, cost, hp, armor, speed, radius, layer, weapons, vision, rearm_s=0.0):
        self.name, self.cost, self.hp, self.armor = name, cost, hp, armor
        self.speed, self.radius, self.layer, self.weapons, self.vision, self.rearm_s = speed, radius, layer, weapons, vision, rearm_s


def utype_from_archetype(arch_id: str, **over) -> UType:
    a = ARCH[arch_id]
    ws = [Weapon(w) for w in a["weapons"] if w["archetype"] not in ("cruise_missile",)]
    if arch_id == "ship_carrier":
        ws = []
    layer = a["layer"]
    cyc = a.get("sortie_cycle_s", 0.0)
    u = UType(arch_id, a["cost_credits"], a["health"], a["armor_class"], a["speed_cells_s"], a["radius_cells"], layer, ws, a["vision_cells"], cyc)
    for k, v in over.items():
        setattr(u, k, v)
    return u


class Unit:
    __slots__ = ("t", "side", "x", "y", "hp", "cd", "alive", "focus", "ammo", "away", "id", "moving", "leaving", "target")

    def __init__(self, t: UType, side: int, x: float, y: float, uid: int):
        self.t, self.side, self.x, self.y, self.hp, self.id = t, side, x, y, float(t.hp), uid
        self.cd = [w.deploy_s for w in t.weapons]
        self.alive = True
        self.focus = [0.0] * len(t.weapons)
        self.ammo = [w.ammo for w in t.weapons]
        self.away = 0.0
        self.moving = False
        self.leaving = 0.0
        self.target = [None] * len(t.weapons)


def _formation(n, side, gap, cx, cy, width=8):
    pts = []
    for i in range(n):
        row, col = i // width, i % width
        cols = min(width, n - row * width)
        y = cy + (col - (cols - 1) / 2.0) * gap
        x = cx - row * gap * (1 if side == 0 else -1)
        pts.append((x, y))
    return pts


def run_fight(a_units, b_units, start_dist=24.0, max_s=150.0, stop_when_one_side_gone=True):
    """Expected-value engagement model at 20 TPS. a_units/b_units: [(UType, count)]. Deterministic (no RNG).

    Simplifications (documented in FRAMEWORK 5.6): flat 2-D plane, no fog, terrain or pathing; units advance on the nearest enemy they can hit and
    stop as soon as any weapon has a target; target choice = (matrix bucket desc, distance, id); direct fire always hits, ballistic fire lands on the
    fire-time position with an 8-sample scatter ring; no friendly fire, veterancy, repair or cover; aircraft leave for `sortie_cycle_s` after their
    ammo is spent (exposed for `leave_expose_s`); light separation keeps ground units from stacking."""
    units, uid = [], 0
    for side, lst in ((0, a_units), (1, b_units)):
        flat = []
        for t, n in lst:
            flat += [t] * n
        gap = max([t.radius * 2 for t in flat] + [1.0]) + 0.45 if flat else 1.0
        pts = _formation(len(flat), side, gap, -start_dist / 2 if side == 0 else start_dist / 2, 0.0)
        for t, (x, y) in zip(flat, pts):
            units.append(Unit(t, side, x, y, uid))
            uid += 1
    dt = 1.0 / TPS
    pending = []
    stats = {0: 0.0, 1: 0.0}
    t_end = 0.0
    for step in range(int(max_s * TPS)):
        t = step * dt
        t_end = t
        alive = [u for u in units if u.alive]
        s0 = [u for u in alive if u.side == 0]
        s1 = [u for u in alive if u.side == 1]
        if stop_when_one_side_gone and (not s0 or not s1):
            break
        enemies = {0: s1, 1: s0}
        still = []
        for imp in pending:
            it, side, w, ix, iy, tgt = imp
            if it > t + 1e-9:
                still.append(imp)
                continue
            if w.homing and tgt.alive:
                ix, iy = tgt.x, tgt.y
            victims = []
            if w.splash > 0:
                samples = [(ix, iy)]
                if w.scatter > 0:
                    samples = [(ix + w.scatter * math.cos(k * math.pi / 4), iy + w.scatter * math.sin(k * math.pi / 4)) for k in range(8)]
                accum = {}
                for sx, sy in samples:
                    for e in enemies[side]:
                        if not e.alive or e.t.layer not in w.layers:
                            continue
                        d = max(0.0, math.hypot(e.x - sx, e.y - sy) - e.t.radius)
                        if d <= w.splash:
                            fall = 100 - (100 - w.edge_pct) * d / w.splash
                            accum[e] = accum.get(e, 0.0) + fall / 100.0 / len(samples)
                victims = list(accum.items())
            elif tgt.alive and (w.homing or math.hypot(tgt.x - ix, tgt.y - iy) <= tgt.t.radius + 0.25):
                victims = [(tgt, 1.0)]
            for e, f in victims:
                p = pct(w.dtype, e.t.armor)
                dmg = w.dmg * w.hits * p / 100.0 * f
                if e.alive and dmg > 0:
                    e.hp -= dmg
                    stats[side] += dmg
                    if e.hp <= 0:
                        e.alive = False
        pending = still
        moves = []
        for u in alive:
            if not u.alive:
                continue
            if u.away > 0:
                u.away -= dt
                if u.away <= 0:
                    u.away = 0.0
                    u.ammo = [w.ammo for w in u.t.weapons]
                    u.x = (-start_dist / 2 - 4) if u.side == 0 else (start_dist / 2 + 4)
                continue
            engaged = False
            for wi, w in enumerate(u.t.weapons):
                if u.cd[wi] > 0:
                    u.cd[wi] -= dt
                cand, bestkey = None, None
                for e in enemies[u.side]:
                    if e.t.layer not in w.layers or not e.alive or e.away > 0:
                        continue
                    d = math.hypot(u.x - e.x, u.y - e.y)
                    if d > w.range + e.t.radius or d < w.min_range:
                        continue
                    p = pct(w.dtype, e.t.armor)
                    if p <= 0:
                        continue
                    key = (-(min(p, 100) // 10), d, e.id)
                    if bestkey is None or key < bestkey:
                        bestkey, cand = key, e
                if cand is not None:
                    if u.target[wi] is not cand:
                        u.focus[wi] = 0.0
                    u.target[wi] = cand
                    engaged = True
                    if u.cd[wi] <= 0 and not (w.ammo and u.ammo[wi] <= 0):
                        d = math.hypot(u.x - cand.x, u.y - cand.y)
                        flight = d / w.proj_speed if w.proj_speed > 0 else 0.0
                        w2 = w
                        if w.ramp_s > 0:
                            u.focus[wi] += w.reload_s
                            ramp = 1.0 + (w.ramp_max - 1.0) * min(1.0, u.focus[wi] / w.ramp_s)
                            w2 = copy.copy(w)
                            w2.dmg = w.dmg * ramp
                        pending.append((t + flight, u.side, w2, cand.x, cand.y, cand))
                        u.cd[wi] = w.reload_s
                        if w.ammo:
                            u.ammo[wi] -= 1
                else:
                    u.target[wi] = None
                    u.focus[wi] = 0.0
            if u.t.speed > 0:
                if u.t.layer == "air" and any(w.ammo for w in u.t.weapons) and all(u.ammo[i] <= 0 for i, w in enumerate(u.t.weapons) if w.ammo):
                    if u.leaving <= 0:
                        u.leaving = G["aircraft"]["leave_expose_s"]
                if u.leaving > 0:
                    u.leaving -= dt
                    moves.append((u, (-1.0 if u.side == 0 else 1.0) * u.t.speed * dt, 0.0))
                    u.moving = True
                    if u.leaving <= 0:
                        u.leaving = 0.0
                        u.away = u.t.rearm_s
                    continue
            u.moving = False
            if u.t.speed > 0 and not engaged:
                ne, nd = None, 1e9
                for e in enemies[u.side]:
                    if e.away > 0 or not any(e.t.layer in w.layers for w in u.t.weapons):
                        continue
                    d = math.hypot(u.x - e.x, u.y - e.y)
                    if d < nd:
                        nd, ne = d, e
                if ne is not None:
                    rng = max([w.range for w in u.t.weapons] or [0.0]) * 0.92
                    if nd > rng:
                        step_d = u.t.speed * dt
                        moves.append((u, (ne.x - u.x) / nd * step_d, (ne.y - u.y) / nd * step_d))
                        u.moving = True
        for u, mx, my in moves:
            u.x += mx
            u.y += my
        if moves:
            movers = [m[0] for m in moves if m[0].t.layer != "air"]
            same = {0: [u for u in s0 if u.t.layer != "air"], 1: [u for u in s1 if u.t.layer != "air"]}
            for u in movers:
                for v in same[u.side]:
                    if v is u or not v.alive:
                        continue
                    dx, dy = u.x - v.x, u.y - v.y
                    dd = math.hypot(dx, dy)
                    need = u.t.radius + v.t.radius + 0.1
                    if dd < need:
                        if dd < 1e-6:
                            dx, dy, dd = 1e-3, 0.0, 1e-3
                        push = min(0.08, (need - dd) * 0.5)
                        u.x += dx / dd * push
                        u.y += dy / dd * push
                        if v.t.speed > 0:
                            v.x -= dx / dd * push
                            v.y -= dy / dd * push
    res = {"t": t_end}
    alive = [u for u in units if u.alive]
    for side, lst in ((0, a_units), (1, b_units)):
        res[f"cost{side}"] = sum(tt.cost * n for tt, n in lst)
        res[f"rem{side}"] = sum(u.t.cost * (u.hp / u.t.hp) for u in alive if u.side == side)
        res[f"n{side}"] = sum(1 for u in alive if u.side == side)
        res[f"dmg{side}"] = stats[side]
    return res


def group_share(a: UType, b: UType, cost=6000, start=24.0, **kw):
    na, nb = max(1, round(cost / a.cost)), max(1, round(cost / b.cost))
    r = run_fight([(a, na)], [(b, nb)], start_dist=start, **kw)
    return r["rem0"] / r["cost0"] - r["rem1"] / r["cost1"], r, na, nb


# ---------------------------------------------------------------------------------------------- reference units for fights
def ref(name: str) -> UType:
    if name in ARCH:
        return utype_from_archetype(name)
    return structure_utype(name)


def structure_utype(name: str) -> UType:
    """Static structure as a fight participant: name or name@hp."""
    base, _, hp_s = name.partition("@")
    s = None
    if base in G["structures"]:
        s = G["structures"][base]
    elif base in G["defenses"]["advanced"]:
        s = copy.deepcopy(G["structures"]["advanced_defense"])
        s["health"] = G["defenses"]["advanced"][base]["health"]
        s["cost_credits"] = G["structures"]["advanced_defense"]["cost_credits"]
    elif base in ("building_heavy", "building_light", "fortress"):
        s = dict(cost_credits=0, health=int(hp_s or 4000), armor_class=base, radius_cells=1.5, vision_cells=8)
    else:
        raise KeyError(name)
    ws = []
    if base in G["defenses"]["shared"]:
        ws = [Weapon(w) for w in G["defenses"]["shared"][base]]
    if base in G["defenses"]["advanced"]:
        ws = [Weapon(G["defenses"]["advanced"][base]["weapon"])]
    hp = int(hp_s) if hp_s else s["health"]
    return UType(name, s["cost_credits"], hp, s["armor_class"], 0.0, s["radius_cells"], "ground", ws, s.get("vision_cells", 8))


# ---------------------------------------------------------------------------------------------- reports
def cmd_table(args=None) -> str:
    rows = []
    for tier in ("T1", "T2", "T3"):
        for role, r in G["tier_curves"][tier].items():
            dps = f"{r['dps_vs_primary']:.0f}"
            if "sortie_avg_dps_vs_primary" in r:
                dps = f"{r['dps_vs_primary']:.0f} burst / {r['sortie_avg_dps_vs_primary']:.0f} sortie"
            rows.append([tier, role, r["archetype"], r["cost_credits"], r["build_time_s"], r["health"], dps, r["range_cells"],
                         r["speed_cells_s"], r["vision_cells"], r["radius_cells"]])
    return md_table(["Tier", "Role", "Archetype", "Cost", "Build s", "HP", "DPS vs primary class", "Range", "Speed c/s", "Vision", "Radius"], rows,
                    ["l", "l", "l"] + ["r"] * 8)


def cmd_matrix(args=None) -> str:
    short = {"infantry": "inf", "light_vehicle": "lveh", "medium_armor": "med", "heavy_armor": "hvy", "air_light": "airL", "air_heavy": "airH",
             "ship_light": "shpL", "ship_heavy": "shpH", "building_light": "bldL", "building_heavy": "bldH", "fortress": "fort"}
    rows = [[d] + [G["damage_matrix"][d][a] for a in ARMORS] for d in DTYPES]
    return md_table(["type \\ armor"] + [short[a] for a in ARMORS], rows)


def cmd_ttk(args=None) -> str:
    atts = ["inf_line", "inf_at", "veh_scout", "mbt_t1", "mbt_t2", "veh_aa", "arty_howitzer", "arty_missile", "siege_ap", "siege_he", "siege_rail",
            "air_gunship", "air_fighter"]
    tgts = ["inf_line", "veh_scout", "mbt_t1", "mbt_t2", "siege_ap", "arty_howitzer", "air_fighter", "air_gunship", "building_heavy@4500", "fortress@6000"]
    rows = []
    for a in atts:
        row = [a]
        for t in tgts:
            if "@" in t:
                base, hp = t.split("@")
                tg = dict(health=int(hp), armor_class=base, layer="ground")
            else:
                ta = ARCH[t]
                tg = dict(health=ta["health"], armor_class=ta["armor_class"], layer=ta["layer"])
            v = ttk_unopposed(ARCH[a], tg)
            row.append("-" if v == float("inf") else f"{v:.1f}")
        rows.append(row)
    return md_table(["attacker \\ target (s)"] + [t.replace("building_heavy@4500", "Factory").replace("fortress@6000", "HQ") for t in tgts], rows)


def check_ttk() -> list[str]:
    fails = []
    for a, t, lo, hi in G["targets"]["ttk_unopposed_s"]:
        if "@" in t:
            base, hp = t.split("@")
            tg = dict(health=int(hp), armor_class=base, layer="ground")
        else:
            ta = ARCH[t]
            tg = dict(health=ta["health"], armor_class=ta["armor_class"], layer=ta["layer"])
        v = ttk_unopposed(ARCH[a], tg)
        if not (lo <= v <= hi):
            fails.append(f"TTK {a}->{t}: {v:.1f}s outside [{lo},{hi}]")
    return fails


def ttk_rows():
    rows = []
    for a, t, lo, hi in G["targets"]["ttk_unopposed_s"]:
        if "@" in t:
            base, hp = t.split("@")
            tg = dict(health=int(hp), armor_class=base, layer="ground")
        else:
            ta = ARCH[t]
            tg = dict(health=ta["health"], armor_class=ta["armor_class"], layer=ta["layer"])
        v = ttk_unopposed(ARCH[a], tg)
        rows.append([a, t.replace("building_heavy@4500", "Factory (4500)"), f"{v:.1f}", f"{lo}-{hi}", "ok" if lo <= v <= hi else "FAIL"])
    return rows


def duel_ttk(a_id: str, b_id: str) -> tuple[float, float]:
    """Discrete 1v1 from a start distance inside both ranges; returns (time, winner_side)."""
    a, b = ref(a_id), ref(b_id)
    rng = min(max([w.range for w in a.weapons] or [3.0]), max([w.range for w in b.weapons] or [3.0]))
    r = run_fight([(a, 1)], [(b, 1)], start_dist=max(2.0, rng * 0.95), max_s=200.0)
    return r["t"], (0 if r["n0"] and not r["n1"] else 1 if r["n1"] and not r["n0"] else -1)


def rps_matrix(names, cost=6000, start=24.0):
    us = {n: ref(n) for n in names}
    grid = {}
    for a in names:
        for b in names:
            if (b, a) in grid:
                grid[(a, b)] = -grid[(b, a)]
            elif a == b:
                grid[(a, b)] = 0.0
            else:
                grid[(a, b)] = group_share(us[a], us[b], cost, start)[0]
    return grid


def cmd_rps(args=None) -> str:
    names = ["inf_line", "inf_at", "veh_scout", "mbt_t1", "mbt_t2", "arty_howitzer", "arty_missile", "siege_ap", "siege_he"]
    grid = rps_matrix(names, G["targets"]["rps_equal_cost"]["cost_per_side"], G["targets"]["rps_equal_cost"]["start_distance_cells"])
    rows = [[a] + [f"{grid[(a, b)]:+.2f}" for b in names] for a in names]
    return md_table(["row beats col"] + [n for n in names], rows)


def check_rps() -> list[str]:
    fails = []
    cfg = G["targets"]["rps_equal_cost"]
    for a, b, lo, hi, why in cfg["bands"]:
        d = group_share(ref(a), ref(b), cfg["cost_per_side"], cfg["start_distance_cells"])[0]
        if not (lo <= d <= hi):
            fails.append(f"RPS {a} vs {b}: {d:+.2f} outside [{lo},{hi}] ({why})")
    return fails


def rps_band_rows():
    cfg = G["targets"]["rps_equal_cost"]
    rows = []
    for a, b, lo, hi, why in cfg["bands"]:
        d = group_share(ref(a), ref(b), cfg["cost_per_side"], cfg["start_distance_cells"])[0]
        rows.append([a, b, f"{d:+.2f}", f"{lo:+.2f}..{hi:+.2f}", "ok" if lo <= d <= hi else "FAIL", why])
    return rows


# ---- sorties
def sortie_row(air_id: str, n_air: int, aa_share: float, ground_cost=6000, window=22.0):
    air = ref(air_id)
    tank, aa = ref("mbt_t1"), ref("veh_aa")
    k = round(ground_cost * aa_share / aa.cost)
    nt = round((ground_cost - k * aa.cost) / tank.cost)
    g = [(tank, nt)] + ([(aa, k)] if k else [])
    r = run_fight([(air, n_air)], g, start_dist=24.0, max_s=window)
    gv = nt * tank.cost + k * aa.cost
    destroyed = gv - r["rem1"]
    lost = n_air * air.cost - r["rem0"]
    return dict(destroyed=destroyed, air_lost=lost, value_ratio=destroyed / (n_air * air.cost), air_loss_share=lost / (n_air * air.cost),
                air_survivors=r["n0"], k=k, tanks=nt)


def cmd_sorties(args=None) -> str:
    cfg = G["targets"]["sortie"]
    rows = []
    for name, n in cfg["air_group"].items():
        aid = {"gunship": "air_gunship", "bomber": "air_bomber", "strike_drone": "air_drone"}[name]
        for share in (0.0, 0.15, 0.30, 0.45):
            r = sortie_row(aid, n, share, cfg["ground_cost"], cfg["window_s"])
            rows.append([f"{aid} x{n}", f"{int(share * 100)}%", r["k"], r["tanks"], f"{r['destroyed']:.0f}", f"{r['air_lost']:.0f}",
                         f"{r['value_ratio']:.2f}", f"{r['air_loss_share']:.2f}", f"{r['air_survivors']}/{n}"])
    return md_table(["air group", "AA share", "AA", "tanks", "ground value destroyed", "air value lost", "destroyed/air cost", "air loss share", "alive"], rows)


def check_sorties() -> list[str]:
    fails = []
    cfg = G["targets"]["sortie"]
    for name, n in cfg["air_group"].items():
        aid = {"gunship": "air_gunship", "bomber": "air_bomber", "strike_drone": "air_drone"}[name]
        lo, hi = cfg["value_ratio_no_aa"][name]
        r = sortie_row(aid, n, 0.0, cfg["ground_cost"], cfg["window_s"])
        if not (lo <= r["value_ratio"] <= hi):
            fails.append(f"sortie {name} no-AA value ratio {r['value_ratio']:.2f} outside [{lo},{hi}]")
        for key, share in (("pct15", 0.15), ("pct30", 0.30)):
            lo2, hi2 = cfg["air_loss_share_at_aa_share"][key]
            r2 = sortie_row(aid, n, share, cfg["ground_cost"], cfg["window_s"])
            if not (lo2 <= r2["air_loss_share"] <= hi2):
                fails.append(f"sortie {name} air loss share at AA {key} = {r2['air_loss_share']:.2f} outside [{lo2},{hi2}]")
    return fails


# ---- defenses / structures
def break_cost_ratio(defense_names, attacker_id, start=26.0, max_s=240.0):
    """Attacker cost / defense cost at the break-even army size (linear interpolation of the remaining-share margin between the
    largest losing and smallest winning integer army). Returns (ratio, smallest_winning_n)."""
    d_units, dcost = [], 0
    for nm, c in defense_names:
        u = ref(nm)
        d_units.append((u, c))
        dcost += u.cost * c
    att = ref(attacker_id)
    prev = None
    for n in range(1, 40):
        r = run_fight([(att, n)], d_units, start_dist=start, max_s=max_s)
        margin = r["rem0"] / r["cost0"] - r["rem1"] / r["cost1"]
        if r["n0"] > 0 and r["n1"] == 0:
            if prev is None:
                return n * att.cost / dcost, n
            n_star = (n - 1) + (-prev) / (margin - prev)
            return n_star * att.cost / dcost, n
        prev = margin
    return float("inf"), 0


def cmd_defenses(args=None) -> str:
    rows = []
    pair = [("anti_tank_turret", 1), ("watchtower", 1)]
    ratio, n = break_cost_ratio(pair, "mbt_t1")
    rows.append(["anti_tank_turret + watchtower (1250)", "mbt_t1", n, f"{ratio:.2f}"])
    ratio2, n2 = break_cost_ratio([("anti_tank_turret", 2), ("watchtower", 2)], "mbt_t1")
    rows.append(["2 x (turret + tower) (2500)", "mbt_t1", n2, f"{ratio2:.2f}"])
    for nm, d in G["defenses"]["advanced"].items():
        ratio3, n3 = break_cost_ratio([(nm, 1)], "mbt_t2")
        rows.append([f"{nm} (1800)", "mbt_t2", n3, f"{ratio3:.2f}"])
    for nm in ("anti_tank_turret", "bulwark_cannon"):
        pass
    how = ref("arty_howitzer")
    r = run_fight([(how, 2)], [(ref("anti_tank_turret"), 1), (ref("watchtower"), 1)], start_dist=26, max_s=120)
    rows.append(["turret + tower (1250)", "2 x arty_howitzer (2600)", "-", f"howitzers alive {r['n0']}/2 in {r['t']:.0f}s"])
    return md_table(["defense", "attacker", "attackers needed", "attacker cost / defense cost"], rows, ["l", "l", "r", "r"])


def check_defenses() -> list[str]:
    fails = []
    cfg = G["targets"]["defenses"]
    ratio, _ = break_cost_ratio([("anti_tank_turret", 1), ("watchtower", 1)], "mbt_t1")
    lo, hi = cfg["shared_pair_break_ratio"]
    if not (lo <= ratio <= hi):
        fails.append(f"shared defense pair break ratio {ratio:.2f} outside [{lo},{hi}]")
    vals = []
    lo, hi = cfg["advanced_break_ratio_each"]
    for nm in G["defenses"]["advanced"]:
        r2, _ = break_cost_ratio([(nm, 1)], "mbt_t2")
        vals.append(r2)
        if not (lo <= r2 <= hi):
            fails.append(f"advanced defense {nm} break ratio {r2:.2f} outside [{lo},{hi}]")
    mlo, mhi = cfg["advanced_break_ratio_mean"]
    mean = sum(vals) / len(vals)
    if not (mlo <= mean <= mhi):
        fails.append(f"advanced defenses mean break ratio {mean:.2f} outside [{mlo},{mhi}]")
    how = ref("arty_howitzer")
    r = run_fight([(how, 2)], [(ref("anti_tank_turret"), 1), (ref("watchtower"), 1)], start_dist=26, max_s=120)
    if r["n0"] < 2:
        fails.append("2 howitzers must destroy turret+tower without loss (outrange)")
    return fails


def cmd_structures(args=None) -> str:
    rows = []
    fac = "building_heavy@4500"
    for att, cnt in (("mbt_t1", 4), ("mbt_t1", 8), ("mbt_t1", 12), ("mbt_t2", 6), ("siege_he", 4), ("arty_howitzer", 4), ("arty_missile", 4), ("inf_line", 12), ("air_bomber", 2)):
        a = ref(att)
        target = ref(fac)
        r = run_fight([(a, cnt)], [(target, 1)], start_dist=max([w.range for w in a.weapons] or [3.0]) + 1.0, max_s=400)
        rows.append([f"{cnt} x {att}", cnt * a.cost, f"{r['t']:.1f}" if r["n1"] == 0 else ">400"])
    return md_table(["attackers", "cost", "seconds to kill a 4500-HP Factory"], rows, ["l", "r", "r"])


def check_structures() -> list[str]:
    fails = []
    lo, hi = G["targets"]["structure_kill"]["equal_cost_army_seconds"]
    fac = G["structures"]["factory"]
    a = ref("mbt_t1")
    n = max(1, round(fac["cost_credits"] / a.cost))
    r = run_fight([(a, n)], [(ref(f"building_heavy@{fac['health']}"), 1)], start_dist=8, max_s=400)
    t = r["t"] * (n * a.cost) / fac["cost_credits"]      # scale to an army of exactly the building's cost
    if not (lo <= t <= hi):
        fails.append(f"equal-cost T1 army kills a Factory in {t:.1f}s outside [{lo},{hi}]")
    return fails


# ---- superweapons / support powers -------------------------------------------------------------------------
def _T(name, x, y, r, hp, armor, cost):
    return dict(name=name, x=x, y=y, r=r, hp=hp, armor=armor, cost=cost)


def ref_base(gap=1.0):
    st = G["structures"]
    spec = [("HQ", "headquarters", 3000), ("Factory", "factory", 2000), ("Factory2", "factory", 2000), ("Refinery", "refinery", 1800), ("Radar", "radar", 1500),
            ("Lab", "laboratory", 2500), ("Airfield", "airfield", 1600), ("Barracks", "barracks", 500), ("Gen1", "generator", 600), ("Gen2", "generator", 600),
            ("Gen3", "generator", 600), ("SW", "superweapon", 5000)]
    pitch = 4 + gap + 1
    out, k = [], 0
    for i in range(4):
        for j in range(3):
            n, key, cost = spec[k]
            k += 1
            s = st[key]
            out.append(_T(n, i * pitch, j * pitch, s["radius_cells"], s["health"], s["armor_class"], cost))
    return out


def ref_blob(kind: str, n: int, gap=1.5, cols=4):
    a = ARCH[kind]
    rows = (n + cols - 1) // cols
    out = []
    for i in range(n):
        c, r = i % cols, i // cols
        out.append(_T(f"{kind}{i}", (c - (cols - 1) / 2) * gap, (r - (rows - 1) / 2) * gap, a["radius_cells"], a["health"], a["armor_class"], a["cost_credits"]))
    return out


def packet_damage(pk, tg) -> float:
    d = max(0.0, math.hypot(tg["x"] - pk["x"], tg["y"] - pk["y"]) - tg["r"])
    if d > pk["r"]:
        return 0.0
    fall = 100 - (100 - pk["edge_pct"]) * d / pk["r"]
    return pk["dmg"] * pct(pk["dtype"], tg["armor"]) / 100.0 * fall / 100.0


def helios_damage(tg, cx, cy, ang, sw) -> float:
    L, Wd, dur, dps = sw["line_length_cells"], sw["line_width_cells"], sw["traverse_s"], sw["dps"]
    v = L / dur
    ux, uy = math.cos(ang), math.sin(ang)
    dx, dy = tg["x"] - cx, tg["y"] - cy
    along, across = dx * ux + dy * uy, -dx * uy + dy * ux
    rr = Wd / 2 + tg["r"]
    if abs(across) >= rr or abs(along) > L / 2 + rr:
        return 0.0
    chord = 2 * math.sqrt(rr * rr - across * across)
    lo, hi = max(-L / 2, along - chord / 2), min(L / 2, along + chord / 2)
    exp = max(0.0, hi - lo) / v
    return dps * exp * pct("thermal", tg["armor"]) / 100.0


def sw_packets(name, cx, cy, ang):
    sw = G["superweapons"][name]
    out = []
    if name == "atlas":
        for p in sw["packets"]:
            out.append(dict(x=cx + p["offset_cells"] * math.cos(ang), y=cy + p["offset_cells"] * math.sin(ang), r=p["radius_cells"], dmg=p["damage"], dtype=p["damage_type"], edge_pct=p["edge_pct"]))
    elif name == "perun":
        for p in sw["packets"]:
            out.append(dict(x=cx, y=cy, r=p["radius_cells"], dmg=p["damage"], dtype=p["damage_type"], edge_pct=p["edge_pct"]))
    elif name == "horizon":
        for p in sw["packets"]:
            out.append(dict(x=cx + p["offset_cells"] * math.cos(ang), y=cy + p["offset_cells"] * math.sin(ang), r=p["radius_cells"], dmg=p["damage"], dtype=p["damage_type"], edge_pct=p["edge_pct"]))
    return out


def sw_evaluate(name, targets, cx, cy, ang):
    sw = G["superweapons"][name]
    dmg = [0.0] * len(targets)
    if name == "helios":
        for i, t in enumerate(targets):
            dmg[i] = helios_damage(t, cx, cy, ang, sw)
    else:
        for pk in sw_packets(name, cx, cy, ang):
            for i, t in enumerate(targets):
                dmg[i] += packet_damage(pk, t)
    value, kills = 0.0, 0
    for d, t in zip(dmg, targets):
        frac = min(1.0, d / t["hp"])
        if t["armor"] in ("building_light", "building_heavy", "fortress"):
            frac = 1.0 if d >= t["hp"] else 0.25 * frac   # partial building damage is repairable (Engineers)
        value += t["cost"] * frac
        kills += 1 if d >= t["hp"] else 0
    return value, kills, dmg


def sw_best(name, targets, step=1.0):
    xs = [t["x"] for t in targets]
    ys = [t["y"] for t in targets]
    best = (-1.0, 0, None)
    x0, x1, y0, y1 = min(xs) - 3, max(xs) + 3, min(ys) - 3, max(ys) + 3
    angs = [0.0, math.pi / 4, math.pi / 2, 3 * math.pi / 4] if name in ("atlas", "helios", "horizon") else [0.0]
    x = x0
    while x <= x1:
        y = y0
        while y <= y1:
            for a in angs:
                v, k, _ = sw_evaluate(name, targets, x, y, a)
                if v > best[0]:
                    best = (v, k, (x, y, a))
            y += step
        x += step
    return best


def swarm_value(n_aa: int, n_tank=8, hp=None, dur=None):
    sw = G["superweapons"]["tempest"]
    dw = Weapon(sw["drone_weapon"])
    drone = UType("drone", 0, hp or sw["drone_health"], sw["drone_armor_class"], sw["drone_speed_cells_s"], 0.3, "air", [dw], 8)
    tank, aa = ref("mbt_t1"), ref("veh_aa")
    g = [(tank, n_tank)] + ([(aa, n_aa)] if n_aa else [])
    r = run_fight([(drone, sw["drone_count"])], g, start_dist=12, max_s=dur or sw["attack_window_s"], stop_when_one_side_gone=True)
    gcost = n_tank * tank.cost + n_aa * aa.cost
    return (gcost - r["rem1"]) / gcost, r["n0"]


def dragonfall_value(defenders: dict):
    sw = G["superweapons"]["dragonfall"]
    eng = UType("engine", 0, sw["engine_health"], sw["engine_armor_class"], sw["engine_speed_cells_s"], 0.8, "ground", [Weapon(sw["engine_weapon"])], 8)
    d_units = []
    for nm, c in defenders.items():
        d_units.append((ref(nm), c))
    r = run_fight([(eng, sw["capsule_count"])], d_units, start_dist=9, max_s=sw["engine_lifetime_s"], stop_when_one_side_gone=True)
    dcost = sum(u.cost * c for u, c in d_units)
    return (dcost - r["rem1"]) / dcost, r["n0"], r["t"]


def cmd_sw(args=None) -> str:
    out = []
    base = ref_base()
    scen = [("tight base (12 bldgs, 1-cell gaps)", base), ("dispersed base (4-cell gaps)", ref_base(4.0)), ("12 T1 tanks blob", ref_blob("mbt_t1", 12)),
            ("6 T3 heavies blob", ref_blob("siege_ap", 6, gap=1.9, cols=3)), ("20 rifle squads blob", ref_blob("inf_line", 20, gap=1.2, cols=5))]
    rows = []
    for name in ("atlas", "perun", "helios", "horizon"):
        row = [name]
        for sn, tg in scen:
            v, k, at = sw_best(name, tg)
            row.append(f"{v:.0f} ({k})")
        rows.append(row)
    out.append(md_table(["superweapon (best aim)"] + [s[0] + " credit value (kills)" for s in scen], rows))
    # aurora and others are not damage-based
    rows = []
    for n_aa in (0, 1, 2, 4, 6):
        f, alive = swarm_value(n_aa)
        rows.append([f"Tempest vs 8 tanks + {n_aa} AA", f"{f * 100:.0f}%", alive])
    out.append(md_table(["Tempest 24 drones, 20 s", "ground value destroyed", "drones alive"], rows, ["l", "r", "r"]))
    rows = []
    for label, d in (("8 tanks", {"mbt_t1": 8}), ("4 tanks + 4 AT infantry", {"mbt_t1": 4, "inf_at": 4}), ("2 AT turrets + 6 tanks", {"anti_tank_turret": 2, "mbt_t1": 6}),
                     ("undefended base (Factory, Refinery, Barracks, 2 Generators)", {"factory": 1, "refinery": 1, "barracks": 1, "generator": 2})):
        f, alive, t = dragonfall_value(d)
        rows.append([f"Dragonfall vs {label}", f"{f * 100:.0f}%", alive, f"{t:.0f}s"])
    out.append(md_table(["Dragonfall 3 engines", "defender value destroyed", "engines alive", "duration"], rows, ["l", "r", "r", "r"]))
    return "\n\n".join(out)


def check_sw() -> list[str]:
    fails = []
    cfg = G["targets"]["superweapon"]
    lo, hi = cfg["tight_base_value_credits"]
    base = ref_base()
    blob12 = ref_blob("mbt_t1", 12)
    heav = ref_blob("siege_ap", 6, gap=1.9, cols=3)
    v12 = sum(t["cost"] for t in blob12)
    vh = sum(t["cost"] for t in heav)
    for name in ("atlas", "perun", "helios", "horizon"):
        v, k, _ = sw_best(name, base)
        if not (lo <= v <= hi) or k < cfg["tight_base_kills_min"]:
            fails.append(f"superweapon {name} on tight base: value {v:.0f}, kills {k} (want value in [{lo},{hi}], kills >= {cfg['tight_base_kills_min']})")
        vb = sw_best(name, blob12)[0]
        if vb < v12 * cfg["blob12_tanks_value_min_pct"] / 100.0:
            fails.append(f"superweapon {name} on 12-tank blob: {vb:.0f} < {cfg['blob12_tanks_value_min_pct']}% of {v12}")
    vhv = sw_best("atlas", heav)[0]
    if vhv < vh * cfg["heavies_blob_value_min_pct"] / 100.0:
        fails.append(f"Atlas on 6 heavies: {vhv:.0f} < {cfg['heavies_blob_value_min_pct']}% of {vh}")
    f0, _ = swarm_value(0)
    f4, _ = swarm_value(4)
    if not (f0 * 100 >= cfg["tempest_unanswered_min_pct"] and f4 * 100 <= cfg["tempest_4aa_max_pct"]):
        fails.append(f"Tempest: unanswered {f0 * 100:.0f}% (>= {cfg['tempest_unanswered_min_pct']}) / 4 AA {f4 * 100:.0f}% (<= {cfg['tempest_4aa_max_pct']}) violated")
    fb, alive, _ = dragonfall_value({"factory": 1, "refinery": 1, "barracks": 1, "generator": 2})
    if fb * 100 < cfg["dragonfall_undefended_base_min_pct"]:
        fails.append(f"Dragonfall vs undefended base {fb * 100:.0f}% < {cfg['dragonfall_undefended_base_min_pct']}%")
    f8, alive8, _ = dragonfall_value({"mbt_t1": 8})
    if f8 * 100 > cfg["dragonfall_vs_8_tanks_max_pct"] or alive8 > 0:
        fails.append(f"Dragonfall vs 8 tanks: {f8 * 100:.0f}% destroyed (max {cfg['dragonfall_vs_8_tanks_max_pct']}) engines alive {alive8} (want 0)")
    return fails


# ---- economy / power / pacing ------------------------------------------------------------------------------------
def collector_cycle(d_cells: float) -> tuple[float, float]:
    c = G["economy"]["collector"]
    harvest = c["capacity_credits"] / (c["harvest_credits_per_pulse"] * TPS / c["harvest_pulse_ticks"])
    unload = c["capacity_credits"] / (c["unload_credits_per_pulse"] * TPS)
    trip = 2 * d_cells / c["speed_cells_s"]
    cyc = harvest + unload + c["unload_overhead_ticks"] / TPS + trip
    return cyc, c["capacity_credits"] / cyc * 60


def cmd_econ(args=None) -> str:
    rows = []
    for d in (6, 8, 10, 12, 16, 20, 24, 32):
        cyc, inc = collector_cycle(d)
        rows.append([d, f"{cyc:.1f}", f"{inc:.0f}"])
    t1 = md_table(["deposit-refinery distance (cells)", "cycle s", "credits/min per collector"], rows)
    e = G["economy"]
    ref_inc = collector_cycle(e["derived"]["reference_distance_cells"])[1]
    rows = [
        ["Collector purchase payback", f"{1400 / ref_inc:.1f} min"],
        ["Refinery + free collector payback", f"{1800 / ref_inc:.1f} min"],
        ["Expansion total (MCV+refinery+2 collectors+gen+turret+tower)", f"{e['expansion']['total_credits']} cr -> {3 * ref_inc:.0f} cr/min, payback {e['expansion']['total_credits'] / (3 * ref_inc):.1f} min"],
        ["Standard field (24 cells x 600)", f"{e['deposit']['standard_field_credits']} cr, {e['deposit']['standard_field_credits'] / (3 * ref_inc):.1f} min for 3 collectors"],
        ["Full repair of any land vehicle", "50 % of paid price, 100 s"],
        ["Salvage of a 850-credit tank wreck", f"{850 * e['salvage']['payout_pct_of_paid_cost'] // 100} cr for {e['salvage']['action_s']} s"],
    ]
    t2 = md_table(["quantity", "value"], rows, ["l", "l"])
    return t1 + "\n\n" + t2


def check_econ() -> list[str]:
    fails = []
    e = G["economy"]
    t = G["targets"]["economy"]
    ref_inc = collector_cycle(e["derived"]["reference_distance_cells"])[1]
    if abs(ref_inc - e["derived"]["reference_income_cr_per_min_per_collector"]) > 4:
        fails.append(f"reference income {ref_inc:.0f} != stored {e['derived']['reference_income_cr_per_min_per_collector']}")
    pay = e["collector"]["cost_credits"] / ref_inc
    if not (t["collector_payback_min"][0] <= pay <= t["collector_payback_min"][1]):
        fails.append(f"collector payback {pay:.2f} min outside {t['collector_payback_min']}")
    if e["refinery"]["cost_credits"] / ref_inc > t["refinery_payback_max_min"]:
        fails.append("refinery (with its free collector) payback above the limit")
    ex = e["expansion"]["total_credits"] / (3 * ref_inc)
    if not (t["expansion_payback_min"][0] <= ex <= t["expansion_payback_min"][1]):
        fails.append(f"expansion payback {ex:.2f} min outside {t['expansion_payback_min']}")
    field = e["deposit"]["standard_field_credits"] / (3 * ref_inc)
    if not (t["standard_field_minutes_3_collectors"][0] <= field <= t["standard_field_minutes_3_collectors"][1]):
        fails.append(f"standard field lasts {field:.1f} min for 3 collectors, outside {t['standard_field_minutes_3_collectors']}")
    c = e["collector"]
    if c["capacity_credits"] % c["unload_credits_per_pulse"] != 0 or c["capacity_credits"] % c["harvest_credits_per_pulse"] != 0:
        fails.append("collector capacity must be a multiple of the harvest and unload pulses (integer ticks)")
    exp_total = sum(e["expansion"]["components"].values())
    if exp_total != e["expansion"]["total_credits"]:
        fails.append(f"expansion components sum {exp_total} != {e['expansion']['total_credits']}")
    return fails


def cmd_power(args=None) -> str:
    p = G["power"]
    rows = []
    for k, s in p["sets"].items():
        rows.append([k, ", ".join(s["structures"]), s["draw"], s["generators"], s["generators"] * p["generator_output"], s["generators"] * p["generator_cost"]])
    return md_table(["set", "structures", "draw", "generators", "supply", "generator cost"], rows, ["l", "l", "r", "r", "r", "r"])


def power_draw(names: list) -> int:
    cons = G["power"]["consumption"]
    alias = {"at_turret": "anti_tank_turret", "defenses": "defense_avg"}
    tot = 0
    for n in names:
        cnt = 1
        if " x" in n:
            n, c = n.split(" x")
            cnt = int(c)
        tot += cons[alias.get(n, n)] * cnt
    return tot


def check_power() -> list[str]:
    fails = []
    p = G["power"]
    for k, s in p["sets"].items():
        d = power_draw(s["structures"])
        if d != s["draw"]:
            fails.append(f"power set {k}: stored draw {s['draw']} != computed {d}")
        need = math.ceil(d * (100 + p["headroom_pct"]) / 100.0 / p["generator_output"])
        if s["generators"] != need:
            fails.append(f"power set {k}: generators {s['generators']} != {need} for draw {d} with {p['headroom_pct']}% headroom")
        if s["generators"] * p["generator_output"] < d:
            fails.append(f"power set {k}: supply below draw")
    return fails


def simulate_plan(build_order, train, T=1500, d_cells=12.0, start_credits=None):
    """Coarse timeline model (1 s steps, proportional credit sharing = every active queue pulls credits at once, pausing at 0 credits).
    build_order: [(structure, not_before_s)] serial construction queue.
    train: [(not_before_s, unit)] with unit in rifle/at/scout/tank/aa/howitzer/heavy/gunship/collector/mcv."""
    st = G["structures"]
    cred = float(start_credits if start_credits is not None else G["economy"]["start_credits"])
    have = {"headquarters": 1}
    UN = {"rifle": ("inf_line", "barracks", ["barracks"]), "at": ("inf_at", "barracks", ["barracks"]),
          "scout": ("veh_scout", "factory", ["factory"]), "tank": ("mbt_t1", "factory", ["factory"]),
          "aa": ("veh_aa", "factory", ["factory", "radar"]), "howitzer": ("arty_howitzer", "factory", ["factory", "radar"]),
          "heavy": ("siege_ap", "factory", ["factory", "radar", "laboratory"]), "gunship": ("air_gunship", "airfield", ["airfield", "radar", "laboratory"]),
          "fighter": ("air_fighter", "airfield", ["airfield", "radar"]),
          "collector": (None, "refinery", ["refinery"]), "mcv": (None, "factory", ["factory"])}
    SP = {"generator": [], "refinery": ["generator"], "barracks": ["generator"], "factory": ["refinery"], "radar": ["factory"], "airfield": ["radar"],
          "laboratory": ["radar"], "anti_tank_turret": ["factory"], "aa_battery": ["radar"], "watchtower": ["barracks"], "superweapon": ["radar", "laboratory"],
          "dock": ["refinery"]}
    per_coll = collector_cycle(d_cells)[1] / 60.0
    con = None
    bq = list(build_order)
    queues = {"barracks": None, "factory": None, "airfield": None, "refinery": None}
    waiting = {"barracks": [], "factory": [], "airfield": [], "refinery": []}
    pend = sorted(train)
    coll_start = []
    refin = 0
    ms = {}
    counts = {}
    income_total = 0.0
    for t in range(T):
        while pend and pend[0][0] <= t:
            _, u = pend.pop(0)
            waiting[UN[u][1]].append(u)
        supply = sum(st[n]["power_delta"] * c for n, c in have.items() if n in st and st[n]["power_delta"] > 0)
        use = -sum(st[n]["power_delta"] * c for n, c in have.items() if n in st and st[n]["power_delta"] < 0)
        mult = 1.0 if supply >= use else G["production"]["power_shortage_speed_pct"] / 100.0
        if con is None and bq:
            nxt, nb = bq[0]
            if t >= nb and all(have.get(p, 0) > 0 for p in SP[nxt]):
                con = [nxt, 0.0]
                bq.pop(0)
        consumers = []
        if con is not None:
            cost, bt = st[con[0]]["cost_credits"], st[con[0]]["build_time_s"]
            consumers.append(("con", con, cost, bt))
        for prod, q in waiting.items():
            cur = queues[prod]
            if cur is None and q and have.get(prod, 0) > 0:
                u = q[0]
                if all(have.get(p, 0) > 0 for p in UN[u][2]):
                    cur = [u, 0.0]
                    queues[prod] = cur
                    q.pop(0)
            if cur is not None and have.get(prod, 0) > 0:
                nm = cur[0]
                if nm == "collector":
                    cost, bt = 1400, G["service_units"]["collector"]["build_time_s"]
                elif nm == "mcv":
                    cost, bt = 3000, G["service_units"]["mcv"]["build_time_s"]
                else:
                    a = ARCH[UN[nm][0]]
                    cost, bt = a["cost_credits"], a["build_time_s"]
                consumers.append((prod, cur, cost, bt))
        demand = sum(c[2] / c[3] * mult for c in consumers)
        share = 1.0 if demand <= cred or demand == 0 else cred / demand
        for kind, item, cost, bt in consumers:
            step = mult / bt * share
            cred -= cost * step
            item[1] += step
            if item[1] >= 1.0 - 1e-9:
                name = item[0]
                if kind == "con":
                    have[name] = have.get(name, 0) + 1
                    ms.setdefault(name, t)
                    if name == "refinery":
                        refin += 1
                        coll_start.append(t + 12)
                    con = None
                else:
                    counts[name] = counts.get(name, 0) + 1
                    ms.setdefault("first_" + name, t)
                    if name == "collector":
                        coll_start.append(t + 8)
                    queues[kind] = None
        cred = max(cred, 0.0)
        active = sum(1 for x in coll_start if x <= t)
        eff = min(active, 3 * max(refin, 1)) + 0.6 * max(0, active - 3 * max(refin, 1))
        inc = eff * per_coll
        cred += inc
        income_total += inc
    ms["income_total"] = income_total
    ms["credits_end"] = cred
    ms["counts"] = counts
    return ms


def plans() -> dict:
    return {k: dict(build=[tuple(x) for x in v["build"]], train=[tuple(x) for x in v["train"]]) for k, v in G["targets"]["pacing"]["plans"].items()}


def pacing_results():
    res = {}
    for name, p in plans().items():
        ms = simulate_plan(p["build"], p["train"], T=1500)
        res[name] = ms
    return res


def cmd_pacing(args=None) -> str:
    res = pacing_results()
    keys = [("first_rifle", "first infantry squad"), ("first_scout", "first scout (T1 APC)"), ("first_tank", "first T1 tank"), ("radar", "Radar complete (T2)"),
            ("first_aa", "first mobile AA"), ("first_howitzer", "first siege (artillery)"), ("laboratory", "Laboratory complete (T3)"),
            ("first_heavy", "first T3 heavy tank"), ("first_fighter", "first fighter (T2 air)"), ("airfield", "Airfield complete"), ("superweapon", "superweapon structure complete")]
    rows = []
    for k, label in keys:
        row = [label]
        for name in plans():
            v = res[name].get(k)
            row.append(fmt_t(v) if v is not None else "-")
        rows.append(row)
    sw_row = ["first superweapon shot (structure + 480 s recharge)"]
    for name in plans():
        v = res[name].get("superweapon")
        sw_row.append(fmt_t(v + G["superweapons"]["atlas"]["recharge_s"]) if v is not None else "-")
    rows.append(sw_row)
    return md_table(["milestone"] + list(plans()), rows, ["l"] + ["r"] * len(plans()))


def check_pacing() -> list[str]:
    """windows_s[key] = [physical lower bound, fastest-plan max, balanced-plan max]."""
    fails = []
    res = pacing_results()
    tgt = G["targets"]["pacing"]
    for key, (lo, fast_max, bal_max) in tgt["windows_s"].items():
        vals = [res[n].get(key) for n in plans() if res[n].get(key) is not None]
        if not vals:
            fails.append(f"pacing {key}: never reached by any plan")
            continue
        if min(vals) < lo:
            fails.append(f"pacing {key}: fastest plan {fmt_t(min(vals))} beats the physical lower bound {fmt_t(lo)}")
        if min(vals) > fast_max:
            fails.append(f"pacing {key}: fastest plan {fmt_t(min(vals))} slower than {fmt_t(fast_max)}")
        b = res["balanced"].get(key)
        if b is not None and b > bal_max:
            fails.append(f"pacing balanced: {key} at {fmt_t(b)} slower than {fmt_t(bal_max)}")
    lo, hi = tgt["first_superweapon_shot_s"]
    shots = [res[n]["superweapon"] + G["superweapons"]["atlas"]["recharge_s"] for n in plans() if res[n].get("superweapon") is not None]
    if not shots or not (lo <= min(shots) <= hi):
        fails.append(f"earliest superweapon shot {fmt_t(min(shots)) if shots else '-'} outside [{fmt_t(lo)},{fmt_t(hi)}]")
    tlo, thi = tgt["typical_first_shot_s"]
    b = res["balanced"].get("superweapon")
    if b is None or not (tlo <= b + G["superweapons"]["atlas"]["recharge_s"] <= thi):
        fails.append(f"balanced first superweapon shot {fmt_t(b + G['superweapons']['atlas']['recharge_s']) if b else '-'} outside typical window [{fmt_t(tlo)},{fmt_t(thi)}]")
    return fails


# ---- modifiers (bible) ---------------------------------------------------------------------------------------------
def load_bible():
    with open(BIBLE_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def val() -> dict:
    return G["modifier_compensation"]["valuation"]


def selector_match(sel: dict, unit: dict) -> bool:
    if "unit" not in sel["entity_kinds"]:
        return False
    tags = set(unit["tags"])
    if not set(sel["all_tags"]) <= tags:
        return False
    if sel["any_tags"] and not (set(sel["any_tags"]) & tags):
        return False
    if set(sel["exclude_tags"]) & tags:
        return False
    return True


def weapon_selector_hit(selector_id: str, w: dict) -> bool:
    """Weapon/projectile selectors (bible: unresolved_target_domain) resolved by weapon archetype properties."""
    a = WA[w["archetype"]]
    if selector_id == "selector.thermal_beam_weapons":
        return a["damage_type"] == "thermal"
    if selector_id == "selector.ordinary_guided_missiles":
        return a["projectile_kind"] == "missile" and a["interceptable_by"] == "aps_trident"
    return False


def unit_mod_applies(bible: dict, m: dict, unit: dict, arch_id: str) -> bool:
    sel = bible["selectors"][m["selector_id"]]
    if "weapon" in sel["entity_kinds"] or "projectile" in sel["entity_kinds"]:
        return any(weapon_selector_hit(m["selector_id"], w) for w in ARCH[arch_id]["weapons"])
    return selector_match(sel, unit)


def roster_modifier_value(bible: dict, rid: str, layer_filter=None) -> dict:
    r = bible["rosters"][rid]
    mods = [bible["modifiers"][m] for m in r["resolved"]["modifier_ids"]]
    sels = bible["selectors"]
    unit_rows = []
    total = 0.0
    slots_present = {}
    for uid in r["resolved"]["combat_unit_ids"]:
        u = bible["units"][uid]
        asg = G["unit_assignments"][uid]
        archid = asg["archetype"]
        slot = val()["archetype_slot"][archid]
        slots_present[slot] = slots_present.get(slot, []) + [uid]
        base = propose(archid, asg.get("tier"), asg["tags"], asg["abilities"])
        # gather modifier deltas by (layer, stat)
        acc = {}
        for m in mods:
            if layer_filter and m["layer"] != layer_filter:
                continue
            sel = sels[m["selector_id"]]
            if not unit_mod_applies(bible, m, u, archid):
                continue
            wgt = 1.0
            for c in sel.get("conditions", []):
                wgt *= val()["condition_weights"].get(c, val()["condition_weights"]["default"])
            acc.setdefault(m["stat"], {}).setdefault(m["layer"], 0.0)
            acc[m["stat"]][m["layer"]] += m["delta_percent"] * wgt
        def mult(stat, floor=None):
            v = 1.0
            for layer, d in acc.get(stat, {}).items():
                v *= 1 + d / 100.0
            if floor is not None:
                v = max(v, floor)
            return v
        a = ARCH[archid]
        ex = a["power_exponents"]
        hp_m, dmg_m = mult("health"), mult("weapon_damage")
        rl_m = mult("reload_interval_seconds")
        if rl_m > 0:
            rl_m = max(rl_m, 0.5)
        cost_m = mult("cost_credits", 0.6)
        bt_m = mult("build_time_seconds", 0.6)
        sp_m, rg_m, vs_m = mult("movement_speed"), mult("weapon_range_cells"), mult("sight_cells")
        dps_m = dmg_m / rl_m if rl_m > 0 else dmg_m
        pi = (hp_m ** ex["hp"]) * ((dps_m ** ex["dps"]) if base["dps_vs_primary"] > 0 else 1.0) * (rg_m ** ex["range"]) * (sp_m ** ex["speed"]) * (vs_m ** ex["vision"])
        rearm = mult("rearm_time_seconds")
        if a["family"] == "aircraft" and rearm != 1.0:
            pi *= (1 / rearm) ** val()["elasticity"]["rearm_time"]
        speed_flight = mult("projectile_flight_speed")
        pi *= speed_flight ** val()["elasticity"]["projectile_flight_speed"]
        e = pi / cost_m * (1 + val()["elasticity"]["build_time"] * (1 / bt_m - 1))
        unit_rows.append((uid, slot, e))
    weights = {s: val()["slot_weights"][s] for s in slots_present}
    norm = sum(weights.values())
    for uid, slot, e in unit_rows:
        n_in_slot = len(slots_present[slot])
        total += (weights[slot] / norm) / n_in_slot * (e - 1.0)
    # structure / economy modifiers
    struct_val = 0.0
    for m in mods:
        if layer_filter and m["layer"] != layer_filter:
            continue
        sel = sels[m["selector_id"]]
        if "structure" not in sel["entity_kinds"]:
            continue
        share = val()["structure_shares"].get(m["selector_id"], val()["structure_shares"]["default"])
        el = val()["elasticity"]
        d = m["delta_percent"] / 100.0
        st = m["stat"]
        if st == "cost_credits":
            struct_val += share * (1 / (1 + d) - 1)
        elif st == "health":
            struct_val += share * el["structure_health"] * d
        elif st == "build_time_seconds":
            struct_val += share * el["structure_build_time"] * (1 / (1 + d) - 1)
        elif st == "power_output":
            struct_val += share * el["power_output"] * d
        elif st == "repair_progress_rate":
            struct_val += share * el["repair_progress_rate"] * d
    econ_val = 0.0
    for m in mods:
        if m["stat"] == "repair_credit_cost_per_health":
            econ_val += val()["elasticity"]["repair_spend_share"] * (-m["delta_percent"] / 100.0) * val()["elasticity"]["repair_cost_effect"]
    w_unique = 0.0
    if r["kind"] == "subfaction":
        for rep in r["delta"]["replacements"]:
            slot = val()["archetype_slot"][G["unit_assignments"][rep["replacement_unit_id"]]["archetype"]]
            w_unique += weights.get(slot, 0.0) / norm / max(1, len(slots_present.get(slot, [1])))
    return dict(units=total, structures=struct_val, econ=econ_val, total=total + struct_val + econ_val, w_unique=w_unique,
                removed=[bible["units"][x]["name"] for x in r["delta"].get("removed_without_replacement_unit_ids", [])] if r["kind"] == "subfaction" else [])


def compensation_table(bible: dict) -> dict:
    """Per-roster raw passive index and the recommended base-stat compensation (docs/balance/FRAMEWORK.md 5.9).
    faction offset  = clamp(-factor * I_vanilla)                       (all combat units of the faction, HP and DPS)
    unique offset   = clamp(-factor * I_after_faction / w_unique)      (only the 2 replacement units; skipped when |I_after| < skip_below)"""
    cfg = G["modifier_compensation"]
    factor, clamp, uclamp, skip = cfg["factor"], cfg["faction_clamp_pct"], cfg["unique_unit_clamp_pct"], cfg["skip_below_pct"]
    raw = {rid: roster_modifier_value(bible, rid) for rid in bible["rosters"]}
    out = {}
    for fid, f in bible["factions"].items():
        van = f["vanilla_roster_id"]
        i_van = raw[van]["total"] * 100
        off = 0.0 if abs(i_van) < 1.5 else max(-clamp, min(clamp, -factor * i_van))
        off = round(off * 2) / 2.0
        out[van] = dict(raw=i_van, parent_offset=off, unique_offset=0.0, w_unique=0.0, residual=i_van + off)
        for sid in f["subfaction_roster_ids"]:
            i_s = raw[sid]["total"] * 100
            after = i_s + off
            w = raw[sid]["w_unique"]
            uo = 0.0
            if w > 0 and abs(after) >= skip:
                uo = max(-uclamp, min(uclamp, -factor * after / w))
                uo = round(uo * 2) / 2.0
            out[sid] = dict(raw=i_s, parent_offset=off, unique_offset=uo, w_unique=w, residual=after + uo * w)
    return out


def cmd_modifiers(args=None) -> str:
    try:
        bible = load_bible()
    except FileNotFoundError:
        return "(bible not found)"
    tab = compensation_table(bible)
    rows = []
    for rid, r in bible["rosters"].items():
        v = roster_modifier_value(bible, rid)
        c = tab[rid]
        rows.append([rid.replace("roster.", ""), f"{v['units'] * 100:+.1f}", f"{v['structures'] * 100:+.1f}", f"{v['econ'] * 100:+.1f}", f"{c['raw']:+.1f}",
                     f"{c['parent_offset']:+.1f}", f"{c['unique_offset']:+.1f}", f"{c['residual']:+.1f}", ", ".join(v["removed"]) or "-"])
    return md_table(["roster", "units %", "structures %", "economy %", "raw index %", "faction offset %", "unique-unit offset %", "residual %", "removed unit"], rows,
                    ["l", "r", "r", "r", "r", "r", "r", "r", "l"])


def check_modifiers() -> list[str]:
    fails = []
    try:
        bible = load_bible()
    except FileNotFoundError:
        return fails
    band = G["modifier_compensation"]["residual_band_pct"]
    tab = compensation_table(bible)
    for rid, c in tab.items():
        if not (-band <= c["residual"] <= band):
            fails.append(f"roster {rid} residual passive index {c['residual']:+.1f}% outside +-{band}% (raw {c['raw']:+.1f}%)")
    stored = G["modifier_compensation"].get("recommended", {})
    for rid, c in tab.items():
        st = stored.get(rid.replace("roster.", ""))
        if st is None or abs(st[0] - c["parent_offset"]) > 0.01 or abs(st[1] - c["unique_offset"]) > 0.01:
            fails.append(f"stored compensation for {rid} is stale: tool says {c['parent_offset']:+.1f}/{c['unique_offset']:+.1f}")
    return fails


# ---- resolve (bible layering, integer recipe) ------------------------------------------------------------------------
def ceil_div(a: int, b: int) -> int:
    return -((-a) // b)


def half_up_div(a: int, b: int) -> int:
    return (2 * a + b) // (2 * b)


def layered_bp(mods: list[dict], stat: str, floor_bp: int | None = None) -> int:
    """Bible rule: within a layer deltas add, layers multiply. Integer basis points, half-up per layer, floor applied at the end."""
    acc = 10000
    for layer in ("parent_faction", "subfaction", "research_and_temporary_effects"):
        d = sum(int(round(m["delta_percent"] * 100)) for m in mods if m["stat"] == stat and m["layer"] == layer)
        if d:
            acc = half_up_div(acc * (10000 + d), 10000)
    if floor_bp is not None:
        acc = max(acc, floor_bp)
    return acc


def resolve_unit(unit_id: str, roster_id: str, apply_offsets: bool = False) -> dict:
    """Base proposal for unit_id -> final sim-unit integers for roster_id (docs/balance/FRAMEWORK.md 5.2)."""
    bible = load_bible()
    u = bible["units"][unit_id]
    r = bible["rosters"][roster_id]
    asg = G["unit_assignments"][unit_id]
    faction = unit_id.split(".")[1]
    base = propose(asg["archetype"], asg.get("tier"), asg["tags"], asg["abilities"], faction if apply_offsets else None)
    mods = [bible["modifiers"][m] for m in r["resolved"]["modifier_ids"] if unit_mod_applies(bible, bible["modifiers"][m], u, asg["archetype"])
            and not bible["selectors"][bible["modifiers"][m]["selector_id"]].get("conditions")]
    cost_bp = layered_bp(mods, "cost_credits", 6000)
    bt_bp = layered_bp(mods, "build_time_seconds", 6000)
    hp_bp = layered_bp(mods, "health")
    sp_bp = layered_bp(mods, "movement_speed")
    rg_bp = layered_bp(mods, "weapon_range_cells")
    rl_bp = layered_bp(mods, "reload_interval_seconds", 5000)
    vs_bp = layered_bp(mods, "sight_cells")
    dm_bp = layered_bp(mods, "weapon_damage")
    rearm_bp = layered_bp(mods, "rearm_time_seconds")
    cost = half_up_div(base["cost_credits"] * cost_bp, 10000)
    hp = max(1, half_up_div(base["health"] * hp_bp, 10000))
    bt_ms = int(round(base["build_time_s"] * 1000))
    build_ticks = ceil_div(bt_ms * bt_bp * TPS, 1000 * 10000)
    speed_milli = int(round(base["speed_cells_s"] * 1000))
    speed_upt = max(1, half_up_div(speed_milli * 1024 * sp_bp, 1000 * TPS * 10000))
    vision_units = half_up_div(int(round(base["vision_cells"] * 1000)) * 1024 * vs_bp, 1000 * 10000)
    out = dict(unit=unit_id, roster=roster_id, name=u["name"],
               applied_modifiers=[f"{m['owner_id']}: {m['stat']} {m['delta_percent']:+g}% ({m['layer']})" for m in mods],
               bp=dict(cost=cost_bp, build_time=bt_bp, health=hp_bp, speed=sp_bp, range=rg_bp, reload=rl_bp, sight=vs_bp, damage=dm_bp, rearm=rearm_bp),
               base=dict(cost=base["cost_credits"], health=base["health"], build_time_s=base["build_time_s"], speed_cells_s=base["speed_cells_s"],
                         vision_cells=base["vision_cells"]),
               final=dict(cost_credits=cost, health=hp, build_time_ticks=build_ticks, speed_units_per_tick=speed_upt, vision_units=vision_units), weapons=[])
    if "rearm_s_full" in base:
        rearm_final = base["rearm_s_full"] * rearm_bp / 10000.0
        out["final"]["rearm_s_full"] = round(rearm_final, 2)
        out["final"]["sortie_cycle_s"] = round(base["sortie_cycle_s"] - base["rearm_s_full"] + rearm_final, 2)
    for w in base["weapons"]:
        a = WA[w["archetype"]]
        range_units = half_up_div(int(round(w["range_cells"] * 1000)) * 1024 * rg_bp, 1000 * 10000)
        reload_base = ceil_div(int(round(w["reload_s"] * 1000)) * TPS, 1000)
        reload_ticks = max(ceil_div(reload_base, 2), ceil_div(int(round(w["reload_s"] * 1000)) * rl_bp * TPS, 1000 * 10000))
        raw = int(round(w["damage"]))
        vs = a["damage_type"]
        dm_w = layered_bp([m for m in mods if m["stat"] == "weapon_damage" and ("weapon" not in bible["selectors"][m["selector_id"]]["entity_kinds"] or weapon_selector_hit(m["selector_id"], w))], "weapon_damage")
        out["weapons"].append(dict(archetype=w["archetype"], damage_type=vs, damage_per_hit=raw, hits=w["hits_per_volley"], ammo_volleys=w.get("ammo_volleys", 0), range_units=range_units,
                                   reload_ticks=reload_ticks, damage_bonus_bp=dm_w,
                                   volley_vs_primary=w["hits_per_volley"] * final_damage(raw, pct(vs, ARCH[asg["archetype"]]["primary_target_class"]) if not (weapon_targets(w) == ["air"]) else pct(vs, "air_light"), 0, 100, dm_w)))
    return out


def cmd_resolve(args) -> str:
    r = resolve_unit(args.unit, args.roster, args.styled)
    return json.dumps(r, indent=2)


# ---- proposals ---------------------------------------------------------------------------------------------------------
def cmd_proposals(args) -> str:
    bible = load_bible() if BIBLE_PATH.exists() else None
    rows = []
    for uid, asg in G["unit_assignments"].items():
        if asg["archetype"].startswith("service."):
            continue
        faction = uid.split(".")[1]
        if args.faction and faction != args.faction:
            continue
        extra = 0.0
        if args.styled and bible and bible["units"][uid]["roster_class"] == "unique_subfaction":
            rec = G["modifier_compensation"]["recommended"].get(bible["units"][uid]["introduced_by_roster_id"].replace("roster.", ""))
            extra = rec[1] if rec else 0.0
        p = propose(asg["archetype"], asg.get("tier"), asg["tags"], asg["abilities"], faction if args.styled else None, None, extra)
        name = bible["units"][uid]["name"] if bible else uid
        rows.append([uid, name, p["tier"], asg["archetype"], p["cost_credits"], p["build_time_s"], p["health"], p["dps_vs_primary"], p["range_cells"],
                     p["speed_cells_s"], p["vision_cells"], p["radius_cells"], p["armor_class"], p["movement_class"]])
    hdr = ["unit_id", "name", "tier", "archetype", "cost", "build_s", "hp", "dps_primary", "range", "speed", "vision", "radius", "armor", "move"]
    if args.csv:
        return "\n".join([",".join(hdr)] + [",".join(str(c) for c in r) for r in rows])
    return md_table(hdr, rows, ["l", "l"] + ["r"] * 10 + ["l", "l"])


def cmd_check(args) -> str:
    with open(args.file, "r", encoding="utf-8") as f:
        data = json.load(f)
    units = data if isinstance(data, list) else data.get("units", [data])
    out = []
    tol = G["scaling"]["tolerances"]
    for u in units:
        a = ARCH.get(u.get("archetype", ""))
        if a is None:
            out.append(f"{u.get('id', '?')}: unknown archetype")
            continue
        dev = fair_cost_deviation(u) * 100
        msgs = []
        if abs(dev) > tol["power_index_pct"]:
            msgs.append(f"fair-cost deviation {dev:+.1f}% (limit +-{tol['power_index_pct']}%)")
        for key, ref_key, tk in (("cost_credits", "cost_credits", "cost_pct"), ("health", "health", "health_pct"), ("speed_cells_s", "speed_cells_s", "speed_pct"),
                                 ("vision_cells", "vision_cells", "vision_pct"), ("radius_cells", "radius_cells", "radius_pct")):
            if key in u and a[ref_key]:
                d = (u[key] / a[ref_key] - 1) * 100
                if abs(d) > tol[tk]:
                    msgs.append(f"{key} {d:+.0f}% vs archetype (limit +-{tol[tk]}%)")
        out.append(f"{u.get('id', u['archetype'])}: " + ("OK" if not msgs else "; ".join(msgs)))
    return "\n".join(out)


# ---- validate / report -----------------------------------------------------------------------------------------------------
def check_structure_of_json() -> list[str]:
    fails = []
    if [d["index"] for d in G["damage_types"]] != list(range(len(G["damage_types"]))):
        fails.append("damage_types indices not dense")
    if [a["index"] for a in G["armor_classes"]] != list(range(len(G["armor_classes"]))):
        fails.append("armor_classes indices not dense")
    for d in DTYPES:
        if set(G["damage_matrix"][d]) != set(ARMORS):
            fails.append(f"matrix row {d} incomplete")
        for a in ARMORS:
            v = G["damage_matrix"][d][a]
            if not isinstance(v, int) or v < 0 or v > 200:
                fails.append(f"matrix {d}/{a} invalid {v}")
    for aid, a in ARCH.items():
        if a["armor_class"] not in ARMORS:
            fails.append(f"{aid}: bad armor class")
        for w in a["weapons"]:
            if w["archetype"] not in WA:
                fails.append(f"{aid}: bad weapon archetype {w['archetype']}")
    bible_costs = {"unit.shared.engineer": 500, "unit.shared.collector": 1400, "unit.shared.mobile_construction_vehicle": 3000, "unit.shared.landing_transport": 900}
    sv = G["service_units"]
    for k, v in (("engineer", 500), ("collector", 1400), ("mcv", 3000), ("landing_transport", 900)):
        if sv[k]["cost_credits"] != v:
            fails.append(f"service unit {k} cost must be {v} (bible)")
    fixed = {"generator": (600, 25, 150), "refinery": (1800, 40, -30), "barracks": (500, 20, -10), "factory": (2000, 40, -40), "dock": (1800, 40, -35),
             "radar": (1500, 30, -40), "airfield": (1600, 35, -40), "laboratory": (2500, 50, -60), "watchtower": (450, 15, -5),
             "anti_tank_turret": (800, 20, -15), "aa_battery": (900, 20, -20), "advanced_defense": (1800, 35, -40), "superweapon": (5000, 90, -200)}
    for k, (c, b, p) in fixed.items():
        s = G["structures"][k]
        if (s["cost_credits"], s["build_time_s"], s["power_delta"]) != (c, b, p):
            fails.append(f"structure {k} deviates from bible fixed values {(c, b, p)}")
    if G["economy"]["start_credits"] != 7500:
        fails.append("start credits must be 7500")
    # tier_curves mirror archetypes
    for tier, roles in G["tier_curves"].items():
        for role, row in roles.items():
            a = ARCH[row["archetype"]]
            if (row["cost_credits"], row["health"]) != (a["cost_credits"], a["health"]):
                fails.append(f"tier_curves {tier}/{role} out of sync with archetype {row['archetype']}")
    # every assignment resolves
    for uid, asg in G["unit_assignments"].items():
        if asg["archetype"].startswith("service."):
            continue
        if asg["archetype"] not in ARCH:
            fails.append(f"{uid}: unknown archetype {asg['archetype']}")
        for t in asg["tags"]:
            if t not in G["style_tags"]:
                fails.append(f"{uid}: unknown tag {t}")
        for x in asg["abilities"]:
            if x not in G["ability_value_pct"]:
                fails.append(f"{uid}: unknown ability {x}")
    # floors
    if G["production"]["cost_floor_pct"] != 60 or G["production"]["reload_floor_pct"] != 50:
        fails.append("floors must be 60/60/50 (bible)")
    return fails


CHECKS = [("json structure", check_structure_of_json), ("ttk targets", check_ttk), ("equal-cost RPS bands", check_rps), ("aircraft sorties", check_sorties),
          ("defense budgets", check_defenses), ("structure kill time", check_structures), ("superweapon budgets", check_sw), ("economy", check_econ),
          ("power sets", check_power), ("pacing windows", check_pacing), ("roster modifier index", check_modifiers)]


def cmd_validate(args=None) -> int:
    bad = 0
    for name, fn in CHECKS:
        f = fn()
        print(f"[{'PASS' if not f else 'FAIL'}] {name}")
        for m in f:
            print("      - " + m)
        bad += len(f)
    print(f"\n{bad} failure(s)")
    return 1 if bad else 0


def cmd_report(args=None) -> str:
    parts = [("Tier curves", cmd_table()), ("Damage matrix", cmd_matrix()), ("Unopposed TTK grid (s)", cmd_ttk()),
             ("TTK targets", md_table(["attacker", "target", "TTK s", "band", "status"], ttk_rows(), ["l", "l", "r", "r", "l"])),
             ("Equal-cost group fights (row beats col)", cmd_rps()),
             ("RPS bands", md_table(["A", "B", "share diff", "band", "status", "why"], rps_band_rows(), ["l", "l", "r", "r", "l", "l"])),
             ("Aircraft sorties", cmd_sorties()), ("Defense budgets", cmd_defenses()), ("Structure kill times", cmd_structures()),
             ("Superweapon budgets", cmd_sw()), ("Economy", cmd_econ()), ("Power sets", cmd_power()), ("Pacing", cmd_pacing()), ("Roster passive-modifier index", cmd_modifiers())]
    return "\n\n".join(f"### {t}\n\n{b}" for t, b in parts)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for n in ("table", "matrix", "ttk", "rps", "sorties", "defenses", "structures", "sw", "econ", "power", "pacing", "validate", "report"):
        sub.add_parser(n)
    p = sub.add_parser("propose")
    p.add_argument("arch")
    p.add_argument("--tier", type=int)
    p.add_argument("--tags", default="")
    p.add_argument("--abilities", default="")
    p.add_argument("--faction")
    p.add_argument("--cost", type=int, help="scale HP and damage linearly to this price (equal efficiency)")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("modifiers")
    p.add_argument("--emit", action="store_true", help="print the recommended-compensation JSON block for global.json")
    p = sub.add_parser("proposals")
    p.add_argument("--faction")
    p.add_argument("--csv", action="store_true")
    p.add_argument("--styled", action="store_true")
    p = sub.add_parser("resolve")
    p.add_argument("unit")
    p.add_argument("roster")
    p.add_argument("--styled", action="store_true")
    p = sub.add_parser("check")
    p.add_argument("file")
    p = sub.add_parser("duel")
    p.add_argument("a")
    p.add_argument("b")
    args = ap.parse_args(argv)
    if args.cmd == "validate":
        return cmd_validate()
    if args.cmd == "propose":
        r = propose(args.arch, args.tier, [t for t in args.tags.split(",") if t], [x for x in args.abilities.split(",") if x], args.faction, args.cost)
        if args.json:
            print(json.dumps(r, indent=2))
        else:
            for k, v in r.items():
                if k != "weapons":
                    print(f"{k:18s} {v}")
            for w in r["weapons"]:
                print("weapon", w)
        return 0
    if args.cmd == "duel":
        t, win = duel_ttk(args.a, args.b)
        print(f"{args.a} vs {args.b}: {t:.1f}s winner={'A' if win == 0 else 'B' if win == 1 else 'draw'}")
        return 0
    if args.cmd == "modifiers" and args.emit:
        tab = compensation_table(load_bible())
        print(json.dumps({k.replace("roster.", ""): [v["parent_offset"], v["unique_offset"]] for k, v in tab.items()}, indent=1))
        return 0
    fn = {"table": cmd_table, "matrix": cmd_matrix, "ttk": cmd_ttk, "rps": cmd_rps, "sorties": cmd_sorties, "defenses": cmd_defenses, "structures": cmd_structures,
          "sw": cmd_sw, "econ": cmd_econ, "power": cmd_power, "pacing": cmd_pacing, "modifiers": cmd_modifiers, "report": cmd_report,
          "proposals": cmd_proposals, "check": cmd_check, "resolve": cmd_resolve}[args.cmd]
    print(fn(args))
    return 0


if __name__ == "__main__":
    sys.exit(main())
