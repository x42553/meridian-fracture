class_name AppRelaunch
extends RefCounted
## `video/renderer` cannot change at run time: restart once with `--rendering-method` (ui.md 4.7.2, 3.1). The
## `--renderer-relaunched` user argument stops a loop when the requested method is unavailable (the second start logs the
## fallback and keeps the running method).

const RELAUNCH_FLAG: String = "--renderer-relaunched"
const METHODS: PackedStringArray = ["forward_plus", "mobile", "gl_compatibility"]


## Not headless, not the editor, and the executable exists.
static func supported() -> bool:
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint():
		return false
	var exe: String = OS.get_executable_path()
	return not exe.is_empty() and FileAccess.file_exists(exe)


## "" (project default), "forward_plus", "mobile" or "gl_compatibility".
static func requested_method(store: AppSettingsStore) -> String:
	var m: String = str(store.get_value(&"video/renderer"))
	return m if METHODS.has(m) else ""


## Requested != running, no `--rendering-method` on the command line and not already relaunched.
static func needed(store: AppSettingsStore, args: AppLaunchArgs, engine_args: PackedStringArray = PackedStringArray()) -> bool:
	var want: String = requested_method(store)
	if want.is_empty() or want == RenderingServer.get_current_rendering_method():
		return false
	if args.renderer_relaunched:
		return false
	var eargs: PackedStringArray = engine_args if not engine_args.is_empty() else OS.get_cmdline_args()
	for a: String in eargs:
		if a == "--rendering-method" or a.begins_with("--rendering-method=") or a == "--rendering-driver":
			return false
	return true


## Argument vector of the new process: engine args, `--rendering-method <m>`, then `--` and the user args plus the flag.
static func build_args(method: String, engine_args: PackedStringArray, user_args: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append_array(engine_args)
	out.append("--rendering-method")
	out.append(method)
	out.append("--")
	out.append_array(user_args)
	if not user_args.has(RELAUNCH_FLAG):
		out.append(RELAUNCH_FLAG)
	return out


## Starts the new process (does not quit; the caller quits after a true result). Returns the pid, or -1.
static func relaunch(method: String, original_args: PackedStringArray = PackedStringArray()) -> int:
	if not supported() or not METHODS.has(method):
		return -1
	var engine_args: PackedStringArray = original_args if not original_args.is_empty() else OS.get_cmdline_args()
	var pid: int = OS.create_process(OS.get_executable_path(), build_args(method, engine_args, OS.get_cmdline_user_args()))
	if pid < 0:
		Log.error("app", "renderer relaunch failed for '%s'" % method)
	return pid
