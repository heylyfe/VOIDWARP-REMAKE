# gap 10 (FULL_GAME_PLAN.md): gift Larper and nuke spawned inert bodies - the
# Larper gift and the nuke showed a sprite that never animated or reacted, so
# the player saw a dead prop. T-020-era gift bodies and the nuke projectile
# body were exactly that.
#
# The gifts (view/gifts_view.gd): both the black and the gold gift now turn one
# revolution per 4.0 s - the tripmine turn (DESIGN.md section 3.3, the T-021
# TURN_PERIOD) - phase-offset per build order so neighbours do not spin in
# lockstep. A Larper fake gift IS a gift (section 3.3,
# the lie), so real gifts must turn or motion itself gives the Larper away.
# Which body shows (black vs gold, uncollected vs collected, never on an
# occ == 1 slot) keeps following the sim gift state.
#
# The nuke missile (view/vfx/projectile_view.gd): the body length breathes
# through the spec own booster-flame cycle - the four flame lengths 20 / 26 /
# 22 / 30 percent at 12 fps, in the art frame order (tools/sprite_pipeline.gd
# NUKE_PCTS; the anim block 5 ticks per frame) - so the falling missile is a
# live body, not a stretched sphere. The gather() state gate (the missile only
# exists while its sim row is in the lock/descent phase) is unchanged.
#
# PROOF: both bodies transforms change between two sim times (idle motion),
# and the shown gift flips with the sim black -> gold phase flip (state
# reaction). NEGATIVE CONTROL: re-synced at the same sim time with the state
# unchanged, each body holds its exact transform and the same body shows.

const GiftsViewScript := preload("res://view/gifts_view.gd")
const ProjectileViewScript := preload("res://view/vfx/projectile_view.gd")
const LevelStateScript := preload("res://sim/level_state.gd")

const TAU_F := 6.283185307179586
const TURN_PERIOD := 4.0   # DESIGN.md section 3.3, the T-021 binding turn
const MISSILE_LEN := 1.6   # the missile body base length (view constant)

func run() -> Array[String]:
	var f: Array[String] = []
	_test_gift_turn(f)
	_test_gift_state_reaction(f)
	_test_nuke_flame(f)
	_test_nuke_state_gate(f)
	return f

