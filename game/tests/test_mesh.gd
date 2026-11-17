extends RefCounted
#
# Level-mesher tests (ticket T-011; TERRAIN_SPEC.md sections 4, 12; FLEET_PACK T-011 done-when):
#   1. the mesh builds for gallery seeds 1@1, 7@12 and 7@30; triangle count <= 30,000 at level 30;
#   2. seed 7 level 30 meshes in <= 600 ms (logged per build, wall clock of MesherScript.build only);
#   3. greedy merge coverer: every flat top tile is covered exactly once by a merged rectangle;
#   4. build determinism: two builds of the same Level produce identical vertex/index data;
#   5. support spikes (section 12.4): role-1/2 pieces with bbox <= 7x7 only, never inside the
#      hub bbox, never where any of the 9 centre columns holds a tile below the platform;
#   6. the grain factor reference stays inside [0.94, 1.06] over a big coordinate sweep.
# extends RefCounted, preload-by-path only (D-T001-1); a global class_name does not resolve
# under --headless --script.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const MesherScript := preload("res://view/level_mesher.gd")

const MAX_TRIS_L30 := 30000
const MAX_MS := 600
const CASES := [[1, 1], [7, 12], [7, 30]]


func run() -> Array[String]:
	var failures: Array[String] = []
	for case in CASES:
		failures.append_array(_one(int(case[0]), int(case[1])))
	failures.append_array(_determinism())
	failures.append_array(_grain_range())
	return failures

func _one(seed: int, level: int) -> Array[String]:
	var failures: Array[String] = []
	var L := VoidGenScript.generate(seed, level)
	if L.is_empty():
		failures.append("seed %d level %d: generator failed" % [seed, level])
		return failures
	var r: Dictionary = MesherScript.build(L)
	var n_flat: int = int(L["tiles"].filter(func(t): return int(t[3]) == 0).size())
	if int(r["tiles_flat"]) != n_flat:
		failures.append("seed %d level %d: tiles_flat %d != flat tile count %d" % [seed, level, int(r["tiles_flat"]), n_flat])
	if int(r["tiles_top"]) != n_flat:
		failures.append("seed %d level %d: greedy merge covers %d top tiles, expected %d" % [seed, level, int(r["tiles_top"]), n_flat])
	if int(r["triangles"]) <= 0:
		failures.append("seed %d level %d: no triangles" % [seed, level])
	if level == 30 and int(r["triangles"]) > MAX_TRIS_L30:
		failures.append("seed %d level %d: %d triangles > %d" % [seed, level, int(r["triangles"]), MAX_TRIS_L30])
	if int(r["ms"]) > MAX_MS:
		failures.append("seed %d level %d: %d ms > %d ms" % [seed, level, int(r["ms"]), MAX_MS])
	print("MESH seed=%d level=%d tiles=%d flat=%d ramps=%d props=%d pads=%d spikes=%d tris=%d build_ms=%d" % [
		seed, level, L["tiles"].size(), n_flat, int(r["ramps"]), int(r["props"]), int(r["pads"]),
		(r["spikes"] as Array).size(), int(r["triangles"]), int(r["ms"])])
	# hub excluded from spikes: no spike centre may fall inside the hub bbox
	var hub := _piece_bbox(L, 0)
	if not hub.is_empty():
		for cell in r["spikes"]:
			var cx: int = int(cell[0])
			var cz: int = int(cell[1])
			if cx >= int(hub[0]) and cx <= int(hub[2]) and cz >= int(hub[1]) and cz <= int(hub[3]):
				failures.append("seed %d level %d: spike under hub column %d,%d" % [seed, level, cx, cz])
	# every spike must sit under a small platform and none of its 9 columns may hold a tile below
	failures.append_array(_spike_columns(L, r))
	var expected_mats := ["platform_top", "walkway_top"]
	for m in expected_mats:
		if not (r["meshes"] as Dictionary).has(m):
			failures.append("seed %d level %d: mesh '%s' missing (should always have geometry)" % [seed, level, m])
	return failures

