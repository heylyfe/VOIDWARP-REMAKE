extends RefCounted
#
# Camera-collision tests: the third-person rig must pull in when geometry is between the
# pivot and the camera, and return to the exact configured offset when the way is clear.
# Split the way the ticket asks:
#   1. the pull DECISION, pure — camera_distance(desired, hit) / next_pull_distance(current,
#      target, dt): trivially testable with no SceneTree at all. This is where the logic
#      lives.
#   2. the SWEEP, pure but geometric — camera_hit_distance marches a sphere through a
#      collision table built by sim/collision.gd's make_world (the same Dictionary the game
#      uses, hand-built here: bridge overhead, tunnel wall behind, prop, removed tile).
#      Still no SceneTree needed.
#   3. the WIRING through a REAL world (test_app_flow's seam — world.build() without a
#      SceneTree): world.gd's own built rig discovers its parent's `w`, an injected overhead
#      slab shrinks the camera distance, clear air returns it EXACTLY to the configured
#      offset (bit-for-bit the pre-change position), and mouse-look yaw still turns the rig.
#
# The mouse-lock state machine has its own file (test_mouse_lock.gd); nothing here weakens it.

const CameraScript := preload("res://app/camera_rig.gd")
const CollisionScript := preload("res://sim/collision.gd")
const WorldScript := preload("res://app/world.gd")

const DT := 1.0 / 60.0
const SEED := 1
const LEVEL := 1


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_test_pull_decision())
	failures.append_array(_test_pull_spring())
	failures.append_array(_test_sweep_synthetic())
	failures.append_array(_test_real_world_wiring())
	failures.append_array(_test_mouse_look_still_turns())
	return failures


func _test_pull_decision() -> Array[String]:
	var f: Array[String] = []
	# Clear air: hit = NO_HIT, or a hit at/beyond the desired distance, or exactly at it.
	if CameraScript.camera_distance(7.0, CameraScript.NO_HIT) != 7.0:
		f.append("no hit must use the full desired distance")
	if CameraScript.camera_distance(7.0, 7.5) != 7.0:
		f.append("a hit at 7.5 (beyond desired 7.0) must use the full distance")
	if CameraScript.camera_distance(7.0, 7.0) != 7.0:
		f.append("a hit exactly at the desired distance must use the full distance")
	if CameraScript.camera_distance(7.0, -0.5) != 7.0:
		f.append("a negative hit distance must be treated as no hit")
	# A real hit pulls in by the skin, and never below the floor.
	if absf(CameraScript.camera_distance(7.0, 3.5) - 3.35) > 1e-9:
		f.append("hit at 3.5 must pull to 3.35 (skin 0.15), got %f"
				% CameraScript.camera_distance(7.0, 3.5))
	if CameraScript.camera_distance(7.0, 0.4) != CameraScript.PULL_MIN:
		f.append("hit at 0.4 must clamp to PULL_MIN, got %f"
				% CameraScript.camera_distance(7.0, 0.4))
	if CameraScript.camera_distance(7.0, 0.0) != CameraScript.PULL_MIN:
		f.append("touch at the pivot itself must clamp to PULL_MIN")
	# Monotone non-decreasing and in range for every hit between the pivot and the camera.
	var prev := 0.0
	var t := 0.0
	while t <= 7.0:
		var d := CameraScript.camera_distance(7.0, t)
		if d < prev - 1e-9 or d < CameraScript.PULL_MIN - 1e-9 or d > 7.0:
			f.append("camera_distance(hit=%f) = %f: not monotone in [PULL_MIN, desired]"
					% [t, d])
			return f
		prev = d
		t += 0.05
	return f


func _test_pull_spring() -> Array[String]:
	var f: Array[String] = []
	# Pull-in snaps at any dt: a wall between the camera and the player gets no clipped frame.
	if CameraScript.next_pull_distance(7.0, 2.0, DT) != 2.0:
		f.append("pull-in must snap: (7 -> 2, one tick) gave %f"
				% CameraScript.next_pull_distance(7.0, 2.0, DT))
	if CameraScript.next_pull_distance(7.0, 2.0, 0.0) != 2.0:
		f.append("pull-in must snap even at dt = 0")
	# Return eases and lands exactly on the target: the clear rig must sit at the configured
	# offset, not 6.999...
	var cur := 2.0
	var last := cur
	for i in 400:
		cur = CameraScript.next_pull_distance(cur, 7.0, DT)
		if cur < last - 1e-9:
			f.append("the return eased backwards (%f after %f)" % [cur, last])
			return f
		last = cur
	if cur != 7.0:
		f.append("the return must land exactly on 7.0, still at %f" % cur)
	# dt = 0 is a no-op on the return.
	if CameraScript.next_pull_distance(2.0, 7.0, 0.0) != 2.0:
		f.append("return at dt = 0 must not move")
	# And the steady clear case holds the full distance exactly.
	if CameraScript.next_pull_distance(7.0, 7.0, DT) != 7.0:
		f.append("the clear steady state must hold 7.0 exactly")
	return f


