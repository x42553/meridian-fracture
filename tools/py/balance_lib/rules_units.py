"""Rules for units_<code>.json: identity/coverage (V-CMP), bible conflicts (V-CNF), references (V-REF), ranges (V-RNG), abilities (V-ABL), roles (V-ROLE)."""
from __future__ import annotations

import re

from . import convert, vocab
from .abilities import Entity, Registry, Resolved, resolve
from .context import Ctx, LoadedFile, dicts, num, unit_code
from .jsonio import LDict, line_of
from .ranges import RANGES
from .rules_files import add
from .rules_balance import check_balance

REQ_UNIT_KEYS = ("build_time_s", "health", "vision_cells", "radius_cells", "armor_class", "movement_class", "size_class")
# framework ability name -> extra kinds that satisfy it (V-ABL-05)
ALT_KINDS = {"deployable_mode": {"deploy", "mode_switch"}, "sensor": {"sensor_puck", "sensor_mast"}}
ROLE_ABILITY = {"detector": "detector", "transport": "transport", "carrier": "carrier", "command": "command_field", "collector": "harvest",
                "construction": "deploy_structure", "capture": "capture", "repair": "repair", "electronic_warfare": "ew_jammer", "submarine": "submerge"}


def registry(ctx: Ctx) -> Registry | None:
    if not hasattr(ctx, "_registry"):
        lf = ctx.files.get("ability_kinds.json")
        ctx._registry = Registry(lf.data) if lf and lf.ok else None  # type: ignore[attr-defined]
    r = ctx._registry  # type: ignore[attr-defined]
    return r if r is not None and r.ok else None


class _Rep:
    """Bound reporter for one entry."""

    def __init__(self, ctx: Ctx, lf: LoadedFile, e: dict, eid: str) -> None:
        self.ctx, self.lf, self.e, self.eid = ctx, lf, e, eid

    def __call__(self, rule: str, field: str, msg: str, expected: object = "", found: object = "", sev: str | None = None) -> None:
        key = re.split(r"[.\[]", field)[0] if field else "id"
        if key not in self.e:
            key = "id"
        add(self.ctx, rule, self.lf, msg, self.e, key, entity=self.eid, field=field, expected=expected, found=found, sev=sev)


def check_units_file(ctx: Ctx, lf: LoadedFile) -> None:
    code = unit_code(lf.name)
    d = lf.data
    assert isinstance(d, dict)
    fac = d.get("faction", "<absent>")
    want_fac = None if code == "shared" else f"faction.{code}"
    if fac != want_fac and fac != "<absent>":
        add(ctx, "V-CMP-01", lf, f"'faction' of {lf.name} must be {want_fac!r}", d, "faction", field="faction", expected=want_fac, found=fac)
    weapons = {w["id"]: w for w in dicts(d.get("weapons")) if isinstance(w.get("id"), str)}
    units = dicts(d.get("units"))
    summons = dicts(d.get("summons"))
    reg = registry(ctx)
    referenced_weapons: set[str] = set()
    expected_ids = {u for u in ctx.b_units if u.split(".")[1] == code}

    seen: dict[str, int] = {}
    for e in units:
        uid = e.get("id")
        if not isinstance(uid, str):
            continue
        R = _Rep(ctx, lf, e, uid)
        if uid in seen:
            R("V-CMP-01", "id", f"unit {uid} appears more than once in this file (first at line {seen[uid]})", "exactly once", "duplicate")
        seen.setdefault(uid, line_of(e, "id"))
        if uid not in ctx.b_units:
            R("V-CMP-01", "id", f"{uid} is not a bible unit id", "a unit id of meridian_factions.json", uid)
            continue
        if uid not in expected_ids:
            R("V-CMP-01", "id", f"{uid} belongs to units_{uid.split('.')[1]}.json, not to {lf.name}", f"unit.{code}.*", uid)
            continue
        check_unit(ctx, lf, e, uid, R, weapons, reg, referenced_weapons)
    for uid in sorted(expected_ids - set(seen)):
        add(ctx, "V-CMP-01", lf, f"bible unit {uid} ({ctx.b_units[uid].get('name', '?')}) has no entry in {lf.name}", d, "units", entity=uid, field="units",
            expected="exactly one entry", found="<absent>")
    for s in summons:
        sid = s.get("id")
        if isinstance(sid, str):
            check_summon(ctx, lf, s, sid, weapons, reg, referenced_weapons, code)
    for wid, w in weapons.items():
        check_weapon(ctx, lf, w, wid, code)
        if wid not in referenced_weapons:
            add(ctx, "V-REF-03", lf, f"weapon {wid} is not referenced by any unit or summon of {lf.name}", w, "id", entity=wid, field="id",
                expected="referenced by a 'weapons' list", found="orphan")
    # tag namespace size (V-SCH-08)
    tags = set(ctx.bible_unit_tags())
    for u in units + summons:
        tags.update(t for t in (u.get("tags_add") or []) if isinstance(t, str))
        tags.update(t for t in (u.get("unit_tags") or []) if isinstance(t, str))
    if len(tags) > 62:
        add(ctx, "V-SCH-08", lf, f"unit-tag namespace has {len(tags)} tags (max 62 bits)", d, "units", expected="<= 62", found=len(tags))
    check_balance(ctx, lf, units)


