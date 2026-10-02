class_name AiController
extends RefCounted
## One AI player's state (ai.md 3.2): owns the view, the knowledge base, the command builder, the RNG, the scheduler, the
## budget and telemetry. `step()` runs once per think:
##   view.begin_think -> (first call: bootstrap_from_world) -> budget.reset -> cmd.begin_think -> scheduler.run -> cmd.flush.
## Modules (economy, production, strategy, ops ...) are plugged into the scheduler slots with `register()`; the knowledge
## base upkeep (slot 1) and the event ingest (slot 0) are registered by default. Nothing here writes the world: the only
## effect of a think is the commands appended to `out`.

var cfg: AiConfig = null
var ctx: AiContext = null
var scheduler: AiScheduler = null
var budget: AiBudget = AiBudget.new()
var perf: AiPerf = AiPerf.new()
var ingest: AiEventIngest = AiEventIngest.new()
var booted: bool = false
var thinks: int = 0
var last_tick: int = -1
var last_cmds: int = 0
var last_wu: int = 0
var total_wu: int = 0
var total_ticks: int = 0
var wu_max_think: int = 0
var _modules: Array = []  ## registered modules in registration order (setup calls)


func _init(p_cfg: AiConfig, p_shared: AiSharedData, p_store: AiDataStore, p_telemetry: Callable = Callable()) -> void:
	cfg = p_cfg
	var store: AiDataStore = p_store.with_overrides(p_cfg.tuning_override)
	ctx = AiContext.new()
	ctx.cfg = p_cfg
	ctx.pid = p_cfg.pid
	ctx.store = store
	ctx.shared = p_shared
	ctx.diff = store.difficulty(p_cfg.level)
	ctx.view = AiWorldView.new(p_cfg.pid, ctx.diff.info_omniscient)
	ctx.telemetry = AiTelemetry.new(p_cfg.pid, p_telemetry)
	ctx.cmd = AiCommandBuilder.new(p_cfg.pid, ctx.diff, Callable(ctx.telemetry, "emit_cb"))
	ctx.rng = AiRng.new()
	ctx.rng.seed_from(p_cfg.seed)
	ctx.kb = AiKnowledge.new()
	perf.enabled = p_cfg.perf
	scheduler = AiScheduler.new(ctx.diff)
	scheduler.register(AiScheduler.Slot.INGEST, ingest)
	scheduler.register(AiScheduler.Slot.KB, ctx.kb)


## Plugs a module (setup(ctx) / step(ctx, budget) / state_hash()) into a scheduler slot.
func register(slot: int, module: Object) -> void:
	scheduler.register(slot, module)
	_modules.append(module)
	if booted and module.has_method("setup"):
		module.call("setup", ctx)


func is_ready() -> bool:
	return booted


## Derives phase / posture / wants / squads from the CURRENT state (also the entry for the takeover of a dropped human):
## roles and profiles, personality (draw order of ai.md 5.14.3), knowledge tables, presumed enemy HQs.
func bootstrap_from_world() -> void:
	var v: AiWorldView = ctx.view
	ctx.shared.bind(v)
	ctx.roster_idx = v.roster_of(cfg.pid)
	ctx.res = ctx.shared.resolver(ctx.roster_idx)
	ctx.tech = ctx.shared.tech_graph(ctx.roster_idx)
	ctx.tick = v.tick()
	ctx.pers = AiPersonality.build(ctx.store, v.roster_id_of(cfg.pid), cfg.style, ctx.diff, ctx.rng, cfg.personality_override)
	ctx.kb.setup(ctx)
	ingest.setup(ctx)
	scheduler.start_at(ctx.tick)
	for m: Object in _modules:
		if m.has_method("setup"):
			m.call("setup", ctx)
	booted = true


## One think of `dt` ticks ending at the tick of `world`. Appends <= 64 commands to `out`.
func step(world: RefCounted, dt: int, out: Array) -> void:
	perf.begin()
	ctx.view.begin_think(world, dt)
	if not ctx.view.bound() or not ctx.view.match_running():
		perf.end()
		return
	ctx.dt = maxi(dt, 1)
	ctx.tick = ctx.view.tick()
	if not booted:
		bootstrap_from_world()
	var avg: int = ctx.diff.wu_per_tick
	if cfg.wu_share > 0:
		avg = mini(avg, cfg.wu_share)
	var cap: int = ctx.diff.call_cap_wu
	budget.reset(mini(avg * ctx.dt, cap), cap)
	ctx.cmd.begin_think(ctx.dt, ctx.tick)
	scheduler.run(ctx.tick, ctx.dt, ctx, budget)
	last_cmds = ctx.cmd.flush(out)
	last_wu = budget.used
	last_tick = ctx.tick
	thinks += 1
	total_wu += last_wu
	total_ticks += ctx.dt
	wu_max_think = maxi(wu_max_think, last_wu)
	perf.end()


## FNV-1a over the AiRng state, the scheduler, the knowledge tables, the command history and every module's hash.
func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([ctx.rng.state(), scheduler.state_hash(), ctx.kb.state_hash(), ctx.cmd.state_hash(),
		ingest.state_hash(), ctx.pers.state_hash() if ctx.pers != null else 0])
	for m: Object in _modules:
		if m.has_method("state_hash"):
			v.append(int(m.call("state_hash")))
	return AiRng.hash_ints(v)


func debug_snapshot() -> Dictionary:
	return {
		"pid": cfg.pid, "level": cfg.level, "style": cfg.style, "tick": last_tick, "thinks": thinks, "booted": booted,
		"wu_last": last_wu, "wu_avg_per_tick": total_wu / maxi(total_ticks, 1), "wu_max_think": wu_max_think,
		"own_rows": ctx.kb.own.count, "enemy_rows": ctx.kb.enemy_units.count, "ghosts": ctx.kb.ghosts.count,
		"primary": ctx.kb.primary, "income_per_min": ctx.kb.income_per_min, "cmd_stats": ctx.cmd.stats(),
		"slot_runs": scheduler.runs,
	}
