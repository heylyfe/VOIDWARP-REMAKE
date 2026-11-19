extends Node3D
#
# Tripmine view (ticket T-021; SPEC-CONFORMANCE pass: ticket T-085,
# research/fable-tickets.md section 2.1, TERRAIN_SPEC.md section 12.2).
#
# Renders the fake gift hazard the sim's mine state (sim/mines.gd) describes. The
# section 2.1 table is the spec, row by row:
#   body        the T-015 tripmine box at the slot position, one revolution per
#               4.0 s (TURN_PERIOD, binding);
#   rim glow    identical to a black gift - #7CFFF4, at EVERY distance (the lie):
#               an unshaded #7CFFF4 rim frame built as view geometry (the T-015
#               glb carries no ribbon; the additive overlay was removed in J10 -
#               J8 measured it lifts every pixel of the mesh by a flat
#               ~(+45,+46,+54), body included);
#   star        six-pointed, #FF4FD8, emission 1.0, on the top face (baked into the
#               T-015 model) and on all four side faces (view geometry, D-T085-1);
#               alpha 0 beyond 14 u -> 1 at 10 u;
#   particles   CONSTANT - the emitter never stops, including beyond 12 u: 12
#               particles/s, lifetime 1.5 s, size 0.06 u, #FF4FD8, rising 0.4 u/s
#               with a 0.2 u drift volume, emission 2.0; alpha follows the same
#               14 u -> 10 u ramp as the star;
#   trigger ring a faint #FF4FD8 ground ring of radius 0.9 u, alpha 0.25, visible
#               inside 12 u (the cylinder the player must stay out of);
#   Method Acting the ramp becomes 0 beyond 7 u -> 1 at 5 u (set_method_acting);
#   Radar Module: Mines a pink outline through fog within 14 u, regardless of the
#               ramp (set_radar).
#
# The star is a separate surface because the T-015 .glb is ONE vertex-coloured
# primitive: split_star() cuts the pink triangles out of it at load time so the
# ramp can fade the star without fading the black frame (D-T085-1).
#
# The caller drives sync() every frame (or on change) and owns the clock; this
# node never writes sim state. No engine calls beyond the view surface.

const MinesScript := preload("res://sim/mines.gd")

const MODEL := "res://assets/models/tripmine_box.glb"
## The tell radius (DESIGN.md section 3.3): the sim constant, mirrored here.
const TELL_DISTANCE: float = MinesScript.TELL_DISTANCE
## The turn: one full revolution per 4.0 s (DESIGN.md section 3.3 cycle).
const TURN_PERIOD := 4.0
const TAU_F := 6.283185307179586
## The tell colour (section 3.3, the particles + star): #FF4FD8.
const PINK := Color(1.0, 0.309804, 0.847059)

## Rim emission (TERRAIN_SPEC 12.2, D-T020-6): the black gift's own x1.5. NOT
## applied as an additive pass anywhere in this renderer (J8 measured it lifts
## every pixel by ~(+45,+46,+54), body included, making a near-black body
## impossible); kept as the spec's recorded value, exactly as the gift views keep
## theirs. The mine's rim is the unshaded #7CFFF4 frame (_rim_mesh, _rim_material).
const RIM_FACTOR := 1.5
## The rim colour (TERRAIN_SPEC 12.2 "black_gift_rim", palette.json, #7CFFF4).
const RIM_COLOR := Color(0.486275, 1.0, 0.956863)
## Star emission (section 2.1 row 3).
const STAR_EMISSION := 1.0

## Particles (section 2.1 row 4).
const PARTICLE_RATE := 12.0     # particles/s
const PARTICLE_LIFE := 1.5      # s
const PARTICLE_SIZE := 0.06     # u (the spark's diameter)
const PARTICLE_RISE := 0.4      # u/s
const PARTICLE_DRIFT := 0.2     # u (the emission volume radius, D-T085-2)
const PARTICLE_EMISSION := 2.0
const PARTICLE_HEIGHT := 0.6    # u above the box point

## The alpha ramp (section 2.1 rows 3 and 4): 0 beyond FAR, 1 at NEAR.
const RAMP_NEAR := 10.0
const RAMP_FAR := 14.0
## Method Acting (section 2.1, last-but-two row): 0 beyond 7 u -> 1 at 5 u.
const MA_RAMP_NEAR := 5.0
const MA_RAMP_FAR := 7.0

