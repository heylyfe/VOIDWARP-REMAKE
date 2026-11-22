extends RefCounted
#
# Player figure animation tests (J5, Parts A+B): the rebuilt part-set .glb (one mesh object
# per limb, joint origin at hip/shoulder/neck) and the procedural pose machinery in
# world.gd, driven from the sim body state in the VIEW pass only:
#   1. the .glb instantiates with the six named limb nodes (LIMB_NAMES) under PlayerBody,
#      all MeshInstance3D (world.gd's _limbs cache depends on the exact names);
#   2. the pose statics: run legs swing symmetrically and arms counter the SAME-SIDE leg,
#      swing amplitude scales with amp, idle is near rest;
#   3. jump (vy > 0) tucks the legs back and pulls the arms back; fall (vy < 0) raises the
#      arms up over the head and differentiates the knees - and the three airborne/idle
#      states are all distinguishable poses;
#   4. a real build() + step() finds every limb and applies a non-zero pose while running:
#      the view reads the sim state and writes only THE NODES, never the sim;
#   5. (J11) the figure's surfaces - in the level AND in the lobby - carry a real,
#      non-default base material that uses the mesh's vertex colours as albedo (the glb
#      carries no material, so without it the surface drew with Godot's default white and
#      the authored palette was never seen). Asserts on material properties and on the
#      mesh's vertex colours - never on a screenshot.
#   6. (D-ANIM-1, the owner's "legs merged into one long wedge" bug) every pose the contact
#      sheet shows - run forward/backward, strafe left/right, diagonal, turn in place, up/down
#      a ramp, up/down 1 HU stairs, jump, land, dash, glide, idle, walk - is driven through
#      the REAL controller on a staged course, and EVERY rendered frame is checked: each bone
#      keeps its rest length and unit scale (no stretched shin), knees never hyperextend and
#      elbows never invert, soles never sit below the floor under them, knees/ankles never
#      enter the torso, the left leg stays on the body's -x side and the right on +x, and the
#      controller trace is byte-identical with the animation pass on and off.

const WorldScript := preload("res://app/world.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")
const Collision := preload("res://sim/collision.gd")
const Locomotion := preload("res://view/player_locomotion.gd")
const Hash := preload("res://sim/state_hash.gd")
const RunState := preload("res://sim/run_state.gd")

const DT := 1.0 / 60.0
const SEED := 1
const LEVEL := 1


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_glb_part_set(f)
	_leg_pose_statics(f)
	_leg_view_pass(f)
	_leg_ability_poses(f)
	_leg_materials(f)
	_leg_render_smoothness(f)
	_leg_gaits(f)
	_leg_sim_purity(f)
	_leg_rigid_geometry(f)
	return f


class MovingWorld extends "res://app/world.gd":
	func _capture_input() -> Dictionary:
		return {"move_x": 0, "move_z": -1, "buttons": 0, "aim_x": 0, "aim_z": -1}


func _leg_render_smoothness(f: Array[String]) -> void:
	var world := MovingWorld.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	if not world.build(SEED, LEVEL):
		f.append("smoothness: world failed to build")
		world.free()
		return
	var previous: Array[Basis] = []
	var peaks: Array[float] = []
	var limbs: Array = world._limbs.duplicate()
	var names: Array = WorldScript.LIMB_NAMES.duplicate()
	var rig = world.get("_leg_rig")
	if rig != null:
		limbs.append_array(rig.forearms + rig.shins + rig.boots)
		names.append_array(["ElbowL", "ElbowR", "KneeL", "KneeR", "BootL", "BootR"])
	for limb in limbs:
		previous.append(limb.global_basis.orthonormalized())
		peaks.append(0.0)
	var idle_frames := 0
	for frame in 120:
		var tick := frame % 2 == 0
		if tick:
			world.step(DT)
		if world.has_method("_process"):
			world.call("_process", DT * 0.5)
		var changed := false
		for i in limbs.size():
			var basis: Basis = limbs[i].global_basis.orthonormalized()
			var angle := previous[i].get_rotation_quaternion().angle_to(
					basis.get_rotation_quaternion())
			if frame >= 20:
				peaks[i] = maxf(peaks[i], angle)
			changed = changed or not basis.is_equal_approx(previous[i])
			previous[i] = basis
		if frame >= 20 and not tick and not changed:
			idle_frames += 1
	print("ANIM 120 Hz peaks (rad) %s, frozen no-tick frames %d/50" % [peaks, idle_frames])
	for i in peaks.size():
		var limit := 0.30 if i < WorldScript.LIMB_NAMES.size() else 0.40
		if peaks[i] >= limit:
			f.append("smoothness: %s changed %.3f rad in one frame" % [names[i], peaks[i]])
	if idle_frames > 0:
		f.append("smoothness: pose froze on %d no-tick frames" % idle_frames)
	world.teardown()
	world.free()


