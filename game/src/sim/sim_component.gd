class_name SimComponent
extends RefCounted
## Base of every domain component slot (sim_core 3.3.2 / 4.5). Components hold ints and packed int arrays only
## (no Dictionary, Node, float or object references: other entities are referenced by id; 64-bit values as two
## ints) and never point back at their entity or the world.
##
## Every subclass must:
##  * override `hash_into(buf)` and append EVERY authoritative field, in a fixed order (DR-13);
##  * declare its own `const HASH_EXEMPT: PackedStringArray` naming DERIVED fields that are deliberately not hashed.
##    (GDScript forbids shadowing a parent constant, so this base class cannot declare it; the coverage test reads
##    `SimCompX.HASH_EXEMPT` from the concrete class.)


## Appends every authoritative field (fixed order, ints only). The base has no fields.
func hash_into(_buf: PackedInt32Array) -> void:
	pass


## Reflective dump of all script variables (debug UI, tests, desync forensics); packed arrays are copied.
func dump() -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		var v: Variant = get(n)
		if v is SimComponent:
			out[n] = (v as SimComponent).dump()
		elif v is PackedInt32Array:
			out[n] = (v as PackedInt32Array).duplicate()
		else:
			out[n] = v
	return out
