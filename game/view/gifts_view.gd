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
# Black-gift rendering: the glb carries no material by design (export_materials="NONE",
# palette lives in vertex colours), so without a base override the surface draws with
# Godot's default WHITE material and the vertex colours are never seen - the body
# rendered a pale near-white box (the original defect; the additive rim only added
# ~(0.03, 0.04, 0.05) on top of it). The black gift instead renders its vertex colours
# unshaded as its base material (_black_body_material()): body #050608 near-black,
# rim ribbon #7CFFF4 bright cyan (measured 182,251,246) - LIT-INDEPENDENT, so the
# rim stays bright in every act and the gift never reads matte.
#
# The additive rim overlay (rim x1.5, TERRAIN_SPEC 12.2, D-T020-6) is NOT used by the
# black gift: measured (J8), the additive pass adds a flat ~(+45,+46,+54) to EVERY
# pixel of the mesh, body included, so the "near-black body" could never land
# near-black in this renderer (it rendered (42,4c,55) against a (15,28,33) base) and
# the pre-J8 white box happened. RIM_FACTOR stays as the spec's recorded value. The
# same finding J3 reported for the gold gift's x2.0 pass.
#
# The gold gift renders the same way (unshaded vertex colours as its base material,
# pass-through albedo; COLOR_0 now stores LINEAR values, so the screen colour lands
# on spec #FFC83D - see out/decisions/J14.md).
#
# The caller drives sync(gifts) every frame (or on change); this node never
# writes sim state.

const GiftsScript := preload("res://sim/gifts.gd")

const BLACK_MODEL := "res://assets/models/black_gift.glb"
const GOLD_MODEL := "res://assets/models/gold_gift.glb"
const RIM_FACTOR := 1.5   # black_gift_rim emission x 1.5 (TERRAIN_SPEC 12.2, D-T020-6). The black gift no longer applies it as an additive overlay (J8: measured to add a flat ~+45 to EVERY pixel, body included - the "near-black body" could never land near-black); kept as the spec's recorded value. The rim renders via the unshaded vertex-colour base pass (see _black_body_material).
const GOLD_FACTOR := 2.0  # gold_gift emission x 2.0 (TERRAIN_SPEC 12.2); no longer used to render anything (the gold gift renders via _gold_body_material()); kept as the spec's value

var _gifts: RefCounted = null
var _black: Array = []    # slot id -> Node3D (null on occ == 1 slots)
var _gold: Array = []     # slot id -> Node3D


## Builds one node per real gift slot. level: the Level dict; gifts_state: the
## sim's gift state (sim/gifts.gd create()). Re-entrant: a second setup() (a
## second level on the same node) drops the previous level's nodes first,
## exactly as view/tripmine_view.gd setup() does.
func setup(level: Dictionary, gifts_state: RefCounted) -> void:
	_gifts = gifts_state
	for child in get_children():
		child.free()
	_black = []
	_gold = []
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
		_add_body(b, _black_body_material())
		add_child(b)
		_black[i] = b
		var g: Node3D = gold_ps.instantiate()
		g.position = pos
		_add_body(g, _gold_body_material())
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


## Adds the base material to every mesh surface under the instance (the glb
## carries no material of its own - see the file header).
static func _add_body(root: Node3D, mat: StandardMaterial3D) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and n.mesh != null:
			for s in n.mesh.get_surface_count():
				n.set_surface_override_material(s, mat)


## The black gift's base pass: unshaded, using the mesh's vertex colours (body
## #050608 "black_gift_body", rim ribbon #7CFFF4 "black_gift_rim", palette.json) -
## exactly the gold body's pattern (_gold_body_material(), J3). No albedo tint:
## unlike the gold body nothing here sits near the renderer's highlight shoulder, and
## no compensation is needed - measured (J8), pass-through renders body (38,42,49),
## rim (182,251,246).
##
## The rim emission is NOT applied as an additive material_overlay: measured (J8, in
## the Deepwater act-I world, seed 7 level 1), the additive x1.5 overlay adds a flat
## ~(+45,+46,+54) to EVERY pixel of the mesh, body included - body rendered (42,4c,55)
## against the base's (15,28,33) - so the "near-black body" could never land near-black
## (and, pre-J8, pale white). The overlay was removed from the black gift by the same
## call J3 made for the gold gift (the x2.0 pass clipped every channel to white). The
## rim stays a LIT-INDEPENDENT bright cyan because the base pass is unshaded with the
## ribbon's vertex colour at full strength. RIM_FACTOR (TERRAIN_SPEC 12.2, D-T020-6)
## is kept as the spec's recorded value, exactly as GOLD_FACTOR is.
static func _black_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## The gold gift's base pass: unshaded, using the mesh's vertex colours
## (#FFC83D, palette.json role "gold_gift"). Pass-through albedo (1,1,1): the
## glb's COLOR_0 now stores LINEAR values (J14 fixed the sRGB->linear export bug),
## so no pre-cancel tint is needed. J3's Color(1.0, 0.91, 0.46) was compensating
## for that bug and would double-apply now.
## The spec's emission x2.0 (TERRAIN_SPEC 12.2) cannot be applied as an
## additive pass here: measured, the overlay at x2.0 clips every channel and
## the gift renders pure white.
static func _gold_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


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
