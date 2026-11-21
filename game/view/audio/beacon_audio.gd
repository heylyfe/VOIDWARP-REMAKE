extends RefCounted
#
# beacon_open cue (the owner-supplied recording, assets/audio/world/beacon_open.mp3):
# the full-length cue that plays once when the beacon opens - the beacon_opened
# event's moment (sim/events.gd EV_BEACON_OPENED, raised by sim/beacon.gd open()),
# consumed through the view: beacon_view.gd set_open() plays it on the
# closed -> open transition (the app's per-tick view pass feeds that transition
# from the sim state), so no app file is touched here.
#
# House shape: the file-backed play_cue idiom - a static function that loads the
# stream, returns null SILENTLY when the file is missing (a missing file is not
# an error; the run never stalls on audio), creates the player, parents it to
# the host and starts it. No Input singleton, no wall clock: the cue is a
# one-shot tied to the open translation, driven by the sim state.
#
# Once per open: beacon_view.gd owns the played guard (a state flag on the
# view), so a re-fed event list never restarts the cue. Not a loop: the full
# ~9 s cue plays through and the player frees itself on finish.

const PATH := "res://assets/audio/world/beacon_open.mp3"
const CUE_NAME := "beacon_open"
const VOLUME_DB := -6.0  # a full-length cue, not a UI blip: start well under unity
const BUS := "Master"    # the only bus (no default_bus_layout.tres in the project)


## The one started player (already playing, parented to `host`), or null -
## silently, never an error - when the file is missing or the host is unusable.
static func play_open(host: Object) -> AudioStreamPlayer:
	return _play_path(host, PATH)


## The same play against an arbitrary path - the negative-control entry point:
## a missing file must answer null without crashing.
static func _play_path(host: Object, path: String) -> AudioStreamPlayer:
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var stream := _load_stream(path)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.name = CUE_NAME
	p.stream = stream
	p.volume_db = VOLUME_DB
	p.bus = BUS
	p.autoplay = false
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Loads the cue as a stream, or null when the path is absent / not audio.
## Check the resource before loading so missing cues stay silent.
static func _load_stream(path: String) -> AudioStream:
	# Exports pack the imported stream and remap, not the raw MP3 file.
	if not ResourceLoader.exists(path):
		return null
	var res: Variant = load(path)
	if res == null or not (res is AudioStream):
		return null
	var s := res as AudioStream
	if s is AudioStreamMP3:
		# never a loop: the cue plays once through
		(s as AudioStreamMP3).loop = false
	return s

