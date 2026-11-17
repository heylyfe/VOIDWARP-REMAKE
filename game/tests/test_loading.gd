extends RefCounted
#
# Loading-screen test (DESIGN.md section 2 [CANON] >= 5.0 s row; section 14; ticket T-024).
# Drives the injected advance() clock; no test sleeps in real time.
#   - a fast load (1.0 s) is shown for AT LEAST 5.0 s and completes on the first step at/after 5.0;
#   - a simulated 7 s load takes 7 s to complete, shows real (rising) progress the whole time,
#     and is not complete before the load is;
#   - the tip pool is data-driven from data/tips.json (>= 15 tips), hazard_tell tips are weighted
#     x3 in the draw pool, and the visible tip rotates every 5.0 s of display time.

const LoadingScreenScript := preload("res://app/loading_screen.gd")

const STEP := 0.05
const FLOAT_EPS := 0.001


func run() -> Array[String]:
	var f: Array[String] = []
	_test_fast_load_holds_five_seconds(f)
	_test_simulated_seven_second_load(f)
	_test_tips_pool_and_weighting(f)
	_test_tip_rotation_every_five_seconds(f)
	return f


func _advance_until_complete(ls: Control, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if ls.advance(STEP):
			return true
		t += STEP
	return false


func _test_fast_load_holds_five_seconds(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	ls.start(4242, 1.0)   # fast load: the loader is done in 1.0 s
	# not complete before the 5.0 s minimum, even though the load finished at 1.0 s
	while ls.shown_time() < 4.99:
		ls.advance(STEP)
		if ls.is_complete():
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


func _test_simulated_seven_second_load(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
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





func _test_tips_pool_and_weighting(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
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