## Trigger ring (section 2.1, fun risk 8).
const RING_RADIUS := 0.9
const RING_ALPHA := 0.25
## Radar Module: Mines (section 2.1, last row).
const RADAR_RANGE := 14.0

var _nodes: Array = []   # per mine: the root + its parts (see setup)
var _mines: RefCounted = null
var _time: float = 0.0
var _method_acting := false
var _radar := false


## Builds one box node per LIVE mine slot. level: the Level dict; mines_state:
## the sim's mine state (MinesScript.create(...)) - only occ == 1 slots appear.
func setup(level: Dictionary, mines_state: RefCounted) -> void:
	_time = 0.0
	_mines = mines_state
	for child in get_children():
		child.free()
	_nodes = []
	var parts := _model_parts()
	var ids: Array = mines_state.ids
	for line_i in ids.size():
		var slot: int = int(ids[line_i])
		var root := Node3D.new()
		root.position = mines_state.point(slot)
		add_child(root)
		# the box: the T-015 frame in its vertex colours, star triangles removed
		var body := MeshInstance3D.new()
		body.mesh = parts["box"]
		body.material_override = _body_material()
		root.add_child(body)
		# the lie: the black gift's rim, at every distance - a thin unshaded #7CFFF4
		# frame on the box's edges (view geometry; the glb carries no ribbon). The
		# additive overlay was removed (J10): measured, it lifts the body to a pale
		# slate/cream (163,234,228) from palette #050608 no matter the base albedo.
		var rim := MeshInstance3D.new()
		rim.mesh = _rim_mesh()
		rim.material_override = _rim_material()
		root.add_child(rim)
		# the star: its own surface, so the 14 u -> 10 u ramp can fade it
		var star := MeshInstance3D.new()
		star.mesh = parts["star"]
		star.material_override = _star_material()
		root.add_child(star)
		# the four side faces (the table's "on all four side faces")
		var sides := MeshInstance3D.new()
		sides.mesh = _side_star_mesh()
		sides.material_override = star.material_override
		root.add_child(sides)
		# the trigger ring: the 0.9 u cylinder the player must stay out of
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh()
		ring.material_override = _ring_material()
		ring.position = Vector3(0.0, 0.01, 0.0)
		root.add_child(ring)
		# the Radar Module outline: a back-face shell, fog-exempt
		var radar := MeshInstance3D.new()
		radar.mesh = parts["box"]
		radar.material_override = _radar_material()
		radar.scale = Vector3(1.08, 1.08, 1.08)
		radar.visible = false
		root.add_child(radar)
		# the emitter: CONSTANT (section 2.1 row 4 - it never stops)
		var puffs := CPUParticles3D.new()
		puffs.amount = int(round(PARTICLE_RATE * PARTICLE_LIFE))
		puffs.lifetime = PARTICLE_LIFE
		puffs.mesh = _spark_mesh()
		puffs.direction = Vector3.UP
		puffs.spread = 0.0
		puffs.initial_velocity_min = PARTICLE_RISE
		puffs.initial_velocity_max = PARTICLE_RISE
		puffs.gravity = Vector3.ZERO
		puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		puffs.emission_sphere_radius = PARTICLE_DRIFT
		puffs.local_coords = false
		puffs.emitting = true
		puffs.position = Vector3(0.0, PARTICLE_HEIGHT, 0.0)
		root.add_child(puffs)
		_nodes.append({
			"node": root, "slot": slot, "body": body, "rim": rim, "star": star,
			"sides": sides, "ring": ring, "radar": radar, "puffs": puffs,
		})
	sync()


## The clock: seconds of sim/level time (the caller owns it; no engine clock).
func set_time(t: float) -> void:
	_time = t


## Method Acting (curse): the ramp becomes 0 beyond 7 u -> 1 at 5 u.
func set_method_acting(on: bool) -> void:
	_method_acting = on


## Radar Module: Mines: the pink outline through fog within 14 u, ramp or not.
func set_radar(on: bool) -> void:
	_radar = on


## The tell: inside the tell radius the particles + star show; beyond it the
## mine reads as a plain gift (the rim glow only). Distance in world u.
static func tell_visible(dist: float) -> bool:
	return dist <= TELL_DISTANCE


