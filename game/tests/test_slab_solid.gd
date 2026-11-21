extends RefCounted
#
# Solid-slab tests (owner report "platforms look hollow"): the slab sides and undersides must
# render as a closed, opaque block, never a see-through glass box.
#
# Root cause it pins: level_mesher.gd _side() (every vertical slab, prop, pad and spike face)
# and the ramp lateral walls were wound counter-clockwise seen from outside. Godot's front
# faces are CLOCKWISE, so every outward side face was back-facing and culled by cull_back;
# what drew instead was the INSIDE of the far wall (its back face seen from the interior is
# clockwise), lit from behind - a dark, hollow box. test_mesh.gd _winding() never saw it: it
# only asserted slab_side normal.y <= 0.1, which a culled vertical face satisfies either way.
# Ramp wedges also had no underside at all.
#
# Assertions, on the mesh data only:
#   1. every triangle of every solid material: the Godot front-face normal (v2-v0)x(v1-v0)
#      agrees with the authored vertex normal (dot > 0.99);
#   2. every slab_side triangle faces OUT of the slab volume: just past its front face is
#      empty space, just behind it is slab (computed from the Level's tiles, ramps included);
#      faces with slab on both sides are hidden and skipped;
#   3. the undersides are closed: the down-facing slab_side area equals one 1x1 underside per
#      flat tile plus one sqrt(1.25) sloped underside per ramp;
#   4. every material is opaque: no ALPHA write, no blend_ / cull_disabled / cull_front /
#      depth_draw_never render mode, and colour uniforms carry alpha 1.0.
# Runs on generated levels plus a hand-made level holding one ramp per direction (generated
# levels do not guarantee ramps). extends RefCounted, preload-by-path only (D-T001-1).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const MesherScript := preload("res://view/level_mesher.gd")

const CASES := [[1, 1], [7, 1], [7, 12], [7, 30]]
const HU := 0.5
const SLAB := 1.0
const EPS := 0.02
const SOLID_MATS := ["slab_side", "prop", "prop_crate", "spike", "pad"]
const ALL_MATS := ["platform_top", "walkway_top", "deadend_top", "hub_top",
	"slab_side", "prop", "prop_crate", "spike", "pad"]
const NOT_OPAQUE := ["ALPHA", "blend_", "cull_disabled", "cull_front", "depth_draw_never"]


func run() -> Array[String]:
	var failures: Array[String] = []
	for case in CASES:
		var L := VoidGenScript.generate(int(case[0]), int(case[1]))
		if L.is_empty():
			failures.append("seed %d level %d: generator failed" % [int(case[0]), int(case[1])])
			continue
		failures.append_array(_check_level(L, "seed %d level %d" % [int(case[0]), int(case[1])]))
	failures.append_array(_check_level(_ramp_level(), "ramp unit"))
	return failures


## One flat tile and four ramps (one per ascent direction), all apart so every face shows.
## bbox 10 wide keeps the piece off the spike rule.
func _ramp_level() -> Dictionary:
	return {
		"level": 1,
		"pieces": [{"id": 0, "role": 1, "bbox": [0, 0, 9, 0]}],
		"tiles": [[0, 0, 0, 0, 0], [2, 0, 0, 1, 0], [4, 0, 2, 2, 0], [6, 0, -2, 3, 0], [8, 0, 1, 4, 0]],
		"props": [],
		"pads": [],
	}


func _check_level(L: Dictionary, tag: String) -> Array[String]:
	var failures: Array[String] = []
	var r: Dictionary = MesherScript.build(L)
	var meshes: Dictionary = r["meshes"]
	if not meshes.has("slab_side"):
		failures.append("%s: no slab_side mesh at all" % tag)
		return failures
	for mat in SOLID_MATS:
		if meshes.has(mat):
			failures.append_array(_winding_matches_normals(meshes[mat], mat, tag))
	var cols := _columns(L)
	failures.append_array(_faces_outward(meshes["slab_side"], cols, tag))
	var want_down: float = float(r["tiles_top"]) + float(r["ramps"]) * sqrt(1.25)
	var got_down := _down_area(meshes["slab_side"])
	if absf(got_down - want_down) > 1e-3:
		failures.append("%s: slab underside area %.4f, want %.4f (%d flat tiles + %d ramps) - the box is open underneath"
			% [tag, got_down, want_down, int(r["tiles_top"]), int(r["ramps"])])
	failures.append_array(_opaque(r, tag))
	return failures


func _tri(arrays: Array, t: int) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return [verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]]]


## Godot front faces are clockwise: the outward normal of (v0, v1, v2) is (v2-v0) x (v1-v0).
func _front_normal(v: Array) -> Vector3:
	return ((v[2] as Vector3) - v[0]).cross((v[1] as Vector3) - v[0])


