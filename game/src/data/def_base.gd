class_name DefBase
extends RefCounted
## Base of every def (data_balance 4.2). Field-name prefixes control the hash: `_x` (private cache), `ui_x` (label /
## text) and `pres_x` (presentation ids) are excluded from `data_hash`; everything else is hashed. Only int, bool,
## String, PackedInt32Array, PackedByteArray, Array of owned child defs and Dictionary of those may appear (no float,
## no Vector*, no Color, no object reference to another def: cross references are indices).
## GOTCHA (Godot 4): packed arrays are shared by reference between Variants and assignments - never mutate a def's
## packed array in place after build, and `.duplicate()` before handing one to a mutable owner.

var id: String = ""
var index: int = -1  ## position in the owning GameData array of its kind
var kind: int = 0  ## DefEnums.Kind
var tags: int = 0  ## tag mask in the kind's namespace (unit / structure / weapon)
var params: Dictionary = {}  ## converted params (runtime-suffixed keys, sorted)
var ui_name: String = ""
var ui_text: String = ""


## Reflective deep copy (resolved clones): child defs (Array[Def*]) are copied, packed arrays and dictionaries are
## duplicated, so mutating the clone never touches the original.
func copy_resolved() -> DefBase:
	return deep_copy(self) as DefBase


## Reflective deep copy of any def object (all script variables, including `_` / `ui_` / `pres_` ones).
static func deep_copy(src: Object) -> Object:
	var script: GDScript = src.get_script() as GDScript
	var dst: Object = script.new()
	for p: Dictionary in src.get_property_list():
		var usage: int = p["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		dst.set(n, _clone_value(src.get(n)))
	return dst


static func _clone_value(v: Variant) -> Variant:
	var t: int = typeof(v)
	if t == TYPE_OBJECT:
		if v == null:
			return null
		return deep_copy(v as Object)
	if t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY:
		# Godot 4 shares packed arrays by reference between Variants: copy explicitly.
		return v.duplicate()
	if t == TYPE_ARRAY:
		var a: Array = v
		var out: Array = a.duplicate()
		for i: int in out.size():
			out[i] = _clone_value(out[i])
		return out
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var out_d: Dictionary = {}
		for k: Variant in d.keys():
			out_d[k] = _clone_value(d[k])
		return out_d
	return v
