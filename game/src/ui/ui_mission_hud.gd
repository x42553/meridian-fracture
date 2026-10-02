class_name UiMissionHud
extends Control
## The in-mission layer of the HUD (MIS2): objectives panel (top left under the power dock), timer chips (top right of the playfield),
## the caption feed (top centre under the ribbons), plus the reactions to the mission's events: a ribbon and a cue for a new, completed
## or failed objective, the announcer line of a message (audio port), the mission's music state, and the camera hint (UI-only focus:
## the screen moves the view and marks the ground, the layer pings the minimap). It is a child of `UiHud`, full rect, mouse-transparent, and is fed by
## `UiScreenGame`: `on_events(records)` with the frame's event batch, `on_frame(delta)` once per frame. State comes from
## `UiSimPort.mission_state` at 10 Hz (authoritative; a replay seek re-syncs by itself), texts from the `DefMission`.
## Presentation only: it never mutates the sim.

## The view should focus on this sim point (sub-cell units) for `ticks` display ticks.
signal camera_hint(sim_x: int, sim_y: int, ticks: int)

const SYNC_S: float = 0.1
## Events older than this (sim ticks) are not announced: a replay seek or a long pause replays a backlog.
const STALE_TICKS: int = 100
## Objective events of the first ticks are the mission's initial state: the panel shows them, no ribbon announces them.
const START_TICKS: int = 2
const LAYOUT_TOP_DOCK: float = 120.0
const LAYOUT_TOP_PLAIN: float = 54.0

var model: UiMissionModel = null
var objectives: UiObjectivesPanel = null
var messages: UiMissionMessage = null
var timers: UiMissionTimers = null
var observer: bool = false
## The last camera hint ((-1, -1) = none yet) and how often the HUD forwarded one.
var last_hint: Vector2i = Vector2i(-1, -1)
var hints_sent: int = 0
var announcer_played: int = 0
var ribbons_posted: int = 0

var _hud: UiHud = null
var _sim: UiSimPort = null
var _audio: UiAudioPort = null
var _snap: PackedInt32Array = PackedInt32Array()
var _acc: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


## Builds the layer inside `hud` for `def`. `sim` is the match's port, `audio` its audio port (may be a null adapter).
func setup(hud: UiHud, sim: UiSimPort, audio: UiAudioPort, def: DefMission, is_observer: bool) -> void:
	_hud = hud
	_sim = sim
	_audio = audio
	observer = is_observer
	model = UiMissionModel.new()
	model.setup(def)
	hud.add_child(self)
	UiLayerRoot.fill(self)
	objectives = UiObjectivesPanel.new()
	add_child(objectives)
	objectives.setup(model)
	objectives.hotkey_text = UiKeymap.instance().label(&"toggle_objectives")
	timers = UiMissionTimers.new()
	add_child(timers)
	messages = UiMissionMessage.new()
	add_child(messages)
	resized.connect(_layout)
	_sync()
	_layout()
	_layout.call_deferred()


# ---------------------------------------------------------------- frame

func on_frame(delta: float) -> void:
	_acc += delta
	if _acc >= SYNC_S:
		_acc = 0.0
		_sync()
	_layout()


## Reads the state now (also after objective events, so the flash starts in the same frame).
func sync_now() -> void:
	_sync()


func _sync() -> void:
	if _sim == null or model == null:
		return
	if not _sim.mission_state(_snap):
		return
	var changed: PackedInt32Array = model.sync(_snap, _sim.tick(), Time.get_ticks_msec())
	objectives.refresh(changed)
	timers.update(model.visible_timers())


func _layout() -> void:
	if objectives == null or _hud == null:
		return
	var play_w: float = maxf(size.x - float(UiMetrics.SIDEBAR_W), 0.0)
	var dock: UiPowerDock = _hud.power_dock()
	objectives.position = Vector2(12.0, LAYOUT_TOP_DOCK if dock != null and dock.visible else LAYOUT_TOP_PLAIN)
	timers.position = Vector2(maxf(play_w - timers.size.x - 14.0, 0.0), 14.0)
	var n: int = mini(_hud.ribbons().count(), UiMetrics.RIBBON_MAX) if _hud.ribbons() != null else 0
	var y: float = 14.0
	if n > 0:
		y = float(UiMetrics.RIBBON_TOP) + float(n) * (UiMetrics.RIBBON.y + float(UiMetrics.RIBBON_GAP)) + 6.0
	messages.position = Vector2(maxf((play_w - UiMissionMessage.PLATE_W) * 0.5, 0.0), y)


