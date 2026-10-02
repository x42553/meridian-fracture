class_name AppShutdown
extends RefCounted
## Orderly quit helper: drops every process-wide cache that owns a GPU / Resource object (static vars are freed by the engine only AFTER the
## RenderingServer is gone, which prints `RenderingServer::get_singleton() is null` / `RID allocations ... were leaked at exit`).
## Called by `AppState.quit_game` and the test boot just before `SceneTree.quit`; the caches rebuild themselves on demand, so it is always safe.


## True once an orderly quit started (`prepare_quit`): loops and coroutines that wait on background work stop waiting.
static var quitting: bool = false


## First phase of an orderly quit (idempotent, never disposes anything): sets `quitting` so the autostart / test coroutines and the loading build stop
## awaiting frames, and aborts a view build that is still running. The caller then gives the engine a few frames (`AppAudio.release_for_quit`)
## and quits; `prepare_quit` runs from `AppState._exit_tree`.
static func begin_quit(tree: SceneTree) -> void:
	quitting = true
	if tree == null:
		return
	var state: Node = tree.root.get_node_or_null("AppState")
	var mc: Variant = state.get("match_ctx") if state != null else null
	if mc is AppMatchContext and (mc as AppMatchContext).job != null:
		var st: AppViewStage = (mc as AppMatchContext).job.stage
		if st != null and is_instance_valid(st) and not st.built:
			st.abort()


## Ends everything that owns a thread, a task, a socket or a file handle, BEFORE the engine tears the tree down: the running match context
## (map-generation thread, background model builds, session, replay writer, AI) and a LAN session (a host tells its guests it left). Idempotent;
## safe in every phase (splash, menus, lobby, loading, match, end, replays). Task / thread owners also cancel themselves in `_exit_tree`
## (ViewWorld, ViewIconBake, MapGenJob), this is the explicit hand-over that `AppState` calls on every quit path.
static func prepare_quit(tree: SceneTree) -> void:
	quitting = true
	if tree == null:
		return
	var state: Node = tree.root.get_node_or_null("AppState")
	if state != null:
		state.call("unbind_session")
	join_workers()
	var scenes: Node = tree.root.get_node_or_null("AppScenes")
	if scenes != null:
		scenes.call("release_for_quit")  # screens first: they still read the context while they exit
	if tree.root.get_node_or_null("AppNet") != null:
		AppLan.leave()  # a LAN guest sends LEAVE / a host closes the game, then the driven context is disposed
	if state != null:
		var mc: Variant = state.get("match_ctx")
		if mc is AppMatchContext:
			(mc as AppMatchContext).dispose()
		state.set("match_ctx", null)


## Cancels and joins every background thread / task of the process (map generation jobs, model builds): nothing may still be
## executing GDScript when the engine tears the script language down, whoever owns it and whether or not the owner leaked. Idempotent.
static func join_workers() -> void:
	MapGenJob.cancel_all()
	ViewModelBuilder.cancel_all()  # (ViewIconBake's PNG writers are joined by `release_statics`)


static func release_statics() -> void:
	UiCursors.release_all()
	FxAssets.release_statics()
	UiVignette.release_statics()
	UiCooldownSweep.release_statics()
	UiFonts.release_statics()
	UiStyleBox.clear_cache()
	ViewFloatText.release_statics()
	UiThemeService.release_statics()
	UiSkinSet.release_statics()
	UiViewPortWorld.release_statics()
	UiScreenMissionBriefing.release_statics()  # the baked map previews are GPU textures
	AppMission.release_statics()
	ViewIconBake.release_shared()
