#!/usr/bin/env python3
"""Append the structured reports of finished workflow agents to docs/DEVIATIONS.md.

usage: journal_to_deviations.py <workflow-transcript-dir> <heading> [label-prefix ...]
Only agents with a 'result' entry whose label starts with one of the prefixes (default: all) are added.
Orchestrator tool; reads ~/.claude workflow journals. Stdlib only.
"""
import ast, json, os, sys

def main():
    wf, heading, prefixes = sys.argv[1], sys.argv[2], sys.argv[3:]
    labels = {}
    for fn in os.listdir(wf):
        if fn.endswith(".meta.json"):
            labels["a" + fn.split(".")[0][7:]] = json.load(open(os.path.join(wf, fn)))["description"]
    seen, out = set(), []
    for line in open(os.path.join(wf, "journal.jsonl")):
        j = json.loads(line)
        if j.get("type") != "result":
            continue
        name = labels.get(j["agentId"], j["agentId"])
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        if name in seen:
            continue
        seen.add(name)
        d = j["result"]
        if isinstance(d, str):
            try:
                d = json.loads(d)
            except Exception:
                try:
                    d = ast.literal_eval(d)
                except Exception:
                    d = {"summary": d[:3000]}
        out.append(f"\n## {name}\n\n**Summary:** {d.get('summary', '')}\n")
        out.append("**Deviations (downstream code relies on these):**\n" + "\n".join(f"- {x}" for x in d.get("deviations", [])))
        out.append("\n**Tests:** " + str(d.get("tests", ""))[:1200])
        out.append("\n**Known gaps:**\n" + "\n".join(f"- {x}" for x in d.get("known_gaps", [])))
        out.append("\n**Cross-module requests:**\n" + "\n".join(f"- {x}" for x in d.get("cross_module_requests", [])))
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "DEVIATIONS.md")
    with open(p, "a") as f:
        f.write(f"\n# === {heading} ===\n" + "\n".join(out) + "\n")
    print("appended", len(seen), "agents:", ", ".join(sorted(seen)))

main()
