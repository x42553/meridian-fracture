"""Findings, severities and the rule table of validate_balance.py (spec data_balance 5.12)."""
from __future__ import annotations

from dataclasses import dataclass, field

E, W, I = "E", "W", "I"
SEV_NAME = {E: "ERROR", W: "WARN", I: "INFO"}

# rule id -> (default severity, one-line check, ext).  ext=True marks ids that are validator extensions (not in spec 5.12).
RULES: dict[str, tuple[str, str, bool]] = {
    "V-SCH-01": (E, "manifest lists exactly the expected files; every file exists, is strict JSON, an object, and carries schema == meridian.balance.<name>/1", False),
    "V-SCH-02": (E, "unknown key (typo protection) outside params/ability_params, or a duplicate key in a JSON object", False),
    "V-SCH-03": (E, "id shape ^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$, right kind prefix / file code, no duplicate id across files", False),
    "V-SCH-04": (E, "numeric literal with > 3 decimals, NaN/inf, or |x| >= 2^40", False),
    "V-SCH-05": (E, "integer-typed field (credits, hp, counts, tier, pads ...) not integral", False),
    "V-SCH-06": (E, "_pct value with > 2 decimals, or a delta <= -100 %", False),
    "V-SCH-07": (E, "numeric key inside a free-form params object without a recognised unit suffix", False),
    "V-SCH-08": (E, "tag name not [a-z][a-z0-9_]*, or > 62 tags in the unit-tag namespace", False),
    "V-SCH-09": (W, "entries inside a file are not sorted by id (diff-stability lint)", False),
    "V-SCH-10": (E, "wrong JSON type / shape / length for a field (generic schema conformance)", True),
    "V-REF-01": (E, "a referenced id (weapon, unit, structure, summon, zone ...) does not exist", False),
    "V-REF-02": (E, "kind mismatch (drone_id -> non-drone, summon_id -> non-summon)", False),
    "V-REF-03": (W, "orphan: weapon instance / summon not referenced", False),
    "V-REF-04": (E, "archetype / armor / size / movement class / layer / damage type / ability name / flag not in global.json or the registries", False),
    "V-CMP-01": (E, "every bible unit of the file's faction has exactly one entry; no entry for unknown ids or for other factions", False),
    "V-CMP-02": (E, "the 29 bible structures <-> structures.json (exactly once) and every structure maps to a global.json structures/defenses key", False),
    "V-CMP-04": (E, "required sheet field missing after role-archetype / service_units defaults (cost, build time, health, classes, speed, vision, radius; weapon archetype damage reload_s range_cells)", False),
    "V-CMP-05": (E, "armed/unarmed: the 10 unarmed bible units (or units tagged no_gun) have no weapons; every other combat unit has >= 1", False),
    "V-CNF-01": (E, "balance value differs from a non-null bible value (tier, cost, base_stats ...)", False),
    "V-CNF-02": (I, "balance repeats an equal bible value (warning with --strict-redundant)", False),
    "V-CNF-03": (E, "tags_add contains a locked selector tag or a bible tag the unit does not have", False),
    "V-CNF-04": (E, "balance sets a bible-only field (prerequisites, producer, faction membership, structure cost/power/tags ...)", False),
    "V-CNF-05": (E, "global.json vocabulary differs from the frozen TAXONOMY/DefEnums vocabulary, or a bible-fixed constant (structure/service-unit cost, build time, power) differs from the bible", False),
    "V-CNF-08": (E, "weapon instance overrides an archetype-locked field (damage_type, fire_mode, projectile kind, interceptable_by) or targets_override outside the layer set", False),
    "V-CNF-09": (W, "two sources set the same field with different values (structures.json vs global.json ...); error with --strict", False),
    "V-RNG-01": (E, "value outside the shared RANGES table (balance_lib/ranges.py)", False),
    "V-RNG-02": (W, "fair-cost / stat-band outlier vs the role archetype, or weapon numbers outside the archetype band", False),
    "V-RNG-03": (E, "non-zero converted speed < 1 upt, range < 1 u, duration < 1 t, reload_mt < 1", False),
    "V-RNG-04": (E, "damage matrix incomplete (7 x 11) or outside 0-300 %", False),
    "V-RNG-05": (E, "movement table incomplete (9 x 8), or violates the class rules (static 0, air > 0, naval, foot/wheeled/tracked on deep/cliff)", False),
    "V-RNG-06": (W, "derived helper (dps_vs_primary / range_cells) deviates > 1 % from the recomputed value", True),
    "V-WAIVER-01": (W, "balance_lib/waivers.json: a waiver is stale (matches no finding) or lacks rule / id / reason", False),
    "V-TIER-01": (E, "requires_all_structure_ids == [producer] + tier_requirements[tier] (units, research, powers)", False),
    "V-TIER-02": (E, "structure prerequisite graph is acyclic; HQ has no prerequisites", False),
    "V-TIER-03": (E, "land-only playability: no non-naval unit/structure/research/power needs structure.shared.dock", False),
    "V-TIER-05": (W, "within a faction and role tag, cost / build time non-decreasing with tier", False),
    "V-ROLE-01": (E, "tag => capability: anti_air => air weapon, anti_submarine => underwater weapon, artillery => indirect weapon, anti_tank/ground_attack => ground weapon", False),
    "V-ROLE-02": (E, "tag => ability: detector transport carrier command collector construction capture repair electronic_warfare submarine", False),
    "V-ROLE-03": (E, "tag => movement/layer: infantry foot, ship naval|submerged, aircraft air_*, amphibious, land_vehicle wheeled/tracked/amphibious, ground => ground layer", False),
    "V-ROLE-05": (E, "summon/drone/service tag rules (summon: no combat/service; drone: combat + unmanned; service: service, not combat)", False),
    "V-ABL-01": (E, "ability kind/template/alias known, kind valid for the scope, required params present, unknown params rejected, types and ranges", False),
    "V-ABL-02": (E, "at most one ability per kind per def (two explicit entries of one kind)", False),
    "V-ABL-03": (E, "deploy / mode_switch weapon slot indices valid, weapon.modes consistent with the mode_switch modes", False),
    "V-ABL-04": (E, "carrier drone_id is a drone summon; zone-based abilities reference a zone of the right kind", False),
    "V-ABL-05": (W, "sheet <-> global.json unit_assignments: archetype equal, ability names agree, style tags known, tier override equal", False),
}