func _leg_gaits(f: Array[String]) -> void:
	var world := MovingWorld.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	if not world.build(SEED, LEVEL):
		f.append("gait: world failed to build")
		world.free()
		return
	var walk := _sample_gait(world, 3.0, 0)
	var run := _sample_gait(world, 9.0, 0)
	var ramp := _sample_gait(world, 3.0, 4)
	var stairs := _sample_gait(world, 3.0, 5)
	print("ANIM walk %s, run %s, ramp %s, stairs %s" % [walk, run, ramp, stairs])
	if run.cadence < walk.cadence * 1.4 or run.stride < walk.stride * 1.3:
		f.append("gait: run cadence and stride must exceed walking")
	if run.arm < walk.arm * 1.4 or run.lean < walk.lean + 0.12 or run.bob < walk.bob * 1.5:
		f.append("gait: running must swing the arms more, lean further and bob higher")
	if ramp.stride > walk.stride * 0.85 or ramp.bob > walk.bob * 0.35:
		f.append("gait: uphill stride and body bob must shrink")
	if ramp.knee < walk.knee + 0.07 or ramp.lift < walk.lift + 0.09:
		f.append("gait: uphill swing must carry the knee and boot higher")
	if ramp.peak_frame_angle > 0.30 or stairs.peak_frame_angle > 0.36:
		f.append("gait: a rising surface caused a single-frame thigh snap")
	for gait in [walk, run, ramp, stairs]:
		if gait.contacts < 5 or gait.slide > 0.015 or gait.sink > 0.005:
			f.append("plant: expected repeated stationary soles above the floor: %s" % gait)
		if gait.swing_bend < gait.plant_bend + 0.35:
			f.append("gait: the knee should straighten on plant and flex during swing: %s" % gait)
	world.teardown()
	world.free()


func _sample_gait(world: MovingWorld, speed: float, surface: int) -> Dictionary:
	var tiles: Array = []
	for x in range(-1, 2):
		for z in range(-30, 1):
			var height := -z - 1 if surface == 4 else (-z if surface == 5 else 0)
			tiles.append([x, z, height, 4 if surface == 4 else 0, 0])
	world.w = Collision.make_world(tiles, [], [])
	world.ctl.C["run_speed"] = speed
	world.ctl.x = 0.5
	world.ctl.z = -1.5
	world.ctl.y = Collision.support_at(world.w, 0.5, -1.5, 0.0, 1.0)
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = -speed
	world.ctl.grounded = true
	# Snap the render history onto the new course and allow the gait to settle.
	world._anim_next.clear()
	world._anim_height = INF
	world._leg_rig.reset_contacts()
	var previous: Array[bool] = [false, false]
	var plants: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var thighs: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var m := {"cadence": 0.0, "stride": 0.0, "contacts": 0, "slide": 0.0,
			"sink": 0.0, "arm": 0.0, "lean": 0.0, "knee": -INF, "lift": 0.0, "bob": 0.0,
			"plant_bend": INF, "swing_bend": 0.0, "peak_frame_angle": 0.0}
	var min_y := INF
	var max_y := -INF
	var advance := 0.0
	for frame in 300:
		if frame % 2 == 0:
			world.ctl.step(DT, world._capture_input(), world.w)
			world._player_pass()
		var phase := world._anim_phase
		world._process(DT * 0.5)
		if frame < 60:
			continue
		advance += fposmod(world._anim_phase - phase, TAU)
		min_y = minf(min_y, world._pose.body_y)
		max_y = maxf(max_y, world._pose.body_y)
		m.arm = maxf(m.arm, absf(world._pose.arm_l))
		m.lean = maxf(m.lean, -float(world._pose.torso))
		for side in 2:
			var basis: Basis = world._limbs[side + 4].basis
			var rotation := basis.get_rotation_quaternion()
			if frame > 60:
				m.peak_frame_angle = maxf(m.peak_frame_angle, thighs[side].angle_to(rotation))
			thighs[side] = rotation
		_measure_feet(world, surface, m, previous, plants)
	m.cadence = advance / TAU / 2.0
	m.stride = speed / m.cadence
	m.bob = max_y - min_y
	return m


