extends RefCounted
## data_balance 10.1 "convert": DefNumParse / DefConvert vectors, GDScript <-> Python parity (tests/golden/convert_vectors.json).

const GOLDEN: String = "res://tests/golden/convert_vectors.json"


func _milli(v: Variant, rep: DefLoadReport) -> int:
	return DefNumParse.milli(v, "test", rep)


func _apply(fn: String, x: Variant, rep: DefLoadReport) -> int:
	match fn:
		"cells_to_units":
			return DefConvert.cells_to_units(_milli(x, rep))
		"cells_s_to_upt":
			return DefConvert.cells_s_to_upt(_milli(x, rep))
		"s_to_ticks":
			return DefConvert.seconds_to_ticks(_milli(x, rep))
		"s_to_mt":
			return DefConvert.seconds_to_mt(_milli(x, rep))
		"pct_to_bp":
			return DefConvert.pct_to_bp(DefNumParse.milli_pct(x, "test", rep))
		"deg_to_a":
			return DefConvert.deg_to_angle(_milli(x, rep))
		"deg_s_to_apt":
			return DefConvert.deg_s_to_apt(_milli(x, rep))
		"crps_to_mcpt":
			return DefConvert.crps_to_mcpt(_milli(x, rep))
		"pcts_to_bps":
			return DefConvert.pcts_to_bps(DefNumParse.milli_pct(x, "test", rep))
		"milli":
			return _milli(x, rep)
	return -999999


func test_python_parity_vectors(t: TestCtx) -> void:
	var p: JSON = JSON.new()
	t.eq(p.parse(FileAccess.get_file_as_string(GOLDEN)), OK, "golden parses")
	var doc: Dictionary = p.data
	var vecs: Array = doc["vectors"]
	t.ge(vecs.size(), 60, "at least 60 vectors")
	var bad: int = 0
	for v: Dictionary in vecs:
		var rep: DefLoadReport = DefLoadReport.new()
		var got: int = _apply(str(v["fn"]), v["in"], rep)
		if v.has("err"):
			if not rep.has_rule(str(v["err"])):
				bad += 1
				t.fail("%s(%s): expected %s, report: %s" % [v["fn"], str(v["in"]), v["err"], rep.text()])
		elif got != int(v["out"]) or not rep.is_ok():
			bad += 1
			t.fail("%s(%s): got %d, expected %d (%s)" % [v["fn"], str(v["in"]), got, int(v["out"]), rep.text()])
	t.eq(bad, 0, "all vectors agree")


