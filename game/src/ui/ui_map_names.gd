class_name UiMapNames
extends RefCounted
## Cosmetic map names (ui.md 5.14.5): a deterministic syllable table keyed by (family, seed). Never transmitted, never hashed.

const FIRST: PackedStringArray = ["Ridge", "Dust", "Iron", "Salt", "Cinder", "Amber", "Copper", "Glass", "Ash", "Harbor", "Sable", "Granite", "Storm",
	"Silver", "Ember", "Wolf", "Meridian", "Basalt", "Kestrel", "Marrow", "Vesper", "Anvil", "Tide", "Fallow"]
const OPEN: PackedStringArray = ["Crossing", "Basin", "Flats", "Reach", "Divide", "Steppe", "Plain", "Expanse", "Ford", "Hollow"]
const URBAN: PackedStringArray = ["Junction", "Quarter", "Terminal", "District", "Arcade", "Yards", "Precinct", "Underpass", "Exchange", "Rows"]
const COAST: PackedStringArray = ["Straits", "Delta", "Narrows", "Shoals", "Bay", "Estuary", "Coast", "Sound", "Lagoon", "Inlet"]


static func name_for(family: int, seed_value: int) -> String:
	var h: int = (seed_value * 2654435761 + family * 40503) & 0xFFFFFFFF
	var tails: PackedStringArray = OPEN
	if family == 1:
		tails = URBAN
	elif family == 2:
		tails = COAST
	return "%s %s" % [FIRST[h % FIRST.size()], tails[(h >> 8) % tails.size()]]


static func family_name(family: int) -> String:
	match family:
		1:
			return "Urban routes"
		2:
			return "Coast & river"
	return "Open land"
