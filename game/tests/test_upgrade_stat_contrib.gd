extends RefCounted
#
# PER-UPGRADE STAT CONTRIBUTION test (headless) - B5A.
#
# The shape this proves: a script upgrade may declare a stat contribution of its own
# (static stat_mods(kit) -> Array of modifier dicts, ONE stack's worth), and the world merges
# it into the modifier list the stat pipeline applies. So a script upgrade can add to
# run_speed the same way a JSON modifier does - no special case in the module, no content id
# in app/, and run_speed stays the pipeline's to own.
#
# Proven through the SHIPPED path, never the sim alone: every leg builds a real world with
# world.build(), drives it with world.step(), and reads the controller's own run_speed().
# This project has been bitten three times by tests that proved the sim and not the game
# (RUNLOG 18:34Z, 18:48Z), so a leg that only called the module would prove nothing. The
# steps matter for a second reason: world.step() runs _upgrade_speed_pass, which rewrites
# run_speed_mul from the phase stats whenever a boost is live, so a value read at build time
# would not prove the contribution survives the tick.
#
# Legs:
#   athletic_speed  quick_recovery on the athletic class: 1 stack = +5% run speed, 2 stacks
#                   = +10%, against the same build with 0 stacks (the negative control).
#                   Checked at three layers - the pipeline's own run_speed stat, the
#                   controller's live run_speed_mul, and the speed the body moves at - so a
#                   contribution that stops at one of them is caught.
#   other_classes   the same upgrade on dasher and glider moves run speed by nothing: their
#                   half of the rule sentence is the cooldown knob, so the contribution is
#                   class-scoped rather than global.

const WorldScript := preload("res://app/world.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0
const PURSE := 500
const STEPS := 30


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_athletic_speed(f)
	_leg_other_classes(f)
	print("STAT CONTRIBUTION legs complete, failures=%d" % f.size())
	return f


# ---- shared helpers ------------------------------------------------------------------------

func _build(stacks: Dictionary, p_class: String):
	var world = WorldScript.new()
	var ledger := {
		"class": p_class, "votes": {}, "curses": {}, "stacks": stacks.duplicate(),
		"purse": PURSE, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok


## Steps the world through the shipped tick, then returns the controller's own run speed.
func _stepped_run_speed(world, n: int = STEPS) -> float:
	for _i in n:
		world.step(DT)
	return float(world.ctl.run_speed(world.w))


# ---- athletic_speed: +5% per stack, through the stat pipeline ------------------------------

func _leg_athletic_speed(f: Array[String]) -> void:
	var base = _build({}, "athletic")
	var one = _build({"quick_recovery": 1}, "athletic")
	var two = _build({"quick_recovery": 2}, "athletic")
	if base == null or one == null or two == null:
		_check(f, false, "athletic_speed: a world failed to build")
		_drop(base)
		_drop(one)
		_drop(two)
		return
	var r0 := _stepped_run_speed(base)
	var r1 := _stepped_run_speed(one)
	var r2 := _stepped_run_speed(two)
	_check(f, r0 > 0.0, "athletic_speed: the 0-stack run speed reads %.4f" % r0)
	# layer 1: the pipeline's own stat, after the world merged the module's contribution
	var s1 := float(one._stats_black.get("run_speed", 0.0))
	var s2 := float(two._stats_black.get("run_speed", 0.0))
	_check(f, is_equal_approx(s1, 1.05),
		"athletic_speed: 1 stack left the pipeline's run_speed at %.4f, want 1.05" % s1)
	_check(f, is_equal_approx(s2, 1.10),
		"athletic_speed: 2 stacks left the pipeline's run_speed at %.4f, want 1.10" % s2)
	# layer 2: apply_stats made it live on the controller
	_check(f, is_equal_approx(float(one.ctl.run_speed_mul), 1.05),
		"athletic_speed: 1 stack left the controller's run_speed_mul at %.4f, want 1.05"
			% float(one.ctl.run_speed_mul))
	_check(f, is_equal_approx(float(two.ctl.run_speed_mul), 1.10),
		"athletic_speed: 2 stacks left the controller's run_speed_mul at %.4f, want 1.10"
			% float(two.ctl.run_speed_mul))
	# layer 3: the speed the body actually moves at, against the 0-stack world
	_check(f, is_equal_approx(r1 / r0, 1.05),
		"athletic_speed: 1 stack moved the controller's run speed %.4f -> %.4f (x%.4f), want x1.05"
			% [r0, r1, r1 / r0])
	_check(f, is_equal_approx(r2 / r0, 1.10),
		"athletic_speed: 2 stacks moved the controller's run speed %.4f -> %.4f (x%.4f), want x1.10"
			% [r0, r2, r2 / r0])
	_drop(base)
	_drop(one)
	_drop(two)


# ---- other_classes: the contribution is class-scoped, not global ---------------------------

func _leg_other_classes(f: Array[String]) -> void:
	for kit in ["dasher", "glider"]:
		var base = _build({}, kit)
		var two = _build({"quick_recovery": 2}, kit)
		if base == null or two == null:
			_check(f, false, "other_classes: a %s world failed to build" % kit)
			_drop(base)
			_drop(two)
			continue
		var r0 := _stepped_run_speed(base)
		var r2 := _stepped_run_speed(two)
		_check(f, is_equal_approx(r2, r0),
			"other_classes: %s run speed moved %.4f -> %.4f at 2 stacks; the Athletic half must not reach it"
				% [kit, r0, r2])
		# the half that DOES apply to these classes still lands: the cooldown knob
		_check(f, is_equal_approx(float(base.ctl.cooldown_mul), 1.0),
			"other_classes: %s cooldown_mul reads %.4f un-owned, want 1.0"
				% [kit, float(base.ctl.cooldown_mul)])
		_check(f, is_equal_approx(float(two.ctl.cooldown_mul), 0.6),
			"other_classes: %s cooldown_mul reads %.4f at 2 stacks, want 0.6"
				% [kit, float(two.ctl.cooldown_mul)])
		_drop(base)
		_drop(two)
