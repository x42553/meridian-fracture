extends RefCounted
## AiBudget (ai.md 5.2): debt, no carry, cap.


func test_debt_repaid_over_next_reset(t: TestCtx) -> void:
	var b: AiBudget = AiBudget.new()
	b.reset(500, 1000)
	t.eq(b.left, 500)
	t.check_false(b.spend(600), "overspend returns false")
	t.eq(b.left, 0)
	t.eq(b.debt, 100)
	b.reset(500, 1000)
	t.eq(b.left, 400, "pay = min(100, 250)")
	t.eq(b.debt, 0)


func test_no_carry_and_cap(t: TestCtx) -> void:
	var b: AiBudget = AiBudget.new()
	b.reset(500, 1000)
	b.spend(200)
	b.reset(500, 1000)
	t.eq(b.left, 500, "unspent budget is not carried")
	b.reset(5000, 3000)
	t.eq(b.left, 3000, "call cap")
	t.check(b.spend(1), "true while budget remains")
	t.check(not b.exhausted())


func test_repayment_limited_to_half(t: TestCtx) -> void:
	var b: AiBudget = AiBudget.new()
	b.reset(100, 100)
	b.spend(1000)
	t.eq(b.debt, 900)
	b.reset(100, 100)
	t.eq(b.left, 50, "at most half of the call budget repays debt")
	t.eq(b.debt, 850)
