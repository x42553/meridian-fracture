class_name ViewRecipeBook
extends RefCounted
## Loads and validates the recipe data (render spec 7.1): `archetypes/*.json`, `styles.json` + `styles/*.json`,
## `footprints.json`, `<recipe id>.json`. Lookup of recipes, archetypes and fully merged styles (`extends` chains resolved once
## at link time, so every getter is read-only and safe to call from worker threads).
##
## Files that are not recipes (index, styles, moods, fx, quality, assignments, footprints and the art-direction `style.json`)
## are skipped by name; every other `*.json` in the directory must carry schema `meridian.recipe/1`.
##
## STYLE FILES AND MERGE PRECEDENCE. Styles live in `styles.json` (the base / shared file: `neutral` and any style nobody has
## moved yet) and in one file per faction, `styles/<faction>.json` (`napc.json` holds `napc`, `napc.usa`, ...; schema
## `meridian.styles/1`, same `{"styles": {id: style}}` body), so eight authors can work concurrently without touching a shared
## file. Loading order is `styles.json`, then `styles/*.json` sorted by file name (byte order). Every source is merged into the
## raw style table PER STYLE ID with the same deep merge as `extends`: objects merge key by key, arrays / scalars / slots are
## replaced by the LATER source; so a faction file wins over `styles.json`, and a faction file may be a partial override of a
## style that `styles.json` still defines. After all sources are in, `extends` chains are resolved (child over parent). An id that
## appears in more than one source is legal but recorded in `warnings()`; a style file may only define ids of its own faction
## (`napc.json`: `napc`, `napc.*`; validated by tools/py/validate_recipes.py, V-RCP-12), which makes conflicts impossible in practice.

const DEFAULT_DIR: String = "res://data/recipes"
const RESERVED: Array[String] = ["index", "styles", "style", "moods", "fx", "quality", "assignments", "footprints"]
const FOOTPRINTS_SCHEMA: String = "meridian.footprints/1"
const MAX_PADS: int = 8
const STYLES_SCHEMA: String = "meridian.styles/1"
const NEUTRAL: StringName = &"neutral"

var _recipes: Dictionary = {}  # StringName -> ViewRecipe
var _archetypes: Dictionary = {}  # StringName -> ViewRecipe.Archetype
var _styles_raw: Dictionary = {}  # StringName -> Dictionary (as authored)
var _styles: Dictionary = {}  # StringName -> merged Dictionary
var _errors: PackedStringArray = PackedStringArray()
var _warnings: PackedStringArray = PackedStringArray()
var _ids: PackedStringArray = PackedStringArray()
var _style_src: Dictionary = {}  # StringName -> source name of the first definition (for override warnings)
var _footprints: Dictionary = {}  # recipe id (StringName) -> Dictionary name -> float (structure footprint anchors)


## Loads every archetype, the styles file and every recipe under `dir`. False (errors collected) on any schema violation.
func load_all(dir: String = DEFAULT_DIR) -> bool:
	_errors = PackedStringArray()
	_warnings = PackedStringArray()
	for f: String in _json_files(dir + "/archetypes"):
		var d: Dictionary = _read(dir + "/archetypes/" + f)
		if not d.is_empty():
			add_archetype(d, f)
	var sp: String = dir + "/styles.json"
	if FileAccess.file_exists(sp):
		var sd: Dictionary = _read(sp)
		if not sd.is_empty():
			add_styles(sd, "styles.json", true)
	for f: String in _json_files(dir + "/styles"):
		var fd: Dictionary = _read(dir + "/styles/" + f)
		if not fd.is_empty():
			add_styles(fd, "styles/" + f, true)
	var fp: String = dir + "/footprints.json"
	if FileAccess.file_exists(fp):
		var fdict: Dictionary = _read(fp)
		if not fdict.is_empty():
			add_footprints(fdict, "footprints.json")
	for f: String in _json_files(dir):
		if RESERVED.has(f.get_basename()):
			continue
		var rd: Dictionary = _read(dir + "/" + f)
		if not rd.is_empty():
			add_recipe(rd, f)
	link()
	return _errors.is_empty()


func add_archetype(d: Dictionary, src: String = "archetype") -> bool:
	var a: ViewRecipe.Archetype = ViewRecipe.Archetype.from_dict(d, src, _errors)
	if a == null:
		return false
	_archetypes[a.id] = a
	return true