## A minimal synthetic level: one 1x1 tile per gift slot, all at y 0. The dict
## carries every field the sim state build reads.
static func _synthetic(occs: Array) -> Dictionary:
	var gifts: Array = []
	var tiles: Array = []
	for i in occs.size():
		var z: int = i * 3
		gifts.append({"id": i, "x": 3, "z": z, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
		tiles.append([3, z, 0, 0, 0])
	return {
		"gen_version": 0, "seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": [0, 0, 1], "spawns": [[0, 0, 1]], "arms": [], "pieces": [],
		"tiles": tiles, "props": [], "edges": [], "gifts": gifts, "anchors": [], "pads": [],
	}


static func _setup_gifts(occs: Array) -> Dictionary:
	var level := _synthetic(occs)
	var lv: RefCounted = LevelStateScript.build(level, 1, 1)
	var v = GiftsViewScript.new()
	v.setup(level, lv.gifts)
	return {"view": v, "level": level, "lv": lv}


## Idle motion: the real gift bodies turn with sim time (4.0 s per rev), and the
## phase offset keeps neighbours out of lockstep. Negative control: the same
## state re-synced at the same sim time holds the exact transform.
func _test_gift_turn(f: Array[String]) -> void:
	var occs: Array = [0, 1, 0]
	var s := _setup_gifts(occs)
	var v = s["view"]
	var lv: RefCounted = s["lv"]
	var b0 = v._black[0]
	var b2 = v._black[2]
	if b0 == null or b2 == null:
		f.append("turn: a real gift slot got no body")
		v.free()
		return
	v.sync(lv.gifts, 1.0)
	var r0_t1: float = (v._black[0] as Node3D).rotation.y
	var r2_t1: float = (v._black[2] as Node3D).rotation.y
	v.sync(lv.gifts, 2.0)
	var r0_t2: float = (v._black[0] as Node3D).rotation.y
	var r2_t2: float = (v._black[2] as Node3D).rotation.y
	var want0_t1: float = 1.0 * TAU_F / TURN_PERIOD
	var want0_t2: float = 2.0 * TAU_F / TURN_PERIOD
	if absf(r0_t1 - want0_t1) > 0.001:
		f.append("turn: slot 0 rotates %s at t=1.0, want %s" % [str(r0_t1), str(want0_t1)])
	if absf(r0_t2 - want0_t2) > 0.001:
		f.append("turn: slot 0 rotates %s at t=2.0, want %s" % [str(r0_t2), str(want0_t2)])
	if absf(r0_t2 - r0_t1) <= 0.01:
		f.append("turn: the gift body does not move with sim time (%s -> %s)" % [str(r0_t1), str(r0_t2)])
	if absf(r2_t1 - r0_t1) <= 0.01:
		f.append("turn: neighbouring gifts spin in lockstep (%s vs %s)" % [str(r0_t1), str(r2_t1)])
	# the gold bodies turn too (the same box, the same lie)
	v.sync(lv.gifts, 3.0)
	var g0: float = (v._gold[0] as Node3D).rotation.y
	if absf(g0 - (3.0 * TAU_F / TURN_PERIOD)) > 0.001:
		f.append("turn: the gold gift body does not turn with sim time (%s)" % str(g0))
	# NEGATIVE CONTROL: unchanged state, unchanged time -> no movement
	v.sync(lv.gifts, 1.0)
	var nc0: float = (v._black[0] as Node3D).rotation.y
	v.sync(lv.gifts, 1.0)
	var nc1: float = (v._black[0] as Node3D).rotation.y
	if nc0 != nc1:
		f.append("turn: NEGATIVE CONTROL failed - same state, same time, body moved (%s -> %s)" % [str(nc0), str(nc1)])
	v.free()

## State reaction: the shown body follows the sim gift state across the black
## -> gold phase flip; uncollected real slots show, collected slots hide, and
## an occ == 1 slot never shows a body (existing sync behaviour, re-asserted).
func _test_gift_state_reaction(f: Array[String]) -> void:
	var occs: Array = [0, 0, 1]
	var s := _setup_gifts(occs)
	var v = s["view"]
	var lv: RefCounted = s["lv"]
	v.sync(lv.gifts, 1.0)
	if not (v._black[0] as Node3D).visible or not (v._black[1] as Node3D).visible:
		f.append("state: black gifts of real uncollected slots are not shown")
	if (v._black[2] as Node3D) != null or (v._gold[2] as Node3D) != null:
		f.append("state: an occ == 1 slot got a gift body")
	if (v._gold[0] as Node3D).visible:
		f.append("state: the gold gift shows during the black phase")
	# collect every real black gift -> the phase flips to gold on this very tick
	var events: Array = []
	lv.gifts.collect(0, 1, 0, events)
	lv.gifts.collect(1, 1, 0, events)
	v.sync(lv.gifts, 2.0)
	if str(lv.gifts.phase) != "gold":
		f.append("state: the phase did not flip to gold after the last real black gift")
	if (v._black[0] as Node3D).visible or (v._black[1] as Node3D).visible:
		f.append("state: a collected black gift still shows")
	if not (v._gold[0] as Node3D).visible or not (v._gold[1] as Node3D).visible:
		f.append("state: the gold gifts did not flip in on the phase flip")
	# NEGATIVE CONTROL: unchanged state (gold phase), unchanged time -> same shown body
	var g0_before: bool = (v._gold[0] as Node3D).visible
	var r_before: float = (v._gold[0] as Node3D).rotation.y
	v.sync(lv.gifts, 2.0)
	if (v._gold[0] as Node3D).visible != g0_before:
		f.append("state: NEGATIVE CONTROL failed - same state, same time, visibility flipped")
	if (v._gold[0] as Node3D).rotation.y != r_before:
		f.append("state: NEGATIVE CONTROL failed - same state, same time, gold body moved")
	v.free()


## Idle motion: the missile body length follows the spec booster-flame cycle
## (20/26/22/30 %, 12 fps). Negative control: same points, same sim time -> the
## exact same scale.
func _test_nuke_flame(f: Array[String]) -> void:
	var v = ProjectileViewScript.new()
	var pts: Array = [{"x": 5.0, "y": 24.0, "z": 5.0, "r": 0.4, "kind": "missile"}]
	v.sync(pts, 0.0)
	var mi = v.get_child(0) as MeshInstance3D
	if mi == null:
		f.append("flame: no missile body pooled")
		v.free()
		return
	var len0: float = mi.scale.y
	v.sync(pts, 0.25)   # 3 flame frames on: 0 -> 0.20, 3 -> 0.30 (t * 12 fps)
	var len1: float = mi.scale.y
	if absf(len0 - MISSILE_LEN * 1.20) > 0.001:
		f.append("flame: missile length %s at frame 0, want %s" % [str(len0), str(MISSILE_LEN * 1.20)])
	if absf(len1 - MISSILE_LEN * 1.30) > 0.001:
		f.append("flame: missile length %s at frame 3, want %s" % [str(len1), str(MISSILE_LEN * 1.30)])
	if absf(len1 - len0) <= 0.001:
		f.append("flame: the missile body does not breathe with sim time (%s)" % str(len0))
	v.sync(pts, 0.5)    # frame 6 % 4 == 2 -> 0.22
	var len2: float = mi.scale.y
	if absf(len2 - MISSILE_LEN * 1.22) > 0.001:
		f.append("flame: missile length %s at frame 6, want %s" % [str(len2), str(MISSILE_LEN * 1.22)])
	# NEGATIVE CONTROL: unchanged state, unchanged time -> identical scale
	v.sync(pts, 0.0)
	var nc0: float = mi.scale.y
	v.sync(pts, 0.0)
	var nc1: float = mi.scale.y
	if nc0 != nc1:
		f.append("flame: NEGATIVE CONTROL failed - same state, same time, body rescaled (%s -> %s)" % [str(nc0), str(nc1)])
	v.free()

## State reaction: the missile body exists only while the sim rows carry a
## descent point (gather() gates on the lock/descent phase) - with no point the
## pooled body is hidden; when the point returns, the same pooled body shows.
func _test_nuke_state_gate(f: Array[String]) -> void:
	var v = ProjectileViewScript.new()
	var pts: Array = [{"x": 60.5, "y": 29.0, "z": 2.5, "r": 0.4, "kind": "missile"}]
	var shown_with: int = v.sync(pts, 1.0)
	var mi = v.get_child(0) as MeshInstance3D
	if shown_with != 1 or mi == null or not mi.visible:
		f.append("gate: the missile body did not show for a descent point")
		v.free()
		return
	var shown_without: int = v.sync([], 2.0)
	if shown_without != 0:
		f.append("gate: gather with no descent point showed %d bodies" % shown_without)
	if mi.visible:
		f.append("gate: the missile body still shows with no descent point (state unchanged)")
	var shown_again: int = v.sync(pts, 3.0)
	if shown_again != 1 or not mi.visible:
		f.append("gate: the missile body did not return when the descent point returned")
	# NEGATIVE CONTROL: empty state at the same time, re-synced -> still nothing shown
	v.sync([], 4.0)
	var hidden_a: bool = mi.visible
	v.sync([], 4.0)
	var hidden_b: bool = mi.visible
	if hidden_a != hidden_b:
		f.append("gate: NEGATIVE CONTROL failed - same empty state, same time, visibility flipped")
	v.free()
