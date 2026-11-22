extends Node3D
#
# Jump pad view (D-JUMPPAD-5; DESIGN.md section 3.4). NOT the launch pad (that one is a tile
# top material in level_mesher.gd, "pad"). The owner's reference (game/out/owner_refs/
# jumppad_ref.png): a saturated blue, glossy, semi-transparent rounded-square slab with soft
# corners, sitting just above the floor.
#
# One slab per pad in the sim's jump pad set (sim/jump_pads.gd), at the pad tile's centre.
# Everything animated is DERIVED from sim state and the sim tick - this node owns no clock
# and never writes sim state:
#   compress + rebound  the slab squashes to 35 % height in 0.06 s and springs back with a
#                       damped overshoot (~1.19x), from the tick the pad fired (ready_tick -
#                       rearm_ticks); squash_at() is the curve, pinned by the tests;
#   ripple              two flat rings expand from the pad and fade over RIPPLE_S;
#   re-arm              the glow dims while the pad is inert and comes back when it re-arms;
#   idle                a slow 1 Hz glow pulse so a pad reads at a distance;
#   collapse            a pad whose tile fell (lost) or is in the removed set is hidden - it
#                       goes down with the tile, exactly as a gift does (no special case).

const TICK_DT := 1.0 / 60.0

const SIZE := 0.84          # u, the slab's footprint (the tile is 1 u)
const HEIGHT := 0.16        # u
const RADIUS := 0.22        # u, corner radius of the footprint
const BEVEL := 0.07         # u, the soft top edge
const CORNER_SEGS := 6
const LIFT := 0.012         # u above the tile top ("sits just above the floor")

## The pad colour: a saturated blue (the reference), deeper than the walkway's #3A74FF and the
## launch pad's #2A5BFF so it reads as an object, not a tile (palette.json roles.jump_pad).
const BLUE := Color(0.10, 0.17, 1.0, 0.80)
const GLOW := Color(0.20, 0.34, 1.0)
const GLOW_ARMED := 0.9
const GLOW_INERT := 0.2
const RING_COLOR := Color(0.62, 0.80, 1.0)

const SQUASH_T := 0.06      # s to full compression
const SQUASH_MIN := 0.35    # height scale at full compression
const REBOUND_K := 7.0      # 1/s, damping of the rebound
const REBOUND_W := 18.0     # rad/s, the rebound's ring frequency
const ANIM_S := 0.9         # s after which the slab is back at rest
const RIPPLE_S := 0.45      # s, ring lifetime
const RIPPLE_R0 := 0.45     # u
const RIPPLE_R1 := 2.1      # u

var _pads: Array = []          # [x, z, y]
var _slabs: Array = []         # MeshInstance3D per pad (the squash target)
var _rings: Array = []         # [ring_a, ring_b] per pad
var _mats: Array = []          # StandardMaterial3D per pad (glow per pad)
var _ring_mats: Array = []     # [mat_a, mat_b] per pad
var _removed: Dictionary = {}
var _mesh: ArrayMesh = null


func setup(level: Dictionary, jp: RefCounted) -> void:
	for c in get_children():
		c.queue_free()
	_pads = []
	_slabs = []
	_rings = []
	_mats = []
	_ring_mats = []
	if jp == null:
		return
	if _mesh == null:
		_mesh = build_slab_mesh()
	for p in jp.pads:
		_pads.append(p)
		var root := Node3D.new()
		root.name = "JumpPad_%d_%d_%d" % [int(p[0]), int(p[1]), int(p[2])]
		root.position = Vector3(float(int(p[0])) + 0.5, float(int(p[2])) * 0.5 + LIFT,
				float(int(p[1])) + 0.5)
		add_child(root)
		var slab := MeshInstance3D.new()
		slab.name = "Slab"
		slab.mesh = _mesh
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := _slab_material()
		slab.material_override = m
		root.add_child(slab)
		var pair: Array = []
		var mpair: Array = []
		for k in 2:
			var ring := MeshInstance3D.new()
			ring.name = "Ripple%d" % k
			var tm := TorusMesh.new()
			tm.inner_radius = 0.92
			tm.outer_radius = 1.0
			tm.rings = 32
			tm.ring_segments = 6
			ring.mesh = tm
			ring.position = Vector3(0.0, 0.03, 0.0)
			ring.scale = Vector3(1.0, 0.25, 1.0)
			ring.visible = false
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rm := StandardMaterial3D.new()
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			rm.albedo_color = RING_COLOR
			ring.material_override = rm
			root.add_child(ring)
			pair.append(ring)
			mpair.append(rm)
		_slabs.append(slab)
		_mats.append(m)
		_rings.append(pair)
		_ring_mats.append(mpair)
	sync(jp, 0)


## The world's live removed-tile set (collision.gd's w["removed"]): a pad on a removed tile
## is hidden for as long as the tile is gone.
func set_removed(keys: Dictionary) -> void:
	_removed = keys


