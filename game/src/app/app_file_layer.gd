class_name AppFileLayer
extends RefCounted
## Injectable file operations of the crash-safe settings writer (ui.md 5.20.1). The default implementation uses
## `FileAccess` / `DirAccess`; tests subclass it to interrupt the write sequence after each mutating step.
## Every mutating call returns a Godot `Error` code (`OK` = done).


## Writes the complete text and flushes/closes the file.
func write_text(path: String, text: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	var err: int = f.get_error()
	f.close()
	return err


## Plain rename; the caller removes an existing target first (Windows cannot rename over a file, P17).
func rename(from: String, to: String) -> int:
	return DirAccess.rename_absolute(from, to)


func remove(path: String) -> int:
	return DirAccess.remove_absolute(path)


func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


## The whole file, or "" when it is missing/unreadable.
func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Names of the files in a folder (no sub folders); empty when the folder is missing.
func list_files(dir: String) -> PackedStringArray:
	return DirAccess.get_files_at(dir)


## Modification time (unix seconds), 0 when unknown.
func modified_time(path: String) -> int:
	return FileAccess.get_modified_time(path)
