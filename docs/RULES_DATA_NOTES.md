# Rules-data schema notes (from the RULES-DATA author; loaders and runtime MUST support these)

Files: research_effects.json, power_actions.json, zone_templates.json, faction_traits.json, neutral_structures.json (game/data/balance/). Check script: `python3 tools/py/check_rules_data.py`.

## Summary

Authored all five rules files under game/data/balance/ (40 research, 48 powers, 11 shared zone templates, 8 faction trait sets, 8 neutral entries) and tools/py/check_rules_data.py. The check runs at 0 errors. validate_balance.py --only on the five files also reports 0 errors, but it only applies common envelope, numeric-literal and sort checks to them. No superweapon file was authored; those still compile from global.json. Every bible prose number is listed in bible_numbers per entry (V-CNF-06); cost, cooldown, tier and prerequisites appear nowhere. The files were emitted by throwaway generator scripts in the scratchpad.

## Deviations / extensions vs data_balance 7.9-7.14

- research_effects.json: the named-selector block holds 10 selector.balance.* entries, not just the one in the spec. They cover collectors, ground transports, ground units, infantry, land vehicles, production structures, radar, unmanned land units, vehicles+ships and infantry+land vehicles. Powers and zones in other files use them too.
- Ability refs: the spec's ability.interceptor.ural, .arjun and .bear do not exist in ability_kinds.json. Grants use {ref: ability.interceptor.default, params: {cooldown_s, charges_n}}. regen, camouflage, relay_field, aura_regen, salvage and defense_power_reserve are also grants with {ref, params}.
- faction_traits.json: each trait has a discriminator key `encoding` (grant | player | encoded_in | text_only) and exactly one `covers` index. The `encoded_in` payload is an object holding modifier_ids, or structure_id/unit_ids plus ability and ability_ref. This spelling is not fixed by the spec. A trait entry can carry `natively_on_unit_ids` (AE salvage) and `source` (PD collector unit_overrides).
- defense_power_reserve params are reserve_s 20, recharge_s 60, continuous_power_s 60. The spec only says 'reserve 20 s, recharge 60 s continuous', so recharge_s = 60 is an assumption.
- power_actions.json target extensions: `structure_ids` and `powered_required` (own_structure target of Rapid Turnaround).
- power_actions.json zone-action extensions: `count_n`, `cluster_radius_cells`, `delay_s`, `shape` and `fizzle_if_summon_lost`. Field Repair Drop, Floating Workshop and Expeditionary Workshop use delay_s 5 (designer approach time) and fizzle_if_summon_lost. False Convoy, False Front and Feint Landing use count_n and cluster_radius_cells.
- global_effect extensions: `scope: chosen_target` (Rapid Turnaround) and `params` (Joint Landing, refresh_on_reboard false).
- mark action extensions: `find_selector` (selector.land_artillery), `bonus_from_selector` (selector.ground_combat_units), `reveal`, and `then_strike {damage_ref, pattern fixed, at marked_positions}` for Counterlaunch Plot.
- Effect extension: `on_expire: true` on `disable` (Capacitor Discharge and Software Surge: 'then cannot fire for N s').
- Effect extension: `stack_group` on `heal` and `param_mod`.
- Zone templates use `_designer_params` (underscore, so the loader ignores it). Research and power entries use `designer_params`.
- Zone geometry is designer-chosen where the bible gives none. Portable cover and infantry shelter radius is 1.2 cells (the spec example value for cover). Sensor puck hp is 60. Decoy radii are 0.6, 0.8, 0.8 and 1.5 cells. Horizon debris width is 6 cells (2 x the packet radius) and length 10.
- Han Broken Contact spawns the shared dust-screen template at 6 cells per unit position (the template radius). The bible gives no smoke radius for it.
- neutral_structures.json follows the economy spec ids and numbers, not the data 7.14 example. It holds 8 entries: 6 tech structures (civilian_garrison 2000 hp 3x3, field_hospital, harbor_terminal, observation_tower, salvage_depot, substation) plus 2 deposit kinds (salvage_field, salvage_field_rich, mirroring global.json economy.deposit). New kinds are field_hospital and harbor_terminal. New fields are `ability`, `forward_queue`, `needs_shore`, `berth` and `repair_basis_cost_credits`. The salvage depot pays periodically (reward.income_crps 5 = 50 credits per 10 s), not a one-time reward. The observation tower is expressed as sight_cells 14 with no reveal reward.
- Zone params such as unit_decoy_tags, bypass_groups and blocks_new_construction are ordinary `params` keys that the loader must convert by suffix. Boolean and string values pass through unchanged.

## Needs custom runtime handling

- Custom handling: Capacitor Discharge and Software Surge (buff then disable via on_expire); Counterlaunch Plot (mark plus strike at recorded positions); Rapid Turnaround (single chosen own structure); Field Repair Drop and Expeditionary Workshop (delivery summon, then zone, fizzle if the summon dies); Floating Workshop (zone follows the pontoon summon); Broken Contact (spawn_zone per initial position); Joint Landing (disembark condition window); Treaty Coordination and Reserve Bandwidth (param_mod overrides on relay_field/command_field with stack_group); Silent Watch and Armored Overwatch (stationary cond with for_s 0, i.e. immediate); Olm Mobile Workshop (inline zone hp 600, designer); Section Logistics regen radius 6 (designer); Sap Reserve Capacitors (player-scope param_mod).
- summon.nec.survey_drone and summon.sap.recon_balloon are not yet defined in any units sheet (WARN in the check).
- Prose numbers that are acknowledged only through bible_numbers, not encoded as leaf values: 43 (INFO count in the check). Examples are the 12 in 'falls from 12 to 9' and the shell counts of the three strike powers, which live in global.json support_power_damage.
- No Olm repair-drone-station summon exists, so olm.mobile_workshop keeps hp on its inline zone. summon.pd.decoy_transport is redundant with zone.decoy_transport and the two need reconciling.

## Cross-module requests

- Units authors (nec, sap): define summon.nec.survey_drone (sight and detect 6 cells, lifetime 15 s, shootable) and summon.sap.recon_balloon (tethered observation drone, sight and detect 6 cells, lifetime 20 s, shootable) in units_nec.json / units_sap.json. Existing summon.napc.uav, cargo_aircraft, pontoon and pd.patrol_aircraft, workshop_aircraft are already referenced.
- validate_balance.py owner: it treats the five rules files only with the common envelope, numeric-literal and sort checks. It does not check effect ops, selectors, conditions, zone refs, ability kinds or V-CNF-06. tools/py/check_rules_data.py covers those and could be folded in as V-EFF/V-REF/V-CNF-06 rules.
- validate_balance.py owner: V-SCH-07 suffix checks apply only to units_ and structures files. The rules files also carry `params` blobs (zone params, ability params) that need the same suffix enforcement.
- Loader/DefLoaderRules owner: the extensions listed under deviations are runtime-visible and need loader support or an explicit decision. They are action fields (count_n, cluster_radius_cells, delay_s, shape, fizzle_if_summon_lost), target fields (structure_ids, powered_required), global_effect `scope` and `params`, mark fields (find_selector, bonus_from_selector, reveal, then_strike), effect `on_expire`, and the trait `encoding` key.
- Units owner (pd): confirm the collector's amphibious unit_overrides come from the bible roster overrides (faction_traits.json only references them). Also decide whether summon.pd.decoy_transport is kept or dropped in favour of zone.decoy_transport.
- structures.json owner: structure.nec.relay already carries relay_field; the nec.networked_fire trait references it (structure_id plus ability_ref) and expects radius 6 and damage_bonus 10 there.
