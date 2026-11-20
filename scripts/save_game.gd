extends RefCounted
## Colony save file: everything needed to bring a player's colony back as they left
## it. Stored as JSON in user://, separate from settings so a bad save can never
## lose the colony seed or preferences.

const SAVE_PATH := "user://colony_save.json"
const VERSION := 1


static func write(data: Dictionary) -> void:
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	var tmp := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))
	file.close()
	# replace the old save only once the new one is fully written
	var target := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(target)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), target)


## The saved colony for `seed_value`, or {} if there is none (or it belongs to another colony).
static func read(seed_value: int) -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file unreadable; starting the colony fresh.")
		return {}
	if int(data.get("seed", 0)) != seed_value or int(data.get("version", 0)) != VERSION:
		return {}
	return data


static func clear() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
