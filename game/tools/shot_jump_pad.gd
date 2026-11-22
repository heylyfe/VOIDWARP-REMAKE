extends SceneTree
#
# Jump pad screenshot tool (D-JUMPPAD-5): boots the REAL playable world (app/world.gd), finds
# the level's first jump pad and captures it. Windowed run - rendering needs a GPU context,
# never --headless:
#
#   <godot> --path game --script res://tools/shot_jump_pad.gd -- <abs_out_dir> [seed] [level]
#
# Writes <out_dir>/jumppad_00.png .. jumppad_02.png:
#   jumppad_00  the pad at rest beside the walkway's middle lane (camera pulled in)
#   jumppad_01  the player put on the pad: 3 ticks after it fired (compressed + ripple)
#   jumppad_02  the same, 30 ticks later: the player high above the pad (third-person camera)
#
# The world is stepped by this script, so the capture is deterministic. Prints "SHOT <path>"
# per PNG and "SHOTJP OK" / "SHOTJP FAIL <why>"; exit 1 on failure. Not a gate step.

const WorldScript := preload("res://app/world.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 60

var _out_dir := ""
var _seed := 7
var _level := 1
var _fail := ""
var _world: Node3D = null


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
		_level = int(args[2])
	if _out_dir == "":
		_out_dir = ProjectSettings.globalize_path("res://shots_jumppad")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_world = WorldScript.new()
	root.add_child(_world)
	if not _world.build(_seed, _level):
		_fail = "world.build(%d, %d) returned false" % [_seed, _level]
		_finish()
		return
	for i in SETTLE_TICKS:
		_world.step(DT)
	var jp = _world.lstate.jump_pads
	if jp == null or jp.count() == 0:
		_fail = "seed %d level %d has no jump pad" % [_seed, _level]
		_finish()
		return
	var p: Array = jp.pads[0]
	var pad := Vector3(float(int(p[0])) + 0.5, float(int(p[2])) * 0.5, float(int(p[1])) + 0.5)
	print("PAD %s" % str(p))
	var cam: Camera3D = _world.camera
	var rig = _world.rig
	# 0: the pad at rest. The rig is paused so it cannot pull the camera back to the player.
	if rig != null:
		rig.set_process(false)
		rig.set_physics_process(false)
	cam.global_position = pad + Vector3(3.2, 2.6, 3.4)
	cam.look_at(pad + Vector3(-0.3, 0.0, -0.3), Vector3.UP)
	await _shot("jumppad_00")
	# 1: put the player on the pad and let it fire
	var ctl = _world.ctl
	ctl.x = pad.x
	ctl.y = pad.y
	ctl.z = pad.z
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.grounded = true
	ctl.sync_body()
	var fired := false
	for i in 4:
		_world.step(DT)
		for e in _world.last_events:
			if str(e.get("e", "")) == "jump_pad_launch":
				fired = true
	if not fired:
		_fail = "the pad did not fire with the player on it"
		_finish()
		return
	cam.global_position = pad + Vector3(3.6, 3.2, 3.8)
	cam.look_at(pad + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	await _shot("jumppad_01")
	# 2: the fling, from the gameplay camera
	if rig != null:
		rig.set_process(true)
		rig.set_physics_process(true)
	for i in 30:
		_world.step(DT)
	print("PLAYER y %.2f (pad top %.2f)" % [float(ctl.y), pad.y])
	await _shot("jumppad_02")
	_finish()


func _shot(name: String) -> void:
	await process_frame
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
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
	if _fail != "":
		print("SHOTJP FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTJP OK")
	quit(0)
