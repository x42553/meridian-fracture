class_name UiScreenSplash
extends AppSplash
## The boot splash as the UI screen registry sees it (`AppScreens.make(&"splash")` prefers this class): the app's splash
## (wordmark, emblem, grid glow, progress bar, status line; `AppBoot` drives `set_status` / `set_progress`) under the UI-06a
## name. `UiScreenSplash` adds nothing the boot does not need; the visuals live in `AppSplash` so both stay one implementation.


func _init() -> void:
	super._init()