# ---------------------------------------------------------------------------------------------------------------- one bible unit
def vocab_sets(ctx: Ctx) -> dict[str, set]:
    g = ctx.g
    return {
        "size_class": set(vocab.SIZE_CLASSES) | set(g.get("size_classes", {})),
        "armor_class": set(vocab.ARMOR_CLASSES),
        "movement_class": set(vocab.MOVE_CLASSES),
        "layer": set(vocab.LAYERS),
    }


def effective_weapons(ctx: Ctx, e: dict, weapons: dict[str, dict], R: _Rep | None, referenced: set[str]) -> list[dict]:
    """Weapon instances of a def in slot order: the sheet's list resolved against the file's weapons, else the archetype's anonymous instances."""
    if "weapons" in e:
        out = []
        ids = e.get("weapons")
        for i, wid in enumerate(ids if isinstance(ids, list) else []):
            if not isinstance(wid, str):
                continue
            referenced.add(wid)
            w = weapons.get(wid)
            if w is None:
                if R:
                    R("V-REF-01", f"weapons[{i}]", f"weapon {wid!r} is not defined in the 'weapons' list of this file", "id of a weapon instance of this file", wid)
                continue
            out.append(w)
        return out
    return [dict(w) for w in ctx.base_row(e.get("archetype")).get("weapons", []) if isinstance(w, dict)]


