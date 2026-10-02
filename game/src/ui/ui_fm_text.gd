class_name UiFmText
extends RefCounted
## Plain-English wording for the Field Manual (ui.md 5.17): names of the data vocabulary (armor classes, move classes, damage
## types, layers), one sentence per ability kind built from the resolved ability parameters, tooltips and small formatters.
## Pure static; every number goes through `DefFormat` (integer maths, one decimal), so the strings are locale independent.

const STAT_LABELS: Dictionary = {
	"cost": "Cost", "build_time": "Build time", "health": "Health", "speed": "Speed", "water_speed": "Water speed",
	"sight": "Sight", "power": "Power", "damage": "Damage", "range": "Range", "reload": "Reload",
}
## Stats where a lower resolved value is the improvement (cost, times).
const LOWER_IS_BETTER: Array[int] = [DefEnums.Stat.COST, DefEnums.Stat.BUILD_TIME, DefEnums.Stat.RELOAD, DefEnums.Stat.REARM,
	DefEnums.Stat.REPAIR_COST]
const STAT_TEXT: Dictionary = {
	DefEnums.Stat.COST: "cost", DefEnums.Stat.BUILD_TIME: "build time", DefEnums.Stat.HEALTH: "health",
	DefEnums.Stat.SPEED: "speed", DefEnums.Stat.DAMAGE: "damage", DefEnums.Stat.RANGE: "range",
	DefEnums.Stat.RELOAD: "reload interval", DefEnums.Stat.REARM: "rearm time", DefEnums.Stat.SIGHT: "sight",
	DefEnums.Stat.POWER: "power output", DefEnums.Stat.REPAIR_RATE: "repair rate", DefEnums.Stat.REPAIR_COST: "repair cost",
	DefEnums.Stat.PROJ_SPEED: "projectile speed",
}
const KIND_TITLES: Dictionary = {
	DefEnums.Kind.UNIT: "Unit", DefEnums.Kind.STRUCTURE: "Structure", DefEnums.Kind.RESEARCH: "Research",
	DefEnums.Kind.POWER: "Support power", DefEnums.Kind.SUPERWEAPON: "Superweapon",
}


## Display name of a def: its bible name, else the last id segment humanised ("summon.napc.uav" -> "UAV").
static func def_name(d: DefBase) -> String:
	if d == null:
		return "?"
	if not d.ui_name.is_empty():
		return d.ui_name
	var seg: String = d.id.get_slice(".", d.id.get_slice_count(".") - 1)
	var parts: PackedStringArray = seg.split("_")
	for i: int in parts.size():
		parts[i] = parts[i].to_upper() if parts[i].length() <= 3 else parts[i].capitalize()
	return " ".join(parts)


## "light_vehicle" -> "Light vehicle".
static func humanize(id: String) -> String:
	var s: String = id.replace("_", " ").strip_edges()
	return s.substr(0, 1).to_upper() + s.substr(1) if not s.is_empty() else s


static func armor_name(armor_class: int) -> String:
	return humanize(DefEnums.ARMOR_NAMES[armor_class]) if armor_class >= 0 and armor_class < DefEnums.ARMOR_NAMES.size() else "?"


static func move_name(move_class: int) -> String:
	return humanize(DefEnums.MOVE_NAMES[move_class]) if move_class >= 0 and move_class < DefEnums.MOVE_NAMES.size() else "?"


static func damage_name(dtype: int) -> String:
	if dtype < 0 or dtype >= DefEnums.DAMAGE_NAMES.size():
		return "?"
	match dtype:
		DefEnums.DamageType.AP:
			return "Armor-piercing"
		DefEnums.DamageType.HE:
			return "High explosive"
	return humanize(DefEnums.DAMAGE_NAMES[dtype])


static func unit_class_name(unit_class: int) -> String:
	return humanize(DefEnums.UNIT_CLASS_NAMES[unit_class]) if unit_class >= 0 and unit_class < DefEnums.UNIT_CLASS_NAMES.size() else "?"


## "Ground, Surface water" for a layer mask (DefEnums.L_*).
static func layer_text(mask: int) -> String:
	var out: PackedStringArray = PackedStringArray()
	for i: int in DefEnums.LAYER_NAMES.size():
		if (mask >> i) & 1 == 1:
			out.append(humanize(DefEnums.LAYER_NAMES[i]))
	return ", ".join(out) if not out.is_empty() else "None"


