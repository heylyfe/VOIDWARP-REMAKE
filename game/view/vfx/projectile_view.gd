extends Node3D
#
# Generic projectile view (DESIGN.md section 5: projectiles kill on hit, so each one
# must be seen). View layer only: the caller hands sync() one flat list of live
# projectile points gathered from the sim each tick, and this node keeps one glowing
# body per point (pooled - no per-tick allocation once the pool is warm):
#
#   {"x","y","z","r","kind"}   kind: "ball"    the runtime's own projectiles
#                                               (rt.projectiles - isagi's balls)
#                                     "shot"    a row-owned shot (an enemy row's
#                                               "shots" list - claude's wind shots)
#                                     "missile" a row-owned falling detonation point
#                                               (a row's "det" while its phase is the
#                                               lock/descent - the nuke missile)
#
# Unshaded, emissive, fog-exempt: a projectile has to read through the fog at range.
#
# Idle motion for the missile body (FULL_GAME_PLAN.md gap 10: the nuke's body
# was an inert prop): the missile breathes through the spec's own booster-flame
# cycle - the four flame lengths 20 / 26 / 22 / 30 % at 12 fps (the T-016 art
# frames' order, #FFC83D -> #FF2A2A, 5 ticks per frame) - lengthening its body
# by that fraction. No new art, no new visual language: the flame frames ARE the
# nuke's animation. The clock is the caller's: sync() accepts an optional
# absolute time in sim seconds; when the caller supplies none, sync() advances
# its own fixed 1/60 s counter once per call - never a wall clock.

const COLORS := {
	"ball": Color(1.0, 0.95, 0.85),
	"shot": Color(0.55, 0.95, 1.0),
	"missile": Color(1.0, 0.35, 0.2),
}
const MIN_R := 0.18
const MISSILE_LEN := 1.6
## The booster-flame cycle: the fraction of the missile the flame overlays add,
## per frame, in the spec's frame order (tools/sprite_pipeline.gd NUKE_PCTS).
const FLAME_FRAC := [0.20, 0.26, 0.22, 0.30]
const FLAME_FPS := 12.0   # 5 ticks per frame (the anim block's ticks_per_frame)
const DT := 1.0 / 60.0    # the fixed sim step; the internal clock advances this per sync()

var _pool: Array = []       # MeshInstance3D, index = slot
var _shown := 0
var _mats := {}
var _time := 0.0            # sim seconds (caller-set via sync(), else advanced per sync())


## points: [{"x","y","z","r","kind"}]; returns the number shown. time_secs, when
## >= 0.0, sets the absolute sim clock for the missile's flame cycle; negative
## (the default) advances the internal fixed-step clock by one 1/60 s tick.
func sync(points: Array, time_secs: float = -1.0) -> int:
	_shown = 0
	if time_secs >= 0.0:
		_time = time_secs
	else:
		_time += DT
	for p in points:
		var kind := str(p.get("kind", "ball"))
		var mi := _slot(_shown, kind)
		var r := maxf(float(p.get("r", 0.25)), MIN_R)
		mi.position = Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
		if kind == "missile":
			# the booster-flame cycle: body length follows the spec's four flame
			# frames (20/26/22/30 %, 12 fps) - a live body, not an inert prop
			var fi: int = int(_time * FLAME_FPS) % FLAME_FRAC.size()
			mi.scale = Vector3(0.45, MISSILE_LEN * (1.0 + float(FLAME_FRAC[fi])), 0.45)
		else:
			mi.scale = Vector3(r, r, r) * 2.0
		mi.visible = true
		_shown += 1
	for i in range(_shown, _pool.size()):
		(_pool[i] as MeshInstance3D).visible = false
	return _shown


func shown_count() -> int:
	return _shown


func _slot(i: int, kind: String) -> MeshInstance3D:
	while _pool.size() <= i:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		add_child(mi)
		_pool.append(mi)
	var m: MeshInstance3D = _pool[i]
	m.material_override = _material(kind)
	return m


func _material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var c: Color = COLORS.get(kind, COLORS["ball"])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.disable_fog = true
	m.disable_receive_shadows = true
	_mats[kind] = m
	return m


## The live projectile points of one tick, from the runtime and its rows (read only).
## Data-shaped, never id-named: any row carrying a "shots" list or a descending "det"
## point is drawn the same way.
static func gather(rt) -> Array:
	var out: Array = []
	if rt == null:
		return out
	for p in rt.projectiles:
		if bool(p.get("alive", true)):
			out.append({"x": p["x"], "y": p["y"], "z": p["z"], "r": p.get("r", 0.25),
					"kind": "ball"})
	for row in rt.enemies:
		var shots = row.get("shots", null)
		if shots is Array:
			for s in shots:
				out.append({"x": s.get("x", 0.0), "y": s.get("y", 0.0), "z": s.get("z", 0.0),
						"r": 0.25, "kind": "shot"})
		var det = row.get("det", null)
		if det is Dictionary and str(row.get("phase", "")) == "lock":
			out.append({"x": det.get("x", 0.0), "y": det.get("y", 0.0), "z": det.get("z", 0.0),
					"r": 0.4, "kind": "missile"})
	return out
