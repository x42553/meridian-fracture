class_name DefSources
extends RefCounted
## Parsed-but-unconverted loader inputs (data_balance 3.2 / 5.1 P0). Built from disk or from test dictionaries.
## No DirAccess listing: `balance/manifest.json` is the file list (platform-independent order, DR-6).

var bible: Dictionary = {}  ## parsed meridian_factions.json
var balance: Dictionary = {}  ## "global.json" -> Dictionary, the manifest files that could be read
var manifest_files: PackedStringArray = PackedStringArray()  ## from manifest.json (validated sorted + unique)
var manifest_format: int = 0
var mission_files: PackedStringArray = PackedStringArray()  ## manifest "missions": file names under data/missions/ (sorted by the validator)
var missions: Dictionary = {}  ## "demo_ambush.json" -> parsed Dictionary (meridian.mission/1), only the files that could be read
var raw_texts: Dictionary = {}  ## path -> String, kept only for file:line messages (may be empty in tests)
var read_errors: PackedStringArray = PackedStringArray()  ## "RULE where: msg" lines produced while reading
var bible_path: String = ""
var balance_dir: String = ""


## Reads the bible and every manifest file. Missing or unparsable files are recorded in `read_errors` (never a crash).
static func from_disk(bible_file: String, balance_root: String) -> DefSources:
	var s: DefSources = DefSources.new()
	s.bible_path = bible_file
	s.balance_dir = balance_root
	var bible_doc: Variant = s._read_json(bible_file, bible_file)
	if bible_doc is Dictionary:
		s.bible = bible_doc
	var man_path: String = balance_root.path_join("manifest.json")
	var man: Variant = s._read_json(man_path, "manifest.json")
	if man is Dictionary:
		var md: Dictionary = man
		s.manifest_format = int(md.get("format", 0))
		var files: Variant = md.get("files", [])
		if files is Array:
			for f: Variant in files:
				s.manifest_files.append(str(f))
		var mfiles: Variant = md.get("missions", [])
		if mfiles is Array:
			for f: Variant in mfiles:
				s.mission_files.append(str(f))
	for f: String in s.manifest_files:
		if f == "manifest.json":
			continue
		var doc: Variant = s._read_json(balance_root.path_join(f), f)
		if doc is Dictionary:
			s.balance[f] = doc
	var mission_dir: String = balance_root.get_base_dir().path_join("missions")
	for f: String in s.mission_files:
		var mdoc: Variant = s._read_json(mission_dir.path_join(f), "missions/" + f)
		if mdoc is Dictionary:
			s.missions[f] = mdoc
	return s


## From parsed dictionaries (unit tests). `balance` maps file name -> parsed Dictionary; the manifest is its sorted keys.
static func from_dicts(bible_dict: Dictionary, balance_dict: Dictionary) -> DefSources:
	var s: DefSources = DefSources.new()
	s.bible = bible_dict
	s.balance = balance_dict
	s.manifest_format = 1
	var keys: PackedStringArray = PackedStringArray()
	for k: Variant in balance_dict.keys():
		keys.append(str(k))
	keys.sort()
	s.manifest_files = keys
	return s


func deep_copy() -> DefSources:
	var c: DefSources = DefSources.new()
	c.bible = bible.duplicate(true)
	c.balance = balance.duplicate(true)
	c.manifest_files = manifest_files.duplicate()
	c.manifest_format = manifest_format
	c.mission_files = mission_files.duplicate()
	c.missions = missions.duplicate(true)
	c.raw_texts = raw_texts.duplicate()
	c.read_errors = read_errors.duplicate()
	c.bible_path = bible_path
	c.balance_dir = balance_dir
	return c


## "path:line" of the first occurrence of `"needle"` in the raw text of `path` (line 0 / bare path when unknown).
func where(path: String, needle: String) -> String:
	var text: String = raw_texts.get(path, "")
	if text == "" or needle == "":
		return path
	var at: int = text.find("\"" + needle + "\"")
	if at < 0:
		return path
	return "%s:%d" % [path, text.substr(0, at).count("\n") + 1]


func _read_json(full_path: String, label: String) -> Variant:
	if not FileAccess.file_exists(full_path):
		read_errors.append("V-SCH-01 %s: file is listed but does not exist" % label)
		return null
	var text: String = FileAccess.get_file_as_string(full_path)
	if not text.is_empty() and text.unicode_at(0) == 0xFEFF:  # BOM (an invisible literal is lost by the exported script tokenizer)
		text = text.substr(1)
	raw_texts[label] = text
	var p: JSON = JSON.new()
	var err: int = p.parse(text)
	if err != OK:
		read_errors.append("V-SCH-01 %s:%d: %s" % [label, p.get_error_line(), p.get_error_message()])
		return null
	if not (p.data is Dictionary):
		read_errors.append("V-SCH-01 %s: top level must be a JSON object" % label)
		return null
	return p.data
