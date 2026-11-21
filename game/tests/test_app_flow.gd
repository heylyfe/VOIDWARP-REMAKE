extends RefCounted
#
# APP-FLOW test (headless, no real-time sleeps): the app orchestrator's MENU -> LOADING ->
# WORLD transitions, driven through the loading screen's own advance() clock.
#
#   1. the app starts in MENU (menu created and visible, play/quit wired)
#   2. a simulated play_requested moves it to LOADING (menu hidden, loading screen created,
#      the world built in the same frame and reporting level 1)
#   3. driving advance() moves it to WORLD (loading screen released, world added to the app)
#   4. ESC mid-run opens the PAUSE overlay (gap 1), the run freezes (lstate.tick frozen),
#      ESC again resumes (the world steps again), and ABANDON - the overlay's choice of
#      the old ESC behaviour - returns to MENU (world freed, menu shown again)
#   5. quit_requested is wired (is_connected - emitting it would flag the real tree to quit)
#
# Registered like every other test: extends RefCounted, run() -> Array[String], preloads by
# path (no class_name). The app node is NOT added to the SceneTree: under
# `--headless --script`, Engine.get_main_loop() does not hand the test a usable SceneTree
# (probed: the object answers as a bare Object, `is SceneTree` is false), so the test calls
# _ready() itself and asserts on the node's own wiring (parent/child, visibility, signals)
# instead of tree membership. The real scene instantiation is covered by app.tscn loading
# headless.

const AppScript := preload("res://app/app.gd")
const MenuScript := preload("res://app/menu.gd")   # preload keeps the type check meaningful
const RUN_SEED := 1   # J1: Play draws a fresh seed per run; this test pins one so it is deterministic
const DT := 1.0 / 60.0   # the app's fixed 60 Hz step (the sim's contract)


func run() -> Array[String]:
	var failures: Array[String] = []

	var app = AppScript.new()
	# I4: a test must never ratchet the player's real user://records.json. Point the store at a
	# scratch file before _ready loads it.
	app.records_path = "user://test_app_flow_scratch.json"
	# Before _ready there is no menu, so start_run only stores the seed: step 2 still starts the
	# run through the real play_requested path, on a fixed level.
	app.start_run(RUN_SEED)
	app._ready()   # the engine would call this on tree entry; the tree is unavailable here

	# ---- 1. starts in MENU --------------------------------------------------------------
	if app.state() != "MENU":
		failures.append("app starts in %s, want MENU" % app.state())
	var menu = app._menu
	if menu == null:
		failures.append("menu was not created in _ready")
	else:
		if not menu.visible:
			failures.append("menu not visible in MENU state")
		if not (menu is MenuScript):
			failures.append("menu is not a res://app/menu.gd instance")
		if not menu.play_requested.is_connected(app._on_play_requested):
			failures.append("play_requested is not wired to the app")
		if not menu.quit_requested.is_connected(app._on_quit_requested):
			failures.append("quit_requested is not wired to the app")

	# ---- 2. simulated play_requested -> LOADING ------------------------------------------
	if menu != null:
		menu.play_requested.emit()
	if app.state() != "LOADING":
		failures.append("play_requested moved app to %s, want LOADING" % app.state())
	if app.run_seed() != RUN_SEED:
		failures.append("the run used seed %d, want the pinned %d" % [app.run_seed(), RUN_SEED])
	if menu != null and menu.visible:
		failures.append("menu still visible in LOADING state")
	var loading = app._loading
	if loading == null:
		failures.append("loading screen was not created on play_requested")
	elif loading.is_complete():
		# set_load_progress(1.0) is called right after the world build; is_complete also
		# needs the 5 s hold, so it must be false here.
		failures.append("loading screen reports complete before any advance()")
	var world = app._world
	if world == null:
		failures.append("world was not built in the same frame as the loading screen")
	elif world.level_number() != 1:
		failures.append("world reports level %d, want 1" % world.level_number())

	# ---- 3. drive the loading clock -> WORLD ----------------------------------------------
	# the run waits at the class altar until the player confirms or skips (item 7): SKIP
	if app._class_altar != null and app._class_altar.is_open():
		app._class_altar.skip()
	if loading != null:
		var guard := 0
		while app.state() == "LOADING" and guard < 400:
			loading.advance(0.25)
			guard += 1
		if app.state() != "WORLD":
			failures.append("loading never finished after %d advances (state=%s)"
					% [guard, app.state()])
	if app._loading != null:
		failures.append("loading screen not released after loading_finished")
	if app._world == null:
		failures.append("world missing after loading_finished")
	elif app._world.get_parent() != app:
		failures.append("world not added to the app after loading_finished")

	# ---- 4. ESC mid-run pauses; Resume resumes; Abandon returns to MENU -------------------
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	app._unhandled_input(esc)
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		failures.append("ESC mid-run did not open the pause overlay")
	if not app._paused:
		failures.append("the app is not frozen while the pause overlay is open")
	if app._world == null:
		failures.append("pausing freed the run - a paused run must stay alive")
	else:
		var tick_at_pause: int = int(app._world.lstate.tick)
		app._process(DT)
		app._process(DT)
		if int(app._world.lstate.tick) != tick_at_pause:
			failures.append("the frozen world kept ticking (%d -> %d)"
					% [tick_at_pause, int(app._world.lstate.tick)])
	# ESC again - RESUME: the overlay closes and the run steps again.
	app._unhandled_input(esc)
	if app._paused:
		failures.append("ESC on the open pause overlay did not resume the run")
	if app.state() != "WORLD":
		failures.append("resuming left the app in %s, want WORLD" % app.state())
	if app._world == null:
		failures.append("resuming lost the world")
	else:
		var tick_after_resume: int = int(app._world.lstate.tick)
		app._process(DT)
		if int(app._world.lstate.tick) == tick_after_resume:
			failures.append("the world did not step again after resume")
	# ABANDON - the player's choice of the old ESC behaviour: the run ends, the menu is back.
	app._unhandled_input(esc)
	if app._pause_overlay == null or not app._pause_overlay.is_open():
		failures.append("ESC did not re-open the pause overlay before the abandon")
	app._pause_overlay.abandon_requested.emit()
	if app.state() != "MENU":
		failures.append("abandon left app in %s, want MENU" % app.state())
	if app._world != null:
		failures.append("world not freed on abandon")
	if app._menu == null or not app._menu.visible:
		failures.append("menu not shown again after abandon")
	if app._paused or (app._pause_overlay != null and app._pause_overlay.is_open()):
		failures.append("the pause state survived the abandon")

	# ---- cleanup --------------------------------------------------------------------------
	app.free()
	return failures