func add_recipe(d: Dictionary, src: String = "recipe") -> bool:
	var r: ViewRecipe = ViewRecipe.from_dict(d, src, _errors)
	if r == null:
		return false
	_recipes[r.id] = r
	return true


## `d` is a styles document (`{"schema": "meridian.styles/1", "styles": {id: style}}`). With `merge` false a style of an
## existing id is REPLACED; with `merge` true (what load_all uses for styles.json and styles/*.json) it is deep-merged over the
## earlier definition (later source wins per key) and the override is noted in `warnings()`.
func add_styles(d: Dictionary, src: String = "styles", merge: bool = false) -> bool:
	if str(d.get("schema", "")) != STYLES_SCHEMA or not (d.get("styles") is Dictionary):
		_errors.append("%s: expected schema \"%s\" with a 'styles' object" % [src, STYLES_SCHEMA])
		return false
	var st: Dictionary = d["styles"] as Dictionary
	for k: Variant in st:
		if not (st[k] is Dictionary):
			_errors.append("%s: style '%s' must be an object" % [src, k])
			continue
		var sid: StringName = StringName(str(k))
		if merge and _styles_raw.has(sid):
			_warnings.append("style '%s' from %s is merged over the definition in %s" % [sid, src, _style_src.get(sid, "?")])
			_merge_into(_styles_raw[sid] as Dictionary, st[k] as Dictionary)
		else:
			_styles_raw[sid] = (st[k] as Dictionary).duplicate(true)
			_style_src[sid] = src
	return true


## `d` is a footprints document (`{"schema": "meridian.footprints/1", "structures": {recipe id: {fw, fh, door_cx, door_cz,
## exit_dir, dock_cx, dock_cz, dock_dir, pads_n}}}`, generated by tools/py/gen_recipe_index.py from the balance data).
func add_footprints(d: Dictionary, src: String = "footprints") -> bool:
	if str(d.get("schema", "")) != FOOTPRINTS_SCHEMA or not (d.get("structures") is Dictionary):
		_errors.append("%s: expected schema \"%s\" with a 'structures' object" % [src, FOOTPRINTS_SCHEMA])
		return false
	var st: Dictionary = d["structures"] as Dictionary
	for k: Variant in st:
		if not (st[k] is Dictionary):
			_errors.append("%s: footprint '%s' must be an object" % [src, k])
			continue
		var vars: Dictionary = {}
		var rec: Dictionary = st[k] as Dictionary
		for f: Variant in rec:
			vars[str(f)] = float(rec[f])
		var pn: int = int(vars.get("pads_n", 0.0))
		var fw: float = float(vars.get("fw", 1.0))
		for i: int in MAX_PADS:  # all MAX_PADS pairs always exist (recipes compile every branch); unused pads sit at 0
			vars["pad_x%d" % i] = ((float(i) + 0.5) / float(pn) - 0.5) * (fw * 3.0 - 1.0) if i < pn else 0.0
			vars["pad_z%d" % i] = 0.0
		_footprints[StringName(str(k))] = vars
	return true


## Scope variables the interpreter gets for a structure recipe (render spec 5.8.1): fw, fh, door_cx, door_cz, exit_dir, dock_cx,
## dock_cz, dock_dir, pads_n, and pad_x0..pad_x7 / pad_z0..pad_z7 (pad centres; the spec's pad_x(i) / pad_z(i) functions as plain
## variables because ViewExpr has no such function, metres from the footprint centre, the same even spread along the footprint
## width as ViewDefAdapter; pads beyond pads_n are 0). Empty for non-structures.
func footprint_vars(recipe_id: StringName) -> Dictionary:
	return _footprints.get(recipe_id, {}) as Dictionary


func has_footprint(recipe_id: StringName) -> bool:
	return _footprints.has(recipe_id)


## Resolves recipe -> archetype references and merges the style `extends` chains. Called by load_all(); call it again after
## add_* in tests. Returns false when a reference or chain is broken (errors() has the details).
func link() -> bool:
	var n: int = _errors.size()
	for k: Variant in _recipes:
		var r: ViewRecipe = _recipes[k] as ViewRecipe
		r.arch = _archetypes.get(r.archetype) as ViewRecipe.Archetype
		if r.arch == null:
			_errors.append("%s: unknown archetype '%s'" % [r.id, r.archetype])
	_styles.clear()
	for k: Variant in _styles_raw:
		var chain: Array[StringName] = []
		var m: Dictionary = _merged_style(k as StringName, chain)
		if not m.is_empty() or (_styles_raw[k] as Dictionary).is_empty():
			_styles[k] = m
	_ids = PackedStringArray()
	for k: Variant in _recipes:
		_ids.append(String(k as StringName))
	_ids.sort()  # String order (code points), the order of index.json; StringName.sort() would order by hash
	return _errors.size() == n