func toggle_objectives() -> void:
	if objectives != null:
		objectives.toggle()


# ---------------------------------------------------------------- events

func on_events(records: PackedInt32Array) -> void:
	if records.is_empty() or model == null:
		return
	var now_tick: int = _sim.tick() if _sim != null else 0
	for ev: Dictionary in UiMissionModel.decode(records):
		var stale: bool = now_tick - int(ev["tick"]) > STALE_TICKS
		match ev["type"]:
			&"objective":
				sync_now()
				if not stale and int(ev["tick"]) > START_TICKS:
					_objective_event(ev)
			&"message":
				if not stale:
					_message_event(ev)
			&"camera":
				if not stale and not observer:
					last_hint = Vector2i(int(ev["x"]), int(ev["y"]))
					hints_sent += 1
					_ping(int(ev["x"]), int(ev["y"]))
					camera_hint.emit(int(ev["x"]), int(ev["y"]), int(ev["ticks"]))
			&"music":
				if not stale and _audio != null and int(ev["state"]) >= 0 and int(ev["state"]) < DefMissionAction.MUSIC_NAMES.size():
					_audio.music_state(StringName(DefMissionAction.MUSIC_NAMES[int(ev["state"])]))
			&"timer":
				sync_now()


func _objective_event(ev: Dictionary) -> void:
	var idx: int = int(ev["idx"])
	if idx < 0 or model.def == null or idx >= model.def.objectives.size():
		return
	var state: int = int(ev["state"])
	var text: String = model.def.objectives[idx].ui_text
	var primary: bool = model.def.objectives[idx].kind == UiMissionModel.KIND_PRIMARY
	var ribbons: UiRibbonStack = _hud.ribbons() if _hud != null else null
	var rid: StringName = StringName("mission_obj_%d" % idx)
	match state:
		UiMissionModel.S_ACTIVE:
			if int(ev["prev"]) == UiMissionModel.S_HIDDEN:
				_ribbon(ribbons, rid, UiRibbon.Severity.INFO, "NEW OBJECTIVE" if primary else "NEW OPTIONAL OBJECTIVE", text, UiGlyphs.Glyph.RADAR)
				_cue(UiAudioPort.NOTIFY)
		UiMissionModel.S_COMPLETED:
			_ribbon(ribbons, rid, UiRibbon.Severity.OK, "OBJECTIVE COMPLETE", text, UiGlyphs.Glyph.CHECK)
			_cue(UiAudioPort.CONFIRM)
		UiMissionModel.S_FAILED:
			_ribbon(ribbons, rid, UiRibbon.Severity.DANGER, "OBJECTIVE FAILED", text, UiGlyphs.Glyph.WARNING)
			_cue(UiAudioPort.ERROR)


func _ribbon(rs: UiRibbonStack, rid: StringName, severity: int, title: String, subtitle: String, glyph: int) -> void:
	if rs == null:
		return
	rs.post(rid, severity, title, subtitle, glyph, -1.0, -1.0, "", 6.0)
	ribbons_posted += 1


func _message_event(ev: Dictionary) -> void:
	var m: Dictionary = model.message_of(int(ev["idx"]), int(ev["announcer"]))
	if m.is_empty():
		return
	messages.post(str(m["text"]), str(m["speaker"]))
	var line: String = str(m["announcer"])
	if line != "" and _audio != null:
		if _audio.announce(StringName(line)):
			announcer_played += 1


func _cue(id: StringName) -> void:
	if _audio != null:
		_audio.ui(id)


func _ping(sim_x: int, sim_y: int) -> void:
	if _hud == null or _hud.minimap() == null:
		return
	var cells: Vector2i = _hud.minimap().map_cells
	if cells.x <= 0 or cells.y <= 0:
		return
	_hud.minimap().add_ping(Vector2(float(sim_x) / float(cells.x * 1024), float(sim_y) / float(cells.y * 1024)), UiPalette.POWER, UiMinimap.PING_KIND_ALERT)
