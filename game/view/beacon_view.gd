extends Node3D
#
# Beacon view (ticket T-020; SPEC-CONFORMANCE pass: ticket T-085,
# research/fable-tickets.md section 2.3, TERRAIN_SPEC.md sections 6.1 and 12.2,
# DESIGN.md section 3).
#
# CLOSED: the T-015 beacon mesh as modelled (dull beacon_closed #3A4A55, no
# emission), carried by a base pass on the body surfaces: unshaded, white albedo,
# vertex_color_use_as_albedo - the mesh's COLOR_0 (a single flat #3A4A55,
# palette beacon_closed) is the albedo (T-085 / J13). The OPEN state's
# material_override replaces it; the CLOSED path assigns material_override = null,
# so the base pass is what renders. Plus the progress read-out: a dim ring of 8
# unlit segments around the dais edge, one lit per 12.5% of real black gifts collected.
# OPEN: white emissive (beacon_open #E8FFFF, emission x4.0) and the light
# column #E8FFFF, 1.5 u wide, alpha 0.6, to Y +60 u, visible through the fog;
# both ramp in over 0.6 s (36 ticks) from the open tick, then the column pulses
# 0.9..1.0 at 0.5 Hz. The T-015 model has no doorway, so there is no door slab
# to animate (D-T020-6 stands; D-T085-4).
#
# TICK-DRIVEN (T-085): the section 2.3 row "on the tick the last real black gift
# is collected ... the light column rises" is a tick contract, so sync_tick()
# owns the ramp and the pulse - the column is visible on the open tick itself
# (the ramp starts at 1/36, D-T085-3). The frame path (_process) stays for
# callers that have no tick clock (test_gifts.gd's smoke path).
#
# Also built here: the white shock ring that crosses the hub on the open tick,
# and the blocked state (Crowded Dais / Slow Door: the column turns danger red
# while entry is refused, and Slow Door shows a ring filling over 180 ticks).
#
# Reads sim state only (never writes): set_progress + set_open from the caller.

const BeaconScript := preload("res://sim/beacon.gd")
const BeaconAudioScript := preload("res://view/audio/beacon_audio.gd")

const MODEL := "res://assets/models/beacon.glb"
const OPEN_COLOR := Color(0.910, 1.0, 1.0)   # #E8FFFF
const DIM_COLOR := Color(0.227, 0.290, 0.333)  # #3A4A55
const LIT_COLOR := Color(0.486, 1.0, 0.957)  # #7CFFF4 (D-T020-6: no lit colour stated)
const DANGER_RED := Color(1.0, 0.1647, 0.1647)  # #FF2A2A (TERRAIN_SPEC 12.2)
const RING_SEGMENTS := 8
const RING_HALF := 2.5        # dais cells -2..2 -> world edge 2.5 u from the centre
const RING_Y := 0.02          # above the dais top (y = 1 * 0.5)
const EMISSION_MAX := 4.0     # beacon_open emission x 4.0
const COLUMN_HEIGHT := 60.0   # light column to Y +60 u
const COLUMN_RADIUS := 0.75   # 1.5 u wide
const COLUMN_ALPHA := 0.6     # section 2.3 OPEN row
const OPEN_RAMP := 0.6        # 36 ticks
const OPEN_TICKS := 36        # section 2.3: the slab/column ramp, 0.6 s
const PULSE_HZ := 0.5         # section 2.3: slow pulse 0.9 -> 1.0 at 0.5 Hz
const SLOW_DOOR_TICKS := 180  # section 2.3: the Slow Door ring fills over 180 ticks
const TRIGGER_RADIUS := BeaconScript.RADIUS  # 1.5 u, binding

var _ramp := 0.0
var _opened := false
var _open_cue_played := false  # the owner's open cue starts once per open; a re-fed state never restarts it
var _open_tick := -1          # the sim tick the beacon opened on (-1: no tick clock)
var _tick := 0
var _blocked := false
var _slow_door_ticks := -1    # ticks elapsed since entry was refused (-1: not refused)
var _ring: Array = []         # 8 MeshInstance3D
var _column: MeshInstance3D
var _shock: MeshInstance3D
var _slow_door: MeshInstance3D
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
	_apply_closed_body_material()
	_build_ring()
	_build_column()
	_build_shock_ring()
	_build_slow_door()


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


