extends SceneTree
## Windowed only. Pass an absolute output directory after --.
## <godot> --path game --script res://tools/shot_player_anim.gd -- <out_dir>

const World := preload("res://app/world.gd")
const Controller := preload("res://sim/controller.gd")
const Collision := preload("res://sim/collision.gd")
const FRAME := 1.0 / 120.0
const SHOTS := 18
const SPACING := 4
const WARMUP := 30

var _out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.size() != 1 or not args[0].is_absolute_path():
		push_error("Use a windowed run and pass one absolute output directory.")
		quit(1)
		return
	_out_dir = args[0]
	var error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if error != OK:
		push_error("Cannot create %s (%d)" % [_out_dir, error])
		quit(1)
		return
	root.size = Vector2i(1120, 630)
	for clip in [["walk", 3.0, false], ["run", 9.0, false], ["ramp", 3.0, true]]:
		if not await _capture(clip[0], clip[1], clip[2]):
			quit(1)
			return
	print("SHOTANIM OK (%d frames)" % (3 * SHOTS))
	quit()


func _capture(label: String, speed: float, uphill: bool) -> bool:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	_build_stage(world, speed, uphill)
	var input := {"move_x": 0, "move_z": -1, "buttons": 0, "aim_x": 0, "aim_z": -1}
	for frame in range(WARMUP + SHOTS * SPACING):
		if frame % 2 == 0:
			world.ctl.step(FRAME * 2.0, input, world.w)
			world._player_pass()
		world._process(FRAME)
		if frame < WARMUP or (frame - WARMUP) % SPACING != 0:
			continue
		await process_frame
		await RenderingServer.frame_post_draw
		@warning_ignore("integer_division")
		var index := (frame - WARMUP) / SPACING
		var path := _out_dir.path_join("%s_%02d.png" % [label, index])
		var image := root.get_texture().get_image()
		if image == null or image.save_png(path) != OK:
			push_error("Failed to capture %s" % path)
			world.free()
			return false
		print("SHOT %s" % path)
	world.free()
	return true


func _build_stage(world: World, speed: float, uphill: bool) -> void:
	var tiles: Array = []
	for z in range(-14, 0):
		var hu := -z - 1 if uphill else 0
		for x in range(-1, 2):
			tiles.append([x, z, hu, 4 if uphill else 0, 0])
		_add_tread(world, z, hu, uphill)
	world.w = Collision.make_world(tiles, [], [], {"dais": [0, -1, 0]})
	world.ctl = Controller.new()
	world.ctl.setup("dasher", Controller.load_constants())
	world.ctl.C["run_speed"] = speed
	world.ctl.place(world.w)
	world.ctl.y = Collision.support_at(world.w, world.ctl.x, world.ctl.z, 0.0, 1.0)
	world.ctl.grounded = true
	world.ctl.vz = -speed
	var scene: PackedScene = load(World.PLAYER_MODEL)
	world.player_model = scene.instantiate()
	world._apply_player_body_material(world.player_model)
	world.add_child(world.player_model)
	world._cache_player_limbs(world.player_model)
	var background := WorldEnvironment.new()
	background.environment = Environment.new()
	background.environment.background_mode = Environment.BG_COLOR
	background.environment.background_color = Color("#191d2b")
	world.add_child(background)
	var center_z := -0.5 - speed * 0.52
	var center_y := 0.72 - (center_z * 0.5 if uphill else 0.0)
	var target := Vector3(0.6, center_y, center_z)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.85
	world.add_child(camera)
	camera.position = target + Vector3(7.0, 1.7, -1.0)
	camera.look_at(target)
	camera.make_current()


func _add_tread(world: Node3D, z: int, hu: int, uphill: bool) -> void:
	var part := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(3.0, 0.26, sqrt(1.25) if uphill else 1.0)
	part.mesh = slab
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#444e67") if z % 2 == 0 else Color("#515d77")
	part.material_override = material
	part.rotation.x = atan(0.5) if uphill else 0.0
	part.position = Vector3(0.5, hu * 0.5 + (0.25 if uphill else 0.0), z + 0.5) \
			- part.basis.y * 0.13
	world.add_child(part)
