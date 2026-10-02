extends RefCounted
## Unit acknowledgements: gaps, shuffled bag, fatigue guard, bark fallback (audio spec 5.10).


func _resp(mode: int = SndSettings.UV_SYNTH) -> SndUnitResponse:
	var r: Dictionary = SndTestKit.real()
	var u: SndUnitResponse = SndUnitResponse.new()
	u.setup(r["store"], _index_with_responses(r["index"]), null, Callable(), 7)
	u.set_faction("napc")
	u.set_mode(mode)
	return u


## The response assets may not be generated yet: give the test its own index entries for napc.
func _index_with_responses(base: SndAssetIndex) -> SndAssetIndex:
	var ix: SndAssetIndex = SndAssetIndex.new()
	for k: Variant in base.assets.keys():
		if not str(k).begins_with("resp/"):
			ix.assets[k] = base.assets[k]
	ix.groups = base.groups.duplicate()
	for cls: String in ["infantry", "vehicle", "heavy", "air", "naval", "support"]:
		for tp: Array in [["select", 3], ["move", 3], ["attack", 3], ["deny", 2], ["special", 2]]:
			for i: int in range(1, int(tp[1]) + 1):
				ix.assets["resp/napc/%s_%s_%d" % [cls, tp[0], i]] = {"f": "resp/napc/%s_%s_%d.mono.ogg" % [cls, tp[0], i], "b": "resp_napc", "c": 1, "l": 0}
	for i: int in 3:
		ix.assets["resp/napc/structure_select_%d" % (i + 1)] = {"f": "resp/napc/structure_select_%d.mono.ogg" % (i + 1), "b": "resp_napc", "c": 1, "l": 0}
	ix.assets["resp/napc/voice/infantry_select_1"] = {"f": "resp/napc/voice/infantry_select_1.mono.ogg", "b": "resp_napc", "c": 1, "l": 0}
	return ix


func test_global_and_same_gaps(t: TestCtx) -> void:
	var u: SndUnitResponse = _resp()
	t.check(u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 1000), "first select plays")
	t.check(not u.on_selected(SndUnits.VoiceClass.VEHICLE, false, 1, 1200), "another select within 250 ms is dropped")
	t.check(not u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 1500), "same class+type at 500 ms is dropped")
	t.check(u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 1800), "same class+type at 800 ms plays")


func test_no_immediate_repeat(t: TestCtx) -> void:
	var u: SndUnitResponse = _resp()
	var picks: PackedStringArray = PackedStringArray()
	var now: int = 10000
	for i: int in 100:
		# alternate classes so the fatigue guard (same type) does not interfere
		now += 2500
		if u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, now):
			picks.append(u.last_played)
	t.gt(picks.size(), 90, "almost all play")
	for i: int in range(1, picks.size()):
		t.check(picks[i] != picks[i - 1], "no immediate repeat at %d" % i)
	for i: int in range(2, picks.size()):
		t.check(picks[i] != picks[i - 2], "not the same as two before at %d" % i)


func test_fatigue_guard(t: TestCtx) -> void:
	var u: SndUnitResponse = _resp()
	var played: Array[bool] = []
	for i: int in 5:
		played.append(u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 20000 + i * 750))
	t.eq(played, [true, true, true, true, false], "the fifth request inside the window is skipped")


func test_order_mapping_and_deny(t: TestCtx) -> void:
	var u: SndUnitResponse = _resp()
	t.check(u.on_order(SndUnitResponse.Order.MOVE, SndUnits.VoiceClass.VEHICLE, 1000), "move plays")
	t.check(u.last_played.contains("vehicle_move"), "move clip: %s" % u.last_played)
	t.check(u.on_order(SndUnitResponse.Order.ATTACK, SndUnits.VoiceClass.VEHICLE, 2000), "attack plays")
	t.check(u.last_played.contains("vehicle_attack"), "attack clip")
	t.check(not u.on_order(SndUnitResponse.Order.STOP, SndUnits.VoiceClass.VEHICLE, 4000), "stop is silent")
	t.check(u.on_denied(SndUnits.VoiceClass.HEAVY, 5000), "deny plays")
	t.check(u.last_played.contains("heavy_deny"), "deny clip")
	t.check(u.on_selected(SndUnits.VoiceClass.INFANTRY, true, 1, 9000), "structure select plays")
	t.check(u.last_played.contains("structure_select"), "structure clip")


func test_voice_mode_falls_back_to_bleep(t: TestCtx) -> void:
	var u: SndUnitResponse = _resp(SndSettings.UV_VOICE)
	t.check(u.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 1000), "bark exists for infantry select")
	t.check(u.last_played.contains("/voice/"), "bark played: %s" % u.last_played)
	t.check(u.on_selected(SndUnits.VoiceClass.VEHICLE, false, 1, 5000), "no bark for vehicles: bleep")
	t.check(not u.last_played.contains("/voice/"), "fell back to the bleep")
	var off: SndUnitResponse = _resp(SndSettings.UV_OFF)
	t.check(not off.on_selected(SndUnits.VoiceClass.INFANTRY, false, 1, 1000), "off is silent")
