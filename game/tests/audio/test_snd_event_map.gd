extends RefCounted
## Event map: real data loads clean, typo detection, flavour picks, sim_map resolution, coverage against the real GameData.


func test_real_data_loads(t: TestCtx) -> void:
	var r: Dictionary = SndTestKit.real()
	var store: SndDataStore = r["store"]
	var map: SndEventMap = r["map"]
	t.eq(store.errors.size(), 0, "data store errors: %s" % str(store.errors))
	t.eq(map.errors.size(), 0, "event map errors: %s" % str(map.errors.slice(0, 5)))
	t.ge(map.event_ids().size(), 200, "events")
	t.ge(map.profile_ids().size(), 77, "profiles")
	var ids: Dictionary = {}
	for id: StringName in map.event_ids():
		t.check(not ids.has(id.to_lower()), "unique id %s" % id)
		ids[id.to_lower()] = true
	for id: StringName in map.profile_ids():
		t.check(not ids.has(id.to_lower()), "profile id unique %s" % id)


func test_validation_catches_typos(t: TestCtx) -> void:
	var dir: String = "user://snd_test_bad"
	DirAccess.make_dir_recursive_absolute(dir)
	var mix_text: String = FileAccess.get_file_as_string(SndConfig.DATA_DIR + "/mix.json")
	var ev: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SndConfig.DATA_DIR + "/events.json"))
	var events: Dictionary = ev["events"]
	var e1: Dictionary = (events["snd.ui.click"] as Dictionary).duplicate(true)
	e1["prioritee"] = 5
	events["snd.ui.click"] = e1
	var e2: Dictionary = (events["snd.ui.hover"] as Dictionary).duplicate(true)
	e2["variants"] = [{"stream": "ui/does_not_exist"}]
	events["snd.ui.hover"] = e2
	_write(dir, "events.json", JSON.stringify(ev))
	_write(dir, "mix.json", mix_text)
	for f: String in ["music", "announcer", "responses", "factions", "manifest"]:
		_write(dir, f + ".json", FileAccess.get_file_as_string(SndConfig.DATA_DIR + "/" + f + ".json"))
	var r: Dictionary = SndTestKit.fresh_map(dir)
	var store: SndDataStore = r["store"]
	var map: SndEventMap = r["map"]
	t.check(store.errors.size() >= 1, "unknown key reported by the store: %s" % str(store.errors))
	t.check(map.errors.size() >= 1, "missing stream reported by the map: %s" % str(map.errors))
	# wrong schema
	var ev2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SndConfig.DATA_DIR + "/events.json"))
	ev2["schema"] = "meridian.audio.events/1"
	_write(dir, "events.json", JSON.stringify(ev2))
	var st2: SndDataStore = SndDataStore.new()
	st2.load_all(dir)
	t.check(st2.errors.size() >= 1, "wrong schema reported")
	t.check(not st2.loaded, "load_all returns false")


func _write(dir: String, name: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_flavours(t: TestCtx) -> void:
	var map: SndEventMap = SndTestKit.real()["map"]
	var d: SndEventDef = map.get_def(&"snd.weapon.small_arms")
	t.not_null(d, "small_arms event")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var napc_ids: PackedStringArray = d.flavour_ids[&"napc"]
	t.ge(napc_ids.size(), 2, "napc has >= 2 variants")
	for i: int in 50:
		t.check(napc_ids.has(d.pick_id(rng, &"napc")), "napc draws only napc variants")
	var last: String = ""
	var repeats: int = 0
	for i: int in 1000:
		var p: String = d.pick_id(rng, &"han")
		if p == last:
			repeats += 1
		last = p
	t.eq(repeats, 0, "no immediate repeat over 1000 draws")
	t.check(d.var_ids.has(d.pick_id(rng, &"nosuchfaction")), "unknown flavour falls back to the default list")


func test_sim_map(t: TestCtx) -> void:
	var map: SndEventMap = SndTestKit.real()["map"]
	t.eq(map.resolve(&"weapon_fire", {"archetype": "nonexistent"}), &"snd.weapon.small_arms", "unknown archetype -> fallback")
	t.eq(map.resolve(&"explosion", {"size": "huge"}), &"snd.explosion.huge", "explosion huge")
	t.eq(map.resolve(&"weapon_fire", {"archetype": "tank_cannon_heavy"}), &"snd.weapon.tank_cannon_heavy", "tank cannon variant")
	t.eq(map.resolve(&"nosuchrule", {}), &"", "unknown rule -> empty")
	t.eq(map.resolve(&"collapse", {"area": "s3"}), &"snd.collapse.s3", "collapse area")


func test_profiles_resolve_inheritance(t: TestCtx) -> void:
	var map: SndEventMap = SndTestKit.real()["map"]
	var p: SndProfileDef = map.get_profile(&"snd.profile.mbt_t2")
	t.not_null(p, "mbt_t2 profile")
	t.eq(p.voice_class, SndUnits.VoiceClass.VEHICLE, "voice class")
	t.eq(str(p.weapon_variant.get("tank_cannon", "")), "medium", "weapon variant")
	t.eq(p.loops.size(), 1, "tracked engine loop")
	var h: SndProfileDef = map.get_profile(&"snd.profile.struct.generator")
	t.eq(h.voice_class, SndUnits.VoiceClass.STRUCTURE, "structure voice class")
	t.eq(int(h.loops[0]["when"]), SndProfileDef.When.STRUCTURE_ACTIVE, "hum when")


func test_coverage_real_data(t: TestCtx) -> void:
	var map: SndEventMap = SndTestKit.real()["map"]
	var data: GameData = GameData.load_default()
	t.not_null(data, "GameData")
	if data == null:
		return
	var miss: PackedStringArray = map.missing(data)
	t.eq(miss.size(), 0, "SndEventMap.missing(data) is empty: %s" % str(miss.slice(0, 10)))
	var bank: SndSoundBank = SndSoundBank.new()
	bank.bake(data, map, (SndTestKit.real()["store"] as SndDataStore).mix)
	for i: int in data.units.size():
		t.not_null(bank.unit_profile[i], "profile for %s" % data.units[i].id)
	for i: int in data.structures.size():
		t.not_null(bank.struct_profile[i], "profile for %s" % data.structures[i].id)
	t.eq(int(bank.coverage["weapons_fallback"]), 0, "every weapon archetype has a fire event")
	for i: int in data.powers.size():
		t.check(bank.power_cue[i].has(&"activate"), "power %s has an activate cue" % data.powers[i].id)
	for i: int in data.superweapons.size():
		t.check(bank.sw_cue[i].size() >= 2, "superweapon %s has cues" % data.superweapons[i].id)
	t.eq(int(bank.coverage["structs_generic"]), 0, "no generic structure profile")
	t.note("coverage %s" % str(bank.coverage))


func test_arch_table(t: TestCtx) -> void:
	t.eq(SndUnits.ARCH_TABLE.size(), 27, "27 archetypes")
	for i: int in DefEnums.WEAPON_ARCH_NAMES.size():
		t.eq(SndUnits.ARCH_TABLE[i][0], DefEnums.WEAPON_ARCH_NAMES[i], "arch name %d" % i)
	var data: GameData = GameData.load_default()
	if data == null:
		return
	for i: int in 27:
		var wa: DefWeaponArch = data.weapon_archs[i]
		t.eq(SndUnits.ARCH_TABLE[i][1], DefEnums.DAMAGE_NAMES[wa.dtype], "damage type of %s" % wa.id)