func _measure_feet(world: MovingWorld, surface: int, m: Dictionary,
		previous: Array[bool], plants: Array[Vector3]) -> void:
	var rig = world._leg_rig
	for side in 2:
		var boot: MeshInstance3D = rig.boots[side]
		var bounds := boot.get_aabb()
		var sole := boot.to_global(Vector3(0.0, bounds.position.y, 0.0))
		var limb := world._limbs[side + 4] as Node3D
		var shin: MeshInstance3D = rig.shins[side]
		var bend := limb.global_basis.y.angle_to(shin.global_basis.y)
		var planted: bool = rig.stance[side]
		if planted:
			m.plant_bend = minf(m.plant_bend, bend)
			if not previous[side]:
				m.contacts += 1
				plants[side] = sole
			m.slide = maxf(m.slide, sole.distance_to(plants[side]))
			for z in [bounds.position.z, bounds.end.z]:
				var edge := boot.to_global(Vector3(0.0, bounds.position.y, z))
				m.sink = maxf(m.sink, _course_height(surface, edge.z) - edge.y)
		else:
			var hip := limb.to_global(world._limb_mounts[side + 4])
			m.knee = maxf(m.knee, shin.global_position.y - hip.y)
			m.lift = maxf(m.lift, sole.y - _course_height(surface, sole.z))
			m.swing_bend = maxf(m.swing_bend, bend)
		previous[side] = planted


func _course_height(surface: int, z: float) -> float:
	if surface == 4:
		return -z * 0.5
	if surface == 5:
		return -floorf(z) * 0.5
	return 0.0


func _leg_sim_purity(f: Array[String]) -> void:
	var animated := _sim_trace(true, f)
	var disabled := _sim_trace(false, f)
	if animated.size() != 75 or animated != disabled:
		f.append("purity: animation on and off must produce identical controller and hash traces")
	else:
		print("ANIM purity: %d identical tick hashes and controller samples" % animated.size())


func _sim_trace(animated: bool, f: Array[String]) -> Array:
	var world := MovingWorld.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	var trace: Array = []
	if not world.build(SEED, LEVEL):
		world.free()
		return trace
	var state := RunState.new_run(SEED, 1, [])
	state.level_number = LEVEL
	state.level = world.lstate
	for tick in 75:
		world.step(DT)
		var before := _controller_bits(world.ctl)
		var hash_before := Hash.sha256(state)
		if animated:
			world._process(DT * 0.5)
			world._process(DT * 0.5)
		if before != _controller_bits(world.ctl) or hash_before != Hash.sha256(state):
			f.append("purity: rendering mutated the controller or state hash at tick %d" % tick)
			break
		trace.append([hash_before, before])
	world.teardown()
	world.free()
	return trace


func _controller_bits(ctl: RefCounted) -> PackedStringArray:
	var bits := PackedStringArray()
	for value in [ctl.x, ctl.y, ctl.z, ctl.vx, ctl.vy, ctl.vz]:
		bits.append(Hash.bits(value))
	return bits


## Leg 1: the model itself - six limb nodes, every one a MeshInstance3D under PlayerBody.
func _leg_glb_part_set(f: Array[String]) -> void:
	var ps: PackedScene = load("res://assets/models/player_figure.glb")
	if ps == null:
		f.append("leg A: res://assets/models/player_figure.glb failed to load (stale import?)")
		return
	var inst: Node = ps.instantiate()
	var origins := [Vector3(0, 0.80, 0), Vector3(0, 1.40, 0),
			Vector3(-0.34, 1.38, 0), Vector3(0.34, 1.38, 0),
			Vector3(-0.16, 0.85, 0), Vector3(0.16, 0.85, 0)]
	for i in WorldScript.LIMB_NAMES.size():
		var name: String = WorldScript.LIMB_NAMES[i]
		var n = inst.find_child(name, true, false)
		if n == null:
			f.append("leg A: no node named %s in the player .glb" % name)
			continue
		if not (n is MeshInstance3D):
			f.append("leg A: node %s is a %s, expected MeshInstance3D" % [name, n.get_class()])
		elif n.get_parent().name != &"PlayerBody" or not n.position.is_equal_approx(origins[i]):
			f.append("leg A: %s must keep its authored joint origin under PlayerBody" % name)
	_leg_silhouette(f, inst)
	inst.free()


