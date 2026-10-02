#!/usr/bin/env python3
"""Generate docs/FACTIONS.md from the bible mirror game/data/bible/meridian_factions.json.

    python3 tools/py/gen_factions_doc.py            # rewrites docs/FACTIONS.md
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIBLE = ROOT / "game/data/bible/meridian_factions.json"
OUT = ROOT / "docs/FACTIONS.md"


def main() -> None:
    d = json.loads(BIBLE.read_text(encoding="utf-8"))
    units, powers, sws, rosters = d["units"], d["support_powers"], d["superweapons"], d["rosters"]
    research = d["research"]
    mods = d["modifiers"]
    o = [
        "# The eight factions",
        "",
        "> **Generated** from the bible mirror (`game/data/bible/meridian_factions.json`) by `python3 tools/py/gen_factions_doc.py`. "
        "Per-unit and per-structure numbers live in the generated [unit reference](units/README.md). The bible marks all values as a first "
        "design; the shipped numbers were tuned by AI self-play and have not been playtested by humans.",
        "",
        "## Setting",
        "",
        d["setting"]["premise"].split("\n\n")[0],
        "",
        d["setting"]["premise"].split("\n\n")[1],
        "",
        "| Period | Event |",
        "|---|---|",
    ]
    for t in d["setting"]["timeline"]:
        o.append(f"| {t['period']} | **{t['event']}**: {t['description']} |")
    o += ["", "Each faction offers a credible public good and an institutional danger. National names identify fictional successor commands; "
          "their doctrines come from reconstruction history. Every faction has a **vanilla** roster and three **subfaction** rosters; "
          "a subfaction changes one thing about the parent (a modifier, one replaced unit, one exclusive research or power), "
          "so a roster is always one of 32 choices.", ""]
    for fid, f in d["factions"].items():
        code = f["code"].lower()
        o += [f"## {f['name']} ({f['code']})", "", f"*\"{f['motto']}\"*", "",
              f"**Doctrine.** {f['identity']}", "", f"**Look.** {f['visual_direction']}", "", f"**Lore.** {f['lore']}", "", "**Traits.**", ""]
        for t in f["traits_text"]:
            o.append(f"- {t}")
        o += ["", f"**Opening.** {f['opening']}", "", f"**Counterplay.** {f['counterplay']}", ""]
        sw = sws[f["superweapon_id"]]
        o += [f"**Superweapon: {sw['name']}** (recharge {sw['recharge_seconds']} s, warning {sw['warning_seconds']} s). {sw['effect_text']} "
              f"*Counterplay:* {sw['counterplay']}", ""]
        shared_pw = [powers[p]["name"] for p in f["shared_support_power_ids"] if p in powers]
        van_pw = powers.get(f["vanilla_only_support_power_id"], {}).get("name", "")
        shared_rs = [research[r]["name"] for r in f["shared_research_ids"] if r in research]
        o += [f"**Support powers.** {', '.join(shared_pw)} (all rosters); {van_pw} (vanilla roster only).", "",
              f"**Shared research.** {', '.join(shared_rs)}.", "", "**Rosters.**", "",
              "| Roster | Identity | Change |", "|---|---|---|"]
        for rid in [f["vanilla_roster_id"]] + f["subfaction_roster_ids"]:
            r = rosters[rid]
            ch = []
            ch += [m.rstrip(".") for m in r.get("modifiers_text", [])]
            for rep in r["delta"].get("replacements", []):
                a = units[rep["replaced_unit_id"]]["name"]
                b = units[rep["replacement_unit_id"]]["name"]
                ch.append(f"{b} replaces {a}")
            if r.get("exclusive_research_id"):
                ch.append(f"research {research[r['exclusive_research_id']]['name']}")
            if r.get("exclusive_support_power_id") and r["kind"] != "vanilla":
                ch.append(f"power {powers[r['exclusive_support_power_id']]['name']}")
            title = "Vanilla" if r["kind"] == "vanilla" else r["title"]
            o.append(f"| {title} | {r['identity']} | {'; '.join(ch) if ch else 'Baseline roster'} |")
        o += ["", f"Full stats: [{f['code']} unit reference](units/{code}.md); bible digest: [factions/{code}.md](factions/{code}.md).", ""]
    OUT.write_text("\n".join(o), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
