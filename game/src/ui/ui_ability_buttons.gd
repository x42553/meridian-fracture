class_name UiAbilityButtons
extends RefCounted
## The button list of the ability bar for the selection's active subgroup (split out of `UiHudPresenter`): fixed utility buttons
## (Hold, Patrol, Follow, Return, Unload) and at most four ability slots, each with the hotkey it shows (I O K L). The presenter
## also reads it to resolve the ability hotkeys, so the keys always match the buttons on screen.


## The platform label of an action's first binding ("" = unbound): the buttons show the keys that really work (Follow is Ctrl+F, not F).
static func key(action: String) -> String:
	return UiKeymap.instance().label(StringName(action)).replace("Ctrl+", "^")  # a chord must fit the small badge: "^F" for Ctrl+F


## Utility row + ability slots for the active subgroup (5.11.5 / 5.11.6), five buttons at most.
static func build(sel: UiSelection, info: UiSelectionInfo, roster: DefRoster, sim: UiSimPort, row: UiEntityRow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if info == null or sel.mode != UiSelection.Mode.UNITS:
		return out
	var c: int = info.caps_any
	var mobile: bool = (c & UiUnitCaps.CAP_MOBILE) != 0
	var armed: bool = (c & UiUnitCaps.CAP_ARMED) != 0
	var abil: Array[Dictionary] = []
	var u: DefUnit = roster.unit(sel.active_def)
	if u != null:
		for i: int in u.abilities.size():
			var a: DefAbility = u.abilities[i]
			var glyph: int = -1
			var title: String = ""
			match a.kind:
				DefEnums.AbilityKind.MODE_SWITCH:
					glyph = UiGlyphs.Glyph.MODE
					title = "Switch mode"
				DefEnums.AbilityKind.PORTABLE_COVER:
					glyph = UiGlyphs.Glyph.COVER
					title = "Portable cover"
				DefEnums.AbilityKind.DECOY_SPAWN:
					glyph = UiGlyphs.Glyph.CAMO
					title = "Deploy decoy"
				DefEnums.AbilityKind.SENSOR_PUCK:
					glyph = UiGlyphs.Glyph.RADAR
					title = "Sensor puck"
				DefEnums.AbilityKind.SMOKE_LAUNCHER:
					glyph = UiGlyphs.Glyph.SMOKE
					title = "Smoke screen"
			if glyph >= 0 and abil.size() < 4:
				abil.append({"id": &"ability", "glyph": glyph, "slot": i, "enabled": true, "hotkey": key("cmd_ability_%d" % (abil.size() + 1)), "title": title, "text": "Right-click toggles auto-cast."})
	var util: Array[Dictionary] = []
	if mobile and armed:
		util.append({"id": &"hold", "glyph": UiGlyphs.Glyph.HOLD, "slot": -1, "enabled": true, "hotkey": key("cmd_hold"), "title": "Hold position", "text": "Stay put and fire at anything in range."})
	if mobile:
		util.append({"id": &"patrol", "glyph": UiGlyphs.Glyph.PATROL, "slot": -1, "enabled": true, "hotkey": key("cmd_patrol"), "title": "Patrol", "text": "Patrol between the current position and a point."})
		util.append({"id": &"follow", "glyph": UiGlyphs.Glyph.FOLLOW, "slot": -1, "enabled": true, "hotkey": key("cmd_follow"), "title": "Follow", "text": "Follow an own or allied unit."})
	if (c & (UiUnitCaps.CAP_AIR | UiUnitCaps.CAP_CARRIER_DRONE | UiUnitCaps.CAP_COLLECTOR)) != 0:
		util.append({"id": &"return", "glyph": UiGlyphs.Glyph.RETURN, "slot": -1, "enabled": true, "hotkey": key("cmd_return"), "title": "Return", "text": "Return to base or to the refinery."})
	if (c & UiUnitCaps.CAP_TRANSPORT) != 0 and sim.read(sel.primary, row) and row.cargo > 0:
		util.append({"id": &"unload", "glyph": UiGlyphs.Glyph.UNLOAD, "slot": -1, "enabled": true, "hotkey": key("cmd_unload"), "title": "Unload", "text": "Unload the passengers."})
	var room: int = UiAbilityBar.MAX_BUTTONS - abil.size()
	for i2: int in mini(room, util.size()):
		out.append(util[i2])
	out.append_array(abil)
	return out
