class_name UiFormatLite
extends RefCounted
## The few number formatters the menu screens need until `UiFormat` (UI-01b) lands: thousands separators, mm:ss, hash chips.


## 12450 -> "12,450".
static func credits(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## 26 -> "0:26"; 3725 -> "1:02:05".
static func clock(seconds: int) -> String:
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	var s: int = seconds % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]


## 0x9F3AC21E -> "9F3A-C21E".
static func hash8(h: int) -> String:
	var t: String = "%08X" % (h & 0xFFFFFFFF)
	return t.substr(0, 4) + "-" + t.substr(4, 4)
