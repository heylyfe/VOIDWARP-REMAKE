extends Node3D

const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads
#
# The hang glider the player flies under while gliding (owner request 2026-11-20).
# Model: assets_src/blender/glider.py -> res://assets/models/glider.glb (origin = the
# hang point). This node is built ONCE by world.gd, parented to the player figure, and
# driven once per view tick by sync(); nothing is created or freed per frame.
#
#   closed    open == 0: hidden, every node at its rest transform, nothing is written.
#   deploy    gliding: open climbs to 1 over DEPLOY_TICKS (0.20 s); the wing's span
#             snaps out from FOLDED_SPAN with an ease-out-back overshoot.
#   gliding   open == 1: the rig banks into lateral motion (roll), pitches with vertical
#             velocity (nose down falling fast, nose up under the updraft rise), and the
#             wing ripples (a small tick-driven scale oscillation).
#   fold      glide ended: open falls to 0 over FOLD_TICKS (0.15 s) - still visible while
#             the wing folds in - then every node snaps back to rest and hides.
#
# Read-only on sim state: the inputs are ctl.gliding and the player's velocity in the
# figure's local frame. Tick-driven (one call = one 60 Hz tick), never wall clock, so two
# identical runs pose identically.

const GLIDER_MODEL := "res://assets/models/glider.glb"
const PART_NAMES := ["Wing", "WingRim", "Keel", "Crossbar", "AFrame", "Pod", "PodFrame"]
const SPAN_PARTS := ["Wing", "WingRim", "Crossbar"]   # what the deploy unfolds + the flex
const FLEX_PARTS := ["Wing", "WingRim"]

## This node sits at the chest pivot in the 1.80 u figure's space (1.20 u up, 0.20 u
## behind the body centre - Godot +Z is behind the figure), and the bank/pitch rotate
## about it, so the pod frame stays around the torso while the wing tilts. The model is
## lifted HANG_OFFSET above it: the hang point lands at 2.25 u (0.45 u over the hat) and
## the frame (authored 1.05 u under the hang point) rings the chest at 1.20 u.
const MOUNT := Vector3(0.0, 1.20, 0.20)
const HANG_OFFSET := Vector3(0.0, 1.05, 0.0)

const DEPLOY_TICKS := 12        # 0.20 s at 60 Hz
const FOLD_TICKS := 9           # 0.15 s
const FOLDED_SPAN := 0.08       # wing x-scale when fully folded
const BACK_OVERSHOOT := 1.70158 # ease-out-back constant (the snap past full span)

const MAX_ROLL := 0.45          # rad, at ROLL_REF_SPEED of lateral speed
const ROLL_REF_SPEED := 10.0    # u/s, the glider kit's glide_horizontal_speed
const PITCH_PER_VY := 0.05      # rad per u/s of vertical velocity (+vy = nose up)
const MAX_PITCH := 0.45
const ATTITUDE_K := 0.2         # per-tick blend toward the roll/pitch target

const FLEX_AMP := 0.025         # wing ripple: +-2.5 % span
const FLEX_BILLOW := 1.5        # vertical ripple = FLEX_BILLOW x the span ripple
const FLEX_RATE := 0.33         # rad per tick (~3.2 Hz)

var open := 0.0       # 0 = folded/hidden, 1 = fully deployed
var roll := 0.0       # rad about the figure's back axis (+ = right wing up)
var pitch := 0.0      # rad about the figure's right axis (+ = nose up)
var flex_tick := 0
var model: Node3D = null
var parts := {}       # part name -> Node3D
var rest := {}        # part name -> Transform3D (authored)
var _at_rest := true


## Load the glb, give it its materials, find the named parts. false when the model or a
## part is missing (the caller then drops this node).

