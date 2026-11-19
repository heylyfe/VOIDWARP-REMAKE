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


## Reads and parses one JSON file. Returns null when the file is absent or unparseable,
## which is the same signal load_from uses to try the next recovery candidate.
static func _read_json(p: String) -> Variant:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Reading from disk. Unknown keys are ignored; a bad or absent field keeps its default.
## Missing or corrupt file = both records stay 0. Never fails loudly.
##
## Recovery: a crash between the two renames in _rename_over can leave the destination
## absent with the good bytes sitting in .old (or the new bytes in .tmp). Reading only the
## destination would then silently reset the player's bests to 0, and the next save would
## overwrite the recoverable copy. So a missing or unparseable destination falls back to
## .old, then .tmp, through the same validated parse.
func load_from(p_path: String = "") -> void:
	if p_path != "":
		path = p_path
	defaults()
	var parsed: Variant = _read_json(path)
	if parsed == null:
		parsed = _read_json(path + ".old")
	if parsed == null:
		parsed = _read_json(path + ".tmp")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.has("best_level") and typeof(d["best_level"]) in [TYPE_INT, TYPE_FLOAT]:
		best_level = maxi(0, int(d["best_level"]))
	if d.has("best_purse") and typeof(d["best_purse"]) in [TYPE_INT, TYPE_FLOAT]:
		best_purse = maxi(0, int(d["best_purse"]))


## Writing to disk. Returns false on an unopenable file; otherwise true. Callers retry at
## their leisure (a lost record is not worth an error screen). The payload goes to a
## sibling .tmp file first, which is renamed over the destination only after it is fully
## written and closed, so a crash mid-write leaves the old file (or a recoverable .tmp)
## instead of a truncated one.
func save_to(p_path: String = "") -> bool:
	if p_path != "":
		path = p_path
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.flush()
	f.close()
	return _rename_over(tmp, path)


## Renames a finished .tmp file over the destination. The destination is renamed to
## destination + ".old" FIRST, then the .tmp is renamed over the destination, then the
## ".old" file is removed on success or moved back on failure. The destination is absent
## only inside that two-rename window, and load_from recovers from .old or .tmp if a crash
## lands there, so the bytes are never lost - but "never absent" would be a stronger claim
## than the code makes. This matters when the rename fails for any reason (a locked file,
## a virus scanner holding the handle): on this platform the engine's rename has been
## observed to delete the destination before the move fails, and a remove-then-retry
## fallback would then leave no destination at all. Only after the .tmp write has fully
## closed, so a crash between the two leaves the old file intact or the .tmp file
## recoverable. On final failure the .tmp is left in place (recoverable), false is
## returned, and the destination holds its previous bytes again.
static func _rename_over(tmp_path: String, dest_path: String) -> bool:
	if not FileAccess.file_exists(dest_path):
		return DirAccess.rename_absolute(tmp_path, dest_path) == OK
	var old_path := dest_path + ".old"
	if FileAccess.file_exists(old_path) and DirAccess.remove_absolute(old_path) != OK:
		return false
	if DirAccess.rename_absolute(dest_path, old_path) != OK:
		return false
	var err := DirAccess.rename_absolute(tmp_path, dest_path)
	if err == OK:
		DirAccess.remove_absolute(old_path)
		return true
	DirAccess.rename_absolute(old_path, dest_path)
	return false


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
