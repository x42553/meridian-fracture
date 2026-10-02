class_name SndSoundBank
extends RefCounted
## Bakes GameData + the audio event map into flat per-def tables (audio spec 3.6 / 5.4.7): unit and structure profiles,
## armor/layer/speed, weapon fire events, power and superweapon cue sets. Built once per match (< 5 ms). Every table is
## indexed by the def index of ITS kind (SimEntity.def_idx selects the table by SimEntity.kind).

const TAG_COLLECTOR: int = 1
const TAG_LAUNCHER: int = 2
const TAG_DEFENSE: int = 4
const TAG_RADAR: int = 8
const TAG_LAB: int = 16
const TAG_HQ: int = 32
const TAG_DRONE: int = 64
const TAG_TRANSPORT: int = 128

const PHASES_POWER: Array[StringName] = [&"activate", &"loop", &"end"]
const PHASES_SW: Array[StringName] = [&"charge", &"launch", &"loop", &"impact", &"end"]

var map: SndEventMap = null
var mix: SndMixConfig = null
var data: GameData = null

# units (index = DefUnit index)
var unit_profile: Array[SndProfileDef] = []
var unit_armor: PackedByteArray = PackedByteArray()
var unit_layer: PackedByteArray = PackedByteArray()
var unit_move: PackedByteArray = PackedByteArray()
var unit_tags: PackedInt32Array = PackedInt32Array()
var unit_speed: PackedInt32Array = PackedInt32Array()
var unit_faction: PackedStringArray = PackedStringArray()
# structures
var struct_profile: Array[SndProfileDef] = []
var struct_area: PackedByteArray = PackedByteArray()
var struct_tags: PackedInt32Array = PackedInt32Array()
var struct_faction: PackedStringArray = PackedStringArray()
# weapons: index = frozen WeaponArch (EV_FIRE.b is the archetype index)
var arch_kind: PackedByteArray = PackedByteArray()
var arch_flight: PackedByteArray = PackedByteArray()
var arch_fire: Array[SndEventDef] = []  ## default fire event (tank_cannon: the medium variant)
var arch_beam: PackedByteArray = PackedByteArray()
# powers and superweapons
var power_cue: Array[Dictionary] = []
var power_class: PackedStringArray = PackedStringArray()
var power_warning_ticks: PackedInt32Array = PackedInt32Array()
var power_radius: PackedInt32Array = PackedInt32Array()
var sw_cue: Array[Dictionary] = []
var sw_name: PackedStringArray = PackedStringArray()
var sw_duration_ticks: PackedInt32Array = PackedInt32Array()
var sw_warning_ticks: PackedInt32Array = PackedInt32Array()
var sw_radius: PackedInt32Array = PackedInt32Array()  ## sub-cells
var sw_launcher: PackedInt32Array = PackedInt32Array()  ## structure def index of the launcher
var coverage: Dictionary = {}
var unresolved: PackedStringArray = PackedStringArray()


func bake(p_data: GameData, p_map: SndEventMap, p_mix: SndMixConfig) -> void:
	data = p_data
	map = p_map
	mix = p_mix
	unresolved = PackedStringArray()
	coverage = {"units_explicit": 0, "units_table": 0, "units_derived": 0, "units_generic": 0, "structs_explicit": 0, "structs_table": 0,
		"structs_derived": 0, "structs_generic": 0, "weapons_fallback": 0}
	_bake_weapons()
	_bake_units()
	_bake_structures()
	_bake_powers()
	_bake_superweapons()


func _prof(id: String) -> SndProfileDef:
	return map.get_profile(StringName(id))


func _bake_weapons() -> void:
	var n: int = SndUnits.ARCH_TABLE.size()
	arch_kind.resize(n)
	arch_flight.resize(n)
	arch_beam.resize(n)
	arch_fire.clear()
	for a: int in n:
		arch_kind[a] = SndUnits.arch_kind(a)
		arch_flight[a] = SndUnits.arch_flight(a)
		var nm: String = SndUnits.arch_name(a)
		arch_beam[a] = 1 if nm == "beam_thermal" else 0
		var id: StringName = fire_event_id(a, "")
		var def: SndEventDef = map.get_def(id)
		if def == null:
			coverage["weapons_fallback"] = int(coverage["weapons_fallback"]) + 1
			def = map.get_def(map.resolve(&"weapon_fire", {"archetype": "__none__"}))
			if def == null:
				unresolved.append("weapon:%s" % nm)
		arch_fire.append(def)


## Event id of a weapon archetype's fire sound; tank_cannon takes the suffix of the shooter's profile (default medium).
func fire_event_id(arch: int, variant: String) -> StringName:
	var nm: String = SndUnits.arch_name(arch)
	if nm == "tank_cannon":
		nm = "tank_cannon_" + (variant if variant != "" else "medium")
	return map.resolve(&"weapon_fire", {"archetype": nm})