## The white shock ring that crosses the hub on the open tick (section 2.3,
## cosmetic): a flat ring that expands from the dais centre to the dais edge
## over the same 36 ticks as the column.
func _build_shock_ring() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.94
	mesh.outer_radius = 1.0
	mesh.rings = 3
	mesh.ring_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	m.disable_fog = true
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position = Vector3(0.0, RING_Y, 0.0)
	mi.visible = false
	add_child(mi)
	_shock = mi


## The Slow Door ring: it fills from the beacon axis out to the 1.5 u trigger
## radius over 180 ticks while entry is refused (section 2.3, blocked row).
func _build_slow_door() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	mesh.rings = 3
	mesh.ring_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(DANGER_RED.r, DANGER_RED.g, DANGER_RED.b, 0.7)
	m.disable_fog = true
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position = Vector3(0.0, RING_Y, 0.0)
	mi.visible = false
	add_child(mi)
	_slow_door = mi


## The CLOSED body's base pass: unshaded, using the mesh's vertex colours (the
## glb's COLOR_0 is a single flat #3A4A55 "beacon_closed", TERRAIN_SPEC 6.1 /
## palette.json; J13 read the accessor and every one of the 144 vertices carries
## it) - exactly the gifts' base pass (gifts_view.gd _add_body / _black_body_material,
## J3/J8/J10/J11). White albedo passes the mesh colours through unshaded. The OPEN
## state's material_override (_open_material(), emissive #E8FFFF x4.0) replaces it
## while open; set_open(false) clears the override so this pass renders again.
static func _closed_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## Adds the closed body's base material to every mesh surface under the instance
## (the glb carries no material of its own - see the file header).
func _apply_closed_body_material() -> void:
	var mat := _closed_body_material()
	for mi in _body:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)


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


## Opens (or resets) the beacon. tick: the sim tick the beacon opened on (the
## beacon_opened event's tick, i.e. the tick of the last real black gift); -1
## keeps the frame-driven path for callers with no tick clock.
func set_open(opened: bool, tick: int = -1) -> void:
	if opened and not _opened:
		_open_tick = tick
		# the owner-supplied open cue, once per open (beacon_audio.gd; the app's
		# per-tick state feed drives this transition, so the call lands here)
		if not _open_cue_played:
			if BeaconAudioScript.play_open(self) != null:
				_open_cue_played = true
	_opened = opened
	if not opened:
		_ramp = 0.0
		_open_tick = -1
		_open_cue_played = false
		_blocked = false
		_slow_door_ticks = -1
		for b in _body:
			b.material_override = null
		if _column != null:
			_column.visible = false
		if _shock != null:
			_shock.visible = false
		if _slow_door != null:
			_slow_door.visible = false


## The tick the beacon opened on (-1 when it is closed or has no tick clock).
func open_tick() -> int:
	return _open_tick


## The tick-driven sync (section 2.3): the ramp and the pulse are functions of
## the sim tick, so the column is visible on the open tick itself.
func sync_tick(tick: int) -> void:
	_tick = tick
	if not _opened:
		return
	if _open_tick >= 0:
		# the ramp starts at 1/36 on the open tick (D-T085-3): "appears on the tick"
		_ramp = clampf(float(tick - _open_tick + 1) / float(OPEN_TICKS), 0.0, 1.0)
	_apply(_pulse_at(tick))


## The frame-driven path (no tick clock): the ramp advances with delta.
func _process(delta: float) -> void:
	if not _opened or _open_tick >= 0:
		return
	if _ramp < 1.0:
		_ramp = minf(_ramp + delta / OPEN_RAMP, 1.0)
	_apply(0.95 + 0.05 * sin(Time.get_ticks_msec() * 0.001 * TAU * PULSE_HZ))


