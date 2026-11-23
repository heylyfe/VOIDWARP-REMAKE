extends RefCounted
#
# view/player_figure_fallback.gd - the blocky stand-in for player_figure.glb (U4).
#
# Terra's bug hunt found godot.log carrying "instantiate on null" for
# res://assets/models/player_figure.glb when the import cache was missing. A missing
# player model must not crash the game, and it must not leave the third-person rig
# framing empty space either (the game then reads first-person, which is the defect
# T-015 was opened to fix).
#
# So this builds a blocky figure with the SAME six limb names and the SAME local boxes
# the .glb carries, measured from the real model:
#
#   Torso  node (0.00, 0.80, 0)  box (-0.268, -0.260, -0.139) size (0.536, 0.554, 0.278)
#   Head   node (0.00, 1.40, 0)  box (-0.153, -0.331, -0.129) size (0.306, 0.231, 0.258)
#   ArmL   node (-0.34, 1.38, 0) box (-0.160, -0.783, -0.132) size (0.222, 0.555, 0.263)
#   ArmR   node (0.34, 1.38, 0)  box (-0.062, -0.783, -0.132) size (0.222, 0.555, 0.263)
#   LegL   node (-0.16, 0.85, 0) box (-0.106, -0.850, -0.125) size (0.264, 0.546, 0.250)
#   LegR   node (0.16, 0.85, 0)  box (-0.158, -0.850, -0.125) size (0.264, 0.546, 0.250)
#
# The origin is at the feet, exactly as the .glb's is, so the caller's
# `position = feet` and the locomotion rig's `_cache_player_limbs` both work unchanged:
# the rig finds the six nodes by name and reads their AABBs for the limb mounts. The
# boxes are centred on their own origin, so a limb's mount differs from the real model's
# by at most 0.026 u (the real leg/arm meshes are offset inside their node) - a pose
# detail, not a crash, and the fallback is only ever drawn when the real model is gone.

const LIMBS := {
	"Torso": [Vector3(0.0, 0.817, 0.0), Vector3(0.536, 0.554, 0.278)],
	"Head": [Vector3(0.0, 1.1845, 0.0), Vector3(0.306, 0.231, 0.258)],
	"ArmL": [Vector3(-0.389, 0.875, 0.0), Vector3(0.222, 0.555, 0.263)],
	"ArmR": [Vector3(0.389, 0.875, 0.0), Vector3(0.222, 0.555, 0.263)],
	"LegL": [Vector3(-0.134, 0.273, 0.0), Vector3(0.264, 0.546, 0.250)],
	"LegR": [Vector3(0.134, 0.273, 0.0), Vector3(0.264, 0.546, 0.250)],
}


## The body tone the fallback's vertex colours carry. The real .glb stores its palette in
## vertex colours (export_materials="NONE"), and view/player_locomotion.gd's segmentation
## reads ARRAY_COLOR to tone the boots - a mesh with NO colour array makes that pass build
## an empty surface. So the fallback carries colours too, and the rig treats it exactly
## like the real model.
const BODY_TONE := Color(0.62, 0.66, 0.72, 1.0)


## The blocky figure: a Node3D with six named MeshInstance3D children, feet at y = 0.
## The caller applies the player body material and parents it exactly as it would the
## instantiated .glb.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "PlayerFigureFallback"
	for nm in LIMBS:
		var spec: Array = LIMBS[nm]
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = _box_mesh(spec[1], BODY_TONE)
		mi.position = spec[0]
		root.add_child(mi)
	return root


## A box as an ArrayMesh with a filled ARRAY_COLOR, so the locomotion rig's vertex-colour
## passes (tone_mesh, the boot tone) work on it exactly as they do on the .glb.
static func _box_mesh(size: Vector3, tone: Color) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(tone)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
