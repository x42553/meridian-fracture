class_name AppMission
extends RefCounted
## Scripted-mission glue of the app (MIS2): difficulty (the AI levels of a mission's AI players), the mission -> LOCAL `NetSession`
## launch through `AppMatch.start_local` (one code path with skirmish and LAN: lockstep turns, AI runner, command log, replay
## recorder), campaign bookkeeping when the match ends, and the model of the result screen.
##
## Difficulty: a mission is authored at "Medium" (the AI levels in its JSON are what the designer tuned). The selector shifts every
## AI player's level by (difficulty - 1) and clamps to what the AI offers: Easy -1, Medium 0, Hard +1, Brutal +2. Scripted spawners
## (AI players that are switched off in the mission) are not affected by the shift's meaning, only by their level number.

const DIFFICULTY_NAMES: PackedStringArray = ["Easy", "Medium", "Hard", "Brutal"]
const DIFFICULTY_BLURBS: PackedStringArray = ["Relaxed opposition. For learning the mission.", "The mission as designed.",
	"A sharper, faster opponent.", "No mercy. Expect to lose a few times."]
const DEFAULT_DIFFICULTY: int = 1


static func difficulty_count() -> int:
	return DIFFICULTY_NAMES.size()


static func clamp_difficulty(d: int) -> int:
	return clampi(d, 0, DIFFICULTY_NAMES.size() - 1)


static func difficulty_name(d: int) -> String:
	return DIFFICULTY_NAMES[d] if d >= 0 and d < DIFFICULTY_NAMES.size() else "-"


## The level an AI player authored at `authored` plays at on `difficulty`.
static func ai_level_for(authored: int, difficulty: int) -> int:
	return clampi(authored + clamp_difficulty(difficulty) - DEFAULT_DIFFICULTY, 0, maxi(AiFactory.level_count() - 1, 0))


static func def_of(data: GameData, mission_id: String) -> DefMission:
	var t: DefMissionTable = DefMissionTable.of(data)
	return t.get_mission(mission_id) if t != null else null


## The UI-shape config of `mission_id` (`SimMissionSetup.build_config`) with the AI levels of `difficulty`; {} when unknown.
static func build_config(data: GameData, mission_id: String, difficulty: int = DEFAULT_DIFFICULTY) -> Dictionary:
	var cfg: Dictionary = SimMissionSetup.build_config(data, mission_id)
	if cfg.is_empty():
		return cfg
	for pv: Variant in cfg["players"] as Array:
		var p: Dictionary = pv as Dictionary
		if p.has("ai"):
			var ai: Dictionary = p["ai"] as Dictionary
			ai["level"] = ai_level_for(int(ai.get("level", 1)), difficulty)
	return cfg


## Starts the mission as a LOCAL match (see `AppMatch.start_local`; opts are passed on, `title` defaults to the mission title) and
## wires the campaign bookkeeping. `difficulty` < 0 = the one used last time on this mission (Medium the first time). null when the
## mission is unknown or the session cannot be created.
static func start(mission_id: String, difficulty: int = -1, opts: Dictionary = {}) -> AppMatchContext:
	var data: GameData = _app_data()
	if data == null:
		data = GameData.load_default()
	var def: DefMission = def_of(data, mission_id)
	if def == null:
		Log.error("app", "mission '%s' is unknown" % mission_id)
		return null
	var campaign: AppCampaign = _campaign()
	var d: int = clamp_difficulty(difficulty if difficulty >= 0 else campaign.last_difficulty(mission_id, DEFAULT_DIFFICULTY))
	var cfg: Dictionary = build_config(data, mission_id, d)
	var o: Dictionary = opts.duplicate()
	if not o.has("title"):
		o["title"] = def.ui_title
	var ctx: AppMatchContext = AppMatch.start_local(cfg, o)
	if ctx == null:
		return null
	ctx.mission_difficulty = d
	campaign.note_start(mission_id, d)
	var wctx: WeakRef = weakref(ctx)
	ctx.session.match_ended.connect(func(_result: Dictionary) -> void:
		var c: AppMatchContext = wctx.get_ref() as AppMatchContext
		if c != null:
			c.mission_outcome = finish(c))
	return ctx


