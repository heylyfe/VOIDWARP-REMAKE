extends SceneTree
#
# Screenshot tool (ticket T-011; FLEET_PACK section 4). Windowed run - rendering needs a GPU
# context, never --headless:
#
#   <godot> --path game --script res://tools/shot.gd
#
# Renders the 4 fixed camera views of the gallery seeds 1@1, 7@12 and 7@30 into game/shots/:
#   view 1  from (0, 40, 40) u, perspective FOV 75, looking at the beacon tile
#   view 2  from (40, 25, 0) u, perspective FOV 75, looking at the beacon tile
#   view 3  top-down from (0, 90, 0) u, orthographic, 140 u wide
#   view 4  player's-eye from (6, 3, 6) u on the hub looking along +x, perspective FOV 75
# Node setup: FogEnvScript (fog_env.gd) + one MeshInstance3D per level mesh, camera on the root
# Window viewport. Prints "MESH ..." per build and "SHOT <path>" per written screenshot; exits 0
# only when all 12 PNGs were written.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const FogEnvScript := preload("res://view/fog_env.gd")

const CASES := [[1, 1], [7, 12], [7, 30]]
const SHOT_SIZE := Vector2i(1280, 720)
const BEACON_TARGET := Vector3(0.5, 0.5, 0.5)   # tile (0,0) top surface centre (beacon at [0,0,1])

var _fail := ""


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var shots_dir: String = ProjectSettings.globalize_path("res://shots")
	var mk := DirAccess.make_dir_recursive_absolute(shots_dir)
	if mk != OK:
		_fail = "cannot create %s (DirAccess error %d)" % [shots_dir, mk]
		quit(1)
		return
	var env: WorldEnvironment = FogEnvScript.new()
	root.add_child(env)
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	cam.make_current()
	for c in CASES:
		var seed: int = int(c[0])
		var level: int = int(c[1])
		var L: Dictionary = VoidGenScript.generate(seed, level)
		if L.is_empty():
			_fail = "generator failed for seed %d level %d" % [seed, level]
			break
		env.configure(FogEnvScript.biome_id_for_level(level), level)
		for ch in holder.get_children():
			ch.queue_free()
		await process_frame
		var built: Dictionary = MesherScript.build(L)
		print("MESH seed=%d level=%d tris=%d build_ms=%d" % [seed, level, int(built["triangles"]), int(built["ms"])])
		for mn in built["meshes"]:
			var mi := MeshInstance3D.new()
			mi.mesh = built["meshes"][mn]
			holder.add_child(mi)
		for v in range(1, 5):
			_place_camera(cam, v)
			await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			var path := shots_dir.path_join("seed%d_lv%d_view%d.png" % [seed, level, v])
			var err := img.save_png(path)
			if err != OK:
				_fail = "save_png failed for %s (error %d)" % [path, err]
				break
			print("SHOT %s" % path)
		if _fail != "":
			break
	if _fail == "":
		print("SHOTS 12 written OK")
		quit(0)
	else:
		print("SHOTS FAILED: %s" % _fail)
		quit(1)


func _place_camera(cam: Camera3D, v: int) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if v == 3 else Camera3D.PROJECTION_PERSPECTIVE
	match v:
		1:
			cam.position = Vector3(0.0, 40.0, 40.0)
			cam.look_at_from_position(Vector3(0.0, 40.0, 40.0), BEACON_TARGET)
		2:
			cam.look_at_from_position(Vector3(40.0, 25.0, 0.0), BEACON_TARGET)
		3:
			cam.keep_aspect = Camera3D.KEEP_WIDTH
			cam.size = 140.0
			cam.look_at_from_position(Vector3(0.0, 90.0, 0.0), BEACON_TARGET, Vector3(0.0, 0.0, -1.0))
		_:
			cam.look_at_from_position(Vector3(6.0, 3.0, 6.0), Vector3(7.0, 3.0, 6.0))
