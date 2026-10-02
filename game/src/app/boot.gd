extends Node
## Boot scene root (project main scene, ui.md 2.1 / 5.2.1). Keeps the `--smoke` contract (given either before or after the
## `--` separator), honours the QA hooks and then hands over to `AppBoot.run`.
##
## Smoke line format (parsed by tools/py/export.py by its prefix; the leading keys never change):
##   MERIDIAN_BOOT engine=<major.minor.patch-status> renderer=<method> os=<name> debug=<0|1> version=<x.y.z> build=<id> selftest=<ok|N>
## QA hooks (qa.md QA-XR-11): `--qa=<job>` instantiates res://tests/harness/qa_entry.gd (when it exists) and quits with its
## exit code; `--selfcheck` runs the export manifest verification when present; both are ignored when the file is absent.

const SMOKE_FLAG: String = "--smoke"


func _ready() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var args: AppLaunchArgs = AppLaunchArgs.parse(user_args)
	if args.smoke or OS.get_cmdline_args().has(SMOKE_FLAG):
		# lint-allow: L006 smoke line is parsed by tools/py/export.py and CI, Log may not be installed yet
		print(AppInfo.smoke_line(AppInfo.selftest_failures()))
		get_tree().quit(0)
		return
	if not args.qa_job.is_empty() and ResourceLoader.exists(AppPaths.QA_ENTRY):
		await _run_qa(user_args)
		return
	if args.selfcheck and _run_selfcheck():
		return
	@warning_ignore("missing_await")
	AppBoot.run(self)


## Instantiates the QA entry as a child and quits with its exit code.
func _run_qa(user_args: PackedStringArray) -> void:
	var entry: Node = (load(AppPaths.QA_ENTRY) as GDScript).new() as Node
	add_child(entry)
	var code: int = 0
	if entry.has_method("run"):
		code = int(await entry.call("run", user_args))
	elif "exit_code" in entry:
		code = int(entry.get("exit_code"))
	get_tree().quit(code)


## `--selfcheck`: the export manifest verification (`QaExportManifest.verify`) when the QA harness ships it. True = handled.
func _run_selfcheck() -> bool:
	var script: Script = UiDraw.optional_script(&"QaExportManifest")
	if script == null:
		return false
	get_tree().quit(int(script.call("verify")))
	return true


func _exit_tree() -> void:
	# release the engine logger and the Log sink so the process exits without leaked objects
	AppBoot.shutdown_logging()
