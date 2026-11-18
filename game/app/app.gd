extends Node
#
# The app orchestrator (ticket APP-FLOW): MENU -> LOADING -> WORLD, the seam the parallel
# MENU / LOADING tickets plug into. game/app/main.tscn (one Control running menu.gd) is
# superseded by res://app/app.tscn, which project.godot now names as run/main_scene.
#
# Flow:
#   _ready           -> show res://app/menu.gd (a Control), connect play_requested/quit_requested
#   play_requested   -> hide the menu, instantiate res://app/loading_screen.gd, start it
#                       (seed, -1.0, first_launch), THEN add it - add_child runs _ready, whose
#                       bootstrap start(0) would otherwise take a gag pick - connect
#                       loading_finished, build the world THIS frame (world.build(seed, 1)),
#                       then set_load_progress(1.0)
#   _process         -> the loading screen self-drives from its own _process; the app does NOT
#                       call advance() (D-APPFLOW-2, PARKED.md #20)
#   loading_finished -> free the loading screen, add the world, start stepping it
#   world.level_completed -> the app tears the world down (teardown(), then queue_free: the
#                            signal is emitted inside world.step()) and returns to MENU (the
#                            intermission lobby / next-level flow does not exist yet)
#   world.run_over   -> death ends the run (DESIGN.md section 3). The app leaves WORLD so
#                       _process stops stepping the dead world, plays the HUD's 18-tick
#                       death black-out (view/hud/screen_fx.gd), then shows
#                       view/hud/run_over.gd with sim/death.gd's row on blackout_finished.
#                       Retry (like ESC) tears the world down and returns to MENU; a fresh
#                       run starts from there on the same seed.
#   quit_requested   -> get_tree().quit()
#   ESC / the pause binding -> back to MENU from LOADING or WORLD (world/loading freed)
#
# The run seed is start_run(seed)'s argument, else DEFAULT_SEED (1); logged in DECISIONS.md
# D-APPFLOW-1. The loading screen's own _process double-advances when this app also drives
# advance() - spec-literal reading of the ticket, flagged [CONTESTABLE] in D-APPFLOW-2.
#
# public API:
#   func start_run(seed_value: int) -> void   # store the run seed; in MENU this also starts the run
#   func state() -> String                    # "MENU" | "LOADING" | "WORLD" | "RUN_OVER"

const MenuScript := preload("res://app/menu.gd")
const LoadingScreenScript := preload("res://app/loading_screen.gd")
const WorldScript := preload("res://app/world.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")

const DT := 1.0 / 60.0   # fixed 60 Hz sim step (sim/ contract)
const DEFAULT_SEED := 1  # D-APPFLOW-1: fixed default run seed (ticket: "e.g. 1")
const FIRST_LEVEL := 1

const STATE_MENU := "MENU"
const STATE_LOADING := "LOADING"
const STATE_WORLD := "WORLD"
const STATE_RUN_OVER := "RUN_OVER"   # dead: the black-out runs, then the run-over screen

var _state := STATE_MENU
var _seed := DEFAULT_SEED
var _menu: Control = null
var _loading: Control = null
var _world: Node3D = null
var _run_over: Control = null
var _death_info: Dictionary = {}   # sim/death.gd's row for the screen (world.run_over)
var _step_acc := 0.0
var _first_launch := true   # the two-duration law: 5 s on the session's first launch, 2.0 s after
var _pause_codes: Array[int] = []   # KEY_* codes bound to "pause" (data/bindings.json), else ESC


func _ready() -> void:
	_pause_codes = _load_pause_codes()
	_show_menu()


func _process(delta: float) -> void:
	# The loading screen drives its own clock from its own _process (T-024, D-T024-1), so the
	# app must NOT also call advance(): doing both accrues elapsed at 2x and the hold elapses
	# in half the wall time (D-APPFLOW-2, PARKED.md #20). The screen emits loading_finished
	# from inside its own advance(); _on_loading_finished frees it and moves us to WORLD.
	if _state == STATE_WORLD and _world != null:
		# Fixed 60 Hz sim accumulator (the sim's contract), decoupled from the render rate:
		# at 120+ Hz the world must not run 2x fast. Spiral-of-death clamp: 5 ticks/frame.
		_step_acc += delta
		var ticks := 0
		while _step_acc >= DT and ticks < 5:
			_world.step(DT)
			if _world == null:
				break   # the completion handler tore the world down mid-tick
			_step_acc -= DT
			ticks += 1
		if _world == null:
			_step_acc = 0.0
		elif ticks == 5:
			_step_acc = 0.0


# ---- public API -----------------------------------------------------------------------------

## Store the run seed. In MENU this also starts the run (same path as the Play button);
## elsewhere it only changes the seed of the NEXT run. D-APPFLOW-3 [CONTESTABLE].
## The menu has to exist first: before _ready there is none, and a run started that early
## would be orphaned by _ready's _show_menu() (state back to MENU, a live loading screen
## left behind), so an early call degrades to "store the seed".
func start_run(seed_value: int) -> void:
	_seed = seed_value
	if _state == STATE_MENU and _menu != null:
		_begin_run()


func state() -> String:
	return _state


# ---- menu / loading / world transitions -------------------------------------------------------

