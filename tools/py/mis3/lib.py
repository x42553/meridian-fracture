"""MIS3 authoring helpers: a tiny DSL that emits game/data/missions/<id>.json (schema meridian.mission/1).

The JSON files are the shipped content (parsed by src/data, listed in the manifest, hashed). This package is the authoring aid that wrote
them: re-running `python3 tools/py/gen_missions.py` regenerates all of them byte for byte. After a hand edit of a JSON file either port it
here or stop using the generator.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "game" / "data" / "missions"


# ----------------------------------------------------------------------------------------------------------- conditions
def all_(*c): return {"all": list(c)}
def any_(*c): return {"any": list(c)}
def not_(c): return {"not": c}
def time_s(seconds, cmp=">="): return {"kind": "time", "cmp": cmp, "seconds": seconds}
def time_t(ticks, cmp=">="): return {"kind": "time", "cmp": cmp, "ticks": ticks}
def timer(t): return {"kind": "timer", "timer": t}
def obj(o, state): return {"kind": "objective", "objective": o, "state": state}
def active(o): return obj(o, "active")
def done(o): return obj(o, "completed")
def failed(o): return obj(o, "failed")
def count(owner, value=1, cmp=">=", of=None, def_=None, tag=None, area=None):
    c = {"kind": "count", "owner": owner}
    if of: c["of"] = of
    if def_: c["def"] = def_
    if tag: c["tag"] = tag
    if area: c["area"] = area
    if cmp != ">=": c["cmp"] = cmp
    c["value"] = value
    return c
def struct(state, owner=None, def_=None, placed=None):
    c = {"kind": "structure", "state": state}
    if owner is not None: c["owner"] = owner
    if def_: c["def"] = def_
    if placed: c["placed"] = placed
    return c
def area_left(owner, area, def_=None, tag=None):
    c = {"kind": "area_left", "owner": owner, "area": area}
    if def_: c["def"] = def_
    if tag: c["tag"] = tag
    return c
def credits(owner, value, cmp=">="): return {"kind": "credits", "owner": owner, "cmp": cmp, "value": value}
def power(owner, value=0, cmp=">="): return {"kind": "power", "owner": owner, "cmp": cmp, "value": value}
def research(owner, r): return {"kind": "research", "owner": owner, "research": r}
def sp(owner, slot, state): return {"kind": "support_power", "owner": owner, "slot": slot, "state": state}
def sw(owner, state): return {"kind": "superweapon", "owner": owner, "state": state}
def defeated(owner): return {"kind": "defeated", "owner": owner}
def no_assets(owner): return {"kind": "no_assets", "owner": owner}
def wave(w, state): return {"kind": "wave", "wave": w, "state": state}
def fired(t, value=1, cmp=">="): return {"kind": "trigger", "trigger": t, "cmp": cmp, "value": value}


# --------------------------------------------------------------------------------------------------------------- actions
def set_obj(o, state): return {"do": "set_objective", "objective": o, "state": state}
def say(m, announcer=None):
    a = {"do": "show_message", "message": m}
    if announcer: a["announcer"] = announcer
    return a
def timer_start(t, seconds=None):
    a = {"do": "timer_start", "timer": t}
    if seconds is not None: a["seconds"] = seconds
    return a
def timer_stop(t): return {"do": "timer_stop", "timer": t}
def spawn(owner, def_, count=1, area=None, wave=None, order=None, order_area=None, facing=None):
    a = {"do": "spawn_units", "owner": owner, "def": def_, "count": count, "area": area}
    if wave: a["wave"] = wave
    if order:
        o = {"kind": order}
        if order_area: o["area"] = order_area
        a["order"] = o
    if facing is not None: a["facing"] = facing
    return a
def spawn_s(owner, def_, area=None, cell=None, id=None, facing=None):
    a = {"do": "spawn_structure", "owner": owner, "def": def_}
    if area: a["area"] = area
    if cell: a["cell"] = list(cell)
    if id: a["id"] = id
    if facing is not None: a["facing"] = facing
    return a
def give(owner, amount): return {"do": "give_credits", "owner": owner, "amount": amount}
def grant(owner, slot): return {"do": "grant_power", "owner": owner, "slot": slot}
def lock(owner, slot): return {"do": "lock_power", "owner": owner, "slot": slot}
def reveal(owner, area, seconds=None):
    a = {"do": "reveal_area", "owner": owner, "area": area}
    if seconds is not None: a["seconds"] = seconds
    return a
def change_ai(owner, active=None, level=None, style=None, aggression=None):
    a = {"do": "change_ai", "owner": owner}
    if active is not None: a["active"] = active
    if level is not None: a["level"] = level
    if style is not None: a["style"] = style
    if aggression is not None: a["aggression"] = aggression
    return a
def transfer(to, placed=None, owner=None, area=None, def_=None, tag=None, of=None):
    a = {"do": "transfer", "to": to}
    if placed: a["placed"] = placed
    if owner is not None: a["owner"] = owner
    if area: a["area"] = area
    if def_: a["def"] = def_
    if tag: a["tag"] = tag
    if of: a["of"] = of
    return a
def destroy(placed=None, owner=None, area=None, def_=None, tag=None, of=None):
    a = {"do": "destroy"}
    if placed: a["placed"] = placed
    if owner is not None: a["owner"] = owner
    if area: a["area"] = area
    if def_: a["def"] = def_
    if tag: a["tag"] = tag
    if of: a["of"] = of
    return a
def order(owner, kind, area=None, order_area=None, def_=None, tag=None):
    a = {"do": "order_units", "owner": owner, "order": {"kind": kind}}
    if order_area: a["order"]["area"] = order_area
    if area: a["area"] = area
    if def_: a["def"] = def_
    if tag: a["tag"] = tag
    return a
def eliminate(owner): return {"do": "eliminate", "owner": owner}
def enable(t): return {"do": "trigger_enable", "trigger": t}
def disable(t): return {"do": "trigger_disable", "trigger": t}
def win(owner=0): return {"do": "win", "owner": owner}
def lose(owner=0): return {"do": "lose", "owner": owner}
def cam(area=None, cell=None, seconds=None):
    a = {"do": "camera_hint"}
    if area: a["area"] = area
    if cell: a["cell"] = list(cell)
    if seconds is not None: a["seconds"] = seconds
    return a
def music(state): return {"do": "music_state", "state": state}


# ------------------------------------------------------------------------------------------------------------------ mission
class Mission:
    def __init__(self, id, title, group, order, map_, rules=None, sim_seed=None):
        self.d = {"schema": "meridian.mission/1", "id": id, "title": title, "group": group, "order": order, "briefing": [], "map": map_}
        if sim_seed is not None: self.d["sim_seed"] = sim_seed
        self.d["rules"] = rules or {}
        self.d.update({"players": [], "areas": [], "messages": [], "objectives": [], "timers": [], "triggers": []})
        self._ids = {"messages": set(), "objectives": set(), "timers": set(), "triggers": set(), "areas": set()}

    # ---- builders
    def brief(self, heading, text, lore=None):
        b = {"heading": heading, "text": text}
        if lore: b["lore"] = lore
        self.d["briefing"].append(b)

    def player(self, slot, kind, roster, team, name=None, start="hq", units=None, structures=None, credits=None, handicap=None,
               start_slot=None, ai=None, color=None):
        p = {"slot": slot, "kind": kind}
        if name: p["name"] = name
        p["roster"] = roster
        p["team"] = team
        if color is not None: p["color"] = color
        if start_slot is not None: p["start_slot"] = start_slot
        if credits is not None: p["credits"] = credits
        if handicap is not None: p["handicap"] = handicap
        if ai is not None: p["ai"] = ai
        st = {"mode": start}
        if units: st["units"] = units
        if structures: st["structures"] = structures
        p["start"] = st
        self.d["players"].append(p)

    def circle(self, id, x, y, r, anchor=None):
        a = {"id": id, "shape": "circle"}
        if anchor: a["anchor"] = anchor
        a.update({"x": x, "y": y, "r": r})
        self._add("areas", id, a)

    def rect(self, id, x, y, w, h, anchor=None):
        a = {"id": id, "shape": "rect"}
        if anchor: a["anchor"] = anchor
        a.update({"x": x, "y": y, "w": w, "h": h})
        self._add("areas", id, a)

    def msg(self, id, text, speaker=None, announcer=None):
        m = {"id": id, "text": text}
        if speaker: m["speaker"] = speaker
        if announcer: m["announcer"] = announcer
        self._add("messages", id, m)

    def objective(self, id, kind, text, initial="hidden"):
        o = {"id": id, "kind": kind, "text": text}
        if initial != "active": o["initial"] = initial
        self._add("objectives", id, o)

    def timer(self, id, seconds, label=None, repeat=False, autostart=False):
        t = {"id": id, "seconds": seconds}
        if label: t["label"] = label
        if repeat: t["repeat"] = True
        if autostart: t["autostart"] = True
        self._add("timers", id, t)

    def trig(self, id, when, then, once=True, enabled=True, edge=False, cooldown=0):
        t = {"id": id}
        if not once: t["once"] = False
        if not enabled: t["enabled"] = False
        if edge: t["edge"] = True
        if cooldown: t["cooldown_s"] = cooldown
        t["when"] = when
        t["then"] = then
        self._add("triggers", id, t)

    def _add(self, key, id, v):
        assert id not in self._ids[key], f"{self.d['id']}: duplicate {key} id {id}"
        self._ids[key].add(id)
        self.d[key].append(v)

    # ---- output
    def check_limits(self):
        lim = {"areas": 64, "messages": 128, "objectives": 64, "timers": 16, "triggers": 128}
        for k, n in lim.items():
            assert len(self.d[k]) <= n, f"{self.d['id']}: {len(self.d[k])} {k} > {n}"
        for t in self.d["triggers"]:
            assert 1 <= len(t["then"]) <= 32, f"{self.d['id']}: trigger {t['id']} has {len(t['then'])} actions"

    def write(self):
        self.check_limits()
        d = self.d
        lines = ["{"]
        keys = [k for k in d if k not in ("briefing",)]
        out = []
        for k in d:
            v = d[k]
            if isinstance(v, list):
                if not v:
                    out.append(f'  "{k}": []')
                    continue
                items = ",\n".join("    " + json.dumps(x, ensure_ascii=False, separators=(", ", ": ")) for x in v)
                out.append(f'  "{k}": [\n{items}\n  ]')
            else:
                out.append(f'  "{k}": ' + json.dumps(v, ensure_ascii=False, separators=(", ", ": ")))
        text = "{\n" + ",\n".join(out) + "\n}\n"
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"{d['id']}.json").write_text(text, encoding="utf-8")
        return text
