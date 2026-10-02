class_name AiDoctrine
extends RefCounted
## The merged build-order / composition doctrine of ONE roster (ai.md 5.5.2 / 7.3, lean). The shared base lives in
## ai_composition.json under "base" (opener, targets, composition, research) next to the global counter table; a faction file
## ai_faction_<code>.json may carry a `base` patch object (applied to all four rosters of the faction) and `rosters[<roster id>]`
## overlays. Patch keys: opener_patch / targets_patch / research_patch = {remove: [ids], replace: {id: step}, insert_before:
## {id: [steps]}, insert_after: {id: [steps]}, append: [steps]}, composition_patch = {phase: {ROLE: weight | null}}. Patches are
## applied in that order to a deep copy of the base, so a roster never changes the shared data. Every problem is collected in
## `errors` (never a crash): unknown ids in a patch, unknown role names, duplicate step ids.

const FILE_BASE: String = "ai_composition.json"
const PHASES: PackedStringArray = ["opening", "buildup", "midgame", "late"]
const PATCH_KEYS: PackedStringArray = ["opener", "targets", "research"]

## struct names of the DSL -> AiTypes.StructKind
const STRUCT_KINDS: Dictionary = {
	"generator": AiTypes.StructKind.GENERATOR, "refinery": AiTypes.StructKind.REFINERY, "barracks": AiTypes.StructKind.BARRACKS,
	"factory": AiTypes.StructKind.FACTORY, "radar": AiTypes.StructKind.RADAR, "laboratory": AiTypes.StructKind.LAB,
	"airfield": AiTypes.StructKind.AIRFIELD, "dock": AiTypes.StructKind.DOCK, "watchtower": AiTypes.StructKind.WATCHTOWER,
	"at_turret": AiTypes.StructKind.AT_TURRET, "aa_battery": AiTypes.StructKind.AA_BATTERY, "adv_defense": AiTypes.StructKind.ADV_DEFENSE,
	"superweapon": AiTypes.StructKind.SUPERWEAPON, "relay": AiTypes.StructKind.RELAY,
}
## enemy category names of the DSL -> AiTypes.Cat
const CAT_NAMES: Dictionary = {
	"air": AiTypes.Cat.AIR, "armor": AiTypes.Cat.ARMOR, "infantry": AiTypes.Cat.INFANTRY, "artillery": AiTypes.Cat.ARTILLERY,
	"naval": AiTypes.Cat.NAVAL, "sub": AiTypes.Cat.SUB, "camo": AiTypes.Cat.CAMO, "static": AiTypes.Cat.STATIC_DEF,
	"light": AiTypes.Cat.LIGHT, "transport": AiTypes.Cat.TRANSPORT,
}

var roster_id: String = ""
var opener: Array = []  ## Array[Dictionary] steps
var targets: Array = []
var research: Array = []  ## {id, prio, when?}
var composition: Array = []  ## per phase: PackedInt32Array(ROLE_COUNT) weights (0 = not wanted)
var counters: Dictionary = {}  ## trigger name -> {trigger:{...}, mult:{ROLE:q8}, strong:{share_ge, mult}, structs:[...]}
var hysteresis_ticks: int = 6000
var phase_ticks: PackedInt32Array = PackedInt32Array([3000, 9000, 21600])  ## buildup / midgame / late start ticks
var errors: PackedStringArray = PackedStringArray()


static func resolve(store: AiDataStore, p_roster_id: String) -> AiDoctrine:
	var d: AiDoctrine = AiDoctrine.new()
	d.roster_id = p_roster_id
	var raw: Dictionary = store.extra.get(FILE_BASE, {})
	var base: Dictionary = (raw.get("base", {}) as Dictionary).duplicate(true)
	d.hysteresis_ticks = int(raw.get("hysteresis_ticks", 6000))
	var pt: Array = raw.get("phase_ticks", [3000, 9000, 21600])
	if pt.size() == 3:
		d.phase_ticks = PackedInt32Array([int(pt[0]), int(pt[1]), int(pt[2])])
	d.counters = (raw.get("counters", {}) as Dictionary).duplicate(true)
	var parts: PackedStringArray = p_roster_id.split(".")
	var code: String = parts[1] if parts.size() >= 3 else ""
	var fdata: Dictionary = store.extra.get("ai_faction_%s.json" % code, {})
	if fdata.has("base"):
		d._apply(base, fdata["base"] as Dictionary)
	var rosters: Dictionary = fdata.get("rosters", {})
	if rosters.has(p_roster_id):
		d._apply(base, rosters[p_roster_id] as Dictionary)
	d.opener = base.get("opener", [])
	d.targets = base.get("targets", [])
	d.research = base.get("research", [])
	d._compile_composition(base.get("composition", {}) as Dictionary)
	d._check_ids(d.opener)
	d._check_ids(d.targets)
	return d