func _winding_matches_normals(m: ArrayMesh, mat: String, tag: String) -> Array[String]:
	var failures: Array[String] = []
	var arrays := m.surface_get_arrays(0)
	var nor: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	var first := ""
	for t in range(0, idx.size() - 2, 3):
		var w := _front_normal(_tri(arrays, t))
		if w.length() < 1e-9:
			continue
		var n: Vector3 = nor[idx[t]]
		if w.normalized().dot(n.normalized()) <= 0.99:
			bad += 1
			if first == "":
				first = "tri %d at %s front %s vs normal %s" % [t / 3, str(_tri(arrays, t)[0]), str(w.normalized()), str(n)]
	if bad > 0:
		failures.append("%s: mesh '%s': %d/%d triangles back-facing against their own normal (culled - see-through); first %s"
			% [tag, mat, bad, idx.size() / 3, first])
	return failures


## "x,z" -> [[y HU, kind], ...] for every tile of the Level.
func _columns(L: Dictionary) -> Dictionary:
	var cols := {}
	for t in L.get("tiles", []):
		var k := "%d,%d" % [int(t[0]), int(t[1])]
		if not cols.has(k):
			cols[k] = []
		(cols[k] as Array).append([int(t[2]), int(t[3])])
	return cols


## True when p lies strictly inside some tile's 1 u slab. A ramp (kind 1 + d) rises 1 HU over
## the cell toward direction d (0 +x, 1 +z, 2 -x, 3 -z); its slab is the surface minus 1 u.
func _in_slab(cols: Dictionary, p: Vector3) -> bool:
	var cx := floori(p.x)
	var cz := floori(p.z)
	var col: Array = cols.get("%d,%d" % [cx, cz], [])
	for e in col:
		var top: float = float(e[0]) * HU
		var kind: int = int(e[1])
		if kind != 0:
			var fx: float = p.x - float(cx)
			var fz: float = p.z - float(cz)
			var a: float = [fx, fz, 1.0 - fx, 1.0 - fz][kind - 1]
			top += HU * a
		if p.y < top and p.y > top - SLAB:
			return true
	return false


func _faces_outward(m: ArrayMesh, cols: Dictionary, tag: String) -> Array[String]:
	var failures: Array[String] = []
	var arrays := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var inward := 0
	var floating := 0
	var first := ""
	for t in range(0, idx.size() - 2, 3):
		var v := _tri(arrays, t)
		var w := _front_normal(v)
		if w.length() < 1e-9:
			continue
		w = w.normalized()
		var c: Vector3 = ((v[0] as Vector3) + v[1] + v[2]) / 3.0
		var front := _in_slab(cols, c + w * EPS)
		var back := _in_slab(cols, c - w * EPS)
		if front and back:
			continue    # hidden between two slabs
		if front and not back:
			inward += 1
		elif not front and not back:
			floating += 1
		else:
			continue
		if first == "":
			first = "tri %d centroid %s front normal %s (slab in front: %s, behind: %s)" % [t / 3, str(c), str(w), str(front), str(back)]
	if inward > 0 or floating > 0:
		failures.append("%s: slab_side: %d/%d triangles face INTO the slab, %d border no slab; first %s"
			% [tag, inward, idx.size() / 3, floating, first])
	return failures


## Total area of slab_side triangles whose front face points down (undersides).
func _down_area(m: ArrayMesh) -> float:
	var arrays := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	for t in range(0, idx.size() - 2, 3):
		var w := _front_normal(_tri(arrays, t))
		if w.length() > 1e-9 and w.normalized().y < -0.5:
			area += 0.5 * w.length()
	return area


func _opaque(r: Dictionary, tag: String) -> Array[String]:
	var failures: Array[String] = []
	var meshes: Dictionary = r["meshes"]
	for mn in ALL_MATS:
		if not meshes.has(mn):
			continue
		var mat = (meshes[mn] as ArrayMesh).surface_get_material(0)
		if not (mat is ShaderMaterial) or (mat as ShaderMaterial).shader == null:
			failures.append("%s: mesh '%s' has no ShaderMaterial (got %s)" % [tag, mn, str(mat)])
			continue
		var code: String = (mat as ShaderMaterial).shader.code
		for tok in NOT_OPAQUE:
			if code.contains(tok):
				failures.append("%s: mesh '%s' shader contains '%s' - not an opaque solid" % [tag, mn, tok])
		for pname in ["color", "trim_color", "color_light", "color_dark"]:
			var pv = (mat as ShaderMaterial).get_shader_parameter(pname)
			if pv is Color and not is_equal_approx((pv as Color).a, 1.0):
				failures.append("%s: mesh '%s' uniform %s alpha %.3f, want 1.0" % [tag, mn, pname, (pv as Color).a])
	return failures