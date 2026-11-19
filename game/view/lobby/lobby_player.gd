extends Node3D
#
# view/lobby/lobby_player.gd - the walking player inside the Antechamber (J7).
#
# DESIGN.md section 11: "The player arrives at (0, +8) facing -z ... Walk in -> next level.
# No timers. No menus. The mouse is never freed." The hall is a flat 28 x 20 u floor at
# y = 0, so this is a flat-floor walker, NOT the level controller: no gravity, no void, no
# collision world, no sim state. It reads the SAME captured PlayerInput the level does
# (app/input_capture.gd, already pre-rotated by the camera yaw and quantized to int8), so
# W/A/S/D feel identical in the hall and on a level.
#
# The camera is the level's own third-person rig (app/camera_rig.gd, D-T082-1 defaults), so
# the lobby is framed exactly like the game. The figure is the T-015 player model, yawed to
# the camera's forward (the same character/camera coupling world.gd uses).
#
# Pure view: nothing here writes sim state, and nothing here reads the Input singleton -
# the caller passes the axis values (headless tests drive move() directly).

const CameraRigScript := preload("res://app/camera_rig.gd")

const PLAYER_MODEL := "res://assets/models/player_figure.glb"
const RUN_SPEED := 9.0        # data/player.json shared_kit.run_speed (the level's speed)
const ACCEL := 60.0           # u/s^2 toward the target velocity
const FRICTION := 45.0        # u/s^2 when no direction is held
const AXIS_127 := 127.0
const BOUND_X := 13.0         # HALL_X / 2 - 1.0 (the wall slab is 0.5 thick)
const BOUND_Z := 9.0          # HALL_Z / 2 - 1.0
const CAM_X := 13.4           # the camera's own box: the wall's inner face, less a margin
const CAM_Z := 9.4
const CAM_Y_MIN := 0.6
const CAM_Y_MAX := 7.4        # CEIL 8.0 less a margin
const CAM_MIN_T := 0.15       # never pull the camera closer than this fraction of the boom
const FILL_RANGE := 18.0      # palette.json roles.player_fill_light.range
const FILL_ENERGY := 1.2
const FILL_HEX := "#BFFFF8"
const GAIT_RATE := 10.5       # rad/s at full speed (world.gd's ANIM_PHASE_RUN)
const GAIT_SWING := 0.9       # rad, leg swing amplitude at full speed
const LIMB_NAMES := ["ArmL", "ArmR", "LegL", "LegR"]

var rig: Node3D = null
var camera: Camera3D = null
var model: Node3D = null
var x := 0.0
var y := 0.0
var z := 8.0
var vx := 0.0
var vz := 0.0
var _fill: OmniLight3D = null
var _limbs: Array = []        # LIMB_NAMES order -> limb node (or null)
var _phase := 0.0


## Builds the figure, the fill light and the camera rig at p_spawn (feet on the floor).
func build(p_spawn: Vector3) -> void:
	x = p_spawn.x
	y = p_spawn.y
	z = p_spawn.z
	vx = 0.0
	vz = 0.0
	_phase = 0.0
	var ps: PackedScene = load(PLAYER_MODEL)
	if ps != null:
		model = ps.instantiate()
		_apply_player_body_material(model)
		model.position = Vector3(x, y, z)
		add_child(model)
	_limbs = []
	for nm in LIMB_NAMES:
		_limbs.append(model.find_child(nm, true, false) if model != null else null)
	_fill = OmniLight3D.new()
	_fill.light_color = Color(FILL_HEX)
	_fill.omni_range = FILL_RANGE
	_fill.light_energy = FILL_ENERGY
	_fill.position = Vector3(0.0, 1.3, 2.0)
	if model != null:
		model.add_child(_fill)
	else:
		_fill.position = Vector3(x, y + 1.3, z + 2.0)
		add_child(_fill)
	rig = CameraRigScript.new()
	rig.yaw_deg = 0.0
	var cam := Camera3D.new()
	cam.fov = CameraRigScript.FOV_DEFAULT
	cam.current = true
	rig.add_child(cam)
	add_child(rig)
	camera = cam
	# dt = 1.0 snaps the height spring onto the feet (a dt = 0 call is a documented no-op).
	rig.update_rig(Vector3(x, y, z), 1.0)


## Curse consumer (gap 27): lights_out shrinks the player fill light range to the modified
## stat. The curse uses op=set (absolute), so the stat IS the range; the palette base only
## survives when the stat is absent. Never a literal here. No-op before build() (no light yet).
func apply_stats(stats: Dictionary) -> void:
	if _fill == null or not stats.has("fill_light_range"):
		return
	_fill.omni_range = maxf(0.0, float(stats["fill_light_range"]))


