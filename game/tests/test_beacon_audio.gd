extends RefCounted
#
# beacon_open cue (the owner-supplied recording, assets/audio/world/beacon_open.mp3)
# through its real consumer chain: the file, the static player
# (view/audio/beacon_audio.gd), and the beacon view's own open transition
# (view/beacon_view.gd set_open - the state the app's per-tick view pass feeds
# from the sim's beacon, i.e. the beacon_opened moment).
#
#   leg 1  the file exists and loads as an AudioStream (the import ran)
#   leg 2  play_open(host) on a real in-tree Node host: a live AudioStreamPlayer,
#          parented to the host, playing
#   leg 3  negative control: a deliberately wrong path answers null - no crash,
#          no error pushed (the source pushes no error; the file check happens
#          before load(), so load() itself never prints for a missing file)
#   leg 4  a real world.build() + world.step() until the beacon opens: exactly
#          ONE started player on the beacon view, and stepping well past the
#          open does not start a second (the played-guard leg)
#   leg 5  the stream does not loop (a full-length cue plays through once)
#
# Registered like every other test: extends RefCounted, run() -> Array[String],
# preloads by path (no class_name). Nodes that must be in the tree go under
# the real SceneTree root (test_address_me_audio_curses.gd's consumer pattern).

const BeaconAudio := preload("res://view/audio/beacon_audio.gd")
const WorldScript := preload("res://app/world.gd")

const PATH := "res://assets/audio/world/beacon_open.mp3"
const MISSING_PATH := "res://assets/audio/world/no_such_cue.mp3"
const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0
const POST_OPEN_STEPS := 180   # 3 s of sim ticks past the open: no second start


func run() -> Array[String]:
	var f: Array[String] = []
	_file_leg(f)
	_play_leg(f)
	_missing_leg(f)
	_world_leg(f)
	_loop_leg(f)
	return f


func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()


# ---- leg 1: the file --------------------------------------------------------------------------


func _file_leg(f: Array[String]) -> void:
	if not FileAccess.file_exists(PATH):
		f.append("file: the cue is missing at %s" % PATH)
		return
	var res: Variant = load(PATH)
	if res is AudioStream:
		return
	f.append("file: %s loads as %s, want an AudioStream" % [PATH, type_string(typeof(res))])


# ---- leg 2: the real consumer on an in-tree host ----------------------------------------------


func _play_leg(f: Array[String]) -> void:
	var root := _root()
	if root == null:
		f.append("play: no SceneTree root to host the player")
		return
	var host := Node.new()
	root.add_child(host)
	var p: AudioStreamPlayer = BeaconAudio.play_open(host)
	if p == null:
		f.append("play: play_open returned null on an in-tree host (file: %s)" % PATH)
		_cleanup(host)
		return
	if p.get_parent() != host:
		f.append("play: the player is parented to %s, want the host" % str(p.get_parent()))
	if not p.playing:
		f.append("play: the player was returned but is not playing")
	_cleanup(host)


func _cleanup(host: Node) -> void:
	for n in host.get_children():
		n.queue_free()
	host.queue_free()


# ---- leg 3: negative control - a wrong path ---------------------------------------------------


func _missing_leg(f: Array[String]) -> void:
	# the loader first: a missing file must answer null, without loading anything
	var nothing: AudioStream = BeaconAudio._load_stream(MISSING_PATH)
	if nothing != null:
		f.append("missing: the loader answered a stream for %s, want null" % MISSING_PATH)
	# then the full play path on an in-tree host: null, and nothing parented
	var root := _root()
	if root == null:
		f.append("missing: no SceneTree root for the negative control")
		return
	var host := Node.new()
	root.add_child(host)
	var p: AudioStreamPlayer = BeaconAudio.play_open(host)
	# sanity: the real path plays on this host, so a null answer below is the
	# path's fault, not an unusable host
	if p == null:
		f.append("missing: sanity play on the real path returned null (host unusable?)")
		_cleanup(host)
		return
	var bad: AudioStreamPlayer = BeaconAudio._play_path(host, MISSING_PATH)
	if bad != null:
		f.append("missing: the wrong path started a player, want null")
	if host.get_child_count() != 1:
		f.append("missing: the wrong path left %d children on the host, want 1 (the sanity player)"
			% host.get_child_count())
	_cleanup(host)


# ---- leg 4: the real world, once per open -----------------------------------------------------


## The AudioStreamPlayer children under the beacon view (the cue player's home).
func _open_players(beacon_view: Node) -> Array:
	var out: Array = []
	if beacon_view == null:
		return out
	for n in beacon_view.get_children():
		if n is AudioStreamPlayer:
			out.append(n)
	return out


func _world_leg(f: Array[String]) -> void:
	var root := _root()
	if root == null:
		f.append("world: no SceneTree root to host the world")
		return
	var world = WorldScript.new()
	root.add_child(world)
	if not world.build(SEED, LEVEL):
		f.append("world: world failed to build level %d seed %d" % [LEVEL, SEED])
		_drop(world)
		return
	var g: RefCounted = world.lstate.gifts
	if int(g.total_real) <= 0:
		f.append("world: no real gifts in level %d seed %d" % [LEVEL, SEED])
		_drop(world)
		return

	# collect every real black gift, one world.step() each (the app-loop pattern):
	# the beacon opens on the tick the last one lands
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0   # feet on the slot's tile top; pickup centre 0.9 u up
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
	if not bool(world.lstate.beacon.is_open()):
		f.append("world: the beacon never opened after all %d real gifts" % int(g.total_real))
		_drop(world)
		return

	var players := _open_players(world.beacon_view)
	if players.size() != 1:
		f.append("world: %d open-cue players on the beacon view after the open, want exactly 1"
			% players.size())
	elif not (players[0] as AudioStreamPlayer).playing:
		f.append("world: the open-cue player is not playing")

	# the state feed re-syncs every single tick: stepping well past the open must
	# not start a second cue
	for _i in range(POST_OPEN_STEPS):
		world.step(DT)
	var after := _open_players(world.beacon_view)
	if after.size() != 1:
		f.append("world: %d open-cue players after %d further steps, want still exactly 1"
			% [after.size(), POST_OPEN_STEPS])
	_drop(world)


# ---- leg 5: no loop ---------------------------------------------------------------------------


func _loop_leg(f: Array[String]) -> void:
	var s: AudioStream = BeaconAudio._load_stream(PATH)
	if s == null:
		f.append("loop: the cue failed to load at %s" % PATH)
		return
	if s is AudioStreamMP3 and (s as AudioStreamMP3).loop:
		f.append("loop: the cue stream has loop on, want off")