## What a weapon may hit: "Ground, Air".
static func target_text(mask: int) -> String:
	return layer_text(mask)


static func ability_name(kind: int) -> String:
	if kind < 0 or kind >= DefEnums.ABILITY_NAMES.size() or DefEnums.ABILITY_NAMES[kind].is_empty():
		return "Ability"
	return humanize(DefEnums.ABILITY_NAMES[kind])


static func stat_text(stat: int) -> String:
	return str(STAT_TEXT.get(stat, "stat"))


## "on water only" / "in a civilian garrison" / "with paid repairs" (asterisk tooltip, 5.17).
static func cond_text(cond: int) -> String:
	match cond:
		DefEnums.Cond.ON_WATER, DefEnums.Cond.ON_WATER_RT:
			return "on water only"
		DefEnums.Cond.IN_CIVILIAN_GARRISON:
			return "in a civilian garrison"
		DefEnums.Cond.PAID_VEHICLE_REPAIR:
			return "with paid repairs"
		DefEnums.Cond.STATIONARY:
			return "while stationary"
		DefEnums.Cond.OUT_OF_COMBAT:
			return "out of combat"
		DefEnums.Cond.DEPLOYED:
			return "while deployed"
		DefEnums.Cond.CAMOUFLAGED:
			return "while camouflaged"
		DefEnums.Cond.IN_ZONE:
			return "inside a zone"
		DefEnums.Cond.BEHIND_COVER:
			return "behind cover"
		DefEnums.Cond.STRUCTURE_POWERED:
			return "while powered"
		DefEnums.Cond.IN_RELAY_FIELD:
			return "inside a relay field"
		DefEnums.Cond.NEAR_FRIENDLY_UNIT, DefEnums.Cond.NEAR_FRIENDLY_STRUCTURE, DefEnums.Cond.TARGET_NEAR_FRIENDLY_UNIT:
			return "near friendly forces"
		DefEnums.Cond.RECENTLY_DISEMBARKED:
			return "just after disembarking"
	return ""


static func layer_source_text(layer: int) -> String:
	return "faction trait" if layer == 1 else "subfaction"