func test_spec_examples(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	t.eq(DefConvert.cells_to_units(_milli(7.0, rep)), 7168, "7 cells")
	t.eq(DefConvert.cells_to_units(_milli(0.45, rep)), 461, "0.45 cells")
	t.eq(DefConvert.cells_to_units(_milli(0.001, rep)), 1, "0.001 cells")
	t.eq(DefConvert.cells_s_to_upt(_milli(3.0, rep)), 154, "3 cps")
	t.eq(DefConvert.cells_s_to_upt(_milli(2.6, rep)), 133, "2.6 cps")
	t.eq(DefConvert.cells_s_to_upt(_milli(8.0, rep)), 410, "8 cps")
	t.eq(DefConvert.seconds_to_ticks(_milli(15.5, rep)), 310, "15.5 s")
	t.eq(DefConvert.seconds_to_ticks(_milli(0, rep)), 0, "0 s")
	t.eq(DefConvert.seconds_to_mt(_milli(1.6, rep)), 32000, "1.6 s reload")
	t.eq(DefConvert.pct_to_bp(DefNumParse.milli_pct(12.5, "t", rep)), 1250, "12.5 %")
	t.eq(DefConvert.deg_s_to_apt(_milli(720, rep)), 410, "720 deg/s")
	t.eq(DefConvert.deg_s_to_apt(_milli(150, rep)), 85, "150 deg/s")
	t.eq(DefConvert.crps_to_mcpt(_milli(100, rep)), 5000, "100 cr/s")
	t.eq(DefConvert.pcts_to_bps(DefNumParse.milli_pct(1, "t", rep)), 100, "1 %/s")
	t.check(rep.is_ok(), "no report entries: " + rep.text())


func test_rejections(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	_milli(0.0005, rep)
	t.eq(rep.count_rule("V-SCH-04"), 1, "0.0005 -> V-SCH-04")
	_milli(1e12, rep)
	t.eq(rep.count_rule("V-SCH-04"), 2, "1e12 -> V-SCH-04")
	_milli(NAN, rep)
	t.eq(rep.count_rule("V-SCH-04"), 3, "NaN -> V-SCH-04")
	_milli(INF, rep)
	t.eq(rep.count_rule("V-SCH-04"), 4, "inf -> V-SCH-04")
	DefNumParse.milli_pct(0.005, "t", rep)
	t.eq(rep.count_rule("V-SCH-06"), 1, "0.005 % -> V-SCH-06")
	DefNumParse.whole(2.5, "t", rep)
	t.eq(rep.count_rule("V-SCH-05"), 1, "2.5 as integer -> V-SCH-05")
	t.expect_errors(1)
	t.eq(DefNumParse.milli(0.0005, "no-report", null), 0, "null report: 0 + push_error")


func test_int_helpers(t: TestCtx) -> void:
	t.eq(DefConvert.rdiv(-7, 2), -4, "rdiv(-7,2)")
	t.eq(DefConvert.rdiv(7, 2), 4, "rdiv(7,2)")
	t.eq(DefConvert.rdiv(5, 2), 3, "rdiv(5,2)")
	t.eq(DefConvert.rdiv(-5, 2), -3, "rdiv(-5,2)")
	t.eq(DefConvert.ceil_div(21001, 1000), 22, "ceil_div")
	t.check(DefNumParse.is_integral(3.0), "3.0 integral")
	t.check(not DefNumParse.is_integral(3.5), "3.5 not integral")
	t.check(DefNumParse.is_integral(7), "int integral")
	t.check(DefNumParse.is_number(1) and DefNumParse.is_number(1.5) and not DefNumParse.is_number("1"), "is_number")


func test_convert_params_suffixes(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	var raw: Dictionary = {
		"deploy_s": 4, "range_bonus_pct": 25, "radius_cells": 5, "speed_cells_s": 2.0, "turn_deg_s": 90, "cap_credits": 600,
		"rate_crps": 100, "flag": true, "label": "abc", "pack_s": 2, "count_n": 3, "slots_n": [0, 1],
		"modes": [{"id": "air", "slots_n": [0]}], "mult_x100": 250, "hp_hp": 50,
	}
	var out: Dictionary = DefConvert.convert_params(raw, "test", null, rep)
	t.check(rep.is_ok(), rep.text())
	t.eq(out["deploy_t"], 80, "deploy_s -> ticks")
	t.eq(out["range_bonus_bp"], 2500, "pct -> bp")
	t.eq(out["radius_u"], 5120, "cells -> u")
	t.eq(out["speed_upt"], 102, "cells/s -> upt")
	t.eq(out["turn_apt"], 51, "deg/s -> apt")
	t.eq(out["cap_cr"], 600, "credits")
	t.eq(out["rate_mcpt"], 5000, "crps")
	t.eq(out["flag"], true, "bool passes")
	t.eq(out["label"], "abc", "string passes")
	t.eq(out["slots_n"], [0, 1], "int array")
	t.eq((out["modes"] as Array)[0]["slots_n"], [0], "nested")
	t.eq(out["mult_x100"], 250, "x100 passthrough")
	t.eq(out["hp_hp"], 50, "hp")
	var keys: Array = out.keys()
	var sorted_keys: Array = keys.duplicate()
	sorted_keys.sort()
	t.eq(keys, sorted_keys, "keys sorted")
	DefConvert.convert_params({"mystery": 5}, "test", null, rep)
	t.eq(rep.count_rule("V-SCH-07"), 1, "numeric key without suffix")
