extends RefCounted
## Fixture DefMoveTable (the real class, hand-filled) for the map tests, independent of global.json: the TAXONOMY 8 speed table in bp,
## [move_class * 8 + terrain_kind], kinds ordered road/open/rough/forest/marsh/shallow/deep/cliff.
## Never registered under a class_name; map tests preload it.

const ROWS: Array = [
	[110, 100, 80, 70, 60, 70, 0, 0],  # foot
	[130, 100, 55, 0, 35, 50, 0, 0],  # wheeled
	[105, 100, 80, 55, 55, 65, 0, 0],  # tracked
	[105, 100, 75, 50, 80, 90, 70, 0],  # amphibious
	[0, 0, 0, 0, 0, 80, 100, 0],  # naval
	[0, 0, 0, 0, 0, 0, 100, 0],  # submerged
	[100, 100, 100, 100, 100, 100, 100, 100],  # air_fixed
	[100, 100, 100, 100, 100, 100, 100, 100],  # air_hover
	[0, 0, 0, 0, 0, 0, 0, 0],  # static
]


## A real DefMoveTable holding the TAXONOMY table (layers left empty: the map domain reads only speed_bp).
static func make() -> DefMoveTable:
	var m: DefMoveTable = DefMoveTable.new()
	for row: Array in ROWS:
		for v: int in row:
			m.speed_bp.append(v * 100)
	return m


## The terrain.json of the game as a Dictionary (the loader input).
static func terrain_dict() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/balance/terrain.json")) as Dictionary
