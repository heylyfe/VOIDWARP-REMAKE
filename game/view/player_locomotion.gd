extends RefCounted
## Articulates the figure's rigid limb meshes and solves world-space foot contacts.

const SEGMENT := 0.31
const HIP_RISE := 0.16
const SOLE_HEIGHT := 0.09
const MIN_SPEED := 0.20
const Collision := preload("res://sim/collision.gd")

var shins: Array[MeshInstance3D] = []
var boots: Array[MeshInstance3D] = []
var forearms: Array[MeshInstance3D] = []
var stance: Array[bool] = [false, false]
var foot_yaw: Array[float] = [0.0, 0.0]
var _has_contact: Array[bool] = [false, false]
var _plants: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _landings: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _plant_yaw: Array[float] = [0.0, 0.0]
var _landing_yaw: Array[float] = [0.0, 0.0]


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


static func profile(speed: float, run_speed: float, climb: float) -> Vector3:
	var run := smoothstep(0.35, 0.95, speed / maxf(run_speed, 0.001))
	var cadence := (1.0 + 0.28 * speed) / lerpf(1.0, 0.77, climb)
	# Shorten contact when running so a planted foot stays within the leg's reach.
	var duty := minf(lerpf(0.56, 0.27, run), 0.59 * cadence / maxf(speed, MIN_SPEED))
	return Vector3(cadence, duty, run)


func reset_contacts() -> void:
	_has_contact.fill(false)
	stance.fill(false)


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


static func grade(world: Dictionary, root: Vector3, direction: Vector3, vy: float) -> float:
	if vy > 0.01:
		return 0.0
	var here := tile_height(world, root, root.y + 0.05)
	var ahead := tile_height(world, root + direction * 0.58, root.y + 0.51)
	if here == -INF or ahead == -INF:
		return 0.0
	return smoothstep(0.025, 0.22, ahead - here)


func _floor(world: Dictionary, point: Vector3, yaw: float, height_limit: float) -> float:
	var bounds := boots[0].get_aabb()
	var height := tile_height(world, point, height_limit)
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			var corner := point + Vector3(x, 0.0, z).rotated(Vector3.UP, yaw)
			height = maxf(height, tile_height(world, corner, height_limit))
	return height


func place_foot(side: int, neutral: Vector3, velocity: Vector3, phase: float,
		gait: Vector3, climb: float, yaw: float, world: Dictionary, delta: float) -> Vector3:
	var duration := gait.y
	var moving := gait.x > 0.0
	var supported := not moving or phase < duration
	var swing_start := stance[side] or not _has_contact[side]
	if not _has_contact[side] or not moving:
		var underfoot := _floor(world, neutral, yaw, neutral.y + 0.51)
		if underfoot != -INF:
			neutral.y = underfoot + 0.002
		var rest := _targets[side].move_toward(neutral, delta * 2.0) if _has_contact[side] else neutral
		_plants[side] = rest
		_landings[side] = rest
		_plant_yaw[side] = yaw
		_landing_yaw[side] = yaw
		_has_contact[side] = true
	var result: Vector3
	if supported:
		if not stance[side]:
			_plants[side] = _landings[side]
			_plant_yaw[side] = _landing_yaw[side]
		result = _plants[side]
		foot_yaw[side] = _plant_yaw[side]
	else:
		# Commit at lift-off. Rechecking the target at every frame can switch
		# between two treads as the stride adjusts and pop the knee in mid-swing.
		if swing_start:
			var horizon := (1.0 - phase + duration * 0.5) / gait.x
			var landing := neutral + velocity * horizon
			var floor_y := _floor(world, landing, yaw, neutral.y + 0.51)
			if floor_y != -INF:
				landing.y = floor_y + 0.002
			_landings[side] = landing
			_landing_yaw[side] = yaw
		var swing := (phase - duration) / (1.0 - duration)
		var travel := smoothstep(0.0, 1.0, swing)
		result = _plants[side].lerp(_landings[side], travel)
		foot_yaw[side] = lerp_angle(_plant_yaw[side], _landing_yaw[side], travel)
		var lift := lerpf(0.10, 0.18, gait.z) + 0.19 * climb
		result.y += lift * pow(sin(PI * swing), 2.0)
	stance[side] = supported
	_targets[side] = result
	return result


func pose_arm(side: int, limb: MeshInstance3D, mount: Vector3, bend: float) -> void:
	var elbow := mount + Vector3.DOWN * limb.get_aabb().size.y
	forearms[side].transform = Transform3D(Basis(Vector3.RIGHT, bend), elbow)


## Solve the knee in the plane through the hip, ankle and knee pole. The shin can
## extend just enough to keep the ankle attached if a step exceeds the nominal reach.
func pose_leg(side: int, limb: MeshInstance3D, hip: Vector3, mount: Vector3,
		sole: Vector3, model_yaw: float, contact: float) -> void:
	var knee_forward := Vector3.FORWARD
	var air_basis := limb.basis
	var air_knee := hip + air_basis * Vector3.DOWN * SEGMENT
	var air_ankle := air_knee + air_basis * Vector3.DOWN * SEGMENT
	var ankle := air_ankle.lerp(sole + Vector3.UP * SOLE_HEIGHT, contact)
	var delta := ankle - hip
	var distance := maxf(delta.length(), 0.001)
	var axis := delta / distance
	var pole := (knee_forward - axis * axis.dot(knee_forward)).normalized()
	if pole.is_zero_approx():
		pole = Vector3.RIGHT
	# Ease into extension to keep the knee from snapping through straight.
	var extra := distance - 2.0 * SEGMENT + contact * 0.014
	var ease := contact * 0.04
	var shin_length := SEGMENT + 0.5 * (extra + sqrt(extra * extra + ease * ease))
	var along := (SEGMENT * SEGMENT + distance * distance - shin_length * shin_length) / (2.0 * distance)
	var knee := hip + axis * along + pole * sqrt(maxf(0.0, SEGMENT * SEGMENT - along * along))
	var thigh := _bone_basis(knee - hip)
	var shin := _bone_basis(ankle - knee)
	shin = shin.scaled_local(Vector3(1.0, knee.distance_to(ankle) / SEGMENT, 1.0))
	limb.transform = Transform3D(thigh, hip - thigh * mount)
	var inverse := limb.transform.affine_inverse()
	shins[side].transform = inverse * Transform3D(shin, knee)
	var boot_basis := air_basis.slerp(Basis(Vector3.UP, foot_yaw[side] - model_yaw), contact)
	boots[side].transform = inverse * Transform3D(boot_basis, ankle)


static func _bone_basis(segment: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.DOWN, segment.normalized()))
