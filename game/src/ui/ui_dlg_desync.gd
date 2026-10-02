class_name UiDlgDesync
extends UiDialog
## The desync dialog (ui.md 5.16.2): the game states of the players diverged (`desync_detected(report)`). It tells when (mm:ss and
## tick), that a diagnostic package was written to `user://desync`, and offers Show folder (`OS.shell_open`, the one sanctioned use),
## Copy report and Leave. The world stays readable and the HUD frozen behind it. `closed(1)` = Leave, `closed(0)` = Esc.

const RESULT_LEAVE: int = 1

var report: Dictionary = {}
## The session whose recording "Save replay" keeps (set by `UiMatchOverlays`; the button is disabled without one).
var session: NetSession = null
var _save_button: Button = null


func _init(p_report: Dictionary = {}) -> void:
	super._init("Desync detected", 520)
	report = p_report
	dismiss_on_escape = true
	var tick: int = int(report.get("tick", 0))
	add_text("The game states of the players no longer match at %s (tick %d). The match cannot continue." % [
		UiFormatLite.clock(tick * SimConfig.TICK_MS / 1000), tick])
	var kind: String = str(report.get("kind", ""))
	if kind != "":
		add_text("Kind: %s. A diagnostic package was saved; please attach it when reporting the problem." % kind, &"DimLabel")
	var msg: String = str(report.get("message", ""))
	if msg != "":
		add_text(msg, &"DimLabel")
	var folder: Button = add_button("Show folder", 10)
	folder.pressed.disconnect(close.bind(10))
	folder.pressed.connect(show_folder)
	var copy: Button = add_button("Copy report", 11)
	copy.pressed.disconnect(close.bind(11))
	copy.pressed.connect(copy_report)
	_save_button = add_button("Save replay", 12)
	_save_button.pressed.disconnect(close.bind(12))
	_save_button.pressed.connect(save_replay)
	_save_button.tooltip_text = "Keep the recording of this match; watch it later under Replays."
	add_button("Leave", RESULT_LEAVE, &"primary")


## Opens `user://desync` in the OS file browser.
func show_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://desync"))


## The report as JSON on the clipboard.
func copy_report() -> void:
	DisplayServer.clipboard_set(JSON.stringify(report, "  "))


## Asks for a name and keeps the recording of the session next to the automatic replays.
func save_replay() -> void:
	if session == null:
		return
	var s: NetSession = session
	UiDlgReplayName.ask("Save replay", AppReplay.default_name(s.config()), "Save", func(chosen: String) -> void:
		var path: String = AppReplay.save_session(s, chosen)
		if path != "" and _save_button != null:
			_save_button.text = "Replay saved"
			_save_button.disabled = true)