def check_unit(ctx: Ctx, lf: LoadedFile, e: dict, uid: str, R: _Rep, weapons: dict, reg: Registry | None, referenced: set[str]) -> None:
    b = ctx.b_units[uid]
    ua = ctx.ua.get(uid, {})
    arch_id = e.get("archetype")
    row = ctx.base_row(arch_id)
    vs = vocab_sets(ctx)
    # ---- archetype / vocabulary
    if isinstance(arch_id, str):
        if not row:
            R("V-REF-04", "archetype", f"archetype {arch_id!r} is not a key of global.json archetypes (or service.<name> of service_units)",
              "role archetype id", arch_id)
        elif ua and ua.get("archetype") != arch_id:
            R("V-ABL-05", "archetype", "archetype differs from global.json unit_assignments", ua.get("archetype"), arch_id)
    for k, allowed in vs.items():
        v = e.get(k)
        if isinstance(v, str) and v not in allowed:
            R("V-REF-04", k, f"{k} {v!r} is not in the frozen vocabulary", "one of " + ", ".join(sorted(allowed)), v)
    # ---- required fields after defaults (V-CMP-04)
    need = list(REQ_UNIT_KEYS)
    static = ctx.eff(e, "movement_class") == "static"
    if not static:
        need.append("speed_cells_s")
    if b.get("base_stats", {}).get("cost_credits") is None:
        need.append("cost_credits")
    for k in need:
        if ctx.eff(e, k) is None:
            R("V-CMP-04", k, f"required field {k!r} is missing and neither the sheet nor archetype {arch_id!r} supplies it", "value", "<absent>")
    if row.get("family") == "aircraft" and ctx.eff(e, "rearm_s_full") is None:
        R("V-CMP-04", "rearm_s_full", "aircraft need rearm_s_full", "seconds", "<absent>")
    # ---- bible conflicts (V-CNF-01/02)
    bs = b.get("base_stats", {})
    pairs = [("tier", b.get("tier"), e.get("tier")), ("cost_credits", bs.get("cost_credits"), e.get("cost_credits")),
             ("build_time_s", bs.get("build_time_seconds"), e.get("build_time_s")), ("health", bs.get("health"), e.get("health")),
             ("speed_cells_s", bs.get("movement_speed"), e.get("speed_cells_s"))]
    ws = e.get("weapons") if isinstance(e.get("weapons"), list) else []
    w0 = weapons.get(ws[0]) if ws and isinstance(ws[0], str) else None
    if w0:
        pairs += [("weapons[0].damage", bs.get("damage"), w0.get("damage")), ("weapons[0].range_cells", bs.get("weapon_range_cells"), w0.get("range_cells"))]
    for k, bv, sv in pairs:
        if bv is None or sv is None:
            continue
        if num(bv) is not None and num(sv) is not None and float(bv) == float(sv):
            R("V-CNF-02", k.split("[")[0], f"{k} repeats the bible value (may be omitted)", bv, sv)
        else:
            R("V-CNF-01", k.split("[")[0], f"{k} conflicts with the bible (bible values are never overridden)", f"bible {bv}", sv)
    # ---- numeric ranges (V-RNG-01) and conversions (V-RNG-03)
    for k, (lo, hi) in RANGES.items():
        v = num(e.get(k))
        if v is None or k in ("damage", "range_cells", "reload_s", "footprint"):
            continue
        if k == "speed_cells_s" and (static or v == 0):
            continue
        if not lo <= v <= hi:
            R("V-RNG-01", k, f"{k} outside the allowed range", f"{lo}..{hi}", v)
    sp = num(e.get("speed_cells_s"))
    if sp and convert.cells_s_to_upt(sp) < 1:
        R("V-RNG-03", "speed_cells_s", "non-zero speed converts to < 1 unit per tick", ">= 0.0196 cells/s", sp)
    # ---- weapons
    ew = effective_weapons(ctx, e, weapons, R, referenced)
    unarmed_ok = uid in vocab.UNARMED_UNITS
    eff_tags = e.get("tags") if isinstance(e.get("tags"), list) else ua.get("tags", [])
    carrier_arch = "drone_weapon" in row
    if unarmed_ok and ew:
        R("V-CMP-05", "weapons", f"{b.get('name', uid)} is unarmed in the bible but has {len(ew)} weapon(s)", "no weapons", len(ew))
    elif not unarmed_ok and not ew and not carrier_arch and "no_gun" not in eff_tags and b.get("roster_class") != "service":
        R("V-CMP-05", "weapons", f"{b.get('name', uid)} is a combat unit but has no weapon (archetype {arch_id!r} supplies none); add a weapon or the style tag no_gun",
          ">= 1 weapon", 0)
    # ---- tags_add (V-CNF-03)
    for i, t in enumerate(e.get("tags_add") or []):
        if not isinstance(t, str):
            continue
        if t in ctx.locked_tags():
            R("V-CNF-03", f"tags_add[{i}]", f"tag {t!r} is a locked selector tag (it would change modifier scopes)", "a free tag", t)
        elif t in ctx.bible_unit_tags() and t not in b.get("tags", []):
            R("V-CNF-03", f"tags_add[{i}]", f"tag {t!r} is a bible tag with a fixed meaning that this unit does not have", "a free tag", t)
        elif t in b.get("tags", []):
            R("V-CNF-02", f"tags_add[{i}]", f"tag {t!r} is already a bible tag of this unit", "omit", t)
    # ---- style tags
    st = ctx.g.get("style_tags", {})
    for i, t in enumerate(e.get("tags") or []):
        if isinstance(t, str) and (t not in st or t == "note"):
            R("V-ABL-05", f"tags[{i}]", f"style tag {t!r} is not a key of global.json style_tags", "one of " + ", ".join(sorted(k for k in st if k != "note")[:6]) + " ...", t)
    if isinstance(ua.get("tier"), int) and "tier" in e and e["tier"] != ua["tier"]:
        R("V-ABL-05", "tier", "tier differs from the unit_assignments override", ua["tier"], e["tier"])
    # ---- abilities
    entries = e["abilities"] if isinstance(e.get("abilities"), list) else ua.get("abilities", [])
    resolved: dict[str, Resolved] = {}
    if reg:
        ent = Entity("unit", list(entries), e.get("ability_params") if isinstance(e.get("ability_params"), dict) else {}, set(b.get("tags", [])),
                     str(row.get("family", "")), str(arch_id))
        resolved = resolve(reg, ent, R, ctx)
        check_ability_slots(R, resolved, ew)
        check_assignment(R, reg, entries, resolved, ua, e, ew, b)
    check_roles(R, b, ctx, resolved, ew, e, reg is not None)


