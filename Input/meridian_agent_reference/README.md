# Meridian Fracture: agent handoff

This package preserves the existing faction bible as structured data. It contains eight vanilla factions and 24 subfactions, with their lore, modifiers, units, technology, research, powers and superweapons.

## Files and authority

| File | Purpose |
| --- | --- |
| `meridian_factions.json` | Canonical agent reference. Normalized registries plus complete resolved rosters. Load this for reasoning or implementation planning. |
| `meridian_factions.md` | Complete generated reading view, organized by stable faction and roster IDs. |
| `meridian_factions.schema.json` | JSON Schema 2020-12 structural contract for the core registries. |
| `validate_reference.py` | Dependency-free checks for the schema keywords used here, references, prerequisites, inheritance and modifier targets. It is not a general-purpose JSON Schema engine. |
| `render_markdown.py` | Regenerates the Markdown view from canonical JSON. |

The earlier narrative bible and PDF remain valid design sources. Within this package, edit JSON first; Markdown and `resolved` fields are derived views. Source hashes record which draft was serialized; they are provenance, not a requirement to have the original source files present.

## Loading strategy

1. Read `metadata`, `mechanical_conventions` and the relevant shared `rules`.
2. Select a roster by its stable ID, such as `roster.napc.canada`.
3. Read that record's `resolved` object. It already contains the available combat units, service units, structures, research, three support powers, superweapon and inherited/own modifiers.
4. Retrieve only the referenced entities from their registries. Do not load all faction text into every agent's context when one roster is sufficient.
5. Use `delta` to explain differences from vanilla. Do not apply the delta again to `resolved`.

IDs are namespaced: `faction.napc`, `roster.napc.canada`, `unit.napc.narwhal_amphibious_tank`, `structure.shared.radar`, `research.napc.sealed_compartments`. Display names are labels, never lookup keys. Keep an existing ID stable when renaming an entity.

## Safe interpretation

- This is a design draft with untested balance values, not a playable engine configuration.
- `null` means unspecified. A null cost is not a free unit; a null build time is not instant production.
- Passive percentage modifiers are numeric. Apply them in the listed layers, adding percentages within a layer and multiplying across layers. Obey the final caps/floors.
- Source prose repeats the same numeric rule for traceability; do not apply it twice.
- Unit role tags make scopes explicit. The service-unit exclusions and explicit transport exceptions still apply.
- `modifier_applications` lists eligible entities, not unconditional effects. Check `conditions` and `unresolved_target_domain` before implementing a modifier.
- Conditional unit abilities, research effects, repair behavior and strategic powers retain their full prose. Exact weapon definitions, behavior code and many base stats still need design work.
- All `requires_all_structure_ids` are conjunctive prerequisites. Unit lists include the producer. Powered-prerequisite flags add an activation condition, not a new tech dependency.
- Headquarters deployment from an MCV is a separate action from the acyclic building-prerequisite graph. Do not turn it into a required unlock cycle.
- Subfactions inherit the parent's structures, service units, two shared upgrades, two shared powers and superweapon. Their own third power replaces the vanilla-only third power.
- Preserve lore and numbers unless the user's task explicitly changes the design. If prose and structured data disagree, flag the conflict instead of silently inventing a resolution.

## Minimal lookup example

Run from this directory:

```python
import json
from pathlib import Path

design = json.loads(Path("meridian_factions.json").read_text())
roster = design["rosters"]["roster.napc.canada"]
for unit_id in roster["resolved"]["combat_unit_ids"]:
    unit = design["units"][unit_id]
    print(unit_id, unit["tier"], unit["requires_all_structure_ids"])
```

## Checks and regeneration

Python 3 is sufficient; no network access or installed packages are needed.

```sh
python3 validate_reference.py
python3 render_markdown.py
```

After a roster change, update its explicit delta and rebuild its resolved lists, technology nodes and modifier applications. The validator detects stale derived data; it does not silently repair it. After changing a stable ID, update every reference before validation. Update the manifest counts only when a requested design change actually changes the required roster totals.

The initial package contains 32 playable rosters, 156 unit definitions (104 baseline combat units, 48 unique subfaction units, four shared service units), 98 typed passive modifiers, 40 research upgrades, 48 support powers and eight superweapons.
