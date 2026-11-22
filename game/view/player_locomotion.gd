extends RefCounted
## The figure's leg and arm rig (view side only; the sim never reads it).
##
## The authored limb blocks are cut into rigid segments: thigh + shin + boot per leg, upper
## arm + forearm per arm. Every segment is placed with a pure rotation, so every bone keeps
## its length in every frame. The legs use a two-bone IK whose reach is CLAMPED: a foot target
## the leg cannot reach is missed (the ankle stops on the hip->target line), and a planted
## foot that falls out of reach lifts off early instead of dragging the leg longer (D-ANIM-1).
##
## Feet live in world space. A gait cycle has a stance window (phase < duty) where the foot
## holds its plant, and a swing window where it travels to a landing committed at lift-off.
## The stance length is chosen per movement direction so the planted foot never travels
## farther from its hip than the leg can reach forward/back or than its lane allows sideways,
## which keeps the left foot on the left and the right foot on the right when strafing.

const SEGMENT := 0.31            # thigh and shin length (u), constant
const HIP_RISE := 0.16
const SOLE_HEIGHT := 0.09
const MIN_SPEED := 0.20
const REACH := 2.0 * SEGMENT     # hip -> ankle, fully straight
const SWING_DROP := 0.36         # u: a swinging ankle stays at least this far below its hip (D-ANIM-9)
const TOE := 0.14                # u: a boot pointed along the shin reaches this far below the ankle
const MIN_FOLD := 0.24           # u, the nearest an ankle comes to its hip (knee fold limit)
const SOFT := 0.06               # the last SOFT u of reach eases in (no knee snap)
const RELEASE := REACH - 0.025   # a planted ankle farther than this lifts off
const REACH_FORE := 0.25         # max planted-foot travel from its hip, forward/back
const REACH_SIDE := 0.13         # ... and sideways (the lane)
const LANE := 0.035              # a foot never comes nearer the body midline than this
const WIDEN := 0.05              # extra stance width when moving sideways
const POLE_YAW := 0.45           # rad the knees turn toward a sideways step, at most
const STEP_TIME := 0.22          # s, one idle re-plant step
const STEP_SLACK := 0.07         # u off its neutral before an idle foot re-steps
const ENV_SAMPLES := 9           # ground samples along a swing path
const ENV_CLEAR := 0.05          # u a swinging sole keeps above the ground it passes
const ENV_PLATEAU := 0.24       # u: a sample's footprint can touch ground this far off
const ENV_SLOPE_BEHIND := 3.5
const MAX_DROP := 7.0            # u/s a swinging sole may lower
const ENV_SLOPE := 1.2           # rise per unit of approach to a higher tread
const DESCENT_CADENCE := 0.55  # extra cadence share on a full descent (D-ANIM-8)
const TOUCH_LEAD := 0.025         # s of travel a touching-down foot lands ahead of its hip
const TOUCH_GRACE := 0.06        # s a foot that just met the ground holds before reach can lift it
const STEP_GRACE := 0.05         # s a freshly set-down foot holds before reach can lift it
const STANCE_REACH := RELEASE - 0.04  # u hip->ankle a planted foot is brought within (D-ANIM-8)
const SETTLE := 0.05             # u a set-down foot may be above its landing on the swing's last frame
const SHIN_MARGIN := 0.004        # u a planted foot peels off before its shin corner reaches the tread
const PIVOT := 0.55              # rad a planted foot may lag the body yaw before it pivots
const Collision := preload("res://sim/collision.gd")

