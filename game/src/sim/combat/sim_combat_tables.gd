class_name SimCombatTables
extends RefCounted
## The private combat compiler (replaces the spec's DefCombatCompiler): derives SimCombatDef / SimCombatWarhead
## tables from one player's DefPlayerView (roster clones) at world init. One instance per player view plus one
## neutral instance (view null: base defs), held by SimCombatSystem. Reads content ONLY through GameData / Def*.

var data: GameData = null
var view: DefPlayerView = null
var units: Array[SimCombatDef] = []  ## index = unit def idx; null = not in this roster
var structures: Array[SimCombatDef] = []
var zones: Array[SimCombatDef] = []
var neutrals: Array[SimCombatDef] = []
var warheads: Array[SimCombatWarhead] = []


## `v` null builds the neutral table (every def of `d`, base values).
static func build(d: GameData, v: DefPlayerView) -> SimCombatTables:
	var t: SimCombatTables = SimCombatTables.new()
	t.data = d
	t.view = v
	for i: int in d.units.size():
		var u: DefUnit = null
		if v != null:
			u = v.roster.unit(i) if v.roster.has_unit(i) else null
		else:
			u = d.units[i]
		t.units.append(t._unit_def(u) if u != null else null)
	for i: int in d.structures.size():
		var s: DefStructure = null
		if v != null:
			s = v.roster.structure(i) if v.roster.has_structure(i) else null
		else:
			s = d.structures[i]
		t.structures.append(t._structure_def(s) if s != null else null)
	for z: DefZone in d.zones:
		var zd: SimCombatDef = SimCombatDef.new()
		zd.kind = SimEntity.Kind.ZONE
		zd.def_idx = z.index
		zd.armor = DefEnums.ArmorClass.BUILDING_LIGHT
		t.zones.append(zd)
	for n: DefNeutral in d.neutrals:
		var nd: SimCombatDef = SimCombatDef.new()
		nd.kind = SimEntity.Kind.NEUTRAL
		nd.def_idx = n.index
		nd.armor = n.armor_class
		t.neutrals.append(nd)
	return t


## The compiled def for an entity kind (SimEntity.Kind) and def index; null when absent (wrecks of units outside
## this roster: the caller falls back to the neutral table).
func def_of(ent_kind: int, def_idx: int) -> SimCombatDef:
	if def_idx < 0:
		return null
	match ent_kind:
		SimEntity.Kind.STRUCTURE:
			return structures[def_idx] if def_idx < structures.size() else null
		SimEntity.Kind.ZONE:
			return zones[def_idx] if def_idx < zones.size() else null
		SimEntity.Kind.NEUTRAL:
			return neutrals[def_idx] if def_idx < neutrals.size() else null
	return units[def_idx] if def_idx < units.size() else null


## Appends a warhead built elsewhere (powers, superweapons, chain effects); returns its index.
func add_warhead(w: SimCombatWarhead) -> int:
	w.idx = warheads.size()
	warheads.append(w)
	return w.idx


func _unit_def(u: DefUnit) -> SimCombatDef:
	var c: SimCombatDef = SimCombatDef.new()
	c.kind = SimEntity.Kind.UNIT
	c.def_idx = u.index
	c.tags = u.tags
	c.armor = u.armor_class
	c.is_aircraft = 1 if (u.tags & DefEnums.UT_AIRCRAFT) != 0 else 0
	if (u.tags & DefEnums.UT_INFANTRY) != 0:
		c.cflags |= SimCombatConsts.CF_SUPPRESSIBLE
	_build_mounts(c, u.id, u.weapons, u.ability_of(DefEnums.AbilityKind.DEPLOY))
	_build_armor_rows(c, u.abilities)
	if view != null:
		c.static_resist = view.roster.static_sums(DefEnums.Kind.UNIT, u.index, DefEnums.Stat.RESIST)
	var car: DefAbility = u.ability_of(DefEnums.AbilityKind.CARRIER)
	if car != null:
		for w: Variant in car.params.get("wings", []):
			c.carrier_bays = maxi(c.carrier_bays, int((w as Dictionary).get("wing_size_n", 0)))
	c.prio = _unit_prio(u, c)
	if c.is_aircraft == 1:
		SimAirSortie.derive(u, c)
	return c


func _structure_def(s: DefStructure) -> SimCombatDef:
	var c: SimCombatDef = SimCombatDef.new()
	c.kind = SimEntity.Kind.STRUCTURE
	c.def_idx = s.index
	c.tags = s.tags
	c.armor = s.armor_class
	c.pad_count = s.pads
	c.needs_power = 1 if (s.flags & DefEnums.SF_POWERED_DEFENSE) != 0 else 0
	# Aurora hits powered structures: consumers, powered defences, production, relay and strategic structures.
	if s.power < 0 or (s.flags & (DefEnums.SF_POWERED_DEFENSE | DefEnums.SF_PRODUCTION | DefEnums.SF_RELAY | DefEnums.SF_STRATEGIC)) != 0:
		c.emp_susceptible = 1
	_build_mounts(c, s.id, s.weapons, null)
	_build_armor_rows(c, s.abilities)
	if view != null:
		c.static_resist = view.roster.static_sums(DefEnums.Kind.STRUCTURE, s.index, DefEnums.Stat.RESIST)
	c.prio = 10 if c.n_mounts > 0 else 2
	return c


