class_name DefEconomy
extends RefCounted
## Global rule constants (data_balance 4.2): economy, repair, research, floors/caps, vision, combat globals. Every
## field is an int with the runtime-suffixed name. Defaults = the bible-fixed / current `global.json` values, so a
## bare DefEconomy.new() is a valid table for tests; `from_global` reads them from the files (P2) and verifies the
## bible-fixed ones (V-CNF-05).

# rules
var start_cr: int = 7500
var unit_cap_n: int = 150
var queue_length_n: int = 5
var build_radius_u: int = 8192
var power_shortage_rate_bp: int = 5000
var cancel_refund_bp: int = 10000
var sell_refund_bp: int = 5000
# harvest
var collector_capacity_cr: int = 600
var harvest_mcpt: int = 1000
var unload_mcpt: int = 6000
var unload_overhead_t: int = 40
var refinery_free_collectors_n: int = 1
var deposit_cr_per_cell: int = 600
var deposit_rich_cr_per_cell: int = 1200
# repair
var repair_rate_bps: int = 100
var repair_cost_bp: int = 5000
var regen_out_of_combat_t: int = 120
# research
var research_tier2_t: int = 900
var research_tier3_t: int = 1500
# floors / caps
var floor_cost_bp: int = 6000
var floor_build_bp: int = 6000
var floor_reload_bp: int = 5000
var floor_rearm_bp: int = 5000
var resist_cap_bp: int = 5000
var min_damage: int = 1
# vision
var detector_default_radius_u: int = 5120
var watchtower_detect_u: int = 4096
var aa_battery_detect_u: int = 5120
var camouflage_default_delay_t: int = 120
# combat
var suppress_hits_n: int = 3
var suppress_window_t: int = 40
var suppress_slow_bp: int = 2500
var suppress_t: int = 60
var cover_build_t: int = 80
var cover_life_t: int = 900
var cover_resist_bp: int = 2000
var wreck_life_t: int = 1200
var salvage_t: int = 160
var salvage_payout_bp: int = 2000
var sub_surface_t: int = 160
var garrison_squads_n: int = 4
var transport_default_squads_n: int = 2
var intercept_packet_charges_n: int = 8
var intercept_packet_reduction_bp: int = 5000


## Reads `production`, `economy`, `detection`, `resistance_rules` of global.json, then overwrites/verifies the
## bible-fixed values from `mechanical_conventions` (floors, cap, shortage, research times, start credits).
static func from_global(g: Dictionary, bible: Dictionary, rep: DefLoadReport) -> DefEconomy:
	var e: DefEconomy = DefEconomy.new()
	var prod: Dictionary = g.get("production", {})
	var eco: Dictionary = g.get("economy", {})
	var col: Dictionary = eco.get("collector", {})
	var dep: Dictionary = eco.get("deposit", {})
	var rep_d: Dictionary = eco.get("repair", {})
	var det: Dictionary = g.get("detection", {})
	var rr: Dictionary = g.get("resistance_rules", {})
	var ctx: String = "global.json"
	e.start_cr = _whole(eco, "start_credits", e.start_cr, ctx, rep)
	e.queue_length_n = _whole(prod, "queue_length", e.queue_length_n, ctx, rep)
	e.build_radius_u = _cells(eco, "build_radius_cells", e.build_radius_u, ctx, rep)
	e.power_shortage_rate_bp = _pct(prod, "power_shortage_speed_pct", e.power_shortage_rate_bp, ctx, rep)
	e.sell_refund_bp = _pct(eco, "sell_refund_pct", e.sell_refund_bp, ctx, rep)
	e.collector_capacity_cr = _whole(col, "capacity_credits", e.collector_capacity_cr, ctx, rep)
	var hc: int = _whole(col, "harvest_credits_per_pulse", 1, ctx, rep)
	var ht: int = maxi(1, _whole(col, "harvest_pulse_ticks", 1, ctx, rep))
	e.harvest_mcpt = hc * 1000 / ht
	var uc: int = _whole(col, "unload_credits_per_pulse", 6, ctx, rep)
	var ut: int = maxi(1, _whole(col, "unload_pulse_ticks", 1, ctx, rep))
	e.unload_mcpt = uc * 1000 / ut
	e.unload_overhead_t = _whole(col, "unload_overhead_ticks", e.unload_overhead_t, ctx, rep)
	e.deposit_cr_per_cell = _whole(dep, "credits_per_cell", e.deposit_cr_per_cell, ctx, rep)
	e.deposit_rich_cr_per_cell = _whole(dep, "rich_credits_per_cell", e.deposit_rich_cr_per_cell, ctx, rep)
	e.repair_rate_bps = _whole(rep_d, "engineer_pct_per_s_x100", e.repair_rate_bps, ctx, rep)
	e.repair_cost_bp = _pct(rep_d, "full_repair_cost_pct_of_price", e.repair_cost_bp, ctx, rep)
	e.floor_cost_bp = _pct(prod, "cost_floor_pct", e.floor_cost_bp, ctx, rep)
	e.floor_build_bp = _pct(prod, "build_time_floor_pct", e.floor_build_bp, ctx, rep)
	e.floor_reload_bp = _pct(prod, "reload_floor_pct", e.floor_reload_bp, ctx, rep)
	e.resist_cap_bp = _pct(rr, "cap_pct", e.resist_cap_bp, ctx, rep)
	e.min_damage = _whole(rr, "min_damage", e.min_damage, ctx, rep)
	e.detector_default_radius_u = _cells(det, "default_radius_cells", e.detector_default_radius_u, ctx, rep)
	e.watchtower_detect_u = _cells(det, "watchtower_cells", e.watchtower_detect_u, ctx, rep)
	e.aa_battery_detect_u = _cells(det, "aa_battery_cells", e.aa_battery_detect_u, ctx, rep)
	e._verify_bible(bible, rep)
	return e