## The 0.9 -> 1.0 pulse at 0.5 Hz, as a function of the sim tick.
static func _pulse_at(tick: int) -> float:
	return 0.95 + 0.05 * sin(float(tick) / 60.0 * TAU * PULSE_HZ)


## Applies the current ramp + pulse to the body, the column, the shock ring and
## the Slow Door ring.
func _apply(pulse: float) -> void:
	var energy := EMISSION_MAX * _ramp * pulse
	if _open_mat == null:
		_open_mat = _open_material()
	_open_mat.emission_energy_multiplier = energy
	_open_mat.albedo_color = DANGER_RED if _blocked else OPEN_COLOR
	for b in _body:
		b.material_override = _open_mat
	if _column != null:
		_column.visible = _ramp > 0.0
		_column.scale.y = maxf(_ramp, 0.001)
		_column.position.y = COLUMN_HEIGHT * 0.5 * _ramp
		var cm: StandardMaterial3D = _column.material_override
		cm.albedo_color = Color(DANGER_RED.r, DANGER_RED.g, DANGER_RED.b, COLUMN_ALPHA) if _blocked \
			else Color(OPEN_COLOR.r, OPEN_COLOR.g, OPEN_COLOR.b, COLUMN_ALPHA)
	if _shock != null:
		# the shock ring crosses the hub over the same 36 ticks, then hides
		var s: float = _ramp * RING_HALF
		_shock.visible = _ramp > 0.0 and _ramp < 1.0
		_shock.scale = Vector3(maxf(s, 0.001), 1.0, maxf(s, 0.001))
	if _slow_door != null:
		# the Slow Door ring fills from the axis out to the trigger radius
		var f: float = 0.0
		if _slow_door_ticks >= 0:
			f = clampf(float(_slow_door_ticks) / float(SLOW_DOOR_TICKS), 0.0, 1.0)
		_slow_door.visible = _slow_door_ticks >= 0
		_slow_door.scale = Vector3(maxf(f * TRIGGER_RADIUS, 0.001), 1.0,
			maxf(f * TRIGGER_RADIUS, 0.001))


## Blocked (Crowded Dais / Slow Door): the column turns danger red while entry
## is refused. slow_door_ticks: ticks elapsed since the refusal (-1: not refused).
func set_blocked(blocked: bool, slow_door_ticks: int = -1) -> void:
	_blocked = blocked
	_slow_door_ticks = slow_door_ticks if blocked else -1
	if _opened:
		_apply(_pulse_at(_tick))


## The column's current height in u (0 when it is not showing).
func column_height() -> float:
	if _column == null or not _column.visible:
		return 0.0
	return COLUMN_HEIGHT * _column.scale.y


func column_visible() -> bool:
	return _column != null and _column.visible


func column_alpha() -> float:
	if _column == null:
		return 0.0
	return (_column.material_override as StandardMaterial3D).albedo_color.a


func column_color() -> Color:
	if _column == null:
		return Color(0, 0, 0, 0)
	return (_column.material_override as StandardMaterial3D).albedo_color


func shock_ring_visible() -> bool:
	return _shock != null and _shock.visible


func slow_door_visible() -> bool:
	return _slow_door != null and _slow_door.visible


func slow_door_fill() -> float:
	if _slow_door == null:
		return 0.0
	return _slow_door.scale.x / TRIGGER_RADIUS


static func _open_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = OPEN_COLOR
	m.emission_enabled = true
	m.emission = OPEN_COLOR
	return m


## Convenience: sync straight from the sim's beacon state + gift state. tick: the
## sim tick to sync on (-1: the frame path). The open tick is the tick the beacon
## state flipped, which is the tick of the last real black gift (sim/gifts.gd
## opens the beacon on the same tick it collects it).
func sync_from(beacon_state: RefCounted, gifts_state: RefCounted, tick: int = -1) -> void:
	set_open(beacon_state.is_open(), tick)
	if gifts_state != null and not beacon_state.is_open():
		set_progress(gifts_state.total_real - gifts_state.remaining(), gifts_state.total_real)
	if tick >= 0:
		sync_tick(tick)
