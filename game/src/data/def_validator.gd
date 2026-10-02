class_name DefValidator
extends RefCounted
## In-engine validation facade (data_balance 3.8 / 5.12). SKELETON (DATA-01..03 scope): the manifest / schema-header /
## bible-count rules of P1 (V-SCH-01, V-SCH-02) and `check_frozen`; the V-REF/CMP/CNF/RNG/MOD/ROS/TIER/ROLE/EFF/ABL
## rule sets arrive with DATA-08.

enum { LEVEL_FAST = 0, LEVEL_FULL = 1 }

## Files a complete manifest lists (data_balance 7.2); a compiler adds its own.
const CORE_FILES: PackedStringArray = [
	"ability_kinds.json", "faction_traits.json", "global.json", "neutral_structures.json", "power_actions.json",
	"research_effects.json", "structures.json", "units_ae.json", "units_def.json", "units_han.json", "units_napc.json",
	"units_nec.json", "units_olm.json", "units_pd.json", "units_sap.json", "units_shared.json", "zone_templates.json",
]


## P1: rules on the raw inputs. FAST and FULL run the same skeleton rules today.
static func validate_sources(src: DefSources, rep: DefLoadReport, _level: int, extra_files: PackedStringArray = PackedStringArray()) -> void:
	rep.errors.append_array(src.read_errors)
	if src.bible.is_empty():
		rep.error("V-SCH-01", src.bible_path, "the bible could not be read")
		return
	if src.manifest_files.is_empty():
		rep.error("V-SCH-01", "manifest.json", "manifest lists no files")
	if src.manifest_format != 1:
		rep.error("V-SCH-01", "manifest.json", "format must be 1, found %d" % src.manifest_format)
	var sorted_files: PackedStringArray = src.manifest_files.duplicate()
	sorted_files.sort()
	if sorted_files != src.manifest_files:
		rep.error("V-SCH-01", "manifest.json", "files must be sorted ascending")
	for i: int in range(1, sorted_files.size()):
		if sorted_files[i] == sorted_files[i - 1]:
			rep.error("V-SCH-01", "manifest.json", "duplicate entry '%s'" % sorted_files[i])
	for f: String in extra_files:
		if not src.manifest_files.has(f):
			rep.error("V-SCH-01", "manifest.json", "file '%s' is owned by a registered compiler but not listed" % f)
	for f: String in CORE_FILES:
		if not src.manifest_files.has(f):
			rep.error("V-SCH-01", "manifest.json", "expected file '%s' is not listed" % f)
	for f: String in src.manifest_files:
		if not src.balance.has(f):
			if not " ".join(src.read_errors).contains(f):
				rep.error("V-SCH-01", f, "file is listed in the manifest but was not loaded")
			continue
		var d: Dictionary = src.balance[f]
		if f == "global.json":
			if int(d.get("version", 0)) != 1:
				rep.error("V-SCH-01", src.where(f, "version"), "global.json version must be 1")
		elif f != "manifest.json":
			var schema: String = str(d.get("schema", ""))
			if not schema.begins_with("meridian.balance.") or not schema.ends_with("/1"):
				rep.error("V-SCH-01", f, "missing or unexpected schema '%s'" % schema)
	var expected: Dictionary = src.bible.get("metadata", {}).get("expected_counts", {})
	_count(src, rep, expected, "factions", "factions")
	_count(src, rep, expected, "rosters", "rosters")
	_count(src, rep, expected, "support_powers", "support_powers")
	_count(src, rep, expected, "research_upgrades", "research")
	_count(src, rep, expected, "superweapons", "superweapons")
	var nunits: int = int(expected.get("baseline_combat_units", 0)) + int(expected.get("unique_subfaction_units", 0)) + int(expected.get("service_units", 0))
	var have: int = (src.bible.get("units", {}) as Dictionary).size()
	if nunits > 0 and have != nunits:
		rep.error("V-SCH-02", src.bible_path, "bible has %d units, metadata.expected_counts says %d" % [have, nunits])


static func _count(src: DefSources, rep: DefLoadReport, expected: Dictionary, exp_key: String, section: String) -> void:
	if not expected.has(exp_key):
		return
	var have: int = (src.bible.get(section, {}) as Dictionary).size()
	var want: int = int(expected[exp_key])
	if have != want:
		rep.error("V-SCH-02", src.bible_path, "bible section '%s' has %d entries, expected %d" % [section, have, want])


## Table-level rules on the built GameData. TODO(data): DATA-08.
static func validate_data(_data: GameData, _rep: DefLoadReport, _level: int) -> void:
	pass


## Debug: re-hashes the tables and compares to the stored data_hash (nothing mutated a def after build).
static func check_frozen(data: GameData) -> bool:
	return GameData.compute_table_hashes(data) == data.table_hashes
