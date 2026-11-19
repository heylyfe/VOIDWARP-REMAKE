extends RefCounted
#
# Settings store (ticket T-082; the T-024 addendum made concrete).
#   master volume    0-100          (default 80)
#   mouse sensitivity 0.02-0.30 deg/px (default 0.12)
#   field of view    60-90 deg      (default 75)
#   fullscreen       on/off         (default off)
# Stored as JSON in `user://settings.json`. A missing, corrupt or out-of-range file never
# blocks boot: every field is clamped/defaulted (D-T082-3). Pure RefCounted; the caller picks
# the path (tests override it so they never clobber the player's real file).

const DEFAULT_PATH := "user://settings.json"

const VOLUME_MIN := 0
const VOLUME_MAX := 100
const VOLUME_DEFAULT := 80
const SENS_MIN := 0.02
const SENS_MAX := 0.30
const SENS_DEFAULT := 0.12
const FOV_MIN := 60.0
const FOV_MAX := 90.0
const FOV_DEFAULT := 75.0
const FULLSCREEN_DEFAULT := false


var volume: int = VOLUME_DEFAULT
var mouse_sensitivity: float = SENS_DEFAULT
var field_of_view: float = FOV_DEFAULT
var fullscreen: bool = FULLSCREEN_DEFAULT


func to_dict() -> Dictionary:
	return {
		"volume": volume,
		"mouse_sensitivity": mouse_sensitivity,
		"field_of_view": field_of_view,
		"fullscreen": fullscreen,
	}


## Reset every field to its default.
func defaults() -> void:
	volume = VOLUME_DEFAULT
	mouse_sensitivity = SENS_DEFAULT
	field_of_view = FOV_DEFAULT
	fullscreen = FULLSCREEN_DEFAULT


## Reading from disk. Unknown keys are ignored; a bad or absent field keeps its default; a
## present-but-out-of-range field is clamped into range. Missing file = all defaults.
func load_from(path: String = DEFAULT_PATH) -> void:
	defaults()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.has("volume") and typeof(d["volume"]) in [TYPE_INT, TYPE_FLOAT]:
		volume = clampi(int(d["volume"]), VOLUME_MIN, VOLUME_MAX)
	if d.has("mouse_sensitivity") and typeof(d["mouse_sensitivity"]) in [TYPE_INT, TYPE_FLOAT]:
		mouse_sensitivity = clampf(float(d["mouse_sensitivity"]), SENS_MIN, SENS_MAX)
	if d.has("field_of_view") and typeof(d["field_of_view"]) in [TYPE_INT, TYPE_FLOAT]:
		field_of_view = clampf(float(d["field_of_view"]), FOV_MIN, FOV_MAX)
	if d.has("fullscreen") and typeof(d["fullscreen"]) == TYPE_BOOL:
		fullscreen = bool(d["fullscreen"])


## Writing to disk. Returns false on an unopenable file; otherwise true. Callers retry at
## their leisure (settings loss is not worth an error screen). The payload goes to a
## sibling .tmp file first, which is renamed over the destination only after it is fully
## written and closed, so a crash mid-write leaves the old file (or a recoverable .tmp)
## instead of a truncated one.
func save_to(path: String = DEFAULT_PATH) -> bool:
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
## ".old" file is removed on success or moved back on failure - so the destination is
## never left absent. This matters when the rename fails for any reason (a locked file,
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


# ---- application: each field to its actual consumer ----------------------------------------------
# The store only holds values; these push them to the live consumers so a changed field is
# felt the same frame: the master audio bus, a Camera3D's FOV, a Window's mode. The settings
# screen calls them on every change. Mouse sensitivity has its own consumer already (world.gd
# and lobby_scene.gd read it when a level builds), so it lives here as a stored value only.

const MASTER_BUS := 0


## The Window.mode value the fullscreen flag maps to.
static func window_mode_for(fs: bool) -> int:
	return Window.MODE_FULLSCREEN if fs else Window.MODE_WINDOWED


## Push the master volume to the audio bus as decibels (0-100 linear -> db), muting the bus
## at 0 so silence is real silence. Returns the db now on the bus (tests read it back).
func apply_volume(bus: int = MASTER_BUS) -> float:
	AudioServer.set_bus_mute(bus, volume <= 0)
	var db := linear_to_db(float(volume) / 100.0) if volume > 0 else -80.0
	AudioServer.set_bus_volume_db(bus, db)
	return AudioServer.get_bus_volume_db(bus)


## Push the FOV onto a camera (the world's Camera3D). Returns the camera's FOV, or a
## negative value when no camera was given.
func apply_camera(camera: Camera3D) -> float:
	if camera == null:
		return -1.0
	camera.fov = field_of_view
	return camera.fov


## Push fullscreen onto a window (the running game's root window). Returns the window's
## mode, or a negative value when no window was given.
func apply_window(window: Window) -> int:
	if window == null:
		return -1
	window.mode = window_mode_for(fullscreen)
	return window.mode