func _piece_bbox(L: Dictionary, role: int) -> Array:
	for p in L["pieces"]:
		if int(p["role"]) == role:
			return p["bbox"]
	return []


func _spike_columns(L: Dictionary, r: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var cols := {}
	var roles := {}
	for p in L["pieces"]:
		roles[int(p["id"])] = int(p["role"])
	for t in L["tiles"]:
		var kz := "%d,%d" % [int(t[0]), int(t[1])]
		if not cols.has(kz):
			cols[kz] = []
		(cols[kz] as Array).append(int(t[2]))
	var piece_by_center := {}
	for p in L["pieces"]:
		if int(p["role"]) != 1 and int(p["role"]) != 2:
			continue
		var bb: Array = p["bbox"]
		var pid := int(p["id"])
		if (int(bb[2]) - int(bb[0]) + 1) > MesherScript.SPIKE_MAX_BBOX or (int(bb[3]) - int(bb[1]) + 1) > MesherScript.SPIKE_MAX_BBOX:
			continue
		piece_by_center["%d,%d" % [(int(bb[0]) + int(bb[2])) / 2, (int(bb[1]) + int(bb[3])) / 2]] = pid
	for cell in r["spikes"]:
		var key := "%d,%d" % [int(cell[0]), int(cell[1])]
		if not piece_by_center.has(key):
			failures.append("spike at %s is not a small platform centre (seed/level unknown)" % key)
			continue
		var pid: int = int(piece_by_center[key])
		var min_y := 1 << 30
		for t in L["tiles"]:
			if int(t[4]) == pid and int(t[2]) < min_y:
				min_y = int(t[2])
		for ddx in range(-1, 2):
			for ddz in range(-1, 2):
				for y2 in cols.get("%d,%d" % [int(cell[0]) + ddx, int(cell[1]) + ddz], []):
					if int(y2) < min_y:
						failures.append("spike at %s has a tile below its platform in column +%d/+%d" % [key, ddx, ddz])
	return failures

func _mesh_fingerprint(m: ArrayMesh) -> String:
	var s0 := m.surface_get_arrays(0)
	var a: PackedVector3Array = s0[Mesh.ARRAY_VERTEX]
	var i: PackedInt32Array = s0[Mesh.ARRAY_INDEX]
	return "%d|%d|%s|%s" % [a.size(), i.size() / 3, hash(a), hash(i)]


func _determinism() -> Array[String]:
	var failures: Array[String] = []
	var L := VoidGenScript.generate(7, 30)
	var r1: Dictionary = MesherScript.build(L)
	var r2: Dictionary = MesherScript.build(L)
	var m1: Dictionary = r1["meshes"]
	var m2: Dictionary = r2["meshes"]
	if m1.keys() != m2.keys():
		failures.append("determinism: mesh name sets differ")
	for mn in m1.keys():
		if _mesh_fingerprint(m1[mn]) != _mesh_fingerprint(m2[mn]):
			failures.append("determinism: mesh '%s' differs between identical builds" % mn)
	return failures


func _grain_range() -> Array[String]:
	var failures: Array[String] = []
	var lo := 2.0
	var hi := -2.0
	for tx in range(-800, 801, 13):
		for tz in range(-800, 801, 11):
			var g: float = MesherScript.grain_factor(tx * 8 + 5, tz * 8 + 3)
			lo = minf(lo, g)
			hi = maxf(hi, g)
	if lo < 0.94 - 1e-9 or hi > 1.06 + 1e-9:
		failures.append("grain factor out of [0.94, 1.06]: [%f, %f]" % [lo, hi])
	# the CPU grain and the shader must agree at a normalised probe (documented wrap rule)
	if absf(MesherScript.grain_factor(-8 + 3, -16 + 5) - MesherScript.grain_factor(4294967288 + 3, 4294967280 + 5)) > 1e-12:
		failures.append("grain wrap rule mismatch for negative texels")
	return failures
