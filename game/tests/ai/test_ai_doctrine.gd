extends RefCounted
## AiDoctrine (ai_composition.json + ai_faction_<code>.json): patch semantics (ai.md 5.5.2 overlays), the shipped data resolves
## without errors for all 32 rosters, and the references of every non-optional step exist in the roster.


func _store(base: Dictionary, faction: Dictionary = {}) -> AiDataStore:
	var s: AiDataStore = AiDataStore.new()
	s.extra["ai_composition.json"] = {"base": base}
	if not faction.is_empty():
		s.extra["ai_faction_zzz.json"] = faction
	return s


func _ids(lst: Array) -> Array:
	var out: Array = []
	for st: Variant in lst:
		out.append((st as Dictionary)["id"])
	return out


func test_patch_semantics(t: TestCtx) -> void:
	var base: Dictionary = {
		"opener": [{"id": "a", "op": "build", "struct": "generator"}, {"id": "b", "op": "build", "struct": "refinery"}, {"id": "c", "op": "build", "struct": "radar"}],
		"targets": [{"id": "t1", "from_s": 10, "struct": "barracks", "n": 2}],
		"composition": {"opening": {"INFANTRY_BASIC": 40, "TANK_MAIN": 30}, "buildup": {"INFANTRY_BASIC": 20}},
	}
	var fac: Dictionary = {"base": {"opener_patch": {"insert_after": {"a": [{"id": "a2", "op": "build", "struct": "barracks"}]}}},
		"rosters": {"roster.zzz.x": {
			"opener_patch": {"remove": ["c"], "replace": {"b": {"id": "b", "op": "build", "struct": "factory"}}, "insert_before": {"a": [{"id": "z", "op": "build", "struct": "watchtower"}]}, "append": [{"id": "e", "op": "build", "struct": "dock"}]},
			"targets_patch": {"replace": {"t1": {"id": "t1", "from_s": 99, "struct": "barracks", "n": 3}}},
			"composition_patch": {"opening": {"TANK_MAIN": null, "INFANTRY_AT": 15}},
		}}}
	var d: AiDoctrine = AiDoctrine.resolve(_store(base, fac), "roster.zzz.x")
	t.eq(d.errors, PackedStringArray(), "no patch errors")
	t.eq(_ids(d.opener), ["z", "a", "a2", "b", "e"] as Array, "faction insert_after, roster remove / replace / insert_before / append")
	t.eq(str((d.opener[3] as Dictionary)["struct"]), "factory")
	t.eq(int((d.targets[0] as Dictionary)["n"]), 3)
	var w: PackedInt32Array = d.composition[AiTypes.Phase.OPENING]
	t.eq(w[AiTypes.R_INFANTRY_BASIC], 40)
	t.eq(w[AiTypes.R_TANK_MAIN], 0, "null removes a role")
	t.eq(w[AiTypes.R_INFANTRY_AT], 15)
	# the shared base is never mutated: another roster of the same store sees the original
	var other: AiDoctrine = AiDoctrine.resolve(_store(base, fac), "roster.zzz.y")
	t.eq(_ids(other.opener), ["a", "a2", "b", "c"] as Array, "faction base patch only")
	t.eq(_ids((base["opener"] as Array)), ["a", "b", "c"] as Array)


func test_patch_errors_are_reported(t: TestCtx) -> void:
	var base: Dictionary = {"opener": [{"id": "a", "op": "build", "struct": "generator"}], "composition": {"opening": {"NOPE": 5}}}
	var fac: Dictionary = {"rosters": {"roster.zzz.x": {"opener_patch": {"remove": ["missing"], "append": [{"id": "a", "op": "build", "struct": "radar"}]}}}}
	var d: AiDoctrine = AiDoctrine.resolve(_store(base, fac), "roster.zzz.x")
	var text: String = "\n".join(d.errors)
	t.check(text.contains("V1"), "unknown patch id (V1)")
	t.check(text.contains("V11"), "duplicate step id (V11)")
	t.check(text.contains("V8"), "unknown role name (V8)")


