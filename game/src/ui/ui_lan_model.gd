class_name UiLanModel
extends RefCounted
## Pure model of the LAN browser (ui.md 5.15): turns `NetDiscoveryEntry` objects into list rows (cells, dimming, tooltips), filters
## and sorts them, decides what JOIN GAME may do with a selected game and validates the direct-connect fields. No nodes, no sockets;
## unit tested on fixtures.
##
## Columns of the list (5.15 asks for GAME, HOST, MAP, PLAYERS, RULES, PING, BUILD; a discovery datagram carries neither rules nor a
## measured ping, so those two are left out): GAME, HOST, MAP, PLAYERS, BUILD.

enum Col { GAME = 0, HOST = 1, MAP = 2, PLAYERS = 3, BUILD = 4 }

const COLUMN_NAMES: PackedStringArray = ["GAME", "HOST", "MAP", "PLAYERS", "BUILD"]
const COLUMN_WIDTHS: PackedFloat32Array = [270.0, 210.0, 230.0, 120.0, 210.0]
## Hint texts of the silence rules (net.help.*): shown after `NO_GAMES_AFTER_S` of an empty list, on `port_in_use`, and when the announce is blocked.
const NO_GAMES_AFTER_S: float = 8.0
const ANNOUNCE_BLOCKED_AFTER_S: float = 10.0
const HINT_NO_GAMES: String = "No games found yet. Make sure the host has opened a game on the same network, or join with the host's address on the right."
const HINT_PORT_IN_USE: String = "The LAN discovery port is in use by another program. Use Join by address."
const HINT_ANNOUNCE_BLOCKED: String = "Your announcements are not getting out. A firewall or the macOS Local Network permission may be blocking them; other players can still join your address."


## One list row of an entry: `{key, entry, cells: Array[Dictionary], dimmed, locked (password), joinable, reason, tooltip, sort: Array}`. `local_version` is
## the version of this build (shown as "v0.1.0 OK").
static func row_of(e: NetDiscoveryEntry, local_version: String = "") -> Dictionary:
	var join: Dictionary = join_state(e)
	var version: String = e.game_version if e.game_version != "" else local_version
	var build_text: String
	var build_color: Color = UiPalette.semantic(&"ok")
	if e.compatible:
		build_text = "v%s  OK" % version if version != "" else "OK"
	else:
		build_color = UiPalette.semantic(&"danger")
		build_text = "%s  %s" % ["v" + version if version != "" else "", "DATA" if e.mismatch == "game data" else "OLD"]
		build_text = build_text.strip_edges()
	var name_text: String = e.host_name
	var players: String = "%d / %d" % [e.humans + e.ai_count, e.slots_total] if e.slots_total > 0 else "-"
	if e.is_full():
		players += "  FULL"
	elif e.in_progress():
		players = "IN GAME"
	var map_text: String = "%s  %d" % [UiMapNames.family_name(e.map_family), e.map_size] if e.map_size > 0 else UiMapNames.family_name(e.map_family)
	var cells: Array[Dictionary] = [
		{"text": name_text},
		{"text": e.address + ":" + str(e.port), "mono": true},
		{"text": map_text},
		{"text": players, "mono": true},
		{"text": build_text, "color": build_color},
	]
	var tip: String = ""
	if not e.compatible:
		tip = "This game runs a different %s.\nHost: %s  protocol %d  simulation %d  data %s\nYou: see the details when you try to join." % [
			e.mismatch, e.game_version, e.proto_version, e.sim_version, UiFormatLite.hash8(e.data_hash)]
	elif e.is_full():
		tip = "The game is full."
	return {"key": key_of(e), "entry": e, "cells": cells, "dimmed": not bool(join["can_join"]), "locked": e.has_password(), "joinable": bool(join["can_join"]),
		"reason": str(join["reason"]), "tooltip": tip,
		"sort": [e.host_name.to_lower(), e.address, "%d %04d" % [e.map_family, e.map_size], e.humans + e.ai_count, 1 if e.compatible else 0]}


## The identity of a listed game (source address + session id), stable across refreshes.
static func key_of(e: NetDiscoveryEntry) -> String:
	return "%s|%d" % [e.address, e.session_id]