## The section 2.1 alpha ramp: 1 at or inside `near`, 0 at or beyond `far`.
static func ramp_alpha(dist: float, near: float, far: float) -> float:
	if dist <= near:
		return 1.0
	if dist >= far:
		return 0.0
	return (far - dist) / (far - near)


## The particle alpha at a distance (section 2.1 row 4; Method Acting row).
static func particle_alpha(dist: float, method_acting: bool = false) -> float:
	if method_acting:
		return ramp_alpha(dist, MA_RAMP_NEAR, MA_RAMP_FAR)
	return ramp_alpha(dist, RAMP_NEAR, RAMP_FAR)


## The star alpha: the same ramp as the particles (section 2.1 row 3).
static func star_alpha(dist: float, method_acting: bool = false) -> float:
	return particle_alpha(dist, method_acting)


## Syncs the rotation, the rim glow, the star/particle ramp, the trigger ring and
## the radar outline from the caller's eye position (the camera). Call every frame
## or on change. A consumed mine (defused, shielded, saved or detonated) is
## removed from view. eye == Vector3.ZERO means "no camera supplied": the tell
## shows in full (the T-021 convention).
func sync(eye: Vector3 = Vector3.ZERO) -> void:
	var t: float = _time
	var no_eye: bool = eye == Vector3.ZERO
	for line_i in _nodes.size():
		var e: Dictionary = _nodes[line_i]
		var root: Node3D = e["node"]
		var slot: int = int(e["slot"])
		if _mines != null:
			root.visible = not _mines.is_consumed(slot)
		# one full turn per TURN_PERIOD seconds, phase from the slot order so
		# neighbouring mines in a line do not spin in lockstep
		root.rotation.y = t * TAU_F / TURN_PERIOD + float(line_i) * 0.7
		var dist: float = 0.0 if no_eye else _eye_dist(root, eye)
		var a: float = 1.0 if no_eye else particle_alpha(dist, _method_acting)
		# the emitter is CONSTANT: it never stops, only its alpha follows the ramp
		var puffs: CPUParticles3D = e["puffs"]
		puffs.emitting = true
		puffs.color = Color(1.0, 1.0, 1.0, a)
		# the star: the same ramp, on the top face and the four side faces
		var star: MeshInstance3D = e["star"]
		var star_mat: StandardMaterial3D = star.material_override
		star_mat.albedo_color = Color(PINK.r, PINK.g, PINK.b, a)
		star_mat.emission_energy_multiplier = STAR_EMISSION * a
		star.visible = a > 0.0
		(e["sides"] as MeshInstance3D).visible = a > 0.0
		# the trigger ring: visible inside the 12 u tell
		(e["ring"] as MeshInstance3D).visible = no_eye or tell_visible(dist)
		# the radar outline: within 14 u, whatever the ramp says
		(e["radar"] as MeshInstance3D).visible = _radar and (no_eye or dist <= RADAR_RANGE)


## The emitter of the mine on `slot` (null when that slot carries no mine).
func emitter_for_slot(slot: int) -> CPUParticles3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return e["puffs"]
	return null


## The star material of the mine on `slot` (null when that slot carries no mine).
func star_material_for_slot(slot: int) -> StandardMaterial3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return (e["star"] as MeshInstance3D).material_override
	return null


## The rim frame material of the mine on `slot` - unshaded #7CFFF4 (J10).
func rim_material_for_slot(slot: int) -> StandardMaterial3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return (e["rim"] as MeshInstance3D).material_override
	return null


## The rim frame of the mine on `slot` (null when that slot carries no mine).
func rim_for_slot(slot: int) -> MeshInstance3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return e["rim"]
	return null


## The body of the mine on `slot` (null when that slot carries no mine).
func body_for_slot(slot: int) -> MeshInstance3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return e["body"]
	return null


## The body base material of the mine on `slot` (null when that slot carries none).
func body_material_for_slot(slot: int) -> StandardMaterial3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return (e["body"] as MeshInstance3D).material_override
	return null


## The trigger ring of the mine on `slot`.
func ring_for_slot(slot: int) -> MeshInstance3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return e["ring"]
	return null


## The radar outline of the mine on `slot`.
func radar_for_slot(slot: int) -> MeshInstance3D:
	for e in _nodes:
		if int(e["slot"]) == slot:
			return e["radar"]
	return null


