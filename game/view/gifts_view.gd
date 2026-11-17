extends Node3D
#
# Gifts view (ticket T-020; TERRAIN_SPEC.md sections 6.7 and 12.2, DESIGN.md
# section 3). One instance of the T-015 gift models per REAL gift slot, read
# only from the sim's gift state:
#   - black gifts in the black phase, gold gifts in the gold phase - the gold
#     gift appears at exactly the same slot id and position (the position comes
#     from sim/gifts.gd slot_pos(), the single section 6.7 mapping outside
#     terrain/; nothing is computed here);
#   - occ == 1 slots (tripmines, T-021) never get a gift node.
#
# Emission (black rim x1.5, gold x2.0, TERRAIN_SPEC 12.2) is an additive
# material_overlay pass that re-draws the mesh with its vertex colours: the
# near-black body adds ~nothing, the rim ribbon adds its colour times the
# factor (D-T020-6).
#
# The caller drives sync(gifts) every frame (or on change); this node never
# writes sim state.

const GiftsScript := preload("res://sim/gifts.gd")

const BLACK_MODEL := "res://assets/models/black_gift.glb"
const GOLD_MODEL := "res://assets/models/gold_gift.glb"
const RIM_FACTOR := 1.5   # black_gift_rim emission x 1.5 (TERRAIN_SPEC 12.2)
const GOLD_FACTOR := 2.0  # gold_gift emission x 2.0 (TERRAIN_SPEC 12.2)

var _gifts: RefCounted = null
var _black: Array = []    # slot id -> Node3D (null on occ == 1 slots)
var _gold: Array = []     # slot id -> Node3D


## Builds one node per real gift slot. level: the Level dict; gifts_state: the
## sim's gift state (sim/gifts.gd create()).
func setup(level: Dictionary, gifts_state: RefCounted) -> void:
	_gifts = gifts_state
	var n: int = _gifts.slots.size()
	_black.resize(n)
	_gold.resize(n)
	var black_ps: PackedScene = load(BLACK_MODEL)
	var gold_ps: PackedScene = load(GOLD_MODEL)
	for i in n:
		if not _gifts.is_real(i):
			continue
		var pos: Vector3 = _gifts.slot_pos(i)
		var b: Node3D = black_ps.instantiate()
		b.position = pos
		_add_emission(b, RIM_FACTOR)
		add_child(b)
		_black[i] = b
		var g: Node3D = gold_ps.instantiate()
		g.position = pos
		_add_emission(g, GOLD_FACTOR)
		g.visible = false
		add_child(g)
		_gold[i] = g
	sync()


## Adds the additive emission overlay to every mesh under the instance.
static func _add_emission(root: Node3D, factor: float) -> void:
	var mat := emission_material(factor)
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			n.material_overlay = mat


## The shared additive overlay material (one instance per factor value).
static func emission_material(factor: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(factor, factor, factor)
	m.disable_receive_shadows = true
	return m


## Syncs visibility from the sim's gift state (call every frame or on change).
func sync(gifts_state: RefCounted = null) -> void:
	if gifts_state != null:
		_gifts = gifts_state
	if _gifts == null:
		return
	var gold: bool = _gifts.phase == GiftsScript.PHASE_GOLD
	for i in _gifts.slots.size():
		var shown: bool = _gifts.is_real(i) and not _gifts.collected(i)
		if _black[i] != null:
			_black[i].visible = shown and not gold
		if _gold[i] != null:
			_gold[i].visible = shown and gold
