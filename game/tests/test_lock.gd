extends RefCounted
#
# T-072: the ability lock (SR-6 / D-070), read per class from data/player.json
# (ability_lock.lock_effect) - "Athletic 10.35 -> 9.0 u/s when locked and 7.2 u/s on the
# glitched floor; speed upgrades count x1.0 while locked; Dasher cooldown does not tick;
# an active glide ends". The landing shockwave's landing lock is SR-6's other caller;
# the exact class numbers are SR-6's.

const Util := preload("res://tests/sim_testutil.gd")

const DT := Util.DT
const LOCK_TICKS := 120   # 2.0 s - the counter's shockwave lock window


func run() -> Array[String]:
	var f: Array[String] = []
	_stride_lock(f, 0.0)
	_stride_lock_glitched(f)
	_speed_upgrades_count_times_one(f)
	_dasher_cooldown_does_not_tick(f)
	_an_active_glide_ends(f)
	_lock_expires(f)
	return f


# A flat world + a controller standing on it.
func _placed(kit: String) -> Array:
	var ctl = Util.ControllerScript.new()
	ctl.setup(kit, Util.consts())
	var w := Util.world_from_tiles([[0, 0, 0], [1, 0, 0], [2, 0, 0]])
	ctl.place(w)
	ctl.x = 1.5
	return [ctl, w]


# Athletic, no upgrades: 10.35 u/s unlocked, 9.0 u/s when locked (the +15% suspended).
func _stride_lock(f: Array[String], extra_upg: float) -> void:
	var pair: Array = _placed("athletic")
	var ctl = pair[0]
	var w: Dictionary = pair[1]
	if absf(extra_upg) > 1e-9:
		ctl.apply_speed_upgrade(extra_upg)
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	var want_unlocked: float = 9.0 * (1.15 + extra_upg * 1.5)
	if absf(ctl.vx - want_unlocked) > 0.02:
		f.append("lock: unlocked run speed %.4f, want %.4f" % [ctl.vx, want_unlocked])
	ctl.lock_abilities(LOCK_TICKS)
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 9.0) > 0.02:
		f.append("lock: locked run speed %.4f, want 9.0 (10.35 suspended)" % ctl.vx)
	if not ctl.ability_locked(w):
		f.append("lock: ability_locked false while the lock window holds")


# On the glitched floor: 8.28 u/s unlocked (9 x 1.15 x 0.8), exactly 7.2 when locked - the
# same floor speed as the other two classes (SR-6). The toucher-style floor lock shows up
# here the way the sim sees it live: a tile key under the world's glitched map, and the
# controller's current-tile key on it.
func _stride_lock_glitched(f: Array[String]) -> void:
	var pair: Array = _placed("athletic")
	var ctl = pair[0]
	var w: Dictionary = pair[1]
	ctl.cur_key = "1,0,0"
	w["glitched"]["1,0,0"] = true
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 8.28) > 0.02:
		f.append("lock: unlocked run speed on the glitched floor %.4f, want 8.28" % ctl.vx)
	ctl.lock_abilities(LOCK_TICKS)
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 7.2) > 0.02:
		f.append("lock: locked run speed on the glitched floor %.4f, want exactly 7.2" % ctl.vx)
	# the glitched floor's own slow (x0.8) sits on top of the suspended class mult - and
	# can never stack it back (run_speed composes, never multiplies the lock in)


# A purchased speed upgrade counts x1.0 while the lock holds (its x1.5 class boost is off).
func _speed_upgrades_count_times_one(f: Array[String]) -> void:
	var pair: Array = _placed("athletic")
	var ctl = pair[0]
	var w: Dictionary = pair[1]
	ctl.apply_speed_upgrade(0.10)
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 11.70) > 0.02:
		f.append("lock: unlocked upgraded run speed %.4f, want 11.70 (x1.5)" % ctl.vx)
	ctl.lock_abilities(LOCK_TICKS)
	Util.run_ticks(ctl, w, 40, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 9.90) > 0.02:
		f.append("lock: locked upgraded run speed %.4f, want 9.90 (upgrades at x1.0)" % ctl.vx)


