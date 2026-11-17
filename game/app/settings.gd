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
## their leisure (settings loss is not worth an error screen).
func save_to(path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.flush()
	return true
