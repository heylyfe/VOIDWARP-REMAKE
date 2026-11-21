extends RefCounted
#
# The shared house shape every file-backed cue module in this folder uses (beacon_audio.gd
# is the small original): load the stream, return null SILENTLY when the file is missing -
# a missing file is never an error and never stalls the run - create the player, parent it
# to the host and start it.
#
# The one rule this file exists to keep in one place: the load is gated on
# ResourceLoader.exists(path), NEVER on FileAccess.file_exists(path). An export packs the
# imported stream and its remap, not the raw .wav, so a file check makes every cue silent
# in the shipped build (learned the hard way on the beacon cue this cycle).
#
# The player, UI, world and ambience modules (player_audio.gd, ui_audio.gd, world_audio.gd,
# ambience_audio.gd) own their cue tables and call these; nothing else should build an
# AudioStreamPlayer for a cue file by hand.

const BUS := "Master"   # the only bus (no default_bus_layout.tres in the project)


## The cue as a stream, or null when the path is absent / not audio. The ResourceLoader
## gate is the export-safe one (see the header).
static func load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res: Variant = load(path)
	if res == null or not (res is AudioStream):
		return null
	return res as AudioStream


## A one-shot non-positional player parented to `host` and already playing, or null
## (silently) when the file is missing or the host is unusable.
static func play_2d(host: Object, path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var stream := load_stream(path)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = BUS
	p.autoplay = false
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A one-shot positional player at `pos` parented to `host` and already playing, or null
## (silently) when the file is missing or the host is unusable.
static func play_3d(host: Object, path: String, pos: Vector3, volume_db: float = 0.0,
		unit_size: float = 8.0) -> AudioStreamPlayer3D:
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var stream := load_stream(path)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.unit_size = unit_size
	p.volume_db = volume_db
	p.bus = BUS
	p.autoplay = false
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A LOOPING non-positional player parented to `host` and already playing, or null
## (silently). The caller owns the returned player and frees it (stop_loop) when the state
## that started it ends. The stream is duplicated before its loop mode is set, so the
## loader's cached resource is never mutated for every other player of the same cue.
static func loop_2d(host: Object, path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var stream := load_stream(path)
	if stream == null:
		return null
	var looped := _looped(stream)
	if looped == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = looped
	p.volume_db = volume_db
	p.bus = BUS
	p.autoplay = false
	parent.add_child(p)
	p.play()
	return p


## Stops and frees a player loop_2d returned. A null player is a harmless no-op.
static func stop_loop(p: AudioStreamPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.stop()
	p.queue_free()


## A copy of `stream` that loops forward over its whole length, or null when the stream
## type cannot loop (an MP3 cue is never used as a bed).
static func _looped(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
		return wav
	if stream is AudioStreamMP3:
		var mp3 := (stream as AudioStreamMP3).duplicate() as AudioStreamMP3
		mp3.loop = true
		return mp3
	return null

