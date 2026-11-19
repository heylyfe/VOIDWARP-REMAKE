extends RefCounted
#
# CURSE-FRICTION test (W10-D, headless): wet_floor and slipstream_trail - the two
# curses whose whole job is the world's w["slippery"] map - really do change friction
# in play. For the proof this file never dispatches a curse module's hooks by hand: every
# number below comes from app/world.gd's build() / step() on a real level (seed 1, level 5,
# dasher), and every held case has its curses-empty twin built the same way (the
# negative control: it must show the un-cursed value). The one direct module read is
# WetFloor.slow_mul(), the pure helper the brief asks for.
#
# What is measured, and what came back (D-075 check, W10-D audit):
#
#   wet_floor, the live glitched tile. friction_mult() (sim/controller.gd) returns 0.4
#     for a tile that is glitched OR slippery (it has returned 0.4 for glitched since
#     the controller landed), so a glitched floor is already x0.4 WITHOUT the curse. The
#     curse cannot slow a live glitched tile further: the slide distances are byte-for-
#     byte identical with and without it (case W1). That is also what D-075 wants - no
#     extra slow. The friction effect the curse actually ADDS shows once the glitched
#     set is cleansed (a cleansing ring wipes w["glitched"] and never touches
#     w["slippery"]): the stale slippery keys keep the floor at x0.4 while the control
#     floor goes back to x1.0 (case W2), and the slide distance differs measurably.
#
#   slipstream_trail. A dashing seal stamps the tiles it rides into w["slippery"] for
#     180 ticks. The tiles are the ones under the body, stamped at the BODY height, so
#     only the early part of the dash lands on the floor height (hu == the floor tile's
#     half-units); those floor keys are the tiles a walking player can actually stand
#     on and are picked as the slide tile (case S).
#
# The player never receives movement input headless (capture reads real keys), so
# "distance travelled" is measured as a coast: vx = 9.0 at setup, no input, friction is
# what bled it off, distance is what was travelled over 40 ticks. On slippery floor the
# coast carries farther (less deceleration); the sign flips under acceleration-from-rest
# (slippery floor builds speed slower), but both ride the same friction_mult path.
#
# The seal's spawn delay is forced to 2 ticks through the runtime knob
# (rt.spawn_delay_ticks, the same knob the unit tests use) so the test stays short;
# both builds get the same value, so parity holds. The curse's own on_tick pass runs
# after rt.step inside world.step(), exactly as in play.

const WorldScript := preload("res://app/world.gd")
const ControllerScript := preload("res://sim/controller.gd")
const WetFloor := preload("res://content/curses/wet_floor.gd")

const SEED := 1
const LEVEL := 5
const DT := 1.0 / 60.0
const GLITCH_MUL := 0.4
const NORMAL_MUL := 1.0
const SLIDE_TICKS := 40


func run() -> Array[String]:
	var f: Array[String] = []
	_wet_floor(f)
	_slipstream_trail(f)
	return f


# ---- shared helpers -------------------------------------------------------------------

func _build(votes: Dictionary, curses: Dictionary):
	var world = WorldScript.new()
	var ledger := {
		"class": "dasher", "votes": votes, "curses": curses, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


## A straight run of floor tiles at one row height, clean of mines and props (the slide
## must not clip anything). Returns [x0 ... xn, "z,yhu"] or [] when none exists.
func _find_run(world) -> Array:
	var by_row := {}
	for t in world.lv["tiles"]:
		var k := "%d,%d" % [int(t[1]), int(t[2])]
		if not by_row.has(k):
			by_row[k] = {}
		by_row[k][int(t[0])] = true
	var mine_tiles := {}
	for s in world.lstate.mines.slots:
		mine_tiles["%d,%d" % [int(s["x"]), int(s["z"])]] = true
	var prop_cols: Dictionary = world.rt.world["prop_cols"]
	var best: Array = []
	for k in by_row.keys():
		var z := int(k.split(",")[0])
		var yhu := int(k.split(",")[1])
		var xs: Array = by_row[k].keys()
		xs.sort()
		var start: int = 0
		for i in range(1, xs.size() + 1):
			var contiguous: bool = i < xs.size() and xs[i] == xs[i - 1] + 1
			if contiguous:
				continue
			var rr := xs.slice(start, i)
			var clean := true
			for x in rr:
				if mine_tiles.has("%d,%d" % [int(x), z]) or prop_cols.has("%d,%d" % [int(x), z]):
					clean = false
					break
			if clean and (best.is_empty() or rr.size() > best.size() - 1):
				var cand := rr.duplicate()
				cand.append(k)
				best = cand
			start = i
	return best


## Park a coasting player on a tile: vx = 9.0, no input, remember the friction the sim
## reads at setup. Returns {"friction": f, "dist": d} after SLIDE_TICKS steps.
func _slide(world, key: String) -> Dictionary:
	var p: PackedStringArray = key.split(",")
	var x0 := float(int(p[0])) + 0.5
	var yhu := int(p[2])
	world.ctl.x = x0
	world.ctl.y = float(yhu) * 0.5
	world.ctl.z = float(int(p[1])) + 0.5
	world.ctl.vx = 9.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.grounded = true
	world.ctl.cur_key = key
	var f0: float = world.ctl.friction_mult(world.rt.world)
	for _i in SLIDE_TICKS:
		world.step(DT)
	return {"friction": f0, "dist": absf(world.ctl.x - x0)}


func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)

