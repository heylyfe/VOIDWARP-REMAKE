extends SceneTree
#
# Biome screenshot tool (ticket T-054; DESIGN.md section 10 + TERRAIN_SPEC section 12).
# Windowed run - rendering needs a GPU context, never --headless:
#
#   <godot> --path game --script res://tools/shot_biomes.gd
#
# Renders ONE screenshot per act biome (seed 7, the act's final level) into game/shots/:
#   biome_deepwater.png   level 6   (act I)
#   biome_verdigris.png   level 12  (act II)
#   biome_violet_hour.png level 18  (act III)
#   biome_indigo_trench.png level 24 (act IV)
#   biome_pale_abyss.png  level 30  (act V)
# The environment is configured through view/fog_env.gd's biome_id_for_level(level) - the act ->
# biome wiring under test - not through a hardcoded biome id. Camera: the shot.gd view 3 framing
# (0, 90, 0) u, orthographic, 140 u wide, looking down - the palette-readable gallery framing.
# Prints "MESH ..." per build,
# "SHOT <path>" per written PNG, and "SHOTS 5 written OK"; exits 0 only when all 5 PNGs were
# written.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const FogEnvScript := preload("res://view/fog_env.gd")

const SEED := 7
const LEVELS := [6, 12, 18, 24, 30]
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
	for level in LEVELS:
		var L: Dictionary = VoidGenScript.generate(SEED, int(level))
		if L.is_empty():
			_fail = "generator failed for seed %d level %d" % [SEED, int(level)]
			break
		var biome: String = FogEnvScript.biome_id_for_level(int(level))
		env.configure(biome, int(level))
		for ch in holder.get_children():
			ch.queue_free()
		await process_frame
		var built: Dictionary = MesherScript.build(L)
		print("MESH seed=%d level=%d biome=%s tris=%d build_ms=%d" % [SEED, int(level), biome, int(built["triangles"]), int(built["ms"])])
		for mn in built["meshes"]:
			var mi := MeshInstance3D.new()
			mi.mesh = built["meshes"][mn]
			holder.add_child(mi)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = 140.0
		cam.look_at_from_position(Vector3(0.0, 90.0, 0.0), BEACON_TARGET, Vector3(0.0, 0.0, -1.0))
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var path := shots_dir.path_join("biome_%s.png" % biome)
		var err := img.save_png(path)
		if err != OK:
			_fail = "save_png failed for %s (error %d)" % [path, err]
			break
		print("SHOT %s" % path)
	if _fail == "":
		print("SHOTS 5 written OK")
		quit(0)
	else:
		print("SHOTS FAILED: %s" % _fail)
		quit(1)