# U4 (Terra finding 3): release this view's surface-override materials before the node
# is destroyed, on EVERY free path (the world's teardown or a direct free()). A
# MeshInstance3D's override Refs die before its rendering-server instance is freed, so
# freeing with the overrides still set leaves a dangling material RID and the dummy
# renderer prints `ERROR: Parameter "material" is null`; clearing them here first is
# the ownership fix (see asset_load.gd release_materials).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		AssetLoadScript.release_materials(self)
func build() -> bool:
	name = "Glider"
	position = MOUNT
	visible = false
	var ps: PackedScene = AssetLoadScript.scene(GLIDER_MODEL)
	if ps == null:
		return false
	model = ps.instantiate() as Node3D
	if model == null:
		return false
	model.position = HANG_OFFSET
	add_child(model)
	for pn in PART_NAMES:
		var n := model.find_child(pn, true, false) as Node3D
		if n == null:
			return false
		parts[pn] = n
		rest[pn] = n.transform
	_apply_materials()
	return true


## The glb carries no material (vertex colours are the palette). Everything is unshaded
## vertex colour like the figure; the Wing membrane alone is alpha-blended (its vertex
## alpha, baked by glider.py, is the translucency) and double-sided.
func _apply_materials() -> void:
	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.vertex_color_use_as_albedo = true
	solid.albedo_color = Color(1.0, 1.0, 1.0)
	var membrane := StandardMaterial3D.new()
	membrane.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	membrane.vertex_color_use_as_albedo = true
	membrane.albedo_color = Color(1.0, 1.0, 1.0)
	membrane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pn in PART_NAMES:
		var mi := parts[pn] as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, membrane if pn == "Wing" else solid)


## One view tick. gliding = ctl.gliding; vel_local = the player's velocity in the
## figure's frame (x = right, y = up, z = back).
func sync(gliding: bool, vel_local: Vector3) -> void:
	if gliding:
		open = minf(1.0, open + 1.0 / float(DEPLOY_TICKS))
	else:
		open = maxf(0.0, open - 1.0 / float(FOLD_TICKS))
	if open <= 0.0:
		_reset()
		return
	visible = true
	_at_rest = false
	flex_tick += 1
	roll += (roll_target(vel_local.x) - roll) * ATTITUDE_K
	pitch += (pitch_target(vel_local.y) - pitch) * ATTITUDE_K
	transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), MOUNT)
	var span := span_scale(open, gliding)
	var flex := sin(float(flex_tick) * FLEX_RATE) * FLEX_AMP * open
	for pn in SPAN_PARTS:
		var r: Transform3D = rest[pn]
		var sx := span
		var sy := 1.0
		if FLEX_PARTS.has(pn):
			sx = span * (1.0 + flex)
			sy = 1.0 + flex * FLEX_BILLOW
		(parts[pn] as Node3D).transform = Transform3D(
				Basis.from_scale(Vector3(sx, sy, 1.0)) * r.basis, r.origin)


## Folded and hidden: every node back on its authored transform. Writes only on the
## first closed tick, so a player who is not gliding costs nothing and nothing moves.
func _reset() -> void:
	if _at_rest:
		return
	_at_rest = true
	visible = false
	roll = 0.0
	pitch = 0.0
	flex_tick = 0
	transform = Transform3D(Basis(), MOUNT)
	for pn in PART_NAMES:
		(parts[pn] as Node3D).transform = rest[pn]


## Bank into the turn: lateral speed to the right dips the right wing (negative roll).
static func roll_target(lateral: float) -> float:
	return -clampf(lateral / ROLL_REF_SPEED, -1.0, 1.0) * MAX_ROLL


## Nose down when sinking, nose up when rising (the updraft): +vy = +pitch.
static func pitch_target(vy: float) -> float:
	return clampf(vy * PITCH_PER_VY, -MAX_PITCH, MAX_PITCH)


## The wing's x-scale for an open fraction: deploying snaps out with an ease-out-back
## overshoot (it passes full span and settles); folding draws in on a smoothstep.
static func span_scale(p_open: float, deploying: bool) -> float:
	var t := clampf(p_open, 0.0, 1.0)
	var e: float
	if deploying:
		var u := t - 1.0
		e = 1.0 + (BACK_OVERSHOOT + 1.0) * u * u * u + BACK_OVERSHOOT * u * u
	else:
		e = t * t * (3.0 - 2.0 * t)
	return FOLDED_SPAN + (1.0 - FOLDED_SPAN) * e
