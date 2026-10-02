class_name AppAiHook
extends RefCounted
## The AI seam of a match (ui.md 5.3, net.md 5.6, ai.md 3.2): one instance per session, owned by the `AppMatchContext` because a
## Callable does not keep a RefCounted alive. It fills `NetSessionOptions.ai_factory` / `ai_release` / `ai_think_period` /
## `ai_default_handicap` over an `AiFactory` (AiBrain installed by `AiFactory.make`), so lobby AI slots, a joined LAN host's AI and
## the takeover of a dropped human (`NetProtocol.TAKEOVER_AI_LEVEL`) all reach the same code: net asks `make(pid, level, style,
## seed)` for a thinker `Callable(world, out: Array)` and injects its commands into the bundle of the target turn. The roster
## personality is the AI's own business (`style` 0 = the roster's doctrine).
##
## Debug alternative (`--bots`): the scripted `SimBot` of tests/support plays instead. It exists only in development builds and is
## found by its global class name (src may not reference tests). `--bots` = AI slots, `--bots=human` = only the human slot (real
## AI opponents), `--bots=all` = every slot.

const BOT_CLASS: StringName = &"SimBot"
## `AI level -> turns between thinks`: the difficulty's think period in ticks, in turns of `NetProtocol.TURN_TICKS`.
const MIN_PERIOD_TURNS: int = 1
## The takeover thinker of a dropped human is made by net with this level (net.md XR-13).
static var takeover_level: int = AiFactory.takeover_level()

## `--bots` debug modes (static: read by the test boot, the match glue and the game screen).
static var bots_enabled: bool = false
static var bots_all: bool = false
static var bots_human: bool = false
static var _warned: bool = false

## `(pid, level, style, rng_seed) -> Callable(world, out)`; set by tests to intercept the AI slots. Invalid = the real AI.
static var factory: Callable = Callable()

var ai: AiFactory = null
var telemetry: Callable = Callable()
var _bots: Dictionary = {}  ## pid -> SimBot (debug)
var _made: PackedInt32Array = PackedInt32Array()


func _init(p_telemetry: Callable = Callable()) -> void:
	telemetry = p_telemetry
	ai = AiFactory.new(null, p_telemetry)


## Applies `--bots[=all|human]` (the boot flag), resetting the previous mode.
static func set_bot_mode(mode: String) -> void:
	bots_enabled = false
	bots_all = false
	bots_human = false
	match mode:
		"":
			pass
		"human":
			bots_human = true
		"all":
			bots_enabled = true
			bots_all = true
		_:
			bots_enabled = true


## True when the human slot is played by a bot (the game screen then places structures itself).
static func human_is_bot() -> bool:
	return bots_all or bots_human


## The think period of an AI level in turns (net.md 5.6): `think_period_ticks / TURN_TICKS`, rounded up, at least 1.
static func think_period_turns(level: int) -> int:
	var d: AiDifficultyProfile = AiDataStore.load_default().difficulty(clampi(level, 0, AiFactory.level_count() - 1))
	return maxi(MIN_PERIOD_TURNS, (d.think_ticks() + NetProtocol.TURN_TICKS - 1) / NetProtocol.TURN_TICKS)


## net's `ai_factory`: a thinker `Callable(world, out)` for one AI slot.
func make(pid: int, level: int, style: int, rng_seed: int) -> Callable:
	_made.append(pid)
	if factory.is_valid():
		var injected: Variant = factory.call(pid, level, style, rng_seed)
		return injected as Callable if injected is Callable else Callable()
	if bots_enabled:
		var bot: Callable = make_bot_thinker(pid, {"interval": 1})
		if bot.is_valid():
			return bot
	return ai.make(pid, level, style, rng_seed)


## net's `ai_release`.
func release(pid: int) -> void:
	_bots.erase(pid)
	ai.release(pid)


## Releases every thinker made (match teardown; idempotent).
func shutdown() -> void:
	for pid: int in _made:
		release(pid)
	_bots.clear()


## Pids `make` was called for (tests, telemetry).
func made_pids() -> PackedInt32Array:
	return _made.duplicate()


## The SimBot as a net thinker (`Callable(world, out)`), or an invalid Callable when the class is absent (release builds).
func make_bot_thinker(pid: int, bot_opts: Dictionary) -> Callable:
	var script: Script = UiDraw.optional_script(BOT_CLASS)
	if script == null:
		_warn_missing()
		return Callable()
	var bot: Object = script.new(pid, bot_opts) as Object
	var cap: _Capture = _Capture.new()
	bot.set(&"cmd_log", cap)
	_bots[pid] = bot
	# a lambda, not Callable(bot, ...): a Callable does not keep a RefCounted alive, the capture does
	return func(world: RefCounted, out: Array) -> void:
		cap.out = out
		bot.call(&"think", world)


## A debug bot driving a local slot through a submit callback `(ints: PackedInt32Array) -> bool` (the human under `--bots=human|all`).
## `null` when the SimBot class is absent. Call `think(world)` about every 10 ticks.
func make_human_bot(pid: int, submit: Callable) -> AppHumanBot:
	var script: Script = UiDraw.optional_script(BOT_CLASS)
	if script == null:
		_warn_missing()
		return null
	var bot: Object = script.new(pid, {"interval": 1}) as Object
	var cap: _Capture = _Capture.new()
	cap.submit_cb = submit
	bot.set(&"cmd_log", cap)
	return AppHumanBot.new(bot, cap)


static func _warn_missing() -> void:
	if not _warned:
		_warned = true
		Log.warn("app", "--bots: the SimBot test class is not available, the slots use the real AI")


## `SimCommandLog` stand-in: a bot's `submit(world, pid, ints)` lands in `out` (AI slots) or goes to `submit` (a human slot).
class _Capture extends SimCommandLog:
	var out: Array = []
	var submit_cb: Callable = Callable()
	var count: int = 0

	func submit(_world: SimWorld, _pid: int, ints: PackedInt32Array) -> void:
		count += 1
		if submit_cb.is_valid():
			submit_cb.call(ints)
		else:
			out.append(ints)