def check_ability_slots(R: _Rep, resolved: dict[str, Resolved], ew: list[dict]) -> None:
    n = len(ew)
    ms = resolved.get("mode_switch")
    modes = ms.params.get("modes") if ms else None
    if modes is None and ms:
        modes = []
    for k in ("deploy", "mode_switch"):
        r = resolved.get(k)
        if not r:
            continue
        slots: list = []
        if k == "deploy":
            slots = [(f"deployed_slots_n", r.params.get("deployed_slots_n") or [])]
        else:
            slots = [(f"modes[{i}].slots_n", m.get("slots_n", [])) for i, m in enumerate(modes or []) if isinstance(m, dict)]
        for fld, lst in slots:
            for s in lst if isinstance(lst, list) else []:
                if not isinstance(s, int) or not 0 <= s < n:
                    R("V-ABL-03", f"abilities[{r.entry}].{fld}", f"weapon slot {s!r} does not exist (the unit has {n} weapon slot(s), numbered from 0)", f"0..{n - 1}", s)
    for i, w in enumerate(ew):
        wm = w.get("modes") or []
        if wm and not ms:
            R("V-ABL-03", f"weapons[{i}]", f"weapon {w.get('id')} has 'modes' but the unit has no mode_switch ability", "no modes", wm)
        elif wm and ms:
            for m in wm:
                if not isinstance(m, int) or not 0 <= m < len(modes or []):
                    R("V-ABL-03", f"weapons[{i}]", f"weapon {w.get('id')} refers to mode {m!r} but mode_switch defines {len(modes or [])} mode(s)", f"0..{len(modes or []) - 1}", m)
                elif isinstance(modes[m], dict) and i not in (modes[m].get("slots_n") or []):
                    R("V-ABL-03", f"weapons[{i}]", f"weapon slot {i} is enabled in mode {m} by weapon.modes but mode_switch modes[{m}].slots_n does not list it",
                      f"slot {i} in modes[{m}].slots_n", modes[m].get("slots_n"))
    if ms:
        for mi, m in enumerate(modes or []):
            if not isinstance(m, dict):
                continue
            for s in m.get("slots_n", []) or []:
                if isinstance(s, int) and 0 <= s < n:
                    wm = ew[s].get("modes") or []
                    if wm and mi not in wm:
                        R("V-ABL-03", f"weapons[{s}]", f"mode_switch modes[{mi}] enables slot {s} but weapon.modes {wm} excludes mode {mi}", f"mode {mi} in weapon.modes", wm)


def kinds_of_name(reg: Registry, name: str) -> set[str]:
    t = name if name.startswith("ability.") else reg.aliases.get(name)
    k = reg.template_kind(t) if isinstance(t, str) else None
    return ({k} if k else set()) | (ALT_KINDS.get(name, set()) if not name.startswith("ability.") else set())


