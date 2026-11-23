extends RefCounted
#
# test_player_gait.gd - the level's idle/walk/run IS the Antechamber's animation (U1).
#
# The owner's ruling: in-game locomotion must be IDENTICAL to the lobby animation, on the
# same R6 blocky figure. view/player_gait.gd is the ONE gait both call sites read, so this
# test compares the ACTUAL posed transforms of the two figures at the same phase and
# amplitude - not the shared function against itself:
#
#   1. the lobby is the REFERENCE and is unchanged: its applied limb angles are checked
#      against a literal transcription of the pre-U1 lobby code (GAIT_RATE 10.5 rad/s,
#      GAIT_SWING 0.9 rad, [swing, -swing, -swing, swing]), so a change to the shared
#      module that moved the lobby would fail here;
#   2. PARITY: the lobby figure and the level figure are driven for 2 s at the same ground
#      speed (idle 0, walk 3, run 9 u/s) and their four limb nodes' rotation.x and their
#      gait phases must agree at EVERY frame, and the limbs must point the same way in
#      world space;
#   3. the level's leg is ONE rigid block at the hip, like the lobby's: the shin, the boot
#      and the forearm are collinear with their parent (identity local rotation), so the
#      leg swings as a unit instead of being solved by the two-bone IK;
#   4. the rigid boot never goes under the floor at any swing angle (world.gd's _rigid_lift).
#
# Teeth: revert the level to the articulated solver (world.gd's _rigid_weight forced to 0)
# and legs 2 and 3 fail on every frame - the IK's thigh angle is not the lobby's swing and
# the shin is not collinear. See DECISIONS.md D-ANIM-15 for the measured failure count.

const WorldScript := preload("res://app/world.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")
const PlayerGait := preload("res://view/player_gait.gd")
const AnimTest := preload("res://tests/test_player_anim.gd")
const Locomotion := preload("res://view/player_locomotion.gd")

const DT := 1.0 / 60.0
const FRAMES := 120
const RUN_SPEED := 9.0
## The pre-U1 lobby's own constants, transcribed here so the lobby is pinned independently
## of the shared module it now reads.
const LOBBY_RATE := 10.5
const LOBBY_SWING := 0.9
const ANGLE_TOL := 1e-5
const PHASE_TOL := 1e-5
const FLOOR_TOL := 0.005


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_shared_module(f)
	_leg_lobby_reference(f)
	for speed: float in [0.0, 3.0, RUN_SPEED]:
		_leg_parity(f, speed)
	return f


## Leg 1: the shared module's contract, as the lobby's numbers.
func _leg_shared_module(f: Array[String]) -> void:
	if not is_equal_approx(PlayerGait.RATE, LOBBY_RATE):
		f.append("gait: shared RATE %s, the lobby's is %s" % [PlayerGait.RATE, LOBBY_RATE])
	if not is_equal_approx(PlayerGait.SWING, LOBBY_SWING):
		f.append("gait: shared SWING %s, the lobby's is %s" % [PlayerGait.SWING, LOBBY_SWING])
	if PlayerGait.LIMB_NAMES != ["ArmL", "ArmR", "LegL", "LegR"]:
		f.append("gait: LIMB_NAMES %s, want the lobby's four limb nodes" % [PlayerGait.LIMB_NAMES])
	for amp: float in [0.0, 0.25, 0.5, 1.0]:
		for phase: float in [0.0, 0.7, 1.9, 3.1, 4.4, 5.5]:
			var want: float = sin(phase) * LOBBY_SWING * amp
			var got := PlayerGait.limb_angles(phase, amp)
			var pairs := [want, -want, -want, want]
			for i in 4:
				if absf(got[i] - float(pairs[i])) > ANGLE_TOL:
					f.append("gait: limb_angles(%s, %s)[%d] = %s, want %s"
							% [phase, amp, i, got[i], pairs[i]])
	if not is_equal_approx(PlayerGait.amplitude(RUN_SPEED, RUN_SPEED), 1.0):
		f.append("gait: amplitude at the run speed must be 1")
	if not is_equal_approx(PlayerGait.amplitude(0.0, RUN_SPEED), 0.0):
		f.append("gait: amplitude at rest must be 0")
	if not is_equal_approx(PlayerGait.amplitude(RUN_SPEED * 2.0, RUN_SPEED), 1.0):
		f.append("gait: amplitude must clamp at 1")
	var phase := 0.0
	for i in 10:
		phase = PlayerGait.advance(phase, 1.0, DT)
	if absf(phase - fposmod(LOBBY_RATE * DT * 10.0, TAU)) > PHASE_TOL:
		f.append("gait: advance at full amplitude must be RATE x dt, got %s" % phase)


