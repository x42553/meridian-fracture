class_name UiDlgJoinRejected
extends UiDialog
## Why a join or a launch failed (ui.md 5.15 "Join flow", net.md 5.3.1 / 5.13). Built from `NetSession.join_rejected(reason, info)`:
## the message of `NetProtocol.describe_reject`, and for a version mismatch a small table naming the failing layer (protocol,
## simulation or game data) with the host's and the local values, plus the per-file data differences the host sent. A wrong
## password re-opens as a password prompt (`password()` after `closed(RESULT_RETRY)`). `for_abort` builds the same dialog for a launch
## that fell apart (`NetSession.launch_aborted`: map or initial-state mismatch, a player left or timed out while loading).
## `closed(1)` = OK / Back, `closed(2)` = Retry with the entered password, `closed(0)` = Esc.

const RESULT_OK: int = 1
const RESULT_RETRY: int = 2

var reason: int = 0
var info: Dictionary = {}
var _password: LineEdit = null


func _init(p_reason: int = 0, p_info: Dictionary = {}, address: String = "") -> void:
	var content: Dictionary = describe(p_reason, p_info, address)
	super._init(str(content["title"]), 560)
	reason = p_reason
	info = p_info
	add_text(str(content["body"]))
	var rows: Array = content["rows"] as Array
	if not rows.is_empty():
		set_content(_table(rows))
	var extra: PackedStringArray = content["extra"] as PackedStringArray
	if not extra.is_empty():
		add_text("\n".join(extra), &"DimLabel")
	if p_reason == NetProtocol.RejectReason.BAD_PASSWORD:
		_password = LineEdit.new()
		_password.secret = true
		_password.placeholder_text = "Password"
		_password.max_length = 32
		_password.custom_minimum_size = Vector2(0.0, 38.0)
		_password.text_submitted.connect(func(_t: String) -> void: close(RESULT_RETRY))
		set_content(_password)
		add_button("Cancel", 0)
		add_button("Try again", RESULT_RETRY, &"primary")
	else:
		add_button("Back", RESULT_OK, &"primary")


func default_focus() -> Control:
	return _password if _password != null else super.default_focus()


## The password typed into a BAD_PASSWORD prompt ("" for the other dialogs).
func password() -> String:
	return _password.text if _password != null else ""


## Title, body, the comparison rows `[[label, host value, local value], ...]` and extra lines for a join rejection. Pure and tested.
static func describe(p_reason: int, p_info: Dictionary, address: String = "") -> Dictionary:
	var text: String = str(p_info.get("text", ""))
	if text.is_empty():
		text = NetProtocol.describe_reject(p_reason, p_info)
	var title: String = "Could not join"
	var rows: Array = []
	var extra: PackedStringArray = PackedStringArray()
	match p_reason:
		NetProtocol.RejectReason.PROTO_MISMATCH:
			title = "Different game version"
			rows = [["Game version", str(p_info.get("host_game_version", p_info.get("host_version", ""))), str(p_info.get("local_game_version", p_info.get("my_version", "")))],
				["Network protocol", str(int(p_info.get("host_proto_version", p_info.get("host_proto", 0)))), str(int(p_info.get("local_proto_version", p_info.get("my_proto", 0))))]]
		NetProtocol.RejectReason.SIM_MISMATCH:
			title = "Different game version"
			rows = [["Game version", str(p_info.get("host_game_version", p_info.get("host_version", ""))), str(p_info.get("local_game_version", p_info.get("my_version", "")))],
				["Simulation", str(int(p_info.get("host_sim_version", p_info.get("host_sim", 0)))), str(int(p_info.get("local_sim_version", p_info.get("my_sim", 0))))]]
		NetProtocol.RejectReason.DATA_MISMATCH:
			title = "Different game data"
			rows = [["Game version", str(p_info.get("host_game_version", p_info.get("host_version", ""))), str(p_info.get("local_game_version", p_info.get("my_version", "")))],
				["Game data", UiFormatLite.hash8(int(p_info.get("host_data_hash", 0))), UiFormatLite.hash8(int(p_info.get("local_data_hash", p_info.get("my_data_hash", 0))))]]
			var diff: Variant = p_info.get("diff_lines", PackedStringArray())
			if diff is PackedStringArray:
				for i: int in mini((diff as PackedStringArray).size(), 6):
					extra.append((diff as PackedStringArray)[i])
				if (diff as PackedStringArray).size() > 6:
					extra.append("... and %d more" % ((diff as PackedStringArray).size() - 6))
		NetProtocol.RejectReason.LOBBY_FULL:
			title = "Game is full"
		NetProtocol.RejectReason.IN_PROGRESS:
			title = "Match in progress"
		NetProtocol.RejectReason.BANNED:
			title = "Removed from this game"
		NetProtocol.RejectReason.BAD_PASSWORD:
			title = "Password required"
			text = "This game is protected. Enter the password%s." % [" of " + address if address != "" else ""]
		NetProtocol.RejectReason.HOST_BUSY:
			title = "Host is starting the game"
		NetProtocol.RejectReason.SPECTATORS_CLOSED:
			title = "No spectators"
	return {"title": title, "body": text, "rows": rows, "extra": extra}


