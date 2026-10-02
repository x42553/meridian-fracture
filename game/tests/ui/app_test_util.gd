extends RefCounted
## Helpers of the app-layer tests (not a test file): a sandbox folder under `user://`, a fault-injecting file layer and small
## file utilities. The tests never touch the real `user://settings.cfg`.


## A fresh empty folder `user://ut_app_<n>`; remove it with `cleanup`.
static func sandbox(tag: String = "x") -> String:
	var dir: String = "user://ut_app_%s_%d" % [tag, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func cleanup(dir: String) -> void:
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		cleanup(dir.path_join(d))
	DirAccess.remove_absolute(dir)


static func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## File layer that "loses power" after `budget` mutating operations (write / remove / rename): later calls change nothing and
## return an error. `partial = true` makes the operation that runs out of budget write half of the text.
class Crashy extends AppFileLayer:
	var budget: int = 0
	var partial: bool = false
	var ops: int = 0

	func _init(b: int = 0, half: bool = false) -> void:
		budget = b
		partial = half

	func write_text(path: String, text: String) -> int:
		if ops >= budget:
			if partial and ops == budget:
				ops += 1
				super.write_text(path, text.substr(0, text.length() / 2))
			return ERR_FILE_CANT_WRITE
		ops += 1
		return super.write_text(path, text)

	func rename(from: String, to: String) -> int:
		if ops >= budget:
			return ERR_FILE_CANT_WRITE
		ops += 1
		return super.rename(from, to)

	func remove(path: String) -> int:
		if ops >= budget:
			return ERR_FILE_CANT_WRITE
		ops += 1
		return super.remove(path)
