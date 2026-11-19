# Barrier + sync_body test (headless): the two small sim fixes this wave owns in
# sim/controller.gd.
#
# Fix 1 (FULL_GAME_PLAN gap 27): the barrier_shields stat (upgrade subspacial_barrier)
# is no longer dropped. apply_stats reads it; the FIRST call after setup() is the
# level-start grant; try_kill consumes one shield per TRIPMINE hit (code D-MINE,
# i.e. after the defuse roll in sim/mines.gd), before Last Light and before death;
# beacon_enter restores the budget. The nuke is never absorbed [CANON]. Negative
# control, built into fix 1 below: a stats dict at 0 (no stat at all) absorbs nothing.
#
# Fix 2 (PARKED row 27, the player's half): every teleport path in the controller -
# place(), the void-fall respawn landing, and the Last Light dais save - calls
# sync_body() AFTER the position is written, so the owner's collision body
# (sync_body_hook) never resolves the first tick after a teleport against the old
# position. The negative control is applied by REVERTING the three sync_body() calls
# in controller.gd (not shipped): fix 2's assertions then fail.
#
# Nothing here touches world.gd, enemy_runtime.gd, mines.gd, gifts.gd or view/.

const Util := preload("res://tests/sim_testutil.gd")
const CollisionScript := preload("res://sim/collision.gd")
const ControllerScript := preload("res://sim/controller.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const DT := 1.0 / 60.0

func run() -> Array[String]:
	var f: Array[String] = []
	_test_barrier_shields(f)
	_test_sync_body(f)
	return f


# ---- fixtures -------------------------------------------------------------------------

## A flat world with a dais on it, the test_charges.gd shape: one tile at (0,0,0).
func _world() -> Dictionary:
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["dais"] = [0, 0, 0]
	return w


func _fresh() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	return ctl


## The stats dict world.gd computes at build for the given owned upgrades: a real
## controller's base_stats() as `base`, the owned ids' modifiers repeated per stack -
## the exact _run_modifiers() + apply_modifiers() pair (the test_stats_consumers.gd
## recipe).
static func _stats_for(stacks: Dictionary) -> Dictionary:
	var api: RefCounted = ContentApiScript.load()
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	var mods: Array = []
	var ids: Array = stacks.keys()
	ids.sort()
	for id in ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.upgrade(str(id)).get("modifiers", []), int(stacks[id])))
	return ContentApiScript.apply_modifiers(ctl.base_stats(), mods,
			{"phase": "", "class": "dasher"})


static func _kind(ev: Array, k: String) -> int:
	var n := 0
	for e in ev:
		if str(e.get("e", e.get("type", ""))) == k:
			n += 1
	return n


static func _find(ev: Array, k: String) -> Dictionary:
	for e in ev:
		if str(e.get("e", e.get("type", ""))) == k:
			return e
	return {}


static func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok

# ---- fix 1: barrier_shields actually shields ------------------------------------------

