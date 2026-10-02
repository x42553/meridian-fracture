extends RefCounted
## data_balance 10.1 "hash": FNV vectors, LEB128, canonical JSON hash, reflection hash and the float bug counter.


func _bytes_hash(bytes: Array) -> int:
	var h: int = DefHash.OFFSET
	for b: int in bytes:
		h = DefHash.mix_byte(h, b)
	return h


func test_fnv_vectors(t: TestCtx) -> void:
	t.eq(DefHash.mix_byte(DefHash.OFFSET, 0x61), 0xE40C292C, "FNV-1a-32 of 'a'")
	t.eq(DefHash.mix_str(DefHash.OFFSET, "a"), DefHash.mix_byte(0xE40C292C, 0xFF), "mix_str = bytes + 0xFF")
	t.eq(DefHash.mix_str(DefHash.OFFSET, "aé"), _bytes_hash([0x61, 0xC3, 0xA9, 0xFF]), "UTF-8 bytes")


func test_leb128_vectors(t: TestCtx) -> void:
	t.eq(DefHash.mix_int(DefHash.OFFSET, 0), _bytes_hash([0x00]), "0")
	t.eq(DefHash.mix_int(DefHash.OFFSET, 1), _bytes_hash([0x02]), "1")
	t.eq(DefHash.mix_int(DefHash.OFFSET, -1), _bytes_hash([0x03]), "-1")
	t.eq(DefHash.mix_int(DefHash.OFFSET, 63), _bytes_hash([0x7E]), "63")
	t.eq(DefHash.mix_int(DefHash.OFFSET, 64), _bytes_hash([0x80, 0x01]), "64")
	t.eq(DefHash.mix_int(DefHash.OFFSET, -64), _bytes_hash([0x81, 0x01]), "-64")
	t.eq(DefHash.mix_int(DefHash.OFFSET, 1 << 61), DefHash.mix_int(DefHash.OFFSET, 1 << 61), "large stays defined")
	t.check(DefHash.mix_int(DefHash.OFFSET, 5000000000) != DefHash.mix_int(DefHash.OFFSET, 705032704), "no 32-bit wrap")


func test_canonical_json(t: TestCtx) -> void:
	var a: Variant = JSON.parse_string('{"b": 1.5, "a": [1, 2, {"z": true, "y": "s"}], "c": null}')
	var b: Variant = JSON.parse_string('{\r\n  "c": null,\r\n  "a": [1,2,{"y":"s","z":true}],\r\n  "b": 1.500\r\n}')
	var c: Variant = JSON.parse_string('{"b": 1.501, "a": [1, 2, {"z": true, "y": "s"}], "c": null}')
	t.eq(DefHash.hash_json(a), DefHash.hash_json(b), "whitespace / CRLF / key order independent")
	t.ne(DefHash.hash_json(a), DefHash.hash_json(c), "1-milli change differs")
	t.ne(DefHash.hash_json(JSON.parse_string('[1, 2]')), DefHash.hash_json(JSON.parse_string('[2, 1]')), "array order matters")


func test_reflection_hash(t: TestCtx) -> void:
	var u1: DefUnit = DefUnit.new()
	var u2: DefUnit = DefUnit.new()
	u1.id = "unit.x.a"
	u2.id = "unit.x.a"
	t.eq(DefHash.hash_def(DefHash.OFFSET, u1), DefHash.hash_def(DefHash.OFFSET, u2), "equal defs, equal hash")
	u2.ui_name = "label only"
	u2.pres_recipe = "other"
	t.eq(DefHash.hash_def(DefHash.OFFSET, u1), DefHash.hash_def(DefHash.OFFSET, u2), "ui_ / pres_ excluded")
	u2.health = 5
	t.ne(DefHash.hash_def(DefHash.OFFSET, u1), DefHash.hash_def(DefHash.OFFSET, u2), "gameplay field changes the hash")
	u1.health = 5
	var w: DefWeaponSlot = DefWeaponSlot.new()
	u1.weapons.append(w)
	t.ne(DefHash.hash_def(DefHash.OFFSET, u1), DefHash.hash_def(DefHash.OFFSET, u2), "child def is hashed")
	var d: DefUnit = DefUnit.new()
	d.params = {"b": 1, "a": 2}
	var e: DefUnit = DefUnit.new()
	e.params = {"a": 2, "b": 1}
	t.eq(DefHash.hash_def(DefHash.OFFSET, d), DefHash.hash_def(DefHash.OFFSET, e), "params hashed by sorted key")


func test_float_is_a_bug(t: TestCtx) -> void:
	DefHash.float_hits = 0
	var d: DefUnit = DefUnit.new()
	d.params = {"bad": 1.5}
	DefHash.hash_def(DefHash.OFFSET, d)
	t.eq(DefHash.float_hits, 1, "a float inside a def bumps float_hits")
	DefHash.float_hits = 0


func test_ids_and_tags(t: TestCtx) -> void:
	var rep: DefLoadReport = DefLoadReport.new()
	var ids: DefIds = DefIds.new()
	ids.assign(DefEnums.Kind.STRUCTURE, PackedStringArray(["structure.b.z", "structure.a.y", "structure.a.x"]), rep)
	t.eq(ids.index_of(DefEnums.Kind.STRUCTURE, "structure.a.x"), 0, "sorted index 0")
	t.eq(ids.id_of(DefEnums.Kind.STRUCTURE, 2), "structure.b.z", "id_of")
	t.eq(ids.index_of(DefEnums.Kind.STRUCTURE, "structure.nope.q"), -1, "unknown -> -1")
	ids.assign(DefEnums.Kind.UNIT, PackedStringArray(["unit.a.b", "unit.a.b"]), rep)
	t.eq(rep.count_rule("V-SCH-03"), 1, "duplicate id")
	ids.assign(DefEnums.Kind.UNIT, PackedStringArray(["Unit.a.b", "structure.a.b", "unit.noprefix"]), rep)
	t.eq(rep.count_rule("V-SCH-03"), 3, "bad ids: caps, wrong prefix, single segment")
	t.check(DefIds.valid_id("summon.napc.uav") and not DefIds.valid_id("unit..x") and not DefIds.valid_id("unit.a."), "valid_id")
	var tags: DefTags = DefTags.new()
	t.eq(tags.unit_bit("combat"), 1 << 9, "UT_COMBAT bit")
	t.eq(DefEnums.UT_COMBAT, 1 << 9, "UT_COMBAT const")
	t.eq(tags.unit_bit("unmanned"), 1 << 28, "last bible tag")
	t.eq(tags.unit_bit("nope"), 0, "unknown tag")
	t.eq(tags.unit_extra_first_bit(), 29, "first free bit")
	t.eq(tags.structure_bit("superweapon"), 1 << 4, "structure tag")
	var rep2: DefLoadReport = DefLoadReport.new()
	t.check(tags.add_extras(0, PackedStringArray(["zeta_tag", "alpha_tag"]), rep2, "test"), "extras added")
	t.eq(tags.unit_bit("alpha_tag"), 1 << 29, "extras in sorted order")
	t.eq(tags.unit_bit("zeta_tag"), 1 << 30, "extras in sorted order 2")
	t.check(not tags.add_extras(0, PackedStringArray(["tank"]), rep2, "test"), "locked tag refused")
	t.eq(rep2.count_rule("V-CNF-03"), 1, "V-CNF-03")
	t.eq(tags.unit_names(1 << 9 | 1 << 29), PackedStringArray(["combat", "alpha_tag"]), "names of mask")
