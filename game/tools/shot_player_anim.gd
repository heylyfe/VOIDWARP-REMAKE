extends SceneTree
## Player locomotion CONTACT SHEET (view-side proof for the run cycle, D-ANIM-1). Windowed
## only (rendering needs a GPU context); pass ONE absolute output directory after --:
##
##   <godot> --path game --script res://tools/shot_player_anim.gd -- <abs_out_dir> [pose]
##
## Every pose runs the REAL controller (sim/controller.gd) on a staged course and the REAL
## world.gd animation pass, then captures labelled frames from two fixed-offset cameras: a
## side-on view (the gait) and a rear three-quarter view (the owner's angle; legs crossing
## or swapping shows here). Writes <out>/<pose>/side_NN.png, <out>/<pose>/rear_NN.png and a
## labelled sheet <out>/sheet_<pose>.png (top row side, bottom row rear). Cyclic poses
## sample ONE gait cycle in FRAMES frames. Prints "SHOT <path>" per sheet and
## "SHOTANIM OK" / "SHOTANIM FAIL <why>". Named shot_*, so tests/run_all.gd skips it.

const World := preload("res://app/world.gd")
const Controller := preload("res://sim/controller.gd")
const Collision := preload("res://sim/collision.gd")
const Locomotion := preload("res://view/player_locomotion.gd")
const GliderView := preload("res://view/glider_view.gd")
const AnimTest := preload("res://tests/test_player_anim.gd")
const FRAME := 1.0 / 120.0
const FRAMES := 10
const VIEW := Vector2i(640, 640)
const THUMB := 256

## name, kit, speed, move (world x/z input), course, start (x, z), yaw (facing, rad),
## warm (ticks before capture), span (s captured; 0 = one gait cycle), and an optional
## action: "jump" (press at capture start), "land" (jump at warm-up, capture the touchdown),
## "dash", "glide", "turn" (yaw spins 3 rad/s in place).
const POSES := [
	["run_forward", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 50, 0.0, ""],
	["walk_forward", "dasher", 3.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 50, 0.0, ""],
	["run_backward", "dasher", 9.0, Vector2(0, 1), "flat", Vector2(0.5, -8.5), 0.0, 50, 0.0, ""],
	["strafe_left", "dasher", 9.0, Vector2(-1, 0), "flat", Vector2(8.5, 0.5), 0.0, 50, 0.0, ""],
	["strafe_right", "dasher", 9.0, Vector2(1, 0), "flat", Vector2(-8.5, 0.5), 0.0, 50, 0.0, ""],
	["diagonal", "dasher", 9.0, Vector2(1, -1), "flat", Vector2(-6.5, 6.5), 0.0, 50, 0.0, ""],
	["turn_in_place", "dasher", 9.0, Vector2.ZERO, "flat", Vector2(0.5, 0.5), 0.0, 40, 1.2, "turn"],
	["up_ramp", "dasher", 9.0, Vector2(0, -1), "ramp", Vector2(0.5, 1.5), 0.0, 44, 0.0, ""],
	["down_ramp", "dasher", 9.0, Vector2(0, 1), "ramp", Vector2(0.5, -16.5), PI, 44, 0.0, ""],
	["up_stairs", "dasher", 9.0, Vector2(0, -1), "stairs", Vector2(0.5, 1.5), 0.0, 44, 0.0, ""],
	["down_stairs", "dasher", 9.0, Vector2(0, 1), "stairs", Vector2(0.5, -16.5), PI, 44, 0.0, ""],
	["jump", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.75, "jump"],
	["land", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.45, "land"],
	["dash", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.30, "dash"],
	["glide", "glider", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.90, "glide"],
	["idle", "dasher", 9.0, Vector2.ZERO, "flat", Vector2(0.5, 0.5), 0.0, 30, 3.0, ""],
]

var _out := ""
var _fail := ""
var _label: Label


class StillRig extends Node3D:
	var yaw_deg := 0.0
	var pitch_deg := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty() or not args[0].is_absolute_path():
		_finish("use a windowed run and pass one absolute output directory")
		return
	_out = args[0]
	var only := args[1] if args.size() > 1 else ""
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_finish("cannot create %s" % _out)
		return
	root.size = VIEW
	var overlay := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color("#ffe066"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_label)
	root.add_child(overlay)
	var shots := 0
	for pose in POSES:
		if only != "" and pose[0] != only:
			continue
		if not await _capture(pose):
			_finish(_fail)
			return
		shots += 1
	_finish("" if shots > 0 else "no pose named %s" % only, shots)


