extends RefCounted
#
# Loading-screen test (ticket T-024, extended by TICKET LOADING; DESIGN.md section 2 / 14, D-LOAD-1..8).
# Drives the injected advance() clock; no test sleeps in real time.
#   - THE TWO-DURATION LAW (owner ruling, FINAL): the first launch holds 5.0 s (a fast load is shown for
#     at least 5.0 s, a simulated 7 s load takes 7 s); EVERY RESTART holds exactly 2.0 s - never less,
#     never more - and a fast load never waits past it. The hold is a pure function of an explicit
#     flag, proven on both branches, with several step sizes and the real-loader hook;
#   - the tip pool is data-driven from data/tips.json: exactly 30 tips, hazard_tell tips weighted x3,
#     the visible tip rotates every 5.0 s of display time, and the numbers the tips quote are pinned to
#     the code constants / enemy.json values (a tip that stops being true fails here);
#   - the gag stage: every gag draws real enemy sprites that exist, lands its joke inside the 2.0 s
#     restart window, varies between loads, and a missing sprite falls back to a TBD placeholder.

const LoadingScreenScript := preload("res://app/loading_screen.gd")
const LoadingGagsScript := preload("res://app/loading_gags.gd")
const LoadingStageScript := preload("res://app/loading_stage.gd")
const MinesScript := preload("res://sim/mines.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const ControllerScript := preload("res://sim/controller.gd")
const StragglerScript := preload("res://view/straggler_beam.gd")

const STEP := 0.05
const FRAME := 1.0 / 60.0
const FLOAT_EPS := 0.001
const EXACT_EPS := 0.000001

var _made: Array = []   # every loading screen a test built (they are Controls: freed at the end)



func run() -> Array[String]:
	var f: Array[String] = []
	_test_fast_load_holds_five_seconds(f)
	_test_simulated_seven_second_load(f)
	_test_law_is_a_pure_function_of_the_flag(f)
	_test_restart_holds_exactly_two_seconds(f)
	_test_restart_step_sizes(f)
	_test_restart_real_loader_hook(f)
	_test_restart_slow_load_is_not_clipped(f)
	_test_finished_signal_once(f)
	_test_tips_pool_and_weighting(f)
	_test_tips_thirty_and_pinned(f)
	_test_tip_rotation_every_five_seconds(f)
	_test_gags_model(f)
	_test_gag_variety(f)
	_test_stage_sprites(f)
	_test_view_builds(f)
	for n in _made:
		if is_instance_valid(n):
			(n as Node).free()
	_made.clear()
	return f


func _advance_until_complete(ls: Control, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if ls.advance(STEP):
			return true
		t += STEP
	return false


# ---- first launch (T-024's assertions: the 5.0 s case) ----------------------------------------

func _test_fast_load_holds_five_seconds(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(4242, 1.0)   # fast load: the loader is done in 1.0 s (default flag = first launch)
	# not complete before the 5.0 s minimum, even though the load finished at 1.0 s
	while ls.shown_time() < 4.99:
		ls.advance(STEP)
		if ls.is_complete() and ls.shown_time() < 5.0 - FLOAT_EPS:
			f.append("fast load: complete at %.2f s, before the 5.0 s minimum" % ls.shown_time())
			return
	# the hold expires on the first step at/after 5.0 s
	var completed := ls.is_complete()
	var shown := ls.shown_time()
	while not completed and ls.shown_time() < 5.0 + STEP * 2.0:
		completed = ls.advance(STEP)
	shown = ls.shown_time()
	if not completed:
		f.append("fast load: never completed (stuck at %.2f s)" % shown)
		return
	if shown < 5.0 - FLOAT_EPS:
		f.append("fast load: shown only %.3f s, want >= 5.0 s" % shown)
	if shown > 5.0 + STEP + FLOAT_EPS:
		f.append("fast load: held %.3f s, want the first step at/after 5.0 s" % shown)
	if ls.load_fraction() < 1.0 - FLOAT_EPS:
		f.append("fast load: bar shows %.3f at completion, want 1.0" % ls.load_fraction())
	if absf(ls.hold_seconds() - 5.0) > EXACT_EPS or not ls.is_first_launch():
		f.append("fast load: default start() is not the 5.0 s first-launch law")


func _test_simulated_seven_second_load(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(777, 7.0)
	var progressed_before_five := false
	var mid_fraction := -1.0
	var at_five := -1.0
	var t := 0.0
	while t < 7.0 + STEP * 2.0:
		ls.advance(STEP)
		t += STEP
		var frac: float = ls.load_fraction()
		if frac > 0.01 and t < 5.0:
			progressed_before_five = true
		if absf(ls.shown_time() - 3.5) < STEP * 0.5:
			mid_fraction = frac
		if absf(ls.shown_time() - 5.0) < STEP * 0.5:
			at_five = frac
		if ls.is_complete():
			break
	if not ls.is_complete():
		f.append("7 s load: not complete after %.2f s of stepping" % ls.shown_time())
		return
	if ls.shown_time() < 7.0 - FLOAT_EPS:
		f.append("7 s load: completed at %.3f s, want 7.0 s" % ls.shown_time())
	if ls.shown_time() > 7.0 + STEP + FLOAT_EPS:
		f.append("7 s load: completed at %.3f s, want 7.0 s" % ls.shown_time())
	if not progressed_before_five:
		f.append("7 s load: progress stayed at 0 before 5.0 s - not real progress")
	if mid_fraction >= 0.0:
		if absf(mid_fraction - 0.5) > 0.05:
			f.append("7 s load: fraction at 3.5 s is %.3f, want ~0.5" % mid_fraction)
	else:
		f.append("7 s load: never observed the 3.5 s mark")
	if at_five >= 0.0:
		if absf(at_five - 5.0 / 7.0) > 0.05:
			f.append("7 s load: fraction at 5.0 s is %.3f, want ~0.714 (real, not pinned)" % at_five)
	else:
		f.append("7 s load: never observed the 5.0 s mark")


# ---- the two-duration law ---------------------------------------------------------------------

func _test_law_is_a_pure_function_of_the_flag(f: Array[String]) -> void:
	if absf(LoadingScreenScript.hold_seconds_for(true) - 5.0) > EXACT_EPS:
		f.append("law: hold_seconds_for(true) = %.3f, want 5.0 (first launch)" % LoadingScreenScript.hold_seconds_for(true))
	if absf(LoadingScreenScript.hold_seconds_for(false) - 2.0) > EXACT_EPS:
		f.append("law: hold_seconds_for(false) = %.3f, want 2.0 (restart)" % LoadingScreenScript.hold_seconds_for(false))
	if LoadingScreenScript.FIRST_LAUNCH_SECONDS != 5.0 or LoadingScreenScript.RESTART_SECONDS != 2.0:
		f.append("law: the constants are not 5.0 / 2.0")
	if LoadingScreenScript.MIN_DISPLAY_SECONDS != LoadingScreenScript.FIRST_LAUNCH_SECONDS:
		f.append("law: MIN_DISPLAY_SECONDS must stay the 5.0 s first-launch hold")
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(1, 1.0, false)
	if ls.is_first_launch() or absf(ls.hold_seconds() - 2.0) > EXACT_EPS:
		f.append("law: start(.., false) did not bind the 2.0 s restart hold")
	ls.start(1, 1.0, true)
	if not ls.is_first_launch() or absf(ls.hold_seconds() - 5.0) > EXACT_EPS:
		f.append("law: start(.., true) did not bind the 5.0 s first-launch hold")
	ls.set_first_launch(false)
	if absf(ls.hold_seconds() - 2.0) > EXACT_EPS:
		f.append("law: set_first_launch(false) did not re-derive the 2.0 s hold")
	# a restart after a first launch on the SAME object: nothing leaks between loads
	ls.start(2, 0.2, true)
	_advance_until_complete(ls, 20.0)
	var first_total: float = ls.shown_time()
	ls.start(3, 0.2, false)
	_advance_until_complete(ls, 20.0)
	if absf(first_total - 5.0) > EXACT_EPS or absf(ls.shown_time() - 2.0) > EXACT_EPS:
		f.append("law: first then restart on one object gave %.4f s then %.4f s, want 5.0 then 2.0" %
				[first_total, ls.shown_time()])


func _test_restart_holds_exactly_two_seconds(f: Array[String]) -> void:
	# fast loads of every flavour: none may leave before 2.0 s, none may stay past it
	for load_s in [0.0, 0.05, 0.3, 1.0, 1.99, 2.0]:
		var ls := LoadingScreenScript.new()
		_made.append(ls)
		ls.start(31, load_s, false)
		var early := false
		var t := 0.0
		var done := false
		while t < 10.0 and not done:
			done = ls.advance(STEP)
			t += STEP
			if done and ls.shown_time() < 2.0 - EXACT_EPS:
				early = true
		if early:
			f.append("restart (load %.2f s): completed at %.4f s, before the 2.0 s hold" % [load_s, ls.shown_time()])
		if not done:
			f.append("restart (load %.2f s): never completed" % load_s)
			continue
		if absf(ls.shown_time() - 2.0) > EXACT_EPS:
			f.append("restart (load %.2f s): shown %.6f s, want exactly 2.0" % [load_s, ls.shown_time()])
		if ls.load_fraction() < 1.0 - FLOAT_EPS:
			f.append("restart (load %.2f s): bar %.3f at completion, want 1.0" % [load_s, ls.load_fraction()])
	# a fast first-launch load is exactly 5.0 s too (the clamp, not the loose step)
	for load_s2 in [0.0, 1.0, 5.0]:
		var ls2 := LoadingScreenScript.new()
		_made.append(ls2)
		ls2.start(32, load_s2, true)
		_advance_until_complete(ls2, 20.0)
		if absf(ls2.shown_time() - 5.0) > EXACT_EPS:
			f.append("first launch (load %.2f s): shown %.6f s, want exactly 5.0" % [load_s2, ls2.shown_time()])
	# not complete at 1.9 s, complete at 2.0 s
	var ls3 := LoadingScreenScript.new()
	_made.append(ls3)
	ls3.start(33, 0.1, false)
	ls3.advance(1.9)
	if ls3.is_complete():
		f.append("restart: complete at 1.9 s")
	ls3.advance(0.1)
	if not ls3.is_complete():
		f.append("restart: not complete at 2.0 s with a 0.1 s load")


func _test_restart_step_sizes(f: Array[String]) -> void:
	# coarse and fine clocks, including a real-frame 1/60 s step and one giant step: always exactly 2.0 s
	for step in [FRAME, 0.016667, 0.033, 0.1, 0.3, 0.7, 5.0]:
		var ls := LoadingScreenScript.new()
		_made.append(ls)
		ls.start(41, 0.4, false)
		var n := 0
		while not ls.advance(step) and n < 100000:
			n += 1
		if absf(ls.shown_time() - 2.0) > EXACT_EPS:
			f.append("restart (step %.5f): shown %.6f s, want exactly 2.0" % [step, ls.shown_time()])
		# the same clock on a first launch: exactly 5.0
		var ls5 := LoadingScreenScript.new()
		_made.append(ls5)
		ls5.start(42, 0.4, true)
		n = 0
		while not ls5.advance(step) and n < 100000:
			n += 1
		if absf(ls5.shown_time() - 5.0) > EXACT_EPS:
			f.append("first launch (step %.5f): shown %.6f s, want exactly 5.0" % [step, ls5.shown_time()])


func _test_restart_real_loader_hook(f: Array[String]) -> void:
	# the real loader finishes at 0.4 s: the screen still holds to exactly 2.0 s
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(51, -1.0, false)
	var reported := false
	var done := false
	var n := 0
	while not done and n < 1000:
		done = ls.advance(STEP)
		n += 1
		if not reported and ls.shown_time() >= 0.4:
			ls.set_load_progress(1.0)
			reported = true
		if not reported and ls.shown_time() >= 0.2:
			ls.set_load_progress(0.5)
			if absf(ls.load_fraction() - 0.5) > EXACT_EPS:
				f.append("real hook: bar %.3f after set_load_progress(0.5), want 0.5" % ls.load_fraction())
	if absf(ls.shown_time() - 2.0) > EXACT_EPS:
		f.append("real hook (fast): shown %.6f s, want exactly 2.0" % ls.shown_time())
	# no loader report at all: the screen must NOT complete (a screen with no load is not a loaded level)
	var ls2 := LoadingScreenScript.new()
	_made.append(ls2)
	ls2.start(52, -1.0, false)
	ls2.advance(10.0)
	if ls2.is_complete():
		f.append("real hook: completed with no load source at all")


func _test_restart_slow_load_is_not_clipped(f: Array[String]) -> void:
	# a load slower than the hold completes at its OWN duration - the level must exist first
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(61, 3.5, false)
	var done := false
	var n := 0
	while not done and n < 1000:
		done = ls.advance(STEP)
		n += 1
		if done and ls.shown_time() < 3.5 - FLOAT_EPS:
			f.append("restart, 3.5 s load: completed at %.3f s before the load did" % ls.shown_time())
	if ls.shown_time() > 3.5 + STEP + FLOAT_EPS:
		f.append("restart, 3.5 s load: completed at %.3f s, want ~3.5 (never held past the load)" % ls.shown_time())
	# real loader reports 0.5 at the 2.0 s mark: still loading; 1.0 -> complete on the next step
	var ls2 := LoadingScreenScript.new()
	_made.append(ls2)
	ls2.start(62, -1.0, false)
	ls2.set_load_progress(0.5)
	ls2.advance(2.5)
	if ls2.is_complete():
		f.append("restart, half-loaded at 2.5 s: complete before the loader said so")
	ls2.set_load_progress(1.0)
	if not ls2.advance(0.01):
		f.append("restart: not complete right after the loader reported 1.0 past the hold")
	if ls2.shown_time() > 2.5 + 0.01 + EXACT_EPS:
		f.append("restart: shown_time jumped to %.4f after the late load, want 2.51" % ls2.shown_time())


func _test_finished_signal_once(f: Array[String]) -> void:
	for flag in [true, false]:
		var ls := LoadingScreenScript.new()
		_made.append(ls)
		var hits := [0]
		ls.loading_finished.connect(func(): hits[0] += 1)
		ls.start(71, 0.2, flag)
		_advance_until_complete(ls, 20.0)
		ls.advance(1.0)
		ls.advance(1.0)
		if hits[0] != 1:
			f.append("signal (first_launch=%s): loading_finished fired %d times, want exactly 1" % [str(flag), hits[0]])


# ---- tips -------------------------------------------------------------------------------------

func _test_tips_pool_and_weighting(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	var tips := ls.load_tips()
	if tips.size() < 15:
		f.append("tips: data/tips.json has %d tips, want >= 15 (owner spec)" % tips.size())
	var hazard := 0
	for tip in tips:
		if (tip.get("tags", []) as Array).has("hazard_tell"):
			hazard += 1
	if hazard == 0:
		f.append("tips: no hazard_tell tip in the pool - prioritization is empty")
	var pool := LoadingScreenScript.build_weighted_pool(tips)
	if pool.size() != tips.size() - hazard + hazard * 3:
		f.append("tips: weighted pool has %d entries, want %d (hazard_tell x3)" %
			[pool.size(), tips.size() - hazard + hazard * 3])
	for i in tips.size():
		var count := 0
		for idx in pool:
			if idx == i:
				count += 1
		var want := 3 if (tips[i].get("tags", []) as Array).has("hazard_tell") else 1
		if count != want:
			f.append("tips: tip %s appears %d times in the pool, want %d" % [str(tips[i].get("id")), count, want])


func _test_tip_rotation_every_five_seconds(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(99, 20.0)   # long simulated load spans several rotations
	if ls.tip_step() != 0:
		f.append("rotation: step at t=0 is %d, want 0" % ls.tip_step())
	var first_tip := ls.current_tip()
	if first_tip.is_empty():
		f.append("rotation: no tip shown at t=0")
	ls.advance(4.99)
	if ls.tip_step() != 0:
		f.append("rotation: step at 4.99 s is %d, want 0 (rotates every 5.0 s)" % ls.tip_step())
	if ls.current_tip() != first_tip:
		f.append("rotation: tip changed before 5.0 s elapsed")
	ls.advance(0.02)   # 5.01 s
	if ls.tip_step() != 1:
		f.append("rotation: step at 5.01 s is %d, want 1" % ls.tip_step())
	if ls.current_tip() == first_tip:
		f.append("rotation: tip did not change after 5.0 s")
	ls.advance(5.0)   # 10.01 s
	if ls.tip_step() != 2:
		f.append("rotation: step at 10.01 s is %d, want 2" % ls.tip_step())
	# a restart shows exactly one tip, and it is a real one
	var lr := LoadingScreenScript.new()
	_made.append(lr)
	lr.start(5, 0.1, false)
	_advance_until_complete(lr, 10.0)
	if lr.tip_step() != 0 or lr.current_tip().is_empty():
		f.append("rotation: a 2.0 s restart must show one real tip (step %d)" % lr.tip_step())


func _enemy_stats(enemy_id: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://content/enemies/%s/enemy.json" % enemy_id)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var st: Variant = (parsed as Dictionary).get("stats", {})
	return st if typeof(st) == TYPE_DICTIONARY else {}


## One pin: the tip must still say `needle`, and the code value that makes it true must hold.
func _pin(f: Array[String], by_id: Dictionary, id: String, needle: String, ok: bool) -> void:
	if not by_id.has(id):
		f.append("tip pin: %s is not in tips.json" % id)
		return
	var text := str(by_id[id].get("text", ""))
	if not text.contains(needle):
		f.append("tip %s no longer says \"%s\" (text: %s)" % [id, needle, text])
	elif not ok:
		f.append("tip %s says \"%s\" but the build disagrees" % [id, needle])


func _beats_are_1_and_3(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 2:
		return false
	return int((v as Array)[0]) == 1 and int((v as Array)[1]) == 3


func _jump_window(h: float) -> Array:
	var v: float = float(ControllerScript.DEFAULTS["jump_velocity"])
	var g: float = float(ControllerScript.DEFAULTS["gravity"])
	var disc := v * v - 2.0 * g * h
	if disc < 0.0:
		return [-1.0, -1.0]
	return [(v - sqrt(disc)) / g, (v + sqrt(disc)) / g]


func _test_tips_thirty_and_pinned(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	var tips := ls.load_tips()
	if tips.size() != 30:
		f.append("tips: data/tips.json has %d tips, want exactly 30 (this ticket's pool)" % tips.size())
	var by_id := {}
	var hazard := 0
	for tip in tips:
		var id := str(tip.get("id", ""))
		if by_id.has(id):
			f.append("tips: duplicate id %s" % id)
		by_id[id] = tip
		if str(tip.get("text", "")).strip_edges().length() < 20:
			f.append("tips: %s has no real text" % id)
		if str(tip.get("source", "")).strip_edges() == "":
			f.append("tips: %s names no source (every tip is verified against code)" % id)
		if (tip.get("tags", []) as Array).has("hazard_tell"):
			hazard += 1
	if hazard < 11:
		f.append("tips: only %d hazard_tell tips, the original 11 must remain" % hazard)
	# numbers the tips quote, pinned to the code that makes them true
	var C: Dictionary = ControllerScript.DEFAULTS
	_pin(f, by_id, "tip_mine_no_jump", "0.9 u", is_equal_approx(MinesScript.CONTACT_R, 0.9))
	_pin(f, by_id, "tip_mine_blast", "3 u", is_equal_approx(MinesScript.BLAST_RADIUS, 3.0))
	_pin(f, by_id, "tip_mine_consume_order", "20/40/60", MinesScript.DEFUSE_PCT == 20 and MinesScript.DEFUSE_CAP == 60)
	_pin(f, by_id, "tip_mine_range", "14 u", true)
	_pin(f, by_id, "tip_straggler_beam", "20%", GiftsScript.STRAGGLER_DEN == 5)
	_pin(f, by_id, "tip_straggler_beam", "+40", is_equal_approx(StragglerScript.BEAM_TOP, 40.0))
	var you := _enemy_stats("you")
	_pin(f, by_id, "tip_you_ring", "1.0 u", is_equal_approx(float(you.get("ring_height", 0.0)), 1.0))
	_pin(f, by_id, "tip_you_ring", "1.5 u", is_equal_approx(float(you.get("ring_below_feet", 0.0)), 1.5))
	var w1 := _jump_window(1.0)
	_pin(f, by_id, "tip_you_ring", "%.2f s to %.2f s" % [w1[0], w1[1]], true)
	_pin(f, by_id, "tip_you_rumble", "10 u", is_equal_approx(float(you.get("trigger_distance", 0.0)), 10.0))
	_pin(f, by_id, "tip_you_rumble", "1.5 s", int(you.get("rumble_ticks", 0)) == 90)
	_pin(f, by_id, "tip_you_rumble", "9 u/s", is_equal_approx(float(you.get("ring_speed_u_per_s", 0.0)), 9.0))
	_pin(f, by_id, "tip_you_rumble", "14 u", is_equal_approx(float(you.get("ring_max_radius", 0.0)), 14.0))
	var nuke := _enemy_stats("nuke")
	_pin(f, by_id, "tip_nuke_ring", "2.5 s", int(nuke.get("track_ticks", 0)) == 150)
	_pin(f, by_id, "tip_nuke_ring", "2 to 8 Hz", is_equal_approx(float(nuke.get("beep_hz_start", 0.0)), 2.0)
			and is_equal_approx(float(nuke.get("beep_hz_end", 0.0)), 8.0))
	_pin(f, by_id, "tip_nuke_ring", "1.5 s", int(nuke.get("descent_ticks", 0)) == 90)
	_pin(f, by_id, "tip_nuke_ring", "5 u sphere", is_equal_approx(float(nuke.get("ring_radius", 0.0)), 5.0))
	var gin := _enemy_stats("gin")
	_pin(f, by_id, "tip_gin_patch", "5x5", int(gin.get("patch_half_tiles", 0)) == 2)
	_pin(f, by_id, "tip_gin_patch", "#FF2A2A", str(gin.get("patch_outline_color", "")) == "#FF2A2A")
	_pin(f, by_id, "tip_gin_patch", "2.0 s", int(gin.get("telegraph_ticks", 0)) == 120)
	_pin(f, by_id, "tip_gin_patch", "10 s void zone", int(gin.get("zone_ticks", 0)) == 600)
	var seal := _enemy_stats("seal")
	_pin(f, by_id, "tip_seal_bark", "4-12 u", is_equal_approx(float(seal.get("telegraph_range_min_u", 0.0)), 4.0)
			and is_equal_approx(float(seal.get("telegraph_range_max_u", 0.0)), 12.0))
	var w2 := _jump_window(1.2)
	_pin(f, by_id, "tip_seal_bark", "from %.2f s to %.2f s" % [w2[0], w2[1]], true)
	var kiwi := _enemy_stats("kiwi_cat")
	_pin(f, by_id, "tip_kiwi_cat", "5.6 u/s", is_equal_approx(float(kiwi.get("base_speed", 0.0)), 5.6))
	_pin(f, by_id, "tip_kiwi_cat", "7.2 u/s", is_equal_approx(float(C["run_speed"]) * float(kiwi.get("pursuit_ceiling", 0.0)), 7.2))
	var coil := _enemy_stats("coil")
	_pin(f, by_id, "tip_coil_shock", "1.2 u", is_equal_approx(float(coil.get("landing_kill_radius_u", 0.0)), 1.2))
	_pin(f, by_id, "tip_coil_shock", "6 u", is_equal_approx(float(coil.get("shockwave_radius_u", 0.0)), 6.0))
	_pin(f, by_id, "tip_coil_shock", "2.0 s", is_equal_approx(float(coil.get("ability_lock_s", 0.0)), 2.0))
	_pin(f, by_id, "tip_coil_ring", "6 u radius", is_equal_approx(float(coil.get("shockwave_radius_u", 0.0)), 6.0))
	var ben := _enemy_stats("thicc_ben")
	_pin(f, by_id, "tip_ben_smoke", "13.35 s", is_equal_approx(float(ben.get("teleport_interval_s", 0.0)), 13.35))
	_pin(f, by_id, "tip_ben_smoke", "1.25 s", int(ben.get("telegraph_ticks", 0)) == 75)
	_pin(f, by_id, "tip_ben_smoke", "0.5 s", int(ben.get("chime_tail_ticks", 0)) == 30)
	_pin(f, by_id, "tip_ben_smoke", "4 u", is_equal_approx(float(ben.get("lock_break_dist", 0.0)), 4.0))
	_pin(f, by_id, "tip_ben_launch", "18 u/s", is_equal_approx(float(ben.get("eject_speed", 0.0)), 18.0))
	_pin(f, by_id, "tip_ben_launch", "5 u of apex", absf(float(ben.get("apex_u", 0.0)) - 5.0) < 0.1)
	var isagi := _enemy_stats("isagi")
	_pin(f, by_id, "tip_isagi_volley", "3 balls", int(isagi.get("volley_balls", 0)) == 3)
	_pin(f, by_id, "tip_isagi_volley", "0.15 s", is_equal_approx(float(isagi.get("volley_in_s", 0.0)), 0.15))
	_pin(f, by_id, "tip_isagi_volley", "0.75 s", is_equal_approx(float(isagi.get("volley_gap_s", 0.0)), 0.75))
	_pin(f, by_id, "tip_isagi_volley", "2 HU", is_equal_approx(float(isagi.get("step_clears_hu", 0.0)), 2.0))
	_pin(f, by_id, "tip_isagi_tell", "1.2 s", is_equal_approx(float(isagi.get("windup_s", 0.0)), 1.2))
	var toucher := _enemy_stats("toucher")
	_pin(f, by_id, "tip_toucher_infect", "3 u", is_equal_approx(float(toucher.get("infect_radius_u", 0.0)), 3.0))
	_pin(f, by_id, "tip_toucher_infect", "every 2.0 s", int(toucher.get("infect_interval_ticks", 0)) == 120)
	_pin(f, by_id, "tip_toucher_infect", "12 s", is_equal_approx(float(toucher.get("tile_life_s", 0.0)), 12.0))
	_pin(f, by_id, "tip_toucher_infect", "18 s from level 14",
			is_equal_approx(float(toucher.get("tile_life_s_from_level_14", 0.0)), 18.0))
	var addr := _enemy_stats("address_me")
	_pin(f, by_id, "tip_address_me", "1.5 s", int(addr.get("still_ticks", 0)) == 90)
	var claude := _enemy_stats("claude")
	_pin(f, by_id, "tip_claude_drums", "100 BPM", is_equal_approx(float(claude.get("bpm_base", 0.0)), 100.0))
	_pin(f, by_id, "tip_claude_drums", "beats 1 and 3", _beats_are_1_and_3(claude.get("drum_beats", [])))
	_pin(f, by_id, "tip_claude_plushie", "angrier by 2", is_equal_approx(float(claude.get("agitation_rise_per_s", 0.0)), 2.0))
	_pin(f, by_id, "tip_claude_plushie", "at 100", is_equal_approx(float(claude.get("agitation_max", 0.0)), 100.0))
	_pin(f, by_id, "tip_claude_plushie", "every 25 s", is_equal_approx(float(claude.get("plushie_interval_s", 0.0)), 25.0))
	_pin(f, by_id, "tip_claude_plushie", "10-25 u", is_equal_approx(float(claude.get("plushie_min_u", 0.0)), 10.0)
			and is_equal_approx(float(claude.get("plushie_max_u", 0.0)), 25.0))
	_pin(f, by_id, "tip_claude_plushie", "three at most", int(claude.get("plushie_max", 0)) == 3)
	_pin(f, by_id, "tip_claude_plushie", "takes 35 off", is_equal_approx(float(claude.get("plushie_calm", 0.0)), 35.0))
	# hurdle heights: the tip names each body height, SR-2 / enemy.json world_height
	_pin(f, by_id, "tip_hurdle", "kiwi cat (1.0 u)", is_equal_approx(float(kiwi.get("world_height", 0.0)), 1.0))
	_pin(f, by_id, "tip_hurdle", "toucher (1.4 u)", is_equal_approx(float(toucher.get("world_height", 0.0)), 1.4))
	_pin(f, by_id, "tip_hurdle", "seal (0.6 u)", is_equal_approx(float(seal.get("world_height", 0.0)), 0.6))
	_pin(f, by_id, "tip_hurdle", "thicc ben (4.0 u)", is_equal_approx(float(ben.get("world_height", 0.0)), 4.0))
	# charges / Last Light / invulnerability
	_pin(f, by_id, "tip_void_dive", "1.0 s of invulnerability", is_equal_approx(float(C["respawn_invuln"]), 1.0))
	_pin(f, by_id, "tip_invuln_window", "1.0 s after a respawn", is_equal_approx(float(C["respawn_invuln"]), 1.0))
	_pin(f, by_id, "tip_invuln_window", "2.0 s after Last Light", is_equal_approx(float(C["last_light_invuln"]), 2.0))
	_pin(f, by_id, "tip_last_light_once", "2.0 s of invulnerability", is_equal_approx(float(C["last_light_invuln"]), 2.0))
	_pin(f, by_id, "tip_last_light_once", "within 8 u", is_equal_approx(float(C["last_light_push_radius"]), 8.0))
	_pin(f, by_id, "tip_beacon_restore", "cap of 2", int(C["charge_cap"]) == 2)


# ---- gags -------------------------------------------------------------------------------------

func _finite(v: Variant) -> bool:
	return typeof(v) != TYPE_FLOAT or is_finite(float(v))


func _test_gags_model(f: Array[String]) -> void:
	if LoadingGagsScript.GAG_IDS.size() < 5:
		f.append("gags: %d gags, want >= 5 (one per enemy bit)" % LoadingGagsScript.GAG_IDS.size())
	if not is_equal_approx(LoadingGagsScript.BEAT_A_SECONDS, LoadingScreenScript.RESTART_SECONDS):
		f.append("gags: beat A must be exactly the restart hold (the joke lands in 2.0 s)")
	for id in LoadingGagsScript.GAG_IDS:
		var refs: Array = LoadingGagsScript.SPRITES.get(id, [])
		if refs.is_empty():
			f.append("gag %s: no SPRITES entry" % id)
			continue
		for ref in refs:
			var path: String = LoadingGagsScript.sprite_path(ref[0], ref[1])
			if not ResourceLoader.exists(path):
				f.append("gag %s: sprite %s missing (would draw as a TBD placeholder)" % [id, path])
		var allowed := {}
		for ref in refs:
			allowed[str(ref[0]) + "/" + str(ref[1])] = true
		var with_sprite := 0
		var samples := 0
		var punchline := false
		var t := 0.0
		while t < LoadingGagsScript.CYCLE_SECONDS * 2.0:
			var its := LoadingGagsScript.items(id, t)
			samples += 1
			var has_sprite := false
			for it in its:
				for key in it:
					if not _finite(it[key]):
						f.append("gag %s t=%.2f: non-finite %s" % [id, t, str(key)])
				if str(it.get("k", "")) == "sprite":
					has_sprite = true
					if not allowed.has(str(it["enemy"]) + "/" + str(it["name"])):
						f.append("gag %s t=%.2f: draws %s/%s not listed in SPRITES" % [id, t, it["enemy"], it["name"]])
				if t <= LoadingGagsScript.BEAT_A_SECONDS and (str(it.get("k", "")) == "bubble" or str(it.get("k", "")) == "text") \
						and float(it.get("s", 0.0)) >= 0.99:
					punchline = true
			if has_sprite:
				with_sprite += 1
			t += 0.05
		if float(with_sprite) / float(samples) < 0.5:
			f.append("gag %s: an enemy is on stage in only %d of %d frames" % [id, with_sprite, samples])
		if not punchline:
			f.append("gag %s: no spoken/printed beat fully shown inside the first 2.0 s (restart would miss the joke)" % id)
		# the timeline loops: t and t + 5.0 are the same picture
		var a := LoadingGagsScript.items(id, 1.37)
		var b := LoadingGagsScript.items(id, 1.37 + LoadingGagsScript.CYCLE_SECONDS)
		if a.size() != b.size():
			f.append("gag %s: the 5.0 s timeline does not loop cleanly" % id)
	if not LoadingGagsScript.items("no_such_gag", 1.0).is_empty():
		f.append("gags: an unknown gag id must draw nothing")


func _test_gag_variety(f: Array[String]) -> void:
	var seen := {}
	var prev := ""
	for s in 200:
		var g: String = LoadingGagsScript.pick_gag(s, prev)
		if g == prev:
			f.append("gag pick: seed %d repeated the previous gag %s" % [s, g])
		if not LoadingGagsScript.GAG_IDS.has(g):
			f.append("gag pick: unknown id %s" % g)
		if LoadingGagsScript.pick_gag(s, prev) != g:
			f.append("gag pick: seed %d is not deterministic" % s)
		seen[g] = true
		prev = g
	if seen.size() != LoadingGagsScript.GAG_IDS.size():
		f.append("gag pick: 200 seeds reached only %d of %d gags" % [seen.size(), LoadingGagsScript.GAG_IDS.size()])
	# two consecutive loads in one process differ
	var a := LoadingScreenScript.new()
	_made.append(a)
	a.start(11, 0.1, false)
	var first: String = a.gag_id()
	var b := LoadingScreenScript.new()
	_made.append(b)
	b.start(11, 0.1, false)
	if b.gag_id() == first:
		f.append("gag pick: two consecutive loads showed the same gag %s" % first)


func _test_stage_sprites(f: Array[String]) -> void:
	var stage := LoadingStageScript.new()
	var real: Dictionary = stage.sprite_info("seal", "idle_00")
	if bool(real.get("tbd", true)) or real.get("tex") == null:
		f.append("stage: the real seal sprite did not load")
	else:
		var rect: Rect2 = real["rect"]
		var tsz: Vector2 = (real["tex"] as Texture2D).get_size()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0 or rect.size.x > tsz.x or rect.size.y > tsz.y:
			f.append("stage: the seal sprite's opaque rect %s is not inside its %s texture" % [str(rect), str(tsz)])
	var missing: Dictionary = stage.sprite_info("no_such_enemy", "no_such_frame")
	if not bool(missing.get("tbd", false)) or missing.get("tex") == null:
		f.append("stage: a missing sprite must fall back to a TBD placeholder texture, never null")
	stage.free()


func _test_view_builds(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	_made.append(ls)
	ls.start(8, 0.5, false)
	ls._build_view()
	ls.advance(1.0)
	if not ls.status_text().contains("%"):
		f.append("view: the status line shows no percentage: %s" % ls.status_text())
	var restart_text: String = ls.status_text()
	ls.start(8, 0.5, true)
	if ls.status_text() == restart_text:
		f.append("view: first-launch and restart status lines should differ in register")
