"""Regenerate the agent Markdown snapshot from canonical JSON; standard library only."""
from pathlib import Path
import json

HERE=Path(__file__).resolve().parent
def table(headers,rows):
    def clean(x):return str(x).replace('|','/').replace('\n',' ')
    return '\n'.join(['| '+' | '.join(headers)+' |','| '+' | '.join(['---']*len(headers))+' |']+
                     ['| '+' | '.join(clean(x) for x in row)+' |' for row in rows])+'\n'
def ids(items):return ', '.join('`'+x+'`' for x in items)

def render(d):
    m=['# Meridian Fracture - agent reference\n',
       'Schema version: `1.0.0`. Design version: `0.1`. Status: **draft, not playtested**. This file is generated from `meridian_factions.json`; edit JSON first and regenerate this view.\n',
       '## Agent contract\n',
       '- Use stable IDs as keys; display names may change.\n- Read the chosen roster under `rosters` and use its `resolved` lists. Do not re-add replaced units or the vanilla-only third power.\n- Numeric parent and subfaction modifiers are encoded once in `modifiers`. Source prose restates those rules; never count it as an extra bonus.\n- Treat `null` as unspecified. Do not invent costs, health, weapons or unit build times.\n- Treat conditional abilities, research effects and support-power effects as normative prose that still needs implementation design.\n- Apply explicit terrain/state conditions. A conditional target list does not make a modifier unconditional.\n- Preserve established lore and balance values unless the user requests a design change.\n- After editing, rebuild affected `resolved` records, run `validate_reference.py`, then run `render_markdown.py`.\n',
       '## Setting\n'+d['setting']['premise']+'\n',
       table(['Period','Event','Description'],[(x['period'],x['event'],x['description']) for x in d['setting']['timeline']]),
       '## Roster index\n',
       table(['ID','Faction','Roster','Doctrine'],[(rid,d['factions'][r['faction_id']]['name'],r['name'],r['identity']) for rid,r in d['rosters'].items()]),
       '## Shared rules\n']
    for rid,r in d['rules'].items():m += [f"### {rid} | {r['title']}\n\n{r['text']}\n"]
    m += ['## Mechanical conventions\n','```json\n'+json.dumps(d['mechanical_conventions'],indent=2)+'\n```\n',
          '## Building registry\n',
          table(['ID / name','Credits','Power supply delta','Build seconds','Prerequisites / conditions','Function'],
                [(sid+' / '+s['name'],s['cost_credits'],s['power_supply_delta'],s['build_time_seconds'] if s['build_time_seconds'] is not None else 'unspecified',
                  ', '.join(s['requires_all_structure_ids'])+'; '+' '.join(s['conditions']),s['description']) for sid,s in d['structures'].items()]),
          'The starting Headquarters is supplied. Other Headquarters deploy from an MCV; the deployment edge is separate from building prerequisites. Positive power supplies capacity, negative power consumes it.\n',
          '## Shared service units\n']
    for uid,u in d['units'].items():
        if u['roster_class']=='service':
            m += [f"### {uid} | {u['name']}\n\nRequires {ids(u['requires_all_structure_ids'])}. Cost: {u['base_stats']['cost_credits']} credits.\n\n{u['role_and_abilities']}\n"]
    def mods(modids):
        return table(['Modifier ID','Layer','Stat','Delta percent','Selector','Conditions / source'],[
            (mid,d['modifiers'][mid]['layer'],d['modifiers'][mid]['stat'],f"{d['modifiers'][mid]['delta_percent']:+g}",
             d['modifiers'][mid]['selector_id'],d['modifiers'][mid]['source_text']) for mid in modids])
    def unit_rows(unitids,with_roles=True):
        headers=['Unit ID / name','Tier','Requires all structures']+(['Role / abilities'] if with_roles else [])
        rows=[]
        for uid in unitids:
            u=d['units'][uid]
            row=[uid+' / '+u['name'],u['tier'],', '.join(u['requires_all_structure_ids'])]
            if with_roles:row.append(u['role_and_abilities'])
            rows.append(row)
        return table(headers,rows)
    def research(uid):
        u=d['research'][uid]
        return f"**{uid} | {u['name']}** - T{u['tier']}; {u['cost_credits']} credits; {u['research_time_seconds']} seconds; requires {ids(u['requires_all_structure_ids'])}.\n\n{u['effect_text']}\n"
    def power(pid):
        p=d['support_powers'][pid]
        return f"**{pid} | {p['name']}** - T{p['tier']}; {p['cost_credits']} credits per use; {p['cooldown_seconds']} seconds cooldown; requires powered {ids(p['requires_all_structure_ids'])}.\n\n{p['effect_text']}\n"
    for fid,f in d['factions'].items():
        vanilla=d['rosters'][f['vanilla_roster_id']]
        m += [f"## {fid} | {f['name']}\n\n*{f['motto']}*\n\n{f['lore']}\n\n**Doctrine:** {f['identity']}\n\n**Visual direction:** {f['visual_direction']}\n",
              '### Inherited traits\n'+'\n'.join('- '+x for x in f['traits_text'])+'\n',mods(f['passive_modifier_ids']),
              f"### {f['vanilla_roster_id']} | Vanilla technology tree\n",unit_rows(f['baseline_combat_unit_ids']),
              '**Service units:** '+ids(vanilla['resolved']['service_unit_ids'])+'.\n\n**Buildings:** '+ids(f['structure_ids'])+'.\n',
              '### Inherited research\n']
        for uid in f['shared_research_ids']:m.append(research(uid))
        m.append('### Inherited support powers\n')
        for pid in f['shared_support_power_ids']:m.append(power(pid))
        m += ['### Vanilla-only third power\n',power(f['vanilla_only_support_power_id'])]
        sid=f['superweapon_id'];s=d['superweapons'][sid]
        m += [f"### {sid} | {s['name']}\n\nLauncher: `{s['launcher_structure_id']}`. Recharge: {s['recharge_seconds']} seconds. Warning: {s['warning_seconds']} seconds. Starts empty; maximum one stored charge.\n\n{s['effect_text']}\n\n**Counterplay:** {s['counterplay']}\n",
              f"**Vanilla opening:** {f['opening']}\n\n**Fight this faction:** {f['counterplay']}\n"]
        if vanilla['resolved']['unit_overrides']:
            m += ['**Roster-specific service overrides:**\n\n```json\n'+json.dumps(vanilla['resolved']['unit_overrides'],indent=2)+'\n```\n']
        for rid in f['subfaction_roster_ids']:
            r=d['rosters'][rid];rr=r['resolved']
            m += [f"### {rid} | {r['name']} - {r['title']}\n\nParent: `{r['parent_roster_id']}`.\n\n{r['lore']}\n\n**Doctrine:** {r['identity']}\n",mods(r['own_modifier_ids']),
                  '#### Exact roster changes\n',table(['Replaced ID','Unique replacement ID'],[(x['replaced_unit_id'],x['replacement_unit_id']) for x in r['delta']['replacements']]),
                  '**Removed without replacement:** '+ids(r['delta']['removed_without_replacement_unit_ids'])+'.\n',
                  '#### Unique unit definitions\n',unit_rows([x['replacement_unit_id'] for x in r['delta']['replacements']]),
                  '#### Complete resolved combat tree\n',unit_rows(rr['combat_unit_ids'],False),
                  '**Service units:** '+ids(rr['service_unit_ids'])+'. All parent structures remain.\n',
                  '**Inherited research:** '+ids(f['shared_research_ids'])+'.\n',research(r['exclusive_research_id']),
                  '**Inherited support powers:** '+ids(f['shared_support_power_ids'])+'.\n',power(r['exclusive_support_power_id']),
                  '**Unavailable vanilla-only power:** '+ids(r['delta']['unavailable_support_power_ids'])+'.\n',
                  '**Inherited superweapon:** `'+rr['superweapon_id']+'`. '+r['superweapon_note']+'\n',
                  f"**Opening:** {r['opening']}\n\n**Counterplay:** {r['counterplay']}\n"]
    m += ['## Modifier selector registry\n',
          'Selectors are unions across entity kinds, with all-tag, any-tag and exclusion filters. Explicit ID lists further restrict selection. The JSON contains resolved eligible target IDs for each roster. Conditions still apply at runtime. Weapon/projectile domains without final specifications remain explicitly unresolved.\n',
          table(['Selector ID','Entity kinds','All tags','Any tags','Excluded tags','Explicit IDs','Conditions / unresolved domains'],
                [(sid,', '.join(s['entity_kinds']),', '.join(s['all_tags']),', '.join(s['any_tags']),', '.join(s['exclude_tags']),
                  ', '.join(s['explicit_entity_ids']),'; '.join(s['conditions'])+' '+(s['unresolved_target_domain'] or '')+
                  (' Also applies to '+', '.join(s['additional_superweapon_ids']) if s['additional_superweapon_ids'] else '')) for sid,s in d['selectors'].items()]),
          '## Campaign fault lines\n']
    for x in d['setting']['campaign_fault_lines']:m += [f"### {x['id']} | {x['parties']}\n\n{x['description']}\n"]
    m += ['## Prototype priorities\n']+[f'{i}. {s}\n' for i,s in enumerate(d['prototype_priorities'],1)]
    m += ['## Deliberately unspecified\n']+['- '+x+'\n' for x in d['metadata']['known_unknowns']]
    return '\n'.join(m)

if __name__=='__main__':
    d=json.loads((HERE/'meridian_factions.json').read_text())
    out=HERE/'meridian_factions.md';out.write_text(render(d),encoding='utf-8')
    print('Wrote',out.name)