var shins: Array[MeshInstance3D] = []
var boots: Array[MeshInstance3D] = []
var forearms: Array[MeshInstance3D] = []
var stance: Array[bool] = [false, false]
var foot_yaw: Array[float] = [0.0, 0.0]
var pole_yaw := 0.0              # knee direction offset (model frame), set per frame
var floors: Array[float] = [-INF, -INF]   # ground under each foot (model frame), set per frame
var shin_depth := 0.0            # half the shin block's depth and width (u), from the mesh
var shin_width := 0.0
var releases := 0                # diagnostics: early lift-offs (foot out of reach / lane)
var _has_contact: Array[bool] = [false, false]
var _plants: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _landings: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _plant_yaw: Array[float] = [0.0, 0.0]
var _landing_yaw: Array[float] = [0.0, 0.0]
var _swing_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_yaw: Array[float] = [0.0, 0.0]
var _swing_begin: Array[float] = [0.0, 0.0]
var _released: Array[bool] = [false, false]
var _grace: Array[float] = [0.0, 0.0]
var _prev_phase: Array[float] = [0.0, 0.0]
var _step: Array[float] = [-1.0, -1.0]   # idle step progress 0..1, -1 = none
var _swing_hold: Array[float] = [0.0, 0.0]
var _swing_floor: Array[float] = [0.0, 0.0]
var _swing_drop: Array[float] = [0.1, 0.1]
var _envelope: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]


func build(limbs: Array, mounts: Array[Vector3]) -> void:
	for i in range(2, 6):
		var upper := limbs[i] as MeshInstance3D
		if upper == null:
			continue
		var bounds := upper.get_aabb()
		var source := upper.mesh
		var mount := mounts[i]
		if i < 4:
			var length := bounds.size.y * 0.49
			forearms.append(_segment(upper, source, bounds, length, 0.89))
			upper.mesh = _segment_mesh(source, bounds, mount, bounds.size.y - length, 1.0)
		else:
			shins.append(_segment(upper, source, bounds, SEGMENT, 0.83))
			shin_depth = bounds.size.z * 0.83 * 0.5
			shin_width = bounds.size.x * 0.83 * 0.5
			boots.append(_segment(upper, source, bounds, SOLE_HEIGHT, 0.94))
			upper.mesh = _segment_mesh(source, bounds, mount, SEGMENT, 1.0)


