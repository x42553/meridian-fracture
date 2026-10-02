class_name DefDomainCompiler
extends RefCounted
## Plug-in interface for domain-owned balance files (combat, abilities, economy, ...; data_balance 3.12). Subclasses
## override every method; the defaults report NOT IMPLEMENTED so a half-written compiler cannot pass silently.


## Unique lowercase domain id ("combat", "abilities", "economy", ...).
func domain_id() -> String:
	push_error("NOT IMPLEMENTED: DefDomainCompiler.domain_id")
	return ""


## Manifest files owned by this compiler (must appear in manifest.json).
func file_names() -> PackedStringArray:
	return PackedStringArray()


## P3: declare ids so other files can reference them.
func collect_ids(_src: DefSources, _ids: DefIds, _rep: DefLoadReport) -> void:
	pass


## P4-P6: convert to ints; store tables in data.ext[domain_id()] and/or fill common defs.
func compile(_src: DefSources, _data: GameData, _rep: DefLoadReport) -> void:
	pass


## P9: domain rules (rule ids prefixed by the domain, e.g. V-CMB-*).
func validate(_data: GameData, _rep: DefLoadReport, _level: int) -> void:
	pass


## {"combat": int, ...} folded into data_hash in sorted-key order.
func table_hashes(_data: GameData) -> Dictionary:
	return {}
