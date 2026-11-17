extends SceneTree

# T-015 headless check: load every game/assets/models/*.glb through the real
# import pipeline and print its name and triangle count. Fails (exit 1) if any
# file fails to load, exceeds the 2000-triangle budget, or the count != 11.
#   tools\godot\godot.exe --headless --path game --import
#   tools\godot\godot.exe --headless --path game --script res://tools/check_models.gd

const MAX_TRIS := 2000
const EXPECTED := 11

func _init() -> void:
	var dir := DirAccess.open("res://assets/models")
	if dir == null:
		print("GLB FAIL models dir missing")
		quit(1)
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			names.append(f)
	names.sort()
	var failed := false
	for n in names:
		var ps: PackedScene = load("res://assets/models/" + n)
		if ps == null:
			print("GLB FAIL %s (load returned null)" % n)
			failed = true
			continue
		var root: Node = ps.instantiate()
		var tris := 0
		var first_col := "(none)"
		var stack: Array = [root]
		while stack.size() > 0:
			var node: Node = stack.pop_back()
			for c in node.get_children():
				stack.push_back(c)
			if node is MeshInstance3D and node.mesh != null:
				var mesh: Mesh = node.mesh
				for s in mesh.get_surface_count():
					var arrays: Array = mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					if idx.size() > 0:
						tris += int(idx.size() / 3.0)
					else:
						tris += int(verts.size() / 3.0)
					if first_col == "(none)" and arrays[Mesh.ARRAY_COLOR] != null:
						var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
						first_col = "(%.4f, %.4f, %.4f)" % [cols[0].r, cols[0].g, cols[0].b]
		print("GLB %s tris %d first_vertex_colour %s" % [n, tris, first_col])
		if tris > MAX_TRIS:
			print("GLB FAIL %s over the %d-triangle budget" % [n, MAX_TRIS])
			failed = true
		root.free()
	if names.size() != EXPECTED:
		print("GLB FAIL expected %d .glb files, found %d" % [EXPECTED, names.size()])
		failed = true
	if failed:
		quit(1)
	else:
		print("GLB OK (%d/%d loaded, all <= %d triangles)" % [names.size(), EXPECTED, MAX_TRIS])
		quit(0)
