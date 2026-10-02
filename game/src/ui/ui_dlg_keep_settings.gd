class_name UiDlgKeepSettings
extends UiDialog
## "Keep these settings?" (ui.md 5.18.3): opened after a window mode, resolution or vsync change. A 15-second countdown answers
## itself with Revert, so a wrong resolution can never lock a player out (QA A-12 allows no prompt shorter than 5 s).
## Result codes: 1 keep, 0 revert (button, Escape or the countdown).

const KEEP: int = 1
const REVERT: int = 0
const SECONDS: float = 15.0

var seconds_left: float = SECONDS
var _note: Label = null


func _init(summary: String = "", seconds: float = SECONDS) -> void:
	super._init("Keep these settings?", 480)
	seconds_left = seconds
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_text(summary if not summary.is_empty() else "The display settings changed.")
	_note = add_text("", &"DimLabel")
	add_button("Revert", REVERT)
	add_button("Keep changes", KEEP, &"primary")
	_update_note()
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


## Advances the countdown; at zero the dialog closes with Revert. Public so tests drive time.
func tick(delta: float) -> void:
	if is_closed():
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	_update_note()
	if seconds_left <= 0.0:
		close(REVERT)


func _update_note() -> void:
	_note.text = "Reverting automatically in %d s." % int(ceil(seconds_left))
