class_name DefNumParse
extends RefCounted
## THE only file of `src/data` that touches a float (lint L003 exempts `*_parse.gd`). Godot's JSON yields `float`
## for every number; this class turns a raw JSON number into exact integer milli-units once (data_balance 5.2.1).
## Legal designer numbers have <= 3 decimals, so |m - r| < 1e-9 on every IEEE-754 platform.

const MAX_MILLI: int = 1099511627776  ## 2^40
const _TOL: float = 0.001
const _HUGE: float = 1.0e13


static func is_number(v: Variant) -> bool:
	var t: int = typeof(v)
	return t == TYPE_INT or t == TYPE_FLOAT


## True for a number whose milli value is a multiple of 1000 (3.0 yes, 3.5 no).
static func is_integral(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return true
	if t != TYPE_FLOAT:
		return false
	var f: float = v
	if is_nan(f) or is_inf(f):
		return false
	var m: float = f * 1000.0
	if absf(m) >= _HUGE:
		return false
	var r: int = roundi(m)
	return absf(m - float(r)) <= _TOL and r % 1000 == 0


## Number -> exact integer milli-units; reports V-SCH-04 (> 3 decimals, NaN/inf, |x| >= 2^40 milli) and returns 0.
## `rep` may be null (then push_error).
static func milli(v: Variant, ctx: String, rep: DefLoadReport) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT:
		var iv: int = v
		if iv >= MAX_MILLI / 1000 or iv <= -MAX_MILLI / 1000:
			return _fail(rep, "V-SCH-04", ctx, "number %d is out of range" % iv)
		return iv * 1000
	if t != TYPE_FLOAT:
		return _fail(rep, "V-SCH-04", ctx, "expected a number, got type %d" % t)
	var f: float = v
	if is_nan(f) or is_inf(f):
		return _fail(rep, "V-SCH-04", ctx, "number is NaN or infinite")
	var m: float = f * 1000.0
	if absf(m) >= _HUGE:
		return _fail(rep, "V-SCH-04", ctx, "number is out of range (|x| >= 2^40 milli)")
	var r: int = roundi(m)
	if absf(m - float(r)) > _TOL:
		return _fail(rep, "V-SCH-04", ctx, "more than 3 decimals")
	if r >= MAX_MILLI or r <= -MAX_MILLI:
		return _fail(rep, "V-SCH-04", ctx, "number is out of range (|x| >= 2^40 milli)")
	return r


## Like milli() for a percent: at most 2 decimals (V-SCH-06).
static func milli_pct(v: Variant, ctx: String, rep: DefLoadReport) -> int:
	var r: int = milli(v, ctx, rep)
	if r % 10 != 0:
		return _fail(rep, "V-SCH-06", ctx, "percent has more than 2 decimals")
	return r


## Integer field: a number that must be integral (V-SCH-05); returns x (not milli).
static func whole(v: Variant, ctx: String, rep: DefLoadReport) -> int:
	var r: int = milli(v, ctx, rep)
	if r % 1000 != 0:
		return _fail(rep, "V-SCH-05", ctx, "expected an integer")
	return r / 1000


## Lossy milli value without validation (used by the canonical JSON hash, where any deterministic value will do).
static func milli_raw(v: Variant) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT:
		var iv: int = v
		return iv * 1000
	if t != TYPE_FLOAT:
		return 0
	var f: float = v
	if is_nan(f) or is_inf(f):
		return 0
	var m: float = f * 1000.0
	if absf(m) >= _HUGE:
		return MAX_MILLI if m > 0.0 else -MAX_MILLI
	return roundi(m)


static func _fail(rep: DefLoadReport, rule: String, ctx: String, msg: String) -> int:
	if rep == null:
		push_error("%s %s: %s" % [rule, ctx, msg])
	else:
		rep.error(rule, ctx, msg)
	return 0
