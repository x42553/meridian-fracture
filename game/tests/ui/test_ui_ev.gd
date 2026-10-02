extends RefCounted
## `UiEv` codes, field decoding and the contract with the sim constants (ui.md 6.2.1, 10.2 `test_ui_ev`).


func test_registry_codes(t: TestCtx) -> void:
	t.eq(UiEv.SPAWNED, 1)
	t.eq(UiEv.REMOVED, 2)
	t.eq(UiEv.OWNER_CHANGED, 3)
	t.eq(UiEv.CASH, 4)
	t.eq(UiEv.CMD_REJECTED, 5)
	t.eq(UiEv.ORDER_FAILED, 6)
	t.eq(UiEv.PLAYER_ELIMINATED, 7)
	t.eq(UiEv.MATCH_END, 8)
	t.eq(UiEv.DEATH, 208)
	t.eq(UiEv.EMP, 213)
	t.eq(UiEv.ATTACK_ALERT, 214)
	t.eq(UiEv.STRUCTURE_READY, 302)
	t.eq(UiEv.POWER_SHORTAGE, 311)
	t.eq(UiEv.WARNING, 404)
	t.eq(UiEv.SW_READY, 405)
	t.eq(UiEv.STRIDE, 10)


func test_verify_against_sim(t: TestCtx) -> void:
	var problems: PackedStringArray = UiEv.verify_against_sim()
	t.eq(problems, PackedStringArray(), "every code equals the sim constant: %s" % ", ".join(problems))


func test_names(t: TestCtx) -> void:
	t.eq(UiEv.by_name(&"attack_alert"), 214)
	t.eq(UiEv.by_name(&"death"), 208)
	t.eq(UiEv.by_name(&"warning"), 404)
	t.eq(UiEv.by_name(&"nonsense"), -1)
	t.eq(UiEv.name_of(214), &"attack_alert")
	t.eq(UiEv.name_of(9999), &"")
	for k: Variant in UiEv.NAMES:
		t.eq(UiEv.name_of(UiEv.by_name(k as StringName)), k, "round trip %s" % k)


func test_record_decoding(t: TestCtx) -> void:
	# an EV_DEATH: killer pid 3, owner 0, flags 64 (unit) | 1 (wreck)
	var e: int = (3 + 1) | ((0 + 1) << 8)
	var c: int = 2 | (65 << 8)
	var rec: PackedInt32Array = PackedInt32Array([UiEv.DEATH, 500, 1024, 2048, 77, 12, c, 88, e, 0])
	t.eq(UiEv.count(rec), 1)
	t.eq(UiEv.field(rec, 0, UiEv.I_TICK), 500)
	t.eq(UiEv.field(rec, 0, UiEv.I_A), 77)
	t.eq(UiEv.death_killer_pid(e), 3)
	t.eq(UiEv.death_owner(e), 0)
	t.eq(UiEv.death_flags(c), 65)
	var two: PackedInt32Array = rec.duplicate()
	two.append_array(PackedInt32Array([UiEv.CASH, 501, 0, 0, 1, 50, 900, 1, 0, 0]))
	t.eq(UiEv.count(two), 2)
	t.eq(UiEv.field(two, 1, UiEv.I_B), 50)
	t.check(not UiEv.known(4242), "unknown types are simply not known")
	t.check(UiEv.known(UiEv.CASH))
	t.eq(UiEv.count(PackedInt32Array()), 0)