# ---- case W: wet_floor -----------------------------------------------------------------

func _wet_floor(f: Array[String]) -> void:
	var w_h = _build({}, {"wet_floor": 1})
	var w_c = _build({}, {})
	if w_h == null or w_c == null:
		f.append("wet_floor: world failed to build (held=%s control=%s)" % [str(w_h != null), str(w_c != null)])
		_drop(w_h)
		_drop(w_c)
		return
	var run := _find_run(w_h)
	if run.size() < 5:
		f.append("wet_floor: no clean straight floor run found (need >= 5 tiles, got %s)" % str(run))
		_drop(w_h)
		_drop(w_c)
		return
	var z := int(str(run[run.size() - 1]).split(",")[0])
	var yhu := int(str(run[run.size() - 1]).split(",")[1])
	var xs := run.slice(0, run.size() - 1)
	# glitch every tile of the run in BOTH builds (game state, curse-independent)
	var keys: Array = []
	for x in xs:
		var key := "%d,%d,%d" % [int(x), z, yhu]
		keys.append(key)
		(w_h.rt.world["glitched"] as Dictionary)[key] = true
		(w_c.rt.world["glitched"] as Dictionary)[key] = true
	var key0 := str(keys[0])
	# step once so the curse's on_tick pass mirrors glitched -> slippery
	w_h.step(DT)
	w_c.step(DT)
	# ---- W-map: the held run's glitched tiles are slippery; the control's are not
	for key in keys:
		_check(f, (w_h.rt.world["slippery"] as Dictionary).has(key),
				"wet_floor: a glitched tile the player can stand on is not in w[\"slippery\"] while held (%s)" % key)
		_check(f, not (w_c.rt.world["slippery"] as Dictionary).has(key),
				"wet_floor: the curses-empty run wrote a slippery key (%s) - negative control broken" % key)
	# ---- W-slow: D-075 - the glitched floor's own -20% is untouched by the curse (REQ 3)
	for pair in [[w_h, "held"], [w_c, "control"]]:
		var w = pair[0]
		w.ctl.cur_key = key0
		_check(f, is_equal_approx(w.ctl.run_speed(w.rt.world), 9.0 * ControllerScript.GLITCH_SLOW_MUL),
				"wet_floor %s: run speed on glitched floor %.4f, want %.4f (x0.8, no extra slow)" % [
					pair[1], w.ctl.run_speed(w.rt.world), 9.0 * ControllerScript.GLITCH_SLOW_MUL])
		_check(f, is_equal_approx(w.ctl.glitch_slow_mul, ControllerScript.GLITCH_SLOW_MUL),
				"wet_floor %s: the curse moved the controller's glitch slow stat to %.4f, want %.2f" % [
					pair[1], w.ctl.glitch_slow_mul, ControllerScript.GLITCH_SLOW_MUL])
	_check(f, is_equal_approx(w_h.ctl.glitch_slow_mul, w_c.ctl.glitch_slow_mul),
			"wet_floor: the curses-held controller's glitch slow (%.4f) differs from the not-held one (%.4f)" % [
				w_h.ctl.glitch_slow_mul, w_c.ctl.glitch_slow_mul])
	_check(f, is_equal_approx(WetFloor.slow_mul({"curses_held": {"wet_floor": 1}}), float(ControllerScript.GLITCH_SLOW_MUL)),
			"wet_floor: slow_mul() reports %.4f, want %.2f (the value the curse must leave alone)" % [
				WetFloor.slow_mul({"curses_held": {"wet_floor": 1}}), float(ControllerScript.GLITCH_SLOW_MUL)])
	# ---- W1: friction on the LIVE glitched tile. A glitched tile is NOT slippery by itself -
	# DESIGN section 7 (D-075) reserves the x0.4 for the curse that grants it - so the curse is
	# the only thing that makes this floor slippery, and the coast distance must differ.
	var a_h := _slide(w_h, key0)
	var a_c := _slide(w_c, key0)
	_check(f, is_equal_approx(a_h["friction"], GLITCH_MUL),
			"wet_floor held: friction on live glitched floor %.2f, want 0.4" % a_h["friction"])
	_check(f, is_equal_approx(a_c["friction"], 1.0),
			"wet_floor not held: friction on live glitched floor %.2f, want 1.0 - a glitched tile is not slippery without the curse (D-075)" % a_c["friction"])
	_check(f, a_h["dist"] > a_c["dist"] + 1e-6,
			"wet_floor: coast distance over %d ticks on a live glitched tile held (%.4f) is not longer than not held (%.4f); the curse must make the floor slippery, and low friction slides farther" % [
				SLIDE_TICKS, a_h["dist"], a_c["dist"]])
	# ---- W2: the glitched set is cleansed (a cleanse wipes w["glitched"], never
	# w["slippery"]): the control floor goes back to x1.0, the held floor keeps x0.4
	for key in keys:
		(w_h.rt.world["glitched"] as Dictionary).erase(key)
		(w_c.rt.world["glitched"] as Dictionary).erase(key)
	for key in keys:
		_check(f, (w_h.rt.world["slippery"] as Dictionary).has(key),
				"wet_floor: the stale slippery key vanished when the glitched set was cleansed (%s); Wet Floor must keep the floor slippery" % key)
		_check(f, not (w_c.rt.world["slippery"] as Dictionary).has(key),
				"wet_floor: the curses-empty run is still slippery after the cleanse (%s)" % key)
	var b_h := _slide(w_h, key0)
	var b_c := _slide(w_c, key0)
	_check(f, is_equal_approx(b_h["friction"], GLITCH_MUL),
			"wet_floor held: friction after cleanse %.2f, want 0.4 (the stale slippery keys hold)" % b_h["friction"])
	_check(f, is_equal_approx(b_c["friction"], NORMAL_MUL),
			"wet_floor not held: friction after cleanse %.2f, want 1.0 (floor went back to normal)" % b_c["friction"])
	_check(f, b_h["dist"] > b_c["dist"] + 0.2,
			"wet_floor: coast distance over %d ticks after cleanse held %.4f vs control %.4f; the stale slippery floor must coast measurably farther" % [
				SLIDE_TICKS, b_h["dist"], b_c["dist"]])
	_drop(w_h)
	_drop(w_c)

