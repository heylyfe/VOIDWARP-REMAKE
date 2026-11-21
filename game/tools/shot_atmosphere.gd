extends SceneTree
#
# Atmosphere screenshot tool (sky dome + floating rocks + lighting mood). Boots the REAL
# playable world (app/world.gd) exactly like tools/shot_app.gd and captures fixed camera
# framings, so a run before and a run after an atmosphere change compare 1:1. Windowed run -
# rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tools/shot_atmosphere.gd -- <abs_out_dir> <tag> [seed] [level]
#
# Writes <out_dir>/<tag>_spawn.png, <tag>_walk.png, <tag>_horizon.png, <tag>_sky.png:
#   spawn    the third-person view at spawn after 90 settle ticks (shot_app app_00 framing)
#   walk     the same view after 60 more ticks (shot_app app_01 framing)
#   horizon  a fixed camera 6 u above the spawn looking out level with the horizon
#   sky      the same camera pitched 25 degrees up (the cloud dome + the rocks)
# The horizon/sky cameras are placed from the spawn point only, so the framing is the same
# with and without the atmosphere. Prints "SHOT <path>" per PNG and SHOTATMO OK / FAIL.
# This is a verification tool, not a gate step.

const WorldScript := preload("res://app/world.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 90
const WALK_TICKS := 60

var _out_dir := ""
var _tag := "shot"
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
		_tag = args[1]
	if args.size() >= 3:
		_seed = int(args[2])
	if args.size() >= 4:
		_level = int(args[3])
	if _out_dir == "" or _out_dir.is_relative_path():
		_fail = "the out dir must be an absolute path (got '%s')" % _out_dir
		_finish()
		return
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	if mk != OK:
		_fail = "cannot create %s (DirAccess error %d)" % [_out_dir, mk]
		_finish()
		return
	_world = WorldScript.new()
	root.add_child(_world)
	if not _world.build(_seed, _level):
		_fail = "world.build(%d, %d) returned false" % [_seed, _level]
		_finish()
		return
	var spawn := Vector3(_world.ctl.x, _world.ctl.y, _world.ctl.z)
	for i in SETTLE_TICKS:
		_world.step(DT)
	await _shot("spawn")
	for i in WALK_TICKS:
		_world.step(DT)
	await _shot("walk")
	var cam: Camera3D = _world.camera
	if cam != null:
		cam.global_position = spawn + Vector3(0.0, 6.0, 0.0)
		cam.rotation_degrees = Vector3(-4.0, 30.0, 0.0)
		await _shot("horizon")
		cam.rotation_degrees = Vector3(25.0, 30.0, 0.0)
		await _shot("sky")
	_finish()


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join("%s_%s.png" % [_tag, name])
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
		print("SHOTATMO FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTATMO OK")
	quit(0)
