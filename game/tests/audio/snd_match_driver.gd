class_name SndMatchDriver
extends RefCounted
## Drives a real SimWorld (SimMatchKit: real GameData, generated map, two armies that fight) through the real audio stack
## (SndManager on the Dummy audio driver): the app's per-frame sequence of audio spec 3.2 without a renderer. Used by
## test_snd_match_flow and tests/scenarios/snd_match.gd.

const NAPC_ARMY: PackedStringArray = ["unit.napc.rifle_squad", "unit.napc.rifle_squad", "unit.napc.javelin_team", "unit.napc.bastion_heavy_tank", "unit.napc.bastion_heavy_tank"]
const NEC_ARMY: PackedStringArray = ["unit.nec.jager_squad", "unit.nec.jager_squad", "unit.nec.leopard_tank", "unit.nec.marte_heavy_mbt", "unit.nec.archer_spg"]


## Returns {ok, error, ticks, starts, culls, voices_per_s, max_voices_3d, max_loops, lines, music_states, counters, ms_audio_avg, ms_audio_max}.
## `o`: ticks (600), seed (3), bots (false), fight (true), family (0), quality (medium), music (true), fog (false).
static func run(o: Dictionary = {}) -> Dictionary:  # coroutine
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var out: Dictionary = {"ok": false, "error": ""}
	var m: Dictionary = SimMatchKit.make_match({"seed": int(o.get("seed", 3)), "bots": bool(o.get("bots", false)), "family": int(o.get("family", 0)),
		"rules": {"fog": bool(o.get("fog", false)), "victory": 1}})
	var w: SimWorld = m["world"]
	if w == null:
		out["error"] = "no world"
		return out
	if bool(o.get("fight", true)):
		_spawn_armies(w)
	var root3d: Node3D = Node3D.new()
	var cam: Camera3D = Camera3D.new()
	root3d.add_child(cam)
	tree.root.add_child(root3d)
	cam.current = true
	var snd: SndManager = SndManager.new()
	snd.name = "SndTest"
	tree.root.add_child(snd)
	await tree.process_frame
	snd.set_process(false)
	var ms: int = 100000
	snd.set_time_override(ms)
	if not snd.setup():
		out["error"] = "Snd.setup failed"
		return out
	var s: SndSettings = SndSettings.new()
	s.quality = int(o.get("quality", SndSettings.Q_MEDIUM))
	if not bool(o.get("music", true)):
		s.music_mode = SndSettings.MUSIC_OFF
	snd.apply_settings(s)
	if not snd.attach_world(root3d):
		out["error"] = "attach_world failed"
		return out
	var cfg: SndMatchConfig = SndMatchConfig.from_world(w, 0)
	snd.begin_match(cfg)
	var waited: int = 0
	while not snd.is_match_ready() and waited < 600:
		ms += 16
		snd.set_time_override(ms)
		snd._process(0.016)
		await tree.process_frame
		waited += 1
	if not snd.is_match_ready():
		out["error"] = "match audio never became ready"
		return out
	var ticks: int = int(o.get("ticks", 600))
	var focus: Vector3 = Vector3.ZERO
	var focus_set: bool = false
	var frame_dt: float = 1.0 / 60.0
	var starts0: int = snd.pool().stats.starts
	var max3d: int = 0
	var max2d: int = 0
	var max_loops: int = 0
	var audio_us: int = 0
	var audio_worst: int = 0
	var worst_frame: int = 0
	var frames: int = 0
	var music_states: Dictionary = {}
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.ERROR:
			errors.append("%s: %s" % [tag, msg])
	var sim_ticks: int = 0
	var carry: float = 0.0
	while sim_ticks < ticks and w.match_state == SimWorld.MATCH_RUNNING:
		carry += 20.0 * frame_dt
		while carry >= 1.0 and sim_ticks < ticks:
			for b: SimBot in m["bots"]:
				b.think(w)
			w.step()
			sim_ticks += 1
			carry -= 1.0
		if not focus_set and not w.units_of(0).is_empty():
			focus = SndUnits.to_world(w.units_of(0)[0].x, w.units_of(0)[0].y, 0.0)
			focus_set = true
		if bool(o.get("realtime", false)):
			OS.delay_msec(12)  # the audio thread mixes in real time: music transitions need real seconds to complete
			ms = Time.get_ticks_msec()
		else:
			ms += 17
		snd.set_time_override(ms)
		var batch: PackedInt32Array = w.events.take()
		var t0: int = Time.get_ticks_usec()
		if bool(o.get("heat", false)) and sim_ticks > 60:
			snd.meter.add(3.0, 0.0, true)  # a sustained battle: the music must go COMBAT and stay there
		snd.set_camera(focus, Basis.IDENTITY, 55.0)
		snd.on_events(w, batch, carry)
		snd.on_frame(w, carry, frame_dt)
		snd._process(frame_dt)
		var dt_us: int = Time.get_ticks_usec() - t0
		audio_us += dt_us
		if dt_us > audio_worst:
			audio_worst = dt_us
			worst_frame = frames
		frames += 1
		max3d = maxi(max3d, snd.pool().active_3d())
		max2d = maxi(max2d, snd.pool().active_2d())
		max_loops = maxi(max_loops, snd.loops.active_loops())
		music_states[snd.music().current_state()] = true
		if frames % 8 == 0 or bool(o.get("realtime", false)):
			await tree.process_frame  # let the engine mix and process node deletions
	Log.sink = old_sink
	var game_s: float = float(sim_ticks) / 20.0
	var starts: int = snd.pool().stats.starts - starts0
	out = {
		"ok": errors.is_empty(), "error": "" if errors.is_empty() else str(errors), "ticks": sim_ticks, "game_s": game_s, "starts": starts,
		"culls": snd.pool().stats.culls, "voices_per_s": float(starts) / maxf(game_s, 0.001), "max_voices_3d": max3d, "max_voices_2d": max2d,
		"max_loops": max_loops, "counters": snd.pool().stats.counters.duplicate(), "bridge": snd.bridge.stats.counters.duplicate() if snd.bridge != null else {},
		"ms_audio_avg": float(audio_us) / 1000.0 / float(maxi(frames, 1)), "ms_audio_max": float(audio_worst) / 1000.0, "worst_frame": worst_frame, "frames": frames,
		"music_states": music_states.keys(), "heat": snd.meter.heat, "combat_events": SndMatchDriver.count_combat(w), "driver": AudioServer.get_driver_name(),
	}
	snd.end_match(SndMatchConfig.RESULT_ABORT)
	snd.shutdown()
	snd.index.release_banks(PackedStringArray())
	snd.free()
	root3d.free()
	return out


static func count_combat(w: SimWorld) -> int:
	return w.combat.counters[SimCombatSystem.CNT_IMPACTS] if w.combat != null else 0


## Two armies close enough to see each other, right next to player 0's start.
static func _spawn_armies(w: SimWorld) -> void:
	var data: GameData = w.data
	var base_x: int = 0
	var base_y: int = 0
	var s0: Array[SimEntity] = w.structures_of(0)
	if not s0.is_empty():
		base_x = s0[0].x
		base_y = s0[0].y
	else:
		base_x = w.map.w * 512
		base_y = w.map.h * 512
	var cx: int = base_x + 16 * 1024
	var cy: int = base_y + 6 * 1024
	for i: int in NAPC_ARMY.size():
		var di: int = data.unit_idx(NAPC_ARMY[i])
		if di >= 0:
			w.spawn_unit(di, 0, cx - 4 * 1024, cy + i * 1400, 0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
	for i: int in NEC_ARMY.size():
		var dj: int = data.unit_idx(NEC_ARMY[i])
		if dj >= 0 and w.players.size() > 1:
			w.spawn_unit(dj, 1, cx + 5 * 1024, cy + i * 1400, 0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
