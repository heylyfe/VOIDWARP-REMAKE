extends Node3D
#
# Third-person orbit camera (ticket T-082). All numbers are [CONTESTABLE] (no earlier document
# states any of them) and pinned in DECISIONS D-T082-1:
#   - the camera orbits a pivot 2.5 u above the player's feet on a 7.0 u sphere;
#     offset = R_y(yaw) * R_x(pitch) * (0, 0, 7.0), look target = the pivot;
#   - pitch default -18 deg (looking down), clamped to -60..+30;
#   - FOV 75 deg (settings range 60-90); mouse 0.12 deg/px default;
#   - NO camera collision: there is nothing but void to clip;
#   - the camera's HEIGHT above the world follows the player's feet through a 0.12 s
#     exponential spring so the 0.5 u auto step-up does not jolt the view.
# The math lives in pure static functions (headless tests exercise them directly); the node
# side is the thin applier world.gd drives. The rig reads sim state, never writes it — it
# has no reference to any sim object at all (the replay test in tests/test_input.gd proves
# a randomly moved camera cannot change sim state).
#
# MOUSE-LOOK (J5, supersedes D-T082-4's "no path to the yaw"): apply_mouse() is now called
# by world.gd's mouse-motion handler, but ONLY while the mouse is captured. When released
# the rig has no turn path again. The capture state machine is the pure toggle below; the
# sanctioned wiring is: captured -> apply_mouse with the settings' sensitivity; released ->
# no motion applied; Ctrl edge (this file's next_mouse_locked) is the only toggle.

const DISTANCE := 7.0
const PIVOT_HEIGHT := 2.5
const PITCH_DEFAULT := -18.0
const PITCH_MIN := -60.0
const PITCH_MAX := 30.0
const FOV_DEFAULT := 75.0
const MOUSE_SENS_DEFAULT := 0.12
const SPRING_TIME := 0.12


var yaw_deg: float = 0.0
var pitch_deg: float = PITCH_DEFAULT
var _spring_y: float = 0.0


## Camera offset from the pivot (R_y(yaw) * R_x(pitch) applied to (0, 0, DISTANCE)).
## pitch negative = camera above the pivot looking down (default -18 = looking down 18 deg).
static func camera_offset(yaw_deg_: float, pitch_deg_: float) -> Vector3:
	var a := deg_to_rad(pitch_deg_)
	var t := deg_to_rad(yaw_deg_)
	var lx := 0.0
	var ly := -DISTANCE * sin(a)
	var lz := DISTANCE * cos(a)
	return Vector3(lx * cos(t) + lz * sin(t), ly, -lx * sin(t) + lz * cos(t))


## World position of the camera for a player at `feet` (the feet y is the SPRUNG height).
static func camera_position(feet: Vector3, yaw_deg_: float, pitch_deg_: float) -> Vector3:
	return feet + Vector3(0.0, PIVOT_HEIGHT, 0.0) + camera_offset(yaw_deg_, pitch_deg_)


## Look target for the camera: PIVOT_HEIGHT above the feet.
static func pivot_for(feet: Vector3) -> Vector3:
	return feet + Vector3(0.0, PIVOT_HEIGHT, 0.0)


## Mouse motion -> new (yaw, pitch). Godot yaw + = looking left, so mouse-right (dx > 0)
## subtracts; pitch + = looking up, so mouse-down (dy > 0) subtracts. Sensitivity is deg/px
## from the settings (default 0.12, range 0.02-0.30).
static func apply_mouse(yaw_deg_: float, pitch_deg_: float, dx_px: float, dy_px: float,
		sens_deg_per_px: float) -> Vector2:
	var yaw2 := yaw_deg_ - dx_px * sens_deg_per_px
	var pitch2 := clampf(pitch_deg_ - dy_px * sens_deg_per_px, PITCH_MIN, PITCH_MAX)
	return Vector2(yaw2, pitch2)


## The mouse-capture toggle (J5): pure, so the headless test can pin it. toggle_edge is the
## Ctrl edge this tick (already edge-detected against the previous tick by the caller);
## release_request is any force-release (the APP_PAUSE edge, and build/teardown/death use
## the same state directly). A release wins over a same-tick toggle: the annotations say
## "release on pause, menu and death screens" without exception.
static func next_mouse_locked(locked: bool, toggle_edge: bool, release_request: bool) -> bool:
	if release_request:
		return false
	if toggle_edge:
		return not locked
	return locked


## The Input.mouse_mode for a lock state (single point so the wiring cannot drift).
static func mouse_mode_for(locked: bool) -> int:
	return Input.MOUSE_MODE_CAPTURED if locked else Input.MOUSE_MODE_VISIBLE


## Exponential spring: the camera height eases toward the feet height with time constant
## 0.12 s: y += (target - y) * (1 - e^(-dt/0.12)). dt = 0 is a no-op; a 0.5 u step-up passes
## ~63 % after 0.12 s, ~95 % after 3 time constants. Only DOWNWARD and step-up deltas pass
## through here — the caller feeds it the same feet y the sim reported, never sim state.
static func spring_y(current_y: float, target_y: float, dt_seconds: float) -> float:
	var k := 1.0 - exp(-dt_seconds / SPRING_TIME)
	return current_y + (target_y - current_y) * k


## The node-side applier: call once per frame from the main scene. `feet` is the sim-reported
## feet position. Springs the height, then moves this node to the camera position and aims
## it at the pivot. Safe to call before the node enters the tree (positions only, no look_at).
func update_rig(feet: Vector3, dt_seconds: float) -> void:
	_spring_y = spring_y(_spring_y, feet.y, dt_seconds)
	var pos := camera_position(Vector3(feet.x, _spring_y, feet.z), yaw_deg, pitch_deg)
	var piv := pivot_for(Vector3(feet.x, _spring_y, feet.z))
	if is_inside_tree():
		look_at_from_position(pos, piv, Vector3.UP)
	else:
		transform = Transform3D(Basis.IDENTITY, pos)
