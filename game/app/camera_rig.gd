extends Node3D
#
# Third-person orbit camera (ticket T-082). All numbers are [CONTESTABLE] (no earlier document
# states any of them) and pinned in DECISIONS D-T082-1:
#   - the camera orbits a pivot 2.5 u above the player's feet on a 7.0 u sphere;
#     offset = R_y(yaw) * R_x(pitch) * (0, 0, 7.0), look target = the pivot;
#   - pitch default -18 deg (looking down), clamped to -60..+30;
#   - FOV 75 deg (settings range 60-90); mouse 0.12 deg/px default;
#   - camera collision: the camera sweeps a PULL_RADIUS sphere from the pivot out along its
#     offset against the level's collision table (world.gd's `w`, the pure sim/collision.gd
#     geometry; no engine physics, a fixed 0.1 u march + bisection, so deterministic). A hit
#     pulls the distance in — snapping this frame, never below PULL_MIN, keeping PULL_SKIN
#     off the surface; clear air eases the distance back out and lands EXACTLY on DISTANCE,
#     so with nothing in the way the applier places the camera at the D-T082-1 offset
#     bit-for-bit. Yaw/pitch, the offset shape, FOV and the mouse-lock state machine are
#     untouched. The pull constants are [CONTESTABLE] pending a DECISIONS pin;
#   - the camera's HEIGHT above the world follows the player's feet through a 0.12 s
#     exponential spring so the 0.5 u auto step-up does not jolt the view.
# The math lives in pure static functions (headless tests exercise them directly); the node
# side is the thin applier world.gd drives. The rig reads sim state, never writes it: the
# only sim data it touches is the collision table `w`, read through its parent world for the
# ray query as a plain Dictionary (nothing is written, and the replay test in
# tests/test_input.gd still proves a randomly moved camera cannot change sim state).
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

# Camera collision (all [CONTESTABLE], un-pinned — DECISIONS carries no entry yet).
const NO_HIT := -1.0            # "nothing between the pivot and the camera"
const PULL_MIN := 0.5           # the camera never collapses closer than this to the pivot
const PULL_SKIN := 0.15         # gap kept between the camera sphere and the geometry it hit
const PULL_RADIUS := 0.25       # camera sphere radius for the sweep
const PULL_STEP := 0.1          # march step; well under the 1 u slab thickness, no tunneling
const PULL_RETURN_TIME := 0.2   # exponential ease-back once the way is clear

const CollisionScript := preload("res://sim/collision.gd")


var yaw_deg: float = 0.0
var pitch_deg: float = PITCH_DEFAULT
var _spring_y: float = 0.0
var _pull_distance: float = DISTANCE


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


## CAMERA COLLISION — the pull decision, pure. Given the desired camera distance and the
## hit distance from the pivot along the camera ray (NO_HIT or a hit at/beyond the desired
## distance = clear), returns the camera distance to use: the full desired distance when
## clear, otherwise the hit pulled in by PULL_SKIN, clamped to never below PULL_MIN (the
## camera must not crush into the player) and never beyond desired.
static func camera_distance(desired_dist: float, hit_dist: float) -> float:
	if hit_dist < 0.0 or hit_dist >= desired_dist:
		return desired_dist
	return clampf(hit_dist - PULL_SKIN, PULL_MIN, desired_dist)


## CAMERA COLLISION — distance spring, pure. Pull-in snaps (a wall between the camera and
## the player must not get one clipped frame); easing back out is exponential with time
## constant PULL_RETURN_TIME, and within 0.01 u of the target it lands EXACTLY on the
## target, so a clear rig returns to the configured offset exactly. dt = 0 is a no-op.
static func next_pull_distance(current: float, target: float, dt_seconds: float) -> float:
	if target <= current:
		return target
	var out := current + (target - current) * (1.0 - exp(-dt_seconds / PULL_RETURN_TIME))
	if target - out < 0.01:
		return target
	return out


## CAMERA COLLISION — the sweep, pure and deterministic: march the ray pivot -> pivot +
## dir * desired_dist through the level's collision table (the Dictionary sim/collision.gd's
## make_world builds; READ only) with a PULL_RADIUS sphere, and return the distance from the
## pivot at which the sphere first touches solid geometry, or NO_HIT. Fixed PULL_STEP march
## (under the 1 u slab thickness, so no tunneling) plus a bisection refine of the touch
## point. Tile slabs and prop boxes only — enemies and pads do not block the camera.
static func camera_hit_distance(w: Dictionary, pivot: Vector3, dir: Vector3,
		desired_dist: float) -> float:
	var d := dir
	if desired_dist <= 0.0 or d.length_squared() == 0.0:
		return NO_HIT
	d = d / d.length()
	var clear_t := 0.0
	while clear_t < desired_dist:
		var t := minf(clear_t + PULL_STEP, desired_dist)
		if not _sphere_clear(w, pivot + d * t):
			return _refine_hit(w, pivot, d, clear_t, t)
		clear_t = t
	return NO_HIT


