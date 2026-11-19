extends RefCounted
#
# Records store (DESIGN.md section 9: best level and best purse are recorded locally).
#   best_level  the deepest level any run has reached
#   best_purse  the largest purse any run has carried at run end
# Stored as JSON in user://records.json. A missing, corrupt or out-of-range file never
# blocks anything: every field is defaulted (same contract as app/settings.gd - the caller
# picks the path, tests override it so they never clobber the player real file).
# Pure RefCounted: no scene-tree types, no engine types beyond FileAccess, no RNG.

const DEFAULT_PATH := "user://records.json"

var best_level: int = 0
var best_purse: int = 0

## The path load_from/save_to/record_run use. Defaults to the player real file; tests
## point it at a scratch path.
var path: String = DEFAULT_PATH


func to_dict() -> Dictionary:
	return {
		"best_level": best_level,
		"best_purse": best_purse,
	}


## Reset both records to zero (defaults).
func defaults() -> void:
	best_level = 0
	best_purse = 0


## Exposed getters (the menu / run-over screen read these without touching the fields).
func get_best_level() -> int:
	return best_level


func get_best_purse() -> int:
	return best_purse


## Reading from disk. Unknown keys are ignored; a bad or absent field keeps its default.
## Missing or corrupt file = both records stay 0. Never fails loudly.
func load_from(p_path: String = "") -> void:
	if p_path != "":
		path = p_path
	defaults()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.has("best_level") and typeof(d["best_level"]) in [TYPE_INT, TYPE_FLOAT]:
		best_level = maxi(0, int(d["best_level"]))
	if d.has("best_purse") and typeof(d["best_purse"]) in [TYPE_INT, TYPE_FLOAT]:
		best_purse = maxi(0, int(d["best_purse"]))


## Writing to disk. Returns false on an unopenable file; otherwise true. Callers retry at
## their leisure (a lost record is not worth an error screen).
func save_to(p_path: String = "") -> bool:
	if p_path != "":
		path = p_path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.flush()
	return true


## Record a finished run: best_level and best_purse only ever ratchet UP - a worse run
## never lowers them. Persists immediately (a crash after run end must keep the record).
## Returns true when the file was written.
func record_run(level_reached: int, purse: int) -> bool:
	var changed := false
	if int(level_reached) > best_level:
		best_level = int(level_reached)
		changed = true
	if int(purse) > best_purse:
		best_purse = int(purse)
		changed = true
	if not changed and FileAccess.file_exists(path):
		return true
	return save_to()