func _leg_silhouette(f: Array[String], inst: Node) -> void:
	var head := inst.find_child("Head", true, false)
	if head == null:
		return
	for part in ["WitchHat", "HatBrim", "Antlers", "HairRuff", "Face"]:
		var mesh := head.get_node_or_null(NodePath(part)) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			f.append("silhouette: Head must carry a %s mesh so it follows the neck pose" % part)
		elif part == "WitchHat" and not is_equal_approx(
				(head as Node3D).position.y + mesh.position.y + mesh.get_aabb().end.y, 1.80):
			f.append("silhouette: the hat must top out at 1.80 u in the rest pose")


## Leg 2+3: the pure pose statics. Angles are radians; the sign convention is that a limb
## hanging along -Y swings its tip BACKWARD for a positive X rotation.
func _leg_pose_statics(f: Array[String]) -> void:
	# Run, full speed: the legs are mirror images, the arms counter their own side (an
	# arm swung the opposite way of the same-side leg), and the swing is real.
	var full_amp := 1.0
	for phase in [0.0, 0.7, 1.9, 3.1, 4.4, 5.5]:
		var p: Dictionary = WorldScript._pose_run(phase, full_amp)
		if not is_equal_approx(float(p["leg_l"]), -float(p["leg_r"])):
			f.append("run legs must mirror at phase %.2f: %s" % [phase, str(p)])
		# arms counter the same-side leg (arm_l against leg_l)
		if not is_equal_approx(float(p["arm_l"]), -0.85 * float(p["leg_l"])):
			f.append("arm_l must counter leg_l at phase %.2f: %s" % [phase, str(p)])
		var mid: Dictionary = WorldScript._pose_run(phase, 0.5)
		if absf(float(mid["leg_l"])) > absf(float(p["leg_l"])) + 1e-9:
			f.append("running slower must shrink the swing at phase %.2f" % phase)
	# amp 0 collapses to a slack pose (no swing leak).
	var p0: Dictionary = WorldScript._pose_run(1.1, 0.0)
	for key in ["torso", "arm_l", "arm_r", "leg_l", "leg_r"]:
		if absf(float(p0[key])) > 1e-9:
			f.append("run at amp 0 must not move %s, got %s" % [key, str(p0[key])])
	# Idle: near rest, everything tiny.
	var idle: Dictionary = WorldScript._pose_idle(0.0)
	for key in idle.keys():
		if absf(float(idle[key])) > 0.15:
			f.append("idle %s of %s rad is not near rest" % [key, str(idle[key])])
	# Airborne states are distinct poses and distinct from standing.
	var jump: Dictionary = WorldScript._pose_jump()
	var fall: Dictionary = WorldScript._pose_fall()
	if not is_equal_approx(float(jump["leg_l"]), float(jump["leg_r"])):
		f.append("jump must keep both legs tucked back (asymmetric legs)")
	for key in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if absf(float(jump[key]) - float(fall[key])) < 0.2:
			f.append("jump and fall %s are too close to be told apart" % key)
	if float(fall["arm_l"]) < 2.0:
		f.append("fall must raise the arms up (flail), got arm_l %s" % str(fall["arm_l"]))
	if float(jump["leg_l"]) <= 0.0 or float(fall["leg_l"]) >= 0.0:
		f.append("jump legs tuck back (+legs) and fall legs trail (-legs), got %s / %s"
				% [str(jump["leg_l"]), str(fall["leg_l"])])


