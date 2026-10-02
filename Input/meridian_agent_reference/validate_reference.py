"""Validate the package's schema subset, cross-references and resolved inheritance.
Standard library only: python3 validate_reference.py [path/to/meridian_factions.json]
"""
from pathlib import Path
import argparse, collections, json, re, sys

def require(condition,message):
    if not condition:raise ValueError(message)

def validate_schema(value,schema,root,path='$'):
    """Implements the assertion keywords used by this package, not all JSON Schema."""
    supported={'$schema','$id','$defs','$ref','title','description','type','enum','const','required','properties','additionalProperties',
               'propertyNames','items','uniqueItems','minimum','maximum','exclusiveMinimum','pattern','minItems','maxItems'}
    require(not(set(schema)-supported),f'{path}: unsupported schema keywords: {set(schema)-supported}')
    if '$ref' in schema:
        ref=schema['$ref'];require(ref.startswith('#/'),f'{path}: only local schema references are supported')
        target=root
        for part in ref[2:].split('/'):target=target[part.replace('~1','/').replace('~0','~')]
        return validate_schema(value,target,root,path)
    def istype(t):
        return {'object':isinstance(value,dict),'array':isinstance(value,list),'string':isinstance(value,str),
                'number':isinstance(value,(int,float)) and not isinstance(value,bool),'integer':isinstance(value,int) and not isinstance(value,bool),
                'boolean':isinstance(value,bool),'null':value is None}[t]
    if 'type' in schema:
        types=schema['type'] if isinstance(schema['type'],list) else [schema['type']]
        require(any(istype(t) for t in types),f'{path}: expected {types}, got {type(value).__name__}')
    if 'const' in schema:
        expected=schema['const']
        require(value==expected and (isinstance(value,bool)==isinstance(expected,bool)),f'{path}: expected constant {expected!r}')
    if 'enum' in schema:require(value in schema['enum'],f'{path}: not in enum')
    if isinstance(value,str) and 'pattern' in schema:require(re.search(schema['pattern'],value) is not None,f'{path}: pattern mismatch')
    if isinstance(value,(float,int)) and not isinstance(value,bool):
        if 'minimum' in schema:require(value>=schema['minimum'],f'{path}: below minimum')
        if 'maximum' in schema:require(value<=schema['maximum'],f'{path}: above maximum')
        if 'exclusiveMinimum' in schema:require(value>schema['exclusiveMinimum'],f'{path}: at or below exclusive minimum')
    if isinstance(value,dict):
        require(set(schema.get('required',[]))<=set(value),f'{path}: missing required fields {set(schema.get("required",[]))-set(value)}')
        props=schema.get('properties',{})
        for k,v in value.items():
            if 'propertyNames' in schema:validate_schema(k,schema['propertyNames'],root,path+'.<key>')
            if k in props:validate_schema(v,props[k],root,path+'.'+k)
            elif schema.get('additionalProperties') is False:raise ValueError(f'{path}: unexpected field {k}')
            elif isinstance(schema.get('additionalProperties'),dict):validate_schema(v,schema['additionalProperties'],root,path+'.'+k)
    if isinstance(value,list):
        if schema.get('uniqueItems'):require(len({json.dumps(x,sort_keys=True) for x in value})==len(value),f'{path}: duplicate items')
        if 'minItems' in schema:require(len(value)>=schema['minItems'],f'{path}: too few items')
        if 'maxItems' in schema:require(len(value)<=schema['maxItems'],f'{path}: too many items')
        if 'items' in schema:
            for i,v in enumerate(value):validate_schema(v,schema['items'],root,f'{path}[{i}]')

REGISTRIES=('rules','selectors','structures','units','modifiers','research','support_powers','superweapons','factions','rosters')

