extends Node3D
#
# Tripmine view (ticket T-021; DESIGN.md sections 3.3 / 5.7). Renders the fake
# gift hazard the sim's mine state (sim/mines.gd) describes:
#   - the box: the shared tripmine model (game/assets/models/tripmine_box.glb -
#     black framed box, six-pointed star centre, built in T-015);
#   - slow rotation: one full turn per 4.0 s (TURN_PERIOD), the section 3.3
#     rotation cycle (the sprite roster's 5-frame cycle is the same turn);
#   - PINK PARTICLES (,color #FF4FD8, section 3.3) - a constant small emitter
#     above the box, visible only when the mine's tell is showing;
#   - TELL (section 3.3): beyond TELL_DISTANCE (12 u) the mine shows the same
#     rim glow as a black gift (the additive emission overlay below) and the
#     particles are dimmed to nothing; inside 12 u the particles and the star
#     are visible. The model geometry is shared; the tell is the emitter +
#     the rim, exactly like the gift view's rim (D-T021-6).
#
# The caller drives sync() every frame (or on change); this node never writes
# sim state. No engine calls beyond the view surface (Node3D + materials).

const GiftsViewScript := preload("res://view/gifts_view.gd")
const MinesScript := preload("res://sim/mines.gd")

const MODEL := "res://assets/models/tripmine_box.glb"
## The turn: one full revolution per 4.0 s (DESIGN.md section 3.3 cycle).
const TURN_PERIOD := 4.0
const TAU_F := 6.283185307179586
## The tell colour (section 3.3, the particles + star): #FF4FD8.
const PINK := Color(1.0, 0.309804, 0.847059)

var _nodes: Array = []   # per mine slot index: Node3D (the box + emitter)
var _mines: RefCounted = null
var _time: float = 0.0


## Builds one box node per LIVE mine slot. level: the Level dict; mines_state:
## the sim's mine state (MinesScript.create(...)) - only occ == 1 slots appear.
func setup(level: Dictionary, mines_state: RefCounted) -> void:
	_time = 0.0
	_mines = mines_state
	for child in get_children():
		child.free()
	var ids: Array = mines_state.ids
	for line_i in ids.size():
		var slot: int = int(ids[line_i])
		var box := MeshInstance3D.new()
		# the shared box mesh; the star is baked into the model (D-T021-6)
		var ps: PackedScene = load("res://assets/models/tripmine_box.glb")
		var inst: Node3D = ps.instantiate()
		box.add_child(inst)
		var pos: Vector3 = mines_state.point(slot)
		box.position = pos
		add_child(box)
		# the "ordinary gift" half of the tell: the same additive rim overlay the
		# black gifts wear (sim/gifts.gd view, TERRAIN_SPEC section 12.2, x1.5)
		box.material_overlay = GiftsViewScript.emission_material(1.5)
		# the emitter: the tell's pink sparkles (dimmed/hidden by sync)
		var puffs := CPUParticles3D.new()
		puffs.amount = 8
		puffs.lifetime = 1.2
		puffs.mesh = _spark_mesh()
		puffs.emitting = true
		puffs.position = Vector3(0.0, 0.6, 0.0)
		box.add_child(puffs)
		_nodes.append({"node": box, "slot": slot})
	sync()


## The clock: seconds of sim/level time (the caller owns it; no engine clock).
func set_time(t: float) -> void:
	_time = t


## The tell: inside the tell radius the particles + star show; beyond it the
## mine reads as a plain gift (the rim glow only). Distance in world u.
static func tell_visible(dist: float) -> bool:
	return dist <= TELL_DISTANCE


## Syncs the rotation, the rim glow and the tell state from the caller's eye
## position (the camera). Call every frame or on change. A consumed mine
## (defused, shielded, saved or detonated) is removed from view.
func sync(eye: Vector3 = Vector3.ZERO) -> void:
	var t: float = _time
	for line_i in _nodes.size():
		var entry: Dictionary = _nodes[line_i]
		var box: Node3D = entry["node"]
		var slot: int = int(entry["slot"])
		if _mines != null:
			box.visible = not _mines.is_consumed(slot)
		# one full turn per TURN_PERIOD seconds, phase from the slot id so
		# neighbouring mines in a line do not spin in lockstep
		box.rotation.y = t * TAU_F / TURN_PERIOD + float(line_i) * 0.7
		# the rim glow: the gift view's additive overlay, always on (the rim is
		# the "ordinary gift look" half of the tell)
		# the emitter: visible only while the tell is showing
		var puff: CPUParticles3D = _emitter_of(box)
		if puff == null:
			continue
		puff.emitting = tell_visible(_eye_dist(box, eye)) or eye == Vector3.ZERO


func _emitter_of(box: Node3D) -> CPUParticles3D:
	for c in box.get_children():
		if c is CPUParticles3D:
			return c
	return null


## The spark: a tiny billboarded sphere per particle, in the tell pink. Mesh
## only; the emitter owns the motion.
static func _spark_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = PINK
	mat.emission_enabled = true
	mat.emission = PINK
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.material = mat
	return m


func _eye_dist(box: Node3D, eye: Vector3) -> float:
	var dx: float = box.position.x - eye.x
	var dy: float = box.position.y - eye.y
	var dz: float = box.position.z - eye.z
	return sqrt(dx * dx + dy * dy + dz * dz)
