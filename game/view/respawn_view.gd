extends Node3D
#
# Void-fall respawn view (ticket T-085; research/fable-tickets.md section 2.5,
# DESIGN.md sections 3.1 / 3.2). View layer only: it reads the sim's respawn
# event and the controller's invulnerability countdown and never writes sim state.
#
# The section 2.5 rows this node owns:
#   reappear      on the last safe tile: a vertical white streak 3 u tall that
#                 collapses onto the tile over 9 ticks, and a ground ring that
#                 expands to 1.5 u over the same 9 ticks;
#   invulnerability 60 ticks (1.0 s, binding): the player model blinks at 8 Hz
#                 with a white rim; the rim disappears ON the tick invulnerability
#                 ends, not a frame later.
#
# The blink is a tick function, not a frame one: 8 Hz is 7.5 ticks per cycle, so
# the half period is 3.75 ticks and the phase is measured from the respawn tick
# (D-T085-6). The rim is drawn here as a back-face white shell around the player
# (the caller feeds the player's position); the player model's own blink is
# blink_on(), which the caller applies to the model it owns.
#
# "Death at 0 charges: no streak, no reappear" is the caller's contract: it
# simply never calls on_respawn() on that path.

const PLAYER_MODEL := "res://assets/models/player_figure.glb"

## Reappear (section 2.5, reappear row).
const STREAK_HEIGHT := 3.0     # u
const STREAK_TICKS := 9        # ticks to collapse onto the tile
const RING_MAX := 1.5          # u, the ground ring's final radius
const STREAK_RADIUS := 0.06    # u, the streak's own width
## Invulnerability (section 2.5, invulnerability row; binding).
const INVULN_TICKS := 60       # 1.0 s
const BLINK_HZ := 8.0          # the player model's blink rate
const WHITE := Color(1.0, 1.0, 1.0)

var _respawn_tick := -1        # the sim tick of the last respawn (-1: none yet)
var _tick := 0
var _pos := Vector3.ZERO       # the last safe tile's top centre
var _streak: MeshInstance3D
var _ring: MeshInstance3D
var _rim: MeshInstance3D
var _rim_alpha := 0.0


func _init() -> void:
	_build_streak()
	_build_ring()
	_build_rim()


func _build_streak() -> void:
	var mesh := CylinderMesh.new()
	mesh.height = STREAK_HEIGHT
	mesh.top_radius = STREAK_RADIUS
	mesh.bottom_radius = STREAK_RADIUS
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _white_material(0.9, false)
	mi.visible = false
	add_child(mi)
	_streak = mi


func _build_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	mesh.rings = 3
	mesh.ring_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _white_material(0.8, false)
	mi.visible = false
	add_child(mi)
	_ring = mi


## The white rim: the player figure drawn back-faces-only, so it reads as an
## outline around the model the caller owns.
func _build_rim() -> void:
	var mi := MeshInstance3D.new()
	var ps: PackedScene = load(PLAYER_MODEL)
	if ps != null:
		var inst: Node3D = ps.instantiate()
		var src := _first_mesh(inst)
		if src != null:
			mi.mesh = src.mesh
		inst.free()
	mi.material_override = _white_material(1.0, true)
	mi.scale = Vector3(1.08, 1.08, 1.08)
	mi.visible = false
	add_child(mi)
	_rim = mi


static func _first_mesh(root: Node) -> MeshInstance3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null


static func _white_material(alpha: float, outline: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(WHITE.r, WHITE.g, WHITE.b, alpha)
	m.disable_fog = true
	m.disable_receive_shadows = true
	if outline:
		m.cull_mode = BaseMaterial3D.CULL_FRONT
	return m


## The sim's respawn event: the tick it fired on and the last safe tile's top
## centre (the controller's respawn event carries the tile key; the caller turns
## it into a world position).
func on_respawn(tick: int, pos: Vector3) -> void:
	_respawn_tick = tick
	_tick = tick
	_pos = pos
	position = pos
	_streak.visible = true
	_ring.visible = true
	_rim.position = Vector3.ZERO
	_rim.visible = true
	_rim_alpha = 1.0
	_apply()


## The per-tick sync: invuln_ticks_left is the controller's invulnerability
## countdown in ticks (ceil(invuln * 60)); player_pos is where the player model
## stands this tick (the rim follows it).
func sync_tick(tick: int, invuln_ticks_left: int, player_pos: Vector3 = Vector3.ZERO) -> void:
	_tick = tick
	if player_pos != Vector3.ZERO:
		_rim.position = player_pos - _pos
	_apply(invuln_ticks_left)


## The blink phase: 8 Hz = 7.5 ticks per cycle, half period 3.75 ticks, measured
## from the respawn tick. False once invulnerability has ended.
static func blink_on(elapsed_ticks: float) -> bool:
	if elapsed_ticks < 0.0:
		return false
	var half := 60.0 / (2.0 * BLINK_HZ)
	return fmod(elapsed_ticks, 2.0 * half) < half


## The rim's alpha for a countdown value: 1 while invulnerability holds, 0 on the
## tick it ends (section 2.5: "the rim disappears on the tick invulnerability ends").
static func rim_alpha_for(invuln_ticks_left: int) -> float:
	return 1.0 if invuln_ticks_left > 0 else 0.0


func _apply(invuln_ticks_left: int = -1) -> void:
	# the reappear: the streak collapses onto the tile over 9 ticks, the ring
	# expands to 1.5 u over the same 9 ticks
	var age: float = float(_tick - _respawn_tick) if _respawn_tick >= 0 else float(STREAK_TICKS)
	var k: float = clampf(age / float(STREAK_TICKS), 0.0, 1.0)
	var h: float = STREAK_HEIGHT * (1.0 - k)
	_streak.visible = _respawn_tick >= 0 and h > 0.0
	_streak.scale = Vector3(1.0, maxf(h / STREAK_HEIGHT, 0.001), 1.0)
	_streak.position = Vector3(0.0, h * 0.5, 0.0)
	_ring.visible = _respawn_tick >= 0 and k < 1.0
	_ring.scale = Vector3(maxf(k * RING_MAX, 0.001), 1.0, maxf(k * RING_MAX, 0.001))
	_ring.position = Vector3(0.0, 0.02, 0.0)
	# the invulnerability blink + rim
	if invuln_ticks_left >= 0:
		_rim_alpha = rim_alpha_for(invuln_ticks_left)
		var elapsed: float = float(INVULN_TICKS - invuln_ticks_left)
		_rim.visible = _rim_alpha > 0.0 and blink_on(elapsed)
	else:
		_rim.visible = _rim_alpha > 0.0
	(_rim.material_override as StandardMaterial3D).albedo_color = \
		Color(WHITE.r, WHITE.g, WHITE.b, _rim_alpha)


# ---- read-outs for the caller and the tests -------------------------------------

func streak_visible() -> bool:
	return _streak.visible


func streak_height() -> float:
	return STREAK_HEIGHT * _streak.scale.y if _streak.visible else 0.0


func ring_radius() -> float:
	return _ring.scale.x if _ring.visible else 0.0


func rim_visible() -> bool:
	return _rim.visible


func rim_alpha() -> float:
	return _rim_alpha


func respawn_tick() -> int:
	return _respawn_tick