func fire_def(arch: int, variant: String) -> SndEventDef:
	if arch < 0 or arch >= arch_fire.size():
		return map.get_def(map.resolve(&"weapon_fire", {"archetype": "__none__"}))
	if variant == "" or SndUnits.arch_name(arch) != "tank_cannon":
		return arch_fire[arch]
	var d: SndEventDef = map.get_def(fire_event_id(arch, variant))
	return d if d != null else arch_fire[arch]


func _faction_code(f: int) -> String:
	if f >= 0 and f < data.factions.size():
		return data.factions[f].code.to_lower()
	return ""


func _bake_units() -> void:
	var n: int = data.units.size()
	unit_profile.resize(n)
	unit_armor.resize(n)
	unit_layer.resize(n)
	unit_move.resize(n)
	unit_tags.resize(n)
	unit_speed.resize(n)
	unit_faction.resize(n)
	for i: int in n:
		var u: DefUnit = data.units[i]
		unit_armor[i] = u.armor_class
		unit_layer[i] = u.home_layer
		unit_move[i] = u.move_class
		unit_speed[i] = u.speed
		unit_faction[i] = _faction_code(u.faction)
		var tags: int = 0
		if u.id.ends_with("collector"):
			tags |= TAG_COLLECTOR
		if u.unit_class == DefEnums.UnitClass.DRONE:
			tags |= TAG_DRONE
		if u.id.ends_with("landing_transport"):
			tags |= TAG_TRANSPORT
		unit_tags[i] = tags
		unit_profile[i] = _unit_profile(u)


func _unit_profile(u: DefUnit) -> SndProfileDef:
	if u.pres_snd_profile != "":
		var p: SndProfileDef = _prof(u.pres_snd_profile)
		if p != null:
			coverage["units_explicit"] = int(coverage["units_explicit"]) + 1
			return p
		unresolved.append("def:%s" % u.id)
	var t: StringName = StringName(str(map.unit_profile.get(u.id, "")))
	if t != &"":
		var p2: SndProfileDef = map.get_profile(t)
		if p2 != null:
			coverage["units_table"] = int(coverage["units_table"]) + 1
			return p2
	# derived from the def's own fields
	var id: String = ""
	if u.unit_class == DefEnums.UnitClass.DRONE:
		id = "snd.profile.summon_drone"
	elif u.unit_class == DefEnums.UnitClass.SUMMON:
		id = "snd.profile.summon_capsule" if u.move_class == DefEnums.MoveClass.STATIC else "snd.profile.decoy"
	elif u.id.ends_with("collector"):
		id = "snd.profile.svc_collector"
	elif u.id.ends_with("engineer"):
		id = "snd.profile.svc_engineer"
	elif u.id.ends_with("mobile_construction_vehicle"):
		id = "snd.profile.svc_mcv"
	elif u.id.ends_with("landing_transport"):
		id = "snd.profile.svc_landing_transport"
	var p3: SndProfileDef = _prof(id) if id != "" else null
	if p3 != null:
		coverage["units_derived"] = int(coverage["units_derived"]) + 1
		return p3
	var g: SndProfileDef = _prof("snd.profile.generic." + DefEnums.MOVE_NAMES[clampi(u.move_class, 0, DefEnums.MOVE_NAMES.size() - 1)])
	if g == null:
		g = _prof("snd.profile.generic.tracked")
	if g == null:
		unresolved.append("def:%s" % u.id)
		g = SndProfileDef.new()
		g.voice_class = SndUnits.VoiceClass.VEHICLE
	coverage["units_generic"] = int(coverage["units_generic"]) + 1
	return g


func _bake_structures() -> void:
	var n: int = data.structures.size()
	struct_profile.resize(n)
	struct_area.resize(n)
	struct_tags.resize(n)
	struct_faction.resize(n)
	for i: int in n:
		var s: DefStructure = data.structures[i]
		struct_faction[i] = _faction_code(s.faction)
		var cells: int = s.fp_w * s.fp_h
		if s.fp_mask.size() == s.fp_w * s.fp_h:
			cells = 0
			for b: int in s.fp_mask:
				cells += 1 if b != 0 else 0
		struct_area[i] = SndUnits.area_class(cells)
		var tags: int = 0
		if s.superweapon >= 0:
			tags |= TAG_LAUNCHER
		if not s.weapons.is_empty():
			tags |= TAG_DEFENSE
		if s.id.ends_with(".radar"):
			tags |= TAG_RADAR
		if s.id.ends_with(".laboratory"):
			tags |= TAG_LAB
		if s.id.ends_with(".headquarters"):
			tags |= TAG_HQ
		struct_tags[i] = tags
		struct_profile[i] = _struct_profile(s)