def check_assignment(R: _Rep, reg: Registry, entries: list, resolved: dict, ua: dict, e: dict, ew: list, b: dict) -> None:
    """V-ABL-05: sheet abilities agree with global.json unit_assignments (only when the sheet lists its own abilities)."""
    if "abilities" not in e or not ua:
        return
    a_names = [n for n in ua.get("abilities", []) if isinstance(n, str)]
    sheet = [n for n in entries if isinstance(n, str)]
    sheet_kinds = {k for n in sheet for k in kinds_of_name(reg, n)}
    a_kinds = {k for n in a_names for k in kinds_of_name(reg, n)}
    for n in a_names:
        if n in sheet:
            continue
        ks = kinds_of_name(reg, n)
        if ks and ks & sheet_kinds:
            continue
        mech = {"amphibious": e.get("movement_class") == "amphibious", "unmanned": "unmanned" in b.get("tags", []),
                "breach_charge": any(w.get("archetype") == "breach_charge" for w in ew)}
        if mech.get(n):
            continue
        R("V-ABL-05", "abilities", f"unit_assignments gives this unit the framework ability {n!r} but the sheet has no matching entry", f"{n!r} (or an ability of kind {sorted(ks)})", sheet)
    for n in sheet:
        if n in a_names:
            continue
        ks = kinds_of_name(reg, n)
        if ks & a_kinds:
            continue
        R("V-ABL-05", "abilities", f"sheet ability {n!r} is not part of the unit_assignments abilities {a_names}", "one of the assigned abilities", n)


def check_roles(R: _Rep, b: dict, ctx: Ctx, resolved: dict, ew: list, e: dict, have_reg: bool) -> None:
    tags = set(b.get("tags", []))
    wa = ctx.wa
    layers: set[str] = set()
    modes_ind = False
    for w in ew:
        a = wa.get(w.get("archetype"), {})
        tgt = w.get("targets_override") or a.get("targets", [])
        layers.update(x for x in tgt if isinstance(x, str))
        modes_ind = modes_ind or a.get("fire_mode") == "indirect"
    if "combat" in tags and ew:
        if "anti_air" in tags and "air" not in layers:
            R("V-ROLE-01", "weapons", "tag anti_air requires a weapon that can hit the air layer", "a weapon with target 'air'", sorted(layers))
        if "anti_submarine" in tags and "underwater" not in layers:
            R("V-ROLE-01", "weapons", "tag anti_submarine requires a weapon that can hit the underwater layer", "a torpedo/depth_charge", sorted(layers))
        if "artillery" in tags and not modes_ind:
            R("V-ROLE-01", "weapons", "tag artillery requires an indirect-fire weapon", "fire_mode indirect", "direct-fire only")
        if ({"anti_tank", "ground_attack"} & tags) and "ground" not in layers:
            R("V-ROLE-01", "weapons", "tag anti_tank/ground_attack requires a weapon that can hit the ground layer", "target 'ground'", sorted(layers))
    if have_reg:
        for tag, kind in ROLE_ABILITY.items():
            if tag in tags and kind not in resolved:
                R("V-ROLE-02", "abilities", f"tag {tag!r} requires an ability of kind {kind!r}, which the unit does not have (explicit or implicit)",
                  f"ability kind {kind}", sorted(resolved))
    mc = ctx.eff(e, "movement_class")
    ly = ctx.eff(e, "layer")

    def need(cond: bool, tag: str, exp: str) -> None:
        if tag in tags and not cond:
            R("V-ROLE-03", "movement_class", f"tag {tag!r} requires movement_class {exp}", exp, mc)
    need(mc == "foot", "infantry", "foot")
    need(mc in ("naval", "submerged"), "ship", "naval|submerged")
    need(mc == "submerged", "submarine", "submerged")
    need(mc in ("air_fixed", "air_hover"), "aircraft", "air_fixed|air_hover")
    need(mc == "amphibious", "amphibious", "amphibious")
    need(mc in ("wheeled", "tracked", "amphibious"), "land_vehicle", "wheeled|tracked|amphibious")
    if "ground" in tags and ly != "ground":
        R("V-ROLE-03", "layer", "tag 'ground' requires layer ground", "ground", ly)
    if "abilities" in e and ("unmanned" in tags) != ("unmanned" in (e.get("abilities") or [])):
        R("V-ABL-05", "abilities", "framework ability 'unmanned' must appear exactly for the bible units tagged unmanned", "unmanned" if "unmanned" in tags else "absent",
          e.get("abilities"))


