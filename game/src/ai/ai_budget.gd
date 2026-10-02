class_name AiBudget
extends RefCounted
## Work-unit accounting (ai.md 5.2). One work unit (wu) ~ 3 microseconds; modules call spend(n) BEFORE the work and stop
## when it returns false. Overspend becomes `debt`, repaid at <= half of the next call budgets, so the AVERAGE holds.
## No decision ever depends on the wall clock.

var left: int = 0
var debt: int = 0  ## overspend carried to the next reset
var used: int = 0  ## wu spent since the last reset (including overshoot); diagnostics and slot charging


## call_budget = min(avg_wu * dt, call_cap); no unspent carry between thinks.
func reset(call_budget: int, call_cap: int) -> void:
	var pay: int = mini(debt, call_budget / 2)
	debt -= pay
	left = mini(call_cap, call_budget - pay)
	used = 0


## Spends n; true while budget remains (the spend that empties the budget returns false).
func spend(n: int = 1) -> bool:
	used += n
	left -= n
	if left < 0:
		debt += -left
		left = 0
	return left > 0


func exhausted() -> bool:
	return left <= 0