func _struct_profile(s: DefStructure) -> SndProfileDef:
	if s.pres_snd_profile != "":
		var p: SndProfileDef = _prof(s.pres_snd_profile)
		if p != null:
			coverage["structs_explicit"] = int(coverage["structs_explicit"]) + 1
			return p
		unresolved.append("def:%s" % s.id)
	var t: SndProfileDef = _prof(str(map.structure_profile.get(s.id, "")))
	if t != null:
		coverage["structs_table"] = int(coverage["structs_table"]) + 1
		return t
	var code: String = _faction_code(s.faction)
	var id: String = ""
	if s.id.begins_with("structure.shared."):
		var nm: String = s.id.trim_prefix("structure.shared.")
		nm = "turret" if nm == "anti_tank_turret" else ("hq" if nm == "headquarters" else nm)
		id = "snd.profile.struct." + nm
	elif s.superweapon >= 0:
		id = "snd.profile.struct.sw_" + code
	elif s.id.ends_with(".relay"):
		id = "snd.profile.struct.relay"
	else:
		id = "snd.profile.struct.adv_" + code
	var p2: SndProfileDef = _prof(id)
	if p2 != null:
		coverage["structs_derived"] = int(coverage["structs_derived"]) + 1
		return p2
	var g: SndProfileDef = _prof("snd.profile.generic.static")
	if g == null:
		unresolved.append("def:%s" % s.id)
		g = SndProfileDef.new()
		g.voice_class = SndUnits.VoiceClass.STRUCTURE
	coverage["structs_generic"] = int(coverage["structs_generic"]) + 1
	return g


func _bake_powers() -> void:
	var n: int = data.powers.size()
	power_cue.clear()
	power_class.resize(n)
	power_warning_ticks.resize(n)
	power_radius.resize(n)
	for i: int in n:
		var p: DefPower = data.powers[i]
		var cls: String = str(map.power_cues.get(p.id, "generic"))
		power_class[i] = cls
		power_warning_ticks[i] = p.warning_t
		power_radius[i] = p.radius
		var cues: Dictionary = {}
		for ph: StringName in PHASES_POWER:
			var d: SndEventDef = map.get_def(StringName("snd.power.%s.%s" % [cls, ph]))
			if d != null:
				cues[ph] = d
		if not cues.has(&"activate"):
			var gd: SndEventDef = map.get_def(&"snd.power.generic.activate")
			if gd != null:
				cues[&"activate"] = gd
			else:
				unresolved.append("power:%s" % p.id)
		power_cue.append(cues)


func _bake_superweapons() -> void:
	var n: int = data.superweapons.size()
	sw_cue.clear()
	sw_name.resize(n)
	sw_duration_ticks.resize(n)
	sw_warning_ticks.resize(n)
	sw_radius.resize(n)
	sw_launcher.resize(n)
	for i: int in n:
		var s: DefSuperweapon = data.superweapons[i]
		var nm: String = str(map.sw_cues.get(s.id, ""))
		sw_name[i] = nm
		sw_duration_ticks[i] = s.duration_t
		sw_warning_ticks[i] = s.warning_t
		sw_radius[i] = s.radius
		sw_launcher[i] = s.launcher
		var cues: Dictionary = {}
		for ph: StringName in PHASES_SW:
			var d: SndEventDef = map.get_def(StringName("snd.sw.%s.%s" % [nm, ph]))
			if d != null:
				cues[ph] = d
		if nm == "" or not (cues.has(&"launch") or cues.has(&"impact")):
			unresolved.append("sw:%s" % s.id)
		sw_cue.append(cues)


func profile_of(kind: int, def_idx: int) -> SndProfileDef:
	if kind == SimEntity.Kind.STRUCTURE:
		return struct_profile[def_idx] if def_idx >= 0 and def_idx < struct_profile.size() else null
	return unit_profile[def_idx] if def_idx >= 0 and def_idx < unit_profile.size() else null


func tags_of(kind: int, def_idx: int) -> int:
	if kind == SimEntity.Kind.STRUCTURE:
		return struct_tags[def_idx] if def_idx >= 0 and def_idx < struct_tags.size() else 0
	return unit_tags[def_idx] if def_idx >= 0 and def_idx < unit_tags.size() else 0


func faction_of(kind: int, def_idx: int) -> String:
	if kind == SimEntity.Kind.STRUCTURE:
		return struct_faction[def_idx] if def_idx >= 0 and def_idx < struct_faction.size() else ""
	return unit_faction[def_idx] if def_idx >= 0 and def_idx < unit_faction.size() else ""
