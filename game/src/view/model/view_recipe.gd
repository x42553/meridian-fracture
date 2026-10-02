class_name ViewRecipe
extends RefCounted
## Parsed model recipe (render spec 4.10, 7.3) and its archetype (7.2). Plain data: the ops stay raw JSON values, the
## interpreter compiles them per build. Instances are created by ViewRecipeBook (or tests) and never mutated afterwards, so
## worker threads can read them freely.

const SCHEMA: String = "meridian.recipe/1"
const ARCH_SCHEMA: String = "meridian.archetype/1"


## A view archetype (`archetypes/<id>.json`): parametric op list + defaults + derived lets + default slots.
class Archetype extends RefCounted:
	var id: StringName = &""
	var size_class: StringName = &"medium"
	var scale: float = 1.0  ## 1.25 for the inf_* archetypes (RTS readability)
	var bevel: float = 0.0  ## builder default_bevel
	var meta: Dictionary = {}
	var defaults: Dictionary = {}  ## param -> number | string | bool (the type of the default is the type of the param)
	var derive: Dictionary = {}  ## ordered: let name -> number | expression
	var slots: Dictionary = {}  ## slot name -> op array
	var ops: Array = []

	## Parses an archetype dictionary; errors are appended to `errs` and null is returned.
	static func from_dict(d: Dictionary, src: String, errs: PackedStringArray) -> Archetype:
		var n: int = errs.size()
		if str(d.get("schema", "")) != ARCH_SCHEMA:
			errs.append("%s: schema must be \"%s\"" % [src, ARCH_SCHEMA])
		var a: Archetype = Archetype.new()
		a.id = StringName(str(d.get("id", "")))
		if a.id == &"":
			errs.append("%s: archetype has no id" % src)
		a.size_class = StringName(str(d.get("size_class", "medium")))
		a.scale = float(d.get("scale", 1.0))
		a.bevel = float(d.get("bevel", 0.0))
		for key: String in ["meta", "defaults", "derive", "slots"]:
			if d.has(key) and not (d[key] is Dictionary):
				errs.append("%s: '%s' must be an object" % [src, key])
		if d.has("ops") and not (d["ops"] is Array):
			errs.append("%s: 'ops' must be an array" % src)
		if errs.size() > n:
			return null
		a.meta = d.get("meta", {}) as Dictionary
		a.defaults = d.get("defaults", {}) as Dictionary
		a.derive = d.get("derive", {}) as Dictionary
		a.slots = d.get("slots", {}) as Dictionary
		a.ops = d.get("ops", []) as Array
		for k: Variant in a.defaults:
			var v: Variant = a.defaults[k]
			if not (v is float or v is int or v is String or v is bool):
				errs.append("%s: default '%s' must be a number, string or bool" % [src, k])
		for k: Variant in a.slots:
			if not (a.slots[k] is Array):
				errs.append("%s: slot '%s' must be an op array" % [src, k])
		return a if errs.size() == n else null


var id: StringName = &""
var archetype: StringName = &""
var style: StringName = &"auto"  ## "auto": resolved from the def / owner (ViewRecipeBook.style_for_def)
var scale: float = 1.0
var seed_override: int = 0  ## JSON `seed`; 0 = derived from (recipe id, style id)
var bevel: float = -1.0  ## < 0 = archetype default
var params: Dictionary = {}  ## overrides of archetype.defaults (numbers, strings, bools or numeric expressions)
var kits: Dictionary = {}  ## named parameter sets (reserved; not applied by the interpreter)
var slots: Dictionary = {}  ## slot name -> op array (wins over style and archetype slots)
var ops_after: Array = []
var sockets: Dictionary = {}  ## name -> {pos, dir, part?}: extra sockets appended after ops_after
var meta: Dictionary = {}
var arch: Archetype = null  ## resolved by ViewRecipeBook.link()


static func from_dict(d: Dictionary, src: String, errs: PackedStringArray) -> ViewRecipe:
	var n: int = errs.size()
	if str(d.get("schema", "")) != SCHEMA:
		errs.append("%s: schema must be \"%s\"" % [src, SCHEMA])
	var r: ViewRecipe = ViewRecipe.new()
	r.id = StringName(str(d.get("id", "")))
	r.archetype = StringName(str(d.get("archetype", "")))
	if r.id == &"" or r.archetype == &"":
		errs.append("%s: recipe needs 'id' and 'archetype'" % src)
	r.style = StringName(str(d.get("style", "auto")))
	r.scale = float(d.get("scale", 1.0))
	r.seed_override = int(d.get("seed", 0))
	r.bevel = float(d.get("bevel", -1.0))
	for key: String in ["params", "kits", "slots", "sockets", "meta"]:
		if d.has(key) and not (d[key] is Dictionary):
			errs.append("%s: '%s' must be an object" % [src, key])
	if d.has("ops_after") and not (d["ops_after"] is Array):
		errs.append("%s: 'ops_after' must be an array" % src)
	if errs.size() > n:
		return null
	r.params = d.get("params", {}) as Dictionary
	r.kits = d.get("kits", {}) as Dictionary
	r.slots = d.get("slots", {}) as Dictionary
	r.ops_after = d.get("ops_after", []) as Array
	r.sockets = d.get("sockets", {}) as Dictionary
	r.meta = d.get("meta", {}) as Dictionary
	for k: Variant in r.slots:
		if not (r.slots[k] is Array):
			errs.append("%s: slot '%s' must be an op array" % [src, k])
	return r if errs.size() == n else null
