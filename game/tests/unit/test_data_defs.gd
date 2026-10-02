extends RefCounted
## DATA-02: every Def class instantiates, reflective copy_resolved() deep-copies, every script variable is hashed or
## prefixed _/ui_/pres_, no float-typed property.

const CLASSES: PackedStringArray = [
	"def_base", "def_unit", "def_structure", "def_weapon_arch", "def_weapon_slot", "def_damage_table", "def_move_table",
	"def_body_table", "def_ability", "def_effect", "def_cond_val", "def_cond_application", "def_research", "def_power",
	"def_power_action", "def_superweapon", "def_impact_packet", "def_zone", "def_neutral", "def_faction", "def_economy",
	"def_modifier", "def_selector", "def_roster",
]
const ALLOWED_TYPES: Array = [
	TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_STRING_ARRAY, TYPE_OBJECT,
]


func _script_vars(o: Object) -> Array:
	var out: Array = []
	for p: Dictionary in o.get_property_list():
		var usage: int = p["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out.append(p)
	return out


func test_every_class_instantiates(t: TestCtx) -> void:
	for c: String in CLASSES:
		var sc: GDScript = load("res://src/data/%s.gd" % c) as GDScript
		t.not_null(sc, c + " loads")
		if sc != null:
			t.not_null(sc.new(), c + " instantiates")
	t.not_null(GameData.new(), "GameData")
	t.not_null(DefTags.new(), "DefTags")
	t.not_null(DefIds.new(), "DefIds")
	t.not_null(DefLoadReport.new(), "DefLoadReport")
	t.not_null(DefSources.new(), "DefSources")


func test_hashed_or_prefixed_and_no_float(t: TestCtx) -> void:
	for c: String in CLASSES:
		var o: Object = (load("res://src/data/%s.gd" % c) as GDScript).new()
		var hashed: PackedStringArray = DefHash.hashed_props(o)
		for p: Dictionary in _script_vars(o):
			var n: String = p["name"]
			var prefixed: bool = n.begins_with("_") or n.begins_with("ui_") or n.begins_with("pres_")
			t.check(prefixed != hashed.has(n), "%s.%s is exactly one of hashed / prefixed" % [c, n])
			t.check(int(p["type"]) != TYPE_FLOAT, "%s.%s is not a float" % [c, n])
			t.check(ALLOWED_TYPES.has(int(p["type"])), "%s.%s has an allowed type (%d)" % [c, n, int(p["type"])])


func _busy_unit() -> DefUnit:
	var u: DefUnit = DefUnit.new()
	u.id = "unit.x.a"
	u.health = 100
	u.requires = PackedInt32Array([1, 2])
	u.params = {"k": [1, 2], "d": {"z": 1}}
	var w: DefWeaponSlot = DefWeaponSlot.new()
	w.damage = 50
	var cv: DefCondVal = DefCondVal.new()
	cv.value = 7
	w.cond_vals.append(cv)
	u.weapons.append(w)
	var a: DefAbility = DefAbility.new()
	a.kind = DefEnums.AbilityKind.DEPLOY
	a.params = {"deploy_t": 80, "slots": [0]}
	u.abilities.append(a)
	var uv: DefCondVal = DefCondVal.new()
	uv.value = 9
	u.cond_vals.append(uv)
	return u


func test_copy_resolved_is_deep(t: TestCtx) -> void:
	var base: DefUnit = _busy_unit()
	var h0: int = DefHash.hash_def(DefHash.OFFSET, base)
	var c: DefUnit = base.copy_resolved()
	t.eq(DefHash.hash_def(DefHash.OFFSET, c), h0, "clone hashes like the original")
	c.health = 1
	c.requires.append(3)
	c.weapons[0].damage = 999
	c.weapons[0].cond_vals[0].value = 1
	c.abilities[0].params["deploy_t"] = 1
	(c.abilities[0].params["slots"] as Array).append(5)
	c.cond_vals[0].value = 2
	(c.params["k"] as Array).append(3)
	(c.params["d"] as Dictionary)["z"] = 5
	t.eq(base.health, 100, "health untouched")
	t.eq(base.requires.size(), 2, "packed array untouched")
	t.eq(base.weapons[0].damage, 50, "weapon slot not aliased")
	t.eq(base.weapons[0].cond_vals[0].value, 7, "slot cond_vals not aliased")
	t.eq(base.abilities[0].params["deploy_t"], 80, "ability params not aliased")
	t.eq((base.abilities[0].params["slots"] as Array).size(), 1, "nested ability array not aliased")
	t.eq(base.cond_vals[0].value, 9, "unit cond_vals not aliased")
	t.eq((base.params["k"] as Array).size(), 2, "params array not aliased")
	t.eq((base.params["d"] as Dictionary)["z"], 1, "params dict not aliased")
	t.eq(DefHash.hash_def(DefHash.OFFSET, base), h0, "original hash unchanged")
	t.check(c.weapons[0] != base.weapons[0], "distinct objects")
	t.check(c is DefUnit, "same class")


func test_copy_effect_and_structure(t: TestCtx) -> void:
	var e: DefEffect = DefEffect.new()
	e.ability = DefAbility.new()
	e.ability.params = {"a_t": 1}
	e.cond_codes = PackedInt32Array([1])
	var c: DefEffect = e.copy_resolved()
	c.ability.params["a_t"] = 2
	c.cond_codes.append(2)
	t.eq(e.ability.params["a_t"], 1, "effect payload not aliased")
	t.eq(e.cond_codes.size(), 1, "effect codes not aliased")
	var s: DefStructure = DefStructure.new()
	s.fp_mask = PackedByteArray([1, 0, 1])
	s.weapons.append(DefWeaponSlot.new())
	var sc: DefStructure = s.copy_resolved()
	sc.weapons[0].damage = 5
	sc.fp_mask[0] = 0
	t.eq(s.weapons[0].damage, 0, "structure slot not aliased")
	t.eq(s.fp_mask[0], 1, "mask not aliased")
	var sw: DefSuperweapon = DefSuperweapon.new()
	sw.packets.append(DefImpactPacket.new())
	var swc: DefSuperweapon = sw.copy_resolved()
	swc.packets[0].damage = 7
	t.eq(sw.packets[0].damage, 0, "packets not aliased")


func test_kinds_and_defaults(t: TestCtx) -> void:
	t.eq(DefUnit.new().kind, DefEnums.Kind.UNIT, "unit kind")
	t.eq(DefStructure.new().kind, DefEnums.Kind.STRUCTURE, "structure kind")
	t.eq(DefWeaponArch.new().kind, DefEnums.Kind.WEAPON_ARCH, "arch kind")
	t.eq(DefSelector.new().kind, DefEnums.Kind.SELECTOR, "selector kind")
	t.eq(DefEnums.AbilityKind.DEPLOY_STRUCTURE, 23, "DEPLOY_STRUCTURE code the kernel reads")
	t.eq(DefEnums.Stat.HEALTH, 2, "Stat.HEALTH code the kernel reads")
	t.eq(DefEnums.UF_NON_BLOCKING, 128, "UF_NON_BLOCKING")
	t.eq(DefEnums.WEAPON_ARCH_NAMES.size(), DefEnums.WeaponArch.COUNT, "27 archetype names")
	t.eq(DefEnums.ABILITY_NAMES.size(), DefEnums.AbilityKind.COUNT, "ability name table size")
	t.eq(DefEnums.UNIT_TAG_NAMES.size(), 29, "29 bible unit tags")
	t.eq(DefEnums.UNIT_TAG_NAMES[26], "tank", "tank bit 26")
	t.eq(DefEnums.KIND_NAMES.size(), DefEnums.Kind.COUNT, "kind names")


func test_ability_registry_materialises_defaults(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	var reg: DefAbilityKinds = DefAbilityKinds.from_json(DefTestKit.read_json("res://data/balance/ability_kinds.json"), rep)
	t.check(rep.is_ok(), "registry ids equal DefEnums.AbilityKind: " + rep.text())
	t.eq(reg.kind_id("deploy"), 3, "deploy kind id")
	t.eq(reg.kind_id("summon_orbit"), 34, "summon_orbit kind id")
	t.eq(reg.resolve_entry("deployable_mode"), "ability.deploy.default", "alias resolves")
	t.eq(reg.resolve_entry("amphibious"), "", "amphibious yields no ability")
	t.check(reg.known_entry("amphibious"), "but it is a known name")
	t.check(not reg.known_entry("no_such_thing"), "unknown name")
	t.eq(reg.implicit_templates_for(PackedStringArray(["detector"]), "", "veh_scout").has("ability.detector.default"), true, "tag:detector implicit")
	t.eq(reg.implicit_templates_for(PackedStringArray(), "", "veh_scout").has("ability.transport.squads2"), true, "archetype implicit")
	# Charlemagne: deployable_mode + {deploy_s: 4, range_bonus_pct: 25}
	var a: DefAbility = reg.instantiate("ability.deploy.default", {"deploy_s": 4, "range_bonus_pct": 25}, "test", null, rep)
	t.check(rep.is_ok(), rep.text())
	t.eq(a.kind, DefEnums.AbilityKind.DEPLOY, "kind")
	t.eq(a.template, reg.template_index("ability.deploy.default"), "template index")
	t.eq(a.params, {
		"command_radius_bonus_u": 0, "damage_bonus_bp": 0, "deploy_t": 80, "deployed_slots_n": [], "immobile": true,
		"pack_t": 40, "range_bonus_bp": 2500, "turn_locked": false,
	}, "every default materialised, keys converted and sorted")
	reg.instantiate("ability.deploy.default", {"bogus_s": 1}, "test", null, rep)
	t.eq(rep.count_rule("V-ABL-01"), 1, "unknown param -> V-ABL-01")
	reg.instantiate("ability.no.such", {}, "test", null, rep)
	t.eq(rep.count_rule("V-ABL-01"), 2, "unknown template -> V-ABL-01")