## The match of `ctx` ended: records the result in the campaign (a win only when the mission script won for the local player's team;
## anything else, a surrender included, is a defeat) and saves. Returns `AppCampaign.record_result`'s dictionary plus `won`, `ticks`,
## `difficulty` and `id`.
static func finish(ctx: AppMatchContext) -> Dictionary:
	var id: String = ctx.mission_id()
	var w: SimWorld = ctx.world()
	var won: bool = false
	var ticks: int = 0
	if w != null:
		ticks = w.tick
		if w.mission != null:
			if w.mission.result == SimMissionConst.RES_WIN and ctx.local_pid >= 0 and w.team_of(w.mission.result_pid) == w.team_of(ctx.local_pid):
				won = true
			if w.mission.result != SimMissionConst.RES_NONE:
				ticks = w.mission.result_tick
	var out: Dictionary = _campaign().record_result(id, won, ticks, ctx.mission_difficulty)
	out["won"] = won
	out["ticks"] = ticks
	out["difficulty"] = ctx.mission_difficulty
	out["id"] = id
	return out


## The model of the mission result screen: {id, title, won, ticks, clock, difficulty, difficulty_name, outcome, objectives
## [{text, kind, state, word}], stats {...}, next_id, faction_code, summary}. `summary` = `AppMatch.result_summary` of the match.
static func result_model(ctx: AppMatchContext, summary: Dictionary) -> Dictionary:
	var data: GameData = ctx.data if ctx.data != null else _app_data()
	var id: String = ctx.mission_id()
	var def: DefMission = def_of(data, id)
	var outcome: Dictionary = ctx.mission_outcome
	if outcome.is_empty():
		outcome = finish(ctx)
		ctx.mission_outcome = outcome
	var mm: UiMissionModel = UiMissionModel.new()
	var objectives: Array = []
	if def != null:
		mm.setup(def)
		var snap: PackedInt32Array = PackedInt32Array()
		if ctx.sim != null and ctx.sim.mission_state(snap):
			mm.sync(snap, ctx.tick())
		var won_now: bool = bool(outcome.get("won", false))
		for r: Dictionary in mm.final_rows():
			if won_now and int(r["state"]) == UiMissionModel.S_ACTIVE and int(r["kind"]) == UiMissionModel.KIND_PRIMARY:
				r["state"] = UiMissionModel.S_COMPLETED  # winning the mission settles its still-open primaries (e.g. "keep the base alive")
			objectives.append({"text": r["text"], "kind": r["kind"], "state": r["state"], "word": UiMissionModel.state_word(int(r["state"]), true)})
	var stats: Dictionary = {}
	for rv: Variant in summary.get("players", []) as Array:
		var row: Dictionary = rv as Dictionary
		if bool(row.get("is_local", false)):
			stats = (row.get("stats", {}) as Dictionary).duplicate()
			stats["score"] = row.get("score", 0)
	var campaign: AppCampaign = _campaign()
	var model: UiCampaignModel = UiCampaignModel.build(data, campaign)
	var ticks: int = int(outcome.get("ticks", 0))
	var local_code: String = ""
	var node: UiCampaignModel.Entry = model.entry(id)
	if node != null:
		local_code = node.faction_code
	return {"id": id, "title": def.ui_title if def != null else id, "won": bool(outcome.get("won", false)), "ticks": ticks,
		"clock": UiFormatLite.clock(ticks * SimConfig.TICK_MS / 1000), "difficulty": ctx.mission_difficulty,
		"difficulty_name": difficulty_name(ctx.mission_difficulty), "outcome": outcome, "objectives": objectives, "stats": stats,
		"next_id": model.next_after(id) if bool(outcome.get("won", false)) else "", "faction_code": local_code, "summary": summary,
		"best_ticks": campaign.best_ticks(id)}


## "mission=<id>" of `--autostart=mission=<id>` -> the id ("" for anything else).
static func id_of_autostart(autostart: String) -> String:
	return autostart.substr(8) if autostart.begins_with("mission=") else ""


static func _campaign() -> AppCampaign:
	var st: Node = _autoload("AppState")
	if st != null and st.get("profile") is AppProfile:
		return (st.get("profile") as AppProfile).campaign
	return _fallback


static var _fallback: AppCampaign = AppCampaign.new()


static func release_statics() -> void:
	_fallback = AppCampaign.new()


static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null


static func _app_data() -> GameData:
	var state: Node = _autoload("AppState")
	if state != null and state.get("data") is GameData:
		return state.get("data") as GameData
	return null
