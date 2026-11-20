extends SceneTree
#
# App screenshot tool: boots the REAL playable world (app/world.gd) and captures what the
# player actually sees. Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tools/shot_app.gd -- <out_dir> [seed] [level]
#
# Writes <out_dir>/app_00.png .. app_03.png:
#   app_00  the third-person view at spawn, after the world has settled
#   app_01  the same view after the player walks forward for a second
#   app_02  a close look at the nearest gift slot (camera pulled in)
#   app_03  a top-down overview of the whole level (orthographic, 140 u wide)
#
# The world is stepped by this script (world.gd has no _process of its own - app.gd drives
# step()), so the capture is deterministic and does not depend on the frame rate.
#
# Prints "SHOT <path>" per written PNG and "SHOTAPP OK" / "SHOTAPP FAIL <why>"; exit 1 on
# failure. This is a verification tool, not a gate step.

const WorldScript := preload("res://app/world.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const DT := 1.0 / 60.0
const SETTLE_TICKS := 90
const WALK_TICKS := 60

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
		_out_dir = ProjectSettings.globalize_path("res://shots_app")
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
	for i in SETTLE_TICKS:
		_world.step(DT)
	await process_frame
	await _shot("app_00")

	# Walk forward for a second so the shot is not just the spawn tile.
	for i in WALK_TICKS:
		_world.step(DT)
	await process_frame
	await _shot("app_01")

	await _shot_gift_closeup()
	await _shot_overview()
	_finish()


## Pull the camera in on the nearest real gift slot so the gift model is unmistakable.
func _shot_gift_closeup() -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var target := Vector3.ZERO
	var found := false
	var lstate = _world.lstate
	if lstate != null and lstate.gifts != null:
		var best := INF
		var feet := Vector3(_world.ctl.x, _world.ctl.y, _world.ctl.z)
		for i in lstate.gifts.slots.size():
			if not lstate.gifts.present(i):
				continue
			var p: Vector3 = lstate.gifts.slot_pos(i)
			var d: float = p.distance_to(feet)
			if d < best:
				best = d
				target = p
				found = true
	if not found:
		return
	var saved_pos := cam.global_position
	var saved_look := cam.global_transform
	cam.global_position = target + Vector3(2.2, 1.6, 2.2)
	cam.look_at(target, Vector3.UP)
	await process_frame
	await _shot("app_02")
	cam.global_transform = saved_look
	cam.global_position = saved_pos


## Orthographic overview of the whole level, so the tile texture reads at a glance.
func _shot_overview() -> void:
	var cam: Camera3D = _world.camera
	if cam == null:
		return
	var saved := cam.global_transform
	var saved_fov := cam.fov
	var saved_proj := cam.projection
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 140.0
	cam.global_position = Vector3(0.5, 90.0, 0.5)
	cam.look_at(Vector3(0.5, 0.0, 0.5), Vector3(0.0, 0.0, -1.0))
	await process_frame
	await _shot("app_03")
	cam.projection = saved_proj
	cam.fov = saved_fov
	cam.global_transform = saved


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
	if _world != null:
		_world.teardown()
		_world.queue_free()
		_world = null
	if _fail != "":
		print("SHOTAPP FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTAPP OK")
	quit(0)