func _eye_dist(root: Node3D, eye: Vector3) -> float:
	var dx: float = root.position.x - eye.x
	var dy: float = root.position.y - eye.y
	var dz: float = root.position.z - eye.z
	return sqrt(dx * dx + dy * dy + dz * dz)


# ---- the model: one vertex-coloured primitive, split into box + star ------------

## Loads the T-015 box and splits it: {"box": ArrayMesh, "star": ArrayMesh}.
static func _model_parts() -> Dictionary:
	var ps: PackedScene = load(MODEL)
	if ps == null:
		return {"box": ArrayMesh.new(), "star": ArrayMesh.new()}
	var inst: Node3D = ps.instantiate()
	var src: MeshInstance3D = _first_mesh(inst)
	var parts := {"box": ArrayMesh.new(), "star": ArrayMesh.new()}
	if src != null and src.mesh != null:
		parts = split_star(src.mesh)
	inst.free()
	return parts


static func _first_mesh(root: Node) -> MeshInstance3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null


## The tell pink, as a vertex-colour key: #FF4FD8 is the only colour in the model
## with red AND blue above half and green below it (the frame is #050608, the
## panels #0A2E30 - both far below on red and blue).
static func is_pink(c: Color) -> bool:
	return c.r > 0.5 and c.b > 0.5 and c.g < 0.5


## Splits a vertex-coloured mesh into its non-pink triangles (the box) and its
## pink ones (the star). Both surfaces keep the source vertex arrays, so the
## split costs one index pass and no vertex copy.
static func split_star(mesh: Mesh) -> Dictionary:
	var box := ArrayMesh.new()
	var star := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array()
			for i in verts.size():
				idx.append(i)
		var box_idx := PackedInt32Array()
		var star_idx := PackedInt32Array()
		var t := 0
		while t + 2 < idx.size():
			var a: int = idx[t]
			var b: int = idx[t + 1]
			var c: int = idx[t + 2]
			if is_pink(cols[a]) and is_pink(cols[b]) and is_pink(cols[c]):
				star_idx.append(a)
				star_idx.append(b)
				star_idx.append(c)
			else:
				box_idx.append(a)
				box_idx.append(b)
				box_idx.append(c)
			t += 3
		_add_surface(box, arrays, box_idx)
		_add_surface(star, arrays, star_idx)
	return {"box": box, "star": star}


static func _add_surface(dst: ArrayMesh, arrays: Array, idx: PackedInt32Array) -> void:
	if idx.is_empty():
		return
	var a: Array = arrays.duplicate()
	a[Mesh.ARRAY_INDEX] = idx
	dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)


# ---- materials ------------------------------------------------------------------

## The box body: the model's own vertex colours, unshaded and flat (the voxel
## style of TERRAIN_SPEC 12.1 rule 5; the black gift's pass, J8). Unshaded so the
## body renders its palette colour (#050608 frame, #0A2E30 panels) at every
## lighting - the shaded default was muddied by the act-I world's teal ambient
## (J3 measured the same on the gold gift).
static func _body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## The star: #FF4FD8, emission 1.0, alpha driven by the ramp (sync).
static func _star_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = PINK
	m.emission_enabled = true
	m.emission = PINK
	m.emission_energy_multiplier = STAR_EMISSION
	m.disable_receive_shadows = true
	return m


## The spark: a tiny billboarded sphere per particle, in the tell pink, emission
## 2.0 (section 2.1 row 4). Mesh only; the emitter owns the motion.
static func _spark_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = PARTICLE_SIZE * 0.5
	m.height = PARTICLE_SIZE
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = PINK
	mat.emission_enabled = true
	mat.emission = PINK
	mat.emission_energy_multiplier = PARTICLE_EMISSION
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.material = mat
	return m


## The four side-face hexagrams: three crossing bars per face, 0/60/120 deg, on
## the frame's own faces (the T-015 model bakes the star on the top face only).
static func _side_star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.225   # the frame's half width (0.22) + a hair, so it never z-fights
	var mid := 0.25     # the box is 0.5 u tall: the face centre sits at half height
	for face in 4:
		var ang := float(face) * PI * 0.5
		var n := Vector3(sin(ang), 0.0, cos(ang))
		var u := Vector3(n.z, 0.0, -n.x)   # n x u == UP, so the winding is outward
		var centre := n * half + Vector3(0.0, mid, 0.0)
		for bar in 3:
			_bar(st, centre, u, Vector3.UP, float(bar) * PI / 3.0, 0.40, 0.05)
	st.generate_normals()
	return st.commit()


