extends Node
#
# The app orchestrator (ticket APP-FLOW): MENU -> LOADING -> WORLD, the seam the parallel
# MENU / LOADING tickets plug into. game/app/main.tscn (one Control running menu.gd) is
# superseded by res://app/app.tscn, which project.godot now names as run/main_scene.
#
# Flow:
#   _ready           -> show res://app/menu.gd (a Control), connect play_requested/quit_requested
#   play_requested   -> hide the menu, instantiate res://app/loading_screen.gd, add it,
#                       start(seed, -1.0), connect loading_finished, build the world THIS
#                       frame (world.build(seed, 1)), then set_load_progress(1.0)
#   _process         -> loading.advance(delta) while in LOADING (the loading screen also
#                       advances itself from its own _process - see D-APPFLOW-2)
#   loading_finished -> free the loading screen, add the world, start stepping it
#   quit_requested   -> get_tree().quit()
#   ESC / the pause binding -> back to MENU from LOADING or WORLD (world/loading freed)
#
# The run seed is start_run(seed)'s argument, else DEFAULT_SEED (1); logged in DECISIONS.md
# D-APPFLOW-1. The loading screen's own _process double-advances when this app also drives
# advance() - spec-literal reading of the ticket, flagged [CONTESTABLE] in D-APPFLOW-2.
#
# public API:
#   func start_run(seed_value: int) -> void   # store the run seed; in MENU this also starts the run
#   func state() -> String                    # "MENU" | "LOADING" | "WORLD"

const MenuScript := preload("res://app/menu.gd")
const LoadingScreenScript := preload("res://app/loading_screen.gd")
const WorldScript := preload("res://app/world.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")

const DT := 1.0 / 60.0   # fixed 60 Hz sim step (sim/ contract)
const DEFAULT_SEED := 1  # D-APPFLOW-1: fixed default run seed (ticket: "e.g. 1")
const FIRST_LEVEL := 1

const STATE_MENU := "MENU"
const STATE_LOADING := "LOADING"
const STATE_WORLD := "WORLD"

var _state := STATE_MENU
var _seed := DEFAULT_SEED
var _menu: Control = null
var _loading: Control = null
var _world: Node3D = null
var _step_acc := 0.0
var _pause_codes: Array[int] = []   # KEY_* codes bound to "pause" (data/bindings.json), else ESC


func _ready() -> void:
	_pause_codes = _load_pause_codes()
	_show_menu()


func _process(delta: float) -> void:
	if _state == STATE_LOADING and _loading != null:
		# The loading screen emits loading_finished from inside advance(); the handler
		# frees _loading and moves us to WORLD.
		_loading.advance(delta)
	elif _state == STATE_WORLD and _world != null:
		# Fixed 60 Hz sim accumulator (the sim's contract), decoupled from the render rate:
		# at 120+ Hz the world must not run 2x fast. Spiral-of-death clamp: 5 ticks/frame.
		_step_acc += delta
		var ticks := 0
		while _step_acc >= DT and ticks < 5:
			_world.step(DT)
			_step_acc -= DT
			ticks += 1
		if ticks == 5:
			_step_acc = 0.0


# ---- public API -----------------------------------------------------------------------------

## Store the run seed. In MENU this also starts the run (same path as the Play button);
## elsewhere it only changes the seed of the NEXT run. D-APPFLOW-3 [CONTESTABLE].
func start_run(seed_value: int) -> void:
	_seed = seed_value
	if _state == STATE_MENU:
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
	add_child(_loading)
	_loading.start(_seed, -1.0)
	_loading.loading_finished.connect(_on_loading_finished)
	_state = STATE_LOADING
	# Build the world in the same frame the loading screen appears (the ticket's contract).
	_world = WorldScript.new()
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