func _test_sweep_synthetic() -> Array[String]:
	var f: Array[String] = []
	# Clear void: no tiles, no props at all.
	var void_world := CollisionScript.make_world([], [], [])
	if CameraScript.camera_hit_distance(void_world, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0) != CameraScript.NO_HIT:
		f.append("sweep in clear void must report NO_HIT")
	# A floor BELOW the pivot (top 2.0, pivot 2.5) does not block a level camera ray.
	var floor_world := CollisionScript.make_world([[0, 0, 4, 0, 0]], [], [])
	if CameraScript.camera_hit_distance(floor_world, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0) != CameraScript.NO_HIT:
		f.append("a slab 0.5 u below the pivot must not block a level ray")
	_print_bridge(f)
	_print_wall(f)
	_print_prop(f)
	_print_removed(f)
	return f


func _print_bridge(f: Array[String]) -> void:
	# Under a bridge: one slab, top 4.0 (tile y=8), box [3.0, 4.0]; pivot at 2.5 under it.
	# Straight up, the sphere (r 0.25) first touches at 3.0 - 0.25 = 2.75 -> hit ~ 0.25.
	var w := CollisionScript.make_world([[0, 0, 8, 0, 0]], [], [])
	var hit := CameraScript.camera_hit_distance(w, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 1.0, 0.0), 7.0)
	if absf(hit - 0.25) > 0.02:
		f.append("bridge overhead: hit must be ~0.25, got %f" % hit)
	var d := CameraScript.camera_distance(7.0, hit)
	if d != CameraScript.PULL_MIN:
		f.append("bridge overhead must pull the camera to PULL_MIN, got %f" % d)


func _print_wall(f: Array[String]) -> void:
	# Tunnel wall behind: one slab in the -z column, box y [2.0, 3.0] spanning the pivot's
	# height. Ray from (0.5, 2.5, 0.5) toward -z; the slab at z [-4, -3] is first touched
	# when the sphere's near face reaches z = -3 + 0.25: hit ~ 0.5 - (-2.75) = 3.25.
	var w := CollisionScript.make_world([[0, -4, 6, 0, 0]], [], [])
	var hit := CameraScript.camera_hit_distance(w, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0)
	if absf(hit - 3.25) > 0.02:
		f.append("tunnel wall: hit must be ~3.25, got %f" % hit)
	var d := CameraScript.camera_distance(7.0, hit)
	if absf(d - 3.1) > 0.001:
		f.append("tunnel wall must pull to 3.1 (skin, within the bisection precision), got %f" % d)
	# A DIFFERENT column one cell to the side does not block: the sweep is along the ray.
	var w2 := CollisionScript.make_world([[5, -4, 6, 0, 0]], [], [])
	if CameraScript.camera_hit_distance(w2, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0) != CameraScript.NO_HIT:
		f.append("a slab one column off the ray must not block it")


func _print_prop(f: Array[String]) -> void:
	# A prop behind the player blocks too: box y [2.5, 3.5] over cell (0, -4) -> same 3.25.
	var w := CollisionScript.make_world([], [[0, -4, 5, 2, 0, 0]], [])
	var hit := CameraScript.camera_hit_distance(w, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0)
	if absf(hit - 3.25) > 0.02:
		f.append("prop behind: hit must be ~3.25, got %f" % hit)


func _print_removed(f: Array[String]) -> void:
	# A tile taken out mid-level (the tiles-modified set) stops blocking the camera.
	var w := CollisionScript.make_world([[0, -4, 6, 0, 0]], [], [])
	w["removed"][CollisionScript.tile_key(0, -4, 6)] = true
	if CameraScript.camera_hit_distance(w, Vector3(0.5, 2.5, 0.5),
			Vector3(0.0, 0.0, -1.0), 7.0) != CameraScript.NO_HIT:
		f.append("a removed tile must stop blocking the camera")