func pad_count() -> int:
	return _slabs.size()


func slab(i: int) -> MeshInstance3D:
	return _slabs[i]


## Per frame (or per tick): the sim's jump pad state and its level tick.
func sync(jp: RefCounted, tick: int) -> void:
	if jp == null:
		return
	var now := float(tick) * TICK_DT
	for i in _slabs.size():
		var root: Node3D = (_slabs[i] as Node3D).get_parent()
		var gone: bool = jp.is_lost(i) or _removed.has(jp.tile_key(i))
		root.visible = not gone
		if gone:
			continue
		var fired := int(jp.ready_tick[i]) - int(jp.rearm_ticks)
		var t := INF
		if int(jp.ready_tick[i]) > 0:
			t = float(tick - fired) * TICK_DT
		var sy := squash_at(t)
		var sxz := 1.0 + (1.0 - sy) * 0.25
		(_slabs[i] as Node3D).scale = Vector3(sxz, sy, sxz)
		var armed: bool = jp.is_armed(i, tick)
		var pulse := 0.5 + 0.5 * sin(now * TAU)
		var m: StandardMaterial3D = _mats[i]
		m.emission_energy_multiplier = (GLOW_ARMED * (0.75 + 0.25 * pulse)) if armed else GLOW_INERT
		for k in 2:
			var ring: MeshInstance3D = _rings[i][k]
			var rt := t - 0.08 * float(k)
			if rt < 0.0 or rt > RIPPLE_S:
				ring.visible = false
				continue
			var u := rt / RIPPLE_S
			var r := lerpf(RIPPLE_R0, RIPPLE_R1, 1.0 - (1.0 - u) * (1.0 - u))
			ring.visible = true
			ring.scale = Vector3(r, 0.25, r)
			var rm: StandardMaterial3D = _ring_mats[i][k]
			rm.albedo_color = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, (1.0 - u) * 0.9)


## The slab's height scale t seconds after the pad fired (INF / negative = at rest = 1.0):
## a linear squash to SQUASH_MIN over SQUASH_T, then a damped spring back through ~1.19x.
static func squash_at(t: float) -> float:
	if t < 0.0 or t >= ANIM_S:
		return 1.0
	if t < SQUASH_T:
		return lerpf(1.0, SQUASH_MIN, t / SQUASH_T)
	var u := t - SQUASH_T
	return 1.0 - (1.0 - SQUASH_MIN) * exp(-REBOUND_K * u) * cos(REBOUND_W * u)


func _slab_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = BLUE
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.05
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.3
	m.emission_enabled = true
	m.emission = GLOW
	m.emission_energy_multiplier = GLOW_ARMED
	return m


# ---- the mesh: a rounded-square slab with a soft bevelled top ----------------------------

## The footprint outline at half-extent `half` and corner radius `r`, points ordered by
## increasing angle from +X toward +Z (clockwise seen from above, Godot's front-face order
## for the caps and sides built below).
static func outline(half: float, r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := half - r
	var centres := [Vector2(c, c), Vector2(-c, c), Vector2(-c, -c), Vector2(c, -c)]
	for q in 4:
		var a0 := float(q) * PI * 0.5
		for s in segs + 1:
			var a := a0 + PI * 0.5 * float(s) / float(segs)
			pts.append((centres[q] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


static func build_slab_mesh() -> ArrayMesh:
	var half := SIZE * 0.5
	var bottom := outline(half, RADIUS, CORNER_SEGS)
	var shoulder := outline(half, RADIUS, CORNER_SEGS)
	var top := outline(half - BEVEL, maxf(RADIUS - BEVEL * 0.8, 0.02), CORNER_SEGS)
	var rings := [
		[bottom, 0.0], [shoulder, HEIGHT - BEVEL], [top, HEIGHT],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := bottom.size()
	for k in 2:
		var lo: PackedVector2Array = rings[k][0]
		var hi: PackedVector2Array = rings[k + 1][0]
		var ylo: float = rings[k][1]
		var yhi: float = rings[k + 1][1]
		for i in n:
			var j := (i + 1) % n
			var l0 := Vector3(lo[i].x, ylo, lo[i].y)
			var l1 := Vector3(lo[j].x, ylo, lo[j].y)
			var u0 := Vector3(hi[i].x, yhi, hi[i].y)
			var u1 := Vector3(hi[j].x, yhi, hi[j].y)
			st.add_vertex(u0)
			st.add_vertex(l0)
			st.add_vertex(l1)
			st.add_vertex(u0)
			st.add_vertex(l1)
			st.add_vertex(u1)
	var centre := Vector3(0.0, HEIGHT, 0.0)
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(centre)
		st.add_vertex(Vector3(top[i].x, HEIGHT, top[i].y))
		st.add_vertex(Vector3(top[j].x, HEIGHT, top[j].y))
	st.index()
	st.generate_normals()
	return st.commit()
