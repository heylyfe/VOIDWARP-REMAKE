extends Node3D
#
# Straggler beam view (ticket T-020; DESIGN.md section 3.3).
#
# "Straggler highlight beam marks the last 20% of REAL gifts only; hazards are
# never highlighted and never count toward remaining-gift totals."
#
# Which gifts are stragglers is sim state: sim/gifts.gd straggler_ids() (the
# 20% rule lives there, one implementation for the black and the gold phase).
# This node only draws: one vertical beam #7CFFF4 from the gift's slot position
# up to Y +40 u, fog-exempt so it reads across the level. The positions come
# from the sim's slot_pos() - nothing is computed here.

const GiftsScript := preload("res://sim/gifts.gd")

const BEAM_COLOR := Color(0.486, 1.0, 0.957)  # #7CFFF4
const BEAM_TOP := 40.0     # absolute Y the beam reaches
const BEAM_RADIUS := 0.09
const BEAM_ALPHA := 0.5

var _gifts: RefCounted = null
var _beams := {}           # slot id -> MeshInstance3D


func setup(gifts_state: RefCounted) -> void:
	_gifts = gifts_state
	sync()


## Syncs the beam set from the sim's gift state (call every frame or on change).
func sync(gifts_state: RefCounted = null) -> void:
	if gifts_state != null:
		_gifts = gifts_state
	if _gifts == null:
		return
	var ids: Array = _gifts.straggler_ids()
	var wanted := {}
	for id in ids:
		wanted[id] = true
	# remove beams that left the straggler set
	for id in _beams.keys():
		if not wanted.has(id):
			_beams[id].queue_free()
			_beams.erase(id)
	# add the new ones
	for id in ids:
		if _beams.has(id):
			continue
		var pos: Vector3 = _gifts.slot_pos(id)
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		var len: float = maxf(BEAM_TOP - pos.y, 0.5)
		mesh.height = len
		mesh.top_radius = BEAM_RADIUS
		mesh.bottom_radius = BEAM_RADIUS
		mesh.radial_segments = 8
		mesh.rings = 1
		mi.mesh = mesh
		mi.material_override = _material()
		mi.position = Vector3(pos.x, pos.y + len * 0.5, pos.z)
		add_child(mi)
		_beams[id] = mi


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, BEAM_ALPHA)
	m.disable_fog = true
	m.disable_receive_shadows = true
	return m
