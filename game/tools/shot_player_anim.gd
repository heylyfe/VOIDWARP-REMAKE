extends SceneTree
## Player locomotion CONTACT SHEET (view-side proof for the run cycle, D-ANIM-1). Windowed
## only (rendering needs a GPU context); pass ONE absolute output directory after --:
##
##   <godot> --path game --script res://tools/shot_player_anim.gd -- <abs_out_dir> [pose]
##
## Every pose runs the REAL controller (sim/controller.gd) on a staged course and the REAL
## world.gd animation pass, then captures labelled frames from three fixed-offset cameras:
## a side-on view (the gait), a rear three-quarter view (the owner's angle; legs crossing
## or swapping shows here) and a third view per pose (_third_view: "downhill" for descents,
## "xray" with a see-through torso for climbs, else "front"). Writes
## <out>/<pose>/<view>_NN.png and a labelled sheet <out>/sheet_<pose>.png (rows: side, rear,
## third view). The land sheet carries a red bar at the running hip height. Cyclic poses
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
const NARROW_LAYER := 2         # render layer of the narrow sloped course (side, third, climb rear)
const WIDE_LAYER := 4           # render layer of the full-width sloped course (descent rear)
## Poses whose legs are drawn in proof colours (_leg_tint). The body material is UNSHADED
## vertex colour (world.gd _player_body_material), so a light cannot help: the robe hem,
## the thighs, the shins and the boots are all near-black and merge into one shape on the
## sheet (review of 3a77375 - no knee, no boot edge, no left/right in the descent rear
## views or the jump tuck). The tint is a material_override on the shot's own figure only.
const LEG_TINT_POSES := ["down_ramp", "down_stairs", "jump", "land"]
## [thigh, shin, boot] per side: left warm, right cool; each segment a different value, so
## the knee and the ankle are colour edges and the two feet never share a colour.
const LEG_TINT := [
	[Color("#ffb066"), Color("#e2701e"), Color("#7a2e00")],
	[Color("#8fe8ff"), Color("#1ea7d6"), Color("#004a78")],
]

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
	["land", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.50, "land"],
	["dash", "dasher", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.30, "dash"],
	["glide", "glider", 9.0, Vector2(0, -1), "flat", Vector2(0.5, 8.5), 0.0, 40, 0.90, "glide"],
	["idle", "dasher", 9.0, Vector2.ZERO, "flat", Vector2(0.5, 0.5), 0.0, 30, 3.0, ""],
]

var _out := ""
var _fail := ""
var _label: Label
var _legend: Label


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
	_legend = Label.new()
	_legend.position = Vector2(12, VIEW.y - 44)
	_legend.add_theme_font_size_override("font_size", 20)
	_legend.add_theme_color_override("font_color", Color("#ffe066"))
	_legend.add_theme_color_override("font_outline_color", Color.BLACK)
	_legend.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_legend)
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
	var tinted: bool = name in LEG_TINT_POSES
	if tinted:
		_leg_tint(world)
	_legend.text = "proof tint: L orange, R cyan; thigh > shin > boot" if tinted else ""
	var input := {"move_x": int(pose[3].x), "move_z": int(pose[3].y), "buttons": 0,
			"aim_x": 0, "aim_z": -1}
	var action: String = pose[9]
	var tick := 0
	# Warm-up: the test's own (run up to speed; for "land", jump and stop just before the
	# touchdown), so the sheet and the gate see the same motion.
	tick += AnimTest.warm_up(world, pose)
	var span: float = pose[8]
	if span <= 0.0:
		var gait: Vector3 = Locomotion.profile(float(pose[2]), world._run_speed,
				world._climb_weight, world._side_weight, world._descent_pace)
		span = 1.0 / gait.x
	var frames_total := int(round(span / FRAME))
	var every := maxf(1.0, float(frames_total) / float(FRAMES))
	var cams := _cameras(world, pose)
	var rows: Array = [[], [], []]
	var third := _third_view(name)
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
		for view in 3:
			var cam: Camera3D = cams[view]
			cam.make_current()
			var label: String = ["side", "rear", third][view]
			_label.text = "%s   %s   %02d/%02d" % [name, label, shot + 1, FRAMES]
			# The x-ray view draws the torso (and the arms, which hang in front of the hips
			# from this angle) see-through, so a raised thigh in front of the body, or
			# through it, can be told apart.
			_xray(world, label == "xray")
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := dir.path_join("%s_%02d.png" % [label, shot])
			if image == null or image.save_png(path) != OK:
				_fail = "failed to save %s" % path
				world.free()
				return false
			image.resize(THUMB, THUMB, Image.INTERPOLATE_BILINEAR)
			rows[view].append(image)
		shot += 1
	_xray(world, false)
	world.free()
	return _sheet(name, rows)