## `{can_join: bool, reason: String}`: what JOIN GAME may do with this entry, and why not.
static func join_state(e: NetDiscoveryEntry) -> Dictionary:
	if not e.compatible:
		return {"can_join": false, "reason": "This game runs a different %s. Both computers must run the same build." % e.mismatch}
	if e.in_progress():
		return {"can_join": false, "reason": "The match has already started."}
	if e.is_full() and not e.spectators_allowed():
		return {"can_join": false, "reason": "The game is full."}
	return {"can_join": true, "reason": ""}


## Filtered and sorted rows. `filters`: text (case-insensitive substring of name, host and map), hide_full, hide_incompatible.
## `sort_col` is a `Col`; the default order is by name then address (a stable order while entries come and go).
static func build_rows(entries: Array[NetDiscoveryEntry], filters: Dictionary = {}, sort_col: int = Col.GAME, descending: bool = false, local_version: String = "") -> Array[Dictionary]:
	var text: String = str(filters.get("text", "")).strip_edges().to_lower()
	var rows: Array[Dictionary] = []
	for e: NetDiscoveryEntry in entries:
		if bool(filters.get("hide_full", false)) and (e.is_full() or e.in_progress()):
			continue
		if bool(filters.get("hide_incompatible", false)) and not e.compatible:
			continue
		var r: Dictionary = row_of(e, local_version)
		if text != "":
			var hay: String = "%s %s %s" % [e.host_name, e.address, str((r["cells"] as Array[Dictionary])[Col.MAP]["text"])]
			if not hay.to_lower().contains(text):
				continue
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = (a["sort"] as Array)[sort_col]
		var kb: Variant = (b["sort"] as Array)[sort_col]
		if ka == kb:
			var na: String = str((a["sort"] as Array)[0]) + str((a["sort"] as Array)[1]) + str(a["key"])
			var nb: String = str((b["sort"] as Array)[0]) + str((b["sort"] as Array)[1]) + str(b["key"])
			return na < nb
		return (ka > kb) if descending else (ka < kb))
	return rows


## Direct-connect input -> `{ok, host, port, error, target}`. The address may carry a port ("192.168.1.20:27616"); `port_text` is used
## otherwise (empty = 27615). Host names up to 253 characters, ports 1024-65535.
static func validate_direct(address: String, port_text: String = "") -> Dictionary:
	var a: String = address.strip_edges()
	var parsed: Dictionary = NetProtocol.parse_address(a)
	if not bool(parsed["ok"]):
		return {"ok": false, "host": "", "port": 0, "target": "", "error": "Enter the host's IP address or name (%s)." % str(parsed["error"])}
	var has_port: bool = a.begins_with("[") and a.contains("]:") or (a.count(":") == 1)
	var port: int = int(parsed["port"]) if has_port else (port_text.strip_edges().to_int() if port_text.strip_edges() != "" else NetProtocol.DEFAULT_PORT)
	if port_text.strip_edges() != "" and not port_text.strip_edges().is_valid_int() and not has_port:
		return {"ok": false, "host": "", "port": 0, "target": "", "error": "The port must be a number between 1024 and 65535."}
	if port < 1024 or port > 65535:
		return {"ok": false, "host": "", "port": 0, "target": "", "error": "The port must be between 1024 and 65535."}
	var host: String = str(parsed["host"])
	var target: String = "%s:%d" % [host if not host.contains(":") else "[" + host + "]", port]
	return {"ok": true, "host": host, "port": port, "target": target, "error": ""}


## The silence hint of the browser (5.15 "no false alarms"): `browse_error` and `announce_ok` come from the `NetDiscovery`, `empty_s` is
## how long the list has been empty and `hosting` whether this computer announces a game.
static func hint(browse_error: String, empty_s: float, hosting: bool = false, announce_ok: bool = true, announce_bad_s: float = 0.0) -> String:
	if browse_error == "port_in_use":
		return HINT_PORT_IN_USE
	if hosting and not announce_ok and announce_bad_s >= ANNOUNCE_BLOCKED_AFTER_S:
		return HINT_ANNOUNCE_BLOCKED
	if empty_s >= NO_GAMES_AFTER_S:
		return HINT_NO_GAMES
	return ""


## Text of the compatibility banner of the detail card: `{text, ok}`.
static func banner(e: NetDiscoveryEntry) -> Dictionary:
	if e.compatible:
		return {"ok": true, "text": "Same build as yours. You can join."}
	return {"ok": false, "text": "Different %s (host build %s). Both computers must run the same build." % [e.mismatch, e.game_version]}
