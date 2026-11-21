extends Node3D
#
# Floating contour-outlined rocks (DECISIONS D-ATMO-2). Low-poly convex chunks drift in a wide
# ring far outside the level, each with a thin bright outline.
#
# Rock shape: `variants` hulls per level, each the convex hull of 14 jittered points on a unit
# sphere (2 * 14 - 4 = 24 triangles, flat-shaded). Convex by construction (brute-force hull),
# so the outline hull below never pokes through the body.
#
# Outline: an INVERTED HULL. A second MultiMesh draws the same hull, grown outward by
# outline_width SCREEN pixels in its vertex shader, with cull_front and an unshaded outline
# colour, so only the rim that sticks out past the body silhouette is visible. Chosen over a fresnel rim because a
# 24-triangle flat-shaded rock has so few faces that a fresnel term brightens whole faces, not
# an edge line; the hull gives a constant-thickness contour, the reference signature look.
#
# Placement: a pure function of (seed, cfg) - layout() - drawn from a RandomNumberGenerator
# seeded with the level seed. Positions are min_radius..max_radius u from the origin (the level
# radius is <= 130 u) at min_height..max_height. All numbers come from data/palette.json
# "debris". View-only: MeshInstance3D + MultiMesh, no collision shape, no physics body, no sim
# state; the motion runs on _process wall time, never on the sim tick.
#
# public API:
#   static func load_config() -> Dictionary
#   static func layout(seed: int, cfg: Dictionary, rng: RandomNumberGenerator = null) -> Array
#   static func rock_points(rng, n) -> PackedVector3Array; static func hull_faces(points) -> Array
#   func configure(seed: int, cfg: Dictionary = {}) -> void
#   var rocks: Array        # the layout rows
#   var body_material / outline_material: ShaderMaterial

const PALETTE_PATH := "res://data/palette.json"
const POINTS_PER_ROCK := 14
const SEED_SALT := 0x0DEB215

const BODY_SHADER := """
shader_type spatial;
render_mode cull_back, fog_disabled;
uniform vec4 body : source_color;
void fragment() {
	ALBEDO = body.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;
uniform vec4 outline : source_color;
uniform float width_px = 2.0;
void vertex() {
	// Inverted hull grown in SCREEN space: each vertex moves away from the rock centre by
	// width_px on screen, so the contour stays the same thickness at 170 u and at 300 u
	// (a world-space grow is sub-pixel that far out). The hull is convex and centred on its
	// origin, so the radial push never opens a crack between the flat-shaded faces.
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 mid = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vec2 d = clip.xy / clip.w - mid.xy / mid.w;
	if (dot(d, d) > 1e-12) {
		clip.xy += normalize(d * VIEWPORT_SIZE) * (2.0 * width_px / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}
void fragment() {
	ALBEDO = outline.rgb;
}
"""

var rocks: Array = []
var body_material: ShaderMaterial = null
var outline_material: ShaderMaterial = null
var _bodies: Array = []     # MultiMeshInstance3D per variant
var _outlines: Array = []   # MultiMeshInstance3D per variant
var _slot: Array = []       # rock index -> [variant, instance index]
var _drift := 0.0
var _bob := 0.0
var _width := 0.0
var _t := 0.0


static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("debris: cannot parse %s" % PALETTE_PATH)
		return {}
	return (parsed as Dictionary).get("debris", {})


## The deterministic field: one row per rock. A null rng = seeded from `seed` (the shipped
## path); passing an rng is for tests (e.g. an unseeded one for the negative control).
static func layout(seed: int, cfg: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash([seed, SEED_SALT])
	var count := int(cfg.get("count", 0))
	var variants := maxi(1, int(cfg.get("variants", 1)))
	var r0 := float(cfg.get("min_radius", 170.0))
	var r1 := float(cfg.get("max_radius", 300.0))
	var y0 := float(cfg.get("min_height", -60.0))
	var y1 := float(cfg.get("max_height", 60.0))
	var s0 := float(cfg.get("min_size", 1.0))
	var s1 := float(cfg.get("max_size", 3.0))
	var spin := float(cfg.get("spin_speed", 0.2))
	var out: Array = []
	for i in count:
		var ang := rng.randf() * TAU
		# sqrt keeps the ring area density even instead of piling rocks on the inner edge
		var dist := sqrt(lerpf(r0 * r0, r1 * r1, rng.randf()))
		var bias := rng.randf()
		out.append({
			"pos": Vector3(cos(ang) * dist, lerpf(y0, y1, rng.randf()), sin(ang) * dist),
			# squared bias: mostly small rocks, a few big ones (the reference spread)
			"size": s0 + bias * bias * (s1 - s0),
			"variant": rng.randi() % variants,
			"axes": Vector3(rng.randf_range(0.75, 1.25), rng.randf_range(0.6, 1.1),
					rng.randf_range(0.75, 1.25)),
			"rot": Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU),
			"spin": Vector3(rng.randf_range(-spin, spin), rng.randf_range(-spin, spin),
					rng.randf_range(-spin, spin)),
			"phase": rng.randf() * TAU,
		})
	return out