## One frame of walking. p_move_x / p_move_z are the captured int8 world-space axes
## (-127..127, already rotated by the camera yaw by app/input_capture.gd).
func move(p_dt: float, p_move_x: int, p_move_z: int) -> void:
	var tx := float(p_move_x) / AXIS_127 * RUN_SPEED
	var tz := float(p_move_z) / AXIS_127 * RUN_SPEED
	var rate := ACCEL if (p_move_x != 0 or p_move_z != 0) else FRICTION
	vx = _approach(vx, tx, rate * p_dt)
	vz = _approach(vz, tz, rate * p_dt)
	x = clampf(x + vx * p_dt, -BOUND_X, BOUND_X)
	z = clampf(z + vz * p_dt, -BOUND_Z, BOUND_Z)
	if absf(x) >= BOUND_X:
		vx = 0.0
	if absf(z) >= BOUND_Z:
		vz = 0.0
	if model != null:
		model.position = Vector3(x, y, z)
		model.rotation.y = deg_to_rad(float(rig.yaw_deg)) if rig != null else 0.0
	_anim(p_dt)
	if rig != null:
		rig.update_rig(Vector3(x, y, z), p_dt)
		_clamp_camera()


## The hall is a closed box, so the third-person boom cannot sit outside it. The level rig
## has no camera collision because there is nothing but void to clip (D-T082-1); here there
## are walls, and the arrival point (0, +8) is only 2 u from the south wall, so an
## unclamped 7 u boom renders the back of that wall. The boom is shortened along its own
## direction until the camera is inside the hall, which keeps the view behind the player
## instead of snapping it to a wall.
func _clamp_camera() -> void:
	var pivot: Vector3 = CameraRigScript.pivot_for(Vector3(x, y, z))
	var want: Vector3 = CameraRigScript.camera_position(Vector3(x, y, z), rig.yaw_deg,
			rig.pitch_deg)
	var off: Vector3 = want - pivot
	var t := 1.0
	while t > CAM_MIN_T:
		if _camera_inside(pivot + off * t):
			break
		t -= 0.05
	t = maxf(t, CAM_MIN_T)
	rig.position = pivot + off * t
	if rig.is_inside_tree() and rig.position.distance_to(pivot) > 0.01:
		rig.look_at(pivot, Vector3.UP)


static func _camera_inside(p: Vector3) -> bool:
	return absf(p.x) <= CAM_X and absf(p.z) <= CAM_Z \
			and p.y >= CAM_Y_MIN and p.y <= CAM_Y_MAX


## The feet position the antechamber's proximity test measures from (not `position`:
## that is Node3D's own property).
func feet() -> Vector3:
	return Vector3(x, y, z)


## The camera's forward, flattened onto the floor: the 60-degree look cone's axis.
func look_dir() -> Vector3:
	if rig == null:
		return Vector3(0.0, 0.0, -1.0)
	var t := deg_to_rad(float(rig.yaw_deg))
	return Vector3(-sin(t), 0.0, -cos(t))


## The figure's base pass (J11): the T-015 .glb carries no material by design
## (export_materials="NONE"; the palette rides the vertex colours), so without a base
## override every surface renders Godot's default WHITE and the authored palette is never
## seen. Unshaded with vertex colours as albedo, the same base pass gifts_view.gd applies
## to the gift models - this hall has no sun of its own, and the palette intent is the
## authored hex. Surface override materials do not touch the limb nodes' transforms, so
## the gait below is unaffected.
static func _player_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## Adds the base material to every mesh surface under the figure.
static func _apply_player_body_material(p_root: Node3D) -> void:
	var mat := _player_body_material()
	var stack: Array = [p_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)


## Mouse motion -> the rig (only while the mouse is captured; the caller gates it).
func apply_mouse(p_dx: float, p_dy: float, p_sens: float) -> void:
	if rig == null:
		return
	var np: Vector2 = CameraRigScript.apply_mouse(rig.yaw_deg, rig.pitch_deg, p_dx, p_dy, p_sens)
	rig.yaw_deg = np.x
	rig.pitch_deg = np.y


## Horizontal speed (u/s), for the gait amplitude.
func speed() -> float:
	return sqrt(vx * vx + vz * vz)


static func _approach(p_now: float, p_target: float, p_step: float) -> float:
	if p_now < p_target:
		return minf(p_now + p_step, p_target)
	return maxf(p_now - p_step, p_target)


## A compact gait: legs swing apart, arms counter them, scaled by the horizontal speed.
## The level's full pose system (world.gd) is not duplicated here - the hall is a walk.
func _anim(p_dt: float) -> void:
	if _limbs.is_empty():
		return
	var amp := clampf(speed() / RUN_SPEED, 0.0, 1.0)
	_phase = fmod(_phase + GAIT_RATE * amp * p_dt, TAU)
	var swing := sin(_phase) * GAIT_SWING * amp
	var pairs := [swing, -swing, -swing, swing]   # ArmL, ArmR, LegL, LegR
	for i in _limbs.size():
		var limb: Node3D = _limbs[i]
		if limb != null and is_instance_valid(limb):
			limb.rotation.x = float(pairs[i])
