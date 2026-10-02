class_name DefAbilityKinds
extends RefCounted
## Registry of ability kinds with param specs, templates, framework-name aliases and implicit rules, parsed from
## `ability_kinds.json` (data_balance 5.10.2 / 7.4). Validation + default materialisation for ability instances.

var kinds: Dictionary = {}  ## kind name -> {id, scopes, params: {key: spec}}
var templates: Dictionary = {}  ## template id -> {kind, params (file units)}
var aliases: Dictionary = {}  ## bare framework name -> template id | null
var implicit: Array = []  ## [{when, templates}]
var def_params: Dictionary = {}  ## def-scope param registry
var template_ids: PackedStringArray = PackedStringArray()  ## sorted; index == GameData.abilities index


static func from_json(d: Dictionary, rep: DefLoadReport) -> DefAbilityKinds:
	var r: DefAbilityKinds = DefAbilityKinds.new()
	r.kinds = d.get("kinds", {})
	r.templates = d.get("templates", {})
	r.aliases = d.get("aliases", {})
	r.implicit = d.get("implicit", [])
	r.def_params = d.get("def_params", {})
	for k: Variant in r.kinds.keys():
		var name: String = str(k)
		var spec: Dictionary = r.kinds[k]
		var want: int = DefEnums.ABILITY_NAMES.find(name)
		if want <= 0 or int(spec.get("id", -1)) != want:
			rep.error("V-CNF-05", "ability_kinds.json kinds.%s" % name, "kind id %s differs from DefEnums.AbilityKind (%d)" % [str(spec.get("id")), want])
	var ids: PackedStringArray = PackedStringArray()
	for t: Variant in r.templates.keys():
		ids.append(str(t))
		var tk: String = str((r.templates[t] as Dictionary).get("kind", ""))
		if not r.kinds.has(tk):
			rep.error("V-ABL-01", "ability_kinds.json templates.%s" % str(t), "unknown kind '%s'" % tk)
	ids.sort()
	r.template_ids = ids
	return r


func kind_id(kind_name: String) -> int:
	if not kinds.has(kind_name):
		return -1
	return int((kinds[kind_name] as Dictionary).get("id", -1))


func template_index(template_id: String) -> int:
	return template_ids.find(template_id)


## Template id of a sheet entry: an `ability.*` id as is, a bare framework name through `aliases` ("" when the name
## produces no ability or is unknown; `known_entry` tells the two apart).
func resolve_entry(entry: String) -> String:
	if entry.begins_with("ability."):
		return entry if templates.has(entry) else ""
	var a: Variant = aliases.get(entry, "")
	return "" if a == null else str(a)


func known_entry(entry: String) -> bool:
	return templates.has(entry) or aliases.has(entry)


## Templates implied by `when` keys ("tag:<t>", "family:<f>", "archetype:<a>") matching the entity, registry order.
func implicit_templates_for(unit_tags: PackedStringArray, family: String, archetype: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Variant in implicit:
		var rd: Dictionary = row
		var when: String = str(rd.get("when", ""))
		var hit: bool = false
		if when.begins_with("tag:"):
			hit = unit_tags.has(when.substr(4))
		elif when.begins_with("family:"):
			hit = family == when.substr(7)
		elif when.begins_with("archetype:"):
			hit = archetype == when.substr(10)
		if hit:
			for t: Variant in rd.get("templates", []):
				out.append(str(t))
	return out


## Builds one ability instance: kind defaults < template params < `overrides` (all in file units), validated against
## the kind spec (unknown key or missing required key = V-ABL-01), every default materialised, converted by suffix.
func instantiate(template_id: String, overrides: Dictionary, ctx: String, data: GameData, rep: DefLoadReport) -> DefAbility:
	var a: DefAbility = DefAbility.new()
	if not templates.has(template_id):
		rep.error("V-ABL-01", ctx, "unknown ability template '%s'" % template_id)
		return a
	var t: Dictionary = templates[template_id]
	var kind_name: String = str(t.get("kind", ""))
	var spec: Dictionary = (kinds[kind_name] as Dictionary).get("params", {})
	var file_params: Dictionary = {}
	for k: Variant in spec.keys():
		var ps: Dictionary = spec[k]
		if ps.has("def"):
			file_params[k] = ps["def"]
	var tp: Dictionary = t.get("params", {})
	for k: Variant in tp.keys():
		file_params[k] = tp[k]
	for k: Variant in overrides.keys():
		if not spec.has(k):
			rep.error("V-ABL-01", ctx, "ability '%s': unknown param '%s'" % [template_id, str(k)])
			continue
		file_params[k] = overrides[k]
	for k: Variant in spec.keys():
		var ps2: Dictionary = spec[k]
		if bool(ps2.get("req", false)) and not file_params.has(k):
			rep.error("V-ABL-01", ctx, "ability '%s': required param '%s' is missing" % [template_id, str(k)])
	a.kind = kind_id(kind_name)
	a.template = template_index(template_id)
	a.params = DefConvert.convert_params(file_params, "%s %s" % [ctx, template_id], data, rep)
	return a
