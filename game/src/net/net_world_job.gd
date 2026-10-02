class_name NetWorldJob
extends RefCounted
## Time-sliced world construction (docs/spec/net.md 3.3) so the main thread keeps servicing the transport
## while a map is generated. Produced by opts.world_builder(config). Subclass and override step(),
## progress_pct(), error() and take_adapter() for a sliceable build; NetWorldJob.sync() wraps a plain builder
## into a job that finishes in one step.

var _builder: Callable = Callable()
var _adapter: NetSimAdapter = null
var _err: String = ""
var _done: bool = false


## Wraps `builder` (`() -> NetSimAdapter`) into a one-step job (fallback when the map / sim cannot slice).
static func sync(builder: Callable) -> NetWorldJob:
	var j: NetWorldJob = NetWorldJob.new()
	j._builder = builder
	return j


## Advances the build for about `budget_us` microseconds. true when finished (call again otherwise).
func step(_budget_us: int) -> bool:
	if _done:
		return true
	_done = true
	if not _builder.is_valid():
		_err = "world builder is not callable"
		return true
	var res: Variant = _builder.call()
	if res is NetSimAdapter:
		_adapter = res as NetSimAdapter
	else:
		_err = "world builder returned no adapter"
	return true


## 0..100.
func progress_pct() -> int:
	return 100 if _done else 0


## "" = ok.
func error() -> String:
	return _err


## Valid once step() returned true and error() == "".
func take_adapter() -> NetSimAdapter:
	var a: NetSimAdapter = _adapter
	_adapter = null
	return a
