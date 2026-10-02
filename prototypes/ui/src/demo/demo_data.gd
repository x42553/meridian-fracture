class_name DemoData
extends RefCounted
## Loads the bible slice (data/factions_slice.json, generated from Input/) and turns a roster into
## build-card view-models. Costs the bible leaves null get DEMO numbers (tier x category), never balance.

const TABS: Array[String] = ["structures", "infantry", "vehicles", "aircraft", "naval", "defense", "powers"]
const TAB_TITLES: Dictionary = {"structures": "STRUCTURES", "infantry": "INFANTRY", "vehicles": "VEHICLES", "aircraft": "AIRCRAFT", "naval": "NAVAL", "defense": "DEFENSE", "powers": "SUPPORT POWERS"}
const TAB_GLYPHS: Dictionary = {
	"structures": UiGlyphs.Glyph.STRUCTURES, "infantry": UiGlyphs.Glyph.INFANTRY, "vehicles": UiGlyphs.Glyph.VEHICLES,
	"aircraft": UiGlyphs.Glyph.AIRCRAFT, "naval": UiGlyphs.Glyph.NAVAL, "defense": UiGlyphs.Glyph.DEFENSE, "powers": UiGlyphs.Glyph.POWERS,
}
const _HOTKEYS := "QWERASDFZXCV"

static var _slice: Dictionary = {}

static func slice() -> Dictionary:
	if _slice.is_empty():
		var f := FileAccess.open("res://data/factions_slice.json", FileAccess.READ)
		_slice = JSON.parse_string(f.get_as_text())
	return _slice

static func faction(code: String) -> Dictionary:
	for f in slice()["factions"]:
		if f["code"] == code:
			return f
	return {}

static func roster(code: String, index: int) -> Dictionary:
	return faction(code)["rosters"][index]

static func category_of(producer: String) -> String:
	if producer.ends_with("barracks"):
		return "infantry"
	if producer.ends_with("airfield"):
		return "aircraft"
	if producer.ends_with("dock"):
		return "naval"
	return "vehicles"

static func _demo_cost(tier: int, category: String) -> int:
	var base: Dictionary = {"infantry": 300, "vehicles": 900, "aircraft": 1400, "naval": 800}
	return int(float(base.get(category, 900)) * (1.0 + float(tier - 1) * 0.85))

