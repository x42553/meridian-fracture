class_name DefDamageTable
extends RefCounted
## Damage types, armor classes and the damage matrix (data_balance 4.2), built from `global.json` (P2).

var damage_ids: PackedStringArray = PackedStringArray()  ## index = DamageType
var group_mask: PackedInt32Array = PackedInt32Array()  ## per damage type
var nonlethal_mask: int = 0  ## bit per damage type
var armor_ids: PackedStringArray = PackedStringArray()  ## index = ArmorClass
var matrix_pct: PackedInt32Array = PackedInt32Array()  ## [dtype * 11 + armor], integer percent, 0 = cannot damage
var matrix_bp: PackedInt32Array = PackedInt32Array()  ## derived: matrix_pct * 100 (AI reads dmg_matrix_bp)
var resist_cap_bp: int = 5000
var min_damage: int = 1


## matrix_pct of (damage type, armor class).
func pct(dtype: int, armor: int) -> int:
	return matrix_pct[dtype * DefEnums.ArmorClass.COUNT + armor]


## Builds the table from global.json; vocabulary deviating from the frozen enums reports V-CNF-05.
static func from_global(g: Dictionary, rep: DefLoadReport) -> DefDamageTable:
	var t: DefDamageTable = DefDamageTable.new()
	var nd: int = DefEnums.DamageType.COUNT
	var na: int = DefEnums.ArmorClass.COUNT
	t.group_mask.resize(nd)
	var dts: Array = g.get("damage_types", [])
	var groups_list: Array = g.get("resist_groups", [])
	for i: int in groups_list.size():
		if i >= DefEnums.RESIST_GROUP_NAMES.size() or str(groups_list[i]) != DefEnums.RESIST_GROUP_NAMES[i]:
			rep.error("V-CNF-05", "global.json resist_groups", "group %d differs from the frozen ResistGroup" % i)
	for i: int in nd:
		t.damage_ids.append(DefEnums.DAMAGE_NAMES[i])
	for row: Variant in dts:
		var d: Dictionary = row
		var ix: int = int(d.get("index", -1))
		var id: String = str(d.get("id", ""))
		if ix < 0 or ix >= nd or DefEnums.DAMAGE_NAMES[ix] != id:
			rep.error("V-CNF-05", "global.json damage_types", "damage type '%s' has index %d (frozen table differs)" % [id, ix])
			continue
		var m: int = 0
		for gname: Variant in d.get("groups", []):
			m |= DefEnums.resist_group_bit(str(gname))
		t.group_mask[ix] = m
		if bool(d.get("nonlethal", false)):
			t.nonlethal_mask |= 1 << ix
	if dts.size() != nd:
		rep.error("V-CNF-05", "global.json damage_types", "expected %d damage types, found %d" % [nd, dts.size()])
	for i: int in nd:
		if t.group_mask[i] != DefEnums.DAMAGE_GROUP_MASK[i]:
			rep.error("V-CNF-05", "global.json damage_types", "group mask of '%s' is %d, frozen %d" % [DefEnums.DAMAGE_NAMES[i], t.group_mask[i], DefEnums.DAMAGE_GROUP_MASK[i]])
	for i: int in na:
		t.armor_ids.append(DefEnums.ARMOR_NAMES[i])
	for row: Variant in g.get("armor_classes", []):
		var d: Dictionary = row
		var ix: int = int(d.get("index", -1))
		if ix < 0 or ix >= na or DefEnums.ARMOR_NAMES[ix] != str(d.get("id", "")):
			rep.error("V-CNF-05", "global.json armor_classes", "armor class '%s' has index %d (frozen table differs)" % [str(d.get("id", "")), ix])
	t.matrix_pct.resize(nd * na)
	t.matrix_bp.resize(nd * na)
	var mx: Dictionary = g.get("damage_matrix", {})
	for i: int in nd:
		var rowd: Dictionary = mx.get(DefEnums.DAMAGE_NAMES[i], {})
		for j: int in na:
			var v: int = DefNumParse.whole(rowd.get(DefEnums.ARMOR_NAMES[j], 0), "global.json damage_matrix.%s.%s" % [DefEnums.DAMAGE_NAMES[i], DefEnums.ARMOR_NAMES[j]], rep)
			t.matrix_pct[i * na + j] = v
			t.matrix_bp[i * na + j] = v * 100
	var rr: Dictionary = g.get("resistance_rules", {})
	t.resist_cap_bp = DefConvert.pct_to_bp(DefNumParse.milli(rr.get("cap_pct", 50), "global.json resistance_rules.cap_pct", rep))
	t.min_damage = DefNumParse.whole(rr.get("min_damage", 1), "global.json resistance_rules.min_damage", rep)
	return t