## Leg 2: the lobby is the reference. Its applied angles are the pre-U1 formula, frame by
## frame, so the shared module cannot have moved the hall.
func _leg_lobby_reference(f: Array[String]) -> void:
	var lp = LobbyPlayerScript.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lp)
	lp.build(Vector3(0.0, 0.0, 0.0))
	for speed: float in [0.0, 3.0, RUN_SPEED]:
		lp.vx = 0.0
		lp.vz = -speed
		lp._phase = 0.0
		var phase := 0.0
		var amp: float = clampf(speed / RUN_SPEED, 0.0, 1.0)
		for frame in FRAMES:
			lp._anim(DT)
			phase = fposmod(phase + LOBBY_RATE * amp * DT, TAU)
			if absf(lp._phase - phase) > PHASE_TOL:
				f.append("lobby: phase %s at frame %d, the pre-U1 formula gives %s"
						% [lp._phase, frame, phase])
				break
			var swing: float = sin(phase) * LOBBY_SWING * amp
			var pairs := [swing, -swing, -swing, swing]
			for i in 4:
				var got: float = (lp._limbs[i] as Node3D).rotation.x
				if absf(got - float(pairs[i])) > ANGLE_TOL:
					f.append("lobby: %s %s at frame %d, the pre-U1 formula gives %s"
							% [LobbyPlayerScript.LIMB_NAMES[i], got, frame, pairs[i]])
					break
	lp.free()


## Leg 3+4: the level figure against the lobby figure, frame by frame, at one speed.
func _leg_parity(f: Array[String], speed: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var world = WorldScript.new()
	tree.root.add_child(world)
	world.set_process(false)
	# The contact sheet's own flat course, so the level figure is the one the sheets show.
	AnimTest.stage(world, AnimTest.POSES[0])
	world.ctl.vx = 0.0
	world.ctl.vz = -speed
	world.ctl.vy = 0.0
	world.ctl.grounded = true
	world._player_yaw = 0.0
	world.player_model.rotation.y = 0.0
	world._gait_phase = 0.0
	world._rigid_weight = 1.0
	var lp = LobbyPlayerScript.new()
	tree.root.add_child(lp)
	lp.build(Vector3(0.0, 0.0, 0.0))
	lp.vx = 0.0
	lp.vz = -speed
	lp._phase = 0.0
	var rig = world._leg_rig
	var worst_angle := 0.0
	var worst_phase := 0.0
	var worst_floor := -INF
	var rigid_frames := 0
	for frame in FRAMES:
		lp._anim(DT)
		world._process(DT)
		if float(world._rigid_weight) >= 1.0:
			rigid_frames += 1
		worst_phase = maxf(worst_phase, absf(wrapf(world._gait_phase - lp._phase, -PI, PI)))
		for i in 4:
			var lobby_limb: Node3D = lp._limbs[i]
			var game_limb: Node3D = world._limbs[i + 2]
			worst_angle = maxf(worst_angle, absf(game_limb.rotation.x - lobby_limb.rotation.x))
			# ... and the limb points the same way in world space, not just the same angle.
			var lobby_dir: Vector3 = lobby_limb.global_basis * Vector3.DOWN
			var game_dir: Vector3 = game_limb.global_basis * Vector3.DOWN
			if lobby_dir.distance_to(game_dir) > ANGLE_TOL:
				f.append("parity %s u/s: %s points %s, the lobby's %s (frame %d)"
						% [speed, LobbyPlayerScript.LIMB_NAMES[i], game_dir, lobby_dir, frame])
				break
		# The level's leg is ONE rigid block at the hip: the shin, the boot and the forearm
		# are collinear with their parent, exactly like the lobby's single limb block.
		for side in 2:
			var parts: Array = [rig.shins[side], rig.boots[side], rig.forearms[side]]
			var labels := ["shin", "boot", "forearm"]
			for k in parts.size():
				var basis: Basis = (parts[k] as Node3D).transform.basis
				if basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) > ANGLE_TOL:
					f.append("parity %s u/s: the %s of leg %d is not collinear with its parent (frame %d)"
							% [speed, labels[k], side, frame])
					break
			var boot: MeshInstance3D = rig.boots[side]
			var box := boot.get_aabb()
			for x in [box.position.x, box.end.x]:
				for z in [box.position.z, box.end.z]:
					var corner := boot.to_global(Vector3(x, box.position.y, z))
					worst_floor = maxf(worst_floor, -corner.y)
	if worst_angle > ANGLE_TOL:
		f.append("parity %s u/s: the level's limb angles differ from the lobby's by %.6f rad"
				% [speed, worst_angle])
	if worst_phase > PHASE_TOL:
		f.append("parity %s u/s: the gait phases differ by %.6f rad" % [speed, worst_phase])
	if rigid_frames != FRAMES:
		f.append("parity %s u/s: the lobby gait was showing on %d of %d frames"
				% [speed, rigid_frames, FRAMES])
	if worst_floor > FLOOR_TOL:
		f.append("parity %s u/s: a rigid boot corner went %.4f u under the floor"
				% [speed, worst_floor])
	print("GAIT parity %s u/s: worst angle %.7f rad, worst phase %.7f rad, worst boot %.4f u"
			% [speed, worst_angle, worst_phase, worst_floor])
	world.teardown()
	world.free()
	lp.free()