# ---- case S: slipstream_trail ----------------------------------------------------------

func _slipstream_trail(f: Array[String]) -> void:
	var w_h = _build({"seal": 1}, {"slipstream_trail": 1})
	var w_c = _build({"seal": 1}, {})
	if w_h == null or w_c == null:
		f.append("slipstream_trail: world failed to build (held=%s control=%s)" % [str(w_h != null), str(w_c != null)])
		_drop(w_h)
		_drop(w_c)
		return
	# shorten the 6 s natural spawn delay through the runtime knob (both builds alike)
	w_h.rt.spawn_delay_ticks = 2
	w_c.rt.spawn_delay_ticks = 2
	var run := _find_run(w_h)
	if run.size() < 5:
		f.append("slipstream_trail: no clean straight floor run found (need >= 5 tiles, got %s)" % str(run))
		_drop(w_h)
		_drop(w_c)
		return
	var z := int(str(run[run.size() - 1]).split(",")[0])
	var yhu := int(str(run[run.size() - 1]).split(",")[1])
	var xs := run.slice(0, run.size() - 1)
	var feet := float(yhu) * 0.5
	# the seal spawns at tick 2; teleport it to the -x end of the run on the row so the
	# dash line runs along the floor; the line is fixed at telegraph start (D-069)
	for pair in [[w_h, "held"], [w_c, "control"]]:
		var w = pair[0]
		w.ctl.x = float(xs[xs.size() - 1]) + 0.5
		w.ctl.y = feet
		w.ctl.z = float(z) + 0.5
		w.ctl.vx = 0.0
		w.ctl.vy = 0.0
		w.ctl.vz = 0.0
		w.ctl.grounded = true
		w.ctl.cur_key = "%d,%d,%d" % [int(xs[xs.size() - 1]), z, yhu]
	var seal_h: Dictionary = {}
	var seal_c: Dictionary = {}
	for pair in [[w_h, "held"], [w_c, "control"]]:
		var w = pair[0]
		for _i in 30:
			w.step(DT)
			if w.rt.enemies.size() > 0:
				if pair[1] == "held":
					seal_h = w.rt.enemies[0]
				else:
					seal_c = w.rt.enemies[0]
				break
	if seal_h.is_empty() or seal_c.is_empty():
		f.append("slipstream_trail: the seal never spawned (held=%s control=%s)" % [str(not seal_h.is_empty()), str(not seal_c.is_empty())])
		_drop(w_h)
		_drop(w_c)
		return
	for pair in [[seal_h, "held"], [seal_c, "control"]]:
		pair[0]["x"] = float(xs[0]) + 0.5
		pair[0]["y"] = feet
		pair[0]["z"] = float(z) + 0.5
	# drive telegraph -> dash -> recover; dodge the player to the spawn tile on the
	# first telegraph tick (the line is fixed then) so the dash misses
	for pair in [[w_h, "held"], [w_c, "control"]]:
		var w = pair[0]
		var seal: Dictionary = seal_h if pair[1] == "held" else seal_c
		var dodged := false
		var dash_seen := false
		for _i in 220:
			w.step(DT)
			var ph := str(seal.get("phase", ""))
			if ph == "telegraph" and not dodged:
				dodged = true
				var s0 = w.lv["spawns"][0]
				w.ctl.x = float(s0[0]) + 0.5
				w.ctl.y = float(s0[2]) * 0.5
				w.ctl.z = float(s0[1]) + 0.5
				w.ctl.cur_key = "%d,%d,%d" % [int(s0[0]), int(s0[1]), int(s0[2])]
			if ph == "dash":
				dash_seen = true
			if ph == "recover" and dash_seen:
				break
		if not dash_seen:
			f.append("slipstream_trail %s: the seal never dashed (phase stuck at %s)" % [pair[1], str(seal.get("phase", ""))])
			_drop(w_h)
			_drop(w_c)
			return
		# park the seal far above the player so it cannot re-engage during the
		# measurement / expiry window; it eases down 2.0 u/s and stays > 12 u away
		seal["y"] = 40.0
	var trail_h: Dictionary = w_h.rt.world["slippery"]
	var trail_c: Dictionary = w_c.rt.world["slippery"]
	var target := "%d,%d,%d" % [int(xs[0]), z, yhu]
	_check(f, trail_h.size() > 0, "slipstream_trail held: a dash stamped no tile into w[\"slippery\"]")
	_check(f, trail_h.has(target),
			"slipstream_trail held: the run's floor tile under the dash start (%s) is not in w[\"slippery\"]" % target)
	_check(f, trail_c.is_empty(),
			"slipstream_trail not held: the curses-empty run wrote %d slippery keys - negative control broken" % trail_c.size())
	_check(f, not trail_c.has(target),
			"slipstream_trail not held: the trail tile (%s) is slippery without the curse" % target)
	var trail_keys: Array = trail_h.keys()
	# ---- friction: the slide on the trail tile (held 0.4 vs control 1.0), nothing else moved
	var s_h := _slide(w_h, target)
	var s_c := _slide(w_c, target)
	_check(f, is_equal_approx(s_h["friction"], GLITCH_MUL),
			"slipstream_trail held: friction on the trail tile %.2f, want 0.4" % s_h["friction"])
	_check(f, is_equal_approx(s_c["friction"], NORMAL_MUL),
			"slipstream_trail not held: friction on the trail tile %.2f, want 1.0 (no curse, no trail)" % s_c["friction"])
	_check(f, s_h["dist"] > s_c["dist"] + 0.2,
			"slipstream_trail: coast distance over %d ticks held %.4f vs control %.4f; the trail must coast measurably farther" % [
				SLIDE_TICKS, s_h["dist"], s_c["dist"]])
	# ---- the 180-tick lifetime: all stamps are still present right after the slide
	# (the earliest stamp outlives the dash by 120 ticks), then all are gone 250 ticks on
	var alive := 0
	for key in trail_keys:
		if (w_h.rt.world["slippery"] as Dictionary).has(key):
			alive += 1
	_check(f, alive == trail_keys.size(),
			"slipstream_trail held: %d of %d trail keys expired before their 180 ticks were up" % [
				trail_keys.size() - alive, trail_keys.size()])
	for _i in 250:
		w_h.step(DT)
	var left := 0
	for key in trail_keys:
		if (w_h.rt.world["slippery"] as Dictionary).has(key):
			left += 1
	_check(f, left == 0,
			"slipstream_trail held: %d trail keys still in w[\"slippery\"] 250 ticks after the dash; the 180-tick lifetime (3 s) must erase them" % left)
	_drop(w_h)
	_drop(w_c)