## Structure placement flags in plain text.
static func place_flags_text(mask: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if mask & DefEnums.PLACE_SHORELINE != 0:
		out.append("Must be placed on the shoreline")
	if mask & DefEnums.PLACE_MAX_ONE_STRATEGIC != 0:
		out.append("Maximum one strategic structure per player")
	if mask & DefEnums.PLACE_NO_RADIUS_EXTENSION != 0:
		out.append("Does not extend the build radius")
	return out


static func target_mode_text(mode: int) -> String:
	match mode:
		DefEnums.TargetMode.POINT:
			return "Target a point"
		DefEnums.TargetMode.LINE:
			return "Target a line"
		DefEnums.TargetMode.OWN_STRUCTURE:
			return "Target one of your structures"
	return "No target"


static func target_vision_text(vision: int) -> String:
	match vision:
		DefEnums.TargetVision.CURRENT:
			return "Needs current vision"
		DefEnums.TargetVision.EXPLORED:
			return "Explored terrain"
	return "Any location"


## Glyph id (UiGlyphs) for a unit by its tags and class.
static func unit_glyph(u: DefUnit) -> int:
	var t: int = u.tags
	if t & DefEnums.UT_INFANTRY != 0:
		return UiGlyphs.Glyph.ENGINEER if t & DefEnums.UT_CONSTRUCTION != 0 or t & DefEnums.UT_SERVICE != 0 and u.has_ability(DefEnums.AbilityKind.CAPTURE) else UiGlyphs.Glyph.INFANTRY
	if t & DefEnums.UT_COLLECTOR != 0:
		return UiGlyphs.Glyph.COLLECTOR
	if t & DefEnums.UT_SUBMARINE != 0:
		return UiGlyphs.Glyph.SUBMARINE
	if t & DefEnums.UT_CARRIER != 0:
		return UiGlyphs.Glyph.CARRIER
	if t & DefEnums.UT_SHIP != 0:
		return UiGlyphs.Glyph.NAVAL
	if t & DefEnums.UT_AIRCRAFT != 0:
		return UiGlyphs.Glyph.DRONE if t & DefEnums.UT_UNMANNED != 0 else UiGlyphs.Glyph.AIRCRAFT
	if t & DefEnums.UT_ARTILLERY != 0:
		return UiGlyphs.Glyph.ARTILLERY
	if t & DefEnums.UT_SIEGE != 0:
		return UiGlyphs.Glyph.SIEGE
	if t & DefEnums.UT_ANTI_AIR != 0:
		return UiGlyphs.Glyph.ANTI_AIR
	if t & DefEnums.UT_SCOUT != 0:
		return UiGlyphs.Glyph.SCOUT
	if t & DefEnums.UT_TRANSPORT != 0:
		return UiGlyphs.Glyph.TRANSPORT
	if t & DefEnums.UT_TANK != 0:
		return UiGlyphs.Glyph.TANK
	if t & DefEnums.UT_UNMANNED != 0:
		return UiGlyphs.Glyph.DRONE
	if t & DefEnums.UT_CONSTRUCTION != 0:
		return UiGlyphs.Glyph.MCV
	if t & DefEnums.UT_REPAIR != 0:
		return UiGlyphs.Glyph.REPAIR
	return UiGlyphs.Glyph.VEHICLES


## Glyph for a structure card.
static func structure_glyph(s: DefStructure) -> int:
	if s.tags & DefEnums.ST_SUPERWEAPON != 0:
		return UiGlyphs.Glyph.MISSILE
	if s.tags & DefEnums.ST_DEFENSE != 0:
		return UiGlyphs.Glyph.DEFENSE
	if s.tags & DefEnums.ST_RELAY != 0:
		return UiGlyphs.Glyph.RADAR
	if s.power > 0:
		return UiGlyphs.Glyph.BOLT
	return UiGlyphs.Glyph.STRUCTURES


# ---------------------------------------------------------------------------------------------------------------- formatting

## "+10%" / "-15%" with one decimal at most.
static func delta_text(bp: int) -> String:
	return DefFormat.delta_percent_text(bp)


## Relative change of `resolved` against `base` in basis points, half-up; 0 when the base is 0.
static func delta_bp(base: int, resolved: int) -> int:
	if base == 0:
		return 0
	var num: int = (resolved - base) * 10000
	var half: int = absi(base) / 2
	return (num + half) / base if num >= 0 else -((-num + half) / base)


## Seconds text of a tick count ("27.5 s").
static func secs(ticks: int) -> String:
	return DefFormat.seconds_text(ticks) + " s"


static func cells(u: int) -> String:
	return DefFormat.cells_text(u)


## Damage per second x 10 of a weapon slot: damage x hits per volley / reload.
static func dps_x10(damage: int, hits: int, reload_mt: int) -> int:
	if reload_mt <= 0:
		return 0
	var num: int = damage * maxi(hits, 1) * SimConfig.TPS * 1000 * 10
	return (2 * num + reload_mt) / (2 * reload_mt)


static func dps_text(x10: int) -> String:
	return DefFormat.tenths_text(x10)


# ---------------------------------------------------------------------------------------------------------------- abilities

## One plain sentence for an ability instance. `data` resolves structure / unit names (optional).
static func ability_text(a: DefAbility, data: GameData = null) -> String:
	var p: Dictionary = a.params
	match a.kind:
		DefEnums.AbilityKind.DETECTOR:
			return "Detects camouflaged and submerged units within %s cells." % cells(_i(p, "radius_u", data.economy.detector_default_radius_u if data != null else 5120))
		DefEnums.AbilityKind.CAMOUFLAGE:
			var s: String = "Becomes invisible to enemies without detection after %s" % secs(_i(p, "delay_t"))
			if _b(p, "needs_stationary"):
				s += " standing still"
			if _b(p, "needs_no_attack"):
				s += " without attacking"
			s += "."
			if _b(p, "reveal_on_fire") or _b(p, "reveal_on_damage"):
				s += " Revealed when it fires or takes damage."
			return s
		DefEnums.AbilityKind.DEPLOY:
			var d: String = "Deploys in %s (packs up in %s)" % [secs(_i(p, "deploy_t")), secs(_i(p, "pack_t"))]
			if _b(p, "immobile"):
				d += "; cannot move while deployed"
			var bonus: PackedStringArray = PackedStringArray()
			if _i(p, "range_bonus_bp") != 0:
				bonus.append("%s range" % delta_text(_i(p, "range_bonus_bp")))
			if _i(p, "damage_bonus_bp") != 0:
				bonus.append("%s damage" % delta_text(_i(p, "damage_bonus_bp")))
			return d + (". Deployed: " + ", ".join(bonus) + "." if not bonus.is_empty() else ".")
		DefEnums.AbilityKind.MODE_SWITCH:
			var modes: Array = p.get("modes", []) as Array
			var names: PackedStringArray = PackedStringArray()
			for m: Variant in modes:
				names.append(humanize(str((m as Dictionary).get("id", ""))))
			return "Switches weapon mode (%s) in %s." % [", ".join(names), secs(_i(p, "switch_t"))]
		DefEnums.AbilityKind.TRANSPORT:
			var cargo: PackedStringArray = PackedStringArray()
			if _i(p, "capacity_squads_n") > 0:
				cargo.append("%d infantry squad%s" % [_i(p, "capacity_squads_n"), "" if _i(p, "capacity_squads_n") == 1 else "s"])
			if _i(p, "capacity_vehicles_n") > 0:
				cargo.append("%d vehicle%s" % [_i(p, "capacity_vehicles_n"), "" if _i(p, "capacity_vehicles_n") == 1 else "s"])
			var t: String = "Carries " + (" and ".join(cargo) if not cargo.is_empty() else "passengers") + "."
			if _b(p, "passengers_fire"):
				t += " Passengers can fire from inside."
			if _i(p, "passenger_damage_reduction_bp") > 0:
				t += " Passengers take %s%% less damage." % DefFormat.percent_text(_i(p, "passenger_damage_reduction_bp"))
			return t
		DefEnums.AbilityKind.HEAL:
			return "Heals friendly infantry within %s cells at %s%% of maximum health per second." % [cells(_i(p, "radius_u")), DefFormat.percent_text(_i(p, "rate_bps"))]
		DefEnums.AbilityKind.REPAIR:
			var r: String = "Repairs %s%% of maximum health per second" % DefFormat.percent_text(_i(p, "rate_bps"))
			r += " (free)." if str(p.get("cost", "")) == "free" else " (costs credits)."
			if _i(p, "radius_u") > 0:
				r = "Repairs friendly units within %s cells at %s%% of maximum health per second%s" % [cells(_i(p, "radius_u")),
					DefFormat.percent_text(_i(p, "rate_bps")), " at no cost." if str(p.get("cost", "")) == "free" else ", paid for with credits."]
			return r
		DefEnums.AbilityKind.COMMAND_FIELD:
			return "Command field: friendly units within %s cells deal %s damage." % [cells(_i(p, "radius_u")), delta_text(_i(p, "damage_bonus_bp"))]
		DefEnums.AbilityKind.INTERCEPTOR:
			return "Shoots down %d incoming shell%s or missile%s within %s cells; recharges in %s." % [_i(p, "charges_n", 1),
				"" if _i(p, "charges_n", 1) == 1 else "s", "" if _i(p, "charges_n", 1) == 1 else "s", cells(_i(p, "range_u")), secs(_i(p, "cooldown_t"))]
		DefEnums.AbilityKind.SUPPRESSION_SUPPORT:
			return "Friendly infantry within %s cells recover from suppression %s%% faster." % [cells(_i(p, "radius_u")), DefFormat.percent_text(_i(p, "recovery_bonus_bp"))]
		DefEnums.AbilityKind.DECOY_SPAWN:
			return "Launches a decoy (up to %d at a time); cooldown %s." % [_i(p, "max_active_n", 1), secs(_i(p, "cooldown_t"))]
		DefEnums.AbilityKind.SENSOR_PUCK:
			return "Places a sensor puck that reveals its surroundings; cooldown %s." % secs(_i(p, "cooldown_t"))
		DefEnums.AbilityKind.SMOKE_LAUNCHER:
			return "Fires a smoke screen (%s-cell radius, %s); cooldown %s." % [cells(_i(p, "radius_u")), secs(_i(p, "duration_t")), secs(_i(p, "cooldown_t"))]
		DefEnums.AbilityKind.EW_JAMMER:
			return "Enemy units within %s cells lose %s%% of their sight." % [cells(_i(p, "radius_u")), DefFormat.percent_text(_i(p, "sight_penalty_bp"))]
		DefEnums.AbilityKind.DISEMBARK_BUFF:
			return "Units that just disembarked deal %s damage for %s." % [delta_text(_i(p, "damage_bonus_bp")), secs(_i(p, "duration_t"))]
		DefEnums.AbilityKind.PORTABLE_COVER:
			return "Builds portable cover in %s that lasts %s and reduces bullet damage by %s%%." % [secs(_i(p, "build_t")), secs(_i(p, "lifetime_t")), DefFormat.percent_text(_i(p, "resist_bp"))]
		DefEnums.AbilityKind.SALVAGE:
			return "Salvages wrecks in %s for %s%% of their value." % [secs(_i(p, "action_t")), DefFormat.percent_text(_i(p, "payout_bp"))]
		DefEnums.AbilityKind.FRONTAL_SHIELD:
			return "Frontal shield: %s%% less damage from the front." % DefFormat.percent_text(_i(p, "reduction_bp"))
		DefEnums.AbilityKind.CARRIER:
			var wings: Array = p.get("wings", []) as Array
			var n: int = 0
			for w: Variant in wings:
				n += int((w as Dictionary).get("wing_size_n", 0))
			return "Launches %d strike drones up to %s cells away; replaces losses in %s." % [n, cells(_i(p, "launch_range_u")), secs(_i(p, "replace_t"))]
		DefEnums.AbilityKind.SENSOR_MAST:
			return "Deploys in %s to reveal %s cells around it; cannot move while deployed." % [secs(_i(p, "deploy_t")), cells(_i(p, "reveal_radius_u"))]
		DefEnums.AbilityKind.CAPTURE:
			return "Captures neutral tech structures in %s." % secs(_i(p, "capture_t"))
		DefEnums.AbilityKind.HARVEST:
			return "Harvests deposits and carries up to %s credits." % DefFormat.credits_text(_i(p, "capacity_cr"))
		DefEnums.AbilityKind.DEPLOY_STRUCTURE:
			var sname: String = "a structure"
			if data != null and _i(p, "structure_idx", -1) >= 0 and _i(p, "structure_idx", -1) < data.structures.size():
				sname = data.structures[_i(p, "structure_idx")].ui_name
			return "Deploys into %s in %s." % [sname, secs(_i(p, "deploy_t"))]
		DefEnums.AbilityKind.SUBMERGE:
			return "Can submerge to hide from most enemies; needs %s to resurface." % secs(_i(p, "surface_t"))
		DefEnums.AbilityKind.SORTIE:
			return "Flies sorties and returns to a service pad to rearm."
		DefEnums.AbilityKind.SPOTTER:
			return "Spots for friendly artillery within %s cells." % cells(_i(p, "radius_u"))
		DefEnums.AbilityKind.DIRECTIONAL_ARMOR:
			return "Directional armor: %s%% less damage from the front, %s%% more from behind." % [DefFormat.percent_text(_i(p, "front_reduction_bp")), DefFormat.percent_text(_i(p, "rear_increase_bp"))]
		DefEnums.AbilityKind.RELAY_FIELD:
			var rel: String = "Relay field: friendly units within %s cells deal %s damage" % [cells(_i(p, "radius_u")), delta_text(_i(p, "damage_bonus_bp"))]
			return rel + (" while the relay is powered." if _b(p, "powered_required") else ".")
		DefEnums.AbilityKind.SERVICE_PADS:
			return "%d landing pad%s that rearm and repair aircraft." % [_i(p, "pads_n", 1), "" if _i(p, "pads_n", 1) == 1 else "s"]
		DefEnums.AbilityKind.REFINERY:
			return "Accepts credits from collectors and comes with a free collector."
		DefEnums.AbilityKind.AURA_REGEN:
			return "Heals friendly units within %s cells at %s%% of maximum health per second." % [cells(_i(p, "radius_cells", 0) * 1024), DefFormat.percent_text(_i(p, "rate_pct_per_s", 0) * 100)]
		DefEnums.AbilityKind.REGEN:
			return "Slowly regenerates health while out of combat."
		DefEnums.AbilityKind.DEFENSE_POWER_RESERVE:
			return "Keeps defenses firing for a while after power is lost."
		DefEnums.AbilityKind.SUMMON_ORBIT:
			return "Orbits its owner."
	return ability_name(a.kind) + "."


static func _i(p: Dictionary, key: String, def: int = 0) -> int:
	var v: Variant = p.get(key, def)
	return int(v) if v is int or v is float else def


static func _b(p: Dictionary, key: String) -> bool:
	return bool(p.get(key, false))
