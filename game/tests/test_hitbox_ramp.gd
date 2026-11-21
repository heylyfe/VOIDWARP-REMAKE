extends RefCounted
#
# test_hitbox_ramp.gd - cycle 4 item 13: the pickup volume must not jitter on ramps or
# stairs, and must not depend on the walk animation.
#
# Root cause (measured): NOT the animation. The pickup point is ctl.y + BODY_CENTER, read
# straight from the controller; the pose pass only writes limb nodes. The jitter was the
# collision's snap-down being dead code: a standing body always reaches move_body with
# dy = -g x dt (0.0089 u), never dy == 0, so a descent steeper than one tick of gravity
# (a ramp at run speed: 0.075 u/tick; a 1 HU tread: 0.5 u) left the ground. The body hopped
# down every ramp and stair - grounded flickering (which also flipped the pose to jump/fall)
# and the volume bobbing 0.0-0.28 u over the slope. Fixed in sim/collision.gd move_body.
#
# Legs:
#   1. walk ramp chains of all four kinds (1-4) up AND down, plus a 1 HU step staircase:
#      the body stays grounded every tick, its height never reverses direction, and over
#      the ramp interior the pickup point's height over the ramp surface is constant
#      (amplitude < JITTER_EPS);
#   2. a gift on the walk path is actually collected (sim/gifts.gd tick, the real radius);
#   3. the same walk through a REAL world build with the pose pass running, started at four
#      different animation phases: the pickup trace is bit-identical, while the limb pose
#      DOES differ (non-vacuous) and a volume read off the animated figure would differ
#      (the in-test negative control: the prime-suspect design fails this leg).