static func _unit_prio(u: DefUnit, c: SimCombatDef) -> int:
	if c.n_mounts == 0:
		return 3
	var by_armor: PackedInt32Array = PackedInt32Array([6, 7, 8, 9, 8, 9, 8, 9, 8, 9, 9])
	return by_armor[clampi(u.armor_class, 0, by_armor.size() - 1)]


func _build_mounts(c: SimCombatDef, label: String, weapons: Array[DefWeaponSlot], deploy: DefAbility) -> void:
	var n: int = mini(weapons.size(), SimCombatConsts.MAX_MOUNTS)
	var deployed_slots: Array = []
	if deploy != null:
		deployed_slots = deploy.params.get("deployed_slots_n", [])
	var nonlethal_mask: int = data.damage.nonlethal_mask
	for i: int in n:
		var s: DefWeaponSlot = weapons[i]
		var arch: DefWeaponArch = data.weapon_archs[s.arch] if s.arch >= 0 and s.arch < data.weapon_archs.size() else null
		var wh: SimCombatWarhead = SimCombatWarhead.from_slot(s, arch, nonlethal_mask, "%s#%d" % [label, i])
		var wclass: int = 0
		if (s.target_mask & DefEnums.L_AIR) != 0:
			wclass |= SimCombatConsts.WC_ANTI_AIR
			c.cflags |= SimCombatConsts.CF_HAS_AA
		if (s.target_mask & DefEnums.L_UNDER) != 0:
			wclass |= SimCombatConsts.WC_ANTI_SUB
			c.cflags |= SimCombatConsts.CF_HAS_ASW
		if s.fire_mode == DefEnums.FireMode.INDIRECT:
			wclass |= SimCombatConsts.WC_ARTILLERY
		if s.arch == DefEnums.WeaponArch.DEMOLITION_CANNON or s.arch == DefEnums.WeaponArch.BREACH_CHARGE:
			wclass |= SimCombatConsts.WC_ANTI_STRUCT
		var mk: int = SimCombatConsts.MK_HULL
		if s.mount == 1:
			mk = SimCombatConsts.MK_TURRET if s.turret_turn > 0 else SimCombatConsts.MK_FIXED
		var req_dep: int = -1
		if not deployed_slots.is_empty():
			req_dep = 1 if deployed_slots.has(i) else 0
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(SimCombatDef.MT)
		row[SimCombatDef.MT_SLOT] = i
		row[SimCombatDef.MT_KIND] = mk
		row[SimCombatDef.MT_ARC_CENTER] = 0
		row[SimCombatDef.MT_ARC_HALF] = mini(s.fire_arc / 2, Fp.ANGLE_HALF) if s.fire_arc > 0 else Fp.ANGLE_HALF
		row[SimCombatDef.MT_TURN] = s.turret_turn if mk == SimCombatConsts.MK_TURRET else 0
		row[SimCombatDef.MT_AIM_TOL] = SimCombatConsts.AIM_TOL_DEFAULT
		row[SimCombatDef.MT_BARRELS] = 1
		row[SimCombatDef.MT_INDEP] = 1 if (n > 1 and (wclass & (SimCombatConsts.WC_ANTI_AIR | SimCombatConsts.WC_ANTI_SUB)) != 0) else 0
		row[SimCombatDef.MT_WCLASS] = wclass
		row[SimCombatDef.MT_WH] = add_warhead(wh)
		row[SimCombatDef.MT_MODE_MASK] = s.mode_mask
		row[SimCombatDef.MT_REQ_DEPLOYED] = req_dep
		row[SimCombatDef.MT_FLAGS] = s.flags
		c.mounts.append_array(row)
		c.prof.append_array(SimWeaponProfile.derive(s, arch))
		c.slots.append(s)
	c.n_mounts = n


## Directional rows (layer 0) and the point-defence block from the def's abilities.
func _build_armor_rows(c: SimCombatDef, abilities: Array[DefAbility]) -> void:
	for a: DefAbility in abilities:
		match a.kind:
			DefEnums.AbilityKind.FRONTAL_SHIELD:
				var groups: int = int(a.params.get("resist_mask", DefEnums.RG_BULLET))
				var types: int = 0
				for dt: int in SimCombatConsts.DT_COUNT:
					if dt != SimCombatConsts.DT_EMP and (data.damage.group_mask[dt] & groups) != 0:
						types |= 1 << dt
				var f: int = SimCombatConsts.make_filter(types, SimCombatConsts.DC_DIRECT, SimCombatConsts.DC_SPLASH | SimCombatConsts.DC_INDIRECT | SimCombatConsts.DC_STRATEGIC)
				c.dir_rows.append_array(PackedInt32Array([f, 0, (int(a.params.get("arc_a", 0)) + 1) / 2, int(a.params.get("reduction_bp", 0)), 0]))
			DefEnums.AbilityKind.DIRECTIONAL_ARMOR:
				var fa: int = (int(a.params.get("front_arc_a", 0)) + 1) / 2
				c.dir_rows.append_array(PackedInt32Array([SimCombatConsts.FILTER_ALL_WEAPON, 0, fa, int(a.params.get("front_reduction_bp", 0)), 0]))
				var rear: int = int(a.params.get("rear_increase_bp", 0))
				if rear > 0:
					c.dir_rows.append_array(PackedInt32Array([SimCombatConsts.FILTER_ALL_WEAPON, Fp.ANGLE_HALF, 1024, -rear, 0]))
			DefEnums.AbilityKind.INTERCEPTOR:
				c.aps_count = int(a.params.get("charges_n", 1))
				c.aps_cooldown = int(a.params.get("cooldown_t", 0))
				c.aps_radius = int(a.params.get("range_u", 0))