## PULL_RADIUS sphere at p against solid boxes: true when it touches nothing. Boxes span one
## cell [cx, cx+1] x [cz, cz+1] x [lo, hi]; the scan covers only the columns the sphere's
## footprint overlaps. The boxes come from sim/collision.gd's own column helper, so the
## camera sweeps the exact geometry the sim moves bodies against — one source of truth.
static func _sphere_clear(w: Dictionary, p: Vector3) -> bool:
	var r2 := PULL_RADIUS * PULL_RADIUS
	var x0 := int(floor(p.x - PULL_RADIUS))
	var x1 := int(floor(p.x + PULL_RADIUS))
	var z0 := int(floor(p.z - PULL_RADIUS))
	var z1 := int(floor(p.z + PULL_RADIUS))
	var boxes: Array = []
	var cx := x0
	while cx <= x1:
		var cz := z0
		while cz <= z1:
			boxes.clear()
			CollisionScript._boxes_in_column(w, cx, cz, boxes)
			for b in boxes:
				var dx: float = clampf(p.x, float(cx), float(cx) + 1.0) - p.x
				var dz: float = clampf(p.z, float(cz), float(cz) + 1.0) - p.z
				var dy: float = clampf(p.y, float(b["lo"]), float(b["hi"])) - p.y
				if dx * dx + dy * dy + dz * dz < r2:
					return false
			cz += 1
		cx += 1
	return true


## Bisects the first-touch fraction between the last clear sample and the first blocked one
## (12 steps of a 0.1 u bracket = sub-0.00003 u precision; plenty for a view placement).
static func _refine_hit(w: Dictionary, pivot: Vector3, d: Vector3, clear_t: float,
		hit_t: float) -> float:
	var lo := clear_t
	var hi := hit_t
	for i in 12:
		var mid := (lo + hi) * 0.5
		if _sphere_clear(w, pivot + d * mid):
			lo = mid
		else:
			hi = mid
	return hi


## The node-side applier: call once per frame from the main scene. `feet` is the sim-reported
## feet position. Springs the height, sweeps the camera ray against the level's collision
## table (see camera_hit_distance; no table -> no pull), springs the pull distance, then
## moves this node to the camera position and aims it at the pivot. Safe to call before the
## node enters the tree (positions only, no look_at).
func update_rig(feet: Vector3, dt_seconds: float) -> void:
	_spring_y = spring_y(_spring_y, feet.y, dt_seconds)
	var f := Vector3(feet.x, _spring_y, feet.z)
	var piv := pivot_for(f)
	var off := camera_offset(yaw_deg, pitch_deg)
	_pull_distance = next_pull_distance(_pull_distance,
			_target_distance(piv, off), dt_seconds)
	var pos := piv + off if _pull_distance == DISTANCE \
			else piv + (off / DISTANCE) * _pull_distance
	if is_inside_tree():
		look_at_from_position(pos, piv, Vector3.UP)
	else:
		transform = Transform3D(Basis.IDENTITY, pos)


## The distance the rig wants this frame: the pure camera_distance applied to the sweep of
## the camera ray through the level's collision table. Without a table (the menu, teardown,
## a rig with no parent) nothing is in the way and the target is the full DISTANCE.
func _target_distance(piv: Vector3, off: Vector3) -> float:
	var cw := _collision_world()
	if cw.is_empty():
		return DISTANCE
	return camera_distance(DISTANCE,
			camera_hit_distance(cw, piv, off / DISTANCE, DISTANCE))


## The level's collision table, read-only, through the parent world (world.gd keeps it in
## its `w` member and the rig is its direct child). Returns {} when there is none. Never
## written: the sweep query only reads the Dictionary (see the header note).
func _collision_world() -> Dictionary:
	var p := get_parent()
	if p == null:
		return {}
	var cw: Variant = (p as Node).get("w")
	if cw is Dictionary and not (cw as Dictionary).is_empty() \
			and (cw as Dictionary).has("cols"):
		return cw
	return {}