func has_recipe(id: StringName) -> bool:
	return _recipes.has(id)


## Null if unknown (ViewModelBuilder then builds a placeholder and logs one warning).
func recipe(id: StringName) -> ViewRecipe:
	return _recipes.get(id) as ViewRecipe


func archetype(id: StringName) -> ViewRecipe.Archetype:
	return _archetypes.get(id) as ViewRecipe.Archetype


func has_style(style_id: StringName) -> bool:
	return _styles.has(style_id)


## Fully merged style (extends chain resolved); an empty Dictionary for an unknown style.
func style(style_id: StringName) -> Dictionary:
	return _styles.get(style_id, {}) as Dictionary


## "roster.napc.canada" -> &"napc.canada"; falls back to the faction ("napc"), then &"neutral".
func style_for_roster(roster_id: String) -> StringName:
	var s: String = roster_id.trim_prefix("roster.")
	while not s.is_empty():
		if _styles.has(StringName(s)):
			return StringName(s)
		var dot: int = s.rfind(".")
		if dot < 0:
			break
		s = s.substr(0, dot)
	return NEUTRAL


## unit.napc.* / structure.napc.* / summon.napc.* -> the owner's roster style when the owner plays that faction (napc.usa), else the faction's
## base style; *.shared.* -> the owner's style; neutral.* -> neutral.
func style_for_def(def_id: String, owner_roster_id: String) -> StringName:
	var parts: PackedStringArray = def_id.split(".")
	if parts.size() < 2:
		return NEUTRAL
	if parts[0] == "neutral" or parts[1] == "neutral":
		return NEUTRAL
	if parts[1] == "shared":
		return style_for_roster(owner_roster_id)
	if _styles.has(StringName(parts[1])):
		# VQ2A: a unit / structure of the owner's OWN faction wears the owner's roster style, so subfaction insignia, accent and kit-bash
		# slots (napc.usa, ...) appear on every model of that roster, not only on the shared ones; foreign defs keep their faction style
		var rs: StringName = style_for_roster(owner_roster_id)
		if rs != NEUTRAL and String(rs).get_slice(".", 0) == parts[1]:
			return rs
		return StringName(parts[1])
	return style_for_roster(owner_roster_id) if parts[0] == "proj" else NEUTRAL


## Sorted recipe ids.
func ids() -> PackedStringArray:
	return _ids


func archetype_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _archetypes:
		out.append(String(k as StringName))
	out.sort()
	return out


func style_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _styles:
		out.append(String(k as StringName))
	out.sort()
	return out


func errors() -> PackedStringArray:
	return _errors


## Non-fatal notes of the last load (a style id defined by more than one file).
func warnings() -> PackedStringArray:
	return _warnings


# ---------------------------------------------------------------------------------------------- internals
func _merged_style(id: StringName, chain: Array[StringName]) -> Dictionary:
	if chain.has(id):
		_errors.append("style extends cycle at '%s'" % id)
		return {}
	var raw: Dictionary = _styles_raw.get(id, {}) as Dictionary
	var parent: StringName = StringName(str(raw.get("extends", "")))
	var out: Dictionary = {}
	if parent != &"":
		if not _styles_raw.has(parent):
			_errors.append("style '%s' extends unknown style '%s'" % [id, parent])
		else:
			chain.append(id)
			out = _merged_style(parent, chain)
			chain.pop_back()
	_merge_into(out, raw)
	out.erase("extends")
	return out


## Deep merge: objects merge key by key, everything else (arrays, slots, scalars) is replaced by the child.
static func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k: Variant in src:
		var v: Variant = src[k]
		if v is Dictionary and dst.get(k) is Dictionary:
			_merge_into(dst[k] as Dictionary, v as Dictionary)
		elif v is Dictionary:
			dst[k] = (v as Dictionary).duplicate(true)
		elif v is Array:
			dst[k] = (v as Array).duplicate(true)
		else:
			dst[k] = v


func _json_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out  # e.g. no styles/ directory yet
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func _read(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		_errors.append("%s:%d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return {}
	if not (j.data is Dictionary):
		_errors.append("%s: root must be an object" % path)
		return {}
	return j.data as Dictionary
