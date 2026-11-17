extends Node3D
#
# Beacon view (ticket T-020; TERRAIN_SPEC.md sections 6.1 and 12.2, DESIGN.md
# section 3, research/fable-tickets.md section 2.3).
#
# CLOSED: the T-015 beacon mesh as modelled (dull beacon_closed #3A4A55, no
# emission), plus the progress read-out: a dim ring of 8 unlit segments around
# the dais edge, one lit per 12.5% of real black gifts collected.
# OPEN: white emissive (beacon_open #E8FFFF, emission x4.0) and the light
# column #E8FFFF, 1.5 u wide, alpha 0.6, to Y +60 u, visible through the fog;
# both ramp in over 0.6 s (36 ticks) from the open tick, then the column pulses
# 0.9..1.0 at 0.5 Hz. The T-015 model has no doorway, so there is no door slab
# to animate (D-T020-6).
#
# Reads sim state only (never writes): set_progress + set_open from the caller.

const BeaconScript := preload("res://sim/beacon.gd")

const MODEL := "res://assets/models/beacon.glb"
const OPEN_COLOR := Color(0.910, 1.0, 1.0)   # #E8FFFF
const DIM_COLOR := Color(0.227, 0.290, 0.333)  # #3A4A55
const LIT_COLOR := Color(0.486, 1.0, 0.957)  # #7CFFF4 (D-T020-6: no lit colour stated)
const RING_SEGMENTS := 8
const RING_HALF := 2.5        # dais cells -2..2 -> world edge 2.5 u from the centre
const RING_Y := 0.02          # above the dais top (y = 1 * 0.5)
const EMISSION_MAX := 4.0     # beacon_open emission x 4.0
const COLUMN_HEIGHT := 60.0   # light column to Y +60 u
const COLUMN_RADIUS := 0.75   # 1.5 u wide
const OPEN_RAMP := 0.6        # 36 ticks

var _ramp := 0.0
var _opened := false
var _ring: Array = []         # 8 MeshInstance3D
var _column: MeshInstance3D
var _body: Array = []         # the beacon mesh instances
var _open_mat: StandardMaterial3D


func _init() -> void:
	var ps: PackedScene = load(MODEL)
	if ps != null:
		var body: Node3D = ps.instantiate()
		add_child(body)
		var stack: Array = [body]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.push_back(c)
			if n is MeshInstance3D:
				_body.append(n)
	_build_ring()
	_build_column()


## Places the node on the beacon tile of the Level dict (x + 0.5, y * 0.5, z + 0.5).
func setup(level: Dictionary) -> void:
	var bp: Array = level.get("beacon", [0, 0, 1])
	position = Vector3(float(int(bp[0])) + 0.5, float(int(bp[2])) * 0.5, float(int(bp[1])) + 0.5)


func _build_ring() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.9, 0.25)
	for i in RING_SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _ring_material(false)
		# 8 points on the square rim of the 5x5 dais: 4 edge midpoints + 4 corners.
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		var c := absf(cos(angle))
		var s := absf(sin(angle))
		var mx := signf(cos(angle)) * maxf(c, s) * RING_HALF
		var mz := signf(sin(angle)) * maxf(c, s) * RING_HALF
		mi.position = Vector3(mx, RING_Y, mz)
		mi.rotation.y = angle + PI * 0.5
		add_child(mi)
		_ring.append(mi)


func _build_column() -> void:
	var mesh := CylinderMesh.new()
	mesh.height = COLUMN_HEIGHT
	mesh.top_radius = COLUMN_RADIUS
	mesh.bottom_radius = COLUMN_RADIUS
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(OPEN_COLOR.r, OPEN_COLOR.g, OPEN_COLOR.b, 0.6)
	m.disable_fog = true
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position = Vector3(0.0, COLUMN_HEIGHT * 0.5, 0.0)
	mi.scale.y = 0.001
	mi.visible = false
	add_child(mi)
	_column = mi


static func _ring_material(lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = LIT_COLOR if lit else DIM_COLOR
	if lit:
		m.emission_enabled = true
		m.emission = LIT_COLOR
		m.emission_energy_multiplier = 1.5
	return m


## Progress read-out: one segment lit per 12.5% of real black gifts collected.
func set_progress(collected: int, total: int) -> void:
	var lit := 0
	if total > 0:
		lit = clampi(collected * RING_SEGMENTS / total, 0, RING_SEGMENTS)
	for i in _ring.size():
		_ring[i].material_override = _ring_material(i < lit)


## Opens (or resets) the beacon; the open ramp runs in _process.
func set_open(opened: bool) -> void:
	_opened = opened
	if not opened:
		_ramp = 0.0
		for b in _body:
			b.material_override = null
		if _column != null:
			_column.visible = false


func _process(delta: float) -> void:
	if not _opened:
		return
	if _ramp < 1.0:
		_ramp = minf(_ramp + delta / OPEN_RAMP, 1.0)
	var pulse := 1.0
	if _ramp >= 1.0:
		# slow pulse 0.9 -> 1.0 at 0.5 Hz once the ramp is done
		pulse = 0.95 + 0.05 * sin(Time.get_ticks_msec() * 0.001 * TAU * 0.5)
	var energy := EMISSION_MAX * _ramp * pulse
	if _open_mat == null:
		_open_mat = _open_material()
	_open_mat.emission_energy_multiplier = energy
	for b in _body:
		b.material_override = _open_mat
	if _column != null:
		_column.visible = _ramp > 0.01
		_column.scale.y = maxf(_ramp, 0.001)
		_column.position.y = COLUMN_HEIGHT * 0.5 * _ramp


static func _open_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = OPEN_COLOR
	m.emission_enabled = true
	m.emission = OPEN_COLOR
	return m


## Convenience: sync straight from the sim's beacon state + gift state.
func sync_from(beacon_state: RefCounted, gifts_state: RefCounted) -> void:
	set_open(beacon_state.is_open())
	if gifts_state != null and not beacon_state.is_open():
		set_progress(gifts_state.total_real - gifts_state.remaining(), gifts_state.total_real)
