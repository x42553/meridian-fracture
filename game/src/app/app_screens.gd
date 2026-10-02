class_name AppScreens
extends RefCounted
## Screen registry (ui.md 2.1): `screen id -> Callable() -> UiScreen`. Resolution order of `make(id)`: an explicit
## `register` / fixture override, then the real screen class `UiScreen<CamelId>` when the project has it (UI-06a and later add
## `UiScreenMainMenu`, `UiScreenLobby` ... and are picked up without touching the app), then the app's placeholders
## (`AppSplash`, `AppPlaceholderScreen`).

const IDS: Array[StringName] = [&"splash", &"main_menu", &"lobby", &"lan_browser", &"loading", &"game", &"end", &"replays",
	&"field_manual", &"options", &"credits", &"fatal", &"campaign", &"mission_briefing", &"mission_result"]

static var _factories: Dictionary = {}
static var _classes: Dictionary = {}


static func is_valid_id(id: StringName) -> bool:
	return IDS.has(id) or _factories.has(id)


## Registers (or replaces) the factory of a screen id; fixture screens override real ones this way.
static func register(id: StringName, factory: Callable) -> void:
	_factories[id] = factory


static func unregister(id: StringName) -> void:
	_factories.erase(id)


static func clear_overrides() -> void:
	_factories.clear()


## `UiScreen` + PascalCase(id): `main_menu` -> `UiScreenMainMenu`.
static func class_of(id: StringName) -> StringName:
	return StringName("UiScreen" + String(id).capitalize().replace(" ", ""))


## A new screen for `id`, or null for an unknown id (logged).
static func make(id: StringName) -> UiScreen:
	if _factories.has(id):
		var made: Variant = (_factories[id] as Callable).call()
		if made is UiScreen:
			(made as UiScreen).screen_id = id
			return made as UiScreen
	if not IDS.has(id):
		Log.error("app", "screens: unknown screen id '%s'" % id)
		return null
	var cls: StringName = class_of(id)
	if not _classes.has(cls):
		_classes[cls] = UiDraw.optional_script(cls)
	var script: Script = _classes[cls] as Script
	if script != null:
		var real: Variant = script.new()
		if real is UiScreen:
			(real as UiScreen).screen_id = id
			return real as UiScreen
	var screen: UiScreen
	if id == &"splash":
		screen = AppSplash.new()
	else:
		screen = AppPlaceholderScreen.new()
	screen.screen_id = id
	return screen