# Dasher: the dash cannot start and the cooldown never ticks within the window.
func _dasher_cooldown_does_not_tick(f: Array[String]) -> void:
	var pair: Array = _placed("dasher")
	var ctl = pair[0]
	var w: Dictionary = pair[1]
	# spend the dash (12 dash ticks), then lock while the dasher's 3.0 s regen is mid-run
	Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0, Util.ControllerScript.BTN_ABILITY))
	Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0))
	if ctl.dash_ready:
		f.append("lock: the dasher was ready before the window opened")
	ctl.lock_abilities(LOCK_TICKS)
	for i in range(LOCK_TICKS):
		Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0,
				Util.ControllerScript.BTN_ABILITY))
	if ctl.dash_ticks > 0:
		f.append("lock: a dash started inside the window")
	if absf(ctl.dash_cd - 2.0) > 1e-9:
		f.append("lock: dash cooldown ticked inside the window (%.4f, want 2.0)" % ctl.dash_cd)
	if ctl.dash_ready:
		f.append("lock: dash_ready true inside the window")
	# the window over, one 3.0 s regen resumes at once
	Util.run_ticks(ctl, w, int(Util.consts()["dash_regen"] * 60.0) + 2,
			func(_c, _i): return Util.mk_in(0, 0))
	if not ctl.dash_ready:
		f.append("lock: dash_ready false after the window over + a full 3.0 s regen")


# Glider: holding the jump button in open air engages the glide; the lock application ends
# an ACTIVE glide at once, and nothing re-engages inside the window. (A lock never leaves
# its state stuck: that window-over assertion lives in _lock_expires.)
func _an_active_glide_ends(f: Array[String]) -> void:
	var ctl = Util.ControllerScript.new()
	ctl.setup("glider", Util.consts())
	var w := Util.world_from_tiles([[0, 0, 0]])
	ctl.place(w)
	ctl.cur_key = ""
	ctl.x = 0.5
	ctl.y = 10.0
	ctl.z = 0.5
	ctl.vy = -4.0
	ctl.grounded = false
	ctl.step(DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
	if not ctl.gliding:
		f.append("lock: the glide never engaged in open air")
	ctl.lock_abilities(LOCK_TICKS)
	if ctl.gliding:
		f.append("lock: an active glide survived the lock application")


# The lock window runs for exactly ticks/60 s (the controller owns the conversion).
func _lock_expires(f: Array[String]) -> void:
	var pair: Array = _placed("athletic")
	var ctl = pair[0]
	var w: Dictionary = pair[1]
	ctl.lock_abilities(30)   # 0.5 s
	if not ctl.ability_locked(w):
		f.append("lock: a 0.5 s window never locked")
	Util.run_ticks(ctl, w, 31, func(_c, _i): return Util.mk_in(0, 0))
	if ctl.ability_locked(w):
		f.append("lock: the window still held after 0.5 s (%.6f left)" % ctl.lock)
	# the effect list read: each class's lock disables precisely player.json's block
	var eff: Array = Util.ControllerScript.lock_effects("dasher")
	if not (eff.has("dash_disabled") and eff.size() == 1):
		f.append("lock: the dasher's lock_effect %s is not exactly [dash_disabled]" % str(eff))
	var eff2: Array = Util.ControllerScript.lock_effects("glider")
	if not (eff2.has("glide_disabled") and eff2.size() == 1):
		f.append("lock: the glider's lock_effect %s is not exactly [glide_disabled]" % str(eff2))
	var eff3: Array = Util.ControllerScript.lock_effects("athletic")
	if not (eff3.has("class_multipliers_off") and eff3.size() == 1):
		f.append("lock: the athletic's lock_effect %s is not exactly [class_multipliers_off]"
				% str(eff3))
	# an unknown class id falls back to no effects (a lock can never be a no-op)
	if not Util.ControllerScript.lock_effects("no_such_kit").has("glide_disabled"):
		f.append("lock: an unknown class id read as an empty effect list")