# ---------------------------------------------------------------------------------------------------------------- summons / drones
def check_summon(ctx: Ctx, lf: LoadedFile, s: dict, sid: str, weapons: dict, reg: Registry | None, referenced: set[str], code: str) -> None:
    R = _Rep(ctx, lf, s, sid)
    if not sid.startswith(f"summon.{code}."):
        R("V-SCH-03", "id", f"summon id must start with summon.{code}.", f"summon.{code}.*", sid)
    vs = vocab_sets(ctx)
    for k, allowed in vs.items():
        v = s.get(k)
        if isinstance(v, str) and v not in allowed:
            R("V-REF-04", k, f"{k} {v!r} is not in the frozen vocabulary", "one of " + ", ".join(sorted(allowed)), v)
    tags = [t for t in (s.get("unit_tags") or []) if isinstance(t, str)]
    cls = s.get("class")
    if cls == "summon" and ({"combat", "service"} & set(tags)):
        R("V-ROLE-05", "unit_tags", "a SUMMON def has neither 'combat' nor 'service'", "no combat/service", sorted({"combat", "service"} & set(tags)))
    if cls == "drone":
        for need in ("combat", "unmanned"):
            if need not in tags:
                R("V-ROLE-05", "unit_tags", f"a DRONE def carries the tags combat and unmanned; {need!r} is missing", need, tags)
        if "service" in tags:
            R("V-ROLE-05", "unit_tags", "a DRONE def is not a service unit", "no service tag", "service")
    for k in ("health", "speed_cells_s", "vision_cells", "radius_cells", "cost_credits", "build_time_s"):
        v = num(s.get(k))
        if v is None:
            continue
        if k == "speed_cells_s" and (v == 0 or s.get("movement_class") == "static"):
            continue
        if k in ("cost_credits", "build_time_s") and cls == "summon":
            continue
        lo, hi = RANGES[k]
        if not lo <= v <= hi:
            R("V-RNG-01", k, f"{k} outside the allowed range", f"{lo}..{hi}", v)
    if cls == "drone":
        for k in ("cost_credits", "build_time_s"):
            if k not in s:
                R("V-CMP-04", k, "a drone def carries the replacement cost and time", "value", "<absent>")
    ew = effective_weapons(ctx, s, weapons, R, referenced)
    if reg:
        ent = Entity("unit", list(s.get("abilities") or []), s.get("ability_params") if isinstance(s.get("ability_params"), dict) else {}, set(tags), "", "")
        resolved = resolve(reg, ent, R, ctx)
        check_ability_slots(R, resolved, ew)
        if "detector" in tags and "detector" not in resolved:
            R("V-ROLE-02", "abilities", "tag detector requires an ability of kind detector", "detector", sorted(resolved))