const Util := preload("res://tests/sim_testutil.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const WorldScript := preload("res://app/world.gd")
const EventsScript := preload("res://sim/events.gd")

## Allowed vertical jitter of the pickup point over the ramp surface (u).
const JITTER_EPS := 0.001
## Allowed reversal of the walk's height direction per tick (u): float noise only.
const REVERSE_EPS := 1e-6
const RAMP_N := 4


class StubLevel:
	extends RefCounted
	var players: Array = [{"x": 0.0, "y": 0.0, "z": 0.0}]
	var gifts: RefCounted = null
	var tick: int = 0
	var beacon: RefCounted = null


# ---- geometry --------------------------------------------------------------------------

## Ramp kind k (1-4) -> [axis (0 = x, 1 = z), sign of the ascending direction].
static func _axis(kind: int) -> Array:
	var d := kind - 1
	return [0 if (d == 0 or d == 2) else 1, 1 if d < 2 else -1]


## Cell (along-axis a, lateral l) -> [x, z].
static func _cell(ax: int, a: int, l: int) -> Array:
	return [a, l] if ax == 0 else [l, a]


## A 3-wide strip: 8 flat rows at HU 0, RAMP_N ramp rows of `kind` (row i: low edge HU i),
## 8 flat rows at HU RAMP_N. Rows are laid along the ramp's ascending direction.
static func _ramp_world(kind: int) -> Dictionary:
	var ax: int = _axis(kind)[0]
	var sg: int = _axis(kind)[1]
	var tiles: Array = []
	for l in range(-1, 2):
		for k in range(-8, RAMP_N + 8):
			var c: Array = _cell(ax, k * sg, l)
			if k < 0:
				tiles.append([c[0], c[1], 0, 0, 0])
			elif k < RAMP_N:
				tiles.append([c[0], c[1], k, kind, 0])
			else:
				tiles.append([c[0], c[1], RAMP_N, 0, 0])
	return Util.CollisionScript.make_world(tiles, [], [])


## Distance climbed along the ramp chain at along-axis coordinate a (0 at the foot).
static func _ramp_s(kind: int, a: float) -> float:
	return a if _axis(kind)[1] > 0 else 1.0 - a


## A 1 HU step staircase along +x (TERRAIN_SPEC 6.4 `step`, 1-row treads): 8 flat rows at
## HU 0, then RAMP_N treads (row i at HU i + 1), then 8 flat rows at HU RAMP_N.
static func _stair_world() -> Dictionary:
	var tiles: Array = []
	for l in range(-1, 2):
		for k in range(-8, RAMP_N + 8):
			var hu: int = 0 if k < 0 else (k + 1 if k < RAMP_N else RAMP_N)
			tiles.append([k, l, hu, 0, 0])
	return Util.CollisionScript.make_world(tiles, [], [])


static func _new_ctl(w: Dictionary, px: float, py: float, pz: float):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.x = px
	ctl.y = py
	ctl.z = pz
	# settle onto the start tile before the walk begins
	for t in 20:
		ctl.step(Util.DT, Util.mk_in(0, 0), w)
	return ctl


static func _gifts(slots: Array) -> RefCounted:
	var lv := StubLevel.new()
	var rows: Array = []
	for i in slots.size():
		rows.append({"id": i, "x": slots[i][0], "z": slots[i][1], "y": slots[i][2],
				"piece": 0, "tier": 0, "occ": 0})
	lv.gifts = GiftsScript.create({"gifts": rows})
	return lv


## Walks `ticks` ticks with input (mx, mz), running the real per-tick gift pickup after
## every controller step (the world.gd order: controller -> row mirror -> tick++ -> gifts).
## Returns {trace: [[x, pickup_y, z, grounded]...], air, reverse, collected}.
static func _walk(ctl, w: Dictionary, lv: RefCounted, mx: int, mz: int, ticks: int,
		dir: int, per_tick: Callable = Callable()) -> Dictionary:
	var trace: Array = []
	var air := 0
	var reverse := 0.0
	var prev_y: float = ctl.y
	var ev: Array = []
	for t in ticks:
		ctl.step(Util.DT, Util.mk_in(mx, mz), w)
		if per_tick.is_valid():
			per_tick.call(t)
		var p: Dictionary = lv.players[0]
		p["x"] = ctl.x
		p["y"] = ctl.y
		p["z"] = ctl.z
		lv.tick += 1
		GiftsScript.tick(lv, 0, ev)
		if not ctl.grounded:
			air += 1
		reverse = maxf(reverse, -float(dir) * (ctl.y - prev_y))
		prev_y = ctl.y
		trace.append([ctl.x, ctl.y + GiftsScript.BODY_CENTER, ctl.z, ctl.grounded])
	var got := 0
	for e in ev:
		# black pickups only: the last black one flips the slots gold in place, and the
		# gold copy of the slot the body still stands by is a second, separate pickup
		if str(e.get("type", "")) == EventsScript.EV_GIFT_COLLECTED and str(e.get("phase", "")) == "black":
			got += 1
	return {"trace": trace, "air": air, "reverse": reverse, "collected": got}


## Amplitude (max - min) of the pickup point's height over the ramp surface, over the
## samples whose whole 0.8 u footprint is on the ramp chain (s in [0.5, RAMP_N - 0.5]).
static func _ramp_amp(kind: int, trace: Array) -> Array:
	var ax: int = _axis(kind)[0]
	var lo := INF
	var hi := -INF
	var n := 0
	for row in trace:
		var s: float = _ramp_s(kind, float(row[0]) if ax == 0 else float(row[2]))
		if s < 0.5 or s > float(RAMP_N) - 0.5:
			continue
		var h: float = float(row[1]) - 0.5 * s
		lo = minf(lo, h)
		hi = maxf(hi, h)
		n += 1
	return [hi - lo if n > 0 else INF, n]


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_ramps(f)
	_leg_stairs(f)
	_leg_anim_independent(f)
	return f


## Legs 1 + 2 on the ramps: kinds 1-4, up and down, a gift on ramp row 2 and one on the
## far flat. Grounded every tick, no height reversal, constant height over the ramp.
func _leg_ramps(f: Array[String]) -> void:
	var worst := 0.0
	for kind in [1, 2, 3, 4]:
		var ax: int = _axis(kind)[0]
		var sg: int = _axis(kind)[1]
		var w := _ramp_world(kind)
		for dir in [1, -1]:
			# start 3.5 u before the chain's foot (up) or 4.5 u past its head (down)
			var s0: float = -3.5 if dir > 0 else float(RAMP_N) + 4.5
			var a0: float = s0 if sg > 0 else 1.0 - s0
			var y0: float = 0.0 if dir > 0 else float(RAMP_N) * 0.5
			var g_ramp: Array = _cell(ax, 2 * sg, 0)
			var far_k: int = RAMP_N + 2 if dir > 0 else -3
			var g_flat: Array = _cell(ax, far_k * sg, 0)
			var lv := _gifts([[g_ramp[0], g_ramp[1], 2],
					[g_flat[0], g_flat[1], RAMP_N if dir > 0 else 0]])
			var px: float = a0 if ax == 0 else 0.5
			var pz: float = 0.5 if ax == 0 else a0
			var ctl = _new_ctl(w, px, y0, pz)
			var m: int = sg * dir
			var r: Dictionary = _walk(ctl, w, lv, m if ax == 0 else 0, 0 if ax == 0 else m,
					100, dir)
			var tag := "ramp kind %d %s" % [kind, "up" if dir > 0 else "down"]
			_check_walk(f, tag, r, 2)
			var amp: Array = _ramp_amp(kind, r["trace"])
			worst = maxf(worst, float(amp[0]))
			if int(amp[1]) < 20:
				f.append("%s: only %d interior samples - the walk missed the ramp" % [tag, int(amp[1])])
			elif float(amp[0]) >= JITTER_EPS:
				f.append("%s: pickup height over the ramp jitters %.4f u (want < %.4f)" % [
						tag, float(amp[0]), JITTER_EPS])
	print("HITBOX ramp jitter amplitude (worst of 8 walks) = %.6f u" % worst)


## Shared walk assertions: grounded every tick, the height never reverses, every gift on
## the path collected.
static func _check_walk(f: Array[String], tag: String, r: Dictionary, want_gifts: int) -> void:
	if int(r["air"]) > 0:
		f.append("%s: airborne %d ticks on a walk (the body hops; want 0)" % [tag, int(r["air"])])
	if float(r["reverse"]) > REVERSE_EPS:
		f.append("%s: height reversed by %.4f u (want monotonic)" % [tag, float(r["reverse"])])
	if int(r["collected"]) != want_gifts:
		f.append("%s: collected %d of %d gifts on the path" % [tag, int(r["collected"]), want_gifts])


## Legs 1 + 2 on the 1 HU staircase, up and down: grounded every tick (the body follows
## each tread instead of hopping it), monotonic height, the tread gift collected.
func _leg_stairs(f: Array[String]) -> void:
	var w := _stair_world()
	for dir in [1, -1]:
		var x0: float = -3.5 if dir > 0 else float(RAMP_N) + 4.5
		var y0: float = 0.0 if dir > 0 else float(RAMP_N) * 0.5
		var lv := _gifts([[2, 0, 3]])
		var ctl = _new_ctl(w, x0, y0, 0.5)
		var r: Dictionary = _walk(ctl, w, lv, dir, 0, 100, dir)
		_check_walk(f, "stairs %s" % ("up" if dir > 0 else "down"), r, 1)


## Leg 3: the same down-ramp walk (kind 1, a gift on ramp row 2) through a REAL world
## build, the figure's pose pass (_player_pass -> _anim_pass) running after every
## controller step, started at four animation phases. The pickup trace must be identical
## run to run; the pose must not be (else the leg proves nothing); and a volume anchored on
## the animated figure - the left foot tip, the prime-suspect design - must differ, which
## is the in-test negative control: that design fails the identity this leg asserts.
func _leg_anim_independent(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(1, 1):
		f.append("anim leg: world failed to build level 1 seed 1")
		world.free()
		return
	var w := _ramp_world(1)
	world.w = w
	var traces: Array = []
	var poses: Array = []
	var feet: Array = []
	for phase in [0.0, 1.3, 2.6, 4.2]:
		var ctl = _new_ctl(w, float(RAMP_N) + 4.5, float(RAMP_N) * 0.5, 0.5)
		world.ctl = ctl
		world._anim_phase = phase
		world._pose = {}
		var lv := _gifts([[2, 0, 2]])
		var pose_log: Array = []
		var foot_log: Array = []
		var after_pose := func(_t: int) -> void:
			world._player_pass()
			var leg := world._limbs[4] as Node3D
			pose_log.append(leg.rotation.x)
			foot_log.append(world.player_model.position.y + leg.position.y
					+ (leg.basis * Vector3.DOWN).y * 0.8)
		var r: Dictionary = _walk(ctl, w, lv, -1, 0, 100, -1, after_pose)
		_check_walk(f, "anim leg phase %.1f" % phase, r, 1)
		traces.append(r["trace"])
		poses.append(pose_log)
		feet.append(foot_log)
	world.teardown()
	world.free()
	var pose_differs := false
	var foot_differs := false
	for i in range(1, traces.size()):
		if traces[i] != traces[0]:
			f.append("anim leg: the pickup trace at phase run %d differs from run 0 - the volume depends on the pose" % i)
		if poses[i] != poses[0]:
			pose_differs = true
		if feet[i] != feet[0]:
			foot_differs = true
	if not pose_differs:
		f.append("anim leg: the four phases produced the same pose - the leg is vacuous")
	if not foot_differs:
		f.append("anim leg: NEGATIVE CONTROL - a figure-anchored volume did not move with the pose; the identity check proves nothing")