## Card view-models grouped by tab. Icons are attached later by the icon baker (see model_kind).
static func build_items(code: String, roster_index: int) -> Dictionary:
	var d: Dictionary = slice()
	var r: Dictionary = roster(code, roster_index)
	var out: Dictionary = {}
	for t in TABS:
		out[t] = [] as Array[UiBuildItem]
	var structs: Dictionary = d["structures"]
	for sid in r["structures"]:
		var s: Dictionary = structs[sid]
		var nm: String = s["name"]
		var it := UiBuildItem.new()
		it.id = sid
		it.display_name = nm
		it.cost = int(s["cost"]) if s["cost"] != null else 0
		it.build_seconds = float(s["time"]) if s["time"] != null else 30.0
		it.power_delta = int(s["power"]) if s["power"] != null else 0
		var req: Array = s["requires"]
		it.requires = ", ".join(req.map(func(x: String) -> String: return String(structs[x]["name"]) if structs.has(x) else x))
		var is_defense: bool = nm in ["Watchtower", "Anti-tank turret", "AA battery"] or (sid.begins_with("structure.%s." % code) and it.cost <= 1800 and it.cost > 0)
		if sid == "structure.shared.headquarters":
			continue
		var cat: String = "defense" if is_defense else "structures"
		it.model_kind = DemoModels.kind_for(nm, cat)
		it.tier = 3 if req.size() >= 2 else (2 if req.size() == 1 and req[0] in ["structure.shared.radar", "structure.shared.factory"] else 1)
		it.glyph = UiGlyphs.Glyph.DEFENSE if is_defense else UiGlyphs.Glyph.STRUCTURES
		(out[cat] as Array).append(it)
	var units: Dictionary = d["units"]
	var uids: Array = []
	uids.append_array(r["units"])
	uids.append_array(r["service"])
	for uid in uids:
		var u: Dictionary = units[uid]
		var prod: String = String(u["producer"])
		var cat2: String = "vehicles"
		if prod.ends_with("barracks"):
			cat2 = "infantry"
		elif prod.ends_with("airfield"):
			cat2 = "aircraft"
		elif prod.ends_with("dock"):
			cat2 = "naval"
		var it2 := UiBuildItem.new()
		it2.id = uid
		it2.display_name = u["name"]
		it2.tier = int(u["tier"]) if u["tier"] != null else 1
		it2.cost = int(u["cost"]) if u["cost"] != null else _demo_cost(it2.tier, cat2)
		it2.build_seconds = clampf(float(it2.cost) / 32.0, 8.0, 60.0)
		it2.model_kind = DemoModels.kind_for(it2.display_name, cat2)
		it2.description = String(u["role"])
		it2.requires = ("Requires " + ("Radar" if it2.tier == 2 else "Laboratory")) if it2.tier >= 2 else ""
		it2.glyph = TAB_GLYPHS[cat2]
		(out[cat2] as Array).append(it2)
	for pid in r["powers"]:
		var p: Dictionary = d["powers"][pid]
		var it3 := UiBuildItem.new()
		it3.id = pid
		it3.display_name = p["name"]
		it3.cost = int(p["cost"]) if p["cost"] != null else 0
		it3.build_seconds = float(p["cooldown"]) if p["cooldown"] != null else 90.0
		it3.description = p["text"]
		it3.model_kind = "power"
		it3.glyph = UiGlyphs.Glyph.POWERS
		(out["powers"] as Array).append(it3)
	var sw: Dictionary = d["superweapons"][r["superweapon"]]
	var it4 := UiBuildItem.new()
	it4.id = r["superweapon"]
	it4.display_name = sw["name"]
	it4.build_seconds = float(sw["recharge"])
	it4.model_kind = "power"
	it4.glyph = UiGlyphs.Glyph.MISSILE
	it4.description = "Superweapon. Recharge %d s, warning %d s." % [sw["recharge"], sw["warning"]]
	(out["powers"] as Array).append(it4)
	for t in TABS:
		var arr: Array = out[t]
		for i in arr.size():
			var it5: UiBuildItem = arr[i]
			it5.hotkey = _HOTKEYS[i] if i < _HOTKEYS.length() else ""
	return out

## Demo states so a static screenshot shows every card state at once.
static func apply_demo_states(items: Dictionary) -> void:
	var veh: Array = items["vehicles"]
	var pattern: Array = [
		[UiBuildItem.State.AVAILABLE, 0.0, 0], [UiBuildItem.State.BUILDING, 0.62, 3], [UiBuildItem.State.AVAILABLE, 0.0, 0],
		[UiBuildItem.State.UNAFFORDABLE, 0.0, 0], [UiBuildItem.State.LOCKED, 0.0, 0], [UiBuildItem.State.READY, 1.0, 1],
		[UiBuildItem.State.ON_HOLD, 0.34, 2], [UiBuildItem.State.QUEUED, 0.0, 2], [UiBuildItem.State.AVAILABLE, 0.0, 0],
	]
	for i in veh.size():
		var p: Array = pattern[i % pattern.size()]
		var it: UiBuildItem = veh[i]
		it.state = p[0]
		it.progress = p[1]
		it.queued = p[2]
	for t in ["structures", "infantry", "aircraft", "naval", "defense"]:
		var arr: Array = items[t]
		for i in arr.size():
			var it2: UiBuildItem = arr[i]
			if i == 1 and t == "structures":
				it2.state = UiBuildItem.State.BUILDING
				it2.progress = 0.41
			elif it2.tier >= 3:
				it2.state = UiBuildItem.State.LOCKED
	var powers: Array = items["powers"]
	for i in powers.size():
		var it3: UiBuildItem = powers[i]
		it3.state = UiBuildItem.State.COOLDOWN if i != 0 else UiBuildItem.State.AVAILABLE
		it3.progress = [1.0, 0.35, 0.72, 0.18][i % 4]
