class_name DefFormat
extends RefCounted
## Integer-math display strings for the Field Manual, dev overlays and the UI/AI examples (data_balance 3.3). No floats:
## every value is scaled by an integer and printed with one decimal (or two for percents).


## Fixed-point text of `tenths` (value x 10): 70 -> "7.0", -15 -> "-1.5".
static func tenths_text(tenths: int) -> String:
	var neg: bool = tenths < 0
	var a: int = -tenths if neg else tenths
	return "%s%d.%d" % ["-" if neg else "", a / 10, a % 10]


## Sub-cell units -> cells, one decimal half-up: 7168 -> "7.0", 563 -> "0.5".
static func cells_text(u: int) -> String:
	return _signed_div_text(u * 10 + 512 if u >= 0 else u * 10 - 512, 1024)


## Units per tick -> cells per second, one decimal: 102 -> "2.0".
static func speed_text(upt: int) -> String:
	return _signed_div_text(upt * SimConfig.TPS * 10 + (512 if upt >= 0 else -512), 1024)


## Ticks -> seconds, one decimal half-up: 550 -> "27.5", 21 -> "1.1".
static func seconds_text(t: int) -> String:
	return _signed_div_text(t * 10 + (SimConfig.TPS / 2 if t >= 0 else -(SimConfig.TPS / 2)), SimConfig.TPS)


## Milli-ticks -> seconds, one decimal half-up: 24000 -> "1.2".
static func mt_seconds_text(mt: int) -> String:
	var half: int = SimConfig.TPS * 1000 / 2
	return _signed_div_text(mt * 10 + (half if mt >= 0 else -half), SimConfig.TPS * 1000)


## Basis points -> percent, trailing zeros trimmed: 1000 -> "10", -1500 -> "-15", 1250 -> "12.5", 5 -> "0.05".
static func percent_text(bp: int) -> String:
	var neg: bool = bp < 0
	var a: int = -bp if neg else bp
	var whole: int = a / 100
	var frac: int = a % 100
	var s: String = str(whole)
	if frac != 0:
		s += ".%02d" % frac
		if s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
	return ("-" if neg else "") + s


## Credits with thousands separators: 1400 -> "1,400".
static func credits_text(cr: int) -> String:
	var neg: bool = cr < 0
	var s: String = str(-cr if neg else cr)
	var out: String = ""
	var n: int = s.length()
	for i: int in n:
		out += s[i]
		var rest: int = n - 1 - i
		if rest > 0 and rest % 3 == 0:
			out += ","
	return ("-" if neg else "") + out


## Signed bp delta with an explicit plus: 1000 -> "+10%", -1500 -> "-15%".
static func delta_percent_text(bp: int) -> String:
	return ("+" if bp >= 0 else "") + percent_text(bp) + "%"


static func _signed_div_text(numer_tenths_scaled: int, d: int) -> String:
	# numer/d is the value x 10 before truncation (half-up already added by the caller, sign-symmetric).
	return tenths_text(numer_tenths_scaled / d)