func _apply(base: Dictionary, patch: Dictionary) -> void:
	for key: String in PATCH_KEYS:
		if patch.has(key + "_patch"):
			var lst: Array = base.get(key, [])
			_patch_list(lst, patch[key + "_patch"] as Dictionary, key)
			base[key] = lst
	if patch.has("composition_patch"):
		var comp: Dictionary = base.get("composition", {})
		var cp: Dictionary = patch["composition_patch"]
		for ph: String in cp:
			var row: Dictionary = comp.get(ph, {})
			var pr: Dictionary = cp[ph]
			for role_name: String in pr:
				if pr[role_name] == null:
					row.erase(role_name)
				else:
					row[role_name] = int(pr[role_name])
			comp[ph] = row
		base["composition"] = comp


func _index_of(lst: Array, step_id: String) -> int:
	for i: int in lst.size():
		if str((lst[i] as Dictionary).get("id", "")) == step_id:
			return i
	return -1


func _patch_list(lst: Array, patch: Dictionary, what: String) -> void:
	for sid: Variant in patch.get("remove", []):
		var i: int = _index_of(lst, str(sid))
		if i < 0:
			errors.append("V1: %s remove '%s' not found (%s)" % [what, str(sid), roster_id])
		else:
			lst.remove_at(i)
	var rep: Dictionary = patch.get("replace", {})
	for sid2: String in rep:
		var i2: int = _index_of(lst, sid2)
		if i2 < 0:
			errors.append("V1: %s replace '%s' not found (%s)" % [what, sid2, roster_id])
		else:
			lst[i2] = (rep[sid2] as Dictionary).duplicate(true)
	var ib: Dictionary = patch.get("insert_before", {})
	for sid3: String in ib:
		var i3: int = _index_of(lst, sid3)
		if i3 < 0:
			errors.append("V1: %s insert_before '%s' not found (%s)" % [what, sid3, roster_id])
			continue
		for s: Variant in ib[sid3]:
			lst.insert(i3, (s as Dictionary).duplicate(true))
			i3 += 1
	var ia: Dictionary = patch.get("insert_after", {})
	for sid4: String in ia:
		var i4: int = _index_of(lst, sid4)
		if i4 < 0:
			errors.append("V1: %s insert_after '%s' not found (%s)" % [what, sid4, roster_id])
			continue
		for s2: Variant in ia[sid4]:
			i4 += 1
			lst.insert(i4, (s2 as Dictionary).duplicate(true))
	for s3: Variant in patch.get("append", []):
		lst.append((s3 as Dictionary).duplicate(true))


func _check_ids(lst: Array) -> void:
	var seen: Dictionary = {}
	for s: Variant in lst:
		var sid: String = str((s as Dictionary).get("id", ""))
		if seen.has(sid):
			errors.append("V11: duplicate step id '%s' (%s)" % [sid, roster_id])
		seen[sid] = true


func _compile_composition(comp: Dictionary) -> void:
	composition.clear()
	for ph: String in PHASES:
		var w: PackedInt32Array = PackedInt32Array()
		w.resize(AiTypes.ROLE_COUNT)
		var row: Dictionary = comp.get(ph, {})
		for rn: String in row:
			var b: int = AiTypes.role_bit(rn)
			if b < 0:
				errors.append("V8: unknown role '%s' in composition (%s)" % [rn, roster_id])
				continue
			w[b] = maxi(int(row[rn]), 0)
		composition.append(w)


## Phase index (0 opening .. 3 late) for a tick; `tech_scale_x100` stretches the thresholds (slower AIs stay longer in a phase).
func phase_at(tick: int, tech_scale_x100: int = 100) -> int:
	var t: int = tick * 100 / maxi(tech_scale_x100, 1)
	if t < phase_ticks[0]:
		return AiTypes.Phase.OPENING
	if t < phase_ticks[1]:
		return AiTypes.Phase.BUILDUP
	if t < phase_ticks[2]:
		return AiTypes.Phase.MIDGAME
	return AiTypes.Phase.LATE


static func struct_kind_of(name: String) -> int:
	return int(STRUCT_KINDS.get(name, -1))


static func cat_of(name: String) -> int:
	return int(CAT_NAMES.get(name, -1))


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([opener.size(), targets.size(), research.size(), errors.size()])
	for w: PackedInt32Array in composition:
		v.append(AiRng.hash_ints(w))
	return AiRng.hash_ints(v)
