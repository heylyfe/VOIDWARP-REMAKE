extends RefCounted
#
# test_run_seed.gd - job J1: level 1 differs every run, and a passed seed still reproduces.
#   1. app.fresh_seed() returns u32 values that are not all the same (the engine RNG is
#      randomized; eight equal draws in a row would mean it is not);
#   2. start_run(seed) in MENU builds exactly the level voidgen gives for that seed (the bot
#      and future multiplayer depend on it): run_seed() == seed and the world's level hash
#      equals voidgen.generate(seed, 1)'s;
#   3. the explicit seed is used once: the next Play (no seed passed) draws a fresh one, and
#      the world it builds is the level for that fresh seed;
#   4. two unpinned Play runs in a row get different seeds.
# This is the ONLY test that runs the fresh-seed path; it asserts properties, never a specific
# level. Every other app test pins its seed with start_run (test_app_flow, test_app_death).

const AppScript := preload("res://app/app.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")

const PINNED_SEED := 60717


func run() -> Array[String]:
	var f: Array[String] = []
	_test_fresh_seed(f)
	_test_pinned_then_fresh(f)
	return f


func _test_fresh_seed(f: Array[String]) -> void:
	var seen: Dictionary = {}
	for i in range(8):
		var s: int = AppScript.fresh_seed()
		if s < 0 or s > 0xFFFFFFFF:
			f.append("fresh_seed returned %d, outside u32" % s)
		seen[s] = 1
	if seen.size() < 2:
		f.append("fresh_seed returned the same value 8 times in a row - it is not fresh")


func _test_pinned_then_fresh(f: Array[String]) -> void:
	var app = AppScript.new()
	app._ready()   # the engine would call this on tree entry; the tree is unavailable here
	if app.state() != "MENU":
		f.append("app starts in %s, want MENU" % app.state())
		app.free()
		return
	# ---- 2. an explicit seed reproduces exactly that level ----
	app.start_run(PINNED_SEED)
	if app.run_seed() != PINNED_SEED:
		f.append("start_run(%d) ran seed %d" % [PINNED_SEED, app.run_seed()])
	var want: String = VoidGenScript.level_hash(VoidGenScript.generate(PINNED_SEED, 1))
	if app._world == null:
		f.append("start_run(%d) built no world" % PINNED_SEED)
	elif VoidGenScript.level_hash(app._world.lv) != want:
		f.append("start_run(%d) built a different level than voidgen.generate(%d, 1)"
				% [PINNED_SEED, PINNED_SEED])
	app._return_to_menu()
	# ---- 3. the next Play draws a fresh seed ----
	app._menu.play_requested.emit()
	var s2: int = app.run_seed()
	if s2 == PINNED_SEED:
		f.append("Play after start_run(%d) reused the pinned seed instead of drawing a fresh one"
				% PINNED_SEED)
	if app._world == null:
		f.append("Play built no world")
	elif VoidGenScript.level_hash(app._world.lv) != VoidGenScript.level_hash(VoidGenScript.generate(s2, 1)):
		f.append("Play's world is not voidgen.generate(run_seed()=%d, 1)" % s2)
	app._return_to_menu()
	# ---- 4. two unpinned Play runs in a row differ (the property only, never a specific level) ----
	app._menu.play_requested.emit()
	var s3: int = app.run_seed()
	if s3 == s2:
		f.append("two Play runs in a row both used seed %d - level 1 did not change" % s2)
	app._return_to_menu()
	app.free()
