class_name DefLoadReport
extends RefCounted
## Ordered problem list of one load (data_balance 3.2). Every entry is "RULE where: msg"; `where` carries `path:line`
## whenever a source location is known.

enum Sev { ERROR = 0, WARN = 1, INFO = 2 }

var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()
var infos: PackedStringArray = PackedStringArray()


## Appends "RULE where: msg" to the list of `sev`.
func add(sev: int, rule: String, where: String, msg: String) -> void:
	var line: String = "%s %s: %s" % [rule, where, msg]
	if sev == Sev.ERROR:
		errors.append(line)
	elif sev == Sev.WARN:
		warnings.append(line)
	else:
		infos.append(line)


func error(rule: String, where: String, msg: String) -> void:
	add(Sev.ERROR, rule, where, msg)


func warn(rule: String, where: String, msg: String) -> void:
	add(Sev.WARN, rule, where, msg)


func info(rule: String, where: String, msg: String) -> void:
	add(Sev.INFO, rule, where, msg)


func is_ok() -> bool:
	return errors.is_empty()


## Number of entries (any severity) whose rule id is `rule`.
func count_rule(rule: String) -> int:
	var n: int = 0
	var prefix: String = rule + " "
	for arr: PackedStringArray in [errors, warnings, infos]:
		for line: String in arr:
			if line.begins_with(prefix):
				n += 1
	return n


func has_rule(rule: String) -> bool:
	return count_rule(rule) > 0


## Copies every entry of `other` (used when a sub-step keeps its own report).
func merge(other: DefLoadReport) -> void:
	errors.append_array(other.errors)
	warnings.append_array(other.warnings)
	infos.append_array(other.infos)


## Errors, then warnings, then infos, at most `max_lines` lines.
func text(max_lines: int = 200) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in errors:
		out.append("ERROR " + line)
	for line: String in warnings:
		out.append("WARN  " + line)
	for line: String in infos:
		out.append("INFO  " + line)
	if out.size() > max_lines:
		var extra: int = out.size() - max_lines
		out = out.slice(0, max_lines)
		out.append("... %d more" % extra)
	return "\n".join(out)