func _test_barrier_shields(f: Array[String]) -> void:
	# the shipped path: the upgrade's modifier reaches apply_modifiers' output
	var stats := _stats_for({"subspacial_barrier": 1})
	_check(f, absf(float(stats.get("barrier_shields", -1.0)) - 1.0) <= 1e-9,
			"barrier_shields: the stats dict carries %s, want 1.0" % str(stats.get("barrier_shields")))
	var base := _stats_for({})
	_check(f, not base.has("barrier_shields") or absf(float(base.get("barrier_shields", 0.0))) <= 1e-9,
			"barrier_shields: the bare stats dict carries the stat (%s)" % str(base.get("barrier_shields")))

	var w := _world()

	# WITH THE UPGRADE OWNED: the first tripmine is absorbed, before Last Light
	# and without a teleport, and the shield is consumed
	var ctl = _fresh()
	ctl.apply_stats(stats)
	_check(f, int(ctl.barrier_shields) == 1,
			"barrier_shields: apply_stats granted %d shields, want 1" % int(ctl.barrier_shields))
	var ev: Array = []
	var saved: bool = ctl.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, saved, "barrier_shields: the held shield did not absorb the tripmine")
	_check(f, not bool(ctl.dead), "barrier_shields: the absorbed hit still killed the player")
	_check(f, int(ctl.barrier_shields) == 0,
			"barrier_shields: the shield survived absorption (%d held)" % int(ctl.barrier_shields))
	_check(f, not bool(ctl.last_light_spent),
			"barrier_shields: the absorption spent Last Light - the shield sits before it")
	_check(f, int(ctl.charges) == 2,
			"barrier_shields: the absorption spent a charge (%d held)" % int(ctl.charges))
	_check(f, _kind(ev, "barrier_shield_absorbed") == 1,
			"barrier_shields: no barrier_shield_absorbed event fired")
	var absorbed := _find(ev, "barrier_shield_absorbed")
	_check(f, int(absorbed.get("shields", -1)) == 0,
			"barrier_shields: the absorbed event carries shields=%s, want 0" % str(absorbed.get("shields")))

	# the ladder holds: shield gone, the armed Last Light saves the second hit...
	ev = []
	saved = ctl.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, saved and not bool(ctl.dead) and bool(ctl.last_light_spent),
			"barrier_shields: the second hit did not fall through to Last Light")

	# ... and with Last Light spent the third hit kills (the save granted 2.0 s
	# of invulnerability, so burn it off the way the clock would)
	ctl.invuln = 0.0
	ev = []
	saved = ctl.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, not saved and bool(ctl.dead) and str(ctl.dead_code) == "D-MINE",
			"barrier_shields: the third hit did not kill (saved=%s dead=%s code=%s)"
					% [str(saved), str(ctl.dead), str(ctl.dead_code)])

	# tripmines ONLY: a nuke hit is never absorbed, even with the shield held
	var nuke = _fresh()
	nuke.apply_stats(stats)
	nuke.last_light_spent = true      # the save cannot fire
	nuke.charges = 0
	ev = []
	saved = nuke.try_kill("D-NUKE", "nuke", w, ev)
	_check(f, not saved and bool(nuke.dead),
			"barrier_shields: the nuke was absorbed - the shield is tripmines only [CANON]")
	_check(f, int(nuke.barrier_shields) == 1,
			"barrier_shields: the nuke consumed the shield (%d held)" % int(nuke.barrier_shields))

	# invulnerability suppresses WITHOUT consuming the shield
	var inv = _fresh()
	inv.apply_stats(stats)
	inv.invuln = 1.0
	ev = []
	saved = inv.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, not saved and int(inv.barrier_shields) == 1 and _kind(ev, "kill_suppressed") == 1,
			"barrier_shields: an invulnerable hit consumed the shield")

	# THE GOLD EDGE DOES NOT REFILL A SPENT SHIELD: re-applying the same stats
	# dict (what _apply_phase_stats does) clamps, never re-grants
	var edge = _fresh()
	edge.apply_stats(stats)
	ev = []
	edge.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, int(edge.barrier_shields) == 0, "barrier_shields: the shield was not consumed")
	edge.apply_stats(stats)
	_check(f, int(edge.barrier_shields) == 0,
			"barrier_shields: the gold-phase edge refilled a spent shield")

	# beacon entry restores the budget ("restored on beacon entry")
	edge.beacon_enter()
	_check(f, int(edge.barrier_shields) == 1,
			"barrier_shields: beacon entry restored %d, want 1" % int(edge.barrier_shields))

	# NEGATIVE CONTROL: the stat at 0 (a dict without it) absorbs nothing and the
	# mine kills, with nothing able to save the player
	var none = _fresh()
	none.apply_stats({"run_speed": 1.0})
	_check(f, int(none.barrier_shields) == 0,
			"barrier_shields: a dict without the stat granted a shield")
	none.charges = 0
	none.last_light_spent = true
	ev = []
	saved = none.try_kill("D-MINE", "tripmine", w, ev)
	_check(f, not saved and bool(none.dead) and str(none.dead_code) == "D-MINE",
			"barrier_shields: with the stat at 0 the mine did not kill")