func _test_real_world_wiring() -> Array[String]:
	var f: Array[String] = []
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("world failed to build level %d seed %d - cannot test the rig wiring"
				% [LEVEL, SEED])
		world.free()
		return f
	var rig = world.rig
	if rig == null:
		f.append("build() created no rig")
		world.teardown()
		world.free()
		return f
	var feet := Vector3(float(world.ctl.x), float(world.ctl.y), float(world.ctl.z))

	# Clear air HIGH above the level: nothing blocks, so the applier must place the camera
	# at the configured offset BIT-FOR-BIT (the no-obstruction case is unchanged).
	var clear_feet := Vector3(feet.x, feet.y + 60.0, feet.z)
	rig._spring_y = clear_feet.y
	for i in 60:
		rig.update_rig(clear_feet, DT)
	var fx := Vector3(clear_feet.x, rig._spring_y, clear_feet.z)
	var want := CameraScript.camera_position(fx, rig.yaw_deg, rig.pitch_deg)
	if (rig.position as Vector3) != want:
		f.append("clear air: the rig must sit exactly at camera_position, got %s want %s"
				% [str(rig.position), str(want)])
	if rig._pull_distance != CameraScript.DISTANCE:
		f.append("clear air: pull distance must be exactly DISTANCE, got %f"
				% rig._pull_distance)

	# The fixture, still in clear air: inject one slab into the real collision table in the
	# clear column — a box band containing the pivot, so it obstructs from t = 0 at any
	# pitch. Everything is computed through the same table the game plays on.
	rig.pitch_deg = -60.0
	rig.update_rig(clear_feet, DT)
	var piv := Vector3(clear_feet.x, rig._spring_y, clear_feet.z) \
			+ Vector3(0.0, CameraScript.PIVOT_HEIGHT, 0.0)
	var dir := (CameraScript.camera_offset(rig.yaw_deg, rig.pitch_deg)
			/ CameraScript.DISTANCE)
	var key: String = "%d,%d" % [int(floor(clear_feet.x)), int(floor(clear_feet.z))]
	var old_col: Variant = (world.w["cols"] as Dictionary).get(key, null)
	var slab_y: int = int(floor(piv.y * 2.0)) + 1   # top = slab_y * 0.5, box [top-1, top]
	# The `cols` entry format is the sim's own: {"y", "kind", "i"} per tile.
	(world.w["cols"] as Dictionary)[key] = ([{"y": slab_y, "kind": 0, "i": 999999}] as Array)
	var hit_t := CameraScript.camera_hit_distance(world.w, piv, dir, CameraScript.DISTANCE)
	var expect := CameraScript.camera_distance(CameraScript.DISTANCE, hit_t)
	if expect != CameraScript.PULL_MIN:
		f.append("the injected slab did not obstruct from the pivot (hit %f) - fixture broke"
				% hit_t)
		_restore_col(world.w, key, old_col)
		world.teardown()
		world.free()
		return f
	rig.update_rig(clear_feet, DT)
	if float(rig._pull_distance) != expect:
		f.append("obstructed rig must sit at the swept pull distance %f, got %f"
				% [expect, float(rig._pull_distance)])

	# Take the slab back out: the distance eases back and lands EXACTLY on DISTANCE.
	_restore_col(world.w, key, old_col)
	rig.update_rig(clear_feet, DT)
	var after_one := float(rig._pull_distance)
	if after_one <= expect or after_one >= CameraScript.DISTANCE:
		f.append("one tick clear must ease the distance out, in (pull, DISTANCE): %f in (%f, %f)"
				% [after_one, expect, CameraScript.DISTANCE])
	for i in 400:
		rig.update_rig(clear_feet, DT)
	if float(rig._pull_distance) != CameraScript.DISTANCE:
		f.append("the returned rig must sit at exactly DISTANCE, got %f"
				% float(rig._pull_distance))
	var fx2 := Vector3(clear_feet.x, rig._spring_y, clear_feet.z)
	var want2 := CameraScript.camera_position(fx2, rig.yaw_deg, rig.pitch_deg)
	if (rig.position as Vector3) != want2:
		f.append("returned rig must sit exactly at camera_position, got %s want %s"
				% [str(rig.position), str(want2)])

	world.teardown()
	world.free()
	return f


func _restore_col(w: Dictionary, key: String, old_col: Variant) -> void:
	if old_col == null:
		w["cols"].erase(key)
	else:
		w["cols"][key] = old_col


func _test_mouse_look_still_turns() -> Array[String]:
	var f: Array[String] = []
	# End-to-end: apply_mouse still turns the rig node, and the turn happens with collision
	# running (the same world rig, camera pulled in or not).
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL):
		f.append("world failed to build level %d seed %d - cannot test mouse-look"
				% [LEVEL, SEED])
		world.free()
		return f
	var rig = world.rig
	if rig == null:
		f.append("build() created no rig")
		world.teardown()
		world.free()
		return f
	var feet := Vector3(float(world.ctl.x), float(world.ctl.y) + 60.0, float(world.ctl.z))
	rig._spring_y = feet.y
	for i in 60:
		rig.update_rig(feet, DT)
	var yaw0 := float(rig.yaw_deg)
	var np := CameraScript.apply_mouse(yaw0, float(rig.pitch_deg), 100.0, 0.0, 0.12)
	rig.yaw_deg = (np as Vector2).x
	rig.update_rig(feet, DT)
	if absf(float(rig.yaw_deg) - (yaw0 - 100.0 * 0.12)) > 1e-9:
		f.append("apply_mouse must turn the rig yaw by -sens*dx, got %f want %f"
				% [float(rig.yaw_deg), yaw0 - 100.0 * 0.12])
	var want := CameraScript.camera_position(
			Vector3(feet.x, rig._spring_y, feet.z), rig.yaw_deg, rig.pitch_deg)
	if (rig.position as Vector3) != want:
		f.append("after the yaw the rig must sit exactly at camera_position,"
				+ " got %s want %s" % [str(rig.position), str(want)])
	world.teardown()
	world.free()
	return f