func _finish(why: String, shots := 0) -> void:
	if why == "":
		print("SHOTANIM OK (%d poses, %d frames each view)" % [shots, FRAMES])
		quit(0)
	else:
		push_error(why)
		print("SHOTANIM FAIL %s" % why)
		quit(1)


func _capture(pose: Array) -> bool:
	var name: String = pose[0]
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	var heights := _stage(world, pose)
	var input := {"move_x": int(pose[3].x), "move_z": int(pose[3].y), "buttons": 0,
			"aim_x": 0, "aim_z": -1}
	var action: String = pose[9]
	var tick := 0
	# Warm-up: run up to speed (and for "land", jump and come back down).
	for i in int(pose[7]):
		_tick(world, input, pose, i == int(pose[7]) - 30 and action == "land")
		world._process(FRAME)
		world._process(FRAME)
		tick += 1
	if action == "land":
		var guard := 0
		while not bool(world.ctl.grounded) and guard < 240:
			_tick(world, input, pose, false)
			world._process(FRAME)
			world._process(FRAME)
			guard += 1
	var span: float = pose[8]
	if span <= 0.0:
		var gait: Vector3 = Locomotion.profile(float(pose[2]), world._run_speed,
				world._climb_weight, world._side_weight, world._descent_weight)
		span = 1.0 / gait.x
	var frames_total := int(round(span / FRAME))
	var every := maxf(1.0, float(frames_total) / float(FRAMES))
	var cams := _cameras(world, pose)
	var side_imgs: Array[Image] = []
	var rear_imgs: Array[Image] = []
	var dir := _out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var next := 0.0
	var shot := 0
	for f in frames_total + 1:
		if f % 2 == 0:
			var press := (action == "jump" or action == "glide") and f < 40 \
					or action == "glide" or (action == "dash" and f < 4)
			_tick(world, input, pose, press, action == "dash")
		world._process(FRAME)
		if float(f) + 0.001 < next or shot >= FRAMES:
			continue
		next += every
		for view in 2:
			var cam: Camera3D = cams[view]
			cam.make_current()
			_label.text = "%s   %s   %02d/%02d" % [name, "side" if view == 0 else "rear",
					shot + 1, FRAMES]
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := dir.path_join("%s_%02d.png" % ["side" if view == 0 else "rear", shot])
			if image == null or image.save_png(path) != OK:
				_fail = "failed to save %s" % path
				world.free()
				return false
			image.resize(THUMB, THUMB, Image.INTERPOLATE_BILINEAR)
			(side_imgs if view == 0 else rear_imgs).append(image)
		shot += 1
	world.free()
	return _sheet(name, side_imgs, rear_imgs)


## One 60 Hz sim tick through the real controller, then the world's own player pass.
func _tick(world: World, input: Dictionary, pose: Array, jump: bool, ability := false) -> void:
	var held := input.duplicate()
	held["buttons"] = (Controller.BTN_JUMP if jump else 0) | (Controller.BTN_ABILITY if ability else 0)
	if pose[9] == "turn":
		world.rig.yaw_deg = fposmod(world.rig.yaw_deg + rad_to_deg(3.0) * FRAME * 2.0, 360.0)
	world.ctl.step(FRAME * 2.0, held, world.w)
	world._player_pass()