## The authored parts are blocks. Remap their vertices to the upper/lower lengths,
## keeping the vertex colours, face normals and per-instance material.
static func _segment_mesh(source: Mesh, bounds: AABB, top: Vector3,
		length: float, width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in source.get_surface_count():
		var arrays := source.surface_get_arrays(i)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in vertices.size():
			var v := vertices[j] - Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
			vertices[j] = top + v * Vector3(width, length / bounds.size.y, width)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _segment(upper: MeshInstance3D, source: Mesh, bounds: AABB,
		length: float, width: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = _segment_mesh(source, bounds, Vector3.ZERO, length, width)
	for i in source.get_surface_count():
		part.set_surface_override_material(i, upper.get_surface_override_material(i))
	upper.add_child(part)
	return part


## Gait for a ground speed: x cadence (cycles/s), y duty (stance share of a cycle), z the
## walk->run blend. `side` is the sideways share of the movement (0 forward/back, 1 pure
## strafe). The duty is capped so a planted foot travels at most REACH_FORE / REACH_SIDE
## from its hip during stance: the leg never needs to be longer than it is.
static func profile(speed: float, run_speed: float, climb: float, side := 0.0,
		slope := 0.0) -> Vector3:
	var run := smoothstep(0.35, 0.95, speed / maxf(run_speed, 0.001))
	# Going down, the steps quicken and shorten (DESCENT_CADENCE): the leading foot reaches
	# down to the next tread or the slope before the body follows, instead of a long split.
	var cadence := (1.0 + 0.28 * speed) / lerpf(1.0, 0.77, climb) * (1.0 + 0.30 * side) 			* (1.0 + DESCENT_CADENCE * slope)
	# Uphill the stance reach shrinks (the foot behind sits low, the one ahead high). Going
	# down it does not: the hips are lowered onto the slope instead, and a shrunken stance
	# share left both feet off the ground most of the cycle (a float, not a descent).
	var fore := sqrt(maxf(0.0, 1.0 - side * side)) / (1.0 - 0.45 * climb)
	var reach := 1.0 / sqrt(pow(fore / REACH_FORE, 2.0) + pow(side / REACH_SIDE, 2.0))
	var duty := minf(lerpf(0.56, 0.30, run), 1.84 * reach * cadence / maxf(speed, MIN_SPEED))
	return Vector3(cadence, maxf(duty, 0.10), run)


func reset_contacts() -> void:
	floors.fill(-INF)
	_has_contact.fill(false)
	stance.fill(false)
	_released.fill(false)
	_step.fill(-1.0)


## Use point support for the soles. The controller uses a wider footprint.
static func tile_height(world: Dictionary, point: Vector3, limit: float) -> float:
	var x := floori(point.x)
	var z := floori(point.z)
	var best := -INF
	for tile in world.get("cols", {}).get("%d,%d" % [x, z], []):
		if world["removed"].has(Collision.tile_key(x, z, tile["y"])):
			continue
		var rise := 0.0
		match int(tile["kind"]):
			1: rise = point.x - x
			2: rise = point.z - z
			3: rise = 1.0 - (point.x - x)
			4: rise = 1.0 - (point.z - z)
		var top := Collision.tile_top(tile["y"]) + rise * 0.5
		if top <= limit:
			best = maxf(best, top)
	return best


## 0..1: how steeply the ground rises ahead in the movement direction.
static func grade(world: Dictionary, root: Vector3, direction: Vector3, vy: float) -> float:
	if vy > 0.01:
		return 0.0
	var here := tile_height(world, root, root.y + 0.05)
	var ahead := tile_height(world, root + direction * 0.58, root.y + 0.51)
	if here == -INF or ahead == -INF:
		return 0.0
	return smoothstep(0.025, 0.22, ahead - here)


## 0..1: how steeply the ground falls away ahead in the movement direction.
static func descent(world: Dictionary, root: Vector3, direction: Vector3) -> float:
	var here := tile_height(world, root, root.y + 0.05)
	var ahead := tile_height(world, root + direction * 0.58, root.y + 0.05)
	if here == -INF or ahead == -INF:
		return 0.0
	return smoothstep(0.025, 0.22, here - ahead)


## The highest support under the boot's footprint (the sole rests on its highest corner).
func floor_under(world: Dictionary, point: Vector3, yaw: float, height_limit: float) -> float:
	var bounds := boots[0].get_aabb()
	var height := tile_height(world, point, height_limit)
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			var corner := point + Vector3(x, 0.0, z).rotated(Vector3.UP, yaw)
			height = maxf(height, tile_height(world, corner, height_limit))
	return height


## A foot's resting spot under its hip, widened outward when the body moves sideways.
static func neutral(side: int, root: Vector3, yaw: float, hip_local: Vector3, sideways: float) -> Vector3:
	var out := -1.0 if side == 0 else 1.0
	var local := Vector3(hip_local.x + out * WIDEN * sideways, 0.0, hip_local.z)
	return root + local.rotated(Vector3.UP, yaw)


## Moves one sole (world space) and returns it. `phase` is this foot's 0..1 cycle phase,
## `gait` profile()'s result (x == 0 means standing), `hip` the hip joint in world space,
## `root` the body root. A planted foot holds still; it lifts off at the end of stance, or
## early if it falls out of the leg's reach or crosses its lane. The landing is committed
## at lift-off, along the ACTUAL horizontal velocity (so strafing / backpedalling step the
## right way while the body keeps its facing).
func place_foot(side: int, rest: Vector3, velocity: Vector3, phase: float, gait: Vector3,
		climb: float, yaw: float, world: Dictionary, delta: float, hip: Vector3,
		root: Vector3, down := 0.0) -> Vector3:
	var limit := rest.y + 0.51
	if not _has_contact[side]:
		# A foot meeting the ground (a touchdown) lands a little ahead of its hip along the
		# travel, so the body moves over it while it compresses instead of leaving it behind.
		var start := rest + Vector3(velocity.x, 0.0, velocity.z) * TOUCH_LEAD
		var underfoot := floor_under(world, start, yaw, limit)
		if underfoot != -INF:
			start.y = underfoot + 0.002
		_plants[side] = start
		_landings[side] = start
		_targets[side] = start
		_plant_yaw[side] = yaw
		_landing_yaw[side] = yaw
		foot_yaw[side] = yaw
		_has_contact[side] = true
		stance[side] = true
		_released[side] = false
		_step[side] = -1.0
		_prev_phase[side] = phase
		_grace[side] = TOUCH_GRACE
	_grace[side] -= delta
	if stance[side]:
		_pivot(side, yaw, root)
	var was_swinging := not stance[side]
	var result: Vector3
	if gait.x > 0.0:
		result = _gait_foot(side, rest, velocity, phase, gait, climb, yaw, world, hip, root, down)
	else:
		result = _idle_foot(side, rest, yaw, world, delta, hip, root)
	if not stance[side]:
		result = _keep_lane(side, result, yaw, root)
		# A swinging foot never passes down through a surface it was above last frame.
		var ceiling := maxf(result.y + 0.25, _targets[side].y + 0.01)
		var ground := floor_under(world, result, foot_yaw[side], ceiling)
		if ground != -INF:
			result.y = maxf(result.y, ground + 0.002)
		if was_swinging:
			# Coming off a ledge the foot lowers at a bounded rate (no one-frame drop); going
			# down a flight, up to twice as fast, so it is down on the lower tread when its
			# stance begins.
			result.y = maxf(result.y, _targets[side].y - MAX_DROP * (1.0 + down) * delta)
	_targets[side] = result
	return result


## The height a swinging sole is held at by the ground it passes (its riser/tread
## clearance), without the stylistic lift and heel kick.
func swing_floor(side: int) -> float:
	return _swing_floor[side]


func _gait_foot(side: int, rest: Vector3, velocity: Vector3, phase: float, gait: Vector3,
		climb: float, yaw: float, world: Dictionary, hip: Vector3, root: Vector3,
		down: float) -> Vector3:
	if _step[side] >= 0.0:
		# An idle re-step was interrupted by a start: it becomes this cycle's swing.
		_step[side] = -1.0
		_lift_off(side, phase, rest, velocity, gait, yaw, world)
	if phase < _prev_phase[side] - 0.5:
		_released[side] = false      # a new cycle: the foot may land again
	_prev_phase[side] = phase
	if phase < gait.y and not _released[side]:
		if not stance[side]:
			_plants[side] = _landings[side]
			_plant_yaw[side] = _landing_yaw[side]
			stance[side] = true
			# Going down, a foot set down on a lower tread holds while the hips come down
			# to it (the body follows the leading foot down; see reach_drop) instead of
			# lifting off the frame it lands.
			# Only a foot already down on its landing: one still being lowered off a ledge
			# (bounded drop rate) would snap onto the plant below it.
			if down > 0.2 and _targets[side].y <= _landings[side].y + SETTLE:
				_grace[side] = maxf(_grace[side], STEP_GRACE)
		# A foot that has just met the ground holds for TOUCH_GRACE while the body (still
		# settling from the air) comes down over it: out of reach it lags, it does not lift.
		if not _must_release(side, _plants[side], hip, yaw, root, _grace[side] <= 0.0):
			foot_yaw[side] = _plant_yaw[side]
			return _plants[side]
		releases += 1
	if stance[side]:
		_lift_off(side, phase, rest, velocity, gait, yaw, world)
	var s := clampf((phase - _swing_begin[side]) / maxf(1.0 - _swing_begin[side], 0.05), 0.0, 1.0)
	var lift := (lerpf(0.10, 0.18, gait.z) + 0.20 * climb) * (1.0 - 0.45 * down)
	# Running adds a heel kick: the foot rises behind the body early in the swing (the
	# knee folds up) instead of trailing straight back along the ground.
	var kick := 0.15 * gait.z * (1.0 - 0.6 * climb) * (1.0 - 0.8 * down)
	return _swing(side, s, lift, kick, gait.z)


func _lift_off(side: int, phase: float, rest: Vector3, velocity: Vector3, gait: Vector3,
		yaw: float, world: Dictionary) -> void:
	_swing_from[side] = _targets[side]
	_swing_yaw[side] = foot_yaw[side]
	_swing_begin[side] = phase
	_released[side] = true
	stance[side] = false
	# Land so that mid-stance falls under the hip at the current velocity.
	var horizon := (1.0 - phase + gait.y * 0.5) / gait.x
	var landing := rest + velocity * horizon
	# A long stride up a slope or stairs lands well above the body's tread: allow the
	# steepest walkable rise (0.5 u per u) over the stride's length.
	var reach_up := 0.51 + 0.55 * Vector2(landing.x - rest.x, landing.z - rest.z).length()
	var floor_y := floor_under(world, landing, yaw, rest.y + reach_up)
	if floor_y != -INF:
		landing.y = floor_y + 0.002
	_landings[side] = landing
	_landing_yaw[side] = yaw
	_sample_envelope(side, world)


## A swing from _swing_from to _landings: smooth travel plus a lift arc, held above a
## clearance envelope of the ground along the path (sampled at lift-off). The envelope is
## a set of cones (slope ENV_SLOPE) over the sampled treads, so the foot rises before a
## riser going up and reaches over the nosing before it lowers going down, continuously.
func _swing(side: int, s: float, lift: float, kick := 0.0, run := 0.0) -> Vector3:
	var from := _swing_from[side]
	var to := _landings[side]
	# A riser right in front of the lifting foot: hold the travel while the foot rises.
	var hold := _swing_hold[side]
	var eased := smoothstep(hold, 1.0, s)
	var travel := lerpf(eased, clampf((s - hold) / maxf(1.0 - hold, 0.01), 0.0, 1.0), 0.45 * run)
	var result := from.lerp(to, travel)
	var weight := smoothstep(0.0, maxf(hold, 0.12), s) * (1.0 - smoothstep(1.0 - _swing_drop[side], 1.0, s))
	var envelope := _envelope_at(side, travel)
	# Where the ground already forces the foot up (a riser), that clearance IS the lift:
	# the arc is not stacked on top of it (which would bring the sole up to the hip).
	var forced := maxf(0.0, envelope - ENV_CLEAR - result.y) * weight
	var arc := maxf(0.0, lift * pow(sin(PI * s), 2.0) - forced)
	_swing_floor[side] = maxf(result.y, lerpf(result.y, envelope - ENV_CLEAR, weight))
	result.y += arc + kick * pow(sin(PI * pow(s, 0.55)), 2.0)
	result.y = maxf(result.y, lerpf(result.y, envelope, weight))
	foot_yaw[side] = lerp_angle(_swing_yaw[side], _landing_yaw[side], travel)
	return result


func _envelope_at(side: int, travel: float) -> float:
	var from := _swing_from[side]
	var to := _landings[side]
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var envelope := -INF
	var heights: PackedFloat32Array = _envelope[side]
	for i in heights.size():
		var t := float(i) / float(ENV_SAMPLES - 1)
		var gap := maxf(0.0, absf(travel - t) * length - ENV_PLATEAU)
		# Shallow ahead (rise early before a higher tread), steeper behind (once past a
		# ledge the foot may drop toward a lower landing).
		var slope := ENV_SLOPE if t > travel else ENV_SLOPE_BEHIND
		envelope = maxf(envelope, heights[i] + ENV_CLEAR - slope * gap)
	return envelope


func _sample_envelope(side: int, world: Dictionary) -> void:
	var from := _swing_from[side]
	var to := _landings[side]
	var limit := maxf(from.y, to.y) + 0.3
	var heights := PackedFloat32Array()
	for i in ENV_SAMPLES:
		var point := from.lerp(to, float(i) / float(ENV_SAMPLES - 1))
		var ground := floor_under(world, point, _landing_yaw[side], limit)
		heights.append(ground if ground != -INF else minf(from.y, to.y))
	_envelope[side] = heights
	_swing_hold[side] = clampf((_envelope_at(side, 0.0) - from.y) * 0.6, 0.0, 0.3)
	# Coming down off a ledge onto the landing: give the set-down more of the swing.
	_swing_drop[side] = clampf(0.1 + (_envelope_at(side, 1.0) - to.y) * 0.6, 0.1, 0.45)


func _idle_foot(side: int, rest: Vector3, yaw: float, world: Dictionary, delta: float,
		hip: Vector3, root: Vector3) -> Vector3:
	_released[side] = false
	var home := rest
	var underfoot := floor_under(world, rest, yaw, rest.y + 0.51)
	if underfoot != -INF:
		home.y = underfoot + 0.002
	var other := 1 - side
	if _step[side] < 0.0:
		var off := Vector2(_plants[side].x - home.x, _plants[side].z - home.z).length()
		var twisted := absf(wrapf(yaw - _plant_yaw[side], -PI, PI)) > 0.30
		var wants := not stance[side] or off > STEP_SLACK or twisted \
				or absf(_plants[side].y - home.y) > 0.03 \
				or _must_release(side, _plants[side], hip, yaw, root)
		if wants and (not stance[side] or _step[other] < 0.0):
			_swing_from[side] = _targets[side]
			_swing_yaw[side] = foot_yaw[side]
			_step[side] = 0.0
			stance[side] = false
	if _step[side] < 0.0:
		foot_yaw[side] = _plant_yaw[side]
		return _plants[side]
	_step[side] = minf(_step[side] + delta / STEP_TIME, 1.0)
	_landings[side] = home
	_landing_yaw[side] = yaw
	_sample_envelope(side, world)
	var result := _swing(side, _step[side], 0.07)
	if _step[side] >= 1.0:
		_step[side] = -1.0
		stance[side] = true
		_plants[side] = home
		_plant_yaw[side] = yaw
		result = home
	return result


## A planted foot holds its spot while the body turns a little; past PIVOT it pivots with
## the body about the root, so a fast turn never winds the legs past each other.
func _pivot(side: int, yaw: float, root: Vector3) -> void:
	var lag := wrapf(yaw - _plant_yaw[side], -PI, PI)
	if absf(lag) <= PIVOT:
		return
	var turn := lag - signf(lag) * PIVOT
	var offset := _plants[side] - root
	offset.y = 0.0
	_plants[side] = root + offset.rotated(Vector3.UP, turn) + Vector3.UP * (_plants[side].y - root.y)
	_plant_yaw[side] += turn


func _must_release(side: int, plant: Vector3, hip: Vector3, yaw: float, root: Vector3,
		reach := true) -> bool:
	if reach and hip.distance_to(plant + Vector3.UP * SOLE_HEIGHT) > RELEASE:
		return true
	# A leg folded tight over its planted foot (the hips come down past it on a descent)
	# pitches the shin so far that the block's lower corner would sink into the tread:
	# the foot peels off instead.
	if shin_depth > 0.0:
		var turn := minf(pole_yaw, 0.0) if side == 1 else maxf(pole_yaw, 0.0)
		var pole := Vector3.FORWARD.rotated(Vector3.UP, yaw + turn)
		# (SHIN_MARGIN covers the hips' motion between this check and the drawn pose.)
		if shin_lowest(solve(hip, plant + Vector3.UP * SOLE_HEIGHT, pole)) < plant.y + SHIN_MARGIN:
			return true
	var local := (plant - root).rotated(Vector3.UP, -yaw)
	return local.x * (-1.0 if side == 0 else 1.0) < LANE


func _keep_lane(side: int, point: Vector3, yaw: float, root: Vector3) -> Vector3:
	var out := -1.0 if side == 0 else 1.0
	var local := (point - root).rotated(Vector3.UP, -yaw)
	if local.x * out >= LANE:
		return point
	local.x = out * LANE
	return root + local.rotated(Vector3.UP, yaw)


## Forearms are children of their upper arm, so they follow its swing; the elbow only
## flexes forward (bend >= 0) and never inverts.
func pose_arm(side: int, limb: MeshInstance3D, mount: Vector3, bend: float) -> void:
	var elbow := mount + Vector3.DOWN * limb.get_aabb().size.y
	forearms[side].transform = Transform3D(Basis(Vector3.RIGHT, clampf(bend, 0.0, 2.3)), elbow)


## Two-bone leg in the figure's frame. `sole` is the planted/swinging sole (model space),
## blended by `contact` with the airborne pose (thigh pitch + knee flex, forward kinematics).
## The solve clamps the reach: thigh and shin are placed by pure rotations and keep
## SEGMENT length in every frame; an unreachable sole is missed, never stretched to.
func pose_leg(side: int, limb: MeshInstance3D, hip: Vector3, mount: Vector3,
		sole: Vector3, model_yaw: float, contact: float, thigh_pitch := 0.0,
		knee_flex := 0.0, ground := -INF) -> void:
	var thigh_dir := Basis(Vector3.RIGHT, thigh_pitch) * Vector3.DOWN
	var shin_dir := Basis(Vector3.RIGHT, thigh_pitch - maxf(knee_flex, 0.0)) * Vector3.DOWN
	var air_ankle := hip + (thigh_dir + shin_dir) * SEGMENT
	var target := air_ankle.lerp(sole + Vector3.UP * SOLE_HEIGHT, contact)
	# The floor guard: under the foot's own sole while the gait is placing it (`floors`),
	# else under the body's centre (airborne and dash legs). The centre floor lifted a foot
	# planted on a lower tread or downhill on a slope off its ground (D-ANIM-8).
	var floor_y: float = floors[side] if floors[side] != -INF else ground
	if floor_y != -INF:
		# A pointed (airborne) boot dips its toe up to TOE below the ankle line.
		target.y = maxf(target.y, floor_y + SOLE_HEIGHT + TOE * (1.0 - contact) + 0.002)
	var out := -1.0 if side == 0 else 1.0
	if target.x * out < LANE:
		target.x = out * LANE
	# A knee only turns OUTWARD toward a sideways step (the leading leg); the trailing
	# knee stays forward instead of swinging across the body.
	var turn := minf(pole_yaw, 0.0) if side == 1 else maxf(pole_yaw, 0.0)
	var pole := Vector3.FORWARD.rotated(Vector3.UP, turn)
	target = clear_hip(hip, target, pole)
	var joints := solve(hip, target, pole)
	# The shin block is wider than the ankle is high: steeply pitched (a swing's first
	# frames, a push-off) its lower corners reach under the sole. Lift the foot until the
	# lowest shin corner clears the floor under the foot (`floors`, model frame). A planted
	# foot this catches is a frame from peeling off (_must_release's shin check).
	if floors[side] != -INF:
		for i in 3:
			var short := floors[side] + 0.002 - shin_lowest(joints)
			if short <= 0.0:
				break
			target.y += short
			joints = solve(hip, target, pole)
	var knee: Vector3 = joints[0]
	var ankle: Vector3 = joints[1]
	var bend: Vector3 = joints[2]
	var thigh := bone_basis(knee - hip, bend)
	var shin := bone_basis(ankle - knee, bend)
	limb.transform = Transform3D(thigh, hip - thigh * mount)
	var inverse := limb.transform.affine_inverse()
	shins[side].transform = inverse * Transform3D(shin, knee)
	var flat := Basis(Vector3.UP, wrapf(foot_yaw[side] - model_yaw, -PI, PI))
	var boot_basis := shin.slerp(flat, contact) if contact < 1.0 else flat
	boots[side].transform = inverse * Transform3D(boot_basis, ankle)


## The lowest corner height of the shin block for a solve()'s [knee, ankle, bend].
func shin_lowest(joints: Array) -> float:
	var shin_axis: Vector3 = ((joints[1] as Vector3) - (joints[0] as Vector3)).normalized()
	var bend_dir: Vector3 = joints[2]
	var depth_axis := (bend_dir - shin_axis * shin_axis.dot(bend_dir)).normalized()
	var across := depth_axis.cross(shin_axis).normalized()
	return (joints[1] as Vector3).y - absf(depth_axis.y) * shin_depth - absf(across.y) * shin_width


## How far the hip must come DOWN for a planted sole to be within STANCE_REACH of it (a
## foot set down on a lower tread or downhill: the body follows it down).
static func reach_drop(sole: Vector3, hip: Vector3) -> float:
	var ankle := sole + Vector3.UP * SOLE_HEIGHT
	var flat := Vector2(hip.x - ankle.x, hip.z - ankle.z).length()
	if flat >= STANCE_REACH:
		return 0.0
	return maxf(0.0, hip.y - ankle.y - sqrt(STANCE_REACH * STANCE_REACH - flat * flat))


## How far the hip must rise for a planted sole to stay MIN_FOLD (+ margin) below it.
static func fold_height(sole: Vector3, hip: Vector3) -> float:
	var ankle := sole + Vector3.UP * SOLE_HEIGHT
	var flat := Vector2(hip.x - ankle.x, hip.z - ankle.z).length()
	var need := MIN_FOLD + 0.02
	if flat >= need:
		return 0.0
	return maxf(0.0, ankle.y + sqrt(need * need - flat * flat) - hip.y)


## A sole drawn up close to the hip (a high step, a tuck) is pushed out forward-down,
## by twice its shortfall, then onto the MIN_FOLD sphere: continuous, and the knee folds
## up in front instead of the leg spinning about a target sitting on the hip joint. (The
## one point this map cannot resolve lies up-and-behind the hip, where no sole goes.)
static func clear_hip(hip: Vector3, target: Vector3, forward: Vector3) -> Vector3:
	var offset := target - hip
	var shortfall := MIN_FOLD - offset.length()
	if shortfall <= 0.0:
		return target
	offset += (forward * 0.6 + Vector3.DOWN * 0.8) * 2.0 * shortfall
	if offset.length() < MIN_FOLD:
		offset = offset.normalized() * MIN_FOLD if offset.length() > 1e-5 else Vector3.DOWN * MIN_FOLD
	return hip + offset


## [knee, ankle, bend direction]. The ankle sits on the hip->target line at the reachable
## distance (soft-limited in the last SOFT u so the knee eases straight instead of snapping).
static func solve(hip: Vector3, target: Vector3, pole: Vector3) -> Array:
	var delta := target - hip
	var distance := delta.length()
	var axis := delta / distance if distance > 1e-5 else Vector3.DOWN
	var knee_in := REACH - SOFT
	var reach := distance
	if distance > knee_in:
		reach = knee_in + SOFT * (1.0 - exp(-(distance - knee_in) / SOFT))
	reach = maxf(reach, 0.12)
	# The knee is a hinge about the axis across the leg (pole x up = the figure's right): the knee lies in front
	# of the hip->ankle line in every direction the leg points, continuously.
	var hinge := pole.cross(Vector3.UP)
	var bend := hinge.cross(axis)
	if bend.length_squared() < 1e-4:
		bend = pole - axis * axis.dot(pole)
	bend = bend.normalized()
	var half := reach * 0.5
	var knee := hip + axis * half + bend * sqrt(maxf(0.0, SEGMENT * SEGMENT - half * half))
	return [knee, hip + axis * reach, bend]


## A rigid bone hanging from its top joint along `direction`, its front (-Z) toward `front`.
static func bone_basis(direction: Vector3, front: Vector3) -> Basis:
	var y := -direction.normalized()
	var z := -(front - y * y.dot(front))
	if z.length_squared() < 1e-6:
		z = Vector3.BACK - y * y.dot(Vector3.BACK)
	z = z.normalized()
	return Basis(y.cross(z), y, z)