def validate_semantics(d):
    allids={}
    for reg in REGISTRIES:
        for ident in d[reg]:
            require(ident not in allids,f'Duplicate ID {ident}');allids[ident]=reg
    def refs(x,path='$'):
        if isinstance(x,dict):
            for k,v in x.items():
                if k.endswith('_id') and v is not None:require(v in allids,f'{path}.{k}: missing reference {v}')
                elif k.endswith('_ids'):
                    for ref in v:require(ref in allids,f'{path}.{k}: missing reference {ref}')
                refs(v,path+'.'+k)
        elif isinstance(x,list):
            for i,v in enumerate(x):refs(v,f'{path}[{i}]')
    refs(d)
    # Only building prerequisites are acyclic. HQ deployment from an MCV is a separate action.
    seen=set();active=set()
    def walk(bid):
        require(bid not in active,f'Building prerequisite cycle at {bid}')
        if bid in seen:return
        active.add(bid)
        for dep in d['structures'][bid]['requires_all_structure_ids']:
            require(dep in d['structures'],f'{bid}: non-structure prerequisite {dep}');walk(dep)
        active.remove(bid);seen.add(bid)
    for bid in d['structures']:walk(bid)
    classes=collections.Counter(x['roster_class'] for x in d['units'].values())
    kinds=collections.Counter(x['kind'] for x in d['rosters'].values())
    counts={'factions':len(d['factions']),'rosters':len(d['rosters']),'vanilla_rosters':kinds['vanilla'],
            'subfaction_rosters':kinds['subfaction'],'baseline_combat_units':classes['baseline_combat'],
            'unique_subfaction_units':classes['unique_subfaction'],'service_units':classes['service'],
            'support_powers':len(d['support_powers']),'research_upgrades':len(d['research']),'superweapons':len(d['superweapons'])}
    require(counts==d['metadata']['expected_counts'],f'Counts differ from the design manifest: {counts}')
    for fid,f in d['factions'].items():
        require(len(f['subfaction_roster_ids'])==3,f'{fid}: expected three subfactions')
        require(len(f['shared_research_ids'])==2 and len(f['shared_support_power_ids'])==2,f'{fid}: shared research/power count')
        for uid in f['baseline_combat_unit_ids']:
            require(d['units'][uid]['faction_id']==fid and d['units'][uid]['roster_class']=='baseline_combat',f'{fid}: foreign or non-baseline unit {uid}')
        for rid in [f['vanilla_roster_id']]+f['subfaction_roster_ids']:
            require(d['rosters'][rid]['faction_id']==fid,f'{fid}: foreign roster {rid}')
        require(f['superweapon_id'] in d['superweapons'],f'{fid}: incorrect superweapon reference type')
    for uid,u in d['units'].items():
        expect=[u['producer_structure_id']]+d['mechanical_conventions']['tier_requirements'][str(u['tier'])]
        require(u['requires_all_structure_ids']==expect,f'{uid}: incorrect tier prerequisites')
    for registry in ('research','support_powers'):
        for ident,x in d[registry].items():
            require(x['requires_all_structure_ids']==d['mechanical_conventions']['tier_requirements'][str(x['tier'])],f'{ident}: incorrect tier prerequisites')
    for rid,r in d['rosters'].items():
        f=d['factions'][r['faction_id']];rr=r['resolved'];delta=r['delta']
        expected=list(f['baseline_combat_unit_ids'])
        research=list(f['shared_research_ids']);mods=list(f['passive_modifier_ids'])
        if r['kind']=='subfaction':
            require(r['parent_roster_id']==f['vanilla_roster_id'],f'{rid}: wrong parent')
            require(len(delta['replacements'])==2 and len(delta['removed_without_replacement_unit_ids'])==1,f'{rid}: incorrect roster trade')
            replace={x['replaced_unit_id']:x['replacement_unit_id'] for x in delta['replacements']}
            removed=set(delta['removed_without_replacement_unit_ids'])
            require(not removed & set(replace),f'{rid}: replacement is also removed')
            require(set(replace)|removed<=set(expected),f'{rid}: changes a unit outside the parent roster')
            for old,new in replace.items():
                require(d['units'][new]['replaces_unit_id']==old,f'{rid}: replacement provenance mismatch')
                require(d['units'][new]['introduced_by_roster_id']==rid,f'{rid}: replacement belongs to another roster')
            expected=[replace.get(x,x) for x in expected if x not in removed]
            research.append(r['exclusive_research_id']);mods+=r['own_modifier_ids']
            require(delta['unavailable_support_power_ids']==[f['vanilla_only_support_power_id']],f'{rid}: vanilla-only power not excluded')
        else:
            require(not delta['replacements'] and not delta['removed_without_replacement_unit_ids'],f'{rid}: vanilla cannot have unit deltas')
        require(rr['combat_unit_ids']==expected,f'{rid}: stale resolved combat roster')
        require(rr['research_ids']==research,f'{rid}: stale resolved research')
        require(rr['modifier_ids']==mods,f'{rid}: stale resolved modifiers')
        require(rr['support_power_ids']==f['shared_support_power_ids']+[r['exclusive_support_power_id']],f'{rid}: stale support-power inheritance')
        require(rr['superweapon_id']==f['superweapon_id'],f'{rid}: wrong superweapon')
        require(rr['structure_ids']==f['structure_ids'],f'{rid}: wrong structure inheritance')
        require(set(rr['service_unit_ids'])=={u for u,v in d['units'].items() if v['roster_class']=='service'},f'{rid}: missing service unit')
        require(set(rr['unit_overrides'])<=set(rr['combat_unit_ids']+rr['service_unit_ids']),f'{rid}: override of unavailable unit')
        unlocked=set(rr['structure_ids'])
        for registry,ids in [('units',rr['combat_unit_ids']+rr['service_unit_ids']),('research',rr['research_ids']),('support_powers',rr['support_power_ids'])]:
            for ident in ids:require(set(d[registry][ident]['requires_all_structure_ids'])<=unlocked,f'{rid}: inaccessible {ident}')
        nodes=[{'unit_id':uid,'producer_structure_id':d['units'][uid]['producer_structure_id'],'requires_all_structure_ids':d['units'][uid]['requires_all_structure_ids']} for uid in rr['combat_unit_ids']+rr['service_unit_ids']]
        require(rr['technology_nodes']==nodes,f'{rid}: stale resolved technology nodes')
        require([x['modifier_id'] for x in rr['modifier_applications']]==mods,f'{rid}: incomplete modifier applications')
        for app in rr['modifier_applications']:
            sel=d['selectors'][d['modifiers'][app['modifier_id']]['selector_id']]
            expected_targets={'unit':[],'structure':[]}
            for kind,registry,ids in [('unit','units',rr['combat_unit_ids']+rr['service_unit_ids']),('structure','structures',rr['structure_ids'])]:
                for ident in ids:
                    tags=set(d[registry][ident]['tags'])
                    if kind=='unit':tags.update(rr['unit_overrides'].get(ident,{}).get('add_tags',[]))
                    if (kind in sel['entity_kinds'] and (not sel['explicit_entity_ids'] or ident in sel['explicit_entity_ids'])
                        and set(sel['all_tags'])<=tags and (not sel['any_tags'] or set(sel['any_tags'])&tags) and not set(sel['exclude_tags'])&tags):
                        expected_targets[kind].append(ident)
            require(app['eligible_unit_ids']==expected_targets['unit'] and app['eligible_structure_ids']==expected_targets['structure'],f'{rid}: stale modifier targets {app["modifier_id"]}')
            require(app['conditions']==sel['conditions'],f'{rid}: modifier conditions drift')
            require(app['eligible_superweapon_ids']==[x for x in sel['additional_superweapon_ids'] if x==rr['superweapon_id']],f'{rid}: stale superweapon modifier targets')
            require(app['unresolved_target_domain']==sel['unresolved_target_domain'],f'{rid}: unresolved-domain annotation drift')
    return counts

def main():
    parser=argparse.ArgumentParser();parser.add_argument('reference',nargs='?',type=Path,default=Path(__file__).with_name('meridian_factions.json'))
    args=parser.parse_args();d=json.loads(args.reference.read_text());schema=json.loads(args.reference.with_name('meridian_factions.schema.json').read_text())
    validate_schema(d,schema,schema);counts=validate_semantics(d)
    print(json.dumps({'status':'valid','checks':['schema','ID references','building dependency graph','tier prerequisites','roster inheritance','modifier targets'],'counts':counts},indent=2))

if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,FileNotFoundError) as e:
        print('INVALID: '+str(e),file=sys.stderr);sys.exit(1)