# ---- fix 2: sync_body on every teleport path ------------------------------------------

func _test_sync_body(f: Array[String]) -> void:
	var w := _world()

	# place(): the hook fires AFTER the body lands on the dais tile
	var a = _fresh()
	var seen: Array = []
	var holder := [a]
	a.sync_body_hook = func(): seen.append(Vector3(holder[0].x, holder[0].y, holder[0].z))
	a.place(w)
	_check(f, seen.size() == 1,
			"sync_body: place() fired the hook %d times, want 1" % seen.size())
	if seen.size() == 1:
		var p: Vector3 = seen[0]
		_check(f, p.is_equal_approx(Vector3(0.5, 0.0, 0.5)),
				"sync_body: place() fired the hook at (%.2f, %.2f, %.2f), want the dais tile" % [p.x, p.y, p.z])

	# the void-fall respawn landing: the hook fires after the teleport to the safe
	# tile (the dais fallback here: the ring is empty)
	var b = _fresh()
	b.place(w)
	seen = []
	holder = [b]
	b.sync_body_hook = func(): seen.append(Vector3(holder[0].x, holder[0].y, holder[0].z))
	b.charges = 2
	b.y = -100.0   # past kill_plane_y: the fall happens on this tick
	b.step(DT, Util.mk_in(), w)
	var respawned := false
	for _i in range(400):
		for e in b.step(DT, Util.mk_in(), w):
			if str(e.get("e", "")) == "respawn":
				respawned = true
				break
		if respawned:
			break
	_check(f, respawned, "sync_body: no respawn event inside 400 ticks")
	_check(f, seen.size() == 1,
			"sync_body: the respawn fired the hook %d times, want 1" % seen.size())
	if seen.size() == 1:
		var p2: Vector3 = seen[0]
		_check(f, p2.is_equal_approx(Vector3(0.5, 0.0, 0.5)),
				"sync_body: the hook fired at (%.2f, %.2f, %.2f) - the pre-teleport position, want the dais" % [p2.x, p2.y, p2.z])

	# the Last Light dais save: the hook fires after the teleport, before the
	# enemy push; a non-mine code so the barrier never enters the path
	var c = _fresh()
	c.place(w)
	seen = []
	holder = [c]
	c.sync_body_hook = func(): seen.append(Vector3(holder[0].x, holder[0].y, holder[0].z))
	c.charges = 2
	c.x = 30.5
	var ev: Array = []
	var saved: bool = c.try_kill("D-CLAUDE", "claude", w, ev)
	_check(f, saved and not bool(c.dead), "sync_body: the armed save did not fire")
	_check(f, seen.size() == 1,
			"sync_body: the Last Light save fired the hook %d times, want 1" % seen.size())
	if seen.size() == 1:
		var p3: Vector3 = seen[0]
		_check(f, p3.is_equal_approx(Vector3(0.5, 0.0, 0.5)),
				"sync_body: the hook fired at (%.2f, %.2f, %.2f) - the pre-teleport position, want the dais" % [p3.x, p3.y, p3.z])
	_check(f, bool(c.last_light_spent), "sync_body: Last Light was not spent by the save")

	# no hook set: every teleport path is a no-op for the sync call (and safe)
	var d = _fresh()
	d.place(w)
	d.charges = 2
	d.y = -100.0
	d.step(DT, Util.mk_in(), w)
	for _i in range(400):
		var done := false
		for e in d.step(DT, Util.mk_in(), w):
			if str(e.get("e", "")) == "respawn":
				done = true
				break
		if done:
			break
	_check(f, bool(d.grounded), "sync_body: a respawn with no hook hung airborne")
