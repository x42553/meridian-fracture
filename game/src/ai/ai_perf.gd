class_name AiPerf
extends RefCounted
## Diagnostic-only wall-clock sampling of the AI (ai.md 2.1). The ONLY AI file allowed to read the clock; its output is
## written to metrics and never read by a decision (lint: test_ai_purity_lint).

var enabled: bool = false
var samples: int = 0
var total_us: int = 0
var worst_us: int = 0
var last_us: int = 0
var _t0: int = 0


func begin() -> void:
	if enabled:
		_t0 = Time.get_ticks_usec()


func end() -> void:
	if not enabled:
		return
	last_us = Time.get_ticks_usec() - _t0
	samples += 1
	total_us += last_us
	worst_us = maxi(worst_us, last_us)


func avg_us() -> int:
	return total_us / maxi(samples, 1)
