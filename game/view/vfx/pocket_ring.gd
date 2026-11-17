extends Node3D
#
# The Pocket Beacon's channel ring (ticket T-053, addendum R4, D-T053-3, D-T053-8):
# a ring around the player filling over exactly 180 ticks, gone the tick the
# channel cancels (the sim event pair beacon_channel_started/cancelled/teleport is
# the only source of truth - this node never starts, cancels or fills by itself).
# The fill is a torus arc: progress p in 0..1 draws an arc of RING_RADIUS u with
# p x 2 Pi radians swept, centred on the player's feet.

const PocketBeaconContent := preload("res://content/upgrades/pocket_beacon.gd")

const RING_RADIUS := 1.5
const RING_COLOR := Color(0.49, 1.0, 0.49, 0.9)   # the beacon family's pale green
const TUBE := 0.06

var _mesh: MeshInstance3D = null
var _ticks := 0
var _active := false


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = RING_RADIUS - TUBE
	tor.outer_radius = RING_RADIUS + TUBE
	_mesh.mesh = tor
	_mesh.material_override = _material(RING_COLOR)
	_mesh.visible = false
	add_child(_mesh)


## One HUD tick: p_active + the channel's ticks-held read straight from
## sim/upgrades.gd channels (the caller passes UpgradeChannels, 0 when none).
func sync(p_active: bool, ticks_held: int, x: float, y: float, z: float) -> void:
	_active = p_active
	_ticks = maxi(0, int(ticks_held))
	if _active and _mesh != null:
		_mesh.visible = true
		position = Vector3(x, y + 0.1, z)
		var p: float = clampf(float(_ticks) / float(PocketBeaconContent.CHANNEL_TICKS), 0.0, 1.0)
		_mesh.scale = Vector3(0.25 + 0.75 * p, 1.0, 0.25 + 0.75 * p)
	elif _mesh != null:
		_mesh.visible = false


func active() -> bool:
	return _active


static func _material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.35
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
