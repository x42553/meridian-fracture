class_name AppProfile
extends RefCounted
## The minimum player profile: commander name (sanitised OS user name by default), last roster and lifetime counters.
## Persisted through `AppSettingsStore` (`net/player_name`, `game/last_roster`); counters stay in memory until a later
## task stores them. Names may contain any printable Unicode; `ascii_name()` is the file-name-safe form.

const DEFAULT_NAME: String = "Commander"

var player_name: String = DEFAULT_NAME
var last_roster: String = "roster.napc.vanilla"
var favourites: PackedStringArray = PackedStringArray()
var counters: Dictionary = {"matches": 0, "wins": 0, "losses": 0}
## Campaign progress (`user://campaign.cfg`, MIS2). In memory until boot opens the file (`AppBoot`), so tests never write the real one.
var campaign: AppCampaign = AppCampaign.new()


## Builds the profile from a settings store.
static func from_store(store: AppSettingsStore) -> AppProfile:
	var p: AppProfile = AppProfile.new()
	p.player_name = sanitize_name(str(store.get_value(&"net/player_name")))
	p.last_roster = str(store.get_value(&"game/last_roster"))
	return p


## Writes the profile fields back into the store.
func save_to(store: AppSettingsStore) -> void:
	store.set_value(&"net/player_name", player_name)
	store.set_value(&"game/last_roster", last_roster)


## Control characters removed, whitespace collapsed, at most 24 characters; "Commander" when nothing is left.
static func sanitize_name(raw: String) -> String:
	var out: String = ""
	var last_space: bool = true
	for i: int in raw.length():
		var c: int = raw.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or c == 0x2028 or c == 0x2029:
			continue
		if c == 32 or c == 0xA0:
			if last_space:
				continue
			last_space = true
			out += " "
			continue
		last_space = false
		out += String.chr(c)
	out = out.strip_edges()
	if out.length() > AppSettingsSchema.NAME_MAX:
		out = out.substr(0, AppSettingsSchema.NAME_MAX).strip_edges()
	return out if not out.is_empty() else DEFAULT_NAME


## Sanitised OS user name, else "Commander".
static func default_name() -> String:
	var raw: String = OS.get_environment("USER")
	if raw.is_empty():
		raw = OS.get_environment("USERNAME")
	if raw.is_empty():
		return DEFAULT_NAME
	return sanitize_name(raw.capitalize() if raw == raw.to_lower() else raw)


## ASCII-only form of the name for file names (every other character becomes an underscore).
func ascii_name() -> String:
	var out: String = ""
	for i: int in player_name.length():
		var c: int = player_name.unicode_at(i)
		var ok: bool = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95
		out += String.chr(c) if ok else "_"
	return out