func _show_menu() -> void:
	if _menu == null:
		_menu = MenuScript.new()
		add_child(_menu)
		_menu.play_requested.connect(_on_play_requested)
		_menu.quit_requested.connect(_on_quit_requested)
	else:
		_menu.show()
	_state = STATE_MENU


func _on_play_requested() -> void:
	_begin_run()


## Hide the menu, show the loading screen, build the world THIS frame, report real progress.
func _begin_run() -> void:
	if _state != STATE_MENU:
		return
	if _menu != null:
		_menu.hide()
	_loading = LoadingScreenScript.new()
	# start() BEFORE add_child: add_child runs _ready, whose bootstrap start(0) would take a gag
	# pick and overwrite the static _last_gag_id, so every restart would replay the same gag
	# (BUG-app-loop-2). start()'s _update_view() is documented safe before _ready.
	_loading.start(_seed, -1.0, _first_launch)
	_first_launch = false
	add_child(_loading)
	_loading.loading_finished.connect(_on_loading_finished)
	_state = STATE_LOADING
	# Build the world in the same frame the loading screen appears (the ticket's contract).
	_world = WorldScript.new()
	_world.level_completed.connect(_on_level_completed)
	_world.run_over.connect(_on_run_over)
	_death_info = {}
	if not _world.build(_seed, FIRST_LEVEL):
		# Generator/content failure: never trap the player on the loading screen.
		push_warning("app: world.build(%d, %d) failed; back to menu" % [_seed, FIRST_LEVEL])
		_loading.free()
		_loading = null
		_world.free()
		_world = null
		_show_menu()
		return
	_loading.set_load_progress(1.0)


func _on_loading_finished() -> void:
	if _loading != null:
		# queue_free, not free(): loading_finished is emitted from inside advance();
		# freeing the screen synchronously would pull the object from under its own
		# call stack. queue_free deletes at idle time, after advance() returns.
		_loading.queue_free()
		_loading = null
	if _world != null:
		add_child(_world)
	_state = STATE_WORLD


func _on_quit_requested() -> void:
	get_tree().quit()


## The world entered its beacon (APP-LOOP). The intermission lobby and the next-level
## flow do not exist in this app yet, so the honest advance is back to the menu - the
## same teardown ESC uses, except that the world is queue_free'd: level_completed is
## emitted from inside world.step(), so a synchronous free would delete the object under
## its own emitting stack (D-APPFLOW-7's queue_free-vs-free rule). _world is nulled NOW,
## so the _process loop's re-check fires and stops stepping it.
func _on_level_completed() -> void:
	if _world == null:
		return
	_world.teardown()
	_world.queue_free()
	_world = null
	_show_menu()


## The player died: DESIGN.md section 3, "Death ends the run". world.step() emitted this
## from inside its own tick, so nothing here frees the world (D-APPFLOW-7: queue_free, not
## free, on a signal emitted from inside the emitter - and the world is still needed).
## Leaving STATE_WORLD is what stops _process from stepping the dead run; the world stays
## in the tree for its own HUD's 18-tick death black-out, and the run-over screen opens on
## blackout_finished (one frame of black on black, seamless: screen_fx holds black).
func _on_run_over(info: Dictionary) -> void:
	if _world == null or _state != STATE_WORLD:
		return
	_death_info = info
	_state = STATE_RUN_OVER
	var hud = _world.hud
	if hud == null:
		_show_run_over()   # no HUD to play the black-out: the screen opens now
		return
	if not hud.blackout_finished.is_connected(_on_blackout_finished):
		hud.blackout_finished.connect(_on_blackout_finished)
	hud.death_blackout()


## The death black-out landed (view/hud/screen_fx.gd, section 2.4): show the run-over row.
func _on_blackout_finished() -> void:
	if _state != STATE_RUN_OVER:
		return
	_show_run_over()


func _show_run_over() -> void:
	if _run_over == null:
		_run_over = RunOverScript.new()
		_run_over.retried.connect(_on_retry_requested)
		add_child(_run_over)   # run_over.gd builds its own layout in _init
	_run_over.show_run_over(_death_info)


## Retry a new run: the same teardown as ESC, then the menu - Play starts the next run on
## the same seed (there is no intermission lobby yet). The screen is queue_free'd, not
## freed: retried is emitted from inside its own Button.
func _on_retry_requested() -> void:
	_return_to_menu()


# ---- pause (ESC / the pause binding) -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if _pause_codes.has(int(key.keycode)):
			_return_to_menu()


## ESC / the pause binding: free the world (and any loading screen), show the menu again.
func _return_to_menu() -> void:
	if _state == STATE_MENU:
		return
	# queue_free: retried is emitted from inside the run-over screen's own Button.
	if _run_over != null:
		_run_over.queue_free()
		_run_over = null
	_death_info = {}
	if _world != null:
		_world.teardown()
		_world.free()
		_world = null
	if _loading != null:
		_loading.free()
		_loading = null
	_show_menu()


func _load_pause_codes() -> Array[int]:
	var codes: Array[int] = [KEY_ESCAPE]
	var res := InputCaptureScript.load_bindings("res://data/bindings.json")
	if (res.get("errors", []) as Array).is_empty():
		var kb: Dictionary = res.get("key_bindings", {})
		var bound: Array = kb.get("pause", [])
		var out: Array[int] = []
		for code in bound:
			var c := int(code)
			if not out.has(c):
				out.append(c)
		if not out.is_empty():
			return out
	return codes