## Leg 4: through a REAL build + step, every limb is found and the view writes only the
## limb nodes. Push the controller airborne and moving with its own public sim API.
func _leg_view_pass(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("leg D: world failed to build level %d seed %d" % [LEVEL, SEED])
		world.free()
		return
	for i in WorldScript.LIMB_NAMES.size():
		if world._limbs[i] == null:
			f.append("leg D: build() did not find limb node %s"
					% WorldScript.LIMB_NAMES[i])
	if not f.is_empty():
		world.teardown()
		world.free()
		return
	# Simulate a run through one step of the view pass (moving velocity, grounded): the
	# limbs must be posed, non-zero, and NOTHING in the sim may read them back.
	world.ctl.vx = 4.5
	world.ctl.grounded = true
	var sim_probe: Array = [float(world.ctl.vx), float(world.ctl.vy), float(world.ctl.vz),
			float(world.ctl.x), float(world.ctl.y), float(world.ctl.z)]
	world._player_pass()
	var posed := 0
	for i in WorldScript.LIMB_NAMES.size():
		var n = world._limbs[i]
		if (n.rotation as Vector3).length() > 0.01:
			posed += 1
	if posed == 0:
		f.append("leg D: no limb was posed while running (the anim pass did not run)")
	# After the pose pass the sim state is untouched.
	var after: Array = [float(world.ctl.vx), float(world.ctl.vy), float(world.ctl.vz),
			float(world.ctl.x), float(world.ctl.y), float(world.ctl.z)]
	if str(after) != str(sim_probe):
		f.append("leg D: the pose pass wrote back into the sim state (%s -> %s)"
				% [str(sim_probe), str(after)])
	world.teardown()
	world.free()

func _leg_ability_poses(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("ability poses: world failed to build")
		world.free()
		return
	var torso := world._limbs[0] as Node3D
	var left := world._limbs[2] as Node3D
	var right := world._limbs[3] as Node3D
	world.ctl.grounded = true
	world.ctl.dash_ticks = 8
	for tick in 12:
		world._player_pass()
	if torso.rotation.x >= -0.5 or left.rotation.x >= -0.95 or right.rotation.x >= -0.95:
		f.append("ability poses: a grounded dash must lean forward and sweep both arms back")
	world.ctl.dash_ticks = 0
	world.ctl.grounded = false
	world.ctl.vy = -1.0
	world.ctl.gliding = true
	for tick in 12:
		world._player_pass()
	if left.rotation.z >= -0.95 or right.rotation.z <= 0.95:
		f.append("ability poses: a glide must spread both arms outward")
	var rest_shoulder: Vector3 = world._limb_rest[2] + world._limb_mounts[2]
	var rest_hip: Vector3 = world._limb_rest[0] + world._limb_mounts[0]
	var shoulder: Vector3 = left.transform * world._limb_mounts[2]
	var expected: Vector3 = torso.transform * world._limb_mounts[0] \
			+ torso.basis * (rest_shoulder - rest_hip)
	if not shoulder.is_equal_approx(expected):
		f.append("ability poses: the raised arm must stay attached to its shoulder")
	world.ctl.gliding = false
	for tick in 20:
		world._player_pass()
	var fall := WorldScript._pose_fall()
	var left_fall := Vector3.DOWN.rotated(Vector3.RIGHT, float(fall["torso"]) + float(fall["arm_l"]))
	var right_fall := Vector3.DOWN.rotated(Vector3.RIGHT, float(fall["torso"]) + float(fall["arm_r"]))
	if (left.basis * Vector3.DOWN).distance_to(left_fall) > 0.08 \
			or (right.basis * Vector3.DOWN).distance_to(right_fall) > 0.08:
		f.append("ability poses: releasing glide must blend back to the fall pose")
	world.teardown()
	world.free()


## Leg 5 (J11): the figure renders through a real, non-default base material - in the
## level AND in the lobby. The .glb carries no material by design, so before the fix every
## surface drew with Godot's default white material and the authored palette colours were
## never seen. Asserts on the actual material properties and on the mesh's vertex colours -
## never on a screenshot.
func _leg_materials(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("leg E: world failed to build level %d seed %d" % [LEVEL, SEED])
		world.free()
		return
	_check_figure_materials(f, world.player_model, "level")
	world.teardown()
	world.free()
	var lp = LobbyPlayerScript.new()
	lp.build(Vector3(0.0, 0.0, 8.0))
	_check_figure_materials(f, lp.model, "lobby")
	lp.free()


## Every surface under the figure: a StandardMaterial3D, unshaded, using the mesh's vertex
## colours as albedo, with the un-tinted white base the palette pass uses; and the mesh must
## actually carry vertex colours ("not the default white").
func _check_figure_materials(f: Array[String], root: Node3D, which: String) -> void:
	if root == null:
		f.append("figure materials: %s figure is null (build failed?)" % which)
		return
	var found := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				found += 1
				var m: Material = mi.get_surface_override_material(s)
				if m == null:
					f.append("figure materials: %s figure surface %d has no base material (renders default white)"
							% [which, s])
					continue
				if not (m is StandardMaterial3D):
					f.append("figure materials: %s figure surface %d base material is %s, want StandardMaterial3D"
							% [which, s, m.get_class()])
					continue
				var sm := m as StandardMaterial3D
				if sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
					f.append("figure materials: %s figure surface %d shading_mode %d, want %d (unshaded)"
							% [which, s, sm.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED])
				if not sm.vertex_color_use_as_albedo:
					f.append("figure materials: %s figure surface %d does not use vertex colours as albedo"
							% [which, s])
				if not sm.albedo_color.is_equal_approx(Color(1.0, 1.0, 1.0)):
					f.append("figure materials: %s figure surface %d albedo %s, want (1,1,1)"
							% [which, s, str(sm.albedo_color)])
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				var col_v: Variant = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR else null
				if not (col_v is PackedColorArray) or (col_v as PackedColorArray).is_empty():
					f.append("figure materials: %s figure surface %d carries no vertex colours" % [which, s])
	if found == 0:
		f.append("figure materials: %s figure has no mesh surfaces" % which)


# --- Leg 6 (D-ANIM-1): rigid limbs on every pose, every frame ----------------------------

const Controller := preload("res://sim/controller.gd")
const GliderView := preload("res://view/glider_view.gd")
const RENDER_DT := 1.0 / 120.0
const LEG_BONE := 0.31           # view/player_locomotion.gd SEGMENT: thigh and shin length
const LENGTH_TOL := 0.002        # u: a bone may not change length by more than this
const FLOOR_TOL := 0.005         # u: a sole corner may not sit lower than this under its floor

## The contact-sheet poses (tools/shot_player_anim.gd draws exactly these). Columns:
## name, kit, speed, move (world x/z input), course, start (x, z), facing yaw (rad), warm-up
## ticks, captured span (s; 0 = one second), action.
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


class StillRig extends Node3D:
	var yaw_deg := 0.0
	var pitch_deg := 0.0


## Stage `pose` on a fresh world: the course's collision, a real controller of the pose's
## kit at the start, a camera-less yaw holder, the figure, its glider, and the limb cache.
## Shared with tools/shot_player_anim.gd, which adds the visible treads and cameras.
static func stage(world: Node, pose: Array) -> Dictionary:
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
		heights[z] = [hu, kind]
	world.w = Collision.make_world(tiles, [], [], {"dais": [0, 0, 0]})
	world.ctl = Controller.new()
	world.ctl.setup(pose[1], Controller.load_constants())
	world.ctl.C["run_speed"] = float(pose[2])
	var start: Vector2 = pose[5]
	var row: Array = heights[floori(start.y)]
	world.ctl.x = start.x
	world.ctl.z = start.y
	world.ctl.y = Collision.tile_top(row[0]) + (0.5 * (1.0 - (start.y - floorf(start.y)))
			if row[1] == 4 else 0.0)
	world.ctl.cur_key = "%d,%d,%d" % [floori(start.x), floori(start.y), row[0]]
	world.ctl.grounded = true
	world.ctl.sync_body()
	var rig := StillRig.new()
	rig.yaw_deg = rad_to_deg(float(pose[6]))
	world.rig = rig
	world.add_child(rig)
	var scene: PackedScene = load(WorldScript.PLAYER_MODEL)
	world.player_model = scene.instantiate()
	WorldScript._apply_player_body_material(world.player_model)
	world.add_child(world.player_model)
	world.glider_view = GliderView.new()
	if world.glider_view.build():
		world.player_model.add_child(world.glider_view)
	else:
		world.glider_view.free()
		world.glider_view = null
	world._cache_player_limbs(world.player_model)
	return heights


## One 60 Hz sim tick through the real controller, then (if animated) the player pass;
## `render` also draws the tick's two 120 Hz render frames.
static func tick(world: Node, pose: Array, jump: bool, ability: bool, animate := true,
		render := false) -> void:
	var held := {"move_x": int(pose[3].x), "move_z": int(pose[3].y), "aim_x": 0, "aim_z": -1,
			"buttons": (Controller.BTN_JUMP if jump else 0) | (Controller.BTN_ABILITY if ability else 0)}
	if pose[9] == "turn":
		world.rig.yaw_deg = fposmod(world.rig.yaw_deg + rad_to_deg(3.0) * RENDER_DT * 2.0, 360.0)
	world.ctl.step(RENDER_DT * 2.0, held, world.w)
	if animate:
		world._player_pass()
		if render:
			world._process(RENDER_DT)
			world._process(RENDER_DT)


## Warm the pose up (for "land", jump and come back down). Returns the ticks spent.
static func warm_up(world: Node, pose: Array, animate := true) -> int:
	var ticks := 0
	for i in int(pose[7]):
		tick(world, pose, i == int(pose[7]) - 30 and pose[9] == "land", false, animate, true)
		ticks += 1
	if pose[9] == "land":
		while not bool(world.ctl.grounded) and ticks < 400:
			tick(world, pose, false, false, animate, true)
			ticks += 1
	return ticks


## The buttons held on render frame `frame` of the captured span.
static func buttons_at(pose: Array, frame: int) -> Array[bool]:
	var action: String = pose[9]
	return [(action == "jump" and frame < 40) or action == "glide", action == "dash" and frame < 4]


func _leg_rigid_geometry(f: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var worst := {}
	for pose in POSES:
		var world = WorldScript.new()
		tree.root.add_child(world)
		world.set_process(false)
		stage(world, pose)
		var rig = world._leg_rig
		if rig == null or rig.shins.size() != 2 or rig.boots.size() != 2 or rig.forearms.size() != 2:
			f.append("rigid %s: the leg/arm rig was not built" % pose[0])
			world.free()
			continue
		var arm_rest: Array[float] = []
		for side in 2:
			# pose_arm hangs the forearm one upper-arm length below the shoulder mount
			arm_rest.append((world._limbs[side + 2] as MeshInstance3D).get_aabb().size.y)
		var ticks: int = warm_up(world, pose)
		var span: float = pose[8] if float(pose[8]) > 0.0 else 1.0
		var faults := {}
		var frames := int(round(span / RENDER_DT))
		for frame in frames:
			if frame % 2 == 0:
				var held: Array[bool] = buttons_at(pose, frame)
				tick(world, pose, held[0], held[1])
				ticks += 1
			world._process(RENDER_DT)
			_check_frame(world, arm_rest, faults)
		for kind in faults.keys():
			var entry: Array = faults[kind]
			f.append("rigid %s: %s in %d limb checks over %d frames (worst %.4f)" % [pose[0], kind, entry[0],
					frames, entry[1]])
			worst[kind] = maxf(float(worst.get(kind, 0.0)), float(entry[1]))
		world.free()
		# Animation OFF: the same inputs must leave the controller bit-identical.
		if not _same_sim_without_animation(pose, ticks, tree):
			f.append("rigid %s: the controller trace differs with the animation pass off" % pose[0])
	print("ANIM rigid geometry: %d poses checked every render frame, worst faults %s"
			% [POSES.size(), worst])


func _fault(faults: Dictionary, kind: String, amount: float) -> void:
	var entry: Array = faults.get(kind, [0, 0.0])
	faults[kind] = [entry[0] + 1, maxf(entry[1], amount)]


func _check_frame(world, arm_rest: Array[float], faults: Dictionary) -> void:
	var rig = world._leg_rig
	var model: Node3D = world.player_model
	var torso: MeshInstance3D = world._limbs[0]
	var torso_box := torso.get_aabb().grow(-0.01)
	var torso_inv := torso.global_transform.affine_inverse()
	var right := model.global_basis.x.normalized()
	var ankles: Array[Vector3] = []
	var knees: Array[Vector3] = []
	for side in 2:
		var thigh: MeshInstance3D = world._limbs[side + 4]
		var shin: MeshInstance3D = rig.shins[side]
		var boot: MeshInstance3D = rig.boots[side]
		var hip := thigh.to_global(world._limb_mounts[side + 4])
		var knee := shin.global_position
		var ankle := boot.global_position
		knees.append(knee)
		ankles.append(ankle)
		# 1. constant bone lengths and unit scale (the stretched-shin wedge fails here).
		var stretch := maxf(absf(hip.distance_to(knee) - LEG_BONE), absf(knee.distance_to(ankle) - LEG_BONE))
		if stretch > LENGTH_TOL:
			_fault(faults, "leg bone length changed", stretch)
		for part in [thigh, shin, boot]:
			var scale := (part as Node3D).global_basis.get_scale()
			var off := (scale - Vector3.ONE).abs()
			var worst_axis := maxf(off.x, maxf(off.y, off.z))
			if worst_axis > 0.001:
				_fault(faults, "leg segment scaled", worst_axis)
		# 2. the knee flexes, never hyperextends backwards (hinge across the body's right).
		var thigh_dir := (knee - hip).normalized()
		var shin_dir := (ankle - knee).normalized()
		var flex := thigh_dir.angle_to(shin_dir)
		var hinge := -thigh_dir.cross(shin_dir).dot(right)
		if flex > 0.02 and hinge < -0.01:
			_fault(faults, "knee hyperextended", -hinge)
		if flex > 2.75:
			_fault(faults, "knee folded past its limit", flex)
		# 3. no sole corner below the floor under it.
		var box := boot.get_aabb()
		for x in [box.position.x, box.end.x]:
			for z in [box.position.z, box.end.z]:
				var corner := boot.to_global(Vector3(x, box.position.y, z))
				var ground := Locomotion.tile_height(world.w, corner, corner.y + 0.3)
				if ground != -INF and corner.y < ground - FLOOR_TOL:
					_fault(faults, "sole below the floor", ground - corner.y)
		# 4. knee and ankle stay out of the torso block (1 cm in from its faces); the shin's
		# midpoint may graze the leaning block's lower front edge by up to 3 cm, the
		# thickness of the thigh that already enters the torso at the hip by design.
		for point in [knee, ankle]:
			if torso_box.has_point(torso_inv * point):
				_fault(faults, "leg inside the torso", 1.0)
		if torso.get_aabb().grow(-0.03).has_point(torso_inv * knee.lerp(ankle, 0.5)):
			_fault(faults, "shin through the torso", 1.0)
	# 5. the left leg stays on the body's -x side, the right on +x (no swap, no crossing).
	var root := model.global_position
	for side in 2:
		var side_sign := -1.0 if side == 0 else 1.0
		for point in [ankles[side], knees[side]]:
			var lateral: float = (point - root).dot(right) * side_sign
			if lateral <= 0.0:
				_fault(faults, "leg crossed the body midline", -lateral)
	# Arms: the forearm hangs from the elbow at its rest distance with unit scale, and the
	# elbow only flexes forward.
	for side in 2:
		var upper: MeshInstance3D = world._limbs[side + 2]
		var fore: MeshInstance3D = rig.forearms[side]
		var shoulder := upper.to_global(world._limb_mounts[side + 2])
		var elbow := fore.global_position
		var bone := absf(shoulder.distance_to(elbow) - arm_rest[side])
		if bone > LENGTH_TOL:
			_fault(faults, "arm bone length changed", bone)
		var scale := fore.global_basis.get_scale()
		var off := (scale - Vector3.ONE).abs()
		if maxf(off.x, maxf(off.y, off.z)) > 0.001:
			_fault(faults, "forearm scaled", maxf(off.x, maxf(off.y, off.z)))
		var upper_dir := -upper.global_basis.y.normalized()
		var fore_dir := -fore.global_basis.y.normalized()
		if upper_dir.angle_to(fore_dir) > 0.02 \
				and upper_dir.cross(fore_dir).dot(upper.global_basis.x.normalized()) < -0.01:
			_fault(faults, "elbow inverted", 1.0)


## Re-run the pose's inputs without any animation pass; the controller must match the
## animated run's final state bit for bit (and the pose cannot have fed back into the sim).
func _same_sim_without_animation(pose: Array, ticks: int, tree: SceneTree) -> bool:
	var traces: Array = []
	for animate in [true, false]:
		var world = WorldScript.new()
		tree.root.add_child(world)
		world.set_process(false)
		stage(world, pose)
		var trace := PackedStringArray()
		var spent: int = warm_up(world, pose, animate)
		var frame := 0
		while spent < ticks:
			var held: Array[bool] = buttons_at(pose, frame)
			tick(world, pose, held[0], held[1], animate)
			if animate:
				world._process(RENDER_DT)
				world._process(RENDER_DT)
			frame += 2
			spent += 1
			trace.append_array(_controller_bits(world.ctl))
			trace.append("%s|%s|%d" % [world.ctl.grounded, world.ctl.gliding, world.ctl.dash_ticks])
		traces.append(trace)
		world.free()
	return traces[0] == traces[1] and not (traces[0] as PackedStringArray).is_empty()
