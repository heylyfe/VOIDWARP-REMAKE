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

const WorldScript := preload("res://app/world.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")

const DT := 1.0 / 60.0
const SEED := 1
const LEVEL := 1


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_glb_part_set(f)
	_leg_pose_statics(f)
	_leg_view_pass(f)
	_leg_materials(f)
	return f


## Leg 1: the model itself - six limb nodes, every one a MeshInstance3D under PlayerBody.
func _leg_glb_part_set(f: Array[String]) -> void:
	var ps: PackedScene = load("res://assets/models/player_figure.glb")
	if ps == null:
		f.append("leg A: res://assets/models/player_figure.glb failed to load (stale import?)")
		return
	var inst: Node = ps.instantiate()
	for name in WorldScript.LIMB_NAMES:
		var n = inst.find_child(name, true, false)
		if n == null:
			f.append("leg A: no node named %s in the player .glb" % name)
			continue
		if not (n is MeshInstance3D):
			f.append("leg A: node %s is a %s, expected MeshInstance3D" % [name, n.get_class()])
	inst.free()


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
