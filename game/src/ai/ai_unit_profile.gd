class_name AiUnitProfile
extends RefCounted
## Derived combat profile of a resolved def (ai.md 4.3 / 5.3.5), built once per (roster, def) from the roster's resolved
## DefUnit / DefStructure (hp, cost, weapons, armor). dps_x100[c] = damage per second x 100 against armor class c summed over
## the weapon slots and the damage matrix (0 = cannot hurt that class, also when the weapon cannot reach the class's layer).
## Slots that are active only in another mode are folded into dps_x100_alt. `power` = isqrt(hp x mean dps / 100).

const NCLASS: int = DefEnums.ArmorClass.COUNT

var def: int = -1
var is_structure: bool = false
var cost: int = 0
var build_ticks: int = 0
var hp: int = 0
var speed: int = 0
var speed_water: int = 0
var sight: int = 0
@warning_ignore("shadowed_global_identifier")
var range: int = 0  ## max weapon range (units)
var min_range: int = 0
var dps_x100: PackedInt32Array = PackedInt32Array()  ## per armor class
var dps_x100_alt: PackedInt32Array = PackedInt32Array()  ## mode-dependent slots (deploy / mode switch)
var hits_mask: int = 0  ## DefEnums layer bits L_GROUND=1, L_AIR=2, L_WATER=4, L_UNDER=8
var armor_class: int = 0
var layer: int = 0
var move_class: int = 0
var tag_mask: int = 0
var role_mask: int = 0
var handler_mask: int = 0
var transport_cap: int = 0
var deploy_ticks: int = 0
var mode_count: int = 0
var splash_r: int = 0
var value: int = 0  ## = cost
var power: int = 0
var tier: int = 0
var category: int = AiTypes.Cat.LIGHT  ## AiTypes.Cat (enemy-profile bucket)


## `res` = the resolver of the roster (role/handler masks); `dmg` = data.damage.
static func build_unit(data: GameData, roster: DefRoster, u_idx: int, res: AiRoleResolver) -> AiUnitProfile:
	var d: DefUnit = roster.unit(u_idx)
	if d == null:
		return null
	var p: AiUnitProfile = AiUnitProfile.new()
	p.def = u_idx
	p.cost = maxi(d.cost, 0)
	p.value = p.cost
	p.build_ticks = d.build_ticks
	p.hp = d.health
	p.speed = d.speed
	p.speed_water = d.speed_water
	p.sight = d.sight
	p.range = d.max_range
	p.min_range = d.min_range
	p.armor_class = d.armor_class
	p.layer = d.home_layer
	p.move_class = d.move_class
	p.tag_mask = d.tags
	p.tier = d.tier
	p.transport_cap = d.transport_squads
	p.mode_count = 0
	p.role_mask = res.mask_of(u_idx)
	p.handler_mask = res.handlers_of(u_idx)
	var dep: DefAbility = d.ability_of(DefEnums.AbilityKind.DEPLOY)
	if dep != null:
		p.deploy_ticks = int(dep.params.get("deploy_t", 0))
	if d.has_ability(DefEnums.AbilityKind.MODE_SWITCH):
		p.mode_count = 2
	p._fill_weapons(data, d.weapons)
	p.category = _category_of(d.tags)
	return p


static func build_structure(data: GameData, roster: DefRoster, s_idx: int, _res: AiRoleResolver) -> AiUnitProfile:
	var d: DefStructure = roster.structure(s_idx)
	if d == null:
		return null
	var p: AiUnitProfile = AiUnitProfile.new()
	p.def = s_idx
	p.is_structure = true
	p.cost = maxi(d.cost, 0)
	p.value = p.cost
	p.build_ticks = d.build_ticks
	p.hp = d.health
	p.sight = d.sight
	p.armor_class = d.armor_class
	p.role_mask = 1 << AiTypes.R_STRUCTURE
	p._fill_weapons(data, d.weapons)
	p.range = 0
	for w: DefWeaponSlot in d.weapons:
		p.range = maxi(p.range, w.range)
	p.category = AiTypes.Cat.STATIC_DEF if not d.weapons.is_empty() else AiTypes.Cat.LIGHT
	return p


func _fill_weapons(data: GameData, weapons: Array[DefWeaponSlot]) -> void:
	dps_x100.resize(NCLASS)
	dps_x100.fill(0)
	dps_x100_alt.resize(NCLASS)
	dps_x100_alt.fill(0)
	var tps: int = SimConfig.TPS
	for w: DefWeaponSlot in weapons:
		var reload: int = maxi(w.reload_ticks, 1)
		var per_s_x100: int = w.damage * maxi(w.hits_per_volley, 1) * tps * 100 / reload
		var alt: bool = w.mode_mask != 0 and (w.mode_mask & 1) == 0
		hits_mask |= w.target_mask
		splash_r = maxi(splash_r, w.splash_radius)
		for c: int in NCLASS:
			if not _layer_ok(w.target_mask, c):
				continue
			var pct: int = data.damage.pct(w.dtype, c)
			var v: int = per_s_x100 * pct / 100
			if w.splash_radius >= Fp.CELL and c == DefEnums.ArmorClass.INFANTRY:
				v = v * 130 / 100  # splash bonus versus infantry (ai.md 5.3.5)
			if alt:
				dps_x100_alt[c] += v
			else:
				dps_x100[c] += v
	var sum: int = 0
	var n: int = 0
	for c2: int in NCLASS:
		if dps_x100[c2] > 0:
			sum += dps_x100[c2]
			n += 1
	power = Fp.isqrt(hp * (sum / maxi(n, 1)) / 100)


## True when a weapon with `target_mask` can reach armor class c (AIR armor needs the air layer, SHIP armor the water layer).
static func _layer_ok(target_mask: int, c: int) -> bool:
	if c == DefEnums.ArmorClass.AIR_LIGHT or c == DefEnums.ArmorClass.AIR_HEAVY:
		return (target_mask & DefEnums.L_AIR) != 0
	if c == DefEnums.ArmorClass.SHIP_LIGHT or c == DefEnums.ArmorClass.SHIP_HEAVY:
		return (target_mask & (DefEnums.L_WATER | DefEnums.L_UNDER)) != 0
	return (target_mask & DefEnums.L_GROUND) != 0


static func _category_of(tags: int) -> int:
	if (tags & DefEnums.UT_AIRCRAFT) != 0:
		return AiTypes.Cat.AIR
	if (tags & DefEnums.UT_SUBMARINE) != 0:
		return AiTypes.Cat.SUB
	if (tags & DefEnums.UT_SHIP) != 0:
		return AiTypes.Cat.NAVAL
	if (tags & DefEnums.UT_TRANSPORT) != 0:
		return AiTypes.Cat.TRANSPORT
	if (tags & DefEnums.UT_ARTILLERY) != 0 or (tags & DefEnums.UT_SIEGE) != 0 and (tags & DefEnums.UT_TANK) == 0:
		return AiTypes.Cat.ARTILLERY
	if (tags & DefEnums.UT_TANK) != 0:
		return AiTypes.Cat.ARMOR
	if (tags & DefEnums.UT_INFANTRY) != 0:
		return AiTypes.Cat.INFANTRY
	return AiTypes.Cat.LIGHT


## Mean dps x100 over the classes the def can hurt (0 when unarmed).
func dps_avg_x100() -> int:
	var sum: int = 0
	var n: int = 0
	for v: int in dps_x100:
		if v > 0:
			sum += v
			n += 1
	return sum / maxi(n, 1)


func is_combat() -> bool:
	return dps_avg_x100() > 0
