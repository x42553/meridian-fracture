class_name UiReplayModel
extends RefCounted
## Pure model of the replay browser (ui.md 5.16.6): turns the metadata `NetReplay.read_info` returns into list rows (date, map,
## players with colour pips, result, length, build compatibility), applies the filters and the sort, and formats the detail pane.
## No nodes, no I/O: `UiScreenReplays` feeds it and renders the rows with `UiListRow`.

enum Col { DATE = 0, MAP = 1, PLAYERS = 2, RESULT = 3, LENGTH = 4, BUILD = 5 }

const COLUMN_NAMES: PackedStringArray = ["DATE", "MAP", "PLAYERS", "RESULT", "LENGTH", "BUILD"]
const COLUMN_WIDTHS: PackedFloat32Array = [146.0, 176.0, 176.0, 128.0, 70.0, 92.0]
## Build states of `build_state`.
const BUILD_OK: int = 0
const BUILD_BALANCE: int = 1
const BUILD_OLD: int = 2
const BUILD_BROKEN: int = 3
const PIP: float = 9.0


## The column widths scaled to `avail` px (never below the base widths, at most 1.8 x): the extra room goes to MAP and PLAYERS.
static func scaled_widths(avail: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = COLUMN_WIDTHS.duplicate()
	var base: float = 0.0
	for w: float in COLUMN_WIDTHS:
		base += w
	var extra: float = clampf(avail - base, 0.0, base * 0.8)
	out[Col.MAP] += extra * 0.4
	out[Col.PLAYERS] += extra * 0.4
	out[Col.RESULT] += extra * 0.2
	return out


## "Last match" (autosave_1), "Match 2 back" (autosave_2 ..), "Recovered (truncated)" (crash_*), else the file name.
static func title_of(info: Dictionary) -> String:
	var base: String = str(info.get("name", ""))
	match str(info.get("kind", "manual")):
		"autosave":
			var n: int = base.trim_prefix(NetReplay.AUTOSAVE_PREFIX).to_int()
			return "Last match" if n <= 1 else "Match %d back" % n
		"crash":
			return "Recovered (truncated)"
	return base


## The small caption of an automatic replay in the list: "LAST" (autosave_1), "AUTO 2" ..., "RECOVERED" (crash_*), "" for manual ones.
static func tag_of(info: Dictionary) -> String:
	match str(info.get("kind", "manual")):
		"autosave":
			var n: int = str(info.get("name", "")).trim_prefix(NetReplay.AUTOSAVE_PREFIX).to_int()
			return "LAST" if n <= 1 else "AUTO %d" % n
		"crash":
			return "CRASH"
	return ""


## Local date and time "2026-10-01 14:03" of a unix time (`bias_min` = the local UTC offset in minutes; default: the system's).
static func date_text(unix: int, bias_min: int = -100000) -> String:
	if unix <= 0:
		return "-"
	var bias: int = bias_min
	if bias == -100000:
		bias = int(Time.get_time_zone_from_system().get("bias", 0))
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [int(dt["year"]), int(dt["month"]), int(dt["day"]), int(dt["hour"]), int(dt["minute"])]


## The unix time shown as the replay's date: when it was started, else the file's modification time.
static func when_of(info: Dictionary) -> int:
	var s: int = int(info.get("started_unix", 0))
	return s if s > 0 else int(info.get("mtime", 0))


static func map_name(map: Dictionary) -> String:
	return UiMapNames.name_for(int(map.get("family", 0)), int(map.get("seed", 0)))


## "Ridge Crossing  128" for the list.
static func map_text(map: Dictionary) -> String:
	if map.is_empty():
		return "-"
	return "%s  %d" % [map_name(map), int(map.get("size", 0))]


static func size_text(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (float(bytes) / 1048576.0)
	return "%d KB" % maxi((bytes + 1023) / 1024, 1)


## "12:34" of a tick count.
static func length_text(ticks: int) -> String:
	return UiFormatLite.clock(ticks * SimConfig.TICK_MS / 1000)


## The pids of the winning team of a finalised match, [] when nobody won.
static func winners_of(info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var res: Dictionary = info.get("result", {}) as Dictionary
	if res.is_empty() or int(res.get("reason", 0)) != NetProtocol.MatchEndReason.SIM_DECIDED:
		return out
	var wt: int = int(res.get("winner_team", -1))
	if wt < 0:
		return out
	for pv: Variant in info.get("players", []) as Array:
		var p: Dictionary = pv as Dictionary
		if int(p.get("team", -1)) == wt:
			out.append(p)
	return out


## "Commander, Bot 1, Bot 2" (winners starred).
static func players_text(info: Dictionary) -> String:
	var win: PackedInt32Array = PackedInt32Array()
	for w: Dictionary in winners_of(info):
		win.append(int(w["pid"]))
	var names: PackedStringArray = PackedStringArray()
	for pv: Variant in info.get("players", []) as Array:
		var p: Dictionary = pv as Dictionary
		names.append(("* " if win.has(int(p["pid"])) else "") + str(p.get("name", "")))
	return ", ".join(names)


static func result_text(info: Dictionary) -> String:
	if not bool(info.get("valid", false)):
		return "Unreadable"
	var res: Dictionary = info.get("result", {}) as Dictionary
	if res.is_empty():
		return "Truncated" if str(info.get("kind", "")) == "crash" or bool(info.get("truncated", false)) else "Unfinished"
	match int(res.get("reason", 0)):
		NetProtocol.MatchEndReason.ABANDONED:
			return "Left early"
		NetProtocol.MatchEndReason.DESYNC:
			return "Out of sync"
		NetProtocol.MatchEndReason.HOST_CLOSED:
			return "Host closed"
		NetProtocol.MatchEndReason.NO_HUMANS_LEFT:
			return "Ended"
	var w: Array[Dictionary] = winners_of(info)
	if w.is_empty():
		return "Draw"
	var first: String = str(w[0].get("name", ""))
	return "Won: " + first + (" +%d" % (w.size() - 1) if w.size() > 1 else "")


## BUILD_OK / BUILD_BALANCE (plays, balance changed) / BUILD_OLD (refused by the version gate) / BUILD_BROKEN (unreadable).
static func build_state(info: Dictionary) -> int:
	if not bool(info.get("valid", false)):
		return BUILD_BROKEN
	if not bool(info.get("compatible", false)):
		return BUILD_OLD
	if str(info.get("warning", "")) != "":
		return BUILD_BALANCE
	return BUILD_OK


static func build_text(info: Dictionary) -> String:
	match build_state(info):
		BUILD_OLD:
			return "OLD BUILD"
		BUILD_BALANCE:
			return "BALANCE"
		BUILD_BROKEN:
			return "BROKEN"
	return "OK"


static func build_color(state: int) -> Color:
	match state:
		BUILD_OLD, BUILD_BROKEN:
			return UiPalette.semantic(&"danger")
		BUILD_BALANCE:
			return UiPalette.semantic(&"warn")
	return UiPalette.semantic(&"ok")


## Can the replay be watched at all (valid file, version gate passes).
static func playable(info: Dictionary) -> bool:
	return bool(info.get("valid", false)) and bool(info.get("compatible", false))


## Why it cannot be watched ("" when it can).
static func refusal(info: Dictionary) -> String:
	if not bool(info.get("valid", false)):
		return "This file is not a readable replay: %s" % str(info.get("error", "unknown error"))
	if not bool(info.get("compatible", false)):
		return str(info.get("incompatible_reason", "This replay was recorded with a different build."))
	return ""


## The dots (player colours) of the PLAYERS cell.
static func pips_of(info: Dictionary) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	for pv: Variant in info.get("players", []) as Array:
		out.append(UiPalette.team(int((pv as Dictionary).get("color", 0))))
	return out


## Cells of one row (UiListRow shape).
static func cells_of(info: Dictionary) -> Array[Dictionary]:
	var state: int = build_state(info)
	var dim: Color = UiPalette.TEXT_DIM
	var cells: Array[Dictionary] = []
	cells.append({"text": date_text(when_of(info)), "mono": true})
	var map: Dictionary = info.get("map", {}) as Dictionary
	var kind: String = str(info.get("kind", "manual"))
	if kind == "manual" and bool(info.get("valid", false)):
		cells.append({"text": title_of(info)})
	elif not bool(info.get("valid", false)):
		cells.append({"text": title_of(info)})
	else:
		cells.append({"text": map_text(map), "tag": tag_of(info), "tag_color": UiPalette.semantic(&"warn") if kind == "crash" else UiPalette.TEXT_DIM})
	cells.append({"text": players_text(info), "dots": pips_of(info)})
	cells.append({"text": result_text(info), "color": dim})
	cells.append({"text": length_text(int(info.get("duration_ticks", 0))) if bool(info.get("valid", false)) else "-", "mono": true, "align": HORIZONTAL_ALIGNMENT_RIGHT})
	cells.append({"text": build_text(info), "color": build_color(state)})
	return cells


## Text filter match: file / display name, map name, player names, roster ids.
static func matches_text(info: Dictionary, needle: String) -> bool:
	var n: String = needle.strip_edges().to_lower()
	if n == "":
		return true
	var hay: PackedStringArray = PackedStringArray([str(info.get("name", "")), title_of(info), map_name(info.get("map", {}) as Dictionary)])
	for pv: Variant in info.get("players", []) as Array:
		hay.append(str((pv as Dictionary).get("name", "")))
		hay.append(str((pv as Dictionary).get("roster", "")))
	for h: String in hay:
		if h.to_lower().contains(n):
			return true
	return false


## Sort key of a column (ints sort numerically, strings case-insensitively).
static func sort_key(info: Dictionary, col: int) -> Variant:
	match col:
		Col.DATE:
			return when_of(info)
		Col.MAP:
			return map_name(info.get("map", {}) as Dictionary).to_lower()
		Col.PLAYERS:
			return (info.get("players", []) as Array).size()
		Col.RESULT:
			return result_text(info).to_lower()
		Col.LENGTH:
			return int(info.get("duration_ticks", 0))
		Col.BUILD:
			return build_state(info)
	return 0


## Rows of the list: `[{key (path), info, cells, dimmed, tooltip, playable}]` after the filters (`text`, `hide_autosaves`,
## `hide_incompatible`) and the sort (default: newest first).
static func build_rows(infos: Array[Dictionary], filters: Dictionary = {}, sort_col: int = Col.DATE, descending: bool = true) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for info: Dictionary in infos:
		if bool(filters.get("hide_autosaves", false)) and str(info.get("kind", "manual")) != "manual":
			continue
		if bool(filters.get("hide_incompatible", false)) and not playable(info):
			continue
		if not matches_text(info, str(filters.get("text", ""))):
			continue
		var tip: String = refusal(info)
		if tip == "" and str(info.get("warning", "")) != "":
			tip = str(info["warning"])
		rows.append({"key": str(info.get("path", "")), "info": info, "cells": cells_of(info), "dimmed": not playable(info), "tooltip": tip,
			"playable": playable(info)})
	var col: int = sort_col
	var desc: bool = descending
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = sort_key(a["info"] as Dictionary, col)
		var kb: Variant = sort_key(b["info"] as Dictionary, col)
		if ka == kb:
			return str(a["key"]) < str(b["key"])
		return ka > kb if desc else ka < kb)
	return rows


## The detail lines of the selected replay: `[[caption, value], ...]`.
static func detail_lines(info: Dictionary) -> Array[Array]:
	var out: Array[Array] = []
	if info.is_empty():
		return out
	var map: Dictionary = info.get("map", {}) as Dictionary
	out.append(["REPLAY", title_of(info)])
	out.append(["MAP", map_name(map)])
	out.append(["FAMILY", UiMapNames.family_name(int(map.get("family", 0)))])
	out.append(["SEED", "0x%s  //  %d x %d" % [UiFormatLite.hash8(int(map.get("seed", 0))), int(map.get("size", 0)), int(map.get("size", 0))]])
	out.append(["LENGTH", length_text(int(info.get("duration_ticks", 0)))])
	out.append(["RESULT", result_text(info)])
	out.append(["DATE", date_text(when_of(info))])
	out.append(["BUILD", "%s%s" % [build_text(info), "  (v%s)" % str(info.get("game_version", "")) if str(info.get("game_version", "")) != "" else ""]])
	out.append(["SIZE", size_text(int(info.get("size", 0)))])
	out.append(["RECORDING", "complete" if bool(info.get("finalized", false)) else "cut short (truncated)"])
	return out


## "napc" of "roster.napc.canada".
static func faction_code(roster_id: String) -> String:
	var p: PackedStringArray = roster_id.split(".")
	return p[1] if p.size() >= 2 else ""


## "napc.canada" of a subfaction roster, "" for a vanilla one.
static func sub_key(roster_id: String) -> String:
	var p: PackedStringArray = roster_id.split(".")
	return "%s.%s" % [p[1], p[2]] if p.size() >= 3 and p[2] != "vanilla" else ""


## "North American Pact  //  Canada" (the roster id when the data does not know it).
static func roster_line(data: GameData, roster_id: String) -> String:
	if data == null:
		return roster_id
	var idx: int = data.roster_idx(roster_id)
	if idx < 0:
		return roster_id
	var r: DefRoster = data.rosters[idx]
	var fac: String = data.factions[r.faction].ui_name if r.faction >= 0 and r.faction < data.factions.size() else ""
	return fac if r.is_vanilla else "%s  //  %s" % [fac, r.ui_title]


## The rules of the match as short chips: "7,500 credits", "Fog of war", "Superweapons", "Unit cap 150" ...
static func rule_chips(info: Dictionary) -> PackedStringArray:
	var r: Dictionary = info.get("rules", {}) as Dictionary
	var out: PackedStringArray = PackedStringArray()
	if r.is_empty():
		return out
	out.append("%s credits" % UiFormatLite.credits(int(r.get("start_credits", 0))))
	out.append("Fog of war" if bool(r.get("fog", false)) else "No fog")
	out.append("Superweapons" if bool(r.get("superweapons", false)) else "No superweapons")
	out.append("Unit cap %d" % int(r.get("unit_cap", 0)))
	if bool(r.get("shared_vision", false)):
		out.append("Shared vision")
	if bool(r.get("veterancy", false)):
		out.append("Veterancy")
	return out