## The dialog for a failed launch (`NetSession.launch_aborted(reason, detail)`, `NetProtocol.AbortReason`).
static func for_abort(abort_reason: int, detail: String) -> UiDialog:
	var t: Dictionary = abort_text(abort_reason, detail)
	var d: UiDialog = UiDialog.new(str(t["title"]), 520)
	d.add_text(str(t["body"]))
	d.add_button("Back to the lobby", RESULT_OK, &"primary")
	return d


## {title, body} of a launch abort: the map / initial-state mismatch texts of net.md 5.13 name the version problem, the others say
## who left or failed.
static func abort_text(abort_reason: int, detail: String) -> Dictionary:
	match abort_reason:
		NetProtocol.AbortReason.MAP_MISMATCH:
			return {"title": "Different map generated", "body": "%s\nBoth computers must run the same version. Details were written to the log." % _first_line(detail, "A player generated a different map than the host.")}
		NetProtocol.AbortReason.INIT_MISMATCH:
			return {"title": "Different starting state", "body": "%s\nBoth computers must run the same version. Details were written to the log." % _first_line(detail, "A player built a different starting state than the host.")}
		NetProtocol.AbortReason.CONFIG_INVALID:
			return {"title": "Match settings rejected", "body": _first_line(detail, "The match settings were corrupted in transit.")}
		NetProtocol.AbortReason.LOAD_TIMEOUT:
			return {"title": "Loading took too long", "body": _first_line(detail, "A player did not finish loading in time.")}
		NetProtocol.AbortReason.LOAD_FAILED:
			return {"title": "A player could not load the match", "body": _first_line(detail, "Loading failed on one computer.")}
		NetProtocol.AbortReason.HUMAN_LEFT:
			return {"title": "A player left", "body": _first_line(detail, "A player left while the game was loading.")}
		NetProtocol.AbortReason.HOST_CANCEL:
			return {"title": "Start cancelled", "body": _first_line(detail, "The host cancelled the start.")}
	return {"title": "The game could not start", "body": _first_line(detail, "The launch was aborted.")}


static func _first_line(detail: String, fallback: String) -> String:
	return detail.strip_edges() if not detail.strip_edges().is_empty() else fallback


static func _table(rows: Array) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	for h: String in ["", "HOST", "YOU"]:
		grid.add_child(UiScreenKit.label(h, &"CaptionLabel"))
	for r: Variant in rows:
		var row: Array = r as Array
		grid.add_child(UiScreenKit.label(str(row[0]), &"DimLabel"))
		var host_v: Label = UiScreenKit.label(str(row[1]), &"NumLabel")
		var mine_v: Label = UiScreenKit.label(str(row[2]), &"NumLabel")
		if str(row[1]) != str(row[2]):
			mine_v.theme_type_variation = &"DangerLabel"
		grid.add_child(host_v)
		grid.add_child(mine_v)
	return grid
