class_name AppHumanBot
extends RefCounted
## A debug bot (`--bots=human|all`) that plays the LOCAL human slot: it thinks about every `PERIOD_TICKS` sim ticks and its commands
## go through `NetSession.submit_command`, exactly like the UI's, so the lockstep, the command log and the replay see them. The
## brain is the scripted `SimBot` of tests/support (development builds only); `AppAiHook.make_human_bot` builds this.

const PERIOD_TICKS: int = 10

var bot: Object = null
var capture: RefCounted = null
var _last_tick: int = -1000


func _init(p_bot: Object = null, p_capture: RefCounted = null) -> void:
	bot = p_bot
	capture = p_capture


## Once per rendered frame after `NetSession.poll()`: thinks when `PERIOD_TICKS` ticks have passed.
func update(world: SimWorld) -> void:
	if bot == null or world == null or world.tick - _last_tick < PERIOD_TICKS:
		return
	_last_tick = world.tick
	bot.call(&"think", world)


## Commands the bot has issued so far.
func commands() -> int:
	return int(capture.get(&"count")) if capture != null else 0