func _xray(world: World, on: bool) -> void:
	var parts: Array = [world._limbs[0], world._limbs[2], world._limbs[3]]
	parts.append_array(world._leg_rig.forearms)
	for i in parts.size():
		(parts[i] as GeometryInstance3D).transparency = (0.6 if i == 0 else 0.85) if on else 0.0


## Proof aid, shot tool only: draws each leg's thigh, shin and boot in its own flat colour
## (LEG_TINT) through material_override on this sheet's figure. The game's body material,
## the pose and the sim are untouched; the override only replaces what these MeshInstances
## draw while the sheet is shot (the figure is freed with the world after the pose).
func _leg_tint(world: World) -> void:
	for side in 2:
		var parts: Array = [world._limbs[4 + side]]
		if world._leg_rig.shins.size() == 2:
			parts.append(world._leg_rig.shins[side])
		if world._leg_rig.boots.size() == 2:
			parts.append(world._leg_rig.boots[side])
		for i in parts.size():
			if parts[i] == null:
				continue
			var tint := StandardMaterial3D.new()
			tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tint.albedo_color = LEG_TINT[side][i]
			(parts[i] as GeometryInstance3D).material_override = tint


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
		if course == "flat":
			_add_tread(world, z, hu, kind == 4, false, 1)
		else:
			# Two drawings of a sloped course: the narrow strip for the side and third
			# views (and a climb's rear view), the full-width course for a descent's
			# rear view (_cameras).
			_add_tread(world, z, hu, kind == 4, true, NARROW_LAYER)
			_add_tread(world, z, hu, kind == 4, false, WIDE_LAYER)
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


## One visible tread (collision is the staged tile data, not these meshes). A ramp or
## stair course is DRAWN only 1.2 u wide around the figure's line (the figure is 0.54 u
## wide), so the level side view sees the slope / stair profile as a silhouette with the
## soles on its outline, instead of a wall of treads hiding the feet (the 25 u course of
## the v0.1.13-alpha.3 sheets) or a tread top whose near edge sits below the feet.
## The rear three-quarter view of a DESCENT sees a full-width copy instead (WIDE_LAYER):
## looking down the slope past the figure, the 1.2 u strip was a thin band below the
## boots and the black boots stood dark-on-dark against the empty background (review of
## 1b7bb7d); the wide course puts lit, striped surface behind every foot.
func _add_tread(world: Node3D, z: int, hu: int, ramp: bool, narrow: bool, layer: int) -> void:
	var width := 1.2 if narrow else 25.0
	var part := MeshInstance3D.new()
	var slab := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#444e67") if z % 2 == 0 else Color("#5a6782")
	part.material_override = material
	if ramp:
		slab.size = Vector3(width, 0.26, sqrt(1.25))
		part.rotation.x = atan(0.5)
		part.position = Vector3(0.5, hu * 0.5 + 0.25, z + 0.5) - part.basis.y * 0.13
	else:
		var top := hu * 0.5
		slab.size = Vector3(width, top + 1.0, 1.0)
		part.position = Vector3(0.5, (top - 1.0) * 0.5, z + 0.5)
	part.mesh = slab
	part.layers = layer
	world.add_child(part)
	# Stripes every 1 u across each tread: the stride and a sideways step read against them.
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color("#2a3145")
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.04, 0.01, slab.size.z)
	var half := int(width * 0.5)
	for x in range(-half, half + 1):
		var mark := MeshInstance3D.new()
		mark.mesh = stripe
		mark.material_override = dark
		mark.layers = layer
		mark.transform = part.transform * Transform3D(Basis.IDENTITY,
				Vector3(float(x) - 0.5, slab.size.y * 0.5 + 0.006, 0.0))
		world.add_child(mark)


## The third view of a pose: "downhill" for a descent (low, from the downhill side, so the
## slope or the treads can never hide the feet), "xray" for a climb (high oblique with the
## torso drawn see-through, so a raised thigh's depth against the body reads), else "front".
static func _third_view(name: String) -> String:
	if name in ["down_ramp", "down_stairs"]:
		return "downhill"
	if name in ["up_ramp", "up_stairs"]:
		return "xray"
	return "front"


