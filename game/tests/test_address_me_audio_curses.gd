extends RefCounted
#
# The curse gate on address me's audio (view/audio/address_me_audio.gd asking the
# curse modules which cues are allowed). The rule owner is
# content/curses/unannounced.gd - "no trumpet - only the sprite and the rumble" -
# and this file proves the SHIPPED consumer honors it through play_cue, never by
# re-stating the rule:
#
#   - the curse held: spawn_trumpet plays nothing (no player is created), while
#     rumble_build and explode_boom still play (the sprite tell and the kill boom
#     stay);
#   - negative control: the same play_cue call with the curse NOT held plays the
#     trumpet (a real player, on a host inside the tree, not a suppressed null);
#   - the cue_names()/file-name contract the earlier audio test pins is untouched.
#
# The held state is the run's carried dict, {"curses_held": {curse_id: stacks}},
# exactly the shape the curse modules read.

const Audio := preload("res://view/audio/address_me_audio.gd")
const Unannounced := preload("res://content/curses/unannounced.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_contract(f)
	_allowed(f)
	_play_through_consumer(f)
	return f


func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


func _eqs(f: Array[String], got, want, msg: String) -> void:
	if str(got) != str(want):
		f.append("%s: got %s, want %s" % [msg, str(got), str(want)])


# The base audio contract is untouched: cue_names() (no state) still names all
# three cues, sorted, and every name maps to its placeholder file.
func _contract(f: Array[String]) -> void:
	_eqs(f, Audio.cue_names(), ["explode_boom", "rumble_build", "spawn_trumpet"],
			"contract: cue_names changed")
	_eqs(f, Audio.file_name_for("spawn_trumpet"), "address_me_trumpet",
			"contract: trumpet file name changed")
	_eqs(f, Audio.file_name_for("rumble_build"), "address_me_rumble",
			"contract: rumble file name changed")
	_eqs(f, Audio.file_name_for("explode_boom"), "address_me_boom",
			"contract: boom file name changed")
	_eqs(f, Audio.allowed_cues({}).size(), 3, "contract: a curse-free run dropped a cue")


# The gate goes through the curse module: held unannounced drops ONLY the trumpet.
func _allowed(f: Array[String]) -> void:
	var held := {"curses_held": {"unannounced": 1}}
	var a: Array = Audio.allowed_cues(held)
	_eqs(f, a, ["explode_boom", "rumble_build"], "allowed: held run dropped the wrong cues")
	_check(f, not Audio.cue_allowed(held, "spawn_trumpet"), "allowed: trumpet not suppressed")
	_check(f, Audio.cue_allowed(held, "rumble_build"), "allowed: rumble suppressed too")
	_check(f, Audio.cue_allowed(held, "explode_boom"), "allowed: boom suppressed too")
	# the curse in charge is the real one, not a copy of the rule
	_eqs(f, str(Unannounced.TRUMPET_CUE), "spawn_trumpet", "allowed: trumpet cue moved")
	# an unknown cue is never allowed to play
	_check(f, not Audio.cue_allowed({}, "no_such_cue"), "allowed: an unknown cue played")


# Through the REAL consumer (play_cue) on a host genuinely inside the tree.
func _play_through_consumer(f: Array[String]) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		f.append("consumer: no SceneTree to host the player")
		return
	var host := Node.new()
	(loop as SceneTree).root.add_child(host)

	# negative control: curse NOT held -> the trumpet plays (a real player)
	var free_host := Node.new()
	(loop as SceneTree).root.add_child(free_host)
	var p: AudioStreamPlayer = Audio.play_cue(free_host, "spawn_trumpet", {"curses_held": {}})
	if p == null:
		f.append("consumer: the trumpet did not play on a curse-free run")
	elif not p.playing:
		f.append("consumer: the trumpet player was created but is not playing")
	if free_host.get_node_or_null("address_me_spawn_trumpet") == null:
		f.append("consumer: no trumpet player found on the curse-free host")

	# the curse held: play_cue itself must refuse the trumpet - no player at all
	var held := {"curses_held": {"unannounced": 1}}
	var silenced: AudioStreamPlayer = Audio.play_cue(host, "spawn_trumpet", held)
	if silenced != null:
		f.append("consumer: the trumpet played under unannounced")
	if host.get_node_or_null("address_me_spawn_trumpet") != null:
		f.append("consumer: a trumpet player was left under unannounced")

	# the sprite tell and the kill's own boom still play under the curse
	var rum: AudioStreamPlayer = Audio.play_cue(host, "rumble_build", held)
	if rum == null:
		f.append("consumer: the rumble was silenced under unannounced")
	var boom: AudioStreamPlayer = Audio.play_cue(host, "explode_boom", held)
	if boom == null:
		f.append("consumer: the boom was silenced under unannounced")

	# the legacy two-argument call (no state threaded) still plays every cue
	var legacy: AudioStreamPlayer = Audio.play_cue(free_host, "spawn_trumpet")
	if legacy == null:
		f.append("consumer: the stateless play_cue call was suppressed")

	for n in host.get_children():
		n.queue_free()
	for n in free_host.get_children():
		n.queue_free()
	host.queue_free()
	free_host.queue_free()