## Bible mechanical_conventions are authoritative: a differing global.json value is V-CNF-05, the bible value wins.
func _verify_bible(bible: Dictionary, rep: DefLoadReport) -> void:
	var mc: Dictionary = bible.get("mechanical_conventions", {})
	if mc.is_empty():
		return
	var ctx: String = "bible mechanical_conventions"
	var fl: Dictionary = mc.get("floors_as_fraction_of_base", {})
	floor_cost_bp = _fix(floor_cost_bp, _frac(fl.get("cost_credits", null), ctx, rep), "floor_cost", rep)
	floor_build_bp = _fix(floor_build_bp, _frac(fl.get("build_time_seconds", null), ctx, rep), "floor_build_time", rep)
	floor_reload_bp = _fix(floor_reload_bp, _frac(fl.get("reload_interval_seconds", null), ctx, rep), "floor_reload", rep)
	resist_cap_bp = _fix(resist_cap_bp, _frac(mc.get("maximum_combined_damage_resistance_fraction", null), ctx, rep), "resist_cap", rep)
	power_shortage_rate_bp = _fix(power_shortage_rate_bp, _frac(mc.get("power_shortage_production_and_research_rate_multiplier", null), ctx, rep), "power_shortage_rate", rep)
	var rt: Dictionary = mc.get("research_time_seconds_by_tier", {})
	if rt.has("2"):
		research_tier2_t = _fix(research_tier2_t, DefConvert.seconds_to_ticks(DefNumParse.milli(rt["2"], ctx, rep)), "research_tier2", rep)
	if rt.has("3"):
		research_tier3_t = _fix(research_tier3_t, DefConvert.seconds_to_ticks(DefNumParse.milli(rt["3"], ctx, rep)), "research_tier3", rep)
	var sp: Dictionary = mc.get("starting_preset", {})
	if sp.has("credits"):
		start_cr = _fix(start_cr, DefNumParse.whole(sp["credits"], ctx, rep), "start_credits", rep)


func _fix(have: int, bible_v: int, what: String, rep: DefLoadReport) -> int:
	if bible_v < 0:
		return have
	if have != bible_v:
		rep.error("V-CNF-05", "global.json vs bible mechanical_conventions", "%s: global.json gives %d, the bible fixes %d" % [what, have, bible_v])
	return bible_v


## Bible fraction (0.6) -> bp; -1 when absent.
func _frac(v: Variant, ctx: String, rep: DefLoadReport) -> int:
	if v == null:
		return -1
	return DefConvert.rdiv(DefNumParse.milli(v, ctx, rep) * 10000, 1000)


static func _whole(d: Dictionary, key: String, dflt: int, ctx: String, rep: DefLoadReport) -> int:
	if not d.has(key):
		return dflt
	return DefNumParse.whole(d[key], "%s %s" % [ctx, key], rep)


static func _cells(d: Dictionary, key: String, dflt: int, ctx: String, rep: DefLoadReport) -> int:
	if not d.has(key):
		return dflt
	return DefConvert.cells_to_units(DefNumParse.milli(d[key], "%s %s" % [ctx, key], rep))


static func _pct(d: Dictionary, key: String, dflt: int, ctx: String, rep: DefLoadReport) -> int:
	if not d.has(key):
		return dflt
	return DefConvert.pct_to_bp(DefNumParse.milli_pct(d[key], "%s %s" % [ctx, key], rep))
