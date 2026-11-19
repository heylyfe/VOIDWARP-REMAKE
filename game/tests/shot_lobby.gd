extends SceneTree
#
# Lobby screenshot tool (J7): boots the REAL Antechamber (view/lobby/lobby_scene.gd) and
# captures what the player actually sees. Windowed run - rendering needs a GPU context,
# never --headless:
#
#   <godot> --path game --script res://tests/shot_lobby.gd -- <out_dir> [seed] [completed]
#
# Writes <out_dir>/lobby_00.png .. lobby_03.png:
#   lobby_00  the arrival view from (0, +8) facing -z: hall, banners, gate, sigil
#   lobby_01  standing at an altar: its description panel is up, the others are hidden
#   lobby_02  the same altar after the F-pick: the bay flares, the gate opens
#   lobby_03  a wide view of the whole hall from the south wall
#
# Named shot_lobby.gd, not test_lobby_shot.gd, so tests/run_all.gd does not discover it
# (it needs a window; the headless gate has none). Prints "SHOT <path>" per PNG and
# "SHOTLOBBY OK" / "SHOTLOBBY FAIL <why>"; exit 1 on failure. A verification tool, not a
# gate step.

const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 30
const HOLD_TICKS := 30

var _out_dir := ""
var _seed := 7
var _completed := 1
var _fail := ""
var _scene: Node3D = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	if args.size() >= 2:
		_seed = int(args[1])
	if args.size() >= 3:
		_completed = int(args[2])
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("res://shots_lobby")
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	if mk != OK:
		_fail = "cannot create %s (DirAccess error %d)" % [_out_dir, mk]
		_finish()
		return

	_scene = LobbySceneScript.new()
	root.add_child(_scene)
	if not _scene.build(_seed, _completed, {"purse": 400}):
		_fail = "lobby.build(%d, %d) returned false" % [_seed, _completed]
		_finish()
		return
	for i in SETTLE_TICKS:
		_scene.tick(DT, 0, 0, false)
	await _shot("lobby_00")

	# Stand at the first offer altar and look at it: the panel comes up.
	var target: Dictionary = {}
	for a in _scene.hall._altars:
		if str(a["kind"]) == "offer":
			target = a
			break
	if target.is_empty():
		_fail = "the lobby has no offer altar to stand at"
		_finish()
		return
	_stand_at(target)
	for i in 4:
		_scene.tick(DT, 0, 0, false)
	await _shot("lobby_01")

	# Hold F: the pick lands, the bay flares, the gate opens.
	for i in HOLD_TICKS:
		var res: Dictionary = _scene.tick(DT, 0, 0, true)
		if int(res["select"]) != -1:
			break
	_scene.tick(DT, 0, 0, false)
	await _shot("lobby_02")

	# A wide view of the whole hall from the south wall.
	var cam: Camera3D = _scene.player.camera
	if cam != null:
		var saved := cam.global_transform
		cam.global_position = Vector3(0.0, 6.8, 9.2)
		cam.look_at(Vector3(0.0, 1.2, -4.0), Vector3.UP)
		await _shot("lobby_03")
		cam.global_transform = saved
	_finish()


func _stand_at(p_altar: Dictionary) -> void:
	var root3: Node3D = p_altar["root"]
	_scene.player.x = root3.position.x
	_scene.player.z = root3.position.z + 2.0
	_scene.player.vx = 0.0
	_scene.player.vz = 0.0
	_scene.player.rig.yaw_deg = 0.0


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	if err != OK:
		_fail = "save_png(%s) error %d" % [path, err]
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _scene != null:
		_scene.teardown()
		_scene.queue_free()
		_scene = null
	if _fail != "":
		print("SHOTLOBBY FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTLOBBY OK")
	quit(0)