## Three cameras that hold a fixed offset from the figure (set from the pose's starting
## facing, so a turn in place is seen turning): side-on from the figure's right, a rear
## three-quarter from behind and above (the angle of the owner's bad_leg_pose.png), and the
## pose's third view (_third_view). Ground poses follow the figure's height EXACTLY: a
## lagging camera dropped the feet off the bottom of the frame on a descent (review of
## v0.1.13-alpha.3). Ramps and stairs get a wider frame centred lower, so a foot reaching
## down to the next tread stays in shot.
func _cameras(world: World, pose: Array) -> Array:
	var name: String = pose[0]
	var yaw: float = pose[6]
	var offsets := {
		"downhill": Vector3(2.0, -0.15, -2.8),
		"xray": Vector3(2.7, 1.5, -0.9),
		"front": Vector3(2.0, 0.25, -2.8),
	}
	# On ramps and stairs the side camera is LEVEL with its aim point: with the narrow
	# course the tread and slope profile is then a clean silhouette and a sole on it sits
	# exactly on its outline (a camera looking down drew a sole standing mid-tread below the
	# tread's near edge, so contact could not be judged).
	var sloped: bool = pose[4] != "flat"
	var side := Vector3(3.4, 0.0 if sloped else 0.55, 0.0)
	# A descent's rear camera stands higher (2.7 u over the aim point instead of 1.5): on a
	# 1:2 slope the ground behind the figure rises 1.45 u over the 2.9 u setback, so the
	# 1.5 u camera looked along the slope and the tread just uphill of the figure hid the
	# boots (review of 1b7bb7d). From 2.7 u the sight line drops ~40 deg, clear of the uphill
	# tread edge, and the boots sit against the wide course (_add_tread) below them.
	var descent: bool = name in ["down_ramp", "down_stairs"]
	var rear := Vector3(1.1, 2.7 if descent else 1.5, 2.9)
	var views := [side, rear, offsets[_third_view(name)]]
	# An airborne pose outruns a 2.4 u frame: the arc lifts the figure clean out of the top
	# of the shot. Widen the frame and follow the height with a lag for those poses only.
	var airborne: bool = name in ["jump", "glide"]
	var cams: Array = []
	for index in views.size():
		var offset: Vector3 = views[index]
		var cam := _FollowCam.new()
		cam.figure = world.player_model
		cam.offset = (offset as Vector3).rotated(Vector3.UP, yaw)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 3.8 if airborne else (3.1 if sloped else 2.4)
		cam.lag = 0.80 if airborne else 1.0
		cam.aim = 0.85 if not sloped else 0.70
		# The deployed glider's canopy rides ~1.9 u over the boots: in a 3.8 u frame aimed
		# 0.85 u up it crossed the top edge of every cell from frame 6 on (review of
		# 1b7bb7d). A 4.4 u frame aimed 1.35 u up holds canopy and boots together.
		if name == "glide":
			cam.size = 4.4
			cam.aim = 1.35
		if sloped:
			var wide := descent and index == 1
			cam.cull_mask &= ~(NARROW_LAYER if wide else WIDE_LAYER)
		world.add_child(cam)
		cam.follow()
		cams.append(cam)
	if name == "land":
		_hip_marker(world)
	return cams


## Land: a thin red bar at the running waistline (the torso block's lower edge in a steady
## run), travelling with the figure, so the touchdown drop below it and the recovery back
## up to it can be read off every frame.
func _hip_marker(world: World) -> void:
	var bar := _HipBar.new()
	bar.figure = world.player_model
	var torso := world._limbs[0] as MeshInstance3D
	bar.height = world._limb_rest[0].y + torso.get_aabb().position.y - 0.065 - 0.05
	# A cross (one bar across the figure, one along it), so the side view and the rear
	# view each see a bar edge-on as a horizontal line.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.014, 0.014)
	var along := MeshInstance3D.new()
	var mesh_along := BoxMesh.new()
	mesh_along.size = Vector3(0.014, 0.014, 1.4)
	along.mesh = mesh_along
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ff5a5a")
	material.no_depth_test = true
	bar.mesh = mesh
	bar.material_override = material
	along.material_override = material
	bar.add_child(along)
	world.add_child(bar)


class _HipBar extends MeshInstance3D:
	var figure: Node3D
	var height := 0.0

	func _process(_delta: float) -> void:
		if figure != null:
			position = figure.position + Vector3.UP * height
			rotation.y = figure.rotation.y


class _FollowCam extends Camera3D:
	var figure: Node3D
	var offset := Vector3.ZERO
	var lag := 1.0
	var aim := 0.85
	var _y := INF

	func _process(_delta: float) -> void:
		follow()

	func follow() -> void:
		if figure == null:
			return
		# Follow x/z exactly; height exactly on the ground, with a lag in the air.
		var feet := figure.position
		_y = feet.y if _y == INF else lerpf(_y, feet.y, lag)
		var target := Vector3(feet.x, _y + aim, feet.z)
		position = target + offset
		look_at(target)


func _sheet(name: String, rows: Array) -> bool:
	var sheet := Image.create(THUMB * FRAMES, THUMB * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for row in rows.size():
		for i in (rows[row] as Array).size():
			var image: Image = rows[row][i]
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
					Vector2i(i * THUMB, row * THUMB))
	var path := _out.path_join("sheet_%s.png" % name)
	if sheet.save_png(path) != OK:
		_fail = "failed to save %s" % path
		return false
	print("SHOT %s" % path)
	return true
