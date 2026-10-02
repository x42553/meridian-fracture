extends RefCounted
## data_balance 10.1 "format": integer-math display strings.


func test_spec_vectors(t: TestCtx) -> void:
	t.eq(DefFormat.cells_text(7168), "7.0", "7168 u")
	t.eq(DefFormat.cells_text(563), "0.5", "563 u")
	t.eq(DefFormat.cells_text(0), "0.0", "0 u")
	t.eq(DefFormat.speed_text(102), "2.0", "102 upt")
	t.eq(DefFormat.seconds_text(550), "27.5", "550 t")
	t.eq(DefFormat.seconds_text(21), "1.1", "21 t")
	t.eq(DefFormat.mt_seconds_text(24000), "1.2", "24000 mt")
	t.eq(DefFormat.percent_text(1000), "10", "1000 bp")
	t.eq(DefFormat.percent_text(-1500), "-15", "-1500 bp")
	t.eq(DefFormat.percent_text(1250), "12.5", "1250 bp")
	t.eq(DefFormat.percent_text(5), "0.05", "5 bp")


func test_helpers(t: TestCtx) -> void:
	t.eq(DefFormat.tenths_text(-15), "-1.5", "tenths")
	t.eq(DefFormat.credits_text(1400), "1,400", "credits")
	t.eq(DefFormat.credits_text(7500), "7,500", "credits 7500")
	t.eq(DefFormat.credits_text(950), "950", "credits small")
	t.eq(DefFormat.credits_text(1234567), "1,234,567", "credits big")
	t.eq(DefFormat.delta_percent_text(1000), "+10%", "delta +")
	t.eq(DefFormat.delta_percent_text(-1500), "-15%", "delta -")
	# consistency with the converters: designer value -> runtime -> text round-trips for the spec examples
	t.eq(DefFormat.cells_text(DefConvert.cells_to_units(7000)), "7.0", "7 cells round trip")
	t.eq(DefFormat.seconds_text(DefConvert.seconds_to_ticks(27500)), "27.5", "27.5 s round trip")