## The course: flat ground, a 1:2 ramp or 1 HU (0.5 u) stairs rising toward -z.
func _stage(world: World, pose: Array) -> Dictionary:
	var course: String = pose[4]
	var tiles: Array = []
	var heights := {}
	for z in range(-24, 13):
		var hu := 0
		var kind := 0
		if course != "flat" and z < 0:
			hu = -z - 1 if course == "ramp" else -z
			kind = 4 if course == "ramp" else 0
		if course == "ramp" and z <= -20:
			hu = 19
			kind = 0
		for x in range(-12, 13):
			tiles.append([x, z, hu, kind, 0])
		heights[z] = hu
		_add_tread(world, z, hu, kind == 4)
	world.w = Collision.make_world(tiles, [], [], {"dais": [0, 0, 0]})
	world.ctl = Controller.new()
	world.ctl.setup(pose[1], Controller.load_constants())
	world.ctl.C["run_speed"] = float(pose[2])
	var start: Vector2 = pose[5]
	world.ctl.x = start.x
	world.ctl.z = start.y
	var hu: int = heights[floori(start.y)]
	world.ctl.y = Locomotion.tile_height(world.w, Vector3(start.x, 0.0, start.y), 100.0)
	world.ctl.cur_key = "%d,%d,%d" % [floori(start.x), floori(start.y), hu]
	world.ctl.grounded = true
	world.ctl.sync_body()
	var rig := StillRig.new()
	rig.yaw_deg = rad_to_deg(float(pose[6]))
	world.rig = rig
	world.add_child(rig)
	var scene: PackedScene = load(World.PLAYER_MODEL)
	world.player_model = scene.instantiate()
	world._apply_player_body_material(world.player_model)
	world.add_child(world.player_model)
	world.glider_view = GliderView.new()
	if world.glider_view.build():
		world.player_model.add_child(world.glider_view)
	else:
		world.glider_view.free()
		world.glider_view = null
	world._cache_player_limbs(world.player_model)
	var background := WorldEnvironment.new()
	background.environment = Environment.new()
	background.environment.background_mode = Environment.BG_COLOR
	background.environment.background_color = Color("#191d2b")
	world.add_child(background)
	return heights


func _add_tread(world: Node3D, z: int, hu: int, ramp: bool) -> void:
	var part := MeshInstance3D.new()
	var slab := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#444e67") if z % 2 == 0 else Color("#5a6782")
	part.material_override = material
	if ramp:
		slab.size = Vector3(25.0, 0.26, sqrt(1.25))
		part.rotation.x = atan(0.5)
		part.position = Vector3(0.5, hu * 0.5 + 0.25, z + 0.5) - part.basis.y * 0.13
	else:
		var top := hu * 0.5
		slab.size = Vector3(25.0, top + 1.0, 1.0)
		part.position = Vector3(0.5, (top - 1.0) * 0.5, z + 0.5)
	part.mesh = slab
	world.add_child(part)
	# Stripes every 1 u across each tread: the stride and a sideways step read against them.
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color("#2a3145")
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.04, 0.01, slab.size.z)
	for x in range(-12, 13):
		var mark := MeshInstance3D.new()
		mark.mesh = stripe
		mark.material_override = dark
		mark.transform = part.transform * Transform3D(Basis.IDENTITY,
				Vector3(float(x) - 0.5, slab.size.y * 0.5 + 0.006, 0.0))
		world.add_child(mark)


## Two cameras that hold a fixed offset from the figure (set from the pose's starting
## facing, so a turn in place is seen turning): side-on from the figure's right, and a rear
## three-quarter from behind and above (the angle of the owner's bad_leg_pose.png).
func _cameras(world: World, pose: Array) -> Array:
	var side := _FollowCam.new()
	var rear := _FollowCam.new()
	var yaw: float = pose[6]
	side.offset = Vector3(3.4, 0.55, 0.0).rotated(Vector3.UP, yaw)
	rear.offset = Vector3(1.1, 1.5, 2.9).rotated(Vector3.UP, yaw)
	for cam in [side, rear]:
		cam.figure = world.player_model
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.4
		world.add_child(cam)
		cam.follow()
	return [side, rear]


class _FollowCam extends Camera3D:
	var figure: Node3D
	var offset := Vector3.ZERO
	var _y := INF

	func _process(_delta: float) -> void:
		follow()

	func follow() -> void:
		if figure == null:
			return
		# Follow x/z exactly; follow height slowly, so a stair climb shows as a climb.
		var feet := figure.position
		_y = feet.y if _y == INF else lerpf(_y, feet.y, 0.08)
		var target := Vector3(feet.x, _y + 0.85, feet.z)
		position = target + offset
		look_at(target)


func _sheet(name: String, side: Array[Image], rear: Array[Image]) -> bool:
	var sheet := Image.create(THUMB * FRAMES, THUMB * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in side.size():
		var s: Image = side[i]
		var r: Image = rear[i]
		s.convert(Image.FORMAT_RGBA8)
		r.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(i * THUMB, 0))
		sheet.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(i * THUMB, THUMB))
	var path := _out.path_join("sheet_%s.png" % name)
	if sheet.save_png(path) != OK:
		_fail = "failed to save %s" % path
		return false
	print("SHOT %s" % path)
	return true