static func _bar(st: SurfaceTool, centre: Vector3, u: Vector3, v: Vector3,
		rot: float, length: float, width: float) -> void:
	var du: Vector3 = u * cos(rot) + v * sin(rot)
	var dv: Vector3 = -u * sin(rot) + v * cos(rot)
	var hl := length * 0.5
	var hw := width * 0.5
	var p0: Vector3 = centre - du * hl - dv * hw
	var p1: Vector3 = centre + du * hl - dv * hw
	var p2: Vector3 = centre + du * hl + dv * hw
	var p3: Vector3 = centre - du * hl + dv * hw
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)


## The trigger ring: a flat annulus of radius 0.9 u on the ground.
static func _ring_mesh() -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = RING_RADIUS - 0.06
	m.outer_radius = RING_RADIUS
	m.rings = 3
	m.ring_segments = 24
	return m


static func _ring_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(PINK.r, PINK.g, PINK.b, RING_ALPHA)
	m.disable_receive_shadows = true
	return m


## The Radar Module outline: the box drawn back-faces-only, pink, fog-exempt.
static func _radar_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.albedo_color = Color(PINK.r, PINK.g, PINK.b, 0.9)
	m.disable_fog = true
	m.disable_receive_shadows = true
	return m


## The rim frame (J10): the black gift's ribbon, as view geometry - twelve thin
## boxes on the box's edges, protruding a hair past its faces so it never
## z-fights. Unshaded #7CFFF4, opaque: lit-independent, fog-affected (exactly
## the black gift's ribbon, which does not disable the fog either), so it holds
## at EVERY distance (the lie) and never needs an additive pass.
const RIM_THICK := 0.05
const RIM_HALF := 0.25      # the box's half width (the model spans ±0.25, y 0..0.5)
const RIM_HEIGHT := 0.5

static func _rim_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := RIM_THICK
	var h := RIM_HALF
	var yc := RIM_HEIGHT * 0.5
	# the four vertical edges
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_box(st, Vector3(sx * h, yc, sz * h), Vector3(t, RIM_HEIGHT, t))
	# the four top and the four bottom edges
	for sy in [0.0, RIM_HEIGHT]:
		for sz in [-1.0, 1.0]:
			_add_box(st, Vector3(0.0, sy, sz * h), Vector3(2.0 * h + t, t, t))
		for sx in [-1.0, 1.0]:
			_add_box(st, Vector3(sx * h, sy, 0.0), Vector3(t, t, 2.0 * h + t))
	return st.commit()


## The rim material: unshaded #7CFFF4, shadows off - the black gift's ribbon
## pass (gifts_view._black_body_material, J8), NOT an emission-boosted one:
## x1.5 on a lit colour clips toward white in this renderer's FILMIC tonemap.
static func _rim_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = RIM_COLOR
	m.disable_receive_shadows = true
	return m


## Adds one axis-aligned box to the surface tool, with flat outward normals.
static func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	# (u, v) per axis such that cross(u, v) == the axis; swapped for the -i face
	var pairs := [[Vector3.UP, Vector3.BACK], [Vector3.BACK, Vector3.RIGHT],
			[Vector3.RIGHT, Vector3.UP]]
	var half := size * 0.5
	for a in 3:
		for s in [1.0, -1.0]:
			var n: Vector3 = axes[a] * s
			var u: Vector3 = pairs[a][0]
			var v: Vector3 = pairs[a][1]
			if s < 0.0:
				var tmp := u
				u = v
				v = tmp
			# half extents along u and v (the two axes that are not `a`)
			var ub: int = (a + 1) % 3
			var vb: int = (a + 2) % 3
			var huv: float = half[ub]
			var hvv: float = half[vb]
			var base: Vector3 = centre + n * half[a]
			var p00: Vector3 = base - u * huv - v * hvv
			var p10: Vector3 = base + u * huv - v * hvv
			var p11: Vector3 = base + u * huv + v * hvv
			var p01: Vector3 = base - u * huv + v * hvv
			for p in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(n)
				st.add_vertex(p)