@dataclass
class Finding:
    rule: str
    severity: str
    file: str
    message: str
    line: int = 0
    entity: str = ""
    field: str = ""
    expected: str = ""
    found: str = ""

    def text(self) -> str:
        loc = f"{self.file}:{self.line}" if self.line else self.file
        where = ".".join(x for x in (self.entity, self.field) if x)
        s = f"{SEV_NAME[self.severity]:5} {self.rule} {loc}" + (f" [{where}]" if where else "") + f": {self.message}"
        if self.expected or self.found:
            s += f" (expected: {self.expected or '-'}; found: {self.found or '-'})"
        return s

    def as_dict(self) -> dict:
        return {"rule": self.rule, "severity": SEV_NAME[self.severity], "where": self.file, "line": self.line, "entity": self.entity,
                "field": self.field, "message": self.message, "expected": self.expected, "found": self.found}


@dataclass
class Report:
    findings: list[Finding] = field(default_factory=list)
    strict: bool = False
    strict_redundant: bool = False

    def add(self, rule: str, file: str, message: str, *, line: int = 0, entity: str = "", field: str = "", expected: object = "", found: object = "",
            sev: str | None = None) -> None:
        s = sev or RULES[rule][0]
        if rule == "V-CNF-09" and self.strict and sev is None:
            s = E
        if rule == "V-CNF-02" and self.strict_redundant:
            s = W
        self.findings.append(Finding(rule, s, file, message, line, entity, field, _s(expected), _s(found)))

    def count(self, sev: str) -> int:
        return sum(1 for f in self.findings if f.severity == sev)

    def exit_code(self) -> int:
        if self.count(E):
            return 1
        if self.strict and self.count(W):
            return 2
        return 0


def _s(v: object) -> str:
    if isinstance(v, str):
        return v
    if v is None:
        return "null"
    if isinstance(v, float) and v.is_integer():
        return repr(v)
    if isinstance(v, (list, tuple, dict)):
        t = str(list(v) if isinstance(v, tuple) else v).replace("'", '"')
        return t if len(t) <= 80 else t[:77] + "..."
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)
