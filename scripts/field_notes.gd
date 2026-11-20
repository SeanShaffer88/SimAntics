extends RefCounted
## Field notes: a journal the colony writes as it lives. Milestones (first workers,
## new chambers, the queen moving down, flights, visitors) are noted once each;
## recurring events like rain are noted each time but never twice in a row.

const MAX_ENTRIES := 80

var entries: Array = []  # {"time": unix seconds, "text": String}
var _seen: Dictionary = {}


## Records an observation. A non-empty `key` makes it a once-only milestone.
func note(text: String, key: String = "") -> void:
	if key != "":
		if _seen.has(key):
			return
		_seen[key] = true
	if not entries.is_empty() and entries[entries.size() - 1]["text"] == text:
		return
	entries.append({"time": Time.get_unix_time_from_system(), "text": text})
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()


func has_noted(key: String) -> bool:
	return _seen.has(key)


## How many once-only notes start with `prefix` (e.g. behaviours the player has seen).
func count_prefix(prefix: String) -> int:
	var n := 0
	for key: String in _seen:
		if key.begins_with(prefix):
			n += 1
	return n


## The most recent `count` entries, newest first.
func recent(count: int) -> Array:
	var out := []
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 1 - count), -1):
		out.append(entries[i])
	return out


func to_save() -> Dictionary:
	return {"entries": entries, "seen": _seen.keys()}


func restore(saved: Dictionary) -> void:
	entries = saved.get("entries", [])
	for key in saved.get("seen", []):
		_seen[str(key)] = true
