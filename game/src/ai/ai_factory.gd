class_name AiFactory
extends RefCounted
## One instance per match, built by app/ (AppMatch.make_ai_thinker) and handed to net as `opts.ai_factory = factory.make`
## (ai.md 3.2). Owns the shared derived data and the thinker registry, the level / style names and the global CPU governor
## (a match-wide 2400 wu/tick divided among the live thinkers). `make` returns `func(world, out)` bound to a new AiThinker.

var store: AiDataStore = null
var shared: AiSharedData = null
var telemetry: Callable = Callable()  ## func(pid: int, code: int, a: int, b: int, tick: int)
var debug_level: int = 0
var perf: bool = false
var personality_overrides: Dictionary = {}  ## pid -> {field: int}
var tuning_override: Dictionary = {}
## `make` installs the full module set (`AiBrain.install`: economy + strategy + defense + attack + scouting). Test kits that plug
## their own module set into a bare thinker set this false.
var install_brain: bool = true
var _thinkers: Dictionary = {}  ## pid -> AiThinker


func _init(p_store: AiDataStore = null, p_telemetry: Callable = Callable()) -> void:
	store = p_store if p_store != null else AiDataStore.load_default()
	shared = AiSharedData.new(store)
	telemetry = p_telemetry


## net's ai_factory(pid, level, style, seed) -> Callable(world, out).
func make(pid: int, level: int, style: int, p_seed: int) -> Callable:
	var cfg: AiConfig = AiConfig.make(pid, level, style, p_seed)
	cfg.debug_level = debug_level
	cfg.perf = perf
	cfg.personality_override = personality_overrides.get(pid, {})
	cfg.tuning_override = tuning_override
	var t: AiThinker = AiThinker.new(cfg, self)
	if install_brain:
		AiBrain.install(t.controller)
	_thinkers[pid] = t
	_rebalance()
	return Callable(t, "think")


func thinker(pid: int) -> AiThinker:
	return _thinkers.get(pid, null)


func release(pid: int) -> void:
	var t: AiThinker = _thinkers.get(pid, null)
	if t != null:
		# the brain's modules keep the context (ctx.brain -> module -> ctx is a reference cycle): cutting one edge lets the thinker
		# and everything it reads (world view, tables) be freed with the match
		t.controller.ctx.brain = null
	_thinkers.erase(pid)
	_rebalance()


func live_count() -> int:
	return _thinkers.size()


## Global governor: per-AI average wu/tick = min(profile, GLOBAL / live thinkers).
func _rebalance() -> void:
	if _thinkers.is_empty():
		return
	var share: int = AiTypes.GLOBAL_WU_PER_TICK / _thinkers.size()
	for pid: int in _thinkers:
		(_thinkers[pid] as AiThinker).cfg.wu_share = share


## FNV-1a over the thinker state hashes in ascending pid order.
func state_hash() -> int:
	var pids: Array = _thinkers.keys()
	pids.sort()
	var v: PackedInt32Array = PackedInt32Array()
	for pid: int in pids:
		v.append(pid)
		v.append((_thinkers[pid] as AiThinker).state_hash())
	return AiRng.hash_ints(v)


func debug_frame(pid: int) -> AiDebugFrame:
	var t: AiThinker = thinker(pid)
	if t == null or t.cfg.debug_level < 2:
		return null
	var f: AiDebugFrame = AiDebugFrame.new()
	f.pid = pid
	f.tick = t.last_think_tick
	var c: AiContext = t.controller.ctx
	f.panel.append("phase: n/a")
	f.panel.append("income_per_min: %d" % c.kb.income_per_min)
	f.panel.append("ghosts: %d" % c.kb.ghosts.count)
	return f


static func level_count() -> int:
	return AiTypes.AI_LEVEL_COUNT


static func style_count() -> int:
	return AiTypes.AI_STYLE_COUNT


static func level_names() -> PackedStringArray:
	return AiTypes.LEVEL_KEYS.duplicate()


static func style_names() -> PackedStringArray:
	return AiTypes.STYLE_KEYS.duplicate()


## Lobby default handicap of the level: 100, 100, 100, 120 (Brutal's clearly labelled economy bonus).
static func level_handicap_pct(level: int) -> int:
	return AiDataStore.load_default().difficulty(level).handicap_pct


## "" or "ai.cheats.brutal": the label shown next to the level name.
static func level_cheat_key(level: int) -> String:
	return AiDataStore.load_default().difficulty(level).label_cheats


static func takeover_level() -> int:
	return AiTypes.TAKEOVER_LEVEL