# ---------------------------------------------------------------------------------------------------------------- weapon instance
def check_weapon(ctx: Ctx, lf: LoadedFile, w: dict, wid: str, code: str) -> None:
    R = _Rep(ctx, lf, w, wid)
    if not wid.startswith(f"weapon.{code}."):
        R("V-SCH-03", "id", f"weapon id must start with weapon.{code}.", f"weapon.{code}.*", wid)
    an = w.get("archetype")
    a = ctx.wa.get(an) if isinstance(an, str) else None
    if isinstance(an, str) and a is None:
        R("V-REF-04", "archetype", f"weapon archetype {an!r} is not one of the 27 in global.json weapon_archetypes", "a TAXONOMY weapon archetype", an)
        return
    if a is None:
        return
    emp = an == "emp_pulse"
    dmg, rl, rg = num(w.get("damage")), num(w.get("reload_s")), num(w.get("range_cells"))
    if dmg is not None and not RANGES["damage"][0] <= dmg <= RANGES["damage"][1]:
        R("V-RNG-01", "damage", "damage outside the allowed range", "1..100000", dmg)
    if dmg is not None and dmg < 25 and not emp:
        R("V-RNG-02", "damage", "damage per hit < 25: a 10 % modifier would be quantised away (use hits_per_volley for multi-shot)", ">= 25", dmg)
    if dmg is not None and dmg > 900 and an not in ("bomb", "naval_bombard", "cruise_missile", "demolition_cannon", "artillery_shell", "missile_artillery"):
        R("V-RNG-02", "damage", "a single hit above 900 could one-shot a full-health T1 tank (documented exceptions: bombs and salvos)", "<= 900", dmg)
    lo_r, hi_r = a.get("range_cells_band", [0, 0])
    lo_l, hi_l = a.get("reload_s_band", [0, 0])
    if rl is not None and not emp:
        if not RANGES["reload_s"][0] <= rl <= RANGES["reload_s"][1]:
            R("V-RNG-01", "reload_s", "reload_s outside the allowed range", "0.05..60", rl)
        elif convert.s_to_mt(rl) < 1:
            R("V-RNG-03", "reload_s", "reload converts to < 1 milli-tick", ">= 0.001 s", rl)
        if lo_l and not lo_l * 0.9 - 1e-9 <= rl <= hi_l * 1.1 + 1e-9:
            R("V-RNG-02", "reload_s", f"reload_s outside the {an} band {lo_l}-{hi_l} s (+-10 %)", f"{lo_l * 0.9:.3g}..{hi_l * 1.1:.3g}", rl)
    if rg is not None and not emp:
        lo = 0 if lo_r < RANGES["range_cells"][0] else RANGES["range_cells"][0]
        if not lo <= rg <= RANGES["range_cells"][1]:
            R("V-RNG-01", "range_cells", "range_cells outside the allowed range", f"{lo}..60", rg)
        elif rg > 0 and convert.cells_to_units(rg) < 1:
            R("V-RNG-03", "range_cells", "range converts to < 1 unit", ">= 0.001", rg)
        if hi_r and not lo_r * 0.9 - 1e-9 <= rg <= hi_r * 1.1 + 1e-9:
            R("V-RNG-02", "range_cells", f"range_cells outside the {an} band {lo_r}-{hi_r} cells (+-10 %)", f"{lo_r * 0.9:.3g}..{hi_r * 1.1:.3g}", rg)
    for k, ak in (("splash_cells", "splash_cells"), ("scatter_cells", "scatter_cells"), ("min_range_cells", "min_range_cells"), ("splash_edge_pct", "splash_edge_pct")):
        v, base = num(w.get(k)), num(a.get(ak))
        if v is None or base is None:
            continue
        lim = 0.3 * base
        if abs(v - base) > lim + 1e-9 and k != "min_range_cells":
            R("V-RNG-02", k, f"{k} may differ from the archetype default only by +-30 %", f"{base * 0.7:.3g}..{base * 1.3:.3g}", v)
    if (w.get("ramp_seconds") or w.get("ramp_max_pct", 100) != 100) and an != "beam_thermal":
        R("V-RNG-02", "ramp_seconds", "ramp_seconds / ramp_max_pct apply to beams only", "beam_thermal", an)
    to = w.get("targets_override")
    if isinstance(to, list) and to:
        allowed = {("air",), ("air", "ground")}
        if tuple(sorted(x for x in to if isinstance(x, str))) not in {tuple(sorted(x)) for x in allowed} and set(to) != set(a.get("targets", [])):
            # narrowing to a subset of the archetype targets (Harpoon/Sea Spear 'never aircraft', Bastion 'no anti-air') is a documented case
            if not set(to) <= set(a.get("targets", [])):
                R("V-CNF-08", "targets_override", "targets_override may only narrow the archetype target set or use the documented cases (['air'], ['air','ground'])",
                  f"subset of {a.get('targets')} or the documented cases", to)