## n points on a unit sphere (Fibonacci spread + jitter) with a radial jitter 0.75..1.1.
static func rock_points(rng: RandomNumberGenerator, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var yy := 1.0 - (float(i) + 0.5) / float(n) * 2.0 + rng.randf_range(-0.12, 0.12)
		yy = clampf(yy, -0.98, 0.98)
		var ring := sqrt(1.0 - yy * yy)
		var th := float(i) * 2.399963 + rng.randf_range(-0.5, 0.5)
		var r := rng.randf_range(0.75, 1.1)
		pts.append(Vector3(cos(th) * ring, yy, sin(th) * ring) * r)
	return pts


## Brute-force convex hull: every triple whose plane has all other points on one side is a
## face, wound outward. O(n^4) is fine for 14 points (364 triples x 14).
static func hull_faces(pts: PackedVector3Array) -> Array:
	var faces: Array = []
	var n := pts.size()
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= float(maxi(n, 1))
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length_squared() < 1e-10:
					continue
				nrm = nrm.normalized()
				var dd := nrm.dot(pts[i])
				var pos := 0
				var neg := 0
				for m in n:
					if m == i or m == j or m == k:
						continue
					var s := nrm.dot(pts[m]) - dd
					if s > 1e-6:
						pos += 1
					elif s < -1e-6:
						neg += 1
				if pos > 0 and neg > 0:
					continue
				# outward = away from the centroid
				if nrm.dot(pts[i] - centre) < 0.0:
					faces.append([i, k, j])
				else:
					faces.append([i, j, k])
	return faces


## A flat-shaded ArrayMesh for one convex hull (faces wound outward, counter-clockwise).
static func hull_mesh(pts: PackedVector3Array, faces: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		# Godot front faces are clockwise seen from outside: emit a, c, b
		var nrm := (b - a).cross(c - a).normalized()
		for v in [a, c, b]:
			st.set_normal(nrm)
			st.add_vertex(v)
	return st.commit()


func configure(seed: int, cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		cfg = load_config()
	name = "Debris"
	for c in get_children():
		c.free()
	_bodies.clear()
	_outlines.clear()
	_slot.clear()
	rocks = layout(seed, cfg)
	_drift = float(cfg.get("drift_speed", 0.0))
	_bob = float(cfg.get("bob", 0.0))
	_width = float(cfg.get("outline_width", 2.0))
	body_material = ShaderMaterial.new()
	body_material.shader = Shader.new()
	body_material.shader.code = BODY_SHADER
	body_material.set_shader_parameter("body", Color(str(cfg.get("body_hex", "#141016"))))
	outline_material = ShaderMaterial.new()
	outline_material.shader = Shader.new()
	outline_material.shader.code = OUTLINE_SHADER
	outline_material.set_shader_parameter("outline", Color(str(cfg.get("outline_hex", "#FFFFFF"))))
	outline_material.set_shader_parameter("width_px", _width)
	var variants := maxi(1, int(cfg.get("variants", 1)))
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = hash([seed, SEED_SALT, "shape"])
	var per_variant: Array = []
	for v in variants:
		per_variant.append(0)
	for r in rocks:
		var v: int = int(r["variant"])
		_slot.append([v, per_variant[v]])
		per_variant[v] += 1
	for v in variants:
		var pts := rock_points(shape_rng, POINTS_PER_ROCK)
		var m := hull_mesh(pts, hull_faces(pts))
		_bodies.append(_multimesh(m, body_material, per_variant[v], "RockBody%d" % v))
		_outlines.append(_multimesh(m, outline_material, per_variant[v], "RockOutline%d" % v))
	_apply_transforms()


func _multimesh(m: Mesh, mat: Material, n: int, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	return mmi


## Rock i at wall time t (the body and its outline share it; the outline grows on screen).
func rock_transform(i: int, t: float) -> Transform3D:
	var r: Dictionary = rocks[i]
	var size := float(r["size"])
	var rot: Vector3 = r["rot"] + r["spin"] * t
	var b := Basis.from_euler(rot) * Basis.from_scale(r["axes"] * size)
	var pos: Vector3 = r["pos"] + Vector3(0.0, sin(t * 0.6 + float(r["phase"])) * _bob, 0.0)
	return Transform3D(b, pos)


func _apply_transforms() -> void:
	for i in rocks.size():
		var tr := rock_transform(i, _t)
		var v: int = _slot[i][0]
		var k: int = _slot[i][1]
		(_bodies[v] as MultiMeshInstance3D).multimesh.set_instance_transform(k, tr)
		(_outlines[v] as MultiMeshInstance3D).multimesh.set_instance_transform(k, tr)


func _process(delta: float) -> void:
	if rocks.is_empty():
		return
	_t += delta
	rotation.y = _t * _drift
	_apply_transforms()
