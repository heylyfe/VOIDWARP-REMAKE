#
# coil telegraph VFX (ticket T-031). View layer only: reads sim telegraph events and
# renders, never writes sim state. Two pieces, both wired to the T-083 anim block:
#
#   1. The landing ring - a translucent flat disc of radius 3 u in danger red (#FF2A2A),
#      drawn on the landing tile's top plane for every live "coil_ring" telegraph
#      (the T-083 anim block: telegraph effect red_ring, visible for the whole cue and
#      the flight; DESIGN.md §5.2: a ring of radius 3 u drawn at the landing zone).
#   2. The landing shockwave - the T-083 attack_landing effect: shown on the landing
#      tick, expanding to radius 6 u over the following 12 ticks, then fading out by
#      tick 18 (DESIGN.md §5.2: landing shockwave, radius 6 u, non-killing).
#
# The caller (the future enemy-anim pass, or any scene driving it) calls sync() with the
# runtime's live telegraph list every tick to maintain the rings, and impact() when the
# coil_land event arrives; both are steps of the fixed 60 Hz tick, never wall-clock.
# Unshaded, fog-exempt, additive - the ring must read across the level (BILLBOARDING
# hard rule cousin: the tell is the answer, fog must never eat it).

extends Node3D

const RING_COLOR := Color(1.0, 0.168, 0.168)      # #FF2A2A
const RING_RADIUS := 3.0
const SHOCKWAVE_RADIUS := 6.0
const SHOCKWAVE_EXPAND_TICKS := 12
const SHOCKWAVE_FADE_TICKS := 18
const DISC_HEIGHT := 0.04

var _rings := {}        # telegraph key -> MeshInstance3D (the landing ring)
var _shocks: Array = [] # [{"mesh": MeshInstance3D, "t": ticks, "x": fx, "z": fz}]

func _ready() -> void:
	_rings = {}
	_shocks = []


## Syncs the live-ring set against the runtime's telegraph list. Call once per tick with
## the same list object the runtime holds (entries are read, never written). dt_ticks is
## the 60 Hz tick delta (1 at 60 Hz).
func sync(telegraphs: Array, dt_ticks: int = 1) -> void:
	var wanted := {}
	for t in telegraphs:
		var kind := str(t.get("kind", ""))
		if kind != "coil_ring":
			continue
		if int(t.get("ticks", 0)) <= 0:
			continue
		var shape: Dictionary = t.get("shape", {})
		# the telegraph shape carries the landing plane y as y0 (D-T-031-5)
		var y: float = float(shape.get("y0", 0.0)) + DISC_HEIGHT
		var key := "%s,%s,%s" % [str(shape.get("cx", 0.0)), str(shape.get("cz", 0.0)), str(y)]
		wanted[key] = {"x": float(shape.get("cx", 0.0)), "z": float(shape.get("cz", 0.0)),
				"y": y}
	# remove rings whose telegraph expired (the strike landed)
	for key in _rings.keys():
		if not wanted.has(key):
			_rings[key].queue_free()
			_rings.erase(key)
	# add rings that appeared
	for key in wanted.keys():
		if _rings.has(key):
			continue
		var p: Dictionary = wanted[key]
		var mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = RING_RADIUS
		disc.bottom_radius = RING_RADIUS
		disc.height = DISC_HEIGHT
		disc.radial_segments = 48
		disc.rings = 1
		mi.mesh = disc
		mi.material_override = _material(RING_COLOR, 0.45)
		mi.position = Vector3(p["x"], p["y"], p["z"])
		add_child(mi)
		_rings[key] = mi
	# advance the shockwaves
	var keep: Array = []
	for s in _shocks:
		s["t"] = int(s["t"]) + dt_ticks
		_advance_shock(s)
		if int(s["t"]) < SHOCKWAVE_FADE_TICKS:
			keep.append(s)
		else:
			var m: MeshInstance3D = s["mesh"]
			m.queue_free()
	_shocks = keep


## Spawns one expanding shockwave at the landing point (the coil_land event's position).
func impact(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = DISC_HEIGHT
	disc.radial_segments = 48
	disc.rings = 1
	mi.mesh = disc
	mi.material_override = _material(RING_COLOR, 0.7)
	mi.position = Vector3(pos.x, pos.y + DISC_HEIGHT, pos.z)
	add_child(mi)
	_shocks.append({"mesh": mi, "t": 0})


func ring_count() -> int:
	return _rings.size()


func shock_count() -> int:
	return _shocks.size()


func _advance_shock(s: Dictionary) -> void:
	var t: int = int(s["t"])
	var f: float = clampf(float(t) / float(SHOCKWAVE_EXPAND_TICKS), 0.0, 1.0)
	var r: float = lerpf(1.0, SHOCKWAVE_RADIUS, f)
	var mi: MeshInstance3D = s["mesh"]
	mi.scale = Vector3(r, 1.0, r)
	# fade out over the final 6 ticks of the 18-tick window
	if t > SHOCKWAVE_EXPAND_TICKS:
		var fade: float = 1.0 - float(t - SHOCKWAVE_EXPAND_TICKS) / float(SHOCKWAVE_FADE_TICKS - SHOCKWAVE_EXPAND_TICKS)
		var mat: StandardMaterial3D = mi.material_override
		var c: Color = mat.albedo_color
		c.a = 0.7 * clampf(fade, 0.0, 1.0)
		mat.albedo_color = c


static func _material(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.disable_fog = true
	m.disable_receive_shadows = true
	return m