func test_phase_thresholds(t: TestCtx) -> void:
	var d: AiDoctrine = AiDoctrine.resolve(AiDataStore.load_default(), "roster.napc.vanilla")
	t.eq(d.phase_at(0), AiTypes.Phase.OPENING)
	t.eq(d.phase_at(3000), AiTypes.Phase.BUILDUP)
	t.eq(d.phase_at(9000), AiTypes.Phase.MIDGAME)
	t.eq(d.phase_at(21600), AiTypes.Phase.LATE)
	t.eq(d.phase_at(4000, 200), AiTypes.Phase.OPENING, "a slower AI (tech delay x2) stays in the phase longer")


func test_shipped_data_resolves_for_all_rosters(t: TestCtx) -> void:
	var data: GameData = SimMatchKit.data()
	var store: AiDataStore = AiDataStore.load_default()
	t.eq(store.errors, PackedStringArray(), "AI data files load clean")
	t.gt(store.extra.size(), 3, "composition + faction files loaded")
	for rid: String in data.roster_ids():
		var d: AiDoctrine = AiDoctrine.resolve(store, rid)
		t.eq(d.errors, PackedStringArray(), "%s: doctrine resolves" % rid)
		var ri: int = data.roster_idx(rid)
		var res: AiRoleResolver = AiRoleResolver.resolve(data, data.rosters[ri], store)
		for st: Variant in d.opener:
			var s: Dictionary = st
			if bool(s.get("opt", false)):
				continue
			match str(s.get("op", "")):
				"build":
					t.check(res.structure_of_kind(AiDoctrine.struct_kind_of(str(s["struct"]))) >= 0, "%s: step %s struct exists" % [rid, s["id"]])
				"train":
					if s.has("role"):
						t.check(res.has_role(AiTypes.role_bit(str(s["role"]))), "%s: step %s role exists" % [rid, s["id"]])
					elif s.has("def"):
						t.check(data.unit_idx(str(s["def"])) >= 0, "%s: step %s def exists" % [rid, s["id"]])
		var live: int = 0
		for r: int in AiTypes.ROLE_COUNT:
			if d.composition[AiTypes.Phase.BUILDUP][r] > 0 and res.has_role(r):
				live += 1
		t.gt(live, 3, "%s: buildup composition has roles the roster owns" % rid)
		for st2: Variant in d.targets:
			t.check(res.structure_of_kind(AiDoctrine.struct_kind_of(str((st2 as Dictionary)["struct"]))) >= 0, "%s: target struct exists" % rid)


func test_doctrine_differs_where_it_should(t: TestCtx) -> void:
	var store: AiDataStore = AiDataStore.load_default()
	var usa: AiDoctrine = AiDoctrine.resolve(store, "roster.napc.usa")
	var van: AiDoctrine = AiDoctrine.resolve(store, "roster.napc.vanilla")
	# AIT: the Airfield left the opener spine (the air-led USA won 26 % of its games with it there); a target asks for one from 7:00
	t.check(not _ids(usa.opener).has("af1"), "USA no longer opens with an Airfield")
	var air_t: Array = usa.targets.filter(func(x: Variant) -> bool: return str((x as Dictionary).get("struct", "")) == "airfield")
	t.eq(air_t.size(), 1, "USA targets one Airfield")
	if air_t.size() == 1:
		t.eq(int((air_t[0] as Dictionary)["from_s"]), 420, "... from 7:00")
	t.gt(usa.composition[AiTypes.Phase.MIDGAME][AiTypes.R_FIGHTER], van.composition[AiTypes.Phase.MIDGAME][AiTypes.R_FIGHTER])
	t.eq(usa.composition[AiTypes.Phase.MIDGAME][AiTypes.R_HEAVY], 0, "USA has no Heavy in its doctrine")
	var han: AiDoctrine = AiDoctrine.resolve(store, "roster.han.china")
	t.gt(han.composition[AiTypes.Phase.OPENING][AiTypes.R_INFANTRY_BASIC], van.composition[AiTypes.Phase.OPENING][AiTypes.R_INFANTRY_BASIC], "HAN swarms infantry")
	var sap: AiDoctrine = AiDoctrine.resolve(store, "roster.sap.india")
	t.gt(sap.targets.size(), van.targets.size(), "SAP adds defensive targets")
	var pd: AiDoctrine = AiDoctrine.resolve(store, "roster.pd.japan")
	t.check(_ids(pd.opener).has("dock1"), "PD plans a Dock")
	var ae: AiDoctrine = AiDoctrine.resolve(store, "roster.ae.kongo")
	t.check(_ids(ae.opener).has("salv1"), "AE plans salvagers")
